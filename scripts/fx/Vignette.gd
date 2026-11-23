extends Node3D
## A little scene on a dungeon floor -- environmental storytelling (Robert,
## 2026-10-02). A cold camp, someone who didn't make it, a small shrine
## somebody still tends, the aftermath of a fight, someone's stash. Built
## from props so you SEE it before you read it; press E to look closer and
## read what it tells you (data/vignettes.json -- a region's own lines
## first). The first look sometimes turns something up, and always teaches
## you a little about surviving down here. Placed by Level._place_vignettes
## where there's open floor, away from the stairs.

const K := "res://assets/kenney/"
const LOOK_RADIUS := 2.6

var level
var cell := Vector2i.ZERO
var kind := "camp"
var look_key := ""
var _seed := 0
var _key := ""
var index := 0
var legacy := false        # a lost workshop whose master still sits there (upper floors)
var _legacy_key := ""
var _ghost: Node3D
var _aura: OmniLight3D
const WORKSHOPS := ["smithy", "alchemy_lab", "apothecary", "jeweler", "herb_garden"]
const CRAFT_OF := {"smithy": "smithing", "alchemy_lab": "alchemy", "apothecary": "medicine", "jeweler": "jewelcrafting", "herb_garden": "herbalism"}
const LEGACY_SKILL := 2
var _rng := RandomNumberGenerator.new()
static var _text := {}


func setup(lvl, args: Dictionary) -> void:
	level = lvl
	cell = args.get("cell", Vector2i.ZERO)
	kind = str(args.get("kind", "camp"))
	look_key = str(args.get("look", ""))
	_seed = int(args.get("seed", 0))
	index = int(args.get("index", 0))
	legacy = bool(args.get("legacy", false)) and kind in WORKSHOPS
	# keyed by the floor and the scene's number, not its cell: a floor the
	# forge grows later redraws its map, and a scene already looked at (or a
	# legacy already given) must stay that way
	_key = "vignette:%s:%d" % [level.level_id, index]
	_legacy_key = "legacy:%s" % level.level_id


func _ready() -> void:
	_rng.seed = _seed
	match kind:
		"camp":
			_camp()
		"fallen":
			_fallen()
		"shrine":
			_shrine()
		"battle":
			_battle()
		"smithy":
			_smithy()
		"alchemy_lab":
			_alchemy_lab()
		"apothecary":
			_apothecary()
		"jeweler":
			_jeweler()
		"herb_garden":
			_herb_garden()
		_:
			_cache()
	if legacy:
		_seat_master()
	add_to_group("interactable")
	if legacy and not Game.has_flag(_legacy_key):
		add_to_group("discoverable")


func _process(_delta: float) -> void:
	if _aura and not Game.has_flag(_legacy_key):
		_aura.light_energy = 1.1 + sin(Time.get_ticks_msec() / 450.0) * 0.35


# ---- what you see -----------------------------------------------------------------

func _prop(path: String, at: Vector3, s: float, yaw: float = 0.0) -> Node3D:
	if not ResourceLoader.exists(K + path):
		return Node3D.new()
	var m: Node3D = preload("res://scripts/core/Art.gd").make(path, _rng.randi() % 7)
	m.position = at
	m.scale = Vector3.ONE * s
	m.rotation.y = yaw
	add_child(m)
	return m


func _light(at: Vector3, c: Color, e: float, r: float) -> void:
	var l := OmniLight3D.new()
	l.light_color = c
	l.light_energy = e
	l.omni_range = r
	l.position = at
	add_child(l)


func _j() -> float:
	return _rng.randf_range(-0.3, 0.3)


func _camp() -> void:
	_prop("nature-kit/campfire_stones.glb", Vector3.ZERO, 1.8, _rng.randf() * TAU)
	_prop("nature-kit/tent_smallOpen.glb", Vector3(1.6 + _j(), 0, -1.0 + _j()), 1.4, _rng.randf_range(2.4, 3.6))
	_prop("nature-kit/log.glb", Vector3(-1.2 + _j(), 0, 0.9 + _j()), 1.2, _rng.randf() * TAU)
	_prop("mini-dungeon/pot.glb", Vector3(0.9, 0, 1.1), 1.6)
	_light(Vector3(0, 0.4, 0), Color(1.0, 0.45, 0.15), 0.35, 2.5)      # the last warmth in the ashes


