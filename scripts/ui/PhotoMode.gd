extends CanvasLayer
## Round 165: photo mode. Robert, 2026-10-19: "Yes add them all" (photo mode + beast showcase).
## F9 (or Menu > Photo mode, or a beast's Photograph button): the HUD and touch controls step aside, the world holds still, and a
## free orbit camera takes over. Drag to look round, wheel / pinch / buttons to move in and out, W A S D to slide the view, Q / E for height,
## [ ] for the lens. Six looks (a colour grade and a soft vignette), a caption that names the beast or you (form, generation, mutation),
## Tab to turn to the next of you and your beasts. Enter or the Photo button saves a PNG (user://photos, and your Pictures folder when allowed).
## Same on phone and PC. Nothing is ever uploaded.

const SHADER := "shader_type canvas_item;\nuniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;\nuniform vec3 tint = vec3(1.0);\nuniform float sat = 1.0;\nuniform float contrast = 1.0;\nuniform float vignette = 0.0;\nvoid fragment() {\n\tvec3 c = textureLod(screen_tex, SCREEN_UV, 0.0).rgb;\n\tfloat l = dot(c, vec3(0.299, 0.587, 0.114));\n\tc = mix(vec3(l), c, sat);\n\tc = (c - 0.5) * contrast + 0.5;\n\tc *= tint;\n\tvec2 d = SCREEN_UV - 0.5;\n\tc *= 1.0 - vignette * dot(d, d) * 2.2;\n\tCOLOR = vec4(c, 1.0);\n}\n"
const FILTERS := [
	["Natural", Vector3(1, 1, 1), 1.0, 1.0, 0.0],
	["Warm", Vector3(1.08, 1.0, 0.88), 1.1, 1.05, 0.25],
	["Cool", Vector3(0.9, 0.98, 1.1), 1.0, 1.05, 0.25],
	["Vivid", Vector3(1, 1, 1), 1.45, 1.12, 0.15],
	["Mono", Vector3(1, 1, 1), 0.0, 1.15, 0.3],
	["Dusk", Vector3(1.0, 0.82, 0.95), 0.9, 1.1, 0.4],
]
const PAN_MAX := 10.0

var active := false
var player: Node3D = null
var cam: Camera3D = null
var prev_cam: Camera3D = null
var yaw := 0.0
var pitch := -0.2
var dist := 5.0
var fov := 62.0
var height := 0.0
var pan := Vector3.ZERO
var targets: Array = []        # [Node3D] you, then the beasts at your side
var ti := 0
var filter_i := 0
var caption_on := true
var ui_on := true
var shots := 0
var last_path := ""
var _hud = null
var _touch = null
var _grade: ColorRect
var _mat: ShaderMaterial
var _pad: Control
var _bar: Control
var _cap: Label
var _status: Label
var _hold := {}                # button name -> pressed
var _filter_btn: Button
var _focus_btn: Button
var _cap_btn: Button
var _built := false
var _show_btn: Button


func _ready() -> void:
	layer = 90
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("photo_mode")


func _build() -> void:
	if _built:
		return
	_built = true
	_grade = ColorRect.new()
	_grade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_grade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = SHADER
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	_grade.material = _mat
	add_child(_grade)
	_pad = Control.new()
	_pad.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pad.mouse_filter = Control.MOUSE_FILTER_STOP
	_pad.gui_input.connect(_pad_input)
	add_child(_pad)
	_cap = Label.new()
	_cap.add_theme_font_size_override("font_size", 20)
	_cap.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	_cap.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_cap.add_theme_constant_override("outline_size", 6)
	_cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 14)
	_status.add_theme_color_override("font_color", Color(1, 0.95, 0.75))
	_status.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_status.add_theme_constant_override("outline_size", 5)
	_status.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_status.position = Vector2(-160, 14)
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_status)
	_bar = VBoxContainer.new()
	_bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_bar.offset_bottom = -8
	_bar.offset_left = 10
	_bar.offset_right = -10
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bar)
	_bar.add_child(_cap)
	_show_btn = Button.new()
	_show_btn.text = "..."
	_show_btn.custom_minimum_size = Vector2(56, 40)
	_show_btn.focus_mode = Control.FOCUS_NONE
	_show_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_show_btn.offset_left = -66
	_show_btn.offset_top = 8
	_show_btn.modulate = Color(1, 1, 1, 0.55)
	_show_btn.visible = false
	_show_btn.pressed.connect(func(): set_ui(true))
	add_child(_show_btn)
	var r1 := HFlowContainer.new()
	r1.alignment = FlowContainer.ALIGNMENT_CENTER
	_bar.add_child(r1)
	_mk(r1, "Photo", func(): shoot(), 110)
	_focus_btn = _mk(r1, "Focus", func(): next_target(), 150)
	_filter_btn = _mk(r1, "Look", func(): cycle_filter(), 130)
	_cap_btn = _mk(r1, "Caption", func(): caption_on = not caption_on; _sync(), 120)
	_mk(r1, "Hide buttons", func(): set_ui(false), 140)
	if not OS.has_feature("mobile") and not OS.has_feature("web"):
		_mk(r1, "Photo folder", func(): OS.shell_open(ProjectSettings.globalize_path("user://photos")), 130)
	_mk(r1, "Close", func(): close(), 90)
	var r2 := HFlowContainer.new()
	r2.alignment = FlowContainer.ALIGNMENT_CENTER
	_bar.add_child(r2)
	_hold_btn(r2, "In", "in")
	_hold_btn(r2, "Out", "out")
	_hold_btn(r2, "Up", "up")
	_hold_btn(r2, "Down", "down")
	_hold_btn(r2, "Wide", "wide")
	_hold_btn(r2, "Tight", "tight")
	_hold_btn(r2, "Left", "left")
	_hold_btn(r2, "Right", "right")


