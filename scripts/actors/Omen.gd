extends Node3D
## Round 152: an omen in the deep -- a glow with a column of light above it. Walk into it (no key needed) and it
## pays (Pull.collect). It fades if you leave the level; it does not come back once taken.

var level
var cell := Vector2i.ZERO
var kind := "cache"
var _taken := false
var _t := 0.0
var _orb: MeshInstance3D
var _light: OmniLight3D


func setup(lvl, args: Dictionary) -> void:
	level = lvl
	cell = args.get("cell", Vector2i.ZERO)
	kind = str(args.get("kind", "cache"))


func _color() -> Color:
	var P = Game.sys("pull")
	var a: Array = P.omen_def(kind).get("color", [1.0, 0.85, 0.4]) if P != null else [1.0, 0.85, 0.4]
	return Color(float(a[0]), float(a[1]), float(a[2]))


func _ready() -> void:
	add_to_group("omen")
	var c := _color()
	_orb = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.28
	sm.height = 0.56
	_orb.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = c
	mat.emission_enabled = true
	mat.emission = c
	mat.emission_energy_multiplier = 3.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_orb.material_override = mat
	_orb.position.y = 1.1
	add_child(_orb)
	var col := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.05
	cm.bottom_radius = 0.2
	cm.height = 16.0
	cm.radial_segments = 12
	col.mesh = cm
	var cmat := StandardMaterial3D.new()
	cmat.albedo_color = Color(c.r, c.g, c.b, 0.22)
	cmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cmat.emission_enabled = true
	cmat.emission = c
	cmat.emission_energy_multiplier = 1.2
	col.material_override = cmat
	col.position.y = 8.0
	col.visibility_range_end = 70.0
	col.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(col)
	_light = OmniLight3D.new()
	_light.light_color = c
	_light.light_energy = 1.6
	_light.omni_range = 6.0
	_light.position.y = 1.2
	add_child(_light)


func _process(delta: float) -> void:
	if _taken:
		return
	_t += delta
	if _orb:
		_orb.position.y = 1.1 + sin(_t * 2.0) * 0.12
		_orb.rotate_y(delta * 1.5)
	if _light:
		_light.light_energy = 1.4 + sin(_t * 3.0) * 0.4
	var pl = get_tree().get_first_node_in_group("player")
	if pl == null:
		return
	if (pl.global_position - global_position).length() < 1.9:
		_taken = true
		var P = Game.sys("pull")
		if P != null:
			P.collect(kind, global_position)
		var tw := create_tween()
		tw.tween_property(self, "scale", Vector3(0.01, 3.0, 0.01), 0.45)
		tw.tween_callback(queue_free)
