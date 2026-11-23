#!/usr/bin/env python3
"""Round 182: tools/stats_report.py on made-up players -- a wall on floor 9 must be flagged, smooth floors must not."""
import json, os, sys, tempfile
sys.path.insert(0, os.path.dirname(__file__))
import stats_report as SR
ok = fail = 0
def check(n, c, d=""):
    global ok, fail
    if c: ok += 1
    else:
        fail += 1; print("  FAIL  " + n + ("  [" + str(d) + "]" if d else ""))
tmp = tempfile.mkdtemp()
for p in range(10):
    rows = []
    last = 12 if p < 6 else 9            # four of ten stop at floor 9
    for f in range(1, last + 1):
        rows.append({"k": "enter_level", "f": f, "m": f * 20 + p})
        if f == 9:
            rows += [{"k": "death", "f": 9, "cause": "stone_warden"}] * 3
        elif f % 4 == 0:
            rows.append({"k": "death", "f": f, "cause": "goblin"})
        if f % 5 == 0:
            rows.append({"k": "boss_kill", "f": f, "type": "chief"})
    rows.append({"k": "session_end", "f": last, "sm": 30})
    with open(os.path.join(tmp, "p%02d.jsonl" % p), "w") as fh:
        fh.write("\n".join(json.dumps(r) for r in rows) + "\n")
# a Supabase export too
with open(os.path.join(tmp, "export.json"), "w") as fh:
    json.dump([{"install": "abcdef0123456789", "data": json.dumps({"k": "enter_level", "f": 1, "m": 3})}], fh)
rows = SR.gather([tmp])
t = {r["floor"]: r for r in SR.report(rows)}
check("eleven players (ten files and an export)", len({i for i, _ in rows}) == 11)
check("floor 1 reached by all eleven", t[1]["players"] == 11, t[1])
check("floor 9: thirty falls", t[9]["falls"] == 30, t[9])
check("floor 9 flagged: falls jump", "falls jump" in t[9]["flags"], t[9])
check("floor 9 flagged: players stop here", "players stop here" in t[9]["flags"], t[9])
check("floor 9's top cause named", t[9]["top_causes"].startswith("stone_warden"), t[9])
check("smooth floors are not flagged", all(t[f]["flags"] == "" for f in (1, 2, 3, 5, 6, 7, 10, 11)), {f: t[f]["flags"] for f in t})
check("bosses counted", t[5]["bosses_beaten"] == 10 and t[10]["bosses_beaten"] == 6, (t[5], t[10]))
check("median minutes to reach floor 10", t[10]["median_min_to_reach"] == 202, t[10])
check("sittings that ended counted where they ended", t[9]["sittings_ended"] == 4 and t[12]["sittings_ended"] == 6)
print("STATS REPORT TEST %d passed, %d failed" % (ok, fail))
sys.exit(1 if fail else 0)
