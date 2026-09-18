# katana

Web crawler built for automation pipelines. It walks a site from a seed URL,
follows links, parses endpoints out of JavaScript, and emits the discovered URL
surface — optionally executing the page in a headless browser so client-side
routing and XHR endpoints appear. It is the tool that turns one target into the
list of URLs that `nuclei`, `ffuf` and `dalfox` actually test.

## Installation and location

| | |
|---|---|
| Version | `1.7.0` (upstream release, sha256-verified at image build) |
| Binary | `/usr/local/bin/katana` |
| Config | `-config <file>`; no default config file is created |
| Chrome data | `-cdd <dir>` (`-chrome-data-dir`) when running headless |
| Output | stdout, or `-o <file>`; `-srd` for stored responses |

Katana is stateless between runs apart from the resume file and whatever
`-sr`/`-sfd` write to disk. Headless mode downloads its own Chromium — which
then fails to run in this image (see *Limits*). Non-headless crawling needs no
browser.

```bash
katana -version -duc     # "Current version: v1.7.0"
```

## Rules that apply to this tool

- **Authorization first.** Crawl only targets Greg has explicitly confirmed for
  the current engagement. If a target's authorization is unclear, it is
  unauthorized.
- **Egress is the tunnel.** All traffic leaves through the WireGuard interface
  in the shared network namespace. `-proxy` is not what protects the home IP.
- **A crawl is not a gentle operation.** Katana requests every link it finds,
  including destructive-looking ones, and with `-aff` it submits forms. Keep
  `-c`/`-p`/`-rl` low on anything that is not Greg's, and leave `-aff` off.
- **Keep the scope tight.** `-fs rdn` (default) confines the crawl to the
  registrable domain. Do not widen it with `-fs fqdn` or `-ns` without a
  reason, and never crawl out of scope by accident with `-do` output feeding
  another tool.
- **Depth and duration are the real limits.** `-d` and `-ct` bound the crawl;
  the rate flags only bound the speed. Set both.
- **Store responses deliberately.** `-sr` writes every response body to disk;
  on a large site that is a lot of data, potentially including credentials.
- **Evidence goes to disk.** `-jsonl -o $WORK/katana.jsonl`.
- **Pass `-duc`.** No update checks against ProjectDiscovery during an
  engagement.

## Command reference

Every flag below is from `katana -h` on 1.7.0.

### Input

| Flag | Meaning |
|---|---|
| `-u, -list string[]` | Target URL, or a list. Repeatable and comma-separated; a file path is accepted. |
| `-resume <file>` | Resume from a previous scan file. |
| `-e, -exclude <filter>` | Exclude hosts matching `cdn`, `private-ips`, CIDR, IP or regex. |
| stdin | Targets piped on stdin are crawled. Verified working, though `-h` does not document it. |

### Crawl behaviour

| Flag | Default | Meaning |
|---|---|---|
| `-d, -depth <n>` | 3 | Maximum crawl depth. |
| `-jc, -js-crawl` | off | Parse endpoints out of JavaScript files. |
| `-jsl, -jsluice` | off | Enable jsluice parsing of JavaScript (memory intensive). |
| `-ct, -crawl-duration <d>` | none | Stop after this long (`30s`, `5m`, `1h`). |
| `-kf, -known-files <set>` | off | Crawl `all`, `robotstxt`, `sitemapxml`. Needs depth ≥ 3 to be complete. |
| `-s, -strategy <name>` | depth-first | `depth-first` or `breadth-first`. |
| `-pc, -path-climb` | off | Auto-crawl parent paths. |
| `-iqp, -ignore-query-params` | off | Treat `?a=1` and `?a=2` on the same path as one URL. |
| `-fsu, -filter-similar` | off | Skip similar-looking URLs (`/users/123` vs `/users/456`). |
| `-fst, -filter-similar-threshold <n>` | 10 | Distinct values before a path position counts as a parameter. |
| `-mrs, -max-response-size <n>` | 4194304 | Maximum response size to read. |
| `-mdp, -max-domain-pages <n>` | unlimited | Pages per domain. |
| `-timeout <s>` | 10 | Per-request timeout. |
| `-time-stable <s>` | 1 | Wait until the page is stable (headless). |
| `-retry <n>` | 1 | Request retries. |
| `-dr, -disable-redirects` | off | Do not follow redirects. |
| `-td, -tech-detect` | off | Technology detection. |
| `-H, -headers <hdr>` | | Header/cookie in `header:value` form. Repeatable, or a file. |
| `-tlsi, -tls-impersonate` | off | Experimental JA3 client-hello randomisation. |
| `-proxy <url>` | | HTTP/SOCKS5 proxy. Not needed here. |
| `-config <file>` | | Configuration file. |
| `-fc, -form-config <file>` | | Custom form configuration. |
| `-flc, -field-config <file>` | | Custom field configuration. |

