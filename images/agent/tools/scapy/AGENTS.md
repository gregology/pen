# scapy

Scapy is a Python packet-manipulation library: it builds packets layer by layer,
sends them, captures replies, and reads or writes pcap files. Where `nmap` asks
standard questions with standard probes, scapy lets you send the exact malformed,
truncated, or protocol-violating packet that a parser bug needs — which makes it
the tool for testing how a target's protocol handling behaves when the input is
not what a normal client would send.

## Installation and location

| | |
|---|---|
| Version | 2.7.0 (`/opt/venvs/scapy/bin/python3 -c "from scapy.all import conf; print(conf.version)"`) |
| Location | `/opt/venvs/scapy/lib/python3.11/site-packages/scapy/` — the PyPI release in its own virtualenv, not the Debian package |
| Interpreter | `/opt/venvs/scapy/bin/python3` (3.11.2). **Bare `python3` is `/opt/py/bin/python3`, which has no scapy** — every command below names the venv interpreter |
| REPL | `/usr/local/bin/scapy`, the package's console script, reads piped stdin; scripts are the supported interface |
| Config | none; behaviour is set per process through `conf` (`conf.L3socket`, `conf.iface`, `conf.verb`) |
| Output | pcaps via `wrpcap`, or whatever the script prints |

Root is required. As an unprivileged user, sending raises
`PermissionError [Errno 1] Operation not permitted` — there is no capability
fallback for raw sockets.

## Rules that apply to this tool

1. **Authorization first.** A crafted packet is indistinguishable from an attack
   at the target, and scapy will happily send one. Only send to hosts in scope,
   and only the packet types the engagement authorizes.
2. **Prefer loopback for development.** Build and debug the script against
   `127.0.0.1` (with `python3 -m http.server 8090` as the target; 8080 in this
   container is the VPN control API), then change the destination. Every example
   here was validated on loopback for that reason.
3. **No evasion by default.** Spoofed sources (`IP(src=…)`), crafted flags, and
   fragmentation change attribution and target logs; they need explicit approval
   per target, exactly like nmap's `-S`/`-D`.
4. **Rate-limit yourself.** scapy has no built-in pacing; a `send()` loop floods.
   Add `time.sleep()` between packets and cap the count — the target may be one of
   Greg's own services serving real users.
5. **Captures and payloads are sensitive.** A pcap written by `wrpcap` contains
   whatever crossed the interface, credentials included. Keep pcaps in `$WORK`,
   never paste payloads into the transcript.
6. **Save scripts and evidence to `$WORK`.** A finding backed by a crafted packet
   must include the script that sent it and the pcap of the result.

## Command reference

Scapy is a library, not a CLI. The working patterns are
`/opt/venvs/scapy/bin/python3 -c '…'` and script files.

| API | Purpose |
|---|---|
| `IP(dst=…)/TCP(dport=…, flags='S')` | Build packets by stacking layers (`/`) |
| `Ether()/IP()/…` | L2 frame (needed for `sendp`/`srp`) |
| `send(pkt, iface=…, verbose=0)` | Send L3 packets, no reply captured |
| `sendp(frame, iface=…)` | Send L2 frames |
| `sr(pkt, timeout=2)` | Send and receive; returns `(answered, unanswered)` |
| `sr1(pkt, timeout=2)` | Send and receive the first reply, or `None` on timeout |
| `srp` / `srp1` | L2 equivalents (no reply from loopback in this container) |
| `sniff(iface=, filter=, count=, timeout=, prn=)` | Blocking capture |
| `AsyncSniffer(iface=, filter=, store=True, prn=)` | Background capture: `.start()` / `.stop()` |
| `rdpcap(path)` / `PcapReader(path)` | Read a whole pcap / iterate packets |
| `wrpcap(path, pkts)` | Write a pcap |
| `pkt.summary()`, `pkt.show()` | One-line / full dissection |
| `pkt.haslayer(Raw)`, `bytes(pkt[Raw].load)` | Payload access |
| `conf.L3socket = L3RawSocket` | Legacy loopback workaround; **not needed on 2.7.0** (see gotchas) |
| `conf.iface`, `get_if_list()`, `conf.route.route(dst)` | Interface and route selection |

`timeout=` is in seconds; on expiry `sr1` returns `None` and `sr` returns an empty
answer list. There is no retry: one send per call.

## Typical workflows

