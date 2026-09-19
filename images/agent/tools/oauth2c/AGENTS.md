# oauth2c — OAuth2/OIDC token acquisition

oauth2c talks to an OAuth2 or OpenID Connect issuer and comes back with a real
token. It exists in this image to solve one problem for the other tools: almost
every interesting API needs a bearer token, and `schemathesis`, `arjun`, `ffuf`,
`nuclei` and `jwt_tool` all assume you already have one. Reach for it first in an
authenticated engagement, against an issuer Greg has confirmed, to turn a client
registration and a grant into `$TOKEN`. It is not an OAuth misconfiguration
scanner (that is what the platform's manual OIDC checks are for), not a JWT
tamperer (`jwt_tool`), and not a session brute-forcer.

It performs the issuer's discovery, drives the chosen grant, and prints the
resulting tokens. In this container it is the only tool that knows how to walk
an authorization-code or device flow end to end.

## Installation and location

| | |
|---|---|
| Version | 1.21.0 (`oauth2c version` prints `oauth2c version 1.21.0 (…)`) |
| Binary | `/usr/local/bin/oauth2c` — pinned static Go release, no libc dependency |
| Config | none on disk; all parameters are flags |
| Subcommands | `version`, `docs`, `help`, `completion` |
| Usage | `oauth2c [issuer url] [flags]` |

The binary is the upstream release artifact for v1.21.0, hash-verified at build
time. The issuer URL is positional. `oauth2c docs` prints the generated CLI
documentation; `oauth2c [issuer url] --help` is the authoritative flag list for
the installed build.

## Rules that apply to this tool

1. **Authorization first.** Registering a client, driving a flow, or replaying a
   stolen refresh token against an issuer is an authentication attempt against a
   real system. The issuer must be in scope for the engagement. A discovery
   document being reachable is not authorization to use it.
2. **The token that comes back is a credential.** It carries whatever the grant
   authorized, for as long as the issuer says. Keep it in a variable or a file
   under `$WORK` with restrictive permissions, never in the transcript, and
   never in a findings document. Prefer short-lived tokens for testing.
3. **`--client-secret` on the command line lands in shell history and in process
   listings.** Anyone who can read `/proc` or the shell history of this container
   gets the secret. Pass it through the environment where the tool supports it,
   or accept that the secret is exposed for the duration of the run and rotate it
   afterwards. Never put a live secret in a command you paste into the
   transcript.
4. **A real browser is not available.** There is no display in this container, so
   the authorization-code grant must be told not to try: pass `--no-browser` and
   complete the URL by hand, or use the device grant and approve on another
   device. A command that opens a browser here hangs or fails.
5. **Client-credentials is the unattended grant.** It needs no human, which also
   means it can be run by accident at scale. Confirm the client's scope before
   using it, and check which token you actually got (`scope`, `aud`, `exp`)
   before handing it to another tool.
6. **Tokens go into other tools, not into reports.** Hand `$TOKEN` to
   `schemathesis --header`, `arjun --headers`, `ffuf -H`, or `mitmproxy`; record
   only the *fact* that a token was obtained, its issuer, its scope and its
   expiry, never the token value.
7. **Acquiring a token with stolen or guessed credentials is out of scope**
   unless the engagement explicitly says otherwise in writing — at which point
   the credential source, not this tool, is the finding.

## Command reference

Flags verified against the v1.21.0 binary. This is a subset of the full flag
set: only the options relevant to obtaining a token in this container are
documented, and anything absent here should be checked with
`oauth2c --help` before use rather than assumed.

Client identity and grant

| Flag | Meaning |
|---|---|
| `--grant-type TYPE` | Which grant to run (values below) |
| `--auth-method METHOD` | Token-endpoint client authentication method (values below) |
| `--client-id ID` | Client identifier |
| `--client-secret SECRET` | Client secret — see the warning under *Rules* |
| `--audience AUD` | Requested audience (repeatable) |
| `--assertion CLAIMS` | Claims for a JWT bearer assertion |
| `--assertion-jwt JWT` | Pre-signed JWT assertion, passed through as-is |
| `--dpop` | Use DPoP (demonstrating proof-of-possession) |
| `--http-timeout DURATION` | HTTP client timeout |

`--grant-type` accepts, in the pinned binary: `authorization_code`,
`client_credentials`, `password`, `refresh_token`,
`urn:ietf:params:oauth:grant-type:jwt-bearer`,
`urn:ietf:params:oauth:grant-type:token-exchange`,
`urn:ietf:params:oauth:grant-type:device_code`. An unrecognised value is
rejected before any request is made.

`--auth-method` accepts: `client_secret_basic`, `client_secret_post`,
`client_secret_jwt`, `private_key_jwt`, `self_signed_tls_client_auth`,
`tls_client_auth`, `none`.

Endpoints and redirect

| Flag | Meaning |
|---|---|
| `--authorization-endpoint URL` | Override the discovered authorization endpoint |
| `--device-authorization-endpoint URL` | Override the discovered device authorization endpoint |
| `--mtls-token-endpoint URL` | mTLS-bound token endpoint |
| `--mtls-pushed-authorization-request-endpoint URL` | mTLS-bound PAR endpoint |
| `--callback-addr ADDR` | Callback server bind address, e.g. `0.0.0.0:9876` |
| `--callback-tls-cert FILE` / `--callback-tls-key FILE` | TLS for the callback listener |

Interactive-flow control (the flags that matter here)

| Flag | Meaning |
|---|---|
| `--no-browser` | Do not try to open a browser — **mandatory in this container** for the authorization-code grant |
| `--browser-timeout DURATION` | How long to wait for the browser step |
| `--no-origin` | Do not send an `Origin` header |
| `--login-hint HINT` | User identifier hint to the issuer |
| `--idp-hint HINT` | Identity provider hint |
| `--acr-values VALUE` | Requested ACR values (repeatable) |
| `--max-age SECONDS` | Maximum authentication age |
| `--id-token-hint TOKEN` | `id_token_hint` for the authorization request |
| `--authentication-code CODE` | Authentication code for passwordless authentication |
| `--claims CLAIMS` | Requested claims |
| `--actor-token TOKEN` / `--actor-token-type TYPE` | Acting-party token for token exchange |
| `--encrypted-request-object` / `--encryption-key KEY` | Send request parameters as an encrypted JWT, with the given JWKS key |
| `--insecure` | Allow insecure connections — a deliberate downgrade |

## Typical workflows

1. **Confirm the binary and the issuer's discovery document.**

   ```bash
   oauth2c version
   curl -s "https://$TARGET/.well-known/openid-configuration" | jq '{issuer, token_endpoint, device_authorization_endpoint, grant_types_supported}'
   ```

   If `grant_types_supported` does not list the grant you intend to use, the flow
   will fail at the token endpoint no matter how the flags are set. A local
   issuer fixture for a discovery check belongs on loopback port **8090** — port
   8080 is the VPN gateway's control API in this container and answers 401.

2. **Client-credentials — the unattended path.** This is the grant to use when
   the engagement provides a machine client:

   ```bash
   TOKEN=$(oauth2c "https://$TARGET" \
     --grant-type client_credentials \
     --auth-method client_secret_basic \
     --client-id "$CLIENT_ID" --client-secret "$CLIENT_SECRET" \
     2>/dev/null | jq -r '.access_token')
   test -n "$TOKEN" && test "$TOKEN" != null || echo "NO TOKEN"
   ```

   The `test` is the point: an empty or null `$TOKEN` handed to the next tool
   produces a wall of 401s that look like a target problem. Scopes are requested
   with `--scopes` — verified present in the v1.21.0 binary but outside the
   documented subset above, so confirm it with `oauth2c --help` before relying on
   it in a saved command.

3. **Authorization-code with no browser.** The tool cannot open a browser here;
   print the URL, complete it on a machine that has one, and let the callback
   come back to this container:

   ```bash
   oauth2c "https://$TARGET" \
     --grant-type authorization_code \
     --client-id "$CLIENT_ID" --client-secret "$CLIENT_SECRET" \
     --callback-addr 0.0.0.0:9876 --no-browser
   ```

   An `--insecure` issuer with a self-signed certificate is the case `--insecure`
   exists for; using it on a valid certificate silently accepts a MITM.

4. **Device grant — the interactive-free-ish path.** It needs no browser on this
   host, but it still needs a human to approve the code on another device, so it
   is not unattended:

   ```bash
   oauth2c "https://$TARGET" \
     --grant-type urn:ietf:params:oauth:grant-type:device_code \
     --client-id "$CLIENT_ID"
   ```

5. **Refresh an existing token.** The refresh token is credential material —
   keep it in `$WORK`, not in the transcript. `--refresh-token` is verified
   present in the v1.21.0 binary but sits outside the documented subset above,
   so confirm it with `oauth2c --help` before saving the command:

   ```bash
   oauth2c "https://$TARGET" --grant-type refresh_token \
     --client-id "$CLIENT_ID" --client-secret "$CLIENT_SECRET" \
     --refresh-token "$(cat "$WORK/oauth/refresh_token")"
   ```

6. **Hand the token to the API tools.** The scope check comes first, because a
   token with the wrong audience fails in a way that looks like a target defect:

   ```bash
   TOKEN=$(oauth2c "https://$TARGET" --grant-type client_credentials \
     --client-id "$CLIENT_ID" --client-secret "$CLIENT_SECRET" | jq -r '.access_token')
   echo "$TOKEN" | cut -d. -f2 | base64 -d 2>/dev/null | jq '{scope, aud, exp}'
   schemathesis run "https://$TARGET/openapi.json" \
     --header "Authorization: Bearer $TOKEN" --rate-limit 30/m --max-time 300
   ```

## Output and parsing

The token response is printed — either a JSON object in the standard OAuth2
token-response shape (`access_token`, `token_type`, `expires_in`, and for OIDC
`id_token`), or for the flows that need human interaction, the URL to visit
followed by the result once the flow completes. Whether the JSON is the only
thing on stdout in every flow, and the exact shape of the interactive prompts, is
**unverified** here: no live issuer was available to exercise the flows while
this document was written.

Treat every parse as a check, not an assumption:

```bash
oauth2c "https://$TARGET" --grant-type client_credentials \
  --client-id "$CLIENT_ID" --client-secret "$CLIENT_SECRET" \
  > "$WORK/oauth/token.json" 2> "$WORK/oauth/token.err"
jq -e '.access_token' "$WORK/oauth/token.json" >/dev/null || { echo "no access_token"; cat "$WORK/oauth/token.err"; }
```

`id_token` is a JWT and can be inspected with `jwt_tool` — decode it, do not
paste it. The token file under `$WORK` is credential material: delete it when
the engagement closes, and never let it into a findings document.

## Chaining with the rest of the toolchain

- **oauth2c → schemathesis.** `--header "Authorization: Bearer $TOKEN"` turns a
  wall of 401s into a real schema-conformance run. This is the primary reason
  the tool is in the image.
- **oauth2c → arjun / ffuf / httpx / nuclei.** Each takes headers; each will
  otherwise test the login page and report nothing. Prefer the tool's own
  credential input over the command line where it has one.
- **oauth2c → jwt_tool.** A real token is the input `jwt_tool` needs for its
  claim tampering and cracking work.
- **oauth2c ↔ mitmproxy.** Run the flow through mitmproxy when you need to see
  exactly what the issuer and the client exchanged — useful when discovery or
  client authentication behaves differently than the flags suggest.
- **Upstream in the chain:** the client registration and its secret are an
  engagement input, not something this tool discovers. If the scope of that
  client is broader than the test needs, say so before using it.

## Limits, failure modes and gotchas

- **There is no browser.** Any flow that tries to open one fails here. Pass
  `--no-browser` for authorization-code; the device grant is the alternative and
  still requires a human on another device.
- **`--client-secret` is visible in the process table and shell history.** This
  is the failure mode that leaks a credential without any error message. Prefer
  another credential input where the tool offers one, and rotate the secret after
  a run that used the command line.
- **Discovery failures look like flag failures.** A wrong issuer URL, an
  unreachable `.well-known` document, or a proxy in the way produces an error
  about endpoints, not about the network. Check discovery with `curl` before
  debugging flags.
- **A wrong `--auth-method` produces a 401 from the token endpoint** even though
  the client id and secret are correct. `client_secret_basic` and
  `client_secret_post` are different registrations; use the one the client was
  registered with.
- **`--insecure` turns TLS verification off.** Against a self-signed issuer it is
  necessary; against a valid certificate it silently accepts an interception. Do
  not leave it in a saved command line.
- **A token that "works" may be the wrong token.** Client-credentials tokens are
  issued for a client, not a user; an audience or scope mismatch surfaces later
  as a 403 from the API, which reads like an authorization finding. Decode the
  token and check `scope`, `aud` and `exp` before drawing conclusions.
- **The grant name for device and token exchange is a full URN.** `--grant-type
  device_code` is rejected — the accepted value is
  `urn:ietf:params:oauth:grant-type:device_code`.
- **Whether the token JSON is the only stdout content in interactive flows is
  unverified.** Redirect stdout to a file and validate before piping into `jq`;
  a prompt on stdout makes `jq` fail on a run that actually succeeded.

## Safety and scope

- **Confirm the issuer and the client registration with Greg before the first
  request.** Which issuer, which client, which scopes, and which grant are all
  scope decisions; a token minted with broader scope than the test needs is a
  scope expansion even if nothing is attacked with it.
- **Token acquisition is an authentication attempt.** Failed logins can lock
  accounts, trip alarms, and appear in the issuer's logs as an attack. Do not
  drive password or refresh-token grants against a production identity provider
  without explicit approval.
- **Never paste a live token into the transcript.** Write it to `$WORK`, use it
  from there, and delete it at the end of the engagement.
- **Do not use stolen credentials.** If the credential was not issued for this
  engagement, obtaining a token with it is out of scope unless the engagement
  says otherwise in writing.
- **Token lifetime is part of the plan.** Prefer the shortest-lived token the
  issuer will issue, and re-acquire rather than caching one in a shell profile
  or an environment file that outlives the engagement.