### Extraction

| Flag | Meaning |
|---|---|
| `-fx, -form-extraction` | Extract form, input, textarea and select elements into JSONL output. |
| `-xhr, -xhr-extraction` | Extract XHR request URL and method into JSONL output. |
| `-aff, -automatic-form-fill` | Experimental: actually fill and submit forms. |
| `-kb, -knowledge-base` | Knowledge-base classification. |
| `-kb-secrets` | Secrets extractor. `-kb-validate-secrets` validates them against the provider — it sends live API calls to third parties. |
| `-kb-endpoints` | Classify REST/GraphQL/SOAP/XHR endpoints. |

### Scope and filtering

| Flag | Default | Meaning |
|---|---|---|
| `-fs, -field-scope <scope>` | `rdn` | Pre-defined scope: `dn`, `rdn`, `fqdn`, or a custom regex. |
| `-cs, -crawl-scope <re>` | | In-scope URL regex the crawler may follow. Repeatable. |
| `-cos, -crawl-out-scope <re>` | | URL regex to exclude. Repeatable. |
| `-ns, -no-scope` | off | Disable host-based default scope. |
| `-do, -display-out-scope` | off | Show external endpoints found while scoped crawling. |
| `-mr, -match-regex <re>` | | Only output URLs matching this regex. |
| `-fr, -filter-regex <re>` | | Drop output URLs matching this regex. |
| `-em, -extension-match <ext>` | | Only output these extensions (`php,html,js,none`). |
| `-ef, -extension-filter <ext>` | | Drop these extensions (`png,css`). |
| `-ndef, -no-default-ext-filter` | off | Remove the built-in extension filter list. |
| `-mdc, -match-condition <expr>` | | DSL match condition. |
| `-fdc, -filter-condition <expr>` | | DSL filter condition. |
| `-fpt, -filter-page-type <t>` | | Filter by page type (`error`, `captcha`, `parked`). |
| `-duf, -disable-unique-filter` | off | Disable duplicate-content filtering. |
| `-pcs, -page-content-similar` | off | Filter near-duplicate pages after exact dedup. |

### Rate

| Flag | Default | Meaning |
|---|---|---|
| `-c, -concurrency <n>` | 10 | Concurrent fetchers. |
| `-p, -parallelism <n>` | 10 | Concurrent inputs. |
| `-rl, -rate-limit <n>` | 150 | Requests per second, globally. |
| `-rlm, -rate-limit-minute <n>` | | Requests per minute. |
| `-hrl, -host-rate-limit <n>` | | Requests per second per host. |
| `-hrlm, -host-rate-limit-minute <n>` | | Requests per minute per host. |
| `-rd, -delay <s>` | 0 | Delay between requests, in seconds. |

### Headless

