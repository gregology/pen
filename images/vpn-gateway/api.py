"""Exit-node control API for the vpn-gateway container.

This process owns the tunnel lifecycle: it brings up the initial node at
startup and switches nodes on request. Tunnel management lives here and
nowhere else — one code path, so the kill switch invariants only have to
be reasoned about once. The kill switch itself is applied by
entrypoint.sh before this process starts, so a tunnel failure can never
open egress; it can only leave the namespace dark.
"""

import hmac
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

TOKEN = os.environ["VPN_API_TOKEN"]
PORT = int(os.environ.get("VPN_API_PORT", "8080"))
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
    # wg-quick aborts on DNS= lines when resolvconf is absent; DNS is
    # pinned at the compose level, so provider DNS lines are stripped.
    with open(os.path.join(CONFIG_DIR, name + ".conf")) as f:
        lines = [ln for ln in f if not ln.strip().startswith("DNS")]
    with open(ACTIVE_CONF, "w") as f:
        f.writelines(lines)
    os.chmod(ACTIVE_CONF, 0o600)


def resolve_endpoint():
    host = port = None
    with open(ACTIVE_CONF) as f:
        for line in f:
            match = re.match(r"\s*Endpoint\s*=\s*(\S+):(\d+)\s*$", line)
            if match:
                host, port = match.group(1), int(match.group(2))
    if host is None:
        raise ValueError("config has no Endpoint")
    # WireGuard is UDP-only, so a single AF_INET answer suffices.
    ip = socket.getaddrinfo(host, port, socket.AF_INET, socket.SOCK_DGRAM)[0][4][0]
    return ip, port


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


def keep_lan_on_main_table():
    # Without this, wg-quick's not-fwmark rule diverts LAN-bound replies
    # into the tunnel and the GUI goes dark while the tunnel is up.
    run(["ip", "rule", "add", "to", LAN_CIDR, "lookup", "main",
         "priority", str(LAN_RULE_PRIORITY)])


def tunnel_up(name):
    global current_node
    with node_lock:
        try:
            write_active_config(name)
            ip, port = resolve_endpoint()
        except (OSError, ValueError) as exc:
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

    def authorized(self):
        expected = f"Bearer {TOKEN}"
        header = self.headers.get("Authorization", "")
        return hmac.compare_digest(header.encode(), expected.encode())

    def reply(self, code, body):
        payload = json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def do_GET(self):
        if not self.authorized():
            return self.reply(401, {"error": "unauthorized"})
        if self.path == "/status":
            return self.reply(200, tunnel_status())
        if self.path == "/nodes":
            return self.reply(200, {"current": current_node, "nodes": list_nodes()})
        return self.reply(404, {"error": "not found"})

    def do_POST(self):
        if not self.authorized():
            return self.reply(401, {"error": "unauthorized"})
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
