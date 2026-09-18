# subfinder

Passive subdomain enumeration. It queries public sources — certificate
transparency logs, search engines, threat-intelligence APIs, DNS datasets — and
returns the subdomains those sources already know about, without touching the
target's own DNS. It is the first step of external recon: it produces the name
list that `dnsx` resolves and `httpx` probes.

## Installation and location

| | |
|---|---|
| Version | `2.16.0` (upstream release, sha256-verified at image build) |
| Binary | `/usr/local/bin/subfinder` |
| Config | `/root/.config/subfinder/config.yaml` |
| Provider keys | `/root/.config/subfinder/provider-config.yaml` |
| Output | stdout, or `-o <file>`; `-oD <dir>` with `-dL` |

Subfinder caches nothing between runs. It has no local database; every run
re-queries the sources, which is why the same query can return different
results an hour apart.

```bash
subfinder -version -duc     # "Current Version: v2.16.0" + config directory
subfinder -ls -duc          # every source, with key requirements marked
```

## Rules that apply to this tool

- **Authorization first.** Enumerate only domains Greg has explicitly confirmed
  for the current engagement. Subdomain enumeration of a domain you have not
  been asked to test is reconnaissance of a third party, even though it is
  "passive" — it queries third-party databases about someone else's estate.
- **Egress is the tunnel.** All traffic leaves through the WireGuard interface
  in the shared network namespace. Subfinder's requests go to public APIs, not
  to the target, but they are still attributable traffic that must leave
  through the tunnel.
- **Keep the rate limit on.** `-rl` caps global requests per second; `-rls`
  caps per-provider. Many free sources rate-limit or temporarily ban on
  overuse. Start at `-rl 5` and raise only if a run is genuinely too slow.
- **Bound the run.** `-max-time` (default 10 minutes) and `-timeout` (default
  30s) keep a wedged source from hanging the engagement. Do not remove them.
- **`-all` is slower and noisier, not better.** The default source set is the
  subset that works without API keys and gives reliable results. `-all` adds
  keyed and experimental sources that mostly fail without credentials.
- **No API keys are configured in this image.** Sources marked `*` in `-ls`
  will return nothing. Do not present a keyed source's silence as a negative
  finding.
- **Evidence goes to disk.** `-o $WORK/subfinder.txt` (or `-oJ` for JSONL).
- **Pass `-duc`.** No update checks against ProjectDiscovery during an
  engagement.

## Command reference

Every flag below is from `subfinder -h` on 2.16.0.

### Input

| Flag | Meaning |
|---|---|
| `-d, -domain string[]` | Domain(s) to enumerate. Repeatable or comma-separated. |
| `-dL, -list <file>` | File of domains, one per line. Combine with `-oD` for per-domain output files. |
| stdin | Accepted when neither `-d` nor `-dL` is given. |

### Sources

| Flag | Meaning |
|---|---|
| `-s, -sources string[]` | Use only these sources. `-ls` lists the valid names. |
| `-es, -exclude-sources string[]` | Exclude these sources. |
| `-all` | Use every source, including ones needing keys. Slow. |
| `-recursive` | Use only sources that support recursive enumeration. |
| `-ls, -list-sources` | List all available sources and exit. `-oJ` gives JSON. |
| `-cs, -collect-sources` | Include the source that produced each result. **JSON output only.** |

`-ls` marks key requirements:

- `*` — requires an API key or token. Returns nothing without one.
- `~` — optionally supports a key for better results.

On this image, with no keys configured, the sources that actually return data
are the unmarked ones, which include `crtsh`, `commoncrawl`, `waybackarchive`,
`anubis`, `digitorus`, `hudsonrock`, `rapiddns`, `sitedossier`, `thc`,
`threatcrowd`, `scanmalware`, `shodanct`, plus `hackertarget` and `reconeer`
which work unkeyed at reduced result counts.

### Filtering

| Flag | Meaning |
|---|---|
| `-m, -match string[]` | Only output subdomains matching these strings or file entries. |
| `-f, -filter string[]` | Drop subdomains matching these strings or file entries. |
| `-ei, -exclude-ip` | Drop results that are IP addresses rather than names. |
| `-nW, -active` | Resolve results and output only names that resolve. |
| `-oI, -ip` | Include the resolved host IP. `-active` only. |

### Rate, timeouts and resolution

