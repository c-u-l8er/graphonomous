// PROBE G0-D/1 — the minimal reproducer for GAP-T9: can TRVM's nest checker judge a
// GRAPHONOMOUS-PROJECTION-v0 child today? READ-ONLY: imports TRVM governance files by absolute
// path at fd0df4c, writes nothing, uses a memory store only.
"use strict";
import { createHash } from "node:crypto";
import { canonicalBytes } from "/home/travis/ProjectAmp2/TRVM/governance/derive_protocol.mjs";
import { memoryStore, artifactRoot, artifactBytes, resolveArtifact } from "/home/travis/ProjectAmp2/TRVM/governance/cas.mjs";
import { verifiedClaimSemId, certificateOf, CERTIFICATE_PROTOCOL } from "/home/travis/ProjectAmp2/TRVM/governance/certificate.mjs";
import {
  checkNestBundle, checkNestBytes, IMPLEMENTED_CHILD_PROTOCOLS, SHIPPED_POLICY, effectivePolicy, deriveChainIds, GRAMMAR,
} from "/home/travis/ProjectAmp2/TRVM/governance/nest_check.mjs";
import {
  NEST_PROTOCOL, NEST_CLAIM_SCOPE, REFERENCE_CONTRACT, CONNECTIVE, nestedClaimSemId, nestAggregateId, nestStructureSemId,
  buildNestBundle, operandFor, referenceFor, CHILD_PROTOCOLS,
} from "/home/travis/ProjectAmp2/TRVM/governance/nest_bundle.mjs";
import { checkComposeBundle } from "/home/travis/ProjectAmp2/TRVM/governance/compose_check.mjs";
import { COMPOSE_PROTOCOL } from "/home/travis/ProjectAmp2/TRVM/governance/compose_bundle.mjs";

const H = (s) => createHash("sha256").update(s).digest("hex");
const say = (...a) => console.log(...a);

/* ── 1. a Graphonomous-shaped child bundle, small but complete in the four bound values ─────────── */
const PROTO = "GRAPHONOMOUS-PROJECTION-v0";
const projection_root = "root-da4f3d7a534801e0aedbfee4853cba989e24e5107c28e02ad83507a044afef85"; // baseline, D-049
const chain_ids = {
  trvm_commit: "fd0df4cdf6ea196f4b48c07b777fdbbfba1e2873",
  trvm_blobs: { "governance/cas.mjs": "4b84dff4b4d1fd68412c579cd9683b8dc4075d7f",
    "governance/derive_protocol.mjs": "8ec73d9b3401e1e013388c6daf9d8b2c63d43954" },
  projector: "graphonomous.g0.project.v0",
};
const claim = {
  projection_root,
  snapshot_commitment: "gsnap-" + H("x"),
  ruleset: "g0rule-" + "0".repeat(64),
  spec: "G0_G1_SPEC.md@2026-09-02",
  scope: { kind: "PROJECTION_RECONSTRUCTION_IDENTITY", truth_claimed: false, warrant: false },
  projection_claim_sem_id: null,
};
const { projection_claim_sem_id: _c, ...claimRest } = claim; // canonicalBytes REFUSES an undefined member (derive_protocol.mjs:350), so omit, never null-out
claim.projection_claim_sem_id = "gclaim-" + H(PROTO + "|" + canonicalBytes({ ...claimRest, protocol: PROTO }));
const aggregate = { entries: 3005, per_kind: [["node", 1]], faults: 0, aggregate_id: null };
const { aggregate_id: _a, ...aggRest } = aggregate;
aggregate.aggregate_id = "gagg-" + H(PROTO + "|" + canonicalBytes(aggRest));
const child = { protocol: PROTO, claim, chain_ids, aggregate,
  references: { contract: { resolution: "CONTENT_ADDRESSED", wire: "CANONICAL", address_is_a_warrant: false },
    operands: [{ artifact_root: projection_root }] },
  structure: { entries: 3005 },
  annotations: { note: "NON-AUTHORITATIVE prose" } };

