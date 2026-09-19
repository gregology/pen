#!/bin/bash
# tools/schemathesis/install.sh — version pin, install, and verification for schemathesis.
set -eux -o pipefail

. /tmp/tool-install-helpers.sh

SCHEMATHESIS_VERSION=4.27.4
SCHEMATHESIS_VENV=/opt/venvs/schemathesis

python3 -m venv "$SCHEMATHESIS_VENV"
"$SCHEMATHESIS_VENV/bin/pip" install --no-cache-dir --upgrade pip
"$SCHEMATHESIS_VENV/bin/pip" install --no-cache-dir "schemathesis==${SCHEMATHESIS_VERSION}"

# `st` is schemathesis' own alias for the same console script; expose only the
# full name and leave the short one unlinked, so a two-letter name that could
# mean anything is not silently bound on PATH.
expose_venv_only "$SCHEMATHESIS_VENV" schemathesis

verify_output 'schemathesis, version' schemathesis --version
