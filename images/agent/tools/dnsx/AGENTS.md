# dnsx

Multi-purpose DNS toolkit. It resolves a list of names, queries specific record
types in bulk, brute-forces subdomains against a wordlist, and filters the
results — wildcard detection, status-code filtering, response-type filtering.
It is the resolver layer between `subfinder`'s passive name list and `httpx`'s
live-host list, and the tool that keeps an enumerated list honest.

## Installation and location

| | |
|---|---|
| Version | `1.3.1` (upstream release, sha256-verified at image build) |
| Binary | `/usr/local/bin/dnsx` |
| Config | none created by default; resolvers come from `-r` or dnsx's built-in list |
| Output | stdout, or `-o <file>` |

dnsx keeps no cache and no state between runs. `-resume` writes a resume file
in the working directory. It resolves through its own built-in list of public
resolvers unless `-r` supplies a resolver list; it does not use
`/etc/resolv.conf`, which in this image points at `nameserver 127.0.0.11` while
`dnsx -a -json` reports `"resolver":["1.0.0.1:53"]`. Pass `-r` to pin a resolver
explicitly.

```bash
dnsx -version -duc     # "Current Version: 1.3.1"
```

## Rules that apply to this tool

- **Authorization first.** Resolve and brute-force only domains Greg has
  explicitly confirmed for the current engagement. If authorization is unclear,
  it is unauthorized.
- **Egress is the tunnel.** All traffic leaves through the WireGuard interface
  in the shared network namespace. DNS is included — do not use an in-container
  or host resolver that escapes the tunnel.
- **Brute force is not passive.** `-d` with `-w` sends a DNS query per word per
  domain. That is inbound traffic to the target's nameservers and is visible to
  them. It needs the same authorization as a port scan, and it needs a
  conservative `-rl`.
- **Zone transfer is an attack, not a lookup.** `-axfr` asks the authoritative
  nameserver to hand over the whole zone. Never run it without explicit
  confirmation for the specific domain.
- **Watch for wildcards before trusting results.** A domain with `*.example.com`
  resolving makes every wordlist entry look live. Use `-auto-wildcard` or `-wd`.
- **Evidence goes to disk.** `-o $WORK/dnsx.txt`, or `-json` for structure.
- **Pass `-duc`.** No update checks against ProjectDiscovery during an
  engagement.

## Command reference

Every flag below is from `dnsx -h` on 1.3.1.

### Input

| Flag | Meaning |
|---|---|
| `-l, -list <input>` | Names to resolve. A file, comma-separated values, or stdin. |
| `-d, -domain <input>` | Domain(s) to brute-force. File, comma-separated, or stdin. |
| `-w, -wordlist <input>` | Wordlist for brute force. File, comma-separated, or stdin. |
| stdin | Default input. Piped lines are treated as names to resolve. |

There are two distinct modes. `-l` (or stdin) **resolves** names that already
exist. `-d` + `-w` **brute-forces**: it builds `word.domain` for every word and
resolves each one.

### Query types

| Flag | Record type |
|---|---|
| `-a` | A. **This is the default when no query flag is given.** |
| `-aaaa` | AAAA. |
| `-cname` | CNAME. |
| `-ns` | NS. |
| `-txt` | TXT. |
| `-srv` | SRV. |
| `-ptr` | PTR (reverse lookup; give it IPs). |
| `-mx` | MX. |
| `-soa` | SOA. |
| `-caa` | CAA. |
| `-any` | ANY. |
| `-axfr` | AXFR zone transfer. |
| `-all, -recon` | All of: a, aaaa, cname, ns, txt, srv, ptr, mx, soa, axfr, caa. |
| `-e, -exclude-type <types>` | Exclude query types. |

Multiple query flags may be combined in one run.

### Filtering and display

| Flag | Meaning |
|---|---|
| `-re, -resp` | Display the DNS response. |
| `-ro, -resp-only` | Display only the response value, not the name. |
| `-rc, -rcode <codes>` | Filter by DNS status code, e.g. `noerror,servfail,refused`. |
| `-rtf, -response-type-filter <types>` | Return entries with **no** records of the given types (e.g. `a,cname`). |
| `-wd, -wildcard-domain <domain>` | Manual wildcard filtering for this domain. Other flags are ignored. JSON output recommended. |
| `-auto-wildcard` | Detect wildcard domains automatically and filter them. Mutually exclusive with `-wd`. |
| `-wt, -wildcard-threshold <n>` | Wildcard filter threshold (default 5). |
| `-cdn` | Display CDN name. |
| `-asn` | Display host ASN information. |
| `-hf, -hostsfile` | Use the system hosts file. |
| `-trace` | Perform DNS tracing. |
| `-trace-max-recursion <n>` | Max recursion for tracing (default 255). |

