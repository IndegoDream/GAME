extends HBoxContainer
## The pack (I), round 27. Robert, 2026-10-03: "I need an actual inventory
## with an equipment dummy or screen with armour on it".
##
## Left: you, on a turning dummy, wearing exactly what you wear (Armour.gd),
## with every slot laid out around you -- head and body down the left,
## hands and legs down the right, eight rings and two toe rings below.
## Click a slot to choose what goes there.
## Right, in tabs:
##   Pack       everything you carry, by kind, with what you can do with it
##   Bench      anything with anything (Game.combine_attempt): the odds,
##              the chance of a surprise, what you understand of the mix
##   Forge      make a piece of any kind from a material you have
##   Nanoforge  the nanotech tree (data/nanotech.json)
##   Formulas   what you know how to make, and a button to set it up
##   Runes      (round 38) carve runes and set them into what you wear; your
##              talismans; rune words found; at a table, carve and draw
## The window fades in, and the dummy turns (drag it to turn it yourself).

var hud                         # HUD.gd, for its label/button helpers
var tabs: TabContainer
var pack_body: VBoxContainer
var _summary: Label
var _detail: Label
var _view: SubViewport
var _view_box: SubViewportContainer
var _pivot: Node3D
var _dummy: Node3D
var _dummy_key := ""
var _spin := 0.0
var _drag := false
var _left_slots: VBoxContainer
var _right_slots: VBoxContainer
var _ring_row: GridContainer          # (round 39: two rows of five, so the pack fits beside the menu)
var _bench_body: VBoxContainer
var _forge_body: VBoxContainer
var _nano_body: Control
var _formula_body: VBoxContainer
var _rune_body: VBoxContainer        # round 38: runes and talismans
var rune_pick := {}                   # gear id -> the rune chosen for it
var rune_log := ""
var _choose_slot := ""
var bench_base := ""
var bench_adds := []
var bench_log := ""
var forge_family := "gloves"
var forge_stock := ""
var forge_gem := ""
var forge_design := {}
var forge_design_craft := "forge"
var nano_pick := ""
var _dirty := false
var bag_view := "grid"             # round 139: slots with pictures; "list" is the old one
var bag_filter := "All"
var bag_sel := ""                  # the slot you have tapped

const LEFT := ["cowl", "choker", "necklace", "cape", "pauldrons", "robe", "chest", "underarmour", "vambraces"]
const RIGHT := ["weapon", "gloves", "gauntlets", "bracelet_l", "bracelet_r", "pants", "greaves", "boots"]
const LOW := ["ring_l1", "ring_l2", "ring_l3", "ring_l4", "ring_r1", "ring_r2", "ring_r3", "ring_r4", "toering_l", "toering_r"]
const QCOL := [Color(0.6, 0.6, 0.6), Color(0.92, 0.92, 0.9), Color(0.5, 0.95, 0.55), Color(0.45, 0.7, 1.0), Color(0.95, 0.65, 1.0)]

static var _icons := {}
var _short_screen := false     # a phone's short screen: smaller slot buttons (round 29)


func setup(h) -> void:
	hud = h
	add_theme_constant_override("separation", 14)
	# a phone's screen is shorter (round 29: TouchUI.fit_screen): fit to it
	var vh: float = h.get_viewport().get_visible_rect().size.y if h.is_inside_tree() else 720.0
	var short := vh < 700.0
	_short_screen = short
	var doll_h := 400.0 if not short else maxf(260.0, vh - 290.0)
	# ---- left: you ----
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(500, 0)          # (round 39: it sits beside the menu's sections now)
	left.add_theme_constant_override("separation", 6)
	add_child(left)
	hud._label(left, I18n.t("What you wear"), 22, Color(0.7, 0.9, 1.0))
	_summary = hud._label(left, "", 13, Color(0.85, 0.88, 0.9))
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_summary.custom_minimum_size = Vector2(490, 0)
	var doll := HBoxContainer.new()
	doll.add_theme_constant_override("separation", 6)
	left.add_child(doll)
	_left_slots = VBoxContainer.new()
	_left_slots.add_theme_constant_override("separation", 3)
	doll.add_child(_left_slots)
	_view_box = SubViewportContainer.new()
	_view_box.stretch = true
	_view_box.custom_minimum_size = Vector2(196, doll_h)
	_view_box.gui_input.connect(_on_view_input)
	doll.add_child(_view_box)
	_view = SubViewport.new()
	_view.own_world_3d = true
	_view.transparent_bg = true
	_view.size = Vector2i(196, int(doll_h))
	_view.msaa_3d = Viewport.MSAA_4X
	_view_box.add_child(_view)
	_build_stage()
	_right_slots = VBoxContainer.new()
	_right_slots.add_theme_constant_override("separation", 3)
	doll.add_child(_right_slots)
	_ring_row = GridContainer.new()
	_ring_row.columns = 10 if not _short_screen and hud.get_viewport().get_visible_rect().size.x >= 1500.0 else 5
	_ring_row.add_theme_constant_override("h_separation", 3)
	_ring_row.add_theme_constant_override("v_separation", 3)
	left.add_child(_ring_row)
	_detail = hud._label(left, "", 13, Color(0.92, 0.9, 0.8))
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.custom_minimum_size = Vector2(490, 60 if not short else 40)
	# ---- right: tabs ----
	tabs = TabContainer.new()
	tabs.custom_minimum_size = Vector2(500, minf(600.0, vh - 120.0))
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(tabs)
	pack_body = _tab("Pack")
	_bench_body = _tab("Bench")
	_forge_body = _tab("Forge")
	var nano_scroll := ScrollContainer.new()
	nano_scroll.name = "Nanoforge"
	tabs.add_child(nano_scroll)
	_nano_body = Control.new()
	_nano_body.custom_minimum_size = Vector2(540, 760)
	_nano_body.draw.connect(_draw_nano_links)
	nano_scroll.add_child(_nano_body)
	_formula_body = _tab("Formulas")
	_rune_body = _tab("Runes")
	tabs.tab_changed.connect(func(_i): refresh())


func _tab(name_: String) -> VBoxContainer:
	var sc := ScrollContainer.new()
	sc.name = name_
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(sc)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 4)
	sc.add_child(v)
	return v


func show_tab(name_: String) -> void:
	for i in tabs.get_tab_count():
		if tabs.get_tab_title(i) == name_:
			tabs.current_tab = i
	refresh()


# ---- the dummy ------------------------------------------------------------------------

func _build_stage() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.62, 0.7)
	e.ambient_light_energy = 0.55
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.glow_enabled = true
	e.glow_intensity = 0.5
	env.environment = e
	_view.add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation = Vector3(-0.6, 0.5, 0)
	key.light_energy = 1.3
	_view.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation = Vector3(-0.2, 2.8, 0)
	rim.light_energy = 0.8
	rim.light_color = Color(0.7, 0.85, 1.0)
	_view.add_child(rim)
	var cam := Camera3D.new()
	cam.fov = 30.0
	cam.position = Vector3(0, 1.0, 4.1)
	_view.add_child(cam)
	cam.look_at(Vector3(0, 0.95, 0))
	_pivot = Node3D.new()
	_view.add_child(_pivot)
	var disc := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.55
	cm.bottom_radius = 0.6
	cm.height = 0.05
	disc.mesh = cm
	var dm := StandardMaterial3D.new()
	dm.albedo_color = Color(0.18, 0.17, 0.16)
	dm.roughness = 0.8
	disc.material_override = dm
	disc.position.y = -0.025
	_pivot.add_child(disc)


