extends Node3D
## What the world looks like right now (round 44) -- the visual half of
## systems/World.gd. One of these sits in every level and keeps it in step
## with the clock and the sky while you play:
##   * under the sky: the sun climbs and sets, dusk goes gold, night goes blue
##     and the moon comes up; clouds thicken with the weather; a storm
##     flashes; rain, snow, mist or leaves fall around you; Frost lays snow on
##     the ground, Thaw scatters flowers, Harvest turns the trees
##   * in the deep: the light dims with the night, and the air carries what
##     the deep is doing (qi mist, spores, ash, a cold seep, dripping dark)
##   * on a festival day, Eliet is strung with coloured lanterns
## Nothing here touches play -- that's World.gd. Recomputed every few seconds.

const Look := preload("res://scripts/world/Look.gd")

var level
var _motes: Node3D
var _fx_kind := ""
var _t := 0.0
var _flash_t := 0.0
var _flash: OmniLight3D
var _amb0 := 1.0
var _fog0 := 0.01
var _amb_col0 := Color(1, 1, 1)
var _fog_col0 := Color(1, 1, 1)
var _fog_on0 := false
var _snow: MeshInstance3D
var _rng := RandomNumberGenerator.new()
var state := {}           # what's showing now (for tests and the World page)
var _dressed := {}        # what the season and the festival put down (kept in state)


func setup(lvl) -> void:
	level = lvl


func _W():
	return Game.sys("world")


func _ready() -> void:
	name = "WorldFX"
	add_to_group("fog_exempt")          # (FogOfWar: not a thing standing on a cell)
	_rng.seed = hash(str(level.level_id) + "fx")
	if level._env:
		_amb0 = level._amb_base
		_fog0 = level._fog_base
		_amb_col0 = level._env.ambient_light_color
		_fog_col0 = level._env.fog_light_color
		_fog_on0 = level._env.fog_enabled
	var W = _W()
	if W:
		_dress_season(W)
		if str(level.level_id) == "village" and not W.festival().is_empty() and not W.calm:
			_festival_lanterns(W.festival())
	apply()


func _process(delta: float) -> void:
	_t += delta
	if _t >= 4.0:
		_t = 0.0
		apply()
	if _flash and _flash_t > 0.0:
		_flash_t -= delta
		_flash.light_energy = maxf(0.0, _flash_t) * 12.0
	elif _flash and bool(state.get("flash", false)) and _rng.randf() < delta * 0.08:
		_flash_t = 0.25            # lightning
		_flash.position = Vector3(_rng.randf_range(-20, 20), 30, _rng.randf_range(-20, 20)) + _player_pos()


func _player_pos() -> Vector3:
	var p = get_tree().get_first_node_in_group("player") if is_inside_tree() else null
	return p.global_position if p else Vector3.ZERO


