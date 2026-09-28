#!/usr/bin/env python3
"""V3-1 (a), context — what sessions actually used for memory: Graphonomous v1 tool calls vs opening a file
in the Claude Code file memory. Counts only; writes <out>/usage.json.

Usage: usage.py [--root DIR] [--memory DIR] [--out DIR]
"""
import argparse, collections, json, os, re

HOME = os.path.expanduser("~")
ap = argparse.ArgumentParser()
ap.add_argument("--root", default=f"{HOME}/.claude/projects/-home-travis-ProjectAmp2")
ap.add_argument("--memory", default=f"{HOME}/.claude/projects/-home-travis-ProjectAmp2/memory")
ap.add_argument("--out", default=f"{HOME}/.graphonomous/v3-bench")
a = ap.parse_args()

GTOOL = re.compile(r"graphonomous__(\w+)$")
mem = os.path.realpath(a.memory) + "/"
g_calls, g_sessions, g_by = 0, set(), collections.Counter()
m_reads, m_bash, m_sessions, m_files = 0, 0, set(), collections.Counter()
months = collections.defaultdict(lambda: [0, 0])  # month -> [graphonomous calls, Read of a memory file]
for dirpath, _, names in os.walk(a.root):
    if os.path.realpath(dirpath).startswith(mem.rstrip("/")):
        continue
    for n in names:
        if not n.endswith(".jsonl"):
            continue
        p, session = os.path.join(dirpath, n), n[:-6]
        for line in open(p, encoding="utf-8", errors="replace"):
            if "tool_use" not in line or ("graphonomous__" not in line and "/memory/" not in line):
                continue
            try:
                ev = json.loads(line)
            except ValueError:
                continue
            content = (ev.get("message") or {}).get("content")
            if not isinstance(content, list):
                continue
            month = (ev.get("timestamp") or "")[:7]
            for b in content:
                if b.get("type") != "tool_use":
                    continue
                m = GTOOL.search(b.get("name", ""))
                if m:
                    g_calls += 1; g_sessions.add(session); months[month][0] += 1
                    g_by[m.group(1) + ":" + str((b.get("input") or {}).get("action", ""))] += 1
                    continue
                inp = b.get("input") or {}
                fp = inp.get("file_path") or ""
                cmd = inp.get("command") or ""
                if b.get("name") == "Read" and os.path.realpath(fp).startswith(mem) and fp.endswith(".md"):
                    m_reads += 1; m_sessions.add(session); m_files[os.path.basename(fp)] += 1; months[month][1] += 1
                elif b.get("name") == "Bash" and mem.rstrip("/") in cmd.replace("~", HOME):
                    m_bash += 1; m_sessions.add(session)
out = {"graphonomous_calls": g_calls, "graphonomous_sessions": len(g_sessions),
       "graphonomous_by_tool_action": dict(g_by.most_common()),
       "memory_file_reads": m_reads, "memory_bash_commands_naming_the_dir": m_bash,
       "memory_sessions": len(m_sessions),
       "memory_files_opened_distinct": len(m_files), "memory_top_files": dict(m_files.most_common(10)),
       "by_month_graphonomous_calls_vs_memory_reads": {k: v for k, v in sorted(months.items()) if k}}
os.makedirs(a.out, mode=0o700, exist_ok=True)
json.dump(out, open(os.path.join(a.out, "usage.json"), "w"), indent=1)
print(json.dumps({k: v for k, v in out.items() if k != "memory_top_files"}, indent=1))
