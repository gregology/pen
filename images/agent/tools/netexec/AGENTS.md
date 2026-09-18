# netexec

Swiss-army credential validation and host enumeration across SMB, LDAP, WinRM,
SSH, MSSQL, RDP, VNC, NFS, WMI and FTP. netexec (`nxc`) takes host lists, user
and password lists and answers two questions fast: *does this credential work
anywhere*, and *what does this host expose*. It is the maintained successor to
CrackMapExec. Results accumulate in a per-protocol SQLite workspace, which makes
it the natural place to keep an engagement's credential and host inventory.

> **Build requirement: `dploot` must be pinned below 4.** netexec 1.5.1
> declares `dploot>=3.1.0` with no upper bound, and dploot 4 moved
> `dploot.lib.smb` to `dploot.lib.network.smb`. An image built without the pin
> (dploot 4.1.1) produces a netexec whose SMB protocol dies at import with
> `ModuleNotFoundError: No module named 'dploot.lib.smb'`, and eight modules
> (`wifi`, `mremoteng`, `dpapi_hash`, `mobaxterm`, `vnc`, `rdcman`, `firefox`,
> `wam`) fail to load in *every* protocol for the same reason. The current
> image ships `dploot` 3.2.2 and `nxc smb` works — verified end to end against
> a loopback SMB server. `nxc smb --version` prints a version on the broken
> image too, so if SMB misbehaves, run
> `/opt/venvs/netexec/bin/python -c "import nxc.protocols.smb.dpapi"` first —
> that is what fails when the pin is missing. The interpreter matters: bare
> `python3` is `/opt/py/bin/python3`, which has no `nxc` and reports
> `ModuleNotFoundError` even on a good image.

## Installation and location

| Item | Value |
|---|---|
| Binaries | `/opt/venvs/netexec/bin/nxc` and `/opt/venvs/netexec/bin/netexec` (identical wrappers) |
| Version | `1.5.1` (installed from git tag v1.5.1, package version `1.5.1+0.c7dc286b`) |
| Version string | `1.5.1 - Yippee-Ki-Yay - c7dc286b - 0` |
| Protocol DB navigator | `/opt/venvs/netexec/bin/nxcdb` |
| Config | `/root/.nxc/nxc.conf` |
| Workspaces | `/root/.nxc/workspaces/<workspace>/<protocol>.db` (default workspace: `default`) |
| Other state | `/root/.nxc/logs/`, `modules/`, `obfuscated_scripts/`, `screenshots/`, `tmp/` |
| Modules | `/opt/venvs/netexec/lib/python3.11/site-packages/nxc/modules/` |
| Protocols | `mssql ftp rdp ldap ssh vnc smb winrm nfs wmi` |

`sqlite3` CLI is **not** installed — query the workspace DBs with `python3` +
`sqlite3` (the module is available).

## Rules that apply to this tool

1. **Explicit human confirmation per target.** netexec logs into real services.
   Confirm host list, protocol, credential source and the account lockout
   policy before the first attempt — a "does this password work elsewhere"
   sweep is a spray and can lock out real people.
2. **Sprays are lockouts.** `-u users.txt -p passwords.txt` is a full
   brute-force matrix by default. Use `--no-bruteforce` for pair-wise attempts,
   `-p` single + `-u` list for a true spray, and always cap the damage:
   `-t 2 --jitter 5 --gfail-limit 3 --ufail-limit 2 --fail-limit 10`.
3. **All traffic exits the WireGuard tunnel** in the shared netns. `nxc` has no
   proxy option that changes containment.
4. **`-x`/`-X` and `--sam`/`--lsa`/`--ntds` change the target.** Command
   execution leaves processes, files and event-log entries; credential dumping
   moves secrets. Both are separate authorizations from scanning.