func _rebuild_dummy() -> void:
	var pl = get_tree().get_first_node_in_group("player") if is_inside_tree() else null
	var spec: Dictionary = pl.dress_spec() if pl and pl.has_method("dress_spec") else {"hair": "topknot", "gear": Game.worn_looks()}
	var key := JSON.stringify(spec)
	if key == _dummy_key and _dummy != null:
		return
	_dummy_key = key
	if _dummy:
		_dummy.free()
	_dummy = preload("res://scripts/core/Art.gd").person(spec)
	_pivot.add_child(_dummy)
	preload("res://scripts/world/Dress.gd").dress(_dummy, spec)
	preload("res://scripts/actors/Armour.gd").dress_gear(_dummy, spec.get("gear", []))
	for ap in _dummy.find_children("*", "AnimationPlayer", true, false):
		var a: AnimationPlayer = ap
		if a.has_animation("idle"):
			a.get_animation("idle").loop_mode = Animation.LOOP_LINEAR
			a.play("idle")


func _process(delta: float) -> void:
	if not visible or _pivot == null:
		return
	if not _drag:
		_spin += delta * 0.35
	_pivot.rotation.y = _spin
	if _dirty:
		_dirty = false
		_refresh_now()


func _on_view_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		_drag = ev.pressed
	elif ev is InputEventMouseMotion and _drag:
		_spin += ev.relative.x * 0.01


# ---- slots ------------------------------------------------------------------------------

func _short(n: String, k: int = 18) -> String:
	return n if n.length() <= k else n.substr(0, k - 1) + "…"


func _slot_button(parent: Node, slot: String, small: bool = false) -> Button:
	var id := Game.worn(slot)
	var b := Button.new()
	var fam := Game.slot_family(slot)
	b.icon = icon(fam, Game.piece_look(id).get("color", [0.5, 0.5, 0.5]) if id != "" else [0.35, 0.35, 0.38])
	b.expand_icon = false
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", 11)
	b.custom_minimum_size = Vector2(52, 44) if small else Vector2(160, 40)
	if small:
		b.text = ""
	else:
		b.text = _short(Game.item_name(id), 16) if id != "" else Game.slot_name(slot)
	if id != "":
		b.add_theme_color_override("font_color", QCOL[clampi(Game.quality_index(id), 0, 4)])
	else:
		b.add_theme_color_override("font_color", Color(0.55, 0.55, 0.6))
	b.tooltip_text = "%s\n%s" % [Game.slot_name(slot), (Game.item_name(id) + "\n" + Game.item_desc(id)) if id != "" else "(empty)"]
	if slot == _choose_slot:
		b.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	b.pressed.connect(choose_slot.bind(slot))
	parent.add_child(b)
	return b


func choose_slot(slot: String) -> void:
	_choose_slot = slot
	show_tab("Pack")


# ---- icons, drawn here -----------------------------------------------------------------

static func icon(fam: String, col) -> ImageTexture:
	var c := Color(0.5, 0.5, 0.5)
	if col is Array and col.size() >= 3:
		c = Color(float(col[0]), float(col[1]), float(col[2]))
	var key := "%s|%s" % [fam, c.to_html()]
	if _icons.has(key):
		return _icons[key]
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var hi := c.lightened(0.3)
	match fam:
		"ring", "toering":
			_circle(img, 16, 18, 9, 3, c)
			_disc(img, 16, 8, 4, hi)
		"bracelet", "choker":
			_circle(img, 16, 16, 11, 3, c)
		"necklace", "amulet":
			_circle(img, 16, 10, 10, 2, c)
			_disc(img, 16, 22, 5, hi)
		"cowl":
			_disc(img, 16, 15, 11, c)
			_disc(img, 16, 18, 6, Color(0.9, 0.75, 0.6))
		"cape":
			img.fill_rect(Rect2i(8, 4, 16, 3), c)
			for y in range(7, 29):
				var w := 8 + (y - 7) / 2
				img.fill_rect(Rect2i(16 - w, y, w * 2, 1), c)
		"pauldrons":
			_disc(img, 9, 14, 7, c)
			_disc(img, 23, 14, 7, c)
			img.fill_rect(Rect2i(12, 12, 8, 14), c.darkened(0.4))
		"robe":
			for y in range(4, 30):
				var w2 := 5 + (y - 4) / 3
				img.fill_rect(Rect2i(16 - w2, y, w2 * 2, 1), c)
			img.fill_rect(Rect2i(15, 4, 2, 26), c.darkened(0.3))
		"armor":
			img.fill_rect(Rect2i(7, 5, 18, 22), c)
			img.fill_rect(Rect2i(15, 5, 2, 22), hi)
			img.fill_rect(Rect2i(3, 5, 4, 8), c.darkened(0.2))
			img.fill_rect(Rect2i(25, 5, 4, 8), c.darkened(0.2))
		"underarmour":
			img.fill_rect(Rect2i(8, 6, 16, 20), c)
			img.fill_rect(Rect2i(4, 6, 4, 12), c)
			img.fill_rect(Rect2i(24, 6, 4, 12), c)
		"vambraces", "greaves":
			img.fill_rect(Rect2i(9, 4, 6, 24), c)
			img.fill_rect(Rect2i(17, 4, 6, 24), c)
			img.fill_rect(Rect2i(9, 4, 6, 2), hi)
			img.fill_rect(Rect2i(17, 4, 6, 2), hi)
		"gloves", "gauntlets":
			img.fill_rect(Rect2i(9, 12, 14, 14), c)
			for f in 4:
				img.fill_rect(Rect2i(9 + f * 4, 5, 3, 8), c)
			img.fill_rect(Rect2i(5, 15, 4, 6), c)
			if fam == "gauntlets":
				img.fill_rect(Rect2i(7, 24, 18, 5), hi)
		"pants":
			img.fill_rect(Rect2i(8, 4, 16, 6), c)
			img.fill_rect(Rect2i(8, 10, 7, 19), c)
			img.fill_rect(Rect2i(17, 10, 7, 19), c)
		"boots":
			img.fill_rect(Rect2i(8, 4, 8, 20), c)
			img.fill_rect(Rect2i(8, 22, 18, 6), c)
			img.fill_rect(Rect2i(8, 27, 18, 2), c.darkened(0.5))
		"weapon":
			for i in 22:
				img.fill_rect(Rect2i(6 + i, 25 - i, 2, 2), c.lightened(0.2))
			img.fill_rect(Rect2i(5, 20, 8, 3), c.darkened(0.3))
		_:
			_disc(img, 16, 16, 9, c)
	var t := ImageTexture.create_from_image(img)
	_icons[key] = t
	return t


static func _disc(img: Image, cx: int, cy: int, r: int, c: Color) -> void:
	for y in range(cy - r, cy + r + 1):
		for x in range(cx - r, cx + r + 1):
			if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height() and Vector2(x - cx, y - cy).length() <= r:
				img.set_pixel(x, y, c)


static func _circle(img: Image, cx: int, cy: int, r: int, w: int, c: Color) -> void:
	for y in range(cy - r - w, cy + r + w + 1):
		for x in range(cx - r - w, cx + r + w + 1):
			var d := Vector2(x - cx, y - cy).length()
			if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height() and absf(d - r) <= w * 0.5 + 0.3:
				img.set_pixel(x, y, c)


# ---- refresh ---------------------------------------------------------------------------

