# schemathesis — OpenAPI/Swagger and GraphQL property-based testing

schemathesis reads an API schema, generates requests from it, sends them, and
checks the responses against what the schema says should happen. It is the tool
for "this API publishes a spec — does the implementation match it", and for
finding the inputs a hand-written test would never try: wrong types, missing
required fields, boundary values, unexpected headers. Reach for it when the
target serves an OpenAPI/Swagger document or answers GraphQL introspection —
`/openapi.json`, `/swagger.json`, `/v3/api-docs`, `/graphql`. It is not a
content discovery tool (gobuster/feroxbuster/ffuf), not a template scanner
(nuclei), and not an injection tool (sqlmap, commix, dalfox): it reports
*schema conformance* failures, and an injection finding usually arrives as a
500 that one of its checks flagged.

Two properties decide whether this tool is useful or dangerous. It generates
**valid and invalid** requests from the schema and **really sends them**,
including `POST`, `PUT`, `PATCH` and `DELETE`. And it is property-based: the
request count is a function of `--max-examples` and the number of operations,
not of anything a human chose per endpoint.

## Installation and location

| | |
|---|---|
| Version | 4.27.4 (`schemathesis --version` prints `schemathesis, version 4.27.4`) |
| Entry point | `/usr/local/bin/schemathesis` → `/opt/venvs/schemathesis/bin/schemathesis` |
| Venv | `/opt/venvs/schemathesis` |
| Library interpreter | `/opt/venvs/schemathesis/bin/python3` (bare `python3` is `/opt/py` and has no schemathesis) |
| Alias | upstream also ships `st`; the image leaves it unlinked, so `st` is not on `PATH`. Use the `schemathesis` spelling in scripts and reports. |
| Usage | `schemathesis run <schema-url-or-path>` |
| Reports | `--report-dir` (default `./schemathesis-report`) plus per-format path flags |

The venv is exposed with only the full console script linked — the `st` alias
was deliberately not bound on `PATH`, so a two-letter name that could mean
anything is not silently owned by this tool. `/opt/venvs/schemathesis/bin/st`
exists as an upstream artifact; running it is not a path this image supports.

```bash
schemathesis --version          # -> schemathesis, version 4.27.4
schemathesis run --help         # the authoritative option list for the installed build
```

## Rules that apply to this tool

1. **Authorization first.** A schema run generates and transmits write requests,
   including `DELETE`, against a live service. A target that appears in a
   `$TARGET` variable is not authorization; Greg's explicit confirmation for
   *this* engagement is. Never point it at a host whose authorization status is
   unclear.
2. **Bound every run.** Set `--max-time` and `--rate-limit` on the first run
   against any target, and treat `--max-examples` as a cost control. The default
   is property-based generation with no ceiling you set by hand — a run with a
   high `--max-examples` sends thousands of requests and will look like a
   denial-of-service attempt to the target's operators.
3. **Read the schema before you run it.** The schema tells you which paths and
   methods it declares. If it carries `DELETE /users/{id}` or a bulk import,
   assume the run will call it. If the target's spec is not the one you expect,
   stop.
4. **Authenticated APIs need credentials supplied on the command line.** A
   schema behind auth produces a wall of 401/403 findings that say nothing about
   the API; supply `--auth USER:PASS`, or a bearer token via
   `--header 'Authorization: Bearer …'`. Obtaining that token is `oauth2c`'s
   job, not this tool's.
5. **Do not treat a clean run as proof of correctness.** A run that produced no
   failures means the implementation matched the schema for the cases generated
   in the time and example budget allowed. That is a bounded statement, not a
   clean bill of health. Say which budget it was made under.
6. **Evidence goes to `$WORK`.** `--report-json-path` / `--report-ndjson-path` /
   `--report-junit-path` write machine-readable files you can re-parse without
   re-running. A finding without the report that produced it is not a finding.
7. **`--proxy` is for interception, not containment.** Pointing schemathesis at
   mitmproxy changes who can read the traffic; it does not change attribution.
   All egress leaves through the WireGuard tunnel and the gateway kill switch
   regardless.

## Command reference

The complete set of long options in 4.27.4 is listed below. Anything not in this
table does not exist in the installed version — check `schemathesis run --help`
before trusting a flag you read upstream, because the current README describes a
newer or older build than the one in this image.

Schema location and target

| Flag | Meaning |
|---|---|
| `--url URL` | API base URL. **Required when the schema is a file** — `The `--url` option is required when specifying a schema via a file.` |
| `--origin URL` | Origin (scheme, host, port) to which the schema's own base path is appended |
| `--wait-for-schema SECONDS` | Wait for the schema endpoint to become available (disabled by default) |
| `--tls-verify PATH\|false` | CA bundle for TLS verification, or `false` to disable it |

