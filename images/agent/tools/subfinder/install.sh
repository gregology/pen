#!/bin/bash
# tools/subfinder/install.sh — version pin, install, and verification for subfinder.
set -eux -o pipefail

. /tmp/tool-install-helpers.sh

SUBFINDER_VERSION=2.16.0
SUBFINDER_SHA256=1b7f9c608e9a5bd59e609a5e09710d63c5485e92d3d49dc2c16eb4fdbe10cb60

fetch "https://github.com/projectdiscovery/subfinder/releases/download/v${SUBFINDER_VERSION}/subfinder_${SUBFINDER_VERSION}_linux_amd64.zip" \
    "$SUBFINDER_SHA256" /tmp/subfinder.zip
unpack /tmp/subfinder.zip /tmp/unpack
install_bins /tmp/unpack subfinder
rm -f /tmp/subfinder.zip
rm -rf /tmp/unpack

subfinder -version
