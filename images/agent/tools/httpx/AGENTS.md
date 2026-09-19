# httpx

ProjectDiscovery's HTTP toolkit: takes a list of hosts, ports or URLs and
answers "what is actually listening, what does it claim to be, and what does it
return?" It is the probing layer that turns a port list into a target list —
status codes, titles, tech stack, server banners, TLS details, favicons, CDN
and ASN, in JSONL. Nothing else in the toolchain does that breadth in one pass.

This is **not** the Python `httpx` library; that package is not installed in this
image, so bare `httpx` always runs ProjectDiscovery's binary.

## Installation and location

| | |
|---|---|
| Version | `1.12.0` (upstream release, sha256-verified at image build) |
| Binary | `/usr/local/bin/httpx` |
| Config | `/root/.config/httpx/config.yaml` (created on first run if absent) |
| Data dir | `/root/.config/httpx/` — resume files, output |

httpx caches nothing between runs except the resume file and the filtered
error-page path (`filtered_error_page.json`, written to the working directory).
It streams input and does not need a target file on disk.

There is no Python venv and no Python `httpx` package in this image: `python3 -c
'import httpx'` raises `ModuleNotFoundError`, and `/opt/venvs/httpx` does not
exist. httpx is the pinned upstream release binary at `/usr/local/bin/httpx`, so
nothing shadows it — verify before trusting a pipeline:

```bash
command -v httpx        # expect /usr/local/bin/httpx
httpx -version -duc     # expect "[INF] Current Version: v1.12.0"
```

```bash
httpx -ldv -duc       # the internal output-field vocabulary
```

`-ldv` prints the field names that `-eof` accepts, which is **not** the same
list as the JSON keys — see *Output and parsing* for both.

## Rules that apply to this tool

- **Authorization first.** Probe only targets Greg has explicitly confirmed for
  the current engagement. If a target's authorization is unclear, it is
  unauthorized.
- **Egress is the tunnel.** All traffic leaves through the WireGuard interface
  in the shared network namespace. `-proxy` is not what protects the home IP.
- **Keep threads and rate conservative.** Defaults are `-t 50 -rl 150`. Start
  at `-t 10 -rl 25` on anything that is not Greg's, and remember httpx is
  usually the first tool to touch a host — the traffic it generates is the
  target's first impression of the engagement.
- **Bound the surface with `-ports`/`-path`.** Probing a host on every port is
  a port scan; that belongs to naabu, where the intent is explicit.
- **A single request per host is the polite default.** Use `-path` sparingly
  and `-fr` only when redirects matter.
- **Evidence goes to disk.** `-json -o $WORK/httpx.jsonl` so the target list is
  reproducible.
- **Pass `-duc`.** No update checks against ProjectDiscovery during an
  engagement.

## Command reference

Every flag below is from `httpx -h` on 1.12.0.

### Input

| Flag | Meaning |
|---|---|
| `-u, -target string[]` | Target host(s). Repeatable or comma-separated. |
| `-l, -list <file>` | File of hosts, one per line. |
| `-rr, -request <file>` | Raw HTTP request file to use as the probe. |
| `-im, -input-mode <mode>` | Input file mode. Currently `burp`. |
| stdin | Piped lines are treated as targets. This is the normal mode in a pipeline. |
| `-no-stdin` | Disable stdin processing. |
| `-p, -ports <spec>` | Ports to probe, nmap syntax: `http:1,2-10,11,https:80`, `80,443,8080`. |
| `-path <p>` | Path or comma-separated list of paths to request (file allowed). |
| `-vhost-input` | Treat input as a list of vhosts. |

Input lines may be bare hosts (`example.com`), host:port, or full URLs. httpx
tries HTTPS first and falls back to HTTP unless `-nf`/`-nfs` change that.

### Probes

