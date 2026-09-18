#!/bin/bash
# tools/trivy/install.sh — version pin, install, and verification for trivy.
set -eux -o pipefail

. /tmp/tool-install-helpers.sh

TRIVY_VERSION=0.74.0
TRIVY_SHA256=cf1e32ec8d4d8823e023096a28cadb14f5b5123ce03f201fb633c5b76aa712dd

# Upstream .deb, so its own dependencies are resolved by apt.
fetch "https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/trivy_${TRIVY_VERSION}_Linux-64bit.deb" \
    "$TRIVY_SHA256" /tmp/trivy.deb
apt-get update
apt-get install -y --no-install-recommends /tmp/trivy.deb
rm -f /tmp/trivy.deb
rm -rf /var/lib/apt/lists/*

verify_output 'trivy' trivy --version
