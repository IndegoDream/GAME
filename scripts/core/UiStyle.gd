extends RefCounted
## How the game's windows look and move (round 49). Robert, 2026-10-04:
## "make the gui and hud and menus more smooth and modern but keeping to the
## esthetic."
##
## The same world as before -- dark lacquer, warm gold, a cool glow for qi --
## but softer and rounder, with depth (a shadow under every window), real
## fonts (Inter for reading, Cinzel's carved capitals for titles), and motion
## that eases instead of popping:
##   * windows rise and fade in when they open; menu pages slide across
##   * buttons glow as the pointer comes over them and give a little when pressed
##   * the health and qi bars leave a pale trail when they drop, so you SEE
##     what a hit took; messages slide in
## Everything here is looks; every number is in data/ui.json. HUD.gd builds
## the theme from here once (root.theme) and every window inherits it.

const FONT_DIR := "res://assets/fonts/"

static var _cfg := {}
static var _fonts := {}
static var _watching := false


static func cfg() -> Dictionary:
	if _cfg.is_empty():
		_cfg = Game._load_json("res://data/ui.json", {}) if Game else {}
		if _cfg.is_empty():
			_cfg = {"_empty": true}
	return _cfg


static func col(key: String, fallback: Color = Color(1, 1, 1)) -> Color:
	var a = (cfg().get("color", {}) as Dictionary).get(key, [])
	if a is Array and a.size() >= 3:
		return Color(float(a[0]), float(a[1]), float(a[2]), float(a[3]) if a.size() > 3 else 1.0)
	return fallback


static func num(sec: String, key: String, fallback: float) -> float:
	return float((cfg().get(sec, {}) as Dictionary).get(key, fallback))


# ---- fonts -------------------------------------------------------------------------------------

static func font(kind: String = "body") -> Font:
	## "body", "bold", "heavy" or "title" -- null if the files aren't there
	## (then the engine's own font is used, as before)
	if _fonts.has(kind):
		return _fonts[kind]
	var files: Array = (cfg().get("fonts", {}) as Dictionary).get(kind, [])
	var main: FontFile = null
	var chain: Array[Font] = []
	for f in files:
		var ff := _font_file(FONT_DIR + str(f))
		if ff == null:
			continue
		if main == null:
			main = ff
		else:
			chain.append(ff)
	if main:
		var fb := ThemeDB.fallback_font
		if fb and not chain.has(fb):
			chain.append(fb)
		var cjk: Font = I18n.cjk_font()      # round 140: Chinese, Japanese, Korean letters come from the player's own system font
		if cjk and not chain.has(cjk):
			chain.append(cjk)
		main.fallbacks = chain
	_fonts[kind] = main
	return main


static func _font_file(p: String) -> FontFile:
	if ResourceLoader.exists(p):
		var r = load(p)
		if r is FontFile:
			return r
	if FileAccess.file_exists(p):
		var ff := FontFile.new()
		ff.data = FileAccess.get_file_as_bytes(p)
		return ff
	return null


static func title(l: Control, size: int = -1) -> void:
	## carved capitals for a heading (Cinzel)
	var f := font("title")
	if f == null or l == null:
		return
	if l is RichTextLabel:
		l.add_theme_font_override("normal_font", f)
	else:
		l.add_theme_font_override("font", f)
	if size > 0:
		l.add_theme_font_size_override("font_size", size)


static func is_title_size(size: int) -> bool:
	return size >= int(num("fonts", "title_from_size", 19))


# ---- boxes -------------------------------------------------------------------------------------

static func box(bg: Color, border: Color = Color(0, 0, 0, 0), kind: String = "panel") -> StyleBoxFlat:
	## a window or a card: rounded, a hairline edge (the accent colour, softened),
	## a soft shadow underneath
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(int(num("radius", kind, 12)))
	sb.corner_detail = 10
	sb.anti_aliasing = true
	sb.set_content_margin_all(14 if kind == "panel" else 10)
	if border.a > 0.0:
		sb.set_border_width_all(1)
		sb.border_color = Color(border.r, border.g, border.b, border.a * 0.55)
	else:
		sb.set_border_width_all(1)
		sb.border_color = col("edge", Color(1, 1, 1, 0.07))
	var sh := int(num("shadow", kind, 0))
	if sh > 0 and bg.a > 0.5:
		sb.shadow_size = sh
		sb.shadow_color = col("shadow", Color(0, 0, 0, 0.45))
		sb.shadow_offset = Vector2(0, sh * 0.25)
	return sb


