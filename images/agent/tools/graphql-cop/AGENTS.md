# graphql-cop — GraphQL security audit

graphql-cop posts a fixed catalogue of probe queries at a GraphQL endpoint and
reports which ones it answers: introspection and field suggestions still on,
GraphiQL served, tracing/debug modes enabled, mutations reachable over GET, and
several query shapes that amplify load server-side. Every finding carries a
severity and a copy-paste cURL that reproduces it. It is the first GraphQL tool
to run, because what it reports decides which neighbour is needed next:
clairvoyance recovers a schema when introspection is off, and schemathesis fuzzes
a recovered schema. It is not an injection scanner — it asks the endpoint about
itself and never invents a query against the application's own types.

## Installation and location

| Item | Value |
|---|---|
| Version | Git tag **1.16**; `version.py` inside that tag still reports `VERSION = '1.15'` (upstream did not bump it), so `graphql-cop --version` prints `version: 1.15`. Both numbers describe what is installed |
| Install shape | GitHub tag source tree — **not on PyPI** |
| Source tree | `/opt/graphql-cop` (`graphql-cop.py`, `config.py`, `version.py`, `lib/`, `static/`) |
| Venv | `/opt/venvs/graphql-cop` |
| Launcher | `/usr/local/bin/graphql-cop` — a wrapper that `cd /opt/graphql-cop` before exec'ing the script, so the tree's static assets resolve |
| Interpreter | `/opt/venvs/graphql-cop/bin/python3` |
| Dependencies | `requests` is the requirement that matters; the venv also carries `simplejson`, `termcolor` and `PySocks`. Upstream's `requirements.txt` pins `requests==2.25.1` and `PySocks==1.7.1` from 2021, and those pins are deliberately not used |
| Argument parsing | Python `optparse` |
| Default endpoint paths | `/`, `/graphiql`, `/playground`, `/console`, `/graphql` — used only when `-t` carries no path |
| Wordlists | `-w` takes a file of **endpoint paths**, not field names; SecLists lives at `/opt/wordlists/current` |
| Runs as | root; `-h` and `--version` contact no target |

```bash
graphql-cop --version     # version: 1.15
graphql-cop -l            # the test names this build will actually run
```

## Rules that apply to this tool

- **Authorization first.** The load-amplifying probes below are real requests
  against a live API. Only against hosts explicitly confirmed for the
  engagement, and confirm again before the DoS-class tests.
- **DoS-class tests are load-amplifying by design.** Alias Overloading, Batch
  Queries, Directives Overloading and Circular Query using Introspection each
  turn one request into many server-side operations. They require explicit
  confirmation and must not be run against a shared or production system
  without it.
- **`-f` is not a retry switch.** It forces a scan against an endpoint that did
  not look like GraphQL, so probes go to something that may not be a GraphQL
  server at all. Confirm the endpoint by hand first.
- **`-o json` prints to stdout.** Redirect it to `$WORK`; the JSON is the
  reproducible record, the coloured terminal lines are not.
- **Use absolute paths.** The launcher `cd`s into `/opt/graphql-cop`, so a
  relative `-w` path resolves inside the tool tree, not in your working
  directory.
- **`-l` decides the test names.** Exclusions are per-run and a typo is not an
  error — see *Limits*.
- **TLS verification is hardcoded off** (`verify=False`), so a certificate
  problem is never reported and an interception proxy is invisible.
- **Headers are credentials.** `-H` usually carries a bearer token or a cookie,
  and `curl_verify` in the JSON output embeds the full request including those
  headers.
- **Egress is the tunnel.** `-x` is for local interception, not containment.

## Command reference

Usage is `graphql-cop.py -t http://example.com -o json`; the launcher is
`graphql-cop`. Flags below are from `-h` on this build, cross-checked against
the 1.16 tree.

| Flag | Meaning |
|---|---|
| `-t, --target=URL` | Target URL. With a path (`/graphql`) that one endpoint is tested; with a bare host the five default paths are tried |
| `-H, --header='{"Name": "value"}'` | Merge headers into every request, JSON object form; repeatable. A malformed value prints a cast error and the run continues without it |
| `-o, --output=FORMAT` | `json` prints the machine-readable array to stdout; any other value, or omitting the flag, gives the human report |
| `-e, --excluded-tests=LIST` | Comma-separated test names to drop for this run. Names come from `-l` |
| `-l, --list-tests` | Print the registered test names, one per line, and exit 0 |
| `-f, --force` | Scan even when GraphQL was not detected on the endpoint |
| `-d, --debug` | Add an `X-GraphQL-Cop-Test` header naming the current test to each request |
| `-x, --proxy=URL` | Send every request through a proxy, `http://user:pass@host:port` |
| `-w, --wordlist=FILE` | Replace the default path list with this file's endpoint paths (a leading `/` is added when missing). Ignored when `-t` already carries a path |
| `-v, --version` | Print `version: <n>` and exit. **`-v` is the version flag here, not verbose** |
| `-h, --help` | Usage; contacts no target |

### Detections

The catalogue below is upstream's documented set, with what each test asserts.
Any test with `result: true` in the JSON output is a finding.

