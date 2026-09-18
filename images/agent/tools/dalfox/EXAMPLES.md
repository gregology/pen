# dalfox — worked examples

Every command and output below was run against `dalfox 3.2.3` in the agent image
(`/usr/bin/dalfox`) against a throwaway localhost fixture with two relevant
endpoints:

- `/search?q=X` — reflects `X` unencoded into HTML text and into an `value="…"`
  attribute (a real reflected XSS);
- `/dom?q=X` — no reflection in the body, but inline JavaScript does
  `document.getElementById('x').innerHTML = decodeURIComponent(location.search…)`
  (a DOM sink that only static analysis can see).

## 1. Flags that do not exist in 3.2.3

```
$ dalfox version
8:48PM UNREACHABLE http://version/ (DNS resolution failed)
8:48PM WRN XSS found 0 XSS
8:48PM INF scan completed in 0.384 seconds

$ dalfox --version
dalfox 3.2.3

$ dalfox scan 'http://127.0.0.1:8090/search?q=test' --worker 2
error: unexpected argument '--worker' found
  tip: a similar argument exists: '--workers'

$ dalfox scan 'http://127.0.0.1:8090/search?q=test' --deep-domxss
error: unexpected argument '--deep-domxss' found
  tip: a similar argument exists: '--deep-scan'

$ dalfox scan --file urls2.txt --silence
error: unexpected argument '--file' found     # file input is positional or -i file
```

