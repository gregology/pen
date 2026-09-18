# john

John the Ripper, Debian's **core** build. In this image john is a `crypt(3)`
cracker: Unix `crypt` hashes (`descrypt`, `md5crypt` `$1$`, `sha256crypt` `$5$`,
`sha512crypt` `$6$`, `bcrypt`), LM, BSDI crypt, AFS and tripcode. It is *not*
jumbo — there are no `*2john` helpers, no NTLM/NetNTLM/Kerberoast formats and no
`--list=` introspection. Everything outside the `crypt(3)` family belongs to
hashcat.

john's value here is narrow and real: it is the fastest path for `/etc/shadow`
and other `crypt(3)` material, it runs 16 OpenMP threads by default, and its
`unshadow`/`unique` helpers are the standard way to assemble a shadow file for
cracking.

## Installation and location

| Item | Value |
|---|---|
| Binary | `/usr/sbin/john` (note: `sbin`, not `bin`) |
| Version | 1.9.0-2 (Debian bookworm package, core — not jumbo) |
| Data package | `john-data` 1.9.0-2 |
| Config | `/etc/john/john.conf` (incremental modes and rule sections live here) |
| Data | `/usr/share/john/` — `password.lst`, `*.chr` charsets, `cronjob` |
| Helpers | `/usr/sbin/unshadow`, `/usr/sbin/unique`, `/usr/sbin/unafs`, `/usr/sbin/mailer` |
| Pot file | `/root/.john/john.pot` |
| Log | `/root/.john/john.log` |
| Session files | Named `--session=NAME`: `./NAME.rec` + `./NAME.log` **in the current working directory**. Unnamed/default session: `/root/.john/john.rec` + `/root/.john/john.log` |

Supported `--format` names in this build: `descrypt`, `bsdicrypt`, `md5crypt`,
`bcrypt`, `LM`, `AFS`, `tripcode`, `dummy`, `crypt`. `crypt` is generic
`crypt(3)` and covers `$1$`, `$5$`, `$6$` and `$2*$` on glibc.

## Rules that apply to this tool

1. **Authorization first.** Crack only hashes from systems Greg has confirmed
   for the current engagement. A shadow file copied out of a container or a
   repo is not authorization to crack it; ask first, including for "just this
   one account".
2. **Cracked plaintext is credential material.** Keep it in `$WORK`
   (`$WORK/loot/john/`), and keep it out of findings notes beyond the account
   it belongs to.
3. **All network traffic exits the WireGuard tunnel** in the shared netns.
   john is offline; it opens no sockets. Nothing here needs network access, so
   do not add any.
4. **No incremental/brute-force run without an explicit, written ceiling.**
   State the keyspace, the measured speed (`john --test=3`) and the wall-clock
   cost, and get confirmation before starting. 16 threads at 100% also starve
   any authorized scan running in parallel — use `--fork=4` (or `--node=`) to
   cap john.
5. **Named sessions belong to the directory that created them.** `--session=NAME`
   writes `./NAME.rec` and `./NAME.log` in the *current* directory, and
   `--restore`/`--status` look there; a different cwd silently loses the
   session. The default (unnamed) session writes `/root/.john/john.rec`, not
   the cwd.
6. **Save the evidence.** The hash file, the exact command line and the pot
   file go under `$WORK`.

## Command reference

| Flag | Meaning |
|---|---|
| `--wordlist=FILE` | Wordlist mode; `--stdin` reads candidates from stdin instead |
| `--rules` | Enable the mangling rules from `[List.Rules:Wordlist]` in `john.conf` |
| `--single` | "Single crack" mode: derive candidates from the GECOS/login fields |
| `--incremental[=MODE]` | Brute-force/incremental mode (see modes below) |
| `--format=NAME` | Force the hash format; **use `crypt` for `$1$`/`$5$`/`$6$`** |
| `--show` | Print cracked passwords for the given files (pass `--format` too) |
| `--users=LOGIN[,..]` | Restrict to these accounts (`--users=-root` excludes) |
| `--salts=[-]N` | Only salts with at least N passwords (or fewer with `-`) |
| `--fork=N` | Fork N processes (parallel cracking without OpenMP oversubscription) |
| `--node=MIN[-MAX]/TOTAL` | Split work across a fixed number of nodes |
| `--session=NAME` | Name the session; writes `./NAME.rec` and `./NAME.log` |
| `--restore[=NAME]` | Resume a session (default `john`) |
| `--status[=NAME]` | Print the status of a running session |
| `--test[=SECONDS]` | Benchmark every compiled format |
| `--stdout[=LENGTH]` | Print candidates instead of cracking (rule/wordlist sanity check) |
| `--save-memory=LEVEL` | 1–3, for very large hash sets |
| `--make-charset=FILE` | Build a `.chr` file for incremental mode |

