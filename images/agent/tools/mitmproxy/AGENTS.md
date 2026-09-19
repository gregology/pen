# mitmproxy

mitmproxy is an interactive HTTP(S) proxy that terminates TLS with its own CA,
which makes it the tool for reading and rewriting traffic that is otherwise
opaque: authenticated API calls, session cookies, request signing, and client
behaviour under modified responses. In this container only `mitmdump` is usable —
`mitmproxy` needs a TTY and `mitmweb`'s UI needs a browser to view — but
`mitmdump` plus an addon script covers capture, replay, filtering, and rewriting
without either.

## Installation and location

| | |
|---|---|
| Version | 11.0.0 (`mitmdump --version` → `Mitmproxy: 11.0.0 / Python: 3.11.2 / OpenSSL: OpenSSL 3.3.2 3 Sep 2024`) |
| Binaries | `/opt/venvs/mitmproxy/bin/{mitmdump,mitmproxy,mitmweb}` (virtualenv `/opt/venvs/mitmproxy`, first on `PATH`) |
| Certificates | `~/.mitmproxy/` by default, or `--set confdir=DIR` |
| CA files | `mitmproxy-ca.pem` (private key — sensitive), `mitmproxy-ca.p12`, `mitmproxy-ca-cert.pem`, `mitmproxy-ca-cert.cer`, `mitmproxy-ca-cert.p12`, `mitmproxy-dhparam.pem` |
| Flow files | Written where `-w` points; mitmproxy's own tnetstring format, never pcap |
| Logs | stderr; `ctx.log.*` from addons goes to stderr at default verbosity |

The venv holds `bcrypt` below 4.1 deliberately: mitmproxy imports
`passlib.apache` at startup, and passlib 1.7.4 calls `bcrypt.hashpw` with a
>72-byte test string during backend detection, which later bcrypt releases
reject with `ValueError: password cannot be longer than 72 bytes`. With bcrypt
5.x all three entry points exit 1 before printing anything. Do not upgrade
bcrypt in this venv.

This is a mitmproxy problem, not a platform one: because each Python tool has
its own venv, the constraint is invisible to every other tool. NetExec and
impacket resolve their own dependencies independently and are unaffected.

## Rules that apply to this tool

1. **Authorization first.** A proxy that terminates TLS sees everything in
   cleartext, including credentials that were never meant to be readable. Only
   intercept traffic for targets in scope, and only on interfaces and hosts Greg
   has confirmed.
2. **Flow files are credential material.** A `.mitm` capture holds full request
   and response bodies, cookies, `Authorization` headers, and any tokens in
   URLs. Keep them in `$WORK`, never paste bodies into the transcript, and delete
   them when the engagement closes. The same applies to addon logs.
3. **The CA private key is a signing capability.** `mitmproxy-ca.pem` lets anyone
   mint trusted certificates for any host while a client trusts it. Keep the
   `confdir` inside `$WORK`, never copy the key out of the container, and never
   install the CA in a client you do not control.
4. **The proxy is not a containment mechanism.** Traffic proxied by mitmproxy
   still exits through the WireGuard tunnel; a tool's proxy setting does not
   change attribution. Do not use mitmproxy to route around the gateway.
5. **Local targets for learning.** Point the proxy at this container's own
   services (`python3 -m http.server`) or at authorized targets. Do not park it
   in front of arbitrary third-party traffic.
6. **Bound and name every capture.** `-w "$WORK/mitm/<label>.mitm"`, plus the
   `-s` script and `--set` options recorded in the findings note, so a rewritten
   response can be reproduced.

## Command reference

`mitmdump` options

| Flag | Meaning |
|---|---|
| `-p, --listen-port PORT` | Proxy port (default 8080 — check for a clash) |
| `-w, --save-stream-file PATH` | Write flows as they arrive; prefix `+` to append, strftime patterns are expanded |
| `-r, --rfile PATH` | Read flows from a file instead of listening |
| `-n, --no-server` | Don't start a proxy (use with `-r`) |
| `-s, --scripts FILE` | Load an addon script (repeatable) |
| `-m, --mode MODE` | `regular` (default), `transparent`, `socks5`, `reverse:SPEC`, `upstream:SPEC`, `wireguard[:PATH]` |
| `--set option[=value]` | Set any option, e.g. `--set confdir=/work/mitm-ca` |
| `--flow-detail LEVEL` | 0–4; how much of each flow is printed |
| `-q, --quiet` | Suppress flow output (also silences `ctx.log.info`; errors still print) |
| `--options` | Print every option with its documentation |
| `--commands` | Print every command and signature (148 here) |

