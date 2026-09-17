# wafw00f

Web application firewall fingerprinting. It sends a small set of benign and
deliberately-suspicious probes and matches the responses against ~190 WAF
signatures, so a scan can be planned around what sits in front of the target.
It is a reconnaissance step, not a vulnerability scanner: it changes how hard
you push, not what you find.

## Installation and location

| Item | Value |
|---|---|
| Version | `v2.4.2` (`wafw00f -V` prints the banner and version) |
| Entry point | `/opt/pen-venv/bin/wafw00f` (Python virtualenv `/opt/pen-venv`) |
| Install | PyPI release into the venv at image build |
| Signature set | built into the package; `wafw00f -l` lists it — 192 lines in this version |
| Runs as | root; no TTY required |

## Rules that apply to this tool

1. **Authorization first.** wafw00f is not passive: its generic detection sends
   probe requests containing XSS, SQL-injection and path-traversal payloads in
   the query string (visible in the JSON `trigger_url`). Against an unauthorized
   host that is an attack, whatever the intent.
2. **Everything leaves through the VPN.** One non-loopback interface: the
   WireGuard tunnel in the shared netns. `-p/--proxy` is for local interception,
   not containment.
3. **It is cheap — a handful of requests per host** (verified: 7 for a
   single-target run). Keep it that way; do not loop it over a large host list
   without rate control, and prefer one pass with `-i`.
4. **Save evidence to the working directory.** `-o $WORK/waf.json` (or `-f json
   -o -` on stdout) so the fingerprint is reproducible and the exact signatures
   are recorded.
5. **A "no WAF" result is not permission.** It means no signature matched — not
   that the target tolerates more traffic.

## Command reference

| Flag | Meaning |
|---|---|
| `wafw00f URL [URL …]` | One or more targets as positional arguments |
| `-i, --input-file FILE` | Read targets from a file (text one-per-line, or CSV/JSON with a `url` column/element) |
| `-a, --findall` | Report every matching WAF instead of stopping at the first |
| `-t, --test NAME` | Test for one specific WAF; the name must match `--list` exactly (quote names with spaces) |
| `-l, --list` | List the WAFs it can detect |
| `-o, --output FILE` | Write results to a file; the extension picks the format. `-` writes to stdout |
| `-f, --format csv\|json\|text` | Force the output format |
| `-r, --noredirect` | Do not follow 3xx redirects |
| `-p, --proxy URL` | HTTP/SOCKS proxy for the probes |
| `-H, --headers FILE` | Replace the default header set from a text file |
| `-T, --timeout N` | Request timeout |
| `-v, --verbose` | More detail (repeatable) |
| `--no-colors` | Disable ANSI colours (use this in every scripted run) |
| `-V, --version` | Print version and exit |
| `-h, --help` | Help |

## Typical workflows

1. **Fingerprint one host before planning the scan.**

   ```bash
   wafw00f "https://$TARGET" -a --no-colors
   wafw00f "https://$TARGET" -a -f json -o $WORK/waf.json
   jq -r '.[] | select(.detected) | [.firewall, .manufacturer] | @tsv' $WORK/waf.json
   ```

2. **A list of hosts, one JSON report.**

   ```bash
   printf 'https://%s\n' $TARGET www.$TARGET api.$TARGET > $WORK/waf-targets.txt
   wafw00f -i $WORK/waf-targets.txt -a -f json -o $WORK/waf-all.json
   jq -r '.[] | select(.detected) | [.url, .firewall] | @tsv' $WORK/waf-all.json
   ```

3. **Feed a live-host list from httpx.**

   ```bash
   httpx -l $WORK/hosts.txt -silent -mc 200,301,403 > $WORK/live.txt
   wafw00f -i $WORK/live.txt -f csv -o $WORK/waf.csv
   column -s, -t $WORK/waf.csv | head
   ```

4. **Check for one specific product before choosing a bypass.**

   ```bash
   wafw00f -l | grep -i cloudflare        # exact name first
   wafw00f "https://$TARGET" -t "Cloudflare (Cloudflare Inc.)" -a --no-colors
   ```

5. **Record the decision, not just the result.** Write the fingerprint into the
   engagement note together with the scan settings it justified (lower
   concurrency, `--delay`, or abandoning a payload class).

## Output and parsing

Text output (verified, `--no-colors`):

```
[*] Checking https://example.com
[+] The site https://example.com is behind Cloudflare (Cloudflare Inc.) WAF.
[+] Generic Detection results:
[-] No WAF detected by the generic detection
[~] Number of requests: 7
```

JSON output is an **array**, one object per detection pass, with keys
`detected, firewall, manufacturer, trigger_url, url` (verified):

