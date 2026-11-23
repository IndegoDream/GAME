extends SceneTree
## marketing shots from the real game: godot --path . --resolution 1920x1080 --script res://tools/promo_shot.gd -- <out_dir> <scenes comma list: village,walk,fight1,fight2,boss>
var G
var out := ""
var m
func _wait(n: int) -> void:
	for i in n:
		await process_frame
func _shot(name: String) -> void:
	root.get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("shot ", name, " level=", G.current_level)
func _player():
	return get_first_node_in_group("player")
func _nearest_enemy(from: Vector3, want_boss := false):
	var best = null
	var bd := 1e9
	for e in get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or e.dead:
			continue
		if want_boss and not bool(e.stats.get("boss", false)):
			continue
		var d: float = e.global_position.distance_to(from)
		if d < bd:
			bd = d
			best = e
	return best
func _face(pl, target: Vector3) -> void:
	var d: Vector3 = target - pl.global_position
	pl._yaw = atan2(-d.x, -d.z)
	pl._apply_cam()
func _go(level: String, tag: String, frames: int) -> void:
	G.go_to(level, tag)
	await _wait(frames)
	m = root.get_node("Main")
func _fight(prefix: String, shots: int, boss: bool) -> void:
	var pl = _player()
	var foe = _nearest_enemy(pl.global_position, boss)
	if foe == null:
		print("no foe on ", G.current_level)
		return
	var dirv: Vector3 = (foe.global_position - pl.global_position)
	dirv.y = 0
	pl.global_position = foe.global_position - dirv.normalized() * 3.2 + Vector3(0, 0.3, 0)
	_face(pl, foe.global_position)
	await _wait(25)
	for i in shots:
		_face(pl, foe.global_position if is_instance_valid(foe) else pl.global_position + Vector3(0, 0, -5))
		if i % 2 == 0:
			pl._start_blow(false, 1.0)
		else:
			pl.cast_art("qi_burst")
		await _wait(14)
		_shot("%s_%d" % [prefix, i + 1])
		await _wait(8)

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	out = a[0]
	var which: Array = (a[1] as String).split(",") if a.size() > 1 else ["village", "walk", "fight1"]
	DirAccess.make_dir_recursive_absolute(out)
	G = root.get_node("Game")
	G.save_path = "user://promo_save.json"
	G.save_base = "user://promo_slots"
	G.playlog_path = "user://promo_playlog.jsonl"
	root.add_child(load("res://Main.tscn").instantiate())
	await _wait(200)
	m = root.get_node("Main")
	var hud = get_first_node_in_group("hud")
	if hud != null and hud._title != null:
		hud._title.visible = false
	var pl = _player()
	G.hp = G.max_hp()
	print("start level ", G.current_level, " player ", pl)
	if "village" in which:
		_shot("village_a")
		pl.set_camera_mode("shoulder")
		await _wait(20)
		_shot("village_b")
		pl.set_camera_mode("far")
		await _wait(10)
	if "walk" in which:
		Input.action_press("move_forward")
		for i in 6:
			await _wait(22)
			_shot("walk_%d" % (i + 1))
		Input.action_release("move_forward")
	if "fight1" in which:
		await _go("floor3", "<", 260)
		await _fight("fight_floor3", 4, false)
	if "fight2" in which:
		await _go("floor12", "<", 260)
		await _fight("fight_floor12", 4, false)
	if "boss" in which:
		await _go("floor8", "<", 260)
		await _fight("boss_floor8", 4, true)
	quit()
