"""Q3 detail: typed reference fields in arguments/defeaters/assumptions/sources and their resolve counts at d217ee2."""
import json,re,collections
P='pin'; L=json.load(open(f'{P}/CLAIM_LEDGER.json')); ids={c['claim_id'] for c in L['claims']}
M={f:json.load(open(f'{P}/mosaic/{f}.json')) for f in ['evidence','assumptions','arguments','sources','objectives','defeaters','occupancy','embodiment']}
mos={}
for f,D in M.items():
    for k,v in D.items():
        if isinstance(v,list) and v and isinstance(v[0],dict) and 'id' in v[0]:
            for x in v: mos[x['id']]=f'{f}.{k}'
def cnt(it): return {str(k) if not isinstance(k,tuple) else ' | '.join(map(str,k)):n for k,n in collections.Counter(it).items()}
def res(t): return 'claim' if t in ids else (mos.get(t) or ('witness-path' if '/' in str(t) else 'UNRESOLVED'))
out={}
A=M['arguments']['arguments']
out['arguments']={'roles':dict(collections.Counter(a['role'] for a in A)),'obligation_discharged':dict(collections.Counter(a.get('obligation_discharged') for a in A)),
 'conclusion_claim':dict(collections.Counter(res(a.get('conclusion_claim')) for a in A if a.get('conclusion_claim'))),
 'premise_claims':dict(collections.Counter(res(p) for a in A for p in a['premise_claims'])),'premise_claims_total':sum(len(a['premise_claims']) for a in A),
 'evidence_refs_kind':dict(collections.Counter(e.get('kind') for a in A for e in a['evidence_refs'])),'evidence_refs_resolve':cnt((e.get('kind'),res(e.get('ref'))) for a in A for e in a['evidence_refs']),
 'assumption_refs':dict(collections.Counter(res(r) for a in A for r in a['assumption_refs'])),'residual_refs':dict(collections.Counter(res(r) for a in A for r in a.get('residual_refs',[]))),
 'sample':{k:A[0][k] for k in ('id','role','rule','premise_claims','evidence_refs','assumption_refs','conclusion_claim','obligation_discharged')}}
out['role_conclusions']=M['arguments'].get('role_conclusions')
D=M['defeaters']['defeaters']; I=M['defeaters']['incidents']
tr=collections.Counter(); tshape=collections.Counter()
for d in D:
    t=d.get('target_ref')
    if t is not None: tr[(d['target_type'],type(t).__name__, res(t) if isinstance(t,str) else ('dict:'+','.join(sorted(t.keys()))))]+=1
    t2=d.get('target')
    if t2 is not None: tshape[(d['target_type'],type(t2).__name__, res(t2) if isinstance(t2,str) else 'dict:'+','.join(sorted(t2.keys())) if isinstance(t2,dict) else 'list')]+=1
out['defeaters']={'kinds':dict(collections.Counter(d['kind'] for d in D)),'target_types':dict(collections.Counter(d['target_type'] for d in D)),'statuses':dict(collections.Counter(d.get('status') for d in D)),
 'target_ref':{' | '.join(map(str,k)):n for k,n in tr.items()},'target':{' | '.join(map(str,k)):n for k,n in tshape.items()},
 'related_claims':dict(collections.Counter(res(c) for d in D for c in d.get('related_claims',[]))),'related_claims_total':sum(len(d.get('related_claims',[])) for d in D),
 'disposition_keys':cnt(tuple(sorted(d['disposition'].keys())) if isinstance(d.get('disposition'),dict) else type(d.get('disposition')).__name__ for d in D)}
out['defeaters_target_dict_claim_resolve']={}
cnt2=collections.Counter()
for d in D:
    for key in ('target','target_ref'):
        t=d.get(key)
        if isinstance(t,dict):
            for kk,vv in t.items():
                if isinstance(vv,str): cnt2[(key,kk,res(vv))]+=1
