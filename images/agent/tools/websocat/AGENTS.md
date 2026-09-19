# websocat — WebSocket and SSE client

websocat is a WebSocket client, a WebSocket server, and — in its advanced form —
a bidirectional relay between any two addresses. For this platform the useful
half is the first: it opens a WebSocket, frames what you type or pipe into it,
prints what comes back, and lets you script a whole conversation with a shell
pipeline. Reach for it when a target exposes a `ws://` or `wss://` endpoint and
you need to see or drive the message flow.

Be clear about what it does not do: **there is no standard CLI WebSocket
fuzzer.** The workflow here is websocat for scripted framing and message relay,
the Python `websocket-client` and `websockets` libraries for message-level
fuzzing, and `mitmproxy` (already in the image) to intercept and rewrite live
frames. For **Server-Sent Events** there is no dedicated tool at all: an SSE
endpoint is a long-lived HTTP response with `Content-Type: text/event-stream`,
and `curl -N` against it is the practical probe. websocat is the framing and
sanity-check layer, not the whole WebSocket test plan.

## Installation and location

| | |
|---|---|
| Version | 1.14.1 (`websocat --version` prints `websocat 1.14.1` on **both** stdout and stderr) |
| Binary | `/usr/local/bin/websocat` — pinned static musl build (`x86_64-unknown-linux-musl`), no libc dependency |
| Config | none on disk |
| Help | `--help` for the common set, `--help=long` for the full flag list |

```bash
websocat --version        # -> websocat 1.14.1  (once on stdout, once on stderr)
websocat --help=long | less
```

The doubled version line is not an error: the binary writes the same string to
both streams. A script that does `websocat --version | grep -c 1.14.1` gets `1`;
one that captures stderr too gets `2`.

## Rules that apply to this tool

1. **Authorization first.** A WebSocket is a live, usually authenticated channel
   to a running application. Connecting is one thing; **sending frames is
   interaction, not observation** — a frame can create a record, trigger a job,
   or change state. Confirm the endpoint with Greg before the first frame, the
   same way you would confirm a POST endpoint.
2. **Never use `-s` (server mode) unless the engagement asks for a listener.**
   Standing up a WebSocket server opens a port and creates a new attack surface
   inside the container. It is not a way to "test" a target, and it must not be
   pointed at anything.
3. **Never relay a target's socket to a listener you do not control.** Advanced
   mode is a bidirectional pipe: `websocat wss://target ws://0.0.0.0:9000` would
   forward the target's traffic to anything that connects. Both ends of a relay
   must be yours and both must be in scope.
4. **Terminate the input side.** websocat is a relay, not a request/response
   tool. A command whose input never ends — an interactive terminal, a `tail -f`,
   a socket — keeps the connection open forever, and the server may keep the
   session alive with it. Always design the run so it ends: `-1`, `-E`, a file
   argument, or an explicit EOF on stdin.
5. **Bound the transcript.** A busy channel (a chat feed, a price ticker, a
   logging socket) will fill a file with megabytes in minutes. Pipe through
   `head`, `timeout`, or a line cap, and write to `$WORK`.
6. **Frames are evidence, frames can be credentials.** A WebSocket handshake
   carries cookies and `Authorization` headers, and the frames frequently carry
   tokens, user data, or commands. Keep captures in `$WORK`, and do not paste
   frame contents into the transcript.
7. **SSE is not WebSocket.** websocat does not speak `text/event-stream`. Use
   `curl -N` (no output buffering) against the SSE endpoint, with the same
   authorization and bounding rules.

## Command reference

Three verified invocation forms:

```bash
websocat ws://URL | wss://URL          # simple client
websocat -s port                        # simple server
websocat [FLAGS] [OPTIONS] <addr1> <addr2>   # advanced: bidirectional relay
```

A bare `ws://` or `wss://` address as the only argument is the simple-client
form. Anything with two addresses is the relay. Flags verified in this build:

| Flag | Meaning |
|---|---|
| `-e`, `--set-environment` | Parse `key=value` lines from the input side and set environment variables for the command run on the other side |
| `-E`, `--exit-on-eof` | Exit once the input side reaches EOF, rather than holding the connection open |
| `--jsonrpc` | Format typed messages as JSON-RPC 2.0 method calls |
| `-0`, `--null-terminated` | Messages are NUL-terminated rather than newline-terminated — the flag for binary frames |
| `-1`, `--one-message` | Send (or read) a single message, then finish |
| `--oneshot` | One-shot mode: open, exchange, close |
| `--print-ping-rtts` | Print round-trip times for ping/pong frames |
| `-q` | Suppress diagnostics (the banner/log lines on stderr) |
| `--help=long` | The full flag list, including the TLS options this document does not enumerate |

