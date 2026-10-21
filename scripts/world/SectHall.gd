extends Node3D
## A sect's hall-front in the valley (round 24, Valley.gd): a stone dais
## under the hall with an incense burner and the sect's name, two training
## posts in the yard, and the sect's ENTRY TRIAL, run here when the elder
## sets it (NPC.gd role "sect"):
##
##   combat     foes of the valley rise in the yard; beat them in time
##   endurance  hold the yard while they keep coming
##   stillness  sit on the dais without rising until the incense burns down
##
## E on the dais: sit in the hall -- 2.5x for a disciple of this sect,
## 1.25x for a guest (Game.SECT_HALL_AID / SECT_GUEST_AID).

var level
var cell := Vector2i.ZERO
var sid := ""
var element := "earth"
var trial := {}          # {"kind", "need", "seconds", "left", "kills"} while a trial runs
var _foes := []
var _spawn_t := 0.0
var _sat := 0.0
var _headless := false


func setup(lvl, args: Dictionary) -> void:
	level = lvl
	cell = args.get("cell", Vector2i.ZERO)
	sid = str(args.get("id", ""))
	element = str(args.get("element", "earth"))


func _ready() -> void:
	_headless = DisplayServer.get_name() == "headless"
	add_to_group("sect_hall")
	add_to_group("interactable")
	var s: Dictionary = Game.sect_def(sid)
	var dais := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(6.0, 0.35, 3.2)
	dais.mesh = bm
	dais.position.y = 0.17
	if not _headless:
		dais.material_override = preload("res://scripts/world/Look.gd").surface(["castle_brick_01", [0.85, 0.82, 0.78], 1.2])
	add_child(dais)
	var burner := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.35
	cm.bottom_radius = 0.25
	cm.height = 0.5
	burner.mesh = cm
	burner.position = Vector3(0, 0.6, 0.6)
	if not _headless:
		var bronze := StandardMaterial3D.new()
		bronze.albedo_color = Color(0.45, 0.33, 0.18)
		bronze.metallic = 0.7
		bronze.roughness = 0.4
		burner.material_override = bronze
		var smoke := CPUParticles3D.new()
		smoke.amount = 20
		smoke.lifetime = 4.0
		smoke.position = Vector3(0, 0.95, 0.6)
		smoke.direction = Vector3(0, 1, 0)
		smoke.spread = 10.0
		smoke.initial_velocity_min = 0.2
		smoke.initial_velocity_max = 0.35
		smoke.gravity = Vector3(0.02, 0.03, 0)
		var sp := SphereMesh.new()
		sp.radius = 0.06
		sp.height = 0.12
		smoke.mesh = sp
		var smm := StandardMaterial3D.new()
		smm.albedo_color = Color(0.85, 0.85, 0.9, 0.22)
		smm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		smm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		smoke.material_override = smm
		add_child(smoke)
		var glow := OmniLight3D.new()
		glow.light_color = preload("res://scripts/world/TowerTrial.gd").EL_COLOR.get(element, Color(1, 0.8, 0.5))
		glow.light_energy = 1.0
		glow.omni_range = 6.0
		glow.position = Vector3(0, 1.4, 0.6)
		add_child(glow)
	add_child(burner)
	var lbl := Label3D.new()
	lbl.text = "%s\n(%s)" % [s.get("name", I18n.t("A sect")), element]
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.pixel_size = 0.01
	lbl.font_size = 40
	lbl.outline_size = 10
	lbl.modulate = Color(1.0, 0.9, 0.65)
	lbl.position = Vector3(0, 3.6, 0)
	add_child(lbl)
	# training posts in the yard (real practice, Game.post_drill)
	for side in [-1, 1]:
		var post := StaticBody3D.new()
		post.add_to_group("training_post")
		post.position = Vector3(side * 12.0, 0, 9.0)
		var pm := MeshInstance3D.new()
		var pb := BoxMesh.new()
		pb.size = Vector3(0.26, 1.9, 0.26)
		pm.mesh = pb
		pm.position.y = 0.95
		post.add_child(pm)
		var arm := MeshInstance3D.new()
		var ab := BoxMesh.new()
		ab.size = Vector3(1.1, 0.14, 0.14)
		arm.mesh = ab
		arm.position.y = 1.3
		post.add_child(arm)
		var col := CollisionShape3D.new()
		var cs := BoxShape3D.new()
		cs.size = Vector3(0.3, 2.0, 0.3)
		col.shape = cs
		col.position.y = 1.0
		post.add_child(col)
		if not _headless:
			var wood: Material = preload("res://scripts/world/Look.gd").surface(["old_wood_floor", [0.72, 0.56, 0.4], 1.0])
			pm.material_override = wood
			arm.material_override = wood
		add_child(post)


# ---- sitting in the hall ------------------------------------------------------------

