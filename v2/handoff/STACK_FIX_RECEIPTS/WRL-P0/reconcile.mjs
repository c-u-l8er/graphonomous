import { readFileSync } from "node:fs";
import * as V2 from "/home/travis/ProjectAmp2/WRL/relation-v2.js";
const P = JSON.parse(readFileSync("/home/travis/ProjectAmp2/graphonomous/v2/handoff/WRL_SCHEMA_OR_PROFILE/graphonomous.semantic.v0.json", "utf8"));
const row = V2.V2_PROFILES["graphonomous.semantic.v0"];
const S = (x) => JSON.stringify(x);
const out = {
  rulepack: [row.rulepack_id, P.semantic_policies.rulepack_id, row.rulepack_id === P.semantic_policies.rulepack_id],
  policy_vocab_vs_canonical_default: [row.policies, P.canonical_defaults.policy, row.policies.length === 1 && row.policies[0] === P.canonical_defaults.policy],
  domain: [row.domain, P.relation_signatures.domain, row.domain === P.relation_signatures.domain],
  signature: [S(row.signature), S({orientation:P.relation_signatures.orientation,texture:P.relation_signatures.texture,arity:P.relation_signatures.arity,endpoint_roles:P.relation_signatures.endpoint_roles}), S(row.signature) === S({orientation:P.relation_signatures.orientation,texture:P.relation_signatures.texture,arity:P.relation_signatures.arity,endpoint_roles:P.relation_signatures.endpoint_roles})],
  roles: [Object.keys(row.roles).length, P.roles.kinds.length, S(Object.keys(row.roles)) === S(P.roles.kinds)],
  ports_every_role: [S([...new Set(Object.values(row.roles).map(S))]), S(P.roles.ports), Object.values(row.roles).every((p) => S(p) === S(P.roles.ports))],
  kinds: [Object.keys(row.endpoints).length, P.relation_signatures.kinds.length, S(Object.keys(row.endpoints)) === S(P.relation_signatures.kinds)],
};
const theirs = Object.fromEntries(Object.entries(P.endpoint_constraints).filter(([k]) => k !== "note"));
const norm = (o) => S(Object.keys(o).sort().map((k) => [k, o[k].map((p) => p.join(">")).sort()]));
out.endpoint_pairs = [Object.values(row.endpoints).reduce((n, v) => n + v.length, 0), Object.values(theirs).reduce((n, v) => n + v.length, 0), norm(row.endpoints) === norm(theirs)];
for (const [k, [a, b, same]] of Object.entries(out)) console.log(`${same ? "AGREE" : "DISAGREE"} ${k}: wrl=${a} graphonomous=${b}`);
console.log("verdict:", Object.values(out).every(([, , s]) => s) ? "ROW == GRAPHONOMOUS JSON (D-037 form)" : "DRIFT");
