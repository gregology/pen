# trivy — worked examples

Every command was run in the agent container and the output shown is real. The
fixture tree used throughout is four files: an npm lockfile, a pip requirements
file, a Dockerfile, and a `.env` with a token and a database URL.

```bash
mkdir -p /tmp/ex && cd /tmp/ex
cat > package-lock.json <<'EOF'
{"name":"t","lockfileVersion":3,"packages":{"":{"name":"t"},"node_modules/lodash":{"version":"4.17.11"},"node_modules/minimist":{"version":"0.0.8"}}}
EOF
printf 'requests==2.19.0\nflask==0.12.2\n' > requirements.txt
printf 'GITHUB_TOKEN=ghp_AbCdEfGhIjKlMnOpQrStUvWxYz0123456789\nDATABASE_URL=postgres://admin:S3cr3tP4ssw0rd@db.internal:5432/appdb\n' > .env
cat > Dockerfile <<'EOF'
FROM debian:12
USER root
EXPOSE 22
EOF
```

## 1. One scan, all three scanners, JSON report

```bash
trivy fs --scanners vuln,misconfig,secret -q -f json -o /tmp/ex/scan.json /tmp/ex
jq -r '.Results[] | "\(.Target)\t\(.Class)\t\(.Type)\tvulns=\(.Vulnerabilities|length)\tmisconf=\(.Misconfigurations|length)\tsecrets=\(.Secrets|length)"' /tmp/ex/scan.json
```

```
package-lock.json	lang-pkgs	npm	vulns=9	misconf=0	secrets=0
requirements.txt	lang-pkgs	pip	vulns=9	misconf=0	secrets=0
Dockerfile	config	dockerfile	vulns=0	misconf=3	secrets=0
.env	secret	null	vulns=0	misconf=0	secrets=1
```

`misconfig` is **not** a default scanner. `trivy fs` alone covers `vuln` and
`secret` only; the Dockerfile row disappears without `--scanners misconfig`.

## 2. Table output for the worst findings

```bash
trivy fs --scanners vuln --severity CRITICAL --ignore-unfixed /tmp/ex
```

```
package-lock.json (npm)
=======================
Total: 2 (CRITICAL: 2)

┌──────────┬────────────────┬──────────┬────────┬───────────────────┬───────────────┬─────────────────────────────┐
│ Library  │ Vulnerability  │ Severity │ Status │ Installed Version │ Fixed Version │            Title            │
├──────────┼────────────────┼──────────┼────────┼───────────────────┼───────────────┼─────────────────────────────┤
│ lodash   │ CVE-2019-10744 │ CRITICAL │ fixed  │ 4.17.11           │ 4.17.12       │ nodejs-lodash: prototype…   │
│ minimist │ CVE-2021-44906 │ CRITICAL │ fixed  │ 0.0.8             │ 1.2.6, 0.2.4  │ minimist: prototype pollu…  │
└──────────┴────────────────┴──────────┴────────┴───────────────────┴───────────────┴─────────────────────────────┘
```

Titles are truncated in table mode. `--ignore-unfixed` keeps only findings with a
released fix, which is what makes a scan actionable.

## 3. Severity histogram and per-class detail from JSON

```bash
jq -r '[.Results[]?.Vulnerabilities[]?.Severity] | group_by(.) | map("\(.[0])=\(length)") | .[]' /tmp/ex/scan.json
```

```
CRITICAL=2
HIGH=7
LOW=1
MEDIUM=8
```

```bash
jq -r '.Results[]? | select(.Misconfigurations) | .Misconfigurations[] | "\(.Severity)\t\(.ID)\t\(.Title)"' /tmp/ex/scan.json
```

```
HIGH	DS-0002	Image user should not be 'root'
MEDIUM	DS-0004	Port 22 exposed
LOW	DS-0026	No HEALTHCHECK defined
```

```bash
jq -r '.Results[]? | select(.Secrets) | .Secrets[] | "\(.Severity)\t\(.RuleID)\t\(.Title)"' /tmp/ex/scan.json
```

```
CRITICAL	github-pat	GitHub Personal Access Token
```

## 4. Secrets only — no vulnerability DB required

```bash
rm -rf /tmp/ex/ec
trivy fs --cache-dir /tmp/ex/ec --scanners secret -q -f json -o /tmp/ex/sec.json /tmp/ex
jq -r '.Results[]? | select(.Secrets) | "\(.Target): \(.Secrets|length) secret(s)"' /tmp/ex/sec.json
```

```
.env: 1 secret(s)
```

This works with a completely empty cache directory, which makes secret scanning
the one trivy mode usable before the 114 MiB DB download.

## 5. Scan the container's own filesystem

```bash
cd /tmp && time trivy rootfs --scanners vuln --skip-dirs /root/.cache --skip-dirs /tmp \
      -q -f json -o /tmp/self.json /
```

```
real	0m8.907s
EXIT=0
```

