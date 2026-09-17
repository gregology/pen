# nuclei — worked examples

Every command below was run in the agent container as root. Output shown is
real, trimmed where marked. Two variables are assumed:

```bash
export TARGET=https://example.com     # an authorized target
export WORK=/working/engagements/example
mkdir -p "$WORK"
```

For a target you can use without asking, `scanme.nmap.org` is provided by the
nmap project for scan testing and `example.com` is safe for single requests.
Keep rates low against both. Note that from some network positions
`scanme.nmap.org:80` is unreachable; confirm with httpx before concluding a
scan was clean.

## 1. Confirm the scanner is actually armed

A nuclei with no templates is worse than no nuclei: every scan returns nothing
and looks like a clean target.

```bash
nuclei -version -duc
nuclei -tv -duc
find /root/nuclei-templates -name '*.yaml' | wc -l
```

Real output on this image:

```
[INF] Nuclei Engine Version: v3.11.1
[INF] Nuclei Config Directory: /root/.config/nuclei
[INF] Nuclei Cache Directory: /root/.cache/nuclei
[INF] Public nuclei-templates version:  (/root/nuclei-templates)
13742
```

The version string is **empty** even though 13,742 templates are installed —
`-tv` reads metadata that nuclei's own updater writes, and this image's
templates were installed by extracting a release archive. Trust the file count,
not the version line.

If `find` returns 0, every command below will abort with
`[FTL] Could not run nuclei: no templates provided for scan`. Fix the
environment before scanning anything.

## 2. Fingerprint first, then scan what the fingerprint implies

```bash
nuclei -u "$TARGET" -severity info -tags tech -jsonl -silent -duc -ni -rl 10 -c 5
```

One line per technology. A Rails app does not need a WordPress sweep, and this
is how you find out which CVE templates are worth the requests:

```bash
jq -r '[."template-id", ."matched-at"] | @tsv' <(nuclei -u "$TARGET" \
  -severity info -tags tech -jsonl -silent -duc -ni -rl 10 -c 5)
```

## 3. A real finding, end to end

Missing security headers is the cheapest useful check and it produces a large,
readable result set with named matchers — good for validating the pipeline
before pointing it at anything expensive.

```bash
nuclei -u "$TARGET" \
  -t http/misconfiguration/http-missing-security-headers.yaml \
  -jsonl -silent -duc -ni -rl 5 -c 3 \
  -o "$WORK/nuclei-headers.jsonl"
wc -l "$WORK/nuclei-headers.jsonl"
```

Against `https://example.com` this returned 1 finding. The object looks like
this (trimmed):

```json
{"template":"http/misconfiguration/http-missing-security-headers.yaml",
 "template-url":"https://cloud.projectdiscovery.io/public/http-missing-security-headers",
 "template-id":"http-missing-security-headers",
 "template-path":"/root/nuclei-templates/http/misconfiguration/http-missing-security-headers.yaml",
 "info":{"name":"HTTP Missing Security Headers","author":["pdteam"],"tags":["misconfig","http","headers"],
         "description":"...","severity":"info","metadata":{...},
         "classification":{"cve-id":null,"cwe-id":["cwe-693"]}},
 "matcher-name":"strict-transport-security","type":"http","host":"example.com","port":"443","scheme":"https",
 "url":"https://example.com","matched-at":"https://example.com","ip":"172.66.147.243",
 "timestamp":"2026-09-17T21:06:00Z",
 "curl-command":"curl -X 'GET' -d '' -H 'Accept: */*' -H 'Accept-Language: en' ... 'https://example.com'",
 "matcher-status":false,
 "request":"GET / HTTP/1.1\r\n...","response":"HTTP/1.1 200 OK\r\n..."}
```

Note `info.classification.cwe-id` is an **array** while `cve-id` is null, and
that `matcher-name` tells you *which* header was missing. That is the field
that makes a missing-headers result readable instead of a wall of identical
lines.

## 4. High-severity sweep with evidence retained

```bash
nuclei -u "$TARGET" \
  -severity high,critical \
  -etags dos,fuzz,intrusive \
  -rl 10 -c 5 -timeout 10 -retries 2 -ni \
  -silent -jsonl -duc \
  -o "$WORK/nuclei-high.jsonl" \
  -sresp -srd "$WORK/nuclei-traffic"
```

`-sresp` writes every request and response nuclei sent, not just the matches.
Per finding, confirm by hand before writing it up:

```bash
jq -r 'select(.info.severity=="critical") | ."curl-command"' "$WORK/nuclei-high.jsonl"
```

Each emitted `curl-command` is the exact request that matched, so the finding
is reproducible without nuclei.

## 5. Trim the JSON before it reaches a report

