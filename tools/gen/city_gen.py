#!/usr/bin/env python3
"""2026-11-06: the Common City (levels/city.json). Robert, 2026-11-03: "a common city for chat, trade and co-op ...
auction houses ... towns and sects larger with a country feel, not crowded (a few buildings isn't a town)".
Offline now, built online-ready: the Exchange (auction house), the Notice Wall (online: other players' posts and
co-op calls), an inn, a smithy, an apothecary, a guild hall, a temple, a park, a canal with bridges, broad avenues.
Reached from Eliet's east road (village exit "C") and by waystone. Deterministic. Run: python3 tools/gen/city_gen.py"""
import json, math, random, os
from collections import deque

P = "levels/city.json"
W, H = 176, 140
rng = random.Random(20261106)
g = [[" "] * W for _ in range(H)]


def inside(x, y): return 0 <= x < W and 0 <= y < H
def at(x, y): return g[y][x] if inside(x, y) else " "
def put(x, y, c):
    if inside(x, y): g[y][x] = c


# the land inside the walls, with a margin of meadow and woods outside them
for y in range(3, H - 3):
    for x in range(3, W - 3):
        g[y][x] = "."
X0, Y0, X1, Y1 = 14, 12, W - 15, H - 13          # the walls
for x in range(X0, X1 + 1):
    for t in (0, 1):
        put(x, Y0 + t, "#"); put(x, Y1 - t, "#")
for y in range(Y0, Y1 + 1):
    for t in (0, 1):
        put(X0 + t, y, "#"); put(X1 - t, y, "#")
cx, cy = W // 2, H // 2
# woods outside the walls
for y in range(3, H - 3):
    for x in range(3, W - 3):
        if (x < X0 - 1 or x > X1 + 1 or y < Y0 - 1 or y > Y1 + 1) and rng.random() < 0.18:
            g[y][x] = "t"


