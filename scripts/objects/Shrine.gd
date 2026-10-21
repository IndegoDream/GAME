extends StaticBody3D
## A cultivation shrine ('Z'). Press E to sit and cultivate: qi flows in
## much faster here than meditating anywhere else. If you quit while
## sitting at a shrine, your nanites keep refining qi at the shrine rate
## until you come back (up to 8 hours).

var level
var cell := Vector2i.ZERO
var _light: OmniLight3D
var _t := 0.0


func setup(lvl, args: Dictionary) -> void:
	level = lvl
	cell = args.get("cell", Vector2i.ZERO)


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("shrine")
	var ring = load("res://assets/kenney/nature-kit/statue_ring.glb").instantiate()
	ring.scale = Vector3.ONE * 2.0
	add_child(ring)
	var stones = preload("res://scripts/core/Art.gd").make("nature-kit/campfire_stones.glb")
	stones.scale = Vector3.ONE * 2.4
	stones.position = Vector3(0, 0.1, 0)
	add_child(stones)
	var orb := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.28
	sph.height = 0.56
	orb.mesh = sph
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.5, 0.95, 1.0)
	m.emission_enabled = true
	m.emission = Color(0.4, 0.9, 1.0)
	m.emission_energy_multiplier = 3.0
	orb.material_override = m
	orb.position = Vector3(0, 1.4, 0)
	orb.name = "Orb"
	add_child(orb)
	_light = OmniLight3D.new()
	_light.light_color = Color(0.45, 0.9, 1.0)
	_light.omni_range = 7.0
	_light.light_energy = 1.6
	_light.position = Vector3(0, 1.5, 0)
	add_child(_light)
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.6
	cyl.height = 2.0
	shape.shape = cyl
	shape.position = Vector3(0, 1.0, 0)
	add_child(shape)


func _process(delta: float) -> void:
	_t += delta
	var orb = get_node_or_null("Orb")
	if orb:
		orb.position.y = 1.4 + sin(_t * 1.6) * 0.12
	_light.light_energy = 1.5 + (0.8 if Game.meditating else 0.0) + sin(_t * 2.0) * 0.15


func prompt() -> String:
	return "E: Sit and cultivate (stand up by moving)" if not Game.meditating else "Cultivating... (move to stand)"


func interact(player) -> void:
	if player.has_method("start_meditating"):
		player.start_meditating(true)
