#!/usr/bin/env node
// solve.mjs — run the solver over a directory of static HTML, or a crawl JSON.
//   node bin/solve.mjs <dir> [--json out.json] [--beta-min 0.6] [--no-floor]
import { readFileSync, writeFileSync, readdirSync, existsSync } from 'node:fs';
import { join, relative } from 'node:path';
import { runReport } from '../lib/report.mjs';
import { DEFAULT_FLOOR } from '../lib/solve.mjs';

const args = process.argv.slice(2);
const dir = args.find((a) => !a.startsWith('--'));
const flag = (n, d = null) => { const i = args.indexOf('--' + n); return i < 0 ? d : (args[i + 1] ?? true); };
if (!dir) { console.error('usage: solve.mjs <dir-of-html> [--json out.json] [--beta-min N] [--no-floor]'); process.exit(2); }

const walk = (d, base = d) => readdirSync(d, { withFileTypes: true }).flatMap((e) => {
  if (e.name.startsWith('.') || ['node_modules', 'old_scrap', 'dist', 'prototype'].includes(e.name)) return [];
  const p = join(d, e.name);
  return e.isDirectory() ? walk(p, base) : (e.name.endsWith('.html') ? [{ url: '/' + relative(base, p), html: readFileSync(p, 'utf8') }] : []);
});

const docs = walk(dir);
const read = (n) => existsSync(join(dir, n)) ? readFileSync(join(dir, n), 'utf8') : null;
const site = { origin: flag('origin', dir), robots: read('robots.txt'), sitemap: read('sitemap.xml'),
               llmsTxt: read('llms.txt'), agentCard: read('.well-known/agent-card.json') };

const floor = flag('no-floor') ? { sigma_empty: false, beta_min: 0, deny_default: 'allow', acyclic: false }
                               : { ...DEFAULT_FLOOR, beta_min: Number(flag('beta-min', DEFAULT_FLOOR.beta_min)) };

const r = runReport(docs, site, floor);

const bar = (n, w = 28) => '█'.repeat(Math.min(w, n)) + (n > w ? '…' : '');
console.log('\n' + '═'.repeat(80));
console.log(`  ${r.solver}   ·   ${r.rulepack}`);
console.log(`  ${r.site.origin}`);
console.log('═'.repeat(80));
console.log(`  run    ${r.run_id}`);
console.log(`  site   ${r.site.pages} pages · ${r.site.claims} claims (${r.site.quantityClaims} quantity) · ${r.site.withCanonical} canonical · ${r.site.withJsonld} with ld+json`);
console.log(`  floor  ${JSON.stringify(r.floor)}`);
console.log(`\n  findings ${r.summary.findings}   ` +
  Object.entries(r.summary.by_class).map(([k, v]) => `${k} ${v}`).join(' · '));
console.log(`  families ` + Object.entries(r.summary.by_family).map(([k, v]) => `${k.toUpperCase()} ${v}`).join(' · '));
console.log(`  options  ${r.summary.options}  ·  vetoed ${r.summary.vetoed}  ·  floor-bits ${r.summary.floor_bits}  ·  refused-entirely ${r.summary.refused_entirely}`);
console.log(`  β        measured ${r.summary.beta_measured} / declared ${r.summary.beta_declared}` +
            `      utility  measured ${r.summary.utility_measured} / declared ${r.summary.utility_declared}  ← the gradient is opinion`);

for (const s of r.solved) {
  const f = s.finding;
  console.log('\n' + '─'.repeat(80));
  console.log(`  [${f.class.toUpperCase()}] ${f.rule}  ·  ${f.families.map((x) => x.toUpperCase()).join('/')}`);
  console.log(`  ${f.detail}`);
  console.log(`  ${f.lid.slice(0, 26)}…`);
  for (const e of f.explain.slice(0, 2)) console.log(`      · ${e}`);
  if (!s.verdict) { console.log(`  ⚠ ${s.note}`); continue; }
  const v = s.verdict;
  console.log(`\n  → DECISION  ${v.decision ?? '(refused — no feasible remedy)'}${v.margin != null ? `   margin ${v.margin}` : ''}`);
  if (s.chosen) {
    console.log(`     β=${s.chosen.beta.toFixed(2)} (${s.chosen.betaSource})  edits=${s.chosen.edits}`);
    for (const c of (s.chosen.changes || []).slice(0, 3)) console.log(`     ${c.page}  →  ${c.change}`);
  }
  if (v.ranking.length > 1) console.log(`     runners-up: ${v.ranking.slice(1).map((x) => `${x.id}(${x.score})`).join(', ')}`);
  for (const ve of v.vetoed) {
    console.log(`     ✗ ${ve.id}  (raw ${ve.rawWouldBe})`);
    for (const fa of ve.failures) console.log(`         ${fa.family}: ${fa.why}`);
  }
  if (v.floorBit) console.log(`     ⚑ the floor overrode the gradient here`);
}

console.log('\n' + '═'.repeat(80));
console.log(`  ${r.summary.vetoed} of ${r.summary.options} remedies refused by the floor; ` +
            `on ${r.summary.floor_bits} finding(s) the highest-scoring remedy was one of them.`);
console.log('═'.repeat(80) + '\n');

const out = flag('json');
if (out) { writeFileSync(out, JSON.stringify(r, null, 2)); console.log(`wrote ${out}\n`); }
