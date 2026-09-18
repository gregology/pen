#!/bin/bash
# tools/hydra/install.sh — install and verification for hydra.
set -eux -o pipefail

. /tmp/tool-install-helpers.sh

apt_install hydra

# `hydra -h` prints its banner and then exits 255 — hydra's own choice, not a
# failure, and exactly why verify_output captures before grepping.
verify_output 'Hydra v' hydra -h
