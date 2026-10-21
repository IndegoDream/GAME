#!/usr/bin/env python3
"""Round 121: writes data/classes.json (the Paths -- nine classes, five ranks each).
All numbers live here; Paths.gd reads the result. Deltas follow the title-gift
convention: multiplier keys are added to 1.0 (0.04 = +4%), additive keys as-is,
damage_taken deltas are negative (-0.05 = 5% less)."""
import json, sys

BLADE = ["sword", "saber"]
HEAVY = ["axe", "hammer", "halberd", "spear"]
RANGED = ["bow", "crossbow"]
KI = ["ki", "unarmed", "staff"]
DAGGER = ["dagger"]
SMITH = ["hammer", "axe"]
STAFF = ["staff"]

REALM_GATE = [0, 0, 1, 2, 4]          # realm needed for rank 1..5 (rank 1 is free)


def rank(name, text, needs=None, always=None, weapon=None, trigger=None, title=None, art=False):
    r = {"name": name, "text": text}
    if needs:
        r["needs"] = needs
    if always:
        r["always"] = always
    if weapon:
        r["weapon"] = {"skills": weapon[0], "effect": weapon[1]}
    if trigger:
        r["trigger"] = trigger
    if title:
        r["title"] = title
    if art:
        r["art"] = True
    return r


P = {}

P["duelist"] = {
    "name": "Duelist", "color": [0.85, 0.9, 1.0],
    "blurb": "Sword and saber, timing, the clean answer. You win by being exactly where the blow is not.",
    "weapons": BLADE,
    "deeds": {
        "cuts": {"label": "foes felled with a sword or saber", "ev": ["kill"], "skills": BLADE},
        "parries": {"label": "blows parried", "ev": ["parry"]},
        "bosses": {"label": "great foes felled with a blade", "ev": ["boss_kill"], "skills": BLADE},
    },
    "art": {"name": "Riposte Stance", "cooldown": 24.0, "secs": 7.0,
            "desc": "For 7 seconds your parry window is wider, you strike harder, and every parry you make arms your next blow (+50%).",
            "buff": {"damage_mult": 0.15, "timing": 0.05}, "on_parry_ambush": {"mult": 1.5, "secs": 3.0}},
    "ranks": [
        rank("Student of the Edge", "You were taught the stance, and little else.", weapon=(BLADE, {"damage_mult": 0.04})),
        rank("Fencer", "You read a blow's start. Parries come easier, and you learn Riposte Stance.", {"cuts": 30, "parries": 8},
             always={"timing": 0.02}, weapon=(BLADE, {"attack_speed": 0.02}), art=True),
        rank("Blade-Bearer", "Your cuts land where you meant them.", {"cuts": 150, "parries": 40, "bosses": 1},
             always={"crit_chance": 0.03}, weapon=(BLADE, {"damage_mult": 0.06})),
        rank("Master of Answers", "Every parry now arms your next blow.", {"cuts": 500, "parries": 140, "bosses": 4},
             always={"timing": 0.02, "dodge_chance": 0.01},
             trigger={"on": "parry", "do": "ambush", "mult": 1.4, "secs": 3.0, "icd": 1.0,
                      "text": "A parry arms your next blow (+40% for 3 s)."}),
        rank("The Unbroken Edge", "A sword that has never once been late.", {"cuts": 1400, "parries": 400, "bosses": 10},
             weapon=(BLADE, {"damage_mult": 0.08, "attack_speed": 0.04, "crit_chance": 0.02}), title="Of the Unbroken Edge"),
    ],
}