5. **Everything is recorded twice.** Results go to stdout, to `--log FILE` and
   into the workspace SQLite DB — including recovered credentials in plaintext.
   Treat `/root/.nxc/` as credential material and copy it to `$WORK` rather
   than leaving secrets only in a container filesystem.
6. **Cap the default thread count.** `nxc` defaults to 256 threads
   (`-t 256`); against anything small that is a load test (`-t 5` is a sane
   start for a handful of hosts).

## Command reference

Global options (before the protocol subcommand, `nxc --help`):

| Flag | Meaning |
|---|---|
| `-t N, --threads N` | Concurrent threads (default 256) |
| `--timeout N` | Per-thread timeout in seconds |
| `--jitter N` | Random delay between authentication attempts |
| `--no-progress` | Disable the progress bar |
| `--log FILE` | Export results to FILE (text, plus a header line with the command) |
| `--verbose` / `--debug` | More output (mutually exclusive) |
| `-6`, `--dns-server`, `--dns-tcp`, `--dns-timeout` | IPv6 forcing and DNS control |
| `--version` | Version string — does **not** load the protocol module |

There is **no `--json` flag in 1.5.1** (verified: no JSON option in `nxc --help`
or `nxc smb --help`). Machine-readable output means the workspace database or
`--log`.

SMB options (`nxc smb --help`; verified working in the current image):

| Group | Flags |
|---|---|
| Credentials | `-u/--username`, `-p/--password`, `-H/--hash`, `-id` (credential ID from the workspace DB — no long form), `-d/--domain`, `--local-auth` (local accounts on each target), `--no-bruteforce`, `--continue-on-success`, `--ignore-pw-decoding` |
| Limits | `--gfail-limit`, `--ufail-limit`, `--fail-limit` |
| Kerberos | `-k/--kerberos`, `--use-kcache`, `--aesKey`, `--kdcHost`, `--generate-tgt`, `--generate-krb5-file`, `--generate-hosts-file` |
| Certificates | `--pfx-cert`, `--pfx-base64`, `--pfx-pass`, `--pem-cert`, `--pem-key` |
| Modules | `-M/--module`, `-o/--options`, `-L/--list-modules`, `--options` |
| Enumeration | `--shares [filter]`, `--dir [path]`, `--disks`, `--interfaces`, `--users`, `--groups`, `--local-groups`, `--computers`, `--pass-pol`, `--rid-brute [max]`, `--loggedon-users`, `--smb-sessions`, `--reg-sessions`, `--qwinsta`, `--tasklist`, `--spider SHARE`, `--laps` |
| Credential gathering | `--sam [regdump\|secdump]`, `--lsa [regdump\|secdump]`, `--ntds [vss\|drsuapi]`, `--kerberos-keys`, `--history`, `--enabled`, `--user`, `--dpapi`, `--sccm` |
| Execution | `-x CMD`, `-X PS_CMD`, `--exec-method {atexec,wmiexec,smbexec,mmcexec}`, `--no-output`, `--obfs`, `--amsi-bypass FILE`, `--codec`, `--get-output-tries`, `--dcom-timeout` |
| Files | `--put-file SRC DST`, `--get-file SRC DST` |
| OPSEC/other | `--port`, `--smb-timeout`, `--no-smbv1`, `--no-admin-check`, `--no-write-check`, `--gen-relay-list FILE`, `--append-host`, `--silent` |

SSH options (verified working): `-u/-p/-H`, `--port`, `--key-file`,
`--no-bruteforce`, `--continue-on-success`, `--gfail-limit`, `--ufail-limit`,
`--fail-limit`, `-k`, `--use-kcache`, `--options`. There is **no `--local-auth`**
outside SMB.

Targets are positional and accept IPs, ranges, CIDR, hostnames, FQDNs, files,
Nmap XML and Nessus files.

## Typical workflows

### 1. Credential validation sweep (the core use)

