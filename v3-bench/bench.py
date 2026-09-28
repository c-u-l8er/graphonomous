#!/usr/bin/env python3
"""V3-1 (a), step 2 — run the five systems of PREDECLARATION.md over the real queries.

Snapshots the memory folder into <out>/corpus/ (sha256 manifest), ranks every file for every query with
S1 index · S2 grep · S3 bm25 locally, then S4 bm25+jev · S5 jev-all through Jev on OpenRouter.
Writes <out>/rankings.json and <out>/jev_raw.jsonl. Private data: <out> stays outside any public repo.

Usage: bench.py [--out DIR] [--memory DIR] [--no-jev]
The OpenRouter key is read from $OPENROUTER_API_KEY or ~/.config/alphapiler/openrouter.key and never printed.
"""
import argparse, hashlib, json, math, os, random, re, shutil, sys, time, urllib.request

HOME = os.path.expanduser("~")
ap = argparse.ArgumentParser()
ap.add_argument("--out", default=f"{HOME}/.graphonomous/v3-bench")
ap.add_argument("--memory", default=f"{HOME}/.claude/projects/-home-travis-ProjectAmp2/memory")
ap.add_argument("--no-jev", action="store_true")
a = ap.parse_args()

JEV_URL, JEV_MODEL, SEED, TOPK = "https://openrouter.ai/api/v1/systemone", "typesafe/jev-1.13", 20260928, 20
SECRET = re.compile(r"sk-[A-Za-z0-9_-]{20,}|sk-or-v1-[a-f0-9]{20,}|ghp_[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16}|"
                    r"eyJ[A-Za-z0-9_-]{20,}\.|-----BEGIN [A-Z ]*PRIVATE KEY|password\s*[:=]\s*\S{6,}", re.I)
STOP = set("""a an and are as at be by for from has have how i in into is it its of on or that the this to was
were what when where which who why will with not no do does did we our you your via vs per""".split())

# ---------- corpus snapshot ----------
corpus_dir = os.path.join(a.out, "corpus")
if os.path.exists(corpus_dir):
    shutil.rmtree(corpus_dir)
os.makedirs(corpus_dir, mode=0o700)
index_lines = {}
for line in open(os.path.join(a.memory, "MEMORY.md"), encoding="utf-8"):
    for m in re.finditer(r"\[[^\]]*\]\(([^)]+\.md)\)", line):
        index_lines.setdefault(os.path.basename(m.group(1)), "")
        index_lines[os.path.basename(m.group(1))] += " " + line.strip()
docs, manifest = [], {}
for n in sorted(os.listdir(a.memory)):
    if not n.endswith(".md") or n == "MEMORY.md":
        continue
    raw = open(os.path.join(a.memory, n), encoding="utf-8", errors="replace").read()
    shutil.copy2(os.path.join(a.memory, n), os.path.join(corpus_dir, n))
    manifest[n] = hashlib.sha256(raw.encode()).hexdigest()
    desc = ""
    m = re.search(r"^description:\s*(.+)$", raw, re.M)
    if m:
        desc = m.group(1).strip().strip('"').strip("'")
    body = re.sub(r"^---\n.*?\n---\n", "", raw, count=1, flags=re.S)
    docs.append({"file": n, "desc": desc, "index": index_lines.get(n, "").strip(), "text": desc + "\n" + body})
json.dump({"taken": time.strftime("%Y-%m-%dT%H:%M:%S%z"), "files": manifest,
           "corpus_sha256": hashlib.sha256(json.dumps(manifest, sort_keys=True).encode()).hexdigest()},
          open(os.path.join(a.out, "corpus_manifest.json"), "w"), indent=1)
queries = [json.loads(l) for l in open(os.path.join(a.out, "queries.jsonl"))]
print(f"corpus: {len(docs)} files ({sum(1 for d in docs if d['index'])} with an index line) · {len(queries)} queries",
      file=sys.stderr)

# ---------- tokens ----------
def toks(s):
    s = s.lower()
    out = []
    for w in re.findall(r"[a-z0-9]+(?:[-_.][a-z0-9]+)*", s):
        parts = re.split(r"[-_.]", w)
        for t in ([w] + parts if len(parts) > 1 else [w]):
            if len(t) > 1 and t not in STOP:
                out.append(t)
    return out

N = len(docs)
for d in docs:
    d["tl"] = toks(d["text"]); d["ts"] = set(d["tl"]); d["it"] = set(toks(d["index"] + " " + d["desc"]))
df = {}
for d in docs:
    for t in d["ts"]:
        df[t] = df.get(t, 0) + 1
idf = lambda t: math.log(1 + (N - df.get(t, 0) + 0.5) / (df.get(t, 0) + 0.5))
dfi = {}
for d in docs:
    for t in d["it"]:
        dfi[t] = dfi.get(t, 0) + 1
idfi = lambda t: math.log(1 + (N - dfi.get(t, 0) + 0.5) / (dfi.get(t, 0) + 0.5))
avgdl = sum(len(d["tl"]) for d in docs) / N
tf = [dict() for _ in docs]
for i, d in enumerate(docs):
    for t in d["tl"]:
        tf[i][t] = tf[i].get(t, 0) + 1

def rank(scores, tie=None):  # deterministic: score desc, then the tie-break score desc, then filename
    tie = tie or [0.0] * N
    return [docs[i]["file"] for i in sorted(range(N), key=lambda i: (-scores[i], -tie[i], docs[i]["file"]))]

