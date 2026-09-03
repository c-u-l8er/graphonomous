#!/usr/bin/env node
/* g05_build.mjs — the G0.5 data compiler: Node computes, the browser renders.
 *
 * G0.5 is a READ-ONLY inspector over the built projections. The page it feeds does lookups and rendering and nothing
 * else: it never hashes, never evaluates a rule, never re-derives an explanation. So every answer the page can show is
 * computed HERE, in Node, by the library that owns it — lib/query.mjs (the six-function Graph surface: node ·
 * neighbors · path · facts · explain · as_of) and lib/acceptance.mjs (A1–A7) — and written to ui/data/<slug>.json.
 *
 * ONE FILE PER SNAPSHOT ROOT. A world file holds records from exactly one projection; the page loads one world at a
 * time and the file itself is the boundary. Nothing here merges two roots (spec §10.2 / G0.5 constraint 6).
 *
 * WHAT IS BAKED, AND WHY THAT SHAPE — the choice the brief asks to have documented:
 *
 *   explain.records[lid] = Graph.explain(lid)            for every node lid and every relation lid
 *   explain.facts[key]   = Graph.explain([rel, ...args]) for every derived fact, key = JSON.stringify([rel, ...args])
 *
 * i.e. the FULL trees, not a lazily-shaped seed. The brief offers an alternative: store each record's
 * assertion+location join (that is `_explainRecord`) and each fact's stored `derivations` (already on the fact), and
 * let the page unfold premises through `factIndex`. That was measured on the largest world — multi: 778 nodes, 1574
 * relations, 3270 assertions, 1010 derived facts — and it saves ~0.9 MB out of ~12 MB, because the base-source map
 * the page would then need in order to unfold (`_baseSource` per base premise) is itself ~1.6 MB. Paying 0.9 MB to
 * move tree-walking into the browser is a bad trade for an inspector whose entire claim is that the screen shows what
 * Node computed: with the trees baked whole, test/g05.test.mjs asserts deep equality between what the page renders and
 * `Graph.explain(...)` for EVERY relation and EVERY derived fact rather than for a sample, and ui/app.js contains no
 * unfolding code that could drift from the library.
 *
 * `factIndex` is emitted anyway, and used: the page resolves a derived premise inside a tree to that premise's own
 * fact record — its position in `facts` — by lookup on JSON.stringify([rel, ...args]), never by hashing.
 *
 * NO UI STATE. Nothing about panels, viewports, selection or layout is computed here or stored here. Layout is a
 * function the page applies to lids at render time; it is not data, and it is in no identity (G0.5 constraint 3).
 *
 * usage: node tools/g05_build.mjs --out ui/data [--dir <projection dir> ...]
 *        defaults to projections/{baseline,historical,multi,multi-v1}
 */
import { readFileSync, existsSync, mkdirSync, writeFileSync, readdirSync, unlinkSync } from "node:fs";
import { resolve, join, dirname, basename } from "node:path";
import { fileURLToPath } from "node:url";
import { openGraph } from "../lib/query.mjs";
import { runAcceptance } from "../lib/acceptance.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const V2 = resolve(HERE, "..");
/* The four worlds GPT v5 §10.1 asks the selector to offer: three v0 and the v1 successor. Adding a world is adding a
 * directory here — the page is driven entirely by ui/data/index.json and knows none of these names. */
const DEFAULT_DIRS = ["baseline", "historical", "multi", "multi-v1"].map((d) => join(V2, "projections", d));

/* The exact phrasing the adjudicator requires next to a certificate: what a G0-D bundle establishes is that the
 * projection reconstructs under the verifier coordinates it pins — never that it is "still valid" or "still verifies",
 * which would smuggle a truth claim the scope block explicitly refuses. */
const VERIFIER_NOTE = "verifies under its pinned verifier coordinates";

