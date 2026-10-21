extends CanvasLayer
## Everything drawn on top of the world: HP and qi bars, cultivation
## stage, gold, the level name, the "E: ..." prompt, a message log,
## dialogs (merchant, smith, elder), the inventory (I) and pause (Esc).

var _hp_bar: ProgressBar
var _qi_bar: ProgressBar
var _hp_text: Label
var _qi_text: Label
var _stage: Label
var _gold: Label
var _clock: Label
var _clock_t := 0.0
var _level_name: Label
var _prompt: Label
var _screen_fx: ColorRect            # round 52
var _hurt := 0.0
var _pulse := 0.0
var _prompt_pill: PanelContainer      # round 50: the prompt as a pill with a key-cap
var _prompt_key: PanelContainer
var _prompt_keytext: Label
var _prompt_full := ""
var _boss_box: VBoxContainer          # round 50: a boss's name and health across the top
var _boss_name: Label
var _boss_bar: ProgressBar
var _boss_of: Node
var _boss_t := 0.0
var _log: VBoxContainer
var _dialog: PanelContainer
var _dialog_title: Label
var _dialog_body: Label
var _dialog_buttons: VBoxContainer
var _dialog_body_scroll: ScrollContainer
var _dialog_btn_scroll: ScrollContainer
var _inventory: PanelContainer
var _journal: PanelContainer
var _chat: PanelContainer
var _play: Control                # round 141c: the craft mini-game screen
var _chat_log: RichTextLabel      # round 22: names in colour, notes in grey, follows the conversation
var _chat_think: Label
var _chat_chips: HFlowContainer
var _think_t := 0.0
var _trade: PanelContainer        # round 22: the trade screen
var _trade_npc = null
var _trade_title: Label
var _trade_line: Label
var _trade_gold: Label
var _trade_note: Label
var _trade_buy: VBoxContainer
var _trade_sell: VBoxContainer
var _chat_in: LineEdit
var _chat_send: Button
var _chat_title: Label
var _chat_npc = null
var _chat_scroll: ScrollContainer
var _jr_body: VBoxContainer
var _inv_body: VBoxContainer
var _kit                     # Kit.gd: the pack screen (round 27)
var _pause: PanelContainer
var _help: Label
var _goals: Label            # what's waiting / what's next (Game.next_goals), under the level name
var _goals_t := 0.0
var _lattice: PanelContainer      # K: the Meridian Lattice (LatticeView.gd)
var _lat_view: Control
var _lat_info: Label
var _lat_arts: Label
var _lat_rows: VBoxContainer      # round 20: each art -- wire it, give it an element; arts still to glimpse
var _lat_sel := ""                 # the point last clicked (for a nanite bridge)
var _heat_bar: ProgressBar
var _heat_text: Label
var _heat_fill: StyleBoxFlat
var _slots: Label
var _first: Label
var _photo = null
var _swarm_bar: ProgressBar       # round 21: the nanite swarm's own road, beside qi
var _swarm_text: Label
var _gfx_btn: Button
var _win_btn: Button
var _cam_btn: Button
var _touch_btn: Button
var _vr_btn: Button
const XRMode := preload("res://scripts/core/XRMode.gd")
var _fog_btn: Button
var _steam_btn: Button
var _music_btn: Button
var _sfx_btn: Button
const Gfx := preload("res://scripts/core/Gfx.gd")
const UI := preload("res://scripts/core/UiStyle.gd")      # round 49: the look and the motion
const FX := preload("res://scripts/fx/FX.gd")              # round 61: a rare find's beam
var _theme: Theme
var _moment: Node            # Moment.gd: free-text "what do you do?" (T)


func _ready() -> void:
	add_to_group("hud")
	layer = 10
	_theme = _ui_theme()
	# round 49: windows put straight on this layer (the title, the level card,
	# character creation...) wear the same theme as everything under root
	child_entered_tree.connect(func(n):
		if n is Control and (n as Control).theme == null:
			(n as Control).theme = _theme)
	UI.watch(get_tree())                     # every button: the hover glow, the press
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = _theme
	add_child(root)
	# round 52: the screen's edges (a soft vignette; red when you're hit; a pulse near death)
	_screen_fx = ColorRect.new()
	_screen_fx.name = "ScreenFX"
	_screen_fx.set_anchors_preset(Control.PRESET_FULL_RECT)
	_screen_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sfm := ShaderMaterial.new()
	sfm.shader = load("res://assets/shaders/screen_fx.gdshader")
	_screen_fx.material = sfm
	root.add_child(_screen_fx)

	# ---- top-left: bars ----
	var panel := PanelContainer.new()
	panel.position = Vector2(16, 14)
	panel.add_theme_stylebox_override("panel", UI.box(UI.col("glass", Color(0.035, 0.04, 0.06, 0.66)), Color(0, 0, 0, 0), "card"))
	root.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 5)
	panel.add_child(v)
	# round 63: the HomeAI apps' look -- a slate card, a clear heading, pill bars, chips
	_stage = _label(v, "", 17, UI.col("text", Color(0.93, 0.93, 0.96)))
	if UI.font("bold"):
		_stage.add_theme_font_override("font", UI.font("bold"))
	_hp_bar = _bar(v, Color(0.9, 0.3, 0.33))
	_hp_bar.custom_minimum_size = Vector2(320, 18)
	UI.trail(_hp_bar)                        # round 49: a pale trail shows what a hit took
	_hp_text = _overlay(_hp_bar)
	_qi_bar = _bar(v, Color(0.3, 0.72, 1.0))
	_qi_bar.custom_minimum_size = Vector2(320, 15)
	UI.trail(_qi_bar)
	_qi_text = _overlay(_qi_bar)
	_qi_text.add_theme_font_size_override("font_size", 11)
	_swarm_bar = _bar(v, Color(0.3, 0.9, 0.75))
	_swarm_bar.custom_minimum_size = Vector2(320, 14)
	_swarm_text = _overlay(_swarm_bar)
	_swarm_text.add_theme_font_size_override("font_size", 11)
	_heat_bar = _bar(v, Color(0.95, 0.55, 0.15))
	_heat_bar.custom_minimum_size = Vector2(320, 12)
	_heat_fill = _heat_bar.get_theme_stylebox("fill") as StyleBoxFlat
	_heat_text = _overlay(_heat_bar)
	_heat_text.add_theme_font_size_override("font_size", 10)
	_slots = _label(v, "", 13, UI.col("text_dim", Color(0.55, 0.57, 0.65)))
	_first = _label(v, "", 13, Color(1.0, 0.9, 0.6))          # round 163: the guided first hour
	_first.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_first.custom_minimum_size = Vector2(320, 0)
	_first.visible = false
	var chip := PanelContainer.new()
	var cs := UI._flat(UI.col("chip", Color(0.13, 0.145, 0.18, 0.9)), 999, 0.0)
	cs.content_margin_left = 12
	cs.content_margin_right = 12
	cs.content_margin_top = 3
	cs.content_margin_bottom = 3
	chip.add_theme_stylebox_override("panel", cs)
	chip.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	v.add_child(chip)
	_gold = _label(chip, "", 14, Color(1.0, 0.85, 0.45))
	_clock = _label(v, "", 12, UI.col("text_dim", Color(0.55, 0.57, 0.65)))          # round 44: the day, the hour, the weather

	# ---- top-right: where you are, and what's next (round 63: one card) ----
	var obj := PanelContainer.new()
	obj.name = "ObjectivesCard"
	var ocs: StyleBoxFlat = UI.box(UI.col("glass", Color(0.09, 0.1, 0.13, 0.82)), Color(0, 0, 0, 0), "card")
	ocs.border_width_left = 3
	ocs.border_color = UI.col("gold", Color(0.95, 0.78, 0.45))
	obj.add_theme_stylebox_override("panel", ocs)
	obj.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 16)
	obj.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	obj.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(obj)
	var ov := VBoxContainer.new()
	ov.add_theme_constant_override("separation", 3)
	ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
	obj.add_child(ov)
	_level_name = Label.new()
	_level_name.add_theme_font_size_override("font_size", 18)
	if UI.font("bold"):
		_level_name.add_theme_font_override("font", UI.font("bold"))
	_level_name.add_theme_color_override("font_color", UI.col("text", Color(0.93, 0.93, 0.96)))
	_level_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ov.add_child(_level_name)
	_goals = Label.new()
	_goals.add_theme_font_size_override("font_size", 14)
	_goals.add_theme_color_override("font_color", UI.col("text_dim", Color(0.55, 0.57, 0.65)).lightened(0.25))
	_goals.custom_minimum_size = Vector2(300, 0)
	_goals.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_goals.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ov.add_child(_goals)
	_pursuit_chip = Label.new()                      # round 63: what your character is pursuing while you're idle
	_pursuit_chip.add_theme_font_size_override("font_size", 13)
	_pursuit_chip.add_theme_color_override("font_color", Color(0.6, 0.9, 1.0))
	_pursuit_chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_pursuit_chip.visible = false
	ov.add_child(_pursuit_chip)

	# ---- top-centre: a boss's name and health (round 50) ----
	_boss_box = VBoxContainer.new()
	_boss_box.anchor_left = 0.5
	_boss_box.anchor_right = 0.5
	_boss_box.offset_left = -200
	_boss_box.offset_right = 200
	_boss_box.offset_top = 16
	_boss_box.add_theme_constant_override("separation", 4)
	_boss_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boss_box.visible = false
	root.add_child(_boss_box)
	_boss_name = _label(_boss_box, "", 22, Color(1.0, 0.75, 0.95))
	_boss_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_name.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_boss_name.add_theme_constant_override("outline_size", 6)
	_boss_bar = _bar(_boss_box, Color(0.85, 0.3, 0.75))
	_boss_bar.custom_minimum_size = Vector2(400, 12)
	UI.trail(_boss_bar)

	# ---- bottom-centre: prompt ----
	# round 50: a pill -- the key in a gold key-cap, then what it does
	_prompt_pill = PanelContainer.new()
	var pps: StyleBoxFlat = UI.box(UI.col("glass", Color(0.035, 0.04, 0.06, 0.66)), Color(0, 0, 0, 0), "card")
	pps.set_corner_radius_all(22)
	pps.content_margin_left = 8
	pps.content_margin_right = 18
	pps.content_margin_top = 6
	pps.content_margin_bottom = 6
	_prompt_pill.add_theme_stylebox_override("panel", pps)
	_prompt_pill.anchor_left = 0.5
	_prompt_pill.anchor_right = 0.5
	_prompt_pill.anchor_top = 1.0
	_prompt_pill.anchor_bottom = 1.0
	_prompt_pill.offset_top = -172
	_prompt_pill.offset_bottom = -132
	_prompt_pill.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_prompt_pill.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_prompt_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt_pill.visible = false
	root.add_child(_prompt_pill)
	var ph := HBoxContainer.new()
	ph.add_theme_constant_override("separation", 10)
	ph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt_pill.add_child(ph)
	_prompt_key = PanelContainer.new()
	var kcs: StyleBoxFlat = UI.box(Color(0.1, 0.09, 0.07, 0.95), UI.col("gold", Color(0.95, 0.78, 0.45)), "button")
	kcs.set_border_width_all(1)
	kcs.border_width_bottom = 3                  # a key-cap: thicker underneath
	kcs.border_color = UI.col("gold", Color(0.95, 0.78, 0.45))
	kcs.content_margin_left = 9
	kcs.content_margin_right = 9
	kcs.content_margin_top = 1
	kcs.content_margin_bottom = 1
	kcs.shadow_size = 0
	_prompt_key.add_theme_stylebox_override("panel", kcs)
	_prompt_key.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ph.add_child(_prompt_key)
	_prompt_keytext = _label(_prompt_key, "", 17, UI.col("gold", Color(0.95, 0.78, 0.45)))
	_prompt_keytext.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var kf := UI.font("heavy")
	if kf:
		_prompt_keytext.add_theme_font_override("font", kf)
	_prompt = _label(ph, "", 19, UI.col("text", Color(0.93, 0.91, 0.86)))
	_prompt.remove_theme_font_override("font")          # (19px would make it a title: it's an action)
	_prompt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	# ---- bottom-left: message log ----
	_log = VBoxContainer.new()
	_log.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_log.position = Vector2(16, -306)             # (round 49: clear of the keys at the bottom)
	_log.size = Vector2(600, 220)
	_log.add_theme_constant_override("separation", 4)
	_log.alignment = BoxContainer.ALIGNMENT_END
	_log.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_log)

	# ---- bottom-right: controls help ----
	_help = Label.new()
	_help.text = I18n.t("WASD move  ·  mouse look  ·  click/J attack  ·  E interact  ·  Shift sprint  ·  Space jump\nTab menu  ·  M meditate  ·  I pack  ·  O party  ·  1 salve  ·  2 qi pill  ·  3 gourd  ·  4 talisman (5 switch)  ·  N journal  ·  P character\nF / V arts  ·  X switch  ·  6 path art (7 switch)  ·  8 / 9 support arts (0 switch)  ·  right mouse guard (tap: parry)  ·  hold click: heavy  ·  Ctrl roll  ·  Z lock on  ·  G flying sword  ·  T do something unusual  ·  K meridians  ·  C camera  ·  Esc menu  ·  H hide this")
	_help.add_theme_font_size_override("font_size", 12)
	_help.add_theme_color_override("font_color", UI.col("text_dim", Color(0.55, 0.57, 0.65)).lightened(0.2))
	var hsb: StyleBoxFlat = UI.box(UI.col("glass", Color(0.09, 0.1, 0.13, 0.82)), Color(0, 0, 0, 0), "card")      # round 50: on a quiet glass card (round 63: the apps' slate)
	hsb.shadow_size = 0
	hsb.set_content_margin_all(10)
	_help.add_theme_stylebox_override("normal", hsb)
	_help.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_help.grow_horizontal = Control.GROW_DIRECTION_BEGIN   # long lines grow left, never off-screen
	_help.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_help.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 14)
	root.add_child(_help)
	# round 62: the keys card is a lot to look at -- after a few minutes it
	# folds away (H brings it back; it stays as you leave it)
	_help_short = Label.new()
	_help_short.text = I18n.t("H: keys")
	_help_short.add_theme_font_size_override("font_size", 12)
	_help_short.add_theme_color_override("font_color", Color(0.85, 0.86, 0.9, 0.55))
	_help_short.add_theme_color_override("font_outline_color", Color.BLACK)
	_help_short.add_theme_constant_override("outline_size", 4)
	_help_short.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 14)
	_help_short.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_help_short.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_help_short.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_help_short.visible = false
	root.add_child(_help_short)
	if Game.playtime > 180.0 or Game.has_flag("ui:help_folded"):
		_fold_help()
	else:
		get_tree().create_timer(maxf(20.0, 180.0 - Game.playtime)).timeout.connect(func():
			if _help.visible and not Game.has_flag("ui:help_shown"):
				_fold_help())

	# ---- dialog ----
	_dialog = PanelContainer.new()
	_dialog.add_theme_stylebox_override("panel", _box(Color(0.07, 0.06, 0.1, 0.94), Color(0.8, 0.65, 0.35)))
	_dialog.set_anchors_preset(Control.PRESET_CENTER)
	_dialog.position = Vector2(-330, -250)
	_dialog.custom_minimum_size = Vector2(660, 0)
	_dialog.visible = false
	root.add_child(_dialog)
	var dv := VBoxContainer.new()
	dv.add_theme_constant_override("separation", 10)
	_dialog.add_child(dv)
	_dialog_title = _label(dv, "", 24, Color(1.0, 0.85, 0.5))
	# long texts and long lists scroll instead of running off the screen
	_dialog_body_scroll = ScrollContainer.new()
	_dialog_body_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	dv.add_child(_dialog_body_scroll)
	_dialog_body = _label(_dialog_body_scroll, "", 16, Color(0.92, 0.92, 0.9))
	_dialog_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dialog_body.custom_minimum_size = Vector2(620, 0)
	_dialog_btn_scroll = ScrollContainer.new()
	_dialog_btn_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	dv.add_child(_dialog_btn_scroll)
	_dialog_buttons = VBoxContainer.new()
	_dialog_buttons.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_dialog_btn_scroll.add_child(_dialog_buttons)

	# ---- inventory ----
	# round 27: the pack is a whole screen -- you on a dummy, every slot, and
	# the bench, forge, nanoforge and formulas in tabs (Kit.gd)
	_inventory = PanelContainer.new()
	_inventory.add_theme_stylebox_override("panel", _box(Color(0.05, 0.06, 0.09, 0.96), Color(0.4, 0.7, 0.9)))
	_inventory.set_anchors_preset(Control.PRESET_FULL_RECT)
	_inventory.offset_left = 24
	_inventory.offset_top = 16
	_inventory.offset_right = -24
	_inventory.offset_bottom = -16
	_inventory.visible = false
	root.add_child(_inventory)
	_kit = preload("res://scripts/core/Kit.gd").new()
	if get_viewport().get_visible_rect().size.y < 700.0:
		# a phone's short screen (round 29): the kit scrolls instead of spilling off the bottom
		var ksc := ScrollContainer.new()
		ksc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		_inventory.add_child(ksc)
		_kit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ksc.add_child(_kit)
	else:
		_inventory.add_child(_kit)
	_kit.setup(self)
	_inv_body = _kit.pack_body

	# ---- journal (N): skills, elements, items you know, places you've been ----
	_journal = PanelContainer.new()
	_journal.add_theme_stylebox_override("panel", _box(Color(0.08, 0.07, 0.05, 0.95), Color(0.85, 0.7, 0.4)))
	_journal.set_anchors_preset(Control.PRESET_CENTER)
	_journal.position = Vector2(-330, -300)
	_journal.custom_minimum_size = Vector2(660, 600)
	_journal.visible = false
	root.add_child(_journal)
	var jscroll := ScrollContainer.new()
	jscroll.custom_minimum_size = Vector2(640, 580)
	jscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_journal.add_child(jscroll)
	_jr_body = VBoxContainer.new()
	_jr_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	jscroll.add_child(_jr_body)

	# ---- the Meridian Lattice (K) ----
	_lattice = PanelContainer.new()
	_lattice.add_theme_stylebox_override("panel", _box(Color(0.03, 0.04, 0.07, 0.96), Color(0.4, 0.7, 0.95)))
	_lattice.set_anchors_preset(Control.PRESET_CENTER)
	_lattice.position = Vector2(-520, -320)
	_lattice.custom_minimum_size = Vector2(1040, 640)
	_lattice.visible = false
	root.add_child(_lattice)
	var lh := HBoxContainer.new()
	lh.add_theme_constant_override("separation", 16)
	_lattice.add_child(lh)
	_lat_view = preload("res://scripts/ui/LatticeView.gd").new()
	lh.add_child(_lat_view)
	_lat_view.picked.connect(func(pid):
		_lat_sel = pid
		if Game.can_focus(pid) == "":
			Game.message.emit(Game.set_focus(pid))
		_fill_lattice())
	_lat_view.hovered.connect(func(pid): _fill_lattice(pid))
	var lv := VBoxContainer.new()
	lv.custom_minimum_size = Vector2(440, 0)
	lv.add_theme_constant_override("separation", 10)
	lh.add_child(lv)
	_label(lv, I18n.t("The Meridian Lattice"), 24, Color(0.6, 0.85, 1.0))
	_lat_info = _label(lv, "", 15, Color(0.92, 0.92, 0.9))
	_lat_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lat_info.custom_minimum_size = Vector2(430, 0)
	_lat_arts = _label(lv, "", 14, Color(1.0, 0.88, 0.6))
	_lat_arts.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lat_arts.custom_minimum_size = Vector2(430, 0)
	var lscroll := ScrollContainer.new()
	lscroll.custom_minimum_size = Vector2(440, 250)
	lscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	lv.add_child(lscroll)
	_lat_rows = VBoxContainer.new()
	_lat_rows.add_theme_constant_override("separation", 4)
	_lat_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lscroll.add_child(_lat_rows)
	var lhelp := _label(lv, I18n.t("Click a point to focus it, then meditate (M). Arts used in a fight leave practice that settles when you rest. New arts are GLIMPSED by doing what they grow from. Every art heats your nanites -- past the cap is a backlash. K closes."), 12, Color(0.65, 0.7, 0.75))
	lhelp.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lhelp.custom_minimum_size = Vector2(430, 0)

	# ---- talking freely with someone (round 22: smoother) ----
	_chat = PanelContainer.new()
	_chat.add_theme_stylebox_override("panel", _box(Color(0.06, 0.055, 0.08, 0.96), Color(0.75, 0.6, 0.9)))
	_chat.set_anchors_preset(Control.PRESET_CENTER)
	_chat.position = Vector2(-390, -290)
	_chat.custom_minimum_size = Vector2(780, 0)
	_chat.visible = false
	root.add_child(_chat)
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 8)
	_chat.add_child(cv)
	_chat_title = _label(cv, "", 22, Color(0.9, 0.8, 1.0))
	_chat_log = RichTextLabel.new()
	_chat_log.bbcode_enabled = true
	_chat_log.scroll_following = true
	_chat_log.selection_enabled = true
	_chat_log.custom_minimum_size = Vector2(756, 330)
	_chat_log.add_theme_font_size_override("normal_font_size", 16)
	_chat_log.add_theme_font_size_override("italics_font_size", 15)
	_chat_log.add_theme_color_override("default_color", Color(0.92, 0.92, 0.9))
	var logbg := StyleBoxFlat.new()
	logbg.bg_color = Color(0.03, 0.03, 0.05, 0.6)
	logbg.set_corner_radius_all(6)
	logbg.set_content_margin_all(10)
	_chat_log.add_theme_stylebox_override("normal", logbg)
	cv.add_child(_chat_log)
	_chat_think = _label(cv, "", 13, Color(0.65, 0.65, 0.75))
	_chat_chips = HFlowContainer.new()
	_chat_chips.add_theme_constant_override("h_separation", 6)
	_chat_chips.add_theme_constant_override("v_separation", 6)
	cv.add_child(_chat_chips)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	cv.add_child(row)
	_chat_in = LineEdit.new()
	_chat_in.custom_minimum_size = Vector2(560, 36)
	_chat_in.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chat_in.placeholder_text = "Say something..."
	_chat_in.text_submitted.connect(func(_t): _chat_say())
	row.add_child(_chat_in)
	_chat_send = _button(row, "Say", _chat_say)
	_chat_send.custom_minimum_size = Vector2(80, 36)
	_button(row, "Goodbye", close_chat).custom_minimum_size = Vector2(100, 36)

	# ---- the trade screen (round 22) ----
	_trade = PanelContainer.new()
	_trade.add_theme_stylebox_override("panel", _box(Color(0.07, 0.06, 0.05, 0.96), Color(0.85, 0.7, 0.4)))
	_trade.set_anchors_preset(Control.PRESET_CENTER)
	_trade.position = Vector2(-470, -300)
	_trade.custom_minimum_size = Vector2(940, 600)
	_trade.visible = false
	root.add_child(_trade)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 8)
	_trade.add_child(tv)
	var th := HBoxContainer.new()
	tv.add_child(th)
	_trade_title = _label(th, "", 24, Color(1.0, 0.85, 0.5))
	_trade_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_trade_gold = _label(th, "", 20, Color(1.0, 0.85, 0.4))
	_trade_line = _label(tv, "", 14, Color(0.85, 0.82, 0.75))
	_trade_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_trade_line.custom_minimum_size = Vector2(900, 0)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 16)
	tv.add_child(cols)
	for side in ["buy", "sell"]:
		var col := VBoxContainer.new()
		col.custom_minimum_size = Vector2(450, 0)
		cols.add_child(col)
		_label(col, I18n.t("For sale") if side == "buy" else I18n.t("Yours to sell"), 18, Color(0.95, 0.8, 0.5) if side == "buy" else Color(0.7, 0.9, 0.75))
		var sc := ScrollContainer.new()
		sc.custom_minimum_size = Vector2(450, 380)
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		col.add_child(sc)
		var list := VBoxContainer.new()
		list.add_theme_constant_override("separation", 4)
		list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sc.add_child(list)
		if side == "buy":
			_trade_buy = list
		else:
			_trade_sell = list
	_trade_note = _label(tv, "", 15, Color(0.75, 1.0, 0.8))
	var tb := HBoxContainer.new()
	tb.add_theme_constant_override("separation", 8)
	tv.add_child(tb)
	_button(tb, "Sell all materials", func():
		var got := 0
		for id in Game.sellables():
			if str(Game.item_def(id).get("type", "")) == "material":
				got += Game.sell(id, Game.count(id))
		fill_trade("Sold every material for %d gold." % got if got > 0 else "You have no materials to sell."))
	_button(tb, "Talk", func():
		var n = _trade_npc
		close_trade()
		if n:
			open_chat(n))
	_button(tb, "Goodbye", close_trade)

	# ---- pause ----
	_pause = PanelContainer.new()
	_pause.add_theme_stylebox_override("panel", _box(Color(0.05, 0.05, 0.08, 0.95), Color(0.7, 0.7, 0.8)))
	_pause.set_anchors_preset(Control.PRESET_CENTER)
	_pause.position = Vector2(-160, -130)
	_pause.custom_minimum_size = Vector2(320, 0)
	_pause.visible = false
	root.add_child(_pause)
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 8)
	pv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# round 58: the menu outgrew a 720-high screen (and a phone's) -- it scrolls now
	_pause_scroll = ScrollContainer.new()
	_pause_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_pause_scroll.process_mode = Node.PROCESS_MODE_ALWAYS
	_pause.add_child(_pause_scroll)
	_pause_scroll.add_child(pv)
	_pause_list = pv
	_label(pv, I18n.t("Paused"), 26, Color(0.9, 0.9, 1.0))
	_section(pv, "Play")
	_button(pv, "Resume", _toggle_pause)
	_button(pv, "Save", func(): Game.save_game(); Game.message.emit("Saved."); _toggle_pause())
	_button(pv, "Your pursuit (time away)", func(): _toggle_pause(); open_away_plan())
	_button(pv, "Quick travel", func(): _toggle_pause(); open_travel(false))          # round 63
	if not Game.sys("tester").clean():
		_button(pv, "Teleport to any floor", func():          # round 168: on the first page, not buried in the test kit
			_toggle_pause()
			var tk = Game.sys("tester")
			if tk != null and tk.unlocked():
				tk.teleport_menu(self)
			else:
				Game.message.emit(I18n.t("Teleport needs the test kit's open locks.")))
	_button(pv, "Map", func(): _toggle_pause(); _hub.show_page("Map"))          # round 75
	# graphics, window, camera (Gfx.gd -- kept in user://settings.json)
	_section(pv, "Settings")
	_gfx_btn = _button(pv, "", func():
		var n := Gfx.next_preset(get_tree())
		_refresh_settings_buttons()
		Game.message.emit(I18n.t("Graphics: %s%s") % [Gfx.LABEL[n], "" if n == "low" else " -- new models show from the next place you enter"]))
	_win_btn = _button(pv, "", func():
		Gfx.set_window("windowed" if str(Gfx.load_settings()["window"]) == "fullscreen" else "fullscreen", get_tree())
		_refresh_settings_buttons())
	_cam_btn = _button(pv, "", func():
		var pl = get_tree().get_first_node_in_group("player")
		if pl and pl.has_method("cycle_camera"):
			pl.cycle_camera()
		else:
			Gfx.next_camera()
		_refresh_settings_buttons())
	_steam_btn = _button(pv, "", func():
		Gfx.next_steam(get_tree())
		_refresh_settings_buttons())
	# round 59: every sound setting in one place
	_button(pv, "Graphics fine-tune...", func(): _toggle_pause(); open_gfx_tune(true))          # round 123
	_button(pv, "Cloud save...", func(): _toggle_pause(); open_cloud(true))          # round 124
	_sound_btn = _button(pv, "Sound...", func(): _toggle_pause(); open_sound(true))
	_touch_btn = _button(pv, "", func():
		Gfx.next_touch(get_tree())
		_refresh_settings_buttons())
	_vr_btn = _button(pv, "", func():
		XRMode.next_mode(get_tree())
		Game.message.emit("VR changes next time you start the game.")
		_refresh_settings_buttons())
	_fog_btn = _button(pv, "", func():
		Gfx.next_fog(get_tree())
		_refresh_settings_buttons())
	_refresh_settings_buttons()
	# round 58: the full game (phones), what's planned (everywhere)
	_section(pv, "The game")
	_unlock_btn = _button(pv, "Unlock the full game", func(): open_unlock("", ""))
	_restore_btn = _button(pv, "Restore purchases", func(): _toggle_pause(); _restore_purchases())
	_bless_btn = _button(pv, "The deep's blessing", func(): offer_gift("blessing"))
	_privacy_btn = _button(pv, "Privacy choices (ads)", func(): _toggle_pause(); Game.ads.show_privacy())
	_button(pv, "Report a problem", func(): _toggle_pause(); open_report())          # round 64: straight to Dev
	_button(pv, "Streak, dailies & luck", func(): _toggle_pause(); open_dialog("Streak, dailies & luck", Game.Hook.describe(), [["Close", close_dialog]]))          # round 126
	_button(pv, "Controls (change any key)", func(): _toggle_pause(); open_controls())          # round 158
	_button(pv, "Photo mode (F9)", func(): open_photo())          # round 165
	if not Game.sys("tester").clean():
		_button(pv, "Test kit (vault, god mode, portable table)", func(): _toggle_pause(); Game.sys("tester").menu(self))          # round 156
	_button(pv, "Comforts & Style", func(): _toggle_pause(); Game.Comfort.menu(self))          # round 127
	_button(pv, "Accessibility...", func(): _toggle_pause(); open_hub("System"))          # round 142a
	_button(pv, "Expansions to come", func(): _toggle_pause(); open_expansions())
	_refresh_store_buttons()
	_button(pv, I18n.t("Characters (%d slots)") % Game.SLOTS, func(): _toggle_pause(); show_title(); _title_slots())      # round 51: three games, each its own character
	_button(pv, "Quit", func(): _toggle_pause(); open_away_plan(true))

	Game.stats_changed.connect(refresh)
	if Game.sys("travel"):
		Game.sys("travel").channel_changed.connect(_on_travel_channel)          # round 63
	# round 30: big moments (your blood waking, a trial cleared) wait for a quiet
	# moment and then open as a window; a third bloodline asks what to do; a
	# world event writes itself across the screen
	Game.big_moment.connect(func(t, b): _moments_q.append([t, b]))
	Game.ending_requested.connect(show_ending)       # round 33
	Game.level_up.connect(func(info):                                                 # round 36
		if str(info.get("kind", "")) == "realm":
			_moments_q.append(["__level_up", info])     # a realm crossed: the full window
		else:
			show_level_card(info))                       # a step: a card that doesn't stop play
	Game.blood_choice.connect(func(id): _moments_q.append(["__blood_choice", id]))
	Game.banner.connect(show_banner)
	Game.message.connect(log_message)
	Game.unlock_wanted.connect(open_unlock)
	Game.loot_reveal.connect(show_loot_reveal)                 # round 61
	if Game.sys("floorrun"):
		Game.sys("floorrun").floor_cleared.connect(func(card): _floor_card_soon(card))
	if Game.audio:
		Game.audio.now_playing.connect(show_now_playing)          # round 59          # round 58: the way below the free floors
	if Game.store:
		Game.store.changed.connect(_refresh_store_buttons)
		Game.store.prices_changed.connect(_refresh_store_buttons)
	_hub_setup()                                       # round 39: one menu, sections down the side
	refresh()
	preload("res://scripts/core/Access.gd").apply.call_deferred(get_tree())          # round 142a: text size, colour filter, captions


