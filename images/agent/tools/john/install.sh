#!/bin/bash
# tools/john/install.sh — install and verification for john.
set -eux -o pipefail

. /tmp/tool-install-helpers.sh

# Debian's core john build cracks crypt(3) formats ($1$, $5$, $6$, bcrypt,
# descrypt) and little else. Every non-crypt(3) hash belongs to hashcat —
# see tools/hashcat/. Do not reach for john for NTLM or Kerberos material.
apt_install john

john --list=build-info | head -3