| Flag | Meaning |
|---|---|
| `-hl, -headless` | Enable headless crawling (experimental). |
| `-hh, -hybrid` | Headless hybrid crawling (experimental). |
| `-sc, -system-chrome` | Use a locally installed Chrome instead of the bundled one. |
| `-scp, -system-chrome-path <path>` | Path to that Chrome binary. |
| `-cwu, -chrome-ws-url <url>` | Use a Chrome instance launched elsewhere. |
| `-cdd, -chrome-data-dir <dir>` | Where to store Chrome profile data. |
| `-nos, -no-sandbox` | Run Chrome with `--no-sandbox`. |
| `-noi, -no-incognito` | Do not use incognito mode. |
| `-ho, -headless-options <opt>` | Extra Chrome options. |
| `-sb, -show-browser` | Show the browser window. |
| `-pls, -page-load-strategy <s>` | `heuristic`, `load`, `domcontentloaded`, `networkidle`, `none`. |
| `-dwt, -dom-wait-time <s>` | Wait after load with the `domcontentloaded` strategy. |
| `-mfc, -max-failure-count <n>` | Consecutive action failures before stopping. |
| `-al, -auto-login <user:pass>` | Automatic login (headless only). |
| `-ed, -enable-diagnostics` | Diagnostics. |

### Output

| Flag | Meaning |
|---|---|
| `-jsonl, -j` | JSONL output. |
| `-o, -output <file>` | Write output to a file. |
| `-ot, -output-template <tpl>` | Custom output template. |
| `-f, -field <field>` | Display a single field (`url`, `path`, `fqdn`, `rdn`, `rurl`, `qurl`, `qpath`, `file`, `ufile`, `key`, `value`, `kv`, `dir`, `udir`). DEPRECATED in `-h`: use `-ot`. |
| `-sf, -store-field <field>` | Store a field in per-host output. |
| `-sfd, -store-field-dir <dir>` | Per-host field output directory. |
| `-sr, -store-response` | Store requests and responses. |
| `-srd, -store-response-dir <dir>` | Where to store them. |
| `-or, -omit-raw` | Leave raw request/response out of JSONL. |
| `-ob, -omit-body` | Leave response bodies out of JSONL. |
| `-lof, -list-output-fields` | Prints the available JSONL field names; does not filter output. |
| `-eof, -exclude-output-fields` | Drop these JSONL fields. |
| `-ncb, -no-clobber` | Do not overwrite the output file. |
| `-silent` | Output results only. |
| `-nc, -no-color` | No ANSI colour. |
| `-v, -verbose` / `-debug` | Verbose and debug output. |
| `-elog, -error-log <file>` | Write failed-request errors to a file. |
| `-duc, -disable-update-check` | Skip the update check. Use always. |
| `-up, -update` | Update the binary. Do not use inside this image. |

## Typical workflows

1. **Map a site's URL surface, non-headless.**

   ```bash
   katana -u "$TARGET" -d 3 -silent -nc -duc -o "$WORK/katana-urls.txt"
   wc -l "$WORK/katana-urls.txt"
   ```

2. **Include JavaScript-derived endpoints.**

   ```bash
   katana -u "$TARGET" -d 3 -jc -silent -nc -duc -o "$WORK/katana-js.txt"
   ```

3. **Find forms and XHR endpoints for later testing.**

   ```bash
   katana -u "$TARGET" -d 3 -jc -fx -xhr -jsonl -silent -duc \
     -o "$WORK/katana-endpoints.jsonl"
   ```

4. **Bounded crawl of a large site.** Depth alone is not enough on a site with
   many links at depth 2:

   ```bash
   katana -u "$TARGET" -d 5 -ct 10m -rl 25 -c 5 -p 5 -silent -nc -duc \
     -em php,html,js -o "$WORK/katana-bounded.txt"
   ```

5. **Restrict and exclude by URL shape.** Only the application path, never the
   static assets or the logout links:

   ```bash
   katana -u "$TARGET" -d 4 \
     -cs '/app/' -cos '/logout|/signout|/delete' \
     -ef png,jpg,css,woff,woff2,svg \
     -silent -nc -duc -o "$WORK/katana-app.txt"
   ```

6. **Feed discovered URLs straight into a scanner.** See *Chaining*.

## Output and parsing

Plain output is one URL per line. `-jsonl` emits one object per discovered
request. Verified structure in this build — top level is exactly
`timestamp`, `request`, `response`, plus `error` on failure and `forms` with
`-fx`:

