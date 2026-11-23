extends Node3D
## Round 185 (Robert: "keep bringing it to life -- I want a wow factor"): lantern night in Eliet.
## On a clear evening every other day (and every festival evening), from dusk until late, the village
## sends up paper lanterns: they lift off from all over the village, warm and glowing, rise slowly,
## drift on the wind and climb until they're sparks among the stars. Arrive in the middle of it and
## the sky is already full. Looks only (WorldFX starts and stops it; off on Low effects).

const MAX_ALIVE := 70
const TOP := 150.0

var level
var running := false            # WorldFX: spawn new ones (old ones keep rising either way)
var spawned := 0                # (tests)
var _lanterns: Array = []       # [node, age, speed, sway phase, sway size, wind scale]
var _rng := RandomNumberGenerator.new()
var _next := 0.0
var _mat: StandardMaterial3D
var _halo_mat: StandardMaterial3D
var _mesh: CylinderMesh
var _halo: QuadMesh
var wind := Vector3(0.35, 0.0, 0.15)


func setup(lvl) -> void:
	level = lvl


func _ready() -> void:
	name = "SkyLanterns"
	add_to_group("fog_exempt")
	_rng.seed = hash("lanterns|%s" % str(level.level_id if level else ""))
	_mesh = CylinderMesh.new()
	_mesh.top_radius = 0.26
	_mesh.bottom_radius = 0.32
	_mesh.height = 0.62
	_mesh.radial_segments = 8
	_mesh.rings = 1
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(1.0, 0.62, 0.28)
	_mat.emission_enabled = true
	_mat.emission = Color(1.0, 0.5, 0.16)
	_mat.emission_energy_multiplier = 2.6
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mesh.material = _mat
	_halo = QuadMesh.new()
	_halo.size = Vector2(2.4, 2.4)
	_halo_mat = StandardMaterial3D.new()
	_halo_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_halo_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_halo_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_halo_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_halo_mat.albedo_color = Color(1.0, 0.55, 0.2, 0.55)
	_halo_mat.albedo_texture = preload("res://scripts/fx/FX.gd").soft_dot()
	_halo.material = _halo_mat


func start(prewarm: bool) -> void:
	## lantern night begins (prewarm: it began a while ago -- the sky already has some up)
	if running:
		return
	running = true
	_next = 0.5
	if prewarm:
		for i in 22:
			var l := _launch()
			if l.is_empty():
				break
			var age := _rng.randf_range(5.0, 120.0)
			_advance(l, age)


func stop() -> void:
	running = false


func alive() -> int:
	return _lanterns.size()


func highest() -> float:
	var y := -INF
	for l in _lanterns:
		y = maxf(y, (l[0] as Node3D).position.y)
	return y


func _ground_spot() -> Vector3:
	var cells: Array = level.spawns.get(".", []) if level != null and level.get("spawns") is Dictionary else []
	if cells.is_empty():
		return Vector3(_rng.randf_range(-20, 20), 0.0, _rng.randf_range(-20, 20))
	var c: Vector2i = cells[_rng.randi() % cells.size()]
	# half of them go up near you, so the closest ones pass right over your head
	var pl = get_tree().get_first_node_in_group("player") if is_inside_tree() else null
	if pl is Node3D and _rng.randf() < 0.5:
		for i in 14:
			var c2: Vector2i = cells[_rng.randi() % cells.size()]
			if level.cell_to_world(c2).distance_to((pl as Node3D).global_position) < 26.0:
				c = c2
				break
	return level.cell_to_world(c) + Vector3(_rng.randf_range(-0.8, 0.8), 0.0, _rng.randf_range(-0.8, 0.8))


func _launch() -> Array:
	if _lanterns.size() >= MAX_ALIVE:
		return []
	var n := Node3D.new()
	var body := MeshInstance3D.new()
	body.mesh = _mesh
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(body)
	var glow := MeshInstance3D.new()
	glow.mesh = _halo
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(glow)
	add_child(n)
	n.position = _ground_spot() + Vector3(0, 1.6, 0)
	var l := [n, 0.0, _rng.randf_range(0.55, 0.95), _rng.randf() * TAU, _rng.randf_range(0.08, 0.3), _rng.randf_range(0.7, 1.3)]
	_lanterns.append(l)
	spawned += 1
	return l


func _advance(l: Array, dt: float) -> void:
	var n: Node3D = l[0]
	var age: float = float(l[1]) + dt
	l[1] = age
	var up: float = float(l[2]) * clampf(0.35 + age / 8.0, 0.35, 1.0)      # a slow lift-off, then a steady climb
	var sway := Vector3(cos(age * 0.7 + float(l[3])), 0.0, sin(age * 0.5 + float(l[3]))) * float(l[4])
	n.position += (Vector3(0, up, 0) + wind * float(l[5]) * clampf(n.position.y / 25.0, 0.2, 1.6) + sway) * dt
	n.rotation.y += dt * 0.3


func _process(delta: float) -> void:
	if running:
		_next -= delta
		if _next <= 0.0:
			_next = _rng.randf_range(1.0, 2.4)
			_launch()
	var i := _lanterns.size() - 1
	while i >= 0:
		var l: Array = _lanterns[i]
		_advance(l, delta)
		if (l[0] as Node3D).position.y > TOP or float(l[1]) > 260.0:
			(l[0] as Node3D).queue_free()
			_lanterns.remove_at(i)
		i -= 1
