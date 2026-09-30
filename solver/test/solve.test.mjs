import { test } from 'node:test';
import assert from 'node:assert/strict';
import { buildGraph } from '../lib/graph.mjs';
import { runConsistency } from '../lib/rules_web.mjs';
import { solveFinding, DEFAULT_FLOOR } from '../lib/solve.mjs';
import { remediesFor } from '../lib/remedies.mjs';
import { RULES } from '../lib/rules_web.mjs';

const page = (url, body) => ({ url, html: `<html lang="en"><head><title>T — Site</title></head><body><h1>T</h1>${body}</body></html>` });
const contradiction = () => runConsistency(buildGraph([
  page('/a', '<p>The kernel enforces 109 laws today.</p>'),
  page('/b', '<p>The kernel enforces 109 laws today.</p>'),
  page('/c', '<p>The kernel enforces 103 laws today.</p>')
])).find((f) => f.rule === 'CLAIM_VALUE_DISAGREEMENT');

test('the floor vetoes an ungrounded remedy even at the highest utility', () => {
  const s = solveFinding(contradiction());
  const veto = s.verdict.vetoed.find((v) => v.id === 'add-a-canonical-number-page');
  assert.ok(veto, 'the generate-a-page remedy must be refused');
  assert.ok(veto.failures.some((f) => f.family === 'β'));
  assert.notEqual(s.verdict.decision, 'add-a-canonical-number-page');
});

test('a remedy that leaves its own finding standing is vetoed on σ', () => {
  const s = solveFinding(contradiction());
  const veto = s.verdict.vetoed.find((v) => v.id === 'leave-a-note-explaining');
  assert.ok(veto.failures.some((f) => f.family === 'σ'));
});

test('an unwarranted remedy is vetoed on governance', () => {
  const s = solveFinding(contradiction());
  const veto = s.verdict.vetoed.find((v) => v.id === 'bulk-rewrite-every-mention');
  assert.ok(veto.failures.some((f) => f.family === 'governance'));
});

test('the floor actually changes the outcome (floorBit is set)', () => {
  const s = solveFinding(contradiction());
  assert.ok(s.verdict.floorBit, 'the top-utility option should have been vetoed');
  assert.ok(s.verdict.floorBit.raw > s.verdict.ranking[0].score);
});

test('dropping the floor lets the ungrounded remedy win — which is the point', () => {
  const open = { sigma_empty: false, beta_min: 0, deny_default: 'allow', acyclic: false };
  const s = solveFinding(contradiction(), open);
  assert.equal(s.verdict.floorEnforced, 0);
  assert.equal(s.verdict.decision, 'bulk-rewrite-every-mention',
    'with no floor the highest declared utility wins, ungrounded');
});

test('measured beta is derived from the premises, not declared', () => {
  const f = contradiction();
  const o = remediesFor(f).find((r) => r.id === 'correct-the-minority');
  assert.equal(o.betaSource, 'measured');
  const total = f.premises[0].occurrences + f.premises[1].occurrences;
  assert.equal(o.beta, f.premises[0].occurrences / total);
});

test('every catalogue option declares its utility provenance', () => {
  for (const r of RULES) {
    const f = { rule: r.id, lid: 'cfind-x', subject: 'u:1',
      premises: [{ value: 9, occurrences: 3, pages: ['/a'], contexts: [] },
                 { value: 1, occurrences: 1, pages: ['/b'], contexts: [] }] };
    for (const o of remediesFor(f)) {
      assert.ok(typeof o.why === 'string' && o.why.length > 10, `${r.id}/${o.id} has no utility provenance`);
      assert.ok(['measured', 'declared'].includes(o.betaSource));
    }
  }
});

test('solving is deterministic', () => {
  const a = JSON.stringify(solveFinding(contradiction()).verdict);
  const b = JSON.stringify(solveFinding(contradiction()).verdict);
  assert.equal(a, b);
});

test('the default floor is the documented one', () => {
  assert.deepEqual(DEFAULT_FLOOR,
    { sigma_empty: true, beta_min: 0.6, deny_default: 'must_allow', acyclic: true });
});
