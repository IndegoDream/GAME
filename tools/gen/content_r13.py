"""Round 13 content (Robert, 2026-10-02):
"No one is proficient with anything from the start except one skill plus
hand to hand combat and survival" -> weapon skills + survival in skills.json,
a starter weapon for each weapon background.
"Use sect and guild contribution points for special items" -> each guild's
"specials" (rank-gated, bought with contribution) and the items they sell.

Idempotent: run it again and nothing doubles.
    python3 gen/content_r13.py
"""
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(HERE, "..", "data")


def load(name):
    with open(os.path.join(DATA, name), encoding="utf-8") as f:
        return json.load(f)


def save(name, d):
    with open(os.path.join(DATA, name), "w", encoding="utf-8") as f:
        json.dump(d, f, indent=2, ensure_ascii=False)
        f.write("\n")


WEAPON_SKILLS = {
    "sword": ("Swordplay", {"metal": 0.7, "fire": 0.3}, "The straight blade: cut, guard, thrust. Untrained hands swing it like a stick."),
    "dagger": ("Knife-work", {"metal": 0.5, "water": 0.5}, "Close, quick, and quiet. A dagger in a novice's hand is mostly a way to get cut."),
    "saber": ("Saber", {"metal": 0.6, "wood": 0.4}, "The curved blade that wants to keep moving."),
    "spear": ("Spear", {"wood": 0.6, "metal": 0.4}, "Distance is the whole art. Lose it and the spear is a long stick."),
    "axe": ("Axe", {"wood": 0.5, "fire": 0.5}, "Weight and commitment. Miss and you're open."),
    "hammer": ("Hammer", {"earth": 0.7, "metal": 0.3}, "Slow, crushing, and tiring -- until your body learns where the weight wants to go."),
    "halberd": ("Polearm", {"metal": 0.5, "earth": 0.5}, "Halberds and glaives: reach and weight together, and the hardest to learn."),
    "staff": ("Staff", {"wood": 0.6, "water": 0.4}, "The oldest weapon, and the one qi flows through most easily."),
    "unarmed": ("Unarmed", {"earth": 0.5, "fire": 0.5}, "Fists, elbows, knees, and fist wraps. Everyone starts here -- everyone who lives has some."),
}

SURVIVAL = {"name": "Survival", "kind": "path", "elements": {"wood": 0.5, "earth": 0.5},
            "desc": "Staying alive where the world doesn't care if you do: spotting a trap's tell, dressing a wound in the field, "
                    "getting more from a kill, knowing when to rest. Higher skill means traps bite less, healing goes further, "
                    "your wounds close on their own between fights, and hunts give more."}

STARTERS = {
    "practice_spear": {"name": "Practice Spear", "type": "weapon", "kind": "spear", "damage": 6, "value": 25,
                       "desc": "Ash shaft, iron tip, a militia stamp on the butt. +6 damage, long reach."},
    "hunting_knife": {"name": "Hunting Knife", "type": "weapon", "kind": "dagger", "damage": 4, "value": 20,
                      "desc": "For skinning more than fighting -- in the right hands, both. +4 damage, fast."},
    "woodcutters_axe": {"name": "Woodcutter's Axe", "type": "weapon", "kind": "axe", "damage": 7, "value": 22,
                        "desc": "Your father's, or someone's. +7 damage, heavy."},
    "quarterstaff": {"name": "Quarterstaff", "type": "weapon", "kind": "staff", "damage": 5, "value": 18,
                     "desc": "A straight length of hardwood. +5 damage, good reach."},
}

