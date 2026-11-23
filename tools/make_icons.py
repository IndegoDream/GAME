#!/usr/bin/env python3
"""Round 139: icons for every item that doesn't have one yet (96x96, the same dark rounded tile as the hand-made set).
Run from the game folder:  python3 tools/make_icons.py [--sheet out.png]
Only draws what is missing; never overwrites. Shape comes from the item's name/type, colour from its element (crafting.json)."""
import json, math, os, sys, hashlib
from PIL import Image, ImageDraw, ImageFilter

S = 4
N = 96 * S
ELEM = {"wood": (96, 160, 90), "fire": (214, 104, 70), "earth": (176, 140, 84), "metal": (150, 160, 178), "water": (86, 150, 200), "": (160, 140, 190)}
TILE = {"wood": (30, 52, 34), "fire": (62, 34, 30), "earth": (56, 48, 32), "metal": (40, 46, 58), "water": (28, 46, 70), "": (44, 38, 56)}


def mix(a, b, t):
    return tuple(int(a[i] * (1 - t) + b[i] * t) for i in range(3))


def tile(el):
    im = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    base = TILE.get(el, TILE[""])
    d.rounded_rectangle([2 * S, 2 * S, N - 2 * S, N - 2 * S], radius=14 * S, fill=(150, 150, 165, 255))
    d.rounded_rectangle([5 * S, 5 * S, N - 5 * S, N - 5 * S], radius=11 * S, fill=base + (255,))
    # a quiet lighter top
    top = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    td = ImageDraw.Draw(top)
    td.rounded_rectangle([5 * S, 5 * S, N - 5 * S, 44 * S], radius=11 * S, fill=mix(base, (255, 255, 255), 0.07) + (255,))
    mask = Image.new("L", (N, N), 0)
    ImageDraw.Draw(mask).rounded_rectangle([5 * S, 5 * S, N - 5 * S, N - 5 * S], radius=11 * S, fill=255)
    im.paste(top, (0, 0), Image.composite(top.split()[3], Image.new("L", (N, N), 0), mask))
    d.rounded_rectangle([7 * S, 7 * S, N - 7 * S, N - 7 * S], radius=9 * S, outline=mix(base, (255, 255, 255), 0.12) + (255,), width=S)
    return im


def P(x, y):
    return (x * S, y * S)


def poly(d, pts, col, hi=True):
    d.polygon([P(*p) for p in pts], fill=col + (255,))
    if hi:
        d.line([P(*pts[0]), P(*pts[1])], fill=mix(col, (255, 255, 255), 0.45) + (255,), width=2 * S)


def gem(d, c):
    cx, cy, r = 48, 50, 22
    pts = [(cx + r * math.cos(math.radians(a)), cy + r * math.sin(math.radians(a))) for a in range(-90, 270, 60)]
    poly(d, pts, c)
    d.polygon([P(*pts[0]), P(*pts[1]), P(cx, cy)], fill=mix(c, (255, 255, 255), 0.35) + (255,))


def chunk(d, c):
    pts = [(30, 52), (36, 34), (52, 28), (66, 38), (68, 58), (54, 68), (38, 66)]
    poly(d, pts, c)
    d.polygon([P(36, 34), P(52, 28), P(50, 42), P(40, 46)], fill=mix(c, (255, 255, 255), 0.3) + (255,))


def leaf(d, c):
    d.line([P(48, 72), P(48, 34)], fill=mix(c, (0, 0, 0), 0.3) + (255,), width=3 * S)
    for k, (dx, dy, w) in enumerate([(-1, 0, 20), (1, 8, 18), (-1, 16, 15), (1, 22, 12)]):
        x = 48 + dx * 4
        y = 56 - dy
        box = [P(x if dx > 0 else x - w, y - 8), P(x + w if dx > 0 else x, y + 4)]
        d.ellipse(box, fill=mix(c, (255, 255, 255), 0.1 * (k % 2)) + (255,))
    d.ellipse([P(41, 22), P(55, 44)], fill=mix(c, (255, 255, 255), 0.18) + (255,))


