// PROBE A — the frozen core: identities, an honest derivation, and the Graphonomous rule attempt.
import {
  CORE_SPEC, CORE_SEM_ID, PROTOCOL_VERSION, JS_IMPLEMENTATION_ID,
  programSemId, validateProgram, ProgramRegistry, evaluate, resolveGrants,
  deriveLocally, validateForeignResult, footprintWithinGrant, canonicalBytes,
  DerivationAuthority, checkRequest,
} from "/home/travis/ProjectAmp2/TRVM/governance/derive_protocol.mjs";

console.log("PROTOCOL_VERSION =", PROTOCOL_VERSION);
console.log("JS_IMPLEMENTATION_ID =", JS_IMPLEMENTATION_ID);
console.log("CORE_SEM_ID =", CORE_SEM_ID);
console.log("CORE_SPEC.ops =", Object.keys(CORE_SPEC.ops).join(","));
console.log("CORE_SPEC.refusals =", CORE_SPEC.refusals.join(" | "));

// 1. an honest program and its id
const P = { op: "add", a: { op: "read", resource: "fb" }, b: { op: "input", name: "bias" } };
console.log("\n[1] programSemId(P) =", programSemId(P));
console.log("    same AST, different key order →", programSemId({ b: P.b, a: P.a, op: "add" }) === programSemId(P) ? "SAME id (canonical)" : "DIFFERENT");

// 2. a full authority round trip, to see the receipt shape
const world = { fb: 5, "warrant:w1": { value: 7, other: "x" } };
const reader = { read: (r) => ({ value: world[r], version: 1 }), scope: (q) => "scope-digest:" + q };
const auth = new DerivationAuthority(reader, [P]);
const a = auth.authorize({ intent_id: "i1", program_sem_id: programSemId(P), canonical_inputs: { bias: 2 },
  requested_resources: { exact: ["fb", "warrant:w1"], predicates: ["class=TESTED"] } });
console.log("\n[2] authorize ok =", a.ok, a.ok ? "" : a.reason);
if (a.ok) {
  console.log("    request keys =", Object.keys(a.request).join(","));
  console.log("    request.read_grants =", canonicalBytes(a.request.read_grants));
  console.log("    request.grant_id =", a.request.grant_id);
  const reg = new ProgramRegistry(); reg.bind(P);
  const d = deriveLocally(reg, a.request);
  console.log("    deriveLocally ok =", d.ok, d.ok ? "" : d.reason);
  if (d.ok) {
    console.log("    RESULT (the 'receipt'):");
    console.log("   ", JSON.stringify(d.result, null, 2).split("\n").join("\n    "));
    const acc = auth.accept(a.request, d.result);
    console.log("    accept →", JSON.stringify(acc));
    console.log("    footprintWithinGrant →", JSON.stringify(footprintWithinGrant(d.result.semantic_result.read_footprint, a.request.read_grants)));
    // replay: same request, same bytes?
    const d2 = deriveLocally(reg, a.request);
    console.log("    replay byte-identical =", canonicalBytes(d2.result) === canonicalBytes(d.result));
    // foreign validation of a lie
    const lie = { ...d.result, semantic_result: { ...d.result.semantic_result, value: 999 } };
    console.log("    validateForeignResult(lie) →", JSON.stringify(validateForeignResult(reg, a.request, lie)));
  }
}

// 3. cite + scope + len, the ops Graphonomous would lean on
{
  const Q = { op: "len", a: { op: "scope", query: "class=TESTED" } };
  const reg = new ProgramRegistry(); reg.bind(Q);
  const { read_grants, grant_id } = resolveGrants({ read: reader.read, scope: (q) => ["rec-1", "rec-2", "rec-3"] }, { predicates: ["class=TESTED"] });
  const d = deriveLocally(reg, { request_id: "r", program_sem_id: programSemId(Q), canonical_inputs: {}, read_grants, grant_id });
  console.log("\n[3] len(scope) over a 3-element scope digest →", d.ok ? d.result.semantic_result.value : d.reason,
    " footprint.predicates =", d.ok ? canonicalBytes(d.result.semantic_result.read_footprint.predicates) : "");
  const C = { op: "cite", name: "w1" };
  const reg2 = new ProgramRegistry(); reg2.bind(C);
  const g2 = resolveGrants(reader, { exact: ["warrant:w1"] });
  const d2 = deriveLocally(reg2, { request_id: "r", program_sem_id: programSemId(C), canonical_inputs: {}, read_grants: g2.read_grants, grant_id: g2.grant_id });
  console.log("    cite(w1) → value", JSON.stringify(d2.ok ? d2.result.semantic_result.value : d2.reason), " support =", JSON.stringify(d2.ok ? d2.result.semantic_result.support : ""));
}