var _hub: PanelContainer


func _hub_setup() -> void:
	## the pack, the character sheet, the journal and the lattice become pages
	## of one menu (Hub.gd); every way in that opened them still does
	_ensure_char()
	_hub = preload("res://scripts/ui/Hub.gd").new()
	_inventory.get_parent().add_child(_hub)
	_hub.setup(self)
	_hub.adopt("You", _char)
	_hub.adopt("Pack", _inventory)
	_hub.adopt("Journal", _journal)
	_hub.adopt("Meridians", _lattice)
	_dialog.get_parent().move_child(_dialog, -1)       # a window asked for from the menu shows over it
	if _chat:
		_chat.get_parent().move_child(_chat, -1)
	if _trade:
		_trade.get_parent().move_child(_trade, -1)
	_pause.get_parent().move_child(_pause, -1)
	for w in [_dialog, _chat, _trade, _hub, _pause]:
		if w is Control:
			UI.animate_opens(w)                   # round 49: windows rise and fade in


func open_hub(sec: String = "") -> void:
	if sec == "":
		_hub.toggle()
	else:
		_hub.show_page(sec)


func _process(delta: float) -> void:
	_tick_slots(delta)
	_refresh_heat()
	_clock_t -= delta
	if _clock_t <= 0.0:
		_clock_t = 10.0
		update_clock()
	_pursuit_t -= delta
	if _pursuit_t <= 0.0 and _pursuit_chip:
		_pursuit_t = 0.5
		var PU = Game.sys("pursuit")
		var tx: String = PU.chip_text() if PU else ""
		_pursuit_chip.text = tx
		_pursuit_chip.visible = tx != ""
	if not _moments_q.is_empty() and not is_blocking():
		var m: Array = _moments_q.pop_front()
		if str(m[0]) == "__blood_choice":
			open_blood_choice(str(m[1]))
		elif str(m[0]) == "__level_up":
			open_level_up(m[1])
		elif str(m[0]) == "__floor_card":
			open_floor_card(m[1])                         # round 61: a floor's verdict
		elif str(m[0]) == "__gift":
			offer_gift(str(m[1]))                        # round 58: an ad you may choose to watch
		else:
			open_dialog(str(m[0]), str(m[1]), [["Onward", close_dialog]])
	if _chat_think and _chat_think.text != "":
		_think_t += delta
		_chat_think.text = _chat_think.text.rstrip(".") + ".".repeat(1 + int(_think_t * 3.0) % 3)
	_goals_t -= delta
	if _goals_t <= 0.0:
		_goals_t = 1.0
		refresh_goals()
	_screen_tick(delta)
	_boss_t -= delta
	if _boss_t <= 0.0:
		_boss_t = 0.2
		refresh_boss()


func _refresh_settings_buttons() -> void:
	var st := Gfx.load_settings()
	_gfx_btn.text = I18n.t("Graphics: ") + str(Gfx.LABEL.get(str(st["preset"]), st["preset"]))
	_win_btn.text = I18n.t("Window: ") + ("fullscreen" if str(st["window"]) == "fullscreen" else "windowed")
	_cam_btn.text = I18n.t("Camera: %s  (C)") % str(Gfx.CAMERA_LABEL.get(str(st["camera"]), st["camera"]))
	if _sound_btn:
		_sound_btn.text = I18n.t("Sound: music %d, ambience %d, effects %d") % [int(st.get("music", 6)), int(st.get("ambience", 7)), int(st.get("sfx", 8))]
	if _steam_btn:
		_steam_btn.visible = preload("res://scripts/core/SteamLink.gd").available() and not OS.has_feature("steam")
		_steam_btn.text = I18n.t("Steam: %s") % (Game.steam.status if Game.steam and Game.steam.on else str(st.get("steam", "off")))
	if _vr_btn:
		_vr_btn.text = "VR: " + str(XRMode.LABEL.get(XRMode.mode(), "off")) + ("" if XRMode.available() else I18n.t("  (no VR support in this build)"))
	if _touch_btn:
		_touch_btn.text = I18n.t("Touch controls: ") + str(Gfx.TOUCH_LABEL.get(str(st.get("touch", "auto")), "auto"))
	if _fog_btn:
		_fog_btn.text = I18n.t("Fog of war: ") + ("on" if str(st.get("fog", "on")) == "on" else I18n.t("off (from the next floor)"))


# ---- round 58: the full game, the free tier's ads, expansions ------------------------------------
# On a phone the village, the valley and floors 1-5 are free with no ads.
# Below floor 5 (model "ads", data/store.json) the whole game stays free to the
# end, with an occasional ad at a break and gifts for ads you choose; the
# first time down, a window says so. The full game -- one purchase -- removes
# the ads. (model "locked": below floor 5 needs the purchase.) Restore is in
# every window (Apple requires it). Expansions: their own window.

var _unlock_btn: Button
var _restore_btn: Button
var _bless_btn: Button
var _privacy_btn: Button


func _refresh_store_buttons() -> void:
	var st = Game.store
	if _unlock_btn == null:
		return
	var buyable: bool = st != null and (st.phone_store() or st.demo()) and not st.full_game()
	_unlock_btn.visible = buyable
	var p: String = st.price_text() if st else ""
	var what := "Remove the ads -- the full game" if st and st.model() == "ads" else "Unlock the full game"
	if st and st.demo():
		what = str(st.data().get("pitch_demo", {}).get("button", "Get the full game on Steam"))
	_unlock_btn.text = what + ("  (%s)" % p if p != "" else "")
	_restore_btn.visible = st != null and st.backend in ["google", "apple", "test"]
	var ads = Game.ads
	_bless_btn.visible = ads != null and ads.live() and ads.gift_why_not("blessing") == ""
	_bless_btn.text = str(ads.gift("blessing").get("name", I18n.t("The deep's blessing"))) + I18n.t("  (a short ad)") if ads else ""
	_privacy_btn.visible = ads != null and ads.privacy_button()


func _price_line(st) -> String:
	var p: String = st.price_text()
	return I18n.t("\n\nPrice: %s -- once, on this store account.") % p if p != "" else ""


func unlock_text(mode: String = "") -> String:
	var st = Game.store
	if st == null:
		return ""
	if st.full_game():
		return I18n.t("You have the full game: every floor, and no ads.") if st.model() == "ads" else I18n.t("You have the full game: every floor is open.")
	var body := ""
	if st.model() == "ads":
		var pa: Dictionary = st.data().get("pitch_ads", {})
		body = str(pa.get("body", "")) if mode == "word" else str(pa.get("menu_body", ""))
	else:
		body = str(st.data().get("pitch", {}).get("body", "Below floor 5 is the full game."))
	body += _price_line(st)
	var w: String = st.why_not()
	if w != "":
		body += "\n\n" + w
	return body


func open_unlock(level_id: String, arrive_at: String) -> void:
	## the store's window -- from the stair (level_id: where you were going) or the menus ("")
	var st = Game.store
	if st == null:
		return
	if _title and _title.visible:
		close_title()
	if _pause and _pause.visible:
		_toggle_pause()
	var why: String = st.travel_check(level_id) if level_id != "" else ""
	if why.begins_with("expansion:"):
		open_expansion(why.trim_prefix("expansion:"), level_id, arrive_at)
		return
	if st.demo():
		_open_demo_end(level_id)
		return
	var mode := "word" if why == "word" else ("locked" if why == "locked" else "menu")
	var ads_model: bool = st.model() == "ads"
	var title := ""
	if ads_model:
		var pa: Dictionary = st.data().get("pitch_ads", {})
		title = str(pa.get("title", I18n.t("The road goes on"))) if mode == "word" else str(pa.get("menu_title", I18n.t("Remove the ads")))
	else:
		title = str(st.data().get("pitch", {}).get("title", I18n.t("The full game")))
	var opts := []
	if mode == "word":
		opts.append([str(st.data().get("pitch_ads", {}).get("carry_on", I18n.t("Carry on (free)"))), func():
			st.mark_told("ads")
			close_dialog()
			Game.go_to(level_id, arrive_at)])
	if st.can_buy():
		var p: String = st.price_text()
		var lbl := (I18n.t("Remove the ads") if ads_model else I18n.t("Unlock the full game")) + ("  -- " + p if p != "" else "")
		opts.append([lbl, func(): _buy("full_game", level_id, arrive_at)])
	if st.backend in ["google", "apple", "test"] and not st.full_game():
		opts.append(["Restore purchases", _restore_purchases])
	opts.append(["Expansions to come", open_expansions])
	opts.append(["Not now" if mode != "menu" else I18n.t("Close"), close_dialog])
	Game.log_event("unlock_window", {"from": level_id, "mode": mode})
	open_dialog(title, unlock_text(mode), opts)


func _open_demo_end(level_id: String) -> void:
	## the Steam demo: the end of the free floors, and the way to the full game
	var st = Game.store
	var pd: Dictionary = st.data().get("pitch_demo", {})
	Game.log_event("unlock_window", {"from": level_id, "mode": "demo"})
	open_dialog(str(pd.get("title", "The end of the demo")), str(pd.get("body", "")),
		[[str(pd.get("button", "Get the full game on Steam")), func(): _buy("full_game", "", "")],
		["Expansions to come", open_expansions],
		["Not now", close_dialog]])


func _buy(key: String, level_id: String, arrive_at: String) -> void:
	var after := Callable()
	if level_id != "":
		after = func():
			Game.store.mark_told("ads")
			Game.go_to(level_id, arrive_at)      # bought on the stair: straight on down
	close_dialog()
	var why: String = Game.store.buy(key, after)
	if why != "":
		open_dialog("The store", why, [["Try again", func(): open_unlock(level_id, arrive_at)], ["Not now", close_dialog]])


func _restore_purchases() -> void:
	var t: String = Game.store.restore()
	if t != "":
		Game.message.emit(t)
	close_dialog()
	_refresh_store_buttons()


func open_expansions() -> void:
	## what's planned after the game (data/store.json "expansions"): a promise, not a sale
	var st = Game.store
	var lines := []
	var opts := []
	for e in (st.expansions() if st else []):
		var id := str(e.get("id", ""))
		var tag := "planned -- not built yet"
		if str(e.get("status", "planned")) == "released":
			tag = "yours" if st.owns_expansion(id) else "out now"
			if not st.owns_expansion(id) and st.can_buy(id):
				opts.append(["%s%s" % [str(e.get("name", id)), "  -- " + st.price_text(id) if st.price_text(id) != "" else ""], func(): _buy(id, "", "")])
		lines.append("%s  (%s)\n%s" % [str(e.get("name", "?")), tag, str(e.get("pitch", ""))])
	var body := "\n\n".join(lines) if not lines.is_empty() else "Nothing planned yet."
	body += I18n.t("\n\nThe game you have is complete on its own: fifty floors to the Heart of the Deep, and an ending. Expansions add to it; nothing in it waits on them.")
	opts.append(["Close", close_dialog])
	open_dialog("Expansions to come", body, opts)


func open_expansion(id: String, level_id: String = "", arrive_at: String = "") -> void:
	## the way into an expansion's places, when it isn't yours yet
	var st = Game.store
	var e: Dictionary = st.expansion(id)
	var released := str(e.get("status", "planned")) == "released"
	var body := str(e.get("pitch", ""))
	var opts := []
	if released and st.can_buy(id):
		body += I18n.t("\n\nPrice: %s") % st.price_text(id) if st.price_text(id) != "" else ""
		opts.append(["Get %s" % str(e.get("name", id)), func(): _buy(id, level_id, arrive_at)])
	elif released and not st.phone_store():
		body += I18n.t("\n\nIt's on the store page as its own download.")
	else:
		body += I18n.t("\n\nNot built yet -- it's coming.")
	opts.append(["Not now", close_dialog])
	open_dialog(str(e.get("name", "An expansion")), body, opts)


func queue_gift(id: String) -> void:
	## offered at the next quiet moment (after whatever window is up)
	_moments_q.append(["__gift", id])


func offer_gift(id: String) -> void:
	## an ad the player can choose to watch, for something (Ads.gd "gifts")
	var ads = Game.ads
	if ads == null or ads.gift_why_not(id) != "":
		if ads and id == "recover_gold":
			ads.last_fall_gold = 0
		return
	if is_blocking() and not (_pause and _pause.visible):
		queue_gift(id)                      # (another window's up: after it)
		return
	if _pause and _pause.visible:
		_toggle_pause()
	open_dialog(str(ads.gift(id).get("name", "A gift")), ads.gift_ask(id),
		[["Watch the ad", func():
			close_dialog()
			var why: String = ads.watch_gift(id, _refresh_store_buttons)
			if why != "":
				Game.message.emit("No ad to show right now -- try again in a little while.")],
		["No thanks", func():
			if id == "recover_gold":
				ads.last_fall_gold = 0
			close_dialog()]])


