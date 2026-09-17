# testssl.sh

TLS/SSL assessment for a live endpoint. It answers "is this TLS actually safe?"
by testing protocol versions, cipher suites, key exchange, certificate chains,
server defaults and known TLS vulnerabilities, with machine-readable JSON output
and an SSL-Labs-style rating. It is read-only — it never authenticates, never
sends credentials, and never changes server state.

**In the image as built, testssl.sh does not run.** Its prerequisite check fails
because `hexdump` is missing. Read the next section before planning any TLS work.

## Installation and location

| Item | Value |
|---|---|
| Version | 3.2.4 — from `/opt/testssl.sh/CHANGELOG.md` (`### Security fixes in 3.2`, `(3.2.4)`) and the image build's pinned `TESTSSL_VERSION`. `testssl.sh --version` cannot be used (see below) |
| Path | `/usr/local/bin/testssl.sh` → symlink to `/opt/testssl.sh/testssl.sh` |
| Install | upstream source tarball `v3.2.4` extracted to `/opt/testssl.sh/` |
| Shell | bash; exits through `openssl` (bundled `/opt/testssl.sh/bin/openssl.Linux.x86_64`, "OpenSSL 1.0.2-bad (1.0.2k-dev)") |
| Runs as | root; no TTY required |
| Blocking defect | `hexdump` is not installed (`bsdextrautils` is absent), so **every** invocation dies at startup |

Verified failure in the image:

```
$ testssl.sh --version
Fatal error: You need to install hexdump for this program to work
$ testssl.sh --help
Fatal error: You need to install hexdump for this program to work
```

The message comes from the prerequisite loop at `testssl.sh` line 24168
(`fatal "You need to install ${binary} for this program to work"`), which runs
before argument handling, so no flag avoids it — not even `--help`.

Verified fix (scratch container only):

```
$ apt-get update && apt-get install -y --no-install-recommends bsdextrautils
$ command -v hexdump
/usr/bin/hexdump        # util-linux 2.38.1
$ testssl.sh --version  # now works
```

Installing packages at runtime is not how this platform adds tools — the fix
belongs in `images/agent/Dockerfile` (add `bsdextrautils`, or the `hexdump`
package it provides) followed by an image rebuild. Everything below was verified
against this image **after** that scratch install; treat the flags as accurate
for testssl.sh 3.2.4, and the image as unusable until it is rebuilt.

## Rules that apply to this tool

1. **Authorization first.** A TLS scan is read-only, but it is dozens to
   hundreds of connections to one port with deliberately odd handshakes. Only
   against targets explicitly confirmed for the engagement.
2. **Everything leaves through the VPN.** One non-loopback interface: the
   WireGuard tunnel in the shared netns. `--proxy` is not containment.
3. **It is still logged, and it still looks like an attack.** Verified probe
   patterns include SSLv2/v3 hellos, renegotiation attempts and cipher scans.
   A target IDS or WAF will see them; `--sneaky` and `--ids-friendly` reduce the
   noise but do not remove it.
4. **Runtime is minutes, not seconds.** Verified: 408 s for `example.com`
   (two IPs, full scan), 269 s with `--fast --sneaky`, 214 s against a local
   endpoint, 17 s for a `--fast --protocols` subset. Budget time and use
   `--connect-timeout`/`--openssl-timeout` so a dead port cannot hang a batch.
5. **Save evidence to the working directory.** `--jsonfile $WORK/<name>.json`
   (flat, jq-friendly) and `--logfile $WORK/<name>.log`. Never reuse a filename:
   testssl refuses to overwrite, and `--append` corrupts the JSON (below).
6. **`--phone-out` is an egress decision.** It allows CRL downloads and OCSP
   queries to third-party services. Do not enable it without explicit
   confirmation.

## Command reference

`testssl.sh [options] <URI>` — the URI must be last. `<URI>` is
`host | host:port | URL | URL:port`; port 443 is the default. There is **no
`--port` flag** (verified: it exits 254 with a usage error). Non-standard ports
go in the URI.

### Scope of the run

