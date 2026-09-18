#!/bin/bash
# tools/gobuster/install.sh — install and verification for gobuster.
set -eux -o pipefail

. /tmp/tool-install-helpers.sh

# bookworm ships 3.5.0, which predates the upstream 3.7 CLI rework: no
# JSON/XML/CSV output, no --rate, and `-p` is the pattern flag rather than
# proxy. AGENTS.md documents the 3.5.0 flag set for that reason; re-verify
# against `gobuster <mode> --help` before documenting a version bump.
apt_install gobuster

verify_output 'gobuster' gobuster version
