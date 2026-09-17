# hydra

Online password guessing against network services. hydra takes a login list
and a password list (or a brute-force charset) and makes real authentication
attempts against FTP, HTTP(S) forms, SMB, SSH, RDP, MSSQL, MySQL, LDAP, SMTP,
SNMP and others. Unlike hashcat and john it needs no hashes — which is exactly
why it is the most dangerous tool in this directory: every attempt is a real
logon against a real service, it appears in that service's logs, and it can
lock accounts out.

Use it only when online validation is authorized and the failure counters are
known. For anything where a hash can be obtained instead, prefer the offline
tools.

## Installation and location

| Item | Value |
|---|---|
| Binary | `/usr/bin/hydra` |
| Version | 9.4 (Debian bookworm package) |
| Config | none required; optional restore file `./hydra.restore` in the cwd |
| Output | stdout; `-o FILE` writes text (default), JSON or JSONv1 |
| Wordlists | `/opt/wordlists/SecLists/Passwords/`, `/opt/wordlists/SecLists/Usernames/` |

Compiled-in services (`hydra -h`, last line): `adam6500 asterisk cisco
cisco-enable cobaltstrike cvs firebird ftp[s] http[s]-{head|get|post}
http[s]-{get|post}-form http-proxy http-proxy-urlenum icq imap[s] irc ldap2[s]
ldap3[-{cram|digest}md5][s] memcached mongodb mssql mysql nntp oracle-listener
oracle-sid pcanywhere pcnfs pop3[s] postgres radmin2 rdp redis rexec rlogin
rpcap rsh rtsp s7-300 sip smb smtp[s] smtp-enum snmp socks5 ssh sshkey svn
teamspeak telnet[s] vmauthd vnc xmpp`.

**Not compiled in** (verified): `afp ncp oracle sapr3 smb2`. There is no SMB2
support — the `smb` module speaks SMB1/NTLM only.

## Rules that apply to this tool

1. **Explicit human confirmation per target, every time.** hydra authenticates
   to real services. Confirm the host, the service, the account list and the
   password list with Greg before the first attempt — an unanswered question is
   not confirmation, and neither is a previously authorized scan of the same
   host.
2. **Assume it will lock accounts and trip alarms.** Every attempt is a real
   logon. AD, Okta-fronted apps, and most hardened services count failures per
   account and per source IP. Ask for the lockout threshold and the source IP's
   reputation before running, and start at `-t 1`.
3. **Written scope, lockout-safe rate.** Default is `-t 16` parallel attempts
   per target. Use `-t 1` (or `-t 2`) plus `-W` between attempts for anything
   with a failure counter or an IDS, and `-e nsr` before any list-based attack.
4. **All traffic exits the WireGuard tunnel** in the shared netns. hydra has no
   proxy setting of its own that changes containment — `HYDRA_PROXY` routes
   through a proxy *inside* the tunnel, it does not replace it.
5. **Never `-x` brute force without a written ceiling.** A charset attack on a
   live service is a denial-of-service with extra steps; state the maximum
   candidate count and the expected duration first.
6. **Evidence into `$WORK`.** `-o "$WORK/loot/hydra/<target>-<service>.txt"`,
   plus the exact command line, so a finding can be reproduced without the
   transcript.

## Command reference

| Flag | Meaning |
|---|---|
| `-l LOGIN` / `-L FILE` | Single login, or a file of logins |
| `-p PASS` / `-P FILE` | Single password, or a file of passwords |
| `-C FILE` | Colon-separated `login:pass` pairs instead of `-L`/`-P` |
| `-e nsr` | Also try `n` null password, `s` login as password, `r` reversed login |
| `-x MIN:MAX:CHARSET` | Brute-force generation (`-x -h` prints the charset help); `-y` disables the `a`/`A`/`1` placeholders, `-r` disables random order |
| `-u` | Loop over users instead of passwords (implied by `-x`) |
| `-s PORT` | Non-default port |
| `-S` | SSL connect (legacy `-O` enables SSLv2/v3) |
| `-f` / `-F` | Stop after the first found pair, per host / globally (`-M` mode) |
| `-t N` | Parallel connects per target (**default 16** — the lockout dial) |
| `-T N` | Parallel connects overall with `-M` (default 64) |
| `-w TIME` / `-W TIME` | Wait for a response (32 s) / between connects per thread (0 s) |
| `-c TIME` | Wait per login attempt across all threads (forces `-t 1`) |
| `-M FILE` | Target list file, one `host[:port]` per line — no positional target allowed |
| `-o FILE` | Write found pairs to FILE |
| `-b FORMAT` | Format for `-o`: `text` (default), `json`, `jsonv1` |
| `-R` | Restore a previous aborted session from `./hydra.restore` |
| `-I` | Ignore an existing restore file (skips the 10-second wait) |
| `-K` | Do not redo failed attempts (mass-scan friendly) |
| `-q` | Suppress connection-error messages (partial — see gotchas) |
| `-v` / `-V` / `-d` | Verbose / show each login+pass attempt / debug |
| `-U SERVICE` | Print the module's usage and parameter syntax |
| `-m OPT` | Module-specific options (e.g. SMB dialect) |
| `-4` / `-6` | IPv4 (default) / IPv6 |