func _fallen() -> void:
	var fspec: Dictionary = preload("res://scripts/world/Dress.gd").spec_for("fallen%d" % _seed, "villager", {"cape": [0.3, 0.28, 0.3]})
	var body: Node3D = preload("res://scripts/core/Art.gd").person(fspec)
	body.rotation.y = _rng.randf() * TAU
	add_child(body)
	preload("res://scripts/world/Dress.gd").dress(body, fspec)
	var ap := _find_anim(body)
	if ap and ap.has_animation("die"):
		ap.play("die")
		ap.seek(ap.get_animation("die").length, true)
		ap.pause()
	if DisplayServer.get_name() != "headless":
		_pale(body)
	var sw := _prop("mini-dungeon/weapon-sword.glb", Vector3(1.1 + _j(), 0.05, 0.4 + _j()), 1.6, _rng.randf() * TAU)
	sw.rotation.x = PI / 2
	_prop("mini-dungeon/shield-round.glb", Vector3(-0.9 + _j(), 0.1, -0.7 + _j()), 1.3, _rng.randf() * TAU).rotation.z = PI / 2.2
	_prop("mini-dungeon/stones.glb", Vector3(0.4, 0, -1.2), 1.2, _rng.randf() * TAU)


func _shrine() -> void:
	var piece := "nature-kit/statue_columnDamaged.glb" if _rng.randf() < 0.5 else "nature-kit/statue_head.glb"
	_prop(piece, Vector3(0, 0, -0.6), 1.3 if piece.contains("head") else 1.0)
	for i in 4:
		var a := TAU * i / 4.0 + _rng.randf() * 0.4
		var at := Vector3(cos(a) * 0.9, 0, sin(a) * 0.9 + 0.3)
		var candle := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.05
		cm.bottom_radius = 0.06
		cm.height = 0.22 + _rng.randf() * 0.15
		candle.mesh = cm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.95, 0.92, 0.8)
		candle.material_override = mat
		candle.position = at + Vector3(0, cm.height / 2.0, 0)
		add_child(candle)
		var flame := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.04
		sm.height = 0.1
		flame.mesh = sm
		var fm := StandardMaterial3D.new()
		fm.albedo_color = Color(1.0, 0.75, 0.3)
		fm.emission_enabled = true
		fm.emission = Color(1.0, 0.65, 0.2)
		fm.emission_energy_multiplier = 4.0
		fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		flame.material_override = fm
		flame.position = at + Vector3(0, cm.height + 0.05, 0)
		add_child(flame)
	_prop("nature-kit/pot_small.glb", Vector3(0.3, 0, 0.6), 1.6)
	_light(Vector3(0, 0.9, 0.2), Color(1.0, 0.75, 0.4), 0.8, 4.0)


func _battle() -> void:
	var scorch := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 1.6
	cm.bottom_radius = 1.6
	cm.height = 0.01
	scorch.mesh = cm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.05, 0.04, 0.04, 0.75)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	scorch.material_override = m
	scorch.position = Vector3(0, 0.035, 0)
	add_child(scorch)
	for i in 3:
		var w := "mini-dungeon/weapon-sword.glb" if i != 1 else "mini-dungeon/weapon-spear.glb"
		var p := _prop(w, Vector3(_rng.randf_range(-1.4, 1.4), 0.45, _rng.randf_range(-1.4, 1.4)), 1.6, _rng.randf() * TAU)
		p.rotation.x = deg_to_rad(_rng.randf_range(60, 110))
	var sh := _prop("mini-dungeon/shield-rectangle.glb", Vector3(_j() * 2, 0.08, _j() * 2), 1.4, _rng.randf() * TAU)
	sh.rotation.x = PI / 2
	_prop("mini-dungeon/rocks.glb", Vector3(-1.2, 0, 1.0), 0.8, _rng.randf() * TAU)


func _cache() -> void:
	_prop("mini-dungeon/barrel.glb", Vector3(-0.7, 0, -0.4), 1.6)
	_prop("mini-dungeon/barrel.glb", Vector3(-0.2, 0, -0.9), 1.6, 0.7)
	_prop("mini-dungeon/pot.glb", Vector3(0.6, 0, -0.6), 1.6)
	_prop("nature-kit/pot_large.glb", Vector3(0.9, 0, 0.3), 1.2)
	_prop("mini-dungeon/table.glb", Vector3(-0.4, 0, 0.8), 1.4, _rng.randf() * TAU)


# ---- lost workshops -------------------------------------------------------------------

