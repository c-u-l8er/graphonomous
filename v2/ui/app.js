/* G0.5 — the read-only inspector.
 *
 * This file renders. It does not compute answers. Every identity, every explanation tree, every A1–A7 answer on the
 * screen was produced in Node by lib/query.mjs / lib/acceptance.mjs and baked into ui/data/<slug>.json by
 * tools/g05_build.mjs. Here we index those values by lid and by fact key, lay them out, and draw them.
 *
 * Specifically, and by design, this file contains:
 *   - no hashing (a lid, a rel-, a rev-, a sem-, a root- is read from the data, never computed here);
 *   - no rule evaluation and no explanation unfolding (an explain tree is displayed exactly as Graph.explain returned it);
 *   - no writes of any kind, no network beyond two relative GETs for the data files, no eval;
 *   - no layout information taken from or written to the data: positions are a function this file applies to lids at
 *     draw time, deterministic (ring by BFS depth, ordered by lid), and part of no identity.
 */

/* ------------------------------------------------------------------ tiny DOM */
const h = (tag, props, ...kids) => {
  const e = document.createElement(tag);
  for (const [k, v] of Object.entries(props || {})) {
    if (v == null || v === false) continue;
    if (k === "class") e.className = v;
    else if (k === "text") e.textContent = v;
    else if (k.startsWith("on")) e.addEventListener(k.slice(2), v);
    else e.setAttribute(k, v === true ? "" : String(v));
  }
  add(e, kids);
  return e;
};
const NS = "http://www.w3.org/2000/svg";
const s = (tag, props, ...kids) => {
  const e = document.createElementNS(NS, tag);
  for (const [k, v] of Object.entries(props || {})) {
    if (v == null || v === false) continue;
    if (k === "text") e.textContent = v;
    else if (k.startsWith("on")) e.addEventListener(k.slice(2), v);
    else e.setAttribute(k, String(v));
  }
  add(e, kids);
  return e;
};
function add(e, kids) {
  for (const kid of kids.flat(Infinity)) {
    if (kid == null || kid === false || kid === "") continue;
    e.append(kid && kid.nodeType ? kid : document.createTextNode(String(kid)));
  }
}
const $ = (id) => document.getElementById(id);
const clear = (e) => { while (e.firstChild) e.removeChild(e.firstChild); return e; };

/* ------------------------------------------------------------------ state (UI only — never an identity) */
const S = {
  index: null,
  slug: null,
  view: "graph",
  focus: null,
  depth: 2,
  roles: new Set(),
  kinds: new Set(),
  inspect: null,          // {type, lid} | {type:"fact", key}
  explain: null,          // {kind:"record"|"fact", key, title}
  hotRelation: null,
  faultHighlight: null,
  search: "",
};
let W = null;             // the loaded world payload + lookup maps

/* ------------------------------------------------------------------ formatting */
const ROLE_COLORS = [
  "#4fc3f7", "#ffca63", "#6ddf9c", "#b98bff", "#ff9f6a", "#7ce0c8", "#ff9ee0", "#a9e07f",
  "#8fb6ff", "#e0c36d", "#ff7a85", "#68d6e8", "#c0a0ff", "#9aa7b8", "#e88fb0", "#7fd0a0",
  "#d6a76a", "#9ee0d0", "#c9d1d9", "#ffb0b0",
];
const roleColor = (role) => {
  const i = W && W.roleOrder.indexOf(role);
  return i >= 0 ? ROLE_COLORS[i % ROLE_COLORS.length] : "#9aa7b8";
};
const shortLid = (lid, max = 30) => {
  if (lid.length <= max) return lid;
  const parts = lid.split(":");
  const tail = parts.slice(-2).join(":");
  return tail.length <= max ? "…" + tail : "…" + lid.slice(-(max - 1));
};
/* A content address is recognised by its prefix, so a shortened one keeps the head, never the tail. */
const shortRoot = (id, keep = 14) => (id && id.length > keep + 12 ? id.slice(0, keep + 12) + "…" : id);
const scalar = (v) => (typeof v === "string" ? v : JSON.stringify(v));
const registryFamily = (assertedBy) => (String(assertedBy).split(":")[1] || String(assertedBy));

/* A lid rendered as a navigation control. Navigation only — nothing on this page acts on a record. */
const lidBtn = (lid, cls) => h("button", { class: "lid " + (cls || kindClassOf(lid)), title: lid, onclick: () => gotoLid(lid), text: lid });
const lidShort = (lid, max) => h("button", { class: "lid " + kindClassOf(lid), title: lid, onclick: () => gotoLid(lid), text: shortLid(lid, max || 30) });
function kindClassOf(lid) {
  if (!W) return "";
  if (W.relByLid.has(lid)) return "rel";
  if (W.faultByLid.has(lid)) return "fault";
  if (W.locByLid.has(lid)) return "loc";
  return "";
}
const maybeLid = (v) => (typeof v === "string" && W && W.anyLid.has(v) ? lidBtn(v) : h("span", { class: "dim", text: scalar(v) }));

/* rel(arg, arg) — the way a derived fact is written everywhere else in G0. */
const factExpr = (arr) =>
  h("span", null,
    h("span", { class: "rulepill", text: arr[0] }), "(",
    arr.slice(1).map((a, i) => [i ? ", " : "", maybeLid(a)]),
    ")");

const kv = (pairs) => {
  const dl = h("dl", { class: "kv" });
  for (const [k, v] of pairs) {
    if (v == null || v === "") continue;
    dl.append(h("dt", { text: k }), h("dd", null, v));
  }
  return dl;
};

/* ------------------------------------------------------------------ load */
async function boot() {
  const idx = await (await fetch("data/index.json", { cache: "no-store" })).json();
  S.index = idx;
  if (!idx.worlds.length) { $("view").append(h("div", { class: "empty", text: "ui/data holds no worlds: run node tools/g05_build.mjs --out ui/data" })); return; }
  renderWorlds();
  await selectWorld(idx.worlds[0].slug);
}

async function selectWorld(slug) {
  const entry = S.index.worlds.find((w) => w.slug === slug);
  $("view").replaceChildren(h("div", { class: "empty", text: `loading ${entry.file} (${(entry.bytes / 1e6).toFixed(1)} MB of precomputed answers)…` }));
  const data = await (await fetch("data/" + entry.file, { cache: "no-store" })).json();
  W = index(data);
  S.slug = slug;
  S.roles = new Set(W.roleOrder);
  S.kinds = new Set(Object.keys(W.counts.relation_kinds));
  S.focus = pickFocus();
  S.inspect = { type: "node", lid: S.focus };
  S.explain = { kind: "record", key: S.focus };
  S.hotRelation = null;
  S.faultHighlight = null;
  S.search = "";
  $("search").value = "";
  renderAll();
}

