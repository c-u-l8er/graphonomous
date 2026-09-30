// remedies.mjs — the candidate-remedy catalogue: one entry per rule, each turning a
// finding into the OPTION SET the bridge ranks.
//
// Every option carries an Invariant Value whose families are the floor:
//
//   σ  conflicts the remedy LEAVES STANDING (its own finding lid, when it does not
//      actually resolve the thing)                                → req.sigma_empty
//   β  material sufficiency in [0,1]                              → req.beta_min
//   auth/deny  does a warrant exist for this edit                 → req.deny_default
//   κ  circular grounding                                         → req.acyclic
//
// β PROVENANCE. Where the finding's premises carry evidence, β is MEASURED from them
// (`beta_source: 'measured'`) — e.g. the share of occurrences supporting the value a
// remedy would standardise on. Where they do not, β is DECLARED, and every surface
// that prints it says so. Utility is DECLARED everywhere, without exception. This is
// deliberate: the veto half of this solver is defensible today, the gradient half is
// an opinion wearing a number, and the report is required to say which is which.

const O = (id, { sigma = [], beta = 1, betaSource = 'declared', warranted = true,
                 kappa = false, edits = 1 }, utility, why, changes = []) =>
  ({ id, sigma, beta, betaSource, warranted, kappa, edits, utility, why, changes });

const pagesOf = (p) => (p?.pages || []).join(', ');

