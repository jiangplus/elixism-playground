# Playground on Elixism — can a Phoenix app build with Elixism?

`playground/` is a **real Phoenix app** (`mix phx.new playground --no-html
--no-assets --no-ecto --no-mailer --no-dashboard`). It compiles and boots under
the real Elixir/OTP toolchain (`mix compile`, `mix phx.server`).

The question here was: can [Elixism](../../elixism) — the from-scratch
Elixir→Scheme→WebAssembly compiler — build that Phoenix app?

## Verdict: no, and the gap is categorical, not incremental

Feeding each generated file to `elixism` (`exc compile`) gives:

| File | Result with Elixism |
|------|---------------------|
| `lib/playground.ex` | parse error: `unexpected operator "@"` (line 2, `@moduledoc`) |
| `lib/playground/application.ex` | parse error: `unexpected operator "@"` (line 4, `@moduledoc`) |
| `lib/playground_web.ex` | parse error: `unexpected operator "@"` (line 2) |
| `lib/.../endpoint.ex` | parse error at `@session_options` |
| `lib/.../telemetry.ex` | parse error: `unexpected operator "@"` (line 9, `@impl`) |
| `lib/.../error_json.ex` | parse error at `@moduledoc` |
| `lib/.../gettext.ex` | parse error: `unexpected operator "@"` (line 2) |
| `lib/.../router.ex` | "parses", but only because Elixism turns the router DSL (`pipeline`, `scope`, `pipe_through`, `plug`) into calls to functions that don't exist — it would fail at link/run time |

The very first token Elixism hits — `@` — isn't in its grammar. But fixing the
parser wouldn't help, because Phoenix is built on layers Elixism doesn't have:

1. **Module attributes** — `@moduledoc`, `@impl`, `@session_options`. Elixism's
   parser has no `@` operator at all.
2. **The macro programming model** — every file is `use Phoenix.Endpoint` /
   `use Phoenix.Router` / `use Application` / `use Gettext.Backend`. `use`
   invokes a compile-time `__using__/1` macro that *injects code*. Elixism
   accepts exactly one `use` (`use GenServer`, which it ignores); it has no
   general macro expansion.
3. **`defmacro` / `quote` / `unquote`** — `playground_web.ex` literally defines
   macros that `quote` a block and splice `unquote(verified_routes())`. Elixism
   has no `quote`.
4. **Compile-time DSLs** — `plug ...`, `pipeline :api do ... end`,
   `scope "/api" do ... end`, `summary(...)`/`sum(...)` from
   `Telemetry.Metrics`. These are macros that build plug pipelines and route
   tables at compile time.
5. **`import`** — Elixism only auto-imports `Kernel`.
6. **The runtime** — Plug, Bandit/Cowboy (TCP sockets), `Phoenix.PubSub`,
   `:telemetry`, `gettext`, `Application.get_env`. These are BEAM libraries
   (some backed by C/NIFs and real networking). Elixism has no BEAM, and Wasm
   has no sockets.

Elixism is a clean **subset compiler**: data types, pattern matching, multi-clause
functions, structs, protocols, comprehensions, and a hand-built OTP layer
(processes/GenServer/Supervisor on fibers). Phoenix is a **macro framework on the
BEAM**. The distance between them is the entire metaprogramming + BEAM-runtime
stack, not a missing function or two.

## What Elixism *can* do: the same shape, by hand

[`playground_elixism.ex`](playground_elixism.ex) is the Playground app rebuilt in
the Elixir subset Elixism supports — same Endpoint → Router → Controller
structure, supervised, but with the macro DSL replaced by plain pattern matching:

There are two runnable artifacts, sharing the same idea:

**1. [`playground_app.ex`](playground_app.ex) — the pure web app** (also the Wasm
payload):

- `Playground.Router.route(method, path)` — Phoenix's `scope`/`get` macros become
  a pattern-matched function returning a controller action atom.
- `Playground.PageController` — actions are `conn -> {status, body}` functions
  (a "plug is a function").
- `Playground.JSON.encode/1` — a small JSON encoder written in Elixir.
- `Playground.Endpoint.handle(method, path, body)` — the pure request pipeline
  (split query string → build conn → route → JSON), returning a JSON string.

**2. [`playground_elixism.ex`](playground_elixism.ex) — the supervised OTP demo:**
wraps a `Router`/`PageController` in a `GenServer` endpoint started under a
`Supervisor` (`:one_for_one`), registered by name, with the router returning the
action as a real `&Mod.fun/1` capture.

Run the OTP demo on the host VM:

```sh
cd ../../elixism
./bin/exc run ../playground/elixism/playground_elixism.ex
```

```
endpoint up, serving /api ...
GET /api/health -> 200 %{status: "ok"}  (req #1)
GET /api/hello -> 200 %{hello: "Elixism"}  (req #2)
POST /api/echo -> 200 %{echo: "ping"}  (req #3)
DELETE /api/nope -> 404 %{error: "not found"}  (req #4)
```

## Serving real HTTP from WebAssembly

[`wasm/`](wasm/) compiles `playground_app.ex` to `program.wasm` and stands up a
Node `http.createServer` that routes **real HTTP requests through the
Wasm-compiled Elixir** (Node owns the socket; the request handler runs in Wasm):

```sh
cd wasm && ./build.sh && node server.js
# in another shell:
curl -s 'localhost:4000/api/hello?name=Phoenix'   # => {"hello":"Phoenix"}
curl -s -X POST -d hi localhost:4000/api/echo      # => {"echo":"hi"}
```

So the *architecture* of a no-frontend/no-DB Phoenix JSON app — routing requests
to controllers and rendering JSON — runs on Elixism **and serves over HTTP from
Wasm**. What still doesn't port is the **macro sugar** that lets you write it
declaratively and the **BEAM networking**; here Node supplies the transport
(exactly the fetch/socket bridge a browser would).

### Two Elixism bugs found — and fixed

Building this surfaced two compiler bugs in Elixism, both now fixed in
`../../elixism`:

- **`&Mod.fun/arity` captures invoked at the wrong arity.** The parser bound `&`
  tighter than `/`, so `&PC.health/1` parsed as *`&(PC.health) / 1`* — a division
  by 1 over a zero-arg call — and `(&PC.health/1).(conn)` raised
  `UndefinedFunctionError PC.health/0`. Fixed in `parser.scm` (fold the trailing
  `/<int>` into the capture) + `compiler.scm` (match the `(var name)` shape).
- **"Bare `receive` drops the block continuation"** turned out to be a
  *misdiagnosis* — it was the capture bug above. A broken capture made the
  endpoint's `handle_call` raise, killing the endpoint fiber and deadlocking the
  scheduler (which returns `#f`). With captures fixed, an unbound `receive`
  followed by more statements works correctly; no separate fix was needed.

## To build the *real* Phoenix on Elixism

You'd still need, in rough order: an `@`-attribute parser + attribute store;
`import`/`alias`; a real macro engine (`defmacro`/`quote`/`unquote`/`__using__`
and `use` expansion); then ports (or shims) of Plug, Phoenix.Router/Controller/
Endpoint, PubSub and telemetry. The HTTP transport, at least, is now solved —
`wasm/server.js` shows Node (or a browser's `fetch`) bridging requests into a
Wasm-compiled Elixir handler. The rest is the metaprogramming layer; this
directory marks where the boundary is today.