func _mk(parent: Node, text: String, cb: Callable, w: float = 100.0) -> Button:
	var b := Button.new()
	b.text = I18n.t(text)
	b.custom_minimum_size = Vector2(w, 40)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _hold_btn(parent: Node, text: String, key: String) -> void:
	var b := Button.new()
	b.text = I18n.t(text)
	b.custom_minimum_size = Vector2(70, 40)
	b.focus_mode = Control.FOCUS_NONE
	b.button_down.connect(func(): _hold[key] = true)
	b.button_up.connect(func(): _hold[key] = false)
	parent.add_child(b)


# ---- opening and closing -------------------------------------------------------------------------------------------

func open(beast_slot: int = -1) -> bool:
	if active:
		return true
	player = get_tree().get_first_node_in_group("player") as Node3D
	if player == null or Game.sys("tester") == null and false:
		return false
	_build()
	_hud = get_tree().get_first_node_in_group("hud")
	_touch = get_tree().get_first_node_in_group("touch_ui")
	prev_cam = get_viewport().get_camera_3d()
	cam = Camera3D.new()
	cam.fov = fov
	get_tree().root.add_child(cam)
	var py := 0.0
	if "_yaw" in player:
		py = float(player._yaw)
	yaw = py + PI
	pitch = -0.2
	dist = 4.5
	height = 0.0
	pan = Vector3.ZERO
	fov = 62.0
	caption_on = true
	active = true
	_collect_targets()
	ti = 0
	if beast_slot >= 0:
		for i in targets.size():
			if targets[i] != player and "slot" in targets[i] and int(targets[i].slot) == beast_slot:
				ti = i
	set_ui(true)
	visible = true
	if _hud != null:
		_hud.visible = false
	if _touch != null:
		_touch.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	cam.current = true
	_update_cam(0.0)
	_sync()
	Game.log_event("photo_open", {})
	return true


func close() -> void:
	if not active:
		return
	active = false
	visible = false
	if cam != null:
		cam.current = false
		cam.queue_free()
		cam = null
	if player != null and "camera" in player and player.camera != null:
		player.camera.current = true
	elif prev_cam != null and is_instance_valid(prev_cam):
		prev_cam.current = true
	if _hud != null:
		_hud.visible = true
	if _touch != null:
		_touch.visible = true
	for k in _hold:
		_hold[k] = false
	if _hud != null:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if _hud.is_blocking() else Input.MOUSE_MODE_CAPTURED
	if _hud != null and _hud.has_method("refresh"):
		_hud.refresh()


func _collect_targets() -> void:
	targets = [player]
	for n in get_tree().get_nodes_in_group("familiar_node"):
		if n is Node3D and n.visible:
			targets.append(n)


func next_target() -> void:
	_collect_targets()
	ti = (ti + 1) % maxi(targets.size(), 1)
	pan = Vector3.ZERO
	_sync()


func cycle_filter() -> void:
	filter_i = (filter_i + 1) % FILTERS.size()
	_sync()


