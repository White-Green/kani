#!/bin/bash
# Copyright Kani Contributors
# SPDX-License-Identifier: Apache-2.0 OR MIT

set -eu

mkdir /c/kissat
KISSAT_DIR="/c/kissat"
curl -L -o "$KISSAT_DIR/kissat.exe" "https://github.com/sfiruch/kissat/releases/download/rel-4.0.0/kissat.exe"
echo $KISSAT_DIR >> $GITHUB_PATH
