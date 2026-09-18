#!/bin/bash
# tools/nuclei/install.sh — version pin, install, and verification for nuclei.
set -eux -o pipefail

. /tmp/tool-install-helpers.sh

NUCLEI_VERSION=3.11.1
NUCLEI_SHA256=ea63d4ae232808cd7c6bc00d0142428e231fab59dae01042246097d195835ab6
NUCLEI_TEMPLATES_VERSION=10.4.9
NUCLEI_TEMPLATES_SHA256=d7cd989935f9a84943cba8a193f567db37626dbf4e526ff57ba5b1f24badd5d6

fetch "https://github.com/projectdiscovery/nuclei/releases/download/v${NUCLEI_VERSION}/nuclei_${NUCLEI_VERSION}_linux_amd64.zip" \
    "$NUCLEI_SHA256" /tmp/nuclei.zip
unpack /tmp/nuclei.zip /tmp/unpack
install_bins /tmp/unpack nuclei

# The scanner is inert without templates, and `nuclei -update-templates` is not
# usable at build time (a self-update path needing a writable template dir and
# a GitHub release to exist). Fetching the archive directly means a build either
# produces a working scanner or fails loudly.
fetch "https://github.com/projectdiscovery/nuclei-templates/archive/refs/tags/v${NUCLEI_TEMPLATES_VERSION}.tar.gz" \
    "$NUCLEI_TEMPLATES_SHA256" /tmp/nuclei-templates.tar.gz
mkdir -p /root
tar -xzf /tmp/nuclei-templates.tar.gz -C /root
mv "/root/nuclei-templates-${NUCLEI_TEMPLATES_VERSION}" /root/nuclei-templates
rm /tmp/nuclei-templates.tar.gz /tmp/nuclei.zip
rm -rf /tmp/unpack

test "$(find /root/nuclei-templates -name '*.yaml' | wc -l)" -gt 1000
verify_output 'nuclei' nuclei -version