```json
[
  {
    "detected": true,
    "firewall": "Cloudflare",
    "manufacturer": "Cloudflare Inc.",
    "trigger_url": "https://example.com/?acwdezck=%3Cscript%3Ealert%28%22XSS%22%29%3B%3C%2Fscript%3E&otjufwdy=UNION+SELECT+ALL+FROM+information_schema…",
    "url": "https://example.com"
  },
  {
    "detected": false,
    "firewall": "None",
    "manufacturer": "None",
    "trigger_url": null,
    "url": "https://example.com"
  }
]
```

CSV output starts with
`url,trigger_url,detected,firewall,manufacturer` (verified).

```bash
# just the detections, one per line
jq -r '.[] | select(.detected==true) | "\(.url)\t\(.firewall)\t\(.manufacturer)"' $WORK/waf.json
# hosts with nothing detected
jq -r '.[] | select(.detected==false) | .url' $WORK/waf.json | sort -u
# the probe that triggered the match (useful evidence of what was sent)
jq -r '.[] | select(.detected==true) | .trigger_url' $WORK/waf.json
```

**Exit codes are always 0 (verified):** detection, no detection, and even a
closed port all exit `0`. Parse the output; `$?` carries no information.

## Chaining with the rest of the toolchain

```bash
# httpx list -> wafw00f -> decide the ffuf/nuclei rate
httpx -l $WORK/hosts.txt -silent > $WORK/live.txt
wafw00f -i $WORK/live.txt -a -f json -o $WORK/waf.json
if jq -e '.[] | select(.detected==true)' $WORK/waf.json >/dev/null; then
  RATE=5; THREADS=5          # behind a WAF: slower, and expect blocks
else
  RATE=20; THREADS=10
fi
ffuf -w $WORDLISTS/Discovery/Web-Content/common.txt -u "https://$TARGET/FUZZ" \
  -rate "$RATE" -t "$THREADS" -mc all -s -of json -o $WORK/dirs.json

# WAF fingerprint into the findings note
jq -r '.[] | select(.detected==true) | "WAF: \(.firewall) (\(.manufacturer)) via \(.url)"' $WORK/waf.json \
  >> $WORK/notes.md

# nuclei behind a WAF: expect rate limiting, so lower concurrency explicitly
nuclei -u "https://$TARGET" -rl 10 -c 5 -jsonl -o $WORK/nuclei.jsonl

# dalfox has its own WAF handling; use wafw00f's answer to pick the mode
dalfox scan "https://$TARGET/search?q=test" --waf-bypass auto --skip-waf-probe \
  --workers 2 --rate-limit 5 -f json -o $WORK/dalfox.json < /dev/null
```

## Limits, failure modes and gotchas

- **"No WAF detected by the generic detection" means exactly that: no signature
  matched.** It does not mean the target is unprotected. A WAF can be
  configured not to respond to these probes, sit behind a CDN that strips the
  tells, or only cover some paths. Record it as "not fingerprinted", not as
  "no WAF".
- **The probes are attack-shaped.** Verified in `trigger_url`: `<script>alert("XSS")`,
  `UNION SELECT ALL FROM information_schema`, `../../etc/passwd`. An IDS/WAF
  will log them and may block the source IP — which is the VPN exit node, shared
  with any other engagement using it.
- **The first result is not the whole truth.** Without `-a` wafw00f stops at the
  first matching signature; with `-a` it reports every match (verified: two
  records for `example.com`, one Cloudflare and one generic-negative). Use `-a`
  when the fingerprint feeds a decision.
- **`--list` is the authority on `-t` names.** Verified: `-t "Cloudflare"`
  failed with `WAF Cloudflare was not found in our list`; the detectable names
  are the lines printed by `wafw00f -l` (192 of them here), and names with
  spaces must be quoted.
- **Exit code 0 on every outcome**, including connection failures. A run that
  tested nothing looks identical to a clean run if you only check `$?`.
- **`-o FILE` picks the format from the extension**; `-o -` writes to stdout and
  `-f` forces the format. Mixing an explicit `-f json` with `-o file.csv`
  produces JSON inside a `.csv` file.
- **One pass is enough.** wafw00f is a fingerprint, not a scanner; running it in
  a loop adds no information and does add probe traffic.

## Safety and scope

Stop and get explicit human confirmation before:

- running wafw00f against any host not already authorized for this engagement,
  because its probes are indistinguishable from an attack in the target's logs;
- sweeping `-i` over a large host list;
- using `-p/--proxy` to route probes anywhere other than a local interception
  proxy you control;
- treating a "no WAF" result as authorization to raise concurrency. The rate
  budget comes from the engagement, not from this tool's output.
