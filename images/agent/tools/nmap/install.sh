#!/bin/bash
# tools/nmap/install.sh — install and verification for nmap.
set -eux -o pipefail

. /tmp/tool-install-helpers.sh

# The nmap in the agent image. Root uid is deliberate: nmap's SYN and UDP
# scans and OS detection need raw sockets, and Docker grants no ambient
# capabilities to a non-root process.
apt_install nmap

verify_output 'Nmap version' nmap --version
