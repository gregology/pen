#!/bin/bash
# tools/feroxbuster/install.sh — version pin, install, and verification for feroxbuster.
set -eux -o pipefail

. /tmp/tool-install-helpers.sh

FEROXBUSTER_VERSION=2.13.1
FEROXBUSTER_SHA256=0978619a10049ccaad290b2d1241bc4d8a6aac18da07d6231186fb9d343f99de

fetch "https://github.com/epi052/feroxbuster/releases/download/v${FEROXBUSTER_VERSION}/x86_64-linux-feroxbuster.zip" \
    "$FEROXBUSTER_SHA256" /tmp/feroxbuster.zip
unpack /tmp/feroxbuster.zip /tmp/unpack
install_bins /tmp/unpack feroxbuster
rm -f /tmp/feroxbuster.zip
rm -rf /tmp/unpack

verify_output '2.13.1' feroxbuster --version
