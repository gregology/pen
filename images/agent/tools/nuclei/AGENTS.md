# nuclei

Template-driven vulnerability scanner. A YAML template describes a request, a
matcher, and what a match means; nuclei runs them against a target and reports
matches. It is the broad-strokes scanner in this toolchain: use it to find what
is *known* to be wrong with a service, then hand the interesting findings to a
specialist tool. Nothing else here covers CVE, exposure, default-credential and
misconfiguration templates in one pass.

## Installation and location

| | |
|---|---|
| Version | `3.11.1` (upstream release, sha256-verified at image build) |
| Binary | `/usr/local/bin/nuclei` |
| Templates | `/root/nuclei-templates` (baked at image build; 13,742 YAML files) |
| Config | `/root/.config/nuclei/config.yaml` (created on first run if absent) |
| Cache | `/root/.cache/nuclei/` |
| PDCP dir | `/root/.pdcp` (a path nuclei reports; it does not create it) |

Templates ship in the image because a scanner with no templates is inert. They
are installed at build time, so an ordinary scan needs no network access to
GitHub. Nuclei still performs an automatic update *check* on startup unless
told not to — pass `-duc` on every invocation. Nuclei writes `resume.cfg`,
report databases and stored responses relative to the working directory, so run
it inside the engagement directory.

```bash
nuclei -version -duc     # engine version, config dir, cache dir
nuclei -tv -duc          # installed nuclei-templates version
nuclei -tl -duc | wc -l  # templates matching the current filters
nuclei -tgl -duc         # every available tag
```

Two things to know before trusting a result set:

- **If the scan aborts with `[FTL] Could not run nuclei: no templates provided
  for scan`, there are no usable templates.** That is an environment fault, not
  a clean target. Check `find /root/nuclei-templates -name '*.yaml' | wc -l`.
- **`-tv` can print an empty version** — `Public nuclei-templates version:  (/root/nuclei-templates)`
  — even when the templates are present and usable. The template version is
  read from metadata that nuclei's own updater writes; a template tree
  installed by extracting a release archive has no such metadata. Use the file
  count and the directory listing as the real check, and record whichever
  identifier you can (`-tv` output, file count, or the archive tag) with a
  scan.

## Rules that apply to this tool

- **Authorization first.** Run only against targets Greg has explicitly
  confirmed for the current engagement. If a target's authorization is unclear,
  it is unauthorized.
- **Egress is the tunnel.** All traffic leaves through the WireGuard interface
  in the shared network namespace. Nothing in nuclei's configuration is what
  keeps the home IP out of the target's logs.
- **Narrow before broad.** Running the full template set at a target is
  thousands of requests and the fastest way to get rate-limited or blocked.
  Prefer `-severity` and `-tags` over firing the whole library. Widen only with
  a reason, and record the reason in the findings note.
- **Keep rate and concurrency conservative.** The defaults (`-rl 150`,
  `-c 25`, `-bs 25`) assume a target that can take it. Start at `-rl 10 -c 5`
  on anything that is not Greg's, and raise it only when the target is known to
  tolerate the load.
- **Pass `-ni` unless the scan needs interactsh.** Interactsh (OAST) is on by
  default and registers the scan with public ProjectDiscovery callback servers
  (`oast.pro`, `oast.live`, …). That is a third party receiving
  target-derived context. Enable it only for blind-vulnerability testing, and
  say so in the findings.
- **Do not run fuzzing templates by default.** `-dast` sends payloads; that is
  a different activity from matching a fingerprint, and it needs explicit
  confirmation for the specific target.
- **Never enable code or file templates without confirmation.** `-code` runs
  JavaScript/code templates and `-file` reads local files.
- **Evidence goes to disk.** `-jsonl -o` so a finding is reproducible
  independently of the transcript.
- **Always pass `-duc`.** No update checks against ProjectDiscovery during an
  engagement.

## Command reference

Every flag below is from `nuclei -h` on 3.11.1.

### Target input

