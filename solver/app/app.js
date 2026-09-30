// app.js — the prototype. Every module below is the SAME code the CLI runs; nothing
// is reimplemented for the browser, and nothing is bundled. The only thing the page
// cannot do itself is fetch a third-party origin (same-origin policy), so the dev
// server does that one job — in production, a Worker.
import { runReport } from '/lib/report.mjs';
import { DEFAULT_FLOOR } from '/lib/solve.mjs';

const $ = (id) => document.getElementById(id);
const esc = (s) => String(s ?? '').replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));

let corpus = null;   // { docs, site } — kept so the floor can be re-run without re-fetching

const floorNow = () => ({
  sigma_empty: $('sigma').checked,
  beta_min: Number($('betaMin').value),
  deny_default: $('deny').checked ? 'must_allow' : 'allow',
  acyclic: true
});

// --- rendering --------------------------------------------------------------
function renderSummary(r) {
  const s = r.summary;
  $('summary').classList.remove('hidden');
  $('summary').innerHTML = [
    ['', s.findings, 'findings'],
    ['c', s.by_class.contradiction, 'contradiction'],
    ['d', s.by_class.drift, 'drift'],
    ['s', s.by_class.stale, 'stale'],
    ['u', s.by_class.unresolved, 'unresolved'],
    ['', r.site.pages, 'pages'],
    ['', r.site.quantityClaims, 'claims'],
    ['v', s.vetoed, `of ${s.options} vetoed`],
    ['', s.floor_bits, 'floor overrode'],
    ['', `${s.beta_measured}/${s.options}`, 'β measured']
  ].map(([k, v, l]) => `<div class="stat ${k}"><b>${esc(v)}</b><span>${esc(l)}</span></div>`).join('');
  $('runid').textContent = r.run_id.slice(0, 22) + '…';
}

function renderOption(o, verdict) {
  const veto = verdict.vetoed.find((v) => v.id === o.id);
  const chosen = verdict.decision === o.id;
  const rank = verdict.ranking.find((x) => x.id === o.id);
  const cls = chosen ? 'chosen' : veto ? 'vetoed' : '';
  return `<div class="opt ${cls}">
    <div class="mark">${chosen ? '✓' : veto ? '✗' : '·'}</div>
    <div>
      <div class="id">${esc(o.id)}</div>
      <div class="why">utility ${esc(o.utility)} — ${esc(o.why)}</div>
      ${veto ? veto.failures.map((f) => `<div class="fail">refused · ${esc(f.family)}: ${esc(f.why)}</div>`).join('') : ''}
      ${chosen ? (o.changes || []).map((c) => `<div class="chg">→ ${esc(c.page)} — ${esc(c.change)}</div>`).join('') : ''}
    </div>
    <div class="num">
      <span class="beta-${o.betaSource}">β ${o.beta.toFixed(2)} ${o.betaSource === 'measured' ? '✓measured' : 'declared'}</span><br>
      ${veto ? `score <b>0</b> (raw ${esc(veto.rawWouldBe)})` : `score <b>${esc(rank ? rank.score : '—')}</b>`}<br>
      ${esc(o.edits)} edit${o.edits === 1 ? '' : 's'}
    </div>
  </div>`;
}

function renderFindings(r) {
  const order = { contradiction: 0, drift: 1, stale: 2, unresolved: 3 };
  const sorted = [...r.solved].sort((a, b) =>
    (order[a.finding.class] - order[b.finding.class]) ||
    (b.verdict?.floorEnforced || 0) - (a.verdict?.floorEnforced || 0));

  $('findings').innerHTML = sorted.map((s) => {
    const f = s.finding, v = s.verdict;
    const dec = !v ? '<span class="decision none">no catalogue</span>'
      : v.decision ? `<span class="decision">→ ${esc(v.decision)}</span>`
                   : '<span class="decision none">→ refused entirely</span>';
    return `<details>
      <summary>
        <span class="tag ${f.class}">${esc(f.class)}</span>
        <span class="fam">${esc(f.families.join('·').toUpperCase())}</span>
        <span class="detail">${esc(f.detail)}<div class="rule">${esc(f.rule)} v${f.rule_version} · ${esc(f.lid.slice(0, 24))}…</div></span>
        ${dec}
      </summary>
      <div class="body">
        <ul class="explain">${f.explain.map((e) => `<li>${esc(e)}</li>`).join('')}</ul>
        ${v ? `<h4>candidate remedies — floor then gradient</h4>
               ${s.options.map((o) => renderOption(o, v)).join('')}
               <div class="note">${esc(v.note)}</div>` : `<div class="note">${esc(s.note)}</div>`}
      </div>
    </details>`;
  }).join('');
}

function solve() {
  if (!corpus) return;
  const t0 = performance.now();
  const r = runReport(corpus.docs, corpus.site, floorNow());
  renderSummary(r); renderFindings(r);
  $('status').textContent =
    `${corpus.docs.length} pages · ${r.summary.findings} findings · ${r.summary.vetoed} vetoed · ${(performance.now() - t0).toFixed(0)} ms in the browser`;
  window.__report = r;                 // for poking at in devtools
}

// --- loading ----------------------------------------------------------------
async function loadFixture(name) {
  $('status').textContent = 'loading…';
  corpus = await (await fetch(`/api/fixture?name=${encodeURIComponent(name)}`)).json();
  solve();
}

async function loadUrl(url) {
  $('status').textContent = 'fetching through the dev server (the page cannot do this itself)…';
  const r = await (await fetch(`/api/fetch?url=${encodeURIComponent(url)}`)).json();
  if (r.error) { $('status').textContent = 'fetch failed: ' + r.error; return; }
  corpus = { docs: [{ url: '/', html: r.html }], site: { origin: url } };
  solve();
}

// --- wiring -----------------------------------------------------------------
$('betaMin').addEventListener('input', () => { $('betaOut').textContent = Number($('betaMin').value).toFixed(2); solve(); });
$('sigma').addEventListener('change', solve);
$('deny').addEventListener('change', solve);
$('fixture').addEventListener('change', (e) => e.target.value && loadFixture(e.target.value));
$('run').addEventListener('click', () => {
  const u = $('url').value.trim();
  u ? loadUrl(u) : $('fixture').value && loadFixture($('fixture').value);
});

(async () => {
  const names = await (await fetch('/api/fixtures')).json();
  $('fixture').innerHTML = names.map((n) => `<option>${esc(n)}</option>`).join('');
  $('betaOut').textContent = DEFAULT_FLOOR.beta_min.toFixed(2);
  if (names.length) loadFixture(names[0]);
})();
