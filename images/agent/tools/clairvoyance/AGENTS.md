# clairvoyance — GraphQL schema recovery when introspection is off

clairvoyance rebuilds a GraphQL schema from an endpoint that has introspection
disabled, by brute-forcing field and argument names and reading the field
suggestions the server returns in its error messages. Use it when graphql-cop
reports that introspection is off but you still need the API surface: for a
report, or as the input schema schemathesis fuzzes. It recovers names, not
vulnerabilities, and it is loud by design — it sends a large number of requests
and the `fast` profile is a load event, not a probe. When introspection is on,
read the schema directly instead; when field suggestions are also off, there is
no oracle to read and this tool has nothing to work with.

## Installation and location

| Item | Value |
|---|---|
| Version | **2.5.5** (GitHub tag `v2.5.5`) |
| Install shape | GitHub tag source tree installed as a Python package — **not on PyPI** |
| Source tree | `/opt/clairvoyance`; `pip install --no-build-isolation /opt/clairvoyance` builds it from there |
| Venv | `/opt/venvs/clairvoyance` |
| Console script | `/usr/local/bin/clairvoyance`, symlinked from `/opt/venvs/clairvoyance/bin/clairvoyance`; only that name is exposed, so a dependency's scripts do not land on `PATH` |
| Interpreter | `/opt/venvs/clairvoyance/bin/python3` |
| Build detail | `pyproject.toml` is poetry-shaped with no `[build-system]`, so `poetry-core` is installed in the venv first and pip builds with `--no-build-isolation` |
| Wordlist | With no `-w`, the wordlist shipped inside the package (`clairvoyance/wordlist.txt` next to the installed module) is used; `-w` replaces it for every brute-force stage |
| Defaults | `-d 'query { FUZZ }'`, `-p fast`, 50 concurrent requests, 3 retries when unset |
| Runs as | root; no TTY required; `clairvoyance --help` is verified at image build time |

```bash
clairvoyance --help       # the pinned v2.5.5 argument list
command -v clairvoyance   # /usr/local/bin/clairvoyance
```

## Rules that apply to this tool

- **Authorization first.** Every name it guesses is a POST to a live API. Only
  against hosts explicitly confirmed for the engagement.
- **Treat the `fast` profile as a load event.** It is the default and it runs 50
  concurrent requests. On anything shared or rate-limited, use `-p slow` (which
  drops concurrency to 1) or set `-c` yourself, and say which profile you ran in
  the findings note.
- **`--max-retries` and `--backoff` are what stop it hammering a struggling
  server.** They trade time for retries; leave them set rather than letting a
  broken endpoint be retried in a tight loop.
- **Run it only when introspection is off.** If graphql-cop reports
  Introspection, the schema is already available without brute force.
- **Always pass `-o` with an absolute path.** The schema file is the deliverable;
  see *Output and parsing* for what happens without it.
- **`-H` needs the exact `Name: value` separator** — a colon followed by a
  space. Any other spacing crashes before the first request.
- **The recovered schema is sensitive engagement material.** It is internal API
  surface; keep it in `$WORK`, out of the repo.
- **TLS verification is on by default.** `-k/--no-ssl` turns it off, which also
  hides certificate problems.
- **Egress is the tunnel.** `-x` is for local interception, not containment.
- **No proxy is set by default.** `-x` is unset unless you pass it, so nothing
  here reaches `127.0.0.1:8080` — which in this container is the VPN gateway's
  control API, not a proxy — unless you aim it there.

## Command reference

The positional `url` is the GraphQL endpoint. Every flag below was verified
against the pinned v2.5.5 source.

