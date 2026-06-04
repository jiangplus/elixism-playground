// Playground HTTP server — Node.js in front, the request handler running in
// WebAssembly (compiled from Elixir by Elixism).
// SPDX-License-Identifier: Apache-2.0
//
//   node server.js            # serve on http://localhost:4000
//   PORT=8080 node server.js
//
// Architecture: Node owns the HTTP transport; each request is handed to the
// Wasm module's handler  (method, url, body) -> JSON string  and the reply is
// sent back. This is exactly Phoenix's "a plug is conn -> conn", except the
// pipeline is compiled Elixir running in Wasm rather than on the BEAM.

// Hoot 0.9 emits the Wasm exnref opcodes, which V8 gates behind a flag; re-exec
// with it so plain `node server.js` works.
const EXNREF = "--experimental-wasm-exnref";
if (!process.execArgv.includes(EXNREF)) {
  const { spawnSync } = require("child_process");
  const r = spawnSync(process.execPath, [EXNREF, __filename, ...process.argv.slice(2)], {
    stdio: "inherit",
  });
  process.exit(r.status ?? 1);
}

const http = require("http");
const { Scheme } = require("./reflect.js");
const PORT = process.env.PORT || 4000;

async function loadHandler() {
  // load_main returns the program's top-level values; the final one is our
  // handler procedure. Hoot reflects it to a JS-callable `Procedure`.
  const results = await Scheme.load_main("program.wasm", {
    reflect_wasm_dir: __dirname,
    user_imports: { host: { print: () => {} } },
  });
  const vals = Array.isArray(results) ? results : [results];
  const handler = vals.find((v) => v && typeof v.call === "function");
  if (!handler) throw new Error("wasm program did not return a handler procedure");
  return handler;
}

// Elixism builds strings with string-append, which yields *mutable* Scheme
// strings; Hoot reflects those to a MutableString wrapper rather than a native
// JS string. Coerce either form to a real string.
function toJsString(v) {
  if (typeof v === "string") return v;
  if (v && v.reflector && typeof v.reflector.string_value === "function") {
    return v.reflector.string_value(v);
  }
  return String(v);
}

async function main() {
  const handler = await loadHandler();
  let count = 0;

  const server = http.createServer((req, res) => {
    let body = "";
    req.on("data", (c) => (body += c));
    req.on("end", () => {
      count++;
      let status = 200;
      let payload;
      try {
        // Call INTO WebAssembly: returns a JSON string {"status":N,"body":...}.
        const out = toJsString(handler.call(req.method, req.url, body)[0]);
        const parsed = JSON.parse(out);
        status = parsed.status;
        payload = parsed.body;
      } catch (e) {
        status = 500;
        payload = { error: String(e) };
      }
      const text = JSON.stringify(payload);
      res.writeHead(status, {
        "content-type": "application/json",
        "x-served-by": "elixism-wasm",
      });
      res.end(text);
      console.log(`${req.method} ${req.url} -> ${status} (req #${count})`);
    });
  });

  server.listen(PORT, () => {
    console.log(`Playground (Elixir → Elixism → WebAssembly) on http://localhost:${PORT}`);
    console.log("Routes: GET / , GET /api/health , GET /api/hello?name=... , GET /api/users , POST /api/echo");
  });
}

main().catch((e) => {
  console.error("fatal:", e);
  process.exit(1);
});
