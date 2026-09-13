#!/bin/sh
set -eu

# Nothing else runs until the egress policy is in place — this is the
# ordering the no-leak guarantee depends on.
/app/killswitch.sh

# dsh web refuses to bind 0.0.0.0 by design, and Docker port publishing
# cannot reach a loopback-bound process, so the GUI gets a forwarder in
# this namespace. killswitch.sh limits :3080 to the host and sandbox.
socat TCP-LISTEN:3080,fork,reuseaddr TCP:127.0.0.1:3080 &

exec python3 /app/api.py
