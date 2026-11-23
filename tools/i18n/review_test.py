#!/usr/bin/env python3
"""Round 182: the translation review round trip (export -> a reviewer fills cells -> import)."""
import json, os, subprocess, sys, tempfile
from openpyxl import load_workbook
HERE = os.path.dirname(os.path.abspath(__file__))
ok = fail = 0
def check(n, c, d=""):
    global ok, fail
    if c: ok += 1
    else:
        fail += 1; print("  FAIL  " + n + ("  [" + str(d) + "]" if d else ""))
tmp = tempfile.mkdtemp()
x = os.path.join(tmp, "zh.xlsx")
r = subprocess.run([sys.executable, os.path.join(HERE, "review_export.py"), "zh_CN", x], capture_output=True, text=True)
check("export runs", r.returncode == 0 and os.path.exists(x), r.stderr[-300:])
wb = load_workbook(x)
check("three sheets", wb.sheetnames == ["Read me", "Glossary", "Strings"], wb.sheetnames)
g = wb["Glossary"]
rows = {g.cell(i, 1).value: i for i in range(2, g.max_row + 1)}
check("the glossary names the swarm and alchemy", "The swarm" in rows and "Alchemy" in rows)
check("it counts strings using the current word", int(g.cell(rows["Swarm"], 3).value or 0) > 50, g.cell(rows["Swarm"], 3).value)
g.cell(rows["Swarm"], 6).value = "纳米群"
g.cell(rows["The swarm"], 6).value = "纳米群"
g.cell(rows["Alchemy"], 6).value = "炼丹 / 炼金"          # two choices: refused
s = wb["Strings"]
check("most-seen first: the first rows are short menu words", len(str(s.cell(2, 3).value).split()) <= 4 and s.cell(2, 2).value == 1)
idx = {s.cell(i, 3).value: i for i in range(2, s.max_row + 1)}
k1 = "Synergy -- the swarm and your qi"
k2 = next(k for k in idx if k and "%d" in k and len(k) < 40)
s.cell(idx[k1], 5).value = "协同——纳米群与你的真气（人工）"
s.cell(idx[k2], 5).value = "坏的译文没有占位符"
wb.save(x)
ovd = os.path.join(tmp, "ov")
env = dict(os.environ, REVIEW_OVERRIDE_DIR=ovd)
r = subprocess.run([sys.executable, os.path.join(HERE, "review_import.py"), x, "zh_CN"], capture_output=True, text=True, env=env)
check("import runs", r.returncode == 0, r.stdout[-400:] + r.stderr[-400:])
ov = json.load(open(os.path.join(ovd, "zh_CN.json"), encoding="utf8"))
cat = json.load(open(os.path.join(os.path.dirname(os.path.dirname(HERE)), "data", "i18n", "zh_CN.json"), encoding="utf8"))
check("a hand correction lands as written", ov.get(k1) == "协同——纳米群与你的真气（人工）")
check("a correction that loses %d is refused", k2 not in ov and "refused" in r.stdout)
check("two choices in one cell are refused", "pick one term" in r.stdout)
swapped = [k for k in ov if "swarm" in k.lower() and k != k1]
check("the glossary swaps 蜂群 for 纳米群 across the swarm strings", len(swapped) > 50 and all("蜂群" not in ov[k] for k in swapped), len(swapped))
check("...and only where the English says swarm", all("swarm" in k.lower() for k in ov if k != k1))
check("...keeping each string's placeholders", all(sorted(__import__("re").findall(r"%[+\-0-9.]*[sdf]", k)) == sorted(__import__("re").findall(r"%[+\-0-9.]*[sdf]", ov[k])) for k in ov))
check("strings that didn't use the old word are untouched", all(cat[k] != ov[k] for k in swapped))
print("REVIEW TEST %d passed, %d failed" % (ok, fail))
sys.exit(1 if fail else 0)
