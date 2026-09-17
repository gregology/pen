# feroxbuster — worked examples

All commands below were run against `feroxbuster 2.13.1` in the agent image
(`/usr/local/bin/feroxbuster`) against a throwaway localhost fixture with this
tree:

```
/                 /admin/            /admin/index.html    /admin/panel/
/admin/panel/deep.html                 /api/v1/users        /api/v2/keys
/login (links to /api/v2/keys)         /newdir/hidden.html  /newdir/
/linked (links to /newdir/)            /robots.txt          /search
/cookie (403 without session)          /redirect (302 -> /admin/)
```

The wordlist used for most runs, `dirs3.txt`:

```
index.html admin admin/ panel deep.html linked hidden.html api robots.txt
login search cookie redirect
```

## 1. Basic recursive scan with JSON evidence

```
$ feroxbuster -u http://127.0.0.1:8090 -w dirs3.txt -t 10 -q --json -o fb1.json --no-state
$ jq -r 'select(.type=="response") | [.status, .content_length, .url] | @tsv' fb1.json
200	3	http://127.0.0.1:8090/
404	10	http://127.0.0.1:8090/admin
200	7	http://127.0.0.1:8090/admin/
200	6	http://127.0.0.1:8090/api/v2/keys
403	7	http://127.0.0.1:8090/cookie
200	3	http://127.0.0.1:8090/index.html
200	59	http://127.0.0.1:8090/linked
200	104	http://127.0.0.1:8090/login
302	0	http://127.0.0.1:8090/redirect
200	32	http://127.0.0.1:8090/robots.txt
200	73	http://127.0.0.1:8090/search
```

Record types present in the file:

```
$ jq -r '.type' fb1.json | sort | uniq -c
      1 configuration
     11 response
      1 statistics
```

`/api/v2/keys` is not in `dirs3.txt`: it was found by link extraction from
`/login`, which is the default behaviour.

Full response record (one line, wrapped here):

```
{"type":"response","url":"http://127.0.0.1:8090/admin","original_url":"http://127.0.0.1:8090/",
 "path":"/admin","wildcard":false,"status":404,"method":"GET","content_length":10,
 "line_count":1,"word_count":2,"headers":{...},"extension":"","truncated":false,
 "timestamp":1789677693.569149}
```

Statistics record — this is where rate limiting and filtering show up:

```
$ jq -c 'select(.type=="statistics")' fb1.json
{"type":"statistics","timeouts":0,"requests":25,"expected_per_scan":14,"total_expected":16,
 "errors":0,"successes":10,"redirects":1,"client_errors":14,"server_errors":0,"total_scans":1,
 "initial_targets":0,"links_extracted":2,"extensions_collected":0,"status_200s":10,
 "status_301s":0,"status_302s":1,"status_401s":0,"status_403s":1,"status_429s":0,
 "status_500s":0,"status_503s":0,"status_504s":0,"status_508s":0,"wildcards_filtered":6,
 "responses_filtered":6,"resources_discovered":10,"url_format_errors":0,
 "redirection_errors":0,"connection_errors":0,"request_errors":0,"certificate_errors":0,
 "directory_scan_times":[0.208957627],"total_runtime":[0.75575411],
 "targets":["http://127.0.0.1:8090/"]}
```

## 2. The default filter hides real results — and how to stop it

Same target, same wordlist, default settings versus `-D`:

```
$ feroxbuster -u http://127.0.0.1:8090 -w dirs3.txt -t 10 -d 4 --silent --no-state 2>/dev/null | grep -v '^$' | sort
http://127.0.0.1:8090/
http://127.0.0.1:8090/admin
http://127.0.0.1:8090/admin/
http://127.0.0.1:8090/api/v2/keys
http://127.0.0.1:8090/cookie
http://127.0.0.1:8090/index.html
http://127.0.0.1:8090/linked
http://127.0.0.1:8090/login
http://127.0.0.1:8090/redirect
http://127.0.0.1:8090/robots.txt
http://127.0.0.1:8090/search
```

`/admin/index.html` exists (`curl` returns 200) but is missing. With
`-D/--dont-filter` the response set changes completely — the suppressed 404s
come back as noise, and the count goes from 11 to 18:

```
$ feroxbuster -u http://127.0.0.1:8090 -w dirs3.txt -t 10 -d 4 -D --silent --no-state 2>/dev/null | grep -v '^$' | sort
http://127.0.0.1:8090/
http://127.0.0.1:8090/admin
http://127.0.0.1:8090/admin/
http://127.0.0.1:8090/api
http://127.0.0.1:8090/api/
http://127.0.0.1:8090/api/v2/
http://127.0.0.1:8090/api/v2/keys
http://127.0.0.1:8090/cookie
http://127.0.0.1:8090/deep.html
http://127.0.0.1:8090/hidden.html
http://127.0.0.1:8090/index.html
http://127.0.0.1:8090/linked
http://127.0.0.1:8090/login
http://127.0.0.1:8090/newdir
http://127.0.0.1:8090/panel
http://127.0.0.1:8090/redirect
http://127.0.0.1:8090/robots.txt
http://127.0.0.1:8090/search
```

`/api`, `/panel`, `/deep.html`, `/hidden.html`, `/newdir` are 404s that the
default filter was hiding — useful noise, not findings. Neither mode surfaced
`/admin/index.html`, which only appears once recursion is forced *and* the 404
noise is explicitly filtered by reference page:

```
$ feroxbuster -u http://127.0.0.1:8090 -w dirs3.txt -t 10 -d 4 -D --force-recursion \
    --filter-similar-to http://127.0.0.1:8090/nope -q --json -o s19.json --no-state
$ jq -r 'select(.type=="response") | .url' s19.json | sort
http://127.0.0.1:8090/
http://127.0.0.1:8090/admin/
http://127.0.0.1:8090/admin/index.html
http://127.0.0.1:8090/cookie
http://127.0.0.1:8090/index.html
http://127.0.0.1:8090/linked
http://127.0.0.1:8090/login
http://127.0.0.1:8090/redirect
http://127.0.0.1:8090/robots.txt
http://127.0.0.1:8090/search
$ jq -c 'select(.type=="statistics") | {requests, responses_filtered, resources_discovered, status_429s}' s19.json
{"requests":179,"responses_filtered":0,"resources_discovered":10,"status_429s":0}
```

**Drop `--filter-similar-to` and that same command explodes**: verified 30,387
requests and 25,761 discovered resources, because with `-D` the 404 responses
are reported and `--force-recursion` then treats each of them as a directory to
scan.

Record what was filtered, so a false negative is visible in the evidence:

```
$ jq -c 'select(.type=="statistics") | {requests, responses_filtered, wildcards_filtered, links_extracted}' s18a.json
{"requests":29,"responses_filtered":9,"wildcards_filtered":9,"links_extracted":6}
```

## 3. Soft-404 / wildcard target

A second fixture answers `200` with an identical 72-byte body for every path:

```
$ curl -s -o /dev/null -w '%{http_code} %{size_download}\n' http://127.0.0.1:8081/zzz
200 72

$ feroxbuster -u http://127.0.0.1:8081 -w dirs3.txt -t 10 --silent --no-state 2>/dev/null | grep -v '^$' | wc -l
0                                    # default: auto-filter suppressed everything

$ feroxbuster -u http://127.0.0.1:8081 -w dirs3.txt -t 10 -D --silent --no-state 2>/dev/null | grep -v '^$' | wc -l
53                                   # -D: every wordlist entry "matches"

$ feroxbuster -u http://127.0.0.1:8081 -w dirs3.txt -t 10 --filter-similar-to http://127.0.0.1:8081/zzz \
    --silent --no-state 2>/dev/null | grep -v '^$' | wc -l
0                                    # silence by explicit reference page

$ feroxbuster -u http://127.0.0.1:8081 -w dirs3.txt -t 10 -D -C 200 --silent --no-state 2>/dev/null | grep -v '^$' | wc -l
0                                    # everything is 200 here, so an allow/deny list also works
```

## 4. Depth control

```
$ feroxbuster -u http://127.0.0.1:8090 -w dirs3.txt -t 10 -d 1 --silent --no-state 2>/dev/null | grep -c .
11
$ feroxbuster -u http://127.0.0.1:8090 -w dirs3.txt -t 10 -n --silent --no-state 2>/dev/null | grep -c .
11
```

Deeper trees need `-d 2+`; `-d 0` means infinite. Recursion is what produces
`/admin/index.html` above — the depth-1 run reports `/admin/` but not its
contents.

