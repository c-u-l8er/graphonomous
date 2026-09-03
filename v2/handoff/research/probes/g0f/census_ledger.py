#!/usr/bin/env python3
"""Q2 + Q3 census of CLAIM_LEDGER.json and mosaic/*.json at d217ee2 (files dumped by `git show` into pin/)."""
import json, re, collections, os, hashlib
P='pin'
L=json.load(open(f'{P}/CLAIM_LEDGER.json'))
tree=set(l.split('\t')[1] for l in open(f'{P}/ls-tree.txt').read().splitlines())
out={}
cl=L['claims']
out['top_level_keys']=list(L.keys())
out['_statuses']=list(L['_statuses'].keys()); out['_settled']=L['_settled']['statuses']; out['_round']=L['_round']
out['claim_count']=len(cl); ids=[c['claim_id'] for c in cl]; out['dup_ids']=len(ids)-len(set(ids))
# field census
fc=collections.Counter(); ft=collections.defaultdict(collections.Counter)
for c in cl:
    for k,v in c.items():
        fc[k]+=1; ft[k][type(v).__name__ if v is not None else 'null']+=1
out['field_census']={k:{'count':n,'types':dict(ft[k])} for k,n in fc.most_common()}
# id regex per prefix
pre=collections.defaultdict(list)
for i in ids: pre[i.split('-')[0]].append(i)
out['prefix_counts']={k:len(v) for k,v in sorted(pre.items(),key=lambda kv:-len(kv[1]))}
out['id_regex_all']=sum(1 for i in ids if re.fullmatch(r'[A-Z0-9]+(-[A-Z0-9.]+)+',i))
out['id_regex_bare_token_D031']=sum(1 for i in ids if re.fullmatch(r'[A-Z][A-Z0-9]*(-[A-Z0-9.]+)+',i))
out['ids_with_dot']=[i for i in ids if '.' in i]; out['ids_with_digit_only_segment']=[i for i in ids if re.search(r'-\d+$',i)][:40]
out['status_counts']=dict(collections.Counter(c['status'] for c in cl))
out['status_outside_vocab']=[c['claim_id'] for c in cl if c['status'] not in L['_statuses']]
settled=set(L['_settled']['statuses'])
out['settled_count']=sum(1 for c in cl if c['status'] in settled)
out['settled_without_witness']=[(c['claim_id'],c['status']) for c in cl if c['status'] in settled and not c.get('witnesses')]
out['obligation_counts']=dict(collections.Counter(c.get('obligation') for c in cl if 'obligation' in c))
out['evidence_kind_counts']=dict(collections.Counter(c.get('evidence_kind') for c in cl if 'evidence_kind' in c))
out['status_x_obligation_present']={f'{s}:{"has" if o else "no"}':n for (s,o),n in collections.Counter((c['status'],'obligation' in c) for c in cl).items()}
# witnesses
wit=[]; forms=collections.Counter(); resolve=0; dangle=[]; sec=0; by_root=collections.Counter(); claims_without=collections.Counter()
for c in cl:
    ws=c.get('witnesses') or []
    if not ws: claims_without[c['status']]+=1
    for w in ws:
        m=re.fullmatch(r'(\S+)(?:\s+§(\S+))?',w)
        path,section=(m.group(1),m.group(2)) if m else (w,None)
        form='path §n' if section else ('path' if m else 'OTHER')
        if '#' in w: form='path#frag'
        forms[form]+=1
        ok=path in tree; resolve+=ok
        if not ok: dangle.append((c['claim_id'],w))
        by_root[path.split('/')[0]]+=1
        if section: sec+=1
        wit.append((c['claim_id'],path,section,ok))
out['witnesses']={'total':len(wit),'claims_with':sum(1 for c in cl if c.get('witnesses')),'claims_without_by_status':dict(claims_without),'forms':dict(forms),'with_section':sec,'resolve_in_tree':resolve,'dangling':dangle,'by_top_dir':dict(by_root),'distinct_paths':len(set(w[1] for w in wit)),'distinct_path_section':len(set((w[1],w[2]) for w in wit))}
# section-in-file check for §n witnesses
secmiss=[]
for cid,path,section,ok in wit:
    if ok and section:
        try: txt=open(f'{P}/{path}',encoding='utf8',errors='replace').read() if os.path.exists(f'{P}/{path}') else None
        except Exception: txt=None
        if txt is None: continue
        if not re.search(r'§\s*'+re.escape(section)+r'\b',txt): secmiss.append((cid,path,section))
