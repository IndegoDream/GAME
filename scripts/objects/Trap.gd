extends Area3D
## Spike trap. Round 46 (Robert, 2026-10-04: "be more subtle with traps and
## secrets"): past the first floor a trap is HIDDEN -- a pressure plate under
## the same stone as the rest of the floor, with only a small tell (a few
## loose pebbles, a darker stain) for those who look. Linger near it (stand
## still; Survival helps; sprinting, you'll never see it) and you spot it;
## Spirit Sense finds it from further off. Step on one you haven't spotted
## and it clicks: you have a breath to roll clear before the spikes come up.
## Spotted or sprung, it's a known trap from then on: the spikes cycle down /
## up and anyone standing on the plate when they rise is hurt -- watch the
## rhythm and walk through. Beasts of the deep know where their traps are and
## don't set off hidden ones. data/subtlety.json "trap".

const DOWN_TIME := 1.8
const UP_TIME := 1.0
const DAMAGE := 14

var level
var cell := Vector2i.ZERO
var _key := ""
var hidden := false
var notice := 0.0
var _spring_t := -1.0
var _model: Node3D
var _tell: Node3D
var _anim: AnimationPlayer
var _up := false
var _t := 0.0
var _hit_this_cycle := {}


func setup(lvl, args: Dictionary) -> void:
	level = lvl
	cell = args.get("cell", Vector2i.ZERO)
	_t = float((cell.x * 7 + cell.y * 3) % 10) / 10.0 * DOWN_TIME
	if level and level.get("level_id") != null:
		_key = Game.flag_key(str(level.level_id), cell, "trap_seen")


func _depth() -> int:
	return int(level.def.get("depth", Game.depth)) if level and level.get("def") is Dictionary else int(Game.depth)


func damage() -> int:
	return int(round(DAMAGE * (1.0 + float(Game.subtlety("trap").get("damage_per_depth", 0.15)) * maxi(_depth() - 1, 0))))


func _ready() -> void:
	add_to_group("trap")
	_model = load("res://assets/kenney/mini-dungeon/trap.glb").instantiate()
	_model.scale = Vector3.ONE * 2.0
	add_child(_model)
	_anim = _find_anim(_model)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.6, 1.2, 1.6)
	shape.shape = box
	shape.position = Vector3(0, 0.6, 0)
	add_child(shape)
	monitoring = true
	if _anim and _anim.has_animation("hide"):
		_anim.play("hide")
		_anim.seek(_anim.current_animation_length, true)
	hidden = _depth() > int(Game.subtlety("trap").get("shown_until_depth", 1)) and (_key == "" or not Game.has_flag(_key))
	if hidden:
		_model.visible = false          # the floor shows through: it looks like any other stone
		_add_tell()
		add_to_group("discoverable")


func _add_tell() -> void:
	## the only signs: a few loose pebbles at the edge, a faint darker stain
	_tell = Node3D.new()
	add_child(_tell)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(cell) + "tell")
	var stain := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(1.3, 1.3)
	stain.mesh = pm
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.08, 0.06, 0.05, 0.16)
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	stain.material_override = sm
	stain.position = Vector3(0, 0.03, 0)
	_tell.add_child(stain)
	for i in 3:
		var pb := MeshInstance3D.new()
		var sp := SphereMesh.new()
		sp.radius = rng.randf_range(0.035, 0.06)
		sp.height = sp.radius * 1.4
		pb.mesh = sp
		var pmat := StandardMaterial3D.new()
		pmat.albedo_color = Color(0.42, 0.4, 0.37)
		pb.material_override = pmat
		pb.position = Vector3(rng.randf_range(-0.7, 0.7), 0.04, rng.randf_range(-0.7, 0.7))
		_tell.add_child(pb)


func _player():
	return get_tree().get_first_node_in_group("player") if is_inside_tree() else null


func _physics_process(delta: float) -> void:
	if hidden:
		_watch(delta)
		return
	_t += delta
	if not _up and _t >= DOWN_TIME:
		_up = true
		_t = 0.0
		_hit_this_cycle.clear()
		if _anim and _anim.has_animation("show"):
			_anim.play("show")
	elif _up and _t >= UP_TIME:
		_up = false
		_t = 0.0
		if _anim and _anim.has_animation("hide"):
			_anim.play("hide")
	if _up and _t > 0.1:
		for b in get_overlapping_bodies():
			if _hit_this_cycle.has(b):
				continue
			if b.has_method("take_damage"):
				_hit_this_cycle[b] = true
				_hurt(b)


func _hurt(b) -> void:
	if b.is_in_group("player"):
		# Survival: you learn a trap's tells -- it bites less, and every bite teaches
		b.take_damage(int(round(damage() * Game.survival_trap_mult())), "spikes")
		Game.add_skill_xp("survival", 4.0, "a trap's lesson")
	else:
		b.take_damage(damage(), "spikes")


func _watch(delta: float) -> void:
	## a hidden plate: noticed if you linger near it; sprung if you step on it
	if _spring_t >= 0.0:
		_spring_t -= delta
		if _spring_t < 0.0:
			_spring()
		return
	var p = _player()
	if p == null:
		return
	if get_overlapping_bodies().has(p):
		_spring_t = float(Game.subtlety("trap").get("spring_delay", 0.4))
		Game.sfx("creak", 0.9)
		Game.message.emit("Click -- the stone shifts under your foot!")
		return
	var d := Vector2(p.global_position.x - global_position.x, p.global_position.z - global_position.z).length()
	if d <= float(Game.subtlety("trap").get("reach", 3.2)):
		notice += Game.notice_rate("trap", p) * delta
		if notice >= 1.0:
			reveal("eye")


func _spring() -> void:
	reveal("sprung")
	_up = true
	_t = 0.0
	_hit_this_cycle.clear()
	if _anim and _anim.has_animation("show"):
		_anim.play("show")
	Game.sfx("hit_metal", 0.8)
	for b in get_overlapping_bodies():
		if b.has_method("take_damage") and b.is_in_group("player"):
			_hit_this_cycle[b] = true
			_hurt(b)


func sensed() -> void:
	if hidden:
		reveal("sense")


func reveal(how: String) -> void:
	## spotted (or sprung): a known trap from now on
	if not hidden:
		return
	hidden = false
	_model.visible = true
	if _tell:
		_tell.queue_free()
		_tell = null
	remove_from_group("discoverable")
	if _key != "":
		Game.set_flag(_key)
	_t = 0.0
	_up = false
	match how:
		"eye":
			Game.message.emit("You spot it just in time: a pressure plate set into the floor. A trap.")
			Game.add_skill_xp("survival", 3.0, "a trap spotted")
			Game.log_event("trap_spotted", {"cell": [cell.x, cell.y]})
		"sense":
			Game.message.emit("Your spirit sense finds a pressure plate hidden in the floor.")
			Game.log_event("trap_spotted", {"cell": [cell.x, cell.y], "how": "sense"})
		_:
			Game.log_event("trap_sprung", {"cell": [cell.x, cell.y]})


func _find_anim(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var a := _find_anim(c)
		if a:
			return a
	return null