| Flag | Meaning |
|---|---|
| `url` | Positional; the GraphQL endpoint to recover a schema from |
| `-v, --verbose` | Repeatable count; one `-v` switches logging to `DEBUG` |
| `-i, --input-schema <file>` | A JSON schema to supplement with recovered information, so already-known parts are not brute-forced again |
| `-o, --output <file>` | Write the recovered JSON schema to this file. The help says the default is stdout; see *Limits* — pass it explicitly |
| `-d, --document <string>` | Start document; `FUZZ` is the substitution point. Default `query { FUZZ }` |
| `-H, --header <header>` | Add a header, `Name: value` (colon **and space**); repeatable |
| `-c, --concurrent-requests <int>` | Concurrent requests; unset means 50 |
| `-w, --wordlist <file>` | Newline-separated candidate names used for all brute-force stages; replaces the bundled list |
| `-wv, --validate` | Drop wordlist items that do not match the GraphQL name regex `[_A-Za-z][_0-9A-Za-z]*`, and log how many were removed |
| `-x, --proxy <string>` | Proxy for all requests (aiohttp proxy format) |
| `-k, --no-ssl` | Disable TLS verification |
| `-m, --max-retries <int>` | Retries for a failing request; 50 under the `slow` profile when unset |
| `-b, --backoff <int>` | Exponential backoff factor. Delay is calculated as `0.5 * backoff**retries` seconds; 2 under `slow` when unset, no delay when unset otherwise |
| `-p, --profile slow\|fast` | Speed profile, default `fast`. `slow` fills in `-c 1`, `-m 50`, `-b 2` unless you set them yourself |

**What the profiles and limits actually are** (verified in v2.5.5):

| Setting | `fast` (default) | `slow` |
|---|---|---|
| Concurrent requests (`-c`) | 50 | 1 unless `-c` is set |
| Max retries (`-m`) | 3 unless `-m` is set | 50 unless `-m` is set |
| Backoff (`-b`) | none unless `-b` is set | 2 unless `-b` is set |

## Typical workflows

1. **Recover a schema from a rate-limited target.** `slow` is the profile to
   reach for first on anything not owned by the engagement:

   ```bash
   clairvoyance -p slow -v -o "$WORK/clairvoyance-schema.json" \
     "https://$TARGET/graphql"
   jq '.data.__schema.types | length' "$WORK/clairvoyance-schema.json"
   ```

2. **A fast run against a fixture or a lab host.** The loopback fixture
   convention in this image is port 8090:

   ```bash
   clairvoyance -o "$WORK/schema-fixture.json" "http://127.0.0.1:8090/graphql"
   ```

3. **Authenticated recovery.** Without a credential, most authenticated
   endpoints return nothing to read:

   ```bash
   clairvoyance -H "Authorization: Bearer $TOKEN" \
     -H "Cookie: session=$SESSION" \
     -p slow -o "$WORK/schema-auth.json" "https://$TARGET/graphql"
   ```

4. **Supplement a schema you already have.** Anything in `-i` is not guessed
   again, which shortens the run and reduces traffic:

   ```bash
   clairvoyance -i "$WORK/partial-schema.json" \
     -o "$WORK/schema-plus.json" "https://$TARGET/graphql"
   ```

5. **Bound the retry behaviour on a struggling endpoint.** Fewer retries, and a
   backoff so the retries that happen are spaced:

   ```bash
   clairvoyance -p slow -c 1 -m 10 -b 2 \
     -o "$WORK/schema-gentle.json" "https://$TARGET/graphql"
   ```

6. **A custom name list, validated before use.** `-wv` removes entries the
   GraphQL name grammar will never accept:

   ```bash
   clairvoyance -w "$WORK/field-names.txt" -wv -v \
     -o "$WORK/schema-custom.json" "https://$TARGET/graphql"
   ```

## Output and parsing

The output is a JSON schema document written to the `-o` path. It is written on
every iteration, so the file appears early and grows while the run continues —
do not treat a small file mid-run as the finished schema.

**Pass `-o` explicitly.** The help text says output defaults to stdout, but in
v2.5.5 the schema is written only when `-o` is given; the CLI entry point does
not print it. A run without `-o` therefore produces no schema anywhere.

The recovered schema can be fed to schemathesis, or to a GraphQL client to
inspect and query. Treat a recovered schema as a partial document: it is
assembled from what the endpoint's suggestion errors revealed, so confirm a
field against a live query before relying on it, and never report it as the
vendor's published schema.

Logging goes to stderr, so `jq` on a redirected capture is not polluted by it:

```
INFO  Starting blind introspection on https://$TARGET/graphql...
INFO  Iteration 1
INFO  Blind introspection complete.
```

`-v` (repeatable) raises the logger to `DEBUG`. The environment variables
`LOG_LEVEL`, `LOG_FMT` and `LOG_DATEFMT` override the default level and format.