def bloom(d, c):
    for a in range(0, 360, 60):
        x, y = 48 + 14 * math.cos(math.radians(a)), 46 + 14 * math.sin(math.radians(a))
        d.ellipse([P(x - 9, y - 9), P(x + 9, y + 9)], fill=c + (255,))
    d.ellipse([P(40, 38), P(56, 54)], fill=(240, 220, 130, 255))
    d.line([P(48, 58), P(48, 76)], fill=(70, 130, 70, 255), width=3 * S)


def moss(d, c):
    for (x, y, r) in [(36, 56, 12), (50, 50, 15), (62, 58, 11), (46, 62, 13), (56, 64, 9)]:
        d.ellipse([P(x - r, y - r), P(x + r, y + r)], fill=mix(c, (255, 255, 255), 0.05 * (x % 3)) + (255,))


def jar(d, c):
    d.rounded_rectangle([P(30, 40), P(66, 72)], radius=5 * S, fill=c + (255,))
    d.rounded_rectangle([P(28, 30), P(68, 42)], radius=3 * S, fill=mix(c, (0, 0, 0), 0.35) + (255,))
    d.rounded_rectangle([P(36, 50), P(60, 62)], radius=3 * S, fill=mix(c, (255, 255, 255), 0.5) + (255,))


def flask(d, c):
    d.rounded_rectangle([P(42, 20), P(54, 30)], radius=2 * S, fill=mix(c, (0, 0, 0), 0.35) + (255,))
    d.polygon([P(43, 30), P(53, 30), P(70, 70), P(26, 70)], fill=c + (255,))
    d.polygon([P(36, 56), P(60, 56), P(70, 70), P(26, 70)], fill=mix(c, (255, 255, 255), 0.4) + (255,))


def bow(d, c):
    d.arc([P(30, 18), P(80, 78)], 100, 260, fill=c + (255,), width=4 * S)
    d.line([P(44, 21), P(44, 75)], fill=(220, 220, 220, 255), width=S)
    d.line([P(30, 48), P(66, 48)], fill=mix(c, (255, 255, 255), 0.4) + (255,), width=2 * S)
    d.polygon([P(66, 48), P(60, 44), P(60, 52)], fill=(230, 230, 230, 255))


def crossbow(d, c):
    d.rounded_rectangle([P(44, 22), P(52, 76)], radius=2 * S, fill=mix(c, (0, 0, 0), 0.25) + (255,))
    d.arc([P(14, 24), P(82, 58)], 200, 340, fill=c + (255,), width=4 * S)
    d.line([P(18, 41), P(78, 41)], fill=(220, 220, 220, 255), width=S)
    d.line([P(48, 28), P(48, 50)], fill=(230, 230, 230, 255), width=2 * S)


def wraps(d, c):
    d.rounded_rectangle([P(28, 30), P(66, 70)], radius=8 * S, fill=c + (255,))
    for y in (38, 48, 58):
        d.line([P(28, y), P(66, y + 4)], fill=mix(c, (255, 255, 255), 0.45) + (255,), width=3 * S)
    d.rounded_rectangle([P(60, 26), P(74, 46)], radius=5 * S, fill=mix(c, (0, 0, 0), 0.2) + (255,))


def ingot(d, c):
    poly(d, [(26, 62), (36, 38), (62, 38), (72, 62)], c)
    d.polygon([P(36, 38), P(62, 38), P(58, 46), P(40, 46)], fill=mix(c, (255, 255, 255), 0.35) + (255,))


def crystal(d, c):
    poly(d, [(48, 16), (62, 42), (48, 78), (34, 42)], c)
    d.polygon([P(48, 16), P(62, 42), P(48, 44)], fill=mix(c, (255, 255, 255), 0.35) + (255,))


def orb(d, c):
    d.ellipse([P(28, 30), P(68, 70)], fill=c + (255,), outline=(235, 235, 245, 255), width=2 * S)
    d.ellipse([P(36, 38), P(46, 48)], fill=mix(c, (255, 255, 255), 0.6) + (255,))