| Flag | Default | Meaning |
|---|---|---|
| `-rl, -rate-limit <n>` | none | Global max HTTP requests per second across all sources. |
| `-rls <provider=n/s>` | per-provider table | Per-provider rate limit, `key=value` format, e.g. `-rls hackertarget=10/m`. |
| `-t <n>` | 10 | Concurrent goroutines for resolving. `-active` only. |
| `-timeout <s>` | 30 | Per-request timeout. |
| `-max-time <min>` | 10 | Minutes to wait for enumeration results. |
| `-mr, -max-results <n>` | 0 (unlimited) | Results per source. Paginating sources honour it. |
| `-rsr, -response-size-read <n>` | 0 (unlimited) | Max response body size read per passive source. |
| `-r string[]` | | Comma-separated resolvers for `-active`. |
| `-rL, -rlist <file>` | | File of resolvers. |
| `-proxy <url>` | | HTTP proxy. Not needed here. |

The default per-provider limits are baked into `-h` and include
`github=30/m`, `fullhunt=60/m`, `pugrecon=10/s`, `securitytrails=1/s`,
`shodan=1/s`, `virustotal=4/m`, `hackertarget=2/s`, `waybackarchive=15/m`,
`whoisxmlapi=50/s`, `sitedossier=8/m`, `netlas=1/s`, `github=83/m`,
`hudsonrock=5/s`, `urlscan=1/s`. Overriding `-rls` for a keyless source with a
stricter value is the right response to a temporary ban.

### Output

| Flag | Meaning |
|---|---|
| `-o, -output <file>` | Write results to a file. |
| `-oJ, -json` | JSONL output. |
| `-oD, -output-dir <dir>` | Per-domain output files. `-dL` only. |
| `-cs, -collect-sources` | Include source attribution. `-json` only. |
| `-silent` | Names only, no banner or log lines. |
| `-nc, -no-color` | No ANSI colour. |
| `-v` | Verbose: show sources as they are queried. |
| `-stats` | Report per-source statistics. |
| `-duc, -disable-update-check` | Skip the update check. Use always. |
| `-up, -update` | Update the binary. Do not use inside this image. |

### Configuration

| Flag | Meaning |
|---|---|
| `-config <file>` | Alternate config file. |
| `-pc, -provider-config <file>` | Alternate provider key file. |

## Typical workflows

1. **Baseline enumeration of one domain.**

   ```bash
   subfinder -d "$DOMAIN" -silent -nc -rl 5 -duc -o "$WORK/subfinder.txt"
   wc -l "$WORK/subfinder.txt"
   ```

2. **Enumeration with source attribution**, so a thin result set can be
   explained:

   ```bash
   subfinder -d "$DOMAIN" -silent -json -cs -rl 5 -duc \
     -o "$WORK/subfinder.jsonl"
   jq -r '.sources[]?' "$WORK/subfinder.jsonl" | sort | uniq -c | sort -rn
   ```

3. **Resolve as you enumerate.** Trades time and DNS traffic for a list of
   names that actually exist:

   ```bash
   subfinder -d "$DOMAIN" -silent -active -oI -rl 5 -t 5 -duc \
     -o "$WORK/subfinder-active.txt"
   ```

4. **Several domains at once, one output file each.**

   ```bash
   printf '%s\n' "$DOMAIN" "$DOMAIN2" > "$WORK/domains.txt"
   subfinder -dL "$WORK/domains.txt" -oD "$WORK/subfinder-out" -silent -rl 5 -duc
   ls "$WORK/subfinder-out"
   ```

5. **Restrict to the sources that are known to work unkeyed**, when speed
   matters more than coverage:

   ```bash
   subfinder -d "$DOMAIN" -s crtsh,commoncrawl,waybackarchive,rapiddns,thc \
     -silent -nc -rl 5 -duc
   ```

6. **Feed the pipeline.** See *Chaining*.

## Output and parsing

Plain output is one subdomain per line. With `-json` each line is an object.
Verified key sets — note the source field changes name and shape with `-cs`:

| Invocation | Keys emitted |
|---|---|
| `-json` | `host`, `input`, `source` |
| `-json -cs` | `host`, `input`, `sources` |

| Field | Meaning |
|---|---|
| `.host` | The discovered subdomain. |
| `.input` | The domain that was queried. |
| `.source` | Which source produced it, as a string. Present without `-cs`. |
| `.sources` | **Array** of sources. Present with `-cs` instead of `source`. |
| `.ip` | Resolved IP. Only with `-active -ip`. |

```json
{"host":"nttcheap11.example.com","input":"example.com","source":"anubis"}
{"host":"kevinhouston.example.com","input":"example.com","sources":["anubis"]}
```

```bash
# the name list, deduplicated
jq -r '.host' "$WORK/subfinder.jsonl" | sort -u

# which sources are actually contributing
jq -r '.source // (.sources[]?)' "$WORK/subfinder.jsonl" | sort | uniq -c | sort -rn

# names in a specific subdomain tree
jq -r 'select(.host | test("^api\\.")) | .host' "$WORK/subfinder.jsonl"

# everything except the apex and www
jq -r '.host' "$WORK/subfinder.jsonl" \
  | grep -vE '^(www\.)?'"$(echo "$DOMAIN" | sed 's/\./\\./g')"'$' | sort -u
```

