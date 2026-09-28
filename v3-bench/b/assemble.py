#!/usr/bin/env python3
"""V3-1 (b) — assemble and freeze the dataset (PREDECLARATION.md, "Two subsets" and "Splits").

  assemble.py a        merge extract/x*.jsonl into subset A (validate, leakage regex, de-duplicate)
  assemble.py btasks   turn construct/pairs.jsonl into blind grading tasks (no kind, no intended label)
  assemble.py b        keep only B pairs both graders labelled identically; report agreement
  assemble.py freeze   split each subset 40/60 tune/test by source (seed 20260928) and write dataset.jsonl
                       + dataset_manifest.json (sha256); refuses to overwrite an existing freeze

All data lives in ~/.graphonomous/v3-bench/b/ (private). Only counts and hashes are printed.
"""
import hashlib, json, os, random, re, sys

HOME = os.path.expanduser("~")
B = f"{HOME}/.graphonomous/v3-bench/b"
LABELS = ["duplicate", "refines", "supersedes", "contradicts", "evidence_for", "evidence_against",
          "scope_disjoint", "unrelated"]
LEAK = re.compile(r"retract|supersed|\bwrong\b|correct(ed|ion)|falsif|stale|no longer|used to|restat|conflat|"
                  r"orthogonal|still (true|holds|stands)|was replaced|replaces|overturn|previous|earlier|formerly|"
                  r"originally|disagree|confirm", re.I)
SECRET = re.compile(r"sk-[A-Za-z0-9_-]{20,}|sk-or-v1-[a-f0-9]{20,}|ghp_[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16}|"
                    r"eyJ[A-Za-z0-9_-]{20,}\.|-----BEGIN [A-Z ]*PRIVATE KEY|password\s*[:=]\s*\S{6,}", re.I)
SEED = 20260928

def rows(p):
    return [json.loads(l) for l in open(p) if l.strip()]
def norm(s):
    return " ".join(re.findall(r"[a-z0-9]+", s.lower()))
def check_text(it, where):
    bad = [k for k in ("a", "b", "scope") if not isinstance(it.get(k), str) or not it[k].strip()]
    if bad:
        return f"{where}: empty {bad}"
    for k in ("a", "b", "scope"):
        if LEAK.search(it[k]):
            return f"{where}: transition wording in {k}"
        if SECRET.search(it[k]):
            return f"{where}: secret-shaped text in {k}"
    return None

def cmd_a():
    items, dropped, seen = [], {}, set()
    for n in sorted(os.listdir(f"{B}/extract")):
        if not re.fullmatch(r"x\d+\.jsonl", n):
            continue
        for it in rows(f"{B}/extract/{n}"):
            why = check_text(it, it.get("id", "?"))
            if not why and it.get("label") not in LABELS[:7]:
                why = "label outside the author-grounded seven"
            if not why and not (it.get("marker_quote") and it.get("source")):
                why = "no provenance"
            key = (norm(it.get("a", "")), norm(it.get("b", "")))
            if not why and key in seen:
                why = "duplicate item"
            if why:
                dropped[why.split(": ")[-1]] = dropped.get(why.split(": ")[-1], 0) + 1
                continue
            seen.add(key)
            items.append({"id": it["id"], "subset": "A", "label": it["label"], "scope": it["scope"], "a": it["a"],
                          "b": it["b"], "a_date": it.get("a_date"), "b_date": it.get("b_date"),
                          "group": it["source"], "provenance": {"source": it["source"], "line": it.get("line"),
                                                                "marker_quote": it["marker_quote"]}})
    with open(f"{B}/A.jsonl", "w") as f:
        for it in items:
            f.write(json.dumps(it) + "\n")
    per = {l: sum(1 for i in items if i["label"] == l) for l in LABELS[:7]}
    print(f"A: {len(items)} items · per label {per} · dropped {dropped}")

def cmd_btasks():
    pairs = rows(f"{B}/construct/pairs.jsonl")
    ok, dropped = [], {}
    for p in pairs:
        why = check_text(p, p.get("id", "?"))
        if why:
            dropped[why.split(': ')[-1]] = dropped.get(why.split(': ')[-1], 0) + 1
        else:
            ok.append(p)
    rnd = random.Random(f"{SEED}:btasks"); rnd.shuffle(ok)
    tasks = [{"id": p["id"], "scope": p["scope"], "a": p["a"], "b": p["b"], "a_date": p.get("a_date"),
              "b_date": p.get("b_date")} for p in ok]
    json.dump({"labels": LABELS, "items": tasks}, open(f"{B}/grade/tasks.json", "w"), indent=1)
    print(f"B grading tasks: {len(tasks)} (dropped {dropped})")

def cmd_b():
    pairs = {p["id"]: p for p in rows(f"{B}/construct/pairs.jsonl")}
    g = [json.load(open(f"{B}/grade/{n}.json"))["labels"] for n in ("g1", "g2")]
    ids = sorted(set(g[0]) & set(g[1]))
    agree = [i for i in ids if g[0][i]["label"] == g[1][i]["label"] and g[0][i]["label"] in LABELS]
    out = []
    for i in agree:
        p = pairs[i]
        out.append({"id": i, "subset": "B", "label": g[0][i]["label"], "scope": p["scope"], "a": p["a"], "b": p["b"],
                    "a_date": p.get("a_date"), "b_date": p.get("b_date"), "group": p.get("a_source", i),
                    "provenance": {"a_source": p.get("a_source"), "b_source": p.get("b_source"), "kind": p["kind"],
                                   "intended_label": p["intended_label"],
                                   "grader_reasons": [g[0][i].get("reason"), g[1][i].get("reason")]}})
    with open(f"{B}/B.jsonl", "w") as f:
        for it in out:
            f.write(json.dumps(it) + "\n")
    both = len(ids)
    intended = sum(1 for i in agree if pairs[i]["intended_label"] == g[0][i]["label"])
    per = {l: sum(1 for i in out if i["label"] == l) for l in LABELS}
    print(f"B: graded by both {both} · agreed {len(agree)} ({len(agree) / both:.0%}) · agreed label = constructor's "
          f"intended {intended}/{len(agree)} · per label {per}")

def cmd_freeze():
    if os.path.exists(f"{B}/dataset_manifest.json"):
        sys.exit("already frozen: dataset_manifest.json exists")
    items = rows(f"{B}/A.jsonl") + rows(f"{B}/B.jsonl")
    def split(group):
        h = int(hashlib.sha256(f"{SEED}:{group}".encode()).hexdigest(), 16) % 100
        return "tune" if h < 40 else "test"
    for it in items:
        it["split"] = split(it["group"])
    with open(f"{B}/dataset.jsonl", "w") as f:
        for it in items:
            f.write(json.dumps(it, sort_keys=True) + "\n")
    digest = hashlib.sha256(open(f"{B}/dataset.jsonl", "rb").read()).hexdigest()
    counts = {s: {sp: {l: sum(1 for i in items if i["subset"] == s and i["split"] == sp and i["label"] == l)
                       for l in LABELS} for sp in ("tune", "test")} for s in ("A", "B")}
    totals = {s: {sp: sum(counts[s][sp].values()) for sp in ("tune", "test")} for s in ("A", "B")}
    json.dump({"dataset_sha256": digest, "items": len(items), "totals": totals, "counts": counts},
              open(f"{B}/dataset_manifest.json", "w"), indent=1)
    print(f"frozen: dataset_sha256 {digest[:16]}… · totals {totals}")

{"a": cmd_a, "btasks": cmd_btasks, "b": cmd_b, "freeze": cmd_freeze}[sys.argv[1]]()