func prompt() -> String:
	if not trial.is_empty():
		match str(trial["kind"]):
			"stillness":
				return I18n.t("The trial: sit still on the dais -- %d s to go") % int(ceil(float(trial["seconds"]) - _sat))
			"combat":
				return I18n.t("The trial: %d of them left, %d s") % [_alive(), int(ceil(float(trial["left"])))]
			"endurance":
				return I18n.t("The trial: hold the yard -- %d s") % int(ceil(float(trial["left"])))
	var s: Dictionary = Game.sect_def(sid)
	if Game.in_sect(sid):
		return I18n.t("E: Sit in the hall of the %s (x%.1f)") % [s.get("name", ""), Game.SECT_HALL_AID]
	return I18n.t("E: Sit at the back of the hall, as a guest (x%.2f)") % Game.SECT_GUEST_AID


func interact(player) -> void:
	if player and player.has_method("start_meditating"):
		player.start_meditating(false)
		Game.sit_aid = Game.SECT_HALL_AID if Game.in_sect(sid) else Game.SECT_GUEST_AID
		Game.message.emit("The incense is thick and the hall is quiet. (meditation x%.2f)" % Game.sit_aid)


# ---- the entry trial ---------------------------------------------------------------

func start_trial() -> String:
	var why := Game.sect_join_check(sid)
	if why != "":
		return why
	if not trial.is_empty():
		return I18n.t("The trial is already under way.")
	var t: Dictionary = Game.sect_def(sid).get("trial", {"kind": "combat", "need": 4, "seconds": 75})
	trial = {"kind": str(t.get("kind", "combat")), "need": int(t.get("need", 4)), "seconds": float(t.get("seconds", 60)),
		"left": float(t.get("seconds", 60))}
	_sat = 0.0
	_spawn_t = 0.0
	Game.log_event("sect_trial_start", {"sect": sid, "kind": trial["kind"]})      # (round 57: standing comes from PASSING, not starting -- see _end)
	match str(trial["kind"]):
		"combat":
			for i in int(trial["need"]):
				_spawn(TAU * i / float(trial["need"]))
			return I18n.t("TRIAL: %d of them, %d seconds. Begin.") % [int(trial["need"]), int(trial["seconds"])]
		"endurance":
			return I18n.t("TRIAL: hold the yard for %d seconds. Don't fall.") % int(trial["seconds"])
		"stillness":
			return I18n.t("TRIAL: sit on the dais (press E there) and don't rise until the incense is gone -- %d seconds.") % int(trial["seconds"])
	return ""


func _spawn(angle: float) -> void:
	var pool: Array = Game.tower_enemy_pool(1)
	if pool.is_empty() or level == null:
		return
	var at := global_position + Vector3(cos(angle) * 8.0, 0, 6.0 + sin(angle) * 4.0)
	var foe = level._spawn_script("res://scripts/actors/Enemy.gd", at, {"type": str(pool[randi() % pool.size()]), "cell": level.world_to_cell(at)})
	if foe:
		foe.set_meta("sect_trial", sid)
		_foes.append(foe)


func _alive() -> int:
	var k := 0
	for f in _foes:
		if is_instance_valid(f) and not f._dead:
			k += 1
	return k


func _end(passed: bool, why: String) -> void:
	for f in _foes:
		if is_instance_valid(f) and not f._dead:
			f.queue_free()
	_foes = []
	var kind := str(trial.get("kind", ""))
	trial = {}
	if passed:
		Game.log_event("sect_trial", {"sect": sid, "kind": kind})
		Game.message.emit(Game.join_sect(sid))
	else:
		Game.message.emit(why)


func _process(delta: float) -> void:
	if trial.is_empty():
		return
	var pl = get_tree().get_first_node_in_group("player")
	if pl and pl.dead:
		_end(false, "You fall in the trial. The elder will let you try again.")
		return
	trial["left"] = float(trial["left"]) - delta
	match str(trial["kind"]):
		"combat":
			if _alive() == 0:
				_end(true, "")
			elif float(trial["left"]) <= 0.0:
				_end(false, "Too slow. The disciples drag the last of them off. Try again when you're ready.")
		"endurance":
			_spawn_t -= delta
			if _spawn_t <= 0.0 and _alive() < 3:
				_spawn_t = 7.0
				_spawn(randf() * TAU)
			if float(trial["left"]) <= 0.0:
				_end(true, "")
		"stillness":
			var here: bool = pl != null and pl.meditating and (pl.global_position - global_position).length() < 5.0
			if here:
				_sat += delta
				if _sat >= float(trial["seconds"]):
					_end(true, "")
			elif _sat > 1.0:
				_end(false, "You rose before the incense was gone. The elder says nothing, which is worse. (Try again.)")
			elif float(trial["left"]) < -120.0:
				_end(false, "You never sat. The trial lapses.")