`--incremental` modes available in `/etc/john/john.conf`: `ASCII`, `LM_ASCII`,
`Alnum`, `Alpha`, `LowerNum`, `UpperNum`, `LowerSpace`, `Lower`, `Upper`,
`Digits`. `--incremental` with no mode uses the default (ASCII).

**Not available in this build** (all verified): `--list=build-info`,
`--list=formats`, `--pot=FILE`, `--format=nt`, `--format=raw-md5`, and `--help`
(which prints `Unknown option: "--help"`). Each returns
`Unknown option: "…"` or `Unknown ciphertext format name requested`.

## Typical workflows

### 1. Crack a shadow file (wordlist, then rules, then incremental)

```bash
mkdir -p "$WORK/loot/john" && cd "$WORK/loot/john"
unshadow /etc/passwd /etc/shadow > combined.txt     # helper writes to stdout
john --wordlist=/opt/wordlists/SecLists/Passwords/Common-Credentials/10k-most-common.txt \
     --format=crypt --session=shadow1 combined.txt </dev/null
john --show --format=crypt combined.txt
```

`john` auto-detects `crypt` for `$6$`/`$1$`/`$5$` hashes (verified: a `$6$…`
shadow file cracks and `--show`s correctly with no `--format` at all). Writing
`--format=crypt` explicitly is still worth doing: it removes the guess and
keeps the command self-documenting.

### 2. Rules pass on the same file

```bash
john --wordlist=words.txt --format=crypt --rules --session=shadow2 combined.txt </dev/null
john --show --format=crypt combined.txt     # pot already holds run 1's cracks
```

### 3. Brute force a short password with incremental mode

```bash
timeout 300 john --incremental=Digits --format=crypt --session=digits combined.txt </dev/null
john --status=digits; john --show --format=crypt combined.txt
```

Incremental mode is single-salt-optimised; against `$6$` it runs at a few
hundred candidates/s on this host, so it is only viable for a short or
structured password.

### 4. Resume after an interruption

```bash
cd "$WORK/loot/john"          # the cwd that holds digits.rec
john --restore=digits </dev/null
```

### 5. Generate and sanity-check candidates without cracking

```bash
john --stdout --wordlist=words.txt | head            # what will be tried
john --wordlist=words.txt --format=crypt --rules --stdout | wc -l   # keyspace size
```

## Output and parsing

Progress and hits on stderr/stdout:

```
Loaded 1 password hash (crypt, generic crypt(3) [?/64])
Will run 16 OpenMP threads
Press 'q' or Ctrl-C to abort, almost any other key for status
password         (user)
1g 0:00:00:00 100% 8.333g/s 25.00p/s 25.00c/s 25.00C/s wrongpass..password
Use the "--show" option to display all of the cracked passwords reliably
Session completed
```

`--show` prints shadow-style lines — `user:password:18000:0:99999:7:::` — plus a
trailing blank line and `N password hashes cracked, M left`. A bare hash file
(no `user:` prefix) shows the same shape with `?` in the login field.

The pot file is the durable artifact — `hash:plain`, one per line:

```
$6$saltsalt$qFmFH.bQmmtXzyBY0s9v7Oicd2z4XSIecDzlB5KiA2/jctKu9YterLp8wwnSq.qc.eoxqOmSuNp2xS0ktL3nh/:password
```

Parse it with `cut -d: -f2-` — but beware that `crypt(3)` hashes contain `$`
and can contain `:`, so prefer `john --show` output for reporting. There is no
JSON output in this build.

`--test=3` output is the format inventory plus per-format speed. Speeds are
host- and load-dependent, not properties of the build — the same formats
benchmarked roughly 2× slower in this container — so read the sample for shape,
not for numbers:

```
Benchmarking: descrypt, traditional crypt(3) [DES 128/128 SSE2]... DONE
Many salts:	2473K c/s real, 263531 c/s virtual
Benchmarking: md5crypt [MD5 32/64 X2]... DONE
Raw:	21965 c/s real, 3126 c/s virtual
Benchmarking: bcrypt ("$2a$05", 32 iterations) [Blowfish 32/64 X3]... DONE
Raw:	1435 c/s real, 178 c/s virtual
Benchmarking: LM [DES 128/128 SSE2]... DONE
Raw:	3754K c/s real, 398374 c/s virtual
Benchmarking: crypt, generic crypt(3) [?/64]... DONE
Many salts:	6080 c/s real, 669 c/s virtual
```

