# arjun

HTTP parameter discovery. It takes a URL, throws a wordlist of parameter names
at it in chunks, and reports the names that change the response — the hidden
query, body and JSON parameters a crawler cannot see and a plain wordlist fuzz
would have to guess one at a time. Its output is the input to dalfox, sqlmap,
ffuf and any injection tool that needs to know *which* parameter to attack.

## Installation and location

| Item | Value |
|---|---|
| Version | `arjun 2.2.7` — no `--version` flag; read it from `pip show arjun` or the banner |
| Entry point | `/opt/pen-venv/bin/arjun` (Python virtualenv `/opt/pen-venv`) |
| Install | upstream source, `pip install arjun` into the venv at image build |
| Package dir | `/opt/pen-venv/lib/python3.11/site-packages/arjun/` |
| Bundled wordlists | `/opt/pen-venv/lib/python3.11/site-packages/arjun/db/large.txt` (153 KB), `medium.txt`, `small.txt`, `special.json`; the default is `large.txt` |
| Runs as | root; no TTY required |

## Rules that apply to this tool

1. **Authorization first.** arjun sends thousands of requests with invented
   parameter names. Only against explicitly confirmed targets.
2. **Everything leaves through the VPN.** One non-loopback interface: the
   WireGuard tunnel in the shared netns. `-oB` (Burp output) is for local
   interception, not containment.
3. **Cap the rate yourself.** The defaults are `-t 5` and `--rate-limit 9999`;
   the chunking makes the request count large even with few threads. Start at
   `-t 3 --rate-limit 10` and watch the target's response times.
4. **Never run `--passive` without a scope decision.** It does not talk to the
   target: it queries third-party sources (Wayback Machine, Common Crawl, OTX)
   with the target's domain. That is an egress and information-disclosure
   decision, not a scanning option.
5. **Save evidence to the working directory.** `-oJ $WORK/arjun.json` (machine
   readable) and `-oT $WORK/arjun.txt` (URLs with an example parameter) both.

## Command reference

| Flag | Meaning |
|---|---|
| `-u URL` | Target URL |
| `-i [FILE]` | Import target URLs from a file, one per line |
| `-m METHOD` | `GET` (default), `POST`, `XML`, `JSON` |
| `-w FILE` | Wordlist of parameter names (default `{arjundir}/db/large.txt`) |
| `-t N` | Concurrent threads (default 5) |
| `-d N` | Delay between requests, **seconds** (default 0) |
| `--rate-limit N` | Maximum requests per second (default 9999) |
| `-c N` | Chunk size: how many parameter names are sent per request |
| `-T N` | HTTP request timeout in seconds (default 15) |
| `-o, -oJ FILE` | JSON output file (both spellings work) |
| `-oT FILE` | Text output file |
| `-oB [host:port]` | Send the discovered requests to Burp Suite (default `127.0.0.1:8080`) |
| `--headers 'A: b'` | Extra headers, separated by newlines |
| `--include 'x=y'` | Data to include in every request |
| `--passive [SOURCES]` | Parameter names from third-party sources (wayback, commoncrawl, otx) |
| `--stable` | Prefer stability over speed |
| `--disable-redirects` | Do not follow redirects |
| `--casing STYLE` | Parameter-name casing: `like_this`, `likeThis`, `likethis` |
| `-q` | Quiet: no output at all (not even the findings summary) |
| `-h` | Help. **There is no `--version`** (verified: `unrecognized arguments: --version`) |

## Typical workflows

1. **GET parameter discovery on one endpoint.**

   ```bash
   arjun -u "https://$TARGET/api/v1/users" -m GET -t 3 --rate-limit 10 \
     -oJ $WORK/arjun-users.json -oT $WORK/arjun-users.txt
   jq -r 'to_entries[] | .key as $u | .value.params[] | "\($u)\t\(.)"' $WORK/arjun-users.json
   ```

2. **POST form and JSON body discovery.**

   ```bash
   arjun -u "https://$TARGET/api/login" -m POST -t 3 --rate-limit 10 -oJ $WORK/arjun-post.json
   arjun -u "https://$TARGET/api/login" -m JSON -t 3 --rate-limit 10 -oJ $WORK/arjun-json.json
   ```

3. **A list of endpoints from a crawler.**

   ```bash
   katana -u https://$TARGET -jc -d 3 -silent | grep '?' | sort -u > $WORK/param-urls.txt
   arjun -i $WORK/param-urls.txt -m GET -t 3 --rate-limit 10 -oJ $WORK/arjun-all.json
   ```

4. **Authenticated discovery with a session cookie or token.**

   ```bash
   arjun -u "https://$TARGET/account" -m GET \
     --headers "Cookie: session=$TOKEN
   Authorization: Bearer $TOKEN" -t 3 --rate-limit 10 -oJ $WORK/arjun-auth.json
   ```

5. **Hand the discovered parameters to the injection tools.**

   ```bash
   jq -r 'to_entries[] | .key as $u | .value.params[] | "\($u)?\(.)=FUZZ"' $WORK/arjun-all.json \
     > $WORK/fuzz-targets.txt
   ffuf -w $WORK/payloads.txt:FUZZ -u "$(head -1 $WORK/fuzz-targets.txt)" -t 10 -rate 10
   dalfox scan -i file $WORK/fuzz-targets.txt --workers 2 --delay 100 -f json -o $WORK/dalfox.json < /dev/null
   ```

