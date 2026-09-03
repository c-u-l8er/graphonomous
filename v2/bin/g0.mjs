#!/usr/bin/env node
/* g0 — the G0 command line.
 *   g0 snapshot --label <l> --r10 <commit> --package <dir> [--computedriven <c>] [--super <c>] [--trvm <c>] [--wrl <c>] [--factory <c> [--factory-ledger]] --out <file>
 *               --factory-ledger (G0-F): the factory source pins EVERY file adapters/factory.mjs reads (ledger, mosaic
 *               assumptions/sources, the 20 receipts, cells.json, every witness path) and params.adapters = [crosswalk, factory]
 *   g0 project  --snapshot <file> --out <dir> [--shuffle <seed>] [--reverse-adapters]
 *   g0 verify   --dir <dir>
 *   g0 census   --dir <dir>
 *   g0 eval     --dir <dir>                       run the rule program; writes <dir>/derived (G0-E)
 *   g0 verify-eval --dir <dir>                    replay every stored derivation through the independent checker
 *   g0 query    --dir <dir>[,<dir>…] <fn> <args…>  node|neighbors|path|facts|explain|as_of (JSON args; JSON out)
 *   g0 world    --dir <dir>                       G0-C: seals the semantic world through WRL — writes <dir>/world (sem-, kernel rel-/rev-);
 *                                                 a D-037 spike world/ is moved to world-spike/ first
 *   g0 certify  --dir <dir>                       G0-D: writes <dir>/certificate/{bundle.json,VCLAIM} (GRAPHONOMOUS-PROJECTION-v0); puts the
 *                                                 snapshot record into <dir>/cas beside the manifest (the root does not move)
 *   g0 check-cert --dir <dir> [--bundle <file>]   re-derives everything from <dir> and checks the bundle; exit 1 on REFUSED; writes nothing
 */
import { readFileSync, writeFileSync } from "node:fs";
import { resolve, join } from "node:path";
import { fileURLToPath } from "node:url";
import { dirname } from "node:path";
import { openRepo } from "../adapters/git.mjs";
import { project, verify } from "../lib/project.mjs";
import { canonicalBytesG0, sortSet } from "../lib/canon.mjs";
import { makeLid } from "../lib/lid.mjs";
import { factoryFiles } from "../adapters/factory.mjs";

const HERE = dirname(fileURLToPath(import.meta.url)); const AMP = resolve(HERE, "../../..");
const args = process.argv.slice(2); const cmd = args.shift();
const opt = (n, d) => { const i = args.indexOf("--" + n); return i >= 0 ? (args[i + 1] ?? true) : d; };
const flag = (n) => args.includes("--" + n);