| Flag | Meaning |
|---|---|
| `-u, -target string[]` | Target URL or host. Repeatable, or comma-separated. `-target` is an alias of `-u`, not a separate mode. |
| `-l, -list <file>` | File of targets, one per line. |
| `-targets-inline <text>` | Inline multiline target list, for template profiles. |
| `-eh, -exclude-hosts string[]` | Hosts/IPs/CIDRs to exclude from the input. |
| `-im, -input-mode <mode>` | `list` (default), `burp`, `jsonl`, `yaml`, `openapi`, `swagger`. |
| `-sa, -scan-all-ips` | Scan every IP a hostname resolves to. |
| `-iv, -ip-version string[]` | `4`, `6`, or both. Default `4`. |
| `-no-stdin` | Disable stdin processing. |
| stdin | Piped lines are treated as targets, same as `-l`. |

### Template selection

| Flag | Meaning |
|---|---|
| `-t, -templates <path>` | Template file or directory; comma-separated, or a file of paths. |
| `-w, -workflows <path>` | Workflow, or workflow directory. |
| `-tl` | List templates matching current filters instead of running them. |
| `-tgl` | List every available tag. |
| `-tags <a,b>` | Only templates carrying these tags (`cve`, `exposure`, `misconfig`, `takeover`, `default-login`, `tech`, …). |
| `-etags, -exclude-tags <a,b>` | Exclude these tags. Use to drop `dos` and `fuzz` on fragile targets. |
| `-itags, -include-tags <a,b>` | Force-include tags excluded by default or by config. |
| `-s, -severity <a,b>` | `info`, `low`, `medium`, `high`, `critical`, `unknown`. **`-s` is severity here, not silent.** |
| `-es, -exclude-severity <a,b>` | Drop severities. |
| `-id, -template-id <id>` | Run templates by id; wildcards allowed. |
| `-eid, -exclude-id <id>` | Exclude templates by id. |
| `-it, -include-templates <path>` | Force-include a template path excluded by default or config. |
| `-et, -exclude-templates <path>` | Exclude a template file or directory. |
| `-pt, -type <t>` | Protocol filter: `http`, `dns`, `ssl`, `tcp`, `headless`, `file`, `websocket`, `whois`, `code`, `javascript`, `workflow`. |
| `-ept, -exclude-type <t>` | Exclude protocol types. |
| `-a, -author <name>` | Filter by template author. |
| `-em, -exclude-matchers <name>` | Drop specific matchers from the results. |
| `-tc, -template-condition <expr>` | Filter templates by expression. |
| `-nt, -new-templates` | Only templates added in the latest release. |
| `-as, -automatic-scan` | Wappalyzer technology detection mapped to tags. |
| `-dast` | Enable DAST (fuzzing) templates. `-fuzz` is the deprecated spelling. |
| `-code` / `-file` / `-esc` / `-egm` | Enable code, file, self-contained and global-matcher templates. Leave off. |
| `-validate` | Validate templates and exit. |

### Request behaviour and rate limiting

| Flag | Default | Meaning |
|---|---|---|
| `-rl, -rate-limit <n>` | 150 | Requests per second, globally. |
| `-rld, -rate-limit-duration <d>` | 1s | Window for `-rl`. |
| `-per-host-rate-limit` | off | Apply the rate limit per host rather than globally. |
| `-c, -concurrency <n>` | 25 | Concurrent templates. |
| `-bs, -bulk-size <n>` | 25 | Concurrent hosts per template. |
| `-pc, -payload-concurrency <n>` | 25 | Payload concurrency per template. |
| `-timeout <s>` | 10 | Per-request timeout. |
| `-retries <n>` | 1 | Retries on failure. |
| `-mhe, -max-host-error <n>` | 30 | Errors before a host is skipped for the rest of the scan. |
| `-nmhe, -no-mhe` | off | Never skip a host on errors. |
| `-mt, -max-time <d>` | none | Hard stop for the whole run (`30m`, `1h`). |
| `-H, -header <hdr>` | | Extra header/cookie. Repeatable, or from a file. |
| `-V, -var key=value` | | Custom template variable. |
| `-fr, -follow-redirects` / `-fhr` / `-dr` / `-mr <n>` | | Redirect behaviour. |
| `-r, -resolvers <file>` | | Resolver list for nuclei's own DNS. |
| `-sr, -system-resolvers` | | Fall back to system DNS on resolver errors. |
| `-lna, -restrict-local-network-access` | off | Block connections to local/private networks. |
| `-ni, -no-interactsh` | off | Disable interactsh (OAST) templates and server registration. |
| `-headless` | off | Enable templates needing a headless browser. |
| `-sc, -system-chrome` | off | Use the browser already on `PATH` (the pinned `/usr/local/bin/chromium` from `tools/browser`) rather than downloading one. |
| `-passive` | off | Passive HTTP response processing mode. |
| `-proxy, -p <url>` | | Proxy. Not needed here; the tunnel is the egress. |
| `-rlm, -rate-limit-minute <n>` | | Marked DEPRECATED in `-h`; use `-rl`. |