P["vanguard"] = {
    "name": "Vanguard", "color": [1.0, 0.8, 0.55],
    "blurb": "Axe, hammer, halberd and spear. You are the wall the fight happens against, and the breaker of other walls.",
    "weapons": HEAVY,
    "deeds": {
        "blows": {"label": "foes felled with an axe, hammer, halberd or spear", "ev": ["kill"], "skills": HEAVY},
        "breaks": {"label": "foes staggered with a heavy weapon", "ev": ["stagger"], "skills": HEAVY},
        "elites": {"label": "elite foes felled with a heavy weapon", "ev": ["elite_kill"], "skills": HEAVY},
        "bosses": {"label": "great foes felled with a heavy weapon", "ev": ["boss_kill"], "skills": HEAVY},
    },
    "art": {"name": "Ground Slam", "cooldown": 22.0, "secs": 5.0,
            "desc": "Bring the weapon down: everything within four paces takes a heavy blow and is staggered, and you take 30% less damage for 5 seconds.",
            "slam": {"radius": 4.0, "mult": 1.3, "stagger": 1.6}, "buff": {"damage_taken": -0.3}},
    "ranks": [
        rank("Shield-Bearer", "You stand where you are told to stand.", always={"hp_mult": 0.04}, weapon=(HEAVY, {"damage_mult": 0.03})),
        rank("Wall", "You learn Ground Slam, and how to take a blow.", {"blows": 30, "breaks": 6},
             always={"damage_taken": -0.03}, art=True),
        rank("Breaker", "Armour is a suggestion.", {"blows": 150, "breaks": 30, "elites": 3},
             always={"hp_mult": 0.04}, weapon=(HEAVY, {"damage_mult": 0.06})),
        rank("Unmoved", "Staggering a foe steels you: 12% less damage for 4 seconds.", {"blows": 500, "breaks": 100, "bosses": 3},
             always={"damage_taken": -0.03, "regen": 0.5},
             trigger={"on": "stagger", "do": "buff", "effect": {"damage_taken": -0.12}, "secs": 4.0, "icd": 1.0,
                      "text": "A stagger steels you (12% less damage for 4 s)."}),
        rank("The Mountain on Two Legs", "Nothing in the deep has moved you yet.", {"blows": 1400, "breaks": 300, "bosses": 8},
             always={"hp_mult": 0.06, "damage_taken": -0.04}, weapon=(HEAVY, {"damage_mult": 0.07}), title="Mountain on Two Legs"),
    ],
}

P["ranger"] = {
    "name": "Ranger", "color": [0.7, 1.0, 0.6],
    "blurb": "Bow and crossbow. Distance is the whole art: you win the fight before it reaches you.",
    "weapons": RANGED,
    "deeds": {
        "shots": {"label": "arrows and bolts loosed", "ev": ["shot"], "skills": RANGED},
        "kills": {"label": "foes felled with a bow or crossbow", "ev": ["kill"], "skills": RANGED},
        "charged": {"label": "fully drawn shots", "ev": ["shot"], "skills": RANGED, "charged": True},
        "bosses": {"label": "great foes felled at range", "ev": ["boss_kill"], "skills": RANGED},
    },
    "art": {"name": "Hunter's Focus", "cooldown": 26.0, "secs": 8.0, "needs": "ranged",
            "desc": "For 8 seconds you loose faster (+35%) and every shot hits 25% harder. Needs a bow, crossbow or qi focus in hand.",
            "buff": {"attack_speed": 0.35, "ranged_mult": 0.25}},
    "ranks": [
        rank("Marksman", "A steady hand.", weapon=(RANGED, {"ranged_mult": 0.05})),
        rank("Skirmisher", "Move, loose, move. You learn Hunter's Focus.", {"shots": 60, "kills": 20},
             always={"move_mult": 0.03}, art=True),
        rank("Deadeye", "You find the gap in anything.", {"shots": 400, "kills": 100, "charged": 30},
             weapon=(RANGED, {"ranged_mult": 0.07, "crit_chance": 0.03})),
        rank("Rhythm", "A kill quickens the next draw (+12% attack speed for 3 seconds).", {"shots": 1200, "kills": 300, "charged": 120, "bosses": 2},
             always={"dodge_chance": 0.02},
             trigger={"on": "kill", "do": "buff", "effect": {"attack_speed": 0.12}, "secs": 3.0, "icd": 0.5, "skills": RANGED,
                      "text": "A kill with a ranged weapon quickens the next draw (+12% for 3 s)."}),
        rank("Horizon-Piercer", "Your arrows arrive before the sound.", {"shots": 3000, "kills": 800, "charged": 300, "bosses": 6},
             always={"move_mult": 0.03}, weapon=(RANGED, {"ranged_mult": 0.08, "crit_chance": 0.03}), title="Horizon-Piercer"),
    ],
}

