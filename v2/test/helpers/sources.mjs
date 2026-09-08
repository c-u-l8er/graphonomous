/* sources.mjs — is this checkout able to rebuild a projection from the pinned source registries?
 *
 * The handoff ZIP deliberately ships VERIFICATION COPIES of the sibling files it imports (D-033,
 * tools/make_gpt_bundle.mjs) and no `.git` history for the source registries. Tests that rebuild a projection from
 * `<commit>:<path>` therefore cannot run there, and a clean bundle must not look red for that reason (GPT v6 §7,
 * D-069 R2). This helper answers the question once, cheaply, so those tests can SKIP with a reason that names what is
 * missing instead of throwing at import time. */
import { readFileSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { execFileSync } from "node:child_process";

const V = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const cache = new Map();

/** `{ ok, reason }` for one snapshot file. `reason` is null when ok, else a sentence naming the first missing pin. */
export function probeSnapshot(snapshotFile) {
  if (cache.has(snapshotFile)) return cache.get(snapshotFile);
  let out;
  try {
    const snap = JSON.parse(readFileSync(resolve(V, "snapshots", snapshotFile), "utf8"));
    const missing = [];
    for (const s of snap.sources) {
      const dir = s.repo_dir || resolve(V, "../..", s.repo);
      try { execFileSync("git", ["-C", dir, "rev-parse", "--verify", `${s.commit}^{commit}`], { stdio: ["ignore", "pipe", "pipe"] }); }
      catch { missing.push(`${s.repo}@${String(s.commit).slice(0, 7)} (${dir})`); }
    }
    out = missing.length
      ? { ok: false, reason: `the pinned source registries are not reachable here: ${missing.join(", ")}. This file rebuilds a projection from git and belongs to \`npm run test:full-tree\`; \`npm run test:repro\` is the clean-bundle target.` }
      : { ok: true, reason: null };
  } catch (e) {
    out = { ok: false, reason: `snapshots/${snapshotFile} could not be read: ${String(e.message).split("\n")[0]}` };
  }
  cache.set(snapshotFile, out);
  return out;
}

/** `{ ok, reason }` for a set of snapshot files — ok only if every one of them can be rebuilt. */
export function probeSnapshots(...files) {
  for (const f of files) { const r = probeSnapshot(f); if (!r.ok) return r; }
  return { ok: true, reason: null };
}
