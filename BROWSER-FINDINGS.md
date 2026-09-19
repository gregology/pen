# Findings: "No browser and no Playwright"

What an agent reported, what was actually true, and what changed.

## The report

Agents probing targets through `pen` reported `No browser and no Playwright`.
That is accurate as a description of the image and wrong as a description of the
platform, and the gap between the two is the finding.

## What was actually there

No Playwright, and no browser binary at all. What the image had was:

- Chromium's **shared libraries**, installed by `tools/katana/install.sh` so that
  a *runtime-downloaded* Chromium could launch.
- Three tools documenting a browser-dependent capability that nothing had ever
  exercised:
  - `katana -hl` / `-hh` — downloads its own Chromium through go-rod (~181 MB)
    into `/root/.cache/rod/browser/`. The only recorded evidence of it working
    was the download itself, followed by `Crawl completed in 1s. 0 endpoints
    found.` — a run that proves the download, not the rendering.
  - `httpx -ss` — same download. Its own documentation said so: *"Headless
    screenshots are unverified in this image … treat the screenshot flags as
    untested until someone runs one."*
  - `nuclei -headless` — needs a Chromium and, with `-headless` off by default,
    silently never loads the templates that need one.
- Four third-party DSH browser plugins on npm (`dsh-browser-playwright`,
  `dsh-browser`, `dsh-tool-browser`, `dsh-agent-browser`), each published
  Aug–Sep 2026 by a single unknown maintainer, each of which probes for an
  installed Chromium-family binary and fails when there is none. Their failure
  messages are where "no browser, and no Playwright" comes from.

So the message was a true report about a tool surface that the platform's own
documentation implied was covered.

## Why it went unnoticed

`katana/AGENTS.md` had carried an honest caveat — *"Headless crawling is
unverified in this image … treat `-hl`/`-hh` as untested until someone runs
one"* — and commit `467cc84` replaced it with the assertion that *"the
downloaded browser runs"*. The replacement evidence is the zero-endpoint crawl
above. `httpx/AGENTS.md` continued to say the opposite about the same binary, so
the two documents contradicted each other and neither had been tested.

The root cause is not a missing package. It is that a browser-dependent path was
declared working without the one test that would have caught it: render a page
whose content is written by JavaScript and read it back with `-hl`/`-ss`.

## What changed

### A browser the whole toolchain shares

`tools/browser/` installs Playwright 1.63.0 in its own venv and bakes
`chromium-headless-shell` (Chromium 153.0.8010.12, revision 1243) at
`/opt/ms-playwright` at build time via `playwright install --only-shell
chromium`. `--only-shell` takes the 114 MB headless shell rather than the
187 MB full browser; headless is the only mode this container has.

It also links the binary to `/usr/local/bin/chromium`, which is the part that
matters to the tools already here. `katana -sc`, `httpx -system-chrome` and
`nuclei -sc` all resolve a system browser through go-rod's
`launcher.LookPath()`, which searches `PATH` and a fixed list for a binary named
`chromium`. Without that link each of them either downloads a second copy at
runtime or fails with `the chrome browser is not installed` — verified in
ProjectDiscovery's own source (`runner/headless.go` in httpx, `MustDisableSandbox
() = IsLinux() && os.Geteuid() == 0` alongside it).

Baking it removes the last runtime download in the toolchain, and with it a
dependency on the tunnel being healthy the first time someone wants a screenshot.

### A browser the agent can drive

The three existing tools can *use* a browser; none can be *driven*. `browser` is
a small CLI over Playwright for the class of testing that needs one:

```
browser open https://target/ --target target
browser snapshot                    # @ref, role, name — one line per element
browser fill @1a2b3c "admin"
browser click @4d5e6f
browser screenshot
browser close
```

Sessions persist between commands, so a login survives across several
invocations, and `browser run` takes the same commands from a file. The
`snapshot` output is deliberately an accessibility-style tree rather than HTML:
a DOM dump would consume an agent's whole context on one page.

### The sandbox is off, and that is a decision

Chromium aborts at zygote init when it runs as root without `--no-sandbox`:

```
FATAL:content/browser/zygote_host/zygote_host_impl_linux.cc:128] No usable sandbox!
exit=133
```

This container runs as root deliberately (nmap's SYN and UDP scans need it) and
cannot create the user namespaces Chromium's namespace sandbox needs
(`unshare --user` → `Operation not permitted` under Docker's default seccomp
profile). So `--no-sandbox` stays, and the barrier around a hostile page is the
network topology rather than the browser's own sandbox.

`tools/browser/sandbox-experiment.sh` settles whether that can be improved on a
given host, by testing whether a dropped-privilege Chromium can start sandboxed.
On the dev host it cannot. The script exists so the answer is evidence rather
than assumption, and it is the first thing to run if someone proposes turning
the sandbox back on.

Note that the ProjectDiscovery tools were already in exactly this position —
`MustDisableSandbox()` returns true for root on Linux, so their Chromium has
always run unsandboxed. What changed is that it is now documented instead of
implicit.

## The capability gaps behind the report

A browser was necessary but not sufficient. Auditing all 32 tools against the
kinds of testing a web project actually needs turned up four capabilities with
no coverage at all, and they are now filled:

| Gap | Before | Now |
|---|---|---|
| Spec-driven API testing | nothing read an OpenAPI or GraphQL schema | `schemathesis` |
| GraphQL | `katana -kb-endpoints` classified endpoints | `graphql-cop`, `clairvoyance` |
| JWT / OAuth | `tshark` could see a bearer token in a capture | `jwt_tool`, `oauth2c` |
| WebSocket / SSE | `httpx -ws` detected support | `websocat` |
| Screenshot evidence | `httpx -ss`, unverified | `gowitness`, plus `browser screenshot` |

## What was deliberately not added

- **`agent-browser`** (Vercel): downloads its own Chrome for Testing, ships
  cloud-browser backends that would be a second egress path, and is built for
  desktops with a UI.
- **`chrome-devtools-mcp`** (Google): documents root as unsupported, defaults
  `--headless` to false, and reports usage statistics and may send trace URLs to
  a third-party API by default.
- **Third-party `dsh-*` browser plugins**: unaudited, single-maintainer, and a
  delivery route this repo does not take for code that touches targets.
- **`smuggler.py`, `h2csmuggler`**: no commits in four to five years, never cut a
  release.
- **`Assetnote wordlists`**: no tagged release, and the generator publishes to
  object storage outside git, so there is no immutable artifact to pin.

## The test that would have caught this

The browser now has a build-time check that renders a page whose text is written
by JavaScript and reads it back:

```
verify_output 'BROWSER-OK' browser run --timeout 60 <<'EOF'
open data:text/html,<h1 id=t>placeholder</h1><script>...</script>
text #t
close
EOF
```

A browser that cannot launch fails the build instead of returning an empty
result at engagement time. The same check exists for `/usr/local/bin/chromium`,
because a missing link only surfaces when someone first asks for a screenshot.