func refresh() -> void:
	## coalesced: many stat changes in a frame, one rebuild
	_dirty = true
	if not is_inside_tree() or not is_processing():
		_refresh_now()


func _refresh_now() -> void:
	_dirty = false
	var gs := Game.gear_summary()
	_summary.text = I18n.t("Health %d  ·  damage %d  ·  ward %.1f (blows %d%% weaker)  ·  carrying %.1f of %.1f%s%s") % [
		Game.max_hp(), Game.damage(), float(gs["ward"]), int(gs["cut"]), float(gs["weight"]), float(gs["carry"]),
		(I18n.t("  ·  slowed %d%%") % int(gs["slow"])) if int(gs["slow"]) > 0 else "", (I18n.t("  ·  %d nano piece%s") % [int(gs["nano"]), "" if int(gs["nano"]) == 1 else "s"]) if int(gs["nano"]) > 0 else ""]
	for box in [_left_slots, _right_slots, _ring_row]:
		for c in box.get_children():
			c.free()             # (button presses only ever mark the kit dirty, so nothing frees itself mid-signal)
	for s in LEFT:
		_slot_button(_left_slots, s)
	for s in RIGHT:
		_slot_button(_right_slots, s)
	for s in LOW:
		_slot_button(_ring_row, s, true)
	_rebuild_dummy()
	match tabs.get_tab_title(tabs.current_tab):
		"Pack":
			fill_pack()
		"Bench":
			fill_bench()
		"Forge":
			fill_forge()
		"Nanoforge":
			fill_nano()
		"Formulas":
			fill_formulas()
		"Runes":
			fill_runes()


func _clear(box: Node) -> void:
	for c in box.get_children():
		c.free()


func _row(parent: Node, text: String, tip: String = "", col: Color = Color(0.92, 0.92, 0.9)) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	parent.add_child(row)
	var l: Label = hud._label(row, text, 14, col)
	l.custom_minimum_size = Vector2(300, 0)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.tooltip_text = tip
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	return row


func _small(parent: Node, text: String, cb: Callable, disabled: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 13)
	b.disabled = disabled
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _say(t: String) -> void:
	if t != "":
		Game.message.emit(t)
	refresh()


# ---- Pack --------------------------------------------------------------------------------

func fill_pack() -> void:
	_clear(pack_body)
	if _choose_slot != "":
		var fam := Game.slot_family(_choose_slot)
		hud._label(pack_body, I18n.t("%s -- choose what to wear there") % Game.slot_name(_choose_slot), 17, Color(1.0, 0.85, 0.45))
		if Game.worn(_choose_slot) != "":
			var r0 := _row(pack_body, "Wearing: %s" % Game.item_name(Game.worn(_choose_slot)), Game.item_desc(Game.worn(_choose_slot)))
			_small(r0, I18n.t("Take off"), func(): _say(Game.unequip(_choose_slot)))
		var any := false
		for id in _sorted(Game.inventory.keys()):
			if Game.gear_family(id) != fam or id == Game.worn(_choose_slot):
				continue
			any = true
			var r1 := _row(pack_body, "%s  (%d)" % [Game.item_name(id), Game.count(id)], Game.item_desc(id), QCOL[clampi(Game.quality_index(id), 0, 4)])
			_small(r1, I18n.t("Wear here"), func(): _say(Game.wear(id, _choose_slot)))
			_detail_on(r1, id)
		if not any:
			hud._label(pack_body, I18n.t("Nothing else of that kind in your pack. Find some, or make some (Forge)."), 13, Color(0.65, 0.65, 0.7))
		_small(pack_body, "Back to the pack", func():
			_choose_slot = ""
			refresh())
		return
	bag_view = "list" if float(Game.counters.get("bag_view", 0.0)) > 0.0 else "grid"
	hud._label(pack_body, I18n.t("Gold %d  ·  pouch holds %d of each material") % [Game.gold, Game.pouch_cap()], 14, Color(1.0, 0.85, 0.45))
	var groups := {"Gear": [], "Jewellery": [], "Materials": [], "Consumables": [], "Runes": [], "Talismans": [], "Crystals": [], "Relics": [], "Other": []}
	for id in Game.inventory.keys():
		if Game.is_treasure(id) or Game.count(id) <= 0:
			continue
		var t := str(Game.item_def(id).get("type", ""))
		if Game.is_jewel(id):
			groups["Jewellery"].append(id)
		elif Game.gear_family(id) != "":
			groups["Gear"].append(id)
		elif t == "material":
			groups["Materials"].append(id)
		elif t == "consumable":
			groups["Consumables"].append(id)
		elif t == "rune":
			groups["Runes"].append(id)
		elif t == "talisman":
			groups["Talismans"].append(id)
		elif t == "crystal":
			groups["Crystals"].append(id)
		elif t == "relic":
			groups["Relics"].append(id)
		else:
			groups["Other"].append(id)
	_view_toggle()
	if bag_view == "grid":
		_bag_grid(groups)
	else:
		_bag_list(groups)
	var tre: Array = Game.inventory.keys().filter(func(i): return Game.is_treasure(i))
	if tre.size() > 0:
		hud._label(pack_body, I18n.t("Treasures"), 17, Color(0.55, 1.0, 0.75))
		for id in tre:
			var td: Dictionary = Game.items.get(id, {})
			var extra := " (%d sips)" % Game.gourd_sips() if id == "spirit_gourd" else ""
			_row(pack_body, "%s%s%s -- %s" % [Game.item_name(id), (" [" + str(td.get("key")) + "]") if td.get("active", false) else "", extra, td.get("desc", "")], "", Color(0.85, 1.0, 0.9))
	hud._label(pack_body, I18n.t("Techniques"), 17, Color(0.6, 0.95, 1.0))
	if Game.techniques.is_empty():
		_row(pack_body, "None yet. They're out there -- in old stones, in what you do, in who you listen to.", "", Color(0.65, 0.65, 0.7))
	for tid in Game.techniques:
		var t2: Dictionary = Game.technique_defs.get(tid, {})
		_row(pack_body, "%s%s -- %s" % [t2.get("name", tid), (" [" + str(t2.get("key")) + "]") if t2.get("kind") == "active" else "", t2.get("desc", "")], "", Color(0.85, 0.95, 1.0))
	var unknown := Game.technique_defs.size() - Game.techniques.size()
	if unknown > 0:
		hud._label(pack_body, I18n.t("%d more undiscovered.") % unknown, 13, Color(0.6, 0.6, 0.65))
	hud._label(pack_body, I18n.t("Kills: %s") % hud._kills_text(), 13, Color(0.7, 0.7, 0.7))


func _bag_list(groups: Dictionary) -> void:
	## the old list: kept, one tap away (round 139)
	if Game.inventory.is_empty():
		hud._label(pack_body, "(empty)", 15, Color(0.6, 0.6, 0.6))
	for g in ["Gear", "Jewellery", "Materials", "Consumables", "Runes", "Talismans", "Crystals", "Relics", "Other"]:
		if groups[g].is_empty():
			continue
		hud._label(pack_body, g, 17, Color(0.6, 0.9, 1.0))
		for id in _sorted(groups[g]):
			var d: Dictionary = Game.item_def(id)
			var worn_n := Game.equipped_count(id)
			var txt := "%d × %s%s" % [Game.count(id), Game.item_name(id), (I18n.t("  [worn]") if worn_n > 0 else "")]
			var row := _row(pack_body, txt, Game.item_desc(id), QCOL[clampi(Game.quality_index(id), 0, 4)])
			_detail_on(row, id)
			_item_actions(row, id)


