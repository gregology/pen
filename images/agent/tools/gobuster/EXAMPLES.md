# gobuster — worked workflows

Assumes `$TARGET` is an authorised host, `$WORK` the engagement directory, and
wordlists under `/opt/wordlists/current` (SecLists). All paths below exist in
that release.

Remember the version: **gobuster 3.5.0**, which has no JSON output and no
`--rate`. Rate control is `-t` × `--delay`.

## 1. First pass over a web application

Goal: a fast, low-noise inventory before anyone fuzzes anything.

```bash
mkdir -p "$WORK"

gobuster dir -u "https://$TARGET" \
  -w /opt/wordlists/current/Discovery/Web-Content/common.txt \
  -t 10 --delay 100ms -k -o "$WORK/dir-common.txt"
```

Results look like:

```
/admin                (Status: 301) [Size: 0] [--> https://target.example/admin/]
/.git/HEAD            (Status: 200) [Size: 23]
/server-status        (Status: 403) [Size: 276]
```

If you instead get `the server returns a status code that matches the provided
options for non existing urls … (Length: 4321)`, the site has a catch-all
response. Record that length and re-run with `--exclude-length 4321`. Do not
proceed without excluding it — every subsequent result would be a false positive.

## 2. Turn the first pass into a tree without re-scanning everything

gobuster does not recurse, so drive it: extract the directories that answered
301/302 and re-run one level down.

```bash
grep -E '\(Status: 30[12]\)' "$WORK/dir-common.txt" | awk '{print $1}' | sort -u > "$WORK/dirs.txt"

while read -r d; do
  name=$(echo "$d" | tr -c 'A-Za-z0-9' '_')
  gobuster dir -u "https://$TARGET$d" \
    -w /opt/wordlists/current/Discovery/Web-Content/raft-medium-directories.txt \
    -t 10 --delay 100ms -k -q -o "$WORK/dir-$name.txt"
done < "$WORK/dirs.txt"
```

`-q` matters here: the banner and progress line per iteration are noise in a
loop, and results are appended to per-directory files so a crash mid-loop does
not lose earlier output. If recursion depth is what you actually want, stop and
use `feroxbuster --depth 4` instead — it manages the queue itself.

## 3. Extension discovery, then a targeted file pass

```bash
gobuster dir -u "https://$TARGET" \
  -w /opt/wordlists/current/Discovery/Web-Content/raft-medium-extensions.txt \
  -f -t 10 --delay 100ms -k -q -o "$WORK/ext-probe.txt"

grep -E '\(Status: 200\)' "$WORK/ext-probe.txt" | awk '{print $1}' | tr -d '/' | sort -u
```

`-f` appends `/` to each entry, turning `php` into `/php/` — a directory probe
that filters out the catch-all. Then use the extensions that produced 200/403:

```bash
gobuster dir -u "https://$TARGET" \
  -w /opt/wordlists/current/Discovery/Web-Content/raft-medium-files.txt \
  -x php,html,bak,old -s 200,204,301,302,307,401,403 -b "" \
  --exclude-length 4321 -t 10 --delay 100ms -k -q -o "$WORK/files.txt"
```

`-x` multiplies the wordlist by the extension count, so this is the step where
`--delay` matters. `-b ""` is mandatory when `-s` is set.

## 4. Virtual hosts on one IP (the mode that finds what DNS cannot)

```bash
gobuster vhost -u "https://$TARGET" \
  -w /opt/wordlists/current/Discovery/DNS/subdomains-top1million-5000.txt \
  --append-domain --domain target.example \
  -t 10 --delay 100ms -k -q -o "$WORK/vhost-raw.txt"
```

Noise control — a default vhost answers every Host header identically, so
measure the baseline first:

```bash
BASELINE=$(curl -sk -o /dev/null -w '%{size_download}' \
  -H "Host: zzz-does-not-exist.target.example" "https://$TARGET")

gobuster vhost -u "https://$TARGET" \
  -w /opt/wordlists/current/Discovery/DNS/subdomains-top1million-5000.txt \
  --append-domain --domain target.example --exclude-length "$BASELINE" \
  -t 10 --delay 100ms -k -q -o "$WORK/vhost.txt"
```

Every surviving `Found:` line is a vhost whose response differs from the
default. Feed those names into `/etc/hosts` (or `curl --resolve`) and scan them
as separate sites.

## 5. DNS brute-force that complements subfinder/dnsx

```bash
subfinder -d target.example -silent | dnsx -silent -a -resp > "$WORK/passive.txt"

gobuster dns -d target.example \
  -w /opt/wordlists/current/Discovery/DNS/subdomains-top1million-20000.txt \
  -t 20 --timeout 2s -i --no-color -o "$WORK/dns-brute.txt"

grep '^Found: ' "$WORK/dns-brute.txt" | awk '{print $2}' | sort -u > "$WORK/brute.txt"
comm -13 <(awk '{print $1}' "$WORK/passive.txt" | sort -u) "$WORK/brute.txt"
```

The `comm` line is the point: it prints the names brute force found that passive
sources did not. If gobuster aborts with a wildcard error, the zone has a
wildcard record — add `--wildcard` only to continue, and expect mostly false
hits.

## 6. A WAF-fronted target: choosing the rate

```bash
wafw00f "https://$TARGET" -a -f json -o "$WORK/waf.json"
if jq -e '.[] | select(.detected == true)' "$WORK/waf.json" >/dev/null; then
  T=4; D=750ms
else
  T=10; D=100ms
fi

gobuster dir -u "https://$TARGET" \
  -w /opt/wordlists/current/Discovery/Web-Content/common.txt \
  -t "$T" --delay "$D" -k -v -o "$WORK/dir.txt"
grep -ci 'Status: 429' "$WORK/dir.txt" || true
```

`-v` is deliberate: it prints `Missed:` lines and errors, which is how you see
timeouts and connection resets instead of silently concluding "no paths exist".
If 429s appear, halve `-t` and double `--delay`; if timeouts appear, raise
`--timeout` and add `--retry`.

## 7. Reproducible evidence

gobuster has no JSON to archive, so the note has to carry the command, the
version, the wordlist hash and the filtered results:

```bash
{
  echo "# gobuster — $(date -Is)"
  gobuster version
  echo "wordlist: $(sha256sum /opt/wordlists/current/Discovery/Web-Content/common.txt)"
  echo "target: https://$TARGET"
} >> "$WORK/notes.md"

grep -E '\(Status: (200|30[12])\)' "$WORK/dir-common.txt" >> "$WORK/notes.md"
```
