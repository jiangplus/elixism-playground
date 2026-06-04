<!-- SPDX-License-Identifier: Apache-2.0 -->
# Playground on WebAssembly — an HTTP server

This serves real HTTP requests from **Elixir code compiled to WebAssembly** by
[Elixism](../../../elixism). Node.js owns the socket; every request is handed to
the Wasm module's pure handler and the JSON reply is sent back.

```
  HTTP request                                   JSON response
       │                                               ▲
       ▼                                               │
┌──────────────┐   handler.call(method,url,body)  ┌────┴───────────────────────┐
│ Node http    │ ───────────────────────────────▶ │ program.wasm               │
│ createServer │ ◀─────────────────────────────── │  Playground.Endpoint.handle │
└──────────────┘     JSON string {status, body}   │  Router → Controller → JSON │
   (transport)                                     │  (compiled Elixir, in Wasm) │
                                                   └─────────────────────────────┘
```

The app itself is [`../playground_app.ex`](../playground_app.ex): a `Router`,
a `PageController`, a hand-written `JSON` encoder, and a pure
`Endpoint.handle/3` — all ordinary Elixir, compiled by Elixism. There is **no
BEAM and no Plug**; the "plug pipeline" is just a function `conn -> {status,
body}`, which is what makes it portable to Wasm.

## Run it

Requires Node 22+ and the Hoot toolchain (tested with **Hoot 0.9.0**; build the
`../../../hoot` checkout with `make`).

```sh
./build.sh          # bundle + compile ../playground_app.ex to program.wasm
node server.js      # serve on http://localhost:4000  (PORT=8080 to change)
```

Then, from another shell:

```console
$ curl -s localhost:4000/
{"routes":["/api/health","/api/hello?name=...","/api/users","POST /api/echo"],"runtime":"Elixism on WebAssembly","app":"Playground"}

$ curl -s localhost:4000/api/health
{"status":"ok"}

$ curl -s 'localhost:4000/api/hello?name=Phoenix'      # query param parsed in Wasm
{"hello":"Phoenix"}

$ curl -s localhost:4000/api/users                     # nested arrays/objects
{"users":[{"role":"engineer","name":"Alice","id":1},{"role":"designer","name":"Bob","id":2}]}

$ curl -s -X POST -d 'hi' localhost:4000/api/echo      # request body
{"echo":"hi"}

$ curl -s -o /dev/null -w '%{http_code}\n' localhost:4000/nope   # 404 status
404
```

## How it works

- **`build.sh`** runs Elixism's `wasm-node/bundle.scm` in *handler mode*: it
  flattens the Elixism runtime, AOT-compiles `playground_app.ex`, and makes the
  program's final value the procedure `(method path body) -> json-string`. Hoot
  then compiles that to `program.wasm`.
- **`server.js`** calls `Scheme.load_main` (Hoot's `reflect.js`), finds the
  returned handler procedure, and calls it for each HTTP request. Two Hoot-0.9
  details are handled automatically:
  - **exnref.** Hoot 0.9 output uses the Wasm `exnref` opcodes; the server
    re-execs Node with `--experimental-wasm-exnref`.
  - **mutable strings.** Elixism builds strings with `string-append`, which Hoot
    reflects as a `MutableString` wrapper; `server.js` coerces it to a native
    JS string before `JSON.parse`.

## Scope

The request path is **pure** (no processes), which is exactly why it ports to
Wasm cleanly. State across requests (the request counter, etc.) lives in the
Node transport. The fiber/process layer (`spawn`/`receive`/GenServer/Supervisor)
is exercised by the host demo [`../playground_elixism.ex`](../playground_elixism.ex)
and the parent suite (`make test` in `elixism/`); porting the scheduler into
Wasm is tracked as future work in the Elixism design docs.
