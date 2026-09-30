// sync_vendor.mjs — copy the box-and-box modules the solver imports, and record
// their hashes. The browser needs them served from this directory; node does not.
//
// This exists because a MANUAL copy of box-and-box has already gone stale once in
// this portfolio (the served playground kept reporting an old law count while every
// other surface had moved on). So the copy is scripted, and test/vendor.test.mjs
// FAILS when it drifts from source. A vendored file nobody checks is a lie with a
// timestamp.
import { readFileSync, writeFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { sha256 } from '../lib/hash.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
export const SRC = '/home/travis/ProjectAmp2/AmpersandBoxDesign/box-and-box';
export const DEST = join(HERE, '..', 'vendor', 'box-and-box');
export const FILES = ['numerics.mjs', 'score.mjs', 'value.mjs', 'bridge.mjs'];

export function manifest() {
  const out = {};
  for (const f of FILES) out[f] = sha256(readFileSync(join(SRC, f), 'utf8'));
  return out;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const m = manifest();
  for (const f of FILES) writeFileSync(join(DEST, f), readFileSync(join(SRC, f), 'utf8'));
  writeFileSync(join(DEST, 'VENDOR_MANIFEST.json'),
    JSON.stringify({ source: SRC, synced_files: FILES, sha256: m }, null, 2) + '\n');
  console.log(`synced ${FILES.length} files from ${SRC}`);
  for (const [f, h] of Object.entries(m)) console.log(`  ${f.padEnd(14)} ${h.slice(0, 16)}`);
}