function index(d) {
  const w = Object.assign({}, d);
  w.nodeByLid = new Map(d.nodes.map((n) => [n.lid, n]));
  w.relByLid = new Map(d.relations.map((r) => [r.lid, r]));
  w.asrtByLid = new Map(d.assertions.map((a) => [a.lid, a]));
  w.locByLid = new Map(d.locations.map((l) => [l.lid, l]));
  w.faultByLid = new Map(d.faults.map((f) => [f.lid, f]));
  w.anyLid = new Set([...w.nodeByLid.keys(), ...w.relByLid.keys(), ...w.asrtByLid.keys(), ...w.locByLid.keys(), ...w.faultByLid.keys()]);
  w.roleOrder = Object.keys(d.counts.node_roles);
  w.out = new Map(); w.in = new Map();
  for (const r of d.relations) {
    if (!w.out.has(r.source)) w.out.set(r.source, []);
    w.out.get(r.source).push(r);
    if (!w.in.has(r.target)) w.in.set(r.target, []);
    w.in.get(r.target).push(r);
  }
  w.searchable = [
    ...d.nodes.map((n) => ({ lid: n.lid, what: n.kind, type: "node" })),
    ...d.relations.map((r) => ({ lid: r.lid, what: r.kind, type: "relation" })),
    ...d.faults.map((f) => ({ lid: f.lid, what: f.code, type: "fault" })),
    ...d.locations.map((l) => ({ lid: l.lid, what: l.precision, type: "location" })),
    ...d.assertions.map((a) => ({ lid: a.lid, what: a.precision, type: "assertion" })),
  ];
  w.factKeys = Object.keys(d.explain.facts);
  return w;
}

/* Deterministic default focus: the page opens where A1 opens — the first node lid the baked acceptance answer names.
 * Falls back to the busiest node, ties broken by lid. Either way it is a function of the data, never of a saved view. */
function pickFocus() {
  for (const q of W.acceptance.questions) {
    if (!q.answered) continue;
    for (const st of q.steps || []) {
      const cands = st.kind === "facts" ? (st.value || []).flatMap((f) => f.args)
        : st.kind === "lids" ? st.value || []
        : st.kind === "record" && st.value ? [st.value.lid]
        : [];
      for (const c of cands) if (typeof c === "string" && W.nodeByLid.has(c)) return c;
    }
  }
  let best = null, bestN = -1;
  for (const n of [...W.nodeByLid.keys()].sort()) {
    const deg = (W.out.get(n) || []).length + (W.in.get(n) || []).length;
    if (deg > bestN) { best = n; bestN = deg; }
  }
  return best;
}

/* ------------------------------------------------------------------ render orchestration */
function renderAll() {
  renderWorlds();
  renderWhere();
  renderFilters();
  renderCounts();
  renderIdentity();
  renderView();
  renderExplain();
}

function renderWorlds() {
  const box = clear($("worlds"));
  for (const w of S.index.worlds) {
    box.append(h("button", { class: "world" + (w.slug === S.slug ? " on" : ""), onclick: () => selectWorld(w.slug) },
      h("div", { class: "nm", text: w.name }),
      h("div", { class: "snap", text: w.snapshot }),
      h("div", { class: "cnt", text: `${w.counts.node} nodes · ${w.counts.relation} relations · ${w.derived_facts} derived · ${(w.bytes / 1e6).toFixed(1)} MB` })));
  }
}

function renderWhere() {
  clear($("where")).append(
    h("span", null, "world ", h("b", { text: W.name })),
    h("span", null, "snapshot ", h("b", { class: "id", text: W.identity.snapshot })),
    h("span", null, "projection ", h("b", { class: "id", text: shortRoot(W.identity.projection.root) })),
    h("span", { class: "faint", text: W.identity.spec }));
}

function renderCounts() {
  clear($("counts")).append(kv([
    ["records", Object.entries(W.counts.records).map(([k, v]) => h("span", null, h("span", { class: "chip", text: k }), " ", h("span", { class: "num", text: v }), " ")) ],
    ["derived facts", h("span", { class: "num", text: W.facts.length })],
    ["derived rules", h("div", null, Object.entries(W.counts.derived_rules).map(([k, v]) =>
      h("div", null, h("span", { class: "rulepill", text: k }), " ", h("span", { class: "num", text: v })))) ],
    ["registries", h("div", null, Object.entries(W.counts.registries).map(([k, v]) =>
      h("div", null, h("span", { class: "faint", text: registryFamily(k) }), " ", h("span", { class: "num", text: v })))) ],
    ["location precision", Object.entries(W.counts.location_precision).map(([k, v]) => h("span", null, h("span", { class: "chip", text: k }), " ", h("span", { class: "num", text: v }), " "))],
  ]));
}

function renderFilters() {
  const roleBox = clear($("roleFilters"));
  for (const [role, n] of Object.entries(W.counts.node_roles)) {
    roleBox.append(h("button", {
      class: "f" + (S.roles.has(role) ? " on" : ""), style: `color:${roleColor(role)}`,
      onclick: () => { S.roles.has(role) ? S.roles.delete(role) : S.roles.add(role); renderFilters(); renderView(); },
    }, h("i", { class: "sw" }), h("span", { text: role }), h("span", { class: "n", text: n })));
  }
  const kindBox = clear($("kindFilters"));
  for (const [kind, n] of Object.entries(W.counts.relation_kinds)) {
    kindBox.append(h("button", {
      class: "f" + (S.kinds.has(kind) ? " on" : ""),
      onclick: () => { S.kinds.has(kind) ? S.kinds.delete(kind) : S.kinds.add(kind); renderFilters(); renderView(); },
    }, h("span", { text: kind }), h("span", { class: "n", text: n })));
  }
}

