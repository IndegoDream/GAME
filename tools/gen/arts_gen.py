#!/usr/bin/env python3
"""Round 122: the ki arts library (Robert: movement, defence, attack and support arts; sects and
paths give some arts only to their own; nanites and ki each work alone and best together).
   python3 arts_gen.py <out.json>
32 arts in four families. Everything the game needs to know about them is data here;
the behaviour lives in scripts/actors/ArtCaster.gd (templates) and scripts/core/ArtsExt.gd (rules)."""
import json, sys

S = lambda sect, rank: {"sect": sect, "rank": rank}
P = lambda path, rank: {"path": path, "rank": rank}

IRON, WILLOW, MISTY, STONE, SILVER, CRIMSON = ("iron_fist_clan", "whispering_willow", "misty_peak_monastery",
                                               "stoneheart_brotherhood", "silverleaf_grove", "crimson_veil")

ARTS = [
    # ------------------------------------------------------------------ ATTACK (F)
    dict(id="heron_lance", name="Heron's Lance", family="strike", template="lance_line", cooldown=5.0, heat=26, route=["hegu", "quchi"],
         branches=["metal", "water"], params=dict(range=12.0, width=1.6, mult=1.9),
         desc="A needle of qi through everything in a line ahead of you, twelve metres long, for 1.9x damage.",
         hint="Fluent in Qi Burst, then twenty-five kills with your qi: it learns to narrow to a lance.",
         req=dict(realm=1), glimpse=dict(**{"from": "art_kill"}, need=25, text="Your qi has begun to run in a line, not a ring -- the heron's strike."),
         requires=dict(art="qi_burst", stage=1)),
    dict(id="leaf_sweep", name="Thousand-Leaf Sweep", family="strike", template="arc_sweep", cooldown=5.5, heat=24, route=["hegu"],
         branches=["wood"], element="wood", params=dict(radius=4.6, arc=200.0, mult=1.6, stagger=0.5),
         desc="A great arc of leaf-edged qi in front of you: everything within 4.6 m takes 1.6x and is knocked off balance.",
         hint="Taught by the Whispering Willow to its Inner Disciples.", req=dict(any=[S(WILLOW, 2)])),
    dict(id="ironstorm_chain", name="Ironstorm Chain", family="strike", template="chain_arc", cooldown=8.0, heat=34,
         route=["hegu", "quchi", "jianyu"], branches=["metal"], element="metal", params=dict(range=7.5, jumps=4, mult=1.7, falloff=0.85),
         desc="Lightning along an iron chain: it strikes the nearest foe, then leaps to the next, up to four more times, each a little weaker.",
         hint="Taught to the Elder's Disciples of the Iron Fist Clan.", req=dict(any=[S(IRON, 4)])),
    dict(id="quake_fist", name="Quake Fist", family="strike", template="ground_slam", cooldown=7.0, heat=30, route=["hegu", "quchi"],
         branches=["earth"], element="earth", params=dict(reach=4.0, radius=3.4, mult=2.0, stagger=1.3),
         desc="Your fist into the ground ahead: a shock of 3.4 m for 2x damage that staggers everything it touches.",
         hint="Taught by the Stoneheart Brotherhood to its Inner Disciples.", req=dict(any=[S(STONE, 2)])),
    dict(id="rending_claw", name="Rending Claw", family="strike", template="rend", cooldown=3.0, heat=18, route=["laogong", "neiguan"],
         branches=["fire", "metal"], params=dict(reach=3.6, mult=1.7, bleed=0.9, bleed_secs=5.0),
         desc="Qi hooked into claws: one foe in front takes 1.7x and keeps bleeding for nearly its own wounds again over five seconds.",
         hint="A Shadowblade's trade. Reach rank 2 of the Shadowblade road.", req=dict(any=[P("shadowblade", 2)])),
    dict(id="crimson_bloom", name="Crimson Bloom", family="strike", template="arc_sweep", cooldown=7.0, heat=30, route=["laogong", "waiguan"],
         branches=["fire"], element="fire", params=dict(radius=4.2, arc=360.0, mult=1.3, burn=0.5, burn_secs=4.0),
         desc="A flower of red qi opens around you: everything within 4.2 m takes 1.3x and burns.",
         hint="Taught by the Crimson Veil to its Inner Disciples.", req=dict(any=[S(CRIMSON, 2)])),
    dict(id="shatterpoint", name="Shatterpoint", family="strike", template="shatter", cooldown=6.0, heat=28, route=["hegu", "shousanli"],
         branches=["earth", "metal"], params=dict(reach=3.8, arc=100.0, mult=1.6, vs_staggered=1.8, vs_armoured=1.5, sunder=6.0),
         desc="Qi into the seam of a guard: 1.6x, nearly doubled against a foe already staggered, and armour splits (it takes more from everything for six seconds).",
         hint="A Vanguard's art. Reach rank 3 of the Vanguard road, or rank 4 of the Duelist's.", req=dict(any=[P("vanguard", 3), P("duelist", 4)])),
    dict(id="tidebreaker", name="Tidebreaker Wave", family="strike", template="lance_line", cooldown=7.0, heat=30,
         route=["quchi", "neiguan", "shaohai"], branches=["water"], element="water",
         params=dict(range=10.0, width=3.2, mult=1.5, slow=4.0, knock=5.0),
         desc="A wall of water-qi, 3 m wide, ten metres long: 1.5x, slows what it hits and throws it back.",
         hint="Taught to the Elder's Disciples of the Misty Peak Monastery.", req=dict(any=[S(MISTY, 4)])),
    # ------------------------------------------------------------------ MOVEMENT (V)
    dict(id="gale_blink", name="Gale Blink", family="step", template="blink", cooldown=4.5, heat=16, route=["yongquan", "huantiao"],
         branches=["wood", "water"], params=dict(range=7.0, iframes=0.25),
         desc="Be somewhere else: you appear seven metres ahead, stopped only by walls. Nothing can touch you for a heartbeat.",
         hint="Fluent in Wind Step, then step cleanly through twenty blows.", req=dict(realm=1),
         glimpse=dict(**{"from": "dodge"}, need=20, text="For a heartbeat you were not in the place the blow landed. You could be elsewhere on purpose."),
         requires=dict(art="wind_step", stage=1)),
    dict(id="silent_slip", name="Silent Slip", family="step", template="slip", cooldown=6.0, heat=18, route=["yongquan", "zusanli"],
         branches=["wood", "metal"], params=dict(dash=6.0, iframes=0.7, ambush=1.4),
         desc="A soundless slide through a blow: 0.7 seconds of nothing can touch you, and your next strike lands for 1.4x.",
         hint="A Ranger's art (rank 2 of the Ranger road) -- or rank 3 of the Delver's.", req=dict(any=[P("ranger", 2), P("delver", 3)])),
    dict(id="thunder_leap", name="Thunder Leap", family="step", template="leap_strike", cooldown=8.0, heat=26, route=["yongquan", "zusanli"],
         branches=["earth", "fire"], params=dict(distance=7.0, radius=3.5, mult=1.5, stagger=0.8),
         desc="Leap seven metres and land like a dropped bell: everything within 3.5 m takes 1.5x and reels.",
         hint="A Vanguard's art (rank 2) -- or rank 3 of the Duelist's.", req=dict(any=[P("vanguard", 2), P("duelist", 3)])),
    dict(id="reed_glide", name="Reed Glide", family="step", template="glide", cooldown=14.0, heat=8, route=["yongquan"],
         branches=["water", "wood"], params=dict(move=1.3, seconds=7.0),
         desc="Run light as a reed on water: 30% faster for seven seconds, almost no heat.",
         hint="Run hard and long: forty stretches of sprinting, and your qi learns to run with you.", req=dict(),
         glimpse=dict(**{"from": "sprint"}, need=40, text="You've run so long your qi has started running with you instead of behind you."),
         requires=dict(art="wind_step", stage=0)),
    dict(id="undertow_pull", name="Undertow Pull", family="step", template="pull", cooldown=6.0, heat=20, route=["yongquan", "huantiao"],
         branches=["water"], element="water", params=dict(range=9.0, mult=0.8, stagger=1.4),
         desc="Qi hooked round a foe nine metres off: it is dragged to your feet, hurt a little, and stunned.",
         hint="Taught by the Misty Peak Monastery to its Inner Disciples.", req=dict(any=[S(MISTY, 2)])),
    dict(id="mirror_afterimage", name="Mirror Afterimage", family="step", template="afterimage", cooldown=10.0, heat=24,
         route=["yongquan", "huantiao", "weizhong"], branches=["metal", "fire"], params=dict(dash=5.0, iframes=0.6, radius=6.0, stagger=1.3),
         desc="Step back out of your own shape and leave it standing: foes within 6 m strike the image and are stunned.",
         hint="A Shadowblade's art. Reach rank 3 of the Shadowblade road.", req=dict(any=[P("shadowblade", 3)])),
    dict(id="backwind_retreat", name="Backwind Retreat", family="step", template="retreat", cooldown=9.0, heat=14, route=["yongquan", "zusanli"],
         branches=["wood", "earth"], params=dict(dash=6.0, iframes=0.5, heal=0.06),
         desc="Leave the fight on a wind at your back: six metres away, nothing can touch you for half a second, and you close a little of your wounds.",
         hint="Be hurt, and live: forty blows taken, and your body learns to leave.", req=dict(),
         glimpse=dict(**{"from": "hurt"}, need=40, text="Pain is a teacher. This time it taught you how to leave."),
         requires=dict(art="wind_step", stage=0)),
    # ------------------------------------------------------------------ DEFENCE (guard)
    dict(id="counter_current", name="Counter Current", family="guard", template="guard_passive", cooldown=0.0, heat=0, route=["qihai"],
         branches=["water", "metal"], params=dict(guard_take=0.45, parry_bonus=0.04, parry_charge=1.5, parry_charge_secs=3.0),
         desc="A guard that turns the blow's own strength: a perfect parry charges your next strike for 1.5x for three seconds.",
         hint="Block forty blows with Iron Shell, and the strength in them starts to feel like yours.", req=dict(),
         glimpse=dict(**{"from": "block"}, need=40, text="You have taken so many blows on your guard that you can feel where each one wants to go."),
         requires=dict(art="iron_shell", stage=0)),
    dict(id="thorn_bark", name="Thorn Bark", family="guard", template="guard_passive", cooldown=0.0, heat=0, route=["qihai", "shanzhong"],
         branches=["wood"], element="wood", params=dict(guard_take=0.4, thorns=0.35, block_heat_mult=0.8),
         desc="A guard of living bark: a third of every blow you take on it goes back into the attacker, and it heats you less.",
         hint="Taught to the Elder's Disciples of the Silverleaf Grove -- or reach rank 4 of the Warden road.", req=dict(any=[S(SILVER, 4), P("warden", 4)])),
    dict(id="bulwark_stance", name="Bulwark Stance", family="guard", template="guard_passive", cooldown=0.0, heat=0, route=["qihai", "guanyuan"],
         branches=["earth"], element="earth", params=dict(guard_take=0.2, block_heat_mult=1.4, parry_bonus=-0.04),
         desc="Plant yourself: only a fifth of a blow gets through. The price is heat on every block, and a parry that's harder to time.",
         hint="Taught to the Elder's Disciples of the Stoneheart Brotherhood -- or reach rank 3 of the Warden road.", req=dict(any=[S(STONE, 4), P("warden", 3)])),
    dict(id="ember_ward", name="Ember Ward", family="guard", template="guard_passive", cooldown=0.0, heat=0, route=["qihai", "mingmen"],
         branches=["fire"], element="fire", params=dict(guard_take=0.4, ward_burn=0.4, parry_burn=0.7),
         desc="A guard of banked coals: attackers who strike it burn, and a perfect parry sets them properly alight.",
         hint="Taught by the Crimson Veil to its Core Disciples.", req=dict(any=[S(CRIMSON, 3)])),
    dict(id="steady_breath", name="Steady Breath", family="guard", template="guard_passive", cooldown=0.0, heat=0, route=["qihai", "shanzhong"],
         branches=["water", "wood"], params=dict(guard_take=0.42, block_heal=0.015, parry_vent=40.0),
         desc="Breathe through the blow: each block closes a little of your wounds, and a perfect parry vents far more heat.",
         hint="A Mender's art (rank 2) -- or rank 3 of the Ki Adept's.", req=dict(any=[P("mender", 2), P("ki_adept", 3)])),
    # ------------------------------------------------------------------ SUPPORT: restore (slot 8)
    dict(id="mending_breath", name="Mending Breath", family="support", sub="restore", template="heal_target", cooldown=12.0, heat=14,
         route=["qihai"], branches=["wood", "water"], params=dict(pct=0.20, range=12.0, nature="flesh"),
         desc="Qi breathed into a wound: heals 20% of the life of whoever with you is hurt worst -- you, or a companion in range.",
         hint="Use salves in earnest: six of them, and the healing in them starts to be yours.", req=dict(),
         glimpse=dict(**{"from": "salve"}, need=6, text="You know where the salve goes, and why. You could do that without the salve.")),
    dict(id="lotus_bloom", name="Lotus Bloom", family="support", sub="restore", template="heal_area", cooldown=22.0, heat=24,
         route=["qihai", "shanzhong", "jiuwei"], branches=["wood", "water"], params=dict(radius=8.0, pct=0.30, pulses=6, nature="qi"),
         desc="A lotus of soft light under everyone within 8 m: over six seconds they heal 30% of their life.",
         hint="A Mender's art (rank 3) -- or taught to the Core Disciples of the Whispering Willow.", req=dict(any=[P("mender", 3), S(WILLOW, 3)])),
    dict(id="cleansing_light", name="Cleansing Light", family="support", sub="restore", template="cleanse", cooldown=18.0, heat=10,
         route=["qihai", "shanzhong"], branches=["wood", "water"], params=dict(radius=8.0, pct=0.08, vent=30.0, nature="qi"),
         desc="A clean light through you and those near you: torn meridians mend, heat vents, and everyone heals a little.",
         hint="Taught by the Silverleaf Grove to its Inner Disciples.", req=dict(any=[S(SILVER, 2)])),
    dict(id="call_back_breath", name="Call Back the Breath", family="support", sub="restore", template="revive", cooldown=60.0, heat=40,
         route=["guanyuan", "jiuwei", "mingmen"], branches=["wood", "earth"], params=dict(range=12.0, pct=0.5, fallback_pct=0.35, nature="qi"),
         desc="Call a fallen companion back: they stand at half their life. If no one has fallen, it heals the worst hurt for 35%.",
         hint="A Mender's art. Reach rank 4 of the Mender road.", req=dict(realm=3, any=[P("mender", 4)])),
    dict(id="gear_mend", name="Gear Mend", family="support", sub="restore", template="heal_target", cooldown=16.0, heat=16,
         route=["qihai", "guanyuan"], branches=["metal", "fire"], params=dict(pct=0.28, range=12.0, nature="mech", plating=0.93, plating_secs=15.0),
         desc="Qi through metal joints: heals a construct companion fully as well as a man, and platings you over for fifteen seconds (7% less damage taken).",
         hint="A Forgewright's art. Reach rank 2 of the Forgewright road.", req=dict(any=[P("forgewright", 2)])),
    # ------------------------------------------------------------------ SUPPORT: boon + hex (slot 9)
    dict(id="tiger_spirit", name="Tiger Spirit", family="support", sub="boon", template="boon", cooldown=30.0, heat=18, route=["zusanli", "huantiao"],
         branches=["metal", "fire"], element="metal", params=dict(seconds=20.0, effect={"damage_mult": 1.15}, ally_dmg=1.15, radius=12.0),
         desc="The tiger walks with you: 15% more damage for twenty seconds, for you and for any companion within 12 m.",
         hint="Taught by the Iron Fist Clan to its Inner Disciples.", req=dict(any=[S(IRON, 2)])),
    dict(id="mountain_skin", name="Mountain Skin", family="support", sub="boon", template="boon", cooldown=32.0, heat=18, route=["zusanli", "chengshan"],
         branches=["earth"], element="earth", params=dict(seconds=20.0, effect={"damage_taken": 0.82}, ally_take=0.82, radius=12.0),
         desc="Skin like a hillside: 18% less damage taken for twenty seconds, for you and your companions within 12 m.",
         hint="Taught by the Stoneheart Brotherhood to its Core Disciples.", req=dict(any=[S(STONE, 3)])),
    dict(id="wind_fleet", name="Wind-Fleet", family="support", sub="boon", template="boon", cooldown=28.0, heat=16, route=["yongquan", "huantiao"],
         branches=["wood", "water"], params=dict(seconds=18.0, effect={"move_mult": 1.2, "attack_speed": 1.12}, ally_dmg=1.1, radius=12.0),
         desc="Everything quickens: 20% faster feet and 12% faster blows for eighteen seconds; companions near you hit 10% harder.",
         hint="Know Mending Breath, and step through thirty blows.", req=dict(),
         glimpse=dict(**{"from": "dodge"}, need=30, text="Stepping through a blow, you felt the world slow. You could slow it for others."),
         requires=dict(art="mending_breath", stage=0)),
    dict(id="still_heart", name="Still Heart", family="support", sub="boon", template="refill", cooldown=30.0, heat=0, route=["yongquan", "zusanli"],
         branches=["water"], params=dict(vent=60.0, ki=3.0, regen_secs=10.0, regen=0.01),
         desc="One breath of perfect stillness: 60 heat gone at once, three ki shots restored, and your wounds close slowly for ten seconds.",
         hint="A Ki Adept's art. Reach rank 2 of the Ki Adept road.", req=dict(any=[P("ki_adept", 2)])),
    dict(id="mark_of_prey", name="Mark of Prey", family="support", sub="hex", template="hex_mark", cooldown=14.0, heat=18, route=["laogong", "neiguan"],
         branches=["metal", "fire"], params=dict(radius=10.0, count=3, seconds=8.0, mult=1.25),
         desc="Qi painted on three foes within 10 m: for eight seconds they take 25% more from everything, from you and your companions.",
         hint="A hunter's art. Reach rank 3 of the Ranger road, or of the Delver's.", req=dict(any=[P("ranger", 3), P("delver", 3)])),
    dict(id="withering_gaze", name="Withering Gaze", family="support", sub="hex", template="hex_weaken", cooldown=20.0, heat=26,
         route=["laogong", "neiguan", "waiguan"], branches=["fire", "water"], element="fire", params=dict(radius=8.0, seconds=10.0, weak=0.7, burn=0.15),
         desc="A look that burns the strength out of them: foes within 8 m hit 30% softer for ten seconds, and smoulder.",
         hint="Taught to the Elder's Disciples of the Crimson Veil.", req=dict(any=[S(CRIMSON, 4)])),
    dict(id="binding_roots", name="Binding Roots", family="support", sub="hex", template="hex_root", cooldown=16.0, heat=24,
         route=["laogong", "neiguan"], branches=["wood", "earth"], element="wood", params=dict(radius=6.0, slow=5.0, stagger=1.0),
         desc="Roots out of the ground under every foe within 6 m: stunned a moment, then slowed for five seconds.",
         hint="Taught to the Elder's Disciples of the Whispering Willow.", req=dict(any=[S(WILLOW, 4)])),
]