func set_ui(on: bool) -> void:
	ui_on = on
	if _bar != null:
		for ch in _bar.get_children():
			if ch != _cap:
				ch.visible = on
	if _show_btn != null:
		_show_btn.visible = not on
	if _status != null:
		_status.visible = on


func _focus_node() -> Node3D:
	if ti < targets.size() and is_instance_valid(targets[ti]):
		return targets[ti]
	ti = 0
	return player


func _focus_point() -> Vector3:
	var f := _focus_node()
	return f.global_position + Vector3(0, 1.1 if f == player else 0.8, 0) + pan


func caption_text() -> String:
	var f := _focus_node()
	if f == player or not f.is_in_group("familiar_node"):
		var nm := str(Game.char_name) if str(Game.char_name) != "" else I18n.t("Wanderer")
		return "%s  ·  %s  ·  %s" % [nm, Game.cultivation_label(), Game._place_label(Game.current_level)]
	var slot: int = int(f.slot) if "slot" in f else 0
	var b: Dictionary = Game.summoned_beast(slot)
	if b.is_empty():
		return ""
	var bits := [Game.familiar_title(b)]
	var BR = Game.sys("breeding")
	if BR != null:
		if int(b.get("gen", 0)) > 0:
			bits.append(I18n.t("generation %d") % int(b["gen"]))
		if BR.variant_name(b) != "":
			bits.append(BR.variant_name(b))
		if str(b.get("trait", "")) != "" and BR.data.get("traits", {}).has(str(b["trait"])):
			bits.append(I18n.t(str(BR.data["traits"][str(b["trait"])]["name"])))
	return "  ·  ".join(bits)


func _sync() -> void:
	if _mat == null:
		return
	var fl: Array = FILTERS[filter_i]
	_mat.set_shader_parameter("tint", fl[1])
	_mat.set_shader_parameter("sat", float(fl[2]))
	_mat.set_shader_parameter("contrast", float(fl[3]))
	_mat.set_shader_parameter("vignette", float(fl[4]))
	var f := _focus_node()
	var fname := I18n.t("you") if f == player else (str(Game.summoned_beast(int(f.slot)).get("name", "")) if "slot" in f else I18n.t("beast"))
	_focus_btn.text = I18n.t("Focus: %s") % fname
	_filter_btn.text = I18n.t("Look: %s") % I18n.t(str(fl[0]))
	_cap_btn.text = I18n.t("Caption: on") if caption_on else I18n.t("Caption: off")
	_cap.text = caption_text() if caption_on else ""
	_status.text = I18n.t("Drag to look  ·  wheel or pinch to zoom  ·  Enter: photo  ·  Esc: close") + ("  ·  " + I18n.t("%d saved") % shots if shots > 0 else "")


# ---- the camera ---------------------------------------------------------------------------------------------------

func _update_cam(delta: float) -> void:
	if cam == null:
		return
	var step := delta * 3.0
	if _hold.get("in", false):
		dist -= delta * 5.0
	if _hold.get("out", false):
		dist += delta * 5.0
	if _hold.get("up", false):
		height += step
	if _hold.get("down", false):
		height -= step
	if _hold.get("wide", false):
		fov += delta * 30.0
	if _hold.get("tight", false):
		fov -= delta * 30.0
	if _hold.get("left", false):
		yaw += delta * 1.2
	if _hold.get("right", false):
		yaw -= delta * 1.2
	var mv := Vector2.ZERO
	if Input.is_key_pressed(KEY_W):
		mv.y -= 1.0
	if Input.is_key_pressed(KEY_S):
		mv.y += 1.0
	if Input.is_key_pressed(KEY_A):
		mv.x -= 1.0
	if Input.is_key_pressed(KEY_D):
		mv.x += 1.0
	if mv != Vector2.ZERO:
		var fwd := Vector3(-sin(yaw), 0, -cos(yaw)) * -1.0       # the camera looks toward the focus: forward = away from the camera
		var right := Vector3(cos(yaw), 0, -sin(yaw))
		pan += (fwd * -mv.y + right * mv.x) * delta * 3.0
		if pan.length() > PAN_MAX:
			pan = pan.normalized() * PAN_MAX
	if Input.is_key_pressed(KEY_Q):
		height -= step
	if Input.is_key_pressed(KEY_E):
		height += step
	if Input.is_key_pressed(KEY_BRACKETLEFT):
		fov += delta * 30.0
	if Input.is_key_pressed(KEY_BRACKETRIGHT):
		fov -= delta * 30.0
	dist = clampf(dist, 0.8, 14.0)
	height = clampf(height, -1.0, 6.0)
	fov = clampf(fov, 25.0, 100.0)
	pitch = clampf(pitch, -1.2, 1.1)
	var fp := _focus_point() + Vector3(0, height, 0)
	var dir := Vector3(sin(yaw) * cos(pitch), -sin(pitch), cos(yaw) * cos(pitch))
	var want := fp + dir * dist
	var space := get_viewport().get_world_3d().direct_space_state if get_viewport().get_world_3d() != null else null
	if space != null:
		var q := PhysicsRayQueryParameters3D.create(fp, want)
		q.collision_mask = 1
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			want = fp + (hit["position"] - fp) * 0.9
	cam.global_position = want
	cam.look_at(fp, Vector3.UP)
	cam.fov = fov