/* ------------------------------------------------------------------ identity panel */
function renderIdentity() {
  const I = W.identity;
  const box = clear($("identity"));
  const coord = (n, title, why, rows) => box.append(
    h("div", { class: "fourrow", style: "margin-bottom:9px" },
      h("div", { class: "r " + n },
        h("div", { class: "lbl", text: title }),
        h("div", { class: "val" }, kv(rows)),
        h("div", { class: "why", text: why }))));

  coord("statement", "1 · projection root — what the registries said",
    "content address of the observed projection: records, faults, manifest. Moves when a source byte moves.",
    [["root", h("span", { class: "id", text: I.projection.root })],
     ["snapshot", h("span", { class: "id", text: I.snapshot })],
     ["entries", h("span", { class: "num", text: I.projection.entries })],
     ["ruleset", h("span", { class: "faint", text: I.ruleset })]]);

  coord("kind", "2 · evaluation root — what the rules derived",
    "a separate artifact beside the projection: a rule change moves this root and not the one above.",
    I.evaluation ? [
      ["root", h("span", { class: "id", text: I.evaluation.root })],
      ["over projection", h("span", { class: "faint", text: I.evaluation.projection_root })],
      ["evaluator", h("span", { class: "faint", text: I.evaluation.evaluator })],
      ["facts", h("span", { class: "num", text: I.evaluation.count })],
      ["trvm_derivation", h("b", { style: "color:var(--warn)", text: String(I.evaluation.trvm_derivation) })],
      ["checker", h("span", { class: "faint", text: `${I.evaluation.checker.checked} derivations re-checked, ok=${I.evaluation.checker.ok}, failures=${I.evaluation.checker.failures}` })],
    ] : [["evaluation", h("span", { class: "faint", text: "none stored" })]]);

  coord("rev", "3 · WRL world — the sealed semantic world",
    "kernel-minted identities for the same records under a semantic profile. A different coordinate system from the roots above.",
    I.wrl ? [
      ["sem", h("span", { class: "id sem-id", text: I.wrl.sem })],
      ["profile_id", h("span", { class: "faint", text: I.wrl.profile_id })],
      ["objects", h("span", { class: "num", text: I.wrl.objects })],
      ["relations", h("span", { class: "num", text: I.wrl.relations })],
      ["minted_by", h("span", { class: "faint", text: I.wrl.minted_by.join(", ") })],
      ["state", h("span", { class: "faint", text: I.wrl.state })],
    ] : [["world", h("span", { class: "faint", text: "not sealed" })]]);

  const C = I.certificate;
  coord("rel", "4 · G0-D certificate — the verified claim",
    "a claim about reconstruction under pinned verifier coordinates. Not a truth claim; see scope.",
    C ? [
      ["vclaim", h("span", { class: "id vclaim-id", text: C.vclaim })],
      ["protocol", h("span", { class: "faint", text: C.protocol })],
      ["aggregate_id", h("span", { class: "faint", text: C.aggregate_id })],
      ["snapshot_commitment", h("span", { class: "id", text: C.claim.snapshot_commitment })],
      ["schema_set_id", h("span", { class: "faint", text: C.claim.schema_set_id })],
      ["adapter_contract_id", h("span", { class: "faint", text: C.claim.adapter_contract_id })],
      ["projection_claim", h("span", { class: "faint", text: C.claim.projection_claim_sem_id })],
      ["status", h("b", { style: "color:var(--good)", text: C.verifier_note })],
    ] : [["certificate", h("span", { class: "faint", text: "none" })]]);

  if (C) {
    const scopeRows = Object.entries(C.claim.scope).sort(([a], [b]) => (a < b ? -1 : 1)).map(([k, v]) =>
      h("tr", null,
        h("td", { class: "faint", text: k }),
        h("td", null, typeof v === "boolean"
          ? h("b", { style: `color:${v ? "var(--good)" : "var(--warn)"}`, text: String(v) })
          : h("span", { class: "dim", text: String(v) }))));
    box.append(h("div", { class: "sec" },
      h("h3", { text: "certificate scope — what it does NOT claim" }),
      h("div", { class: "body" },
        h("table", { class: "t" }, h("tbody", null, scopeRows)))));

    box.append(h("div", { class: "sec" },
      h("h3", { text: "chain ids — the verifier coordinates" }),
      h("div", { class: "body" }, kv([
        ["projector", h("div", null, h("div", { class: "faint", text: C.chain_ids.projector.id }), h("div", { class: "id", text: C.chain_ids.projector.code }))],
        ["checker", h("div", null, h("div", { class: "faint", text: C.chain_ids.checker.id }), h("div", { class: "id", text: C.chain_ids.checker.code }))],
        ["trvm_commit", h("span", { class: "faint", text: C.chain_ids.trvm_commit })],
        ["trvm_blobs", h("div", null, C.chain_ids.trvm_blobs.map((b) =>
          h("div", null, h("span", { class: "faint", text: b.file }), " ", h("span", { class: "dim", text: b.blob.slice(0, 12) }))))],
      ]))));
  }

  box.append(h("div", { class: "sec" },
    h("h3", { text: "pinned sources" }),
    h("div", { class: "body" },
      h("table", { class: "t" },
        h("thead", null, h("tr", null, h("th", { text: "namespace" }), h("th", { text: "repo@commit" }), h("th", { text: "files" }))),
        h("tbody", null, W.identity.snapshot_sources.map((src) =>
          h("tr", null,
            h("td", { class: "dim", text: src.namespace }),
            h("td", { class: "faint", text: `${src.repo}@${src.commit.slice(0, 12)}` }),
            h("td", { class: "num", text: src.files }))))))));
}

/* ------------------------------------------------------------------ view switch */
function renderView() {
  const view = clear($("view"));
  for (const b of document.querySelectorAll("#tabs button")) b.classList.toggle("on", b.dataset.view === S.view);
  if (S.view === "graph") { view.append(graphPane()); view.append(inspectorPane()); }
  else if (S.view === "faults") view.append(faultsPane());
  else view.append(acceptancePane());
}

/* ------------------------------------------------------------------ graph */
const RING_CAP = [1, 22, 34];

function graphModel() {
  const nodeOk = (lid) => { const n = W.nodeByLid.get(lid); return !!n && S.roles.has(n.kind); };
  const relOk = (r) => S.kinds.has(r.kind) && nodeOk(r.source) && nodeOk(r.target);
  const around = (lid) => [...(W.out.get(lid) || []), ...(W.in.get(lid) || [])]
    .filter(relOk).sort((a, b) => (a.lid < b.lid ? -1 : 1));

  const rings = [[S.focus]];
  const seen = new Set([S.focus]);
  const over = [];
  for (let d = 1; d <= S.depth; d++) {
    const next = [];
    for (const lid of rings[d - 1]) for (const r of around(lid)) {
      const other = r.source === lid ? r.target : r.source;
      if (seen.has(other)) continue;
      seen.add(other); next.push(other);
    }
    next.sort();
    const cap = RING_CAP[d] || 34;
    if (next.length > cap) { over.push({ depth: d, hidden: next.length - cap }); for (const lid of next.slice(cap)) seen.delete(lid); }
    rings.push(next.slice(0, cap));
  }
  const placed = new Set(rings.flat());
  const edges = W.relations.filter((r) => relOk(r) && placed.has(r.source) && placed.has(r.target));
  return { rings, placed, edges, over, focusHidden: !nodeOk(S.focus) };
}

