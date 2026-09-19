# Choosing a tool, and applying the decision

What the agent container carries, why each tool earned its place, and which
capabilities were deliberately left out. Read this before adding a tool; read
[`README.md`](README.md) for the mechanics of doing so.

The list below is the current state, not a wish list. Every tool named as
adopted is installed by `tools/<name>/install.sh`.

## The three tests

Every candidate is assessed on these, in order.

1. **Is the capability already covered?** The platform wants one good tool per
   capability, not three. A tool that duplicates an existing one is a maintenance
   cost and a source of conflicting output formats. Overlap is acceptable only
   when the tools answer genuinely different questions — ffuf and feroxbuster
   both do content discovery, but one is for targeted fuzzing and the other for
   mapping a whole tree.
2. **Is it maintained?** Last commit and last release, checked against the
   project's own release history. Abandoned tools are a liability: they miss new
   CVEs, break on new Python and Ruby runtimes, and their output stops matching
   current server behaviour. `dirb` is the standing example — kept only for its
   bundled wordlists and documented as legacy.
3. **Can it run unattended, as root, with machine-readable output?** The
   consumer is an agent, not a human at a terminal. Interactive TUIs and tools
   that need a browser or a wireless radio are worth much less here than they are
   in a human's toolkit.

A fourth test applies to anything that *sends* traffic: **is this a scope
change?** Adding a capability broadens the attack surface the platform can reach.
Per the platform's *do not use initiative* principle, that is Greg's decision,
not the agent's.

## Where the flag list comes from

Package availability was checked against the Debian bookworm binary index (the
image base) rather than assumed. Bookworm is thin for this domain: of the tools
here, few arrive as usable Debian packages, and most come as upstream releases,
`.deb`s, or Python packages. That is not the distro's failure — Debian ships what
is stable, and security tooling moves too fast for a two-year release cycle.

Two consequences that matter when adding a tool:

- **A Debian package may be years behind upstream.** testssl.sh is the worked
  example: bookworm ships 3.0.8 against upstream 3.2.4, and for a tool whose
  whole job is telling you an obsolete TLS configuration is unsafe, that
  difference is disqualifying. Take the upstream release.
- **An old Debian package has old flags.** gobuster in bookworm is 3.5.0, which
  predates the 3.7 CLI rework: no JSON output, no `--rate`, different `-p`
  semantics. Documenting from the current upstream README would produce commands
  that error. Always verify flags against the artifact you actually install.

## Capability map

One tool per capability, with the reason it is the one.

### Vulnerability scanning

| Tool | Version | Install | Why this one |
|---|---|---|---|
| `nuclei` | 3.11.1 | upstream release | A large community template library covering CVEs, default credentials, misconfiguration and exposed panels, with JSONL output and per-template severity filtering. The only scanner in this class that is both broad and cheap per request. Templates are baked at build time, so runtime needs no download. |

`nikto` was rejected: it overlaps nuclei's misconfiguration and
outdated-component checks and adds little. `wpscan` was rejected as
WordPress-specific — none of the target projects are WordPress. `zaproxy` was
rejected as an agent-facing tool: its value is the desktop UI, and its automated
scan is heavier and less precise than nuclei's templates. Revisit only if a
target needs authenticated spidering that `katana` cannot do.

### Reconnaissance and attack-surface mapping

| Tool | Version | Install | Why this one |
|---|---|---|---|
| `httpx` | 1.12.0 | upstream release | The probing layer that turns hosts into targets: status, title, tech stack, TLS details, JSON output, high concurrency. Nothing else does this at this breadth. |
| `katana` | 1.7.0 | upstream release | Crawler that executes JavaScript, so it finds routes in SPA targets a plain link-follower misses. Feeds nuclei and ffuf. |
| `subfinder` | 2.16.0 | upstream release | Passive subdomain enumeration from public sources. One binary, no API keys required for the default sources. |
| `dnsx` | 1.3.1 | upstream release | The DNS resolver/brute-forcer paired with subfinder; also does wildcard filtering, which is what keeps enumerated results honest. |
| `naabu` | 2.6.1 | upstream release | Fast port discovery with a Go-native SYN path. Distinct from `masscan`: masscan is stateless and fastest over wide ranges, naabu handles host lists and pipes into httpx/nuclei without file shuffling. |
| `nmap` | bookworm | `apt` | Service/version detection, OS fingerprinting and NSE. Root uid is deliberate — SYN and UDP scans need raw sockets. |
| `masscan` | bookworm | `apt` | Asynchronous scanning of very large address spaces. Not a replacement for nmap: it finds ports, it does not characterise services. |
| `gobuster` | bookworm 3.5.0 | `apt` | Brute-force enumeration with a mode per target type, including vhost discovery — the one mode nothing else here covers well. |
| `whatweb` | bookworm 0.5.5 | `apt` | Web technology fingerprinting with ~1,800 plugins and per-plugin evidence. |
| `wafw00f` | 2.4.2 | PyPI | WAF fingerprinting. Cheap, and it changes how hard a scan should push. |

