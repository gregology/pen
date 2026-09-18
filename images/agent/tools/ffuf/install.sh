#!/bin/bash
# tools/ffuf/install.sh — version pin, install, and verification for ffuf.
set -eux -o pipefail

. /tmp/tool-install-helpers.sh

FFUF_VERSION=2.3.0
FFUF_SHA256=b2a3c725fcb9da175159682f54d6e9149f2905b00d84d155e7efc5d599975ceb

fetch "https://github.com/ffuf/ffuf/releases/download/v${FFUF_VERSION}/ffuf_${FFUF_VERSION}_linux_amd64.tar.gz" \
    "$FFUF_SHA256" /tmp/ffuf.tar.gz
unpack /tmp/ffuf.tar.gz /tmp/unpack
install_bins /tmp/unpack ffuf
rm -f /tmp/ffuf.tar.gz
rm -rf /tmp/unpack

ffuf -V
