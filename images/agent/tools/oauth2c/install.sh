#!/bin/bash
# tools/oauth2c/install.sh — version pin, install, and verification for oauth2c.
set -eux -o pipefail

. /tmp/tool-install-helpers.sh

OAUTH2C_VERSION=1.21.0
OAUTH2C_SHA256=8761e0b04dfb3599afc5911b06ef27c94c21873c45b1fd97beebc45ce4ed0a6d

# Static Go binary: no libc dependency to track, which is why this is a
# pinned upstream release rather than a package.
fetch "https://github.com/SecureAuthCorp/oauth2c/releases/download/v${OAUTH2C_VERSION}/oauth2c_${OAUTH2C_VERSION}_Linux_x86_64.tar.gz" \
    "$OAUTH2C_SHA256" /tmp/oauth2c.tar.gz
unpack /tmp/oauth2c.tar.gz /tmp/unpack
install_bins /tmp/unpack oauth2c
rm -f /tmp/oauth2c.tar.gz
rm -rf /tmp/unpack

verify_output 'oauth2c version' oauth2c version