func _item_actions(row: Control, id: String) -> void:
	## the buttons an item gets, in the list and under the slot grid alike (round 139)
	var d: Dictionary = Game.item_def(id)
	var worn_n := Game.equipped_count(id)
	match str(d.get("type", "")):
		"consumable":
			_small(row, "Use", func(): Game.use_item(id))
		"rune":
			_small(row, "Inscribe...", func(): show_tab("Runes"))
		"relic":
			# round 44: a piece of the old age -- keep it, or let one of two peoples look after it
			var F = Game.sys("factions")
			for fid in ["heirs", "sects"]:
				var gb := _small(row, I18n.t("Give to the %s") % (str(F.fdef(fid).get("short", fid)) if F else fid), func(): _say(Game.sys("ruins").give(id, fid)))
				gb.tooltip_text = I18n.t("%s will think better of you; %s, worse.") % [F.name_of(fid), F.name_of(str(F.fdef(fid).get("rival", "")))] if F else ""
		"crystal":
			# round 43: a condensed legacy -- absorb it once you're strong enough, or sell it
			var why: String = Game.crystal_ready(id)
			var ab := _small(row, I18n.t("Absorb") if why == "" else I18n.t("Absorb (at %s)") % Game.realm_name_of(int(Game.crystal_info(id).get("need", 0))), func(): _say(Game.absorb_crystal(id)))
			ab.disabled = why != ""
			ab.tooltip_text = why if why != "" else I18n.t("Take the legacy into yourself now.")
		"talisman":
			if str(Game.talisman_use(id).get("kind", "")) != "seal":
				var rb := _small(row, "Ready [4]" if Game.talisman_ready != Game.base_id(id) else "Readied", func():
					Game.talisman_ready = Game.base_id(id)
					refresh())
				rb.disabled = Game.talisman_ready == Game.base_id(id)
		"material":
			if float(Game.nanite_data().get("gain", {}).get("absorb", {}).get(id, 0.0)) > 0.0:
				var pl = get_tree().get_first_node_in_group("player")
				_small(row, I18n.t("Absorb"), func(): _say(Game.absorb(id, pl != null and pl.meditating)))
			if not Game.knows_material(id):
				_small(row, I18n.t("Study"), func(): _say(Game.study_material(id)))
	if Game.gear_family(id) != "":
		if worn_n < Game.count(id):
			_small(row, I18n.t("Wear"), func(): _say(Game.equip(id)))
		if worn_n > 0:
			_small(row, "Take off", func():
				for s in Game.gear_slots():
					if Game.worn(str(s[0])) == id:
						_say(Game.unequip(str(s[0])))
						return)
	if not Game.is_treasure(id) and str(d.get("type", "")) in ["material", "consumable"] or Game.gear_family(id) != "":
		_small(row, "Bench", func(): bench_put(id))


func _detail_on(row: Control, id: String) -> void:
	row.mouse_entered.connect(func(): show_detail(id))
	for c in row.get_children():
		if c is Control:
			(c as Control).mouse_entered.connect(func(): show_detail(id))


func show_detail(id: String) -> void:
	var d: Dictionary = Game.item_def(id)
	var lines := [Game.item_name(id)]
	if Game.gear_family(id) != "":
		var bits := []
		if d.has("hp") and int(d.get("hp", 0)) > 0:
			bits.append(I18n.t("+%d health") % int(d["hp"]))
		if Game.piece_ward(id) > 0.0:
			bits.append(I18n.t("%.1f ward") % Game.piece_ward(id))
		bits.append(I18n.t("%.1f weight") % Game.piece_weight(id))
		var mk := str(d.get("make", ""))
		if mk != "":
			bits.append({"crafted": "crafted", "nano": "nano", "both": I18n.t("crafted + nano")}.get(mk, mk))
		lines.append(", ".join(bits))
		if d.has("effect"):
			lines.append(Game.effect_text(Game.jewel_effect(id)))
		for a in d.get("affixes", []):
			lines.append("  · " + str(a))
		if Game.inscription_text(id) != "":
			lines.append(Game.inscription_text(id))
	elif str(d.get("type", "")) == "material":
		lines.append(Game.traits_text(id))
	lines.append(str(d.get("desc", "")).get_slice("\n", 0))
	_detail.text = "\n".join(lines)


func _sorted(ids: Array) -> Array:
	var a := ids.duplicate()
	a.sort_custom(func(x, y): return Game.item_name(x) < Game.item_name(y))
	return a


# ---- Bench -------------------------------------------------------------------------------

func bench_put(id: String) -> void:
	if bench_base == "":
		bench_base = id
	elif bench_adds.size() < 3:
		bench_adds.append(id)
	show_tab("Bench")


func bench_set(base: String, adds: Array) -> void:
	bench_base = base
	bench_adds = adds.duplicate()


func bench_go() -> Dictionary:
	var r := Game.combine_attempt(bench_base, bench_adds)
	bench_log = str(r.get("text", ""))
	if bool(r.get("ok", false)):
		var made := str(r.get("item", ""))
		if made != "" and Game.count(made) > 0 and Game.gear_family(made) != "":
			bench_base = made
		elif Game.count(bench_base) <= 0:
			bench_base = ""
		bench_adds = bench_adds.filter(func(a): return Game.count(str(a)) > 0)
	refresh()
	return r


func fill_bench() -> void:
	if Game.sys("tester") != null:
		Game.sys("tester").pull_all()           # round 156: the vault's materials are on the bench
	_clear(_bench_body)
	var where: String = {"": "No proper bench here: you can still try, but your odds are worse. (A workbench at home, a smith's forge or an artisan's workshop.)",
		"home": "At your own bench.", "forge": "At the smith's forge (metal works better here).", "workshop": "In the workshop."}.get(Game.at_bench, "")
	if Game.at_bench == "" and Game.road_bench():
		where = I18n.t("On the road, at your folding table.") + (I18n.t(" (With your field forge.)") if Game.field_forge() else "")
	hud._label(_bench_body, where, 13, Color(0.75, 0.8, 0.85)).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hud._label(_bench_body, I18n.t("Put a thing on the bench and work up to three things into it. Gear takes on what you work into it; materials become something new; a known formula makes its product."), 13, Color(0.7, 0.7, 0.75)).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var opts := _sorted(Game.inventory.keys().filter(func(i): return Game.count(i) > 0 and not Game.is_treasure(i) and str(Game.item_def(i).get("type", "")) != "currency"))
	_picker(_bench_body, "On the bench", bench_base, opts, func(v): bench_base = v)
	for i in 3:
		var cur: String = bench_adds[i] if i < bench_adds.size() else ""
		_picker(_bench_body, "Work in #%d" % (i + 1), cur, opts, func(v):
			if v == "":
				if i < bench_adds.size():
					bench_adds.remove_at(i)
			elif i < bench_adds.size():
				bench_adds[i] = v
			else:
				bench_adds.append(v))
	if bench_base != "" and bench_adds.size() > 0:
		var pv := Game.combine_preview(bench_base, bench_adds)
		var lines := []
		if not bool(pv["ok"]):
			lines.append(str(pv["why"]))
		else:
			var kind_t: String = {"formula": "a formula's product", "infuse": "an infused piece", "merge": "two pieces folded into one", "brew": "a stronger draught", "alloy": "something new"}.get(str(pv["kind"]), "")
			lines.append(I18n.t("Makes: %s%s") % [kind_t, (" (%s)" % Game.item_name(str(Game.formula_def(str(pv["formula"])).get("makes", "")))) if str(pv["formula"]) != "" else ""])
			lines.append(I18n.t("Odds: %d%%   ·   chance of a surprise: %d%%   ·   %s %d") % [int(round(float(pv["chance"]) * 100)), int(round(float(pv["luck"]) * 100)), Game.skill_name(str(pv["skill"])), Game.skill_level(str(pv["skill"]))])
			var tl := []
			for tr in pv["traits"]:
				tl.append("%s %d" % [Game.trait_name(tr), int(pv["traits"][tr])])
			lines.append(I18n.t("What you understand of the mix: %s") % (", ".join(tl) if tl.size() > 0 else I18n.t("nothing yet")))
			if (pv["synergies"] as Array).size() > 0:
				lines.append(I18n.t("Synergies: %s") % ", ".join(pv["synergies"]))
			if (pv["notes"] as Array).size() > 0:
				lines.append("(" + "; ".join(pv["notes"]) + ")")
		var l: Label = hud._label(_bench_body, "\n".join(lines), 14, Color(0.95, 0.9, 0.75))
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var b := _small(_bench_body, "Work it", func(): bench_go(), not bool(pv["ok"]))
		b.custom_minimum_size = Vector2(160, 36)
	if bench_log != "":
		var ll: Label = hud._label(_bench_body, bench_log, 14, Color(0.7, 1.0, 0.8))
		ll.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_small(_bench_body, "Clear the bench", func():
		bench_base = ""
		bench_adds = []
		bench_log = ""
		refresh())


