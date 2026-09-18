# pypykatz — offline Windows credential extraction (pure-Python Mimikatz)

pypykatz parses Windows credential stores without a Windows host: LSASS process
minidumps, registry hives (SAM/SECURITY/SYSTEM/SOFTWARE), DPAPI masterkeys and
blobs, NTDS.dit, RDP credential blobs, Kerberos ccache. It is the analysis half
of a credential attack — the dump comes from somewhere else (netexec, impacket,
metasploit, a remote `smb lsassdump`, or a filesystem image). Its natural
handoff is john/hashcat for the hashes it cannot reverse, and netexec/impacket
when the extracted material is a hash to use rather than crack.

## Install and location

| | |
|---|---|
| Version | 0.6.13 (PyPI release 2026-01-02, `requires_python >=3.6`) |
| Entry point | `/usr/local/bin/pypykatz` → `/opt/venvs/pypykatz/bin/pypykatz` |
| Venv | `/opt/venvs/pypykatz` |
| Dependencies | `minidump`, `minikerberos`, `aiowinreg`, `msldap`, `winacl`, `aiosmb`, `aesedb`, `unicrypto`, `tqdm` |

## Commands

Top-level in 0.6.13: `live`, `lsa`, `registry`, `dpapi`, `crypto`, `kerberos`,
`remote`, `smb`, `ldap`, `rdp`, `parser`, plus `version`, `banner`, `logo`.

**There is no `ai` subcommand and no command spelled `lsass`.** The LSASS
command is `lsa`.

### `pypykatz lsa <cmd> <memoryfile> [flags]`

`cmd` is `minidump`, `rekall`, `info` or `zipdump`.

| Flag | What it does |
|---|---|
| `memoryfile` | Positional path to the dump (or, with `-d`, a directory). |
| `--json` | Print credentials as JSON to stdout. |
| `-o, --outfile FILE` | Write results to a file. With `--json` the file is JSON; otherwise text. **Overwrites.** |
| `-g, --grep` | Print colon-separated rows instead of the readable report. |
| `-p, --packages A [B …]` | Limit parsing: `all` (default), `msv`, `wdigest`, `tspkg`, `ssp`, `livessp`, `dpapi`, `cloudap`, `kerberos`. |
| `-k, --kerberos-dir DIR` | Write extracted Kerberos tickets out as files. |
| `-d, --directory` | Treat the positional path as a directory of dumps (with `-r` to recurse). |
| `-e, --halt-on-error` | Stop at the first dump that fails to parse instead of continuing. |
| `-t, --timestamp_override 0\|1` | Force the MSV timestamp mode (`1` = anti-mimikatz builds) when structure selection fails. |

### Other commands

```
pypykatz registry <SYSTEM> [--sam FILE] [--security FILE] [--software FILE] [-o FILE] [--json]
pypykatz live lsa [--json] [-o FILE] [-g] [--method procopen|handledup] [-p …]
pypykatz smb lsassdump|lsassfile|regdump|regfile|secretsdump|dcsync|shareenum|printnightmare|client
pypykatz dpapi keys|blob|blobfile|cred|vcred|vpol|wifi|chrome|securestring|tcap
pypykatz crypto nt|lm|dcc|gppass|vnc|ofscan
pypykatz parser ntds
pypykatz kerberos …
pypykatz rdp logonpasswords|mstsc
```

`registry` requires `SYSTEM` as a positional argument. `live lsa` reads LSASS
from the running machine and is **Windows only** — on Linux it cannot work.

## Examples

### Parse an LSASS minidump and keep both forms

```bash
pypykatz lsa minidump $WORK/lsass.dmp -o $WORK/lsa.json --json
pypykatz lsa minidump $WORK/lsass.dmp -o $WORK/lsa.txt
jq -r '.. | objects | select(has("NThash")) | [.username, .domainname, .NThash] | @tsv' $WORK/lsa.json | sort -u
```

The text report is the mimikatz-style `msv`/`wdigest`/`kerberos` block per logon
session; the JSON is the same data for parsing. `-o` overwrites — write each run
to its own file.

### Pre-check that the file is a dump at all

```bash
pypykatz lsa info $WORK/lsass.dmp
```

Cheap, and the fastest way to tell "wrong process" from "wrong parser".

### Greppable rows for handlers and notes

