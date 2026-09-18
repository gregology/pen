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

# Allowlist, not skip list. netexec's venv provides 134 console scripts: its own
# two wrappers plus everything its dependency tree drags in — utility binaries
# (flask, tabulate, tqdm, pygmentize), other tools' packages (httpx, pypykatz,
# certipy, dploot), and a second copy of impacket's example scripts. Exporting
# all of it would both clutter PATH and silently rebind names other tools own,
# with install order deciding the winner.
#
# Verified on host01 before this fix: /usr/local/bin/httpx pointed at
# /opt/venvs/netexec/bin/httpx, so the agent's `httpx` was a Python HTTP client
# that rejected `-version`; and secretsdump.py resolved to netexec's impacket
# 0.14.0.dev0 while the impacket tool installs 0.13.1, so the documented version
# was not the one that ran.
expose_venv_only "$NETEXEC_VENV" nxc netexec nxcdb
test -x /usr/local/bin/nxc
"$NETEXEC_VENV/bin/pip" check
verify_output '1.5.1' nxc --version
