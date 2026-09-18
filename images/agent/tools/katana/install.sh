#!/bin/bash
# tools/katana/install.sh — version pin, install, and verification for katana.
set -eux -o pipefail

. /tmp/tool-install-helpers.sh

KATANA_VERSION=1.7.0
KATANA_SHA256=fe1142d92f418549338ea46d67a472124878482e225d279e9a42700c75d76a4d

# katana -hl and httpx screenshots download a Chromium build (go-rod) at runtime
# and fail to launch it without these: Debian slim ships none of the shared
# libraries Chromium links against. Installing them here keeps a
# runtime-downloaded browser able to render — the "silently returns zero
# endpoints" failure they prevent is worse than the image cost.
apt_install \
    libnss3 libnspr4 libatk1.0-0 libatk-bridge2.0-0 libatspi2.0-0 \
    libcups2 libgbm1 libxkbcommon0 libxcomposite1 libxdamage1 \
    libxrandr2 libxfixes3 libpango-1.0-0 libcairo2 libasound2

fetch "https://github.com/projectdiscovery/katana/releases/download/v${KATANA_VERSION}/katana_${KATANA_VERSION}_linux_amd64.zip" \
    "$KATANA_SHA256" /tmp/katana.zip
unpack /tmp/katana.zip /tmp/unpack
install_bins /tmp/unpack katana
rm -f /tmp/katana.zip
rm -rf /tmp/unpack

verify_output '1.7.0' katana -version
