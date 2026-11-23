#!/usr/bin/env python3
"""2026-11-03: the Lands. Ten distinct biome regions (dense, each with its own plants, ores, animals, foes and boss),
chained from the valley and growing harder, then main-quest chapters that walk the player through them to
transcendence. ADDS to data/frontier.json (regions, sites, extra_gates), data/items.json, data/crafting.json,
data/enemies.json and data/main_quest.json; never removes. Idempotent. Run from the project root:
    python3 tools/gen/lands_gen.py"""
import json, os, shutil, sys

def load(p): return json.load(open(p))
def save(p, d): json.dump(d, open(p, "w"), indent=1, ensure_ascii=False)
def backup(p):
    b = p + ".bak-lands"
    if not os.path.exists(b): shutil.copy(p, b)

# id: (name, value, element, traits, desc)
M = {}
def mat(i, n, v, el, tr, d): M[i] = (n, v, el, tr, d)

# ---- Whisperwood
mat("glowcap", "Glowcap", 60, "wood", {"living": 2, "seeking": 1}, "A fungus that glows the colour of a held breath. It grows only where the trees are oldest.")
mat("heartwood", "Heartwood", 84, "wood", {"hard": 2, "living": 2}, "The red core of a very old tree. It is warm to the touch in winter.")
mat("ghostmoth_wing", "Ghost-Moth Wing", 72, "wood", {"supple": 2, "seeking": 2}, "A wing like frosted glass. It trembles toward anything hidden.")
mat("stag_antler", "Spirit-Stag Antler", 96, "wood", {"vital": 2, "resonant": 1}, "Shed in autumn, left where the stag was sure no one would find it.")
mat("wolf_pelt", "Whisper-Wolf Pelt", 70, "wood", {"supple": 2, "warding": 1}, "Grey, thick, and almost silent when it moves.")
mat("old_amber", "Old Amber", 110, "earth", {"binding": 2, "resonant": 2}, "Sap that set while something was still thinking. You can see it, small, inside.")
# ---- Mistfen
mat("bog_lotus", "Bog Lotus", 76, "water", {"vital": 2, "warding": 1}, "Opens at dusk on black water. The petals taste of iron and honey.")
mat("venom_reed", "Venom Reed", 62, "wood", {"volatile": 2, "keen": 1}, "A hollow reed with a bitter milk in it. Handle the cut end with care.")
mat("peat_core", "Peat Core", 58, "earth", {"binding": 2, "living": 1}, "A black brick of centuries of moss, still faintly alive.")
mat("will_o_oil", "Will-o'-Wisp Oil", 118, "fire", {"seeking": 2, "volatile": 2}, "A drop of pale fire in a skin of marsh gas. It wants to lead you somewhere.")
mat("toad_gland", "Fen-Toad Gland", 54, "water", {"vital": 1, "volatile": 1}, "Slick, cold, and powerfully medicinal if you can stomach it.")
mat("drowned_pearl", "Drowned Pearl", 125, "water", {"resonant": 2, "warding": 2}, "Dull on the outside. Held to a lamp, it holds a small moon.")
# ---- Bonefields
mat("grave_bloom", "Grave Bloom", 70, "earth", {"vital": 1, "warding": 2}, "White flowers that grow in rows, exactly where someone was buried.")
mat("battle_iron", "Battle Iron", 92, "metal", {"hard": 3, "binding": 1}, "Iron that was swung in anger and survived it. It remembers the weight.")
mat("marrow_salt", "Marrow Salt", 88, "earth", {"vital": 2, "volatile": 1}, "A pale crust on old bone. The swarm in your blood is curious about it.")
mat("widow_shroud", "Widow's Shroud", 100, "wood", {"warding": 3, "supple": 1}, "Grave-cloth that never rotted. Whoever it covered is long gone; the cloth stays.")
mat("war_standard", "Torn War Standard", 130, "metal", {"resonant": 2, "keen": 1, "binding": 1}, "A banner worn to threads. It still points the way an army went.")
# ---- Jadehill Terraces
mat("terrace_jade", "Terrace Jade", 120, "earth", {"resonant": 2, "warding": 2}, "Green stone cut from a farmed hillside. Tended, not mined.")
mat("cloud_rice", "Cloud Rice", 74, "wood", {"vital": 3, "living": 1}, "A pale grain grown above the mist. A bowl is worth a day of meditation.")
mat("crane_feather", "Crane Feather", 98, "wood", {"supple": 3, "seeking": 1}, "White as paper, light as a thought, and never wet.")
mat("sage_tea_leaf", "Sage Tea Leaf", 82, "wood", {"seeking": 2, "vital": 2}, "Picked at dawn from terraces older than the sects.")
mat("monkey_charm", "Monkey King's Charm", 140, "metal", {"keen": 2, "supple": 2}, "A trinket the bandits steal from each other. It is always warm.")
# ---- Sunken Mere
mat("pearl_oyster", "Mere Pearl", 130, "water", {"resonant": 3, "warding": 1}, "Grown slowly in cold, clear water. Perfectly round.")
mat("serpent_scale", "Serpent Scale", 112, "water", {"hard": 2, "supple": 2}, "A scale as wide as a palm. Cool, flexible, and extremely tough.")
mat("kelp_silk", "Kelp Silk", 78, "water", {"supple": 3, "living": 1}, "Fibres drawn from deep kelp. Spun, they make a cloth that sheds blows.")
mat("drowned_crown", "Drowned Crown Shard", 150, "metal", {"resonant": 3, "binding": 1}, "A fragment of something worn by a king who is now fish food.")
mat("river_otter_pelt", "Otter Pelt", 66, "water", {"supple": 2, "warding": 1}, "Dense, oily, and exactly as warm as it looks.")
# ---- Stormcliffs
mat("thunder_iron", "Thunder Iron", 124, "metal", {"conductive": 3, "hard": 2}, "Iron where lightning has struck again and again. It hums before a storm.")
mat("storm_glass", "Storm Glass", 140, "fire", {"conductive": 2, "keen": 2, "volatile": 1}, "Glass fused by a bolt, still holding a little of its fury.")
mat("roc_quill", "Roc Quill", 118, "wood", {"supple": 2, "keen": 2}, "A feather as long as your arm. It slices the wind like a blade.")
mat("sky_lichen", "Sky Lichen", 80, "wood", {"warding": 2, "vital": 1}, "Clings to cliffs no one has climbed.")
mat("tempest_heart", "Tempest Heart", 180, "fire", {"volatile": 3, "resonant": 2}, "A knot of storm in a stone shell. It will not stay still.")
# ---- Emberwaste
mat("firestone", "Cinderstone", 104, "fire", {"volatile": 2, "hard": 1}, "A black stone that is warm in a cold room.")
mat("ash_blossom", "Ash Blossom", 88, "fire", {"vital": 2, "volatile": 1}, "Grows from cooled lava. The petals are grey, the heart is red.")
mat("magma_crab_shell", "Magma-Crab Shell", 132, "fire", {"hard": 3, "warding": 1}, "Plate that has been molten and cooled a hundred times.")
mat("drake_ember", "Drake Ember", 190, "fire", {"volatile": 3, "keen": 1}, "A coal from something that breathes fire. It never quite goes out.")
mat("obsidian_edge", "Obsidian Edge", 116, "earth", {"keen": 3, "hard": 1}, "A sliver of volcanic glass. You can shave with it.")
# ---- Frostmere
mat("frost_lotus", "Frost Lotus", 118, "water", {"warding": 2, "vital": 2}, "Blooms through ice. The petals are cold enough to burn.")
mat("rime_crystal", "Rime Crystal", 134, "water", {"resonant": 3, "keen": 1}, "A crystal grown in a single winter night. It rings when touched.")
mat("snow_lynx_pelt", "Snow-Lynx Pelt", 108, "water", {"supple": 3, "warding": 1}, "White and soft as breath. It keeps in all heat.")
mat("wendigo_horn", "Wendigo Horn", 176, "water", {"hard": 2, "volatile": 2}, "A horn from something that was once a man. It carries a cold hunger.")
mat("glacier_heart", "Glacier Heart", 200, "water", {"resonant": 2, "warding": 3}, "Blue and blind-bright. It makes a perfect cold.")
# ---- Sandglass Dunes
mat("desert_rose", "Desert Rose", 96, "earth", {"seeking": 2, "keen": 1}, "A crystal flower of sand and mineral, edges like petals.")
mat("scorpion_stinger", "Dune-Scorpion Stinger", 110, "earth", {"keen": 2, "volatile": 2}, "A curved black barb, still wet at the tip.")
mat("hourglass_sand", "Hourglass Sand", 150, "earth", {"resonant": 2, "binding": 2}, "Sand that remembers falling. Hold it and the hour slips by differently.")
mat("sun_scarab", "Sun Scarab", 128, "fire", {"hard": 2, "living": 2}, "A gold beetle shell the size of a fist. It's warm all night.")
mat("sand_giant_core", "Sand-Giant Core", 195, "earth", {"hard": 3, "binding": 2}, "A fist of packed stone from the heart of a giant of sand.")
# ---- Blighted Deep Wood
mat("blight_bloom", "Blight Bloom", 170, "wood", {"nano": 2, "volatile": 2, "vital": 1}, "A flower grown wrong. The swarm in your blood leans toward it.")
mat("nanite_sap", "Nanite Sap", 190, "wood", {"nano": 3, "living": 2}, "Sap with a glitter in it. It moves when you aren't looking.")
mat("warped_heartwood", "Warped Heartwood", 180, "wood", {"nano": 2, "hard": 3}, "Wood that grew around a machine and learned its shape.")
mat("corrupted_antler", "Corrupted Antler", 200, "wood", {"nano": 2, "keen": 2, "volatile": 1}, "An antler with wire in it. It twitches.")
mat("root_king_seed", "Root King's Seed", 260, "wood", {"nano": 3, "living": 3, "resonant": 1}, "The seed of something that is still growing, a very long way down.")