out['witnesses']['section_missing_in_dumped_file(only pin/ files dumped: mosaic/*)']=secmiss
# assumptions[]
A=json.load(open(f'{P}/mosaic/assumptions.json')); asm_ids={a['id'] for a in A['assumptions']}
ashape=collections.Counter(); aid_res=0; aid_dang=[]; free=0; claims_with_a=0
for c in cl:
    al=c.get('assumptions')
    if al: claims_with_a+=1
    for a in al or []:
        if isinstance(a,str) and re.fullmatch(r'ASM-[A-Z0-9-]+',a):
            ashape['id']+=1
            if a in asm_ids: aid_res+=1
            else: aid_dang.append((c['claim_id'],a))
        elif isinstance(a,str):
            ashape['free-text']+=1; free+=1
            if re.search(r'\bASM-[A-Z0-9-]+',a): ashape['free-text-mentioning-ASM']+=1
        else: ashape[type(a).__name__]+=1
out['assumptions_field']={'claims_with_nonempty':claims_with_a,'items':dict(ashape),'ids_resolve':aid_res,'ids_dangling':aid_dang,'mosaic_assumption_ids':len(asm_ids)}
# assumption_refs
ar=collections.Counter(); arres=0; ardang=[]; arn=0
for c in cl:
    for r in c.get('assumption_refs') or []:
        arn+=1; ar[type(r).__name__]+=1
        rid=r if isinstance(r,str) else r.get('id') or r.get('ref')
        if rid in asm_ids: arres+=1
        else: ardang.append((c['claim_id'],r))
out['assumption_refs']={'claims_with_field':fc['assumption_refs'],'claims_nonempty':sum(1 for c in cl if c.get('assumption_refs')),'items':arn,'item_types':dict(ar),'resolve':arres,'dangling':ardang[:20],'dangling_count':len(ardang)}
# implementation_binding
C=json.load(open(f'{P}/cells.json')); cells={c['num'] for c in C['cells']}
ib=collections.Counter(); cellb=collections.Counter(); cell_dang=[]; path_dang=[]
for c in cl:
    b=c.get('implementation_binding')
    if b is None: ib['null']+=1
    elif isinstance(b,str) and b.startswith('cell:'):
        ib['cell']+=1; n=b[5:]; cellb[n]+=1
        if n not in cells: cell_dang.append((c['claim_id'],b))
    elif isinstance(b,str):
        ib['path']+=1
        if b.split(' ')[0] not in tree: path_dang.append((c['claim_id'],b))
    else: ib[type(b).__name__]+=1
out['implementation_binding']={'kinds':dict(ib),'cells':dict(cellb),'cells_in_cells.json':len(cells),'cell_dangling':cell_dang,'path_dangling':path_dang,'g0_baseline_cell_nodes':['16','27a'],'bound_cells_already_in_g0':[n for n in cellb if n in ('16','27a')]}
# prior_art
pa=collections.Counter(); pa_src=collections.Counter(); S=json.load(open(f'{P}/mosaic/sources.json')); src_ids={s['id'] for s in S['sources']}
pa_res=0; pa_dang=[]; pa_n=0
for c in cl:
    p=c.get('prior_art')
    if p is None: pa['null']+=1; continue
    pa[type(p).__name__]+=1
    if isinstance(p,str):
        pa_n+=1
        for m in re.findall(r'SRC-[A-Z0-9-]+',p):
            if m in src_ids: pa_res+=1
            else: pa_dang.append((c['claim_id'],m))
        if re.fullmatch(r'(none|n/a|—|-)\.?',p.strip(),re.I): pa_src['none-literal']+=1
        elif re.search(r'SRC-',p): pa_src['mentions SRC-*']+=1
        else: pa_src['free prose']+=1
out['prior_art']={'types':dict(pa),'string_forms':dict(pa_src),'SRC_mentions_resolve':pa_res,'SRC_mentions_dangling':pa_dang,'sources_json_ids':len(src_ids)}
# typed provenance
def sub(k): 
    d=collections.Counter(); 
    for c in cl:
        v=c.get(k)
        if v is None: continue
        if isinstance(v,dict): d[tuple(sorted(v.keys()))]+=1
        else: d[repr(v)[:60]]+=1
    return {str(k2):n for k2,n in d.most_common(12)}