function graphPane() {
  const m = graphModel();
  const VBW = 760, VBH = 560, cx = VBW / 2, cy = VBH / 2;
  const radii = S.depth === 1 ? [0, 205] : [0, 130, 225];
  const pos = new Map();
  m.rings.forEach((ring, d) => {
    if (d === 0) { pos.set(ring[0], [cx, cy]); return; }
    const r = radii[d];
    ring.forEach((lid, i) => {
      const a = -Math.PI / 2 + (2 * Math.PI * i) / ring.length;
      pos.set(lid, [cx + r * Math.cos(a), cy + r * Math.sin(a)]);
    });
  });

  const g = s("svg", { viewBox: `0 0 ${VBW} ${VBH}`, preserveAspectRatio: "xMidYMid meet", role: "img", "aria-label": "semantic neighbourhood" });
  g.append(s("defs", null, s("marker", { id: "arw", viewBox: "0 0 8 8", refX: 7, refY: 4, markerWidth: 6, markerHeight: 6, orient: "auto-start-reverse" },
    s("path", { d: "M0 0 L8 4 L0 8 z", fill: "#4a5a6d" }))));
  for (let d = 1; d <= S.depth; d++) g.append(s("circle", { class: "ring", cx, cy, r: radii[d] }));

  const showEdgeLabels = m.edges.length <= 42;
  for (const r of m.edges) {
    const a = pos.get(r.source), b = pos.get(r.target);
    if (!a || !b) continue;
    const hot = S.hotRelation === r.lid;
    const line = s("line", { class: "edge" + (hot ? " hot" : ""), x1: a[0], y1: a[1], x2: b[0], y2: b[1], "marker-end": "url(#arw)" });
    const hit = s("line", { class: "edgehit", x1: a[0], y1: a[1], x2: b[0], y2: b[1], onclick: () => openRelation(r.lid) });
    hit.append(s("title", { text: `${r.kind}: ${r.source} → ${r.target}` }));
    g.append(line, hit);
    /* labels sit at 0.62 along the edge, not the midpoint: in a star neighbourhood every midpoint lands in the same
     * crowded band around the focus, and the kinds become unreadable. */
    if (showEdgeLabels) g.append(s("text", { class: "elabel", x: a[0] + (b[0] - a[0]) * 0.62, y: a[1] + (b[1] - a[1]) * 0.62 - 3, "text-anchor": "middle", text: r.kind }));
  }

  m.rings.forEach((ring, d) => {
    for (const lid of ring) {
      const [x, y] = pos.get(lid);
      const n = W.nodeByLid.get(lid);
      const isFocus = d === 0;
      const dot = s("circle", {
        class: "nodedot" + (isFocus ? " focus" : ""), cx: x, cy: y, r: isFocus ? 9 : 6,
        fill: roleColor(n ? n.kind : ""), onclick: () => focusNode(lid),
      });
      dot.append(s("title", { text: `${lid}\n${n ? n.kind : "?"}` }));
      const left = x < cx;
      g.append(dot, s("text", {
        class: "nlabel" + (isFocus ? " focus" : ""),
        x: isFocus ? x : x + (left ? -11 : 11), y: isFocus ? y - 15 : y + 3.5,
        "text-anchor": isFocus ? "middle" : left ? "end" : "start",
        text: shortLid(lid, isFocus ? 46 : 26),
      }));
    }
  });

  const bar = h("div", { class: "graphbar" },
    h("span", { class: "faint", text: "focus" }), lidBtn(S.focus),
    h("span", { class: "faint", text: "depth" }),
    [1, 2].map((d) => h("button", { class: "btn sm" + (S.depth === d ? " on" : ""), text: String(d), onclick: () => { S.depth = d; renderView(); } })),
    h("span", { class: "faint", text: `${m.placed.size} nodes · ${m.edges.length} relations drawn` }),
    m.over.map((o) => h("span", { class: "chip", text: `+${o.hidden} more at depth ${o.depth} (not drawn)` })),
    m.focusHidden ? h("span", { class: "chip", style: "color:var(--warn)", text: "focus role is filtered out" }) : null);

  const legend = h("div", { class: "legend" }, W.roleOrder.filter((r) => S.roles.has(r)).map((r) =>
    h("span", { class: "l" }, h("i", { style: `background:${roleColor(r)}` }), r)));

  return h("div", null, bar, h("div", { class: "graphwrap" }, g), legend);
}

function focusNode(lid) {
  S.focus = lid;
  S.inspect = { type: "node", lid };
  S.hotRelation = null;
  setExplain({ kind: "record", key: lid });
  renderView();
}
function openRelation(lid) {
  const r = W.relByLid.get(lid);
  S.inspect = { type: "relation", lid };
  S.hotRelation = lid;
  if (!W.nodeByLid.has(S.focus)) S.focus = r.source;
  setExplain({ kind: "record", key: lid });
  renderView();
}
function openFact(key) {
  S.inspect = { type: "fact", key };
  setExplain({ kind: "fact", key });
  if (S.view !== "acceptance") renderView();
}
function gotoLid(lid) {
  if (W.nodeByLid.has(lid)) { S.view = "graph"; focusNode(lid); }
  else if (W.relByLid.has(lid)) { S.view = "graph"; openRelation(lid); }
  else if (W.faultByLid.has(lid)) { S.view = "faults"; S.faultHighlight = lid; renderView(); }
  else if (W.locByLid.has(lid)) { S.inspect = { type: "location", lid }; renderView(); }
  else if (W.asrtByLid.has(lid)) { S.inspect = { type: "assertion", lid }; renderView(); }
  renderExplain();
}
function setExplain(e) { S.explain = e; renderExplain(); }

/* ------------------------------------------------------------------ inspectors */
function inspectorPane() {
  const i = S.inspect;
  if (!i) return h("div", { class: "empty", text: "click a node or a relation" });
  if (i.type === "node") return nodeInspector(i.lid);
  if (i.type === "relation") return relationInspector(i.lid);
  if (i.type === "fact") return factInspector(i.key);
  if (i.type === "location") return recordInspector("source location", W.locByLid.get(i.lid));
  if (i.type === "assertion") return assertionInspector(i.lid);
  return h("div", { class: "empty", text: "nothing selected" });
}

