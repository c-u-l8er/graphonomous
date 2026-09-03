#!/usr/bin/env node
/* make_gpt_bundle.mjs — build the GPT handoff ZIP for graphonomous/v2 with REPRO_DEPENDENCIES (D-033):
 *   node tools/make_gpt_bundle.mjs <name> <report.md>
 * Layout inside the zip (mirrors ProjectAmp2 so the sibling imports resolve and the non-git tests run from the zip):
 *   <name>/graphonomous/v2/**            this tree (projections included; pre-b1 receipts included)
 *   <name>/TRVM/governance/<file>        byte copies of every sibling file imported (transitively) by v2 code
 *   <name>/WRL/<file>
 *   <name>/REPRO_DEPENDENCIES/MANIFEST.json   repo, commit, blob OID, sha256, path, imported_by, for each copy
 *   <name>/<report.md>, <name>/SHA256SUMS
 * Uses only git + zip via child_process; never writes into a sibling repository. */
import { readFileSync, writeFileSync, mkdirSync, rmSync, cpSync, existsSync, readdirSync, statSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { resolve, join, dirname, relative } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url)); const V2 = resolve(HERE, ".."); const AMP = resolve(V2, "../..");
const [name, report] = process.argv.slice(2);
if (!name || !report) { console.error("usage: make_gpt_bundle.mjs <name> <report.md>"); process.exit(2); }
const OUT = resolve(process.env.HOME, "Downloads"); const STAGE = resolve(process.env.TMPDIR || "/tmp/claude-1000/-home-travis-ProjectAmp2/21673ead-a5fe-401c-80ba-a5175ab628ee/scratchpad", "bundle-" + name);
rmSync(STAGE, { recursive: true, force: true }); mkdirSync(join(STAGE, name), { recursive: true });
const sha256 = (b) => createHash("sha256").update(b).digest("hex");
const git = (dir, args) => execFileSync("git", ["-C", dir, ...args], { encoding: "utf8", maxBuffer: 64 * 1024 * 1024 }).trim();

// 1. the v2 tree (skip node_modules, nothing else — projections and pre-b1 receipts travel)
/* `ui/data` is a BUILD PRODUCT of tools/g05_build.mjs (36 MB, four worlds) and is gitignored; the receiver
 * regenerates it with one command and test/g05.test.mjs rebuilds it into a temp dir to check it anyway. */
const SKIP_DIRS = new Set(["node_modules", ".git"]);
const walk = (d, acc = []) => { for (const e of readdirSync(d)) { const p = join(d, e); if (SKIP_DIRS.has(e)) continue; if (relative(V2, p) === "ui/data") continue; if (statSync(p).isDirectory()) walk(p, acc); else acc.push(p); } return acc; };
const v2files = walk(V2);
for (const f of v2files) { const rel = relative(V2, f); mkdirSync(dirname(join(STAGE, name, "graphonomous/v2", rel)), { recursive: true }); cpSync(f, join(STAGE, name, "graphonomous/v2", rel)); }

