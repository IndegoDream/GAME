extends CanvasLayer
const Acc := preload("res://scripts/core/Access.gd")
## TouchUI: playing on a phone or a tablet (round 29 -- Robert: "allow me to
## play and test through my phone"). Shown when the screen is a touch screen
## (or when Graphics > Touch controls is "on").
## Round 132 layout: thumb cluster bottom right (attack, guard, jump, use, step); a moves bar down the right edge; menu buttons along the top between the HUD cards; quick-use bottom left of centre.
##
##   left thumb   -- anywhere on the left of the screen: a stick appears
##                   under your thumb; push to walk, push all the way to run
##   right thumb  -- drag anywhere on the right that isn't a button: look
##   buttons      -- attack, guard (hold; tap to parry), jump, use (E),
##                   step (V), qi art (F), switch art (X); along the top:
##                   meditate, salve, pill, gourd, bag, journal, meridians,
##                   camera, menu
##
## The buttons press the game's own actions (TouchScreenButton), so they do
## exactly what the keys do. While a window is open (a talk, the bag, the
## menu) only the window takes your taps, plus a close button.

const STICK_RADIUS := 110.0
const LOOK_SPEED := 0.0055
const BAR_X := 40.0            # the moves bar: centre of its buttons from the right edge
const BAR_Y := 150.0           # ...first button from the top
const BAR_STEP := 66.0         # ...spacing
const BAR_COUNT := 6

var _stick_finger := -1
var _stick_origin := Vector2.ZERO
var _stick_now := Vector2.ZERO
var _look_finger := -1
var _look_last := Vector2.ZERO
var _draw: Control
var _play_buttons: Array = []      # [TouchScreenButton, anchor, offset, size]
var _close_button: TouchScreenButton
var _all: Array = []
var _unit := 1.0
var _was_blocking := false
var _turn: Label


static func wanted() -> bool:
	var mode := str(preload("res://scripts/core/Gfx.gd").settings.get("touch", "auto"))
	if mode == "on":
		return true
	if mode == "off":
		return false
	return DisplayServer.is_touchscreen_available() or OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios")


static func sync(tree: SceneTree) -> void:
	## add the touch controls, or take them away, to match the setting
	var have = tree.get_first_node_in_group("touch_ui")
	if wanted() and have == null:
		fit_screen(tree)
		var t = (load("res://scripts/ui/TouchUI.gd") as GDScript).new()
		t.name = "TouchUI"
		(tree.current_scene if tree.current_scene else tree.root).add_child.call_deferred(t)
	elif not wanted() and have != null:
		have._release_stick()
		have.queue_free()


static func fit_screen(tree: SceneTree) -> void:
	## the game's windows were laid out for a 1280 x 720 screen: on a phone
	## (thousands of tiny pixels) scale them up to read, keeping the shape
	## of the phone's screen
	var w := tree.root
	w.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	w.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	w.content_scale_size = Vector2i(1067, design_height())


static func design_height() -> int:
	## how many layout pixels tall the screen is: 720 on a big screen; a
	## phone (under ~600 CSS pixels tall) gets 600, so the words are bigger
	if DisplayServer.get_name() == "headless":
		return 720
	var ws := DisplayServer.window_get_size()
	var sc := maxf(DisplayServer.screen_get_scale(), 1.0) if OS.has_feature("web") else 1.0
	return 600 if float(ws.y) / sc < 600.0 else 720


