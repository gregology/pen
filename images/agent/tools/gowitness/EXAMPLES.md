# gowitness — worked examples

Every flag below is from the pinned 3.2.0 build; the flag reference lives in
[`AGENTS.md`](AGENTS.md). The workflows were **not executed while writing this
document** — the first real scan needs a browser, and gowitness downloads its
own Chrome (see *0. Before the first scan*). Read the outputs here as the shapes
the 3.2.0 data model produces, not as captured transcripts, and confirm the
browser question before trusting a first run.

```bash
export WORK=/working/engagements/example
export TARGET=target.example
mkdir -p "$WORK"
```

## 0. Before the first scan

gowitness needs a `chrome`-family binary. It downloads a platform-appropriate
one on first use, which needs the VPN tunnel up and is the only runtime browser
download left in the image. The Playwright `chromium-headless-shell` installed
by the sibling `browser` tool is not a `chrome` path and cannot be substituted
with `--chrome-path`.

Choose one of these before running anything:

```bash
# a) let it download its own Chrome (needs the tunnel up)
gowitness scan single -u http://127.0.0.1:8090/ --write-stdout

# b) point it at a chrome binary you have verified
gowitness scan single -u http://127.0.0.1:8090/ --chrome-path /path/to/chrome \
  --write-stdout

# c) point it at an already-running Chrome DevTools instance
gowitness scan single -u http://127.0.0.1:8090/ \
  --chrome-wss-url ws://127.0.0.1:9222/devtools/browser/<id> --write-stdout
```

A loopback fixture is enough for that first check, and it keeps the test
honest — nothing external is touched:

```bash
mkdir -p /tmp/site
printf '<html><head><title>Pen Fixture</title></head><body><h1>ok</h1></body></html>' \
  > /tmp/site/index.html
cd /tmp/site && python3 -m http.server 8090 --bind 127.0.0.1 &
sleep 2
curl -s -o /dev/null -w 'status=%{http_code}\n' http://127.0.0.1:8090/
```

Port 8090 is the loopback fixture convention in this image. Do not use 8080:
in the agent container that is the VPN gateway's control API.

## 1. Live hosts from httpx, screenshots plus JSONL

The ordinary shape of the job: a host list, a liveness filter, then a screenshot
pass with metadata, because screenshots alone are not queryable.

```bash
# 1. confirm what is live (httpx writes the filtered list)
httpx -l "$WORK/hosts.txt" -silent -mc 200,301,403,401 -o "$WORK/live.txt"
wc -l "$WORK/live.txt"

# 2. screenshot the live set, with a JSONL record of every result
gowitness scan file -f "$WORK/live.txt" \
  -t 4 -T 20 --delay 3 \
  -s "$WORK/shots" \
  --write-jsonl --write-jsonl-file "$WORK/gowitness.jsonl"

# 3. what did we get?
wc -l "$WORK/gowitness.jsonl"          # one line per probed URL
ls "$WORK/shots" | wc -l               # one image per success
jq -r '[.response_code, .url, .title] | @tsv' "$WORK/gowitness.jsonl" | head
```

Why each flag is there:

- `-f/--file` is the input list; `-` would read stdin instead.
- `-t 4` keeps four browser threads, not the default six; `-T 20` caps a page at
  20 s; `--delay 3` is the default but is written down because the delay is paid
  per probe and spread across threads — a 500-host list at `-t 4 --delay 3` is
  at least six minutes of waiting alone, and the same list at `-t 1` is at least
  twenty-five.
- `--write-jsonl` plus `--write-jsonl-file` is the record. Without a writer the
  run saves screenshots only and there is nothing to `jq`.

Check the failures separately — a render that failed looks exactly like a host
with nothing on it:

```bash
jq -r 'select(.failed) | [.url, .failed_reason] | @tsv' "$WORK/gowitness.jsonl"
```

The JSONL writer appends. If you re-run the scan, rename the file first or the
per-run counts mix two runs.

## 2. Scan an nmap XML

When the port scan already happened, let gowitness read it instead of rebuilding
a URL list. Filter to HTTP services: without a filter it tries every port in the
XML, SSH included.

```bash
nmap -sV -oX "$WORK/nmap.xml" -iL "$WORK/hosts.txt"

gowitness scan nmap -f "$WORK/nmap.xml" \
  --open-only --service-contains http \
  -t 4 -T 30 --delay 3 \
  -s "$WORK/nmap-shots" \
  --write-jsonl --write-jsonl-file "$WORK/gowitness-nmap.jsonl"

# which services produced images, and which failed
jq -r 'select(.failed == false) | [.response_code, .url] | @tsv' \
  "$WORK/gowitness-nmap.jsonl" | head
jq -r 'select(.failed) | [.url, .failed_reason] | @tsv' "$WORK/gowitness-nmap.jsonl"
```

- `-o/--open-only` skips ports nmap did not mark open.
- `--service-contains http` is the broad filter; `--service http --service
  https` is the literal one. `--port 80 --port 443` is the third option when the
  service names are wrong.
- `--hostnames` adds hostnames from the XML as extra URL candidates, which
  matters for virtual hosting.

A Nessus export works the same way: `gowitness scan nessus -f results.nessus`,
with `--service-name`, `--plugin-name` and `--plugin-output` narrowing the
plugin matches.

## 3. Single-URL evidence capture for a report

For one finding you want a full-page image and a record that ties it to the URL
and timestamp. This is the example to run against the loopback fixture first, so
the output shape is familiar before it matters.

