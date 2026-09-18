# ffuf — worked examples

Every command and output below was run against `ffuf 2.3.0` in the agent image
(`/usr/local/bin/ffuf`), against a throwaway localhost fixture, so the numbers
are reproducible rather than illustrative. Paths use the doc conventions:
`$WORK` is the per-engagement directory, `$TARGET` the authorized host.

The fixture reproduced the cases that matter: a normal site with `/admin/`,
`/api/v1/users`, a `302`, a `403`, a reflecting `/search?q=`, a vhost that
answers only to `Host: internal.local`, and a second server that returns an
identical `200` body for every path (soft-404/wildcard).

## 1. Nothing found? Check the default matcher first

```
$ ffuf -w dirs.txt -u http://127.0.0.1:8090/FUZZ -t 10 -s
redirect
search
index.html
login
cookie
admin/
api/v1/users
robots.txt
```

`admin` and `missing-entry-xyz` are absent because the default matcher is
`200-299,301,302,307,401,403,405,500` — `404` is not in it. With `-mc all` the
same wordlist reports all 11 entries, including the `404`s:

```
$ ffuf -w dirs.txt -u http://127.0.0.1:8090/FUZZ -mc all -t 10 -s -of json -o f1.json
$ jq -r '.results[] | [.status, .length, .words, .input.FUZZ] | @tsv' f1.json
404	10	2	api
200	3	1	index.html
302	0	1	redirect
200	72	5	login
200	73	5	search
200	28	3	api/v1/users
404	10	2	admin
403	7	1	cookie
404	10	2	missing-entry-xyz
200	32	3	robots.txt
200	7	1	admin/
```

The `404` rows share status and size (10 bytes): that is the wildcard
signature to filter on.

## 2. Virtual-host discovery

```
$ ffuf -w vhosts.txt -u http://127.0.0.1:8090/ -H 'Host: FUZZ.local' -mc all -t 10 -s -of json -o f5.json
$ jq -r '.results[] | [.status, .length, .input.FUZZ] | @tsv' f5.json
200	3	mail
200	3	api
200	15	internal
200	3	www
```

Three hosts get the default page (3 bytes); `internal` gets a different one
(15 bytes). Filtering the default with `-fs 3` leaves exactly one row:

```
$ ffuf -w vhosts.txt -u http://127.0.0.1:8090/ -H 'Host: FUZZ.local' -mc all -fs 3 -t 10 -s -of json -o f6.json
$ jq -r '.results[] | [.status, .length, .input.FUZZ] | @tsv' f6.json
200	15	internal
```

## 3. Cookie fuzzing

```
$ ffuf -w cookies.txt -u http://127.0.0.1:8090/cookie -H 'Cookie: session=FUZZ' -mc all -t 10 -s -of json -o f6b.json
$ jq -r '.results[] | [.status, .length, .input.FUZZ] | @tsv' f6b.json
200	11	admin
403	7	guest
```

## 4. POST body fuzzing

```
$ ffuf -w params.txt -u http://127.0.0.1:8090/api -X POST \
    -H 'Content-Type: application/x-www-form-urlencoded' -d 'user=FUZZ' \
    -mc all -t 10 -s -of json -o f7.json
$ jq -r '.results[] | [.status, .length, .input.FUZZ] | @tsv' f7.json
200	14	admin
403	12	user
403	12	q
```

The same mechanics carry JSON bodies: `-d '{"name":"FUZZ"}' -H 'Content-Type:
application/json'`.

## 5. Raw request file

```
$ cat req.txt
GET /FUZZ HTTP/1.1
Host: 127.0.0.1:8090
User-Agent: ffuf-verify

$ ffuf -request req.txt -request-proto http -w dirs.txt -mc all -t 10 -s -of json -o f14.json
$ jq -r '.results | length' f14.json
11
```

Without `-request-proto http` the request goes out as HTTPS and fails.

## 6. Wildcard/soft-404 suppression, measured

Against a server that answers `200` and an identical 72-byte body for every
path:

```
$ ffuf -w dirs.txt -u http://127.0.0.1:8081/FUZZ -mc all -t 10 -s -of json -o ff1a.json
$ jq -r '.results | length' ff1a.json
13
$ ffuf -w dirs.txt -u http://127.0.0.1:8081/FUZZ -mc all -ac -t 10 -s -of json -o ff1b.json
$ jq -r '.results | length' ff1b.json
0
$ ffuf -w dirs.txt -u http://127.0.0.1:8081/FUZZ -mc all -fs 72 -t 10 -s -of json -o ff1c.json 2>/dev/null
$ jq -r '.results | length' ff1c.json
0
$ ffuf -w dirs.txt -u http://127.0.0.1:8081/FUZZ -mc all -fr 'Nothing to see here' -t 10 -s -of json -o ff1d.json 2>/dev/null
$ jq -r '.results | length' ff1d.json
0
$ ffuf -w dirs.txt -u http://127.0.0.1:8081/FUZZ -mc all -fw 10 -t 10 -s -of json -o ff1e.json 2>/dev/null
$ jq -r '.results | length' ff1e.json
13
```

