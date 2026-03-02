#!/usr/bin/env bash
# Copyright Kani Contributors
# SPDX-License-Identifier: Apache-2.0 OR MIT
#
# Runs `rustfmt` in our source crates and tests.
# The arguments given to this script are passed to rustfmt.
set -o errexit
set -o pipefail
set -o nounset

# Run from the repository root folder
ROOT_FOLDER=$(git rev-parse --show-toplevel)
cd ${ROOT_FOLDER}

# Parse arguments to check for --check flag
check_flag=""
for arg in "$@"; do
  if [ "$arg" = "--check" ]; then
    check_flag="--check"
    break
  fi
done

# Verify crates.
error=0

# Check all crates. Only fail at the end.
cargo fmt ${check_flag} || error=1

# Check test source files.
TESTS=("tests" "docs/src/tutorial")
# Add ignore patterns for code we don't want to format.
IGNORE=("*/perf/s2n-quic/*")

# Arguments for the find command for excluding the IGNORE paths
IGNORE_ARGS=()
for ignore in "${IGNORE[@]}"; do
    IGNORE_ARGS+=(-not -path "$ignore")
done

for suite in "${TESTS[@]}"; do
    # Note: We set the configuration file here because some submodules have
    # their own configuration file.
    # Run rustfmt file-by-file to avoid hitting command-line length limits on
    # Windows runners.
    while IFS= read -r -d '' file; do
        rustfmt --config-path rustfmt.toml ${check_flag} "$file" || error=1
    done < <(find "${suite}" -name "*.rs" ${IGNORE_ARGS[@]} -print0)
done

exit $error