| Flag | Meaning |
|---|---|
| *(no check flag)* | Runs everything except `-E` and `-g` |
| `-p, --protocols` | Protocol versions, including ALPN/HTTP2 and SPDY |
| `-S, --server-defaults` | Server's default picks and certificate info |
| `-E, --cipher-per-proto` | Cipher suites per protocol |
| `-e, --each-cipher` | Every local cipher, tested remotely |
| `-s, --std, --categories` | Standard cipher categories by strength |
| `-f, --fs, --forward-secrecy` | Forward secrecy settings |
| `-P, --server-preference` | Server's protocol+cipher preference |
| `-h, --header, --headers` | HSTS, HPKP, banners, security headers, cookies |
| `-c, --client-simulation` | Which clients negotiate what |
| `-g, --grease` | Implementation bugs (GREASE, size limits) |
| `-U, --vulnerable` | All vulnerability checks (`-H` Heartbleed, `-I` CCS, `-T` Ticketbleed, `--BB` ROBOT, `-R` renegotiation, `-C` CRIME, `-B` BREACH, `-O` POODLE, `-W` SWEET32, `-A` BEAST, `-L` LUCKY13, `-F` FREAK, `-J` LOGJAM, `-D` DROWN, `-4` RC4, …) |
| `-t, --starttls PROTO` | STARTTLS service: ftp, smtp, lmtp, pop3, imap, xmpp, xmpp-server, telnet, ldap, nntp, sieve, postgres, mysql |
| `--mx DOMAIN` | Test MX hosts (STARTTLS, port 25) |
| `--ip ADDR` | Test this address instead of resolving the URI |

### Output and evidence

| Flag | Meaning |
|---|---|
| `--jsonfile, -oj FILE` | Flat JSON: one object per finding (best for `jq`) |
| `--jsonfile-pretty, -oJ FILE` | Structured JSON: one object with a `scanResult` array |
| `--logfile, -oL FILE` | Plain-text log of stdout |
| `--csvfile, -oC FILE` | Additional CSV output to a file or directory |
| `--html` / `--htmlfile, -oH FILE` | HTML report to an auto-named file / to a named file |
| `--severity LOW\|MEDIUM\|HIGH\|CRITICAL` | Filter CSV+JSON to findings at or above this level |
| `--append` | Append to an existing output file. **Breaks JSON** (see gotchas) |
| `--quiet` | Suppress the banner (acknowledges the usage terms) |
| `--color 0\|1\|2\|3` | 0 = no escape codes: required for clean logs |
| `--wide`, `--mapping openssl\|iana`, `--colorblind` | Report formatting |
| `--debug 0-6` | Debug output (kept in `/tmp` for levels ≥1) |

### Traffic, timing, mass testing

| Flag | Meaning |
|---|---|
| `--fast` | Fewer checks. Verified warning printed: `'--fast' can have some undesired side effects thus it is not recommended to use anymore` |
| `--sneaky` | Leave fewer traces in target logs (User-Agent, referer) |
| `--ids-friendly` | Skip checks that tend to trip IDSs |
| `--connect-timeout N`, `--openssl-timeout N` | Bound hangers |
| `--openssl PATH` | Use a specific openssl binary |
| `--proxy host:port\|auto` | Experimental proxy support |
| `--file, -iL FILE` | Mass testing: one full command line per line (comments with `#`, or nmap `-oG` output) |
| `--mode serial\|parallel`, `--parallel`, `--serial` | Mass-testing execution mode |
| `--warnings batch\|off` | Stop on the first testing error, or skip and continue (implied `batch` with `--file`) |
| `--phone-out` | Allow CRL/OCSP traffic to third parties — needs confirmation |
| `--mtls FILE` | Client certificate for mTLS endpoints (beta) |

## Typical workflows

1. **Fingerprint one endpoint, keep both evidence forms.**

   ```bash
   testssl.sh --quiet --color 0 --severity MEDIUM \
     --jsonfile "$WORK/tls-$TARGET.json" --logfile "$WORK/tls-$TARGET.log" \
     "$TARGET"                       # add :8443 for a non-standard port
   jq -r '.[] | select(.severity!="OK" and .severity!="INFO") | [.id,.severity,.finding] | @tsv' \
     "$WORK/tls-$TARGET.json"
   ```