| Flag | Meaning |
|---|---|
| `-sc, -status-code` | Status code. |
| `-cl, -content-length` | Content length. |
| `-ct, -content-type` | Content type. |
| `-location` | Redirect target. |
| `-title` | Page title. |
| `-server, -web-server` | Server header. |
| `-td, -tech-detect` | Technology detection (wappalyzer dataset). |
| `-cpe` | CPE with product version. |
| `-wp, -wordpress` | WordPress plugins and themes. |
| `-favicon` | mmh3 hash of `/favicon.ico`. |
| `-hash <alg>` | Body hash: `md5`, `mmh3`, `simhash`, `sha1`, `sha256`, `sha512`. |
| `-jarm` | JARM TLS fingerprint. |
| `-rt, -response-time` | Response time. |
| `-lc, -line-count` / `-wc, -word-count` | Body line/word count. |
| `-bp, -body-preview` | First N characters of the body (default 100). |
| `-ip` | Host IP. |
| `-cname` | Host CNAME. |
| `-asn` | ASN information. |
| `-cdn` | CDN/WAF in use. **Default true.** |
| `-ws, -websocket` | Server supports websockets. |
| `-method` | HTTP request method. |
| `-probe` | Probe status. |
| `-tls-grab` | Grab TLS/SSL data into the `.tls` object. |
| `-tls-probe` | Probe TLS domains extracted from the certificate. |
| `-csp-probe` | Probe CSP domains. |
| `-pipeline` / `-http2` / `-vhost` | Probe for HTTP/1.1 pipelining, HTTP/2, vhost support. |
| `-extract-fqdn, -efqdn` | Extract domains/subdomains from body and headers into JSONL output. |
| `-kb, -knowledge-base` | Knowledge-base classification. |

### Matchers and filters

| Flag | Meaning |
|---|---|
| `-mc, -match-code <codes>` | Keep only these status codes (`-mc 200,302`). |
| `-ml, -match-length <n>` / `-mlc` / `-mwc` | Match by content length / line count / word count. |
| `-ms, -match-string <s>` | Match a string in the response. |
| `-mr, -match-regex <re>` | Match a regex. |
| `-mfc, -match-favicon <hash>` | Match a favicon hash. |
| `-mcdn, -match-cdn <name>` | Match a CDN provider. |
| `-mrt, -match-response-time <expr>` | e.g. `-mrt '< 1'`. |
| `-mdc, -match-condition <expr>` | DSL condition. |
| `-fc, -filter-code <codes>` | Drop these status codes. |
| `-fl, -filter-length <n>` / `-flc` / `-fwc` | Drop by content length / line count / word count. |
| `-fs, -filter-string <s>` | Drop responses containing a string. |
| `-fe, -filter-regex <re>` | Drop responses matching a regex. |
| `-ffc, -filter-favicon <hash>` | Drop by favicon hash. |
| `-fcdn, -filter-cdn <name>` | Drop a CDN provider. |
| `-frt, -filter-response-time <expr>` | e.g. `-frt '> 1'`. |
| `-fdc, -filter-condition <expr>` | DSL condition. |
| `-fd, -filter-duplicates` | Drop near-duplicate responses, keeping the first. |
| `-fpt, -filter-page-type <t>` | `login`, `captcha`, `parked`. |
| `-fep, -filter-error-page` | DEPRECATED in `-h`: use `-fpt`. |
| `-strip` | Strip HTML/XML tags from the stored response. |
| `-lof, -list-output-fields` | Prints the list of available output field names. **It does not filter output** — see *Output and parsing*. |
| `-eof, -exclude-output-fields` | Drop these JSON fields. Takes the internal names that `-lof` prints. |
| `-e, -exclude <filter>` | Exclude hosts matching `cdn`, `private-ips`, CIDR, IP or regex. |

### Extractors

| Flag | Meaning |
|---|---|
| `-er, -extract-regex <re>` | Print content matching a regex. |
| `-ep, -extract-preset <preset>` | `url`, `ipv4`, `mail`. |

### Rate, timeout, retries