def core(d, c):
    d.ellipse([P(26, 26), P(70, 70)], fill=mix(c, (0, 0, 0), 0.3) + (255,))
    d.ellipse([P(34, 34), P(62, 62)], fill=c + (255,))
    d.ellipse([P(43, 43), P(53, 53)], fill=mix(c, (255, 255, 255), 0.7) + (255,))


def blade(d, c):
    d.polygon([P(46, 16), P(52, 16), P(54, 62), P(44, 62)], fill=c + (255,))
    d.rounded_rectangle([P(34, 62), P(64, 68)], radius=2 * S, fill=(150, 120, 70, 255))
    d.rounded_rectangle([P(45, 68), P(53, 80)], radius=2 * S, fill=(110, 80, 50, 255))



def chest(d, c):
    d.polygon([P(30, 28), P(40, 24), P(48, 30), P(56, 24), P(66, 28), P(72, 40), P(64, 44), P(64, 74), P(32, 74), P(32, 44), P(24, 40)], fill=c + (255,))
    d.line([P(48, 30), P(48, 74)], fill=mix(c, (0, 0, 0), 0.3) + (255,), width=2 * S)
    d.line([P(34, 48), P(62, 48)], fill=mix(c, (255, 255, 255), 0.35) + (255,), width=2 * S)


def cowl(d, c):
    d.pieslice([P(26, 22), P(70, 78)], 180, 360, fill=c + (255,))
    d.rectangle([P(26, 50), P(70, 70)], fill=c + (255,))
    d.ellipse([P(36, 44), P(60, 66)], fill=mix(c, (0, 0, 0), 0.6) + (255,))


def mask(d, c):
    d.polygon([P(28, 30), P(68, 30), P(66, 54), P(56, 70), P(48, 74), P(40, 70), P(30, 54)], fill=c + (255,))
    d.ellipse([P(34, 40), P(44, 48)], fill=(20, 20, 25, 255))
    d.ellipse([P(52, 40), P(62, 48)], fill=(20, 20, 25, 255))


def cape(d, c):
    d.polygon([P(34, 22), P(62, 22), P(74, 76), P(48, 68), P(22, 76)], fill=c + (255,))
    d.rectangle([P(34, 20), P(62, 28)], fill=mix(c, (255, 255, 255), 0.3) + (255,))


def pauldrons(d, c):
    d.pieslice([P(14, 30), P(54, 80)], 180, 360, fill=c + (255,))
    d.pieslice([P(42, 30), P(82, 80)], 180, 360, fill=mix(c, (255, 255, 255), 0.12) + (255,))
    d.line([P(18, 56), P(50, 56)], fill=mix(c, (0, 0, 0), 0.3) + (255,), width=2 * S)


def robe(d, c):
    d.polygon([P(36, 20), P(60, 20), P(64, 36), P(74, 78), P(22, 78), P(32, 36)], fill=c + (255,))
    d.polygon([P(44, 20), P(52, 20), P(54, 78), P(42, 78)], fill=mix(c, (255, 255, 255), 0.3) + (255,))


def shirt(d, c):
    d.polygon([P(34, 24), P(44, 28), P(52, 28), P(62, 24), P(76, 38), P(66, 46), P(64, 74), P(32, 74), P(30, 46), P(20, 38)], fill=mix(c, (0, 0, 0), 0.15) + (255,))


def vambraces(d, c):
    for x in (22, 52):
        d.polygon([P(x, 26), P(x + 22, 26), P(x + 18, 74), P(x + 4, 74)], fill=c + (255,))
        d.line([P(x + 3, 40), P(x + 19, 40)], fill=mix(c, (255, 255, 255), 0.4) + (255,), width=2 * S)
        d.line([P(x + 4, 56), P(x + 18, 56)], fill=mix(c, (255, 255, 255), 0.4) + (255,), width=2 * S)


