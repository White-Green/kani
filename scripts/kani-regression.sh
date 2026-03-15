#!/usr/bin/env bash
# Copyright Kani Contributors
# SPDX-License-Identifier: Apache-2.0 OR MIT

if [[ -z $KANI_REGRESSION_KEEP_GOING ]]; then
  set -o errexit
fi
set -o pipefail
set -o nounset

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
export PATH=$SCRIPT_DIR:$PATH
EXTRA_X_PY_BUILD_ARGS="${EXTRA_X_PY_BUILD_ARGS:-}"
KANI_DIR=$SCRIPT_DIR/..

# This variable forces an error when there is a mismatch on the expected
# descriptions from cbmc checks.
# TODO: We should add a more robust mechanism to detect python unexpected behavior.
export KANI_FAIL_ON_UNEXPECTED_DESCRIPTION="true"

# Gather dependencies version from top `kani-dependencies` file.
source "${KANI_DIR}/kani-dependencies"
# Sanity check dependencies values.
[[ "${CBMC_MAJOR}.${CBMC_MINOR}" == "${CBMC_VERSION%.*}" ]] || \
    (echo "Conflicting CBMC versions"; exit 1)
# Check if installed versions are correct.
echo "OSTYPE is: $OSTYPE"
if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "win32" ]]; then
  echo "Running on Windows ($OSTYPE)"
  # On Windows, python3 might not be in the path, but python is
  PYTHON_BIN=$(command -v python3 || command -v python || echo "python")
  echo "Using python: $PYTHON_BIN"
  $PYTHON_BIN "${SCRIPT_DIR}/check-cbmc-version.py" --major "${CBMC_MAJOR}" --minor "${CBMC_MINOR}"
else
  check-cbmc-version.py --major "${CBMC_MAJOR}" --minor "${CBMC_MINOR}"
fi
if [[ "$OSTYPE" != "msys" && "$OSTYPE" != "win32" ]]; then
  check_kissat_version.sh
else
  echo "Warning: Kissat version check skipped on Windows"
  # Work around Windows CBMC temp-file collisions by avoiding test parallelism.
  export RUST_TEST_THREADS=1
fi

# Formatting check
echo "Running Formatting check..."
${SCRIPT_DIR}/kani-fmt.sh --check

# Build kani
echo "Building Kani..."
cargo build-dev

# Unit tests
echo "Running Unit tests..."
cargo test -p cprover_bindings
cargo test -p kani-compiler
cargo test -p kani-driver
cargo test -p kani_metadata
# Use concrete playback to enable assertions failure
echo "Running kani crate tests..."
cargo test -p kani --features concrete_playback
# Test the actual macros, skipping doc tests and enabling extra traits for "syn"
# so we can debug print AST
echo "Running kani_macros tests..."
RUSTFLAGS=--cfg=kani_sysroot cargo test -p kani_macros --features syn/extra-traits --lib

# Declare testing suite information (suite and mode)
TESTS=(
    "kani kani"
    "expected expected"
    "ui expected"
    "std-checks cargo-kani"
    "firecracker kani"
    "prusti kani"
    "smack kani"
    "cargo-kani cargo-kani"
    "cargo-ui cargo-kani"
    "script-based-pre exec"
    "coverage coverage-based"
    "cargo-coverage cargo-coverage"
    "kani-docs cargo-kani"
    "kani-fixme kani-fixme"
)

WINDOWS_SKIPPED_SUITES=(
  "expected"
  "std-checks"
  "ui"
  "firecracker"
  "prusti"
  "smack"
)

is_windows=false
if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "win32" ]]; then
  is_windows=true
fi
WINDOWS_SUITE_FILTER="${KANI_WINDOWS_SUITE_FILTER:-}"
WINDOWS_COMPILETEST_FILTER="${KANI_WINDOWS_COMPILETEST_FILTER:-}"
WINDOWS_HEARTBEAT_INTERVAL_SEC="${KANI_WINDOWS_REGRESSION_HEARTBEAT_SEC:-60}"
WINDOWS_HEARTBEAT_PID=""

