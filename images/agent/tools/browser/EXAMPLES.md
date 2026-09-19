# browser — worked examples

Six complete workflows: runtime confirmation of a DOM-XSS sink, an SPA's
post-hydration routes, an authenticated session reused across processes,
evidence screenshots, bearer-token injection, and a multi-step `run` flow.
Every flag used here is from the pinned source described in `AGENTS.md`.

Two notes on provenance, so nothing below is read as more than it is:

- The output blocks show the exact format `browser` prints — they are taken
  from the source's print statements and from the fixtures below, not from a
  captured terminal transcript. Run example 1 end to end against its fixture
  before trusting the rest against a live target.
- The fixtures are local and deliberately vulnerable. They are the safe place to
  learn the workflow; the same command against a real host is an attack on that
  host and needs the authorization described in `AGENTS.md`'s *Safety and scope*.

```bash
export WORK=/working/engagements/example
mkdir -p "$WORK"/{fixtures,flows,har,evidence,browser}
cd "$WORK/fixtures"

# Every invocation below talks to one browser: $WORK/browser-session.
# --target is checked by `open` only, and never changes what the page may load.
BROWSER="browser --target 127.0.0.1 --session $WORK/browser-session"
```

## 1. Confirm a DOM-XSS sink that only fires at runtime

`dalfox` reports a DOM-XSS *candidate* (`[A]`) from static analysis: it saw
`innerHTML = location.search` in the source. That is a claim about a victim's
browser, and only a browser can settle it. This fixture has exactly that sink
behind the URL hash, which never leaves the browser.

```bash
cat > "$WORK/fixtures/domxss.html" <<'EOF'
<!doctype html>
<html>
<head><title>Search</title></head>
<body>
<h1>Search</h1>
<input id="q" name="q" placeholder="search term">
<p id="echo"></p>
<div id="results"></div>
<script>
  var q = decodeURIComponent(location.hash.slice(1));
  if (q) {
    document.getElementById('echo').textContent = q;
    document.getElementById('results').innerHTML = q;
  }
</script>
</body>
</html>
EOF

cd "$WORK/fixtures" && python3 -m http.server 8090 --bind 127.0.0.1 &
sleep 2
curl -s -o /dev/null -w 'fixture status=%{http_code}\n' http://127.0.0.1:8090/domxss.html
```

**Step 1 — the negative control.** First establish what the page does with no
payload, so the finding is a difference and not a constant.

```bash
browser --target 127.0.0.1 --session "$WORK/browser-session" \
  open http://127.0.0.1:8090/domxss.html
$BROWSER eval "typeof window.__penFired"
```

```
200 http://127.0.0.1:8090/domxss.html
undefined
```

`typeof` is deliberate: a bare `browser eval "window.__penFired"` prints `null`
both for a missing property and for a real `null`, so it cannot distinguish
"the payload did not run" from "the payload ran and set null".

**Step 2 — the payload.** The hash is not sent to the server, so nothing about
this request is visible to a server-side scanner. The `onerror` handler is the
proof: it only fires if the engine parsed the string as HTML and then tried to
load the image.

```bash
$BROWSER open 'http://127.0.0.1:8090/domxss.html#<img src=x onerror="window.__penFired=1">'
$BROWSER eval "typeof window.__penFired"
$BROWSER eval "window.__penFired"
$BROWSER html "#results"
```

```
200 http://127.0.0.1:8090/domxss.html#<img src=x onerror="window.__penFired=1">
number
1
<img src="x" onerror="window.__penFired=1">
```

That is the confirmation: the sink is live, the engine executed the injected
handler, and the DOM holds the parsed node. Record all four facts in the
finding — the URL, the sink, the marker expression, and its value.

**Step 3 — evidence, in one process so the HAR is written.** Global options go
before the subcommand, which is why this one is written out in full.

```bash
browser --session "$WORK/browser-session" --har "$WORK/har/domxss.har" run <<'EOF'
open http://127.0.0.1:8090/domxss.html#<img src=x onerror="window.__penFired=1">
screenshot $WORK/evidence/domxss-sink.png
eval "document.getElementById('results').innerHTML"
close
EOF
jq -r '.log.entries[] | [.response.status, .request.url] | @tsv' "$WORK/har/domxss.har"
```

