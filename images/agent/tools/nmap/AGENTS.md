# nmap

Nmap is the port scanner and network mapper: it discovers live hosts, enumerates
TCP and UDP ports, fingerprints services and operating systems, and runs the NSE
script library against the results. It is the first tool in a network engagement,
because every later tool consumes the port and service list it produces — and the
one that most easily looks like an attack, because a port sweep is exactly what it
is.

## Installation and location

| | |
|---|---|
| Version | 7.93 (`nmap --version`) |
| Binary | `/usr/bin/nmap` (Debian bookworm package) |
| NSE scripts | `/usr/share/nmap/scripts/` (604 `.nse` files), database `/usr/share/nmap/scripts/script.db` |
| Data files | `/usr/share/nmap/nmap-services`, `nmap-protocols`, `nmap-os-db`, `nmap-service-probes`, `nmap-mac-prefixes` |
| Config | none; per-user `~/.nmaprc` is not present |
| Output | written wherever `-o*` points; default is stdout |

The agent runs as root, which matters: nmap silently degrades to a TCP connect
scan when it cannot open a raw socket. Running as an unprivileged user makes
`-sS`, `-sU` and `-O` abort with `You requested a scan type which requires root
privileges.` and exit code 1, so never run nmap through `su`/`setpriv`.

There is no `man` binary in the image. `nmap --help` is the only local reference;
the full manual is at <https://nmap.org/book/man.html>.

## Rules that apply to this tool

1. **Authorization first.** Scanning a host that Greg has not confirmed for the
   current engagement is an attack. A hostname in a wordlist is not authorization.
   Scope expansion — a new host, a new port range, a new script category — needs
   explicit confirmation before the packets leave, not after.
2. **All traffic exits the WireGuard tunnel.** The agent has one non-loopback
   interface; there is no route around it and no per-tool proxy setting that
   changes that. Confirm with `ip -o addr` before a scan if the result matters.
3. **Conservative intensity by default.** `-T3` (the default) or lower. `-T4` and
   `-T5` assume a fast, reliable network and a target that tolerates bursts; on a
   home connection or a small VPS they cause false `filtered` results, dropped
   ports, and can trip rate limits. Measured here against `scanme.nmap.org`,
   `--top-ports 20 --max-retries 2`: `-T3` finished in 1.64 s, `-T2` in 11.41 s —
   the lower template sends fewer probes in flight and produces fewer retransmit
   artefacts. Add `--max-retries 2` and `--max-rate` rather than raising `-T`.
4. **No aggressive NSE.** `--script=default,safe` covers banner, title, and
   service facts. `intrusive`, `exploit`, `brute`, `dos`, and `vuln` categories
   change state on the target or can take it down; they need explicit human
   approval per target, and `--script=vuln` is not a substitute for `nuclei`.
5. **Evasion flags are a scope change.** `-D` (decoys), `-S` (spoofed source),
   `--spoof-mac`, `--badsum`, `-f`, and `--data-length` hide the scan from the
   target's operators. Against Greg's own hosts that only degrades his logs; ask
   first.
6. **Save evidence to `$WORK`.** `-oA "$WORK/nmap/<label>"` for every scan that
   supports a finding, so the XML can be re-parsed without re-scanning.
