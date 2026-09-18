# The pentest toolchain

Every tool in the agent image lives in this directory, one subdirectory per
tool. A tool's directory owns **everything about that tool**: the pinned
version, the install steps, and the operator documentation. Nothing about a
tool lives anywhere else in the repository.

This directory is copied into the agent container at `/tools/` (read-only), so
the agent can read its own tool documentation. The `install.sh` files are
excluded from that copy — see *Layout* below.

- Choosing a tool, or asking why one is not here: [`TOOL_RESEARCHING.md`](TOOL_RESEARCHING.md)
- How to add one: this document.

## Layout

```
tools/
  _lib/
    install-helpers.sh        shared build helpers, sourced by every install.sh
    install.sh.template       starting point for a new tool
  <name>/
    install.sh                required — version pin, install, verification
    AGENTS.md                 required — operator documentation
    EXAMPLES.md               optional — worked multi-step workflows
  README.md                   this file
  TOOL_RESEARCHING.md         selection criteria and capability coverage
```

`_lib/install.sh.template` is a template, not a tool: it has no `install.sh`
of its own and is never run.

## In the container

| Path | Contents |
|---|---|
| `/tools/<name>/AGENTS.md` | Operator documentation (everything except `install.sh`) |
| `/opt/py` | General-purpose Python environment; `python3` resolves here |
| `/opt/venvs/<name>` | A Python tool's own virtualenv |
| `/usr/local/bin` | Every tool's console script, symlinked to its venv |
| `/opt/wordlists/current` | SecLists, symlinked to the pinned tag |

## Adding a tool

1. **Decide it belongs.** Run it through the three tests in
   [`TOOL_RESEARCHING.md`](TOOL_RESEARCHING.md): does an existing tool already
   cover the capability, is it maintained, and can it run unattended as root
   with machine-readable output. Adding a tool is a scope decision — per the
   platform's *do not use initiative* principle, confirm the capability with
   Greg before adding the install path.

2. **Create the directory.**

   ```bash
   mkdir tools/<name>
   cp _lib/install.sh.template tools/<name>/install.sh
   $EDITOR tools/<name>/install.sh
   ```

3. **Write `install.sh`.** It must end by proving the tool works — a version
   command, or a parse check for a script-based tool. A build that installs a
   tool that cannot run is worse than a build that fails, because it fails
   silently at engagement time instead.

4. **Write `AGENTS.md`.** Research the tool against its upstream release
   artifact, not its README. The document is for an operator who has not used
   this tool: flags that matter, worked examples, output formats, and the
   failure modes that waste time. See *Documentation standard* below.

5. **Add the two lines to the Dockerfile**, keeping the list alphabetical:

   ```dockerfile
   COPY tools/<name>/install.sh /tmp/install.sh
   RUN bash /tmp/install.sh
   ```

6. **Build and verify** (see *Verifying a change*).

That is the whole change. Nothing else in the repository refers to individual
tools by name.

## The four install shapes

Pick the shape that matches how the tool is distributed. Every script starts
with the same two lines:

```bash
#!/bin/bash
# tools/<name>/install.sh — version pin, install, and verification for <name>.
set -eux -o pipefail

. /tmp/tool-install-helpers.sh
```

### 1. Debian package

```bash
apt_install <name>
"<name>" --version
```

`apt_install` runs `apt-get update`, installs with `--no-install-recommends`,
and clears the apt lists. Debian's version is unpinned — record the version it
currently ships in `AGENTS.md` and re-check it when the tool next changes
behaviour enough to notice.

### 2. Pinned upstream release

```bash
<NAME>_VERSION=1.2.3
<NAME>_SHA256=<sha256 of the release artifact>

fetch "https://github.com/<org>/<repo>/releases/download/v${<NAME>_VERSION}/<artifact>" \
    "$<NAME>_SHA256" /tmp/<name>.zip
unpack /tmp/<name>.zip /tmp/unpack
install_bins /tmp/unpack <name>
rm -f /tmp/<name>.zip
rm -rf /tmp/unpack

<name> --version
```

This is the shape to prefer. These tools sit on the agent's attack surface, so
a silently swapped download is a backdoor in the container that probes Greg's
projects. **Every fetched artifact is hash-verified at build time.** If
upstream publishes no checksum, pin the version tag and say so in a comment
rather than inventing a hash — see `words/install.sh` for that case.

### 3. Python tool with its own virtualenv

```bash
<NAME>_VERSION=1.2.3
<NAME>_VENV=/opt/venvs/<name>

python3 -m venv "$<NAME>_VENV"
"$<NAME>_VENV/bin/pip" install --no-cache-dir --upgrade pip
"$<NAME>_VENV/bin/pip" install --no-cache-dir "<package>==${<NAME>_VERSION}"

expose_venv "$<NAME>_VENV"
<name> --version
```

**One venv per Python tool.** `expose_venv` runs `pip check` and symlinks every
console script into `/usr/local/bin`; because a venv script's shebang is an
absolute path into its own venv, the tool runs under the interpreter its
packages were resolved for, with no `activate` and no PATH manipulation.

This is the point of the layout, not an implementation detail. Shared venvs
force unrelated tools into one dependency resolution, which is why the previous
image carried a comment block explaining that `bcrypt` had to be held below 4.1
for mitmproxy, that `dploot` had to be held below 4 for NetExec, and that
impacket could not be pinned at all because NetExec needed an unreleased
revision. Each of those constraints now lives in the one tool it belongs to.

Give the tool's own constraints to `pip` for **that tool's** packages. A
dependency pin belongs in the `install.sh` of the tool that needs it, with the
observed failure in a comment — not in a shared list.