func _picker(parent: Node, label: String, current: String, ids: Array, on_pick: Callable) -> OptionButton:
	var h := HBoxContainer.new()
	parent.add_child(h)
	var l: Label = hud._label(h, label, 13, Color(0.8, 0.85, 0.9))
	l.custom_minimum_size = Vector2(110, 0)
	var ob := OptionButton.new()
	ob.custom_minimum_size = Vector2(380, 30)
	ob.add_item("(nothing)")
	ob.set_item_metadata(0, "")
	var sel := 0
	for i in ids.size():
		var id := str(ids[i])
		ob.add_item("%s (%d)%s" % [Game.item_name(id), Game.count(id), "" if not (str(Game.item_def(id).get("type", "")) == "material") or not Game.knows_material(id) else "  · " + Game.traits_text(id)])
		ob.set_item_metadata(i + 1, id)
		if id == current:
			sel = i + 1
	ob.selected = sel
	ob.item_selected.connect(func(ix):
		on_pick.call(str(ob.get_item_metadata(ix)))
		refresh())
	h.add_child(ob)
	return ob


# ---- Forge -------------------------------------------------------------------------------

func forge_play() -> void:
	## round 141c: the craft's mini-game first (if it's on), then the piece
	var cp = Game.sys("craftplay")
	if cp == null:
		forge_go()
		return
	cp.begin(Game.forge_skill(forge_family, forge_stock), {"difficulty": int(Game.forge_tier(forge_family, forge_stock) / 2)}, func(): forge_go())


func forge_go() -> Dictionary:
	var r := Game.forge_piece(forge_family, forge_stock, forge_gem, -1.0, -1.0, forge_design)
	if bool(r.get("success", false)):
		forge_design = {}
	bench_log = str(r.get("text", ""))
	if Game.count(forge_stock) < int(Game.gear_data()["families"].get(forge_family, {}).get("needs", 1)):
		forge_stock = ""
	if forge_gem != "" and Game.count(forge_gem) <= 0:
		forge_gem = ""
	refresh()
	return r


func fill_forge() -> void:
	_clear(_forge_body)
	hud._label(_forge_body, I18n.t("Make a piece of any kind from a material you carry. Jewellery takes a metal and, if you like, anything at all as its stone -- the stone decides its gift."), 13, Color(0.7, 0.7, 0.75)).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var h := HBoxContainer.new()
	_forge_body.add_child(h)
	hud._label(h, I18n.t("Make"), 13, Color(0.8, 0.85, 0.9)).custom_minimum_size = Vector2(110, 0)
	var fam_ob := OptionButton.new()
	fam_ob.custom_minimum_size = Vector2(380, 30)
	var fams: Array = Game.forge_families()
	for i in fams.size():
		fam_ob.add_item(str(Game.gear_data()["families"][fams[i]].get("name", fams[i])))
		fam_ob.set_item_metadata(i, fams[i])
		if fams[i] == forge_family:
			fam_ob.selected = i
	fam_ob.item_selected.connect(func(ix):
		forge_family = str(fam_ob.get_item_metadata(ix))
		forge_stock = ""
		refresh())
	h.add_child(fam_ob)
	var stocks: Array = Game.forge_stocks(forge_family)
	var sids := stocks.map(func(r): return str(r[0]))
	if forge_stock != "" and not (forge_stock in sids):
		forge_stock = ""
	if forge_stock == "" and sids.size() > 0:
		forge_stock = sids[0]
	if sids.is_empty():
		hud._label(_forge_body, I18n.t("You carry nothing that can be made into that%s.") % (I18n.t(" yet -- some kinds need the Nanoforge") if forge_family != "" else ""), 13, Color(0.9, 0.7, 0.6))
	else:
		_picker(_forge_body, "From", forge_stock, sids, func(v): forge_stock = v)
		var gems := _sorted(Game.inventory.keys().filter(func(i): return Game.count(i) > 0 and str(Game.item_def(i).get("type", "")) == "material"))
		_picker(_forge_body, "Set with", forge_gem, gems, func(v): forge_gem = v)
		if forge_stock != "":
			_design_pickers()
			var why := Game.forge_check(forge_family, forge_stock, forge_gem)
			if why == "" and not Game.Design.is_plain(forge_design):
				why = Game.Design.check(forge_design_craft, forge_design, Game.skill_level(Game.forge_skill(forge_family, forge_stock)))
			var t := Game.forge_tier(forge_family, forge_stock)
			var lines := ["Needs %d %s and %d gold · %s %d against tier %d" % [int(Game.gear_data()["families"][forge_family].get("needs", 1)), Game.item_name(forge_stock), t * 3,
				Game.skill_name(Game.forge_skill(forge_family, forge_stock)), Game.skill_level(Game.forge_skill(forge_family, forge_stock)), t],
				"Odds: %d%%" % int(round(Game.forge_chance(forge_family, forge_stock, forge_gem) * 100))]
			if why != "":
				lines.append(why)
			hud._label(_forge_body, "\n".join(lines), 14, Color(0.95, 0.9, 0.75)).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_small(_forge_body, "Make it", func(): forge_play(), why != "").custom_minimum_size = Vector2(160, 36)
	if bench_log != "":
		hud._label(_forge_body, bench_log, 14, Color(0.7, 1.0, 0.8)).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func _design_pickers() -> void:
	## motif / trim / dye -- what it looks like, and what that does to the numbers
	hud._label(_forge_body, I18n.t("Design -- changes how it looks and what it gives (every gain has a cost)."), 13, Color(0.8, 0.85, 0.9))
	var D := Game.Design
	var dc := "jewel" if str(Game.gear_data()["families"].get(forge_family, {}).get("kind", "")) == "jewel" else "forge"
	if forge_design_craft != dc:
		forge_design_craft = dc
		forge_design = {}
	for gr0 in D.groups(dc):
		var gr := [gr0[2], gr0[0], gr0[1]]
		var h := HBoxContainer.new()
		_forge_body.add_child(h)
		hud._label(h, str(gr[0]), 13, Color(0.8, 0.85, 0.9)).custom_minimum_size = Vector2(110, 0)
		var ob := OptionButton.new()
		ob.custom_minimum_size = Vector2(380, 30)
		var cur := str(forge_design.get(gr[2], ""))
		var opts: Array = D.options(dc, gr[1])
		for i in opts.size():
			var o: Dictionary = opts[i][1]
			var note := ""
			if int(o.get("min_skill", 0)) > 0:
				note += I18n.t(" (skill %d)") % int(o["min_skill"])
			for it in o.get("cost", {}):
				note += " [%d %s]" % [int(o["cost"][it]), Game.item_name(str(it))]
			ob.add_item(str(o.get("name", opts[i][0])) + note)
			ob.set_item_metadata(i, str(opts[i][0]))
			ob.set_item_tooltip(i, str(o.get("desc", "")))
			if str(opts[i][0]) == cur:
				ob.selected = i
		var key := str(gr[2])
		ob.item_selected.connect(func(ix):
			forge_design[key] = str(ob.get_item_metadata(ix))
			refresh())
		h.add_child(ob)
		var dsc := ""
		for r in opts:
			if str(r[0]) == cur:
				dsc = str((r[1] as Dictionary).get("desc", ""))
		if dsc != "":
			hud._label(_forge_body, "    " + dsc, 12, Color(0.65, 0.7, 0.75))


