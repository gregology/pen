# whatweb — worked workflows

`$TARGET` is an authorised host, `$WORK` the engagement directory. Ruby and the
plugins are already installed. Version note: this is Debian's **whatweb 0.5.5**,
whose flag set differs from current upstream — `--no-cookies`,
`--output-sync` and `--output-buffer-size` do not exist here.

## 1. Profile a site, cheapest useful level first

```bash
mkdir -p "$WORK"

whatweb -a 1 --colour never "https://$TARGET" | tee "$WORK/ww-a1.txt"
```

One request per target. Often enough to see the server, language, CMS and
framework. Read the line as: target, HTTP status, then plugin fields —
`HTTPServer[...]`, `X-Powered-By[...]`, `MetaGenerator[...]`, `Title[...]`,
`IP[...]`, `Country[...]`.

Escalate only where the level-1 result contains something worth versioning:

```bash
grep -Eio 'WordPress|Drupal|Joomla|Jenkins|GitLab|Tomcat|Exchange' "$WORK/ww-a1.txt" | sort -u

whatweb -a 3 -v --colour never "https://$TARGET" --log-json "$WORK/ww-a3.json" -q
jq -r '.[].plugins | to_entries[] | select(.value.version != null)
       | "\(.key)\t\(.value.version | join(","))\tcertainty=\(.value.certainty // 100)"' \
  "$WORK/ww-a3.json"
```

The `jq` line is the deliverable: technology, version, and the plugin's own
certainty. A `certainty` below 100 means the plugin matched a heuristic — check
the `string` field for what it actually saw before reporting the version.

## 2. Bulk fingerprint from an httpx list

```bash
httpx -l "$WORK/hosts.txt" -silent -mc 200,301,403 -o "$WORK/live.txt"
wc -l < "$WORK/live.txt"

whatweb -i "$WORK/live.txt" -a 1 -t 10 --no-errors --colour never \
  --log-json "$WORK/ww-bulk.json" -q

jq 'length' "$WORK/ww-bulk.json"      # compare against wc -l above
```

If the counts differ, hosts failed rather than being bare. Re-run just those
without `--no-errors`:

```bash
comm -23 <(sort -u "$WORK/live.txt") <(jq -r '.[].target' "$WORK/ww-bulk.json" | sort -u) \
  > "$WORK/ww-failed.txt"
whatweb -i "$WORK/ww-failed.txt" -a 1 --colour never 2>&1 | head -20
```

## 3. Build the technology inventory table

```bash
jq -r '.[] | .target as $t | .plugins | keys[] | [., $t] | @tsv' "$WORK/ww-bulk.json" \
  > "$WORK/ww-tech.tsv"

# most common technologies and how many hosts run each
cut -f1 "$WORK/ww-tech.tsv" | sort | uniq -c | sort -rn | head -25

# one host's full stack, readable
awk -F'\t' -v h="https://$TARGET" '$2==h {print $1}' "$WORK/ww-tech.tsv" | sort -u
```

This table decides the next phase: a host running Tomcat and Struts goes to the
relevant nuclei templates; WordPress plus an outdated PHP gets the CMS checks; a
host whose only technology is `HTTPServer[nginx]` is a custom app and needs
content discovery instead.

## 4. Version harvesting for CVE lookup

```bash
jq -r '.[] | .target as $t | .plugins | to_entries[]
       | select(.value.version != null)
       | [$t, .key, (.value.version | join(", ")), ((.value.string // []) | join("; "))]
       | @tsv' "$WORK/ww-bulk.json" > "$WORK/ww-versions.tsv"
column -t -s $'\t' "$WORK/ww-versions.tsv" | head -40
```

The fourth column is what the plugin actually matched — quote it in the finding,
because it is the difference between "the version is 6.4.3" and "a meta tag said
6.4.3". Verify any version that gates a CVE claim against the application itself
before reporting it.

## 5. WAF-aware escalation

```bash
wafw00f "https://$TARGET" -a -f json -o "$WORK/waf.json"
if jq -e '.[] | select(.detected == true)' "$WORK/waf.json" >/dev/null; then
  whatweb -a 1 -t 3 --wait 1 --colour never "https://$TARGET" --log-json "$WORK/ww.json" -q
else
  whatweb -a 3 -t 10 --colour never "https://$TARGET" --log-json "$WORK/ww.json" -q
fi
```

Behind a WAF, aggression 3's follow-up requests are the ones most likely to be
challenged; start at level 1 with low threads. whatweb names some WAFs itself,
but a negative from whatweb is not a negative — wafw00f actively probes and is
the authority here.

## 6. Authenticated and cookie-carrying scans

```bash
# basic auth
whatweb -a 3 -u "admin:$PASS" --colour never "https://$TARGET/admin" \
  --log-json "$WORK/ww-admin.json" -q

# form login: log in with curl, keep the cookie jar, replay it
curl -sk -c "$WORK/cookies.txt" -d "user=admin&pass=$PASS" "https://$TARGET/login" -o /dev/null
whatweb -a 3 --cookie-jar "$WORK/cookies.txt" --colour never "https://$TARGET/dashboard" \
  --log-json "$WORK/ww-dash.json" -q

jq -r '.[].plugins | keys[]' "$WORK/ww-dash.json" | sort -u
```

Without credentials whatweb fingerprints the login page, which is usually a
stripped-down stack. Compare the authenticated and unauthenticated key sets — the
difference is the application itself.

## 7. Targeted plugin runs and one-off signatures

```bash
whatweb -I wordpress                     # what the plugin looks for
whatweb -I java,server | head -40        # search by keyword
whatweb -a 3 -p WordPress,PHP,Apache --colour never "https://$TARGET" \
  --log-json "$WORK/ww-wp.json" -q

whatweb --custom-plugin ':text=>"internal build"' --colour never "https://$TARGET"
whatweb --custom-plugin ':version=>/build [0-9.]+/' -a 1 --colour never "https://$TARGET"
```

`-p` with explicit names is the cheapest reliable scan: a handful of requests, no
breadth, high signal. `--custom-plugin` is for a string that matters to this
engagement only, without writing a Ruby plugin.

## 8. Evidence and reproducibility

```bash
{
  echo "# whatweb $(whatweb --version) — $(date -Is)"
  echo "target: https://$TARGET  aggression: 3  threads: 5"
  jq -r '.[] | .plugins | to_entries[]
         | "\(.key): \((.value.version // .value.string // []) | join(","))"' \
    "$WORK/ww-a3.json"
} >> "$WORK/notes.md"
```

whatweb's version, the aggression level and the thread count belong in the note:
the same command at aggression 4 against the same host produces a different,
larger result set, and a reader cannot tell which one you ran from the output
alone. Fresh filename per run — `--log-json` appends, so reusing one produces a
file that `jq` cannot parse.
