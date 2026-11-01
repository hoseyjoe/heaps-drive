// The channel on the C# target, end to end: builds tests-cs/probe.hxml (a headless HaxeUI app serving
// Start.open), launches it, and drives it through the real socket. Needs haxe, dotnet and haxeui-cs.
// Run from the repo root: node tools/selftest-channel-cs.mjs        (SKIP_BUILD=1 reuses bin/probe)
import { spawn, execSync } from "node:child_process";
import net from "node:net";
import { existsSync, mkdirSync, rmSync } from "node:fs";
import { join, resolve } from "node:path";
import { connect } from "./drive.mjs";

const dir = resolve("bin/selftest-cs");
rmSync(dir, { recursive: true, force: true });
mkdirSync(dir, { recursive: true });
const file = join(dir, "drive.json");
let failures = 0;
const ok = (cond, what) => { console.log(`${cond ? "ok  " : "FAIL"} - ${what}`); if (!cond) failures++; };
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const never = (ms, v) => new Promise((r) => setTimeout(() => r(v), ms));
const code = async (p) => { try { await p; return null; } catch (e) { return e.code ?? e.message; } };

if (!process.env.SKIP_BUILD) execSync("haxe tests-cs/probe.hxml", { stdio: "inherit" });
const dll = resolve("bin/probe/bin/Debug/net10.0/ChannelProbe.dll");
if (!existsSync(dll)) { console.log(`FAIL - the probe was not built (${dll})`); process.exit(1); }

let out = "";
const app = spawn("dotnet", [dll], { env: { ...process.env, DRIVE_DIR: dir }, stdio: ["ignore", "pipe", "pipe"], windowsHide: true });
app.stdout.setEncoding("utf8"); app.stderr.setEncoding("utf8");
app.stdout.on("data", (s) => { out += s; }); app.stderr.on("data", (s) => { out += s; });
const exited = new Promise((r) => app.on("exit", r));
// A run ends by itself: whatever hangs, the child dies by its PID and the run fails.
const watchdog = setTimeout(() => {
  console.log("FAIL - the selftest took over 90 s; killing the probe");
  try { process.kill(app.pid); } catch {}
  process.exit(1);
}, 90000);
const clients = [];
const open = async () => { const c = await connect(file); clients.push(c); return c; };

/** One line off a raw socket (for the replies a client library would not show), or null on close/timeout. */
const rawLine = (s, ms = 3000) => new Promise((res) => {
  let buf = "";
  const t = setTimeout(() => res(null), ms);
  s.setEncoding("utf8");
  s.on("data", (d) => { buf += d; const nl = buf.indexOf("\n"); if (nl >= 0) { clearTimeout(t); res(buf.slice(0, nl)); } });
  s.on("close", () => { clearTimeout(t); res(buf.includes("\n") ? buf.slice(0, buf.indexOf("\n")) : null); });
  s.on("error", () => {});
});

try {
  const deadline = Date.now() + 40000;
  while (!existsSync(file) && Date.now() < deadline) await sleep(100);
  ok(existsSync(file), "the app wrote drive.json");
  if (!existsSync(file)) throw new Error("drive.json never appeared");
  const { port, token } = JSON.parse((await import("node:fs")).readFileSync(file, "utf8"));

  let a = await open();
  const found = await a.send("find", { target: "#table" });
  ok(found.id === "table" && found.source === "table" && [found.x, found.y, found.w, found.h].every(Number.isInteger)
    && found.x === 10 && found.y === 20 && found.w === 300 && found.h === 200, `find answers the table's node with whole numbers (${JSON.stringify([found.x, found.y, found.w, found.h])})`);

  await a.send("wheel", { target: "#table", notches: 2 });
  const log = (await a.send("state")).log;
  ok(log.includes("wheel 160,120 2"), `wheel with notches 2 reached the input (${JSON.stringify(log)})`);

  let t0 = Date.now();
  const timedOut = await code(a.send("wait", { condition: { exists: "#never" }, timeoutMs: 200 }));
  let took = Date.now() - t0;
  ok(timedOut === "timeout" && took >= 150 && took <= 1000, `wait timeoutMs 200 times out in 150-1000 ms (${timedOut} after ${took} ms)`);

  // A timeoutMs that is not a number falls back to the 5 s default, as on HashLink: the condition that
  // holds is answered, and the one that never does is not given up on within a second.
  const quick = await a.send("wait", { condition: { exists: "#table" }, timeoutMs: "x" }).then(() => "ok", (e) => e.code ?? e.message);
  ok(quick === "ok", `wait with timeoutMs "x" answers a condition that holds (${quick})`);
  t0 = Date.now();
  const slow = await Promise.race([a.send("wait", { condition: { exists: "#never" }, timeoutMs: "x" }).then(() => "answered", (e) => e.code ?? e.message), never(1500, "pending")]);
  ok(slow === "pending", `wait with timeoutMs "x" on a never-true condition is still waiting after 1.5 s (${slow})`);

  // The wait above still holds the session; a second client is turned away while it is connected.
  const second = net.connect(port, "127.0.0.1");
  const busy = await rawLine(second);
  second.destroy();
  ok(busy !== null && JSON.parse(busy).code === "busy", `a second client is answered busy (${busy})`);
  a.close(); clients.splice(clients.indexOf(a), 1);

  // The client has gone mid-wait: the app lets go of it, and the next one is served within a second.
  t0 = Date.now();
  const b = await open();
  const again = await code(b.send("find", { target: "#table" }));
  took = Date.now() - t0;
  ok(again === null && took < 1000, `a reconnect is served within a second (${again ?? "served"} after ${took} ms)`);
  b.close(); await sleep(100);
  const wrong = net.connect(port, "127.0.0.1");
  wrong.write(JSON.stringify({ id: 7, token: "not-the-token", cmd: "find", args: { target: "#table" } }) + "\n");
  const unauth = await rawLine(wrong);
  wrong.destroy();
  ok(unauth !== null && JSON.parse(unauth).code === "unauthorized" && JSON.parse(unauth).id === 7, `a wrong token is unauthorized (${unauth})`);

  await sleep(100);
  const c = await open();
  const t1 = Date.now();
  const big = await c.send("state", { big: 1500000 });
  ok(big.blob.length === 1500000 && /^x+$/.test(big.blob), `a reply of 1.5 MB arrives whole (${big.blob.length} chars, ${Date.now() - t1} ms)`);

  await c.send("quit");
  c.close();
  const exitCode = await Promise.race([exited, never(10000, "timeout")]);
  ok(exitCode === 0, `quit ended the process (code ${exitCode})`);
  ok(!existsSync(file), "quit removed drive.json");
  ok(!/tick failed/.test(out), "the channel's tick did not fail after cleanup");
  if (/tick failed/.test(out)) console.log(out.split("\n").filter((l) => /tick failed/.test(l)).slice(0, 3).join("\n"));
} catch (e) {
  console.log(`FAIL - ${e.stack ?? e}`);
  failures++;
} finally {
  clearTimeout(watchdog);
  for (const c of clients) c.close();
  if (app.exitCode === null && app.signalCode === null) {
    console.log("(killing the probe by PID)");
    try { process.kill(app.pid); } catch {}
  }
}
if (failures) console.log("--- probe output ---\n" + out.slice(-3000));
console.log(failures === 0 ? "selftest passed" : `selftest: ${failures} failed`);
process.exit(failures === 0 ? 0 : 1);
