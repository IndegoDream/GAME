extends Node3D
## A wonder: the reason to go into one of Expanse.gd's side chambers.
## (Robert, 2026-10-02: "more things to do and explore and find".)
##
##   relic      teal crystals of the old machines, still humming. E: draw
##              the swarm out of it -- integration and nanite shards. Once.
##   hermitage  a mat, candles, a thread of incense. E: sit here -- your
##              meditation runs half again as deep while you stay.
##   echo       a standing stone with a ring of light turning over it. E:
##              watch the old fight it remembers -- a glimpse of an art
##              you haven't found (Game.glimpse rows). Once.
##   cache      a heap of loose stones. Spirit Sense (or Sensor Bloom)
##              makes it glow. E: dig -- gold, the floor's materials, and
##              sometimes incense or a nanite bridge. Once.
##   grotto     a still pool: the pool itself is the fishing spot (&) the
##              chamber was carved with; this marks it, glowing faintly.
##   lair       whatever lives in it is the floor's own foe (placed by the
##              map); this is what it guarded -- a cache once they're dead.
##   trial      an altar. E: begin a trial -- foes of this floor rise
##              around it; beat them all in 90 seconds and the altar pays
##              (gold, qi, swarm, a glimpse). Once a day.

var level
var cell := Vector2i.ZERO
var kind := "relic"
var key := ""
var _light: OmniLight3D
var _ring: MeshInstance3D
var _mats := []
var _trial_foes := []
var _trial_t := 0.0
var _headless := false

const TRIAL_SECONDS := 90.0


func setup(lvl, args: Dictionary) -> void:
	level = lvl
	cell = args.get("cell", Vector2i.ZERO)
	kind = str(args.get("kind", "relic"))
	key = "wonder:%s:%s:%d" % [lvl.level_id if lvl else "?", kind, int(args.get("i", 0))]


func _ready() -> void:
	_headless = DisplayServer.get_name() == "headless"
	add_to_group("interactable")
	add_to_group("wonder")
	if kind in ["cache", "lair"]:
		add_to_group("discoverable")        # Spirit Sense / Sensor Bloom light it up
	match kind:
		"relic":
			_build_relic()
		"hermitage":
			_build_hermitage()
		"echo":
			_build_echo()
		"cache", "lair":
			_build_cache()
		"grotto":
			_build_glow(Color(0.45, 0.85, 1.0), 0.8)
		"trial":
			_build_altar()
	if used():
		_dim()


func used() -> bool:
	if kind == "trial":
		return str(Game.flags.get(key, "")) == Game.today()
	return Game.has_flag(key)


func _done() -> void:
	if kind == "trial":
		Game.flags[key] = Game.today()
	else:
		Game.set_flag(key)
	Game.bump("wonders")
	Game.log_event("wonder", {"kind": kind, "level": level.level_id if level else ""})
	_dim()


# ---- what E says, what E does ----------------------------------------------------

func prompt() -> String:
	match kind:
		"relic":
			return I18n.t("A nanite relic -- spent, cold") if used() else I18n.t("E: Draw the swarm out of the old relic")
		"hermitage":
			return I18n.t("E: Sit in the quiet alcove (meditation runs deeper here)")
		"echo":
			return I18n.t("An echo stone -- quiet now") if used() else I18n.t("E: Watch the echo the stone remembers")
		"cache", "lair":
			return I18n.t("Dug-out stones") if used() else I18n.t("E: Loose stones -- dig")
		"grotto":
			return I18n.t("A still pool, glowing faintly")
		"trial":
			if _trial_foes.size() > 0:
				return I18n.t("The trial is under way -- %d left, %ds") % [_foes_left(), int(ceil(_trial_t))]
			return I18n.t("The altar is quiet until tomorrow") if used() else I18n.t("E: Begin the trial at the altar")
	return ""


