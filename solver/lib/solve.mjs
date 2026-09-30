// solve.mjs — finding → candidate options → floor-then-gradient → certificate.
// The kernel is imported from the vendored box-and-box; nothing in it is modified.
import { select } from '../vendor/box-and-box/bridge.mjs';
import { V } from '../vendor/box-and-box/value.mjs';
import { remediesFor } from './remedies.mjs';
import { optionLid } from './lid.mjs';

/** The floor. Weakening any of these is what the kernel exists to make visible. */
export const DEFAULT_FLOOR = Object.freeze({
  sigma_empty: true,          // a remedy may not leave its own finding standing
  beta_min: 0.6,              // material sufficiency: no remedy the site cannot ground
  deny_default: 'must_allow', // an edit needs a warrant
  acyclic: true               // no circular grounding
});

export function solveFinding(finding, floor = DEFAULT_FLOOR) {
  const remedies = remediesFor(finding);
  if (!remedies.length) {
    return { finding, options: [], verdict: null,
             note: `no remedy catalogue for rule ${finding.rule}` };
  }
  const options = remedies.map((r) => ({
    id: r.id,
    value: V({ sigma: r.sigma, beta: r.beta, kappa: r.kappa, denyDefault: !r.warranted, n: r.edits }),
    utility: r.utility,
    meta: { lid: optionLid(finding.lid, r.id), why: r.why, betaSource: r.betaSource,
            beta: r.beta, edits: r.edits, changes: r.changes }
  }));
  const verdict = select(options, floor);
  const byId = new Map(options.map((o) => [o.id, o.meta]));
  return {
    finding, floor,
    options: options.map((o) => ({ id: o.id, ...o.meta, utility: o.utility })),
    verdict,
    chosen: verdict.decision ? { id: verdict.decision, ...byId.get(verdict.decision) } : null
  };
}

export function solveAll(findings, floor = DEFAULT_FLOOR) {
  return findings.map((f) => solveFinding(f, floor));
}

export default { solveFinding, solveAll, DEFAULT_FLOOR };