```bash
mkdir -p "$WORK/loot/nxc"
nxc smb "$WORK/targets.txt" -u alice -p 'Passw0rd!' --local-auth \
  -t 5 --jitter 2 --log "$WORK/loot/nxc/smb-validate.log"
```

Verified output shape for one host and one credential (against a loopback
`smbserver.py`):

```
SMB                      127.0.0.1       445    SePhCBlh         [*] ccUgQror (name:SePhCBlh) (domain:SePhCBlh) (signing:False) (SMBv1:True)
SMB                      127.0.0.1       445    SePhCBlh         [+] SePhCBlh\smbuser:smbpass
SMB                      127.0.0.1       445    SePhCBlh         [-] SePhCBlh\smbuser:nope STATUS_LOGON_FAILURE
```

Note `(signing:False)` on the host line: that is the field `--gen-relay-list`
selects on.

### 2. Password spray that respects lockout counters

```bash
nxc smb "$WORK/targets.txt" -u "$WORK/users.txt" -p 'Spring2026!' \
  --no-bruteforce --continue-on-success -t 2 --jitter 10 \
  --ufail-limit 1 --gfail-limit 10 --fail-limit 5 \
  --log "$WORK/loot/nxc/spray.log"
```

One password, many users, `-t 2` with jitter, stopped by the failure limits.
Never `-u users.txt -p passwords.txt` without `--no-bruteforce` unless a full
matrix is explicitly authorized.

### 3. Host enumeration with one valid credential

```bash
nxc smb 10.0.0.20 -u alice -p 'Passw0rd!' -d CORP \
  --shares --users --groups --pass-pol --loggedon-users --interfaces --disks \
  --log "$WORK/loot/nxc/enum-10.0.0.20.log"
nxc ldap 10.0.0.10 -u alice -p 'Passw0rd!' -d CORP --users --groups --pass-pol
nxc winrm 10.0.0.20 -u alice -p 'Passw0rd!' -d CORP
```

### 4. Post-exploitation: credential dumping and command execution

Both require their own authorization; both leave traces.

```bash
nxc smb 10.0.0.20 -u alice -p 'Passw0rd!' --local-auth --sam --lsa \
  --log "$WORK/loot/nxc/dump-10.0.0.20.log"
nxc smb 10.0.0.10 -u Administrator -p 'Passw0rd!' -d CORP --ntds drsuapi

nxc smb 10.0.0.20 -u alice -p 'Passw0rd!' --local-auth -x 'whoami /all'
nxc smb 10.0.0.20 -u alice -p 'Passw0rd!' --local-auth -X 'Get-Process | Select-Object -First 5'
nxc winrm 10.0.0.20 -u alice -p 'Passw0rd!' -d CORP -x hostname
```

By default dumps are also written under `/root/.nxc/logs/{sam,lsa,ntds}/`;
copy them to `$WORK` and feed them to hashcat. `-x` is cmd, `-X` is PowerShell,
`--exec-method` picks the transport.

### 5. Modules

```bash
nxc smb -L                       # list modules
nxc smb 10.0.0.20 -u alice -p 'Passw0rd!' -M lsassy
nxc smb 10.0.0.20 -u alice -p 'Passw0rd!' -M spider_plus -o DOWNLOAD_FLAG=True
nxc smb 10.0.0.20 -u alice -p 'Passw0rd!' -M <module> --options
```

Modules are loaded for every protocol invocation. On a correctly built image
(`dploot<4`) none fail; on an unpinned build you get
`[-] Failed loading module at …: No module named 'dploot.lib.smb'` for eight
modules on *every* protocol, including `nxc ssh -L`.

## Output and parsing

Result lines (`SSH` example, verified against a local server):

```
SSH                      127.0.0.1       2223   127.0.0.1        [*] SSH-2.0-paramiko_5.0.0
SSH                      127.0.0.1       2223   127.0.0.1        [-] testuser:wrongpass
```