const CATALOGUE = {
  // -------------------------------------------------------------------------
  CLAIM_VALUE_DISAGREEMENT(f) {
    const [dom, min] = f.premises;
    const total = dom.occurrences + min.occurrences;
    const beta = dom.occurrences / total;                     // MEASURED
    const unit = f.subject.split(':')[0];
    return [
      O('correct-the-minority', { beta, betaSource: 'measured', edits: min.occurrences },
        8, `β measured: ${dom.occurrences} of ${total} occurrences already state ${dom.value}`,
        min.pages.map((p) => ({ page: p, change: `replace "${min.value} ${unit}" with "${dom.value} ${unit}"` }))),
      O('state-both-with-scope', { beta: 0.7, edits: min.occurrences + dom.occurrences },
        5, 'declared: keeping both is correct only if they are genuinely different quantities',
        [{ page: pagesOf(min), change: `qualify each figure with the scope it counts` }]),
      O('add-a-canonical-number-page', { beta: 0.3, edits: 1 },
        11, 'declared HIGHEST: one new page, no edits to existing copy, adds indexable surface',
        [{ page: `/${unit}`, change: `new page asserting the authoritative ${unit} count` }]),
      O('leave-a-note-explaining', { sigma: [f.lid], beta: 0.9, edits: 1 },
        9, 'declared: cheapest edit that touches nothing load-bearing',
        [{ page: min.pages[0], change: 'add a footnote acknowledging the discrepancy' }]),
      O('bulk-rewrite-every-mention', { beta: 0.25, warranted: false, edits: total },
        12, 'declared: maximum consistency, maximum blast radius, no stated warrant', [])
    ];
  },
  // -------------------------------------------------------------------------
  AMBIGUOUS_QUANTITY(f) {
    return [
      O('disambiguate-by-scope', { beta: 0.65, edits: f.premises.length },
        7, 'declared: name what each figure counts; the site knows, the page does not say',
        f.premises.map((p) => ({ page: p.pages[0], change: `state what the ${p.value} counts` }))),
      O('pick-one-and-standardise', { sigma: [f.lid], beta: 0.4, edits: f.premises.length },
        9, 'declared HIGHEST: one number everywhere reads cleanest',
        []),
      O('escalate-to-a-human', { beta: 1.0, edits: 0 },
        3, 'declared: the pack cannot tell which is current, and says so',
        [{ page: '(none)', change: 'no edit — this finding is referred, not solved' }])
    ];
  },
  // -------------------------------------------------------------------------
  CANONICAL_DISAGREEMENT(f) {
    const declared = f.premises.map((p) => p.canonical).filter(Boolean);
    const beta = declared.length / Math.max(1, f.premises.length);  // MEASURED
    return [
      O('canonicalise-to-the-declared', { beta, betaSource: 'measured', edits: f.premises.length },
        8, `β measured: ${declared.length} of ${f.premises.length} pages already declare one`,
        f.premises.filter((p) => !p.canonical).map((p) => ({ page: p.page, change: `add <link rel="canonical" href="${declared[0] || '?'}">` }))),
      O('301-the-duplicates', { beta: 0.8, edits: f.premises.length - 1 },
        6, 'declared: strongest signal, but removes pages that may be wanted',
        []),
      O('noindex-the-duplicates', { sigma: [f.lid], beta: 0.85, edits: f.premises.length - 1 },
        9, 'declared HIGHEST: instant, reversible, no redirects to maintain', [])
    ];
  },
  MISSING_CANONICAL(f) {
    return [
      O('self-canonical-every-page', { beta: 1.0, betaSource: 'measured', edits: f.premises.length },
        7, 'β measured: a self-referential canonical is derivable from the URL itself, no new material needed',
        f.premises.map((p) => ({ page: p.page, change: `add self-referential canonical` }))),
      O('leave-it-to-the-engine', { sigma: [f.lid], beta: 1.0, edits: 0 },
        8, 'declared HIGHEST: zero work, and often no consequence', [])
    ];
  },
  // -------------------------------------------------------------------------
  SCHEMA_PROSE_DISAGREEMENT(f) {
    const p = f.premises[0];
    return [
      O('align-schema-to-the-page', { beta: 0.95, betaSource: 'measured', edits: 1 },
        9, 'β measured: the h1 supplies the correct value; nothing is invented',
        [{ page: p.page, change: p.h1 ? `set schema name to "${p.h1}"` : 'repair the ld+json block' }]),
      O('align-page-to-the-schema', { beta: 0.6, edits: 1 },
        4, 'declared: possible, but changes what a reader sees to match a machine field', []),
      O('drop-the-structured-data', { sigma: [f.lid], beta: 1.0, edits: 1 },
        10, 'declared HIGHEST: deleting the block removes the contradiction fastest',
        [{ page: p.page, change: 'remove the ld+json block' }])
    ];
  },
  NO_MACHINE_READABLE_CLAIM(f) {
    return [
      O('emit-schema-from-existing-claims', { beta: 1.0, betaSource: 'measured', edits: f.premises.length },
        9, 'β measured: every field is transcribed from a claim the page already makes',
        f.premises.map((p) => ({ page: p.page, change: 'add ld+json carrying the page\'s own quantity claims' }))),
      O('write-new-marketing-schema', { beta: 0.2, edits: f.premises.length },
        11, 'declared HIGHEST: richer schema, more eligible result types',
        []),
      O('do-nothing', { sigma: [f.lid], beta: 1.0, edits: 0 },
        2, 'declared: the prose is still readable by anything that renders it', [])
    ];
  },
  // -------------------------------------------------------------------------
  TITLE_H1_DRIFT(f) {
    const p = f.premises[0];
    return [
      O('title-from-h1', { beta: 0.95, betaSource: 'measured', edits: 1 },
        8, 'β measured: the h1 is on the page already; the title borrows from it',
        [{ page: p.page, change: `retitle from the h1: "${(p.h1 || '').slice(0, 70)}"` }]),
      O('h1-from-title', { beta: 0.9, betaSource: 'measured', edits: 1 },
        6, 'β measured: symmetric; changes what the reader sees first', []),
      O('keyword-stuff-the-title', { beta: 0.15, warranted: false, edits: 1 },
        10, 'declared HIGHEST: maximum query coverage', [])
    ];
  },
  DESCRIPTION_DRIFT(f) {
    const p = f.premises[0];
    return [
      O('description-from-opening', { beta: 0.95, betaSource: 'measured', edits: 1 },
        8, 'β measured: drawn verbatim from the page\'s own opening prose',
        [{ page: p.page, change: 'rewrite the meta description from the first paragraph' }]),
      O('delete-the-description', { beta: 1.0, edits: 1 },
        5, 'declared: a missing description is rewritten by the engine from the body — often better than a wrong one', []),
      O('generate-a-description', { beta: 0.35, edits: 1 },
        9, 'declared HIGHEST: written for the click, not from the page', [])
    ];
  },
  ENTITY_NAME_DRIFT(f) {
    return [
      O('standardise-on-one-spelling', { beta: 0.8, betaSource: 'measured', edits: f.premises.length },
        9, `β measured: all ${f.premises.length} spellings are the site's own; one is chosen, none invented`,
        f.premises.map((p) => ({ page: '(all titles)', change: `normalise "${p.spelling}"` }))),
      O('add-sameas-to-schema', { beta: 0.85, edits: 1 },
        7, 'declared: tells an agent the spellings are one entity without touching copy', []),
      O('rebrand', { sigma: [f.lid], beta: 0.1, warranted: false, edits: 99 },
        11, 'declared HIGHEST: a single new name solves it permanently', [])
    ];
  },
  // -------------------------------------------------------------------------
  SITEMAP_GRAPH_DIVERGENCE(f) {
    const p = f.premises[0];
    const n = (p.listed_not_found?.length || 0) + (p.found_not_listed?.length || 0);
    return [
      O('regenerate-the-sitemap', { beta: 1.0, betaSource: 'measured', edits: 1 },
        9, 'β measured: the crawled graph is the material; the sitemap is derived from it',
        [{ page: '/sitemap.xml', change: `regenerate from the ${n} divergent URL(s)` }]),
      O('link-the-unlisted-pages', { beta: 0.9, edits: p.found_not_listed?.length || 0 },
        6, 'declared: fixes reachability as well as listing', []),
      O('delete-the-sitemap', { sigma: [f.lid], beta: 1.0, edits: 1 },
        8, 'declared HIGHEST: no sitemap, no divergence', [])
    ];
  },
  ORPHANED_PAGE(f) {
    const p = f.premises[0];
    return [
      O('link-from-a-related-page', { beta: 0.9, betaSource: 'measured', edits: 1 },
        8, 'β measured: the link text can be taken from the orphan\'s own h1',
        [{ page: p.page, change: 'add an inbound internal link from a topically related page' }]),
      O('add-to-primary-nav', { beta: 0.9, edits: 1 },
        6, 'declared: strongest internal signal; costs nav space, which is finite', []),
      O('link-from-every-page', { beta: 0.5, warranted: false, edits: 99 },
        10, 'declared HIGHEST: maximum internal authority flow', []),
      O('delete-the-page', { beta: 0.7, warranted: false, edits: 1 },
        4, 'declared: an orphan nobody links may be one nobody wants', [])
    ];
  },
  // -------------------------------------------------------------------------
  AGENT_ACCESS_UNDECLARED(f) {
    const p = f.premises[0];
    if (p.kind === 'robots_block') {
      return [
        O('keep-the-block-and-say-so', { beta: 1.0, betaSource: 'measured', edits: 1 },
          7, 'β measured: the policy already exists in robots.txt; this only states it in prose',
          [{ page: '/llms.txt', change: 'declare the block as an intentional policy' }]),
        O('unblock-ai-crawlers', { beta: 0.5, warranted: false, edits: 1 },
          9, 'declared HIGHEST: generative visibility is impossible while blocked — but this reverses an owner decision with no warrant', [])
      ];
    }
    return [
      O('publish-llms-txt', { beta: 0.9, betaSource: 'measured', edits: 1 },
        8, 'β measured: contents are the site\'s own page titles and purposes, transcribed',
        [{ page: '/llms.txt', change: 'declare purpose, key pages, and agent policy' }]),
      O('publish-an-agent-card', { beta: 0.75, edits: 1 },
        7, 'declared: a signed card at /.well-known/ is the strongest agent-entry signal available today',
        [{ page: '/.well-known/agent-card.json', change: 'publish an A2A agent card' }]),
      O('state-a-robots-policy', { beta: 0.95, betaSource: 'measured', edits: 1 },
        6, 'β measured: a decision the owner already implicitly holds, written down', []),
      O('do-nothing-silence-is-fine', { sigma: [f.lid], beta: 1.0, edits: 0 },
        9, 'declared HIGHEST: zero work, and most sites do exactly this', [])
    ];
  }
};

/** @returns {object[]} candidate options for a finding, or [] when no catalogue entry exists */
export function remediesFor(finding) {
  const entry = CATALOGUE[finding.rule];
  return entry ? entry(finding) : [];
}

export const COVERED_RULES = Object.freeze(Object.keys(CATALOGUE));
export default { remediesFor, COVERED_RULES };
