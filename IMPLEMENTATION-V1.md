# V1 Implementation Plan

Implements the architecture in `DESIGN.md`: four containers (agent, browser,
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
- **An off-the-shelf image for the interactive browser, pinned by tag.** The
  `browser` sidecar runs `jlesage/chromium` at a calendar-version tag. It was
  chosen because remote debugging is a documented first-class environment
  variable there rather than a flag smuggled through an entrypoint, it needs no
  capability beyond the defaults, it is multi-arch, and its own documentation
  states the same unsandboxed position hard limit 12 already records. Building
  the X server, window manager, VNC server and a second Chromium ourselves would
  add a large maintenance surface for no containment gain, since containment
  here comes from `network_mode: service:vpn-gateway`, exactly as it does for the
  agent. Rejected alternatives, recorded so they are not rediscovered: Kasm
  Workspaces images (the community edition's licence excludes revenue-generating
  use), browserless (SSPL-or-commercial, and its interactive live takeover is
  Enterprise-gated), neko (no CDP at all, and it defaults to port 8080 — the
  gateway's control API), every Firefox-based image (Firefox 141 removed CDP, and
  Camoufox has no human-viewable display), and `browser-use/web-ui` (asks for
  `SYS_ADMIN`, which hard limit 11 forbids).
- **What that image does not ship, and why it is installed at startup for now.**
  Alpine splits Chromium's software rendering into separate packages —
  `chromium-swiftshader` (the Vulkan ICD) and `chromium-angle` (the GL
  libraries) — and this image installs only the browser. A container with no
  `/dev/dri` therefore has no rendering fallback at all, and a challenge widget
  that fingerprints through canvas and WebGL dies in the renderer: observed as
  a deterministic crash ~1s into hCaptcha's proof-of-work module, with
  `libvk_swiftshader.so: No such file or directory` in the Chromium log and
  crashpad unable to write a dump because the container's seccomp profile
  blocks `sched_getscheduler`. `INSTALL_PACKAGES` is the image's own documented
  hook and is what the compose file uses, but it runs on every container start
  and needs the tunnel and DNS up at that moment — the runtime-download
  dependency this repository rejected once already. The intended end state is a
  derived image with those packages baked, which is also where a Chromium
  version pin would live; the sidecar is on Alpine's 152 while the agent's
  browser is Playwright's 153, and Alpine's branch has no 153 at all, so
  aligning them is a change of provenance rather than a version bump.

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
  Because rotation is what disturbs the namespace's routing, each bring-up
  re-asserts both halves of the LAN exception, idempotently: the policy
  rule at priority 90 *and* the `LAN_CIDR` route via the egress gateway in
  table `main`. A rule pointing at a table that no longer holds the route
  is a silent no-op — LAN-bound replies then fall through to the `wg0`
  table and the GUIs go dark from the LAN while `/status` still reports the
  tunnel healthy. The route is asserted *via* the gateway rather than left
  on-link so the namespace never ARPs for an off-subnet client: the bridge
  does not proxy ARP, so an on-link lookup dead-ends in `INCOMPLETE`
  neighbour entries. Endpoints (no credential — the kill switch limits the
  port to the sandbox network and loopback):
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
- Healthcheck: `curl -f http://localhost:8080/status`. The
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
- **The pentest toolchain on top of the base.** Each tool owns a directory
  under `images/agent/tools/<name>/` holding its `install.sh` (version pins and
  install) and its `AGENTS.md` (operator usage); the selection rationale is in
  `images/agent/tools/TOOL_RESEARCHING.md`. Versions:
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
   `LITELLM_MASTER_KEY`, `KIMI_CODING_API_KEY`,
   `ZAI_API_KEY`, `DEEPSEEK_API_KEY`, `GAMING_RIG_API_KEY`,
   `CODE_SERVER_PASSWORD` (new; generate one).
   There is no `VPN_API_TOKEN`: the control API is unauthenticated and
   confined to the sandbox network and loopback by the kill switch.
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
| GUIs survive rotation | `POST /switch`, then `curl` both `10.0.0.10:3080` and `:3081` from a LAN host other than the Docker host — the throwaway host-local `curl` those ports normally get proves nothing, because a host-local client is masqueraded to the bridge gateway and never needs a route back to the LAN. |
| Containment | Agent cannot reach the egress network or host LAN directly (e.g., `curl` a host-only address must fail); only llm-proxy and the gateway API respond. |
| Audit trail | Run a DSH session against each provider alias; confirm every LLM request/response appears in `/home/user/pen/llm-logs/audit.jsonl`, including ones the agent might prefer to hide. |
| Kill switch survives restart | `docker restart vpn-gateway`; repeat leak test before and after tunnel recovery. |
| Browser renders and executes JavaScript | From the agent: `browser --target 127.0.0.1 run` against a fixture page whose text is written by a script (`python3 -m http.server 8090`), then `text #t` must return the scripted string. A browser that launches but does not execute JS is the failure this catches, and it is the failure that made three tools report empty results as if the target had nothing. |
| Browser is reachable by the tools that expect one | `command -v chromium` resolves `/usr/local/bin/chromium`, and `katana -u <fixture> -hl -sc -d 1 -duc` returns URLs from a page whose links are added by script. Without `-sc` katana silently downloads its own Chromium instead, so the flag is part of the test. |
| Screenshot path produces an image | `httpx -u <fixture> -ss -system-chrome -duc -json -o /tmp/s.json`, then confirm the stored screenshot is a non-empty PNG. This row exists because the previous image documented screenshot flags that had never once been run. |
| Browser sandbox status is known, not assumed | `bash /tools/browser/sandbox-experiment.sh` exits 0 (sandbox available under a dropped uid) or 1 (it is not). Either answer is acceptable; an unrecorded answer is not, because it is the difference between a renderer isolated from the agent and a renderer that is not. |
| Interactive browser egress is the tunnel | With the tunnel up, the exit IP the browser view sees equals the agent's (`curl https://ifconfig.me` from the agent, and the same URL in the view); with the tunnel down (`ip link set wg0 down`), a page load in the view fails. The sidecar has no route of its own, and this row is what proves that rather than reading it off the compose file. |
| The DevTools endpoint is not reachable off loopback | From the namespace, `ss -ltn` shows Chromium's CDP on `127.0.0.1:9224` and **nothing** listening on 9222; `curl -fsS http://127.0.0.1:9224/json/version` answers from the agent, the same request from a LAN host to `10.0.0.10:9224` must fail, `docker port browser` must print nothing, and the same request from llm-proxy to the gateway's sandbox address must fail. The image's own forwarder is what made this false once, so the 9222 line is the part of the row that carries the guarantee. |
| The browser view is a LAN control surface | From a LAN host, `http://10.0.0.10:3082` serves the noVNC page; from the egress network the same port is dropped, matching the GUI rows above. A view that answers the tunnel is a second way in. |
| The agent drives the session the human cleared | Log in by hand in the view, then `browser --cdp http://127.0.0.1:9224 text` returns the authenticated page, and `browser --cdp … close` reports that it detached without killing the browser. This is the capability the whole sidecar exists for, and it fails if the attach path quietly launches a fresh browser instead. |
| The sidecar can render a challenge widget | From the agent: `browser --cdp http://127.0.0.1:9224 eval "(()=>{const c=document.createElement('canvas');return {webgl:!!c.getContext('webgl'),webgl2:!!c.getContext('webgl2')}})()"` returns true, and an hCaptcha-protected page completes rather than losing its frame. When it does die, `/home/user/pen/browser-profile/log/chromium/error.log` carries `Renderer process exited unexpectedly: termination status N`, and N names the cause — but only with `--enable-logging=stderr --v=1`, because crashpad is degraded under this container's seccomp profile. This row exists because the image shipped without Alpine's rendering subpackages and nothing in the platform noticed. |

### Re-verified after the toolchain deploy — 2026-09-17 (all pass)

The toolchain image was deployed by replacing the `agent` (and, as a
dependency, `vpn-gateway`) container from the repo compose file. Two
procedure corrections came out of it, both recorded here because the naive
form of each test damages the platform rather than testing it:

- **The leak test must not use `wg-quick` on the exit-node config.** The API
  brings the tunnel up from `/run/wg0.conf`, where the basename is what names
  the interface (`wg0`) and the `DNS=` lines are stripped. Running
  `wg-quick up /vpn/configs/<node>.conf` directly creates a *second*
  interface named after the file and lets `resolvconf` overwrite
  `/etc/resolv.conf` with the provider's resolvers — which the kill switch
  then blocks, so the container loses DNS and every probe times out for the
  wrong reason. Drop the link instead:

  ```
  docker exec vpn-gateway ip link set wg0 down     # tunnel down, config intact
  # ... probe from the agent: every attempt must fail ...
  docker exec vpn-gateway ip link set wg0 up
  ```

- **The API reports `tunnel: up` from the interface alone.** After a link
  flap the interface is up but the WireGuard socket does not re-handshake,
  so `/status` says `up` while every packet is dropped. Confirm recovery with
  a fresh handshake age, not the state string, and recover by rotating nodes
  through `POST /switch` (which does a full down-then-up) rather than by
  toggling the link.

- **The control API carries no credential, by design.** It was formerly
  authenticated by a shared bearer token, which was removed: the token was
  never the boundary (the kill switch restricts port 8080 to the sandbox
  network and loopback) and a blank `VPN_API_TOKEN` in the stack environment
  made the agent's own calls fail with a 401. Confirm the API answers with
  `curl -fsS http://localhost:8080/status` from inside the namespace, and
  confirm the boundary still holds by checking that the same request from the
  egress network is dropped.

Results: leak test 10/10 blocked with zero home-IP answers; attribution via
an Adelaide exit (`103.214.20.198`) distinct from the home line; rotation to
`nz-akl` and back clean; containment unchanged (LAN, egress bridge, and peer
addresses all refused; llm-proxy healthy on the sandbox path); audit trail
extended by a live chat completion; GUI 401 and code-server 302 on
`10.0.0.10`; all 29 tools present and the 27 doc directories readable at
`/working/tools`.

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