func _ready() -> void:
	layer = 9                     # under the HUD's windows (10), over the world
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("touch_ui")
	_draw = Control.new()
	_draw.set_anchors_preset(Control.PRESET_FULL_RECT)
	_draw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_draw.draw.connect(_paint)
	add_child(_draw)
	# round 132 -- Robert: "a tool bar on the right side can hold the moves on the phone".
	# the thumb cluster (bottom right) keeps what you press all the time; the moves live in a bar down the right edge.
	var br := [["ATK", "attack", 170, 150, 112], ["GRD", "guard", 310, 118, 78], ["JUMP", "jump", 150, 290, 78],
		["USE", "interact", 290, 245, 70], ["STEP", "wind_step", 420, 85, 62]]
	for b in br:
		_play_buttons.append([_button(str(b[0]), str(b[1]), float(b[4])), "br", Vector2(float(b[2]), float(b[3])), float(b[4])])
	# the moves bar, right edge, top to bottom
	var bar := [["ART", "qi_burst"], ["SWAP", "art_cycle"], ["TAL", "talisman"], ["PATH", "path_art"], ["SUP", "support_art"], ["SUP2", "support2_art"]]
	var k := 0
	for m in bar:
		_play_buttons.append([_button(str(m[0]), str(m[1]), 54.0), "tr", Vector2(BAR_X, BAR_Y + k * BAR_STEP), 54.0])
		k += 1
	# the menu buttons sit top centre (clear of the quest card on the right), the quick-use items bottom centre
	var top := [["PAUSE", "pause"], ["CAM", "camera_view"], ["MENU", "menu"], ["MER", "lattice"], ["BAG", "inventory"]]
	var i := 0
	for b in top:
		_play_buttons.append([_button(str(b[0]), str(b[1]), 48.0), "tl", Vector2(410.0 + float(i) * 56.0, 40.0), 48.0, i])      # between the stat card and the quest card
		i += 1
	var quick := [["MED", "meditate"], ["SALVE", "use_salve"], ["PILL", "use_pill"], ["GOURD", "use_gourd"], ["FLOW", "flow"]]
	i = 0
	for b in quick:
		_play_buttons.append([_button(str(b[0]), str(b[1]), 52.0), "bl", Vector2(320.0 + float(i) * 58.0, 42.0), 52.0, i])      # clear of the floor banner and of STEP
		i += 1
	for qi in range(4):                      # round 158: the quick-art keys continue the quick row
		_play_buttons.append([_button("Q%d" % (qi + 1), "quick%d" % (qi + 1), 48.0), "bl", Vector2(320.0 + float(qi) * 58.0, 100.0), 48.0, 5 + qi])
	_turn = Label.new()
	_turn.text = "Turn your phone or tablet sideways to play."
	_turn.add_theme_font_size_override("font_size", 34)
	_turn.add_theme_color_override("font_outline_color", Color.BLACK)
	_turn.add_theme_constant_override("outline_size", 8)
	_turn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_turn.set_anchors_preset(Control.PRESET_CENTER)
	_turn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_draw.add_child(_turn)
	_close_button = _button("CLOSE", "pause", 64.0)
	get_viewport().size_changed.connect(_layout)
	_layout()
	var hud = get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("set_touch_help"):
		hud.set_touch_help()


func _button(text: String, action: String, size: float) -> TouchScreenButton:
	var b := TouchScreenButton.new()
	b.action = action
	b.texture_normal = _disc(Color(0.08, 0.09, 0.12, 0.42), Color(1, 1, 1, 0.35))
	b.texture_pressed = _disc(Color(0.85, 0.75, 0.45, 0.55), Color(1, 0.95, 0.8, 0.8))
	var sh := CircleShape2D.new()
	sh.radius = 64.0
	b.shape = sh
	b.shape_centered = true
	b.passby_press = false
	b.visibility_mode = TouchScreenButton.VISIBILITY_ALWAYS
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.size = Vector2(128, 128)
	l.add_theme_font_size_override("font_size", 30 if text.length() <= 4 else 24)
	l.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 6)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(l)
	b.set_meta("size", size)
	add_child(b)
	_all.append(b)
	return b


static func _disc(fill: Color, rim: Color) -> ImageTexture:
	## a 128 px round button face
	var img := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	for y in 128:
		for x in 128:
			var d := Vector2(x - 63.5, y - 63.5).length()
			var c := Color(0, 0, 0, 0)
			if d <= 63.0:
				c = fill if d < 58.0 else rim
				c.a *= clampf(63.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)


func relayout() -> void:
	if is_inside_tree():
		_layout()


func _left() -> bool:
	return Acc.left_handed()


func _layout() -> void:
	var vs := get_viewport().get_visible_rect().size
	_unit = clampf(minf(vs.x, vs.y) / 720.0, 0.6, 2.0)
	var big: float = Acc.big_touch()
	var left := _left()
	for pb in _play_buttons:
		var b: TouchScreenButton = pb[0]
		var kind := str(pb[1])
		var grow := 1.0 if (kind == "tl" or kind == "bl") else (minf(big, 1.2) if kind == "tr" else big)       # (a left-hand mirror and big buttons: round 142a)
		var off: Vector2 = pb[2] * _unit
		var sz: float = float(pb[3]) * (minf(_unit, 1.0) if (kind == "tl" or kind == "bl") else _unit) * grow     # the HUD's cards beside the small rows don't grow, so neither do those buttons
		var center := Vector2(vs.x - off.x, off.y)                         # "tr": from the top right corner
		if left:
			center = Vector2(off.x, 275.0 + 27.0 * _unit + (off.y - BAR_Y * _unit))      # the moves bar moves to the left edge, under the stat card
		match kind:
			"br":
				center = Vector2(off.x, vs.y - off.y) if left else Vector2(vs.x - off.x, vs.y - off.y)
			"tl":                                       # (x is in layout units, not scaled: the HUD's cards beside them don't scale)
				center = Vector2(float(pb[2].x), off.y)
			"bl":
				center = Vector2(vs.x - float(pb[2].x), vs.y - off.y) if left else Vector2(float(pb[2].x), vs.y - off.y)
		b.scale = Vector2.ONE * (sz / 128.0)
		b.position = center - Vector2(sz, sz) * 0.5
	var cs := 64.0 * _unit
	_close_button.scale = Vector2.ONE * (cs / 128.0)
	_close_button.position = Vector2(vs.x - cs - 16.0 * _unit, 16.0 * _unit)
	_turn.visible = vs.y > vs.x * 1.05
	_turn.position = Vector2(vs.x * 0.5 - 300.0, vs.y * 0.5 - 30.0)
	_turn.size = Vector2(600, 60)