### Rate and reliability

| Flag | Default | Meaning |
|---|---|---|
| `-t, -threads <n>` | 100 | Concurrent threads. **This is threads, not templates.** |
| `-rl, -rate-limit <n>` | -1 (disabled) | DNS requests per second. Set it. |
| `-retry <n>` | 2 | DNS attempts (minimum 1). |
| `-timeout <d>` | 3s | Timeout per DNS query. |
| `-stream` | off | Stream mode; disables wordlist, wildcard, stats and resume. |
| `-resume` | off | Resume an existing scan. |

### Output

| Flag | Meaning |
|---|---|
| `-json, -j` | JSONL output. |
| `-o, -output <file>` | Write output to a file. |
| `-omit-raw, -or` | Omit the raw DNS response from JSONL output. |
| `-ot, -output-template <tpl>` | Custom output template, e.g. `-ot '{{host}} {{a}}'`. |
| `-silent` | Results only, no banner or log lines. |
| `-nc, -no-color` | No ANSI colour. |
| `-v, -verbose` | Verbose output. |
| `-raw, -debug` | Display the raw DNS response. **`-raw` is a debug display flag, not a "raw output" mode.** |
| `-stats` | Display running statistics. |
| `-duc, -disable-update-check` | Skip the update check. Use always. |
| `-up, -update` | Update the binary. Do not use inside this image. |

### Resolvers and proxy

| Flag | Meaning |
|---|---|
| `-r, -resolver <list>` | Resolvers to use: file or comma-separated. |
| `-proxy <url>` | Proxy, e.g. `socks5://127.0.0.1:8080`. Not needed here. |

## Typical workflows

1. **Resolve a name list, keeping the name with its address.** This is the
   standard hand-off from `subfinder`:

   ```bash
   subfinder -d "$DOMAIN" -silent -rl 5 -duc \
     | dnsx -silent -a -resp -rl 50 -duc \
     | tee "$WORK/resolved.txt"
   ```

2. **Addresses only**, when the next tool wants IPs:

   ```bash
   subfinder -d "$DOMAIN" -silent -rl 5 -duc \
     | dnsx -silent -a -resp-only -rl 50 -duc > "$WORK/ips.txt"
   ```

3. **Check a specific record type across many names.** For example, which
   hosts have MX records (mail infrastructure):

   ```bash
   dnsx -l "$WORK/subdomains.txt" -silent -mx -resp -rl 50 -duc
   ```

4. **Reverse-resolve an IP range** to find names (PTR):

   ```bash
   dnsx -l "$WORK/ips.txt" -silent -ptr -resp -rl 50 -duc
   ```

5. **Brute-force a small, targeted wordlist** on an authorized domain:

   ```bash
   dnsx -d "$DOMAIN" -w /opt/wordlists/SecLists/Discovery/DNS/subdomains-top1million-5000.txt \
     -silent -a -resp -rl 25 -t 25 -auto-wildcard -duc \
     -o "$WORK/dnsx-brute.txt"
   ```

6. **Find dangling records.** Names that exist but have no A record are
   subdomain-takeover candidates:

   ```bash
   dnsx -l "$WORK/subdomains.txt" -silent -cname -rtf a -json -rl 50 -duc \
     -o "$WORK/dangling.jsonl"
   ```

7. **Full record dump for one domain.**

   ```bash
   echo "$DOMAIN" | dnsx -silent -all -json -rl 10 -duc -o "$WORK/dnsx-all.jsonl"
   ```

## Output and parsing

Plain output behaviour is worth knowing before parsing it:

- `dnsx -a` alone prints **just the hostname** (`example.com`), not the address.
- `dnsx -a -resp` prints `host [A] [address]`, one line per record.
- `dnsx -a -resp-only` prints just the address.
- `dnsx -rcode noerror` prints `host [NOERROR]`.
- `-ot '{{host}} {{a}}'` prints `example.com 172.66.147.243,104.20.23.154`.

`-json` emits one object per result. Verified key set for a plain A query:

```
host  ttl  resolver  a  all  status_code  timestamp  query-time
```

