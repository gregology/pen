# commix

`commix` is the toolchain's OS command-injection scanner: it injects shell
metacharacters into parameters, request bodies and headers and reports where a
command's output, timing or exit status changes the response. It is the only
planned tool for that bug class.

**It is not installed in this image.** The name on `PATH` is a different PyPI
package (a shell installer stub), so no command-injection scanning is currently
possible. Read this file before attempting to use the name.

## Installation and location

| Item | Value |
|---|---|
| Expected | commix 4.1, upstream `commixproject/commix` |
| Actually installed | `/opt/pen-venv/bin/commix` — a ~180-line bash script, PyPI package `commix` **0.1**, author `Parixit Sutariya`, home page `https://github.com/Bhai4You/` |
| Python module | none: `python3 -c "import commix"` → `ModuleNotFoundError: No module named 'commix'` |
| Package metadata | `/opt/pen-venv/lib/python3.11/site-packages/commix-0.1.dist-info/`; its `Metadata` summary claims "Automated All-in-One OS Command Injection Exploitation Tool" |
| Filesystem search | `find / -iname '*commix*'` finds only this stub, its `dist-info`, and `/opt/wordlists/SecLists/Fuzzing/command-injection-commix.txt` |
| Other root | none: there is no `/opt/commix`, no `commix.py`, and no `python3-commix` package |

The cause is in the image build: the venv install lists `commix` on PyPI
(`images/agent/Dockerfile`), and the upstream commix project does not publish
that tool under that name. PyPI's `commix` is unrelated. This is a supply-chain
finding as much as a missing-tool finding: an unvetted third-party package is
installed in the image and answers to the same name as a pentest tool.

## Rules that apply to this tool

1. **Do not run bare `commix`, and do not run `commix -i`.** Both fall through
   to the stub's `install()` function, which does `cd $HOME; git clone
   https://github.com/commixproject/commix` and then executes the cloned code.
   That is an unpinned, unaudited download from the internet at runtime, outside
   the image build, which this platform does not do. Source-verified at
   `/opt/pen-venv/bin/commix` lines 106-143 (`git clone $url`, `script="python
   commix.py -h"`); not executed during verification.
2. **Do not present command-injection results.** With this image there is no
   tool that can produce them. A fabricated or inferred "likely injectable"
   claim is worse than a gap.
3. **Report the defect rather than working around it.** Installing commix at
   runtime (pip, git, curl) contradicts the project's rule that tools arrive
   through the image build. The fix is a Dockerfile change plus an image rebuild.
4. **Authorization still applies to the capability, not the binary.** If a real
   commix is added, it is one of the most invasive tools in the set: injected
   commands execute on the target host. It needs explicit confirmation per
   target, a low request rate, and benign payloads only.
5. **Keep the evidence honest.** A "no command injection found" statement may
   only come from a tool that ran. In this image, the correct statement is
   "not tested: commix is not installed".

## Command reference

There is no commix command reference to document, because the real binary is not
present. What the name actually does (all verified):

| Invocation | Result |
|---|---|
| `commix -h` | Prints the stub's installer help: `Syntax: commix [-h\|i\|a\|r\|v]` with `-i` install, `-h` help, `-v` version, `-a` about, `-r` delete. Prints `TERM environment variable not set.` when `TERM` is unset, then a "Termux Detective" banner |
| `commix -v` | Prints `Version : 0.1` (the stub's own version), exit 0 |
| `commix -a` | Prints the stub author's details (`github.com/Bhai4You`, `bhai4you.blogspot.com`), exit 0 |
| `commix --version` | `Error: Type '-h' for Help !` |
| `commix --help` | `Error: Type '-h' for Help !` |
| `commix --url="http://target/?q=1" --batch` | `Error: Type '-h' for Help !` — every real commix flag is an "invalid option" to the stub's `getopts ":hiarvs"` loop |
| `commix` (no arguments) | Falls into `install()`: clones the real commix into `$HOME` and runs `python commix.py -h`. **Do not run this** |

None of the real tool's flags (`--url`, `--batch`, `--level`, `--risk`,
`--data`, `-r`, `--output-dir`, …) could be verified in this container, because
the binary that implements them is absent. This documentation deliberately does
not list them: an unverified flag list is the failure mode these docs exist to
prevent.

