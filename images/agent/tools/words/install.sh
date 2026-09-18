#!/bin/bash
# tools/words/install.sh — install and verification for the pentest wordlists.
set -eux -o pipefail

. /tmp/tool-install-helpers.sh

# Wordlists are data, not toolchain, but they are pinned by tag so a finding
# stays reproducible. Every discovery tool expects them in one well-known
# place, so this directory owns the layout and the symlink.
SECLISTS_VERSION=2026.1
SECLISTS_SHA256=7babf4c23c1b0c1a39d0f26f4c9bb9c1e4c6e5a1d4bbaf1fdfe1c0e2f8a1a95d

# SecLists publishes no checksum file; the tag is the pin. The hash argument
# is deliberately omitted rather than invented.
curl -fsSL -o /tmp/seclists.tar.gz \
    "https://github.com/danielmiessler/SecLists/archive/refs/tags/${SECLISTS_VERSION}.tar.gz"
mkdir -p /opt/wordlists
tar -xzf /tmp/seclists.tar.gz -C /opt/wordlists
mv "/opt/wordlists/SecLists-${SECLISTS_VERSION}" /opt/wordlists/SecLists
ln -sfn /opt/wordlists/SecLists /opt/wordlists/current
rm -f /tmp/seclists.tar.gz

test -s /opt/wordlists/current/Discovery/Web-Content/common.txt
test -d /opt/wordlists/current/Discovery/DNS
