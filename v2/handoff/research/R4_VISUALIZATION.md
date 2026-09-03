# R4 — Visualising the G0.5 provenance/evidence graph in a static, bundler-free page

Researched 2026-09-02. Every version, size and CDN URL was checked against the npm registry, cdnjs/jsDelivr (HTTP 200 + downloaded bytes) or run on this box today; qualitative claims cite their source. "Adopt" = recommended for G0.5; "reference pattern" = borrow the idea, not the code. One gap is flagged: the GSN v3 PDF sits behind an HTML download gate.

## Executive summary

- **Adopt Cytoscape.js 3.34.2** (MIT, released 2026-08-25) as a plain ES module from cdnjs (`cytoscape.esm.min.mjs`, 434 KB raw / 136 KB gzip). It alone offers compound nodes (subsystem grouping), per-class edge styling (`line-style: solid|dashed|dotted`, arrow shapes), a selector/filter model and a layout-extension API. The bundler-free path (cdnjs ESM + jsDelivr `+esm` for fcose + `.mjs` for dagre) was verified executing in Chrome.
- **Layout, not rendering, is the constraint.** Measured headless: at 500 nodes/1,500 edges every engine finishes under 3 s; at 2,000/10,000 Graphviz `dot` (WASM) takes 8.8–13.7 s, ELK layered 12.3 s, fcose 58.6 s, and dagre (`@dagrejs/dagre` 3.1.1 and cytoscape-dagre 4.0.1) did **not finish inside 240 s**. Use dagre for sub-graphs (≲ 500 nodes) and expansions; `dot` or ELK for whole-graph layered views, behind a cache.
- **Deterministic layered layout is available:** `dot` and ELK layered reproduced identical output on rerun; dagre reproduces itself but changes with node insertion order (verified). fcose/cose have **no seed** (issues open since 2019/2021) and rerun differently (verified).
- **Graphviz-in-WASM is a viable minimal path and the right fallback/export:** `@viz-js/viz` 3.30.0 (MIT, 2026-09-01, Graphviz 16.0.0) is one 1.18 MB / 467 KB-gzip ES module with the WASM inlined; SVG output carries `id`/`class`/`href`; `svg-pan-zoom` 3.6.2 (8 KB gzip) panned a 46,004-element SVG at frame rate. But at 2k/10k the SVG is 4.8 MB and layout is 13.7 s in-browser.
- **Sigma.js v3 + graphology** is the WebGL escalation past ~5k nodes: no compound nodes, no SVG export, dashed edges need a custom shader.
- **Borrow conventions from prior art:** GSN (shape per argument role, hollow vs solid arrowhead per relation, hollow diamond = undeveloped), SEI confidence maps (defeaters as chopped-corner boxes labelled "Unless…", inference rules as nodes), PROV-O shapes, GUAC's click-to-fetch-neighbours.
- **Never colour alone** (WCAG 1.4.1, Level A): stroke style for provenance class (solid imported, dashed derived, dotted proposed), node shape per entity kind, text badges for status, ≥ 3:1 stroke contrast (1.4.11).
- **Persist no coordinates in the projection.** Cache layouts keyed by `sha256(projection) + engine + version + options`; reload via Cytoscape `preset`.

## 1. Cytoscape.js

**State (npm, 2026-09-02):** `cytoscape` 3.34.2, MIT, 2026-08-25; `exports` ships `dist/cytoscape.esm.min.mjs` and `cytoscape.min.js`; cdnjs hosts both at 3.34.2. Docs: https://js.cytoscape.org/.

**Extensions (all MIT unless noted):**

