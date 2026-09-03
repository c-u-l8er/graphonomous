// TRVM-P0 — the minimal ALIEN-CHILD AGREEMENT VECTOR for Graphonomous G0-D.
//
// A leaf of a protocol TRVM does not implement is built, stored in a CAS the checker does not trust,
// wrapped in a TRVM-NESTED-COMPOSITION-v2 bundle by the TRVM producer, and judged twice:
//   · WITH a caller-supplied child-protocol table  → VERIFIED, and the verdict names the checker set
//   · WITHOUT one                                  → REFUSED with the R13 §7.1 [3a] set, verbatim
// Graphonomous reuses this by replacing `PROTOCOL`, `CLAIM_FIELD`, `child()` and `checkChild()` with
// GRAPHONOMOUS-PROJECTION-v0 and `checkProjectionCertificate`, keeping the two assertions.
//
// READ-ONLY over TRVM: imports by absolute path, memory store only, writes nothing. Exit 0 iff both hold.
"use strict";
import { createHash } from "node:crypto";
const TRVM = "/home/travis/ProjectAmp2/TRVM/governance";
const { canonicalBytes } = await import(`${TRVM}/derive_protocol.mjs`);
const { memoryStore, canonicalWireBytes } = await import(`${TRVM}/cas.mjs`);
const { publicResult } = await import(`${TRVM}/schema.mjs`);
const { verifiedClaimSemId, certificateOf } = await import(`${TRVM}/certificate.mjs`);
const { checkNestBundle, checkNestBytes, IMPLEMENTED_CHILD_PROTOCOLS, SHIPPED_POLICY, policyId } =
  await import(`${TRVM}/nest_check.mjs`);
const { buildNestBundle } = await import(`${TRVM}/nest_bundle.mjs`);

const H = (s) => createHash("sha256").update(s).digest("hex");

/* ── 1. the alien protocol: its bundle and its OWN checker ──────────────────────────────────────── */
const PROTOCOL = "TRVM-TEST-ALIEN-LEAF-v1";
const CLAIM_FIELD = "alien_claim_sem_id";
const CHECKER_ID = "trvm-test-alien-checker-v1";
const CHAIN = Object.freeze({ alien_toolchain: "alien-tc-0.1.0", alien_pin: "a".repeat(40) });
const claimId = (c) => "aclaim-" + H(PROTOCOL + "|" + canonicalBytes({ protocol: PROTOCOL, statement: c.statement, domain: c.domain }));
const aggId = (a) => { const { aggregate_id, ...rest } = a; return "aagg-" + H(PROTOCOL + "|" + canonicalBytes(rest)); };

function child() {
  const cases = [{ x: 0, y: 0 }, { x: 1, y: 2 }, { x: 2, y: 1 }];
  const claim = { statement: "x + y = y + x", domain: { x: [0, 1, 2], y: [0, 1, 2] } };
  claim[CLAIM_FIELD] = claimId(claim);                       // omit-then-set: canonicalBytes refuses undefined
  const aggregate = { count: cases.length, verdict: "VERIFIED" };
  aggregate.aggregate_id = aggId(aggregate);
  return { protocol: PROTOCOL, claim, chain_ids: { ...CHAIN }, aggregate, cases,
    annotations: { note: "NON-AUTHORITATIVE — a leaf protocol TRVM does not implement" } };
}

/** The protocol's own checker: re-derives every bound value, returns the public shape
 *  `{ok, verdict, refusals:[{code, detail}], measured}` with ok === (verdict === "VERIFIED"). */
function checkChild(b) {
  const refusals = [];
  const refuse = (code, detail) => refusals.push({ code, detail });
  if (b?.protocol !== PROTOCOL) refuse("alien-protocol-mismatch", String(b?.protocol));
  const claim = b?.claim ?? {};
  if (claimId(claim) !== claim[CLAIM_FIELD]) refuse("alien-claim-id-mismatch", `${CLAIM_FIELD} is not over this claim`);
  if (canonicalBytes(b?.chain_ids ?? null) !== canonicalBytes(CHAIN)) refuse("alien-chain-id-mismatch", "chain_ids is not this checker's live pin");
  const cases = Array.isArray(b?.cases) ? b.cases : [];
  const agg = b?.aggregate ?? {};
  if (agg.count !== cases.length) refuse("alien-count-inconsistent", `aggregate.count says ${agg.count}, this checker derives ${cases.length}`);
  for (const [i, c] of cases.entries()) if (c?.x + c?.y !== c?.y + c?.x) refuse("alien-case-failed", `case ${i}`);
  if (agg.verdict !== (refusals.length === 0 ? "VERIFIED" : "REFUSED")) refuse("alien-count-inconsistent", "aggregate.verdict is not the derived one");
  if (aggId(agg) !== agg.aggregate_id) refuse("alien-count-inconsistent", "aggregate_id is not over this aggregate");
  return publicResult({ refusals, measured: { derived_cases: cases.length } });
}

