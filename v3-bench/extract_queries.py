#!/usr/bin/env python3
"""V3-1 (a), step 1 — the questions sessions actually asked Graphonomous v1.

Walks Claude Code transcripts (default ~/.claude/projects/-home-travis-ProjectAmp2) and collects every
retrieve query sent to the v1 MCP server: the v0.4 machine form (`…graphonomous__retrieve`, action
"context"/"episodic"/"procedural") and the older flat tool (`…graphonomous__retrieve_context`).

Writes <out>/queries.jsonl — one row per distinct query text, with first/last timestamp, how many times it
was asked, and in how many sessions. Private data: <out> must be outside any public repository.

Usage: extract_queries.py [--root DIR] [--out DIR]
"""
import argparse, json, os, re, sys

HOME = os.path.expanduser("~")
ap = argparse.ArgumentParser()
ap.add_argument("--root", default=f"{HOME}/.claude/projects/-home-travis-ProjectAmp2")
ap.add_argument("--out", default=f"{HOME}/.graphonomous/v3-bench")
a = ap.parse_args()

NAME = re.compile(r"graphonomous__(retrieve|retrieve_context)$")
rows, files, calls = {}, 0, 0
for dirpath, _, names in os.walk(a.root):
    for n in names:
        if not n.endswith(".jsonl"):
            continue
        p = os.path.join(dirpath, n)
        with open(p, "rb") as f:
            if b"graphonomous__retrieve" not in f.read():
                continue
        files += 1
        session = n[:-6]
        for line in open(p, encoding="utf-8", errors="replace"):
            if "graphonomous__retrieve" not in line:
                continue
            try:
                ev = json.loads(line)
            except ValueError:
                continue
            content = (ev.get("message") or {}).get("content")
            if not isinstance(content, list):
                continue
            for b in content:
                if b.get("type") != "tool_use" or not NAME.search(b.get("name", "")):
                    continue
                inp = b.get("input") or {}
                action = inp.get("action", "context")
                q = (inp.get("query") or "").strip()
                if not q or action not in ("context", "episodic", "procedural"):
                    continue
                calls += 1
                key = " ".join(q.split()).lower()
                r = rows.setdefault(key, {"query": q, "asked": 0, "sessions": set(),
                                          "first": ev.get("timestamp"), "last": ev.get("timestamp")})
                r["asked"] += 1
                r["sessions"].add(session)
                t = ev.get("timestamp")
                if t and (not r["first"] or t < r["first"]): r["first"] = t
                if t and (not r["last"] or t > r["last"]): r["last"] = t

os.makedirs(a.out, mode=0o700, exist_ok=True)
out = os.path.join(a.out, "queries.jsonl")
with open(out, "w") as f:
    for i, r in enumerate(sorted(rows.values(), key=lambda r: r["first"] or "")):
        f.write(json.dumps({"qid": f"q{i:03d}", "query": r["query"], "asked": r["asked"],
                            "sessions": len(r["sessions"]), "first": r["first"], "last": r["last"]}) + "\n")
print(f"{files} transcript files with retrieve calls · {calls} retrieve calls · {len(rows)} distinct queries → {out}",
      file=sys.stderr)
