// The lib end to end: builds examples/hello.hxml, launches it off-screen, drives it through the
// real socket, screenshots it, quits it, then checks a stale drive.json is reported, not hung on.
// Run from the repo root: node tools/selftest.mjs
import { spawn, execSync } from "node:child_process";
import { existsSync, mkdirSync, rmSync, writeFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { connect } from "./drive.mjs";

const dir = resolve("bin/selftest");
rmSync(dir, { recursive: true, force: true });
mkdirSync(dir, { recursive: true });
const file = join(dir, "drive.json");
let failures = 0;
const ok = (cond, what) => { console.log(`${cond ? "ok  " : "FAIL"} - ${what}`); if (!cond) failures++; };

execSync("haxe examples/hello.hxml", { stdio: "inherit" });
const app = spawn("hl", ["bin/hello.hl"], { env: { ...process.env, DRIVE_DIR: dir }, stdio: ["ignore", "inherit", "inherit"], windowsHide: true });
// Made before quit is sent, so an exit that comes straight after it cannot be missed.
const exited = new Promise((r) => app.on("exit", r));
let c = null;
try {
  const deadline = Date.now() + 30000;
  while (!existsSync(file) && Date.now() < deadline) await new Promise((r) => setTimeout(r, 100));
  ok(existsSync(file), "the app wrote drive.json");
  if (!existsSync(file)) throw new Error("drive.json never appeared");

  c = await connect(file);
  const found = await c.send("find", { target: "text:Hello" });
  ok(found.source === "h2d" && found.w > 0, "find text:Hello through the socket");
  await c.send("click", { target: "text:Hello" });
  await c.send("wait", { condition: { clicks: 1 }, timeoutMs: 3000 });
  ok((await c.send("state")).clicks === 1, "the click landed");
  await c.send("wait", { condition: { text: "name:count", equals: "clicked 1" }, timeoutMs: 3000 });
  ok(true, "the label shows it");
  const shot = await c.send("shot", { file: join(dir, "hello.png") });
  ok(shot.w === 200 && shot.h === 100 && existsSync(shot.file), "a screenshot at the canvas size");
  let refused = null;
  try { await c.send("click", { target: "text:Nope" }); } catch (e) { refused = e.code; }
  ok(refused === "not_found", "a missing target is not_found");
  await c.send("quit");
  c.close();
  c = null;
  const code = await Promise.race([exited, new Promise((r) => setTimeout(() => r("timeout"), 10000))]);
  ok(code === 0, `the app exited cleanly (code ${code})`);
  ok(!existsSync(file), "quit removed drive.json");
} catch (e) {
  console.log(`FAIL - ${e.stack ?? e}`);
  failures++;
} finally {
  if (c) c.close();
  // Whatever happened above, the driven app (an invisible utility window nobody can close) must not outlive the run.
  if (app.exitCode === null && app.signalCode === null) app.kill();
}

// A drive.json left behind by a crashed run: a dead port must be an error, not a hang.
writeFileSync(file, JSON.stringify({ port: 1, token: "stale" }));
const out = (() => { try { execSync(`node tools/drive.mjs --file "${file}" state`, { stdio: "pipe" }); return { status: 0, err: "" }; } catch (e) { return { status: e.status, err: String(e.stderr) }; } })();
ok(out.status === 1 && out.err.includes("cannot reach the app"), "a stale drive.json reports it cannot reach the app");

console.log(failures === 0 ? "selftest passed" : `selftest: ${failures} failed`);
process.exit(failures === 0 ? 0 : 1);
