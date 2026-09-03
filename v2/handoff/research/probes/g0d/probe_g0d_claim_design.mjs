// PROBE G0-D/2 — a candidate GRAPHONOMOUS-PROJECTION-v0 claim over the REAL baseline projection.
// READ-ONLY: reads projections/baseline/{ROOT,manifest.json,snapshot.json}, rules, schemas, adapters; writes nothing.
"use strict";
import { readFileSync, readdirSync } from "node:fs";
import { createHash } from "node:crypto";
import { canonicalBytesG0, hashRecord, sortSet, gitBlobOid, TRVM_PIN, assertTrvmPinned, artifactRoot } from "/home/travis/ProjectAmp2/graphonomous/v2/lib/canon.mjs";
import { loadRules } from "/home/travis/ProjectAmp2/graphonomous/v2/lib/rules.mjs";
import { verifiedClaimSemId } from "/home/travis/ProjectAmp2/TRVM/governance/certificate.mjs";

const V = "/home/travis/ProjectAmp2/graphonomous/v2";
const H = (b) => createHash("sha256").update(b).digest("hex");
const PROTO = "GRAPHONOMOUS-PROJECTION-v0";
const say = (...a) => console.log(...a);

const root = readFileSync(`${V}/projections/baseline/ROOT`, "utf8").trim();
const manifest = JSON.parse(readFileSync(`${V}/projections/baseline/manifest.json`, "utf8"));
const snap = JSON.parse(readFileSync(`${V}/projections/baseline/snapshot.json`, "utf8")); // witness already stripped
say("[1] baseline ROOT =", root, " artifactRoot(manifest) equal:", artifactRoot(manifest) === root);
say("    manifest keys =", Object.keys(manifest).sort().join(", "));
say("    manifest.snapshot =", manifest.snapshot, " ruleset =", manifest.ruleset.slice(0, 24) + "…", " adapter_runs =", manifest.adapter_runs.length);
say("    snapshot sources (declared order) =", snap.sources.map((s) => s.namespace).join(" → "));

/* snapshot commitment: the SET of source identities, order-independent, dropped-source-sensitive */
const sourceIdentity = (s) => ({ namespace: s.namespace, registry: s.registry, repo: s.repo, commit: s.commit, tree: s.tree,
  files: sortSet(s.files.map((f) => ({ path: f.path, blob: f.blob, sha256: f.sha256, bytes: f.bytes }))) });
const snapshotCommitment = (sources) => "gsnap-" + H(Buffer.concat([Buffer.from(PROTO + "|snapshot|", "utf8"), canonicalBytesG0(sortSet(sources.map(sourceIdentity)))]));
const c0 = snapshotCommitment(snap.sources);
const permuted = snap.sources.slice().reverse();
const dropped = snap.sources.filter((s) => s.namespace !== "trvm");
const naiveHash = (sources) => hashRecord({ ...snap, sources }).hash;
say("\n[2] snapshot commitment (sorted set of source identities) =", c0);
say("    reversed source order →", snapshotCommitment(permuted) === c0 ? "HOLDS (order-independent)" : "MOVED");
say("    dropped source 'trvm' →", snapshotCommitment(dropped) === c0 ? "HOLDS (!)" : "MOVED (dropped source refused)");
say("    for contrast, hashRecord(snapshot) as stored: reversed order →", naiveHash(permuted) === naiveHash(snap.sources) ? "HOLDS" : "MOVED (the stored snapshot hash is ORDER-DEPENDENT)");
say("    duplicate source →", (() => { try { snapshotCommitment([...snap.sources, snap.sources[0]]); return "accepted (!)"; } catch (e) { return "refused: " + e.code; } })());

/* schema set identity and adapter contract identity */
const schemaFiles = readdirSync(`${V}/schemas`).filter((f) => f.endsWith(".schema.json")).sort();
const schema_set_id = "gschema-" + H(canonicalBytesG0(schemaFiles.map((f) => [f, gitBlobOid(readFileSync(`${V}/schemas/${f}`))])));
const adapterFiles = readdirSync(`${V}/adapters`).filter((f) => f.endsWith(".mjs")).sort();
const adapter_contract_id = "gadapt-" + H(canonicalBytesG0(adapterFiles.map((f) => [f, gitBlobOid(readFileSync(`${V}/adapters/${f}`))])));
const rules = loadRules();
say("\n[3] schema_set_id =", schema_set_id.slice(0, 30) + "… over", schemaFiles.length, "schemas");
say("    adapter_contract_id =", adapter_contract_id.slice(0, 30) + "… over", adapterFiles.join(", "));
say("    ruleset (loaded) =", rules.rule_sem_id.slice(0, 30) + "… equals manifest.ruleset:", rules.rule_sem_id === manifest.ruleset);
say("    TRVM pin verified:", JSON.stringify(assertTrvmPinned()).slice(0, 90) + "…");