`version` is a target URL, not a subcommand; `--worker` is `--workers`;
`--deep-domxss` does not exist (`--deep-scan` means "keep testing payloads
after a finding"); `--file` does not exist.

## 2. Reflected XSS, single URL, JSON evidence

```
$ dalfox scan 'http://127.0.0.1:8090/search?q=test' -S --no-color \
    --workers 2 --delay 100 -o dalfox1.json -f json < /dev/null
$ jq -r 'keys | join(",")' dalfox1.json
findings,meta
$ jq -r '.meta | keys | join(",")' dalfox1.json
dalfox_version,dedup_mode,failed_requests,findings_count,incomplete,scan_duration_ms,target_summary,targets,targets_deduplicated,total_requests
$ jq -c '.meta' dalfox1.json
{"dalfox_version":"3.2.3","dedup_mode":"exact","failed_requests":0,"findings_count":1,
 "incomplete":false,"scan_duration_ms":11233,
 "target_summary":[{"findings_count":1,"status":"findings","target":"http://127.0.0.1:8090/search?q=test"}],
 "targets":["http://127.0.0.1:8090/search?q=test"],"targets_deduplicated":0,"total_requests":183}
$ jq -r '.findings[0] | keys | join(",")' dalfox1.json
confidence,confidence_reason,cwe,data,detection_method,evidence,inject_type,location,message_id,message_str,method,param,payload,severity,type,type_description
$ jq -c '.findings[0]' dalfox1.json
{"confidence":"high","confidence_reason":"DOM verification confirmed an executable position (DOM marker)",
 "cwe":"CWE-79","data":"http://127.0.0.1:8090/search?q=%3E%3Csvg%20onload%3Dalert%281%29%20class%3Ddlx3914bbf1%3E",
 "detection_method":"dom-verification","evidence":"DOM verification successful for param q (DOM marker)",
 "inject_type":"inHTML","location":"Query","message_id":606,
 "message_str":"Triggered XSS Payload (DOM marker): q=><svg onload=alert(1) class=dlx3914bbf1>",
 "method":"GET","param":"q","payload":"><svg onload=alert(1) class=dlx3914bbf1>","severity":"High","type":"V",
 "type_description":"Vulnerable - dalfox asserts this input is exploitable; act on it"}
```

Note `total_requests: 183` for a single parameter: pacing flags matter.
`-S/--silence` suppressed the logs but still wrote the file.

## 3. What the terminal looks like without `-S`

```
$ dalfox scan 'http://127.0.0.1:8090/search?q=test' --no-color --workers 2 --delay 100 --skip-mining-dom < /dev/null
8:48PM INF start scan to http://127.0.0.1:8090/search?q=test
8:48PM INF found reflected 1 params
8:49PM WRN XSS found 1 XSS
[POC][V][GET][inHTML] http://127.0.0.1:8090/search?q=%3E%3Csvg%20onload%3Dalert%281%29%20class%3Ddlx22990457%3E

8:49PM INF scan completed in 13.041 seconds

$ dalfox scan 'http://127.0.0.1:8090/search?q=test' -S --no-color --workers 2 --delay 50 --poc-type curl < /dev/null
curl -X GET "http://127.0.0.1:8090/search?q=%3E%3Csvg%20onload%3Dalert%281%29%20class%3Ddlxdc0e1e45%3E"
  ├── Issue: XSS payload DOM object identified
  ├── Payload: ><svg onload=alert(1) class=dlxdc0e1e45>
  └── L1: ody><h1>Results for ><svg onload=alert(1) class=dlxdc0e1e45></h1><input name="q"
```

## 4. DOM-XSS analysis needs no browser

```
$ dalfox scan 'http://127.0.0.1:8090/dom?q=test' -S --no-color --workers 1 --skip-mining-dom < /dev/null
[POC][A][GET][DOM-XSS] http://127.0.0.1:8090/dom?xss=%3Cimg%20src=x%20onerror=alert(1)%20class%3Ddlxc650a9cd%3E
  ├── Issue: DOM-based XSS via location.search to innerHTML (needs runtime confirmation)
  └── Payload: xss=<img src=x onerror=alert(1) class=dlxc650a9cd>

$ dalfox scan 'http://127.0.0.1:8090/dom?q=test' -S --no-color --workers 1 --skip-mining-dom --skip-ast-analysis < /dev/null
(no output)
```

`[A]` is the AST finding type: static source→sink analysis of inline
JavaScript, no headless browser involved (none is installed). `--skip-mining-dom`
does not silence it; `--skip-ast-analysis` does.

## 5. Input modes

```
# positional URL
$ dalfox scan 'http://127.0.0.1:8090/search?q=test' -S --no-color --workers 2 --delay 50 < /dev/null

# positional file path (auto-detected)
$ printf 'http://127.0.0.1:8090/search?q=alpha\nhttp://127.0.0.1:8090/search?q=beta\n' > urls2.txt
$ dalfox scan urls2.txt -S --no-color --workers 2 --delay 50 < /dev/null
  └── L1: ody><h1>Results for ><svg onload=alert(1) class=dlx07b32890></h1><input name="q"

# explicit file input
$ dalfox scan -i file urls2.txt -S --no-color --workers 2 --delay 50 < /dev/null

# pipe
$ cat urls2.txt | dalfox scan -i pipe -S --no-color --workers 2 --delay 50

# raw HTTP request
$ printf 'GET /search?q=rawtest HTTP/1.1\nHost: 127.0.0.1:8090\n\n' > raw.txt
$ dalfox scan -i raw-http raw.txt -S --no-color --workers 1 --delay 50 < /dev/null
```

All four produced findings. The stdin form needs no flag — dalfox detects a
pipe — but that same behaviour is why every other invocation in these examples
has `< /dev/null`.

## 6. Formats and exit codes

```
$ for f in json jsonl plain markdown sarif toml; do
    dalfox scan 'http://127.0.0.1:8090/search?q=test' -S --no-color --workers 2 --delay 50 \
      -f $f -o dalfox-$f.out < /dev/null >/dev/null 2>&1
    printf '%-9s rc=%s bytes=%s\n' "$f" "$?" "$(wc -c < dalfox-$f.out)"
  done
json      rc=1 bytes=1303
jsonl     rc=1 bytes=1016
plain     rc=1 bytes=324
markdown  rc=1 bytes=1095
sarif     rc=1 bytes=3924
toml      rc=1 bytes=1027

$ jq -c '.meta | {findings_count, incomplete, total_requests}' all-poc.json
{"findings_count":1,"incomplete":false,"total_requests":183}

$ dalfox scan 'http://127.0.0.1:8090/robots.txt' -S --no-color --workers 1 < /dev/null >/dev/null 2>&1; echo rc=$?
rc=0
$ dalfox scan 'http://127.0.0.1:9999/x' -S --no-color --workers 1 < /dev/null >/dev/null 2>&1; echo rc=$?
rc=2
```

Exit codes: `1` findings, `0` clean, `2` error. A `1` is the result you were
looking for.

## 7. Rate control is the dominant cost

```
$ time dalfox scan urls2.txt -S --no-color --workers 1 --delay 1000 -f json -o /dev/null < /dev/null
workers1 delay1000 elapsed=177s

$ time dalfox scan urls2.txt -S --no-color --workers 1 --rate-limit 2 -f json -o /dev/null < /dev/null
workers1 rl2 elapsed=182s

$ time dalfox scan 'http://127.0.0.1:8090/search?q=test' -S --no-color --workers 2 --delay 100 -f json -o /dev/null < /dev/null
elapsed=12s (183 requests)
```

For a mass scan, prefer `--rate-limit` (global, shared across workers) over
per-worker delays; `--max-payloads-per-param` or `--only-discovery` bound the
work per target.

## 8. Typical hand-off from katana

```
$ katana -u https://$TARGET -jc -d 3 -silent | grep '?' > $WORK/param-urls.txt
$ dalfox scan -i file $WORK/param-urls.txt --dedup-urls signature \
    --workers 2 --delay 100 -f jsonl -o $WORK/dalfox.jsonl < /dev/null
$ jq -r 'select(.findings) | .findings[]? | [.type, .method, .param, .data] | @tsv' $WORK/dalfox.jsonl
V	GET	q	http://$TARGET/search?q=%3E%3Csvg%20onload%3Dalert%281%29%20class%3Ddlx…%3E
```

`--dedup-urls signature` collapses URLs that differ only in parameter values,
which is what stops a crawler's `?page=1..N` from becoming N full scans.