func _refresh_heat() -> void:
	## nanite heat: amber, red when you're running hot; injuries named
	if _heat_bar == null:
		return
	var cap := Game.heat_cap()
	_heat_bar.max_value = cap
	_heat_bar.value = minf(Game.heat, cap)
	var hot := Game.running_hot()
	if _heat_fill:
		_heat_fill.bg_color = Color(1.0, 0.25, 0.15) if hot else Color(0.95, 0.55, 0.15)
	var t := I18n.t("Heat %d / %d%s") % [int(Game.heat), int(cap), I18n.t("  HOT: arts +15%") if hot else ""]
	if not Game.injury.is_empty():
		t += I18n.t("  ·  injured: ") + ", ".join(Game.injury.keys())
	if _heat_text.text != t:
		_heat_text.text = t


var _help_short: Label
var _pursuit_chip: Label
var _pursuit_t := 0.0


func _fold_help() -> void:
	_help.visible = false
	if _help_short and not Gfx.small_device():
		_help_short.visible = true
	Game.set_flag("ui:help_folded")


func refresh_goals() -> void:
	var g: Array = Game.next_goals()
	var al := Game.almost()                 # round 61: what you're nearly at
	if al != "":
		g = g.slice(0, 2) + [al]
	var PU = Game.sys("pull")
	var sl: String = PU.sit_line() if PU != null else ""
	if sl != "":
		g.insert(0, sl)                                   # round 152: while you sit, what the sitting is doing
	_goals.text = "\n".join(g)


func _input(event: InputEvent) -> void:
	_capture_event(event)          # round 158: before any button sees it (Space and Enter would press the focused one)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if _pause.visible:
			_toggle_pause()
		elif _trade.visible:
			close_trade()
		elif _chat.visible:
			close_chat()
		elif _dialog.visible:
			close_dialog()
		elif _hub and _hub.visible:
			_hub.close_hub()
		else:
			_toggle_pause()
		get_viewport().set_input_as_handled()
		return
	# round 39: the menu -- Tab opens it where you left off; Q / E (or the
	# shoulder buttons) flip sections while it's open
	if _hub and _hub.visible and not _dialog.visible and not _chat.visible and not _pause.visible:
		if event.is_action_pressed("cam_left") or event.is_action_pressed("guard") and event is InputEventJoypadButton:
			_hub.step(-1)
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("interact") and event is InputEventKey or event.is_action_pressed("qi_burst") and event is InputEventJoypadButton:
			_hub.step(1)
			get_viewport().set_input_as_handled()
			return
	var can_menu := not _dialog.visible and not _pause.visible and not _chat.visible and not (_title != null and _title.visible) and not (_ending != null and _ending.visible) and not (_create != null and _create.visible)
	if event.is_action_pressed("menu") and can_menu:
		_hub.toggle()
		get_viewport().set_input_as_handled()
		return
	for pair in [["party", "Party"], ["bonds", "Bonds"], ["road", "Road"], ["swarm", "Swarm"], ["map", "Map"]]:
		if event.is_action_pressed(pair[0]) and can_menu:
			_hub.toggle_page(pair[1])
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("moment") and not is_blocking():
		open_moment()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("help") and not is_blocking():
		_help.visible = not _help.visible
		if _help_short:
			_help_short.visible = not _help.visible
		if _help.visible:
			Game.set_flag("ui:help_shown")          # (they asked for it: leave it up)
			Game.flags.erase("ui:help_folded")
		else:
			Game.set_flag("ui:help_folded")
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("lattice") and not _dialog.visible and not _pause.visible and not _chat.visible:
		toggle_lattice()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("photo") and not _dialog.visible and not _pause.visible and not _chat.visible and not photo_active():
		open_photo()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("character") and not _dialog.visible and not _pause.visible and not _chat.visible:
		toggle_character()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("journal") and not _dialog.visible and not _pause.visible:
		toggle_journal()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("inventory") and not _dialog.visible and not _pause.visible:
		_hub.toggle_page("Pack")
		get_viewport().set_input_as_handled()


func set_touch_help() -> void:
	## (round 29) on a touch screen: the help says thumbs, not keys, and the
	## top-right lines move down out from under the row of buttons
	_help.text = I18n.t("Left thumb: walk (push all the way to run)  ·  right thumb: look\nATK attack  ·  GRD guard (tap: parry)  ·  USE talk / open\nSTEP dodge  ·  right-edge bar = your moves: ART, SWAP (switch), TAL, PATH, SUP (heal, boon, hex)")
	if preload("res://scripts/core/Access.gd").left_handed():          # round 142a
		_help.text = I18n.t("Right thumb: walk (push all the way to run)  ·  left thumb: look\nATK attack  ·  GRD guard (tap: parry)  ·  USE talk / open\nSTEP dodge  ·  left-edge bar = your moves: ART, SWAP (switch), TAL, PATH, SUP (heal, boon, hex)")
	_help.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_help.grow_horizontal = Control.GROW_DIRECTION_END
	_help.grow_vertical = Control.GROW_DIRECTION_END
	_help.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT, Control.PRESET_MODE_MINSIZE, 0)
	_help.position = Vector2(20, 190)
	get_tree().create_timer(45.0).timeout.connect(func(): _help.visible = false)     # (no H key on a phone to hide it)
	_level_name.position.y = 84
	_goals.position.y = 116


func pad_focus(container: Node) -> void:
	## with a game pad plugged in, the first button in a window takes the
	## focus, so the pad's stick and A button can work it
	if Input.get_connected_joypads().is_empty() or container == null:
		return
	for c in container.find_children("*", "BaseButton", true, false):
		if (c as Control).is_visible_in_tree() and not (c as BaseButton).disabled:
			(c as Control).grab_focus.call_deferred()
			return


var _moments_q: Array = []
var _banner: Label


# ---- round 59: sound ----------------------------------------------------------------------

var _sound_btn: Button
var _np_label: Label
var _np_tween: Tween


func sound_lines() -> Array:
	## [label, action] for the Sound window -- each press turns that dial one notch
	var st := Gfx.load_settings()
	var often := str(st.get("music_often", "sometimes"))
	return [
		["Music: %d / 10" % int(st.get("music", 6)), func(): Gfx.step_volume("music", get_tree())],
		["Ambience (the place's own sound): %d / 10" % int(st.get("ambience", 7)), func(): Gfx.step_volume("ambience", get_tree())],
		["Effects: %d / 10" % int(st.get("sfx", 8)), func(): Gfx.step_volume("sfx", get_tree())],
		["Music between quiet stretches: %s" % str(Gfx.MUSIC_OFTEN_LABEL.get(often, often)), func(): Gfx.next_sound_option("music_often", get_tree())],
		["Drums in a fight: %s" % str(st.get("fight_music", "on")), func(): Gfx.next_sound_option("fight_music", get_tree())],
		["Music style: %s" % ("the old loops (classic)" if str(st.get("music_style", "new")) == "classic" else "pieces with quiet between (new)"), func(): Gfx.next_sound_option("music_style", get_tree())],
		["Effects style: %s" % ("our own sounds" if str(st.get("sfx_style", "classic")) == "own" else "the originals (classic)"), func(): Gfx.next_sound_option("sfx_style", get_tree())],
		["Death burn effect: %s" % str(st.get("own_fx", "on")), func(): Gfx.next_sound_option("own_fx", get_tree())],
	]


func open_gfx_tune(back_to_pause: bool = false) -> void:
	## round 123: every effect on its own, over the preset you picked. A * marks one you changed.
	var tree := get_tree()
	var opts := []
	opts.append(["Look: %s  (tap for the next preset)" % Gfx.LABEL[Gfx.preset()], func():
		Gfx.next_preset(tree)
		_refresh_settings_buttons()
		open_gfx_tune(back_to_pause)])
	opts.append(["Picture size: %d%%  (lower = lighter on the GPU, softer picture)" % int(round(float(Gfx.settings.get("scale", "1.0")) * 100.0)), func():
		Gfx.next_scale(tree)
		open_gfx_tune(back_to_pause)])
	opts.append(["Frame cap: %s" % str(Gfx.settings.get("fps", "auto")), func():
		Gfx.next_fps(tree)
		open_gfx_tune(back_to_pause)])
	opts.append(["World: %s" % str(Gfx.WORLD_LABEL[str(Gfx.settings.get("world", "auto"))]), func():
		Gfx.next_world(tree)
		open_gfx_tune(back_to_pause)])
	for row in Gfx.TUNE:
		var key: String = row[0]
		opts.append([Gfx.tune_text(row), func():
			Gfx.tune_step(key, tree)
			open_gfx_tune(back_to_pause)])
	opts.append(["Back to the preset's own settings", func():
		Gfx.tune_reset(tree)
		open_gfx_tune(back_to_pause)])
	opts.append(["Done", func():
		close_dialog()
		if back_to_pause:
			_toggle_pause()])
	open_dialog("Graphics fine-tune", "Start from Low, Medium, High or Ultra, then change any one thing: a sharp picture with few effects, or lots of effects at a lighter size. Changes to models and textures show from the next place you enter. A * marks what you changed.", opts)


# ---- round 124: cloud save ---------------------------------------------------------------------------

func CloudSaveWhen() -> String:
	return str(Gfx.settings.get("cloud_when", "saves"))


func _cloud_done(back_to_pause: bool) -> void:
	close_dialog()
	if back_to_pause:
		_toggle_pause()


func open_cloud(back_to_pause: bool = false, note: String = "") -> void:
	var cs = Game.cloudsave
	if cs == null:
		open_dialog("Cloud save", "Cloud save isn't available in this build.", [["Done", func(): _cloud_done(back_to_pause)]])
		return
	var opts := []
	var body := "One character on every device: each save is copied to your account a little after it is written, and when you open the game on another device the NEWER save is the one you play. The older one is kept beside it as a backup, so nothing is lost. Playing offline always works; it syncs when it can.\n\n%s" % cs.describe()
	if note != "":
		body += "\n\n" + note
	if not cs.configured():
		opts.append(["Set up the cloud address...", func(): _cloud_setup_form(back_to_pause)])
	elif not cs.signed_in():
		opts.append(["Sign in...", func(): _cloud_login_form(back_to_pause, false)])
		opts.append(["Make an account...", func(): _cloud_login_form(back_to_pause, true)])
		opts.append(["Change the cloud address...", func(): _cloud_setup_form(back_to_pause)])
	else:
		opts.append(["Sync now", func(): _cloud_sync(back_to_pause)])
		opts.append(["Upload: %s" % Gfx.CLOUD_WHEN_LABEL[CloudSaveWhen()], func():
			Gfx.next_cloud_when()
			open_cloud(back_to_pause)])
		opts.append(["Take the cloud save for this slot (%d)" % Game.slot, func(): _cloud_take(back_to_pause)])
		opts.append(["Sign out", func():
			open_dialog("Cloud save", "Signing out...", [])
			await cs.sign_out()
			open_cloud(back_to_pause)])
	opts.append(["Done", func(): _cloud_done(back_to_pause)])
	open_dialog("Cloud save", body, opts)


func _cloud_form(title: String, body: String, fields: Array, submit_text: String, on_submit: Callable, back_to_pause: bool) -> void:
	## fields: [[label, placeholder, secret, text], ...] -> on_submit receives an Array of the texts
	var edits := []
	open_dialog(title, body, [
		[submit_text, func():
			var vals := []
			for e in edits:
				vals.append((e as LineEdit).text)
			on_submit.call(vals)],
		["Back", func(): open_cloud(back_to_pause)]])
	var at := 0
	for f in fields:
		var le := LineEdit.new()
		le.placeholder_text = str(f[1])
		le.secret = bool(f[2])
		le.text = str(f[3])
		le.custom_minimum_size = Vector2(320, 40)
		le.tooltip_text = str(f[0])
		_dialog_buttons.add_child(le)
		_dialog_buttons.move_child(le, at)
		at += 1
		edits.append(le)
	if edits.size() > 0:
		(edits[0] as LineEdit).grab_focus.call_deferred()


func _cloud_setup_form(back_to_pause: bool) -> void:
	var cs = Game.cloudsave
	_cloud_form("Cloud address", "Your Supabase project's address and its public (anon) key -- the two lines Project Settings -> API shows. Nothing secret goes here.", [
		["address", "https://yourproject.supabase.co", false, cs.url],
		["key", "public anon key", false, cs.anon]], "Save",
		func(v):
			cs.save_user_config(str(v[0]), str(v[1]))
			open_cloud(back_to_pause, "Saved."), back_to_pause)


func _cloud_login_form(back_to_pause: bool, making: bool) -> void:
	var cs = Game.cloudsave
	_cloud_form("Make an account" if making else "Sign in", "Your email and a password (6+ characters). Your password is only ever sent to the cloud service itself.", [
		["email", "email", false, ""], ["password", "password", true, ""]], "Make the account" if making else "Sign in",
		func(v):
			open_dialog("Cloud save", "One moment...", [])
			var r: Dictionary = await (cs.sign_up(str(v[0]), str(v[1])) if making else cs.sign_in(str(v[0]), str(v[1])))
			open_cloud(back_to_pause, str(r.get("message", ""))), back_to_pause)


func _cloud_sync(back_to_pause: bool) -> void:
	var cs = Game.cloudsave
	open_dialog("Cloud save", "Syncing...", [])
	var r: Dictionary = await cs.sync_all(Game.slot)
	open_cloud(back_to_pause, "\n".join(r.get("lines", [])))


func _cloud_take(back_to_pause: bool) -> void:
	var cs = Game.cloudsave
	open_dialog("Cloud save", "Fetching...", [])
	var r: Dictionary = await cs.take_cloud(Game.slot)
	if not r.get("ok", false):
		open_cloud(back_to_pause, str(r.get("message", "")))
		return
	open_dialog(I18n.t("Cloud save"), str(r["message"]) + I18n.t("\n\nReload from it now? (Your current game on this device is not saved first -- the old save file is kept as a backup.)"), [
		["Reload from the cloud save", func():
			close_dialog()
			Game.use_slot(Game.slot)
			Game.new_game()
			Game.load_game()
			Game.go_to(Game.current_level, Game.spawn_tag if Game.spawn_tag != "" else "P")
			if back_to_pause:
				pass],
		["Not now", func(): open_cloud(back_to_pause)]])


func open_sound(back_to_pause: bool = false) -> void:
	var opts := []
	for l in sound_lines():
		var act: Callable = l[1]
		opts.append([str(l[0]), func():
			act.call()
			_refresh_settings_buttons()
			open_sound(back_to_pause)])
	opts.append(["Done", func():
		close_dialog()
		if back_to_pause:
			_toggle_pause()])
	var body := "Music comes as pieces with quiet stretches between them; the place's own sound carries the quiet. Drums come up under a fight and go after it."
	var a = Game.audio
	if a and a.piece != "":
		var t: String = a.title_of(a.piece)
		if t != "":
			body += I18n.t("\n\nNow playing: %s") % t
	open_dialog("Sound", body, opts)


# ---- round 61: one more floor ----------------------------------------------------------

const GRADE_COLORS := {"S": Color(1.0, 0.82, 0.3), "A": Color(0.6, 0.95, 0.7), "B": Color(0.6, 0.8, 1.0), "C": Color(0.85, 0.85, 0.85), "D": Color(0.9, 0.6, 0.55)}
const QUALITY_COLORS := [Color(0.6, 0.6, 0.6), Color(1, 1, 1), Color(0.5, 0.9, 0.55), Color(0.45, 0.7, 1.0), Color(1.0, 0.7, 0.25)]


func _floor_card_soon(card: Dictionary) -> void:
	## a breath after the master falls (its loot and words come first), then the card
	if is_inside_tree():
		get_tree().create_timer(2.2).timeout.connect(func(): _moments_q.append(["__floor_card", card]))
	else:
		_moments_q.append(["__floor_card", card])


func floor_card_text(c: Dictionary) -> String:
	var lines := []
	if str(c.get("line", "")) != "":
		lines.append("\"%s\"" % str(c["line"]))
		lines.append("")
	lines.append(I18n.t("Time: %d min  (par %d)") % [int(round(float(c.get("minutes", 0)))), int(round(float(c.get("par", 0))))])
	lines.append(I18n.t("Foes felled: %d of %d%s") % [int(c.get("kills", 0)), int(c.get("foes", 0)), (I18n.t("  (%d elite)") % int(c["elites"])) if int(c.get("elites", 0)) > 0 else ""])
	if int(c.get("chests_total", 0)) > 0:
		lines.append(I18n.t("Chests: %d of %d") % [int(c.get("chests", 0)), int(c.get("chests_total", 0))])
	if int(c.get("secrets_total", 0)) > 0:
		lines.append(I18n.t("Hidden ways: %d of %d") % [int(c.get("secrets", 0)), int(c.get("secrets_total", 0))])
	lines.append(I18n.t("Walked: %d%% of it") % int(float(c.get("parts", {}).get("explored", 0.0)) * 100.0))
	if int(c.get("best_hit", 0)) > 0:
		lines.append(I18n.t("Hardest blow: %d") % int(c["best_hit"]))
	lines.append(I18n.t("Closest call: %d%% health left") % int(float(c.get("low", 1.0)) * 100.0))
	var pay: Dictionary = c.get("pay", {})
	if bool(c.get("better", false)) and (int(pay.get("gold", 0)) > 0 or float(pay.get("insight", 0)) > 0.0 or float(pay.get("qi_kills", 0)) > 0.0):
		var got := []
		if int(pay.get("gold", 0)) > 0:
			got.append(I18n.t("%d gold") % int(pay["gold"]))
		if float(pay.get("insight", 0)) > 0.0:
			got.append(I18n.t("+%d insight") % int(pay["insight"]))
		if float(pay.get("qi_kills", 0)) > 0.0:
			got.append("qi")
		lines.append("")
		lines.append((I18n.t("Your best here (was %s): ") % c["prev"] if str(c.get("prev", "")) != "" else I18n.t("First time through: ")) + ", ".join(got) + ".")
	elif str(c.get("prev", "")) != "":
		lines.append("")
		lines.append(I18n.t("Your best here is still %s -- do better and it pays the difference.") % str(c["prev"]))
	if int(c.get("streak", 0)) > 0:
		lines.append(I18n.t("Descent streak: %d -- take the stairs down to keep it going.") % int(c["streak"]))
	var b: Dictionary = c.get("below", {})
	if not b.is_empty():
		lines.append("")
		var bl := "Below: %s" % str(b.get("name", ""))
		if bool(b.get("town", false)):
			bl += I18n.t(" -- a town, a bed and a trader")
		if bool(b.get("locked", false)):
			bl += I18n.t(" (the full game)")
		lines.append(bl)
		if str(b.get("gate", "")) != "":
			lines.append(I18n.t("The way down asks for: ") + str(b["gate"]))
	var PU = Game.sys("pull")
	var tz: String = PU.teaser_block() if PU != null else ""
	if tz != "":
		lines.append("")
		lines.append(tz)                                  # round 152: end on I18n.t("just a little more")
	return "\n".join(lines)


func open_floor_card(c: Dictionary) -> void:
	var g := str(c.get("grade", "C"))
	Game.sfx("floor_clear", 0.9)
	open_dialog(I18n.t("Floor %d: %s  --  %s") % [int(c.get("depth", 0)), g, str(c.get("title", ""))], floor_card_text(c),
		[["Onward", close_dialog]])


func show_loot_reveal(id: String, q: int) -> void:
	var c: Color = QUALITY_COLORS[clampi(q, 0, QUALITY_COLORS.size() - 1)]
	show_banner(("MASTERWORK" if q >= 4 else "SUPERIOR") + ": " + Game.item_name(id), c)
	var at: Vector3 = Game.drop_pos
	if at == Vector3.INF:
		var pl = get_tree().get_first_node_in_group("player")
		at = pl.global_position if pl else Vector3.ZERO
	FX.beam(at, c)
	Game.drop_pos = Vector3.INF


func show_now_playing(title: String) -> void:
	## a piece's name, for a moment, in a corner
	if _np_label == null:
		_np_label = Label.new()
		_np_label.add_theme_font_size_override("font_size", 17)
		_np_label.add_theme_color_override("font_color", Color(0.85, 0.92, 0.88, 0.95))
		_np_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
		_np_label.add_theme_constant_override("outline_size", 6)
		_np_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		_np_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_np_label.offset_left = -520
		_np_label.offset_right = -24
		_np_label.offset_top = -132
		_np_label.offset_bottom = -106
		_np_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_np_label)
	_np_label.text = "~  %s  ~" % title
	_np_label.modulate.a = 0.0
	_np_label.visible = true
	if _np_tween:
		_np_tween.kill()
	_np_tween = create_tween()
	_np_tween.tween_property(_np_label, "modulate:a", 1.0, 1.2)
	_np_tween.tween_interval(4.5)
	_np_tween.tween_property(_np_label, "modulate:a", 0.0, 2.0)


func show_banner(text: String, color: Color = Color(1, 0.85, 0.5)) -> void:
	## a line across the middle of the screen that fades (round 30)
	if _banner == null:
		_banner = Label.new()
		_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_banner.add_theme_font_size_override("font_size", 46)
		UI.title(_banner)
		_banner.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		_banner.add_theme_constant_override("outline_size", 10)
		_banner.set_anchors_preset(Control.PRESET_TOP_WIDE)
		_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_banner.offset_top = 150
		_banner.offset_bottom = 220
		add_child(_banner)
	_banner.text = text
	_banner.add_theme_color_override("font_color", color)
	_banner.modulate.a = 0.0
	_banner.visible = true
	var tw := create_tween()
	tw.tween_property(_banner, "modulate:a", 1.0, 0.4)
	tw.tween_interval(2.6)
	tw.tween_property(_banner, "modulate:a", 0.0, 1.0)