Service invocation form: `hydra [options] server service [OPT]`. The module's
`OPT` string is a **separate argument**; appending it to the service name
produces `[ERROR] Unknown service: …`.

### HTTP form module syntax

```
http-get-form://<path>:<params>:<condition>[:<optional>]
http-post-form://<path>:<params>:<condition>[:<optional>]
```

- `<params>`: the form body/query with `^USER^` and `^PASS^` placeholders
  (base64 variants `^USER64^` / `^PASS64^`).
- `<condition>`: `F=<string>` fails the attempt when that string is present
  (the default interpretation), `S=<string>` succeeds when present. Getting
  this backwards is the classic hydra mistake — check the app's failure text
  first, or run once with `-d` to see the request and response.
- Optional headers: `H=Cookie\: sessid=aaaa` for a required session cookie.
- Colons inside values must be escaped `\:`.

## Typical workflows

### 1. Confirm the module syntax, then check one credential

```bash
hydra -U http-post-form
hydra -U smb
hydra -h | tail -3            # compiled-in service list

hydra -l admin -p 'Summer2026!' -t 1 -f -s 8443 -S \
  10.0.0.5 https-post-form "/login:username=^USER^&password=^PASS^:F=Invalid credentials"
```

`https-post-form` / `https-get-form` are the TLS variants of the form modules
(verified via `hydra -U https-post-form`).

### 2. Small list-based attack with an evidence file

```bash
mkdir -p "$WORK/loot/hydra"
hydra -L /opt/wordlists/SecLists/Usernames/top-usernames-shortlist.txt \
      -P /opt/wordlists/SecLists/Passwords/Common-Credentials/10k-most-common.txt \
      -t 2 -W 2 -f -o "$WORK/loot/hydra/webapp-post.json" -b json \
      10.0.0.5 -s 8443 -S \
      https-post-form "/login:username=^USER^&password=^PASS^:F=Invalid credentials"
```

`-t 2 -W 2` is the lockout-conscious setting: two concurrent attempts, two
seconds between attempts per thread. 10 000 passwords at that rate is ~2.8
hours — say so before starting, and shorten the list.

### 3. Spray one password across many hosts

```bash
printf '10.0.0.11\n10.0.0.12\n10.0.0.13\n' > "$WORK/targets-ssh.txt"
hydra -M "$WORK/targets-ssh.txt" -l deploy -p 'Company!234' -t 1 -W 1 -F ssh
```

`-M` takes no positional target; `-F` stops the whole run on the first hit.

### 4. SMB/NTLM with a hash instead of a password

```bash
hydra -l administrator -p 'aad3b435b51404eeaad3b435b51404ee:8846f7eaee8fb117ad06bdd830b7586c' \
      -m 'local hash' 10.0.0.5 smb
```

The SMB module accepts `-p LMHASH:NTHASH` with `-m "local hash"`; `-m "local
lmv2"` forces LMv2, and `-m "other_domain:DOM"` sets the domain. Only SMB1/NTLM
is available (`smb2` is not compiled in).

### 5. Resume a stopped run

```bash
cd "$WORK/loot/hydra"      # hydra.restore lives here
hydra -R
```

## Output and parsing

Per attempt with `-V`:

```
[ATTEMPT] target 127.0.0.1 - login "admin" - pass "foo" - 1 of 4 [child 0] (0/0)
```

Hit line:

```
[8899][http-post-form] host: 127.0.0.1   login: admin   password: s3cr3t
1 of 1 target successfully completed, 1 valid password found
```

Text `-o` file: a comment header with the full command line, then the hit
lines — parse with `grep -v '^#'` and split on whitespace.

JSON `-o` file (`-b json`, verified structure):

```json
{ "generator": {
	"software": "Hydra", "version": "v9.4", "built": "2026-09-17 20:40:18",
	"server": "127.0.0.1", "service": "http-get-form", "jsonoutputversion": "1.00",
	"commandline": "hydra -l admin -P words.txt -s 8898 -t 4 -f -o hj.json -b json 127.0.0.1 http-get-form /login:username=^USER^&password=^PASS^:F=Login failed"
	},
"results": [
	{"port": 8898, "service": "http-get-form", "host": "127.0.0.1", "login": "admin", "password": "s3cr3t"}
	],
"success": true,
"errormessages": [  ],
"quantityfound": 1   }
```

