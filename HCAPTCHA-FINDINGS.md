# Findings: hCaptcha kills the sidecar's renderer

The `browser` sidecar cannot complete an hCaptcha challenge, so any target behind
one cannot be logged into through the shared browser. This records what has been
ruled out, by what method, and the single measurement still missing. It exists so
the eliminated hypotheses are not re-run — several of them cost a deployment to
eliminate, and one of them eliminated a claim made in this repository.

## The symptom

Attaching over CDP and reloading an hCaptcha-protected login page reproduces
this deterministically, three runs out of three:

| t (s) | Event |
|---|---|
| +0.0 | reload; page logs the CSP warning |
| +1.5 | `hcaptcha.com/1/api.js` → 200; both `newassets.hcaptcha.com/.../hcaptcha.html` frames → 200 |
| +2.2 | `api.hcaptcha.com/checksiteconfig` (real sitekey) → 200 |
| +2.4 | `newassets.hcaptcha.com/c/…/hsw.js` (the WASM proof-of-work) → 200, executes |
| +2.9–3.3 | **the renderer dies**; Chromium reloads the tab and the captcha state is lost |

Cloudflare's challenge completes in the same browser over the same tunnel, so
this is specific to hCaptcha's path rather than to the sidecar's browser,
network or exit node.

## Ruled out, with the method

| Hypothesis | Evidence | Verdict |
|---|---|---|
| The CSP warning | `upgrade-insecure-requests` is a no-op in a report-only policy — [W3C Upgrade Insecure Requests §3.1](https://w3c.github.io/webappsec-upgrade-insecure-requests/#delivery), normative: *"Monitoring the `upgrade-insecure-requests` directive has no effect: the directive is ignored when sent via a `Content-Security-Policy-Report-Only` header."* The page's enforcing CSP allows `hcaptcha.com` in `connect-src` and `frame-src`, and the warning appears on healthy loads too. | Not the cause |
| Network, egress, DNS, IP reputation, clock | Every hCaptcha endpoint returned 200 through the tunnel, and `checksiteconfig` returned a real configuration for the real sitekey, which is what lets the flow reach the proof-of-work at all. | Not the cause |
| JS heap exhaustion | Last healthy sample before death: 10.5 MB used of 22 MB. Death is instant, not degrading. | Not the cause |
| A missing software rendering backend | `document.createElement("canvas").getContext("webgl")` returns a context in the sidecar, and `chromium-angle` was already a dependency of Alpine's chromium package — so ANGLE on Mesa llvmpipe was present from the start. Installing `chromium-swiftshader` (the Vulkan ICD, genuinely absent) changed nothing. | Not the cause |
| Disk or memory pressure | `/tmp` is a 31 GB tmpfs with 5.7 MB used; `/` is 27% used of 1.8 TB. It remains the case that the image hardcodes `--disable-dev-shm-usage`, so the container's `shm_size: "1gb"` is unused. | Not the cause |
| Exotic or masked CPU | host01 is a stock Intel i9-9880H (Coffee Lake), AVX2 present, no AVX-512. A codegen bug emitting unsupported instructions here would not be obscure. | Not the cause |
| A synchronous hardware exception | `dmesg` carries **no** `traps:` line for the sidecar's Chromium. The kernel logs `show_signal_msg()` only for hardware exceptions (SIGSEGV, SIGBUS, SIGILL, SIGFPE, SIGTRAP), so the renderer is not dying of one — which leaves a deliberate crash or abort, a clean exit, or SIGKILL. | Not a hardware fault |
| Chromium 152 versus 153 | Not testable as a rebuild: Alpine 3.24 ships `chromium 152.0.7977.82-r0` and **Alpine edge ships the same upstream version**, so there is no 153 to bump to; the agent's 153 comes from Playwright's own build, a different provenance. The bisect behind the recommendation varied version, headedness and sitekey at once, and its 153 arm never ran the real challenge path because Cloudflare blocked it. | Unproven, and unreachable by a tag bump |

One claim in this repository was wrong and is corrected by the table above: the
rendering-backend gap was described as leaving the container with no WebGL at
all. It did not. The gap was real — the Vulkan ICD was missing and the Chromium
log said so — but it was not this crash.

## The measurement still missing

**The renderer's termination status.** Everything above narrows the cause to
four candidates with four different fixes, and the exit reason separates them.

crashpad cannot supply it. It reports `sched_getscheduler: Function not
implemented (38)` and writes no minidump, and `chrome://crashes` is empty. The
reason for that has not been pinned down; do not assume the container's seccomp
profile without checking, and do not weaken that profile to obtain a dump
without deciding to, explicitly.

The compose file therefore raises Chromium's own logging, which reaches
`/home/user/pen/browser-profile/log/chromium/error.log` (jlesage writes
Chromium's stdout and stderr there, and truncates the file at 1 MB on each
container start):

```
--enable-logging=stderr --v=1
```

Two of the four candidates are already distinguishable from the `dmesg` result:
neither SIGSEGV nor SIGILL is in play, so the remaining question is a deliberate
crash or abort, a clean exit, or SIGKILL — and the log says which.

## The hypothesis under test in the same restart

The crash lands 0.5–1 s after the proof-of-work module starts, which is the
WebAssembly tier-up window: V8 runs a module with its baseline compiler first,
recompiles hot functions with the optimising compiler in the background, and
begins executing that code about a second in. That timing is why the compose
file also carries

```
--js-flags=--no-wasm-tier-up
```

Flag names verified in V8's [`src/flags/flag-definitions.h`](https://raw.githubusercontent.com/v8/v8/main/src/flags/flag-definitions.h)
(`wasm_tier_up`, `liftoff_only`). It is a probe with two useful outcomes: if
hCaptcha starts completing, tier-up is implicated and there is a workaround; if
it still dies, tier-up is eliminated and the log will say why. `--liftoff-only`
is the stronger form if this one is inconclusive.

## Fixed along the way, and verified

- **The DevTools endpoint is loopback-only.** The image ran its own forwarder,
  `socat TCP-LISTEN:9222,fork TCP:127.0.0.1:9223`, and `TCP-LISTEN` with no bind
  address listens on every interface of the namespace. Since the sidecar shares
  the gateway's namespace, CDP was reachable by llm-proxy and the Docker host.
  The forwarder is now off and Chromium binds loopback itself on 9224.
  Verified: `ss -ltnp` shows one listener, `127.0.0.1:9224`, and nothing on 9222.
- **The browser's background traffic to Google**, seen as repeated
  `google_apis/gcm/engine/registration_request.cc` entries, is disabled.
- **The Vulkan ICD** is installed, so the Vulkan and WebGPU paths exist. This
  did not fix the crash.

## Open, and unrelated

`dmesg` carries one `traps:` line: `chrome-headless[2419680] trap int3`. That is
`chrome-headless-shell`, the agent's own browser, not the sidecar, and `int3` is
the breakpoint Chromium executes deliberately — the same mechanism its crash
handler uses. It has not been investigated and may be a shutdown-time artifact.

## Re-running the probes

```bash
docker exec agent browser --cdp http://127.0.0.1:9224 eval 'document.createElement("canvas").getContext("webgl") ? "WEBGL:YES" : "WEBGL:NO"'
docker exec agent ss -ltnp | grep -E ':922[0-9]'
sudo dmesg -T | grep -iE 'traps:|segfault|invalid opcode|bus error|oom|killed process'
tail -100 /home/user/pen/browser-profile/log/chromium/error.log
```
