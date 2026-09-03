"""Q4 cross-source identity: crosswalk (v2.7 @ ba4e625 = baseline; v2.6 @ 699fbc2 = historical) vs factory ledger @ d217ee2."""
import json,re,collections
L=json.load(open('pin/CLAIM_LEDGER.json')); cl=L['claims']; fid={c['claim_id'] for c in cl}; byid={c['claim_id']:c for c in cl}
mos={}
for f in ['evidence','assumptions','arguments','sources','objectives','defeaters','occupancy','embodiment']:
    D=json.load(open(f'pin/mosaic/{f}.json'))
    for k,v in D.items():
        if isinstance(v,list) and v and isinstance(v[0],dict) and 'id' in v[0]:
            for x in v: mos[x['id']]=f'{f}.{k}'
BARE=re.compile(r'\b[A-Z][A-Z0-9]*(?:-[A-Z0-9.]+)+\b')
tree=set(l.split('\t')[1] for l in open('pin/ls-tree.txt').read().splitlines())
def walk(o,path,fn):
    if isinstance(o,dict):
        for k,v in o.items(): walk(v,path+'/'+k,fn)
    elif isinstance(o,list):
        for i,v in enumerate(o): walk(v,path+f'/{i}',fn)
    else: fn(o,path)
out={}
for label,fn_ in [('v2.7@ba4e625',"cw/cw_v27_ba4e625.json"),('v2.6@699fbc2',"cw/cw_v26_699fbc2.json")]:
    cw=json.load(open(fn_)); recs=cw['records']; rid={str(r['record_id']) for r in recs}
    e={'records':len(recs),'record_keys':dict(collections.Counter(k for r in recs for k in r).most_common(40)),'top_keys':list(cw.keys())}
    # (a) every string naming a factory claim id
    hits=collections.Counter(); ex=[]; nonledger=collections.Counter(); tokens_any=collections.Counter()
    def fn(o,path):
        if not isinstance(o,str): return
        key=re.sub(r'/\d+','/*',path)
        for t in set(BARE.findall(o)):
            if t in fid: hits[(key,t)]+=1; ex.append((path,t))
            elif t in mos: hits[(key,'MOSAIC:'+t)]+=1
    walk(cw,'',fn)
    e['factory_claim_id_mentions']={f'{k} :: {t}':n for (k,t),n in hits.items()}
    e['factory_claim_id_mentions_total']=sum(hits.values())
    e['factory_candidates_keys']={k:(k in fid) for k in (cw.get('factory_candidates') or {})}
    e['resolved_candidates_keys']=list((cw.get('resolved_candidates') or {}).keys()); e['liveness_keys']=list((cw.get('liveness_candidates') or {}).keys()); e['semantic_obligations_keys']=list((cw.get('semantic_obligations') or {}).keys())
    # (a) records with source_registry claim-ledger
    cr=[r for r in recs if r.get('source_registry')=='claim-ledger']
    e['claim-ledger_records']=[{k:r.get(k) for k in ('record_id','name','statement','claim','relation','semantic_obligation','source_registry','source_ids','witness_paths','evidence_class_token','derivation_links','scope_profile','trust_profile') if k in r} for r in cr]
    # (d) collisions: tokens present in BOTH namespaces
    cw_tokens=set()
    def fn2(o,path):
        if isinstance(o,str):
            for t in re.findall(r'\b(?:S[1-6]\??|L1\??|E-\d{2}[abc]?|F\d{1,2}|EXP-\d+[a-z]?|W-\d+|R0\.\d(?:\.\d)?|H[1-7]|INC-[A-Z0-9-]+|[A-Z][A-Z0-9]*(?:-[A-Z0-9.]+)+)\b',o): cw_tokens.add(t)
    walk(cw,'',fn2)
    cw_ids=rid|set((cw.get('semantic_obligations') or {}).keys())|set((cw.get('liveness_candidates') or {}).keys())|set((cw.get('factory_candidates') or {}).keys())|set((cw.get('resolved_candidates') or {}).keys())
    e['cw_identifier_namespace']=sorted(cw_ids - rid)
    e['exact_id_collisions_cw_ids_vs_factory_claims']=sorted(cw_ids & fid)
    e['exact_id_collisions_cw_ids_vs_mosaic_ids']=sorted(cw_ids & set(mos))
    e['cw_prefixes_seen']=dict(collections.Counter(t.split('-')[0] if '-' in t else re.sub(r'\d.*','',t) for t in cw_tokens).most_common(30))
    # (c) near-duplicate texts
    def norm(s): return re.sub(r'\s+',' ',re.sub(r'[^a-z0-9 ]',' ',s.lower())).strip()
    def toks(s): return set(norm(s).split())
    ftexts=[(c['claim_id'],k,c[k]) for c in cl for k in ('statement','finding') if isinstance(c.get(k),str) and len(c[k])>20]
    ctexts=[(str(r['record_id']),k,v) for r in recs for k,v in r.items() if isinstance(v,str) and len(v)>20 and k not in ('source_registry','evidence_class','evidence_class_token','derivation_links')]
    exact=[]; near=[]
    fn_norm=[(a,b,norm(c),toks(c)) for a,b,c in ftexts]
    for ra,rb,rc in ctexts:
        n=norm(rc); T=toks(rc)
        for fa,fb,fnn,FT in fn_norm:
            if n==fnn: exact.append((ra,rb,fa,fb))
            else:
                j=len(T&FT)/max(1,len(T|FT))
                if j>=0.5 and min(len(T),len(FT))>=8: near.append((round(j,2),ra,rb,fa,fb,rc[:90],byid[fa][fb][:90]))
    near.sort(reverse=True)
    e['text_exact_matches']=exact; e['text_near_matches_jaccard>=0.5']=near[:12]; e['text_near_count']=len(near)
    # names: crosswalk `name` vs factory ids/statements
    names=[(str(r['record_id']),r.get('name') or r.get('title') or '') for r in recs]
    e['cw_name_field_present']=sum(1 for _,n in names if n)
    # (e) obligations
    e['cw_semantic_obligations']={k:(v if isinstance(v,str) else json.dumps(v)[:80]) for k,v in (cw.get('semantic_obligations') or {}).items()}
    out[label]=e
