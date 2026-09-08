#!/usr/bin/env node
/* make_trvm_snapshot.mjs — write snapshots/tri.json: the multi-v1 six sources, plus TRVM GOVERNANCE as a seventh
 * source at its own pin, and a fourth adapter. Every file adapters/trvm.mjs reads is pinned by path + blob + sha256 +
 * bytes, so `openSources` refuses the projection if any of them moved (R15 §8.4: the pinned-commit read, never the
 * worktree).
 *   node tools/make_trvm_snapshot.mjs [--trvm <commit>] [--out snapshots/tri.json]                                   */
import { readFileSync, writeFileSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { resolve, dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { TRVM_FILES, TRVM_DIRS, NS } from "../adapters/trvm.mjs";
import { sortSet } from "../lib/canon.mjs";

const V = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const TRVM = resolve(V, "../../TRVM");
const argv = process.argv.slice(2);
const opt = (n, d) => { const i = argv.indexOf("--" + n); return i >= 0 ? argv[i + 1] : d; };
const git = (args) => execFileSync("git", ["-C", TRVM, ...args], { encoding: "utf8", maxBuffer: 256 * 1024 * 1024 }).trim();
const gitBytes = (args) => execFileSync("git", ["-C", TRVM, ...args], { maxBuffer: 256 * 1024 * 1024 });

const commit = git(["rev-parse", "--verify", `${opt("trvm", "HEAD")}^{commit}`]);
const tree = git(["rev-parse", `${commit}^{tree}`]);
const all = new Set(git(["ls-tree", "-r", "--name-only", commit]).split("\n").filter(Boolean));

const paths = new Set();
for (const { path } of TRVM_FILES) { if (!all.has(path)) throw new Error(`${path} is not in TRVM@${commit.slice(0, 7)}`); paths.add(path); }
for (const { prefix } of TRVM_DIRS) for (const p of all) if (p.startsWith(prefix) && p.endsWith(".json")) paths.add(p);

/* the snapshot schema requires every SET to be sorted by CANONICAL BYTES, not by name (lib/canon.mjs sortSet) */
const files = sortSet([...paths].sort().map((path) => {
  const bytes = gitBytes(["show", `${commit}:${path}`]);
  return { path, blob: git(["rev-parse", `${commit}:${path}`]), sha256: createHash("sha256").update(bytes).digest("hex"), bytes: bytes.length };
}), "files");

const base = JSON.parse(readFileSync(join(V, "snapshots", "multi-v1.json"), "utf8"));
const snap = {
  ...base,
  id: `snapshot:g0:tri-${base.sources.find((s) => s.namespace === "r10").commit.slice(0, 7)}-${base.sources.find((s) => s.namespace === "factory").commit.slice(0, 7)}-${commit.slice(0, 7)}`,
  spec: base.spec,
  sources: sortSet([...base.sources, {
    namespace: NS, registry: `registry:${NS}:invariant-grid@${commit.slice(0, 12)}`, repo: "TRVM",
    commit, tree, files,
  }], "sources"),
  params: { ...base.params, adapters: [...base.params.adapters, "trvm"] },
  taken_at: new Date().toISOString().replace(/\.\d{3}Z$/, "Z"),
};
const out = resolve(V, opt("out", "snapshots/tri.json"));
writeFileSync(out, JSON.stringify(snap, null, 1) + "\n");
console.log(JSON.stringify({ out, id: snap.id, trvm_commit: commit, trvm_files: files.length, total_bytes: files.reduce((n, f) => n + f.bytes, 0), sources: snap.sources.map((s) => `${s.namespace}@${s.commit.slice(0, 7)}(${s.files.length})`), adapters: snap.params.adapters }, null, 1));