P["ki_adept"] = {
    "name": "Ki Adept", "color": [0.6, 0.9, 1.0],
    "blurb": "Bare hands, the staff, the qi focus. You make the body a channel and let the energy out in a line.",
    "weapons": KI,
    "deeds": {
        "kills": {"label": "foes felled with ki, bare hands or a staff", "ev": ["kill"], "skills": KI},
        "bursts": {"label": "charged ki shots and qi bursts", "ev": ["shot", "qi_burst"], "skills": KI},
        "points": {"label": "meridian points opened", "ev": ["point_open"]},
    },
    "art": {"name": "Open the Gates", "cooldown": 30.0, "secs": 8.0,
            "desc": "For 8 seconds your qi flows freely: +25% damage, ki shots come twice as fast, and your ki pool is refilled at once.",
            "buff": {"damage_mult": 0.25, "ki_mult": 1.0}, "refill_ki": True},
    "ranks": [
        rank("Breath-Counter", "You count your breaths, and they count back.", always={"qi_mult": 0.03}, weapon=(KI, {"damage_mult": 0.04})),
        rank("Open Palm", "Ki comes quicker. You learn Open the Gates.", {"kills": 25, "points": 2},
             weapon=(KI, {"ki_mult": 0.10}), art=True),
        rank("Gate-Opener", "Your meridians carry more than they did.", {"kills": 120, "bursts": 15, "points": 8},
             always={"meditate_mult": 0.05, "qi_mult": 0.03}, weapon=(KI, {"damage_mult": 0.06})),
        rank("Flowing Qi", "A kill gives a breath back: +1 ki shot.", {"kills": 400, "bursts": 60, "points": 18},
             weapon=(KI, {"ki_mult": 0.15}),
             trigger={"on": "kill", "do": "ki", "n": 1.0, "icd": 0.5, "skills": KI, "text": "A kill with ki, bare hands or a staff returns one ki shot."}),
        rank("Heaven-Reaching", "The line between you and the sky is straight.", {"kills": 1000, "bursts": 200, "points": 30},
             always={"qi_mult": 0.04, "meditate_mult": 0.05}, weapon=(KI, {"damage_mult": 0.08, "ki_mult": 0.15}), title="Heaven-Reaching"),
    ],
}

P["warden"] = {
    "name": "Nanite Warden", "color": [0.5, 1.0, 0.9],
    "blurb": "The swarm is your armour and your clock. You grow it, tune it, and let it take the blows.",
    "weapons": [],
    "deeds": {
        "kills": {"label": "foes felled", "ev": ["kill"]},
        "parries": {"label": "blows parried", "ev": ["parry"]},
        "nodes": {"label": "nanoforge nodes unlocked", "ev": ["nano_node"]},
        "research": {"label": "tech-tree cards researched", "ev": ["researched"]},
    },
    "art": {"name": "Swarm Shell", "cooldown": 28.0, "secs": 7.0,
            "desc": "The swarm hardens into a shell for 7 seconds: 40% less damage taken and a fast mend.",
            "buff": {"damage_taken": -0.4, "regen": 3.0}},
    "ranks": [
        rank("Seeded", "The swarm answers a little faster.", always={"swarm_mult": 0.04}),
        rank("Shell-Caster", "You learn Swarm Shell.", {"kills": 20, "parries": 5},
             always={"regen": 0.4}, art=True),
        rank("Hive-Mind", "The swarm thinks beside you.", {"kills": 100, "parries": 30, "nodes": 2, "research": 3},
             always={"swarm_mult": 0.06, "hp_mult": 0.04, "damage_taken": -0.03}),
        rank("Counter-Weave", "A parry hardens the swarm: 20% less damage for 3 seconds.", {"kills": 300, "parries": 100, "nodes": 5, "research": 10},
             always={"regen": 0.4, "qi_mult": 0.03},
             trigger={"on": "parry", "do": "buff", "effect": {"damage_taken": -0.2}, "secs": 3.0, "icd": 1.0,
                      "text": "A parry hardens the swarm (20% less damage for 3 s)."}),
        rank("Living Fortress", "You and the swarm are one structure.", {"kills": 900, "parries": 300, "nodes": 9, "research": 25},
             always={"swarm_mult": 0.08, "damage_taken": -0.05, "hp_mult": 0.05, "damage_mult": 0.04}, title="Living Fortress"),
    ],
}

