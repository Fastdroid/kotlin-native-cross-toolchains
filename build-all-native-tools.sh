#!/bin/bash
set -e
cd "$(dirname "$0")"
source config

./build-mingw-tools.sh
./build-wabt.sh
./build-wamrc.sh
