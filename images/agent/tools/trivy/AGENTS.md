# trivy

Trivy is the vulnerability and misconfiguration scanner: one binary that reads OS
packages, language lockfiles, IaC and container images and reports known CVEs,
misconfigurations, embedded secrets, and licences. It is the tool that turns "this
service is running version X" into a list of CVEs with fixed versions, and the
only tool here that can audit the platform's own image without a container
runtime.

## Installation and location

| | |
|---|---|
| Version | 0.74.0 (`trivy --version`) |
| Binary | `/usr/bin/trivy` (upstream `.deb`, 168 MB) |
| Cache | `/root/.cache/trivy` — `db/` (1.4 GB), `java-db/` (~267 MB, on demand), `policy/` (3.1 MB checks bundle), `fanal/` (image/layer cache); not pre-seeded, created by the first DB download |
| Config | `trivy.yaml` in the working directory, or `-c FILE`; `--generate-default-config` writes a template |
| Env | `TRIVY_*` variables mirror every flag (`TRIVY_SKIP_DB_UPDATE=true`, `TRIVY_CACHE_DIR`, `TRIVY_SEVERITY`, …) |
| DB metadata | `/root/.cache/trivy/db/metadata.json` — `Version`, `UpdatedAt`, `NextUpdate`, `DownloadedAt`; exists only after the first DB download |

The cache is **not** baked into the image: at first use `/root/.cache/trivy` does
not exist, so neither `db/` nor `db/metadata.json` is present until a DB-backed
scan runs. Two data sets are fetched from the network on first use: the
vulnerability DB (`mirror.gcr.io/aquasec/trivy-db:2`, falling back to
`ghcr.io/aquasecurity/trivy-db:2`) and the misconfiguration checks bundle
(`mirror.gcr.io/aquasec/trivy-checks:2`).
The DB download is 113.92 MiB compressed and expands to 1.4 GB on disk; it is
re-fetched when `NextUpdate` passes. The Java index DB is pulled only when a Java
artefact is scanned.

## Rules that apply to this tool

1. **Authorization first.** Scanning a repository, image, or filesystem that is
   not in scope is reconnaissance of someone else's property. Confirm targets
   with Greg before the first scan.
2. **Remote image tags are a network fetch.** `trivy image <tag>` pulls manifests
   and layers from the registry. Pull only authorized images, and prefer a local
   directory or an SBOM when the image is yours.
3. **Reports contain exploitable detail.** A trivy report lists unpatched CVEs
   with versions and paths — a ready-made attack plan. Keep JSON output in
   `$WORK`, and do not paste whole reports into the transcript; summarise.
4. **Secret findings are credentials.** `--scanners secret` prints matched file,
   line, and rule. In 0.74.0 the `Match` field is masked (`GITHUB_TOKEN=****…`),
   but the file path and rule still point at a live secret — write findings to a
   file, and never copy the secret itself anywhere.
5. **Scan inside the container's own filesystem, never the host's.** `trivy fs /`
   and `trivy rootfs /` scan this container only. There is no host filesystem
   mounted and no Docker socket; do not go looking for one.
6. **Budget the cache and the scan tree.** Exclude the cache from whole-filesystem
   scans (`--skip-dirs /root/.cache`) or trivy spends its time re-reading its own
   1.4 GB database. Check `df -h /` before pulling the DB.
7. **Evidence to `$WORK`.** `-f json -o "$WORK/trivy/<label>.json"` plus the cache
   state (`jq . /root/.cache/trivy/db/metadata.json`) so a finding is
   reproducible against a known DB version.

## Command reference

Scanning subcommands (from `trivy --help`):

| Command | Alias | Target |
|---|---|---|
| `trivy fs PATH` | `filesystem` | A directory or file tree: language lockfiles, IaC, secrets |
| `trivy rootfs ROOTDIR` | — | An unpacked root filesystem, including OS packages (`/` for this container) |
| `trivy image [--input FILE] IMAGE` | — | A container image by tag, tar archive, or `--image-src` |
| `trivy repo PATH\|URL` | `repository` | A git repository, local path or remote URL |
| `trivy config PATH` | — | Configuration files only (Dockerfile, compose, Kubernetes, Terraform, Ansible, Helm) |
| `trivy sbom FILE` | — | An existing CycloneDX/SPDX SBOM |
| `trivy kubernetes`, `trivy vm` | — | Cluster / VM image (experimental) |

