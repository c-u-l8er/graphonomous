#!/usr/bin/env python3
"""V3-1 (a), step 3 — build the blind labeling pools (PREDECLARATION.md "Labels").

Pool per query = union of every system's top 10 + S3_bm25's top 20, shuffled with a fixed seed. A task file
carries the query and the candidates (file name + one-line description) and NOTHING about which system
proposed what or at which rank. Writes <out>/label_tasks/<qid>.json.

Usage: pool.py [--out DIR]
"""
import argparse, json, os, random, re

HOME = os.path.expanduser("~")
ap = argparse.ArgumentParser()
ap.add_argument("--out", default=f"{HOME}/.graphonomous/v3-bench")
a = ap.parse_args()

R = json.load(open(os.path.join(a.out, "rankings.json")))["rankings"]
Q = {q["qid"]: q for q in map(json.loads, open(os.path.join(a.out, "queries.jsonl")))}
corpus = os.path.join(a.out, "corpus")
def desc(f):
    m = re.search(r"^description:\s*(.+)$", open(os.path.join(corpus, f), encoding="utf-8").read(), re.M)
    return m.group(1).strip().strip('"').strip("'") if m else ""

td = os.path.join(a.out, "label_tasks"); os.makedirs(td, mode=0o700, exist_ok=True)
sizes = []
for qid, systems in sorted(R.items()):
    pool = set(systems["S3_bm25"][:20])
    for ranking in systems.values():
        pool |= set(ranking[:10])
    pool = sorted(pool); random.Random(f"20260928:pool:{qid}").shuffle(pool)
    json.dump({"qid": qid, "query": Q[qid]["query"], "asked_first": Q[qid]["first"],
               "candidates": [{"file": f, "description": desc(f)} for f in pool]},
              open(os.path.join(td, f"{qid}.json"), "w"), indent=1)
    sizes.append(len(pool))
print(f"{len(sizes)} tasks · pool size min {min(sizes)} / median {sorted(sizes)[len(sizes)//2]} / max {max(sizes)} · "
      f"{sum(sizes)} judgments")
