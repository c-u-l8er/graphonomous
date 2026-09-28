#!/usr/bin/env python3
"""V3-1 (b) — score under the asymmetric cost matrix and apply PREDECLARATION.md's decision rule.

J-gov's region (a set of labels) and tau are chosen on TUNE A only — every label subset x tau in
{0.30, 0.35, ..., 0.95}, minimizing mean cost, ties -> higher tau, then smaller region — then frozen and
applied once to test. Records the sha256 of the cost matrix and of the dataset it scored.
Writes <b>/results.json (ids and numbers only) and prints the tables.
"""
import hashlib, itertools, json, os, random, sys

HOME = os.path.expanduser("~")
B = f"{HOME}/.graphonomous/v3-bench/b"
HERE = os.path.dirname(os.path.abspath(__file__))
SEED, RES = 20260928, 10000

matrix_path = os.path.join(HERE, "cost_matrix.json")
M = json.load(open(matrix_path))
C, LABELS, CAT = M["cost"], M["labels"], M["catastrophic_false_positives"]
matrix_sha = hashlib.sha256(open(matrix_path, "rb").read()).hexdigest()
man = json.load(open(f"{B}/dataset_manifest.json"))
if hashlib.sha256(open(f"{B}/dataset.jsonl", "rb").read()).hexdigest() != man["dataset_sha256"]:
    sys.exit("dataset.jsonl does not match its frozen manifest")
items = [json.loads(l) for l in open(f"{B}/dataset.jsonl")]
rules = json.load(open(f"{B}/preds_rules.json"))
jev = {r["id"]: r for r in map(json.loads, open(f"{B}/jev_raw.jsonl"))}
judge = json.load(open(f"{B}/judge/judge.json"))["labels"] if os.path.exists(f"{B}/judge/judge.json") else {}
missing = [i["id"] for i in items if i["id"] not in jev]
if missing:
    sys.exit(f"{len(missing)} items have no Jev answer")

def jev_top(i):
    p = {k: float(v) for k, v in jev[i]["probabilities"].items()}
    lab = max(LABELS, key=lambda l: (p.get(l, 0.0), -LABELS.index(l)))
    return lab, p.get(lab, 0.0)

def gov(region, tau):
    def f(i):
        lab, p = jev_top(i)
        return lab if (lab in region and p >= tau) else "abstain"
    return f

systems = {
    "ABS": lambda i: "abstain",
    "R-cons": lambda i: rules[i]["R-cons"],
    "R-recency": lambda i: rules[i]["R-recency"],
    "J-raw": lambda i: jev_top(i)[0],
}
if judge:
    systems["C"] = lambda i: judge.get(i, {}).get("label", "abstain") if judge.get(i, {}).get("label") in LABELS + ["abstain"] else "abstain"

def sel(subset, split):
    return [it for it in items if it["subset"] == subset and it["split"] == split]
def cost(it, pred):
    return C[it["label"]][pred]
def mean_cost(xs, f):
    return sum(cost(it, f(it["id"])) for it in xs) / len(xs) if xs else None

# ---- tune J-gov on TUNE A only ----
tuneA = sel("A", "tune")
taus = [round(0.30 + 0.05 * k, 2) for k in range(14)]
best = None
for r in range(0, len(LABELS) + 1):
    for region in itertools.combinations(LABELS, r):
        for tau in taus:
            c = mean_cost(tuneA, gov(set(region), tau))
            key = (round(c, 12), -tau, len(region), region)
            if best is None or key < best[0]:
                best = (key, set(region), tau, c)
_, REGION, TAU, TUNE_COST = best
systems["J-gov"] = gov(REGION, TAU)

