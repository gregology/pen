# V1 Implementation Plan

Implements the architecture in `DESIGN.md`: three containers (agent,
vpn-gateway, llm-proxy) deployed as a **Portainer stack** from this Git repo.

## Why these implementation choices

- **`network_mode: service:vpn-gateway` for the agent.** The agent shares the
  VPN container's network namespace, so there is no route — misconfigured or
  otherwise — by which agent traffic can reach the internet except through the
  gateway's interfaces. This is stronger than routing or proxy env vars, which
  individual pentest tools may ignore. The tradeoff (agent's ports are
  published on the gateway) is minor.
- **Custom vpn-gateway image rather than gluetun.** Gluetun provides an
  excellent kill switch but its control API cannot hot-swap between a dozen
  WireGuard configs, which is a core requirement. A minimal image
  (Alpine + `wireguard-tools` + a small control API + iptables kill switch)
  is small, auditable, and does exactly what we need. If gluetun adds config
  rotation later, revisit.
- **Fail-closed via iptables in the shared namespace.** OUTPUT policy drops
  everything except traffic out the tunnel interface, traffic to the sandbox
  network (so the agent can reach llm-proxy and the gateway API), and
  localhost. Because rotation is "down old config, up new config," the kill
  switch — not the tunnel manager — is what guarantees no leak during the gap.
- **LiteLLM as the LLM proxy.** It already solves provider fan-out, key
  custody, and per-request logging, so we don't build a proxy to get an audit
  trail. Full request/response capture goes to an append-only volume the
  agent cannot write to.
- **Host-built images, not Portainer `build:`.** Portainer builds from a
  creation-time snapshot of the repo in its own project directory, so
  image builds through the stack go stale the moment main moves (observed
  in practice: a redeploy overwrote a fresh fix with stale code). The
  house convention from the Portainer runbook applies instead: images are
  built on the host from `/home/user/pen/images/*` and referenced by tag
  with `pull_policy: never`. Secrets live in Portainer stack environment
  variables, never in the repo.

## Repo layout

```
docker-compose.yml          # the Portainer stack
images/
  vpn-gateway/
    Dockerfile              # alpine + wireguard-tools + iptables + api
    entrypoint.sh           # kill switch FIRST, then tunnel, then API
    api.py                  # GET /status, GET /nodes, POST /switch {node}
  agent/
    Dockerfile              # node + pnpm + DSH + baseline pentest tools
    entrypoint.sh
litellm/
  config.yaml               # upstream providers, namespaced model aliases
  custom_callbacks.py       # append-only audit logger -> /logs/audit.jsonl
```

All state lives in host paths under `/home/user/pen/` (bind mounts, not named
volumes, so logs and data are directly accessible on the Portainer host
for backup, rotation, and inspection). These paths sit inside the repo
checkout; `.gitignore` is what keeps secrets and logs out of commits:

```
/home/user/pen/vpn-configs/       # WireGuard .conf files, chmod 600, gitignored — never committed
/home/user/pen/llm-logs/          # audit.jsonl written by the LLM proxy, gitignored
/home/user/pen/dsh-data/          # agent workspace / DSH state, gitignored
```

Note: the bind-mounted `litellm/` config files are absolute host paths,
so the running config comes from the checkout at `/home/user/pen` — keep
that checkout current when deploying via Portainer's Git stack (Portainer's
own clone is not what gets mounted).

## Build order

### 1. vpn-gateway image (`images/vpn-gateway/`)

The security-critical component; build and test it first, alone.

- `entrypoint.sh` applies `killswitch.sh` before anything else runs — the
  no-leak guarantee depends on that ordering. Then it starts the GUI
  forwarder and execs `api.py`.