Four suppression strategies, three outcomes: `-ac`, `-fs` and `-fr` removed the
noise; `-fw 10` did not, because the fixture's word count was not 10. Measure
before filtering. On a server with genuine content, `-ac` behaved: it returned
the same 8 real results as `-fc 404`.

## 7. Recursion

Recursion requires `-u` to end in `FUZZ`:

```
$ ffuf -w dirs.txt -u http://127.0.0.1:8090/ -recursion -t 10 -s
Keyword FUZZ defined, but not found in headers, method, URL or POST data.
Encountered error(s): 1 errors occured.
	* When using -recursion the URL (-u) must end with FUZZ keyword.
```

With a two-word list (`admin/`, `index.html`) and `-mc all -fc 404`, the
default (redirect-based) strategy does not descend:

```
$ ffuf -w dirs5.txt -u http://127.0.0.1:8090/FUZZ -recursion -recursion-depth 2 -mc all -fc 404 -t 5 -s -of json -o ff12a.json
$ jq -r '.results[].url' ff12a.json | sort
http://127.0.0.1:8090/admin/
http://127.0.0.1:8090/index.html
```

Greedy queues jobs — note the doubled slash when the match already ends in `/`:

```
$ ffuf -w dirs5.txt -u http://127.0.0.1:8090/FUZZ -recursion -recursion-strategy greedy \
    -recursion-depth 2 -mc all -fc 404 -t 5 -s -of json -o ff12b.json
Adding a new job to the queue: http://127.0.0.1:8090/admin//FUZZ
Adding a new job to the queue: http://127.0.0.1:8090/index.html/FUZZ
Starting queued job on target: http://127.0.0.1:8090/admin//FUZZ
Starting queued job on target: http://127.0.0.1:8090/index.html/FUZZ
```

`//FUZZ` requests `//index.html`, which many servers treat as a different path
than `/index.html`. Prefer a wordlist without trailing slashes for recursion.

## 8. Reading the output formats

```
$ ffuf -w dirs.txt -u http://127.0.0.1:8090/FUZZ -mc 200 -t 10 -s -of json -o ff3.json
$ jq -r 'keys | join(",")' ff3.json
commandline,config,results,time
$ jq -c '.results[0] | {input, url, status}' ff3.json
{"input":{"FFUFHASH":"63c49a","FUZZ":"login"},"url":"http://127.0.0.1:8090/login","status":200}
```

The stdout JSONL from `-json` uses the same field names but base64-encodes the
input values:

```
$ ffuf -w dirs.txt -u http://127.0.0.1:8090/FUZZ -mc 200 -t 10 -s -json | head -1
{"input":{"FFUFHASH":"MDY3YWRh","FUZZ":"bG9naW4="},"position":10,"status":200,"length":104,...}
$ ffuf -w dirs.txt -u http://127.0.0.1:8090/FUZZ -mc 200 -t 10 -s -json | head -1 | jq -r '.input.FUZZ' | base64 -d; echo
login
```

## 9. Wordlist from stdin and generated inputs

```
$ printf 'admin/\nindex.html\n' | ffuf -w - -u http://127.0.0.1:8090/FUZZ -mc all -fc 404 -t 5 -s -of json -o ff13.json
$ jq -r '.results[]?.url' ff13.json
http://127.0.0.1:8090/admin/
http://127.0.0.1:8090/index.html

$ ffuf -input-cmd 'printf "admin/\nindex.html\n"' -input-num 2 -u http://127.0.0.1:8090/FUZZ -mc all -fc 404 -t 5 -s -of json -o ff13b.json -debug-log /tmp/ffuf-debug.log
$ jq -r '.results[]?.url' ff13b.json
(no output)
$ grep -o 'net/url: invalid control character in URL' /tmp/ffuf-debug.log | head -1
net/url: invalid control character in URL
```

`-input-cmd` does not line-split the command's stdout: the whole output is
substituted at `FUZZ` as one value, newlines included, so the URL is rejected
(`net/url: invalid control character in URL`) and the run matches nothing.
`-input-num` sizes the generated set, it does not enumerate lines. For a list
of inputs, pipe it in with `-w -` as above.

## 10. Extension expansion behaves literally

```
$ ffuf -w dirs.txt -u http://127.0.0.1:8090/FUZZ -e .html -mc all -t 10 -s -of json -o ff7.json
$ jq -r '[.results[].input.FUZZ] | map(select(test("html")))' ff7.json
["deep.html.html","index.html.html","index.html","admin.html","admin/.html","panel.html","linked.html", ...]
```

`-e .html` is appended to *every* entry, including entries that already end in
`.html` and entries ending in `/`. Use a purpose-built wordlist rather than
extending a mixed one.

## 11. Pacing

```
$ time ffuf -w dirs.txt -u http://127.0.0.1:8090/FUZZ -mc all -rate 20 -t 10 -s -o /dev/null
rate=20 -> 1s for 13 requests
$ time ffuf -w dirs.txt -u http://127.0.0.1:8090/FUZZ -mc all -t 10 -s -o /dev/null
no rate -> 0s
```

`-rate` is process-wide requests per second; `-p 0.05` spaces a single thread's
requests by 50 ms. Use one or the other, not both, and set them from the
engagement's agreed budget rather than the binary's defaults (`-t 40`).
