# naabu

Fast port scanner written in Go. It takes hostnames, IPs or CIDRs and reports
which TCP ports are open, with a native SYN path and a CONNECT fallback, plus
optional host discovery and nmap service detection. It is the first active step
against a confirmed target: it turns a name or address into the port list that
`httpx` then turns into a live-service list.

## Installation and location

| | |
|---|---|
| Version | `2.6.1` (upstream release, sha256-verified at image build) |
| Binary | `/usr/local/bin/naabu` |
| Config | `/root/.config/naabu/config.yaml` (`-config` overrides) |
| Resume file | `resume.cfg` in the working directory, with `-resume` |
| Output | stdout, or `-o <file>` |

naabu is stateless between runs. It caches nothing; `-resume` reads and writes
`resume.cfg` in the current directory.

```bash
naabu -version -duc     # "Current Version: 2.6.1"
naabu -hc -duc          # diagnostic check
```

## Rules that apply to this tool

- **Authorization first.** Port-scan only hosts Greg has explicitly confirmed
  for the current engagement. If a target's authorization is unclear, it is
  unauthorized.
- **Scanning ports is the most intrusive thing this toolchain does first.**
  Even a top-100 scan is 100 connection attempts per host, and a full-range
  scan is 65,535. Confirm the target tolerates it before widening the range.
- **Egress is the tunnel.** All traffic leaves through the WireGuard interface
  in the shared network namespace. There is no `naabu` proxy setting that
  provides attribution control; containment is the topology.
- **Keep the rate low.** Defaults are `-rate 1000` packets per second and
  `-c 25`. That is a lot of traffic from a VPN exit towards someone else's
  host. Start at `-rate 100 -c 10` and raise only with a reason.
- **Know which scan type you are running.** The default is CONNECT (`-s c`),
  an ordinary TCP handshake needing no raw sockets; SYN (`-s s`) needs root and
  `CAP_NET_RAW` and is faster, but sees ports that CONNECT can miss through a
  filtered path. The agent runs as root in this container by design, so both are
  available — pick deliberately and record which one produced a result.
- **Use `-top-ports` before `-p -`.** A full 65,535-port sweep is a different
  conversation from a top-1000 scan. Escalate deliberately.
- **`-passive` is not passive for privacy.** It sends the target's address to
  Shodan's InternetDB API. That is a third party learning which host you are
  interested in.
- **`-nmap-cli` shells out to nmap**, which is present in the image. That
  inherits nmap's own rate and detection behaviour; it is not a free add-on.
- **Evidence goes to disk.** `-json -o $WORK/naabu.jsonl`.
- **Pass `-duc`.** No update checks against ProjectDiscovery during an
  engagement.

## Command reference

Every flag below is from `naabu -h` on 2.6.1.

### Input

| Flag | Meaning |
|---|---|
| `-host string[]` | Hosts to scan. Comma-separated, repeatable. |
| `-list, -l <file>` | File of hosts, one per line. |
| `-exclude-hosts, -eh <hosts>` | Hosts to exclude, comma-separated. |
| `-exclude-file, -ef <file>` | File of hosts to exclude. |
| stdin | Hosts are read from stdin by default. |
| `-no-stdin` | Disable stdin processing. |
| `-irt, -input-read-timeout <d>` | Input read timeout (default 3m). |

### Port selection

| Flag | Meaning |
|---|---|
| `-port, -p <spec>` | Ports to scan: `80,443,100-200`. |
| `-top-ports, -tp <n>` | Top ports: `100` (default), `1000`, or `full`. |
| `-exclude-ports, -ep <spec>` | Ports to exclude (file or comma-separated). |
| `-ports-file, -pf <spec>` | List of ports to scan (file or comma-separated). |
| `-port-threshold, -pts <n>` | Port threshold to skip the port scan for a host. |
| `-exclude-cdn, -ec` | Skip full port scans for CDN/WAF hosts; scan only 80 and 443. |
| `-display-cdn, -cdn` | Display the CDN in use. |

### Scan type and host discovery

