#!/usr/bin/env python3
"""Floors 5-10 content (2026-10-02): the settlement of Shellhaven (floor 5),
then four floors that walk the five-element cycle down beneath the sleeping
tortoise -- Wood (6), Fire (7), Earth (8), Metal (9) -- to the next
settlement on floor 10. Idempotent: re-running replaces these entries."""
import json, os
D = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "data")


def load(n):
    with open(os.path.join(D, n), encoding="utf-8") as f:
        return json.load(f)


def save(n, d):
    with open(os.path.join(D, n), "w", encoding="utf-8") as f:
        json.dump(d, f, indent=2, ensure_ascii=False)
        f.write("\n")


def mob(floor, name, model, tint, scale, hp, dmg, speed, aggro, rng, cd, qi, loot, **kw):
    d = {"floor": floor, "name": name, "model": model, "tint": tint, "scale": scale}
    d.update(kw)
    d.update({"hp": hp, "damage": dmg, "speed": speed, "aggro": aggro, "range": rng,
              "cooldown": cd, "qi": qi, "loot": loot})
    return d


ENEMIES = {
    # ---- floor 6: The Strangling Grove (Wood) ----
    "thornling": mob(6, "Thornling", "orc", [0.4, 0.75, 0.3], 0.85, 230, 30, 4.2, 9, 1.7, 1.0, 110,
                     {"gold": [16, 30], "spirit_resin": [0, 1], "spirit_herb": [0, 2]}),
    "rootbound_monk": mob(6, "Rootbound Monk", "human", [0.45, 0.6, 0.35], 1.3, 520, 40, 2.5, 8, 2.2, 1.7, 190,
                          {"gold": [30, 55], "heartwood": [0, 1], "spirit_resin": [0, 1]}),
    "grove_mother": mob(6, "The Grove Mother", "human", [0.35, 0.8, 0.45], 2.2, 2200, 56, 2.8, 14, 3.2, 1.6, 1600,
                        {"gold": [380, 500], "heartwood": [2, 4], "spirit_resin": [3, 5], "verdant_heart": [1, 1]},
                        boss=True),
    "moss_stag": mob(6, "Moss Stag", "beast", [0.4, 0.6, 0.35], 1.9, 120, 16, 4.4, 7, 1.8, 1.5, 30,
                     {"raw_meat": [1, 3], "beast_hide": [1, 2]},
                     passive=True, retaliates=True, tameable=6,
                     familiar={"name": "Fern", "finds": ["spirit_herb", "moonpetal", "spirit_resin"],
                               "effect": {"gather_chance": 0.1}}),
    # ---- floor 7: The Ember Forges (Fire) ----
    "cinder_imp": mob(7, "Cinder Imp", "orc", [1.0, 0.45, 0.2], 0.75, 260, 36, 4.6, 10, 1.6, 0.9, 130,
                      {"gold": [18, 34], "firestone": [0, 1], "ember_root": [0, 1]}),
    "slag_brute": mob(7, "Slag Brute", "orc", [0.5, 0.35, 0.3], 1.6, 700, 50, 2.3, 8, 2.4, 1.9, 240,
                      {"gold": [35, 65], "slag_iron": [1, 2]}),
    "furnace_sovereign": mob(7, "The Furnace Sovereign", "human", [1.0, 0.5, 0.25], 2.2, 2900, 64, 3.0, 14, 3.2, 1.5, 2100,
                             {"gold": [450, 600], "firestone": [3, 5], "slag_iron": [3, 5], "sovereign_ember": [1, 1]},
                             boss=True),
    "ember_salamander": mob(7, "Ember Salamander", "beast", [0.95, 0.4, 0.2], 1.3, 140, 20, 4.0, 7, 1.7, 1.4, 34,
                            {"beast_hide": [1, 2], "firestone": [0, 1]},
                            passive=True, retaliates=True, tameable=7,
                            familiar={"name": "Cinder", "finds": ["ember_root", "gold_nugget", "firestone"],
                                      "effect": {"damage_mult": 1.06}}),
    # ---- floor 8: The Terracotta Barrows (Earth) ----
    "clay_soldier": mob(8, "Clay Soldier", "human", [0.8, 0.6, 0.42], 1.15, 380, 44, 2.9, 9, 2.0, 1.4, 170,
                        {"gold": [22, 40], "ancient_clay": [1, 2]}),
    "clay_cavalier": mob(8, "Clay Cavalier", "orc", [0.7, 0.5, 0.35], 1.7, 900, 58, 3.4, 10, 2.6, 1.8, 300,
                         {"gold": [40, 75], "ancient_clay": [1, 3], "emperor_jade": [0, 1]}),
    "buried_emperor": mob(8, "The Buried Emperor", "human", [0.85, 0.75, 0.4], 2.4, 3800, 72, 2.6, 15, 3.4, 1.6, 2800,
                          {"gold": [550, 750], "emperor_jade": [2, 4], "imperial_seal": [1, 1]},
                          boss=True),
    "burrow_mole": mob(8, "Burrow Mole", "beast", [0.5, 0.42, 0.35], 1.1, 110, 14, 3.4, 6, 1.6, 1.5, 32,
                       {"beast_hide": [1, 2], "raw_meat": [1, 2]},
                       passive=True, retaliates=True, tameable=6,
                       familiar={"name": "Delve", "finds": ["iron_ore", "silver_ore", "rough_ruby", "gold_nugget"],
                                 "effect": {"gather_chance": 0.12}}),
    # ---- floor 9: The Sword Grave (Metal) ----
    "sword_wraith": mob(9, "Sword Wraith", "human", [0.8, 0.85, 0.95], 1.0, 340, 62, 4.4, 11, 2.2, 1.0, 210,
                        {"gold": [26, 48], "grave_steel": [0, 1]}),
    "grave_keeper": mob(9, "Grave Keeper", "orc", [0.55, 0.58, 0.65], 1.6, 1100, 64, 2.4, 9, 2.5, 1.8, 360,
                        {"gold": [50, 90], "grave_steel": [1, 3]}),
    "sword_saint_shade": mob(9, "Shade of the Sword Saint", "human", [0.75, 0.9, 1.0], 2.0, 4600, 85, 3.6, 16, 3.6, 1.2, 3600,
                             {"gold": [700, 900], "grave_steel": [4, 6], "sword_intent_shard": [1, 1]},
                             boss=True),
    "steel_crow": mob(9, "Steel Crow", "beast", [0.6, 0.65, 0.75], 0.9, 90, 18, 5.0, 8, 1.6, 1.2, 36,
                      {"grave_steel": [0, 1], "raw_meat": [0, 1]},
                      passive=True, retaliates=True, tameable=7,
                      familiar={"name": "Glint", "finds": ["grave_steel", "silver_ore", "sapphire_shard"],
                                "effect": {"damage_mult": 1.04, "hp_mult": 1.04}}),
}