Columns are `protocol  host  port  hostname  [status]  message`, where `[*]`
is information, `[-]` a failed authentication or lookup, and `[+]` a success
(the suffix varies by protocol and privilege). `nxc` prints these without a
TTY; a failure in the protocol module surfaces as a Rich traceback panel in the
middle of the results.

`--log FILE` produces a header line plus Python-logging lines:

```
[2026-09-17 20:53:26]> /opt/venvs/netexec/bin/nxc ssh 127.0.0.1 --port 2223 -u testuser -p testpass --no-progress --log /tmp/nxw/nxc2.log

2026-09-17 20:53:27 | ssh.py:60 - INFO - SSH                      127.0.0.1       2223   127.0.0.1        [*] SSH-2.0-paramiko_5.0.0
```

### The workspace database — the real output format

Everything is also stored in SQLite. Verified layout and content:

```
/root/.nxc/
├── nxc.conf
├── logs/{sam,lsa,ntds,dpapi}/
├── modules/  obfuscated_scripts/  screenshots/  tmp/
└── workspaces/default/
    ├── smb.db    hosts, users, groups, shares, admin_relations, group_relations,
    │             loggedin_relations, conf_checks, conf_checks_results,
    │             dpapi_secrets, dpapi_backupkey
    ├── ssh.db    hosts, credentials, admin_relations, loggedin_relations, keys
    ├── ldap.db   hosts, users
    ├── winrm.db  hosts, users, admin_relations, loggedin_relations
    ├── mssql.db  hosts, users, admin_relations, loggedin_relations
    ├── ftp.db    hosts, credentials, loggedin_relations, directory_listings
    ├── nfs.db    hosts, credentials, loggedin_relations, shares
    ├── rdp.db    hosts
    ├── vnc.db    hosts, credentials
    └── wmi.db    hosts, credentials
```

Real rows after an SSH login attempt (no `sqlite3` CLI — use `python3`):

```bash
python3 - <<'PY'
import sqlite3
con = sqlite3.connect('/root/.nxc/workspaces/default/ssh.db')
print(con.execute('SELECT * FROM hosts').fetchall())
print(con.execute('SELECT * FROM credentials').fetchall())
PY
# [(1, '127.0.0.1', 2223, 'SSH-2.0-paramiko_5.0.0', '')]
# [(1, 'testuser', 'testpass', 'plaintext')]
```

Note the credential is stored when authentication *succeeds*, even if the
post-auth command fails — and in plaintext.

Workspaces are switched with `nxcdb` (there is no `--workspace` flag on `nxc`):

```bash
nxcdb -gw                 # get current workspace
nxcdb -cw eng-memair      # create
nxcdb -sw eng-memair      # set
```

## Chaining with the rest of the toolchain

- **nmap/naabu → nxc.** Port discovery gives the protocol surface (445 SMB,
  5985 WinRM, 389/636 LDAP, 1433 MSSQL, 22 SSH, 3389 RDP); write the hosts to a
  file and hand it to `nxc` as a positional target list.
- **impacket → nxc.** `secretsdump.py`/`GetNPUsers.py` produce hashes and
  usernames; `nxc smb -H <hash>` validates them host-to-host with
  `--continue-on-success`. Use nxc for breadth and impacket for depth — the two
  share the same protocol library, so a credential that works in one works in
  the other.
- **nxc → hashcat/john.** `--sam`/`--lsa`/`--ntds` output (and the files under
  `/root/.nxc/logs/`) go to `hashcat -m 1000 --username`; `$1$`/`$5$`/`$6$`
  go to `john --format=crypt`.
- **hashcat → nxc.** Cracked passwords come back through
  `nxc <proto> <target> -u user -p pass --continue-on-success`, which is the
  re-validation step that turns a cracked hash into a finding.
- **nxc → hydra.** Enumerated usernames (`--users`, `--rid-brute`) feed hydra's
  `-L`; keep hydra's rate far below nxc's and never point it at accounts you
  have not confirmed.
