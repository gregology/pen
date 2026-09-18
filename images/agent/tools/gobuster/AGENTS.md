# gobuster — mode-based brute-forcer (dir, dns, vhost, fuzz, s3, gcs, tftp)

gobuster is one binary with a subcommand per enumeration type. `dir` brute-forces
web paths, `dns` subdomains, `vhost` virtual hosts, `fuzz` any position marked
with the `FUZZ` keyword, and `s3`/`gcs`/`tftp` enumerate cloud buckets and TFTP
files. Reach for it when you want a fast, dependency-free brute-forcer whose
output is stable text; reach for `ffuf` when you need response filtering and
recursion, `feroxbuster` to map a whole tree, `dnsx`/`subfinder` for DNS-heavy
work, and `arjun` when the question is parameter *names* rather than paths.

## Install and location

| | |
|---|---|
| Version | **3.5.0-1+b1** (Debian bookworm) — this predates the upstream 3.7 CLI rework |
| Binary | `/usr/bin/gobuster` — no man page in this image (no `gobuster(1)`, and no `man` binary); `gobuster <mode> --help` is the local reference |
| Wordlists | `/opt/wordlists/current` (SecLists) |

**The flags below are the v3.5.0 set.** Newer upstream releases renamed and added
flags, so do not copy commands from the current upstream README without checking
`gobuster <mode> --help`. In particular 3.5.0 has **no JSON/XML/CSV output**, no
`--rate`, and no `--wildcard` in dir mode.

## Flags that matter

Global (every mode):

| Flag | What it does |
|---|---|
| `-w FILE` | Wordlist. **Required.** `-w -` reads the wordlist from stdin. |
| `-t N` | Concurrent threads, default 10. |
| `--delay D` | Wait between requests per thread, as a Go duration (`--delay 1500ms`, `--delay 2s`), default 0. |
| `-o FILE` | Write results to a file (results only; progress and errors stay on the terminal). |
| `-q` | No banner, no progress. |
| `-z`, `--no-progress` | Suppress the progress line only (progress goes to stderr on a TTY). |
| `-v`, `--verbose` | Verbose output: also print `Missed:` lines and errors. |
| `--no-error` | Suppress errors. |
| `-p FILE` | Pattern file: each line is applied to every word, `{GOBUSTER}` is replaced by the word. |
| `--no-color` | Disable ANSI colour. |

HTTP modes (`dir`, `vhost`, `fuzz`):

| Flag | What it does |
|---|---|
| `-u URL` | Target URL. Required. Without a scheme, `host:80` → `http://`, `host:443` → `https://`, `host` → `http://`; any other explicit port without a scheme is an error. |
| `-m METHOD` | HTTP method, default `GET`. |
| `-c COOKIES` | Cookie header value. |
| `-H 'Name: value'` | Extra header, repeatable. |
| `-U USER`, `-P PASS` | Basic auth. `-U` without `-P` prompts on the terminal and fails without a TTY. |
| `-a AGENT`, `--random-agent` | Fixed or random User-Agent. |
| `-r`, `--follow-redirect` | Follow redirects (default off). |
| `-k`, `--no-tls-validation` | Skip TLS certificate verification. |
| `--proxy URL` | HTTP(S) proxy. |
| `--timeout D` | Per-request timeout, Go duration, default `10s`. |
| `--retry`, `--retry-attempts N` | Retry on timeout (default 3 attempts). |
| `--client-cert-pem`, `--client-cert-pem-key`, `--client-cert-p12`, `--client-cert-p12-password` | mTLS client certificates. |

`dir` mode:

| Flag | What it does |
|---|---|
| `-s CODES` | Positive status codes, e.g. `-s 200,204,301,302,307,401,403`. Ranges allowed (`200,300-305`). |
| `-b CODES` | Negative status codes; **default `404`**. If you set `-s`, you must clear this with `-b ""` or the run aborts. |
| `-x EXTS` | File extensions to try, e.g. `-x php,html,bak`. |
| `-X FILE` | Read extensions from a file. |
| `--exclude-length N` | Drop responses of this body length (repeatable). Use it for soft-404s. |
| `-e`, `--expanded` | Print the full URL instead of `/path`. |
| `-n`, `--no-status` | Omit status codes. |
| `--hide-length` | Omit body length. |
| `-f`, `--add-slash` | Request `/path/` instead of `/path`. |
| `-d`, `--discover-backup` | Also try `~`, `.bak`, `.bak2`, `.old`, `.1`, `.swp` variants. |