```
200 http://127.0.0.1:8090/domxss.html#<img src=x onerror="window.__penFired=1">
/working/engagements/example/evidence/domxss-sink.png
<img src="x" onerror="window.__penFired=1">
closed
200	http://127.0.0.1:8090/domxss.html
```

Note what the HAR does **not** contain: the sink fired entirely in the browser,
so the only server-side evidence is the page fetch. For a client-side finding
the evidence is the screenshot, the `eval` output and the payload URL — capture
all three or the finding is not reproducible.

**Against a real target**, the same three steps are one `open` with the payload
in the parameter the scanner flagged, and the marker check afterwards. That is
active interaction with the target, executing attacker-controlled script in the
target's origin as whoever the browser session is signed in as: get
confirmation before it, not after.

## 2. Map an SPA's post-hydration routes

A route table that arrives after load is invisible to `curl`, to `gobuster`, and
to a crawler that does not execute JavaScript. This fixture fetches its routes,
renders them, and re-renders the whole app on every route change — which is also
how refs go stale.

```bash
mkdir -p "$WORK/fixtures/spa"
cat > "$WORK/fixtures/spa/routes.json" <<'EOF'
{"/": "Home", "/orders": "Orders", "/orders/1042": "Order 1042", "/admin": "Admin"}
EOF
cat > "$WORK/fixtures/spa/order-1042.json" <<'EOF'
{"id": 1042, "total": 42.5}
EOF
cat > "$WORK/fixtures/spa/index.html" <<'EOF'
<!doctype html>
<html>
<head><title>SPA fixture</title></head>
<body>
<div id="app">loading&hellip;</div>
<script>
const routes = {};
let nav = '';
function render() {
  const path = location.hash.slice(1) || '/';
  document.getElementById('app').innerHTML =
    '<h1>SPA fixture</h1><nav>' + nav + '</nav>' +
    '<button id="load">Load order</button>' +
    '<div id="view">' + (routes[path] || 'not found') + '</div>';
  document.getElementById('load').addEventListener('click', () => {
    fetch('/spa/order-1042.json').then((r) => r.json()).then((o) => {
      document.getElementById('view').textContent = 'order ' + o.id + ' total ' + o.total;
    });
  });
}
fetch('/spa/routes.json').then((r) => r.json()).then((data) => {
  Object.assign(routes, data);
  nav = Object.entries(routes)
    .map(([path, title]) => '<a href="#' + path + '">' + title + '</a>').join(' ');
  window.addEventListener('hashchange', render);
  render();
});
</script>
</body>
</html>
EOF
```

**Step 1 — see the un-hydrated page, and see that it is not an error.**

```bash
$BROWSER open http://127.0.0.1:8090/spa/ --wait commit
$BROWSER snapshot; echo "exit=$?"
```

```
200 http://127.0.0.1:8090/spa/
url: http://127.0.0.1:8090/spa/
title:
(no named elements — the page may not have rendered)
exit=0
```

Exit 0 with no elements is the trap: it means "nothing addressable", not "this
page is empty". A bare `<div>` never appears in a snapshot anyway. The `title:`
line may already read `SPA fixture` if the head parsed before the commit
returned; what matters is that no `link` elements are listed.

**Step 2 — wait for hydration deterministically, then look.**

```bash
$BROWSER wait --fn "document.querySelectorAll('nav a').length > 0"
$BROWSER snapshot
```

```
ok
url: http://127.0.0.1:8090/spa/
title: SPA fixture
@1e2f3a4 heading "SPA fixture"
@5b6c7d8 link "Home"
@9a0b1c2 link "Orders"
@3d4e5f6 link "Order 1042"
@7a8b9c0 link "Admin"
@2c3d4e5 button "Load order"
```

**Step 3 — collect the routes.** Each click re-renders `#app`, so every
`data-pen-ref` attribute from the previous snapshot is destroyed. The first
stale ref looks like this:

```bash
$BROWSER click @5b6c7d8      # the "Home" ref from the snapshot above
$BROWSER click @9a0b1c2      # the "Orders" ref, from the same snapshot
```