# ---- Nanoforge -----------------------------------------------------------------------------

const NODE_W := 150.0
const NODE_H := 46.0


func _node_pos(n: Dictionary) -> Vector2:
	var p: Array = n.get("pos", [0, 0])
	return Vector2(270.0 + float(p[0]) * 165.0 - NODE_W / 2.0, 20.0 + float(p[1]) * 82.0)


func fill_nano() -> void:
	_clear(_nano_body)
	var head: Label = hud._label(_nano_body, I18n.t("Your swarm: %s · %d nanite shards") % [Game.tier_name(), Game.count("nanite_shard")], 14, Color(0.6, 1.0, 0.9))
	head.position = Vector2(4, 0)
	for n in Game.nanotech_data().get("nodes", []):
		var nid := str(n["id"])
		var st := Game.nano_state(nid)
		if st == "hidden":
			continue
		var b := Button.new()
		b.text = str(n.get("name", nid))
		b.add_theme_font_size_override("font_size", 12)
		b.position = _node_pos(n) + Vector2(0, 18)
		b.size = Vector2(NODE_W, NODE_H)
		b.clip_text = true
		var col: Color = {"open": Color(0.35, 0.95, 0.8), "ready": Color(1.0, 0.85, 0.4), "locked": Color(0.55, 0.55, 0.6)}.get(st, Color.WHITE)
		b.add_theme_color_override("font_color", col)
		b.tooltip_text = "%s\n%s" % [n.get("desc", ""), "" if st == "open" else Game.nano_why(nid)]
		b.pressed.connect(func():
			nano_pick = nid
			refresh())
		_nano_body.add_child(b)
	var hidden: int = Game.nanotech_data().get("nodes", []).filter(func(n): return Game.nano_state(str(n["id"])) == "hidden").size()
	var info := ""
	if nano_pick != "":
		var n2 := Game.nano_node_def(nano_pick)
		var cost := []
		for k in n2.get("cost", {}):
			cost.append("%d %s" % [int(n2["cost"][k]), Game.item_name(str(k))])
		info = I18n.t("%s\n%s\nCosts: %s · needs the swarm at %s%s") % [n2.get("name", ""), n2.get("desc", ""), ", ".join(cost), Game.tier_name(int(n2.get("tier", 0))),
			"" if Game.nano_state(nano_pick) != "locked" else I18n.t("\nNot yet: ") + Game.nano_why(nano_pick)]
	if hidden > 0:
		info += I18n.t("\n\n%d more the swarm hasn't shown you. Experiment at the bench.") % hidden
	var il: Label = hud._label(_nano_body, info, 13, Color(0.9, 0.95, 1.0))
	il.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	il.position = Vector2(4, 600)
	il.size = Vector2(530, 100)
	if nano_pick != "" and Game.nano_state(nano_pick) == "ready":
		var ub := _small(_nano_body, I18n.t("Unlock %s") % Game.nano_node_def(nano_pick).get("name", ""), func(): _say(Game.nano_unlock(nano_pick)))
		ub.position = Vector2(4, 560)
	_nano_body.queue_redraw()


func _draw_nano_links() -> void:
	for n in Game.nanotech_data().get("nodes", []):
		if Game.nano_state(str(n["id"])) == "hidden":
			continue
		for p in n.get("needs", []):
			var pn := Game.nano_node_def(str(p))
			if pn.is_empty() or Game.nano_state(str(p)) == "hidden":
				continue
			var a := _node_pos(pn) + Vector2(NODE_W / 2.0, 18.0 + NODE_H)
			var b := _node_pos(n) + Vector2(NODE_W / 2.0, 18.0)
			var lit := Game.nano_has(str(p))
			_nano_body.draw_line(a, b, Color(0.35, 0.95, 0.8, 0.8) if lit else Color(0.5, 0.5, 0.55, 0.5), 2.0, true)


# ---- Formulas ------------------------------------------------------------------------------

func fill_formulas() -> void:
	_clear(_formula_body)
	var any := false
	for f in Game.craft_data().get("formulas", []):
		var fid := str(f["id"])
		if not Game.knows_formula(fid):
			continue
		any = true
		var needs: Dictionary = f.get("needs", {})
		var row := _row(_formula_body, "%s ×%d  ←  %s" % [Game.item_name(str(f["makes"])), int(f.get("n", 1)), Game.recipe_text({"needs": needs})], str(f.get("hint", "")), Color(0.9, 0.95, 0.8))
		var ids := needs.keys()
		var ok := Game.formula_usable(fid)
		_small(row, "Set up", func():
			bench_set(str(ids[0]), ids.slice(1))
			show_tab("Bench"), not ok)
	if not any:
		hud._label(_formula_body, I18n.t("You know no formulas yet. Smiths, merchants and alchemists sell them -- or find them yourself, by putting the right things together at the bench."), 13, Color(0.7, 0.7, 0.75)).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var n_unknown: int = Game.craft_data().get("formulas", []).filter(func(f): return not Game.knows_formula(str(f["id"]))).size()
	if n_unknown > 0:
		hud._label(_formula_body, I18n.t("\n%d formulas you haven't found.") % n_unknown, 13, Color(0.6, 0.6, 0.65))


# ---- Runes (round 38) ----------------------------------------------------------------------

func _worn_pieces() -> Array:
	var out := []
	for sl in Game.gear_slots():
		var id := Game.worn(str(sl[0]))
		if id != "" and not (id in out) and Game.count(id) > 0:
			out.append(id)
	return out


func _runes_carried() -> Array:
	return _sorted(Game.inventory.keys().filter(func(i): return Game.is_rune(i) and Game.count(i) > 0))


