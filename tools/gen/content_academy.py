#!/usr/bin/env python3
"""The Lotus Ascent Academy (2026-10-02): a guild you can't simply join --
pass the entrance exam (Strength / Knowledge / Craft) at Shellhaven. Its
ranks each need standing, a realm AND a rank trial in the arena; merit
(earned with standing) buys techniques from its library. Idempotent."""
import json, os
D = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "data")


def load(n):
    with open(os.path.join(D, n), encoding="utf-8") as f:
        return json.load(f)


def save(n, d):
    with open(os.path.join(D, n), "w", encoding="utf-8") as f:
        json.dump(d, f, indent=2, ensure_ascii=False)
        f.write("\n")


ACADEMY = {
    "name": "Lotus Ascent Academy", "rival": "", "exam": True,
    "desc": "A school of cultivation that only takes those who prove themselves. Its disciples are expected to grow -- and to be seen growing.",
    "rep_from": {"kill": 0.5, "boss": 20, "secret": 5, "chest": 1, "craft_fine": 3},
    "ranks": [
        {"name": "Outer Disciple", "rep": 0, "realm": 1},
        {"name": "Inner Disciple", "rep": 120, "realm": 2, "trial_tier": 6, "effect": {"damage_mult": 1.05}, "perk": "+5% damage"},
        {"name": "Core Disciple", "rep": 400, "realm": 3, "trial_tier": 9, "effect": {"hp_mult": 1.08}, "perk": "+8% HP"},
        {"name": "True Disciple", "rep": 1000, "realm": 4, "trial_tier": 13, "effect": {"qi_mult": 1.12}, "perk": "+12% qi"},
        {"name": "Elder's Chosen", "rep": 2400, "realm": 6, "trial_tier": 18, "effect": {"damage_mult": 1.1, "damage_taken": 0.92}, "perk": "+10% damage, 8% less damage taken"},
        {"name": "Lotus Elder", "rep": 5000, "realm": 8, "trial_tier": 26, "effect": {"meditate_mult": 1.5}, "perk": "cultivate half again as fast"},
    ],
    "contracts": [
        {"id": "academy_grove", "desc": "Field study: put down 12 thornlings in the Strangling Grove.", "goal": {"kill": "thornling", "count": 12}, "reward": {"rep": 40, "gold": 60}},
        {"id": "academy_salves", "desc": "Infirmary duty: make 3 Resin Salves.", "goal": {"craft": "resin_salve", "count": 3}, "reward": {"rep": 30, "gold": 40}},
        {"id": "academy_forges", "desc": "Field study: break 8 slag brutes in the Ember Forges.", "goal": {"kill": "slag_brute", "count": 8}, "reward": {"rep": 55, "gold": 90}},
        {"id": "academy_barrows", "desc": "Field study: bring down 6 clay cavaliers.", "goal": {"kill": "clay_cavalier", "count": 6}, "reward": {"rep": 70, "gold": 120}},
        {"id": "academy_grave", "desc": "Field study: lay 10 sword wraiths to rest.", "goal": {"kill": "sword_wraith", "count": 10}, "reward": {"rep": 90, "gold": 160}},
    ],
    "library": [
        {"tech": "lotus_breathing", "rank": 0, "merit": 60},
        {"tech": "flowing_strikes", "rank": 1, "merit": 150},
        {"tech": "lotus_body", "rank": 2, "merit": 350},
        {"tech": "heart_of_the_lotus", "rank": 3, "merit": 800},
        {"tech": "thousand_petal_guard", "rank": 4, "merit": 1800},
    ],
}

TECHS = {
    "lotus_breathing": {"name": "Lotus Breathing", "kind": "passive", "realm": 1, "desc": "The Academy's first lesson: breathe like a lotus opening. You cultivate 30% faster.",
                        "effect": {"meditate_mult": 1.3}, "hint": "Taught in the Lotus Ascent Academy's library.", "unlock": {"academy": True}},
    "flowing_strikes": {"name": "Flowing Strikes", "kind": "passive", "realm": 2, "desc": "Each strike flows into the next. You attack 10% faster.",
                        "effect": {"attack_speed": 1.1}, "hint": "Taught in the Lotus Ascent Academy's library.", "unlock": {"academy": True}},
    "lotus_body": {"name": "Lotus Body", "kind": "passive", "realm": 3, "desc": "A body that closes its wounds like petals at dusk. +12% HP.",
                   "effect": {"hp_mult": 1.12}, "hint": "Taught in the Lotus Ascent Academy's library.", "unlock": {"academy": True}},
    "heart_of_the_lotus": {"name": "Heart of the Lotus", "kind": "passive", "realm": 4, "desc": "Qi gathers to you as water gathers to a pond. +20% qi.",
                           "effect": {"qi_mult": 1.2}, "hint": "Taught in the Lotus Ascent Academy's library.", "unlock": {"academy": True}},
    "thousand_petal_guard": {"name": "Thousand-Petal Guard", "kind": "passive", "realm": 6, "desc": "Blows slide off a thousand layered petals of qi. 12% less damage taken.",
                             "effect": {"damage_taken": 0.88}, "hint": "Taught in the Lotus Ascent Academy's library.", "unlock": {"academy": True}},
}

ITEMS = {
    "lotus_disciple_robe": {"name": "Lotus Disciple's Robe", "type": "armor", "hp": 120, "value": 200,
                            "effect": {"meditate_mult": 1.1},
                            "desc": "White silk with a lotus at the breast. Every disciple gets one; nobody sells one. +120 max HP, cultivate 10% faster."},
}


def main():
    g = load("guilds.json"); g["academy"] = ACADEMY; save("guilds.json", g)
    t = load("techniques.json"); t.update(TECHS); save("techniques.json", t)
    it = load("items.json"); it.update(ITEMS); save("items.json", it)
    en = load("enemies.json")
    for c in ACADEMY["contracts"]:
        k = c["goal"].get("kill")
        assert not k or k in en, k
    it = load("items.json")
    for c in ACADEMY["contracts"]:
        k = c["goal"].get("craft")
        assert not k or k in it, k
    print("academy ranks", len(ACADEMY["ranks"]), "library", len(ACADEMY["library"]))


if __name__ == "__main__":
    main()