static func _btn_box(bg: Color, border: Color, bw: int, left_bar: int = 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(int(num("radius", "button", 8)))
	sb.corner_detail = 8
	sb.anti_aliasing = true
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	if bw > 0:
		sb.set_border_width_all(bw)
		sb.border_color = border
	if left_bar > 0:
		sb.border_width_left = left_bar
		sb.border_color = border
	return sb


static func _flat(bg: Color, radius: int, margin: float = 0.0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.corner_detail = 6
	sb.anti_aliasing = true
	if margin > 0.0:
		sb.set_content_margin_all(margin)
	return sb


# ---- the theme ---------------------------------------------------------------------------------

static func theme() -> Theme:
	var t := Theme.new()
	var gold := col("gold", Color(0.95, 0.78, 0.45))
	var text := col("text", Color(0.93, 0.91, 0.86))
	var dim := col("text_dim", Color(0.62, 0.64, 0.7))
	var edge := col("edge", Color(1, 1, 1, 0.07))
	var raised := col("raised", Color(0.11, 0.11, 0.15, 0.9))
	var hover := col("raised_hover", Color(0.17, 0.16, 0.21, 0.96))
	var sunk := col("sunk", Color(0.07, 0.07, 0.095, 0.96))
	var body := font("body")
	if body:
		t.default_font = body
	t.default_font_size = int(num("fonts", "size", 15))
	var bold := font("bold")
	# buttons: a raised tile; the pointer warms its edge; pressed sinks
	for type in ["Button", "OptionButton", "MenuButton", "CheckButton", "CheckBox"]:
		t.set_stylebox("normal", type, _btn_box(raised, edge, 1))
		t.set_stylebox("hover", type, _btn_box(hover, Color(gold.r, gold.g, gold.b, 0.75), 1))
		t.set_stylebox("pressed", type, _btn_box(sunk, gold, 1))
		t.set_stylebox("hover_pressed", type, _btn_box(sunk.lightened(0.05), gold, 1))
		var fo := _btn_box(Color(0, 0, 0, 0), Color(gold.r, gold.g, gold.b, 0.55), 2)
		fo.draw_center = false
		t.set_stylebox("focus", type, fo)
		t.set_stylebox("disabled", type, _btn_box(Color(raised.r, raised.g, raised.b, 0.45), Color(1, 1, 1, 0.03), 1))
		t.set_color("font_color", type, text)
		t.set_color("font_hover_color", type, Color(1.0, 0.94, 0.78))
		t.set_color("font_pressed_color", type, gold)
		t.set_color("font_hover_pressed_color", type, gold.lightened(0.15))
		t.set_color("font_focus_color", type, text)
		t.set_color("font_disabled_color", type, Color(dim.r, dim.g, dim.b, 0.6))
		if bold:
			t.set_font("font", type, bold)
	# the menu's side rail: quiet until chosen, then a gold bar down its edge
	t.set_type_variation("RailButton", "Button")
	t.set_stylebox("normal", "RailButton", _btn_box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0))
	t.set_stylebox("hover", "RailButton", _btn_box(Color(1, 1, 1, 0.05), Color(0, 0, 0, 0), 0))
	t.set_stylebox("pressed", "RailButton", _btn_box(Color(gold.r, gold.g, gold.b, 0.11), gold, 0, 3))
	t.set_stylebox("hover_pressed", "RailButton", _btn_box(Color(gold.r, gold.g, gold.b, 0.15), gold, 0, 3))
	t.set_color("font_color", "RailButton", dim.lightened(0.15))
	t.set_color("font_hover_color", "RailButton", text)
	# a quiet, borderless button for rows of choices inside a page
	t.set_type_variation("FlatButton", "Button")
	t.set_stylebox("normal", "FlatButton", _btn_box(Color(1, 1, 1, 0.025), Color(0, 0, 0, 0), 0))
	t.set_stylebox("hover", "FlatButton", _btn_box(Color(1, 1, 1, 0.07), Color(0, 0, 0, 0), 0))
	# tabs (the pack's Bench / Forge / ...): a gold line under the open one
	for type in ["TabContainer", "TabBar"]:
		var sel := _btn_box(Color(gold.r, gold.g, gold.b, 0.1), gold, 0)
		sel.border_width_bottom = 2
		sel.set_corner_radius_all(6)
		sel.corner_radius_bottom_left = 0
		sel.corner_radius_bottom_right = 0
		t.set_stylebox("tab_selected", type, sel)
		t.set_stylebox("tab_unselected", type, _btn_box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0))
		t.set_stylebox("tab_hovered", type, _btn_box(Color(1, 1, 1, 0.05), Color(0, 0, 0, 0), 0))
		t.set_stylebox("tab_disabled", type, _btn_box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0))
		t.set_stylebox("tab_focus", type, StyleBoxEmpty.new())
		t.set_color("font_selected_color", type, gold)
		t.set_color("font_unselected_color", type, dim.lightened(0.1))
		t.set_color("font_hovered_color", type, text)
		if bold:
			t.set_font("font", type, bold)
	var tp := box(Color(0.05, 0.055, 0.08, 0.7), Color(0, 0, 0, 0), "card")
	tp.corner_radius_top_left = 0
	t.set_stylebox("panel", "TabContainer", tp)
	t.set_stylebox("tabbar_background", "TabContainer", StyleBoxEmpty.new())
	# text fields
	for type in ["LineEdit", "TextEdit"]:
		var n := _btn_box(sunk, edge, 1)
		t.set_stylebox("normal", type, n)
		var f := _btn_box(sunk, Color(gold.r, gold.g, gold.b, 0.8), 1)
		t.set_stylebox("focus", type, f)
		t.set_stylebox("read_only", type, _btn_box(Color(sunk.r, sunk.g, sunk.b, 0.5), edge, 1))
		t.set_color("font_color", type, text)
		t.set_color("font_placeholder_color", type, Color(dim.r, dim.g, dim.b, 0.7))
		t.set_color("caret_color", type, gold)
		t.set_color("selection_color", type, Color(gold.r, gold.g, gold.b, 0.3))
	# scrollbars: thin, rounded, out of the way until you reach for them
	for type in ["VScrollBar", "HScrollBar"]:
		var tr := _flat(Color(1, 1, 1, 0.03), 4)
		tr.content_margin_left = 3
		tr.content_margin_right = 3
		tr.content_margin_top = 3
		tr.content_margin_bottom = 3
		t.set_stylebox("scroll", type, tr)
		t.set_stylebox("scroll_focus", type, tr)
		t.set_stylebox("grabber", type, _flat(Color(1, 1, 1, 0.18), 4))
		t.set_stylebox("grabber_highlight", type, _flat(Color(gold.r, gold.g, gold.b, 0.6), 4))
		t.set_stylebox("grabber_pressed", type, _flat(Color(gold.r, gold.g, gold.b, 0.85), 4))
	# panels, tooltips, popups, separators
	t.set_stylebox("panel", "PanelContainer", box(col("ink", Color(0.035, 0.04, 0.06, 0.94))))
	t.set_stylebox("panel", "Panel", box(col("ink", Color(0.035, 0.04, 0.06, 0.94))))
	var tip := box(Color(0.04, 0.045, 0.065, 0.97), gold, "card")
	tip.set_content_margin_all(10)
	t.set_stylebox("panel", "TooltipPanel", tip)
	t.set_color("font_color", "TooltipLabel", text)
	t.set_stylebox("panel", "PopupMenu", box(Color(0.05, 0.055, 0.08, 0.98), edge, "card"))
	t.set_stylebox("hover", "PopupMenu", _flat(Color(gold.r, gold.g, gold.b, 0.15), 6))
	t.set_color("font_color", "PopupMenu", text)
	t.set_color("font_hover_color", "PopupMenu", Color(1.0, 0.94, 0.78))
	var sep := StyleBoxLine.new()
	sep.color = Color(1, 1, 1, 0.08)
	sep.thickness = 1
	t.set_stylebox("separator", "HSeparator", sep)
	t.set_constant("separation", "HSeparator", 10)
	# sliders (settings)
	var sl := _flat(Color(1, 1, 1, 0.08), 3)
	sl.content_margin_top = 3
	sl.content_margin_bottom = 3
	t.set_stylebox("slider", "HSlider", sl)
	t.set_stylebox("grabber_area", "HSlider", _flat(Color(gold.r, gold.g, gold.b, 0.7), 3))
	t.set_stylebox("grabber_area_highlight", "HSlider", _flat(gold, 3))
	# progress bars (each bar sets its own colour: bar_style)
	t.set_stylebox("background", "ProgressBar", _flat(col("track", Color(0.06, 0.06, 0.08, 0.9)), int(num("radius", "bar", 6))))
	t.set_stylebox("fill", "ProgressBar", _flat(Color(0.55, 0.75, 0.95), int(num("radius", "bar", 6))))
	# text
	t.set_color("font_color", "Label", text)
	t.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.85))
	t.set_color("default_color", "RichTextLabel", text)
	if bold:
		t.set_font("bold_font", "RichTextLabel", bold)
	if body:
		t.set_font("normal_font", "RichTextLabel", body)
	t.set_constant("line_spacing", "Label", 2)
	return t


