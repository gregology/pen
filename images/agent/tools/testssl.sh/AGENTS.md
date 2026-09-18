# testssl.sh — TLS/SSL assessment

testssl.sh answers "is this TLS actually safe?" by testing protocol versions,
cipher suites, key exchange, certificate chains, server defaults and known TLS
vulnerabilities, with machine-readable JSON output and an SSL-Labs-style rating.
It is read-only — it never authenticates, never sends credentials, and never
changes server state.

## Install and location

| | |
|---|---|
| Version | 3.2.4 (upstream source tarball, sha256-verified at image build) |
| Path | `/usr/local/bin/testssl.sh` → `/opt/testssl.sh/testssl.sh` |
| Shell | bash; drives a bundled `/opt/testssl.sh/bin/openssl.Linux.x86_64` |
| Dependency | `bsdextrautils` — installed by `install.sh`, see below |
| Runtime | root not required; no TTY required |

**The `hexdump` dependency is load-bearing and is installed deliberately.**
testssl.sh hard-requires `hexdump`, which bookworm's `bsdextrautils` provides,
and only *Recommends* it. A `--no-install-recommends` install therefore produces
a testssl.sh that dies at startup on its prerequisite check — before argument
parsing, so `--version` and `--help` fail too, with
`Fatal error: You need to install hexdump for this program to work`.
`tools/testssl.sh/install.sh` installs `bsdextrautils` explicitly and then runs
`testssl.sh --version`, so a build either produces a working tool or fails
loudly. If you ever see that fatal error, the image was built from a broken
install script, not from a target problem.

## Rules that apply to this tool

1. **Authorization first.** A TLS scan is dozens to hundreds of connections to
   one port with deliberately odd handshakes. Only against confirmed targets.
2. **Egress is the tunnel.** `--proxy` is not a containment mechanism.
3. **It is logged, and it looks like an attack.** Probe patterns include
   SSLv2/v3 hellos, renegotiation attempts and cipher scans. `--sneaky` and
   `--ids-friendly` reduce the noise but do not remove it.
4. **Runtime is minutes, not seconds.** Budget it, and always set
   `--connect-timeout`/`--openssl-timeout` so a dead port cannot hang a batch.
5. **Save evidence to `$WORK`.** `--jsonfile` (flat, jq-friendly) plus
   `--logfile`. Never reuse a filename: testssl refuses to overwrite, and
   `--append` corrupts JSON.
6. **`--phone-out` is an egress decision.** It allows CRL downloads and OCSP
   queries to third-party services. Do not enable it without explicit
   confirmation.

## Flags that matter

`testssl.sh [options] <URI>` — the URI must be last and carries the port
(`host:8443`). There is **no `--port` flag**; `-p` means `--protocols`.

### Scope of the run

| Flag | Meaning |
|---|---|
| *(no check flag)* | Runs everything except `-E` and `-g` |
| `-p, --protocols` | Protocol versions, including ALPN/HTTP2 |
| `-S, --server-defaults` | Server's default picks and certificate info |
| `-E, --cipher-per-proto` | Cipher suites per protocol |
| `-e, --each-cipher` | Every local cipher, tested remotely |
| `-s, --std, --categories` | Standard cipher categories by strength |
| `-f, --fs, --forward-secrecy` | Forward secrecy settings |
| `-P, --server-preference` | Server's protocol+cipher preference |
| `-h, --header, --headers` | HSTS, HPKP, banners, security headers, cookies |
| `-c, --client-simulation` | Which clients negotiate what |
| `-g, --grease` | Implementation bugs (GREASE, size limits) |
| `-U, --vulnerable` | All vulnerability checks |
| `-t, --starttls PROTO` | STARTTLS service: ftp, smtp, lmtp, pop3, imap, xmpp, telnet, ldap, nntp, sieve, postgres, mysql |
| `--mx DOMAIN` | Test MX hosts (STARTTLS, port 25) |
| `--ip ADDR` | Test this address instead of resolving the URI |

