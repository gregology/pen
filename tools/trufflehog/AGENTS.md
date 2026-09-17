# trufflehog

TruffleHog finds credentials in source trees, git history, container images, and
other sources, and — when allowed to — verifies each candidate by calling the
issuing service's API. It is the tool for the question the external scanners
cannot answer: *did someone commit a live key into one of Greg's repositories?*
Its value is the verification step; its risk is that verification is an outbound
call carrying a credential, and that raw findings are secrets.

## Installation and location

| | |
|---|---|
| Version | 3.97.5 (`trufflehog --version`) |
| Binary | `/usr/local/bin/trufflehog` (upstream release tarball, 36 MB) |
| Detectors | compiled into the binary; no rules directory |
| Config | optional, `--config FILE`; verification endpoints via `--verifier` |
| Cache | none — nothing is written outside the output file |
| Sources | `git`, `github`, `gitlab`, `filesystem`, `s3`, `gcs`, `docker`, `syslog`, `stdin`, `multi-scan`, `json-enumerator`, `jenkins`, `elasticsearch`, `postman`, `huggingface`, `circleci`, `travisci`, plus `analyze` for key permissions |

The CLI is Kingpin-based: `trufflehog [<flags>] <command> [<args> ...]`. Global
flags may appear before the command; **source-specific flags must appear after
it** (see the gotchas).

## Rules that apply to this tool

1. **Authorization first.** Scanning a repository, bucket, or image that is not
   in scope reads other people's data. Confirm the target with Greg first.
2. **Verification is an outbound call with a credential in it.** With verification
   enabled (the default for `--results`), trufflehog replays a found credential
   against the issuing service — GitHub, Slack, AWS, and so on. That traffic
   leaves through the VPN like everything else, hits a third party, and can appear
   in their logs or trigger their abuse controls. Use `--no-verification` when the
   engagement does not authorize calling third-party APIs, and say so in the
   findings note.
3. **Findings are live secrets.** Default (non-JSON) output prints the raw secret
   in full; JSON output carries `Raw`, `RawV2`, and `SecretParts`. Never paste a
   finding into the transcript: write `--json` output to a file inside `$WORK`,
   and record only detector, file, commit, and line in human-readable notes.
4. **A scan is read-only.** `filesystem` and `git` only read; `docker` pulls image
   layers over the network; `s3`/`gcs`/`github`/`gitlab` need credentials and reach
   out. Do not point credentials-bearing sources at anything unauthorized.
5. **Silence is not proof.** TruffleHog validates structure (a GitHub PAT needs a
   valid checksum) and, by default, reports unverified detections too — but
   syntactically invalid fakes produce *zero* results. Absence of findings means
   "nothing matched a detector", not "no secrets".
6. **Evidence to `$WORK`.** `trufflehog --json ... > "$WORK/trufflehog/<label>.jsonl"`
   plus the exact command line; keep the per-scan summary line from stderr.

## Command reference

Global flags that matter

| Flag | Meaning |
|---|---|
| `-j, --json` | One JSON object per finding (JSONL) on stdout |
| `--no-verification` | Do not call the issuing API; every result becomes `Verified: false` |
| `--results=` | `verified`, `unknown`, `unverified`, `filtered_unverified`; default `verified,unverified,unknown` |
| `--fail` | Exit 183 when results are found |
| `--fail-on-scan-errors` | Exit 1 when the scan hits an error; without it, errors exit 0 |
| `--concurrency=N` | Worker count |
| `--include-detectors="all"` / `--exclude-detectors=` | Restrict detectors |
| `--filter-entropy=3.0` | Drop unverified results below an entropy threshold |
| `--filter-unverified` | Keep only the first unverified hit per chunk per detector |
| `--max-decode-depth=5` | Iterative decoding depth (base64 inside UTF-16, …) |
| `--sarif`, `--github-actions`, `--json-legacy` | Alternate output formats |
| `--log-level=-1` | Silence the JSON log lines on stderr |
| `--no-update` | Do not check GitHub for a newer release at startup |
| `--config FILE`, `--verifier=`, `--custom-verifiers-only`, `--detector-timeout=` | Configuration and verification control |
| `--archive-max-size/depth/timeout` | Limits when scanning archives |

Source flags (after the subcommand)

| Source | Flags |
|---|---|
| `git <uri>` | `--branch`, `--since-commit`, `--max-depth`, `--exclude-globs` |
| `filesystem [path]` | `--directory` (repeatable) |
| `docker --image NAME` | image reference; pulls from the registry |
| `s3`, `gcs`, `github`, `gitlab` | provider credentials and scope flags (not exercised here) |
| `-i/--include-paths FILE` | File of newline-separated regexes of paths to include |
| `-x/--exclude-paths FILE` | File of newline-separated regexes of paths to exclude |