```
clicked @5b6c7d8 -> http://127.0.0.1:8090/spa/#/
browser: @9a0b1c2 is not in the current page; run `snapshot` again
```

That is the whole rule in one line: re-snapshot after every page change. The
crawl loop does it every round.

```bash
: > "$WORK/browser/spa-routes.txt"
for round in 1 2 3 4 5; do
  $BROWSER snapshot --json > "$WORK/browser/spa-snapshot.json"
  ref=$(jq -r '.nodes[] | select(.role=="link") | .ref' \
        "$WORK/browser/spa-snapshot.json" | sed -n "${round}p")
  [ -n "$ref" ] || break
  $BROWSER click "$ref" > /dev/null
  $BROWSER wait --fn "document.querySelectorAll('nav a').length > 0" > /dev/null
  $BROWSER eval "location.href" >> "$WORK/browser/spa-routes.txt"
done
sort -u "$WORK/browser/spa-routes.txt"
```

```
http://127.0.0.1:8090/spa/#/
http://127.0.0.1:8090/spa/#/admin
http://127.0.0.1:8090/spa/#/orders
http://127.0.0.1:8090/spa/#/orders/1042
```

**Step 4 — take the request side too.** The routes are hash-only, so nothing
above ever reached the server. The XHR endpoints are the part the other tools
can act on.

```bash
browser --session "$WORK/browser-session" --har "$WORK/har/spa.har" run <<'EOF'
open http://127.0.0.1:8090/spa/
wait --fn "document.querySelectorAll('nav a').length > 0"
click "#load"
wait --fn "document.getElementById('view').textContent.indexOf('total') > -1"
text "#view"
EOF
jq -r '.log.entries[].request.url' "$WORK/har/spa.har" | sort -u
```

```
200 http://127.0.0.1:8090/spa/
ok
clicked #load -> http://127.0.0.1:8090/spa/
ok
order 1042 total 42.5
http://127.0.0.1:8090/spa/
http://127.0.0.1:8090/spa/order-1042.json
http://127.0.0.1:8090/spa/routes.json
```

A `/favicon.ico` request may appear too — read the HAR rather than this list.

`/spa/routes.json` and `/spa/order-1042.json` are endpoints no link-following
crawl would report, and `/spa/` is a directory worth fuzzing. Hand them over:

```bash
# the endpoints -> nuclei's exposure and misconfiguration templates
jq -r '.log.entries[].request.url' "$WORK/har/spa.har" | sort -u > "$WORK/browser/spa-urls.txt"
nuclei -l "$WORK/browser/spa-urls.txt" -tags exposure,misconfig -ni -rl 25 -c 10 \
  -silent -jsonl -duc -o "$WORK/har/spa-nuclei.jsonl"

# the app path -> content discovery
ffuf -w /opt/wordlists/current/Discovery/Web-Content/common.txt -u http://127.0.0.1:8090/spa/FUZZ \
  -mc all -fc 404 -t 10 -rate 20 -of json -o "$WORK/browser/spa-ffuf.json"
```

Compare with `katana -jc`, which would have read the same path strings out of
the JavaScript statically. The browser's advantage here is not the strings — it
is knowing which of them the app actually calls, and in what order.

## 3. Reuse an authenticated session across commands

The point of the session directory: a login performed by one process is still
there for the next one. This fixture holds its state in `localStorage`, which is
the case that matters — it is invisible to `cookies`.

```bash
mkdir -p "$WORK/fixtures/auth"
cat > "$WORK/fixtures/auth/index.html" <<'EOF'
<!doctype html>
<html>
<head><title>Sign in</title></head>
<body>
<h1>Sign in</h1>
<form id="login">
  <label for="username">Username</label>
  <input id="username" name="username">
  <label for="password">Password</label>
  <input id="password" name="password" type="password">
  <button type="submit">Sign in</button>
</form>
<script>
document.getElementById('login').addEventListener('submit', (event) => {
  event.preventDefault();
  localStorage.setItem('pen_token', 'demo-token-' + document.getElementById('username').value);
  location.href = '/auth/account.html';
});
</script>
</body>
</html>
EOF
cat > "$WORK/fixtures/auth/account.html" <<'EOF'
<!doctype html>
<html>
<head><title>Account</title></head>
<body>
<h1>Account</h1>
<p id="who">not signed in</p>
<script>
const token = localStorage.getItem('pen_token');
document.getElementById('who').textContent = token ? 'signed in with ' + token : 'not signed in';
</script>
</body>
</html>
EOF
```

