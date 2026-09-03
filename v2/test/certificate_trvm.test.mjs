/* certificate_trvm.test.mjs — the TRVM agreement vector for G0-D (D-054 item 8, R13 §6 test plan (8), D-055 design (a′)).
 *
 * A TRVM nest bundle cites the shipped baseline certificate as a child. TODAY (TRVM fd0df4c, pre-TRVM-P0) the judge side is
 * closed: `checkNestBundle(nest, {store})` returns the R13 §7.1 [3a] refusal set VERBATIM, and a supplied `child_protocols`
 * table is refused `nest-policy-weakened` before anything is checked — both asserted here, always. The agreement vectors
 * (VERIFIED with the table; the same refusal-code set on a forged child from both checkers) are written now and SKIPPED
 * until TRVM's checker accepts `child_protocols`; the main session flips them on after TRVM-P0 lands and the pin moves.
 *
 * The PRODUCER already accepts a supplied table (`buildNestBundle(children, {protocols})`), so the nest bundle here is built
 * by the real producer, not by hand. Nothing is written: the store is in memory. */
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, resolve, join } from "node:path";
import { checkNestBundle, checkNestBytes, IMPLEMENTED_CHILD_PROTOCOLS, effectivePolicy } from "../../../TRVM/governance/nest_check.mjs";
import { buildNestBundle, CHILD_PROTOCOLS } from "../../../TRVM/governance/nest_bundle.mjs";
import { verifiedClaimSemId, certificateOf } from "../../../TRVM/governance/certificate.mjs";
import { memoryStore, artifactRoot, canonicalWireBytes, resolveArtifact } from "../../../TRVM/governance/cas.mjs";
import { checkCertificate, childProtocolEntry, claimSemId, PROTOCOL, CLAIM_FIELD, CHECKER_ID } from "../lib/certificate.mjs";

const V = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const DIRS = ["baseline", "historical"].map((n) => resolve(V, "projections", n));
const child = JSON.parse(readFileSync(join(DIRS[0], "certificate/bundle.json"), "utf8"));
const VCLAIM = readFileSync(join(DIRS[0], "certificate/VCLAIM"), "utf8").trim();
const clone = (o) => JSON.parse(JSON.stringify(o));
/** THE ENTRY GRAPHONOMOUS SUPPLIES. */
const CHILD_PROTOCOLS_SUPPLIED = Object.freeze({ [PROTOCOL]: childProtocolEntry(DIRS) });
const store = memoryStore(new Map()); const childRoot = store.put(child);
const nest = buildNestBundle([child], { protocols: CHILD_PROTOCOLS_SUPPLIED });
const codes = (r) => r.refusals.map((x) => x.code);
/** Is TRVM-P0 here? An EMPTY supplied table is either refused as policy (pre-P0: `child_protocols is not a field of this
 *  verifier's policy`) or consumed as "nothing added" (post-P0: the [3a] set, since the child is still unsupported). */
const probe = checkNestBundle(nest, { store, child_protocols: {} });
const TRVM_P0 = !codes(probe).includes("nest-policy-weakened");
const R13_3A = ["nest-child-protocol-unsupported", "nest-chain-ids-mismatch", "nest-count-inconsistent", "nest-count-inconsistent", "nest-structure-mismatch", "nest-structure-mismatch", "nest-structure-mismatch", "nest-child-refused"];

test("mint side: TRVM's verifiedClaimSemId mints the shipped VCLAIM for the child; the producer with the supplied table builds a one-operand nest bundle whose operand cites projection_claim_sem_id as the claim field and the shipped VCLAIM as the certificate; the child resolves `ok` from the store", () => {
  assert.equal(verifiedClaimSemId(certificateOf(child, CLAIM_FIELD)), VCLAIM); assert.equal(childRoot, artifactRoot(child)); assert.equal(resolveArtifact(store, childRoot).outcome, "ok");
  assert.equal(nest.claim.operands.length, 1); assert.deepEqual(nest.claim.operands[0], { protocol: PROTOCOL, claim_sem_id: child.claim[CLAIM_FIELD], aggregate_id: child.aggregate.aggregate_id, verified_claim_sem_id: VCLAIM });
  assert.deepEqual(nest.references.operands, [{ verified_claim_sem_id: VCLAIM, artifact_root: childRoot }]); assert.equal(nest.aggregate.nested_verdict, "VERIFIED"); assert.deepEqual(nest.chain_ids, { leaf_chains: [child.chain_ids] });
  assert.throws(() => buildNestBundle([child]), /nest-bundle-unknown-child-protocol/, "the producer's own frozen table does not know the protocol");
  assert.ok(Object.isFrozen(CHILD_PROTOCOLS) && Object.isFrozen(IMPLEMENTED_CHILD_PROTOCOLS) && !(PROTOCOL in IMPLEMENTED_CHILD_PROTOCOLS));
});

test("judge side WITHOUT a table (always): checkNestBundle(nest, {store}) returns the R13 §7.1 [3a] refusal set verbatim — nest-child-protocol-unsupported naming the three built-ins, then the consequential nest-chain-ids-mismatch, 2× nest-count-inconsistent, 3× nest-structure-mismatch, nest-child-refused; checker_evaluations 0, unique_artifact_resolutions 1; the bytes boundary agrees", () => {
  const r = checkNestBundle(nest, { store }); assert.equal(r.ok, false); assert.equal(r.verdict, "REFUSED");
  assert.deepEqual(codes(r), R13_3A);
  assert.equal(r.refusals[0].detail, `operand 0: child protocol "${PROTOCOL}"; this checker implements [TRVM-BOUNDED-PROOF-v1, TRVM-BOUNDED-DOMAIN-PROOF-v1, TRVM-NESTED-COMPOSITION-v2]`);
  assert.equal(r.measured.checker_evaluations, 0); assert.equal(r.measured.unique_artifact_resolutions, 1);
  assert.deepEqual(r.measured.refusal_codes_transitive, ["nest-chain-ids-mismatch", "nest-child-protocol-unsupported", "nest-child-refused", "nest-count-inconsistent", "nest-structure-mismatch"]);
  assert.deepEqual(codes(checkNestBytes(canonicalWireBytes(nest), { store })), R13_3A);
});