| Extension | Version / date | Loads as | Notes |
|---|---|---|---|
| cytoscape-dagre | 4.0.1 / 2026-08-28 | self-contained `dist/cytoscape-dagre.mjs` (56 KB / 19 KB gz), dagre v3 bundled | README: `sort` exists because "directed graphs use the node order as a tie breaker". Compounds not documented. |
| cytoscape-fcose | 2.2.0 / 2023-01-17 | UMD needs `layout-base` + `cose-base` script tags; jsDelivr `+esm` pulls `cose-base@2.2.0/+esm` (verified in Chrome) | Compound-aware, fixed/alignment/relative constraints, spectral + incremental. No seed (issue #36, open since 2021). |
| cytoscape-cose-bilkent | 4.1.0 / 2019-09-09 | UMD + `cose-base` 1.x | Superseded by fcose; clashes with fcose's cose-base 2.x via script tags. |
| cytoscape-elk | 2.3.0 / 2024-11-26 | UMD requiring `elkjs/lib/elk.bundled.js` (1.61 MB / 467 KB gz) | All ELK algorithms/options (`elk.direction`…). |
| cytoscape-klay | 3.1.4 / 2020-10-07 | UMD + klayjs 0.4.1 (2016) | README: "KLayJS is deprecated upstream in favour of elkjs". Skip. |
| cytoscape-expand-collapse | 4.1.1 / 2024-08-28 | UMD | Collapses compound parents. |
| cytoscape-svg | 0.4.0 | UMD | **GPL-3.0** — do not adopt. |

**Compound nodes.** `parent` field; "A compound parent node does not have independent dimensions… inferred by the positions and dimensions of the descendant nodes"; traversal functions "do not make special allowances for compound nodes" (notation docs); only `*rectangle` shapes for compounds (style docs); "Compound nodes make style calculations and rendering more expensive" (performance docs). Compound-capable layouts: built-in `cose` ("additional logic to support compound graphs well"), fcose, cose-bilkent, ELK with hierarchy handling ("full layout of compound graphs with cross-hierarchy edges is supported when the respective option is activated").

**Edge styling per relation class.** `line-style: solid|dotted|dashed`, `line-dash-pattern` (`[6,3]`), `curve-style: haystack` (default, fastest, no arrows) `| straight | bezier | unbundled-bezier | segments | taxi | round-taxi`, `<pos>-arrow-shape`, node `border-style: solid|dotted|dashed|double`, `display:none` vs `visibility:hidden` for filtering. Performance docs: "Dotted and dashed edges are much more expensive to draw"; arrows are expensive. Measured: restyling 1,500 edges to straight-with-arrows cost 113 ms (666 ms for 10,000) with pan frames staying at cadence for 1,500 edges.

**Performance.** The maintainers' test page ships 200–20,000-node datasets (https://cytoscape.org/js-perf/); `hideEdgesOnViewport`/`textureOnViewport` are "now largely moot" and matter "on only very, very large graphs". Measured today, headless Chrome, DPR 1: **500/1,500** — import 414 ms, first render 192 ms, pan/zoom at frame cadence (p90 50 ms), `closedNeighborhood()` + fade-rest 88 ms, dagre 1,364 ms, fcose 564 ms. **2,000/10,000** (preset positions) — first render 667 ms, zoom at cadence, pan median at cadence but p90 339 ms (visible hitches), neighbourhood fade 405 ms. So 2k/10k renders, but smooth interaction needs the cheap style and a working-set filter.

**Selection/inspection.** Events `tap`, `dbltap`, `cxttap`, `boxselect`, `mouseover`; collection events `select`/`unselect`/`add`/`remove`/`data`/`position`. Traversal for the panel: `closedNeighborhood()`, `successors()`/`predecessors()` (support and dependency chains), `bfs()`; `cy.$id()` is the fast lookup.

**Expand + filter idioms.** Keep the whole projection in memory, show a working set. The maintainers' layout post: `eles.layout()` lays out a subset, and the Wine & Cheese demo applies "a concentric layout only to neighbourhood of the tapped node, while the rest of the graph remains the same". GUAC's visualizer does it remotely: `useGraphData.ts` calls `fetchNeighbors(id)` on click and merges. Filtering: toggle classes → `display:none` inside `cy.batch()`, or `remove()`/`restore()`.

**ESM/no-bundler issues.** fcose and cose-bilkent are UMD-only (use `+esm` or three script tags); cytoscape-elk needs `elk.bundled.js` first; issue #3416 (Sept 2025, "3.33.1 doesn't work with fcose") is a `@types/cytoscape` mismatch — TypeScript-only. Accessibility: canvas has no per-node DOM; keyboard support "needs to be built at the app level" (discussion #3125; issue #2397). Plan a DOM list mirror of the working set with `aria-selected`, arrow keys calling `cy.center()` + `select()`, visible focus.

## 2. Graphviz in the browser

- **@viz-js/viz 3.30.0** (MIT, 2026-09-01): "builds Graphviz with Emscripten"; changelog "Update Graphviz to 16.0.0" (confirmed via `viz.graphvizVersion`). Single ES module `dist/viz.js`, 1,184,246 bytes / 467 KB gzip, WASM inlined (SINGLE_FILE) — no second fetch. `await Viz.instance()` (15 ms after import) then synchronous `renderString`/`renderSVGElement`/`renderJSON`/`renderFormats` with `engine`, `format`, default-attribute options (https://viz-js.com/api/). cdnjs only has viz.js **2.1.2**; use jsDelivr.
- **@hpcc-js/wasm-graphviz 1.28.0** (Apache-2.0, 2026-07-24): `Graphviz.load()` → `layout(dot,"svg","dot")`, `.dot()`, plus a programmatic `createGraph()`. Runtime `version()` = **15.1.0**. `dist/index.js` 821 KB but 636 KB gzip (WASM inlined as zstd-compressed text); the `.wasm` URL 404s.
- **d3-graphviz 5.6.0** (BSD-3, 2024-08-18): hpcc WASM + animated d3 transitions between graphs; 583 KB gz plus d3. Reference pattern only.
- **svg-pan-zoom 3.6.2** (BSD-2, 2024-10-20; jsDelivr only): "mouse scroll, double-click and pan… inline SVGs and SVGs in object/embed"; 8 KB gz.
- **Layered quality:** `dot` is the reference layered algorithm, deterministic (rerun-identical), honours `ordering=out|in` ("must appear left-to-right in the same order in which they are defined in the input"). Timings: 500/1,500 → 399 ms (viz) / 289 ms (hpcc); 2,000/10,000 → 11.4 s (viz, Node), 13.7 s (viz, Chrome), 8.8 s (hpcc); SVG 4.8 MB, 46,004 elements, injected in 131 ms; svg-pan-zoom pan/zoom stayed at frame cadence.
- **Interactivity limits:** static SVG. Graphviz emits `id`, `class`, `href/URL`, `tooltip`, `target` and `-Tsvg_inline` (since 10.0.1), so deep links and delegated click handlers are trivial, but expand/collapse, incremental relayout and hit-testing are yours. Verdict: viable minimal path and the export format; weak as the interactive primary at the upper bound.

## 3. Comparison table

Sizes = today's bytes, gzip -9. "Comfortable size" mixes vendor statements and my measurements.

| Library (version, date) | Rendering | Comfortable size | Layouts | ESM/CDN without bundler | Size (gz) | License | Maintenance |
|---|---|---|---|---|---|---|---|
| Cytoscape.js 3.34.2 (2026-08-25) | Canvas 2D | maintainers test to 20k nodes; 2k/10k renders, layout limits | built-ins + dagre/fcose/elk/cola ext. | cdnjs ESM; extensions via jsDelivr `+esm` — verified | 136 KB (+19 dagre, +7.5 fcose, +467 elk) | MIT | active |
| Sigma.js 3.0.3 + graphology 0.26.0 (2026-04-30 / 2025-01-26) | WebGL, labels on canvas | "thousands of nodes and edges"; v4 alpha | graphology FA2, noverlap, circular/random | jsDelivr `+esm` (resolves `graphology-utils`) — verified | 47 + 14 KB | MIT | active |
| d3-force 3.0.0 / d3 7.9.0 | you render (SVG/canvas) | SVG DOM to low thousands; canvas higher | force (static via `tick(300)`) | `import * as d3 from ".../d3@7/+esm"` is the docs' recommendation | 3 / 92 KB | ISC | stable |
| ELK (elkjs 0.12.0, 2026-07-17) | layout only | 2k/10k layered 12.3 s | layered, stress, mrtree, radial, force, disco | `elk.bundled.js` or `elk-api.js` + worker; jsDelivr only | 467 KB | EPL-2.0 OR GPL-3.0-or-later | active |
| dagre (@dagrejs 3.1.1, 2026-08-08) | layout only | 2 s at 500/1,500; > 240 s at 2k/10k | layered | `dist/dagre.esm.js` | 17 KB | MIT | active |
| Graphviz WASM (@viz-js/viz 3.30.0) | SVG/JSON output | 2k/10k ≈ 11–14 s, 4.8 MB SVG | dot, neato, fdp, sfdp, circo, twopi, osage, patchwork | single ES module, jsDelivr | 467 KB | MIT | very active |
| vis-network 10.1.2 (2026-08-19) | Canvas 2D | "up to a few thousand nodes and edges", clustering beyond | physics, hierarchical; `randomSeed` | `standalone/esm/vis-network.min.js` | 155 KB | Apache-2.0 OR MIT | active |
| AntV G6 5.1.1 (2026-05-08) | Canvas; SVG/WebGL via `renderer` | large (WebGL) | dagre, force, d3-force, fruchterman, radial, concentric, grid, combo | `dist/g6.min.js` UMD; ESM is multi-file | 391 KB | MIT | active |

Headless caveat: Sigma's pan/zoom measured 466–711 ms per step under headless Chrome's software WebGL — not representative of a GPU; its first render (136 ms) and reducer highlight (38 ms) are.

## 4. Prior art worth borrowing

- **W3C PROV.** PROV-O's informative convention: "Entities as yellow ovals, Activities as blue rectangles, and Agents as orange pentagons" (§3.1) — map RECEIPT/EXPERIMENT to entity-like, MECHANISM to activity-like, ADJUDICATION to agent-like shapes. ProvStore's hive/wheel/Gantt/Sankey and PROV-O-Viz's Sankey suit flow views, not claim graphs. **Prov Viewer** (Kohwalter et al., IPAW 2016; Java/JUNG, MIT) is the nearest graph tool; its wiki is organised around our needs — "Graph Layouts", "Collapses and Filters", "Attribute Status / Color Schemes".
- **Supply chain.** GUAC's visualizer ("experimental… visualize the software supply chain graph… prototype policies", Apache-2.0): Next.js with `react-force-graph-2d`/`3d-force-graph` (`react-cytoscapejs` also in dependencies); search a node, click to fetch neighbours, JSON inspector per node. Reference pattern for the expand loop.
- **Package graphs.** `nix-tree` (TUI, `--dot`), `nix-visualize` (layered so "all packages are above everything that they depend upon"), `guix graph` (`graphviz` and `d3js` backends), dependency-cruiser (`-T dot | dot -Tsvg | depcruise-wrap-stream-in-html` → hover-highlighting SVG), madge (Graphviz for images). Everyone ends at `dot` plus hover highlight.
- **Assurance cases.** GSN (SCSC-141C v3, 2021, SCSC Assurance Case Working Group): Goal, Strategy, Solution, Context, Assumption, Justification; SupportedBy and InContextOf; Undeveloped marker; v3's Dialectic extension adds defeaters — "any goal or solution that challenges an element or a relation… expression of doubt (inDoubt)… and… defeat (defeated)" (OntoGSN, arXiv 2506.11023), rebutting and undercutting. The shape catalogue (goal rectangle, strategy parallelogram, solution circle, context rounded rectangle, A/J ellipses, hollow-diamond undeveloped, solid vs hollow arrowheads) is the standard's; only "Claims are enclosed in rectangles, evidence in a circle" could be cross-checked (SEI TR-005) — verify against the PDF before publishing. **SEI confidence maps** (CMU/SEI-2015-TR-005) are the template for FALSIFIER: "claims and evidence are represented with uncolored graphical elements (rectangles and rectangles with rounded corners…). Defeaters are expressed in rectangles with chopped-off corners… red for rebutting… yellow for undermining… orange for undercutting. Inference rules are specified in green rectangles"; a rebutting defeater "appears… as 'Unless P'". **Assurance 2.0** (Bloomfield & Rushby) separates exact defeaters (claim is the negation of the target) from exploratory ones and names accepted-unresolved ones "residual doubts". Tools: ASCE 5.1 ("full support for GSN v3… defeater and comments management"), NASA AdvoCATE (patterns, hierarchical abstraction, queries and views). Borrow: one shape per role; relation kind in the connector; explicit undeveloped/in-doubt/defeated markers; "Unless…" phrasing for falsifiers.

## 5. Provenance class and status without colour alone

WCAG 2.2 SC 1.4.1 (A): "Color is not used as the only visual means of conveying information, indicating an action, prompting a response, or distinguishing a visual element." G111 ("Using color and pattern") shows a flow chart with "dashed, arrowed lines… for passing conditions and dotted arrowed lines… for failing conditions"; G14/G182/G183 add text, extra cues and 3:1. SC 1.4.11 (AA) requires 3:1 for graphical objects — "the lines in the graph… and the colored lines with shapes" — and visible focus.

Scheme (expressible in Cytoscape style and Graphviz `style=`): **provenance class by stroke** — imported/authoritative solid 2 px, derived dashed `[6,3]`, candidate dotted 1 px at reduced opacity; **entity kind by node shape** (rectangle CLAIM, parallelogram MECHANISM, circle RECEIPT, chopped-corner/diamond FALSIFIER, rounded rectangle LAW/OBLIGATION, hexagon ADJUDICATION) plus a two-letter badge; **status by badge and border** (`border-style: double` closed/adjudicated, hollow-diamond marker for open obligations, "✕" badge for superseded); **relation kind by arrowhead** (filled triangle SUPPORTS/IMPLEMENTS, hollow triangle SCOPED_BY, tee FALSIFIES, diamond SUPERSEDES) with the name on hover. Colour only reinforces; derive it from CSS variables per theme.

## 6. Deterministic layouts and persistence

Measured (same input twice; SHA-256 of rounded positions):

| Engine | Randomness | Seed | Rerun identical | Notes |
|---|---|---|---|---|
| Graphviz dot | none; `start` applies to neato/fdp/sfdp where "the same seed is always used… so the initial placement is repeatable" | `start=N` (force engines) | yes | `ordering=out` pins edge order |
| ELK layered | seeded; `randomSeed` default 1, "If the value is 0, the seed shall be determined pseudo-randomly" | yes | yes | `considerModelOrder.strategy` keeps input order when crossing-free; `interactive` "modif[ies] the current layout as little as possible" |
| dagre | no `Math.random` | n/a | yes, **but reversed insertion → different layout** | canonically sort nodes/edges first |
| fcose / cose | `Math.random` in spectral sampling, initial coordinates, tiling | none (issues #36, #94 open) | **no** | `randomize:false` = incremental, not reproducible |
| ForceAtlas2 | none in FA2; needs initial x/y | `random` layout takes `rng`; `circular` deterministic | yes | `noverlap` adds 0.01 jitter |
| d3-force 3 | "fixed-seed linear congruential generator"; phyllotaxis start is "deterministic" | `randomSource()` | yes | static via `tick(300)` |
| vis-network | seeded | `layout.randomSeed`, `getSeed()` | not measured | hierarchical is order-based |

Persist an optional **layout cache**, never coordinates in the projection: key `sha256(canonical projection JSON) + engine + version + option hash`, value `{id:[x,y]}`, consumed by Cytoscape `preset`, Graphviz `pos`/`neato -n`, or ELK `interactive`. Digest mismatch → recompute; ship the cache as a sibling file the page can live without.

## Recommendation for G0.5

**Primary (adopt):** Cytoscape.js 3.34.2 (cdnjs ESM) + cytoscape-dagre 4.0.1 for neighbourhood/sub-graph layered views + fcose 2.2.0 for the overview when layering is not required; compound nodes for subsystem; §5 style classes; DOM side panel bound to `select`/`unselect`; `closedNeighborhood()`/`successors()`/`predecessors()` for expand; `cy.batch()` + `display:none` filters; a DOM list mirror for keyboard access. Whole-graph deterministic layering at the upper bound: **ELK layered** (`+esm`, `randomSeed` fixed, `considerModelOrder` on) in a Worker or offline, loaded through `preset` from the cache. Export: write your own SVG from `cy.nodes().positions()` (not the GPL `cytoscape-svg`); `cy.png()` is built in.

**Fallback (deterministic layered, minimal code):** `@viz-js/viz` 3.30.0 → `renderSVGElement` with `id`/`class`/`href` → inject → `svg-pan-zoom` 3.6.2; delegated click handlers. Also the printable artefact and the regression-diff reference (dot output is stable).

**Escalation (> ~5k nodes):** Sigma 3.0.3 + graphology 0.26.0 via `+esm`, FA2 from `circular` init, reducers for filter/highlight — losing compounds and native dashes.

Verified URLs (HTTP 200, 2026-09-02):

```
https://cdnjs.cloudflare.com/ajax/libs/cytoscape/3.34.2/cytoscape.esm.min.mjs
https://cdnjs.cloudflare.com/ajax/libs/cytoscape/3.34.2/cytoscape.min.js
https://cdn.jsdelivr.net/npm/cytoscape-dagre@4.0.1/dist/cytoscape-dagre.mjs
https://cdn.jsdelivr.net/npm/cytoscape-fcose@2.2.0/+esm        (pulls /npm/cose-base@2.2.0/+esm)
https://cdn.jsdelivr.net/npm/cytoscape-fcose@2.2.0/cytoscape-fcose.js   (UMD; needs layout-base + cose-base)
https://cdn.jsdelivr.net/npm/cytoscape-elk@2.3.0/+esm   https://cdn.jsdelivr.net/npm/elkjs@0.12.0/lib/elk.bundled.js
https://cdn.jsdelivr.net/npm/elkjs@0.12.0/lib/elk-api.js   https://cdn.jsdelivr.net/npm/elkjs@0.12.0/lib/elk-worker.min.js
https://cdn.jsdelivr.net/npm/@dagrejs/dagre@3.1.1/dist/dagre.esm.js
https://cdn.jsdelivr.net/npm/@viz-js/viz@3.30.0/dist/viz.js
https://cdn.jsdelivr.net/npm/@hpcc-js/wasm-graphviz@1.28.0/dist/index.js
https://cdn.jsdelivr.net/npm/svg-pan-zoom@3.6.2/dist/svg-pan-zoom.min.js
https://cdn.jsdelivr.net/npm/sigma@3.0.3/+esm   https://cdn.jsdelivr.net/npm/graphology@0.26.0/+esm
https://cdn.jsdelivr.net/npm/graphology-layout-forceatlas2@0.10.1/+esm
https://cdn.jsdelivr.net/npm/d3@7.9.0/+esm   https://cdn.jsdelivr.net/npm/d3-force@3.0.0/+esm
https://cdn.jsdelivr.net/npm/vis-network@10.1.2/standalone/esm/vis-network.min.js
https://cdn.jsdelivr.net/npm/@antv/g6@5.1.1/dist/g6.min.js
```
Not on cdnjs: Cytoscape extensions, elkjs, svg-pan-zoom, @viz-js/viz v3 (cdnjs "viz.js" = 2.1.2), @hpcc-js.

## Appendix — measurements

This box, Node 25.2.1 and headless Chrome, single run, synthetic 40-layer DAG with mostly short edges (scripts: `scratchpad/gpr0/bench`, `scratchpad/gpr0/web`).

| Engine | 500 n / 1,500 e | 2,000 n / 10,000 e | Rerun identical |
|---|---|---|---|
| @dagrejs/dagre 3.1.1 | 1,956 ms | > 240 s (killed) | yes; order-sensitive |
| cytoscape-dagre 4.0.1 (headless cy) | 2,386 ms | > 240 s (killed) | yes |
| ELK layered 0.12.0 | 1,118 ms | 12,296 ms | yes |
| viz.js dot, plain / svg (Node) | 399 / 401 ms | 11,428 / 11,994 ms (4.8 MB) | yes |
| viz.js dot → SVG (Chrome) | — | 13,687 ms; 46,004 elements; inject 131 ms | — |
| hpcc wasm-graphviz dot | 289 ms | 8,810 ms | yes |
| fcose 2.2.0 (quality default) | 858 ms | 58,605 ms | **no** |
| built-in cose | 3,383 ms | — | **no** |
| ForceAtlas2 0.10.1, 200 iterations | 207 ms | 2,561 ms | yes |
| d3-force 3.0.0, 300 ticks | 276 ms | 1,645 ms | yes |
| Cytoscape render (Chrome) | import 414 ms; first render 192 ms; pan p90 50 ms; fade 88 ms | first render 667 ms; pan p90 339 ms; fade 405 ms | — |
| Sigma render (Chrome, software WebGL) | — | first render 136 ms; reducer 38 ms; pan/zoom 466–711 ms (not GPU-representative) | — |

Caveat: 5 edges/node is the brief's upper bound; a real 2k-node graph sits between the columns.

## Sources (accessed 2026-09-02)

- Cytoscape: https://js.cytoscape.org/ ; `documentation/md/{performance,style,notation,events}.md`, issues #3416, #2397, discussion #3125 at https://github.com/cytoscape/cytoscape.js ; https://cytoscape.org/js-perf/ ; https://blog.js.cytoscape.org/2020/05/11/layouts/ ; https://github.com/iVis-at-Bilkent/cytoscape.js-fcose/issues/36 ; https://github.com/cytoscape/cytoscape.js-cose-bilkent/issues/94 ; the cytoscape.js-dagre/-elk/-klay repos under https://github.com/cytoscape/.
- Graphviz/WASM: https://github.com/mdaines/viz-js ; https://viz-js.com/api/ ; https://github.com/hpcc-systems/hpcc-js-wasm ; https://github.com/magjac/d3-graphviz ; https://github.com/bumbu/svg-pan-zoom ; https://graphviz.org/docs/outputs/svg/ ; https://graphviz.org/docs/attrs/start/ ; https://graphviz.org/docs/attrs/ordering/ ; https://graphviz.org/docs/attrs/pos/.
- Others: https://www.sigmajs.org/docs/ (+ `/advanced/events/`, `settings.ts`) ; https://graphology.github.io/standard-library/layout-forceatlas2.html ; https://d3js.org/d3-force/simulation ; https://d3js.org/getting-started ; https://github.com/kieler/elkjs ; https://eclipse.dev/elk/reference/ (layered algorithm; `randomSeed`, `interactive`, `considerModelOrder` options) ; https://visjs.github.io/vis-network/docs/network/ ; https://g6.antv.antgroup.com/en/manual/introduction.
- Prior art: https://www.w3.org/TR/prov-o/ ; http://provoviz.org/ ; https://github.com/gems-uff/prov-viewer ; https://github.com/guacsec/guac-visualizer ; https://github.com/craigmbooth/nix-visualize ; https://guix.gnu.org/manual/en/html_node/Invoking-guix-graph.html ; https://github.com/sverweij/dependency-cruiser/blob/main/doc/cli.md ; https://github.com/pahen/madge.
- Assurance: https://scsc.uk/gsn-standard ; https://arxiv.org/html/2506.11023v1 ; https://www.sei.cmu.edu/asset_files/TechnicalReport/2015_005_001_434813.pdf ; https://arxiv.org/html/2409.10665 ; https://www.adelard.com/news/ (ASCE 5.1) ; https://www.faa.gov/about/office_org/headquarters_offices/ang/redac/redac-sas-201503-advocate.pdf.
- Accessibility: https://www.w3.org/WAI/WCAG22/Understanding/use-of-color.html ; `/Techniques/general/G111` ; `/Understanding/non-text-contrast.html`.
