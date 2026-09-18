#!/bin/bash
# tools/hydra/install.sh — install and verification for hydra.
set -eux -o pipefail

. /tmp/tool-install-helpers.sh

apt_install hydra

# `hydra -h` prints its banner and then exits 255 — hydra's own choice, not a
# failure. Two shell hazards to avoid here, both of which silently broke this
# check on a real build: piping into `head` gives hydra SIGPIPE, and with
# `set -o pipefail` even a matching `grep` reports the pipeline's status as
# hydra's, so `$?` cannot be used as the match result. Capture, then grep the
# captured text — the grep's own exit status is the reliable signal.
hydra -h > /tmp/hydra-help.txt 2>&1 || true
if ! grep -q 'Hydra v' /tmp/hydra-help.txt; then
    echo "hydra did not print its banner" >&2
    exit 1
fi
rm -f /tmp/hydra-help.txt
