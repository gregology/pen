# katana — worked examples

Every command below was run in the agent container as root, against a local
fixture and the authorized public hosts. Output shown is real, trimmed where
marked.

```bash
export WORK=/working/engagements/example
mkdir -p "$WORK"
```

## 1. A fixture worth crawling

```bash
mkdir -p /tmp/site/sub
cat > /tmp/site/index.html <<'EOF'
<html><head><title>Pen Fixture Home</title></head><body>
<a href="/page1.html">one</a>
<a href="/sub/page2.html">two</a>
<script src="/app.js"></script>
</body></html>
EOF
printf '<html><head><title>Page One</title></head><body><a href="/">home</a></body></html>' > /tmp/site/page1.html
printf '<html><head><title>Page Two</title></head><body><a href="/index.html">home</a></body></html>' > /tmp/site/sub/page2.html
printf 'var api = "/api/v1/items";\nfunction go(){ fetch("/api/v1/items?debug=1"); }\n' > /tmp/site/app.js
cd /tmp/site && python3 -m http.server 8099 --bind 127.0.0.1 &
sleep 2
curl -s -o /dev/null -w 'status=%{http_code}\n' http://127.0.0.1:8099/
```

## 2. Map the URL surface

```bash
katana -u http://127.0.0.1:8099 -d 2 -silent -nc -duc -o "$WORK/katana-urls.txt"
cat "$WORK/katana-urls.txt"
```

Real output:

```
http://127.0.0.1:8099
http://127.0.0.1:8099/app.js
http://127.0.0.1:8099/page1.html
http://127.0.0.1:8099/sub/page2.html
```

## 3. Add the JavaScript-derived endpoints

The fixture's `app.js` mentions `/api/v1/items` only inside a string and a
`fetch()` call — invisible to a plain link-follower.

```bash
katana -u http://127.0.0.1:8099 -d 2 -jc -jsl -silent -duc
```

Adds:

```
http://127.0.0.1:8099/api/v1/items
```

`-jc` alone parses endpoints out of JavaScript; `-jsl` adds jsluice parsing,
which its own help text calls memory intensive. Start with `-jc`.

## 4. Forms and XHR, as structured output

```bash
printf '<html><head><title>Form</title></head><body><form action="/submit" method="POST"><input name="user"><input name="pass" type="password"><textarea name="c"></textarea><select name="s"><option>1</option></select></form></body></html>' > /tmp/site/form.html

katana -u http://127.0.0.1:8099/form.html -d 1 -silent -jsonl -fx -duc \
  | jq -c '.forms[]?'
```

Real output:

```json
{"method":"POST","action":"http://127.0.0.1:8099/submit",
 "enctype":"application/x-www-form-urlencoded","parameters":["user","pass","c","s"]}
```

That is the input list for `arjun`, `dalfox` or `ffuf` without reading any HTML.

## 5. Understand the JSONL shape before parsing it

```bash
katana -u http://127.0.0.1:8099 -d 1 -silent -jsonl -duc | head -1 | jq -r 'keys_unsorted | join(",")'
# timestamp,request,response
katana -u http://127.0.0.1:8099 -d 1 -silent -jsonl -duc | head -1 | jq -r '.request | keys_unsorted | join(",")'
# method,endpoint,raw
katana -u http://127.0.0.1:8099 -d 1 -silent -jsonl -duc | head -1 | jq -r '.response | keys_unsorted | join(",")'
# status_code,headers,body,content_length,raw
```

A failed fetch replaces `response` with an `error`:

```json
{"timestamp":"...","request":{"method":"GET","endpoint":"http://127.0.0.1:8099/index.html",...},
 "error":"GET http://127.0.0.1:8099/index.html giving up after 2 attempts: ... connection refused"}
```

Extract the surface, and skim the failures separately:

```bash
katana -u "$TARGET" -d 3 -silent -jsonl -duc -o "$WORK/katana.jsonl"
jq -r '.request.endpoint' "$WORK/katana.jsonl" | sort -u > "$WORK/urls.txt"
jq -r 'select(.error) | "\(.request.endpoint)\t\(.error)"' "$WORK/katana.jsonl"
```

## 6. Keep the file small enough to read

katana puts the full response body into every JSONL line by default.

```bash
katana -u "$TARGET" -d 2 -or -ob -jsonl -silent -duc | jq -r '.request.endpoint'
```

`-or` drops raw request/response text, `-ob` drops bodies.

## 7. Bound a crawl on a site you do not control the size of

```bash
katana -u "$TARGET" -d 5 -ct 10m -rl 25 -c 5 -p 5 \
  -em php,html,js \
  -cos '/logout|/signout|/delete' \
  -silent -nc -duc -o "$WORK/katana-bounded.txt"
```

`-d` bounds depth, `-ct` bounds wall-clock. On a site with pagination, depth
alone is not a bound. `-cos` keeps the crawler off state-changing links.

## 8. Crawl then discover then scan

```bash
# crawl -> content discovery
katana -u "$TARGET" -d 3 -silent -duc > "$WORK/urls.txt"
ffuf -u "$TARGET/FUZZ" \
  -w /opt/wordlists/SecLists/Discovery/Web-Content/common.txt \
  -mc 200,301,302,401,403 -rate 25 -s

# crawl -> confirm live -> scan
katana -u "$TARGET" -d 3 -silent -duc \
  | httpx -silent -sc -title -duc \
  | tee "$WORK/live.txt" \
  | nuclei -severity medium,high,critical -ni -rl 25 -c 10 -silent -jsonl -duc \
      -o "$WORK/nuclei.jsonl"
```

katana reads targets on stdin as well as with `-u`, so it can sit anywhere in a
pipeline. Note the output flag is **`-jsonl`**; `katana -json` fails with
`flag provided but not defined: -json`, unlike httpx where `-json` is correct.

## 9. Parameterised URLs for injection testing

```bash
jq -r '.request.endpoint' "$WORK/katana.jsonl" | grep -E '\?' | sort -u > "$WORK/params.txt"
wc -l "$WORK/params.txt"
```

## Known-broken in this image: headless crawling

`-hl` and `-hh` download a Chromium build on first use and then cannot run it.
The failure is silent, which is the dangerous part:

```bash
$ katana -u http://127.0.0.1:8099 -d 1 -hl -duc
[launcher.Browser] Download: https://storage.googleapis.com/chromium-browser-snapshots/Linux_x64/1321438/chrome-linux.zip
[launcher.Browser] Downloaded: /root/.cache/rod/browser/chromium-1321438
[INF] Crawl completed in 1s. 0 endpoints found.
$ echo $?
0
```

Exit code 0, zero endpoints, no error. The bundled browser is missing 14 shared
libraries:

```bash
$ ldd /root/.cache/rod/browser/chromium-1321438/chrome | grep -c 'not found'
14
$ /root/.cache/rod/browser/chromium-1321438/chrome --version
... error while loading shared libraries: libnss3.so: cannot open shared object file
```

A headless crawl that finds nothing has learned nothing about the target — it
never had a browser. Use `-jc` (non-headless JavaScript parsing), which needs no
browser and works.
