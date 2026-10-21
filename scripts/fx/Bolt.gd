extends Node3D
## A thrown stone, a spat glob, a bolt of qi (round 28): what a ranged or
## mending foe sends at you. It flies straight at where you WERE, so you
## can step aside; it stops at walls; and it reaches you through
## Player.take_damage with its thrower as the source, so your guard blocks
## it and a well-timed parry turns it.

var owner_foe: Node
var dir := Vector3.FORWARD
var speed := 13.0
var damage := 5
var color := Color(1.0, 0.75, 0.35)
var life := 2.5
var _level


func setup(foe: Node, from: Vector3, to: Vector3, spd: float, dmg: int, c: Color) -> void:
	owner_foe = foe
	position = from
	var d := to - from
	dir = d.normalized() if d.length() > 0.01 else Vector3.FORWARD
	speed = spd
	damage = dmg
	color = c
	_level = foe.get("level") if foe != null else null


func _ready() -> void:
	add_to_group("bolt")
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.13
	sm.height = 0.26
	mi.mesh = sm
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 3.0
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = m
	add_child(mi)
	if DisplayServer.get_name() != "headless":
		var l := OmniLight3D.new()
		l.light_color = color
		l.omni_range = 2.5
		l.light_energy = 1.2
		add_child(l)
	preload("res://scripts/fx/FX.gd").trail(self, color)          # a glowing tail behind it (round 29)


func _physics_process(delta: float) -> void:
	life -= delta
	if life <= 0.0:
		queue_free()
		return
	position += dir * speed * delta
	if _level != null and is_instance_valid(_level) and _level.has_method("world_to_cell"):
		var c: Vector2i = _level.world_to_cell(global_position)
		if _level._is_wallish(c) or _level.char_at(c) == " ":
			preload("res://scripts/fx/FX.gd").hit(global_position, color)
			queue_free()            # it hits the wall
			return
	var player = get_tree().get_first_node_in_group("player")
	if player == null or player.dead:
		return
	if (player.global_position + Vector3(0, 1.0, 0)).distance_to(global_position) < 0.75:
		if owner_foe != null and is_instance_valid(owner_foe) and owner_foe.has_method("deal"):
			owner_foe.deal(player, damage)
		else:
			player.take_damage(damage, "a bolt", null)
		queue_free()
