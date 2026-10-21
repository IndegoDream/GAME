extends "res://scripts/systems/GameSystem.gd"
## The deep's reaches (round 56): which you've walked into, which hearts
## you've taken, which lands' keepsakes you hold. The reaches themselves are
## grown onto each floor as it's built (scripts/Reach.gd); this only
## remembers, and pays.
##
## First time into a reach: a line naming it, a little insight. Its heart
## (ReachHeart.gd), once its warden falls: gold by depth, the land's own
## materials, qi, and -- the first heart of each land, once a game -- that
## land's keepsake (a treasure with its own small gift). Ten lands; a
## completionist can find them all.

var seen := {}          # "floor7:0" -> biome key
var claimed := {}       # "floor7:0" -> true
var keepsakes := {}     # biome -> true


func setup(game) -> void:
	super.setup(game)
	var D: Dictionary = preload("res://scripts/world/Reach.gd").data()
	for bk in D.get("biomes", {}):
		var k: Dictionary = D["biomes"][bk].get("keepsake", {})
		var kid := str(k.get("id", ""))
		if kid != "" and not G.items.has(kid):
			G.items[kid] = {"name": str(k.get("name", kid)), "type": "treasure", "value": int(k.get("value", 300)),
				"effect": (k.get("effect", {}) as Dictionary).duplicate(), "desc": str(k.get("desc", "")), "reach": str(bk)}


func reset() -> void:
	seen = {}
	claimed = {}
	keepsakes = {}


func save_state() -> Dictionary:
	return {"seen": seen, "claimed": claimed, "keepsakes": keepsakes}


func load_state(d: Dictionary) -> void:
	seen = d.get("seen", {}) if d.get("seen", {}) is Dictionary else {}
	claimed = d.get("claimed", {}) if d.get("claimed", {}) is Dictionary else {}
	keepsakes = d.get("keepsakes", {}) if d.get("keepsakes", {}) is Dictionary else {}


func biome(bk: String) -> Dictionary:
	return preload("res://scripts/world/Reach.gd").biome(bk)


func key(level_id: String, i: int) -> String:
	return "%s:%d" % [level_id, i]


func entered(level_id: String, r: Dictionary) -> bool:
	## true the first time (this game) you walk into this reach
	var k := key(level_id, int(r.get("i", 0)))
	if seen.has(k):
		return false
	var bk := str(r.get("biome", ""))
	var new_land := not seen.values().has(bk)
	seen[k] = bk
	var B := biome(bk)
	var D: Dictionary = preload("res://scripts/world/Reach.gd").data()
	G.gain_insight(float(D.get("insight_first", 2.0)) * (2.0 if new_land else 1.0), "a reach of the deep")
	G.message.emit(I18n.t("A REACH OF THE DEEP: %s. %s") % [str(B.get("name", bk)), str(B.get("desc", ""))])
	G.log_event("reach_found", {"biome": bk, "level": level_id, "new_land": new_land})
	G.stats_changed.emit()
	return true


func is_claimed(level_id: String, i: int) -> bool:
	return claimed.has(key(level_id, i))


func claim(level_id: String, i: int, bk: String, depth: int) -> Dictionary:
	## the heart's store, once a game. Returns what it gave.
	var k := key(level_id, i)
	if claimed.has(k):
		return {}
	claimed[k] = true
	var D: Dictionary = preload("res://scripts/world/Reach.gd").data()
	var B := biome(bk)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(k + ":heart")
	var got := {}
	var gold := int(D.get("heart_gold_per_depth", 18)) * maxi(1, depth) + rng.randi_range(10, 40)
	G.add_item("gold", gold, false)
	got["gold"] = gold
	var mr: Array = D.get("heart_mats", [3, 6])
	for row in [[str(B.get("material", "")), rng.randi_range(int(mr[0]), int(mr[1]))], [str(B.get("material2", "")), rng.randi_range(1, 3)]]:
		if str(row[0]) != "" and G.has_item_def(str(row[0])):
			G.add_item(str(row[0]), int(row[1]), false)
			got[str(row[0])] = int(row[1])
	var kid := str(B.get("keepsake", {}).get("id", ""))
	if kid != "" and not keepsakes.has(bk) and G.items.has(kid):
		keepsakes[bk] = true
		G.add_item(kid, 1, false)
		got[kid] = 1
	var qi: float = float(D.get("heart_qi_kills", 8)) * _kill_qi(depth) * float(G.KILL_QI_MULT)
	G.add_qi(qi, "a reach's heart")
	got["qi"] = int(qi)
	G.log_event("reach_heart", {"biome": bk, "level": level_id})
	G.stats_changed.emit()
	return got


func _kill_qi(depth: int) -> float:
	var tot := 0.0
	var n := 0
	for eid in G.enemies:
		var s: Dictionary = G.enemies[eid]
		if int(s.get("floor", -1)) == depth and not bool(s.get("boss", false)) and not bool(s.get("passive", false)):
			tot += float(s.get("qi", 0))
			n += 1
	return tot / n if n > 0 else 10.0 * pow(1.4, depth)


func lands_found() -> Array:
	var out := []
	for v in seen.values():
		if not out.has(str(v)):
			out.append(str(v))
	out.sort()
	return out


func summary() -> Dictionary:
	var all: Dictionary = preload("res://scripts/world/Reach.gd").data().get("biomes", {})
	return {"lands": lands_found().size(), "of": all.size(), "reaches": seen.size(), "hearts": claimed.size(), "keepsakes": keepsakes.size()}