def gloves(d, c):
    d.rounded_rectangle([P(30, 40), P(66, 76)], radius=8 * S, fill=c + (255,))
    for x in (30, 40, 50, 60):
        d.rounded_rectangle([P(x, 20), P(x + 8, 46)], radius=4 * S, fill=c + (255,))
    d.rounded_rectangle([P(24, 44), P(36, 62)], radius=5 * S, fill=mix(c, (255, 255, 255), 0.15) + (255,))
    d.rectangle([P(30, 68), P(66, 76)], fill=mix(c, (0, 0, 0), 0.3) + (255,))


def pants(d, c):
    d.polygon([P(30, 22), P(66, 22), P(70, 76), P(54, 76), P(48, 44), P(42, 76), P(26, 76)], fill=c + (255,))
    d.rectangle([P(30, 22), P(66, 30)], fill=mix(c, (255, 255, 255), 0.25) + (255,))


def greaves(d, c):
    for x in (24, 52):
        d.polygon([P(x, 20), P(x + 20, 20), P(x + 16, 74), P(x + 4, 74)], fill=c + (255,))
        d.ellipse([P(x + 2, 36), P(x + 18, 50)], fill=mix(c, (255, 255, 255), 0.3) + (255,))


def boots(d, c):
    d.polygon([P(34, 20), P(54, 20), P(54, 56), P(74, 64), P(74, 76), P(30, 76)], fill=c + (255,))
    d.rectangle([P(30, 70), P(74, 78)], fill=mix(c, (0, 0, 0), 0.35) + (255,))
    d.rectangle([P(34, 20), P(54, 28)], fill=mix(c, (255, 255, 255), 0.3) + (255,))


def ring(d, c):
    d.ellipse([P(26, 34), P(70, 78)], outline=c + (255,), width=7 * S)
    d.polygon([P(48, 18), P(58, 30), P(48, 38), P(38, 30)], fill=mix(c, (255, 255, 255), 0.5) + (255,))


def bracelet(d, c):
    d.ellipse([P(18, 30), P(78, 74)], outline=c + (255,), width=8 * S)
    d.ellipse([P(40, 24), P(56, 38)], fill=mix(c, (255, 255, 255), 0.45) + (255,))


def necklace(d, c):
    d.arc([P(22, 14), P(74, 74)], 20, 160, fill=mix(c, (255, 255, 255), 0.1) + (255,), width=3 * S)
    d.polygon([P(48, 62), P(58, 72), P(48, 84), P(38, 72)], fill=c + (255,))


def scroll(d, c):
    d.rounded_rectangle([P(26, 26), P(70, 70)], radius=4 * S, fill=(226, 214, 180, 255))
    d.ellipse([P(20, 22), P(34, 74)], fill=mix((226, 214, 180), (0, 0, 0), 0.2) + (255,))
    d.ellipse([P(62, 22), P(76, 74)], fill=mix((226, 214, 180), (0, 0, 0), 0.2) + (255,))
    for y in (38, 48, 58):
        d.line([P(36, y), P(60, y)], fill=c + (255,), width=2 * S)


def runestone(d, c):
    d.rounded_rectangle([P(28, 22), P(68, 74)], radius=14 * S, fill=(96, 98, 112, 255))
    d.line([P(48, 32), P(48, 64)], fill=c + (255,), width=3 * S)
    d.line([P(48, 44), P(38, 36)], fill=c + (255,), width=3 * S)
    d.line([P(48, 52), P(58, 44)], fill=c + (255,), width=3 * S)


def talisman(d, c):
    d.rounded_rectangle([P(34, 14), P(62, 82)], radius=3 * S, fill=(232, 220, 170, 255))
    d.line([P(48, 24), P(48, 70)], fill=(190, 40, 40, 255), width=3 * S)
    d.line([P(40, 34), P(56, 34)], fill=(190, 40, 40, 255), width=3 * S)
    d.line([P(40, 50), P(56, 50)], fill=(190, 40, 40, 255), width=3 * S)


def treasure(d, c):
    pts = []
    for i in range(10):
        r = 26 if i % 2 == 0 else 11
        a = math.radians(-90 + i * 36)
        pts.append((48 + r * math.cos(a), 48 + r * math.sin(a)))
    poly(d, pts, mix(c, (255, 220, 120), 0.5), hi=False)


