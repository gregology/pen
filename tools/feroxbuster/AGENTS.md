# feroxbuster

Recursive content discovery. Point it at one URL (or a list) with a wordlist and
it walks the tree by itself: it scans a directory, recognises subdirectories,
queues them, and repeats to a configurable depth. It is the "map the whole
thing" tool in this toolchain — use ffuf when you need a keyword placed
somewhere specific.

## Installation and location

| Item | Value |
|---|---|
| Version | `feroxbuster 2.13.1` (`feroxbuster --version`) |
| Binary | `/usr/local/bin/feroxbuster` |
| Install | upstream release (`x86_64-linux-feroxbuster.zip`), static Rust binary |
| Wordlists | `/opt/wordlists/SecLists` (`/opt/wordlists/current` by symlink) |
| Config file | none in this image: `/etc/feroxbuster/` does not exist, so there is no default wordlist or default settings |
| Runs as | root; no TTY required |

## Rules that apply to this tool

1. **Authorization first.** Recursive discovery generates the largest request
   volume of anything in this toolchain. Only run it against targets explicitly
   confirmed for the current engagement.
2. **Everything leaves through the VPN.** One non-loopback interface: the
   WireGuard tunnel in the shared netns. `-p/--proxy` is for replaying through
   Burp or similar, not containment.
3. **Always pass `-w`.** Without it feroxbuster looks for
   `/usr/share/seclists/Discovery/Web-Content/raft-medium-directories.txt`,
   which **does not exist in this image**; the run ends with
   `Could not open …` and no results.
4. **Conservative concurrency by default.** The binary defaults to `-t 50`
   with no rate limit. Use `-t 10 --rate-limit 20` until the target is known to
   tolerate more, and `--time-limit` as a backstop.
5. **Write evidence to the working directory.** `--json -o $WORK/<name>.jsonl`
   gives one machine-readable record per response plus a statistics record.
6. **Recursion is unbounded in the worst case.** `-d 0` means infinite depth
   and `--force-recursion` queues every discovered endpoint. On a site whose
   URLs nest arbitrarily (or one that links to itself) this is a request
   amplifier. Cap `-d`, and set `--time-limit` or `-L/--scan-limit`.

## Command reference

### Target selection

| Flag | Meaning |
|---|---|
| `-u, --url URL` | Single target (required unless `--stdin`, `--resume-from` or `--request-file`) |
| `--stdin` | Read target URLs from stdin (one per line) |
| `--parallel N` | Run N child processes, one per stdin URL |
| `--resume-from FILE` | Resume a partially complete scan from a `*.state` file |
| `--request-file FILE` | Raw HTTP request to use as a template for all requests |
| `--protocol http\|https` | Scheme for `--request-file`/bare-domain targets (default `https`) |

### Request construction

| Flag | Meaning |
|---|---|
| `-w, --wordlist FILE` | Wordlist path or URL (**required in this image**) |
| `-x, --extensions php,js` | Extensions to search for; `@file` reads them from a file |
| `-m, --methods GET,POST` | HTTP methods (default `GET`) |
| `-H, --headers 'Name: v'` | Headers, repeatable |
| `-b, --cookies 'a=b'` | Cookies |
| `-Q, --query 'token=x'` | Query parameters appended to every request |
| `--data 'a=b'`, `--data-json '{...}'`, `--data-urlencoded 'a=b'` | Bodies; the composite forms also set the content type and method `POST` |
| `-a, --user-agent UA`, `-A, --random-agent` | User agent (default `feroxbuster/2.13.1`) |
| `-f, --add-slash` | Append `/` to each request URL |

### Recursion and collection

| Flag | Meaning |
|---|---|
| `-d, --depth N` | Maximum recursion depth (default 4; `0` = infinite) |
| `-n, --no-recursion` | Single directory only |
| `--force-recursion` | Recurse into *all* discovered endpoints, not just the ones it selected |
| `--extract-links` (default on) / `--dont-extract-links` | Extract links from response bodies and scan them |
| `-E, --collect-extensions` | Learn extensions from responses and add them |
| `-g, --collect-words` | Learn words from responses and add them to the wordlist |
| `-B, --collect-backups` | Request likely backup extensions for found URLs |
| `--scan-dir-listings` | Recurse into directory listings |
| `--smart`, `--thorough` | Presets: `--auto-tune --collect-words --collect-backups` (+ extensions and dir listings for `--thorough`) |
| `-L, --scan-limit N` | Maximum concurrent directory scans |
| `--dont-scan PATTERN`, `--scope URL` | Exclude / include URLs and regexes |

### Filters

| Flag | Meaning |
|---|---|
| `-C, --filter-status 404 500` | Status codes to drop |
| `-S, --filter-size N` | Response sizes to drop |
| `-W, --filter-words N` | Word counts to drop |
| `-N, --filter-lines N` | Line counts to drop |
| `-X, --filter-regex 'pattern'` | Body/header regex to drop |
| `--filter-similar-to URL` | Drop pages similar to this one (the soft-404 page) |
| `--unique` | Only unique responses |
| `-s, --status-codes 200 301` | Allow list (default: all) |
| `-D, --dont-filter` | **Disable the automatic wildcard filter** (see gotchas) |

