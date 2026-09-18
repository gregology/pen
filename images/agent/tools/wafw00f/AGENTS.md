# wafw00f — web application firewall fingerprinting

wafw00f sends a normal request, then a small set of attack-shaped probes, and
matches the responses against its signature set to name the WAF in front of a
target. Use it before deciding how hard to push: a fingerprinted WAF changes the
request rate, the payload classes worth trying, and whether a scan returning
nothing means "clean" or "blocked". It answers "is there a WAF and which one";
whatweb answers "what is the stack".

## Install and location

| | |
|---|---|
| Version | 2.4.2 (PyPI release 2026-01-26, requires Python ≥3.10; pinned in `install.sh`) |
| Entry point | `/usr/local/bin/wafw00f` → `/opt/venvs/wafw00f/bin/wafw00f` |
| Venv | `/opt/venvs/wafw00f` |
| Signatures | bundled; `wafw00f -l` prints the exact names this build can match (192 in 2.4.2) |

## Flags that matter

| Flag | What it does |
|---|---|
| `URL [URL …]` | Positional targets. A target without a scheme gets `https://` prepended (with a logged warning). |
| `-i FILE` | Read targets from a file: `.json` (a list of objects with a `url` key), `.csv` (needs a `url` column) or plain text, one per line. |
| `-a, --findall` | Report every matching signature instead of stopping at the first, and always run the generic detection afterwards. |
| `-t, --test NAME` | Test one specific WAF. `NAME` must match a `-l` entry exactly, manufacturer included, e.g. `"Cloudflare (Cloudflare Inc.)"`. **Also stops after the first target.** |
| `-l, --list` | Print every detectable WAF and its manufacturer, then exit 0. |
| `-o FILE` | Write results; the extension picks the format (`.json`, `.csv`, anything else = text). `-o -` writes to stdout. |
| `-f, --format json\|csv\|text` | Force the output format when writing to a file. |
| `-r, --noredirect` | Do not follow 3xx redirects (default is to follow). |
| `-p, --proxy URL` | HTTP/SOCKS proxy for the probes, e.g. `socks5://host:1080`. |
| `-H, --headers FILE` | Replace the default header set from a text file of `Name: value` lines. |
| `-T, --timeout N` | Request timeout in seconds, default 7. |
| `-v, --verbose` | Repeatable; more detail on stderr. |
| `--no-colors` | Disable ANSI colours — use this in every captured run. |
| `-V, --version` | Print version and exit. |

## Examples

### Fingerprint one host before planning the scan

```bash
wafw00f "https://target.example" -a --no-colors
wafw00f "https://target.example" -a -f json -o $WORK/waf.json
jq -r '.[] | select(.detected) | [.firewall, .manufacturer] | @tsv' $WORK/waf.json
```

Expect `[+] The site https://target.example is behind Cloudflare (Cloudflare
Inc.) WAF.`, then a generic-detection block and `[~] Number of requests: N`.
With `-a`, an unfolded list of `{"detected": false, "firewall": "None"}`
records is normal — it means no signature matched.

### A host list in one report

```bash
printf 'https://%s\n' target.example www.target.example api.target.example > $WORK/waf-targets.txt
wafw00f -i $WORK/waf-targets.txt -a -f json -o $WORK/waf-all.json
jq -r '.[] | select(.detected) | [.url, .firewall] | @tsv' $WORK/waf-all.json
```

### Feed a live-host list from httpx

```bash
httpx -l $WORK/hosts.txt -silent -mc 200,301,403 > $WORK/live.txt
wafw00f -i $WORK/live.txt -f csv -o $WORK/waf.csv
```

### Check for one product before choosing a bypass

```bash
wafw00f -l | grep -i cloudflare          # get the exact name first
wafw00f "https://target.example" -t "Cloudflare (Cloudflare Inc.)" --no-colors
```

A wrong name prints `[-] WAF <name> was not found in our list` and exits 0 —
indistinguishable from a clean negative unless you read the line.

## Output formats

Text (verified shape with `--no-colors`):

```
[*] Checking https://target.example
[+] The site https://target.example is behind Cloudflare (Cloudflare Inc.) WAF.
[+] Generic Detection results:
[-] No WAF detected by the generic detection
[~] Number of requests: N
```

JSON is an **array**, one object per detection pass, keys `detected`,
`firewall`, `manufacturer`, `trigger_url`, `url`; written with `indent=2,
sort_keys=True`:

```json
[
  {
    "detected": true,
    "firewall": "Cloudflare",
    "manufacturer": "Cloudflare Inc.",
    "trigger_url": "https://target.example/?xxxxxxxx=<script>alert(\"XSS\");</script>&…",
    "url": "https://target.example"
  }
]
```

CSV header: `url,trigger_url,detected,firewall,manufacturer`.

```bash
jq -r '.[] | select(.detected==true) | "\(.url)\t\(.firewall)\t\(.manufacturer)"' $WORK/waf.json
jq -r '.[] | select(.detected==true) | .trigger_url' $WORK/waf.json   # what was actually sent
jq -r '[.[] | select(.detected==false)] | length' $WORK/waf.json      # clean negatives
```

## Failure modes

- **"No WAF detected by the generic detection" means no signature matched**,
  not "no WAF". A WAF can be silent for these probes, sit behind a CDN that
  strips the tells, or only cover some paths. Record "not fingerprinted".
- **A target that is down produces no record at all.** With `-i`, unreachable
  hosts are logged (`Site X appears to be down`) and skipped; the JSON then
  contains fewer entries than the input list, or `[]`. Only `-v` shows why.
- **`-t` returns after the first target.** With `-i` and `-t` combined you test
  exactly one host. Use `-a` and a complete host list instead.
- **`-t NAME` must match a plugin name exactly**, including the parenthesised
  manufacturer; names with spaces must be quoted. `-l` is the authority.
- **The probes are attack-shaped.** The query string carries
  `<script>alert("XSS")`, `UNION SELECT ALL FROM information_schema`,
  `../../etc/passwd` and an XXE entity (visible in `trigger_url`). Any IDS/WAF
  will log them — and they leave from the shared VPN exit node.
- **`-o FILE` format comes from the extension** while `-f` forces the format
  independently; `-f json -o report.csv` writes JSON into a `.csv` file.
- **Exit codes carry almost nothing.** Normal runs exit 0 whether or not
  anything was detected; only file errors exit 1. Parse the output.

## Notes

- **Cost is low but not free:** a handful of requests per host. Do not loop it
  over a host list; `-i` does that in one pass.
- **Attack traffic exits through the VPN** like every other tool here. `-p` is
  for local interception, not containment.
- Combine with the fingerprint rather than treating it as trivia: a detected WAF
  is a reason to lower ffuf/nuclei concurrency and raise delays, and to expect
  that an empty scan result means "blocked" until proven otherwise.
- Record the returned `trigger_url` in the findings note — it is the exact
  request that identified the WAF, and the evidence that a WAF's logs will
  contain your scan.

## Safety

- Only against targets explicitly confirmed for the engagement: the probes are
  indistinguishable from an attack in the target's logs.
- A "no WAF" result is not authorization to raise concurrency. The rate budget
  comes from the engagement, not from this tool's output.
- `-p` must point at a local interception proxy you control, never at a route
  around the tunnel.
