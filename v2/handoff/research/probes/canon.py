import json,sys,hashlib
for f in sys.argv[1:]:
    d=json.load(open(f))
    s=json.dumps(d,sort_keys=True,separators=(',',':'),ensure_ascii=False)
    b=s.encode('utf-8'); print(hashlib.sha256(b).hexdigest(), len(b), f.split('/')[-1])
