// drive.cs end to end: builds examples/HelloCs (headless, or a real Avalonia window put off every
// display), launches it, and drives it through the real socket. Needs haxe, dotnet and haxeui-cs.
//   node tools/selftest-cs.mjs <headless|window> [--scale 1.5]      (SKIP_BUILD=1 reuses the build)
// Run from the repo root. `window` opens a window on this machine's desktop that is never on a
// display and never active; the run reads that from the app after every check (state.windowActive
// and state.onDisplay) and fails if either is ever true. DRIVE_VISIBLE is never set here.
// The last part is a run of its own: an uncaught error in the app (exit, stderr, no hang).
import { spawn, execSync } from "node:child_process";
import net from "node:net";
import zlib from "node:zlib";
import { existsSync, mkdirSync, readFileSync, rmSync } from "node:fs";
import { join, resolve } from "node:path";
import { connect } from "./drive.mjs";

const mode = process.argv[2];
if (mode !== "headless" && mode !== "window") {
  console.log("usage: node tools/selftest-cs.mjs <headless|window> [--scale 1.5]");
  process.exit(2);
}
const windowMode = mode === "window";
const scaleAt = process.argv.indexOf("--scale");
const scale = scaleAt >= 0 ? Number(process.argv[scaleAt + 1]) : 1;
if (!(scale > 0)) { console.log("--scale needs a number"); process.exit(2); }
const appArgs = scaleAt >= 0 ? ["--scale", String(scale)] : [];

const hxml = windowMode ? "examples/hello-cs.hxml" : "examples/hello-cs-headless.hxml";
const dll = resolve(windowMode ? "bin/hello-cs" : "bin/hello-cs-headless", "bin/Debug/net10.0/HelloCs.dll");
const dir = resolve(`bin/selftest-cs-${mode}${scale !== 1 ? "-" + scale : ""}`);
rmSync(dir, { recursive: true, force: true });
mkdirSync(dir, { recursive: true });

let failures = 0;
const ok = (cond, what) => { console.log(`${cond ? "ok  " : "FAIL"} - ${what}`); if (!cond) failures++; return cond; };
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const never = (ms, v) => new Promise((r) => setTimeout(() => r(v), ms));
const code = async (p) => { try { await p; return null; } catch (e) { return e.code ?? e.message; } };
/** Equal as JSON values, whatever order an object's keys came in. */
const same = (a, b) => JSON.stringify(sorted(a)) === JSON.stringify(sorted(b));
const sorted = (v) => (v && typeof v === "object" && !Array.isArray(v) ? Object.fromEntries(Object.keys(v).sort().map((k) => [k, sorted(v[k])])) : v);

if (!process.env.SKIP_BUILD) execSync(`haxe ${hxml}`, { stdio: "inherit" });
if (!existsSync(dll)) { console.log(`FAIL - HelloCs was not built (${dll})`); process.exit(1); }

// Every app started here, so whatever happens the run ends and they die by their PIDs.
const children = new Set();
const watchdog = setTimeout(() => {
  console.log("FAIL - the selftest took over 150 s; killing the app");
  for (const p of children) { try { process.kill(p); } catch {} }
  process.exit(1);
}, 150000);

/** Starts HelloCs with its drive.json in `where`; its output is collected, its exit awaited. */
function launch(where, withScale = true) {
  mkdirSync(where, { recursive: true });
  const env = { ...process.env, DRIVE_DIR: where };
  delete env.DRIVE_VISIBLE;   // a human's switch for watching: never a selftest's
  const app = spawn("dotnet", [dll, ...(withScale ? appArgs : [])], { env, stdio: ["ignore", "pipe", "pipe"], windowsHide: true });
  children.add(app.pid);
  const run = { app, pid: app.pid, out: "", err: "", file: join(where, "drive.json"), exitCode: null };
  app.stdout.setEncoding("utf8"); app.stderr.setEncoding("utf8");
  app.stdout.on("data", (s) => { run.out += s; });
  app.stderr.on("data", (s) => { run.err += s; });
  run.exited = new Promise((r) => app.on("exit", (c, sig) => { run.exitCode = c ?? sig ?? "signal"; children.delete(app.pid); r(run.exitCode); }));
  return run;
}

