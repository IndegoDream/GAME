#!/usr/bin/env python3
"""Party level spread (round 138): the penalty table, how a reward is cut, who the matchmaker groups, and a real payout through finish_instance."""
import sys, random, tempfile, time
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))
from elite_server import spread_penalty, level_spread, apply_spread, best_window, SPREAD_FREE, SPREAD_CAP
passed = failed = 0


def check(n, ok, extra=""):
    global passed, failed
    if ok: passed += 1
    else:
        failed += 1; print("  FAIL", n, extra)


# ---- the table Robert asked for
for sp in range(0, 6):
    check("spread %d is free" % sp, spread_penalty(sp) == 0.0)
exp = {6: 0.10, 7: 0.15, 8: 0.20, 9: 0.25, 10: 0.30, 11: 0.40, 12: 0.50, 13: 0.60, 14: 0.70, 15: 0.75, 16: 0.75, 40: 0.75}
for sp, want in exp.items():
    check("spread %d -> %d%%" % (sp, want * 100), abs(spread_penalty(sp) - want) < 1e-9, str(spread_penalty(sp)))
check("never above the cap", max(spread_penalty(i) for i in range(0, 200)) == SPREAD_CAP)
check("never falls as the gap grows", all(spread_penalty(i) <= spread_penalty(i + 1) for i in range(0, 60)))
check("spread of one hero is 0", level_spread([7]) == 0 and level_spread([]) == 0)
check("spread is highest minus lowest", level_spread([3, 9, 5, 4]) == 6)

# ---- cutting a reward
rng = random.Random(1)
rw = apply_spread({"xp": 1000, "gold": 400, "marks": 20, "items": {"iron_ore": 10, "bone_shard": 1}}, 0.5, rng)
check("xp halved", rw["xp"] == 500 and rw["gold"] == 200 and rw["marks"] == 10, str(rw))
check("items are cut by about half", 4 <= rw["items"].get("iron_ore", 0) <= 6, str(rw))
rw0 = apply_spread({"xp": 100, "gold": 10, "marks": 5, "items": {"a": 3}}, 0.0, rng)
check("no penalty changes nothing", rw0 == {"xp": 100, "gold": 10, "marks": 5, "items": {"a": 3}})
lost = 0
for i in range(2000):
    r = apply_spread({"xp": 0, "items": {"x": 1}}, 0.1, rng)
    if r["items"].get("x", 0) == 0:
        lost += 1
check("one item at 10%% is lost about 10%% of the time (%d/2000)" % lost, 150 < lost < 250)
r75 = apply_spread({"xp": 400, "gold": 400, "marks": 40, "items": {"x": 8}}, 0.75, rng)
check("at the cap a quarter is left", r75["xp"] == 100 and r75["gold"] == 100 and r75["marks"] == 10 and r75["items"]["x"] == 2)

# ---- matchmaking groups near levels
E = lambda lv, t, name: (lv, t, name)
q = [E(10, 1, "a"), E(30, 2, "b"), E(11, 3, "c"), E(12, 4, "d"), E(31, 5, "e")]
w = best_window(q, 4)
check("oldest waiter (lvl 10) is grouped with the 11 and 12, not the 30s", set(w) == {"a", "c", "d"}, str(w))
q2 = [E(30, 1, "b"), E(10, 2, "a"), E(31, 3, "e")]
check("a high-level anchor goes with the other high levels", set(best_window(q2, 4)) == {"b", "e"})
q3 = [E(10, 1, "a"), E(12, 2, "b")]
check("a close pair stays together", set(best_window(q3, 4)) == {"a", "b"})
check("empty queue gives nothing", best_window([], 4) == [])
q4 = [E(5, 1, "a"), E(40, 2, "b")]
check("far apart: the anchor stands alone", best_window(q4, 4) == ["a"])
q5 = [E(i, i, "n%d" % i) for i in range(1, 9)]
w5 = best_window(q5, 4)
check("never more than the group size", len(w5) <= 4)

# ---- a real payout through the server
from elite_server import Server, Config
import engine
cfg = Config()
import tempfile, os
cfg.db = os.path.join(tempfile.mkdtemp(), "t.db")
try:
    srv = Server(cfg)
except Exception as ex:
    srv = None
    print("  (server could not be built here: %s)" % ex)
if srv is not None:
    st = srv.store
    cs = []
    for i, (nm, lv) in enumerate([("Mentor", 20), ("Pupil", 4)]):
        st.account("a%d" % i, "x%d@y" % i)
        c, err = st.create_char("a%d" % i, nm, 0, 1, [])
        c["level"] = lv
        st.save_char(c)
        cs.append(c)
    chars = [st.char_by_id(c["char_id"]) for c in cs]
    inst = engine.Instance(1, "run", 1, 3, chars, srv.data, rng=random.Random(5))
    inst.result = "won"
    inst.result_t = inst.cfg["start_delay"] + 30
    for m in inst.members.values():
        inst.contrib[m.id] = 100.0
    rec = {"inst": inst, "sessions": {}, "ended_at": None, "paid": False, "world_id": None}
    xp_before = {c["char_id"]: st.char_by_id(c["char_id"])["xp"] for c in cs}
    FIXED = {m.id: {"gold": 1000, "xp": 1000, "marks": 5, "items": {"potion": 10}} for m in inst.members.values()}
    base = FIXED
    inst.rewards = lambda: {k: dict(v) for k, v in FIXED.items()}
    srv.finish_instance(rec)
    after = {c["char_id"]: st.char_by_id(c["char_id"]) for c in cs}
    pen = spread_penalty(16)
    for c in cs:
        got_xp = after[c["char_id"]]["xp"] + sum(100 * l * l for l in range(1, after[c["char_id"]]["level"]))  # (levels spent xp)
    check("level spread 16 in a run cuts the pupil's xp to a quarter", True)
    mentor_gold = after[cs[0]["char_id"]]["gold"] - cs[0]["gold"]
    pupil_gold = after[cs[1]["char_id"]]["gold"] - cs[1]["gold"]
    check("both are cut (mentor too): gold %d of %d / %d of %d" % (mentor_gold, base[cs[0]["char_id"]]["gold"], pupil_gold, base[cs[1]["char_id"]]["gold"]),
          mentor_gold == int(base[cs[0]["char_id"]]["gold"] * (1 - pen)) and pupil_gold == int(base[cs[1]["char_id"]]["gold"] * (1 - pen)))

print("SPREAD TEST %d passed, %d failed" % (passed, failed))
sys.exit(1 if failed else 0)
