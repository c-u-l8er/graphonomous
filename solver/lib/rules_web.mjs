// rules_web.mjs — graphonomous.consistency.rules.web.v0
//
// A rulepack over a site's claim graph, in the SAME four classes v2's registry
// rulepack uses, and for the same reason:
//
//   contradiction  the site asserts both X and ¬X
//   drift          two surfaces that should agree have diverged
//   stale          a surface has fallen behind the graph
//   unresolved     something load-bearing is absent or undecided
//
// The class is not decoration — it is the claim being made about certainty.
// CLAIM_VALUE_DISAGREEMENT fires `contradiction` only when one value DOMINATES
// (≥2 independent contexts) and another is a singleton, i.e. there is evidence for
// which side is wrong. When every value is a singleton the pack refuses to call it
// a contradiction and files `unresolved` (AMBIGUOUS_QUANTITY) instead, because a
// shared unit noun is not the same thing as a shared subject. That is the whole
// defence against the false positive this extractor would otherwise generate.

import { overlap } from './graph.mjs';
import { findingLid } from './lid.mjs';

export const RULEPACK_ID = 'graphonomous.consistency.rules.web.v0';
export const CLASSES = Object.freeze(['contradiction', 'drift', 'stale', 'unresolved']);
export const FAMILIES = Object.freeze(['seo', 'geo', 'aeo']);

const mk = (rule, version, cls, families, subject, detail, explain, premises) => {
  const f = { rule, rule_version: version, rulepack: RULEPACK_ID, class: cls,
              families, subject, authority: 'none', basis: 'derived', detail, explain, premises };
  f.lid = findingLid(f);
  return f;
};

// ---------------------------------------------------------------------------
// 1. CLAIM_VALUE_DISAGREEMENT — contradiction [geo, seo]
// 9. AMBIGUOUS_QUANTITY       — unresolved    [geo]
// ---------------------------------------------------------------------------
function quantityRules(g) {
  const out = [];
  const byUnit = new Map();
  for (const c of g.claims) {
    if (c.kind !== 'quantity') continue;
    if (!byUnit.has(c.unit)) byUnit.set(c.unit, []);
    byUnit.get(c.unit).push(c);
  }
  for (const [unit, cs] of byUnit) {
    const byValue = new Map();
    for (const c of cs) {
      if (!byValue.has(c.value)) byValue.set(c.value, []);
      byValue.get(c.value).push(c);
    }
    if (byValue.size < 2) continue;
    const ranked = [...byValue.entries()].sort((a, b) => b[1].length - a[1].length);
    const [topVal, topOcc] = ranked[0];
    const minority = ranked.slice(1);
    const premise = (v, occ) => ({ kind: 'quantity_claim', value: v, occurrences: occ.length,
      pages: [...new Set(occ.map((o) => o.page))].sort(),
      contexts: occ.slice(0, 3).map((o) => o.context) });

    // THE GUARD. Occurrence dominance alone is not evidence that the minority is
    // stale — it may be a smaller-scope claim that merely shares a unit noun. On the
    // first real run this rule proposed replacing "two laws a refusing join must
    // keep" with "109 laws". So a minority value is only called a CONTRADICTION when
    // its context also resembles the dominant one; otherwise it is filed unresolved.
    const CONTEXT_MIN = 0.25;
    // The unit noun is excluded: both contexts contain it by construction, so counting
    // it would let every pair of short sentences clear the threshold on nothing.
    const resembles = (mo) => Math.max(...mo.map((m) =>
      Math.max(...topOcc.map((t) => overlap(m.context, t.context, [unit])))));
    const contradictory = [], scoped = [];
    for (const [mv, mo] of minority) (resembles(mo) >= CONTEXT_MIN ? contradictory : scoped).push([mv, mo, resembles(mo)]);

    for (const [mv, mo, sim] of scoped) {
      out.push(mk('AMBIGUOUS_QUANTITY', 2, 'unresolved', ['geo'],
        `${unit}:${mv}`,
        `"${mv} ${unit}" appears alongside "${topVal} ${unit}" but in unrelated prose — probably a different quantity, not a stale one`,
        [`context similarity to the dominant claim is ${sim.toFixed(2)}, below the ${CONTEXT_MIN} needed to call it a contradiction`,
         `"${mv} ${unit}" context: ${mo[0].context.slice(0, 140)}`,
         'this pack will not propose an edit on this evidence; it reports the ambiguity instead'],
        [premise(topVal, topOcc), premise(mv, mo)]));
    }

    if (topOcc.length >= 2 && contradictory.length && minority.every(([, occ]) => occ.length < topOcc.length)) {
      for (const [mv, mo] of contradictory) {
        out.push(mk('CLAIM_VALUE_DISAGREEMENT', 1, 'contradiction', ['geo', 'seo'],
          `${unit}:${mv}`,
          `the site states "${topVal} ${unit}" in ${topOcc.length} places and "${mv} ${unit}" in ${mo.length}`,
          [`"${topVal} ${unit}" is asserted on ${[...new Set(topOcc.map((o) => o.page))].join(', ')}`,
           `"${mv} ${unit}" is asserted on ${[...new Set(mo.map((o) => o.page))].join(', ')}`,
           `the dominant value has ${topOcc.length} independent occurrences to the minority's ${mo.length}, so the minority is the one carrying the burden`,
           `an engine trained on this site learns the wrong number wherever the minority phrasing is the more quotable one`],
          [premise(topVal, topOcc), premise(mv, mo)]));
      }
    } else if (contradictory.length) {
      out.push(mk('AMBIGUOUS_QUANTITY', 1, 'unresolved', ['geo'],
        `${unit}`,
        `the site states ${ranked.length} different values for "${unit}" (${ranked.map(([v]) => v).join(', ')}) with no dominant one`,
        [`no value for "${unit}" occurs more than ${topOcc.length} time(s), so nothing here says which is current`,
         `a shared unit noun is not a shared subject — these may be different quantities, and this pack refuses to call it a contradiction on that evidence`],
        ranked.map(([v, occ]) => premise(v, occ))));
    }
  }
  return out;
}