### Pacing and output

| Flag | Meaning |
|---|---|
| `-t, --threads N` | Concurrent threads (default 50) |
| `--rate-limit N` | Requests per second **per directory** (default 0 = unlimited) |
| `--time-limit 10m` | Wall-clock cap for all scans |
| `--timeout N` | Per-request timeout in seconds (default 7) |
| `--auto-tune` | Lower the scan rate when errors pile up |
| `--auto-bail` | Stop when errors pile up |
| `-r, --redirects` | Follow redirects |
| `-k, --insecure` | Do not validate TLS certificates |
| `--json` | Emit JSON records to `--output`/`--debug-log` |
| `-o, --output FILE` | Output file |
| `--silent` | Only print URLs (or JSON with `--json`); implies no logging |
| `-q, --quiet` | Hide the banner and progress bars. **Conflicts with `--silent`** |
| `-v, -vv, -vvv` | Increase verbosity |
| `--no-state` | Do not write a `*.state` file |
| `-U, --update` | Self-update — never use inside the container |

## Typical workflows

1. **Map one host against a SecLists directory list, JSON evidence.**

   ```bash
   feroxbuster -u https://$TARGET -w $WORDLISTS/Discovery/Web-Content/raft-medium-directories.txt \
     -t 10 --rate-limit 20 -d 3 -x php,html,js \
     --json -o $WORK/ferox.jsonl --time-limit 20m
   jq -r 'select(.type=="response") | [.status, .content_length, .url] | @tsv' $WORK/ferox.jsonl | sort -k1,1n
   ```

2. **Pipeline mode: many hosts, clean URL output.**

   ```bash
   httpx -l $WORK/live-hosts.txt -silent > $WORK/urls.txt
   feroxbuster --stdin --parallel 3 -w $WORDLISTS/Discovery/Web-Content/common.txt \
     -t 10 --rate-limit 10 -d 2 --silent --no-state \
     < $WORK/urls.txt | grep -v '^$' | sort -u > $WORK/found-urls.txt
   ```

3. **Soft-404 target: measure the wildcard page, then filter it.**

   ```bash
   curl -s -o /dev/null -w '%{http_code} %{size_download}\n' "https://$TARGET/$(openssl rand -hex 8)"
   feroxbuster -u https://$TARGET -w $WORDLISTS/Discovery/Web-Content/common.txt \
     -t 10 --filter-similar-to "https://$TARGET/definitely-not-a-page" \
     --json -o $WORK/ferox.jsonl
   ```

4. **Resume an interrupted long scan.** Send `SIGINT` (Ctrl-C) once; the state
   file name is printed and written to the current directory as
   `ferox-<host>-<epoch>.state`, then:

   ```bash
   feroxbuster --resume-from $WORK/ferox-https_example_com-1789677870.state -q
   ```

5. **Filter noise from an authenticated area.**

   ```bash
   feroxbuster -u https://$TARGET -w $WORDLISTS/Discovery/Web-Content/raft-small-words.txt \
     -H "Authorization: Bearer $TOKEN" -C 401 403 -S 0 -d 2 -t 10 --rate-limit 10
   ```

## Output and parsing

`--json -o FILE` writes JSONL. Three record types, in order:

- `configuration` — the effective settings (echo them into the report: it is
  the proof of what was run);
- `response` — one per reported response;
- `statistics` — totals at the end of the scan.

`response` fields (verified):
`url, original_url, path, wildcard, status, method, content_length, line_count,
word_count, headers, extension, truncated, timestamp`.

`statistics` fields (verified):
`timeouts, requests, expected_per_scan, total_expected, errors, successes,
redirects, client_errors, server_errors, total_scans, initial_targets,
links_extracted, extensions_collected, status_200s, status_301s, status_302s,
status_401s, status_403s, status_429s, status_500s, status_503s, status_504s,
status_508s, wildcards_filtered, responses_filtered, resources_discovered,
url_format_errors, redirection_errors, connection_errors, request_errors,
certificate_errors, directory_scan_times, total_runtime, targets`.

```bash
# live URLs only
jq -r 'select(.type=="response" and .status==200) | .url' $WORK/ferox.jsonl | sort -u
# what the wildcard filter removed, and whether the target rate-limited us
jq -c 'select(.type=="statistics") | {requests, status_429s, wildcards_filtered, responses_filtered, errors, total_runtime}' $WORK/ferox.jsonl
# exactly which settings produced this evidence
jq -c 'select(.type=="configuration") | {wordlist, threads, depth, rate_limit, extract_links, dont_filter, user_agent, time_limit}' $WORK/ferox.jsonl
```

`--silent` prints bare URLs (for piping) but also emits blank lines between
results: verified with `cat -A`, each URL line is followed by an empty line.
Strip them with `grep -v '^$'` before using the file. `--silent --json` prints
the JSONL records on stdout instead, which is the cleanest pipeline form.

## Chaining with the rest of the toolchain

