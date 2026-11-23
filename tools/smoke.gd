extends SceneTree
## Smoke test: builds levels for real and checks them, headless.
##   godot --headless --path . --script res://tools/smoke.gd -- floor2
## With no level id, checks every file in res://levels/.
## Prints one "SMOKE OK <id> ..." or "SMOKE FAIL <id>: ..." line per level.
## Godot Studio runs this before any level file Dev writes goes live.

var _ids: Array = []
var _i := 0
var _frames := 0
var _level: Node3D
var _player: CharacterBody3D
var _fails := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_ids = args
	else:
		var d := DirAccess.open("res://levels")
		if d:
			for f in d.get_files():
				if f.ends_with(".json"):
					_ids.append(f.get_basename())
		# round 24: the places drawn when entered -- the valley, and the first
		# and last floor of every tower in data/valley.json
		if FileAccess.file_exists("res://data/valley.json"):
			_ids.append("valley")
			var v = JSON.parse_string(FileAccess.get_file_as_string("res://data/valley.json"))
			if v is Dictionary:
				for t in v.get("towers", []):
					for n in [1, 9]:
						_ids.append("tower:%s:%d" % [t.get("id", ""), n])
		# round 123: the tech frontier's regions
		if FileAccess.file_exists("res://data/frontier.json"):
			var fj = JSON.parse_string(FileAccess.get_file_as_string("res://data/frontier.json"))
			if fj is Dictionary:
				for rid in fj.get("regions", {}):
					_ids.append("frontier:%s" % rid)
		# round 30: today's daily trial (it's drawn from the date and how deep you've come)
		if FileAccess.file_exists("res://scripts/world/TrialGen.gd"):
			_ids.append(load("res://scripts/world/TrialGen.gd").make_id(Time.get_date_string_from_system()))
	_ids.sort()


func _process(_delta: float) -> bool:
	if _i >= _ids.size():
		print("SMOKE DONE %d level(s), %d failed" % [_ids.size(), _fails])
		quit(1 if _fails > 0 else 0)
		return true
	var id: String = _ids[_i]
	var game = root.get_node_or_null("Game")
	if _frames == 0:
		if game == null:
			print("SMOKE FAIL %s: the Game autoload isn't loaded" % id)
			_fails += 1
			_i += 1
			return false
		var def: Dictionary = game.load_level_def(id)
		if def.is_empty():
			print("SMOKE FAIL %s: levels/%s.json is missing or isn't valid JSON" % [id, id])
			_fails += 1
			_i += 1
			return false
		_level = load("res://scripts/world/Level.gd").new()
		_level.name = "Level"
		_level.build(def)
		root.add_child(_level)
		_player = load("res://scripts/actors/Player.gd").new()
		root.add_child(_player)
		_player.global_position = _level.spawn_point("P")
	_frames += 1
	if _frames < 20:
		return false
	# checks
	var problems: Array = []
	for w in _level.warnings:
		problems.append(w)
	if _player.global_position.y < -2.0:
		problems.append("the player fell through the floor at the start point")
	if _level.def.get("theme", "dungeon") == "dungeon" and str(_level.def.get("online", "")) == "" and int(_level.counts.get("exits", 0)) == 0:
		problems.append("a dungeon floor with no exits")
	var c: Dictionary = _level.counts
	var summary := "%dx%d walls=%d enemies=%d chests=%d exits=%d traps=%d secrets=%d ore=%d herbs=%d npcs=%d lights=%d lore=%d inheritances=%d gems=%d fishing=%d" % [
		_level.width, _level.height, int(c.get("walls", 0)), int(c.get("enemies", 0)), int(c.get("chests", 0)),
		int(c.get("exits", 0)), int(c.get("traps", 0)), int(c.get("secrets", 0)), int(c.get("ore", 0)),
		int(c.get("herbs", 0)), int(c.get("npcs", 0)), int(c.get("lights", 0)),
		int(c.get("lore", 0)), int(c.get("inheritances", 0)), int(c.get("gems", 0)), int(c.get("fishing", 0))]
	if problems.is_empty():
		print("SMOKE OK %s %s" % [id, summary])
	else:
		_fails += 1
		print("SMOKE FAIL %s: %s" % [id, "; ".join(problems)])
	_player.queue_free()
	_level.queue_free()
	_frames = 0
	_i += 1
	return false
