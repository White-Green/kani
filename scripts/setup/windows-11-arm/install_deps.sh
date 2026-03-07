#!/bin/bash
# Copyright Kani Contributors
# SPDX-License-Identifier: Apache-2.0 OR MIT

set -euo pipefail

# Windows ARM environment dependencies setup
echo "Setting up Windows ARM CI environment..."

# Source kani-dependencies to get versions
source kani-dependencies

echo "Installing Z3..."
choco install -y z3 --no-progress || { echo "Z3 installation failed"; exit 1; }
echo "Installing CMake..."
# On Windows ARM runners, the MSI-based cmake.install dependency can fail with
# generic MSI errors (1603). Use the portable package to avoid MSI.
choco install -y cmake.portable --no-progress || { echo "CMake portable installation failed"; exit 1; }
echo "Installing winflexbison..."
choco install -y winflexbison3 --no-progress || { echo "winflexbison installation failed"; exit 1; }
if ! command -v bison >/dev/null 2>&1 && command -v win_bison >/dev/null 2>&1; then
  powershell.exe -NoProfile -NonInteractive -Command "\
    \$wb = (Get-Command win_bison.exe -ErrorAction Stop).Source; \
    \$dst = Join-Path (Split-Path \$wb -Parent) 'bison.exe'; \
    Copy-Item -Path \$wb -Destination \$dst -Force"
fi
if ! command -v flex >/dev/null 2>&1 && command -v win_flex >/dev/null 2>&1; then
  powershell.exe -NoProfile -NonInteractive -Command "\
    \$wf = (Get-Command win_flex.exe -ErrorAction Stop).Source; \
    \$dst = Join-Path (Split-Path \$wf -Parent) 'flex.exe'; \
    Copy-Item -Path \$wf -Destination \$dst -Force"
fi

install_cbmc_from_msi() {
  echo "Installing CBMC from MSI..."
  local cbmc_installer="cbmc-${CBMC_VERSION}-win64.msi"
  local cbmc_url="https://github.com/diffblue/cbmc/releases/download/cbmc-${CBMC_VERSION}/${cbmc_installer}"
  curl -L --remote-name "${cbmc_url}"
  local cbmc_installer_win
  cbmc_installer_win="$(cygpath -w "$(pwd)/${cbmc_installer}")"
  local msi_log_win="${RUNNER_TEMP:-${TEMP:-C:\\Windows\\Temp}}\\cbmc-install.log"
  local msi_log_msys
  msi_log_msys="$(cygpath -u "${msi_log_win}")"
  mkdir -p "$(dirname "${msi_log_msys}")"
  echo "Installing ${cbmc_installer} silently (log: ${msi_log_win})..."

  run_msi() {
    local log_file="$1"
    set +e
    if [[ -n "${log_file}" ]]; then
      powershell.exe -NoProfile -NonInteractive -Command "\
        \$p = Start-Process -FilePath 'msiexec.exe' -ArgumentList @('/i','${cbmc_installer_win}','/qn','/norestart','/l*v','${log_file}') -Wait -PassThru; \
        exit \$p.ExitCode"
    else
      powershell.exe -NoProfile -NonInteractive -Command "\
        \$p = Start-Process -FilePath 'msiexec.exe' -ArgumentList @('/i','${cbmc_installer_win}','/qn','/norestart') -Wait -PassThru; \
        exit \$p.ExitCode"
    fi
    local exit_code=$?
    set -e
    return ${exit_code}
  }

  set +e
  run_msi "${msi_log_win}"
  local msi_exit_code=$?
  if [[ ${msi_exit_code} -eq 86 ]]; then
    echo "Warning: Failed to open MSI log file (${msi_log_win}). Retrying without /l*v..."
    run_msi ""
    msi_exit_code=$?
  fi
  if [[ ${msi_exit_code} -ne 0 ]]; then
    echo "CBMC MSI installation failed with exit code ${msi_exit_code}"
    if [[ -f "${msi_log_msys}" ]]; then
      echo "--- Begin ${msi_log_win} (tail) ---"
      tail -n 200 "${msi_log_msys}" || true
      echo "--- End ${msi_log_win} (tail) ---"
    fi
    exit ${msi_exit_code}
  fi
  set -e
  rm "${cbmc_installer}"

  local cbmc_bin_dir_win="C:\\Program Files\\CBMC\\bin"
  local cbmc_bin_dir_msys
  cbmc_bin_dir_msys="$(cygpath -u "${cbmc_bin_dir_win}")"
  if [[ -d "${cbmc_bin_dir_msys}" ]]; then
    export PATH="${cbmc_bin_dir_msys}:$PATH"
  fi
}

