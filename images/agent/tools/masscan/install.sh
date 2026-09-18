#!/bin/bash
# tools/masscan/install.sh — install and verification for masscan.
set -eux -o pipefail

. /tmp/tool-install-helpers.sh

# The Debian package is a plain 0755 binary with no setuid bit and no file
# capabilities, and masscan performs no privilege check of its own: it asks
# libpcap for an AF_PACKET socket, which the kernel gates on CAP_NET_RAW. The
# agent runs as root by design, so no capability needs granting here.
apt_install masscan

# No `| head` here: truncating masscan's output kills it with SIGPIPE, which
# `set -o pipefail` then reports as a failed build.
masscan --version 2>&1 | grep -m1 'Masscan version'