## Chaining with the rest of the toolchain

- **nmap/netexec → shell → john.** A foothold gives `/etc/passwd` +
  `/etc/shadow`; `unshadow` merges them, john cracks them. `unique` strips
  duplicate words from a custom wordlist before a rules pass.
- **john → hashcat.** If john reports `Unknown ciphertext format name
  requested`, the hash is not `crypt(3)` — hand it to hashcat with the right
  `-m` (NTLM 1000, NetNTLMv2 5600, TGS-REP 13100, AS-REP 18200).
- **hashcat → john.** The reverse handoff is only for `$1$`/`$5$`/`$6$`/bcrypt:
  john's `crypt` format is a single generic engine and sometimes faster on
  many-salt sets (`--salts=2` filters those).
- **Cracked passwords → netexec/impacket re-validation.** A password recovered
  from `/etc/shadow` is a finding once it is shown to work against the
  authorized service; feed it to `nxc ssh <host> -u user -p pass` or
  `hydra -l user -p pass <host> ssh`, remembering lockout counters.
- **Evidence into the findings note.** Keep `combined.txt`, the command line,
  `john --show` output and the pot file under `$WORK`.

## Limits, failure modes and gotchas

**This is core john, not jumbo.** The single most common mistake is reaching
for a jumbo flag or format. `--list=build-info`, `--list=formats` and
`--pot=FILE` do not exist here, and `--format=nt`, `--format=raw-md5`,
`--format=netntlmv2` are rejected. If you need those, this is the wrong tool —
use hashcat.

**No `*2john` helpers.** `dpkg -L john` shows only `unafs`, `unique`,
`unshadow` and `mailer`; there are no `ssh2john`, `zip2john`, `keepass2john`
scripts anywhere in the image. Anything that would need one (SSH private keys,
ZIP/7z/KeePass/Office files) must go to hashcat's `*2hash`-equivalent modes, or
be extracted with the format's own tooling (for example
`ssh-keygen -p -f key -N ''` for a known passphrase prompt, or a Python helper
in the venv).

**Named sessions live in the cwd; the default session does not.** `--session=NAME`
writes `./NAME.rec` + `./NAME.log` in the current directory, and
`--restore`/`--status` only find it again from there — a different cwd loses the
session. An unnamed run writes `/root/.john/john.rec` and `/root/.john/john.log`
and leaves nothing in the cwd. `timeout`/SIGINT leaves a usable `.rec` behind
and prints `The session file ./NAME.rec was written`.

**`--format` is optional but keep it consistent.** john auto-detects `crypt`
from the hash prefix, and `--show` works with or without the flag on a
`$6$`/`$1$` file. Passing `--format=crypt` on the crack and the `--show` keeps
long command lines reproducible; passing a *wrong* format (`--format=LM` on a
shadow file) is what returns "0 cracked".

**OpenMP oversubscription.** "Will run 16 OpenMP threads" is the default on
this host. Two concurrent john jobs will fight for the same 16 CPUs; use
`--fork=N` with `--node=` for deliberate splits.

**Speed expectations.** The `--test=3` figures above are host- and
load-dependent and this container has measured them about 2× lower, so treat
them as order of magnitude and re-measure on the host at the time: `crypt`
(generic `crypt(3)`) thousands of c/s many-salts and hundreds single-salt;
md5crypt tens of thousands; bcrypt (`$2a$05`) ~1 k/s; LM in the millions.
rockyou (14.3 M words) against `$6$` at a few hundred c/s is hours *per pass*,
and john's rule set will multiply that — size the attack before starting it.

**Interactive expectations.** john reads single keys from stdin
(`q`/Ctrl-C to abort). Under a pipe or script, always append `</dev/null`;
otherwise john consumes the rest of the script the way hashcat does.

**Bare hash files work.** A file with one `$6$…` line and no username is
accepted and reports the plaintext against `?` in `--show`.

## Safety and scope

Never run without explicit human confirmation per target and per hash set:

- cracking hashes from any system outside the confirmed scope, including
  hashes found in repos, images or backups;
- long incremental/brute-force runs that will occupy all 16 CPUs for hours
  while other authorized work is happening;
- copying `/etc/shadow` (or any credential file) out of a host into `$WORK`
  without saying so first — that is a credential-handling decision, not a
  cracking one;
- printing cracked plaintext into shared notes or into a command line the LLM
  proxy logs.