windows_dump_regression_processes() {
  powershell.exe -NoProfile -NonInteractive -Command "
    \$ErrorActionPreference = 'SilentlyContinue'
    \$namePattern = 'cargo|rustc|kani|cbmc|goto|z3|cvc5|cl|link|mspdbsrv'
    \$procs = Get-Process |
      Where-Object { \$_.ProcessName -match \$namePattern } |
      Sort-Object CPU -Descending |
      Select-Object -First 16 ProcessName, Id, CPU, @{Name='WSMB';Expression={[math]::Round(\$_.WorkingSet64 / 1MB, 1)}}, StartTime
    if (\$procs) {
      \$procs | Format-Table -AutoSize | Out-String -Width 220 | Write-Host
      \$pidList = \$procs | Select-Object -ExpandProperty Id
      \$cmds = Get-CimInstance Win32_Process |
        Where-Object { \$pidList -contains \$_.ProcessId } |
        Select-Object ProcessId, ParentProcessId, Name, CommandLine
      if (\$cmds) {
        Write-Host 'Command lines:'
        \$cmds | Format-Table -AutoSize | Out-String -Width 260 | Write-Host
      }
    } else {
      Write-Host 'No matching regression processes found.'
    }
  " || true
}

windows_collect_timeout_artifacts() {
  local suite="$1"
  local mode="$2"
  local dump_dir_msys="${RUNNER_TEMP:-/tmp}/kani-timeout-dumps"
  mkdir -p "${dump_dir_msys}"

  echo "Collecting timeout diagnostics for suite=${suite} mode=${mode}"
  echo "Timeout dump directory: ${dump_dir_msys}"

  powershell.exe -NoProfile -NonInteractive -Command "
    \$ErrorActionPreference = 'SilentlyContinue'
    Get-CimInstance Win32_Process |
      Where-Object { \$_.Name -match 'cargo|rustc|kani-driver|goto-instrument|cbmc|goto' } |
      Select-Object ProcessId, ParentProcessId, Name, CreationDate, CommandLine |
      Format-Table -AutoSize | Out-String -Width 260 | Write-Host
  " || true

  local procdump_bin=""
  if command -v procdump64 >/dev/null 2>&1; then
    procdump_bin="procdump64"
  elif command -v procdump >/dev/null 2>&1; then
    procdump_bin="procdump"
  fi

  if [[ -n "${procdump_bin}" ]]; then
    echo "Using ${procdump_bin} for timeout dumps"
    mapfile -t dump_pids < <(powershell.exe -NoProfile -NonInteractive -Command "
      \$ErrorActionPreference = 'SilentlyContinue'
      Get-Process |
        Where-Object { \$_.ProcessName -in @('goto-instrument','kani-driver') } |
        Select-Object -ExpandProperty Id
    " | tr -d '\r' | sed '/^$/d')

    for pid in "${dump_pids[@]}"; do
      local dump_path="${dump_dir_msys}/proc-${pid}.dmp"
      echo "Capturing dump for pid=${pid} -> ${dump_path}"
      timeout --foreground 30 "${procdump_bin}" -accepteula -ma "${pid}" "${dump_path}" || true
    done
  else
    echo "procdump not found; skipping dump file generation."
  fi
}
windows_start_regression_heartbeat() {
  local suite="$1"
  local mode="$2"
  (
    while true; do
      echo "[windows-regression-heartbeat] suite=${suite} mode=${mode} time=$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
      windows_dump_regression_processes
      sleep "${WINDOWS_HEARTBEAT_INTERVAL_SEC}"
    done
  ) &
  WINDOWS_HEARTBEAT_PID=$!
}

windows_stop_regression_heartbeat() {
  if [[ -n "${WINDOWS_HEARTBEAT_PID}" ]] && kill -0 "${WINDOWS_HEARTBEAT_PID}" >/dev/null 2>&1; then
    kill "${WINDOWS_HEARTBEAT_PID}" >/dev/null 2>&1 || true
    wait "${WINDOWS_HEARTBEAT_PID}" 2>/dev/null || true
  fi
  WINDOWS_HEARTBEAT_PID=""
}



# Build compiletest and print configuration. We pick suite / mode combo so there's no test.
echo "--- Compiletest configuration"
cargo run -p compiletest --quiet -- --suite kani --mode cargo-kani --dry-run --verbose
echo "-----------------------------"

# Build `kani-cov`
echo "Building kani-cov..."
cargo build -p kani-cov

# Extract testing suite information and run compiletest
for testp in "${TESTS[@]}"; do
  testl=($testp)
  suite=${testl[0]}
  mode=${testl[1]}

  if [[ "${is_windows}" == "true" ]]; then
    if [[ -n "${WINDOWS_SUITE_FILTER}" ]]; then
      SUITE_ALLOWED=false
      IFS=',' read -ra SUITE_FILTERS <<< "${WINDOWS_SUITE_FILTER}"
      for allowed_suite in "${SUITE_FILTERS[@]}"; do
        if [[ "${suite}" == "${allowed_suite}" ]]; then
          SUITE_ALLOWED=true
          break
        fi
      done
      if [[ "${SUITE_ALLOWED}" != "true" ]]; then
        echo "Skipping compiletest suite=$suite mode=$mode due to KANI_WINDOWS_SUITE_FILTER=${WINDOWS_SUITE_FILTER}"
        continue
      fi
    fi
    if [[ " ${WINDOWS_SKIPPED_SUITES[*]} " == *" ${suite} "* ]]; then
      echo "Skipping compiletest suite=$suite mode=$mode on Windows"
      continue
    fi
    echo "Check compiletest suite=$suite mode=$mode"
    WINDOWS_COMPILETEST_ARGS=(--no-fail-fast --timeout 5400)
    if [[ "${KANI_WINDOWS_COMPILETEST_VERBOSE:-0}" == "1" ]]; then
      WINDOWS_COMPILETEST_ARGS+=(--verbose)
    fi
    WINDOWS_COMPILETEST_FILTERS=()
    if [[ -n "${WINDOWS_COMPILETEST_FILTER}" ]]; then
      IFS=',' read -ra WINDOWS_COMPILETEST_FILTERS <<< "${WINDOWS_COMPILETEST_FILTER}"
      echo "Using compiletest filter(s): ${WINDOWS_COMPILETEST_FILTER}"
    fi
    WINDOWS_COMPILETEST_WALLCLOCK_TIMEOUT="${KANI_WINDOWS_COMPILETEST_WALLCLOCK_TIMEOUT:-1800}"
    if [[ -n "${KANI_REGRESSION_SOLVER:-}" ]]; then
      WINDOWS_COMPILETEST_ARGS+=(--kani-flag=--solver --kani-flag="${KANI_REGRESSION_SOLVER}")
    fi
    if [[ -n "${KANI_REGRESSION_OBJECT_BITS:-}" ]]; then
      WINDOWS_COMPILETEST_ARGS+=(
        --kani-flag=--object-bits
        --kani-flag="${KANI_REGRESSION_OBJECT_BITS}"
      )
    fi
    if [[ "$suite" == "std-checks" ]]; then
      WINDOWS_COMPILETEST_ARGS+=(--kani-flag=--verbose)
      WINDOWS_COMPILETEST_ARGS+=(--kani-flag=--no-undefined-function-checks)
      WINDOWS_COMPILETEST_ARGS+=(--kani-flag=--jobs --kani-flag=1)
      export KANI_WINDOWS_GOTO_INSTRUMENT_TIMEOUT_SECS="${KANI_WINDOWS_GOTO_INSTRUMENT_TIMEOUT_SECS:-30}"
      export KANI_WINDOWS_GOTO_INSTRUMENT_TRACE="${KANI_WINDOWS_GOTO_INSTRUMENT_TRACE:-1}"
      export KANI_WINDOWS_SKIP_ENFORCE_CONTRACT="${KANI_WINDOWS_SKIP_ENFORCE_CONTRACT:-1}"
    fi
    windows_start_regression_heartbeat "$suite" "$mode"
    set +e
    if command -v timeout >/dev/null 2>&1; then
      timeout --foreground "${WINDOWS_COMPILETEST_WALLCLOCK_TIMEOUT}" \
        cargo run -p compiletest --quiet -- --suite "$suite" --mode "$mode" \
        "${WINDOWS_COMPILETEST_FILTERS[@]}" \
        "${WINDOWS_COMPILETEST_ARGS[@]}"
      compiletest_exit=$?
    else
      cargo run -p compiletest --quiet -- --suite "$suite" --mode "$mode" \
        "${WINDOWS_COMPILETEST_FILTERS[@]}" \
        "${WINDOWS_COMPILETEST_ARGS[@]}"
      compiletest_exit=$?
    fi
    set -e
    windows_stop_regression_heartbeat
    if [[ ${compiletest_exit} -ne 0 ]]; then
      if [[ ${compiletest_exit} -eq 124 ]]; then
        echo "Compiletest suite=$suite mode=$mode hit wall-clock timeout (${WINDOWS_COMPILETEST_WALLCLOCK_TIMEOUT}s)"
        windows_collect_timeout_artifacts "$suite" "$mode"
      else
        echo "Compiletest suite=$suite mode=$mode failed with exit code ${compiletest_exit}"
      fi
      windows_dump_regression_processes
      exit ${compiletest_exit}
    fi
  else
    echo "Check compiletest suite=$suite mode=$mode"
    cargo run -p compiletest --quiet -- --suite $suite --mode $mode \
        --quiet --no-fail-fast
  fi
done

if [[ "${is_windows}" == "true" ]]; then
  echo "Skipping firecracker codegen regression on Windows."
else
  # We rarely benefit from re-using build artifacts in the firecracker test,
  # and we often end up with incompatible leftover artifacts:
  # "error[E0514]: found crate `serde_derive` compiled by an incompatible version of rustc"
  # So if we're calling the full regression suite, wipe out old artifacts.
  if [ -d "$KANI_DIR/firecracker/build" ]; then
    rm -rf "$KANI_DIR/firecracker/build"
  fi

  # Check codegen of firecracker
  echo "Checking codegen of firecracker..."
  time "$SCRIPT_DIR"/codegen-firecracker.sh
fi

# Test for --manifest-path which we cannot do through compiletest.
# It should just successfully find the project and specified proof harness. (Then clean up.)
echo "Testing --manifest-path..."
FEATURES_MANIFEST_PATH="$KANI_DIR/tests/cargo-kani/cargo-features-flag/Cargo.toml"
MANIFEST_PATH_ARGS=()
if [[ -n "${KANI_REGRESSION_SOLVER:-}" ]]; then
  MANIFEST_PATH_ARGS+=(--solver "${KANI_REGRESSION_SOLVER}")
fi
"${SCRIPT_DIR}/cargo-kani" --manifest-path "$FEATURES_MANIFEST_PATH" --harness trivial_success "${MANIFEST_PATH_ARGS[@]}"
cargo clean --manifest-path "$FEATURES_MANIFEST_PATH"

# Build all packages in the workspace and ensure no warning is emitted.
# Please don't replace `cargo build-dev` above with this command.
# Setting RUSTFLAGS like this always resets cargo's build cache resulting in
# all tests to be re-run. I.e., cannot keep re-runing the regression from where
# we stopped.
# Only run with the `cprover` feature to avoid compiling the `charon` library
# which is not our code and may have warnings. The downside is that we wouldn't
# detect any warnings in the charon code path. TODO: Remove
# `--no-default-features --features cprover` when the warnings in charon are
# fixed and we advance the charon pin to that version
echo "Final build with warnings check..."
RUSTFLAGS="-D warnings" cargo build --target-dir /tmp/kani_build_warnings --no-default-features --features cprover

echo
echo "All Kani regression tests completed successfully."
echo