Authentication and request shaping

| Flag | Meaning |
|---|---|
| `--auth USER:PASS` | HTTP basic auth on every generated request |
| `--auth-wfc PATH` | Authenticate from a Web Fuzzing Commons auth file |
| `--auth-wfc-user NAME` | Which entry to use from that file (defaults to the first) |
| `--header 'Name: value'` | Extra header on every request; repeatable (e.g. `Authorization`) |
| `--proxy URL` | Proxy all requests (e.g. mitmproxy) |
| `--request-cert FILE` / `--request-cert-key FILE` | Client certificate and its private key |
| `--request-timeout SECONDS` | Per-request network timeout |
| `--request-retries N` | Retries on network-level failures |
| `--max-redirects N` | Redirects to follow per request |

Generation

| Flag | Meaning |
|---|---|
| `--max-examples N` | Maximum test cases **per API operation** — the main request-volume control |
| `--mode MODE` | Data generation mode: `positive` (schema-conformant), `negative` (deliberately violating the schema), `all` (default) |
| `--seed N` | Random seed, for a reproducible run |
| `--generation-deterministic` | Eliminate random variation between runs |
| `--generation-database PATH\|none\|:memory:` | Where discovered examples are stored |
| `--generation-unique-inputs` | Force unique test cases |
| `--generation-maximize METRIC` | Guide generation toward inputs more likely to expose bugs; repeatable |
| `--generation-codec CODEC` | Codec used when generating strings |
| `--generation-allow-x00 BOOLEAN` | Allow `NULL` bytes inside generated strings |
| `--generation-with-security-parameters BOOLEAN` | Generate security parameters |
| `--generation-graphql-allow-null BOOLEAN` | Use `null` for optional GraphQL arguments |

Checks and run control

| Flag | Meaning |
|---|---|
| `--checks NAME,…` | Only run these response checks (repeatable) |
| `--exclude-checks NAME,…` | Skip these response checks (repeatable) |
| `--max-failures N` | Stop the suite after N failures or errors |
| `--max-time SECONDS` | Whole-run time budget; fuzzing and stateful testing repeat until it is spent |
| `--max-response-time SECONDS` | Fail responses slower than this |
| `--continue-on-failure` | Keep running the remaining cases in a scenario after a failure |
| `--baseline PATH` / `--baseline-update` / `--baseline-prune` | Record accepted failures, merge new ones in, drop entries that no longer reproduce |
| `--include-by EXPR` / `--exclude-by EXPR` | Filter operations with a custom expression |
| `--exclude-deprecated` | Skip operations marked deprecated |
| `--workers N\|auto` | Concurrent workers; **default 1, maximum 64** |
| `--rate-limit LIMIT/DURATION\|auto` | Request rate limit, e.g. `100/m`, or `auto` to honour `Retry-After` on 429 |
| `--suppress-health-check NAME,…` | Disable generation health checks (`data_too_large`, `filter_too_much`, `too_slow`, `large_base_example`, `all`) |
| `--warnings off\|LIST` | Warning display control |

Output and reports

| Flag | Meaning |
|---|---|
| `--report FORMAT,…` | Generate reports: `junit`, `vcr`, `har`, `ndjson`, `json`, `allure` |
| `--report-dir DIR` | Directory for all report files; default `./schemathesis-report` |
| `--report-json-path FILE` | JSON run report at an explicit path |
| `--report-ndjson-path FILE` | NDJSON event stream at an explicit path |
| `--report-junit-path FILE` | JUnit XML at an explicit path |
| `--report-har-path FILE` | **HAR** (HTTP Archive) of the requests and responses at an explicit path |
| `--report-vcr-path FILE` | VCR cassette |
| `--report-allure-path DIR` | Allure result directory |
| `--report-preserve-bytes` | Keep exact payload bytes in cassettes, base64-encoded |
| `--output-sanitize BOOLEAN` | Obscure sensitive data in output |
| `--output-truncate BOOLEAN` | Truncate schemas and responses in error messages |
| `--no-color` / `--force-color` | ANSI colour off / on (the two cannot be combined) |

## Typical workflows

