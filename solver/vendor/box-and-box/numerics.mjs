// numerics.mjs — the kernel's NORMATIVE numeric domain (the single source for rounding +
// tolerance). Pure, zero-dependency. Centralizes the four previously-duplicated `round`
// helpers (value.mjs, bridge.mjs, govern.mjs at 3dp; evolution.mjs at 6dp) so two conformant
// runtimes round identically. See README "Numerics" for the full contract; in brief:
//
//   EXACT class    — integer / scaled-integer fields compare with === (no rounding):
//                    norm counts, ledger token balances, phase indices, the tropical
//                    (min-plus / max-plus) semiring used for hard floors. A floor decision
//                    must never hinge on a rounding tie.
//   TOLERANCE class — real-valued fields (β confidence, axiological scores, the probability /
//                    log-sum-exp semirings, Δ deltas) are display-rounded with `round()` and
//                    COMPARED with `approxEq` at EPS. logsumexp is tolerance-class by nature.
//
// CANONICAL ROUNDING RULE (normative, so two runtimes agree bit-for-bit on the rounded value):
//   round(x, dp) = Math.round(x * 10^dp) / 10^dp
// evaluated in IEEE-754 binary64, where Math.round is "round half toward +∞" (JS semantics).
// A conformant runtime in another language MUST reproduce THIS rule — in particular the
// half-toward-+∞ tie-break (NOT C's half-away-from-zero) and binary64 intermediate precision.
// ±Infinity and NaN pass through unchanged: a floored/annihilated branch carries ±∞ and rounding
// must not turn it finite.

// canonical display tolerance for the TOLERANCE class.
export const EPS = 1e-9;

// DP: canonical decimal places. 3 for the kernel's public carriers (β, scores); 6 for the
// finer-grained evolution non-regression delta where small improvements must not vanish.
export const DP = 3;
export const DP_DELTA = 6;

// round(x, dp=DP) — the ONE rounding util (see CANONICAL ROUNDING RULE above).
export function round(x, dp = DP) {
  if (!Number.isFinite(x)) return x;
  const f = 10 ** dp;
  return Math.round(x * f) / f;
}

// the 6-dp specialization evolution.mjs used for score-vector deltas.
export const roundDelta = (x) => round(x, DP_DELTA);

// tolerance-class equality (real fields). Exact-class fields should use === directly.
export const approxEq = (a, b, eps = EPS) =>
  a === b || (Number.isFinite(a) && Number.isFinite(b) && Math.abs(a - b) <= eps * (1 + Math.abs(a) + Math.abs(b)));

export default { EPS, DP, DP_DELTA, round, roundDelta, approxEq };