```bash
jq -r '.ArtifactName, .ArtifactType' /tmp/self.json
jq -r '[.Results[]?.Vulnerabilities[]?]|length' /tmp/self.json
jq -r '[.Results[]?.Vulnerabilities[]?|select(.Severity=="CRITICAL")]|length' /tmp/self.json
jq -r '[.Results[]?.Vulnerabilities[]?|select(.FixedVersion==null or .FixedVersion=="")]|length' /tmp/self.json
```

```
453723d7746d
filesystem
4598
105
4277
```

Sample targets from that report: the container hostname (`os-pkgs`, debian),
`Node.js`, `Python`, and the Go binaries that ship in the image
(`usr/local/bin/dnsx`, `ffuf`, `httpx`, …). `--skip-dirs /root/.cache` is not
optional: without it the same scan runs for tens of minutes re-reading trivy's own
1.4 GB database.

## 6. Scan a public image by tag without a Docker socket

```bash
trivy image --image-src remote --scanners vuln --severity CRITICAL -q debian:12
```

```
Report Summary
┌──────────────────────────┬────────┬─────────────────┐
│          Target          │  Type  │ Vulnerabilities │
├──────────────────────────┼────────┼─────────────────┤
│ debian:12 (debian 12.15) │ debian │        4        │
└──────────────────────────┴────────┴─────────────────┘
```

```bash
trivy image --image-src remote --scanners vuln -q -f json -o /tmp/img.json debian:12
jq -r '.ArtifactName, .ArtifactType, (.Metadata|keys|join(","))' /tmp/img.json
jq -r '[.Results[]?.Vulnerabilities[]?]|length' /tmp/img.json
```

```
debian:12
container_image
DiffIDs,ImageConfig,ImageID,Layers,OS,Reference,RepoDigests,RepoTags,Size
225
```

`Metadata` exists only for image scans. Forcing the socket-backed source shows why
the remote fallback matters:

```bash
trivy image --image-src docker -q debian:12
```

```
FATAL	Fatal error	run error: image scan error: scan error: unable to initialize a scan service:
unable to initialize artifact: unable to initialize container image: unable to find the specified
image "debian:12" in ["docker"]: 1 error occurred:
	* docker error: unable to inspect the image (debian:12): failed to connect to the docker API at
unix:///var/run/docker.sock; check if the path is correct and if the daemon is running:
dial unix /var/run/docker.sock: connect: no such file or directory
```

Exit code 1. The default `--image-src` order (`docker,containerd,podman,remote`)
is why plain `trivy image debian:12` succeeds anyway — over the network.

## 7. SBOM round trip

```bash
trivy fs --scanners vuln -q -f cyclonedx -o /tmp/ex/sbom.cdx.json /tmp/ex
jq -r '.bomFormat, .specVersion, (.components|length)' /tmp/ex/sbom.cdx.json
trivy sbom -q -f json -o /tmp/ex/sbom-vulns.json /tmp/ex/sbom.cdx.json
jq -r '.Results[]? | "\(.Target)\t\(.Class)\t\(.Type)\tvulns=\(.Vulnerabilities|length)"' /tmp/ex/sbom-vulns.json
```

```
CycloneDX
1.7
6
package-lock.json	lang-pkgs	npm	vulns=9
requirements.txt	lang-pkgs	pip	vulns=9
```

## 8. Re-render a saved report without re-scanning

```bash
trivy convert -q -f cyclonedx -o /tmp/ex/conv.json /tmp/ex/scan.json
jq -r '.bomFormat, (.components|length)' /tmp/ex/conv.json
```

```
CycloneDX
6
```

`trivy convert -f sarif|github|spdx-json` does the same for CI formats, entirely
offline, from a report that is already on disk.

## 9. Reproducible offline re-scan

```bash
trivy fs --download-db-only -q                      # one time, ~114 MiB
TRIVY_SKIP_DB_UPDATE=true trivy fs --scanners vuln -q -f json -o /tmp/ex/off.json /tmp/ex
jq -r '[.Results[]?.Vulnerabilities[]?]|length' /tmp/ex/off.json
jq -c . /root/.cache/trivy/db/metadata.json
```

```
18
{"Version":2,"NextUpdate":"2026-09-18T19:08:59.467565106Z","UpdatedAt":"2026-09-17T19:08:59.467565357Z","DownloadedAt":"2026-09-17T20:59:40.47098713Z"}
```

On a cold cache the same flag is fatal, which is the failure to expect when
someone runs an "offline" scan on a fresh container:

```bash
trivy fs --cache-dir /tmp/empty --scanners vuln --skip-db-update /tmp/ex
```

```
FATAL	Fatal error	run error: init error: DB error: database error: --skip-db-update cannot be specified on the first run
```

Exit code 1.

## 10. Exit codes for a pipeline

```bash
trivy fs --scanners vuln --severity CRITICAL --ignore-unfixed --exit-code 1 -q /tmp/ex >/dev/null; echo $?
```

```
1
```

```bash
trivy fs --scanners vuln,secret,misconfig --exit-code 1 -q /tmp/clean >/dev/null; echo $?   # empty dir
```

```
0
```

`--exit-code` counts what survived `--severity` and `--ignore-unfixed`, so it is
only useful as a gate when those filters describe what you actually block on.