| Field | Meaning |
|---|---|
| `.host` | The name that was queried. |
| `.ttl` | Record TTL. |
| `.resolver` | Resolvers that answered — **an array**, and with `-all` it lists every resolver tried: `["1.0.0.1:53","8.8.8.8:53","8.8.4.4:53","9.9.9.9:53","149.112.112.112:53","208.67.222.222:53","208.67.220.220:53","1.1.1.1:53"]`. |
| `.a` | A records (array of strings). |
| `.aaaa` | AAAA records. |
| `.cname` / `.ns` / `.mx` / `.txt` / `.srv` / `.ptr` / `.caa` | Present only when that record type was queried. |
| `.soa` | **An object, not an array**, with `name`, `ns`, `mailbox`, `serial`, `refresh`, … |
| `.all` | Raw record strings for the query. **Removed by `-or`**; there is no field called `raw`. |
| `.status_code` | DNS response code, e.g. `NOERROR`. |
| `.timestamp` | When the record was observed. |
| `."query-time"` | Query duration, e.g. `1ms`. The hyphen means it needs quoting in `jq`. |

Verified key sets:

- `dnsx -a -json` → `host, ttl, resolver, a, all, status_code, timestamp, query-time`
- `dnsx -all -json` → `host, ttl, resolver, a, aaaa, mx, soa, ns, txt, all, status_code, axfr, timestamp, query-time`

Two shapes that catch people out: an MX lookup on a domain with no mail
records returns `"mx":[""]` — an array containing an empty string, not an empty
array — and `-all` adds an `axfr` key alongside the record types.

Verified lines:

```json
{"host":"example.com","ttl":160,"resolver":["1.0.0.1:53"],"a":["172.66.147.243","104.20.23.154"],
 "all":["example.com.\t160\tIN\tA\t172.66.147.243","example.com.\t160\tIN\tA\t104.20.23.154"],
 "status_code":"NOERROR","timestamp":"2026-09-17T20:44:15.738972023Z","query-time":"1ms"}
```

```json
{"host":"example.com","ttl":300,"resolver":["1.0.0.1:53","8.8.8.8:53","8.8.4.4:53"],
 "mx":[""],"ns":["hera.ns.cloudflare.com","elliott.ns.cloudflare.com"],
 "txt":["v=spf1 -all","_k2n1y4vw3qtb4skdx9e7dxt97qrmmq9"],
 "all":["example.com.\t300\tIN\tTXT\t\"v=spf1 -all\"","..."],
 "status_code":"NOERROR","timestamp":"2026-09-17T21:04:38.653708716Z","query-time":"4ms"}
```

```bash
# name to address, one line each
jq -r 'select(.a) | "\(.host)\t\(.a | join(","))"' "$WORK/dnsx.jsonl"

# names that resolved to nothing — dead ends or dangling records
jq -r 'select((.a // []) | length == 0) | .host' "$WORK/dnsx.jsonl"

# CNAME chains, for takeover analysis
jq -r 'select(.cname) | "\(.host)\t\(.cname | join(","))"' "$WORK/dnsx.jsonl"

# status-code histogram — how much of the list was NXDOMAIN
jq -r '.status_code' "$WORK/dnsx.jsonl" | sort | uniq -c | sort -rn

# compact output without the raw record strings
dnsx -l "$WORK/subdomains.txt" -silent -a -json -or -rl 50 -duc \
  | jq -c '{host, a}'
```

`-ot` is often simpler than `jq` for a flat table:

```bash
dnsx -l "$WORK/subdomains.txt" -silent -a -ot '{{host}} {{a}}' -rl 50 -duc
```

## Chaining with the rest of the toolchain

The hand-off order is `subfinder | dnsx | httpx`, then `nuclei`. dnsx reads one
name per line on stdin and writes one result per line.

```bash
# subdomains -> resolved names -> live HTTP -> scan
subfinder -d "$DOMAIN" -silent -rl 5 -duc \
  | dnsx -silent -a -resp -rl 50 -duc \
  | httpx -silent -sc -title -td -duc \
  | tee "$WORK/live.txt" \
  | nuclei -severity medium,high,critical -ni -rl 25 -c 10 -silent -jsonl -duc

# names -> ports -> live HTTP
subfinder -d "$DOMAIN" -silent -rl 5 -duc \
  | dnsx -silent -a -resp-only -rl 50 -duc \
  | naabu -top-ports 100 -rate 100 -c 10 -silent -duc \
  | httpx -silent -sc -title -duc
```

- `dnsx -a -resp` keeps the query name, which is what `httpx` needs for a
  correct Host header and TLS SNI. Use `-resp-only` only when a downstream tool
  genuinely wants bare IPs.
