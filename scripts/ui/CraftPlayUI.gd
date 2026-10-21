extends Control
## The screen for the craft mini-games (rules and scoring: scripts/systems/CraftPlay.gd). One panel, one big button that
## works with a key, a click or a tap, and a Skip that always works. Calls cb(score 0..1), or cb(-1.0) when skipped.

var CP                              # the CraftPlay system
var kind := ""
var skill := ""
var edge := 0
var cb: Callable
var _state := "intro"               # intro -> play -> done
var _t := 0.0                       # seconds in this state
var _local := 0.0                   # seconds in this strike / cut / round
var _step := 0                      # strike, cut or round number
var _scores: Array = []
var _holding := false
var _temp := 0.2
var _in_band := 0.0
var _fill := 0.0
var _seq: Array = []
var _entered: Array = []
var _show_i := 0
var _phase := "show"                # trace: show -> input
var _flash := ""
var _flash_t := 0.0
var _title: Label
var _hint: Label
var _msg: Label
var _act: Button
var _skip: Button
var _pad: Control
var _final := 0.0
var _params := {}
const W := 640.0
const H := 400.0


func start(p_kind: String, p_skill: String, p_edge: int, p_cb: Callable) -> void:
	CP = Game.sys("craftplay")
	kind = p_kind
	skill = p_skill
	edge = p_edge
	cb = p_cb
	_state = "intro"
	_t = 0.0
	_step = 0
	_scores = []
	_holding = false
	_temp = 0.2
	_in_band = 0.0
	_fill = 0.0
	_entered = []
	_phase = "show"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	if _title == null:
		_build()
	_title.text = {"hammer": I18n.t("At the anvil"), "simmer": I18n.t("Over the flame"), "pour": I18n.t("Measuring"), "facet": I18n.t("At the wheel"), "trace": I18n.t("Setting the strokes")}.get(kind, "")
	_hint.text = {"hammer": I18n.t("Strike when the heat is in the glowing zone."), "simmer": I18n.t("Hold to heat, let go to cool. Keep the flame in the band."),
		"pour": I18n.t("Hold to pour. Let go on the line."), "facet": I18n.t("Cut as the pointer crosses the mark."), "trace": I18n.t("Watch the strokes, then draw them back.")}.get(kind, "")
	_act.text = {"hammer": I18n.t("STRIKE"), "simmer": I18n.t("HOLD"), "pour": I18n.t("POUR"), "facet": I18n.t("CUT"), "trace": ""}.get(kind, "")
	_act.visible = kind != "trace"
	_pad.visible = false
	_msg.text = I18n.t("Get ready...")
	if kind == "trace":
		_seq = CP.trace_sequence(CP.trace_length(edge, Game.skill_level(skill)), randi())
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_apply_params()
	queue_redraw()


func _build() -> void:
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 22)
	_title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.55))
	_title.position = Vector2(0, 14)
	_title.size = Vector2(W, 30)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_title)
	_hint = Label.new()
	_hint.add_theme_font_size_override("font_size", 14)
	_hint.add_theme_color_override("font_color", Color(0.75, 0.78, 0.85))
	_hint.position = Vector2(0, 46)
	_hint.size = Vector2(W, 22)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_hint)
	_msg = Label.new()
	_msg.add_theme_font_size_override("font_size", 18)
	_msg.position = Vector2(0, 290)
	_msg.size = Vector2(W, 26)
	_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_msg)
	_act = Button.new()
	_act.add_theme_font_size_override("font_size", 26)
	_act.custom_minimum_size = Vector2(260, 56)
	_act.size = Vector2(260, 56)
	_act.focus_mode = Control.FOCUS_NONE
	_act.button_down.connect(_press)
	_act.button_up.connect(_release)
	add_child(_act)
	_skip = Button.new()
	_skip.text = I18n.t("Skip (no bonus)")
	_skip.size = Vector2(150, 34)
	_skip.focus_mode = Control.FOCUS_NONE
	_skip.pressed.connect(_do_skip)
	add_child(_skip)
	_pad = Control.new()
	_pad.size = Vector2(W, 120)
	add_child(_pad)
	var names := ["↑", "→", "↓", "←"]
	var pos := [Vector2(1, 0), Vector2(2, 1), Vector2(1, 2), Vector2(0, 1)]
	for i in 4:
		var b := Button.new()
		b.text = names[i]
		b.add_theme_font_size_override("font_size", 26)
		b.size = Vector2(64, 40)
		b.position = Vector2(W * 0.5 - 32 + (pos[i].x - 1) * 76, pos[i].y * 40)
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(_stroke.bind(i))
		_pad.add_child(b)
	resized.connect(_layout)
	_layout()


