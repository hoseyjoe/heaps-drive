// The heaps-drive client (heaps-drive spec §1). Every command is injected inside the app, so the
// user's cursor, keyboard and focus are never touched.
//
// CLI:    node tools/drive.mjs [--file path/to/drive.json] <cmd> ['<json args>']
//         prints the result; exit 1 and the error (and any candidates / lastSeen) when not ok.
//         The file defaults to $DRIVE_JSON, else ./drive.json.
// Module: const app = await connect("bin/drive/drive.json"); await app.send("click", { target: "text:Go" }); app.close();
//
// Commands: tree [within] | find target | click target [right double force] | type target text |
//   key name | wheel target notches | drag from to | wait condition [timeoutMs] |
//   shot file [within] | state [app args] | resize w h | quit
// Targets: "#id", "text:Exact", "text~:part" (any case), "name:objectName", an app's own prefixes,
//   or { target, within }. Errors: not_found, ambiguous (with candidates), occluded (force: true
//   clicks anyway), disabled, bad_request, timeout (with lastSeen), unauthorized, busy, internal.
// Each request times out on this side after its timeoutMs (wait) plus 10 s, or 15 s, so a hung app
// cannot hang the caller: the request is rejected with code "client_timeout".
import net from "node:net";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { resolve } from "node:path";

export async function connect(file) {
  const { port, token } = JSON.parse(readFileSync(file, "utf8"));
  const socket = net.connect(port, "127.0.0.1");
  await new Promise((res, rej) => { socket.once("connect", res); socket.once("error", rej); });
  socket.setEncoding("utf8");
  let buffer = "", nextId = 1;
  const waiting = new Map();
  socket.on("data", (chunk) => {
    buffer += chunk;
    let nl;
    while ((nl = buffer.indexOf("\n")) >= 0) {
      const line = buffer.slice(0, nl);
      buffer = buffer.slice(nl + 1);
      const oldest = waiting.get([...waiting.keys()][0]);
      let reply;
      try { reply = JSON.parse(line); } catch {
        // Replies come in request order, so an unreadable one belongs to the oldest request.
        if (oldest) { waiting.delete(oldest.id); oldest.reject(new Error(`unreadable reply from the app: ${line.slice(0, 200)}`)); }
        else console.warn(`drive-app: ignored an unreadable line from the app: ${line.slice(0, 200)}`);
        continue;
      }
      // Only id 0 (busy, or a line the app could not read) falls back to the oldest request.
      const w = reply.id === 0 ? oldest : waiting.get(reply.id);
      if (!w) { console.warn(`drive-app: ignored a reply for no outstanding request (id ${reply.id})`); continue; }
      waiting.delete(w.id);
      if (reply.ok) w.resolve(reply.result);
      else w.reject(Object.assign(new Error(`${reply.code}: ${reply.error}`), reply));
    }
  });
  socket.on("error", () => {});   // reported through "close"
  socket.on("close", () => { for (const w of waiting.values()) w.reject(new Error("the app closed the connection")); waiting.clear(); });
  return {
    send(cmd, args = {}) {
      const id = nextId++;
      if (cmd === "shot" && typeof args.file === "string") args = { ...args, file: resolve(args.file) };
      const limit = typeof args.timeoutMs === "number" ? args.timeoutMs + 10000 : 15000;
      return new Promise((resolve, reject) => {
        const timer = setTimeout(() => {
          waiting.delete(id);
          reject(Object.assign(new Error(`client_timeout: no reply to ${cmd} within ${limit} ms`), { code: "client_timeout" }));
        }, limit);
        const settle = (f) => (v) => { clearTimeout(timer); f(v); };
        waiting.set(id, { id, resolve: settle(resolve), reject: settle(reject) });
        socket.write(JSON.stringify({ id, token, cmd, args }) + "\n");
      });
    },
    close() { socket.end(); socket.unref(); },   // unref: a hung app cannot keep this process alive
  };
}

/** Runs one command from argv against `file`; the exit code says whether it was ok. */
export async function cli(file, argv = process.argv.slice(2)) {
  const at = argv.indexOf("--file");
  if (at >= 0) { file = argv[at + 1]; argv = argv.filter((_, i) => i !== at && i !== at + 1); }
  file = file ?? process.env.DRIVE_JSON ?? "drive.json";
  const [cmd, json] = argv;
  if (!cmd) { console.error("usage: node drive.mjs [--file drive.json] <cmd> ['<json args>']"); process.exitCode = 2; return; }
  let app;
  try { app = await connect(file); }
  catch (e) {
    console.error(`cannot reach the app through ${file} (${e.code ?? e.message}): is the driven build running? A drive.json left by a crashed run points at a dead port.`);
    process.exitCode = 1;
    return;
  }
  try { console.log(JSON.stringify(await app.send(cmd, json ? JSON.parse(json) : {}), null, 2)); }
  catch (e) {
    console.error(e.message);
    if (e.candidates) console.error(JSON.stringify(e.candidates, null, 2));
    if (e.lastSeen !== undefined) console.error("lastSeen: " + JSON.stringify(e.lastSeen, null, 2));
    process.exitCode = 1;
  }
  finally { app.close(); }
}

if (process.argv[1] && resolve(fileURLToPath(import.meta.url)) === resolve(process.argv[1])) await cli(undefined);