/* the claim, the aggregate, the chain, the certificate */
const claimBody = { protocol: PROTO, projection_root: root, snapshot_commitment: c0, snapshot_id: manifest.snapshot,
  spec: manifest.spec, ruleset: manifest.ruleset, schema_set_id, adapter_contract_id,
  scope: { kind: "PROJECTION_RECONSTRUCTION_IDENTITY", quantifier: "OVER_THE_PINNED_SOURCE_SET", truth_claimed: false,
    evidence_sufficiency_claimed: false, state_promoted: false, registry_written: false, trvm_derivation: false } };
const projection_claim_sem_id = "gclaim-" + H(Buffer.concat([Buffer.from(PROTO + "|", "utf8"), canonicalBytesG0(claimBody)]));
const aggBody = { count: manifest.count, per_kind: manifest.per_kind, faults: manifest.faults, adapter_runs: manifest.adapter_runs };
const aggregate_id = "gagg-" + H(Buffer.concat([Buffer.from(PROTO + "|", "utf8"), canonicalBytesG0(aggBody)]));
const chain_ids = { trvm_commit: TRVM_PIN.commit, trvm_blobs: TRVM_PIN.blobs, projector: "graphonomous.g0.project.v0",
  checker: "graphonomous.g0.certificate_check.v0", node_semver_major: null };
const chain = { ...chain_ids }; delete chain.node_semver_major; // no run-dependent value in the chain
const vclaim = verifiedClaimSemId({ protocol: PROTO, claim_sem_id: projection_claim_sem_id, aggregate_id, chain_ids: chain });
say("\n[4] projection_claim_sem_id =", projection_claim_sem_id);
say("    aggregate_id =", aggregate_id);
say("    verified_claim_sem_id =", vclaim);
const move = (label, patch) => {
  const body = { ...claimBody, ...patch };
  const cid = "gclaim-" + H(Buffer.concat([Buffer.from(PROTO + "|", "utf8"), canonicalBytesG0(body)]));
  const v = verifiedClaimSemId({ protocol: PROTO, claim_sem_id: cid, aggregate_id, chain_ids: chain });
  say(`    ${label.padEnd(34)} claim ${cid === projection_claim_sem_id ? "HOLDS" : "MOVED"} · certificate ${v === vclaim ? "HOLDS" : "MOVED"}`);
};
move("projection_root changed", { projection_root: "root-" + "0".repeat(64) });
move("snapshot: source dropped", { snapshot_commitment: snapshotCommitment(dropped) });
move("snapshot: sources reordered", { snapshot_commitment: snapshotCommitment(permuted) });
move("ruleset changed", { ruleset: "g0rule-" + "1".repeat(64) });
move("schema set changed", { schema_set_id: "gschema-x" });
move("adapter contract changed", { adapter_contract_id: "gadapt-x" });
move("protocol id bumped to v1", { protocol: "GRAPHONOMOUS-PROJECTION-v1" });
const vProse = verifiedClaimSemId({ protocol: PROTO, claim_sem_id: projection_claim_sem_id, aggregate_id, chain_ids: chain });
say("    witness.json / README / prose changed  claim HOLDS · certificate", vProse === vclaim ? "HOLDS" : "MOVED", "(not in any bound value)");
const vChain = verifiedClaimSemId({ protocol: PROTO, claim_sem_id: projection_claim_sem_id, aggregate_id, chain_ids: { ...chain, trvm_commit: "deadbeef" } });
say("    TRVM pin moved (chain)                 claim HOLDS · certificate", vChain === vclaim ? "HOLDS" : "MOVED");
say("    certificate copied to another snapshot: the checker recomputes claim from the projection dir it is handed;",
  "a different ROOT ⇒ different projection_root ⇒ nest-style 'certificate-stale' refusal (relation, not value)");
