// report.mjs — assemble a whole run into one serialisable object. Shared by the CLI
// and the browser app so both render the same numbers from the same code.
import { buildGraph } from './graph.mjs';
import { runConsistency, RULEPACK_ID, RULES, CLASSES, FAMILIES } from './rules_web.mjs';
import { solveAll, DEFAULT_FLOOR } from './solve.mjs';
import { lidOf } from './lid.mjs';

export const SOLVER_ID = 'graphonomous.solver.web.v0';

export function runReport(docs, site = {}, floor = DEFAULT_FLOOR) {
  const graph = buildGraph(docs, site);
  const findings = runConsistency(graph);
  const solved = solveAll(findings, floor);

  const byClass = Object.fromEntries(CLASSES.map((c) => [c, findings.filter((f) => f.class === c).length]));
  const byFamily = Object.fromEntries(FAMILIES.map((fam) =>
    [fam, findings.filter((f) => f.families.includes(fam)).length]));

  const vetoed = solved.reduce((n, s) => n + (s.verdict?.floorEnforced || 0), 0);
  const floorBits = solved.filter((s) => s.verdict?.floorBit).length;
  const measuredBeta = solved.reduce((n, s) => n + s.options.filter((o) => o.betaSource === 'measured').length, 0);
  const totalOptions = solved.reduce((n, s) => n + s.options.length, 0);
  const refused = solved.filter((s) => s.verdict && s.verdict.decision === null).length;

  return {
    solver: SOLVER_ID, rulepack: RULEPACK_ID, rules_declared: RULES.length, floor,
    site: { origin: graph.origin, ...graph.stats },
    summary: {
      findings: findings.length, by_class: byClass, by_family: byFamily,
      options: totalOptions, vetoed, floor_bits: floorBits, refused_entirely: refused,
      beta_measured: measuredBeta, beta_declared: totalOptions - measuredBeta,
      utility_measured: 0, utility_declared: totalOptions
    },
    // one id over the whole run: same site + same code ⇒ same id
    run_id: lidOf('crun', { solver: SOLVER_ID, rulepack: RULEPACK_ID, floor,
                            findings: findings.map((f) => f.lid).sort() }),
    graph: {
      pages: graph.pages.map((p) => ({ url: p.url, title: p.title, h1: p.h1, canonical: p.canonical,
        description: p.description, links: p.links.length, jsonld: p.jsonld.length,
        inbound: (graph.inbound.get(p.url) || []).length, bodyChars: p.bodyChars })),
      claims: graph.claims, robots: graph.robots, sitemapUrls: graph.sitemapUrls
    },
    solved
  };
}

export default { runReport, SOLVER_ID };