out['imported_from']=sub('imported_from'); out['imported_from_source_revision']=dict(collections.Counter(c['imported_from'].get('source_revision') for c in cl if isinstance(c.get('imported_from'),dict)))
out['readjudicated']=sub('readjudicated'); out['readjudicated_by_method']={f'{a} | {b}':n for (a,b),n in collections.Counter((c['readjudicated'].get('by'),c['readjudicated'].get('method','')[:60]) for c in cl if isinstance(c.get('readjudicated'),dict)).items()}
out['readjudicated_authority_transferred']=dict(collections.Counter(c['readjudicated'].get('authority_transferred') for c in cl if isinstance(c.get('readjudicated'),dict)))
out['last_verified']=dict(collections.Counter(c.get('last_verified') for c in cl))
out['refutation_scope']=dict(collections.Counter(c.get('refutation_scope') for c in cl if 'refutation_scope' in c))
out['refuted_without_scope']=[c['claim_id'] for c in cl if c['status']=='REFUTED' and 'refutation_scope' not in c]
# evidence_qualifiers
eq=collections.Counter(); eq_cit=0; eq_cit_d=[]; eq_arg=0; eq_arg_d=[]; ARG=json.load(open(f'{P}/mosaic/arguments.json')); arg_ids={a['id'] for a in ARG['arguments']}
for c in cl:
    q=c.get('evidence_qualifiers')
    if q is None: continue
    eq[tuple(sorted(q.keys())) if isinstance(q,dict) else type(q).__name__]+=1
    if isinstance(q,dict):
        if 'citation_ref' in q: (eq_cit:=eq_cit) ; 
        cr=q.get('citation_ref'); ma=q.get('mapping_argument_ref')
        if cr: 
            if cr in src_ids: eq_cit+=1
            else: eq_cit_d.append((c['claim_id'],cr))
        if ma:
            if ma in arg_ids: eq_arg+=1
            else: eq_arg_d.append((c['claim_id'],ma))
out['evidence_qualifiers']={'shapes':{str(k):n for k,n in eq.items()},'citation_ref_resolve':eq_cit,'citation_ref_dangling':eq_cit_d,'mapping_argument_ref_resolve':eq_arg,'mapping_argument_ref_dangling':eq_arg_d}
# relation-like fields
idset=set(ids)
rel={}
for k in ['supersedes','superseded_by','split_from','derived_from','refines','related','depends_on','dependencies','defeaters','see_also','conflicts_with','requires','generalizes','specializes','parent','children']:
    vals=[(c['claim_id'],c[k]) for c in cl if k in c]
    if not vals: continue
    res=0; dang=[]; typ=collections.Counter()
    for cid,v in vals:
        for t in (v if isinstance(v,list) else [v]):
            typ[type(t).__name__]+=1
            if isinstance(t,str) and t in idset: res+=1
            elif isinstance(t,str):
                toks=[x for x in re.findall(r'[A-Z][A-Z0-9]*(?:-[A-Z0-9.]+)+',t) if x in idset]
                if toks: res+=1; typ['prose-containing-id']+=1
                else: dang.append((cid,t[:80]))
    rel[k]={'claims':len(vals),'types':dict(typ),'targets_resolve':res,'unresolved':dang}
out['relation_like_fields']=rel
# any other string value that mentions another claim id (statement/evidence/finding prose)
mention=collections.Counter(); mention_ex=[]
for c in cl:
    for k in ['statement','evidence','finding','review_focus','gap','assumptions','prior_art']:
        v=c.get(k); s=json.dumps(v) if v is not None else ''
        for t in set(re.findall(r'[A-Z][A-Z0-9]*(?:-[A-Z0-9.]+)+',s)):
            if t in idset and t!=c['claim_id']: mention[k]+=1; mention_ex.append((c['claim_id'],k,t))
out['prose_mentions_of_other_claim_ids']={'by_field':dict(mention),'total':len(mention_ex),'examples':mention_ex[:8]}
# ---------- Q3 mosaic ----------
mos={}
def idre(idl):
    if not idl: return None
    ps=collections.Counter(re.match(r'[A-Z]+',i).group(0) if re.match(r'[A-Z]+',i) else '?' for i in idl)
    return {'n':len(idl),'prefixes':dict(ps),'all_match_^[A-Z]+(-[A-Z0-9.]+)+$':all(re.fullmatch(r'[A-Z]+(-[A-Z0-9.]+)+',i) for i in idl)}
mosaic_ids={}
def walk(o,path,fn):
    if isinstance(o,dict):
        for k,v in o.items(): walk(v,path+'/'+k,fn)
    elif isinstance(o,list):
        for i,v in enumerate(o): walk(v,path+f'/{i}',fn)
    else: fn(o,path)
for f in ['evidence','assumptions','arguments','sources','objectives','defeaters','occupancy','operations','embodiment','factory']:
    D=json.load(open(f'{P}/mosaic/{f}.json')); e={'top_level_keys':list(D.keys()),'version':D.get('version'),'round':D.get('round') or D.get('_round')}
    lists={k:len(v) for k,v in D.items() if isinstance(v,list)}
    e['record_lists']=lists
    for k,v in D.items():
        if isinstance(v,list) and v and isinstance(v[0],dict) and 'id' in v[0]:
            e[f'ids:{k}']=idre([x['id'] for x in v]); mosaic_ids[f'{f}.{k}']={x['id'] for x in v}
            e[f'fields:{k}']=dict(collections.Counter(kk for x in v for kk in x.keys()).most_common(25))
        if isinstance(v,dict) and v and all(isinstance(x,dict) for x in v.values()) and len(v)>2:
            e[f'dict:{k}']={'n':len(v),'keys':list(v.keys())[:12]}
    mos[f]=e; mos[f]['_doc']=D
