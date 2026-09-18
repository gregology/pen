# dirb — legacy web content scanner (use only when you have a reason)

dirb brute-forces web paths from a wordlist and decides what "not found" looks
like per directory (its NEC heuristic, computed from a request to a random
name). It is installed for completeness and for its bundled server-specific
wordlists, **not** as the content discovery tool of choice. For path
brute-forcing use `gobuster`, `ffuf` or `feroxbuster`: dirb is single-threaded,
has no JSON output, cannot read targets from stdin, and its upstream has not
released since 2.22 (the man page in the Debian package is dated 2009; the last
Debian change was 2020).

## Install and location

| | |
|---|---|
| Version | 2.22+dfsg-5 (Debian bookworm package, unpinned) |
| Binaries | `/usr/bin/dirb`, `/usr/bin/dirb-gendict`, `/usr/bin/html2dic` |
| Wordlists | 40+ files under `/usr/share/dirb/wordlists/` |

No root needed, no TTY needed, but the interactive hotkeys are TTY-only (see
Failure modes).

## Flags that matter

| Flag | What it does |
|---|---|
| `dirb <url_base> [wordlist …]` | Target plus optional wordlist file(s), space-separated. Default wordlist is `/usr/share/dirb/wordlists/common.txt`. |
| `-o FILE` | Write the full session log to a file (the same text you see on screen). |
| `-S` | Silent mode: do not print each tested word. Found URLs are still printed. |
| `-r` | **Do not recurse.** Recursion into found directories is on by default. |
| `-R` | Interactive recursion: ask before entering each directory (needs a TTY). |
| `-w` | Do not stop on WARNING messages (default: leave a directory whose every response is 401/403/500 after 100 of them). |
| `-N <code>` | Treat this HTTP code as non-existent. |
| `-f` | Fine-tune the not-found detection by comparing body size as well as code. |
| `-X <exts>` | Append extensions to every word, e.g. `-X .php,.bak`. |
| `-x <exts_file>` | Same, with the extensions listed in a file. |
| `-z <millisecs>` | Delay between requests in milliseconds. (The Debian man page's text for `-z` is wrong — it repeats the `-X` description; the source implements a delay.) |
| `-a <agent>` | Custom User-Agent (default is an IE6 string: `Mozilla/4.0 (compatible; MSIE 6.0; Windows NT 5.1)`). |
| `-c <cookies>` | Cookie header value. |
| `-H <header>` | Extra request header; repeatable. |
| `-u <user:pass>` | HTTP basic authentication. |
| `-i` | Case-insensitive search. |
| `-l` | Print the `Location` header of found redirects. |
| `-v` | Also show NOT_FOUND pages. |
| `-t` | Do not force a trailing `/` on URLs. |
| `-b` | Do not squash `/../` and `/./` sequences in the given URL. |
| `-p <proxy[:port]>`, `-P <user:pass>` | Proxy and proxy authentication (default proxy port 1080). |
| `-E <cert>` | Client certificate for mTLS. |
| `-resume` | **First argument**: resume the session dumped from `~/.cache/dirb/resume/`. |

Undocumented but parsed in 2.22: `-h <vhost>` (sends that Host header), `-s`
(verify the peer's TLS certificate — verification is **off** by default),
`-d <level>` (debug output). `-g`, `-m`, `-M` are accepted and do nothing;
their implementations are commented out in the source.

## Examples

### Default scan of a host

```bash
dirb https://target.example/ -o $WORK/dirb-root.txt
grep -E '^\+ ' $WORK/dirb-root.txt
```

Output is one line per hit: `+ https://target.example/admin (CODE:301|SIZE:0)`.
Recursion is on, so the run continues into every discovered directory — expect
a long run on a real site, and use `-r` when you only want the top level.

### Non-recursive, silent, throttled

```bash
dirb https://target.example/ -r -S -z 200 -o $WORK/dirb-flat.txt
```

`-S` keeps the transcript small, `-z 200` adds 200 ms between requests, `-r`
stops the recursion. This is the only rate control dirb has.

### A technology-specific wordlist — dirb's remaining unique value

```bash
dirb https://target.example/ /usr/share/dirb/wordlists/vulns/tomcat.txt -S -o $WORK/dirb-tomcat.txt
dirb https://target.example/ /usr/share/dirb/wordlists/big.txt -X .php,.bak -S -o $WORK/dirb-ext.txt
```

The `vulns/` lists (apache, iis, tomcat, jboss, weblogic, sharepoint, oracle,
sap, …) are plain wordlists and can be fed to gobuster/ffuf instead — usually
the better choice, because those tools are parallel and produce parseable
output:

```bash
gobuster dir -u https://target.example -w /usr/share/dirb/wordlists/vulns/tomcat.txt \
  -t 10 --delay 100ms -o $WORK/tomcat.txt
```

### Extensions and 404 handling on a soft-404 site

```bash
dirb https://target.example/ -f -N 404 -X .php,.html -S -o $WORK/dirb-soft404.txt
```

`-f` compares body size as well as status code. If every path comes back `200`
with a friendly error page, dirb's NEC logic is what you are fighting — and
ffuf's `-fs`/`-ac` filters are the better tool.

## Output formats

Text only. Every found object is `+ <url> (CODE:<status>|SIZE:<bytes>)`;
warnings are `(!) WARNING: …`; directory transitions are
`---- Entering directory: <url> ----`. `-o` writes the same log (banner,
options, findings) to a file — it is a log, not a result set.

There is no JSON, XML or CSV, and no status-code table. Machine-readable output
means `grep -oE '^\+ [^ ]+ \(CODE:[0-9]+\|SIZE:[0-9]+\)'` plus `awk`, or using
`gobuster dir`/`ffuf` instead.

## Failure modes

- **Exit codes:** `255` (`exit(-1)`) when no URL is given or a parameter is
  wrong, `0` when the run completes — including runs that found nothing. `$?`
  distinguishes nothing else.
- **The hotkeys need a TTY.** `q` (dump state and quit), `n` (next directory)
  and `r` (stats) are read with `select()` on stdin; with a non-TTY stdin the
  key read returns nothing and the scan simply runs to completion. In practice:
  redirect stdin from `/dev/null` and stop the run with a signal, and do not
  expect `-resume` to have anything to resume.
- **`-resume` is fragile.** State is dumped to `~/.cache/dirb/resume/` only when
  `q` is pressed; `dirb -resume` must be the first argument. In a headless
  container there is usually nothing to resume.
- **Recursion is on by default.** `-r` is required for a flat scan; without it a
  single hit on `/admin/` can multiply the run.
- **Single-threaded.** One request at a time with no concurrency option — a 20k
  word list against a slow target is measured in tens of minutes. This is the
  main reason to prefer gobuster/ffuf/feroxbuster.
- **Warnings stop directories.** On a directory where everything answers
  401/403/500, after 100 such responses dirb abandons it unless `-w` is given.
- **Listable directories are skipped by default** with `(!) WARNING: Directory
  IS LISTABLE. No need to scan it.` — `-w` makes it scan anyway.
- **TLS verification is off by default** (`CURLOPT_SSL_VERIFYPEER = 0`); `-s`
  turns it on. A real certificate problem will not be reported, which makes a
  dirb run against a self-signed or expiring endpoint look clean.
- **No stdin target input.** dirb takes the URL as an argument only.
- **Soft-404s break the NEC logic.** A site answering `200` with a generic page
  to everything makes every word a "hit". `-f` mitigates; the fix is a
  different tool.

## Notes

- **Modern substitute:** `gobuster dir`/`feroxbuster` for paths (parallel,
  parseable), `ffuf -ac` when the site has soft-404s. Keep dirb for its
  `vulns/` wordlists and for reproducing older write-ups.
- **Wordlists:** dirb's own lists are under `/usr/share/dirb/wordlists/`
  (`common.txt`, `big.txt`, `small.txt`, `indexes.txt`, `extensions_common.txt`,
  `mutations_common.txt`, `others/`, `stress/`, `vulns/`). SecLists is at
  `/opt/wordlists/current` — `Discovery/Web-Content/common.txt`,
  `raft-small-directories.txt`, `raft-medium-directories.txt`,
  `DirBuster-2007_directory-list-2.3-small.txt` (the current name for the old
  `directory-list-2.3-small.txt`).
- The default User-Agent is a 2001-era IE6 string; anything watching for
  scanners will notice. `-a` overrides it if the engagement requires blending in.
- No configuration file, no shell-out to other tools, and no output directory
  convention: everything is the current working directory and whatever `-o` you
  pass. Keep artifacts under `$WORK`.

## Safety

- Only against targets explicitly confirmed for the engagement.
- dirb follows every discovered directory by default, including logout and
  delete paths; use `-r` or restrict the wordlist on an application where that
  matters.
- The default User-Agent identifies the tool. On an engagement where the target
  owner expects to see the traffic, that is fine; where they do not, raise it
  before scanning rather than after.
