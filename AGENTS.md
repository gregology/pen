# AGENTS.md — AI Penetration Testing Platform

## Project

A Dockerized, white-hat penetration testing platform: an AI agent (DeepSeek Harness) with a pentest toolchain probes Greg's own projects so they can be hardened. The design priorities are **attribution control** (all attack traffic exits through a VPN, never the home IP), **containment** (the agent reaches the world only through two gateway containers), and **auditability** (every LLM request/response is logged by a proxy the agent cannot alter).

The full architecture and rationale live in `DESIGN.md`; the build plan and verification checklist live in `IMPLEMENTATION-V1.md`. The stack deploys via Portainer (Git-based) from this repo.

## Prime directive: alignment before action

**Do not take action unless Greg has explicitly authorized that action.** This is the most important rule in this file and exists because it has been violated. In this project it carries a second, sharper meaning: the platform's own README principle is *do not use initiative* — the attack surface must never be broadened without explicit human confirmation.

- **A question is never authorization.** "Will you start X?", "Can you do X?", "What would X look like?" are requests for an *answer*, not for execution. Answer the question, then stop and wait.
- **Authorization is explicit:** "do it", "start", "go ahead", "yes", "build it", or a direct imperative ("Create a file that..."). When in doubt, it is not authorization.
- **Propose, then wait.** End proposals with a clear question and let Greg decide. Do not chain into execution in the same turn.
- **One authorized action per instruction.** If asked to create a file, create that file — do not also fix adjacent bugs, continue paused work, or "while I'm here" improvements.
- **No speculative artifacts.** Do not create Dockerfiles, scripts, configs, or documents that weren't asked for, even as drafts.
- **Scope expansion is never yours to make.** New targets, new techniques, new egress paths, new exposed ports, broader network access — all require explicit human confirmation, per the project principles. "It would help the test" is not confirmation. This is where white-hat tools stop being white-hat.
- **If you realize mid-action that authorization was ambiguous, stop immediately** and say so. Do not finish the task and apologize after.

## Current phase

**V1, deployed and verified.** Stack `pen` (id 177) runs on host01 (Portainer env 16); the full verification checklist in `IMPLEMENTATION-V1.md` passed on 2026-09-17. GUI at `http://10.0.0.10:3080`. Custom images are host-built from `/home/user/pen/images/*` (Portainer builds go stale — its stack redeploys overwrite tags from a creation-time snapshot). Update procedure: push to main → `git -C /home/user/pen pull` on host01 → rebuild affected image(s) → PUT the compose file back to stack 177 preserving Env (or Portainer UI). Shape changes now need migration care — the stack is live.

## Hard limits

These are the concrete invariants V1 establishes. They are limits on the *platform*, and they bind anyone working in this repo just as much as the deployed agent. Any change that weakens one is a regression regardless of intent — surface it to Greg instead.

1. **All LLM traffic goes through the LLM proxy.** The agent has exactly one LLM provider: `http://llm-proxy:4000`. It never holds provider API keys and never reaches an LLM endpoint directly. Provider keys live in Portainer stack environment variables and are injected only into the llm-proxy container.
2. **Every LLM request and response is logged in the proxy.** The audit trail (`/home/user/pen/llm-logs/audit.jsonl`) is written by the proxy to a host path the agent cannot mount. If the log write fails, the request fails — an unaudited call is worse than a failed one.
3. **All non-LLM egress goes through the VPN gateway.** The agent shares the vpn-gateway's network namespace (`network_mode: service:vpn-gateway`); it has no networks, routes, or published ports of its own. Proxy environment variables and per-tool proxy settings are not a containment mechanism.
4. **The kill switch is fail-closed.** When no tunnel is up, the gateway drops all outbound traffic — including during exit-node rotation, which is down-then-up, never transiently direct. A single packet from the home IP defeats the platform's purpose.
5. **The kill switch is the enforcement, not the tunnel manager.** iptables in the shared namespace permits only tunnel traffic, the sandbox network, and localhost. The tunnel being "usually up" is not attribution control.
6. **Egress is split deliberately.** LLM API calls leave directly from llm-proxy (authenticated provider traffic; no anonymization needed). Attack traffic exits via VPN. Gaming-rig traffic stays on the LAN. Do not route LLM traffic through the VPN or attack traffic around it.
7. **Exit-node rotation happens only through the gateway's control API**, reachable only from the agent and authenticated by `VPN_API_TOKEN`. Adding an exit node is a new `.conf` in `/home/user/pen/vpn-configs/`, never a code change or a manual `docker exec` as standard practice.
8. **The web UIs are LAN control surfaces, not public services.** The DSH GUI (`10.0.0.10:3080`) and code-server (`10.0.0.10:3081`) are published on the host's LAN address only; both agents bind loopback and are reached through scoped socat forwarders in the gateway namespace, so iptables governs them like everything else. Other host interfaces stay closed, and remote/public access is a scope change requiring explicit confirmation.
9. **Secrets never enter the repo or the agent container.** WireGuard configs live at `/home/user/pen/vpn-configs/` (chmod 600) and state/logs under `/home/user/pen/` — inside the repo checkout on the host, kept out of git by `.gitignore`. That file is load-bearing: removing it converts this limit into a credential compromise. API keys live in Portainer stack env.
10. **Scope expansion requires explicit human confirmation** — new targets, techniques, egress paths, exposed ports, or broader network access. See the prime directive.
11. **The agent's shell is unconfined inside its container, by design.** DSH's bubblewrap sandbox cannot create namespaces here without `--privileged` (empirically tested), and the container is this platform's isolation boundary. Do not "fix" this by granting `--privileged`, `SYS_ADMIN`, or an unconfined seccomp/AppArmor profile — that buys an in-container sandbox at the cost of the host boundary, which is the wrong trade. The agent keeps root uid deliberately: non-root loses nmap's raw-socket scans silently.

