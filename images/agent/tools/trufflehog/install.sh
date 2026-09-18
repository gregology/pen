#!/bin/bash
# tools/trufflehog/install.sh — version pin, install, and verification for trufflehog.
set -eux -o pipefail

. /tmp/tool-install-helpers.sh

TRUFFLEHOG_VERSION=3.97.5
TRUFFLEHOG_SHA256=e3d97199c565c37ca6152750197f667e08ae6a1edf5911fbdec168622b28620c

fetch "https://github.com/trufflesecurity/trufflehog/releases/download/v${TRUFFLEHOG_VERSION}/trufflehog_${TRUFFLEHOG_VERSION}_linux_amd64.tar.gz" \
    "$TRUFFLEHOG_SHA256" /tmp/trufflehog.tar.gz
unpack /tmp/trufflehog.tar.gz /tmp/unpack
install_bins /tmp/unpack trufflehog
rm -f /tmp/trufflehog.tar.gz
rm -rf /tmp/unpack

trufflehog --version
