#!/bin/bash
# tools/gowitness/install.sh — version pin, install, and verification for gowitness.
set -eux -o pipefail

. /tmp/tool-install-helpers.sh

GOWITNESS_VERSION=3.2.0
GOWITNESS_SHA256=d315bf505691ea64a87f6231a757acfee0a94c024ab3531f35b3c52dad15895e

# The asset name carries the version and platform; the binary inside does not,
# so this cannot use install_bins. Statically linked Go.
fetch "https://github.com/sensepost/gowitness/releases/download/${GOWITNESS_VERSION}/gowitness-${GOWITNESS_VERSION}-linux-amd64" \
    "$GOWITNESS_SHA256" /tmp/gowitness
install -m 0755 /tmp/gowitness /usr/local/bin/gowitness
rm -f /tmp/gowitness

# gowitness screenshots through its own Chrome, not the Playwright build in
# tools/browser/ (it wants a `chrome` binary path, and the headless shell is
# not one). Left to download its own copy on first use, which is the one
# runtime browser download that remains; see AGENTS.md.
verify_output 'gowitness' gowitness version
