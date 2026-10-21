extends RefCounted
## The arena -- where the Lotus Ascent Academy tests its applicants and the
## settlements hold their tournaments (Robert, 2026-10-02: "some sort of
## reason for getting stronger, a tournament maybe or a school entry exam").
##
## An arena level is never a file: its id is "arena_<host>_<event>_<stage>"
## and Game.load_level_def() asks this file for it, building the fight from
## Game.arena (what's being fought, and who). Clear the floor and the next
## round begins (or you're done); fall and you're carried out -- no gold
## lost, nothing broken but pride.

const PREFIX := "arena_"
const W := 24
const H := 18

## Rivals: cultivators you'll meet again and again. Each grows a little
## every time you cross paths -- win or lose.
const RIVALS := [
	{"name": "Lu Feng", "sect": "Iron Pine Sect", "kind": "sword", "tint": [0.55, 0.75, 0.55],
	 "hello": "Lu Feng bows exactly as deep as courtesy demands and not a hair deeper.",
	 "win": "\"Steady. I'll remember that.\"", "lose": "\"You fought well. Not well enough.\""},
	{"name": "Mei Ruolan", "sect": "Crimson Lantern Pavilion", "kind": "dagger", "tint": [1.0, 0.45, 0.45],
	 "hello": "Mei Ruolan twirls a dagger and smiles like she already knows how this ends.",
	 "win": "\"Oh, I LIKE you.\"", "lose": "\"Don't look so sad. You were almost fun.\""},
	{"name": "Brother Hu", "sect": "Stone Gate Monastery", "kind": "fists", "tint": [0.85, 0.7, 0.45],
	 "hello": "Brother Hu cracks his knuckles and apologises, sincerely, in advance.",
	 "win": "\"The mountain bows to the river. Well struck.\"", "lose": "\"Rest. Eat something. Come again.\""},
	{"name": "Xu Anlan", "sect": "Azure Spear Hall", "kind": "spear", "tint": [0.45, 0.6, 1.0],
	 "hello": "Xu Anlan plants her spear and waits, utterly still.",
	 "win": "\"...Again. Next time.\"", "lose": "\"Distance. You never closed it.\""},
	{"name": "Old Qiu", "sect": "no sect at all", "kind": "staff", "tint": [0.7, 0.7, 0.75],
	 "hello": "Old Qiu leans on his staff and yawns. Nobody here seems to know how old he is.",
	 "win": "\"Ha! The young ones are getting good.\"", "lose": "\"Patience, child. Patience is a weapon too.\""},
	{"name": "Tang Wei", "sect": "Black Ox Clan", "kind": "hammer", "tint": [0.4, 0.38, 0.45],
	 "hello": "Tang Wei rests a hammer the size of a door on his shoulder.",
	 "win": "\"Hah! Good! Again! No -- tomorrow.\"", "lose": "\"Too light. Eat more.\""},
	{"name": "Shen Yue", "sect": "Moonlit Saber School", "kind": "saber", "tint": [0.75, 0.75, 1.0],
	 "hello": "Shen Yue draws in a single motion you barely see.",
	 "win": "\"Your intent was clearer than mine. I'll fix that.\"", "lose": "\"You hesitated. I didn't.\""},
	{"name": "Gao Lin", "sect": "Thunder Axe Fort", "kind": "axe", "tint": [0.95, 0.85, 0.35],
	 "hello": "Gao Lin laughs, loud enough to echo, and spins his axe.",
	 "win": "\"HA! Worth the trip!\"", "lose": "\"Next time bring an army!\""},
]


static func is_arena(level_id: String) -> bool:
	return level_id.begins_with(PREFIX)


static func make_id(host: String, event: String, stage: int) -> String:
	return "%s%s_%s_%d" % [PREFIX, host, event, stage]


static func rival_def(r: Dictionary, tier: int, met: int) -> Dictionary:
	## A rival's fighting numbers: the floor tier they're met at, and a
	## little more for every time you've met before.
	var grow := 1.0 + 0.08 * met
	var t := maxi(tier, 1)
	var hp := int(round((60.0 * t + 40.0) * grow * (1.0 + 0.04 * t)))
	var dmg := int(round((5.5 * t + 6.0) * grow))
	return {"floor": -1, "name": "%s (%s)" % [r["name"], r["sect"]], "model": "human", "tint": r["tint"],
		"scale": 1.1, "hp": hp, "damage": dmg, "speed": 3.6, "aggro": 30, "range": 2.1 if r["kind"] != "spear" else 2.8,
		"cooldown": 1.0 if r["kind"] in ["dagger", "fists"] else 1.3, "qi": 30 * t, "loot": {}, "rival": r["name"], "kind": r["kind"]}


static func generate(level_id: String, state: Dictionary) -> Dictionary:
	## The arena for the current stage of whatever's being fought.
	var rounds: Array = state.get("rounds", [])
	var stage := int(state.get("stage", 0))
	if rounds.is_empty() or stage >= rounds.size():
		return {}
	var foes: Array = rounds[stage]
	var g := []
	for y in H:
		var row := ""
		for x in W:
			var dx := (x - W / 2.0 + 0.5) / (W / 2.0)
			var dy := (y - H / 2.0 + 0.5) / (H / 2.0)
			row += "." if dx * dx + dy * dy < 0.92 else " "
		g.append(row)
	var put := func(x: int, y: int, ch: String) -> void:
		var r: String = g[y]
		g[y] = r.substr(0, x) + ch + r.substr(x + 1)
	# lanterns and banners round the ring, the fighter's mark in the south
	for p in [Vector2i(5, 3), Vector2i(18, 3), Vector2i(2, 9), Vector2i(21, 9), Vector2i(5, 14), Vector2i(18, 14), Vector2i(12, 1), Vector2i(12, 16)]:
		put.call(p.x, p.y, "L")
	for p in [Vector2i(8, 2), Vector2i(15, 2), Vector2i(8, 15), Vector2i(15, 15)]:
		put.call(p.x, p.y, "=")
	put.call(12, 13, "P")
	var enemies := {}
	var letters := "abdegijkmnqruvwyz"
	var spots := [Vector2i(12, 5), Vector2i(9, 6), Vector2i(15, 6), Vector2i(7, 8), Vector2i(17, 8), Vector2i(10, 4), Vector2i(14, 4), Vector2i(12, 7)]
	var n := 0
	for f in foes:
		var eid := str(f.get("id", ""))
		var ch := letters[enemies.size() % letters.length()]
		enemies[ch] = eid
		for i in int(f.get("count", 1)):
			if n < spots.size():
				var sp: Vector2i = spots[n]
				put.call(sp.x, sp.y, ch)
				n += 1
	return {
		"id": level_id,
		"name": str(state.get("title", "The Arena")) + (" -- %s" % str(state.get("round_names", [])[stage]) if stage < state.get("round_names", []).size() else ""),
		"theme": "dungeon",
		"depth": int(state.get("depth", 1)),
		"arena": true,
		"ambient": [0.55, 0.48, 0.4],
		"map": g,
		"enemies": enemies,
		"chests": {},
		"exits": {},
	}
