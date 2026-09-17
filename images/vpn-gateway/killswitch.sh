#!/bin/sh
# Fail-closed egress policy for the namespace the agent lives in.
# Everything not explicitly permitted here must not leave.
set -eu

: "${SANDBOX_CIDR:?required}"
: "${EGRESS_CIDR:?required}"
: "${LAN_CIDR:?required}"
: "${DNS_SERVERS:?required}"
API_PORT="${VPN_API_PORT:-8080}"

iptables -F
iptables -P INPUT ACCEPT
iptables -P FORWARD DROP
iptables -P OUTPUT DROP

# Docker's embedded DNS (127.0.0.11), the control API, and the GUI
# forward target all live on loopback.
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT

# Replies to legitimate inbound connections (published GUI port,
# healthchecks) must get out; only new outbound connections are suspect.
iptables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# The only route to the internet.
iptables -A OUTPUT -o wg+ -j ACCEPT

# Sandbox peers: agent -> llm-proxy and the control API.
iptables -A OUTPUT -d "$SANDBOX_CIDR" -j ACCEPT

# Endpoint resolution has to work before the first tunnel exists.
# This leaks only the fact that we resolve DNS at all.
for server in $DNS_SERVERS; do
    iptables -A OUTPUT -p udp -d "$server" --dport 53 -j ACCEPT
    iptables -A OUTPUT -p tcp -d "$server" --dport 53 -j ACCEPT
done

# The control API answers the sandbox network and loopback only —
# never the egress network or the tunnel.
iptables -A INPUT -p tcp --dport "$API_PORT" -s "$SANDBOX_CIDR" -j ACCEPT
iptables -A INPUT -p tcp --dport "$API_PORT" -j DROP

# The forwarded web UIs (dsh :3080, code-server :3081) answer the LAN —
# Docker DNAT preserves the real client source IP — plus the host via
# either bridge and the sandbox, and never the tunnel.
for port in 3080 3081; do
    iptables -A INPUT -p tcp --dport "$port" -s "$SANDBOX_CIDR" -j ACCEPT
    iptables -A INPUT -p tcp --dport "$port" -s "$EGRESS_CIDR" -j ACCEPT
    iptables -A INPUT -p tcp --dport "$port" -s "$LAN_CIDR" -j ACCEPT
    iptables -A INPUT -p tcp --dport "$port" -j DROP
done
