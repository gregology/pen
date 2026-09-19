#!/bin/bash
# tools/websocat/install.sh — version pin, install, and verification for websocat.
set -eux -o pipefail

. /tmp/tool-install-helpers.sh

WEBSOCAT_VERSION=1.14.1
WEBSOCAT_SHA256=66f8dd3a0394761556339117f8bb5123bddefd44e087af2a72ec22b0bd08d514

# The musl build: statically linked, so it does not add a glibc version
# dependency to the image.
fetch "https://github.com/vi/websocat/releases/download/v${WEBSOCAT_VERSION}/websocat.x86_64-unknown-linux-musl" \
    "$WEBSOCAT_SHA256" /tmp/websocat
install -m 0755 /tmp/websocat /usr/local/bin/websocat
rm -f /tmp/websocat

verify_output 'websocat 1.14.1' websocat --version