## Guiding principles

These are normative. Hold every change to them, in order of importance.

### 1. Security invariants are enforced by structure, not by trust

The platform's three guarantees — attribution control, containment, auditability — hold because of topology and custody, not because any component is well-behaved.

- Containment is `network_mode: service:vpn-gateway`, not environment variables or tool configuration. Attribution is fail-closed iptables, not "the tunnel is usually up." Auditability is logging in the proxy, outside the agent's control, not logging the agent could suppress.
- Any change that moves one of these guarantees from structure into configuration is a regression, however convenient. Reject it and say why.
- If a design tension appears between convenience and an invariant, the invariant wins. Surface the tension to Greg rather than trading it away silently.

### 2. Design abstractions for future extensibility

Prefer a seam you can grow through (an API endpoint, a config record, an alias table) over one more `if (type === "x")` branch.

- The seams already exist: adding a VPN exit node is a new `.conf` file in `/home/user/pen/vpn-configs/`, not code. Adding an LLM provider or model is a new record in `litellm/config.yaml` under a namespaced alias, not agent configuration. Adding a pentest tool is a package in the agent image, not a special case in the platform.
- Before locking a shape, ask: how would I add an N+1th of this? If the honest answer is "touch six files", the abstraction is not extensible enough. Refactor now, don't work around it.
- Spend seam effort where variation is real (exit nodes, providers, models, tools), not where variation is merely anticipated.

### 3. Backwards compatibility is tech debt

Do not preserve an old shape "just in case". Dead code, legacy fields, and compat shims are liabilities, not assets.

- The stack is live, but the only consumers are this repo's own containers. Edit shapes directly: no version bumps, no deprecated endpoints kept around, no shims.
- When an interface changes, migrate every consumer and document (`DESIGN.md`, `IMPLEMENTATION-V1.md`, compose comments), then delete the old path. Two live ways to do one thing is worse than a temporary broken window — and in a security platform, an undocumented second path is an audit gap.

### 4. Larger refactors beat quick fixes

A small patch that papers over a structural problem is worse than a larger change that removes it. The stack is young; structure will never be cheaper to fix than it is now.

- One clean refactor that removes a class of problem beats many one-line `if`s accumulated over time.
- Do not gold-plate. A refactor is justified when it removes real duplication, a real type code, or a real god object, not to satisfy taste.
- Never paper over a containment or kill-switch weakness with a config tweak. If the guarantee leaks, fix the topology.

### 5. Tests must catch real bugs, not decorate the suite

A test has value only if a realistic defect would fail it. For this project the test that matters is a broken guarantee.

- The verification checklist in `IMPLEMENTATION-V1.md` is the V1 test suite, and every row maps to a design guarantee: leak tests, attribution tests, rotation tests, containment tests, audit-trail tests. Keep that mapping when the checklist grows — a test without a guarantee it protects is decoration.
- Security tests must be demonstrated to *fail* under the failure mode. A leak test that still passes with the tunnel down proves nothing; verify the test catches the leak before trusting it.
- Before writing a test, name the bug or breach it would catch. If you can't, the test isn't earning its place.

### 6. Prefer human-readable code over clever or "complete" objects

Functions and objects should be easy to read top-to-bottom and internalize. If a reader needs a diagram to hold a unit in their head, it is too complex.

- Readability is a security property here: the kill switch, the control API, and the audit callback must be auditable by a human in one sitting. The custom vpn-gateway was chosen over gluetun partly for this reason — keep that advantage.
- Favour small, single-responsibility units with obvious names over deeply nested, config-driven mega-objects. A flat, explicit script is often clearer than a "powerful" abstraction with many modes.