**Step 1 — the control.** An empty session, so the signed-in result later is a
difference and not a default.

```bash
browser --session "$WORK/browser-session-empty" --target 127.0.0.1 \
  open http://127.0.0.1:8090/auth/account.html
browser --session "$WORK/browser-session-empty" text "#who"
```

```
200 http://127.0.0.1:8090/auth/account.html
not signed in
```

**Step 2 — sign in, in one process.** CSS selectors rather than `@ref`s: a ref
belongs to one snapshot of one page, and a file of hard-coded refs is a file
that breaks the next time the page renders. No `close` line — the browser has
to outlive this script.

```bash
cat > "$WORK/flows/login.txt" <<'EOF'
# Sign in and land on the account page.
open http://127.0.0.1:8090/auth/
snapshot
fill "#username" "greg"
fill "#password" "hunter2"
click "button[type=submit]"
wait --load networkidle
text "#who"
EOF

browser --target 127.0.0.1 --session "$WORK/browser-session" run "$WORK/flows/login.txt"
```

```
200 http://127.0.0.1:8090/auth/
url: http://127.0.0.1:8090/auth/
title: Sign in
@2f7a1b9 heading "Sign in"
@6c0d4e2 textbox "username"
@8b1f5a3 textbox "password"
@4e9c7d0 button "Sign in"
filled #username
filled #password
clicked button[type=submit] -> http://127.0.0.1:8090/auth/account.html
ok
signed in with demo-token-greg
```

**Step 3 — three new processes, same session.** Nothing above is held in
memory: each command is a fresh `browser` that attaches to the running Chromium
and reads the profile on disk.

```bash
browser --session "$WORK/browser-session" cookies
browser --session "$WORK/browser-session" storage --local
browser --target 127.0.0.1 --session "$WORK/browser-session" \
  open http://127.0.0.1:8090/auth/account.html
browser --session "$WORK/browser-session" text "#who"
```

```
0 cookie(s)
{
 "pen_token": "demo-token-greg"
}
200 http://127.0.0.1:8090/auth/account.html
signed in with demo-token-greg
```

`0 cookie(s)` with a live session is the lesson: `storage` without `--local`
would have printed `{}` here (it reads `sessionStorage` by default), and the
token is credential material — do not paste that block into the transcript.

**Step 4 — close both sessions.** The empty one has been running this whole
time.

```bash
browser --session "$WORK/browser-session" close
browser --session "$WORK/browser-session-empty" close
```

```
closed
closed
```

A container restart in the middle of this would have relaunched Chromium on the
next command. The `pen_token` value would have survived in
`$WORK/browser-session/profile` (it is `localStorage` with no expiry, on the
workspace), but anything held only in memory, and any session cookie without an
expiry, would be gone. Re-check `text "#who"` after any restart before trusting
a session.

## 4. Evidence screenshots

The screenshot is the artefact that ends an argument: it shows what the browser
rendered, at a URL, at a time.

```bash
$BROWSER open 'http://127.0.0.1:8090/domxss.html#<img src=x onerror="window.__penFired=1">'

# default: $WORK/screenshots/<host_path>_<UTC timestamp>.png, viewport 1280x1024
$BROWSER screenshot

# the whole page, for a result below the fold
$BROWSER screenshot --full

# an explicit path is the reproducible form: name it after the finding
$BROWSER screenshot "$WORK/evidence/domxss-results-sink.png"

# or just choose the directory and keep the generated name
$BROWSER screenshot --dir "$WORK/evidence"
ls -l "$WORK/evidence" "$WORK/screenshots"
```

```
200 http://127.0.0.1:8090/domxss.html#<img src=x onerror="window.__penFired=1">
/working/engagements/example/screenshots/127.0.0.1_8090_domxss.html_20260917T101500.png
/working/engagements/example/screenshots/127.0.0.1_8090_domxss.html_20260917T101502.png
/working/engagements/example/evidence/domxss-results-sink.png
```