Other modes: `dns -d DOMAIN` (required) with `-i/--show-ips`, `-c/--show-cname`,
`-r/--resolver server[:port]`, `--wildcard`, `--timeout` (default `1s`);
`vhost -u URL` with `--append-domain`, `--domain`, `--exclude-length`;
`fuzz -u URL` with `-b/--excludestatuscodes`, `--exclude-length`, `-B/--body`,
requiring `FUZZ` in the URL, headers, body or credentials; `s3`/`gcs` with
`-m/--maxfiles`; `tftp -s SERVER` with `--timeout`.

## Examples

### Directory brute-force with a small list

```bash
gobuster dir -u https://target.example -w /opt/wordlists/current/Discovery/Web-Content/common.txt \
  -t 10 --delay 100ms -o $WORK/gobuster-dir.txt
```

On a TTY, progress prints on stderr and hits print to stdout as
`/admin                (Status: 301) [Size: 0] [--> https://target.example/admin/]`.
In a pipe, stderr is empty and the banner plus results go to stdout.
`common.txt` is small (~4.6k words) — the right first pass. If the server answers
everything with 200, gobuster aborts with `the server returns a status code that
matches the provided options for non existing urls`; re-run with
`--exclude-length <length from that message>`.

### Extensions and a soft-404 filter

```bash
gobuster dir -u https://target.example -w /opt/wordlists/current/Discovery/Web-Content/raft-medium-directories.txt \
  -x php,html,txt,bak -s 200,204,301,302,307,401,403 -b "" \
  --exclude-length 1234 -t 10 --delay 100ms -o $WORK/gobuster-ext.txt
```

`raft-medium-directories.txt` is directory-shaped (~30k words);
`raft-medium-files.txt` is the file-shaped counterpart.

### Subdomain enumeration

```bash
gobuster dns -d target.example -w /opt/wordlists/current/Discovery/DNS/subdomains-top1million-5000.txt \
  -t 20 -i --timeout 2s -o $WORK/gobuster-dns.txt
```

Hits print `Found: api.target.example [10.0.0.5]`. A wildcard DNS record makes
every word "Found" and gobuster stops with a wildcard error unless `--wildcard`
is given — then treat the results as noise. Use `dnsx`/`subfinder` when you want
passive sources or recursion.

### Virtual host discovery (the mode nothing else here covers well)

```bash
gobuster vhost -u https://10.0.0.5 -w /opt/wordlists/current/Discovery/DNS/subdomains-top1million-5000.txt \
  --append-domain --domain target.example --exclude-length 1234 -t 10 -o $WORK/gobuster-vhost.txt
```

