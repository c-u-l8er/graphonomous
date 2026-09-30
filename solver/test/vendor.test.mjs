import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { SRC, DEST, FILES } from '../tools/sync_vendor.mjs';

// A vendored copy nobody checks is a lie with a timestamp. This is the check.
test('vendored box-and-box is byte-identical to source', () => {
  for (const f of FILES) {
    assert.equal(readFileSync(join(DEST, f), 'utf8'), readFileSync(join(SRC, f), 'utf8'),
      `${f} has drifted from ${SRC} — run: npm run sync:vendor`);
  }
});

test('vendor manifest hashes match the files on disk', async () => {
  const { sha256 } = await import('../lib/hash.mjs');
  const m = JSON.parse(readFileSync(join(DEST, 'VENDOR_MANIFEST.json'), 'utf8'));
  for (const f of FILES) assert.equal(sha256(readFileSync(join(DEST, f), 'utf8')), m.sha256[f], f);
});

test('the vendored kernel imports nothing outside itself', () => {
  for (const f of FILES) {
    for (const m of readFileSync(join(DEST, f), 'utf8').matchAll(/^import .* from ['"]([^'"]+)['"]/gm)) {
      assert.ok(m[1].startsWith('./'), `${f} imports ${m[1]} — the browser cannot resolve that`);
    }
  }
});
