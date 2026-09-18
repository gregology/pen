#!/bin/bash
# tools/dalfox/install.sh — version pin, install, and verification for dalfox.
set -eux -o pipefail

. /tmp/tool-install-helpers.sh

DALFOX_VERSION=3.2.3
DALFOX_SHA256=6f4c68b01c13d6eb2fded1a14827701651451b9225c679a70689ec2dcaab231f

# The upstream .deb carries its own dependencies, so it installs with apt
# rather than a dpkg that would leave the package database inconsistent.
fetch "https://github.com/hahwul/dalfox/releases/download/v${DALFOX_VERSION}/dalfox-v${DALFOX_VERSION}-linux-x86_64.deb" \
    "$DALFOX_SHA256" /tmp/dalfox.deb
apt-get update
apt-get install -y --no-install-recommends /tmp/dalfox.deb
rm -f /tmp/dalfox.deb
rm -rf /var/lib/apt/lists/*

# `dalfox version` is NOT a version command: dalfox parses the bare word as a
# target URL, attempts to scan http://version/, fails DNS, and exits 2. The
# flag form is the one that prints and exits cleanly.
dalfox --version