| Flag | Default | Meaning |
|---|---|---|
| `-scan-type, -s <t>` | `c` | `c` for CONNECT, `s` for SYN. |
| `-sn, -host-discovery` | off | Perform host discovery only. |
| `-Pn, -skip-host-discovery` | off | Skip host discovery. |
| `-wn, -with-host-discovery` | off | Enable host discovery. |
| `-ps, -probe-tcp-syn <ports>` | | TCP SYN ping. |
| `-pa, -probe-tcp-ack <ports>` | | TCP ACK ping. |
| `-pe, -probe-icmp-echo` | off | ICMP echo ping. |
| `-pp, -probe-icmp-timestamp` | off | ICMP timestamp ping. |
| `-pm, -probe-icmp-address-mask` | off | ICMP address-mask ping. |
| `-arp, -arp-ping` | off | ARP ping. |
| `-nd, -nd-ping` | off | IPv6 neighbour discovery. |
| `-rev-ptr` | off | Reverse PTR lookup for input IPs. |
| `-verify` | off | Re-validate open ports with a TCP verification. |
| `-ping` | off | Ping probes for host verification. |

### Rate and reliability

| Flag | Default | Meaning |
|---|---|---|
| `-rate <n>` | 1000 | Packets to send per second. |
| `-c <n>` | 25 | Internal worker threads. |
| `-retries <n>` | 3 | Retries for the port scan. |
| `-timeout <d>` | 1s | Wait before a port is considered timed out. |
| `-warm-up-time <s>` | 2 | Seconds between scan phases. |
| `-ss, -smart-scan` | off | Predictive port scanning using a port-correlation model. |
| `-pt, -prediction-threshold <n>` | 20 | Minimum confidence for port predictions (0-100%). |
| `-stream` | off | Stream mode; disables resume, nmap, verify, retries and shuffling. |
| `-resume` | off | Resume using `resume.cfg`. |

### Service detection

| Flag | Meaning |
|---|---|
| `-sD, -service-discovery` | **Not implemented in 2.6.1.** Aborts with `[FTL] Program exiting: service discovery feature is not implemented`. |
| `-sV, -service-version` | **Not implemented in 2.6.1.** Same fatal error as `-sD`. |
| `-nmap-cli <cmd>` | Run an nmap command on found results, e.g. `-nmap-cli 'nmap -sV'`. Verified working; nmap is installed. |
| `-nmap` | Invoke nmap on targets. **Deprecated** in `-h`. |

### Network and resolution

| Flag | Default | Meaning |
|---|---|---|
| `-ip-version, -iv <v>` | `4,6` | IP versions to scan of a hostname. |
| `-scan-all-ips, -sa` | off | Scan every IP a DNS record resolves to. |
| `-r <list>` | | Custom resolvers, comma-separated or from a file. |
| `-sr, -system-resolver` | off | Use the system DNS as a fallback resolver. |
| `-dns-order <o>` | `l` | DNS resolution order: `p`, `l`, `lp`, `pl`. |
| `-interface, -i <name>` | | Network interface to use for the scan. |
| `-interface-list, -il` | | List available interfaces and public IP. |
| `-source-ip <ip:port>` | | Source IP and port. |
| `-proxy <url>` | | SOCKS5 proxy. Not needed here. |
| `-proxy-auth <user:pass>` | | SOCKS5 proxy authentication. |

### Output

| Flag | Meaning |
|---|---|
| `-json, -j` | JSONL output. |
| `-o, -output <file>` | Write output to a file. |
| `-csv` | CSV output. |
| `-silent` | Results only, no banner or log lines. |
| `-lof, -list-output-fields <fields>` | Prints the available output field names; does not filter output. |
| `-eof, -exclude-output-fields <fields>` | Drop these output fields, by their internal names. |
| `-stats` | Display running statistics. **Deprecated** in `-h`. |
| `-si, -stats-interval <s>` | Stats interval. **Deprecated** in `-h`. |
| `-v, -verbose` | Verbose output. |
| `-debug` | Debugging output. |
| `-nc, -no-color` | No ANSI colour. |
| `-hc, -health-check` | Diagnostic check. |
| `-mp, -metrics-port <port>` | Metrics port (default 63636). |
| `-duc, -disable-update-check` | Skip the update check. Use always. |
| `-up, -update` | Update the binary. Do not use inside this image. |

