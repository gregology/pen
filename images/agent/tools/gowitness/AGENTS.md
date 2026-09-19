# gowitness — screenshot and evidence collection at scale

gowitness loads each URL in a real Chrome, screenshots it, and can write the
response code, title, final URL, TLS detail, headers, cookies and console and
network logs alongside the image. Reach for it when a finding needs visual
evidence ("this admin panel is reachable and unauthenticated") or when a live
host list is too long to open by hand and a wall of screenshots is the fastest
triage. It is not a crawler ([`katana`](../katana/AGENTS.md)), not a
fingerprinter ([`whatweb`](../whatweb/AGENTS.md), `httpx`) and not a scanner: it
renders whatever you point it at, which also means it executes whatever
JavaScript that page serves.

## Installation and location

| Item | Value |
|---|---|
| Version | **3.2.0**, pinned static Go binary, sha256-verified at image build |
| Binary | `/usr/local/bin/gowitness` |
| Version check | `gowitness version` prints the banner, then version, git hash, build environment and build time |
| Command tree | `scan`, `report`, `version`; `scan` has `single`, `file`, `cidr`, `nmap`, `nessus`; `report` has `convert`, `generate`, `list`, `merge`, `migrate`, `server` |
| Browser | **none bundled.** gowitness downloads a platform-appropriate Chrome itself on first use unless told otherwise — see *Rules* |
| Default output | screenshots only, in `./screenshots`; **no metadata is written unless you ask** |
| Default screenshot | 1280x720 viewport (`--chrome-window-x`, `--chrome-window-y`), JPEG quality 60 |
| Default rate | 6 threads, 60 s page timeout, 3 s delay before each screenshot |
| Default driver | `chromedp` (`gorod` is the alternative) |
| Runs as | root; no TTY required |

```bash
gowitness version
gowitness scan --help
gowitness report generate --help
```

Every flag below is from the pinned 3.2.0 command definitions.

## Rules that apply to this tool

- **Authorization first.** gowitness visits every URL it is given and renders
  whatever comes back. A target list is a hit list; only confirmed hosts.
- **Write metadata deliberately, or the run is unqueryable.** The default saves
  screenshots and nothing else — upstream's own `gowitness scan --help` warning.
  Pass `--write-jsonl`, `--write-csv` or `--write-db` (or `--write-stdout`) on
  every run you intend to report from.
- **Bound the run.** `-t/--threads`, `-T/--timeout` and `--delay` are the only
  limits: a scan is a browser render per URL, so a 1,000-host list at the
  default 3 s delay is at least 50 minutes of wall clock before failures.
- **A screenshot is as loud as a crawl.** Each page load pulls its subresources
  and runs its scripts. Confirm the target list before the run, not after.
- **The browser download is the one remaining runtime browser download in the
  image.** It needs the VPN tunnel up to happen. Point gowitness at an existing
  browser with `--chrome-path`, or at a running DevTools instance with
  `--chrome-wss-url`, to avoid it.
- **It cannot use the sibling `browser` tool's binary.** That tool installs
  Playwright's `chromium-headless-shell`, which is a headless shell, not the
  `chrome` binary path gowitness wants. Do not point `--chrome-path` at it.
- **`--chrome-user-data-dir` pointed at a real profile reuses that profile's
  logged-in sessions.** That directory is a credential store; treat it as one,
  and treat screenshots of authenticated pages as evidence.
- **Evidence goes to `$WORK`.** Screenshots, JSONL, CSV and the SQLite database
  are engagement material.
- **Egress is the tunnel.** `--chrome-proxy` is for local interception, not
  containment, and `127.0.0.1:8080` in this container is the VPN gateway's
  control API — never point a proxy flag there.

## Command reference

### Subcommands

| Command | Purpose |
|---|---|
| `gowitness scan single -u URL` | One URL |
| `gowitness scan file -f FILE` | Newline-separated targets; `-` reads stdin |
| `gowitness scan cidr -c CIDR` | CIDR ranges expanded into HTTP/HTTPS candidates |
| `gowitness scan nmap -f XML` | Targets parsed out of an `nmap -oX` file |
| `gowitness scan nessus -f FILE` | Targets parsed out of a Nessus export |
| `gowitness report generate` | Static HTML report as a ZIP archive |
| `gowitness report list` | Summary table from a database or JSONL file |
| `gowitness report convert` | Convert between `.sqlite3` and `.jsonl` |
| `gowitness report merge` | Merge several SQLite databases into one |
| `gowitness report migrate` | Migrate a gowitness v2 database to v3 |
| `gowitness report server` | Serve the web UI from a data source |