/* ── 2. verifiedClaimSemId mints for the protocol, and THIS is the preimage ────────────────────── */
const cert = certificateOf(child, "projection_claim_sem_id");
const preimageObj = { certificate_protocol: CERTIFICATE_PROTOCOL, protocol: cert.protocol, claim_sem_id: cert.claim_sem_id,
  aggregate_id: cert.aggregate_id, chain_ids: cert.chain_ids };
const preimage = CERTIFICATE_PROTOCOL + "|" + canonicalBytes(preimageObj);
const vclaim = verifiedClaimSemId(cert);
say("[2] certificateOf(child, 'projection_claim_sem_id') =", JSON.stringify(cert).slice(0, 160) + "…");
say("    preimage bytes (" + Buffer.byteLength(preimage) + " octets):");
say("    " + preimage);
say("    verifiedClaimSemId =", vclaim);
say("    re-derived by hand   =", "vclaim-" + H(preimage), " equal:", vclaim === "vclaim-" + H(preimage));
say("    reword annotations → ", verifiedClaimSemId(certificateOf({ ...child, annotations: { note: "other" } }, "projection_claim_sem_id")) === vclaim ? "HOLDS" : "MOVED");
say("    change chain_ids.projector → ",
  verifiedClaimSemId({ ...cert, chain_ids: { ...chain_ids, projector: "v1" } }) === vclaim ? "HOLDS" : "MOVED");
say("    change claim_sem_id → ", verifiedClaimSemId({ ...cert, claim_sem_id: "gclaim-" + H("y") }) === vclaim ? "HOLDS" : "MOVED");
try { verifiedClaimSemId({ protocol: PROTO, claim_sem_id: cert.claim_sem_id, aggregate_id: cert.aggregate_id }); }
catch (e) { say("    missing chain_ids →", e.message); }

/* ── 3. store the child the way nest_check resolves references; wrap in a one-operand nest bundle ── */
const store = memoryStore(new Map());
const childRoot = store.put(child);
say("\n[3] child stored:", childRoot, " resolve:", resolveArtifact(store, childRoot).outcome, " bytes:", artifactBytes(child));
say("    IMPLEMENTED_CHILD_PROTOCOLS =", Object.keys(IMPLEMENTED_CHILD_PROTOCOLS).join(", "));
say("    Object.isFrozen(IMPLEMENTED_CHILD_PROTOCOLS) =", Object.isFrozen(IMPLEMENTED_CHILD_PROTOCOLS));

// the producer refuses first
try { buildNestBundle([child]); } catch (e) { say("    buildNestBundle([child]) →", e.message); }

// so build the nest bundle by hand, exactly as buildNestBundle would if it knew the protocol
const op = operandFor(child, "projection_claim_sem_id");
const operands = [op];
const verdicts = { [op.verified_claim_sem_id]: "VERIFIED" };
const aggN = { operands: 1, child_verdicts: verdicts, leaf_receipts_rederived_by_parent: 0, films_replayed_by_parent: 0,
  nested_verdict: "VERIFIED", aggregate_id: null };
aggN.aggregate_id = nestAggregateId(aggN);
const bytes = artifactBytes(child);
const st = { edges: 1, unique_artifacts: 1, max_depth_below: 1, bytes_if_inlined: bytes, unique_bytes: bytes,
  films_below_by_edge_multiplicity: 0, films_below_distinct: 0, cases_below_by_edge_multiplicity: 0, cases_below_distinct: 0,
  structure_sem_id: null };