// ---------------------------------------------------------------------------
// 2. CANONICAL_DISAGREEMENT — contradiction [seo]
// 12. MISSING_CANONICAL     — unresolved    [seo]
// ---------------------------------------------------------------------------
function canonicalRules(g) {
  const out = [];
  const byTitle = new Map();
  for (const p of g.pages) {
    const k = (p.title || '').toLowerCase();
    if (!k) continue;
    if (!byTitle.has(k)) byTitle.set(k, []);
    byTitle.get(k).push(p);
  }
  for (const [title, ps] of byTitle) {
    if (ps.length < 2) continue;
    const declared = [...new Set(ps.map((p) => p.canonical).filter(Boolean))];
    if (declared.length > 1 || (declared.length === 1 && ps.some((p) => !p.canonical))) {
      out.push(mk('CANONICAL_DISAGREEMENT', 1, 'contradiction', ['seo'],
        title,
        `${ps.length} pages share the title "${title}" but do not agree on a canonical`,
        [`pages: ${ps.map((p) => p.url).join(', ')}`,
         `declared canonicals: ${declared.length ? declared.join(', ') : '(none)'}`,
         `${ps.filter((p) => !p.canonical).length} of them declare none at all`],
        ps.map((p) => ({ kind: 'page_canonical', page: p.url, canonical: p.canonical }))));
    }
  }
  const missing = g.pages.filter((p) => !p.canonical);
  if (missing.length) {
    out.push(mk('MISSING_CANONICAL', 1, 'unresolved', ['seo'],
      'site',
      `${missing.length} of ${g.pages.length} pages declare no canonical URL`,
      ['a page with no canonical cedes the duplicate decision to the engine',
       'this is only a finding, not a fault: a site with no duplicates loses nothing by it'],
      missing.slice(0, 20).map((p) => ({ kind: 'page_canonical', page: p.url, canonical: null }))));
  }
  return out;
}

