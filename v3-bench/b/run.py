#!/usr/bin/env python3
"""V3-1 (b) — run the systems over the FROZEN dataset (PREDECLARATION.md "Systems").

  run.py rules    R-cons and R-recency (local)                         -> preds_rules.json
  run.py jev      one Jev `choice` over the 8 labels for every item    -> jev_raw.jsonl
  run.py judge    blind task file for the Claude text judge            -> judge/tasks.json

Refuses to run unless dataset.jsonl matches dataset_manifest.json. Every item is asked the same question;
the split only matters to score.py (region and tau are chosen on tune, then frozen, then test is scored).
The OpenRouter key comes from $OPENROUTER_API_KEY or ~/.config/alphapiler/openrouter.key and is never printed.
"""
import hashlib, json, os, random, re, sys, time, urllib.request

HOME = os.path.expanduser("~")
B = f"{HOME}/.graphonomous/v3-bench/b"
SEED = 20260928
JEV_URL, JEV_MODEL = "https://openrouter.ai/api/v1/systemone", "typesafe/jev-1.13"
DEFS = {
    "duplicate": "B states the same proposition as A",
    "refines": "B narrows, qualifies or extends A, and A still stands",
    "supersedes": "B replaces A as the current statement; A is withdrawn",
    "contradicts": "A and B cannot both hold, and neither is marked as replacing the other",
    "evidence_for": "B reports a measurement or finding that supports A",
    "evidence_against": "B reports a measurement or finding against A, without stating a replacement claim",
    "scope_disjoint": "similar wording, but a different subject or scope: they are not about the same thing",
    "unrelated": "no meaningful relation",
}
SECRET = re.compile(r"sk-[A-Za-z0-9_-]{20,}|sk-or-v1-[a-f0-9]{20,}|ghp_[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16}|"
                    r"eyJ[A-Za-z0-9_-]{20,}\.|-----BEGIN [A-Z ]*PRIVATE KEY|password\s*[:=]\s*\S{6,}", re.I)
STOP = set("""a an and are as at be by for from has have how i in into is it its of on or that the this to was
were what when where which who why will with not no do does did we our you your via vs per""".split())

def frozen():
    man = json.load(open(f"{B}/dataset_manifest.json"))
    if hashlib.sha256(open(f"{B}/dataset.jsonl", "rb").read()).hexdigest() != man["dataset_sha256"]:
        sys.exit("dataset.jsonl does not match its frozen manifest")
    return [json.loads(l) for l in open(f"{B}/dataset.jsonl")]

def toks(s):
    return {t for t in re.findall(r"[a-z0-9]+", s.lower()) if len(t) > 1 and t not in STOP}

def cmd_rules():
    out = {}
    for it in frozen():
        ta, tb = toks(it["a"]), toks(it["b"])
        j = len(ta & tb) / len(ta | tb) if ta | tb else 0.0
        cons = "duplicate" if j >= 0.8 else "unrelated" if j <= 0.1 else "abstain"
        newer = not (it.get("a_date") and it.get("b_date") and it["b_date"] <= it["a_date"])
        out[it["id"]] = {"jaccard": round(j, 4), "R-cons": cons,
                         "R-recency": "supersedes" if (j >= 0.3 and newer) else cons}
    json.dump(out, open(f"{B}/preds_rules.json", "w"), indent=1)
    print(f"rules: {len(out)} items")

def state_of(it):
    ad = f", dated {it['a_date']}" if it.get("a_date") else ""
    bd = f", dated {it['b_date']}" if it.get("b_date") else ""
    return (f"Two claims from the working notes of a software project, both about: {it['scope']}\n\n"
            f"Claim A (the older claim{ad}):\n{it['a']}\n\nClaim B (the newer claim{bd}):\n{it['b']}")

def cmd_jev():
    key = os.environ.get("OPENROUTER_API_KEY")
    kp = f"{HOME}/.config/alphapiler/openrouter.key"
    key = key or (open(kp).read().strip() if os.path.exists(kp) else None)
    if not key:
        sys.exit("no OpenRouter key")
    items = frozen()
    done = set()
    rawp = f"{B}/jev_raw.jsonl"
    if os.path.exists(rawp):
        done = {json.loads(l)["id"] for l in open(rawp)}
    with open(rawp, "a") as raw:
        for it in items:
            if it["id"] in done:
                continue
            keys = list(DEFS); random.Random(f"{SEED}:jev:{it['id']}").shuffle(keys)
            body = {"model": JEV_MODEL, "state": state_of(it), "questions": {"relation": {
                "type": "choice", "instructions": "How does claim B relate to claim A?",
                "criteria": {k: DEFS[k] for k in keys}}}}
            payload = json.dumps(body)
            if SECRET.search(payload):
                sys.exit(f"ABORT: secret-shaped text in the payload for {it['id']}")
            for attempt in (1, 2, 3):
                t0 = time.time()
                try:
                    req = urllib.request.Request(JEV_URL, data=payload.encode(), method="POST", headers={
                        "Authorization": f"Bearer {key}", "Content-Type": "application/json"})
                    with urllib.request.urlopen(req, timeout=120) as r:
                        j = json.loads(r.read())
                    break
                except Exception as e:
                    if attempt == 3:
                        sys.exit(f"Jev failed on {it['id']}: {e}")
                    time.sleep(3 * attempt)
            ans = j["answers"]["relation"]
            raw.write(json.dumps({"id": it["id"], "ms": round((time.time() - t0) * 1000), "choice": ans.get("choice"),
                                  "confidence": ans.get("confidence"), "probabilities": ans.get("probabilities"),
                                  "usage": j.get("usage")}) + "\n")
            raw.flush()
    print(f"jev: {sum(1 for _ in open(rawp))} answers in {rawp}")

def cmd_judge():
    items = frozen()
    rnd = random.Random(f"{SEED}:judge"); rnd.shuffle(items)
    os.makedirs(f"{B}/judge", mode=0o700, exist_ok=True)
    json.dump({"labels": DEFS, "items": [{"id": i["id"], "scope": i["scope"], "a": i["a"], "b": i["b"],
                                           "a_date": i.get("a_date"), "b_date": i.get("b_date")} for i in items]},
              open(f"{B}/judge/tasks.json", "w"), indent=1)
    print(f"judge tasks: {len(items)}")

{"rules": cmd_rules, "jev": cmd_jev, "judge": cmd_judge}[sys.argv[1]]()
