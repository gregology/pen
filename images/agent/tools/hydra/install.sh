#!/bin/bash
# tools/hydra/install.sh — install and verification for hydra.
set -eux -o pipefail

. /tmp/tool-install-helpers.sh

apt_install hydra

# Capture before truncating: piping straight into `head` closes the pipe early,
# the tool dies on SIGPIPE, and `set -o pipefail` reports that as the build's
# exit status even though the tool works.
hydra -h 2>&1 | grep -m1 'Hydra v'
