"""Q2 witness detail: dump every distinct witness path at d217ee2 and check the `§n` anchor exists in the file; also arguments.json evidence_refs {kind:witness,path}."""
import json,re,subprocess,os,collections
G=['git','-C',os.path.expanduser('~/.invariant-factory/canonical.git')]
L=json.load(open('pin/CLAIM_LEDGER.json')); tree=set(l.split('\t')[1] for l in open('pin/ls-tree.txt').read().splitlines())
os.makedirs('pin/wit',exist_ok=True)
paths=set(); refs=[]
for c in L['claims']:
    for w in c['witnesses']:
        m=re.fullmatch(r'(\S+)(?:\s+§(\S+))?',w); paths.add(m.group(1)); refs.append((c['claim_id'],m.group(1),m.group(2),c['status']))
for p in sorted(paths):
    fn='pin/wit/'+p.replace('/','__')
    if not os.path.exists(fn): open(fn,'wb').write(subprocess.run(G+['show',f'd217ee2:{p}'],capture_output=True).stdout)
ok=miss=0; missing=[]; anchors_forms=collections.Counter()
for cid,p,s,st in refs:
    if s is None: continue
    txt=open('pin/wit/'+p.replace('/','__'),encoding='utf8',errors='replace').read()
    anchors_forms[re.sub(r'\d+','n',s)]+=1
    if re.search(r'§\s*'+re.escape(s)+r'(?![\d.])',txt): ok+=1
    else: miss+=1; missing.append((cid,p,s))
print('distinct witness paths',len(paths),'all in tree',all(p in tree for p in paths))
print('section refs',ok+miss,'anchor found',ok,'anchor MISSING',miss,missing)
print('section forms',dict(anchors_forms))
ext=collections.Counter(os.path.splitext(p)[1] for p in paths); print('extensions',dict(ext))
# witness lid shapes the contract would mint: witness:factory:<path>#<section>
lids=set(f'witness:factory:{p}'+(f'#{s}' if s else '') for _,p,s,_ in refs); print('distinct witness lids (path#section)',len(lids),'path-only lids',len(set(p for _,p,s,_ in refs if not s)))
# outcome by status of the citing claim
print('witness refs by citing status',dict(collections.Counter(st for *_,st in refs)))
# a path cited both bare and with a section?
both=set(p for _,p,s,_ in refs if s)&set(p for _,p,s,_ in refs if not s); print('paths cited both bare and with §',len(both),sorted(both)[:10])
# arguments.json evidence_refs witness paths
A=json.load(open('pin/mosaic/arguments.json'))['arguments']
wp=[e['path'] for a in A for e in a['evidence_refs'] if e.get('kind')=='witness']; print('argument witness paths',len(wp),'in tree',sum(1 for p in wp if p.split(' ')[0] in tree),'with §',sum(1 for p in wp if '§' in p))
print('argument witness examples',wp[:5])
# LOCAL_RE check for lid grammar on paths + '§' sections
LOCAL=re.compile(r'^[A-Za-z0-9._/@+~#%:-]+$')
bad=[p for p in paths if not LOCAL.match(p)]; print('witness paths failing LOCAL_RE',bad)
secs=set(s for _,_,s,_ in refs if s); print('section tokens failing LOCAL_RE',[s for s in secs if not LOCAL.match(s)], 'distinct sections',len(secs))