1. **TCP port probe with a hand-built SYN** (open = `SA`, closed = `RA`):

   ```bash
   /opt/venvs/scapy/bin/python3 -c "
   from scapy.all import *
   ans, unans = sr(IP(dst='127.0.0.1')/TCP(dport=[8090, 7999], flags='S'), timeout=2, verbose=0)
   for sent, recv in ans:
       print(sent[TCP].dport, recv[TCP].sprintf('%TCP.flags%'))
   print('unanswered:', len(unans))
   "
   ```

2. **Capture HTTP to a pcap while generating it locally** (`AsyncSniffer` needs a
   short warm-up before traffic starts):

   ```bash
   /opt/venvs/scapy/bin/python3 -c "
   from scapy.all import AsyncSniffer, wrpcap
   import subprocess, time
   sn = AsyncSniffer(iface='lo', filter='tcp port 8090', store=True)
   sn.start(); time.sleep(0.5)
   subprocess.run(['curl','-s','-o','/dev/null','http://127.0.0.1:8090/'], check=True)
   time.sleep(0.5)
   pkts = sn.stop()
   wrpcap('/tmp/scapy-http.pcap', pkts)
   print('captured', len(pkts), 'packets')
   "
   ```

3. **Read a pcap and pull the payloads** (works on tshark/tcpdump captures too):

   ```bash
   /opt/venvs/scapy/bin/python3 -c "
   from scapy.all import rdpcap, Raw, IP, TCP
   for p in rdpcap('/tmp/scapy-http.pcap'):
       if p.haslayer(Raw):
           print(p[IP].src, '->', p[IP].dst, p[TCP].dport, repr(bytes(p[Raw].load)[:45]))
   "
   ```

4. **Craft packets and save them for later replay** (no packets sent):

   ```bash
   /opt/venvs/scapy/bin/python3 -c "
   from scapy.all import *
   wrpcap('/tmp/crafted.pcap', [Ether()/IP(dst='192.0.2.1')/TCP(dport=443, flags='S')])
   print(rdpcap('/tmp/crafted.pcap')[0].summary())
   "
   ```

5. **Replay a capture to a target in scope** (bounded, paced):

   ```bash
   /opt/venvs/scapy/bin/python3 -c "
   from scapy.all import rdpcap, sendp
   import time
   for i, p in enumerate(rdpcap('/tmp/crafted.pcap')):
       if i >= 5: break
       sendp(p, iface='eth0', verbose=0); time.sleep(0.5)
   print('replayed')
   "
   ```

## Output and parsing

Scapy's native output is Python objects. `summary()` returns one line per packet:

```
Ether / IP / TCP 127.0.0.1:http_alt > 127.0.0.1:53470 PA / Raw
IP / ICMP 127.0.0.1 > 127.0.0.1 echo-reply 0
IP / ICMP 127.0.0.1 > 127.0.0.1 dest-unreach port-unreachable / IPerror / UDPerror
```

A packet captured on the container's own interfaces shows the egress address
(`172.31.0.2`) as its source rather than loopback.

`haslayer`/`getlayer` and the layer classes are how a script inspects a packet:

```python
p = rdpcap("cap.pcap")[0]
p[IP].dst, p[TCP].dport, p[TCP].sprintf("%TCP.flags%"), bool(p[TCP].flags.S)
```

Writing pcaps:

```python
wrpcap("out.pcap", packets)          # list of packets, any layer
```

Reading them: `rdpcap` returns a list (all packets in memory — careful with large
captures), `PcapReader` streams:

```python
from scapy.all import PcapReader
with PcapReader("big.pcap") as pr:
    print(sum(1 for _ in pr))
```

pcaps written by scapy are ordinary libpcap files: `tshark -r out.pcap` reads them
(verified), and scapy reads pcaps written by `tshark`/`tcpdump`.

Filter syntax in `sniff(filter=…)` is BPF, the same grammar as `tcpdump` and
tshark's `-f`: `icmp`, `tcp port 8090`, `host 10.0.0.5 and not port 22`. A bad
filter does **not** raise: scapy prints
`ERROR: Cannot set filter: Failed to compile filter expression …` and returns an
empty capture.

## Chaining with the rest of the toolchain

```bash
# track a scan: nmap's port list -> one crafted probe per port
PORTS=$(/opt/venvs/scapy/bin/python3 -c "
import xml.etree.ElementTree as ET
r = ET.parse('$WORK/nmap/tcp-sweep.xml').getroot()
print(','.join(p.get('portid') for p in r.findall('./host/ports/port') if p.find('state').get('state') == 'open'))")
/opt/venvs/scapy/bin/python3 -c "
from scapy.all import *
ans, _ = sr(IP(dst='$TARGET')/TCP(dport=[int(p) for p in '$PORTS'.split(',')], flags='S'), timeout=3, verbose=0)
for s, r in ans: print(s[TCP].dport, r[TCP].sprintf('%TCP.flags%'))
"
```