export const factKeyOf = (rel, args) => JSON.stringify([rel, ...args]);
const readJSON = (p) => JSON.parse(readFileSync(p, "utf8"));
const readText = (p) => readFileSync(p, "utf8").trim();
const readLines = (p) => (existsSync(p) ? readFileSync(p, "utf8").split("\n").filter(Boolean) : []);
const sortedTally = (xs, f) => {
  const m = new Map();
  for (const x of xs) { const k = f(x); m.set(k, (m.get(k) || 0) + 1); }
  return Object.fromEntries([...m].sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0)));
};
const bySlug = (snapshotId) => snapshotId.replace(/^snapshot:g0:/, "").replace(/[^A-Za-z0-9._-]/g, "-");

/** Everything the page may show about one projection, computed by the library, keyed for lookup. */
export function buildWorld(dir, { compareGraph = null, compareName = null, graph = null } = {}) {
  const g = graph || openGraph(dir);
  const p = g.p;
  const name = basename(dir);
  const snapshotDoc = existsSync(join(dir, "snapshot.json")) ? readJSON(join(dir, "snapshot.json")) : null;

  /* ---- identity: four distinct coordinate systems, never flattened into one "the id" ---- */
  const worldDir = join(dir, "world");
  const ids = existsSync(join(worldDir, "identities.json")) ? readJSON(join(worldDir, "identities.json")) : null;
  const certDir = join(dir, "certificate");
  const bundle = existsSync(join(certDir, "bundle.json")) ? readJSON(join(certDir, "bundle.json")) : null;

  const identity = {
    snapshot: p.manifest.snapshot,
    label: snapshotDoc ? snapshotDoc.label : null,
    spec: p.manifest.spec,
    ruleset: p.manifest.ruleset,
    projection: {
      root: p.root,
      manifest_snapshot: p.manifest.snapshot,
      entries: p.manifest.count,
      per_kind: p.manifest.per_kind || null,
      faults: p.manifest.faults || null,
    },
    evaluation: p.derived
      ? {
          root: p.derived.root,
          projection_root: p.derived.manifest.projection_root,
          ruleset: p.derived.manifest.ruleset,
          evaluator: p.derived.manifest.evaluator,
          trvm_derivation: p.derived.manifest.trvm_derivation,
          count: p.derived.manifest.count,
          digest: p.derived.manifest.digest,
          by_rule: p.derived.manifest.by_rule,
          checker: p.derived.manifest.checker,
        }
      : null,
    wrl: ids
      ? {
          sem: ids.sem,
          profile_id: ids.profile_id,
          projection_root: ids.projection_root,
          snapshot: ids.snapshot,
          objects: ids.objects,
          relations: ids.relations.length,
          minted_by: [...new Set(ids.relations.map((r) => r.minted_by))].sort(),
          state: ids.state ?? null,
          supersedes: ids.supersedes ?? null,
          kernel: ids.wrl ?? null,
        }
      : null,
    certificate: bundle
      ? {
          vclaim: existsSync(join(certDir, "VCLAIM")) ? readText(join(certDir, "VCLAIM")) : null,
          protocol: bundle.protocol,
          type: bundle.type ?? null,
          version: bundle.version ?? null,
          claim: bundle.claim,
          aggregate_id: bundle.aggregate ? bundle.aggregate.aggregate_id : null,
          chain_ids: bundle.chain_ids,
          references: bundle.references ?? null,
          structure: bundle.structure ?? null,
          annotations: bundle.annotations ?? null,
          verifier_note: VERIFIER_NOTE,
        }
      : null,
    snapshot_sources: snapshotDoc
      ? snapshotDoc.sources.map((s) => ({ namespace: s.namespace, registry: s.registry, repo: s.repo, commit: s.commit, files: s.files.length }))
      : [],
    params: snapshotDoc ? snapshotDoc.params : null,
  };

  /* ---- counts ---- */
  const adapterRuns = readLines(join(dir, "records", "adapter_run.jsonl")).length;
  const counts = {
    records: {
      node: p.nodes.length,
      relation: p.relations.length,
      assertion: p.assertions.length,
      source_location: p.locations.length,
      fault: p.faults.length,
      adapter_run: adapterRuns,
    },
    node_roles: sortedTally(p.nodes, (n) => n.kind),
    relation_kinds: sortedTally(p.relations, (r) => r.kind),
    fault_codes: sortedTally(p.faults, (f) => f.code),
    derived_rules: p.derived ? sortedTally(p.derived.facts, (f) => f.rel) : {},
    registries: sortedTally(p.assertions, (a) => a.asserted_by),
    location_precision: sortedTally(p.locations, (l) => l.precision),
  };

  /* ---- WRL: the world-scoped allocation and the revision, per statement lid ---- */
  const wrl = {};
  if (ids) for (const r of [...ids.relations].sort((a, b) => (a.relation_name < b.relation_name ? -1 : 1))) {
    wrl[r.relation_name] = { rel: r.rel, rev: r.rev, minted_by: r.minted_by };
  }

  /* ---- the records, as they are on disk ---- */
  const byLid = (a, b) => (a.lid < b.lid ? -1 : a.lid > b.lid ? 1 : 0);
  const nodes = [...p.nodes].sort(byLid);
  const relations = [...p.relations].sort(byLid);
  const assertions = [...p.assertions].sort(byLid);
  const locations = [...p.locations].sort(byLid);
  const faults = [...p.faults].sort(byLid);

  /* ---- derived facts + the premise→fact lookup table ---- */
  const facts = p.derived ? p.derived.facts.slice() : [];
  const factIndex = {};
  facts.forEach((f, i) => { factIndex[factKeyOf(f.rel, f.args)] = i; });

  /* ---- the baked explanations: exactly what lib/query.mjs returns ---- */
  const explain = { records: {}, facts: {} };
  for (const n of nodes) explain.records[n.lid] = g.explain(n.lid);
  for (const r of relations) explain.records[r.lid] = g.explain(r.lid);
  for (const f of facts) explain.facts[factKeyOf(f.rel, f.args)] = g.explain([f.rel, ...f.args]);

  /* ---- A1–A7, run in Node against this root (and, where a question needs two pins, one named compare root) ---- */
  const acceptance = runAcceptance({ primary: g, ...(compareGraph ? { compare: compareGraph } : {}) });

  return {
    schema: "graphonomous.g0.5.world.v0",
    generated_by: "tools/g05_build.mjs",
    read_only: true,
    note: "Every value in this file was computed in Node by lib/query.mjs and lib/acceptance.mjs. The page displays it; it does not recompute it. Nothing here describes UI state.",
    name,
    slug: bySlug(p.manifest.snapshot),
    dir: dir.startsWith(V2) ? dir.slice(V2.length + 1) : dir,
    identity,
    counts,
    nodes,
    relations,
    assertions,
    locations,
    faults,
    wrl,
    facts,
    factIndex,
    explain,
    acceptance: {
      compare: compareGraph ? { name: compareName, snapshot: compareGraph.snapshot, root: compareGraph.root } : null,
      compare_note: compareGraph
        ? `A2 and A4 compare this root against ${compareGraph.snapshot}; every other question is answered from ${g.snapshot} alone.`
        : "no compare root was loaded: A2 and A4 refuse rather than answer from one pin",
      questions: acceptance,
    },
  };
}