The address scheme must match the origin: `ws://` for an `http://` origin,
`wss://` for an `https://` origin.

## Typical workflows

1. **Liveness and framing check against a confirmed endpoint.** One message,
   then exit — no hanging connection:

   ```bash
   mkdir -p "$WORK/ws"
   printf '{"type":"ping"}\n' \
     | timeout 20 websocat -1 -q "wss://$TARGET/ws" | tee "$WORK/ws/ping.txt"
   ```

   `-1` is what makes this terminate. Without it the command waits on the socket
   until `timeout` kills it, and any output you did get is interleaved with a
   still-live session.

2. **A scripted conversation from a file.** Each line is one message; `-E` closes
   the connection when the file runs out:

   ```bash
   cat > "$WORK/ws/script.txt" <<'EOF'
   {"type":"subscribe","channel":"orders"}
   {"type":"ping"}
   EOF
   timeout 30 websocat -E -q "wss://$TARGET/ws" < "$WORK/ws/script.txt" \
     > "$WORK/ws/session.txt"
   ```

3. **Read-only listening with a hard cap.** When the point is to see what the
   server pushes, keep the input side empty and cap the output:

   ```bash
   timeout 60 websocat -q "wss://$TARGET/ws" < /dev/null \
     | head -50 > "$WORK/ws/first50.txt"
   ```

   With `-q` there is no diagnostic output at all, so an empty file means "the
   server sent nothing in 60 seconds" — which is not the same as "there is no
   endpoint". Confirm the connection was established before drawing that
   conclusion (drop `-q` for that run, or check the handshake in mitmproxy).

4. **Binary frames.** stdin/stdout are line-oriented by default, so a binary
   protocol needs NUL termination, or a file/socket as the other address:

   ```bash
   timeout 20 websocat -0 -q "wss://$TARGET/ws" < "$WORK/ws/frame.bin" \
     > "$WORK/ws/reply.bin"
   ```

5. **Ping latency, for a target that answers pings.** Useful for deciding whether
   a slow response is the application or the path:

   ```bash
   timeout 30 websocat --print-ping-rtts "wss://$TARGET/ws" < /dev/null
   ```

6. **SSE probe.** Not websocat — an SSE stream is a plain long-lived HTTP
   response, so `curl -N` is the tool:

   ```bash
   timeout 30 curl -N -sS -H "Accept: text/event-stream" \
     "https://$TARGET/events" | tee "$WORK/ws/sse.txt" | head -40
   ```

   `-N` disables curl's output buffering; without it you see nothing until the
   stream ends, which for SSE is never.

## Output and parsing

- **Frames go to stdout, diagnostics to stderr.** `-q` removes the diagnostics;
  it does not change framing. A pipeline that needs clean data should use `-q`
  and treat an empty stdout as "no frames received".
- **Line-oriented by default.** One message per line, and a message containing a
  newline arrives split. That is the single most common source of "the JSON
  doesn't parse": a pretty-printed frame from the server arrives as several
  lines. Either parse the stream as a sequence of JSON values that spans lines,
  or change the framing with `-0`.
- **`--jsonrpc` re-frames typed input** as JSON-RPC 2.0 method calls, which is
  what you want against a JSON-RPC-over-WebSocket endpoint and wrong against
  anything else.
- **Nothing is written to disk unless you redirect it.** Redirect to `$WORK`, and
  cap the volume:

  ```bash
  timeout 60 websocat -q "wss://$TARGET/ws" < /dev/null \
    | tee "$WORK/ws/stream.txt" | wc -l
  ```

  A frame count of `0` with no error is ambiguous: the endpoint may have closed
  immediately, or the server may simply have had nothing to say. Re-run without
  `-q` to see whether the handshake succeeded.

## Chaining with the rest of the toolchain

- **mitmproxy → websocat.** `mitmdump` is where the WebSocket handshake is
  visible — the cookies, the `Origin`, and the subprotocol are the things you
  need to reproduce the connection outside a browser. Whether mitmproxy 11.0.0
  can rewrite individual WebSocket frames here, and with which options, is
  **unverified** in this image: check `/tools/mitmproxy/AGENTS.md` and
  `mitmdump --help` rather than assuming frame rewriting works.