func open_blood_choice(new_id: String) -> void:
	## you can only carry two lines: what becomes of the third?
	var pend: Dictionary = Game.bloodline.get("pending", {})
	if pend.is_empty():
		return
	var nl := Game.blood_line(new_id)
	var dn: String = Game.blood_line(Game.blood_dominant()).get("name", "")
	var sn: String = Game.blood_line(Game.blood_secondary()).get("name", "")
	var body := "%s blood has entered you: %s

You can carry only two lines -- %s (dominant, %d%%) and %s (secondary, %d%%). What becomes of the new one?" % [
		nl.get("name", new_id), nl.get("desc", ""), dn, int(Game.purity(Game.blood_dominant())), sn, int(Game.purity(Game.blood_secondary()))]
	var done := func(choice: String):
		Game.resolve_blood_choice(choice)
		close_dialog()
	open_dialog("New Blood", body, [
		["Make it my secondary line (%s fades away)" % sn, done.bind("secondary")],
		["Make it my dominant line (%s becomes secondary; %s fades)" % [dn, sn], done.bind("dominant")],
		["Burn it away to feed my %s blood" % dn, done.bind("refine")],
		["Let it go", done.bind("refuse")]])


func open_blood(note: String = "", back: Callable = Callable()) -> void:
	var rows := Game.blood_rows()
	var body := (note + "\n\n" if note != "" else "")
	if not Game.blood_awake():
		body += I18n.t("Your blood hasn't woken yet. It wakes deep down -- around the twentieth floor.")
		if not rows.is_empty():
			body += I18n.t("\n\nYou were born with %s blood (%d%%): %s") % [rows[0][0], int(rows[0][1]), Game.blood_line(str(rows[0][5])).get("stir", "")]
	elif rows.is_empty():
		body += I18n.t("No great blood runs in you -- yet. Dead masters' legacies and drops of old blood can change that.")
	else:
		for r in rows:
			var L := Game.blood_line(str(r[5]))
			body += I18n.t("%s -- %s line, %d%% (%s)\n%s\n") % [r[0], r[3], int(r[1]), r[2], L.get("desc", "")]
			var ms: Dictionary = L.get("milestones", {})
			var ats: Array = ms.keys()
			ats.sort_custom(func(a, b): return float(a) < float(b))
			for at in ats:
				body += "   %s %d%%: %s\n" % ["[x]" if float(r[1]) >= float(at) else "[ ]", int(float(at)), Game.effect_text(ms[at])]
			if str(L.get("power50", "")) != "":
				body += "   %s\n" % L.get("power50", "")
			body += "\n"
		body += I18n.t("Your dominant line gives in full; the secondary at half. Purity rises from drops of old blood, the legacies of masters, defeating your blood's kin, breakthroughs, and sitting at shrines.")
	var opts := []
	if Game.blood_secondary() != "":
		opts.append(["Let your secondary line lead (once a day)", func(): open_blood(Game.swap_blood(), back)])
	opts.append(["Back" if back.is_valid() else I18n.t("Close"), back if back.is_valid() else close_dialog])
	open_dialog("Your Blood", body, opts)


var _title: Control


func show_title() -> void:
	if _dialog and _dialog.visible and _dialog_title.text == "While you were away":
		_away_text = _dialog_body.text       # round 62: the report waits until you're through the door
		close_dialog()
	## round 31: a front door. The world is already built behind it; the
	## title just waits for a click (which, in a browser, is also what lets
	## the music start). Round 51: three games, each its own character --
	## carry on with this one, or open "Characters" to play or start another.
	if _title == null:
		_title = PanelContainer.new()
		var tsb := StyleBoxFlat.new()                 # round 50: a veil over the world, not a framed box -- the place shows through
		tsb.bg_color = Color(0.02, 0.025, 0.04, 0.84)
		_title.add_theme_stylebox_override("panel", tsb)
		_title.set_anchors_preset(Control.PRESET_FULL_RECT)
		_title.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(_title)
		var center := CenterContainer.new()
		center.set_anchors_preset(Control.PRESET_FULL_RECT)
		_title.add_child(center)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 10)
		v.custom_minimum_size = Vector2(460, 0)
		center.add_child(v)
		var t := _label(v, I18n.t("DUNGEON CRAWL ELITE"), 44, Color(1.0, 0.85, 0.5))
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var sub := _label(v, I18n.t("a cultivation dungeon crawl"), 16, Color(0.8, 0.8, 0.85))
		sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var orn := ColorRect.new()                     # a thin gold rule under the name
		orn.color = Color(0.95, 0.78, 0.45, 0.55)
		orn.custom_minimum_size = Vector2(160, 1)
		orn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		v.add_child(orn)
		_label(v, " ", 10, Color.WHITE)
		_title_btns = VBoxContainer.new()
		_title_btns.add_theme_constant_override("separation", 10)
		v.add_child(_title_btns)
		_title_foot = _label(v, "", 12, Color(0.6, 0.6, 0.65))
		_title_foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_title_foot.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_title_foot.custom_minimum_size = Vector2(460, 0)
	_title_main()
	_title.visible = true
	UI.stagger(_title.find_children("*", "VBoxContainer", true, false)[0] if not _title.find_children("*", "VBoxContainer", true, false).is_empty() else null)     # round 50: the front door unfolds
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if Game.audio:
		Game.audio.set_music("title")
	pad_focus.call_deferred(_title)


# ---- round 33: the ending ------------------------------------------------------

var _ending: PanelContainer


func show_ending() -> void:
	## The Heart of the Deep let you go: the epilogue (what became of everyone,
	## by what you chose), the credits, and the way back -- or onward.
	if _ending:
		_ending.queue_free()
	_ending = PanelContainer.new()
	_ending.add_theme_stylebox_override("panel", _box(Color(0.02, 0.02, 0.035, 0.98), Color(0.85, 0.7, 0.4)))
	_ending.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ending.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_ending)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ending.add_child(center)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	center.add_child(v)
	var t := _label(v, I18n.t("THE HEART OF THE DEEP"), 40, Color(1.0, 0.85, 0.5))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var sub := _label(v, I18n.t("fifty floors under Eliet -- the end of this road"), 15, Color(0.8, 0.8, 0.85))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var vh := get_viewport().get_visible_rect().size.y
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(minf(760.0, get_viewport().get_visible_rect().size.x - 40.0), minf(420.0, vh * 0.55))
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(body)
	for line in Game.epilogue_lines():
		var l := _label(body, str(line), 15, Color(0.92, 0.9, 0.85))
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(sc.custom_minimum_size.x - 24.0, 0)
	_label(body, " ", 8, Color.WHITE)
	for line in Game.credits_lines():
		var c := _label(body, str(line), 13, Color(0.7, 0.7, 0.75))
		c.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		c.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		c.custom_minimum_size = Vector2(sc.custom_minimum_size.x - 24.0, 0)
	_label(v, " ", 6, Color.WHITE)
	_button(v, "Back to Eliet", func():
		close_ending()
		Game.go_to("village", "P"))
	_button(v, "Begin again, stronger (the Trial Board in Eliet: ascend)", func():
		close_ending()
		Game.go_to("village", "P")
		Game.message.emit("The Trial Board in Eliet: Ascend -- the deep gets harder, and what you've learned comes with you."))
	if Game.audio:
		Game.audio.set_music("title")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Game.log_event("ending_shown")
	pad_focus.call_deferred(v)


func close_ending() -> void:
	if _ending:
		_ending.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if is_blocking() else Input.MOUSE_MODE_CAPTURED


var _title_btns: VBoxContainer
var _title_foot: Label
var _erase_ask := -1


func _clear_title_btns() -> void:
	for c in _title_btns.get_children():
		_title_btns.remove_child(c)
		c.queue_free()


func _title_main() -> void:
	## carry on with this character, or choose another
	_clear_title_btns()
	_erase_ask = -1
	var me: Dictionary = Game.slot_info(Game.slot)
	var playing: bool = Game.background != "" and (bool(me.get("exists", false)) or Game.has_flag("creation_done"))
	if playing:
		_button(_title_btns, I18n.t("Continue -- %s, %s, %s") % [Game.char_name if Game.char_name != "" else "you", Game.cultivation_label(), _place_name(Game.current_level)], close_title)
	else:
		_button(_title_btns, "Begin -- a new character in slot %d" % Game.slot, close_title)
	_button(_title_btns, I18n.t("Characters  (%d of %d slots in use)") % [_slots_used(), Game.SLOTS], _title_slots)
	_button(_title_btns, "Language: %s" % I18n.native_name(I18n.current), func():        # round 140: tap to go to the next one
		var cs: Array = I18n.codes()
		I18n.set_language(str(cs[(cs.find(I18n.current) + 1) % cs.size()]))
		_title_main())
	if Game.store and (Game.store.phone_store() or Game.store.demo()) and not Game.store.full_game():
		var tl := "Remove the ads -- the full game" if Game.store.model() == "ads" else "Unlock the full game"
		if Game.store.demo():
			tl = str(Game.store.data().get("pitch_demo", {}).get("button", "Get the full game on Steam"))
		_button(_title_btns, tl, func(): close_title(); open_unlock("", ""))      # round 58
	_button(_title_btns, I18n.t("Settings"), func(): close_title(); _toggle_pause())
	if not OS.has_feature("web"):
		_button(_title_btns, "Quit", func(): Game.save_game(); get_tree().quit())
	_title_foot.text = "v%s   ·   %s" % [str(ProjectSettings.get_setting("application/config/version", "")), "Steam " + Game.steam.status if Game.steam and Game.steam.on else "move WASD · look with the mouse · E to talk · Esc for the menu"]
	pad_focus.call_deferred(_title_btns)


func _slots_used() -> int:
	var n := 0
	for i in range(1, Game.SLOTS + 1):
		if bool(Game.slot_info(i).get("exists", false)) or (i == Game.slot and Game.background != ""):
			n += 1
	return n


func _title_slots() -> void:
	## the three games: each its own character, saved on its own
	_clear_title_btns()
	_label(_title_btns, I18n.t("Characters"), 22, Color(1.0, 0.85, 0.5)).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	for n in range(1, Game.SLOTS + 1):
		var info: Dictionary = Game.slot_info(n)
		var here := n == Game.slot
		if here and Game.background != "":
			info = {"slot": n, "exists": true, "name": Game.char_name if Game.char_name != "" else "(unnamed)", "label": Game.cultivation_label(),
				"place": Game.current_level, "playtime": Game.playtime, "saved_at": Time.get_unix_time_from_system(), "finished": Game.finished()}
		var card := PanelContainer.new()
		var cs: StyleBoxFlat = UI.box(Color(0.06, 0.065, 0.09, 0.95), UI.col("gold", Color(0.95, 0.78, 0.45)) if here else Color(0, 0, 0, 0), "card")
		card.add_theme_stylebox_override("panel", cs)
		card.custom_minimum_size = Vector2(460, 0)
		_title_btns.add_child(card)
		var cv := VBoxContainer.new()
		cv.add_theme_constant_override("separation", 4)
		card.add_child(cv)
		if bool(info.get("exists", false)):
			_label(cv, I18n.t("Slot %d  ·  %s%s") % [n, str(info.get("name", "")), I18n.t("   (playing now)") if here else ""], 17, Color(1.0, 0.9, 0.7))
			var pt := int(float(info.get("playtime", 0.0)))
			_label(cv, I18n.t("%s  ·  %s  ·  %dh %02dm played%s") % [str(info.get("label", "")), _place_name(str(info.get("place", "village"))), pt / 3600, (pt / 60) % 60,
				"  ·  the road walked" if bool(info.get("finished", false)) else ""], 13, Color(0.8, 0.84, 0.9))
			var when := float(info.get("saved_at", 0.0))
			if when > 0.0 and not here:
				_label(cv, I18n.t("Last played ") + Time.get_datetime_string_from_unix_time(int(when), true).left(16), 12, Color(0.6, 0.62, 0.68))
			var r := HBoxContainer.new()
			r.add_theme_constant_override("separation", 8)
			cv.add_child(r)
			if here:
				_button(r, "Continue", close_title)
			else:
				_button(r, "Play", func():
					Game.switch_slot(n, false)
					close_title())
			if _erase_ask == n:
				_button(r, "Yes, erase it", func():
					_erase_slot(n))
				_button(r, "Keep it", func():
					_erase_ask = -1
					_title_slots())
			else:
				_button(r, "Erase", func():
					_erase_ask = n
					_title_slots())
		else:
			_label(cv, I18n.t("Slot %d  ·  empty") % n, 17, Color(0.75, 0.78, 0.85))
			_label(cv, I18n.t("A new character, with a world of their own: their own inheritances, their own road."), 13, Color(0.65, 0.68, 0.75))
			_button(cv, "Begin a new character here", func():
				_new_in_slot(n))
	_button(_title_btns, "Back", _title_main)
	pad_focus.call_deferred(_title_btns)


func _new_in_slot(n: int) -> void:
	if n == Game.slot and Game.background == "":
		close_title()
		return
	Game.switch_slot(n, true)
	close_title()


func _erase_slot(n: int) -> void:
	## erase a character (the file is kept, renamed, in case it's wanted back)
	if n == Game.slot:
		Game.erase_slot(n)
		Game.new_game()
		Game.use_slot(n)
		Game.go_to("village", "P")
	else:
		Game.erase_slot(n)
	_erase_ask = -1
	_title_slots()


var _away_text := ""


func close_title() -> void:
	if _title:
		_title.visible = false
	if _away_text != "":
		_moments_q.append(["While you were away", _away_text])     # (round 62: shown once you're in)
		_away_text = ""
	if Game.needs_creation() and not Game.arena_active():
		start_creation.call_deferred()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if is_blocking() else Input.MOUSE_MODE_CAPTURED
	if Game.audio:
		var lv = get_tree().root.find_child("Level", true, false)
		if lv:
			Game.audio.set_music(Game.audio.music_for(lv.level_id, lv.def))


func open_craftplay(kind: String, skill: String, edge: int, cb: Callable) -> void:
	## round 141c: the mini-game for a craft (scripts/ui/CraftPlayUI.gd); cb(score) when it ends, cb(-1.0) if skipped
	if _play == null:
		_play = preload("res://scripts/ui/CraftPlayUI.gd").new()
		add_child(_play)
	_play.start(kind, skill, edge, cb)


func open_photo(beast_slot: int = -1) -> void:
	## round 165: photo mode (F9, the pause menu, a beast's Photograph button)
	if _title != null and _title.visible:
		return
	if _photo == null:
		_photo = preload("res://scripts/ui/PhotoMode.gd").new()
		get_parent().add_child(_photo)
	if _pause.visible:
		_toggle_pause()
	if _hub != null and _hub.visible:
		_hub.close_hub()
	_photo.open(beast_slot)


func photo_active() -> bool:
	return _photo != null and _photo.active


func is_blocking() -> bool:
	return photo_active() or (_hub != null and _hub.visible) or (_title != null and _title.visible) or (_ending != null and _ending.visible) or (_char != null and _char.visible) or (_create != null and _create.visible) or _dialog.visible or _pause.visible or _inventory.visible or _journal.visible or _chat.visible or _lattice.visible or _trade.visible or (_play != null and _play.visible)


func menu_pages_open() -> bool:
	## the planning pages (menu, bag, journal, sheet, meridians, trade) -- the
	## world holds still behind these; dialogs/pause/title are handled apart
	return photo_active() or (_hub != null and _hub.visible) or (_char != null and _char.visible) or _inventory.visible or _journal.visible or _lattice.visible or _trade.visible


func toggle_lattice() -> void:
	_hub.toggle_page("Meridians")             # round 39: a page of the menu


func _fill_lattice(hover: String = "") -> void:
	## the right-hand side: the point under the mouse (or your focus), your
	## progress, and every art you know with its mastery
	var pid := hover if hover != "" else Game.lattice_focus
	var lines := []
	lines.append(I18n.t("%d of 36 points open.") % Game.lattice.size())
	if pid != "":
		var p: Dictionary = Game.lattice_point(pid)
		var state := "open" if Game.lattice.has(pid) else ("%d%% open" % int(Game.point_fraction(pid) * 100) if Game.point_ring_open(int(p.get("ring", 1))) else "sealed")
		lines.append(I18n.t("\n%s -- %s\n%s meridian, %s ring, %s. %s.") % [p.get("name", pid), p.get("meaning", ""), str(p.get("meridian", "")).capitalize(),
			Game._ordinal(int(p.get("ring", 1))), str(p.get("element", "")), state])
		lines.append(I18n.t("Opening it: %s, and +5 %s affinity.") % [Game._point_bonus_text(str(p.get("meridian", "")), int(p.get("ring", 1))), p.get("element", "")])
		if pid == Game.lattice_focus and not Game.lattice.has(pid):
			lines.append(I18n.t("This is your focus."))
		elif hover != "" and Game.can_focus(pid) == "":
			lines.append(I18n.t("Click to make it your focus."))
	else:
		lines.append(I18n.t("\nNo focus yet -- click a point to start opening it."))
	if Game.bridges.has(pid):
		lines.append(I18n.t("A nanite bridge spans it: arts run through, half again as hot."))
	lines.append(I18n.t("Heat %d / %d.  Bridges: %d placed, %d carried (hold %d).") % [int(Game.heat), int(Game.heat_cap()), Game.bridges.size(), Game.count("nanite_bridge"), Game.bridge_limit()])
	var miss: Array = Game.breakthrough_missing()
	lines.append(I18n.t("Insight %d / %d. To break through to %s: %s.") % [int(Game.insight), Game.insight_need(), Game.realm_info(Game.realm + 1)["name"],
		"ready -- sit (M) and face your heart demon" if miss.is_empty() else ", ".join(miss)])
	_lat_info.text = "\n".join(lines)
	_lat_arts.text = ""
	_lat_arts.visible = false
	_fill_lattice_rows()
	if _lat_view:
		_lat_view.queue_redraw()


func _fill_lattice_rows() -> void:
	if _lat_rows == null:
		return
	for c in _lat_rows.get_children():
		c.queue_free()
	# a bridge for the point you clicked
	if _lat_sel != "" and not Game.lattice.has(_lat_sel):
		var bp := Game.lattice_point(_lat_sel)
		if Game.bridges.has(_lat_sel):
			_row_button(_lat_rows, "Pull the bridge out of %s" % bp.get("name", _lat_sel), func():
				Game.message.emit(Game.pull_bridge(_lat_sel))
				_fill_lattice())
		elif Game.count("nanite_bridge") > 0:
			var why := Game.can_bridge(_lat_sel)
			var b := _row_button(_lat_rows, "Wire a nanite bridge across %s" % bp.get("name", _lat_sel) if why == "" else why, func():
				Game.message.emit(Game.set_bridge(_lat_sel))
				_fill_lattice())
			b.disabled = why != ""
	_fill_swarm_rows()
	var axm = Game.sys("arts")
	if axm != null:                                   # round 122: where the support arts go
		_row_button(_lat_rows, "Support arts: %s  (tap to change)" % axm.mode_text(), func():
			Game.message.emit(axm.cycle_mode())
			_fill_lattice())
	var ah := Label.new()
	ah.text = I18n.t("\nYour arts:") if not Game.arts.is_empty() else I18n.t("\nYour arts: none yet -- they come from shrines, steles, masters, and from glimpses of what you do.")
	ah.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ah.custom_minimum_size = Vector2(420, 0)
	ah.add_theme_font_size_override("font_size", 15)
	ah.add_theme_color_override("font_color", Color(1.0, 0.88, 0.6))
	_lat_rows.add_child(ah)
	for aid in Game.arts:
		var id := str(aid)
		var a: Dictionary = Game.arts[aid]
		var nxt: float = Game.art_next_need(id)
		var fam := Game.art_family(id)
		var slot := Game.slot_of(id)
		var wired := Game.slot_art(slot) == id
		var l := Label.new()
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(420, 0)
		l.add_theme_font_size_override("font_size", 14)
		l.add_theme_color_override("font_color", Color(1.0, 0.88, 0.6))
		l.text = "%s (%s) -- %s%s%s%s%s" % [Game.technique_defs.get(id, {}).get("name", id), fam, Game.art_stage_name(id),
			(I18n.t("  %d/%d, +%d unsettled") % [int(a.get("m", 0.0)), int(nxt), int(a.get("u", 0.0))]) if nxt > 0.0 else "",
			("  · " + Game.art_branch(id)) if Game.art_branch(id) != "" else "",
			"  · heat %d" % int(Game.art_heat(id)) if Game.art_heat(id) > 0.0 else "",
			("  [%s]" % ("locked" if axm != null and axm.is_ext(id) and axm.gate(id) != "" else "route sealed")) if Game.art_blocked(id) != "" else ""]
		_lat_rows.add_child(l)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 6)
		_lat_rows.add_child(h)
		if axm != null and fam != "guard" and Game.art_blocked(id) == "":
			var rl := Label.new()
			rl.text = axm.resonance_text(id)
			rl.add_theme_font_size_override("font_size", 11)
			rl.add_theme_color_override("font_color", Color(0.55, 0.95, 0.85))
			h.add_child(rl)
		if not wired and Game.known_arts(slot).size() > 1:
			_row_button(h, "Wire to %s" % ("guard" if axm != null and axm.slot_key(slot) == "guard" else (axm.slot_key(slot) if axm != null else "?")), func():
				Game.message.emit(Game.wire(id))
				_fill_lattice())
		if fam != "guard" and Game.art_blocked(id) == "":
			for qi in range(4):
				var qn := qi
				var on := str(Game.quick_slots[qi]) == id
				var qb := _row_button(h, "%s%s" % [Game.quick_key_label(qi), " ✓" if on else ""], func():
					Game.message.emit(Game.set_quick(qn, "" if on else id))
					_fill_lattice())
				qb.tooltip_text = I18n.t("Put this art on quick key %s") % Game.quick_key_label(qi)
				qb.custom_minimum_size = Vector2(46, 0)
		if Game.can_branch(id) == "":
			for el in Game.branch_options(id):
				var e := str(el)
				var bb := _row_button(h, "%s: %s" % [e.capitalize(), Game.branch_text(id, e)], func():
					Game.message.emit(Game.choose_branch(id, e))
					_fill_lattice())
				bb.tooltip_text = Game.branch_text(id, e)
				bb.clip_text = true
				bb.custom_minimum_size = Vector2(205, 0)
	if axm != null:                                   # round 122: the library, and what each art asks of you
		var al := Label.new()
		al.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		al.custom_minimum_size = Vector2(420, 0)
		al.add_theme_font_size_override("font_size", 13)
		al.add_theme_color_override("font_color", Color(0.9, 0.8, 1.0))
		var at := ["\nThe wider library (sects, roads, and what you find):"]
		for r in axm.rows():
			if not bool(r["known"]):
				at.append("  %s (%s%s) -- %s" % [r["name"], r["family"], (", " + r["sub"]) if str(r["sub"]) != "" else "", r["status"]])
		if at.size() > 1:
			al.text = "\n".join(at)
			_lat_rows.add_child(al)
	var g: Array = Game.glimpse_rows()
	if not g.is_empty():
		var gl := Label.new()
		gl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		gl.custom_minimum_size = Vector2(420, 0)
		gl.add_theme_font_size_override("font_size", 13)
		gl.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
		var t := ["\nStill to find:"]
		for r in g:
			t.append("  %s -- %s%s" % [r[0], (I18n.t("glimpsed %d/%d") % [r[1], r[2]]) if int(r[1]) > 0 else r[4],
				(I18n.t("  (needs your ") + str(r[3]) + ")") if str(r[3]) != "" else ""])
		gl.text = "\n".join(t)
		_lat_rows.add_child(gl)


