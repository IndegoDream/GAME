extends PanelContainer
## The menu (round 39). Robert, 2026-10-04: "I want the menus to be more
## intuitive and fluid and make sense, make things more snappy, more
## responsive. We actually need a more in-depth menu screen that could help
## just organize it."
##
## One screen, sections down the left side:
##   You (P)         the character sheet: stats and where they come from
##   Pack (I)        what you wear and carry; bench, forge, nanoforge, formulas, runes
##   Party (O)       your companions (a party of two), the roster, contract beasts, taming
##   Bonds (U)       everyone who knows you, and how well
##   Road (L)        the road down: the chapter, the next gate, errands, the story, masters
##   Journal (N)     the long record: skills, elements, places, goals
##   Meridians (K)   the Meridian Lattice and your arts
##   System          save, settings, plan your time away, the keys, quit
## Tab opens it where you left it; each key jumps straight to its section
## (press it again to close); Q / E (or the shoulder buttons) flip sections;
## Esc closes. The old windows live inside it as pages -- every way in
## that used to open them still does, it just opens here.

var hud
var rail: VBoxContainer
var holder: Control
var header: Label
var hint: Label
var pages := {}                 # section -> Control
var buttons := {}               # section -> Button
var current := ""
var last := "You"
var _party: VBoxContainer
var _bonds: VBoxContainer
var _road: VBoxContainer
var _system: VBoxContainer
var _mind: VBoxContainer
var _spirit: VBoxContainer
var _swarm: VBoxContainer
var _world: VBoxContainer           # round 44
var _quests: VBoxContainer          # round 52: side quests
var _craft: VBoxContainer           # round 137: the crafting journal
var _dao: VBoxContainer             # round 139: dao sense and the eight daos
var _map: Control                   # round 75: the map
var swarm_branch := ""          # the Swarm page's filter ("" = every branch)
var _stable_pick := -1
var _confirm_release := -1      # a release needs a second press
var _dirty := false

const ORDER := ["You", "Spirit", "Dao", "Mind", "Meridians", "Swarm", "Path", "Pack", "Party", "Bonds", "Quests", "Road", "Journal", "Craft", "Map", "World", "Guide", "System"]     # round 119: grouped, so the rail reads in three parts
const GROUP_AT := {"You": "CHARACTER", "Pack": "PEOPLE AND GEAR", "Quests": "JOURNEY"}
const PageTabs := preload("res://scripts/ui/PageTabs.gd")
const Guide := preload("res://scripts/systems/Guide.gd")
var _guide: VBoxContainer              # round 120: the optional lessons
var _path: VBoxContainer               # round 121: the Paths (classes)
var nextline: Label                    # round 120: "NEXT: ..." under the header
var help_btn: Button
var _tour_layer: Control
var _tour_card: PanelContainer
var _tour := {}                        # the lesson being walked, {} = none
var _tour_i := 0
var _offer_shown := {}
const KEYS := {"You": "P", "Spirit": "", "Dao": "", "Pack": "I", "Party": "O", "Bonds": "U", "Road": "L", "Quests": "", "World": "", "Map": "F2", "Mind": "", "Swarm": "Y", "Path": "", "Journal": "N", "Craft": "", "Meridians": "K", "Guide": "", "System": "Esc"}
const COL := {"You": Color(1.0, 0.85, 0.5), "Pack": Color(0.6, 0.85, 1.0), "Party": Color(0.75, 1.0, 0.8), "Bonds": Color(1.0, 0.75, 0.85),
	"Road": Color(1.0, 0.9, 0.6), "Quests": Color(1.0, 0.82, 0.45), "Journal": Color(0.95, 0.85, 0.65), "Craft": Color(1.0, 0.78, 0.5), "Meridians": Color(0.6, 0.85, 1.0), "System": Color(0.8, 0.8, 0.9),
	"Mind": Color(0.85, 0.75, 1.0), "Swarm": Color(0.5, 1.0, 0.9), "Spirit": Color(0.7, 0.95, 0.75), "Dao": Color(0.72, 0.85, 1.0), "World": Color(0.75, 0.9, 1.0), "Map": Color(0.8, 0.95, 0.7), "Guide": Color(1.0, 0.95, 0.6), "Path": Color(1.0, 0.8, 0.5)}


func setup(h) -> void:
	hud = h
	Game.language_changed.connect(_on_language_changed)
	name = "Hub"
	add_theme_stylebox_override("panel", hud._box(Color(0.03, 0.035, 0.05, 0.985), Color(0.45, 0.6, 0.8)))
	set_anchors_preset(Control.PRESET_FULL_RECT)
	offset_left = 12
	offset_top = 10
	offset_right = -12
	offset_bottom = -10
	visible = false
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 6)
	add_child(outer)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	outer.add_child(top)
	header = hud._label(top, "", 16, Color(0.92, 0.92, 0.95))
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.clip_text = true
	help_btn = Button.new()                         # round 120: a lesson for whatever page you are on
	help_btn.text = I18n.t("? Help")
	help_btn.tooltip_text = I18n.t("A short, optional walk-through of this page")
	help_btn.add_theme_font_size_override("font_size", 14)
	help_btn.pressed.connect(_on_help)
	top.add_child(help_btn)
	hint = hud._label(top, I18n.t("Q / E switch   ·   Tab or Esc close"), 13, Color(0.6, 0.65, 0.75))
	nextline = hud._label(outer, "", 14, Color(1.0, 0.95, 0.65))
	nextline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nextline.visible = false
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(body)
	var rail_box := PanelContainer.new()
	var rsb: StyleBoxFlat = preload("res://scripts/core/UiStyle.gd").box(Color(0.055, 0.06, 0.085, 0.92), Color(0, 0, 0, 0), "card")
	rsb.set_content_margin_all(8)
	rail_box.add_theme_stylebox_override("panel", rsb)
	body.add_child(rail_box)
	rail = VBoxContainer.new()
	rail.add_theme_constant_override("separation", 4)
	rail.custom_minimum_size = Vector2(124, 0)
	rail_box.add_child(rail)
	var grp := ButtonGroup.new()
	for sec in ORDER:
		if GROUP_AT.has(sec) and get_viewport_rect().size.y >= 680.0:
			var cap := Label.new()
			cap.text = str(GROUP_AT[sec])
			cap.add_theme_font_size_override("font_size", 11)
			cap.add_theme_color_override("font_color", Color(0.5, 0.58, 0.7))
			cap.custom_minimum_size = Vector2(0, 20)
			cap.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
			rail.add_child(cap)
		var b := Button.new()
		b.text = _rail_text(sec)
		b.toggle_mode = true
		b.button_group = grp
		b.theme_type_variation = "RailButton"          # round 49: quiet until chosen, then a gold bar
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 15)
		b.add_theme_color_override("font_pressed_color", COL[sec])
		b.add_theme_color_override("font_hover_pressed_color", COL[sec])
		b.custom_minimum_size = Vector2(124, 32)
		b.focus_mode = Control.FOCUS_ALL
		b.pressed.connect(func(): show_page(sec))
		rail.add_child(b)
		buttons[sec] = b
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rail.add_child(sp)
	var close := Button.new()
	close.text = I18n.t("Close   Tab")
	close.add_theme_font_size_override("font_size", 14)
	close.pressed.connect(close_hub)
	rail.add_child(close)
	holder = Control.new()
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	holder.clip_contents = true
	body.add_child(holder)
	_party = _scroll_page("Party")
	_bonds = _scroll_page("Bonds")
	_road = _scroll_page("Road")
	_system = _scroll_page("System")
	_mind = _scroll_page("Mind")              # round 40
	_spirit = _scroll_page("Spirit")
	_swarm = _scroll_page("Swarm")
	_world = _scroll_page("World")            # round 44: the day, the peoples, the camps, the old age
	_guide = _scroll_page("Guide")            # round 120
	_path = _scroll_page("Path")              # round 121
	_quests = _scroll_page("Quests")          # round 52: side quests
	_dao = _scroll_page("Dao")                # round 139
	_dao.add_theme_constant_override("separation", 10)
	_craft = _scroll_page("Craft")            # round 137: recipes, herbology, supplies, bestiary
	_craft.add_theme_constant_override("separation", 10)
	_map = preload("res://scripts/ui/MapScreen.gd").new()          # round 75: where you've been
	_map.setup(hud)
	adopt("Map", _map)
	_tour_layer = Control.new()                # round 120: the lesson card floats over every page
	_tour_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tour_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_tour_layer)
	Game.stats_changed.connect(_mark)
	Game.familiar_changed.connect(_mark)
	Game.companion_changed.connect(_mark)


func adopt(sec: String, panel: Control) -> void:
	## an existing window becomes a page: fills the space, no frame of its own
	if panel.get_parent():
		panel.get_parent().remove_child(panel)
	holder.add_child(panel)
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.position = Vector2.ZERO
	panel.offset_left = 0
	panel.offset_top = 0
	panel.offset_right = 0
	panel.offset_bottom = 0
	panel.custom_minimum_size = Vector2.ZERO
	panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	panel.visible = false
	for sc in panel.find_children("*", "ScrollContainer", false, false):
		(sc as Control).custom_minimum_size = Vector2.ZERO
		(sc as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		(sc as Control).size_flags_vertical = Control.SIZE_EXPAND_FILL
	pages[sec] = panel


func _scroll_page(sec: String) -> VBoxContainer:
	var sc := ScrollContainer.new()
	sc.name = sec
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.set_anchors_preset(Control.PRESET_FULL_RECT)
	sc.visible = false
	holder.add_child(sc)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 10)          # round 139: room to breathe
	sc.add_child(v)
	pages[sec] = sc
	return v


# ---- opening, switching, closing -------------------------------------------------------

func _rail_text(sec: String) -> String:
	return "%s   %s" % [tr(sec), KEYS[sec]] if KEYS[sec] != "Esc" and KEYS[sec] != "" else tr(sec)


func _on_language_changed() -> void:
	## round 140: the rail and the open page say it in the new language
	for sec in ORDER:
		if buttons.has(sec):
			buttons[sec].text = _rail_text(sec)
	if visible:
		_fill(current)
		_header()


func show_page(sec: String) -> void:
	if not pages.has(sec):
		return
	var was := visible
	if not was:
		visible = true                       # (round 49: it rises and fades in -- UiStyle.animate_opens)
		Game.sfx("ui_open", 0.45)
		hud._log.visible = false
	elif sec != current:
		Game.sfx("ui_select", 0.35)
	for k in pages:
		pages[k].visible = (k == sec)
	if was and sec != current:
		preload("res://scripts/core/UiStyle.gd").slide_in(pages[sec])      # round 49: the page slides across
	if sec != current:
		Game.log_event("menu_open", {"page": sec})        # round 163: the first-hour guide notices a menu opened
	current = sec
	if sec != "System":
		last = sec
	for k in buttons:                        # (round 49: exactly one lit -- set_pressed_no_signal doesn't release the others)
		if buttons[k].button_pressed != (k == sec):
			buttons[k].set_pressed_no_signal(k == sec)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_fill(sec)
	_header()
	hud.pad_focus.call_deferred(rail)


func toggle_page(sec: String) -> void:
	if visible and current == sec:
		close_hub()
	else:
		show_page(sec)


func toggle() -> void:
	if visible:
		close_hub()
	else:
		show_page(last)


func close_hub() -> void:
	if not visible:
		return
	visible = false
	for k in pages:
		pages[k].visible = false
	current = ""
	end_lesson()
	Game.at_bench = ""
	_stable_pick = -1
	_confirm_release = -1
	hud._log.visible = true
	Game.sfx("ui_close", 0.4)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if hud.is_blocking() else Input.MOUSE_MODE_CAPTURED


func step(d: int) -> void:
	var i := ORDER.find(current)
	show_page(ORDER[(i + d + ORDER.size()) % ORDER.size()])


func _mark() -> void:
	## something changed: the open page refreshes once, next frame (not once per change)
	if visible and not _dirty and current in ["Party", "Bonds", "Road", "Mind", "Swarm", "Spirit", "World", "Guide", "Path"]:
		_dirty = true
		_refill.call_deferred()
	elif visible:
		_header.call_deferred()


func _refill() -> void:
	_dirty = false
	if visible and current != "":
		_fill(current)
		_header()


func _header() -> void:
	header.text = I18n.t("%s%s   ·   HP %d / %d   ·   Qi %d / %d   ·   %d gold   ·   %s") % [(Game.char_name + "  --  ") if Game.char_name != "" else "",
		Game.cultivation_label(), Game.hp, Game.max_hp(), int(Game.qi), int(Game.qi_to_next()), Game.gold, Game.current_level.capitalize() if Game.current_level != "village" else "Eliet"]
	_next_line()


func _fill(sec: String) -> void:
	_fill_raw(sec)
	_fit.call_deferred(sec)


func _fit(sec: String) -> void:
	## round 174: every page fits whatever the screen -- long lines wrap, wide rows stack or flow
	var pg: Control = pages.get(sec)
	if pg == null or not is_instance_valid(pg) or holder == null or not pg.is_visible_in_tree():
		return
	var lim: float = holder.size.x - 16.0
	if lim < 80.0:
		return
	for n in pg.find_children("*", "Label", true, false):
		var l := n as Label
		if l.autowrap_mode == TextServer.AUTOWRAP_OFF and l.text.length() > 28 and l.get_combined_minimum_size().x > lim * 0.45:
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			l.custom_minimum_size.x = 0.0
		elif l.autowrap_mode != TextServer.AUTOWRAP_OFF and l.custom_minimum_size.x > lim * 0.3 and lim < 1100.0:
			l.custom_minimum_size.x = 0.0                  # a wrapping line takes whatever room there is
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		elif l.custom_minimum_size.x > lim:
			l.custom_minimum_size.x = lim * 0.9
	for n in pg.find_children("*", "Button", true, false):
		var b := n as Button
		if b.text.length() > 26 and b.get_combined_minimum_size().x > lim * 0.7:
			b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			b.clip_text = false
			b.custom_minimum_size.x = minf(b.custom_minimum_size.x, lim * 0.7)
		elif b.custom_minimum_size.x > lim:
			b.custom_minimum_size.x = lim * 0.9
	for n in pg.find_children("*", "GridContainer", true, false):
		var g := n as GridContainer
		while g.columns > 1 and g.get_combined_minimum_size().x > lim:
			g.columns -= 1
	for _pass in 3:
		var changed := false
		for n in pg.find_children("*", "HBoxContainer", true, false):
			var h := n as HBoxContainer
			if h == null or not is_instance_valid(h) or h.is_queued_for_deletion() or h.get_child_count() < 2 or not h.is_visible_in_tree():
				continue
			if h.get_combined_minimum_size().x <= lim:
				continue
			_shrink_row(h, lim)
			if h.get_combined_minimum_size().x <= lim:
				changed = true
				continue
			var all_buttons := true
			for c in h.get_children():
				if not (c is Button):
					all_buttons = false
			if all_buttons and h.get_parent() != null:
				_to_flow(h)
			else:
				_to_stack(h)
			changed = true
		if not changed:
			break


func _shrink_row(h: HBoxContainer, lim: float) -> void:
	## squeeze the big fixed-size parts of a row (a drawing, a text column) before giving up and stacking it
	var kids: Array = h.get_children().filter(func(c): return c is Control and (c as Control).custom_minimum_size.x > 260.0)
	kids.sort_custom(func(a, b): return (a as Control).custom_minimum_size.x > (b as Control).custom_minimum_size.x)
	for c in kids:
		var deficit: float = h.get_combined_minimum_size().x - lim
		if deficit <= 0.0:
			return
		var cc := c as Control
		var w: float = cc.custom_minimum_size.x
		var nw: float = maxf(260.0, w - deficit)
		if nw >= w:
			continue
		var square: bool = absf(cc.custom_minimum_size.y - w) < 2.0
		cc.custom_minimum_size.x = nw
		if square:
			cc.custom_minimum_size.y = nw


