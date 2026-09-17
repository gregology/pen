# Agent Toolset Research

What the `agent` container should carry, why each tool earns its place, and
which capabilities were deliberately left out. This is the *why* companion to
the tool list in `images/agent/Dockerfile`; versions were resolved on
2026-09-17 and should be re-pinned when the image is next built.

**Status: adopted.** Everything recommended in the "Recommended toolset"
section below ships in `pen/agent:v1`, with three deviations found during the
build and recorded in `IMPLEMENTATION-V1.md` — `bcrypt<4.1` and `dploot<4` pins
for mitmproxy and NetExec respectively, and a renamed venv `httpx` console
script so ProjectDiscovery's `httpx` is not shadowed on PATH. Per-tool usage
documentation lives in `tools/`.

## Method

Candidates were assessed on three tests, in order:

1. **Is the capability already covered?** The platform wants one good tool per
   capability, not three. A tool that duplicates an existing one is a
   maintenance cost and a source of conflicting output formats.
2. **Is it maintained?** Last commit and last release were checked against the
   project's own release history. Abandoned tools are a liability: they miss
   new CVEs, break on new Python/Ruby runtimes, and their output stops matching
   current server behaviour.
3. **Can it run unattended, as root, with machine-readable output?** The
   consumer is an agent, not a human at a terminal. Interactive TUIs (ZAP's
   desktop, `wpscan`'s prompt-driven flows) and tools that need a browser or a
   wireless radio are worth much less here than they are in a human's toolkit.

Package availability was checked against the Debian bookworm binary index
(the image base) rather than assumed. Bookworm is thin for this domain: of the
tools below, only three (`wafw00f`, `tshark`, `scapy`) are installable as
Debian packages at a usable version, and the rest arrive as upstream releases,
`.deb`s, or Python packages. This is not the distro's failure — Debian ships
what is stable, and security tooling moves too fast for a two-year release
cycle.

## Current capability gaps

The V1 agent carries: `nmap`, `masscan`, `whatweb`, `dirb`, `gobuster`,
`sqlmap`, `hydra`, `john`, `tcpdump`, `nc`, `socat`, `ssh`, `curl`, `dig`,
`whois`, `git`, `gcc`, `python3`, `jq`, `rg`.

Against the projects this platform exists to test — Rails (`memair`), Go CLI
(`sctx`), mesh/VPN tooling (`MeshBridge`, `tank`), static and browser JS
(`tank`, `gregology.github.io`), self-hosted services — the gaps are:

- **No vulnerability scanner.** `nmap`'s NSE scripts and `whatweb` banner
  matching are fingerprinting, not vulnerability detection. Nothing checks a
  live HTTP service against a CVE corpus.
- **No HTTP probing or crawling layer.** There is no way to take a list of
  hosts and answer "which of these speak HTTP, what do they claim to be, and
  what URLs exist?" — the step that turns a port list into a target list.
- **Weak content discovery.** `dirb` is unmaintained and single-threaded;
  `gobuster` is fine for directories but does nothing else.
- **Injection coverage stops at SQL.** No command injection, no XSS, no
  parameter discovery — three of the most common bug classes in a Rails or Go
  web app.
- **No TLS assessment.** Cipher suites, protocol versions, and certificate
  chains are unaudited.
- **No exploitation or post-exploitation capability.** Nothing turns "this
  service is version X" into a working proof, and nothing validates a found
  credential against a remote service.
- **No secret scanning.** Disproportionately valuable here: a dozen of the
  local projects are git repos, and a leaked key in a repo is a breach that no
  amount of external scanning finds.
- **No container/IaC scanning.** The platform is itself Dockerized and deploys
  from compose files; image CVEs and compose misconfiguration are in scope.

## Recommended toolset

Sizes are the installed cost in the image. Everything is Linux amd64.

### 1. Vulnerability scanning

| Tool | Version | Install | Why this one |
|---|---|---|---|
| `nuclei` | 3.11.1 | upstream release (Go) | A large community template library covering CVEs, default credentials, misconfiguration, and exposed panels, with `-jsonl` output and per-template severity filtering. It is the only scanner in this class that is both broad and cheap to run per-request. Ships with `nuclei -update-templates`; templates are baked at image build so runtime needs no download. |

`nikto` was rejected despite being maintained: it overlaps nuclei's
misconfiguration and outdated-component checks and adds little beyond them.
`wpscan` was rejected as WordPress-specific — none of the target projects are
WordPress. `zaproxy` (ZAP) was rejected as an agent-facing tool: its value is
the desktop UI and manual browsing, and its automated scan is heavier and less
precise than nuclei's templates. Revisit if a target needs authenticated
spidering that `katana` cannot do.

### 2. Reconnaissance and attack-surface mapping

| Tool | Version | Install | Why this one |
|---|---|---|---|
| `httpx` | 1.12.0 | upstream (Go) | The probing layer that turns hosts into targets: status, title, tech stack, TLS details, `-json` output, high concurrency. Nothing else does this at this breadth. |
| `katana` | 1.7.0 | upstream (Go) | Crawler that executes JavaScript, so it finds routes in the SPA parts of `tank` and `gregology.github.io` that a plain link-follower misses. Feeds nuclei and ffuf. |
| `subfinder` | 2.16.0 | upstream (Go) | Passive subdomain enumeration from public sources. One binary, no API keys required for the default sources. |
| `dnsx` | 1.3.1 | upstream (Go) | The DNS resolver/brute-forcer paired with subfinder; also does wildcard filtering, which is what keeps enumerated results honest. |
| `naabu` | 2.6.1 | upstream (Go) | Fast port discovery with a Go-native SYN path. Distinct from `masscan` (already present): masscan is stateless and fastest over wide ranges, naabu handles host lists and pipes into httpx/nuclei without file shuffling. |

`amass` (5.1.1) was rejected: it is heavier, slower, and its OWASP-maintained
rewrite is partly redundant with subfinder+dnsx at this scale. `bbot` (3.0.2)
was rejected as an orchestration framework over the same tools — worth
revisiting only if the platform wants scheduled, multi-stage recon campaigns.

### 3. Web application testing

| Tool | Version | Install | Why this one |
|---|---|---|---|
| `nuclei` (above) | — | — | Also the web-vuln scanner: CVEs, exposures, misconfig, default logins. |
| `ffuf` | 2.3.0 | upstream (Go) | The standard fuzzer: content discovery, virtual-host discovery, and arbitrary `FUZZ` placement in headers/body/parameters. Single static binary, JSON output (`-of json`), and `-rate`/`-p` controls so it does not hammer a target. |
| `feroxbuster` | 2.13.1 | upstream (.deb) | Recursive content discovery that follows links and respects robots/redirects out of the box — the recursive case is awkward in ffuf (needs `-recursion` plus careful filters) and absent from gobuster. Kept alongside ffuf deliberately: ffuf for targeted fuzzing, feroxbuster for "map the whole tree". |
| `commix` | 4.1 | upstream source | Command-injection detection and exploitation. Nothing else covers OS command injection, which is the highest-impact bug class for `MeshBridge`'s shell-out code paths and any service that shells to `ip`/`wg`. |
| `dalfox` | 3.2.3 (linux-x86_64 `.deb`) | upstream (.deb) | DOM-aware XSS scanning with a headless-browser mode and JSON output. Nuclei's XSS templates are pattern matches; dalfox actually drives the payloads through a parser. |
| `arjun` | 2.2.7 | upstream source | HTTP parameter discovery — finds the hidden query/body parameters that a crawler cannot see and that `ffuf` cannot guess without a wordlist. Its last upstream release predates the others; it is stable rather than abandoned, and its syntax (`arjun -u URL -oT json`) is unchanged. |
| `wafw00f` | 2.2.0 (Debian) | `apt` | WAF fingerprinting. Cheap, and changes how hard a scan should push. Debian's version (2.2.0) lags upstream 2.4.2 by two years of WAF signatures; take the PyPI release instead if a target sits behind a WAF. |

`sqlmap` (already present) remains the SQLi tool. `dirb` and `gobuster`
(already present) are superseded by feroxbuster and ffuf respectively but stay
installed: gobuster's `vhost` mode is a convenient fallback and dirb costs
nothing.

### 4. TLS and transport

| Tool | Version | Install | Why this one |
|---|---|---|---|
| `testssl.sh` | 3.2.x upstream (bookworm ships 3.0.8) | upstream or `apt` | Protocol/cipher/certificate assessment against a live endpoint with `--jsonfile`. The one tool that answers "is this TLS actually safe?" for the self-hosted services. |

`sslyze` (Python) and `sslscan` (Debian 2.0.7) were rejected as duplicates of
testssl.sh; `sslscan`'s Debian version is three years behind, which for a
TLS-era-sensitive tool is disqualifying.

### 5. Exploitation and credential validation

| Tool | Version | Install | Why this one |
|---|---|---|---|
| `metasploit-framework` | 6.4.x nightly | Rapid7 apt repo (official) | The reference exploitation framework: thousands of modules spanning network services, web apps, and post-exploitation, with `msfconsole -x` for scripted runs, `msfvenom` for payload generation, and module-level documentation. Nothing else covers "prove this CVE is exploitable" as broadly. |
| `impacket` | 0.13.1 (PyPI) | pip | Python implementations of SMB, MSRPC, LDAP, Kerberos, and WMI. Present in bookworm as `python3-impacket` 0.10.0, which is three years stale — install the current release from PyPI instead. `secretsdump`, `smbclient.py`, `psexec.py`, and `ntlmrelayx.py` are the workhorses. |
| `netexec` | 1.5.1 | pip from git | The maintained successor to CrackMapExec (whose upstream is archived). SMB/WinRM/LDAP/MSSQL/SSH credential validation and enumeration with `--json` output — the fastest way to answer "does this credential work anywhere else?" |
| `hashcat` | 6.2.6 | `apt` + `ocl-icd-libopencl1`, `pocl-opencl-icd` | GPU-class cracking that also runs on CPU via PoCL (the OpenCL ICD packages are required — hashcat aborts without an ICD even for CPU-only work). Chosen over `john` (already present) for hash-mode breadth and rule engine, with john retained for its superior handling of exotic and password-protected-file formats. |

`medusa` and `ncrack` were rejected as duplicates of `hydra` (already
present). `patator` was rejected: more flexible than hydra, but its Python
dependencies and less predictable CLI make it a worse default for an agent.
`searchsploit`/`exploitdb` was rejected for bookworm (no package); look up
exploits through Metasploit's `search` instead. `sliver` (1.7.7) was rejected
for V1 scope: a full C2 framework implies long-term persistence and beaconing,
which is not what "harden Greg's own projects" needs, and it would be the
single largest binary in the image.

### 6. Source, secret, and container scanning

Directly relevant: a dozen local projects are git repos and the platform
deploys container images built from compose.

| Tool | Version | Install | Why this one |
|---|---|---|---|
| `trufflehog` | 3.97.5 | upstream (Go) | Scans git history **and** filesystems for live, verified credentials — it re-validates the key against the issuing service, so its findings are actionable rather than entropy guesses. |
| `trivy` | 0.74.0 | upstream (.deb) | One binary covering container-image CVEs, filesystem/package CVEs, IaC and compose misconfiguration, and embedded secrets. Directly applicable to `pen` itself and to anything Greg builds locally. |

`gitleaks` (8.30.1) was rejected as a duplicate of trufflehog: same job, less
verification. `grype`/`syft` were rejected as duplicates of trivy's scan
output; revisit only if a signed SBOM pipeline becomes a requirement.
`semgrep` was rejected on licence grounds: the engine is LGPL-2.1, but the
rule packs that give it value are under the proprietary Semgrep Rules License
v1.0, which restricts use to the licensee's own code and internal business
purposes. Baking it in would make the agent's licence posture depend on how
each target repo is classified. `pwntools`, `gdb`+`pwndbg`, `radare2`, and
`ropper` were rejected: binary exploitation and reverse engineering are a
different discipline from remote surface testing, and the two compiled targets
here (`sctx`, `MeshBridge`) are Go/Python services, not stripped binaries.

### 7. Interception, replay, and packet craft

| Tool | Version | Install | Why this one |
|---|---|---|---|
| `mitmproxy` (`mitmdump`) | 11.0.0 | pip (pinned) | Scriptable HTTP(S) interception with `--save-stream-file`, replay via `mitmproxy`'s addons, and a Python API for custom manipulation. 11.0.0 is the last release supporting Python 3.11 (11.1.0 moved to ≥3.12); pin it, or bump the base image (see below). |
| `scapy` | 2.5.0 (Debian) | `apt` | Packet crafting and replay from Python. `tcpdump` (present) observes; scapy generates malformed and hand-crafted traffic, which is how protocol parsers in `MeshBridge` get tested. |
| `tshark` | 4.0.17 (Debian) | `apt` | Wireshark's CLI with `-T json` and display filters. Turns captured pcaps into agent-readable findings without a GUI. |

`bettercap` (2.32.0 in bookworm) was rejected for now: its headline features
(ARP/DNS spoofing, on-path interception) require being on the same L2 segment
as the victim, which the agent's VPN-only egress does not provide. Revisit
only if the platform gains an internal-network vantage point. `responder`,
`dsniff`, `ettercap`, and `sslstrip` fail the same test, and `sslstrip`'s
upstream is dead.

### 8. Local-network and wireless

Not included, and the reason is structural rather than a judgement on the
tools: the agent's only non-loopback interface is the WireGuard tunnel, and a
container has no radio. `aircrack-ng` on a monitor-mode interface is
impossible here without a scope change (host network plus a passed-through
adapter). SAML/SNMP/SMB LAN enumeration is likewise blind from the VPN exit.
If internal-network testing becomes a goal, that is a topology change — a new
vantage container on the LAN, not more tools in this one.

## Base image note

The image base is `node:24-bookworm-slim` (Debian 12, Python 3.11.2). Two
recommended tools want a newer Python: `mitmproxy` 12.x and `certipy-ad` 5.x
(AD CS, not recommended above) both require ≥3.12. Debian 13 (`trixie`) ships
Python 3.13.5 and also bumps `sqlmap`, `hydra`, `nmap`, `gobuster`, `sslscan`,
and `testssl.sh` within `apt`. Bumping the base is a cheap change that removes
the pinning friction, but it is a change to a live, verified image and should
be done deliberately with the full verification checklist re-run, not as a
side effect of adding tools.

## Estimated image cost

| Group | Installed |
|---|---|
| 6 ProjectDiscovery binaries | ~120 MB |
| ffuf, feroxbuster, dalfox, commix, arjun, testssl.sh, trufflehog | ~30 MB |
| trivy | ~150 MB |
| Metasploit + Ruby deps | ~900 MB |
| Python tools (impacket, netexec, mitmproxy, …) | ~150 MB |
| scapy, tshark, hashcat + PoCL, jq/rg/etc. | ~350 MB |
| **Total added** | **~1.7 GB** |

Metasploit is the one entry whose cost is worth a second look; dropping it
would keep the image near 1 GB. Nuclei templates and SecLists are the two data
sets to consider: templates (~15 MB) are baked at build time because the
scanner is useless without them, while SecLists (~1.5 GB extracted) should be
a host-mounted directory under `/home/user/pen/` rather than image content,
since wordlists are data that changes independently of the toolchain.