- The kill switch (`killswitch.sh`) is default-deny OUTPUT in the shared
  namespace. Permitted: loopback, conntrack replies, the `wg+` interfaces,
  the sandbox CIDR, DNS to exactly the pinned resolvers (endpoint
  resolution must work before the first tunnel exists — this leaks only
  the fact that we resolve DNS), and per-endpoint UDP exceptions managed
  by the API (the tunnel's own underlay packets need an explicit rule).
  The control API and GUI ports accept INPUT only from the sandbox and,
  for the GUI, the host — never the tunnel.
- `api.py` owns the tunnel lifecycle, including initial bring-up, so there
  is exactly one tunnel-management code path. Startup order is kill switch
  → API → tunnel (backgrounded): the API serves even while the tunnel is
  down, so `/status` can report the failure and `/switch` can retry.
  Endpoints, authenticated by a shared bearer token:
  - `GET /status` → current node, tunnel state, handshake age, counters.
  - `GET /nodes` → config names found in `/vpn/configs`.
  - `POST /switch {"node": "<name>"}` → replace endpoint exception,
    `wg-quick down`, `wg-quick up`. At every instant egress is the old
    tunnel, the new endpoint only, or nothing.
  Config `DNS=` lines are stripped on activation (wg-quick aborts without
  resolvconf; DNS is pinned in compose instead).
- The GUI forwarder exists because `dsh web` refuses `--host 0.0.0.0` by
  design, and Docker port publishing cannot reach a loopback-bound
  process. dsh listens on loopback :3090; `socat` bridges the published
  :3080 to it (the ports must differ — a wildcard :3080 forwarder would
  collide with any loopback :3080 listener). The kill switch scopes
  :3080 to host and sandbox traffic.
- Healthcheck: `curl -f http://localhost:8080/status` (tokened). The
  agent's `depends_on: service_healthy` means the agent never starts
  before the kill switch is live.

### 2. llm-proxy

- `litellm/config.yaml` defines four upstream providers, all spoken to
  as OpenAI-completions-compatible APIs:
  - **kimi-coding** (k3, k3-256k, kimi-for-coding, kimi-for-coding-highspeed)
  - **zai** (glm-5.3, glm-5.3-flash, glm-5.3-highspeed)
  - **deepseek** (deepseek-flash, deepseek-v4-pro)
  - **gaming-rig** — a local server on the LAN (10.0.0.21:8080); reached
    via the egress bridge and the host's route, so this traffic never
    touches the VPN and never leaves the local network. Its long
    `stream_timeout` (30 min) mirrors the DSH config it replaces.
- Model aliases are **namespaced** (`kimi-coding/k3`, `zai/glm-5.3`,
  `gaming-rig/qwen38-27b`, …) because model IDs collide across providers
  (`glm-5.3-flash` exists on both zai and gaming-rig). The agent is
  configured with a single `llm-proxy` provider and uses these aliases
  as model IDs.
- `litellm/custom_callbacks.py` writes every request/response (and
  failure) as one JSON line to `/logs/audit.jsonl`, bind-mounted from
  `/home/user/pen/llm-logs/`. If the log write fails, the request fails —
  unaudited LLM calls are worse than failed ones. Rotation is a host
  concern (logrotate).
- Provider API keys (`KIMI_CODING_API_KEY`, `ZAI_API_KEY`,
  `DEEPSEEK_API_KEY`, `GAMING_RIG_API_KEY`) and `LITELLM_MASTER_KEY`
  come from Portainer stack env. The agent authenticates to the proxy with the master key
  (or a virtual key), so revoking agent access doesn't require rotating
  provider keys.

### 3. agent image (`images/agent/`)

- Base: Node 24 slim + `@deepseek-ai/dsh` installed globally, plus a
  curated toolset in four groups:
  - **system** — procps, net-tools, iproute2, lsof, psmisc, file, less,
    tree, bc, nano, vim-tiny, tzdata, libxml2-utils
  - **network** — iputils-ping, traceroute, mtr-tiny, tcpdump,
    netcat-openbsd, socat, telnet, openssh-client, openssl
  - **assessment** — nmap, masscan, whatweb, dirb, sqlmap, hydra, john,
    gobuster, hashcat (+PoCL), tshark, scapy
  - **dev/build** — git, python3 (+pip, venv), build-essential,
    libssl-dev, jq, yq, ripgrep, fd-find, unzip, zip, p7zip-full,
    xz-utils, dos2unix, curl, whois, dnsutils
  The slim base ships no procps, no iproute2, and no python3, so this list
  is what makes the agent usable for diagnostics at all. Notes: Debian's
  `yq` is the Python jq-wrapper, not the Go implementation (`fd` is
  symlinked from `fdfind` for the same reason `fdfind` is the packaged
  name). `pip install` needs a venv — the system Python is externally
  managed.
- **The pentest toolchain on top of the base** (reasoning in
  `TOOLSET-RESEARCH.md`, per-tool usage in `tools/`):
  - **reconnaissance** — nuclei 3.11.1 (with nuclei-templates 10.4.9 baked
    to `/root/nuclei-templates`), httpx 1.12.0, katana 1.7.0,
    subfinder 2.16.0, dnsx 1.3.1, naabu 2.6.1
  - **web** — ffuf 2.3.0, feroxbuster 2.13.1, dalfox 3.2.3, commix 4.1,
    arjun 2.2.7, wafw00f 2.4.2, testssl.sh 3.2.4
  - **supply chain** — trivy 0.74.0, trufflehog 3.97.5
  - **exploitation** — Metasploit 6.5.3 (Rapid7 apt repo), impacket,
    NetExec 1.5.1, pypykatz
  - **traffic** — mitmproxy 11.0.0
  - **wordlists** — SecLists, pinned by release tag at `/opt/wordlists/SecLists`
  - Everything compiled or scripted is an upstream release with a
    sha256 in the Dockerfile's `ARG`s, verified at build time. Debian
    wins only where its version is current (`tshark`, `scapy`, `hashcat`)
    or where a package is the only sane source. Python tools live in one
    virtualenv (`/opt/pen-venv`) that is first on `PATH`.
- **Three pins and a rename that are load-bearing**, each found by a real
  failure during the build:
  - `mitmproxy==11.0.0` — 11.1.0+ requires Python 3.12; bookworm has 3.11.
  - `bcrypt==4.0.1` — passlib 1.7.4 (imported by mitmproxy at startup)
    probes its bcrypt backend with a >72-byte password, which bcrypt 4.1+
    rejects by raising. Unpinned, every mitmproxy entry point exits at
    import with no usable message.
  - `dploot<4` — NetExec declares `dploot>=3.1.0` with no upper bound;
    dploot 4 moved its SMB module, so the unpinned install produces a
    NetExec whose SMB protocol dies with `ModuleNotFoundError`. Its
    version banner still prints, so only a real run reveals it.
  - The venv's `httpx` console script is renamed `httpx-httpclient`,
    because it otherwise shadows ProjectDiscovery's `httpx` binary on
    `PATH` — two unrelated tools with the same name, and the network
    mapper is the one that has to win. The library stays installed;
    NetExec's dependency chain imports it.
  - `commix` is installed from its upstream release, not PyPI: the
    package published there under that name is an unrelated installer
    stub with no scanner in it.
- `nikto`, `wpscan`, and `exploitdb` remain absent from bookworm and are
  deliberately not baked; the recommended toolset covers their cases.
  If an engagement needs one, add it as a pinned, hash-verified upstream
  release rather than a `pip install` of a name that looks right.
- `john` is Debian's **core** build, not jumbo: crypt(3)-family formats
  only, no `*2john` helpers, no NTLM. Hashcat covers everything else.
- **code-server** (web VS Code), pinned to v4.137.0 and sha256-verified at
  build time. It opens `/working`, binds loopback `:8081`, and stores
  state on the data mount. The gateway forwards `:3081` to it under the
  same iptables rules as the DSH GUI. Login password comes from
  `CODE_SERVER_PASSWORD`; unset, code-server generates one into
  `/home/user/pen/dsh-data/code-server/config.yaml`. Extensions come from
  Open VSX, not Microsoft's marketplace.
- `/working` is the shared working directory (host
  `/home/user/pen/working`): `AGENTS.md`, test notes, and anything Greg
  and the agent both edit. It is the DSH workspace root and the
  code-server folder, so both see the same files. The host directory is
  group 1000 with the setgid bit, and the container runs as `0:1000` with
  `umask 002`, so agent-written files are group-writable — no sudo needed
  on the host side.
- `DSH_PERMISSION_MODE=danger-full-access`: DSH's bubblewrap-backed bash
  sandbox cannot create namespaces inside this container (tested plain,
  `seccomp=unconfined`, `SYS_ADMIN`, `SYS_ADMIN + apparmor=unconfined` —
  all denied; only `--privileged` would work, and that is a worse trade
  than losing an in-container sandbox that the network topology already
  makes redundant). Root uid is kept deliberately: Docker grants no
  ambient capabilities to a non-root process, so a uid change would
  silently cost nmap's SYN/UDP scans and OS detection.
- `settings.seed.yaml` is copied to `$DSH_HOME/settings.yaml` on first
  boot: exactly one provider, `llm-proxy`, with the twelve namespaced
  model aliases. `$DSH_HOME` lives on the host bind mount so the GUI
  persists across rebuilds and Greg can inspect state. The network — not
  this file — is what blocks direct provider access.
- Runs `dsh web --no-open --port 3080` (loopback-only by DSH's design;
  the gateway's forwarder exposes it).
- No `ports:` and no network attachments of its own — `network_mode:
  service:vpn-gateway` is the whole containment story.

### 4. Stack & deployment

1. Clone this repo to `/home/user/pen` on host01 and create the runtime
   directories (WireGuard configs go in `vpn-configs/`, chmod 600 — they
   contain private keys, never commit them):
   `mkdir -p /home/user/pen/{vpn-configs,llm-logs,dsh-data,working}`
2. Build the custom images on the host (re-run after every repo change
   to `images/`):
   `docker build -t pen/vpn-gateway:v1 /home/user/pen/images/vpn-gateway`
   `docker build -t pen/agent:v1 /home/user/pen/images/agent`
3. Create the stack via the Portainer API (repository endpoint, env 16)
   or the UI, compose path `docker-compose.yml`.
4. Set stack environment variables in Portainer:
   `VPN_API_TOKEN`, `LITELLM_MASTER_KEY`, `KIMI_CODING_API_KEY`,
   `ZAI_API_KEY`, `DEEPSEEK_API_KEY`, `GAMING_RIG_API_KEY`,
   `CODE_SERVER_PASSWORD` (new; generate one).
5. Deploy. Note: this Portainer version records the stack with
   `GitConfig: null`, so later compose changes are applied by PUT-ing the
   whole file back (preserving Env), not by "pull and redeploy".
6. Reach the DSH web GUI at `http://10.0.0.10:3080` — published on the
   host's LAN address only (the agent passes `--trusted-host
   10.0.0.10:3080` so the trust fence accepts that authority). Plain-HTTP
   LAN access is not a secure browser context, so parts of the settings
   UI relying on `crypto.randomUUID` may misbehave — a known DSH
   limitation, also seen on dev01.

## Verification checklist (do all before declaring V1 done)

Each test maps to a design guarantee:

| Guarantee | Test |
|---|---|
| No home-IP leak | `docker exec vpn-gateway wg-quick down <cfg>`; from agent, `curl --max-time 5 https://ifconfig.me` must **fail**. |
| Attribution | With tunnel up, agent's `curl https://ifconfig.me` returns the VPN exit IP, never the residential IP. |
| Rotation works | `POST /switch` to each config; `ifconfig.me` after each switch shows the new exit; no leak window (run first test mid-rotation). |
| Containment | Agent cannot reach the egress network or host LAN directly (e.g., `curl` a host-only address must fail); only llm-proxy and the gateway API respond. |
| Audit trail | Run a DSH session against each provider alias; confirm every LLM request/response appears in `/home/user/pen/llm-logs/audit.jsonl`, including ones the agent might prefer to hide. |
| Kill switch survives restart | `docker restart vpn-gateway`; repeat leak test before and after tunnel recovery. |

### Results — 2026-09-17, host01 (all pass)

- **Leak**: tunnel forced down; agent egress timed out. Mid-rotation probe
  during a healthy switch: 60 probes, 59 answered by VPN exits (old node,
  then new node), 1 blocked in the gap, zero home-IP responses.
- **Attribution**: exit IPs are Surfshark exits (verified vs. home IP by
  blind on-host comparison).
- **Rotation**: au-adl → de-fra → jp-tok → uk-man → us-buf, distinct
  geo-correct exit IP each time. (Found and fixed en route: cluster
  hostnames must be pinned to one resolved IP in the active config, or
  `wg setconf` and the firewall disagree and the tunnel dies mid-rotation.)
- **Containment**: agent cannot reach the LAN router, host01's LAN IP, the
  egress bridge gateway, or llm-proxy's egress address; llm-proxy (sandbox
  path) and the tokened gateway API respond; bad token → 401.
- **Audit trail**: calls as the agent logged with messages, response, and
  the requested alias (`zai/glm-5.3-flash` vs upstream `glm-5.3-flash`).
- **Restart**: 20/20 egress probes blocked during the gateway restart gap;
  tunnel auto-recovered to the first config; GUI and proxy path healthy
  after. (Note: restarting vpn-gateway replaces the shared netns — the
  agent must be restarted too.)

## Explicitly out of scope for V1

- Target allow-listing at the gateway (scope control stays a human/agent
  discipline per the README principles for now; enforce in V2).
- Automated rotation policy (V1 exposes the API; the agent decides when).
- Log analysis/reporting UI.
