#!/bin/bash
# tools/dnsx/install.sh — version pin, install, and verification for dnsx.
set -eux -o pipefail

. /tmp/tool-install-helpers.sh

DNSX_VERSION=1.3.1
DNSX_SHA256=438b964653056dd51dcfe614b1a16f8bced3cc48a1d27bc07cc6fdf2ef2a9533

fetch "https://github.com/projectdiscovery/dnsx/releases/download/v${DNSX_VERSION}/dnsx_${DNSX_VERSION}_linux_amd64.zip" \
    "$DNSX_SHA256" /tmp/dnsx.zip
unpack /tmp/dnsx.zip /tmp/unpack
install_bins /tmp/unpack dnsx
rm -f /tmp/dnsx.zip
rm -rf /tmp/unpack

verify_output 'dnsx' dnsx -version
