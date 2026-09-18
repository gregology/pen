# tshark

TShark is Wireshark's command-line engine: it captures packets from an interface
and dissects capture files into protocol trees. For this platform it has two jobs
— turn a pcap into evidence (fields, conversations, statistics, exported objects)
and answer "what did that tool actually put on the wire?" — and both are done
without a GUI, which is the only way it can be done in this container.

## Installation and location

| | |
|---|---|
| Version | TShark 4.0.17 (Debian bookworm `tshark` + `wireshark-common` 4.0.17-0+deb12u3) |
| Binary | `/usr/bin/tshark` |
| Suite | `/usr/bin/{dumpcap,capinfos,editcap,mergecap,text2pcap,rawshark,reordercap,sharkd}` |
| Preferences | `/etc/wireshark/`, per-user `~/.config/wireshark/`; override per run with `-o name:value` |
| Capture output | wherever `-w` points; a pcap/pcapng file |
| No GUI | `wireshark` and `wireshark-qt` are not installed and there is no display |

`dumpcap` has **no** file capabilities (`getcap /usr/bin/dumpcap` is empty) and
there is no `wireshark` group. Capture works because the agent is root; do not
drop privileges for capture. `dumpcap` prints `cap_set_proc() fail return:
Operation not permitted` twice on startup here — the container lacks
`CAP_SETPCAP`, and the warning is benign as root. `tshark --version` and every
capture likewise print `Running as user "root" and group "node". This could be
dangerous.` to stderr.

## Rules that apply to this tool

1. **Authorization first.** Capturing traffic that Greg has not authorized is
   wiretapping, whatever the interface. Capture only on this container's own
   interfaces, and only traffic for the engagement in scope.
2. **A pcap can contain other people's credentials.** HTTP basic auth, cookies,
   bearer tokens, SNMP communities, and unencrypted passwords end up verbatim in
   a capture. Treat every `.pcap` as sensitive material: keep it in `$WORK`, never
   paste packet payloads into a transcript, and delete captures that are no longer
   needed.
3. **All agent traffic exits the WireGuard tunnel.** Capturing the agent's own
   interface records attack traffic that is already attributed to the VPN; do not
   use capture to try to observe or bypass the tunnel.
4. **Bound every live capture.** Always use `-a duration:N` or `-c N`, or a ring
   buffer (`-b filesize:`, `-b files:`, `-b duration:`), so a forgotten capture
   cannot fill the disk. Check `df -h /` before a long capture.
5. **Save evidence to `$WORK`.** `-w "$WORK/pcap/<label>.pcap"` plus the exact
   `-f`/`-Y` filters used, written into the findings note. A filter you cannot
   reproduce makes the capture unverifiable.
6. **Local traffic for local questions.** Generate your own loopback traffic
   (`python3 -m http.server` + `curl`) when the goal is to learn or test a
   dissector, filter, or addon. Do not point captures at third-party hosts.

## Command reference

Modes: **capture** (`-i`, needs `-w` or it prints to stdout), **read** (`-r file`),
and passive decode of stdin (`-r -`).

Capture

| Flag | Meaning |
|---|---|
| `-i lo` / `-i eth0` / `-i any` | Interface; `any` uses Linux cooked capture and works here |
| `-D` | List interfaces — see the gotcha below: this lists only extcap plugins, use `dumpcap -D` |
| `-f 'tcp port 8090'` | **Capture** filter, BPF syntax, applied in the kernel |
| `-c 50` | Stop after N packets |
| `-a duration:30` / `-a filesize:10240` / `-a packets:1000` | Autostop condition |
| `-b filesize:8192 -b files:5` | Ring buffer, KB per file, keep 5 files |
| `-b duration:60 -b files:10` | Time-based ring |
| `-w out.pcap` | Write pcap |
| `-p` | Don't put the interface in promiscuous mode |

Read and dissect

| Flag | Meaning |
|---|---|
| `-r file.pcap` | Read a capture (also `-r -` from stdin) |
| `-Y 'http.request'` | **Display** filter, Wireshark syntax, applied after dissection |
| `-d tcp.port==12345,http` | Force a dissector onto a port |
| `-o name:value` | Override a preference for this run |
| `-2` | Two-pass analysis (needed for some reassembly-dependent filters) |
| `-T fields -e f1 -e f2` | Field output — the machine-readable mode |
| `-T json` / `-T pdml` / `-T ek` | JSON / XML / Elasticsearch bulk |
| `-E header=y -E separator=, -E quote=d` | Field-output formatting |
| `-q` | Quiet: suppress per-packet output, keep `-z` statistics |
| `-z io,stat,1` / `-z io,phs` / `-z conv,tcp` / `-z endpoints,ip` | Statistics |
| `-z follow,tcp,ascii,0` | Reassemble and print TCP stream 0 |
| `--export-objects http,DIR` | Carve HTTP objects to a directory |
| `-G fields` / `-G defaultprefs` / `-G currentprefs` | Dump field registry / preferences |
| `-V` / `-x` | Full protocol tree / hex+ASCII dump per packet |