# ---- bars --------------------------------------------------------------------------------------

static func bar_style(b: ProgressBar, color: Color) -> void:
	## a rounded fill with a little light along its top edge; the track
	## behind it is drawn by the trail (so the trail sits between them)
	var r := int(num("radius", "bar", 6))
	var fill := _flat(color, r)
	fill.border_width_top = 1
	fill.border_color = color.lightened(0.4)
	fill.border_blend = true
	b.add_theme_stylebox_override("fill", fill)
	var bg := _flat(col("track", Color(0.06, 0.06, 0.08, 0.9)), r)
	bg.set_border_width_all(1)
	bg.border_color = col("edge", Color(1, 1, 1, 0.07))
	b.add_theme_stylebox_override("background", bg)


static func trail(b: ProgressBar) -> ProgressBar:
	## a pale bar behind the real one that catches up a moment after a drop --
	## you see what the hit took. Draws the track (behind the parent).
	var g := ProgressBar.new()
	g.name = "Trail"
	g.show_percentage = false
	g.show_behind_parent = true
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	g.set_anchors_preset(Control.PRESET_FULL_RECT)
	var r := int(num("radius", "bar", 6))
	var bg = b.get_theme_stylebox("background")
	if bg:
		g.add_theme_stylebox_override("background", bg)
	var gf := _flat(Color(1.0, 0.93, 0.8, 0.5), r)
	g.add_theme_stylebox_override("fill", gf)
	b.add_theme_stylebox_override("background", StyleBoxEmpty.new())
	g.max_value = b.max_value
	g.value = b.value
	b.add_child(g)
	b.set_meta("trail", g)
	return g