def mat(name, value, element, desc, *lore):
    d = {"name": name, "type": "material", "value": value}
    if element:
        d["element"] = element
    d["desc"] = desc
    if lore:
        d["lore"] = [{"skill": s, "level": l, "text": t} for s, l, t in lore]
    return d


ITEMS = {
    # materials
    "spirit_resin": mat("Spirit Resin", 14, "wood", "Amber sap that bled from a tree with a cultivator's roots.",
                        ("medicine", 4, "Spread thin over a wound, it seals and breathes at the same time."),
                        ("alchemy", 6, "It carries Wood qi without spoiling. Pills built on it keep for years.")),
    "heartwood": mat("Spirit Heartwood", 40, "wood", "The dense, warm core of a grove tree. It is faintly alive.",
                     ("smithing", 10, "Hard as iron along the grain. A spear shaft of it never splinters.")),
    "verdant_heart": mat("Verdant Heart", 300, "wood", "The Grove Mother's seed. It beats, slowly, like a sleeping thing.",
                         ("alchemy", 12, "One heart, ground fine, could feed a whole sect's pills for a year -- or one person's breakthrough.")),
    "firestone": mat("Firestone", 35, "fire", "A red stone, warm to hold, warmer the longer you hold it.",
                     ("jewelcrafting", 6, "Set in silver it burns steady; set in gold it burns bright."),
                     ("alchemy", 7, "A pinch of it in a pill makes the qi go down like a swallowed coal.")),
    "slag_iron": mat("Slag Iron", 30, "metal", "Iron that has been through the Ember Forges too many times. Black, heavy, stubborn.",
                     ("smithing", 9, "Fold it with firestone and it forgets it was ever brittle.")),
    "sovereign_ember": mat("Sovereign Ember", 350, "fire", "A coal that has never gone out. Something in it remembers being a king.",
                           ("smithing", 14, "A furnace fed with it can melt what no other fire can.")),
    "ancient_clay": mat("Ancient Clay", 25, "earth", "Fired clay from the buried army, still holding the shape of a soldier's hand.",
                        ("smithing", 8, "Crushed and bound, it makes scale armour lighter than iron and almost as hard.")),
    "emperor_jade": mat("Emperor's Jade", 60, "earth", "Deep green jade from the barrows. The carvings on it are orders.",
                        ("jewelcrafting", 9, "Jade that has given orders still wants to. Worn, it steadies the wearer.")),
    "imperial_seal": mat("Imperial Seal", 400, "earth", "The Buried Emperor's seal. Press it to clay and the clay stands up.",
                         ("smithing", 16, "Set in a halberd's head, it makes the weapon an order no one can refuse.")),
    "grave_steel": mat("Grave Steel", 55, "metal", "Steel from a sword that was buried with its master. It still has an edge.",
                       ("smithing", 12, "Every piece remembers a different sword. Fold enough of them together and they argue -- then agree.")),
    "sword_intent_shard": mat("Sword Intent Shard", 500, "metal", "A splinter of pure intent, cold and bright. It cuts the hand that doubts it.",
                              ("smithing", 18, "Forge it into a blade only when you know exactly what the blade is for.")),
    # weapons
    "thornwood_spear": {"name": "Thornwood Spear", "type": "weapon", "damage": 32, "value": 460,
                        "desc": "A heartwood shaft bound with resin, its tip a living thorn. +32 damage."},
    "firestone_saber": {"name": "Firestone Saber", "type": "weapon", "damage": 38, "value": 560,
                        "desc": "Slag iron folded around a vein of firestone. It glows when it swings. +38 damage."},
    "emperors_halberd": {"name": "Emperor's Halberd", "type": "weapon", "damage": 44, "value": 700,
                         "desc": "A clay-army halberd reforged with jade. Soldiers would kneel to it. +44 damage."},
    "grave_sword": {"name": "Sword of the Grave", "type": "weapon", "damage": 52, "value": 900,
                    "desc": "Five buried swords become one, and the one has made up its mind. +52 damage."},
    # armour
    "barkskin_mail": {"name": "Barkskin Mail", "type": "armor", "hp": 200, "value": 420,
                      "desc": "Plates of heartwood sealed in resin. It grows back where it's cut. +200 max HP."},
    "slag_plate": {"name": "Slag Plate", "type": "armor", "hp": 250, "value": 520,
                   "desc": "Black, heavy, ugly, and it has never once broken. +250 max HP."},
    "terracotta_scale": {"name": "Terracotta Scale", "type": "armor", "hp": 320, "value": 680,
                         "desc": "Clay scales from the buried army, jade-bound. +320 max HP."},
    # pills and salves
    "resin_salve": {"name": "Resin Salve", "type": "consumable", "heal": 160, "value": 50, "attune": {"wood": 1},
                    "desc": "Seals a wound and lets it breathe. Heals 160 HP; a little Wood settles in you."},
    "verdant_pill": {"name": "Verdant Pill", "type": "consumable", "qi": 120, "value": 70, "attune": {"wood": 3},
                     "desc": "Tastes of green things growing. +120 qi, and Wood settles in you."},
    "magma_pill": {"name": "Magma Pill", "type": "consumable", "qi": 160, "value": 90, "attune": {"fire": 4},
                   "desc": "Goes down like a swallowed coal. +160 qi, and Fire settles in you."},
    "earthmarrow_pill": {"name": "Earthmarrow Pill", "type": "consumable", "qi": 200, "value": 110, "attune": {"earth": 4},
                         "desc": "Heavy as a stone in the belly. +200 qi, and Earth settles in you."},
    "sword_qi_pill": {"name": "Sword Qi Pill", "type": "consumable", "qi": 260, "value": 140, "attune": {"metal": 4},
                      "desc": "It cuts on the way down. +260 qi, and Metal settles in you."},
    "shell_tea": {"name": "Shellhaven Tea", "type": "consumable", "heal": 90, "value": 18, "attune": {"water": 1},
                  "desc": "Brewed from the moss that grows on the tortoise's shell. Heals 90 HP; a little Water settles in you."},
    # jewellery
    "firestone_ring": {"name": "Firestone Ring", "type": "ring", "value": 180, "effect": {"damage_mult": 1.06},
                       "desc": "A firestone in a silver band. Your strikes land hotter. (+6% damage)"},
    "emperor_jade_pendant": {"name": "Emperor's Jade Pendant", "type": "amulet", "value": 240, "effect": {"hp_mult": 1.1},
                             "desc": "A carved order hung at the throat: STAND. (+10% HP)"},
    # treasures (one of a kind)
    "tortoise_scale": {"name": "Scale of the Sleeping Tortoise", "type": "treasure", "value": 1200,
                       "effect": {"damage_taken": 0.9, "meditate_mult": 1.25},
                       "desc": "A scale the old tortoise shed a thousand years ago, still warm with its slow breath. You take less damage, and cultivate a little deeper."},
    "saints_sheath": {"name": "The Sword Saint's Sheath", "type": "treasure", "value": 2000,
                      "effect": {"attack_speed": 1.15, "damage_mult": 1.08},
                      "desc": "An empty sheath that still knows the shape of the greatest sword ever drawn. Whatever you carry, it draws faster and cuts deeper."},
}