7. **`scanme.nmap.org` is the only public scan target** (Nmap's own test host).
   Keep it to low intensity and small port sets; it is a shared resource.

## Command reference

Target specification

| Flag | Meaning |
|---|---|
| `-iL hosts.txt` | Read targets from a file, one host/CIDR/range per line |
| `--exclude host1,host2` / `--excludefile f` | Remove targets |
| `-iR n` | Random internet hosts — never use it here |
| `-n` / `-R` | Never resolve / always resolve DNS |
| `-p 22,80,443` `-p 1-1024` `-p U:53,T:80` `-p-` | Port selection; `-p-` is all 65535 |
| `--top-ports 100` / `-F` | Most common ports / fast (100) subset |
| `--exclude-ports 9100` | Skip ports |

Host discovery and scan technique

| Flag | Meaning |
|---|---|
| `-sn` | Ping scan only, no ports (misses hosts that drop ICMP — use `-Pn`) |
| `-Pn` | Skip discovery, treat every target as up |
| `-PS22,80` `-PA80` `-PU53` | TCP SYN / ACK / UDP discovery probes |
| `-sS` | TCP SYN scan — the default as root, fast, needs raw sockets |
| `-sT` | TCP connect scan — works unprivileged, slower, logged by the target |
| `-sU` | UDP scan — needs root, slow, expect `open\|filtered` |
| `-sN` / `-sF` / `-sX` | Null/FIN/Xmas scans; needs root, mostly for firewall mapping |
| `-sL` | List scan (DNS only, no packets) |

Detection, scripts, timing, output

| Flag | Meaning |
|---|---|
| `-sV` | Service and version detection (adds seconds per host) |
| `--version-intensity 0..9` / `--version-light` | Probe effort (`--version-light` = 2) |
| `-O` | OS detection; needs root and at least one open **and** one closed port |
| `--osscan-limit` / `--osscan-guess` | Only promising targets / guess harder |
| `--script=default,safe` | NSE by script, file, directory or category |
| `--script-help=http-title` | Per-script help, including categories and URL |
| `--script-args k=v,k2=v2` / `--script-args-file f` | Script arguments |
| `-sC` | Shorthand for `--script=default` |
| `--script-updatedb` | Rebuild `script.db` after adding scripts |
| `-T0`..`-T5` | Timing template, paranoid → insane (higher is faster/riskier) |
| `--min-rate n` / `--max-rate n` | Floor/ceiling on packets per second |
| `--max-retries n` | Cap port-scan retransmissions |
| `--host-timeout 30m` | Give up on a host |
| `--scan-delay 100ms` | Pause between probes (politeness) |
| `-oN` `-oX` `-oG` `-oA base` | Normal / XML / grepable / all three |
| `-oX -` `-oG -` | Write XML/grepable to stdout |
| `--open` | Show only open ports |
| `-v` / `-d` | Verbose / debug |

## Typical workflows

1. **Port sweep from a host file, evidence in all formats.**

   ```bash
   mkdir -p "$WORK/nmap"
   nmap -sS -T3 --top-ports 1000 --max-retries 2 --open \
        -iL "$WORK/targets.txt" -oA "$WORK/nmap/tcp-sweep"
   ```

2. **Service and version fingerprint of the ports that came back open.**

   ```bash
   PORTS=$(python3 - "$WORK/nmap/tcp-sweep.xml" <<'PY'
   import sys, xml.etree.ElementTree as ET
   root = ET.parse(sys.argv[1]).getroot()
   print(",".join(sorted({p.get("portid") for p in root.findall("./host/ports/port")
                          if p.find("state").get("state") == "open"}, key=int)))
   PY
   )
   nmap -sV --version-light -T3 -p "$PORTS" -iL "$WORK/targets.txt" \
        -oA "$WORK/nmap/service-scan"
   ```

3. **Targeted NSE on known ports** (safe categories only):

   ```bash
   nmap -sV -p 80,443,8080 --script='default and safe' \
        --script-args http.useragent='pen-agent' \
        -oX "$WORK/nmap/web-nse.xml" "$TARGET"
   ```

4. **OS detection when the host allows it.** One open and one closed port make
   the fingerprint usable; without that nmap prints `OSScan results may be
   unreliable` and the guesses carry no weight.

   ```bash
   nmap -O --osscan-limit -p 22,80,8000 "$TARGET" -oA "$WORK/nmap/os"
   ```

5. **UDP spot-check** of the services that matter (DNS, NTP, SNMP, WireGuard):

   ```bash
   nmap -sU -T3 --max-retries 1 -p 53,123,161,51820 "$TARGET" \
        -oA "$WORK/nmap/udp"
   ```

## Output and parsing

`-oA base` writes three files: `base.nmap` (human), `base.xml`, `base.gnmap`
(grepable). The XML is the stable interface.

```xml
<nmaprun scanner="nmap" args="nmap -sV -p 8080 --script=http-title 127.0.0.1" version="7.93" xmloutputversion="1.05">
<host><status state="up" reason="syn-ack"/><address addr="127.0.0.1" addrtype="ipv4"/>
<ports><port protocol="tcp" portid="8080">
  <state state="open" reason="syn-ack"/>
  <service name="http" product="SimpleHTTPServer" version="0.6" extrainfo="Python 3.11.2">
    <cpe>cpe:/a:python:simplehttpserver:0.6</cpe></service>
  <script id="http-title" output="Directory listing for /"><elem key="title">Directory listing for /</elem></script>
</port></ports><os><osmatch name="Linux 5.0 - 5.2" accuracy="96"/></os></host>
<runstats><finished time="..." elapsed="6.31" exit="success"/><hosts up="1" down="0" total="1"/></runstats>
</nmaprun>
```

Python (always available, no extra package):

```bash
python3 - "$WORK/nmap/tcp-sweep.xml" <<'PY'
import sys, xml.etree.ElementTree as ET
for host in ET.parse(sys.argv[1]).getroot().findall("host"):
    addr = host.find("address").get("addr")
    for port in host.findall("./ports/port"):
        state, svc = port.find("state").get("state"), port.find("service")
        print(addr, port.get("portid"), state, svc.get("name") if svc is not None else "")
PY
```

`xmllint` is installed (`/usr/bin/xmllint`); XPath is the quickest one-liner:

```bash
xmllint --xpath '//port[state/@state="open"]/@portid' scan.xml      # -> portid="8080"
xmllint --xpath 'string(//host/address/@addr)' scan.xml
xmllint --xpath '//script/@id' scan.xml
```

Grepable output is one line per host and parses with `awk`/`cut`:

```
Host: 127.0.0.1 (localhost)	Status: Up
Host: 127.0.0.1 (localhost)	Ports: 8080/open/tcp//http//SimpleHTTPServer 0.6 (Python 3.11.2)/
```

`nmap` exits 0 whenever the scan ran, including when every port is `filtered`
and the host is unreachable. Never branch on the exit code; branch on the XML
(`runstats/hosts@up`, `port/state/@state`).

## Chaining with the rest of the toolchain

```bash
# nmap XML -> URL list -> httpx -> nuclei
PORTS=$(python3 -c "import sys,xml.etree.ElementTree as ET;print(','.join(p.get('portid') for p in ET.parse(sys.argv[1]).getroot().findall('./host/ports/port') if p.find('state').get('state')=='open'))" "$WORK/nmap/tcp-sweep.xml")
nmap -sV -p "$PORTS" -oX "$WORK/nmap/svc.xml" -iL "$WORK/targets.txt"
python3 -c "
import sys, xml.etree.ElementTree as ET
for h in ET.parse(sys.argv[1]).getroot().findall('host'):
    a = h.find('address').get('addr')
    for p in h.findall('./ports/port'):
        if p.find('state').get('state') == 'open':
            print(f'http://{a}:{p.get(\"portid\")}')" "$WORK/nmap/svc.xml" \
  | httpx -silent -json | tee "$WORK/httpx.jsonl"
```

```bash
# nmap graphable output into a findings table
nmap -sS -T3 --top-ports 100 -oG - "$TARGET" \
  | awk -F'\t' '/Ports:/ {n=split($2,a," "); for(i=2;i<=n;i++) print a[i]}' \
  | cut -d/ -f1,2,5 | sort -u > "$WORK/nmap/open-ports.txt"
```

A capture taken at the same time as a scan (`tshark -i eth0 -f "host $TARGET"`)
can be filtered by the ports the XML reports, which is how you prove what the
scan actually sent. `scapy` can replay a single probe from that pcap.

## Limits, failure modes and gotchas

- **Root-only scan types.** `-sS`, `-sU`, `-O`, `-sN/-sF/-sX` and raw-packet
  features fail as non-root with `You requested a scan type which requires root
  privileges.` and exit 1. Connect scans (`-sT`) work unprivileged and are slower
  and visible to the target.
- **`-O` needs a good fingerprint.** With fewer than one open and one closed port
  nmap warns `OSScan results may be unreliable because we could not find at least
  1 open and 1 closed port` and reports only aggressive guesses. Use
  `--osscan-limit` to skip hopeless hosts.
- **UDP is slow and ambiguous.** `open|filtered` means "no reply" — it is not
  evidence the port is open. `--max-retries 1` keeps a UDP scan bounded.
- **`-sn` misses ICMP-blocking hosts.** If a host is known to be up, use `-Pn`
  and accept the extra scan time.
- **Timing artefacts.** `-T4`/`-T5` produce `filtered` where `-T2`/`-T3` show
  `open`, especially through a VPN with variable RTT. A `filtered` verdict from a
  fast template is not evidence of a firewall.
- **IPv6 vs IPv4.** `scanme.nmap.org` and many dual-stack names resolve to an
  AAAA record first in the scan report; `-6` is a separate scan and nmap does not
  do both in one run.
- **No DNS without a resolver.** `-n` avoids resolution delays; unresolved
  hostnames in output then appear as bare IPs.
- **`--script-updatedb` rewrites `/usr/share/nmap/scripts/script.db`.** Harmless
  and idempotent, but it mutates the image layer rather than `$WORK`.
- **No `man` page in the image.** `nmap --help`, `--script-help`, and
  <https://nmap.org/book/man.html>.
- **Rate-limited public hosts.** `scanme.nmap.org` throttles; a burst scan shows
  `filtered` ports that are actually open. Scan it once, slowly.

## Safety and scope

- Confirm the target list with Greg before the first packet. Ports scanned, hosts
  included, and script categories used are all scope.
- `--script=vuln`, `--script=intrusive`, `--script=exploit`, and `--script=brute`
  can alter or crash a service: human approval per target, and prefer `nuclei`
  for vulnerability checks.
- `-sU` against a production interface can trip IDS or fill logs; ask first.
- Decoys, source spoofing, MAC spoofing, and fragmenting are evasion — they
  remove attribution from the scan and require explicit approval.
- Keep scans at `-T3` or lower against anything that serves real users, and
  schedule them outside peak hours when Greg asks for that.
- Write XML output to `$WORK` before drawing conclusions; a finding without the
  supporting scan is not a finding.