| Flag | Default | Meaning |
|---|---|---|
| `-t, -threads <n>` | 50 | Worker threads. |
| `-rl, -rate-limit <n>` | 150 | Max requests per second. |
| `-rlm, -rate-limit-minute <n>` | | Max requests per minute. |
| `-timeout <s>` | 10 | Per-request timeout, seconds. |
| `-retries <n>` | 0 | Retries. |
| `-delay <d>` | -1ns | Delay between requests (`200ms`, `1s`). |
| `-maxhr, -max-host-error <n>` | 30 | Errors per host before skipping the rest of its paths. |
| `-rsts, -response-size-to-save <n>` | 50000000 | Max response bytes saved. |
| `-rstr, -response-size-to-read <n>` | 50000000 | Max response bytes read. |

### Output

| Flag | Meaning |
|---|---|
| `-json, -j` | JSONL to stdout. The pipeline format. |
| `-o, -output <file>` | Write results to a file. |
| `-oa, -output-all` | Write results in every format; requires `-o` (omitting it fails with `[FTL] Please specify an output file`) |
| `-silent` | Results only; no banner or progress. |
| `-nc, -no-color` | No ANSI colour. |
| `-csv` | CSV output. |
| `-md, -markdown` | Markdown table output. |
| `-ob, -omit-body` | Leave the response body out of output. |
| `-irh, -include-response-header` | Include response headers in JSON (`-json` only). |
| `-irr, -include-response` | Include full request/response in JSON. |
| `-irrb, -include-response-base64` | Base64-encoded request/response in JSON. |
| `-include-chain` | Include the redirect chain in JSON. |
| `-sr, -store-response` | Store each HTTP response to disk. |
| `-srd, -store-response-dir <dir>` | Where to store them. |
| `-store-chain` | Include the redirect chain when storing responses. |
| `-stats`, `-si <s>` | Progress statistics and interval. |

### Request shaping and config

| Flag | Meaning |
|---|---|
| `-H, -header <hdr>` | Extra header, `header:value`. Repeatable or from a file. |
| `-body <body>` | POST body. |
| `-x <methods>` | Methods to probe; `all` for every method. |
| `-fr, -follow-redirects` | Follow redirects. |
| `-fhr, -follow-host-redirects` | Follow redirects on the same host only. |
| `-maxr, -max-redirects <n>` | Redirect limit (default 10). |
| `-rhsts, -respect-hsts` | Respect HSTS on redirect requests. |
| `-random-agent` | Random User-Agent. **Default true**, and it overrides a `-H 'User-Agent: …'` you set (see *Limits*). |
| `-auto-referer` | Set Referer to the current URL. |
| `-sni, -sni-name <name>` | Custom TLS SNI name. |
| `-r, -resolvers <list>` | Custom resolvers (file or comma-separated). |
| `-allow <list>` / `-deny <list>` | IP/CIDR allow and deny lists (file or comma-separated). |
| `-nf, -no-fallback` | Probe both HTTPS and HTTP instead of falling back. |
| `-nfs, -no-fallback-scheme` | Probe only the scheme given in the input. |
| `-ldp, -leave-default-ports` | Keep `:80`/`:443` in the Host header. |
| `-unsafe` | Send raw requests, skipping Go normalization. |
| `-no-decode` | Do not decode the body. |
| `-s, -stream` | Stream mode: elaborate input without sorting. |
| `-sd, -skip-dedupe` | Disable input deduplication (stream mode only). |
| `-resume` | Resume from `resume.cfg`. |
| `-proxy, -http-proxy <url>` | HTTP/SOCKS proxy. Not needed here. |
| `-config <file>` | Config file (default `$HOME/.config/httpx/config.yaml`). |
| `-duc, -disable-update-check` | Skip the update check. Use always. |
| `-up, -update` | Update the binary. Do not use inside this image. |

### Headless (screenshots)