`-b jsonv1` produced the same structure in this build. Parse with
`jq -r '.results[] | "\(.host):\(.port) \(.login):\(.password)"'`.

Exit status is `0` in both the found and not-found cases — check
`quantityfound` (JSON) or the "N valid password found" line (text), not the
exit code.

## Chaining with the rest of the toolchain

- **nmap → hydra.** Only attack services nmap actually found, and only the
  credential paths in scope. `naabu`/`nmap` output gives `host:port` lines that
  map onto `-M` target files.
- **Usernames from netexec/impacket → hydra.** `nxc smb --users`,
  `--rid-brute`, `impacket lookupsid.py` or an LDAP dump produce the account
  list; `hydra` takes it with `-L`. Do not spray every enumerated account —
  pick the confirmed ones.
- **Hydra hit → netexec re-validation.** A pair found on one service is worth
  testing (within scope) on the others with
  `nxc <proto> <host> -u user -p pass --continue-on-success`, which runs with a
  much higher default thread count — cap it.
- **Hydra hit → hashcat/john for the rest.** If the same password policy holds,
  a recovered password informs the rule set (`best64`, `dive`) for offline
  cracking of the rest of the dump — far cheaper than more online attempts.
- **Evidence into the findings note.** The `-o` file plus the command line and
  the account list used; note explicitly which accounts were tried, because
  that is what the target's logs will show.

## Limits, failure modes and gotchas

**Lockout is the default outcome of carelessness.** `-t 16` against a
domain-joined service will lock accounts. Lockout policies are site-specific
(thresholds of 3–10 failures over a 15–30 minute window are common; a fresh AD
domain has no lockout at all until a policy is set), so ask rather than assume
— and remember the threshold applies to accounts, not to your run. A 10 000
word list at `-t 16` sends attempts far faster than any real policy can absorb.
Use spraying (`-p` single + `-L` list, `-t 1 -W` between rounds) instead of a
full list attack, and set `--ufail-limit`-style discipline in nxc if you switch
tools.

**`-q` does not silence everything.** Verified: with a closed port, both
`hydra … ssh` and `hydra … -q ssh` printed
`[ERROR] could not connect to ssh://127.0.0.1:9 - Connection refused`. Plan for
noisy output and filter it rather than relying on `-q`.

**`-M` and a positional target are mutually exclusive.** `hydra -M hosts.txt …
127.0.0.1 http-get-form …` fails with
`[ERROR] The -M FILE option can not be used together with a host on the
commandline`. Drop the positional host.

**Module `OPT` must be its own argument.** `hydra … 127.0.0.1
http-get-form:/login:…` gives `[ERROR] Unknown service: http-get-form:/login:…`.

**The `F=`/`S=` condition decides correctness, not hydra.** A wrong failure
string produces either zero results or a false positive. Verify manually with
`curl` first, then confirm the first hit with a single `-l/-p` run.

**HTTP module quirk.** hydra always fetches the form URL first (to grab a
cookie) and follows up to 5 redirects; a login endpoint that redirects on
success needs the `S=` success condition or a `F=` string that is present only
on failure. `-d` shows the raw request/response.

**Restore file location.** `./hydra.restore` is written in the current working
directory on abort (verified: 89 KB file after SIGINT) and `hydra -R` reads it
from there. `-I` skips the 10-second wait and starts fresh, discarding it.

**Protocol reality.** `smb2` is not compiled in, so modern Windows targets that
refuse SMB1 will not work; `rdp` needs NLA-disabled or compatible settings;
`sshkey` tests keys, not passwords. Check `hydra -U <service>` for each module
before trusting an invocation.

**No JSON on stdout.** JSON is only available through `-o FILE -b json`; stdout
stays human-readable text.

## Safety and scope

Never run without explicit human confirmation per target:

- any list-based attack against a live service (state the account list, the
  password list, the thread count and the expected number of failed logons);
- `-x` brute-force generation, in any size;
- spraying against identity providers, VPNs or admin panels where a lockout
  locks out a human;
- attacking a service whose lockout policy is unknown;
- attacking any host that is not in the written scope for this engagement —
  "the same subnet" is not scope;
- re-running an attack that already tripped an alarm without telling Greg
  first.

If a run starts producing failed-logon alerts or account lockouts, stop it and
report — do not "finish the list first".