- `dnsx -json` output is not directly consumable by `httpx` or `nuclei`; use
  `jq -r '.host'` to get back to a name list.
- dnsx runs before httpx because probing a name that does not resolve wastes a
  connection attempt and produces a `.failed` entry in httpx output.
- `naabu` resolves names itself, so a dnsx step before naabu is optional; it is
  worth it when you also want the record data for the report.

## Limits, failure modes and gotchas

- **`-t` is threads here, not templates.** In nuclei `-t` selects templates.
  The letters collide across the toolchain; check before copying a command.
- **`-raw` is a debug display flag**, not a raw-output mode. `-or` (omit raw)
  is the flag that removes the raw record strings from JSON output, by dropping
  the `all` key. They read as opposites and are unrelated.
- **`-resp-only` and `-a` alone are different from `-a -resp`.** `-a` with no
  display flag prints only the hostname; `-resp` adds the record type and value;
  `-resp-only` prints only the value. Picking the wrong one silently changes the
  output shape a pipeline consumes.
- **`/etc/hosts` is not read unless `-hf` is passed.** `echo localhost | dnsx -a
  -resp -silent` still prints `localhost [A] [127.0.0.1]`; that answer comes from
  DNS. dnsx asks DNS, not the resolver library.
- **Rate limiting is off by default.** `-rl` defaults to `-1`, meaning
  unlimited, with 100 threads. Against a target's nameserver that is a
  denial-of-service shape. Always set `-rl` explicitly on an engagement.
- **Wildcard DNS silently inflates results.** If `*.example.com` resolves, a
  `-d`/`-w` brute force reports every wordlist entry as live. Use
  `-auto-wildcard` (automatic) or `-wd` (manual). `-wd` ignores your other
  flags, so use it as a separate filtering pass over JSON.
- **`-stream` disables wildcard filtering and the wordlist path.** By its own
  help text it turns off wordlist, wildcard, stats and stop/resume. Do not
  combine it with a brute force and expect wildcard filtering.
- **`-axfr` almost always fails, and that is the normal result.** A refused
  zone transfer is the expected outcome on a correctly configured nameserver;
  it is not an error to retry harder. It is also an intrusive request that needs
  explicit authorization.
- **`-trace` queries authoritative nameservers directly.** That is a different
  traffic pattern from a recursive lookup and is visible to the zone's own
  infrastructure. Without `-resp` it prints only the name, which makes a
  successful trace look like a failed one.
- **dnsx does not use `/etc/resolv.conf`.** Without `-r` it queries its own
  built-in public resolver list; in this image `/etc/resolv.conf` points at
  `nameserver 127.0.0.11`, yet `dnsx -a -json` reports
  `"resolver":["1.0.0.1:53"]`. Pass `-r` with a known resolver list when the
  resolver identity matters for reproducibility, and note that DNS still has to
  leave through the tunnel.
- **`-resp-only` discards the name.** It is convenient for `naabu`, but it
  makes the result set impossible to attribute afterwards. Prefer `-a -resp`
  and reduce with `jq` when the name matters.
- **A failed lookup and a filtered lookup look the same in plain output.** Both
  print nothing. Use `-json` and check `.status_code`, or count with `-stats`.
- **Reverse lookups are not a way to enumerate.** `echo 127.0.0.1 | dnsx -ptr`
  prints `127.0.0.1 [PTR] [localhost]`, but most addresses in a range have no
  PTR record. Empty PTR output is the normal case, not a bug.
- **`-rcode` values are uppercase in the response but lowercase on the command
  line** (`-rcode noerror`). Getting the case wrong silently filters everything.
- **`-rtf` is an absence filter.** It returns entries with *no* records of the
  given type, which is the opposite of what a passing reading suggests. It is
  the right tool for finding dangling CNAMEs and the wrong tool for confirming
  a record exists.
- **`-any` is widely refused.** Many resolvers and authoritative servers return
  a minimal or empty answer to ANY queries per RFC 8482. Absence of results
  from `-any` proves nothing.

## Safety and scope

Requires explicit human confirmation before running:

- Any domain not already confirmed for this engagement.
- Any brute force (`-d` with `-w`), because it sends a query per word to the
  target's nameservers and is not passive enumeration.
- `-axfr` (zone transfer) on any domain, in any circumstance.
- `-trace`, which queries authoritative nameservers directly.
- Any run without an explicit `-rl`, since the default is unlimited.
- DNS resolution through a resolver outside the tunnel, or pointing `-r` at a
  public resolver not covered by the engagement.