Utility subcommands: `convert` (re-render a saved JSON report), `clean`,
`server`, `registry`, `module`, `plugin`, `vex`, `version`.

Flags that matter

| Flag | Values / default |
|---|---|
| `--scanners` | `vuln,misconfig,secret,license`; default `vuln,secret` |
| `-s, --severity` | `UNKNOWN,LOW,MEDIUM,HIGH,CRITICAL`; default all |
| `-f, --format` | `table` (default), `json`, `template`, `sarif`, `cyclonedx`, `spdx`, `spdx-json`, `github`, `cosign-vuln` |
| `-o, --output` | Report file |
| `--exit-code N` | Exit N when findings exist; default 0 |
| `--ignore-unfixed` | Only report vulnerabilities with a fixed version |
| `--ignore-status`, `--ignorefile` | VEX statuses / `.trivyignore` path |
| `--skip-db-update` | Never fetch the DB; **fatal on a cold cache** |
| `--download-db-only` | Fetch the DB and exit |
| `--db-repository`, `--java-db-repository`, `--checks-bundle-repository` | Override the OCI sources |
| `--cache-dir` | Use a pinned cache (reproducible/offline scans) |
| `--offline-scan` | Do not issue API requests to identify dependencies |
| `--skip-dirs`, `--skip-files` | Exclude paths from the scan |
| `--list-all-pkgs` | Default true: include clean packages in JSON |
| `--include-non-failures` | With `misconfig`; include passes |
| `--misconfig-scanners` | `azure-arm,cloudformation,dockerfile,helm,kubernetes,terraform,terraformplan-json,terraformplan-snapshot,ansible` |
| `--secret-config` | Secret-scanner rules file (default `trivy-secret.yaml`) |
| `--image-src` | `docker,containerd,podman,remote`; default in that order |
| `--input FILE` | Scan an image tar instead of a tag |
| `--platform`, `--parallel` (5), `--timeout` (5m), `-q`, `-d` | Scope, workers, timeout, quiet, debug |

`--security-checks` still parses but produces no warning in 0.74.0; it is
deprecated in favour of `--scanners`. Use `--scanners`.

## Typical workflows

1. **Scan a project tree with everything on.** `misconfig` is *not* on by default.

   ```bash
   mkdir -p "$WORK/trivy"
   trivy fs --scanners vuln,misconfig,secret \
            -f json -o "$WORK/trivy/project.json" "$WORK/src/project"
   jq -r '.Results[] | "\(.Target) \(.Class) vulns=\(.Vulnerabilities|length) misconfig=\(.Misconfigurations|length) secrets=\(.Secrets|length)"' \
        "$WORK/trivy/project.json"
   ```

2. **Scan the container's own filesystem** (the only image this agent can reach
   without a runtime socket). Exclude the cache or it takes tens of minutes.

   ```bash
   trivy rootfs --scanners vuln --skip-dirs /root/.cache --skip-dirs /tmp \
         -f json -o "$WORK/trivy/self.json" / -q
   ```

3. **Scan a public image by tag** (registry pull, no Docker socket):

   ```bash
   trivy image --image-src remote --scanners vuln --severity CRITICAL \
         --ignore-unfixed debian:12
   ```

4. **Secrets only, no vulnerability DB needed** — fast, and useful in CI-like
   loops:

   ```bash
   trivy fs --cache-dir "$WORK/trivy/empty-cache" --scanners secret \
         -f json -o "$WORK/trivy/secrets.json" "$WORK/src/project"
   ```

5. **Reproducible/offline scan.** Prime once, then re-scan without the network:

   ```bash
   trivy fs --download-db-only                       # one time, ~114 MiB
   TRIVY_SKIP_DB_UPDATE=true trivy fs --scanners vuln \
         --cache-dir /root/.cache/trivy -f json -o out.json "$TARGET"
   jq -c '.Metadata? // empty' out.json              # image scans only
   jq -c . /root/.cache/trivy/db/metadata.json       # DB version used
   ```