function assertionGroups(assertions) {
  const fams = new Map();
  for (const a of assertions) {
    const f = registryFamily(a.asserted_by);
    if (!fams.has(f)) fams.set(f, []);
    fams.get(f).push(a);
  }
  return [...fams].sort(([a], [b]) => (a < b ? -1 : 1)).map(([fam, list]) =>
    h("div", { class: "asrtgroup" },
      h("div", { class: "hd" },
        h("span", { class: "fam", text: fam }),
        h("span", { class: "faint", text: `${list.length} assertion${list.length === 1 ? "" : "s"}` }),
        h("span", { class: "faint", text: list[0].asserted_by })),
      list.map((a) => h("div", { class: "asrt" },
        kv([
          ["assertion", lidBtn(a.lid)],
          ["precision", h("span", { class: "chip", text: a.precision })],
          ["attrs", a.attrs ? attrsTable(a.attrs) : null],
        ]),
        locationBlock(a.location)))));
}

function locationBlock(loc) {
  if (!loc) return h("div", { class: "loc faint", text: "no location record" });
  if (loc.missing) return h("div", { class: "loc", style: "color:var(--bad)" }, "location record missing: ", h("span", { class: "mono", text: loc.lid }));
  return h("div", { class: "loc" }, kv([
    ["path", h("span", { class: "dim", text: loc.path })],
    ["fragment", loc.fragment ? h("span", { class: "dim", text: loc.fragment }) : h("span", { class: "faint", text: "— (whole file)" })],
    ["pinned_identity", h("span", { class: "id", text: loc.pinned_identity })],
    ["precision", h("span", { class: "chip", text: loc.precision })],
    ["registry", h("span", { class: "faint", text: loc.registry })],
    ["location lid", lidBtn(loc.lid, "loc")],
  ]));
}

function attrsTable(attrs) {
  const rows = Object.entries(attrs).sort(([a], [b]) => (a < b ? -1 : 1));
  if (!rows.length) return h("span", { class: "faint", text: "{}" });
  /* the key column never wraps — a field name broken across three lines is unreadable in a narrow pane — so the
   * table gets its own horizontal scroll rather than the page getting one. */
  return h("div", { class: "scrollx" },
    h("table", { class: "t" }, h("tbody", null, rows.map(([k, v]) =>
      h("tr", null, h("td", { class: "faint k", text: k }), h("td", null, maybeLid(v)))))));
}

function nodeInspector(lid) {
  const ex = W.explain.records[lid];
  const n = W.nodeByLid.get(lid);
  if (!ex || !n) return h("div", { class: "empty", text: "no such node in this world" });
  const outs = (W.out.get(lid) || []), ins = (W.in.get(lid) || []);
  return h("div", { class: "insp" },
    h("h4", { text: "node inspector" }),
    h("div", { class: "body" },
      kv([
        ["lid", h("span", { class: "id", text: n.lid })],
        ["role (kind)", h("span", { class: "chip role", style: `color:${roleColor(n.kind)}`, text: n.kind })],
        ["basis", h("span", { class: "chip", text: n.basis })],
        ["snapshot", h("span", { class: "faint", text: n.snapshot })],
        ["evidence_state", n.evidence_state
          ? h("span", null, h("b", { style: "color:var(--accent-2)", text: n.evidence_state.token }),
              " ", h("span", { class: "faint", text: "vocabulary " }), h("span", { class: "dim", text: n.evidence_state.vocabulary }))
          : null],
        ["semantic attrs", attrsTable(n.attrs || {})],
        ["degree", h("span", null, h("span", { class: "num", text: outs.length }), " out · ", h("span", { class: "num", text: ins.length }), " in")],
      ]),
      h("div", { style: "margin-top:10px" },
        h("div", { class: "hint", style: "margin-bottom:5px" },
          `${ex.assertions.length} assertion${ex.assertions.length === 1 ? "" : "s"}, grouped by the registry namespace that asserted them:`),
        assertionGroups(ex.assertions)),
      h("div", { style: "margin-top:6px" },
        h("div", { class: "hint", style: "margin-bottom:5px", text: "relations touching this node (click one for the statement / revision / allocation panel):" }),
        h("table", { class: "t" },
          h("thead", null, h("tr", null, h("th", { text: "dir" }), h("th", { text: "kind" }), h("th", { text: "other" }), h("th", { text: "statement lid" }))),
          h("tbody", null,
            [...outs.map((r) => ["out", r, r.target]), ...ins.map((r) => ["in", r, r.source])]
              .sort((a, b) => (a[1].lid < b[1].lid ? -1 : 1))
              .map(([dir, r, other]) => h("tr", null,
                h("td", { class: "faint", text: dir }),
                h("td", { class: "dim", text: r.kind }),
                h("td", null, lidShort(other, 34)),
                h("td", null, h("button", { class: "lid rel", text: shortLid(r.lid, 40), title: r.lid, onclick: () => openRelation(r.lid) }))))))),
      derivedAbout(lid)));
}

/* Derived facts that mention this lid — a lookup over the baked facts, not a query. */
function derivedAbout(lid) {
  const hits = W.facts.filter((f) => f.args.includes(lid));
  if (!hits.length) return null;
  return h("div", { style: "margin-top:10px" },
    h("div", { class: "hint", style: "margin-bottom:5px", text: `${hits.length} derived fact(s) mention this lid:` }),
    h("ul", { class: "plain" }, hits.map((f) => h("li", null,
      factExpr([f.rel, ...f.args]), " ",
      h("button", { class: "btn sm", text: "explain", onclick: () => openFact(JSON.stringify([f.rel, ...f.args])) })))));
}