| Flag | Meaning |
|---|---|
| `-ss, -screenshot` | Screenshot the page with a headless browser. |
| `-system-chrome` | Use a locally installed Chrome. |
| `-ho, -headless-options <opt>` | Extra Chrome options. |
| `-st, -screenshot-timeout <s>` | Screenshot timeout (default 10s). |
| `-sid, -screenshot-idle <s>` | Idle time before the screenshot (default 1s). |
| `-esb, -exclude-screenshot-bytes` | Keep screenshot bytes out of JSON. |
| `-ehb, -exclude-headless-body` | Keep the headless body out of JSON. |
| `-no-screenshot-full-page` | Screenshot the viewport, not the full page. |
| `-jsc, -javascript-code <js>` | Run JavaScript after navigation. |

## Typical workflows

1. **Is this host alive over HTTP, and what is it?**

   ```bash
   echo "$TARGET" | httpx -silent -sc -title -td -server -duc
   ```

2. **Build a live-URL list from a port scan, with JSON for later stages.**

   ```bash
   naabu -host "$TARGET" -top-ports 1000 -silent -duc \
     | httpx -silent -json -sc -title -td -duc -o "$WORK/live.jsonl"
   jq -r '.url' "$WORK/live.jsonl" > "$WORK/live-urls.txt"
   ```

3. **Only pages that need attention.** Drop the boring codes early so later
   tools see less:

   ```bash
   httpx -l "$WORK/hosts.txt" -silent -json -fc 404,400,502,503 \
     -mc 200,301,302,401,403 -duc -o "$WORK/interesting.jsonl"
   ```

4. **TLS and certificate detail on a suspect endpoint.**

   ```bash
   echo "https://$TARGET" | httpx -silent -json -tls-grab -jarm -favicon -duc \
     -o "$WORK/tls.jsonl"
   ```

5. **Technology-scoped triage across many hosts.** Find everything running a
   specific stack:

   ```bash
   httpx -l "$WORK/hosts.txt" -silent -json -td -duc \
     | jq -r 'select(.tech[]? | test("nginx|rails|go"; "i")) | .url' \
     | sort -u > "$WORK/nginx-rails.txt"
   ```

6. **Confirm vhosts before calling a name dead.**

   ```bash
   httpx -l "$WORK/subdomains.txt" -silent -sc -title -cl -fc 404 -duc
   ```

## Output and parsing

`-json` emits one object per responsive target. A verified default line, with
`-silent -json` and no extra probe flags, against a local HTTP server:

```json
{"timestamp":"...","port":"8099","url":"http://127.0.0.1:8099","input":"http://127.0.0.1:8099",
 "title":"Pen Fixture Home","scheme":"http","webserver":"SimpleHTTP/0.6 Python/3.11.2",
 "content_type":"text/html","method":"GET","host":"127.0.0.1","host_ip":"127.0.0.1","path":"/",
 "time":"2.6ms","a":["127.0.0.1"],"tech":["Python:3.11.2","SimpleHTTP:0.6"],"words":6,"lines":6,
 "status_code":200,"content_length":185,"failed":false,"knowledgebase":{"pHash":0}}
```

The default key set is:

```
timestamp  port  url  input  title  scheme  webserver  content_type  method  host
host_ip  path  time  a  tech  words  lines  status_code  content_length  failed
knowledgebase
```

Probe flags add keys rather than replacing them. `-irh` adds `header`;
`-tls-grab` adds `tls` (TLS targets only); `-cname` adds `cname`; `-favicon`
adds `favicon`; `-jarm` adds `jarm_hash`; `-asn` adds `asn`; `-sr` adds
`stored_response_path`; `-ip` populates `host_ip`; `-extract-fqdn` adds
`body_domains`/`body_fqdn`; `-cpe` adds `cpe`.

The fields that matter day to day:

| Field | Meaning |
|---|---|
| `.url` | Final URL probed (after scheme fallback). |
| `.input` | The line as it arrived on stdin. Use this to join back to the input list. |
| `.status_code` | HTTP status. |
| `.title` | Page title. |
| `.tech` | Array of detected technologies. |
| `.webserver` | Server header. |
| `.content_length` | Body length. |
| `.content_type` | Content-Type. |
| `.host` / `.port` / `.scheme` / `.path` | Parsed components. |
| `.host_ip` | Resolved IP. |
| `.a` | Resolved A records (array). |
| `.cdn` / `.cdn_name` / `.cdn_type` | CDN detection; present only when a CDN match is found. |
| `.location` | Redirect target. |
| `.final_url` | URL after redirects (when following). |
| `.time` | Response time. |
| `.failed` / `.error` | Present/true when the probe failed (see *Limits*). |
| `.tls` | TLS detail object, with `-tls-grab` on a TLS target. |
| `.jarm_hash` | JARM fingerprint. |
| `.favicon` | mmh3 favicon hash. |
| `.asn` | ASN object, with `-asn`. |
| `.stored_response_path` | Path on disk when `-sr` was used. |

```bash
# one line per live host: status, title, url
jq -r '[.status_code, (.title // "-"), .url] | @tsv' "$WORK/live.jsonl"

# only successful pages that are not generic 404s
jq -r 'select(.status_code == 200 and (.title // "" | test("404|not found"; "i") | not)) | .url' \
  "$WORK/live.jsonl"

# technology inventory across a fleet
jq -r '.tech[]?' "$WORK/live.jsonl" | sort | uniq -c | sort -rn

# keep only the fields a later stage needs
jq -c '{url, status_code, tech}' "$WORK/live.jsonl"
```

**Field-name filtering does not work the way the help text implies.** In this
build `-lof <anything>` prints the *list of available output field names* and
produces no scan output — it behaves as a listing flag, not as a "keep only
these fields" filter. `-eof` does work, and consumes those same names:

```bash
httpx -ldv -duc                 # print the vocabulary
httpx -silent -json -eof knowledgebase -duc < hosts.txt
httpx -silent -json -eof technologies -duc < hosts.txt   # removes .tech
```

The names `-ldv`/`-lof`/`-eof` use are internal (`statuscode`, `contentlength`,
`technologies`, `responsetime`, …), **not** the JSON keys (`status_code`,
`content_length`, `tech`, `time`). Mixing them up silently does nothing. To
select fields rather than drop them, use `jq`:

```bash
httpx -silent -json -duc < hosts.txt | jq -c '{url, status_code, tech}'
```

## Chaining with the rest of the toolchain

httpx reads one host/URL per line on stdin and writes one JSON object per line
with `-json`. Input lines may be bare hosts, `host:port`, or full URLs.

```bash
# ports -> live web services -> findings
naabu -host "$TARGET" -top-ports 1000 -silent -duc \
  | httpx -silent -json -sc -title -td -duc -o "$WORK/live.jsonl"
jq -r '.url' "$WORK/live.jsonl" \
  | nuclei -severity medium,high,critical -ni -rl 25 -c 10 -silent -jsonl -duc

# subdomains -> resolved -> live -> crawl
subfinder -d "$DOMAIN" -silent -duc \
  | dnsx -silent -a -resp-only -duc \
  | httpx -silent -sc -title -td -duc \
  | tee "$WORK/live-hosts.txt" \
  | katana -silent -d 3 -duc
```

- `naabu` emits `host:port`; httpx understands that form directly, so no
  rewriting is needed.
- `dnsx -resp-only` emits bare IPs. httpx will probe them, but the Host header
  will be the IP — use `dnsx -a -resp` and keep the names when vhosts matter.
- `httpx -json` output feeds `nuclei` after `jq -r '.url'`, because nuclei
  wants URLs, not JSON objects.
- `httpx` is also the correctness check on `katana`: URLs katana found that
  httpx reports `404` are dead ends.

## Limits, failure modes and gotchas

- **Check which `httpx` you are running.** `command -v httpx` must print
  `/usr/local/bin/httpx` and `httpx -version` must print the version banner; a
  `Usage: httpx [OPTIONS] URL` reply means a different program answered. See
  *Installation and location*.
- **Scheme fallback is silent.** Given a bare host, httpx tries HTTPS then HTTP.
  A result with `.url` starting `http://` means HTTPS failed, which is itself a
  finding worth noting.
