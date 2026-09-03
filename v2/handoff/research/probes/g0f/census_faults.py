"""Q6 expected fault counts + leftover Q2 details (binding prose, incident subject refs, witness outcome split)."""
import json,re,collections
L=json.load(open('pin/CLAIM_LEDGER.json')); cl=L['claims']; ids={c['claim_id'] for c in cl}
tree=set(l.split('\t')[1] for l in open('pin/ls-tree.txt').read().splitlines())
pb=[c['implementation_binding'] for c in cl if isinstance(c.get('implementation_binding'),str) and not c['implementation_binding'].startswith('cell:')]
prose=[b for b in pb if ' ' in b]; print('path bindings',len(pb),'with trailing prose',len(prose),'first token in tree',sum(1 for b in pb if b.split(' ')[0] in tree),'| examples',prose[:2])
print('path bindings with §',sum(1 for b in pb if '§' in b))
I=json.load(open('pin/mosaic/defeaters.json'))['incidents']
print('incident claim subjects',[(i['id'],i['subject_ref'],i['subject_ref'] in ids) for i in I if i['subject_type']=='claim'])
print('incident receipt subjects unresolved',[(i['id'],i['subject_ref']) for i in I if i['subject_type']=='receipt' and i['subject_ref'] not in tree])
settled=set(L['_settled']['statuses'])
w_settled=sum(len(c['witnesses']) for c in cl if c['status'] in settled); w_open=sum(len(c['witnesses']) for c in cl if c['status'] not in settled)
print('WITNESSES edges: from settled claims',w_settled,'(outcome per contract: pass of that obligation) | from unsettled',w_open,'(outcome not-run/unknown)')
print('REFUTED witnesses',sum(len(c['witnesses']) for c in cl if c['status']=='REFUTED'))
# supersedes prose / id
sup=[(c['claim_id'],c['supersedes']) for c in cl if 'supersedes' in c]
flat=[(a,t) for a,v in sup for t in (v if isinstance(v,list) else [v])]
print('supersedes items',len(flat),'exact id',sum(1 for _,t in flat if t in ids),'prose w/ id',sum(1 for _,t in flat if t not in ids and any(x in ids for x in re.findall(r'[A-Z][A-Z0-9]*(?:-[A-Z0-9.]+)+',t))),'prose no id',sum(1 for _,t in flat if t not in ids and not any(x in ids for x in re.findall(r'[A-Z][A-Z0-9]*(?:-[A-Z0-9.]+)+',t))))
sb=[(c['claim_id'],t) for c in cl if 'superseded_by' in c for t in (c['superseded_by'] if isinstance(c['superseded_by'],list) else [c['superseded_by']])]
print('superseded_by items',len(sb),'exact id',sum(1 for _,t in sb if t in ids),[t for _,t in sb if t not in ids])
# symmetric check: A.superseded_by=B  <=> B.supersedes=A ?
sup_pairs={(a,t) for a,t in flat if t in ids}; sb_pairs={(t,a) for a,t in sb if t in ids}
print('supersedes pairs',len(sup_pairs),'superseded_by pairs (inverted)',len(sb_pairs),'agree both ways',len(sup_pairs&sb_pairs),'only in supersedes',len(sup_pairs-sb_pairs),'only in superseded_by',len(sb_pairs-sup_pairs))
# assumptions free text lid: how many would need the h. fallback (length>120 after encoding or unspellable)
SAFE=re.compile(r'[A-Za-z0-9._/@+~#:-]')
def enc(s): return ''.join(ch if SAFE.match(ch) and ch!='%' else ''.join('%%%02X'%b for b in ch.encode()) for ch in s)
fa=[a for c in cl for a in c['assumptions']]; print('free-text assumptions',len(fa),'distinct',len(set(fa)),'encoded>120 → h. fallback',sum(1 for a in set(fa) if len(enc(a))>120))
# receipts: established/retyped/broken per round
import os
tot=collections.Counter()
for f in sorted(os.listdir('pin/mosaic/receipts')):
    D=json.load(open('pin/mosaic/receipts/'+f)); inv=D.get('invariants',{})
    for k in ('established','retyped','broken','demoted','opened','refuted','withdrawn'):
        v=inv.get(k); 
        if isinstance(v,list): tot[k]+=len(v)
print('receipt invariants list totals over 20 receipts',dict(tot))
est=[x for f in os.listdir('pin/mosaic/receipts') for x in (json.load(open('pin/mosaic/receipts/'+f)).get('invariants',{}).get('established') or []) if isinstance(x,str)]
print('established ids resolve',sum(1 for x in est if x in ids),'/',len(est), 'unresolved sample',[x for x in est if x not in ids][:6])
ret=[x for f in os.listdir('pin/mosaic/receipts') for x in (json.load(open('pin/mosaic/receipts/'+f)).get('invariants',{}).get('retyped') or [])]
print('retyped shapes',collections.Counter(type(x).__name__ for x in ret), ret[:2])