### Output and evidence

| Flag | Meaning |
|---|---|
| `--jsonfile, -oj FILE` | Flat JSON: one object per finding (best for `jq`) |
| `--jsonfile-pretty, -oJ FILE` | Structured JSON: one object with a `scanResult` array |
| `--logfile, -oL FILE` | Plain-text log of stdout |
| `--csvfile, -oC FILE` | Additional CSV output |
| `--htmlfile, -oH FILE` | HTML report to a named file |
| `--severity LOW\|MEDIUM\|HIGH\|CRITICAL` | Filter CSV+JSON to findings at or above this level |
| `--append` | Append to an existing output file. **Breaks JSON** |
| `--quiet` | Suppress the banner |
| `--color 0\|1\|2\|3` | 0 = no escape codes: required for clean logs |
| `--wide`, `--mapping openssl\|iana` | Report formatting |

### Traffic, timing, mass testing

| Flag | Meaning |
|---|---|
| `--fast` | Fewer checks. The tool itself warns it is not recommended any more |
| `--sneaky` | Leave fewer traces in target logs |
| `--ids-friendly` | Skip checks that tend to trip IDSs |
| `--connect-timeout N`, `--openssl-timeout N` | Bound hangers |
| `--openssl PATH` | Use a specific openssl binary |
| `--proxy host:port\|auto` | Experimental proxy support |
| `--file, -iL FILE` | Mass testing: one full command line per line |
| `--mode serial\|parallel` | Mass-testing execution mode |
| `--warnings batch\|off` | Stop on the first error, or skip and continue |
| `--phone-out` | Allow CRL/OCSP traffic to third parties — needs confirmation |
| `--mtls FILE` | Client certificate for mTLS endpoints (beta) |

## Examples

### Fingerprint one endpoint, keep both evidence forms

```bash
testssl.sh --quiet --color 0 --severity MEDIUM \
  --jsonfile "$WORK/tls-$TARGET.json" --logfile "$WORK/tls-$TARGET.log" \
  "$TARGET"                       # add :8443 for a non-standard port

jq -r '.[] | select(.severity!="OK" and .severity!="INFO") | [.id,.severity,.finding] | @tsv' \
  "$WORK/tls-$TARGET.json"
```

### Fast triage across many hosts (the mass-testing path)

```bash
httpx -l $WORK/hosts.txt -silent -ports 443,8443 -tls-grab -json \
  | jq -r '.url' | sed 's#https://##' > $WORK/tls-targets.txt

awk '{print "--quiet --color 0 --fast --protocols --server-defaults " $0}' \
  $WORK/tls-targets.txt > $WORK/tls-commands.txt
testssl.sh --file $WORK/tls-commands.txt --mode serial --logfile $WORK/tls-mass.log
```

### Certificate-only review (chain, expiry, hostname match)

```bash
testssl.sh --quiet --color 0 -S --severity MEDIUM "$TARGET"
```

The rating block also shows why a grade is capped (`Grade capped to B. TLS 1.1
offered`, `Grade capped to M. Domain name mismatch`).

### STARTTLS services (mail, LDAP, Postgres)

```bash
testssl.sh --quiet --color 0 -t smtp --protocols --server-defaults mail.$TARGET
testssl.sh --quiet --color 0 -t postgres db.$TARGET
```

## Output formats

### Flat JSON (`--jsonfile`) — use this for jq

A JSON **array**; each element has keys `id, ip, port, severity, finding`.
Severity values: `OK, INFO, LOW, MEDIUM, HIGH, WARN, CRITICAL`.

```json
{"id":"SSLv3","ip":"example.com/172.66.147.243","port":"443","severity":"OK","finding":"not offered"}
```

