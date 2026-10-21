extends Node3D
## Little lives (Robert, 2026-10-02: ambient life). Rats that scurry along
## the floor and bolt when you come close, bats circling up near the roof,
## moths that dance around the light, cats that wander a town and sit, and
## birds in the village that hop about and take off when you walk up. They
## can't be fought or talked to -- they're the world getting on with its own
## business. No collision; nothing in play depends on them.

var level
var cell := Vector2i.ZERO
var kind := "rat"
var _rng := RandomNumberGenerator.new()
var _home := Vector3.ZERO
var _target := Vector3.ZERO
var _wait := 0.0
var _t := 0.0
var _body: Node3D
var _wings: Array[Node3D] = []
var _speed := 2.0
var _fleeing := false
var _airborne := false


func setup(lvl, args: Dictionary) -> void:
	level = lvl
	cell = args.get("cell", Vector2i.ZERO)
	kind = str(args.get("kind", "rat"))
	_rng.seed = int(args.get("seed", 0))


func _ready() -> void:
	_home = position
	_target = position
	_t = _rng.randf() * 10.0
	_body = Node3D.new()
	add_child(_body)
	match kind:
		"bat":
			_build_bat()
			position.y = 2.8 + _rng.randf() * 0.6
		"moth":
			_build_moth()
			position.y = 1.6
		"cat":
			_build_cat()
		"bird":
			_build_bird()
		_:
			_build_rat()
	if DisplayServer.get_name() == "headless":
		set_process(false)


# ---- bodies (made from simple shapes, tinted to read at the game's distance) ----