```bash
pypykatz lsa minidump $WORK/lsass.dmp -g | tee $WORK/lsa.grep
# packagename:domain:user:NT:LM:SHA1:masterkey:sha1_masterkey:key_guid:plaintext
```

The header is printed by the tool itself. Empty fields are legitimate — e.g.
`wdigest` rows carry plaintext where `msv` rows carry hashes.

### Registry hives from a host or an image

```bash
pypykatz registry $WORK/SYSTEM --sam $WORK/SAM --security $WORK/SECURITY \
  --json -o $WORK/registry.json
jq -r '.. | objects | select(has("NThash")) | [.username, .NThash] | @tsv' $WORK/registry.json
```

Without SECURITY you get local account hashes but no LSA secrets and no domain
cached credentials. `--software` is only needed for some DPAPI/key material.

### Crypto helpers when all you have is a value

```bash
pypykatz crypto nt 'Sup3rS3cret!'          # NT hash of a password
pypykatz crypto dcc 'Sup3rS3cret!'         # DCC v1 (cache) hash
pypykatz crypto gppass '<cpassword from Groups.xml>'
```

### A directory of dumps

```bash
pypykatz lsa minidump $WORK/dumps -d -r -o $WORK/all.json --json
```

`-d` treats the positional argument as a directory, `-r` walks subdirectories.

## Output formats

- `--json` → JSON on stdout (`json.dump(..., indent=4, sort_keys=True)`).
- `-o FILE --json` → the same JSON to a file.
- `-o FILE` (no `--json`) → readable text: `FILE: ======== <name> ========`, one
  block per logon session, then `== Orphaned credentials ==`, then a
  `== Failed to parse these files:` list if any dump failed.
- `-g/--grep` → header row plus colon-separated rows, one per credential; `-d`
  adds a leading `filename` column.

There is no XML/CSV. Everything downstream (john/hashcat input, netexec `-H`,
impacket `-hashes`) is generated from the JSON or the grep rows with `jq`/`awk`.

## Failure modes

- **`pypykatz lsass …` does not exist.** The LSASS commands are
  `pypykatz lsa minidump <file>` and, on Windows, `pypykatz live lsa`. A wrong
  subcommand prints argparse usage and exits non-zero.
- **`live` is Windows-only.** On Linux the live paths need Windows APIs; use
  `lsa minidump` against a dump instead.
- **A dump of the wrong process parses to an empty result, quietly.** `lsa info`
  is the cheap pre-check.
- **The `smb` command group can vanish.** `__main__.py` imports the SMB helper
  inside a `try/except` and prints the exception; if `aiosmb` or its
  dependencies are broken in the venv, `pypykatz smb …` is simply absent and
  startup shows an error string. Check with `pypykatz smb client help` before
  relying on it.
- **`-o` overwrites the target file** with no warning; it does not append.
- **Parsing failures are logged, not fatal.** Structures that do not match the
  expected build are skipped; run with `-v` (repeatable) to see why a session is
  missing, and `-t 1` for anti-mimikatz builds.
- **DCC2/cache entries are not reversible by pypykatz**, and NT hashes are not
  passwords. Hand them to hashcat/john (mode 2100 for DCC2, 1000 for NTLM).
- **A "successful" parse of a dumped file is not proof of anything about the
  live host** — record the dump's provenance (host, time, how it was taken) with
  the results.

## Notes

- Dumps and parsed output are **live credentials**. They stay in `$WORK`, never
  in the repo, never in git — the same custody rule as `vpn-configs/`.
- Extraction order worth following: `lsa info` → `lsa minidump --json` → `-g`
  rows → `registry` with SAM+SECURITY → `dpapi`/`parser ntds` only if the first
  passes leave gaps.
- Output volume is large and `indent=4` makes it larger; for pipelines prefer
  `-g` + `awk` over the pretty JSON.
- To use pypykatz as a library: `/opt/venvs/pypykatz/bin/python3`.

## Safety

Requires explicit human confirmation before running:

- **`pypykatz smb lsassdump`/`secretsdump`/`dcsync` are remote attacks**, not
  analysis: they authenticate to a target, dump memory or replicate secrets, and
  are loud in EDR and Windows event logs. Prefer analysing an already-collected
  dump.
- Extracting credentials from any host not confirmed for the engagement.
- Copying credential material out of `$WORK`, or into a findings note.
