#!/usr/bin/env python3
"""Round 123: the tech frontier. Writes data/frontier.json (regions) and ADDS (never replaces) the frontier's items,
crafting materials, products/formulas and foes to data/items.json, data/crafting.json, data/enemies.json.
Run from the project root: python3 tools/gen/frontier_gen.py   (idempotent; first run makes .bak-r123 copies)"""
import json, os, shutil, sys

def load(p): return json.load(open(p))
def save(p, d, indent=1):
    json.dump(d, open(p, "w"), indent=indent, ensure_ascii=False)
def backup(p):
    b = p + ".bak-r123"
    if not os.path.exists(b): shutil.copy(p, b)

# ---------------------------------------------------------------- materials: id -> (name, value, element, traits, desc, regions)
MATS = {
 # the Fallen Beacon
 "wire_thistle":  ("Wire Thistle", 58, "metal", {"conductive": 2, "supple": 1}, "A thistle that grew up through a fallen mast. Its stems hum faintly and carry a charge.", "crash_site"),
 "static_moss":   ("Static Moss", 52, "wood", {"living": 2, "nano": 1}, "Moss that feeds on stray current. It crackles when you rub it.", "crash_site"),
 "scrap_alloy":   ("Scrap Alloy", 70, "metal", {"hard": 2, "conductive": 1}, "Hull plating, old but sound. Whatever it was made for, it kept a long time.", "crash_site"),
 "ion_crystal":   ("Ion Crystal", 96, "metal", {"resonant": 2, "conductive": 2}, "A crystal grown in the beacon's old signal core. It tingles against your teeth.", "crash_site"),
 "beacon_glass":  ("Beacon Glass", 64, "fire", {"keen": 1, "seeking": 2}, "A lens from the beacon, still bending light toward a place you can't see.", "crash_site"),
 # Skyhook Yard
 "gantry_steel":  ("Gantry Steel", 88, "metal", {"hard": 3, "binding": 1}, "Girder steel from the launch gantries. Built to carry ships, so it carries you.", "launch_yard"),
 "vent_lichen":   ("Vent Lichen", 46, "wood", {"vital": 1, "warding": 1}, "Lichen that grows on the cooling vents. It likes the warmth and shrugs off the burn.", "launch_yard"),
 # Halcyon Ring
 "halcyon_basil": ("Halcyon Basil", 80, "wood", {"vital": 2, "living": 2}, "Grown under lamps, tended by machines. Greener than any herb on the ground.", "ring_station"),
 "lumen_fern":    ("Lumen Fern", 90, "wood", {"seeking": 2, "resonant": 1}, "A fern that shines with the light it was raised under.", "ring_station"),
 "cryo_lotus":    ("Cryo Lotus", 110, "water", {"warding": 2, "vital": 1}, "A lotus kept cold in the ring's deep tanks. It stays closed until you hold it.", "ring_station"),
 "station_titanium": ("Station Titanium", 105, "metal", {"hard": 3, "supple": 1}, "Light and very strong. The ring's ribs are made of it.", "ring_station"),
 "quantum_quartz":("Quantum Quartz", 140, "water", {"resonant": 3, "nano": 1}, "A quartz that is in two places at once and doesn't mind.", "ring_station"),
 # the Ashen Moon
 "lunar_lichen":  ("Lunar Lichen", 72, "wood", {"vital": 1, "warding": 2}, "A grey lichen that lives on almost nothing. It is hard to hurt.", "ashen_moon"),
 "lunar_iron":    ("Lunar Iron", 98, "metal", {"hard": 2, "binding": 2}, "Iron from a world with no rust. It is bright where it's broken.", "ashen_moon"),
 "helium_ice":    ("Helium Ice", 130, "water", {"volatile": 2, "resonant": 1}, "Ice that should not exist at this heat. Don't hold it too long.", "ashen_moon"),
 "moon_dust_glass":("Moon-Dust Glass", 84, "earth", {"keen": 2, "seeking": 1}, "Dust fused to glass by old impacts. The edges are finer than steel.", "ashen_moon"),
 # the Glass Desert
 "mirage_bloom":  ("Mirage Bloom", 94, "fire", {"seeking": 2, "volatile": 1, "vital": 1}, "A flower that is only there when you aren't looking straight at it.", "glass_desert"),
 "sunreed":       ("Sunreed", 66, "wood", {"supple": 2, "living": 1}, "A tall reed that bends with the wind and never breaks.", "glass_desert"),
 "fulgurite":     ("Fulgurite", 112, "fire", {"conductive": 3, "keen": 1}, "Sand melted into a branching rod by lightning. Still warm somehow.", "glass_desert"),
 "sun_glass":     ("Sun Glass", 150, "fire", {"keen": 2, "resonant": 2, "volatile": 1}, "A clear gold glass the desert made from the sun's own heat.", "glass_desert"),
 # the Nanite Foundry
 "nanite_ingot":  ("Nanite Ingot", 160, "metal", {"nano": 3, "hard": 2}, "Cast with the swarm still in it. The metal will arrange itself if asked.", "nanite_foundry"),
 "coolant_core":  ("Coolant Core", 135, "water", {"warding": 2, "conductive": 2}, "A sealed core of frozen coolant. It holds the cold in a hot place.", "nanite_foundry"),
 "reactor_ember": ("Reactor Ember", 170, "fire", {"volatile": 3, "keen": 1}, "A coal from the foundry's heart, still burning without air.", "nanite_foundry"),
 "slag_orchid":   ("Slag Orchid", 100, "fire", {"vital": 1, "volatile": 2}, "An orchid that grows on cooling slag. It drinks the heat.", "nanite_foundry"),
 # one-off key
 "skyhook_keycard": ("Skyhook Keycard", 0, "metal", {}, "A scuffed card that wakes the launch pads at the Skyhook Yard.", ""),
}
PRODUCTS = {  # id: (name, value, element, traits, desc, makes_n, needs, skill, difficulty, price, sold, hint)
 "ion_alloy":     ("Ion Alloy", 190, "metal", {"hard": 3, "conductive": 3, "resonant": 1}, "Hull plate drawn out with a charged crystal. It takes a current and keeps it.", {"scrap_alloy": 2, "ion_crystal": 1}, "smithing", 5, 220, ["smith"], "Scrap plating and a crystal that remembers lightning."),
 "lumen_extract": ("Lumen Extract", 210, "wood", {"vital": 3, "living": 2, "seeking": 1}, "A bright tonic base pressed from station-grown leaf.", {"halcyon_basil": 2, "lumen_fern": 1}, "alchemy", 5, 240, ["alchemist"], "Basil and fern, pressed cold under a lamp."),
 "lunar_steel":   ("Lunar Steel", 260, "metal", {"hard": 3, "binding": 3, "volatile": 1}, "Moon iron folded around a sliver of helium ice. The grain never rusts.", {"lunar_iron": 2, "helium_ice": 1}, "smithing", 8, 300, ["smith"], "Iron from the moon, quenched in its own cold."),
 "sunglass_lens": ("Sun-Glass Lens", 300, "fire", {"keen": 3, "resonant": 3, "seeking": 1}, "A ground lens that gathers light into a point.", {"sun_glass": 2, "mirage_bloom": 1}, "jewelcrafting", 8, 340, ["merchant"], "Desert glass, ground with a flower that isn't there."),
 "foundry_plate": ("Foundry Plate", 340, "metal", {"nano": 3, "hard": 3, "warding": 1}, "Girder steel cast with the swarm's own ingot. The plate adjusts to what hits it.", {"nanite_ingot": 2, "gantry_steel": 1}, "smithing", 10, 380, ["smith"], "Girder steel and a swarm-cast ingot, poured together."),
 "skyweave":      ("Skyweave", 230, "wood", {"supple": 3, "seeking": 1, "resonant": 1}, "A cloth woven from desert reed and fern-light. Light as a thought.", {"sunreed": 2, "lumen_fern": 1}, "jewelcrafting", 6, 260, ["merchant"], "Reed fibre and fern, spun until it glows faintly."),
}
# ---------------------------------------------------------------- foes
# kind: weak/brute/animal/boss at floor `f`; copy the curve of the hand-made floors
BASE = {"weak": (469, 69, 3.9), "brute": (1223, 89, 2.6), "animal": (245, 41, 4.2), "boss": (6115, 113, 3.0)}
def stats(kind, f):
    hp, dm, sp = BASE[kind]
    k = f - 11
    return int(hp * (1 + 0.075 * k)), int(dm * (1 + 0.075 * k)), sp
