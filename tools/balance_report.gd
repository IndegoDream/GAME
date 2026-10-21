extends SceneTree
## Balance report (round 71): every floor's foes, measured as the game really spawns them, against the
## cultivator the game expects on that floor (the floor forge's expected(): step 3n, realm step/10).
##   godot --headless --path . --script res://tools/balance_report.gd -- [out.json]
## For each floor: the player's hits-to-kill and seconds-to-kill a typical foe, the floor's brute and its
## boss; how many seconds those foes need to kill the player; and the jump from the floor before. Prints
## BALANCE lines and one "BALANCE DONE <n> floors, <m> flagged" line, and writes the JSON.
## Flags (data/combat.json "balance" -- defaults below): a regular foe that kills the expected player in under
## MIN_SURVIVE seconds, a boss over MAX_BOSS_TTK seconds of hitting, a regular foe over MAX_FOE_TTK, and any
## floor-to-floor jump in lethality over JUMP.

var _ids: Array = []
var _i := 0
var _frames := 0
var _level: Node3D
var _rows: Array = []
var _out := "user://balance_report.json"
var _cfg := {"min_survive": 7.0, "max_foe_ttk": 11.0, "max_boss_ttk": 150.0, "min_boss_ttk": 15.0, "jump": 0.4,
	"swing_s": 0.9, "hit_rate": 0.8, "uptime": 0.65}


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		_out = a[0]
	var d := DirAccess.open("res://levels")
	if d:
		for f in d.get_files():
			if f.begins_with("floor") and f.ends_with(".json"):
				_ids.append(f.get_basename())
	_ids.sort_custom(func(x, y): return int(x.trim_prefix("floor")) < int(y.trim_prefix("floor")))
	var C = JSON.parse_string(FileAccess.get_file_as_string("res://data/combat.json"))
	if C is Dictionary and C.get("balance") is Dictionary:
		for k in C["balance"]:
			_cfg[k] = C["balance"][k]


func expected(n: int) -> Dictionary:
	## the cultivator the floor forge tunes floor n for (godot_forge.expected)
	var s := 3 * n
	var r := int(s / 10)
	return {"step": s, "realm": r, "damage": (9.0 + 2.0 * s + 6.0 * r + 5.8 * n) * 1.3,
		"hp": (100.0 + 14.0 * s + 40.0 * r + 36.0 * n) * 1.15}


func _process(_delta: float) -> bool:
	if _i >= _ids.size():
		_finish()
		return true
	var id: String = _ids[_i]
	var game = root.get_node_or_null("Game")
	if _frames == 0:
		var def: Dictionary = game.load_level_def(id)
		var n := int(def.get("depth", int(id.trim_prefix("floor"))))
		game.depth = n
		var e := expected(n)
		game.realm = e["realm"]
		game.sublevel = (e["step"] % 10) + 1
		_level = load("res://scripts/world/Level.gd").new()
		_level.name = "Level"
		_level.build(def)
		root.add_child(_level)
	_frames += 1
	if _frames < 12:
		return false
	_measure(id)
	_level.queue_free()
	_level = null
	_frames = 0
	_i += 1
	return false


