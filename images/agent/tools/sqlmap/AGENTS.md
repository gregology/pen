# sqlmap

Automated SQL injection detection and exploitation. sqlmap takes a target URL,
a saved HTTP request, or a crawl of a site, probes parameters with a large
payload corpus, confirms which injection techniques work, and then enumerates
or dumps what the database will give up. It is the tool for "is this parameter
injectable, and what does the schema behind it look like".

It is also loud and destructive-by-default at higher settings: `--risk 3`
includes payloads that can modify or delete data, and `--os-shell`/`--file-write`
turn an injection into command execution on the database host. Detection is
cheap and safe; everything after that is an exploitation decision.

## Installation and location

| Item | Value |
|---|---|
| Binary | `/usr/bin/sqlmap` (Debian package; runs `python3 /usr/share/sqlmap/sqlmap.py`) |
| Version | 1.7.2#stable (Debian bookworm) |
| Program data | `/usr/share/sqlmap/` — `tamper/` (71 scripts), `data/txt/user-agents.txt`, `data/xml/` |
| User data | `/root/.local/share/sqlmap/` — `history/`, `output/` |
| Default output | `/root/.local/share/sqlmap/output/` |
| Wordlists | `/opt/wordlists/SecLists/Discovery/Web-Content/` for `--crawl`-adjacent work |

Every run prints `[WARNING] your sqlmap version is outdated` — that is the
Debian package comparing itself against upstream, not a failure.

## Rules that apply to this tool

1. **Explicit human confirmation per target URL.** SQL injection testing sends
   hostile payloads into a live application and can corrupt data. Confirm the
   URL, the parameter set, `--level`/`--risk` and whether enumeration is
   authorized *before* the first request — detection and extraction are
   separate authorizations.
2. **Start at `--level 1 --risk 1 --technique` narrowed.** `--risk 2`/`3` add
   payloads that write to the database (UPDATE/INSERT/stacked queries). Treat
   anything above risk 1 as a change to the target, needing its own
   confirmation.
3. **`--os-shell`, `--os-cmd`, `--os-pwn`, `--file-read`, `--file-write`,
   `--reg-*` and `--sql-shell` are post-exploitation.** They never run without
   explicit confirmation, and never with `--batch` on an unattended loop.
4. **All traffic exits the WireGuard tunnel** in the shared netns. `--proxy`
   points at a proxy inside the tunnel; it is not a containment mechanism and
   does not change where traffic leaves from.
5. **Rate-limit.** Default is 1 thread. Raising `--threads` or dropping
   `--delay` on a production service is a self-inflicted outage; state the
   request budget (`--level`/`--risk`/technique choice) before running.
6. **Evidence into `$WORK`.** Either point `--output-dir "$WORK/sqlmap"` or copy
   `/root/.local/share/sqlmap/output/<host>/` there afterwards.

## Command reference

### Target definition

| Flag | Meaning |
|---|---|
| `-u URL, --url=URL` | Target URL including the parameter to test |
| `-r REQUESTFILE` | Load the HTTP request from a file (Burp-style raw request) |
| `--data=DATA` | POST body (`--data="id=1"` switches to POST testing) |
| `-g GOOGLEDORK` | Treat search results as targets (not useful here) |
| `-c CONFIGFILE` | Load options from an INI file |
| `--crawl=CRAWLDEPTH` | Crawl from the target URL and test what it finds |
| `--forms` | Parse and test forms on the target page |
| `-p PARAM` / `--skip` | Restrict or exclude parameters |
| `--cookie`, `--headers`, `--referer`, `--user-agent`, `--random-agent` | Request decoration (session cookies, extra headers, UA) |
| `--proxy=PROXY`, `--proxy-cred`, `--proxy-file` | Route through a proxy |

### Detection and control

| Flag | Meaning |
|---|---|
| `--batch` | Never ask; use default answers. **Required for unattended runs** |
| `--smart` | Only run thorough tests when a heuristic is positive |
| `--level=1..5` | Number of tests/payloads (default 1) |
| `--risk=1..3` | Risk of the payloads (default 1; 2–3 can modify data) |
| `--technique=BEUSTQ` | Techniques: B boolean, E error, U union, S stacked, T time, Q inline. Default all |
| `--dbms=DBMS` | Skip fingerprinting and force a DBMS (e.g. `mysql`, `mssql`, `postgresql`, `sqlite`) |
| `--tamper=SCRIPT[,..]` | Tamper scripts, e.g. `space2comment`, `charencode`, `between` |
| `--threads=N` | Concurrent HTTP requests (default 1) |
| `--delay=S`, `--timeout=S`, `--retries=N` | Pacing and reliability |
| `--parse-errors` | Show DBMS error messages from responses |
| `--flush-session` | Forget the cached session for this target and retest |
| `--answers=…` | Preset answers (e.g. `"quit=N,follow=N"`) |
| `--list-tampers` | Print the tamper scripts and exit (71 in this build) |

### Enumeration and extraction

