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
MSYS_NO_PATHCONV=1 msiexec /i "$FILE" /qn /norestart /l* installer_log.txt
cat installer_log.txt
export PATH="/c/Program Files/cbmc/bin:$PATH"
echo "/c/Program Files/cbmc/bin" >> $GITHUB_PATH
cbmc --version
rm $FILE