func interact(player) -> void:
	match kind:
		"relic":
			if used():
				return
			var d := maxi(Game.depth, 1)
			Game.integrate(20.0 + 6.0 * d, "relic")
			var n := 1 + d / 8
			Game.add_item("nanite_shard", n, false)
			Game.message.emit(I18n.t("You lay your palm on the relic and the swarm drinks from it -- the old machine goes cold. (+%d nanite shard%s; your swarm grows)") % [n, "" if n == 1 else "s"])
			_done()
		"hermitage":
			if player and player.has_method("start_meditating"):
				player.start_meditating(false)
				Game.sit_aid = 1.5
				if not Game.has_flag(key):
					Game.set_flag(key)
					Game.note_place("A quiet alcove on %s" % (level.display_name() if level else "a floor"))
				Game.message.emit("The candles steady. Here, your breath goes deeper (meditation x1.5 while you sit).")
		"echo":
			if used():
				return
			var rows: Array = Game.glimpse_rows()
			var picks := rows.filter(func(r): return str(r[3]) == "")
			if picks.is_empty():
				picks = rows
			if picks.is_empty():
				Game.message.emit("The echo shows an old fight -- nothing you don't already know. Still, it's good to watch a master.")
				Game.integrate(15.0, "echo")
			else:
				var r: Array = picks[absi(hash(key)) % picks.size()]
				var aid := _art_id_named(str(r[0]))
				Game.glimpse_art(aid, 3.0)
				Game.message.emit(I18n.t("The stone remembers a fight: two figures of light, one moving the way %s moves. You watch until it fades. (%s glimpsed)") % [r[0], r[0]])
			_done()
		"cache", "lair":
			if used():
				return
			if kind == "lair" and _lair_guarded():
				Game.message.emit("Not with them still here.")
				return
			var d := maxi(Game.depth, 1)
			Game.add_item("gold", 10 * d + randi() % (5 * d + 1))
			for row in _floor_materials():
				Game.add_item(str(row), 1 + randi() % 2)
			var roll := randf()
			if roll < 0.06:
				Game.add_item("nanite_bridge", 1)
			elif roll < 0.3:
				Game.add_item("calming_incense", 1)
			elif roll < 0.5:
				Game.add_item("nanite_shard", 1)
			Game.message.emit("Under the loose stones: someone's hidden things, long forgotten.")
			_done()
		"trial":
			if used() or _trial_foes.size() > 0:
				return
			_begin_trial()


func _art_id_named(nm: String) -> String:
	for aid in Game.lattice_data().get("arts", {}):
		if str(Game.technique_defs.get(aid, {}).get("name", aid)) == nm:
			return str(aid)
	return ""


func _floor_materials() -> Array:
	## what this floor's foes carry (the region's materials)
	var out := []
	if level == null:
		return ["iron_ore"]
	for ch in level.def.get("enemies", {}):
		var e: Dictionary = Game.enemies.get(str(level.def["enemies"][ch]), {})
		for id in e.get("loot", {}):
			if id != "gold" and Game.items.get(id, {}).get("type") == "material" and not id in out:
				out.append(id)
	return out.slice(0, 2) if out.size() > 0 else ["iron_ore"]


func _lair_guarded() -> bool:
	for e in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(e) and not e._dead and not bool(e.stats.get("passive", false)) \
				and (e.global_position - global_position).length() < 9.0:
			return true
	return false


# ---- the trial -------------------------------------------------------------------

func _begin_trial() -> void:
	var weak := ""
	var en: Dictionary = level.def.get("enemies", {}) if level else {}
	for ch in en:
		var e: Dictionary = Game.enemies.get(str(en[ch]), {})
		if not e.is_empty() and not bool(e.get("boss", false)) and not bool(e.get("passive", false)):
			weak = str(en[ch])
			break
	if weak == "":
		Game.message.emit("The altar stays silent.")
		return
	var n := 3 + Game.depth / 6
	_trial_foes = []
	for i in n:
		var a := TAU * float(i) / n
		var at := global_position + Vector3(cos(a), 0, sin(a)) * 3.2
		var foe = level._spawn_script("res://scripts/actors/Enemy.gd", at, {"type": weak, "cell": cell})
		if foe:
			foe.set_meta("trial", true)
			_trial_foes.append(foe)
	_trial_t = TRIAL_SECONDS
	Game.message.emit("TRIAL: the altar wakes, and %d shapes rise around it. Ninety seconds." % n)
	Game.log_event("trial_start", {"level": level.level_id})


