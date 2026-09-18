# tshark — worked examples

Every command below was run in the agent container and the output shown is real.
Local traffic is generated with the container's own loopback HTTP server, so the
examples are safe to repeat; the one external example is a single request to
`example.com`.

## 0. Start a local target and a capture

```bash
mkdir -p /tmp/lab && cd /tmp/lab
nohup python3 -m http.server 8080 --bind 127.0.0.1 >httpd.log 2>&1 &
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8080/
```

```
200
```

## 1. Capture loopback HTTP and read it back

```bash
( for i in 1 2 3; do curl -s -o /dev/null http://127.0.0.1:8080/; sleep 0.2; done ) &
tshark -i lo -f 'tcp port 8080' -a duration:5 -w /tmp/lab/http.pcap
```

```
36 packets captured
```

```bash
tshark -r /tmp/lab/http.pcap -Y http.request \
       -T fields -e ip.src -e tcp.srcport -e http.request.method -e http.request.uri -e http.host
```

```
127.0.0.1	40944	GET	/	127.0.0.1:8080
127.0.0.1	40962	GET	/	127.0.0.1:8080
127.0.0.1	40976	GET	/	127.0.0.1:8080
```

Packet counts and source ports depend on how many requests finish before the
autostop fires (a repeat run captured 12 packets with one request); the filters
are the reproducible part, not the line count.

The capture filter (`-f`) limited what was recorded; the display filter (`-Y`)
selected the requests afterwards. Swapping them is the most common mistake and
fails with `Only read filters, not capture filters, can be specified when reading
a capture file.` / `"port" was unexpected in this context.`

## 2. Capture one authorized external TLS session and extract the SNI

```bash
( sleep 1; curl -s -o /dev/null -w 'http_code=%{http_code}\n' https://example.com/ ) &
tshark -i eth0 -f 'tcp port 443' -a duration:8 -w /tmp/lab/tls.pcap
```

```
http_code=200
24 packets captured
```

```bash
capinfos -c -u -a -e -T /tmp/lab/tls.pcap
```

```
File name	Number of packets	Capture duration (seconds)	Start time	End time
/tmp/lab/tls.pcap	24	0.212058988	2026-09-17 20:47:50.650487940	2026-09-17 20:47:50.862546928
```

Timestamps and duration change per run (a repeat run measured 0.088 s); the packet
count is stable for a single `curl` request.

```bash
tshark -r /tmp/lab/tls.pcap -Y 'tls.handshake.type==1' \
       -T fields -e ip.dst -e tls.handshake.extensions_server_name
```

```
104.20.23.154	example.com
```

## 3. Field output as CSV, ready for a report

```bash
tshark -r /tmp/lab/http.pcap -Y http.request \
       -T fields -E header=y -E separator=, -E quote=d \
       -e frame.number -e ip.src -e http.host -e http.request.uri
```

```
frame.number,ip.src,http.host,http.request.uri
"4","127.0.0.1","127.0.0.1:8080","/"
"16","127.0.0.1","127.0.0.1:8080","/"
"28","127.0.0.1","127.0.0.1:8080","/"
```

One row per captured request, so the row count matches whatever landed in the
pcap; `-E header=y` is what makes the file self-describing.

## 4. Statistics: protocol mix, conversations, endpoints

```bash
tshark -r /tmp/lab/tls.pcap -q -z io,phs
```

```
 Protocol Hierarchy Statistics
eth                                      frames:24 bytes:7719
  ip                                     frames:24 bytes:7719
    tcp                                  frames:24 bytes:7719
      tls                                frames:12 bytes:6911
        tcp.segments                     frames:1 bytes:1213
```

```bash
tshark -r /tmp/lab/tls.pcap -q -z conv,tcp
```

```
TCP Conversations
172.17.0.5:45392  <-> 104.20.23.154:443   11 6080 bytes  13 1639 bytes  24 7719 bytes  0.2121
```

```bash
tshark -r /tmp/lab/http.pcap -q -z io,stat,0.1
```

```
| IO Statistics               |
| Duration: 0.2 secs          |
| Interval: 0.1 secs          |
|  Interval   | Frames | Bytes |
| 0.0 <> 0.1  |      9 |  5118 |
| 0.1 <> 0.2  |      8 |  1359 |
```

Interval tables are bounded by the capture's duration: a capture shorter than the
interval prints the table headers with no interval rows (observed on a 0.001 s
capture), which is not an error.

