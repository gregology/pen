# whatweb — web technology fingerprinting

whatweb fetches a page and runs ~1,800 Ruby plugins against the response to name
the CMS, framework, server, JavaScript libraries, analytics, embedded devices and
— sometimes — the WAF in front. Use it to answer "what is this site built from"
so the next step is targeted: a WordPress version points at CMS checks, a Jenkins
or Tomcat banner points at nuclei templates, an IIS server points at a different
wordlist. It is not a vulnerability scanner and not a crawler; wafw00f is the
tool for WAF questions and httpx is the tool for bulk tech-detect over thousands
of hosts.

## Install and location

| | |
|---|---|
| Version | **0.5.5-1** (Debian bookworm; upstream is now at 0.6.x, so flags from the current upstream README do not all exist here) |
| Binary | `/usr/bin/whatweb` |
| Plugins | `/usr/share/whatweb/plugins/` (1,818 `.rb` files); user plugins in `/usr/share/whatweb/my-plugins/` |

Flags that **do not exist** in this version: `--no-cookies`, `--output-sync`,
`--output-buffer-size`. The package also does **not** ship upstream's
`plugins-disabled/` directory, so `-p +plugins-disabled` will not resolve. The
Debian patches change only the library load path.

## Flags that matter

| Flag | What it does |
|---|---|
| `<TARGETs>` | URLs, hostnames, IPs, filenames, CIDR ranges (`192.168.0.0/24`) or ranges (`10.0.0.1-10.0.0.50`). |
| `-i, --input-file FILE` | Read targets from a file; `-i /dev/stdin` accepts a pipe. |
| `-a, --aggression 1\|3\|4` | Trade stealth for reliability. **Only 1, 3 and 4 are accepted; `-a 2` errors.** Default 1. |
| `-v, --verbose` | Include plugin descriptions and per-plugin detail. `-vv` dumps the internal object for debugging. |
| `-q, --quiet` | Suppress the brief one-line output (useful with `--log-*`). |
| `-l, --list-plugins` | List every loaded plugin and exit. |
| `-I, --info-plugins [SEARCH]` | Describe plugins, optionally filtered by comma-separated keywords. |
| `-p, --plugins LIST` | Choose plugins: comma-separated names, files, directories, with `+`/`-` modifiers. |
| `-g, --grep STRING\|/REGEX/` | Print only results matching a string or `/regex/`. |
| `--custom-plugin DEFINITION` | Define a one-off plugin: `--custom-plugin ':text=>"powered by abc"'`, `:version=>/regex/`, `:md5=>'hash'`. |
| `-U, --user-agent AGENT` | Replace the User-Agent (default `WhatWeb/0.5.5`). |
| `-H, --header 'Name: value'` | Add or replace a header; an empty value removes a default header. |
| `-u, --user user:pass` | HTTP basic authentication. |
| `-c, --cookie 'a=1; b=2'` | Send cookies. |
| `--cookie-jar FILE` | Read cookies (one per line) and reuse them for the scan. |
| `--follow-redirect WHEN` | `never`, `http-only`, `meta-only`, `same-site`, `always` (default `always`). |
| `--max-redirects N` | Redirect limit, default 10. |
| `-t, --max-threads N` | Worker threads, default 25. |
| `--open-timeout N`, `--read-timeout N` | Connection and read timeouts in seconds. |
| `--wait N` | Sleep N seconds between connections. |
| `--no-errors` | Suppress per-target error messages. |
| `--colour WHEN` | `never`, `always`, `auto` — use `never` for captured output. |
| `--log-brief`, `--log-verbose`, `--log-json`, `--log-xml`, `--log-json-verbose`, `--log-sql`, `--log-magictree`, `--log-object FILE` | Write results to files in each format. |
| `--url-prefix P`, `--url-suffix S`, `--url-pattern PAT` | Rewrite targets. |
| `--proxy HOST[:PORT]`, `--proxy-user user:pass` | Route requests through a proxy. |
| `--debug` | Raise plugin errors instead of swallowing them. |