func apply() -> void:
	## bring the light, the air and the sky in step with the hour and the weather
	var W = _W()
	if W == null or level == null or level._env == null:
		return
	var env: Environment = level._env
	var reg: String = W.region(str(level.level_id), level.def)
	var w: Dictionary = W.weather(reg)
	var tint := Color(1, 1, 1)
	var tc: Array = w.get("tint", [])
	if tc.size() >= 3:
		tint = Color(float(tc[0]), float(tc[1]), float(tc[2]))
	var st: Array = W.season().get("look", {}).get("tint", [1, 1, 1])
	var season_tint := Color(float(st[0]), float(st[1]), float(st[2])) if st.size() >= 3 else Color(1, 1, 1)
	var fogm := float(w.get("fog", 1.0))
	state = {"region": reg, "weather": str(w.get("id", "")), "phase": W.phase(), "season": W.season_id(), "fx": str(w.get("fx", "")), "flash": bool(w.get("flash", false))}
	state.merge(_dressed)
	if level.is_outdoor() and not (level.def.get("atmos", {}) as Dictionary).is_empty():
		level.apply_atmos()          # round 123: a tech place's own air -- no day, no weather
		_set_fx("")
		return
	if level.is_outdoor():
		var dl: float = Game.daylight()
		var dusk := clampf(1.0 - absf(dl - 0.5) * 2.0, 0.0, 1.0) if dl < 1.0 and dl > 0.0 else 0.0
		var dim := float(w.get("dim", 1.0))
		if level.sun_light:
			var sun: DirectionalLight3D = level.sun_light
			sun.rotation_degrees = Vector3(-52, -35, 0) if dl >= 1.0 else Vector3(-18 - 30 * dl, -35, 0)
			sun.light_energy = (0.18 + 1.07 * dl) * dim
			sun.light_color = Color(0.6, 0.7, 1.0).lerp(Color(1.0, 0.97, 0.92), dl).lerp(Color(1.0, 0.7, 0.45), dusk * 0.6) * season_tint
			if bool(w.get("warm", false)):
				sun.light_color = sun.light_color.lerp(Color(1.0, 0.85, 0.6), 0.25)
		if level._sky_mat:
			level._sky_mat.set_shader_parameter("daylight", dl * dim)
			level._sky_mat.set_shader_parameter("dusk", dusk)
			level._sky_mat.set_shader_parameter("cloud_cover", float(w.get("cloud", 0.4)))
			if level.sun_light:
				level._sky_mat.set_shader_parameter("sun_dir", level.sun_light.transform.basis.z.normalized())
		env.ambient_light_color = Color(0.4, 0.45, 0.65).lerp(Color(0.62, 0.6, 0.58), dl) * season_tint
		env.ambient_light_energy = (0.3 + 0.25 * dl) * lerpf(1.0, dim, 0.6)
		if fogm > 1.05:
			env.fog_enabled = true
			env.fog_light_color = Color(0.55, 0.6, 0.7).lerp(Color(0.85, 0.87, 0.9), dl)
			env.fog_density = maxf(_fog0, 0.004 * fogm)
		else:
			# round 48: even on a clear day the far hills sit in a little air
			# (data/horizon.json "haze") -- that's what makes distance read as distance
			var hz: Dictionary = preload("res://scripts/world/Horizon.gd").config().get("haze", {})
			var haze := float(hz.get("clear", 0.0))
			env.fog_enabled = _fog_on0 or haze > 0.0
			var hday := Look.color3(hz.get("day", []), Color(0.74, 0.8, 0.88))
			var hnight := Look.color3(hz.get("night", []), Color(0.08, 0.1, 0.18))
			var hdusk := Look.color3(hz.get("dusk", []), Color(0.95, 0.68, 0.45))
			env.fog_light_color = _fog_col0 if _fog_on0 else hnight.lerp(hday, dl).lerp(hdusk, dusk * 0.5)
			env.fog_density = maxf(_fog0 if _fog_on0 else 0.0, haze)
			env.fog_sky_affect = 0.0
		state["daylight"] = dl
	else:
		var dd: float = W.deep_dim() if not W.calm else 1.0
		level._amb_base = _amb0 * dd
		level._fog_base = _fog0 * fogm
		env.ambient_light_energy = level._amb_base
		env.fog_density = level._fog_base
		env.ambient_light_color = _amb_col0.lerp(_amb_col0 * tint, 0.35)
		env.fog_light_color = _fog_col0.lerp(tint * 0.5, 0.3 if tc.size() >= 3 else 0.0)
		state["dim"] = dd
	_set_fx(str(w.get("fx", "")))
	if bool(w.get("flash", false)) and _flash == null and level.is_outdoor():
		_flash = OmniLight3D.new()
		_flash.light_color = Color(0.8, 0.85, 1.0)
		_flash.omni_range = 80.0
		_flash.light_energy = 0.0
		add_child(_flash)


func _set_fx(kind: String) -> void:
	if kind == _fx_kind:
		return
	_fx_kind = kind
	if _motes:
		_motes.queue_free()
		_motes = null
	if kind == "":
		return
	var m = preload("res://scripts/fx/Motes.gd").new()
	m.kind = kind
	m.tint = Color(0.6, 0.9, 1.0)
	_motes = m
	add_child(m)


# ---- the season's dressing ----------------------------------------------------------------