E=json.load(open('pin/mosaic/evidence.json'))
out['factory_obligation_vocab']={'evidence.json#obligations':list(E['obligations'].keys()),'used_on_claims':dict(collections.Counter(c.get('obligation') for c in cl if 'obligation' in c))}
# (e) same-proposition candidates: what the crosswalk ALREADY emits into the factory namespace vs what the factory adapter would emit for the 4 cited claims
four=['EMB-AUTH-NONAMP','EMB-CUT-EMPTY','TAX-FLOW','TAX-RELATIONAL-2']
def wlid(w):
    m=re.fullmatch(r'(\S+)(?:\s+§(\S+))?',w); return f'witness:factory:{m.group(1)}'+(f'#{m.group(2)}' if m.group(2) else '')
out['four_factory_claims']={c:{'status':byid[c]['status'],'obligation':byid[c].get('obligation'),'evidence_kind':byid[c].get('evidence_kind'),'witnesses':byid[c]['witnesses'],'witness_lids':[wlid(w) for w in byid[c]['witnesses']],'implementation_binding':byid[c].get('implementation_binding'),'statement':byid[c]['statement'][:160]} for c in four}
# baseline projection lids under factory namespace
import os
B='/home/travis/ProjectAmp2/graphonomous/v2/projections/baseline/records/'
rels=[json.loads(l) for l in open(B+'relation.jsonl') if 'factory' in l]
nodes=[json.loads(l) for l in open(B+'node.jsonl') if ':factory:' in l]
out['baseline_factory_relations']=[(r['kind'],r['source'],r['target'],len(r.get('assertions',[]))) for r in rels]
out['baseline_factory_nodes']=[(n['kind'],n['lid'],len(n.get('assertions',[]))) for n in nodes]
# would-be factory adapter emissions that coincide with baseline lids
fact_wit_lids={wlid(w) for c in cl for w in c['witnesses']}
base_wit={n['lid'] for n in nodes if n['kind']=='WITNESS'}
out['witness_lid_overlap']=sorted(base_wit&fact_wit_lids)
# which factory claims cite scripts/emb-support.mjs (bare) → same WITNESS node
out['factory_claims_citing_emb_support']=[(c['claim_id'],w) for c in cl for w in c['witnesses'] if w.startswith('scripts/emb-support.mjs')]
# LOCATED_IN witness→loc: the loc lid the crosswalk minted
out['baseline_loc_lids_factory']=sorted({r['target'] for r in rels if r['kind']=='LOCATED_IN'})
emb_blob=[l for l in open('pin/ls-tree.txt') if l.rstrip().endswith('scripts/emb-support.mjs')][0].split()[2]
out['emb_support_blob_at_pin']=emb_blob
# cells: BINDS targets crosswalk already has vs factory cell bindings
cwb=json.load(open('cw/cw_v27_ba4e625.json'))
cw_cells=sorted({re.match(r'cells\.json:(\S+)',s).group(1) for r in cwb['records'] for s in r.get('source_ids',[]) if isinstance(s,str) and s.startswith('cells.json:')})
f_cells=sorted({c['implementation_binding'][5:] for c in cl if isinstance(c.get('implementation_binding'),str) and c['implementation_binding'].startswith('cell:')})
out['cells']={'crosswalk_BINDS_targets':cw_cells,'factory_bound_cells':f_cells,'shared_cell_targets':sorted(set(cw_cells)&set(f_cells))}
# which crosswalk records bind shared cells and which factory claims bind them
for n in out['cells']['shared_cell_targets']:
    out['cells'][f'cell:{n}']={'crosswalk_records':[str(r['record_id']) for r in cwb['records'] if any(isinstance(s,str) and s.startswith(f'cells.json:{n}') for s in r.get('source_ids',[]))],'factory_claims':[c['claim_id'] for c in cl if c.get('implementation_binding')==f'cell:{n}']}
# prefix collision inside the factory: INC claims vs INC incidents
out['intra_factory_prefix_collision_INC']={'claims':[i for i in fid if i.startswith('INC-')],'incident_ids_sample':[i for i in mos if i.startswith('INC-')][:5],'exact_overlap':sorted({i for i in fid if i.startswith('INC-')}&set(mos))}
# crosswalk ids that are also factory ids of a different kind: S4 as space label
out['S_token_in_factory']={'FED-Q3-HYP-S4 statement':byid['FED-Q3-HYP-S4']['statement'][:200]}
json.dump(out,open('census_cross.json','w'),indent=1,ensure_ascii=False,default=str)
for k,v in out.items():
    if isinstance(v,dict) and 'records' in v:
        print('=====',k)
        for kk,vv in v.items(): print(kk,'=',json.dumps(vv,ensure_ascii=False,default=str)[:1600]); 
    else: print(k,'=',json.dumps(v,ensure_ascii=False,default=str)[:1600])
    print()
