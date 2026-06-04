# Playground — the pure web app, shared by the host OTP demo and the Wasm
# HTTP server. No processes here: a request is a pure function
#   Endpoint.handle(method, path, body) -> JSON string
# which is exactly Phoenix's "a plug is conn -> conn", minus the macro DSL.
#
# This file defines modules only (no top-level call), so it can be compiled
# into either target.

defmodule Playground.JSON do
  # A tiny JSON encoder (enough for maps/lists/strings/numbers/atoms), written
  # in Elixir and compiled by Elixism. Demonstrates recursion, guards, the
  # pipe, Enum, and the now-fixed &local/1 capture.
  def encode(term), do: enc(term)

  defp enc(nil), do: "null"
  defp enc(true), do: "true"
  defp enc(false), do: "false"
  defp enc(x) when is_integer(x), do: Integer.to_string(x)
  defp enc(x) when is_binary(x), do: "\"" <> escape(x) <> "\""
  defp enc(x) when is_atom(x), do: "\"" <> to_string(x) <> "\""
  defp enc(x) when is_list(x), do: "[" <> Enum.join(Enum.map(x, &enc/1), ",") <> "]"
  defp enc(x) when is_map(x), do: enc_map(x)

  defp enc_map(m) do
    body =
      m
      |> Map.to_list()
      |> Enum.map(fn {k, v} -> enc_key(k) <> ":" <> enc(v) end)
      |> Enum.join(",")

    "{" <> body <> "}"
  end

  defp enc_key(k) when is_binary(k), do: "\"" <> escape(k) <> "\""
  defp enc_key(k), do: "\"" <> to_string(k) <> "\""

  defp escape(s) do
    s
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
    |> String.replace("\n", "\\n")
  end
end

defmodule Playground.Router do
  # Phoenix's `scope "/api" do get "/health", ... end` becomes a pattern-matched
  # function returning the controller action atom. (Elixism has no router DSL.)
  def route("GET", "/"), do: :index
  def route("GET", "/api/health"), do: :health
  def route("GET", "/api/hello"), do: :hello
  def route("GET", "/api/users"), do: :users
  def route("POST", "/api/echo"), do: :echo
  def route(_method, _path), do: :not_found
end

defmodule Playground.PageController do
  # Each action: conn (a map) -> {status, body_map}. Phoenix dispatches action
  # atoms via apply/3; Elixism has neither apply nor (until now) captures, so we
  # pattern-match the action atom explicitly.
  def dispatch(:index, conn), do: index(conn)
  def dispatch(:health, conn), do: health(conn)
  def dispatch(:hello, conn), do: hello(conn)
  def dispatch(:users, conn), do: users(conn)
  def dispatch(:echo, conn), do: echo(conn)
  def dispatch(:not_found, conn), do: not_found(conn)

  def index(_conn) do
    {200,
     %{
       app: "Playground",
       runtime: "Elixism on WebAssembly",
       routes: ["/api/health", "/api/hello?name=...", "/api/users", "POST /api/echo"]
     }}
  end

  def health(_conn), do: {200, %{status: "ok"}}

  def hello(conn) do
    name = Map.get(Map.get(conn, :query, %{}), "name", "world")
    {200, %{hello: name}}
  end

  def users(_conn) do
    {200,
     %{
       users: [
         %{id: 1, name: "Alice", role: "engineer"},
         %{id: 2, name: "Bob", role: "designer"}
       ]
     }}
  end

  def echo(conn), do: {200, %{echo: Map.get(conn, :body, "")}}

  def not_found(conn) do
    {404, %{error: "not found", method: Map.get(conn, :method), path: Map.get(conn, :path)}}
  end
end

defmodule Playground.Endpoint do
  # The pure request pipeline: split off any query string, build a conn map,
  # route to a controller, and JSON-encode {status, body}. Returns a JSON
  # string the transport (Node http server, or the host) turns into a response.
  def handle(method, raw_path, body) do
    {path, query} = split_path(raw_path)

    conn = %{method: method, path: path, query: query, body: body}

    action = Playground.Router.route(method, path)
    {status, payload} = Playground.PageController.dispatch(action, conn)

    Playground.JSON.encode(%{status: status, body: payload})
  end

  defp split_path(raw) do
    case String.split(raw, "?") do
      [path] -> {path, %{}}
      [path, qs] -> {path, parse_query(qs)}
      [path | _rest] -> {path, %{}}
    end
  end

  defp parse_query(qs) do
    qs
    |> String.split("&")
    |> Enum.reduce(%{}, fn pair, acc ->
      case String.split(pair, "=") do
        [k, v] -> Map.put(acc, k, v)
        _ -> acc
      end
    end)
  end
end