### Cloud (leave alone)

`-auth`, `-ac`, `-pd`, `-dashboard`, `-tid`, `-aid`, `-aname`, `-pdu` upload
results to ProjectDiscovery Cloud. Do not use them; findings leave the machine.

## Typical workflows

1. **Top ports on one host, conservative rate.**

   ```bash
   naabu -host "$TARGET" -top-ports 100 -rate 100 -c 10 -silent -duc \
     -o "$WORK/naabu-top100.txt"
   ```

2. **Named ports, JSON for the pipeline.**

   ```bash
   naabu -host "$TARGET" -p 22,80,443,3000,8000,8080,8443 \
     -rate 100 -c 10 -json -silent -duc -o "$WORK/naabu.jsonl"
   jq -r 'if .host then "\(.host):\(.port)" else "\(.ip):\(.port)" end' "$WORK/naabu.jsonl"
   ```

3. **Fast SYN scan of a specific port set** (requires root — which the agent
   has):

   ```bash
   naabu -host "$TARGET" -p 1-1024 -s s -rate 200 -c 10 -silent -duc
   ```

4. **Sweep a host list from subfinder or dnsx.**

   ```bash
   dnsx -l "$WORK/subdomains.txt" -silent -a -resp-only -rl 50 -duc \
     | naabu -top-ports 100 -rate 100 -c 10 -silent -duc \
     | httpx -silent -sc -title -duc
   ```

5. **Skip CDN hosts so the scan does not hammer an edge network.**

   ```bash
   naabu -list "$WORK/hosts.txt" -top-ports 100 -exclude-cdn -rate 100 -c 10 \
     -silent -duc -o "$WORK/naabu-nocdn.txt"
   ```

6. **Add service versions with nmap for the ports that opened.**

   ```bash
   naabu -host "$TARGET" -top-ports 100 -rate 100 -c 10 -silent -duc \
     -nmap-cli 'nmap -sV -Pn'
   ```

7. **Confirm the scan actually ran.** `-verify` re-checks each discovered port
   over TCP, which removes false positives from filtered networks:

   ```bash
   naabu -host "$TARGET" -top-ports 1000 -verify -rate 100 -c 10 -silent -duc
   ```

## Output and parsing

Plain output is one `host:port` per line — the exact form `httpx` consumes:

```
scanme.nmap.org:22
scanme.nmap.org:80
```

With `-json`, each line is an object. The key set depends on the input form:

- **Hostname input** — `host, ip, timestamp, port, protocol, tls`
- **Bare-IP input** — `ip, timestamp, port, protocol, tls` (no `host` key)

```json
{"host":"localhost","ip":"127.0.0.1","timestamp":"2026-09-17T20:48:41.824739243Z","port":8099,"protocol":"tcp","tls":false}
```

A single open port can appear on more than one line: in the verification run one
open loopback port produced two `-json` lines about 2 seconds apart while
`-silent` printed one, so a naive line count over `-json` output can
double-count.

| Field | Meaning |
|---|---|
| `.host` | Host as supplied. **Absent when the input was an IP.** |
| `.ip` | Resolved IP that answered. |
| `.port` | Open port. |
| `.protocol` | Transport protocol, always `tcp` in this build. |
| `.timestamp` | When the port was found. |
| `.tls` | Whether the port looks like TLS. |
| `.service`, `.version`, `.product`, … | nmap-derived fields from `-nmap-cli`, not naabu itself. |

`-eof` removes fields and takes the internal names that `-lof` prints (24 of
them, including `host`, `ip`, `port`, `protocol`, `tls`, `cdnname`,
`iscdnip`, `product`, `version`). `-lof` itself prints that list and produces
no scan output.

