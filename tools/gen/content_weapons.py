#!/usr/bin/env python3
"""Weapons that drop, turn up in chests, and can be made (2026-10-02).
Robert: "make sure weapons are being dropped and found as well as able to
be made". Every weapon has a kind (Game.WEAPON_KINDS: sword, dagger, saber,
spear, axe, hammer, halberd, staff, fists) that changes how it plays; gear
with "drop": true and a "tier" (its floor) can drop from that floor's
monsters (bosses always drop something) and from "random_gear" chests.
Idempotent."""
import json, os
D = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "data")


def load(n):
    with open(os.path.join(D, n), encoding="utf-8") as f:
        return json.load(f)


def save(n, d):
    with open(os.path.join(D, n), "w", encoding="utf-8") as f:
        json.dump(d, f, indent=2, ensure_ascii=False)
        f.write("\n")


KINDS = {"iron_sword": "sword", "bone_blade": "saber", "spirit_steel_sword": "sword", "nanite_edge": "sword",
         "thornwood_spear": "spear", "firestone_saber": "saber", "emperors_halberd": "halberd", "grave_sword": "sword"}
SPEED = {"nanite_edge": 1.1}


def w(name, kind, dmg, tier, value, desc, **kw):
    d = {"name": name, "type": "weapon", "kind": kind, "damage": dmg, "tier": tier, "drop": True, "value": value, "desc": desc}
    d.update(kw)
    return d


def a(name, hp, tier, value, desc, **kw):
    d = {"name": name, "type": "armor", "hp": hp, "tier": tier, "drop": True, "value": value, "desc": desc}
    d.update(kw)
    return d


GEAR = {
    # floor 1 -- the warrens
    "goblin_shiv": w("Goblin Shiv", "dagger", 5, 1, 25, "A notched blade a goblin kept very, very sharp."),
    "chipped_hatchet": w("Chipped Hatchet", "axe", 9, 1, 30, "A woodcutter's hatchet. The goblins found other uses for it."),
    "goblin_leathers": a("Goblin Leathers", 30, 1, 25, "Stitched hides, stiff with old sweat. Better than nothing. +30 max HP."),
    # floor 2 -- the crypt
    "bone_spear": w("Bone Spear", "spear", 12, 2, 60, "A thighbone shaft with a sharpened shoulder blade bound to the tip."),
    "knight_longsword": w("Knight's Longsword", "sword", 14, 2, 80, "Carried by a skeleton knight for longer than you have been alive."),
    "shroud_mail": a("Shroud Mail", 70, 2, 70, "Mail links woven through a burial shroud. Cold. +70 max HP."),
    # floor 3 -- the drowned seam
    "miners_pick": w("Miner's Pick", "hammer", 20, 3, 90, "A heavy pick that broke stone for twenty years and bones for a few more."),
    "drowned_hook": w("Drowned Man's Hook", "saber", 16, 3, 85, "A curved hook-blade, still dripping no matter how long it dries."),
    "miner_leathers": a("Miner's Leathers", 100, 3, 90, "Thick apron and cap, studded at the shoulders. +100 max HP."),
    # floor 4 -- the sanctum
    "warden_staff": w("Warden's Staff", "staff", 22, 4, 220, "A rod of living metal; the nanites in it lean toward your qi. (+8% qi)",
                      effect={"qi_mult": 1.08}),
    "sentinel_halberd": w("Sentinel Halberd", "halberd", 30, 4, 260, "Too heavy for a person. The sentinels weren't people."),
    "sentinel_plate": a("Sentinel Plate", 150, 4, 260, "A plate shed by a sanctum sentinel, refitted for something smaller. +150 max HP."),
    # floor 6 -- the grove
    "rootwood_staff": w("Rootwood Staff", "staff", 30, 6, 330, "A grove root that kept growing after it was cut. Kills feed it -- and you. (+4 HP per kill)",
                        effect={"heal_on_kill": 4}),
    "thorn_knuckles": w("Thorn Knuckles", "fists", 22, 6, 300, "Wraps studded with living thorns. Fast, and they bite."),
    "thornweave_vest": a("Thornweave Vest", 190, 6, 340, "A vest of woven vines that tightens when you're struck. +190 max HP."),
    # floor 7 -- the forges
    "imp_fang_daggers": w("Imp-Fang Daggers", "dagger", 30, 7, 400, "A pair of blades cut from cinder imps' fangs. Still warm."),
    "slag_maul": w("Slag Maul", "hammer", 54, 7, 480, "A lump of slag iron on a beam. Subtle it is not."),
    "forgeguard_mail": a("Forgeguard Mail", 240, 7, 480, "Smith's mail, scorched and riveted twice over. +240 max HP."),
    # floor 8 -- the barrows
    "clay_general_glaive": w("Clay General's Glaive", "halberd", 52, 8, 620, "The general's own glaive, fired in the kiln with him."),
    "jade_guard_sabre": w("Jade-Guard Sabre", "saber", 42, 8, 560, "A sabre with a jade guard carved with an order: ADVANCE."),
    "clay_lamellar": a("Clay Lamellar", 300, 8, 620, "Hundreds of fired-clay plates on silk cords. +300 max HP."),
    # floor 9 -- the sword grave
    "wraith_blade": w("Wraith Blade", "sword", 52, 9, 820, "A sword a wraith would not let go of. It is light, and it is eager.", speed=1.15),
    "keeper_greataxe": w("Keeper's Greataxe", "axe", 66, 9, 860, "A grave keeper's axe for digging -- and for the ones who dig."),
    "grave_wardens_coat": a("Grave-Warden's Coat", 340, 9, 860, "A long coat of grave-steel scales. +340 max HP."),
}