if (cmd === "snapshot") {
  const label = opt("label"); const pkg = opt("package"); const outFile = opt("out");
  const r10 = openRepo("invariant-r10", resolve(AMP, "invariant-r10"), opt("r10"));
  const sources = [];
  const reg = (namespace, repo, files) => sources.push({ namespace, registry: makeLid("REGISTRY", namespace, `${repo.name}@${repo.commit.slice(0, 12)}`).lid, repo: repo.name, commit: repo.commit, tree: repo.tree, files: sortSet(files.filter((p) => repo.has(p)).map((p) => ({ path: p, blob: repo.blobOid(p), sha256: repo.sha256(p), bytes: repo.bytes(p).length }))) });
  reg("r10", r10, [`${pkg}/CROSS_REGISTRY_CLAIM_MAP.json`, `${pkg}/evidence_state.json`, `${pkg}/10_MACHINE_READABLE_LEDGER.json`, `${pkg}/INV_FRONTIER_R10_PRE.md`, `${pkg}/12_R10PRE_SYNTHESIS.md`, "inputs-gpt-execution-adjudication.md", ...r10.under(`${pkg}/inputs/`), ...r10.under(`${pkg}/witnesses/`), ...r10.under("handoffs/")]);
  const HOME = process.env.HOME;
  for (const [ns, dir, name, key] of [["computedriven", "computedriven", "computedriven", "computedriven"], ["super", "super", "super", "super"], ["trvm", "TRVM", "TRVM", "trvm"], ["wrl", "WRL", "WRL", "wrl"], ["factory", `${HOME}/.invariant-factory/canonical.git`, "invariant-factory", "factory"]]) {
    const c = opt(key); if (!c) continue; const repoDir = dir.startsWith("/") ? dir : resolve(AMP, dir); const repo = openRepo(name, repoDir, c);
    const files = ns === "computedriven" ? ["docs/admission-model.md", "docs/durable-authority-model.md", "docs/failure-model.md", "cd-core/src/locus.rs", "cd-core/src/authority.rs", "receipts/R0.7.md"] : ns === "super" ? ["README.md", "ampd/README.md"] : ns === "trvm" ? ["governance/invariant-grid.json", "LAWS.md", "WRL_CORE_0.2.md"] : ns === "wrl" ? ["wrl.js"] : flag("factory-ledger") ? [...new Set(["CLAIM_LEDGER.json", "mosaic/embodiment.json", "scripts/emb-support.mjs", ...factoryFiles(repo)])] : ["CLAIM_LEDGER.json", "mosaic/embodiment.json", "scripts/emb-support.mjs"];
    const src = { namespace: ns, registry: makeLid("REGISTRY", ns, `${repo.name}@${repo.commit.slice(0, 12)}`).lid, repo: repo.name, commit: repo.commit, tree: repo.tree, files: sortSet(files.filter((p) => repo.has(p)).map((p) => ({ path: p, blob: repo.blobOid(p), sha256: repo.sha256(p), bytes: repo.bytes(p).length }))) };
    if (dir.startsWith("/")) src.repo_dir = repoDir;
    sources.push(src);
  }
  const params = { package_dir: pkg, ...(flag("factory-ledger") ? { adapters: ["crosswalk", "factory"] } : {}) };
  if (flag("factory-ledger") && !sources.some((s) => s.namespace === "factory")) { console.error("--factory-ledger needs --factory <commit>"); process.exit(2); }
  const snap = { id: `snapshot:g0:${label}`, spec: "G0_G1_SPEC.md@2026-09-02", label, params, sources: sortSet(sources), taken_at: new Date().toISOString() };
  writeFileSync(outFile, JSON.stringify(snap, null, 1) + "\n");
  console.log(`snapshot ${snap.id}: ${sources.length} sources, ${sources.reduce((n, s) => n + s.files.length, 0)} pinned files → ${outFile}`);
} else if (cmd === "project") {
  const res = project(opt("snapshot"), { out: opt("out"), shuffleSeed: opt("shuffle") !== undefined ? Number(opt("shuffle")) : undefined, reverseAdapters: flag("reverse-adapters") });
  console.log(JSON.stringify({ root: res.root, counts: res.counts, faults_by_code: res.by_code, head_drift: res.drift }, null, 1));
} else if (cmd === "verify") {
  const v = verify(opt("dir")); console.log(JSON.stringify(v, null, 1)); process.exit(v.problems.length ? 1 : 0);
} else if (cmd === "census") {
  const dir = opt("dir"); const m = JSON.parse(readFileSync(resolve(dir, "manifest.json"), "utf8"));
  const kinds = {}; for (const [lid] of m.entries) { const k = lid.split(":")[0]; kinds[k] = (kinds[k] || 0) + 1; }
  const nodes = readFileSync(resolve(dir, "records/node.jsonl"), "utf8").split("\n").filter(Boolean).map((l) => JSON.parse(l));
  const nk = {}; for (const n of nodes) nk[n.kind] = (nk[n.kind] || 0) + 1;
  const rels = readFileSync(resolve(dir, "records/relation.jsonl"), "utf8").split("\n").filter(Boolean).map((l) => JSON.parse(l));
  const rk = {}; for (const r of rels) rk[r.kind] = (rk[r.kind] || 0) + 1;
  console.log(JSON.stringify({ root: readFileSync(resolve(dir, "ROOT"), "utf8").trim(), entries: m.count, by_prefix: kinds, node_kinds: nk, relation_kinds: rk, faults: m.faults }, null, 1));
} else if (cmd === "eval") {
  const { runEvaluation } = await import("../lib/evaluation.mjs");
  const r = runEvaluation(opt("dir")); console.log(JSON.stringify({ root: r.root, projection_root: r.manifest.projection_root, ruleset: r.manifest.ruleset, count: r.manifest.count, by_rule: r.manifest.by_rule, digest: r.manifest.digest, checker: r.manifest.checker, trvm_derivation: r.manifest.trvm_derivation }, null, 1));
} else if (cmd === "verify-eval") {
  const { verifyEvaluation } = await import("../lib/evaluation.mjs");
  const v = verifyEvaluation(opt("dir")); console.log(JSON.stringify(v, null, 1)); process.exit(v.problems.length ? 1 : 0);
} else if (cmd === "query") {
  const { Projections } = await import("../lib/query.mjs");
  const dirs = String(opt("dir")).split(","); const P = new Projections(dirs);
  const rest = args.filter((a, i) => !(a.startsWith("--") || (i > 0 && args[i - 1].startsWith("--"))));
  const [fn, ...fnArgs] = rest; const parse = (x) => { try { return JSON.parse(x); } catch { return x; } };
  let g = P.as_of(opt("as-of", P.snapshots()[0]));
  if (fn === "as_of") { g = P.as_of(fnArgs[0]); console.log(JSON.stringify({ snapshot: g.snapshot, root: g.root, derived: g.derived ? g.derived.root : null })); }
  else if (["node", "neighbors", "path", "facts", "explain"].includes(fn)) console.log(JSON.stringify(g[fn](...fnArgs.map(parse)), null, 1));
  else { console.error("usage: g0 query --dir <dir>[,<dir>] [--as-of <snapshot>] node|neighbors|path|facts|explain|as_of <json args…>"); process.exit(2); }
} else if (cmd === "world") {
  const { buildWorld, loadProfile, DEFAULT_PROFILE_ID } = await import("../lib/wrl_world.mjs");
  // --profile selects the WRL profile row to seal under; absent it is graphonomous.semantic.v0, so every existing
  // invocation reproduces the world it produced before v1 existed (D-064).
  const profile = loadProfile(opt("profile", DEFAULT_PROFILE_ID));
  const w = await buildWorld(opt("dir"), { profile, out: opt("out", join(opt("dir"), "world")) }); console.log(JSON.stringify({ sem: w.sem, profile_id: w.profile_id, projection_root: w.projection_root, objects: w.objects, relations: w.relations.length, canonical_bytes: w.bytes, wrl: w.wrl, state: w.state, supersedes: w.supersedes, spike_reproduced: w.spike_reproduced, sample: w.relations.slice(0, 3) }, null, 1));
} else if (cmd === "certify") {
  const { buildCertificate } = await import("../lib/certificate.mjs");
  const c = buildCertificate(opt("dir"));
  console.log(JSON.stringify({ verified_claim_sem_id: c.verified_claim_sem_id, artifact_root: c.artifact_root, bundle_bytes: c.bytes.length, protocol: c.bundle.protocol, claim: c.bundle.claim, aggregate_id: c.bundle.aggregate.aggregate_id, chain_ids: c.bundle.chain_ids, references: c.bundle.references, structure: c.bundle.structure }, null, 1));
} else if (cmd === "check-cert") {
  const { checkCertificate } = await import("../lib/certificate.mjs");
  const bundle = opt("bundle") ? readFileSync(resolve(opt("bundle"))) : undefined;
  const r = checkCertificate(opt("dir"), bundle);
  const m = r.measured;
  console.log(JSON.stringify({ ok: r.ok, verdict: r.verdict, codes: r.codes, refusals: r.refusals, verified_claim_sem_id: m.verified_claim_sem_id, stated_verified_claim_sem_id: m.stated_verified_claim_sem_id, projection_root: m.projection_root, snapshot_commitment: m.snapshot_commitment, projection_claim_sem_id: m.projection_claim_sem_id, aggregate_id: m.aggregate_id, schema_set_id: m.schema_set_id, adapter_contract_id: m.adapter_contract_id, ruleset: m.ruleset, entries_checked: m.entries_checked, cas_objects: m.cas_objects, writes: m.writes }, null, 1));
  process.exit(r.ok ? 0 : 1);
} else { console.error("usage: g0 snapshot|project|verify|census|eval|verify-eval|query|world|certify|check-cert …"); process.exit(2); }
