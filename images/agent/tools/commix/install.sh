#!/bin/bash
# tools/commix/install.sh — version pin, install, and verification for commix.
set -eux -o pipefail

. /tmp/tool-install-helpers.sh

COMMIX_VERSION=4.1
COMMIX_SHA256=d71e6a98231c2eb434eb9cc1b835523ad5618578309e2f835c40d767f2af79de

# commix is deliberately NOT taken from PyPI: the package published there as
# `commix` is an unrelated installer stub that shadows the real tool and does
# nothing. The upstream release is the only source of the command-injection
# scanner, and it is a plain Python tree run from its own directory.
fetch "https://github.com/commixproject/commix/archive/refs/tags/v${COMMIX_VERSION}.tar.gz" \
    "$COMMIX_SHA256" /tmp/commix.tar.gz
tar -xzf /tmp/commix.tar.gz -C /opt
mv "/opt/commix-${COMMIX_VERSION}" /opt/commix
chmod +x /opt/commix/commix.py
ln -s /opt/commix/commix.py /usr/local/bin/commix
rm -f /tmp/commix.tar.gz

# Parse the entry point: a syntax error in a vendored tree would otherwise
# surface only when the tool is first run against a target.
python3 -c "import ast; ast.parse(open('/opt/commix/commix.py').read())"

# `--version` prints and exits without needing a target. Verified against 4.1.
commix --version