`--only-verified` does **not** exist in 3.97.5 (`unknown long flag
'--only-verified'`); the equivalent is `--results=verified`.

## Typical workflows

1. **Local repository including history** (the commit-level answer):

   ```bash
   mkdir -p "$WORK/trufflehog"
   trufflehog --no-update --no-verification --log-level=-1 --json \
       git "file://$WORK/src/project" \
       > "$WORK/trufflehog/project.jsonl" 2> "$WORK/trufflehog/project.log"
   jq -r '"\(.DetectorName)\t\(.Verified)\t\(.SourceMetadata.Data.Git.file)\t\(.SourceMetadata.Data.Git.commit[0:8])"' \
       "$WORK/trufflehog/project.jsonl" | sort -u
   ```

   The URI scheme is required: `file:///abs/path` works, a bare `/abs/path` fails.

2. **Verified results only**, when verification is authorized:

   ```bash
   trufflehog --no-update --json --results=verified \
       git "file://$WORK/src/project" > "$WORK/trufflehog/verified.jsonl"
   ```

3. **A directory of repositories or an unpacked tree:**

   ```bash
   trufflehog --no-update --no-verification --log-level=-1 --json \
       filesystem "$WORK/src" > "$WORK/trufflehog/tree.jsonl"
   ```

4. **A container image** (registry pull, no Docker socket needed):

   ```bash
   trufflehog --no-update --no-verification --json docker --image "$IMAGE" \
       > "$WORK/trufflehog/image.jsonl"
   ```

5. **Anything on stdin** — piping a config or a diff:

   ```bash
   cat "$WORK/src/project/config/database.yml" \
     | trufflehog --no-update --no-verification --json stdin
   ```

## Output and parsing

One JSON object per line, on stdout; logs and the summary line go to stderr.

```json
{"SourceMetadata":{"Data":{"Filesystem":{"file":"/tmp/thv/fs2/uris.txt","line":1}}},"SourceID":1,
 "SourceType":15,"SourceName":"trufflehog - filesystem","DetectorType":968,
 "DetectorName":"Postgres","DetectorDescription":"Postgres connection string containing credentials",
 "DecoderName":"PLAIN","Verified":false,"VerificationFromCache":false,
 "Raw":"postgres://admin:S3cr3tP4ssw0rd@db.internal:5432","RawV2":"postgres://admin:S3cr3tP4ssw0rd@db.internal:5432",
 "Redacted":"","ExtraData":{"database":"appdb","host":"db.internal:5432","sslmode":"<unset>","username":"admin"},
 "StructuredData":null,"SecretParts":{"connection_string":"postgres://admin:S3cr3tP4ssw0rd@db.internal:5432"}}
```

Git findings put `commit`, `file`, `email`, `repository`, `timestamp`, and `line`
under `SourceMetadata.Data.Git`. Fields that matter:

| Field | Notes |
|---|---|
| `DetectorName` | `PrivateKey`, `Postgres`, `MongoDB`, `AWS`, … |
| `Verified` | `true` only when the issuing API confirmed the credential |
| `Raw` / `RawV2` / `SecretParts` | The secret itself — treat as confidential |
| `Redacted` | Present for some detectors; may still be empty |
| `SourceMetadata` | Where it was found (file+line, git commit, image layer) |
| `DecoderName` | `PLAIN`, `BASE64`, … |

Recipes that do not print secrets:

```bash
# one line per finding: detector, location, verification state
jq -r 'if .SourceMetadata.Data.Git then
         "\(.DetectorName)\t\(.Verified)\tgit:\(.SourceMetadata.Data.Git.file):\(.SourceMetadata.Data.Git.line)@\(.SourceMetadata.Data.Git.commit[0:8])"
       else
         "\(.DetectorName)\t\(.Verified)\t\(.SourceMetadata.Data.Filesystem.file):\(.SourceMetadata.Data.Filesystem.line)"
       end' findings.jsonl | sort -u

# counts by verification state
jq -r '.Verified' findings.jsonl | sort | uniq -c

# unique detectors present
jq -r '.DetectorName' findings.jsonl | sort -u
```

The stderr summary line is the scan's evidence record — keep it:

```json
{"level":"info-0","logger":"trufflehog","msg":"finished scanning","chunks":3,"bytes":1906,
 "verified_secrets":0,"unverified_secrets":3,"scan_duration":"34.07274ms","trufflehog_version":"3.97.5"}
```

Exit codes: `0` for a completed scan regardless of findings; `183` with `--fail`
and at least one finding; `1` with `--fail-on-scan-errors` and a scan error.
Without `--fail-on-scan-errors`, a scan that could not read its target still exits
0 — do not treat exit 0 as "clean" unless you also checked the log for
`"msg":"error running scan"`.