| Field | Meaning |
|---|---|
| `.timestamp` | When the URL was found. |
| `.request.endpoint` | The URL fetched. This is the field to extract. |
| `.request.method` | HTTP method. |
| `.request.raw` | Raw request text. Removed by `-or`. |
| `.request.tag`, `.request.attribute`, `.request.source` | Present on links found by parsing HTML (e.g. `tag:"a"`, `attribute:"href"`, `source:"http://…"`). |
| `.response.status_code` | HTTP status. |
| `.response.headers` | Response headers as an object. |
| `.response.body` | Response body. Removed by `-ob`. |
| `.response.content_length` | Body length. |
| `.response.raw` | Raw response text. Removed by `-or`. |
| `.error` | Present instead of `.response` when the fetch failed. |
| `.forms[]` | With `-fx`: `method`, `action`, `enctype`, `parameters[]`. |

Verified `-fx` output for a page containing a form:

```json
{"timestamp":"...","request":{"method":"GET","endpoint":"http://127.0.0.1:8099/form.html","raw":"..."},
 "response":{"status_code":200,"headers":{...},"body":"...","content_length":230,"raw":"..."},
 "forms":[{"method":"POST","action":"http://127.0.0.1:8099/submit",
           "enctype":"application/x-www-form-urlencoded","parameters":["user","pass","c","s"]}]}
```

A failed fetch carries an error instead of a response:

```json
{"timestamp":"...","request":{"method":"GET","endpoint":"http://127.0.0.1:8099/index.html",...},
 "error":"GET http://127.0.0.1:8099/index.html giving up after 2 attempts: ... connection refused"}
```

```bash
# the URL surface, deduplicated
jq -r '.request.endpoint' "$WORK/katana.jsonl" | sort -u

# only successful fetches
jq -r 'select(.response.status_code == 200) | .request.endpoint' "$WORK/katana.jsonl"

# parameterised URLs — the interesting ones for injection testing
jq -r '.request.endpoint' "$WORK/katana.jsonl" | grep -E '\?' | sort -u

# POST endpoints and their bodies
jq -r 'select(.request.method == "POST")
       | "\(.request.endpoint)\t\(.request.body // "")"' "$WORK/katana.jsonl"

# forms and their parameters, with -fx
jq -c '.forms[]? | {method, action, parameters}' "$WORK/katana.jsonl"

# fetches that failed, with the reason
jq -r 'select(.error) | "\(.request.endpoint)\t\(.error)"' "$WORK/katana.jsonl"
```

Note there is **no `.response.technologies`** unless `-td` is passed, and
katana's JSONL contains the full response body by default — `-ob` and `-or`
are what keep the file readable.

Keep output small enough to read:

```bash
katana -u "$TARGET" -d 2 -or -ob -jsonl -silent -duc | jq -r '.request.endpoint'
```

## Chaining with the rest of the toolchain

Katana emits one URL per line in plain mode, which is what the other tools
want. In `-jsonl` mode, extract `.request.endpoint` first.

```bash
# crawl -> content discovery
katana -u "$TARGET" -d 3 -silent -duc > "$WORK/urls.txt"
ffuf -u "$TARGET/FUZZ" -w /opt/wordlists/SecLists/Discovery/Web-Content/common.txt \
  -mc 200,301,302,401,403 -rate 25 -s

# crawl -> scan each discovered URL
katana -u "$TARGET" -d 3 -jc -silent -duc \
  | nuclei -tags exposure,misconfig -ni -rl 25 -c 10 -silent -jsonl -duc \
      -o "$WORK/katana-nuclei.jsonl"

# crawl -> confirm which discovered URLs are live -> scan
katana -u "$TARGET" -d 3 -silent -duc \
  | httpx -silent -sc -title -duc \
  | tee "$WORK/live.txt" \
  | nuclei -severity medium,high,critical -ni -rl 25 -c 10 -silent -jsonl -duc
```

- `ffuf` and `feroxbuster` want a base URL plus a wordlist, so katana's output
  is best used as a *seed* list and a source of discovered directories, not as
  `FUZZ` input directly.
- `dalfox` accepts a file of URLs with parameters; katana is the usual way to
  produce it:

  ```bash
  jq -r '.request.endpoint' "$WORK/katana.jsonl" | grep -E '\?' | sort -u \
    > "$WORK/params.txt"
  ```

