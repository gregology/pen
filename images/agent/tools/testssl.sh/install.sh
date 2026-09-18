#!/bin/bash
# tools/testssl.sh/install.sh — version pin, install, and verification for testssl.sh.
set -eux -o pipefail

. /tmp/tool-install-helpers.sh

TESTSSL_VERSION=3.2.4
TESTSSL_SHA256=98528f8a0ac07f1e226efaa8ead438247df8efcb8fee4e056a937ab82a305490

# Two dependencies testssl.sh needs and Debian only Recommends, so a
# --no-install-recommends install produces a testssl that cannot do its job:
#
#   hexdump — checked before argument parsing, so even --version dies.
#   a resolver — check_resolver_bins() is unconditional and aborts the run
#     with exit 249 unless one of dig, host, drill or nslookup is present.
#     bind9-dnsutils supplies the first three.
apt_install bsdextrautils bind9-dnsutils

fetch "https://github.com/testssl/testssl.sh/archive/refs/tags/v${TESTSSL_VERSION}.tar.gz" \
    "$TESTSSL_SHA256" /tmp/testssl.tar.gz
tar -xzf /tmp/testssl.tar.gz -C /opt
mv "/opt/testssl.sh-${TESTSSL_VERSION}" /opt/testssl.sh
chmod +x /opt/testssl.sh/testssl.sh
ln -s /opt/testssl.sh/testssl.sh /usr/local/bin/testssl.sh
rm -f /tmp/testssl.tar.gz

verify_output '3.2.4' testssl.sh --version

# The resolver failure only shows up once a scan starts, so assert the binaries
# here rather than trusting --version to have proven the tool usable.
for binary in dig host nslookup; do
    command -v "$binary" > /dev/null
done