Use the IP as the URL and `--append-domain` to turn each word into
`<word>.target.example` in the Host header. Vhost results are noisy when the
default vhost answers everything identically — `--exclude-length` (from the
noise response's size) is how you cut it down.

### Targeted fuzzing of one position

```bash
gobuster fuzz -u 'https://target.example/api/v1/users?id=FUZZ' \
  -w /opt/wordlists/current/Discovery/Web-Content/burp-parameter-names.txt \
  -b 404,400 -t 5 -o $WORK/gobuster-fuzz.txt
```

`FUZZ` can also be in a header value (`-H 'X-Api-Key: FUZZ'`) or the body
(`-B 'user=FUZZ&pass=x'`, needs `-m POST`). This overlaps ffuf entirely — prefer
ffuf for real fuzzing and keep gobuster `fuzz` for quick checks.

## Output formats

Plain text, one result per line, written to stdout and to `-o FILE` identically;
**3.5.0 has no JSON, XML or CSV output**.

- `dir`: `/path                (Status: 200) [Size: 1234] [--> https://target.example/path/]`
- `dns`: `Found: api.target.example [10.0.0.5]` (with `-v`, misses print as `Missed: …`)
- `vhost`: `Found: admin.target.example Status: 200 [Size: 4321]`
- `fuzz`: `Found: [Status=200] [Length=512] /api/v1/users`
- `s3`: `http://bucket.s3.amazonaws.com/ [Status]`
- `tftp`: `filename [size]`

Machine-readable means post-processing text:

```bash
grep -E '\(Status: 200\)' $WORK/gobuster-dir.txt | awk '{print $1}'
grep '^Found: ' $WORK/gobuster-dns.txt | awk '{print $2}'
```

or using `ffuf -of json` / `feroxbuster --json` when a downstream tool needs
structured results.

## Failure modes

- **Wildcard/soft-404 aborts the run** with `the server returns a status code
  that matches the provided options for non existing urls. <url> => <code>
  (Length: <n>)` and exit status 1. Fix by excluding that length
  (`--exclude-length n`) or moving the code to the blacklist (`-b`), not by
  ignoring it — otherwise every line in the output is a lie.
- **`-s` and `-b` are mutually exclusive.** Setting `-s` while the default
  `-b 404` is still in place aborts with `status-codes (...) and
  status-codes-blacklist (...) are both set`. Pass `-b ""`.
- **No default ports, no default paths.** A bare `-u host` becomes `http://host`
  (port 80). An HTTPS site needs the scheme or port 443.
- **`-U` without `-P` prompts for a password.** Without a TTY the run fails with
  `username given but reading of password failed`.
- **The wordlist must exist**, and a wordlist of `-` is the only way to read
  from stdin.
- **A missing status-code match is not a missing file.** Only the codes you
  asked for are printed; `-s 200` hides the `403` that is your actual finding.
  Default `-b 404` with no `-s` prints everything else, which is the safer
  default.
- **Progress is TTY-only; results are not.** On a TTY progress goes to stderr
  and results to stdout; in a pipe stderr is empty and the banner plus results
  go to stdout. `-q` removes the banner and progress but not errors.
- **No TLS verification by default is a choice you have to make** — a `-k`-less
  run against a self-signed target fails handshakes per thread, which looks like
  "nothing found". Use `-k` for lab targets and record it.
- **Exit status is 1 on any error** (including wildcard aborts and wordlist
  problems), 0 on a completed run — including a run with zero results.

## Notes

- **Rate control is `-t` × `--delay`.** There is no requests-per-second flag in
  3.5.0. `-t 10 --delay 100ms` is roughly a 100 req/s ceiling; for a
  WAF-fronted target start at `-t 5 --delay 500ms` and watch for 429/403 shifts.
- **Wordlist choice is the whole game.** `Discovery/Web-Content/common.txt`
  (first pass), `raft-small-words.txt`, `raft-medium-directories.txt` /
  `raft-large-directories.txt`, `raft-medium-files.txt`,
  `raft-medium-extensions.txt` + `-X`,
  `Discovery/Web-Content/api/api-endpoints.txt`,
  `Discovery/DNS/subdomains-top1million-5000.txt` (vhost/dns) — all under
  `/opt/wordlists/current`. Upstream docs still cite
  `directory-list-2.3-medium.txt`; in SecLists 2026.1 that file is named
  `DirBuster-2007_directory-list-2.3-medium.txt`.
- `dir` mode does not recurse. For "map the whole tree" use feroxbuster; for one
  flat pass gobuster is faster and simpler.
- `vhost` and `dns` overlap with httpx/dnsx/subfinder but answer different
  questions: gobuster `vhost` tests Host headers against one IP (no DNS needed).
- `s3`/`gcs` enumerate public bucket names over HTTP; only run them within an
  authorised scope, and expect the bucket owner to see the requests.

## Safety

- Only against hosts explicitly confirmed for the engagement.
- `-U`/`-P`, `-H 'Cookie: …'` and `-B` act as that user and can write state on
  POST endpoints.
- Raising `-t` or dropping `--delay` on a production service is a
  self-inflicted outage; state the request budget first.
- `s3`/`gcs` are internet-facing by nature.
