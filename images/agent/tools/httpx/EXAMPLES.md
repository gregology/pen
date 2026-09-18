# httpx — worked examples

Every command below was run in the agent container as root, against a local
fixture server and the two authorized public hosts. Output shown is real,
trimmed where marked.

```bash
export WORK=/working/engagements/example
mkdir -p "$WORK"
```

**Check which binary you are running.** The venv on `PATH` used to ship the
Python `httpx` console script (now renamed `httpx-httpclient`), so a bare
`httpx` would run the wrong program:

```bash
$ httpx -version
Usage: httpx [OPTIONS] URL
Error: No such option '-e'.
```

Correct on the current image:

```bash
$ command -v httpx
/usr/local/bin/httpx
$ httpx -version -duc
[INF] Current Version: v1.12.0
```

If `command -v httpx` points into `/opt/venvs/httpx/bin`, substitute
`/usr/local/bin/httpx` for every `httpx` below.

## 1. Stand up a target you are allowed to hammer

Everything here can be exercised against a loopback server, which keeps the
verification honest and generates no external traffic:

```bash
mkdir -p /tmp/site/sub
printf '<html><head><title>Pen Fixture Home</title></head><body><a href="/page1.html">one</a></body></html>' > /tmp/site/index.html
printf '<html><head><title>Pen Fixture Page One</title></head><body>one</body></html>' > /tmp/site/page1.html
cd /tmp/site && python3 -m http.server 8099 --bind 127.0.0.1 &
sleep 2
curl -s -o /dev/null -w 'status=%{http_code}\n' http://127.0.0.1:8099/
```

## 2. Is this alive, and what is it?

```bash
echo "http://127.0.0.1:8099" | httpx -silent -sc -title -td -server -duc
```

Real output:

```
http://127.0.0.1:8099 [200] [Pen Fixture Home] [Python:3.11.2,SimpleHTTP:0.6]
```

The same host as JSON, with no extra probe flags beyond `-json`:

```json
{"timestamp":"...","port":"8099","url":"http://127.0.0.1:8099","input":"http://127.0.0.1:8099",
 "title":"Pen Fixture Home","scheme":"http","webserver":"SimpleHTTP/0.6 Python/3.11.2",
 "content_type":"text/html","method":"GET","host":"127.0.0.1","host_ip":"127.0.0.1","path":"/",
 "time":"2.6ms","a":["127.0.0.1"],"tech":["Python:3.11.2","SimpleHTTP:0.6"],"words":6,"lines":6,
 "status_code":200,"content_length":185,"failed":false,"knowledgebase":{"pHash":0}}
```

`-json` already includes status, title, tech, server, content type, length,
response time and resolved IP. The individual probe flags exist to change the
*plain* output, not to add these fields.

## 3. Ports to live URLs

```bash
naabu -host 127.0.0.1 -p 8099 -silent -duc \
  | httpx -silent -json -sc -title -td -duc -o "$WORK/live.jsonl"
jq -r '.url' "$WORK/live.jsonl" > "$WORK/live-urls.txt"
cat "$WORK/live-urls.txt"
```

`naabu -silent` emits `host:port`, which httpx accepts directly. No rewriting.

## 4. Filter at the source

Keep only responses worth a second look:

```bash
httpx -l "$WORK/hosts.txt" -silent -json \
  -mc 200,301,302,401,403 -fc 404,400,502,503 \
  -duc -o "$WORK/interesting.jsonl"
```

Match on response content rather than codes:

```bash
# pages whose titles look like a login screen
httpx -l "$WORK/hosts.txt" -silent -json -title -duc \
  | jq -r 'select(.title // "" | test("login|sign in|admin"; "i")) | .url'
```

## 5. Technology triage across a fleet

```bash
httpx -l "$WORK/hosts.txt" -silent -json -td -duc \
  | jq -r 'select(.tech[]? | test("nginx|rails|go"; "i")) | .url' \
  | sort -u > "$WORK/nginx-rails.txt"
```

Inventory instead of filter:

```bash
jq -r '.tech[]?' "$WORK/live.jsonl" | sort | uniq -c | sort -rn
```

## 6. TLS detail on one endpoint

```bash
echo "https://example.com" | httpx -silent -json \
  -tls-grab -jarm -favicon -duc -o "$WORK/tls.jsonl"
jq -r '.tls | keys_unsorted | join(",")' "$WORK/tls.jsonl"
```

On plaintext HTTP, `-tls-grab` adds no `.tls` key at all — it is not an error,
there is simply nothing to grab.

## 7. Dropping and selecting fields

`-lof` does **not** filter output. It prints the available field names:

```bash
httpx -ldv -duc | head -5
```

```
header_md5
header_mmh3
header_sha256
header_simhash
body_md5
```

Those names are internal (`statuscode`, `technologies`, `contentlength`), not
the JSON keys (`status_code`, `tech`, `content_length`). `-eof` consumes them
and does work:

```bash
# remove the knowledgebase block
httpx -silent -json -eof knowledgebase -duc < "$WORK/hosts.txt"

# remove the tech array (note: 'technologies', not 'tech')
httpx -silent -json -eof technologies -duc < "$WORK/hosts.txt"
```

To *keep* a subset, use `jq`:

```bash
httpx -silent -json -duc < "$WORK/hosts.txt" \
  | jq -c '{url, status_code, tech, webserver}'
```

## 8. Dead hosts are silent unless you ask

Without `-probe`, a connection-refused host produces **no JSON line at all**:

```bash
$ echo "127.0.0.1:8098" | httpx -silent -json -duc
$
```

With `-probe`, the failure is explicit:

```json
{"timestamp":"...","url":"https://127.0.0.1:8098","input":"127.0.0.1:8098",
 "error":"8098 chain=\"connection refused\"","words":0,"lines":0,
 "status_code":0,"content_length":0,"failed":true}
```

Use `-probe` whenever a pipeline needs to distinguish "not HTTP" from "refused"
from "filtered".

## 9. Keep the raw exchange as evidence

```bash
httpx -u https://example.com -silent -json -irr -duc \
  | jq -r '.request' | head -20
```

`-irr` adds the full request/response to the JSON; `-irh` adds only the response
headers. To mirror every response to disk instead:

```bash
httpx -l "$WORK/hosts.txt" -silent -json -sr -srd "$WORK/httpx-sr" -duc
find "$WORK/httpx-sr" -type f | head -5
```

Verified layout: `<dir>/response/<host>_<port>/<sha1>.txt`, plus
`<dir>/response/index.txt`.

## 10. Hand off to a scanner

```bash
httpx -l "$WORK/hosts.txt" -silent -json -sc -title -td -duc \
    -o "$WORK/live.jsonl"
jq -r '.url' "$WORK/live.jsonl" \
  | nuclei -severity medium,high,critical -ni -rl 25 -c 10 -silent -jsonl -duc \
      -o "$WORK/nuclei.jsonl"
```

## Known-broken in this image

Screenshots do not work. httpx downloads a Chromium build via go-rod and then
cannot launch it:

```
$ httpx -silent -json -ss -duc < "$WORK/hosts.txt"
[FTL] Could not create runner: [launcher] Failed to launch the browser ...
      /root/.cache/rod/browser/chromium-1321438/chrome: error while loading
      shared libraries: libnss3.so: cannot open shared object file
```

Do not use `-ss`, `-system-chrome`, `-jsc`, `-esb` or `-ehb` until the image
carries the browser's shared libraries.
