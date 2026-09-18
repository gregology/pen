# masscan — worked workflows

`$TARGET` is an authorised host or range, `$WORK` the engagement directory.
masscan runs as root in this container (raw sockets). Every command here is
loud: confirm the rate with the engagement owner before raising it above the
default.

## 1. Prove what masscan will do before it does it

```bash
masscan "$TARGET" -p22,80,443 --rate 1000 --echo > "$WORK/masscan.conf"
cat "$WORK/masscan.conf"
```

`--echo` prints the parsed configuration and exits 0 without transmitting. The
keys it prints are `seed`, `rate`, `shard`, `retries`, `nocapture`, `adapter`,
`ports` and `range` — not `adapter-ip`, `router-mac` or `wait` — so it answers
which interface was chosen and at what rate, and nothing about the source
address the target will log.

The echoed file is not a usable config as written: `masscan -c` aborts on it
with `CONF: unknown config option: nocapture=servername` (exit 1) until its
`nocapture` line is removed. Neither is `--offline` an option — it fails with
`[-] FAILED: bad packet template` on every adapter, loopback included. To see
the targets a scan would cover, use the list scan, which expands them without
sending:

```bash
masscan "$TARGET" -p22,80,443 -sL
```

## 2. Single host, full port range, JSON evidence

```bash
masscan "$TARGET" -p0-65535 --rate 1000 --wait 5 -oJ "$WORK/host.json"
jq -r '.[] | .ip as $ip | .ports[] | select(.status=="open") | "\($ip):\(.port)/\(.proto) \(.reason) ttl=\(.ttl)"' \
  "$WORK/host.json" | sort -u -t: -k2 -n
```

65,536 probes at 1000 pps is ~65 s of transmit. Expect a handful of objects, one
per open port. If the file is empty:

```bash
masscan "$TARGET" -p0-65535 --rate 1000 --echo | grep -E 'adapter|rate'
```

An empty result with a plausible config usually means the target answered RSTs
(closed), not that the scan failed. An empty result with an unexpected adapter
means traffic went somewhere the kill switch dropped. Cross-check one known-open
port with `nmap -Pn -p 22,80,443 "$TARGET"` before writing "no open ports" in the
findings.

## 3. Sweep a subnet for a small port set, then split the survivors

```bash
masscan 10.0.0.0/24 -p22,80,443,445,3389,8080 --rate 2000 -oL "$WORK/lan.list"
awk '$1=="open" {print $4":"$3}' "$WORK/lan.list" | sort -u > "$WORK/lan-open.txt"
cut -d: -f1 "$WORK/lan-open.txt" | sort -u > "$WORK/lan-hosts.txt"
wc -l "$WORK/lan-hosts.txt"
```

`awk`ing the list format is cheaper than parsing JSON for a sweep, and it leaves
you a clean host list. Hand off:

```bash
httpx -l "$WORK/lan-hosts.txt" -silent -json -o "$WORK/httpx.jsonl"
nmap -iL "$WORK/lan-hosts.txt" -sV -sC --version-light -oA "$WORK/nmap-services"
```

Rule of thumb: masscan decides *where* to look, nmap and httpx decide *what it
is*.

## 4. Banners on a tunnel interface (no ARP, no local RST fight)

```bash
masscan "$TARGET" -p22,80,443,3306,6379 --banners --rate 100 --wait 15 \
  -oJ "$WORK/banners.json"
jq -r '.[] | select(.ports[0].status=="open") | "\(.ports[0].port) \(.ports[0].service // "no-banner")"' \
  "$WORK/banners.json"
```

Two different failure shapes to tell apart:

- **Port open, no banner fields** — the handshake never completed. On an
  Ethernet adapter that is usually the kernel RSTing the SYN-ACK; fix with
  `--adapter-port` plus an iptables DROP rule, or `--adapter-ip`. On this
  container's tunnel adapter masscan reports `VPN tunnel interface found` and
  uses an implicit router, so check the kernel-stack conflict first.
- **Nothing at all** — the rate is too high for the target, or the port is
  filtered. Drop to `--rate 100` and add `--retries 2`.

## 5. Split a wide scan across runs or machines

```bash
masscan 10.0.0.0/16 -p80 --rate 5000 --shards 1/3 -oJ "$WORK/shard1.json"
masscan 10.0.0.0/16 -p80 --rate 5000 --shards 2/3 -oJ "$WORK/shard2.json"
masscan 10.0.0.0/16 -p80 --rate 5000 --shards 3/3 -oJ "$WORK/shard3.json"
jq -s 'add' "$WORK"/shard[123].json > "$WORK/shard-all.json"

# or fixed-size chunks with an index
for i in 0 1000 2000 3000; do
  masscan 10.0.0.0/16 -p80 --rate 5000 --resume-index "$i" --resume-count 1000 \
    -oJ "$WORK/chunk-$i.json"
done
```

Shards partition by probe index, so the union is the same scan with no overlap.
Combine with `jq -s 'add'` for JSON, or `cat` the `-oL` files.

## 6. Interrupt and resume without losing the tail

```bash
masscan 10.0.0.0/8 -p443 --rate 20000 --excludefile "$WORK/exclude.txt" -oJ "$WORK/wide.json"
# Ctrl-C during the run:
#   the scan stops, state is written to paused.conf, and masscan waits --wait
#   seconds for late replies before exiting
masscan --resume paused.conf
```

`--resume` implies appending to the original output file. Ctrl-C is not instant:
the 10 s default wait exists so replies already in flight are recorded. Do not
`kill -9` it if you want the results.

## 7. Convert and archive

```bash
masscan "$TARGET" -p1-1024 --rate 1000 -oB "$WORK/scan.bin"
masscan --readscan "$WORK/scan.bin" -oX "$WORK/scan.xml"
masscan --readscan "$WORK/scan.bin" -oJ "$WORK/scan.json"
xmllint --format "$WORK/scan.xml" | head -30
```

Binary output is much smaller for wide scans and the only format meant to be
kept long-term; convert to XML/JSON for whichever parser the report uses.
Archive the exclusion file, the `--echo` config and the exact command alongside
it — a port list without the scanned range and rate is not evidence.
