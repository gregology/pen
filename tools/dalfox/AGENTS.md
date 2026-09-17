# dalfox

XSS scanner and verifier. It takes URLs (or raw HTTP requests), discovers
parameters, injects a payload catalogue, and reports only what it can verify:
reflected XSS it can confirm in the response, DOM-XSS candidates from static
analysis of inline JavaScript, and stored-XSS checks. Nuclei's XSS templates are
pattern matches; dalfox drives payloads through the real response and labels its
confidence.

## Installation and location

| Item | Value |
|---|---|
| Version | `dalfox 3.2.3` (`dalfox --version` or `dalfox -V`) |
| Binary | `/usr/bin/dalfox` |
| Install | upstream `.deb` (`dalfox-v3.2.3-linux-x86_64.deb`) installed with apt |
| Wordlists | `/opt/wordlists/SecLists`; dalfox's own lists ship inside the binary |
| Browser | **none installed** (no chromium/firefox). Not required: DOM analysis is static AST analysis |
| Runs as | root; no TTY required, but see the stdin warning below |

## Rules that apply to this tool

1. **Authorization first.** dalfox sends real payloads into real parameters and
   follows them with verification requests. Only against explicitly confirmed
   targets.
2. **Everything leaves through the VPN.** One non-loopback interface: the
   WireGuard tunnel in the shared netns. `--proxy` is for local interception,
   not containment.
3. **Rate-limit by default.** The binary defaults to `--workers 50` against up
   to 50 concurrent targets. Use `--workers 2 --delay 100` (or `--rate-limit`)
   per host until the target is known to tolerate more.
4. **Always redirect stdin.** When stdin is not a TTY, dalfox reads targets from
   it *in addition* to the arguments. Verified: invoking dalfox from a script
   whose stdin was the script itself made it consume the remaining script lines
   as targets (`Merged 71 target(s) from stdin and 1 target(s) from arguments`).
   Use `< /dev/null` when you are not deliberately piping a URL list.
5. **Save evidence to the working directory.** `-f json -o $WORK/dalfox.json`
   plus the `meta` block is the reproducible record; the terminal output is not.
6. **TLS verification is off by default.** `--insecure` defaults to true. Pass
   `--insecure=false` when certificate validation matters to the finding.

## Command reference

Subcommands: `scan` (default when a target is given), `server`, `payload`,
`mcp`, `completion`, `help`. `dalfox version` is **not** a subcommand — it is
treated as a target URL.

### Input

| Flag | Meaning |
|---|---|
| `dalfox scan [TARGET]...` | One or more URLs. A path to a file is also accepted (auto-detected) |
| `-i, --input-type auto\|url\|file\|pipe\|raw-http\|har` | Force the input interpretation (default `auto`) |
| `--dedup-urls exact\|signature\|off` | Target dedup (default `exact`; `signature` collapses URLs differing only in parameter values) |
| `--state-file PATH` | Record completed targets and skip them on re-run |
| `-p, --param name[:query]` | Restrict analysis to named parameters (types: query, body, json, multipart, cookie, header, graphql, xml) |
| `-d, --data`, `-H`, `--cookies`, `-X/--method`, `--user-agent` | Request construction |
| `--cookie-from-raw FILE` | Load cookies from a raw request |

### Output

| Flag | Meaning |
|---|---|
| `-f, --format plain\|json\|jsonl\|markdown\|sarif\|toml` | Report format (default `plain`) |
| `-o, --output FILE` | Write the report to a file |
| `-S, --silence` | Only POC lines on stdout (the report file is still written) |
| `--no-color` | Disable ANSI colours (also honours `NO_COLOR`) |
| `--poc-type plain\|curl\|httpie\|http-request` | POC rendering (default `plain`) |
| `--only-poc v,r,a,i` | Show only these finding types (`v` vulnerable, `r` reflected, `a` AST DOM, `i` informational) |
| `--limit N`, `--limit-result-type` | Result count limits |
| `--include-request`, `--include-response`, `--include-all` | Attach HTTP request/response to findings |
| `--stream-findings` | Emit findings as they are verified instead of at the end |
| `--dry-run` | Parse targets and discover parameters without sending payloads |
| `--baseline FILE`, `--baseline-mode filter\|annotate` | Report only findings new since a previous JSON report |

### Scanning behaviour

| Flag | Meaning |
|---|---|
| `--deep-scan` | Test **all** payloads even after a finding; also lifts the built-in 3000-payload-per-parameter cap |
| `--max-payloads-per-param N` | Explicit payload cap (0 = built-in default) |
| `--only-discovery` / `--skip-discovery` | Parameter discovery only / skip discovery |
| `--skip-mining`, `--skip-mining-dict`, `--skip-mining-dom`, `-W FILE` | Parameter mining controls (`-W` supplies a wordlist) |
| `--skip-ast-analysis` | Disable the static DOM-XSS analysis that produces `[A]` findings |
| `--analyze-external-js` | Also fetch and analyse same-origin external scripts (off by default) |
| `--skip-reflection-header/-cookie/-path` | Turn off reflection checks |
| `--sxss`, `--sxss-url URL`, `--sxss-retries N` | Stored-XSS mode |
| `--hpp` | HTTP parameter pollution |
| `--detect-outdated-libs` | Report known-vulnerable JS libraries (informational) |
| `--custom-payload FILE`, `--only-custom-payload`, `--encoders`, `--remote-payloads` | Payload control |
| `--waf-bypass auto\|force\|off`, `--skip-waf-probe`, `--force-waf TYPE`, `--waf-evasion`, `--waf-min-confidence N` | WAF handling |

