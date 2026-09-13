#!/bin/sh
set -eu

# Seed the harness config once. Editing afterwards happens on the host
# bind mount; even a hostile edit cannot restore direct provider access
# because the kill switch only permits traffic to the sandbox network.
if [ ! -f "$DSH_HOME/settings.yaml" ]; then
    mkdir -p "$DSH_HOME"
    cp /app/settings.seed.yaml "$DSH_HOME/settings.yaml"
fi

exec dsh web --no-open --port 3080
