#!/bin/bash
# tools/tshark/install.sh — install and verification for tshark.
set -eux -o pipefail

. /tmp/tool-install-helpers.sh

# bookworm's tshark is current; apt is the cheaper path than a source build.
apt_install tshark

verify_output '4.0.17' tshark --version
