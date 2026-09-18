#!/bin/bash
# tools/impacket/install.sh — install and verification for impacket.
set -eux -o pipefail

. /tmp/tool-install-helpers.sh

IMPACKET_VENV=/opt/venvs/impacket

# impacket has no version pin on purpose. NetExec depends on an unreleased
# impacket revision (0.14.0.dev0), and in a shared environment pip cannot
# satisfy both that and a release pin in one resolution. In its own venv the
# conflict disappears, so this is free to track the current release.
python3 -m venv "$IMPACKET_VENV"
"$IMPACKET_VENV/bin/pip" install --no-cache-dir --upgrade pip
"$IMPACKET_VENV/bin/pip" install --no-cache-dir impacket

expose_venv "$IMPACKET_VENV"
# impacket's console scripts are named after the example files (`secretsdump.py`),
# not with an `impacket-` prefix. Check the name that actually gets installed.
test -x /usr/local/bin/secretsdump.py
"$IMPACKET_VENV/bin/python3" -c 'import impacket; print(impacket.__version__)'
