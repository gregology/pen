#!/bin/bash
# tools/dirb/install.sh — install and verification for dirb.
set -eux -o pipefail

. /tmp/tool-install-helpers.sh

# Legacy, installed for its wordlists rather than as a discovery tool: dirb is
# single-threaded, unmaintained since 2.22 (the Debian man page is dated 2009),
# has no machine-readable output, and leaves TLS verification off by default.
# gobuster, ffuf and feroxbuster supersede it for everything except the
# server-specific wordlists under /usr/share/dirb/wordlists/vulns/.
apt_install dirb

# The wordlists are the reason this package is here; prove they arrived.
test -d /usr/share/dirb/wordlists/vulns
test -s /usr/share/dirb/wordlists/common.txt
"$(command -v dirb)" 2>&1 | head -2 || true