st.structure_sem_id = nestStructureSemId(st);
const nest = { type: "NestedComposition", protocol: NEST_PROTOCOL, version: "0.2.0",
  claim: { connective: CONNECTIVE, scope: NEST_CLAIM_SCOPE, operands, nested_claim_sem_id: nestedClaimSemId(CONNECTIVE, NEST_CLAIM_SCOPE, operands) },
  chain_ids: deriveChainIds([child]),
  references: { contract: REFERENCE_CONTRACT, operands: [referenceFor(child, op.verified_claim_sem_id)] },
  aggregate: aggN, structure: st };
say("    nest bundle chain_ids (derived from the child) =", JSON.stringify(nest.chain_ids).slice(0, 120) + "…");

const r = checkNestBundle(nest, { store });
say("\n[3a] checkNestBundle(nest, {store}) → ok:", r.ok, "verdict:", r.verdict);
for (const x of r.refusals) say("     " + x.code + ": " + x.detail);
say("     measured.refusal_codes_transitive =", JSON.stringify(r.measured.refusal_codes_transitive));
say("     checker_evaluations =", r.measured.checker_evaluations, " unique_artifact_resolutions =", r.measured.unique_artifact_resolutions);

/* ── 4. every route a caller might take to register the protocol, and why each is closed ────────── */
say("\n[4] registration routes:");
try { IMPLEMENTED_CHILD_PROTOCOLS[PROTO] = { claim_field: "projection_claim_sem_id", check: () => ({ ok: true, verdict: "VERIFIED", refusals: [], measured: {} }), composed: false }; say("    (a) assignment to the frozen table: no throw?!"); }
catch (e) { say("    (a) assignment to the frozen table →", e.constructor.name + ": " + e.message); }
say("        table still =", Object.keys(IMPLEMENTED_CHILD_PROTOCOLS).join(", "));
const pol = effectivePolicy({ child_protocols: { [PROTO]: {} } });
say("    (b) checkNestBundle(nest, {store, child_protocols:{…}}) → effectivePolicy:", JSON.stringify(pol));
const r2 = checkNestBundle(nest, { store, child_protocols: { [PROTO]: { claim_field: "projection_claim_sem_id" } } });
say("        → verdict:", r2.verdict, "refusals:", r2.refusals.map((x) => x.code).join(", "));
say("    (c) SHIPPED_POLICY fields =", Object.keys(SHIPPED_POLICY).join(", "), "— no registry field exists");
say("    (d) producer table CHILD_PROTOCOLS frozen:", Object.isFrozen(CHILD_PROTOCOLS), "; nest_check declares its own copy and does not import it (nest_check.mjs:151)");
say("    (e) the bytes boundary is the same checker:", checkNestBytes(Buffer.from(canonicalBytes(nest), "utf8"), { store }).refusals.map((x) => x.code).join(", "));

/* ── 5. the sibling composer refuses identically ───────────────────────────────────────────────── */
const compose = { protocol: COMPOSE_PROTOCOL, claim: { connective: "CONJUNCTION", operands: [op] },
  children: [{ verified_claim_sem_id: op.verified_claim_sem_id, bundle: child }], aggregate: {} };
const rc = checkComposeBundle(compose);
say("\n[5] checkComposeBundle over the same child → codes:", [...new Set(rc.refusals.map((x) => x.code))].join(", "));

/* ── 6. what the two real leaf protocols carry as chain_ids, and what aggregate_id commits to ──── */
import { chainIds, PROOF_PROTOCOL } from "/home/travis/ProjectAmp2/TRVM/governance/proof_bundle.mjs";
const live = chainIds();
say("\n[6] leaf chain_ids() keys =", Object.keys(live).join(", "));
say("    e.g. lowering_version =", live.lowering_version, " canonical_emitter_profile_id =", String(live.canonical_emitter_profile_id).slice(0, 40) + "…");
say("    nest GRAMMAR.bundle.required =", GRAMMAR.bundle.required.join(", "), "| optional =", GRAMMAR.bundle.optional.join(", "));
say("    nest GRAMMAR.operand.required =", GRAMMAR.operand.required.join(", "));
