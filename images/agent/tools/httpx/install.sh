#!/bin/bash
# tools/httpx/install.sh — version pin, install, and verification for httpx.
set -eux -o pipefail

. /tmp/tool-install-helpers.sh

HTTPX_VERSION=1.12.0
HTTPX_SHA256=9d8439e8b6c9aa7d1e2314817a392e00d5178da3af5652f7475f88868f418f76

fetch "https://github.com/projectdiscovery/httpx/releases/download/v${HTTPX_VERSION}/httpx_${HTTPX_VERSION}_linux_amd64.zip" \
    "$HTTPX_SHA256" /tmp/httpx.zip
unpack /tmp/httpx.zip /tmp/unpack
install_bins /tmp/unpack httpx
rm -f /tmp/httpx.zip
rm -rf /tmp/unpack

httpx -version
