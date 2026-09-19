# jwt_tool — JWT validation, forging, tampering and cracking

jwt_tool takes a JSON Web Token apart: it decodes the header and payload, checks
the signature against a key or a JWKS, cracks an HMAC secret from a dictionary,
tampers with claims, forges tokens for the classic JWT implementation bugs
(`alg:none`, null signature, key confusion, JWKS injection), and — when given a
target URL — replays those forged tokens as real requests and reports what the
server answered. Reach for it when an engagement produces a token and the
question is "what does this application actually check". It is not a token
*acquisition* tool (`oauth2c` gets you a legitimate token), not an API schema
tester (`schemathesis`), and not a general hash cracker (`hashcat`, `john`).

The tool splits cleanly into two halves, and the split is the safety line:

- **Offline**: decode, inspect, tamper, re-sign, crack. Nothing leaves the
  container. No authorization needed beyond handling the token as a credential.
- **Live**: `-t`/`-r` with a token, `-M` scan modes, and the `-X` exploit set
  send forged tokens to a target. That is a real authentication attempt against a
  real system, and it is the half that needs confirmation before it runs.

## Installation and location

| | |
|---|---|
| Version | 2.3.0 (GitHub tag `v2.3.0`; the tool prints `JWT_Tool version 2.3.0` in its banner) |
| Source tree | `/opt/jwt_tool` — `jwt_tool.py` plus the tool's own data files |
| Launcher | `/usr/local/bin/jwt_tool` — a wrapper that `cd`s to `/opt/jwt_tool` and runs the script under the venv interpreter |
| Venv | `/opt/venvs/jwt-tool` (dependencies: `termcolor`, `pycryptodomex`, `requests`, `ratelimit`) |
| Library interpreter | `/opt/venvs/jwt-tool/bin/python3` (bare `python3` is `/opt/py` and has none of jwt_tool's dependencies) |
| Data files | `jwt-common.txt` (common HMAC secrets), `jwks-common.txt`, `common-headers.txt`, `common-payloads.txt` — in `/opt/jwt_tool` |
| Config and logs | a generated `jwtconf.ini` and a `logs.txt`, under the tool's data path (see below) |

jwt_tool is **not on PyPI**. It was installed from the pinned GitHub source
tarball, and its data files are relative paths resolved against the working
directory — which is what the wrapper exists for. Launch it as `jwt_tool`, never
as `python3 /opt/jwt_tool/jwt_tool.py` from an arbitrary directory: the wordlists
(`jwt-common.txt`, `common-headers.txt`, `common-payloads.txt`) are looked up
relative to the current directory.

**Where the config and logs land.** The wrapper `cd`s to `/opt/jwt_tool`, but the
script derives its data path from `~/.jwt_tool` (falling back to the script's own
directory if that cannot be created), so as root the generated `jwtconf.ini` and
the `logs.txt` request log are read from and written to **`/root/.jwt_tool/`**.
This was read from the pinned `v2.3.0` source, not exercised against a running
container — verify with `ls -la /root/.jwt_tool/` after the first run before
relying on a path in a script.

Two first-run behaviours to expect:

- With no config file, the tool prints `No config file yet created. Running
  config setup.`, writes `jwtconf.ini`, prints
  `Configuration file built - review contents of "jwtconf.ini" to customise your
  options.` and **exits 1**. That is one-time setup, not a failure of your
  command.
- Config setup also generates key material into that data path:
  `jwttool_custom_private_RSA.pem`, `jwttool_custom_public_RSA.pem`,
  `jwttool_custom_private_EC.pem`, `jwttool_custom_public_EC.pem` and
  `jwttool_custom_jwks.json`. The RSA and EC private keys live there — treat the
  whole directory as credential material.

If the config's recorded version does not match the script's version, the tool
backs it up as `old_(<version>)_jwtconf.ini`, regenerates it, prints
`Config file showing wrong version` and exits 1. Customisations in the old file
have to be transferred by hand.

## Rules that apply to this tool

1. **Offline work needs no authorization; live work does.** Decoding, tampering,
   re-signing and cracking a token you already hold touches no target. Every
   command with `-t`, `-r`, `-M` or `-X` against a host sends a forged token and
   is an active attack: it needs the target's explicit confirmation for this
   engagement, and it can lock accounts or trip alarms.
2. **A token is a credential.** Treat one found in a scan, a log, a HAR, or a
   proxy capture the way you would treat a password: keep it in a file under
   `$WORK`, never paste it into the transcript, and know that jwt_tool's own
   `logs.txt` writes every token it generates — including forged ones — to disk
   in full.
3. **Never run `-T` or `-I` unattended.** Both open an interactive menu that
   reads from stdin. In a non-interactive shell they block or die. The
   non-interactive path is to pass the claim flags (`-hc`/`-pc`/`-hv`/`-pv`)
   directly.
4. **The exploit set is not a checklist to run in full.** `-X a` through `-X i`
   each send a differently-forged token to the target. `-M at` runs the whole
   playbook, including the weak-secret dictionary and every exploit. Start with
   one specific hypothesis, not `at`.
5. **Bound the request rate.** `-rt` is a per-minute cap; the default is
   effectively unlimited. A fuzzing mode against a live target without `-rt` is a
   burst of authentication attempts.
6. **Evidence goes to `$WORK`, tokens do not go into findings.** Record the log
   ID (`jwttool_<md5>`) and the response code the tool reported; the forged token
   itself belongs in a credential file under `$WORK`, not in the report.
7. **The proxy default is wrong for this container.** `jwtconf.ini` is generated
   with `proxy = 127.0.0.1:8080`, and port 8080 in this namespace is the VPN
   gateway's control API, not a proxy. Any live command that does not pass `-np`
   will try to send its forged token through the gateway's control API. Pass
   `-np`, or set `proxy` to `False` in `jwtconf.ini` (`-np` is the per-request
   form of the same setting).

## Command reference

Complete argument list for v2.3.0. There is no `--version`; `-h` prints the
usage, and the banner carries the version. If a flag is not in this table it does
not exist in the installed build — in particular there is **no `--starttls` and
no `--no-banner`** (those belong to other tools), and no `--quiet`.

Token input and output

| Flag | Meaning |
|---|---|
| `jwt` (positional) | The token to work on. Optional if the token appears in `-rc`/`-rh`/`-pd` or is fetched with `-Q` |
| `-b`, `--bare` | Suppress the banner and colour and print **tokens only** — the flag to use in a pipeline |
| `-Q`, `--query ID` | Look up a `jwttool_…` log ID in the logfile, print that request's details, and use its token as the input |
| `-v`, `--verbose` | More verbose parsing output |

Target and request

| Flag | Meaning |
|---|---|
| `-t`, `--targeturl URL` | Send forged tokens to this URL |
| `-r`, `--request FILE` | Base the request on a raw HTTP request file (request line, headers, then body) |
| `-i`, `--insecure` | Use `http` rather than `https` for a request built from `-r` |
| `-rc`, `--cookies 'k=v; …'` | Cookies to send; the token is substituted where a JWT is found |
| `-rh`, `--headers 'Name: value'` | Headers to send; repeatable |
| `-pd`, `--postdata DATA` | POST body to send |
| `-cv`, `--canaryvalue TEXT` | Text that appears only in a valid response — the reliable success signal |
| `-rt`, `--rate N` | Maximum requests per **minute** |
| `-np`, `--noproxy` | Disable the proxy for this run (see Rules; the generated config points at `127.0.0.1:8080`) |
| `-nr`, `--noredir` | Do not follow redirects for this run |

Scanning modes (live target required)

| Flag | Meaning |
|---|---|
| `-M pb`, `--mode pb` | Playbook audit: the full known-bug sequence |
| `-M er`, `--mode er` | Fuzz **existing** claims in the token to force errors |
| `-M cc`, `--mode cc` | Fuzz **common** claims (`common-payloads.txt`) |
| `-M at`, `--mode at` | All tests: playbook, then error fuzzing, then common claims |

Every mode runs a prescan first: it sends the original token, a token with a
broken signature, and a request with no token at all, then reports whether the
target actually distinguishes them. A run with no `-cv` and identical status
codes for valid and missing tokens stops and asks on stdin
`Do you wish to continue anyway? ("Y" or "N")` — which blocks an unattended run.

Exploits (live target required)

| Flag | Meaning |
|---|---|
| `-X a` | `alg:none` — four case variants (`none`, `None`, `NONE`, `nOnE`) |
| `-X n` | Null signature (empty signature segment) |
| `-X b` | Blank password accepted in the HMAC signature |
| `-X p` | "Psychic signature" accepted in ECDSA (CVE-2022-21449) |
| `-X s` | Spoof JWKS — needs `-ju URL` to point at the JWKS you host |
| `-X k` | Key confusion — sign with the RSA/EC **public** key as the HMAC secret; needs `-pk FILE` |
| `-X i` | Inject an inline JWKS (`jwk` in the token header) |

Signing and claim editing

| Flag | Meaning |
|---|---|
| `-S`, `--sign ALG` | Sign the result: `hs256/hs384/hs512` (needs `-p` or `-kf`), `rs256/rs384/rs512`, `es256/es384/es512`, `ps256/ps384/ps512` (asymmetric ones use `-pr` or the generated key) |
| `-pr`, `--privkey FILE` | Private key for asymmetric signing |
| `-T`, `--tamper` | **Interactive** header/payload editor — reads stdin, see Rules |
| `-I`, `--injectclaims` | Inject claims non-interactively (the unattended path) |
| `-hc`, `--headerclaim NAME` | Header claim to inject or tamper with; repeatable |
| `-pc`, `--payloadclaim NAME` | Payload claim to inject or tamper with; repeatable |
| `-hv`, `--headervalue VALUE` | Value for the matching `-hc`; repeatable. A **path to a file** makes it iterate over the file's lines |
| `-pv`, `--payloadvalue VALUE` | Value for the matching `-pc`; repeatable, same file behaviour |

Cracking and verification

| Flag | Meaning |
|---|---|
| `-C`, `--crack` | Crack the HMAC secret; needs one of `-d`/`-p`/`-kf` |
| `-d`, `--dict FILE` | Dictionary of candidate secrets |
| `-p`, `--password SECRET` | Test a single secret |
| `-kf`, `--keyfile FILE` | Guess the secret from a `kid`-style key file |
| `-V`, `--verify` | Verify an RSA/EC signature; needs `-pk` or `-jw` |
| `-pk`, `--pubkey FILE` | Public key (verification, and the key-confusion exploit) |
| `-jw`, `--jwksfile FILE` | JWKS file: parses it, derives public keys, and verifies the token against each |
| `-ju`, `--jwksurl URL` | URL where you host a spoofed JWKS (with `-X s`) |

## Typical workflows

The worked commands, with expected output and the failures each one produces,
are in [`EXAMPLES.md`](EXAMPLES.md). The outline:

1. **Offline decode and inspection** — read the header and payload, check the
   algorithm and the time claims, with nothing leaving the container.
2. **Offline claim tamper and re-sign** — the non-interactive `-I` path, not
   `-T`.
3. **Crack an HMAC secret** — `-C -d` with a wordlist, and what the "Key not in
   dictionary" message tells you to do next.
4. **Verify against a JWKS** — establish what the server's keys are before
   hypothesising about the token.
5. **`alg:none` against a confirmed target** — one specific exploit, with a
   canary, a rate limit and no proxy.
6. **Read a previous request back out of the log** — `-Q` with a `jwttool_…` ID.

## Output and parsing

- **Banner and colour.** Every run prints a large banner and colourised lines
  unless `-b` is passed. In a pipeline, `-b` is what makes the output parseable.
- **Tokens.** With `-b` and no target, generated tokens are printed one per line
  and that is the whole useful output.
- **Live requests.** Each forged request prints a log ID and the response
  summary, colour-coded by status class:
  `jwttool_<md5> <module> Response Code: <code>, <bytes> bytes`. The log ID is
  the key back into `logs.txt`.
- **Canary.** With `-cv`, a response containing the canary prints
  `[+] FOUND "<value>" in response:` before the summary. That is the only
  unambiguous success signal — status codes alone are not.

```bash
# Bare token output for a pipeline; -b suppresses the banner and colour
jwt_tool -b "$TOKEN" > "$WORK/jwt/token.txt"

# Every generated request, back out of the log (log lives under the data path)
grep -o 'jwttool_[0-9a-f]\{32\}' /root/.jwt_tool/logs.txt | sort -u | head

# Re-read one of them
jwt_tool -Q jwttool_<id> -b
```

`logs.txt` holds each token in full, appended per run. It is a credential store:
check it before handing the container or the workspace to anyone else, and do
not copy it into `$WORK` evidence.

## Chaining with the rest of the toolchain

- **`oauth2c` → jwt_tool.** Obtain a legitimate token, then use jwt_tool offline
  to understand what the application will and will not accept. This is the
  intended order for an authenticated API.
- **mitmproxy → jwt_tool.** A token captured live can be decoded and tampered
  offline; that is the cheapest first step in any JWT engagement.
- **jwt_tool → `hashcat`.** When `-C -d` exhausts a wordlist, the tool prints
  ready-made hashcat invocations for mode `16500` (`-m 16500`), including a rule
  attack and an incremental brute force. Use the exact syntax it prints rather
  than reconstructing it.
- **jwt_tool → schemathesis.** Once a claim mutation is known to be accepted,
  record which claim and which value; the API-schema run then covers the rest of
  the request surface.
- **`-X k` → openssl/JWKS tooling.** Key confusion needs the server's public key;
  if the JWKS is published, `-jw` will parse it and `-V` will confirm you have the
  right one before you attempt the exploit.

## Limits, failure modes and gotchas

- **`-T` and `-I` block on stdin.** They print an interactive menu and wait for a
  selection. In an unattended run the command hangs until something kills it, and
  the "tampering" you think you performed never happened. Use the claim flags
  instead of the menus.
- **`-hv`/`-pv` with a file value fuzzes, it does not set.** If the value happens
  to be a path to an existing file, the tool reads it line by line and generates
  one token per line. For a literal value that is also a filename, that is a
  silent behaviour change.
- **`-I` refuses mismatched claim/value counts.**
  `Amount of header values must match header claims to inject.` (and the payload
  equivalent) means the `-hc`/`-hv` or `-pc`/`-pv` pairs are not one-to-one.
  Supplying only one side prints `Must specify … values to match … claims to
  inject.`
- **First run exits 1 while writing the config.** `createConfig()` ends with
  `exit(1)` after printing the config-built message, so a first invocation looks
  like a failure. Re-run the command.
- **A version mismatch also exits 1.** After a version change the config is
  backed up and regenerated, and any custom proxy/wordlist settings are lost
  until you copy them across.
- **Live work silently uses the wrong proxy.** With the generated
  `proxy = 127.0.0.1:8080`, a forged-token request goes to the VPN gateway's
  control API and comes back 401 or as a proxy error, which reads like the target
  rejecting the token. Pass `-np`.
- **"No substitution occurred"** — `[-] No substitution occurred - check that a
  token is included in a cookie/header in the request` and exit 1 means the
  token in `-rc`/`-rh`/`-pd` was not recognised as a JWT (they are matched by
  their `eyJ…` shape). The request was never sent.
- **Scan modes stop on a canary/status ambiguity.** With no `-cv`, a target that
  answers the same status for valid and missing tokens triggers an interactive
  prompt. Supply `-cv` with something only a logged-in response contains.
- **The original token must keep working.** If the target invalidates the session
  after a forged attempt, the prescan reports
  `Original token not working after invalid submission` and exits; the results
  gathered after that point mean nothing.
- **`-C` only works on HMAC tokens.** For `RS`/`ES`/`PS` the tool says
  `Algorithm is not HMAC-SHA - cannot test against passwords, try the Verify
  function.` and returns without cracking. A non-HMAC token with `-C` is not a
  failed crack, it is the wrong operation.
- **`testKey` refuses anything that is not HS256/384/512** and exits 1 — `-V`
  against an HMAC token is not how you verify it.
- **The wordlist is small.** `jwt-common.txt` is a list of common secrets, not a
  cracking dictionary. Exhausting it quickly is expected, not a negative result.
- **Everything logs.** `logs.txt` accumulates every token the tool has seen or
  generated, with the full command line. Assume anything you run is written down
  in the container.

## Safety and scope

- **Offline operations are the safe default.** Decoding, inspecting, tampering,
  re-signing with your own key, and cracking a token you hold require no target
  contact and no authorization beyond treating the token as a credential. Do the
  offline work first; it usually answers the question without any packets.
- **Every live flag is an attack.** `-t`, `-r`, `-M` and `-X` send forged
  credentials to a real system. They need explicit human confirmation per target,
  and they are loud: failed JWT validation is exactly what an application logs,
  alerts on, and locks accounts over.
- **`-X s` and `-X i` are worse than the others.** JWKS spoofing and inline JWKS
  injection do not just guess — they try to make the target trust a key you
  control. That is a credential-forgery capability; confirm it is in scope before
  it is attempted, and never run it against a system with real users.
- **Do not point `-M at` at production.** It runs the playbook, the weak-secret
  dictionary and every exploit in one pass. If a target is authorized at all,
  start from a single hypothesis with `-rt` set and `-np` on.
- **Treat the outputs as credential material.** `logs.txt`, generated tokens,
  forged tokens, the generated private keys under the tool's data directory, and
  the JWKS you build for `-X s` are all sensitive.
- **Recovering the HMAC secret is a finding, not a licence.** A cracked secret
  lets you mint tokens for that system indefinitely. Report it; do not use it
  beyond the minimum needed to demonstrate the impact that was authorized.