P["shadowblade"] = {
    "name": "Shadowblade", "color": [0.78, 0.7, 1.0],
    "blurb": "The knife. Quick, quiet, never where the blow lands, and always where the opening is.",
    "weapons": DAGGER,
    "deeds": {
        "kills": {"label": "foes felled with a knife", "ev": ["kill"], "skills": DAGGER},
        "dodges": {"label": "rolls and slips", "ev": ["dodge", "perfect_dodge"]},
        "slips": {"label": "perfect dodges", "ev": ["perfect_dodge"]},
        "elites": {"label": "elite foes felled with a knife", "ev": ["elite_kill"], "skills": DAGGER},
    },
    "art": {"name": "Vanish", "cooldown": 20.0, "secs": 4.0,
            "desc": "Slip six paces through anything, then for 4 seconds you are hard to hit (+20% to slip a blow) and your next strike lands for double.",
            "dash": 6.0, "buff": {"dodge_chance": 0.2}, "ambush": {"mult": 2.0, "secs": 4.0}},
    "ranks": [
        rank("Quiet Hands", "You know where your feet are.", always={"dodge_chance": 0.01}, weapon=(DAGGER, {"damage_mult": 0.04})),
        rank("Shade", "You learn Vanish.", {"kills": 30, "dodges": 20},
             always={"move_mult": 0.03}, art=True),
        rank("Knife in the Dark", "Your edge finds the soft places.", {"kills": 150, "dodges": 80, "slips": 15},
             always={"dodge_chance": 0.02}, weapon=(DAGGER, {"damage_mult": 0.06, "crit_chance": 0.04})),
        rank("Ghost's Answer", "A perfect dodge arms your next blow (+70% for 3 seconds).", {"kills": 500, "dodges": 250, "slips": 50, "elites": 3},
             always={"dodge_chance": 0.02},
             trigger={"on": "perfect_dodge", "do": "ambush", "mult": 1.7, "secs": 3.0, "icd": 1.0,
                      "text": "A perfect dodge arms your next blow (+70% for 3 s)."}),
        rank("No Witness", "They never saw it, and they never will.", {"kills": 1400, "dodges": 700, "slips": 150, "elites": 10},
             always={"move_mult": 0.03}, weapon=(DAGGER, {"damage_mult": 0.08, "crit_chance": 0.04, "attack_speed": 0.04}), title="No Witness"),
    ],
}

