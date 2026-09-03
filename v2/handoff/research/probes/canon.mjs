// Sorted-key canonical JSON in JS: the WRL discipline (sorted keys, compact separators) applied to arbitrary JSON.
import { readFileSync } from 'node:fs'; import { createHash } from 'node:crypto';
const canon = (v) => {
  if (v === null || typeof v !== 'object') return JSON.stringify(v);
  if (Array.isArray(v)) return '[' + v.map(canon).join(',') + ']';
  return '{' + Object.keys(v).sort().map(k => JSON.stringify(k) + ':' + canon(v[k])).join(',') + '}';
};
for (const f of process.argv.slice(2)) {
  const s = canon(JSON.parse(readFileSync(f, 'utf8')));
  console.log(createHash('sha256').update(s, 'utf8').digest('hex'), Buffer.byteLength(s), f.split('/').pop());
}
