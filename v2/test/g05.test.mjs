/* g05.test.mjs — the G0.5 inspector shows what Node computed, or the build fails.
 *
 * G0.5 is a read-only page over baked data. Everything that could make it lie is a difference between
 * ui/data/<slug>.json and what lib/query.mjs / lib/acceptance.mjs return live, so that is what this file measures:
 * the compiler runs, its output is deterministic, every relation carries its kernel identities, every derived premise
 * resolves through factIndex by lookup, every baked explanation is byte-for-byte the library's explanation, the
 * acceptance payload is the acceptance module re-run, no world file mixes two snapshot roots, no UI/layout key made it
 * into the data, and ui/app.js reaches nothing but its own two relative data files. */
import { test } from "node:test";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { readFileSync, readdirSync, mkdtempSync, rmSync, existsSync, mkdirSync, copyFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { createHash } from "node:crypto";
import { fileURLToPath } from "node:url";
import { dirname, resolve, join } from "node:path";
import { openGraph } from "../lib/query.mjs";
import { runAcceptance } from "../lib/acceptance.mjs";

const V = resolve(dirname(fileURLToPath(import.meta.url)), "..");
/* The five worlds the selector offers: three under the frozen graphonomous.semantic.v0, the v1 successor over the
 * same six pinned sources, and `tri` — the same six plus TRVM governance as a third source family (D-073). The list is here and in tools/g05_build.mjs's DEFAULT_DIRS and NOWHERE
 * ELSE — the page reads ui/data/index.json and knows none of these names. */
const PROJECTIONS = ["baseline", "historical", "multi", "multi-v1", "tri"].map((n) => ({ name: n, dir: join(V, "projections", n) }));
const REL_ID = /^rel-[0-9a-f]{64}$/;
const REV_ID = /^rev-[0-9a-f]{64}$/;
const json = (p) => JSON.parse(readFileSync(p, "utf8"));
const round = (v) => JSON.parse(JSON.stringify(v));

/* Build once into a throwaway directory: the tests measure the compiler's output, not a file someone edited.
 *
 * `ui/data` is a 36 MB BUILD PRODUCT — gitignored, and excluded from the handoff ZIP on purpose. Nothing in this file
 * may require it to already exist (GPT v6 §7 G0.5-R1, D-069). So the temp directory is shaped as a COMPLETE `ui/`
 * fixture — the three shipped page files beside a generated `data/` — and the server test serves that fixture. The
 * developer's own `ui/data` is compared only if it happens to be there, as a staleness check. */
const FIXTURE = mkdtempSync(join(tmpdir(), "g05-"));
const OUT = join(FIXTURE, "data");
const PAGE_FILES = ["index.html", "app.js", "app.css"];
mkdirSync(OUT, { recursive: true });
for (const f of PAGE_FILES) copyFileSync(join(V, "ui", f), join(FIXTURE, f));
const stdout = execFileSync(process.execPath, [join(V, "tools", "g05_build.mjs"), "--out", OUT], { cwd: V, encoding: "utf8" });
const summary = JSON.parse(stdout);
const INDEX = json(join(OUT, "index.json"));
const worlds = INDEX.worlds.map((w) => ({ entry: w, data: json(join(OUT, w.file)) }));
process.on("exit", () => rmSync(FIXTURE, { recursive: true, force: true }));

/* Byte equality of two files, reported by hash and first differing offset. NOT assert.deepEqual on two Buffers: on a
   mismatch that assertion renders a diff of every byte, and on the 15 MB world files it was measured at 6.4 GB of
   resident memory for one comparison (2026-09-05, tools/mem_probe.mjs) — the whole reason this suite could take a 30 GB
   machine down when ui/data was stale. A stale payload is a one-line fact; it must cost one line to report. */
function assertSameBytes(a, b, msg) {
  const A = readFileSync(a), B = readFileSync(b);
  if (A.equals(B)) return;
  const h = (x) => createHash("sha256").update(x).digest("hex").slice(0, 16);
  let i = 0; const n = Math.min(A.length, B.length); while (i < n && A[i] === B[i]) i++;
  assert.fail(`${msg}: ${A.length} vs ${B.length} bytes, sha256 ${h(A)}… vs ${h(B)}…, first difference at byte ${i}`);
}

test("the compiler emits one file per projection, each naming its own snapshot id and roots", () => {
  assert.equal(readdirSync(OUT).filter((f) => f.endsWith(".json")).length, PROJECTIONS.length + 1, "one world file each, plus index.json");
  assert.equal(worlds.length, PROJECTIONS.length);
  for (const p of PROJECTIONS) {
    const onDisk = {
      snapshot: json(join(p.dir, "manifest.json")).snapshot,
      root: readFileSync(join(p.dir, "ROOT"), "utf8").trim(),
      evalRoot: readFileSync(join(p.dir, "derived", "ROOT"), "utf8").trim(),
      sem: readFileSync(join(p.dir, "world", "SEM"), "utf8").trim(),
      vclaim: readFileSync(join(p.dir, "certificate", "VCLAIM"), "utf8").trim(),
    };
    const w = worlds.find((x) => x.data.name === p.name);
    assert.ok(w, `no world file for ${p.name}`);
    assert.equal(w.data.identity.snapshot, onDisk.snapshot);
    assert.equal(w.data.identity.projection.root, onDisk.root);
    assert.equal(w.data.identity.evaluation.root, onDisk.evalRoot);
    assert.equal(w.data.identity.wrl.sem, onDisk.sem);
    assert.equal(w.data.identity.certificate.vclaim, onDisk.vclaim);
    assert.equal(w.data.slug, onDisk.snapshot.replace(/^snapshot:g0:/, ""));
    assert.equal(w.entry.snapshot, onDisk.snapshot);
    assert.equal(w.entry.projection_root, onDisk.root);
    /* the four coordinate systems are four different strings — the page is allowed to say so */
    const four = [onDisk.root, onDisk.evalRoot, onDisk.sem, onDisk.vclaim];
    assert.equal(new Set(four).size, 4);
    assert.equal(w.data.identity.certificate.verifier_note, "verifies under its pinned verifier coordinates");
  }
  assert.equal(summary.worlds.length, PROJECTIONS.length, "the printed summary describes every file it wrote");
});

test("the build is deterministic: two independent temp builds are byte-identical", () => {
  const second = mkdtempSync(join(tmpdir(), "g05-again-"));
  try {
    execFileSync(process.execPath, [join(V, "tools", "g05_build.mjs"), "--out", second], { cwd: V });
    assert.deepEqual(readdirSync(second).sort(), readdirSync(OUT).sort(), "the two builds do not even emit the same file names");
    for (const f of readdirSync(OUT)) {
      assertSameBytes(join(second, f), join(OUT, f), `${f} is not byte-identical on a rebuild`);
    }
  } finally { rmSync(second, { recursive: true, force: true }); }
});

/* A DEVELOPER staleness check, not a correctness gate. In a clean checkout or the handoff ZIP there is no ui/data and
   this skips with the command that would create one; in a working tree it catches a payload someone forgot to rebuild. */
test("developer staleness: if ui/data exists, it is what the compiler produces right now", (t) => {
  const served = join(V, "ui", "data");
  if (!existsSync(served)) { t.skip("ui/data is absent — it is a gitignored build product; `node tools/g05_build.mjs --out ui/data` creates it. The payload itself was already built and checked into a temp directory by this file."); return; }
  for (const f of readdirSync(OUT)) {
    assert.ok(existsSync(join(served, f)), `ui/data/${f} is missing — rebuild: node tools/g05_build.mjs --out ui/data`);
    assertSameBytes(join(served, f), join(OUT, f), `ui/data/${f} is stale — rebuild: node tools/g05_build.mjs --out ui/data`);
  }
});

test("every relation carries a kernel-shaped WRL rel- and rev-, and every WRL entry names a real statement", () => {
  for (const { data } of worlds) {
    const wrlKeys = Object.keys(data.wrl);
    assert.equal(wrlKeys.length, data.relations.length, `${data.name}: ${wrlKeys.length} WRL entries for ${data.relations.length} relations`);
    const rels = new Set();
    for (const r of data.relations) {
      const w = data.wrl[r.lid];
      assert.ok(w, `${data.name}: no WRL identity for ${r.lid}`);
      assert.match(w.rel, REL_ID, `${data.name}: ${r.lid} rel- is not kernel-shaped`);
      assert.match(w.rev, REV_ID, `${data.name}: ${r.lid} rev- is not kernel-shaped`);
      assert.ok(w.minted_by && w.minted_by.length, `${data.name}: ${r.lid} has no minter`);
      assert.ok(!rels.has(w.rel), `${data.name}: rel- allocated twice inside one world (${w.rel})`);
      rels.add(w.rel);
    }
    for (const k of wrlKeys) assert.ok(data.relations.some((r) => r.lid === k), `${data.name}: WRL names ${k}, which is not a relation here`);
  }
});

test("factIndex resolves every derived fact and every derived premise in any stored derivation — by lookup, not by hashing", () => {
  for (const { data } of worlds) {
    data.facts.forEach((f, i) => {
      const key = JSON.stringify([f.rel, ...f.args]);
      assert.equal(data.factIndex[key], i, `${data.name}: factIndex misses ${key}`);
    });
    assert.equal(Object.keys(data.factIndex).length, data.facts.length, `${data.name}: factIndex and facts disagree in size`);

    /* every premise the library labelled `derived`, anywhere in any baked tree, must be reachable by lookup */
    let derivedPremises = 0;
    const walk = (n) => {
      if (!n || typeof n !== "object") return;
      if (n.basis === "derived" && Array.isArray(n.fact)) {
        derivedPremises++;
        const key = JSON.stringify(n.fact);
        const at = data.factIndex[key];
        assert.equal(typeof at, "number", `${data.name}: derived premise ${key} does not resolve through factIndex`);
        const target = data.facts[at];
        assert.deepEqual([target.rel, ...target.args], n.fact, `${data.name}: factIndex[${key}] points at the wrong fact`);
      }
      for (const arr of [n.premises, n.derivations]) if (Array.isArray(arr)) arr.forEach(walk);
    };
    for (const t of Object.values(data.explain.facts)) walk(t);
    assert.ok(derivedPremises > 0, `${data.name}: no derived premises seen — the walk found nothing to check`);

    /* every stored derivation's premises are either absent-markers or fact tuples the page can key on */
    for (const f of data.facts) for (const d of f.derivations) for (const p of d.premises) {
      if (Array.isArray(p)) assert.equal(typeof JSON.stringify(p), "string");
      else assert.ok(Array.isArray(p.absent), `${data.name}: a premise is neither a tuple nor an absence: ${JSON.stringify(p)}`);
    }
  }
});

test("what the page renders IS Graph.explain(): every baked record and fact explanation equals the library's, live", () => {
  for (const p of PROJECTIONS) {
    const w = worlds.find((x) => x.data.name === p.name).data;
    const g = openGraph(p.dir);

    assert.equal(Object.keys(w.explain.records).length, w.nodes.length + w.relations.length);
    for (const rec of [...w.nodes, ...w.relations]) {
      assert.deepEqual(w.explain.records[rec.lid], round(g.explain(rec.lid)), `${p.name}: baked explain(${rec.lid}) differs from lib/query.mjs`);
    }
    assert.equal(Object.keys(w.explain.facts).length, w.facts.length);
    for (const f of w.facts) {
      const key = JSON.stringify([f.rel, ...f.args]);
      assert.deepEqual(w.explain.facts[key], round(g.explain([f.rel, ...f.args])), `${p.name}: baked explain(${key}) differs from lib/query.mjs`);
    }

    /* a named sample, spelled out, so a failure says which question it breaks */
    const sample = w.relations[0].lid;
    const live = round(g.explain(sample));
    assert.equal(live.subject, sample);
    assert.ok(live.assertions.length > 0);
    assert.deepEqual(w.explain.records[sample], live);
  }
});

test("the acceptance payload is lib/acceptance.mjs re-run, with the compare root it names", () => {
  const graphs = new Map(PROJECTIONS.map((p) => [p.name, openGraph(p.dir)]));
  for (const p of PROJECTIONS) {
    const w = worlds.find((x) => x.data.name === p.name).data;
    const cmpName = w.acceptance.compare
      ? [...graphs].find(([, g]) => g.snapshot === w.acceptance.compare.snapshot)[0]
      : null;
    assert.ok(cmpName, `${p.name}: no compare root recorded`);
    assert.notEqual(cmpName, p.name, `${p.name}: compared against itself`);
    const live = round(runAcceptance({ primary: graphs.get(p.name), compare: graphs.get(cmpName) }));
    assert.deepEqual(w.acceptance.questions, live, `${p.name}: the baked A1–A7 is not what runAcceptance returns`);
    assert.deepEqual(w.acceptance.questions.map((q) => q.id), ["A1", "A2", "A3", "A4", "A5", "A6", "A7"]);
    for (const q of w.acceptance.questions) {
      assert.ok(q.answered || q.reason, `${p.name} ${q.id}: neither answered nor given a reason`);
      if (q.answered) assert.equal(q.snapshot, w.identity.snapshot, `${p.name} ${q.id}: answered from the wrong root`);
    }
  }
  /* and a question that needs two pins refuses rather than answering from one */
  const one = runAcceptance({ primary: graphs.get("baseline") });
  for (const id of ["A2", "A4"]) {
    const q = one.find((x) => x.id === id);
    assert.equal(q.answered, false);
    assert.match(q.reason, /needs a compare snapshot/);
  }
});

test("no world file mixes snapshots: every record in it carries that world's snapshot id", () => {
  for (const { data } of worlds) {
    const snap = data.identity.snapshot;
    for (const [kind, list] of [["node", data.nodes], ["relation", data.relations], ["assertion", data.assertions], ["location", data.locations], ["fault", data.faults], ["fact", data.facts]]) {
      for (const r of list) assert.equal(r.snapshot, snap, `${data.name}: a ${kind} carries ${r.snapshot}, not ${snap}`);
    }
    assert.equal(data.identity.projection.manifest_snapshot, snap);
    assert.equal(data.identity.evaluation.projection_root, data.identity.projection.root);
    assert.equal(data.identity.wrl.snapshot, snap);
    assert.equal(data.identity.wrl.projection_root, data.identity.projection.root);
    assert.equal(data.identity.certificate.claim.snapshot_id, snap);
    assert.equal(data.identity.certificate.claim.projection_root, data.identity.projection.root);
    /* the compare root A2/A4 use is a different world, and it is named, not merged in */
    assert.notEqual(data.acceptance.compare.snapshot, snap);
    assert.ok(!JSON.stringify(data.counts).includes(data.acceptance.compare.snapshot));
  }
  const snaps = worlds.map((w) => w.data.identity.snapshot);
  assert.equal(new Set(snaps).size, snaps.length, "two world files claim the same snapshot");
});

test("the built payload holds no UI or layout state — layout is not data", () => {
  const forbidden = ["x", "y", "position", "layout", "viewport", "selected", "expanded"];
  for (const f of readdirSync(OUT)) {
    const found = new Set();
    const walk = (v) => {
      if (Array.isArray(v)) return v.forEach(walk);
      if (!v || typeof v !== "object") return;
      for (const [k, x] of Object.entries(v)) { if (forbidden.includes(k)) found.add(k); walk(x); }
    };
    walk(json(join(OUT, f)));
    assert.deepEqual([...found], [], `${f} carries UI/layout keys: ${[...found].join(", ")}`);
  }
});

test("the page is read-only and offline: no absolute fetch, no eval, no write verbs on its two data files", () => {
  const app = readFileSync(join(V, "ui", "app.js"), "utf8");
  const html = readFileSync(join(V, "ui", "index.html"), "utf8");

  const fetches = [...app.matchAll(/fetch\(\s*([^)]*)/g)].map((m) => m[1]);
  assert.ok(fetches.length > 0, "the page must load its data");
  for (const f of fetches) {
    assert.doesNotMatch(f, /["'`]\s*(https?:)?\/\//, `fetch to a non-relative URL: ${f}`);
    assert.match(f, /["'`]data\//, `fetch outside the baked data directory: ${f}`);
  }
  assert.doesNotMatch(app, /\beval\s*\(/, "app.js must not eval");
  assert.doesNotMatch(app, /new\s+Function\s*\(/, "app.js must not build functions from strings");
  assert.doesNotMatch(app, /\bXMLHttpRequest\b|\bWebSocket\b|\bEventSource\b|\bnavigator\.sendBeacon\b/, "app.js must make no other network calls");
  assert.doesNotMatch(app, /method\s*:\s*["'](POST|PUT|PATCH|DELETE)["']/i, "app.js must issue no write requests");
  assert.doesNotMatch(app, /\.innerHTML\s*=/, "app.js must not set innerHTML");
  assert.doesNotMatch(html, /<form\b/i, "the page must offer no form");
  assert.doesNotMatch(html, /\bdisabled\b/i, "no disabled controls: a write control the adjudicator can see is a write control");
  assert.match(html, /Every value on this page was computed by/, "the footer statement is missing");
  assert.match(html, /UI state is not part of any identity/, "the footer statement is missing");
});

test("the server refuses to leave its directory", async () => {
  const { spawn } = await import("node:child_process");
  const port = 8979;
  const srv = spawn(process.execPath, [join(V, "bin", "g05.mjs"), "--port", String(port), "--dir", FIXTURE], { stdio: ["ignore", "pipe", "pipe"] });
  try {
    await new Promise((ok, no) => {
      srv.stdout.once("data", (d) => (String(d).includes("http://") ? ok() : no(new Error("no url printed"))));
      srv.once("error", no);
      setTimeout(() => no(new Error("server did not start")), 5000);
    });
    const base = `http://127.0.0.1:${port}`;
    assert.equal((await fetch(`${base}/index.html`)).status, 200);
    assert.equal((await fetch(`${base}/data/index.json`)).status, 200);
    assert.equal((await fetch(`${base}/../package.json`)).status, 404, "a traversal must not reach outside the served directory");
    assert.equal((await fetch(`${base}/%2e%2e%2fpackage.json`)).status, 404);
    assert.equal((await fetch(`${base}/../../../etc/passwd`)).status, 404);
    assert.equal((await fetch(`${base}/index.html`, { method: "POST" })).status, 405, "the server is GET-only");
    const ct = (await fetch(`${base}/app.js`)).headers.get("content-type");
    assert.match(ct, /text\/javascript/);
  } finally { srv.kill(); }
});