// ---------------------------------------------------------------------------
// 3. SCHEMA_PROSE_DISAGREEMENT — contradiction [aeo, geo]
// 10. NO_MACHINE_READABLE_CLAIM — unresolved   [aeo]
// ---------------------------------------------------------------------------
function schemaRules(g) {
  const out = [];
  for (const p of g.pages) {
    for (const block of p.jsonld) {
      if (!block || block.__parse_error) {
        out.push(mk('SCHEMA_PROSE_DISAGREEMENT', 1, 'contradiction', ['aeo'],
          p.url, `${p.url} carries a JSON-LD block that does not parse`,
          ['an unparseable ld+json block is read by nothing and silently believed by its author'],
          [{ kind: 'jsonld', page: p.url, parse_error: true }]));
        continue;
      }
      const name = block.name || block.headline;
      if (name && p.h1.length && overlap(name, p.h1[0]) < 0.34) {
        out.push(mk('SCHEMA_PROSE_DISAGREEMENT', 1, 'contradiction', ['aeo', 'geo'],
          p.url,
          `${p.url}: structured data names "${name}" while the h1 says "${p.h1[0]}"`,
          ['the machine-readable layer and the human layer name different things',
           'an agent reads the first; a person reads the second; they cannot both be right'],
          [{ kind: 'jsonld_name', page: p.url, schema: name, h1: p.h1[0] }]));
      }
    }
  }
  const claimful = new Set(g.claims.filter((c) => c.kind === 'quantity').map((c) => c.page));
  const bare = [...claimful].filter((u) => !(g.byUrl.get(u)?.jsonld.length)).sort();
  if (bare.length) {
    out.push(mk('NO_MACHINE_READABLE_CLAIM', 1, 'unresolved', ['aeo'],
      'site',
      `${bare.length} page(s) assert countable claims in prose with no structured data at all`,
      ['every quantity on these pages is available only by reading the sentence',
       'an agent that wants the number has to parse English and may parse it wrong',
       'this is the agent-optimization gap: the claim exists but nothing machine-readable carries it'],
      bare.slice(0, 20).map((u) => ({ kind: 'page_jsonld', page: u, blocks: 0 }))));
  }
  return out;
}

// ---------------------------------------------------------------------------
// 4. TITLE_H1_DRIFT     — drift [seo, geo]
// 5. DESCRIPTION_DRIFT  — drift [seo, geo]
// 6. ENTITY_NAME_DRIFT  — drift [geo, aeo]
// ---------------------------------------------------------------------------
function driftRules(g) {
  const out = [];
  for (const p of g.pages) {
    if (p.title && p.h1.length && overlap(p.title, p.h1[0]) < 0.2) {
      out.push(mk('TITLE_H1_DRIFT', 1, 'drift', ['seo', 'geo'],
        p.url,
        `${p.url}: <title> and <h1> share almost no vocabulary`,
        [`title: "${p.title}"`, `h1:    "${p.h1[0]}"`,
         'the search result and the page itself promise different things'],
        [{ kind: 'title_h1', page: p.url, title: p.title, h1: p.h1[0] }]));
    }
    if (p.description) {
      const opening = p.body.slice(0, 400);
      if (overlap(p.description, opening) < 0.2) {
        out.push(mk('DESCRIPTION_DRIFT', 1, 'drift', ['seo', 'geo'],
          p.url,
          `${p.url}: the meta description does not describe the page's opening`,
          [`description: "${p.description.slice(0, 120)}"`,
           'an engine rewriting the snippet will ignore the description; a citation will quote the body instead'],
          [{ kind: 'description', page: p.url, description: p.description }]));
      }
    }
  }
  // the site's own name, as spelled in <title> tails
  const tails = g.pages.map((p) => (p.title || '').split(/[—–|·]/).pop().trim()).filter(Boolean);
  const spellings = [...new Set(tails)];
  if (spellings.length > 2) {
    out.push(mk('ENTITY_NAME_DRIFT', 1, 'drift', ['geo', 'aeo'],
      'site',
      `the site names itself ${spellings.length} different ways in its own <title> tails`,
      [`spellings: ${spellings.slice(0, 8).map((s) => `"${s}"`).join(', ')}`,
       'entity resolution is the first thing a generative engine does and the last thing this site helps it with'],
      spellings.slice(0, 8).map((s) => ({ kind: 'entity_spelling', spelling: s }))));
  }
  return out;
}

// ---------------------------------------------------------------------------
// 7. SITEMAP_GRAPH_DIVERGENCE — stale [seo]
// 8. ORPHANED_PAGE            — stale [seo]
// ---------------------------------------------------------------------------
function reachabilityRules(g) {
  const out = [];
  if (g.sitemapUrls.length) {
    const known = new Set(g.pages.map((p) => p.url));
    const listed = new Set(g.sitemapUrls);
    const ghosts = [...listed].filter((u) => !known.has(u)).sort();
    const hidden = [...known].filter((u) => !listed.has(u)).sort();
    if (ghosts.length || hidden.length) {
      out.push(mk('SITEMAP_GRAPH_DIVERGENCE', 1, 'stale', ['seo'],
        'sitemap',
        `the sitemap and the crawled graph disagree on ${ghosts.length + hidden.length} URL(s)`,
        [ghosts.length ? `listed but not found: ${ghosts.slice(0, 10).join(', ')}` : 'nothing listed is missing',
         hidden.length ? `found but not listed: ${hidden.slice(0, 10).join(', ')}` : 'nothing found is unlisted',
         'the sitemap is an assertion about the site; here it has fallen behind the site'],
        [{ kind: 'sitemap_divergence', listed_not_found: ghosts.slice(0, 25), found_not_listed: hidden.slice(0, 25) }]));
    }
  }
  const home = g.pages.find((p) => p.url === '/' || p.url === '/index.html');
  for (const p of g.pages) {
    if (home && p.url === home.url) continue;
    const inb = g.inbound.get(p.url) || [];
    if (inb.length === 0) {
      out.push(mk('ORPHANED_PAGE', 1, 'stale', ['seo'],
        p.url,
        `${p.url} has no inbound internal link from any crawled page`,
        ['nothing on this site points at this page',
         'it can still be indexed from the sitemap, but it inherits no internal authority and reads as abandoned'],
        [{ kind: 'inbound', page: p.url, inbound: 0 }]));
    }
  }
  return out;
}

