"""Prints how a bot party fares at each tier -- a quick look when tuning engine.CFG.  python3 balance_probe.py"""
import sys, random, json
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))
src = open(Path(__file__).parent / "test_engine.py").read().split("# ---- a dungeon run can be won")[0]
src = src.replace("Path(__file__)", "Path(%r)" % str(Path(__file__).parent / "test_engine.py"))
exec(src)
for tier, n, realm, kind in [(1, 1, 0, "run"), (3, 3, 3, "run"), (5, 4, 4, "run"), (4, 6, 4, "raid"), (7, 8, 6, "raid")]:
    wins = 0
    ts = []
    downs = []
    for seed in range(6):
        inst = engine.Instance(1, kind, tier, tier * 5, chars(n, realm=realm, step=5), data, rng=random.Random(seed))
        run(inst, 1800, fighter)
        wins += inst.result == "won"
        ts.append(round(inst.t))
        downs.append(sum(m.downs for m in inst.members.values()))
    print(kind, "tier", tier, "party", n, "wins", wins, "/6  seconds", ts, " downs", downs)