Options worth setting with `--set`

| Option | Purpose |
|---|---|
| `confdir` | Where the CA lives (default `~/.mitmproxy`) |
| `save_stream_filter='~u example\.com'` | Only write matching flows to `-w` |
| `readfile_filter='~m POST'` | Only load matching flows from `-r` |
| `modify_body='\|~u host\|regex\|replacement'` | Rewrite bodies without a script |
| `modify_headers='\|~u host\|Header-Name\|value'` | Add/remove/replace headers |
| `map_local='\|~u host\|regex\|/dir'` | Serve a local directory instead of the upstream |
| `map_remote`, `dumper_filter`, `flow_detail`, `stream_large_bodies` | Other documented options (`--options`) |

Spec syntax for `modify_*`, `map_*`: the **first character is the separator**,
then either `subject<sep>replacement` (applies to everything) or
`filter<sep>subject<sep>replacement` (filter is a mitmproxy flow filter, subject
is a regex). `replacement` may be `@path` to read the value from a file.

Flow filters (verified operators): `~u REGEX` URL, `~m METHOD`, `~c STATUS`
response code, `~b REGEX` body, `~q` no-response flows. The full grammar is in
mitmproxy's flowfilter documentation.

## Typical workflows

1. **Capture HTTP and HTTPS through the proxy.** The client must trust the CA;
   `--cacert` or `SSL_CERT_FILE` both work for curl.

   ```bash
   mkdir -p "$WORK/mitm" "$WORK/mitm-ca"
   mitmdump -q -w "$WORK/mitm/session.mitm" --set confdir="$WORK/mitm-ca" -p 8888 &
   sleep 2
   curl -s -o /dev/null -w '%{http_code}\n' -x http://127.0.0.1:8888 http://127.0.0.1:8090/
   curl -s -o /dev/null -w '%{http_code}\n' \
        --cacert "$WORK/mitm-ca/mitmproxy-ca-cert.pem" -x http://127.0.0.1:8888 https://example.com/
   kill %1
   ```

   Without the CA the TLS handshake fails (`curl` reports code `000`).

2. **Read a capture back non-interactively, filtered.**

   ```bash
   mitmdump -nr "$WORK/mitm/session.mitm" --flow-detail 1
   mitmdump -nr "$WORK/mitm/session.mitm" --set readfile_filter='~u nope' --flow-detail 1
   ```

3. **Rewrite with an addon script** (the general case). Save it in `$WORK`:

   ```python
   # "$WORK/mitm/addon.py"
   from mitmproxy import ctx, http

   class Rewriter:
       def request(self, flow: http.HTTPFlow) -> None:
           if flow.request.path == "/":
               flow.request.headers["X-Pen-Test"] = "added-by-addon"
               ctx.log.info(f"request {flow.request.method} {flow.request.pretty_url}")

       def response(self, flow: http.HTTPFlow) -> None:
           if flow.response and flow.response.headers.get("content-type", "").startswith("text/html"):
               flow.response.text = flow.response.text.replace("Directory listing", "PEN-REWRITTEN")
               flow.response.headers["X-Pen-Rewritten"] = "yes"

   addons = [Rewriter()]
   ```

   ```bash
   mitmdump -s "$WORK/mitm/addon.py" -w "$WORK/mitm/rewrite.mitm" \
            --set confdir="$WORK/mitm-ca" -p 8888
   ```

   Verified effect: the body marker is replaced, `X-Pen-Rewritten: yes` appears on
   the response, and the injected request header is visible in the saved flow.

4. **Rewrite without a script** for simple substitutions:

   ```bash
   mitmdump -q -p 8888 --set confdir="$WORK/mitm-ca" \
     --set modify_body='/~u 127\.0\.0\.1/Directory listing/PEN-MODBODY/' \
     --set modify_headers='/~u 127\.0\.0\.1/X-Pen-Mod/yes'
   # or stand in a local directory for a host (note the leading separator)
   mitmdump -q -p 8888 --set 'map_local=|~u example\.com|example\.com|/tmp/site'
   ```

