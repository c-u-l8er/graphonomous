// ingest.mjs — HTML → page records + claim records. No DOM, no dependencies:
// the same scanner runs in node and the browser.
//
// KNOWN CEILING (inherited, and stated rather than hidden): this extractor has no
// subject resolution. It therefore does NOT attempt open-domain claim extraction.
// It extracts two narrow, checkable kinds:
//
//   quantity   "210 laws"            → {unit:'laws', value:210}
//   definition "X is a Y"            → {subject:'X', object:'a Y'}
//
// Quantity claims are sound without subject resolution WITHIN ONE SITE, because the
// site is the subject. That narrowing is what makes the contradiction rule honest.

const strip = (s) => s.replace(/\s+/g, ' ').trim();
const decode = (s) => s
  .replace(/&nbsp;/g, ' ').replace(/&amp;/g, '&').replace(/&lt;/g, '<')
  .replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&#39;|&apos;/g, "'")
  .replace(/&mdash;/g, '—').replace(/&ndash;/g, '–').replace(/&hellip;/g, '…')
  .replace(/&#(\d+);/g, (_, d) => String.fromCodePoint(+d));

const attr = (tag, name) => {
  const m = tag.match(new RegExp(name + '\\s*=\\s*(?:"([^"]*)"|\'([^\']*)\'|([^\\s>]+))', 'i'));
  return m ? decode(m[1] ?? m[2] ?? m[3] ?? '') : null;
};

// Tags whose text content is not prose.
const NON_PROSE = /<(script|style|noscript|svg|template)\b[^>]*>[\s\S]*?<\/\1>/gi;

/** Units we will compare across pages. Deliberately small and explicit: an open
 *  unit list turns every incidental number into a false contradiction. */
export const TRACKED_UNITS = Object.freeze([
  'laws', 'rungs', 'tests', 'rules', 'machines', 'phases', 'repositories', 'repos',
  'projections', 'adapters', 'commits', 'schemas', 'products', 'tools', 'modules',
  'invariants', 'properties', 'dimensions', 'engines', 'sources', 'findings'
]);

const NUMWORD = { one:1, two:2, three:3, four:4, five:5, six:6, seven:7, eight:8, nine:9, ten:10,
  eleven:11, twelve:12 };

/**
 * @param {string} html
 * @param {string} url
 * @returns {object} page record
 */
export function ingestPage(html, url) {
  const head = html.slice(0, Math.max(0, html.search(/<\/head>/i)) || html.length);

  const title = (html.match(/<title[^>]*>([\s\S]*?)<\/title>/i) || [])[1];
  const canonicalTag = (head.match(/<link[^>]*rel\s*=\s*["']?canonical["']?[^>]*>/i) || [])[0];
  const canonical = canonicalTag ? attr(canonicalTag, 'href') : null;
  const descTag = (head.match(/<meta[^>]*name\s*=\s*["']?description["']?[^>]*>/i) || [])[0];
  const description = descTag ? attr(descTag, 'content') : null;
  const robotsTag = (head.match(/<meta[^>]*name\s*=\s*["']?robots["']?[^>]*>/i) || [])[0];
  const metaRobots = robotsTag ? attr(robotsTag, 'content') : null;
  const htmlTag = (html.match(/<html[^>]*>/i) || [])[0] || '';
  const lang = attr(htmlTag, 'lang');

  // --- structured data ------------------------------------------------------
  const jsonld = [];
  for (const m of html.matchAll(/<script[^>]*type\s*=\s*["']application\/ld\+json["'][^>]*>([\s\S]*?)<\/script>/gi)) {
    try { jsonld.push(JSON.parse(decode(m[1]))); } catch { jsonld.push({ __parse_error: true }); }
  }

  // --- headings -------------------------------------------------------------
  const headings = [];
  for (const m of html.matchAll(/<h([1-6])\b[^>]*>([\s\S]*?)<\/h\1>/gi)) {
    const text = strip(decode(m[2].replace(/<[^>]+>/g, ' ')));
    if (text) headings.push({ level: +m[1], text, at: m.index });
  }

  // --- internal links -------------------------------------------------------
  const links = [];
  for (const m of html.matchAll(/<a\b([^>]*)>([\s\S]*?)<\/a>/gi)) {
    const href = attr('<a ' + m[1] + '>', 'href');
    if (!href || /^(mailto:|tel:|javascript:|#)/i.test(href)) continue;
    if (/^https?:\/\//i.test(href)) continue;           // off-origin: out of scope here
    links.push({ href: href.split('#')[0], text: strip(decode(m[2].replace(/<[^>]+>/g, ' '))) });
  }

  // --- prose ----------------------------------------------------------------
  const prose = html.replace(NON_PROSE, ' ');
  const body = strip(decode(prose.replace(/<[^>]+>/g, ' ')));

  return {
    kind: 'page', url, title: title ? strip(decode(title)) : null,
    canonical, description, metaRobots, lang,
    h1: headings.filter((h) => h.level === 1).map((h) => h.text),
    headings, links, jsonld, bodyChars: body.length, body
  };
}

/** nearest preceding heading text for a character offset */
const anchorFor = (headings, at) => {
  let a = null;
  for (const h of headings) { if (h.at <= at) a = h.text; else break; }
  return a;
};

/**
 * @param {object} page a record from ingestPage
 * @returns {object[]} claim records
 */
export function extractClaims(page) {
  const claims = [];
  const html = page.body;
  const unitAlt = TRACKED_UNITS.join('|');

  // quantity: "210 laws", "two hundred" is out of scope; "twelve rules" is in.
  const re = new RegExp(
    '\\b(\\d[\\d,]*|' + Object.keys(NUMWORD).join('|') + ')\\s+' +
    '(?:enforced\\s+|property-tested\\s+|total\\s+|distinct\\s+|canonical\\s+)?' +
    '(' + unitAlt + ')\\b', 'gi');
  for (const m of html.matchAll(re)) {
    const raw = m[1].toLowerCase();
    const value = NUMWORD[raw] ?? Number(raw.replace(/,/g, ''));
    if (!Number.isFinite(value)) continue;
    const start = Math.max(0, m.index - 90);
    claims.push({
      kind: 'quantity', page: page.url, unit: m[2].toLowerCase(), value,
      context: strip(html.slice(start, Math.min(html.length, m.index + 90))),
      anchor: anchorFor(page.headings, m.index)
    });
  }

  // definition: "<Subject> is a/an/the <rest>." — first clause only, capitalised subject.
  for (const m of html.matchAll(/([A-Z][A-Za-z0-9.&\[\]-]{2,40}(?:\s+[A-Z][A-Za-z0-9.&\[\]-]{1,25}){0,3})\s+is\s+(an?|the)\s+([^.;:]{5,140})[.;:]/g)) {
    claims.push({
      kind: 'definition', page: page.url,
      subject: strip(m[1]), object: strip(m[2] + ' ' + m[3]),
      anchor: anchorFor(page.headings, m.index)
    });
  }
  return claims;
}

export default { ingestPage, extractClaims, TRACKED_UNITS };
