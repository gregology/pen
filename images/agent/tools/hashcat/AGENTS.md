# hashcat

Offline password cracking. hashcat takes a hash (or a file of hashes) plus a
candidate generator — a wordlist, rules applied to a wordlist, a mask, or a
combination — and writes recovered plaintext to a potfile. It is the tool for
every hash that is not a `crypt(3)` password: NTLM, NetNTLMv1/v2, Kerberoast,
AS-REP, raw MD5/SHA, database and file-format hashes. The `john` in this image
is Debian's core build and cracks only `crypt(3)` formats, so hashcat is the
default for everything else.

Everything here is offline: hashcat never touches the network, and the only
traffic a cracking job produces is the LLM traffic of the session that runs it.

## Installation and location

| Item | Value |
|---|---|
| Binary | `/usr/bin/hashcat` |
| Version | 6.2.6 (Debian bookworm package) |
| OpenCL | PoCL 3.1 via `ocl-icd-libopencl1` + `pocl-opencl-icd` — **CPU only, no GPU** |
| Device | 1 × CPU `pthread-haswell-Intel(R) Core(TM) i9-9880H CPU @ 2.30GHz`, 16 processors, OpenCL C 1.2 (`hashcat -I`) |
| Rule files | `/usr/share/hashcat/rules/` (`best64.rule`, `rockyou-30000.rule`, `dive.rule`, `T0XlC.rule`, `combinator.rule`, `leetspeak.rule`, `hybrid/`, …) |
| Default potfile | `/root/.local/share/hashcat/hashcat.potfile` |
| Sessions/restore | `/root/.local/share/hashcat/sessions/<session>.restore` |
| Other state | `/root/.local/share/hashcat/hashcat.dictstat2`, `hashcat.log`, `<session>.log` |
| Wordlists | `/opt/wordlists/SecLists` (`/opt/wordlists/current` is the same tree) |

There is no `hashcat-utils`, no `hcxtools`, and no GPU. `rockyou.txt` is **not
extracted** in the wordlist tree — only `rockyou.txt.tar.gz` (53 MB) and
`rockyou-NN.txt` percentage samples:

```bash
mkdir -p /tmp/wl && tar -xzf \
  /opt/wordlists/SecLists/Passwords/Leaked-Databases/rockyou.txt.tar.gz -C /tmp/wl
wc -l /tmp/wl/rockyou.txt      # 14344391
```

## Rules that apply to this tool

1. **Authorization first.** Cracking is only legitimate on hashes obtained from
   systems Greg has explicitly confirmed for the current engagement. Holding a
   hash is not authorization to crack it and neither is finding it in a repo or
   a dump. New target, new hash set, new candidate source — ask before running.
2. **Cracking output is credential material and lives in the working
   directory.** Recovered plaintext goes to `$WORK` (for example
   `$WORK/loot/hashcat/`), never to a world-readable temp path, and never into
   a findings note pasted verbatim beyond the account it belongs to.
3. **All network traffic exits the WireGuard tunnel** in the shared netns.
   hashcat makes no network connections; keep it that way. Do not point
   `--brain-host` at a remote host, and do not upload hashes anywhere.
4. **This is a CPU-only box: no brute force without an explicit, written
   ceiling.** Mask and rule campaigns need the same authorization discipline as
   an online attack: state the keyspace, the speed from the table below and the
   wall-clock cost, and get confirmation before starting. Compute the keyspace
   from the mask's charset sizes (multiply them — `hashcat -a 3 --keyspace`
   under-reports it, see workflow 4) and divide by the benchmark speed before
   committing to a run.
5. **Always pass `</dev/null` when running from a script or a pipe.** hashcat
   reads stdin for its interactive `[s]tatus [p]ause …` controls and will eat
   the rest of a piped script (verified: a piped verification script was
   truncated after the first hashcat invocation).
6. **Save the evidence.** Keep the hash file, the wordlist path, the exact
   command line and the potfile under `$WORK` so a finding can be reproduced
   without the transcript.

## Command reference

Attack modes (`-a`) and hash modes (`-m`) are both numeric; get `-m` wrong and
hashcat either autodetects something else or reports "No hashes loaded".

