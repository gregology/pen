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
verify_output '0.6.13' pypykatz version

# The `smb` command group is imported inside a try/except in __main__.py, so a
# broken aiosmb or dependency leaves the subcommand silently absent and visible
# only as a string on startup. Importing the module directly tests the same
# code path without going through the CLI. The module is `pypykatz.smb` —
# there is no `pypykatz.commands` package, which a first attempt assumed.
verify_output 'smb module loads' "$PYPYKATZ_VENV/bin/python3" -c \
    'import pypykatz.smb; print("smb module loads")'

# Deliberately NOT verified with `pypykatz smb client help`: on Python 3.11 that
# reaches a runtime bug in pypykatz's own argument parsing (SMBCMDArgs has no
# `decode`), which fails the build for a defect in the tool rather than in this
# script. The docs record it instead.