func _origin() -> Vector2:
	return Vector2((size.x - W) * 0.5, maxf(8.0, (size.y - H) * 0.5))


func _layout() -> void:
	var o := _origin()
	for c in [_title, _hint, _msg]:
		(c as Control).position.x = o.x
	_title.position.y = o.y + 14
	_hint.position.y = o.y + 46
	_msg.position.y = o.y + 286
	_act.position = o + Vector2(W * 0.5 - 130, 318)
	_skip.position = o + Vector2(W - 160, H - 44)
	_pad.position = o + Vector2(0, 280)
	queue_redraw()


func _apply_params() -> void:
	match kind:
		"simmer":
			_params = CP.simmer_params(edge)
		"pour":
			_params = CP.pour_params(edge)
		"hammer":
			_params = CP.hammer_params(edge, 0)
		"facet":
			_params = CP.facet_params(edge, 0)


# ---- input ----------------------------------------------------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and not event.echo:
		var k: Key = event.keycode
		if event.pressed:
			if k == KEY_ESCAPE:
				_do_skip()
			elif k in [KEY_SPACE, KEY_E, KEY_ENTER] and kind != "trace":
				_press()
			elif kind == "trace":
				var s := {KEY_UP: 0, KEY_W: 0, KEY_RIGHT: 1, KEY_D: 1, KEY_DOWN: 2, KEY_S: 2, KEY_LEFT: 3, KEY_A: 3}
				if s.has(k):
					_stroke(int(s[k]))
		elif k in [KEY_SPACE, KEY_E, KEY_ENTER]:
			_release()
		get_viewport().set_input_as_handled()
	elif event is InputEventJoypadButton and event.pressed and kind != "trace":
		_press()
		get_viewport().set_input_as_handled()
	elif event is InputEventJoypadButton and not event.pressed:
		_release()


func _ix(s: float) -> int:
	return 0 if s <= 0.0 else (1 if s < 0.5 else (2 if s < 1.0 else 3))


func _do_skip() -> void:
	_finish(-1.0)


func _press() -> void:
	if _state != "play":
		return
	match kind:
		"hammer":
			var p: Dictionary = CP.hammer_params(edge, _step)
			var m: float = CP.hammer_marker(_local, float(p["speed"]))
			var s: float = CP.hit_score(m - float(p["centre"]), float(p["width"]) * 0.5)
			_scores.append(s)
			_flash = [I18n.t("Missed"), I18n.t("Glancing"), I18n.t("Good"), I18n.t("Perfect")][_ix(s)]
			_flash_t = 0.6
			_step += 1
			_local = 0.0
			if _step >= int(Game.sys("craftplay").data.get("hammer", {}).get("strikes", 5)):
				_end_play()
		"simmer":
			_holding = true
		"pour":
			_holding = true
		"facet":
			var p2: Dictionary = CP.facet_params(edge, _step)
			var d: float = CP.circ_dist(CP.facet_pointer(_local, float(p2["speed"])), float(p2["mark"]))
			var s2: float = CP.hit_score(d, float(p2["arc"]) * 0.5)
			_scores.append(s2)
			_flash = [I18n.t("Chipped"), I18n.t("Close"), I18n.t("Clean"), I18n.t("Perfect cut")][_ix(s2)]
			_flash_t = 0.6
			_step += 1
			_local = 0.0
			if _step >= int(Game.sys("craftplay").data.get("facet", {}).get("cuts", 6)):
				_end_play()


func _release() -> void:
	if _state != "play" or not _holding:
		return
	_holding = false
	if kind == "pour":
		_pour_done()