// 2. transitive sibling imports from every .mjs/.js under v2 (import ... from "../../../X/…")
const IMPORT_RE = /from\s+["']((?:\.\.\/)+(?:TRVM|WRL|[A-Za-z0-9_.-]+)\/[^"']+)["']/g;
const CODE_DIRS = ["lib", "adapters", "bin", "test", "schemas", "tools"].map((d) => join(V2, d) + "/");
const seen = new Map(); const queue = v2files.filter((f) => /\.(mjs|js)$/.test(f) && CODE_DIRS.some((d) => f.startsWith(d))).map((f) => ({ file: f, importer: relative(AMP, f) }));
while (queue.length) {
  const { file, importer } = queue.shift(); const src = readFileSync(file, "utf8");
  for (const m of src.matchAll(IMPORT_RE)) {
    const target = resolve(dirname(file), m[1]); if (!target.startsWith(AMP) || target.startsWith(V2)) continue;
    if (!existsSync(target)) { console.warn(`warning: ${relative(AMP, file)} imports ${m[1]} which does not exist`); continue; }
    if (!seen.has(target)) { seen.set(target, new Set()); queue.push({ file: target, importer: relative(AMP, target) }); }
    seen.get(target).add(importer);
  }
  // relative imports inside a sibling file (./wrl.js) are siblings of the same repo
  if (!file.startsWith(V2)) for (const m of src.matchAll(/from\s+["'](\.\/[^"']+)["']/g)) { const t = resolve(dirname(file), m[1]); if (existsSync(t) && !seen.has(t)) { seen.set(t, new Set([relative(AMP, file)])); queue.push({ file: t, importer: relative(AMP, t) }); } }
}
const deps = [];
for (const [abs, importers] of [...seen.entries()].sort()) {
  const relAmp = relative(AMP, abs); const repoDir = resolve(AMP, relAmp.split("/")[0]); const inRepo = relative(repoDir, abs);
  const bytes = readFileSync(abs); const commit = git(repoDir, ["rev-parse", "HEAD"]); const blob = git(repoDir, ["rev-parse", `HEAD:${inRepo}`]);
  const blobOfWorktree = createHash("sha1").update(Buffer.concat([Buffer.from(`blob ${bytes.length}\0`), bytes])).digest("hex");
  deps.push({ path: relAmp, repository: relAmp.split("/")[0], commit, blob_at_head: blob, blob_of_copied_bytes: blobOfWorktree, worktree_matches_head: blob === blobOfWorktree, sha256: sha256(bytes), bytes: bytes.length, imported_by: [...importers].sort() });
  mkdirSync(dirname(join(STAGE, name, relAmp)), { recursive: true }); writeFileSync(join(STAGE, name, relAmp), bytes);
}
mkdirSync(join(STAGE, name, "REPRO_DEPENDENCIES"), { recursive: true });
writeFileSync(join(STAGE, name, "REPRO_DEPENDENCIES/MANIFEST.json"), JSON.stringify({ generated_for: name, rule: "verification copies only (D-033); production imports the real sibling checkout and canon.mjs refuses a moved TRVM blob", files: deps }, null, 1) + "\n");
writeFileSync(join(STAGE, name, "REPRO_DEPENDENCIES/README.md"), `# REPRO_DEPENDENCIES\n\nByte-exact copies of every sibling file the shipped Graphonomous code imports, placed at their ProjectAmp2-relative paths so the imports resolve unchanged from inside this ZIP. \`MANIFEST.json\` records repository, HEAD commit, blob OID at HEAD, blob OID of the copied bytes (they must agree), sha256 and importers.\n\nRe-run from the zip (no git needed): \`cd ${name}/graphonomous/v2 && node --test test/canon.test.mjs test/lid.test.mjs test/schema.test.mjs test/rules.test.mjs test/eval.test.mjs test/b1.test.mjs test/query.test.mjs test/wrl_world.test.mjs test/certificate.test.mjs test/certificate_trvm.test.mjs && python3 test/canon_twin.py --manifest projections/baseline && node bin/g0.mjs verify --dir projections/baseline && node bin/g0.mjs verify-eval --dir projections/baseline\`. \`test/projection.test.mjs\` rebuilds from the pinned registries and needs the real ProjectAmp2 checkout.\n`);
cpSync(resolve(report), join(STAGE, name, report.split("/").pop()));
// 3. SHA256SUMS + zip
const all = walk(join(STAGE, name)).sort(); const sums = all.map((f) => `${sha256(readFileSync(f))}  ${relative(join(STAGE, name), f)}`).join("\n") + "\n";
writeFileSync(join(STAGE, name, "SHA256SUMS"), sums);
const zip = join(OUT, `${name}.zip`); rmSync(zip, { force: true });
execFileSync("python3", ["-c", "import sys,os,zipfile\nroot,name,out=sys.argv[1:4]\nz=zipfile.ZipFile(out,'w',zipfile.ZIP_DEFLATED)\nfor d,_,fs in sorted(os.walk(os.path.join(root,name))):\n  for f in sorted(fs):\n    p=os.path.join(d,f); z.write(p, os.path.relpath(p, root))\nz.close()", STAGE, name, zip]);
const zsum = sha256(readFileSync(zip)); writeFileSync(zip + ".sha256", `${zsum}  ${name}.zip\n`);
console.log(JSON.stringify({ zip, sha256: zsum, files: all.length, repro_dependencies: deps.map((d) => `${d.path}@${d.commit.slice(0, 7)} blob ${d.blob_at_head.slice(0, 8)} ${d.worktree_matches_head ? "ok" : "WORKTREE≠HEAD"}`), bytes: statSync(zip).size }, null, 1));
