extends PanelContainer
## Round 188: the guild chat on screen while you play -- the last few lines, bottom-left above the message log. It
## fades when the chat is quiet and comes back with the next line. Enter: type to the guild (Enter sends, Esc cancels).
## F6 opens the whole Guild page.

const SHOW_SECONDS := 14.0
const LINES := 6
var hud
var typing := false
var _feed: RichTextLabel
var _in: LineEdit
var _quiet := 999.0


func setup(h) -> void:
	hud = h
	name = "ChatBox"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.045, 0.06, 0.55)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(8)
	add_theme_stylebox_override("panel", sb)
	set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	custom_minimum_size = Vector2(440, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(v)
	_feed = RichTextLabel.new()
	_feed.bbcode_enabled = true
	_feed.fit_content = true
	_feed.scroll_active = false
	_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_feed.custom_minimum_size = Vector2(424, 0)
	_feed.add_theme_font_size_override("normal_font_size", 14)
	_feed.add_theme_font_size_override("italics_font_size", 13)
	v.add_child(_feed)
	_in = LineEdit.new()
	_in.max_length = 200
	_in.placeholder_text = I18n.t("To the guild (Enter sends, Esc cancels)")
	_in.visible = false
	_in.text_submitted.connect(func(_t): _send())
	_in.gui_input.connect(_on_in_input)
	v.add_child(_in)
	visible = false
	var FS = Game.sys("fellowship")
	if FS != null:
		FS.chat_added.connect(func(_l): _refresh(true))
	_place()
	get_viewport().size_changed.connect(_place)


func _place() -> void:
	## above the message log (HUD._log sits 306 px up from the bottom)
	position = Vector2(16, get_viewport().get_visible_rect().size.y - 306.0 - 8.0 - maxf(size.y, 60.0))


func _refresh(fresh: bool) -> void:
	var FS = Game.sys("fellowship")
	if FS == null:
		return
	var ls: Array = FS.lines("", LINES)
	if ls.is_empty() and not typing:
		visible = false
		return
	_feed.clear()
	for l in ls:
		_feed.append_text(_line(l) + "\n")
	if fresh:
		_quiet = 0.0
	visible = not _hub_open()
	modulate.a = 1.0
	_place.call_deferred()


func _line(l: Dictionary) -> String:
	## (the same colours as the Guild page)
	var who := str(l.get("who", ""))
	var text := str(l.get("text", "")).replace("[", "[lb]")
	match str(l.get("kind", "line")):
		"sys":
			return "[i][color=#9aa3b5]%s[/color][/i]" % text
		"sect":
			return "[color=#7fe0c8]%s[/color]" % text
		"gift", "trade":
			return "[color=#ffd27a]%s[/color]" % text
		"you":
			return "[color=#a8d8ff][b]%s[/b][/color]: %s" % [who.replace("[", "[lb]"), text]
		"online":
			return "[color=#9cff9c]● %s[/color]: %s" % [who.replace("[", "[lb]"), text]
	if str(l.get("ch", "")) == "sect":
		return "[color=#7fe0c8]%s[/color]" % text
	var col := Color.from_hsv(float(abs(hash(who)) % 360) / 360.0, 0.45, 1.0)
	return "[color=#%s][b]%s[/b][/color]: %s" % [col.to_html(false), who.replace("[", "[lb]"), text]


func _hub_open() -> bool:
	return hud != null and hud._hub != null and hud._hub.visible


func start_typing() -> void:
	var FS = Game.sys("fellowship")
	if FS == null or not FS.in_guild():
		Game.message.emit(I18n.t("No guild yet -- menu > Guild (F6) to join one or found your own."))
		return
	typing = true
	_in.visible = true
	_in.text = ""
	_refresh(true)
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_in.grab_focus.call_deferred()


func stop_typing() -> void:
	typing = false
	_in.visible = false
	_in.release_focus()
	if not hud.is_blocking():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if not preload("res://scripts/ui/TouchUI.gd").wanted() else Input.MOUSE_MODE_VISIBLE
	_place.call_deferred()


func _send() -> void:
	var t := _in.text.strip_edges()
	if t != "":
		Game.sys("fellowship").say(t)
	stop_typing()


func _on_in_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and (ev as InputEventKey).keycode == KEY_ESCAPE:
		stop_typing()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if typing:
		return
	if _hub_open():
		visible = false
		return
	_quiet += delta
	if _quiet < SHOW_SECONDS:
		if not visible and Game.sys("fellowship") != null and not Game.sys("fellowship").chat.is_empty():
			visible = true
		modulate.a = 1.0 if _quiet < SHOW_SECONDS - 2.0 else clampf((SHOW_SECONDS - _quiet) / 2.0, 0.0, 1.0)
	elif visible:
		visible = false
