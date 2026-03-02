#!/bin/bash
# Copyright Kani Contributors
# SPDX-License-Identifier: Apache-2.0 OR MIT

set -euo pipefail

# Windows ARM environment dependencies setup
echo "Setting up Windows ARM CI environment..."

# Source kani-dependencies to get versions
source kani-dependencies

# Chocolatey and major tools might not have native ARM64 versions easily available.
# We'll try to use available x64 binaries which Windows 11 ARM can run.
# Note: cbmc and z3 choco packages might be x64 but should run under emulation.
# Install CBMC using GitHub release (using x64 binary for emulation)
echo "Installing CBMC..."
CBMC_INSTALLER="cbmc-${CBMC_VERSION}-win64.msi"
CBMC_URL="https://github.com/diffblue/cbmc/releases/download/cbmc-${CBMC_VERSION}/${CBMC_INSTALLER}"
curl -L --remote-name "${CBMC_URL}"
MSI_LOG="cbmc-install.log"
echo "Installing ${CBMC_INSTALLER} silently (log: ${MSI_LOG})..."
cmd.exe //c "msiexec /i \"${CBMC_INSTALLER}\" /qn /norestart /l*v \"${MSI_LOG}\""
MSI_EXIT_CODE=$?
if [[ ${MSI_EXIT_CODE} -ne 0 ]]; then
  echo "CBMC MSI installation failed with exit code ${MSI_EXIT_CODE}"
  if [[ -f "${MSI_LOG}" ]]; then
    echo "--- Begin ${MSI_LOG} (tail) ---"
    tail -n 200 "${MSI_LOG}" || true
    echo "--- End ${MSI_LOG} (tail) ---"
  fi
  exit ${MSI_EXIT_CODE}
fi
rm "${CBMC_INSTALLER}"

echo "Installing Z3..."
choco install -y z3 --no-progress || { echo "Z3 installation failed"; exit 1; }
echo "Installing CMake..."
choco install -y cmake --no-progress || { echo "CMake installation failed"; exit 1; }

# cvc5 - we'll try the x64 binary for now as there's no native Windows ARM64 binary.
ARCH="Win64"
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
  echo "C:\\msys64\\usr\\local\\bin" >> "$GITHUB_PATH"
  echo "Successfully updated GITHUB_PATH"
fi
/usr/local/bin/cvc5.exe --version
/usr/local/bin/cbmc.exe --version
where cbmc.exe || echo "cbmc.exe not found in PATH"

# Kissat is currently skipped for Windows ARM
echo "Warning: Kissat installation skipped for Windows ARM"