func _foes_left() -> int:
	var k := 0
	for f in _trial_foes:
		if is_instance_valid(f) and not f._dead:
			k += 1
	return k


func _process(delta: float) -> void:
	if _ring:
		_ring.rotate_y(delta * 0.6)
	if _trial_foes.is_empty():
		return
	_trial_t -= delta
	if _foes_left() == 0:
		_trial_foes = []
		_trial_won()
	elif _trial_t <= 0.0:
		for f in _trial_foes:
			if is_instance_valid(f) and not f._dead:
				f.queue_free()
		_trial_foes = []
		Game.message.emit("TRIAL: too slow -- the shapes sink back into the stone. The altar will wait for you.")


func _trial_won() -> void:
	var d := maxi(Game.depth, 1)
	Game.add_item("gold", 25 * d)
	Game.add_qi(15.0 * d, "the trial")
	Game.integrate(10.0 + 3.0 * d, "trial")
	var rows: Array = Game.glimpse_rows().filter(func(r): return str(r[3]) == "")
	if not rows.is_empty():
		Game.glimpse_art(_art_id_named(str(rows[0][0])), 2.0)
	Game.message.emit("TRIAL WON: the altar pays in gold and qi, and something you saw stays with you.")
	_done()


# ---- how they look ------------------------------------------------------------------