function relationInspector(lid) {
  const r = W.relByLid.get(lid);
  const ex = W.explain.records[lid];
  const w = W.wrl[lid];
  if (!r) return h("div", { class: "empty", text: "no such relation in this world" });
  return h("div", { class: "insp" },
    h("h4", { text: "relation inspector — statement · kind · revision · allocation" }),
    h("div", { class: "body" },
      h("div", { class: "fourrow" },
        h("div", { class: "r statement" },
          h("div", { class: "lbl", text: "1 · statement lid — what was said" }),
          h("div", { class: "val id", text: r.lid }),
          h("div", { class: "why", text: "the projection's own local identifier for this relation record: derived from kind and endpoints, stable across worlds." })),
        h("div", { class: "r kind" },
          h("div", { class: "lbl", text: "2 · relation kind and endpoints" }),
          h("div", { class: "val" }, lidBtn(r.source), " ", h("b", { style: "color:var(--accent-2)", text: "—" + r.kind + "→" }), " ", lidBtn(r.target)),
          h("div", { class: "why", text: "the typed edge itself; attrs live on the assertions below, not here." })),
        h("div", { class: "r rev" },
          h("div", { class: "lbl", text: "3 · WRL rev- — the revision identity" }),
          h("div", { class: "val id rev-id", text: w ? w.rev : "— not minted" }),
          h("div", { class: "why", text: "the kernel's identity for this relation's content. Two worlds that say the same thing share a rev-." })),
        h("div", { class: "r rel" },
          h("div", { class: "lbl", text: "4 · WRL rel- — the world-scoped allocation" }),
          h("div", { class: "val id rel-id", text: w ? w.rel : "— not minted" }),
          h("div", { class: "why", text: w ? `allocated inside this sealed world by ${w.minted_by}; a different world allocates a different rel- for the same rev-.` : "no allocation recorded for this statement." }))),
      h("div", { style: "margin-top:10px" }, kv([
        ["basis", h("span", { class: "chip", text: r.basis })],
        ["snapshot", h("span", { class: "faint", text: r.snapshot })],
        ["relation attrs", attrsTable(r.attrs || {})],
        ["minted_by", w ? h("span", { class: "faint", text: w.minted_by }) : null],
      ])),
      h("div", { style: "margin-top:10px" },
        h("div", { class: "hint", style: "margin-bottom:5px" },
          `${ex.assertions.length} assertion occurrence${ex.assertions.length === 1 ? "" : "s"} — where each registry said it, and at which pinned byte:`),
        assertionGroups(ex.assertions))));
}

function assertionInspector(lid) {
  const a = W.asrtByLid.get(lid);
  return h("div", { class: "insp" },
    h("h4", { text: "assertion" }),
    h("div", { class: "body" },
      kv([
        ["lid", h("span", { class: "id", text: a.lid })],
        ["subject", lidBtn(a.subject)],
        ["asserted_by", h("span", { class: "dim", text: a.asserted_by })],
        ["precision", h("span", { class: "chip", text: a.precision })],
        ["snapshot", h("span", { class: "faint", text: a.snapshot })],
        ["attrs", a.attrs ? attrsTable(a.attrs) : null],
      ]),
      locationBlock(W.locByLid.get(a.location))));
}

function recordInspector(title, rec) {
  if (!rec) return h("div", { class: "empty", text: "no record" });
  return h("div", { class: "insp" },
    h("h4", { text: title }),
    h("div", { class: "body" }, kv(Object.entries(rec).sort(([a], [b]) => (a < b ? -1 : 1)).map(([k, v]) =>
      [k, typeof v === "object" ? attrsTable(v) : k === "lid" ? h("span", { class: "id", text: v }) : maybeLid(v)]))));
}

function factInspector(key) {
  const i = W.factIndex[key];
  const f = i == null ? null : W.facts[i];
  if (!f) return h("div", { class: "empty", text: "no such derived fact in this world" });
  return h("div", { class: "insp" },
    h("h4", { text: "derived fact" }),
    h("div", { class: "body" }, kv([
      ["fact", factExpr([f.rel, ...f.args])],
      ["rule", h("span", { class: "rulepill", text: f.rel })],
      ["basis", h("span", { class: "chip", text: f.basis })],
      ["depth", h("span", { class: "num", text: f.depth })],
      ["evaluator", h("span", { class: "faint", text: f.evaluator })],
      ["trvm_derivation", h("b", { style: "color:var(--warn)", text: String(f.trvm_derivation) })],
      ["key", h("span", { class: "faint", text: f.key })],
      ["inputs", h("div", null, f.inputs.map((x) => h("div", { class: "faint", text: x })))],
      ["snapshot", h("span", { class: "faint", text: f.snapshot })],
      ["derivations", h("span", { class: "num", text: f.derivations.length })],
    ])));
}

/* ------------------------------------------------------------------ explain panel */
function renderExplain() {
  const box = clear($("explain"));
  const e = S.explain;
  if (!e) { box.append(h("div", { class: "empty", text: "select a node, a relation or a derived fact" })); return; }
  const tree = e.kind === "fact" ? W.explain.facts[e.key] : W.explain.records[e.key];
  if (!tree) { box.append(h("div", { class: "empty", text: "no explanation stored for this lid" })); return; }
  box.append(h("div", { class: "body" }, explainRoot(tree)));
}

function explainRoot(t) {
  if (t.fact) return explainFact(t);
  return explainRecord(t);
}

/* explain(lid) — an observed record with the assertions and pinned locations that carry it. */
function explainRecord(t) {
  const head = h("div", null,
    h("div", { style: "margin-bottom:7px" },
      h("span", { class: "badge " + (t.basis === "observed" ? "observed" : t.basis) , text: t.basis }), " ",
      h("span", { class: "id", text: t.subject })),
    t.kind ? kv([["kind", h("span", { class: "chip", text: t.kind })]]) : null,
    t.source ? kv([["endpoints", h("span", null, lidShort(t.source, 30), " → ", lidShort(t.target, 30))]]) : null,
    t.evidence_state ? kv([["evidence_state", h("span", null, h("b", { style: "color:var(--accent-2)", text: t.evidence_state.token }), " ", h("span", { class: "faint", text: t.evidence_state.vocabulary }))]]) : null,
    t.attrs ? h("details", { open: true }, h("summary", { class: "faint", text: "attrs" }), attrsTable(t.attrs)) : null,
    t.record ? h("details", { open: true }, h("summary", { class: "faint", text: "record" }), attrsTable(t.record)) : null,
    t.location ? h("div", null, h("div", { class: "faint", style: "margin-top:6px", text: "location" }), locationBlock(t.location)) : null);
  if (!t.assertions) return head;
  return h("div", null, head,
    h("div", { class: "hint", style: "margin:8px 0 4px" }, "this record is carried by ", h("b", { text: String(t.assertions.length) }), " assertion(s); each names a registry and a pinned byte:"),
    assertionGroups(t.assertions));
}

/* explain([rel, ...args]) — the derivation tree, exactly as Graph.explain returned it. Nothing is unfolded here. */
function explainFact(t) {
  return h("div", null,
    h("div", { class: "trvm" },
      h("span", { class: "badge derived", text: "derived" }),
      factExpr(t.fact),
      h("span", { class: "faint", text: "depth " }), h("span", { class: "num", text: t.depth }),
      h("span", { class: "faint", text: "evaluator " }), h("span", { class: "dim", text: t.evaluator }),
      h("span", null, h("span", { class: "faint", text: "trvm_derivation " }), h("b", { text: String(t.trvm_derivation) }))),
    h("div", { class: "hint", style: "margin-bottom:6px" },
      t.derivations.length === 1 ? "one stored derivation:" : `${t.derivations.length} stored derivations:`),
    t.derivations.map((d, i) => derivationNode(d, i, 0)));
}