static func set_bar(b: ProgressBar, value: float, max_v: float = -1.0) -> void:
	## the bar shows the truth at once; its trail eases down after it
	if max_v > 0.0:
		b.max_value = max_v
	b.value = value
	var g = b.get_meta("trail") if b.has_meta("trail") else null
	if g == null or not is_instance_valid(g):
		return
	g.max_value = b.max_value
	if b.value >= g.value or not b.is_inside_tree():
		if g.has_meta("tw") and is_instance_valid(g.get_meta("tw")):
			(g.get_meta("tw") as Tween).kill()
		g.value = b.value
		return
	if g.has_meta("tw") and is_instance_valid(g.get_meta("tw")) and (g.get_meta("tw") as Tween).is_running():
		if is_equal_approx(float(g.get_meta("to", -1.0)), b.value):
			return
		(g.get_meta("tw") as Tween).kill()
	var tw: Tween = g.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_interval(num("motion", "bar_trail_wait", 0.35))
	tw.tween_property(g, "value", b.value, num("motion", "bar_trail", 0.45)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	g.set_meta("tw", tw)
	g.set_meta("to", b.value)


# ---- motion ------------------------------------------------------------------------------------

static func pop_in(c: Control) -> void:
	## a window opening: it rises a little and fades in
	if c == null or not c.is_inside_tree():
		return
	if c.has_meta("_pop") and is_instance_valid(c.get_meta("_pop")):
		(c.get_meta("_pop") as Tween).kill()
	var dur := num("motion", "open", 0.18)
	var s0 := num("motion", "open_scale", 0.975)
	c.modulate.a = 0.0
	c.scale = Vector2(s0, s0)
	c.pivot_offset = c.size * 0.5
	var tw: Tween = c.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "modulate:a", 1.0, dur)
	var grow := func(s: float):
		if is_instance_valid(c):
			c.pivot_offset = c.size * 0.5
			c.scale = Vector2(s, s)
	tw.tween_method(grow, s0, 1.0, dur)
	c.set_meta("_pop", tw)