### Output

| Flag | Meaning |
|---|---|
| `-jsonl, -j` | One JSON object per match on stdout. The pipeline format. |
| `-o, -output <file>` | Also write findings to a file. |
| `-silent` | Print findings only; no banner, progress or info logs. **There is no `-s` alias for this.** |
| `-nc, -no-color` | No colour. Use whenever parsing output. |
| `-or, -omit-raw` | Leave the request/response pair out of JSON output. |
| `-ot, -omit-template` | Leave the encoded template out of JSON output. |
| `-jle, -jsonl-export <file>` | Write **findings** as JSONL to a file. Not an error log. |
| `-je, -json-export <file>` | Write findings as a JSON array to a file. |
| `-me, -markdown-export <dir>` | Export findings as Markdown into a directory. |
| `-se, -sarif-export <file>` | Export findings as SARIF. |
| `-ms, -matcher-status` | Display match failure status. |
| `-sresp, -store-resp` / `-srd, -store-resp-dir <dir>` | Store every request/response nuclei sends (default dir `output`). |
| `-rdb, -report-db <file>` | Persist report data in a nuclei reporting database. |
| `-rd, -redact <key>` | Redact keys from query parameters, headers and body in output. |
| `-elog, -error-log <file>` | Write sent-request **errors** to a file. This is the error log. |
| `-stats`, `-sj, -stats-json` | Progress statistics, human or JSONL. |
| `-hps, -http-stats` | Capture HTTP status statistics (experimental). |

### Update and maintenance

| Flag | Meaning |
|---|---|
| `-ut, -update-templates` | Fetch the latest template release. Needs egress to GitHub. |
| `-ud, -update-template-dir <dir>` | Install/update templates into a custom directory. |
| `-duc, -disable-update-check` | Skip the automatic update check on this run. Use always. |
| `-reset` | Remove all nuclei config and data, **including templates**. Do not use. |
| `-up, -update` | Update the nuclei binary. Do not use inside this image. |

## Typical workflows

1. **Known-CVE sweep of a specific service.** Feed it the URLs `httpx`
   already confirmed:

   ```bash
   mkdir -p "$WORK"
   httpx -l "$WORK/hosts.txt" -silent -json -duc -o "$WORK/live.jsonl"
   jq -r '.url' "$WORK/live.jsonl" \
     | nuclei -severity critical,high -etags dos,fuzz -rl 25 -c 10 -ni -silent \
         -jsonl -duc -o "$WORK/nuclei-high.jsonl"
   ```

2. **Exposure and misconfiguration review of one app.** No payloads, high
   signal:

   ```bash
   nuclei -u "$TARGET" -tags exposure,misconfig,config -severity medium,high,critical \
     -rl 10 -c 5 -ni -silent -jsonl -duc -o "$WORK/nuclei-exposure.jsonl"
   ```

3. **Confirm a suspected technology and its known issues.** Run `tech` first,
   then the CVE templates for the products it reports:

   ```bash
   nuclei -u "$TARGET" -tags tech -silent -duc
   nuclei -u "$TARGET" -tags cve -severity high,critical -ni -silent -jsonl -duc \
     -o "$WORK/cve.jsonl"
   ```

