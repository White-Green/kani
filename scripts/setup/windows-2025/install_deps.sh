#!/bin/bash
# Copyright Kani Contributors
# SPDX-License-Identifier: Apache-2.0 OR MIT

set -euo pipefail

# Windows environment dependencies setup
echo "Setting up Windows CI environment..."

# Source kani-dependencies to get versions
source kani-dependencies

# Install dependencies using Chocolatey
# GitHub Actions Windows runner has choco pre-installed
# Use -y to bypass prompts
# Install CBMC using GitHub release
echo "Installing CBMC..."
CBMC_ARCH="win64"
CBMC_URL="https://github.com/diffblue/cbmc/releases/download/cbmc-${CBMC_VERSION}/cbmc-v${CBMC_VERSION}-${CBMC_ARCH}.zip"
curl -L --remote-name "${CBMC_URL}"
unzip -o -j "cbmc-v${CBMC_VERSION}-${CBMC_ARCH}.zip" "*/bin/*.exe" -d /usr/local/bin
rm "cbmc-v${CBMC_VERSION}-${CBMC_ARCH}.zip"

echo "Installing Z3..."
choco install -y z3 --no-progress || { echo "Z3 installation failed"; exit 1; }
echo "Installing CMake..."
choco install -y cmake --no-progress || { echo "CMake installation failed"; exit 1; }

# Install cvc5 (no choco package for version 1.3.0)
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

# Kissat is currently skipped for Windows as it requires a complex build setup
# or a specific Windows port.
echo "Warning: Kissat installation skipped for Windows"