install_cbmc_from_source() {
  echo "Installing CBMC from source..."
  local build_type="${CBMC_SOURCE_CMAKE_BUILD_TYPE:-RelWithDebInfo}"
  local sat_impl="${CBMC_SOURCE_SAT_IMPL:-minisat2;cadical}"
  local work_dir
  work_dir="$(mktemp -d)"

  git clone --branch "cbmc-${CBMC_VERSION}" --depth 1 https://github.com/diffblue/cbmc "${work_dir}"
  pushd "${work_dir}"
  git submodule update --init

  # Build x64 binaries; Windows ARM executes them via emulation.
  CXXFLAGS="${CBMC_SOURCE_CXXFLAGS:--Zi /Oy-}" cmake -S . -B build \
    -G "Visual Studio 17 2022" -A x64 \
    -DWITH_JBMC=OFF \
    -Dsat_impl="${sat_impl}"
  cmake --build build --config "${build_type}" --parallel

  local cbmc_exe_msys
  cbmc_exe_msys="$(find build -type f -path "*/${build_type}/cbmc.exe" | head -n 1)"
  if [[ -z "${cbmc_exe_msys}" ]]; then
    echo "CBMC executable not found for configuration ${build_type}"
    exit 1
  fi

  local cbmc_bin_msys
  cbmc_bin_msys="$(dirname "${cbmc_exe_msys}")"
  if [[ ! -d "${cbmc_bin_msys}" ]]; then
    echo "CBMC bin directory not found: ${cbmc_bin_msys}"
    exit 1
  fi

  export PATH="${cbmc_bin_msys}:$PATH"
  if [[ -n "${GITHUB_PATH:-}" ]]; then
    echo "$(cygpath -w "${cbmc_bin_msys}")" >> "$GITHUB_PATH"
  fi

  popd
}

if [[ "${CBMC_BUILD_FROM_SOURCE:-0}" == "1" ]]; then
  install_cbmc_from_source
else
  install_cbmc_from_msi
fi

# cvc5 - we'll try the x64 binary for now as there's no native Windows ARM64 binary.
ARCH="Win64-x86_64"
CVC5_VERSION="1.3.0"
CVC5_URL="https://github.com/cvc5/cvc5/releases/download/cvc5-${CVC5_VERSION}/cvc5-${ARCH}-static.zip"
curl -L --remote-name "${CVC5_URL}"
# Put binaries in a location that's likely in the PATH, or we'll need to add it
mkdir -p /usr/local/bin
unzip -o -j "cvc5-${ARCH}-static.zip" "cvc5-${ARCH}-static/bin/cvc5.exe" -d /usr/local/bin
rm "cvc5-${ARCH}-static.zip"
# Add paths to GITHUB_PATH if running in CI
if [[ -n "${GITHUB_PATH:-}" ]]; then
  echo "C:\\ProgramData\\chocolatey\\bin" >> "$GITHUB_PATH"
  if [[ "${CBMC_BUILD_FROM_SOURCE:-0}" != "1" ]]; then
    echo "C:\\Program Files\\CBMC\\bin" >> "$GITHUB_PATH"
  fi
  echo "C:\\msys64\\usr\\local\\bin" >> "$GITHUB_PATH"
  echo "Successfully updated GITHUB_PATH"
fi
/usr/local/bin/cvc5.exe --version
cbmc.exe --version
where cbmc.exe || echo "cbmc.exe not found in PATH"
where goto-cc.exe || echo "goto-cc.exe not found in PATH"
where goto-cl.exe || echo "goto-cl.exe not found in PATH"
where cl.exe || echo "cl.exe not found in PATH"

# Some Windows CBMC packages expose `goto-cl.exe` instead of `goto-cc.exe`.
if ! command -v goto-cc >/dev/null 2>&1 && command -v goto-cl >/dev/null 2>&1; then
  powershell.exe -NoProfile -NonInteractive -Command "\
    \$gotoCl = (Get-Command goto-cl.exe -ErrorAction Stop).Source; \
    \$gotoCc = Join-Path (Split-Path \$gotoCl -Parent) 'goto-cc.exe'; \
    Copy-Item -Path \$gotoCl -Destination \$gotoCc -Force; \
    Write-Host 'Created goto-cc.exe at' \$gotoCc"
fi


# Ensure Visual C++ compiler is available for CBMC preprocessing.
CL_DIR_WIN="$(powershell.exe -NoProfile -NonInteractive -Command "\
  \$cmd = Get-Command cl.exe -ErrorAction SilentlyContinue; \
  if (\$cmd) { Split-Path \$cmd.Source -Parent; exit 0 }; \
  \$vswhere = Join-Path \${env:ProgramFiles(x86)} 'Microsoft Visual Studio\\Installer\\vswhere.exe'; \
  if (-not (Test-Path \$vswhere)) { exit 0 }; \
  \$installPath = & \$vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath; \
  if (-not \$installPath) { exit 0 }; \
  \$cl = Get-ChildItem -Path (Join-Path \$installPath 'VC\\Tools\\MSVC') -Recurse -Filter cl.exe -ErrorAction SilentlyContinue \
    | Where-Object { \$_.FullName -match '\\\\bin\\\\Hostx64\\\\x64\\\\cl.exe$' } \
    | Select-Object -First 1; \
  if (\$cl) { Split-Path \$cl.FullName -Parent }")"
if [[ -n "${CL_DIR_WIN}" ]]; then
  CL_DIR_MSYS="$(cygpath -u "${CL_DIR_WIN}")"
  export PATH="${CL_DIR_MSYS}:$PATH"
  if [[ -n "${GITHUB_PATH:-}" ]]; then
    echo "${CL_DIR_WIN}" >> "$GITHUB_PATH"
  fi
  echo "Configured cl.exe from ${CL_DIR_WIN}"
else
  echo "Warning: could not locate cl.exe path automatically"
fi
where cl.exe || echo "cl.exe not found in PATH after configuration"
# Kissat is currently skipped for Windows ARM
echo "Warning: Kissat installation skipped for Windows ARM"