func _pour_done() -> void:
	var tg: Array = _params.get("targets", [0.6])
	var target := float(tg[_step % tg.size()])
	var s: float = CP.pour_score(_fill, target, float(_params["tolerance"]))
	_scores.append(s)
	_flash = I18n.t("Spot on") if s >= 0.85 else (I18n.t("Near") if s >= 0.45 else I18n.t("Off"))
	_flash_t = 0.7
	_step += 1
	_fill = 0.0
	if _step >= int(_params.get("rounds", 3)):
		_end_play()


func _stroke(dir: int) -> void:
	if _state != "play" or _phase != "input":
		return
	_entered.append(dir)
	_flash = ["↑", "→", "↓", "←"][dir]
	_flash_t = 0.25
	if _entered.size() >= _seq.size():
		_scores = [CP.trace_score(_seq, _entered)]
		_end_play()


func _end_play() -> void:
	var s := 0.0
	if kind == "simmer":
		s = _in_band / maxf(float(_params["seconds"]), 0.1)
	else:
		for x in _scores:
			s += float(x)
		s /= maxf(float(_scores.size()), 1.0)
	_final = clampf(s, 0.0, 1.0)
	_state = "done"
	_t = 0.0
	_act.visible = false
	_pad.visible = false
	_msg.text = "%s  (%d%%)" % [CP.grade(_final), int(round(_final * 100.0))]


func _finish(score: float) -> void:
	if not visible:
		return
	visible = false
	_holding = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var c := cb
	cb = Callable()
	if c.is_valid():
		c.call(score)


# ---- time ---------------------------------------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	_flash_t = maxf(0.0, _flash_t - delta)
	match _state:
		"intro":
			if _t >= 0.9:
				_state = "play"
				_t = 0.0
				_local = 0.0
				_msg.text = ""
				if kind == "trace":
					_phase = "show"
					_show_i = 0
		"play":
			_local += delta
			match kind:
				"simmer":
					_temp = CP.simmer_step(_temp, _holding, _t, delta, _params)
					if CP.simmer_in_band(_temp, _t, _params):
						_in_band += delta
					if _t >= float(_params["seconds"]):
						_end_play()
				"pour":
					if _holding:
						_fill = minf(1.0, _fill + float(_params["rate"]) * delta)
						if _fill >= 1.0:
							_holding = false
							_pour_done()
				"trace":
					if _phase == "show":
						_show_i = int(_local / 0.75)
						if _show_i >= _seq.size():
							_phase = "input"
							_pad.visible = true
							_msg.text = I18n.t("Now draw them back.")
		"done":
			if _t >= 1.4:
				_finish(_final)
	queue_redraw()


# ---- drawing ----------------------------------------------------------------------------------------------------------------

