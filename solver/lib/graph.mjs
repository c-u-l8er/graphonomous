// graph.mjs — page records + site files → the claim graph the rulepack reasons over.
// Pure; no I/O. Whoever calls it supplies the bytes (node reads files, the browser
// fetches through a proxy or takes an upload).
import { ingestPage, extractClaims } from './ingest.mjs';

const norm = (u) => {
  let s = (u || '').split('#')[0];
  if (s.length > 1 && s.endsWith('/')) s = s.slice(0, -1);
  if (s.endsWith('/index.html')) s = s.slice(0, -'/index.html'.length) || '/';
  return s || '/';
};

/** Words that carry no discriminating signal. Without this, two short strings agree
 *  merely by both being English. */
const STOP = new Set(('the a an and or but of to in on at for with from by is are was were be been '
  + 'this that these those it its as not no you your we our they their he she his her '
  + 'has have had will would can could may might must shall should do does did if then than '
  + 'so such very more most one two three four five six seven eight nine ten each every all any')
  .split(' '));

/**
 * Word-set similarity over content words.
 * @param {string} a @param {string} b
 * @param {string[]} ignore extra words to drop — pass the term that GROUPED the two
 *   strings, since a shared grouping key is evidence of nothing.
 */
export const overlap = (a, b, ignore = []) => {
  const drop = new Set([...STOP, ...ignore.map((x) => String(x).toLowerCase())]);
  const W = (s) => new Set((String(s || '').toLowerCase().match(/[a-z0-9]{3,}/g) || [])
    .filter((w) => !drop.has(w)));
  const A = W(a), B = W(b);
  if (!A.size || !B.size) return 0;
  let n = 0; for (const w of A) if (B.has(w)) n++;
  return n / Math.min(A.size, B.size);
};

/**
 * @param {{url:string, html:string}[]} docs
 * @param {{robots?:string, sitemap?:string, llmsTxt?:string, agentCard?:string, origin?:string}} site
 */
/** The directory a relative href on this page resolves against. Derived from the RAW
 *  url, because norm() strips "/index.html" and with it the fact that the page sits
 *  one level down — which silently reparents every sibling link. */
const baseOf = (raw) => {
  const u = (raw || '/').split('#')[0];
  return u.endsWith('/') ? u : u.slice(0, u.lastIndexOf('/') + 1);
};

export function buildGraph(docs, site = {}) {
  const pages = docs.map((d) => ({ ...ingestPage(d.html, norm(d.url)), base: baseOf(d.url) }));
  const claims = pages.flatMap((p) => extractClaims(p));

  // inbound link index.
  // A relative href resolves against the DIRECTORY of the page it appears on — not
  // against the root. Getting this wrong reported 45 of 63 pages as orphans on the
  // first run, which is a bug that reads exactly like a finding.
  const resolve = (href, base) => {
    if (href.startsWith('/')) return norm(href);
    const segs = (base + href.replace(/^\.\//, '')).split('/');
    const out = [];
    for (const s of segs) {
      if (s === '..') out.pop();
      else if (s !== '.') out.push(s);
    }
    return norm(out.join('/'));
  };
  const inbound = new Map(pages.map((p) => [p.url, []]));
  for (const p of pages) {
    const seen = new Set();                       // count SOURCE PAGES, not <a> tags
    for (const l of p.links) {
      const t = resolve(l.href, p.base);
      if (!inbound.has(t) || t === p.url || seen.has(t)) continue;
      seen.add(t);
      inbound.get(t).push({ from: p.url, text: l.text });
    }
  }

  // sitemap urls
  const sitemapUrls = [];
  if (site.sitemap) {
    for (const m of site.sitemap.matchAll(/<loc>\s*([^<]+?)\s*<\/loc>/gi)) {
      let u = m[1].trim();
      try { u = new URL(u).pathname; } catch { /* already a path */ }
      sitemapUrls.push(norm(u));
    }
  }

  // robots: which AI crawlers are blocked, and is any policy stated at all
  const aiAgents = ['GPTBot','ClaudeBot','anthropic-ai','PerplexityBot','OAI-SearchBot','Google-Extended','CCBot'];
  const robots = { present: !!site.robots, blocked: [], mentioned: [] };
  if (site.robots) {
    const groups = site.robots.split(/^\s*user-agent\s*:/im).slice(1);
    for (const g of groups) {
      const name = (g.match(/^\s*([^\r\n]+)/) || [])[1]?.trim() || '';
      const hit = aiAgents.find((a) => a.toLowerCase() === name.toLowerCase());
      if (!hit) continue;
      robots.mentioned.push(hit);
      if (/^\s*disallow\s*:\s*\/\s*$/im.test(g)) robots.blocked.push(hit);
    }
  }

  return {
    origin: site.origin || null,
    pages, claims,
    byUrl: new Map(pages.map((p) => [p.url, p])),
    inbound, sitemapUrls,
    robots,
    llmsTxt: site.llmsTxt || null,
    agentCard: site.agentCard || null,
    stats: {
      pages: pages.length, claims: claims.length,
      quantityClaims: claims.filter((c) => c.kind === 'quantity').length,
      withCanonical: pages.filter((p) => p.canonical).length,
      withJsonld: pages.filter((p) => p.jsonld.length).length
    }
  };
}

export default { buildGraph, overlap };