func _dress_season(W) -> void:
	var look: Dictionary = W.season().get("look", {})
	if not level.is_outdoor():
		return
	var cells: Array = (level.spawns.get(".", []) as Array).duplicate()
	cells.sort()
	if bool(look.get("flowers", false)):
		var kinds := ["nature-kit/flower_purpleA.glb", "nature-kit/flower_redB.glb", "nature-kit/flower_yellowA.glb", "nature-kit/flower_yellowC.glb", "nature-kit/flower_purpleC.glb"]
		var n := 0
		for c in cells:
			if n >= 40:
				break
			if (c.x * 31 + c.y * 17) % 9 != 0:
				continue
			var at: Vector3 = level.cell_to_world(c) + Vector3(_rng.randf_range(-0.7, 0.7), 0.0, _rng.randf_range(-0.7, 0.7))
			level._prop(kinds[n % kinds.size()], at, 1.6, _rng.randf() * TAU)
			n += 1
		_dressed["flowers"] = n
	if bool(look.get("snow_ground", false)) and level.is_outdoor():
		# round 63: under the sky the snow lies in the ground itself -- the map
		# and the land past it alike, so there's no pale square where the map is
		var lm = preload("res://scripts/world/Horizon.gd").land_material(level)
		if lm is ShaderMaterial:
			(lm as ShaderMaterial).set_shader_parameter("snow_cover", 0.38)
		_dressed["snow_ground"] = true
	elif bool(look.get("snow_ground", false)):
		# snow on the ground: a pale sheet laid over the whole valley floor
		_snow = MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(level.width * level.CELL, level.height * level.CELL)
		_snow.mesh = pm
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.86, 0.9, 0.97, 0.3)        # round 62: softer -- a sunny Frost day washed everything out
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.roughness = 0.9
		_snow.material_override = m
		_snow.position = Vector3(level.width * level.CELL / 2.0 - level.CELL / 2.0, 0.04, level.height * level.CELL / 2.0 - level.CELL / 2.0)
		add_child(_snow)
		_dressed["snow_ground"] = true


func _festival_lanterns(f: Dictionary) -> void:
	## the village, strung with lanterns along its roads
	var cols: Array = f.get("colors", [[1, 0.8, 0.4]])
	var roads: Array = (level.spawns.get(",", []) as Array).duplicate()
	roads.sort()
	var n := 0
	for c in roads:
		if n >= 26:
			break
		if (c.x * 13 + c.y * 7) % 6 != 0:
			continue
		var at: Vector3 = level.cell_to_world(c)
		var cc: Array = cols[n % cols.size()]
		var col := Color(float(cc[0]), float(cc[1]), float(cc[2]))
		var lamp := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.16
		sm.height = 0.3
		lamp.mesh = sm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = col
		mat.emission_enabled = true
		mat.emission = col
		mat.emission_energy_multiplier = 1.4
		lamp.material_override = mat
		lamp.position = at + Vector3(0.6, 2.75, 0.6)
		add_child(lamp)
		# a thin dark post with a little paper shade on top
		var post := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.035
		cm.bottom_radius = 0.05
		cm.height = 2.6
		post.mesh = cm
		var pm := StandardMaterial3D.new()
		pm.albedo_color = Color(0.18, 0.12, 0.08)
		post.material_override = pm
		post.position = at + Vector3(0.6, 1.3, 0.6)
		post.name = "FestivalPost%d" % n
		add_child(post)
		var shade := MeshInstance3D.new()
		var sc := CylinderMesh.new()
		sc.top_radius = 0.05
		sc.bottom_radius = 0.22
		sc.height = 0.14
		shade.mesh = sc
		var shm := StandardMaterial3D.new()
		shm.albedo_color = col.darkened(0.3)
		shade.material_override = shm
		shade.position = at + Vector3(0.6, 2.95, 0.6)
		add_child(shade)
		if n % 2 == 0:
			var l := OmniLight3D.new()
			l.light_color = col
			l.light_energy = 1.6
			l.omni_range = 7.0
			l.position = at + Vector3(0.6, 2.9, 0.6)
			add_child(l)
		n += 1
	_dressed["lanterns"] = n