func _to_stack(h: HBoxContainer) -> void:
	## a row that is too wide for the screen becomes a column
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.size_flags_vertical = h.size_flags_vertical
	v.add_theme_constant_override("separation", 8)
	var par: Node = h.get_parent()
	if par == null:
		return
	var idx: int = h.get_index()
	for c in h.get_children():
		h.remove_child(c)
		v.add_child(c)
		if c is Control:
			(c as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var scrolled := false
	var anc: Node = par
	while anc != null and anc != holder:
		if anc is ScrollContainer:
			scrolled = true
			break
		anc = anc.get_parent()
	var top: Control = v
	if not scrolled:                       # a stacked page with no scroll of its own would hide what is below the fold
		var sc := ScrollContainer.new()
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
		sc.add_child(v)
		top = sc
	par.add_child(top)
	par.move_child(top, idx)
	par.remove_child(h)
	h.queue_free()


func _to_flow(h: HBoxContainer) -> void:
	var f := HFlowContainer.new()
	f.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	f.add_theme_constant_override("h_separation", 6)
	f.add_theme_constant_override("v_separation", 6)
	var par: Node = h.get_parent()
	var idx: int = h.get_index()
	for c in h.get_children():
		h.remove_child(c)
		f.add_child(c)
	par.add_child(f)
	par.move_child(f, idx)
	par.remove_child(h)
	h.queue_free()


func _fill_raw(sec: String) -> void:
	match sec:
		"You":
			hud.fill_character()
		"Pack":
			hud._kit._refresh_now()
		"Journal":
			hud.fill_journal()
		"Meridians":
			hud._fill_lattice()
		"Party":
			fill_party()
		"Bonds":
			fill_bonds()
		"Road":
			fill_road()
		"System":
			fill_system()
		"Mind":
			fill_mind()
		"Spirit":
			fill_spirit()
		"Swarm":
			fill_swarm()
		"World":
			fill_world()
		"Guide":
			fill_guide()
		"Path":
			fill_path()
		"Quests":
			fill_quests()
		"Craft":
			fill_craft()
		"Dao":
			fill_dao()
		"Map":
			_map.refresh()
	var tabbed := {"Party": _party, "Road": _road, "Quests": _quests, "Mind": _mind, "Spirit": _spirit, "World": _world, "Craft": _craft}     # round 119: long pages become tabs
	if tabbed.has(sec):
		PageTabs.apply(tabbed[sec], sec, COL[sec])
	elif sec == "Journal":
		PageTabs.apply(hud._jr_body, "Journal", COL[sec])


# ---- round 120: the optional Guide -------------------------------------------------------

func _next_line() -> void:
	## "NEXT: ..." under the header: what to do on this page, from the real state of the game
	if nextline == null:
		return
	var t := ""
	if Guide.hints_on():
		t = Guide.next_hint(current)
		if t != "" and Guide.lesson_for_page(current) != "" and current in ["Meridians", "Mind", "Swarm", "Path"]:
			if not Game.has_flag("guide:offered:" + current) or _offer_shown.has(current):
				_offer_shown[current] = true
				Game.set_flag("guide:offered:" + current)
				t += I18n.t("     (New to this page? ? Help gives a one-minute tour -- optional.)")
	nextline.text = ("▸ " + t) if t != "" else ""
	nextline.visible = t != ""
	help_btn.visible = current != "Guide" and current != "Map"


func _on_help() -> void:
	var lid := Guide.lesson_for_page(current)
	if lid == "":
		show_page("Guide")
	else:
		start_lesson(lid)


func fill_guide() -> void:
	_clear(_guide)
	_t(_guide, "Guide -- short lessons, only if you want them", COL["Guide"])
	_p(_guide, "Nothing here opens by itself. Pick a lesson and a small card walks you through it one step at a time, jumping to the real page as it goes. Press End guide any time. The ? Help button on a page starts the lesson for that page.", Color(0.85, 0.88, 0.9), 14)
	var tr := _row(_guide)
	_btn(tr, I18n.t("Page hints (the yellow NEXT line): %s") % ("ON" if Guide.hints_on() else "OFF"), func():
		Guide.set_hints(not Guide.hints_on())
		_fill("Guide")
		_header(), false, "A one-line suggestion at the top of the Meridians, Mind and Swarm pages")
	if not _tour.is_empty():
		_btn(tr, I18n.t("End the guide now"), func():
			end_lesson()
			_fill("Guide"))
	for l in Guide.lessons():
		var v := _card(_guide, COL["Guide"])
		var r := _row(v)
		var tl := _h(r, str(l.get("title", "")), COL["Guide"].lightened(0.2), 17)
		tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hud._label(r, I18n.t("about %d min  ·  %d steps") % [int(l.get("mins", 1)), (l.get("steps", []) as Array).size()], 12, Color(0.65, 0.7, 0.75))
		_p(v, str(l.get("blurb", "")), Color(0.85, 0.88, 0.9), 13)
		_p(v, I18n.t("Steps: ") + "  ›  ".join((l.get("steps", []) as Array).map(func(x): return str(x.get("title", "")))), Color(0.62, 0.66, 0.72), 11)
		var id := str(l.get("id", ""))
		_btn(v, I18n.t("Start this lesson"), func(): start_lesson(id))


func start_lesson(id: String) -> void:
	var l := Guide.lesson(id)
	if l.is_empty():
		return
	_tour = l
	_tour_i = 0
	if _tour_card == null:
		_build_tour_card()
	_tour_show()


func end_lesson() -> void:
	_tour = {}
	_tour_i = 0
	if _tour_card != null:
		_tour_card.visible = false


var _tc_title: Label
var _tc_step: Label
var _tc_text: Label
var _tc_back: Button
var _tc_next: Button


func _build_tour_card() -> void:
	_tour_card = PanelContainer.new()
	_tour_card.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb: StyleBoxFlat = preload("res://scripts/core/UiStyle.gd").box(Color(0.1, 0.1, 0.05, 0.97), COL["Guide"], "card")
	sb.set_content_margin_all(14)
	sb.border_width_left = 3
	sb.border_width_top = 3
	sb.border_width_right = 3
	sb.border_width_bottom = 3
	_tour_card.add_theme_stylebox_override("panel", sb)
	_tour_card.anchor_left = 0.0
	_tour_card.anchor_right = 1.0
	_tour_card.anchor_top = 1.0
	_tour_card.anchor_bottom = 1.0
	_tour_card.offset_left = 150
	_tour_card.offset_right = -14
	_tour_card.offset_bottom = -14
	_tour_card.offset_top = -210
	_tour_card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_tour_layer.add_child(_tour_card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	_tour_card.add_child(v)
	_tc_title = hud._label(v, "", 12, Color(0.75, 0.72, 0.5))
	_tc_step = hud._label(v, "", 18, COL["Guide"])
	_tc_text = hud._label(v, "", 14, Color(0.92, 0.93, 0.95))
	_tc_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tc_text.custom_minimum_size = Vector2(400, 0)
	_tc_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", 8)
	v.add_child(r)
	_tc_back = _btn(r, I18n.t("Back"), func(): _tour_go(-1))
	_tc_next = _btn(r, I18n.t("Next"), func(): _tour_go(1))
	_btn(r, I18n.t("Show me"), func(): _tour_show())
	_btn(r, I18n.t("End guide"), func(): end_lesson())


func _tour_go(d: int) -> void:
	var steps: Array = _tour.get("steps", [])
	_tour_i += d
	if _tour_i >= steps.size():
		end_lesson()
		_say(I18n.t("Lesson done. Everything is in the Guide page if you want it again."))
		return
	_tour_i = maxi(_tour_i, 0)
	_tour_show()


func _tour_show() -> void:
	var steps: Array = _tour.get("steps", [])
	if _tour.is_empty() or steps.is_empty():
		return
	var st: Dictionary = steps[clampi(_tour_i, 0, steps.size() - 1)]
	_tour_card.visible = true
	_tc_title.text = I18n.t("%s   ·   step %d of %d   ·   optional -- End guide any time") % [str(_tour.get("title", "")), _tour_i + 1, steps.size()]
	_tc_step.text = str(st.get("title", ""))
	_tc_text.text = str(st.get("text", ""))
	_tc_back.disabled = _tour_i == 0
	_tc_next.text = I18n.t("Done") if _tour_i >= steps.size() - 1 else I18n.t("Next")
	var pg := str(st.get("page", ""))
	if pg != "" and pages.has(pg) and pg != current:
		show_page(pg)


# ---- little builders ---------------------------------------------------------------------

func _clear(box: Node) -> void:
	for c in box.get_children():
		c.queue_free()


func _h(box: Node, text: String, col: Color = Color(1.0, 0.85, 0.5), size: int = 20) -> Label:
	return hud._label(box, text, size, col)


func _t(box: Node, text: String, col: Color = Color(1.0, 0.85, 0.5)) -> Label:
	## page title: carved capitals, same on every page; "Name -- what it is" puts the second half underneath, quietly
	var parts: PackedStringArray = tr(text).split(" -- ", true, 1)
	var l: Label = hud._label(box, parts[0], 24, col)
	if parts.size() > 1:
		_p(box, parts[1].substr(0, 1).to_upper() + parts[1].substr(1), Color(0.62, 0.66, 0.74), 13)
	return l


func _p(box: Node, text: String, col: Color = Color(0.85, 0.87, 0.9), size: int = 14) -> Label:
	var l: Label = hud._label(box, text, size, col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(560, 0)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


func _card(box: Node, accent: Color) -> VBoxContainer:
	var pc := PanelContainer.new()
	var sb: StyleBoxFlat = preload("res://scripts/core/UiStyle.gd").box(Color(0.065, 0.07, 0.1, 0.95), Color(0, 0, 0, 0), "card")
	sb.border_width_left = 3
	sb.border_color = accent
	sb.set_content_margin_all(12)
	pc.add_theme_stylebox_override("panel", sb)
	pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(pc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	pc.add_child(v)
	return v


func _row(box: Node) -> HBoxContainer:
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", 6)
	box.add_child(r)
	return r


func _btn(box: Node, text: String, cb: Callable, disabled: bool = false, tip: String = "") -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 13)
	b.disabled = disabled
	b.tooltip_text = tip
	b.pressed.connect(cb)
	b.pressed.connect(func(): Game.sfx("ui_click", 0.4))
	box.add_child(b)
	return b


func _bar(box: Node, v: float, mx: float, col: Color, w: float = 200.0) -> ProgressBar:
	var b := ProgressBar.new()
	b.custom_minimum_size = Vector2(w, 12)
	b.show_percentage = false
	b.min_value = 0.0
	b.max_value = maxf(mx, 0.001)
	b.value = clampf(v, 0.0, mx)
	preload("res://scripts/core/UiStyle.gd").bar_style(b, col)      # round 49: rounded, a little light on top
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_child(b)
	return b


func _say(t: String) -> void:
	if t != "":
		Game.message.emit(t)
	_fill(current)
	_header()


# ---- Party: companions, the roster, contract beasts, taming ------------------------------

func fill_party() -> void:
	_clear(_party)
	_t(_party, "Companions", COL["Party"])
	_p(_party, I18n.t("Party: %d of %d.  %s") % [Game.party_size(), Game.party_cap(), "" if Game.party_cap() >= 2 else Game.second_slot_text()], Color(0.75, 0.8, 0.85), 13)
	for slot in [0, 1]:
		var cc: Dictionary = Game.cslot(slot)
		if cc.is_empty():
			if slot == 0 or Game.party_cap() >= 2:
				var e := _card(_party, Color(0.4, 0.45, 0.5))
				_p(e, "An empty place at your %s. Grow close to someone in a town and ask them along -- or call someone from your roster below, from any town." % ("shoulder" if slot == 0 else "camp (they wait there and search for you)"), Color(0.65, 0.68, 0.72), 13)
			continue
		var nm := str(cc.get("name", ""))
		var v := _card(_party, Color(1.0, 0.7, 0.85) if bool(cc.get("partner", false)) else Color(0.6, 0.85, 1.0))
		var t := _row(v)
		var tl := _h(t, nm + ("  (your partner)" if bool(cc.get("partner", false)) else ""), Color(1.0, 0.85, 0.9) if bool(cc.get("partner", false)) else Color(0.85, 0.95, 1.0), 18)
		tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hud._label(t, (I18n.t("walks at your shoulder") if slot == 0 else I18n.t("second in the party")) + (I18n.t("  ·  away exploring") if bool(cc.get("away", false)) else ""), 12, Color(0.6, 0.65, 0.7))
		var lr := _row(v)
		hud._label(lr, I18n.t("Life"), 12, Color(0.7, 0.7, 0.75))
		_bar(lr, float(Game.companion_hp(slot)), float(Game.companion_max_hp(slot)), Color(0.85, 0.3, 0.3), 160)
		hud._label(lr, I18n.t("Bond: %s") % Game.bond_stage(nm), 12, Color(1.0, 0.8, 0.85))
		_bar(lr, float(Game.bond(nm).get("warmth", 0.0)), 100.0, Color(1.0, 0.6, 0.75), 120)
		_p(v, "  ·  ".join(Game.companion_rows(slot).map(func(r): return "%s: %s" % [r[0], r[1]])), Color(0.85, 0.88, 0.9), 13)
		var MN = Game.sys("menagerie")
		if MN != null and MN.is_wayfarer(nm):
			for ml in MN.human_lines(nm):
				_p(v, ml, Color(0.9, 0.85, 0.7), 13)
			var mdi: Dictionary = MN.human_deed_info(nm)
			var mr := _row(v)
			_btn(mr, I18n.t("Ask: %s") % str(mdi.get("name", "")), func(): _say(MN.ask_human(nm)), float(mdi.get("left", 0.0)) > 0.0, str(mdi.get("desc", "")))
			if MN.oath_ready(nm):
				_btn(mr, I18n.t("Hear their oath"), func(): _say(MN.oath_text(nm) + "\n\n" + MN.swear(nm)))
			_story_row(v, nm)
		var sr := _row(v)
		hud._label(sr, I18n.t("Fights as"), 13, Color(0.7, 0.75, 0.8))
		var S: Dictionary = Game.companions_data().get("styles", {})
		var ids: Array = S.keys()
		ids.sort()
		for sid in ids:
			var on: bool = sid == Game.companion_style(slot)
			_btn(sr, str(S[sid].get("name", sid)), func(): _say("" if Game.set_companion_style(str(sid), slot) else ""), on, str(S[sid].get("desc", "")))
		var gr := _row(v)
		var gear := []
		for id in Game.inventory:
			var tp := str(Game.item_def(str(id)).get("type", ""))
			if (tp == "weapon" or tp == "armor") and str(id) != Game.weapon and Game.equipped_count(str(id)) < Game.count(str(id)):
				gear.append(str(id))
		gear.sort()
		if gear.size() > 0:
			var ob := OptionButton.new()
			ob.custom_minimum_size = Vector2(220, 28)
			for i in gear.size():
				ob.add_item(Game.item_name(gear[i]))
				ob.set_item_metadata(i, gear[i])
			gr.add_child(ob)
			_btn(gr, I18n.t("Give"), func(): _say(Game.give_companion_gear(str(ob.get_item_metadata(ob.selected)), slot)))
		for gs in ["weapon", "armor"]:
			if Game.companion_gear(gs, slot) != "":
				_btn(gr, I18n.t("Take back their %s") % gs, func(): _say(Game.take_companion_gear(gs, slot)))
		var talk_row := _row(v)
		_btn(talk_row, I18n.t("Talk to %s") % nm, func():
			for cn in get_tree().get_nodes_in_group("companion_node"):
				if int(cn.slot) == slot:
					hud.close_kit()
					cn.talk()
					break)
		var SK = Game.sys("seek")
		if slot == 1:
			_p(v, I18n.t("Waits at camp -- only one human companion walks with you. Either of your two can be sent searching."), Color(0.7, 0.78, 0.85), 12)
		if SK != null:
			var kr := _row(v)
			if SK.searching(slot):
				var sk: Dictionary = SK.state(slot)
				hud._label(kr, I18n.t("Searching for %s -- back in %s.") % [I18n.t(str(SK.kinds().get(str(sk.get("kind", "")), {}).get("name", ""))).to_lower(), Game._dur(SK.left(slot))], 13, Color(0.7, 0.9, 1.0))
			else:
				hud._label(kr, I18n.t("Search for"), 13, Color(0.7, 0.75, 0.8))
				var hb := OptionButton.new()
				hb.custom_minimum_size = Vector2(90, 28)
				for hh in SK.hours():
					hb.add_item("%dh" % int(hh))
					hb.set_item_metadata(hb.item_count - 1, float(hh))
				hb.select(1)
				for kk in SK.kinds():
					var kwhy: String = SK.block(slot, str(kk))
					_btn(kr, I18n.t(str(SK.kinds()[kk].get("name", kk))), func(): _say(SK.start(slot, str(kk), float(hb.get_item_metadata(hb.selected)))), kwhy != "", kwhy if kwhy != "" else I18n.t(str(SK.kinds()[kk].get("desc", ""))))
				kr.add_child(hb)
		var ar := _row(v)
		if slot == 1:
			_btn(ar, I18n.t("Walk with you instead"), func():
				Game.swap_party()
				_say(""), Game.cslot(0).has("search") or Game.cslot(1).has("search") or bool(Game.cslot(0).get("away", false)))
		_btn(ar, I18n.t("Send home"), func():
			Game.part_with_companion(slot)
			_say(""), SK != null and SK.searching(slot))
	# the roster
	var ros: Array = Game.roster().filter(func(n): return Game.in_party(n) < 0)
	if ros.size() > 0:
		_h(_party, "Your roster -- everyone who has travelled with you", Color(0.8, 0.9, 1.0), 16)
		for nm2 in ros:
			var r := _row(_party)
			var why := Game.can_recall(str(nm2))
			var l: Label = hud._label(r, I18n.t("%s  --  %s, level %d") % [nm2, Game.bond_stage(str(nm2)), _lvl_of(str(nm2))], 14, Color(0.88, 0.9, 0.95))
			l.custom_minimum_size = Vector2(300, 0)
			_bar(r, float(Game.bond(str(nm2)).get("warmth", 0.0)), 100.0, Color(1.0, 0.6, 0.75), 100)
			_btn(r, I18n.t("Call"), func(): _say(Game.recall(str(nm2))), why != "", why)
			if why != "":
				hud._label(r, why, 11, Color(0.55, 0.58, 0.62))
	# contract beasts
	_h(_party, "Contract beasts", Color(0.7, 1.0, 0.8))
	var nx := Game.next_summon_text()
	_p(_party, I18n.t("Contracts %d of %d (Taming %d opens more)  ·  at your side %d of %d%s") % [Game.beast_count(), Game.contract_cap(), Game.taming_level(),
		Game.beasts_out().size(), Game.summon_cap(), ("  ·  " + nx) if nx != "" else ""], Color(0.75, 0.8, 0.85), 13)
	if Game.contracts.is_empty():
		_p(_party, "No beast has chosen you yet. Wild animals that don't attack you -- a cave hare, a tunnel boar, a moss stag -- can be won over with raw meat, fed by hand.", Color(0.65, 0.68, 0.72), 13)
	var BRs = Game.sys("breeding")
	if BRs != null and not Game.contracts.is_empty():
		_h(_party, I18n.t("Stable"), Color(0.95, 0.8, 0.6))
		_p(_party, I18n.t("Pair two bonded beasts in a town; in a few hours a young one hatches with a parent's gift, maybe a trait or a mutation. Stable %d of %d  ·  raised %d  ·  best generation %d") % [BRs.pairs.size(), BRs.slots(), BRs.born, BRs.best_gen], Color(0.75, 0.8, 0.85), 13)
		for pi in BRs.pairs.size():
			var pp: Dictionary = BRs.pairs[pi]
			var pr := _row(_party)
			var pl: Label = hud._label(pr, BRs.status_lines()[pi], 13, Color(1.0, 0.9, 0.7))
			pl.custom_minimum_size = Vector2(330, 0)
			_btn(pr, I18n.t("Collect the young"), func(): _say(BRs.hatch(pi)); _fill(I18n.t("Party")), BRs.left(pp) > 0.0 and not Game.tester_unlocked())
			_btn(pr, I18n.t("Separate"), func(): _say(BRs.separate(pi)); _fill(I18n.t("Party")))
		if _stable_pick >= 0 and _stable_pick < Game.contracts.size():
			_p(_party, I18n.t("Choose a partner for %s from the cards below (press Pair on another beast).") % str(Game.contracts[_stable_pick].get("name", "")), Color(1.0, 0.9, 0.6), 13)
	for i in Game.contracts.size():
		var c: Dictionary = Game.contracts[i]
		var lead := is_same(c, Game.familiar)
		var state := "in the stable" if bool(c.get("breeding", false)) else "exploring" if bool(c.get("away", false)) else ("at your heel (lead)" if lead else ("at your side" if bool(c.get("out", false)) else "resting in your spirit space"))
		var v2 := _card(_party, Color(0.6, 1.0, 0.75) if bool(c.get("out", false)) else Color(0.35, 0.45, 0.4))
		var t2 := _row(v2)
		var tl2 := _h(t2, Game.familiar_title(c), Color(0.75, 1.0, 0.85), 17)
		tl2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hud._label(t2, state, 12, Color(0.6, 0.7, 0.65))
		var br := _row(v2)
		hud._label(br, I18n.t("Bond"), 12, Color(0.7, 0.75, 0.7))
		_bar(br, float(c.get("bond", 0.0)), 200.0, Color(0.5, 0.95, 0.65), 200)
		hud._label(br, str(Game.contract_tier_def(c).get("name", "")), 13, Color(1.0, 0.75, 0.55) if int(c.get("tier", 0)) > 0 else Color(0.7, 0.75, 0.7))
		_p(v2, "  ·  ".join(Game.beast_rows(c).filter(func(r): return str(r[0]) != "Bond" and str(r[0]) != "Contract").map(func(r): return "%s: %s" % [r[0], r[1]])), Color(0.85, 0.9, 0.87), 13)
		var MN2 = Game.sys("menagerie")
		if MN2 != null:
			for bl in MN2.beast_lines(c):
				_p(v2, bl, Color(0.75, 0.95, 0.8), 13)
		if BRs != null:
			for ll in BRs.lineage_lines(c):
				_p(v2, ll, Color(1.0, 0.88, 0.65), 13)
			var tl3: Array = BRs.tree_lines(c)
			if tl3.size() > 1:
				_p(v2, I18n.t("Family tree:") + "\n" + "\n".join(tl3), Color(0.8, 0.85, 0.8), 12)
		if MN2 != null and bool(c.get("out", false)) and not bool(c.get("away", false)) and not MN2.beast_deed_info(c).is_empty():
			var bdi: Dictionary = MN2.beast_deed_info(c)
			_btn(_row(v2), I18n.t("Ask: %s") % str(bdi.get("name", "")), func(): _say(MN2.ask_beast(c)), float(bdi.get("left", 0.0)) > 0.0, str(bdi.get("desc", "")))
		var a2 := _row(v2)
		if BRs != null and not bool(c.get("construct", false)):
			if _stable_pick == i:
				_btn(a2, I18n.t("Cancel pairing"), func(): _stable_pick = -1; _fill(I18n.t("Party")))
			elif _stable_pick >= 0:
				var why3: String = BRs.why_not(_stable_pick, i)
				_btn(a2, I18n.t("Pair with %s") % str(Game.contracts[_stable_pick].get("name", "")), func():
					_say(BRs.pair(_stable_pick, i))
					_stable_pick = -1
					_fill("Party"), why3 != "", why3)
			elif not bool(c.get("breeding", false)):
				_btn(a2, I18n.t("Pair…"), func(): _stable_pick = i; _fill(I18n.t("Party")), BRs.pairs.size() >= BRs.slots(),
					I18n.t("The stable is full (%d of %d).") % [BRs.pairs.size(), BRs.slots()])
		if bool(c.get("out", false)) and not bool(c.get("away", false)):
			var pslot := 0
			var bo: Array = Game.beasts_out()
			for bi in bo.size():
				if is_same(bo[bi], c):
					pslot = bi
			_btn(a2, I18n.t("Photograph"), func(): hud.open_photo(pslot))
		if bool(c.get("out", false)):
			_btn(a2, I18n.t("Rest"), func(): _say(Game.rest_beast(i)), bool(c.get("away", false)))
		else:
			_btn(a2, I18n.t("Call to your side"), func(): _say(Game.summon_beast(i)), Game.beasts_out().size() >= Game.summon_cap(),
				"" if Game.beasts_out().size() < Game.summon_cap() else I18n.t("You can hold %d at your side. %s") % [Game.summon_cap(), nx])
		if not lead:
			_btn(a2, I18n.t("Make lead"), func(): _say(Game.make_lead(i)), bool(c.get("away", false)))
		var miss: Array = Game.deepen_missing(i)
		if miss != ["max"]:
			var tiers: Array = Game.beast_data().get("tiers", [])
			var nt: Dictionary = tiers[int(c.get("tier", 0)) + 1]
			_btn(a2, I18n.t("Deepen: %s") % str(nt.get("name", "")), func(): _say(Game.deepen_contract(i)), not miss.is_empty(),
				I18n.t("Needs: ") + ", ".join(miss) if not miss.is_empty() else I18n.t("Ready."))
			if not miss.is_empty():
				hud._label(a2, I18n.t("needs ") + ", ".join(miss), 11, Color(0.6, 0.62, 0.6))
		var le := LineEdit.new()
		le.placeholder_text = "new name"
		le.custom_minimum_size = Vector2(130, 26)
		a2.add_child(le)
		_btn(a2, I18n.t("Rename"), func(): _say(Game.rename_beast(i, le.text)))
		_btn(a2, I18n.t("Release?") if _confirm_release != i else I18n.t("Release -- sure?"), func():
			if _confirm_release == i:
				_confirm_release = -1
				_say(Game.release_beast(i))
			else:
				_confirm_release = i
				_fill("Party"))
	# round 154: constructs -- golems, the mech suit, voyages
	var CN = Game.sys("constructs")
	if CN != null:
		_h(_party, I18n.t("Constructs"), Color(0.95, 0.85, 0.55))
		_p(_party, I18n.t("Golems %d of %d  ·  built, not tamed: they do not use a beast slot. Research Animation (the swarm) to begin.") % [CN.golem_count(), CN.golem_cap()], Color(0.75, 0.8, 0.85), 13)
		for gk in CN.golems():
			var gd: Dictionary = CN.golems()[gk]
			var gr := _row(_party)
			var gl: Label = hud._label(gr, "%s  --  %s" % [I18n.t(str(gd.get("name", gk))), CN.needs_text(str(gk))], 13, Color(0.88, 0.9, 0.95))
			gl.custom_minimum_size = Vector2(330, 0)
			var gwhy: String = CN.build_block(str(gk))
			_btn(gr, I18n.t("Build"), func(): _say(CN.build(str(gk))), gwhy != "", gwhy if gwhy != "" else I18n.t(str(gd.get("desc", ""))))
		var mr2 := _row(_party)
		var mwhy: String = CN.mech_block()
		if CN.mech_on:
			mwhy = ""
		_btn(mr2, I18n.t("Leave the frame") if CN.mech_on else I18n.t("Wear the power frame"), func(): _say(CN.toggle_mech()), mwhy != "", mwhy if mwhy != "" else I18n.t("Tougher and harder-hitting, a little slower; it drinks qi while worn. Key: backslash."))
		if CN.voyage.is_empty():
			var vr := _row(_party)
			for vd in CN.voyages():
				var vwhy: String = CN.voyage_block(str(vd.get("id", "")))
				_btn(vr, "%s (%dh)" % [I18n.t(str(vd.get("name", ""))), int(vd.get("hours", 1))], func(): _say(CN.start_voyage(str(vd.get("id", "")))), vwhy != "", vwhy if vwhy != "" else I18n.t("Send a golem crew away on the skiff."))
		else:
			_p(_party, I18n.t("%s is at sea -- home in %d min.") % [str(CN.voyage.get("crew", "")), int(ceil(CN.voyage_left() / 60.0))], Color(0.7, 0.9, 1.0), 13)
	# the taming tree
	_h(_party, I18n.t("The taming tree -- Taming %d (%s)") % [Game.taming_level(), Game.skill_title("taming")], Color(0.85, 1.0, 0.75), 16)
	for row in Game.taming_tiers():
		var tdef: Dictionary = row[0]
		var chosen: String = row[1]
		var open: bool = row[2]
		var tr := _row(_party)
		hud._label(tr, I18n.t("Taming %d:") % int(tdef.get("skill", 1)), 13, Color(0.75, 0.8, 0.75)).custom_minimum_size = Vector2(90, 0)
		for side in ["a", "b"]:
			var pk: Dictionary = tdef[side]
			var is_it := str(pk.get("id", "")) == chosen
			_btn(tr, ("✓ " if is_it else "") + str(pk.get("name", "")), func(): _say(Game.choose_perk(str(pk["id"]))), not open or chosen != "", str(pk.get("desc", "")))
		var dsc := ""
		if chosen != "":
			dsc = str((tdef["a"] if str(tdef["a"].get("id", "")) == chosen else tdef["b"]).get("desc", ""))
		elif open:
			dsc = "Choose one, for good."
		hud._label(tr, dsc, 12, Color(0.65, 0.7, 0.68))


func _lvl_of(nm: String) -> int:
	var L: Dictionary = Game.companions_data().get("levels", {})
	var xp := float(Game.bond(nm).get("xp", 0.0))
	var lv := 0
	for need in L.get("xp", [0]):
		if xp >= float(need):
			lv += 1
	return maxi(0, lv - 1)


# ---- Bonds -----------------------------------------------------------------------------

func fill_bonds() -> void:
	_clear(_bonds)
	_t(_bonds, "Bonds", COL["Bonds"])
	var names: Array = Game.bonds.keys().filter(func(n): return int(Game.bond(str(n)).get("talks", 0)) > 0 or float(Game.bond(str(n)).get("warmth", 0.0)) != 0.0)
	names.sort_custom(func(a, b): return float(Game.bond(a).get("warmth", 0.0)) > float(Game.bond(b).get("warmth", 0.0)))
	_p(_bonds, "Everyone who knows you, closest first. Warmth grows with what you say and do -- time on the road, a fight shared, a kindness remembered. Close friends may travel with you; someone devoted may walk the road of cultivation with you.", Color(0.75, 0.75, 0.8), 13)
	if names.is_empty():
		_p(_bonds, "No bonds yet. Start with Elder Mo at the fountain -- a few kind words is enough. Everyone you talk to shows up here.", Color(0.65, 0.65, 0.7), 13)
	for nm in names:
		var b: Dictionary = Game.bond(str(nm))
		var w := float(b.get("warmth", 0.0))
		var tags := []
		if Game.partner == str(nm):
			tags.append(I18n.t("your partner"))
		if Game.in_party(str(nm)) >= 0:
			tags.append(I18n.t("travelling with you"))
		elif Game.has_flag("travelled:" + str(nm)):
			tags.append(I18n.t("on your roster"))
		var v := _card(_bonds, Color(1.0, 0.6, 0.75) if w >= 60 else (Color(0.9, 0.75, 0.6) if w >= 20 else Color(0.4, 0.42, 0.48)))
		var r := _row(v)
		var l := _h(r, str(nm), Color(1.0, 0.88, 0.92), 16)
		l.custom_minimum_size = Vector2(200, 0)
		hud._label(r, Game.bond_stage(str(nm)), 13, Color(1.0, 0.75, 0.85))
		_bar(r, maxf(w, 0.0), 100.0, Color(1.0, 0.55, 0.7) if w >= 0 else Color(0.5, 0.5, 0.55), 180)
		hud._label(r, I18n.t("%d talks%s") % [int(b.get("talks", 0)), ("  ·  " + ", ".join(tags)) if not tags.is_empty() else ""], 12, Color(0.65, 0.68, 0.75))
		var mem: Array = b.get("memories", [])
		if mem.size() > 0:
			_p(v, I18n.t("They remember: ") + "  /  ".join(mem.slice(maxi(0, mem.size() - 3)).map(func(m): return "\"%s\"" % str(m))), Color(0.78, 0.75, 0.8), 12)


# ---- Road --------------------------------------------------------------------------------

func fill_road() -> void:
	_clear(_road)
	_today_section()
	_collection_section()
	_garden_section()
	_t(_road, "The road down", COL["Road"])
	var ch: Dictionary = Game.mq_chapter()
	if ch.is_empty():
		_p(_road, "Every chapter of the road is behind you.", Color(0.8, 0.9, 0.8))
	else:
		var v := _card(_road, COL["Road"])
		_h(v, I18n.t("Chapter %d of %d: %s") % [Game.mq_index() + 1, Game.mq_chapters().size(), str(ch.get("name", ""))], Color(1.0, 0.92, 0.7), 17)
		_p(v, str(ch.get("brief", "")), Color(0.82, 0.82, 0.86), 13)
		for row in Game.mq_progress():
			hud._label(v, ("   ✓  " if bool(row[1]) else "   ·  ") + str(row[0]), 14, Color(0.6, 0.9, 0.6) if bool(row[1]) else Color(0.95, 0.92, 0.85))
		if Game.mq_ready():
			_p(v, "Done -- go and tell %s." % str(ch.get("who", "Elder Mo")), Color(1.0, 0.85, 0.4), 14)
	var ng: Dictionary = Game.next_gate()
	if not ng.is_empty():
		var gv := _card(_road, Color(0.9, 0.6, 0.4))
		var fl := int(ng.get("floor", 0))
		var miss: Array = Game.gate_missing(fl)
		_h(gv, "The gate to floor %d" % fl, Color(1.0, 0.8, 0.6), 16)
		_p(gv, str(ng.get("text", "")), Color(0.8, 0.8, 0.82), 13)
		_p(gv, (I18n.t("Open to you.") if miss.is_empty() else I18n.t("You lack: ") + ", ".join(miss) + ".") + "  (" + str(ng.get("hint", "")) + ")", Color(0.6, 0.9, 0.6) if miss.is_empty() else Color(1.0, 0.75, 0.6), 13)
	var errs: Array = Game.errands_open().filter(func(e): return str(e[2]) == "active")
	if errs.size() > 0:
		_h(_road, "Elder Mo's errands", Color(0.95, 0.85, 0.6), 16)
		for e in errs:
			hud._label(_road, I18n.t("   %s  (floor %d)%s") % [str(e[1].get("name", "")), int(e[1].get("floor", 0)), I18n.t("  -- done: take it to Elder Mo") if Game.errand_ready(str(e[0])) else ""], 13,
				Color(0.6, 0.9, 0.6) if Game.errand_ready(str(e[0])) else Color(0.88, 0.88, 0.9))
	var st: Array = Game.story_rows()
	if st.size() > 0:
		_h(_road, "The story", Color(0.95, 0.8, 0.9), 16)
		for r in st:
			hud._label(_road, "   %s -- %s%s" % [r[0], {"open": I18n.t("waiting for you (%s)") % r[3], "done": "done"}.get(str(r[1]), str(r[1])), ("  (\"" + str(r[2]).left(70) + "\")") if str(r[2]) != "" else ""], 13,
				Color(1.0, 0.85, 0.6) if str(r[1]) != "done" else Color(0.75, 0.78, 0.8))
	fill_legacies(_road)                        # round 51: the three tiers of inheritance, and what's left to find
	_h(_road, I18n.t("Hidden masters: %d found, %d taught you") % [Game.hm_count_found(), Game.hm_count_done()], Color(0.85, 0.85, 1.0), 16)
	var hh := Game.hm_hint()
	if hh != "":
		_p(_road, I18n.t("A rumour: ") + hh, Color(0.8, 0.8, 0.95), 13)
	var L = Game.sys("lore")
	if L:
		_h(_road, I18n.t("What you've learned -- notes, advice, history (%d of %d pieces of Eliet's history)") % [L.history_found.size(), (L.data.get("history", []) as Array).size()], Color(0.95, 0.9, 0.75), 16)
		if L.notes.is_empty():
			_p(_road, "Nothing yet. Read the old stones, open what's hidden, and ask people for advice -- the world has things to tell you.", Color(0.65, 0.65, 0.7), 13)
		var shown := 0
		for i in range(L.notes.size() - 1, -1, -1):
			var nt: Dictionary = L.notes[i]
			_p(_road, ("◆ " if str(nt.get("kind", "")) == "history" else "• ") + str(nt.get("text", "")), Color(0.95, 0.88, 0.7) if str(nt.get("kind", "")) == "history" else Color(0.85, 0.9, 0.85), 13)
			shown += 1
			if shown >= 14:
				break
	_h(_road, "The two roads", Color(0.85, 0.95, 0.8), 16)           # round 119
	var BAL = Game.sys("balance")
	if BAL:
		BAL.refresh()
		var rr := _row(_road)
		_p(rr, "Main road  %d%%" % int(BAL.main_pct()), Color(1.0, 0.92, 0.7), 14).custom_minimum_size = Vector2(170, 0)
		_bar(rr, BAL.main_pct(), 100.0, Color(1.0, 0.85, 0.4), 220.0)
		var rl := _row(_road)
		var lp: float = BAL.legacy_pct()
		_p(rl, "Legacy road  %s" % ("%d%%" % int(lp) if lp >= 0.0 else "(no master met yet)"), Color(0.7, 1.0, 0.9), 14).custom_minimum_size = Vector2(170, 0)
		_bar(rl, maxf(lp, 0.0), 100.0, Color(0.4, 0.9, 0.8), 220.0)
		var note := "The story and the masters' tasks run side by side. Up to %d points apart costs you nothing; farther and you are Imbalanced (less qi, slower sitting, harder foes) until the roads draw level." % int(BAL.limit())
		if BAL.imbalance() > 0.0:
			note = I18n.t("IMBALANCED (%d%%): the roads are %d points apart. Walk the one you have neglected.") % [int(BAL.imbalance() * 100.0), int(BAL.gap())]
		elif BAL.even_road():
			note = "THE EVEN ROAD: your roads run level, and danger bites 15% less."
		_p(_road, note, Color(1.0, 0.8, 0.6) if BAL.imbalance() > 0.0 else Color(0.8, 0.9, 0.85), 13)
		if BAL.holds():
			var asp: Dictionary = BAL.aspects()
			for k in asp:
				var ra := _row(_road)
				_p(ra, str(BAL.cfg.get("aspects", {}).get(k, {}).get("name", k)), Color(0.85, 0.9, 0.95), 13).custom_minimum_size = Vector2(110, 0)
				_bar(ra, float(asp[k]), 1.0, Color(0.6, 0.8, 1.0), 180.0)
			_p(_road, BAL.hint_line(), Color(1.0, 0.9, 0.6), 14)
	var HL = Game.sys("heirloom")
	if HL and HL.started:
		_h(_road, "The Heirloom", Color(1.0, 0.85, 0.5), 16)
		_p(_road, HL.status_line(), Color(1.0, 0.92, 0.75), 14)
		if HL.complete():
			_p(_road, "Feed it rare materials at the smith and fight with it on: it grows from Dormant to Awakened to Ascendant.", Color(0.8, 0.85, 0.8), 13)
		else:
			_p(_road, I18n.t("Next: ") + HL.needs_text(HL.next_index()), Color(0.85, 0.9, 0.85), 13)
	_h(_road, "How far you've come", Color(0.8, 0.95, 1.0), 16)
	_p(_road, I18n.t("Deepest floor %d  ·  mastery %d%%  ·  balance %d%% (growth x%.2f)") % [Game.reach_depth(), int(round(Game.mastery() * 100)), int(round(Game.balance() * 100)), Game.balance_mult()], Color(0.85, 0.9, 0.95), 14)


var quest_filter := ""             # round 54: "" = every kind


func fill_quests() -> void:
	## round 52/54: every quest in the game -- the road down itself, and side
	## quests of every kind (crafts, gathering, people, masters, hunting,
	## exploration): what you're on and the step you're at, who's asking, and
	## how much of each kind you've done
	_clear(_quests)
	var Q = Game.sys("quests")
	_t(_quests, "Quests", COL["Quests"])
	var DG = Game.sys("goals")
	if DG != null:
		var gv := _card(_quests, Color(0.6, 0.9, 1.0))
		var gh := _row(gv)
		var gt := _h(gh, I18n.t("Today's goals"), Color(0.7, 0.92, 1.0), 16)
		gt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hud._label(gh, (I18n.t("streak %d") % DG.streak) if DG.streak > 0 else "", 12, Color(1.0, 0.9, 0.6))
		for gg in DG.goals():
			var gr := _row(gv)
			var gmark: String = "[x]" if bool(gg["done"]) else "[ ]"
			var gl: Label = hud._label(gr, "%s  %s" % [gmark, DG.text_of(gg)], 13, Color(0.6, 0.85, 0.65) if bool(gg["done"]) else Color(0.9, 0.93, 0.97))
			gl.custom_minimum_size = Vector2(330, 0)
			_bar(gr, float(DG.progress(gg)), float(gg["need"]), Color(0.5, 0.85, 1.0), 120)
	# the main quest, always first
	var ch: Dictionary = Game.mq_chapter()
	var mv := _card(_quests, Color(1.0, 0.9, 0.6))
	_h(mv, I18n.t("Main -- ") + (I18n.t("Chapter %d of %d: %s") % [Game.mq_index() + 1, Game.mq_chapters().size(), str(ch.get("name", ""))] if not ch.is_empty() else I18n.t("the road is walked")), Color(1.0, 0.92, 0.7), 16)
	if not ch.is_empty():
		for row in Game.mq_progress():
			hud._label(mv, ("   ✓  " if bool(row[1]) else "   ▸  ") + str(row[0]), 13, Color(0.6, 0.9, 0.6) if bool(row[1]) else Color(0.95, 0.92, 0.85))
	if Q == null:
		return
	# the kinds, as filters
	var fr := _row(_quests)
	var kinds := [["", "All"]]
	for kr in Q.KINDS:
		if Q.all().any(func(q): return str(q.get("kind", "side")) == str(kr[0])):
			kinds.append(kr)
	for kr2 in kinds:
		var kid := str(kr2[0])
		var tot: int = Q.all().filter(func(q): return kid == "" or str(q.get("kind", "side")) == kid).size()
		var dn: int = Q.done.keys().filter(func(d): return kid == "" or Q.kind_of(str(d)) == kid).size()
		var b := _btn(fr, "%s %d/%d" % [str(kr2[1]).trim_suffix(" quests"), dn, tot], func():
			quest_filter = kid
			_fill("Quests"))
		b.theme_type_variation = "RailButton"
		b.toggle_mode = true
		b.set_pressed_no_signal(quest_filter == kid)
	_p(_quests, "A gold ! over someone's head means they have a quest for you; a ? means you've news for them. Follow one and it shows at the top right; what it sends you to find is marked with a gold diamond once you're near.", Color(0.65, 0.68, 0.74), 12)
	var shown := 0
	for qid in Q.active:
		if quest_filter != "" and Q.kind_of(str(qid)) != quest_filter:
			continue
		shown += 1
		var q: Dictionary = Q.qdef(str(qid))
		var v := _card(_quests, COL["Quests"] if Q.tracked == str(qid) else Color(0.55, 0.55, 0.6))
		_h(v, str(q.get("name", "")) + ("   (following)" if Q.tracked == str(qid) else ""), Color(1.0, 0.92, 0.7), 16)
		_p(v, I18n.t("%s  ·  from %s (%s)") % [Q.kind_name(Q.kind_of(str(qid))), str(q.get("giver", "")), hud._place_name(str(q.get("place", "")))], Color(0.7, 0.75, 0.82), 12)
		var sts: Array = q.get("stages", [])
		var i := int(Q.active[qid]["stage"])
		for k in sts.size():
			if k < i:
				hud._label(v, "   ✓  " + str(sts[k].get("log", "")), 13, Color(0.6, 0.85, 0.6))
			elif k == i:
				hud._label(v, "   ▸  " + str(sts[k].get("log", "")) + Q.progress_text(str(qid)), 14, Color(1.0, 0.95, 0.85))
		if Q.tracked != str(qid):
			var r := _row(v)
			var id := str(qid)
			_btn(r, I18n.t("Follow this one"), func():
				Q.tracked = id
				hud.refresh_goals()
				_fill("Quests"))
	if shown == 0:
		_p(_quests, "Nothing of this kind on the go.", Color(0.7, 0.72, 0.78), 13)
	var rm: Array = Q.rumours().filter(func(r3): return quest_filter == "" or Q.kind_of(str(r3[0])) == quest_filter)
	if rm.size() > 0:
		_h(_quests, "People asking for help", Color(0.95, 0.85, 0.6), 16)
		for r2 in rm:
			hud._label(_quests, "   !  %s, in %s  --  %s" % [str(r2[1]), hud._place_name(str(r2[2])), Q.kind_name(Q.kind_of(str(r2[0])))], 14, Color(1.0, 0.88, 0.55))
	var later := 0
	var other_sects := 0
	for q2 in Q.all():
		var id2 := str(q2["id"])
		if (quest_filter == "" or Q.kind_of(id2) == quest_filter) and not Q.unlocked(id2) and not Q.active.has(id2) and not Q.done.has(id2):
			if Q.sect_locked(id2):
				other_sects += 1
			else:
				later += 1
	if later > 0:
		_p(_quests, "%d more will come to you as you go deeper (and as you finish the ones before them)." % later, Color(0.65, 0.67, 0.72), 13)
	if other_sects > 0:
		_p(_quests, "%d belong to the roads of sects you haven't joined -- each valley sect's elder has five, for their own disciples. One sect at a time; what you finish stays yours." % other_sects, Color(0.7, 0.68, 0.85), 13)
	var dn2: Array = Q.done.keys().filter(func(d2): return quest_filter == "" or Q.kind_of(str(d2)) == quest_filter)
	if dn2.size() > 0:
		_h(_quests, I18n.t("Done (%d of %d)") % [Q.done.size(), Q.all().size()], Color(0.75, 0.9, 0.75), 16)
		for qid2 in dn2:
			hud._label(_quests, "   ✓  %s  (%s)" % [str(Q.qdef(str(qid2)).get("name", "")), Q.kind_name(Q.kind_of(str(qid2)))], 13, Color(0.65, 0.8, 0.65))


func fill_legacies(box: Node) -> void:
	## round 51: what this game holds -- minor, major and heavenly -- and
	## enough of a hint to keep a completionist looking after the road is walked
	var LG = Game.sys("legacies")
	if LG == null:
		return
	var sm: Dictionary = LG.summary()
	var v := _card(box, Color(0.95, 0.8, 0.45))
	_h(v, "Inheritances", Color(1.0, 0.88, 0.6), 17)
	var mi: Array = sm["minor"]
	_p(v, I18n.t("Minor -- the craft masters at lost workshops: %d of %d taken. One sits near the top of the stair; the rest wait at other workshops above floor %d.") % [int(mi[0]), int(mi[1]), int(LG.cfg("minor").get("upper_floors", 10)) + 1], Color(0.85, 0.9, 0.85), 13)
	var ma: Array = sm["major"]
	var bands := []
	var mb: Dictionary = sm["major_bands"]
	var keys := mb.keys()
	keys.sort()
	for b in keys:
		bands.append(I18n.t("%d between floors %d and %d") % [int(mb[b]), int(b) * 10 + 1, int(b) * 10 + 10])
	_p(v, I18n.t("Major -- dead masters still seated where they died: %d of %d found.%s%s") % [int(ma[0]), int(ma[1]),
		(I18n.t(" Still out there: ") + ", ".join(bands) + ".") if bands.size() > 0 else "",
		(I18n.t(" %d more %s not woken yet -- they will, when you're strong enough for them.") % [int(sm["sleeping"]), "has" if int(sm["sleeping"]) == 1 else "have"]) if int(sm["sleeping"]) > 0 else ""], Color(0.85, 0.9, 0.95), 13)
	_p(v, "They hide well: far from the stairs, in dead ends and sealed rooms. Spirit Sense finds them only from a few steps away -- or stand still and search, right beside one. A drift of pale motes is the only sign.", Color(0.65, 0.68, 0.75), 12)
	var hv: Array = sm["heavenly"]
	var got := hv.filter(func(x): return bool(x["claimed"])).size()
	_p(v, I18n.t("Heavenly -- %d in this world, %d yours.") % [hv.size(), got], Color(1.0, 0.9, 0.6), 13)
	if Game.realm >= int(LG.cfg("heavenly").get("perceive_realm", 3)):
		for x in hv:
			if bool(x["claimed"]):
				_p(v, "   ✓  " + str(LG.heavenly(str(x["id"])).get("master", "")), Color(0.7, 0.95, 0.7), 13)
			else:
				_p(v, I18n.t("   ·  one rests somewhere between floors %d and %d") % [int(x["lo"]), int(x["hi"])], Color(0.95, 0.88, 0.7), 13)
	else:
		_p(v, "   (Until you reach %s you couldn't even feel one. Rumour says they lie deep.)" % Game.realm_name_of(int(LG.cfg("heavenly").get("perceive_realm", 3))), Color(0.65, 0.65, 0.7), 12)


# ---- System --------------------------------------------------------------------------------

func fill_system() -> void:
	_clear(_system)
	_t(_system, "System", COL["System"])
	var r := _row(_system)
	_btn(r, I18n.t("Save now"), func():
		Game.save_game()
		_say(I18n.t("Saved.")))
	_btn(r, I18n.t("Settings: graphics, sound, camera, fog..."), func():
		close_hub()
		hud._toggle_pause())
	_btn(r, I18n.t("Plan your time away"), func():
		close_hub()
		hud.open_away_plan())
	_btn(r, I18n.t("Quit"), func():
		close_hub()
		hud.open_away_plan(true))
	_language_section()
	_access_section()
	_difficulty_section()
	_h(_system, "Keys", Color(0.85, 0.85, 0.95), 16)
	_p(_system, "Menu: Tab (or Esc to close)  ·  You P  ·  Pack I  ·  Party O  ·  Bonds U  ·  Road L  ·  Swarm Y  ·  Journal N  ·  Meridians K  ·  Q / E flip sections", Color(0.85, 0.88, 0.92), 13)
	_p(_system, hud._help.text, Color(0.75, 0.78, 0.82), 13)



# ---- Mind (round 40): where your sitting goes, synergy, cleansing --------------------------

func fill_mind() -> void:
	_clear(_mind)
	var M = Game.sys("mind")
	var C = Game.sys("cleansing")
	var Y = Game.sys("synergy")
	if M == null or C == null or Y == null:
		return
	_t(_mind, "Mind -- where your sitting goes", COL["Mind"])
	_p(_mind, I18n.t("Now: %s%s") % [M.summary(), I18n.t("   ·   you're sitting") if Game.sitting else "   ·   (sit with M to meditate)"], Color(0.9, 0.88, 1.0), 14)
	var fr := _row(_mind)
	hud._label(fr, I18n.t("Focus"), 14, Color(0.75, 0.75, 0.85))
	for m in M.WORK:
		var on: bool = not M.use_split and M.mode == m
		_btn(fr, ("● " if on else "") + M.label(m), func(): _say(M.set_mode(m)), on,
			{"cultivate": "Qi in full, and your meridian focus point opens.", "cleanse": "Cleanse a meridian node (qi at 60%).", "research": "Work on swarm research (qi at 60%)."}[m])
	if M.threads() >= 2:
		_p(_mind, I18n.t("Divided Mind: you can hold %d threads at once%s. Set the shares:") % [M.threads(), "" if Game.sys("research").unlocked("split_eff") else " (a split sitting does 85% of each)"], Color(0.8, 0.78, 0.95), 13)
		for k in M.WORK:
			var sr := _row(_mind)
			hud._label(sr, M.label(k), 13, Color(0.85, 0.85, 0.95)).custom_minimum_size = Vector2(90, 0)
			var sl := HSlider.new()
			sl.min_value = 0.0
			sl.max_value = 1.0
			sl.step = 0.05
			sl.value = float(M.split.get(k, 0.0))
			sl.custom_minimum_size = Vector2(260, 20)
			sr.add_child(sl)
			var vl: Label = hud._label(sr, "%d%%" % int(round(float(M.shares().get(k, 0.0)) * 100)), 13, Color(0.85, 0.85, 0.95))
			sl.value_changed.connect(func(v):
				M.set_share(k, v)
				vl.text = "%d%%" % int(round(float(M.shares().get(k, 0.0)) * 100)))
		var ub := _btn(_row(_mind), I18n.t("Use the split"), func():
			M.use_split = true
			_say(""))
		ub.disabled = M.use_split
	else:
		_p(_mind, "Your mind holds one thread. Research Divided Mind (the Swarm page) to split a sitting two ways, then three.", Color(0.65, 0.65, 0.75), 12)
	var bg: float = M.bg_rate()
	_p(_mind, ("The swarm works on research and cleansing while you don't sit: %d%% pace." % int(round(bg * 100))) if bg > 0.0 else "The swarm only works while you sit (Swarm Parallelism lets it work all the time).", Color(0.75, 0.85, 0.9), 12)
	# synergy
	_h(_mind, "Synergy -- the swarm and your qi", Color(0.6, 1.0, 0.95), 17)
	_p(_mind, I18n.t("Level %.1f: the lower of your realm (%s) and your swarm tier (%s)%s.") % [Y.level(), Game.realm_name(), Game.tier_name(), I18n.t(", +0.5 in harmony") if Game.harmony() == "harmony" else " -- grow both"], Color(0.8, 0.95, 0.95), 13)
	for r in Y.rows():
		var rr := _row(_mind)
		hud._label(rr, str(r[0]), 14, Color(0.7, 1.0, 0.95)).custom_minimum_size = Vector2(110, 0)
		hud._label(rr, str(r[1]), 13, Color(0.92, 0.95, 0.95)).custom_minimum_size = Vector2(250, 0)
		var dl: Label = hud._label(rr, str(r[2]), 11, Color(0.6, 0.68, 0.7))
		dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		dl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var up: float = Y.upkeep_per_minute()
	_p(_mind, (I18n.t("Your designs and installs draw %.1f qi a minute%s.") % [up, I18n.t(" -- RUN DRY: they're quiet until you gather qi") if Y.starved else ""]) if up > 0.0 else I18n.t("Nothing you run draws qi yet."), Color(1.0, 0.6, 0.5) if Y.starved else Color(0.75, 0.85, 0.85), 12)
	_p(_mind, str(Y.data.get("lore", "")), Color(0.6, 0.65, 0.7), 11)
	# cleansing
	_h(_mind, "Meridian cleansing", Color(0.9, 0.8, 1.0), 17)
	var cur: String = C.current()
	if cur != "":
		var cn: Dictionary = C.node(cur)
		var need: float = C.seconds_for(cur, C.grade_of(cur) + 1)
		var cr := _row(_mind)
		hud._label(cr, I18n.t("Cleansing %s (%s): %s -> %s") % [cn["name"], cn["meaning"], C.grade_name(C.grade_of(cur)), C.grade_name(C.grade_of(cur) + 1)], 14, Color(0.95, 0.9, 1.0))
		_bar(cr, float(C.progress.get(cur, 0.0)), need, Color(0.75, 0.6, 1.0), 200)
		hud._label(cr, I18n.t("%s of sitting left (x%.2f speed)") % [Game._dur(maxf(0.0, need - float(C.progress.get(cur, 0.0))) / maxf(C.speed(), 0.01)), C.speed()], 11, Color(0.65, 0.65, 0.75))
	else:
		_p(_mind, "No node you can cleanse right now -- open meridian points (K), or grow your realm.", Color(0.65, 0.65, 0.72), 13)
	var st: Dictionary = C.data.get("stats", {})
	var g := GridContainer.new()
	g.columns = 4
	g.add_theme_constant_override("h_separation", 12)
	_mind.add_child(g)
	for k in st:
		hud._label(g, str(st[k].get("name", k)), 13, Color(0.85, 0.85, 0.95))
		_bar(g, C.stat_fraction(str(k)), 1.0, Color(0.8, 0.65, 1.0), 120)
		hud._label(g, "%s%d%% of %d%%" % ["-" if bool(st[k].get("inverse", false)) else "+", int(round(C.stat_bonus(str(k)) * 100)), int(round(float(st[k].get("cap", 0)) * 100))], 12, Color(0.9, 0.9, 0.95))
		hud._label(g, "", 10, Color.WHITE)
	_p(_mind, str(C.data.get("_about", "")).get_slice("THE METRIC: ", 1), Color(0.6, 0.6, 0.7), 11)
	_h(_mind, "Major nodes", Color(0.95, 0.85, 1.0), 15)
	for n in C.nodes():
		if bool(n["major"]):
			_node_row(C, n)
	for mer in ["strike", "guard", "step"]:
		_h(_mind, "Minor nodes -- the %s meridian" % mer, Color(0.85, 0.85, 1.0), 15)
		for n2 in C.nodes():
			if not bool(n2["major"]) and str(n2.get("meridian", "")) == mer:
				_node_row(C, n2)


func _node_row(C, n: Dictionary) -> void:
	var nid := str(n["id"])
	var r := _row(_mind)
	var gname: String = C.grade_name(C.grade_of(nid))
	var dots := ""
	for i in 4:
		dots += "◆" if i < C.grade_of(nid) else "◇"
	var l: Label = hud._label(r, "%s  %s -- %s" % [dots, n["name"], n["meaning"]], 13, Color(1.0, 0.95, 0.75) if C.grade_of(nid) >= 4 else Color(0.9, 0.9, 0.95))
	l.custom_minimum_size = Vector2(330, 0)
	hud._label(r, "%s  ·  %s" % [gname, ", ".join((n["stats"] as Array).map(func(x): return "everything" if str(x) == "all" else C.stat_name(str(x))))], 12, Color(0.7, 0.7, 0.8)).custom_minimum_size = Vector2(200, 0)
	var why: String = C.can_cleanse(nid)
	if nid == C.current():
		hud._label(r, I18n.t("cleansing now"), 12, Color(0.8, 0.65, 1.0))
	elif why == "":
		_btn(r, I18n.t("Cleanse this"), func(): _say(C.set_target(nid)))
	else:
		var wl: Label = hud._label(r, why, 11, Color(0.55, 0.55, 0.62))
		wl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		wl.clip_text = true


# ---- Swarm (round 40): research, designs, installs ---------------------------------------

func fill_swarm() -> void:
	_clear(_swarm)
	var R = Game.sys("research")
	var Y = Game.sys("synergy")
	if R == null:
		return
	_t(_swarm, "The swarm", COL["Swarm"])
	_p(_swarm, I18n.t("%s  ·  integration %d  ·  bandwidth %d of %d  ·  body load %d of %d  ·  upkeep %d (%.1f qi a minute)%s") % [Game.tier_name(), int(Game.integration),
		R.bandwidth_used(), R.bandwidth_cap(), R.load_used(), R.load_cap(), R.upkeep_points(), Y.upkeep_per_minute() if Y else 0.0, "  ·  RUN DRY" if Y and Y.starved else ""], Color(0.8, 1.0, 0.95), 13)
	_mind_section()
	_aspect_section()
	_inner_section()
	if R.current != "":
		var rn: Dictionary = R.node(R.current)
		var rr := _row(_swarm)
		hud._label(rr, I18n.t("Researching %s") % rn.get("name", ""), 14, Color(0.6, 1.0, 0.9))
		_bar(rr, float(R.progress.get(R.current, 0.0)), R.cost_seconds(R.current), Color(0.4, 0.95, 0.85), 220)
		hud._label(rr, I18n.t("%s of sitting left") % Game._dur(maxf(0.0, R.cost_seconds(R.current) - float(R.progress.get(R.current, 0.0))) / maxf(R.speed(), 0.01)), 11, Color(0.6, 0.7, 0.7))
		_btn(rr, I18n.t("Set aside"), func(): _say(R.stop()))
		if Game.sys("mind").mode != "research" and float(Game.sys("mind").shares().get("research", 0.0)) <= 0.0:
			_btn(rr, I18n.t("Make Research my focus"), func(): _say(Game.sys("mind").set_mode("research")))
	_p(_swarm, "Research while you sit (Research as your focus on the Mind page). Connect, tune and install while you sit, too%s." % ("" if Game.sitting else " -- you're standing now"), Color(0.65, 0.7, 0.75), 12)
	var fr := HFlowContainer.new()           # (wraps to a second line rather than running off the edge)
	fr.add_theme_constant_override("h_separation", 6)
	fr.add_theme_constant_override("v_separation", 4)
	_swarm.add_child(fr)
	var eb := _btn(fr, I18n.t("Every branch"), func():
		swarm_branch = ""
		_fill("Swarm"))
	eb.disabled = swarm_branch == ""
	for bid in R.data.get("branches", {}):
		var bd: Dictionary = R.branch(str(bid))
		var bb := _btn(fr, str(bd.get("name", bid)), func():
			swarm_branch = str(bid)
			_fill("Swarm"))
		bb.disabled = swarm_branch == str(bid)
	for bid2 in R.data.get("branches", {}):
		if swarm_branch != "" and swarm_branch != str(bid2):
			continue
		var bd2: Dictionary = R.branch(str(bid2))
		var cv: Array = bd2.get("color", [0.8, 0.9, 1.0])
		var col := Color(float(cv[0]), float(cv[1]), float(cv[2]))
		_h(_swarm, "%s -- %s%s" % [bd2.get("name", bid2), bd2.get("desc", ""), I18n.t("   (late)") if bool(bd2.get("late", false)) else ""], col, 16)
		for nid in R.branch_nodes(str(bid2)):
			_design_card(R, str(nid), col)


func _design_card(R, nid: String, col: Color) -> void:
	var n: Dictionary = R.node(nid)
	var st: String = R.state_of(nid)
	var v := _card(_swarm, col if st in ["known", "connected", "installed"] else (col.darkened(0.5) if st != "locked" else Color(0.3, 0.32, 0.36)))
	var t := _row(v)
	var tl := _h(t, str(n.get("name", nid)), col.lightened(0.3) if st != "locked" else Color(0.6, 0.62, 0.66), 15)
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var kind := str(n.get("kind", ""))
	var tag: String = {"design": I18n.t("design  ·  bandwidth %d, upkeep %d") % [int(n.get("bandwidth", 1)), int(n.get("upkeep", 0))], "passive": I18n.t("always on"), "unlock": I18n.t("unlocks: ") + str(n.get("unlock", "")),
		"install": I18n.t("install  ·  load %d%s") % [int(n.get("load", 1)), (I18n.t(", upkeep %d") % int(n["upkeep"])) if int(n.get("upkeep", 0)) > 0 else ""]}.get(kind, kind)
	hud._label(t, "%s  ·  %s" % [tag, st], 11, Color(0.65, 0.7, 0.75))
	_p(v, str(n.get("desc", "")) + (("  (" + Game.effect_text(n["effect"]) + ")") if n.has("effect") else ""), Color(0.85, 0.88, 0.9), 12)
	var a := _row(v)
	match st:
		"locked":
			hud._label(a, I18n.t("Needs: ") + ", ".join(R.gate_missing(nid)), 11, Color(0.6, 0.55, 0.55))
		"open", "begun":
			var c: Dictionary = n.get("cost", {})
			var why: String = R.can_research(nid)
			_btn(a, I18n.t("Research") if st == "open" else I18n.t("Continue"), func(): _say(R.start(nid)), why != "", why)
			if st == "open":
				hud._label(a, I18n.t("%s of sitting  ·  %d qi  ·  %s") % [Game._dur(float(c.get("seconds", 600))), int(R.cost_qi(nid)),
					", ".join((c.get("items", {}) as Dictionary).keys().map(func(it): return "%d %s (%d)" % [int(c["items"][it]), Game.item_name(str(it)), Game.count(str(it))]))], 11, Color(0.7, 0.75, 0.75))
			else:
				_bar(a, float(R.progress.get(nid, 0.0)), R.cost_seconds(nid), Color(0.4, 0.8, 0.75), 140)
		"researching":
			_bar(a, float(R.progress.get(nid, 0.0)), R.cost_seconds(nid), Color(0.4, 0.95, 0.85), 180)
			hud._label(a, I18n.t("in progress"), 11, Color(0.6, 1.0, 0.9))
		"known":
			if kind == "design":
				_btn(a, I18n.t("Connect"), func(): _say(R.connect_design(nid, Game.sitting)), not Game.sitting, "" if Game.sitting else I18n.t("Sit first (M)."))
			elif kind == "install":
				_btn(a, I18n.t("Install"), func(): _say(R.install(nid, Game.sitting)), not Game.sitting, "" if Game.sitting else I18n.t("Sit first (M)."))
			else:
				hud._label(a, I18n.t("part of you"), 11, Color(0.6, 1.0, 0.8))
		"connected":
			var tn := str(R.connected[nid].get("tune", ""))
			hud._label(a, (I18n.t("Tuned: %s") % R.tuning(tn).get("name", "")) if tn != "" else I18n.t("Untuned"), 12, Color(0.9, 0.85, 0.6) if tn != "" else Color(0.65, 0.65, 0.7))
			var mats := []
			for m in R.data.get("tunings", {}):
				if Game.count(str(m)) >= int(R.tuning(str(m)).get("need", 1)):
					mats.append(str(m))
			if mats.size() > 0:
				var ob := OptionButton.new()
				ob.custom_minimum_size = Vector2(230, 26)
				for i in mats.size():
					var td: Dictionary = R.tuning(mats[i])
					ob.add_item("%s (%d %s)" % [td.get("name", ""), int(td.get("need", 1)), Game.item_name(mats[i])])
					ob.set_item_metadata(i, mats[i])
					ob.set_item_tooltip(i, str(td.get("desc", "")))
				a.add_child(ob)
				_btn(a, I18n.t("Tune"), func(): _say(R.tune(nid, str(ob.get_item_metadata(ob.selected)), Game.sitting)), not Game.sitting, "" if Game.sitting else I18n.t("Sit first (M)."))
			_btn(a, I18n.t("Disconnect"), func(): _say(R.disconnect_design(nid)))
		"installed":
			hud._label(a, "installed", 12, Color(1.0, 0.85, 0.5))
			_btn(a, I18n.t("Remove"), func(): _say(R.uninstall(nid)))



# ---- Spirit (round 40, Robert: "add a spirit page with the affinities listed there") ------

const ELEM_GIFT := {"fire": "your strikes (up to +25% damage)", "earth": "your body (up to +20% health)", "water": "your cultivation (up to +40% from sitting)",
	"wood": "your gathering (up to +50%)", "metal": "your crafting (up to +15% success, +10% finer work)"}
const ELEM_FEEL := {"fire": "Fire", "earth": "Earth", "water": "Water", "wood": "Wood", "metal": "Metal"}


func fill_spirit() -> void:
	_clear(_spirit)
	_t(_spirit, "Spirit -- your elements", COL["Spirit"])
	_p(_spirit, "Five elements live in your foundation. Each grows with what you do -- the skills you practise, the points you open, what you eat and burn and carry -- and each gives its own gift. At %d an element is ACTIVE: part of who you are." % int(Game.AFFINITY_ACTIVE), Color(0.8, 0.85, 0.8), 13)
	var best := ""
	var bv := -1.0
	for e in Game.ELEMENTS:
		if float(Game.affinity.get(e, 0.0)) > bv:
			bv = float(Game.affinity.get(e, 0.0))
			best = str(e)
	var eff: Dictionary = Game.affinity_effect()
	var st: Dictionary = Game.affinity_status()
	for e in Game.ELEMENTS:
		var a := float(Game.affinity.get(e, 0.0))
		var cv: Array = Game.ELEMENT_COLOR.get(e, [0.8, 0.8, 0.8])
		var col := Color(float(cv[0]), float(cv[1]), float(cv[2])).lightened(0.25)
		var v := _card(_spirit, col)
		var r := _row(v)
		var nl := _h(r, "%s%s" % [ELEM_FEEL[e], I18n.t("  (your strongest)") if e == best and a > 0.0 else ""], col.lightened(0.2), 17)
		nl.custom_minimum_size = Vector2(230, 0)
		_bar(r, a, 100.0, col, 260)
		hud._label(r, "%d / 100%s" % [int(a), I18n.t("   ACTIVE") if a >= Game.AFFINITY_ACTIVE else ""], 13, Color(1.0, 0.95, 0.7) if a >= Game.AFFINITY_ACTIVE else Color(0.75, 0.78, 0.8))
		var now := ""
		match str(e):
			"fire":
				now = I18n.t("+%d%% damage") % int(round((float(eff.get("damage_mult", 1.0)) - 1.0) * 100))
			"earth":
				now = I18n.t("+%d%% health") % int(round((float(eff.get("hp_mult", 1.0)) - 1.0) * 100))
			"water":
				now = I18n.t("+%d%% from sitting") % int(round((float(eff.get("meditate_mult", 1.0)) - 1.0) * 100))
			"wood":
				now = I18n.t("+%d%% gathering") % int(round(float(eff.get("gather_chance", 0.0)) * 100))
			"metal":
				now = I18n.t("+%d%% craft success, +%d%% finer work") % [int(round(float(eff.get("craft_success", 0.0)) * 100)), int(round(float(eff.get("craft_quality", 0.0)) * 100))]
		_p(v, I18n.t("Strengthens %s.  Now: %s.  Feeds %s; overcomes %s.  Weapon of the element: %s.") % [ELEM_GIFT[e], now, ELEM_FEEL[Game.GENERATES[e]], ELEM_FEEL[Game.OVERCOMES[e]],
			str(Game.ELEMENT_WEAPON.get(e, "")).capitalize()], Color(0.85, 0.88, 0.85), 12)
		var grows := []
		for sid in Game.skill_defs:
			if float((Game.skill_defs[sid].get("elements", {}) as Dictionary).get(e, 0.0)) >= 0.3:
				grows.append(Game.skill_name(str(sid)))
		if grows.size() > 0:
			_p(v, I18n.t("Grows with: ") + ", ".join(grows) + I18n.t(", and the meridian points of its element."), Color(0.65, 0.7, 0.68), 11)
	_h(_spirit, "How they sit together", Color(0.85, 0.95, 0.85), 16)
	if st["synergies"].is_empty() and st["clashes"].is_empty():
		_p(_spirit, "No two elements are strong enough yet to feed or fight each other.", Color(0.7, 0.72, 0.7), 13)
	for t in st["synergies"]:
		_p(_spirit, str(t) + I18n.t(" -- the second one's gift grows by 40%."), Color(0.6, 1.0, 0.7), 13)
	for t2 in st["clashes"]:
		_p(_spirit, str(t2) + I18n.t(" -- qi comes 12% slower and the weaker gift halves."), Color(1.0, 0.6, 0.55), 13)
	_p(_spirit, "The generating cycle: Wood feeds Fire, Fire feeds Earth, Earth feeds Metal, Metal feeds Water, Water feeds Wood. The overcoming cycle: Water quenches Fire, Fire melts Metal, Metal cuts Wood, Wood splits Earth, Earth dams Water. Two strong elements that feed each other synergize; two that fight, held close in strength, clash.", Color(0.6, 0.65, 0.62), 12)
	_h(_spirit, "The rest of your spirit", Color(0.85, 0.95, 0.85), 16)
	_p(_spirit, I18n.t("Spirit (attribute) %d  ·  insight %d / %d toward %s  ·  dao heart %d%%  ·  balance of the elements %d%%") % [Game.attr_total("spirit"), int(Game.insight), Game.insight_need(),
		Game.realm_info(Game.realm + 1)["name"], int(round(Game.dao_heart)), int(round(float(Game.balance_parts()[3][1]) * 100))], Color(0.85, 0.9, 0.88), 13)
	var br: Array = Game.blood_rows()
	if br.size() > 0:
		_p(_spirit, I18n.t("Your blood: ") + ", ".join(br.map(func(x): return "%s %d%%" % [x[0], int(x[1])])), Color(1.0, 0.75, 0.7), 13)
	if Game.in_sect():
		var sd: Dictionary = Game.sect_def(str(Game.sect.get("id", "")))
		_p(_spirit, I18n.t("Your sect, the %s, walks the way of %s.") % [sd.get("name", ""), str(sd.get("element", "")).capitalize()], Color(0.85, 0.85, 1.0), 13)


# ---- round 44: the World page ------------------------------------------------------------------

func _eff_words(e: Dictionary) -> String:
	## an effect dictionary, in plain words
	var words := {"meditate_mult": "from sitting", "qi_mult": "qi", "damage_mult": "damage", "attack_speed": "strike speed", "insight_mult": "insight",
		"damage_taken": "damage taken", "move_mult": "speed", "research_speed": "research", "swarm_mult": "swarm", "bond_mult": "bonds", "hp_mult": "health"}
	var out := []
	for k in e:
		var v := float(e[k])
		if words.has(k):
			out.append("%+d%% %s" % [int(round((v - 1.0) * 100)), words[k]])
		elif k == "gather_chance":
			out.append(I18n.t("%+d%% to gather") % int(round(v * 100)))
		elif k == "gather_bonus":
			out.append(I18n.t("+%d gathered") % int(v))
		elif k == "loot_luck":
			out.append(I18n.t("%+d%% luck") % int(round(v * 100)))
		elif k == "crit_chance":
			out.append(I18n.t("%+d%% telling blows") % int(round(v * 100)))
		elif k == "dodge_chance":
			out.append(I18n.t("%+d%% to dodge") % int(round(v * 100)))
		elif k == "regen":
			out.append(I18n.t("+%.2f health a second") % v)
		elif k == "sense_radius":
			out.append(I18n.t("+%d spirit sense") % int(v))
		elif str(k).begins_with("craft_"):
			out.append(I18n.t("%+d%% crafting") % int(round(v * 100)))
		elif k == "foe_damage":
			out.append(I18n.t("foes hit %+d%%") % int(round((v - 1.0) * 100)))
		elif k == "foe_speed":
			out.append(I18n.t("foes move %+d%%") % int(round((v - 1.0) * 100)))
		elif k == "foe_hp":
			out.append(I18n.t("foes are %+d%% tougher") % int(round((v - 1.0) * 100)))
		elif k == "elite_mult":
			out.append(I18n.t("more elites"))
		elif k == "loot_mult":
			out.append(I18n.t("better loot"))
	return ", ".join(out)


func fill_world() -> void:
	_clear(_world)
	var W = Game.sys("world")
	var F = Game.sys("factions")
	var S = Game.sys("settlements")
	var R = Game.sys("ruins")
	if W == null:
		_p(_world, "(the world isn't running)")
		return
	_t(_world, "The World", COL["World"])
	# -- the day
	var v := _card(_world, Color(0.75, 0.9, 1.0))
	_h(v, W.date_text(), Color(0.9, 0.95, 1.0), 17)
	var s: Dictionary = W.season()
	_p(v, "%s -- %s" % [str(s.get("name", "")), str(s.get("desc", ""))], Color(0.85, 0.9, 0.85), 13)
	var se := _eff_words(s.get("effect", {}))
	var sf := _eff_words(s.get("foes", {}))
	if se != "" or sf != "":
		_p(v, I18n.t("   This season: %s%s") % [se, ("; " + sf) if sf != "" else ""], Color(0.75, 0.9, 0.8), 13)
	_p(v, I18n.t("   %s  (%d day%s until the season turns.)") % [str(s.get("tip", "")), W.days_to_next_season(), "" if W.days_to_next_season() == 1 else "s"], Color(0.7, 0.75, 0.8), 12)
	var ph: Dictionary = W.phase_def()
	_p(v, "%s -- %s" % [str(ph.get("name", "")), str(ph.get("desc", ""))], Color(0.85, 0.85, 0.95), 13)
	var pe := _eff_words(ph.get("effect", {}))
	var pf := _eff_words(ph.get("foes", {}))
	if pe != "" or pf != "":
		_p(v, I18n.t("   Now: %s%s") % [pe, (I18n.t("; down below, ") + pf) if pf != "" else ""], Color(0.75, 0.8, 0.95), 13)
	var reg: String = W.region()
	var w: Dictionary = W.weather(reg)
	_p(v, I18n.t("Here: %s -- %s") % [str(w.get("name", "")), str(w.get("desc", ""))], Color(0.85, 0.9, 1.0), 13)
	var we := _eff_words(w.get("effect", {}))
	if we != "":
		_p(v, "   %s" % we, Color(0.75, 0.85, 0.95), 13)
	var fc: Array = W.forecast("surface")
	_p(v, I18n.t("Over Eliet: ") + "   ·   ".join(fc.map(func(x): return "%s: %s" % [x[0], x[1]])), Color(0.7, 0.75, 0.85), 12)
	var S0 = Game.sys("settlements")
	if S0:
		for vv in S0.visitors():
			_p(v, "Up in Eliet today: %s." % str(vv["name"]), Color(0.85, 1.0, 0.8), 13)       # round 45
	var fest: Dictionary = W.festival()
	if not fest.is_empty():
		_p(v, I18n.t("TODAY in Eliet: %s. %s") % [str(fest.get("name", "")), str(fest.get("desc", ""))], Color(1.0, 0.85, 0.5), 14)
	else:
		var nf: int = W.next_festival_in()
		var nfd: Dictionary = W.festival(W.day() + nf) if nf >= 0 else {}
		if not nfd.is_empty():
			_p(v, I18n.t("Next festival: %s, in %d day%s.") % [str(nfd.get("name", "")), nf, "" if nf == 1 else "s"], Color(0.9, 0.8, 0.6), 12)
	# -- round 56: the deep's reaches
	var Rch = Game.sys("reaches")
	if Rch:
		var sm: Dictionary = Rch.summary()
		var rv := _card(_world, Color(0.6, 0.9, 0.8))
		_h(rv, I18n.t("The deep's reaches -- %d of %d lands found") % [int(sm["lands"]), int(sm["of"])], Color(0.75, 1.0, 0.9), 17)
		_p(rv, "Past the edge of every floor the deep goes on: a wide land of its own joined by a tunnel through the rock, with a heart at its far end and a warden over it. Deeper floors have two.", Color(0.75, 0.82, 0.85), 12)
		var D: Dictionary = preload("res://scripts/world/Reach.gd").data().get("biomes", {})
		var found: Array = Rch.lands_found()
		var keys: Array = D.keys()
		keys.sort()
		for bk in keys:
			if found.has(bk):
				_p(rv, "   ✓  %s%s -- %s" % [str(D[bk].get("name", bk)), I18n.t("  (its keepsake is yours)") if Rch.keepsakes.has(bk) else "", str(D[bk].get("desc", ""))], Color(0.85, 1.0, 0.9), 13)
			else:
				_p(rv, "   ?  a land you haven't found", Color(0.6, 0.65, 0.7), 13)
		_p(rv, I18n.t("Reaches walked: %d   ·   hearts taken: %d   ·   keepsakes: %d") % [int(sm["reaches"]), int(sm["hearts"]), int(sm["keepsakes"])], Color(0.7, 0.85, 0.8), 12)
	# -- the peoples
	if F:
		_h(_world, "The peoples", COL["World"], 18)
		for fid in F.ids():
			var fd: Dictionary = F.fdef(fid)
			var fcv: Array = fd.get("color", [0.8, 0.8, 0.8])
			var fcol := Color(float(fcv[0]), float(fcv[1]), float(fcv[2]))
			var c := _card(_world, fcol)
			var r := _row(c)
			var nl := _h(r, str(fd.get("name", fid)), fcol.lightened(0.2), 16)
			nl.custom_minimum_size = Vector2(260, 0)
			var t: Dictionary = F.tier(fid)
			var tc: Array = t.get("color", [0.8, 0.8, 0.8])
			_bar(r, F.value(fid) + 1000.0, 2000.0, Color(float(tc[0]), float(tc[1]), float(tc[2])), 200)
			hud._label(r, F.standing_text(fid), 13, Color(float(tc[0]), float(tc[1]), float(tc[2])))
			_p(c, str(fd.get("desc", "")), Color(0.8, 0.82, 0.85), 13)
			if str(fd.get("rival", "")) != "":
				_p(c, "   Rivals: %s. Helping one cools the other." % F.name_of(str(fd["rival"])), Color(0.7, 0.7, 0.75), 12)
			for g in F.gift_lines(fid):
				_p(c, "   %s %s: %s" % ["✓" if bool(g[2]) else "·", g[0], g[1]], Color(0.75, 1.0, 0.8) if bool(g[2]) else Color(0.6, 0.62, 0.66), 12)
			var hs := []
			for h in F.history:
				if str(h.get("f", "")) == fid:
					hs.append(h)
			if not hs.is_empty():
				var last: Dictionary = hs[-1]
				_p(c, I18n.t("   Last: %+d (%s)") % [int(float(last.get("by", 0))), str(last.get("why", ""))], Color(0.65, 0.7, 0.75), 12)
	# -- the camps
	if S:
		_h(_world, "Camps in the deep", COL["World"], 18)
		var ids: Array = S.ids()
		ids.sort_custom(func(a, b): return S._depth_of(a) < S._depth_of(b))
		for sid in ids:
			var sd: Dictionary = S.sdef(sid)
			var met: bool = bool(S.st(sid).get("met", false))
			var c2 := _card(_world, Color(0.55, 0.85, 0.65) if met else Color(0.4, 0.42, 0.46))
			if not met:
				_p(c2, "Someone is living on floor %d. (Not yet met.)" % S._depth_of(sid), Color(0.65, 0.67, 0.7), 13)
				continue
			var r2 := _row(c2)
			var n2 := _h(r2, I18n.t("%s  --  floor %d") % [str(sd.get("name", sid)), S._depth_of(sid)], Color(0.85, 1.0, 0.85), 15)
			n2.custom_minimum_size = Vector2(300, 0)
			var nx: float = S.next_stage_at(sid)
			_bar(r2, float(S.st(sid).get("pros", 0.0)), nx if nx > 0 else maxf(float(S.st(sid).get("pros", 0.0)), 1.0), Color(0.6, 0.9, 0.6), 160)
			hud._label(r2, S.stage_name(sid), 13, Color(0.9, 0.95, 0.8))
			_p(c2, S._stage_line(sid), Color(0.8, 0.85, 0.8), 13)
			_p(c2, I18n.t("   Today: ") + S.need_text(sid), Color(0.75, 0.8, 0.85), 12)
	# -- the old age
	if R:
		_h(_world, "The Old Age", COL["World"], 18)
		_p(_world, "Dig sites ring with jade stones and lines of light, on every floor from the fourth down. The deeper you dig, the older the age.", Color(0.75, 0.8, 0.85), 13)
		for e in R.timeline():
			var c3 := _card(_world, Color(0.45, 0.95, 0.9) if bool(e["known"]) else Color(0.4, 0.55, 0.55))
			var nfound := 0
			for en in e["entries"]:
				if bool(en["found"]):
					nfound += 1
			_h(c3, "%s  --  %s   (%d of %d)" % [str(e["name"]), str(e["when"]), nfound, (e["entries"] as Array).size()], Color(0.7, 1.0, 0.95), 15)
			if bool(e["known"]) or nfound > 0:
				_p(c3, str(e["summary"]), Color(0.85, 0.9, 0.9), 13)
			for en in e["entries"]:
				if bool(en["found"]):
					_p(c3, "   %s: %s" % [str(en["name"]), str(en["text"])], Color(0.8, 0.88, 0.85), 12)
				else:
					_p(c3, "   ? -- something of this age lies on floor %d" % int(en["floor"]), Color(0.55, 0.6, 0.62), 12)
			if bool(e["known"]):
				var era: Dictionary = R.era(str(e["era"]))
				_p(c3, "   Learned: %s" % str(era.get("technique", {}).get("name", "")), Color(1.0, 0.85, 0.5), 12)


# ---- round 121: the Paths (nine classes) ---------------------------------------------------

const PERK_NAMES := {"damage_mult": "damage", "ranged_mult": "ranged damage", "ki_mult": "ki speed", "hp_mult": "health", "attack_speed": "attack speed",
	"crit_chance": "to strike true", "dodge_chance": "to slip a blow", "move_mult": "speed", "qi_mult": "qi", "meditate_mult": "from sitting",
	"swarm_mult": "swarm growth", "loot_luck": "loot luck", "gather_chance": "extra gathering", "craft_success_smithing": "smithing success",
	"craft_success_medicine": "medicine success", "craft_success_alchemy": "alchemy success", "craft_quality_smithing": "smithing quality"}


func _perk_text(d: Dictionary) -> String:
	var parts := []
	for k in d:
		var v := float(d[k])
		var ks := str(k)
		if ks == "damage_taken":
			parts.append(I18n.t("%d%% %s damage taken") % [int(round(absf(v) * 100.0)), "less" if v < 0.0 else "more"])
		elif ks == "regen":
			parts.append(I18n.t("+%s health a second") % str(snappedf(v, 0.1)))
		elif ks == "heal_on_kill":
			parts.append(I18n.t("+%d health per kill") % int(v))
		elif ks == "sight":
			parts.append(I18n.t("+%d sight") % int(v))
		elif ks == "sense_radius":
			parts.append(I18n.t("+%d sense radius") % int(v))
		elif ks == "gather_bonus":
			parts.append(I18n.t("+%d from every vein") % int(v))
		elif ks == "timing":
			parts.append(I18n.t("+%s s parry window") % str(snappedf(v, 0.01)))
		else:
			parts.append("+%s%% %s" % [str(snappedf(v * 100.0, 0.1)).trim_suffix(".0"), str(PERK_NAMES.get(ks, ks))])
	return ", ".join(parts)


func _rank_perk_line(rd: Dictionary) -> String:
	var bits := []
	if rd.has("always"):
		bits.append(_perk_text(rd["always"]))
	if rd.has("weapon"):
		var w: Dictionary = rd["weapon"]
		bits.append(I18n.t("%s (with %s)") % [_perk_text(w.get("effect", {})), "/".join(w.get("skills", []))])
	if rd.has("trigger"):
		bits.append(I18n.t("KEYSTONE: ") + str((rd["trigger"] as Dictionary).get("text", "")))
	if bool(rd.get("art", false)):
		bits.append(I18n.t("learn your art"))
	if str(rd.get("title", "")) != "":
		bits.append(I18n.t("title: ") + str(rd["title"]))
	return "  ·  ".join(bits)


func fill_path() -> void:
	_clear(_path)
	var P = Game.sys("paths")
	if P == null:
		return
	var key := str(P.cfg.get("key", "6"))
	_t(_path, "Path -- the road you walk", COL["Path"])
	_p(_path, I18n.t("A Path is who you are in a fight. Pick one and it grows with what you actually do: kills with its weapons, parries, shots, crafts. Each rank gives a gift, rank 2 teaches an ART (press %s, or the PATH button on a phone), rank 4 a KEYSTONE that triggers as you play. From %s a SECOND path opens and gives half of what a path gives. Nothing here is a trap: change your road any time (free until you are rank 2, then it costs gold), and every path remembers its own progress.") % [key, P.rank_name(int(P.cfg.get("second_path_rank", 3)))], Color(0.85, 0.88, 0.9), 13)
	if P.primary == "":
		var s: String = P.suggested()
		if s != "":
			_p(_path, I18n.t("Your past (%s) points toward the %s -- but any road is open.") % [str(Game.BACKGROUNDS.get(Game.background, {}).get("name", I18n.t("your past"))), str(P.def(s).get("name", s))], Color(1.0, 0.92, 0.6), 13)
		else:
			_p(_path, "You walk no path yet. Choose one below -- it is free the first time.", Color(1.0, 0.92, 0.6), 13)
	else:
		_path_card(P, P.primary, false)
		if P.secondary != "":
			_path_card(P, P.secondary, true)
		elif P.can_second():
			_p(_path, "A second path is open to you. Pick one below (\"Take as second\").", Color(0.7, 1.0, 0.85), 13)
	_h(_path, "The nine roads", COL["Path"].lightened(0.15), 17)
	for p in P.paths():
		var pid := str(p.get("id", ""))
		if pid == P.primary or pid == P.secondary:
			continue
		var v := _card(_path, _path_col(p))
		var r := _row(v)
		var tl := _h(r, str(p.get("name", pid)), _path_col(p).lightened(0.25), 16)
		tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if P.rank_of(pid) > 1:
			hud._label(r, I18n.t("you reached %s here") % P.rank_name(P.rank_of(pid)), 11, Color(0.7, 0.8, 0.7))
		_p(v, str(p.get("blurb", "")), Color(0.85, 0.88, 0.9), 12)
		var wl: Array = p.get("weapons", [])
		_p(v, I18n.t("Art: %s -- %s%s") % [str(p.get("art", {}).get("name", "")), str(p.get("art", {}).get("desc", "")), (I18n.t("   Favours: ") + ", ".join(wl)) if wl.size() > 0 else "   Works with any weapon."], Color(0.65, 0.7, 0.78), 11)
		var br := _row(v)
		var cost: int = P.respec_cost() if P.primary != "" else 0
		_btn(br, I18n.t("Take as my path%s") % ((I18n.t(" (%d gold)") % cost) if cost > 0 else ""), func(): _say(str(P.choose(pid, false).get("text", ""))), P.primary == pid)
		if P.can_second():
			_btn(br, I18n.t("Take as second"), func(): _say(str(P.choose(pid, true).get("text", ""))))


func _path_col(p: Dictionary) -> Color:
	var c: Array = p.get("color", [1, 1, 1])
	return Color(float(c[0]), float(c[1]), float(c[2]))


func _path_card(P, pid: String, is_second: bool) -> void:
	var p: Dictionary = P.def(pid)
	var col := _path_col(p)
	var v := _card(_path, col)
	var rk: int = P.rank_of(pid)
	var r := _row(v)
	var tl := _h(r, I18n.t("%s%s  --  %s (rank %d of 5)") % ["Second path: " if is_second else "", str(p.get("name", pid)), P.rank_name(rk), rk], col.lightened(0.25), 18)
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if is_second:
		_btn(r, I18n.t("Drop"), func():
			P.drop_second()
			_say(I18n.t("You set your second path aside.")))
	_p(v, str(p.get("blurb", "")), Color(0.85, 0.88, 0.9), 13)
	var wl: Array = p.get("weapons", [])
	_p(v, (I18n.t("Favours: ") + ", ".join(wl) + I18n.t(" (weapon gifts count only while one is in hand)")) if wl.size() > 0 else I18n.t("Works with any weapon."), Color(0.65, 0.72, 0.8), 12)
	# the next rank
	var nn: Dictionary = P.next_needs(pid)
	if nn.is_empty():
		_p(v, "You have reached the top of this road.", Color(1.0, 0.92, 0.6), 14)
	else:
		_h(v, I18n.t("Next: rank %d, %s") % [int(nn["rank"]), str(nn["name"])], Color(1.0, 0.95, 0.7), 14)
		if not bool(nn.get("realm_ok", true)):
			_p(v, I18n.t("Needs the realm of %s (you are %s).") % [Game.realm_name_of(int(nn["realm_need"])), Game.realm_name_of(Game.realm)], Color(1.0, 0.7, 0.6), 12)
		for n in nn.get("needs", []):
			var nr := _row(v)
			var lb: Label = hud._label(nr, str(n["label"]), 12, Color(0.8, 0.85, 0.9))
			lb.custom_minimum_size = Vector2(250, 0)
			_bar(nr, float(n["have"]), float(n["need"]), col, 150)
			hud._label(nr, "%d / %d" % [int(n["have"]), int(n["need"])], 11, Color(0.7, 0.75, 0.8))
	# the art
	if P.has_art(pid):
		var a: Dictionary = p.get("art", {})
		var ar := _row(v)
		hud._label(ar, I18n.t("ART: %s  [%s]  ·  ready every %ds") % [str(a.get("name", "")), str(P.cfg.get("key", "6")), int(a.get("cooldown", 25))], 13, Color(1.0, 0.95, 0.6))
		if P.primary != "" and P.secondary != "":
			var slot_is: bool = (P.art_slot == "second") == is_second
			_btn(ar, I18n.t("Readied") if slot_is else I18n.t("Ready this art"), func():
				P.set_art_slot("second" if is_second else "primary")
				_fill("Path"), slot_is)
		_p(v, str(a.get("desc", "")), Color(0.85, 0.88, 0.9), 12)
	# every rank
	for i in range(1, 6):
		var rd: Dictionary = P.rank_def(pid, i)
		var done: bool = rk >= i
		var line := "%s %d  %s -- %s" % ["✓" if done else "·", i, str(rd.get("name", "")), str(rd.get("text", ""))]
		_p(v, line, Color(0.9, 0.95, 0.85) if done else Color(0.6, 0.64, 0.7), 12)
		var pk := _rank_perk_line(rd)
		if pk != "":
			_p(v, "      " + pk, Color(0.7, 0.85, 0.75) if done else Color(0.5, 0.54, 0.6), 11)


# ---- round 137: the crafting journal -----------------------------------------------------------

const LV_COL := [Color(0.5, 0.5, 0.55), Color(0.7, 0.75, 0.85), Color(0.6, 0.9, 0.75), Color(1.0, 0.85, 0.45)]


func _pill(box: Node, text: String, col: Color) -> Label:
	var l: Label = hud._label(box, text, 12, col)
	return l


func _kitchen_section() -> void:
	## round 164: cooking -- meals that heal and give a buff for a while
	var CK = Game.sys("cooking")
	if CK == null:
		return
	_h(_craft, I18n.t("Kitchen"), Color(1.0, 0.82, 0.55))
	_p(_craft, I18n.t("Fish, meat and herbs become meals. Cook at a hearth in any town; eat from the bag. Different meals work together; a practised cook's meals last longer (x%.2f).") % CK.stretch(), Color(0.7, 0.74, 0.82), 13)
	for m in CK.meals():
		var mid := str(m["id"])
		var cv := _card(_craft, Color(1.0, 0.82, 0.55))
		var cr := _row(cv)
		var ct := _h(cr, I18n.t(str(m["name"])), Color(1.0, 0.9, 0.7), 15)
		ct.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hud._label(cr, I18n.t("cooked %d") % int(CK.made.get(mid, 0)), 11, Color(0.6, 0.62, 0.68))
		_p(cv, CK.lines(mid), Color(0.85, 0.88, 0.92), 12)
		var why: String = CK.why_not(mid)
		var br := _row(cv)
		_btn(br, I18n.t("Cook"), func(): _say(CK.cook(mid)); _fill(I18n.t("Craft")), why != "", why)
		hud._label(br, I18n.t("needs ") + CK.needs_text(mid), 11, Color(0.6, 0.62, 0.68))


func fill_craft() -> void:
	_clear(_craft)
	var CB = Game.sys("craftbook")
	if CB == null:
		return
	var acc: Color = COL["Craft"]
	# ---- recipes -----
	var CPl = Game.sys("craftplay")
	if CPl != null:
		var cpr := _row(_craft)
		_btn(cpr, I18n.t("Craft mini-games: %s") % (I18n.t("on") if CPl.enabled else I18n.t("off")), func():
			CPl.enabled = not CPl.enabled
			_fill("Craft"), CPl.enabled, I18n.t("A short skill game before you smith, brew, pour, cut or carve. A good game nudges the odds and the quality a little; skipping costs nothing."))
		var lst: Dictionary = CPl.last
		_p(cpr, I18n.t("Last game: %s") % (str(lst.get("text", "")) + " (" + str(int(round(float(lst.get("score", 0.0)) * 100.0))) + "%)") if not lst.is_empty() else I18n.t("Hammer, simmer, pour, facet, trace -- one for each craft."), Color(0.7, 0.74, 0.82), 13)
	_workshop_section()
	_commission_section()
	_h(_craft, tr("Recipes"), acc)
	_p(_craft, tr("Everything you make is written down here: what went in, who made it, how many times. Make it again from the page."), Color(0.7, 0.74, 0.82), 13)
	var keys: Array = CB.recipe_keys()
	if keys.is_empty():
		_p(_craft, tr("Nothing made yet. Craft something at a bench, forge a piece, or mix at the bench and its recipe appears here."), Color(0.6, 0.62, 0.68))
	for k in keys:
		var v: Dictionary = CB.recipe_view(str(k))
		if v.is_empty():
			continue
		var card := _card(_craft, acc)
		var head := _row(card)
		_h(head, str(v["name"]), Color(0.97, 0.94, 0.86), 17)
		_pill(head, I18n.t("%s · %s · made %d×") % [str(v["kind"]), Game.skill_name(str(v["skill"])) if str(v["skill"]) != "" else "", int(v["times"])], Color(0.62, 0.68, 0.78))
		var ing := []
		for it in v["inputs"]:
			ing.append("%d %s%s" % [int(it["need"]), str(it["name"]), "" if int(it["have"]) >= int(it["need"]) else I18n.t(" (have %d)") % int(it["have"])])
		_p(card, tr("Needs: ") + (", ".join(ing) if ing.size() > 0 else "-") + ((" · %d gold" % int(v["gold"])) if int(v["gold"]) > 0 else ""), Color(0.86, 0.88, 0.92), 13)
		if not (v["design"] as Dictionary).is_empty():
			var dl := []
			for dk in v["design"]:
				dl.append("%s %s" % [str(dk), str(v["design"][dk])])
			_p(card, tr("Design: ") + ", ".join(dl), Color(0.8, 0.75, 0.95), 12)
		if bool(v["remake"]):
			var rk := str(k)
			var b := _btn(card, tr("Make again"), func(): _say(CB.remake(rk)), not bool(v["have_all"]), tr("Uses the same materials and design."))
			b.custom_minimum_size = Vector2(130, 30)
	# ---- herbology -----
	_kitchen_section()
	_t(_craft, tr("Herbology"), COL["Spirit"])
	_shelf_page(CB, "herbs")
	# ---- supplies -----
	_t(_craft, tr("Supplies"), COL["Pack"])
	_p(_craft, tr("Handle a material in a craft and the journal learns its traits; use it a few times and it learns what it adds and what suits it."), Color(0.7, 0.74, 0.82), 13)
	for sh in ["ores", "gems", "beast", "reagents", "tech"]:
		_shelf_page(CB, sh)
	# ---- bestiary -----
	_h(_craft, tr("Bestiary"), Color(1.0, 0.7, 0.65))
	var fm: Array = CB.foes_met()
	_p(_craft, tr("Foes met: %d of %d. Defeat one to open its page; fight it more and the page shows its strength and what it carries.") % [int(fm[0]), int(fm[1])], Color(0.7, 0.74, 0.82), 13)
	var last_floor := -1
	for fid in CB.foes():
		var c: Dictionary = CB.foe_card(str(fid))
		if not bool(c["met"]):
			continue
		if int(c["floor"]) != last_floor:
			last_floor = int(c["floor"])
			var fl: Label = hud._label(_craft, I18n.t("Floor %d") % last_floor, 14, Color(0.6, 0.66, 0.78))
		var card2 := _card(_craft, Color(1.0, 0.7, 0.65))
		var hr := _row(card2)
		_h(hr, str(c["name"]), Color(0.97, 0.94, 0.86), 16)
		_pill(hr, I18n.t("defeated %d×%s") % [int(c["kills"]), I18n.t("  · boss") if bool(c.get("boss", false)) else ""], Color(0.8, 0.66, 0.62))
		if c.has("hp"):
			_p(card2, I18n.t("Strength: %d health, %d damage, speed %.1f") % [int(c["hp"]), int(c["damage"]), float(c["speed"])], Color(0.86, 0.88, 0.92), 13)
		else:
			_p(card2, tr("Fight it a few more times to learn its strength."), Color(0.55, 0.58, 0.65), 12)
		var dr: Array = c.get("drops", [])
		if dr.size() > 0:
			_p(card2, tr("Dropped for you: ") + ", ".join(dr.map(func(i): return Game.item_name(str(i)))), Color(0.8, 0.9, 0.8), 13)
		if c.has("table"):
			var unseen := []
			for it in c["table"]:
				if not (it in dr):
					unseen.append(Game.item_name(str(it)))
			if unseen.size() > 0:
				_p(card2, tr("Also carries: ") + ", ".join(unseen), Color(0.95, 0.85, 0.6), 13)
		elif dr.size() == 0:
			_p(card2, tr("Nothing learned about what it carries yet."), Color(0.55, 0.58, 0.65), 12)


func _story_row(v: Node, nm: String) -> void:
	## round 143: a wayfarer's story (scripts/systems/WayfarerStories.gd)
	var WS = Game.sys("stories")
	if WS == null:
		return
	var sv: Dictionary = WS.view(nm)
	var st := str(sv.get("state", "none"))
	if st == "none":
		return
	var col := Color(0.95, 0.85, 0.65)
	if st == "complete":
		_p(v, I18n.t("Their story is told (%d of %d). Their gift is stronger for it.") % [int(sv["chapter"]), int(sv["of"])], col, 13)
		return
	var head := I18n.t("Story, chapter %d of %d: %s") % [int(sv["chapter"]), int(sv["of"]), tr(str(sv["title"]))]
	if st == "locked":
		_p(v, head + "  ·  " + I18n.t("they will tell it when trust is %d") % int(sv["trust"]), Color(0.6, 0.62, 0.68), 13)
		return
	var sr2 := _row(v)
	if st == "offer":
		_btn(sr2, I18n.t("Hear their story: %s") % tr(str(sv["title"])), func():
			hud.open_dialog(nm + " -- " + tr(str(sv["title"])), tr(str(sv["text"])) + "\n\n" + I18n.t("Needed: %s.") % tr(str(sv["hint"])), [[tr("I'll do it"), func():
				_say(WS.accept(nm))
				hud.close_dialog()
				_fill("Party")], [tr("Not yet"), hud.close_dialog]]))
	else:
		_p(sr2, head + "  ·  " + tr(str(sv["hint"])) + (" %d / %d" % [int(sv["have"]), int(sv["need"])]), col, 13)
		if st == "ready":
			_btn(sr2, tr("Tell them it's done"), func():
				hud.open_dialog(nm, tr(WS.finish(nm)), [[tr("Close"), hud.close_dialog]])
				_fill("Party"))


func _mind_section() -> void:
	## round 146: the swarm's voice (scripts/systems/NaniteMind.gd)
	var NM = Game.sys("nanite_mind")
	if NM == null:
		return
	var mc := Color(0.65, 0.95, 1.0)
	if not NM.awake:
		if Game.nanite_tier() >= 3:
			_p(_swarm, tr("Something in the swarm is almost listening. It wakes at Nanite Ascendance."), Color(0.6, 0.7, 0.75), 12)
		return
	_h(_swarm, I18n.t("%s, your swarm's mind") % NM.char_name, mc)
	_p(_swarm, I18n.t("It has watched how you play: %s. It keeps changing as you do.") % NM.summary(), Color(0.7, 0.74, 0.82), 13)
	var card := _card(_swarm, mc)
	for k in NM.ranked():
		var tr_def: Dictionary = NM.data["traits"][k]
		var rr := _row(card)
		var lb := _h(rr, tr(str(tr_def["name"])), Color(0.9, 0.95, 1.0), 13)
		lb.custom_minimum_size = Vector2(90, 0)
		_bar(rr, float(NM.traits.get(k, 0.0)) * 100.0, 100.0, Color(0.5, 0.85, 1.0), 160)
		_p(rr, tr(str(tr_def["text"])), Color(0.7, 0.75, 0.82), 11)
	var rr2 := _row(card)
	hud._label(rr2, I18n.t("rapport"), 13, Color(1.0, 0.9, 0.8))
	_bar(rr2, NM.rapport, 100.0, Color(1.0, 0.8, 0.5), 200)
	_p(card, I18n.t("Its help grows with rapport: up to +%d%% qi, +%d%% meridian focus, research and cleansing speed, and +%d%% ki arts.") % [int(round(float(NM.data["gift"]["qi_mult"]) * 100.0)), int(round(float(NM.data["gift"]["focus_mult"]) * 100.0)), int(round(float(NM.data["gift"]["ki_mult"]) * 100.0))], Color(0.75, 0.85, 0.8), 12)
	var br := _row(card)
	_btn(br, tr("Ask for advice"), func():
		var a: String = NM.ask()
		if a != "":
			hud.open_dialog(NM.char_name, a, [[tr("Close"), hud.close_dialog]]))
	_btn(br, I18n.t("Tips: %s") % (I18n.t("on") if NM.tips_on else I18n.t("off")), func():
		NM.tips_on = not NM.tips_on
		_fill("Swarm"), false, tr("It speaks up at key moments, never more than once every couple of minutes. Turn it off if you'd rather it stayed quiet."))


func _aspect_section() -> void:
	## round 146: aspecting the swarm to an element (scripts/systems/Aspect.gd)
	var AS = Game.sys("aspect")
	if AS == null:
		return
	var ac := Color(1.0, 0.85, 0.55)
	_h(_swarm, tr("Aspect"), ac)
	if not AS.available():
		_p(_swarm, tr("Your swarm can take an aspect from Nanite Lattice on. Then walk and draw breath (M while moving, or ]) to attune it; sitting refines it."), Color(0.6, 0.62, 0.68), 13)
		return
	_p(_swarm, tr("Choose an element for your swarm. Walk and draw breath (M while moving, or ]) to grow your attunement and keep its buff up -- it fades after a few minutes, so refresh it. Striking, being struck or standing still breaks the flow. Sitting refines the chosen element. Secrets wait at 40 and 80."), Color(0.7, 0.74, 0.82), 13)
	_p(_swarm, tr("Quick flow: click the mouse wheel, press the ` key, or tap FLOW on a touch screen."), Color(0.7, 0.9, 0.8), 12)
	var fr2 := HFlowContainer.new()
	fr2.add_theme_constant_override("h_separation", 6)
	_swarm.add_child(fr2)
	for e in Game.ELEMENTS:
		var el: String = str(e)
		var b := _btn(fr2, tr(str(AS.aspect_def(el).get("name", el))) + "  %d" % int(AS.att[el]), func():
			_say(AS.set_focus(el))
			_fill("Swarm"))
		b.disabled = AS.focus == el
	var cur: Dictionary = AS.aspect_def(AS.focus)
	var cc := _card(_swarm, ac)
	var hr := _row(cc)
	_h(hr, tr(str(cur.get("name", ""))), Color(1.0, 0.93, 0.8), 16)
	_pill(hr, I18n.t("attunement %d / 100  ·  refined %d  ·  strength x%.2f") % [int(AS.att[AS.focus]), int(AS.refine[AS.focus]), AS.strength(AS.focus)], Color(0.8, 0.75, 0.6))
	_bar(hr, float(AS.att[AS.focus]), 100.0, Color(1.0, 0.8, 0.4), 160)
	_p(cc, tr(str(cur.get("text", ""))), Color(0.82, 0.84, 0.9), 12)
	var st := I18n.t("The buff is up (%d s left)") % int(AS.buff_left) if AS.buff_on() else I18n.t("The buff is down. Walk and draw breath.")
	if AS.flowing:
		st = I18n.t("Flowing -- keep walking.") + "  " + st
	_p(cc, st, Color(0.7, 0.9, 0.75) if AS.buff_on() else Color(0.9, 0.75, 0.7), 12)
	_btn(cc, tr("Stop flowing") if AS.flowing else tr("Start flowing (then walk)"), func():
		if AS.flowing:
			AS.stop_flow(I18n.t("You let the flow go."))
		else:
			_say(AS.start_flow())
		_fill("Swarm"), false, tr("Easier on the move: press M while walking, or ]."))
	for r in AS.secret_rows():
		var sc: Color = Color(1.0, 0.9, 0.6) if bool(r["found"]) else Color(0.5, 0.52, 0.58)
		var sp: String = (tr(str(r["name"])) + " -- " + tr(str(r["text"]))) if bool(r["found"]) else I18n.t("??? (attune a thread to %d)") % int(r["att"]) if str(r["element"]) != "" else I18n.t("??? (bring every thread to %d)") % int(r["att"])
		if str(r["element"]) == "" or str(r["element"]) == AS.focus or bool(r["found"]):
			_p(_swarm, ("✓ " if bool(r["found"]) else "· ") + sp, sc, 12)


func _workshop_section() -> void:
	## round 148: the road workshop and the sects' techniques (scripts/systems/Workshop.gd)
	var WS = Game.sys("workshop")
	if WS == null:
		return
	var wc := Color(1.0, 0.8, 0.5)
	_t(_craft, tr("Road Workshop"), wc)
	var have: Array = []
	if WS.road_table():
		have.append(tr("folding table"))
	if WS.field_forge():
		have.append(tr("field forge"))
	if WS.rune_table():
		have.append(tr("alchemist's roll"))
	if WS.has("master"):
		have.append(tr("master's kit"))
	_p(_craft, tr("Build a bench you can carry, one stage at a time, and find the sects' deeper techniques. These are long chains: things to hand over, make, reach and fell. Two lines at a time."), Color(0.7, 0.74, 0.82), 13)
	_p(_craft, I18n.t("You carry: %s") % (", ".join(have) if have.size() > 0 else tr("nothing yet")), Color(0.9, 0.9, 0.75), 13)
	for kind in ["workshop", "sect"]:
		_p(_craft, tr("The bench") if kind == "workshop" else tr("The sects' techniques"), Color(0.85, 0.9, 1.0), 14)
		for ln in WS.lines():
			if str(ln["kind"]) != kind:
				continue
			var id: String = str(ln["id"])
			var st: String = WS.status(id)
			var card := _card(_craft, wc if st != "locked" else Color(0.4, 0.42, 0.5))
			var hr := _row(card)
			_h(hr, ("✓ " if st == "done" else "") + tr(str(ln["name"])), Color(1.0, 0.95, 0.85) if st != "locked" else Color(0.6, 0.62, 0.68), 16)
			_pill(hr, I18n.t("%d steps") % (ln["steps"] as Array).size(), Color(0.7, 0.72, 0.8))
			_p(card, tr(str(ln["text"])), Color(0.82, 0.84, 0.9), 12)
			match st:
				"done":
					_p(card, tr(str(ln["reward"]["text"])), Color(0.7, 0.95, 0.75), 12)
				"locked":
					_p(card, I18n.t("Finish first: %s") % ", ".join(WS.missing_needs(id)), Color(0.6, 0.62, 0.68), 12)
				"open":
					_btn(card, tr("Begin"), func():
						_say(WS.start(id))
						_fill("Craft"))
				_:
					var s: Dictionary = WS.cur(id)
					var p: Array = WS.progress(id)
					var step_no: int = int(WS.act[id]["step"]) + 1
					_p(card, I18n.t("Step %d of %d: %s") % [step_no, (ln["steps"] as Array).size(), tr(str(s["text"]))], Color(1.0, 0.92, 0.7), 13)
					var pr := _row(card)
					_bar(pr, float(p[0]), float(p[1]), Color(1.0, 0.8, 0.45), 200)
					_pill(pr, "%d / %d" % [int(p[0]), int(p[1])], Color(0.8, 0.8, 0.7))
					if str(s["kind"]) == "give":
						_p(card, WS.items_text(s), Color(0.8, 0.85, 0.8), 12)
						_btn(card, tr("Hand over"), func():
							_say(WS.hand_over(id))
							_fill("Craft"), not WS.ready(id), "")
					_btn(card, tr("Set aside"), func():
						WS.abandon(id)
						_fill("Craft"))


func _inner_section() -> void:
	## round 147: the inner world (scripts/systems/InnerWorld.gd)
	var IW = Game.sys("inner_world")
	if IW == null:
		return
	var ic := Color(0.6, 0.95, 0.85)
	_h(_swarm, tr("Inner World"), ic)
	if not IW.open():
		_p(_swarm, tr("A pocket of space behind your own eyes. It opens when your swarm can hold it (Nanite Lattice), and it grows with sitting, tending and the beasts that rest in it."), Color(0.6, 0.62, 0.68), 13)
		return
	var ld: Dictionary = IW.level_def()
	var top := _card(_swarm, ic)
	var tr1 := _row(top)
	_h(tr1, I18n.t("%s  (level %d)") % [tr(str(ld.get("name", ""))), IW.level()], Color(0.9, 1.0, 0.95), 16)
	if IW.next_at() > 0.0:
		_bar(tr1, IW.xp, IW.next_at(), Color(0.5, 0.95, 0.8), 160)
	_p(top, tr(str(ld.get("text", ""))), Color(0.82, 0.86, 0.9), 12)
	_p(top, tr("Its living meters each give a small permanent gift. The realm asks for one of them each day; feed that one and it grows twice as fast."), Color(0.7, 0.74, 0.82), 12)
	for m in ["qi", "flora", "fauna"]:
		var mr := _row(top)
		var mm: String = m
		_pill(mr, IW.meter_text(mm) + ("  *" if IW.need() == mm else ""), Color(1.0, 0.9, 0.6) if IW.need() == mm else Color(0.75, 0.82, 0.85))
		_bar(mr, float(IW.meters[mm]), 100.0, Color(0.5, 0.9, 0.75), 180)
	_p(top, I18n.t("Today the realm wants: %s.") % IW.meter_text(IW.need()) + "  " + tr("Qi grows with sitting, flora with picking, fauna with beasts at rest."), Color(0.9, 0.9, 0.7), 12)
	# the long road: the sects' techniques are how this world grows its big rooms
	var lr := _card(_swarm, ic)
	_h(lr, I18n.t("The long road  (level cap %d of %d)") % [IW.level_cap(), IW.levels().size()], Color(1.0, 0.9, 0.6), 15)
	_p(lr, tr("Sitting and tending fill your world up to its ceiling. Only the sects' techniques (Craft, Road Workshop) raise the ceiling and widen its rooms."), Color(0.78, 0.8, 0.86), 12)
	for imp in IW.improvements():
		_p(lr, ("✓  " if bool(imp[2]) else "·  ") + tr(str(imp[1])), Color(0.7, 0.95, 0.75) if bool(imp[2]) else Color(0.7, 0.72, 0.78), 12)
	# sitting
	var sc := _card(_swarm, ic)
	_h(sc, tr("When you sit"), Color(0.9, 1.0, 0.95), 15)
	_p(sc, I18n.t("Your breath goes into: %s.") % IW.focus_text(), Color(0.8, 0.9, 0.85), 12)
	var fr := HFlowContainer.new()
	fr.add_theme_constant_override("h_separation", 6)
	sc.add_child(fr)
	var b1 := _btn(fr, tr("Tend the realm"), func():
		_say(IW.set_focus("grow"))
		_fill("Swarm"))
	b1.disabled = IW.focus == "grow"
	var b2 := _btn(fr, tr("Practice ground"), func():
		_say(IW.set_focus("drill"))
		_fill("Swarm"), not IW.room_open("ground"), "" if IW.room_open("ground") else I18n.t("Opens at level %d.") % int(IW.data["rooms"]["ground"]))
	b2.disabled = IW.focus == "drill" or not IW.room_open("ground")
	var b3 := _btn(fr, tr("Dao pool"), func():
		_say(IW.set_focus("pool"))
		_fill("Swarm"), not IW.room_open("pool"), "" if IW.room_open("pool") else I18n.t("Opens at level %d.") % int(IW.data["rooms"]["pool"]))
	b3.disabled = IW.focus == "pool" or not IW.room_open("pool")
	if IW.room_open("ground"):
		_p(sc, tr("Practice ground: pick what to drill. It trains while you sit, up to a daily limit."), Color(0.7, 0.74, 0.82), 12)
		var dr := HFlowContainer.new()
		dr.add_theme_constant_override("h_separation", 6)
		sc.add_child(dr)
		for s in IW.drill_skills():
			var sk: String = str(s)
			var bb := _btn(dr, tr(str(Game.skill_defs.get(sk, {}).get("name", sk))) + "  Lv %d" % Game.skill_level(sk), func():
				_say(IW.set_focus("drill", sk))
				_fill("Swarm"))
			bb.disabled = IW.drill_skill == sk and IW.focus == "drill"
	# garden
	var gc := _card(_swarm, Color(0.7, 0.95, 0.7))
	_h(gc, tr("Inner garden"), Color(0.8, 1.0, 0.8), 15)
	_p(gc, tr("Grows in half the time, faster as flora grows, and keeps growing while you are away."), Color(0.7, 0.74, 0.82), 12)
	for i in IW.plot_count():
		var idx: int = i
		var pr := _row(gc)
		match IW.state(i):
			"empty":
				_h(pr, I18n.t("Plot %d: empty") % (i + 1), Color(0.9, 0.95, 0.9), 14)
				for h in IW.herbs():
					var hid: String = str(h["id"])
					_btn(pr, I18n.t("Plant %s  (you have %d)") % [Game.item_name(hid), Game.count(hid)], func():
						_say(IW.plant(idx, hid))
						_fill("Swarm"), Game.count(hid) < 1, "")
			"growing":
				_h(pr, I18n.t("Plot %d: %s, growing") % [i + 1, Game.item_name(str(IW.plots[i]["herb"]))], Color(0.9, 0.95, 0.9), 14)
				_p(pr, I18n.t("about %d minutes left") % IW.minutes_left(i), Color(0.7, 0.8, 0.7), 12)
			_:
				_h(pr, I18n.t("Plot %d: %s, ready") % [i + 1, Game.item_name(str(IW.plots[i]["herb"]))], Color(1.0, 0.95, 0.7), 14)
				_btn(pr, tr("Pick"), func():
					_say(IW.pick(idx))
					_fill("Swarm"))
	# habitat
	var hc := _card(_swarm, Color(0.95, 0.85, 0.6))
	_h(hc, tr("Habitat"), Color(1.0, 0.92, 0.75), 15)
	if not IW.room_open("habitat"):
		_p(hc, I18n.t("Opens at level %d.") % int(IW.data["rooms"]["habitat"]), Color(0.6, 0.62, 0.68), 12)
	else:
		_p(hc, I18n.t("Beasts resting in your spirit space live here (%d of %d places). Their bond grows faster, and now and then one brings back a find.") % [IW.housed().size(), IW.capacity()], Color(0.7, 0.74, 0.82), 12)
		for b in IW.housed():
			_p(hc, "%s  (%s)  ·  %s" % [str(b.get("name", "")), tr(str(b.get("species", "")).replace("_", " ").capitalize()), I18n.t("bond %d") % int(float(b.get("bond", 0.0)))], Color(0.9, 0.92, 0.85), 12)
		if IW.housed().is_empty():
			_p(hc, tr("No beast is resting. Send one to rest from the Party page and it will live here."), Color(0.6, 0.62, 0.68), 12)
		var parts := []
		for k in IW.stock:
			parts.append("%s x%d" % [Game.item_name(str(k)), int(IW.stock[k])])
		_p(hc, (I18n.t("Waiting: %s") % ", ".join(parts)) if parts.size() > 0 else tr("Nothing waiting yet."), Color(0.85, 0.85, 0.7), 12)
		_btn(hc, tr("Collect finds"), func():
			_say(IW.collect())
			_fill("Swarm"), IW.stock.is_empty(), "")


func _collection_section() -> void:
	## round 145: completion percentages (scripts/systems/Collection.gd)
	var CO = Game.sys("collection")
	if CO == null:
		return
	CO.claim()
	var col := Color(0.95, 0.85, 1.0)
	_h(_road, tr("Collection"), col)
	_p(_road, tr("What the world holds, and how much of it is in your book. Every tenth of the whole gives a little insight. Unseen things show as ???."), Color(0.7, 0.74, 0.82), 13)
	var top := _row(_road)
	_h(top, I18n.t("%d%% complete") % CO.percent(), Color(1.0, 0.95, 0.8), 17)
	_bar(top, CO.overall() * 100.0, 100.0, Color(0.85, 0.7, 1.0), 320)
	for c in CO.categories():
		if int(c["need"]) <= 0:
			continue
		var card := _card(_road, col)
		var hr := _row(card)
		_h(hr, str(c["name"]), Color(0.97, 0.94, 0.9), 15)
		_pill(hr, "%d / %d" % [int(c["have"]), int(c["need"])], Color(0.72, 0.7, 0.85))
		_bar(hr, float(c["have"]), float(c["need"]), Color(0.7, 0.6, 0.95), 200)
		var seen: Array = c["seen"]
		if seen.size() > 0 and str(c["id"]) != "foes":
			_p(card, "  ·  ".join(seen), Color(0.82, 0.84, 0.9), 12)
		var hid: Array = c["hidden"]
		if hid.size() > 0:
			_p(card, I18n.t("Still unseen: %s") % "  ·  ".join(hid.slice(0, 6)) + (" ..." if hid.size() > 6 else ""), Color(0.55, 0.57, 0.65), 12)


func _garden_section() -> void:
	## round 145: three herb plots at your lodging (scripts/systems/Garden.gd)
	var GA = Game.sys("garden")
	if GA == null:
		return
	var gc := Color(0.7, 0.95, 0.7)
	_h(_road, tr("Garden"), gc)
	_p(_road, tr("Plant a herb, come back later, pick two. It grows in real time, even while you are away. A day's picking is capped, so this is a pastime."), Color(0.7, 0.74, 0.82), 13)
	if not GA.in_town():
		_p(_road, tr("The garden is at your lodging, in town."), Color(0.6, 0.62, 0.68), 13)
	for i in GA.plots.size():
		var card := _card(_road, gc)
		var hr := _row(card)
		var idx: int = i
		match GA.state(i):
			"empty":
				_h(hr, I18n.t("Plot %d: empty") % (i + 1), Color(0.9, 0.95, 0.9), 15)
				for h in GA.herbs():
					var hid: String = str(h["id"])
					_btn(hr, I18n.t("Plant %s  (you have %d)") % [Game.item_name(hid), Game.count(hid)], func():
						_say(GA.plant(idx, hid))
						_fill("Road"), Game.count(hid) < 1 or not GA.in_town(), "")
			"growing":
				_h(hr, I18n.t("Plot %d: %s, growing") % [i + 1, Game.item_name(str(GA.plots[i]["herb"]))], Color(0.9, 0.95, 0.9), 15)
				_p(hr, I18n.t("about %d minutes left") % GA.minutes_left(i), Color(0.7, 0.8, 0.7), 12)
			_:
				_h(hr, I18n.t("Plot %d: %s, ready") % [i + 1, Game.item_name(str(GA.plots[i]["herb"]))], Color(1.0, 0.95, 0.7), 15)
				_btn(hr, tr("Pick"), func():
					_say(GA.pick(idx))
					_fill("Road"), not GA.in_town(), "")


func _today_section() -> void:
	## round 144: the day's offerings (scripts/systems/Boons.gd)
	var BO = Game.sys("boons")
	if BO == null:
		return
	var warm := Color(0.75, 0.95, 0.8)
	_h(_road, tr("Today"), warm)
	_p(_road, tr("Each day brings something fresh: a blessing for the next trip, a pedlar, a shrine, a hunt. None of it costs real money, and skipping it costs nothing."), Color(0.7, 0.74, 0.82), 13)
	if not BO.in_town():
		_p(_road, tr("These are laid out in towns. Come back to choose."), Color(0.6, 0.62, 0.68), 13)
	var act: Array = BO.active_text()
	if act.size() > 0:
		_p(_road, I18n.t("On this trip: %s") % ", ".join(act), Color(1.0, 0.92, 0.7), 14)
	# blessings and hardships
	var bc := _card(_road, warm)
	_h(bc, tr("Before you set out"), Color(0.9, 1.0, 0.92), 16)
	_p(bc, tr("One blessing from today's three. Optionally one hardship too, which pays a little more qi and finds while it lasts. Both end when you are back in a town."), Color(0.78, 0.82, 0.9), 12)
	for kind in ["boon", "curse"]:
		var ids: Array = BO.boon_offers() if kind == "boon" else BO.curse_offers()
		_p(bc, tr("Blessings") if kind == "boon" else tr("Hardships"), Color(0.85, 0.9, 1.0), 13)
		for id in ids:
			var d: Dictionary = BO.boon_def(str(id)) if kind == "boon" else BO.curse_def(str(id))
			var on := str(BO.run[kind]) == str(id)
			var rr := _row(bc)
			var k2: String = kind
			var i2: String = str(id)
			_btn(rr, ("✓ " if on else "") + tr(str(d["name"])), func():
				_say(BO.pick(k2, "" if on else i2))
				_fill("Road"), not BO.can_change(), "")
			_p(rr, tr(str(d["text"])), Color(0.8, 0.85, 0.8) if kind == "boon" else Color(0.95, 0.8, 0.75), 12)
	# the pedlar
	var pc := _card(_road, Color(1.0, 0.85, 0.5))
	_h(pc, I18n.t("%s is in town today") % tr(BO.merchant_name()), Color(1.0, 0.92, 0.7), 16)
	_p(pc, tr("Goods at twice their base price, two of each a day. For the things that are hard to come by, not for getting rich."), Color(0.78, 0.82, 0.9), 12)
	for s in BO.merchant_stock():
		var pr := _row(pc)
		var sid: String = str(s["id"])
		_btn(pr, I18n.t("Buy %s  (%d gold)") % [Game.item_name(sid), int(s["price"])], func():
			_say(BO.merchant_buy(sid))
			_fill("Road"), int(s["left"]) <= 0 or Game.gold < int(s["price"]) or not BO.in_town(), "")
		_p(pr, I18n.t("%d left today") % int(s["left"]) + "  ·  " + I18n.t("you carry %d") % Game.count(sid), Color(0.7, 0.8, 0.7), 12)
	# the shrine
	var sh: Dictionary = BO.shrine_today()
	if not sh.is_empty():
		var sc := _card(_road, Color(0.7, 0.85, 1.0))
		_h(sc, tr("The day's shrine: ") + tr(str(sh["name"])), Color(0.85, 0.93, 1.0), 16)
		_p(sc, tr(str(sh["text"])), Color(0.78, 0.82, 0.9), 12)
		_btn(sc, tr("Kneel (once a day)") if not BO.shrine_used else tr("You have knelt today"), func():
			_say(BO.shrine_use())
			_fill("Road"), not BO.shrine_ready(), "")
	# the quarry
	var q: Dictionary = BO.quarry()
	if str(q["species"]) != "":
		var qc := _card(_road, Color(1.0, 0.75, 0.6))
		_h(qc, I18n.t("The day's quarry: %s") % tr(str(q["name"])), Color(1.0, 0.9, 0.8), 16)
		_p(qc, I18n.t("Hunt %d of them today for a little insight and gold. %d of %d.") % [int(q["need"]), mini(int(q["kills"]), int(q["need"])), int(q["need"])] + ("  ✓" if bool(q["paid"]) else ""), Color(0.82, 0.84, 0.9), 13)


func _commission_section() -> void:
	## round 143: the commission board (scripts/systems/Commissions.gd)
	var CM = Game.sys("commissions")
	if CM == null:
		return
	var gold := Color(1.0, 0.85, 0.5)
	_h(_craft, tr("Commissions"), gold)
	_p(_craft, tr("Named clients post orders in every town, four a day. Make the thing and bring it to any town within three days. It pays a little better than a trader, earns standing with the matching guild, and gives some practice. At most three at a time."), Color(0.7, 0.74, 0.82), 13)
	var mine: Array = CM.active_orders()
	if mine.size() > 0:
		_p(_craft, I18n.t("Your orders (%d of %d):") % [mine.size(), int(CM.cfg().get("max_active", 3))], Color(0.8, 0.9, 0.8), 14)
	for o in mine:
		var oid := str(o["id"])
		var card := _card(_craft, gold)
		var hr := _row(card)
		_h(hr, "%d x %s%s" % [int(o["n"]), Game.item_name(str(o["item"])), CM.quality_text(int(o["q"]))], Color(0.97, 0.94, 0.86), 16)
		_pill(hr, I18n.t("%d gold  ·  %s  ·  until day %d") % [int(o["gold"]), Game.skill_name(str(o["skill"])), int(o["expires"]) - int(CM._day()) + 1] if false else I18n.t("%d gold  ·  %s") % [int(o["gold"]), Game.skill_name(str(o["skill"]))], Color(0.62, 0.68, 0.78))
		_p(card, CM.client_line(o), Color(0.86, 0.88, 0.92), 13)
		var have := int(CM.have_for(o))
		var br := _row(card)
		_btn(br, tr("Deliver"), func():
			_say(CM.deliver(oid))
			_fill("Craft"), not CM.can_deliver(o), tr("Hand it over in any town."))
		_btn(br, tr("Drop"), func():
			CM.abandon(oid)
			_fill("Craft"))
		_p(br, I18n.t("In your pack: %d of %d") % [mini(have, int(o["n"])), int(o["n"])] + ("" if CM.in_town() else "  ·  " + I18n.t("deliver it in a town")), Color(0.7, 0.8, 0.7), 12)
	if CM.in_town():
		var open: Array = CM.board(str(Game.current_level))
		_p(_craft, I18n.t("On the board in %s:") % CM.town_name(str(Game.current_level)), Color(0.85, 0.88, 0.95), 14)
		if open.is_empty():
			_p(_craft, tr("Nothing left on the board today. It fills again tomorrow."), Color(0.6, 0.62, 0.68), 13)
		for o in open:
			var oid2 := str(o["id"])
			var card2 := _card(_craft, Color(0.6, 0.6, 0.7))
			var h2 := _row(card2)
			_h(h2, "%d x %s%s" % [int(o["n"]), Game.item_name(str(o["item"])), CM.quality_text(int(o["q"]))], Color(0.97, 0.94, 0.86), 16)
			_pill(h2, I18n.t("%d gold  ·  %s") % [int(o["gold"]), Game.skill_name(str(o["skill"]))], Color(0.62, 0.68, 0.78))
			_p(card2, CM.client_line(o), Color(0.86, 0.88, 0.92), 13)
			var extra := []
			var gid := str(CM.cfg().get("guilds", {}).get(str(o["skill"]), ""))
			if gid != "":
				extra.append(I18n.t("+%d standing with the %s") % [int(o["rep"]), Game.guild_name(gid)])
			if bool(o.get("bonus", false)):
				extra.append(I18n.t("and a find"))
			if extra.size() > 0:
				_p(card2, ", ".join(extra), Color(0.7, 0.85, 0.75), 12)
			_btn(card2, tr("Take it"), func():
				_say(CM.accept(oid2))
				_fill("Craft"), mine.size() >= int(CM.cfg().get("max_active", 3)))
	else:
		_p(_craft, tr("Commissions are posted in towns. Come back to a town's board to take new ones."), Color(0.6, 0.62, 0.68), 13)


func _shelf_page(CB, sh: String) -> void:
	var pr: Array = CB.shelf_progress(sh)
	var hdr: Label = hud._label(_craft, I18n.t("%s  (%d of %d found)") % [CB.shelf_name(sh), int(pr[0]), int(pr[1])], 15, Color(0.82, 0.9, 1.0) if sh != "herbs" else Color(0.75, 1.0, 0.8))
	if sh == "herbs":
		_p(_craft, CB.shelf_blurb(sh), Color(0.7, 0.74, 0.82), 13)
	var shown := 0
	for id in CB.materials_on(sh):
		var c: Dictionary = CB.material_card(str(id))
		if int(c["level"]) <= 0:
			continue
		shown += 1
		var card := _card(_craft, LV_COL[int(c["level"])])
		var hr := _row(card)
		_h(hr, str(c["name"]), Color(0.97, 0.94, 0.86), 16)
		_pill(hr, I18n.t("%s · you carry %d") % [str(c["level_name"]), int(c["count"])], LV_COL[int(c["level"])])
		_p(card, str(c.get("desc", "")), Color(0.74, 0.77, 0.84), 12)
		if int(c["level"]) < 2:
			_p(card, tr("Work it into a craft, or study it, to learn what it does."), Color(0.55, 0.58, 0.65), 12)
			continue
		var tl := []
		for t in c["traits"]:
			tl.append("%s %d%s" % [str(t["name"]), int(t["level"]), (" (%s)" % str(t["desc"])) if str(t.get("desc", "")) != "" else ""])
		_p(card, tr("Adds to a craft: ") + "; ".join(tl), Color(0.86, 0.9, 0.95), 13)
		if int(c["level"]) >= 3:
			_p(card, str(c["element_note"]), Color(0.72, 0.8, 0.9), 12)
		var pairs: Array = c.get("pairs", [])
		if pairs.size() > 0:
			var pl := []
			for p in pairs:
				pl.append("%s (%s)" % [str(p["name"]), str(p["why"])])
			_p(card, tr("Pairs well with: ") + "; ".join(pl), Color(0.7, 0.95, 0.8), 13)
		if int(c.get("pairs_hidden", 0)) > 0:
			var hn := int(c["pairs_hidden"])
			_p(card, (tr("%d more partners you have not found yet.") % hn) if hn <= 8 else tr("Many more partners are out there, in places you have not been."), Color(0.95, 0.85, 0.6), 12)
		if int(c["level"]) >= 3 and (c["uses"] as Array).size() > 0:
			var ul: Array = c["uses"]
			_p(card, tr("Goes into: ") + ", ".join(ul.slice(0, 6)) + ((I18n.t(" -- and %d more") % (ul.size() - 6)) if ul.size() > 6 else ""), Color(0.86, 0.88, 0.92), 12)
		var where := []
		for w in c.get("found", []):
			where.append(hud._place_name(w))
		if where.size() > 0:
			_p(card, tr("Found: ") + ", ".join(where), Color(0.62, 0.68, 0.78), 12)
		if (c["dropped_by"] as Array).size() > 0:
			_p(card, tr("Dropped by: ") + ", ".join(c["dropped_by"]), Color(0.62, 0.68, 0.78), 12)
	if shown == 0:
		_p(_craft, tr("Nothing found here yet."), Color(0.55, 0.58, 0.65), 12)


# ---- round 139: the Dao page, and your own difficulty -------------------------------------------------------------

func fill_dao() -> void:
	_clear(_dao)
	var D = Game.sys("dao")
	if D == null:
		return
	var acc: Color = COL["Dao"]
	_t(_dao, "Dao", acc)
	_p(_dao, tr("The dao is the grain of the world. First you learn to feel it; then you choose which way you will follow it. Nothing here is bought, and no way is the best one."), Color(0.7, 0.74, 0.82), 13)
	# ---- sense -----
	var c := _card(_dao, acc)
	_h(c, "%s: %s" % [tr("Dao sense"), tr(D.stage_name())], Color(0.97, 0.94, 0.86), 18)
	_p(c, tr(D.stage_text()), Color(0.8, 0.84, 0.9), 13)
	var nx: float = D.next_stage_at()
	if nx > 0.0:
		_bar(c, D.sense, nx, acc, 320.0)
		_p(c, "%d / %d  %s" % [int(D.sense), int(nx), tr("to the next stage. Sitting and doing both grow it.")], Color(0.62, 0.68, 0.78), 12)
	_p(c, tr("Sense sets how deep any one dao can go: you cannot understand what you cannot yet see."), Color(0.62, 0.68, 0.78), 12)
	var left: int = D.contemplates_left()
	var cb := _btn(c, tr("Contemplate this place") + "  (%d)" % left, func(): _say(D.contemplate()), left <= 0, tr("Stand still and feel which way the place leans. A few times a day."))
	cb.custom_minimum_size = Vector2(220, 32)
	if str(D.cont.get("day", "")) == Game.today() and str(D.cont.get("dao", "")) != "" and str(D.cont.get("level", "")) == Game.current_level:
		_p(c, tr("This place leans toward the %s dao today: what you do here in its way counts twice.") % str(D.def(str(D.cont["dao"])).get("name", "")), Color(0.75, 0.9, 1.0), 13)
	# ---- the eight -----
	_h(_dao, tr("The eight ways"), acc, 18)
	for did in D.dao_ids():
		var d: Dictionary = D.def(str(did))
		var r: int = D.rank(str(did))
		var rp: int = D._rank_of(str(did))
		var card := _card(_dao, acc if str(did) == D.focus else Color(0.35, 0.4, 0.5))
		var head := _row(card)
		var nm: String = str(D.founded["name"]) if D.is_founded(str(did)) else tr(str(d.get("name", did)))
		_h(head, nm, Color(0.97, 0.94, 0.86), 17)
		_pill(head, tr(D.rank_name(r)) + ("  " + tr("(held back by dao sense)") if rp > r else ""), LV_COL[mini(r / 2, LV_COL.size() - 1)])
		if str(did) == D.focus:
			_pill(head, tr("following"), acc)
		_p(card, tr(str(d.get("text", ""))), Color(0.8, 0.84, 0.9), 12)
		var nr: float = D.next_rank_at(str(did))
		var have: float = float(D.pts.get(str(did), 0.0))
		if nr > 0.0:
			_bar(card, have, nr, acc, 260.0)
		var gl := []
		var fx: Dictionary = D.dao_fx(str(did))
		for k in fx:
			gl.append(_fx_text(str(k), float(fx[k])))
		_p(card, tr("Gives now: ") + (", ".join(gl) if gl.size() > 0 else tr("nothing yet")), Color(0.7, 0.9, 0.78), 12)
		if str(did) != D.focus:
			var fb := _btn(card, tr("Follow this way"), func(): _say(D.set_focus(str(did))))
			fb.custom_minimum_size = Vector2(150, 28)
	# ---- your own -----
	_h(_dao, tr("A way of your own"), acc, 18)
	if not D.founded.is_empty():
		var fd: Dictionary = D.def(str(D.founded["dao"]))
		var tn := ""
		for t in fd.get("tenets", []):
			if str(t[0]) == str(D.founded.get("tenet", "")):
				tn = "%s -- %s" % [tr(str(t[1])), tr(str(t[2]))]
		_p(_dao, "%s: %s %s. %s" % [str(D.founded["name"]), tr("a way of the"), tr(str(fd.get("name", ""))), tn], Color(0.97, 0.94, 0.86), 14)
	elif D.can_found():
		_p(_dao, tr("You have gone as far down this way as others went. Name yours, and choose what it holds to."), Color(0.85, 0.88, 0.92), 13)
		var le := LineEdit.new()
		le.placeholder_text = tr("the name of your dao")
		le.custom_minimum_size = Vector2(260, 30)
		_dao.add_child(le)
		for t in D.def(D.focus).get("tenets", []):
			var tid := str(t[0])
			var tb := _btn(_dao, "%s -- %s" % [tr(str(t[1])), tr(str(t[2]))], func(): _say(D.found(le.text, tid)))
			tb.custom_minimum_size = Vector2(320, 30)
	else:
		_p(_dao, tr("Follow one way to its end (dao sense: Dao-seeing, and the way at its fullest) and you may found a dao of your own: a name, a tenet, and half again the gift."), Color(0.62, 0.68, 0.78), 13)


func _fx_text(key: String, v: float) -> String:
	var names := {"damage_mult": "damage", "hp_mult": "life", "qi_mult": "qi", "meditate_mult": "sitting", "attack_speed": "speed", "damage_taken": "damage taken",
		"heal_on_kill": "life per kill", "gather_chance": "gathering", "sense_radius": "sense radius", "craft_success": "craft success", "craft_quality": "craft quality",
		"loot_luck": "luck", "crit_chance": "crits", "dodge_chance": "dodging", "burn_on_hit": "burning", "regen": "mending"}
	var nm: String = tr(str(names.get(key, key)))
	if key in Game.ADDITIVE_KEYS or key.begins_with("craft_"):
		if key in ["heal_on_kill", "sense_radius", "regen"]:
			return "+%.1f %s" % [v, nm]
		return "+%.1f%% %s" % [v * 100.0, nm]
	return "%+.1f%% %s" % [(v - 1.0) * 100.0, nm]


func _difficulty_section() -> void:
	var Df = Game.sys("difficulty")
	if Df == null:
		return
	var acc := Color(1.0, 0.7, 0.55)
	_h(_system, tr("Difficulty"), acc, 18)
	_p(_system, tr("Yours to set, in the village. Harder pays more qi and more finds; gentler pays less. Online play always runs on the server's own numbers."), Color(0.7, 0.74, 0.82), 13)
	var r := _row(_system)
	for t in Df.tiers():
		var tid := str(t.get("id", ""))
		var b := _btn(r, tr(str(t.get("name", tid))), func(): _say(Df.set_tier(tid)), tid == Df.tier, tr(str(t.get("text", ""))))
		b.custom_minimum_size = Vector2(96, 30)
	_p(_system, tr(str(Df.tier_def().get("text", ""))), Color(0.85, 0.88, 0.92), 13)
	_p(_system, tr("Handicaps (you give yourself these):"), Color(0.8, 0.84, 0.9), 13)
	var r2 := _row(_system)
	for h in Df.handicap_list():
		var hid := str(h.get("id", ""))
		var on: bool = Df.handicaps.has(hid)
		var hb := _btn(r2, ("[x] " if on else "[ ] ") + tr(str(h.get("name", hid))), func(): _say(Df.toggle_handicap(hid)), false, tr(str(h.get("text", ""))))
		hb.custom_minimum_size = Vector2(130, 30)
	var rw := int(round(Df.reward() * 100.0))
	_p(_system, "%s %+d%%" % [tr("Reward from kills now:"), rw] + ("" if Df.can_change() else "   (" + tr("change it in the village") + ")"), Color(0.75, 0.9, 0.8), 12)


func _access_section() -> void:
	## round 142a: accessibility (scripts/core/Access.gd) -- each button steps through that setting's choices
	var Acc = preload("res://scripts/core/Access.gd")
	_h(_system, tr("Accessibility"), Color(0.75, 1.0, 0.85), 18)
	_p(_system, tr("Everything here is off until you turn it on, and belongs to this device, not your character."), Color(0.7, 0.74, 0.82), 13)
	for key in Acc.ORDER:
		var k: String = key
		var r := _row(_system)
		var cur: String = Acc.get_opt(k)
		var b := _btn(r, "%s: %s" % [tr(str(Acc.TITLE[k])), tr(str(Acc.LABEL[cur]))], func():
			Acc.step(k, get_tree())
			fill_system.call_deferred())
		b.custom_minimum_size = Vector2(380, 30)
		_p(_system, tr(str(Acc.HELP[k])), Color(0.62, 0.68, 0.78), 12)


func _language_section() -> void:
	_h(_system, tr("Language"), Color(0.8, 0.9, 1.0), 18)
	var fl := HFlowContainer.new()
	fl.add_theme_constant_override("h_separation", 6)
	fl.add_theme_constant_override("v_separation", 6)
	_system.add_child(fl)
	for row in I18n.LANGS:
		var code := str(row[0])
		var b := _btn(fl, str(row[1]), func(): I18n.set_language(code), code == I18n.current)
		b.custom_minimum_size = Vector2(120, 30)
	if I18n.current == "en":
		_p(_system, "English is the source text.", Color(0.62, 0.68, 0.78), 12)
	else:
		_p(_system, (I18n.t("%d phrases are translated: menus, items, floors, quests and story. Anything not yet reviewed by a native speaker may read oddly -- tell us what to fix.") % I18n.coverage()), Color(0.62, 0.68, 0.78), 12)