2. **Fast triage across many hosts (the mass-testing path).**

   ```bash
   httpx -l $WORK/hosts.txt -silent -ports 443,8443 -tls-grab -json \
     | jq -r '.url' | sed 's#https://##' > $WORK/tls-targets.txt
   awk '{print "--quiet --color 0 --fast --protocols --server-defaults " $0}' \
     $WORK/tls-targets.txt > $WORK/tls-commands.txt
   testssl.sh --file $WORK/tls-commands.txt --mode serial \
     --logfile $WORK/tls-mass.log
   ```

3. **Certificate-only review** (chain, expiry, hostname match):

   ```bash
   testssl.sh --quiet --color 0 -S --severity MEDIUM "$TARGET"
   ```

   The rating block also shows why a grade is capped (verified output included
   `Grade capped to B. TLS 1.1 offered` and `Grade capped to M. Domain name
   mismatch`).

4. **STARTTLS services** (mail, LDAP, Postgres):

   ```bash
   testssl.sh --quiet --color 0 -t smtp --protocols --server-defaults mail.$TARGET
   testssl.sh --quiet --color 0 -t postgres db.$TARGET
   ```

5. **Two-hour budget, full audit of one host.** Run the default (no check
   flags) with timeouts, and do not stack `-e` or `-g` unless they are needed:

   ```bash
   testssl.sh --quiet --color 0 --connect-timeout 10 --openssl-timeout 10 \
     --jsonfile-pretty "$WORK/tls-full-$TARGET.json" "$TARGET"
   ```

## Output and parsing

### Flat JSON (`--jsonfile`) — use this for jq

A JSON **array**; each element has keys `id, ip, port, severity, finding`
(verified). Severity values seen: `OK, INFO, LOW, MEDIUM, HIGH, WARN, CRITICAL`.

```
$ jq -r 'length' tls.json
6                       # after --severity HIGH
$ jq -r '.[] | [.id, .severity] | @tsv' tls.json
cert_subjectAltName	HIGH
cert_trust	HIGH
cert_chain_of_trust	CRITICAL
...
$ jq -c '.[3]' example-fast.json
{"id":"SSLv3","ip":"example.com/172.66.147.243","port":"443","severity":"OK","finding":"not offered"}
```

```bash
# only what needs action, grouped by host
jq -r '.[] | select(.severity=="CRITICAL" or .severity=="HIGH" or .severity=="MEDIUM") | [.ip,.port,.id,.severity,.finding] | @tsv' $WORK/tls.json
# a specific check
jq -r '.[] | select(.id=="cert_expirationStatus") | .finding' $WORK/tls.json
# counts by severity
jq -r '[.[].severity] | group_by(.) | map("\(.[0])=\(length)") | join(" ")' $WORK/tls.json
```

`--severity` filters CSV and JSON output only; the text log still contains
everything.

### Structured JSON (`--jsonfile-pretty`)

Verified top-level keys: `Invocation, at, openssl, scanResult, scanTime,
startTime, version`. `scanResult` is an array — one entry per scanned IP.

```bash
jq -r 'keys | join(",")' $WORK/tls-pretty.json
jq -r '.scanResult | length' $WORK/tls-pretty.json
jq -r '.scanResult[] | .scanTime // empty' $WORK/tls-pretty.json
```

### Text output

Sections printed in order: protocols, server defaults, cipher categories, and
the SSL Labs rating block:

```
 Rating (experimental)
 Protocol Support (weighted)  95 (28)
 Key Exchange     (weighted)  90 (27)
 Cipher Strength  (weighted)  90 (36)
 Final Score                  91
 Overall Grade                B
 Grade cap reasons            Grade capped to B. TLS 1.1 offered
 Done 2026-09-17 20:42:03 [ 408s] -->> 172.66.147.243:443 (example.com) <<--
```

## Chaining with the rest of the toolchain

