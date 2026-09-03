/* facts.mjs — the base-fact projection the rule program reads (rules/g0.rules.json `facts`): node/2, attr/3, rel/4,
 * rattr/3 from node and relation records, asrt/3 and aattr/3 from assertion records (D-032: occurrence attributes —
 * role, outcome, executed, … — live on the assertion, so the rules join asrt/aattr, never rattr, for them). Sorted by
 * fact key and deduplicated, so the evaluator's input order is a function of the records, not of file order. */
import { canonicalBytesG0 } from "./canon.mjs";

export const factKey = (rel, args) => canonicalBytesG0([rel, ...args]).toString("utf8");

export function factsFromRecords({ nodes = [], relations = [], assertions = [] }) {
  const out = new Map();
  const put = (rel, ...args) => { const k = factKey(rel, args); if (!out.has(k)) out.set(k, { rel, args }); };
  for (const n of nodes) { put("node", n.lid, n.kind); for (const [k, v] of Object.entries(n.attrs || {})) put("attr", n.lid, k, v); }
  for (const r of relations) { put("rel", r.lid, r.kind, r.source, r.target); for (const [k, v] of Object.entries(r.attrs || {})) put("rattr", r.lid, k, v); }
  for (const a of assertions) { put("asrt", a.lid, a.subject, a.location); for (const [k, v] of Object.entries(a.attrs || {})) put("aattr", a.lid, k, v); }
  return [...out.entries()].sort((a, b) => (a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : 0)).map(([, f]) => f);
}