## 5. Follow a stream and carve the objects

```bash
tshark -r /tmp/lab/http.pcap -q -z follow,tcp,ascii,0
```

```
Follow: tcp,ascii
Filter: tcp.stream eq 0
Node 0: 127.0.0.1:40944
Node 1: 127.0.0.1:8080
GET / HTTP/1.1
Host: 127.0.0.1:8080
User-Agent: curl/7.88.1
Accept: */*
```

```bash
mkdir -p /tmp/lab/objs
tshark -r /tmp/lab/http.pcap --export-objects http,/tmp/lab/objs -q
ls /tmp/lab/objs/
```

```
%2f  %2f(1)  %2f(2)
```

Object names are derived from the URL path, so `/` becomes `%2f`, and the count
follows the number of captured requests. Read them with `file` and `head` before
assuming they are HTML.

## 6. Ring buffer for a bounded long capture

```bash
( for i in $(seq 1 60); do curl -s -o /dev/null http://127.0.0.1:8080/; sleep 0.1; done ) &
sleep 1
tshark -i lo -f 'tcp port 8080' -b filesize:8 -b files:3 -a duration:8 -w /tmp/lab/ring.pcap
ls -la /tmp/lab/ring_*
```

```
-rw------- 1 root root 8560 ... /tmp/lab/ring_00011_20260917204825.pcap
-rw------- 1 root root 8460 ... /tmp/lab/ring_00012_20260917204825.pcap
-rw------- 1 root root 684  ... /tmp/lab/ring_00013_20260917204826.pcap
```

```bash
tshark -i lo -f 'tcp port 8080' -b duration:2 -b files:2 -a duration:6 -w /tmp/lab/dur.pcap
ls /tmp/lab/dur_*
```

```
/tmp/lab/dur_00002_20260917204832.pcap
/tmp/lab/dur_00003_20260917204834.pcap
```

`-b files:N` keeps only the newest N files; older ones are deleted as the ring
rotates. The base name you pass to `-w` is a prefix, not a filename: the sequence
number depends on what was already in the directory, so read the files with
`ls -t` rather than guessing a name. Intervals shorter than the capture duration
are what produce multiple files, so keep generating traffic while the ring runs.

## 7. Find a field name, then use it

```bash
tshark -G fields | rg -N 'dns.qry.name|tls.handshake.extensions_server_name' | cut -f2,3,4
```

```
Name	dns.qry.name	FT_STRING
Name Length	dns.qry.name.len	FT_UINT16
Server Name list length	dtls.handshake.extensions_server_name_list_len	FT_UINT16
Server Name length	dtls.handshake.extensions_server_name_len	FT_UINT16
Server Name	tls.handshake.extensions_server_name	FT_STRING
```

Columns are `F|P`, description, abbreviation, type, parent protocol. Match on
column 3; read the description and type from columns 2 and 4.

## 8. Read a scapy-generated pcap (cross-tool)

```bash
python3 -c "
from scapy.all import wrpcap, Ether, IP, TCP
wrpcap('/tmp/lab/crafted.pcap', [Ether()/IP(dst='192.0.2.1')/TCP(dport=443, flags='S')])"
tshark -r /tmp/lab/crafted.pcap -T fields -e ip.dst -e tcp.flags.syn
```

```
192.0.2.1	1
```

## 9. Split and merge captures before analysis

```bash
editcap -c 10 /tmp/lab/tls.pcap /tmp/lab/split.pcap
ls /tmp/lab/split*
```

```
/tmp/lab/split_00000_20260917204750.pcap
/tmp/lab/split_00001_20260917204750.pcap
/tmp/lab/split_00002_20260917204750.pcap
```

```bash
mergecap -w /tmp/lab/merged.pcap /tmp/lab/http.pcap /tmp/lab/tls.pcap
capinfos -c /tmp/lab/merged.pcap
```

```
Number of packets:   36
```

## 10. What "no results" looks like

```bash
tshark -r /tmp/lab/http.pcap -Y 'dns' -T fields -e dns.qry.name | wc -l   # 0, exit 0
tshark -r /tmp/lab/nosuch.pcap                                            # exit 2
tshark -r /tmp/lab/http.pcap -Y 'http.request and and'                     # exit 2
```

A filter with no matches is indistinguishable from a capture with no traffic if
you only look at the exit code: cross-check with `capinfos -c`.