RECIPES = [
    {"makes": "thornwood_spear", "needs": {"heartwood": 3, "spirit_resin": 4}, "gold": 120, "skill": "smithing", "difficulty": 13},
    {"makes": "barkskin_mail", "needs": {"heartwood": 4, "spirit_resin": 3}, "gold": 110, "skill": "smithing", "difficulty": 13},
    {"makes": "firestone_saber", "needs": {"firestone": 4, "slag_iron": 3}, "gold": 160, "skill": "smithing", "difficulty": 16},
    {"makes": "slag_plate", "needs": {"slag_iron": 6}, "gold": 150, "skill": "smithing", "difficulty": 15},
    {"makes": "emperors_halberd", "needs": {"emperor_jade": 3, "ancient_clay": 4, "slag_iron": 2}, "gold": 220, "skill": "smithing", "difficulty": 18},
    {"makes": "terracotta_scale", "needs": {"ancient_clay": 6, "emperor_jade": 2}, "gold": 200, "skill": "smithing", "difficulty": 18},
    {"makes": "grave_sword", "needs": {"grave_steel": 5, "sword_intent_shard": 1}, "gold": 300, "skill": "smithing", "difficulty": 22},
    {"makes": "resin_salve", "needs": {"spirit_resin": 2, "spirit_herb": 1}, "gold": 5, "skill": "medicine", "difficulty": 6},
    {"makes": "shell_tea", "needs": {"spirit_herb": 2, "moonpetal": 1}, "gold": 0, "skill": "medicine", "difficulty": 2},
    {"makes": "verdant_pill", "needs": {"heartwood": 1, "spirit_herb": 2}, "gold": 15, "skill": "alchemy", "difficulty": 9},
    {"makes": "magma_pill", "needs": {"firestone": 1, "ember_root": 2}, "gold": 20, "skill": "alchemy", "difficulty": 11},
    {"makes": "earthmarrow_pill", "needs": {"ancient_clay": 2, "moonpetal": 1}, "gold": 25, "skill": "alchemy", "difficulty": 13},
    {"makes": "sword_qi_pill", "needs": {"grave_steel": 1, "iron_thistle": 2}, "gold": 30, "skill": "alchemy", "difficulty": 15},
    {"makes": "firestone_ring", "needs": {"firestone": 2, "silver_ore": 1}, "gold": 40, "skill": "jewelcrafting", "difficulty": 8},
    {"makes": "emperor_jade_pendant", "needs": {"emperor_jade": 2, "gold_nugget": 2}, "gold": 60, "skill": "jewelcrafting", "difficulty": 10},
]

