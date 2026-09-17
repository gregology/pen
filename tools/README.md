# Tool Documentation

Per-tool usage documentation for the pentest toolchain in the `agent`
container. Written for the agent that uses these tools: each directory holds
the flags that matter, worked examples, output formats, and the failure modes
that waste time.

This directory is the `tools/` path inside the agent container (the repo is
bind-mounted at the same layout under `/home/user/pen/`), so the agent can
read its own instructions from `/working` or from this checkout.

## Index

Reconnaissance and mapping

| Tool | Directory | Job |
|---|---|---|
| `naabu` | [`naabu/`](naabu/AGENTS.md) | Fast port discovery over host lists |
| `httpx` | [`httpx/`](httpx/AGENTS.md) | Probe hosts for HTTP, tech, TLS, titles |
| `katana` | [`katana/`](katana/AGENTS.md) | Crawl sites, execute JS, collect URLs |
| `subfinder` | [`subfinder/`](subfinder/AGENTS.md) | Passive subdomain enumeration |
| `dnsx` | [`dnsx/`](dnsx/AGENTS.md) | Resolve, brute-force, and filter DNS |

Vulnerability discovery

| Tool | Directory | Job |
|---|---|---|
| `nuclei` | [`nuclei/`](nuclei/AGENTS.md) | Template-driven CVE and misconfig scanning |
| `ffuf` | [`ffuf/`](ffuf/AGENTS.md) | Fuzzing: paths, parameters, vhosts |
| `feroxbuster` | [`feroxbuster/`](feroxbuster/AGENTS.md) | Recursive content discovery |
| `dalfox` | [`dalfox/`](dalfox/AGENTS.md) | XSS scanning and verification |
| `commix` | [`commix/`](commix/AGENTS.md) | OS command injection |
| `arjun` | [`arjun/`](arjun/AGENTS.md) | Hidden HTTP parameter discovery |
| `wafw00f` | [`wafw00f/`](wafw00f/AGENTS.md) | WAF fingerprinting |
| `testssl.sh` | [`testssl.sh/`](testssl.sh/AGENTS.md) | TLS protocol, cipher, certificate audit |

Code, secrets, containers

| Tool | Directory | Job |
|---|---|---|
| `trufflehog` | [`trufflehog/`](trufflehog/AGENTS.md) | Verified secret scanning of repos and filesystems |
| `trivy` | [`trivy/`](trivy/AGENTS.md) | Image, filesystem, IaC, and dependency CVEs |

Exploitation and credentials

| Tool | Directory | Job |
|---|---|---|
| `metasploit` | [`metasploit/`](metasploit/AGENTS.md) | Exploit modules, payload generation, sessions |
| `impacket` | [`impacket/`](impacket/AGENTS.md) | SMB, Kerberos, LDAP, WMI protocol tooling |
| `netexec` | [`netexec/`](netexec/AGENTS.md) | Credential validation and host enumeration |
| `hashcat` | [`hashcat/`](hashcat/AGENTS.md) | Offline hash cracking (CPU via OpenCL) |
| `john` | [`john/`](john/AGENTS.md) | crypt(3)-family cracking — the narrow case hashcat handles badly |
| `hydra` | [`hydra/`](hydra/AGENTS.md) | Online credential attacks against a live service |
| `sqlmap` | [`sqlmap/`](sqlmap/AGENTS.md) | SQL injection detection and exploitation |
| `nmap` | [`nmap/`](nmap/AGENTS.md) | Port, service, and NSE script scanning — the input to everything else |

Traffic and replay

| Tool | Directory | Job |
|---|---|---|
| `mitmproxy` | [`mitmproxy/`](mitmproxy/AGENTS.md) | HTTP(S) interception and rewriting |
| `scapy` | [`scapy/`](scapy/AGENTS.md) | Packet crafting and replay |
| `tshark` | [`tshark/`](tshark/AGENTS.md) | Capture analysis and protocol dissection |

## Rules that apply to every tool here

1. **Authorization first.** These are offensive tools. Run them only against
   targets Greg has explicitly confirmed for the current engagement. If a
   target's authorization is unclear, it is unauthorized. Scope expansion —
   a new host, a new technique, a new network path — needs explicit human
   confirmation before the first packet, not after.
2. **Everything leaves through the VPN.** The agent has one non-loopback
   interface: the WireGuard tunnel in the shared network namespace. That is
   the containment, and it applies to every tool in this directory without
   exception. Do not attempt to route around it, and do not assume a tool's
   own proxy settings are what is protecting the home IP.
3. **Prefer JSON output.** Every tool here can emit JSON or JSONL. Parse it
   with `jq` rather than reading human-formatted text — the formats are
   stable, the prose formats are not.
4. **Rate-limit by default.** Start with conservative concurrency
   (`-c 10`-`25`, `-rate`/`-rl` where available) and raise it only when the
   target is known to tolerate it. A self-inflicted denial of service on
   Greg's own service is still an outage.
5. **Write findings down.** Results belong in the shared working directory
   (`/working`, host `/home/user/pen/working`), not just in the transcript.
   Raw tool output goes to a file; judgement goes in the findings note.
6. **The audit trail is not optional.** Every LLM request already goes
   through the logging proxy. Tool output that supports a finding should be
   saved to `/working` so the evidence is reproducible independently of the
   conversation.

## Conventions used in these docs

- `$TARGET` is the authorized host or URL, e.g. `https://memair.example`.
- `$WORK` is a per-engagement directory, e.g. `/working/engagements/memair`.
  Create it before the first scan and keep every artifact underneath it.
- `WORDLISTS=/opt/wordlists/SecLists` (the upstream SecLists release, pinned
  at image build; `/opt/wordlists/current` is the same tree by symlink).
- Commands are shown as they should be run in the agent's shell (root, no
  `sudo`). Where a tool needs a TTY, the doc says so explicitly — the agent's
  shell has none.

## Chaining

The tools are designed to hand off to each other through line-oriented files,
which is why each one can read targets from stdin:

```
naabu -host $TARGET -silent            # ports
  | httpx -silent -json                # live web services + tech
  | jq -r 'select(.tech[]? | test("nginx|rails|go")) | .url'
  | nuclei -silent -jsonl               # CVE and misconfig matches
  | jq -c '{t: .info.severity, n: .info.name, u: .matched-at}'
```

```
subfinder -d example.com -silent
  | dnsx -silent -a -resp
  | httpx -silent -ports 80,443,8080 -json
  | tee $WORK/live-hosts.jsonl
```

```
katana -u $TARGET -jc -d 3 -silent
  | feroxbuster --stdin -q
```