### Rate, timeouts, scope

| Flag | Meaning |
|---|---|
| `--workers N` | Concurrent workers (default 50). **Not `--worker`** |
| `--delay N` | Delay between a worker's requests, **milliseconds** (default 0) |
| `-r, --rate-limit N` (alias `--rl`) | Global outbound requests/second shared across workers and targets |
| `--timeout N` | Per-request timeout, seconds (default 10) |
| `--scan-timeout N` | Wall-clock cap on a target's injection stage, seconds (0 = off) |
| `--retries N`, `--retry-delay MS` | Retry 5xx/transport errors; `429` is always retried |
| `--max-concurrent-targets N`, `--max-targets-per-host N` | Fan-out limits (defaults 50 / 100) |
| `-F, --follow-redirects`, `--insecure[=false]`, `--ignore-return 302,403` | Transport |
| `--include-url`, `--exclude-url`, `--out-of-scope`, `--out-of-scope-file`, `--ignore-param` | Scope control |

## Typical workflows

1. **One URL, JSON evidence, conservative rate.**

   ```bash
   dalfox scan 'https://$TARGET/search?q=test' --workers 2 --delay 100 \
     -f json -o $WORK/dalfox.json < /dev/null
   jq -r '.findings[] | [.type, .method, .param, .severity, .payload] | @tsv' $WORK/dalfox.json
   ```

2. **A URL list from katana or httpx.**

   ```bash
   katana -u https://$TARGET -jc -d 3 -silent | grep '?' > $WORK/param-urls.txt
   dalfox scan -i file $WORK/param-urls.txt --workers 2 --delay 100 \
     --dedup-urls signature -f json -o $WORK/dalfox.json < /dev/null
   # or stream them in:
   grep '?' $WORK/katana-urls.txt | dalfox scan -i pipe --silence --no-color \
     --workers 2 --delay 100 -f jsonl -o $WORK/dalfox.jsonl
   ```

3. **Verify one suspected parameter without the full catalogue.**

   ```bash
   dalfox scan 'https://$TARGET/item?id=1' -p id:query --only-discovery < /dev/null   # what params exist
   dalfox scan 'https://$TARGET/item?id=1' -p id:query --workers 2 --delay 100 \
     -f json -o $WORK/dalfox-id.json < /dev/null
   ```

4. **POST/JSON endpoints and authenticated scans.**

   ```bash
   dalfox scan 'https://$TARGET/api/comment' -X POST \
     -H 'Content-Type: application/json' -d '{"body":"FUZZ","id":1}' \
     -p body:json --cookies "session=$TOKEN" --workers 2 --delay 200 < /dev/null
   ```

5. **Resume and compare across runs.**

   ```bash
   dalfox scan -i file $WORK/param-urls.txt --state-file $WORK/dalfox.state \
     -f json -o $WORK/dalfox-run2.json < /dev/null
   dalfox scan -i file $WORK/param-urls.txt --baseline $WORK/dalfox-run1.json \
     --baseline-mode filter -f json -o $WORK/dalfox-new.json < /dev/null
   ```

## Output and parsing

`-f json -o FILE` writes a single object with two keys, `meta` and `findings`
(not an array — `.findings[]` is the list).

`meta` (verified): `dalfox_version, dedup_mode, failed_requests,
findings_count, incomplete, scan_duration_ms, target_summary, targets,
targets_deduplicated, total_requests`.

`findings[]` (verified): `type, type_description, method, param, payload, data,
evidence, inject_type, location, severity, confidence, confidence_reason, cwe,
detection_method, message_id, message_str`.

```bash
# one line per verified finding
jq -r '.findings[] | [.type, .method, .param, .severity, .confidence, .payload] | @tsv' $WORK/dalfox.json
# was the scan complete, and how many requests did it cost?
jq -c '.meta | {findings_count, incomplete, total_requests, scan_duration_ms, targets_deduplicated}' $WORK/dalfox.json
# only confirmed-vulnerable findings, as ready-to-run curl
jq -r '.findings[] | select(.type=="V") | .data' $WORK/dalfox.json
```

Terminal form of a finding:

```
[POC][V][GET][inHTML] http://127.0.0.1:8090/search?q=%3E%3Csvg%20onload%3Dalert%281%29%20class%3Ddlx3914bbf1%3E
  ├── Issue: XSS payload DOM object identified
  ├── Payload: ><svg onload=alert(1) class=dlx3914bbf1>
  └── L1: ody><h1>Results for ><svg onload=alert(1) class=dlx3914bbf1></h1><input name="q"
```

