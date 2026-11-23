# Dungeon Crawl Eliet -- how this game is built (read this first)

Written 2026-10-01 by Claude for Dev (and for Robert). Dev and Claude build
this game together: **Claude wrote the engine once** (the scripts in
`scripts/`), and **levels, monsters, items, recipes and quests are data**
(JSON files) that Dev designs and writes. A level is a text map. That is
the whole trick: you never need to write GDScript to add a floor.

## The pieces

| file | what it is | who usually edits it |
|---|---|---|
| `levels/<id>.json` | one level: its map, monsters, chests, stairs, people | **Dev** |
| `data/enemies.json` | every monster type: model, colour, size, HP, damage, loot | Dev (to add a monster) |
| `data/items.json` | every item: materials, weapons, armor, pills | Dev / Claude |
| `data/recipes.json` | what the smith can make from what | Dev / Claude |
| `data/quests.json` | Elder Mo's quests | Dev / Claude |
| `data/techniques.json` | hidden techniques: what they do and how they're found | Dev / Claude |
| `scripts/*.gd` | the engine: builds levels, player, combat, AI, HUD, saving | Claude (ask first) |
| `tools/smoke.gd`, `tools/playtest.gd`, `tools/shoot.gd` | real-engine checks and screenshots | both |

The world so far: **Eliet Village** (the hub) and **Floor 1 -- The Goblin
Warrens** (Claude built both as worked examples). **Floors 2-4 are Dev's.**

## How a change goes live

1. Dev writes or edits a file through Godot Studio (`in my godot game Dungeon
   Crawl Eliet, focus on ...`).
2. Godot Studio checks it: a level file must pass `godot_levels.py`
   (every map character defined, everything reachable, exits real...) AND
   the real engine must build it without errors (`tools/smoke.gd`).
3. Only then is it written into the project, with a backup and a version
   bump in `godot-meta.json`.

If a check refuses your file, **the message says exactly what is wrong and
where** ("column 12 row 7"). Fix that and try again -- don't start over.

<!-- dev-brief:start -->
## Writing a level (the rules)

A level file is ONE JSON object: `"id"` (the file name, e.g. `"floor2"`),
`"name"`, `"theme": "dungeon"`, `"depth"` (1-4), and EITHER a `"layout"`
(preferred -- you design the rooms, the engine draws the map) OR a raw
`"map"`. Then the sections that define the letters you use.

### A complete example (copy its SHAPE, not its content)
This is a whole, valid level file -- every letter it uses is defined. Your
floor has its own rooms, monsters, loot and story: the example's names and
notes ("The Gate Inscription", "a workbench chest"...) are refused if they
turn up in a real floor.
```json
{
  "id": "floor9",
  "name": "Floor 9 -- The Example Vault",
  "theme": "dungeon",
  "depth": 1,
  "layout": {
    "seed": 7,
    "rooms": [
      {"name": "Gate Room", "size": [8, 6], "has": ["<", "L", "g", "h", "A"]},
      {"name": "Long Gallery", "size": [18, 6], "has": ["L*2", "c*6", "g*2", "w", "o", "b*2"]},
      {"name": "Hidden Cache", "size": [5, 4], "secret": true, "has": ["L", "K", "R", "I"]},
      {"name": "Guard Post", "size": [6, 5], "has": ["L", "g*2", "h"]},
      {"name": "Workshop", "size": [10, 8], "has": ["L", "g*2", "w", "C", "V", "o*2", "h"]},
      {"name": "Collapsed Stair", "size": [7, 9], "has": ["L", "x*3", "^", "o"]},
      {"name": "Flooded Cellar", "size": [12, 9], "has": ["L", "~*6", "&", "w*2", "h", "x*2"]},
      {"name": "Storeroom", "size": [6, 6], "has": ["L", "b*3", "g", "E"]},
      {"name": "Great Cavern", "size": [16, 14], "has": ["L*3", "g*3", "w*2", "o*2", "h*2", "^", "c*4"]},
      {"name": "Throne", "size": [12, 9], "has": ["L*2", "W", "w*2", "D", "=*2", ">"]}
    ],
    "corridor_traps": 3,
    "secret_passages": 1
  },
  "enemies": {"g": "goblin", "w": "goblin_brute", "W": "goblin_chief"},
  "chests": {
    "C": {"loot": {"iron_ore": [2, 4], "gold": [10, 20]}, "note": "a workbench chest"},
    "K": {"loot": {"gold": [30, 50], "qi_pill": [1, 1]}, "note": "the hidden cache"},
    "D": {"loot": {"gold": [40, 70], "healing_salve": [1, 2]}, "note": "the chief's hoard"},
    "E": {"loot": {"iron_ore": [1, 3], "spirit_herb": [1, 2]}, "note": "a dusty crate"},
    "V": {"loot": {"qi_pill": [1, 2]}, "hidden": true, "note": "only spirit sense shows this one"}
  },
  "inheritances": {
    "I": {"master": "the Example Master", "hidden": true, "needs_realm": 1,
          "text": "What the master's lingering will says to whoever finds them.",
          "grants": {"items": {"breakthrough_pill": 1}, "techniques": ["some_technique_id"], "qi": 200}}
  },
  "exits": {
    "<": {"to": "floor8", "arrive": ">", "label": "Up to Floor 8", "down": false},
    ">": {"to": "floor10", "arrive": "<", "label": "Down to Floor 10"}
  },
  "lore": {
    "A": {"title": "The Gate Inscription", "text": "The story of this place, two or three sentences."},
    "R": {"title": "A Hidden Carving", "text": "What the carving says.", "teaches": "some_technique_id"}
  }
}
```
How the layout works:
- Rooms are joined in the order listed: first room = the way in (put `<`
  there), last room = the boss and the way down (`>`).
- `"secret": true` makes a hidden room behind a secret wall, off the room
  before it. Put the best chest and the lore stone that teaches there.
