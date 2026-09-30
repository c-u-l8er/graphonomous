// bridge.mjs — the floor-then-gradient bridge (laws B1–B3).
// consume() gates each option on its invariant Value; a vetoed option gets score 0̲
// (which annihilates ⊗), and select() ranks only the feasible survivors. No heuristic
// utility, however large, can resurrect a vetoed option.
import { consume } from './value.mjs';
import { SEMIRINGS } from './score.mjs';
import { round } from './numerics.mjs';

const fin = (x) => (x === -Infinity ? 0 : round(x)); // display 0̲ as 0

// An OPTION couples a full invariant Value with a heuristic utility:
//   { id, value: <Value>, utility: <number> }
// `req` is the consume() Requirements applied to every option's value.

export function gatedScore(option, req, semiring = 'tropical') {
  const S = SEMIRINGS[semiring] || SEMIRINGS.tropical;
  const verdict = consume(option.value, req);
  return { score: verdict.ok ? (option.utility ?? S.one) : S.zero, verdict }; // B1
}

export function select(options, req = {}, semiring = 'tropical') {
  const S = SEMIRINGS[semiring] || SEMIRINGS.tropical;

  const evaluated = options.map((o) => {
    const g = gatedScore(o, req, semiring);
    return { id: o.id, raw: o.utility ?? S.one, score: g.score, ok: g.verdict.ok, failures: g.verdict.failures };
  });

  const feasible = evaluated.filter((e) => e.ok).sort((a, b) => b.score - a.score); // B2
  const vetoed = evaluated.filter((e) => !e.ok);
  const chosen = feasible[0] || null;
  const margin = feasible.length > 1 ? feasible[0].score - feasible[1].score : null;

  // honesty signal: would a vetoed option have won on raw utility if the floor were off?
  const topRaw = evaluated.slice().sort((a, b) => b.raw - a.raw)[0];
  const floorBit = chosen && topRaw && topRaw.id !== chosen.id && !topRaw.ok
    ? { id: topRaw.id, raw: round(topRaw.raw) } : null;

  let note;
  if (!chosen) note = 'No feasible option — the floor refused the entire set.';
  else if (floorBit) {
    const fb = vetoed.find((v) => v.id === floorBit.id);
    note = `“${floorBit.id}” had the highest raw utility (${floorBit.raw}) but was vetoed: ` +
           `${fb.failures.map((f) => `${f.family}: ${f.why}`).join('; ')}. ` +
           `0̲ annihilated it; the gradient selected “${chosen.id}”.`;
  } else if (vetoed.length) note = `${vetoed.length} option(s) vetoed and excluded from ranking.`;
  else note = 'All options feasible; selection by the gradient alone.';

  return {
    decision: chosen ? chosen.id : null,
    margin: margin == null ? null : round(margin),
    semiring,
    ranking: feasible.map((e) => ({ id: e.id, score: fin(e.score) })),
    vetoed: vetoed.map((e) => ({ id: e.id, gatedScore: 0, rawWouldBe: round(e.raw), failures: e.failures })),
    floorBit,
    floorEnforced: vetoed.length,
    note
  };
}

export default { gatedScore, select };
