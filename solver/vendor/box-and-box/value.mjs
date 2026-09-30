// value.mjs — Invariant Arithmetic, faithful runtime (v0.2)
// A Value is a PRODUCT OF MONOIDS across families. combine merges; chain composes
// along PULSE phases (partial — refuses a backward step); promote/reconcile/deliberate
// are endomorphisms; consume is the boolean gate. These satisfy laws L1–L15 (see test/laws.mjs).

import { round } from './numerics.mjs';

export const PHASES = ['retrieve', 'route', 'act', 'learn', 'consolidate'];
export const phaseIdx = (p) => PHASES.indexOf(p);

const uniq = (arr) => [...new Set(arr)];
const firstNonNull = (a, b) => (a !== null && a !== undefined) ? a : b;
const clone = (v) => ({ ...v, sigma: [...v.sigma], authority: [...v.authority], audit: [...v.audit] });

// identity element of the whole product monoid
export const V0 = () => ({
  n: 0,              // ℝ under +
  kappa: false,      // Bool under ∨ (OR) — cyclicity
  beta: 1,           // [0,1] under min — persistence / confidence
  sigma: [],         // Set<Tag> under ∪ — derived conflicts
  pi: null,          // Phase|null, first-non-null (NOT commutative)
  iota: null,        // IdemKey,  first-non-null
  psi: null,         // Cadence,  first-non-null
  authority: [],     // List<Cap> under concat (free monoid)
  denyDefault: true, // Bool under ∧ (AND)
  audit: []          // List<Event> under concat (free monoid)
});

// build a Value with sensible defaults
export const V = (p = {}) => ({
  ...V0(), ...p,
  sigma: [...(p.sigma || [])],
  authority: [...(p.authority || [])],
  audit: [...(p.audit || [])]
});

// ---- combine : Value × Value → Value ----------------------------------------
// componentwise monoid op. NOT globally commutative (temporal & governance are
// first-non-null / concat), but associative with identity V0 ⇒ a monoid.
export function combine(a, b) {
  return {
    n: a.n + b.n,
    kappa: a.kappa || b.kappa,
    beta: Math.min(a.beta, b.beta),
    sigma: uniq([...a.sigma, ...b.sigma]),
    pi: firstNonNull(a.pi, b.pi),
    iota: firstNonNull(a.iota, b.iota),
    psi: firstNonNull(a.psi, b.psi),
    authority: [...a.authority, ...b.authority],
    denyDefault: a.denyDefault && b.denyDefault,
    audit: [...a.audit, ...b.audit]               // pure concat (free monoid ⇒ associative)
  };
}

// ---- chain : Value × Value → Value  (PARTIAL) -------------------------------
// the phase-graded composition. Defined only when phase(a) ≤ phase(b) in PULSE
// order; a backward step is REFUSED (returns {error}). Composition moves the
// value to the exit (later) phase.
export function chain(a, b) {
  if (a.pi != null && b.pi != null && phaseIdx(a.pi) > phaseIdx(b.pi)) {
    return { error: `π-violation: cannot chain '${b.pi}' after '${a.pi}'` };
  }
  const r = combine(a, b);
  r.pi = firstNonNull(b.pi, a.pi); // exit phase
  return r;
}

// ---- promote : Value × Evidence → Value -------------------------------------
// β-monotone endomorphism: promote(v).β ≥ v.β, always.
export function promote(v, evidence = {}) {
  return { ...clone(v), beta: Math.max(v.beta, evidence.beta ?? 0) };
}

// ---- reconcile : Value × Set<Tag> → Value -----------------------------------
// σ-antitone, idempotent endomorphism: removes resolved conflict tags.
export function reconcile(v, tags = []) {
  const drop = new Set(tags);
  return { ...clone(v), sigma: v.sigma.filter((t) => !drop.has(t)) };
}

// ---- deliberate : Value → Value ---------------------------------------------
// κ-antitone, idempotent endomorphism: forces κ = false (breaks the cycle flag).
export function deliberate(v) {
  return { ...clone(v), kappa: false };
}

// ---- consume : Value × Requirements → {ok, failures, value} -----------------
// the correctness gate (a predicate, not an operation on Value).
export function consume(v, req = {}) {
  const failures = [];
  if (req.beta_min != null && v.beta < req.beta_min)
    failures.push({ family: 'β', why: `β=${round(v.beta)} < β_min=${req.beta_min}` });
  if (req.sigma_empty && v.sigma.length > 0)
    failures.push({ family: 'σ', why: `unresolved conflicts {${v.sigma.join(', ')}}` });
  if (req.acyclic && v.kappa)
    failures.push({ family: 'κ', why: 'cyclic — self-reference detected' });
  if (req.phase && v.pi !== req.phase)
    failures.push({ family: 'π', why: `phase ${v.pi} ≠ required ${req.phase}` });
  if (req.forward_from && v.pi != null && phaseIdx(v.pi) < phaseIdx(req.forward_from))
    failures.push({ family: 'π', why: `phase ${v.pi} precedes ${req.forward_from}` });
  if (req.deny_default === 'must_allow' && v.denyDefault === true && req.authorized !== true)
    failures.push({ family: 'governance', why: 'deny_default with empty authority_path' });
  return { ok: failures.length === 0, failures, value: v };
}

// compact human digest for traces
export function digest(v) {
  if (v.error) return `⟂ ${v.error}`;
  return [
    `n=${round(v.n)}`,
    `κ=${v.kappa}`,
    `β=${round(v.beta)}`,
    `σ={${v.sigma.join(',')}}`,
    `π=${v.pi ?? '·'}`,
    `auth=[${v.authority.join('·')}]`,
    `deny=${v.denyDefault}`
  ].join('  ');
}

export default { PHASES, phaseIdx, V0, V, combine, chain, promote, reconcile, deliberate, consume, digest };
