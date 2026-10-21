extends Node3D
## Something to gather. Press E next to it; it regrows after a while (real
## time, even while the game is closed), so the economy keeps turning.
##   'o' ore vein     -- iron (silver deep down). Mining.
##   'h' plant        -- a spirit herb, or on deeper floors ember root,
##                       moonpetal or iron thistle. Herbalism.
##   '^' glittering vein -- gold, jade, ruby, sapphire, silver. Mining.
##   '&' fishing spot -- cast a line and wait. Fishing.
## The better the skill, the more comes out -- and the rarer it can be.

const REGROW_SECONDS := 600.0
const GEM_REGROW_SECONDS := 1800.0
const FISH_REGROW_SECONDS := 90.0
const CAST_SECONDS := 2.5

const PLANTS := {
	"spirit_herb": {"color": Color(0.6, 1.0, 0.75), "min_depth": 0},
	"ember_root": {"color": Color(1.0, 0.5, 0.35), "min_depth": 2},
	"iron_thistle": {"color": Color(0.7, 0.75, 0.8), "min_depth": 2},
	"moonpetal": {"color": Color(0.75, 0.8, 1.0), "min_depth": 3},
}

var kind := "ore"
var cell := Vector2i.ZERO
var level
var plant := "spirit_herb"
var _key := ""
var _model: Node3D
var _casting := false
var yields := ""            # round 30: a meteor's star iron (a world event) instead of the floor's ore
var region := {}            # round 123: what grows and is dug only in this place (def.gather: herb / ore / gem lists)
var ore_item := ""
var plant_color := Color(0.6, 1.0, 0.75)


func setup(lvl, args: Dictionary) -> void:
	level = lvl
	kind = str(args.get("kind", "ore"))
	cell = args.get("cell", Vector2i.ZERO)
	yields = str(args.get("yields", ""))
	_key = Game.flag_key(level.level_id, cell, "gathered")
	region = level.def.get("gather", {}) if level != null and level.def.get("gather", {}) is Dictionary else {}
	if kind == "herb":
		plant = _pick_plant()
	elif kind == "ore" and yields == "" and region.has("ore"):
		ore_item = str(_pick_from(region["ore"])["id"])


func _depth() -> int:
	return int(level.def.get("depth", 0)) if level != null else 0


func _pick_from(list: Array) -> Dictionary:
	## a weighted pick that is fixed per spot (the same spot always gives the same thing)
	var r := RandomNumberGenerator.new()
	r.seed = hash("%s:%d,%d:pick" % [level.level_id, cell.x, cell.y])
	var tot := 0.0
	for e in list:
		tot += float(e.get("w", 1))
	var roll := r.randf() * tot
	for e in list:
		roll -= float(e.get("w", 1))
		if roll <= 0.0:
			return e
	return list[list.size() - 1]


func _pick_plant() -> String:
	## Which plant grows here is fixed per spot (the same herb regrows),
	## chosen from what this depth can grow -- or, in a place with its own flora (round 123), from that.
	if region.has("herb") and not (region["herb"] as Array).is_empty():
		var e := _pick_from(region["herb"])
		var col: Array = e.get("color", [0.6, 1.0, 0.75])
		plant_color = Color(float(col[0]), float(col[1]), float(col[2]))
		return str(e["id"])
	var r := RandomNumberGenerator.new()
	r.seed = hash("%s:%d,%d" % [level.level_id, cell.x, cell.y])
	var roll := r.randf()
	var d := _depth()
	if d >= 3 and roll < 0.25:
		return "moonpetal"
	if d >= 2 and roll < 0.45:
		return "ember_root" if roll < 0.32 else "iron_thistle"
	return "spirit_herb"


func _ready() -> void:
	add_to_group("interactable")
	match kind:
		"herb":
			_model = preload("res://scripts/core/Art.gd").make("nature-kit/plant_bushDetailed.glb")
			_model.scale = Vector3.ONE * 2.2
			var c: Color = plant_color if region.has("herb") else PLANTS.get(plant, PLANTS["spirit_herb"])["color"]
			_tint(_model, c)
			var glow := OmniLight3D.new()
			glow.light_color = c
			glow.omni_range = 3.0
			glow.light_energy = 0.8
			glow.position = Vector3(0, 0.6, 0)
			add_child(glow)
		"gem":
			_model = preload("res://scripts/core/Art.gd").make("mini-dungeon/rocks.glb")
			_model.scale = Vector3.ONE * 1.7
			_tint(_model, Color(0.95, 0.75, 1.0))
			var sparkle := OmniLight3D.new()
			sparkle.light_color = Color(1.0, 0.85, 1.0)
			sparkle.omni_range = 2.6
			sparkle.light_energy = 1.2
			sparkle.position = Vector3(0, 0.8, 0)
			add_child(sparkle)
		"fish":
			_model = Node3D.new()
			var bob := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.12
			sm.height = 0.24
			bob.mesh = sm
			var m := StandardMaterial3D.new()
			m.albedo_color = Color(1.0, 0.35, 0.3)
			m.emission_enabled = true
			m.emission = Color(1.0, 0.3, 0.2)
			bob.material_override = m
			bob.position = Vector3(0, 0.15, 0)
			_model.add_child(bob)
			var ripple := OmniLight3D.new()
			ripple.light_color = Color(0.5, 0.8, 1.0)
			ripple.omni_range = 2.5
			ripple.light_energy = 0.7
			ripple.position = Vector3(0, 0.5, 0)
			_model.add_child(ripple)
		_:
			_model = preload("res://scripts/core/Art.gd").make("mini-dungeon/rocks.glb")
			_model.scale = Vector3.ONE * 1.6
			_tint(_model, Color(1.0, 0.85, 0.6) if _deep() else Color(0.75, 0.8, 1.0))
	add_child(_model)
	_refresh()