# product: (name, value, element, traits, desc, needs, skill, difficulty, price, sold_by, hint)
P = {
 "wildwood_tonic": ("Wildwood Tonic", 150, "wood", {"vital": 3, "living": 2}, "A green, thick tonic. It mends and it steadies.", {"glowcap": 2, "stag_antler": 1}, "alchemy", 4, 180, ["alchemist"], "Glowcap and antler together make the oldest tonic in the wood."),
 "heartwood_bow": ("Heartwood Stave", 210, "wood", {"hard": 2, "supple": 2, "living": 1}, "A bow stave that keeps its draw for a lifetime.", {"heartwood": 2, "wolf_pelt": 1}, "smithing", 5, 240, ["smith"], "Heartwood and pelt for a stave and its grip."),
 "fen_antivenom": ("Fen Antivenom", 140, "water", {"vital": 3, "warding": 2}, "Bitter, quick, and it ends most poisons.", {"bog_lotus": 2, "toad_gland": 1}, "alchemy", 4, 170, ["alchemist"], "Lotus cools, toad draws it out."),
 "wisp_lantern": ("Wisp Lantern", 260, "fire", {"seeking": 3, "resonant": 1}, "A lantern that shows what is hidden nearby.", {"will_o_oil": 1, "drowned_pearl": 1}, "jewelcrafting", 6, 300, ["merchant"], "Oil in a pearl shell."),
 "grave_ward": ("Grave Ward", 200, "earth", {"warding": 3, "resonant": 1}, "A charm of shroud and bloom that quiets the restless dead.", {"grave_bloom": 2, "widow_shroud": 1}, "jewelcrafting", 6, 240, ["merchant"], "Bloom and shroud, bound with a knot."),
 "warsteel": ("Warsteel", 280, "metal", {"hard": 3, "binding": 3}, "Battle iron re-folded with marrow salt. It rings like a bell.", {"battle_iron": 2, "marrow_salt": 1}, "smithing", 7, 320, ["smith"], "Fold the iron with salt from the bones."),
 "terrace_elixir": ("Terrace Elixir", 290, "wood", {"vital": 3, "seeking": 2, "living": 1}, "Rice and tea, brewed into something that sharpens the mind.", {"cloud_rice": 2, "sage_tea_leaf": 1}, "alchemy", 7, 330, ["alchemist"], "Rice, sage, and patience."),
 "crane_cloak": ("Crane-Feather Cloak", 310, "wood", {"supple": 3, "seeking": 2, "warding": 1}, "A cloak that makes the wearer lighter on their feet.", {"crane_feather": 3, "kelp_silk": 1}, "jewelcrafting", 7, 350, ["merchant"], "Feathers stitched with silk."),
 "mere_mail": ("Serpent Mail", 340, "water", {"hard": 3, "supple": 2, "warding": 1}, "Scale armour that turns blades like water turns stones.", {"serpent_scale": 3, "kelp_silk": 1}, "smithing", 8, 380, ["smith"], "Scales overlap like a fish."),
 "storm_edge": ("Stormsteel", 380, "metal", {"conductive": 3, "keen": 2, "hard": 2}, "Thunder iron tempered in a bolt. It bites.", {"thunder_iron": 2, "storm_glass": 1}, "smithing", 9, 420, ["smith"], "Iron and glass struck by the same sky."),
 "cinder_plate": ("Cinder Plate", 360, "fire", {"hard": 3, "warding": 2, "volatile": 1}, "Magma-crab plate fired a last time. Fireproof, nearly.", {"magma_crab_shell": 2, "firestone": 1}, "smithing", 9, 400, ["smith"], "Shell and stone, cooked slowly."),
 "frost_draught": ("Frost Draught", 350, "water", {"warding": 3, "vital": 2, "resonant": 1}, "A calm, cold drink that settles the meridians.", {"frost_lotus": 2, "rime_crystal": 1}, "alchemy", 9, 390, ["alchemist"], "Lotus petals dissolved in rime."),
 "sand_lens": ("Hourglass Lens", 400, "earth", {"resonant": 3, "seeking": 2, "binding": 1}, "A lens of old sand that slows what it looks at.", {"hourglass_sand": 2, "desert_rose": 1}, "jewelcrafting", 10, 450, ["merchant"], "Sand, ground and set."),
 "blight_graft": ("Blight Graft", 520, "wood", {"nano": 3, "living": 3, "hard": 1}, "A living graft of wood and swarm. It keeps growing.", {"nanite_sap": 2, "warped_heartwood": 1}, "alchemy", 12, 600, ["alchemist"], "The sap wants to be part of something."),
}

