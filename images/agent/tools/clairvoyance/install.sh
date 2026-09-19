#!/bin/bash
# tools/clairvoyance/install.sh — version pin, install, and verification for clairvoyance.
set -eux -o pipefail

. /tmp/tool-install-helpers.sh

CLAIRVOYANCE_VERSION=2.5.5
CLAIRVOYANCE_SHA256=e6586fe349bad442c56f6c546b9f8638f72e4bf6bc0140d7b8922f81ece0f186
CLAIRVOYANCE_VENV=/opt/venvs/clairvoyance

# A real package with a console-script entry point, but not published on PyPI,
# so pip installs it from the pinned source tree.
fetch "https://github.com/nikitastupin/clairvoyance/archive/refs/tags/v${CLAIRVOYANCE_VERSION}.tar.gz" \
    "$CLAIRVOYANCE_SHA256" /tmp/clairvoyance.tar.gz
tar -xzf /tmp/clairvoyance.tar.gz -C /opt
mv "/opt/clairvoyance-${CLAIRVOYANCE_VERSION}" /opt/clairvoyance
rm -f /tmp/clairvoyance.tar.gz

# pyproject.toml is poetry-shaped and has no [build-system], so pip cannot
# build it in an isolated environment; --no-build-isolation lets poetry-core
# (installed just below) do the metadata work against this venv.
python3 -m venv "$CLAIRVOYANCE_VENV"
"$CLAIRVOYANCE_VENV/bin/pip" install --no-cache-dir --upgrade pip
"$CLAIRVOYANCE_VENV/bin/pip" install --no-cache-dir poetry-core
"$CLAIRVOYANCE_VENV/bin/pip" install --no-cache-dir --no-build-isolation \
    /opt/clairvoyance

expose_venv_only "$CLAIRVOYANCE_VENV" clairvoyance

verify_output 'clairvoyance' clairvoyance --help