| Flag | Meaning |
|---|---|
| `-m, --hash-type N` | Hash mode (0 MD5, 100 SHA1, 1000 NTLM, 1700 SHA2-512, 500 md5crypt, 1800 sha512crypt, 3200 bcrypt, 5600 NetNTLMv2, 13100 Kerberos TGS-REP etype 23, 18200 Kerberos AS-REP etype 23, 22000 WPA-PBKDF2-PMKID+EAPOL) |
| `-a, --attack-mode N` | 0 straight/wordlist, 1 combination, 3 brute-force/mask, 6 wordlist+mask, 7 mask+wordlist, 9 association |
| `-r, --rules-file FILE` | Rule file applied to each wordlist entry. **Use the absolute path** — see gotchas |
| `-j` / `-k` | Single rule applied to the left wordlist / right wordlist (combinator) |
| `-1..-4` | Custom charsets for masks (`-1 ?l?d`) |
| `-i, --increment` | Increment mask length (`--increment-min`, `--increment-max`) |
| `--stdout` | Print candidates instead of cracking (sanity-check a generator) |
| `--keyspace` | Print the mask keyspace and exit |
| `-o, --outfile FILE` | Write recovered hashes here as well as the potfile |
| `--outfile-format 1,2,3` | 1 `hash[:salt]`, 2 `plain`, 3 `hex_plain`, 4 `crack_pos`, 5/6 timestamps |
| `--potfile-path FILE` | Use a job-specific potfile instead of the default |
| `--show` / `--left` | Print cracked / still-uncracked hashes from the potfile |
| `--username` | Hashfile is `username:hash` (and pwdump `user:rid:lm:nt:::`); needed for secretsdump output |
| `--remove` | Delete cracked hashes from the input file |
| `--runtime N` | Abort after N seconds (checked at checkpoint intervals, so it overshoots) |
| `--session NAME` / `--restore` | Name a session / resume it from the restore file |
| `--status`, `--status-timer N`, `--status-json` | Live status line, refresh interval, JSON status |
| `--example-hashes` (`--hash-info`) | Show mode metadata and an example hash; `-m N` filters to one mode |
| `--machine-readable` | With `--hash-info`: full-length example hash as JSON |
| `--identify` | Guess modes from the hash structure (unreliable — see gotchas) |
| `-b, --benchmark` | Benchmark (`-m N` for one mode, `--benchmark-all` for all) |
| `-I, --backend-info` | List OpenCL platforms/devices; `-II` adds backend details |
| `-O` | Optimized kernels: faster, but caps password length (rejects long candidates) |
| `-w N` | Workload profile 1 low … 4 nightmare; on 16 CPU threads `-w 2` is the default |
| `--force` | Ignore warnings (needed only for unsupported/old drivers; the value is a warning you may be ignoring a real problem) |
| `--quiet` | Suppress the status screen; keeps result lines |

## Typical workflows

### 1. NTLM hashes from a Windows dump (secretsdump / nxc `--sam`)

```bash
mkdir -p "$WORK/loot/hashcat"
# secretsdump prints user:rid:lmhash:nthash::: — keep that file as-is
hashcat -a 0 -m 1000 "$WORK/loot/ntds.txt" --username \
  /opt/wordlists/SecLists/Passwords/Common-Credentials/10k-most-common.txt \
  --potfile-path "$WORK/loot/hashcat/ntlm.pot" -o "$WORK/loot/hashcat/ntlm.cracked" </dev/null
hashcat -a 0 -m 1000 "$WORK/loot/ntds.txt" --username \
  --potfile-path "$WORK/loot/hashcat/ntlm.pot" --show
```

### 2. Kerberoast and AS-REP from impacket

`GetUserSPNs.py -request` emits `$krb5tgs$23$…` (mode 13100) and
`GetNPUsers.py -request` emits `$krb5asrep$23$…` (mode 18200) already in
hashcat format. No conversion step is needed.

```bash
hashcat --identify "$WORK/loot/kerberoast.txt"        # confirms 13100
hashcat -a 0 -m 13100 "$WORK/loot/kerberoast.txt" \
  /opt/wordlists/SecLists/Passwords/Common-Credentials/10k-most-common.txt \
  -r /usr/share/hashcat/rules/best64.rule \
  --potfile-path "$WORK/loot/hashcat/krb.pot" --status --status-timer 10 </dev/null
```

### 3. Wordlist plus rules (the default attack)

