#!/usr/bin/env python3
"""2026-11-06: the solo world, grown. Robert: "is our world too small for solo play" -- it was (every Land ~250 m
across, crossed in thirty seconds, and each Land's gate opened straight into the next).

What this does to data/frontier.json (idempotent: it marks what it did with "_grown": 2 and "_road": true):
  1. THE LANDS ~3x the ground: width and height x1.7, with sub-areas the generator (scripts/world/Frontier.gd)
     now knows how to draw -- groves (a ring of old trees around a clearing of herbs and a cache), caves (a rock
     shelf with one way in, ore and gems along its walls, a cache at the back), more camps (where the Land's people
     stand) and ruins. Big props are spread a little thinner per cell so the frame rate holds; foes x2.
  2. ROADS between the Lands: every Land-to-Land gate now opens onto a road -- a long open stretch with a
     waystation (a keeper who trades), a road-warden, camps, ruins, a grove and a cave, foes from both ends,
     and the far end's gate. The way back works the same in reverse.
Backups: data/frontier.json.bak-world-20261106 (once). Run from the project root:  python3 tools/gen/world_gen.py
Dev: change names/lines/stock freely (keep ids). Re-running is safe."""
import json, os, shutil

P = "data/frontier.json"
LANDS = ["whisperwood", "mistfen", "bonefields", "jadehill", "sunken_mere", "stormcliffs", "emberwaste", "frostmere", "sandglass", "blighted_wood"]
SCALE = 1.7

# road id -> (from, to, name, blurb, waystation keeper, warden, lore)
ROADS = {
    "whisperwood": {
        "mistfen": ("The Mosslight Track", "Where the old trees thin and the ground starts to give. Lanterns on poles, most of them still lit.",
                    ("Keeper Arn", "Coin for dry socks. Coin for anything, really -- the fen takes the rest."),
                    ("Warden Sel", "Stay on the boards where there are boards. Where there aren't, step where the moss is greenest."),
                    ("A Lantern Pole", "LIGHT ONE, LEAVE ONE. WHOEVER COMES AFTER YOU IS CARRYING THE SAME DARK.")),
        "jadehill": ("The Pilgrims' Stair", "A climb of worn steps out of the wood and up toward the terraces. Shrines at every turn, offerings still fresh.",
                     ("Keeper Hui", "Tea, rice, rope. Pilgrims buy the first two going up and the third coming down."),
                     ("Warden Tamsin", "The monkeys on this stair will rob you blind. Hold your bag in front, not behind."),
                     ("A Shrine Step", "EVERY STEP IS A BOW. EVERY BOW IS A STEP. THE TERRACES ARE FOR THOSE WHO KEEP BOWING.")),
        "blighted_wood": ("The Rot Road", "The wood goes wrong by degrees: first the colour, then the smell, then the silence. Someone keeps the road open anyway.",
                          ("Keeper Vosh", "Masks, salves, burning-sticks. You'll want all three before the trees start breathing back."),
                          ("Warden Ilk", "If a tree moves, it isn't a tree. If it doesn't move, it might still not be a tree."),
                          ("A Burned Marker", "WE CUT THIS ROAD TO KEEP IT FROM SPREADING. IT SPREADS ALONG THE ROAD INSTEAD. KEEP CUTTING.")),
    },
    "bonefields": {
        "emberwaste": ("The Ashwalk", "A grey road through grey fields, getting warmer underfoot with every mile, until the ground glows through the cracks.",
                       ("Keeper Dusk", "Water costs more out here. So does everything. That's the heat talking."),
                       ("Warden Brann", "Walk at dawn or dusk. At noon the stones will cook your boots."),
                       ("A Heat-Cracked Milestone", "THE DEAD LIE NORTH. THE FIRE LIES SOUTH. THE LIVING WALK BETWEEN, AND ARE GLAD OF IT.")),
    },
    "mistfen": {
        "sunken_mere": ("The Drowned Causeway", "An old stone causeway, half under water. Fish swim through what used to be its arches.",
                        ("Keeper Nell", "Mind the third arch, it's gone soft. And buy a pole -- you'll want to test the water before you trust it."),
                        ("Warden Coll", "When the water is still, something is watching. When it ripples, it's coming."),
                        ("A Causeway Stone", "BUILT BY THE MERE-KINGS. DROWNED BY THE MERE-KINGS. THEY WANTED IT BOTH WAYS.")),
    },
    "jadehill": {
        "stormcliffs": ("The Thunder Ledge", "A cliff path cut into the rock, wide enough for one cart, with the wind trying to take it from you the whole way.",
                        ("Keeper Bo", "Iron spikes for your boots. Copper rods for your pack. Trust me, you want the rods."),
                        ("Warden Rhian", "If your hair stands up, lie flat. Not near the edge."),
                        ("A Lightning-Scarred Post", "STRUCK NINE TIMES. STILL STANDING. BE LIKE THE POST.")),
    },
    "stormcliffs": {
        "frostmere": ("The White Pass", "Up out of the storms and into the cold. The snow is deep, the air is thin, and every sound carries for miles.",
                      ("Keeper Yeva", "Furs, fire-oil, dried meat. And a bell -- ring it if you fall, someone may come."),
                      ("Warden Oskar", "Follow the poles. When you can't see the next pole, stop and wait for it."),
                      ("A Frozen Cairn", "EACH STONE IS ONE WHO MADE IT. ADD YOURS WHEN YOU COME BACK DOWN.")),
    },
    "emberwaste": {
        "sandglass": ("The Glassblow Flats", "Where the fire cooled into sand and the sand into glass. The wind sings across it, high and thin.",
                      ("Keeper Zahir", "Veils for the glare, wraps for the cuts. The flats are beautiful and they want your skin."),
                      ("Warden Ama", "If the wind starts singing low, find shelter. The low song strips flesh."),
                      ("A Glass Obelisk", "THE SAND REMEMBERS THE FIRE. THE GLASS REMEMBERS THE SAND. YOU WILL REMEMBER THIS ROAD.")),
    },
}