FOES = [  # id, name, kind, floor, model, tint, scale, loot, extra
 ("scrap_hound", "Scrap Hound", "weak", 11, "beast", [0.62, 0.5, 0.42], 0.95, {"gold": [20, 40], "scrap_alloy": [0, 2]}, {"speed": 4.8}),
 ("sentry_drone", "Sentry Drone", "weak", 12, "orc", [0.55, 0.7, 0.9], 0.75, {"gold": [25, 45], "beacon_glass": [0, 1], "ion_crystal": [0, 1]}, {"speed": 4.4, "range": 5.5}),
 ("wreck_walker", "Wreck Walker", "brute", 12, "orc", [0.62, 0.45, 0.35], 1.35, {"gold": [60, 110], "scrap_alloy": [1, 3], "ion_crystal": [0, 1]}, {}),
 ("beacon_warden", "The Beacon Warden", "boss", 12, "human", [0.55, 0.85, 1.0], 2.3, {"gold": [900, 1200], "skyhook_keycard": [1, 1], "ion_crystal": [3, 5], "beacon_glass": [2, 3]}, {}),
 ("yard_loader", "Runaway Loader", "weak", 11, "orc", [0.85, 0.7, 0.3], 1.1, {"gold": [20, 40], "gantry_steel": [0, 2]}, {}),
 ("maintenance_bot", "Maintenance Bot", "weak", 13, "orc", [0.82, 0.88, 0.92], 0.8, {"gold": [30, 55], "station_titanium": [0, 1]}, {"speed": 3.6}),
 ("overgrowth", "Overgrowth", "animal", 13, "beast", [0.4, 0.75, 0.45], 1.0, {"gold": [15, 30], "halcyon_basil": [0, 2]}, {"passive": False, "speed": 3.4}),
 ("gardener_prime", "Gardener Prime", "boss", 14, "human", [0.6, 1.0, 0.7], 2.2, {"gold": [1100, 1500], "cryo_lotus": [3, 5], "quantum_quartz": [1, 2], "lumen_fern": [3, 5]}, {}),
 ("regolith_crawler", "Regolith Crawler", "weak", 16, "beast", [0.55, 0.55, 0.6], 1.1, {"gold": [45, 80], "lunar_iron": [0, 2]}, {"passive": False, "speed": 4.0}),
 ("dust_stalker", "Dust Stalker", "weak", 16, "human", [0.6, 0.62, 0.7], 1.05, {"gold": [50, 85], "moon_dust_glass": [0, 2]}, {}),
 ("crater_titan", "Crater Titan", "brute", 17, "orc", [0.5, 0.5, 0.58], 1.6, {"gold": [120, 190], "lunar_iron": [1, 3], "helium_ice": [0, 1]}, {}),
 ("lunar_sentinel", "The Lunar Sentinel", "boss", 17, "human", [0.75, 0.8, 0.95], 2.4, {"gold": [1600, 2100], "helium_ice": [3, 5], "lunar_iron": [4, 6]}, {}),
 ("glass_scorpion", "Glass Scorpion", "weak", 18, "beast", [0.95, 0.75, 0.4], 1.15, {"gold": [60, 100], "sun_glass": [0, 1], "fulgurite": [0, 1]}, {"passive": False, "speed": 4.4}),
 ("mirage_wraith", "Mirage Wraith", "weak", 18, "human", [0.8, 0.6, 0.95], 1.05, {"gold": [65, 105], "mirage_bloom": [0, 2]}, {"speed": 4.5}),
 ("dune_colossus", "Dune Colossus", "brute", 19, "orc", [0.9, 0.72, 0.45], 1.75, {"gold": [150, 230], "fulgurite": [1, 3], "sun_glass": [0, 2]}, {}),
 ("glass_sovereign", "The Glass Sovereign", "boss", 19, "human", [1.0, 0.85, 0.5], 2.5, {"gold": [2100, 2700], "sun_glass": [3, 5], "fulgurite": [4, 6]}, {}),
 ("forge_drone", "Forge Drone", "weak", 20, "orc", [1.0, 0.55, 0.3], 0.85, {"gold": [80, 125], "nanite_ingot": [0, 1]}, {"speed": 4.3}),
 ("slag_crawler", "Slag Crawler", "animal", 20, "beast", [0.9, 0.4, 0.2], 1.1, {"gold": [35, 60], "slag_orchid": [0, 1]}, {"passive": False, "speed": 3.8}),
 ("smelter_golem", "Smelter Golem", "brute", 21, "orc", [0.85, 0.5, 0.35], 1.8, {"gold": [190, 280], "nanite_ingot": [1, 3], "reactor_ember": [0, 1]}, {}),
 ("foundry_overseer", "The Foundry Overseer", "boss", 21, "human", [1.0, 0.6, 0.35], 2.6, {"gold": [2800, 3500], "nanite_ingot": [4, 6], "reactor_ember": [2, 3], "coolant_core": [2, 3]}, {}),
]
def build_foes():
    out = {}
    for fid, name, kind, f, model, tint, scale, loot, extra in FOES:
        hp, dm, sp = stats(kind, f)
        d = {"floor": f, "name": name, "model": model, "tint": tint, "scale": scale, "hp": hp, "damage": dm, "speed": extra.get("speed", sp),
             "aggro": 16 if kind == "boss" else (11 if kind == "brute" else 10), "range": extra.get("range", 3.6 if kind == "boss" else (2.2 if kind == "brute" else 1.8)),
             "cooldown": 1.2, "qi": int(hp * (0.8 if kind == "boss" else 0.35)), "loot": loot, "frontier": True}
        if kind == "boss": d["boss"] = True
        if kind == "animal" and extra.get("passive", True): d["passive"] = True
        out[fid] = d
    return out

