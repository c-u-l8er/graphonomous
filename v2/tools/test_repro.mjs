#!/usr/bin/env node
/* test_repro.mjs — the documented verification target (GPT v6 §7 G0.5-R2, D-069).
 *
 *   npm run test:repro      the CLEAN-BUNDLE target. Runs every test file, the Python canonicalizer twin, and the
 *                           CLI verifiers over the four shipped projections. Tests that need the pinned source
 *                           registries SKIP with a reason; the target is green when NOTHING FAILED.
 *   npm run test:full-tree  the same, plus the assertion that the pinned registries ARE reachable and therefore that
 *                           nothing skipped for their absence. Use this in the real ProjectAmp2 checkout.
 *
 * The one file list serves both, so the clean target cannot rot by forgetting to add a new test file to it. */
import { execFileSync, spawnSync } from "node:child_process";
import { readdirSync, existsSync, readFileSync } from "node:fs";
import { resolve, dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { probeSnapshots } from "../test/helpers/sources.mjs";

const V = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const FULL = process.argv.includes("--full-tree");
const PROJECTIONS = ["baseline", "historical", "multi", "multi-v1", "tri"];
const say = (s) => process.stdout.write(s + "\n");
const fails = [];

say(`# graphonomous/v2 ${FULL ? "test:full-tree" : "test:repro"} — node ${process.version}`);

/* 1. the whole suite, one reporter, counted. */
const files = readdirSync(join(V, "test")).filter((f) => f.endsWith(".test.mjs")).sort().map((f) => join("test", f));
/* A CEILING, on its own merits. `node --test` defaults its worker count to the CPU count (24 on this box), so it
 * starts every one of these files at once; several hold a whole projection parsed in memory and test/g05.test.mjs
 * builds 56 MB of world payloads TWICE. Bounding that is worth doing regardless.
 *
 * CORRECTION, so nobody inherits a wrong diagnosis: this ceiling was first written on 2026-09-04 blaming the suite for
 * a run of OOM kills on the development machine. It was NOT the suite. `dmesg` named the killed process every time —
 * the editor's own MainThread at ~23.6 GB anon RSS, oom_score_adj 100 — and the test workers merely died with the
 * parent that spawned them. The fan-out above is real and worth capping; it was not the cause of those crashes.
 *   --test-concurrency  caps how many workers exist at once;
 *   --max-old-space-size caps what any ONE of them may grow to, so a runaway becomes a red test instead of a SIGKILL.
 * Both are needed: the first bounds the sum, the second bounds the worst single term. Raise them only with a
 * measurement (tools/mem_probe.mjs prints peak RSS per file). */
const CONCURRENCY = Number(process.env.G0_TEST_CONCURRENCY || 2);
const HEAP_MB = Number(process.env.G0_TEST_HEAP_MB || 3072);
say(`# ceiling: --test-concurrency=${CONCURRENCY}, --max-old-space-size=${HEAP_MB} per worker`);

/* PREFLIGHT (2026-09-05). The ceiling above bounds what the suite may take; it says nothing about what the machine
 * can GIVE. Three OOM kills in two days all landed on the editor process that had spawned this suite (dmesg named it
 * each time, at 14-23 GB), and a kill is a lost session with no red line to read. So the runner refuses to start when
 * MemAvailable is below what its own ceiling could ask for, and says so in numbers. The one measured hog was not fan-out
 * at all: test/g05.test.mjs compared two 15 MB files with assert.deepEqual on Buffers, which on a stale ui/data rendered
 * a diff of every byte (6.4 GB resident for ONE comparison). That is fixed at the assertion; this guard is for whatever
 * the next one is. Override with G0_TEST_IGNORE_MEMORY=1 if the number is wrong on your machine. */
const NEED_MB = CONCURRENCY * HEAP_MB + 1024;
if (existsSync("/proc/meminfo") && !process.env.G0_TEST_IGNORE_MEMORY) {
  const m = /^MemAvailable:\s+(\d+) kB$/m.exec(readFileSync("/proc/meminfo", "utf8"));
  const availMb = m ? Math.round(Number(m[1]) / 1024) : null;
  if (availMb !== null && availMb < NEED_MB) {
    say(`\nVERDICT: REFUSED TO START — MemAvailable is ${availMb} MB and this run's ceiling is ${NEED_MB} MB ` +
        `(${CONCURRENCY} workers × ${HEAP_MB} MB + 1024 MB margin). Free memory (a /tmp tmpfs counts as memory here), ` +
        `or lower G0_TEST_CONCURRENCY / G0_TEST_HEAP_MB, or set G0_TEST_IGNORE_MEMORY=1. Not starting is the whole point: ` +
        `an out-of-memory kill takes the process that spawned this suite, not the suite.`);
    process.exit(2);
  }
  say(`# preflight: MemAvailable ${availMb} MB ≥ ceiling ${NEED_MB} MB`);
}
const r = spawnSync(process.execPath, [`--max-old-space-size=${HEAP_MB}`, "--test", `--test-concurrency=${CONCURRENCY}`, "--test-reporter=tap", ...files],
  { cwd: V, encoding: "utf8", maxBuffer: 256 * 1024 * 1024, env: { ...process.env, NODE_OPTIONS: [process.env.NODE_OPTIONS, `--max-old-space-size=${HEAP_MB}`].filter(Boolean).join(" ") } });
if (r.status === null && r.signal) fails.push(`the test runner was killed by ${r.signal} — this is an OUT-OF-MEMORY kill, not a test failure. Lower G0_TEST_CONCURRENCY (currently ${CONCURRENCY}) or G0_TEST_HEAP_MB (currently ${HEAP_MB}).`);
const tap = (r.stdout || "") + (r.stderr || "");
const num = (k) => { const m = tap.match(new RegExp("^# " + k + " (\\d+)$", "m")); return m ? Number(m[1]) : null; };
const [tests, pass, fail, skipped] = [num("tests"), num("pass"), num("fail"), num("skipped")];
say(`\n## suite  ${tests} tests · ${pass} pass · ${fail} fail · ${skipped} skipped`);
if (fail === null) { fails.push("the TAP summary could not be parsed"); say(tap.slice(-4000)); }
else if (fail > 0) { fails.push(`${fail} test(s) failed`); say(tap.split("\n").filter((l) => /^not ok |^\s+error:|^\s+failureType:/.test(l)).slice(0, 60).join("\n")); }
/* every skip is printed with its reason: a clean bundle must SAY why, not merely be green. */
/* Group by REASON, not by test: 22 tests in one file skipping for one missing checkout is ONE fact, printed once. */
const skips = [...tap.matchAll(/^ok \d+ - (.+) # SKIP(?: (.*))?$/gm)].map((m) => ({ test: m[1], why: (m[2] || "(no reason given)").trim() }));
if (skips.length) {
  const byReason = new Map();
  for (const s of skips) { if (!byReason.has(s.why)) byReason.set(s.why, []); byReason.get(s.why).push(s.test); }
  say(`\n## skipped, with reasons  (${skips.length} test${skips.length === 1 ? "" : "s"}, ${byReason.size} distinct reason${byReason.size === 1 ? "" : "s"})`);
  for (const [why, tests] of [...byReason].sort()) {
    say(`\n  ${tests.length} test${tests.length === 1 ? "" : "s"}: ${why}`);
    for (const t of tests.slice(0, 3)) say(`      · ${t.slice(0, 110)}`);
    if (tests.length > 3) say(`      · … and ${tests.length - 3} more in the same file`);
  }
}

/* 2. the Python twin of the canonical encoder — a second implementation, no git needed. */
try { execFileSync("python3", [join(V, "test", "canon_twin.py"), "--selftest"], { cwd: V, stdio: "pipe" }); say("\n## canon twin  ok (python3 test/canon_twin.py --selftest)"); }
catch (e) { fails.push("canon_twin selftest failed"); say("\n## canon twin  FAILED\n" + String(e.stdout || e.message).slice(-2000)); }

/* 3. the shipped projections verify from their own bytes — projection root, evaluation root, certificate. */
say("\n## shipped projections");
for (const p of PROJECTIONS) {
  const dir = join(V, "projections", p);
  if (!existsSync(dir)) { fails.push(`projections/${p} is missing`); say(`  ${p}: MISSING`); continue; }
  const out = [];
  for (const [label, args] of [["verify", ["verify", "--dir", `projections/${p}`]], ["verify-eval", ["verify-eval", "--dir", `projections/${p}`]], ["cert v0", ["check-cert", "--dir", `projections/${p}`]], ["cert v1", ["check-cert", "--dir", `projections/${p}`, "--protocol", "v1"]], ["consistency", ["consistency", "--dir", `projections/${p}`]]]) {
    const x = spawnSync(process.execPath, [join(V, "bin", "g0.mjs"), ...args], { cwd: V, encoding: "utf8", maxBuffer: 64 * 1024 * 1024 });
    if (x.status === 0) out.push(`${label} ok`);
    else { fails.push(`projections/${p}: ${label} exited ${x.status}`); out.push(`${label} FAILED(${x.status})`); }
  }
  say(`  ${p}: ${out.join(" · ")}`);
}

/* 4. full-tree only: the registries must actually be here, so a skip cannot hide a regression. */
if (FULL) {
  const avail = probeSnapshots("baseline.json", "historical.json", "multi.json", "multi-v1.json");
  say(`\n## pinned registries  ${avail.ok ? "reachable" : "NOT REACHABLE"}`);
  if (!avail.ok) { fails.push("test:full-tree requires the pinned registries: " + avail.reason); say("  " + avail.reason); }
  else if (skipped > 1) say(`  note: ${skipped} tests still skipped — read the reasons above; a skip in the full tree is a claim about something other than the registries.`);
}

say("\n" + (fails.length ? `VERDICT: FAILED — ${fails.length} problem(s)\n  - ` + fails.join("\n  - ") : `VERDICT: GREEN — ${pass} passing, ${skipped} skipped with reasons, 0 failing`));
process.exit(fails.length ? 1 : 0);