# S1 and S2 break ties by the BM25 score: a person reading the index or a grep hit list does not pick
# alphabetically, so an alphabetical tie-break would make today's habits look worse than they are.
def s1_index(q):
    qt = set(toks(q)); return rank([sum(idfi(t) for t in qt & d["it"]) for d in docs], bm25_scores(q))
def s2_grep(q):
    qt = set(toks(q)); return rank([sum(idf(t) for t in qt & d["ts"]) for d in docs], bm25_scores(q))
def s3_bm25(q):
    return rank(bm25_scores(q))
def bm25_scores(q, k1=1.2, b=0.75):
    qt = toks(q); sc = []
    for i, d in enumerate(docs):
        L, s = len(d["tl"]), 0.0
        for t in set(qt):
            f = tf[i].get(t, 0)
            if f:
                s += idf(t) * f * (k1 + 1) / (f + k1 * (1 - b + b * L / avgdl))
        sc.append(s)
    return sc

# ---------- Jev ----------
by_file = {d["file"]: d for d in docs}
def option_text(f):
    d = by_file[f]
    return (f[:-3] + ": " + (d["desc"] or d["index"] or "")).replace("\n", " ")[:300]

def state_text(q):
    return ("An AI coding agent working in Travis's ProjectAmp2 repository (a multi-project portfolio: Super, "
            "TRVM, WRL, ComputeDriven, Graphonomous, RRABBIT and others) is about to start a task and asks its "
            f"memory this question:\n\n{q}\n\nEach option is one note in the agent's memory, summarised in one line.")

INSTR = "Which memory note should the agent read first to answer its question?"

def jev(q, files, tag, raw):
    rnd = random.Random(f"{SEED}:{tag}:{q}")
    order = files[:]; rnd.shuffle(order)
    labels = {f"m{i:03d}": f for i, f in enumerate(order)}
    body = {"model": JEV_MODEL, "state": state_text(q),
            "questions": {"note": {"type": "choice", "instructions": INSTR,
                                   "criteria": {k: option_text(f) for k, f in labels.items()}}}}
    payload = json.dumps(body)
    hit = SECRET.search(payload)
    if hit:
        sys.exit(f"ABORT: secret-shaped text in the outgoing payload for {tag} (pattern at offset {hit.start()})")
    for attempt in (1, 2):
        t0 = time.time()
        req = urllib.request.Request(JEV_URL, data=payload.encode(), method="POST",
                                     headers={"Authorization": f"Bearer {KEY}", "Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(req, timeout=120) as r:
                j = json.loads(r.read())
            break
        except Exception as e:
            err = getattr(e, "read", lambda: b"")()[:300]
            if attempt == 2:
                sys.exit(f"Jev failed for {tag}: {e} {err!r}")
            time.sleep(3)
    ms = round((time.time() - t0) * 1000)
    ans = j["answers"]["note"]
    probs = ans.get("probabilities") or {}
    raw.write(json.dumps({"tag": tag, "ms": ms, "options": len(labels), "choice": ans.get("choice"),
                          "confidence": ans.get("confidence"), "probabilities": probs,
                          "labels": labels, "usage": j.get("usage"), "model": j.get("model", JEV_MODEL)}) + "\n")
    # order by Jev's probability; ties (and any label Jev omitted) fall back to the input order `files`
    pos = {f: i for i, f in enumerate(files)}
    return sorted(files, key=lambda f: (-float(probs.get(next(k for k, v in labels.items() if v == f), 0.0)), pos[f])), ms

KEY = None
if not a.no_jev:
    KEY = os.environ.get("OPENROUTER_API_KEY")
    if not KEY:
        kp = f"{HOME}/.config/alphapiler/openrouter.key"
        KEY = open(kp).read().strip() if os.path.exists(kp) else None
    if not KEY:
        sys.exit("no OpenRouter key: set OPENROUTER_API_KEY or use --no-jev")

rankings, lat = {}, []
raw = open(os.path.join(a.out, "jev_raw.jsonl"), "w") if KEY else None
for qr in queries:
    q, qid = qr["query"], qr["qid"]
    r = {"S1_index": s1_index(q), "S2_grep": s2_grep(q), "S3_bm25": s3_bm25(q)}
    if KEY:
        top = r["S3_bm25"][:TOPK]
        re4, ms4 = jev(q, top, f"{qid}:S4", raw)
        r["S4_bm25_jev"] = re4 + r["S3_bm25"][TOPK:]
        # every file, in BM25 order so that probability ties fall back to BM25 rather than the alphabet
        r["S5_jev_all"], ms5 = jev(q, r["S3_bm25"], f"{qid}:S5", raw)
        lat += [ms4, ms5]
        print(f"  {qid}: S4 {ms4} ms · S5 {ms5} ms", file=sys.stderr)
    rankings[qid] = r
if raw:
    raw.close()
json.dump({"systems": sorted(next(iter(rankings.values())).keys()), "rankings": rankings,
           "jev_model": JEV_MODEL if KEY else None, "jev_latency_ms": sorted(lat)},
          open(os.path.join(a.out, "rankings.json"), "w"), indent=1)
print(f"wrote rankings for {len(rankings)} queries · systems {sorted(next(iter(rankings.values())).keys())}",
      file=sys.stderr)