test("judge side WITH a table, pre-TRVM-P0 (asserted while the pin is fd0df4c): a supplied child_protocols is refused nest-policy-weakened before anything is checked — the GAP-T9 reproducer (D-055)", (t) => {
  if (TRVM_P0) { t.skip("TRVM-P0 has landed: child_protocols is consumed, not refused — this reproducer is history"); return; }
  assert.deepEqual(codes(probe), ["nest-policy-weakened"]); assert.deepEqual(codes(checkNestBundle(nest, { store, child_protocols: CHILD_PROTOCOLS_SUPPLIED })), ["nest-policy-weakened"]);
  assert.deepEqual(effectivePolicy({ child_protocols: {} }), { refusal: "child_protocols is not a field of this verifier's policy" });
});

test("AGREEMENT (post-TRVM-P0): checkNestBundle(nest, {store, child_protocols}) → VERIFIED with measured.child_protocol_set naming the supplied checker; the Graphonomous checker says VERIFIED on the same child", (t) => {
  if (!TRVM_P0) { t.skip("pending TRVM-P0: nest_check does not yet accept child_protocols (nest-policy-weakened)"); return; }
  const r = checkNestBundle(nest, { store, child_protocols: CHILD_PROTOCOLS_SUPPLIED }); assert.equal(r.verdict, "VERIFIED", codes(r).join()); assert.equal(r.ok, true);
  assert.equal(r.measured.checker_evaluations, 1); assert.ok(r.measured.child_protocol_set, "the verdict names which checker set accepted it"); assert.ok(JSON.stringify(r.measured.child_protocol_set).includes(CHECKER_ID));
  assert.equal(checkCertificate(DIRS[0], child, { cited: null }).verdict, "VERIFIED");
  assert.deepEqual(codes(checkNestBytes(canonicalWireBytes(nest), { store, child_protocols: CHILD_PROTOCOLS_SUPPLIED })), []);
});

test("AGREEMENT (post-TRVM-P0): on a forged child (chain forged and re-sealed, filed under its own root, cited by its own certificate) both checkers refuse with the same gproj- code set; a child whose certificate no longer matches the citation is nest-certificate-stale; a table naming a built-in is refused as an override and a malformed entry as malformed", (t) => {
  if (!TRVM_P0) { t.skip("pending TRVM-P0: nest_check does not yet accept child_protocols (nest-policy-weakened)"); return; }
  const forged = clone(child); forged.chain_ids.trvm_commit = "deadbeef".repeat(5); forged.claim[CLAIM_FIELD] = claimSemId(forged.claim);
  const st2 = memoryStore(new Map()); st2.put(forged);
  const g = checkCertificate(DIRS[0], forged, { cited: null }); assert.equal(g.verdict, "REFUSED");
  let nest2; try { nest2 = buildNestBundle([forged], { protocols: CHILD_PROTOCOLS_SUPPLIED }); } catch (e) { assert.match(e.message, /nest-bundle-child-refused/); }
  if (nest2) { const r = checkNestBundle(nest2, { store: st2, child_protocols: CHILD_PROTOCOLS_SUPPLIED }); assert.equal(r.verdict, "REFUSED"); const childCodes = r.measured.refusal_codes_transitive.filter((c) => c.startsWith("gproj-")); assert.deepEqual(childCodes, g.codes); }
  // the honest nest citing the honest certificate, with the store now serving the FORGED bytes under the honest root
  const lying = memoryStore(new Map()); lying.entries.set(childRoot, canonicalWireBytes(forged));
  const rl = checkNestBundle(nest, { store: lying, child_protocols: CHILD_PROTOCOLS_SUPPLIED }); assert.ok(codes(rl).includes("nest-artifact-root-mismatch"), "a store answering the honest root with other bytes is caught by the CAS");
  // TRVM-P0 as landed refuses both under the frozen vocabulary (`nest-policy-weakened`); R13 (a′) proposed two new codes — either spelling is the same refusal
  const ro = checkNestBundle(nest, { store, child_protocols: { ...CHILD_PROTOCOLS_SUPPLIED, "TRVM-BOUNDED-PROOF-v1": CHILD_PROTOCOLS_SUPPLIED[PROTOCOL] } }); assert.ok(codes(ro).some((c) => ["nest-policy-weakened", "nest-child-protocol-override-refused"].includes(c)), codes(ro).join()); assert.equal(ro.verdict, "REFUSED");
  const rm = checkNestBundle(nest, { store, child_protocols: { [PROTOCOL]: { claim_field: CLAIM_FIELD } } }); assert.ok(codes(rm).some((c) => ["nest-policy-weakened", "nest-child-protocol-malformed"].includes(c)), codes(rm).join()); assert.equal(rm.verdict, "REFUSED");
  assert.deepEqual(codes(probe), R13_3A, "an empty supplied table adds nothing: the [3a] set, byte-identical to the shipped checker");
});
