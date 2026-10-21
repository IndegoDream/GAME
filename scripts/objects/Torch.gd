extends Node3D
## A dungeon torch: a small flame on a post and a flickering warm light.

var _light: OmniLight3D
var _t := 0.0
var _seed := 0.0
var color := Color(1.0, 0.68, 0.35)     # each region burns its own light (Look.gd "torch")
var on_wall := false                    # hung on the wall in a passage: a bracket, not a post in the walkway


func setup(_level, args: Dictionary) -> void:
	on_wall = bool(args.get("wall", false))
	var dv = args.get("dir", Vector2.ZERO)
	dir = dv if dv is Vector2 else Vector2.ZERO
	var c = args.get("color", [])
	if c is Array and c.size() >= 3:
		color = Color(float(c[0]), float(c[1]), float(c[2]))


var dir := Vector2.ZERO                 # which way the wall is (wall torches)
var _flames: Array = []


func _mat(col: Color, rough: float = 0.8, metal: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = metal
	return m


func _add(parent: Node3D, mesh: Mesh, mat: Material, at: Vector3, sc := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = at
	mi.scale = sc
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF     # (its own light sits on it)
	parent.add_child(mi)
	return mi


func _fire(col: Color, energy: float) -> StandardMaterial3D:
	var f := StandardMaterial3D.new()
	f.albedo_color = col
	f.emission_enabled = true
	f.emission = col
	f.emission_energy_multiplier = energy
	f.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return f


func _ready() -> void:
	_seed = randf() * 10.0
	var iron := _mat(Color(0.16, 0.15, 0.16), 0.5, 0.7)
	var wood := _mat(Color(0.35, 0.22, 0.12))
	var root := Node3D.new()
	add_child(root)
	var top := 1.45 if on_wall else 1.55
	if on_wall:
		# a bracket: a plate on the wall, an arm out, an iron cup with a wrapped head
		root.rotation.y = atan2(dir.x, dir.y)          # local +z points at the wall
		var plate := BoxMesh.new()
		plate.size = Vector3(0.2, 0.34, 0.05)
		_add(root, plate, iron, Vector3(0, 1.35, 0.2))
		var arm := BoxMesh.new()
		arm.size = Vector3(0.05, 0.05, 0.24)
		_add(root, arm, iron, Vector3(0, 1.3, 0.09))
		var brace := BoxMesh.new()
		brace.size = Vector3(0.04, 0.04, 0.26)
		_add(root, brace, iron, Vector3(0, 1.2, 0.13)).rotation.x = -0.6
	else:
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.05
		cyl.bottom_radius = 0.08
		cyl.height = 1.5
		_add(root, cyl, wood, Vector3(0, 0.75, 0))
	var cup := CylinderMesh.new()
	cup.top_radius = 0.12
	cup.bottom_radius = 0.06
	cup.height = 0.2
	_add(root, cup, iron, Vector3(0, top, 0))
	var head := SphereMesh.new()
	head.radius = 0.09
	head.height = 0.16
	_add(root, head, _mat(Color(0.2, 0.12, 0.07), 1.0), Vector3(0, top + 0.12, 0))
	# the flame: an outer teardrop, a hot core and a thin tip, all swaying
	var outer := SphereMesh.new()
	outer.radius = 0.12
	outer.height = 0.24
	var f1 := _add(root, outer, _fire(color.lerp(Color(1.0, 0.55, 0.12), 0.35), 3.2), Vector3(0, top + 0.3, 0), Vector3(0.85, 1.7, 0.85))
	var core := SphereMesh.new()
	core.radius = 0.07
	core.height = 0.14
	var f2 := _add(root, core, _fire(Color(1.0, 0.92, 0.6), 4.5), Vector3(0, top + 0.25, 0), Vector3(0.8, 1.5, 0.8))
	var tip := CylinderMesh.new()
	tip.top_radius = 0.0
	tip.bottom_radius = 0.06
	tip.height = 0.22
	var f3 := _add(root, tip, _fire(color, 3.0), Vector3(0, top + 0.5, 0))
	_flames = [f1, f2, f3]

	_light = OmniLight3D.new()
	_light.light_color = color
	_light.omni_range = 12.0
	_light.light_energy = 2.4
	_light.position = Vector3(0, top + 0.45, 0) + (Vector3(dir.x, 0, dir.y) * -0.2 if on_wall else Vector3.ZERO)
	add_child(_light)


var _shadow_t := 0.0


func _process(delta: float) -> void:
	_t += delta
	# High+: torches near you cast real shadows (a few at a time -- every
	# torch on a floor casting them would cost more than it shows)
	_shadow_t -= delta
	if _shadow_t <= 0.0:
		_shadow_t = 0.5 + randf() * 0.2
		var r := preload("res://scripts/core/Gfx.gd").torch_shadow_radius()
		var on := false
		if r > 0.0 and is_inside_tree():
			var pl = get_tree().get_first_node_in_group("player")
			on = pl != null and pl.global_position.distance_to(global_position) < r
		if _light.shadow_enabled != on:
			_light.shadow_enabled = on
	_light.light_energy = 2.3 + sin(_t * 9.0 + _seed) * 0.18 + sin(_t * 23.0 + _seed * 2.0) * 0.1
	# the flames lick and sway (cheap: only their scale and lean)
	for k in _flames.size():
		var f: MeshInstance3D = _flames[k]
		var s := 1.0 + 0.12 * sin(_t * (11.0 + k * 3.0) + _seed + k)
		f.rotation.z = 0.08 * sin(_t * (7.0 + k) + _seed * 1.3)
		f.rotation.x = 0.06 * sin(_t * (5.0 + k * 2.0) + _seed)
		if k == 2:
			f.scale.y = s * 1.1
