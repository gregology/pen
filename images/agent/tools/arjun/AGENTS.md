# arjun — HTTP parameter discovery

arjun takes a URL and a list of candidate parameter *names*, sends them in
batched requests, and reports the names whose presence changes the response. It
finds query, body and JSON parameters a crawler cannot see. Reach for it after
you have live endpoints and before you attack them: dalfox, sqlmap, commix and
ffuf all need to know *which* parameter to attack. It is not content discovery
(that is gobuster/feroxbuster/ffuf) and not fingerprinting (whatweb/wafw00f).

## Install and location

| | |
|---|---|
| Version | 2.2.7 (PyPI release, pinned in `install.sh`) |
| Entry point | `/usr/local/bin/arjun` → `/opt/venvs/arjun/bin/arjun` |
| Venv | `/opt/venvs/arjun` |
| Wordlists | bundled in the package: `.../arjun/db/large.txt` (default, 25,890 names), `medium.txt`, `small.txt`, `special.json` |

Its own venv, so nothing it depends on can conflict with another Python tool.
To use arjun as a library: `/opt/venvs/arjun/bin/python3`.

## Flags that matter

| Flag | What it does |
|---|---|
| `-u URL` | Target URL. Required unless `-i` is used. |
| `-i FILE` | Import targets from a file. The **first line** selects the format: `http://`/`https://` → URL list; `GET`/`POST` → one raw HTTP request; `<?xml` → Burp Suite XML export. Any other first line imports zero targets. |
| `-m GET\|POST\|XML\|JSON` | Request method, default `GET`. Any non-GET method forces the chunk size to 500. |
| `-w FILE\|large\|medium\|small` | Parameter-name wordlist. Default `db/large.txt`. |
| `-t N` | Concurrent threads, default 5. |
| `-d SECONDS` | Delay between requests, float, default 0. Setting it forces `-t 1`. |
| `-c N` | Chunk size — parameter names per request, default 250. |
| `-T SECONDS` | Per-request timeout, default 15. |
| `--rate-limit N` | Requests per second, default 9999. |
| `-o FILE`, `-oJ FILE` | JSON report; both spellings are the same option. |
| `-oT FILE` | Text report, one URL-with-parameter per line. Opened in **append** mode. |
| `-oB [host:port]` | Replay every discovered request through a Burp proxy, default `127.0.0.1:8080`. |
| `--headers 'A: b'` | Extra request headers, newline-separated inside the argument. Never pass it with no value — that forks `nano`. |
| `--include x=y` | Data added to every request (for `-m JSON`, the literal `$arjun$` is replaced by the generated JSON object). |
| `--passive [host]` | Add parameter names harvested from Wayback, Common Crawl and OTX. Discloses the target's domain to third parties. |
| `--casing STYLE` | Rewrite wordlist casing: `like_this`, `likeThis`, `likethis`. |
| `--stable` | Random 3–9 s delay and one thread. |
| `--disable-redirects` | Parsed, but redundant: every request already sets `allow_redirects=False`. |
| `-q` | Suppress all output, including the findings summary. |
| `-h` | Help. There is no `--version`; argparse rejects it. |

## Examples

### GET discovery on one endpoint

```bash
arjun -u "https://target.example/api/v1/users" -t 3 --rate-limit 10 \
  -oJ $WORK/arjun-users.json -oT $WORK/arjun-users.txt
jq -r 'to_entries[] | "\(.key)\t\(.value.params | join(","))"' $WORK/arjun-users.json
```

Expect `[+] parameter detected: debug, based on: body length` followed by
`[+] Parameters found: debug`. "No parameters were discovered." is the honest
empty result — but it is also what a target that rejects everything looks like,
so check for the `[!] Target returned HTTP 4xx` warning above it before
recording a negative.

### POST form and JSON body discovery

```bash
arjun -u "https://target.example/api/login" -m POST -t 3 --rate-limit 10 -oJ $WORK/arjun-post.json
arjun -u "https://target.example/api/login" -m JSON -t 3 --rate-limit 10 -oJ $WORK/arjun-json.json
```

`POST` sends `application/x-www-form-urlencoded`; `JSON` sends a JSON object and
sets `Content-Type: application/json`. Every invented name is sent as a real
request body — against an endpoint that writes data this is a mutation, not a
probe.

### Endpoint list from a crawler

```bash
katana -u https://target.example -jc -d 3 -silent | grep '?' | sort -u > $WORK/param-urls.txt
arjun -i $WORK/param-urls.txt -m GET -t 3 --rate-limit 10 -oJ $WORK/arjun-all.json
```

Write the file deliberately: if its first line is not a URL, `GET`/`POST` or
`<?xml`, arjun imports nothing and exits 0 with no output at all.