allmos=set().union(*mosaic_ids.values())
# references: every string field naming a claim id or a mosaic id
for f,e in mos.items():
    D=e.pop('_doc'); refs=collections.Counter(); resolved=collections.Counter(); dang=collections.defaultdict(list); typed=collections.Counter()
    def fn(o,path):
        if not isinstance(o,str): return
        key=re.sub(r'/\d+','/*',path)
        for t in set(re.findall(r'\b[A-Z][A-Z0-9]*(?:-[A-Z0-9.]+)+\b',o)):
            if t in idset: refs[(key,'claim')]+=1; resolved['claim']+=1
            elif t in allmos: refs[(key,'mosaic')]+=1; resolved['mosaic']+=1
            elif re.match(r'(ASM|ARG|SRC|INS|DEF|INC|SO|EVAL|OCC|CAP|MEAS)-',t): dang[key].append(t)
    walk(D,'',fn)
    # typed refs {kind: ...}
    def fn2(o,path):
        pass
    def walk2(o,path):
        if isinstance(o,dict):
            if 'kind' in o and ('ref' in o or 'id' in o or 'claim' in o or 'witness' in o or 'source' in o) and isinstance(o.get('kind'),str):
                typed[o['kind']]+=1
            for k,v in o.items(): walk2(v,path+'/'+k)
        elif isinstance(o,list):
            for i,v in enumerate(o): walk2(v,path+f'/{i}')
    walk2(D,'')
    e['refs_by_field']={f'{k[0]} → {k[1]}':n for k,n in refs.most_common(40)}
    e['resolved']=dict(resolved); e['dangling_prefixed_tokens']={k:sorted(set(v)) for k,v in dang.items()}
    e['typed_ref_kinds']=dict(typed)
out['mosaic']=mos
# receipts
rc={}
for fn_ in sorted(os.listdir(f'{P}/mosaic/receipts')):
    D=json.load(open(f'{P}/mosaic/receipts/{fn_}'))
    dig=[]
    def fd(o,path):
        if isinstance(o,str) and re.fullmatch(r'[0-9a-f]{40}|[0-9a-f]{64}',o): dig.append((re.sub(r'/\d+','/*',path),len(o)))
    walk(D,'',fd)
    rc[fn_]={'receipt_version':D.get('receipt_version'),'keys':list(D.keys()),'digests':{f'{a} ({b})':n for (a,b),n in collections.Counter(dig).items()},'parent':{k:(v if not isinstance(v,(list,dict)) else type(v).__name__) for k,v in (D.get('parent') or {}).items()} if isinstance(D.get('parent'),dict) else D.get('parent'),'candidate':{k:(str(v)[:70]) for k,v in (D.get('candidate') or {}).items()} if isinstance(D.get('candidate'),dict) else D.get('candidate'),'invariants':{k:(v if isinstance(v,(int,str)) else (len(v) if isinstance(v,list) else v)) for k,v in (D.get('invariants') or {}).items()} if isinstance(D.get('invariants'),dict) else None}
out['receipts']=rc
# receipts: claim ids mentioned
rcm=collections.Counter()
for fn_ in os.listdir(f'{P}/mosaic/receipts'):
    s=open(f'{P}/mosaic/receipts/{fn_}').read()
    rcm[fn_]=len(set(t for t in re.findall(r'\b[A-Z][A-Z0-9]*(?:-[A-Z0-9.]+)+\b',s) if t in idset))
out['receipt_claim_id_mentions']=dict(rcm)
# revisions domain
recs={f'INV-{f[4:-5]}' if f.startswith('INV-') else f for f in os.listdir(f'{P}/mosaic/receipts')}
dom=set(L['_revisions']['pre_receipt'])|{f[:-5] for f in os.listdir(f'{P}/mosaic/receipts')}
out['refutation_scope_in_domain']={k:(k=='timeless' or k in dom) for k in out['refutation_scope']}
json.dump(out,open('census_ledger.json','w'),indent=1,ensure_ascii=False,default=str)
def show(k,v): print(f'{k}: {json.dumps(v,ensure_ascii=False,default=str)[:1800]}')
for k,v in out.items():
    if k in ('mosaic','receipts'): continue
    show(k,v)
print('=== mosaic ===')
for f,e in out['mosaic'].items(): show(f,e)
print('=== receipts ===')
for f,e in out['receipts'].items(): show(f,e)
