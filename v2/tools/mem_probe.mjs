#!/usr/bin/env node
/* mem_probe.mjs — what does each test file actually COST, in peak resident memory?
 *
 * WHY THIS EXISTS. On 2026-09-04 this suite repeatedly OOM-killed a 30 GB machine, taking the editor with it. The
 * cause was not one heavy test: it was that `node --test` defaults its worker count to the CPU count (24 here), so it
 * started all 18 files at once, and several of them hold a whole projection parsed in memory while
 * test/g05.test.mjs builds 56 MB of world payloads twice. An out-of-memory kill is not a test failure — it is a lost
 * session, with no red line to read afterwards.
 *
 * The ceiling in package.json and tools/test_repro.mjs is set from THIS measurement rather than from a guess, and it
 * is re-measurable whenever a projection is added:
 *
 *   node tools/mem_probe.mjs                 every test file, one at a time
 *   node tools/mem_probe.mjs g05 consistency  just these
 *
 * Each file runs in its own process WITH the same heap cap the suite uses, so a runaway here dies as a Node error
 * with a stack, never as a SIGKILL. Peak RSS is sampled from /proc rather than guessed.
 *
 * MEASURED 2026-09-05, one file at a time under `ulimit -v`: 17 of 18 files peak between 0 and 460 MB;
 * test/g05.test.mjs peaked at 4,519 MB (6,416 MB with the one test isolated). The compiler it spawns peaks at 303 MB.
 * The whole excess was ONE assertion — `assert.deepEqual` on two 15 MB Buffers, which on a mismatch (a stale ui/data)
 * renders a diff of every byte. Replaced by a byte comparison that reports a hash; the same test now peaks at 185 MB.
 * The ceiling in test_repro.mjs was right to exist and wrong about what it was bounding: not a sum of many, one term. */
import { spawn } from "node:child_process";
import { readdirSync, readFileSync, existsSync } from "node:fs";
import { resolve, dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const V = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const HEAP_MB = Number(process.env.G0_TEST_HEAP_MB || 3072);
const want = process.argv.slice(2).filter((a) => !a.startsWith("-"));
const files = readdirSync(join(V, "test")).filter((f) => f.endsWith(".test.mjs"))
  .filter((f) => !want.length || want.some((w) => f.includes(w))).sort();

/** Sum RSS of a process and every descendant, from /proc. Returns MB. */
function treeRssMb(root) {
  let kids = new Map();
  try {
    for (const pid of readdirSync("/proc").filter((d) => /^\d+$/.test(d))) {
      try {
        const stat = readFileSync(`/proc/${pid}/stat`, "utf8");
        const ppid = Number(stat.slice(stat.lastIndexOf(")") + 2).split(" ")[1]);
        if (!kids.has(ppid)) kids.set(ppid, []);
        kids.get(ppid).push(Number(pid));
      } catch { /* the process exited between readdir and read: not an error */ }
    }
  } catch { return 0; }
  const seen = new Set(); const stack = [root]; let kb = 0;
  while (stack.length) {
    const pid = stack.pop();
    if (seen.has(pid)) continue;
    seen.add(pid);
    try {
      const status = readFileSync(`/proc/${pid}/status`, "utf8");
      const m = /^VmRSS:\s+(\d+) kB$/m.exec(status);
      if (m) kb += Number(m[1]);
    } catch { /* gone */ }
    for (const k of kids.get(pid) ?? []) stack.push(k);
  }
  return Math.round(kb / 1024);
}

const rows = [];
for (const f of files) {
  const started = Date.now();
  const child = spawn(process.execPath, [`--max-old-space-size=${HEAP_MB}`, "--test", "--test-concurrency=1", `test/${f}`],
    { cwd: V, stdio: ["ignore", "pipe", "pipe"] });
  let out = "";
  child.stdout.on("data", (d) => (out += d));
  child.stderr.on("data", (d) => (out += d));
  let peak = 0;
  const tick = setInterval(() => { const mb = treeRssMb(child.pid); if (mb > peak) peak = mb; }, 120);
  const code = await new Promise((ok) => child.on("close", (c, sig) => ok(sig ? `KILLED:${sig}` : c)));
  clearInterval(tick);
  const n = (k) => { const m = new RegExp(`^ℹ ${k} (\\d+)$`, "m").exec(out); return m ? Number(m[1]) : null; };
  rows.push({ file: f, peak_mb: peak, seconds: +((Date.now() - started) / 1000).toFixed(1), exit: code, tests: n("tests"), pass: n("pass"), fail: n("fail"), skipped: n("skipped") });
  process.stdout.write(`${f.padEnd(28)} peak ${String(peak).padStart(5)} MB  ${String(rows.at(-1).seconds).padStart(6)}s  ${rows.at(-1).pass ?? "?"}/${rows.at(-1).tests ?? "?"} pass${rows.at(-1).fail ? `  FAIL ${rows.at(-1).fail}` : ""}${String(code).startsWith("KILLED") ? `  ${code}` : ""}\n`);
}

const worst = rows.slice().sort((a, b) => b.peak_mb - a.peak_mb);
const sum = rows.reduce((n, r) => n + r.peak_mb, 0);
process.stdout.write(`\nheaviest: ${worst.slice(0, 3).map((r) => `${r.file} ${r.peak_mb} MB`).join(" · ")}\n`);
process.stdout.write(`if every file ran at once the peak would be about ${sum} MB; the suite's ceiling holds it to roughly ${worst.slice(0, Number(process.env.G0_TEST_CONCURRENCY || 2)).reduce((n, r) => n + r.peak_mb, 0)} MB\n`);
if (existsSync("/proc/meminfo")) {
  const total = /^MemTotal:\s+(\d+) kB$/m.exec(readFileSync("/proc/meminfo", "utf8"));
  if (total) process.stdout.write(`machine has ${Math.round(Number(total[1]) / 1024 / 1024)} GB total\n`);
}
