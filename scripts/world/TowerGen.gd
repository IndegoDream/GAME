extends RefCounted
## One floor of a valley tower (round 24): a round stone room, the stair
## down where you came in, and in the middle the floor's trial
## (TowerTrial.gd). The stair up appears when the trial is passed.
##
## Level id: "tower:<tower id>:<floor 1-9>". The tower itself -- its name,
## its floors' names, kinds and trials -- is in data/valley.json.

const R := 8          # the room's radius in cells


static func is_tower(level_id: String) -> bool:
	return level_id.begins_with("tower:")


static func parse(level_id: String) -> Dictionary:
	var p := level_id.split(":")
	if p.size() != 3 or not p[2].is_valid_int():
		return {}
	return {"id": p[1], "n": clampi(int(p[2]), 1, 9)}


static func make_id(tid: String, n: int) -> String:
	return "tower:%s:%d" % [tid, n]


static func generate(level_id: String, t: Dictionary, door_letter: String) -> Dictionary:
	var pr := parse(level_id)
	if pr.is_empty() or t.is_empty():
		return {}
	var n: int = pr["n"]
	var floors: Array = t.get("floors", [])
	var f: Dictionary = floors[n - 1] if n - 1 < floors.size() else {"name": "Floor %d" % n, "kind": "combat", "trial": ""}
	var size := R * 2 + 5
	var c := Vector2i(size / 2, size / 2)
	var rows := []
	for y in size:
		var row := ""
		for x in size:
			var d := Vector2(x - c.x, y - c.y).length()
			row += "." if d <= R + 0.3 else " "
		rows.append(row)
	var put := func(q: Vector2i, ch: String) -> void:
		var row: String = rows[q.y]
		rows[q.y] = row.substr(0, q.x) + ch + row.substr(q.x + 1)
	# torches round the wall, the stair down at the south, the way up north
	for i in 8:
		var a := TAU * i / 8.0 + PI / 8.0
		put.call(c + Vector2i(int(round(cos(a) * (R - 1))), int(round(sin(a) * (R - 1)))), "L")
	put.call(Vector2i(c.x, c.y + R), "<")
	var tier := int(t.get("tier", 1))
	var down := {"to": "valley", "arrive": door_letter, "label": "Out to the valley", "down": true} if n == 1 \
		else {"to": make_id(str(pr["id"]), n - 1), "arrive": "up", "label": "Down to floor %d" % (n - 1), "down": true}
	return {"id": level_id, "name": "%s -- %s" % [t.get("name", I18n.t("A tower")), f.get("name", I18n.t("Floor %d") % n)],
		"theme": "dungeon", "look": str(t.get("look", "barrows")), "depth": int({1: 3, 2: 8, 3: 15}.get(tier, 3)) + n / 3,
		"no_expand": true, "map": rows, "exits": {"<": down}, "enemies": {},
		"up_cell": [c.x, c.y - R + 1], "centre": [c.x, c.y],
		"tower": {"id": str(pr["id"]), "n": n, "kind": str(f.get("kind", "combat")), "trial": str(f.get("trial", "")),
			"floor_name": str(f.get("name", "")), "tier": tier, "name": str(t.get("name", ""))}}