## Typical workflows

1. **Capture loopback HTTP while generating it yourself.**

   ```bash
   mkdir -p "$WORK/pcap"
   (cd /tmp && nohup python3 -m http.server 8090 --bind 127.0.0.1 >/dev/null 2>&1 &)
   ( for i in 1 2 3; do curl -s -o /dev/null http://127.0.0.1:8090/; done ) &
   tshark -i lo -f 'tcp port 8090' -a duration:5 -w "$WORK/pcap/local-http.pcap"
   ```

2. **Capture a single authorized external TLS session and read the SNI.**

   ```bash
   ( sleep 1; curl -s -o /dev/null https://example.com/ ) &
   tshark -i eth0 -f 'tcp port 443' -a duration:8 -w "$WORK/pcap/tls.pcap"
   tshark -r "$WORK/pcap/tls.pcap" -Y 'tls.handshake.type==1' \
          -T fields -e ip.dst -e tls.handshake.extensions_server_name
   ```

3. **Extract a table for a report** (fields, CSV, then `jq` for JSON):

   ```bash
   tshark -r "$WORK/pcap/local-http.pcap" -Y http.request \
          -T fields -E header=y -E separator=, -E quote=d \
          -e frame.number -e ip.src -e http.host -e http.request.uri
   ```

4. **Conversations, protocol mix, and a follow of one stream:**

   ```bash
   tshark -r "$WORK/pcap/tls.pcap" -q -z io,phs
   tshark -r "$WORK/pcap/tls.pcap" -q -z conv,tcp
   tshark -r "$WORK/pcap/local-http.pcap" -q -z follow,tcp,ascii,0
   ```

5. **Long, bounded capture with a ring buffer**, then work on the newest file:

   ```bash
   tshark -i eth0 -f 'host 10.0.0.5' -b duration:300 -b files:12 \
          -w "$WORK/pcap/ring.pcap"
   ls -t "$WORK/pcap"/ring_*.pcap | head -1
   ```

## Output and parsing

**Field discovery.** `-G fields` is the authoritative name list; each row is
`F|P <TAB> description <TAB> abbrev <TAB> type <TAB> parent`:

```
Request URI	http.request.uri	FT_STRING	http
Server Name	tls.handshake.extensions_server_name	FT_STRING	tls
```

```bash
tshark -G fields | rg -N 'http.request.uri|tls.handshake.extensions_server_name' | cut -f2,3,4
```

**`-T fields`** prints one line per packet, tab-separated by default; missing
fields leave empty columns. This is the format to parse:

```bash
tshark -r cap.pcap -Y 'tls.handshake.type==1' \
       -T fields -e ip.dst -e tls.handshake.extensions_server_name
# 104.20.23.154	example.com
```

**`-T json`** nests by protocol layer, and repeated/compound fields become
sub-objects (`layers.tls` may hold only `tls.record`). Recursive `jq` is the
reliable way in:

```bash
tshark -r cap.pcap -Y 'tls.handshake.type==1' -T json \
  | jq -r '[.[] | .. | objects | select(has("tls.handshake.extensions_server_name"))
            | .["tls.handshake.extensions_server_name"]] | unique | .[]'
# example.com
```

**Statistics** (`-q` keeps only the tables):

```
| IO Statistics                    |            Protocol Hierarchy Statistics
| Duration: 0.212 secs             |            eth   frames:24 bytes:7719
| Interval: 0.212 secs             |              ip  frames:24 bytes:7719
|  Interval   | Frames | Bytes     |                tcp frames:24 bytes:7719
| 0.0 <> 0.1  |      9 |  5118     |                  tls frames:12 bytes:6911
```

**Exit codes.** `0` for a successful read even when the filter matches nothing;
`2` for a missing file or an invalid display filter; `2` for a binary file that
is not a capture. Exit `0` is not proof of a clean capture — an XML file handed
to `-r` is dissected as a `MIME_FILE/XML` packet and still exits 0, while a
plain text file exits 2. Check the packet count (`capinfos -c`) or the dissected
protocol before trusting a read.

`capinfos -c -u -a -e -T file.pcap` summarises a capture in tab-separated form
(packet count, duration, start, end).

## Chaining with the rest of the toolchain

```bash
# tshark fields -> jq -> findings file
tshark -r "$WORK/pcap/tls.pcap" -Y 'tls.handshake.type==1' -T json \
  | jq -r '.[] | ._source.layers as $l | "\($l.ip["ip.src"]) -> \($l.ip["ip.dst"])"' \
  >> "$WORK/findings/tls-endpoints.txt"
```

