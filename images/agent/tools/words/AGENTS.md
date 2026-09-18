# words — the pentest wordlists

SecLists, pinned by release tag, at `/opt/wordlists/current`. Every discovery
tool in the toolchain reads from here: gobuster, ffuf, feroxbuster, dnsx,
gobuster `vhost`, hydra, hashcat, sqlmap. This is data, not a tool — there is no
binary, and the directory exists so the lists live in one known place instead of
being re-downloaded per engagement.

## Install and location

| | |
|---|---|
| Release | SecLists 2026.1 (upstream tarball, pinned in `install.sh`) |
| Root | `/opt/wordlists/SecLists` |
| Stable path | `/opt/wordlists/current` (symlink to the pinned tree) |
| Checksum | none published upstream — the version tag is the pin |

Always reference `/opt/wordlists/current`, never the versioned directory: a
future bump moves the symlink and leaves every documented command working. The
tag is the build-time pin recorded in `install.sh`; the tree is a plain extracted
copy with no version marker, so the tag is not verifiable from the running
container.

## Paths that matter

**Web content discovery**

| Path | Shape |
|---|---|
| `Discovery/Web-Content/common.txt` | ~4.6k words; the standard first pass |
| `Discovery/Web-Content/raft-small-words.txt` | 43,007 words; small only against the rest of the raft set |
| `Discovery/Web-Content/raft-medium-directories.txt` | ~30k directory-shaped words |
| `Discovery/Web-Content/raft-large-directories.txt` | the big directory list |
| `Discovery/Web-Content/raft-medium-files.txt` | file-shaped, with extensions |
| `Discovery/Web-Content/raft-medium-extensions.txt` | extensions, for `-x`/`-X` |
| `Discovery/Web-Content/burp-parameter-names.txt` | parameter names for arjun/ffuf |
| `Discovery/Web-Content/api/api-endpoints.txt` | API paths |
| `Discovery/Web-Content/quickhits.txt` | high-signal short list |
| `Discovery/Web-Content/Logins.fuzz.txt` | login paths |

**DNS and vhosts**

| Path | Shape |
|---|---|
| `Discovery/DNS/subdomains-top1million-5000.txt` | 5k, the usual vhost/dns list |
| `Discovery/DNS/subdomains-top1million-20000.txt` | 20k |
| `Discovery/DNS/namelist.txt` | short name list |
| `Discovery/DNS/dns-Jhaddix.txt` | large mixed list |

**Credentials**

`Passwords/Common-Credentials/10k-most-common.txt`,
`Passwords/Leaked-Databases/rockyou.txt.tar.gz` (compressed — extract before
use; `Passwords/Leaked-Databases/rockyou-NN.txt` are percentage samples),
`Usernames/top-usernames-shortlist.txt`.

**Payloads**

`Fuzzing/command-injection-commix.txt`, `Fuzzing/XSS/`, `Fuzzing/LFI/`,
`Fuzzing/Databases/`.

## The rename that breaks copied commands

In the 2026.1 tag, the long-standing `directory-list-2.3-*` files were renamed:

| Old name (still cited in many write-ups) | Name in this release |
|---|---|
| `Discovery/Web-Content/directory-list-2.3-small.txt` | `DirBuster-2007_directory-list-2.3-small.txt` |
| `Discovery/Web-Content/directory-list-2.3-medium.txt` | `DirBuster-2007_directory-list-2.3-medium.txt` |
| `Discovery/Web-Content/directory-list-2.3-big.txt` | `DirBuster-2007_directory-list-2.3-big.txt` |

A command copied from a tutorial that references the old name fails with a
missing-file error. Verify a path before citing it:

```bash
ls /opt/wordlists/current/Discovery/Web-Content/ | grep -i dirbuster
```

## Verifying an install

```bash
test -s /opt/wordlists/current/Discovery/Web-Content/common.txt
test -d /opt/wordlists/current/Discovery/DNS
ls -l /opt/wordlists/current          # -> /opt/wordlists/SecLists
```

Both checks run at the end of `install.sh`, so a build that produces an empty or
mis-named tree fails rather than shipping a toolchain whose wordlists are
missing.

## Notes

- **Wordlist choice changes the result as much as the tool does.** A scan with
  `common.txt` and a scan with `raft-large-directories.txt` are different
  experiments; record which list produced a finding.
- **`raft-medium-directories.txt` and `raft-medium-files.txt` are not
  interchangeable.** The directory list has no extensions; the file list does.
  Using the wrong one is a common cause of a thin result set.
- **rockyou is shipped compressed.** Extract it into `$WORK`, not into
  `/opt/wordlists`, so a 133 MB file is not duplicated into the image layer at
  runtime.
- SecLists is large. If disk pressure appears, check `du -shL
  /opt/wordlists/current` before assuming a scan is at fault.
