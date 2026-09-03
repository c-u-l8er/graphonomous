/* git.mjs — pinned, read-only access to the source repositories. Every read goes through `<commit>:<path>`; the
 * working tree is never consulted (D-003, D-023). HEAD is recorded as a witness only. */
import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { G0Error } from "../lib/canon.mjs";

const git = (dir, args, opts = {}) => execFileSync("git", ["-C", dir, ...args], { maxBuffer: 256 * 1024 * 1024, ...opts });
const gitText = (dir, args) => git(dir, args, { encoding: "utf8" }).trim();

/** Open a repository at a pinned commit. Resolves abbreviated commits to full OIDs once and refuses to proceed if the
 *  object is missing. Returns an object whose every method is pinned. */
export function openRepo(name, dir, commit) {
  let full;
  try { full = gitText(dir, ["rev-parse", "--verify", `${commit}^{commit}`]); }
  catch (e) { throw new G0Error("SOURCE_MOVED", `${name}: commit ${commit} is not in ${dir} (${String(e.message).split("\n")[0]})`); }
  const tree = gitText(dir, ["rev-parse", `${full}^{tree}`]);
  const paths = new Set(gitText(dir, ["ls-tree", "-r", "--name-only", full]).split("\n").filter(Boolean));
  const head = gitText(dir, ["rev-parse", "HEAD"]);
  const blobCache = new Map(), bytesCache = new Map();
  return {
    name, dir, commit: full, tree, head, paths,
    has: (p) => paths.has(p),
    blobOid(p) {
      if (!paths.has(p)) return null;
      if (!blobCache.has(p)) blobCache.set(p, gitText(dir, ["rev-parse", `${full}:${p}`]));
      return blobCache.get(p);
    },
    bytes(p) {
      if (!paths.has(p)) throw new G0Error("SOURCE_MISSING", `${name}@${full.slice(0, 7)} has no ${p}`);
      if (!bytesCache.has(p)) bytesCache.set(p, git(dir, ["show", `${full}:${p}`]));
      return bytesCache.get(p);
    },
    sha256(p) { return createHash("sha256").update(this.bytes(p)).digest("hex"); },
    /** Files under a prefix, sorted. */
    under(prefix) { return [...paths].filter((p) => p.startsWith(prefix)).sort(); },
  };
}

export const headOf = (dir) => gitText(dir, ["rev-parse", "HEAD"]);
export const branchOf = (dir) => { try { return gitText(dir, ["branch", "--show-current"]); } catch { return ""; } };