# foes: id, name, kind, floor, model, tint, scale, loot, extra
FOES = [
 # Whisperwood
 ("whisper_wolf", "Whisper-Wolf", "weak", 8, "beast", [0.55, 0.58, 0.62], 1.0, {"gold": [14, 30], "wolf_pelt": [0, 2]}, {"speed": 5.0, "passive": False}),
 ("thornling_ranger", "Thornling Ranger", "weak", 9, "human", [0.45, 0.7, 0.4], 0.95, {"gold": [16, 34], "heartwood": [0, 1], "glowcap": [0, 1]}, {"range": 6.0}),
 ("moss_ogre", "Moss Ogre", "brute", 10, "orc", [0.4, 0.6, 0.35], 1.5, {"gold": [50, 90], "heartwood": [1, 2], "old_amber": [0, 1]}, {}),
 ("spirit_stag", "Spirit Stag", "animal", 9, "beast", [0.8, 0.9, 0.95], 1.3, {"gold": [10, 24], "stag_antler": [0, 1]}, {"passive": True, "speed": 5.2}),
 ("ghost_moth", "Ghost Moth", "animal", 8, "beast", [0.85, 0.9, 1.0], 0.7, {"gold": [6, 14], "ghostmoth_wing": [0, 1]}, {"passive": True, "speed": 4.5}),
 ("elder_treant", "The Elder Treant of Whisperwood", "boss", 10, "orc", [0.45, 0.65, 0.35], 2.7, {"gold": [700, 950], "old_amber": [2, 4], "heartwood": [3, 5], "stag_antler": [1, 2]}, {}),
 # Mistfen
 ("fen_toad", "Fen Toad", "animal", 10, "beast", [0.45, 0.62, 0.4], 0.9, {"gold": [8, 20], "toad_gland": [0, 2]}, {"passive": False, "speed": 4.2}),
 ("bog_wraith", "Bog Wraith", "weak", 11, "human", [0.55, 0.7, 0.6], 1.05, {"gold": [22, 44], "will_o_oil": [0, 1], "peat_core": [0, 1]}, {}),
 ("leech_swarm", "Leech Swarm", "weak", 10, "beast", [0.25, 0.3, 0.25], 0.8, {"gold": [14, 28], "venom_reed": [0, 1]}, {"speed": 4.8, "passive": False}),
 ("mire_hulk", "Mire Hulk", "brute", 12, "orc", [0.3, 0.4, 0.3], 1.6, {"gold": [70, 120], "peat_core": [1, 3], "drowned_pearl": [0, 1]}, {}),
 ("hag_of_the_fen", "The Hag of the Fen", "boss", 12, "human", [0.4, 0.55, 0.45], 2.3, {"gold": [900, 1200], "drowned_pearl": [2, 3], "will_o_oil": [2, 3], "bog_lotus": [3, 5]}, {}),
 # Bonefields
 ("bone_hound", "Bone Hound", "weak", 11, "beast", [0.85, 0.82, 0.75], 1.0, {"gold": [20, 40], "marrow_salt": [0, 1]}, {"speed": 5.0, "passive": False}),
 ("restless_soldier", "Restless Soldier", "weak", 12, "human", [0.7, 0.68, 0.62], 1.05, {"gold": [24, 46], "battle_iron": [0, 2]}, {}),
 ("carrion_crow", "Carrion Crow", "animal", 11, "beast", [0.15, 0.15, 0.2], 0.8, {"gold": [8, 18], "widow_shroud": [0, 1]}, {"passive": False, "speed": 5.0}),
 ("grave_knight", "Grave Knight", "brute", 13, "orc", [0.7, 0.72, 0.8], 1.6, {"gold": [90, 150], "battle_iron": [1, 3], "war_standard": [0, 1]}, {}),
 ("general_of_the_fallen", "The General of the Fallen", "boss", 13, "human", [0.8, 0.8, 0.9], 2.4, {"gold": [1100, 1500], "war_standard": [2, 3], "battle_iron": [4, 6], "marrow_salt": [2, 3]}, {}),
 # Jadehill Terraces
 ("monkey_bandit", "Monkey Bandit", "weak", 14, "human", [0.7, 0.5, 0.3], 0.85, {"gold": [40, 80], "monkey_charm": [0, 1]}, {"speed": 5.2}),
 ("terrace_guardian", "Terrace Guardian", "brute", 15, "orc", [0.5, 0.75, 0.6], 1.6, {"gold": [110, 170], "terrace_jade": [1, 2]}, {}),
 ("white_crane", "White Crane", "animal", 14, "beast", [0.97, 0.97, 1.0], 1.1, {"gold": [12, 26], "crane_feather": [0, 2]}, {"passive": True, "speed": 4.6}),
 ("jade_hermit", "The Jade Hermit", "boss", 16, "human", [0.5, 0.85, 0.65], 2.4, {"gold": [1500, 2000], "terrace_jade": [4, 6], "sage_tea_leaf": [3, 5], "monkey_charm": [1, 2]}, {}),
 # Sunken Mere
 ("mere_serpent", "Mere Serpent", "weak", 15, "beast", [0.3, 0.6, 0.7], 1.4, {"gold": [45, 85], "serpent_scale": [0, 2]}, {"speed": 4.4, "passive": False}),
 ("drowned_one", "Drowned One", "weak", 16, "human", [0.5, 0.65, 0.7], 1.0, {"gold": [50, 90], "kelp_silk": [0, 2], "drowned_crown": [0, 1]}, {}),
 ("river_otter_pack", "River Otter", "animal", 14, "beast", [0.45, 0.35, 0.3], 0.8, {"gold": [8, 20], "river_otter_pelt": [0, 2]}, {"passive": True, "speed": 5.0}),
 ("kelp_horror", "Kelp Horror", "brute", 17, "orc", [0.25, 0.5, 0.35], 1.8, {"gold": [130, 200], "kelp_silk": [1, 3], "pearl_oyster": [0, 1]}, {}),
 ("mere_matriarch", "The Mere Matriarch", "boss", 17, "beast", [0.2, 0.55, 0.65], 3.0, {"gold": [1700, 2300], "pearl_oyster": [3, 5], "serpent_scale": [4, 6], "drowned_crown": [1, 2]}, {}),
 # Stormcliffs
 ("cliff_roc", "Cliff Roc", "weak", 18, "beast", [0.7, 0.62, 0.5], 1.5, {"gold": [60, 100], "roc_quill": [0, 2]}, {"speed": 5.5, "passive": False}),
 ("storm_sprite", "Storm Sprite", "weak", 19, "human", [0.7, 0.85, 1.0], 0.7, {"gold": [60, 105], "storm_glass": [0, 1]}, {"speed": 5.0, "range": 7.0}),
 ("thunder_ram", "Thunder Ram", "brute", 20, "beast", [0.8, 0.8, 0.9], 1.7, {"gold": [150, 230], "thunder_iron": [1, 3]}, {}),
 ("storm_lord", "The Storm Lord", "boss", 20, "human", [0.65, 0.8, 1.0], 2.6, {"gold": [2300, 3000], "tempest_heart": [1, 2], "thunder_iron": [4, 6], "storm_glass": [3, 5]}, {}),
 # Emberwaste
 ("magma_crab", "Magma Crab", "weak", 20, "beast", [0.9, 0.4, 0.2], 1.2, {"gold": [70, 115], "magma_crab_shell": [0, 1]}, {"speed": 4.0, "passive": False}),
 ("cinder_imp_pack", "Cinder Imp", "weak", 21, "human", [1.0, 0.5, 0.25], 0.8, {"gold": [75, 120], "firestone": [0, 2]}, {"speed": 5.0}),
 ("ash_drake", "Ash Drake", "brute", 22, "beast", [0.55, 0.3, 0.25], 1.9, {"gold": [200, 300], "drake_ember": [0, 1], "obsidian_edge": [0, 2]}, {}),
 ("caldera_tyrant", "The Caldera Tyrant", "boss", 22, "beast", [0.9, 0.35, 0.15], 3.2, {"gold": [3000, 3800], "drake_ember": [3, 5], "magma_crab_shell": [4, 6], "ash_blossom": [3, 5]}, {}),
 # Frostmere
 ("snow_lynx", "Snow Lynx", "weak", 22, "beast", [0.95, 0.97, 1.0], 1.1, {"gold": [80, 130], "snow_lynx_pelt": [0, 2]}, {"speed": 5.4, "passive": False}),
 ("ice_wight", "Ice Wight", "weak", 23, "human", [0.7, 0.88, 1.0], 1.05, {"gold": [85, 135], "rime_crystal": [0, 1]}, {}),
 ("wendigo", "Wendigo", "brute", 24, "orc", [0.85, 0.9, 0.95], 1.9, {"gold": [220, 330], "wendigo_horn": [0, 1], "frost_lotus": [0, 2]}, {}),
 ("glacier_empress", "The Glacier Empress", "boss", 24, "human", [0.7, 0.9, 1.0], 2.7, {"gold": [3400, 4300], "glacier_heart": [1, 2], "rime_crystal": [4, 6], "frost_lotus": [3, 5]}, {}),
 # Sandglass Dunes
 ("dune_scorpion", "Dune Scorpion", "weak", 23, "beast", [0.85, 0.7, 0.4], 1.3, {"gold": [85, 135], "scorpion_stinger": [0, 1]}, {"speed": 4.6, "passive": False}),
 ("sun_scarab_swarm", "Sun Scarab", "animal", 22, "beast", [0.95, 0.8, 0.2], 0.8, {"gold": [20, 40], "sun_scarab": [0, 1]}, {"passive": False, "speed": 5.0}),
 ("sand_giant", "Sand Giant", "brute", 25, "orc", [0.85, 0.75, 0.5], 2.1, {"gold": [260, 380], "sand_giant_core": [0, 1], "hourglass_sand": [0, 2]}, {}),
 ("pharaoh_of_hours", "The Pharaoh of Hours", "boss", 25, "human", [1.0, 0.85, 0.45], 2.7, {"gold": [4000, 5000], "hourglass_sand": [4, 6], "sand_giant_core": [2, 3], "desert_rose": [3, 5]}, {}),
 # Blighted Deep Wood
 ("blight_stag", "Blight Stag", "weak", 28, "beast", [0.5, 0.75, 0.7], 1.4, {"gold": [140, 220], "corrupted_antler": [0, 1]}, {"speed": 5.4, "passive": False}),
 ("wire_treant", "Wire Treant", "brute", 30, "orc", [0.45, 0.6, 0.55], 2.1, {"gold": [320, 480], "warped_heartwood": [1, 2], "nanite_sap": [0, 2]}, {}),
 ("spore_wraith", "Spore Wraith", "weak", 29, "human", [0.6, 0.85, 0.7], 1.0, {"gold": [150, 230], "blight_bloom": [0, 2]}, {}),
 ("root_king", "The Root King", "boss", 32, "orc", [0.4, 0.7, 0.55], 3.4, {"gold": [7000, 9000], "root_king_seed": [1, 2], "nanite_sap": [4, 6], "warped_heartwood": [3, 5]}, {}),
]
BASE = {"weak": (469, 69, 3.9), "brute": (1223, 89, 2.6), "animal": (245, 41, 4.2), "boss": (6115, 113, 3.0)}
def stats(kind, f):
    hp, dm, sp = BASE[kind]
    k = f - 11
    s = 1 + 0.075 * k if k >= 0 else 1 + 0.045 * k
    return int(hp * s), int(dm * s), sp