**Aggression levels** (from the tool's own help): `1` Stealthy — one HTTP
request per target, follows redirects; `3` Aggressive — if a level-1 plugin
matches, additional requests are made; `4` Heavy — many requests per target,
every plugin's URLs are attempted. Level 4 against a production site is a small
crawl, not a fingerprint.

## Examples

### One host, readable output

```bash
whatweb -a 1 --colour never "https://target.example"
```

Expect one line: `https://target.example [200 OK] Country[RESERVED][ZZ],
HTTPServer[nginx/1.24.0], IP[10.0.0.5], Title[Example], WordPress[6.4.3],
X-Powered-By[PHP/8.2.12]`. The `[200 OK]` field is the HTTP status; anything
after it is plugin output.

### Aggressive version detection on one host

```bash
whatweb -a 3 -v --colour never "https://target.example" | tee $WORK/whatweb-target.txt
```

`-a 3` runs the follow-up requests that turn `WordPress` into `WordPress[6.4.3]`.
`-v` adds the plugin descriptions and the specific strings that matched — this is
the evidence you cite. Level 4 (`-a 4`) attempts every URL every plugin knows;
use it only on a target that tolerates a crawl and only with `-t 5 --wait 1`.

### A host list into JSON, then a technology inventory

```bash
httpx -l $WORK/hosts.txt -silent -mc 200,301,403 > $WORK/live.txt
whatweb -i $WORK/live.txt -a 1 -t 10 --no-errors --colour never \
  --log-json $WORK/whatweb.json -q
jq -r '.[] | .target as $t | .plugins | keys[] | "\(.)\t\($t)"' $WORK/whatweb.json \
  | sort | uniq -c | sort -rn | head -20
```

The second command gives you "which technologies appear on how many hosts" — the
table that decides where to spend the next hour. `-q` suppresses the terminal
lines because `--log-json` already captured them.

### Versions only, ready for a CVE lookup

```bash
jq -r '.[] | .target as $t | .plugins | to_entries[]
       | select(.value.version != null)
       | "\($t)\t\(.key)\t\(.value.version | join(","))"' $WORK/whatweb.json | column -t
```

Never trust the version alone — whatweb reads banners, and banners lie; confirm
with the application's own version endpoint before reporting a CVE match.

### Authenticated, cookie-carrying scan

```bash
whatweb -a 3 -u "admin:$PASS" -c "session=$TOKEN" -H "X-Forwarded-For: 127.0.0.1" \
  --colour never "https://target.example/dashboard" --log-json $WORK/whatweb-auth.json
```

Authenticated whatweb sees the application rather than the login page, which is
usually where the interesting tech lives. A wrong password just re-detects the
login page.

### A one-off signature with no plugin

```bash
whatweb --custom-plugin ':text=>"internal build"' --colour never "https://target.example"
whatweb -a 1 -p title,md5,HTTPServer --colour never "https://target.example"
```

## Output formats

Default output is the brief one-liner: `target [status code]
Plugin[version][string], Plugin2[...]`. Use `-q` with any `--log-*`.

`--log-json FILE` writes a JSON **array**, one object per target, each with
`target`, `http_status`, `request_config` and `plugins` — a map of plugin name to
`{version, string, os, account, model, firmware, module, filepath, certainty}`;
arrays are omitted when empty (`certainty` is omitted when it is 100).

```json
[
  {
    "target": "https://target.example",
    "http_status": 200,
    "request_config": {},
    "plugins": {
      "HTTPServer": { "string": ["nginx/1.24.0"] },
      "WordPress": { "version": ["6.4.3"], "certainty": 90 }
    }
  }
]
```

Other machine-readable logs: `--log-xml`, `--log-json-verbose` (per-plugin detail
including match locations), `--log-sql` (`--log-sql-create` writes the schema),
`--log-magictree`, `--log-object`, `--log-brief`, `--log-verbose`. There is no
"JSON to stdout" flag — write a file and read it.

## Failure modes

- **`-a 2` is rejected**: `Agression level must be 1,3, or 4.` Levels are not a
  scale of 1–4.
- **`plugins-disabled` does not exist in this package.** `-p +plugins-disabled`
  fails with `Error: The following plugins were not found: …`. Use plugin names
  from `-l` or explicit paths under `/usr/share/whatweb/plugins/`.
- **A target that times out produces nothing but an error line**
  (`ERROR Opening: …`), suppressed entirely by `--no-errors`. Count your JSON
  records against your input list — fewer records means some hosts failed, not
  that they have no technology.
- **Redirects are followed by default.** The `target` in the JSON output stays
  the URL you asked for even when the fingerprint came from the redirect
  destination; check with `--follow-redirect never` if that distinction matters.
- **whatweb's own User-Agent is a giveaway.** It identifies as `WhatWeb/0.5.5`
  unless `-U` is set; some WAFs block it, and `--no-errors` will hide the
  resulting failures.
- **High thread counts amplify problems.** `-t 25` from one VPN exit looks like a
  burst; use `-t 5 --wait 1` for anything rate-sensitive.
- **Version strings are banner-derived and frequently wrong or stale.**
  `WordPress[6.4.3]` may come from a generator meta tag that was not updated.
  Treat version matches as leads, not findings.
- **Aggression 4 is a crawl.** Against a large site it can be thousands of
  requests and is easily mistaken for an attack.
- **`--log-*` files are written with append semantics** — running the same
  command twice appends a second JSON document to the file, producing invalid
  JSON. Delete the file or use a fresh name between runs. This one silently
  breaks any downstream `jq`.

## Notes

- **Plugin selection beats aggression for cost control.** `-I wordpress`
  describes a plugin; `-p title,HTTPServer,WordPress` runs only those. A targeted
  `-p` at aggression 3 is usually cheaper *and* more informative than a full
  aggression-4 sweep.
- **Overlap:** whatweb and wafw00f both name WAFs, but whatweb only sees what the
  default page exposes. When the question is "will my payloads be blocked", use
  wafw00f; when the question is "what is this built from", use whatweb.
  `httpx -tech-detect` answers the same question at scale; whatweb's advantage is
  plugin depth and per-plugin evidence.
- **Rate:** a level-1 scan is one request per target plus redirects — cheap
  enough to run over a whole host list. Level 3 multiplies that by the number of
  matching plugins; level 4 is effectively unbounded. Record the level used in
  the findings note.
- Wordlists for the *next* step are under `/opt/wordlists/current`; whatweb does
  not use them itself.

## Safety

- Only against hosts explicitly confirmed for the engagement.
- `-a 4` is a crawl against a production service — confirm before running it.
- `-u`/`-c`/`--cookie-jar` act as that user; treat any resulting session as
  credential material.
- Raising `-t` removes the politeness that keeps a fingerprint from looking like
  a burst.