### Scan flags

These are persistent on `gowitness scan`, so every subcommand accepts them.

| Flag | Default | Meaning |
|---|---|---|
| `-t, --threads <n>` | 6 | Concurrent browser threads |
| `-T, --timeout <s>` | 60 | Seconds before a page is considered timed out |
| `--delay <s>` | 3 | Seconds between navigation and screenshotting |
| `--driver gorod\|chromedp` | chromedp | Which browser driver to use |
| `--uri-filter <scheme>` | `http,https` | URI schemes passed to the scanner; repeatable |
| `--http-code-filter <code>` | all | Only screenshot these HTTP status codes; repeatable |
| `-s, --screenshot-path <dir>` | `./screenshots` | Where screenshots are written |
| `--screenshot-format jpeg\|png` | jpeg | Image format |
| `--screenshot-jpeg-quality <n>` | 60 | JPEG quality, 1–100 |
| `--screenshot-fullpage` | off | Capture the full page, not just the viewport |
| `--screenshot-skip-save` | off | Do not save to the screenshot path (useful with `--write-screenshots`) |
| `--write-screenshots` | off | Store screenshots with the writers as well as on disk |
| `--save-content` | off | Save content from network requests to the writers. **Upstream warns this can explode in size** |
| `--skip-html` | off | Leave the first response's HTML out of the results |
| `--skip-network-logs` | off | Leave per-request network logs out (also disables `--save-content`) |
| `--javascript <fn>` | | JavaScript **function** to evaluate on every page before the screenshot, e.g. `() => console.log('gowitness')` |
| `--javascript-file <file>` | | Same, from a file |
| `--log-scan-errors` | off | Log timeouts, DNS failures and the like to stderr (verbose) |
| `--chrome-path <path>` | | A Chrome binary to use; **downloads a platform-appropriate one by default** |
| `--chrome-wss-url <url>` | | Websocket URL of an already-running Chrome DevTools instance |
| `--chrome-proxy <proto://host:port>` | | HTTP/SOCKS5 proxy for the browser |
| `--chrome-user-agent <ua>` | upstream Chrome/128 desktop UA | User-Agent string |
| `--chrome-user-data-dir <dir>` | temporary | Chrome profile directory; left in place after the scan |
| `--chrome-window-x <px>`, `--chrome-window-y <px>` | 1280, 720 | Viewport size |
| `--chrome-header <header>` | | Extra request header; repeatable |

### Writers

| Flag | Default | Meaning |
|---|---|---|
| `--write-jsonl` | off | JSON Lines output |
| `--write-jsonl-file <file>` | `gowitness.jsonl` | Where the JSONL goes |
| `--write-csv` | off | CSV output (limited columns) |
| `--write-csv-file <file>` | `gowitness.csv` | Where the CSV goes |
| `--write-db` | off | Write to a SQLite database |
| `--write-db-uri <uri>` | `sqlite://gowitness.sqlite3` | Database URI; SQLite, MySQL and PostgreSQL are supported |
| `--write-db-enable-debug` | off | Verbose database query logging |
| `--write-stdout` | off | Print successful results to stdout |
| `--write-none` | off | Empty writer, to silence the "no writers configured" warning |

### Input flags per subcommand

| Subcommand | Input flag | Notes |
|---|---|---|
| `single` | `-u, --url <url>` | Errors out if no URL is given |
| `file` | `-f, --file <file>` | `-` reads stdin; also `--no-http`, `--no-https`, `-p/--port` (default 80,443), `--ports-small\|medium\|large` |
| `cidr` | `-c, --cidr <cidr>` | Repeatable; `-f` here is `--cidr-file`, **not** `--file`; `-p/--port` defaults to 80,443; `--random` shuffles the target order |
| `nmap` | `-f, --file <xml>` | `-o/--open-only`, `--port`, `--exclude-port`, `--skip-port`, `--service`, `--service-contains`, `--hostnames` |
| `nessus` | `-f, --file <file>` | `--hostnames`, `--port`, `--service-name`, `--plugin-name`, `--plugin-output` |