```bash
# crawl then recurse: katana finds routes the wordlist never will
katana -u https://$TARGET -jc -d 3 -silent > $WORK/katana-urls.txt
feroxbuster --stdin -w $WORDLISTS/Discovery/Web-Content/raft-small-directories.txt \
  -t 10 --rate-limit 10 -d 2 --silent --no-state \
  < $WORK/katana-urls.txt | grep -v '^$' | sort -u > $WORK/tree.txt

# discovered URLs into the vulnerability scanner
jq -r 'select(.type=="response" and .status==200) | .url' $WORK/ferox.jsonl \
  | httpx -silent -mc 200 -json | jq -r '.url' \
  | nuclei -silent -jsonl | jq -c '{t:.info.severity,n:.info.name,u:."matched-at"}'

# hand a discovered endpoint to ffuf for parameter work
jq -r 'select(.type=="response" and (.url|test("\\?"))) | .url' $WORK/ferox.jsonl \
  | head -50 > $WORK/param-urls.txt

# feroxbuster's own wordlist can come from someone else's results
jq -r '.results[].input.FUZZ' $WORK/ffuf-dirs.json | sort -u > $WORK/ffuf-words.txt
feroxbuster -u https://$TARGET -w $WORK/ffuf-words.txt -d 1 -t 10 --rate-limit 10
```

## Limits, failure modes and gotchas

- **The automatic wildcard filter is on by default and it hides results.**
  Verified on a soft-404 fixture: the default run reported 0 URLs while
  `-D/--dont-filter` reported 45. On a normal fixture the default run reported
  11 URLs with `responses_filtered: 9` in `statistics` and omitted endpoints
  that exist (`/admin/index.html`; `curl` returns 200 for it). With `-D` all 18
  responses appeared — including 404 noise like `/api`, `/panel`, `/deep.html` —
  but recursion still did not produce `/admin/index.html`.
- **`-D --force-recursion` without a filter is a recursion bomb.** Verified on
  the same fixture: 30,387 requests and 25,761 discovered resources, because
  with filtering off, `--force-recursion` descends into 404 endpoints as if they
  were directories. The bounded form that both recurses and stays sane is
  `-D --force-recursion --filter-similar-to <URL that returns your 404 page>`
  (verified: 179 requests, 10 responses, and `/admin/index.html` present). Use
  that shape and read `wildcards_filtered`/`responses_filtered` from the
  `statistics` record afterwards.
- **`-q` and `--silent` are mutually exclusive.** Verified: `error: the
  argument '--quiet' cannot be used with '--silent'`, exit code 2. Pick one.
- **`-o` without `--json` is not a results file.** It writes the
  `Configuration { … }` debug dump (290 lines in the verification run). Always
  pair `-o` with `--json`.
- **State files are written on `SIGINT`, not on `SIGTERM`.** Verified: `kill
  -INT` produced `ferox-http_127_0_0_1_8090_-1789677870.state`; a `SIGTERM`
  timeout left none. State is `{"scans":[…]}` and `--resume-from` picks up
  `NotStarted`/`Running` scans. `--no-state` suppresses the file entirely.
- **No default wordlist exists in this image.** Without `-w` the run dies on
  `/usr/share/seclists/...`. There is also no `/etc/feroxbuster/ferox-config.toml`.
- **Exit codes carry meaning:** `0` normal, `1` when `--time-limit` cut the run
  short, `2` on CLI/config errors. A `1` is not a successful complete scan.
- **`--rate-limit` is per directory, not global.** Verified on a 4750-word
  list: unlimited took 20.4 s; `--rate-limit 50` took 95.5 s. With recursion
  each directory gets its own budget, so total request rate is
  `threads × directories × rate-limit` unless `-L/--scan-limit` bounds the
  concurrency.
- **Recursion depth counts directories, not URLs.** Default `-d 4`; `-d 0` is
  infinite. Depth 1 scans the root only. A tree that is deeper than `-d` is
  silently truncated — that is a false negative, not a clean result.
- **`--extract-links` changes what recursion does.** With extraction on (the
  default), feroxbuster follows links it finds in bodies and may not descend
  into every wordlist-discovered directory; `--force-recursion` restores the
  "scan everything found" behaviour. Pick deliberately and record which you used.
- **`--parallel` spawns child processes that each honour the flags.** Total
  load multiplies by N.
- **`--update` exists and must not be used.** Tool versions are pinned by the
  image build; updating in place breaks reproducibility.
- **Response bodies are capped at 4 MB** (`--response-size-limit`) and large
  bodies are reported with `truncated: true`.

## Safety and scope

Stop and get explicit human confirmation before:

- scanning any host not already authorized for this engagement;
- `-d 0`, `--force-recursion`, `--thorough` or `--parallel` on a production
  host, all of which multiply request volume;
- `-x`/`-E`/`-g`/`-B` collection modes, which invent new request paths the
  target owner has not seen;
- sending authenticated requests (`-H Authorization`, `--data*`) — the scan
  then acts as that user and can write state;
- raising `--rate-limit`/`-t` above the agreed engagement budget.

Every request is logged by the target. A recursive scan of a soft-404 site with
filters disabled can be tens of thousands of requests; treat that as an
availability risk, not a read-only measurement.