def build_foes():
    out = {}
    for fid, name, kind, f, model, tint, scale, loot, extra in FOES:
        hp, dm, sp = stats(kind, f)
        d = {"floor": f, "name": name, "model": model, "tint": tint, "scale": scale, "hp": hp, "damage": dm, "speed": extra.get("speed", sp),
             "aggro": 16 if kind == "boss" else (11 if kind == "brute" else 10), "range": extra.get("range", 3.6 if kind == "boss" else (2.2 if kind == "brute" else 1.8)),
             "cooldown": 1.2, "qi": int(hp * (0.8 if kind == "boss" else 0.35)), "loot": loot, "frontier": True, "land": True}
        if kind == "boss": d["boss"] = True
        if kind == "animal" and extra.get("passive", True): d["passive"] = True
        out[fid] = d
    return out

def herb(i, w, c): return {"id": i, "w": w, "color": c}
def nat(*models, scale=1.0): return "nat:" + "|".join(models) + ":%s" % scale

R = {}
def region(rid, **kw): R[rid] = kw

region("whisperwood", name="Whisperwood", kind="open", w=150, h=118, depth=9, theme="wilds", look="grove",
  blurb="A wood so old the paths are older than the sects. Light comes down in coins. Something always walks a few steps behind you.",
  atmos={"daylight": 0.72, "dusk": 0.5, "clouds": 0.5, "sun": [1.0, 0.92, 0.7], "sun_energy": 0.9, "ambient": [0.45, 0.58, 0.45], "ambient_energy": 0.55, "fog": [0.55, 0.7, 0.55], "fog_density": 0.012, "horizon": [0.45, 0.6, 0.45]},
  rock=0.10, freq=0.06, gate_from="valley", gate_back="8", rim="rocks", ground_tint=[0.7, 0.85, 0.65],
  giants={"x": nat("tree_pineTallA_detailed", "tree_oak", "tree_fat", "tree_pineTallC", scale=1.7), "c": nat("log_large", "stump_roundDetailed", "mushroom_redTall", scale=1.6)},
  lamp="arc", motes="spores", features=["camp", "ruins", "crater", "camp", "ruins", "crater", "ruins"],
  gather={"herb": [herb("glowcap", 5, [0.6, 1.0, 0.8]), herb("ghostmoth_wing", 2, [0.85, 0.9, 1.0]), herb("spirit_herb", 3, [0.5, 1.0, 0.5])], "ore": [{"id": "heartwood", "w": 4}, {"id": "iron_ore", "w": 1}], "gem": [{"id": "old_amber", "w": 3}, {"id": "stag_antler", "w": 2}]},
  density={"h": 70, "o": 200, "^": 200, "x": 28, "c": 70},
  foes=[["whisper_wolf", 26], ["thornling_ranger", 20], ["moss_ogre", 10], ["spirit_stag", 12], ["ghost_moth", 10]], boss="elder_treant",
  npcs=[{"role": "villager", "name": "Warden Isolde", "stays": True, "persona": "Warden Isolde, who walks Whisperwood's paths and keeps count of the stags. Quiet, watchful, fond of the wolves.", "line": "The wood is not hostile. It is attentive. There is a difference, and you will learn it."},
        {"role": "alchemist", "name": "Mossmother Ketta", "stays": True, "persona": "Mossmother Ketta, a forager-alchemist who lives in a hollow log. Brisk, smells of mushrooms, remembers every plant by name.", "line": "Glowcap likes the oldest trunks. Heartwood, the dead ones. Bring me both and I'll make you something."}],
  lore=[{"title": "A Blaze on a Tree", "text": "THREE CUTS, A DOT. THAT MEANS: THE ROAD IS BEHIND YOU. FOLLOW IT WHEN YOU ARE READY TO LEAVE. IF YOU CANNOT FIND IT, THE WOOD HAS DECIDED YOU ARE NOT YET."}])