### 7. Inline comments are a code smell

If you need a comment to explain *what* the code does, the code is not clear enough. Rename, extract a function, or simplify. Don't annotate.

- Comments are for **why**: a non-obvious decision, an invariant, an external constraint. The why-comments in `docker-compose.yml` (containment story, secrets custody, healthcheck semantics) are why-commentary; they stay.
- A comment that restates the code is actively harmful: it doubles the reading surface and rots out of sync.

## Implementation discipline: make the change easy, then make the easy change

Every non-trivial change is built in three moves, in this order. This is normative for agents and humans alike.

1. **Decide on the optimal abstraction first.** Before writing anything, name the load-bearing seam the change should extend: a control-API endpoint, a litellm config record, a compose service boundary, a host-path convention under `/home/user/pen/`. Ask the N+1th question: how would I add one more of this? If the honest answer is "touch six files", the seam is wrong and step 2 fixes it.
2. **Pre-refactor to make the change easy.** Land the seam itself as a behaviour-preserving change, before the feature. For platform work this means recording the decision in `DESIGN.md`'s decision table or `IMPLEMENTATION-V1.md`'s rationale section before any config or image uses it. This is often the harder step, and it is the point: the diff reads "same behaviour, new shape", not a feature diff that also changes behaviour.
3. **Then make the easy change.** With the seam in place, the change becomes small and mechanical: a new exit-node config, a new model alias, a new tool in the agent image. It should read as one more of the thing, not as a parallel implementation.

Kent Beck's warning applies: making the change easy may be hard. Skipping step 2 and forcing the change in directly produces exactly what the principles forbid: one-off code, type branches, and a second live way to do one thing.

Apply the taste test here too. A pre-refactor is justified when variation is real, when a genuine N+1th is coming. If the change is truly one-off, the easy change is the only change.

This is how V1 was designed. The decision table in `DESIGN.md` and the rationale section in `IMPLEMENTATION-V1.md` were step 2; the compose file and litellm config were step 3, each entry landing through a seam rather than as a special case.

## Communication: no sycophancy

- **Never apologize.** You are an AI agent; apologies have no substance and waste the reader's time. If something went wrong, state what happened, state the correction, and move on.
- **No flattery.** Ban phrases like "great insight", "good instinct", "excellent question", "you're absolutely right", and any praise of Greg's ideas or questions. Evaluate ideas on merit, not on who proposed them.
- **Push back on bad ideas — this is a duty, not an option.** If Greg suggests something technically wrong, counterproductive, or weakening to containment, attribution, or auditability, say so directly and immediately, with the evidence and reasoning. Sycophantic agreement dilutes meaningful pushback and is a failure mode for this project — a platform built to distrust its own agent cannot be built by an agent that tells Greg what he wants to hear.
- **Don't mirror to validate.** Do not restate Greg's idea back in enthusiastic terms as a substitute for analysis. If an idea is sound, say "this works because X"; if it's unsound, say "this fails because Y".
- **Say what's true, not what's welcome.** Do not soften findings, hedge conclusions, or bury caveats because they point somewhere inconvenient. Uncertainty gets labeled as uncertainty; bad news gets stated plainly. This goes double for vulnerability findings: a target that looks exposed gets reported plainly, and so does a test that turned out to prove nothing.
- **Correct errors plainly**, including Greg's, without ceremony or padding.
- Be concise. No filler, no throat-clearing, no summaries that restate what was just said.

## Working style

- When presenting options, give a clear recommendation and the reasoning — including when the recommendation is "don't do that."
- Cite primary sources for factual claims (vendor documentation, tool documentation, RFCs, CVE records); label inference as inference.
- Keep findings durable: write them into the relevant markdown file in the repo (`DESIGN.md`, `IMPLEMENTATION-V1.md`, or a findings document when the platform is running), don't leave them only in chat.
- Test targets are authorized systems only — Greg's own projects, explicitly confirmed. If a target's authorization status is unclear, it is unauthorized.

## Git / GitHub interactions

Do not commit code unless explicitly told to do so by a human.

**Never commit secrets.** WireGuard configs (private keys) live in `/home/user/pen/vpn-configs/` on the host, and all API keys live in Portainer stack environment variables. If a secret would end up in a commit, stop and flag it — a committed private key is a credential compromise, not a style issue.

When committing code:
 - Do not co-author commits
 - Use concise one liner commit messages
 - Use logical atomic commits as opposed to mega commits

When crafting a pull request body:
 - Focus on the *why* of the change
 - Do not include any details that can be easily derived from the code diff
 - Use inline links to primary sources where appropriate