function derivationNode(d, i, level) {
  const det = h("details", { open: level < 2 });
  det.append(h("summary", null,
    h("span", { class: "badge derived", text: "derived" }),
    rulePill(d.rule),
    h("span", { class: "faint", text: "depth" }), h("span", { class: "num", text: d.depth }),
    d.conclusion ? h("span", null, "⊢ ", factExpr(d.conclusion)) : null));
  const body = h("div", null);
  if (d.bindings && Object.keys(d.bindings).length) {
    body.append(h("details", null, h("summary", { class: "faint", text: "bindings" }), attrsTable(d.bindings)));
  }
  body.append(h("div", { class: "hint", style: "margin:4px 0 2px", text: "premises:" }));
  for (const p of d.premises || []) body.append(premiseNode(p, level + 1));
  det.append(body);
  return h("div", { class: "exnode" }, det);
}

/* A rule id is `<ruleset sem id>#<name>`. The name is what a reader needs; the ruleset is 71 characters of hash that
 * is identical on every line. Show the name, shorten the ruleset, keep the whole thing on the element's title. */
function rulePill(rule) {
  const i = String(rule).indexOf("#");
  const name = i < 0 ? String(rule) : String(rule).slice(i);
  const set = i < 0 ? "" : String(rule).slice(0, i);
  return h("span", { class: "rulepill", title: rule }, name, set ? h("span", { class: "faint", text: " " + shortRoot(set, 8) }) : null);
}

function premiseNode(p, level) {
  if (p.basis === "absent") {
    return h("div", { class: "exnode" },
      h("div", { class: "absentbox" },
        h("div", null, h("span", { class: "badge absent", text: "absent" }), " ", h("span", { class: "t" }, factExpr(p.absent))),
        h("div", { class: "faint", style: "margin-top:3px" },
          "what is absent: no fact ", h("b", { text: p.absent[0] }), " over ",
          p.absent.slice(1).map((a, i) => [i ? ", " : "", h("span", { class: "mono", text: scalar(a) })]),
          " exists in this evaluation. The premise is satisfied by that absence.")));
  }
  if (p.basis === "derived" && p.elided) {
    return h("div", { class: "exnode" },
      h("div", { class: "leaf" },
        h("span", { class: "badge elided", text: "elided" }), " ", factExpr(p.fact), " ",
        h("span", { class: "faint", text: "already unfolded above (cycle or depth budget)" }), " ",
        factButton(p.fact)));
  }
  if (p.basis === "derived") {
    const det = h("details", { open: level < 2 });
    det.append(h("summary", null,
      h("span", { class: "badge derived", text: "derived" }), factExpr(p.fact), " ",
      h("span", { class: "faint", text: "via" }), rulePill(p.rule),
      h("span", { class: "faint", text: "depth" }), h("span", { class: "num", text: p.depth }),
      factButton(p.fact)));
    const body = h("div", null);
    if (p.bindings && Object.keys(p.bindings).length) body.append(h("details", null, h("summary", { class: "faint", text: "bindings" }), attrsTable(p.bindings)));
    body.append(h("div", { class: "hint", style: "margin:4px 0 2px", text: "premises:" }));
    for (const q of p.premises || []) body.append(premiseNode(q, level + 1));
    det.append(body);
    return h("div", { class: "exnode" }, det);
  }
  /* base */
  const det = h("details", { open: level < 2 });
  det.append(h("summary", null, h("span", { class: "badge base", text: "base" }), factExpr(p.fact)));
  det.append(baseSource(p.source));
  return h("div", { class: "exnode" }, det);
}

/* the page's only use of factIndex: jump from a premise to that premise's own fact record, by lookup. */
function factButton(fact) {
  const key = JSON.stringify(fact);
  if (!(key in W.factIndex)) return null;
  return h("button", { class: "btn sm", text: "open", onclick: () => openFact(key) });
}

function baseSource(src) {
  if (!src) return h("div", { class: "leaf faint", text: "no source recorded" });
  if (src.missing) return h("div", { class: "leaf", style: "color:var(--bad)" }, "record not in this projection: ", h("span", { class: "mono", text: src.lid }));
  if (src.basis === "assertion") {
    return h("div", { class: "leaf" },
      kv([
        ["assertion", lidBtn(src.lid)],
        ["asserted_by", h("span", { class: "dim", text: src.asserted_by })],
        ["attrs", src.attrs ? attrsTable(src.attrs) : null],
      ]),
      locationBlock(src.location));
  }
  return h("div", { class: "leaf" },
    kv([
      ["record", lidBtn(src.lid)],
      ["kind", h("span", { class: "chip", text: src.kind })],
      ["basis", h("span", { class: "badge observed", text: src.basis })],
    ]),
    h("details", { open: true },
      h("summary", { class: "faint", text: `${(src.assertions || []).length} assertion(s) and their pinned locations` }),
      assertionGroups(src.assertions || [])));
}

/* ------------------------------------------------------------------ faults */
function faultsPane() {
  const byCode = new Map();
  for (const f of W.faults) {
    if (!byCode.has(f.code)) byCode.set(f.code, []);
    byCode.get(f.code).push(f);
  }
  const wrap = h("div", null,
    h("div", { class: "graphbar" },
      h("span", { class: "faint", text: `${W.faults.length} faults in ${byCode.size} codes · recorded by the projection, not by this page` }),
      Object.entries(W.counts.fault_codes).map(([c, n]) => h("span", { class: "chip", text: `${c} ${n}` }))));
  for (const [code, list] of [...byCode].sort(([a], [b]) => (a < b ? -1 : 1))) {
    wrap.append(h("div", { class: "faultcode" },
      h("div", { class: "hd" }, h("span", { class: "c", text: code }), h("span", { class: "faint", text: `${list.length} fault${list.length === 1 ? "" : "s"}` })),
      list.map((f) => h("div", { class: "fault", style: S.faultHighlight === f.lid ? "background:#1d2530" : null },
        h("div", { class: "msg", text: f.message }),
        h("div", { class: "meta" }, "rule ", h("span", { class: "dim", text: f.rule }), " · ", h("span", { class: "mono", text: f.lid })),
        h("div", { style: "margin-top:3px" },
          h("span", { class: "faint", text: "concerns: " }),
          f.concerns.length ? f.concerns.map((c, i) => [i ? " · " : "", W.anyLid.has(c) ? lidBtn(c) : h("span", { class: "dim", text: c })]) : h("span", { class: "faint", text: "—" }))))));
  }
  return wrap;
}