- `katana` after `httpx` is the correct order: crawl only confirmed live hosts.

## Limits, failure modes and gotchas

- **Headless crawling is unverified in this image, and when it fails it fails
  quietly.** `-hl`/`-hh` download a Chromium build via go-rod from
  `storage.googleapis.com` into `/root/.cache/rod/browser/chromium-<rev>` on
  first use (about 150 MB, needs egress). The shared libraries Chromium links
  against — `libnss3`, `libnspr4`, `libatk*`, `libatspi`, `libcups`, `libgbm`,
  `libxkbcommon`, `libXcomposite`, `libXdamage`, `libXrandr`, `libXfixes`,
  `libpango`, `libcairo`, `libasound` — **are now installed by
  `tools/katana/install.sh`**. Previously they were not, and without them `ldd`
  reported 14 missing and the browser could not launch at all. What has not
  been done is a live headless crawl against a built image, so treat `-hl`/`-hh`
  as untested until someone runs one.

  The failure mode to watch for is the dangerous kind: katana **exits 0** and
  reports `Crawl completed in 1s. 0 endpoints found.` rather than an error. A
  headless crawl that finds nothing has found nothing about the target — it
  never had a browser. If you need certainty now, use `-jc` (non-headless JS
  parsing), which needs no browser and is known to work.
- **The output flag is `-jsonl`, not `-json`.** `katana -json` fails with
  `flag provided but not defined: -json`. This differs from httpx, where
  `-json` is correct.
- **`-lof` prints the available field names** rather than filtering output.
  Use `-eof` to drop fields, or `jq` to select them.
- **`-kf` needs `-d 3` or more.** The help states this explicitly; with a
  shallower depth the known-files crawl is incomplete.
- **`-aff` submits forms.** Automatic form fill is experimental and can change
  server state (signups, deletions, submissions). Leave it off.
- **`-kb-validate-secrets` sends live API calls to third-party providers** to
  validate any secret it finds. That leaks the target's secret to the issuing
  service and creates attributable traffic. Do not enable it without explicit
  confirmation.
- **`-fs rdn` is the default and it is load-bearing.** It keeps the crawl
  inside the registrable domain. `-ns` disables host scope entirely; `-fs fqdn`
  narrows to the exact hostname. Check which one you are running.
- **`-do` output is out of scope by definition.** External endpoints seen while
  scoped crawling get displayed; do not pass them to a scanner without treating
  them as a new target requiring authorization.
- **A crawl can log you out or trip rate limits.** Katana follows every link,
  including logout and delete links. Use `-cos` to exclude them on any app
  where that matters.
- **Deep crawls explode combinatorially.** Depth 5 on a site with filters and
  pagination can be tens of thousands of requests. Always set `-ct` as well as
  `-d`.
- **`-rl` is global while `-c`/`-p` are per-worker.** Raising concurrency
  without raising the rate limit just makes katana queue.
- **`-jsl` is memory intensive** by its own help text. On a JS-heavy site it
  can exhaust the container's memory before it finds anything.
- **URLs discovered by crawling are not necessarily reachable.** Katana reports
  what the HTML references, including dead links and templated placeholders
  like `/api/v1/{id}`. Confirm with httpx before reporting a surface.
- **`-sr` writes bodies to disk verbatim**, which can include session tokens and
  personal data. Store only what the finding needs.

## Safety and scope

Requires explicit human confirmation before running:

- Any target not already confirmed for this engagement.
- Any crawl that leaves the registrable domain (`-fs fqdn`, `-ns`, or passing
  `-do` results downstream).
- `-aff` (form submission), `-kb-validate-secrets` (live third-party API
  calls), and `-al` (automatic login).
- Headless mode (`-hl`, `-hh`), which needs a browser and executes page
  JavaScript.
- Raising `-c`, `-p` or `-rl` above the conservative defaults on a target that
  is not Greg's.
- Crawls without a duration bound (`-ct`) or depth bound (`-d`) on a site whose
  size is unknown.
- Crawling private or internal address space.