func _draw() -> void:
	var o := _origin()
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.55))
	draw_rect(Rect2(o, Vector2(W, H)), Color(0.07, 0.08, 0.11, 0.97))
	draw_rect(Rect2(o, Vector2(W, H)), Color(0.55, 0.45, 0.3, 0.9), false, 2.0)
	var c := o + Vector2(W * 0.5, 170.0)
	match kind:
		"hammer":
			var p: Dictionary = CP.hammer_params(edge, mini(_step, 4))
			var x0 := c.x - 240.0
			draw_rect(Rect2(x0, c.y - 18, 480, 36), Color(0.16, 0.14, 0.13))
			var zc := x0 + float(p["centre"]) * 480.0
			var zw := float(p["width"]) * 480.0
			draw_rect(Rect2(zc - zw * 0.5, c.y - 18, zw, 36), Color(1.0, 0.55, 0.15, 0.85))
			draw_rect(Rect2(zc - zw * 0.125, c.y - 18, zw * 0.25, 36), Color(1.0, 0.9, 0.5, 0.95))
			if _state == "play":
				var m: float = CP.hammer_marker(_local, float(p["speed"]))
				draw_rect(Rect2(x0 + m * 480.0 - 3, c.y - 26, 6, 52), Color(0.9, 0.95, 1.0))
			for i in _scores.size():
				draw_circle(Vector2(c.x - 60 + i * 30, c.y + 50), 9, Color(0.4, 1.0, 0.5).lerp(Color(0.5, 0.2, 0.2), 1.0 - float(_scores[i])))
		"simmer":
			var bx := c.x - 30.0
			draw_rect(Rect2(bx, c.y - 100, 60, 200), Color(0.14, 0.12, 0.12))
			var bc: float = CP.simmer_band_centre(_t if _state == "play" else 0.0)
			var bh := float(_params.get("band", 0.22)) * 200.0
			draw_rect(Rect2(bx - 8, c.y + 100 - bc * 200.0 - bh * 0.5, 76, bh), Color(0.3, 0.9, 0.5, 0.45))
			draw_rect(Rect2(bx, c.y + 100 - _temp * 200.0, 60, _temp * 200.0), Color(1.0, 0.45, 0.15).lerp(Color(1.0, 0.85, 0.3), _temp))
			var left := maxf(0.0, float(_params.get("seconds", 8.0)) - _t) if _state == "play" else float(_params.get("seconds", 8.0))
			draw_rect(Rect2(c.x - 140, c.y + 110, 280.0 * left / maxf(float(_params.get("seconds", 8.0)), 0.1), 6), Color(0.8, 0.8, 0.9, 0.6))
		"pour":
			var vx := c.x - 40.0
			draw_rect(Rect2(vx, c.y - 100, 80, 200), Color(0.13, 0.15, 0.18))
			draw_rect(Rect2(vx, c.y + 100 - _fill * 200.0, 80, _fill * 200.0), Color(0.4, 0.8, 0.95, 0.85))
			var tg: Array = _params.get("targets", [0.6])
			var ty := c.y + 100 - float(tg[_step % tg.size()]) * 200.0
			draw_line(Vector2(vx - 20, ty), Vector2(vx + 100, ty), Color(1.0, 0.9, 0.4), 3.0)
			for i in _scores.size():
				draw_circle(Vector2(c.x + 100 + i * 24, c.y - 90), 8, Color(0.4, 1.0, 0.5).lerp(Color(0.5, 0.2, 0.2), 1.0 - float(_scores[i])))
		"facet":
			var p3: Dictionary = CP.facet_params(edge, mini(_step, 5))
			var r := 100.0
			draw_arc(c, r, 0, TAU, 64, Color(0.3, 0.35, 0.45), 6.0)
			var a0 := -PI * 0.5 + (float(p3["mark"]) - float(p3["arc"]) * 0.5) * TAU
			draw_arc(c, r, a0, a0 + float(p3["arc"]) * TAU, 24, Color(0.5, 0.95, 1.0), 10.0)
			draw_circle(c, 34, Color(0.6, 0.85, 1.0, 0.35))
			if _state == "play":
				var pa: float = -PI * 0.5 + CP.facet_pointer(_local, float(p3["speed"])) * TAU
				draw_line(c, c + Vector2(cos(pa), sin(pa)) * (r + 12), Color(1, 1, 1), 4.0)
			for i in _scores.size():
				draw_circle(Vector2(c.x - 75 + i * 30, c.y + 125), 8, Color(0.4, 1.0, 0.5).lerp(Color(0.5, 0.2, 0.2), 1.0 - float(_scores[i])))
		"trace":
			var g := ["↑", "→", "↓", "←"]
			var font := ThemeDB.fallback_font
			if _state == "play" and _phase == "show" and _show_i < _seq.size():
				draw_string(font, c + Vector2(-30, 40), g[int(_seq[_show_i])], HORIZONTAL_ALIGNMENT_CENTER, 60, 120, Color(1.0, 0.9, 0.5))
			for i in _seq.size():
				var filled := _phase == "input" and i < _entered.size()
				draw_circle(Vector2(c.x - (_seq.size() - 1) * 14 + i * 28, c.y - 90), 8, Color(0.5, 0.9, 0.5) if filled else Color(0.3, 0.3, 0.35))
	if _flash_t > 0.0:
		draw_string(ThemeDB.fallback_font, o + Vector2(0, 100), _flash, HORIZONTAL_ALIGNMENT_CENTER, W, 28, Color(1.0, 1.0, 0.7, minf(1.0, _flash_t * 3.0)))
