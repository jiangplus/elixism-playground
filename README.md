# Playground

A small **Phoenix** API app (no HTML, no JS/assets, no database) that doubles as
a test bed for [**Elixism**](../elixism) — a from-scratch compiler that runs a
subset of Elixir on WebAssembly.

There are two things in this repo:

| Path | What it is |
|------|------------|
| `lib/`, `config/`, `mix.exs`, … | the **real Phoenix app**, built and run by `mix` on the BEAM |
| [`elixism/`](elixism/) | the same app's *shape* ported to **Elixism**, runnable on the host VM and served over HTTP from **WebAssembly** |

---

## Run the real Phoenix app (mix / BEAM)

Standard Phoenix. Needs Elixir + Erlang/OTP.

```sh
mix setup            # install & compile dependencies
mix phx.server       # start the endpoint on http://localhost:4000
# or inside IEx:  iex -S mix phx.server
```

It's an API-only app (`--no-html --no-assets --no-ecto`), so there's no web page
to visit — it exposes the JSON endpoints under `/api` defined in
`lib/playground_web/router.ex`.

---

## Run Playground on Elixism

Real Phoenix can't compile on Elixism — it's a macro framework on the BEAM
(`@`-attributes, `use Phoenix.*`, `defmacro`/`quote`, Plug/Bandit sockets), none
of which Elixism has. So [`elixism/`](elixism/) ports the *shape* of the app —
Router → Controller → JSON, plus a supervised endpoint — into the Elixir subset
Elixism does support. See [`elixism/README.md`](elixism/README.md) for the full
write-up (and the two Elixism compiler bugs this surfaced and fixed).

There are two ways to run it.

### 1. Host VM — the supervised OTP demo

Runs Router → GenServer endpoint → Controller, under a Supervisor, directly on
Guile. Needs only **Guile 3** (`brew install guile` / `apt install guile-3.0`).

```sh
cd ../elixism
./bin/exc run ../playground/elixism/playground_elixism.ex
```

```
endpoint up, serving /api ...
GET /api/health -> 200 %{status: "ok"}  (req #1)
GET /api/hello  -> 200 %{hello: "Elixism"}  (req #2)
POST /api/echo  -> 200 %{echo: "ping"}  (req #3)
DELETE /api/nope -> 404 %{error: "not found"}  (req #4)
```

### 2. WebAssembly — serve real HTTP from Node

Compiles the app to `program.wasm` and runs a Node server that routes live HTTP
requests through the Wasm-compiled Elixir handler. Needs **Guile 3 + the Hoot
toolchain** (`../../hoot`, built with `make`) and **Node 22+**.

```sh
cd elixism/wasm
./build.sh            # bundle + compile playground_app.ex -> program.wasm
node server.js        # serve on http://localhost:4000  (PORT=8080 to change)
```

Then from another shell:

```sh
curl -s localhost:4000/api/health                # {"status":"ok"}
curl -s 'localhost:4000/api/hello?name=Phoenix'  # {"hello":"Phoenix"}
curl -s localhost:4000/api/users                 # {"users":[...]}
curl -s -X POST -d 'hi' localhost:4000/api/echo  # {"echo":"hi"}
```

Stop the server with `Ctrl-C` (or `pkill -f server.js`).

### Which is which

| | Runs on | Demonstrates |
|---|---------|--------------|
| `elixism/playground_elixism.ex` | host Guile | Supervisor + GenServer + `&Mod.fun/1` routing (the OTP/process layer) |
| `elixism/wasm/` | Node + WebAssembly | the pure request pipeline (`playground_app.ex`) serving real HTTP |

---

## Learn more

* Phoenix: https://www.phoenixframework.org/ · https://hexdocs.pm/phoenix
* Elixism: [`../elixism/README.md`](../elixism/README.md)
* Guile Hoot (Scheme → WebAssembly): https://spritely.institute/hoot/
