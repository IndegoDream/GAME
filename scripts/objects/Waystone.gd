extends StaticBody3D
## A waystone (round 63, systems/Travel.gd). A carved standing stone with a
## band of runes and a ring of light turning above it. Dark until you come
## near; then it wakes (ATTUNED), and from then on it glows the deep's blue
## while its place is yours to travel to -- or a dim ember while the floor's
## master still lives. Press E at it to travel.

var level
var cell := Vector2i.ZERO
var place_id := ""
var place_name := ""
var _t := 0.0
var _ring: MeshInstance3D
var _band_mat: StandardMaterial3D
var _ring_mat: StandardMaterial3D
var _ground_glow: MeshInstance3D
var _ground_mat: StandardMaterial3D
var _light: OmniLight3D
var _woke := 0.0           # a flare when it's attuned


func setup(lvl, args: Dictionary) -> void:
	level = lvl
	cell = args.get("cell", Vector2i.ZERO)
	place_id = str(args.get("id", ""))
	place_name = str(args.get("name", place_id))


func _travel():
	return Game.sys("travel")


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("waystone")
	var stone_mat := StandardMaterial3D.new()
	stone_mat.albedo_color = Color(0.42, 0.42, 0.45)
	stone_mat.roughness = 0.92
	# the stone: a tapering six-sided pillar on a round plinth
	var plinth := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.95
	pm.bottom_radius = 1.1
	pm.height = 0.3
	pm.radial_segments = 24
	plinth.mesh = pm
	plinth.material_override = stone_mat
	plinth.position.y = 0.15
	add_child(plinth)
	var pillar := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.26
	cm.bottom_radius = 0.46
	cm.height = 2.6
	cm.radial_segments = 6
	pillar.mesh = cm
	pillar.material_override = stone_mat
	pillar.position.y = 1.6
	add_child(pillar)
	var cap := MeshInstance3D.new()
	var capm := CylinderMesh.new()
	capm.top_radius = 0.02
	capm.bottom_radius = 0.3
	capm.height = 0.4
	capm.radial_segments = 6
	cap.mesh = capm
	cap.material_override = stone_mat
	cap.position.y = 3.1
	add_child(cap)
	# the rune band
	_band_mat = StandardMaterial3D.new()
	_band_mat.albedo_color = Color(0.1, 0.12, 0.14)
	_band_mat.emission_enabled = true
	_band_mat.emission = Color(0.3, 0.75, 1.0)
	_band_mat.emission_energy_multiplier = 0.0
	var band := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.37
	bm.bottom_radius = 0.39
	bm.height = 0.22
	bm.radial_segments = 6
	band.mesh = bm
	band.material_override = _band_mat
	band.position.y = 1.75
	add_child(band)
	# the ring of light that turns above it
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ring_mat.albedo_color = Color(0.45, 0.85, 1.0, 0.0)
	_ring = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.62
	tm.outer_radius = 0.68
	tm.rings = 48
	_ring.mesh = tm
	_ring.material_override = _ring_mat
	_ring.position.y = 2.35
	_ring.rotation_degrees.x = 72.0
	add_child(_ring)
	# ground glow ring around the plinth
	_ground_mat = StandardMaterial3D.new()
	_ground_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ground_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ground_mat.albedo_color = Color(0.45, 0.85, 1.0, 0.0)
	_ground_glow = MeshInstance3D.new()
	_ground_glow.name = "GroundGlow"
	var gtm := TorusMesh.new()
	gtm.inner_radius = 1.54
	gtm.outer_radius = 1.66
	gtm.rings = 48
	_ground_glow.mesh = gtm
	_ground_glow.material_override = _ground_mat
	_ground_glow.position.y = 0.02
	_ground_glow.visible = false
	add_child(_ground_glow)
	_light = OmniLight3D.new()
	_light.light_color = Color(0.45, 0.85, 1.0)
	_light.omni_range = 8.0
	_light.light_energy = 0.0
	_light.position = Vector3(0, 2.3, 0)
	add_child(_light)
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.55
	cyl.height = 3.2
	shape.shape = cyl
	shape.position = Vector3(0, 1.6, 0)
	add_child(shape)
	rotation.y = float(hash(place_id) % 628) / 100.0
	_look()


func attuned() -> bool:
	var T = _travel()
	return T != null and T.stones.has(place_id)


func ready_to_travel_here() -> bool:
	var T = _travel()
	return T != null and attuned() and T.conquered(place_id)


func _look() -> void:
	## dark / ember (attuned, master alive) / blue (yours)
	var c := Color(0.45, 0.85, 1.0) if ready_to_travel_here() else Color(1.0, 0.55, 0.25)
	var on := attuned()
	_band_mat.emission = c
	_ring_mat.albedo_color = Color(c.r, c.g, c.b, _ring_mat.albedo_color.a)
	_ground_mat.albedo_color = Color(c.r, c.g, c.b, _ground_mat.albedo_color.a)
	_ground_glow.visible = ready_to_travel_here()
	_light.light_color = c
	if not on:
		_band_mat.emission_energy_multiplier = 0.15


func _process(delta: float) -> void:
	_t += delta
	var T = _travel()
	if T == null:
		return
	if not attuned():
		_ground_glow.visible = false
		var pl = get_tree().get_first_node_in_group("player")
		if pl and is_instance_valid(pl) and (pl as Node3D).global_position.distance_to(global_position) < float(T.cfg.get("attune_radius", 3.2)):
			if T.attune(place_id, place_name):
				_woke = 1.6
				Game.sfx("waystone", 1.0)
				_look()
		return
	var ready := ready_to_travel_here()
	var base := 2.2 if ready else 0.9
	_woke = maxf(0.0, _woke - delta)
	_band_mat.emission_energy_multiplier = base + sin(_t * 1.7) * 0.35 + _woke * 3.0
	_ring_mat.albedo_color.a = (0.55 if ready else 0.25) + 0.1 * sin(_t * 2.3) + minf(_woke, 1.0) * 0.4
	_ring.rotation.y += delta * (0.7 if ready else 0.25)
	_ring.position.y = 2.35 + sin(_t * 1.2) * 0.08
	_ground_glow.visible = ready
	if ready:
		_ground_mat.albedo_color.a = 0.28 + 0.12 * sin(_t * 1.8) + minf(_woke, 1.0) * 0.3
	_light.light_energy = (1.4 if ready else 0.5) + _woke * 2.5


func prompt() -> String:
	if not attuned():
		return "A waystone (come closer to attune it)"
	return "E: Waystone -- quick travel"


func interact(_player) -> void:
	var hud = get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("open_travel"):
		hud.open_travel(true)
