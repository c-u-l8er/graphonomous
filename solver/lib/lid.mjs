// lid.mjs — content-bound logical ids. Same discipline as v2/lib/lid.mjs: an id IS
// a hash of the thing it names, so a finding's id is stable across runs and changes
// the instant its premises change. Uses the solver's sync hash, never node:crypto.
import { sha256 } from './hash.mjs';

/** deterministic JSON: object keys sorted at every depth */
export function canonicalJson(v) {
  if (v === null || typeof v !== 'object') return JSON.stringify(v ?? null);
  if (Array.isArray(v)) return '[' + v.map(canonicalJson).join(',') + ']';
  const keys = Object.keys(v).filter((k) => v[k] !== undefined).sort();
  return '{' + keys.map((k) => JSON.stringify(k) + ':' + canonicalJson(v[k])).join(',') + '}';
}

export const lidOf = (prefix, payload) => prefix + '-' + sha256(canonicalJson(payload));
export const findingLid = (f) => lidOf('cfind', {
  rule: f.rule, rule_version: f.rule_version, rulepack: f.rulepack,
  subject: f.subject, premises: f.premises
});
export const optionLid = (findingLid, id) => lidOf('copt', { finding: findingLid, option: id });

export default { canonicalJson, lidOf, findingLid, optionLid };
