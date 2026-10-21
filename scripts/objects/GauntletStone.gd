extends StaticBody3D
## The Ember Stone (round 126): begin the Gauntlet, spend embers on blessings.

const Hook := preload("res://scripts/systems/Hook.gd")
var level
var label := "The Ember Stone"
var tint := Color(1.0, 0.5, 0.2)
var _t := 0.0
var _orb: MeshInstance3D


func setup(lvl, _args: Dictionary) -> void:
	level = lvl


func _ready() -> void:
	add_to_group("interactable")
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.36, 0.36, 0.4)
	stone.roughness = 0.9
	var base := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.7
	bm.bottom_radius = 0.85
	bm.height = 1.0
	bm.radial_segments = 8
	base.mesh = bm
	base.material_override = stone
	base.position.y = 0.5
	add_child(base)
	var glow := StandardMaterial3D.new()
	glow.albedo_color = tint
	glow.emission_enabled = true
	glow.emission = tint
	glow.emission_energy_multiplier = 1.6
	_orb = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.28
	sm.height = 0.56
	_orb.mesh = sm
	_orb.material_override = glow
	_orb.position.y = 1.7
	_orb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_orb)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.outer_radius = 0.9
	tm.inner_radius = 0.82
	ring.mesh = tm
	ring.material_override = glow
	ring.position.y = 0.06
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	var lamp := OmniLight3D.new()
	lamp.light_color = tint
	lamp.omni_range = 5.0
	lamp.light_energy = 1.2
	lamp.position.y = 1.8
	add_child(lamp)
	var sign := Label3D.new()
	sign.text = label
	sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sign.pixel_size = 0.009
	sign.no_depth_test = true
	sign.position = Vector3(0, 2.5, 0)
	sign.font_size = 40
	sign.outline_size = 10
	sign.modulate = tint.lerp(Color.WHITE, 0.5)
	add_child(sign)
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.8
	cyl.height = 1.2
	shape.shape = cyl
	shape.position.y = 0.6
	add_child(shape)


func _process(delta: float) -> void:
	_t += delta
	if _orb:
		_orb.position.y = 1.7 + sin(_t * 2.0) * 0.1


func prompt() -> String:
	return "Press E: %s" % label


func interact(_player) -> void:
	var hud = get_tree().get_first_node_in_group("hud")
	if hud == null or hud.is_blocking():
		return
	Hook.gauntlet_menu(hud)