```bash
# back to the host:port form the rest of the toolchain wants
jq -r 'if .host then "\(.host):\(.port)" else "\(.ip):\(.port)" end' "$WORK/naabu.jsonl"

# unique open ports across a fleet
jq -r '.port' "$WORK/naabu.jsonl" | sort -n | uniq -c | sort -rn

# hosts with anything interesting open
jq -r 'select(.port | IN(22,3389,5900,6379,27017)) | "\(.host // .ip):\(.port)"' \
  "$WORK/naabu.jsonl"

# distinct hosts that have at least one open port
jq -r '.host // .ip' "$WORK/naabu.jsonl" | sort -u

# drop a field you do not need
naabu -host "$TARGET" -top-ports 100 -json -eof tls -silent -duc
```

Timing reference on this image: `naabu -host 127.0.0.1 -top-ports 1000` takes
about 5 seconds against loopback; a real target is bounded by `-rate` and RTT,
not by naabu.

## Chaining with the rest of the toolchain

naabu reads hosts on stdin and, with `-silent`, writes `host:port` lines —
which is exactly what httpx accepts. No `jq` is needed in the plain case.

```bash
# ports -> live web services -> findings
naabu -host "$TARGET" -top-ports 1000 -silent -rate 100 -c 10 -duc \
  | httpx -silent -json -sc -title -td -duc -o "$WORK/live.jsonl"

jq -r '.url' "$WORK/live.jsonl" \
  | nuclei -severity medium,high,critical -ni -rl 25 -c 10 -silent -jsonl -duc \
      -o "$WORK/nuclei.jsonl"

# subdomains -> ports -> web -> scan
subfinder -d "$DOMAIN" -silent -rl 5 -duc \
  | dnsx -silent -a -resp-only -rl 50 -duc \
  | naabu -top-ports 100 -rate 100 -c 10 -silent -duc \
  | httpx -silent -sc -title -td -duc \
  | nuclei -severity medium,high,critical -ni -rl 25 -c 10 -silent -jsonl -duc
```

- If you use `-json`, convert with
  `jq -r 'if .host then "\(.host):\(.port)" else "\(.ip):\(.port)" end'` before
  handing to httpx; httpx does not parse naabu's JSON, and `.host` is absent
  when the input was a bare IP.
- `naabu` emits both `host` and `ip`; using `host:port` downstream keeps the
  name for the Host header and TLS SNI. Using `ip:port` loses vhost routing.
- `-exclude-cdn` is worth a separate pass: a CDN edge will show 80/443 open on
  every name, which is noise, not a finding.
- naabu reads `host:port` input too, so output from a previous naabu run can be
  re-scanned; but it rejects full URLs (`http://…`) with
  `[FTL] Could not run enumeration: no valid ipv4 or ipv6 targets were found`.
  Strip the scheme first if you are feeding it httpx output.

## Limits, failure modes and gotchas

- **The default scan type is CONNECT, not SYN.** `-scan-type` defaults to `c`.
  SYN scanning needs `-s s` *and* root with `CAP_NET_RAW`; the agent runs as
  root in this container by design, but CONNECT is the safer default and the
  one that works through networks that drop raw packets. `-s s` on this image
  logs `Running SYN scan with CAP_NET_RAW privileges` and works.
- **Service detection is stubbed out.** `-sD` and `-sV` accept the flag and then
  abort: `[FTL] Program exiting: service discovery feature is not implemented`.
  They are not a way to get banners. Use `-nmap-cli 'nmap -sV'` instead, which
  is implemented and runs against the ports naabu found.
- **naabu takes hosts, not URLs.** Feeding it `http://host/` from an httpx
  pipeline fails with `[FTL] Could not run enumeration: no valid ipv4 or ipv6
  targets were found`. `host`, `host:port`, IPs and CIDRs are accepted.
- **`.host` is absent from JSON when the input was an IP.** A `jq` expression
  that assumes `.host` exists will emit `null:port` for IP inputs. Use
  `.host // .ip`.
- **An unknown `-eof` field is silently ignored.** A name that is not in the
  `-lof` list is not rejected: the run completes and simply drops nothing.