### Authenticated discovery

```bash
arjun -u "https://target.example/account" -m GET \
  --headers "Cookie: session=$TOKEN
Authorization: Bearer $TOKEN" -t 3 --rate-limit 10 -oJ $WORK/arjun-auth.json
```

Headers are one argument, one per line inside the quotes. Omitting the value
(`--headers` alone) opens an editor and hangs in a non-interactive shell.

### Hand the discovered parameters to the injection tools

```bash
jq -r 'to_entries[] | .key as $u | .value.params[] | "\($u)?\(.)=FUZZ"' $WORK/arjun-all.json \
  > $WORK/fuzz-targets.txt
ffuf -w /opt/wordlists/current/Discovery/Web-Content/common.txt:FUZZ \
  -u "$(head -1 $WORK/fuzz-targets.txt)" -t 5 -rate 10
jq -r '.["https://target.example/item"].params[]' $WORK/arjun-all.json \
  | while read -r p; do sqlmap -u "https://target.example/item?$p=1" --batch --smart; done
```

## Output formats

`-o`/`-oJ FILE` writes one JSON object keyed by target URL; each value has
`params` (discovered names), `method` and `headers` (the headers arjun sent).
Written with `json.dump(..., sort_keys=True, indent=4)` and overwritten on each
export.

```bash
jq -r 'to_entries[] | .key as $u | .value.params[] | "\($u)\t\(.)"' $WORK/arjun.json   # url<TAB>param
jq -r '[to_entries[].value.params | length] | add' $WORK/arjun.json                    # total hits, null if empty
```

`-oT FILE` is plain text, appended (mode `a+`) — rerunning the same command
duplicates lines. GET lines are `url?name=randomvalue`; POST lines are
`url<TAB>query`; JSON lines are `url<TAB>{json}`.

There is no XML or CSV output. `-oB` re-issues the discovered requests through
Burp instead of writing a file.

## Failure modes

- **Exit code 0 on every completed scan**, found or not. Argument errors exit
  non-zero; a scan that reached nothing still exits 0. Never branch on `$?` —
  parse the JSON.
- **A bad `-i` file silently does nothing.** The importer returns an empty
  target list when the first line is not a URL, `GET`/`POST` or `<?xml`; arjun
  loops over zero targets and exits 0.
- **No stdin support.** `cat urls.txt | arjun` prints `[-] No target(s)
  specified`. Targets come from `-u` or `-i` only.
- **`--headers` with no value forks `nano`.** In a shell without a TTY it fails
  or hangs; always pass the header string as the argument.
- **TLS verification is disabled** (`verify=False`) and redirects are not
  followed. A 301 to the real endpoint looks like a dead end.
- **Dynamic pages produce false positives.** Detection is "did the response
  change"; timestamps, ads and CSRF tokens change on their own. `--stable`
  reduces this at a large time cost; confirm every hit by hand before reporting
  it.
- **Rate-limit rejections degrade silently.** If the target answers
  400/413/418/429/503 the run prints `[!] Target returned HTTP <code>, this may
  cause problems.` and keeps going with unreliable comparisons.
- **`-q` suppresses everything,** including `[+] Parameters found:` — fine when
  the JSON file is the output, useless when a human is reading.
- **`-oT` appends.** Repeated runs produce duplicated lines in the same file.

## Notes

- **Request volume.** The default `large.txt` has 25,890 names; chunking
  (`-c 250`) keeps the request count to dozens per endpoint, but a URL list of a
  few hundred endpoints is tens of thousands of requests. Start with `-t 3
  --rate-limit 10` and raise only with a reason.
- The `--rate-limit` cap is per process and applies globally to all threads, so
  it is the reliable throttle; `-d` adds a fixed sleep per request and drops you
  to one thread.
- **arjun also re-tests names it extracts from the response** (its `heuristic`
  pass adds parameter names found in the page/JS to the candidate list). A
  reported name may be one the application already used, not a discovery — say
  which in the findings note.
- **Wordlists.** `-w /opt/wordlists/current/Discovery/Web-Content/burp-parameter-names.txt`
  is the useful override when you want Burp's parameter list instead of
  arjun's.
- **`-oB` needs a Burp on `127.0.0.1:8080`.** With nothing listening, the export
  throws connection errors that look like target failures. In this container
  something *is* listening there — the VPN gateway's control API — so pass an
  explicit `host:port` for your own proxy rather than accepting the default.

## Safety

Requires explicit human confirmation before running:

- any target not already confirmed for this engagement;
- `--passive`, which queries Wayback/Common Crawl/OTX with the target's domain —
  an egress decision, not a scanning option;
- `-m POST`/`JSON` against endpoints that write data;
- the default `large.txt` against a production service without a rate limit.