region("mistfen", name="Mistfen", kind="open", w=140, h=112, depth=11, theme="wilds", look="drowned",
  blurb="A fen under permanent mist. Pale lights drift over the black water. Everything here is patient, and most of it is hungry.",
  atmos={"daylight": 0.55, "dusk": 0.5, "clouds": 0.9, "sun": [0.8, 0.9, 0.85], "sun_energy": 0.6, "ambient": [0.42, 0.55, 0.5], "ambient_energy": 0.55, "fog": [0.62, 0.72, 0.68], "fog_density": 0.02, "horizon": [0.5, 0.6, 0.55]},
  rock=0.12, freq=0.05, gate_from="whisperwood", gate_back="1", rim="rocks", ground_tint=[0.55, 0.7, 0.6],
  giants={"x": nat("tree_thin_dark", "tree_blocks_dark", "tree_default_dark", scale=1.6), "c": nat("log", "stump_squareDetailed", "lily_small", "hanging_moss", scale=1.5)},
  lamp="arc", motes="drips", features=["camp", "ruins", "crater", "crater", "ruins", "camp"],
  gather={"herb": [herb("bog_lotus", 4, [0.7, 0.85, 1.0]), herb("venom_reed", 4, [0.6, 0.8, 0.5]), herb("toad_gland", 1, [0.5, 0.7, 0.5])], "ore": [{"id": "peat_core", "w": 4}], "gem": [{"id": "will_o_oil", "w": 2}, {"id": "drowned_pearl", "w": 2}]},
  density={"h": 70, "o": 170, "^": 220, "x": 30, "c": 60},
  foes=[["fen_toad", 18], ["bog_wraith", 20], ["leech_swarm", 16], ["mire_hulk", 9]], boss="hag_of_the_fen",
  npcs=[{"role": "villager", "name": "Ferryman Oss", "stays": True, "persona": "Ferryman Oss, who poles a flat boat nobody has seen him fill. Slow, dry, expects to be paid in news.", "line": "Follow the pale lights if you want to be lost. Follow the reeds if you want to be somewhere."}],
  lore=[{"title": "Written on a Bog-Post", "text": "THE LIGHTS ARE NOT KIND, BUT THEY ARE HONEST. THEY GO WHERE THEY ARE STILL HUNGRY."}])
region("bonefields", name="The Bonefields", kind="open", w=146, h=116, depth=11, theme="wilds", look="barrows",
  blurb="Two armies met here and did not leave. The grass grows in rows. The banners still point toward the war.",
  atmos={"daylight": 0.6, "dusk": 0.6, "clouds": 0.8, "sun": [0.95, 0.85, 0.75], "sun_energy": 0.7, "ambient": [0.5, 0.5, 0.55], "ambient_energy": 0.5, "fog": [0.6, 0.58, 0.58], "fog_density": 0.009, "horizon": [0.45, 0.42, 0.42]},
  rock=0.15, freq=0.04, gate_from="valley", gate_back="9", rim="rocks", ground_tint=[0.78, 0.74, 0.7],
  giants={"x": nat("statue_head", "stone_tallC", "stone_tallF", "rock_tallA", scale=1.6), "c": nat("fence_broken", "statue_block", "stone_largeA", scale=1.4)},
  lamp="beacon", motes="ash", features=["camp", "ruins", "ruins", "crater", "ruins", "camp", "ruins"],
  gather={"herb": [herb("grave_bloom", 5, [0.95, 0.95, 1.0]), herb("widow_shroud", 1, [0.8, 0.8, 0.85])], "ore": [{"id": "battle_iron", "w": 4}, {"id": "marrow_salt", "w": 2}, {"id": "bone_shard", "w": 4}], "gem": [{"id": "war_standard", "w": 1}, {"id": "silver_ore", "w": 2}]},
  density={"h": 90, "o": 110, "^": 200, "x": 40, "c": 60},
  foes=[["bone_hound", 18], ["restless_soldier", 22], ["carrion_crow", 12], ["grave_knight", 9]], boss="general_of_the_fallen",
  npcs=[{"role": "villager", "name": "Gravewalker Hesk", "stays": True, "persona": "Gravewalker Hesk, who buries what the field gives up. Grim, kind, has stopped being afraid.", "line": "Bone shard for the marrow-forge, if you ask the swarm. Iron for the smith. Take what you need, leave the banners."}],
  lore=[{"title": "A Standard, Planted", "text": "THE FIELD WAS NOT LOST. IT WAS NEVER FOUGHT FOR. THEY JUST KEPT COMING."}])
region("jadehill", name="Jadehill Terraces", kind="open", w=140, h=112, depth=15, theme="wilds", look="canopy",
  blurb="Green stairs of farmed hillside climb into cloud. Everything is tended. Everyone is watching.",
  atmos={"daylight": 0.85, "dusk": 0.3, "clouds": 0.55, "sun": [1.0, 0.97, 0.85], "sun_energy": 1.1, "ambient": [0.6, 0.7, 0.6], "ambient_energy": 0.6, "fog": [0.8, 0.88, 0.85], "fog_density": 0.006, "horizon": [0.7, 0.82, 0.78]},
  rock=0.12, freq=0.045, gate_from="whisperwood", gate_back="2", rim="rocks", ground_tint=[0.7, 0.9, 0.7],
  giants={"x": nat("crops_bambooStageB", "tree_plateau", "tree_cone", scale=1.7), "c": nat("statue_ring", "stone_tallJ", "crops_wheatStageA", scale=1.5)},
  lamp="mirror", motes="leaves", features=["camp", "ruins", "camp", "crater", "ruins"],
  gather={"herb": [herb("cloud_rice", 5, [1.0, 1.0, 0.85]), herb("sage_tea_leaf", 4, [0.6, 0.9, 0.5])], "ore": [{"id": "terrace_jade", "w": 4}, {"id": "iron_ore", "w": 1}], "gem": [{"id": "crane_feather", "w": 2}, {"id": "monkey_charm", "w": 1}, {"id": "rough_jade", "w": 3}]},
  density={"h": 70, "o": 150, "^": 160, "x": 36, "c": 70},
  foes=[["monkey_bandit", 22], ["terrace_guardian", 10], ["white_crane", 12]], boss="jade_hermit",
  npcs=[{"role": "merchant", "name": "Rice-Factor Lin", "stays": True, "persona": "Rice-Factor Lin, who trades terrace harvests to anyone who climbs high enough. Cheerful, shrewd, never rushed.", "line": "A bowl of cloud rice is a day's meditation, they say. I say it is a bowl of rice. But I sell a great deal of it."}],
  lore=[{"title": "A Tally on a Wall", "text": "SEVEN HUNDRED TERRACES. FOUR HUNDRED TENDED. THE REST WAIT FOR THEIR PEOPLE."}])
region("sunken_mere", name="The Sunken Mere", kind="open", w=146, h=116, depth=16, theme="wilds", look="drowned",
  blurb="A drowned valley. Rooftops break the surface like islands. Something large turns slowly beneath them.",
  atmos={"daylight": 0.78, "dusk": 0.4, "clouds": 0.6, "sun": [0.9, 0.98, 1.0], "sun_energy": 0.95, "ambient": [0.5, 0.65, 0.72], "ambient_energy": 0.6, "fog": [0.7, 0.82, 0.88], "fog_density": 0.008, "horizon": [0.55, 0.7, 0.8]},
  rock=0.12, freq=0.04, gate_from="mistfen", gate_back="1", rim="rocks", ground_tint=[0.6, 0.75, 0.8],
  giants={"x": nat("tree_palm", "tree_palmBend", "rock_largeC", scale=1.7), "c": nat("canoe_paddle", "lily_small", "statue_columnDamaged", scale=1.6)},
  lamp="arc", motes="drips", features=["camp", "ruins", "crater", "crater", "ruins", "camp"],
  gather={"herb": [herb("kelp_silk", 4, [0.4, 0.85, 0.6]), herb("bog_lotus", 2, [0.7, 0.85, 1.0])], "ore": [{"id": "serpent_scale", "w": 3}, {"id": "drowned_crown", "w": 1}], "gem": [{"id": "pearl_oyster", "w": 3}, {"id": "river_otter_pelt", "w": 2}]},
  density={"h": 80, "o": 160, "^": 200, "x": 28, "c": 70},
  foes=[["mere_serpent", 18], ["drowned_one", 16], ["river_otter_pack", 12], ["kelp_horror", 8]], boss="mere_matriarch",
  npcs=[{"role": "villager", "name": "Diver Maru", "stays": True, "persona": "Diver Maru, who works the rooftops and the deep. Wry, sunburnt, counts pearls like prayers.", "line": "The big one does not hate you. It is simply very old and very annoyed."}],
  lore=[{"title": "A Rooftop Etching", "text": "WE LEFT BEFORE THE WATER CAME. WE LEFT THE KINGS BEHIND. THE KINGS DID NOT MIND."}])