func _fill_swarm_rows() -> void:
	## the swarm, beside the lattice: its tier, harmony, and its augments
	var sl := Label.new()
	sl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sl.custom_minimum_size = Vector2(420, 0)
	sl.add_theme_font_size_override("font_size", 14)
	sl.add_theme_color_override("font_color", Color(0.55, 0.95, 0.85))
	var nx := Game.integration_next()
	sl.text = I18n.t("Your swarm: %s (%d%s integration) -- %s. Augments running: %d of %d.") % [Game.tier_name(), int(Game.integration),
		(" / %d" % int(nx)) if nx > 0.0 else "", Game.harmony_text(), Game.augments_on(), Game.augment_slots()]
	_lat_rows.add_child(sl)
	for aug in Game.augments:
		var aid := str(aug)
		var d: Dictionary = Game.augment_def(aid)
		var h := HBoxContainer.new()
		_lat_rows.add_child(h)
		var on := Game.augment_on(aid)
		var b := _row_button(h, ("Stop " if on else "Run ") + str(d.get("name", aid)), func():
			Game.message.emit(Game.set_augment(aid, not on))
			_fill_lattice())
		b.tooltip_text = str(d.get("desc", ""))
		var dl := Label.new()
		dl.text = str(d.get("desc", ""))
		dl.add_theme_font_size_override("font_size", 11)
		dl.add_theme_color_override("font_color", Color(0.7, 0.85, 0.8) if on else Color(0.55, 0.6, 0.6))
		dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		dl.custom_minimum_size = Vector2(250, 0)
		h.add_child(dl)


func _row_button(parent: Node, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 12)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func open_chat(npc) -> void:
	_dialog.visible = false
	_trade.visible = false
	_chat_npc = npc
	_chat_title.text = "%s  --  %s" % [npc.npc_name, Game.bond_stage(npc.npc_name)]
	_chat_log.clear()
	_chat_add("", "Say whatever you like -- %s answers in their own words. (Ask about training, and you may find a teacher.)" % npc.npc_name, "note")
	_chat_think.text = ""
	_fill_chips()
	_chat_in.placeholder_text = "Say something..."
	_chat_in.editable = true
	_chat_send.disabled = false
	_chat_in.text = ""
	_chat.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_chat_in.grab_focus()


func open_moment() -> bool:
	## T: do something nobody built a menu for (Moment.gd).
	var wait := Game.moment_wait()
	if wait > 0.0:
		log_message("Not yet -- the world is still settling from the last thing you tried (%ds)." % int(ceil(wait)))
		return false
	if _moment == null:
		_moment = preload("res://scripts/fx/Moment.gd").new()
		add_child(_moment)
	open_oneshot(_moment, I18n.t("What do you do?"), (I18n.t("(Anything at all -- \"I cook the boar over a fire\", \"I sing for the fishermen\", \"I climb the pillar to see what glitters\". ") +
		I18n.t("The world judges it by who you are and where you stand, and answers -- nothing comes free, and nothing is for nothing. ") +
		"One try; then the world needs a few minutes.)"), "Describe what you try...")
	return true


func open_oneshot(node: Node, title: String, intro: String, placeholder: String) -> void:
	## The chat panel, for something that takes one line from you and
	## answers once (a moment, a wish at the smith's).
	_dialog.visible = false
	_inventory.visible = false
	_journal.visible = false
	_chat_npc = node
	_chat_title.text = title
	_chat_log.clear()
	_chat_add("", intro, "note")
	_chat_think.text = ""
	_fill_chips()
	_chat_in.placeholder_text = placeholder
	_chat_in.editable = true
	_chat_send.disabled = false
	_chat_in.text = ""
	_chat.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_chat_in.grab_focus()


func choose_background(group: String = "") -> void:
	## Who you were before the road -- asked once, at the start (and once
	## of anyone whose save is older than backgrounds). Round 36: the whole of
	## creation (a name, a look, a past, seven questions) starts here.
	if group == "":
		start_creation()
		return
	if not Game.needs_background():
		return
	var intro := "Before the road, before Eliet -- who were you?\n\nEveryone who lives long enough to leave home can throw a punch and find water: you start an Apprentice at Unarmed and Survival. Your past gives you ONE more thing you're good at. Everything else -- every weapon, every craft -- you'll have to learn."
	if Game._legacy_save:
		intro += I18n.t("\n\n(Your save is older than this question. Nothing you've learned is taken away; this only adds.)")
	if group == "":
		open_dialog("Who were you?", intro, [
			["Someone who made things (a craft)", choose_background.bind("craft")],
			["Someone who found things (gathering)", choose_background.bind("gather")],
			["Someone who fought (a weapon)", choose_background.bind("weapon")]])
		return
	var opts := []
	var lines := []
	for bid in Game.BACKGROUNDS:
		var b: Dictionary = Game.BACKGROUNDS[bid]
		if str(b["group"]) != group:
			continue
		lines.append("%s (%s): %s" % [b["name"], Game.skill_name(str(b["skill"])), b["desc"]])
		opts.append(["%s: %s" % [b["name"], Game.skill_name(str(b["skill"]))], _pick_background.bind(str(bid))])
	opts.append(["(back)", choose_background.bind("")])
	open_dialog("Who were you?", "\n".join(lines), opts)


func _pick_background(bid: String) -> void:
	close_dialog()
	Game.choose_background(bid)


func open_trade(npc, note: String = "") -> void:
	_dialog.visible = false
	_chat.visible = false
	_trade_npc = npc
	_trade_title.text = npc.npc_name
	_trade_line.text = npc.trade_line()
	_trade.visible = true
	fill_trade(note)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close_trade() -> void:
	_trade.visible = false
	_trade_npc = null
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func fill_trade(note: String = "") -> void:
	## both sides of the counter, refreshed in place after every sale
	if _trade_npc == null:
		return
	_trade_gold.text = I18n.t("%d gold") % Game.gold
	_trade_note.text = note
	for c in _trade_buy.get_children():
		c.queue_free()
	for c in _trade_sell.get_children():
		c.queue_free()
	for row in _trade_npc.trade_stock():
		var id := str(row[0])
		var price := int(row[1])
		var d: Dictionary = Game.item_def(id)
		_trade_row(_trade_buy, "%s" % Game.item_name(id), I18n.t("%d gold%s") % [price, (I18n.t("  ·  you have %d") % Game.count(id)) if Game.count(id) > 0 else ""],
			str(d.get("desc", "")), [["Buy", func(): fill_trade(_trade_npc.trade_buy(id, 1)), Game.gold < price]] +
			([["x5", func(): fill_trade(_trade_npc.trade_buy(id, 5)), Game.gold < price * 5]] if str(d.get("type", "")) == "consumable" else []))
	var mine: Array = Game.sellables()
	if mine.is_empty():
		_label(_trade_sell, I18n.t("Nothing they'd buy."), 14, Color(0.6, 0.6, 0.6))
	for id in mine:
		var p := Game.sell_price(id)
		var n := Game.count(id)
		var acts := [["Sell 1", func(): fill_trade(_trade_npc.trade_sell(id, 1)), false]]
		if n > 1:
			acts.append(["All %d" % n, func(): fill_trade(_trade_npc.trade_sell(id, Game.count(id))), false])
		_trade_row(_trade_sell, "%d × %s" % [n, Game.item_name(id)], I18n.t("%d gold each") % p, Game.item_desc(id), acts)


func _trade_row(list: VBoxContainer, title: String, sub: String, desc: String, actions: Array) -> void:
	var box := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.04)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(6)
	box.add_theme_stylebox_override("panel", sb)
	list.add_child(box)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	box.add_child(h)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 0)
	h.add_child(v)
	_label(v, title, 15, Color(0.95, 0.93, 0.88))
	var sl := _label(v, sub, 12, Color(0.95, 0.8, 0.45))
	sl.tooltip_text = desc
	box.tooltip_text = desc
	for a in actions:
		var b := Button.new()
		b.text = str(a[0])
		b.add_theme_font_size_override("font_size", 13)
		b.disabled = bool(a[2])
		b.pressed.connect(a[1])
		b.custom_minimum_size = Vector2(56, 30)
		h.add_child(b)


func close_chat() -> void:
	_chat.visible = false
	_chat_npc = null
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func chat_say(text: String) -> void:
	_chat_in.text = text
	_chat_say()


func _chat_to_bottom() -> void:
	pass                 # (the log follows the conversation on its own now)


func _chat_add(who: String, text: String, kind: String) -> void:
	## one line in the conversation: you in blue, them in gold, notes in grey
	var esc := text.replace("[", "[lb]")
	var line := ""
	match kind:
		"you":
			line = I18n.t("[color=#9cc7ff][b]You:[/b][/color] ") + esc
		"them":
			line = I18n.t("[color=#e8c88a][b]%s:[/b][/color] %s") % [who.replace("[", "[lb]"), esc]
		"plain":
			line = esc
		_:
			line = "[color=#9a9fab][i]%s[/i][/color]" % esc
	_chat_log.append_text(("\n\n" if _chat_log.get_parsed_text().strip_edges() != "" else "") + line)


func chat_note(t: String) -> void:
	_chat_add("", t, "note")
	_fill_chips()


func chat_text() -> String:
	return _chat_log.get_parsed_text()


func _fill_chips() -> void:
	## quick things to say or do -- the ways in to what someone can offer
	for c in _chat_chips.get_children():
		c.queue_free()
	var npc = _chat_npc
	if npc == null or not npc.has_method("lesson"):
		_chat_chips.visible = false
		return
	_chat_chips.visible = true
	var nm: String = npc.npc_name
	if Game.knows_lesson(nm) and Game.lesson_for(nm, npc.role) != "":
		var ln: Dictionary = Game.training_data().get("lessons", {}).get(Game.lesson_for(nm, npc.role), {})
		var b := _chip(I18n.t("Train: %s (%d gold)") % [ln.get("name", I18n.t("a lesson")), Game.lesson_price(nm)], func(): npc.lesson())
		b.disabled = Game.lesson_wait(nm)
		if b.disabled:
			b.text += I18n.t(" -- tomorrow")
		b.tooltip_text = str(ln.get("desc", ""))
	elif Game.lesson_for(nm, npc.role) != "":
		_chip(I18n.t("Ask about training"), func(): chat_say(I18n.t("Could you teach me anything? Any training?")))
	_chip("Heard anything strange?", func():
		_chat_add("", "Heard anything strange?", "you")
		var r := Game.rumour(hash(nm + Game.today()))
		_chat_add(nm, ("\"%s\"" % r) if r != "" else "\"Nothing you don't already know.\"", "them"))
	_chip(I18n.t("Tell me about yourself"), func(): chat_say(I18n.t("Tell me about yourself.")))
	if npc.role == "merchant":
		_chip("Trade", func():
			close_chat()
			npc._merchant())


func _chip(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 13)
	b.pressed.connect(cb)
	_chat_chips.add_child(b)
	return b


func _chat_say() -> void:
	var t := _chat_in.text.strip_edges()
	if t == "" or _chat_npc == null or _chat_send.disabled:
		return
	_chat_in.text = ""
	_chat_add("", t, "you")
	_chat_send.disabled = true
	var npc = _chat_npc
	var is_moment: bool = npc.has_method("one_shot")
	if is_moment:
		_chat_in.editable = false
	_chat_think.text = (I18n.t("%s is thinking") % npc.npc_name) if not is_moment and "npc_name" in npc else I18n.t("The world considers")
	_think_t = 0.0
	npc.say(t, func(reply: String):
		_chat_think.text = ""
		if _chat_npc != npc:
			_chat_send.disabled = false
			return
		if is_moment:
			# one try per moment: the world answers, then the moment passes
			_chat_add("", reply, "plain")
			if not reply.begins_with("("):
				_chat_add("", (str(npc.closing_line()) if npc.has_method("closing_line") else "(The moment passes.)"), "note")
			return
		_chat_send.disabled = false
		_chat_add(npc.npc_name, reply, "them")
		_chat_title.text = "%s  --  %s" % [npc.npc_name, Game.bond_stage(npc.npc_name)]
		_fill_chips()
		_chat_in.grab_focus())


func toggle_journal() -> void:
	Game.set_flag("fs:journal")
	_hub.toggle_page("Journal")               # round 39: a page of the menu