| Test | Class | What it asserts about the endpoint |
|---|---|---|
| Alias Overloading | DoS | Accepts 100+ aliases in one query — one request becomes 100+ resolver calls |
| Batch Queries | DoS | Accepts an array of queries in a single request |
| GET based Queries | CSRF | Answers queries over GET, so a link or `<img>` can carry one |
| POST based Queries using urlencoded payloads | CSRF | Accepts `application/x-www-form-urlencoded` POSTs, which a cross-site HTML form can send |
| GraphQL Tracing / Debug Modes | Info leak | Tracing/debug mode is enabled and leaks execution detail |
| Field Duplication | DoS | Accepts 1000+ copies of the same field in one query. **Not registered in this build — see below** |
| Field Suggestions | Info leak | Error messages suggest field names; this is the oracle clairvoyance exploits |
| GraphiQL | Info leak | Serves an interactive GraphiQL console (probed at `/graphiql` in the default list) |
| Introspection | Info leak | Answers full schema introspection, so the API surface is readable by anyone who can reach it |
| Directives Overloading | DoS | Accepts many duplicated directives on one field |
| Circular Query using Introspection | DoS | Accepts a circular `__schema`/`__type` query that walks the type graph |
| Mutation support over GET methods | CSRF | Mutations can be issued over GET |