## Output and parsing

`-oJ FILE` writes one JSON object keyed by the target URL. Each value has
`headers` (the headers arjun sent), `method`, and `params` (the discovered
names). Verified output:

```json
{
    "http://127.0.0.1:8090/api/v1/users": {
        "headers": {
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            "Accept-Encoding": "gzip, deflate",
            "Accept-Language": "en-US,en;q=0.5",
            "Connection": "close",
            "Upgrade-Insecure-Requests": "1",
            "User-Agent": "Mozilla/5.0 (X11; Linux x86_64; rv:83.0) Gecko/20100101 Firefox/83.0"
        },
        "method": "GET",
        "params": ["debug"]
    }
}
```

```bash
# every discovered parameter, one per line, with its URL
jq -r 'to_entries[] | .key as $u | .value.params[] | "\($u)\t\(.)"' $WORK/arjun.json
# just the names for one target
jq -r '.["https://target.example/api"].params[]' $WORK/arjun.json
# did arjun find anything at all?
jq -r '[to_entries[].value.params | length] | add' $WORK/arjun.json
```

`-oT FILE` writes plain URLs with an example value (verified:
`http://127.0.0.1:8090/api/v1/users?debug=8769`) — convenient as a target list,
but it contains a random value, not a real one.

The terminal output names the evidence for each hit, which matters when you
report it:

```
[✓] parameter detected: debug, based on: body length
[+] Parameters found: debug
```

## Chaining with the rest of the toolchain

```bash
# katana / feroxbuster / ffuf produce the URL list, arjun finds the parameters
katana -u https://$TARGET -jc -d 3 -silent | grep '?' | sort -u > $WORK/urls.txt
arjun -i $WORK/urls.txt -m GET -t 3 --rate-limit 10 -oJ $WORK/arjun.json

# parameters -> dalfox (XSS) and ffuf (targeted fuzzing)
jq -r 'to_entries[] | .key as $u | .value.params[] | "\($u)?\(.)=test"' $WORK/arjun.json > $WORK/with-params.txt
dalfox scan -i file $WORK/with-params.txt --workers 2 --delay 100 -f jsonl -o $WORK/dalfox.jsonl < /dev/null

# parameters -> sqlmap (already in the image)
jq -r '.["https://target.example/item"].params[]' $WORK/arjun.json \
  | while read -r p; do sqlmap -u "https://target.example/item?$p=1" --batch --smart; done

# arjun + httpx: only scan endpoints that are alive and interesting
httpx -l $WORK/urls.txt -silent -mc 200 -json | jq -r '.url' > $WORK/live.txt
arjun -i $WORK/live.txt -t 3 --rate-limit 10 -oJ $WORK/arjun-live.json
```

## Limits, failure modes and gotchas

- **No `--version` flag.** Verified: `arjun: error: unrecognized arguments:
  --version`. Get the version from the banner, `pip show arjun`, or the
  `arjun-2.2.7.dist-info` directory.
- **No stdin support.** Verified: piping a URL into arjun prints
  `[-] No target(s) specified`. Targets come from `-u` or `-i FILE` only.
- **Exit code is always 0.** Verified: a scan that found no parameters exited
  `0`, and a scan against a closed port exited `0`. Never branch on `$?`; parse
  the `-oJ` file, and treat an empty `params` array as "nothing found".
- **`-q` prints nothing at all** — not just less. Verified: the findings summary
  (`[+] Parameters found: …`) disappears too. Keep `-q` for scripted runs where
  the JSON file is the output; drop it when a human is reading along.
- **Progress output is carriage-return heavy and hard to read in logs.**
  `Processing chunks: 1/2\rProcessing chunks: 2/2…` overwrites itself on a TTY
  and becomes one long line in a file. Redirect stderr, or use `-q`.
- **The default wordlist is large.** `large.txt` is ~15k names; chunking (`-c`)
  sends many per request, but the request count is still in the hundreds or
  thousands per endpoint. Use `-w` with a short list for a first pass and
  `--rate-limit`/`-d` to stay inside the engagement's budget.
- **Detection is heuristic.** arjun reports a parameter when the response's
  body length or status code changes. Dynamic pages (ads, timestamps, random
  content) produce false positives; `--stable` trades speed for a lower
  false-positive rate, and a reported parameter should be confirmed by hand
  before it becomes a finding.
- **It also re-tests parameters already in the URL.** Verified on
  `/search?q=test`: arjun reported `q` from the target URL itself. That is
  useful context, not a discovery — separate "already known" from "newly
  discovered" in the report.
- **`--passive` is a third-party query.** It sends the target's domain to
  Wayback/Common Crawl/OTX. It is not part of a normal scan and needs explicit
  authorization.
- **`-oB` proxies the discovered requests to Burp** at `127.0.0.1:8080` by
  default. A missing Burp on that port produces connection errors that look like
  target failures.

## Safety and scope

Stop and get explicit human confirmation before:

- running arjun against any host not already authorized for this engagement;
- `--passive`, which discloses the target's domain to third-party services;
- authenticated discovery (`--headers "Cookie: …"`, bearer tokens), which acts
  as that user;
- `-m POST`/`JSON`/`XML` against endpoints that write data — parameter names
  invented by arjun are still sent as real request bodies;
- using the default `large.txt` against a production service without a rate
  limit, since that is the largest request volume in this toolchain after
  feroxbuster's recursion.