`gowitness scan nmap` will try every port in the XML by default, including SSH
and other non-HTTP services. Filter with `--service-contains http` or `--port`.

### Report flags

| Subcommand | Flags |
|---|---|
| `generate` | `--screenshot-path` (default `./screenshots`), `--db-uri` (default `sqlite://gowitness.sqlite3`), `--json-file` (takes precedence over `--db-uri`), `--zip-name` (default `gowitness-report.zip`) |
| `list` | `--db-uri`, `--json-file` (takes precedence) |
| `convert` | `--from-file`, `--to-file`; the extensions (`.sqlite3`, `.jsonl`) choose the direction |
| `merge` | `--source-file` (repeatable), `--source-path`, `--output-file` |
| `migrate` | `-s, --source <file>`; writes `<source>.v3-migrated.sqlite3` next to it |
| `server` | `--host` (default `127.0.0.1`), `--port` (default 7171), `--db-uri`, `--screenshot-path` |

### Global flags

| Flag | Meaning |
|---|---|
| `-D, --debug-log` | Debug logging; also enables `--log-scan-errors` |
| `-q, --quiet` | Silence almost all logging |
| `--no-log-color` | Plain log output |
| `--profile` | CPU, memory and trace profiling into `profiles/<timestamp>/` |

## Typical workflows

The complete versions of these are in [`EXAMPLES.md`](EXAMPLES.md).

1. **Live hosts from httpx, screenshots plus JSONL.**

   ```bash
   httpx -l "$WORK/hosts.txt" -silent -mc 200,301,403 -o "$WORK/live.txt"
   gowitness scan file -f "$WORK/live.txt" -t 4 -T 20 --delay 3 \
     -s "$WORK/shots" --write-jsonl --write-jsonl-file "$WORK/gowitness.jsonl"
   ```

2. **An nmap scan, filtered to HTTP services.**

   ```bash
   nmap -sV -oX "$WORK/nmap.xml" -iL "$WORK/hosts.txt"
   gowitness scan nmap -f "$WORK/nmap.xml" --open-only --service-contains http \
     -t 4 --write-jsonl --write-jsonl-file "$WORK/gowitness-nmap.jsonl"
   ```

3. **One URL, evidence for a report.**

   ```bash
   gowitness scan single -u "https://$TARGET/admin" --screenshot-fullpage \
     -s "$WORK/evidence" --write-jsonl --write-jsonl-file "$WORK/admin.jsonl"
   ```

4. **An HTML report for the engagement folder.**

   ```bash
   gowitness scan file -f "$WORK/live.txt" --write-db \
     --write-db-uri "sqlite://$WORK/gowitness.sqlite3" -s "$WORK/shots" -t 4
   gowitness report generate --db-uri "sqlite://$WORK/gowitness.sqlite3" \
     --screenshot-path "$WORK/shots" --zip-name "$WORK/gowitness-report.zip"
   ```

5. **A rate-limited target: fewer threads, longer timeout, more delay.**

   ```bash
   gowitness scan file -f "$WORK/live.txt" -t 1 -T 45 --delay 10 \
     --screenshot-skip-save --write-jsonl --write-jsonl-file "$WORK/slow.jsonl"
   ```

6. **Reusing an authenticated profile** — powerful and dangerous, see *Safety*:

   ```bash
   cp -a "$WORK/profile" "$WORK/profile-run"      # never the only copy
   gowitness scan file -f "$WORK/app-urls.txt" \
     --chrome-user-data-dir "$WORK/profile-run" \
     -s "$WORK/auth-shots" --write-jsonl --write-jsonl-file "$WORK/auth.jsonl"
   ```

## Output and parsing

Screenshots land in `-s/--screenshot-path` as JPEG or PNG. Metadata goes to
whichever writers you enabled; **with no writer, there is no metadata at all.**

`--write-jsonl` writes one JSON object per result. Verified fields in 3.2.0:

| Field | Meaning |
|---|---|
| `.url`, `.final_url` | Requested URL and the URL after redirects |
| `.probed_at` | Timestamp |
| `.response_code`, `.response_reason`, `.protocol` | HTTP status and reason |
| `.content_length` | Bytes of the response |
| `.title` | Page title |
| `.html` | First response body. Suppressed by `--skip-html` |
| `.failed`, `.failed_reason` | Whether the render failed, and why |
| `.screenshot`, `.file_name`, `.is_pdf` | The model's screenshot field; `.file_name` is the image written on disk |
| `.tls` | `protocol`, `cipher`, `subject_name`, `issuer`, `valid_from`, `valid_to`, `san_list`, … |
| `.technologies[]` | Detected technologies (`.value`) |
| `.headers[]`, `.cookies[]` | Response headers and cookies set by the page |
| `.network[]` | Per-request logs: `url`, `status_code`, `remote_ip`, `mime_type`, `content`, `error`. Suppressed by `--skip-network-logs` |
| `.console[]` | Browser console entries: `type`, `value` |
| `.perception_hash`, `.perception_hash_group_id` | Visual hash, for grouping identical pages |

```bash
# status, URL and title, one line each
jq -r '[.response_code, .url, .title] | @tsv' "$WORK/gowitness.jsonl"
# what failed to render, and why
jq -r 'select(.failed) | [.url, .failed_reason] | @tsv' "$WORK/gowitness.jsonl"
# which hosts set cookies on an unauthenticated visit
jq -r 'select((.cookies | length) > 0) | .url' "$WORK/gowitness.jsonl" | sort -u
# TLS issuers and expiry, for a certificate finding
jq -r 'select(.tls.subject_name != "") | [.url, .tls.issuer, .tls.valid_to] | @tsv' \
  "$WORK/gowitness.jsonl"
# the screenshots that go with a finding
jq -r 'select(.response_code == 200) | .file_name' "$WORK/gowitness.jsonl"
```

`--write-csv` has limited columns; read `gowitness report list` output or the
JSONL when you need detail. `--write-db` writes everything into SQLite at the
`--write-db-uri`, which is what `report generate`, `report list` and
`report server` read.

**The JSONL writer appends.** A second run against the same file adds to it, so
counts and selects silently mix runs — delete or rename the file between runs,
exactly as with whatweb's logs.

`gowitness report generate` writes a **ZIP archive** containing `index.html`, its
CSS and a `screenshots/` directory — not a bare HTML file. Hand the ZIP to the
report; unzip it for a quick look.

## Chaining with the rest of the toolchain

```bash
# discovery -> live check -> screenshots
httpx -l "$WORK/hosts.txt" -silent -mc 200,301,403 -o "$WORK/live.txt"
gowitness scan file -f "$WORK/live.txt" -t 4 --delay 3 \
  -s "$WORK/shots" --write-jsonl --write-jsonl-file "$WORK/gowitness.jsonl"

# port scan -> gowitness' own nmap reader
naabu -l "$WORK/hosts.txt" -top-ports 100 -o "$WORK/ports.txt"
nmap -sV -oX "$WORK/nmap.xml" -iL "$WORK/hosts.txt"
gowitness scan nmap -f "$WORK/nmap.xml" --open-only --service-contains http \
  -t 4 --write-jsonl --write-jsonl-file "$WORK/gowitness-nmap.jsonl"

# crawler output -> screenshots of exactly those URLs
jq -r '.request.endpoint' "$WORK/katana.jsonl" | sort -u > "$WORK/katana-urls.txt"
gowitness scan file -f "$WORK/katana-urls.txt" -t 2 --delay 5 \
  -s "$WORK/shots" --write-jsonl --write-jsonl-file "$WORK/katana-shots.jsonl"

# scanner hits -> visual evidence for the report
jq -r 'select(.info.severity=="high") | .host' "$WORK/nuclei.jsonl" | sort -u \
  > "$WORK/hits.txt"
gowitness scan file -f "$WORK/hits.txt" -s "$WORK/evidence" --write-db \
  --write-db-uri "sqlite://$WORK/hits.sqlite3"
```

gowitness sits after discovery and before the report: `httpx` decides what is
live, `nuclei` decides what matters, gowitness shows what it looks like. It is
the wrong tool for a single `HEAD`-style liveness check — that is `httpx`.

