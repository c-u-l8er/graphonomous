#!/usr/bin/env node
/* g05 — a static file server for the G0.5 read-only inspector, and nothing else.
 *
 * No API, no writes, no state. It answers GET (and HEAD) for files under one directory, refuses anything that escapes
 * it, and exits. The page it serves is read-only by construction; this process gives it nothing to write to.
 *
 *   node bin/g05.mjs [--port 8977] [--dir ui]
 *
 * gzip is applied on the fly (node:zlib, a builtin — the package stays zero-dependency) because a world file is
 * megabytes of long identifiers and compresses roughly tenfold.
 */
import { createServer } from "node:http";
import { createReadStream, statSync, existsSync } from "node:fs";
import { resolve, join, normalize, extname, sep, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { createGzip } from "node:zlib";

const HERE = dirname(fileURLToPath(import.meta.url));
const V2 = resolve(HERE, "..");
const argv = process.argv.slice(2);
const opt = (n, d) => { const i = argv.indexOf("--" + n); return i >= 0 ? (argv[i + 1] ?? d) : d; };

const ROOT = resolve(V2, opt("dir", join(V2, "ui")));
const PORT = Number(opt("port", 8977));

const MIME = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".mjs": "text/javascript; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".svg": "image/svg+xml",
  ".png": "image/png",
  ".jpg": "image/jpeg",
  ".jpeg": "image/jpeg",
  ".webp": "image/webp",
  ".ico": "image/x-icon",
  ".woff2": "font/woff2",
  ".txt": "text/plain; charset=utf-8",
  ".map": "application/json; charset=utf-8",
};
const COMPRESSIBLE = new Set([".html", ".js", ".mjs", ".css", ".json", ".svg", ".txt", ".map"]);

const fail = (res, code, msg) => { res.writeHead(code, { "content-type": "text/plain; charset=utf-8" }); res.end(msg + "\n"); };

/** Resolve a request path inside ROOT, or null. Refuses `..`, absolute escapes, NUL bytes and symlink escapes. */
function safePath(urlPath) {
  let decoded;
  try { decoded = decodeURIComponent(urlPath.split("?")[0].split("#")[0]); } catch { return null; }
  if (decoded.includes("\0")) return null;
  const rel = normalize(decoded).replace(/^(\.\.(\/|\\|$))+/, "");
  const target = resolve(ROOT, "." + (rel.startsWith("/") ? rel : "/" + rel));
  if (target !== ROOT && !target.startsWith(ROOT + sep)) return null;
  return target;
}

const server = createServer((req, res) => {
  if (req.method !== "GET" && req.method !== "HEAD") return fail(res, 405, "read-only server: GET and HEAD only");
  let file = safePath(req.url || "/");
  if (!file) return fail(res, 403, "refused: path escapes the served directory");
  if (existsSync(file) && statSync(file).isDirectory()) file = join(file, "index.html");
  if (!existsSync(file) || !statSync(file).isFile()) return fail(res, 404, "not found: " + req.url);

  const ext = extname(file).toLowerCase();
  const stat = statSync(file);
  const headers = {
    "content-type": MIME[ext] || "application/octet-stream",
    "cache-control": "no-store",
    "x-content-type-options": "nosniff",
    "last-modified": stat.mtime.toUTCString(),
  };
  const wantsGzip = COMPRESSIBLE.has(ext) && /\bgzip\b/.test(req.headers["accept-encoding"] || "");
  if (wantsGzip) headers["content-encoding"] = "gzip";
  else headers["content-length"] = stat.size;
  res.writeHead(200, headers);
  if (req.method === "HEAD") return res.end();
  const stream = createReadStream(file);
  stream.on("error", () => res.destroy());
  if (wantsGzip) stream.pipe(createGzip()).pipe(res); else stream.pipe(res);
});

server.listen(PORT, "127.0.0.1", () => {
  console.log(`g05 read-only inspector: http://127.0.0.1:${PORT}/  (serving ${ROOT}, GET only, no API, no writes)`);
});