func _blocking() -> bool:
	var hud = get_tree().get_first_node_in_group("hud")
	return hud != null and hud.has_method("is_blocking") and hud.is_blocking()


func _on_a_button(p: Vector2) -> bool:
	for b in _all:
		var tb := b as TouchScreenButton
		if not tb.visible:
			continue
		var sz: float = 128.0 * tb.scale.x
		if p.distance_to(tb.position + Vector2(sz, sz) * 0.5) <= sz * 0.55:
			return true
	return false


func _process(_delta: float) -> void:
	# a touch screen has no mouse to capture (the game asks for one now and then)
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var blocking := _blocking()
	if blocking != _was_blocking:
		_was_blocking = blocking
		if blocking:
			_release_stick()
			_look_finger = -1
	for pb in _play_buttons:
		(pb[0] as TouchScreenButton).visible = not blocking
	_close_button.visible = blocking
	_draw.queue_redraw()


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			if _blocking() or _on_a_button(t.position):
				return
			var vs := get_viewport().get_visible_rect().size
			var in_stick := (t.position.x > vs.x * 0.58) if _left() else (t.position.x < vs.x * 0.42)
			if in_stick and _stick_finger < 0:
				_stick_finger = t.index
				_stick_origin = t.position
				_stick_now = t.position
			elif not in_stick and _look_finger < 0:
				_look_finger = t.index
				_look_last = t.position
		else:
			if t.index == _stick_finger:
				_release_stick()
			elif t.index == _look_finger:
				_look_finger = -1
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if d.index == _stick_finger:
			_stick_now = d.position
			_push_stick()
		elif d.index == _look_finger:
			var rel := d.position - _look_last
			_look_last = d.position
			var player = get_tree().get_first_node_in_group("player")
			if player and player.has_method("touch_look"):
				player.touch_look(rel * LOOK_SPEED / maxf(_unit, 0.5))


func _push_stick() -> void:
	var r := STICK_RADIUS * _unit
	var v := (_stick_now - _stick_origin) / r
	if v.length() > 1.0:
		v = v.normalized()
	_set_axis("move_left", "move_right", v.x)
	_set_axis("move_forward", "move_back", v.y)
	if v.length() > 0.92:
		Input.action_press("sprint")
	else:
		Input.action_release("sprint")


func _set_axis(neg: String, pos: String, x: float) -> void:
	if x < -0.12:
		Input.action_press(neg, minf(-x, 1.0))
		Input.action_release(pos)
	elif x > 0.12:
		Input.action_press(pos, minf(x, 1.0))
		Input.action_release(neg)
	else:
		Input.action_release(neg)
		Input.action_release(pos)


func _release_stick() -> void:
	_stick_finger = -1
	for a in ["move_left", "move_right", "move_forward", "move_back", "sprint"]:
		Input.action_release(a)


func _paint() -> void:
	if _blocking():
		return
	# the moves bar: a soft rounded rail behind its buttons
	var vs := get_viewport().get_visible_rect().size
	var u := _unit
	var w := 70.0 * u
	var x0 := vs.x - BAR_X * u - w * 0.5
	var y0 := (BAR_Y - 40.0) * u
	if _left():
		x0 = BAR_X * u - w * 0.5
		y0 = 275.0 - 13.0 * u
	var h := ((BAR_COUNT - 1) * BAR_STEP + 80.0) * u
	_draw.draw_style_box(_bar_style(u), Rect2(x0, y0, w, h))
	if _stick_finger < 0:
		return
	var r := STICK_RADIUS * _unit
	_draw.draw_circle(_stick_origin, r, Color(0.05, 0.06, 0.08, 0.3))
	_draw.draw_arc(_stick_origin, r, 0.0, TAU, 48, Color(1, 1, 1, 0.35), 3.0 * _unit, true)
	var k := _stick_now - _stick_origin
	if k.length() > r:
		k = k.normalized() * r
	_draw.draw_circle(_stick_origin + k, r * 0.42, Color(0.9, 0.85, 0.7, 0.55))


var _bar_sb: StyleBoxFlat

func _bar_style(u: float) -> StyleBoxFlat:
	if _bar_sb == null:
		_bar_sb = StyleBoxFlat.new()
		_bar_sb.bg_color = Color(0.05, 0.06, 0.09, 0.38)
		_bar_sb.border_color = Color(1, 1, 1, 0.16)
		_bar_sb.set_border_width_all(2)
	_bar_sb.set_corner_radius_all(int(35.0 * u))
	return _bar_sb