- **`-cdn` is on by default**, so `cdn_name` appears when a CDN match is found;
  it is not emitted for every target. It also means response fields reflect the
  CDN, not the origin.
- **`-mc` and `-fc` interact.** Passing both is legal; the filter wins after the
  matcher. Keep one direction explicit to avoid confusion.
- **`-t` is threads, not timeout.** `-timeout` is seconds. In nuclei, `-t` is
  templates; the letters collide across tools.
- **A dead host produces no JSON at all unless `-probe` is passed.** With
  `-probe` you get a row with `"failed":true`, `"status_code":0` and an
  `error` string:
  `{"url":"https://127.0.0.1:8098","input":"127.0.0.1:8098","error":"8098 chain=\"connection refused\"","words":0,"lines":0,"status_code":0,"content_length":0,"failed":true}`.
  Without it, silence. A pipeline that treats silence as "not HTTP" is right by
  accident; one that needs to distinguish "refused" from "filtered" needs
  `-probe` and the `error` field.
- **`-lof` does not filter fields.** It prints the available field names. Use
  `-eof` to drop fields or `jq` to select them.
- **`-random-agent` is on by default and wins over `-H`.** In the 1.12.0 build
  audited here `-H 'User-Agent: FIXED-UA'` still sent one random agent, and so
  did `-random-agent=false -H 'User-Agent: FIXED-UA'`. If a target behaves
  differently for a known user agent, confirm the header that actually arrived
  (a header-counting local server) before relying on it.
- **Headless screenshots need `-system-chrome`, and remain unverified here.**
  `-ss` without `-system-chrome` downloads a Chromium build via go-rod into
  `/root/.cache/rod/browser/`, which needs the tunnel up on first use and is
  repeated after every container recreate. With `-system-chrome`, httpx
  resolves the pinned browser at `/usr/local/bin/chromium` (installed by
  `tools/browser`) through the same `launcher.LookPath()` the other rod tools
  use, and no download happens:

  ```bash
  httpx -l "$WORK/live.txt" -ss -system-chrome -duc -json -o "$WORK/screens.json"
  ```

  With `-system-chrome` and no browser on `PATH` it fails loudly with
  `the chrome browser is not installed`. No screenshot has been taken through
  this path on a built image yet, so treat the screenshot flags (`-ss`, `-jsc`,
  `-esb`, `-ehb`) as **untested until someone runs one**, and do not read an
  empty result from them as "no page". The shared libraries Chromium needs are
  installed by `tools/browser/install.sh`; without them the browser fails to
  launch with `Failed to launch the browser ... chrome: error while loading
  shared libraries: libnss3.so: cannot open shared object file`.
- **`-tls-grab` on a plaintext HTTP port** returns no `.tls` object, not an
  error.
- **`-path` multiplies requests.** Every path is probed on every host; ten
  paths across a thousand hosts is ten thousand requests. `-maxhr` will start
  skipping hosts after 30 errors each.
- **`-rl` is global across all threads**, so it is the real speed control;
  raising `-t` alone usually does nothing but queue connections.
- **`-sr` writes a mirror of every response to disk** under
  `<dir>/response/<host>_<port>/<sha1>.txt`, plus `response/index.txt`. On a
  large sweep that is a lot of data, potentially including credentials.
- **`-no-stdin` exists** for the case where httpx is run inside a loop and
  would otherwise consume the loop's input.

## Safety and scope

Requires explicit human confirmation before running:

- Any target not already confirmed for this engagement.
- Probing ports or paths beyond the confirmed surface — a wide `-p` or a long
  `-path` list is a scan, not a probe.
- Any use of `-ss`/`-system-chrome` (headless browser) or `-jsc` (JavaScript
  execution).
- `-unsafe` (raw requests) or `-x all` (every HTTP method), both of which send
  traffic a normal client never would.
- Raising `-t`/`-rl` above the conservative defaults on a target that is not
  Greg's.
- Probing private or internal address space; check with `-e private-ips`.