region("stormcliffs", name="The Stormcliffs", kind="open", w=146, h=116, depth=19, theme="wilds", look="storm",
  blurb="Black cliffs that draw lightning. Rocs nest on the ledges. The thunder here is a language.",
  atmos={"daylight": 0.5, "dusk": 0.6, "clouds": 0.95, "sun": [0.75, 0.8, 0.95], "sun_energy": 0.7, "ambient": [0.4, 0.45, 0.6], "ambient_energy": 0.55, "fog": [0.45, 0.5, 0.62], "fog_density": 0.01, "horizon": [0.3, 0.35, 0.5]},
  rock=0.28, freq=0.05, gate_from="jadehill", gate_back="1", rim="rocks", ground_tint=[0.6, 0.62, 0.72],
  giants={"x": nat("rock_tallH", "rock_tallJ", "stone_tallI", "cliff_rock", scale=1.9), "c": nat("rock_largeA", "stone_largeC", "statue_obelisk", scale=1.6)},
  lamp="beacon", motes="sparks", features=["camp", "pylons", "crater", "ruins", "pylons"],
  gather={"herb": [herb("sky_lichen", 4, [0.7, 0.8, 0.9])], "ore": [{"id": "thunder_iron", "w": 4}, {"id": "storm_glass", "w": 2}], "gem": [{"id": "roc_quill", "w": 3}, {"id": "tempest_heart", "w": 1}, {"id": "sapphire", "w": 1}]},
  density={"h": 80, "o": 130, "^": 140, "x": 34, "c": 80},
  foes=[["cliff_roc", 18], ["storm_sprite", 14], ["thunder_ram", 9]], boss="storm_lord",
  npcs=[{"role": "smith", "name": "Stormsmith Brae", "stays": True, "persona": "Stormsmith Brae, who works lightning into iron on an exposed ledge. Loud, singed, delighted.", "line": "Strike when the sky does. Not before. Not after. I have a lot of burn scars."}],
  lore=[{"title": "A Burned Stone", "text": "HERE THE SKY SPOKE ITS OWN NAME. THE LISTENER WAS NOT HARMED. THE LISTENER WAS NOT THE SAME."}])
region("emberwaste", name="The Emberwaste", kind="open", w=146, h=116, depth=21, theme="wilds", look="ash",
  blurb="A caldera that never finished erupting. Rivers of slow fire. Drakes sleep in the warm stone.",
  atmos={"daylight": 0.7, "dusk": 0.7, "clouds": 0.9, "sun": [1.0, 0.6, 0.4], "sun_energy": 0.9, "ambient": [0.6, 0.4, 0.3], "ambient_energy": 0.6, "fog": [0.55, 0.3, 0.2], "fog_density": 0.012, "horizon": [0.7, 0.35, 0.2]},
  rock=0.24, freq=0.045, gate_from="bonefields", gate_back="1", rim="rocks", ground_tint=[0.55, 0.4, 0.35],
  giants={"x": nat("rock_tallB", "rock_tallE", "rock_tallC", scale=1.9), "c": nat("stone_largeC", "rock_largeE", "stone_tallF", scale=1.6)},
  lamp="furnace", motes="embers", features=["camp", "crater", "ruins", "crater", "camp", "crater"],
  gather={"herb": [herb("ash_blossom", 4, [1.0, 0.5, 0.3])], "ore": [{"id": "firestone", "w": 4}, {"id": "obsidian_edge", "w": 2}], "gem": [{"id": "magma_crab_shell", "w": 2}, {"id": "drake_ember", "w": 1}, {"id": "rough_ruby", "w": 2}]},
  density={"h": 90, "o": 130, "^": 150, "x": 32, "c": 80},
  foes=[["magma_crab", 18], ["cinder_imp_pack", 20], ["ash_drake", 8]], boss="caldera_tyrant",
  npcs=[{"role": "villager", "name": "Cinder-Priest Vahl", "stays": True, "persona": "Cinder-Priest Vahl, who tends a shrine at the caldera's lip. Calm, dry-lipped, unafraid of the heat.", "line": "The drake is not evil. The drake is hungry. That is the same thing for you, I know."}],
  lore=[{"title": "A Shrine of Ash", "text": "THE MOUNTAIN WAKES ONE DAY IN A HUNDRED YEARS. TODAY IS NOT THAT DAY. TODAY IS ONLY HOT."}])
region("frostmere", name="Frostmere", kind="open", w=146, h=116, depth=23, theme="wilds", look="frost",
  blurb="A frozen lake ringed by white pines. The ice sings at night. Something very tall walks the shore.",
  atmos={"daylight": 0.8, "dusk": 0.5, "clouds": 0.7, "sun": [0.85, 0.92, 1.0], "sun_energy": 0.85, "ambient": [0.6, 0.7, 0.85], "ambient_energy": 0.65, "fog": [0.82, 0.9, 1.0], "fog_density": 0.01, "horizon": [0.75, 0.85, 0.95]},
  rock=0.14, freq=0.045, gate_from="stormcliffs", gate_back="1", rim="rocks", ground_tint=[0.9, 0.95, 1.0],
  giants={"x": nat("tree_pineTallD_detailed", "tree_pineTallC", "tree_pineRoundA", "tree_pineSmallD", scale=1.8), "c": nat("rock_largeB", "stone_largeA", "stump_old", scale=1.5)},
  lamp="mirror", motes="snow", features=["camp", "crater", "ruins", "camp", "crater"],
  gather={"herb": [herb("frost_lotus", 3, [0.7, 0.9, 1.0])], "ore": [{"id": "rime_crystal", "w": 4}, {"id": "iron_ore", "w": 1}], "gem": [{"id": "glacier_heart", "w": 1}, {"id": "snow_lynx_pelt", "w": 3}, {"id": "wendigo_horn", "w": 1}]},
  density={"h": 90, "o": 150, "^": 160, "x": 28, "c": 80},
  foes=[["snow_lynx", 16], ["ice_wight", 16], ["wendigo", 8]], boss="glacier_empress",
  npcs=[{"role": "villager", "name": "Ice-Fisher Torvald", "stays": True, "persona": "Ice-Fisher Torvald, who cuts holes in the lake and listens. Taciturn, kind, afraid only of the quiet.", "line": "If the ice stops singing, run. That's the whole of my advice."}],
  lore=[{"title": "A Frost-Written Warning", "text": "HE WALKS THE SHORE BECAUSE HE IS WAITING. DO NOT ASK WHAT FOR."}])