# ---- guild and sect specials: rank-gated, bought with contribution --------
SPECIAL_ITEMS = {
    # Adventurers' Lodge
    "lodge_field_ration": {"name": "Lodge Field Ration", "type": "consumable", "heal": 70, "value": 14,
                           "desc": "Hard bread, harder cheese, a sip of something strong. Heals 70 HP. Lodge issue."},
    "vanguard_token": {"name": "Vanguard's Token", "type": "treasure", "value": 220, "special": True,
                       "effect": {"damage_taken": 0.95},
                       "desc": "A dented bronze disc the Lodge gives those who walk in front. You take 5% less damage."},
    "pathfinder_compass": {"name": "Pathfinder's Compass", "type": "treasure", "value": 420, "special": True,
                           "effect": {"sense_radius": 4.0, "gather_chance": 0.05},
                           "desc": "Its needle points at whatever's hidden nearest. Spirit sense reaches 4m further; a little more from every gather."},
    "champions_brand": {"name": "Champion's Brand", "type": "treasure", "value": 900, "special": True,
                        "effect": {"damage_mult": 1.06, "attack_speed": 1.03},
                        "desc": "The Lodge's mark, burned into a leather cuff. +6% damage, 3% faster strikes."},
    # Gatherers' Hall
    "wild_tonic": {"name": "Wild Tonic", "type": "consumable", "heal": 40, "qi": 40, "value": 16,
                   "desc": "Seven roots and a secret. Heals 40 HP and gives 40 qi."},
    "forager_gloves": {"name": "Forager's Gloves", "type": "treasure", "value": 240, "special": True,
                       "effect": {"gather_chance": 0.15},
                       "desc": "Soft leather, worn through at the fingertips by someone else first. More from every gather."},
    "warden_satchel": {"name": "Warden's Satchel", "type": "treasure", "value": 480, "special": True,
                       "effect": {"gather_bonus": 1},
                       "desc": "A Warden of the Wild's own bag. One more of everything you gather."},
    # Blacksmiths' Guild
    "guild_whetstone": {"name": "Guild Whetstone", "type": "treasure", "value": 260, "special": True,
                        "effect": {"damage_mult": 1.04},
                        "desc": "Fine-grit, guild-cut. Your edge stays keener: +4% damage."},
    "master_tongs": {"name": "Master's Tongs", "type": "treasure", "value": 500, "special": True,
                     "effect": {"craft_quality_smithing": 0.06, "craft_success_smithing": 0.04},
                     "desc": "Black iron, perfectly balanced. Finer and surer smithing."},
    # Alchemists' Circle
    "circle_qi_draught": {"name": "Circle Qi Draught", "type": "consumable", "qi": 120, "value": 30,
                          "desc": "Cloudy, bitter, effective. +120 qi."},
    "furnace_charm": {"name": "Furnace Charm", "type": "treasure", "value": 260, "special": True,
                      "effect": {"craft_success_alchemy": 0.08},
                      "desc": "A clay token that keeps a furnace's heat honest. Surer alchemy."},
    "refiners_lens": {"name": "Refiner's Lens", "type": "treasure", "value": 520, "special": True,
                      "effect": {"craft_quality_alchemy": 0.06, "qi_mult": 1.03},
                      "desc": "See the impurity before it ruins the batch. Finer pills, and a little more qi from everything."},
    # Healers' House
    "house_salve": {"name": "House Salve", "type": "consumable", "heal": 110, "value": 22,
                    "desc": "The Healers' own recipe. Heals 110 HP."},
    "ward_charm": {"name": "Ward Charm", "type": "treasure", "value": 260, "special": True,
                   "effect": {"heal_on_kill": 4},
                   "desc": "A knot of red thread blessed in the wards. Each foe you fell mends you a little."},
    "saints_rosary": {"name": "Saint's Rosary", "type": "treasure", "value": 540, "special": True,
                      "effect": {"damage_taken": 0.94, "hp_mult": 1.04},
                      "desc": "Smooth beads, worn by a hundred prayers. Less damage taken, more life to take it."},
    # Lotus Ascent Academy (the sect): bought with merit
    "lotus_seal": {"name": "Lotus Seal", "type": "treasure", "value": 400, "special": True,
                   "effect": {"qi_mult": 1.06},
                   "desc": "An Inner Disciple's seal. Your cultivation runs 6% richer."},
    "sparring_manual": {"name": "Sparring Manual", "type": "treasure", "value": 600, "special": True,
                        "effect": {"attack_speed": 1.04, "damage_mult": 1.03},
                        "desc": "Margins full of a Core Disciple's notes. Quicker, harder strikes."},
    "elders_jade_slip": {"name": "Elder's Jade Slip", "type": "treasure", "value": 1200, "special": True,
                         "effect": {"meditate_mult": 1.25, "qi_mult": 1.05},
                         "desc": "A True Disciple's privilege: an elder's own cultivation notes. Meditation and qi both run richer."},
}

SPECIALS = {
    "adventurers": [{"item": "lodge_field_ration", "rank": 0, "cost": 12, "repeat": True},
                    {"item": "vanguard_token", "rank": 1, "cost": 70},
                    {"item": "pathfinder_compass", "rank": 2, "cost": 160},
                    {"item": "champions_brand", "rank": 3, "cost": 380}],
    "gatherers": [{"item": "wild_tonic", "rank": 0, "cost": 12, "repeat": True},
                  {"item": "forager_gloves", "rank": 1, "cost": 60},
                  {"item": "warden_satchel", "rank": 2, "cost": 150}],
    "blacksmiths": [{"item": "guild_whetstone", "rank": 1, "cost": 70},
                    {"item": "master_tongs", "rank": 2, "cost": 170}],
    "alchemists": [{"item": "circle_qi_draught", "rank": 0, "cost": 18, "repeat": True},
                   {"item": "furnace_charm", "rank": 1, "cost": 70},
                   {"item": "refiners_lens", "rank": 2, "cost": 170}],
    "healers": [{"item": "house_salve", "rank": 0, "cost": 15, "repeat": True},
                {"item": "ward_charm", "rank": 1, "cost": 70},
                {"item": "saints_rosary", "rank": 2, "cost": 170}],
    "academy": [{"item": "lotus_seal", "rank": 1, "cost": 140},
                {"item": "sparring_manual", "rank": 2, "cost": 300},
                {"item": "elders_jade_slip", "rank": 3, "cost": 700}],
}
# what a tailored commission costs, in contribution (Academy: merit)
TAILOR_COST = {"adventurers": 120, "gatherers": 120, "blacksmiths": 100, "alchemists": 120, "healers": 120, "academy": 200}
TAILOR_RANK = {"adventurers": 1, "gatherers": 1, "blacksmiths": 1, "alchemists": 1, "healers": 1, "academy": 1}


def main():
    sk = load("skills.json")
    for sid, (name, els, desc) in WEAPON_SKILLS.items():
        sk[sid] = {"name": name, "kind": "weapon", "elements": els, "desc": desc}
    sk["survival"] = SURVIVAL
    save("skills.json", sk)

    it = load("items.json")
    it.update(STARTERS)
    it.update(SPECIAL_ITEMS)
    save("items.json", it)

    g = load("guilds.json")
    for gid, rows in SPECIALS.items():
        g[gid]["specials"] = rows
        g[gid]["tailor_cost"] = TAILOR_COST[gid]
        g[gid]["tailor_rank"] = TAILOR_RANK[gid]
    save("guilds.json", g)
    print("skills %d, items %d, guild specials %d" % (len(sk), len(it), sum(len(r) for r in SPECIALS.values())))


if __name__ == "__main__":
    main()
