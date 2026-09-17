# ffuf

A fast web fuzzer. One binary, one keyword (`FUZZ`), and the keyword can be placed
anywhere in a request: path, query value, header, cookie, POST body, or the
virtual-host header. It is the general-purpose fuzzer in this toolchain —
use it for targeted questions ("does this parameter reflect?", "which vhost
answers?"), and feroxbuster for "map the whole tree".

## Installation and location

| Item | Value |
|---|---|
| Version | `ffuf version: 2.3.0` (`ffuf -V`) |
| Binary | `/usr/local/bin/ffuf` |
| Install | upstream Go release tarball (`ffuf_2.3.0_linux_amd64.tar.gz`), static binary, no runtime dependencies |
| Wordlists | `/opt/wordlists/SecLists` (`/opt/wordlists/current` is the same tree by symlink) |
| Runs as | root; no TTY required. `-noninteractive` disables the ENTER-key console |

## Rules that apply to this tool

1. **Authorization first.** Fuzzing is a brute-force attack on someone's
   service. Only run it against targets explicitly confirmed for the current
   engagement. An unclear target is an unauthorized target.
2. **Everything leaves through the VPN.** The agent has one non-loopback
   interface: the WireGuard tunnel in the shared netns. `-x` (proxy) is a
   debugging feature, not containment — do not treat it as one.
3. **Conservative concurrency by default.** The binary defaults to `-t 40`;
   run at `-t 10` and `-rate 20` or lower until the target is known to tolerate
   more. This platform fuzzes Greg's own services; a self-inflicted outage is
   still an outage.
4. **Write evidence to the working directory.** Always `-of json -o
   $WORK/<name>.json`. For an audit trail of every request and response, add
   `-audit-log $WORK/<name>.audit.json`.
5. **Vhost fuzzing is an attack on shared infrastructure.** `-H "Host:
   FUZZ.$TARGET"` sends arbitrary `Host` headers to one IP: a wrong guess can
   land on a different tenant's site behind the same edge. Confirm before
   vhost fuzzing a host you do not own outright.
6. **`-recursion-strategy greedy` multiplies requests.** It queues a fuzzing
   job for every match, including dynamic pages that match on every path.
   Verified: against a fixture that answers `200` to unknown paths, greedy
   recursion produced thousands of URLs from a 13-word list. Prefer the default
   strategy plus a measured filter; never combine greedy with `-recursion-depth 0`.

## Command reference

### Request construction

| Flag | Meaning |
|---|---|
| `-u URL` | Target. `FUZZ` may appear anywhere in the URL; recursion requires the URL to end with it |
| `-w file[:KEYWORD]` | Wordlist and optional keyword (default `FUZZ`). Repeatable; `-w -` reads the wordlist from stdin |
| `-X METHOD` | HTTP method (default `GET`) |
| `-H "Name: Value"` | Header, repeatable. `FUZZ` may be the header value, e.g. `Host: FUZZ.example` or `Cookie: session=FUZZ` |
| `-b "a=b; c=d"` | Cookie header (copy-as-curl form; `-H Cookie:` is the general way) |
| `-d 'a=FUZZ'` | POST body; combine with `-X POST` and a `Content-Type` header |
| `-request file` | Raw HTTP request file (`FUZZ` placed in the request); `-request-proto https\|http` selects the scheme, **default `https`** |
| `-mode clusterbomb\|pitchfork\|sniper` | Multi-wordlist mode when more than one `-w` is given |
| `-e .php,.html` | Extension list appended to every wordlist entry |
| `-enc 'FUZZ:urlencode b64encode'` | Encoders applied to a keyword |
| `-D` | DirSearch wordlist compatibility mode (use with `-e`) |
| `-ic` | Ignore wordlist comment lines |
| `-input-cmd 'cmd'` / `-input-num N` | Generate inputs from a command instead of a wordlist |
| `-http2`, `-raw`, `-ignore-body`, `-sni name` | Transport/response handling |

### Matchers (what to report) and filters (what to drop)

Defaults: `-mc 200-299,301,302,307,401,403,405,500`. Everything else —
including `404` — is silently not reported. If a scan returns nothing, that
default is the first thing to check.

| Matcher | Filter | Meaning |
|---|---|---|
| `-mc codes` | `-fc codes` | Status codes; `all` matches everything |
| `-ms n` | `-fs n` | Response size in bytes (comma lists and ranges) |
| `-mw n` | `-fw n` | Word count |
| `-ml n` | `-fl n` | Line count |
| `-mr regex` | `-fr regex` | Regex on the response body |
| `-mt '>100'` | `-ft '>100'` | Time to first byte, ms |
| `-mmode and\|or`, `-fmode and\|or` | | Combine multiple matchers/filters |

Filter flags are the reliable way to suppress soft-404s once you have measured
the wildcard response: `-fs <size>`, `-fw <words>`, or `-fr <marker>`.

### Autocalibration and pacing

| Flag | Meaning |
|---|---|
| `-ac` | Autocalibrate filters. Implies the `FUZZ` keyword as calibration keyword |
| `-acc "string"` | Custom calibration string (repeatable); implies `-ac` |
| `-ach` | Per-host autocalibration |
| `-ack KEYWORD` | Keyword used for calibration (default `FUZZ`) |
| `-t N` | Concurrent threads (default 40) |
| `-rate N` | Requests per second, process-wide (default 0 = unlimited) |
| `-p 0.1` or `-p 0.1-2.0` | Fixed or random per-request delay in seconds |
| `-timeout N` | Per-request timeout in seconds (default 10) |
| `-maxtime N` / `-maxtime-job N` | Wall-clock cap for the whole run / per job |
| `-sf` / `-se` / `-sa` | Stop on >95% 403s / on spurious errors / both |

### Recursion

| Flag | Meaning |
|---|---|
| `-recursion` | Enable recursion. `-u` **must end with `FUZZ`** |
| `-recursion-depth N` | Maximum depth (default 0 = unlimited) |
| `-recursion-strategy default` | Recurse only into redirect-indicated directories |
| `-recursion-strategy greedy` | Queue a job for every match (see the rule above) |

### Output

| Flag | Meaning |
|---|---|
| `-of json\|ejson\|html\|md\|csv\|ecsv\|all` | Output file format (default `json`) |
| `-o file` | Output file |
| `-od dir` | Directory to store matched response bodies |
| `-or` | Do not create the output file when there are no results |
| `-json` | Newline-delimited JSON on stdout (see the base64 gotcha below) |
| `-audit-log file` | Every request, response and the config |
| `-debug-log file` | Internal debug logging |
| `-s` | Silent (no progress/extra info) |
| `-v` | Verbose: full URL plus redirect location per result |

## Typical workflows

1. **Content discovery with a measured filter.** Fuzz once with `-mc all` to
   find the wildcard size, then re-run with the filter so only real hits remain.

   ```bash
   ffuf -w $WORDLISTS/Discovery/Web-Content/common.txt -u https://$TARGET/FUZZ \
     -mc all -t 10 -rate 20 -s -of json -o $WORK/probe.json
   jq -r '.results[] | [.status,.length,.input.FUZZ] | @tsv' $WORK/probe.json | sort -k2 -n | head
   # a size/status shared by many random hits is the wildcard; filter it:
   ffuf -w $WORDLISTS/Discovery/Web-Content/common.txt -u https://$TARGET/FUZZ \
     -fs 1234 -mc 200,301,302,403 -t 10 -rate 20 -of json -o $WORK/dirs.json
   ```

2. **Virtual-host discovery.** One IP, many names; the interesting vhost has a
   different response size from the default.

   ```bash
   ffuf -w $WORDLISTS/Discovery/DNS/subdomains-top1million-5000.txt \
     -u https://$TARGET/ -H "Host: FUZZ.$TARGET" \
     -mc all -fs 1234 -t 10 -rate 20 -of json -o $WORK/vhosts.json
   ```

3. **POST body / JSON fuzzing.** Same keyword mechanics as paths.

   ```bash
   ffuf -w $WORK/values.txt -u https://$TARGET/api/login -X POST \
     -H 'Content-Type: application/x-www-form-urlencoded' \
     -d 'user=admin&password=FUZZ' -mc all -fc 401 -t 10 -rate 5 \
     -of json -o $WORK/login.json
   ```

4. **Cookie and header fuzzing with a reflection matcher.**

   ```bash
   ffuf -w $WORK/tokens.txt -u https://$TARGET/account \
     -H 'Cookie: session=FUZZ' -mr 'Welcome|dashboard' -t 10 -rate 10
   ffuf -w $WORK/values.txt -u https://$TARGET/ -H 'X-Forwarded-For: FUZZ' -mc all -fs 1234
   ```

5. **Parameter value fuzzing from a crawler's URL list.**

   ```bash
   katana -u https://$TARGET -jc -d 3 -silent \
     | grep '?.' | head -200 > $WORK/param-urls.txt
   ffuf -w $WORK/payloads.txt:FUZZ -u 'https://$TARGET/search?q=FUZZ' \
     -mr 'FUZZ' -t 10 -rate 10 -of json -o $WORK/reflection.json
   ```

## Output and parsing

`-of json -o FILE` writes one object:

```
commandline, config, results, time
```

Each `.results[]` entry has:
`input` (keyword → value, plus `FFUFHASH`), `position`, `status`, `length`,
`words`, `lines`, `content-type`, `redirectlocation`, `url`, `duration`,
`scraper`, `resultfile`, `host`.

```bash
# every real hit, smallest response first
jq -r '.results[] | [.status, .length, .words, .input.FUZZ, .url] | @tsv' $WORK/dirs.json
# only redirects, with their Location
jq -r '.results[] | select(.status==302) | [.url, .redirectlocation] | @tsv' $WORK/dirs.json
# just the URLs, for the next tool
jq -r '.results[].url' $WORK/dirs.json | sort -u > $WORK/found-urls.txt
```

`-json` prints JSONL on stdout, one record per line with the same fields —
**but the input values are base64-encoded**, unlike the `-of json` file:

```bash
ffuf -w words.txt -u https://$TARGET/FUZZ -mc 200 -json -s \
  | jq -r '.input.FUZZ' | while read -r b64; do echo "$b64" | base64 -d; echo; done
# verified: {"input":{"FUZZ":"bG9naW4="}} -> login
```

## Chaining with the rest of the toolchain

```bash
# katana's URL list into targeted parameter fuzzing
katana -u https://$TARGET -jc -d 3 -silent | grep '?' > $WORK/param-urls.txt

# host list into per-host vhost fuzzing
httpx -l $WORK/hosts.txt -silent -ports 80,443 \
  | while read -r u; do
      ffuf -w $WORK/vhosts.txt -u "$u/" -H "Host: FUZZ.$(echo "$u" | awk -F/ '{print $3}')" \
        -mc all -fs 1234 -t 10 -rate 10 -s -of json -o "$WORK/vhosts-$(echo "$u" | tr '/:' '__').json"
    done

# ffuf findings into the vulnerability scanner
jq -r '.results[] | select(.status!=404) | .url' $WORK/dirs.json \
  | httpx -silent -json | jq -r 'select(.status_code==200) | .url' \
  | nuclei -silent -jsonl | jq -c '{t:.info.severity,n:.info.name,u:."matched-at"}'

# feroxbuster can also consume ffuf's URL list and vice versa
jq -r '.results[].url' $WORK/dirs.json | feroxbuster --stdin -q -w $WORDLISTS/Discovery/Web-Content/raft-small-directories.txt
```

## Limits, failure modes and gotchas

- **Silent zero results are usually the matcher, not the target.** The default
  `-mc` list excludes `404`. Re-run with `-mc all` before concluding anything.
- **Soft-404/wildcard servers.** A server that answers `200` (or any status)
  with an identical body for every path makes every wordlist entry "match".
  Verified on such a fixture: `-mc all` returned 13/13 entries, `-ac` returned
  0, `-fs <measured size>` returned 0, `-fr '<body marker>'` returned 0.
  `-ac` works but can over- or under-shoot on heterogeneous targets; measuring
  the wildcard size yourself is more predictable. `-fw` did **not** suppress
  the same fixture (word counts varied), so verify the filter you chose.
- **Autocalibration on a normal server did not over-filter** (verified: `-ac`
  returned the same 8 genuine results that `-fc 404` returned), but a
  wildcard-plus-real-content target is where `-ac`'s choices matter. Check the
  calibration summary ffuf prints (`-v`) or cross-check with `-mc all`.
- **Recursion needs the keyword at the end of `-u`.** Verified error:
  `When using -recursion the URL (-u) must end with FUZZ keyword.`
- **The default recursion strategy rarely descends.** It is redirect-based; a
  directory that merely returns `200` is not followed. Verified with a wordlist
  of `admin/` and `index.html`: default strategy reported only the two root
  matches, while greedy queued
  `Adding a new job to the queue: http://…/admin//FUZZ …` (note the double
  slash when the match already ends in `/`) and `…/index.html/FUZZ`.
- **Greedy recursion is unbounded.** Verified: on a fixture that returns `200`
  for any path it generated a URL tree thousands of entries deep from 13 words.
  Always set `-recursion-depth` and filters with greedy.
- **`-e` appends to every entry unconditionally.** Verified with `-e .html`:
  `index.html` became `index.html.html`, and `admin/` became `admin/.html`.
  Curate a dedicated wordlist instead of extending a mixed one.
- **`-json` base64-encodes input values; the `-of json` file does not.**
  Parsers that work on one break on the other.
- **`-request` defaults to HTTPS.** A raw request for an HTTP target needs
  `-request-proto http`, or ffuf fails to connect.
- **Exit code is not a success signal.** Verified: a missing wordlist
  (`stat /nonexistent.txt: no such file or directory`) and a run that matched
  nothing both exited `0`. Parse the JSON, do not test `$?`.
- **No retry/backoff.** ffuf does not honour `Retry-After` or retry `429`s.
  `-rate`/`-p` are the only brakes; `-sf`/`-se`/`-sa` only stop the run.
- **Output file is created even when empty** unless `-or` is given.
- **Interactive console.** Without `-noninteractive`, ffuf polls for ENTER and
  prints a menu on a TTY; in pipelines use `-s`/`-noninteractive` so nothing
  waits on input.

## Safety and scope

Stop and get explicit human confirmation before:

- fuzzing any host not already authorized for this engagement;
- vhost fuzzing (`Host: FUZZ.…`) a host that shares an IP with other tenants;
- `-recursion-strategy greedy`, `-recursion-depth 0`, or `-t` above 10 on a
  production service;
- fuzzing authenticated endpoints, login forms, or anything that writes state
  (`POST`/`PUT`/`DELETE` bodies), which can create accounts, lock accounts, or
  corrupt data;
- raising `-rate` above the agreed budget for the engagement.

Read-only is not a synonym for harmless: every fuzzing request is logged by the
target, and a wrong vhost or a `POST` body can change its state.
