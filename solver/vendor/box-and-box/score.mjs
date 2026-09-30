// score.mjs — Heuristic Arithmetic, faithful runtime (v0.2)
// A Score lives in a SEMIRING (K, ⊕, ⊗, 0̲, 1̲): ⊕ aggregates alternatives, ⊗ chains
// evidence. vote/rollout/reinforce/dominate/anneal/select satisfy H1–H15. 0̲ annihilates
// ⊗ — the algebraic root of the veto used by the bridge (see bridge.mjs).

export const SEMIRINGS = {
  tropical:    { label: '(max, +)',        oplus: (a, b) => Math.max(a, b),
                 otimes: (a, b) => (a === -Infinity || b === -Infinity) ? -Infinity : a + b,
                 zero: -Infinity, one: 0, idempotent: true },
  probability: { label: '(+, ×)',          oplus: (a, b) => a + b, otimes: (a, b) => a * b,
                 zero: 0, one: 1, idempotent: false },
  log:         { label: '(logsumexp, +)',  oplus: logsumexp,
                 otimes: (a, b) => (a === -Infinity || b === -Infinity) ? -Infinity : a + b,
                 zero: -Infinity, one: 0, idempotent: false }
};
export function logsumexp(a, b) {
  if (a === -Infinity) return b;
  if (b === -Infinity) return a;
  const m = Math.max(a, b);
  return m + Math.log(Math.exp(a - m) + Math.exp(b - m));
}

// a Score carries a utility plus the soft analogues of the invariant families
export const Score = (p = {}) => ({
  u: p.u ?? 0,            // semiring carrier
  w: p.w ?? 1,            // [0,1] trust in this heuristic (×, cf. β's min)
  eps: p.eps ?? 0,        // [0,1] exploration (anneal → 0, cf. deliberate: κ→false)
  gamma: p.gamma ?? 1,    // (0,1] discount (soft order, cf. π's hard order)
  visits: p.visits ?? 0,  // ℕ under +
  sources: [...(p.sources || [])]
});

// ---- vote : aggregate alternatives (⊕ side) ---------------------------------
export function vote(a, b, semiring = 'tropical') {
  const S = SEMIRINGS[semiring] || SEMIRINGS.tropical;
  return Score({
    u: S.oplus(a.u, b.u),
    w: a.w * b.w,                 // independent trust dilutes (×)
    eps: Math.max(a.eps, b.eps),
    gamma: Math.min(a.gamma, b.gamma),
    visits: a.visits + b.visits,
    sources: [...a.sources, ...b.sources]
  });
}

// ---- rollout : chain evidence along a path, γ-discounted (⊗ side) -----------
// score(path) = ⊗ₜ (γ^t · uₜ).  0̲ anywhere annihilates the whole path.
export function rollout(scores, gamma = 0.9, semiring = 'tropical') {
  const S = SEMIRINGS[semiring] || SEMIRINGS.tropical;
  let acc = S.one;
  scores.forEach((s, t) => {
    const discounted = (s.u === S.zero) ? S.zero : Math.pow(gamma, t) * s.u;
    acc = S.otimes(acc, discounted);
  });
  return acc;
}

// ---- reinforce : η-contraction toward a target ------------------------------
export function reinforce(u, target, eta = 0.3) { return (1 - eta) * u + eta * target; }

// ---- dominate : Pareto-prune (idempotent, antitone) -------------------------
// opts: [{id, obj:[...]}] higher-is-better; returns the non-dominated front.
export function dominate(opts) {
  return opts.filter((a) =>
    !opts.some((b) => b.id !== a.id
      && b.obj.every((bj, i) => bj >= a.obj[i])
      && b.obj.some((bj, i) => bj > a.obj[i])));
}

// ---- anneal : ε → 0, T → 0 (idempotent) -------------------------------------
export function anneal(s) { return Score({ ...s, eps: 0 }); }

// ---- softmax (shift-invariant; T→0 ⇒ argmax) --------------------------------
export function softmax(us, T = 1) {
  const m = Math.max(...us);
  const ex = us.map((u) => Math.exp((u - m) / T));
  const z = ex.reduce((a, b) => a + b, 0);
  return ex.map((e) => e / z);
}

export default { SEMIRINGS, logsumexp, Score, vote, rollout, reinforce, dominate, anneal, softmax };