func _mat(c: Color, glow: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = glow
	return m


func _part(mesh: Mesh, c: Color, at: Vector3, glow: float = 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat(c, glow)
	mi.position = at
	_body.add_child(mi)
	return mi


func _sphere(r: float, h: float = -1.0) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = h if h > 0.0 else r * 2.0
	s.radial_segments = 8
	s.rings = 4
	return s


func _build_rat() -> void:
	var c := Color(0.32, 0.27, 0.24)
	_part(_sphere(0.13, 0.22), c, Vector3(0, 0.1, 0)).scale = Vector3(1.0, 1.0, 1.7)
	_part(_sphere(0.08), c.lightened(0.05), Vector3(0, 0.13, 0.24))
	var tail := CylinderMesh.new()
	tail.top_radius = 0.012
	tail.bottom_radius = 0.02
	tail.height = 0.35
	var t := _part(tail, Color(0.55, 0.42, 0.4), Vector3(0, 0.08, -0.36))
	t.rotation.x = PI / 2.3
	_speed = 3.2


func _build_bat() -> void:
	var c := Color(0.12, 0.1, 0.13)
	_part(_sphere(0.1, 0.18), c, Vector3.ZERO)
	for side in [-1.0, 1.0]:
		var w := QuadMesh.new()
		w.size = Vector2(0.38, 0.2)
		var wi := _part(w, c, Vector3(side * 0.22, 0, 0))
		wi.rotation.x = -PI / 2
		(wi.material_override as StandardMaterial3D).cull_mode = BaseMaterial3D.CULL_DISABLED
		_wings.append(wi)
	_speed = 3.0


func _build_moth() -> void:
	_part(_sphere(0.035), Color(1.0, 0.95, 0.75), Vector3.ZERO, 3.0)
	for side in [-1.0, 1.0]:
		var w := QuadMesh.new()
		w.size = Vector2(0.09, 0.07)
		var wi := _part(w, Color(0.95, 0.9, 0.75), Vector3(side * 0.05, 0, 0), 1.0)
		wi.rotation.x = -PI / 2
		(wi.material_override as StandardMaterial3D).cull_mode = BaseMaterial3D.CULL_DISABLED
		_wings.append(wi)
	_speed = 1.2


func _build_cat() -> void:
	var cols := [Color(0.85, 0.55, 0.25), Color(0.2, 0.2, 0.22), Color(0.85, 0.82, 0.78), Color(0.5, 0.45, 0.4)]
	var c: Color = cols[_rng.randi() % cols.size()]
	_part(_sphere(0.16, 0.26), c, Vector3(0, 0.25, 0)).scale = Vector3(1.0, 1.0, 1.8)
	var head := _part(_sphere(0.12), c, Vector3(0, 0.42, 0.3))
	for side in [-1.0, 1.0]:
		var ear := PrismMesh.new()
		ear.size = Vector3(0.07, 0.09, 0.03)
		_part(ear, c, head.position + Vector3(side * 0.06, 0.11, 0))
	var tail := CylinderMesh.new()
	tail.top_radius = 0.025
	tail.bottom_radius = 0.035
	tail.height = 0.4
	var t := _part(tail, c, Vector3(0, 0.42, -0.42))
	t.rotation.x = -0.5
	for leg in [Vector3(-0.08, 0.08, 0.18), Vector3(0.08, 0.08, 0.18), Vector3(-0.08, 0.08, -0.18), Vector3(0.08, 0.08, -0.18)]:
		var lm := CylinderMesh.new()
		lm.top_radius = 0.03
		lm.bottom_radius = 0.03
		lm.height = 0.16
		_part(lm, c, leg)
	_speed = 1.4


func _build_bird() -> void:
	var cols := [Color(0.45, 0.35, 0.28), Color(0.3, 0.4, 0.6), Color(0.8, 0.3, 0.2)]
	var c: Color = cols[_rng.randi() % cols.size()]
	_part(_sphere(0.08, 0.13), c, Vector3(0, 0.1, 0)).scale = Vector3(1.0, 1.0, 1.4)
	_part(_sphere(0.05), c.lightened(0.15), Vector3(0, 0.16, 0.09))
	var beak := PrismMesh.new()
	beak.size = Vector3(0.025, 0.04, 0.025)
	_part(beak, Color(0.95, 0.75, 0.2), Vector3(0, 0.16, 0.15)).rotation.x = PI / 2
	for side in [-1.0, 1.0]:
		var w := QuadMesh.new()
		w.size = Vector2(0.16, 0.08)
		var wi := _part(w, c.darkened(0.2), Vector3(side * 0.09, 0.12, 0))
		wi.rotation.x = -PI / 2
		(wi.material_override as StandardMaterial3D).cull_mode = BaseMaterial3D.CULL_DISABLED
		wi.visible = false
		_wings.append(wi)
	_speed = 2.0


# ---- living --------------------------------------------------------------------

func _player_pos():
	var p = get_tree().get_first_node_in_group("player")
	return p.global_position if p else null


func _pick_spot(radius: int) -> Vector3:
	## A nearby open floor cell (rats and cats keep to the floor).
	for i in 8:
		var c := Vector2i(cell.x + _rng.randi_range(-radius, radius), cell.y + _rng.randi_range(-radius, radius))
		if level and level.is_free(c):
			var w: Vector3 = level.cell_to_world(c)
			return Vector3(w.x + _rng.randf_range(-0.6, 0.6), position.y, w.z + _rng.randf_range(-0.6, 0.6))
	return _home


func _process(delta: float) -> void:
	_t += delta
	match kind:
		"bat":
			_bat(delta)
		"moth":
			_moth(delta)
		"bird":
			_bird(delta)
		_:
			_walker(delta)


func _face(dir: Vector3) -> void:
	if dir.length() > 0.01:
		_body.rotation.y = atan2(dir.x, dir.z)


func _walker(delta: float) -> void:
	var pp = _player_pos()
	var near: bool = pp != null and Vector2(pp.x - position.x, pp.z - position.z).length() < (3.0 if kind == "rat" else 1.6)
	if near and not _fleeing:
		_fleeing = true
		var away: Vector3 = (position - pp)
		away.y = 0
		_target = position + away.normalized() * 4.0
		var c: Vector2i = level.world_to_cell(_target) if level else cell
		if level and not level.is_free(c):
			_target = _pick_spot(3)
		_wait = 0.0
	if _wait > 0.0:
		_wait -= delta
		if kind == "cat":
			_body.position.y = -0.04 * (1.0 - cos(_t * 2.0)) * 0.5      # breathing while it sits
		return
	var to := _target - position
	to.y = 0
	if to.length() < 0.15:
		_fleeing = false
		_wait = _rng.randf_range(1.0, 4.0) if kind == "rat" else _rng.randf_range(4.0, 12.0)
		cell = level.world_to_cell(position) if level else cell
		_target = _pick_spot(3 if kind == "rat" else 4)
		return
	var sp := _speed * (2.2 if _fleeing else 1.0)
	position += to.normalized() * minf(to.length(), sp * delta)
	_face(to)
	_body.position.y = absf(sin(_t * 18.0)) * 0.03


func _bat(delta: float) -> void:
	var r := 2.5 + sin(_t * 0.3) * 0.8
	var a := _t * (_speed / r)
	var goal := _home + Vector3(cos(a) * r, 0, sin(a) * r)
	goal.y = 2.8 + sin(_t * 1.7) * 0.4
	var pp = _player_pos()
	if pp != null and pp.distance_to(position) < 2.5:
		goal.y += 1.0
	var d := goal - position
	position += d * minf(delta * 3.0, 1.0)
	_face(Vector3(d.x, 0, d.z))
	var flap := sin(_t * 22.0) * 0.9
	if _wings.size() == 2:
		_wings[0].rotation.z = flap
		_wings[1].rotation.z = -flap


func _moth(delta: float) -> void:
	var goal := _home + Vector3(sin(_t * 0.9) * 1.2 + sin(_t * 2.3) * 0.3, 1.6 + sin(_t * 1.3) * 0.5, cos(_t * 0.7) * 1.2)
	position += (goal - position) * minf(delta * 2.0, 1.0)
	var flap := sin(_t * 30.0) * 0.8
	if _wings.size() == 2:
		_wings[0].rotation.z = flap
		_wings[1].rotation.z = -flap


func _bird(delta: float) -> void:
	var pp = _player_pos()
	if not _airborne and pp != null and Vector2(pp.x - position.x, pp.z - position.z).length() < 3.0:
		_airborne = true
		_target = _pick_spot(6)
		for w in _wings:
			w.visible = true
	if _airborne:
		var to := _target - position
		to.y = 0
		var hop := clampf(to.length() / 4.0, 0.0, 1.0)
		position += to.normalized() * minf(to.length(), 5.0 * delta)
		position.y = _home.y + 2.0 * hop
		_face(to)
		var flap := sin(_t * 25.0) * 1.0
		if _wings.size() == 2:
			_wings[0].rotation.z = flap
			_wings[1].rotation.z = -flap
		if to.length() < 0.1:
			_airborne = false
			position.y = _home.y
			cell = level.world_to_cell(position) if level else cell
			for w in _wings:
				w.visible = false
		return
	# on the ground: a peck, a hop
	_wait -= delta
	if _wait <= 0.0:
		_wait = _rng.randf_range(0.6, 2.5)
		_body.rotation.y += _rng.randf_range(-1.2, 1.2)
		var step := Vector3(sin(_body.rotation.y), 0, cos(_body.rotation.y)) * 0.25
		var c: Vector2i = level.world_to_cell(position + step) if level else cell
		if level and level.is_free(c):
			position += step
	_body.rotation.x = -0.4 if fmod(_t, 1.3) < 0.15 else 0.0
