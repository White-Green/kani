#!/bin/bash
# Copyright Kani Contributors
# SPDX-License-Identifier: Apache-2.0 OR MIT

# Windows environment dependencies setup
echo "Setting up Windows CI environment..."

# Source kani-dependencies to get versions
source kani-dependencies

# Install dependencies using Chocolatey
# GitHub Actions Windows runner has choco pre-installed
# Use -y to bypass prompts
choco install -y cbmc --version ${CBMC_VERSION}
choco install -y z3
choco install -y cmake
choco install -y unzip

# Install cvc5 (no choco package for version 1.3.0)
ARCH="Win64"
CVC5_VERSION="1.3.0"
CVC5_URL="https://github.com/cvc5/cvc5/releases/download/cvc5-${CVC5_VERSION}/cvc5-${ARCH}-static.zip"
curl -L --remote-name "${CVC5_URL}"
unzip -o -j "cvc5-${ARCH}-static.zip" "cvc5-${ARCH}-static/bin/cvc5.exe"
# Put cvc5.exe in a location that's likely in the PATH, or we'll need to add it
mkdir -p /usr/local/bin
mv cvc5.exe /usr/local/bin/
rm "cvc5-${ARCH}-static.zip"
# Add paths to GITHUB_PATH if running in CI
if [[ -n "${GITHUB_PATH:-}" ]]; then
  echo "C:\ProgramData\chocolatey\bin" >> "$GITHUB_PATH"
  echo "C:\Program Files\CBMC\bin" >> "$GITHUB_PATH"
  echo "/usr/local/bin" >> "$GITHUB_PATH"
fi
/usr/local/bin/cvc5.exe --version

# Kissat is currently skipped for Windows as it requires a complex build setup
# or a specific Windows port.
echo "Warning: Kissat installation skipped for Windows"