TECHNIQUES = {
    "evergreen_body": {"name": "Evergreen Body", "kind": "passive", "realm": 2,
                       "desc": "Like the grove, you grow back. Every kill mends 10 HP, and your body holds 8% more life.",
                       "effect": {"heal_on_kill": 10, "hp_mult": 1.08},
                       "hint": "Somewhere in the Grove, the trees tell how they outlived the sect that planted them.",
                       "unlock": {"lore": True}},
    "ember_meridians": {"name": "Ember Meridians", "kind": "passive", "realm": 2,
                        "desc": "Qi runs through you like fire through a bellows. +12% damage.",
                        "effect": {"damage_mult": 1.12},
                        "hint": "The forge-masters cut their method into the anvils.",
                        "unlock": {"lore": True}},
    "slag_breaker": {"name": "Slag Breaker", "kind": "passive", "realm": 2,
                     "desc": "You've learned where brutes break. You take 10% less damage.",
                     "effect": {"damage_taken": 0.9},
                     "hint": "Break enough of the Forge's brutes and you'll learn where they crack.",
                     "unlock": {"kills": {"slag_brute": 15}}},
    "terracotta_stance": {"name": "Terracotta Stance", "kind": "passive", "realm": 3,
                          "desc": "Stand like the buried army stood for a thousand years. You take 12% less damage.",
                          "effect": {"damage_taken": 0.88},
                          "hint": "The general who drilled the clay army left his drill book behind.",
                          "unlock": {"lore": True}},
    "sword_intent": {"name": "Sword Intent", "kind": "passive", "realm": 3,
                     "desc": "Not a technique -- a decision. +20% damage, and you strike 10% faster.",
                     "effect": {"damage_mult": 1.2, "attack_speed": 1.1},
                     "hint": "The Sword Saint left one disciple. The disciple is still waiting.",
                     "unlock": {"inheritance": True}},
}