- `"has"`: map characters placed in that room. `"x*3"` means three of x.
- `"size"`: [width, height], 4-20 each. **10 to 20 rooms, of varying size**
  (Robert, 2026-10-02: "up to 20 rooms -- a good full run for a great
  experience"): small closets, long halls, a big cavern, side branches.
- `"seed"`: any number; change it to get a different arrangement.
- `"secret_passages"`: 0-3 hidden shortcuts between rooms, a secret wall at
  each end (the engine finds where they fit).

### Map characters
FIXED characters -- these already mean something, so NEVER use one as a key
in "enemies", "chests", "exits", "lore", "inheritances" or "riddles":
`.` floor `L` torch `T` trap `S` secret wall `o` ore `h` herb `c` column
`b` barrel `x` rubble `=` banner `~` water `Z` shrine `P` start
`^` glittering vein (gems, gold) `&` fishing spot (water).
Every OTHER letter you put in a room must be defined in exactly one section:
- `"enemies"`: letter -> monster id. Lowercase for regular monsters, a
  capital for the boss: `{"s": "skeleton", "k": "skeleton_knight", "B": "bone_lord"}`
- `"chests"`: letter -> `{"loot": {"item_id": [min, max]}, "note": "..."}`
  (capitals such as C, K, D, V). Loot uses item ids from the list.
- `"exits"`: `<` and `>` -> `{"to": "floorN", "arrive": "<" or ">", "label": "..."}`.
  A floor's `<` goes UP to the floor above, arriving at its `>`, and needs
  `"down": false`; its `>` goes DOWN to the next floor, arriving at its `<`.
- `"lore"`: letter -> `{"title": "...", "text": "what the stone says",
  "teaches": "technique_id" (optional), "needs_realm": 1 (optional)}`
  (capitals such as A, R, Y). A stone with needs_realm can't be read until
  the player has grown enough.
- `"inheritances"`: letter -> a dead master still seated where they died:
  `{"master": "the ... Sage", "text": "what their lingering will says",
  "hidden": true, "needs_realm": 1, "grants": {"items": {"treasure_id": 1},
  "techniques": ["technique_id"], "qi": 300}}` (capital I, J, U). Claimed
  once. Below needs_realm the master turns the player away -- come back later.
- A chest or an inheritance with `"hidden": true` is invisible until the
  player has Spirit Sense: hidden in plain sight.
- `"riddles"`: a carved face that asks something (use `?` as its letter):
  `{"title": "...", "question": "...", "options": ["...", "...", "..."],
  "answer": 1, "reward": {"items": {...}, "qi": 80}}`. A wrong answer
  silences it for a while. Write your own riddle -- one that fits the place.
- Game animals are monsters with `"passive": true` in data/enemies.json
  (`cave_hare` flees, `tunnel_boar` fights back if hurt). Hunting them
  trains Hunting and gives hide and meat. Put a few in quiet rooms.

### What makes a good floor (Robert's vision: depth, discovery, growth)
Plenty to do, not a corridor to rush: 10-20 rooms of varying size (aim
high); 15-30 enemies and a few animals to hunt, plus ONE boss by the stairs
down; 4-8 chests (one in the secret
room); 2-4 traps; 8+ ore and herbs and a glittering vein `^` or two; a torch
in every room; at
least two lore stones -- one that tells the place's story, one hidden that
teaches a technique. Water floors deserve a fishing spot `&`.
Lore is YOURS: write what each stone really says, in the voice of the
place (a dead monk's warning, a miner's prayer) -- never the example's
words. A hint is better than an instruction: "the stone breathes slower
than you" teaches more than "this teaches Mountain Breath".
<!-- dev-brief:end -->

## Techniques -- growth you discover

Techniques are hidden skills (data/techniques.json). Some are read off lore
stones (`"teaches"`), some come from doing things (killing 15 goblins teaches
Wind Step; sitting at the village shrine for two minutes teaches Qi Burst;
asking Little Rin three times teaches Spirit Sense, which makes hidden things
glow). Each floor should hide at least one. Floor techniques waiting for a
stone: `mountain_breath` (floor 2, the crypt), `silver_vein` (floor 3, the
mine), `nanite_resonance` (floor 4, the Sanctum).

## Treasures -- the cultivation-novel kind

Treasures (`"type": "treasure"` in data/items.json) are one of a kind and
work as long as you carry them -- no slot to fill:

| id | name | what it does | where it is |
|---|---|---|---|
| `storage_ring` | Qiankun Ring | pouch holds 99 of each material (20 without it); gold isn't lost when you fall | Trader Wen sells it (600 gold) -- and the fountain knows a cheaper way |
| `spirit_gourd` | Spirit Gourd | key 3: drink, heals 40%; 3 sips, refills at a shrine | Elder Mo's reward for clearing the warrens |
| `flying_sword` | Azure Flying Sword | key G: strikes the nearest enemy within 14 m | the Azure Sword Sage's inheritance, floor 1 (hidden; Qi Condensation) |
| `jade_pendant` | Pendant of Nine Breaths | +25% qi, faster meditation | **for floor 3**: an inheritance (the Drowned Alchemist?) |
| `lotus_seat` | Nanite Lotus Seat | meditate anywhere as if at a shrine | **for floor 4**: the best legacy in the game |

To add a treasure: an entry in data/items.json with `"type": "treasure"`
and an `"effect"` (any technique effect key works: qi_mult, damage_taken,
damage_mult, meditate_mult, loot_mult...). Put it in an inheritance's
`"grants"` or a chest's loot.

## Growth: skills, crafting, the five elements, the journal

Robert: "allow for crafting to be important ... specialize in one or dabble
in all ... intent and items determine the likelihood and quality ... the
better the character is at their skills the more detailed the description."

- **Skills** (`data/skills.json`): mining, herbalism, fishing, hunting
  (gathering) and smithing, alchemy, medicine, jewelcrafting (crafting).
  Level = sqrt(xp / 10) -- no cap, there is always a way forward. Titles:
  Novice, Apprentice (5), Journeyman (10), Expert (20), Master (35),
  Grandmaster (50). Gathering trains its skill and yields more with it.
- **Crafting is a real attempt.** Each recipe in `data/recipes.json` has a
  `"skill"` and a `"difficulty"`. The player chooses how to go about it:
  Carefully (+15% success, no better than Fine), Steadily, or Boldly (-20%,
  the only road to a Masterwork). Success = 70% + 7% per skill level above
  the difficulty (+ Metal affinity). Failure loses half the materials but
  still teaches. Quality: Crude, Common, Fine, Superior, Masterwork (x0.8 to
  x1.6 on damage / HP / healing / qi). A crafted item's id carries its
  quality: `iron_sword@fine`.
- **Item knowledge grows with skill**: an item in `data/items.json` can have
  `"lore": [{"skill": "mining", "level": 2, "text": "..."}]` -- each line
  appears once the player's skill reaches it. Write these for new
  materials: hint at uses, never a manual.
- **The five elements** (Wood, Fire, Earth, Metal, Water) grow from what the
  player does (each skill feeds its elements). Gifts: Fire = strike, Earth =
  body (HP), Water = cultivation (meditation), Wood = gathering, Metal =
  crafting. Wood feeds Fire feeds Earth feeds Metal feeds Water feeds Wood:
  two strong neighbours SYNERGIZE (the second gift x1.4). Water quenches
  Fire, Fire melts Metal, Metal cuts Wood, Wood splits Earth, Earth dams
  Water: two strong rivals held near-equal CLASH (qi gain -12%, the weaker
  gift halved). Doing it all is allowed -- and costs something.
- **The journal** (key N): every item found (where, what it's used for, what
  the player's skills reveal), every place (visits, secrets, lore read),
  skills, elements, synergies and clashes.
- Monsters belong to floors (`"floor"` in `data/enemies.json`). A floor
  that only uses another floor's monsters gets sent back to be richer.

## Gathering, jewelry, scavenger floors

- Plants `h` grow by depth: spirit herb everywhere; ember root (fire) and
  iron thistle (metal) from floor 2; moonpetal (water) from floor 3. Each
  feeds alchemy or medicine (see data/recipes.json).
- `^` glittering veins give gold, jade, silver -- ruby from floor 2,
  sapphire from floor 3. Jewelcrafting turns them into rings and amulets
  (one of each worn; the effect scales with quality).
- `&` fishing spots: cave carp, and for a patient angler glowfin eels.
- **Scavenger's Hollows**: 15% of the time the stairs down open onto a
  generated hollow between two floors -- caves full of nodes, a few of the
  floor's monsters, sometimes a cache -- then on down. Nothing to author;
  the engine draws them from a seed (scripts/world/ScavengeGen.gd).

## Guilds (data/guilds.json)

Adventurers' Lodge and Gatherers' Hall are in the village; the
Blacksmiths' Guild, Alchemists' Circle and Healers' House are waiting for
the settlement on floor 5. Join any, all or none. Standing comes from what
you do (kills and secrets for the Lodge, gathering for the Hall, crafting
for the craft guilds); ranks give real perks; contracts give gold and
standing and come round again when all are done. Rivals (the Circle and the
House) each trust you half as much while you belong to both.

<!-- dev-brief:settlement -->
## Settlement floors (next: floor 5 -- Shellhaven)

Robert: one every 5 floors up to 20, every 10 up to 50, then every 25.
A settlement is `"theme": "settlement"` -- a town deep underground: the same
"layout" of rooms as a dungeon floor, but each room is a district (a gate, a
market, a plaza with a fountain `f` and `P`, an inn, guild halls, a shrine
`Z`, homes with houses `H`, one place nobody talks about). Corridors are drawn
as roads. No monsters (a tame animal or two is fine). It is a rest from the
fighting and the place that outfits you for the next stretch of floors:
- a merchant with its own `"stock"`: the item ids the floors below need
  (`{"role": "merchant", "name": "...", "stock": ["resin_salve", ...]}`)
- a smith and an apothecary (`"role": "alchemist"`)
- an innkeeper (`{"role": "innkeeper", "name": "...", "price": 12, "lines":
  [rumours]}`): a night's rest heals fully, and the town becomes where you
  wake if you fall below
- guild halls: `{"role": "guild", "guild": "blacksmiths", "name": "..."}`
  (blacksmiths, alchemists, healers meet here)
- at least three people with `"lines"` -- rumours, hints about the floors below
- something hidden (a sealed cellar: a `"secret": true` room with a chest)
- `"breathing": true` if the whole place should rise and fall slowly;
  `"ground": "deck"` for a town built on water (plank decks and boardwalks
  over a dark lake, stalls instead of barrels) -- Lanternmere, floor 10.
Reaching a settlement makes it the player's haven (they wake there after
falling instead of in the village).

### A complete settlement example (copy its SHAPE, not its names)

```json
{
  "id": "floor10", "name": "Floor 10, <the town's own name>", "theme": "settlement",
  "depth": 10, "breathing": false,
  "layout": {"seed": 4, "rooms": [
    {"name": "Gate Court", "size": [9, 6], "has": ["<", "L*2", "R"]},
    {"name": "Lantern Market", "size": [14, 8], "has": ["L*3", "M", "b*3", "h"]},
    {"name": "Well Square", "size": [12, 10], "has": ["f", "P", "L*3", "O", "K"]},
    {"name": "The Low Inn", "size": [9, 7], "has": ["I", "L*2", "H", "b*2"]},
    {"name": "Forge Lane", "size": [12, 6], "has": ["F", "B", "L*2", "H*2"]},
    {"name": "Herb Row", "size": [10, 6], "has": ["A", "C", "L*2", "h*3"]},
    {"name": "Guild Steps", "size": [8, 7], "has": ["E", "L*2", "=*2"]},
    {"name": "Quiet Shrine", "size": [7, 6], "has": ["Z", "L*2", "Y", "h*2"]},
    {"name": "Old Cellar", "size": [6, 5], "secret": true, "has": ["L", "D"]},
    {"name": "Down Stair", "size": [8, 6], "has": [">", "L*2", "W"]}]},
  "npcs": {
    "M": {"role": "merchant", "name": "Trader Osk", "stock": ["resin_salve", "qi_pill"],
          "line": "what they say first", "persona": "who they are, what they want"},
    "I": {"role": "innkeeper", "name": "Innkeeper Bel", "price": 12,
          "lines": ["a rumour about the floor below", "another rumour"]},
    "F": {"role": "smith", "name": "Smith Garro"},
    "A": {"role": "alchemist", "name": "Herbwife Ama"},
    "B": {"role": "guild", "guild": "blacksmiths", "name": "Hall-master Tey"},
    "C": {"role": "guild", "guild": "alchemists", "name": "Sister Wen"},
    "E": {"role": "guild", "guild": "healers", "name": "Brother Cael"},
    "O": {"role": "villager", "name": "Old Hobb", "lines": ["...", "..."],
          "persona": "someone who could travel with you"},
    "K": {"role": "villager", "name": "Little Pim", "lines": ["..."], "persona": "..."},
    "W": {"role": "villager", "name": "Watchman Dov", "lines": ["..."], "persona": "..."}},
  "chests": {"D": {"loot": {"gold": [40, 80]}, "note": "what the chest IS, in this town"}},
  "lore": {"R": {"title": "<its own title>", "text": "how the town came to be -- a few full sentences"},
           "Y": {"title": "<its own title>", "text": "a prayer, a warning, a boast"}},
  "exits": {"<": {"to": "floor9", "arrive": ">", "label": "Up to Floor 9", "down": false},
            ">": {"to": "floor11", "arrive": "<", "label": "Down to Floor 11"}}
}
```
Every district is a real room (6x5 or bigger), each with its own purpose.
NO "enemies" section (a town is safe ground), no boss. The people are the
point: give each of them a name of their own, a "line" or "lines", and the
ones who could come along with you a "persona".
<!-- /dev-brief:settlement -->

### Shellhaven, floor 5 -- on the back of the Sleeping Tortoise

Below the Nanite Sanctum the stairs come out on a cavern so big its roof is
lost in the dark, and in the middle of it a hill that breathes: an ancient
spirit tortoise, asleep for longer than there have been sects, and a town
built on its shell. Moss on the plates, glowing mushrooms, lanterns on poles,
houses wedged into the seams between scales, steam rising from the vents
where it breathes out. Its people are those who came down and didn't go back
up: miners, exiled alchemists, smiths who wanted a hotter forge, a few who
say the tortoise talks to them in their sleep. `"breathing": true`.
Stock for floors 6-9: `resin_salve`, `shell_tea`, `verdant_pill`,
`magma_pill`, `moonpetal_tonic`, `qi_pill`, `breakthrough_pill`,
`barkskin_mail`. Guild halls: blacksmiths, alchemists, healers. The
`tortoise_scale` treasure is the town's secret -- for whoever earns it
(hidden in plain sight: the tortoise sheds, and someone keeps the scales).

## Companions and partners

Talk to people (the free chat) and they come to know you -- warmth moves
with what you say, and with chance. Someone who counts you as a close friend
may agree to travel with you if you ask (their choice: warmth tilts it,
chance decides it; a "not now" can be asked again later). A companion walks
beside you from floor to floor, fights the monsters nearest you (never the
wild animals), talks in their own words, and the road warms the bond on its
own. Someone devoted who travels with you may agree to be your partner:
you cultivate better side by side. Villagers can travel; people with a post
(merchant, smith, apothecary, guild hall, elder, innkeeper) keep it. In a
level file, `"can_travel": true` lets someone with a post come along, and
`"stays": true` keeps a villager home. Give the people who can travel a
`"persona"` -- who they are, what they want, what they're afraid of -- so
they have something to say on the road.

## Weapons -- dropped, found, made

Every weapon has a `"kind"`: sword (balanced), dagger (fast, short), saber
(quick cuts), spear (long reach), axe (heavy), hammer (slow, crushing),
halberd (slow, long, brutal), staff (qi flows through it), fists (a flurry).
The kind sets its speed and reach; an item can override with `"speed"`,
`"reach"`, and carry an `"effect"` that counts while it's in your hand.
Gear with `"drop": true` and a `"tier"` (its floor) can drop from that
floor's monsters -- a boss always leaves something, a big monster now and
then, an ordinary one rarely -- with a quality roll (Crude to Masterwork).
A chest can hold `"random_gear"`, `"random_weapon"` or `"random_armor"`:
`[min, max]` pieces rolled for its floor. Every kind can also be made at
a smith. Found gear isn't "made" -- only what you craft counts for the
Academy's Trial of Craft.

## Why get stronger: the Academy and the tournaments

**The Lotus Ascent Academy** (`"role": "academy"` NPCs -- the examiner at
Shellhaven, a proctor in every settlement after): reach Qi Condensation and
take the entrance exam -- the Trial of Strength (three waves in the arena),
the Trial of Knowledge (five questions about the elements, the realms, what
things are for; four right to pass), the Trial of Craft (something you made
yourself, Fine or better). Pass all three and you're an Outer Disciple.
Each rank above needs standing, a realm AND a rank trial in the arena; merit
(earned with standing) buys techniques from the Academy library. Its tasks
are field studies on the floors below.

**Tournaments** (`"role": "tournament"`, optional `"tier"`): every settlement
holds one. Three bouts -- quarterfinal, semifinal, final -- against rival
cultivators from the other sects (Lu Feng of the Iron Pine Sect, Mei Ruolan
of the Crimson Lantern Pavilion, ...). Rivals remember you: every meeting
makes them stronger, and the final is always against whoever you've crossed
most. Win: gold, a piece from the champions' rack, Academy standing, a title.
Lose: carried out of the ring -- no gold lost. A new bracket every 20 minutes.

## The floor forge -- floors that keep coming (from floor 11 on)

Robert: "continue building floors until I say otherwise". HomeAI's
`godot_forge.py` builds the next floor whenever it's switched on (say "keep
building floors" / "stop building floors" to Dev). The box lays out each
floor from `data/forge_regions.json` (14 dungeon regions, 6 settlement
themes -- add one there and the forge uses it): rooms with purposes, the
region's monsters, materials, gear and pill, a technique hidden in a secret
room, chests, a riddle, an inheritance every third floor. Dev writes the
words (lore, riddle, chest notes, what townsfolk say); anything that fails
the checks falls back to the region's own words. Settlements: every 5
floors to 20, every 10 to 50, then every 25 -- each with a stocked merchant
(remedies and elixirs for the stretch below, the last stretch's pills and
gear), an inn, a forge, an apothecary, guild halls, a tournament, the
Academy. After floor 20 each floor grows 25% (of floor 20's) every 5
floors. A region that comes round again comes back deeper -- "the Deep
...", "the Ancient ..." -- with stronger monsters and a stronger technique.

**Build to 25, then refine** (Robert, 2026-10-02: "build up to 25; once
they reach it begin to refine, expand and enrich what we have. This game
should be robust."). New floors stop at the forge's `max_floor` (25 unless
Robert raises it). After that every tick is one refine pass on the next
floor that has room to grow, cycling 1 -> 25: a dungeon floor gets one
more side room (light, something to gather, its own monsters, a small
chest; at most 3 per floor, always just before the boss room), a
settlement one more townsperson (at most 3), and a lore stone whose words
are copied on another floor gets fresh ones from Dev. The level file
records it under `"refined"` (and each added room/person carries
`"added": "refine"`). Same gate as a new floor: level rules, the engine in
a sandbox, live with a backup in `.backups/forge-refine-floorN-*`,
re-checked, rolled back on failure. When nothing is left to grow the forge
rests and says so. Hand-drawn floors (no "layout") are left alone.

## Who you were, and what you're good at (round 13)

Robert: "No one is proficient with anything from the start except one
skill plus hand to hand combat and survival. More focus in a task could be
more rewarding."
- A new game asks **who you were** (`Game.BACKGROUNDS`, 13 of them: crafts,
  gathering, weapons). You start an Apprentice (level 5) at Unarmed,
  Survival and the ONE skill your background gave you, with its kit.
  Everything else starts at nothing. Older saves are asked once and never
  lose anything (their fighting hand remembers their kills).
- **Every weapon kind is its own skill** (skill ids "sword" (Swordplay), "dagger",
  "saber", "spear", "axe", "hammer", "halberd" (Polearm), "staff",
  "unarmed" for bare hands and fist wraps). Untrained = x0.65 damage and a
  slower swing; Apprentice = x1.0; +2% a level after that. Every landed
  blow and every kill trains the weapon in your hand. Auto-equip compares
  what a weapon does IN YOUR HANDS, so an untrained sword won't push out a
  trained spear.
- **Survival**: traps bite less, salves heal more, wounds close on their
  own between fights; it grows from new floors, traps, falling, dressing
  wounds.
- **Focus**: staying with one skill builds focus (half-life 10 minutes of
  play): up to +50% skill growth, and for crafts and gathering steadier,
  finer work and more yield. The journal shows it.

## Moments: anything you can describe (T)

Robert: "Allow for character free text moments for out of the norm play
but it needs reciprocating." Press **T** anywhere and say what you try.
`scripts/fx/Moment.gd` asks the box's model to judge it (skills, realm, where
you are, who's near, what you carry) and propose JSON effects;
`Game.apply_moment` sets how much: gold, HP, qi, items (consumables and
materials for this depth only -- never gear or treasures), skill xp (real
skills only), bonds (people actually present), affinity -- all capped by
depth. **Reciprocity**: anything short of a clean success that only gives
also takes; a failure costs something and always teaches; the same trick
over and over wears thin; a moment never kills you. One moment every 3
minutes; the world remembers the last 12 (saved). With the model down, a
plain reading of the words (cook, forage, train, steal, sing, help...)
stands in.

## Contribution, guild stores, and pieces made for you

Robert: "Use sect and guild contribution points for special items. Allow
AI to tailor items to the user's gameplay or allow them to request up to 3
items." 
- Every guild pays **contribution** alongside standing (standing never
  goes down; contribution is spent). The Academy's is **merit**. Donating
  materials to a guild earns both.
- Each guild (and the Academy) has **stores** (`"specials"` in
  data/guilds.json): rank-gated special items bought with contribution --
  rations and draughts anyone can take again, and one-of-a-kind treasures
  (Vanguard's Token, Forager's Gloves, Master's Tongs, Lotus Seal...).
- **A tailored piece** (`"tailor_cost"`): the guild's maker reads how you
  play (`Game.play_profile`: fighter / crafter / gatherer / cultivator,
  favourite weapon, best craft, element) and designs for it (Superior).
- **Wishes**: a settlement's smith makes 3 pieces you describe in your own
  words (per settlement -- the next town has its own 3), for a gold fee;
  chance sets the quality and strength.
- The model only ever designs (name, look, kind, which gift --
  `scripts/objects/Artisan.gd`); `Game.finalize_design` sets every number from the
  depth you've reached, on the same lines as the forge's own gear.
  Made-for-you items are saved in your save (`custom_items`), never in
  data/.

## How places look (round 14: texture and detail)

Robert: "can we begin to add more texture and detail to the world" -- he
chose real surfaces AND per-region props/particles/light, plus
environmental storytelling, ambient life and town life.
- `scripts/world/Look.gd` holds a LOOK for every region: floor and wall surface
  (CC0 photo-scanned stone/earth/moss from Poly Haven in
  `assets/textures/<name>/albedo.jpg + normal.jpg`, read straight from the
  file -- the folder has a .gdignore, no import step), a tint, clutter along
  the walls, drifting motes, torch colour, glow features, critters and the
  kinds of little scenes. A floor picks its look by `"look"` in its file,
  else its forge region, else words in its name. **New forge region? Add a
  look with the same key** (or it falls back to the warrens).
- Floors, roads and walls are now ONE textured mesh each per level (built
  in `Level._build_surfaces`), with darker corners where floor meets wall
  -- far fewer nodes than a model per tile. Collision is unchanged.
- `scripts/fx/Motes.gd`: dust, embers, spores, leaves, drips, sparks, snow,
  glints, ash around you; smoke from town chimneys. Looks only.
- `scripts/fx/Vignette.gd` + `data/vignettes.json`: little scenes on dungeon
  floors -- a cold camp, someone who didn't make it, a small shrine, the
  aftermath of a fight, someone's stash. E to look closer: words from the
  region's own lines first; the first look sometimes finds something small
  and always gives a little Survival. **Dev: add lines to vignettes.json**
  (from inside the world, never about the game).
- `scripts/actors/Critter.gd`: rats that bolt, bats circling high, moths around
  the light, cats in towns, birds in the village that take off when you
  walk up. No collision, nothing in play depends on them.
- Town life: villagers wander a few steps around home (traders keep their
  posts; `"wander": false` pins anyone), stop and look at you when you come
  close, stay nearer home at night. The village keeps your real clock
  (`Game.daylight()`): morning, a gold dusk, a blue night with every lantern
  lit. Chimneys smoke; merchants get a stall in open ground.

## Lost workshops and the masters on the upper floors (round 15)

Robert: "maybe throw in lost remnants of smiths, labs from alchemy etc. as
well as the inheritances that can be found in the upper levels."
- Five more scene kinds (Vignette.gd): a lost forge (`smithy`), an
  abandoned laboratory (`alchemy_lab`), a healer's lost rooms
  (`apothecary`), a jeweller's bench (`jeweler`), a hidden garden
  (`herb_garden`). Every dungeon floor has one, chosen by its look
  (`Level.WORKSHOP_FOR`). The first look teaches that craft a little and
  leaves something of its trade (ore, a pill, salves, jade, herbs).
- On floors 1-10 the workshop's MASTER still sits at the work -- a craft
  inheritance: their craft's technique (Forge Sense, Furnace Heart,
  Healer's Touch, Jeweller's Mind, Verdant Eye), their best work (a
  masterwork weapon of the floor, Superior pills/salves, a Superior jade
  ring, seed and herbs), qi, and a lifetime of practice. They only pass it
  to someone who has started down that road (the craft at level 2+);
  everyone else is turned away, kindly. Once per floor, ever
  (`legacy:<floor>` flag -- it survives the forge redrawing the floor).
- Words: `data/vignettes.json` -> "kinds" (the workshops) and "legacies"
  (masters' names, what they say, which technique).

## What people wear (round 15)

Robert: "i want the characters to have more detail as well." `scripts/world/Dress.gd`
dresses the Kenney figures from simple shapes pinned to their bones (they
move with every animation): hair and topknots, straw hats, scholar caps, a
crown for the Academy, beards, robes, sashes, aprons, capes, shoulder
guards. Townsfolk dress for their trade (`Dress.ROLE_LOOK`; villagers get
plain clothes, the same every time for the same name; a level file may add
`"dress": {...}` to any NPC). You wear a robe in the colour of your
strongest element (the Academy's white once you're a disciple), and the
weapon you're holding is in your hand. Rivals wear their sect's colour and
carry their own weapon; monsters get glowing eyes, tusks, a belt, spiked
shoulders on the big ones and a crown of horns on a boss.
`tools/dress_preview.gd` renders a lineup to check them by eye.

## Cultivation: the Meridian Lattice and the ki arts (round 19)

Robert, 2026-10-02: characters develop everything "with practice and
meditation and through use ... maybe found in a skill tree"; progress must
feel worked for but achievable; "fighting can increase ki with every kill
but meditation should not be quick without aids or special skills". The
full design is the Claude Doc "Cultivation x Nanites: the design"; rounds
2-4 (heat and guard arts, breakthroughs with the heart demon, sects and
towers) come next.

- **The lattice** (`data/lattice.json`, `Game.lattice*`, K shows it -
  `scripts/ui/LatticeView.gd`): 36 real acupoints, 6 rings (ring n opens at
  realm n-1), 3 meridians: strike (arms), guard (spine/chest), step
  (legs). Pick a focus point; meditating opens it (`open_seconds` per ring,
  times the meditation aids). Each open point: +2% strike damage / -3%
  damage taken / +2% speed (ring 6 double), +5 affinity in its element.
- **Arts** (`lattice.json` "arts": family + route): an art works once
  its route is open (`Game.art_blocked`). Using it earns practice
  (`Game.practice`, x3 when it lands) and tugs 3 s at its meridian's next
  sealed point. Practice is UNSETTLED until meditation (`settle_practice`)
  or a night at home / time away (`settle_all`) makes it mastery. Stages:
  Practiced 0 / Fluent 150 / Mastered 600 / Transcendent 2000 - power
  0.85 / 1.0 / 1.12 / 1.3, cooldown x1 / 1 / 0.8 / 0.7. Unsettled practice
  caps at twice what the next stage needs. To add an art: a technique
  (`kind: active`) plus an "arts" entry with its route.
- **Pacing** (`Game.meditate_tick`): plain meditation 0.25 qi/s, halved
  after 5 minutes in one sitting; aids multiply (shrine x2, Lotus Seat,
  `meditate_mult` techniques). Kills give 1.5x their qi (`KILL_QI_MULT`).
  Time away: 15 qi/h floor, 4% of a step an hour, meditating x2.


## Heat, the guard, glimpses, branches, bridges (round 20)

Robert asked for "the best combination" that keeps the game playable and
neither too easy nor too hard. Everything below is in Game.gd's round-20
block, with its numbers in data/lattice.json (`heat`, `guard`, `arts`,
`branches`, `items`, `recipes`):

- **Nanite heat.** Every art adds heat (`arts.<id>.heat`). Above 70% you run
  HOT and arts hit 15% harder. Pushing past the cap causes a BACKLASH: you
  lose 10% of max life, heat drops to 60%, and that art's meridian is
  injured for 90 s. Injured arts cost double heat and the meridian's point
  bonuses switch off. Sitting mends an injury four times faster, a salve
  takes 20 s off, and a night in your own bed mends it fully. Heat vents
  on its own: 8/s when calm, 2.5/s in a fight, 20/s while sitting. Water
  and earth affinity make arts run cooler; fire makes them hotter. The cap
  is 100, plus 15 for every complete ring.
- **Guard** (right mouse or B). A blow from the front lets half through
  (`Game.guard_take`); from behind, three quarters. A blow inside the parry
  window (0.2 s after raising the guard) is PARRIED: no damage, the
  attacker staggers (bosses for half as long), and 25 heat vents. Each
  blocked blow adds 4 heat, so holding the guard heats you while parrying
  keeps you cool. Guard arts change these numbers: Iron Shell is the tank
  option, Returning Tide the parry option.
- **Keys.** F fires the wired strike art and V the wired step art; X cycles
  strike arts. Wire any art from the K panel.
- **Glimpses.** New arts are never bought. Each grows from doing the thing
  (`arts.<id>.glimpse`: art_kill / boss / dodge / air_hit / block / parry),
  and most also need the art before it at a set stage (`requires`), so
  this is the skill tree. K shows the progress.
- **Branches.** Once an art is Fluent you choose one of its two elements
  (`branches`), once and for good. The text for each choice is in
  lattice.json `branches.<family>.<element>`.
- **Nanite bridges.** A boss's first fall leaves one. Wired across a sealed
  point (up to two rings beyond your realm), it lets an art run at 1.5x
  heat. You can hold one bridge plus one per complete ring, and it comes
  back when the point opens.
- **Aids.** Meditation multipliers above 3x count at 3 x sqrt(m/3). Calming
  Incense (sold by Trader Wen, or made with alchemy) gives 1.5x for 10 min
  of sitting.
- **Training post** (home). Arts used near it count as practice worth 2,
  between a miss (1) and a hit (3). It allows 30 minutes a day, and each
  use spends its cooldown in seconds from that budget.
- **Forge data.** New techniques, items and recipes live in lattice.json
  and are merged in at startup only where the forge has nothing with that
  id (`_merge_lattice_defs`), so the forge's own files are never touched.


## The nanite swarm: its own road (round 21)

Robert: nanites and cultivation should be "separate and synergistic ...
rise separately through their own unique uses", plus "experimentation for
growth, or finding secrets ... a faster or more diverse path".

- **Separate roads.** Cultivation (qi, realms, the lattice) grows by
  sitting and killing. The swarm (`Game.integration`, with tiers in
  data/nanites.json) grows only by use, never by sitting:
  - heat run through arts: heat x0.25, doubled when hot
  - blocks (+1), parries (+3), backlashes (+15)
  - absorbing nanite shards (40) or a warden core (400)
  - bench recipes that use shards (+10 per shard)
  - experiments (+10)
  `nanite_label()` now returns the swarm tier, not your realm.
- **Synergy.**
  - Every open lattice point gives +1.5% integration.
  - Every swarm tier gives +4% point opening, +12 heat cap, +8% vent and
    +1.5% max HP.
  - With realm and tier within one of each other (both at least 1) you are
    in HARMONY: +10% qi and +10% integration.
  - Three or more apart, the roads STRAIN. If the swarm is ahead, arts run
    1.2x hotter; if qi is ahead, the heat cap is x0.85.
- **Augments** (`augments` in nanites.json) are found by EXPERIMENTING at
  the home workbench: one shard plus one reagent. The right reagent teaches
  an augment, and a reagent of the same element as an undiscovered one
  says "something fire is close". Each runs in a slot: 1/2/3/4 slots at
  tiers 1/3/5/8, managed on K.
- **Discoveries** (`discoveries` in nanites.json) are hidden ways of doing
  things, found by trying them, and each gives a lasting edge:
  - Furnace Sitting: sit while hot.
  - Moonwater Breath: sit near water at night.
  - Edge Running: hold above 85% heat in a fight for 15 s.
  - Perfect Rhythm: three parries in 6 s.
  - Shard Communion: absorb a shard while sitting.
  - Still Mind: sit for 10 minutes.
  Townsfolk answer "Heard anything strange?" with rumours of the ones you
  haven't found.
- **Old saves** start the swarm at the tier their realm used to name
  (`_grandfather_swarm`).


## Training by asking; chat and trade screens (round 22)

- **Lessons** (data/training.json). Each townsperson teaches one lesson,
  picked by role and name: strike, step or guard drill, breath, weapon or
  swarm. It isn't listed anywhere. Ask about training in chat (the words in
  `words`) and three things happen: their voice is told the pitch so they
  offer it in their own words, a Train chip appears in the chat, and the
  lesson becomes a button in their menu. Each person teaches once a day,
  for 15 gold plus 20 per realm (x0.75 for friends).
  - Drills give +12 practice to the wired art and a glimpse of the next art.
  - Breath gives 1.4x meditation for 15 min and pushes your focus point.
  - Weapon gives weapon skill XP.
  - Swarm gives +30 integration and a rumour.
- **Chat** (HUD) is a RichTextLabel: you in blue, them in gold, notes in
  grey. It shows a "thinking..." line and quick chips: training, rumours,
  "tell me about yourself" and Trade. Tests read it with `hud.chat_text()`.
- **Trade** (`HUD.open_trade`) puts their goods and yours side by side.
  Buy 1 or 5, sell 1 or all, and the window refreshes in place.
  `Game.sell_price` pays full value for materials and half for gear and
  consumables, and never buys what you're wearing.
- One HUD theme styles every button, field, scrollbar and tooltip
  (`_ui_theme`). Movement now ramps up over about 0.08 s.


## Every floor wider: side chambers and wonders (round 23)

Robert: "make each floor more expansive and immersive -- more things to do
and explore and find."

- **Expanse.gd** runs when a dungeon floor is BUILT, never on your file.
  It carves 3-6 side chambers into the empty rock between your rooms, each
  joined to the nearest room by a passage. One chamber per floor sits
  behind a secret wall (S).
  - Your map is only ever added to, never moved. It grows right and down
    when it needs room.
  - It's deterministic: the seed is the floor id plus its floor-cell
    count.
  - It skips towns, arenas, and any def with `"no_expand": true`.
  - The built def carries `extras` (kind, cell, index).
- **Wonder.gd** is the thing in each chamber:
  - relic: draw the swarm out, giving integration and shards; once.
  - hermitage: sit for 1.5x meditation via `Game.sit_aid`.
  - echo: a glimpse of an art you haven't found; once.
  - cache: dig for gold, the floor's materials, sometimes incense or a
    bridge; Spirit Sense shows it; once.
  - grotto: a pool with a fishing spot (Moonwater Breath).
  - lair: three of the floor's foes guard a cache.
  - trial: an altar that raises foes; beat them in 90 s for gold, qi,
    swarm and a glimpse; once a day.
- **Your part.** You can make chambers less necessary by giving a floor
  its own side areas. Expanse only uses rock that's still empty, and the
  wonders take their text and loot from your floor's foes.


## The valley: sects and towers (round 24)

Robert: "towers to climb and sects outside of the dungeon -- the dungeon is
the primary way to progress but not the only way." He chose one open
region.

- **Your writing goes in.** Your drafts (data/drafts/) are built into the
  game by `python3 tools/integrate_drafts.py`, which writes
  data/valley.json:
  - It keeps what's already integrated and adds new sects, up to six. Each
    keeps its slot (its seat in the valley).
  - Your towers fill tower slots first; Claude's fill only the slots you
    haven't written yet.
  - Each sect art becomes a real art on an engine template. The template is
    picked from YOUR description ("shockwave" makes a burst, "reflect" makes
    a returning guard...), falling back to the sect's element, and the art
    carries the sect's element from the start.
- **The valley is drawn when it's entered.** `Valley.gd` (`Game.load_level_def("valley")`)
  builds it from valley.json and adds no file to levels/:
  - the road out of Eliet (the village gets a gate at runtime:
    `Level.valley_gate_cell`)
  - a river with bridges, roads, woods
  - three zones of creatures (floors 1-2, 2-6, 6-9)
  - six sect seats (stone-walled yards with a hall)
  - three towers
  - wonders
- **Sects** (`Game.sect`, `SectHall.gd`, NPC role "sect"):
  - The elder tells the creed, the nanite way and the rival, and runs the
    entry trial at the hall: combat, endurance or stillness, by element.
  - Ranks: Outer (0), Inner (100 contribution and Qi Condensation), Core
    (300 and Foundation), Elder's Disciple (800 and Core Formation). Each of
    the first three ranks teaches one of the sect's arts.
  - Contribution comes from every kill, tower floors (+10) and donated
    materials of the sect's element (a fifth of their worth).
  - The hall seats a disciple at 2.5x and a guest at 1.25x.
  - One sect at a time. Leaving keeps your arts, and you can't join another
    the same day.
- **Towers** (`TowerGen.gd`, `TowerTrial.gd`, `TowerSpire.gd`). Level id
  `tower:<id>:<1-9>`.
  - Floor kinds:
    - combat
    - endurance: 40 s + 4 per floor
    - puzzle: five element pillars in the order of creation, or of
      overcoming from floor 6
    - insight: an Academy question
  - Floor 9 always has the guardian.
  - The towers open at Body Tempering, Foundation and Nascent Soul.
  - Each floor pays the first time. The summit gives a title, a nanite
    bridge and a large swarm gain.


## The breakthrough: comprehension and the heart demon (round 25)

- **The steps inside a realm** still fill with qi. At step 10 the qi stops
  at the brim (`Game.at_threshold`).
- **Crossing into the next realm** takes three things (`breakthrough_missing`):
  - insight (`INSIGHT_NEED`: 10, 25, 50, 90, 150...)
  - every point of the current lattice ring open
  - a won tribulation
- **Insight** comes from doing new things. `log_event` calls
  `_insight_from_event` (`INSIGHT_FOR`):
  - a first visit to a place: +2
  - a lore stone: +1
  - an art reaching Fluent / Mastered / Transcendent: +3 / +5 / +8
  - a lesson: +1
  - a discovery: +3
  - a tower floor: +1; a summit: +5
  - a sect rank: +3
  - a riddle: +2
  - an inheritance: +3
  - an augment: +2
  - an art learned from glimpses: +2

  So more places, more lore and more stones give a faster road.
- **The tribulation.** Sit (M) at the threshold and the game offers it
  (`Player._offer_tribulation`). Level `tribulation:<realm>` is a round,
  empty room with your heart demon (`HeartDemon.gd`, stats from
  `heart_demon_def`).
  - It fights normally and, every few seconds after a 0.8 s warning ring,
    uses YOUR favourite family (`favored_family`):
    - strike: a burst
    - step: it appears behind you
    - guard: two seconds of 70% glancing off and 20% reflected
  - Win (`tribulation_won`): the realm rises, Dao Heart +2% (+1% after a
    first loss) to qi, damage and life, the title "Heart Unshaken", and
    you're back where you sat.
  - Lose (`tribulation_lost`): no death penalty. A meridian is injured for
    5 min and there's an hour's wait. Your qi stays full.
- **Older saves** get insight for what they've already done, and never less
  than the previous realm's need (`_grandfather_insight`).

## Dev's landmarks, codex and rumours (round 26)

The last three writing-room briefs go into the game the same way the
sects and towers do: Dev's drafts -> `tools/integrate_drafts.py` ->
`data/valley.json` (keys `landmarks`, `codex`, `rumours`). Until Dev has
written them the keys are empty and the game simply has none.

- **Landmarks** (brief `landmarks`, 12): `name`, `kind`, `where`, `sight`,
  `secret`. `Valley.gd` places each one out in the open wilds (well apart,
  clear ground around it, a pond for a lake) and `Landmark.gd` builds it
  from props by kind (ruin, shrine, hamlet, camp, grove, cave, lake, peak,
  bridge, battlefield, workshop, tomb) with its name over it.
  - E: look -- Dev's `where` and `sight`. First visit: insight +2, and the
    place goes in the journal ("The valley").
  - "Search the place" (once): Dev's `secret`, insight +2, and a find by
    kind -- shrine: ten minutes of deeper sitting and swarm integration;
    ruin/tomb/bridge: a glimpse of an art and gold; camp/hamlet/workshop:
    gold and supplies; grove/lake: wood/water affinity and herbs; cave/peak:
    qi and jade; battlefield: a piece of gear.
  - A shrine can be sat at (x1.5).
- **The nanite codex** (brief `nanite_codex`, 12): `name`, `realm`, `text`.
  Journal (N) -> "The nanite codex". An entry opens when you reach its
  realm; reading a new one gives insight +1 (`Game.read_codex`).
- **Rumours** (brief `rumours`, 5 subjects x 5 lines): mixed into what
  townsfolk say (`Game.rumour`).
- Keep the words in the briefs' lengths; integrate refuses a draft that
  breaks them, and the old valley.json stays.

## The world: time and seasons, peoples, camps in the deep, ruins of the old age (round 44)

Robert, 2026-10-04: "bring more depth to the world" -- peoples in the deep, factions that
remember, time and seasons, ruins and the old age -- "there needs to be a sense of continuity
in the world, so give the visual game aspects more to work with."

Four new modular systems (scripts/systems/, each with its own data file) and what you SEE:

- **World.gd** (data/world.json). The calendar runs on the real date: a season is 5 real days,
  a year is four seasons (Thaw, Blaze, Harvest, Frost), so the world keeps turning while the
  player is away. The hour is the real clock: night, dawn, day, dusk. Weather is rolled for
  each quarter of a day, per place: rain, storm, fog, snow, heat, leaf-fall wind over Eliet;
  qi mist, spore drift, ash fall, cold seep, tremor, dripping dark below (some only on the
  floors they fit). The third day of each season is a festival in Eliet (discount + the
  elder's gift). Every one has an effect (same keys as techniques) and foe_* effects on the
  monsters (night: harder hits, more elites, better loot). WorldFX.gd keeps the look in step:
  the sun moves and sets while you play, clouds and fog follow the weather, rain/snow/mist/
  leaves/ash fall, Frost lays snow, Thaw grows flowers, Harvest turns the trees, festival
  lanterns line Eliet's roads; underground the light dims at night.
- **Factions.gd** (data/factions.json). Five peoples -- the Village of Eliet, the Deepfolk,
  the Hollow Clans, the Heirs of the Makers, the Valley Sects -- with standing from -1000 to
  1000 in tiers (Hated .. Revered). Rivals: Deepfolk vs Hollow Clans, Heirs vs Sects -- help
  one and the other cools. Standing comes from things the player already does (the play log:
  quests, sect trials, research, camps helped, relics given). It sets their traders' prices
  (Hostile: no trade), adds stock, gives gifts (free inn, faster research/bonds/sitting), and
  a Hollow Clans that hates you sends hunters onto the floors.
- **Settlements.gd** + Settlement.gd (data/settlements.json). Nine camps on dungeon floors
  (3, 8, 12, 17, 23, 28, 33, 38, 44), placed at runtime in an open hall (Level.open_spot) --
  no level files touched. Each grows camp -> outpost -> haven -> town as you meet its one need
  a day (bring items, or kill N on that floor) or give supplies. Each stage adds people and
  things you can see (tents, fence, stalls, lanterns, a shrine, an inn, your bronze statue).
  Neglect slips it back toward the start of its stage, never below. The headman says what
  happened while you were away.
- **Ruins.gd** + DigSite.gd (data/ruins.json). A dig site on every dungeon floor from 4 down,
  always the same jade stones with lines of light. Three layers to dig (Archaeology skill;
  sometimes you wake something). At the bottom a relic -- 24 relics in four ages, deeper is
  older: the First Breath, the Lattice Age, the Sundering, the Long Quiet. Each relic is a
  line in the Old Age timeline. All of an age = its technique, and its glyphs become readable
  on every ruin. Relics can go to the Heirs or the Sects (standing, and the rival resents it).
- The menu has a **World** page: the day and what it does, the peoples, the camps, the Old Age.
- GameSystem has a new hook, on_event(kind, data): every system hears every play-log event.

Your words (writing room briefs): world_seasons, world_weather, festivals, factions,
settlements, ruins -- drafts in data/drafts/<id>.json as {"items": [{"id", "text"}]}, used
entry by entry. The relics' texts are one history: keep every fact, they fit together, and
they agree with the history fragments (the Heart, the ladder, the first expedition).

## Rounds 59-62: sound you'd leave on, combat you can read, one more floor, a first hour that hooks

Robert, 2026-10-05: "keep working on increasing the quality of the game to the standard we are trying to release -- more enjoyable, immersive and compulsive." He picked all four, and "make sure you are utilizing Dev". He has said he almost always turns music and sound off because they get boring.

### Round 59: sound (scripts/core/Audio.gd, data/audio.json, tools/music_gen2.py)

- **Music is pieces, not loops.** There are 19 in `assets/audio/music2/`, each 2-3 minutes with an intro, a theme (A) that comes back changed, a middle (B) and a real ending. All are generated from a motif, with sets per place:
  - the village by day (3) and by night (2)
  - the valley (3)
  - the dungeon, floors 1-9 (3)
  - the deep, 10-29 (3)
  - the abyss, 30-50 (2), with a cold synth under the old instruments
  - a town underground (2)
  - the title (1)
- **Pacing:** after a piece comes a quiet stretch (Sound -> "Music between quiet stretches": often 15-40 s, now and then 60-150 s, rarely 3-7 min). The next piece is never the one just heard. Arriving somewhere starts its music after 2-6 s.
- **Now playing:** a piece's name shows for a moment in a corner. Dev names them (brief `music_titles`); ours are used until then.
- **Ambience** is always on (16 seamless beds in `assets/audio/ambience/`, mapped by a floor's look):
  - cave, crypt, deep, water, arcane, forest_under, fire, storm, frost, machine (clockwork, star-mines), silk, town
  - village/valley by day and by night
  - A reach switches to its land's own bed while you're in it (ReachZone -> Audio.set_reach_look).
- **Fight drums:** when a foe is chasing you within 22 m, a drum loop comes up (6 loops: dungeon, deep, boss) and the music steps back to 25%. The drums go 5 s after the last chaser. They can be turned off.
- **Sound window (Menu -> Sound...):**
  - music, ambience and effects volumes (0-10 each)
  - how often music plays
  - fight drums on/off
  - music style: new pieces, or "classic" (the round-31 loops, kept as the backup)
- **Effects:**
  - Every sound varies a little in pitch and loudness.
  - Five takes of hits, swings and hurts, and six of steps.
  - `dig` existed in code but had no file; it has one now.
  - New sounds for later rounds: windup, loot_rare, loot_epic, floor_clear.
- **The director runs headless too**, so the tests check what it would play.

### Round 60: combat you can read (Enemy.gd, Player.gd, scripts/fx/Blast.gd; data/combat.json, data/foes.json)

- **Heavy blows:** every 3-5 swings, a brawler, guardian, skulker, swarmer or charger winds up a HEAVY blow (×1.8). From floor 2 on any of them can; on floor 1 only elites and masters.
  - **The tell:** it rears up, a red ring grows, and the wind-up sound plays.
  - **A guard can't hold it** ("GUARD BROKEN").
  - **A parry** staggers it 1.6× as long and leaves it OPEN.
  - **Rolling through it as it lands** is a PERFECT dodge: the world slows for 0.4 s and it's wide open.
  - **Stepping out of reach** makes it swing at air, and it's open.
  - **Staggering it mid-wind-up** stops the blow (INTERRUPTED).
  - **OPEN** means +50% damage taken for about 1.6 s, and it can't strike back meanwhile.
- **Masters' big moves:** every 7-10 s (faster when enraged), shown on the ground first as a disc that fills.
  - **Slam:** the disc grows under you, then it leaps there.
  - **Sweep:** a wide disc round it, then it spins.
  - Both are Blast.gd nodes, and both are heavy: no guard holds them, a perfect dodge opens the master up, and a parry staggers it.
- **New elite affixes:**
  - **Blinking:** flickers, then steps out of the air behind you.
  - **Volatile:** its last breath is a ring to get out of.
  - **Commanding:** the others near it hit 25% harder and move 15% faster.
- **Weapons fight differently** (combat.json `weapon_traits`, shown in each weapon's description):

| Weapon | Trait |
|---|---|
| Sword | the finisher has a 30% chance of a critical |
| Dagger | +50% from behind; the finisher bleeds |
| Saber | the finisher whirls all the way round |
| Spear | the finisher reaches +1.2 and knocks back |
| Axe | the finisher sunders: +25% damage taken for 4 s |
| Hammer | breaks guards twice as fast; the finisher quakes |
| Halberd | the finisher's wide arc knocks back |
| Staff | every hit cools nanite heat |
| Bare hands | a longer chain window, and a longer finisher stagger |

- **First-time hints** explain heavy blows, openings, guard breaks and big moves.
- **Dev** writes the tells for the codex (brief `foe_tells`).

### Round 61: one more floor (scripts/systems/FloorRun.gd, data/floorrun.json)

- **A floor's tally:** time, foes felled, chests, hidden ways, % walked, hardest blow, closest call.
- **The verdict card:** when the floor's master falls, the card grades the floor S/A/B/C/D, with a line from "whoever watches" (Dev's brief `floor_verdicts`; ours until then).
  - It also shows what's below (its name, whether it's a town, what the gate wants).
  - A better grade than your best on that floor pays the difference in gold per depth, insight and qi. Doing a floor better is worth something.
- **Descent streak:** each floor you go down from in a row, without falling or turning back up, gives +5% qi and +4% loot luck, up to 5. It's shown by the clock and ends when you fall, climb back or go home.
- **Rare finds:** Superior and Masterwork gear arrives with a beam of light where the foe fell, a banner and its own sound.
- **"Almost:" lines under the goals:** your next step at 85%+, one more for the quest you're following, a skill at 90%+, one chest left, the floor nearly walked.

### Round 62: the first hour (HUD.gd, NPC.gd, WorldFX.gd)

- **Quick start:** a button on the first creation screen. It gives a fighter's past, answers every question, spends the points evenly and puts you in Eliet. The full twelve screens are still there for those who want them.
- **Clearer choices:** each creation answer says what it gives ("+1 Spirit, 2 insight").
- **Elder Mo** wears a gold "!" until you've talked to him (the first step).
- **No meridian nudge** in the goals until you've been down the stairs once (one thing at a time).
- **The keys card** folds to "H: keys" after 3 minutes. H brings it back and it stays as you leave it.
- **"While you were away"** waits until you're through the title screen instead of showing under it.
- **Readability:** NPC name tags have a heavy outline (unreadable over snow before), and Frost's snow sheet is softer.

### Dev's part

These briefs are queued in the writing room after `ruins`, ahead of the long side-quest brief:
- `music_titles`
- `foe_tells`
- `floor_verdicts`

**Tests:** playtest steps 99-102.

## Free with the odd ad, or the full game; Steam whole; expansions ready (round 58)

Robert, 2026-10-05, in two messages:

- "free play up to level 5 on iOS and Android with a full pay option after the first 5 levels; Steam has its pay version from the start, with promises of expansions"
- Then: "after level 5 ... it will be ads on the free tier, still able to complete the game, but every so often an ad will pop up -- I don't want it to be too distracting, but I do want to be profitable."

### Phones (data/store.json `model: "ads"`)

- **Free floors.** The village, the valley and floors 1-5 (to Shellhaven) are free with **no ads at all**.
- **Below floor 5.** The whole game stays free to the end, with ads.
  - The first time you go below floor 5, a window ("The road goes on") says how it works. Its buttons are Carry on (free) / Remove the ads / Restore / Not now. It is shown once per device (Store.told).
- **The full game.** One purchase (`full_game`, a non-consumable) removes every ad for good, on that store account. The same character carries on.
- **Ad breaks** (scripts/core/Ads.gd):
  - They come only at a natural break: arriving on a deeper floor by the stairs, or reaching a town.
  - They need you to be safe: not hurt in the last 10 s, and no foe within 14 m.
  - Limits: at most one every 10 minutes, none in the first 7 minutes of a sitting, and at most 4 an hour.
  - "A short break." shows first. The game pauses and goes quiet during the ad, then carries on.
  - Every number lives in store.json `ads`.
- **Gifts** are ads the player CHOOSES to watch:
  - After a fall that cost gold: get it back. It's offered on waking, at the next quiet moment.
  - "The deep's blessing" from the menu: +10% insight and +4% loot luck for 20 min, with a 40 min wait between.
  - A gift is given only if the ad plays through. Gifts are never offered to someone with the full game.
- **Consent.** Google's consent form (UMP) appears where the law needs it, before any ad. After that, "Privacy choices (ads)" is in the menu.
- **The native side** is the Poing Studios AdMob plugin 5.1.0 (addons/admob, the Android binaries in android/bin, "ads" only; no mediation. ios/bin keeps only package.gd so the editor plugin doesn't re-download the iOS libraries -- they're in the round-58 backup if iOS ever comes back).
  - It's reached only through scripts/core/AdMobBridge.gd, which is loaded only on a phone that has it.
  - The web and Steam builds leave addons/admob out.
- **Test ids.** Until Robert makes his AdMob account and app, it uses **Google's test ids**:
  - project.godot `admob/general/android/app_id` / `ios/app_id` (absent means the plugin's test default)
  - store.json `ads.units`
  - Replace both before release.
- **The other way** is still here: `model: "locked"`, where below floor 5 needs the purchase, with no ads.

### Steam: the full game, and a demo

Robert, after Gemini's advice: "have a demo version for steam with an easy transfer when they purchase the full game."

- **The full game on Steam** is paid, whole from the start, with no ads and nothing to buy in the game.
- **The demo** is the export preset "Windows (Steam Demo)" (feature tag `demo`).
  - It's floors 1-5, and the deeper level files are left out of the build.
  - The stair to floor 6 opens "The end of the demo", whose one button is **Get the full game on Steam**: the overlay's store page, or the browser.
  - The page comes from store.json `steam.full_app_id` / `store_url`.
- **Easy transfer:** the demo and the full game share the save folder on the PC (same project name, no custom user dir), so installing the full game picks up the demo's character right where it stopped. Steam Cloud saves stay per app.
- **On Steam** the demo is its own free app tied to the game's page. Its app id goes in project.godot `steam/app_id.demo`; 480 is Valve's test app until it's made.
- **Testing on a PC:** `ELIET_DEMO=1` gives demo mode.

### Purchases and the rest of the store

- **Android** uses Google Play Billing (addons/GodotGooglePlayBilling, official plugin 3.2.0).
  - Purchases are acknowledged, and a pending one doesn't count until it clears.
  - A refund takes it back. Offline, the last answer stands.
- **iOS is dropped** (Robert, 2026-10-05: "Nevermind on the iOS, sounds like a hassle"). The export preset is gone. Store.gd still has its App Store code path, which is unused but harmless; it would only need a Mac, an Apple developer account and a preset to come back.
- **Steam, the box's web build and any PC** have the whole game with no ads and nothing to buy in the game.
- **Testing on a PC.** Run with `ELIET_FREE_TIER=1` (or `"store_test": "on"` in user://settings.json) to get the phone's free tier with a pretend store and a pretend ad network.
- **Where it's kept.** Ownership is per device/store account: user://store.json (with `told`) and user://ads.json (when the last ads and gifts were). It's not in a save slot.
- **Every trip goes through `Game.go_to`.** `Store.travel_check` answers "" / "word" / "locked" / "expansion:<id>", and the HUD opens the right window. No route is a back door.
- **The pause menu** scrolls now (it was taller than a 720 screen). It has:
  - Remove the ads (price)
  - Restore purchases
  - The deep's blessing
  - Privacy choices
  - Expansions to come

### Expansions: how to add one when it's made

1. In data/store.json `expansions`, the entry already has:
   - `id`
   - `levels_prefix` (default `<id>_`)
   - `products` {google, apple}
   - `steam_dlc` (0 for now)
   - `needs_full_game`
   - `status` "planned"
2. Its places are levels whose id starts with `levels_prefix`. `Game.go_to` keeps them shut until it's owned, and opens the expansion's own window instead.
3. Its quests carry `"expansion": "<id>"`; they don't offer until it's owned. Anything else checks `Game.expansion_open(id)`.
4. To sell it:
   - Set `status: "released"`.
   - Make the product in Play Console.
   - Make the DLC on Steam and put its app id in `steam_dlc`.
   - Store adds it to the catalogue and asks the stores for its price. `SteamLink.dlc_installed(appid)` answers on Steam.
5. The expansions page lists planned ones as "planned -- not built yet", a released one as "out now" (with a buy button) or "yours". It says the game is complete on its own.

### Before release (Robert)

- **Play Console:**
  - Make the managed product `full_game` and set its price.
  - Ads declaration: "contains ads".
  - Data safety: advertising ID, used by AdMob.
  - Target audience: not children (ads are rated max "T").
- **AdMob:**
  - Make an app for Android.
  - Make an interstitial unit and a rewarded unit for each.
  - Put the ids in project.godot / store.json.
  - Set up the consent message (GDPR) in AdMob's Privacy & messaging.
- **Steam:**
  - Get a real app id (480 is Valve's test app) and set the price.
  - For the "expansions to come" line, follow Steam's rules on promising future content: say "planned".

### Other notes

- **Words:** store.json `pitch_ads` / `pitch` are mine for now. Dev may rewrite them, but must keep the facts: free to the end, when ads come, never in a fight, one purchase removes them.
- **Tests:** playtest steps 95-98.

## The loophole hunt (round 57)

Robert, 2026-10-05: "work through the game looking for loopholes, broken things -- debug the system."
Found by a full reachability audit of all 52 levels on the box, money-loop probes over every recipe and
forge combination, and a code audit of every reward and of save/load. Fixed:
- MONEY LOOP: buy materials, craft (piston hammers, spring blades, gearplate from shop brass cogs and
  oil) or forge (iron chests), sell for up to 3x. Now a trader never pays more for a made thing than the
  cheapest its materials could ever be bought for (Game.make_cost / made_sell_cap; data/economy.json).
  Crafting still adds value for WEARING; gathered materials still sell at their worth.
- SCAVENGER'S HOLLOWS were a fresh random level every time (new chest, herbs, scenes) -- going up and
  down the stair farmed them forever. Now ScavengeGen.today(): decided once a day per stair, the same
  hollow all day (its chest stays taken).
- A floor's KEEPER respawned on every visit with a guaranteed gear drop, insight and standing. Now it
  dies once (flag "<floor>:keeper"); it only comes back if its key is still the only way through. The
  layout is chosen the same way either way, so nothing else on the floor moves.
- A SECT TRIAL gave +15 standing for STARTING it -- start, fail, repeat to Revered. Standing is now for
  passing ("sect_trial" logs on the pass; "sect_trial_start" at the start).
- AWAY REWARDS replayed if the game was killed within a minute of loading: load_game now saves at once.
- INSIGHT from elites (they come back with their floor) and rival bouts stops at a daily limit
  (economy.json insight_daily_caps); new things are never capped.
- ASCENSION paid for the same collections again every time: now only what's new since the last.
- SAVES: written to "<slot>.tmp", checked, the last good save kept as "<slot>.bak", then swapped in. A
  save that won't read loads its .bak; a broken file is kept aside as ".broken-<time>.json", never
  written over (before: a crash mid-write lost the character to a blank one). Erasing a slot moves its
  .bak too. Steam: a slot that's only in Steam Cloud (a new PC) shows as itself, not "empty".
- Saved mid-fight in the ARENA (or in a tribulation): you wake where you came from / your last town,
  the bout called off (before: the village, with the fight still "active").
- NAMED QUEST FOES spawned at the map's corner: Level._quest_hunt set global_position before the level
  was in the tree. Now position.
- REACHES: a growth could wall off a cell (now and then with a foe in it) -- Reach._unpocket opens them.
- Switching characters carried over sitting / bench / quest "not now" state; negative remove_item gave.
Regression tests: tools/playtest.gd steps 93-94.

## The deep's reaches; Dungeon Crawl Elite; Google Play (round 56)

Robert, 2026-10-05: "make sure the phone version is compatible for Google Play ... then give the world
more depth, more ground to cover, more diverse." The game is renamed **Dungeon Crawl Elite** (the village
is still Eliet); Android package com.grimm82.dungeoncrawlelite.

REACHES (scripts/world/Reach.gd, ReachDress.gd, ReachZone.gd, ReachHeart.gd, systems/Reaches.gd; data/reaches.json)
- When a dungeon floor is built (after Expanse's side chambers), Reach.gd grows ONE reach past the
  right edge of its map (deeper than floor 12, often a SECOND below it): a natural cave (cellular
  automaton, biggest open space kept) 44x32 at floor 1 up to 66x44 deep, joined to the floor by a
  winding tunnel cut through solid rock. The level file is never touched; same floor, same reach.
- Ten lands ("biomes"), never the floor's own look: the Glowcap Wood, the Underlake (islands and
  causeways), the Crystal Hollows, the Root Cathedral, the Ember Rift (pools of fire, "%"), the
  Ossuary Fields, the Frost Gallery (frozen pools), the Sunken Street, the Storm Chasm, the Old Workings.
  Each has its own ground and walls (a LOOKS key), clutter, lamps, giant growths on "x"/"c" cells,
  glow through its ground, its own air (motes), haze and light when you walk in (ReachZone), and its
  own share of herbs / ore / gems / fishing.
- The HEART at the far end: a ring of standing stones and a glowing hoard, guarded by a WARDEN (the
  floor's toughest ordinary foe x2.6 health, the land's own name, a boss bar). Once it falls, E takes
  the store once a game: gold by depth, the land's materials, qi, and -- the first heart of each land
  -- that land's keepsake (a treasure). First steps into a reach give insight (double for a new land).
- The World page lists the ten lands, found and not; play log "reach_found", "reach_heart".
- Words: Dev's to rewrite (brief reaches: each land's name, description and warden's name).

ANDROID / GOOGLE PLAY
- export_presets.cfg preset "Android (Google Play)": Gradle build, AAB, arm64-v8a only, target SDK 36
  (Godot 4.6.3's default; Play requires 36 for new apps since 31 Aug 2026), min SDK 24, no
  permissions (no internet), adaptive + monochrome icons (assets/icon/), app category Game.
- project.godot: config/icon, quit_on_go_back=false, rendering_method.mobile=gl_compatibility (the
  renderer the browser version is proven on), handheld orientation sensor-landscape.
- Main.gd: Android's BACK button = Escape (close what's open, else the pause menu); the game saves
  when a phone sends it to the background (APPLICATION_PAUSED / FOCUS_OUT on mobile).
- Game.gd: on Android llm_url is empty -- no box to ask: LLMCall answers null at once (every caller
  has its own answer) and NPCs don't offer free talk (Game.llm_offline()).
- Renaming moved the save folder (Godot names it after config/name): Game.migrate_user_dir() copies
  the old "Dungeon Crawl Eliet" folder's files across once, never overwriting, leaving the old one.
- The .aab is built in Claude's cloud workspace (JDK 17, Android SDK 36, Godot 4.6.3 templates) and
  signed with the upload key kept in save-data/android-signing/ (back it up: every update needs it).

## The sects' roads (round 55)

Robert, 2026-10-04: "make several chain quests available at the sects for interesting rewards."

- Every valley sect's elder gives a road of FIVE quests (kind "sect", ids <sect id>_1 .. _5):
  1. a guest's errand -- anyone can walk it, member or not;
  2. outer-court duties -- for that sect's own disciples ("unlock": {"sect": id});
  3. a disciple's trouble on a floor, ending in a choice -- Inner Disciple ("sect_rank": 1);
  4. the founder's relic, deep down, with a guardian -- Core Disciple ("sect_rank": 2);
  5. succession: a tower summit, bouts, a deep sovereign, and "stay as heir or wander" -- rank 3.
- What they pay that nothing else does: a keepsake, the sect's token, the sect's SECRET ART, the
  founder's HEIRLOOM (strong treasure), the sect's HEART CANON (strong art) and a title by your
  choice. Also new reward keys: "contrib" (sect contribution -- only to that sect, and only while
  you're in it), "affinity" {element: n}, "insight".
- One sect at a time (as before): other sects' roads stay closed; the Quests page counts them as
  "roads of sects you haven't joined". What you finish stays yours if you leave.
- The elder's dialog says how far along the road you are and what opens next.
- Two chains where the sects meet in the deep: the Jade Pagoda (Elder Bai -> Lady Xiu -> Elder Bai:
  the council, the Grand Tournament, the Oathbreaker and the covenant -- bind or burn) and the
  Hollow Moon Monastery (Sister Hush -> Old Mother Silence -> Abbot Lune: the lost pages, the
  silent lesson, the Hollow Moon Mirror).
- PINNED PLACES: "giver_at" on a quest and "where" on a talk goal tie them to one level -- two
  people share a name (Master Yun, Silverleaf's elder in the valley, and Master Yun of the Jade
  Pagoda). Quests.gd _here().
- A sect Dev writes later (a new id in valley.json) gets a road too: Quests.gd _sect_roads() fills
  data/sidequests.json "sect_template" with its names, element and the element's gifts.
- Words: Dev's to rewrite (brief side_quests, now all 107 pitches).

## Quests of every kind (round 54)

Robert, 2026-10-04: "gather, social, master, main, alchemy, blacksmithing etc quests -- just make it a
real treat for the whole game."

- 71 quests now (data/sidequests.json, "kind" on each): side 26, blacksmithing 6, alchemy 6, medicine
  3, jewelcrafting 3, gathering 6, people (social) 7, masters 7, hunting and taming 3, exploration 4.
  The main quest heads the Quests page; filters by kind, each with done/total.
- CRAFT ROADS: a chain per craft, master to master down the towns -- Smith Hale -> Dagna Ironvent ->
  Haldor Rivet -> Ada Holloway -> Yao the Bellringer -> Bryn Feather; Apothecary Lin -> Lio of the
  Seven Jars -> Wren -> Pell Ironroot -> Sister Qing -> Ruan Cinderfall. "unlock": {"after": id}
  chains them. Rewards: craft tools (treasures with craft_success_<skill>), arts, titles (Smith of
  Ironroot, Master Smith, Grandmaster ...; Elixir Master, Grand Alchemist ...).
- New goal types: "skill" {id, level}; "craft_n" {item or skill, count}; "craft_q" {item or skill,
  quality: fine/superior/masterwork}; "bond" {npc, warmth}; "realm"; "learn"; "event" {kind, count,
  where?, match?} -- ANY play-log event (dodge, parry, stagger, elite_kill, boss_kill, point_open,
  art_stage, gather {kind: herb/ore/gem/fish}, harvest, feed, familiar, rest, talk, secret, chest,
  lore_read, landmark_seen, kill ...). Rewards also: "bond" {npc: warmth}, "skill_xp", "technique".
- 17 new arts ("techniques" in the data file) and 11 more keepsakes/tools.
- Someone with several quests lets you pick which to hear.

## Side quests (round 52)

Robert, 2026-10-04: "build in multiple side quests ... as close to mainstream level of material as possible."

- scripts/systems/Quests.gd + data/sidequests.json: 26 questlines (62 stages) from people in Eliet
  and every town of the deep -- Shellhaven, Lanternmere, Ironroot Hold, the Jade Pagoda, the Ember
  Nest, the Hollow Moon Monastery. Each opens when you've been deep enough ("unlock": {"floor": N}).
- A giver wears a gold "!" over their head when they have a quest for you, "?" when you've news.
  Talking to them offers it in their words (Accept / Not now). The quest you follow shows top right.
- Stage goals: talk (to anyone; "take" hands items over), find (things placed far from the stairs on
  a floor, each with a gold diamond that shows through walls once you're within ~34 m), hunt (a named
  foe: the floor's toughest kind, much harder, with the boss bar; "hunt_drop" is what it carries),
  kill_floor, gather, craft, reach. A talk stage can end in "choices" -> different "endings".
- Rewards: gold, qi ("qi_kills": that many kills' worth of the quest's own depth), items, faction
  standing, titles, and 11 unique keepsakes (small lasting gifts: luck, health, ward, dodge, qi...).
- The Quests page: what you're on (and the step), who's asking and where, how many are still to
  come, and what's done. Quest items left over are taken when a quest ends.
- Your words: brief side_quests (the pitches); drafts in data/drafts/side_quests.json.
- To add one: an entry in data/sidequests.json -- giver must be a real person in "place"; floors
  for find/hunt must be dungeon floors.

## How long the game is (round 52)

- Main quest about 25-35 hours (50 floors, 12 chapters); with the side quests and the inheritances
  about 45-60; everything 70+. Comparable games: Diablo IV ~20-27 h main / 30-50 with side content;
  Hades ~20 h main; Skyrim ~30-35 h main / 60-100 with side quests; Tale of Immortal ~50 h a run.

## Feel: smooth movement, a soft camera, effects that make sense, detail (round 52)

Robert, 2026-10-04: "more depth to the world, more detail, more contrast, action special effects
that make sense. I want the character movement to be smooth ... as close to a good mainstream game."
All numbers: data/feel.json.

- MOVEMENT: up to speed in ~0.12 s and a short controlled stop (~0.1 s); you turn every rendered
  frame (not every physics tick), so turning is smooth at 144 Hz too.
- CAMERA: follows with a touch of lag (softer vertically, so a jump doesn't jerk the view), snaps
  through doors and teleports; shake is "trauma" that builds with blows and fades smoothly (with a
  little roll); a heavy blow or a crit pulls the field of view in for an instant.
- FOES are drawn between physics ticks like you are -- no stepping at high frame rates.
- WHAT A BLOW KNOCKS LOOSE (FX.matter): flesh bleeds dark red, bone chips, metal sparks, stone and
  clay throw grit, bark bleeds sap, fire throws embers, crystal shards, spirits shed wisps. Taken from
  the creature's name (Monster.skin_for), thrown away from the blow.
- DAMAGE NUMBERS pop off what you hit (gold and bigger when you strike true, blue for arts, orange
  for burns). Off in data/feel.json numbers.on.
- QI YOU EARN FLOWS INTO YOU: a kill's qi curves up and into you as motes (more from elites and masters).
- THE SCREEN'S EDGES: a soft vignette; red when you're hit (as much as the blow took); a slow red
  pulse when you're under a third of your health.
- THE LOOK: more contrast and deeper corner shadow (SSAO), a little more bloom on lights and effects.
- DETAIL ON THE FLOOR (GroundDetail.gd): puddles, moss and dirt patches, pebbles drifted against the
  walls, cobwebs in corners -- how much of each by region (a drowned seam is wet, a crypt is webbed, a
  forge is dry and gritty). A few draws per floor; never in the way.

## Inheritances: minor, major, heavenly -- different every game (round 51)

Robert, 2026-10-04: "make sure major inheritance isn't something easy to find -- I like the blacksmith
in the beginning, make it random though to make replay interesting" ... "minor inheritances, major
inheritances and heavenly inheritance, all providing unique benefits ... possible to attain multiple
... even when the main quest is done players are free to be a completionist within their own game."

- scripts/systems/Legacies.gd + data/legacies.json. Each game has its own SEED (saved), so its
  layout is its own and stays put; a new game lays everything out again.
- MINOR (craft masters at lost workshops, Vignette.gd): all five in every game. One sits on floor
  1 or 2 -- which craft is random -- in his own craft's workshop; the other four on random upper
  dungeon floors (never a cavern town). The little scenes on a floor move game to game too.
- MAJOR (the "inheritances" a level file names -- keep writing them; put the 'I' somewhere good):
  always hidden. Each game moves one to a far corner, a dead end or a room behind a secret wall
  (sometimes it stays where you put it). Spirit Sense finds it only from a few steps away (and
  says "something old and patient nearby" from further); without it, stand still right beside it
  and search. A drift of pale motes is the only sign. About a third sleep at the start of a game
  and wake when the player is a realm past what they ask (or the road is walked) -- "word comes
  up the stair". Claimed once, keyed to the floor's 'I' cell wherever it sits.
- HEAVENLY: three per game from a pool of six, on random deep floors (8-48). Core Formation to
  perceive one at all; Spirit Sense from a few steps; then the master's echo (the floor's
  strongest beast, four times as hard, with a boss bar) tests you. The prize: a heaven-grade
  passive art, a treasure and a title nobody else can have. No crystals for these. Your words:
  brief heavenly_inheritances.
- The Road page keeps the count for all three tiers, with where-to-look hints (a band of floors
  for unfound majors, a floor range for each heavenly one once you're strong enough to feel it).

## Three games, three characters (round 51)

Robert: "allow the user to have up to 3 games going that save to their own unique character."
- Slot n saves to user://save_slot<n>.json (Steam Cloud: one file per slot). The last one played
  opens next time. An old single save becomes slot 1 (the old file is kept).
- The title: Continue, or Characters -- a card per slot (name, realm, place, time played): Play,
  Begin a new character here, Erase (asks twice; the file is kept, renamed .erased-<date>).
  The pause menu's old "New game (erases save)" is now "Characters".
- Every character has its own world: its own inheritances, its own road.

## Prompts, foes' health, the boss bar (round 50)

Robert, 2026-10-04: "keep working on it" -- the second pass of the modern HUD.

- PROMPTS: anything with a prompt() of the form "E: Open the chest" shows as a pill -- the
  key in a gold key-cap, then the action (HUD.split_prompt). Keep writing prompts as
  "KEY: what it does"; text without a short key before a colon shows without a key-cap.
- FOES' HEALTH (FoeBar.gd): a slim rounded bar under the name instead of "Thornling 258/258".
  It shows once the foe is hurt (always for elites and bosses), and leaves a pale trail when
  it drops. Names use the bold UI font.
- THE BOSS BAR: a boss within 24 m (and awake) puts its name in carved capitals and a long
  health bar across the top of the screen; it goes when you leave it behind.
- THE FRONT DOOR: the title is a veil over the world (the place shows through), the name over
  a thin gold rule, and the buttons fade in one after another. The level-up card slides in.
- The key help sits on a quiet glass card.
- Numbers: data/ui.json "foe_bar", "boss_bar", motion "stagger".

## Smoother, modern menus and HUD (round 49)

Robert, 2026-10-04: "make the gui and hud and menus more smooth and modern but keeping to the esthetic."

- One place for the look: scripts/core/UiStyle.gd builds the whole theme (HUD._ui_theme returns
  it; every window inherits it -- including windows put straight on the HUD layer). Every
  colour, radius, shadow and timing is in data/ui.json.
- Same world -- dark lacquer, warm gold, a cool glow for qi -- but softer and rounder: windows
  have 12px corners, a hairline edge and a soft shadow; the status panel is translucent glass.
- Real fonts (assets/fonts/, SIL Open Font License): Inter for reading, Cinzel's carved
  capitals for titles. Any label 19px or bigger made through HUD._label is a title.
- Motion: windows rise and fade in when they open (UiStyle.animate_opens); menu pages slide
  across; buttons glow as the pointer or the pad comes over them and give a little when
  pressed (every button, automatically); new log lines fade in; the health and qi bars leave
  a pale trail that catches up a moment after a drop, so you SEE what a hit took
  (UiStyle.set_bar -- the bar's value is always the true one at once).
- The menu's side rail is quiet until chosen, then gets a gold bar down its edge (type
  variation "RailButton"); tabs get a gold line under the open one. Also "FlatButton" for
  quiet rows.
- Fixed: the side rail could show several sections lit at once; the message log sat on top of
  the keys at the bottom of the screen.
- Tweens here run even while the game is paused (the pause menu animates too).

## The world past the edge of the map (round 48)

Robert, 2026-10-04: "the whole world needs more depth -- the illusion of it continuing."

- UNDER THE SKY (Horizon.gd, outdoors): the land runs on ~230 m past the map's edge --
  level at the village's edge, rolling up into wooded hills, then a ring of mountains with
  snow on their peaks (lower in Frost). Grass on the gentle ground, rock where it's steep,
  snow up high (assets/shaders/terrain.gdshader). A forest of real trees stands on the slopes
  (170 trees in four draws), a sect's stone tower stands on a far ridge with its lamp lit at
  night, and smoke rises from far farms. Even on a clear day there's a little haze, so the
  distance reads as distance.
- THE VILLAGE'S EDGE (Level._rim_edge): no more ring of crags -- the fields end in shrubs,
  boulders, old fence and the odd tree, and the land beyond carries on. (The wilds keep their
  crags inside the map; only their outer rim softens.) Still solid: you can't walk off the map.
- UNDERGROUND (Horizon._rock): the halls are cut out of one mass of rock that runs on past
  every wall and over the wall tops, rough-topped, with a ragged edge that falls away into
  the dark of the deep. A faint cold light reaches only that stone (its own render layer).
  A few glowing cracks: caverns you can't reach. Not in arenas or cavern towns.
- LEAVES THAT GET OUT OF THE WAY: leaves between the camera and you thin out (a dithered
  see-through near your line of sight), so a tree never hides you. The shader reads your
  position from the project-wide shader global `player_pos` (project.godot [shader_globals]);
  Player.gd updates it every frame.
- The fog of war no longer hides the world itself (WorldFX's weather or the Horizon): nodes
  in the group "fog_exempt" are skipped. (WorldFX's underground motes were being hidden since
  round 44 -- fixed with it.)
- Every number: data/horizon.json (land, forest, tower, smoke, haze, rock).
- Lesson: Godot can only ADD a shader global at run time in the editor -- in a game it must
  be declared in project.godot.

## Realistic trees, props, people and equipment (round 47)

Robert, 2026-10-04: "More visually realistic worlds and character" and "can the equipment be
smoother, more realistic and not so blocky".

- TREES (Tree.gd): every Kenney tree becomes a real one at Medium graphics and up -- a bark
  trunk (Poly Haven bark) and a crown of photo leaf cards (cut from Poly Haven's tree atlases,
  assets/foliage/) that sway and let light through (assets/shaders/foliage.gdshader). Pines/
  firs get tiers of needled branches. Harvest turns leaves orange, Frost strips them. Built at
  the Kenney tree's size and footing, so no level changes.
- PROPS (Art.gd REMAT): canvas tents on wooden poles, weathered-wood stalls/carts/fences,
  linen banners, thatched roofs, a marble fountain (its water kept), iron lamp posts and trap
  plates, marble columns. A REMAT entry can be {"default": spec, "<material>": spec,
  "keep": [...]} to surface each part of a model by its material. Real flowers (Poly Haven).
- PEOPLE (Human.gd, Dress.gd): brows take the hair colour (they were white), skin is less
  glossy and less orange, eyes are wet, hair less neon; a proper scholar's cap and a woven
  straw hat instead of a box and a flat cone.
- EQUIPMENT (Armour.gd): pieces are turned on a lathe (Armour._lathe / _shape) -- a
  breastplate that swells over the chest and nips at the waist, greaves shaped to the calf,
  vambraces flared at the elbow, a robe that flows from shoulder to a belled hem -- with
  rolled rims on the edges; rounded boots with soles and turned-down cuffs; smooth layered
  pauldrons. Cloth and leather wear photo textures (linen, worn leather); metal is finely
  brushed and scratched. Weapons in hand (Dress._held_real): turned wooden hafts in real wood,
  forged heads with curved edges (a bearded axe, a leaf spearhead, a halberd blade, a round
  hammer head), no boxes.
- New Poly Haven assets and their credits: assets/manifest_round47.json.

## Traps and secrets you have to notice (round 46)

Robert, 2026-10-04: "Be more subtle with traps and secrets."

- A hidden wall ('S') looks exactly like the walls around it and offers nothing to press
  until you NOTICE it. The only tell is a thin drift of dust from its seam (a draft).
- Past the first floor a trap ('T') is hidden: the plate is invisible under the floor, with
  only a few loose pebbles and a faint darker stain. Step on an unspotted one and it clicks:
  about half a second to roll clear, then the spikes. Spotted or sprung, it's a known trap
  with the old visible rhythm. Floor 1's traps stay visible, to teach the rhythm. Beasts don't
  set off hidden traps. Trap damage now grows with depth.
- Noticing builds while you're near: fastest standing still, slow walking, almost never
  sprinting; Survival speeds it up; Spirit Sense notices anything hidden in its reach (a
  brief shimmer, not a beacon). Found things stay found (flags). data/subtlety.json.
- When you write a floor: put secret walls where a curious player would stop and look (a
  dead end, an alcove, a room that's too small for its doors), and traps where people walk
  without thinking (doorways, the middle of a quiet hall). Give a hint nearby in words -- a
  lore stone, a note -- rather than making the thing itself obvious.

## Eliet remembers, and the world talks (round 45)

- The Lantern Stone by Eliet's fountain names those who went down and came back: Mo, of the
  first expedition -- and you, once Eliet reveres you (Level._place_village_memory).
- Peoples who trust you (Trusted+) fly their banners by the fountain.
- A camp that's become a Town sends its trader up to Eliet every third day (Settlements.
  market_day / visitors / place_visitors); that day the camp's stall is empty and the headman
  says so. The World page lists who's up today.
- Lore.gd's tips now carry the world's news: camp_need, camp_unmet, market, relic, festival,
  season, hunters (data/tips.json templates -- yours to reword in the tips brief; keep every
  {placeholder}).

## Inheritances: a base requirement, and inheritance crystals (round 43)

Robert, 2026-10-04: "A base requirement for inheritances is needed. If the
character finds one and can't use it at all, or yet, they can condense the
inheritance into an inheritance crystal for later use or sale."

- THE BASE REQUIREMENT is the higher of the level file's `needs_realm` and the
  realm of every technique the legacy teaches. A level that names no
  `needs_realm` asks for one realm per four floors (floor 20 asks realm 5).
  Below it the will turns you away and says what it asks for.
- OF NO USE: every technique in it is one you already know, and it gives no
  items or qi.
- CONDENSE: locked, of no use, or just by choice, the player can condense the
  will into an "Inheritance Crystal of <master>". It sits in the pack under
  Crystals. Absorb it once you reach its realm and you get the whole legacy
  (items, techniques, qi, any trace of blood). Or sell it -- traders pay its
  full worth (deeper legacy, more inside = more gold). The seat is empty after.
- The numbers (floors per realm, crystal value) live in data/inheritance.json.
- Code: `Game.inheritance_need / inheritance_state / condense_inheritance /
  absorb_crystal`; `Inheritance.gd` offers the choice; Kit.gd's Crystals group.
- When you write an inheritance: always set `needs_realm`, and make the
  master's words say plainly what the legacy is for, so a player who carries
  it as a crystal knows why it's worth keeping.

## Words that give something: tips, history, and how Dev writes (round 42)

Robert, 2026-10-04: "make sure Dev knows that the story and explanations
should be easy to understand and be meaningful, or give something more to
the game -- either filling out its history or giving hints and tips through
conversation, reading, secrets, treasure and inheritance."

- HOW TO WRITE FOR ELIET (data/tips.json "_principles", and writing_room.json
  "principles", which every brief's prompt now carries): plain words, short
  sentences; every piece earns its place -- a true piece of history or a
  useful hint, ideally both; hints are true; said the way someone in the
  world would; connected to what the world already has. Dev's writing room
  now refuses hard-to-read drafts (sentences averaging over 22 words, or one
  over 38) and Dev retries with the reason. The floor forge asks for one
  stone of history and one of hints on every floor.
- THE LORE SYSTEM (scripts/systems/Lore.gd, data/tips.json): TIPS that are
  true now -- hidden ways still on this floor, a hidden chest, the floor's
  master and how to beat it, what the next gate wants and what its item is
  made of, what a material in your pouch is for, a hidden master's rumour,
  where the crafts are taught, cleansing, research, an element clash, a
  friend who'd travel with you, the basics (shrines, parrying) -- and
  HISTORY, sixteen fragments of the story of Eliet and the deep, unlocked by
  depth (nothing found shallower than it belongs), never twice.
- WHERE: below the carving the first time you read a lore stone; inside a
  hidden wall; in a chest (40%); a dead master's last advice; "Any advice?"
  from anyone (and people you talk to know a tip they might pass on). The
  Road page keeps "What you've learned"; mastery counts the history.
- Words: Dev's briefs `tips` (rewording the templates -- used only if every
  {placeholder} is kept) and `history` (20 more fragments, with the floor
  they're found from).
- Tests: playtest step 68 (1363 checks).

## Modular systems: synergy, the mind, cleansing, the swarm's research, spirit (round 40)

Robert, 2026-10-04: the swarm "separate but synergistic with qi -- the
nanites using qi to function, the qi needing the nanites to increase
recovery, focus, adaptability, connection" (connection was what they were
made for, and failed at); "meridian cleansing for major and minor nodes ...
a percentage boost -- figure out a fair metric"; the swarm as a utility with
"its own skill tree ... design different nanites for different functions,
cost qi and resources to research and connect while meditating"; "both" a
chosen focus and a split, with "a research tree for splitting the mind";
"wetware, hardware, cybernetics and power armor in late game ... more techy
as we go, but qi and equipment still matter -- build it modular"; and "a
spirit page with the affinities listed there".

- THE MODULAR SHAPE (scripts/systems/GameSystem.gd): a system is one Node
  under Game with its own data file and saved state, and hooks Game calls
  on every system -- setup, reset, save_state/load_state (save["systems"]),
  effects, tick, meditate(secs, shares, aid), background. A new system is a
  script, a line in Game.SYSTEM_SCRIPTS, and a menu page. Four now:
- SYNERGY (Synergy.gd, data/synergy.json): level = the lower of realm and
  swarm tier (+0.5 in harmony). Recovery +2.5%/level (sitting qi, +0.05
  health/s), Focus +4% (meridians open, cleansing, research), Adaptability
  +2% (skills), Connection +2.5% (insight, bonds with people and beasts).
  HONING (round 41 -- Robert: the swarm "was designed to magnify focus and
  hone warriors as they grow together"): +1.5% damage, +1% strike speed,
  +0.4% telling blows and +0.01 s to the parry window and a roll's slip per
  level (the timing capped at +0.15 s; effect key "timing", additive).
  UPKEEP: connected designs and installs draw 0.015% of a step's qi per
  point per minute; run dry and they go quiet until there's qi again.
- THE MIND (Mind.gd): your sitting goes to Cultivate (qi in full + your
  lattice focus), Cleanse, or Research (qi at 60%). Divided Mind research:
  split two ways, then three (85% each until Quiet Mind). Swarm Parallelism:
  research and cleansing go on at 25%, then 50%, while you don't sit.
- CLEANSING (Cleansing.gd, data/cleansing.json): the 36 lattice points are
  minor nodes (open first), 12 major nodes open with realms (Qihai ...
  Baihui). Five grades, murky -> radiant (0/20/45/70/100%), later grades
  need realms. THE METRIC: each stat has a ceiling (health, damage, qi,
  recovery +30%; speed, strike speed +15%; defense 20%), shared by weight
  (minor 1, major 4, crown nodes 2 to every stat) -- everything radiant is
  exactly the ceiling. Marrow / Heaven Washing Pills (alchemy).
- RESEARCH (Research.gd, data/tech_tree.json): one engine; add a node to
  the file and it's in the game. 47 nodes in 11 branches -- Mending,
  Guarding, Hunting, Scouting, Crafting, Conduit (qi; ends in the Heaven
  Bridge, what the nanites were made for), Divided Mind, and late: Wetware,
  Hardware, Cybernetics, Power Armour. Kinds: design (bandwidth by tier, qi
  upkeep, TUNED with a material: Refined, Silvered, Cooled, Jade-bound,
  Ember-tuned, Resonant), passive, unlock, install (BODY LOAD: 2 + a point
  per two realms + a third of a point per radiant node; modules need their
  frame). Research costs sitting time, a share of a step's qi and materials;
  connect, tune and install while you sit.
- MENU: new sections Spirit (the five elements: values, gifts, what grows
  them, synergies and clashes, insight, dao heart, blood), Mind, Swarm (Y).
- Hooks in Game: adapt_mult (add_skill_xp), insight_mult (gain_insight),
  bond_mult (grow_bond, warm_bond), focus_mult (lattice opening), cleanse
  pills (use_item), mastery parts "cleansing" and "research".
- Words: Dev's brief `tech_tree` (names and descriptions of all 47 nodes).
- Tests: playtest step 67 (1341 checks).

## The menu, a party of two, contract beasts, bonds (round 39)

Robert, 2026-10-04: "can we have companion, contract beast, bonds, etc.? I
want the menus to be more intuitive and fluid and make sense, make things
more snappy, more responsive. We actually need a more in-depth menu screen
that could help just organize it." He chose: one menu with sections down
the side; a party of two; beasts -- "all of the above can be unlocked".

- THE MENU (scripts/ui/Hub.gd): one screen, sections down the left -- You (P),
  Pack (I), Party (O), Bonds (U), Road (L), Journal (N), Meridians (K),
  System. Tab opens it where you left off; each key jumps straight to its
  section and closes it again; Q / E (shoulder buttons on a pad) flip
  sections; Esc closes. The old windows (pack, character sheet, journal,
  lattice) are its pages now -- open_kit, toggle_journal and the rest still
  work, they just open here. A window asked for from the menu shows over
  it. It opens in 0.08 s and refreshes once per frame at most. On a phone:
  MENU on the top row.
- PARTY OF TWO: one companion from the start, a second place from Nascent
  Soul (data/party.json). Every companion function takes the slot (0 at
  your shoulder, 1 behind). Each has their own style, level, gear and life.
  A full party: someone new takes the second place. "Walk first" swaps them.
- THE ROSTER: everyone who has travelled with you. From any town you can
  call them back (if they're still warm to you, 45+). Their persona, home
  and colours are kept in their bond.
- CONTRACT BEASTS: every animal that chooses you is a contract
  (Game.contracts; `familiar` is the lead, the same dictionary). Contracts:
  2, rising with Taming (to 8). At your side: 1; 2 at Taming 10 and Void
  Refinement; 3 at Taming 18 and Immortal Ascension. The lead gives its
  gifts in full, the others 60%. Each can be DEEPENED -- Blood Contract
  (x1.25), Soul (x1.6), Heaven (x2.0) -- with bond, realm, materials and
  gold. Resting beasts still grow (0.1 bond a minute). Rename, make lead,
  rest, call, release -- all on the Party page, with the taming tree.
- BONDS page: everyone who knows you, closest first, warmth bars, what
  they remember, who's on your roster, who's your partner.
- ROAD page: the chapter's goals ticked off, the next gate and what it
  lacks, errands, the story, the hidden masters' rumour, mastery and balance.
- Words: Dev's brief `contracts` (names and moments of the three deepenings).
- Tests: playtest step 66 (1289 checks).

## Rune craft and talismans (round 38)

Robert, 2026-10-04: "build rune craft and talisman into mid-tier game".
Everything lives in `data/runes.json`; Game._merge_runes adds the two skills,
the items and the recipes at start (the forge's own files aren't touched).

- TAUGHT, NOT BORN: both crafts must be taught (`skill_known`). Old Oda, a
  grave-cutter on floor 17, teaches rune craft (Nascent Soul; bring silver
  and bone). Sister Hwa, a letter-writer on floor 22, teaches talismans (Void
  Refinement; bring spirit silk and herbs). They're hidden masters 13 and 14
  (`reward.craft`), and afterwards their TABLE is open: carve, draw, set
  runes (the pack's Runes tab, at_bench "rune"). Your home bench works too.
  Until taught, `can_craft` and the bench refuse those recipes.
- RUNES: 12, carved from a Rune Blank plus a material from the depths
  (Edge, Ember, Root, Tide, Stone, Fortune, Wind, Eye, Storm, Song, Star,
  Void). Each has a gift in a weapon and another in armour. INSCRIBE one into
  something you wear (anywhere): a weapon holds 1, 2 at Runecraft 8, 3 at 15;
  any other piece 1, 2 at 12. A slip cracks the rune, never the piece.
  SCOUR grinds them off for gold. Weapon runes count in full; runes on
  everything else pool (past 8% a gift counts 40%, never past 25%), so
  variety beats stacking one kind.
- RUNE WORDS: 10. The right runes in the right order on one piece speak a
  word with its own gift (Keen Flame: Edge then Ember on a weapon). Old Oda
  tells you one at a time ("Ask about rune words"), and won't tell the next
  until you've cut the last. They count toward mastery.
- TALISMANS: drawn on Spirit Paper in Cinnabar Ink. Key 4 burns the readied
  one, 5 switches (TAL on the phone). Flame, Frost, Thunder (bursts around
  you), Binding (holds foes), Iron Skin and Swift (buffs), Mending (heal),
  Clear Sight (the whole floor's map and further sight), Heavenfire (late).
  Quality and your Talisman craft make them stronger.
- THE ROAD: gate 26 now needs a Mirror Seal Talisman (from floor 24's frost
  vellum and rime ink); gate 36 needs two runes in your weapon. The main
  quest points at both teachers, a first rune, a rune word, and the two
  runes. Balance counts both crafts as making.
- Words: Dev's. Briefs `runes` (names and descriptions) and `rune_words`
  (names and Oda's hints); the hidden masters brief has the two teachers.
- Tests: playtest step 65 (1225 checks).

## Sky, bodies, balance and mastery (round 37)

Robert, 2026-10-04: "make the characters more realistic, more fluid
articulation and better graphic effects"; "give it a sky or ceiling, clouds,
stars, more texture"; "take days to complete and even when you do there is
always more to do ... balance may provide the strongest growth".

- SKY (`assets/shaders/sky.gdshader`): outdoors a drawn sky -- day blue to
  dusk to night, drifting clouds (cover seeded by the day and the level),
  the sun and the moon, twinkling stars and the sky-river at night.
- CEILINGS (`assets/shaders/cave_sky.gdshader`, Level._cave_vault and
  _build_ceiling): underground a rock vault with seams, glowing specks and
  mist; a roof at wall height facing down, and stalactites that show only
  when the camera is below the roof.
- BODIES: people lean into a run and roll into turns, their stride matches
  their speed, their heads turn to look at what's near (LookAtModifier3D on
  the Head bone), animations blend (0.18-0.2 s), skin has subsurface light,
  cloth and hair their own sheen; running kicks up dust.
- EFFECTS: a heavy hit stops time for a heartbeat (Game.hit_stop); smoke,
  mist, steam and spores are soft puffs that billow, not squares.
- BALANCE (`data/character.json` "balance", Game.balance()): four scales
  (attributes, paths of fighting/making/finding, qi against the swarm, the
  elements), each 0..1 by how even it is. Growth (qi, skill practice, the
  swarm) is multiplied by 1 + 0.6 x balance^1.6 -- a specialist is strong
  now, a balanced cultivator grows fastest. Shown on the sheet (P).
- MASTERY (`data/character.json` "mastery", Game.mastery()): how much of the
  game you've done, in 14 weighted parts (floors explored, chapters, story,
  both endings, masters, gates, titles, achievements, collections, bestiary,
  bloodlines, realms, skills, ascensions). Some of it can't be done in one
  life; ascension carries past endings and pure bloodlines on.
- Tests: playtest step 64 (1175 checks).

## The character: who you are, what you've earned (round 36)

Robert, 2026-10-04: "a level up screen where I can see my player stats; the
nanite and qi system complementary to player stats, abilities and titles;
everything is earned; clear progression; the world needs more space; the
dungeons and cities should grow with their level" -- and "make character
creation more involved ... answers weigh in on where their starting stats
are and how many free points they have".

- CREATION (HUD.start_creation, `data/creation.json`): a name, a look (body,
  skin, hair, colour, beard -- the player model uses it), a past (the
  BACKGROUNDS), seven questions (born, trouble, hands, fear, why, temper,
  the road). Every answer is worth one point -- an attribute you're BORN
  with or a free point -- and some a small gift; the last question leans
  in (+2 to your strongest) or keeps points free. A last page shows it all.
  An older save is asked once (only gains). Dev's words: brief `creation`.
- ATTRIBUTES (`data/character.json`): Body, Might, Agility, Spirit. Points
  are counted from what you've done (1 a step, 3 a realm, 1 a chapter, 1 a
  hidden master, + creation's free points), spent on the sheet; born points
  stay, spent ones can be unlearned for gold.
- TITLES each carry a small gift (listed, or by the words in the title),
  capped at +15% a stat.
- THE SWARM now strengthens the hand too: +1.2% damage and +0.1 health a
  second per tier (`data/nanites.json` per_tier).
- THE CHARACTER SHEET (P): every stat, and for the one you pick, where it
  comes from (cultivation, weapon, what you wear, the swarm, attributes,
  titles, blood, elements, meridians, techniques, buffs); the road down and
  the next gate; attributes to spend; titles with their gifts; arts.
- LEVEL UP: a step of cultivation shows a card (what changed, +1 point) that
  doesn't stop play; a realm crossed opens the full window.
- SPACE: the valley's plan is spread 1.45x (`Valley.SPREAD`) -- the river,
  roads, sects, towers further apart, with more woods, creatures and finds
  between them. The floor forge now keeps growing floors with depth
  (`max_added_rooms(n)` = 3 + n/5 side rooms; towns `max_added_people(n)`
  = 3 + n/10 townsfolk; rooms themselves +2% a floor past 10, up to +60%).
- Tests: playtest steps 62-63 (1163 checks).

## Fog of war (round 35)

Robert, 2026-10-03: "add a fog of war so it's harder to see the rest of the
level". `scripts/world/FogOfWar.gd`, made by Level._ready on every underground
level (not the village, settlements, the valley, arenas or a tribulation):

- UNEXPLORED cells are covered black (a MultiMesh of tall boxes); what
  stands there is hidden. REMEMBERED cells (seen before, not now) are
  dimmed, and nothing moving shows in them. IN SIGHT: 8 cells around you,
  walls and unfound secret walls blocking the line (grid Bresenham).
- Foes show only in sight; everything else the floor placed (chests,
  stones, levers, torches, signs) shows once explored. The fog only ever
  un-hides what it hid (meta "fog_hidden").
- What you've explored is kept per floor (`Game.fog_seen`, saved; not for
  trials or hollows, which are drawn fresh). `reveal_all()` for a map.
- Sight: +"sight" (the Spirit Lantern, smithing: +3 for 15 minutes) and a
  third of "sense_radius" (familiars, techniques), up to +8.
- Menu: "Fog of war: on / off" (Gfx.settings "fog"; off takes effect at once
  for what it hid, and the next floor has none).
- Tests: playtest step 61.

## Earned: gates, the road down, errands, buffs, hidden masters (round 34)

Robert, 2026-10-03: "days and hours of play time each level a little harder
to reach, bottlenecks that need more training, items, alchemy to push
through; more crafting, more quests, a main storyline quest that keeps the
players going in the right direction" -- and "put hidden masters throughout".

- GATES (`data/gates.json`): the stairs down to floors 6, 11, 16, ... 46
  refuse (a window says why and what it takes) until you meet the need: the
  realm the floor forge tuned that floor's foes for (`godot_forge.expected`:
  Qi Condensation at 6 ... Immortal Realm III at 46), sometimes a skill
  (Survival 10 at 21; weapon 16 at 36), a story act (25's Mirror, 40, 45),
  and a crafted ITEM spent on the way down (Deep Breath Pill, Warding
  Talisman, Stormglass Lantern, Voidsalt Draught, Heartfire Elixir, Star
  Iron Key, Mirrorheart Ward -- every one made from materials found above
  its gate). Passed once, a gate stays open. Dev's words: brief `gates`.
- THE CURVE (`data/combat.json` "curve"): from floor 3, every floor's foes
  +3% life, +1.8% damage and a little more often elite (on top of the floor).
- BUFFS: crafted consumables with "buff" (whetstone, qi incense, ironskin
  salve, swift tonic, finder's charm, hunter's oil) last 10-15 minutes;
  `Game.buffs`, shown in the journal.
- THE ROAD DOWN (`data/main_quest.json`): twelve chapters from the first
  floor to the Heart; each has goals the game checks itself (floor, master,
  realm, craft, skill, gate, story, guild, home, blood) and a townsperson to
  report to for the reward. The HUD's first goal line is always the next
  goal; the journal shows the chapter. Dev's words: brief `main_quest`.
- ERRANDS: Elder Mo offers, for every floor you've reached, a kill errand
  and a gather errand from that floor's own foes and chests (three new at a
  time), paid by the floor.
- HIDDEN MASTERS (`data/hidden_masters.json`, `scripts/actors/HiddenMaster.gd`):
  twelve, in Eliet, the valley and floors 4-48, each disguised (a sweeper,
  a fisherman, a cook, a beggar, a lost child...). Talk enough (and be
  strong enough) and they reveal themselves and set a test -- sit, bring,
  kill, craft, wait real hours, kill a master, give gold, master yourself
  -- then teach a technique of their own (only effects the engine reads).
  The journal keeps a rumour of the next. Dev's words: brief `hidden_masters`.
- Tests: playtest steps 59-60 (1108 checks).

## Floor 50 is the end (round 33)

Robert, 2026-10-03: "we can stop at level 50 for this game with a sequel or
expansion pack." So:

- The forge's `max_floor` is 50. Its LAST floor is always a dungeon floor
  (never the town the schedule would give it): its master is "<name>, the
  Heart of the Deep" (x1.6 life, bigger, `"final": true`), the level has
  `"final": true`, and its stairs down lead to `"ending"`, not a floor 51
  (`godot_forge.plan_dungeon(final=True)`).
- The game: a floor marked final shows THE LAST FLOOR as you arrive
  (Level.gd). Its stairs (Exit.gd, target `ending`) refuse while the master
  lives, then call `Game.finale()`: flag `story:finished`, title "Heart of
  the Deep", Steam `FINISHED`, and the ENDING SCREEN (HUD.show_ending): an
  epilogue built line by line from what you chose across the story
  (`data/story.json` "epilogue"; Dev's words: brief `epilogue`, items with
  "key" and "text"), the credits, and two ways on -- back to Eliet, or
  ascend at the Trial Board to begin again, stronger (New Game+).
- The story's back half: acts at floors 30 (Captain Rhee, the Lodge's
  expedition), 35 (Smith Hale, the last steel: two pieces of gear), 40
  (Apothecary Lin, the draught: your blood or the children), 45 (Trader
  Wen, the last letter), and "After the Heart" (Elder Mo, in Eliet, once
  you're finished: stay -- "Elder of Eliet" -- or go east -- "The Wanderer",
  which is where the sequel picks up).
- Tests: playtest step 58 (1043 checks); forge test "the last floor".

## The original game, built out: combat, floors, people, yours (round 32)

Robert, 2026-10-03: "I want the original game to be built out more, then the
other platform versions can be converted." Four picks, all in:

**Deeper combat** (`data/combat.json`, Player.gd, Enemy.gd). Click-click-click
is a three-hit COMBO (the third swings wide and staggers); HOLD the click for
a HEAVY blow (charged up to 1.3 s, x1.6-2.6, it breaks guards); Ctrl (pad LT)
is a DODGE ROLL with a moment of invulnerability; Z (middle mouse, pad
right-stick click) LOCKS ON. Every foe has POISE under its life: heavy blows
and finishers wear it down; at zero it STAGGERS and takes a third more.
Bosses change PHASE at two-thirds and one-third life (an affix, a brood).

**Bigger handmade floors** (`scripts/world/SetPieces.gd`, Gate.gd, Lever.gd). Every
dungeon floor from the second gets, from its own seed and without touching
the level file: THE KEEPER (a named two-affix mini-boss, "The Warden of
<floor>", carrying the floor's key), THE GATE (iron bars cutting off a pocket
that never holds the way down) and THE VAULT behind it (real gear, old blood
deep down), and THE LEVERS (three colours, a tablet with the order; right
opens a second gate, wrong wakes the room and resets). The forge builds on
to floor 40. Dev's words for the tablets: writing room brief `puzzle_hints`
(items with a "text" holding three `%s`).

**People and story** (`data/story.json`, Game.gd "story", NPC.gd). Eight
ACTS fire on what you do (floor 2, the floor-3 master, floor 6, 10, the
blood waking, 15, 20, the floor-25 master): a window tells it, and the named
townsperson has the SCENE waiting in Eliet -- two choices, real
consequences (gold, standing, insight, a title, a discount, a rival on the
valley road, your blood). ARCS: what each townsperson says after, and gives,
once. Two ENDINGS at floor 25: seal the shaft or go on. The journal keeps
"The story so far". Dev's words: writing room brief `story` (items with
"act" id, "told", "say", "choices": [{"text","after"}]) -- ours stand until
then. Shen, the rival, appears in `valley_rivals()` when the flag
`rival_shen` is set, until beaten.

**Companions and pets grown up** (`data/companions.json`). A companion fights
in a STYLE you pick at their side (striker / guard / scout), carries GEAR you
hand them (it shows in their hand), LEVELS with strikes and kills, has a life
bar (down for 90 s, or until you rest). A familiar EVOLVES -- grown (bond 40),
fierce (100), spirit beast (170): bigger, a bite, more of what it gives.
TAMING is a skill (feeding, finds, bites) with a TREE: one choice of two a
tier (Keen Nose / Sharp Fangs; Thick Hide / Quick Paws; Pack Bond / Wild
Call). HOME grows at the sign: cottage (350 gold + ore and resin; rest lasts
twice as long), courtyard (a cultivation stone of your own), compound
(quarters and a kennel: companion xp and familiar bond while you're away).

Tests: `tools/playtest.gd` steps 53-57 (1027 checks). Steam achievements for
the story acts (`story_<act>`) and the home (`home_<stage>`) are listed by
`tools/steam_achievements.gd`.

## Sound, the front door, and the first hour (round 31)

Robert, 2026-10-03: "Keep polishing and building now."

- **Sound** (`scripts/core/Audio.gd`, Game.audio): music by place -- the village,
  the valley and towers, the dungeon, the deep (floor 10+), the title --
  slow pentatonic loops that are ours (`tools/music_gen.py` renders them:
  guzheng-like plucks and a flute over a drone; run it to make new ones).
  Sounds are Kenney's CC0 packs (`assets/audio/sfx/`): swings, hits,
  parries, steps on grass or stone, mining, herbs, coins, chests, doors,
  the UI, and jingles for level-ups, achievements, a cleared trial, the
  blood waking, a death. `Game.sfx("hit_flesh")` picks one of
  hit_flesh1..n.ogg; `Game.sfx_at(name, position)` fades with distance;
  `Game.jingle("levelup")`. Menu: Music and Sounds, 0-10. Headless: silent.
- **The title screen** (HUD.show_title): Continue (with where you are) /
  New game / Settings / Quit, over the world. It blocks play until chosen,
  and in a browser the click is what lets the music start.
- **First steps** (Game.first_steps): for the first 90 minutes the goal
  line walks a new player through one thing at a time -- talk to Elder Mo,
  open the bag, get a weapon, take the stairs, read the journal, meditate
  -- then it's gone for good (flag fs:done).
- **The Steam build on the box**: say "build the steam version" -- Godot
  Studio exports the "Windows (Steam)" preset with the Windows template in
  `godot_vendor/templates/` into `data/godot_steam/<game>/` (exe, pck and
  the Steam DLLs: the folder SteamPipe uploads).
- Dev's words for the daily trial's twists and the world events: the
  writing room's "trial_twists" and "world_events" briefs
  (`data/drafts/*.json`); the game uses them over the defaults.

## Bloodlines, and what keeps you coming back (round 30)

Robert, 2026-10-03: "we don't want a boring game we want it to keep people
coming back" -- "allow for bloodlines to be introduced sometimes around floor
20 ... percentages based with milestones ... only one dominant and one
secondary ... legacy inheritances or a natural bloodline that shines through
... percentages based to determine if a player starts with one or has a
hidden one" -- "Integrate steam".

**Bloodlines** (`data/bloodlines.json`, Game.gd "bloodlines").
- Ten lines (Azure Dragon, Vermilion Phoenix, White Tiger, Black Tortoise,
  Qilin, Nine-Tailed Fox, Golden Crow, Kunpeng, Asura, Starborn Lattice),
  each with an element, a colour, KIN (words in foes' names), and gifts at
  10/25/50/75/100% purity (cumulative). At 50% each has its power: Phoenix
  rebirth once a day, Tiger telling blows, Fox slipping blows, Crow burning
  blows, Asura fury when badly hurt, Qilin second shares of loot...
- Birth (new game): `start.visible_chance` (8%) are born with a line,
  `hidden_chance` (25%) carry a hidden one, the rest have none.
- It all sleeps until the deep: each save wakes at a floor between
  `awaken_floor` (18-22). Then a born line comes alive, a hidden one SHINES
  THROUGH, and with nothing at all there's a `natural_chance` (30%) a faint
  line surfaces. A window says so.
- One DOMINANT (full gifts) and one SECONDARY (half gifts, refines at 0.6x).
  A third line asks: replace the secondary, take it as dominant, burn it to
  feed the dominant, or let it go. The secondary can take the lead once a day.
- Purity rises from: drops of old blood (`essence_<line>` items -- bosses and
  elites from floor 20, more on a Blood Moon or Heavenly Sign, the Trial
  Board), dead masters' legacies (`Inheritance` -- a level file can name one:
  `"grants": {"bloodline": "azure_dragon"}`; otherwise a 40% chance deep
  down), defeating kin, breakthroughs, sitting at shrines.
- Dev's words: the writing room's "bloodlines" brief writes each line's name,
  description, first sign and power (`data/drafts/bloodlines.json`), and the
  game uses Dev's words over the defaults automatically.
- Effects: six new additive keys any technique or gear can use too --
  crit_chance, dodge_chance, burn_on_hit, loot_luck, rebirth, low_hp_fury.

**Coming back** (`data/retention.json`).
- THE DAILY TRIAL (`scripts/world/TrialGen.gd`, level id `trial:<date>`): the same
  one or two twists for everyone that day (Blood Moon, Glass Edge, Swarming
  Halls, Ironhide, Quickened, Spirit Tide, No Mercy, Veterans), built to the
  deepest floor you've reached. Clear every foe for gold, insight, trial
  marks and the streak. Missing a day only wears the streak down by one.
  Retries go for a better score (Steam leaderboard per day).
- THE WEEK: three sect trials a week, counted from what you do anyway (the
  play log's events).
- THE TRIAL BOARD (`scripts/objects/TrialBoard.gd`), by the fountain in Eliet: the
  trial, the week, the marks shop, collections, your blood, ascension.
- COLLECTIONS: bestiary, beasts, materials, landmarks, discoveries,
  bloodlines; marks at 25/50/75/100%; "almost there" nudges in the goals.
  The bestiary is also strength: 10 of a kind +4% damage to it, 50 +10%.
- RARE WORLD EVENTS (from floor 2): Blood Moon, Spirit Tide, a Wandering
  Master (`scripts/actors/WanderingMaster.gd`), Meteor Fall (star iron), a Treasure
  Spirit, a Heavenly Sign (blood). Decided once per floor per day, likelier
  the longer it's been since the last.
- ASCENSION (from floor 25 or Core Formation): begin again from Eliet,
  harder (+25% per ascension) and richer, keeping achievements, collections,
  trial marks and streak, known materials and formulas, heirloom gear and
  60% of your blood. Heavenly marks buy permanent boons.

**Steam** (`scripts/core/SteamLink.gd`, `addons/godotsteam/`, `steam/README.md`):
achievements (every one in data/achievements.json + the round-30 ones --
`tools/steam_achievements.gd` writes the list), stats, leaderboards, rich
presence, Steam Cloud saves. Off unless the export has the `steam` feature
(the "Windows (Steam)" preset) or Menu > Steam is on. App ID: project
setting `steam/app_id` (480 = Valve's test app until there's a real one).
The web build leaves the plug-in out.

## Smooth bodies, effects, and the phone (round 29)

Robert, 2026-10-03: "More detail more realistic if possible. Can we make them
less blocky and more smooth we also want good effects. Is there a way to make
this cross platform or at least allow me to play and test through my phone?"

**Monsters** (`scripts/actors/Monster.gd`). The blocky Kenney orc is gone at Medium
graphics and up. What a monster is built as comes from words in its NAME:
- **imp** (imp, wisp, sporeling, drakeling, thornling, ghoul, stalker,
  spider...) and **puglin** (goblin, brute, shambler, chief...): Quaternius'
  Bestiary models in `assets/characters/monsters/` (free under the Quaternius
  Asset License -- `assets/characters/LICENSE-bestiary.txt`). Same skeleton
  as the people, so the same animations move them.
- **golem** (golem, guardian, sentinel, juggernaut, colossus, warden,
  keeper, soldier, sentry...): a full human body in a SKIN.
- Skins, also from the name, on golems and on "human" monsters: stone, clay,
  metal (brass, clock, gear, nanite), crystal (crystal, shard, glass,
  mirror, frost), bone (skeleton, bone), bark (root, thorn, vine), ember
  (cinder, slag, furnace, ash -- glows in the cracks), spectral (wraith,
  shade, ghost, spirit, reflection -- half see-through).
So a new monster in `data/enemies.json` called "Frost Golem" is a crystal
golem with no extra work; "Bog Goblin" is a puglin. Name things for what they
are. Low graphics keeps the old Kenney figures. (The full Bestiary -- 7
monsters -- is a paid pack; only the free two are here.)

**Animals** (`scripts/actors/Beast.gd`): every `"model": "beast"` is built to its
kind from the name -- hare, boar, stag/goat, ferret/mole/rat/fox/wolf,
lizard/salamander/newt, toad, crab/beetle/spider, bird/crow/crane/moth, worm
-- smooth shapes, fur/shell surfaces, legs that walk as fast as it goes, a
tail that sways, wings that beat, and it falls on its side when it dies.
Unknown names get the ferret body.

**Effects** (`scripts/fx/FX.gd`): sparks where blows land (warm from a blade,
blue from qi, orange from a burn, red when YOU are hit), your blade's sweep,
a parry's ring, a death's smoke with qi motes rising, bodies settling into
the ground, dust when you land hard or a charger runs, a thunderous stamp's
shockwave, embers around elites and bosses, glowing trails on thrown bolts.
They're only pictures: nothing waits on them, they do nothing under the
headless check, and Low graphics gets fewer particles and no flash lights.

**Phone and game pad.**
- `scripts/ui/TouchUI.gd`: on a touch screen (or Menu > Touch controls: on), a
  stick appears under your left thumb (push all the way to run), the right
  thumb looks, and buttons press the game's own actions (ATK, GRD, JUMP,
  USE, STEP, ART, SWAP; along the top MENU, CAM, BOOK, MER, BAG, MED, SALVE,
  PILL, GOURD). While a window is open only the window takes taps, plus a
  CLOSE button. On a phone the screen is laid out 600 tall instead of 720 so
  the words are bigger; the bag scrolls.
- A game pad works everywhere (`Game._setup_pad`): left stick walk (click to
  run), right stick look (click: camera), A jump, X attack, B step, Y use,
  LB guard, RB qi art, RT attack, LT flying sword, d-pad salve / pill /
  meditate / switch art, Back the bag, Start the menu. Windows take the
  pad's focus.
- **The phone version** is the game built for a web browser. The box builds
  it (`godot_web.py` in HomeAI; say "build the phone version of my godot
  game Dungeon Crawl Eliet") and Godot Studio serves it at
  `http://<box>:9214/play/dungeon-crawl-eliet/` -- over Tailscale on the
  phone. In a browser the game asks the box's model through that same
  server (`/api/llm_chat`), since 127.0.0.1 is the phone. The phone keeps
  its own save.
- Things to know for the web build: anything read straight from disk is NOT
  in an exported game. `assets/textures/` used to carry a `.gdignore` and
  was read raw -- the phone version had white ground. It's imported now
  (lossy, with mipmaps). Textures import "lossy" (WebP) now so the phone's
  download is about 100 MB, not 350. `export_presets.cfg` is the Web preset;
  the box points its template lines at `godot_vendor/templates/` itself.

## No two fights the same: styles, elites, rivals (round 28)

Robert, 2026-10-03: "keep working on the game, build it out now, make it
more diverse". Everything is in `data/foes.json` (new, Claude's) and
`scripts/actors/Enemy.gd`.

- **Styles** -- how a monster fights:
  - brawler: closes in and hits
  - ranged: keeps 5-9 m away and throws a bolt you can see coming
    (`Bolt.gd`; step aside, guard, or parry)
  - charger: a ring on the ground warns of the wind-up, then it runs at where
    you WERE
  - guardian: turns your blade from the front -- go round it or use arts
  - skulker: unseen until close; its first blow hits 1.6x
  - swarmer: brings two young
  - mender: heals the others -- kill it first
- **Where a style comes from:** enemies.json `"style"` if the forge sets one,
  else words in its name (`foes.json` "keywords": a knight guards, an imp
  throws), else its id picks one (the same every time). Bosses and passive
  animals always brawl.
- **Variants:** from floor 2, about 30% of placed foes take another style
  ("Goblin Slinger", "Charging Skeleton").
- **Elites:** from floor 3, 5% + 0.5%/floor (max 20%) are ELITE -- gold name,
  a coloured aura, 2.2x health, 1.25x damage, 3x qi, a 40% gear drop -- with
  one affix (two from floor 8):
  - swift
  - armoured (-40% damage)
  - venomous (poison that never finishes you)
  - vampiric
  - frenzied (faster under half health)
  - splitting (two lesser ones when it dies)
  - warding (your arts' statuses hold half as long)
  - thunderous (a warning ring, then a stamp)
  - gilded (far more gold)
- **Floor 1 stays plain** -- it teaches the basics.
- **Rolls are seeded** by level, cell and kind, so a floor is the same while
  you're on it.
- **Bosses:** at half health a boss is ENRAGED (faster, attacks sooner).
- **Rival disciples** (`scripts/actors/Rival.gd`): three disciples from sects that
  aren't yours wait by the valley roads (new names each day). E asks for a
  bout -- to a YIELD at 15%, nobody dies.
  - Their sect's element sets their style: fire charges, metal guards, wood
    throws, water mends, earth brawls.
  - A win pays gold, qi, insight (+2) and sect contribution.
  - Each rival takes you on once a day.
  - `Game.rivals` keeps the record (shared with the tournament rivals).
- **Insight:** an elite kill gives +1 insight.

## Gear for the whole body, materials, the bench and the nanoforge (round 27)

Robert, 2026-10-03: "an actual inventory with an equipment dummy ... 4 rings
per hand, one bracelet on each wrist, one choker, one necklace, 2 toe rings,
boots, greaves, pauldrons, gloves, vambraces, gauntlets, chest, pants,
under-armour, robes that can be on the outside of armour, cape and cowl ...
nano tech or crafted or both ... a nanotech crafting tree ... all items
combined in some way ... recipes bought or created through trial and error
... attributes that can be combined to create synergistic effects or
improve the odds of success, failure and unexpected benefits."

- **Slots** (`data/gear.json` "slots", 27 of them). `Game.equipment` is
  slot -> item id; `armor`, `ring` and `amulet` are the old names for the
  chest, first ring and necklace slots and still work. `Game.wear(id, slot)`,
  `Game.unequip(slot)`. A piece found goes on by itself if its slot is empty
  (or it's clearly better armour). Selling or using up something you wear
  takes it off.
- **What armour does:** health (`hp`), WARD (a blow loses ward/(ward+200)
  of itself, `Game.ward_factor`) and WEIGHT. Over what you can carry
  (22 + 9 a realm + a little a step) you move and swing slower, up to 25%.
  Jewellery gives gifts; the same gift on many pieces counts for less
  each time.
- **The catalogue is generated** from gear.json, not written into items.json:
  `g_<stock>_<family>` (e.g. `g_iron_ore_greaves`) for every stock material x
  every kind it can make, and `j_<metal>_<gem>_<family>` jewellery. They drop
  (45% of gear drops are now body pieces or jewellery) and are forged.
- **Materials** (`data/crafting.json`): each has an element and traits --
  hard, supple, vital, keen, conductive, resonant, warding, volatile,
  binding, nano, seeking, living. A material with no entry (the forge adds
  new ones) gets traits from words in its name and description
  (`Game.material_traits`). You only SEE a material's traits once you've
  worked it, studied it (Pack: Study -- costs one), or know a craft well.
- **The bench** (`Game.combine_attempt(base, adds)`; Pack -> Bench tab):
  up to three things into one. Gear + materials = the piece infused
  (affixes from the traits; 2-5 infusions by quality). Materials together =
  an alloy (traits of all, synergies strengthen them; forges like its first
  material, a tier better). A consumable + materials = a stronger one. Two
  of the same kind of piece = one (needs the Singularity Forge). A known
  FORMULA (15 of them) makes its product.
  - Odds: skill, binding (+), volatile (-, unless a Caged Storm binds it),
    elements that feed each other (+) or fight (-), knowing the formula
    (+22%), a real bench (no bench: -12%), the nanoforge.
  - Surprise chance: volatile, resonant, fighting elements. A lucky success
    adds a synergy you didn't put in, or doubles the yield; a lucky failure
    shows you the formula you were reaching for.
  - Failure costs what you worked in; volatile and unbound, it can scorch the
    piece itself.
  - Formulas: bought as scrolls (merchants in the trade screen; smiths and
    alchemists in their workshop menus) or found by putting the right things
    together.
- **Forge** (`Game.forge_piece(family, stock, gem)`): any kind of piece from a
  stock you carry; jewellery from a metal set with ANY material (its traits
  are the gift).
- **Nanoforge** (`data/nanotech.json`, 13 nodes): unlocked with nanite shards at
  your swarm's tier. Nanoweave, lattice plate and swarm-shell (nano armour,
  light), circuit jewellery, Adaptive Skin (crafted+nano "both" pieces 25%
  stronger), Self-repair (health back per nano piece), Catalysis, Resonance
  Tuning, Swarm Reservoir, Phase Weave, Swarm Shell, Singularity Forge. Two
  are secrets: Neural Lace (work storm glass and a nanite shard together)
  and Entropy Harvest (fail five times).
- **The pack screen** (`scripts/core/Kit.gd`, I): a turning dummy of you wearing
  everything, the slots around it, and tabs: Pack, Bench, Forge,
  Nanoforge, Formulas. Your home workbench and a smith's or alchemist's
  workshop open it at the bench.
- **Our own models** (`scripts/actors/Armour.gd`): every piece is built from shapes
  pinned to the person's bones, with textures drawn from noise (brushed
  metal, grain, weave, glowing circuit and hex lines for nano pieces). A
  hood hides the hair; a cape sways and streams behind you (`CapeSway.gd`).
- **Smoother motion:** between physics ticks your body and camera are drawn
  part-way between the last tick and this one, and animations ease into
  each other.

## Graphics, art and the camera (round 17)

Robert, 2026-10-02: "are we able to sharpen the graphics some" ... "I want
the game to be as close to Morrowind or Skyrim in style".

- **Presets** (`scripts/core/Gfx.gd`, Esc menu -> Graphics; kept in
  `user://settings.json`, not the save): Low is the original look; Medium
  adds anti-aliasing, sharp textures, photo-scanned props, ambient
  occlusion, bloom and a colour grade; High adds rough/AO detail on stone,
  bounce light, volumetric fog underground, torch shadows near you and a
  real (HDRI) sky over Eliet; Ultra adds global illumination (SDFGI) and
  bigger, softer shadows. Window: fullscreen / windowed.
- **Photo-scanned props** (`scripts/core/Art.gd`, models in
  `assets/realistic/<id>/`, Poly Haven, CC0 -- `manifest.json` lists every
  source): `Art.make("mini-dungeon/barrel.glb")` returns a stand-in fitted
  to the Kenney model's own size and footing, so levels never move.
  `Art.SWAP` says which Kenney model gets which stand-ins; `Art.REMAT`
  lays a photo texture over Kenney shapes that have no stand-in (houses,
  roofs, columns). Always load props through `Level._prop` / `Art.make`,
  never `load("res://assets/kenney/...")` directly, or Low/High stop
  working.
- **People** (`scripts/actors/Human.gd`, round 18; assets in `assets/characters/`,
  Quaternius, CC0 -- LICENSE files there): realistic men and women, ~1.8 m,
  built from the Universal Base Characters' HEAD + a Modular Character
  Outfits suit (peasant or ranger, two colourways, tinted to the person's
  robe/apron colour) + hair and beard, all on one shared skeleton, animated
  by the Universal Animation Library under the game's own names ("idle",
  "walk", "sprint", "jump", "sit" = cross-legged on the ground,
  "attack-melee-right", "die", "cast", "roll", "talk", ...).
  `Art.person(spec)` gives a person for a `Dress.spec_for` spec (realistic
  at Medium+, the Kenney figure at Low); `Dress.dress(model, spec)` then
  adds hats and the weapon in hand. Never `load(".../character-human.glb")`
  directly. Monsters are still Kenney models.
- **Camera** (C, or Esc menu): far third person, over the shoulder, first
  person (your body is hidden from your eyes, its shadow isn't). In the two
  close views you face where you look, and the wheel swaps between them.
- New .gltf/.hdr assets need Godot's import step: the bridge runs it
  (`godot_bridge.unimported_assets`), the game falls back to Kenney until then.

## Where the game is going (Robert, 2026-10-02)

- **Style:** as close to Morrowind / Skyrim as we can: grounded, realistic
  materials, real skies, first/third-person.
- **The world beyond the dungeon:** one open valley around Eliet that grows
  outward -- towers to climb and sects in the hills, as other ways to
  progress. The dungeon stays the primary way, not the only one.
- **Cultivation, made unique, with a biotech/nanite side:** active ki arts
  (attack, defence, movement), developed over time through practice,
  meditation and use, and laid out as a skill tree. Designed with Robert
  before it's built.
- **Next:** realistic characters to match the props (rigged, CC0), then the
  valley, towers and sects.

## Downtime: always accomplishing something (round 16)

Robert, 2026-10-02: "focus on afk and downtime portions of the game that
way the user always feels like they are accomplishing something." Five
things keep moving when you're not fighting (all in the "downtime" block at
the end of `scripts/core/Game.gd`):

- **Time away** (`away_task`, `resolve_away`): before leaving (Esc ->
  "Plan your time away", Quit asks too, or the bed at home) you pick
  meditate (3x qi), train a skill, go out gathering, or work through a
  crafting queue. On load, up to `AWAY_CAP_HOURS` (12) count; the result is
  `Game.away_report`, shown by `HUD.show_away_report()`.
- **Expeditions** (`start_expedition`, `check_expedition`): send your
  companion (talk to them) or familiar (E on it) to a floor you've been to
  for 1/2/4/8 real hours. They're gone from your side
  (`companion["away"]` / `familiar["away"]`) and come back with gold, that
  floor's monster drops, sometimes gear, and a story.
- **Home** (`scripts/world/Home.gd`, placed in the village by
  `Level._place_home()`): a garden that grows in real time (3 -> 6 -> 9
  beds), a workbench queue (one piece every `queue_period`, from pouch then
  chest), a chest (stash), and a bed (`rest_at_home`: well rested = +10%
  qi and skill growth for 30 min).
- **Daily bounties** (`bounties_today`): three a day (a kill, gathering,
  crafting), paid the moment they're done; days in a row make a streak.
- **Achievements** (`data/achievements.json`: id, name, desc, stat, need):
  each is +0.5% to all growth, forever (`growth_mult`). The stats are the
  ones `achievement_value()` knows; anything else is read from `counters`.
  You can add achievements as data.

The top-right line under the place name (`Game.next_goals()`) always says
what's waiting or what's next. The journal (N) has a Goals section.
Balance knobs are the constants at the top of the downtime block.

## Looks

The human model's head is shrunk to 72% (`Game.HEAD_SCALE`, Robert: "its
obnoxiously large") for you, townsfolk, companions and rival cultivators --
`Game.shrink_head(model)` on any new human model.

## Easter eggs (don't spoil them for Robert)

The village fountain counts coins (and the 33rd coin brings back more than
gold). The Founders' Stone. The unreadable stone on the plaza. The cold
stone in the warrens' great hall. Add your own: an odd lore stone, a villager with a secret.

## Learning from play

The game writes what happens to a play log (user://playlog.jsonl): every
kill, death (and what killed you, where), chest, secret, lore stone,
technique, quest, and how long each floor took. Godot Studio summarises it
for Dev ("how is the game playing"). Use it: a floor where everyone dies in
the same room is too hard; a secret nobody finds is too hidden; a floor
finished in two minutes needs more in it.

## The plan for floors 2-4 (Dev's job)

| floor | name | theme & feel | regular enemies | boss (last room) | special |
|---|---|---|---|---|---|
| floor2 | The Bone Crypt | tombs, long halls of columns, side burial niches | `skeleton`, `skeleton_knight` | `bone_lord` | bone shards; a hidden ossuary with the stone that teaches `mountain_breath`; a hidden chest; a secret passage |
| floor3 | The Drowned Seam | an old silver mine, flooded (`~` water), narrow tunnels | `mine_crawler`, `drowned_miner` | `foreman_golem` | lots of ore `o` (deep ore is silver); a miner's prayer stone teaching `silver_vein`; an inheritance granting `jade_pendant` |
| floor4 | The Nanite Sanctum | where the nanites came from: a great central chamber | `nanite_wraith`, `sanctum_sentinel` | `corrupted_warden` | a shrine `Z` before the boss; the stone teaching `nanite_resonance`; an inheritance granting `lotus_seat`; the best chest in the game |

Stairs: floor2 `<` goes to `floor1` arriving at `>`; floor2 `>` goes to `floor3`
arriving at `<`; and so on. floor4 has a `<` only (it's the deepest for now) --
or a `>` to `floor5` for later, which is allowed: the stairs just say "still
being built".

Difficulty climbs with depth; the monsters in data/enemies.json are already
balanced for it (floor 2 for Body Tempering 5-10, floor 3 for Qi Condensation,
floor 4 for Foundation Establishment).

## The plan for floors 5-10 (Dev's next job)

Below the tortoise the dungeon walks the five-element cycle -- each floor
leans on one element (its plants, its stone, its monsters, what it drops),
and the pills made from it attune you to that element.

| floor | name | element & feel | regular enemies | boss (last room) | animal to hunt / tame | special |
|---|---|---|---|---|---|---|
| floor5 | Shellhaven | water -- the town on the tortoise | none | none | -- | settlement (see above) |
| floor6 | The Strangling Grove | wood -- an old sect garden a spirit-tree swallowed: root-halls, a drowned orchard, a seed vault | `thornling`, `rootbound_monk` | `grove_mother` | `moss_stag` | herbs everywhere; `spirit_resin`, `heartwood`; hidden lore teaching `evergreen_body` |
| floor7 | The Ember Forges | fire -- a dead sect's foundry whose fires never went out: slag rivers, anvil halls, bellows | `cinder_imp`, `slag_brute` | `furnace_sovereign` | `ember_salamander` | `firestone` veins `^`; ore; an anvil lore stone teaching `ember_meridians` |
| floor8 | The Terracotta Barrows | earth -- an emperor's buried army of clay soldiers, standing in ranks: barrow halls, a chariot pit, the tomb | `clay_soldier`, `clay_cavalier` | `buried_emperor` | `burrow_mole` | `ancient_clay`, `emperor_jade`; the general's drill book teaching `terracotta_stance` |
| floor9 | The Sword Grave | metal -- a valley where sword cultivators came to die, ten thousand swords standing in the ground | `sword_wraith`, `grave_keeper` | `sword_saint_shade` | `steel_crow` | `grave_steel`; an inheritance (the Sword Saint's last disciple, hidden, needs_realm 3) granting `sword_intent` and the `saints_sheath` treasure |
| floor10 | (next settlement) | water returns -- a floating market on a black underground lake | none | none | -- | settlement for floors 11-14 |

Each dungeon floor: 12-20 rooms of varying size, 12-25 monsters of ITS floor
only, one boss in the last room by `>`, 4-6 chests (one hidden, one in a
secret room), 8+ things to gather, 1-2 glittering veins `^`, a fishing spot
`&` where there's water, a riddle stone `?`, two lore stones (one telling the
place's story, one hidden that teaches), 2-4 corridor traps, one or two
animals to hunt. Stairs: `<` up arriving at the floor above's `>`, `>` down
arriving at the floor below's `<`.

## Adding a monster (data only)

Add an entry to `data/enemies.json`:
`"ghoul": {"name": "Ghoul", "model": "human" or "orc", "tint": [r, g, b] (0-1),
"scale": 1.0, "hp": 60, "damage": 12, "speed": 3.2, "aggro": 9, "range": 1.8,
"cooldown": 1.3, "qi": 25, "loot": {"bone_shard": [0, 2], "gold": [4, 9]},
"boss": true (only for a boss)}`. Then use it in a level's `"enemies"`.

## Cultivation (why the numbers matter)

The player's growth is cultivation, not XP: five realms (Body Tempering, Qi
Condensation, Foundation Establishment, Core Formation, Nascent Soul), each 10
sub-levels; the nanites are how it works (Nanite Seeding, Bloom, Lattice,
Core, Ascendance). Qi comes from kills, chests, secrets, herbs, crafting,
quests, pills, and meditating (M anywhere; much faster at a shrine `Z`, and
it keeps going while the game is closed if you quit sitting at a shrine, up
to 8 hours). HP and damage come from cultivation + gear.

## Checking your work yourself

- `python godot_levels.py <project folder>` -- the rules check for every level.
- Godot: `--headless --path . --script res://tools/smoke.gd -- floor2` builds a
  level in the real engine; `tools/playtest.gd` plays floor 1 and the village;
  `tools/shoot.gd -- floor2 <folder>` saves screenshots.

## Things that went wrong before (so they don't again)

- The first version of this project "passed its checks" but could not run:
  no floor, no camera, `Main.tscn` used node types Godot can't load, and a
  `.tscn` file contained GDScript. Parse checks only prove the text parses.
  That is why levels now go through a real build (`smoke.gd`) too.
- Godot 4, not Godot 3: `@export` (not `export`), `move_and_slide()` takes no
  arguments, `CharacterBody3D` already has `velocity` (don't declare it).
- Don't promise work in chat that isn't running. Say "keep working on the
  game" to run the next real job; "how's the game" reads the real state.
- 2026-10-02, floor 2: five rooms pasted in as identical "Ossuary Gallery"
  copies to reach a room count, a riddle defined but put in no room, and the
  same technique taught by a lore stone and the inheritance. Copies are now
  removed automatically and the rest is flagged -- every room is its own
  place, with its own name, size and reason to go in.

## Round 63 (2026-10-05): quick travel, pursuits, great distances, the apps' look -- and Dev's own workshop

Robert: "Make sure Dev is doing some of the lifting too" ... "make sure the down time is actually useful and regulated so it's not abused -- it should be what you do when the game is running but you are AFK or while the game is off: the character can be moving towards goals" ... "the sense of distance, smooth lines and curves -- the illusion of great distances" ... "give the whole GUI/HUD a revisit, along the lines of the rest of the apps' style" ... "quick travel to any location they have conquered and found the quick travel [stone] for."

- **Waystones and quick travel** (`scripts/systems/Travel.gd`, `scripts/objects/Waystone.gd`, `data/travel.json`): every place you can return to has a waystone -- Eliet by the fountain, the valley and every town where you come in, each dungeon floor beside its way DOWN (`Level.waystone_center()`, past its master). Walk up to one: ATTUNED (Dev's carved words, brief `waystone_words`). A floor is a destination once its master has fallen (`counters["boss_floor:N"]`); towns at once. From a waystone a trip is instant; from the menu (Quick travel) only when safe and after 2.5 s of gathering yourself -- a blow breaks it. You arrive at the destination's stone (spawn tag "waystone").
- **Pursuits** (`scripts/systems/Pursuit.gd`, `data/pursuit.json`): the away task now has a GOAL (train to level N, bring back N, until the next breakthrough); reached -> rest. Game closed: worked through in 15-minute steps, a timeline report (with a moment in Dev's words, brief `pursuit_moments`). Game open and you've stepped away (90 s without input, nothing near): your character pursues right there, a chip on the objectives card says how it's going; any input ends it with a line of what got done. Regulated: a pursuit BANK (start 6 h, max 12, refills ~10 h a day, spent by pursuing either way), diminishing returns over a stretch (100% / 75% / 50%), and a high-water clock (wind the clock back: nothing counts; forward: you only spend the bank early). Tests that fake time away must move the save's `systems.pursuit.high_water` back too (`_rewind_pursuit` in tools/playtest.gd).
- **Great distances** (`assets/shaders/terrain.gdshader`, `assets/shaders/far_ridge.gdshader`, `Horizon.gd`, `Level._build_road_mask()`): under the sky the map's ground IS the land's ground (one world-space shader, `Horizon.land_material(level)`), so the village no longer sits on a pale plate. Roads are drawn into it from a mask (1 px a metre) with soft, curving edges, and every road that ends near the map's edge runs on out across the land (the north one to the sect pagoda). The ring of mountains opens in passes (`horizon.json land.passes`), and through them three rings of far ranges stand 600-1800 m out, paler with distance. Frost's snow lies in the ground shader (`snow_cover`), not a pale sheet. Underground, past the rock's edge: columns into a vast dark, far lights, mist (`horizon.json cavern`).
- **The apps' look** (`data/ui.json`, HUD): the HomeAI apps' palette (slate #171922 cards on #0f1014, hairline #262a36, #eceef5 text, #8b91a6 secondary), rounder corners, pill chips; Cinzel only for big titles (24+). The stat card, an objectives card (level name, goals, the pursuit chip), the message log as soft pills, the pause menu grouped (PLAY / SETTINGS / THE GAME, `HUD._section()`).
- **Dev's game workshop** (box: `godot_workshop.py`): Dev now codes the game itself, slowly, between the forge and the writing room. Tasks queue in `save-data/godot-workshop.json`; Dev writes FUNC/APPEND/FILE edits with the box's own model (Gemini after 2 failed local tries), and each try runs in a sandbox copy (own user:// folder): parse, boot, its own `tools/dev_checks/<id>.gd`, the full playtest (no new failures vs the game as it is) and the level smoke test. All green -> applied with a backup (`.backups/workshop-<id>-<stamp>/`), "undo Dev's last game change" puts it back. Lessons from every fix that follows a failed try are kept and shown next time (`save-data/godot-workshop-lessons.json`, also `godot_build_journal/DEV_GODOT_LESSONS.md`). **Before a cloud deploy, pull what Dev changed:** `python godot_workshop.py changed <unix time of the last deploy>`.

## Round 64 (2026-10-05): Dev plans and finds its own game work

Robert: "I really want Dev to weigh in more with the coding so I can utilize you for other things." He chose: Dev plans directions itself AND finds its own small work; "will end up utilizing user reports for Dev to fix"; free model first, the cheaper new Gemini when it saves time and money.

- **Directions** ("in my godot game Dungeon Crawl Elite, focus on <anything>") go to `godot_workshop.plan_focus()`: the local model (Gemini if it can't) plans 1-6 small tasks (<=2 files each) from a map of the project (every script's functions, the ones that sound like the request first); each runs through the workshop's full gate; one phone alert with the plan, one when the whole focus is done. Projects without a playtest keep `godot_director`.
- **Bugs in words**: "bug in the game: ...", "report a bug: ...", "in my godot game X, there's a bug: ..." -> `report_bug()` -> planned into a fix.
- **Report a problem** (pause menu, HUD.open_report/save_report): writes `user://bug_reports/r_<time>.json` with the words, version, level, position, what's on screen and the last 25 play-log events. On Robert's PC the workshop reads them straight from `%APPDATA%/Godot/app_userdata/Dungeon Crawl Elite/bug_reports`; reports from anywhere else go in `data/godot_bug_reports/` (.txt or .json).
- **Dev finds its own work** when the queue is empty (`find_work()`): reports first (each once, not capped); then SCRIPT ERRORs the game actually hit in play (Godot's own log, `.../app_userdata/Dungeon Crawl Elite/logs/godot*.log`); then playtest checks that fail in the game as it is. At most 2 self-given tasks a day.
- **Gemini**: switched to gemini-3.8-flash (half price until 2027-01-01) with the daily cap doubled to 80,000 tokens -- the same money as 40,000 before. `promo_guard()` puts the cap back to 40,000 by itself on 2027-01-01 and buzzes Robert. Backup: `save-data/cloud-helper.json.bak-promo-20261005`.

## Mysteries and treasure hunts (2026-11-03)

Robert: "more mystery and intrigue -- a treasure hunt, a whodunit, conspiracies, secret societies." They are side quests
kept in their own file, `data/mysteries.json`, written by `tools/gen/mysteries_gen.py` (edit the generator, run it, never
hand-edit the JSON). `scripts/systems/Quests.gd` (`_mysteries`) reads them. Six so far: The Empty Strongbox (Eliet ->
Shellhaven), The Founders' Cache (treasure: the fountain -> the ford -> Floor 1 -> Floor 3), The Cut Lift Rope
(Shellhaven), The Ninth Lamp (the deep's secret society), The Missing Stags and The Cartographer's Last Map (the Lands).

What a mystery can say that an ordinary side quest can't:
- `"kind": "mystery"` or `"treasure"` -- the Quests page files them under Mysteries / Treasure hunts, and a clue opens
  a page to read instead of flashing past.
- `find.place`: any place -- `"village"`, `"valley"`, `"floor5"`, `"frontier:whisperwood"` -- not only a floor number.
  Towns hold a quest's thing too, but only where the quest says (`near`).
- `find.near`: where the clue lies, so the words can point at it: `"fountain"`, `"water"`, `"stairs"` (the way down),
  `"spawn"` (where you arrive), `"lore"` (the place's lore stone), `"npc:<their name>"` (by that person), or one map letter.
- `find.subtle`: a treasure hunt's find has no diamond until you are about six metres from it. The stage's `log` is the
  riddle -- write it so a player who reads it can walk there.
- `"clues"`: every clue is an item with its own words; the player reads it in the bag, and the accusation lists them.
- `choices[].needs`: a charge you can only make holding the proof (`{"mc_lotus_tally": 1}`, or `{"gold": 90}`).
  Without it the choice isn't offered and the dialog says something unfound would let them say more. Always leave
  at least one WRONG choice that is open to everyone -- guessing has to be possible, and has to cost.
- `"reward": {"pay": 90}` takes gold (an ending you pay for). A negative `bond` is a person who trusts you less.

Rules: every giver and witness must be a real person standing where the quest says (the check reads every level and the
Lands); the demo is floors 1-5, so a mystery the demo should show must stay at Floor 5 or above. Check your work with
`tools/mystery_check.gd` -- it builds every place a clue names and fails if the clue has nowhere to stand.

## The solo world, the Common City, your own world (2026-11-06)

Robert: "is our world too small for solo play" -- it was, about 1.8 km^2 in all. Now:
- **Lands 1.7x per side** (`data/frontier.json`, written by `tools/gen/world_gen.py`; backup `data/frontier.json.bak-world-20261106`),
  each with **groves and caves** inside (`Frontier.gd` `_feature_grove` / `_feature_cave`), and **8 roads** between neighbouring
  Lands (`road_<a>_to_<b>`, with a waystation merchant and a warden). Gate A leads onto the road, the road's gate "1" into B.
- **Floors 6-30 are bigger** (`Expanse.gd`). **Roaming events** in the Lands: a travelling merchant cart and a named roaming
  elite (`data/retention.json` `travelling_merchant`, `roaming_elite`; `wild_mult` 4 makes them more common out there).
- **The Common City** (`levels/city.json`, `tools/gen/city_gen.py`): 176x140, walled, 142 houses; the village's exit `C`.
  Its **auction house** (`scripts/systems/Auction.gd`, `data/auction.json`): list with a 2% fee, the house keeps 8% of a sale,
  buyers come while you are away (`settle()`), daily market lots never cheaper than a trader pays, and what you bought
  there can't be relisted (the mark leaves with the pieces when you sell or use them).
- **Your own world** (`scripts/systems/Worldkeeper.gd`, `scripts/world/KeeperGen.gd`, level `realm:own`): opens with the
  Worldkeeper title or at realm 10; 4-12 plots by realm (house, shrine, pond, grove, herb garden, mine, orchard, lanterns),
  the look of any Land you have walked, a daily tithe. Shaped at the keeper's lectern.
- Checks: `tools/solo_world_check.gd`.

## The CC0 art pack (2026-11-06)

Robert: "Yes, CC0 only" -- free art swapped in, the old look kept as the backup. All of it is public domain;
`assets/cc0/README.md` and `manifest.json` say where each piece came from. One switch: `scripts/core/ArtPack.gd`
`on()` = Medium graphics or higher, not a phone, and pause menu > Graphics fine-tune > "Art: new art packs" (the setting
`art_pack`, "new" / "previous"). Off, every look below is exactly what it was.

- **Houses** (`scripts/world/Houses.gd`, Quaternius Medieval Village MegaKit in `assets/cc0/village/`): every block of
  "H" cells becomes ONE house -- walls with windows, a door on the street side, a second storey on bigger ones, a tiled
  roof the size of the house, gable ends, a chimney (smoke comes from those now). `Houses.fit` splits a block into
  sizes the kit has roofs for; a 1-cell-wide strip keeps the old block. Collision is untouched: every "H" cell is
  still solid with the same box (the check builds the village both ways and compares). Each house shape is built
  once and shared; tiles and plaster get a colour per house.
- **Skies**: ten Poly Haven HDRIs in `assets/sky/`, laid into `sky.gdshader` (`photo`) by day by `ArtPack.dress_sky`,
  picked by the weather, the Land and dusk (`data/art_pack.json` skies/weather/looks/dusk). It fades as the light
  goes, so night keeps the drawn stars and moon. Under a photo sky a Land's fog is thinner.
- **Ground**: ambientCG sets in `assets/cc0/textures/acg_*` (albedo/normal/arm, like the Poly Haven sets; a folder name
  "cc0:acg_x" reaches them through `Look.texture`). `art_pack.json` "land" = a Land's open ground and rock (snow,
  sand, gravel, mud, leaf litter); "surfaces" = a look's floor/wall/road swapped (marble halls, snow, wood floors).
- **Props** (`Art.SWAP_PACK`, "pk:" = `assets/cc0/props/`, "vk:" = `assets/cc0/village/`): stalls, wagons, barrels,
  tables, bookcases mixed in with the photo-scanned ones; `Level._workplaces` sets an anvil by the smith, a cauldron by
  the alchemist, crates by the merchant, a workbench by the guild (looks only, never in the road).
- **Livestock** (`Critter.gd` cow / horse / sheep / pig / llama, Quaternius Farm Animals): herds graze the village, the
  city, the valley and your own world (`Level._place_livestock`), never the wild Lands.
- **Particles** (`Motes.pack_texture`, Kenney Particle Pack in `assets/cc0/fx/`): chimney smoke, mist, sparks, glints.
- The phone exports leave `assets/cc0/` out (`export_presets.cfg`), and `assets/sky/` was already out.
- Check: `tools/art_pack_check.gd` (in the gate). Screens: `SHOOT_HORIZON=3 DCE_ART_PACK=on` with `tools/shoot.gd`
  adds a look along the ground to the horizon; `tools/_house_shot.gd` draws a street of test houses and the animals.

**Performance (same day).** The bigger Lands held ~94,000 nodes -- 56,000 of them the meshes of 5,400 photo-scanned
flower and grass tufts. The open ground's tufts are now drawn in batches (`Level._deco_prop` / `_flush_deco`): each kind
folded into one mesh, one MultiMesh per 32 m patch, nothing past 85 m drawn, no shadows. A Land is ~26,000 nodes now
(fewer than the old, smaller Land). Gather spots' little lights fade out past 32 m. `tools/_landmem.gd <level>` prints
what a level holds by kind and by model.

**Pets wear their barding** (`Beast.barding`, called from `Familiar._build`): hide, iron, jade or spirit-silk over the
back, plates down the spine (more as it grows), a brow-guard; and an evolution is SEEN (`Familiar._transform`: a
turning column of light, a flare, the beast swells into its new body). Preview: `BARDING=iron_barding` with
`tools/beast_probe.gd`.

**Later the same day (2026-11-06):**
- **Music was silent since Oct 13.** Something wrote `data/audio.json` with nothing but `"effects"` -- no `sets`, so no
  piece ever played (nor fight drums, nor per-look ambience). Restored from `.backups/pre-round63-*.tgz`, the effects
  entry kept. `tools/audio_check.gd` (in the gate) now fails if any place has no music or a file is missing.
  Music per place: the Common City and your own world play the town's music; the open Lands play the valley's (green
  ones) or the deep's (strange or ruined ones) from `audio.json` `frontier_music` (they all played the deep's);
  outdoors a Land has its own air (`ambience.outdoor_look`) or the valley's birds and wind.
  **Music style** (Sound menu): "new" = the harmonised pieces (`assets/audio/music2_new`, r117: the tunes' strong-beat
  notes on notes that agree with the chord, 27% clashing -> 1%), "original" = the pieces as first made (`music2`, the
  backup), "classic" = round 31's loops. `Audio.piece_dir()`.
- **The Lands' rock edges** (art pack): every solid cell facing open ground was a 2 m cliff block, and the "rocks" rim
  style was grey boxes. Now photo-scanned boulders (`Level._crag`, batched per 48 m patch, nothing past 170 m), using
  LOW-POLY copies in `assets/cc0/rocks/*_lo.gltf` (~2,000 triangles; made by `tools/gen/decimate_gltf.py` with
  fast-simplification -- a MultiMesh can't use the engine's detail levels, and the full scans are 15k-98k triangles).
  The Lands' big Kenney stones (`rock_large*`, `rock_tall*`, `stone_large*`, `stone_tall*`, `cliff_rock`) take the
  photo rocks too (`Art.SWAP_PACK`). Collision unchanged (checked).
- **Pets grow their role's own body** at fierce, bigger and lit at spirit beast (`Beast.role_form`, `ROLE_BODY`):
  wings (courier, lucky, scholar), shell (guardian, warden, sentinel), great horns and tusks (striker, fury, hunter),
  more tails (tracker, forager, charmer), crystal (digger, hoarder), flame (ember, brewer), light-antlers and a halo
  (lantern, mystic, healer), a crest and long ears (marksman). Preview: `ROLE=courier` with `tools/beast_probe.gd`.
- `tools/shoot.gd`: `SHOOT_AT=x,y` stands the player at a cell.
- **Calmer caves** (Robert: "the dungeon play track with the dripping sounds is a bit much"): the "cave" ambience bed
  (floors 1-5 and every warren-like place) was a high plink every ~2 s; "water" (the flooded halls) 1.4 a second.
  New beds (`tools/music_gen2.py` kinds `cave` / `water`, `far_drip`): warm room tone, slow air through the tunnels,
  a stream far below, the stone settling, a soft low drop every ~12 s; 2.7 dB quieter, high-pitched energy 18% -> 2%.
  The old beds are kept as `cave_classic.ogg` / `water_classic.ogg` (kinds `cave_classic` / `water_classic`) and
  Sound -> "Ambience: classic" plays them (`Audio.amb_file`, setting `amb_style`).
- **Pets move by stage** (note item 5: "idle, walk, bite, deed, down; faster, heavier, more confident as it grows"):
  `Beast.MOTION` (4 rows) -- young is light and quick, glances about, bounces; grown (row 1) is the old motion exactly,
  so every enemy and wild beast moves as before; fierce and spirit beast stride long, land heavy, hold the head high,
  breathe slow and deep, bite faster and further. `Beast.act("bite" | "deed" | "down" | "up")`: Familiar plays the
  bite on its bite, the deed (nose down, then a proud rear) on a find, and lies down beside you while you sit
  (`Game.sitting`); a beast enemy lunges with `act("bite")` on its swing. The per-frame work is `Beast.animate(delta)`
  (headless tests drive it). Check: `tools/pet_motion_check.gd` (in the gate). Preview: `POSE=down|bite|deed|walk`
  with `tools/beast_probe.gd`.
- `tools/playtest.gd` (not in the gate) now compiles under `--script`: its `preload()`s of Reach/Look/Expanse pulled
  in scripts that name the `Game` autoload before it exists, so the whole test failed to compile. Its ~63 remaining
  FAILs are expectations from older rounds (27 wear slots, menu rail order, main-quest start, village rim) -- the same
  set noted on 2026-10-15; the gate's own checks cover those systems as they are now.
- **Spirit beast rebuilt** (Robert: "the final form is kinda childish and bland"). It was the cub's blobs made bigger,
  the whole coat glowing one flat colour, round spots, a party-hat ring of cones, three flat cones for a tail.
  Now (`Beast._spirit_form`, `_beast_body`, `_loft`): wolves/foxes, boars, deer, hares and lizards get ONE smooth
  lofted body (rounded rump, haunch, tucked waist, deep chest, ruff, the head carried up on a neck), lofted legs
  (thigh to ankle, broad paws), a full brush tail (a long tapering one for lizards); coat / darker back / paler belly
  by vertex colour. The cub's blobs stay, hidden, so `_extent` still measures; role parts, barding and lineage marks
  sit on `_torso.get_meta("back_y")`. Light: thin swept flank stripes, soft streamers off the ruff, a plume off the
  tail tip, a pool under it, and a fresnel aura shell (`_aura_mat`; skipped on phones / Low). Birds get fans of
  flight feathers on their own wing pivots and a fanned tail (`_feather_wings`); crabs, worms, toads, golems keep
  their build with stripes and the aura. Lit horns/antlers/crests are shaded bone that glows (`litbone`), not flat
  cut-outs; the shell is scale-plates; role wings are feather fans. Fierce spines are slimmer and swept back.
  Also fixed: `Beast.plan_for` took the first match, and "fox" contains "ox" -- Cinder Fox and Void Fox were built as
  stags; the longest matching word wins now. Check: `tools/pet_motion_check.gd` (173). Look:
  `tools/_final_form_shot.gd -- out.png [stage] [index]` (with `BARDING=...`).
- **Power frame, again** (Robert, 11-06 15:37: "my qi is still draining i took everything off but it looks like im
  still wearing some"). His save (slot 2) still had `constructs.mech` on: 1.93e10 qi a minute, 6% of his step; nothing
  else drained (swarm upkeep 0, gear empty; the 9 bionics fitted show on the body but cost nothing). "Take everything
  off" only cleared gear. Now `Game.unequip_all` opens the frame too, sitting to cultivate opens it
  (`Player.start_meditating`), and the Kit page shows "Power frame ON -- drinking N qi a minute [Leave the frame]"
  while it's worn. Checks in `tools/constructs_check.gd`; `tools/_qi_flow_probe.gd -- /abs/save.json` prints a real
  save's drains and proves the take-off (his copy: -1.93e10 a minute before, 0 after).
- Both eyes now take the stage-2 glow: `_eyes` named both "Eye", the tree renamed the second, and every check by name
  found only one. Eyes are marked with meta `eye` now.
- Final form, second pass: one smooth lofted head (cranium, stop, muzzle, nose, mouth line, slit pupils) for
  wolves/foxes, boars, deer, hares, lizards and toads (`Beast._beast_head`, `HEAD_SHAPE`); toads are lofted too;
  crabs get a carapace with seams of light and a rim of spines (`_spirit_carapace`), worms bands of light
  (`_spirit_rings`), golems veins of light and stones hanging round the shoulders (`_spirit_veins`). A golem doesn't
  grow a shell, wings or tails from its role; a worm no shell, wings, tails or horns. Role wings' lit tips dropped
  (a sheen instead).
- **Keeper's gate across the road** (found triaging the old playtest). `SetPieces.place` measured reach over
  `_free_cells` only -- plain floor marks. The side chambers' tunnels and every walkable mark (stairs, traps,
  torches, nooks...) weren't "free", so the reach from the stairs stopped at the first room (155 of 3,786 cells on
  floor 6, 1 cell on floor 8). The check "the way down must stay on the near side" never saw the way down, and on 37
  floors (8, 12, 13, 14, 16, 25-29, 31, 34, 36, 37, 39 ...) the Keeper's gate or the lever gate stood across the only
  road on: no Keeper's key, no stairs. Now the reach walks `SetPieces._walk_cells` (everything the pathfinder walks,
  less secret walls -- they aren't a way through until found); objects still go on free cells. Gate positions moved on
  those floors (they're seeded per floor, so a gate opened before may stand somewhere new; its Keeper comes back while
  the key is still needed). Check: `tools/gate_reach_check.gd` (49 floors: with each gate shut the stairs down, the
  boss and the Keeper are reachable and the vault isn't; lever gates leave the levers and stairs open) -- in the gate.
- `tools/playtest.gd` brought up to date: 63 stale expectations from rounds 119-181 (28 gear slots, the rail order,
  more chapters, the story drafts' names and hints, deeper masters wanting more talks, one follower and one searcher,
  the bag opening as slots, the 10-31 idle-thread hand-back, upkeep that doesn't leak from a full sea, the local
  calendar for streaks, the Store copy reading the same backend...). 1871/0. It's in the gate now.

## Round 182 (2026-11-07): fair ads, play stats, mods, the Chinese review, co-op join codes

Robert, 2026-11-06: "maximize potential of earnings, game mechanic and balance" -> "ok start building the structure to it".

- **Ad rewards give looks only.** The old rewarded ads ("the deep's blessing": +10% insight and loot luck; "gold back"
  after a fall) sold what `store.json fair_play.never_sold` forbids, and paying players (no ads) couldn't get them.
  Now the one gift is `try_style`: a day of the Style pack's auras (`Ads.style_trial()`, `Store.style()` asks it;
  saved in the ads record, never more than a day ahead). `tools/fair_check.gd` now checks every ad gift: no
  `effect`, no power words in its offer, `Ads._give` never touches gold/buffs/items/qi/insight, and a full numbers
  snapshot before/after an ad is identical. A fall's gold loss is the same for everyone.
- **Play stats (opt-in)**: `scripts/systems/PlayStats.gd` (system `playstats`). Off until yes; asked once at a town after
  20 minutes (`HUD.queue_moment("__ask_stats")`), Settings > "Share anonymous play stats" any time. Rows: day,
  minutes, kind (death, enter_level, boss_kill, breakthrough, levelup, floor_cleared, tribulation_*, trial_start,
  session_start/end), floor, level id, realm step, build, platform, tier -- ids and numbers only (`_short` drops
  anything with a space). `user://playstats.jsonl`, trimmed past ~384 KB. With `data/cloud.json` set up, batches of
  200 go to the `play_stats` table every 10 minutes (migration 04: insert-only, only the service role reads).
  `tools/stats_report.py <files/dirs/export>` prints falls, quits, boss kills and minutes-to-reach per floor and flags
  walls. Checks: `tools/playstats_check.gd` (against `tools/cloud/mock_supabase.py`), `tools/stats_report_test.py`,
  `supabase/tests/run_sql_tests.mjs` (gate runs it when `PGLITE_DIR` points at a folder with @electric-sql/pglite).
- **Mods**: `scripts/core/Mods.gd`. `user://mods/<id>/mod.json` + `data/*.json`, laid over the game's file in
  `Game._load_json` (dict merge, `null` removes, `{"__append": [...]}` adds to a list). Off until turned on (Menu >
  Mods, PC only), applied at the next start. Never moddable: `Mods.PROTECTED` (store, cloud, online, build files,
  retail). Any mod on: `Online.connect_now` refuses (`last_code "mods"`) and `SteamLink.leaderboard` posts nothing.
  Saves record `mods`. Workshop: `SteamLink.note_workshop()` writes subscribed folders to `user://mods_workshop.json`,
  read at the next start. Guide `docs/MODDING.md`, example `docs/modding/ashlight_fern` (ship it beside the exe).
  Check: `tools/mods_check.gd`.
- **Chinese review**: `tools/i18n/review_export.py zh_CN` writes `tools/i18n/review/zh_CN_review.xlsx` (a glossary of
  48 core words with suggested cultivation-novel terms and how many strings use the current one, and all strings
  most-seen first). A native reviewer fills the yellow columns; `tools/i18n/review_import.py <file>` turns them into
  `tools/i18n/override/zh_CN.json` (a glossary choice swaps the old word in every string whose English uses that
  word; placeholders must survive), then `python3 tools/build_i18n.py`. Found: "swarm" is 蜂群 (bees) in 199
  strings, alchemy is 炼金术 (Western alchemy), meditate is 冥想 -- left for the reviewer. Check: `tools/i18n/review_test.py`.
- **Co-op join codes**: the server's parties (up to 8) can share a six-letter code (`p_code`, `p_join`; no 0/O/1/I;
  ends with the party; renew to retire it; only the leader shares; refused while the party is on a run). Party page:
  "Get a join code for friends" / "Join with a code...". `data/online.json "url"` is the shipped server address once
  the shared world has a public home (`tools/server/deploy/`: docker compose with Caddy TLS and 6-hourly DB backups,
  `GO_LIVE.md`). Checks: `tools/server/e2e_test.py` (54), `tools/online_check.gd` via `run_online_check.sh` (now in the gate).

## Round 183 (2026-11-07): the store's look packs, the path art on the pad

Robert: "keep working on rounding out the whole project".

- **Look packs** (`scripts/systems/Looks.gd`, system `looks`; `data/looks.json`): Spirit Beast Coats (pet coat + accent,
  `Familiar._build` asks `coat()`), Tribulation Skies (the strike when you break through: `on_event("breakthrough")` ->
  `sky_burst`, a column and jagged bolts; with no pack a plain pale strike so every breakthrough is seen), Cultivation
  Seats (lotus of light, floating stones, koi ring, ink circle -- built in code by `make_seat`, drawn by
  `Player.start_meditating`, removed by `stop_meditating`), Weapon Spirits (`slash_color()` in `Player._deal_hit`).
  Products `coats_pack`, `skies_pack`, `seats_pack`, `spirits_pack` and `look_collection` (every pack + the Style
  pack) in `data/store.json`, kind cosmetic, `steam_dlc` 0 until Steamworks gives ids. `Store.owns_look`: bought, the
  Collection, Steam DLC, the box's own builds, or an ad's try-on day (the ad gift is now "Try on every look"). Chosen
  looks are per save. Page: Comforts & Style > Looks. Proof: `tools/fair_check.gd` (182: every pack owned and every
  look chosen changes no power number; Looks.gd never touches qi/insight/gold/buffs/items) and `tools/looks_check.gd`
  (44). Picture: `tools/_looks_shot.gd`.
- **Pad**: hold Back -- LB is the path art, RB readies the next (the path art had no pad button). `tools/pad_check.gd` 21.
- **Path page**: a second path's card now says it works at 50% (art x0.75 power, x1.25 wait).
- **Round 183b**: **Familiar Trinkets** (`trinkets_pack`: red cord and bell, jade ribbons, silver chain, sect saddle
  cloth -- `Beast.trinket(spec)`, a collar torus at the back of the head, a bell, ribbons, a girth band of cloth with
  hems and tassels that wraps every body including the lofted spirit form; `Familiar._build` asks
  `Looks.current("trinkets")`). **Wardrobe** (free, not a pack): `Looks.seen` remembers every wearable that comes
  into your bag (`Game.add_item` -> `Looks.saw`; old saves are seeded from what you carry and wear), `set_wardrobe(slot,
  id | "-" | "")` draws a slot as another held piece, hides it, or shows what you really wear; `Game.worn_looks`
  applies it (drawing only -- fair_check hides three slots with every number unchanged). Page: Looks > Wardrobe.
  **Music room** (free): Settings > Sound > "Music room": tap any piece (`Audio.play_now`), its set then plays
  everywhere (`Audio.pin_set`, `next_piece`) until "Let the places choose the music again" (`unpin`). Checks:
  looks_check 71, audio_check 200, fair_check 184. Pictures: `tools/_trinket_shot.gd` (STAGE=, CLOSE=).
- **Round 183c, refined music** (Robert: "make the music more refined and subtle -- it doesn't need to be a lot, just
  add flavor and substance"). `tools/music_gen2.py` `sketch()` (run with `MUSIC_SUBTLE=1 MUSIC_HARMONISE=1
  MUSIC_FOLDER=music3_subtle`): about 75-110 s instead of 130-160; a breathing low drone and a dark pad, ONE voice
  saying the motif, a rest, the answer on the second voice, a single bell or harmonic at the turn, the motif once more,
  softer, then home -- flutes pure (no buzz, little breath), no drums, no busy accompaniment, a darker top (6.5 kHz)
  and about 4-5 LU quieter (-22 to -25 LUFS). `assets/audio/music3_subtle/` (19). Music style "subtle" is the
  default and every saved setting moves to it once (`Gfx` `music_v` 1 -> 2); "new" (full harmonised), "original" and
  "classic" stay in Sound > Music style. In the subtle style the fight drums sit at 60%. Checks:
  `tools/music_subtle_test.py` (every refined piece quieter by 2.5 LU+, shorter, -20 LUFS or less), audio_check 203.

## Round 184 (2026-11-08): a world you can hear, and folk who notice you
Robert: "keep working on making the details of the game better, more immersive".
- **The day beds were silent.** `village_day.ogg` and `valley_day.ogg` had been all zeros since they were made: a
  NaN in `music_gen2.chirp` (`sin(pi*t/t[-1])` a hair below zero at the end, raised to 0.7). Fixed (clipped) and
  both remade -- the village by day now has its birds, breeze and far voices. `tools/world_sfx_test.py` now checks
  every bed is audible.
- **WorldSound.gd** (child of Audio, runs headless for tests):
  - *Spots*: one-off sounds placed around you in 3D -- songbirds, a dove in the morning, owls and frogs at night,
    porch chimes, the smith's hammer in working hours, a woodcutter, the temple bell; below: drops in the dark,
    stones settling, the deep's rumble, a crypt's moaning air, bones, lapping water, crystals humming, the forge's
    pops and steam, gears catching. `data/audio.json` "spots" (by the place's bed: every / vol / dist / h / hours /
    day / weather / not_weather / season) and "weather_spots" (storm: far thunder; tremor: the rumble; drip ...).
    Birds keep quiet in rain, snow and fog. Hushed in a fight, in menus (world_frozen) and when paused. Captioned.
  - *Weather you can hear*: rain (light / heavy in a storm), soft wind for snow, fog and falling leaves -- under the
    sky only ("weather_beds"); a cold seep in the deep.
  - *Echo*: a "World" bus with a reverb sized to the place ("rooms": dry in the open, a little in the village, long
    in the deep, crypts and flooded halls). Blows, steps and spots go through it; menus, fanfares, loot and coins
    stay dry (`Audio.DRY`). `Audio.at()` / `Game.sfx_at()` now play from AudioStreamPlayer3D -- heard from that side,
    duller with distance.
  - *Ground*: steps on snow, water, sand, metal and wood ("ground": by look, by theme; snow weather under the sky),
    grass and stone as before, and a splash under the grass in the rain.
  - Settings > Sound: "Sounds of the world", "Echo in caves and halls" (both on).
- **Passing greetings** (`NPC.gd`, `data/greetings.json`, 54 lines): come within 4.5 m and folk turn and say a word
  over their head -- hurt first ("You're bleeding. Sit down a moment."), a deep town's welcome, the weather, their
  trade, the season, else the hour. Once per approach, 150 s per person, 6 s between any two, never in a menu or a
  fight. Settings > Sound: "Villagers greet you as you pass".
- Sounds are made by `tools/world_sfx_gen.py` (steps 20, spots 57, weather loops 4; fixed seeds).
- Checks: `tools/world_sound_check.gd` 399 (every file, every bed has spots and a room, the gates, ten simulated
  minutes per place, grounds, dry/wet, greetings), `tools/world_sfx_test.py` 321, both in the gate.
  `tools/world_sound_live.gd` (xvfb, ~5 min, not in the gate): real 3D players, the World bus, rain, a real
  villager greeting you; picture in /tmp/greet.png.
- **Round 184b, the life of the air** (looks only; off on Low effects): `WorldFX.life_for` puts fireflies over the
  grass on warm nights (thaw/blaze/harvest, not in rain, snow or fog), drifting petals on spring days, seed fluff on
  summer days, and rain landing around you (`Motes` kinds fireflies -- blinking -- petals, fluff, splashes). Your
  breath shows in the cold (`WorldFX.is_cold`: snow, Frost, late Harvest nights, a frost floor, a cold seep;
  `FX.breath`), and so does a villager's when they greet you. Footfalls throw up snow, sand or a splash
  (`WorldSound.step_fx_kind`, `FX.step_puff`), puddle splashes on wet grass. A storm's thunder now follows its
  lightning by 1-4 s, from where it struck (`WorldSound.thunder_after`). **Bug fixed**: Motes warmed up at the
  world's origin before moving to you, so snow, leaves, ash and drips were missing for their first 8-9 s in a
  place. Checks: world_sound_check 421. Pictures: `tools/_life_shot.gd`, `tools/_motes_shot.gd` (KIND=).

## Round 185 (2026-11-08): the wow -- northern lights, falling stars, cloud shadows, lantern night
Robert: "keep bringing it to life -- I want a wow factor for an indie creator".
- **Northern lights** (`sky.gdshader` `aurora`): curtains along the northern sky -- a folding foot, fine rays
  standing up them, green fading to violet at the top, gaps that drift. Clear nights only: every Frost night, one
  Harvest night in three, now and then otherwise (`WorldFX.sky_wonders`). "The northern lights are out tonight."
- **Shooting stars** (`meteors`): a chance every 6 s on any clear night (0.18), a shower one night in ten (0.75,
  "Stars are falling tonight."). `meteor_test` holds one in place for `tools/_sky_shot.gd`.
- **Cloud shadows** (`terrain.gdshader` `cloud_shadow`, `cloud_wind`): shadows ~90 m across sweeping over the land
  at ~6 m/s by day, strongest under a broken sky (`WorldFX.cloud_shadow_for`).
- **Lantern night** (`scripts/world/SkyLanterns.gd`): on a clear evening every other day (19:00-22:30) and every
  festival evening, Eliet sends up paper lanterns -- warm glowing bodies with a soft halo, lifting off from all over
  the village (half near you), climbing and drifting on the wind to 150 m; up to 70 at once; arriving mid-evening
  the sky is already full (prewarm). "Lantern night -- the village sends its wishes up."
- Folk talk about it (greetings "lanterns", "aurora", "meteors"; `NPC.greeting_for(..., sky)`).
- All looks only and off on Low effects. Checks: world_sound_check 448. Pictures: `tools/_wow_shot.gd`,
  `tools/_sky_shot.gd` (AURORA= PITCH= YAW= FOV=).

## Round 186 (2026-11-08): cleaning up -- Eliet was drawing at 3-4 frames a second
Robert: "keep cleaning up and improving the game". His own crumbs.txt / memlog on the PC showed the village at
3-4 fps on an RTX 5060 Ti (Forward+, Medium), 19-21k nodes. Headless profiling with his save (tools/_perf_village.gd,
SAVE=...) and a fresh one gave the same picture -- the scripts took ~7 ms; the drawing was the problem:
- **Trees**: every limb was its own MeshInstance3D with its own CylinderMesh -- ~5 per tree, 1,658 trees, 8,297
  draws, each drawn again per shadow cascade. `Tree.make` now builds one merged bark mesh + one leaf MultiMesh and
  shares 24 built variants per kind/season/height (`Tree.VARIANTS`, `variant_key`); and once a place has finished
  streaming in, `Level` gathers its trees by 32 m patch -- one bark mesh per patch and bark, one leaf MultiMesh per
  patch and leaf -- one patch a frame (`_begin_tree_batch`, `_batch_tree_chunk`, `batch_trees_now` for tests).
  Shadow casters 10,782 -> 934; draws (xvfb) 10,253 -> ~1,800.
- **Photo scans**: the grass tuft was 24,730 triangles x 670 tufts = 16.6 M triangles; shrubs 27k, the chest 103k,
  stumps 41-62k... Low-poly copies (`<id>_lo.gltf` beside each, 2,000-8,000 triangles, same textures; 30 models,
  `tools/gen/decimate_gltf.py`) are used on every preset but Ultra (`Art.real_path`, `Art.full_detail`). The
  village's triangles 21 M -> 5.8 M. Side-by-side pictures: `tools/_lo_shot.gd` (ID=).
- `tools/perf_check.gd` (in the gate) holds the line: Eliet under 3,000 shadow casters, 3,500 draws, 8 M triangles.
- Voice.say with no model to ask (llm_url "") answers at once instead of an HTTP "Error parsing URL" (was in every
  playtest log). NPC greeting poll no longer looks the player up every frame.
- bionics_check flake (r185) fixed.
- **From Robert's play log** (6,908 events, 10 days): 831 of his 881 item uses were the same pill again within a few
  seconds -> **Use all (N)** on pills whose good adds up (qi, attunement, cleansing -- `Game.can_use_many`,
  `use_many`, one summary line; healing, buffs, coatings and gated pills stay one at a time). And 790 "pouch is full
  ... went to your chest at home" lines -> said once per kind per two minutes (`_overflow_said`; nothing is lost).
  `tools/use_many_check.gd` (14) in the gate.

## Round 187 (2026-11-08): cleaning up -- the valley, ponds, lamps
Robert: "keep working". After r186 the village was fine but the valley still drew 4,266 times a frame (xvfb,
real renderer -- `tools/_perf_live.gd`, ID=). What was left (`tools/_perf_one.gd`, `_perf_who.gd`, `_perf_scan.gd`):
- **Still props** (`Level._prop`): every shrub (four pieces each, 846 of them), boulder, wall block and roof cap was
  its own draw and its own shadow. `_prop` now marks what it makes (`meta pp` = its name). After the trees, the
  level gathers the props nothing else will touch (`prop_batchable`: made by _prop, still a child of the level, not
  renamed since, no script, no group, nothing but Node3D/MeshInstance3D inside, no meta on a mesh) by 32 m patch
  into one MultiMesh per patch and kind of piece (per-surface materials folded into a shared copy, `_fold_mesh`).
  Pieces under 3 m stop drawing past 150 m, under 7 m past 260 m (x0.75 Low, x1.4 High, x2 Ultra). One-offs stay.
  Gather nodes and anything scripted are left alone. `_begin_prop_batch`, `_batch_prop_chunk`, `batch_props_now`.
- **Ponds**: every water cell was its own mesh *and its own material* (687 in the valley) -- now one shared material
  (`_water_mats`), no shadow, and merged into one mesh per patch.
- **Tints**: `_tint` / `_glow_tint` made a new material per piece (389 wall caps = 389 materials) -- now one per
  material and colour (`_tints`), so they batch.
- **Lamps**: small lights (range <= 16 m) fade out past 70 m (`_fade_far_lights`; Gather nodes already did).
- `flower_empodium` and `fern_02` got low-poly copies (3,053 -> 1,596 and 6,232 -> 2,596 triangles).
- Valley: draws 7,593 -> 2,731, shadow casters 6,508 -> 1,622 (all of it); xvfb frame draws 4,266 -> 1,649. Village:
  880 draws, 561 casters. `tools/perf_check.gd` now also checks the valley (under 3,500 draws / 2,500 casters,
  ponds batched, lamps fading) and which props may batch; Eliet tightened to 1,500 draws / 1,200 casters.
- Before/after pictures of the same view: `tools/_batch_shot.gd` (ID=, NEAR=shrub) -> /tmp/bs_a.png, bs_b.png.
- The Lands (frontier) still count ~2,800 draws in all, but only ~290 a frame are in view (their dressing is
  mostly GatherNodes, which already cull) -- left as they are.

## Round 188 (2026-11-08): guilds with a group chat, your own sect, weapon arts, strike styles, a slowness probe
Robert: "fun and addicting... group chat guilds that can give some support but not push the balance, or start our own
sect and own guild" (chat: NPC guildmates now, real players when online is live; support: gifts and trades, help
requests, guild tasks, cosmetic rewards; own sect: full founding). Then: "more variety in the martial arts and their
special abilities for the type of skill it is. Allow for packs to also change attack appearance".
- **Guilds** (`scripts/systems/Fellowship.gd`, `data/fellowship.json`, page `scripts/ui/GuildPage.gd`, Hub tab
  "Guild", F6). Three NPC guilds to join, or found your own for 500 gold (key `own:TAG:XXXX`, recruit NPC members).
  Chat: channels, keyword answers (or the Voice LLM, child `GuildVoice`), ambient talk by persona, reactions to what
  you do. Support never adds power: gifts (daily cap), fair trades (within 5% of value), help requests (you pay 2x
  value, delivered in 8-20 min), weekly guild tasks for renown, renown buys titles, crests, emblems, hall decor.
  `effects()` is always `[]` (fair_check). HUD chat box (`scripts/ui/ChatBox.gd`): Enter to type, last 6 lines, fades.
  Online: `Online._send_guild_key`, server `h_guild_key` + guild chat broadcast to the same key (e2e 59/0).
- **Your own sect** (`scripts/systems/OwnSect.gd`): found at realm 3 with 3000 gold -- name, element, colour, creed,
  the arts it teaches. `G.sect = {"id": "own"}`, Sect Master. Disciples (4/8/12 slots by hall), teach, encourage,
  errands (daily), they grow in real time (max 24 h catch-up, cap: your realm - 1). Hall upgrades; at hall 3 a mature
  gift (x1.15, `mature_effect`). The Empty Seat in the valley (`Valley.OWN_SEAT`, road from its gate) becomes the
  sect's grounds (`scripts/world/OwnSectSite.gd`: board, banners in the sect colour, lanterns, statue, disciples).
- **Weapon arts** (`data/weapon_arts.json` from `tools/gen/weapon_arts_gen.py`): 36 arts, three per kind of weapon
  (sword, dagger, saber, spear, axe, hammer, halberd, staff, unarmed, bow, crossbow, ki) at weapon skill 5/15/30.
  Learned by fighting with that weapon (`Arts.sync`), usable only with one in hand (`Arts.gate` via
  `G.weapon_skill()`), the new one goes on an empty quick key if it's for the weapon in hand. Fifteen ways of
  fighting, seven new in `ArtCaster.gd`: flurry, whirlwind (move while spinning), throw (out and back / fan),
  volley (arrows fall on a spot), counter_stance (`Player.take_damage` -> `counter_strike`), multi_bolt (one orb per
  foe), pin; blink gained `behind` (step behind the nearest foe). `tools/weapon_arts_check.gd` (29) casts every art
  for real against goblins in floor1.
- **Strike Styles** look pack (`strikes_pack`, cosmetic, in the Look Collection): Twin Crescent, Falling Petals,
  Dragon Fire, Thunder Edge, Ink Brush, Frost Fang. `Looks.strike_style()` / `strike_color()`; `FX.strike` (the sweep)
  and `FX.impact` (where it lands) draw them; your shots (`Shot.gd`) and weapon arts take the colour. A Weapon Spirit
  tints the style. Looks only -- same reach, same damage. looks_check now 6 packs (77 headless / 78 with a renderer).
  Pictures: `tools/_strike_shot.gd` (xvfb; slows time to catch the sweep) -> /tmp/strike_*.png.
- **Slowness probe** (`scripts/core/PerfProbe.gd`): a "perf" crumb every 15 s (gpu/cpu/draws/prims/objects); in test
  builds, once a run, if fps < 12 for 8 s after the place settles it switches each suspect off in turn (shadows, sky,
  MSAA, half resolution, lamps, particles, trees, props, water, actors, HUD...) and writes `user://perf_probe.txt`.
  `tools/perf_probe_check.gd` (20).
- Tools writing saves must set `G.save_base` away from `user://save` (else the tester state lands in
  `user://save_account.json` and fair/lite/design checks fail).

## Round 190 (2026-11-08): from Robert's play log -- points, armour, the fountain
His `playlog.jsonl` (6,908 events) and save (`save_slot2.json`, realm 15) from the PC:
- 107 of his 110 attribute points went in one click each -> character page: **+5**, **All (n)** beside each attribute,
  and **Spread them evenly (n)** (`Game.attr_spread`: each point to the lowest, the balance-friendly choice).
- 54 pieces of armour put on one after another, and his save had **7 empty armour slots** -> Pack: **Wear the better
  pieces** (`Game.wear_better`). Armour only; a piece is swapped only for one with at least as much health AND ward
  (`better_piece`); jewellery, weapons and pieces made for you / with affixes / with runes are never touched
  (`_plain_piece`). On his save: health 34,951 -> 66,782, ward 73 -> 396.
- 400 coins in the fountain, nothing after the 100th -> it counts every 50th, and gives back at 500, 777 and each 1000.
- Bench: **Work it again and again (up to 5)** when the odds are 95%+ (his 240 god-craft workings, one click each); stops at the first failure, change or anything running out (`Kit.bench_go_many`).
- A seasoned fighter loading an older save earns twenty-odd weapon arts at once (his save: 21) -> `Arts.sync` learns them quietly (`Game.learn(..., quiet)`) and says it in one line.
- 647 menu opens, most a look and a close (Swarm 86, Meridians 85, Mind 60) -> the rail puts a gold dot on a page
  where something waits (`Hub.ready_marks`, every 1.5 s, ~2 ms on his save): points to spend, no meridian focus,
  nothing being researched, a dao contemplation left, no path, a guild trade offer, better armour in the pack.
  The dot's reason is the button's tooltip.
- Fixed (found by the gate on a new day): your own sect showed two hopefuls at the gate, not three, on ~1 day in 7 --
  one shared a name with a disciple from before and was dropped (`OwnSect.candidates` now never draws them).
  fellowship_check now tries 300 draws, and counts errands home in pouch + chest.
- `tools/qol190_check.gd` (35, in the gate).
- Profiling his own save: `ROB=1` in `tools/_cpu_who.gd` (headless CPU: scripts ~24 ms/frame on this 2-core box) and
  `tools/_gpu_probe.gd` (Vulkan: village 2,142 draws, 4.8 M triangles with his save). Copy his save to
  `user://tool_rob_slot2.json` first. His last run (before r186) still showed 3-4 fps; nothing since -- PerfProbe will say.

## Round 192 (2026-11-08): the graphics card is shared -- and the picture follows the GPU
Robert played twice on r192: "its very laggy keep trying to improve quickness and snappy response". His
`perf_probe.txt` (the r188 probe, first real reading): 2560x1440, medium, **503 ms of GPU per frame for 1,321 draws**,
CPU 2.7 ms; every suspect cost its share (sky ~40%, SSAO ~30%, MSAA ~25%, half resolution -60%) -- a card starved,
not a scene too heavy. His box's Model Manager (localhost:9114) said why: **Ollama held qwen3.5:9b at 14.04 of 15.9 GB
of VRAM**, spilling into system RAM; the game's ~1.2 GB had nowhere to live, so every frame paged.
- `scripts/core/GpuCourtesy.gd` (Main adds it, desktop only, not headless/phone/web): 3 s after start and every 90 s
  while focused, GET 127.0.0.1:11434/api/ps; if a local model holds >1 GB of the card, POST /api/generate
  {model, keep_alive: 0} for each (Ollama's documented unload -- it reloads by itself when next asked). Tells the
  player once; crumbs + perf_probe.txt say what it saw ("ollama: qwen3.5:9b 14.0 GB on the card").
  Setting (pause menu): "Local AI on the graphics card while playing: free it / leave it" (`gpu_ai`). Skipped when
  the game's own AI words are on (ai_on.txt). Test: `tools/gpu_courtesy_check.gd` (14) against
  `tools/server/mock_ollama.py`.
- `scripts/core/AutoRes.gd`: Picture size "auto" (new default; anyone on the old default 100% moves once, `res_v`):
  GPU time over budget x1.15 for 1.5 s -> 3D drawn 8-15% smaller (min 60%, FSR upscale on Forward+); under 60% of
  budget for 6 s -> back up 5%. Only GPU time counts. Menus stay full size. PerfProbe pauses it while measuring and
  writes picture=% and video memory in its header. Test: `tools/auto_res_check.gd` (10).
- Sky: the sky shader reads TIME, so Godot rebuilt its 256 px radiance cubemap every frame -- for nothing (ambient
  is a set colour, reflections are off). `Level._cheap_radiance`: 32 px, PROCESS_MODE_QUALITY (rebuilt only when
  the sky changes).

## Round 194 (2026-11-08): why the card was full -- and no Gate nobody can reach
- The 14 GB wasn't the model: Ollama's /api/ps said `qwen3.5:9b ... context_length 262144`. A 9B model at Q4 is about
  6 GB; the rest was a 256k context. The box's two warm-ups (smart_llm.warm_model, dev_talk.warm) sent no num_ctx, so
  Ollama used its server default (256k on this box). Fixed on the box itself (bundle claude-r193-warm-ctx-b: warm-ups
  ask for 8192, Dev's NUM_CTX). The game now logs the context per model ("qwen3.5:9b 14.0 GB ctx 256k") and the
  crumbs name the card that draws ("card: <adapter> | <vendor> | <api> <renderer>").
- `Online.open_to_players()`: a CLEAN build stands the Gate to Elite Online only when data/online.json has a public
  "url". Without one the Gate led to the HomeAI box over Tailscale -- "can't connect" for every store player. Test
  builds keep it. Robert's rule: a server only once the game has traction. Test: `tools/online_open_check.gd` (9).
- Steam full-game preset exports `build/steam/DungeonCrawlElite.exe` (was "Eliet").
- Android target SDK: blank in the presets = Godot 4.6.3's default, which is **36** (checked in the built APK with
  aapt2: targetSdkVersion 36, compileSdk 36) -- Play's 2026 rule is already met.
- Delete my cloud account (Google Play requires an in-app way): Cloud window -> "Delete my cloud account..." ->
  confirm -> `CloudSave.delete_account()` -> `supabase/functions/delete-account` (saves, then their history -- deleting a
  save copies it into history, so history goes last -- then the account; purchase_events keep the sale, user_id ->
  null). Device saves untouched. Tests: `supabase/tests/delete_account_test.mjs` (14), `tools/cloud_check.gd` (58,
  now in the gate).
- `verify-purchase` knew 2 of the 9 products -- any look pack would have been refused once purchase checks were on.
  `PRODUCTS` now matches data/store.json and the test fails if they drift.
- GpuCourtesy unloads only above 8 GB (was 1 GB): at an 8k context the box's model is ~6.5 GB and leaves the game
  room; unloading it every 90 s only made the box reload it every 90 s (his log: freed at 13 s, 104 s, 199 s).

## Round 195 (2026-11-09): the frame was spent asking "what bonuses do I have?"
With the graphics card freed, Robert's village ran at a median 26 fps with the GPU at 4 ms -- the CPU was the limit.
Note first: `Performance.TIME_PROCESS` (the crumbs' "proc=") is the WORST frame of the last second, not an average --
per-script toggling on it was noise. `tools/_cpu_wall.gd` measures average WALL time per frame instead: 27 ms in the
village on his save (headless), of which Game.gd's _process alone was 10-15 ms.
- `tech_effect()` rebuilt `_effects()` on every call: 131 entries (every pack item checked for treasure, every system's
  effects, gear, runes, lattice...) -- 2.2 ms a call, and the per-frame readers asked several times a frame: the HP bar
  (max_hp x3), FloorRun's low-HP watch (max_hp x2), movement (move_mult), regeneration, spirit sense, research and
  cleansing speed. Those readers now use `fx_now(key)` / `max_hp(true)`: a kept copy of the list, rebuilt when
  `stats_changed` fires, when a cheap signature moves (techniques/inventory/buffs/lattice/guilds/contracts/sect sizes,
  weapon, gear, partner, place, realm) or after FX_KEEP_MS (250 ms). `tech_effect()` itself stays exact (rules, menus,
  tests -- dao_check changes a system's focus and reads it in the same frame). Village/valley/floors 22 and 33/frontier:
  27 -> 7 ms a frame headless (7 ms is the headless floor -- an empty scene measures the same). New per-frame code:
  use fx_now, not tech_effect.
- The autosave (every 60 s) took ~65 ms on a 730 KB save: stringify + two full JSON parses that were only checks.
  The new file is checked by reading it back and comparing; the old file is parsed only if this run didn't write it.
  ~19 ms now. Test: `tools/perf195_check.gd` (14).

## Round 196 (2026-11-09): the lag after every fight
`tools/_spike.gd` (frame-time trace over 20 s on Robert's save) showed the village going from 7 ms frames to 100-190 ms
seven seconds after standing still -- the moment wounds start to close. With a big HP pool, survival regen heals some HP
every physics tick, and every heal called `add_skill_xp("survival")` -> check_unlocks() + stats_changed -> a full
HUD.refresh() (~5 ms) and Player._dress_up -- 24 exact effect-list builds a frame.
- Player._regen batches the survival XP: added once a second of healing (and when healing stops). survival_regen()
  reads max_hp(true).
- HUD listens to stats_changed through `_refresh_soon()`: one refresh at the end of the frame however many changes
  came in (a kill alone emits several). One stats_changed: 9 ms -> 0.4 ms.
- HUD's "dmg" uses Game.damage(true) (kept effect list). Game.damage()/weapon_damage() take `now`.
- Sitting with the practice ground: 7 ms frames. perf195_check now 21 checks.

## Round 197 (2026-11-09): the hitch on every kill
`tools/_fight_spike.gd` (real blows through Player._start_blow on floor 22, his save) and `tools/_fx_parts.gd` (what each
effect source and kill step costs). A kill took 25-40 ms synchronously: record_kill, Hook.on_kill (watch_power, chain),
add_qi, train_weapon, roll_loot, add_item (pouch_cap), drop_gear + Hook.compare -- ~10 exact tech_effect() calls at
~2 ms each.
- `Game.fx_hold(true/false)`: while held, tech_effect() builds the effect list once and rebuilds it only when the
  signature moves (an item gained, a technique learned, the realm...). Enemy._die and Player._deal_hit hold it.
  Kill: 25-40 ms -> 12-19 ms. Nested holds count. Pair every hold(true) with hold(false).
- perf195_check: 23 checks.

## Round 198 (2026-11-09): Use all, the bag, idle foes
Robert's play (build 85): mostly 55-60 fps now. Three things left. "Use all" on 999 pills froze the game 10-20 s (the
crumbs have a 26-36 s gap between perf lines). The bag took 160 ms to redraw on every tap. Floor 34 ran 37-45 fps.
Probes: `tools/_useall.gd`, `tools/_hubfill.gd` (every menu page's redraw time), `tools/_foe_cost.gd`, `tools/_arrive.gd`.
- `Game.use_many` holds the effect list (`fx_hold`) and the play log (`log_hold`) for the batch: 4.5 -> 0.38 ms a pill.
  The effect signature now also covers `affinity.hash()` and `_fx_bump` (a cleansing or blood pill bumps it). A held list
  can't go stale.
- `log_hold(on)`: nested; lines are written in one go, in order, when the outer hold ends. The size check / rotation
  moved into `_log_write`.
- `Quests.qdef` was a linear walk over every quest (plus a new array each call), run for every active quest on every
  logged event: 0.8 ms an event. It's now an id index, rebuilt when `data["quests"]` grows or is replaced. It checks the
  id on every hit. Legacy lines are still searched after the base list (same first-match order as `all()`).
- Kit: `_bag_order` works its sort keys out once (47 -> 4 ms). The slot grid (`_grid`) stays in the page and its
  buttons are re-dressed in place (`_new_slot`/`_dress_slot`, item read from meta "id"). Styles are shared via
  `_shared_style`. The list view and the choose-a-slot view drop the grid. Pack redraw: 163 -> 38 ms headless.
- Player: `stats_changed` -> `_look_soon`, which runs the clothes, the aura and the first-person hand once next frame.
  It used to run on every change.
- Enemy `_rest_slide`: a foe standing still on the ground checks its footing every 0.4-0.6 s instead of sliding every
  tick. Any velocity slides at once. 89 idle foes: 1.5 -> 0.24 ms a physics tick.
- PerfProbe: waits for two matching baseline frames (within 25%, up to ~3 s) before switching things off. It writes
  a "settling" line and says when the slowness eased by itself. His floor-24 probe had blamed shadows and SSAO for a
  passing storm.
- Not reproducible headless: floor 24's first ~20 s after arriving ran at 4-5 fps (proc 215-272 ms, gpu 25 ms), then
  recovered. Likely the card preparing shaders for a new place. The next probe will show it in its settling line.
- Still heavy: the Swarm page redraws all 50 design cards per click (~40 ms headless).
- perf198_check: 36 checks, in the gate.

## Round 199 (2026-11-09): menu pages, the symbol font, boss young
`tools/_hubfill.gd` times every menu page's redraw on his save (ROB=1; PAGES=Road,Works to pick). Before -> after, headless:
Road 1304 -> 52 ms, Works 1250 -> 247, Journal 718 -> 379, Craft 436 -> 377, Quests 216 -> 38, Party 179 -> 85, Mind 81 -> 28.
- `Game.errand_defs()` read every floor's level file on each call (20-30 ms) and the Road page called it twice per
  errand. Cached per (reach_depth, language, item and enemy counts). Treat the returned dictionary as read-only.
- `Hub._fill` and `Kit._refresh_now` hold the effect list (`fx_hold`) while a page draws. Drawing changes nothing, and
  the Works page asked `tech_effect()` ~120 times.
- `HUD._place_name` caches a place's name per language. It used to parse the whole level file per mention.
- **Symbols.** Any control whose text has a glyph the engine's fallback font lacks (ticks, arrows, diamonds, stars,
  CJK) made the engine ask the OS for a font on every shape: 0.6-1.5 ms a label (found with gdb: FcFontMatch under the
  text server). The engine shapes against `ThemeDB.fallback_font` as well as the themed chain, so adding a font to our
  own chain alone doesn't help. Fix in `UiStyle.font()`: `assets/fonts/dce-symbols.ttf` (53 glyphs cut from DejaVu
  Sans with fontTools, 17 KB, licence beside it and in the export filter) goes into our chain AND into
  `ThemeDB.fallback_font.fallbacks`, together with the CJK font. It needs script-support overrides
  (`symbols_font()`), or the text server skips a letterless font for Latin text. A tick label: 0.63 -> 0.018 ms.
  Arabic, Thai and emoji still use the system fallback.
  To add a symbol: add it to the subset (the char list is in the r199 project doc) and to polish199_check.
- **Boss young.** A boss's brood and a splitting boss's pieces were spawned with the boss's sheet, `boss: true`
  included: each dropped boss-tier gear, logged `boss_kill`, ran boss phases and could brood again. `Enemy.setup` now
  clears `boss`/`world_boss` on a minion.
- Not done: Journal, Craft and Works still build 1,000-2,900 nodes per redraw. Building them detached and re-adding
  was slower (750-1230 ms). The real fix is to build only the open tab (PageTabs).
- polish199_check: 36 checks, in the gate.

## Round 200 (2026-11-09): boss ease, lazy tab sections, spread button
- **Boss ease** (`data/combat.json "boss_ease"`, `Game.boss_ease(d, key)`, applied in `Enemy._round30_numbers` to floor
  masters only: `stats.boss`, not a world boss, level id `floor*`). Health and damage ease evenly from floor 25 (x1) to
  floor 49 (x0.75 / x0.85); floor 50 has its own (x0.7 / x0.8). balance_report, kills-you / time-to-kill: floor 49
  17s/66s -> 22s/50s, floor 50 15s/107s -> 19s/74s; floors 26-49 now hold at about 0.43, where floor 25 was. Set the
  numbers to 1 to switch it off. A Keeper flagged boss after setup (Level.gd) is not eased.
- **Lazy tab sections.** `Hub._lazy(owner, prop, build)` adds an empty box with a "lazy_build" meta; `PageTabs` calls
  it the first time that tab is shown (and at once when a page ends up without tabs). The builder runs with the
  page's box variable pointed at the new box, so existing code that writes to `_craft` / `_works` / `_jr_body` needs
  no change. Wrapped: Journal (things found, places), Craft (recipes, herbology, supplies, bestiary), Works (foundry,
  crew, tailor). A lazy body must not hold a tab-level heading (size >= 16 directly in the page). To read a whole page
  in a test: `PageTabs.build_all(box)`. Redraw, headless, his save: Journal 379 -> 27 ms, Craft 377 -> 16, Works 247 -> 18.
  Outer locals are captured by value in the lambdas; declare anything you assign inside the body.
- The Works page's Tailor buttons called `_fill(I18n.t("Works"))`, which did nothing in any language but English. Fixed.
- "Spread them evenly" is at the top of the attributes, lit, when there is more than one point to spend.
- round200_check: 29 checks, in the gate (123 steps).
