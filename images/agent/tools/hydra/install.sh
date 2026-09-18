#!/bin/bash
# tools/hydra/install.sh — install and verification for hydra.
set -eux -o pipefail

. /tmp/tool-install-helpers.sh

apt_install hydra

hydra -h 2>&1 | head -1