func fill_journal() -> void:
	Game.sfx("page", 0.5)
	for c in _jr_body.get_children():
		c.queue_free()
	_label(_jr_body, I18n.t("Journal"), 24, Color(1.0, 0.85, 0.5))
	var bg: Dictionary = Game.BACKGROUNDS.get(Game.background, {})
	if not bg.is_empty():
		_wrap(_label(_jr_body, I18n.t("Before the road: %s -- %s") % [bg["name"], bg["desc"]], 13, Color(0.8, 0.78, 0.7)))
	var tf: Array = Game.top_focus()
	if str(tf[0]) != "" and float(tf[1]) >= 1.0:
		_wrap(_label(_jr_body, I18n.t("Focus: %s (%d) -- +%d%% skill growth while you stay with it") % [Game.skill_name(str(tf[0])), int(tf[1]),
			int(round((Game.focus_mult(str(tf[0])) - 1.0) * 100))], 13, Color(0.7, 0.95, 1.0)))
	_wrap(_label(_jr_body, I18n.t("In your hand: %s") % Game.proficiency_text(), 13, Color(0.95, 0.85, 0.7)))
	var standing := []
	for gid in Game.guilds:
		standing.append("%s: %s, %d %s" % [Game.guild_name(gid), Game.guild_rank_name(gid), int(Game.contribution(gid)), Game.contribution_name(gid)])
	if standing.size() > 0:
		_wrap(_label(_jr_body, I18n.t("Standing -- ") + "; ".join(standing), 13, Color(1.0, 0.8, 0.8)))
	var wn := Game.wishes_left(Game.current_level)
	if Game.havens.has(Game.current_level) or Game.current_level == "village":
		_wrap(_label(_jr_body, I18n.t("Wishes left at this settlement's smith: %d of %d") % [wn, Game.WISHES_PER_SETTLEMENT], 13, Color(0.9, 0.85, 1.0)))
	var mw := Game.moment_wait()
	_wrap(_label(_jr_body, I18n.t("T -- do something unusual: %s") % ("ready" if mw <= 0.0 else "in %ds" % int(ceil(mw))), 13, Color(0.8, 0.9, 0.8)))
	_label(_jr_body, "\nGoals", 18, Color(0.95, 0.8, 0.5))
	for b in Game.bounties_today():
		_wrap(_label(_jr_body, I18n.t("%s %s -- %d/%d  (%d gold)") % ["[done]" if bool(b.get("done", false)) else I18n.t("Bounty:"), str(b.get("text", "")),
			Game.bounty_progress(b), int(b.get("need", 1)), int(b.get("reward_gold", 0))], 14,
			Color(0.6, 0.8, 0.6) if bool(b.get("done", false)) else Color(0.95, 0.92, 0.8)))
	if int(Game.bounties.get("streak", 0)) > 1:
		_label(_jr_body, I18n.t("Bounty streak: %d days") % int(Game.bounties["streak"]), 13, Color(1.0, 0.85, 0.5))
	for row in Game.next_achievements(4):
		_wrap(_label(_jr_body, I18n.t("Achievement -- %s: %s (%d/%d)") % [row[0], row[1], int(row[2]), int(row[3])], 13, Color(0.85, 0.85, 1.0)))
	_wrap(_label(_jr_body, I18n.t("%d of %d achievements earned: +%.1f%% to all growth%s.  While you're away you'll %s.") % [Game.achievements.size(),
		Game.achievement_defs.size(), Game.achievements.size() * Game.ACHIEVEMENT_BONUS * 100.0,
		"; well rested" if Game.rested() else "", Game.away_task_text()], 13, Color(0.75, 0.9, 0.8)))
	if not Game.expedition.is_empty():
		_wrap(_label(_jr_body, I18n.t("%s is on an expedition to %s, back in %s.") % [Game.expedition.get("who", ""), Game.expedition.get("place", ""),
			Game._dur(Game.expedition_left())], 13, Color(0.8, 0.9, 1.0)))
	var SKj = Game.sys("seek")
	if SKj != null:
		for slj in [0, 1]:
			if SKj.searching(slj):
				_wrap(_label(_jr_body, I18n.t("%s's search: back in %s") % [str(Game.cslot(slj).get("name", "")), Game._dur(SKj.left(slj))], 13, Color(0.8, 0.9, 1.0)))
	var CNj = Game.sys("constructs")
	if CNj != null and not CNj.voyage.is_empty():
		_wrap(_label(_jr_body, I18n.t("%s's voyage: home in %s") % [str(CNj.voyage.get("crew", "")), Game._dur(CNj.voyage_left())], 13, Color(0.8, 0.9, 1.0)))
	# round 30: the daily trial, the week, your blood, collections
	_label(_jr_body, I18n.t("\nTrials and collections"), 18, Color(0.95, 0.8, 0.5))
	_wrap(_label(_jr_body, I18n.t("Today's trial: %s%s.  Streak %d.  Trial marks %d.") % [", ".join(Game.trial_mods().map(func(m): return str(Game.retention_data().get("daily", {}).get("mods", {}).get(m, {}).get("name", m)))),
		" (done)" if Game.trial_done_today() else " -- at the Trial Board in Eliet", int(Game.trials.get("streak", 0)), Game.marks], 13, Color(1.0, 0.88, 0.6)))
	for r in Game.weekly_rows():
		_wrap(_label(_jr_body, I18n.t("This week: %s -- %d/%d%s") % [r[0], int(r[1]), int(r[2]), I18n.t(" (done)") if bool(r[3]) else ""], 13, Color(0.6, 0.8, 0.6) if bool(r[3]) else Color(0.92, 0.9, 0.8)))
	var colls := []
	for c in Game.collections():
		colls.append("%s %d/%d" % [str(c["name"]).get_slice(" (", 0), int(c["have"]), int(c["total"])])
	_wrap(_label(_jr_body, I18n.t("Collections: ") + ", ".join(colls), 13, Color(0.85, 0.9, 1.0)))
	if int(Game.ascension.get("count", 0)) > 0:
		_wrap(_label(_jr_body, I18n.t("Ascension %d: every foe is %d%% stronger; %d heavenly marks unspent.") % [int(Game.ascension["count"]), int(round((Game.challenge_mult() - 1.0) * 100)), int(Game.ascension.get("marks", 0))], 13, Color(0.9, 0.8, 1.0)))
	# round 34: the road down (the main quest), the gates, your buffs
	_label(_jr_body, I18n.t("\nThe road down"), 18, Color(0.95, 0.8, 0.5))
	var mqc: Dictionary = Game.mq_chapter()
	if mqc.is_empty():
		_wrap(_label(_jr_body, I18n.t("Every chapter walked. The deep is yours."), 13, Color(1.0, 0.9, 0.6)))
	else:
		_wrap(_label(_jr_body, I18n.t("Chapter %d of %d -- %s: %s") % [Game.mq_index() + 1, Game.mq_chapters().size(), mqc.get("name", ""), mqc.get("brief", "")], 14, Color(1.0, 0.9, 0.6)))
		for r in Game.mq_progress():
			_wrap(_label(_jr_body, "  %s %s" % ["[done]" if bool(r[1]) else "[    ]", r[0]], 13, Color(0.6, 0.8, 0.6) if bool(r[1]) else Color(0.92, 0.9, 0.8)))
		if Game.mq_ready() and Game.mq_reporter() != "":
			_wrap(_label(_jr_body, I18n.t("  Report to %s in Eliet.") % Game.mq_reporter(), 13, Color(1.0, 0.85, 0.5)))
	var ng: Dictionary = Game.next_gate()
	if not ng.is_empty():
		var miss: Array = Game.gate_missing(int(ng.get("floor", 0)))
		_wrap(_label(_jr_body, I18n.t("The next gate, floor %d: %s") % [int(ng.get("floor", 0)), (I18n.t("open -- you have what it needs") if miss.is_empty() else I18n.t("needs ") + ", ".join(miss))], 13, Color(0.85, 0.9, 1.0)))
	var hmt: int = Game.hm_data().get("masters", []).size()
	_wrap(_label(_jr_body, I18n.t("Hidden masters: %d found, %d taught you, of %d.") % [Game.hm_count_found(), Game.hm_count_done(), hmt], 13, Color(1.0, 0.82, 0.45)))
	for mid in Game.hm:
		if Game.hm_stage(str(mid)) == "revealed":
			var hmm: Dictionary = Game.hm_master(str(mid))
			var hp: Array = Game.hm_test_progress(str(mid))
			_wrap(_label(_jr_body, "  %s (%s): %s -- %d / %d" % [hmm.get("name", ""), Game._place_label(str(hmm.get("place", ""))), hmm.get("test", {}).get("text", ""), int(hp[0]), int(hp[1])], 13, Color(0.95, 0.88, 0.7)))
	var hh: String = Game.hm_hint()
	if hh != "":
		_wrap(_label(_jr_body, I18n.t("  Rumour: ") + hh, 13, Color(0.8, 0.78, 0.9)))
	var bl: Array = Game.buff_lines()
	if not bl.is_empty():
		_wrap(_label(_jr_body, I18n.t("In effect: ") + ", ".join(bl), 13, Color(0.8, 1.0, 0.8)))
	# round 32: the story so far
	var srows := Game.story_rows()
	if not srows.is_empty() or Game.story_ending() != "":
		_label(_jr_body, I18n.t("\nThe story so far"), 18, Color(0.95, 0.8, 0.5))
		for r in srows:
			if str(r[1]) == "open":
				_wrap(_label(_jr_body, I18n.t("%s -- %s is waiting to talk, in Eliet.") % [r[0], r[3]], 14, Color(1.0, 0.9, 0.6)))
			else:
				_wrap(_label(_jr_body, I18n.t("%s -- you said: \"%s\"") % [r[0], r[2]], 13, Color(0.85, 0.85, 0.8)))
		if Game.finished():
			_wrap(_label(_jr_body, I18n.t("You walked into the Heart of the Deep, fifty floors down. This game's road is told; it continues in the sequel. (Ascend at the Trial Board to walk it again, stronger.)"), 13, Color(1.0, 0.85, 0.6)))
		if Game.story_ending() == "sealed":
			_wrap(_label(_jr_body, I18n.t("You sealed the shaft. Eliet comes first.") + (I18n.t("  (The seal is broken.)") if Game.has_flag("story:seal_broken") else ""), 13, Color(0.8, 0.9, 1.0)))
		elif Game.story_ending() == "delver":
			_wrap(_label(_jr_body, I18n.t("You went on. Below twenty-five, nothing is mapped."), 13, Color(1.0, 0.7, 0.6)))
	_label(_jr_body, "\nBlood", 18, Color(0.95, 0.8, 0.5))
	var brows := Game.blood_rows()
	if not Game.blood_awake():
		_wrap(_label(_jr_body, (I18n.t("You were born with %s blood (%d%%) -- asleep. ") % [brows[0][0], int(brows[0][1])] if not brows.is_empty() else "") + I18n.t("Blood wakes deep down, around the twentieth floor."), 13, Color(0.8, 0.75, 0.75)))
	elif brows.is_empty():
		_wrap(_label(_jr_body, I18n.t("No great blood yet. Masters' legacies and drops of old blood can change that."), 13, Color(0.8, 0.75, 0.75)))
	for r in brows:
		if Game.blood_awake():
			_wrap(_label(_jr_body, "%s -- %s, %d%% (%s)" % [r[0], r[3], int(r[1]), r[2]], 14, Color(1.0, 0.6, 0.55)))
	# round 32: who travels with you, and your home
	if not Game.companion.is_empty() or not Game.familiar.is_empty() or Game.has_home():
		_label(_jr_body, "\nYours", 18, Color(0.95, 0.8, 0.5))
		if not Game.companion.is_empty():
			var cr := []
			for r in Game.companion_rows():
				cr.append("%s %s" % [str(r[0]).to_lower(), r[1]])
			_wrap(_label(_jr_body, "%s -- %s" % [Game.companion.get("name", ""), ", ".join(cr)], 13, Color(0.85, 0.95, 1.0)))
		if not Game.companion2.is_empty():                # round 39: the second of the party
			_wrap(_label(_jr_body, "%s -- %s" % [Game.companion2.get("name", ""), ", ".join(Game.companion_rows(1).map(func(r): return "%s %s" % [r[0], r[1]]))], 13, Color(0.85, 0.95, 1.0)))
		if not Game.familiar.is_empty():
			_wrap(_label(_jr_body, I18n.t("%s -- bond %d, gives x%.1f%s.  Taming %d%s.") % [Game.familiar_title(), int(Game.familiar.get("bond", 0.0)), Game.familiar_effect_mult(),
				(I18n.t(", bite %d") % Game.familiar_bite()) if Game.familiar_bite() > 0 else "", Game.taming_level(), (": " + ", ".join(Game.taming_perks)) if not Game.taming_perks.is_empty() else ""], 13, Color(0.7, 1.0, 0.8)))
		if Game.has_home():
			var nx := Game.home_next_stage()
			_wrap(_label(_jr_body, I18n.t("Home: %s.%s") % [Game.home_stage_def().get("name", ""), (I18n.t(" Next: %s (%d gold) -- at the sign.") % [nx.get("name", ""), int(nx.get("cost", 0))]) if not nx.is_empty() else ""], 13, Color(1.0, 0.9, 0.65)))
	_label(_jr_body, "\nSkills", 18, Color(0.95, 0.8, 0.5))
	var sids: Array = Game.skill_defs.keys()
	for sid in sids:
		var lvl := Game.skill_level(sid)
		var xp := float(Game.skills.get(sid, 0.0))
		var nxt := 10.0 * (lvl + 1) * (lvl + 1)
		_wrap(_label(_jr_body, "%s %d -- %s  (%d / %d)" % [Game.skill_name(sid), lvl, Game.skill_title(sid), int(xp), int(nxt)],
			14, Color(0.92, 0.9, 0.85) if xp > 0.0 else Color(0.6, 0.6, 0.6)))
	_label(_jr_body, "\nElements", 18, Color(0.95, 0.8, 0.5))
	var aff_line := []
	for e in Game.ELEMENTS:
		aff_line.append("%s %d" % [e.capitalize(), int(Game.affinity[e])])
	_label(_jr_body, "   ".join(aff_line), 14, Color(0.9, 0.9, 0.85))
	var st: Dictionary = Game.affinity_status()
	for t in st["synergies"]:
		_wrap(_label(_jr_body, t + I18n.t(" (the second one's gift grows)"), 13, Color(0.6, 1.0, 0.7)))
	for t in st["clashes"]:
		_wrap(_label(_jr_body, t + I18n.t(" (qi gain suffers; the weaker gift halves)"), 13, Color(1.0, 0.6, 0.55)))
	_wrap(_label(_jr_body, I18n.t("Fire strengthens your strikes, Earth your body, Water your cultivation, Wood your gathering, Metal your crafting. Wood feeds Fire feeds Earth feeds Metal feeds Water feeds Wood; Water quenches Fire, Fire melts Metal, Metal cuts Wood, Wood splits Earth, Earth dams Water."), 12, Color(0.65, 0.65, 0.6)))
	_label(_jr_body, I18n.t("\nThe valley"), 18, Color(0.95, 0.8, 0.5))
	if Game.in_sect():
		var sd: Dictionary = Game.sect_def(str(Game.sect.get("id", "")))
		_wrap(_label(_jr_body, I18n.t("You are %s of the %s (%s), %d contribution. %s") % [Game.sect_rank_name(), sd.get("name", ""), sd.get("element", ""),
			int(Game.sect.get("contrib", 0.0)), Game.sect_next_text()], 13, Color(0.9, 0.85, 1.0)))
	else:
		_wrap(_label(_jr_body, I18n.t("You belong to no sect. %d sects keep seats in the hills around the valley -- the road south out of Eliet leads there.") % Game.valley_data().get("sects", []).size(),
			13, Color(0.8, 0.8, 0.85)))
	for t in Game.valley_data().get("towers", []):
		var tl: String = Game.tower_locked(str(t.get("id", "")))
		_wrap(_label(_jr_body, "%s -- %s" % [t.get("name", ""), (I18n.t("climbed to floor %d of 9") % Game.tower_cleared(str(t["id"]))) if tl == "" else I18n.t("opens at %s") % Game.realm_info(int(t.get("realm", 0)))["name"]],
			13, Color(0.85, 0.9, 1.0)))
	var lms: Array = Game.valley_data().get("landmarks", [])
	if not lms.is_empty():
		var seen := []
		for lm in lms:
			var k := "landmark:%s" % lm.get("name", "")
			if Game.has_flag(k):
				seen.append(str(lm.get("name", "")) + (I18n.t(" (searched)") if Game.has_flag(k + ":secret") else ""))
		_wrap(_label(_jr_body, I18n.t("Places found out in the valley: %d of %d%s") % [seen.size(), lms.size(),
			(" -- " + ", ".join(seen)) if not seen.is_empty() else ". Walk off the roads; there are things worth seeing."], 13, Color(0.8, 0.95, 0.8)))
	var cx: Array = Game.codex_entries()
	if not cx.is_empty():
		var fresh := Game.read_codex()
		_label(_jr_body, I18n.t("\nThe nanite codex%s") % (I18n.t(" (%d new)") % fresh if fresh > 0 else ""), 18, Color(0.95, 0.8, 0.5))
		var shut := 0
		for e in cx:
			if bool(e["open"]):
				_wrap(_label(_jr_body, str(e["name"]), 14, Color(0.6, 0.95, 0.85)))
				_wrap(_label(_jr_body, str(e["text"]), 12, Color(0.78, 0.8, 0.78)))
			else:
				shut += 1
		if shut > 0:
			_wrap(_label(_jr_body, I18n.t("%d more entries -- written for cultivators further along than you.") % shut, 12, Color(0.6, 0.6, 0.65)))
	_label(_jr_body, "\nDiscoveries", 18, Color(0.95, 0.8, 0.5))
	var drows: Array = Game.discovery_rows()
	var found := drows.filter(func(r): return bool(r[2]))
	for r in found:
		_wrap(_label(_jr_body, "%s -- %s" % [r[0], r[1]], 13, Color(0.75, 1.0, 0.9)))
	_wrap(_label(_jr_body, I18n.t("%d of %d ways of doing things found. The rest are out there -- try things; townsfolk trade rumours.") % [found.size(), drows.size()], 12, Color(0.65, 0.7, 0.7)))
	var akn: Array = Game.augments.keys()
	_wrap(_label(_jr_body, I18n.t("Swarm: %s, %d integration -- %s. Augments found: %d of %d (experiment at your workbench).") % [Game.tier_name(), int(Game.integration),
		Game.harmony_text(), akn.size(), Game.nanite_data().get("augments", {}).size()], 13, Color(0.6, 0.95, 0.85)))
	_label(_jr_body, I18n.t("\nThings you've found"), 18, Color(0.95, 0.8, 0.5))
	var ids: Array = Game.journal["items"].keys()
	ids.sort()
	if ids.is_empty():
		_label(_jr_body, I18n.t("Nothing yet."), 13, Color(0.6, 0.6, 0.6))
	for id in ids:
		var e: Dictionary = Game.journal["items"][id]
		var where: Array = e.get("where", [])
		_wrap(_label(_jr_body, I18n.t("%s  (found: %s)") % [Game.item_name(id), ", ".join(where.map(func(w): return _place_name(w)))], 14, Color(0.95, 0.92, 0.85)))
		_wrap(_label(_jr_body, Game.item_desc(id), 12, Color(0.75, 0.75, 0.7)))
	_label(_jr_body, "\nPlaces", 18, Color(0.95, 0.8, 0.5))
	for pid in Game.journal["places"]:
		var pl: Dictionary = Game.journal["places"][pid]
		_label(_jr_body, I18n.t("%s -- visited %d time(s)") % [_place_name(pid), int(pl.get("visits", 0))], 14, Color(0.92, 0.9, 0.85))
		for n in pl.get("notes", []):
			_wrap(_label(_jr_body, "   " + str(n), 12, Color(0.75, 0.75, 0.7)))


func _place_name(pid) -> String:
	if str(pid) == "valley":
		return I18n.t("The Valley of Eliet")
	if Game.TowerGen.is_tower(str(pid)):
		var tp: Dictionary = Game.TowerGen.parse(str(pid))
		return I18n.t("%s, floor %d") % [Game.tower_def(str(tp.get("id", ""))).get("name", I18n.t("a tower")), int(tp.get("n", 1))]
	var d: Dictionary = Game.load_level_def(str(pid)) if ResourceLoader.exists("res://levels/%s.json" % pid) or FileAccess.file_exists("res://levels/%s.json" % pid) else {}
	return str(d.get("name", pid))


func _wrap(l: Label) -> Label:
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(600, 0)
	return l


func _wrapc(l: Label) -> Label:
	## (round 39) wrapped text in one of two columns: it takes the column's width, not more
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(360, 0)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


var _slots_t := 0.0


func _cool_text(aid: String) -> String:
	## how long until an art can be used again, "" when it is ready (round 159)
	var pl = get_tree().get_first_node_in_group("player")
	if pl == null:
		return ""
	var c := float(pl._cool.get(aid, 0.0))
	return "  (%.1fs)" % c if c > 0.05 else ""


func _tick_slots(delta: float) -> void:
	## the slot line shows cooldowns, so it is refreshed a few times a second while any art is cooling
	_slots_t -= delta
	if _slots_t > 0.0 or not _slots.visible:
		return
	_slots_t = 0.25
	var pl = get_tree().get_first_node_in_group("player")
	var cooling := false
	if pl != null:
		for k in pl._cool:
			if float(pl._cool[k]) > 0.0:
				cooling = true
				break
	if cooling or _slots.text.contains("s)"):
		refresh()


func refresh() -> void:
	_stage.text = "%s   ·   %s%s" % [Game.cultivation_label(), Game.nanite_label(), I18n.t("   ·   in harmony") if Game.harmony() == "harmony" else ""]
	var nx := Game.integration_next()
	var t0: float = float(Game.nanite_data().get("tiers", [])[Game.nanite_tier()].get("need", 0)) if Game.nanite_data().get("tiers", []).size() > 0 else 0.0
	_swarm_bar.max_value = maxf(nx - t0, 1.0) if nx > 0.0 else 1.0
	_swarm_bar.value = (Game.integration - t0) if nx > 0.0 else 1.0
	_swarm_text.text = I18n.t("Swarm %d / %d") % [int(Game.integration), int(nx)] if nx > 0.0 else I18n.t("Swarm %d (the summit)") % int(Game.integration)
	UI.set_bar(_hp_bar, Game.hp, Game.max_hp())
	_hp_text.text = "HP %d / %d" % [Game.hp, Game.max_hp()]
	UI.set_bar(_qi_bar, Game.qi, Game.qi_to_next())
	_qi_text.text = "Qi %d / %d" % [int(Game.qi), int(Game.qi_to_next())]
	var sl := []
	var axs = Game.sys("arts")                    # round 122: the support slots depend on the mode
	for pair in (axs.slots_shown() if axs != null else [["F", "strike"], ["V", "step"], ["Guard", "guard"]]):
		var a: String = Game.slot_art(pair[1])
		if a != "":
			sl.append("%s: %s%s" % [pair[0], Game.technique_defs.get(a, {}).get("name", a), _cool_text(a)])
	for qi in range(4):
		var qa := Game.quick_art(qi)
		if qa != "":
			sl.append("%s: %s%s" % [Game.quick_key_label(qi), Game.technique_defs.get(qa, {}).get("name", qa), _cool_text(qa)])
	if Game.talisman_line() != "":
		sl.append(Game.talisman_line())          # round 38: the readied talisman
	var pth = Game.sys("paths")                  # round 121: the path's art and when it is ready
	if pth != null and pth.art_line() != "":
		sl.append(pth.art_line())
	_slots.text = "   ".join(sl)
	_slots.visible = not sl.is_empty()
	var FH = Game.sys("firsthour")
	var fl: String = FH.hud_line() if FH != null else ""
	_first.text = fl
	_first.visible = fl != ""
	_gold.text = I18n.t("%d gold   ·   dmg %d   ·   %s%s") % [Game.gold, Game.damage(), Game.item_name(Game.weapon) if Game.weapon != "" else I18n.t("bare hands"),
		" (untrained)" if Game.skill_level(Game.weapon_skill()) < 5 else ""]
	update_clock()
	if _inventory.visible:
		_kit.refresh()


func set_level_name(text: String) -> void:
	_level_name.text = text
	log_message("— " + text + " —")


func hurt_flash(frac: float) -> void:
	## a blow: the edges of the screen go red, as much as the blow took
	var S: Dictionary = preload("res://scripts/fx/FX.gd").feel("screen")
	_hurt = clampf(maxf(_hurt, 0.2 + frac * 2.5) * float(S.get("hurt_peak", 0.55)) / 0.55, 0.0, 1.0)


func _screen_tick(delta: float) -> void:
	if _screen_fx == null:
		return
	var S: Dictionary = preload("res://scripts/fx/FX.gd").feel("screen")
	var real := delta / maxf(Engine.time_scale, 0.05)
	_hurt = maxf(0.0, _hurt - float(S.get("hurt_decay", 2.2)) * real)
	var frac := float(Game.hp) / maxf(float(Game.max_hp()), 1.0)
	var lowv := clampf((0.3 - frac) / 0.3, 0.0, 1.0) * float(S.get("low_hp", 0.3)) / 0.3 if Game.hp > 0 else 0.0
	_pulse += real * float(S.get("low_pulse", 2.4)) * TAU / 2.0
	var m := _screen_fx.material as ShaderMaterial
	if m == null:
		return
	m.set_shader_parameter("vignette", float(S.get("vignette", 0.32)))
	m.set_shader_parameter("hurt", _hurt)
	m.set_shader_parameter("low", clampf(lowv, 0.0, 1.0))
	m.set_shader_parameter("pulse", _pulse)
	var vs := get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(16, 9)
	m.set_shader_parameter("aspect", vs.x / maxf(vs.y, 1.0))


func refresh_boss() -> void:
	## a boss near you (and awake): its name and health across the top
	if _boss_box == null or not is_inside_tree():
		return
	var p = get_tree().get_first_node_in_group("player")
	var best: Node = null
	var bd := float(UI.cfg().get("boss_bar", {}).get("range", 24.0))
	if p:
		for e in get_tree().get_nodes_in_group("enemy"):
			if not is_instance_valid(e) or not (e is Node3D) or not ("stats" in e) or not bool(e.stats.get("boss", false)) or e._dead or not e._revealed:
				continue
			var d: float = (e as Node3D).global_position.distance_to(p.global_position)
			if d < bd:
				bd = d
				best = e
	if best == null:
		if _boss_box.visible:
			_boss_box.visible = false
		_boss_of = null
		return
	if best != _boss_of:
		_boss_of = best
		_boss_name.text = str(best.stats.get("name", ""))
		_boss_bar.max_value = maxf(float(best.stats.get("hp", 1)), 1.0)
		_boss_bar.value = float(best.hp)
		(_boss_bar.get_meta("trail") as ProgressBar).value = float(best.hp)
		_boss_box.visible = true
		UI.pop_in(_boss_box)
	UI.set_bar(_boss_bar, float(maxi(best.hp, 0)), maxf(float(best.stats.get("hp", 1)), 1.0))


func set_prompt(text: String) -> void:
	## "E: Open the chest" -> [E] Open the chest (a key-cap and the action)
	if _prompt_full == text:
		return
	_prompt_full = text
	if text == "":
		_prompt.text = ""
		if _prompt_pill.visible:
			var tw := _prompt_pill.create_tween()
			tw.tween_property(_prompt_pill, "modulate:a", 0.0, 0.12)
			tw.tween_callback(func():
				if _prompt_full == "":
					_prompt_pill.visible = false)
		return
	var parts := split_prompt(text)
	_prompt_keytext.text = parts[0]
	_prompt_key.visible = parts[0] != ""
	_prompt.text = parts[1]
	_prompt_pill.reset_size()
	if not _prompt_pill.visible or _prompt_pill.modulate.a < 1.0:
		_prompt_pill.visible = true
		_prompt_pill.modulate.a = 0.0
		_prompt_pill.create_tween().tween_property(_prompt_pill, "modulate:a", 1.0, 0.14)


static func split_prompt(text: String) -> Array:
	## ["E", "Open the chest"] -- or ["", text] when there's no key in front
	var i := text.find(":")
	if i > 0 and i <= 12:
		var k := text.substr(0, i).strip_edges()
		if k != "" and not k.contains(".") and k.split(" ").size() <= 2:
			return [k, text.substr(i + 1).strip_edges()]
	return ["", text]


func log_message(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 15)
	# round 63: each line on its own soft pill (the apps' cards), no heavy outline
	var ls := UI._flat(UI.col("glass", Color(0.09, 0.1, 0.13, 0.82)), 10, 0.0)
	ls.content_margin_left = 10
	ls.content_margin_right = 12
	ls.content_margin_top = 3
	ls.content_margin_bottom = 3
	l.add_theme_stylebox_override("normal", ls)
	l.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	if text.begins_with("SKILL") or text.begins_with("AFFINITY") or text.begins_with("Synergy"):
		l.add_theme_color_override("font_color", Color(0.95, 0.8, 0.5))
	elif text.begins_with("Clash"):
		l.add_theme_color_override("font_color", Color(1.0, 0.6, 0.55))
	elif text.begins_with("TECHNIQUE"):
		l.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
		l.add_theme_font_size_override("font_size", 18)
	elif text.begins_with("TREASURE") or text.begins_with("INHERITANCE"):
		l.add_theme_color_override("font_color", Color(0.55, 1.0, 0.75))
		l.add_theme_font_size_override("font_size", 18)
	elif text.begins_with("BREAKTHROUGH") or text.begins_with("Cultivation rises"):
		l.add_theme_color_override("font_color", Color(0.5, 0.95, 1.0))
	elif text.begins_with("-"):
		l.add_theme_color_override("font_color", Color(1.0, 0.55, 0.5))
	_log.add_child(l)
	UI.fade_line(l)
	while _log.get_child_count() > 9:
		_log.get_child(0).queue_free()
		_log.remove_child(_log.get_child(0))
	var tw := l.create_tween()
	tw.tween_interval(6.0)
	tw.tween_property(l, "modulate:a", 0.0, 1.5)
	tw.tween_callback(l.queue_free)


