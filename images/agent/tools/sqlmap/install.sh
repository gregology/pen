#!/bin/bash
# tools/sqlmap/install.sh — install and verification for sqlmap.
set -eux -o pipefail

. /tmp/tool-install-helpers.sh

apt_install sqlmap

verify_output 'sqlmap' sqlmap --version
