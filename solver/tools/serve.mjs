// serve.mjs — dev server for the prototype app.
//
// It does two things node must do and the browser cannot:
//   /api/fixtures            list + read the bundled local sites
//   /api/fetch?url=...       fetch a live origin
//
// THE CORS NOTE, stated plainly: a page cannot fetch arbitrary third-party origins.
// That is not a limitation of this prototype, it is the browser's same-origin policy,
// and no amount of client-side work removes it. In production this endpoint is a
// Cloudflare Worker — about forty lines — and it is the only server-side component
// the solver needs. Everything else here runs in the page.
import { createServer } from 'node:http';
import { readFileSync, readdirSync, existsSync, statSync } from 'node:fs';
import { join, extname, dirname, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const PORT = Number(process.env.PORT || 8941);
const TYPES = { '.html': 'text/html', '.js': 'text/javascript', '.mjs': 'text/javascript',
                '.css': 'text/css', '.json': 'application/json', '.svg': 'image/svg+xml' };

const FIXTURES = {
  'opensentience.org':      '/home/travis/ProjectAmp2/opensentience.org',
  'graphonomous.com':       '/home/travis/ProjectAmp2/graphonomous.com',
  'ampersandboxdesign.com': '/home/travis/ProjectAmp2/ampersandboxdesign.com',
  'bendscript.com':         '/home/travis/ProjectAmp2/bendscript.com',
  'alkeyword.com':          '/home/travis/ProjectAmp2/alkeyword.com'
};

const SKIP = new Set(['node_modules', 'old_scrap', 'dist', 'prototype', '.git', 'docs']);
const walk = (d, base = d, out = []) => {
  for (const e of readdirSync(d, { withFileTypes: true })) {
    if (e.name.startsWith('.') || SKIP.has(e.name)) continue;
    const p = join(d, e.name);
    if (e.isDirectory()) walk(p, base, out);
    else if (e.name.endsWith('.html')) out.push({ url: '/' + relative(base, p), html: readFileSync(p, 'utf8') });
  }
  return out;
};
const readIf = (d, n) => existsSync(join(d, n)) ? readFileSync(join(d, n), 'utf8') : null;

createServer(async (req, res) => {
  const u = new URL(req.url, `http://localhost:${PORT}`);
  const send = (code, body, type = 'application/json') =>
    res.writeHead(code, { 'content-type': type, 'cache-control': 'no-store' }).end(body);

  if (u.pathname === '/api/fixtures') {
    return send(200, JSON.stringify(Object.keys(FIXTURES).filter((k) => existsSync(FIXTURES[k]))));
  }
  if (u.pathname === '/api/fixture') {
    const dir = FIXTURES[u.searchParams.get('name')];
    if (!dir || !existsSync(dir)) return send(404, JSON.stringify({ error: 'unknown fixture' }));
    return send(200, JSON.stringify({
      docs: walk(dir),
      site: { origin: u.searchParams.get('name'), robots: readIf(dir, 'robots.txt'),
              sitemap: readIf(dir, 'sitemap.xml'), llmsTxt: readIf(dir, 'llms.txt'),
              agentCard: readIf(dir, '.well-known/agent-card.json') }
    }));
  }
  if (u.pathname === '/api/fetch') {
    const target = u.searchParams.get('url');
    try {
      const r = await fetch(target, { headers: { 'user-agent': 'graphonomous-solver/0.1 (+prototype)' } });
      return send(200, JSON.stringify({ status: r.status, html: await r.text() }));
    } catch (e) { return send(502, JSON.stringify({ error: String(e) })); }
  }

  let p = u.pathname === '/' ? '/app/index.html' : u.pathname;
  const file = join(ROOT, p);
  if (!file.startsWith(ROOT) || !existsSync(file) || statSync(file).isDirectory())
    return send(404, 'not found', 'text/plain');
  send(200, readFileSync(file), TYPES[extname(file)] || 'application/octet-stream');
}).listen(PORT, () => console.log(`solver app  →  http://127.0.0.1:${PORT}`));