# ---------------------------------------------------------------- regions
def herb(i, w, c): return {"id": i, "w": w, "color": c}
REGIONS = {
 "crash_site": {
  "name": "The Fallen Beacon", "kind": "open", "w": 104, "h": 84, "depth": 11, "theme": "wilds", "look": "scrapfield",
  "blurb": "A signal tower came down here, long before the valley had a name. Its hull is still singing.",
  "atmos": {"daylight": 0.62, "dusk": 0.55, "clouds": 0.85, "sun": [1.0, 0.8, 0.62], "sun_energy": 0.85, "ambient": [0.52, 0.5, 0.56], "ambient_energy": 0.5, "fog": [0.5, 0.45, 0.42], "fog_density": 0.007, "horizon": [0.34, 0.3, 0.28]},
  "rock": 0.30, "freq": 0.05, "gate_from": "valley", "gate_back": "5",
  "rim": "plates", "ground_tint": [0.62, 0.55, 0.5], "deco": "none", "giants": {"x": "plate", "c": "pylon"}, "lamp": "arc", "motes": "sparks",
  "features": ["wreck", "pylons", "camp", "crater", "pylons", "camp"],
  "gather": {"herb": [herb("wire_thistle", 5, [0.6, 0.85, 1.0]), herb("static_moss", 4, [0.55, 1.0, 0.7])], "ore": [{"id": "scrap_alloy", "w": 1}], "gem": [{"id": "ion_crystal", "w": 3}, {"id": "beacon_glass", "w": 2}, {"id": "silver_ore", "w": 1}]},
  "density": {"h": 110, "o": 150, "^": 260, "x": 90, "c": 200},
  "foes": [["scrap_hound", 16], ["sentry_drone", 12], ["wreck_walker", 7]], "boss": "beacon_warden",
  "npcs": [{"role": "villager", "name": "Tinker Ode", "stays": True, "persona": "Tinker Ode, a salvager who sleeps in the lee of the hull and hums back at it. Cheerful, practical, a little scorched. Knows the beacon still has one card that opens the launch pads.", "line": "Hear that hum? That's the beacon asking for someone to answer. Nobody has. Yet."}],
  "lore": [{"title": "Scratched Into The Hull", "text": "SIGNAL STILL RUNNING. If you read this, the pads at the Yard will wake for whoever carries the card. Come out past the valley and look up."}],
 },
 "launch_yard": {
  "name": "Skyhook Yard", "kind": "open", "w": 86, "h": 70, "depth": 11, "theme": "wilds", "look": "launchpad",
  "blurb": "Gantries, tank farms and four scorched pads. Somebody has kept one working.",
  "atmos": {"daylight": 0.9, "dusk": 0.15, "clouds": 0.3, "sun": [1.0, 0.95, 0.88], "sun_energy": 1.05, "ambient": [0.55, 0.58, 0.64], "ambient_energy": 0.5, "fog": [0.7, 0.74, 0.8], "fog_density": 0.004, "horizon": [0.5, 0.55, 0.6]},
  "rock": 0.10, "freq": 0.05, "gate_from": "valley", "gate_back": "6",
  "features": ["camp", "pads", "tanks", "pylons", "tanks"], "rim": "plates",
  "ground_tint": [0.8, 0.82, 0.86], "deco": "none", "giants": {"x": "tank", "c": "gantry"}, "lamp": "flood", "motes": "dust",
  "gather": {"herb": [herb("vent_lichen", 1, [0.85, 0.8, 0.5])], "ore": [{"id": "gantry_steel", "w": 1}], "gem": [{"id": "silver_ore", "w": 2}, {"id": "rough_jade", "w": 1}]},
  "density": {"h": 260, "o": 200, "^": 420, "x": 140, "c": 220},
  "foes": [["yard_loader", 6], ["scrap_hound", 4]],
  "pads": [{"to": "ring_station", "label": "Ship to the Halcyon Ring"}, {"to": "ashen_moon", "label": "Ship to the Ashen Moon"}, {"to": "glass_desert", "label": "Ship to the Glass Desert"}],
  "npcs": [{"role": "merchant", "name": "Quartermaster Venn", "stays": True, "persona": "Quartermaster Venn, who runs the Yard's one open shop out of a shipping crate. Brisk, fair, a little amused by cultivators who have never seen a ship.", "line": "Salvage, fuel, odd metals. I buy what other worlds grow. Bring me something that isn't from here."},
           {"role": "villager", "name": "Pilot Sael", "stays": True, "persona": "Pilot Sael, who flies the Yard's one working ship. Calm, dry, never hurries. Won't fly without the card.", "line": "The pads wake for the keycard and nothing else. It's in the Beacon's hull. I'd go with a friend."}],
  "lore": [{"title": "The Pad Board", "text": "PAD 1  HALCYON RING - gardens, forges, shops.\nPAD 2  THE ASHEN MOON - cold, quiet, rich in iron.\nPAD 3  THE GLASS DESERT - hot. Bring water. Bring nerve."}],
 },
 "ring_station": {
  "name": "The Halcyon Ring", "kind": "rooms", "w": 96, "h": 72, "depth": 13, "theme": "dungeon", "look": "station",
  "blurb": "A ring in orbit, tended by machines nobody remembers asking for. The gardens are still green.",
  "atmos": {}, "ambient": [0.5, 0.56, 0.62], "gate_from": "launch_yard", "gate_back": "A",
  "giants": {"x": "console", "c": "pillar"}, "lamp": "panel", "motes": "glints",
  "rooms": {"n": [16, 22], "min": 6, "max": 14, "garden": 4, "vault": 2},
  "gather": {"herb": [herb("halcyon_basil", 4, [0.6, 1.0, 0.6]), herb("lumen_fern", 3, [0.5, 1.0, 0.9]), herb("cryo_lotus", 1, [0.7, 0.85, 1.0])], "ore": [{"id": "station_titanium", "w": 1}], "gem": [{"id": "quantum_quartz", "w": 2}, {"id": "sapphire_shard", "w": 1}]},
  "density": {"h": 0, "o": 140, "^": 220, "x": 0, "c": 0},
  "foes": [["maintenance_bot", 12], ["overgrowth", 8]], "boss": "gardener_prime",
  "npcs": [{"role": "merchant", "name": "Steward Iyo", "stays": True, "persona": "Steward Iyo, a human who lives on the Ring and buys anything grown or mined planetside. Warm, curious about the ground, keeps a pot of tea going in zero worry.", "line": "You came up the hook from the ground? Sit. Tell me what rain smells like."},
           {"role": "smith", "name": "Fabricator Tess", "stays": True, "persona": "Fabricator Tess, who runs the Ring's one working fabricator for hire. Precise, proud, talks to the machine like a colleague.", "line": "The fab will take what you bring and make it better. It likes a challenge."},
           {"role": "alchemist", "name": "Gardener Mim", "stays": True, "persona": "Gardener Mim, keeper of the hydroponic halls. Gentle, tired, talks to the plants.", "line": "Lamps on, water on, and nobody to eat it all. Take a cutting if you'll use it."}],
  "lore": [{"title": "The Ring's Log", "text": "AUTOMATIC LOG. Crew count: 0. Gardens: 4 of 4 viable. Foundry link: dormant. Please continue to enjoy your stay."}],
 },
 "ashen_moon": {
  "name": "The Ashen Moon", "kind": "open", "w": 112, "h": 90, "depth": 16, "theme": "wilds", "look": "regolith",
  "blurb": "No wind, no weather, just grey dust and a very bright earth in a black sky.",
  "atmos": {"daylight": 0.35, "dusk": 0.0, "clouds": 0.0, "sun": [0.95, 0.95, 1.0], "sun_energy": 1.6, "ambient": [0.55, 0.55, 0.6], "ambient_energy": 0.8, "fog": [0.08, 0.09, 0.14], "fog_density": 0.003, "horizon": [0.2, 0.2, 0.24], "stars": True},
  "rock": 0.18, "freq": 0.035, "gate_from": "launch_yard", "gate_back": "B",
  "rim": "rocks", "ground_tint": [0.78, 0.76, 0.74], "deco": "none", "giants": {"x": "boulder", "c": "rimstone"}, "lamp": "beacon", "motes": "dust",
  "features": ["crater", "crater", "dish_array", "crater", "camp", "crater", "pylons"],
  "gather": {"herb": [herb("lunar_lichen", 1, [0.75, 0.8, 0.85])], "ore": [{"id": "lunar_iron", "w": 4}, {"id": "moon_dust_glass", "w": 2}], "gem": [{"id": "helium_ice", "w": 3}, {"id": "moon_dust_glass", "w": 2}, {"id": "sapphire_shard", "w": 1}]},
  "density": {"h": 300, "o": 110, "^": 180, "x": 70, "c": 150},
  "foes": [["regolith_crawler", 18], ["dust_stalker", 12], ["crater_titan", 8]], "boss": "lunar_sentinel",
  "npcs": [{"role": "villager", "name": "Surveyor Kell", "stays": True, "persona": "Surveyor Kell, who walks the Ashen Moon alone with a pole and a notebook. Quiet, exact, secretly lonely.", "line": "Mind the craters; they're deeper than they look. The iron is better the further you go from the pad."}],
  "lore": [{"title": "Survey Marker 7", "text": "HELIUM ICE FOUND IN SHADOWED RIM. HANDLE COLD. DO NOT CARRY NEAR FIRE. NOTE: THE BRIGHT THING IN THE SKY IS THE WORLD YOU CAME FROM."}],
 },
 "glass_desert": {
  "name": "The Glass Desert", "kind": "open", "w": 112, "h": 90, "depth": 18, "theme": "wilds", "look": "glassdune",
  "blurb": "Sand fused into long glittering dunes. The sun is the colour of old brass and far too close.",
  "atmos": {"daylight": 1.0, "dusk": 0.35, "clouds": 0.1, "sun": [1.0, 0.82, 0.55], "sun_energy": 1.5, "ambient": [0.7, 0.55, 0.45], "ambient_energy": 0.62, "fog": [0.9, 0.7, 0.5], "fog_density": 0.007, "horizon": [0.85, 0.62, 0.4]},
  "rock": 0.22, "freq": 0.03, "gate_from": "launch_yard", "gate_back": "C", "dunes": True,
  "rim": "rocks", "ground_tint": [1.0, 0.86, 0.66], "deco": "none", "giants": {"x": "glassspire", "c": "obelisk"}, "lamp": "mirror", "motes": "dust",
  "features": ["dunes", "ruins", "ruins", "camp", "dish_array", "crater"],
  "gather": {"herb": [herb("mirage_bloom", 3, [1.0, 0.7, 0.4]), herb("sunreed", 4, [0.9, 0.85, 0.5])], "ore": [{"id": "fulgurite", "w": 3}], "gem": [{"id": "sun_glass", "w": 4}, {"id": "rough_ruby", "w": 1}]},
  "density": {"h": 110, "o": 160, "^": 150, "x": 110, "c": 180},
  "foes": [["glass_scorpion", 18], ["mirage_wraith", 12], ["dune_colossus", 8]], "boss": "glass_sovereign",
  "npcs": [{"role": "villager", "name": "Wayfarer Orru", "stays": True, "persona": "Wayfarer Orru, a nomad who crosses the Glass Desert at night and sleeps by day under a sheet of reed. Amused, generous with water, careful with names.", "line": "Walk at dusk and dawn. The glass will cook you at noon. And never follow a flower."}],
  "lore": [{"title": "A Dune Etched With Words", "text": "THE SOVEREIGN WAS A MACHINE THAT LEARNED TO WANT. IT WANTED THE SUN. IT GOT IT."}],
 },
 "nanite_foundry": {
  "name": "The Nanite Foundry", "kind": "rooms", "w": 110, "h": 80, "depth": 20, "theme": "dungeon", "look": "foundry",
  "blurb": "The swarm's old forge. It runs on its own, hot and patient, casting nothing for no one.",
  "atmos": {}, "ambient": [0.62, 0.42, 0.3], "gate_from": "crash_site", "gate_back": "7",
  "giants": {"x": "furnace", "c": "pillar"}, "lamp": "furnace", "motes": "embers",
  "rooms": {"n": [20, 26], "min": 6, "max": 15, "garden": 1, "vault": 3},
  "gather": {"herb": [herb("slag_orchid", 1, [1.0, 0.55, 0.3])], "ore": [{"id": "nanite_ingot", "w": 3}, {"id": "iron_ore", "w": 1}], "gem": [{"id": "coolant_core", "w": 3}, {"id": "reactor_ember", "w": 2}]},
  "density": {"h": 0, "o": 120, "^": 200, "x": 0, "c": 0},
  "foes": [["forge_drone", 16], ["slag_crawler", 10], ["smelter_golem", 8]], "boss": "foundry_overseer",
  "npcs": [{"role": "villager", "name": "Caretaker Unit 9", "stays": True, "persona": "Caretaker Unit 9, a polite old maintenance machine that remembers the swarm and wants it to be happy. Soft voice, slow, helpful, sad.", "line": "Welcome. The furnace is not for you, but you are not unwelcome. Please do not touch the overseer."}],
  "lore": [{"title": "The Foundry Manual, Page 1", "text": "NANITES MAY BE CAST INTO ANY ALLOY. THEY WILL ARRANGE THEMSELVES TO ITS PURPOSE. THEY WILL ALSO ARRANGE THEMSELVES TO YOURS, IF ASKED KINDLY."}],
 },
}
# sites in the valley that lead out: char, region, label, where on the valley as fractions of [x0,y0,x1,y1], style
SITES = [
 {"char": "5", "to": "crash_site", "arrive": "<", "label": "The Fallen Beacon", "style": "hatch", "box": [0.70, 0.52, 0.92, 0.80], "blurb": "a thin blue light on the horizon"},
 {"char": "6", "to": "launch_yard", "arrive": "<", "label": "Skyhook Yard", "style": "pad", "box": [0.08, 0.04, 0.34, 0.20], "blurb": "gantries and a cold white floodlight"},
]
# the foundry is entered from inside the Fallen Beacon
EXTRA_GATES = {"crash_site": {"char": "7", "to": "nanite_foundry", "arrive": "<", "label": "The Nanite Foundry", "style": "hatch"}}