1. **Bound first, then let it run.** Start with a fixture or a confirmed
   non-production host, a two-minute wall-clock budget and a real rate limit:

   ```bash
   mkdir -p "$WORK/schemathesis"
   schemathesis run "http://127.0.0.1:8090/openapi.json" \
     --url "http://127.0.0.1:8090" \
     --rate-limit 20/m --max-time 120 --max-examples 20 --workers 1 \
     --report-json-path "$WORK/schemathesis/run.json" \
     --report-junit-path "$WORK/schemathesis/run.xml"
   ```

   The loopback fixture is the honest first test: `python3 -m http.server 8090`
   in one shell, a 3-endpoint OpenAPI document in the directory it serves, the
   run in another. Be aware of what that fixture can prove: `http.server` is
   read-only, so any `POST`/`PUT`/`DELETE` in the schema comes back as 501 and
   the run reports conformance failures that are the fixture's fault, not a
   target's. What it does prove is that the tool parsed the schema, generated
   requests, and wrote reports — the things you must confirm before pointing it
   at anything real. Port 8080 is the VPN gateway's control API in this
   container — never use it as a fixture.

2. **Positive-only pass on an authenticated API.** The token comes from
   `oauth2c`; the header travels on every generated request:

   ```bash
   schemathesis run "https://$TARGET/openapi.json" \
     --header "Authorization: Bearer $TOKEN" \
     --mode positive --checks status_code_conformance,content_type_conformance \
     --rate-limit 30/m --max-time 300 \
     --report-json-path "$WORK/schemathesis/positive.json"
   ```

3. **Schema from a file, base URL supplied separately.** A downloaded
   `openapi.json` has no usable host of its own, and this is the case the
   `--url` requirement exists for:

   ```bash
   schemathesis run "$WORK/schemathesis/openapi.json" --url "https://$TARGET" \
     --rate-limit 30/m --max-time 300 --workers 1 \
     --report-ndjson-path "$WORK/schemathesis/events.ndjson"
   ```

4. **Negative generation only, to shake out missing validation.** This is the
   mode that sends deliberately malformed bodies and parameters — review what the
   schema declares first, and keep the run short:

   ```bash
   schemathesis run "https://$TARGET/openapi.json" --mode negative \
     --max-examples 10 --rate-limit 20/m --max-time 180 \
     --report-json-path "$WORK/schemathesis/negative.json"
   ```

5. **A HAR of exactly what was sent.** The fastest way to answer "did it really
   send that DELETE" without re-running:

   ```bash
   schemathesis run "https://$TARGET/openapi.json" \
     --max-time 120 --rate-limit 20/m \
     --report-har-path "$WORK/schemathesis/run.har"
   ```

6. **GraphQL.** Point the same command at the GraphQL endpoint; the tool obtains
   the schema by introspection:

   ```bash
   schemathesis run "https://$TARGET/graphql" --max-examples 10 \
     --rate-limit 20/m --max-time 120 \
     --report-json-path "$WORK/schemathesis/graphql.json"
   ```

   Item 6 is the least verified workflow in this document: the GraphQL-specific
   generation options above are documented from the CLI source, but the
   introspection path has not been exercised against a live GraphQL fixture here.
   If it fails, treat `graphql-cop` as the fallback rather than assuming the
   target is clean.

## Output and parsing

The console output is a progress view and a failure summary; it is not the
interface. Branch on the report files.

- `--report-json-path FILE` — the structured run report: operations, checks,
  failures, and the failing cases.
- `--report-ndjson-path FILE` — one JSON event per line, written as the run
  proceeds, so a killed run still yields partial evidence.
- `--report-junit-path FILE` — JUnit XML, for CI-style aggregation.
- `--report-har-path FILE` — HAR, the request/response archive. Use it to prove
  what was actually transmitted, including any state-changing request.

```bash
# Failures in the JSON report, one per line (shape: run-scoped report object)
jq -r '.. | objects | select(has("failures")) | .failures[]? | [.name, (.operation // "")] | @tsv' \
  "$WORK/schemathesis/run.json" 2>/dev/null | head

# What was actually sent, straight out of the HAR
jq -r '.log.entries[] | [.request.method, .request.url, (.response.status|tostring)] | @tsv' \
  "$WORK/schemathesis/run.har"
```

The exact JSON report schema is **unverified** here: it was not exercised
against a real run in this image. Check the top-level keys with
`jq 'keys' "$WORK/schemathesis/run.json"` before writing a parser, rather than
trusting the paths above. The HAR shape is the standard HAR 1.2 layout, which is
stable.

If you need schemathesis as a library rather than a CLI, the interpreter is
`/opt/venvs/schemathesis/bin/python3` — bare `python3` cannot import it.

## Chaining with the rest of the toolchain

- **`oauth2c` → schemathesis.** Acquire the token first, then drive the API run
  with `--header "Authorization: Bearer $TOKEN"`. Without this, an authenticated
  schema produces only 401/403 findings.
- **`jwt_tool` → schemathesis.** When the API authenticates with a JWT, obtain a
  real token, then use `jwt_tool` to work out which claim mutations the API
  actually accepts, and point schemathesis at the same schema to test everything
  *else* about the request.