- **Full-range scans are enormous.** `-tp full` is 65,535 ports per host. With
  `-sa` (scan all IPs) on a multi-A-record name, that multiplies again. Check
  what you are actually asking for before running it.
- **Rate is per-second packets, not per-second hosts.** `-rate 1000` across a
  hundred hosts is still 1000 packets per second leaving one VPN exit. Lower it
  for host lists.
- **`-exclude-cdn` skips the full scan for CDN hosts, keeping only 80/443.**
  That is the right default for a broad sweep, but it means "no open ports"
  from a CDN-fronted name says nothing about the origin.
- **`-passive` sends the target to Shodan.** It queries the InternetDB API, so
  a third party learns the host you are investigating, and the result is only
  as current as Shodan's scan data. Do not use it as a substitute for a scan
  when authorization exists, and do not use it at all without confirming the
  privacy trade is acceptable.
- **`-verify` changes the result set.** Ports that appeared open during the
  sweep can disappear after TCP verification. That is the point, but the two
  numbers will differ from an unverified scan.
- **CONNECT and SYN do not always agree, and CONNECT is the one that loses.**
  Against `scanme.nmap.org` from this container, `-s s` reported port 22 while
  `-s c` on the same port set reported nothing at all, and a top-100 CONNECT
  sweep reported 53 and 22. A CONNECT scan depends on the full TCP handshake
  completing through the VPN path; a filtered or rate-limited path can swallow
  it while the SYN probe still gets an answer. If a target that is obviously up
  shows no open ports, repeat the scan with `-s s` before writing it off, and
  say in the finding which scan type produced the result.
- **Open ports are not services.** A filtered network can return SYN-ACK for
  everything (a firewall or middlebox answering on behalf of the host), and a
  closed port on a rate-limited host can look open. Confirm with httpx or nmap
  before reporting a service.
- **`-iv` defaults to `4,6`.** A hostname with AAAA records is scanned over
  IPv6 as well as IPv4, which can double the traffic and produce ports that
  only exist on one stack. Restrict to `-iv 4` when the target's IPv6 path is
  unknown.
- **`-exclude-cdn` and `-port-threshold` silently shorten the scan.** A host
  with many open ports is skipped past the threshold, and CDN hosts are limited
  to 80/443. Read both before interpreting "nothing found".
- **`-timeout` is a duration**, defaulting to `1s`, even though the help text
  describes it as milliseconds. Pass a Go duration (`500ms`, `2s`).
- **`-stream` disables resume, verify, retries and shuffling.** It is faster
  and less reliable by construction; do not use it for the scan you intend to
  report from.
- **`-nmap-cli` needs nmap and multiplies the traffic.** The command runs
  against every found port on every host. Its own timing flags apply, not
  naabu's.
- **`-sn` performs discovery only** and will not report any ports. If a run
  returns nothing, check that you did not leave `-sn` in.
- **The cloud flags upload your findings.** `-pd`, `-pdu`, `-auth` and friends
  send results to ProjectDiscovery's dashboard. Never enable them on an
  engagement.

## Safety and scope

Requires explicit human confirmation before running:

- Any host not already confirmed for this engagement. Port scanning is
  intrusive and is never implied by a general "look at the site".
- Any scan beyond the top 100 ports, and any `-tp full` or wide `-p` range.
- Any host list, or `-sa`/`-iv 6` on a name with many addresses — the traffic
  multiplies per address.
- SYN scanning (`-s s`), which requires raw sockets and root.
- `-passive`, because it discloses the target to Shodan.
- `-nmap-cli`, which runs a second scanner with its own behaviour.
- `-proxy`/`-proxy-auth`, which would route scan traffic outside the tunnel.
- Any of the cloud flags (`-pd`, `-pdu`, `-auth`, `-tid`, `-aid`, `-aname`),
  which upload findings to a third party.
- Scanning private, internal or RFC1918 address space.
- Raising `-rate`/`-c` above the conservative defaults on a target that is not
  Greg's.