static func animate_opens(c: Control) -> void:
	## every time this window is shown, it eases in
	if c == null or c.has_meta("_pops"):
		return
	c.set_meta("_pops", true)
	c.visibility_changed.connect(func():
		if is_instance_valid(c) and c.visible:
			pop_in(c)
		elif is_instance_valid(c):
			c.modulate.a = 1.0
			c.scale = Vector2.ONE)


static func slide_in(c: Control, from_x: float = -1.0) -> void:
	## a menu page arriving: slides across and fades in
	if c == null or not c.is_inside_tree():
		return
	if c.has_meta("_slide") and is_instance_valid(c.get_meta("_slide")):
		(c.get_meta("_slide") as Tween).kill()
	var dx := num("motion", "page_slide", 18.0) if from_x < 0.0 else from_x
	var dur := num("motion", "page", 0.16)
	c.modulate.a = 0.0
	c.position.x = dx
	var tw: Tween = c.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "modulate:a", 1.0, dur)
	tw.tween_property(c, "position:x", 0.0, dur)
	c.set_meta("_slide", tw)


static func juice(b: BaseButton) -> void:
	## the pointer warms a button (it brightens, smoothly); pressing it gives a little
	if b == null or b.has_meta("_juice"):
		return
	b.set_meta("_juice", true)
	var glow := num("motion", "hover_glow", 1.12)
	var dur := num("motion", "hover", 0.12)
	var to := func(v: float):
		if not is_instance_valid(b) or not b.is_inside_tree():
			return
		if b.has_meta("_jt") and is_instance_valid(b.get_meta("_jt")):
			(b.get_meta("_jt") as Tween).kill()
		var tw: Tween = b.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw.tween_property(b, "self_modulate", Color(v, v, v, 1.0), dur)
		b.set_meta("_jt", tw)
	var warm := func():
		if is_instance_valid(b) and not b.disabled:
			to.call(glow)
	var cool := func():
		to.call(1.0)
	b.mouse_entered.connect(warm)
	b.mouse_exited.connect(cool)
	b.focus_entered.connect(warm)
	b.focus_exited.connect(cool)
	var ps := num("motion", "press_scale", 0.97)
	b.button_down.connect(func():
		if is_instance_valid(b) and not (b.get_parent() is Container):
			b.pivot_offset = b.size * 0.5
			b.scale = Vector2(ps, ps))
	b.button_up.connect(func():
		if is_instance_valid(b) and not (b.get_parent() is Container):
			var tw: Tween = b.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw.tween_property(b, "scale", Vector2.ONE, 0.14))


static func watch(tree: SceneTree) -> void:
	## every button made from now on gets the hover glow and the press
	if _watching or tree == null:
		return
	_watching = true
	tree.node_added.connect(func(n):
		if n is BaseButton:
			juice(n))


static func fade_line(l: Control) -> void:
	## a new line in the message log slides in from the left
	if l == null:
		return
	l.modulate.a = 0.0
	var tw: Tween = l.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 1.0, num("motion", "log_in", 0.22))


static func nudge_in(c: Control, from: Vector2) -> void:
	## slide a little from 'from' (relative) into its place, fading in -- after
	## one frame, so its place is known
	if c == null or not c.is_inside_tree():
		return
	c.modulate.a = 0.0
	var go := func():
		if not is_instance_valid(c):
			return
		var home := c.position
		c.position = home + from
		var tw: Tween = c.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(c, "position", home, num("motion", "open", 0.18) * 1.6)
		tw.tween_property(c, "modulate:a", 1.0, num("motion", "open", 0.18))
	go.call_deferred()


static func stagger(box: Control) -> void:
	## each line of a column fades in a beat after the one above it
	if box == null or not box.is_inside_tree():
		return
	var i := 0
	var step := num("motion", "stagger", 0.06)
	for ch in box.get_children():
		if not (ch is CanvasItem):
			continue
		var ci: CanvasItem = ch
		ci.modulate.a = 0.0
		var tw: Tween = ci.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		tw.tween_interval(0.05 + step * i)
		tw.tween_property(ci, "modulate:a", 1.0, 0.25).set_trans(Tween.TRANS_SINE)
		i += 1