P["mender"] = {
    "name": "Mender", "color": [0.7, 1.0, 0.8],
    "blurb": "Salve, needle and tincture. You keep yourself and others standing, and you make the medicine.",
    "weapons": STAFF,
    "deeds": {
        "dressings": {"label": "wounds dressed with a salve", "ev": ["use_item"], "heal": True},
        "brews": {"label": "medicines and elixirs made", "ev": ["craft"], "success": True, "craft_skills": ["medicine", "alchemy"]},
        "herbs": {"label": "herbs gathered", "ev": ["gather"], "gather_kinds": ["herb"]},
        "rests": {"label": "times you rested", "ev": ["rest"]},
    },
    "art": {"name": "Triage", "cooldown": 40.0, "secs": 10.0,
            "desc": "Take stock and treat yourself: heal 30% of your health at once, ease an injured meridian, and mend +3 a second for 10 seconds.",
            "heal_pct": 0.3, "mend": 30.0, "buff": {"regen": 3.0}},
    "ranks": [
        rank("Bandage-Hand", "You mend what you can.", always={"regen": 0.4, "craft_success_medicine": 0.03}),
        rank("Field Physician", "You learn Triage, and each kill steadies you.", {"dressings": 10, "herbs": 8},
             always={"heal_on_kill": 2}, art=True),
        rank("Herbwise", "You know what grows and what it is for.", {"dressings": 40, "brews": 10, "herbs": 30},
             always={"craft_success_medicine": 0.04, "craft_success_alchemy": 0.04, "regen": 0.4, "hp_mult": 0.03}),
        rank("Quiet Miracle", "Using a salve starts a slow mend (+2 a second for 10 seconds).", {"dressings": 120, "brews": 40, "rests": 6},
             always={"heal_on_kill": 2},
             trigger={"on": "use_item", "do": "buff", "effect": {"regen": 2.0}, "secs": 10.0, "icd": 2.0, "heal": True,
                      "text": "Using a healing item starts a slow mend (+2 a second for 10 s)."}),
        rank("The Hand That Mends", "Where you stand, things get better.", {"dressings": 300, "brews": 100, "rests": 15},
             always={"regen": 0.8, "hp_mult": 0.05, "heal_on_kill": 2, "craft_success_medicine": 0.04},
             weapon=(STAFF, {"damage_mult": 0.06}), title="The Hand That Mends"),
    ],
}

P["forgewright"] = {
    "name": "Forgewright", "color": [1.0, 0.7, 0.45],
    "blurb": "Hammer and anvil. You make the gear that wins the fight, and fight in it.",
    "weapons": SMITH,
    "deeds": {
        "crafts": {"label": "pieces forged at the anvil", "ev": ["craft"], "success": True, "craft_skills": ["smithing"]},
        "designs": {"label": "designed pieces made", "ev": ["forge"], "success": True},
        "ore": {"label": "veins mined", "ev": ["gather"], "gather_kinds": ["mine", "gem"]},
    },
    "art": {"name": "Temper", "cooldown": 45.0, "secs": 20.0,
            "desc": "Fold your own qi into your gear for 20 seconds: +18% damage and 15% less damage taken.",
            "buff": {"damage_mult": 0.18, "damage_taken": -0.15}},
    "ranks": [
        rank("Hammer-Hand", "You know the weight of a hammer.", always={"craft_success_smithing": 0.03}, weapon=(SMITH, {"damage_mult": 0.04})),
        rank("Temperer", "You learn Temper.", {"crafts": 5, "ore": 10},
             always={"craft_quality_smithing": 0.02}, art=True),
        rank("Journeyman of the Anvil", "Your work comes out true.", {"crafts": 25, "designs": 5, "ore": 40},
             always={"craft_success_smithing": 0.04, "hp_mult": 0.03}, weapon=(SMITH, {"damage_mult": 0.05})),
        rank("Fresh From the Forge", "Finishing a piece sets your arm: +10% damage for five minutes.", {"crafts": 80, "designs": 20, "ore": 120},
             always={"craft_quality_smithing": 0.03},
             trigger={"on": "craft", "do": "buff", "effect": {"damage_mult": 0.10}, "secs": 300.0, "icd": 5.0, "success": True, "craft_skills": ["smithing"],
                      "text": "Finishing a piece at the anvil gives +10% damage for five minutes."}),
        rank("Heirloom-Maker", "What you make outlasts you.", {"crafts": 200, "designs": 60, "ore": 300},
             always={"craft_success_smithing": 0.05, "hp_mult": 0.04, "damage_taken": -0.04}, weapon=(SMITH, {"damage_mult": 0.06}), title="Heirloom-Maker"),
    ],
}