`$WORK/evidence`:
```
-rw-r--r-- 1 root root 48213 Sep 17 10:15 domxss-results-sink.png
```

`$WORK/screenshots`:
```
-rw-r--r-- 1 root root 41220 Sep 17 10:15 127.0.0.1_8090_domxss.html_20260917T101500.png
-rw-r--r-- 1 root root 63188 Sep 17 10:15 127.0.0.1_8090_domxss.html_20260917T101502.png
```

Notes that matter at engagement time:

- The generated name is the host and path with everything outside
  `[A-Za-z0-9._-]` replaced by `_`, cut to 80 characters, plus a UTC timestamp.
  It is unique but not descriptive; pass a path when the image is evidence.
- `--full` grows the file: the viewport is 1280×1024, a full-page capture of a
  long page can be several screen-heights. Keep the `.png` extension, which is
  what determines the image format.
- A screenshot of a signed-in page is proof-of-access and often contains tokens
  in a URL or a header value on screen. Keep it in `$WORK`, reference it in the
  report by path, and delete the directory at engagement close.
- Pair the screenshot with the text it is supposed to show, so the finding is
  greppable as well as visible: `$BROWSER text "#results" > "$WORK/evidence/domxss-results.txt"`.

## 5. Inject a bearer token with `headers`

`headers` adds request headers to every request matching one origin, through
request interception — the way to test an API route that the app itself only
calls after a login you do not want to perform. Prove it against an echo
fixture before pointing it at a target.

```bash
cat > "$WORK/fixtures/echo.py" <<'EOF'
import http.server, socketserver

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        body = "auth: %s\ncookie: %s\npath: %s\n" % (
            self.headers.get("Authorization", "(none)"),
            self.headers.get("Cookie", "(none)"),
            self.path)
        raw = body.encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def log_message(self, *args):
        pass

socketserver.TCPServer.allow_reuse_address = True
with socketserver.TCPServer(("127.0.0.1", 8090), Handler) as httpd:
    httpd.serve_forever()
EOF
```

Stop the static fixture first — one listener per port — then:

```bash
kill %1                     # the `python3 -m http.server 8090` from example 1
python3 "$WORK/fixtures/echo.py" &
sleep 1
curl -s http://127.0.0.1:8090/api/orders
```

```
auth: (none)
cookie: (none)
path: /api/orders
```

**With the header, in one process:**

```bash
browser --target 127.0.0.1 --session "$WORK/browser-session" run <<'EOF'
headers -H "Authorization=Bearer demo-token-greg" --origin http://127.0.0.1:8090
open http://127.0.0.1:8090/api/orders
text
EOF
```

```
applying Authorization to http://127.0.0.1:8090/**
200 http://127.0.0.1:8090/api/orders
auth: Bearer demo-token-greg
cookie: (none)
path: /api/orders
```

Read the details off that transcript:

- The separator is `=`. `-H "Authorization: Bearer …"` would have injected a
  header whose *name* is `Authorization: Bearer …`, and the echo would still say
  `auth: (none)` while `headers` printed a success line.
- `headers` prints header names only, never values, so the injection is visible
  in the transcript without leaking the token.
- The scope glob is `scheme://host/**` — everything on that origin, including
  subresources. Repeat `-H` for more than one header; a value containing `=`
  survives (`-H "X-Trace=a=b"` sets `X-Trace: a=b`).

**The failure to expect.** The route handler belongs to the Playwright
connection this invocation opens, and that connection is torn down when the
process exits. A lone `headers` command therefore covers nothing:

```bash
browser --session "$WORK/browser-session" headers -H "Authorization=Bearer demo-token-greg" \
  --origin http://127.0.0.1:8090
browser --target 127.0.0.1 --session "$WORK/browser-session" open http://127.0.0.1:8090/api/orders
browser --session "$WORK/browser-session" text
```

```
applying Authorization to http://127.0.0.1:8090/**
200 http://127.0.0.1:8090/api/orders
auth: (none)
cookie: (none)
path: /api/orders
```