def report(xs, f):
    preds = [(it, f(it["id"])) for it in xs]
    answered = [(it, p) for it, p in preds if p != "abstain"]
    conf = {t: {p: 0 for p in LABELS + ["abstain"]} for t in LABELS}
    for it, p in preds:
        conf[it["label"]][p] += 1
    catas = {l: sum(1 for it, p in answered if p == l and it["label"] != l) for l in CAT}
    # AMENDMENT_1: per-label (macro) cost, over labels with >= 5 items here, so a majority label cannot decide alone
    per_label = {l: sum(cost(it, p) for it, p in preds if it["label"] == l) / n
                 for l in LABELS for n in [sum(1 for it in xs if it["label"] == l)] if n}
    macro_labels = [l for l in per_label if sum(1 for it in xs if it["label"] == l) >= 5]
    reversals = sum(1 for it, p in answered if {it["label"], p} == {"evidence_for", "evidence_against"})
    support_for_rejection = sum(1 for it, p in answered if it["label"] in ("supersedes", "contradicts") and p == "evidence_for")
    return {"n": len(xs), "mean_cost": mean_cost(xs, f),
            "macro_cost": (sum(per_label[l] for l in macro_labels) / len(macro_labels)) if macro_labels else None,
            "macro_labels": macro_labels, "per_label_cost": per_label,
            "evidence_direction_reversals": reversals, "support_asserted_for_rejected_claim": support_for_rejection,
            "coverage": len(answered) / len(xs) if xs else None,
            "accuracy_answered": (sum(1 for it, p in answered if p == it["label"]) / len(answered)) if answered else None,
            "catastrophic": catas, "catastrophic_total": sum(catas.values()), "confusion": conf}

def paired(xs, f, g):
    d = [cost(it, f(it["id"])) - cost(it, g(it["id"])) for it in xs]
    rnd = random.Random(SEED)
    boots = sorted(sum(rnd.choice(d) for _ in d) / len(d) for _ in range(RES))
    return {"mean": sum(d) / len(d), "ci95": [boots[int(0.025 * RES)], boots[int(0.975 * RES) - 1]]}

out = {"matrix_sha256": matrix_sha, "dataset_sha256": man["dataset_sha256"], "jev_gov": {
    "region": sorted(REGION), "tau": TAU, "tune_A_cost": TUNE_COST}, "subsets": {}}
for subset in ("A", "B"):
    for split in ("tune", "test"):
        xs = sel(subset, split)
        if not xs:
            continue
        rep = {s: report(xs, f) for s, f in systems.items()}
        cmp = {f"J-gov - {s}": paired(xs, systems["J-gov"], systems[s]) for s in systems if s != "J-gov"}
        out["subsets"][f"{subset}-{split}"] = {"systems": rep, "paired": cmp}

tA, tB = out["subsets"].get("A-test"), out["subsets"].get("B-test")
c1 = tA["paired"]["J-gov - ABS"]["ci95"][1] < 0
c2 = tA["systems"]["J-gov"]["catastrophic"]["supersedes"] == 0
c3 = (tB is None) or tB["systems"]["J-gov"]["mean_cost"] <= tB["systems"]["ABS"]["mean_cost"]
c4 = len(REGION) > 0
c5 = tA["systems"]["J-gov"]["macro_cost"] <= tA["systems"]["ABS"]["macro_cost"]  # AMENDMENT_1
out["decision"] = {"1_cost_below_abstain_A_test": c1, "2_zero_false_supersedes_A_test": c2,
                   "3_not_worse_than_abstain_B_test": c3, "4_region_nonempty": c4,
                   "5_macro_cost_not_worse_than_abstain_A_test": c5,
                   "v2_gains_a_decider": c1 and c2 and c3 and c4 and c5}
json.dump(out, open(f"{B}/results.json", "w"), indent=1)

f3 = lambda v: "—" if v is None else f"{v:.3f}"
print(f"matrix {matrix_sha[:12]} · dataset {man['dataset_sha256'][:12]} · J-gov frozen on tune A: region "
      f"{sorted(REGION) or '∅'} tau {TAU} (tune cost {TUNE_COST:.3f})")
for k, v in out["subsets"].items():
    print(f"\n{k}  (n={next(iter(v['systems'].values()))['n']})")
    print(f"  {'system':10} cost   macro  coverage acc|ans false sup/con/dup  ev-reversals")
    for s, r in v["systems"].items():
        c = r["catastrophic"]
        print(f"  {s:10} {f3(r['mean_cost'])}  {f3(r['macro_cost'])}  {f3(r['coverage'])}    {f3(r['accuracy_answered'])}   "
              f"{c['supersedes']}/{c['contradicts']}/{c['duplicate']}            {r['evidence_direction_reversals']}")
    for s, p in v["paired"].items():
        print(f"  {s:18} {p['mean']:+.3f}  CI [{p['ci95'][0]:+.3f}, {p['ci95'][1]:+.3f}]")
print("\ndecision:", json.dumps(out["decision"]))
