#!/bin/sh
set -eu

# The container runs as gid 1000 so the shared working directory stays
# editable from the host without sudo; the umask keeps new files
# group-writable.
umask 002

# Seed the harness config once. Editing afterwards happens on the host
# bind mount; even a hostile edit cannot restore direct provider access
# because the kill switch only permits traffic to the sandbox network.
if [ ! -f "$DSH_HOME/settings.yaml" ]; then
    mkdir -p "$DSH_HOME"
    cp /app/settings.seed.yaml "$DSH_HOME/settings.yaml"
fi

# Web VS Code for the shared working directory. Loopback only — the
# gateway's forwarder is the sole LAN-facing listener, so the kill
# switch's INPUT rules govern this port exactly like the DSH GUI.
# Without CODE_SERVER_PASSWORD, code-server generates one into the
# config file on the data mount.
if [ -n "${CODE_SERVER_PASSWORD:-}" ]; then
    export PASSWORD="$CODE_SERVER_PASSWORD"
fi
code-server \
    --bind-addr 127.0.0.1:8081 \
    --auth password \
    --config /data/code-server/config.yaml \
    --user-data-dir /data/code-server \
    --disable-telemetry \
    --disable-update-check \
    /working &

# The GUI is reached over the LAN as http://10.0.0.10:3080; the trust
# fence 403s any Host authority not named here. dsh binds loopback :3090
# because the gateway's GUI forwarder owns wildcard :3080.
exec dsh web --no-open --port 3090 --trusted-host 10.0.0.10:3080