## Output and parsing

JSON top level: `SchemaVersion`, `Trivy.Version`, `ArtifactName`, `ArtifactType`
(`filesystem`, `repository`, `container_image`), `CreatedAt`, `ReportID`,
`Results`, and `Metadata` (populated for images only; `null` for `fs`/`rootfs`).

`Results[]` is keyed by what was scanned:

| Field | Meaning |
|---|---|
| `Target` | File, lockfile, image, hostname, or binary |
| `Class` | `os-pkgs`, `lang-pkgs`, `config`, `secret` |
| `Type` | `debian`, `npm`, `pip`, `gobinary`, `dockerfile`, … (`null` for secret results) |
| `Vulnerabilities[]` | `VulnerabilityID`, `PkgName`, `InstalledVersion`, `FixedVersion`, `Severity`, `Status`, `CVSS`, `PrimaryURL`, `CweIDs` |
| `Misconfigurations[]` | `ID` (`DS-0002`), `Title`, `Message`, `Resolution`, `Severity`, `Status`, `CauseMetadata.StartLine` |
| `Secrets[]` | `RuleID` (`github-pat`), `Title`, `Severity`, `StartLine`, `EndLine`, `Match` (masked) |

Recipes:

```bash
# findings needing a patch, worst first
jq -r '.Results[] | .Target as $t | .Vulnerabilities[]?
       | select(.FixedVersion != null and .FixedVersion != "")
       | "\(.Severity)\t\($t)\t\(.PkgName) \(.InstalledVersion) -> \(.FixedVersion)\t\(.VulnerabilityID)"' \
   report.json | sort -r | head -20

# severity histogram
jq -r '[.Results[]?.Vulnerabilities[]?.Severity] | group_by(.) | map("\(.[0])=\(length)") | .[]' report.json

# secrets with location, no secret material
jq -r '.Results[]? | select(.Secrets) | .Target as $t | .Secrets[] | "\(.Severity)\t\(.RuleID)\t\($t):\(.StartLine)"' report.json

# misconfiguration summary
jq -r '.Results[]? | select(.Misconfigurations) | .Target as $t | .Misconfigurations[] | "\(.Severity)\t\(.ID)\t\($t):\(.CauseMetadata.StartLine)\t\(.Title)"' report.json
```

Table output is for humans only; it truncates titles and hides fields. Parse the
JSON.

Exit codes: `0` when the scan completes and `--exit-code` is unset, `N` when
`--exit-code N` is set and anything matched, `1` on a fatal error (for example
`--skip-db-update` with no cached DB: `FATAL Fatal error run error: init error: DB
error: database error: --skip-db-update cannot be specified on the first run`).
Severity filtering happens before `--exit-code` is evaluated, so
`--severity CRITICAL --ignore-unfixed --exit-code 1` fails only on actionable
critical findings.

## Chaining with the rest of the toolchain

```bash
# trivy JSON -> a findings note
trivy fs --scanners vuln,misconfig,secret -f json -o "$WORK/trivy/scan.json" "$TARGET"
jq -r '.Results[] | .Target as $t | .Vulnerabilities[]?
       | select(.Severity=="CRITICAL" or .Severity=="HIGH")
       | "- [ ] \(.VulnerabilityID) \($t) \(.PkgName) \(.InstalledVersion) (fix: \(.FixedVersion // "none"))"' \
   "$WORK/trivy/scan.json" >> "$WORK/findings/triage.md"
```

```bash
# trivy SBOM -> another scanner / an inventory
trivy fs --format cyclonedx -o "$WORK/trivy/sbom.cdx.json" "$TARGET"
trivy sbom -f json -o "$WORK/trivy/sbom-vulns.json" "$WORK/trivy/sbom.cdx.json"
jq -r '.components[] | "\(.name)@\(.version)"' "$WORK/trivy/sbom.cdx.json" | sort -u
```

```bash
# convert a saved report without re-scanning (offline, deterministic)
trivy convert -f sarif  -o "$WORK/trivy/report.sarif"  "$WORK/trivy/scan.json"
trivy convert -f cyclonedx -o "$WORK/trivy/report.cdx" "$WORK/trivy/scan.json"
```