/* ------------------------------------------------------------------ A1–A7 */
function acceptancePane() {
  const A = W.acceptance;
  const wrap = h("div", null,
    h("div", { class: "graphbar" },
      h("span", { class: "faint", text: "answers computed by lib/acceptance.mjs in Node, over " }),
      h("span", { class: "id", text: W.identity.snapshot }),
      A.compare ? h("span", { class: "faint", text: " · compare pin " }) : null,
      A.compare ? h("span", { class: "id", text: A.compare.snapshot }) : null),
    h("div", { class: "hint", style: "padding:6px 12px" , text: A.compare_note }));
  for (const q of A.questions) wrap.append(questionCard(q));
  return wrap;
}

function questionCard(q) {
  const card = h("div", { class: "q" + (q.answered ? "" : " refused") },
    h("div", { class: "hd" },
      h("div", null, h("span", { class: "id", text: q.id }), " ", h("span", { class: "ttl", text: q.title })),
      h("div", { class: "question", text: q.question }),
      h("div", { class: "proves" }, "proves: ", q.proves),
      q.answered ? h("div", { class: "scope", text: `answered at ${q.snapshot}${q.compare ? " · compared against " + q.compare : ""}` }) : null));
  if (!q.answered) {
    card.append(h("div", { class: "reason" }, h("b", { text: "not answered: " }), q.reason));
    return card;
  }
  for (const st of q.steps) {
    card.append(h("div", { class: "step" },
      h("div", { class: "lbl", text: st.label }),
      h("div", null, h("code", { class: "call", text: st.call })),
      h("div", { class: "val" }, stepValue(st))));
  }
  return card;
}

function stepValue(st) {
  const v = st.value;
  if (v == null) return h("span", { class: "faint", text: "null — nothing to show" });
  switch (st.kind) {
    case "lids":
      return v.length
        ? h("ul", { class: "plain" }, v.map((l) => h("li", null, lidBtn(l))))
        : h("span", { class: "faint", text: "empty" });
    case "facts":
      return v.length
        ? h("ul", { class: "plain" }, v.map((f) => h("li", null,
            factExpr([f.rel, ...f.args]), " ",
            h("span", { class: "faint", text: `depth ${f.depth}` }), " ",
            h("button", { class: "btn sm", text: "explain", onclick: () => openFact(JSON.stringify([f.rel, ...f.args])) }))))
        : h("span", { class: "faint", text: "empty — no fact of this rule was derived" });
    case "explain":
      return h("div", { style: "border:1px solid var(--line);border-radius:3px;padding:8px" }, explainRoot(v));
    case "record":
      return attrsTable(v);
    case "locations":
      return v.length ? h("div", null, v.map((row) => h("div", { style: "margin-bottom:6px" },
        kv(Object.entries(row).filter(([k]) => k !== "location").map(([k, x]) => [k, maybeLid(x)])),
        locationBlock(row.location)))) : h("span", { class: "faint", text: "empty" });
    case "edges":
      return h("table", { class: "t" },
        h("thead", null, h("tr", null, h("th", { text: "kind" }), h("th", { text: "other" }), h("th", { text: "relation" }))),
        h("tbody", null, v.map((e) => h("tr", null,
          h("td", { class: "dim", text: e.kind }),
          h("td", null, lidShort(e.other, 40)),
          h("td", null, h("button", { class: "lid rel", text: shortLid(e.relation, 44), title: e.relation, onclick: () => openRelation(e.relation) }))))));
    case "counts":
      return h("table", { class: "t" }, h("tbody", null, Object.entries(v).map(([k, n]) =>
        h("tr", null, h("td", { class: "faint", text: k }), h("td", { class: "num", text: String(n) })))));
    case "absences":
      return v.length ? h("div", null, v.map((a) => h("div", { class: "absentbox" },
        h("span", { class: "badge absent", text: "absent" }), " ", factExpr(a)))) : h("span", { class: "faint", text: "no absences in this tree" });
    case "verdict":
      return h("div", { class: "verdict" + (String(v).startsWith("NOT HELD") ? " no" : ""), text: String(v) });
    default:
      return h("pre", { class: "faint", text: JSON.stringify(v, null, 1) });
  }
}

/* ------------------------------------------------------------------ search */
function renderSearch() {
  const out = clear($("searchOut"));
  const q = S.search.trim().toLowerCase();
  if (!q) return;
  const hits = W.searchable.filter((r) => r.lid.toLowerCase().includes(q)).slice(0, 50);
  const factHits = W.factKeys.filter((k) => k.toLowerCase().includes(q)).slice(0, 15);
  if (!hits.length && !factHits.length) { out.append(h("div", { class: "faint", text: "no lid matches" })); return; }
  for (const r of hits) out.append(h("div", { class: "row" }, h("span", { class: "chip", text: r.type }), " ", lidShort(r.lid, 34)));
  for (const k of factHits) {
    const f = W.facts[W.factIndex[k]];
    out.append(h("div", { class: "row" },
      h("span", { class: "chip", text: "fact" }), " ",
      h("button", { class: "lid", title: k, onclick: () => openFact(k) },
        h("span", { class: "rulepill", text: f.rel }), "(", f.args.map((a, i) => [i ? ", " : "", shortLid(scalar(a), 26)]), ")")));
  }
  const more = W.searchable.filter((r) => r.lid.toLowerCase().includes(q)).length - hits.length;
  if (more > 0) out.append(h("div", { class: "faint", text: `+${more} more not listed` }));
}

/* ------------------------------------------------------------------ wiring */
for (const b of document.querySelectorAll("#tabs button")) {
  b.addEventListener("click", () => { S.view = b.dataset.view; renderView(); });
}
$("search").addEventListener("input", (e) => { S.search = e.target.value; renderSearch(); });
for (const b of document.querySelectorAll("[data-all]")) {
  b.addEventListener("click", () => {
    if (b.dataset.all === "roles") S.roles = new Set(W.roleOrder);
    else S.kinds = new Set(Object.keys(W.counts.relation_kinds));
    renderFilters(); renderView();
  });
}
for (const b of document.querySelectorAll("[data-none]")) {
  b.addEventListener("click", () => {
    if (b.dataset.none === "roles") S.roles = new Set();
    else S.kinds = new Set();
    renderFilters(); renderView();
  });
}

boot().catch((err) => {
  document.getElementById("view").replaceChildren(h("div", { class: "empty", text: "could not load ui/data: " + err.message }));
});
