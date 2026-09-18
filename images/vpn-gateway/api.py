"""Exit-node control API for the vpn-gateway container.

This process owns the tunnel lifecycle: it brings up the initial node at
startup and switches nodes on request. Tunnel management lives here and
nowhere else — one code path, so the kill switch invariants only have to
be reasoned about once. The kill switch itself is applied by
entrypoint.sh before this process starts, so a tunnel failure can never
open egress; it can only leave the namespace dark.

The API is unauthenticated. Access control is the kill switch's job: it
answers port 8080 from the sandbox network and loopback and drops it from
everywhere else, so the only client that can reach it is the agent, which
shares this network namespace.
"""

import json
import os
import re
import socket
import subprocess
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

CONFIG_DIR = "/vpn/configs"
# Basename is the interface name: wg-quick up /run/wg0.conf manages wg0.
ACTIVE_CONF = "/run/wg0.conf"
IFACE = "wg0"
ENDPOINT_COMMENT = "pen-endpoint"

# Fixed, not configurable: the kill switch opens this exact port to the
# sandbox network and drops it everywhere else, and the agent's URL for it
# is baked into the agent image. A variable here could disagree with both.
# Changing the port means changing killswitch.sh and the agent image together.
PORT = 8080
LAN_CIDR = os.environ["LAN_CIDR"]
# wg-quick claims rule priorities just ahead of whatever already exists,
# so the LAN rule can only win by being (re)asserted after each tunnel
# bring-up, at a priority below wg-quick's chosen slots.
LAN_RULE_PRIORITY = 90

NAME_RE = re.compile(r"^[A-Za-z0-9_-]+$")

node_lock = threading.Lock()
current_node = None


def list_nodes():
    names = []
    for entry in os.listdir(CONFIG_DIR):
        stem, dot, suffix = entry.rpartition(".conf")
        if dot and stem and not suffix:
            names.append(stem)
    return sorted(names)


def write_active_config(name):
    # Two rewrites, both about agreement:
    # - DNS= lines are stripped (wg-quick aborts without resolvconf; DNS
    #   is pinned at the compose level).
    # - The Endpoint hostname is resolved here and rewritten to the IP
    #   literal. Provider hostnames are clusters with many A records, and
    #   wg setconf resolves the name independently — if it picked a
    #   different IP than the firewall's endpoint exception, the handshake
    #   would be dropped by the kill switch. One resolution, one IP, both
    #   consumers.
    endpoint = None
    out = []
    with open(os.path.join(CONFIG_DIR, name + ".conf")) as f:
        for line in f:
            if line.strip().startswith("DNS"):
                continue
            match = re.match(r"(\s*Endpoint\s*=\s*)(\S+):(\d+)\s*$", line)
            if match:
                host, port = match.group(2), int(match.group(3))
                ip = socket.getaddrinfo(
                    host, port, socket.AF_INET, socket.SOCK_DGRAM
                )[0][4][0]
                endpoint = (ip, port)
                line = f"{match.group(1)}{ip}:{port}\n"
            out.append(line)
    if endpoint is None:
        raise ValueError("config has no Endpoint")
    with open(ACTIVE_CONF, "w") as f:
        f.writelines(out)
    os.chmod(ACTIVE_CONF, 0o600)
    return endpoint


def allow_endpoint(ip, port):
    # The kill switch drops all egress except via wg+, so the tunnel's own
    # underlay packets to the provider need an explicit exception.
    subprocess.run(
        ["iptables", "-A", "OUTPUT", "-p", "udp", "-d", ip, "--dport", str(port),
         "-m", "comment", "--comment", ENDPOINT_COMMENT, "-j", "ACCEPT"],
        check=True,
    )


def clear_endpoint_rules():
    out = subprocess.run(
        ["iptables", "-S", "OUTPUT"], check=True, capture_output=True, text=True
    ).stdout
    for line in out.splitlines():
        if ENDPOINT_COMMENT in line:
            subprocess.run(
                ["iptables", "-D", "OUTPUT"] + line.split()[2:], check=True
            )


def run(cmd):
    return subprocess.run(cmd, capture_output=True, text=True)


def default_gateway():
    result = run(["ip", "route", "show", "default"])
    fields = result.stdout.split()
    return fields[fields.index("via") + 1]