## Chaining with the rest of the toolchain

```bash
# scan a directory of repos, keep one JSONL per repo, then triage centrally
for d in "$WORK"/src/*/; do
  name=$(basename "$d")
  trufflehog --no-update --no-verification --log-level=-1 --json git "file://$d" \
    > "$WORK/trufflehog/$name.jsonl" 2>/dev/null
done
jq -r '"\(.DetectorName)\t\(.SourceMetadata.Data.Git.repository // "?")\t\(.SourceMetadata.Data.Git.file)"' \
   "$WORK"/trufflehog/*.jsonl | sort -u > "$WORK/findings/secrets.txt"
```

```bash
# trufflehog (history) and trivy (working tree) cover different ground
trufflehog --no-update --no-verification --json git "file://$WORK/src/project" \
  > "$WORK/trufflehog/project.jsonl"
trivy fs --scanners secret -f json -o "$WORK/trivy/secrets.json" "$WORK/src/project"
```

```bash
# exit-code gate for a repeat scan (verified findings only)
trufflehog --no-update --json --results=verified --fail git "file://$WORK/src/project" \
  > "$WORK/trufflehog/verified.jsonl" || echo "verified secrets present (exit 183)"
```

```bash
# a pcap or mitmproxy flow can also carry credentials: grep the extracted text,
# then feed candidate lines through the stdin source
tshark -r "$WORK/pcap/http.pcap" -Y http.request -T fields -e http.authorization \
  | trufflehog --no-update --no-verification --json stdin
```

## Limits, failure modes and gotchas

- **Source flags must follow the subcommand.** `trufflehog --exclude-paths=f
  filesystem /path` fails with `unknown long flag '--exclude-paths'` while
  `trufflehog filesystem --exclude-paths=f /path` works. With `--json` and stderr
  discarded the failure looks like a clean scan of zero findings. Always keep
  stderr.
- **`git` needs a URI.** `file:///abs/path` or an `https://`/`ssh://` remote;
  a bare path fails with `error preparing repo: unsupported Git URI: /abs/path`.
- **`--only-verified` is gone.** Use `--results=verified` (or `--results
  verified,unknown`). With `--no-verification` every result is unverified, so
  `--results=verified` returns nothing at all — expected, not a bug.
- **Verification is on by default and it calls out.** There is no local-only
  verification. If the network path to a provider is blocked, results come back
  `unknown` rather than verified. Use `--no-verification` deliberately and record
  that you did.
- **Zero findings can mean "not detected".** Detectors validate structure: a
  fabricated `ghp_…`, `sk_live_…`, or `AKIA…` token produced no results here,
  while a generated RSA private key, a `postgres://…` URI, and a `mongodb://…`
  URI were all detected. Do not treat an empty JSONL as proof of a clean repo.
- **`--include-paths`/`--exclude-paths` take files, not patterns.** Each file
  holds newline-separated regexes. A missing file logs
  `unable to open filter file` and yields nothing (exit 0) — another silent-empty
  failure mode. `--exclude-globs='*.pem'` (git source only) takes a comma-separated
  glob list; the filesystem source rejects it.
- **`docker --image` needs no Docker socket** but does need registry egress: it
  pulled and scanned `debian:12` (8887 chunks, 127 MB) in ~7 s. It is a network
  operation, not a local one.
- **The default output prints secrets.** `Raw result:` in the human format is the
  whole credential. Use `--json` to a file, and never `--log-level` output with
  secrets into a transcript.
- **`--fail` is 183, not 1.** Scripts that test `$? -ne 0` conflate "findings" with
  "failure"; test explicitly.
- **Startup may check for updates.** `--no-update` suppresses the GitHub release
  check; without it the binary may make an outbound request before scanning. This
  behaviour was not exercised here (it is outside the authorized verification
  network), so treat the flag as the safe default rather than a proven necessity.
- **No progress indicator in JSON mode.** A long `docker` or `s3` scan looks
  identical to a hang until the summary line appears.

## Safety and scope

- Confirm the repository, image, or bucket with Greg before scanning it.
- Decide verification explicitly: `--no-verification` unless Greg has authorized
  outbound calls that carry a found credential to a third-party API.
- A verified finding is a live credential with a blast radius. Report the
  detector, location, and verification state; let Greg rotate it. Never use the
  credential in a later step without separate authorization.
- Never paste a raw secret, or a finding containing one, into the transcript or a
  commit. Findings go to `$WORK/trufflehog/` and to the findings note as
  locations, not values.
- Scanning `.git` directories of projects you have not been given is reading
  someone else's history — the same rule as reading their mail.
