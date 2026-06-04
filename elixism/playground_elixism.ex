# Playground, the Phoenix-shaped way — but runnable on Elixism.
#
# Real Phoenix can't compile on Elixism (no @-attributes, no defmacro/quote,
# no `use Phoenix.*` macro expansion, no Plug/Bandit sockets). This file keeps
# the *shape* of a Phoenix app — Endpoint -> Router -> Controller, supervised —
# expressed entirely in the Elixir subset Elixism actually supports:
# plain functions, pattern matching, function captures, GenServer, Supervisor.

defmodule Playground.PageController do
  # A "controller action" is just a function: conn (a map) -> {status, body}.
  # This is exactly Phoenix's mental model (a plug is a function), minus macros.
  def health(_conn), do: {200, %{status: "ok"}}
  def hello(conn), do: {200, %{hello: Map.get(conn, :name, "world")}}
  def echo(conn), do: {200, %{echo: Map.get(conn, :body, "")}}
  def not_found(_conn), do: {404, %{error: "not found"}}
end

defmodule Playground.Router do
  # Phoenix's `scope "/api" do get "/health", PageController, :health end`
  # becomes a pattern-matched dispatch returning the action as a function
  # capture (`&Mod.fun/1`) — Phoenix likewise treats a plug as a function value.
  def route("GET", "/api/health"), do: &Playground.PageController.health/1
  def route("GET", "/api/hello"), do: &Playground.PageController.hello/1
  def route("POST", "/api/echo"), do: &Playground.PageController.echo/1
  def route(_method, _path), do: &Playground.PageController.not_found/1
end

defmodule Playground.Endpoint do
  # The endpoint is a GenServer holding request-count state (a stand-in for the
  # telemetry/metrics a real Phoenix.Endpoint accumulates). Each "request" is a
  # synchronous call — no sockets, but the same supervised process boundary.
  use GenServer

  def start_link(reporter) do
    GenServer.start_link(Playground.Endpoint, reporter, name: Playground.Endpoint)
  end

  def request(pid, method, path, conn) do
    GenServer.call(pid, {:request, method, path, conn})
  end

  def init(reporter) do
    # Announce readiness so the app can route once we're registered (and so a
    # restart after a crash is observable) — the supervisor starts us async.
    send(reporter, {:up, self()})
    {:ok, 0}
  end

  def handle_call({:request, method, path, conn}, _from, count) do
    action = Playground.Router.route(method, path)
    {status, body} = action.(conn)
    {:reply, {status, body, count + 1}, count + 1}
  end
end

defmodule Playground.Application do
  # Mirrors lib/playground/application.ex: start the endpoint under a one_for_one
  # supervisor (Phoenix would also start Telemetry + PubSub here).
  def run() do
    me = self()

    {:ok, _sup} =
      Supervisor.start_link([{Playground.Endpoint, me}], strategy: :one_for_one)

    # Wait for the supervised endpoint to come up and register its name, then
    # route requests to it by name (Phoenix refers to the endpoint by module).
    _ready =
      receive do
        {:up, pid} -> pid
      end

    IO.puts("endpoint up, serving /api ...")
    serve("GET", "/api/health", %{})
    serve("GET", "/api/hello", %{name: "Elixism"})
    serve("POST", "/api/echo", %{body: "ping"})
    serve("DELETE", "/api/nope", %{})
  end

  defp serve(method, path, conn) do
    {status, body, n} =
      Playground.Endpoint.request(Playground.Endpoint, method, path, conn)
    IO.puts("#{method} #{path} -> #{status} #{inspect(body)}  (req ##{n})")
  end
end

Playground.Application.run()
