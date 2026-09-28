#!/usr/bin/env python3
"""V3-1 (a), step 4 — score the systems against the blind labels and apply PREDECLARATION.md's rule.

Gains are 2^grade − 1 (grade 0/1/2), discount log2(rank + 1); unpooled files grade 0. A query with no
grade ≥ 1 in its pool is excluded from every mean; a query with no grade 2 is excluded from MRR only.
Writes <out>/results.json (ids and numbers only) and prints the table.

Usage: score.py [--out DIR]
"""
import argparse, json, math, os, random, statistics as st, sys

HOME = os.path.expanduser("~")
ap = argparse.ArgumentParser()
ap.add_argument("--out", default=f"{HOME}/.graphonomous/v3-bench")
a = ap.parse_args()
SEED, B_RESAMPLES, MARGIN = 20260928, 10000, 0.05

R = json.load(open(os.path.join(a.out, "rankings.json")))["rankings"]
labels = {}
for qid in R:
    task = json.load(open(os.path.join(a.out, "label_tasks", f"{qid}.json")))
    lab = json.load(open(os.path.join(a.out, "labels", f"{qid}.json")))["labels"]
    want = {c["file"] for c in task["candidates"]}
    if set(lab) != want or any(v.get("grade") not in (0, 1, 2) for v in lab.values()):
        sys.exit(f"{qid}: labels do not cover the pool exactly once with grades 0/1/2")
    labels[qid] = {f: v["grade"] for f, v in lab.items()}

def ndcg(rank, g, k=5):
    dcg = sum((2 ** g.get(f, 0) - 1) / math.log2(i + 2) for i, f in enumerate(rank[:k]))
    ideal = sorted(g.values(), reverse=True)[:k]
    idcg = sum((2 ** x - 1) / math.log2(i + 2) for i, x in enumerate(ideal))
    return dcg / idcg if idcg else None
def mrr(rank, g, k=10):
    if 2 not in g.values():
        return None
    return next((1 / (i + 1) for i, f in enumerate(rank[:k]) if g.get(f, 0) == 2), 0.0)
def recall(rank, g, k=10):
    rel = {f for f, x in g.items() if x >= 1}
    return len(rel & set(rank[:k])) / len(rel) if rel else None

systems = sorted(next(iter(R.values())))
scored = [q for q in sorted(R) if any(x >= 1 for x in labels[q].values())]
per = {s: {q: {"ndcg5": ndcg(R[q][s], labels[q]), "mrr10": mrr(R[q][s], labels[q]),
               "recall10": recall(R[q][s], labels[q])} for q in scored} for s in systems}
def mean(s, m):
    v = [per[s][q][m] for q in scored if per[s][q][m] is not None]
    return (sum(v) / len(v)) if v else None
summary = {s: {m: mean(s, m) for m in ("ndcg5", "mrr10", "recall10")} for s in systems}

def paired(x, y):
    d = [per[x][q]["ndcg5"] - per[y][q]["ndcg5"] for q in scored]
    rnd = random.Random(SEED)
    boots = sorted(sum(rnd.choice(d) for _ in d) / len(d) for _ in range(B_RESAMPLES))
    lo, hi = boots[int(0.025 * B_RESAMPLES)], boots[int(0.975 * B_RESAMPLES) - 1]
    m = sum(d) / len(d)
    return {"a": x, "b": y, "mean_diff": m, "ci95": [lo, hi],
            "wins": sum(v > 1e-9 for v in d), "ties": sum(abs(v) <= 1e-9 for v in d), "losses": sum(v < -1e-9 for v in d),
            "passes_rule": m >= MARGIN and lo > 0}

base = max(("S1_index", "S2_grep"), key=lambda s: summary[s]["ndcg5"])
f1 = paired("S4_bm25_jev", base)
f2 = paired("S4_bm25_jev", "S3_bm25")
extra = [paired("S5_jev_all", base), paired("S3_bm25", base), paired("S5_jev_all", "S4_bm25_jev")]

# Jev's stated confidence vs what the blind labels say its top pick was worth
jev = [json.loads(l) for l in open(os.path.join(a.out, "jev_raw.jsonl"))]
calib = {}
for tag in ("S4", "S5"):
    rows = []
    for r in jev:
        qid, t = r["tag"].split(":")
        if t != tag or qid not in scored:
            continue
        pick = r["labels"][r["choice"]]
        rows.append((float(r["probabilities"][r["choice"]]), labels[qid].get(pick, 0)))
    calib[tag] = {"n": len(rows), "mean_top_probability": st.mean(p for p, _ in rows),
                  "top_pick_grade2_rate": sum(g == 2 for _, g in rows) / len(rows),
                  "top_pick_grade_ge1_rate": sum(g >= 1 for _, g in rows) / len(rows)}

grades = [x for q in scored for x in labels[q].values()]
out = {"queries_total": len(R), "queries_scored": len(scored),
       "excluded_no_relevant": sorted(set(R) - set(scored)),
       "judgments": sum(len(v) for v in labels.values()),
       "grade_counts": {g: sum(1 for x in grades if x == g) for g in (0, 1, 2)},
       "summary": summary, "baseline": base, "F1": f1, "F2": f2, "reported": extra, "jev_confidence": calib,
       "per_query": per}
json.dump(out, open(os.path.join(a.out, "results.json"), "w"), indent=1)

f = lambda v: "—" if v is None else f"{v:.3f}"
print(f"queries scored {len(scored)}/{len(R)} · judgments {out['judgments']} · grades {out['grade_counts']}")
print(f"{'system':14} nDCG@5  MRR@10  R@10")
for s in systems:
    print(f"{s:14} {f(summary[s]['ndcg5'])}   {f(summary[s]['mrr10'])}   {f(summary[s]['recall10'])}")
print(f"baseline B = {base}")
for name, p in (("F1  S4 − B", f1), ("F2  S4 − S3", f2)) + tuple((f"    {p['a'][:2]} − {p['b'][:2]}", p) for p in extra):
    print(f"{name}: {p['mean_diff']:+.3f}  95% CI [{p['ci95'][0]:+.3f}, {p['ci95'][1]:+.3f}]  "
          f"W/T/L {p['wins']}/{p['ties']}/{p['losses']}  rule {'PASS' if p['passes_rule'] else 'not met'}")
for t, c in calib.items():
    print(f"Jev {t}: mean top-pick probability {c['mean_top_probability']:.2f} · top pick grade 2 in "
          f"{c['top_pick_grade2_rate']:.0%} · grade ≥ 1 in {c['top_pick_grade_ge1_rate']:.0%} (n={c['n']})")
