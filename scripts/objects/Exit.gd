extends Area3D
## Stairs / a doorway to another level. Walk onto it to travel.
## Defined in a level file's "exits" section:
##   ">": {"to": "floor2", "arrive": "<", "label": "Down to the Crypt"}
## "arrive" is the character on the OTHER level you'll appear next to.

var level
var cell := Vector2i.ZERO
var target := ""
var arrive := "P"
var label := ""
var down := true
var style := "stairs"        # "stairs" | "road" (a signpost on the way out) | "door" (a tower's own door) | "hatch" | "pad" (round 123) | "portal" (round 125: the Gate)
var needs := ""              # round 123: an item you must carry for this way to open (the Skyhook keycard wakes the launch pads)
var _armed := false


func setup(lvl, args: Dictionary) -> void:
	level = lvl
	cell = args.get("cell", Vector2i.ZERO)
	target = str(args.get("to", ""))
	arrive = str(args.get("arrive", "P"))
	label = str(args.get("label", ""))
	down = bool(args.get("down", true))
	style = str(args.get("style", "stairs"))
	needs = str(args.get("needs", ""))


func _unlocked() -> bool:
	return needs == "" or int(Game.inventory.get(needs, 0)) > 0 or Game.tester_unlocked()


func _tech_model(model: Node3D) -> void:
	## round 123: a hatch in the ground, or a launch pad -- drawn in code
	var open := _unlocked()
	var col := Color(0.45, 0.8, 1.0) if open else Color(1.0, 0.35, 0.3)
	if style == "portal":
		col = Color(0.75, 0.5, 1.0)
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.3, 0.32, 0.36)
	metal.metallic = 0.8
	metal.roughness = 0.45
	var glow := StandardMaterial3D.new()
	glow.albedo_color = col
	glow.emission_enabled = true
	glow.emission = col
	glow.emission_energy_multiplier = 1.1
	var base := MeshInstance3D.new()
	var bc := CylinderMesh.new()
	bc.top_radius = 1.5 if (style == "pad" or style == "portal") else 1.1
	bc.bottom_radius = bc.top_radius + 0.1
	bc.height = 0.16
	base.mesh = bc
	base.material_override = metal
	base.position.y = 0.08
	model.add_child(base)
	var ring := MeshInstance3D.new()
	var rc := TorusMesh.new()
	rc.outer_radius = bc.top_radius - 0.1
	rc.inner_radius = bc.top_radius - 0.2
	ring.mesh = rc
	ring.material_override = glow
	ring.position.y = 0.17
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	model.add_child(ring)
	var core := MeshInstance3D.new()
	var cc := CylinderMesh.new()
	cc.top_radius = bc.top_radius - 0.25
	cc.bottom_radius = cc.top_radius
	cc.height = 0.03
	core.mesh = cc
	var cm := StandardMaterial3D.new()
	cm.albedo_color = Color(0.05, 0.06, 0.08)
	cm.metallic = 0.6
	cm.roughness = 0.5
	core.material_override = cm
	core.position.y = 0.17
	model.add_child(core)
	if style == "hatch":
		var shaft := MeshInstance3D.new()
		var sc := CylinderMesh.new()
		sc.top_radius = 0.9
		sc.bottom_radius = 0.9
		sc.height = 3.2
		shaft.mesh = sc
		var sm := StandardMaterial3D.new()
		sm.albedo_color = Color(col.r, col.g, col.b, 0.1)
		sm.emission_enabled = true
		sm.emission = col
		sm.emission_energy_multiplier = 0.6
		sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		sm.cull_mode = BaseMaterial3D.CULL_DISABLED
		shaft.material_override = sm
		shaft.position.y = 1.7
		shaft.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		model.add_child(shaft)


func _warm_stone(n: Node) -> void:
	## the stock stair model is a pale lilac: bring it to the warm stone of the walls
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi
		if m.mesh == null:
			continue
		for s in m.mesh.get_surface_count():
			var sm := m.get_active_material(s)
			if sm is StandardMaterial3D:
				var d: StandardMaterial3D = sm.duplicate()
				d.albedo_color = Color(d.albedo_color.r * 0.78, d.albedo_color.g * 0.7, d.albedo_color.b * 0.6)
				d.roughness = 0.9
				m.set_surface_override_material(s, d)


func _ready() -> void:
	var model: Node3D
	if style == "road":
		model = preload("res://scripts/core/Art.gd").make("nature-kit/sign.glb")
		model.scale = Vector3.ONE * 2.2
	elif style == "door":
		model = Node3D.new()
	elif style == "hatch" or style == "pad" or style == "portal":
		model = Node3D.new()
		if DisplayServer.get_name() != "headless":
			_tech_model(model)
	else:
		model = load("res://assets/kenney/mini-dungeon/stairs.glb").instantiate()
		model.scale = Vector3.ONE * 2.0
		_warm_stone(model)
	if down and style == "stairs":
		# sink the stairs so they read as going DOWN into the floor
		model.position.y = -1.6
		var hole := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(2.0, 2.0)
		hole.mesh = pm
		var dark := StandardMaterial3D.new()
		dark.albedo_color = Color(0.0, 0.0, 0.0)
		hole.material_override = dark
		hole.position.y = -1.7
		add_child(hole)
	add_child(model)
	var glow := OmniLight3D.new()
	glow.light_color = Color(0.55, 0.75, 1.0)
	glow.omni_range = 4.0
	glow.light_energy = 1.4
	glow.position = Vector3(0, 1.5, 0)
	add_child(glow)
	var sign := Label3D.new()
	sign.text = label if label != "" else ("Stairs to " + target)
	if needs != "" and not _unlocked():
		sign.text += "  (locked)"
	sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sign.pixel_size = 0.009
	sign.no_depth_test = true
	sign.position = Vector3(0, 2.6, 0)
	sign.font_size = 48
	sign.outline_size = 10
	sign.modulate = Color(0.85, 0.92, 1.0)
	add_child(sign)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.4, 2.0, 1.4)
	shape.shape = box
	shape.position = Vector3(0, 1.0, 0)
	add_child(shape)
	body_entered.connect(_on_body_entered)
	# don't fire on the frame you arrive
	get_tree().create_timer(1.0).timeout.connect(func(): _armed = true)


