extends StaticBody3D
## A dig site of the old age (round 44; the rules are in systems/Ruins.gd).
## The same jade-and-glyph stonework everywhere it appears -- so wherever you
## see it, you know what it is. A mound of earth in the middle that sinks a
## layer at a time as you dig (E); at the bottom, the old floor, and whatever
## was left on it. Once you know the age, its glyphs read out in plain words.

var level
var cell := Vector2i.ZERO
var _mound: Node3D
var _slab: MeshInstance3D
var _glow: OmniLight3D
var _words: Label3D
var _stones := []
var radius := 2

const JADE := Color(0.55, 0.78, 0.7)
const GLYPH := Color(0.45, 0.95, 0.9)
const RING := [[Vector2i(-2, -1), "nature-kit/statue_column.glb", 1.8], [Vector2i(2, -1), "nature-kit/statue_columnDamaged.glb", 1.8],
	[Vector2i(0, -2), "nature-kit/statue_obelisk.glb", 1.7], [Vector2i(-1, 2), "nature-kit/stone_tallB.glb", 1.5], [Vector2i(2, 1), "nature-kit/statue_ring.glb", 1.4]]


func setup(lvl, args: Dictionary) -> void:
	level = lvl
	cell = args.get("cell", Vector2i.ZERO)
	radius = int(args.get("radius", 2))


func _R():
	return Game.sys("ruins")


func _floor_n() -> int:
	return int(level.def.get("depth", 0)) if level else 0


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("dig_site")
	for p in RING:
		var c: Vector2i = cell + p[0]
		var o: Vector2i = p[0]
		if maxi(absi(o.x), absi(o.y)) > radius:
			o = Vector2i(signi(o.x), signi(o.y))       # a smaller hall: the stones stand closer in
			c = cell + o
		if o == Vector2i.ZERO or not level.is_free(c):
			continue
		var m: Node3D = level._model(str(p[1]))
		m.position = level.cell_to_world(c) - global_position
		m.scale = Vector3.ONE * float(p[2])
		m.rotation.y = float(hash(str(c))) * 0.001
		add_child(m)
		_jade(m)
		_glyph_strip(m.position)
		level._solid(c)
		_stones.append(c)
	# the mound: turned earth, with a spade stuck in it
	_mound = Node3D.new()
	var earth := MeshInstance3D.new()
	var em := SphereMesh.new()
	em.radius = 0.95
	em.height = 1.1
	earth.mesh = em
	var emat := StandardMaterial3D.new()
	emat.albedo_color = Color(0.32, 0.24, 0.17)
	emat.roughness = 1.0
	earth.material_override = emat
	earth.position = Vector3(0, 0.0, 0)
	_mound.add_child(earth)
	var spade := MeshInstance3D.new()
	var spm := BoxMesh.new()
	spm.size = Vector3(0.05, 1.1, 0.05)
	spade.mesh = spm
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.45, 0.32, 0.2)
	spade.material_override = wm
	spade.position = Vector3(0.35, 0.75, 0.1)
	spade.rotation_degrees = Vector3(0, 0, -18)
	_mound.add_child(spade)
	var stones: Node3D = level._model("mini-dungeon/stones.glb")
	stones.position = Vector3(-0.9, 0, 0.6)
	stones.scale = Vector3.ONE * 1.2
	_mound.add_child(stones)
	add_child(_mound)
	_slab = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.6, 0.12, 1.6)
	_slab.mesh = bm
	var sm := StandardMaterial3D.new()
	sm.albedo_color = JADE.darkened(0.2)
	sm.emission_enabled = true
	sm.emission = GLYPH
	sm.emission_energy_multiplier = 0.6
	_slab.material_override = sm
	_slab.position = Vector3(0, 0.02, 0)
	add_child(_slab)
	_glow = OmniLight3D.new()
	_glow.light_color = GLYPH
	_glow.omni_range = 6.0
	_glow.position = Vector3(0, 1.2, 0)
	add_child(_glow)
	_words = Label3D.new()
	_words.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_words.pixel_size = 0.007
	_words.font_size = 28
	_words.outline_size = 8
	_words.modulate = Color(0.7, 1.0, 0.95)
	_words.position = Vector3(0, 3.4, 0) + (level.cell_to_world(cell + Vector2i(0, -2)) - global_position)
	add_child(_words)
	var shape := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = Vector3(1.6, 1.0, 1.6)
	shape.shape = b
	shape.position = Vector3(0, 0.5, 0)
	add_child(shape)
	level._solid(cell)
	_refresh()


