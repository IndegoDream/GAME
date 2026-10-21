extends Node3D
## Motes: what hangs in the air of a place (Look.gd "motes") -- dust in the
## warrens, embers rising in the forges, spores in the deeps, leaves falling
## through the canopy, water dripping in the drowned halls, ash, snow,
## sparks, glints of qi -- and smoke from a town's chimneys. A cloud of
## them follows you around, so a big floor costs no more than a small one.
## Looks only: nothing here touches play. Off on the headless engine check.

const FOLLOW_KINDS := ["dust", "embers", "spores", "leaves", "drips", "sparks", "snow", "glints", "ash", "rain", "mist"]
const SPEC := {
	# amount, lifetime, size, colour, gravity y, initial speed, spread, emissive, box half-extents
	"dust":   [70, 9.0, 0.05, Color(0.95, 0.9, 0.8, 0.35), 0.02, 0.15, 180.0, 0.0, Vector3(13, 2.5, 13)],
	"embers": [90, 4.0, 0.07, Color(1.0, 0.55, 0.15, 0.95), 0.6, 0.4, 25.0, 3.0, Vector3(13, 0.5, 13)],
	"spores": [80, 10.0, 0.08, Color(0.7, 1.0, 0.55, 0.7), 0.04, 0.12, 180.0, 1.5, Vector3(13, 2.0, 13)],
	"leaves": [45, 8.0, 0.12, Color(0.75, 0.25, 0.18, 0.95), -0.35, 0.2, 40.0, 0.0, Vector3(13, 0.5, 13)],
	"drips":  [40, 1.2, 0.04, Color(0.6, 0.85, 1.0, 0.8), -9.0, 0.0, 0.0, 0.6, Vector3(13, 0.2, 13)],
	"sparks": [35, 0.6, 0.05, Color(0.75, 0.85, 1.0, 1.0), -2.0, 2.5, 180.0, 4.0, Vector3(12, 1.5, 12)],
	"snow":   [110, 9.0, 0.07, Color(0.95, 0.97, 1.0, 0.85), -0.5, 0.1, 30.0, 0.0, Vector3(13, 0.5, 13)],
	"glints": [55, 5.0, 0.06, Color(0.8, 0.9, 1.0, 0.9), 0.05, 0.1, 180.0, 2.5, Vector3(13, 2.0, 13)],
	"ash":    [70, 8.0, 0.08, Color(0.45, 0.43, 0.42, 0.8), -0.3, 0.1, 40.0, 0.0, Vector3(13, 0.5, 13)],
	"rain":   [260, 0.9, 0.035, Color(0.7, 0.8, 0.95, 0.55), -16.0, 4.0, 4.0, 0.0, Vector3(14, 0.3, 14)],     # round 44: weather
	"mist":   [40, 12.0, 2.6, Color(0.85, 0.88, 0.92, 0.18), 0.02, 0.08, 180.0, 0.0, Vector3(14, 1.2, 14)],
	"smoke":  [14, 6.0, 0.9, Color(0.55, 0.55, 0.58, 0.35), 0.35, 0.3, 15.0, 0.0, Vector3(0.15, 0.1, 0.15)],
}

var kind := ""
var tint := Color(1, 1, 1)
var _p: CPUParticles3D


func _ready() -> void:
	if kind == "" or not SPEC.has(kind) or DisplayServer.get_name() == "headless":
		set_process(false)
		return
	var s: Array = SPEC[kind]
	_p = CPUParticles3D.new()
	_p.amount = int(s[0])
	_p.lifetime = float(s[1])
	_p.preprocess = float(s[1])
	_p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_p.emission_box_extents = s[8]
	_p.gravity = Vector3(0, float(s[4]), 0)
	_p.initial_velocity_min = float(s[5]) * 0.5
	_p.initial_velocity_max = float(s[5])
	_p.direction = Vector3(0, 1, 0) if float(s[4]) >= 0.0 else Vector3(0, -1, 0)
	_p.spread = float(s[6])
	_p.scale_amount_min = 0.6
	_p.scale_amount_max = 1.4
	if kind == "leaves" or kind == "ash":
		_p.angular_velocity_min = -90.0
		_p.angular_velocity_max = 90.0
	if kind == "smoke":
		_p.scale_amount_min = 0.8
		_p.scale_amount_max = 2.2
	var q := QuadMesh.new()
	q.size = Vector2(float(s[2]), float(s[2]) * (3.0 if kind == "drips" else (14.0 if kind == "rain" else 1.0)))
	var m := StandardMaterial3D.new()
	var c: Color = s[3]
	if kind == "glints":
		c = Color(tint.r, tint.g, tint.b, c.a)
	m.albedo_color = c
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# round 37: soft round motes, and smoke that billows instead of squares
	var FXs := preload("res://scripts/fx/FX.gd")
	m.albedo_texture = FXs.puff_texture() if kind in ["smoke", "mist", "steam", "spores"] else FXs.soft_dot()
	if kind == "smoke":
		_p.angular_velocity_min = -25.0
		_p.angular_velocity_max = 25.0
		var sc := Curve.new()
		sc.add_point(Vector2(0.0, 0.4))
		sc.add_point(Vector2(1.0, 1.6))
		_p.scale_amount_curve = sc
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	if float(s[7]) > 0.0:
		m.emission_enabled = true
		m.emission = Color(c.r, c.g, c.b)
		m.emission_energy_multiplier = float(s[7])
	q.material = m
	_p.mesh = q
	# fade in and out over each mote's life
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.2, 0.8, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	_p.color_ramp = g
	add_child(_p)
	set_process(kind in FOLLOW_KINDS)


func _process(_delta: float) -> void:
	var player = get_tree().get_first_node_in_group("player")
	if player:
		var y := 2.0
		if kind in ["leaves", "snow", "ash", "drips"]:
			y = 5.5
		elif kind == "rain":
			y = 9.0
		elif kind == "mist":
			y = 1.2
		elif kind == "embers":
			y = 0.3
		global_position = Vector3(player.global_position.x, y, player.global_position.z)
