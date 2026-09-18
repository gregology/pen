# masscan — asynchronous port scanner (wide ranges, very high rate)

masscan sends SYN packets asynchronously with its own user-mode TCP/IP stack and
no kernel connection tracking, so it can scan large address spaces at rates nmap
cannot approach (default 100 packets/second; the design target is millions). Use
it to answer "which hosts in this range have anything listening" and then hand
the survivors to nmap/httpx. It is the wrong tool for deep scanning one host: no
version detection beyond simple banners, no scripts, no OS fingerprinting — that
is nmap. For host lists and pipeline-friendly fast discovery, naabu is the
gentler option.

## Install and location

| | |
|---|---|
| Version | 2:1.3.2+ds1-1 (Debian bookworm; Debian patches only the build system and spelling) |
| Binary | `/usr/bin/masscan`, man page `masscan(8)` |
| Privileges | plain mode-0755 binary, no setuid, no file capabilities — needs root / `CAP_NET_RAW` |

masscan contains no privilege check of its own; it asks libpcap for an
`AF_PACKET` socket, which the kernel gates on `CAP_NET_RAW`. Run it as root (the
agent container's uid), or grant `cap_net_raw=ep` yourself. The Debian package
declares only `Depends: libc6` even though the binary `dlopen`s
`libpcap.so.0.8` at runtime — this image has it via tcpdump/tshark, but a
"failed to load libpcap shared library" error means the library is missing, not
a permission problem.

## Flags that matter

| Flag | What it does |
|---|---|
| `<targets>` | Positional IPs/ranges/CIDRs, space- or comma-separated: `10.0.0.5`, `10.0.0.1-10.0.0.100`, `10.0.0.0/24`. **No DNS names, no default targets.** |
| `-p, --ports` | Ports, e.g. `-p80,8000-8100`, `-p0-65535`, UDP as `-pU:53,161`. **There is no default port list.** |
| `--rate N`, `--max-rate N` | Transmit rate in packets/second (a double; `0.1` = one packet every 10 s). Default **100**. `--rate` and `--max-rate` are the same option. |
| `--exclude IP/RANGE`, `--excludefile FILE` | Never scan these. Also the guard against accidental internet-wide scans. |
| `-oX FILE`, `-oJ FILE`, `-oG FILE`, `-oL FILE`, `-oB FILE` | XML, JSON, grepable, list, binary output. |
| `--output-format FMT`, `--output-filename FILE` | Long forms; `--output-filename -` writes to stdout. Formats in 1.3.2: `xml`, `json`, `ndjson`, `list`, `grepable`, `binary`, `interactive`, `certs`, `hostonly`, `redis`, `none`, `unicornscan`. |
| `--open-only` | Report only open ports. Open-only is already the default; the flag's real use is being explicit in scripts. |
| `--banners` | Complete the TCP handshake and grab a banner for FTP, HTTP, IMAP, memcached, POP3, SMTP, SSH, SSL, SMBv1/v2, Telnet, RDP, VNC. Fights the host stack (below). |
| `--adapter IF`, `--interface IF`, `-e IF` | Interface to use. Default: the interface holding the default route. |
| `--adapter-ip IP`, `--source-ip IP` | Source IP for probes. Must be an address of the local subnet, unused by anything else. |
| `--adapter-port P`, `--source-port P` | Source port range (single port or an even power-of-two range). Defaults to a random port in 40000–59999. |
| `--router-mac MAC`, `--adapter-mac MAC` | Override the resolved gateway MAC / own MAC. |
| `--wait SECONDS` | Time to wait for late replies after transmit finishes (default 10; `forever` allowed). |
| `--retries N` | Repeat each probe N times, one second apart, regardless of whether a reply arrived (stateless). |
| `--ttl N` | TTL of outgoing packets (default 255). |
| `-c FILE`, `--conf FILE`, `--resume FILE` | Read options from a config file; `--resume` re-reads a paused scan and appends to its output. |
| `--echo` | Do not scan: print the fully resolved configuration (including the adapter and source IP masscan chose) and exit 0. |
| `--nmap` | Print the nmap-compatible option equivalents and exit. |
| `--iflist` | List interfaces and exit. |
| `--readscan FILE` | Read a `-oB` binary result file and re-emit it in another format. |
| `--shards x/y` | Split the scan across y instances; run instance x. |
| `--resume-index N`, `--resume-count N` | Chop a scan into index ranges. |
| `--offline` | Do not transmit; combine with `--packet-trace` to inspect. |
| `--packet-trace` | Print sent/received packet summaries — only usable at low rates. |
| `--pcap FILE`, `--seed N`, `--rotate*`, `--append-output`, `--interactive`, `--ping`, `--http-user-agent UA`, `-sL` | Packet capture, deterministic ordering, log rotation, appending, live console output, ICMP echo with the scan, HTTP UA override, and "generate a random address list instead of scanning". |

## Examples

### Does this host have anything open?

```bash
masscan 10.0.0.5 -p1-65535 --rate 1000 -oJ $WORK/masscan-host.json
jq -r '.[] | .ip as $ip | .ports[] | select(.status=="open") | "\($ip):\(.port)/\(.proto)"' $WORK/masscan-host.json
```

Expect one JSON object per open port with `status: "open"`, `reason: "syn-ack"`.
If nothing at all comes back, check the adapter choice before concluding the host
is closed (see Notes).

### A subnet, open ports only, machine-readable

```bash
masscan 10.0.0.0/24 -p22,80,443,3389,8080 --rate 2000 -oJ $WORK/masscan-lan.json
jq -r '.[] | select(.ports[0].status=="open") | "\(.ip):\(.ports[0].port)"' $WORK/masscan-lan.json | sort -u
```

`/24` × 5 ports = 1,280 probes; at 2000 pps this is under a second of transmit
plus the 10 s `--wait`.

### Internet-scale ranges with exclusions (read the guard first)

```bash
printf '169.254.0.0/16\n224.0.0.0/4\n255.255.255.255\n' > $WORK/exclude.txt
masscan 10.0.0.0/8 -p80,443 --rate 100000 --excludefile $WORK/exclude.txt -oX $WORK/masscan-wide.xml
```

masscan refuses a target set larger than 1,000,000,000 addresses when no
`--exclude` is given (`FAIL: range too big, need confirmation`), so always keep
an exclusion file.

### Banner grabbing when the host stack steals the replies

```bash
# outside the scan: keep the kernel away from the source port masscan will use
iptables -A INPUT -p tcp --dport 61000 -j DROP
masscan 10.0.0.5 -p22,80,443 --banners --adapter-port 61000 --rate 100 -oJ $WORK/masscan-banners.json
```

The local kernel RSTs the SYN-ACK before masscan's own stack can complete the
handshake, which is why banners come back empty without this. The alternative,
and upstream's preferred method, is to give masscan an unused address on the
local subnet with `--adapter-ip`.

### Inspect before you fire

```bash
masscan 10.0.0.0/24 -p80 --rate 1000 --echo | tee $WORK/masscan.conf
masscan -c $WORK/masscan.conf --offline --packet-trace --rate 10
```

`--echo` prints the resolved config — adapter, source IP, router MAC, rate, wait
— and exits without scanning. `--offline --packet-trace` shows exactly which
packets would be sent. Both are cheap insurance before a scan whose traffic
cannot be recalled.

## Output formats

Five writers plus the default console output:

- `-oJ`, `--output-format json` — array of objects, **one object per open port**
  (not per host), written by hand-rolled C:
  `[{ "ip": "10.0.0.5", "timestamp": "1390380064", "ports": [ {"port": 80, "proto": "tcp", "status": "open", "reason": "syn-ack", "ttl": 48} ] }]`.
  `timestamp` is a string.
- `-oX` — nmap-inspired XML (`<nmaprun>`, `<host>`, `<ports>`), suitable for
  tooling that reads nmap XML.
- `-oG` — nmap grepable format.
- `-oL` — `open tcp 80 10.0.0.5 1390380064`, one host/port per line; the easiest
  to `awk`.
- `-oB` — binary, much smaller, converted later with
  `--readscan bin.scan -oX out.xml`.
- `--output-format ndjson` — one JSON object per line with `rec_type: "status"`
  records (and `rec_type: "banner"` when `--banners` is on).

`--output-filename -` writes any of these to stdout. Without an output option,
results print to the console as they are received.

## Failure modes

- **Permission denied:** `[-] FAIL: permission denied` / `[hint] need to sudo or
  run as root or something`, then exit 1.
- **`FAIL: target IP address list empty`** (exit 1) when no target is given —
  including `masscan -p80`. **`FAIL: no ports were specified`** (exit 1) when
  `-p` is missing. Both are fatal, unlike a bare `masscan`, which prints usage
  and exits 0.
- **`FAIL: range too big, need confirmation`** (exit 1) for target sets over
  1e9 addresses without any `--exclude`. Deliberate: add
  `--exclude 255.255.255.255` as a confirmation if the scan really is that wide.
- **`FAIL: could not determine default interface`** (exit 1) when no interface
  has a default route, and `FAIL: failed to detect IP of interface` /
  `FAIL: failed to detect MAC address of interface` when the chosen adapter has
  no usable address. Fix with `--adapter`, `--adapter-ip`.
- **ARP timeout to the gateway** (`FAIL: ARP timed-out resolving MAC address for
  router`) kills the run on Ethernet adapters. On tunnel interfaces (link type
  Null/Loopback) masscan prints `[+] if(<name>): VPN tunnel interface found` and
  uses an implicit router, so no ARP is attempted.
- **Banners come back empty on a host with a normal kernel stack** because the
  kernel RSTs the SYN-ACK. Fix with `--adapter-port` + an iptables DROP rule, or
  `--adapter-ip`.
- **A bad `--rate` value is ignored silently.** The parser returns an error for a
  non-numeric rate, but the caller discards it, so the rate stays at the
  previous/default value instead of failing.
- **The host stack and masscan disagree about source ports.** If masscan's chosen
  source port (random 40000–59999) collides with a kernel-ephemeral port in use,
  replies can be consumed by the kernel. Use `--adapter-port`, or narrow masscan
  to a range below `/proc/sys/net/ipv4/ip_local_port_range`.
- **`/etc/masscan/masscan.conf` is read automatically** when present (before the
  command line, so CLI options win). A surprising rate or exclude list may come
  from a file you did not write.
- **`--wait` governs completeness, not speed.** Exiting immediately after
  transmit loses slow replies; the default 10 s is usually right, and
  `--wait forever` never terminates.
- **`--offline` still "scans"** and produces no results — it is a dry run, not a
  quieter real scan.

## Notes

- **This is the loudest tool in the container.** High-rate SYN scanning saturates
  uplinks, trips IDS/abuse desks, and every packet leaves from the shared VPN
  exit node. Start at the default 100 pps, raise deliberately, and never exceed
  the engagement's agreed rate.
- **Adapter selection matters in this container.** With no `--adapter`, masscan
  picks the interface holding the default route. The agent shares the VPN
  gateway's network namespace, so verify which adapter it chose with
  `--echo`/`--iflist` and pin it (`--adapter wg0`) if there is any doubt.
  **Inference, not verified in this deployment:** if auto-selection picks the
  sandbox interface instead of the tunnel, the kill switch drops that traffic and
  the scan returns nothing at all — a silent empty result that looks like a
  closed target. `--echo` first, every time.
- masscan supports Ethernet, raw-IP and tunnel (Null/Loopback) link types; the
  WireGuard interface is explicitly handled ("VPN tunnel interface found") with
  no ARP step.
- **Sharding/resume:** `--shards 1/3`…`3/3` across three instances, or
  `--resume-index`/`--resume-count` in fixed chunks. Ctrl-C saves `paused.conf`;
  resume it with `--resume paused.conf` (output is appended, not overwritten).
- **Not a replacement for nmap.** masscan finds ports; it does not identify
  services reliably (`--banners` is shallow), does not run scripts, and its "no
  response" on a filtered port says nothing about why. Feed survivors to
  `nmap -sV -sC` or, for web ports, to httpx.
- Keep `--exclude`/`--excludefile` in every wide scan as a matter of habit, and
  archive the exclusion file next to the results — the output is only
  interpretable alongside the exact ranges scanned.

## Safety

Requires explicit human confirmation before running:

- any target outside the confirmed scope, at any rate;
- any rate above the default, and any wide range (a `/16` or larger);
- `--banners` against production hosts (it completes handshakes);
- `--shards` across multiple instances, which multiplies the burst;
- `--adapter-ip`/`--source-ip` changes, which alter the source address the target
  sees;
- scans of private or internal address space.
