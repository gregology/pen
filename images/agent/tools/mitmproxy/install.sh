#!/bin/bash
# tools/mitmproxy/install.sh — version pin, install, and verification for mitmproxy.
set -eux -o pipefail

. /tmp/tool-install-helpers.sh

MITMPROXY_VERSION=11.0.0
MITMPROXY_VENV=/opt/venvs/mitmproxy

# Pinned to 11.0.0 because 11.1.0 and later require Python >= 3.12 and the
# base image is bookworm (Python 3.11).
#
# bcrypt is held below 4.1: passlib 1.7.4 (a mitmproxy transitive dependency)
# probes its bcrypt backend with a >72-byte password, and bcrypt 4.1+ raises
# instead of truncating, which makes every mitmproxy entry point exit at
# import time.
python3 -m venv "$MITMPROXY_VENV"
"$MITMPROXY_VENV/bin/pip" install --no-cache-dir --upgrade pip
"$MITMPROXY_VENV/bin/pip" install --no-cache-dir \
    "mitmproxy==${MITMPROXY_VERSION}" \
    "bcrypt<4.1"

expose_venv "$MITMPROXY_VENV"
test -x /usr/local/bin/mitmdump
verify_output '11.0.0' mitmdump --version
