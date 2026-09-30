import { test } from 'node:test';
import assert from 'node:assert/strict';
import { buildGraph } from '../lib/graph.mjs';
import { runConsistency, RULES, RULEPACK_ID } from '../lib/rules_web.mjs';
import { COVERED_RULES } from '../lib/remedies.mjs';

const page = (url, body, head = '') => ({ url, html:
  `<html lang="en"><head><title>T — Site</title>${head}</head><body><h1>T</h1>${body}</body></html>` });

test('every declared rule has a remedy catalogue entry', () => {
  for (const r of RULES) assert.ok(COVERED_RULES.includes(r.id), `${r.id} has no remedies`);
});

test('every rule class is one of the four', () => {
  for (const r of RULES) assert.ok(['contradiction','drift','stale','unresolved'].includes(r.class));
});

test('CLAIM_VALUE_DISAGREEMENT fires when a dominant value meets a similar-context minority', () => {
  const g = buildGraph([
    page('/a', '<p>The kernel enforces 109 laws today.</p>'),
    page('/b', '<p>The kernel enforces 109 laws today.</p>'),
    page('/c', '<p>The kernel enforces 103 laws today.</p>')
  ]);
  const f = runConsistency(g).find((x) => x.rule === 'CLAIM_VALUE_DISAGREEMENT');
  assert.ok(f, 'expected a contradiction');
  assert.equal(f.class, 'contradiction');
  assert.equal(f.premises[0].value, 109);
  assert.equal(f.premises[1].value, 103);
});

test('THE GUARD: a minority value in unrelated prose is unresolved, not a contradiction', () => {
  const g = buildGraph([
    page('/a', '<p>The kernel enforces 109 laws today.</p>'),
    page('/b', '<p>The kernel enforces 109 laws today.</p>'),
    page('/c', '<p>Associativity and identity: the two laws a monoid must keep.</p>')
  ]);
  const fs = runConsistency(g);
  assert.equal(fs.filter((x) => x.rule === 'CLAIM_VALUE_DISAGREEMENT').length, 0,
    'dominance alone must not be enough to propose an edit');
  const amb = fs.find((x) => x.rule === 'AMBIGUOUS_QUANTITY' && x.rule_version === 2);
  assert.ok(amb, 'expected the scoped claim to be filed unresolved');
});

test('relative hrefs resolve against the containing directory, not the root', () => {
  const g = buildGraph([
    { url: '/patterns/index.html', html: '<html><head><title>P</title></head><body><a href="refusing-join.html">x</a></body></html>' },
    { url: '/patterns/refusing-join.html', html: '<html><head><title>R</title></head><body>hi</body></html>' }
  ]);
  assert.equal(g.inbound.get('/patterns/refusing-join.html').length, 1,
    'a sibling link must not resolve to /refusing-join.html');
  // /patterns is genuinely orphaned in this two-page fixture; the sibling is not.
  const orphans = runConsistency(g).filter((f) => f.rule === 'ORPHANED_PAGE').map((f) => f.subject);
  assert.ok(!orphans.includes('/patterns/refusing-join.html'));
});

test('inbound counts source PAGES, not anchor tags', () => {
  const g = buildGraph([
    { url: '/', html: '<html><head><title>H</title></head><body><a href="/x.html">a</a><a href="/x.html">b</a><a href="/x.html">c</a></body></html>' },
    { url: '/x.html', html: '<html><head><title>X</title></head><body>hi</body></html>' }
  ]);
  assert.equal(g.inbound.get('/x.html').length, 1);
});

test('AGENT_ACCESS_UNDECLARED fires on a site with no agent surface at all', () => {
  const g = buildGraph([page('/', '<p>hello</p>')]);
  assert.ok(runConsistency(g).some((f) => f.rule === 'AGENT_ACCESS_UNDECLARED'));
});

test('a declared llms.txt closes the agent finding', () => {
  const g = buildGraph([page('/', '<p>hello</p>')], { llmsTxt: '# Site\nWhat this is.' });
  assert.ok(!runConsistency(g).some((f) => f.rule === 'AGENT_ACCESS_UNDECLARED' && f.subject === 'site'));
});

test('finding ids are content-bound and stable across runs', () => {
  const docs = [page('/a', '<p>109 laws</p>'), page('/b', '<p>109 laws</p>'), page('/c', '<p>103 laws</p>')];
  const a = runConsistency(buildGraph(docs)).map((f) => f.lid);
  const b = runConsistency(buildGraph(docs)).map((f) => f.lid);
  assert.deepEqual(a, b);
  assert.ok(a.every((l) => l.startsWith('cfind-')));
});

test('the rulepack id is stamped on every finding', () => {
  const g = buildGraph([page('/', '<p>hello</p>')]);
  for (const f of runConsistency(g)) assert.equal(f.rulepack, RULEPACK_ID);
});