func _deep() -> bool:
	return _depth() >= 3


func _regrow() -> float:
	return GEM_REGROW_SECONDS if kind == "gem" else (FISH_REGROW_SECONDS if kind == "fish" else REGROW_SECONDS)


func _refresh() -> void:
	var gone := Game.gathered_recently(_key, _regrow())
	_model.visible = not gone
	if gone:
		remove_from_group("interactable")
	elif not is_in_group("interactable"):
		add_to_group("interactable")


func _process(_delta: float) -> void:
	if not _model.visible and not Game.gathered_recently(_key, _regrow()):
		_refresh()


func prompt() -> String:
	match kind:
		"herb":
			return "E: Pick the " + Game.item_name(plant)
		"gem":
			return "E: Chip at the glittering vein"
		"fish":
			return "E: Cast a line" if not _casting else "(waiting for a bite...)"
		"ore":
			if ore_item != "":
				return "E: Mine the " + Game.item_name(ore_item)
	return "E: Mine the ore vein"


func _skill() -> String:
	return {"herb": "herbalism", "gem": "mining", "fish": "fishing"}.get(kind, "mining")


func _extra(lvl: int) -> int:
	## Skill and Wood affinity (and the Gatherers): a chance of more,
	## growing without a cap.
	var n := 0
	var extra := lvl * 0.04 + Game.tech_effect("gather_chance", 0.0) + Game.focus_bonus(_skill()) * 0.3   # (focus: in the rhythm of it)
	while extra > 0.0:
		if randf() < minf(extra, 1.0):
			n += 1
		extra -= 1.0
	return n


func interact(_player) -> void:
	if Game.gathered_recently(_key, _regrow()) or _casting:
		return
	if kind == "fish":
		_cast()
		return
	Game.set_flag(_key, Time.get_unix_time_from_system())
	var sk := _skill()
	var lvl := Game.skill_level(sk)
	var n := randi_range(1, 2) + int(Game.tech_effect("gather_bonus", 0.0)) + _extra(lvl)
	match kind:
		"herb":
			Game.add_item(plant, n)
			if plant != "spirit_herb" and randf() < 0.3:
				Game.add_item("spirit_herb", 1)
			Game.add_qi(2.0)
		"gem":
			for i in maxi(1, n - 1):
				Game.add_item(gem_roll(randf(), lvl), 1)
		_:
			Game.add_item(yields if yields != "" else (ore_item if ore_item != "" else ("silver_ore" if _deep() else "iron_ore")), n)
	Game.add_skill_xp(sk, (10.0 if kind == "gem" else 6.0) + float(_depth()) * 2.0, "gathering")
	Game.sfx("herb" if kind == "herb" else ("crystal" if kind == "gem" else "mine"), 0.8)
	Game.guild_event("gather")
	Game.log_event("gather", {"kind": kind, "n": n, "plant": plant if kind == "herb" else ""})
	_refresh()


func gem_roll(r: float, lvl: int) -> String:
	## What a glittering vein gives. Depth opens the rarer stones; skill
	## tilts the odds toward them.
	var d := _depth()
	var tilt := lvl * 0.01
	if region.has("gem") and not (region["gem"] as Array).is_empty():
		var tot := 0.0
		for e in region["gem"]:
			tot += float(e.get("w", 1))
		var roll := r * tot
		for e2 in region["gem"]:
			roll -= float(e2.get("w", 1))
			if roll <= 0.0:
				return str(e2["id"])
		return str(region["gem"][0]["id"])
	if d >= 3 and r < 0.08 + tilt:
		return "sapphire_shard"
	if d >= 2 and r < 0.2 + tilt * 2.0:
		return "rough_ruby"
	if r < 0.5 + tilt:
		return "rough_jade"
	if r < 0.8:
		return "gold_nugget"
	return "silver_ore"


func _cast() -> void:
	_casting = true
	Game.message.emit("You cast a line into the dark water...")
	get_tree().create_timer(CAST_SECONDS).timeout.connect(_land)


func land_now() -> void:
	## (tools) skip the wait
	_land()


func _land() -> void:
	if not _casting:
		return
	_casting = false
	Game.set_flag(_key, Time.get_unix_time_from_system())
	var lvl := Game.skill_level("fishing")
	var r := randf()
	var bite := 0.55 + lvl * 0.04
	if r > bite:
		Game.message.emit("Nothing bites. The water keeps its secrets -- for now.")
		Game.add_skill_xp("fishing", 2.0, "patience")
		_refresh()
		return
	var catch := "cave_carp"
	if lvl >= 3 and randf() < 0.15 + lvl * 0.02:
		catch = "glowfin_eel"
	Game.add_item(catch, 1 + _extra(lvl))
	if randf() < 0.02 + lvl * 0.004:
		Game.message.emit("Something glints in the line -- a stone the current carried down.")
		Game.add_item("sapphire_shard", 1)
	Game.add_skill_xp("fishing", 8.0 + float(_depth()) * 2.0, "fishing")
	Game.guild_event("gather")
	Game.log_event("gather", {"kind": "fish", "catch": catch})
	_refresh()


func _tint(n: Node, c: Color) -> void:
	if n is MeshInstance3D:
		for i in n.get_surface_override_material_count():
			var m = n.get_active_material(i)
			if m is StandardMaterial3D:
				var mm: StandardMaterial3D = m.duplicate()
				mm.albedo_color = mm.albedo_color * c
				n.set_surface_override_material(i, mm)
	for ch in n.get_children():
		_tint(ch, c)