func _process(delta: float) -> void:
	if not active:
		return
	_update_cam(delta)
	if _cap != null and caption_on:
		var t := caption_text()
		if _cap.text != t:
			_cap.text = t


func _pad_input(ev: InputEvent) -> void:
	if not active:
		return
	if ev is InputEventMouseMotion and (ev.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		yaw -= ev.relative.x * 0.006
		pitch += ev.relative.y * 0.006
	elif ev is InputEventMouseMotion and (ev.button_mask & MOUSE_BUTTON_MASK_RIGHT) != 0:
		height += ev.relative.y * 0.01
	elif ev is InputEventMouseButton and ev.pressed:
		if ev.button_index == MOUSE_BUTTON_WHEEL_UP:
			dist -= 0.4
		elif ev.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			dist += 0.4
		elif not ui_on and ev.button_index == MOUSE_BUTTON_LEFT:
			pass
	elif ev is InputEventMouseButton and not ev.pressed and not ui_on and ev.button_index == MOUSE_BUTTON_LEFT and ev.double_click:
		set_ui(true)


func _input(ev: InputEvent) -> void:
	if not active:
		return
	if ev is InputEventMagnifyGesture:
		dist /= maxf(0.2, ev.factor)
		get_viewport().set_input_as_handled()
		return
	if ev is InputEventKey and ev.pressed and not ev.echo:
		match ev.keycode:
			KEY_ESCAPE, KEY_F9:
				close()
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
				shoot()
			KEY_TAB:
				next_target()
			KEY_H:
				set_ui(not ui_on)
			KEY_C:
				caption_on = not caption_on
				_sync()
			KEY_L:
				cycle_filter()
			_:
				return
		get_viewport().set_input_as_handled()
	elif ev.is_action_pressed("pause") or ev.is_action_pressed("menu"):
		get_viewport().set_input_as_handled()


# ---- the photo -----------------------------------------------------------------------------------------------------

func shoot() -> String:
	## hide the buttons for a frame, read the picture, put them back. Returns the file's path ("" when it could not be saved).
	if not active:
		return ""
	var was := ui_on
	var st_vis := _status.visible
	if _bar != null:
		for ch in _bar.get_children():
			if ch != _cap:
				ch.visible = false
	_status.visible = false
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	if _bar != null:
		for ch in _bar.get_children():
			if ch != _cap:
				ch.visible = was
	_status.visible = st_vis
	return save_image(img)


func save_image(img: Image) -> String:
	if img == null or img.is_empty():
		return ""
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://photos"))
	var t := Time.get_datetime_dict_from_system()
	shots += 1
	var fn := "dce_%04d%02d%02d_%02d%02d%02d_%d.png" % [int(t["year"]), int(t["month"]), int(t["day"]), int(t["hour"]), int(t["minute"]), int(t["second"]), shots]
	var path := "user://photos/" + fn
	var err := img.save_png(path)
	if err != OK:
		Game.message.emit(I18n.t("The photo could not be saved."))
		return ""
	last_path = path
	var extra := ""
	var pics := OS.get_system_dir(OS.SYSTEM_DIR_PICTURES)
	if pics != "" and DisplayServer.get_name() != "headless":
		var d := pics.path_join("DungeonCrawlElite")
		if DirAccess.make_dir_recursive_absolute(d) == OK and img.save_png(d.path_join(fn)) == OK:
			extra = " + " + I18n.t("your Pictures folder")
	Game.set_flag("fs:photo")
	Game.log_event("photo", {"beasts": targets.size() - 1, "filter": str(FILTERS[filter_i][0])})
	Game.message.emit(I18n.t("PHOTO saved: %s%s") % [fn, extra])
	_sync()
	return path