```bash
# httpx says what speaks TLS; testssl.sh says whether it is safe
httpx -l $WORK/hosts.txt -silent -ports 443,8443 -tls-grab -json \
  | jq -r '.url' | sed 's#https://##' | sort -u > $WORK/tls-targets.txt
while read -r hp; do
  testssl.sh --quiet --color 0 --fast --protocols --server-defaults \
    --jsonfile "$WORK/tls-$(echo "$hp" | tr ':/' '__').json" "$hp"
done < $WORK/tls-targets.txt

# only scan what is new this run, then merge the JSON
jq -s 'add' $WORK/tls-*.json > $WORK/tls-all.json
jq -r '.[] | select(.severity=="CRITICAL" or .severity=="HIGH") | [.ip,.port,.id,.finding] | @tsv' \
  $WORK/tls-all.json > $WORK/tls-findings.tsv

# feed certificate/host findings into the report, and TLS CVEs into nuclei
awk -F'\t' '{print $1}' $WORK/tls-findings.tsv | sed 's#/.*##' | sort -u > $WORK/tls-hosts.txt
nuclei -l $WORK/tls-hosts.txt -t ssl/ -jsonl -o $WORK/nuclei-ssl.jsonl

# wafw00f + testssl.sh together: what is in front, and how good the TLS is
wafw00f -i $WORK/tls-targets.txt -f json -o $WORK/waf.json
```

## Limits, failure modes and gotchas

- **The tool does not run at all in this image.** `hexdump` is missing, and the
  prerequisite check precedes argument parsing, so `--version` and `--help` fail
  too. Fix the image (add `bsdextrautils`) before relying on any of this file.
- **There is no `--port` flag.** Verified: `testssl.sh … 127.0.0.1 --port 8443`
  exits 254 with `<URI> always needs to be the last parameter.`; `-p` means
  `--protocols`. Put the port in the URI: `testssl.sh 127.0.0.1:8443`.
- **It refuses to overwrite output files.** Verified:
  `Fatal error: non-empty "…json" exists. Either use "--append" or (re)move it`,
  exit code **253**. Use a unique filename per run.
- **`--append` produces invalid JSON.** Verified: appending a second scan to a
  `.json` file yields concatenated documents, and `jq` fails with
  `parse error: Expected value before ','`. Append only to logs; never to JSON.
- **Runtime scales with the number of IPs, not just the hostname.** Verified:
  `example.com` resolved to two addresses and the run scanned both (`Done
  testing now all IP addresses (on port 443): …`), 408 s total. Use `--ip` to
  pin one address, or scan in parallel deliberately.
- **`--fast` is discouraged by the tool itself.** Verified startup warning:
  `'--fast' can have some undesired side effects thus it is not recommended to
  use anymore`. It is still the right choice for a first pass across many hosts;
  do not present a `--fast` result as a complete audit.
- **The bundled openssl is ancient and incomplete.** `/opt/testssl.sh/bin/openssl.Linux.x86_64`
  is `OpenSSL 1.0.2-bad (1.0.2k-dev)`; verified warning:
  `Local problem: Your /opt/testssl.sh/bin/openssl.Linux.x86_64 does not support -tls1_3`.
  TLS 1.3 checks therefore have a caveat. `--openssl /usr/bin/openssl` uses the
  system OpenSSL (3.0.20 in this image) instead — verify the resulting report
  before drawing conclusions either way.
- **Exit codes:** `0` a completed run, `253` file-exists refusal, `254` usage
  error (`ERR_CMDLINE`), `244` resource problems. Check the exit code and the
  log; a run that aborts early still prints a plausible-looking partial report.
- **Self-signed and mismatched certificates produce caps, not silence.** In the
  verification run the local fixture scored `Grade capped to T. Issues with
  chain of trust (self signed)` and `Grade capped to M. Domain name mismatch` —
  read the cap reasons, not just the letter.
- **Mass testing turns on `--warnings batch`**, which stops the batch on the
  first testing error; pass `--warnings off` if you want it to continue past
  broken hosts.

## Safety and scope

- **TLS scanning is read-only but not invisible.** Every protocol probe, cipher
  attempt and vulnerability check is logged by the target and by anything in
  front of it. Confirm that the target owner expects this traffic.
- **Get confirmation before:** scanning any host not already authorized;
  `--phone-out` (third-party CRL/OCSP egress); `--mtls` (presents a client
  certificate and can identify the platform to the server); `-U`/`-H`/`-I`/`-R`
  vulnerability checks against production services, which look like exploitation
  attempts; and `--mode parallel` over a host list, which multiplies connections.
- **Do not scan third-party TLS endpoints as part of an engagement** — CDN
  edges, mail gateways and shared load balancers belong to someone else even
  when they serve the target's name.