5. **Reverse mode** — expose one upstream through the proxy port, no client proxy
   configuration:

   ```bash
   mitmdump -q --mode reverse:http://127.0.0.1:8090 -p 9080 --set confdir="$WORK/mitm-ca"
   curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:9080/       # 200
   ```

## Output and parsing

`--flow-detail 1` is one request line plus one response line per flow:

```
127.0.0.1:45752: GET http://127.0.0.1:8090/ HTTP/1.1
     << HTTP/1.0 200 OK 394b
127.0.0.1:45754: GET https://example.com/ HTTP/2.0
     << HTTP/2.0 200 OK 559b
```

`--flow-detail 3` adds headers and body content — useful for a human, dangerous
for a transcript. `--flow-detail 0` with `-q` gives a silent capture.

Filtering what gets *written* is a proxy option, not a flag:

```bash
mitmdump -q -w only.mitm --set save_stream_filter='~u example\.com' -p 8888
mitmdump -nr only.mitm --flow-detail 1     # exactly one flow, the example.com one
```

Filtering what gets *read*:

```bash
for f in '~u nope' '~m GET' '~c 404' '~c 200'; do
  printf '%-10s %s\n' "$f" "$(mitmdump -nr cap.mitm --set readfile_filter="$f" --flow-detail 1 2>/dev/null | grep -c '^[0-9]')"
done
# ~u nope    1
# ~m GET     3
# ~c 404     1
# ~c 200     2
```

Machine-readable output needs an addon — write JSONL from the hooks (same
class-based shape as the verified addon above):

```python
# addon: JSONL of request/response metadata
import json
from mitmproxy import http

class Jsonl:
    def response(self, flow: http.HTTPFlow) -> None:
        with open("/work/mitm/flows.jsonl", "a") as fh:
            fh.write(json.dumps({
                "method": flow.request.method,
                "url": flow.request.pretty_url,
                "status": flow.response.status_code if flow.response else None,
                "req_headers": dict(flow.request.headers),
                "resp_headers": dict(flow.response.headers) if flow.response else {},
            }) + "\n")

addons = [Jsonl()]
```

`mitmweb`'s REST API is reachable without a browser even though its UI is not:
`curl http://127.0.0.1:8081/flows` returned `[]` on a fresh instance and serves
JSON flow data.

`-w out.pcap` does **not** produce a pcap: the extension is ignored and the file
is mitmproxy's tnetstring format. `tshark -r` on it exits 2.

## Chaining with the rest of the toolchain

```bash
# mitmproxy for the decrypted view, tshark for the packets, side by side
tshark -i eth0 -f 'host 10.0.0.5' -a duration:60 -w "$WORK/pcap/session.pcap" &
mitmdump -q -w "$WORK/mitm/session.mitm" --set confdir="$WORK/mitm-ca" -p 8888
```

```bash
# URLs harvested from a flow file -> inject into a content-discovery tool
mitmdump -nr "$WORK/mitm/session.mitm" --flow-detail 1 2>/dev/null \
  | awk '{print $3}' | rg '^https?://' | sort -u > "$WORK/mitm/urls.txt"
```

```bash
# a request seen through the proxy can be replayed by scapy or curl
mitmdump -nr "$WORK/mitm/session.mitm" --flow-detail 3 2>/dev/null > "$WORK/mitm/session.txt"
curl -s -o /dev/null -w '%{http_code}\n' \
     --cacert "$WORK/mitm-ca/mitmproxy-ca-cert.pem" -x http://127.0.0.1:8888 \
     -H 'Authorization: Bearer REDACTED' http://127.0.0.1:8090/
```

```bash
# secrets that appear in bodies/headers: extract text, then scan it
mitmdump -nr "$WORK/mitm/session.mitm" --flow-detail 3 2>/dev/null \
  | trufflehog --no-update --no-verification --json stdin > "$WORK/trufflehog/flows.jsonl"
```

`trivy` and `nuclei` consume the URLs; `tshark` and `scapy` cover the packet
level; `mitmproxy` is the only tool that can both read and *change* application
traffic that a client trusts.

## Limits, failure modes and gotchas