region("sandglass", name="The Sandglass Dunes", kind="open", w=150, h=118, depth=24, theme="wilds", look="glassdune",
  blurb="Dunes that shift by the hour. Time does not keep its shape here. Old cities surface and sink.",
  atmos={"daylight": 1.0, "dusk": 0.4, "clouds": 0.05, "sun": [1.0, 0.85, 0.55], "sun_energy": 1.5, "ambient": [0.75, 0.6, 0.45], "ambient_energy": 0.65, "fog": [0.9, 0.75, 0.55], "fog_density": 0.007, "horizon": [0.85, 0.65, 0.4]},
  rock=0.18, freq=0.03, gate_from="emberwaste", gate_back="1", dunes=True, rim="rocks", ground_tint=[1.0, 0.88, 0.66],
  giants={"x": nat("tree_palm", "tree_palmBend", "rock_tallG", scale=1.8), "c": nat("statue_obelisk", "stone_tallJ", "statue_columnDamaged", scale=1.6)},
  lamp="mirror", motes="dust", features=["dunes", "ruins", "ruins", "camp", "crater", "ruins"],
  gather={"herb": [herb("desert_rose", 3, [0.95, 0.75, 0.55])], "ore": [{"id": "hourglass_sand", "w": 3}, {"id": "scorpion_stinger", "w": 2}], "gem": [{"id": "sun_scarab", "w": 2}, {"id": "sand_giant_core", "w": 1}, {"id": "rough_ruby", "w": 1}]},
  density={"h": 90, "o": 150, "^": 150, "x": 36, "c": 80},
  foes=[["dune_scorpion", 18], ["sun_scarab_swarm", 16], ["sand_giant", 8]], boss="pharaoh_of_hours",
  npcs=[{"role": "villager", "name": "Hourkeeper Isra", "stays": True, "persona": "Hourkeeper Isra, who counts the grains in an hourglass the size of a house. Patient, amused, never in a hurry.", "line": "Three hours from now you will have been here for six. I do not recommend arguing with it."}],
  lore=[{"title": "A Time-Worn Slab", "text": "THE KING ORDERED THE DESERT TO KEEP HIS HOURS. IT OBLIGED. IT HAS NOT STOPPED."}])
region("blighted_wood", name="The Blighted Deep Wood", kind="open", w=160, h=126, depth=30, theme="wilds", look="fungal",
  blurb="The wood past the wood. Trees that grew around machines. The swarm in your blood leans toward it and will not say why.",
  atmos={"daylight": 0.45, "dusk": 0.7, "clouds": 0.95, "sun": [0.6, 0.9, 0.8], "sun_energy": 0.5, "ambient": [0.3, 0.5, 0.45], "ambient_energy": 0.55, "fog": [0.3, 0.55, 0.45], "fog_density": 0.02, "horizon": [0.25, 0.45, 0.4]},
  rock=0.12, freq=0.05, gate_from="whisperwood", gate_back="3", rim="plates", ground_tint=[0.5, 0.75, 0.65],
  giants={"x": nat("tree_blocks_dark", "tree_thin_dark", "tree_default_dark", "tree_cone_dark", scale=2.1), "c": nat("mushroom_redTall", "mushroom_tanTall", "hanging_moss", scale=1.8)},
  lamp="arc", motes="spores", features=["camp", "wreck", "ruins", "crater", "pylons", "ruins", "crater"],
  gather={"herb": [herb("blight_bloom", 4, [0.5, 1.0, 0.7]), herb("nanite_sap", 2, [0.6, 0.9, 1.0])], "ore": [{"id": "warped_heartwood", "w": 4}, {"id": "nanite_ingot", "w": 1}], "gem": [{"id": "corrupted_antler", "w": 2}, {"id": "root_king_seed", "w": 1}, {"id": "ion_crystal", "w": 1}]},
  density={"h": 80, "o": 140, "^": 170, "x": 24, "c": 60},
  foes=[["blight_stag", 20], ["spore_wraith", 18], ["wire_treant", 9]], boss="root_king",
  npcs=[{"role": "villager", "name": "Last Warden Ysolde", "stays": True, "persona": "Last Warden Ysolde, who held the line of the wood after the others fell. Tired, scarred, still pruning.", "line": "I cut what I can and burn what I can't. Something under the roots is awake. It's very polite about it."}],
  lore=[{"title": "A Warden's Last Entry", "text": "THE ROOT KING WAS NEVER A KING. IT WAS A SEED THE SWARM PLANTED, AND IT GREW UP BELIEVING IT WAS THE WORLD."}])

SITES = [  # valley doors out to the Lands
 {"char": "8", "to": "whisperwood", "arrive": "<", "label": "Whisperwood", "style": "hatch", "box": [0.04, 0.40, 0.22, 0.66], "blurb": "a dark line of very old trees"},
 {"char": "9", "to": "bonefields", "arrive": "<", "label": "The Bonefields", "style": "hatch", "box": [0.74, 0.05, 0.96, 0.30], "blurb": "white banners on a grey plain"},
]
# forward gates: region -> list of {char, to, label}
FORWARD = {
 "whisperwood": [("1", "mistfen", "Mistfen"), ("2", "jadehill", "Jadehill Terraces"), ("3", "blighted_wood", "The Blighted Deep Wood")],
 "bonefields": [("1", "emberwaste", "The Emberwaste")],
 "mistfen": [("1", "sunken_mere", "The Sunken Mere")],
 "jadehill": [("1", "stormcliffs", "The Stormcliffs")],
 "stormcliffs": [("1", "frostmere", "Frostmere")],
 "emberwaste": [("1", "sandglass", "The Sandglass Dunes")],
}