`amass` was rejected as heavier, slower, and partly redundant with
subfinder+dnsx at this scale. `bbot` was rejected as an orchestration framework
over the same tools — worth revisiting only if the platform wants scheduled,
multi-stage recon campaigns.

### Web application testing

| Tool | Version | Install | Why this one |
|---|---|---|---|
| `ffuf` | 2.3.0 | upstream release | The standard fuzzer: content discovery, vhost discovery, arbitrary `FUZZ` placement. Single static binary, JSON output, `-rate`/`-p` controls. |
| `feroxbuster` | 2.13.1 | upstream release | Recursive content discovery that follows links and handles redirects out of the box. Kept alongside ffuf deliberately: ffuf for targeted fuzzing, feroxbuster for "map the whole tree". |
| `commix` | 4.1 | upstream source | Command-injection detection. Nothing else covers OS command injection, which is the highest-impact class for shell-out code paths. **Not from PyPI** — the package published under that name is an unrelated installer stub. |
| `dalfox` | 3.2.3 | upstream `.deb` | XSS scanning and verification with JSON output, now via the `oxc` JavaScript parser rather than a headless browser. Nuclei's XSS templates are pattern matches; dalfox drives the payloads through a parser. |
| `arjun` | 2.2.7 | PyPI | HTTP parameter discovery — the hidden parameters a crawler cannot see and ffuf cannot guess. |
| `sqlmap` | bookworm | `apt` | SQL injection detection and enumeration. |
| `dirb` | bookworm | `apt` | **Legacy.** Single-threaded, unmaintained, no JSON, TLS verification off by default. Installed for its server-specific `vulns/*` wordlists, not as a discovery tool. Prefer gobuster/ffuf/feroxbuster. |

### Client-side testing and the browser

| Tool | Version | Install | Why this one |
|---|---|---|---|
| `browser` | Playwright 1.63.0 / Chromium 153 headless shell | PyPI + `playwright install --only-shell` | A drivable browser for the class of testing nothing else here can do: DOM sinks that only fire in a real engine, postMessage and prototype-pollution paths, SPA routes that exist only after hydration, sessions held in localStorage, and screenshots as evidence. It also supplies `/usr/local/bin/chromium`, which is the browser `katana -hl -sc`, `httpx -ss -system-chrome` and `nuclei -headless -sc` resolve through go-rod's `LookPath()`. |

Before this, three tools documented a headless capability that no one had ever
exercised; the shared libraries were installed and the browser was assumed. The
replacement is a pinned browser plus a documented `-sc` path for each consumer.

`chrome-devtools-mcp` was rejected: Google documents root as unsupported, its
`--headless` defaults to false, and it reports usage statistics and may send
trace URLs to a third-party API by default — an egress path a fail-closed
platform should not acquire for a coding-assistant tool. `agent-browser` was
rejected: it downloads its own Chrome for Testing, ships cloud-provider backends
that would be a second egress path, and is built for desktops with a UI. The
third-party `dsh-*` browser plugins are unaudited single-maintainer packages and
are not a delivery route this platform takes.

### API testing (schema-driven, GraphQL, tokens, WebSocket)

