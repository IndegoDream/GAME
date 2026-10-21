extends StaticBody3D
## A treasure chest. Press E to open; the loot is defined per chest
## letter in the level file's "chests" section. Stays opened.

var level
var cell := Vector2i.ZERO
var loot := {}
var note := ""
var hidden := false          # "hidden": true -- only Spirit Sense can see it
var gear := 0                # round 32: a vault's chest holds real gear too
var essence := false         # ...and, deep down, a drop of old blood
var _key := ""
var _model: Node3D
var _shape: CollisionShape3D
var _shown := true
var _check_t := 0.0
var _anim: AnimationPlayer


func setup(lvl, args: Dictionary) -> void:
	level = lvl
	cell = args.get("cell", Vector2i.ZERO)
	loot = args.get("loot", {})
	note = str(args.get("note", ""))
	hidden = bool(args.get("hidden", false))
	gear = int(args.get("gear", 0))
	essence = bool(args.get("essence", false))
	_key = Game.flag_key(level.level_id, cell, "chest")


func _ready() -> void:
	_model = preload("res://scripts/core/Art.gd").make("mini-dungeon/chest.glb")
	_model.scale = Vector3.ONE * 2.2
	add_child(_model)
	_anim = _find_anim(_model)
	_shape = CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.1, 1.0, 1.1)
	_shape.shape = box
	_shape.position = Vector3(0, 0.5, 0)
	add_child(_shape)

	var open_neighbours: int = 0
	if level != null:
		for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = cell + dir
			if level.has_method("is_walkable_char") and level.has_method("char_at"):
				if level.is_walkable_char(level.char_at(n)):
					open_neighbours += 1

	if open_neighbours > 2:
		if level != null and level.astar != null:
			level.astar.set_point_solid(cell, true)
	else:
		_shape.disabled = true

	if Game.has_flag(_key):
		_show_open()
	else:
		add_to_group("interactable")
		add_to_group("discoverable")
		var sparkle := OmniLight3D.new()
		sparkle.light_color = Color(1.0, 0.85, 0.4)
		sparkle.omni_range = 3.5
		sparkle.light_energy = 0.9
		sparkle.position = Vector3(0, 1.2, 0)
		sparkle.name = "Sparkle"
		add_child(sparkle)
	if hidden and not Game.has_flag(_key):
		_shown = true
		_set_shown(Game.can_sense_hidden(), false)


func _process(delta: float) -> void:
	if not hidden or Game.has_flag(_key):
		return
	_check_t -= delta
	if _check_t <= 0.0:
		_check_t = 0.5
		_set_shown(Game.can_sense_hidden(), true)


func _set_shown(show: bool, announce: bool) -> void:
	if show == _shown:
		return
	_shown = show
	_model.visible = show
	_shape.disabled = not show
	var s = get_node_or_null("Sparkle")
	if s:
		s.visible = show
	if show:
		add_to_group("interactable")
		add_to_group("discoverable")
		if announce:
			Game.message.emit("Your spirit sense brushes something that wasn't there a moment ago.")
		Game.log_event("hidden_revealed", {"what": "chest", "cell": [cell.x, cell.y]})
	else:
		remove_from_group("interactable")
		remove_from_group("discoverable")


func prompt() -> String:
	return "E: Open the chest"


func interact(_player) -> void:
	remove_from_group("interactable")
	remove_from_group("discoverable")
	Game.set_flag(_key)
	Game.log_event("chest", {"cell": [cell.x, cell.y]})
	Game.guild_event("chest")
	Game.note_place("Opened a chest%s" % (" only spirit sense could see" if hidden else ""))
	if note != "":
		Game.message.emit(note)
	if Game.sys("lore") and randf() < float(Game.sys("lore").data.get("chest_chance", 0.4)):
		var w: String = Game.sys("lore").framed("chest")          # round 42: sometimes a note
		if w != "":
			for ln in w.split("\n"):
				Game.message.emit(ln)
	Game.roll_loot(loot)
	for i in gear:
		Game.drop_gear(int(level.def.get("depth", Game.depth)) if level else Game.depth, 1)
	if essence and Game.blood_awake():
		var ids: Array = Game.blood_ids()
		var bid: String = Game.blood_dominant() if Game.blood_dominant() != "" and randf() < 0.5 else str(ids[randi() % ids.size()])
		Game.add_item("essence_" + bid, 1)
	Game.sfx("chest", 0.9)
	Game.sfx("coins", 0.7)
	Game.add_qi(5.0)
	if _anim and _anim.has_animation("open"):
		_anim.play("open")
	_lift_lid(true)
	var s = get_node_or_null("Sparkle")
	if s:
		s.queue_free()


func _show_open() -> void:
	if _anim and _anim.has_animation("open"):
		_anim.play("open")
		_anim.seek(_anim.current_animation_length, true)
	_lift_lid(false)


func _lift_lid(animate: bool) -> void:
	## (the photo-scanned chest, Art.gd: its lid hinges at the back)
	var lid := _model.find_child("treasure_chest_lid", true, false) as Node3D
	if lid == null:
		return
	var lock := _model.find_child("treasure_chest_lock", true, false) as Node3D
	if lock:
		lock.visible = false
	if animate and is_inside_tree():
		create_tween().tween_property(lid, "rotation:x", -1.75, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		lid.rotation.x = -1.75


func _find_anim(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var a := _find_anim(c)
		if a:
			return a
	return null