# main quest: a road through the Lands to transcendence. Goals are checked by the game (item/kill/realm/talk).
CHAPTERS = [
 {"id": "land_wood", "name": "The Wood Beyond the Valley", "who": "Elder Mo", "brief": "Whisperwood stands at the valley's edge. Warden Isolde keeps its paths. Bring her proof you can walk where the wood watches: glowcap, heartwood, and the elder treant's head.",
  "goals": [{"talk": "Warden Isolde", "text": "Speak with Warden Isolde in Whisperwood"}, {"item": "glowcap", "count": 3, "text": "Gather 3 glowcap"}, {"item": "heartwood", "count": 3, "text": "Gather 3 heartwood"}, {"kill": "elder_treant", "text": "Fell the Elder Treant of Whisperwood"}],
  "reward": {"gold": 500, "qi": 800, "items": {"wildwood_tonic": 2}, "insight": 4, "title": "Wood-Walker"}},
 {"id": "land_fen", "name": "What the Fen Keeps", "who": "Warden Isolde", "brief": "Past the wood, the mist. Ferryman Oss will take news for passage. The Hag of the Fen keeps a string of drowned pearls. Break her hold on the water.",
  "goals": [{"talk": "Ferryman Oss", "text": "Speak with Ferryman Oss in Mistfen"}, {"item": "bog_lotus", "count": 3, "text": "Gather 3 bog lotus"}, {"kill": "hag_of_the_fen", "text": "Defeat the Hag of the Fen"}],
  "reward": {"gold": 700, "qi": 1200, "items": {"fen_antivenom": 2}, "insight": 4, "title": "Fen-Crosser"}},
 {"id": "land_bones", "name": "The Banners Still Point", "who": "Elder Mo", "brief": "Two armies met on the Bonefields and neither went home. Gravewalker Hesk has buried what he could. Bring the standard down and quiet the field.",
  "goals": [{"talk": "Gravewalker Hesk", "text": "Speak with Gravewalker Hesk in the Bonefields"}, {"item": "battle_iron", "count": 3, "text": "Gather 3 battle iron"}, {"kill": "general_of_the_fallen", "text": "Defeat the General of the Fallen"}],
  "reward": {"gold": 900, "qi": 1500, "items": {"warsteel": 1}, "insight": 5, "title": "Gravewalker's Friend"}},
 {"id": "land_jade", "name": "Terraces in the Cloud", "who": "Elder Mo", "brief": "The Jadehill terraces are tended by people no one meets. The Jade Hermit keeps the gate. Earn the right to climb: cloud rice, sage leaf, and the hermit's answer.",
  "goals": [{"realm": 3, "text": "Reach Core Formation"}, {"item": "cloud_rice", "count": 3, "text": "Gather 3 cloud rice"}, {"kill": "jade_hermit", "text": "Answer the Jade Hermit"}],
  "reward": {"gold": 1200, "qi": 2500, "items": {"terrace_elixir": 2}, "insight": 6, "title": "Terrace-Walker"}},
 {"id": "land_mere", "name": "The Drowned King's Mere", "who": "Diver Maru", "brief": "The Mere swallowed a kingdom. Diver Maru works its rooftops. Reach the pearl beds, and settle the matriarch who guards them.",
  "goals": [{"item": "pearl_oyster", "count": 2, "text": "Gather 2 mere pearls"}, {"kill": "mere_matriarch", "text": "Defeat the Mere Matriarch"}],
  "reward": {"gold": 1500, "qi": 3000, "items": {"mere_mail": 1}, "insight": 6, "title": "Pearl-Diver"}},
 {"id": "land_storm", "name": "A Language of Thunder", "who": "Stormsmith Brae", "brief": "The Stormcliffs speak in lightning. Stormsmith Brae will teach the first words if you can stand the weather. Take the Storm Lord's heart.",
  "goals": [{"realm": 4, "text": "Reach Nascent Soul"}, {"item": "thunder_iron", "count": 3, "text": "Gather 3 thunder iron"}, {"kill": "storm_lord", "text": "Defeat the Storm Lord"}],
  "reward": {"gold": 2000, "qi": 4000, "items": {"storm_edge": 1}, "insight": 7, "title": "Storm-Speaker"}},
 {"id": "land_ember", "name": "The Sleeping Mountain", "who": "Cinder-Priest Vahl", "brief": "The caldera is waiting. Vahl tends the shrine at its lip. Bring cinderstone and a steady hand, and the tyrant's fire will let you pass.",
  "goals": [{"item": "firestone", "count": 3, "text": "Gather 3 cinderstone"}, {"kill": "caldera_tyrant", "text": "Defeat the Caldera Tyrant"}],
  "reward": {"gold": 2600, "qi": 5000, "items": {"cinder_plate": 1}, "insight": 7, "title": "Ember-Walker"}},
 {"id": "land_frost", "name": "The Singing Ice", "who": "Ice-Fisher Torvald", "brief": "The lake sings at night. Torvald listens. The Glacier Empress is what he listens for. Quiet her.",
  "goals": [{"realm": 5, "text": "Reach Soul Transformation"}, {"item": "frost_lotus", "count": 3, "text": "Gather 3 frost lotus"}, {"kill": "glacier_empress", "text": "Defeat the Glacier Empress"}],
  "reward": {"gold": 3200, "qi": 7000, "items": {"frost_draught": 2}, "insight": 8, "title": "Frost-Walker"}},
 {"id": "land_sand", "name": "Hours in the Dunes", "who": "Hourkeeper Isra", "brief": "The Sandglass Dunes keep time their own way. Isra counts the grains. Gather what the sand gives up and stop the pharaoh's clock.",
  "goals": [{"item": "hourglass_sand", "count": 3, "text": "Gather 3 hourglass sand"}, {"kill": "pharaoh_of_hours", "text": "Defeat the Pharaoh of Hours"}],
  "reward": {"gold": 4000, "qi": 9000, "items": {"sand_lens": 1}, "insight": 8, "title": "Time-Walker"}},
 {"id": "land_blight", "name": "The Root King", "who": "Last Warden Ysolde", "brief": "The Blighted Deep Wood grew around what the swarm left behind. Ysolde has held its edge alone. Go in, take what the roots hold, and end the Root King.",
  "goals": [{"realm": 7, "text": "Reach Body Integration"}, {"item": "nanite_sap", "count": 3, "text": "Gather 3 nanite sap"}, {"kill": "root_king", "text": "Defeat the Root King"}],
  "reward": {"gold": 7000, "qi": 15000, "items": {"blight_graft": 1}, "insight": 12, "title": "Root-Breaker"}},
 {"id": "ascend_road", "name": "The Road Upward", "who": "Elder Mo", "brief": "The Lands are behind you. What is left is the road itself: break through the Tribulation, take your place among the immortals, and become something that can keep a world. When you do, a world of your own will open to you in the online realm.",
  "goals": [{"realm": 9, "text": "Break through the Tribulation"}, {"realm": 10, "text": "Reach Immortal Ascension"}],
  "reward": {"insight": 25, "title": "Worldkeeper"}},
]

def main():
    root = sys.argv[1] if len(sys.argv) > 1 else "."
    p = lambda *a: os.path.join(root, *a)
    items = load(p("data/items.json")); backup(p("data/items.json"))
    crafting = load(p("data/crafting.json")); backup(p("data/crafting.json"))
    enemies = load(p("data/enemies.json")); backup(p("data/enemies.json"))
    fr = load(p("data/frontier.json")); backup(p("data/frontier.json"))
    mq = load(p("data/main_quest.json")); backup(p("data/main_quest.json"))
    new_mats = 0
    for mid, (name, value, el, traits, desc) in M.items():
        if mid not in items or items[mid].get("land"):
            items[mid] = {"name": name, "type": "material", "value": value, "element": el, "desc": desc, "land": True}
            new_mats += 1
        crafting["materials"].setdefault(mid, {"element": el, "traits": traits})
    save(p("data/items.json"), items)
    forms = crafting.setdefault("formulas", []); have = {f["id"] for f in forms}; prods = crafting.setdefault("products", {})
    for pid, (name, value, el, traits, desc, needs, skill, diff, price, sold, hint) in P.items():
        prods[pid] = {"name": name, "value": value, "element": el, "traits": traits, "desc": desc}
        if pid not in have:
            forms.append({"id": pid, "needs": needs, "makes": pid, "n": 1, "skill": skill, "difficulty": diff, "price": price, "sold": sold, "hint": hint})
    save(p("data/crafting.json"), crafting)
    enemies.update(build_foes()); save(p("data/enemies.json"), enemies)
    # regions, with their forward gates
    gates = fr.setdefault("extra_gates", {})
    for rid, reg in R.items():
        fr["regions"][rid] = reg
    for rid, lst in FORWARD.items():
        gates[rid] = [{"char": c, "to": to, "arrive": "<", "label": lbl, "style": "hatch"} for c, to, lbl in lst]
    # keep the old Foundry gate (a dict) working alongside lists
    have_sites = {s["char"] for s in fr.get("sites", [])}
    for s in SITES:
        if s["char"] not in have_sites: fr["sites"].append(s)
    save(p("data/frontier.json"), fr)
    ids = {c["id"] for c in mq["chapters"]}
    for c in CHAPTERS:
        if c["id"] not in ids: mq["chapters"].append(c)
    save(p("data/main_quest.json"), mq)
    print("lands: %d regions, %d materials, %d products, %d foes, %d chapters" % (len(R), len(M), len(P), len(FOES), len(CHAPTERS)))
main()
