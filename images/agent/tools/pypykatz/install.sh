#!/bin/bash
# tools/pypykatz/install.sh — version pin, install, and verification for pypykatz.
set -eux -o pipefail

. /tmp/tool-install-helpers.sh

PYPYKATZ_VERSION=0.6.13
PYPYKATZ_VENV=/opt/venvs/pypykatz

python3 -m venv "$PYPYKATZ_VENV"
"$PYPYKATZ_VENV/bin/pip" install --no-cache-dir --upgrade pip
"$PYPYKATZ_VENV/bin/pip" install --no-cache-dir "pypykatz==${PYPYKATZ_VERSION}"

expose_venv "$PYPYKATZ_VENV"
pypykatz version

# The `smb` command group is imported inside a try/except in __main__.py: if
# aiosmb or its dependencies are broken, the subcommand is silently absent and
# only appears as a string on startup. Prove it exists rather than trusting
# that the install succeeded.
pypykatz smb client help >/dev/null