async function ready(run) {
  const deadline = Date.now() + 40000;
  while (!existsSync(run.file) && run.exitCode === null && Date.now() < deadline) await sleep(100);
  if (!existsSync(run.file)) throw new Error(run.exitCode === null ? "drive.json never appeared" : `the app exited (${run.exitCode}) before writing drive.json\n${run.out}${run.err}`);
}

/** The PNG's pixels (8-bit RGB or RGBA, not interlaced) as {w, h, at(x, y) -> [r, g, b, a]}. */
function decodePng(buf) {
  if (buf.readUInt32BE(0) !== 0x89504e47) throw new Error("not a PNG");
  const w = buf.readUInt32BE(16), h = buf.readUInt32BE(20), depth = buf[24], type = buf[25], interlace = buf[28];
  if (depth !== 8 || (type !== 2 && type !== 6) || interlace !== 0) throw new Error(`unsupported PNG (depth ${depth}, type ${type}, interlace ${interlace})`);
  const ch = type === 6 ? 4 : 3;
  const idat = [];
  for (let at = 8; at < buf.length;) {
    const len = buf.readUInt32BE(at), kind = buf.toString("latin1", at + 4, at + 8);
    if (kind === "IDAT") idat.push(buf.subarray(at + 8, at + 8 + len));
    at += 12 + len;
  }
  const raw = zlib.inflateSync(Buffer.concat(idat));
  const stride = w * ch;
  const px = Buffer.alloc(stride * h);
  for (let y = 0; y < h; y++) {
    const filter = raw[y * (stride + 1)];
    for (let i = 0; i < stride; i++) {
      const v = raw[y * (stride + 1) + 1 + i];
      const a = i >= ch ? px[y * stride + i - ch] : 0, b = y > 0 ? px[(y - 1) * stride + i] : 0, c = i >= ch && y > 0 ? px[(y - 1) * stride + i - ch] : 0;
      const p = a + b - c, pa = Math.abs(p - a), pb = Math.abs(p - b), pc = Math.abs(p - c);
      px[y * stride + i] = (v + (filter === 1 ? a : filter === 2 ? b : filter === 3 ? (a + b) >> 1 : filter === 4 ? (pa <= pb && pa <= pc ? a : pb <= pc ? b : c) : 0)) & 0xff;
    }
  }
  return { w, h, at: (x, y) => { const o = y * stride + x * ch; return [px[o], px[o + 1], px[o + 2], ch === 4 ? px[o + 3] : 255]; } };
}

const median = (a) => [...a].sort((x, y) => x - y)[Math.floor(a.length / 2)];
let run = null, c = null;
const clients = [];
let windowReads = 0;