P["delver"] = {
    "name": "Delver", "color": [1.0, 0.92, 0.5],
    "blurb": "Lamp, pick and a good nose. You find what the deep hides, and you come back with more than you took.",
    "weapons": [],
    "deeds": {
        "gathers": {"label": "veins, herbs and catches gathered", "ev": ["gather"]},
        "chests": {"label": "chests opened", "ev": ["chest"]},
        "secrets": {"label": "secret walls found", "ev": ["secret", "secret_noticed"]},
        "traps": {"label": "traps spotted", "ev": ["trap_spotted"]},
        "floors": {"label": "floors cleared", "ev": ["floor_cleared"]},
    },
    "art": {"name": "Pathfinder's Sense", "cooldown": 60.0, "secs": 25.0,
            "desc": "For 25 seconds hidden things hum louder (+14 sense radius), you see further, move 15% faster and find better loot.",
            "buff": {"sense_radius": 14.0, "sight": 3.0, "move_mult": 0.15, "loot_luck": 0.15}},
    "ranks": [
        rank("Lamp-Carrier", "You bring a light, and you look.", always={"sight": 1.0, "loot_luck": 0.02}),
        rank("Pathfinder", "You learn Pathfinder's Sense.", {"gathers": 15, "chests": 3},
             always={"sense_radius": 4.0}, art=True),
        rank("Trap-Wise", "You read a floor the way others read a page.", {"gathers": 50, "chests": 12, "secrets": 3},
             always={"loot_luck": 0.03, "gather_chance": 0.1, "move_mult": 0.03}),
        rank("Secret-Reader", "Finding a secret sharpens your luck (+10% loot luck for five minutes).", {"gathers": 150, "chests": 30, "secrets": 10, "traps": 5, "floors": 5},
             always={"sense_radius": 4.0, "sight": 1.0},
             trigger={"on": "secret", "do": "buff", "effect": {"loot_luck": 0.10}, "secs": 300.0, "icd": 5.0,
                      "text": "Finding a secret wall gives +10% loot luck for five minutes."}),
        rank("Master Delver", "There is nothing down here you have not already met.", {"gathers": 400, "chests": 80, "secrets": 30, "traps": 20, "floors": 20},
             always={"loot_luck": 0.04, "gather_bonus": 1.0, "sense_radius": 4.0, "hp_mult": 0.04, "move_mult": 0.03}, title="Master Delver"),
    ],
}

# default flavour for ranks that name no rank art
for pid, p in P.items():
    p["id"] = pid
    # rank gating: realm and the stated deeds
    for i, r in enumerate(p["ranks"]):
        r["realm"] = REALM_GATE[i]

out = {
    "_about": "Round 121 (Robert: 'build out several more class types the players can build out'). The Paths: nine classes. You walk one (a second opens at rank 3), earn ranks by deeds, and each rank gives a perk; rank 2 teaches the path's signature art (key 6), rank 4 a keystone. Perk numbers are deltas like title gifts. Generated by tools/gen/classes_gen.py.",
    "key": "6",
    "rank_names": ["Initiate", "Adept", "Veteran", "Master", "Paragon"],
    "second_path_rank": 3,
    "second_path_share": 0.5,
    "respec_gold_per_realm": 120,
    "respec_free_below_rank": 2,
    "caps": {"damage_mult": 0.25, "ranged_mult": 0.25, "ki_mult": 0.45, "hp_mult": 0.2, "damage_taken": -0.15, "crit_chance": 0.08,
             "dodge_chance": 0.08, "attack_speed": 0.12, "regen": 2.5, "heal_on_kill": 8.0, "swarm_mult": 0.2, "qi_mult": 0.12,
             "meditate_mult": 0.12, "loot_luck": 0.12, "move_mult": 0.12, "timing": 0.06},
    "paths": [P[k] for k in ["duelist", "vanguard", "ranger", "ki_adept", "warden", "shadowblade", "mender", "forgewright", "delver"]],
}
json.dump(out, open(sys.argv[1] if len(sys.argv) > 1 else "classes.json", "w"), indent=1)
print("paths", len(out["paths"]))