# What each road adds to each family (multipliers; power and heat are shared, cooldown is per art).
AFFINITY = {
    "duelist":    {"strike": {"power": 1.08}, "step": {"cd": 0.90}},
    "vanguard":   {"strike": {"power": 1.06}, "guard": {"power": 1.08}},
    "ranger":     {"step": {"cd": 0.90}, "support": {"power": 1.06}},
    "ki_adept":   {"strike": {"power": 1.05}, "support": {"heat": 0.85}, "step": {"heat": 0.9}},
    "warden":     {"guard": {"power": 1.10}, "support": {"power": 1.05}},
    "shadowblade": {"step": {"cd": 0.88}, "strike": {"power": 1.05}},
    "mender":     {"support": {"power": 1.15, "cd": 0.85}},
    "forgewright": {"support": {"power": 1.08}, "guard": {"power": 1.05}},
    "delver":     {"step": {"cd": 0.92}, "guard": {"power": 1.05}, "support": {"power": 1.05}},
}

# nature of a support art x what the ally is made of. Beasts have no life bar of their own here;
# buffs reach them, healing does not.
KINDS = {
    "human":     {"flesh": 1.0, "qi": 0.9, "mech": 0.3},
    "beast":     {"flesh": 1.0, "qi": 0.7, "mech": 0.2},
    "spirit":    {"flesh": 0.4, "qi": 1.3, "mech": 0.2},
    "construct": {"flesh": 0.2, "qi": 0.6, "mech": 1.4},
}
KIND_NAMES = {"human": "flesh and blood", "beast": "a beast", "spirit": "a spirit", "construct": "a made thing"}

DATA = {
    "_about": "Round 122. Generated by tools/gen/arts_gen.py. 32 arts: 8 attack (F), 7 movement (V), 5 defence (guard), 12 support (8 / 9). "
              "req.any = any ONE of these opens the art (a sect at a rank, or a path at a rank); req.realm = the realm it needs; no req = anyone, "
              "found by glimpses. A sect's arts stay with you if you leave it; a path's arts need you to still walk that road.",
    "resonance": {"power": 1.12, "heat": 0.85, "duration": 1.15},
    "support": {"modes": ["one", "two", "share"], "default": "one"},
    "ally_range": 14.0,
    "affinity": AFFINITY,
    "affinity_caps": {"power": 1.2, "cd": 0.8, "heat": 0.8},
    "kinds": KINDS,
    "kind_names": KIND_NAMES,
    "named_kinds": {},
    "arts": ARTS,
}

if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "arts_ext.json"
    ids = [a["id"] for a in ARTS]
    assert len(ids) == len(set(ids)), "duplicate id"
    with open(out, "w") as f:
        json.dump(DATA, f, indent=1)
    fam = {}
    for a in ARTS:
        fam[a["family"]] = fam.get(a["family"], 0) + 1
    print("wrote", out, len(ARTS), "arts", fam)
