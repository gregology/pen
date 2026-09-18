#!/bin/bash
# tools/arjun/install.sh — version pin, install, and verification for arjun.
set -eux -o pipefail

. /tmp/tool-install-helpers.sh

ARJUN_VERSION=2.2.7
ARJUN_VENV=/opt/venvs/arjun

# Its own venv: arjun is unaffected by, and cannot affect, the pins that
# other Python tools need. Parameter wordlists ship inside the package.
python3 -m venv "$ARJUN_VENV"
"$ARJUN_VENV/bin/pip" install --no-cache-dir --upgrade pip
"$ARJUN_VENV/bin/pip" install --no-cache-dir "arjun==${ARJUN_VERSION}"

expose_venv "$ARJUN_VENV"
verify_output 'usage: arjun' arjun --help
test -s "$ARJUN_VENV"/lib/python*/site-packages/arjun/db/large.txt