func _emissive(c: Color, e: float, alpha: float = 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(c.r, c.g, c.b, alpha)
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = e
	m.roughness = 0.25
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mats.append(m)
	return m


func _mesh(mesh: Mesh, pos: Vector3, mat: Material, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.rotation = rot
	if mat and not _headless:
		mi.material_override = mat
	add_child(mi)
	return mi


func _build_glow(c: Color, energy: float) -> void:
	if _headless:
		return
	_light = OmniLight3D.new()
	_light.light_color = c
	_light.light_energy = energy
	_light.omni_range = 5.0
	_light.position = Vector3(0, 1.2, 0)
	add_child(_light)


func _build_relic() -> void:
	## a cluster of teal crystal prisms around a dark core
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	var mat := _emissive(Color(0.2, 0.8, 0.72), 0.9, 0.85)
	for i in 7:
		var cm := CylinderMesh.new()
		cm.radial_segments = 6
		cm.top_radius = 0.02
		cm.bottom_radius = rng.randf_range(0.12, 0.22)
		cm.height = rng.randf_range(0.7, 1.6)
		var a := TAU * i / 7.0
		var r := 0.0 if i == 0 else rng.randf_range(0.25, 0.5)
		_mesh(cm, Vector3(cos(a) * r, cm.height * 0.4, sin(a) * r), mat, Vector3(rng.randf_range(-0.35, 0.35), 0, rng.randf_range(-0.35, 0.35)))
	var core := SphereMesh.new()
	core.radius = 0.28
	core.height = 0.5
	var cmat := StandardMaterial3D.new()
	cmat.albedo_color = Color(0.12, 0.13, 0.15)
	cmat.metallic = 0.8
	cmat.roughness = 0.35
	_mesh(core, Vector3(0, 0.2, 0), cmat)
	_build_glow(Color(0.3, 0.95, 0.85), 1.6)


func _build_hermitage() -> void:
	## a round mat, three candles, a thread of incense smoke
	var mat := CylinderMesh.new()
	mat.top_radius = 0.75
	mat.bottom_radius = 0.75
	mat.height = 0.05
	var mm := StandardMaterial3D.new()
	mm.albedo_color = Color(0.55, 0.42, 0.25)
	mm.roughness = 1.0
	_mesh(mat, Vector3(0, 0.03, 0), mm)
	for i in 3:
		var a := PI * 0.75 + i * 0.6
		var cm := CylinderMesh.new()
		cm.top_radius = 0.05
		cm.bottom_radius = 0.05
		cm.height = 0.22 + 0.06 * i
		var wax := StandardMaterial3D.new()
		wax.albedo_color = Color(0.92, 0.88, 0.78)
		var at := Vector3(cos(a) * 1.05, cm.height / 2.0, sin(a) * 1.05)
		_mesh(cm, at, wax)
		var fl := SphereMesh.new()
		fl.radius = 0.035
		fl.height = 0.09
		_mesh(fl, at + Vector3(0, cm.height / 2.0 + 0.05, 0), _emissive(Color(1.0, 0.75, 0.35), 4.0))
	if not _headless:
		var smoke := CPUParticles3D.new()
		smoke.amount = 24
		smoke.lifetime = 4.0
		smoke.position = Vector3(0.9, 0.35, -0.6)
		smoke.direction = Vector3(0, 1, 0)
		smoke.spread = 8.0
		smoke.initial_velocity_min = 0.15
		smoke.initial_velocity_max = 0.3
		smoke.gravity = Vector3(0.03, 0.02, 0)
		smoke.scale_amount_min = 0.6
		smoke.scale_amount_max = 1.4
		var sm := SphereMesh.new()
		sm.radius = 0.05
		sm.height = 0.1
		smoke.mesh = sm
		var smm := StandardMaterial3D.new()
		smm.albedo_color = Color(0.85, 0.85, 0.9, 0.25)
		smm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		smm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		smoke.material_override = smm
		add_child(smoke)
	_build_glow(Color(1.0, 0.75, 0.4), 1.1)


func _build_echo() -> void:
	## a tall stone, and a ring of pale light turning above it
	var st := BoxMesh.new()
	st.size = Vector3(0.7, 2.2, 0.35)
	var sm: Material = null
	if not _headless:
		sm = preload("res://scripts/world/Look.gd").surface(["mossy_stone_wall", [0.85, 0.85, 0.82], 1.2])
	_mesh(st, Vector3(0, 1.1, 0), sm, Vector3(0, 0.3, 0.04))
	var t := TorusMesh.new()
	t.inner_radius = 0.62
	t.outer_radius = 0.68
	_ring = _mesh(t, Vector3(0, 1.45, 0), _emissive(Color(0.65, 0.78, 1.0), 1.2, 0.8), Vector3(0.22, 0, 0.15))      # a ring of pale light circling the stone
	_build_glow(Color(0.7, 0.8, 1.0), 1.0)


func _build_cache() -> void:
	var m: Node3D = preload("res://scripts/core/Art.gd").make("mini-dungeon/rocks.glb", absi(hash(key)))
	m.scale = Vector3.ONE * 1.6
	add_child(m)


func _build_altar() -> void:
	var b := BoxMesh.new()
	b.size = Vector3(1.6, 0.7, 1.0)
	var sm: Material = null
	if not _headless:
		sm = preload("res://scripts/world/Look.gd").surface(["castle_brick_01", [0.8, 0.78, 0.75], 1.0])
	_mesh(b, Vector3(0, 0.35, 0), sm)
	var rune := BoxMesh.new()
	rune.size = Vector3(1.2, 0.02, 0.6)
	_mesh(rune, Vector3(0, 0.71, 0), _emissive(Color(1.0, 0.35, 0.25), 2.0))
	_build_glow(Color(1.0, 0.45, 0.3), 1.2)


func _dim() -> void:
	## a spent wonder: its glow nearly gone
	for m in _mats:
		(m as StandardMaterial3D).emission_energy_multiplier *= 0.15
	if _light and kind not in ["hermitage", "grotto"]:
		_light.light_energy *= 0.2