4. **Keep raw request/response pairs as evidence.** Raw traffic is included by
   default; store everything nuclei sent for the hosts that matched:

   ```bash
   nuclei -u "$TARGET" -tags exposure -sresp -srd "$WORK/nuclei-traffic" \
     -silent -jsonl -duc -o "$WORK/exposure.jsonl"
   ```

5. **Bulk scan of a live-host list.** Targets arrive from httpx on stdin:

   ```bash
   cat "$WORK/live-hosts.txt" \
     | nuclei -severity medium,high,critical -ni -rl 25 -c 10 -bs 10 \
         -silent -jsonl -duc -o "$WORK/nuclei-bulk.jsonl"
   ```

## Output and parsing

`-jsonl` emits one object per match. Field names verified against this build:

| Field | Meaning |
|---|---|
| `.template-id` | Template that matched, e.g. `http-missing-security-headers`. |
| `.template-path` | Absolute path to the template file on disk. |
| `.template` | Template path relative to the templates directory. |
| `.template-url` | ProjectDiscovery cloud link. Present on library templates. |
| `.template-encoded` | The template itself, base64. Present instead of `template-url` on locally authored templates. Drop with `-ot`. |
| `.info.name` | Human name. |
| `.info.severity` | `critical`/`high`/`medium`/`low`/`info`/`unknown`. |
| `.info.author` | Template author(s). |
| `.info.tags` | Tags on the template. Always present, possibly empty. |
| `.info.description` | Template description. Omitted when the template has none. |
| `.info.metadata` | Free-form metadata block. Omitted when absent. |
| `.info.classification` | CVE/CWE/CVSS block. **`cve-id` and `cwe-id` are arrays**, e.g. `{"cve-id":null,"cwe-id":["cwe-693"]}`. |
| `.matcher-name` | Which matcher fired, when the template names its matchers (e.g. `strict-transport-security`). |
| `.type` | Protocol that matched: `http`, `dns`, `ssl`, `tcp`, … |
| `.host` / `.port` / `.scheme` / `.url` | Target context. |
| `.matched-at` | Exact URL or string that matched. `.matched` is not emitted by 3.11.1. |
| `.extracted-results` | Array of values pulled out by extractors. **Key absent unless a template has extractors that fired** — e.g. `["Pen Fixture Home"]`. |
| `.ip` | Resolved IP. |
| `.timestamp` | When the match was recorded. |
| `.curl-command` | Reproducer for HTTP findings. Not present on DNS/TCP/SSL matches. |
| `.request` / `.response` | Raw HTTP exchange. Present by default; removed by `-or`. |
| `.matcher-status` | Emitted on every result: `true` for a match, `false` otherwise. `-ms` makes the failures visible. |

A real finding from `http-misconfiguration/http-missing-security-headers.yaml`
against a local server, trimmed:

```json
{"template":"http/misconfiguration/http-missing-security-headers.yaml",
 "template-url":"https://cloud.projectdiscovery.io/public/http-missing-security-headers",
 "template-id":"http-missing-security-headers","template-path":"/root/nuclei-templates/http/misconfiguration/http-missing-security-headers.yaml",
 "info":{"name":"HTTP Missing Security Headers","author":[...],"tags":[...],"description":"...","severity":"info","metadata":{...},"classification":{"cve-id":null,"cwe-id":["cwe-693"]}},
 "matcher-name":"strict-transport-security","type":"http","host":"127.0.0.1","port":"8099","scheme":"http",
 "url":"http://127.0.0.1:8099","matched-at":"http://127.0.0.1:8099","ip":"127.0.0.1",
 "timestamp":"...","curl-command":"curl -X 'GET' ...","matcher-status":false,
 "request":"...","response":"..."}
```

`-or` removes `request` and `response`; nothing else changes. Keys that are
absent stay absent — check with `jq 'has("extracted-results")'` rather than
assuming.