**The registered set is not identical to that list.** In the pinned 1.16 tree,
`lib/tests/__init__.py` has `field_duplication` commented out (upstream issue
#43) and registers `unhandled_error_detection`, which upstream's README does not
list. `-l/--list-tests` is the authority for what this build will run, and a
name that is not registered cannot be excluded.

## Typical workflows

1. **Audit one endpoint, JSON to disk.**

   ```bash
   graphql-cop -t "https://$TARGET/graphql" -o json > "$WORK/graphql-cop.json"
   jq -r '.[] | select(.result) | [.severity, .title] | @tsv' "$WORK/graphql-cop.json"
   ```

2. **Find the endpoint before auditing it.** katana's knowledge-base
   classification tags GraphQL endpoints; the path grep is the practical
   extraction:

   ```bash
   katana -u "https://$TARGET" -d 3 -jc -kb-endpoints -silent -jsonl -duc \
     -o "$WORK/katana.jsonl"
   jq -r '.request.endpoint' "$WORK/katana.jsonl" | grep -i graphql | sort -u \
     > "$WORK/graphql-urls.txt"
   ```

3. **First pass without the load-amplifying tests.**

   ```bash
   graphql-cop -l      # confirm the exact names for this build
   graphql-cop -t "https://$TARGET/graphql" \
     -e alias_overloading,batch_query,directive_overloading,circular_query_introspection \
     -o json > "$WORK/graphql-cop-safe.json"
   ```

4. **Authenticated audit.** An unauthenticated run against a protected endpoint
   mostly tests the login page:

   ```bash
   graphql-cop -t "https://$TARGET/graphql" \
     -H "{\"Authorization\": \"Bearer $TOKEN\"}" \
     -o json > "$WORK/graphql-cop-auth.json"
   ```

5. **Prove a "not GraphQL" verdict before forcing it.** Detection posts
   `query { __typename }` and looks for a GraphQL-shaped answer:

   ```bash
   curl -s -X POST "https://$TARGET/graphql" -H 'Content-Type: application/json' \
     -d '{"query":"query { __typename }"}' | head -c 200
   # only after that answered like GraphQL:
   graphql-cop -t "https://$TARGET/graphql" -f -o json > "$WORK/graphql-cop-forced.json"
   ```

6. **A custom endpoint list.** `-w` is a list of paths, one per line:

   ```bash
   printf '/api/graphql\n/v2/graphql\n' > "$WORK/graphql-paths.txt"
   graphql-cop -t "https://$TARGET" -w "$WORK/graphql-paths.txt" -o json \
     > "$WORK/graphql-cop-paths.json"
   ```

## Output and parsing

`-o json` prints **one line**: a JSON array sorted by test title, containing one
object per test per endpoint — including the tests that passed. Filter on
`result` or every finding is buried in negatives.

Verified keys in this build:

| Key | Meaning |
|---|---|
| `result` | Boolean; `true` is a finding |
| `title` | Test name, matching the `-l` names in spirit |
| `description` | What the probe observed |
| `impact` | Impact class, with the endpoint path appended (e.g. `Denial of Service - /graphql`) |
| `severity` | `HIGH`, `LOW`, `INFO`, … |
| `color` | ANSI colour hint for the terminal report |
| `curl_verify` | The reproduction cURL, with the full request headers and body |

```bash
# findings only
jq -r '.[] | select(.result) | [.severity, .title] | @tsv' "$WORK/graphql-cop.json"
# the reproduction commands, ready to paste
jq -r '.[] | select(.result) | .curl_verify' "$WORK/graphql-cop.json"
# what was tested and came back clean
jq -r '.[] | select(.result == false) | .title' "$WORK/graphql-cop.json"
# count by severity
jq -r '.[] | select(.result) | .severity' "$WORK/graphql-cop.json" | sort | uniq -c
```

A record looks like this (trimmed):

```json
{"result": true, "title": "Directive Overloading",
 "description": "Multiple duplicated directives allowed in a query",
 "impact": "Denial of Service", "severity": "HIGH", "color": "red",
 "curl_verify": "curl -X POST -H \"Content-Type: application/json\" -d '{\"query\": \"query { __typename @aa@aa@aa@aa }\"}' 'http://127.0.0.1:8090/graphql'"}
```

Human output prints only findings, as
`[HIGH] Directive Overloading - Multiple duplicated directives allowed in a query (Denial of Service)`.

When an endpoint is not detected, it prints and moves on:

```
https://$TARGET/graphql does not seem to be running GraphQL. (Consider using -f to force the scan if GraphQL does exist on the endpoint)
```

**Exit status carries no result information.** Verified in the 1.16 script:
there is no findings-based exit. It exits 1 only for a missing `-t` or a URL
without a scheme. A CI gate must parse the JSON.

## Chaining with the rest of the toolchain

```bash
# katana classifies the endpoints, graphql-cop audits each one
katana -u "https://$TARGET" -d 3 -jc -kb-endpoints -silent -jsonl -duc \
  -o "$WORK/katana.jsonl"
jq -r '.request.endpoint' "$WORK/katana.jsonl" | grep -i graphql | sort -u \
  > "$WORK/graphql-urls.txt"
while read -r u; do graphql-cop -t "$u" -o json; done < "$WORK/graphql-urls.txt" \
  > "$WORK/graphql-cop.json"

# nuclei carries GraphQL templates of its own
nuclei -tl -duc | grep -i graphql          # what the pinned template tree has

# the audit decides the next tool
jq -r '.[] | select(.result and .title == "Introspection") | .title' \
  "$WORK/graphql-cop.json"
```

- **Introspection reported as a finding** means the schema is available without
  brute force — take it and hand it to schemathesis.
- **Introspection clean but Field Suggestions reported** is the case
  clairvoyance exists for: it reads field names out of suggestion errors.
- **Both clean** means clairvoyance has no oracle to work with either; schema
  recovery would have to come from documentation or client code.
- Nuclei's GraphQL templates (`nuclei -tl -duc | grep -i graphql`) cover
  advisories this fixed catalogue does not; run them against the same endpoint
  after graphql-cop, not instead of it.

## Limits, failure modes and gotchas

- **The exit status says nothing about findings.** See *Output and parsing*: a
  `0` is not a clean endpoint.
- **A missing `-w` file turns the run into a no-op.** Verified in 1.16:
  `read_custom_wordlist` prints `Could not find wordlist file: <path>` and
  returns an empty set; with a target that has no path there are no endpoints to
  scan, so nothing runs and `-o json` prints `[]`. Use absolute paths — and
  treat `[]` as "nothing ran", not "nothing found".
- **`-w` is ignored when `-t` already has a path.** The wordlist only replaces
  the path list used for bare hosts.
- **A bare host is five endpoints, not one.** Each of the five paths is probed
  with the whole test set, so a host-only `-t` is roughly five times the work.
- **Failed requests read as clean results.** Each test wraps its own parsing in
  a bare `except`, so a timeout, a 500 or a non-JSON reply leaves `result:
  false`. "Not vulnerable" and "never got an answer" are the same JSON; check
  the endpoint by hand before reporting a negative.
- **Detection fails on authenticated endpoints.** `is_graphql` accepts a reply
  only when it looks GraphQL-shaped; a 401/403 or a login redirect produces
  `does not seem to be running GraphQL.` Add `-H` with the credential before
  reaching for `-f`.
- **`-f` probes an endpoint that did not look like GraphQL** — it forces the
  full test set regardless. It is not a fix for a wrong path or a missing
  header.
- **A malformed `-H` silently drops the header** after printing `Cannot cast
  [...] into header dictionary.`. An authenticated scan then runs
  unauthenticated and can report the endpoint as clean.
- **An unknown `-e` name is not an error**: `<name> cannot be excluded,
  skipping`, and the test still runs. `field_duplication` is such a name in this
  build because it is not registered.
- **`-d` makes the traffic louder**, not quieter: every request carries an
  `X-GraphQL-Cop-Test` header naming the test.
- **TLS verification is off and cannot be turned on** in this build.
- **Timeouts are fixed**: 60 s per POST, 20 s per GET, with no flag to change
  them; a slow endpoint therefore fails tests rather than reporting an error.
- **The JSON is one line, not one record per line.** Pretty-print with
  `jq .` when reading it by hand; `head -1` gives you the whole document.

## Safety and scope

Stop and get explicit human confirmation before:

- scanning any host not already authorized for this engagement;
- running the DoS-class tests — Alias Overloading, Batch Queries, Directives
  Overloading, Circular Query using Introspection — against anything shared;
- `-f` against an endpoint you have not confirmed is GraphQL;
- authenticated audits (`-H` with a token or cookie), which act as that user;
- pointing `-x` at anything other than a local interception proxy.

The JSON output and the command line both carry whatever `-H` contained, and
`curl_verify` repeats it in full. Keep the capture in `$WORK`, out of the repo,
and treat it as credential material.