def urn(d, c):
    d.polygon([P(38, 20), P(58, 20), P(56, 30), P(68, 46), P(62, 74), P(34, 74), P(28, 46), P(40, 30)], fill=c + (255,))
    d.line([P(32, 50), P(64, 50)], fill=mix(c, (255, 255, 255), 0.4) + (255,), width=2 * S)


def flame(d, c):
    d.polygon([P(48, 14), P(66, 44), P(60, 72), P(48, 80), P(36, 72), P(30, 44), P(42, 52)], fill=c + (255,))
    d.polygon([P(48, 40), P(56, 56), P(52, 72), P(44, 72), P(40, 56)], fill=mix(c, (255, 255, 255), 0.55) + (255,))


def key(d, c):
    d.ellipse([P(22, 26), P(46, 50)], outline=c + (255,), width=5 * S)
    d.rectangle([P(44, 36), P(76, 42)], fill=c + (255,))
    d.rectangle([P(66, 42), P(70, 52)], fill=c + (255,))
    d.rectangle([P(56, 42), P(60, 50)], fill=c + (255,))


def bowl(d, c):
    ## round 164: a meal -- a bowl with steam
    d.pieslice([P(22, 34), P(74, 86)], 0, 180, fill=c + (255,))
    d.rectangle([P(22, 59), P(74, 62)], fill=mix(c, (255, 255, 255), 0.45) + (255,))
    d.ellipse([P(24, 52), P(72, 66)], fill=mix(c, (255, 220, 150), 0.5) + (255,))
    for x in (38, 48, 58):
        d.arc([P(x - 4, 20), P(x + 4, 34)], 90, 270, fill=(235, 235, 235, 255), width=2 * S)


STOCK = {"jade": (96, 190, 140), "iron": (150, 158, 170), "bone": (226, 218, 196), "bronze": (190, 130, 70), "silver": (204, 210, 224), "gold": (232, 190, 80),
         "steel": (128, 150, 190), "ember": (220, 100, 60), "dragon": (200, 80, 80), "spirit": (140, 190, 230), "nanite": (110, 220, 210), "frost": (170, 220, 240),
         "leather": (160, 110, 70), "silk": (210, 170, 220), "hide": (150, 110, 80), "cloth": (200, 190, 170), "storm": (130, 130, 230), "star": (200, 200, 120)}


MEALS = set()


def pick2(k, typ):
    n = k
    if k in MEALS:
        return bowl
    for fam, fn in [("underarmour", shirt), ("chest", chest), ("armor", chest), ("mail", chest), ("vest", chest), ("cowl", cowl), ("hood", cowl), ("helm", cowl), ("mask", mask), ("cape", cape), ("cloak", cape),
                    ("pauldron", pauldrons), ("robe", robe), ("underarmour", shirt), ("vambrace", vambraces), ("gauntlet", gloves), ("glove", gloves), ("pants", pants),
                    ("greave", greaves), ("boot", boots), ("toering", ring), ("ring", ring), ("bracelet", bracelet), ("choker", necklace), ("necklace", necklace), ("amulet", necklace),
                    ("pendant", necklace)]:
        if fam in n or fam == typ:
            return fn
    if typ in ("formula", "quest"):
        return scroll if typ == "formula" or "scroll" in n or "note" in n or "words" in n or "score" in n else key
    return {"rune": runestone, "talisman": talisman, "treasure": treasure, "relic": urn, "crystal": gem}.get(typ, None) or (flame if "essence" in n else None)