func _measure(id: String) -> void:
	var game = root.get_node("Game")
	var n := int(_level.def.get("depth", int(id.trim_prefix("floor"))))
	var e := expected(n)
	var foes: Array = []
	var boss := {}
	for node in get_nodes_in_group("enemy"):
		if not ("stats" in node):
			continue
		var st: Dictionary = node.stats
		var row := {"name": str(st.get("name", "")), "hp": float(st.get("hp", 1)), "damage": float(st.get("damage", 1)),
			"cooldown": float(st.get("cooldown", 1.3)), "boss": bool(st.get("boss", false)), "speed": float(st.get("speed", 3.0)),
			"elite": ("affixes" in node) and (node.affixes as Array).size() > 0, "passive": bool(st.get("passive", false))}
		if row["boss"]:
			if boss.is_empty() or row["hp"] > boss["hp"]:
				boss = row
		elif not row["passive"]:
			foes.append(row)              # (round 78: a hare in a haven isn't a fight -- the animals don't count)
	if foes.is_empty():
		var haven: bool = str(_level.def.get("theme", "")) == "settlement"
		_rows.append({"floor": n, "id": id, "skipped": "a haven: nothing to fight" if haven else "no foes spawned"})
		print("BALANCE floor %d: %s" % [n, "a haven (no fight)" if haven else "NO FOES SPAWNED"])
		return
	# a floor's typical foe: the median by hp; its brute: the toughest regular
	foes.sort_custom(func(x, y): return x["hp"] < y["hp"])
	var plain: Array = foes.filter(func(x): return not x["elite"])
	if plain.is_empty():
		plain = foes
	var typ: Dictionary = plain[plain.size() / 2]
	var brute: Dictionary = foes[foes.size() - 1]
	var elites: int = foes.size() - plain.size() if plain.size() < foes.size() else 0
	var pdmg: float = e["damage"]
	var php: float = e["hp"]
	var out := {"floor": n, "id": id, "step": e["step"], "realm": e["realm"], "player_damage": round(pdmg), "player_hp": round(php),
		"foes": foes.size(), "elites": elites, "typical": _ttk(typ, pdmg, php), "brute": _ttk(brute, pdmg, php),
		"boss": _ttk(boss, pdmg, php) if not boss.is_empty() else null, "flags": []}
	# three typical foes at once is the usual fight: lethality = seconds they need together
	out["pack_survive_s"] = out["typical"]["kills_player_s"] / 3.0
	var cfg := _cfg
	if out["pack_survive_s"] < float(cfg["min_survive"]):
		out["flags"].append("lethal: three %ss kill the expected player in %.1f s" % [typ["name"], out["pack_survive_s"]])
	if out["typical"]["player_ttk_s"] > float(cfg["max_foe_ttk"]):
		out["flags"].append("spongy: a %s takes %.1f s to kill" % [typ["name"], out["typical"]["player_ttk_s"]])
	if out["boss"] != null:
		if out["boss"]["player_ttk_s"] > float(cfg["max_boss_ttk"]):
			out["flags"].append("boss sponge: %s takes %.0f s" % [boss["name"], out["boss"]["player_ttk_s"]])
		elif out["boss"]["player_ttk_s"] < float(cfg["min_boss_ttk"]):
			out["flags"].append("boss pushover: %s falls in %.0f s" % [boss["name"], out["boss"]["player_ttk_s"]])
		if out["boss"]["kills_player_s"] < float(cfg["min_survive"]) * 2.0:
			out["flags"].append("boss too lethal: %s kills the expected player in %.0f s" % [boss["name"], out["boss"]["kills_player_s"]])
	var prev_i := _rows.size() - 1
	while prev_i >= 0 and _rows[prev_i].has("skipped"):
		prev_i -= 1                   # (round 78: the jump is from the last floor that had a fight -- the havens between don't break the climb)
	if prev_i >= 0:
		var prev: Dictionary = _rows[prev_i]
		var a: float = prev["pack_survive_s"]
		var b: float = out["pack_survive_s"]
		if a > 0 and absf(b - a) / a > float(cfg["jump"]):
			out["flags"].append("jump: lethality %s %.0f%% from floor %d" % ["up" if b < a else "down", absf(b - a) / a * 100.0, prev["floor"]])
	_rows.append(out)
	print("BALANCE floor %2d  player %4d dmg / %5d hp  |  %-18s ttk %5.1fs  kills you %6.1fs  |  pack %5.1fs  |  boss %s  %s" % [
		n, round(pdmg), round(php), typ["name"], out["typical"]["player_ttk_s"], out["typical"]["kills_player_s"], out["pack_survive_s"],
		("%s ttk %.0fs / kills you %.0fs" % [boss["name"], out["boss"]["player_ttk_s"], out["boss"]["kills_player_s"]]) if out["boss"] != null else "none",
		("  FLAG " + "; ".join(out["flags"])) if out["flags"].size() > 0 else ""])


func _ttk(foe: Dictionary, pdmg: float, php: float) -> Dictionary:
	## seconds for the expected player to kill this foe (hits at swing_s, hit_rate landing), and for the foe to
	## kill the player (its cooldown, uptime of its attacks landing)
	var hits := ceili(foe["hp"] / maxf(pdmg, 1.0))
	var player_ttk: float = hits * float(_cfg["swing_s"]) / float(_cfg["hit_rate"])
	var foe_hits := ceili(php / maxf(foe["damage"], 1.0))
	var kills_player: float = foe_hits * foe["cooldown"] / float(_cfg["uptime"])
	return {"name": foe["name"], "hp": foe["hp"], "damage": foe["damage"], "hits": hits, "player_ttk_s": snappedf(player_ttk, 0.1),
		"foe_hits": foe_hits, "kills_player_s": snappedf(kills_player, 0.1)}


func _finish() -> void:
	var flagged := 0
	for r in _rows:
		if r.has("flags") and r["flags"].size() > 0:
			flagged += 1
	var f := FileAccess.open(_out, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"cfg": _cfg, "floors": _rows}, "\t"))
	print("BALANCE DONE %d floors, %d flagged" % [_rows.size(), flagged])
	quit(0)
