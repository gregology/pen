#!/bin/bash
# tools/whatweb/install.sh — install and verification for whatweb.
set -eux -o pipefail

. /tmp/tool-install-helpers.sh

# bookworm ships 0.5.5 against upstream 0.6.x, so flags from the current
# upstream README (--no-cookies, --output-sync, --output-buffer-size) do not
# exist here, and the package omits upstream's plugins-disabled/ directory.
apt_install whatweb

verify_output 'whatweb' whatweb --version