- **nxc workspace → findings note.** `--log` files plus a SQL dump of the
  workspace tables give a reproducible inventory.
- **`nxc smb --gen-relay-list` → impacket `ntlmrelayx.py`.** The signing-check
  list is the input to a relay run (explicit authorization required).

## Limits, failure modes and gotchas

**If SMB dies at import, the image was built without the `dploot<4` pin.**
Symptom and cause, verified on an unpinned build:

```
File "/opt/venvs/netexec/lib/python3.11/site-packages/nxc/protocols/smb.py", line 45, in <module>
    from nxc.protocols.smb.dpapi import collect_masterkeys_from_target, …
File "/opt/venvs/netexec/lib/python3.11/site-packages/nxc/protocols/smb/dpapi.py", line 2, in <module>
    from dploot.lib.smb import DPLootSMBConnection
ModuleNotFoundError: No module named 'dploot.lib.smb'
```

netexec 1.5.1 declares `dploot (>=3.1.0)` with no upper bound, so an unpinned
pip resolution installs dploot 4.x, whose module lives at
`dploot/lib/network/smb.py`; the same import also breaks the `wifi`,
`mremoteng`, `dpapi_hash`, `mobaxterm`, `vnc`, `rdcman`, `firefox` and `wam`
modules for all protocols. The current image ships dploot 3.2.2, the import
succeeds and `nxc smb` runs; check with
`/opt/venvs/netexec/bin/python -c "import nxc.protocols.smb.dpapi"` (the venv
interpreter) rather than `nxc smb --version`, which never loads the protocol
module.

**No JSON.** 1.5.1 has `--log` (text) and the workspace DB. If a consumer needs
JSON, query the SQLite tables and emit it yourself with `python3 -c`.

**Spray vs brute force.** Without `--no-bruteforce`, `-u file -p file` pairs
every user with every password. `--continue-on-success` keeps going after a
hit (needed for "where else does this work"), and `--gfail-limit`,
`--ufail-limit`, `--fail-limit` are the only circuit breakers.

**Post-auth verification can fail on hardened targets.** `nxc ssh` runs `id`
over an exec channel after a successful password login; servers that refuse
exec drop the channel and `nxc` prints a `Channel closed` traceback instead of
`[+]`. The credential is still recorded in `ssh.db` — check the DB, not just
the console.

**Default thread count is 256.** `-t 5` for a handful of hosts, `-t 1` with
`--jitter` for anything with a lockout policy.

**`--local-auth` is SMB-only.** Passing it to `nxc ssh`/`nxc ldap` is an
unrecognized-argument error; use `-d DOMAIN` or a `HOST\user` credential
instead.

**Credential material in the container.** `/root/.nxc/workspaces/*.db` holds
plaintext passwords and hashes. Copy to `$WORK` and treat the DB as loot, not
as scratch state.

**Module failures are printed, not fatal.** A module that fails to load leaves
`[-] Failed loading module at …` lines in the output; the rest of the run
continues. Do not read a "clean" run as "no modules failed".

## Safety and scope

Never run without explicit human confirmation per target:

- any spray or list-based authentication (`-u`/`-p` files) — state the user
  list, the password list, thread count, jitter and failure limits first;
- `--sam`, `--lsa`, `--ntds`, `--dpapi`, `--sccm`, `--laps` (credential
  dumping; `--ntds` is a domain-wide compromise);
- `-x`, `-X`, `--put-file`, `--get-file`, `--spider` (execution and file
  movement leave artifacts on the target);
- `--gen-relay-list` and anything that feeds `ntlmrelayx.py`;
- `--ntds vss` or `--dpapi` on hosts whose backup/VSS behaviour is unknown;
- raising `-t` above single digits, or removing `--jitter`, against a live
  directory;
- leaving `/root/.nxc/` (or any credential DB) in the container as the only
  copy of an engagement's findings.
