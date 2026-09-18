#!/bin/bash
# tools/naabu/install.sh — version pin, install, and verification for naabu.
set -eux -o pipefail

. /tmp/tool-install-helpers.sh

NAABU_VERSION=2.6.1
NAABU_SHA256=018c4c9884dea971eda860435ede3021d1150732f34cfd245498c6726d8cab90

fetch "https://github.com/projectdiscovery/naabu/releases/download/v${NAABU_VERSION}/naabu_${NAABU_VERSION}_linux_amd64.zip" \
    "$NAABU_SHA256" /tmp/naabu.zip
unpack /tmp/naabu.zip /tmp/unpack
install_bins /tmp/unpack naabu
rm -f /tmp/naabu.zip
rm -rf /tmp/unpack

naabu -version