`jsonl` starts with a `meta` record followed by finding records; `plain`,
`markdown`, `sarif` and `toml` are available for hand-off.

**Exit codes (verified):** `0` = scan finished with no findings, `1` = findings
were reported, `2` = error (unreachable target/CLI). A `1` is a result, not a
failure — do not let a `set -e` pipeline treat it as one.

## Chaining with the rest of the toolchain

```bash
# katana's routes -> dalfox
katana -u https://$TARGET -jc -d 3 -silent | grep '?' \
  | dalfox scan -i pipe --silence --no-color --workers 2 --delay 100 \
      -f jsonl -o $WORK/dalfox.jsonl

# httpx decides what is worth scanning, dalfox scans it
httpx -l $WORK/urls.txt -silent -mc 200 -json \
  | jq -r 'select(.tech[]? | test("react|angular|jquery")) | .url' \
  | dalfox scan -i pipe --workers 2 --delay 100 -f jsonl -o $WORK/dalfox-spa.jsonl

# findings into the report and into nuclei's confirmation
jq -r '.findings[] | select(.type=="V" or .type=="A") | [.param, .data] | @tsv' $WORK/dalfox.json
jq -r '.findings[].data' $WORK/dalfox.json | while read -r u; do
  nuclei -u "$u" -silent -t http/misconfiguration/ -jsonl
done

# ffuf/feroxbuster endpoints -> dalfox
jq -r 'select(.type=="response" and (.url|test("\\?"))) | .url' $WORK/ferox.jsonl \
  | dalfox scan -i pipe --workers 2 --delay 100 -f json -o $WORK/dalfox.json
```

## Limits, failure modes and gotchas

- **`dalfox version` is not a command.** Verified: it treats `version` as a
  target and reports `UNREACHABLE http://version/`. Use `dalfox --version`/`-V`.
- **`--worker` and `--deep-domxss` do not exist in 3.2.3.** Verified errors:
  `unexpected argument '--worker' found` (the flag is `--workers`) and
  `unexpected argument '--deep-domxss' found` (the tip suggests `--deep-scan`,
  which is *not* the same thing — it means "test all payloads even after a
  finding"). Do not pass flags remembered from older dalfox releases.
- **No browser is needed, and none is installed.** DOM-XSS coverage is static
  AST analysis of inline scripts and emits `[A]` findings; `--skip-ast-analysis`
  is what silences them (`--skip-mining-dom` only stops mining parameter names
  from `id`/`name` attributes). Verified: an `[A]` finding appeared on a page
  whose only sink was `innerHTML = location.search`, and disappeared with
  `--skip-ast-analysis`.
- **dalfox eats stdin.** With a non-TTY stdin it merges stdin targets with the
  argument targets. Inside scripts, always add `< /dev/null`; when piping a list
  use `-i pipe` and nothing else.
- **`--file` does not exist.** File input is either a positional path
  (`dalfox scan urls.txt`), `-i file`, or `-i pipe` from stdin. There is no
  `-u` flag — targets are positional.
- **`--delay` is milliseconds**, unlike ffuf's `-p` (seconds). Verified: two
  targets with `--workers 1 --delay 1000` took 177 s; the same two with
  `--rate-limit 2` took 182 s. The per-target request count is high (183
  requests for a single reflected parameter in the verification run), so pacing
  choices dominate runtime.
- **Payload caps.** Without `--deep-scan`, each parameter is capped at 3000
  base payloads per set; encoder expansion and WAF-bypass mutations are added on
  top and are not trimmed. On reflective-by-design endpoints this is the
  difference between a two-second scan and a very long one.
- **WAF detection adds pacing automatically.** A detected WAF triggers a
  per-WAF pacing hint even without `--waf-evasion`; `--waf-bypass off` restricts
  dalfox to detect-only if the mutation traffic is not wanted.
- **TLS validation is off unless you ask for it** (`--insecure` defaults to
  true).
- **`-S/--silence` does not suppress the report file**, only the logs. Verified:
  the JSON file was written with `-S`.
- **`incomplete: true` in `meta` means the scan did not finish** (session lost
  or `--scan-timeout`). Do not read that as "clean"; it is a false negative.
- **Output formats are not interchangeable for parsing**: `plain` is for humans,
  `json` is one object, `jsonl` is a meta record plus records, `toml`/`sarif`
  for other consumers. Pick one and parse it.

## Safety and scope

Stop and get explicit human confirmation before:

- scanning any host not already authorized for this engagement;
- `--sxss` (stored XSS) — it writes payloads into the application's data and
  other users can be affected;
- POST/PUT/DELETE injection, comment/feedback forms, or anything that creates
  or mutates records;
- `--deep-scan`, `--hpp`, `--waf-bypass force`, or `--remote-payloads`, which
  substantially increase request volume and payload aggressiveness;
- `--analyze-external-js` or remote payload providers, which contact third
  parties;
- authenticated scans (`--cookies`, `-H Authorization`), which act as that user.

An XSS finding is a claim about a victim's browser. Treat a `[V]` finding as
verified, an `[A]` finding as a candidate that still needs runtime confirmation,
and say which one you are reporting.