func _glow_mat(c: Color, e: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = e
	return m


func _bits(n: int, colors: Array, r: float, at: Vector3, spread: float, glow: float) -> void:
	for i in n:
		var b := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = r
		sm.height = r * 2.0
		sm.radial_segments = 6
		sm.rings = 3
		b.mesh = sm
		b.material_override = _glow_mat(colors[i % colors.size()], glow)
		b.position = at + Vector3(_rng.randf_range(-spread, spread), 0, _rng.randf_range(-spread * 0.6, spread * 0.6))
		add_child(b)


func _smithy() -> void:
	var forge := _prop("nature-kit/campfire_bricks.glb", Vector3(-0.9, 0, -0.6), 2.0)
	forge.scale.y = 2.6
	var anvil := _prop("nature-kit/statue_block.glb", Vector3(0.5, 0, -0.2), 0.55)
	anvil.scale = Vector3(0.6, 0.45, 0.35)
	var sw := _prop("mini-dungeon/weapon-sword.glb", Vector3(0.5, 0.5, -0.2), 1.3, 0.3)
	sw.rotation.x = PI / 2
	_prop("mini-dungeon/barrel.glb", Vector3(1.2, 0, 0.6), 1.5)
	_prop("mini-dungeon/wood-support.glb", Vector3(-1.4, 0, 0.7), 1.2)
	for i in 3:
		var w := _prop("mini-dungeon/weapon-sword.glb" if i != 1 else "mini-dungeon/weapon-spear.glb", Vector3(-0.2 + i * 0.35, 0.55, -1.25), 1.3)
		w.rotation.z = 0.15
	_light(Vector3(-0.9, 0.5, -0.6), Color(1.0, 0.4, 0.1), 0.6, 2.5)     # an ember that never quite went out


func _alchemy_lab() -> void:
	_prop("mini-dungeon/table.glb", Vector3(0, 0, -0.5), 1.6)
	for i in 4:
		var bottle := _prop("mini-dungeon/potion.glb", Vector3(-0.45 + i * 0.3, 0.75, -0.5 + _j() * 0.3), 0.8)
		var cols := [Color(0.4, 1.0, 0.5), Color(0.9, 0.3, 1.0), Color(1.0, 0.6, 0.2), Color(0.3, 0.7, 1.0)]
		if DisplayServer.get_name() != "headless":
			_glow_all(bottle, cols[i], 1.4)
	var cauldron := _prop("nature-kit/pot_large.glb", Vector3(1.0, 0, 0.5), 1.6)
	_bits(1, [Color(0.4, 1.0, 0.45)], 0.22, Vector3(1.0, 0.55, 0.5), 0.0, 2.5)
	_prop("nature-kit/campfire_stones.glb", Vector3(1.0, 0, 0.5), 1.2)
	_prop("nature-kit/pot_small.glb", Vector3(-1.1, 0, 0.6), 1.6)
	_light(Vector3(1.0, 0.9, 0.5), Color(0.45, 1.0, 0.5), 0.9, 3.0)
	cauldron.rotation.y = _rng.randf() * TAU


func _apothecary() -> void:
	_prop("mini-dungeon/table.glb", Vector3(0, 0, -0.5), 1.6)
	_prop("mini-dungeon/chair.glb", Vector3(0, 0, 0.3), 1.4, PI)
	for i in 3:
		_prop("nature-kit/pot_small.glb", Vector3(-1.2 + i * 0.4, 0, 0.9), 1.4)
		_prop("nature-kit/plant_flatShort.glb", Vector3(-1.2 + i * 0.4, 0.3, 0.9), 1.0)
	_prop("mini-dungeon/potion.glb", Vector3(-0.3, 0.75, -0.5), 1.4)
	_prop("nature-kit/grass_leafs.glb", Vector3(0.4, 0.78, -0.55), 1.0)
	_light(Vector3(0, 1.2, -0.3), Color(1.0, 0.9, 0.7), 0.5, 3.0)


func _jeweler() -> void:
	_prop("mini-dungeon/table.glb", Vector3(0, 0, -0.4), 1.5)
	_prop("mini-dungeon/chair.glb", Vector3(0, 0, 0.35), 1.4, PI)
	for i in 4:
		_prop("mini-dungeon/coin.glb", Vector3(_rng.randf_range(-0.5, 0.5), 0.72, -0.4 + _j() * 0.4), 0.9, _rng.randf() * TAU)
	_bits(6, [Color(0.3, 1.0, 0.6), Color(1.0, 0.25, 0.3), Color(0.35, 0.55, 1.0)], 0.05, Vector3(0, 0.76, -0.45), 0.5, 2.0)
	_prop("mini-dungeon/stones.glb", Vector3(1.1, 0, 0.5), 1.0)
	_light(Vector3(0, 1.1, -0.4), Color(0.85, 0.9, 1.0), 0.6, 2.5)


func _herb_garden() -> void:
	for i in 6:
		var a := TAU * i / 6.0
		var at := Vector3(cos(a) * 1.2, 0, sin(a) * 1.0)
		var plants := ["nature-kit/plant_bush.glb", "nature-kit/crops_leafsStageB.glb", "nature-kit/flower_purpleA.glb", "nature-kit/plant_flatTall.glb"]
		_prop(plants[i % plants.size()], at, 1.6, _rng.randf() * TAU)
	_prop("nature-kit/pot_large.glb", Vector3(0, 0, 0), 1.2)
	_prop("nature-kit/stone_smallFlatA.glb", Vector3(0.6, 0, -0.3), 1.6)
	_bits(5, [Color(0.6, 1.0, 0.5)], 0.04, Vector3(0, 0.6, 0), 1.2, 2.0)
	_light(Vector3(0, 2.0, 0), Color(0.8, 1.0, 0.7), 0.7, 4.0)


func _glow_all(n: Node, c: Color, e: float) -> void:
	if n is MeshInstance3D:
		n.material_override = _glow_mat(c, e)
	for ch in n.get_children():
		_glow_all(ch, c, e)


func _seat_master() -> void:
	## The master, still at their work: seated, faintly luminous until the
	## legacy is given, grey bones after.
	var trade := {"smithing": "smith", "alchemy": "alchemist", "medicine": "alchemist", "jewelcrafting": "merchant", "herbalism": "villager"}
	var gspec: Dictionary = preload("res://scripts/world/Dress.gd").spec_for(legacy_master(), str(trade.get(craft(), "villager")), {"beard": true})
	_ghost = preload("res://scripts/core/Art.gd").person(gspec)
	_ghost.position = Vector3(0.0, 0.0, 0.55)
	_ghost.rotation.y = PI
	add_child(_ghost)
	preload("res://scripts/world/Dress.gd").dress(_ghost, gspec)
	var ap := _find_anim(_ghost)
	if ap and ap.has_animation("sit"):
		ap.play("sit")
		ap.seek(ap.get_animation("sit").length * 0.99, true)
		ap.pause()
	var claimed := Game.has_flag(_legacy_key)
	if DisplayServer.get_name() != "headless":
		_ghost_tint(_ghost, Color(0.45, 0.45, 0.45) if claimed else Color(0.55, 0.85, 0.75))
	_aura = OmniLight3D.new()
	_aura.light_color = Color(0.45, 1.0, 0.8)
	_aura.omni_range = 4.0
	_aura.light_energy = 0.0 if claimed else 1.3
	_aura.position = Vector3(0, 1.6, 0.55)
	add_child(_aura)


func _ghost_tint(n: Node, c: Color) -> void:
	if n is MeshInstance3D:
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.emission_enabled = true
		m.emission = c * 0.25
		n.material_override = m
	for ch in n.get_children():
		_ghost_tint(ch, c)


func craft() -> String:
	return str(CRAFT_OF.get(kind, ""))


func legacy_master() -> String:
	var row: Dictionary = texts().get("legacies", {}).get(craft(), {})
	var ms: Array = row.get("masters", [])
	return str(ms[absi(_seed) % ms.size()]) if ms.size() > 0 else "a nameless master"


func legacy_grants() -> Dictionary:
	## What a workshop master passes on: their craft's technique (or, if you
	## already have it, a great deal of practice), their best work, some qi.
	var d := maxi(Game.depth, 1)
	var sk := craft()
	var row: Dictionary = texts().get("legacies", {}).get(sk, {})
	var g := {"qi": int(Game.qi_to_next() * 0.5), "items": {}, "techniques": [], "skill_xp": {sk: 120.0 + 30.0 * d}}
	var tech := str(row.get("technique", ""))
	if tech != "" and not Game.has_tech(tech):
		g["techniques"].append(tech)
	match sk:
		"smithing":
			var pool: Array = Game.gear_pool(d, ["weapon"])
			if pool.size() > 0:
				g["items"][Game.with_quality(str(pool[absi(_seed) % pool.size()]), 4)] = 1
		"alchemy":
			g["items"] = {"qi_pill@superior": 2, "breakthrough_pill": 1}
		"medicine":
			g["items"] = {"healing_salve@superior": 3}
		"jewelcrafting":
			g["items"] = {"jade_ring@superior": 1, "rough_jade": 3}
		"herbalism":
			g["items"] = {"spirit_herb": 8, "moonpetal_tonic": 1} if Game.has_item_def("moonpetal_tonic") else {"spirit_herb": 8}
	return g


func _pale(n: Node) -> void:
	if n is MeshInstance3D:
		for i in n.get_surface_override_material_count():
			var mm = n.get_active_material(i)
			if mm is StandardMaterial3D:
				var d: StandardMaterial3D = mm.duplicate()
				d.albedo_color = d.albedo_color.lerp(Color(0.55, 0.53, 0.5), 0.6)
				n.set_surface_override_material(i, d)
	for c in n.get_children():
		_pale(c)


func _find_anim(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var a := _find_anim(c)
		if a:
			return a
	return null


# ---- what it tells you ---------------------------------------------------------------

static func texts() -> Dictionary:
	if _text.is_empty():
		var d = JSON.parse_string(FileAccess.get_file_as_string("res://data/vignettes.json")) if FileAccess.file_exists("res://data/vignettes.json") else null
		_text = d if d is Dictionary else {"kinds": {}, "looks": {}}
	return _text


func title() -> String:
	return str(texts().get("kinds", {}).get(kind, {}).get("title", "Something here"))


func line() -> String:
	## A region's own words two times in three (when it has any), else the
	## kind's general ones -- the same scene always says the same thing.
	var own: Array = texts().get("looks", {}).get(look_key, {}).get(kind, [])
	var gen: Array = texts().get("kinds", {}).get(kind, {}).get("lines", [])
	if not own.is_empty() and (absi(_seed) % 3 != 0 or gen.is_empty()):
		return str(own[absi(_seed) % own.size()])
	if gen.is_empty():
		return "You look closer. Someone was here before you."
	return str(gen[absi(_seed) % gen.size()])


func prompt() -> String:
	return "E: Look closer"


func interact(_player) -> void:
	if legacy and not Game.has_flag(_legacy_key):
		_legacy_dialog()
		return
	var text := line()
	var found := ""
	if not Game.has_flag(_key):
		Game.set_flag(_key)
		found = find_something(randf())
		Game.add_skill_xp("survival", 4.0 + float(Game.depth), "reading the signs")
		Game.log_event("vignette", {"kind": kind, "cell": [cell.x, cell.y]})
		Game.guild_event("secret", 0.5)
	var hud = get_tree().get_first_node_in_group("hud") if is_inside_tree() else null
	if hud:
		hud.open_dialog(title(), text + ("\n\n" + found if found != "" else ""), [["Move on", hud.close_dialog]])


func _legacy_dialog() -> void:
	var hud = get_tree().get_first_node_in_group("hud") if is_inside_tree() else null
	var sk := craft()
	var row: Dictionary = texts().get("legacies", {}).get(sk, {})
	var master := legacy_master()
	if Game.skill_level(sk) < LEGACY_SKILL:
		var t := str(texts().get("legacies", {}).get("turned_away", "The figure doesn't stir for you."))
		t = t.replace("{place}", title().to_lower().trim_prefix("a ").trim_prefix("an ")).replace("{craft}", Game.skill_name(sk)).replace("{need}", str(LEGACY_SKILL))
		Game.log_event("inheritance_locked", {"master": master})
		if hud:
			hud.open_dialog(title(), line() + "\n\n" + t, [["Leave them to their work", hud.close_dialog]])
		return
	var g := legacy_grants()
	if _line_gate(hud, master, g):
		return
	var parts := []
	for id in g.get("items", {}):
		parts.append("%s%s" % [Game.item_name(str(id)), (" x%d" % int(g["items"][id])) if int(g["items"][id]) > 1 else ""])
	for tid in g.get("techniques", []):
		parts.append(str(Game.technique_defs.get(str(tid), {}).get("name", tid)))
	parts.append("a lifetime of %s" % Game.skill_name(sk))
	var body := str(row.get("words", "\"Take it. All of it.\"")) + "\n\n(You will receive: %s.)" % ", ".join(parts)
	if hud:
		hud.open_dialog("The Legacy of " + master.trim_prefix("the ").capitalize(), body, [["Accept the legacy", func():
			hud.close_dialog()
			accept_legacy()], ["Not yet", hud.close_dialog]])


func _line_gate(hud, master: String, g: Dictionary) -> bool:
	## round 120: a craft master past the first floors gives a short task before the legacy
	## (the beginning craft master stays as easy as it was)
	if Game.depth < 3 or not hud:
		return false
	var LL = preload("res://scripts/systems/LegacyLines.gd")
	var st: String = LL.state(_legacy_key)
	if st == "done":
		return false
	var Q = Game.sys("quests")
	if st == "active":
		var q: String = LL.qid_of(_legacy_key)
		hud.open_dialog("The Task of " + master.trim_prefix("the ").capitalize(),
			"The old hands are still. \"You know what I asked.\"\n\nYour task: %s%s\n\n(Step %d of %d. See the Quests page.)" % [str(Q.stage(q).get("log", "")), Q.progress_text(q), int(Q.active[q]["stage"]) + 1, Q.qdef(q).get("stages", []).size()],
			[["Go and do it", hud.close_dialog]])
		return true
	var def: Dictionary = LL.plan(_legacy_key, master, "minor", g, int(Game.depth))
	var n: int = def["stages"].size()
	hud.open_dialog("The Task of " + master.trim_prefix("the ").capitalize(),
		"\"A craft is not a coin to pick up. Show me you can carry it -- %d small things -- and come back.\"" % n,
		[["Take up the task", func():
			hud.close_dialog()
			LL.start(_legacy_key, master, "minor", g, int(Game.depth))], ["Not now", hud.close_dialog]])
	return true


func accept_legacy() -> bool:
	if not legacy or Game.has_flag(_legacy_key) or Game.skill_level(craft()) < LEGACY_SKILL:
		return false
	var g := legacy_grants()
	var master := legacy_master()
	Game.claim_inheritance(_legacy_key, master, g)
	for sk in g.get("skill_xp", {}):
		Game.add_skill_xp(str(sk), float(g["skill_xp"][sk]), master + "'s legacy")
	Game.note_place("Received the legacy of %s, %s" % [master, title().to_lower()])
	Game.set_flag(_key)
	remove_from_group("discoverable")
	if _aura:
		_aura.light_energy = 0.0
	if _ghost and DisplayServer.get_name() != "headless":
		_ghost_tint(_ghost, Color(0.45, 0.45, 0.45))
	return true


func find_something(roll: float) -> String:
	## The first look sometimes turns something up -- never much, always
	## something that fits what you're looking at.
	var d := maxi(Game.depth, 1)
	match kind:
		"camp":
			if roll < 0.5:
				Game.add_item("raw_meat" if roll < 0.25 else "healing_salve", 1, false)
				return "Among the bedding: %s." % ("some dried meat, still good" if roll < 0.25 else "a salve, half-used")
		"fallen":
			if roll < 0.2:
				var g := Game.drop_gear(d, 0, ["weapon"])
				return "You take their weapon. They won't mind. (%s)" % Game.item_name(g) if g != "" else ""
			if roll < 0.7:
				var gold := 4 + d * 3
				Game.add_item("gold", gold, false)
				return "A purse, tucked inside their robe. %d gold." % gold
		"shrine":
			Game.add_qi(Game.qi_to_next() * 0.04, "a quiet moment at the shrine")
			return "You stand there a while. Something settles in you."
		"battle":
			if roll < 0.55:
				var gold2 := 3 + d * 2
				Game.add_item("gold", gold2, false)
				return "Coins scattered in the dust: %d gold." % gold2
		"smithy", "alchemy_lab", "apothecary", "jeweler", "herb_garden":
			# a lost workshop always teaches its craft a little, and leaves
			# something of its trade behind
			var sk := craft()
			Game.add_skill_xp(sk, 12.0 + 3.0 * d, "a lost workshop")
			var finds := {"smithy": ["silver_ore" if d >= 4 else "iron_ore", 3], "alchemy_lab": ["qi_pill", 1], "apothecary": ["healing_salve", 2],
				"jeweler": ["rough_jade" if roll < 0.5 else "gold_nugget", 2], "herb_garden": ["spirit_herb", 4]}
			var f: Array = finds[kind]
			Game.add_item(str(f[0]), int(f[1]), false)
			return "You go through what they left. %d %s -- and you understand a little more about %s." % [int(f[1]), Game.item_name(str(f[0])), Game.skill_name(sk)]
		_:
			if roll < 0.65:
				var pick := "qi_pill" if roll < 0.2 else "healing_salve"
				Game.add_item(pick, 1, false)
				return "Not all of it rotted: a %s, still sealed." % Game.item_name(pick)
	return ""