```bash
nuclei -u "$TARGET" -severity low,medium,high,critical -ni -silent -jsonl -duc \
  -or -o "$WORK/nuclei-lean.jsonl"

jq -r '[.info.severity, ."template-id", ."matched-at"] | @tsv' "$WORK/nuclei-lean.jsonl" \
  | sort -r > "$WORK/nuclei-findings.tsv"
column -t -s$'\t' "$WORK/nuclei-findings.tsv" | head -30
```

`-or` drops the raw request/response pair, which typically removes most of the
file size and any credentials that were echoed into it.

## 6. Export in the format the reader wants

All four were verified:

```bash
nuclei -u "$TARGET" -t http/misconfiguration/http-missing-security-headers.yaml \
  -silent -duc -ni \
  -jle "$WORK/findings.jsonl" \
  -je  "$WORK/findings.json" \
  -me  "$WORK/findings-md" \
  -se  "$WORK/findings.sarif"

wc -l "$WORK/findings.jsonl"   # one JSON object per finding
head -c 100 "$WORK/findings.json"   # a JSON array
find "$WORK/findings-md" -type f    # one .md per finding, plus index.md
```

## 7. Feed nuclei from the rest of the toolchain

```bash
# confirmed live URLs -> scan
httpx -l "$WORK/hosts.txt" -silent -json -duc \
  | jq -r '.url' \
  | nuclei -severity medium,high,critical -ni -rl 25 -c 10 -silent -jsonl -duc \
      -o "$WORK/nuclei-live.jsonl"

# crawled URLs -> non-payload tags
katana -u "$TARGET" -d 3 -jc -silent -duc \
  | nuclei -tags exposure,misconfig -ni -rl 25 -c 10 -silent -jsonl -duc \
      -o "$WORK/nuclei-katana.jsonl"

# ports -> web -> findings
naabu -host "$TARGET" -top-ports 1000 -silent -rate 100 -c 10 -duc \
  | httpx -silent -duc \
  | nuclei -severity medium,high,critical -ni -rl 25 -c 10 -silent -jsonl -duc
```

nuclei reads bare URLs or hosts on stdin, one per line, whenever `-u` and `-l`
are absent.

## 8. Authoring a local template, and the trap that eats it

A hand-written template is accepted if it lives in the templates tree:

```bash
mkdir -p /root/nuclei-templates/custom-docs
cat > /root/nuclei-templates/custom-docs/fixture-check.yaml <<'YAML'
id: docs-fixture-check

info:
  name: Docs Fixture Check
  author: docs-verification
  severity: low
  description: Matches the local fixture banner.
  tags: fixture

http:
  - method: GET
    path:
      - "{{BaseURL}}/"
    matchers:
      - type: word
        name: fixture-title
        part: body
        words:
          - "Pen Fixture Home"
    extractors:
      - type: regex
        name: page-title
        part: body
        regex:
          - "<title>([^<]+)</title>"
        group: 1
YAML

nuclei -tl -t custom-docs/ -duc            # confirm the loader accepted it
nuclei -u http://127.0.0.1:8099 -t custom-docs/fixture-check.yaml \
  -jsonl -silent -duc -ni
```

Verified output for a matching target:

```json
{"template":"custom-docs/fixture-check.yaml","template-id":"docs-fixture-check",
 "template-path":"/root/nuclei-templates/custom-docs/fixture-check.yaml",
 "template-encoded":"aWQ6IGRvY3MtZml4dHVyZS1jaGVjaw...",
 "info":{"name":"Docs Fixture Check","author":["docs-verification"],"tags":["fixture"],"severity":"low"},
 "extractor-name":"page-title","type":"http","host":"127.0.0.1","port":"8099","scheme":"http",
 "url":"http://127.0.0.1:8099","matched-at":"http://127.0.0.1:8099",
 "extracted-results":["Pen Fixture Home"],"ip":"127.0.0.1","timestamp":"...",
 "curl-command":"curl -X 'GET' ...","matcher-status":false,"request":"...","response":"..."}
```

Locally authored templates carry `template-encoded` (the template itself)
instead of `template-url`, and `extractor-name` appears when the extractor is
named.

**The trap:** change that `tags: fixture` to `tags: local` and the template
disappears:

```
[FTL] Could not run nuclei: no templates provided for scan
```

`local` is a default-excluded tag. The template validates fine
(`nuclei -validate -t <file>` says "All templates validated successfully"), it
just never loads, and the error blames your template set. `-tl -t custom-docs/`
shows what actually loaded. Either avoid `local`, or force it back with
`-itags local`.

## 9. Prove a scan actually happened before reporting "clean"

```bash
nuclei -u "$TARGET" -severity high,critical -stats -si 10 -ni -duc 2>&1 | tail -20
```

A run that reports `Requests: 0`, or a wall of errors, proves nothing about the
target. A run with thousands of requests and zero matches is a defensible
negative result. Pair it with the template count from step 1 so the negative
result is attributable to a known template set.