| Flag | Meaning |
|---|---|
| `--banner`, `--current-db`, `--current-user`, `--hostname` | DBMS identity |
| `--dbs`, `--tables`, `--columns`, `--schema` | Schema enumeration |
| `--dump` | Dump table entries (with `-T` / `-C`) |
| `--dump-all` | Dump everything |
| `--sql-query="SELECT …"`, `--sql-shell` | Arbitrary SQL |
| `--dump-format=CSV\|HTML\|SQLITE` | Dump file format (CSV is the default) |
| `--dump-file=FILE` | Write the dump to a specific file |
| `--output-dir=DIR` | Move the whole per-target output tree |
| `--results-file=FILE` | Location of the aggregate CSV in multiple-target mode |
| `--file-read=FILE`, `--file-write=LOCAL`, `--os-cmd`, `--os-shell`, `--os-pwn` | Post-exploitation (authorization required) |
| `--purge` | Delete all sqlmap session/output data |

## Typical workflows

### 1. Detect first, with a narrow technique and no enumeration

```bash
mkdir -p "$WORK/sqlmap"
sqlmap -u 'https://app.example/item?id=1' --batch \
  --level=1 --risk=1 --technique=B --dbms=mysql \
  --output-dir "$WORK/sqlmap" </dev/null
```

Detection output ends with an injection-point summary (`Parameter: id (GET)` +
`Type:`/`Title:`/`Payload:` per confirmed technique) or with
`[ERROR] all tested parameters do not appear to be injectable` plus a list of
things to try (`--level`/`--risk`, `--tamper`, `--random-agent`).

### 2. Authenticated testing from a saved request

Export the request from the browser/proxy into `req.txt`, keeping cookies:

```bash
sqlmap -r "$WORK/req.txt" --batch --level=2 --risk=1 --technique=BEU \
  --output-dir "$WORK/sqlmap" </dev/null
```

**Non-interactive shells need a pty for `-r`** — see the gotchas. The verified
form is:

```bash
script -qc "sqlmap -r $WORK/req.txt --batch --technique=B --output-dir $WORK/sqlmap" /dev/null
```

### 3. Enumerate and dump once detection is confirmed

```bash
sqlmap -u 'https://app.example/item?id=1' --batch --tables
sqlmap -u 'https://app.example/item?id=1' --batch -T users --columns
sqlmap -u 'https://app.example/item?id=1' --batch -T users --dump \
  --dump-format=CSV
```

### 4. WAF-evasion tamper chain

```bash
sqlmap -u 'https://app.example/item?id=1' --batch \
  --tamper=space2comment,between,charencode --random-agent --delay=1
```

Confirm each tamper loads: sqlmap prints
`[INFO] loading tamper module 'space2comment'` per script. Note its warning
that `changes made by tampering scripts are not included in shown payload
content(s)` — the `Payload:` lines show the untampered payload.

### 5. Crawl a site and test what is found

```bash
sqlmap -u 'https://app.example/' --batch --crawl=2 \
  --crawl-exclude='logout|signout' --level=1 --risk=1 --output-dir "$WORK/sqlmap"
```