```bash
# one line per finding, worst first
jq -r '[.info.severity, ."template-id", ."matched-at"] | @tsv' "$WORK/nuclei-high.jsonl" \
  | sort -r

# just the replayable requests, for manual confirmation
jq -r '."curl-command" // empty' "$WORK/nuclei-high.jsonl" | head

# group by severity
jq -r '.info.severity' "$WORK/nuclei-high.jsonl" | sort | uniq -c

# deduplicate to the URL surface that actually matched something
jq -r '."matched-at"' "$WORK/nuclei-high.jsonl" | sort -u

# which matcher inside each template is firing
jq -r 'select(."matcher-name") | "\(."template-id")\t\(."matcher-name")"' \
  "$WORK/nuclei-high.jsonl" | sort | uniq -c | sort -rn

# CWE and CVE identifiers (both are arrays)
jq -r '.info.classification | [(."cve-id" // [])[], (."cwe-id" // [])[]] | .[]' \
  "$WORK/nuclei-high.jsonl" | sort -u

# extracted values, when the template extracts any
jq -r 'select(has("extracted-results")) | ."extracted-results"[]' "$WORK/nuclei-high.jsonl"
```

### Export formats

Verified behaviour of the export flags:

| Flag | Produces |
|---|---|
| `-jle <file>` | One JSON object per line, same schema as stdout `-jsonl`. |
| `-je <file>` | A JSON **array** of the same objects. |
| `-me <dir>` | One Markdown file per finding, plus `<dir>/index.md`. |
| `-se <file>` | SARIF. |

```bash
nuclei -u "$TARGET" -tags exposure -silent -duc \
  -jle "$WORK/nuclei.jsonl" -je "$WORK/nuclei.json" -me "$WORK/nuclei-md"
```

## Chaining with the rest of the toolchain

nuclei reads URLs or hosts from stdin, one per line, when `-u`/`-l` are absent.

```bash
# subdomains -> resolved -> live URLs -> scan
subfinder -d "$DOMAIN" -silent -duc \
  | dnsx -silent -a -resp-only -duc \
  | httpx -silent -ports 80,443,8080,8443 -duc \
  | nuclei -severity high,critical -ni -rl 25 -c 10 -silent -jsonl -duc \
      -o "$WORK/nuclei.jsonl"
```

- `httpx` first, always: nuclei on a dead host is wasted requests and noisy
  errors.
- `naabu` finds the ports, `httpx` confirms which speak HTTP, nuclei checks
  them:

  ```bash
  naabu -host "$TARGET" -top-ports 1000 -silent -duc \
    | httpx -silent -duc \
    | nuclei -severity medium,high,critical -ni -rl 25 -c 10 -silent -jsonl -duc
  ```

- `katana` supplies the URL surface; nuclei supplies the checks. Fuzzing
  templates need `-dast` and confirmation, so the default hand-off is to
  non-payload tags:

  ```bash
  katana -u "$TARGET" -jc -d 3 -silent -duc \
    | nuclei -tags exposure,misconfig -ni -rl 25 -c 10 -silent -jsonl -duc \
        -o "$WORK/katana-nuclei.jsonl"
  ```

- Anything nuclei reports at `high` or above is reproduced by hand from
  `.curl-command` before it is written up as confirmed.

## Limits, failure modes and gotchas

- **Zero findings is not evidence of safety.** It means no *template* matched.
  Business-logic and authentication flaws are invisible to this scanner; that
  is what `ffuf`, `arjun`, and manual reasoning are for.
- **Interactsh is on by default.** Omit `-ni` and nuclei registers with public
  ProjectDiscovery OAST servers and emits callbacks. This is easy to miss and
  it is a third-party service; pass `-ni` for ordinary scans.
- **A broken scan and a clean scan both exit 0.** An unresolvable host prints
  nothing and reports success. Check `-stats`, or confirm the target responds
  to `httpx` first.
- **`-mhe` silently drops hosts.** After 30 errors (default) a host is skipped
  and none of its remaining templates run. `-nmhe` disables that. A large scan
  that goes quiet on one host is usually this.
- **`-jsonl` includes raw request/response by default**, which makes files
  large and can echo credentials into logs. Use `-or`, or `-rd` to redact keys.
