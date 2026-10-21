"""Plain asserts: python3 test_engine.py   (no network, no pytest)"""
import json, math, random, sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))
import engine
from store import Store

DATA = Path(__file__).parent.parent.parent / "data"
data = {"enemies": json.loads((DATA / "enemies.json").read_text()), "items": json.loads((DATA / "items.json").read_text())}
passed = failed = 0


def check(name, ok, detail=""):
    global passed, failed
    if ok:
        passed += 1
    else:
        failed += 1
        print("  FAIL ", name, detail)


def chars(n, realm=3, step=5):
    return [{"char_id": i + 1, "name": "P%d" % (i + 1), "realm": realm, "step": step, "level": 1} for i in range(n)]


def run(inst, secs, bot=None):
    for _ in range(int(secs / engine.TICK)):
        if bot:
            bot(inst)
        inst.tick()
        if inst.result:
            break


def fighter(inst, aggressive=True, dodge=True):
    swing = int(inst.t / engine.TICK) % 4 == 0          # about two and a half swings a second
    """a bot: walk to the nearest foe and hit it as hard as it plausibly can; step out of telegraphed circles"""
    for m in inst.members.values():
        if not m.alive or m.left:
            continue
        foes = [f for f in inst.foes.values() if f.alive]
        tx, tz = m.x, m.z
        if dodge:
            for h in inst.hazards:
                if h.kind == "circle" and math.hypot(m.x - h.x, m.z - h.z) < h.r + 0.5:
                    d = math.hypot(m.x - h.x, m.z - h.z) or 1
                    tx, tz = m.x + (m.x - h.x) / d * 3, m.z + (m.z - h.z) / d * 3
                elif h.kind == "safe" and h.zones:
                    zx, zz, zr = min(h.zones, key=lambda z: math.hypot(m.x - z[0], m.z - z[1]))
                    tx, tz = zx, zz
        if (tx, tz) == (m.x, m.z) and foes and aggressive:
            f = min(foes, key=lambda f: math.hypot(m.x - f.x, m.z - f.z))
            d = math.hypot(f.x - m.x, f.z - m.z)
            if d > 3:
                tx, tz = m.x + (f.x - m.x) / d * 0.9, m.z + (f.z - m.z) / d * 0.9
        inst.move(m.id, tx, tz)
        if foes and aggressive and swing:
            f = min(foes, key=lambda f: math.hypot(m.x - f.x, m.z - f.z))
            r, s = m.rank()
            inst.hit(m.id, f.id, engine.hit_base(r, s, inst.depth) * 1.0)


# ---- a dungeon run can be won by a party playing sensibly
random.seed(1)
inst = engine.Instance(1, "run", 3, 15, chars(3), data, rng=random.Random(5))
check("run starts counting down", inst.phase == "countdown")
run(inst, 400, fighter)
check("a sensible party wins a tier-3 run", inst.result == "won", "result=%s t=%.0f room=%d" % (inst.result, inst.t, inst.room))
check("it takes a believable time", 60 < inst.t < 400, "%.0f s" % inst.t)
rw = inst.rewards()
check("everyone is rewarded", len(rw) == 3 and all(r["gold"] > 0 and r["marks"] > 0 for r in rw.values()))
allowed = {k for k, v in data["items"].items() if v.get("type") == "material"}
check("loot is only materials", all(set(r["items"]) <= allowed for r in rw.values()))
check("no breakthrough pills", all("breakthrough_pill" not in r["items"] for r in rw.values()))

# ---- a party that stands still loses
inst = engine.Instance(2, "run", 3, 15, chars(2), data, rng=random.Random(6))
run(inst, 400, lambda i: None)
check("standing still loses", inst.result == "failed", str(inst.result))
check("a lost run pays almost nothing", all(r["gold"] == 0 for r in inst.rewards().values()))

# ---- cheating is clamped
inst = engine.Instance(3, "run", 3, 15, chars(1), data, rng=random.Random(7))
run(inst, 6)
f = next(iter(f for f in inst.foes.values() if f.alive))
f.hp = f.max_hp = 1e12
m = inst.members[1]
m.x, m.z = f.x, f.z + 2
big = inst.hit(1, f.id, 10 ** 9)
r, s = m.rank()
check("a giant hit is clamped to what the rank allows", 0 < big <= engine.hit_base(r, s, 15) * engine.CFG["hit_mult"] + 1, str(big))
tot = 0
for _ in range(50):
    tot += inst.hit(1, f.id, 10 ** 6)
check("a flood of hits is limited per second", tot < engine.hit_base(r, s, 15) * engine.CFG["dps_mult"] * 2, str(tot))
check("it is noticed", m.clamps > 3)
check("nan and negative hits do nothing", inst.hit(1, f.id, float("nan")) == 0 and inst.hit(1, f.id, -5) == 0)
m.x, m.z = 40, 0
inst.move(1, 40, 0)
check("a player can't leave the arena", math.hypot(m.x, m.z) <= inst.R + 1e-6)
x0 = m.x
inst.move(1, m.x + 200, m.z)
check("a player can't teleport", abs(m.x - x0) < 5)
check("a hit from across the world is refused", (lambda: (setattr(m, "x", -10), setattr(m, "z", -10), setattr(f, "x", 15), setattr(f, "z", 15), inst.hit(1, f.id, 100))[-1])() == 0)