```bash
hashcat -a 0 -m 0 hashes.txt words.txt \
  -r /usr/share/hashcat/rules/best64.rule \
  --potfile-path job.pot -o cracked.txt --quiet </dev/null
```

Layer rules by running again with a bigger rule file (`rockyou-30000.rule`,
`dive.rule`) rather than by chaining `-r` flags; each run reads the potfile and
skips what is already cracked.

### 4. Mask attack for a known policy

```bash
hashcat -a 3 -m 1000 hashes.txt '?u?l?l?l?l?d?d' --increment --increment-min 6 </dev/null
hashcat -a 3 -m 1000 --keyspace '?u?l?l?l?l?d?d'      # prints 67600 — not this mask's keyspace
```

That printed figure is not the size of this attack. The mask is 26^5 × 100 =
1 188 137 600 candidates, 17 576 times the 67 600 that `--keyspace` reports, so
size mask campaigns from the charset arithmetic rather than from `--keyspace`.
Against the speed table the full mask is seconds of NTLM work; an eight-character
full-charset mask (95^8) is ~123 days at this image's 623 MH/s.

### 5. Long job with a session and restore

```bash
hashcat -a 0 -m 1800 shadow.hashes rockyou.txt \
  --session shadowcrk --status --status-timer 30 --runtime 3600 </dev/null
# if it is still running after the runtime limit, pick it up again:
hashcat --restore --session shadowcrk </dev/null
```

The restore file is `/root/.local/share/hashcat/sessions/shadowcrk.restore`;
`--restore` continues from the stored restore point, and the stored session
keeps its original `--runtime`, so a restored job aborts again at the same
limit unless you start a new session.

## Output and parsing

Result line on stdout (also appended to the potfile, always `hash:plain`):

```
5f4dcc3b5aa765d61d8327deb882cf99:password
8846f7eaee8fb117ad06bdd830b7586c:password
```

`--show` with `--username` preserves the username column:

```
CORP\alice:8846f7eaee8fb117ad06bdd830b7586c:password
```

The potfile is the durable artifact — one `hash:plain` per line, no header, so
it parses with `cut -d: -f2-` or `jq -R 'split(":")'`. `--show` reads it back
per hash file, which is why the same potfile can serve successive rule runs.

JSON is available only for the status line (there is no JSON result file):

```bash
hashcat -a 3 -m 0 hashes.txt '?d?d?d?d?d?d' --status --status-json --status-timer 1 </dev/null
# {"session": "hashcat", ... "recovered_hashes": [0, 1], "devices": [ { "device_id": 1,
#  "device_name": "pthread-haswell-...", "speed": 23676881, "temp": 76 } ] ... }
```

Feed cracked plaintext straight back into the toolchain:

```bash
hashcat -m 1000 ntds.txt --username --show | cut -d: -f2- > "$WORK/loot/plain.txt"
```

## Chaining with the rest of the toolchain

- **nmap/httpx → netexec/impacket → hashcat.** Service discovery finds SMB or
  WinRM; impacket `secretsdump.py` or `nxc --sam/--lsa/--ntds` produces the
  hash file; hashcat cracks it. Keep the dump file untouched so `--username`
  parsing keeps working.
- **impacket Kerberos output → hashcat.** `GetUserSPNs.py -request` (13100) and
  `GetNPUsers.py -request -format hashcat` (18200) write hashcat-format
  hashes; crack them with `-m 13100` / `-m 18200` and re-test the recovered
  password with `nxc` (`--continue-on-success`) or `impacket getTGT.py`.
- **hashcat → netexec re-validation.** A cracked password is only a finding
  once it is shown to work somewhere authorized. Feed it back to
  `nxc <proto> <target> -u user -p pass`, watching for lockout counters.
- **john ↔ hashcat division of labour.** `$1$`/`$5$`/`$6$`/bcrypt/descrypt/LM
  go to `john --format=crypt`; everything else to hashcat. For
  `/etc/shadow`, `unshadow passwd shadow > combined` first (john ships
  `unshadow`).
- **Evidence into the findings note.** Copy the command line, the potfile and
  the count of recovered hashes; leave plaintext out of notes that could be
  shared more widely than the credential's own scope.

## Limits, failure modes and gotchas

**CPU-only reality.** Measured with `hashcat -b -m N` in this image:

| Mode | Hash | Speed |
|---|---|---|
| 0 | MD5 | 237.4 MH/s |
| 100 | SHA1 | 110.3 MH/s |
| 1000 | NTLM | 623.0 MH/s |
| 1700 | SHA2-512 | 5.72 MH/s |
| 5600 | NetNTLMv2 | 17.7 MH/s |
| 13100 | Kerberos TGS-REP etype 23 | 2.02 MH/s |
| 18200 | Kerberos AS-REP etype 23 | 2.42 MH/s |
| 500 | md5crypt `$1$` | 52.4 kH/s |
| 1800 | sha512crypt `$6$` | 1527 H/s |
| 3200 | bcrypt `$2*$` | 286 H/s |
| 22000 | WPA-PBKDF2-PMKID+EAPOL | 4753 H/s |
| 8900 | scrypt | 4 H/s |
| 13400 | KeePass | 571 H/s |

Practical consequences: a 10 000-word list is instant for NTLM and 6.5 s for
sha512crypt. rockyou (14.3 M words extracted) is ~0.02 s for NTLM, ~0.8 s for
NetNTLMv2, ~7 s for Kerberoast (TGS-REP), ~4.6 min for md5crypt, ~50 min for
WPA, ~2.6 h for sha512crypt and ~14 h for bcrypt; scrypt is ~41 days. With
`best64.rule` multiply by ~64. sha512crypt + rockyou + rules is a multi-day job
— pick the wordlist deliberately.

**Rule paths.** The help text's example `-r rules/best64.rule` **fails**:
`rules/best64.rule: No such file or directory`. hashcat does not chdir to
`/usr/share/hashcat`. Always use `/usr/share/hashcat/rules/<name>.rule`.

**`--identify` is not a decision.** A 32-hex MD5 hash matched 11 modes
(3500, 4400, 20900, 4300, 1000, 9900, 8600, 900, 0, 70, 2600) — it only works
for structurally unique formats (it does correctly return 13100 for a
`$krb5tgs$23$` blob). Set `-m` explicitly from the source of the hash.

**Silent stdin consumption.** hashcat's status keys are read from stdin. Under
a pipe (`… | hashcat …`, or a piped script) it consumes the remaining input;
always append `</dev/null`, or use `--stdin` deliberately.

**`--runtime` overshoots.** A `--runtime 5` job ran for 46 s because the limit
is only tested between checkpoint blocks. Do not build precise time budgets on
it.

**No OpenCL-extension failures observed.** All modes tested (0, 100, 1000,
1700, 500, 1800, 3200, 5600, 8900, 13100, 13400, 18200, 22000) initialized and
benchmarked on PoCL 3.1. Slow modes are slow, not broken: `-m 8900` at 4 H/s
and `-m 13400` at 571 H/s each need ~2 minutes to finish their benchmark. If a
mode ever does fail, the error appears during "Initializing device kernels" as
an OpenCL build error, not as a silent skip.

**Other small traps.**

- `No hashes loaded` almost always means a wrong `-m` or a hash file with
  extra whitespace/CRLF (`dos2unix` is installed).
- `--show` on a *different* hash file with the same potfile returns nothing
  useful: the potfile is keyed by hash, so keep hash files with their potfiles.
- `--remove` rewrites the input file in place; work on a copy.
- `-O` speeds up some modes but rejects candidates longer than the mode's
  optimized limit; drop it if you see rejected-candidate warnings.
- The status screen's `Hardware.Mon.#1` line reports `Temp`/`Util`; with a
  PoCL CPU device the utilisation tracks CPU load (96% on 16 threads at
  `-w 2`), and the temperature figure is not a GPU reading — do not use it to
  throttle CPU work.

## Safety and scope

Never run without explicit human confirmation per target and per hash set:

- cracking hashes that came from a system outside the authorized scope, or
  whose provenance is unclear;
- mask/brute-force campaigns that will occupy the CPU for hours without a
  stated end time (they starve the rest of the toolchain, including the tools
  doing the authorized scanning);
- printing recovered plaintext into shared notes or a transcript wider than
  the credential's own scope;
- uploading hashes or potfiles anywhere, including to an LLM provider or a
  "crack this" web service (the LLM proxy sees the session, so plaintext in a
  command line is already logged).