def pick(name, typ):
    n = name
    if any(k in n for k in ("crossbow", "arbalest")):
        return crossbow
    if "bow" in n:
        return bow
    if any(k in n for k in ("wrap", "gauntlet", "glove", "palm")):
        return wraps
    if any(k in n for k in ("coating", "salve", "balm", "oil", "ointment")):
        return jar
    if any(k in n for k in ("antidote", "tonic", "elixir", "potion", "tincture", "draught")):
        return flask
    if any(k in n for k in ("ingot", "titanium", "steel", "iron", "alloy", "silver", "gantry")):
        return ingot
    if any(k in n for k in ("quartz", "crystal", "ice", "glass", "fulgurite", "beacon", "jade", "ruby", "shard")):
        return crystal if "crystal" in n or "quartz" in n or "ice" in n else gem
    if any(k in n for k in ("lichen", "moss", "mycelium", "spore", "cap")):
        return moss
    if any(k in n for k in ("bloom", "lotus", "orchid", "flower", "petal")):
        return bloom
    if any(k in n for k in ("basil", "fern", "reed", "herb", "thistle", "root", "leaf", "sunreed")):
        return leaf
    if any(k in n for k in ("core", "ember", "pearl", "orb")):
        return core
    if any(k in n for k in ("sword", "blade", "dagger", "saber")):
        return blade
    if typ == "consumable":
        return flask
    return chunk


def main():
    it = json.load(open("data/items.json"))
    if "--ids" in sys.argv:                          # the full list as the running game sees it (generated gear, system items)
        extra = json.load(open(sys.argv[sys.argv.index("--ids") + 1]))
        for k, v in extra.items():
            it.setdefault(k, v)
    cr = json.load(open("data/crafting.json")).get("materials", {})
    if os.path.exists("data/cooking.json"):              # round 164: meals live in cooking.json
        for m in json.load(open("data/cooking.json")).get("meals", []):
            it.setdefault(m["id"], {"name": m["name"], "type": "consumable"})
            MEALS.add(m["id"])
    have = set(f[:-4] for f in os.listdir("assets/icons/items") if f.endswith(".png"))
    gen_path = "assets/icons/_generated.txt"           # the ones drawn by this script (so they may be redrawn; hand-made ones never are)
    gen = set(open(gen_path).read().split()) if os.path.exists(gen_path) else set()
    have -= gen
    made = []
    for k, v in it.items():
        if k in have or not isinstance(v, dict):
            continue
        el = str((cr.get(k) or {}).get("element", v.get("element", "")) or "")
        el = el if el in ELEM else ""
        im = tile(el)
        d = ImageDraw.Draw(im)
        col = ELEM[el]
        if el == "":                                      # no element: a colour from the name, so a family of pieces tells apart
            col = [(170, 140, 200), (200, 150, 110), (120, 190, 170), (200, 120, 140), (130, 160, 210), (190, 190, 120)][int(hashlib.md5(k.encode()).hexdigest()[2:4], 16) % 6]
        h = int(hashlib.md5(k.encode()).hexdigest()[:2], 16) / 255.0
        col = mix(col, (255, 255, 255), 0.1 + 0.25 * h) if h > 0.5 else mix(col, (0, 0, 0), 0.1 * h)
        for sk, sc in STOCK.items():
            if sk in k and not el:
                col = sc
        fn = pick2(k, str(v.get("type", ""))) or pick(k, str(v.get("type", "")))
        fn(d, col)
        out = im.resize((96, 96), Image.LANCZOS)
        out.save("assets/icons/items/%s.png" % k)
        made.append(k)
    print("drew", len(made), "icons")
    gen |= set(made)
    open(gen_path, "w").write("\n".join(sorted(gen)) + "\n")
    if "--sheet" in sys.argv and made:
        out = sys.argv[sys.argv.index("--sheet") + 1]
        cols = 10
        rows = (len(made) + cols - 1) // cols
        W = Image.new("RGBA", (cols * 112, rows * 112), (30, 30, 36, 255))
        for i, k in enumerate(made):
            im = Image.open("assets/icons/items/%s.png" % k).convert("RGBA")
            W.paste(im, ((i % cols) * 112 + 8, (i // cols) * 112 + 8), im)
        W.save(out)
    # keep the index honest (the game finds icons by file name, the index is for tools)
    try:
        idx = json.load(open("assets/icons/index.json"))
        for k in made:
            idx.setdefault("items", {})[k] = "items/%s.png" % k
        json.dump(idx, open("assets/icons/index.json", "w"), indent=1)
    except Exception as ex:
        print("index not updated:", ex)


main()