- **mitmproxy → schemathesis.** `--proxy http://127.0.0.1:8081` plus `mitmdump`
  gives you a live view and a rewrite point. This is the fastest way to see that
  a generated request was not the one you expected.
- **`websocat` / Python `websockets`** cover the WebSocket endpoints schemathesis
  cannot: it tests the HTTP surface described by the schema, not a frame protocol
  on top of it.
- **POST-run:** a 500 the run reported is a `nuclei`/manual-inspection lead, not
  a finding on its own. Record the schema, the report file, and the HAR together.
- **Filters:** `--include-by` / `--exclude-by` take expressions over operation
  fields, which is how a large schema gets trimmed to the paths in scope. The
  expression grammar is **unverified** here — read `schemathesis run --help` in
  the image before relying on a specific form.

## Limits, failure modes and gotchas

- **An authenticated schema silently becomes a 401/403 report.** No `--auth` or
  `--header` means every operation returns an auth rejection; the run may look
  busy and report findings that are all "the response didn't match the schema"
  for one boring reason. Read the response codes in the report before reading
  the failure names.
- **High `--max-examples` means thousands of requests.** With the default
  `--workers 1` that is slow; with more workers it is a burst. The default run
  has no time ceiling you set. Always supply `--max-time`, and add
  `--rate-limit N/m` (or `auto` to respect `Retry-After` on 429).
- **A server that mutates data will be mutated.** `POST`, `PUT`, `PATCH` and
  `DELETE` operations in the schema are generated and sent for real. There is no
  dry-run flag in the documented option set. This is the single most common way
  this tool causes damage.
- **A file schema needs `--url`.** Run `schemathesis run openapi.json` with no
  `--url` and the tool stops with
  ``The `--url` option is required when specifying a schema via a file.`` —
  the schema's own `servers` entry is not used as a fallback in that case.
- **`--mode` changes what is generated, not how far the run goes.** `positive`
  generates only schema-conformant data, `negative` only data that violates the
  schema, `all` both. Stateful sequence testing is part of the default run
  phases in 4.27.4 and has no option in this documented set to turn it down —
  bound the whole run with `--max-time` instead.
- **`st` is not on `PATH`.** A script copied from upstream that calls `st` fails
  with `command not found`. Use `schemathesis`.
- **`--no-color` and `--force-color` are mutually exclusive** — combining them is
  an error, not a no-op.
- **The dependency health checks can abort generation.** `filter_too_much`,
  `data_too_large`, `too_slow` and `large_base_example` are generation sanity
  checks; when one fires, schemathesis complains about its own data rather than
  about the API. `--suppress-health-check` silences a specific one — note what
  you suppressed in the run log, because it is a reduction in coverage.
- **The default report directory is `./schemathesis-report`.** Run it from
  `$WORK`, or pass `--report-dir`, or you will scatter report directories into
  the image filesystem (and into whatever directory a wrapper happens to use).
- **`--wait-for-schema` is disabled by default.** A schema endpoint that is
  momentarily down fails the run immediately rather than waiting.
- **TLS verification is on by default.** `--tls-verify false` disables it —
  that is a deliberate, visible downgrade for a self-signed target, not a
  workaround to apply by reflex.
- **Exit status is the run result, not a transport check.** Read the report for
  *what* failed; do not record a pass on exit 0 alone. Whether a run that found
  no failures exits 0 in every configuration is **unverified** here.

## Safety and scope

- **Confirm the target and the schema before the first request.** The schema is
  the scope: every operation in it will be exercised. If the schema is broader
  than the engagement — an admin API, a tenant-management endpoint — narrow it
  with `--include-by` or use a trimmed document, and get the narrowing confirmed.
- **Assume writes happen.** `POST`/`PUT`/`PATCH`/`DELETE` are generated and sent.
  Against a system with real users or real data, this needs explicit human
  approval, a maintenance window, or a staging deployment. Prefer the fixture
  documented above for anything you are not authorized to mutate.
- **Bound it as if it were a load test, because it is one.** `--rate-limit` and
  `--max-time` are the two flags that keep a property-based run from becoming an
  accidental DoS. Say in the findings what budget the run used.
- **Tokens are credentials.** A bearer token passed with `--header` is written
  into the HAR and the run report by default — check `--output-sanitize` before
  exporting those files, keep them in `$WORK`, and never paste a live token into
  the transcript.
- **The HAR is a full request archive.** It can contain credentials in headers,
  bodies, and query strings. Treat it as credential material, not as a log.
- **Attribution is the platform's, not the flag's.** `--proxy` does not route
  around the gateway; all egress stays on the WireGuard tunnel under the
  fail-closed kill switch. Do not use a proxy setting to change that.