CONTRACTS = {
    "adventurers": [
        {"id": "prune_the_grove", "desc": "Cut back the Grove: 15 thornlings.",
         "goal": {"kill": "thornling", "count": 15}, "reward": {"rep": 80, "gold": 90}},
        {"id": "bank_the_fires", "desc": "Put out 10 cinder imps.",
         "goal": {"kill": "cinder_imp", "count": 10}, "reward": {"rep": 95, "gold": 120}},
        {"id": "break_the_ranks", "desc": "Break 12 clay soldiers.",
         "goal": {"kill": "clay_soldier", "count": 12}, "reward": {"rep": 110, "gold": 150}},
        {"id": "lay_the_swords", "desc": "Lay 10 sword wraiths to rest.",
         "goal": {"kill": "sword_wraith", "count": 10}, "reward": {"rep": 130, "gold": 190}},
    ],
}


def main():
    en = load("enemies.json"); en.update(ENEMIES); save("enemies.json", en)
    it = load("items.json"); it.update(ITEMS); save("items.json", it)
    rc = load("recipes.json")
    made = {r["makes"] for r in RECIPES}
    rc = [r for r in rc if r.get("makes") not in made] + RECIPES
    save("recipes.json", rc)
    te = load("techniques.json"); te.update(TECHNIQUES); save("techniques.json", te)
    gu = load("guilds.json")
    for gid, cs in CONTRACTS.items():
        ids = {c["id"] for c in cs}
        gu[gid]["contracts"] = [c for c in gu[gid].get("contracts", []) if c.get("id") not in ids] + cs
    save("guilds.json", gu)
    # sanity: every loot / recipe id exists
    it = load("items.json")
    bad = [i for e in ENEMIES.values() for i in e["loot"] if i not in it and i != "gold"]
    bad += [i for r in RECIPES for i in list(r["needs"]) + [r["makes"]] if i not in it]
    bad += [i for e in ENEMIES.values() for i in e.get("familiar", {}).get("finds", []) if i not in it]
    assert not bad, bad
    print("enemies", len(en), "items", len(it), "recipes", len(rc), "techniques", len(te))


if __name__ == "__main__":
    main()