try {
  run = launch(dir);
  await ready(run);
  const { port, token } = JSON.parse(readFileSync(run.file, "utf8"));
  const open = async () => { const k = await connect(run.file); clients.push(k); return k; };
  const rawConnect = async () => { const s = net.connect(port, "127.0.0.1"); s.on("error", () => {}); await new Promise((r) => s.once("connect", r)); return s; };
  const line = (id, cmd, args) => JSON.stringify({ id, token, cmd, args }) + "\n";
  c = await open();
  const state = () => c.send("state");
  /** Polls `state` until `pred` holds (the app handles input on its own turn); the last state either way. */
  const settle = async (pred, ms = 2500) => {
    const end = Date.now() + ms;
    let s = await state();
    while (!pred(s) && Date.now() < end) { await sleep(40); s = await state(); }
    return s;
  };
  /** The window is not the user's: neither active nor on any display (read from the app itself). */
  const guard = async (after) => {
    if (!windowMode) return;
    const s = await c.send("state");
    windowReads++;
    if (s.windowActive !== false || s.onDisplay !== false)
      ok(false, `the window was never the user's: after "${after}" it reports windowActive=${s.windowActive}, onDisplay=${s.onDisplay}`);
  };
  /** One check: its failures are recorded and the run goes on; the window guard is read after it. */
  const check = async (name, fn) => {
    try { await fn(); } catch (e) { ok(false, `${name}: ${e.stack ?? e}`); }
    try { await guard(name); } catch (e) { ok(false, `${name}: reading the window guard failed: ${e.message}`); }
  };

  ok(existsSync(run.file), "the app wrote drive.json");
  await guard("start");
  console.log(`     (the window's own render scaling is ${(await state()).renderScaling}; Toolkit.scale ${scale})`);

  let go, list, name;
  await check("find #go", async () => {
    go = await c.send("find", { target: "#go" });
    list = await c.send("find", { target: "#list" });
    name = await c.send("find", { target: "#name" });
    ok(go.source === "haxeui" && go.w > 0 && go.h > 0, `find #go: haxeui, ${go.w}x${go.h} at ${go.x},${go.y}`);
  });

  await check("click", async () => {
    await c.send("click", { target: "#go" });
    const s = await settle((s) => s.clicks >= 1);
    ok(s.clicks === 1, `click #go landed (clicks ${s.clicks})`);
  });

  await check("right click", async () => {
    // heaps-drive's right button is 1; AppDriver's is 2.
    await c.send("click", { target: "#go", right: true });
    const s = await settle((s) => s.rightClicks >= 1);
    ok(s.rightClicks === 1 && s.clicks === 1, `a right click is a right click and no more (rightClicks ${s.rightClicks}, clicks ${s.clicks})`);
  });

  await check("double click", async () => {
    const before = (await state()).clicks;
    await c.send("click", { target: "#go", double: true });
    const s = await settle((s) => s.clicks >= before + 2);
    ok(s.clicks === before + 2, `a double click is two clicks (${before} -> ${s.clicks})`);
  });

  await check("type", async () => {
    const text = "héllo 😀";   // an accent, and a character outside the BMP: two UTF-16 units
    const r = await c.send("type", { target: "#name", text });
    ok(r.text === text, `type holds a surrogate pair together (${JSON.stringify(r.text)})`);
  });

  await check("held modifier", async () => {
    // A second click on a field within the double-click interval selects a word, as it would for a
    // person: let that pass, so the click `type` makes is a plain one.
    await sleep(700);
    const text = (await state()).text;
    await c.send("key", { name: "Ctrl+A" });
    const all = await settle((s) => s.selection > 0);
    ok(all.selection === text.length && text.length > 0, `Ctrl+A held Ctrl while A went down: the whole text is selected (${all.selection} of ${text.length})`);
    await c.send("key", { name: "Delete" });
    const gone = await settle((s) => s.text === "");
    ok(gone.text === "", `and Delete removed the selection (${JSON.stringify(gone.text)})`);
    await sleep(700);
    const r = await c.send("type", { target: "#name", text: "x" });
    ok(r.text === "x", `typing then answers just the new text (${JSON.stringify(r.text)})`);
  });

  await check("clipboard keys", async () => {
    ok(await code(c.send("key", { name: "Ctrl+C" })) === "bad_request", "Ctrl+C is refused as bad_request");
  });

  await check("wheel", async () => {
    const before = (await state()).scroll;
    await c.send("wheel", { target: "#list", notches: 3 });
    const down = await settle((s) => s.scroll > before);
    ok(down.scroll > before, `wheel notches 3 scrolled the list down (${before} -> ${down.scroll})`);
    await c.send("wheel", { target: "#list", notches: -3 });
    const up = await settle((s) => s.scroll < down.scroll);
    ok(up.scroll < down.scroll, `wheel notches -3 scrolled it back up (${down.scroll} -> ${up.scroll})`);
  });

  let dragMs = 0;
  await check("drag", async () => {
    const before = await state();
    const t = Date.now();
    const r = await c.send("drag", { from: "#go", to: "#list" });
    dragMs = Date.now() - t;
    await sleep(300);
    const s = await state();
    ok(same(r, {}), `drag answered Done (${JSON.stringify(r)}, ${dragMs} ms)`);
    ok(s.clicks === before.clicks, `a drag from #go to #list clicks neither (clicks ${before.clicks} -> ${s.clicks})`);
    ok(s.pressed === before.pressed + 1 && s.released === before.released + 1, `it pressed and released once (${s.pressed - before.pressed}, ${s.released - before.released})`);
  });

  const file = (n) => join(dir, n);
  await check("shot", async () => {
    const s = await state();
    const r = await c.send("shot", { file: file("whole.png") });
    const png = decodePng(readFileSync(r.file));
    ok(r.w === s.client.w && r.h === s.client.h && png.w === r.w && png.h === r.h, `shot is the client size (${r.w}x${r.h}, client ${s.client.w}x${s.client.h}, PNG ${png.w}x${png.h})`);
    const corner = png.at(png.w - 3, png.h - 3);
    const face = png.at(go.x + 6, go.y + Math.round(go.h / 2));   // left of the label, on the button's face
    ok(face[0] === 255 && face[1] === 0 && face[2] === 0 && !same(face, corner), `#go's face is its red, not the background (${face} against ${corner})`);
    const r2 = await c.send("shot", { file: file("go.png"), within: "#go" });
    const png2 = decodePng(readFileSync(r2.file));
    ok(r2.w === go.w && r2.h === go.h && png2.w === go.w && png2.h === go.h, `shot within #go is its node's size (${r2.w}x${r2.h}, node ${go.w}x${go.h}, scale ${scale})`);
    const r3 = await c.send("shot", { file: file("list.png"), within: "#list" });
    ok(r3.w === list.w && r3.h === list.h, `shot within #list is its node's size (${r3.w}x${r3.h}, node ${list.w}x${list.h})`);
  });

  await check("resize", async () => {
    const r = await c.send("resize", { w: 700, h: 500 });
    ok(same(r, { w: 700, h: 500 }), `resize 700x500 answers the size (${JSON.stringify(r)})`);
    const s = await state();
    ok(same(s.client, { w: 700, h: 500 }), `the client area is 700x500 when it answers (${JSON.stringify(s.client)})`);
    await sleep(1200);   // past AppDriver.Resize's own second of correcting
    const later = await state();
    ok(same(later.client, { w: 700, h: 500 }), `and a second later (${JSON.stringify(later.client)})`);
    const shot = await c.send("shot", { file: file("resized.png") });
    ok(shot.w === 700 && shot.h === 500, `a shot after the resize is 700x500 (${shot.w}x${shot.h})`);
    go = await c.send("find", { target: "#go" });
    await c.send("click", { target: "#go" });
    const after = await settle((x) => x.clicks > later.clicks);
    ok(after.clicks === later.clicks + 1, `a click on #go after the resize lands (clicks ${later.clicks} -> ${after.clicks})`);
  });

  // Review focus 2: a client that vanishes mid-drag or mid-key leaves nothing held, and the drag it
  // abandoned never clicks its source.
  await check("abandoned drag", async () => {
    let proven = false;
    for (const part of [0.4, 0.3, 0.55, 0.2]) {
      if (proven) break;
      const before = await state();
      c.close(); clients.splice(clients.indexOf(c), 1);   // one client at a time
      await sleep(150);
      const s = await rawConnect();
      s.write(line(1, "drag", { from: "#go", to: "#list" }));
      await sleep(Math.max(15, Math.round(dragMs * part)));
      s.destroy();
      await sleep(150);
      c = await open();
      const after = await settle((x) => x.pressed === x.released);
      const goNow = await c.send("find", { target: "#go" });
      const listNow = await c.send("find", { target: "#list" });
      const p = after.pointer;
      const left = p.y > goNow.y + goNow.h && p.y < listNow.y + listNow.h / 2 - 5;   // off #go, and not yet at the end
      if (!left) { console.log(`     (the drag was cut at ${Math.round(part * 100)}% of ${dragMs} ms with the pointer at ${Math.round(p.x)},${Math.round(p.y)}: not between #go and #list; trying again)`); continue; }
      proven = true;
      ok(after.pressed === after.released, `after the socket died mid-drag, nothing is held (pressed ${after.pressed}, released ${after.released})`);
      ok(after.clicks === before.clicks, `the abandoned drag never clicked its source (clicks ${before.clicks} -> ${after.clicks})`);
      ok(after.pressed - before.pressed === 1, `the drag had pressed (${after.pressed - before.pressed})`);
    }
    ok(proven, "an abandoned drag was cut while the pointer was between #go and #list");
  });

  await check("abandoned key", async () => {
    const before = await state();
    c.close(); clients.splice(clients.indexOf(c), 1);   // one client at a time
    await sleep(150);
    const s = await rawConnect();
    await new Promise((r) => s.end(line(1, "key", { name: "Ctrl+A" }), r));   // the request and the end of the connection together
    await sleep(300);
    s.destroy();
    c = await open();
    const after = await settle((x) => x.keysUp === x.keysDown);
    ok(after.keysDown - before.keysDown === 2, `the key was pressed (${after.keysDown - before.keysDown} key downs)`);
    ok(after.keysUp - before.keysUp === 2, `and let go when the client went (${after.keysUp - before.keysUp} key ups)`);
  });

  // How long an idle app takes to answer: the channel's tick must keep running with nothing arriving.
  await check("idle latency", async () => {
    const times = [];
    for (let i = 0; i < 6; i++) {
      await sleep(1500);
      const t = Date.now();
      await c.send("find", { target: "#go" });
      times.push(Date.now() - t);
    }
    console.log(`     (a find after 1.5 s idle: ${times.join(", ")} ms; median ${median(times)} ms)`);
    ok(Math.max(...times) < 1000, `an idle app answers within a second (worst ${Math.max(...times)} ms)`);
  });

  // The window is still not the user's, right before quit.
  await guard("before quit");
  if (windowMode) ok(true, `the window was never active nor on a display (${windowReads} reads)`);

  await c.send("quit");
  c.close(); clients.splice(clients.indexOf(c), 1); c = null;
  const exitCode = await Promise.race([run.exited, never(10000, "timeout")]);
  ok(exitCode === 0, `quit ended the process (code ${exitCode})`);
  ok(!existsSync(run.file), "quit removed drive.json");
  ok(!/tick failed|DRIVE: .*failed/.test(run.out + run.err), "the channel reported no failure");
  if (run.err.trim() !== "") console.log("     (stderr: " + run.err.trim().slice(0, 300) + ")");
} catch (e) {
  console.log(`FAIL - ${e.stack ?? e}`);
  failures++;
} finally {
  for (const k of clients) k.close();
  if (run && run.exitCode === null) { console.log("(killing the app by PID)"); try { process.kill(run.pid); } catch {} }
}