- **A `-w` flow file stays 0 bytes until mitmdump shuts down cleanly.** Flows are
  buffered and flushed on exit, so `stat` on the capture file while the proxy is
  running proves nothing and looks exactly like a capture that failed. Verified:
  `mitmdump -q -p 8907 -w flows.mitm` plus one proxied request left `flows.mitm`
  at `0 bytes`; after `pkill -INT -x mitmdump` the same file was `1931 bytes` and
  `mitmdump -nr flows.mitm --flow-detail 1` listed the exchange. Stop the proxy —
  `SIGINT`, not `SIGKILL` — before reading it or concluding nothing was captured.
- **`mitmproxy` needs a TTY.** `< /dev/null mitmproxy` prints
  `Error: mitmproxy's console interface requires a tty. Please run mitmproxy in
  an interactive shell environment.` and exits 120. The agent's shell has no TTY,
  so the console tool is unusable.
- **`mitmweb`'s UI is not usable from this container.** It is a web app served
  on a port inside the agent's network namespace, and nothing here renders it:
  `tools/browser` is a separate process that navigates to targets, not a client
  for local admin UIs. The process starts and serves HTTP (verified `200` on
  `http://127.0.0.1:8081/`) and the JSON API (`/flows`) works, so scripting
  against the API is possible, but expect to drive everything through
  `mitmdump` instead. `mitmproxy` itself needs a TTY (see above).
- **Transparent mode does no redirection by itself.** `--mode transparent`
  assumes packets are already being redirected to the proxy port by firewall
  rules; `iptables` and `nft` are not installed in this image. Use `regular`
  (clients set `-x`/`HTTP_PROXY`) or `reverse:SPEC` (no client changes).
- **Unknown `--set` options are silently ignored.** `mitmdump --set
  no_such_option=1 -p 8899` starts a working proxy with no warning. A typo in an
  option name looks like a working run with no effect. Cross-check with
  `mitmdump --options`.
- **Invalid values do error.** `--set modify_body='no-separators-here'` fails with
  `Cannot parse modify_body option no-separators-here: Invalid number of
  parameters (2 or 3 are expected)`.
- **Quotes are literal in `modify_*` patterns.** `modify_body='/~u host/"Directory
  listing"/X/'` searches for the regex `"Directory listing"` including quotes and
  matches nothing; drop the quotes (verified: 2 replacements with the unquoted
  form, 0 with quotes).
- **`-q` hides your addon's `ctx.log.info`.** `ctx.log.info` lines only appear
  without `-q`; use `ctx.log.warn`/`ctx.log.error`, or run without `-q` while
  developing the addon.
- **`ctx.log.info` output includes request URLs.** In a transcript that is fine;
  with `--flow-detail 3` or default dumper output, bodies and headers are printed
  too — do not paste that.
- **CA trust is per client.** `curl --cacert` and `SSL_CERT_FILE` work (verified
  `200`); a client that does not trust the CA fails the handshake (verified
  `000`). Certificate pinning defeats the proxy entirely.
- **Port clashes are easy.** mitmdump's default listen port is 8080, which this
  container's VPN control API already holds, so always pass `-p` explicitly;
  local fixtures use 8090 (`-p 8888`, target `8090`).
- **Flow files are append-friendly but not pcap.** Use the `+` prefix
  (`-w +file.mitm`) to append, and convert with `mitmdump -nr in.mitm -w out.mitm`
  if you need a filtered copy.
- **`pkill -f mitmdump` can kill your own shell** when the pattern appears in the
  command line of the script issuing it; use `pkill -f '[m]itmdump'`.
- **HTTP/2 is used automatically** for HTTPS upstreams (flows show `HTTP/2.0`),
  and addons that rewrite bodies must handle compressed content — mitmproxy
  decodes by default (`flow.response.text`), but raw `content` edits need care.

## Safety and scope

- Intercept only hosts and clients in scope. A proxy that rewrites a response can
  change what a target's user sees; that is an active attack, not observation.
- Treat every `.mitm` flow file and addon log as credential material: store in
  `$WORK`, never in git, never in the transcript.
- Keep the CA private key (`mitmproxy-ca.pem`) inside `$WORK/mitm-ca`, do not
  export it, and delete the confdir when the engagement ends.
- Rewriting a third party's traffic (even Greg's own service) is a scope decision:
  confirm before modifying requests or responses rather than only reading them.
- Do not use mitmproxy to bypass the VPN or to add a second egress path; the
  proxy is an observer, not a route.