func fill_runes() -> void:
	_clear(_rune_body)
	var at_table: bool = Game.at_bench in ["home", "rune"] or Game.rune_table_anywhere()
	if rune_log != "":
		hud._label(_rune_body, rune_log, 14, Color(1.0, 0.9, 0.6)).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# -- rune craft
	hud._label(_rune_body, I18n.t("Rune craft"), 18, Color(0.95, 0.8, 0.5))
	if not Game.skill_known("runecraft"):
		var l: Label = hud._label(_rune_body, I18n.t("You don't know the old marks. ") + Game.craft_teacher_hint("runecraft"), 13, Color(0.7, 0.7, 0.75))
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	else:
		hud._label(_rune_body, I18n.t("Runecraft %d (%s). A weapon holds %d rune%s; anything else you wear, %d. Runes on armour and jewellery pool -- a second of the same gift counts for less.") % [
			Game.skill_level("runecraft"), Game.skill_title("runecraft"), _sockets_for("weapon"),
			"" if _sockets_for("weapon") == 1 else "s", _sockets_for("wear")], 13, Color(0.82, 0.85, 0.9)).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var carried := _runes_carried()
		for id in _worn_pieces():
			var have: Array = Game.runes_on(id)
			var cap := Game.rune_sockets(id)
			var marks := []
			for i in cap:
				marks.append("[%s]" % (Game.rune_mark(str(have[i])) if i < have.size() else "  "))
			var w: Dictionary = Game.rune_word_on(id)
			var row := _row(_rune_body, "%s  %s%s" % [Game.item_name(id), " ".join(marks), ("  \"%s\"" % str(w.get("name", ""))) if not w.is_empty() else ""],
				Game.inscription_text(id), Color(0.92, 0.9, 0.85))
			_detail_on(row, id)
			if have.size() > 0:
				_small(row, "Scour (%dg)" % Game.scour_cost(id), func():
					rune_log = Game.scour(id)
					refresh())
			if have.size() < cap and carried.size() > 0:
				var cur := str(rune_pick.get(id, ""))
				if not (cur in carried):
					cur = str(carried[0])
					rune_pick[id] = cur
				var ob := OptionButton.new()
				ob.custom_minimum_size = Vector2(170, 28)
				for j in carried.size():
					ob.add_item("%s (%d)" % [Game.rune_mark(str(carried[j])), Game.count(str(carried[j]))])
					ob.set_item_metadata(j, str(carried[j]))
					if str(carried[j]) == cur:
						ob.selected = j
				ob.item_selected.connect(func(ix): rune_pick[id] = str(ob.get_item_metadata(ix)))
				row.add_child(ob)
				_small(row, "Inscribe (%d%%)" % int(round(Game.inscribe_chance(id, cur) * 100)), func():
					rune_log = str(Game.inscribe(id, str(rune_pick.get(id, cur))).get("text", ""))
					refresh())
		if _worn_pieces().is_empty():
			hud._label(_rune_body, I18n.t("Wear something first: runes go into what you wear."), 13, Color(0.65, 0.65, 0.7))
		if carried.size() > 0:
			hud._label(_rune_body, I18n.t("Runes you carry: ") + ", ".join(carried.map(func(r): return "%s ×%d (%s)" % [Game.rune_mark(str(r)), Game.count(str(r)),
				I18n.t("weapon: ") + Game.effect_text(Game.rune_info(str(r)).get("weapon", {})) + I18n.t("; worn: ") + Game.effect_text(Game.rune_info(str(r)).get("wear", {}))])), 12, Color(0.8, 0.82, 0.86)).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hud._label(_rune_body, I18n.t("Rune words (%d of %d spoken)") % [Game.runewords_found(), Game.runes_data().get("words", []).size()], 15, Color(0.95, 0.8, 0.5))
		for w2 in Game.runes_data().get("words", []):
			if Game.rune_word_known(str(w2.get("id", ""))):
				_row(_rune_body, "%s: %s on %s -- %s" % [str(w2.get("name", "")), " · ".join((w2.get("runes", []) as Array).map(func(r): return Game.rune_mark(str(r)))),
					{"weapon": "a weapon", "wear": "something worn", "any": "anything"}.get(str(w2.get("on", "any")), "anything"), Game.effect_text(w2.get("effect", {}))], "", Color(1.0, 0.88, 0.55))
			else:
				_row(_rune_body, I18n.t("???  (%d runes) -- \"%s\"") % [(w2.get("runes", []) as Array).size(), str(w2.get("hint", ""))], "", Color(0.6, 0.6, 0.66))
	# -- talismans
	hud._label(_rune_body, I18n.t("Talismans"), 18, Color(1.0, 0.6, 0.45))
	if not Game.skill_known("talismans"):
		hud._label(_rune_body, I18n.t("You can burn a talisman, but not draw one. ") + Game.craft_teacher_hint("talismans"), 13, Color(0.7, 0.7, 0.75)).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var tl := Game.talismans_carried()
	if tl.is_empty():
		hud._label(_rune_body, I18n.t("None in your pouch. Key 4 burns the readied one; 5 switches."), 13, Color(0.65, 0.65, 0.7))
	for tid in tl:
		var r2 := _row(_rune_body, "%s ×%d -- %s" % [Game.item_name(str(tid)), Game._talisman_count(str(tid)), str(Game.item_def(str(tid)).get("desc", ""))], "", Color(1.0, 0.85, 0.75))
		var rb2 := _small(r2, "Readied" if Game.talisman_ready == str(tid) else "Ready [4]", func():
			Game.talisman_ready = str(tid)
			refresh())
		rb2.disabled = Game.talisman_ready == str(tid)
	# -- at a table: carve and draw
	hud._label(_rune_body, I18n.t("At the table"), 18, Color(0.7, 0.9, 1.0))
	if not at_table:
		hud._label(_rune_body, I18n.t("Carving runes and drawing talismans wants a table: your own bench at home, or your teacher's. (Setting a rune you can do anywhere.)"), 13, Color(0.65, 0.65, 0.7)).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		return
	for r in Game.recipes:
		var sk := str(r.get("skill", ""))
		if not (sk in ["runecraft", "talismans"]) or not Game.skill_known(sk):
			continue
		var ready := Game.can_craft(r)
		var row3 := _row(_rune_body, "%s  [%s %d vs %d]  %s" % [Game.item_name(str(r["makes"])), Game.skill_name(sk), Game.skill_level(sk), int(r.get("difficulty", 0)), Game.recipe_text(r)],
			str(Game.item_def(str(r["makes"])).get("desc", "")), Color(0.92, 0.92, 0.9) if ready else Color(0.6, 0.6, 0.62))
		var cb := _small(row3, ("Carve" if sk == "runecraft" else "Draw") + (" (%d%%)" % int(round(Game.craft_chance(r) * 100)) if ready else ""), func():
			var cpr = Game.sys("craftplay")
			var go_r := func():
				rune_log = str(Game.craft_attempt(r).get("text", ""))
				refresh()
			if cpr != null:
				cpr.begin(sk, r, go_r)
			else:
				go_r.call())
		cb.disabled = not ready


func _sockets_for(part: String) -> int:
	var lvl := Game.skill_level("runecraft")
	var n := 0
	for row in Game.runes_data().get("sockets", {}).get(part, [[0, 1]]):
		if lvl >= int(row[0]):
			n = int(row[1])
	return n


# ---- round 139: the bag as slots --------------------------------------------------------------------------------------
## Robert, 2026-10-17: "a bag with slots instead of a list ... give each item an icon". Every item is a square slot with its
## picture, a count in the corner and a border that shows its quality; tap one and its actions appear under the grid.
## The old list is one button away.

const BAG_FILTERS := ["All", "Gear", "Jewellery", "Materials", "Consumables", "Other"]