RECIPES = [
    {"makes": "goblin_shiv", "needs": {"goblin_tooth": 3, "iron_ore": 1}, "gold": 5, "skill": "smithing", "difficulty": 0},
    {"makes": "miners_pick", "needs": {"iron_ore": 4, "silver_ore": 1}, "gold": 20, "skill": "smithing", "difficulty": 4},
    {"makes": "warden_staff", "needs": {"nanite_shard": 3, "silver_ore": 2}, "gold": 60, "skill": "smithing", "difficulty": 9},
    {"makes": "rootwood_staff", "needs": {"heartwood": 2, "spirit_resin": 3}, "gold": 80, "skill": "smithing", "difficulty": 12},
    {"makes": "thorn_knuckles", "needs": {"heartwood": 1, "spirit_resin": 2, "beast_hide": 2}, "gold": 60, "skill": "smithing", "difficulty": 11},
    {"makes": "imp_fang_daggers", "needs": {"firestone": 2, "slag_iron": 2}, "gold": 110, "skill": "smithing", "difficulty": 14},
    {"makes": "slag_maul", "needs": {"slag_iron": 7}, "gold": 140, "skill": "smithing", "difficulty": 15},
    {"makes": "jade_guard_sabre", "needs": {"emperor_jade": 2, "slag_iron": 3}, "gold": 180, "skill": "smithing", "difficulty": 17},
    {"makes": "keeper_greataxe", "needs": {"grave_steel": 6}, "gold": 240, "skill": "smithing", "difficulty": 20},
]


def main():
    it = load("items.json")
    for k, kind in KINDS.items():
        if k in it:
            it[k]["kind"] = kind
            if k in SPEED:
                it[k]["speed"] = SPEED[k]
    it.update(GEAR)
    save("items.json", it)
    rc = load("recipes.json")
    made = {r["makes"] for r in RECIPES}
    rc = [r for r in rc if r.get("makes") not in made] + RECIPES
    save("recipes.json", rc)
    it = load("items.json")
    bad = [i for r in RECIPES for i in list(r["needs"]) + [r["makes"]] if i not in it]
    assert not bad, bad
    kinds = {}
    for v in it.values():
        if v.get("type") == "weapon":
            kinds[v.get("kind", "?")] = kinds.get(v.get("kind", "?"), 0) + 1
    print("weapons by kind:", kinds, "| recipes", len(rc))


if __name__ == "__main__":
    main()