// Review focus 4, a run of its own: an uncaught error in the app ends it, non-zero, with the error
// on stderr and no hang, and a pending request is not left waiting.
{
  const crashDir = join(dir, "crash");
  const crash = launch(crashDir, false);
  let cc = null;
  try {
    await ready(crash);
    cc = await connect(crash.file);
    const parked = cc.send("wait", { condition: { crash: true }, timeoutMs: 20000 }).then(() => "answered", (e) => e.message);
    const t = Date.now();
    const why = await Promise.race([parked, never(10000, "no reply in 10 s")]);
    const exitCode = await Promise.race([crash.exited, never(10000, "timeout")]);
    ok(exitCode !== 0 && exitCode !== "timeout", `the crashed app exited non-zero by itself (code ${exitCode}, ${Date.now() - t} ms after the request)`);
    ok(crash.err.includes("a crash on demand"), `the error went to stderr (${JSON.stringify(crash.err.trim().slice(0, 120))})`);
    ok(why === "the app closed the connection", `the socket closed under the pending wait (${why})`);
    ok(crash.exitCode !== null, "no process, and so no window, was left behind");
  } catch (e) {
    console.log(`FAIL - ${e.stack ?? e}`);
    failures++;
  } finally {
    if (cc) cc.close();
    if (crash.exitCode === null) { console.log("(killing the crash app by PID)"); try { process.kill(crash.pid); } catch {} }
  }
}

clearTimeout(watchdog);
if (failures) console.log("--- app output ---\n" + (run?.out ?? "").slice(-2000) + (run?.err ?? "").slice(-2000));
console.log(failures === 0 ? `selftest-cs ${mode}${scale !== 1 ? " --scale " + scale : ""} passed` : `selftest-cs ${mode}: ${failures} failed`);
process.exit(failures === 0 ? 0 : 1);
