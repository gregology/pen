#!/bin/bash
# tools/scapy/install.sh — install and verification for scapy.
set -eux -o pipefail

. /tmp/tool-install-helpers.sh

# Own venv rather than the apt python3-scapy package: bookworm ships 2.5.0
# against upstream 2.7.0, and a system dist-packages install is importable
# only under /usr/bin/python3, which makes it invisible to every other tool.
SCAPY_VENV=/opt/venvs/scapy
python3 -m venv "$SCAPY_VENV"
"$SCAPY_VENV/bin/pip" install --no-cache-dir --upgrade pip
"$SCAPY_VENV/bin/pip" install --no-cache-dir scapy

# scapy is a library first: it has no console script of its own, so the
# interpreter is the interface. A shim at a predictable name keeps it usable
# without the caller knowing which venv it lives in.
cat > /usr/local/bin/scapy <<'EOF'
#!/bin/sh
exec /opt/venvs/scapy/bin/python3 "$@"
EOF
chmod +x /usr/local/bin/scapy

expose_venv "$SCAPY_VENV"
verify_output 'scapy' scapy -c 'from scapy.all import conf; print("scapy", conf.version)'
