#!/bin/bash
# Copyright Kani Contributors
# SPDX-License-Identifier: Apache-2.0 OR MIT

set -eu

# Source kani-dependencies to get CBMC_VERSION
source kani-dependencies

if [ -z "${CBMC_VERSION:-}" ]; then
  echo "$0: Error: CBMC_VERSION is not specified"
  exit 1
fi

FILE="cbmc-${CBMC_VERSION}-win64.msi"
URL="https://github.com/diffblue/cbmc/releases/download/cbmc-${CBMC_VERSION}/$FILE"

set -x

curl -L -o "$FILE" "$URL"
touch install_log
msiexec /i "$FILE" /passive /quiet /qn /norestart /l*! install_log &
while [ "$(jobs -r | wc -l)" -gt 0 ]; do
  tail -n 10 install_log
  echo "waiting for finish..."
  sleep 1
done
export PATH="C:\Program Files\cbmc\bin;$PATH"
cbmc --version
rm $FILE