```bash
# scapy-generated pcap -> tshark dissection
/opt/venvs/scapy/bin/python3 -c "
from scapy.all import *
wrpcap('/tmp/probe.pcap', [IP(dst='127.0.0.1')/TCP(dport=8090, flags='S')])"
tshark -r /tmp/probe.pcap -T fields -e ip.dst -e tcp.dstport -e tcp.flags.syn
```

```bash
# bound a pcap before handing it to another tool
editcap -c 10000 big.pcap "$WORK/pcap/chunk.pcap"   # split every 10000 packets
mergecap -w "$WORK/pcap/merged.pcap" a.pcap b.pcap  # combine captures
capinfos -c -u merged.pcap                          # verify what you built
```

```bash
# nmap told you the port; the capture tells you what the probe looked like
tshark -r "$WORK/pcap/scan.pcap" -Y 'tcp.flags.syn==1 and tcp.flags.ack==0' \
       -T fields -e ip.dst -e tcp.dstport | sort | uniq -c | sort -rn
```

`tshark -T fields` output is line-oriented, so it pipes directly into
`sort | uniq -c`, `awk`, `jq`, or into `nuclei`/`httpx` after a `sed` that builds
URLs. HTTP objects carved with `--export-objects` are ordinary files on disk and
can be scanned with `trivy` or `trufflehog`.

## Limits, failure modes and gotchas

- **`-f` and `-Y` are not interchangeable.** `-f` takes BPF (`tcp port 8080`,
  `host 10.0.0.5`, `icmp`) and only applies while capturing; `-Y` takes Wireshark
  display filters (`http.request`, `tls.handshake.type==1`, `ip.addr==10.0.0.5`)
  and only applies to dissection. Wrong-way usage fails loudly:
  `-r file -f 'http.request'` → `Only read filters, not capture filters, can be
  specified when reading a capture file.`; `-Y 'tcp port 8080'` while capturing
  fails with a display-filter parse error.
- **`tshark -D` is misleading here.** It lists only extcap pseudo-interfaces
  (`ciscodump`, `dpauxmon`, `randpkt`, `sdjournal`, `sshdump`, `udpdump`,
  `wifidump`). Real interfaces come from `dumpcap -D` — here `eth0`, `eth1`,
  `wg0`, `any`, `lo`, `dbus-system`, `dbus-session`, `bluetooth-monitor`,
  `nflog`, `nfqueue`. `ip -o addr` is the fastest check of which one carries
  egress.
- **An empty result is not an error.** A display filter that matches nothing, or
  a capture filter that never fired, produces zero lines and exit code 0. Always
  compare against `capinfos -c` before concluding "no traffic".
- **`-r` on a non-capture file can succeed misleadingly.** An XML file is
  dissected as `MIME_FILE/XML` and exits 0; a plain text file and a binary flow
  file exit 2. Verify the dissected protocol, not just the exit code.
- **Non-standard ports usually still decode.** Wireshark applies HTTP heuristics,
  so `-Y http.request` matched traffic on 8080, 18080 and 12345 without help. When
  it does not, force it with `-d tcp.port==<port>,http` (verified working) rather
  than falling back to `-e data.data`.
- **mitmproxy flow files are not pcaps.** `mitmdump -w out.pcap` writes
  mitmproxy's own tnetstring format regardless of extension; `tshark -r` on it
  exits 2 with `isn't a capture file in a format TShark understands`. Capture
  packets with tshark (or `tcpdump`) in parallel if you need both views.
- **`-z follow` needs a stream number.** Get it from `-z conv,tcp`; stream
  indices change with every capture.
- **Ring-buffer file names are generated.** `-w ring.pcap -b ...` writes
  `ring_00001_<YYYYMMDDHHMMSS>.pcap`, not `ring.pcap`; `-b files:N` deletes the
  oldest. Read `ls -t` rather than a fixed name.
- **Root warnings are cosmetic**; `cap_set_proc() fail` and
  `Running as user "root"` go to stderr and do not affect the capture. Redirect
  stderr only when you have confirmed the capture still works.
- **No `man` pages and no GUI.** `tshark --help`, `-G fields`,
  <https://www.wireshark.org/docs/dfref/> for filter names.

## Safety and scope

- Capturing any interface other than `lo` records traffic that is not yours:
  confirm the interface and the filter with Greg, and prefer a `-f` host/port
  filter over a blanket capture.
- A pcap is credential material. Never attach one to the transcript, never paste
  payloads, keep it inside `$WORK`, and remove it when the engagement closes.
- Decrypting TLS requires the session keys (`SSLKEYLOGFILE`) or the server key;
  do not attempt to obtain either without explicit authorization.
- Long captures are a disk-exhaustion risk. `df -h /` first, ring buffer always.
- Carving objects with `--export-objects` writes attacker-controlled (or
  target-controlled) files to disk. Export into `$WORK`, never execute them.