# ---- dialog -------------------------------------------------------------------

func open_dialog(title: String, body: String, options: Array) -> void:
	## options: [[button text, Callable], ...]
	if _trade:
		_trade.visible = false
	_dialog_title.text = title
	_dialog_body.text = body
	for c in _dialog_buttons.get_children():
		c.queue_free()
	for o in options:
		_button(_dialog_buttons, str(o[0]), o[1])
	# size to fit, up to a limit -- then scroll (the window is 720 high)
	var lines := body.count("\n") + 1 + int(body.length() / 80)
	var vh := get_viewport().get_visible_rect().size.y          # (a phone's screen is shorter: round 29)
	_dialog_body_scroll.custom_minimum_size = Vector2(640, minf(lines * 26.0, minf(320.0, vh * 0.42)))
	_dialog_btn_scroll.custom_minimum_size = Vector2(640, minf(options.size() * 38.0, minf(300.0, vh * 0.36)))
	_dialog_body_scroll.scroll_vertical = 0
	_dialog_btn_scroll.scroll_vertical = 0
	if not _dialog.visible:
		Game.sfx("ui_open", 0.5)
	_dialog.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	pad_focus.call_deferred(_dialog_buttons)


func open_controls(group: String = "") -> void:
	## round 158: every key can be moved. Pick a group, then an action, then press the key you want.
	var C = preload("res://scripts/core/Controls.gd")
	var groups := []
	for r in C.ROWS:
		if not groups.has(str(r[2])):
			groups.append(str(r[2]))
	var opts := []
	if group == "":
		for g in groups:
			var gg: String = g
			opts.append([I18n.t(gg), func(): open_controls(gg)])
		opts.append([I18n.t("Put every key back to its default"), func():
			C.reset_all()
			Game.message.emit(I18n.t("All keys are back to their defaults."))
			open_controls()])
		opts.append([I18n.t("Close"), close_dialog])
		open_dialog(I18n.t("Controls"), I18n.t("Choose a group, then tap an action and press the key you want for it. Escape cancels. A key another action used is moved over to this one, and you are told.\n\nGame pad: hold Back and press A, B, X, Y for the four quick arts; tap Back alone for the bag."), opts)
		return
	var lines := []
	for r in C.ROWS:
		if str(r[2]) != group:
			continue
		if str(r[0]) == "vault_dump" and Game.sys("tester").clean():
			continue
		var act := str(r[0])
		var mark := "" if C.is_default(act) else " *"
		opts.append(["%s:  %s%s" % [I18n.t(str(r[1])), C.key_text(act), mark], func(): _capture_key(act, group)])
	lines.append(I18n.t("* = changed from the default. Tap an action, then press its new key."))
	opts.append([I18n.t("Reset this group"), func():
		for r2 in C.ROWS:
			if str(r2[2]) == group:
				C.reset_one(str(r2[0]))
		open_controls(group)])
	opts.append([I18n.t("Back"), func(): open_controls()])
	open_dialog(I18n.t(group), "\n".join(lines), opts)


var _capture_action := ""
var _capture_group := ""


func _capture_key(action: String, group: String) -> void:
	var C = preload("res://scripts/core/Controls.gd")
	_capture_action = action
	_capture_group = group
	open_dialog(I18n.t("Press a key"), I18n.t("Press the key for: %s\n(Escape to cancel.)") % C.label_of(action), [[I18n.t("Cancel"), func():
		_capture_action = ""
		open_controls(group)]])


func _capture_event(event: InputEvent) -> bool:
	## true when the event was the key being asked for
	if _capture_action == "":
		return false
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return false
	var C = preload("res://scripts/core/Controls.gd")
	var code := int((event as InputEventKey).physical_keycode)
	var act := _capture_action
	var grp := _capture_group
	_capture_action = ""
	get_viewport().set_input_as_handled()
	if code != KEY_ESCAPE:
		Game.message.emit(C.bind(act, code))
	open_controls(grp)
	return true


func close_dialog() -> void:
	if _dialog.visible:
		Game.sfx("ui_close", 0.4)
	_dialog.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if is_blocking() else Input.MOUSE_MODE_CAPTURED


var _pause_scroll: ScrollContainer
var _pause_list: VBoxContainer


func _fit_pause() -> void:
	## as tall as its buttons, but never taller than the screen; centred
	if _pause_scroll == null:
		return
	var vh := get_viewport().get_visible_rect().size.y
	var want := _pause_list.get_combined_minimum_size()
	var w := maxf(320.0, want.x + 16.0)
	var h := minf(want.y, vh * 0.86)
	_pause_scroll.custom_minimum_size = Vector2(w, h)
	_pause.custom_minimum_size = Vector2(w, 0)
	_pause.reset_size()
	var sz := _pause.get_combined_minimum_size()
	_pause.offset_left = -sz.x / 2.0
	_pause.offset_right = sz.x / 2.0
	_pause.offset_top = -sz.y / 2.0
	_pause.offset_bottom = sz.y / 2.0
	_pause_scroll.scroll_vertical = 0


func _toggle_pause() -> void:
	_pause.visible = not _pause.visible
	get_tree().paused = _pause.visible
	if _pause.visible:
		_refresh_store_buttons()
		_fit_pause()
		pad_focus.call_deferred(_pause)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if is_blocking() else Input.MOUSE_MODE_CAPTURED


# ---- inventory ----------------------------------------------------------------

func _fill_inventory() -> void:
	_kit._refresh_now()


func open_kit(tab: String = "Pack", bench: String = "") -> void:
	## the pack screen, from anywhere -- or from a bench, open at the Bench tab
	## (round 39: the menu's Pack page)
	Game.set_flag("fs:bag")
	_kit.show_tab(tab)
	_hub.show_page("Pack")
	Game.at_bench = bench


func close_kit() -> void:
	_hub.close_hub()


func _kills_text() -> String:
	var parts := []
	for k in Game.kills:
		parts.append("%s %d" % [Game.enemies.get(k, {}).get("name", k), int(Game.kills[k])])
	return ", ".join(parts) if parts.size() > 0 else I18n.t("none yet")


# ---- widgets -------------------------------------------------------------------

func _ui_theme() -> Theme:
	## round 22: every button, field and scrollbar in one look. Round 49: built
	## by UiStyle.gd -- the same dark lacquer and gold, softer, with real fonts
	return UI.theme()


func _box(bg: Color, border: Color = Color(0, 0, 0, 0)) -> StyleBoxFlat:
	return UI.box(bg, border)


func _section(parent: Node, text: String) -> Label:
	## round 63: a quiet heading over a group of menu rows (the apps' style)
	var l := _label(parent, text.to_upper(), 11, UI.col("text_dim", Color(0.55, 0.57, 0.65)))
	if UI.font("bold"):
		l.add_theme_font_override("font", UI.font("bold"))
	l.add_theme_constant_override("line_spacing", 0)
	var m := MarginContainer.new()
	l.get_parent().remove_child(l)
	m.add_theme_constant_override("margin_top", 8)
	m.add_child(l)
	parent.add_child(m)
	return l


func _label(parent: Node, text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	if UI.is_title_size(size):
		UI.title(l)                          # headings in carved capitals
	l.add_theme_color_override("font_color", color)
	parent.add_child(l)
	return l


func _bar(parent: Node, color: Color) -> ProgressBar:
	var b := ProgressBar.new()
	b.custom_minimum_size = Vector2(320, 20)
	b.show_percentage = false
	UI.bar_style(b, color)
	parent.add_child(b)
	return b


func _overlay(bar: ProgressBar) -> Label:
	var l := Label.new()
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bf := UI.font("bold")
	if bf:
		l.add_theme_font_override("font", bf)
	bar.add_child(l)
	return l


func _button(parent: Node, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 16)
	b.pressed.connect(cb)
	b.pressed.connect(func(): Game.sfx("ui_click", 0.5))
	b.process_mode = Node.PROCESS_MODE_ALWAYS
	parent.add_child(b)
	return b


# ---- downtime: what happened while you were away; what you'll do next time --------------

func show_away_report() -> void:
	if Game.away_report.is_empty():
		return
	if _title and _title.visible:
		_away_text = "\n".join(Game.away_report)      # round 62: after the front door, not under it
		Game.away_report = []
		return
	var lines: Array = Game.away_report.duplicate()
	Game.away_report = []
	open_dialog("While you were away", "\n".join(lines), [["Back to it", close_dialog]])


# ---- round 63: quick travel (systems/Travel.gd) ----------------------------------------------

var _travel_bar: ProgressBar
var _travel_lbl: Label


func open_travel(from_stone: bool) -> void:
	var T = Game.sys("travel")
	if T == null:
		return
	var why: String = T.why_not(from_stone)
	if why != "":
		Game.message.emit(why)
		return
	var dests: Array = T.destinations()
	var opts := []
	var lines := []
	for d in dests:
		var label := str(d["name"])
		if int(d["depth"]) > 0:
			label = I18n.t("Floor %d -- %s") % [int(d["depth"]), label]
		if bool(d["here"]):
			lines.append(I18n.t("%s  (you are here)") % label)
			continue
		if not bool(d["ready"]):
			lines.append(I18n.t("%s  (attuned -- its master still lives)") % label)
			continue
		var to := str(d["id"])
		opts.append([(I18n.t("Town: ") if bool(d["town"]) and int(d["depth"]) > 0 else "") + label, func():
			close_dialog()
			var w: String = T.travel(to, from_stone)
			if w != "":
				Game.message.emit(w)])
	var tkk = Game.sys("tester")
	if tkk != null and tkk.unlocked():
		opts.append([I18n.t("Teleport to any floor"), func():          # round 168
			close_dialog()
			tkk.teleport_menu(self)])
	opts.append(["Stay", close_dialog])
	var body := ""
	if opts.size() <= 1 or (opts.size() == 2 and tkk != null and tkk.unlocked()):
		body = "No other waystone is yours yet. Each floor has one beside its way down, past its master; Eliet's stands by the fountain, and every town has its own."
	else:
		body = "Where to?%s" % ("" if from_stone else "  (From here it takes a moment of gathering yourself -- a blow breaks it.)")
	if not lines.is_empty():
		body += "\n\n" + "\n".join(lines)
	open_dialog("Waystones", body, opts)


func _on_travel_channel(left: float, total: float) -> void:
	if _travel_bar == null:
		var box := VBoxContainer.new()
		box.name = "TravelChannel"
		box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
		box.position = Vector2(-160, -150)
		box.custom_minimum_size = Vector2(320, 0)
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(box)
		_travel_lbl = _label(box, "", 15, Color(0.75, 0.9, 1.0))
		_travel_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_travel_bar = ProgressBar.new()
		_travel_bar.show_percentage = false
		_travel_bar.custom_minimum_size = Vector2(320, 10)
		_travel_bar.max_value = 1.0
		box.add_child(_travel_bar)
	var box2: Control = _travel_bar.get_parent()
	if left < 0.0:
		box2.visible = false
		return
	var T = Game.sys("travel")
	box2.visible = true
	_travel_lbl.text = I18n.t("Travelling to %s") % (str(T.stones.get(T.channel_to, {}).get("name", "")) if T else "")
	_travel_bar.value = 1.0 - (left / maxf(total, 0.01))


# ---- round 64: Report a problem -- Dev reads these and fixes them ---------------------------------

const REPORT_DIR := "user://bug_reports"
var report_dir := REPORT_DIR          # (tools point this elsewhere)


func open_report() -> void:
	var box := TextEdit.new()
	box.name = "ReportText"
	box.placeholder_text = "What went wrong? What were you doing just before?"
	box.custom_minimum_size = Vector2(600, 120)
	box.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	open_dialog("Report a problem", "Tell us what happened. Where you are, what you were doing and the last things that happened in the game are sent with it.", [
		["Send", func():
			var t := box.text.strip_edges()
			if t == "":
				Game.message.emit("Write a line about what went wrong first.")
				return
			var f := save_report(t)
			close_dialog()
			Game.message.emit("Thanks -- sent. Dev will look into it." if f != "" else "Couldn't save the report.")],
		["Cancel", close_dialog]])
	_dialog_buttons.add_child(box)
	_dialog_buttons.move_child(box, 0)
	_dialog_btn_scroll.custom_minimum_size.y += 130.0
	box.grab_focus.call_deferred()


func save_report(text: String) -> String:
	## user://bug_reports/r_<time>.json: the words, and what the game knows about the moment
	DirAccess.make_dir_recursive_absolute(report_dir)
	var pl = get_tree().get_first_node_in_group("player")
	var recent := []
	if FileAccess.file_exists(Game.playlog_path):
		var lines := FileAccess.get_file_as_string(Game.playlog_path).split("\n", false)
		recent = Array(lines.slice(maxi(0, lines.size() - 25)))
	var msgs := []
	if _log:
		for c in _log.get_children():
			if c is Label:
				msgs.append((c as Label).text)
	var rec := {"text": text, "when": Time.get_datetime_string_from_system(),
		"version": str(ProjectSettings.get_setting("application/config/version", "")),
		"platform": OS.get_name(), "level": str(Game.current_level),
		"position": str((pl as Node3D).global_position) if pl else "",
		"cultivation": Game.cultivation_label(), "hp": "%d/%d" % [Game.hp, Game.max_hp()],
		"on_screen": msgs, "recent_events": recent}
	var path := "%s/r_%d.json" % [report_dir, int(Time.get_unix_time_from_system())]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string(JSON.stringify(rec, " "))
	f.close()
	Game.log_event("bug_report", {"chars": text.length()})
	return path


func open_away_plan(then_quit: bool = false) -> void:
	## Round 63: what your character pursues while you're not playing -- with
	## the game closed, or open while you've stepped away (systems/Pursuit.gd)
	var PU = Game.sys("pursuit")
	var bank_line: String = PU.bank_text() if PU else ""
	var now_line := I18n.t("Now: you'll %s%s.") % [Game.away_task_text(), (" " + PU.goal_text()) if PU and PU.goal_text() != "" else ""]
	var body := I18n.t("When you step away -- game closed, or left standing for a minute and a half with nothing hunting you -- your character works at a pursuit, toward a goal, and rests once it's met.\n\n%s\n%s") % [now_line, bank_line]
	var after := func(t: Dictionary):
		Game.message.emit(PU.set_goal(t) if PU else Game.set_away_task(t))
		if then_quit:
			Game.save_game()
			get_tree().quit()
		else:
			close_dialog()
	var opts := [
		["Meditate...", func(): _away_pick_goal({"kind": "meditate"}, after, then_quit)],
		["Train a skill...", func(): _away_pick_skill(after, then_quit)],
		["Go out gathering...", func(): _away_pick_gather(after, then_quit)],
		["Work at the bench...", func(): _away_pick_craft(after)],
		["Just rest", after.bind({})],
	]
	if then_quit:
		opts.append(["Quit without changing it", func(): Game.save_game(); get_tree().quit()])
	opts.append(["(back)", close_dialog])
	open_dialog("Your pursuit", body, opts)


func _away_pick_goal(t: Dictionary, after: Callable, then_quit: bool = false) -> void:
	## the goal: where the pursuit stops and your character rests
	var opts := []
	var title := "Until when?"
	var body := "Your character stops once the goal is met, and rests."
	match str(t.get("kind", "")):
		"meditate":
			opts.append(["Until my next breakthrough", after.bind({"kind": "meditate", "goal": 1})])
			opts.append(["For as long as it takes", after.bind({"kind": "meditate", "goal": 0})])
		"train":
			var lv: int = Game.skill_level(str(t["skill"]))
			for up in [1, 3, 5]:
				opts.append(["To level %d" % (lv + up), after.bind({"kind": "train", "skill": str(t["skill"]), "goal": lv + up})])
			opts.append(["No end in mind", after.bind({"kind": "train", "skill": str(t["skill"]), "goal": 0})])
			body = I18n.t("%s is level %d. %s") % [Game.skill_name(str(t["skill"])), lv, body]
		"gather":
			for n in [10, 25, 50]:
				opts.append(["Bring back %d" % n, after.bind({"kind": "gather", "skill": str(t["skill"]), "goal": n})])
			opts.append(["For as long as it takes", after.bind({"kind": "gather", "skill": str(t["skill"]), "goal": 0})])
	opts.append(["(back)", func(): open_away_plan(then_quit)])
	open_dialog(title, body, opts)


func _away_pick_skill(after: Callable, then_quit: bool = false) -> void:
	var opts := []
	for sid in Game.skill_defs:
		if str(sid) in ["mining", "herbalism", "fishing", "hunting"]:
			continue
		opts.append(["%s (level %d)" % [Game.skill_name(str(sid)), Game.skill_level(str(sid))], func(): _away_pick_goal({"kind": "train", "skill": str(sid)}, after, then_quit)])
	opts.append(["(back)", func(): open_away_plan(then_quit)])
	open_dialog("Train what?", "Hours of practice, alone. Higher levels need more of it -- but you'll come back better.", opts)


func _away_pick_gather(after: Callable, then_quit: bool = false) -> void:
	var opts := []
	for sid in ["herbalism", "mining", "fishing", "hunting"]:
		if Game.skill_defs.has(sid):
			opts.append(["%s (level %d)" % [Game.skill_name(sid), Game.skill_level(sid)], func(): _away_pick_goal({"kind": "gather", "skill": sid}, after, then_quit)])
	opts.append(["(back)", func(): open_away_plan(then_quit)])
	open_dialog("Gather what?", "You'll go out on the floors you know and bring back what you find -- more as the skill grows (Floor %d is as deep as you've been)." % Game.reach_depth(), opts)


func _away_pick_craft(after: Callable) -> void:
	var opts := []
	for r in Game.recipes:
		var n := Game.bench_can_make(r)
		if n <= 0:
			continue
		opts.append(["%s x%d (%d%% each)" % [Game.item_name(str(r["makes"])), n, int(Game.craft_chance(r) * 100)],
			after.bind({"kind": "craft", "recipe": str(r["makes"]), "count": n})])
		if opts.size() >= 10:
			break
	var body := "You'll work through as many as the hours allow. It takes from your pouch first, then your chest."
	if opts.is_empty():
		body = "You don't have the materials for anything right now."
	opts.append(["(back)", func(): open_away_plan()])
	open_dialog("Make what?", body, opts)


func open_expedition(kind: String) -> void:
	## Send your companion or familiar off on their own for a few hours.
	var why := Game.can_send(kind)
	var who := str(Game.companion.get("name", "")) if kind == "companion" else str(Game.familiar.get("name", ""))
	if why != "":
		open_dialog("An expedition", why, [["All right", close_dialog]])
		return
	var opts := []
	for fid in Game.expedition_floors():
		opts.append([_place_name(fid), func(): _expedition_hours(kind, who, str(fid))])
	opts.append(["(not now)", close_dialog])
	open_dialog("Send %s where?" % who, "%s can go somewhere you've already been, and come back with whatever they find there -- the deeper, the richer, and the longer, the more. They won't be at your side while they're gone." % who, opts)


func open_search(slot: int) -> void:
	## round 155: send a human companion to search for a kind of find
	var SK = Game.sys("seek")
	var who := str(Game.cslot(slot).get("name", ""))
	if SK == null:
		return
	var opts := []
	for kk in SK.kinds():
		var why: String = SK.block(slot, str(kk))
		if why == "":
			opts.append([I18n.t(str(SK.kinds()[kk].get("name", kk))), func(): _search_hours(slot, who, str(kk))])
	opts.append(["(not now)", close_dialog])
	open_dialog(I18n.t("Send %s searching") % who, I18n.t("%s can search for plants, reagents, jewels or shards while you are about. The deeper you have been, the richer the finds.") % who, opts)


func _search_hours(slot: int, who: String, kind: String) -> void:
	var SK = Game.sys("seek")
	var opts := []
	for h in SK.hours():
		opts.append(["%d hour%s" % [int(h), "" if int(h) == 1 else "s"], func():
			close_dialog()
			var m: String = SK.start(slot, kind, float(h))
			if m != "":
				Game.message.emit(m)])
	opts.append(["(back)", func(): open_search(slot)])
	open_dialog(I18n.t("For how long?"), I18n.t("The clock keeps running when the game is closed."), opts)


func _expedition_hours(kind: String, who: String, fid: String) -> void:
	var opts := []
	for h in [1, 2, 4, 8]:
		opts.append(["%d hour%s" % [h, "" if h == 1 else "s"], func():
			close_dialog()
			Game.start_expedition(kind, fid, float(h))])
	opts.append(["(back)", func(): open_expedition(kind)])
	open_dialog(I18n.t("For how long?"), I18n.t("%s heads for %s. The clock keeps running when the game's closed.") % [who, _place_name(fid)], opts)



# ---- round 36: the character sheet (P) and the level-up window ----------------------

var _char: PanelContainer
var _char_body: VBoxContainer
var _char_sel := "max_hp"


func _ensure_char() -> void:
	if _char:
		return
	_char = PanelContainer.new()
	_char.add_theme_stylebox_override("panel", _box(Color(0.05, 0.05, 0.07, 0.96), Color(0.85, 0.7, 0.4)))
	_char.set_anchors_preset(Control.PRESET_FULL_RECT)
	_char.offset_left = 40
	_char.offset_right = -40
	_char.offset_top = 30
	_char.offset_bottom = -30
	_char.visible = false
	add_child(_char)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_char.add_child(sc)
	_char_body = VBoxContainer.new()
	_char_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_char_body.add_theme_constant_override("separation", 6)
	sc.add_child(_char_body)


func toggle_character() -> void:
	_ensure_char()
	_hub.toggle_page("You")


func open_character() -> void:
	_ensure_char()
	_hub.show_page("You")                     # round 39: a page of the menu


func close_character() -> void:
	if _hub:
		_hub.close_hub()


func fill_character() -> void:
	for c in _char_body.get_children():
		c.queue_free()
	var head := HBoxContainer.new()
	_char_body.add_child(head)
	var t := _label(head, "%s%s" % [(Game.char_name + " -- ") if Game.char_name != "" else "", Game.cultivation_label()], 26, Color(1.0, 0.85, 0.5))
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button(head, "Close (P)", close_character)
	var need := Game.qi_to_next()
	_wrap(_label(_char_body, I18n.t("Qi %d / %d to the next step%s.   Swarm: %s (%d integration).   %s") % [int(Game.qi), int(need),
		I18n.t(" -- the sea is full: ") + (I18n.t("sit (M) and face your tribulation") if Game.breakthrough_missing().is_empty() else I18n.t("you still need ") + ", ".join(Game.breakthrough_missing())) if Game.at_threshold() else "",
		Game.tier_name(), int(Game.integration), (I18n.t("Blood: %s") % ", ".join(Game.blood_rows().map(func(r): return "%s %d%%" % [r[0], int(r[1])]))) if not Game.blood_rows().is_empty() else ""], 14, Color(0.85, 0.9, 1.0)))
	# where you're going: the road down's next goal, and the next gate's need
	var road := []
	if Game.mq_line() != "":
		road.append(I18n.t("The road down -- ") + Game.mq_line())
	var ng: Dictionary = Game.next_gate()
	if not ng.is_empty():
		var gm: Array = Game.gate_missing(int(ng.get("floor", 0)))
		road.append(I18n.t("The gate to floor %d %s") % [int(ng.get("floor", 0)), I18n.t("is open to you") if gm.is_empty() else I18n.t("needs ") + ", ".join(gm)])
	if not road.is_empty():
		_wrap(_label(_char_body, "  ·  ".join(road), 14, Color(1.0, 0.88, 0.55)))
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 24)
	_char_body.add_child(cols)
	# -- left: the stats, and where the chosen one comes from
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(left)
	_label(left, I18n.t("Stats (pick one to see where it comes from)"), 18, Color(0.95, 0.8, 0.5))
	var sgrid := GridContainer.new()                  # round 139: two columns, half the height
	sgrid.columns = 2
	sgrid.add_theme_constant_override("h_separation", 8)
	sgrid.add_theme_constant_override("v_separation", 8)
	left.add_child(sgrid)
	for row in Game.char_data().get("stats", []):
		var key := str(row[1])
		var b := _button(sgrid, "%s:  %s" % [row[0], Game.stat_text(key, Game.stat_value(key))], func():
			_char_sel = key
			fill_character())
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		if key == _char_sel:
			b.modulate = Color(1.0, 0.9, 0.6)
	var src := Game.stat_sources(_char_sel)
	var lab := ""
	for row in Game.char_data().get("stats", []):
		if str(row[1]) == _char_sel:
			lab = str(row[0])
	_label(left, I18n.t("\n%s comes from") % lab, 16, Color(0.95, 0.8, 0.5))
	if src.is_empty():
		_label(left, I18n.t("  nothing yet -- it's earned"), 13, Color(0.7, 0.7, 0.7))
	for r in src:
		_wrapc(_label(left, "  %s: %s" % [r[0], r[1]], 13, Color(0.9, 0.9, 0.85)))
	# -- right: attributes, titles, arts
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(right)
	var free := Game.attr_points_free()
	_label(right, I18n.t("Attributes -- %d point%s to spend") % [free, "" if free == 1 else "s"], 18, Color(0.95, 0.8, 0.5) if free == 0 else Color(0.6, 1.0, 0.6))
	_wrapc(_label(right, I18n.t("Earned: 1 for each step of cultivation, 3 for each realm crossed, 1 for each chapter of the road down, 1 for each hidden master who taught you%s.") % ((I18n.t(", and %d from who you are") % int(Game.born.get("free", 0))) if int(Game.born.get("free", 0)) > 0 else ""), 12, Color(0.75, 0.75, 0.8)))
	var A: Dictionary = Game.char_data().get("attributes", {})
	for id in Game.attr_ids():
		var a: Dictionary = A.get(id, {})
		var row := HBoxContainer.new()
		right.add_child(row)
		var l := _label(row, "%s %d%s" % [a.get("name", id), Game.attr_total(id), (I18n.t("  (%d born)") % Game.attr_born(id)) if Game.attr_born(id) > 0 else ""], 16, Color(1, 1, 1))
		l.custom_minimum_size = Vector2(190, 0)
		if free > 0:
			_button(row, "+1", func():
				Game.attr_spend(id)
				Game.sfx("ui_ok", 0.6)
				fill_character())
		_wrapc(_label(right, "  " + str(a.get("desc", "")), 12, Color(0.8, 0.8, 0.85)))
	if Game.attr_points_spent() > 0:
		_button(right, "Unlearn them all (%d gold)" % Game.attr_respec_cost(), func():
			var why := Game.attr_respec()
			if why != "":
				Game.message.emit(why)
			fill_character())
	# round 37: balance (the strongest growth) and mastery (there is always more)
	_label(right, I18n.t("\nBalance %d%% -- growth x%.2f") % [int(round(Game.balance() * 100.0)), Game.balance_mult()], 18, Color(0.6, 0.95, 0.85))
	_wrapc(_label(right, I18n.t("A specialist is strong now; a balanced cultivator grows fastest. Qi, practice and the swarm all grow with your balance."), 12, Color(0.75, 0.8, 0.8)))
	for bp in Game.balance_parts():
		_wrapc(_label(right, "  %s: %d%%  (%s)" % [bp[0], int(round(float(bp[1]) * 100.0)), bp[2]], 13, Color(0.85, 0.95, 0.9)))
	_label(right, I18n.t("\nMastery %.1f%%") % (Game.mastery() * 100.0), 18, Color(0.95, 0.8, 0.5))
	var mp := []
	for m in Game.mastery_parts():
		mp.append("%s %d/%d" % [m[1], int(m[2]), int(m[3])])
	_wrapc(_label(right, "  ".join(PackedStringArray(mp.map(func(x): return str(x) + " ·"))).trim_suffix(" ·"), 12, Color(0.85, 0.85, 0.8)))
	_label(right, I18n.t("\nTitles (%d)") % Game.titles.size(), 18, Color(0.95, 0.8, 0.5))
	if Game.titles.is_empty():
		_wrapc(_label(right, I18n.t("None yet. Titles are earned -- by the road down, the masters, the story, the ring -- and each carries a small gift."), 12, Color(0.7, 0.7, 0.7)))
	for tt in Game.titles:
		_wrapc(_label(right, "  %s -- %s" % [tt, Game.title_gift_text(str(tt))], 13, Color(1.0, 0.85, 0.6)))
	_label(right, I18n.t("\nArts and techniques (%d)") % Game.techniques.size(), 18, Color(0.95, 0.8, 0.5))
	var tl := []
	for tid in Game.techniques:
		tl.append(str(Game.technique_defs.get(tid, {}).get("name", tid)))
	tl.sort()
	_wrapc(_label(right, ", ".join(tl) if not tl.is_empty() else I18n.t("None yet."), 13, Color(0.85, 0.9, 1.0)))