```bash
# how much did it find?
jq '.data.__schema.types | length' "$WORK/clairvoyance-schema.json"
jq -r '.data.__schema.types[].name' "$WORK/clairvoyance-schema.json" | head
# what it has so far, mid-run
jq -r '.data.__schema.queryType.name' "$WORK/clairvoyance-schema.json"
```

## Chaining with the rest of the toolchain

```bash
# katana finds the endpoint
katana -u "https://$TARGET" -d 3 -jc -kb-endpoints -silent -jsonl -duc \
  -o "$WORK/katana.jsonl"
jq -r '.request.endpoint' "$WORK/katana.jsonl" | grep -i graphql | sort -u

# graphql-cop says whether recovery is needed at all
graphql-cop -t "https://$TARGET/graphql" -o json > "$WORK/graphql-cop.json"
jq -r '.[] | select(.result) | .title' "$WORK/graphql-cop.json"

# recovery, then hand the schema to a fuzzer
clairvoyance -p slow -o "$WORK/schema.json" "https://$TARGET/graphql"
schemathesis --help          # this image's schemathesis takes the schema file
```

- [`graphql-cop`](../graphql-cop/AGENTS.md) runs first: Introspection and Field
  Suggestions are the two results that decide whether clairvoyance is useful.
- The recovered schema is the input for schemathesis (`/opt/venvs/schemathesis`),
  which fuzzes the API against it.
- Nuclei's GraphQL templates (`nuclei -tl -duc | grep -i graphql`) cover
  advisories that neither of the other two tests.

## Limits, failure modes and gotchas

- **Loud by design.** The tool exists to send many requests: every candidate
  name is a query, and iterations walk the schema type by type. The `fast`
  profile uses 50 concurrent requests. Size the run before starting it, and
  expect `slow` to take a long time rather than to be gentle — it is patient,
  not quiet.
- **`--backoff` grows exponentially.** Delay is `0.5 * backoff**retries`
  seconds, so with `-b 2` the later retries are minutes apart. That is the
  intent — a struggling server gets space instead of a loop — but it also means
  a run against a dead endpoint can sit for a long time before finishing.
- **`-m 0` does not disable retries.** The client falls back to its own default
  (3) when the value is unset or zero; set a small positive number instead.
- **Exhausted retries return an empty response, which reads as "no such
  field".** A failing endpoint therefore produces a silently smaller schema
  rather than an error. If a field you expected is missing, check the logs for
  connection or status warnings before concluding it does not exist.
- **5xx responses are retried; other failures log a warning.** A JSON decode
  error also raises the hint that the endpoint may need authentication or is
  rate-limiting you — add `-H` before concluding the schema is empty.
- **`-H` is parsed with a strict `": "` split.** `-H "Authorization:Bearer x"`
  or a header with no colon raises a `ValueError` before the first request.
- **`-w` is de-duplicated into a set**, so ordering is not preserved and
  duplicates collapse. `-wv` reports how many entries it removed as invalid
  GraphQL names.
- **The wordlist applies to every stage** — fields, arguments and nested types —
  so a list of only top-level field names will recover less than the bundled
  list does. Adding names is the way to widen coverage, not replacing the
  bundled list wholesale.
- **`-i` must be valid JSON.** It is parsed with `json.load` before anything
  else happens, so a malformed file stops the run immediately.
- **Without `-o` nothing is written.** See *Output and parsing*.
- **`-k/--no-ssl` disables TLS verification**; a certificate problem is then
  never reported.
- **No field suggestions means no oracle.** If the endpoint answers bad field
  names with a generic error, clairvoyance recovers nothing and exits having
  produced an empty or trivial schema. Confirm by hand with one deliberately
  misspelled field and look for a `Did you mean` style suggestion.

## Safety and scope

Stop and get explicit human confirmation before:

- running against any host not already authorized for this engagement;
- the default `fast` profile against anything shared — it is a load event;
- authenticated recovery (`-H` with a token or cookie), which acts as that user;
- pointing `-x` at anything other than a local interception proxy;
- `-k/--no-ssl` where the certificate itself is part of the finding.

A recovered schema maps internal API surface and is engagement evidence. Keep it
in `$WORK`, out of the repository, and hand it on only as part of the report.