- **`-jle` is `-jsonl-export`, not an error log.** The error log is `-elog`.
  Both are one letter apart and do different things.
- **`-s` means severity, not silent.** `nuclei -s critical` filters; the silent
  flag has no short form. Getting this wrong silently changes what runs.
- **`-severity info` misses `unknown`.** Templates with no severity
  classification are `unknown`. Use `-es info` when the goal is "everything
  except noise". `-severity` and `-tags` combine as AND, not OR.
- **DAST templates do not run unless `-dast` is given.** A template tagged
  `fuzz` produces nothing without it.
- **Headless templates need `-sc`, which uses the browser in the image.** The
  image carries a pinned Chromium at `/usr/local/bin/chromium` (installed by
  `tools/browser`). Pass `-sc` and go-rod's `launcher.LookPath()` resolves it:

  ```bash
  nuclei -u "$TARGET" -headless -sc -ni -rl 25 -c 10 -silent -jsonl -duc \
    -o "$WORK/nuclei-headless.jsonl"
  ```

  Without `-sc` nuclei downloads its own Chromium at first use, which needs the
  tunnel up and is lost on container recreate. With `-sc` and no browser on
  `PATH` it fails loudly with `the chrome browser is not installed`. Either
  way, the failure mode to watch for is a headless template set that produces
  nothing — an empty result is not evidence that the target is clean. Unlike
  the other browser-dependent paths in this toolchain, headless templates have
  **not been exercised on a built image**; the first run should be against a
  page known to render client-side.
- **`-etags` removes a template silently, and the error is indistinguishable
  from having no templates.** Verified: a template with `tags: local` loads and
  runs normally in 3.11.1, but `nuclei -t <that file> -etags local` aborts with
  `[FTL] Could not run nuclei: no templates provided for scan`. `-tl -t <dir>`
  shows which templates actually loaded. Force one back with `-itags local`, or
  drop the tag from templates you author.
- **`-validate` passing does not mean the template will run.** A template can
  pass `nuclei -validate -t <file>` and then be removed from the run by
  `-etags`, `-tags` or `-exclude-templates`. Use `-tl -t <dir>` to confirm what
  the loader accepted.
- **`-rl` is global, not per host.** Scanning 50 hosts at `-rl 150` gives each
  host 3 rps. `-per-host-rate-limit` flips that, and then the global limit
  becomes unlimited — read it before using it.
- **WAF interference looks like a clean result.** A WAF returning 403 for every
  payload produces no matches. Run `wafw00f` first when a scan returns nothing
  on an app that should have surface.
- **Some templates are intrusive.** `dos`, `fuzz` and `intrusive` tags can
  change target state. Exclude them unless the engagement covers that class of
  testing.
- **Templates are pinned to the image.** `-duc` suppresses only the update
  *check*. `-ut` would download a newer revision mid-engagement and change what
  the scanner does; avoid it, and record the template identity with every scan.
  Because `-tv` can print an empty version here, record the file count from
  `find /root/nuclei-templates -name '*.yaml' | wc -l` as well.
- **`-reset` deletes the baked templates.** Recovering needs a template
  download from the internet. Do not run it.
- **Hostname vs IP.** With a bare IP, virtual-host templates that expect a Host
  header will not match. Use `-H "Host: name"` when the target is IP-addressed
  behind a vhost.

## Safety and scope

Requires explicit human confirmation before running:

- Any target not already confirmed for this engagement.
- Any scan using `-dast` (fuzzing) or the deprecated `-fuzz`.
- Any scan using `-code`, `-file`, `-esc` or `-egm` — templates that execute
  code or read files.
- Any scan with `-headless`.
- Omitting `-ni`, i.e. enabling interactsh and registering the scan with a
  third-party callback service.
- Scans that may touch private or internal address space. `-lna` blocks it;
  a private-range target is still a scope expansion.
- Raising `-rl`, `-c` or `-bs` above the conservative defaults on a target that
  is not Greg's.
- Running `-ut`/`-up` (changes the tool mid-engagement) or `-reset` (destroys
  the baked templates).
- Enabling `-per-host-rate-limit`, because it removes the global ceiling.