def road(x0, y0, x1, y1, wd=3):
    x, y = x0, y0
    while True:
        for ox in range(-(wd // 2), wd - wd // 2):
            for oy in range(-(wd // 2), wd - wd // 2):
                if at(x + ox, y + oy) in ".t#":
                    put(x + ox, y + oy, ",")
        if (x, y) == (x1, y1):
            break
        if x != x1:
            x += 1 if x1 > x else -1
        elif y != y1:
            y += 1 if y1 > y else -1


# two great avenues crossing at the plaza, through four gates
road(cx, Y0 - 6, cx, Y1 + 6, 5)
road(X0 - 6, cy, X1 + 6, cy, 5)
# ring road inside the walls
road(X0 + 5, Y0 + 5, X1 - 5, Y0 + 5, 3); road(X1 - 5, Y0 + 5, X1 - 5, Y1 - 5, 3)
road(X1 - 5, Y1 - 5, X0 + 5, Y1 - 5, 3); road(X0 + 5, Y1 - 5, X0 + 5, Y0 + 5, 3)
# lanes
for lx in (cx - 40, cx - 20, cx + 20, cx + 40):
    road(lx, Y0 + 5, lx, Y1 - 5, 2)
for ly in (cy - 26, cy + 26):
    road(X0 + 5, ly, X1 - 5, ly, 2)

# the canal: east-west, south of the plaza, with a bridge wherever a road crosses
cyy = cy + 14
for x in range(X0 + 2, X1 - 1):
    for t in range(3):
        if at(x, cyy + t) == ",":
            continue          # (a road crossing it is a bridge)
        put(x, cyy + t, "~")

# the plaza: a wide paved oval, fountain in the middle, lamps round it
for y in range(cy - 9, cy + 10):
    for x in range(cx - 14, cx + 15):
        if ((x - cx) / 14.0) ** 2 + ((y - cy) / 9.0) ** 2 <= 1.0:
            put(x, y, ",")
put(cx, cy, "f")
for a in range(0, 360, 30):
    put(int(cx + 13 * math.cos(math.radians(a))), int(cy + 8 * math.sin(math.radians(a))), "L")


def building(x, y, w, h):
    for yy in range(y, y + h):
        for xx in range(x, x + w):
            if at(xx, yy) in ".t":
                put(xx, yy, "H")


def free(x, y, w, h, m=1):
    for yy in range(y - m, y + h + m):
        for xx in range(x - m, x + w + m):
            if at(xx, yy) != ".":
                return False
    return True


# named places: a building with its keeper standing at the door, on open ground
npcs = {}
def place(letter, role, name, line, x, y, w, h, persona=""):
    for yy in range(y - 2, y + h + 4):
        for xx in range(x - 2, x + w + 2):
            if at(xx, yy) in "tH":
                put(xx, yy, ".")
    building(x, y, w, h)
    dx, dy = x + w // 2, y + h + 1
    for yy in range(y + h, y + h + 3):
        put(dx, yy, ",")
    put(dx, dy, letter)
    n = {"role": role, "name": name, "line": line, "stays": True}
    if persona:
        n["persona"] = persona
    npcs[letter] = n

place("A", "auction", "Clerk Marrow", "Lots in, lots out, coin across the counter. The Exchange never closes; it only gets quieter.",
      cx - 7, cy - 22, 14, 6, "Clerk Marrow, who keeps the Exchange's book. Dry, exact, quietly delighted by a good haggle.")
place("B", "notice", "The Notice Wall", "Notices, wanted posters, someone's lost goat.", cx + 18, cy - 12, 8, 3)
place("I", "innkeeper", "Mother Quill", "Beds upstairs, stew down here, and gossip at no extra charge.", cx - 31, cy - 12, 10, 5,
      "Mother Quill, who runs the Lantern & Ledger inn. Loud, warm, knows everyone's business.")
place("F", "smith", "Smith Odalys", "City iron, city prices, city quality. Mostly.", cx + 26, cy + 3, 9, 5,
      "Smith Odalys of the Brass Street forge. Proud of her work, blunt about yours.")
place("N", "alchemist", "Apothecary Venn", "Remedies for the road and for what the road does to you.", cx - 34, cy + 3, 9, 5,
      "Apothecary Venn, a careful man who labels everything twice.")
place("M", "merchant", "Factor Pelle", "Everything you need for the deep, and a few things you only think you need.", cx + 34, cy - 25, 9, 5)
place("G", "guild", "Guildmaster Ren", "The guilds meet here. Work for those who want it, and pay for those who finish it.", cx - 46, cy - 26, 12, 6)
place("K", "academy", "Proctor Lis", "The Academy keeps a hall in the city, for examinations and for those who came a long way.", cx + 44, cy + 22, 10, 5)
npcs["M"]["stock"] = ["healing_salve", "qi_pill", "calming_incense", "antidote", "storage_ring", "travellers_plate"]

# the temple: a raised shrine in a walled court, north-east
tx, ty = cx + 46, cy - 40
for yy in range(ty - 5, ty + 6):
    for xx in range(tx - 8, tx + 9):
        if at(xx, yy) in ".tH":
            put(xx, yy, ",")
put(tx, ty, "Z")
for xx in (tx - 6, tx + 6):
    for yy in (ty - 3, ty + 3):
        put(xx, yy, "L")

# the park: south-west, trees, a pond with a fishing spot, herbs
px, py = cx - 46, cy + 32
for yy in range(py - 10, py + 11):
    for xx in range(px - 16, px + 17):
        if at(xx, yy) in ".H":
            r = rng.random()
            put(xx, yy, "t" if r < 0.13 else ("h" if r < 0.17 else "."))
for yy in range(py - 3, py + 4):
    for xx in range(px - 5, px + 6):
        if ((xx - px) / 5.0) ** 2 + ((yy - py) / 3.0) ** 2 <= 1.0:
            put(xx, yy, "~")
put(px, py - 4, "&")

# houses: fill the blocks between the lanes, leaving courtyards and gaps (the city breathes)
tries = 0
houses = 0
while tries < 20000 and houses < 190:
    tries += 1
    w, h = rng.randint(4, 8), rng.randint(3, 5)
    x, y = rng.randint(X0 + 3, X1 - w - 3), rng.randint(Y0 + 3, Y1 - h - 3)
    if abs(x + w / 2 - cx) < 18 and abs(y + h / 2 - cy) < 12:
        continue          # (the plaza stays open)
    if free(x, y, w, h, 1 if rng.random() < 0.6 else 2):
        building(x, y, w, h)
        houses += 1
        if rng.random() < 0.3:
            put(x - 1, y + h, "c")          # a crate or barrel by the door

# lamps along the avenues
for y in range(1, H - 1):
    for x in range(1, W - 1):
        if g[y][x] == "," and (x * 7 + y * 13) % 13 == 0:
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                if at(x + dx, y + dy) == ".":
                    put(x + dx, y + dy, "L")
                    break

# the way back to Eliet: the west gate; you arrive just inside it
ex, ey = X0 - 4, cy
put(ex, ey, "E")
PX, PY = X0 + 4, cy
put(PX, PY, "P")
# lore stones
put(cx - 3, cy + 6, "R")
put(cx + 3, cy - 6, "Y")
lore = {
    "R": {"title": "The Charter Stone", "text": "THE COMMON CITY -- built by no one sect, owned by no one Land.\nEvery road in the deep ends here, or begins here, depending on which way you are walking.\n\nWhat is sold here is honestly weighed. What is said here is honestly heard. Whoever breaks either is walked to the gate."},
    "Y": {"title": "A Map Carved in Brass", "text": "Eliet, a day west. The valley beyond it. The stair down. And, scratched in by many hands since: the Lands, the roads between them, and in the corner, very small, 'and further than that, if you are brave'."},
}

rows = ["".join(r).rstrip() for r in g]
d = {"id": "city", "name": "The Common City", "theme": "village", "depth": 0,
     "notes": "Where every road in the deep meets: the Exchange, the Notice Wall, an inn, the guilds. Offline, the deep's other travellers trade here; online, other players.",
     "map": rows, "npcs": npcs, "exits": {"E": {"to": "village", "arrive": "C", "label": "The road west -- Eliet"}}, "lore": lore, "no_expand": True}
json.dump(d, open(P, "w"), indent=1, ensure_ascii=False)

# reachability: everything that matters can be walked to from P
WALK = set(".,PLoh^&Z=f") | set(npcs.keys()) | {"E", "R", "Y"}
start = (PX, PY)
seen = {start}
q = deque([start])
while q:
    x, y = q.popleft()
    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        n = (x + dx, y + dy)
        if n in seen or not inside(*n):
            continue
        if g[n[1]][n[0]] in WALK:
            seen.add(n)
            q.append(n)
miss = []
for k in list(npcs.keys()) + ["E", "Z", "f", "R", "Y"]:
    pos = [(x, y) for y in range(H) for x in range(W) if g[y][x] == k]
    if not pos:
        miss.append(k + ":absent")
    elif not any(p in seen for p in pos):
        miss.append(k + ":unreachable")
walk = sum(1 for y in range(H) for x in range(W) if g[y][x] in WALK)
print("city", W, H, "houses", houses, "walkable", walk, "unreachable/absent:", miss)