```bash
# only what needs action, grouped by host
jq -r '.[] | select(.severity=="CRITICAL" or .severity=="HIGH" or .severity=="MEDIUM")
       | [.ip,.port,.id,.severity,.finding] | @tsv' $WORK/tls.json
# a specific check
jq -r '.[] | select(.id=="cert_expirationStatus") | .finding' $WORK/tls.json
# counts by severity
jq -r '[.[].severity] | group_by(.) | map("\(.[0])=\(length)") | join(" ")' $WORK/tls.json
```

`--severity` filters CSV and JSON output only; the text log still contains
everything.

### Structured JSON (`--jsonfile-pretty`)

Top-level keys: `Invocation, at, openssl, scanResult, scanTime, startTime,
version`. `scanResult` is an array — one entry per scanned IP.

```bash
jq -r 'keys | join(",")' $WORK/tls-pretty.json
jq -r '.scanResult | length' $WORK/tls-pretty.json
```

### Text output

Sections print in order: protocols, server defaults, cipher categories, then the
SSL Labs rating block:

```
 Rating (experimental)
 Protocol Support (weighted)  95 (28)
 Final Score                  91
 Overall Grade                B
 Grade cap reasons            Grade capped to B. TLS 1.1 offered
```

## Failure modes

- **There is no `--port` flag.** `testssl.sh … 127.0.0.1 --port 8443` exits 254
  with `<URI> always needs to be the last parameter.` Put the port in the URI.
- **It refuses to overwrite output files.**
  `Fatal error: non-empty "…json" exists. Either use "--append" or (re)move it`,
  exit **253**. Use a unique filename per run.
- **`--append` produces invalid JSON.** Appending a second scan to a `.json`
  file yields concatenated documents and `jq` fails with `parse error`. Append
  only to logs; never to JSON.
- **Runtime scales with the number of IPs, not just the hostname.** A
  dual-stack name is scanned on both addresses. Use `--ip` to pin one.
- **`--fast` is discouraged by the tool itself.** It is still the right choice
  for a first pass across many hosts; do not present a `--fast` result as a
  complete audit.
- **The bundled openssl is ancient and incomplete**
  (`OpenSSL 1.0.2-bad`), so TLS 1.3 checks carry a caveat:
  `Local problem: Your … openssl does not support -tls1_3`. `--openssl
  /usr/bin/openssl` uses the system OpenSSL (3.0.x) instead — re-verify the
  report before drawing conclusions either way.
- **Exit codes:** `0` a completed run, `253` file-exists refusal, `254` usage
  error, `244` resource problems. A run that aborts early still prints a
  plausible-looking partial report, so check the code and the log.
- **Self-signed and mismatched certificates produce caps, not silence.** Read
  the cap reasons, not just the letter grade.
- **Mass testing turns on `--warnings batch`**, which stops the batch on the
  first error; pass `--warnings off` to continue past broken hosts.

## Notes

- Combine with the fingerprint rather than treating it as trivia: a low grade
  and its cap reasons are frequently the finding, and the `id` field names the
  exact check to cite.
- `httpx -tls-grab` tells you a port speaks TLS and summarises the certificate;
  testssl.sh tells you whether that TLS is safe. Run httpx first to build the
  target list.
- The tool is a large bash script; `--debug 0-6` writes diagnostics to `/tmp`.

## Safety

- **TLS scanning is read-only but not invisible.** Every protocol probe, cipher
  attempt and vulnerability check is logged by the target and by anything in
  front of it. Confirm the target owner expects this traffic.
- Get confirmation before: scanning any host not already authorized;
  `--phone-out` (third-party CRL/OCSP egress); `--mtls` (presents a client
  certificate and can identify the platform to the server); `-U` and the
  individual vulnerability checks against production services, which look like
  exploitation attempts; and `--mode parallel` over a host list, which
  multiplies connections.
- **Do not scan third-party TLS endpoints as part of an engagement** — CDN
  edges, mail gateways and shared load balancers belong to someone else even
  when they serve the target's name.
