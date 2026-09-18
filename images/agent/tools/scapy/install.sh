#!/bin/bash
# tools/scapy/install.sh — version pin, install, and verification for scapy.
set -eux -o pipefail

. /tmp/tool-install-helpers.sh

SCAPY_VERSION=2.7.0
SCAPY_VENV=/opt/venvs/scapy

# Own venv rather than the apt python3-scapy package: bookworm ships 2.5.0
# against upstream 2.7.0, and a system dist-packages install is importable
# only under /usr/bin/python3, which makes it invisible to every other tool.
#
# The optional extras stay out: `scapy[all]` pulls ipython, pyx, cryptography
# and matplotlib, and every documented use imports the library directly.
python3 -m venv "$SCAPY_VENV"
"$SCAPY_VENV/bin/pip" install --no-cache-dir --upgrade pip
"$SCAPY_VENV/bin/pip" install --no-cache-dir "scapy==${SCAPY_VERSION}"

# scapy ships a console script of its own (`scapy = scapy.main:interact`), so
# expose_venv puts the REPL on PATH next to the interpreter. Scripts use the
# interpreter: /opt/venvs/scapy/bin/python3.
expose_venv "$SCAPY_VENV"
test -x /usr/local/bin/scapy
verify_output '2.7.0' "$SCAPY_VENV/bin/python3" -c \
    'from scapy.all import conf; print("scapy", conf.version)'