MERCHANT_BASE = ["healing_salve", "qi_pill", "antidote", "travellers_plate", "herb_broth"]


def load(p):
    return json.load(open(p, encoding="utf-8"))


def main():
    d = load(P)
    if not os.path.exists(P + ".bak-world-20261106"):
        shutil.copy(P, P + ".bak-world-20261106")
    R = d["regions"]
    items = load("data/items.json")
    items = items.get("items", items)
    # ---- 1. the Lands, grown
    for lid in LANDS:
        r = R[lid]
        if int(r.get("_grown", 0)) >= 2:
            continue
        r["w"] = int(round(int(r["w"]) * SCALE))
        r["h"] = int(round(int(r["h"]) * SCALE))
        dens = r.setdefault("density", {})
        for ch in ("x", "c"):
            if int(dens.get(ch, 0)) > 0:
                dens[ch] = int(round(int(dens[ch]) * 1.45))          # big props a little thinner per cell (perf)
        feats = list(r.get("features", []))
        feats += ["grove", "cave", "camp", "grove", "ruins", "cave", "camp"]
        r["features"] = feats
        r["foes"] = [[f[0], int(f[1]) * 2] for f in r.get("foes", [])]
        r["_grown"] = 2
    # ---- 2. roads
    eg = d.setdefault("extra_gates", {})
    made = []
    for a, tos in ROADS.items():
        gates = eg.get(a, [])
        if isinstance(gates, dict):
            gates = [gates]
        for gt in gates:
            b = str(gt["to"])
            if b not in tos and not (b.startswith("road_") and b.split("_to_")[-1] in tos):
                continue
            if b.startswith("road_"):
                b = b.split("_to_")[-1]
            rid = "road_%s_to_%s" % (a, b)
            name, blurb, keeper, warden, lore = tos[b]
            ra, rb = R[a], R[b]
            depth = (int(ra["depth"]) + int(rb["depth"])) // 2
            # gather: the commoner things of both ends
            gather = {}
            for k in ("herb", "ore", "gem"):
                rows = []
                for src in (ra, rb):
                    for it in (src.get("gather", {}).get(k, []) or [])[:2]:
                        rows.append(dict(it))
                if rows:
                    gather[k] = rows
            foes = [[f[0], max(3, int(f[1]) // 3)] for f in ra.get("foes", [])[:2]] + [[f[0], max(3, int(f[1]) // 3)] for f in rb.get("foes", [])[:2]]
            stock = [s for s in MERCHANT_BASE if s in items]
            for src in (ra, rb):
                for it in (src.get("gather", {}).get("herb", []) or [])[:1]:
                    if it["id"] in items:
                        stock.append(it["id"])
            look_src = rb
            road = {
                "name": name, "kind": "open", "w": 92, "h": 214, "depth": depth, "theme": look_src.get("theme", "wilds"),
                "look": look_src.get("look", "grove"), "blurb": blurb, "atmos": look_src.get("atmos", {}),
                "rock": 0.16, "freq": 0.05, "gate_from": a, "gate_back": str(gt["char"]),
                "rim": look_src.get("rim", "rocks"), "giants": ra.get("giants", {}), "lamp": ra.get("lamp", ""), "motes": rb.get("motes", ""),
                "features": ["camp", "ruins", "grove", "camp", "cave", "ruins"],
                "density": {"h": 90, "o": 190, "^": 230, "x": 44, "c": 90},
                "gather": gather, "foes": foes, "road": True, "_road": True,
                "npcs": [
                    {"role": "merchant", "name": keeper[0], "stays": True, "stock": stock, "line": keeper[1],
                     "persona": "%s, who keeps the waystation on %s. Practical, tired, honest about prices." % (keeper[0], name)},
                    {"role": "villager", "name": warden[0], "stays": True, "line": warden[1],
                     "persona": "%s, who walks %s and knows every bad stretch of it." % (warden[0], name)},
                ],
                "lore": [{"title": lore[0], "text": lore[1]}],
            }
            for k in ("ground_tint", "deco", "cliff_tint"):
                if k in look_src:
                    road[k] = look_src[k]
            R[rid] = road
            eg[rid] = [{"char": "1", "to": b, "arrive": "<", "label": rb["name"], "style": "hatch"}]
            # a's gate now opens onto the road; b's way back leads onto the road and arrives at its far gate
            gt["to"] = rid
            gt["label"] = name
            rb["gate_from"] = rid
            rb["gate_back"] = "1"
            made.append(rid)
        eg[a] = gates
    d["_note"] = str(d.get("_note", "")) + ("" if "world_gen" in str(d.get("_note", "")) else "  2026-11-06: tools/gen/world_gen.py grew the Lands ~3x and put a road between every two of them.")
    json.dump(d, open(P, "w", encoding="utf-8"), indent=1, ensure_ascii=False)
    print("lands grown:", len(LANDS), " roads:", len(made), made)


if __name__ == "__main__":
    main()