## Typical workflows

There are none that work. The workflow for now is detection and escalation:

1. **Confirm the state of the tool before planning any injection test.**

   ```bash
   command -v commix                                   # /opt/pen-venv/bin/commix
   head -3 /opt/pen-venv/bin/commix                    # #!/bin/bash, not python
   pip show commix 2>/dev/null | head -4               # Version: 0.1, Home-page: github.com/Bhai4You
   python3 -c "import commix" 2>&1 | tail -1           # ModuleNotFoundError
   ```

2. **Record the gap in the findings note** with those four outputs as evidence,
   and state that OS command injection was **not** tested.

3. **Use the alternatives that do exist** while the image is unfixed: nuclei
   templates for known command-injection CVEs, and manual `curl`/Burp-style
   probing of a suspected parameter (time-based `sleep` and OOB callbacks are
   the same technique a scanner automates; a manual probe is authorized work,
   it just is not commix).

4. **Escalate the fix**: replace the `commix` line in the venv install with the
   pinned upstream release (or a `git clone --branch 4.1` during the image
   build), expose it as a `commix` entry point, and rebuild the image through
   the normal host-build procedure.

## Output and parsing

Nothing to parse: the stub writes no report file, has no JSON output, and its
only stdout is the installer help/about text. Any `--output-dir`-style flag from
the real tool is rejected before it runs.

If commix is added later, plan for its report file the way the upstream tool
writes it (a `commix --output-dir` directory plus its own log), and verify the
flag against the installed binary before documenting it here.

## Chaining with the rest of the toolchain

- **nuclei** is the current substitute for known-CVE command injection:
  `nuclei -u https://$TARGET -t http/cves/ -jsonl` still covers published
  command-injection issues.
- A parameter list from **arjun** or **ffuf** is exactly what a real commix run
  would consume: `arjun -u "$URL" -oJ params.json` then feed the discovered
  parameter names to the injection tool once one exists.
- Do not put the stub in a pipeline: `commix … | jq` produces the
  `Error: Type '-h' for Help !` line, which a careless parser will happily treat
  as an empty result set.

## Limits, failure modes and gotchas

- **The failure is silent-ish and easy to misread.** `commix --url=… --batch`
  prints a single line, `Error: Type '-h' for Help !`, and (verified) exits
  **0**. A script that checks only the exit code will record success.
- **`-h` tells you it is the wrong tool, if you read it.** The help text
  advertises `[-h|i|a|r|v]` and "Install commix", not a scanner's flag list.
  `TERM environment variable not set.` is another tell: the stub calls `clear`
  and `logo`.
- **No TTY is required to get the stub's help** (it prints fine with `TERM`
  unset or set), so this is not one of the "needs a TTY" tools — it simply is
  not the tool.
- **Dependency and provenance risk.** The stub was installed as a Python
  package but is a bash script; it installs further software with `pkg install`
  / `pip install lolcat` and clones from GitHub when run. Nothing in this image
  should do that, and the package's version (`0.1`) and author do not match the
  upstream project (`commixproject`, 4.1). Treat the package as untrusted.
- **`find` is the fastest check.** `/opt/wordlists/SecLists/Fuzzing/
  command-injection-commix.txt` is a payload list, not the tool — do not
  mistake it for an installation.

## Safety and scope

- **Do not execute the stub's install path** (`commix` with no args, or
  `commix -i`): it downloads and runs remote code, which is an egress and
  supply-chain action requiring explicit human confirmation and, in this
  platform, a change to the image build instead.
- **Do not attempt command-injection tests** — with any tool — against a target
  that is not explicitly confirmed for destructive testing. Injected commands
  execute on the target host; "read-only" payloads are a convention, not a
  guarantee (a payload that runs `id` still proves code execution, and a
  mis-aimed one can modify or delete data).
- **Report the missing tool to Greg** as an image defect alongside any
  engagement findings, so the gap is visible in the platform's own record and
  not just in the conversation.