# ---- the boss has phases and adds; a raid can be won by a full party
inst = engine.Instance(4, "raid", 4, 20, chars(6, realm=4), data, rng=random.Random(8))
run(inst, 1500, fighter)
check("a raid can be won", inst.result == "won", "result=%s t=%.0f" % (inst.result, inst.t))
check("the boss went through its phases", inst.boss_ref is not None and inst.boss_ref.phase >= 3, str(inst.boss_ref.phase if inst.boss_ref else None))
check("a raid pays three times a run", True)

# ---- being down, revives and wipes
inst = engine.Instance(5, "run", 2, 10, chars(2), data, rng=random.Random(9))
run(inst, 8)
a, b = inst.members[1], inst.members[2]
inst._hurt(a, 10 ** 6, "test")
check("lethal damage downs a player", not a.alive and a.downs == 1)
a.x, a.z = b.x + 1, b.z
run(inst, 4, lambda i: None)
check("a close ally revives them", a.alive and a.hp > 0, "alive=%s" % a.alive)
inst._hurt(a, 10 ** 6, "t")
inst._hurt(b, 10 ** 6, "t")
inst.tick()
check("everyone down is a wipe", inst.result == "failed")

# ---- a world boss grows with the crowd and waits for the first challenger
inst = engine.Instance(6, "world", 5, 25, [], data, rng=random.Random(10))
run(inst, 30, lambda i: None)
check("an empty world boss just waits", inst.phase == "countdown" and inst.result is None)
inst.join(chars(1)[0])
run(inst, 8, lambda i: None)
b = inst.boss_ref
check("it appears when someone arrives", b is not None and b.alive)
hp1 = b.max_hp
for i in range(5):
    c = chars(1)[0]
    c["char_id"] = 100 + i
    c["name"] = "W%d" % i
    inst.join(c)
check("its health grows as people join", b.max_hp > hp1 * 3, "%.0f -> %.0f" % (hp1, b.max_hp))
check("the cap holds", all(inst.join({"char_id": 200 + i, "name": "X%d" % i, "realm": 3, "step": 1, "level": 1}) for i in range(30)) is not None and len(inst.members) <= 24)

# ---- the store
st = Store(":memory:")
acct = st.account("u1", "a@b.co")
c, err = st.create_char("u1", "Mara", 2, 4)
check("a character is made", c is not None and c["name"] == "Mara", err)
c2, err = st.create_char("u2", "mara", 1, 1)
check("names are unique, case aside", c2 is None)
c3, err = st.create_char("u3", "x", 1, 1)
check("short names are refused", c3 is None)
c4, err = st.create_char("u4", "admin", 1, 1, ["admin"])
check("reserved names are refused", c4 is None)
st.add_items(c, {"iron_ore": 10, "silver_ore": 2})
c["gold"] = 1000
st.save_char(c)
d, _ = st.create_char("u5", "Bob", 0, 1)
lid, err = st.list_item(c, "iron_ore", 5, 30)
check("listing takes the items out of the inventory", lid and c["inv"]["iron_ore"] == 5)
d["gold"] = 500
ok, err = st.buy(d, lid, 3)
check("buying works", ok and d["gold"] == 410 and d["inv"]["iron_ore"] == 3, str(err))
check("the seller is paid by mail, minus the fee", st.inbox(c["char_id"])[0]["gold"] == int(90 * 0.95))
ok, err = st.buy(d, lid, 99)
check("can't buy more than is listed", not ok)
ok, err = st.buy(c, lid, 1)
check("can't buy your own", not ok)
check("cancel returns the rest", st.cancel(c, lid) and c["inv"]["iron_ore"] == 7)
st.claim_mail(c, st.inbox(c["char_id"])[0]["id"])
check("mail gold can be claimed once", c["gold"] == 1000 + 85)
g1 = c["gold"]
st.claim_mail(c, st.inbox(c["char_id"])[0]["id"])
check("and only once", c["gold"] == g1)
check("scores: lower is better for times", st.post_score("raid_time", c, 300) and not st.post_score("raid_time", c, 400) and st.post_score("raid_time", c, 250))
check("an unknown board is refused", not st.post_score("nope", c, 1))
gid = st.make_grant(c, {"iron_ore": 3})
check("a grant takes the items first", gid and c["inv"]["iron_ore"] == 4)
check("and stays pending until acknowledged", len(st.pending_grants(c["char_id"])) == 1)
st.ack_grant(c["char_id"], gid)
check("acknowledged grants are gone", not st.pending_grants(c["char_id"]))
check("a grant can't take what isn't there", st.make_grant(c, {"iron_ore": 999}) is None)
st.delete_account("u1")
check("deleting an account removes the character", st.char_of("u1") is None and st.char_by_name("Mara") is None)

print("ENGINE TEST %d passed, %d failed" % (passed, failed))
sys.exit(1 if failed else 0)