**Pass a name to `expose_venv` when a console script would shadow a different
tool's binary:**

```bash
expose_venv "$HTTPX_VENV" httpx     # ProjectDiscovery's binary owns `httpx`
```

`expose_venv <venv> <name>...` leaves those names unlinked and prints why. The
intended owner of a binary name is always declared explicitly, never decided by
install order.

**When a tool has no console script** (a library, or a tool you invoke as a
module), expose its interpreter with a shim rather than putting the venv on
PATH:

```bash
cat > /usr/local/bin/scapy <<'EOF'
#!/bin/sh
exec /opt/venvs/scapy/bin/python3 "$@"
EOF
chmod +x /usr/local/bin/scapy
```

### 4. Source tree, script, or data

For a tool that is a plain tree run from its own directory (`testssl.sh`,
`commix`) or data rather than an executable (`words`):

```bash
fetch "<tarball url>" "$SHA256" /tmp/<name>.tar.gz
tar -xzf /tmp/<name>.tar.gz -C /opt
mv "/opt/<name>-${<NAME>_VERSION}" /opt/<name>
chmod +x /opt/<name>/<entrypoint>
ln -s /opt/<name>/<entrypoint> /usr/local/bin/<name>
rm -f /tmp/<name>.tar.gz
```

Install trees under `/opt/<name>`, never into `$HOME`. Take the archive from
upstream, not from PyPI or npm, when the published package under that name is
not the tool — `commix` is the worked example: the PyPI package called `commix`
is an unrelated installer stub that shadows the real scanner.

## Documentation standard

`AGENTS.md` is read by the agent during an engagement and by Greg when
reviewing one. It is not marketing.

Write it from the **release artifact** — the tagged source, the sdist, the
package contents — not from the project's README. READMEs describe the current
release; the image pins an older one. `gobuster` is the worked example: the
image ships 3.5.0, which predates the 3.7 CLI rework, so half the flags in the
current README do not exist. Documenting those would have produced commands
that error at engagement time.

Required sections, in this order: what it is and when to reach for it versus
its neighbours; installation and location; the flags that matter; worked
examples; output formats and how to parse them; failure modes; safety notes.

Rules that have earned their place:

- **Never invent a flag.** If you could not verify it against the pinned
  version, leave it out or label it unverified. A wrong flag costs an
  operator's time or produces a false negative.
- **Record the version you documented.** The reader needs to know which
  release the flags describe.
- **Say what a silent failure looks like.** The valuable entries are the ones
  that describe a tool returning nothing, exiting 0, or reporting success
  while doing nothing — `katana -hl` exiting 0 with "0 endpoints found"
  because the browser never launched, `ffuf` returning no matches because its
  default `-mc` excludes 404, `masscan` returning nothing because it selected
  the interface the kill switch drops.
- **Name the specific failure over the general one.** "TLS verification is
  disabled, so a certificate problem is never reported" beats "use with care".
- **Wordlist paths must exist.** SecLists is pinned at
  `/opt/wordlists/current`. In the 2026.1 tag the old
  `Discovery/Web-Content/directory-list-2.3-small.txt` files were renamed to
  `DirBuster-2007_directory-list-2.3-small.txt`; confirm a path before citing
  it.
- **Close with the safety note.** Which flags are destructive, loud, or need
  authorization. This platform's whole premise is that attack surface is not
  broadened without a human decision; the docs are where that shows up at the
  point of use.

## Verifying a change

```bash
# 1. The scripts parse and the helpers are reachable from a clean shell.
for f in tools/*/install.sh; do bash -n "$f" || echo "SYNTAX: $f"; done

# 2. Every tool has documentation, and every directory with documentation has
#    an install script.
for d in tools/*/; do
  n=$(basename "$d"); [ "$n" = "_lib" ] && continue
  [ -f "$d/install.sh" ] || echo "NO INSTALL: $n"
  [ -f "$d/AGENTS.md" ]  || echo "NO DOCS: $n"
done

# 3. Build the image (context is this directory — no repo-root context needed).
docker build -t pen/agent:test .

# 4. Every tool answers, and the installers did not ship.
docker run --rm pen/agent:test bash -lc '
  for c in nmap nuclei ffuf gobuster httpx nxc arjun wafw00f pypykatz; do
    printf "%-12s %s\n" "$c" "$(command -v "$c" || echo MISSING)"
  done
  find /tools -name install.sh'
# Expected: a path for every tool, and no output from find.

# 5. Python isolation held: the base interpreter cannot see a tool's library.
docker run --rm pen/agent:test bash -lc \
  'python3 -c "import impacket" 2>&1 | tail -1'
# Expected: ModuleNotFoundError — import it from /opt/venvs/impacket/bin/python3.
```

Step 4's `find` is the check that `COPY --exclude` did what it claims, and it is
not optional. The flag fails in two different ways and only one is loud:

- If BuildKit cannot resolve the pinned frontend, the build errors.
- **If the pattern does not match anything, the COPY succeeds and ships every
  installer into the runtime image with no warning.** Verified on host01: a
  bare `--exclude=install.sh` removed none of the 32 installers, and
  `--exclude=**/install.sh` removed all 32. The pattern must be recursive.

Run the `find` after any change to that COPY line, and compare the count of
`AGENTS.md` files (32) against the tool directory count.

## Conventions these docs follow

- Tools are referred to by the command you type, not the project name.
- Commands are complete enough to run: absolute paths for wordlists, `$WORK`
  for outputs, `$TARGET` for the target.
- Where a flag differs between the installed version and current upstream, the
  installed version wins and the discrepancy is called out.
- `EXAMPLES.md` exists only where a multi-step workflow earns the extra file.
  Do not create one to hold a longer flag list.
