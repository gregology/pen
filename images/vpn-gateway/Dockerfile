FROM alpine:3.21

# iproute2: busybox `ip` lacks the policy routing wg-quick needs.
# socat: bridges the published GUI port to the agent's loopback-only dsh.
# python3: stdlib-only control API, no pip dependencies to audit.
RUN apk add --no-cache wireguard-tools iproute2 iptables python3 curl socat

WORKDIR /app
COPY killswitch.sh entrypoint.sh sysctl ./
COPY api.py ./
RUN chmod +x killswitch.sh entrypoint.sh sysctl

# /app first so the sysctl shim shadows /sbin/sysctl for wg-quick.
ENV PATH="/app:$PATH"

ENTRYPOINT ["/app/entrypoint.sh"]
