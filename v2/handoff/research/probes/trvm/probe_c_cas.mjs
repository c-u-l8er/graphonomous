// PROBE C — CAS + certificate with a Graphonomous-shaped record
import { memoryStore, artifactRoot, resolveArtifact, canonicalWireBytes, RESOLVE_OUTCOMES, ROOT_SYNTAX, WIRE_LIMITS, ARTIFACT_ROOT_PROTOCOL } from "/home/travis/ProjectAmp2/TRVM/governance/cas.mjs";
import { verifiedClaimSemId, certificateOf, CERTIFICATE_PROTOCOL } from "/home/travis/ProjectAmp2/TRVM/governance/certificate.mjs";
import { grammar, ownSnapshot } from "/home/travis/ProjectAmp2/TRVM/governance/schema.mjs";

console.log("ARTIFACT_ROOT_PROTOCOL =", ARTIFACT_ROOT_PROTOCOL, " ROOT_SYNTAX =", ROOT_SYNTAX, " limit =", WIRE_LIMITS.max_artifact_bytes);
console.log("RESOLVE_OUTCOMES =", RESOLVE_OUTCOMES.join(","));

// a Graphonomous normalized record — nothing TRVM-specific in it
const rec = { kind: "graphonomous.record", id: "S6", class: "TESTED", claims: ["S6 REDUCES_TO S1"],
  receipts: [{ receipt_id: "rcpt-1", executed: true, experiment: "Y" }], projected_from: { registry: "STACK_GAP_REGISTER.md", rev: "abc" } };
const store = memoryStore(new Map());
const root = store.put(rec);
console.log("\n[1] put Graphonomous record → root =", root);
const r = resolveArtifact(store, root);
console.log("    resolve outcome =", r.outcome, " bytes =", r.bytes.length, " artifact.class =", r.artifact.class);
console.log("    artifactRoot(rec) === root :", artifactRoot(rec) === root);
console.log("    artifactRoot(same rec, keys reordered) === root :", artifactRoot({ receipts: rec.receipts, projected_from: rec.projected_from, claims: rec.claims, class: rec.class, id: rec.id, kind: rec.kind }) === root);

// 2. hostile store: pretty-printed bytes under the honest root
const bad = memoryStore(new Map([[root, Buffer.from(JSON.stringify(rec, null, 2), "utf8")]]));
console.log("\n[2] pretty-printed bytes under the honest root →", resolveArtifact(bad, root).outcome);
const dup = memoryStore(new Map([[root, Buffer.from('{"class":"UNTESTED",' + canonicalWireBytes(rec).toString("utf8").slice(1), "utf8")]]));
console.log("    duplicate-key forgery (class twice) →", resolveArtifact(dup, root).outcome);
console.log("    traversal citation '../proof_bundle' →", resolveArtifact(store, "../proof_bundle").outcome);
console.log("    unknown root →", resolveArtifact(store, "root-" + "0".repeat(64)).outcome);

// 3. a "projection root": a manifest of record roots, itself content-addressed
const roots = [rec, { ...rec, id: "S1", class: "PROVEN" }, { ...rec, id: "S9", class: "TESTED", receipts: [] }].map((x) => store.put(x));
const projection = { kind: "graphonomous.projection", registry_rev: "abc", records: roots.slice().sort() };
const proot = store.put(projection);
console.log("\n[3] projection manifest root =", proot, " resolves:", resolveArtifact(store, proot).outcome);
// a certificate over it, using TRVM's claim-qualified identity
const cert = verifiedClaimSemId({ protocol: "GRAPHONOMOUS-PROJECTION-v0", claim_sem_id: "gclaim-" + proot.slice(5),
  aggregate_id: "gagg-" + store.put({ unsupported: ["S9"], tested_with_receipt: ["S6"] }).slice(5), chain_ids: { projector: "gp-0.1", rev: "abc" } });
console.log("    verifiedClaimSemId over a Graphonomous projection →", cert);
try { verifiedClaimSemId({ protocol: "X", claim_sem_id: "c", aggregate_id: "a" }); } catch (e) { console.log("    missing chain_ids →", e.message); }
console.log("    CERTIFICATE_PROTOCOL =", CERTIFICATE_PROTOCOL, " (binds protocol, claim_sem_id, aggregate_id, chain_ids; no verdict, no signature)");
// 4. grammar(): the exact-key-set check as a reusable ingredient
console.log("\n[4] grammar(rec, required=[kind,id,class,claims,receipts,projected_from]) →", JSON.stringify(grammar(rec, { required: ["kind", "id", "class", "claims", "receipts", "projected_from"] })));
console.log("    grammar with an extra field →", JSON.stringify(grammar({ ...rec, verdict: "VERIFIED" }, { required: ["kind", "id", "class", "claims", "receipts", "projected_from"] })));