- **httpx → websocat.** `httpx -ws` reports whether a host advertises WebSocket
  support; that is the cheap discovery step before opening a socket.
- **nuclei → websocat.** Nuclei's `-pt websocket` protocol filter selects
  WebSocket templates; when one of them indicates a live endpoint, websocat is
  how you look at the actual frames.
- **websocat → Python `websocket-client` / `websockets`.** Once the framing is
  understood, message-level fuzzing belongs in Python. The image has no
  websocket-tool venv, so whether either library is importable from the general
  environment is **unverified** — check before writing a long script:

  ```bash
  python3 -c 'import websocket; print(websocket.__version__)'   # websocket-client
  python3 -c 'import websockets; print(websockets.__version__)' # websockets
  ```

  Neither import is guaranteed. If both fail, the tool is not installed yet:
  that is a capability decision, not something to work around by hand-rolling a
  frame parser.

## Limits, failure modes and gotchas

- **Scheme must match the origin.** `websocat ws://host/ws` against an `https://`
  origin fails: the plaintext handshake is sent to a TLS port. Use `wss://` for
  an `https://` origin and `ws://` for an `http://` one.
- **TLS verification is not off by default.** A `wss://` target with a bad or
  self-signed certificate will refuse the connection, and you will need this
  build's own TLS options to proceed. They are **not listed in this document** —
  enumerate them with `websocat --help=long`. Do not assume a bypass flag from a
  blog post exists, and do not treat a certificate rejection as "the endpoint is
  down".
- **A relay with no end hangs forever.** If the command produces output and then
  sits there, the input side never reached EOF. That is not a target problem:
  add `-1`, `-E`, or feed it a file, and re-run under `timeout` while you are
  learning the endpoint's behaviour.
- **A hung websocat keeps a session alive on the server.** A `timeout`-killed
  client can leave the server's session open until its own idle timeout, which
  matters when you are counting active sessions or testing session limits.
- **Line orientation splits messages.** Binary frames, frames containing
  newlines, and pretty-printed JSON all arrive mangled under the default framing.
  Use `-0` for binary and expect to reassemble multi-line JSON.
- **`-q` hides the connection diagnostics, not just the banner.** A silent
  failure — connection refused, handshake rejected, certificate error — looks
  identical to "the server sent nothing" once `-q` is on.
- **`--jsonrpc` changes the outbound framing.** Against a non-JSON-RPC endpoint
  it will produce messages the server rejects, and the rejection may be a silent
  close.
- **`-e` sets environment variables from attacker-controlled input.** `-e` parses
  lines from the input side into environment for the command on the other side.
  Against untrusted data, that feeds target-controlled values into a process
  environment — do not use `-e` with a command that interprets its environment.
- **Server mode is one flag away and is a new listening socket.** `-s port` binds
  a port in the container's namespace. Nothing in this image expects an inbound
  connection; do not start one.
- **No built-in fuzzer.** There is no wordlist option, no mutation engine, no
  replay. If the task is "send 10,000 malformed frames", websocat is the wrong
  tool and Python is the right one.
- **SSE has no dedicated tool.** Do not try to force websocat at a
  `text/event-stream` endpoint; use `curl -N`.

## Safety and scope

- **Confirm the endpoint before the first frame.** A WebSocket connection is
  authenticated interaction with a live application. The handshake alone may
  create a session; frames can create data, trigger work, or disturb other users
  on a shared channel.
- **Do not start `-s`.** Server mode opens a listener in a container whose whole
  design is outbound-only. It is not needed for any documented workflow here, and
  it must never be used to receive a relayed target socket.
- **Keep both ends of a relay yours.** Advanced mode can expose a target's traffic
  to anything that connects. Only ever relay between addresses in scope, and
  never expose one to a listener you do not control.
- **Bound every run.** `timeout`, `-1`, `-E`, and a line cap on the output. An
  unbounded websocat holds a live session open, fills `$WORK`, and is easy to
  mistake for a hung tool.
- **Treat captures as credential material.** Handshake headers, frames, and any
  token seen in them stay in `$WORK` with the rest of the evidence, and out of
  the transcript.
- **Python for message-level fuzzing, mitmproxy for interception.** Those are the
  tools for the parts websocat does not do — and for the frame-rewriting part,
  confirm the mechanism in `mitmproxy`'s own documentation in this image before
  relying on it. websocat's job is the framing, the relay, and the first honest
  look at the protocol.
