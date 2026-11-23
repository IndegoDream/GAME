extends StaticBody3D
## A secret wall ('S' on the map). Round 46 (Robert, 2026-10-04: "be more
## subtle with traps and secrets"): it looks exactly like every other wall
## on the floor and gives you nothing to press -- until you NOTICE it.
## Linger by it (standing still is best; Survival helps; sprinting past,
## you'll never feel it) and you notice the faint draft through a crack;
## Spirit Sense notices it from further off. Only then can you press the
## loose stone (E) and grind it open. The draft is there to be seen, if you
## look: a thin drift of dust from the seam. Once found, it stays open.
## data/subtlety.json "secret".

var level
var cell := Vector2i.ZERO
var _key := ""
var _model: Node3D
var _opening := false
var noticed := false
var notice := 0.0          # (0..1) how close you are to noticing it
var _draft: CPUParticles3D


func setup(lvl, args: Dictionary) -> void:
	level = lvl
	cell = args.get("cell", Vector2i.ZERO)
	_key = Game.flag_key(level.level_id, cell, "secret")


func _ready() -> void:
	if Game.has_flag(_key):
		_open_now()
		return
	level.astar.set_point_solid(cell, true)
	if level.is_town() or not level.has_method("wall_block"):
		_model = load("res://assets/kenney/nature-kit/cliff_block_rock.glb").instantiate()
		_model.scale = Vector3.ONE * 2.0
	else:
		_model = level.wall_block()        # the same stone as every other wall on this floor
	add_child(_model)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.0, 4.0, 2.0)
	shape.shape = box
	shape.position = Vector3(0, 2.0, 0)
	add_child(shape)
	add_to_group("discoverable")
	add_to_group("secret_wall")
	noticed = Game.has_flag(_key + ":noticed")
	if noticed:
		add_to_group("interactable")
	elif bool(Game.subtlety("secret").get("draft", true)):
		_add_draft()


func _add_draft() -> void:
	## the tell: a thin drift of dust from the seam, on the side you can stand
	if DisplayServer.get_name() == "headless":
		return
	var out := Vector3.ZERO
	for d in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
		if level.is_walkable_char(level.char_at(cell + d)):
			out = Vector3(d.x, 0, d.y)
			break
	if out == Vector3.ZERO:
		return
	_draft = CPUParticles3D.new()
	_draft.amount = 6
	_draft.lifetime = 3.5
	_draft.preprocess = 3.5
	_draft.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_draft.emission_box_extents = Vector3(0.5, 0.6, 0.5) * Vector3(1.0 - absf(out.x), 1.0, 1.0 - absf(out.z)) + Vector3(0.02, 0, 0.02)
	_draft.position = out * 1.02 + Vector3(0, 0.9, 0)
	_draft.direction = out
	_draft.spread = 12.0
	_draft.gravity = Vector3.ZERO
	_draft.initial_velocity_min = 0.08
	_draft.initial_velocity_max = 0.18
	var q := QuadMesh.new()
	q.size = Vector2(0.035, 0.035)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.85, 0.82, 0.75, 0.35)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	q.material = m
	_draft.mesh = q
	add_child(_draft)


func _process(delta: float) -> void:
	if noticed or _opening or Game.has_flag(_key):
		return
	var p = get_tree().get_first_node_in_group("player")
	if p == null:
		return
	var d := Vector2(p.global_position.x - global_position.x, p.global_position.z - global_position.z).length()
	if d > float(Game.subtlety("secret").get("reach", 2.6)):
		return
	notice += Game.notice_rate("secret", p) * delta
	if notice >= 1.0:
		_notice_it("draft")


func sensed() -> void:
	## Spirit Sense: you feel the hollow behind the stone
	if not noticed and not Game.has_flag(_key):
		_notice_it("sense")


func _notice_it(how: String) -> void:
	noticed = true
	Game.set_flag(_key + ":noticed")
	add_to_group("interactable")
	Game.add_skill_xp("survival", 3.0, "a hidden way noticed")
	Game.log_event("secret_noticed", {"cell": [cell.x, cell.y], "how": how})
	Game.message.emit("Your spirit sense catches a hollow behind the wall." if how == "sense" else "A faint draft stirs from a crack in the wall. One stone sits wrong.")
	_shimmer()


func _shimmer() -> void:
	## a brief, faint glow along the loose stone -- then it's just a wall again
	var g := OmniLight3D.new()
	g.light_color = Color(0.75, 0.9, 1.0)
	g.omni_range = 2.5
	g.light_energy = 0.9
	g.position = Vector3(0, 1.2, 0)
	add_child(g)
	var tw := create_tween()
	tw.tween_property(g, "light_energy", 0.0, 2.5)
	tw.tween_callback(g.queue_free)


func prompt() -> String:
	return "E: Press the stone where the draft comes through"


func interact(_player) -> void:
	if _opening:
		return
	_opening = true
	remove_from_group("interactable")
	remove_from_group("discoverable")
	Game.set_flag(_key)
	Game.log_event("secret", {"cell": [cell.x, cell.y]})
	Game.note_place("Found a secret wall")
	Game.guild_event("secret")
	Game.sfx("door", 0.8)
	Game.message.emit("A hidden passage grinds open!")
	Game.add_qi(15.0, "found a secret")
	if _draft:
		_draft.emitting = false
	if Game.sys("lore"):
		var w: String = Game.sys("lore").framed("secret")         # round 42: whoever hid it left a word
		var hud = get_tree().get_first_node_in_group("hud")
		if w != "" and hud:
			hud.open_dialog("A hidden passage", w, [["Go on", hud.close_dialog]])
	var tw := create_tween()
	tw.tween_property(_model, "position:y", -2.4, 1.2)
	tw.tween_callback(_open_now)


func _open_now() -> void:
	level.open_cell(cell)
	for c in get_children():
		if c is CollisionShape3D:
			c.disabled = true
	if _model:
		_model.visible = false
	if _draft:
		_draft.queue_free()
		_draft = null
	# a floor tile where the wall used to be
	if level.has_method("floor_patch"):
		add_child(level.floor_patch())
	else:
		var f = load("res://assets/kenney/mini-dungeon/floor.glb").instantiate()
		f.scale = Vector3.ONE * 2.0
		add_child(f)
