# commix — OS command-injection scanner

commix injects shell metacharacters into parameters, request bodies and headers
and reports where a command's output, timing or exit status changes the
response. It is the only tool in the toolchain for OS command injection — a bug
class none of the other scanners cover, and the highest-impact one for code
paths that shell out.

## Install and location

| | |
|---|---|
| Version | 4.1 (upstream release, sha256-verified at image build) |
| Install root | `/opt/commix` (a plain Python tree, run from its own directory) |
| Entry point | `/usr/local/bin/commix` → `/opt/commix/commix.py` |

**commix is deliberately not installed from PyPI.** The package published there
under the name `commix` is an unrelated installer stub — a ~180-line bash script
by a different author that shadows the real tool and, when run with no
arguments, clones and executes code from the internet. The upstream release is
the only source of the real scanner. `install.sh` verifies that the entry point
parses before the build is allowed to succeed.

## Rules that apply to this tool

1. **Authorization first, and it is a higher bar than for scanners.** commix
   does not merely probe: injected commands *execute on the target host*. A
   payload that runs `id` proves code execution; a mis-aimed one can modify or
   delete data. Confirm the target, the parameter and the payload class with
   Greg before the first request.
2. **Egress is the tunnel.** All traffic leaves through the WireGuard interface
   in the shared network namespace. commix's own proxy option is not a
   containment mechanism.
3. **Keep the request rate low.** commix makes many requests per parameter, and
   against a target that shells out (mesh/VPN tooling, anything calling `ip` or
   `wg`) a burst is an availability risk, not just noise.
4. **Benign payloads only unless told otherwise.** Time-based and output-based
   detection prove the same thing as a reverse shell without establishing one.
   Do not escalate to a callback or an interactive shell without a separate,
   explicit decision.
5. **Evidence into `$WORK`.** Record the exact command line, the parameter, and
   the request that demonstrated injection — not just the tool's summary line.

## Flag reference

**This section is deliberately thin, and that is the honest state.** The image
previously carried only the PyPI stub, so no commix flag could ever be verified
against a working binary in this container. Now that the real 4.1 tree is
installed, run the help output before relying on any flag:

```bash
commix --help
```

Treat any flag list copied from upstream documentation or a blog post as
unverified until it appears in that output — the version installed here is
pinned, and the project's CLI has changed across releases. Per the documentation
standard in [`../README.md`](../README.md), an unverified flag list is worse than
no flag list, because it produces commands that error at engagement time.

The invocation shape, which is stable across releases:

```bash
commix --url="https://target.example/item?id=1" --batch --ignore-stdin
```

`--ignore-stdin` is required in the agent's shell, which is not a TTY: without
it commix prints `[info] Using 'stdin' for parsing targets list.` and exits 0
without testing `--url`. It is `help=SUPPRESS` upstream in 4.1, so `-h` does not
list it.

## Failure modes

- **Exit status proves nothing.** An unrecognised option prints an error and
  still exits **0**: `commix --os-shell` and `commix --definitely-not-a-flag`
  both do this, as did the stub the real tool replaced (`Error: Type '-h' for
  Help !`, exit **0**). Read the output; do not branch on `$?`.
- **A non-TTY run without `--ignore-stdin` tests nothing.** commix prints
  `[info] Using 'stdin' for parsing targets list.` and exits 0 without touching
  `--url`, so the run looks successful and has tested nothing. Pass
  `--ignore-stdin` in every agent-shell invocation.
- **Detection is heuristic and confirmation-heavy.** A reported injection point
  should be reproduced by hand (a `sleep` delay, a reflected marker) before it
  enters a findings note.
- **The target may be stateful.** Injected commands run in the target's
  environment; a payload that writes a file, kills a process or restarts a
  service leaves the engagement with a mess to clean up.
- **No injection found is not proof of safety.** commix tests the parameters
  and techniques it knows; blind or filtered injection can be missed. Say
  "not detected by commix" rather than "not vulnerable".

## Chaining with the rest of the toolchain

- **arjun → commix.** `arjun -u "$URL" -oJ params.json` produces exactly the
  parameter list commix needs; without it, commix is guessing.
- **katana → commix.** Crawled URLs with parameters are the input set.
- **nuclei** covers published command-injection CVEs; commix covers the
  application-specific case nuclei has no template for. Run both rather than
  treating either as complete.
- **ffuf** is the cheaper first pass for confirming that a parameter reflects
  or changes behaviour, before commix spends requests on payload classes.

## Safety

Never run without explicit human confirmation per target:

- any target not confirmed for destructive testing — injected commands execute
  on the target host, and "read-only payload" is a convention, not a guarantee;
- `--os-cmd` (pseudo-terminal on the target) or `--alter-shell` (forces the
  shell used for injection), reverse-shell or callback payloads, which
  establish access rather than demonstrating a bug;
- authenticated testing, which acts as that user and can write state;
- raising concurrency or removing delays on a service that serves real users.
