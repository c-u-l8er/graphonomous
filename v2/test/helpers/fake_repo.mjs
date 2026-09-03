/* fake_repo.mjs — an in-memory stand-in for adapters/git.mjs openRepo(): the same pinned surface (name, commit, tree,
 * paths, has, blobOid, bytes, sha256, under) over a literal file table, so adapter behaviour on shapes the real
 * registries do not (yet) contain — an ambiguous bare id, one sentence under two rounds — can be tested without
 * inventing a git repository. Blob ids are real git blob ids of the bytes; the commit/tree ids are sha1 of the table. */
import { createHash } from "node:crypto";
import { gitBlobOid } from "../../lib/canon.mjs";

export function fakeRepo(name, files) {
  const table = Object.fromEntries(Object.entries(files).sort().map(([p, v]) => [p, Buffer.isBuffer(v) ? v : Buffer.from(typeof v === "string" ? v : JSON.stringify(v, null, 1), "utf8")]));
  const paths = new Set(Object.keys(table));
  const commit = createHash("sha1").update("commit:" + name + ":" + Object.entries(table).map(([p, b]) => p + ":" + gitBlobOid(b)).join("|")).digest("hex");
  const tree = createHash("sha1").update("tree:" + commit).digest("hex");
  return {
    name, dir: `<fake:${name}>`, commit, tree, head: commit, paths,
    has: (p) => paths.has(p),
    blobOid: (p) => (paths.has(p) ? gitBlobOid(table[p]) : null),
    bytes: (p) => { if (!paths.has(p)) throw new Error(`${name}: no ${p}`); return table[p]; },
    sha256: (p) => createHash("sha256").update(table[p]).digest("hex"),
    under: (prefix) => [...paths].filter((p) => p.startsWith(prefix)).sort(),
  };
}
export const sha256Of = (v) => createHash("sha256").update(Buffer.isBuffer(v) ? v : Buffer.from(typeof v === "string" ? v : JSON.stringify(v, null, 1), "utf8")).digest("hex");