```bash
# scapy writes the pcap, tshark does the dissecting
/opt/venvs/scapy/bin/python3 -c "
from scapy.all import *
sn = AsyncSniffer(iface='lo', filter='tcp port 8090', store=True); sn.start()
import subprocess, time; time.sleep(0.5)
subprocess.run(['curl','-s','-o','/dev/null','http://127.0.0.1:8090/'], check=True)
time.sleep(0.5); wrpcap('$WORK/pcap/probe.pcap', sn.stop())"
tshark -r "$WORK/pcap/probe.pcap" -Y http.request -T fields -e ip.src -e http.request.uri
```

```bash
# tshark finds the interesting packet, scapy resends it
tshark -r "$WORK/pcap/session.pcap" -Y 'http.request' -T fields -e frame.number | head -1
/opt/venvs/scapy/bin/python3 -c "
from scapy.all import rdpcap, send
pk = rdpcap('$WORK/pcap/session.pcap')[int('$FRAME')-1]
send(pk, verbose=0)"
```

A mitmproxy flow file and a scapy pcap describe the same session at different
layers: mitmproxy has the decrypted application data, scapy has the bytes.
Correlate by port and timestamp, and never treat the mitmproxy file as a pcap.

## Limits, failure modes and gotchas

- **Loopback works with the default socket on 2.7.0.** Verified:
  `sr1(IP(dst='127.0.0.1')/ICMP())` returns the echo reply, and a SYN probe to
  `127.0.0.1` returns `SA` for an open port and `RA` for a closed one, with no
  `conf.L3socket` override. The `conf.L3socket = L3RawSocket` line older examples
  carry is harmless but does nothing here.
- **`srp1(Ether()/…, iface='lo')` gets no reply.** The loopback interface does not
  answer L2 frames; use L3 (`sr1`) or `sendp` to a real interface.
- **Root only.** Non-root sends raise `PermissionError [Errno 1] Operation not
  permitted`; `sniff` fails the same way.
- **No REPL workflow.** `/opt/venvs/scapy/bin/python3 -c` or a script file.
  `/usr/local/bin/scapy` accepts piped stdin (verified), but prints a banner and
  ANSI escapes — do not use it in pipelines.
- **The optional extras are not installed.** The venv carries upstream scapy
  without `scapy[all]`, so `PyX` is absent (`psdump`/`pdfdump` fail) and so is
  `cryptography` (scapy's TLS crypto features are unavailable).
- **`from scapy.all import *` is doing real work.** A `-c` one-liner that uses
  `get_if_list`, `IP`, or `Raw` must import them; `NameError` from a missing
  import is the commonest one-liner failure.
- **Bad capture filters fail silently.** The `ERROR: Cannot set filter:` line goes
  to stderr and the call returns an empty list. Check the count, not just the
  absence of an exception.
- **`AsyncSniffer` starts asynchronously.** Traffic generated immediately after
  `.start()` can be missed; sleep briefly (0.5 s was enough here) before the first
  request.
- **`rdpcap` loads everything into memory.** Use `PcapReader` for large captures.
- **scapy does not pace packets.** `send()` in a loop is a flood; add sleeps and
  limits.
- **No help beyond the console script's usage line.** `scapy -h` documents its
  startup-file flags only, and there is no `man` binary in the image. The API
  reference is <https://scapy.readthedocs.io/>; `pkt.show()` and `ls(TCP)` are the
  local introspection tools.
- **`conf` is per process.** Settings such as `conf.L3socket` do not persist
  between `/opt/venvs/scapy/bin/python3 -c` invocations; put them at the top of
  every script.

## Safety and scope

- Confirm the target and the packet types with Greg before the first `send`.
- Keep development on loopback; only retarget after the script is known-good.
- Source spoofing, crafted/reset flags, fragmentation, and floods are scope
  changes — they can look like an attack to the target's monitoring and to
  Greg's own IDS, and they need explicit approval.
- Rate-limit and cap replay loops; a scapy flood can take a small service down
  more effectively than any scanner.
- Treat every pcap as sensitive and keep crafted-packet scripts in `$WORK` with
  the findings they support.
