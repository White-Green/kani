#!/bin/bash
# Copyright Kani Contributors
# SPDX-License-Identifier: Apache-2.0 OR MIT

set -eu

# Source kani-dependencies to get KISSAT_VERSION
source kani-dependencies

if [ -z "${KISSAT_VERSION:-}" ]; then
  echo "$0: Error: KISSAT_VERSION is not specified"
  exit 1
fi

# Check if the correct Kissat version is already installed
if command -v kissat > /dev/null; then
  if kissat_version=$(kissat --version); then
    if [[ $kissat_version == $KISSAT_VERSION ]]; then
      # Already installed
      exit 0
    else
      echo "Warning: Overriding Kissat version ${kissat_version} with ${KISSAT_VERSION}"
    fi
  fi
fi

set -x

# Clone Kissat repository with the specified version tag
git clone --depth 1 --branch "rel-${KISSAT_VERSION}" https://github.com/arminbiere/kissat.git "kissat-rel-${KISSAT_VERSION}"
DIR_NAME="kissat-rel-${KISSAT_VERSION}"
cd $DIR_NAME
./configure --safe && make kissat && sudo install build/kissat /usr/local/bin
cd -

# Clean up on success
rm $FILE
rm -rf $DIR_NAME