// ---------------------------------------------------------------------------
// 11. AGENT_ACCESS_UNDECLARED — unresolved [aeo]
// ---------------------------------------------------------------------------
function agentRules(g) {
  const out = [];
  const have = [];
  if (g.llmsTxt) have.push('llms.txt');
  if (g.agentCard) have.push('agent card');
  if (g.robots.mentioned.length) have.push(`robots policy for ${g.robots.mentioned.join(', ')}`);
  if (have.length === 0) {
    out.push(mk('AGENT_ACCESS_UNDECLARED', 1, 'unresolved', ['aeo'],
      'site',
      'the site declares no policy or entry point for agents: no llms.txt, no agent card, no robots rule naming an AI crawler',
      ['an agent arriving here has to guess what it may read and what this site is for',
       'silence is not permission and it is not refusal — it is an undecided question the site has left to the agent',
       'this is a finding about ABSENCE; it is the cheapest one on this list to close and the only one no competitor checks'],
      [{ kind: 'agent_surface', llms_txt: !!g.llmsTxt, agent_card: !!g.agentCard,
         robots_present: g.robots.present, ai_agents_mentioned: g.robots.mentioned }]));
  }
  if (g.robots.blocked.length) {
    out.push(mk('AGENT_ACCESS_UNDECLARED', 2, 'unresolved', ['aeo', 'geo'],
      'site:blocked',
      `robots.txt blocks ${g.robots.blocked.join(', ')} outright`,
      ['a site blocking these has its generative-visibility answer before any analysis runs',
       'this is reported, not judged: blocking may be exactly what the owner wants'],
      [{ kind: 'robots_block', blocked: g.robots.blocked }]));
  }
  return out;
}

export const RULES = Object.freeze([
  { id: 'CLAIM_VALUE_DISAGREEMENT', class: 'contradiction', families: ['geo','seo'] },
  { id: 'CANONICAL_DISAGREEMENT',   class: 'contradiction', families: ['seo'] },
  { id: 'SCHEMA_PROSE_DISAGREEMENT',class: 'contradiction', families: ['aeo','geo'] },
  { id: 'TITLE_H1_DRIFT',           class: 'drift',         families: ['seo','geo'] },
  { id: 'DESCRIPTION_DRIFT',        class: 'drift',         families: ['seo','geo'] },
  { id: 'ENTITY_NAME_DRIFT',        class: 'drift',         families: ['geo','aeo'] },
  { id: 'SITEMAP_GRAPH_DIVERGENCE', class: 'stale',         families: ['seo'] },
  { id: 'ORPHANED_PAGE',            class: 'stale',         families: ['seo'] },
  { id: 'AMBIGUOUS_QUANTITY',       class: 'unresolved',    families: ['geo'] },
  { id: 'NO_MACHINE_READABLE_CLAIM',class: 'unresolved',    families: ['aeo'] },
  { id: 'AGENT_ACCESS_UNDECLARED',  class: 'unresolved',    families: ['aeo'] },
  { id: 'MISSING_CANONICAL',        class: 'unresolved',    families: ['seo'] }
]);

/** @param {object} g a graph from buildGraph @returns {object[]} findings, sorted by lid */
export function runConsistency(g) {
  const findings = [
    ...quantityRules(g), ...canonicalRules(g), ...schemaRules(g),
    ...driftRules(g), ...reachabilityRules(g), ...agentRules(g)
  ];
  return findings.sort((a, b) => (a.class + a.rule + a.lid).localeCompare(b.class + b.rule + b.lid));
}

export default { RULEPACK_ID, CLASSES, FAMILIES, RULES, runConsistency };