func _view_toggle() -> void:
	var r := HFlowContainer.new()
	r.add_theme_constant_override("h_separation", 6)
	pack_body.add_child(r)
	for v in ["grid", "list"]:
		var b := _small(r, "Slots" if v == "grid" else "List", _set_view.bind(v), bag_view == v)
		b.custom_minimum_size = Vector2(76, 28)


func _set_view(v: String) -> void:
	bag_view = v
	Game.counters["bag_view"] = 1.0 if v == "list" else 0.0
	refresh()


func _set_filter(f: String) -> void:
	bag_filter = f
	bag_sel = ""
	refresh()


func _quick(id: String) -> void:
	## the obvious thing for an item: drink or eat it, wear it, take it off, absorb it
	if Game.count(id) <= 0:
		return
	var d: Dictionary = Game.item_def(id)
	var t := str(d.get("type", ""))
	if t == "consumable":
		Game.use_item(id)
	elif Game.gear_family(id) != "":
		if Game.equipped_count(id) < Game.count(id):
			_say(Game.equip(id))
		else:
			for sl in Game.gear_slots():
				if Game.worn(str(sl[0])) == id:
					_say(Game.unequip(str(sl[0])))
					break
	elif t == "crystal" and Game.crystal_ready(id) == "":
		_say(Game.absorb_crystal(id))
	else:
		bag_sel = id
		show_detail(id)
	refresh()


func _pick_slot(id: String) -> void:
	bag_sel = id
	show_detail(id)
	refresh()


func _slot_style(col: Color, selected: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.09, 0.12, 0.95)
	sb.set_corner_radius_all(8)
	sb.set_border_width_all(3 if selected else 2)
	sb.border_color = Color(1.0, 0.85, 0.4, 1.0) if selected else (col if col.v < 0.9 or col.s > 0.1 else Color(0.5, 0.55, 0.64, 1.0))
	return sb


func _bag_grid(groups: Dictionary) -> void:
	var cols := 5 if _short_screen else 8
	var fr := HFlowContainer.new()
	fr.add_theme_constant_override("h_separation", 4)
	fr.add_theme_constant_override("v_separation", 4)
	pack_body.add_child(fr)
	for f in BAG_FILTERS:
		var fb := _small(fr, f, _set_filter.bind(f), bag_filter == f)
		fb.custom_minimum_size = Vector2(0 if _short_screen else 80, 26)
	var ids := []
	for g in groups:
		var want: bool = bag_filter == "All" or g == bag_filter or (bag_filter == "Other" and g in ["Runes", "Talismans", "Crystals", "Relics", "Other"])
		if want:
			ids.append_array(groups[g])
	ids = _bag_order(ids, groups)
	var total := maxi(cols * 4, int(ceil(float(ids.size()) / cols)) * cols + (cols if ids.size() > 0 else 0))     # (cols: a hint for how many empty ones to show)
	var grid := HFlowContainer.new()                  # wraps to whatever width the pane has
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	pack_body.add_child(grid)
	var sz := Vector2(56, 56) if _short_screen else Vector2(66, 66)
	for i in total:
		if i < ids.size():
			grid.add_child(_slot_for(str(ids[i]), sz))
		else:
			var e := Panel.new()
			e.custom_minimum_size = sz
			e.add_theme_stylebox_override("panel", _slot_style(Color(0.2, 0.22, 0.28, 0.6), false))
			e.mouse_filter = Control.MOUSE_FILTER_IGNORE
			grid.add_child(e)
	if ids.is_empty():
		hud._label(pack_body, I18n.t("Nothing here."), 14, Color(0.6, 0.6, 0.65))
	# ---- the tapped one
	if bag_sel != "" and Game.count(bag_sel) > 0:
		var id := bag_sel
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", _slot_style(QCOL[clampi(Game.quality_index(id), 0, 4)], false))
		pack_body.add_child(card)
		pack_body.move_child(card, grid.get_index())          # the actions sit ABOVE the grid, so they are never below the fold
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 6)
		card.add_child(v)
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 10)
		v.add_child(head)
		var tr_ := TextureRect.new()
		tr_.texture = Icons.item(Game.base_id(id))
		tr_.custom_minimum_size = Vector2(64, 64)
		tr_.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr_.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		head.add_child(tr_)
		var tb := VBoxContainer.new()
		head.add_child(tb)
		hud._label(tb, "%d × %s%s" % [Game.count(id), Game.item_name(id), (I18n.t("  [worn]") if Game.equipped_count(id) > 0 else "")], 16, QCOL[clampi(Game.quality_index(id), 0, 4)])
		var dl: Label = hud._label(tb, str(Game.item_desc(id)).get_slice("\n", 0), 12, Color(0.78, 0.82, 0.88))
		dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		dl.custom_minimum_size = Vector2(260, 0)
		var ar := HFlowContainer.new()
		ar.add_theme_constant_override("h_separation", 6)
		v.add_child(ar)
		_item_actions(ar, id)
		show_detail(id)


func _bag_order(ids: Array, groups: Dictionary) -> Array:
	## worn first, then by kind, then name -- the same order every time, so a slot stays where your hand expects it
	var rank := {}
	var i := 0
	for g in groups:
		for id in groups[g]:
			rank[id] = i
		i += 1
	var a := ids.duplicate()
	a.sort_custom(func(x, y):
		var wx := 0 if Game.equipped_count(x) > 0 else 1
		var wy := 0 if Game.equipped_count(y) > 0 else 1
		if wx != wy:
			return wx < wy
		if rank.get(x, 0) != rank.get(y, 0):
			return rank.get(x, 0) < rank.get(y, 0)
		return Game.item_name(x) < Game.item_name(y))
	return a


func _slot_for(id: String, sz: Vector2) -> Control:
	var col: Color = QCOL[clampi(Game.quality_index(id), 0, 4)]
	var b := Button.new()
	b.custom_minimum_size = sz
	b.focus_mode = Control.FOCUS_NONE
	b.clip_contents = true
	b.icon = Icons.item(Game.base_id(id))
	b.expand_icon = true
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	var sel: bool = bag_sel == id
	for st in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(st, _slot_style(col, sel or st == "hover"))
	b.tooltip_text = "%s%s" % [Game.item_name(id), (I18n.t("  [worn]") if Game.equipped_count(id) > 0 else "")]
	var n := Game.count(id)
	if n > 1:
		var l := Label.new()
		l.text = str(n)
		l.add_theme_font_size_override("font_size", 12)
		l.add_theme_color_override("font_color", Color(1, 1, 1))
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
		l.add_theme_constant_override("outline_size", 4)
		l.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
		l.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		l.grow_vertical = Control.GROW_DIRECTION_BEGIN
		l.offset_right = -4
		l.offset_bottom = -2
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(l)
	if Game.equipped_count(id) > 0:
		var w := Label.new()
		w.text = "worn"
		w.add_theme_font_size_override("font_size", 10)
		w.add_theme_color_override("font_color", Color(0.6, 1.0, 0.7))
		w.add_theme_color_override("font_outline_color", Color(0, 0, 0))
		w.add_theme_constant_override("outline_size", 3)
		w.position = Vector2(4, 1)
		w.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(w)
	b.pressed.connect(_pick_slot.bind(id))
	b.mouse_entered.connect(show_detail.bind(id))
	b.gui_input.connect(func(ev: InputEvent):                # double-click or right-click does the obvious thing
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed:
			var mb := ev as InputEventMouseButton
			if mb.button_index == MOUSE_BUTTON_RIGHT or (mb.button_index == MOUSE_BUTTON_LEFT and mb.double_click):
				_quick(id))
	return b