def keep_lan_on_main_table():
    # wg-quick's not-fwmark rule sends LAN-bound replies into the tunnel and
    # claims rule priorities just ahead of whatever already exists, so the
    # LAN rule only wins by being re-asserted after each bring-up. The rule
    # is worthless without the route it consults: rotation can leave table
    # main without LAN_CIDR, and a rule pointing at an empty table fails
    # silently. The route goes via the gateway because the bridge does not
    # proxy ARP — on-link, the next hop for a LAN client is unresolvable.
    gateway = default_gateway()
    run(["ip", "rule", "del", "to", LAN_CIDR, "lookup", "main",
         "priority", str(LAN_RULE_PRIORITY)])
    run(["ip", "rule", "add", "to", LAN_CIDR, "lookup", "main",
         "priority", str(LAN_RULE_PRIORITY)])
    try:
        subprocess.run(
            ["ip", "route", "replace", LAN_CIDR, "via", gateway],
            check=True, capture_output=True, text=True,
        )
    except subprocess.CalledProcessError as exc:
        print(f"api: LAN route not restored: {exc.stderr.strip()}")


def tunnel_up(name):
    global current_node
    with node_lock:
        try:
            ip, port = write_active_config(name)
        except (OSError, ValueError, socket.gaierror) as exc:
            return False, f"config error: {exc}"

        # Down before up, and the endpoint exception is replaced before the
        # new tunnel starts: at every instant, egress is either the old
        # tunnel, the new tunnel's endpoint only, or nothing.
        clear_endpoint_rules()
        run(["wg-quick", "down", ACTIVE_CONF])
        try:
            allow_endpoint(ip, port)
        except subprocess.CalledProcessError as exc:
            return False, f"endpoint allow rule failed: {exc}"

        result = run(["wg-quick", "up", ACTIVE_CONF])
        if result.returncode != 0:
            current_node = None
            return False, result.stderr.strip()
        keep_lan_on_main_table()
        current_node = name
        return True, None


def tunnel_status():
    result = run(["wg", "show", IFACE, "dump"])
    if result.returncode != 0 or not result.stdout.strip():
        return {"node": current_node, "tunnel": "down"}
    peer = result.stdout.splitlines()[1].split("\t")
    return {
        "node": current_node,
        "tunnel": "up",
        "latest_handshake": int(peer[4]),
        "rx_bytes": int(peer[5]),
        "tx_bytes": int(peer[6]),
    }


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    # No authentication. The API is reachable only from the sandbox network
    # and loopback — the kill switch drops port 8080 from everywhere else,
    # including the tunnel — and the only client is the agent, which shares
    # this network namespace. A shared bearer token added nothing to that
    # and introduced a way to lose access: a blank VPN_API_TOKEN in the
    # stack environment made the agent's own calls fail.
    def reply(self, code, body):
        payload = json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def do_GET(self):
        if self.path == "/status":
            return self.reply(200, tunnel_status())
        if self.path == "/nodes":
            return self.reply(200, {"current": current_node, "nodes": list_nodes()})
        return self.reply(404, {"error": "not found"})

    def do_POST(self):
        if self.path != "/switch":
            return self.reply(404, {"error": "not found"})
        try:
            length = int(self.headers.get("Content-Length", 0))
            node = json.loads(self.rfile.read(length) or b"{}").get("node", "")
        except (ValueError, json.JSONDecodeError):
            return self.reply(400, {"error": "invalid body"})
        if not NAME_RE.match(node) or node not in list_nodes():
            return self.reply(404, {"error": f"unknown node: {node!r}"})
        ok, error = tunnel_up(node)
        if not ok:
            return self.reply(502, {"error": error, **tunnel_status()})
        return self.reply(200, tunnel_status())

    def log_message(self, fmt, *args):
        sys.stdout.write("api: " + fmt % args + "\n")


def main():
    nodes = list_nodes()
    if not nodes:
        print(f"api: no configs in {CONFIG_DIR}; tunnel down until one appears")
    else:
        # Backgrounded: the API must serve even while (or if) the tunnel
        # comes up, so /status can report the failure and /switch can retry.
        threading.Thread(target=tunnel_up, args=(nodes[0],), daemon=True).start()
    print(f"api: listening on :{PORT}")
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()


if __name__ == "__main__":
    main()