/* ── 2. the supplied table — the VERIFIER names the checker set, the artifact never does ────────── */
const child_protocols = Object.freeze({
  [PROTOCOL]: Object.freeze({ claim_field: CLAIM_FIELD, check: checkChild, composed: false, checker_id: CHECKER_ID }),
});

/* ── 3. store the child, build the nest bundle with the same table ─────────────────────────────── */
const store = memoryStore(new Map());
const leaf = child();
const root = store.put(leaf);
const nest = buildNestBundle([leaf], { child_protocols });
const vclaim = verifiedClaimSemId(certificateOf(leaf, CLAIM_FIELD));
console.log(`child ${PROTOCOL} stored at ${root}`);
console.log(`certificate ${vclaim}  cited by operand 0: ${nest.claim.operands[0].verified_claim_sem_id === vclaim}`);

/* ── 4. WITH the table: VERIFIED, on both boundaries, and the verdict names the set ─────────────── */
const withT = checkNestBundle(nest, { store, child_protocols });
const withB = checkNestBytes(canonicalWireBytes(nest), { store, child_protocols });
const cps = withT.measured.child_protocol_set;
console.log(`\nWITH child_protocols → ${withT.verdict} (bytes boundary ${withB.verdict}); ` +
  `checker_evaluations=${withT.measured.checker_evaluations}`);
console.log(`  child_protocol_set = ${JSON.stringify(cps)}`);
console.log(`  verifier_policy_id = ${withT.measured.verifier_policy_id}  (shipped ${policyId(SHIPPED_POLICY)})`);
const okWith = withT.ok === true && withB.ok === true && withT.measured.checker_evaluations === 1
  && cps?.supplied?.length === 1 && cps.supplied[0].protocol === PROTOCOL && cps.supplied[0].checker_id === CHECKER_ID
  && JSON.stringify(cps.builtin) === JSON.stringify(Object.keys(IMPLEMENTED_CHILD_PROTOCOLS))
  && withT.measured.verifier_policy_id !== policyId(SHIPPED_POLICY)
  && withT.measured.verifier_policy_id === withB.measured.verifier_policy_id;

/* ── 5. WITHOUT the table: the R13 §7.1 [3a] refusal set, verbatim ─────────────────────────────── */
const R13_SET = ["nest-chain-ids-mismatch", "nest-child-protocol-unsupported", "nest-child-refused",
  "nest-count-inconsistent", "nest-structure-mismatch"];
const without = checkNestBundle(nest, { store });
const codes = [...new Set(without.refusals.map((x) => x.code))].sort();
const unsupported = without.refusals.find((x) => x.code === "nest-child-protocol-unsupported")?.detail;
console.log(`\nWITHOUT child_protocols → ${without.verdict}; codes = [${codes.join(", ")}]; ` +
  `checker_evaluations=${without.measured.checker_evaluations}; child_protocol_set=${JSON.stringify(without.measured.child_protocol_set)}`);
console.log(`  ${unsupported}`);
const okWithout = without.ok === false && JSON.stringify(codes) === JSON.stringify(R13_SET)
  && without.measured.checker_evaluations === 0 && without.measured.child_protocol_set === undefined
  && without.measured.verifier_policy_id === policyId(SHIPPED_POLICY)
  && unsupported === `operand 0: child protocol "${PROTOCOL}"; this checker implements [${Object.keys(IMPLEMENTED_CHILD_PROTOCOLS).join(", ")}]`;

/* ── 6. and a lying table cannot mint trust: cross-wire the citation, the parent still refuses ──── */
const liar = { [PROTOCOL]: { claim_field: CLAIM_FIELD, composed: false, checker_id: "liar",
  check: () => ({ ok: true, verdict: "VERIFIED", evidence_verdict: null, refusals: [], measured: {} }) } };
const { nestedClaimSemId } = await import(`${TRVM}/nest_bundle.mjs`);
const forged = JSON.parse(JSON.stringify(nest));
forged.claim.operands[0].claim_sem_id = "aclaim-" + H("another claim");
forged.claim.nested_claim_sem_id = nestedClaimSemId(forged.claim.connective, forged.claim.scope, forged.claim.operands);
const lied = checkNestBundle(forged, { store, child_protocols: liar });
const liedCodes = [...new Set(lied.refusals.map((x) => x.code))].sort();
console.log(`\nLYING checker over a cross-wired citation → ${lied.verdict}; codes = [${liedCodes.join(", ")}]`);
const okLiar = lied.ok === false && liedCodes.includes("nest-citation-cross-wired");

const ok = okWith && okWithout && okLiar;
console.log(`\nAGREEMENT-VECTOR: ${ok ? "PASS" : "FAIL"} — with table ${okWith}, without table ${okWithout}, liar refused ${okLiar}`);
process.exit(ok ? 0 : 1);
