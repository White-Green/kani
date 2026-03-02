#!/bin/bash
# Copyright Kani Contributors
# SPDX-License-Identifier: Apache-2.0 OR MIT

# Windows ARM environment dependencies setup
echo "Setting up Windows ARM CI environment..."

# Source kani-dependencies to get versions
source kani-dependencies

# Chocolatey and major tools might not have native ARM64 versions easily available.
# We'll try to use available x64 binaries which Windows 11 ARM can run.
# Note: cbmc and z3 choco packages might be x64 but should run under emulation.
echo "Installing CBMC..."
choco install -y cbmc --version ${CBMC_VERSION} --no-progress
echo "Installing Z3..."
choco install -y z3 --no-progress
echo "Installing CMake..."
choco install -y cmake --no-progress
echo "Installing Unzip..."
choco install -y unzip --no-progress

# cvc5 - we'll try the x64 binary for now as there's no native Windows ARM64 binary.
ARCH="Win64"
CVC5_VERSION="1.3.0"
CVC5_URL="https://github.com/cvc5/cvc5/releases/download/cvc5-${CVC5_VERSION}/cvc5-${ARCH}-static.zip"
curl -L --remote-name "${CVC5_URL}"
unzip -o -j "cvc5-${ARCH}-static.zip" "cvc5-${ARCH}-static/bin/cvc5.exe"
mkdir -p /usr/local/bin
mv cvc5.exe /usr/local/bin/
rm "cvc5-${ARCH}-static.zip"
# Add paths to GITHUB_PATH if running in CI
if [[ -n "${GITHUB_PATH:-}" ]]; then
  echo "C:\ProgramData\chocolatey\bin" >> "$GITHUB_PATH"
  echo "C:\Program Files\CBMC\bin" >> "$GITHUB_PATH"
  echo "/usr/local/bin" >> "$GITHUB_PATH"
  echo "Successfully updated GITHUB_PATH"
fi
/usr/local/bin/cvc5.exe --version
ls -l "C:\Program Files\CBMC\bin\cbmc.exe" || echo "cbmc.exe not found in expected location"

# Kissat is currently skipped for Windows ARM
echo "Warning: Kissat installation skipped for Windows ARM"
