import { performance } from 'node:perf_hooks';
import { createHash } from 'node:crypto';
const [engine, nStr, mStr] = process.argv.slice(2);
const n = +nStr, m = +mStr;
function lcg(seed){ let s = seed>>>0; return ()=> (s = (Math.imul(s,1664525) + 1013904223)>>>0) / 4294967296; }
function gen(n,m,seed=42){
  const rnd = lcg(seed); const edges = new Set(); const list=[];
  const layers = 40, per = Math.ceil(n/layers); let guard=0;
  while(list.length<m && guard<m*200){ guard++;
    const u = Math.floor(rnd()*n); const ru = Math.floor(u/per);
    const dr = 1 + Math.floor(rnd()*rnd()*6); const rv = ru + dr; if (rv>=layers) continue;
    const v = rv*per + Math.floor(rnd()*per); if (v>=n||v===u) continue;
    const k = u+'->'+v; if(edges.has(k)) continue; edges.add(k); list.push([u,v]);
  }
  return { nodes: Array.from({length:n},(_,i)=>'n'+i), edges: list.map(([u,v],i)=>({id:'e'+i, source:'n'+u, target:'n'+v})) };
}
const g = gen(n,m);
const hash = (x)=>createHash('sha256').update(JSON.stringify(x)).digest('hex').slice(0,12);
const out = (obj)=>console.log(JSON.stringify({engine,n,m:g.edges.length,...obj}));
const toDot = (g)=>'digraph G {\nnode [shape=box width=0.6 height=0.3 fixedsize=true label=""];\n'+g.nodes.map(x=>x+';').join('\n')+'\n'+g.edges.map(e=>e.source+' -> '+e.target+';').join('\n')+'\n}';
async function run(){
 if(engine==='dagre'){
   const dagre = (await import('@dagrejs/dagre')).default;
   const doIt = (order)=>{ const G = new dagre.graphlib.Graph(); G.setGraph({rankdir:'TB', nodesep:20, ranksep:40}); G.setDefaultEdgeLabel(()=>({}));
     for(const id of order) G.setNode(id,{width:60,height:30}); for(const e of g.edges) G.setEdge(e.source,e.target);
     const t0=performance.now(); dagre.layout(G); const t=performance.now()-t0;
     const pos = g.nodes.map(id=>{const p=G.node(id); return [Math.round(p.x),Math.round(p.y)];}); return {t,h:hash(pos)}; };
   const a=doIt(g.nodes), b=doIt(g.nodes), c=doIt([...g.nodes].reverse());
   out({ms:Math.round(a.t), rerun_same_hash:a.h===b.h, reversed_insertion_same_hash:a.h===c.h});
 } else if(engine==='elk'){
   const ELK = (await import('elkjs/lib/elk.bundled.js')).default; const elk = new ELK();
   const mk = ()=>({id:'root', layoutOptions:{'elk.algorithm':'layered','elk.direction':'DOWN'}, children:g.nodes.map(id=>({id,width:60,height:30})), edges:g.edges.map(e=>({id:e.id,sources:[e.source],targets:[e.target]}))});
   const t0=performance.now(); const r1=await elk.layout(mk()); const t=performance.now()-t0; const r2=await elk.layout(mk());
   const p=(r)=>r.children.map(c=>[Math.round(c.x),Math.round(c.y)]);
   out({ms:Math.round(t), rerun_same_hash:hash(p(r1))===hash(p(r2))});
 } else if(engine==='viz'){
   const Viz = await import('@viz-js/viz'); const viz = await Viz.instance();
   const dot = toDot(g); const t0=performance.now(); const s1 = viz.renderString(dot,{format:'plain'}); const t=performance.now()-t0;
   const t1=performance.now(); const svg = viz.renderString(dot,{format:'svg'}); const tsvg=performance.now()-t1;
   const s2 = viz.renderString(dot,{format:'plain'});
   out({graphviz:viz.graphvizVersion, ms_plain:Math.round(t), ms_svg:Math.round(tsvg), svg_bytes:svg.length, rerun_same_hash:hash(s1)===hash(s2)});
 } else if(engine==='hpcc'){
   const { Graphviz } = await import('@hpcc-js/wasm-graphviz'); const gv = await Graphviz.load();
   const dot = toDot(g); const t0=performance.now(); const s1 = gv.layout(dot,'plain','dot'); const t=performance.now()-t0; const s2 = gv.layout(dot,'plain','dot');
   out({graphviz:gv.version(), ms_plain:Math.round(t), rerun_same_hash:hash(s1)===hash(s2)});
 } else if(engine==='fcose' || engine==='cydagre' || engine==='cose'){
   const cytoscape = (await import('cytoscape')).default;
   if(engine==='fcose'){ const fcose=(await import('cytoscape-fcose')).default; cytoscape.use(fcose); }
   if(engine==='cydagre'){ const d=(await import('cytoscape-dagre')).default; cytoscape.use(d); }
   const els = [...g.nodes.map(id=>({data:{id}})), ...g.edges.map(e=>({data:e}))];
   const t00=performance.now(); const cy = cytoscape({headless:true, styleEnabled:true, elements: els}); const tInit=performance.now()-t00;
   const opts = engine==='fcose'? {name:'fcose', animate:false, randomize:true, quality:'default'} : engine==='cydagre'? {name:'dagre', rankDir:'TB'} : {name:'cose', animate:false, randomize:true};
   const runOnce = ()=>new Promise(res=>{ const t0=performance.now(); const l=cy.layout(opts); l.on('layoutstop',()=>{ const pos=cy.nodes().map(nn=>{const p=nn.position(); return [Math.round(p.x),Math.round(p.y)];}); res({t:performance.now()-t0,h:hash(pos)}); }); l.run(); });
   const a=await runOnce(); const b=await runOnce();
   out({init_ms:Math.round(tInit), ms:Math.round(a.t), rerun_same_hash:a.h===b.h});
 } else if(engine==='fa2'){
   const Graph=(await import('graphology')).default; const fa2=(await import('graphology-layout-forceatlas2')).default; const {circular}=await import('graphology-layout');
   const doIt=()=>{ const G=new Graph(); for(const id of g.nodes) G.addNode(id); for(const e of g.edges) G.addEdge(e.source,e.target); circular.assign(G); const settings=fa2.inferSettings(G); const t0=performance.now(); fa2.assign(G,{iterations:200,settings}); const t=performance.now()-t0; const pos=g.nodes.map(id=>{const a=G.getNodeAttributes(id); return [+a.x.toFixed(3),+a.y.toFixed(3)];}); return {t,h:hash(pos),settings}; };
   const a=doIt(), b=doIt(); out({ms:Math.round(a.t), rerun_same_hash:a.h===b.h, settings:a.settings});
 } else if(engine==='d3force'){
   const d3=await import('d3-force');
   const doIt=()=>{ const nodes=g.nodes.map(id=>({id})); const links=g.edges.map(e=>({source:e.source,target:e.target})); const sim=d3.forceSimulation(nodes).force('link',d3.forceLink(links).id(d=>d.id).distance(30)).force('charge',d3.forceManyBody().strength(-30)).force('center',d3.forceCenter()).stop(); const t0=performance.now(); sim.tick(300); const t=performance.now()-t0; const pos=nodes.map(nn=>[+nn.x.toFixed(3),+nn.y.toFixed(3)]); return {t,h:hash(pos)}; };
   const a=doIt(), b=doIt(); out({ms:Math.round(a.t), rerun_same_hash:a.h===b.h});
 } else { out({error:'unknown engine'}); }
}
run().then(()=>process.exit(0)).catch(e=>{ out({error:String(e && e.stack || e).slice(0,400)}); process.exit(1); });