/** Which other loaded world a question that needs two pins is compared against. Data-driven, never hardcoded to 3. */
function pickCompare(name, all) {
  const others = all.filter((w) => w.name !== name);
  return others.find((w) => w.name === "historical") || others.find((w) => w.name === "baseline") || others[0] || null;
}

function main() {
  const argv = process.argv.slice(2);
  const opt = (n, d) => { const i = argv.indexOf("--" + n); return i >= 0 ? (argv[i + 1] ?? d) : d; };
  const dirs = argv.reduce((acc, a, i) => (a === "--dir" && argv[i + 1] ? acc.concat(resolve(argv[i + 1])) : acc), []);
  const projections = (dirs.length ? dirs : DEFAULT_DIRS).map((d) => resolve(d));
  const out = resolve(opt("out", join(V2, "ui", "data")));

  const loaded = projections.map((dir) => ({ dir, name: basename(dir), graph: openGraph(dir) }));
  const seen = new Set();
  for (const w of loaded) {
    if (seen.has(w.graph.snapshot)) throw new Error(`two projections claim ${w.graph.snapshot}: a world file must hold exactly one root`);
    seen.add(w.graph.snapshot);
  }

  mkdirSync(out, { recursive: true });
  for (const f of readdirSync(out)) if (f.endsWith(".json")) unlinkSync(join(out, f));

  const written = [];
  for (const w of loaded) {
    const cmp = pickCompare(w.name, loaded);
    const world = buildWorld(w.dir, { graph: w.graph, compareGraph: cmp ? cmp.graph : null, compareName: cmp ? cmp.name : null });
    const bytes = Buffer.from(JSON.stringify(world), "utf8");
    const file = join(out, world.slug + ".json");
    writeFileSync(file, bytes);
    written.push({ world, file, bytes: bytes.length });
  }

  const index = {
    schema: "graphonomous.g0.5.index.v0",
    generated_by: "tools/g05_build.mjs",
    read_only: true,
    note: "One entry per snapshot root. A world file never mixes roots; the page loads one at a time.",
    worlds: written.map(({ world, bytes }) => ({
      slug: world.slug,
      name: world.name,
      file: world.slug + ".json",
      bytes,
      dir: world.dir,
      snapshot: world.identity.snapshot,
      label: world.identity.label,
      projection_root: world.identity.projection.root,
      evaluation_root: world.identity.evaluation ? world.identity.evaluation.root : null,
      sem: world.identity.wrl ? world.identity.wrl.sem : null,
      profile_id: world.identity.wrl ? world.identity.wrl.profile_id : null,
      vclaim: world.identity.certificate ? world.identity.certificate.vclaim : null,
      snapshot_commitment: world.identity.certificate ? world.identity.certificate.claim.snapshot_commitment : null,
      counts: world.counts.records,
      derived_facts: world.facts.length,
      compare: world.acceptance.compare ? world.acceptance.compare.snapshot : null,
    })),
  };
  const indexBytes = Buffer.from(JSON.stringify(index), "utf8");
  writeFileSync(join(out, "index.json"), indexBytes);

  console.log(JSON.stringify({
    out: out.startsWith(V2) ? out.slice(V2.length + 1) : out,
    worlds: written.map(({ world, bytes }) => ({
      slug: world.slug,
      snapshot: world.identity.snapshot,
      projection_root: world.identity.projection.root,
      evaluation_root: world.identity.evaluation ? world.identity.evaluation.root : null,
      sem: world.identity.wrl ? world.identity.wrl.sem : null,
      vclaim: world.identity.certificate ? world.identity.certificate.vclaim : null,
      compare: world.acceptance.compare ? world.acceptance.compare.snapshot : null,
      bytes,
      counts: world.counts.records,
      derived_facts: world.facts.length,
      explained: { records: Object.keys(world.explain.records).length, facts: Object.keys(world.explain.facts).length },
      acceptance_answered: world.acceptance.questions.filter((q) => q.answered).map((q) => q.id),
      acceptance_refused: world.acceptance.questions.filter((q) => !q.answered).map((q) => q.id),
    })),
    index: { file: "index.json", bytes: indexBytes.length },
    total_bytes: written.reduce((n, w) => n + w.bytes, 0) + indexBytes.length,
  }, null, 1));
}

if (import.meta.url === `file://${process.argv[1]}`) main();
