# Design: AI Penetration Testing Platform (V1)

A Dockerized, white-hat penetration testing platform in which an AI agent
(DeepSeek Harness) probes my own projects so they can be hardened. The design
priorities are **attribution control** (traffic must not originate from my home
network), **containment** (the agent can reach the world only through
controlled chokepoints), and **auditability** (every LLM interaction is
recorded).

## Goals

- Simulate *external* attackers. Tests run from inside my network would
  misidentify internal-only exposures as external vulnerabilities; routing all
  traffic through a VPN exit node makes the threat model honest.
- Protect my home network's reputation and legal standing. Automated scanning
  traffic must never leak with my residential IP, even transiently during VPN
  failures or node rotation.
- Keep the AI agent auditable and constrained. An autonomous agent running
  offensive tooling is powerful; its reasoning (LLM calls) and its network
  reach must both pass through observable, enforceable gateways.

## Non-goals (V1)

- Automated exploitation frameworks, credential brute-forcing at scale, or
  attacks against anything other than explicitly authorized targets.
- Broadening the attack surface autonomously — per project principles, new
  targets or techniques require explicit human confirmation.

## Architecture

Three containers on a Docker network, with deliberately one-directional trust:

```
┌─────────────────┐      ┌──────────────┐
│  agent (DSH)    │─────▶│  llm-proxy   │────▶ LLM providers (HTTPS)
│  + pentest tools│      └──────────────┘
│                 │      ┌──────────────┐
│                 │─────▶│  vpn-gateway │────▶ Internet (via VPN exit node)
└─────────────────┘      └──────────────┘
```

### Agent container

Hosts the DeepSeek Harness instance and the pentesting toolchain. It has **no
direct route to the internet or the host network** — its only reachable peers
are the two gateway containers. This is the core containment property: the
most autonomous and least predictable component is also the most restricted.
All egress policy is enforced by network topology rather than by trusting
configuration inside the agent container, so a misbehaving or compromised
agent cannot bypass it.

### VPN gateway container

The single egress point for all non-LLM traffic. Two requirements define it:

1. **Kill switch (fail-closed).** When no VPN tunnel is up, the gateway drops
   all forwarded traffic. This is non-negotiable: any fail-open moment leaks
   the home IP, which defeats the purpose of the VPN and creates exactly the
   attribution problem the platform exists to avoid. Rotating exit nodes must
   therefore be atomic-with-downtime, never transiently direct.
2. **Exit-node control API.** The agent selects among a dozen or so pre-loaded
   VPN configs via an API on the gateway. Rotation matters because a single
   static exit node will get rate-limited or blocked by targets, skewing test
   results, and because realistic external probing comes from varied origins.
   The API is exposed only to the agent container — it is a control surface,
   not a public one.

### LLM proxy container

The agent's only path to LLM providers. It exists for one reason: **complete,
tamper-resistant audit logs of every LLM request and response**. Logging in
the proxy rather than in the agent means the agent cannot suppress or alter
the record of its own reasoning — essential for a tool that performs offensive
actions, both for post-hoc review and for demonstrating responsible use. As a
secondary benefit it centralizes provider credentials and rate limiting,
keeping secrets out of the agent container.

## Key design decisions

| Decision | Rationale |
|---|---|
| Chokepoints enforced by network topology, not agent config | The agent is autonomous and runs untrusted-ish tooling; policy it could rewrite is not policy. |
| Fail-closed VPN kill switch | A single leaked packet from the home IP undermines attribution control and exposes the operator. |
| Exit-node rotation via API, driven by the agent | Rotation cadence is a tactical decision the agent can make (block evasion, geo-diversity); humans shouldn't babysit it. |
| LLM logging in a separate proxy | Audit logs must be outside the audited component's control. |
| Split LLM egress from general egress | LLM traffic does not need VPN anonymization (it's authenticated API traffic to providers); routing it separately keeps VPN bandwidth for attack traffic and makes audit logs cleaner. |
| Human confirmation for scope expansion | Autonomous expansion of attack surface is where white-hat tools stop being white-hat. |
| GUI exposed via a loopback forwarder in the gateway, not `--host 0.0.0.0` | The web UIs (DSH, code-server) reject wildcard binds by design (remote-code-execution exposure); scoped socat forwarders plus iptables keep them reachable from the LAN without weakening the tools' own trust models. The ports bind the host's LAN address only, and DSH is given `--trusted-host` for that authority so its browser-trust fence accepts it. |
| A shared working directory (`/home/user/pen/working` ↔ `/working`) | Test notes, `AGENTS.md`, and results need to be one set of files that Greg and the agent both edit — in a web editor and in the agent's own tools — rather than copied between host and container. |
| Agent runs unconfined inside its container, with gid-aligned writes | DSH's bubblewrap sandbox cannot create namespaces here without `--privileged` (tested), and the container — not the in-container sandbox — is this platform's isolation boundary. Root uid keeps nmap's SYN/UDP scans and OS detection working; gid 1000 plus `umask 002` keeps the shared directory editable from the host without sudo, which a uid change could not do without silently costing raw-socket tools. |

## V1 scope

1. Agent container: DSH + baseline pentest toolkit.
2. VPN gateway: WireGuard/OpenVPN with fail-closed kill switch and a minimal
   HTTP API (`list` / `switch` exit node, `status`) reachable only from the
   agent.
3. LLM proxy: request/response logging to durable storage, agent-facing
   endpoint, provider keys held here.
4. Docker Compose topology with agent egress restricted to the two gateways.

Later versions: target allow-listing at the gateway, richer rotation policy,
log analysis/reporting, additional toolchains.