| Tool | Version | Install | Why this one |
|---|---|---|---|
| `schemathesis` | 4.27.4 | PyPI | Property-based testing from an OpenAPI or GraphQL schema. Nothing else here reads a spec and generates requests from it; JSON/JUnit/NDJSON/HAR reports. |
| `graphql-cop` | tag 1.16 | upstream source | GraphQL misconfiguration and DoS-class checks (alias and batch overloading, field duplication, introspection, GraphiQL exposure, field suggestions) with JSON output and reproduction cURLs. |
| `clairvoyance` | 2.5.5 | upstream source | Recovers a GraphQL schema through field-suggestion errors when introspection is disabled. Answers a different question from graphql-cop: what is the schema, versus what is wrong with the endpoint. |
| `jwt_tool` | 2.3.0 | upstream source | JWT validation, forging and tampering: `alg:none`, null signature, key confusion, JWKS spoofing, claim tampering, dictionary attacks. Nothing else here covers token structure at all. |
| `oauth2c` | 1.21.0 | upstream release | Obtains tokens across the OAuth2/OIDC grants, which is what the authenticated-API work needs before any scanner can reach behind a login. |
| `websocat` | 1.14.1 | upstream release | Scripted WebSocket framing and relay. There is no standard CLI WebSocket fuzzer, so this plus a small client is the workflow. |

`graphw00f` was left out as fingerprinting that adds little over what
identifier-in-response checks already show. `InQL` was rejected as Burp-only.
`GraphQLmap` and `jwtXploiter` are abandoned. `RESTler` answers a genuinely
different question (stateful operation sequences) but needs Python 3.12 plus a
.NET 8 toolchain built from source; revisit only if sequence testing is needed.

### TLS and transport

| Tool | Version | Install | Why this one |
|---|---|---|---|
| `testssl.sh` | 3.2.4 | upstream source | Protocol, cipher and certificate assessment against a live endpoint with JSON output. The one tool that answers "is this TLS actually safe?" |
| `tshark` | bookworm | `apt` | Protocol dissection of captures into fields, statistics and objects. |
| `scapy` | 2.7.0 | PyPI | Packet crafting and replay — the tool for testing a parser with input a normal client would never send. Installed from PyPI rather than bookworm's `python3-scapy` (2.5.0), which would also be importable only under the system interpreter. |

`sslyze` and `sslscan` were rejected as duplicates of testssl.sh; sslscan's
Debian version is three years behind, which for a TLS-era-sensitive tool is
disqualifying.

### Evidence and reporting

| Tool | Version | Install | Why this one |
|---|---|---|---|
| `gowitness` | 3.2.0 | upstream release | Screenshots a list of URLs into JSONL/CSV/SQLite for a report. Uses its own Chrome rather than the Playwright build, because it wants a `chrome` binary path and not a headless shell; see its `AGENTS.md`. |

`aquatone` was rejected as archived. `EyeWitness` overlaps gowitness with far
lower activity.

### Credential access and exploitation

| Tool | Version | Install | Why this one |
|---|---|---|---|
| `hashcat` | bookworm | `apt` | Offline cracking of every non-`crypt(3)` hash: NTLM, NetNTLM, Kerberoast, AS-REP, database and file formats. PoCL supplies the OpenCL ICD; this is CPU-only. |
| `john` | bookworm | `apt` | Core build: `crypt(3)` formats only, no `*2john` helpers. Kept because it is the fastest path for `/etc/shadow`, and `unshadow`/`unique` are the standard preparation helpers. Everything else belongs to hashcat. |
| `hydra` | bookworm | `apt` | Online password guessing against network services. The most consequential tool here: every attempt is a real logon that can lock an account. |
| `impacket` | PyPI | PyPI | Protocol-level Windows work: credential dumping, Kerberos roasting, remote execution, SMB tooling. |
| `netexec` | v1.5.1 | git tag | Credential validation and host enumeration across SMB/LDAP/WinRM/SSH/MSSQL/RDP and more, with a per-protocol SQLite workspace. |
| `pypykatz` | 0.6.13 | PyPI | Offline parsing of Windows credential stores: LSASS minidumps, registry hives, DPAPI, NTDS. |
| `metasploit` | Rapid7 apt | `apt` (omnibus `.deb`) | The exploitation framework, and the `searchsploit` replacement (Exploit-DB lookups via `search edb:`). |
| `mitmproxy` | 11.0.0 | PyPI | HTTP(S) interception that can both read and rewrite traffic a client trusts. Pinned to 11.0.0 because 11.1.0+ requires Python ≥3.12. |

