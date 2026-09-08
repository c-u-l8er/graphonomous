/* PROBE C1/1 — WHICH RECORD KINDS DOES EACH ADAPTER ACTUALLY EMIT?
 * The projection-v1 contract must state, per adapter, which record kinds it can cause a projection to contain — and
 * that must be MEASURED, not asserted, because `lib/project.mjs` treats every adapter uniformly and nothing in a
 * record names its emitter. So: run each adapter ALONE over the multi-v1 source set and count what came out.
 * READ-ONLY: writes only into a temp directory. */
import { mkdtempSync, rmSync, writeFileSync, readFileSync, existsSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { project } from "../../../../lib/project.mjs";

const V = resolve(dirname(fileURLToPath(import.meta.url)), "../../../..");
const KINDS = ["node", "relation", "assertion", "source_location", "fault", "adapter_run"];
const base = JSON.parse(readFileSync(join(V, "snapshots/multi-v1.json"), "utf8"));
const tmp = mkdtempSync(join(tmpdir(), "g0-emits-"));
const out = {};
for (const set of [["crosswalk"], ["factory"], ["factory_mosaic"], ["crosswalk", "factory"], ["crosswalk", "factory", "factory_mosaic"]]) {
  const snap = JSON.parse(JSON.stringify(base));
  snap.params.adapters = set;
  snap.id = "snapshot:g0:probe-" + set.map((s) => s.replace(/_/g, "-")).join("-and-");
  const sfile = join(tmp, "snap-" + set.join("_") + ".json");
  writeFileSync(sfile, JSON.stringify(snap, null, 1));
  const dir = join(tmp, "p-" + set.join("_"));
  let r;
  try { r = project(sfile, { out: dir, quiet: true }); } catch (e) { out[set.join("+")] = { error: String(e.message).slice(0, 160) }; continue; }
  const counts = {};
  for (const k of KINDS) {
    const p = join(dir, `records/${k}.jsonl`);
    counts[k] = existsSync(p) ? readFileSync(p, "utf8").split("\n").filter(Boolean).length : 0;
  }
  out[set.join("+")] = { root: r.root.slice(0, 20) + "…", counts, nonempty: KINDS.filter((k) => counts[k] > 0) };
}
console.log(JSON.stringify(out, null, 1));
rmSync(tmp, { recursive: true, force: true });
