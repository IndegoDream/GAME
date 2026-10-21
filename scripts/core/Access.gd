extends RefCounted
## Round 142a: accessibility. Robert, 2026-10-18: "make the game more inviting ... something for everyone".
## Everything here is a setting on the machine (user://settings.json, with the graphics settings), never part of the save,
## and every one of them is OFF / standard until the player turns it on:
##   a_text     text size: 1.0 / 1.15 / 1.3 / 1.5 (every label, button and rich text under the HUD)
##   a_cb       colour-blind help: a screen filter that shifts the colours a viewer can't tell apart (deuteranopia, protanopia, tritanopia)
##   a_toggle   tap to guard / tap to run, instead of holding the button down
##   a_caps     captions: sound cues written on screen with a direction ("Foe winds up (left)")
##   a_motion   screen shake and bob: full / reduced / none
##   a_hand     touch controls: right-handed / left-handed (mirrored)
##   a_big      big touch buttons (+25%)
## Pure helpers are static so tools/access_check.gd can test them without a screen.

const Gfx := preload("res://scripts/core/Gfx.gd")
const Tx := preload("res://scripts/core/I18n.gd")

const ORDER := ["a_text", "a_cb", "a_toggle", "a_caps", "a_motion", "a_hand", "a_big"]
const OPTIONS := {
	"a_text": ["1.0", "1.15", "1.3", "1.5"],
	"a_cb": ["off", "deut", "prot", "trit"],
	"a_toggle": ["off", "on"],
	"a_caps": ["off", "on"],
	"a_motion": ["full", "reduced", "none"],
	"a_hand": ["right", "left"],
	"a_big": ["off", "on"],
}
const TITLE := {
	"a_text": "Text size", "a_cb": "Color-blind help", "a_toggle": "Tap to guard and run", "a_caps": "Sound captions",
	"a_motion": "Screen shake and bob", "a_hand": "Touch controls hand", "a_big": "Big touch buttons",
}
const LABEL := {
	"1.0": "Standard", "1.15": "Large", "1.3": "Larger", "1.5": "Largest",
	"off": "Off", "on": "On", "deut": "Green-weak (deuteranopia)", "prot": "Red-weak (protanopia)", "trit": "Blue-yellow (tritanopia)",
	"full": "Full", "reduced": "Reduced", "none": "None", "right": "Right-handed", "left": "Left-handed",
}
const HELP := {
	"a_text": "Bigger words in every menu and window.",
	"a_cb": "Shifts colors you may not tell apart (red / green / blue / yellow) into ones you can.",
	"a_toggle": "Press guard once to hold it up, again to lower it; press run once, and it stops when you stop.",
	"a_caps": "Sounds you can't hear are written on screen, with where they came from.",
	"a_motion": "How much the camera shakes and the weapon bobs. None is steady all the time.",
	"a_hand": "Left-handed mirrors the thumb buttons and the stick for a phone or tablet.",
	"a_big": "Makes the touch buttons a quarter bigger.",
}
const DEFAULTS := {"a_text": "1.0", "a_cb": "off", "a_toggle": "off", "a_caps": "off", "a_motion": "full", "a_hand": "right", "a_big": "off"}

