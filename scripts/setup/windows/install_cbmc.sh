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
touch C:\install_log.txt
msiexec /i "$FILE" /qn /norestart /l*! C:\install_log.txt
while [ "$(jobs -r | wc -l)" -gt 0 ]; do
  cat C:\install_log.txt
  echo "waiting for finish..."
  sleep 1
done
export PATH="C:\Program Files\cbmc\bin;$PATH"
cbmc --version
rm $FILE