var _jade_mat: StandardMaterial3D


func _jade(n: Node) -> void:
	## the old age's stone: a jade wash over whatever the stone is made of (any art style)
	if _jade_mat == null:
		_jade_mat = StandardMaterial3D.new()
		_jade_mat.albedo_color = Color(JADE.r, JADE.g, JADE.b, 0.45)
		_jade_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_jade_mat.emission_enabled = true
		_jade_mat.emission = JADE * 0.25
	if n is MeshInstance3D:
		(n as MeshInstance3D).material_overlay = _jade_mat
	for ch in n.get_children():
		_jade(ch)


func _glyph_strip(at: Vector3) -> void:
	## the old age's mark: a thin line of light up the stone
	var g := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.06, 1.6, 0.06)
	g.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = GLYPH
	m.emission_enabled = true
	m.emission = GLYPH
	m.emission_energy_multiplier = 2.2
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	g.material_override = m
	g.position = at + Vector3(0.0, 1.1, 0.42)
	add_child(g)


func _refresh() -> void:
	var R = _R()
	if R == null:
		return
	var n: int = R.layers_dug(str(level.level_id))
	var total: int = R.layers()
	_mound.visible = n < total
	_mound.scale = Vector3(1.0, 1.0 - 0.3 * n, 1.0)       # it sinks a layer at a time
	_slab.visible = n >= total
	_glow.light_energy = 0.4 if n < total else 1.4
	_words.text = R.inscription_for(str(level.level_id), _floor_n())
	_words.visible = _words.text != ""


func prompt() -> String:
	var R = _R()
	if R and R.site_done(str(level.level_id)):
		return I18n.t("E: Look at the old floor")
	return I18n.t("E: Dig (layer %d of %d)") % [(R.layers_dug(str(level.level_id)) + 1) if R else 1, R.layers() if R else 3]


func interact(player) -> void:
	var R = _R()
	var hud = get_tree().get_first_node_in_group("hud")
	if R == null or hud == null:
		return
	if R.site_done(str(level.level_id)):
		var t: String = R.inscription_for(str(level.level_id), _floor_n())
		hud.open_dialog("The Old Floor", ("The glyphs say: \"%s\"\n\n" % t if t != "" else "Glyphs you can't read yet run round the stones. Find every relic of their age and they'll make sense.\n\n") + R.pointer(_floor_n()), [["Leave", hud.close_dialog]])
		return
	var r: Dictionary = R.dig(str(level.level_id), _floor_n())
	Game.sfx("dig" if ResourceLoader.exists("res://assets/sfx/dig.ogg") else "thud", 0.6)
	preload("res://scripts/fx/FX.gd").puff(global_position + Vector3(0, 0.6, 0), Color(0.45, 0.38, 0.3), 1.2)
	Game.message.emit(str(r.get("text", "")))
	if bool(r.get("guardian", false)):
		_wake_guardian(player)
	_refresh()


func _wake_guardian(_player) -> void:
	## you dug too loudly: something that lives in the old stone comes up
	var pool := []
	for e in Game.enemies:
		var ed: Dictionary = Game.enemies[e]
		if bool(ed.get("boss", false)) or bool(ed.get("passive", false)):
			continue
		if int(ed.get("floor", 0)) <= _floor_n() and int(ed.get("floor", 0)) >= _floor_n() - 4:
			pool.append(str(e))
	pool.sort()
	if pool.is_empty():
		return
	for d in [Vector2i(0, 2), Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, -3), Vector2i(3, 2)]:
		var c: Vector2i = cell + d
		if level.is_free(c):
			level._spawn_script("res://scripts/actors/Enemy.gd", level.cell_to_world(c), {"type": pool[absi(hash(str(c) + level.level_id)) % pool.size()], "cell": c})
			Game.log_event("dig_guardian", {"level": level.level_id})
			return