`--crawl` prints two prompts (whether to normalise crawling results, and whether
to store them to a temp file). `--batch` answers them with the defaults shown
(`normalize` Y, `store` N — verified); use `--answers` to force specific replies
(the help's own example is `--answers="quit=N,follow=N"`).

## Output and parsing

Everything lands under the output directory — by default
`/root/.local/share/sqlmap/output/`, or the `--output-dir` you set. Verified
layout for a target at `http://127.0.0.1:8896/item?id=1`:

```
output/
├── results-09172026_0841pm.csv                 # aggregate, all targets
└── 127.0.0.1/
    ├── log                                     # full session transcript
    ├── session.sqlite                          # cached session (detection state)
    ├── target.txt                              # the target URL
    └── dump/
        └── SQLite_masterdb/
            └── items.csv                       # one CSV per dumped table
```

- **Aggregate CSV** — header
  `Target URL,Place,Parameter,Technique(s),Note(s)`; one row per confirmed
  injection point, e.g.
  `http://127.0.0.1:8896/item?id=1,GET,id,BTU,`. Timestamped
  `results-<MMDDYYYY_HHMM{am,pm}>.csv`, appended across runs.
- **Dump CSV** — plain CSV with a header row
  (`id,name,price` / `1,widget,9.99` …), written when `--dump` completes:
  `[INFO] table 'SQLite_masterdb.items' dumped to CSV file
  '/root/.local/share/sqlmap/output/127.0.0.1/dump/SQLite_masterdb/items.csv'`.
- **`log`** — the same text sqlmap printed, including every payload and the
  final `Parameter:` block. This is the file to grep when a run has to be
  explained: `grep -E 'injectable|Payload|does not seem' log`.
- **`session.sqlite`** — sqlmap's own cache. Do not edit it by hand;
  `--flush-session` is the supported way to force a retest.

Parsing:

```bash
jq -R -s 'split("\n") | map(select(length>0))' "$WORK/sqlmap/results-"*.csv   # or just csv
cut -d, -f1,3,4 "$WORK/sqlmap/results-"*.csv
grep -E 'Payload:' "$WORK/sqlmap/${HOST}/log" | sort -u
```

`sqlmap --version` prints `1.7.2#stable` (plus the outdated-version warning).

## Chaining with the rest of the toolchain

- **katana/feroxbuster → sqlmap.** Crawlers produce parameterised URLs; feed
  them to `-u` (or a bulk file with `-m`) rather than blind-crawling with
  sqlmap, which is slower and noisier.
- **httpx → sqlmap.** `httpx -json` output gives live URLs; `jq -r '.url'`
  into a target list keeps sqlmap on endpoints that actually answer.
- **Proxy capture → sqlmap.** A saved request (`-r`) preserves method, cookies
  and headers — the only reliable way to test a POST/JSON endpoint behind auth.
- **sqlmap → findings note.** A confirmed injection is a finding on its own;
  the dump is a separate, higher-severity one. Record the target, parameter,
  technique, payload, request count and the dump path — not the dumped rows
  themselves, unless the data handling for them is agreed.
- **sqlmap → hashcat/john.** Dumped password hashes go to the crackers: `$1$`
  /`$5$`/`$6$` to john, everything else to hashcat with the right `-m`.
- **sqlmap → hydra/netexec.** Credentials recovered from a dump are validated
  against the authorized service only, with lockout-aware rates.

## Limits, failure modes and gotchas

**`-r` silently does nothing when stdin is not a TTY — the biggest trap.**
`sqlmap -r req.txt --batch` with stdin at EOF prints
`[INFO] parsing HTTP request from 'req.txt'` then
`[INFO] using 'STDIN' for parsing targets list` and exits without testing
anything, exit status 0. This is the code path in
`lib/core/option.py:_setStdinPipeTargets()`: it only returns early when
`conf.url` is already set, and a request file does not set it at that point.
Verified workarounds:

- `script -qc "sqlmap -r req.txt --batch …" /dev/null` — allocates a pty, the
  request file is parsed and the scan runs (verified end to end);
- `-r` plus `-u` is **not** a workaround: sqlmap aborts with
  `[CRITICAL] option '-r' is incompatible with option '-u' ('--url')`;
- closing stdin (`0<&-`) is worse: sqlmap crashes with
  `AttributeError: 'NoneType' object has no attribute 'encoding'`.

**Session caching makes reruns look wrong.** sqlmap stores detection state in
`session.sqlite`; a second run against the same target can skip tests and
answer from cache, which makes a fast verdict look like a clean one. Pass
`--flush-session` whenever a fresh result is required and watch the
`[INFO]` lines for tests that were not re-run.

**A "might be injectable" heuristic is not a finding.** The
`heuristic (basic) test shows that GET parameter 'id' might be injectable`
line is followed by real payload tests, and on a target that only *looks*
injectable sqlmap prints
`[WARNING] false positive or unexploitable injection point detected` and
`GET parameter 'id' does not seem to be injectable`. Report only the
`Parameter:`/`Type:`/`Payload:` block or the `is vulnerable` line.

**Time-based tests dominate runtime.** `--technique=T` (and the heavy-query
payloads sqlmap adds for SQLite) can make a single detection run take minutes;
`--technique=B` or `U` is far quicker when you know the DBMS answers.

**Threads and delay are the target's problem, not yours.** `--threads=10`
against a small service is a load test. Keep the default `--threads=1` unless
the target owner has said otherwise.

**Level/risk are real escalation.** `--risk=3` includes OR-based payloads that
can return or modify every row; `--level=5` sends far more requests. Neither is
a "thoroughness" knob to turn up casually.

**`--os-shell` needs the right conditions.** It requires FILE privilege and a
writable directory (MySQL), `xp_cmdshell` (MSSQL) or similar; on most hardened
targets it fails after a long, noisy attempt. Treat failure as expected, not as
a reason to retry with more force.

**Output paths are root-owned.** sqlmap writes under `/root/.local/share/...`
because the agent runs as root; use `--output-dir` into `$WORK` so the evidence
sits with the rest of the engagement artifacts.

**No JSON output.** Results are text (`log`), CSV (`results-*.csv`, dumps) and
the session SQLite file. Parse the CSVs or grep the log.

## Safety and scope

Never run without explicit human confirmation per target:

- any request against a URL that is not in the written scope for this
  engagement ("it is the same app" is not scope);
- `--risk` above 1, or `--level` above 2, without stating what extra payloads
  that enables;
- `--os-shell`, `--os-cmd`, `--os-pwn`, `--sql-shell`, `--file-read`,
  `--file-write`, `--reg-read/add/del` — all are host compromise, not
  detection;
- `--dump`, `--dump-all` or `--sql-query` against real user data (state what
  will be retrieved and how it will be stored before extracting it);
- `--crawl` against a site that has not been authorized for crawling — it
  follows every link it finds, including logout and destructive GET actions;
- `--threads` above the default, or `--delay=0`, on anything that serves real
  users;
- running sqlmap against a target that is already alerting, without telling
  Greg first.