### Source, secret and container scanning

| Tool | Version | Install | Why this one |
|---|---|---|---|
| `trufflehog` | 3.97.5 | upstream release | Credential detection across git history, filesystems and images, with (optional) verification against the issuing service. Disproportionately valuable here: a leaked key in a repo is a breach that no amount of external scanning finds. |
| `trivy` | 0.74.0 | upstream `.deb` | OS packages, language lockfiles, IaC, images, secrets and licences in one binary. Audits the platform's own image without a container runtime. |

### Data

| Tool | Version | Install | Why this one |
|---|---|---|---|
| `words` | SecLists 2026.1 | upstream tarball | The wordlists every discovery tool reads, pinned by tag so a finding is reproducible, at `/opt/wordlists/current`. |

`Assetnote wordlists` were considered and left out: the repository carries no
tagged release, and its generator now publishes the lists to object storage
outside the git history, so there is no immutable artifact to pin by hash. A
wordlist that cannot be reproduced is worse than the one already here.

### Base image, not tools

`curl`, `wget`, `git`, `jq`, `yq`, `ripgrep`, `file`, `less`, `tree`, `vim-tiny`,
`procps`, `iproute2`, `lsof`, `psmisc`, `tcpdump`, `netcat-openbsd`, `socat`,
`traceroute`, `mtr-tiny`, `whois`, `dnsutils`, `openssl`, `unzip`, `p7zip-full`,
`dos2unix`, `libxml2-utils`, `python3` + `build-essential`.

The slim base ships no `procps`, no `iproute2` and no `python3`. An agent that
cannot run `uptime`, `ps`, `ip` or a Python script is crippled for diagnostics,
so the appliance carries a curated set rather than the distro catalogue.

**The rule for the boundary:** if a package serves the appliance as an operating
system, it belongs in the Dockerfile's base block. If it is a named pentest
capability, it belongs in `tools/<name>/` with its own `install.sh` and
`AGENTS.md`. Diagnostics utilities (`whois`, `traceroute`, `tcpdump`) are base;
scanners with docs directories are tools. The browser is a tool rather than a
base package for the same reason: it is a capability the agent points at a
target, and it needs version pinning and operator documentation.

## Deliberately absent

- **Wireless tooling** (`aircrack-ng`, `kismet`): needs a radio, and the
  container has none.
- **A browser with a visible UI, or a virtual display** (Xvfb, a desktop
  Chromium): everything here is headless, and a screenshot is a file, not a
  window. `tools/browser` covers the headless case.
- **Anything requiring a Docker socket.** There is none, deliberately: trivy
  scans images over the network or from a tar, and `rootfs /` covers this
  container.
- **HTTP request smuggling tooling.** The commonly recommended implementations
  (`smuggler.py`, `h2csmuggler`) have had no commits in four to five years and
  have never cut a release. The maintained HTTP/2 desync work
  (`http2smugl`, `h2spacex`) is worth revisiting if a target terminates HTTP/2
  and the engagement covers protocol-level attacks — the current template set
  covers the CL.TE/TE.CL basics.
- **Orchestration frameworks** (bbot, recon-ng): they wrap tools already present
  and add a scheduling layer the platform does not need yet.

## Adding one

The mechanics — the four install shapes, the per-tool venv rule, the
documentation standard and the verification steps — are in
[`README.md`](README.md). Three points from this document that bear on it:

1. **Confirm the capability before writing the install path.** New tool, new
   target, new technique: scope expansion requires Greg's explicit confirmation.
2. **One venv per Python tool.** A shared venv forces unrelated tools into one
   dependency resolution. The previous image carried a comment block explaining
   that `bcrypt` had to be held below 4.1 for mitmproxy, that `dploot` had to be
   held below 4 for NetExec, and that impacket could not be pinned at all because
   NetExec needed an unreleased revision. In separate venvs each constraint lives
   in the one tool it belongs to. If you catch yourself writing a
   dependency-conflict comment in a shared list, that is the signal the tool
   needs its own venv.
3. **Record the tool here when you add it** — which capability it owns, and what
   it beat. The rejected candidates are as useful as the accepted ones when
   someone proposes the same tool again in six months.