out['defeaters_target_dict_claim_resolve']={' | '.join(k):n for k,n in cnt2.items()}
out['incidents']={'subject_type':dict(collections.Counter(i['subject_type'] for i in I)),'subject_ref':cnt((i['subject_type'],res(i['subject_ref']) if isinstance(i['subject_ref'],str) else type(i['subject_ref']).__name__) for i in I),
 'defeater_ref':dict(collections.Counter(res(i['defeater_ref']) for i in I)),'status':dict(collections.Counter(i['status'] for i in I)),'severity':dict(collections.Counter(i['severity'] for i in I)),'revision_found':dict(collections.Counter(i['revision_found'] for i in I)),'fixed_by':dict(collections.Counter(type(i['fixed_by']).__name__ for i in I)),'reproducer_type':dict(collections.Counter(type(i['reproducer']).__name__ for i in I)),
 'reproducer_paths_in_tree':None}
tree=set(l.split('\t')[1] for l in open(f'{P}/ls-tree.txt').read().splitlines())
rp=collections.Counter()
for i in I:
    r=i['reproducer']; s=r if isinstance(r,str) else json.dumps(r)
    paths=re.findall(r'\b(?:scripts|mosaic|opensentience\.org|AmpersandBoxDesign)/[\w./-]+',s)
    for p in paths: rp['in-tree' if p in tree else 'not-in-tree']+=1
out['incidents']['reproducer_paths_in_tree']=dict(rp)
AS=M['assumptions']['assumptions']
out['assumptions']={'kinds':dict(collections.Counter(a['kind'] for a in AS)),'discharged':dict(collections.Counter(a['discharged'] for a in AS)),'cited_by':dict(collections.Counter(res(c) for a in AS for c in a['cited_by'])),'cited_by_total':sum(len(a['cited_by']) for a in AS),'discharge_types':dict(collections.Counter(type(a['discharge']).__name__ for a in AS)),'discharge_state_keys':dict(collections.Counter(k for a in AS if isinstance(a.get('discharge_state'),dict) for k in a['discharge_state']))}
SR=M['sources']['sources']
out['sources']={'used_by':dict(collections.Counter(res(c) for s in SR for c in s['used_by'])),'used_by_total':sum(len(s['used_by']) for s in SR),'hypotheses_type':dict(collections.Counter(type(h).__name__ for s in SR for h in s['hypotheses'])),'sample_id':SR[0]['id'],'sample_citation':SR[0]['citation'][:120]}
E=M['evidence']
out['evidence']={'kinds':list(E['kinds'].keys()),'kind_fields':dict(collections.Counter(k for v in E['kinds'].values() for k in v)),'obligations':list(E['obligations'].keys()) if isinstance(E['obligations'],dict) else E['obligations'],'status_obligation_domain':{k:(v if isinstance(v,str) else list(v.keys()) if isinstance(v,dict) else v) for k,v in E['status_obligation_domain'].items()} if isinstance(E['status_obligation_domain'],dict) else None,'origins':E['origins'] if not isinstance(E['origins'],dict) else list(E['origins'].keys()),'instrument_produces':dict(collections.Counter(i['produces'] if isinstance(i['produces'],str) else json.dumps(i['produces']) for i in E['instruments']))}
# reverse: which claims are conclusion of an argument vs claims with evidence_kind
concl={a.get('conclusion_claim') for a in A}
out['claims_with_argument']=len(concl&ids); out['settled_claims_without_argument']=sorted(c['claim_id'] for c in L['claims'] if c['status'] in L['_settled']['statuses'] and c['claim_id'] not in concl)[:100]
out['settled_claims_without_argument_n']=len(out['settled_claims_without_argument'])
OCC=M['occupancy']; out['occupancy_kind_vocabulary']=OCC['kind_vocabulary']
json.dump(out,open('census_mosaic_refs.json','w'),indent=1,ensure_ascii=False,default=str)
for k,v in out.items(): print(k,'=',json.dumps(v,ensure_ascii=False,default=str)[:1500]); print()
