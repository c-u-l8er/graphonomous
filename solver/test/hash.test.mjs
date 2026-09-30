import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { sha256, sha256Bytes } from '../lib/hash.mjs';

const ref = (s) => createHash('sha256').update(s, 'utf8').digest('hex');

test('sync sha256 matches node:crypto on edge-case lengths', () => {
  // 55/56/63/64/65 straddle the padding and block boundaries
  for (const n of [0, 1, 55, 56, 63, 64, 65, 119, 120, 127, 128, 1000]) {
    const s = 'x'.repeat(n);
    assert.equal(sha256(s), ref(s), `length ${n}`);
  }
});

test('sync sha256 matches node:crypto on multi-byte utf-8', () => {
  for (const s of ['üñíçødé', '漢字かな', '✓ — …', '👋🏽 family: 👨‍👩‍👧']) assert.equal(sha256(s), ref(s));
});

test('sync sha256 matches node:crypto on random binary', () => {
  for (let i = 0; i < 300; i++) {
    const n = Math.floor(Math.random() * 400);
    const b = new Uint8Array(n);
    for (let j = 0; j < n; j++) b[j] = Math.floor(Math.random() * 256);
    assert.equal(sha256Bytes(b), createHash('sha256').update(Buffer.from(b)).digest('hex'));
  }
});

test('known vector', () => {
  assert.equal(sha256('abc'), 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
});
