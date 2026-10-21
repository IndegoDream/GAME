extends Node3D
## Blast (round 60): a blow you can SEE coming -- a disc on the ground that
## fills from the middle out while it gathers, then lands. Used by a master's
## slam (it lands where you stood) and sweep (all round it), and by a
## Volatile elite's last breath. Step out of the disc and it hits nothing;
## roll through it as it lands and you slip it (a perfect dodge). Being in it
## when it lands hurts, and a guard can't hold it -- only a parry.

const FX := preload("res://scripts/fx/FX.gd")

var radius := 3.0
var fuse := 1.0
var dmg := 10
var color := Color(1.0, 0.3, 0.2)
var source := "a blast"
var owner_foe: Node = null         # who it's from (a parry staggers them; a perfect dodge opens them up)
var after := Callable()            # what happens as it lands (the master arrives, say)
var heavy_now := false             # (Player.take_damage: a heavy blow -- no blocking it)
var _t := 0.0
var _disc: MeshInstance3D
var _edge: MeshInstance3D
var _mat: StandardMaterial3D
var _emat: StandardMaterial3D
var landed := false
var hit_player := false


func setup(at: Vector3, r: float, secs: float, damage: int, c: Color, src: String, foe: Node = null) -> void:
	position = at
	radius = r
	fuse = maxf(secs, 0.05)
	dmg = damage
	color = c
	source = src
	owner_foe = foe


func _ready() -> void:
	add_to_group("blast")
	_mat = StandardMaterial3D.new()
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.albedo_color = Color(color.r, color.g, color.b, 0.0)
	_mat.no_depth_test = false
	_disc = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 1.0
	cm.bottom_radius = 1.0
	cm.height = 0.02
	cm.radial_segments = 48
	_disc.mesh = cm
	_disc.material_override = _mat
	_disc.position.y = 0.06
	_disc.scale = Vector3(0.05, 1, 0.05)
	add_child(_disc)
	# the edge shows the whole reach from the start
	_emat = _mat.duplicate()
	_emat.albedo_color = Color(color.r, color.g, color.b, 0.75)
	_edge = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.95
	tm.outer_radius = 1.0
	tm.rings = 48
	_edge.mesh = tm
	_edge.material_override = _emat
	_edge.position.y = 0.07
	_edge.scale = Vector3.ONE * radius
	add_child(_edge)
	if get_tree().root.get_node_or_null("Game"):
		Game.sfx_at("windup", global_position, 0.8)


func _process(delta: float) -> void:
	if landed:
		return
	_t += delta
	var k := clampf(_t / fuse, 0.0, 1.0)
	_disc.scale = Vector3(radius * k, 1, radius * k)
	_mat.albedo_color = Color(color.r, color.g, color.b, 0.18 + 0.32 * k)
	_emat.albedo_color = Color(color.r, color.g, color.b, 0.5 + 0.5 * absf(sin(_t * 12.0)))
	if _t >= fuse:
		land()


func land() -> void:
	if landed:
		return
	landed = true
	if after.is_valid():
		after.call()
	var pl = get_tree().get_first_node_in_group("player")
	if pl and is_instance_valid(pl) and not pl.dead:
		var d := Vector2(pl.global_position.x - global_position.x, pl.global_position.z - global_position.z).length()
		if d <= radius:
			heavy_now = true
			var before: int = Game.hp
			pl.take_damage(dmg, source, self)
			heavy_now = false
			hit_player = Game.hp < before
	FX.ring(global_position, color, radius, 0.35)
	FX.dust(global_position, clampf(radius * 0.6, 0.8, 2.5))
	Game.sfx_at("stamp", global_position, 1.0)
	queue_free()


# a parry (Player.take_damage) staggers whoever it came from; a perfect dodge opens them
func stagger(secs: float) -> void:
	if owner_foe and is_instance_valid(owner_foe) and owner_foe.has_method("stagger"):
		owner_foe.stagger(secs)


func expose(secs: float) -> void:
	if owner_foe and is_instance_valid(owner_foe) and owner_foe.has_method("expose"):
		owner_foe.expose(secs)
