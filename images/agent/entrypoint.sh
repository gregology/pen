#!/bin/sh
set -eu

# Seed the harness config once. Editing afterwards happens on the host
# bind mount; even a hostile edit cannot restore direct provider access
# because the kill switch only permits traffic to the sandbox network.
if [ ! -f "$DSH_HOME/settings.yaml" ]; then
    mkdir -p "$DSH_HOME"
    cp /app/settings.seed.yaml "$DSH_HOME/settings.yaml"
fi

# The GUI is reached over the LAN as http://10.0.0.10:3080; the trust
# fence 403s any Host authority not named here. dsh binds loopback :3090
# because the gateway's GUI forwarder owns wildcard :3080.
exec dsh web --no-open --port 3090 --trusted-host 10.0.0.10:3080
