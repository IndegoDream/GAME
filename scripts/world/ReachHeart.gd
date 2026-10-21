extends Node3D
## The heart of a reach (round 56): at the far end of the land, where
## everything the reach gathered has collected -- a ring of the land's own
## stone round a glowing hoard. Its WARDEN stands guard: the toughest thing
## that lives on this floor, grown into the reach's own named terror (a boss
## bar while you're near). While it lives the heart won't give; when it
## falls, E takes the store: gold by depth, the land's materials, qi, and the
## first time a land's heart is taken in this game, that land's keepsake.
## Once a game per reach (scripts/systems/Reaches.gd remembers).

var level
var cell := Vector2i.ZERO
var bk := ""
var biome := {}
var i := 0
var warden = null
var _glow: OmniLight3D
var _core: MeshInstance3D
var _t := 0.0


func setup(lvl, args: Dictionary) -> void:
	level = lvl
	cell = args.get("cell", Vector2i.ZERO)
	bk = str(args.get("biome", ""))
	i = int(args.get("i", 0))
	biome = preload("res://scripts/world/Reach.gd").biome(bk)


func _ready() -> void:
	add_to_group("reach_heart")
	add_to_group("fog_exempt")
	var R = Game.sys("reaches")
	var taken: bool = R != null and R.is_claimed(str(level.level_id), i)
	if not taken:
		add_to_group("interactable")
		_spawn_warden.call_deferred()      # (the level is still setting up its children)
	if DisplayServer.get_name() == "headless":
		return
	var c: Color = preload("res://scripts/world/ReachDress.gd").tint(biome)
	var Look := preload("res://scripts/world/Look.gd")
	var stone: Material = Look.surface(Look.LOOKS.get(str(biome.get("look", "")), {}).get("wall", ["rock_face", [0.6, 0.6, 0.62], 3.0]))
	# a ring of standing stones
	for k in 7:
		var a := TAU * k / 7.0
		var st := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.16
		cm.bottom_radius = 0.26
		cm.height = 1.3 + 0.5 * float(k % 3)
		cm.radial_segments = 6
		st.mesh = cm
		st.material_override = stone
		st.position = Vector3(cos(a) * 1.9, cm.height / 2.0, sin(a) * 1.9)
		st.rotation = Vector3(0.08 * sin(a * 3.0), a, 0.06)
		add_child(st)
	# the hoard: a glowing core over a low cairn
	var cairn := MeshInstance3D.new()
	var cy := CylinderMesh.new()
	cy.top_radius = 0.55
	cy.bottom_radius = 0.9
	cy.height = 0.5
	cy.radial_segments = 8
	cairn.mesh = cy
	cairn.material_override = stone
	cairn.position = Vector3(0, 0.25, 0)
	add_child(cairn)
	_core = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.32
	sm.height = 0.64
	_core.mesh = sm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = c * 0.6
	gm.emission_enabled = true
	gm.emission = c
	gm.emission_energy_multiplier = 0.6 if taken else 3.0
	_core.material_override = gm
	_core.position = Vector3(0, 1.0, 0)
	add_child(_core)
	_glow = OmniLight3D.new()
	_glow.light_color = c
	_glow.light_energy = 0.4 if taken else 1.8
	_glow.omni_range = 9.0
	_glow.position = Vector3(0, 1.4, 0)
	add_child(_glow)


func _spawn_warden() -> void:
	## the floor's toughest ordinary foe, made into the reach's warden
	var depth := int(level.def.get("depth", Game.depth))
	var best := ""
	var hp_best := -1
	for eid in Game.enemies:
		var st: Dictionary = Game.enemies[eid]
		if bool(st.get("passive", false)) or bool(st.get("boss", false)) or int(st.get("floor", -1)) != depth:
			continue
		if int(st.get("hp", 0)) > hp_best:
			hp_best = int(st.get("hp", 0))
			best = str(eid)
	if best == "":
		for k in level.def.get("enemies", {}):
			var t := str(level.def["enemies"][k])
			if Game.enemies.has(t) and not bool(Game.enemies[t].get("boss", false)) and not bool(Game.enemies[t].get("passive", false)):
				best = t
				break
	if best == "":
		return
	var at: Vector2i = cell
	for dir in [Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(0, -2), Vector2i(1, 1)]:
		if level.char_at(cell + dir) == ".":
			at = cell + dir
			break
	var e = load("res://scripts/actors/Enemy.gd").new()
	e.setup(level, {"type": best, "cell": at})
	e.stats = (e.stats as Dictionary).duplicate()
	e.stats["name"] = _cap(str(biome.get("warden", "the Warden")))
	var D: Dictionary = preload("res://scripts/world/Reach.gd").data()
	e.stats["hp"] = int(float(e.stats.get("hp", 30)) * float(D.get("warden_hp_mult", 2.6)))
	e.hp = int(e.stats["hp"])
	e.stats["boss"] = true            # (its name across the top of the screen while you're near)
	e.stats["scale"] = float(e.stats.get("scale", 1.0)) * 1.25
	e.set_meta("reach_warden", bk)
	level.add_child(e)
	e.global_position = level.cell_to_world(at)
	warden = e
	level._count("reach_wardens")


func warden_alive() -> bool:
	return warden != null and is_instance_valid(warden) and not bool(warden.get("_dead"))


func prompt() -> String:
	if warden_alive():
		return I18n.t("%s guards this") % _cap(str(biome.get("warden", I18n.t("the warden"))))
	return I18n.t("E: Take what %s gathered") % str(biome.get("name", I18n.t("the reach")))


func interact(_player) -> void:
	if warden_alive():
		Game.message.emit(I18n.t("%s still stands over the heart of %s.") % [_cap(str(biome.get("warden", I18n.t("the warden")))), str(biome.get("name", I18n.t("the reach")))])
		return
	var R = Game.sys("reaches")
	if R == null:
		return
	var got: Dictionary = R.claim(str(level.level_id), i, bk, int(level.def.get("depth", Game.depth)))
	if got.is_empty():
		return
	remove_from_group("interactable")
	Game.sfx("pickup", 0.9)
	var parts := []
	for k in got:
		if k == "gold":
			parts.append(I18n.t("%d gold") % int(got[k]))
		elif k == "qi":
			parts.append("%d qi" % int(got[k]))
		else:
			parts.append("%d x %s" % [int(got[k]), Game.item_name(str(k))])
	Game.message.emit(I18n.t("THE HEART OF %s: %s.") % [str(biome.get("name", I18n.t("THE REACH"))).to_upper(), ", ".join(parts)])
	if _glow:
		_glow.light_energy = 0.4
	if _core:
		(_core.material_override as StandardMaterial3D).emission_energy_multiplier = 0.6


func _process(delta: float) -> void:
	if _core == null:
		return
	_t += delta
	_core.position.y = 1.0 + sin(_t * 1.7) * 0.08
	_core.rotation.y += delta * 0.6


static func _cap(s: String) -> String:
	return s.left(1).to_upper() + s.substr(1)