# row i of the matrix a colour-blind viewer sees (Machado 2009, full severity), then the row of how the lost
# difference is moved into channels they can still tell apart
const CB_SIM := {
	"prot": [Vector3(0.152286, 1.052583, -0.204868), Vector3(0.114503, 0.786281, 0.099216), Vector3(-0.003882, -0.048116, 1.051998)],
	"deut": [Vector3(0.367322, 0.860646, -0.227968), Vector3(0.280085, 0.672501, 0.047413), Vector3(-0.011820, 0.042940, 0.968881)],
	"trit": [Vector3(1.255528, -0.076749, -0.178779), Vector3(-0.078411, 0.930809, 0.147602), Vector3(0.004733, 0.691367, 0.303900)],
}
const CB_SHIFT := {
	"prot": [Vector3(0, 0, 0), Vector3(0.7, 1, 0), Vector3(0.7, 0, 1)],
	"deut": [Vector3(0, 0, 0), Vector3(0.7, 1, 0), Vector3(0.7, 0, 1)],
	"trit": [Vector3(1, 0, 0.7), Vector3(0, 1, 0.7), Vector3(0, 0, 0)],
}
const CB_SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform vec3 s0; uniform vec3 s1; uniform vec3 s2;
uniform vec3 t0; uniform vec3 t1; uniform vec3 t2;
void fragment() {
	vec3 c = textureLod(screen_tex, SCREEN_UV, 0.0).rgb;
	vec3 sim = vec3(dot(s0, c), dot(s1, c), dot(s2, c));
	vec3 err = c - sim;
	vec3 shifted = vec3(dot(t0, err), dot(t1, err), dot(t2, err));
	COLOR = vec4(clamp(c + shifted, 0.0, 1.0), 1.0);
}
"""

const CAPTIONS := {
	"windup": "A foe winds up", "stamp": "A heavy stomp", "bell": "A bell tolls", "thud": "A heavy thud", "hurt": "You are hurt",
	"parry": "Parried", "door": "A door", "creak": "Something creaks", "chest": "A chest", "crystal": "A crystal hums",
	"waystone": "A waystone", "loot_epic": "A rare find", "floor_clear": "Floor cleared", "hit_heavy": "A heavy blow", "coins": "Coins",
	"dig": "Digging",
}

static var _tog := {}
static var _tog_frame := {}
static var _layer: CanvasLayer
static var _cb_rect: ColorRect
static var _cap_box: VBoxContainer
static var _cap_last := {}
static var _hooked := false


# ---- the settings ---------------------------------------------------------------------------------------------------------------

static func get_opt(key: String) -> String:
	Gfx.load_settings()
	var v := str(Gfx.settings.get(key, DEFAULTS.get(key, "")))
	return v if v in OPTIONS.get(key, []) else str(DEFAULTS.get(key, ""))


static func set_opt(key: String, value: String, tree: SceneTree = null) -> void:
	if not OPTIONS.has(key) or not (value in OPTIONS[key]):
		return
	Gfx.load_settings()
	Gfx.settings[key] = value
	Gfx.save_settings()
	if tree != null:
		apply(tree)


static func step(key: String, tree: SceneTree) -> String:
	var opts: Array = OPTIONS.get(key, [])
	if opts.is_empty():
		return ""
	var i := (opts.find(get_opt(key)) + 1) % opts.size()
	set_opt(key, str(opts[i]), tree)
	return str(opts[i])


static func text_scale() -> float:
	return float(get_opt("a_text"))


static func motion() -> float:
	## what is left of the camera's shake and the weapon's bob: 1, half, or none
	return {"full": 1.0, "reduced": 0.5, "none": 0.0}.get(get_opt("a_motion"), 1.0)


static func big_touch() -> float:
	return 1.25 if get_opt("a_big") == "on" else 1.0


static func left_handed() -> bool:
	return get_opt("a_hand") == "left"


static func captions_on() -> bool:
	return get_opt("a_caps") == "on"


# ---- tap-to-hold ----------------------------------------------------------------------------------------------------------------

static func held(action: String) -> bool:
	## Input.is_action_pressed, or -- when tap-to-toggle is on -- a switch the button flips (call it from _physics_process)
	if get_opt("a_toggle") != "on" or (action == "sprint" and _touch_stick()):
		return Input.is_action_pressed(action)
	var f := Engine.get_physics_frames()
	if int(_tog_frame.get(action, -1)) != f:
		_tog_frame[action] = f
		if Input.is_action_just_pressed(action):
			_tog[action] = not bool(_tog.get(action, false))
	return bool(_tog.get(action, false))


static func release(action: String) -> void:
	_tog[action] = false


static func _touch_stick() -> bool:
	var m := str(Gfx.settings.get("touch", "auto"))
	return m == "on" or (m == "auto" and (DisplayServer.is_touchscreen_available() or OS.has_feature("mobile")))


# ---- colour-blind filter ---------------------------------------------------------------------------------------------------------

static func cb_params(mode: String) -> Dictionary:
	## the shader's rows for a mode ({} when off)
	if not CB_SIM.has(mode):
		return {}
	var s: Array = CB_SIM[mode]
	var t: Array = CB_SHIFT[mode]
	return {"s0": s[0], "s1": s[1], "s2": s[2], "t0": t[0], "t1": t[1], "t2": t[2]}


static func cb_apply(c: Color, mode: String) -> Color:
	## the same maths as the shader, for tests: what a pixel becomes
	var p := cb_params(mode)
	if p.is_empty():
		return c
	var v := Vector3(c.r, c.g, c.b)
	var sim := Vector3((p["s0"] as Vector3).dot(v), (p["s1"] as Vector3).dot(v), (p["s2"] as Vector3).dot(v))
	var err := v - sim
	var sh := Vector3((p["t0"] as Vector3).dot(err), (p["t1"] as Vector3).dot(err), (p["t2"] as Vector3).dot(err))
	var o := (v + sh).clamp(Vector3.ZERO, Vector3.ONE)
	return Color(o.x, o.y, o.z, c.a)


# ---- text size ------------------------------------------------------------------------------------------------------------------

const _SIZE_PROPS := {
	"Label": ["font_size"], "Button": ["font_size"], "CheckBox": ["font_size"], "CheckButton": ["font_size"], "LineEdit": ["font_size"],
	"OptionButton": ["font_size"], "LinkButton": ["font_size"], "TextEdit": ["font_size"],
	"RichTextLabel": ["normal_font_size", "bold_font_size", "italics_font_size", "bold_italics_font_size", "mono_font_size"],
}


static func scaled_size(base: int, scale: float) -> int:
	return maxi(8, int(round(float(base) * scale)))


static func scale_node(n: Node, scale: float) -> void:
	if not (n is Control):
		return
	var c := n as Control
	for cls in _SIZE_PROPS:
		if c.is_class(cls):
			for prop in _SIZE_PROPS[cls]:
				var mk := "_a_base_" + str(prop)
				if not c.has_meta(mk):
					c.set_meta(mk, [c.get_theme_font_size(prop), c.has_theme_font_size_override(prop)])
				var bi: Array = c.get_meta(mk)
				if scale == 1.0 and not bool(bi[1]):
					c.remove_theme_font_size_override(prop)
				else:
					c.add_theme_font_size_override(prop, scaled_size(int(bi[0]), scale))
			return


static func scale_tree(n: Node, scale: float) -> void:
	scale_node(n, scale)
	for ch in n.get_children():
		scale_tree(ch, scale)


static func _under_hud(n: Node) -> bool:
	var p := n.get_parent()
	while p != null:
		if p.is_in_group("hud"):
			return true
		if p.is_in_group("touch_ui") or p == _layer:
			return false
		p = p.get_parent()
	return false


static func _on_node_added(n: Node) -> void:
	if n is Control and text_scale() != 1.0:
		(func(): if is_instance_valid(n) and n.is_inside_tree() and _under_hud(n): scale_node(n, text_scale())).call_deferred()


# ---- the screen layer: filter and captions --------------------------------------------------------------------------------------

static func install(tree: SceneTree) -> void:
	if tree == null:
		return
	if _layer == null or not is_instance_valid(_layer):
		_layer = CanvasLayer.new()
		_layer.name = "AccessLayer"
		_layer.layer = 100
		_layer.process_mode = Node.PROCESS_MODE_ALWAYS
		_cb_rect = ColorRect.new()
		_cb_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		_cb_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_cb_rect.color = Color.WHITE
		var sh := Shader.new()
		sh.code = CB_SHADER
		var m := ShaderMaterial.new()
		m.shader = sh
		_cb_rect.material = m
		_cb_rect.visible = false
		_layer.add_child(_cb_rect)
		_cap_box = VBoxContainer.new()
		_cap_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_cap_box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
		_cap_box.anchor_left = 0.5
		_cap_box.anchor_right = 0.5
		_cap_box.anchor_top = 1.0
		_cap_box.anchor_bottom = 1.0
		_cap_box.offset_left = -260.0
		_cap_box.offset_right = 260.0
		_cap_box.offset_top = -250.0
		_cap_box.offset_bottom = -150.0
		_cap_box.alignment = BoxContainer.ALIGNMENT_END
		_layer.add_child(_cap_box)
		tree.root.add_child.call_deferred(_layer)
	if not _hooked:
		_hooked = true
		tree.node_added.connect(_on_node_added)


static func apply(tree: SceneTree) -> void:
	## make the screen match the settings (call after any change, and at start)
	install(tree)
	var mode := get_opt("a_cb")
	var p := cb_params(mode)
	if _cb_rect != null:
		_cb_rect.visible = not p.is_empty() and DisplayServer.get_name() != "headless"
		if not p.is_empty():
			var m := _cb_rect.material as ShaderMaterial
			for k in p:
				m.set_shader_parameter(str(k), p[k])
	var hud = tree.get_first_node_in_group("hud")
	if hud != null:
		scale_tree(hud, text_scale())
	var tu = tree.get_first_node_in_group("touch_ui")
	if tu != null and tu.has_method("relayout"):
		tu.relayout()


# ---- captions -------------------------------------------------------------------------------------------------------------------

static func caption_text(name: String) -> String:
	return str(CAPTIONS.get(name, ""))


static func direction_word(rel: Vector3) -> String:
	## where a sound came from, relative to the way the camera faces (rel: the sound's position in the camera's own frame)
	if Vector2(rel.x, rel.z).length() < 1.5:
		return "close"
	var a := rad_to_deg(atan2(rel.x, -rel.z))
	if absf(a) <= 45.0:
		return "ahead"
	if absf(a) >= 135.0:
		return "behind"
	return "right" if a > 0.0 else "left"


static func caption(name: String, pos = null) -> void:
	if _cap_box == null or not is_instance_valid(_cap_box) or not captions_on():
		return
	var txt := caption_text(name)
	if txt == "":
		return
	var now := Time.get_ticks_msec()
	if now - int(_cap_last.get(name, -9999)) < 1200:
		return
	_cap_last[name] = now
	var shown: String = Tx.t(txt)
	if pos is Vector3 and _cap_box.get_viewport() != null:
		var cam := _cap_box.get_viewport().get_camera_3d()
		if cam != null:
			if cam.global_position.distance_to(pos as Vector3) > 24.0:
				return
			var rel: Vector3 = cam.global_transform.affine_inverse() * (pos as Vector3)
			shown += "  (" + Tx.t(direction_word(rel)) + ")"
	var l := Label.new()
	l.text = "[ " + shown + " ]"
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", scaled_size(20, text_scale()))
	l.add_theme_color_override("font_color", Color(1, 1, 1))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	l.add_theme_constant_override("outline_size", 6)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cap_box.add_child(l)
	while _cap_box.get_child_count() > 4:
		_cap_box.get_child(0).queue_free()
		_cap_box.remove_child(_cap_box.get_child(0))
	var tw := l.create_tween()
	tw.tween_interval(2.2)
	tw.tween_property(l, "modulate:a", 0.0, 0.5)
	tw.tween_callback(l.queue_free)