func open_level_up(info: Dictionary) -> void:
	## the step (or the realm) you just reached, what changed, and points to spend
	var lines := []
	for r in info.get("rows", []):
		if str(r[2]) != "":
			lines.append("%s:  %s" % [r[0], r[2]])
	var body := "You are now %s.\n\n" % str(info.get("label", ""))
	body += "\n".join(lines) if not lines.is_empty() else I18n.t("(nothing you can measure changed -- yet)")
	body += I18n.t("\n\n+%d attribute point%s -- %d to spend.") % [int(info.get("gained", 1)), "" if int(info.get("gained", 1)) == 1 else "s", Game.attr_points_free()]
	var title := "REALM BREAKTHROUGH" if str(info.get("kind", "")) == "realm" else "LEVEL UP"
	open_dialog(title, body, [["Spend points (P)", func():
		close_dialog()
		open_character()], ["Onward", close_dialog]])


var _lvl_card: PanelContainer
var _lvl_tw: Tween


func show_level_card(info: Dictionary) -> void:
	## a step of cultivation: a card in the corner with what changed -- it fades on its own
	if _lvl_card == null:
		_lvl_card = PanelContainer.new()
		_lvl_card.add_theme_stylebox_override("panel", _box(Color(0.05, 0.06, 0.04, 0.88), Color(0.6, 0.95, 0.6)))
		_lvl_card.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
		_lvl_card.offset_left = -330
		_lvl_card.offset_right = -20
		_lvl_card.offset_top = -40
		_lvl_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_lvl_card)
		_lvl_card.add_child(VBoxContainer.new())
	var v: VBoxContainer = _lvl_card.get_child(0)
	for c in v.get_children():
		c.queue_free()
	_label(v, I18n.t("LEVEL UP -- %s") % str(info.get("label", "")), 17, Color(0.7, 1.0, 0.7))
	for r in info.get("rows", []):
		if str(r[2]) != "":
			_label(v, "%s  %s" % [r[0], r[2]], 13, Color(0.92, 0.95, 0.9))
	_label(v, I18n.t("+%d attribute point -- %d to spend (P)") % [int(info.get("gained", 1)), Game.attr_points_free()], 13, Color(1.0, 0.9, 0.55))
	var was_shown := _lvl_card.visible and _lvl_card.modulate.a > 0.5
	_lvl_card.visible = true
	_lvl_card.modulate.a = 1.0
	if not was_shown:
		UI.nudge_in(_lvl_card, Vector2(48, 0))         # round 50: slides in from the side
	if _lvl_tw:
		_lvl_tw.kill()
	_lvl_tw = create_tween()
	_lvl_tw.tween_interval(6.0)
	_lvl_tw.tween_property(_lvl_card, "modulate:a", 0.0, 1.0)
	_lvl_tw.tween_callback(func(): _lvl_card.visible = false)



# ---- round 36: who you are (character creation) -------------------------------------
# A name, a look, a past, seven questions -- every answer weighs on where your
# attributes start and how many free points you'll have (Game.creation_tally),
# and a last page shows it all before you set out.

var _create: PanelContainer
var _cr_title: Label
var _cr_body: VBoxContainer
var _cr := {}


func start_creation() -> void:
	if not Game.needs_creation():
		return
	if _create == null:
		_create = PanelContainer.new()
		_create.add_theme_stylebox_override("panel", _box(Color(0.04, 0.035, 0.05, 0.97), Color(0.85, 0.7, 0.4)))
		_create.set_anchors_preset(Control.PRESET_FULL_RECT)
		_create.offset_left = 60
		_create.offset_right = -60
		_create.offset_top = 40
		_create.offset_bottom = -40
		_create.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(_create)
		var sc := ScrollContainer.new()
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		_create.add_child(sc)
		var v := VBoxContainer.new()
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_theme_constant_override("separation", 10)
		sc.add_child(v)
		_cr_title = _label(v, "", 30, Color(1.0, 0.85, 0.5))
		_cr_body = VBoxContainer.new()
		_cr_body.add_theme_constant_override("separation", 8)
		v.add_child(_cr_body)
	var sex := "m"
	_cr = {"steps": _cr_steps(), "i": 0, "name": Game.char_name, "look": {"sex": sex, "skin": 0, "hair": "topknot", "hair_color": [0.08, 0.07, 0.07], "beard": false}, "answers": {}}
	if not Game.look.is_empty():
		_cr["look"] = Game.look.duplicate(true)
	_create.visible = true
	_dialog.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_cr_show()


func _cr_steps() -> Array:
	var st := ["intro", "name", "look"]
	if Game.needs_background():
		st.append("past")
	for q in Game.creation_data().get("questions", []):
		st.append("q:" + str(q.get("id", "")))
	st.append("summary")
	return st


func _cr_go(d: int) -> void:
	_cr["i"] = clampi(int(_cr["i"]) + d, 0, (_cr["steps"] as Array).size() - 1)
	Game.sfx("page", 0.4)
	_cr_show()


func _cr_clear() -> void:
	for c in _cr_body.get_children():
		c.queue_free()


func _cr_nav(back: bool = true, next_text: String = "") -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_cr_body.add_child(row)
	if back and int(_cr["i"]) > 0:
		_button(row, "Back", _cr_go.bind(-1))
	if next_text != "":
		_button(row, next_text, _cr_go.bind(1))
	var st: Array = _cr["steps"]
	_label(row, "   %d / %d" % [int(_cr["i"]) + 1, st.size()], 13, Color(0.6, 0.6, 0.65))


func _cr_show() -> void:
	_cr_clear()
	var st: Array = _cr["steps"]
	var step := str(st[int(_cr["i"])])
	if step == "intro":
		_cr_title.text = I18n.t("Who are you?")
		var t := "Before Eliet, before the shaft, before the road -- someone was here already. You.\n\nA few questions. There are no wrong answers: every one is worth the same, as a strength you start with or a point you keep to spend. But who you say you are is who you'll start as."
		if not Game.needs_background():
			t += I18n.t("\n\n(Your journey began before these questions existed. Nothing you've earned is taken away; this only adds.)")
		_wrap(_label(_cr_body, t, 16, Color(0.9, 0.9, 0.88)))
		_cr_nav(false, "Begin")
		# round 62: or straight in -- the answers chosen for you (they're in your journal)
		var qs := _button(_cr_body, "Quick start -- straight to Eliet (a fighter's past, the answers chosen for you)", _cr_quick)
		qs.alignment = HORIZONTAL_ALIGNMENT_LEFT
	elif step == "name":
		_cr_title.text = I18n.t("What are you called?")
		var le := LineEdit.new()
		le.placeholder_text = "your name"
		le.text = str(_cr.get("name", ""))
		le.max_length = 24
		le.custom_minimum_size = Vector2(320, 40)
		le.text_changed.connect(func(tx): _cr["name"] = tx)
		le.text_submitted.connect(func(_tx): _cr_go(1))
		_cr_body.add_child(le)
		le.grab_focus.call_deferred()
		_wrap(_label(_cr_body, I18n.t("(Leave it empty and the road will name you.)"), 13, Color(0.65, 0.65, 0.7)))
		_cr_nav(true, "Next")
	elif step == "look":
		_cr_title.text = I18n.t("What do people see?")
		var L: Dictionary = Game.creation_data().get("look", {})
		for k in ["sex", "skin", "hair", "hair_color", "beard"]:
			if k == "beard" and str(_cr["look"].get("sex", "m")) == "f":
				continue
			var opts: Array = L.get(k, [])
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 8)
			_cr_body.add_child(row)
			var lab := _label(row, {"sex": I18n.t("Body"), "skin": I18n.t("Skin"), "hair": I18n.t("Hair"), "hair_color": I18n.t("Hair colour"), "beard": I18n.t("Face")}[k], 15, Color(0.95, 0.8, 0.5))
			lab.custom_minimum_size = Vector2(130, 0)
			for o in opts:
				var val = o[0]
				var b := _button(row, str(o[1]), func():
					_cr["look"][k] = val
					_cr_show())
				if str(_cr["look"].get(k, "")) == str(val):
					b.modulate = Color(1.0, 0.85, 0.5)
		_wrap(_label(_cr_body, I18n.t("(You'll see yourself when you step out.)"), 13, Color(0.65, 0.65, 0.7)))
		_cr_nav(true, "Next")
	elif step == "past":
		_cr_title.text = I18n.t("Who were you, before the road?")
		_wrap(_label(_cr_body, I18n.t("Everyone who lives long enough to leave home can throw a punch and find water: you start an Apprentice at Unarmed and Survival. Your past gives you ONE more thing you're good at, and a little to carry."), 14, Color(0.85, 0.85, 0.85)))
		for grp in [["craft", "Someone who made things"], ["gather", "Someone who found things"], ["weapon", "Someone who fought"]]:
			_label(_cr_body, str(grp[1]), 16, Color(0.95, 0.8, 0.5))
			for bid in Game.BACKGROUNDS:
				var bg: Dictionary = Game.BACKGROUNDS[bid]
				if str(bg["group"]) != str(grp[0]):
					continue
				var b2 := _button(_cr_body, "%s (%s) -- %s" % [bg["name"], Game.skill_name(str(bg["skill"])), bg["desc"]], func():
					_cr["past"] = str(bid)
					_cr_go(1))
				b2.alignment = HORIZONTAL_ALIGNMENT_LEFT
				if str(_cr.get("past", "")) == str(bid):
					b2.modulate = Color(1.0, 0.85, 0.5)
		_cr_nav(true, "")
	elif step.begins_with("q:"):
		var qid := step.trim_prefix("q:")
		var q: Dictionary = {}
		for qq in Game.creation_data().get("questions", []):
			if str(qq.get("id", "")) == qid:
				q = qq
		_cr_title.text = str(q.get("ask", ""))
		var ans: Array = q.get("answers", [])
		for i in ans.size():
			var a: Dictionary = ans[i]
			var hint3 := Game.answer_hint(a)        # round 62: what each answer gives
			var b3 := _button(_cr_body, str(a.get("text", "")) + ("     (%s)" % hint3 if hint3 != "" else ""), func():
				_cr["answers"][qid] = i
				_cr_go(1))
			b3.alignment = HORIZONTAL_ALIGNMENT_LEFT
			if int(_cr["answers"].get(qid, -1)) == i:
				b3.modulate = Color(1.0, 0.85, 0.5)
		_wrap(_label(_cr_body, _cr_tally_text(), 13, Color(0.7, 0.85, 0.7)))
		_cr_nav(true, "")
	elif step == "summary":
		_cr_title.text = I18n.t("This is who you are")
		var t2 := Game.creation_tally(_cr["answers"])
		var A: Dictionary = Game.char_data().get("attributes", {})
		var nm := str(_cr.get("name", "")).strip_edges()
		var lines := ["%s%s." % [nm if nm != "" else I18n.t("Someone the road will name"), (", once a " + str(Game.BACKGROUNDS.get(str(_cr.get("past", Game.background)), {}).get("name", ""))) if str(_cr.get("past", Game.background)) != "" else ""]]
		lines.append("")
		for id in Game.attr_ids():
			lines.append("%s %d -- %s" % [A.get(id, {}).get("name", id), int(t2["attrs"].get(id, 0)), A.get(id, {}).get("desc", "")])
		lines.append("")
		lines.append(I18n.t("Free points to spend: %d (and you'll earn more: every step of cultivation, every realm, every chapter, every master).") % int(t2["free"]))
		for q in Game.creation_data().get("questions", []):
			var qi := int(_cr["answers"].get(str(q.get("id", "")), -1))
			if qi >= 0 and str(q["answers"][qi].get("note", "")) != "":
				lines.append("  · " + str(q["answers"][qi]["note"]))
		var missing := []
		for s2 in _cr["steps"]:
			if str(s2).begins_with("q:") and not _cr["answers"].has(str(s2).trim_prefix("q:")):
				missing.append(str(s2))
		if Game.needs_background() and str(_cr.get("past", "")) == "":
			missing.append("past")
		_wrap(_label(_cr_body, "\n".join(lines), 15, Color(0.92, 0.92, 0.88)))
		var row2 := HBoxContainer.new()
		row2.add_theme_constant_override("separation", 12)
		_cr_body.add_child(row2)
		if missing.is_empty():
			_button(row2, "This is who I am", _cr_finish)
		else:
			_label(row2, I18n.t("(Some questions are still unanswered -- go back.)"), 14, Color(1.0, 0.6, 0.5))
		_button(row2, "Back", _cr_go.bind(-1))
		_button(row2, "Start the questions again", func():
			_cr["answers"] = {}
			_cr["i"] = 0
			_cr_show())


func _cr_tally_text() -> String:
	var t := Game.creation_tally(_cr["answers"])
	var parts := []
	for id in Game.attr_ids():
		parts.append("%s %d" % [str(Game.char_data().get("attributes", {}).get(id, {}).get("name", id)), int(t["attrs"].get(id, 0))])
	return I18n.t("So far: %s, %d free") % [", ".join(parts), int(t["free"])]


func _cr_quick() -> void:
	## round 62 (Robert: "a first hour that hooks"): twelve screens before the
	## first step is a lot -- this picks a past that fights, answers the
	## questions, spends the points evenly, and puts you in the village
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	if Game.needs_background():
		var fighters := []
		for bid in Game.BACKGROUNDS:
			if str(Game.BACKGROUNDS[bid].get("group", "")) == "weapon":
				fighters.append(str(bid))
		_cr["past"] = fighters[rng.randi() % fighters.size()] if not fighters.is_empty() else "wanderer"
	for q in Game.creation_data().get("questions", []):
		var n: int = (q.get("answers", []) as Array).size()
		if n > 0:
			_cr["answers"][str(q.get("id", ""))] = rng.randi() % n
	_cr["quick"] = true
	_cr_finish()


func _cr_finish() -> void:
	if Game.needs_background():
		Game.choose_background(str(_cr.get("past", "wanderer")))
	var old_look := Game.look.duplicate()
	Game.creation_finish(str(_cr.get("name", "")), _cr["look"], _cr["answers"])
	_create.visible = false
	var pl = get_tree().get_first_node_in_group("player")
	if pl and pl.has_method("rebuild_model") and (str(old_look.get("sex", "m")) != str(Game.look.get("sex", "m")) or int(old_look.get("skin", 0)) != int(Game.look.get("skin", 0))):
		pl.rebuild_model()
	Game.message.emit("%s sets out." % Game.char_name)
	if bool(_cr.get("quick", false)):
		var ids: Array = Game.attr_ids()
		var k := 0
		while Game.attr_points_free() > 0 and k < 200:
			Game.attr_spend(str(ids[k % ids.size()]))
			k += 1
		Game.set_flag("quick_start")
		Game.message.emit(I18n.t("Quick start: you're %s, once a %s. Your answers and your points are on your character page (P).") % [Game.char_name, str(Game.BACKGROUNDS.get(Game.background, {}).get("name", "wanderer")).to_lower()])
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif Game.attr_points_free() > 0:
		open_character()
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func update_clock() -> void:
	## round 44: "Day 3 of Thaw, Year 1 · Dusk · Rain"
	if _clock == null:
		return
	var W = Game.sys("world")
	_clock.text = W.summary() if W else ""
	var FR = Game.sys("floorrun")
	if FR and FR.streak > 0:
		_clock.text += "   ·   " + FR.streak_text()          # round 61
	_clock.visible = _clock.text != ""