// 4. THE GRAPHONOMOUS RULE, attempted in the core's JSON shape.
//    "for each record with class TESTED, require >=1 receipt with executed=true; else emit UNSUPPORTED(record)"
console.log("\n[4] Graphonomous rule in TRVM-DERIVE-CORE-v1 shape — where it fails");
const attempts = [
  ["forall over a set", { op: "forall", set: { op: "scope", query: "class=TESTED" }, var: "r", body: { op: "const", value: true } }],
  ["string equality", { op: "eq", a: { op: "read", resource: "rec-1.class" }, b: { op: "const", value: "TESTED" } }],
  ["boolean and", { op: "and", a: { op: "const", value: true }, b: { op: "const", value: true } }],
  ["if/else", { op: "if", c: { op: "const", value: true }, t: { op: "const", value: 1 }, e: { op: "const", value: 0 } }],
  ["field projection", { op: "get", a: { op: "read", resource: "rec-1" }, k: "class" }],
  ["count filtered", { op: "count_where", a: { op: "scope", query: "receipts-of:rec-1" }, field: "executed", equals: true }],
  ["prim op (declared, not built)", { op: "prim", primitive_sem_id: "prim-0000", args: [] }],
  ["read with extra field", { op: "read", resource: "rec-1", as: "r" }],
  ["gte via sub (numbers only)", { op: "sub", a: { op: "len", a: { op: "scope", query: "receipts-of:rec-1" } }, b: { op: "const", value: 1 } }],
];
for (const [label, ast] of attempts) {
  const v = validateProgram(ast);
  let id = null; try { id = programSemId(ast); } catch (e) { id = "REFUSED: " + e.message; }
  console.log(`    ${label.padEnd(30)} validateProgram → ${v.ok ? "ok" : v.reason}`);
  if (v.ok) console.log(`    ${"".padEnd(30)} programSemId → ${id}`);
}
// the one thing the core CAN compute: a numeric count minus a threshold, with NO way to compare it
{
  const N = { op: "sub", a: { op: "len", a: { op: "scope", query: "receipts-of:rec-1" } }, b: { op: "const", value: 1 } };
  const reg = new ProgramRegistry(); reg.bind(N);
  const g = resolveGrants({ read: reader.read, scope: (q) => [] }, { predicates: ["receipts-of:rec-1"] });
  const d = deriveLocally(reg, { request_id: "r", program_sem_id: programSemId(N), canonical_inputs: {}, read_grants: g.read_grants, grant_id: g.grant_id });
  console.log("    len(receipts)-1 with zero receipts →", d.ok ? d.result.semantic_result.value : d.reason, " (a number; the core has no op that turns -1 into a verdict)");
  // and executed=true cannot be filtered: the scope digest is whatever the World's scope() returned; len counts elements blindly
  const g3 = resolveGrants({ read: reader.read, scope: (q) => [{ id: "rc1", executed: false }] }, { predicates: ["receipts-of:rec-1"] });
  const d3 = deriveLocally(reg, { request_id: "r", program_sem_id: programSemId(N), canonical_inputs: {}, read_grants: g3.read_grants, grant_id: g3.grant_id });
  console.log("    len(receipts)-1 with ONE receipt executed=false →", d3.ok ? d3.result.semantic_result.value : d3.reason, " (counts the unexecuted receipt: the filter must live in the World's scope(), outside the derivation)");
}
// 5. type discipline: add over strings, len over non-array
{
  const S = { op: "add", a: { op: "const", value: "2" }, b: { op: "const", value: "3" } };
  const reg = new ProgramRegistry(); reg.bind(S);
  const g = resolveGrants(reader, {});
  const d = deriveLocally(reg, { request_id: "r", program_sem_id: programSemId(S), canonical_inputs: {}, read_grants: g.read_grants, grant_id: g.grant_id });
  console.log("\n[5] add(\"2\",\"3\") →", d.ok ? d.result.semantic_result.value : d.reason);
  const L = { op: "len", a: { op: "const", value: "abc" } };
  const reg2 = new ProgramRegistry(); reg2.bind(L);
  const d2 = deriveLocally(reg2, { request_id: "r", program_sem_id: programSemId(L), canonical_inputs: {}, read_grants: g.read_grants, grant_id: g.grant_id });
  console.log("    len(\"abc\") →", d2.ok ? d2.result.semantic_result.value : d2.reason);
  const F = { op: "const", value: 1.5 };
  console.log("    const 1.5 validate →", JSON.stringify(validateProgram(F)), " id:", programSemId(F).slice(0, 20) + "…");
  const Z = { op: "mul", a: { op: "const", value: -1 }, b: { op: "const", value: 0 } };
  const reg3 = new ProgramRegistry(); reg3.bind(Z);
  const d3 = deriveLocally(reg3, { request_id: "r", program_sem_id: programSemId(Z), canonical_inputs: {}, read_grants: g.read_grants, grant_id: g.grant_id });
  console.log("    mul(-1,0) → value", d3.ok ? Object.is(d3.result.semantic_result.value, -0) ? "-0 in JS" : d3.result.semantic_result.value : d3.reason, " canonical bytes:", d3.ok ? canonicalBytes(d3.result.semantic_result.value) : "");
}