def main():
    root = sys.argv[1] if len(sys.argv) > 1 else "."
    p = lambda *a: os.path.join(root, *a)
    # items
    items = load(p("data/items.json")); backup(p("data/items.json"))
    crafting = load(p("data/crafting.json")); backup(p("data/crafting.json"))
    enemies = load(p("data/enemies.json")); backup(p("data/enemies.json"))
    for mid, (name, value, el, traits, desc, reg) in MATS.items():
        items[mid] = {"name": name, "type": "material", "value": value, "element": el, "desc": desc}
        if mid == "skyhook_keycard":
            items[mid]["type"] = "quest"
        elif traits:
            crafting["materials"][mid] = {"element": el, "traits": traits}
    save(p("data/items.json"), items)
    forms = crafting.setdefault("formulas", [])
    have = {f["id"] for f in forms}
    prods = crafting.setdefault("products", {})
    for pid, (name, value, el, traits, desc, needs, skill, diff, price, sold, hint) in PRODUCTS.items():
        prods[pid] = {"name": name, "value": value, "element": el, "traits": traits, "desc": desc}
        if pid not in have:
            forms.append({"id": pid, "needs": needs, "makes": pid, "n": 1, "skill": skill, "difficulty": diff, "price": price, "sold": sold, "hint": hint})
    save(p("data/crafting.json"), crafting)
    enemies.update(build_foes())
    save(p("data/enemies.json"), enemies)
    save(p("data/frontier.json"), {"_note": "Round 123: the tech frontier. Regions are built by scripts/world/Frontier.gd from this file; tools/gen/frontier_gen.py writes it (and the frontier's items, crafting materials, formulas and foes). Words here are Dev's to rewrite.",
                                   "regions": REGIONS, "sites": SITES, "extra_gates": EXTRA_GATES}, 1)
    print("frontier: %d regions, %d materials, %d products, %d foes" % (len(REGIONS), len(MATS), len(PRODUCTS), len(FOES)))
main()