**Expect most results not to resolve.** A keyless run against `example.com`
returned 509 names, sourced mostly from `anubis`, and the great majority were
stale or junk hostnames (`zhulduz7524528.golubeva.example.com`,
`sub188.example.com`) that no longer exist in DNS. Resolving the first 300 of
them with `dnsx` yielded zero live hosts. That is normal for passive
enumeration: the name list is a *candidate* list, and only `dnsx` or `httpx`
turn it into facts. Report the count of resolved hosts, never the count of
enumerated names.

A run that returns nothing at all usually means the sources were rate-limited,
timed out, or egress is down — not that the domain has no subdomains. Check
with `-stats` and `-v`, and try a single known-good source
(`-s crtsh`) to isolate whether the problem is the network or the source set.

## Chaining with the rest of the toolchain

Subfinder writes one name per line, which is exactly what `dnsx` reads.

```bash
# names -> resolved -> live web services -> scan
subfinder -d "$DOMAIN" -silent -rl 5 -duc \
  | dnsx -silent -a -resp -duc \
  | httpx -silent -sc -title -td -duc \
  | tee "$WORK/live-hosts.txt" \
  | nuclei -severity medium,high,critical -ni -rl 25 -c 10 -silent -jsonl -duc \
      -o "$WORK/nuclei.jsonl"

# names -> ports -> web services
subfinder -d "$DOMAIN" -silent -rl 5 -duc \
  | naabu -top-ports 100 -silent -rate 100 -c 10 -duc \
  | httpx -silent -sc -title -duc
```

- `dnsx` resolves; do not skip it. Most of what passive sources return is stale
  or junk and no longer exists in DNS — on `example.com` the first 300
  enumerated names produced zero resolutions.
- `dnsx -resp-only` emits bare IPs, which loses the hostname. When vhosts
  matter, use `dnsx -a -resp` and keep the name.
- `subfinder -active` does resolution itself, but `dnsx` gives control over
  resolvers, wildcard filtering and record types; prefer the pipeline when the
  result matters.
- Feed `httpx` the names, not the IPs, so the Host header and TLS SNI are
  correct.

## Limits, failure modes and gotchas

- **Passive only.** Subfinder never asks the target's own nameservers. Results
  are limited to what public sources already recorded, and a private or
  recently created subdomain will not appear no matter how many sources run.
- **Most sources need API keys and none are configured here.** `-ls` marks them
  with `*`. A keyed source silently contributes nothing. Do not read that as
  "the subdomain does not exist".
- **`-all` does not fix the key problem.** It enables the keyed sources, which
  fail without credentials, and slows the run down. Use the default set.
- **Free sources rate-limit and ban.** crt.sh in particular returns 429s or
  hangs under load. The symptom is a run that returns fewer names than the
  previous one. Slow down with `-rl 5` or `-rls crtsh=10/m`, or wait.
- **The same query gives different results at different times.** Sources come
  and go. A negative result is only meaningful alongside `-stats` and `-v`
  output showing the sources actually answered.
- **`-cs` requires `-json`.** With plain output the source attribution is
  silently dropped.
- **`-oI` requires `-active`.** Without resolution there is no IP to include.
- **`-t` is not a rate limit.** It is goroutine count for the `-active`
  resolver step and is ignored otherwise.
- **`-max-time` truncates silently.** A run that hits the 10-minute default
  prints what it has and exits 0. On a large domain, raise it deliberately and
  record that you did.
- **Subdomains returned are not subdomains that exist.** Many are
  decommissioned, wildcard-derived, or belong to a different owner after a
  domain transfer. Always resolve before reporting.
- **Wildcard DNS breaks naive resolution.** If `*.domain` resolves, every
  candidate name resolves. `dnsx -auto-wildcard` (or `-wd`) is the filter for
  that; without it a wildcard domain looks like it has thousands of live hosts.
- **`-duc` matters here.** Without it each invocation performs an update check
  against ProjectDiscovery's API, which is unnecessary third-party traffic
  during an engagement.

## Safety and scope

Requires explicit human confirmation before running:

- Any domain not already confirmed for this engagement. Passive enumeration of
  a third party's estate is still reconnaissance of that third party.
- `-all` (enables keyed and experimental sources; slower, noisier, and may
  breach a provider's terms without keys).
- `-active` (adds DNS traffic to the target's nameservers, which is no longer
  passive).
- Configuring provider API keys — that stores a credential in the container and
  attributes queries to it.
- Enumerating a domain that is not Greg's, even for "just a quick check".
