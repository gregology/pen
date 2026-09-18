#!/bin/bash
# tools/wafw00f/install.sh — version pin, install, and verification for wafw00f.
set -eux -o pipefail

. /tmp/tool-install-helpers.sh

WAFFW00F_VERSION=2.4.2
WAFFW00F_VENV=/opt/venvs/wafw00f

# 2.4.2 requires Python >= 3.10; the base image provides 3.11.
python3 -m venv "$WAFFW00F_VENV"
"$WAFFW00F_VENV/bin/pip" install --no-cache-dir --upgrade pip
"$WAFFW00F_VENV/bin/pip" install --no-cache-dir "wafw00f==${WAFFW00F_VERSION}"

expose_venv "$WAFFW00F_VENV"
wafw00f --version
