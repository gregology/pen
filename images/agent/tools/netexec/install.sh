#!/bin/bash
# tools/netexec/install.sh — version pin, install, and verification for netexec.
set -eux -o pipefail

. /tmp/tool-install-helpers.sh

NETEXEC_VERSION=v1.5.1
NETEXEC_VENV=/opt/venvs/netexec

python3 -m venv "$NETEXEC_VENV"
"$NETEXEC_VENV/bin/pip" install --no-cache-dir --upgrade pip

# dploot is pinned below 4: netexec declares `dploot>=3.1.0` with no upper
# bound, and dploot 4 moved its SMB module, so an unpinned install produces a
# netexec whose SMB protocol dies at import with ModuleNotFoundError. The
# version banner still prints, so only a real run reveals it.
#
# aardwolf is pinned below 0.2.14 for a different reason: 0.2.14 is sdists only,
# and its Rust build fails without a rustc/cargo toolchain, which this image
# deliberately does not carry. 0.2.13 ships a manylinux wheel, so the install
# stays a download rather than a compile.
"$NETEXEC_VENV/bin/pip" install --no-cache-dir \
    "dploot<4" \
    "aardwolf<0.2.14" \
    "git+https://github.com/Pennyw0rth/NetExec@${NETEXEC_VERSION}"

expose_venv "$NETEXEC_VENV"
test -x /usr/local/bin/nxc
"$NETEXEC_VENV/bin/pip" check
nxc --version
