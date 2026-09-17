#!/bin/sh
set -eu

# Nothing else runs until the egress policy is in place — this is the
# ordering the no-leak guarantee depends on.
/app/killswitch.sh

# The agents' web UIs refuse wildcard binds by design, and Docker port
# publishing cannot reach a loopback-bound process, so each gets a
# forwarder in this namespace. Ports differ from the loopback ones they
# target — a wildcard bind collides with any loopback listener on the
# same port. killswitch.sh scopes both to host/sandbox/LAN.
socat TCP-LISTEN:3080,fork,reuseaddr TCP:127.0.0.1:3090 &   # dsh web UI
socat TCP-LISTEN:3081,fork,reuseaddr TCP:127.0.0.1:8081 &   # code-server

exec python3 /app/api.py