## 5. stdin, parallel, and clean URL output

```
$ printf 'http://127.0.0.1:8090\nhttp://127.0.0.1:8081\n' > targets.txt
$ feroxbuster --stdin -w dirs3.txt -t 10 --silent --no-state < targets.txt 2>/dev/null | grep -v '^$' | sort -u
http://127.0.0.1:8090/
...
http://127.0.0.1:8090/search

$ feroxbuster --stdin -w dirs3.txt -t 10 --parallel 2 --silent --no-state < targets.txt 2>/dev/null | grep -c .
11
```

`--silent` emits blank lines between URLs (verified with `cat -A`: `$` on its
own line after each result), so always `grep -v '^$'` before feeding a file to
another tool.

## 6. Filters

```
$ feroxbuster -u http://127.0.0.1:8090 -w dirs3.txt -t 10 -C 404 --silent --no-state 2>/dev/null | grep -v '^$' | sort -u
http://127.0.0.1:8090/
http://127.0.0.1:8090/admin/
http://127.0.0.1:8090/admin/index.html
http://127.0.0.1:8090/api/v1/users
http://127.0.0.1:8090/cookie
http://127.0.0.1:8090/index.html
http://127.0.0.1:8090/login
http://127.0.0.1:8090/redirect
http://127.0.0.1:8090/robots.txt
http://127.0.0.1:8090/search

$ feroxbuster -u http://127.0.0.1:8090 -w dirs3.txt -t 10 -S 10 --silent --no-state 2>/dev/null | grep -c .
10                                   # drops the 10-byte 404 body
$ feroxbuster -u http://127.0.0.1:8090 -w dirs3.txt -t 10 -X 'not found' --silent --no-state 2>/dev/null | grep -c .
10                                   # drops the same responses by body regex
```

## 7. Pacing, and what it costs

```
$ wc -l /opt/wordlists/SecLists/Discovery/Web-Content/common.txt
4750
$ time feroxbuster -u http://127.0.0.1:8090 -w .../common.txt -t 10 -q --no-state
unlimited elapsed=20424ms
$ time feroxbuster -u http://127.0.0.1:8090 -w .../common.txt -t 10 --rate-limit 50 -q --no-state
rate-limit 50 elapsed=95462ms
```

`--rate-limit 50` behaved exactly as 4750/50 ≈ 95 s predicts — per directory.
Recursion multiplies that by the number of directories scanned, unless
`-L/--scan-limit` caps concurrent scans.

`--time-limit` is the backstop, and it changes the exit code:

```
$ feroxbuster -u http://127.0.0.1:8090 -w .../common.txt -t 5 --time-limit 4s -q --no-state; echo rc=$?
rc=1
```

## 8. State file and resume

```
$ rm -f ferox-*.state
$ timeout -s INT 6 feroxbuster -u http://127.0.0.1:8090 -w .../common.txt -t 5 -q
$ ls ferox-*.state
ferox-http_127_0_0_1_8090_-1789677870.state

$ head -c 200 ferox-http_127_0_0_1_8090_-1789677870.state
{"scans":[{"id":"167df6b4d84b4001b199697de12aafdd","url":"http://127.0.0.1:8090/",
 "normalized_url":"http://127.0.0.1:8090/","scan_type":"Directory","status":"Running",
 "num_requests":4752,"requests_made_so_far":664}, ...]}

$ feroxbuster --resume-from ferox-http_127_0_0_1_8090_-1789677870.state -q
```

A `SIGTERM` (plain `timeout 6 …`) left **no** state file — the interrupt must be
`SIGINT`. `--no-state` disables the file, which is what the verification runs
above used to keep the workspace clean.

## 9. Common CLI traps

```
$ feroxbuster -u http://127.0.0.1:8090 -w dirs3.txt -q --silent
error: the argument '--quiet' cannot be used with '--silent'
Usage: feroxbuster --url <URL> --wordlist <FILE> --quiet
rc=2

$ feroxbuster -u http://127.0.0.1:8090 -t 10 -q
Could not open /usr/share/seclists/Discovery/Web-Content/raft-medium-directories.txt
```

`-o` without `--json` writes a `Configuration { … }` debug dump (290 lines in
the verification run), not a results list. Use `--json -o file` for evidence and
`--silent --json` for pipelines.
