# browser

`browser` drives a headless Chromium through Playwright so a page can be tested
where it actually runs. Reach for it when the answer depends on a real engine
rather than on the bytes the server sent: DOM-XSS sinks that only execute when
the browser parses injected HTML, `postMessage` handlers and their origin
checks, prototype pollution, SPA routes that exist only after hydration,
sessions held in `localStorage` instead of a cookie, and screenshots as
evidence. It is the runtime step behind the static tools — `dalfox` labels a
DOM-XSS finding `[A]` from AST analysis and `katana -jc` lists endpoints it read
out of JavaScript, and `browser` is what turns either into "it fired" or "it did
not". For anything that needs no DOM, reach for `httpx`, `curl`, `ffuf` or
`nuclei` first: they are faster and leave no browser process behind.

The browser is launched once and kept alive. Every `browser` invocation is a
separate process that attaches to that same Chromium over the DevTools
protocol, so a sequence of commands acts on one session: cookies, `localStorage`
and a signed-in state survive between them, and a one-shot command and a
scripted `run` reach the same browser.

## Installation and location

| | |
|---|---|
| Version | Playwright **1.63.0**; browser **Chromium 153.0.8010.12**, `chromium-headless-shell`, revision **1243** |
| Command | `/usr/local/bin/browser` → `/opt/browser/browser`, a Python script whose shebang is `#!/usr/bin/env python3` |
| Playwright venv | `/opt/venvs/browser` |
| Browser binaries | `/opt/ms-playwright`, baked at image build time by `playwright install --only-shell chromium` (≈114 MB, the headless shell rather than the full 187 MB browser). The tool sets `PLAYWRIGHT_BROWSERS_PATH` itself, so nothing needs exporting |
| Session directory | `$WORK/browser-session`, or `--session DIR`. Holds `session.json` (the browser's pid, debugging port and start time — not cookies), `profile/` (Chromium's `--user-data-dir`) and `chromium.log` (the browser's stdout and stderr, appended) |
| Screenshots | `$WORK/screenshots` by default, or the `PATH`/`--dir` you give |
| System libraries | The 21 Chromium shared libraries plus `fonts-liberation`, installed by `tools/browser/install.sh` |
| Display and TTY | None. It is the headless shell: no X server, no TTY, no window |

`browser --help` and `browser <command> --help` print the same flags documented
here; this document describes the source described above, not a later upstream
release.

The browser is launched with a fixed set of flags. They are not configurable
from the CLI:

| Flag | Why |
|---|---|
| `--no-sandbox` | Deliberate — see the rule below |
| `--disable-dev-shm-usage` | `/dev/shm` is small in a container; without this Chromium crashes on heavy pages |
| `--disable-gpu` | No GPU device in the container |
| `--no-first-run`, `--no-default-browser-check` | No interactive first-run path |
| `--disable-background-networking` | No component, extension or Safe Browsing chatter to third parties |
| `--disable-component-update`, `--disable-sync` | No vendor updates, no profile sync |
| `--password-store=basic` | No keyring/`libsecret` prompt |
| `--window-size=1280,1024` | The default screenshot viewport |
| `--remote-debugging-port=<free port>` | Chosen per launch; recorded in `session.json` |
| `--remote-allow-origins=*` | Playwright's CDP client sends an `Origin` header that recent Chromium rejects without it |
| `--user-data-dir=$SESSION/profile` | The profile is the session: cookies and `localStorage` live here |
| `about:blank` | The first page, which every command acts on |

`--no-sandbox` is not an oversight. Chromium aborts at zygote init when it runs
as root with its own sandbox enabled (`Running as root without --no-sandbox is
not supported`, [crbug.com/638180](https://crbug.com/638180)), and this
container cannot create the user namespaces that sandbox needs. Playwright also
passes `--no-sandbox` by default internally. The consequence is worth stating
plainly: **a renderer parsing a target's hostile JavaScript is not sandboxed
away from the agent.** Containment on this platform is the network topology —
the shared VPN namespace and the fail-closed kill switch — not the browser's own
sandbox, and the browser shares that namespace, so page JavaScript can reach
anything the container can reach. Do not weaken container or host policy to
obtain a sandboxed browser (see hard limit 12 in the repository `AGENTS.md`).

## Rules that apply to this tool

1. **Authorization first.** This is the most interactive tool in the image.
   Every navigation, click and form submit is attack traffic against a real
   service and is logged by the target. Only run it against hosts confirmed for
   the current engagement; an unclear target is an unauthorized target.
2. **`--target` is an accident guard, not an authorization decision.** It is
   checked in `open` only: a click that follows a link, a form submit or
   `eval`-driven navigation to another host is not checked. Declaring a target
   does not authorize anything.
3. **`snapshot` first, and again after every change.** Refs are content-derived
   and go stale the moment the DOM moves. A ref from a page that has since
   re-rendered resolves to nothing.
4. **One session per target and per identity.** Commands without `--session`
   share `$WORK/browser-session`; two invocations against the same session act
   on one browser. Give a separate engagement, or a separate login, its own
   `--session` directory.
5. **Evidence goes to `$WORK`, and it is credential material.** Screenshots,
   HAR files and `cookies` output contain session cookies, bearer tokens and
   response bodies. Never paste them into the transcript, and delete them when
   the engagement closes.
6. **`eval` and `click` are active, not observational.** In-page JavaScript and
   any click can submit a form, change server state, or hit a destructive
   endpoint. Treat both as actions needing the same authorization as `curl -X
   POST`.
7. **Nothing here changes attribution.** The browser has no proxy setting and no
   route of its own: all of its traffic leaves through the WireGuard tunnel in
   the shared network namespace, exactly like every other tool.

## Command reference

Global options. They belong to the invocation, so they go **before** the
subcommand — `browser --target host open https://host/` parses, `browser open
https://host/ --target host` fails with `unrecognized arguments`.

| Option | Meaning |
|---|---|
| `--session DIR` | Session directory (default `$WORK/browser-session`) |
| `--target HOST` | Authorized host, repeatable. When set, `open` refuses a URL whose host is not the target or a subdomain of it |
| `--timeout SECONDS` | Per-action timeout, default 30. Becomes Playwright's default timeout for navigation and for every locator action |
| `--har PATH` | Write a HAR 1.2 file of every response seen during this invocation |

| Command | What it does |
|---|---|
| `open URL` | Navigate the page. Prints `<status> <url>`, or `no-response <url>` when the navigation produced no HTTP response (a `data:` URL, for example) |
| `snapshot` | Print the named elements with `@ref`s — the map of what is clickable and fillable right now |
| `text [SELECTOR]` | Visible text of the first match, or of `<body>` if no selector is given |
| `html [SELECTOR]` | `innerHTML` of the first match, or the whole rendered DOM if no selector is given |
| `eval JS` | Evaluate JavaScript in the page. A returned promise is awaited |
| `click SELECTOR` | Click, then print the URL the page is on afterwards |
| `fill SELECTOR VALUE` | Clear the field and fill it |
| `select SELECTOR VALUE` | Choose an option in a `<select>` by value or by label |
| `press KEY [SELECTOR]` | Press a key, on the element if a selector is given, otherwise on the page. Playwright key names: `Enter`, `Tab`, `Escape`, `ArrowDown`, `Control+A` |
| `wait [SELECTOR]` | Wait for an element, a load state, a JS condition or a fixed number of milliseconds |
| `screenshot [PATH]` | Write a PNG and print its path |
| `cookies` | List cookies, or `--clear` them |
| `storage` | Read or clear web storage |
| `headers` | Add request headers, scoped to one origin, for this invocation |
| `close` | Kill the session's browser process and drop `session.json` |
| `run [FILE]` | Read the same commands from `FILE`, or from stdin when no file is given |

Options that belong to a single command:

| Option | Applies to | Meaning |
|---|---|---|
| `--wait load\|domcontentloaded\|networkidle\|commit` | `open` | When navigation is considered finished. Default `load` |
| `--json` | `snapshot` | Print the snapshot as one JSON object instead of the text tree |
| `--state STATE` | `wait` | Element state to wait for: `visible` (default), `attached`, `hidden`, `detached` |
| `--load STATE` | `wait` | Wait for a page load state: `load`, `domcontentloaded`, `networkidle` |
| `--fn EXPR` | `wait` | Wait until the JavaScript expression is truthy |
| `--ms N` | `wait` | Wait N milliseconds |
| `--full` | `screenshot` | Capture the full page instead of the 1280×1024 viewport |
| `--dir DIR` | `screenshot` | Output directory when no path is given (default `$WORK/screenshots`) |
| `--clear` | `cookies`, `storage` | Clear instead of listing |
| `--local` | `storage` | Read or clear `localStorage`. **Without it, `storage` acts on `sessionStorage`** |
| `-H, --header NAME=VALUE` | `headers` | Header to inject; repeatable. Needs at least one, and the separator is `=`, not `:` |
| `--origin ORIGIN` | `headers` | Origin to scope the headers to. Default: the page's current origin |

### Selectors

Every command that takes a `SELECTOR` accepts three things, resolved in this
order by Playwright:

- an `@ref` from the most recent `snapshot` — `click @1a2b3c`;
- a CSS selector — `fill "#password" "hunter2"`;
- an XPath selector — `text "//h1"` (Playwright detects the `//` prefix, or use
  `xpath=…` explicitly).

Only the first match is used, so an over-broad CSS selector does not error: it
silently acts on the first element Playwright finds in DOM order. When a result
is surprising, run `snapshot` and act on a ref instead.

### `snapshot`

`snapshot` prints the page's addressable elements, one per line:

```
url: http://127.0.0.1:8090/login
title: Sign in
@19f3ab2 heading "Sign in"
@7c41d0e textbox "username"
@2b8e5f1 textbox "password"
@4d5e6fa button "Sign in"
```

- The first two lines are the page URL and `document.title`.
- Each element line is `@<ref> <role> "<name>"`, or `@<ref> <role>` when the
  element has no accessible name.
- `<role>` is the element's `role` attribute if it has one, otherwise an
  implicit role: `input` → `textbox`/`checkbox`/`radio`/`button` by type,
  `select` → `combobox`, `textarea` → `textbox`, `a[href]` → `link`, `button` →
  `button`, `h1`–`h6` → `heading`, `img` → `img`, `form` → `form`. An element
  whose role cannot be worked out — a bare `<div>` or `<span>` — is not listed
  at all.
- `<name>` is, in order of preference, `aria-label`, `placeholder`, `alt`, the
  `name` attribute, then the element's text content; whitespace is collapsed and
  the value is cut at 120 characters.
- Elements hidden by `display:none` are excluded: an element whose `offsetParent`
  is null is skipped, except `<option>`.
- The ref is `@` plus a hash of `tag|role|name`. Two elements with the same tag,
  role and name share a ref, and only the first is listed — so a ref identifies a
  *kind* of element on this page, not a unique node.
- `snapshot` writes `data-pen-ref` attributes into the DOM. They show up in
  `html` output and are removed and rewritten on the next snapshot.

`snapshot --json` prints one line instead — `{"url":…,"title":…,"nodes":[{"ref":…,
"role":…,"name":…,"tag":…}]}` — which is the form to parse:

```bash
browser snapshot --json | jq -r '.nodes[] | [.role, .name, .ref] | @tsv'
```

### `run` scripts

`run` executes the same command grammar, one command per line, in a single
process. Session-wide options belong to the outer invocation:
`browser --target host --har out.har run flow.txt`.

- Lines are split with shell quoting rules, so quote any value containing
  spaces: `fill @2b8e5f1 "hunter two"`.
- **Quoting is not shell expansion.** There is no shell in the loop: `$WORK` on
  a line stays the literal string `$WORK` (and `~` stays `~`), so a relative
  path that starts with `$` lands in the current directory. Either write the
  absolute path, or pipe the script in with an *unquoted* heredoc (`<<EOF`) and
  let the invoking shell expand it first.
- A line whose first word starts with `#` is a comment; blank lines are ignored.
- `run` cannot appear inside a run script.
- `close` ends the script immediately (the remaining lines are not executed).
- The first failing line aborts the script with exit code 1; the lines after it
  do not run, and the browser is left alive with the state it had reached.
- With no file argument, `run` reads stdin — `browser run <<'EOF' … EOF`.

## Typical workflows

1. **Look at a page before touching it.** `snapshot` is the recommended first
   step after every `open`.

   ```bash
   browser --target 127.0.0.1 open http://127.0.0.1:8090/login
   browser snapshot
   ```

2. **Drive a form.**

   ```bash
   browser --target 127.0.0.1 fill @2b8e5f1 "hunter2"
   browser --target 127.0.0.1 fill @7c41d0e "greg"
   browser --target 127.0.0.1 click @4d5e6fa     # prints the URL it landed on
   browser --target 127.0.0.1 text "#who"
   ```

   Each line is a separate process attaching to the same browser; the login
   state persists, so the destructive step is one command you can choose to run
   rather than a batch you fire blindly.

3. **Do the same thing as one script**, when the flow is known and the value of
   a ref cannot change under you:

   ```bash
   browser --target 127.0.0.1 run <<'EOF'
   open http://127.0.0.1:8090/login
   snapshot
   fill @7c41d0e "greg"
   fill @2b8e5f1 "hunter2"
   click @4d5e6fa
   wait --load networkidle
   text "#who"
   EOF
   ```

4. **Hold the browser open across commands and close it deliberately.**

   ```bash
   browser cookies              # who am I, right now
   browser storage --local      # what the app stored
   browser close                # kills the process and drops session.json
   ```

   Nothing else kills the browser: a normal command disconnects and leaves
   Chromium running.

`EXAMPLES.md` in this directory has six complete workflows: runtime
confirmation of a DOM-XSS sink, mapping an SPA's post-hydration routes,
reusing an authenticated session, evidence screenshots, injecting a bearer
token, and a multi-step `run` flow.

## Output and parsing

| Command | stdout |
|---|---|
| `open` | `<status> <final-url>`, or `no-response <final-url>` |
| `snapshot` | The text tree above, or one JSON object with `--json` |
| `text` | The element's visible text, as rendered (no tags) |
| `html` | Serialized DOM; includes `data-pen-ref` attributes if `snapshot` has run |
| `eval` | The result as-is if it is a string, otherwise compact JSON on one line (`json.dumps`, no indentation) |
| `click` | `clicked <selector> -> <url>` |
| `fill` | `filled <selector>` |
| `select` | `selected <value>` |
| `press` | `pressed <key>` |
| `wait` | `ok` |
| `screenshot` | The path written |
| `cookies` | `<n> cookie(s)`, then one `domain<TAB>name<TAB>value` line per cookie; `cookies cleared` with `--clear` |
| `storage` | The entries as indented JSON; `<kind> cleared` with `--clear` |
| `headers` | `applying <header names> to <scheme>://<host>/**` — names only, never values |
| `close` | `closed` |

Exit codes:

| Code | Meaning |
|---|---|
| 0 | The command ran (a page that matched nothing is still a success) |
| 1 | Tool error. One line on stderr, `browser: <reason>`; a Playwright failure adds its exception type, `browser: TimeoutError: …` |
| 2 | No subcommand, or an argument error from the usage parser (`browser: error: unrecognized arguments: …`) |

In pipelines, test the exit code for "the tool worked" and parse stdout for the
result: `browser wait --fn "…"` exiting 0 proves the condition held, not that
anything was found.

### HAR files

`--har PATH` records every response the browser receives **during that
invocation** and writes HAR 1.2 when the run ends. It is a valid HAR envelope —
`{"log":{"version":"1.2","creator":{"name":"pen browser","version":"1"},
"entries":[…]}}` — with these properties worth knowing before you parse it:

- `log.entries[].response.content.text` holds the body inline, and `size` its
  length. There is no `mimeType` fidelity: every entry says `text/plain`,
  regardless of what was served.
- A response that could not be read as text gets `content.text: null` and
  `content.size: 0`. Binary responses are not recoverable from the HAR.
- `time`, `timings`, `queryString` and `cookies` are placeholders (0, zeros, and
  empty arrays). Use the target's own logs or `mitmdump` if you need timing or
  cookies.
- A failed request appears as an entry with `response.status: 0`,
  `statusText: "failed"`, and **no** `content.text` key — so `// empty` guards
  `.content.text` in jq.
- The file is written when the invocation ends, in `finally` — a `SIGKILL`ed or
  timed-out process leaves no HAR at all. A run that saw no traffic still writes
  a valid HAR with an empty `entries` array.
- Each `--har` invocation **overwrites** its path. Pass a distinct path per
  invocation, or wrap the flow in one `browser run`.

```bash
# every response, in order
jq -r '.log.entries[] | [.response.status, .request.method, .request.url] | @tsv' "$WORK/har/xss.har"
# the URL set the page actually touched, including third-party origins
jq -r '.log.entries[].request.url' "$WORK/har/xss.har" | sed 's#\(://[^/]*\).*#\1#' | sort -u
# requests to an API path, with bodies
jq -r '.log.entries[] | select(.request.url|test("/api/"))
       | "\(.request.url)\t\(.response.content.text // "")"' "$WORK/har/xss.har"
# what failed
jq -r '.log.entries[] | select(.response.status == 0) | .request.url' "$WORK/har/xss.har"
# size before you read it — an asset-heavy page is tens of MB
jq '.log.entries | length' "$WORK/har/xss.har"; du -h "$WORK/har/xss.har"
```

## Chaining with the rest of the toolchain

`browser` answers questions the other tools cannot: what the DOM does with a
payload, which routes exist after hydration, what a session looks like from
inside the page. Its output is a URL list, a header set, a screenshot, or a
HAR file — all of which the rest of the toolchain consumes.

```bash
# the SPA's post-hydration routes and XHR endpoints -> the crawler and the scanner
jq -r '.log.entries[].request.url' "$WORK/har/spa.har" | sort -u > "$WORK/browser/urls.txt"
nuclei -l "$WORK/browser/urls.txt" -tags exposure,misconfig -ni -rl 25 -c 10 \
  -silent -jsonl -duc -o "$WORK/nuclei/browser-urls.jsonl"
```

```bash
# a runtime-confirmed sink's parameter -> the reflection and injection tools
# (a URL dalfox flagged [A], confirmed in the browser, is now worth payload work)
dalfox scan 'https://$TARGET/search?q=test' --workers 2 --delay 100 \
  -f json -o "$WORK/dalfox/search.json" < /dev/null

# the parameters the page actually reads -> content and injection fuzzing
jq -r '.nodes[].name' "$WORK/browser/snapshot.json" | sort -u > "$WORK/ffuf/names.txt"
ffuf -w "$WORK/ffuf/names.txt:FUZZ" -u 'https://$TARGET/search?q=FUZZ' \
  -mr 'FUZZ' -mc all -t 10 -rate 20 -of json -o "$WORK/ffuf/reflect.json"
```

```bash
# endpoints found at runtime -> parameter discovery -> SQL injection checks
arjun -u "https://$TARGET/api/items?id=1" -m GET -t 3 --rate-limit 10 \
  -oJ "$WORK/arjun/items.json"
jq -r 'to_entries[] | .key as $u | .value.params[] | "\($u)&\(.)=1"' "$WORK/arjun/items.json" \
  | while read -r q; do
      sqlmap -u "${q/&/?}" --batch --smart --level 1 --risk 1 \
        --output-dir "$WORK/sqlmap" >/dev/null
    done
```

```bash
# what a page's JavaScript revealed about secrets -> the secret scanner
jq -r '.log.entries[].response.content.text // empty' "$WORK/har/spa.har" \
  | trufflehog --no-update --no-verification --json stdin > "$WORK/trufflehog/har.jsonl"
```

`katana` and `browser` answer different halves of the same question. `katana
-jc` reads endpoints out of JavaScript statically and is the cheap first pass;
`katana -hl` crawls with a real engine but reports URLs. `browser` is what you
use when you need the DOM *state* — a ref to click, the value a sink produced, a
screenshot for the report. Run `katana` first to get the surface, then `browser`
on the pages where the behaviour matters.

`mitmproxy` pairs with it as the rewrite half of the pair, with one limitation
to be explicit about: **`browser` cannot be pointed at an interception proxy.**
It has no proxy flag, Chromium is launched with a fixed flag list, and
Playwright connects over CDP — nothing in this CLI puts `mitmdump` in the
browser's path. What actually pairs:

```bash
# the browser's own record is the HAR; the rewriting client is curl through mitmdump
jq -r '.log.entries[] | select(.response.status==200) | .request.url' "$WORK/har/spa.har" \
  | head -1 | while read -r u; do
      mitmdump -q -p 8888 --set confdir="$WORK/mitm-ca" \
        --set 'modify_body=|~u /app.js/PEN-REWRITTEN/' &
      curl -s -o /dev/null -w '%{http_code}\n' -x http://127.0.0.1:8888 --cacert "$WORK/mitm-ca/mitmproxy-ca-cert.pem" "$u"
      kill %1
    done
```

Use the HAR to learn *what* to rewrite or replay, and `mitmdump` to do it for a
client that honours a proxy. Do not assume a `http_proxy` variable in the
environment puts the browser behind the proxy: nothing in this tool configures
one.

## Limits, failure modes and gotchas

- **A container restart kills the browser; the next command relaunches it.**
  `session.json` holds only a pid, a port and a start time — no cookies, no
  storage. When the pid is gone, the next command launches a fresh Chromium, and
  the session starts empty except for whatever the *profile directory* had
  already flushed to disk (`$WORK/browser-session/profile`, which survives a
  restart because it is on the workspace). Cookies with an expiry, `localStorage`
  for origins already visited, and any state a page persisted to IndexedDB come
  back; in-memory session state and session cookies do not. If the pid has been
  recycled by an unrelated process, the first command after the restart fails
  with `browser: the browser on port <port> stopped answering: …` and the
  *following* one launches cleanly — re-run before concluding the tool is broken.
- **A `@ref` goes stale the moment the page changes.** The ref is a hash of the
  element's tag, role and name, and it is validated only by looking for the
  `data-pen-ref` attribute in the current DOM. After a framework re-render,
  `click @1a2b3c` fails with `browser: @1a2b3c is not in the current page; run
  `snapshot` again`. Re-snapshot; do not guess a ref.
- **A snapshot of a page that has not rendered is empty, not an error.** It
  exits 0 and prints `(no named elements — the page may not have rendered)`.
  That is indistinguishable from a page of plain `<div>`s with no roles, so if
  the list is empty and you expected content, `wait --fn "…"`, `text`, or
  `html` before concluding the page has no elements.
- **`--har` bodies are inline and can be very large.** Every response the page
  loaded is stored with `content.text` — on an asset-heavy page that is tens of
  megabytes of indented JSON in one file. Record only the navigation you care
  about, check `du -h` before reading it, and delete it at the end of the
  engagement.
- **The browser is Playwright's Chromium build, not branded Chrome.** It is
  `chromium-headless-shell` 153.0.8010.12, no channel is set, and there is no
  Google Chrome in the image. Version-specific quirks of a real branded Chrome
  may not reproduce, and headless-only behaviour (no window, no extensions, no
  codecs from Chrome's bundle) is what you are testing.
- **`snapshot` skips fixed-position elements.** The filter is `offsetParent ===
  null`, which is also true for `position:fixed`: sticky headers, fixed footers
  and modal overlays are not listed even when they are visible on screen. Reach
  them with a CSS selector instead.
- **A missing selector costs the full timeout.** `text "#nope"` on a page
  without that id waits `--timeout` seconds (30 by default) and then fails with
  `browser: TimeoutError: Locator.inner_text: Timeout 30000ms exceeded …`.
  Nothing is instant-fail here; on a slow target raise `--timeout` instead of
  retrying blindly.
- **`--target` guards `open` only.** `check_scope` runs before `goto`, and
  nothing else calls it: a click that follows a link to another host, a form
  action on another origin, an `eval`-driven `location.href` change, and every
  subresource the page pulls in (CDN, analytics, OAuth provider) are all
  unchecked. `--target` catches typos, not scope.
- **`storage` reads `sessionStorage` unless you pass `--local`.** Most
  "authenticated session" logic uses `localStorage`; `browser storage` against a
  `localStorage`-based app looks empty. It also reads the origin of the *current*
  page, so `open` the app first.
- **`headers -H` takes `NAME=VALUE`, not `NAME: VALUE`.** The tool splits on the
  first `=`, so `-H 'Authorization: Bearer x'` has no `=` and becomes one header
  named `Authorization: Bearer x` with an empty value — not an `Authorization`
  header, while `headers` prints a success line regardless. With no `-H` at all
  it fails (`browser: pass at least one -H name=value`). And the handler lives
  in the Playwright connection this invocation opens, so inject the headers and
  make the request that needs them in the *same* `browser run` script; a
  `headers` command on its own applies to nothing.
- **The page `eval` runs in is the page the tool is holding.** If a site opens a
  new tab, that tab is invisible to every command: the CLI always acts on the
  first page of the context. There is no flag to select or switch pages, and no
  file-upload or download handling.
- **`eval` cannot distinguish `undefined` from `null`.** A non-string result is
  printed with `json.dumps`, and JavaScript `undefined` arrives as Python
  `None`, which prints as `null`. Use `typeof x` or an explicit comparison when
  the difference matters.
- **A bare `wait` is a no-op that prints `ok`.** With no selector, no `--load`
  and no `--fn`, it falls through to `--ms`, whose default is 0. `browser wait`
  returns immediately and looks successful. Always give it a condition.
- **`browser run` with neither a file nor a stdin redirect reads stdin.** On a
  closed or empty stdin it launches a browser, executes nothing and exits 0 —
  a silent no-op. Pass the file, or a heredoc.
- **With `--target` set, a `data:` URL is refused.** `data:` and `about:` URLs
  have no hostname, so the scope check rejects them with `… is outside the
  declared scope`. Drop `--target` for a local smoke test.
- **Local fixtures use port 8090, not 8080.** In this namespace 8080 is the VPN
  gateway's unauthenticated exit-node control API, already bound and answering
  401 — a "target" there is the control plane, not a test service
  (`python3 -m http.server 8090 --bind 127.0.0.1`, target
  `http://127.0.0.1:8090/`). A port that appears *inside* a scan's target list is
  a different thing and keeps its own number.
- **Two invocations against one session share one page.** There is no locking.
  Concurrent runs interleave their navigations in the same tab, so a `--har`
  file can contain another run's traffic. Serialize browser work.
- **The browser keeps running until `close`.** Every other command disconnects
  and leaves Chromium alive, holding the profile and a debugging port. Close the
  session when the workflow is done, or the next engagement's first `open` may
  attach to a browser still holding an authenticated session.
- **`chromium.log` is opened in append mode** and keeps the browser's stdout and
  stderr, including every DevTools protocol warning. It is the first place to
  look when a launch fails (`chromium exited immediately`), and it is not
  rotation-managed.

## Safety and scope

- Every browser action is attack traffic against a real target. Run it only
  against hosts explicitly authorized for the current engagement, and treat an
  unclear target as unauthorized.
- Executing page JavaScript is active interaction, not observation: `eval` and
  any click can change server state, submit forms and trigger destructive
  endpoints. Authorize those the way you would authorize a `POST`, and prefer
  `snapshot`/`text`/`html` until you have a reason to act.
- Screenshots and HAR files are credential material. They contain cookies,
  tokens and full response bodies, and a screenshot of a signed-in page is
  proof-of-access. Keep them in `$WORK`, never paste their contents into the
  transcript, and delete them at engagement close.
- Navigating to a third-party origin broadens scope, even when the page pulls
  it in automatically — a CDN, an OAuth provider, an analytics host. Capture
  the origins that appear in the HAR (`jq -r '.log.entries[].request.url'`), and
  treat any interactive use of them as requiring confirmation. `--target` does
  not stop the page from loading them.
- `--target` is a guard against accidents, not an authorization decision. It
  covers `open` only; the decision about what is in scope is yours, made before
  the first navigation.