The header was applied to a connection that then closed, and the second command
was a different process. Put `headers` and the request that needs it in the same
`run` script. Confirm the behaviour on your own target the first time rather
than assuming it: the fixture above is the cheap way to check.

**Handling the token.** Take it from a file created for the engagement, and let
the shell read it — typing it on the command line puts it in the transcript and
in `/root/.bash_history`:

```bash
printf '%s' "$TOKEN" > "$WORK/tokens/bearer.txt"
chmod 600 "$WORK/tokens/bearer.txt"
browser --target 127.0.0.1 run <<EOF
headers -H "Authorization=Bearer $(cat "$WORK/tokens/bearer.txt")" --origin http://127.0.0.1:8090
open http://127.0.0.1:8090/api/orders
text
EOF
```

Do not put the token on an `open` URL either: a query string ends up in the
target's access log and in the HAR.

## 6. A multi-step flow with `browser run`

When the flow is known, one process beats six: one browser connection, one
place the failure stops, one HAR for the whole thing. This script signs in,
reads the account page, and — because it is a script and not a decision — stops
at the first line that fails.

```bash
cat > "$WORK/flows/account-check.txt" <<'EOF'
# Sign in and prove the session is real, then capture evidence.
# CSS selectors, not @refs: a ref belongs to one snapshot of one page.
open http://127.0.0.1:8090/auth/
wait --fn "document.getElementById('username') !== null"
fill "#username" "greg"
fill "#password" "hunter2"
click "button[type=submit]"
wait --load networkidle
text "#who"
screenshot $WORK/evidence/account-signed-in.png
text "#not-a-real-element"
text "#never-reached"
# close is not reached either: the failing line above aborts the script
close
EOF

browser --target 127.0.0.1 --session "$WORK/browser-session" \
  --har "$WORK/har/account-check.har" run "$WORK/flows/account-check.txt"
echo "exit=$?"
```

```
200 http://127.0.0.1:8090/auth/
ok
filled #username
filled #password
clicked button[type=submit] -> http://127.0.0.1:8090/auth/account.html
ok
signed in with demo-token-greg
/working/engagements/example/evidence/account-signed-in.png
browser: TimeoutError: Locator.inner_text: Timeout 30000ms exceeded.
Call log:
  - waiting for locator("#not-a-real-element")
exit=1
```

Three things to read off that:

- `#never-reached` did not run, and neither did `close`. A run script is
  sequential and stops at the first failure; do not put cleanup after a step
  that can fail and expect it to run.
- The browser is still alive, signed in, at the account page — the failure
  stopped the script, not the session. That is useful: you can inspect the state
  the failure left behind.

  ```bash
  browser --session "$WORK/browser-session" text "#who"
  browser --session "$WORK/browser-session" screenshot "$WORK/evidence/account-after-failure.png"
  ```

- The HAR was still written, because the process exited normally with a tool
  error. A `SIGKILL` would have lost it.

  ```bash
  jq -r '.log.entries[] | [.response.status, .request.url] | @tsv' "$WORK/har/account-check.har"
  ```

  ```
  200	http://127.0.0.1:8090/auth/
  200	http://127.0.0.1:8090/auth/account.html
  ```

The same script from stdin, which is the form to use when the flow is generated
rather than written:

```bash
browser --target 127.0.0.1 --session "$WORK/browser-session" run <<'EOF'
open http://127.0.0.1:8090/auth/account.html
# blank lines and lines starting with # are ignored
text "#who"
close
EOF
```

```
200 http://127.0.0.1:8090/auth/account.html
signed in with demo-token-greg
closed
```

`close` ended the script there, so nothing after it in the file would run. The
browser is now down; the next `open` would launch a fresh one from
`$WORK/browser-session/profile`.

**Clean up the fixture** — and treat everything under `$WORK/har` and
`$WORK/evidence` as credential material until the engagement closes:

```bash
kill %1 2>/dev/null                       # the echo server, if still running
ls -l "$WORK/har" "$WORK/evidence"
# at engagement close: shred or delete the session directory, HARs and screenshots
rm -rf "$WORK/browser-session" "$WORK/har" "$WORK/evidence"
```
