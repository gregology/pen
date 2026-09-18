#!/bin/bash
# tools/testssl.sh/install.sh — version pin, install, and verification for testssl.sh.
set -eux -o pipefail

. /tmp/tool-install-helpers.sh

TESTSSL_VERSION=3.2.4
TESTSSL_SHA256=98528f8a0ac07f1e226efaa8ead438247df8efcb8fee4e056a937ab82a305490

# testssl.sh hard-requires hexdump and only Recommends it, so a
# --no-install-recommends install produces a testssl that cannot start.
apt_install bsdextrautils

fetch "https://github.com/testssl/testssl.sh/archive/refs/tags/v${TESTSSL_VERSION}.tar.gz" \
    "$TESTSSL_SHA256" /tmp/testssl.tar.gz
tar -xzf /tmp/testssl.tar.gz -C /opt
mv "/opt/testssl.sh-${TESTSSL_VERSION}" /opt/testssl.sh
chmod +x /opt/testssl.sh/testssl.sh
ln -s /opt/testssl.sh/testssl.sh /usr/local/bin/testssl.sh
rm -f /tmp/testssl.tar.gz

testssl.sh --version