func _on_body_entered(body: Node) -> void:
	if not _armed or not body.is_in_group("player"):
		return
	if target == "":
		Game.message.emit("These stairs lead nowhere yet.")
		return
	if target.begins_with("online:") and not str(level.level_id).begins_with("online:"):
		_armed = false
		var hud0 = get_tree().get_first_node_in_group("hud")
		if hud0 and hud0.has_method("open_dialog") and not hud0.is_blocking():
			preload("res://scripts/net/OnlineMenu.gd").gate(hud0)            # round 125: sign in, name a hero, step through
		get_tree().create_timer(3.0).timeout.connect(func(): _armed = true)
		return
	if not _unlocked():
		Game.message.emit("The pad is dark. It wakes for %s -- there's one in the wreck of the Fallen Beacon." % Game.item_name(needs))
		_armed = false
		get_tree().create_timer(4.0).timeout.connect(func(): _armed = true)
		return
	if Game.lite_blocked(target):
		Game.message.emit(Game.lite_message())
		_armed = false
		get_tree().create_timer(4.0).timeout.connect(func(): _armed = true)
		return
	if target.begins_with("floor") and level != null and not str(level.level_id).begins_with("floor") and Game.story_sealed() and not Game.tester_unlocked():
		# round 32: you sealed the shaft. Walking in twice breaks the seal.
		if Time.get_unix_time_from_system() - float(Game.flags.get("story:seal_warned", 0.0)) < 12.0:
			Game.break_seal()
		else:
			Game.flags["story:seal_warned"] = Time.get_unix_time_from_system()
			Game.message.emit("The shaft is sealed -- by your own hand. (Step in again to break the seal and go down.)")
			return
	if target == "ending":
		# round 33: the last floor's stairs lead into the Heart of the Deep -- the ending
		var why := Game.finale_check(get_tree())
		if why != "":
			Game.message.emit(why)
			_armed = false
			get_tree().create_timer(3.0).timeout.connect(func(): _armed = true)
			return
		_armed = false
		Game.finale()
		return
	# round 58: the stair below the free floors (the Steam demo, model "locked"),
	# an expansion's way that isn't yours, or the first trip down on the free
	# tier: Game.go_to refuses and the HUD opens the window -- before the gate's
	# own check, before a hollow could be rolled, and before "still being built"
	# (the demo leaves the deeper floors out)
	if Game.store and Game.store.travel_check(target) != "":
		_armed = false
		Game.go_to(target, arrive)
		get_tree().create_timer(3.0).timeout.connect(func(): _armed = true)
		return
	if not Game.level_exists(target):
		Game.message.emit("The way to '%s' is still being built." % target)
		return
	if Game.TowerGen.is_tower(target) and level != null and not Game.TowerGen.is_tower(level.level_id):
		var why := Game.tower_locked(str(Game.TowerGen.parse(target).get("id", "")))
		if why != "":
			Game.message.emit(why)
			_armed = false
			get_tree().create_timer(3.0).timeout.connect(func(): _armed = true)
			return
	# round 34: the gates -- the stairs down refuse until you've earned them
	var gate_why := Game.gate_check(target)
	if gate_why != "":
		Game.message.emit(gate_why)
		var hud = get_tree().get_first_node_in_group("hud")
		if hud and hud.has_method("open_dialog") and not hud.is_blocking():
			hud.open_dialog("The way to floor %d" % Game.floor_depth(target), gate_why, [["Not yet", hud.close_dialog]])
		Game.log_event("gate_refused", {"floor": Game.floor_depth(target)})
		_armed = false
		get_tree().create_timer(3.0).timeout.connect(func(): _armed = true)
		return
	Game.gate_pass(target)
	_armed = false
	# sometimes the way down opens onto a scavenger's hollow first
	# (round 57: once a day per stair -- the same hollow all day, so going up and
	# down again can't roll fresh chests and herbs forever: ScavengeGen.today)
	var hollow: String = Game.ScavengeGen.today(level.level_id, target) if down and arrive == "<" and not Game.ScavengeGen.is_scavenge(level.level_id) and target.begins_with("floor") else ""
	if hollow != "":
		Game.message.emit("The stairs bend somewhere they didn't before -- a hollow full of glitter and green.")
		Game.log_event("scavenge_found", {"from": level.level_id, "to": target})
		Game.go_to(hollow, "<")
		return
	Game.go_to(target, arrive)