```bash
# trivy tells you which service versions are vulnerable;
# nmap tells you which of your hosts run them
trivy image --image-src remote -f json -o img.json "$AUTHORIZED_IMAGE"
jq -r '.Results[]?.Vulnerabilities[]?.PkgName' img.json | sort -u > "$WORK/trivy/pkgs.txt"
nmap -sV -p "$PORTS" -iL "$WORK/targets.txt" -oX "$WORK/nmap/svc.xml"
```

A directory of repositories scanned with `trivy repo` gives the dependency view
while `trufflehog` gives the history view of the same tree; run both and keep the
reports side by side.

## Limits, failure modes and gotchas

- **There is no Docker socket.** `/var/run/docker.sock` does not exist.
  `trivy image --image-src docker debian:12` fails with `docker error: unable to
  inspect the image (debian:12): failed to connect to the docker API at
  unix:///var/run/docker.sock; check if the path is correct and if the daemon is
  running: dial unix /var/run/docker.sock: connect: no such file or directory`
  and exit 1. The default `--image-src` list (`docker,containerd,podman,remote`)
  falls through to `remote`, so **`trivy image <tag>` does work** for public
  images — it pulls manifests and layers over the network, which means it is
  neither socket-dependent nor offline-capable. `--image-src docker` (explicit)
  proves the socket path is dead; `--input FILE` scans an image tar if one exists.
- **The first scan needs the network.** The DB is 113.92 MiB compressed / 1.4 GB
  on disk, fetched from `mirror.gcr.io` with a `ghcr.io` fallback. On a cold cache
  `--skip-db-update` is fatal (`--skip-db-update cannot be specified on the first
  run`, exit 1). Prime with `--download-db-only`, then re-use the cache.
- **Exclude the cache from whole-filesystem scans.** `trivy rootfs /` without
  `--skip-dirs /root/.cache` spends its time hashing trivy's own 1.4 GB DB; the
  same scan with the cache excluded finished in 8.9 s.
- **Misconfig is not a default scanner.** `trivy fs` defaults to `vuln,secret`;
  add `--scanners misconfig` or use `trivy config`. `--include-non-failures` only
  applies with `misconfig`.
- **`trivy repo` scans files, not history.** A secret that was committed and then
  removed is invisible to it (verified: the repo contained a deleted private key;
  `trivy repo` reported nothing). Use `trufflehog git` for history.
- **Secret rules are pattern-based.** `--scanners secret` without the DB works
  (verified with an empty `--cache-dir`), but it flags example keys too; treat
  every hit as needing confirmation before reporting it as a leak.
- **The licence scanner produced nothing on the fixtures here** (`--scanners
  license`, with and without `--license-full`, reported 0 licences for a pip and
  an npm lockfile). Do not rely on it without validating on the actual target.
- **`--list-all-pkgs` defaults to true**, so JSON reports contain clean packages
  as well; filter with `select(.Vulnerabilities)` when you only want findings.
- **`.Metadata` is null outside image scans.** Scripts that read
  `.Metadata.OS` must handle `fs`, `rootfs`, `repo`, and `sbom` scans.
- **Big reports.** `trivy rootfs /` produced a 23.7 MB JSON with 4598 findings
  (105 CRITICAL, 4277 without a fix) on this image, mostly OS packages and the Go
  binaries that make up the toolchain. Filter before reading; never print it raw.
- **`--timeout` defaults to 5m** and image scans of large images can exceed it;
  raise it explicitly for multi-gigabyte images.
- **`kubernetes` and `vm` are experimental** and need cluster/VM access this
  container does not have.

## Safety and scope

- Confirm the scope with Greg before scanning a repository, image, or filesystem
  that is not part of the current engagement.
- Image scans pull data from third-party registries; only authorized images.
- A report with unpatched, remotely exploitable CVEs is sensitive. Store reports
  in `$WORK`, summarise in the transcript, and do not publish one without asking.
- Secret hits are live credentials until proven otherwise: write the file path and
  rule to the findings note, and let Greg decide on rotation. Never test a found
  credential with this tool.
- Do not "fix" findings by editing targets: this tool reports, it does not
  remediate. Remediation changes are Greg's call.
