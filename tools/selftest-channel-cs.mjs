// The channel on the C# target, end to end: builds tests-cs/probe.hxml (a headless HaxeUI app serving
// Start.open), launches it, and drives it through the real socket. Needs haxe, dotnet and haxeui-cs.
// Run from the repo root: node tools/selftest-channel-cs.mjs        (SKIP_BUILD=1 reuses bin/probe)
import { spawn, execSync } from "node:child_process";
import net from "node:net";
import { existsSync, mkdirSync, readFileSync, rmSync } from "node:fs";
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
let appExit = null;
exited.then((c) => { appExit = c ?? "signal"; });
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
  while (!existsSync(file) && appExit === null && Date.now() < deadline) await sleep(100);
  ok(existsSync(file), "the app wrote drive.json");
  if (!existsSync(file)) throw new Error(appExit === null ? "drive.json never appeared" : `the app exited (${appExit}) before writing drive.json`);
  const { port, token } = JSON.parse(readFileSync(file, "utf8"));
  const rawConnect = async () => { const s = net.connect(port, "127.0.0.1"); s.on("error", () => {}); await new Promise((r) => s.once("connect", r)); return s; };
  const line = (id, cmd, args) => JSON.stringify({ id, token, cmd, args }) + "\n";
  const until = async (f, ms) => { const end = Date.now() + ms; while (!f() && Date.now() < end) await sleep(25); return f(); };
  /** The next client is served within a second (a stuck or abusive one has been let go). */
  const servedNext = async () => {
    const t = Date.now();
    const n = await open();
    const r = await code(n.send("find", { target: "#table" }));
    const took = Date.now() - t;
    n.close(); clients.splice(clients.indexOf(n), 1); await sleep(150);
    return { served: r === null && took < 1000, r, took };
  };

  // The reply text itself: JSON.parse cannot tell 10 from 10.0, and a C# Json printer can write the latter.
  {
    const s = await rawConnect();
    const p = rawLine(s);
    s.write(line(1, "find", { target: "#table" }));
    const raw = await p;
    s.destroy(); await sleep(150);
    ok(raw !== null && /"x":10[,}]/.test(raw) && /"y":20[,}]/.test(raw) && /"w":300[,}]/.test(raw) && /"h":200[,}]/.test(raw)
      && /"id":"table"/.test(raw), `find answers the table's node with whole numbers on the wire (${raw})`);
  }
  // A request split inside a two-byte character: the halves are put back together before decoding.
  {
    const s = await rawConnect();
    const p = rawLine(s);
    const bytes = Buffer.from(line(2, "find", { target: "text:é" }), "utf8");
    const at = bytes.indexOf(0xc3) + 1;
    s.write(bytes.subarray(0, at));
    await sleep(250);   // several frames: the first half has been read and kept
    s.write(bytes.subarray(at));
    const raw = await p;
    s.destroy(); await sleep(150);
    let got = null;
    try { got = JSON.parse(raw).result.id; } catch {}
    ok(got === "é", `a character split across two writes arrives whole (${raw})`);
  }

  let a = await open();
  const found = await a.send("find", { target: "#table" });
  ok(found.id === "table" && found.source === "table", "find answers the table's node through the client");

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

  // A client that asks for 12 MB and reads none of it: its outbox passes the limit (4 MB), it is cut off,
  // and the next client is served - the UI thread never waited on it.
  {
    const stuck = await rawConnect();
    stuck.pause();
    for (let i = 1; i <= 8; i++) stuck.write(line(i, "state", { big: 1500000 }));
    await sleep(1500);
    const next = await servedNext();
    ok(next.served, `a client that never reads is cut off, and the next is served (${next.r ?? "served"} after ${next.took} ms)`);
    let closed = false;
    stuck.on("close", () => { closed = true; });
    stuck.resume();
    ok(await until(() => closed, 5000), "the stuck client's connection was closed by the app");
    stuck.destroy();
  }

  // A request line that never ends: past 1 MiB with no newline, the connection is closed.
  {
    const s = await rawConnect();
    let closed = false;
    s.on("close", () => { closed = true; });
    const chunk = Buffer.alloc(64 * 1024, 97);
    for (let i = 0; i < 20 && !closed; i++) { s.write(chunk); await sleep(10); }
    ok(await until(() => closed, 5000), "a request line over 1 MiB with no end closes the connection");
    s.destroy();
    await sleep(150);
    const next = await servedNext();
    ok(next.served, `the next client is served after it (${next.r ?? "served"} after ${next.took} ms)`);
  }

  // A reader that stalls: 3 MB of replies back up behind a client that is not reading, so the app
  // cannot write them at once: its outbox backs up across ticks; once the client reads, both arrive whole.
  {
    const s = await rawConnect();
    s.pause();
    s.write(line(1, "state", { big: 1500000 }) + line(2, "state", { big: 1500000 }));
    await sleep(1500);
    let text = "";
    s.setEncoding("utf8");
    s.on("data", (d) => { text += d; });
    const t = Date.now();
    s.resume();
    await until(() => text.split("\n").length >= 3, 8000);
    const replies = text.split("\n").filter((l) => l !== "").map((l) => { try { return JSON.parse(l); } catch { return null; } });
    ok(replies.length === 2 && replies.every((r) => r && r.ok && r.result.blob.length === 1500000 && /^x+$/.test(r.result.blob)),
      `replies held up behind a stalled reader arrive whole (${replies.length} replies, ${Date.now() - t} ms after it read)`);
    s.destroy();
    await sleep(150);
  }

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
if (failures || process.env.SHOW_OUTPUT) console.log("--- probe output ---\n" + out.slice(-3000));
console.log(failures === 0 ? "selftest passed" : `selftest: ${failures} failed`);
process.exit(failures === 0 ? 0 : 1);