```bash
# fixture check
gowitness scan single -u http://127.0.0.1:8090/ --screenshot-fullpage \
  -s "$WORK/evidence" --write-jsonl --write-jsonl-file "$WORK/fixture.jsonl"
jq -c '{url, response_code, title, file_name, failed}' "$WORK/fixture.jsonl"

# the real capture
gowitness scan single -u "https://$TARGET/admin" \
  --screenshot-fullpage --chrome-window-y 2000 \
  -s "$WORK/evidence" \
  --write-jsonl --write-jsonl-file "$WORK/admin.jsonl"

jq -r '[.probed_at, .response_code, .url, .title, .file_name] | @tsv' "$WORK/admin.jsonl"
```

Notes:

- `--screenshot-fullpage` captures the whole page, not the 1280x720 viewport.
- `--chrome-window-x/--chrome-window-y` change the viewport that the full-page
  capture starts from; they are the only size controls.
- `.file_name` is the image on disk under `-s`. `--skip-html` leaves the HTML
  out of the record if it should be smaller.
- An authenticated capture is evidence containing the session's view of the
  application — keep it in `$WORK` and treat it as sensitive.

## 4. An HTML report after a scan

`report generate` builds a static report from a database or a JSONL file. Write
the database during the scan so the report can be regenerated later without
re-scanning.

```bash
gowitness scan file -f "$WORK/live.txt" \
  -t 4 -T 20 --delay 3 \
  -s "$WORK/shots" \
  --write-db --write-db-uri "sqlite://$WORK/gowitness.sqlite3" \
  --write-jsonl --write-jsonl-file "$WORK/gowitness.jsonl"

# a quick summary before building the report
gowitness report list --db-uri "sqlite://$WORK/gowitness.sqlite3"

# the report: a ZIP containing index.html plus the screenshots
gowitness report generate \
  --db-uri "sqlite://$WORK/gowitness.sqlite3" \
  --screenshot-path "$WORK/shots" \
  --zip-name "$WORK/gowitness-report.zip"
unzip -l "$WORK/gowitness-report.zip" | head
```

- `--db-uri` uses the `sqlite://` URI form; the same database can be converted
  later with `gowitness report convert --from-file "$WORK/gowitness.sqlite3"
  --to-file "$WORK/gowitness-export.jsonl"`.
- `report generate` can read the JSONL instead with
  `--json-file "$WORK/gowitness.jsonl"`, and that flag takes precedence over
  `--db-uri` when both are present.
- The output is a ZIP, not an `index.html` on its own; unzip it to read the
  report, or hand the ZIP on as-is.
- `gowitness report server --db-uri "sqlite://$WORK/gowitness.sqlite3"` serves
  the same data interactively on `127.0.0.1:7171` (its default). Leave it on
  loopback — binding it wider, or moving it to 8080, is a scope change and 8080
  is the gateway control API.

## 5. A bounded scan on a rate-limited target

The three knobs are threads, timeout and delay. On a target that rate-limits or
sits behind a WAF, turn concurrency down and delay up, and accept the runtime.

```bash
gowitness scan file -f "$WORK/sensitive.txt" \
  -t 1 -T 45 --delay 10 \
  -s "$WORK/slow-shots" \
  --write-jsonl --write-jsonl-file "$WORK/gowitness-slow.jsonl" \
  --log-scan-errors 2> "$WORK/gowitness-slow.err"

# how much of it actually rendered?
jq -r 'select(.failed) | .failed_reason' "$WORK/gowitness-slow.jsonl" \
  | sort | uniq -c | sort -rn
tail -20 "$WORK/gowitness-slow.err"
```

- `-t 1` means one browser at a time; `--delay 10` waits ten seconds after load
  before the screenshot, so a three-URL run is already half a minute of
  deliberate waiting.
- `-T 45` bounds a page that never finishes loading rather than letting it hold
  a thread for the 60 s default.
- `--log-scan-errors` writes timeouts and DNS failures to stderr; `-q` would
  suppress the normal log noise instead.
- This is still a browser load per URL with all its subresources. Bounding it
  makes it slower, not quiet.

## 6. Reusing an authenticated profile

Pointing `--chrome-user-data-dir` at a real Chrome profile makes gowitness browse
as whoever is logged in there — the way to screenshot an application behind a
login without scripting the login flow. **The profile directory is a credential
store**: it contains session cookies and saved logins, gowitness leaves it in
place after the scan, and the screenshots it produces show authenticated pages.
Copy the profile and scan the copy, never the only profile.

```bash
# copy the profile; the original is left untouched
cp -a "$WORK/chrome-profile" "$WORK/chrome-profile-run"

gowitness scan file -f "$WORK/app-urls.txt" \
  --chrome-user-data-dir "$WORK/chrome-profile-run" \
  --chrome-header "X-Engagement: authorised" \
  -t 1 -T 30 --delay 3 \
  -s "$WORK/auth-shots" \
  --write-jsonl --write-jsonl-file "$WORK/gowitness-auth.jsonl"

# did the session hold, or did every page land on the login form?
jq -r '[.response_code, .final_url, .title] | @tsv' "$WORK/gowitness-auth.jsonl"
```

- Check `.final_url` and `.title`: a redirect to the login page is the silent
  failure mode of an expired session, and it looks like a successful scan.
- `.cookies[]` in the JSONL will contain session cookies from the visited
  pages. That file is credential material; do not paste it into a report.
- Confirm with a human before doing this at all: it acts as that user inside the
  application, and a mis-aimed URL can change state.