## Limits, failure modes and gotchas

- **By default nothing is queryable.** Upstream's warning is literal: with no
  `--write-*` flag you get screenshots and no record of what they are. The
  scanner also prints `no writers have been configured. to persist probe
  results, add writers using --write-* flags` — do not silence that with
  `--write-none` unless you really want nothing.
- **Upstream's own example text says `--write-json`.** The registered flag in
  3.2.0 is `--write-jsonl`; `--write-json` is not a flag.
- **The first run downloads Chrome.** It needs the tunnel up, and the download
  is not part of the image. Point `--chrome-path` at a chrome binary you have
  verified, or `--chrome-wss-url` at an already-running DevTools instance, to
  skip it. Playwright's `chromium-headless-shell` from the sibling `browser`
  tool is not a `chrome` path and will not do.
- **A failed render is not a missing page.** Check `.failed`/`.failed_reason`
  in the JSONL, or add `--log-scan-errors`, before reporting a host as dead.
  `-D/--debug-log` also enables scan-error logging.
- **The default delay dominates the runtime.** `--delay 3` per URL plus up to
  `-T 60` of timeout is the floor for a large list: a 500-host scan is at least
  25 minutes even when every page loads instantly.
- **`--http-code-filter` filters screenshots, not just records** — it is the
  list of response codes to screenshot. Setting it to `200` means a 403 admin
  panel is never captured.
- **`--save-content` can fill the disk.** Its help text warns about exactly
  that; `--skip-network-logs` turns it off again.
- **`--javascript` must be a function, not a statement.** `--javascript
  "console.log('x')"` is not what the flag takes; the value has to be a function
  such as `() => console.log('x')`. Treat any JavaScript you inject as executing
  in a page you do not control.
- **`-f` is not one flag across subcommands.** It is `--file` for `file`, `nmap`
  and `nessus`, but `--cidr-file` for `cidr`; `-c` is `--cidr` there, while
  `-c` does not exist on the other subcommands. `-t` is threads everywhere.
- **`scan nmap` tries every port in the XML** unless you filter with
  `--service-contains http` or `--port`. Screenshotting SSH services wastes the
  run and adds noise to the target's logs.
- **`scan cidr` is an internal-network tool.** It expands ranges into HTTP/HTTPS
  candidates and renders each one; against anything but confirmed address space
  it is a scan of somebody else's network.
- **`report generate` needs a data source**, and `--json-file` silently takes
  precedence over `--db-uri` when both are given. Its output is a ZIP.
- **`report convert` infers direction from extensions**: `.sqlite3` and `.jsonl`
  only, source and destination must differ, anything else errors out.
- **`report server` binds `127.0.0.1:7171` by default.** Upstream's own example
  uses `--port 8080` — in this container 8080 is the VPN gateway's control API,
  so do not bind anything there, and treat a non-loopback `--host` as a scope
  change.
- **`--chrome-proxy` defaults to empty**, so the browser does not inherit a
  proxy; if you set it, do not point it at `127.0.0.1:8080`.
- **The JSONL and CSV writers append.** Rename or delete the previous run's file
  first if you want per-run counts.
- **No bundled browser means no offline capability.** With the tunnel down, a
  first run fails at browser acquisition rather than at the target.

## Safety and scope

Stop and get explicit human confirmation before:

- scanning any host not already authorized for this engagement;
- `scan cidr` against address space that is not explicitly in scope;
- `--chrome-user-data-dir` pointed at a real profile — it reuses that profile's
  logged-in sessions, and the directory is a credential store;
- `--save-content` on a large site, which writes response bodies (potentially
  passwords, tokens and personal data) to disk;
- `--javascript`/`--javascript-file`, which execute code of your choosing in
  every page;
- raising `-t` or lowering `--delay` on a target that is not yours;
- `report server` bound to anything other than loopback.

Chromium in this container cannot use its namespace sandbox (a recorded platform
decision), so a target's hostile JavaScript is not sandboxed away from the
agent — treat every rendered page as untrusted input. Screenshots, saved content
and the SQLite database are engagement evidence and may contain credentials;
keep them in `$WORK`, out of the repository.
