extends VBoxContainer
## Round 188: the Guild page (menu > Guild, F6): the group chat, your guild (join one or found your own), help and
## trades, the week's guild tasks and renown, and your own sect (found it, its disciples, its hall).
## Fellowship.gd and OwnSect.gd hold the state; this only shows it and passes your choices on.

const TABS := ["Chat", "Guild", "Support", "Tasks", "Sect"]
const ACC := Color(0.95, 0.75, 0.45)
var hub
var hud
var tab := "Chat"
var chan := ""                     # "" all, "guild", "sect"
var _tabbar: KeepRow
var _status: Label
var _bodies := {}                  # tab -> Control
var _lists := {}                   # tab -> VBoxContainer (the scrolled column)
var _feed: RichTextLabel
var _in: LineEdit
var _offers: HFlowContainer
var _form := {}                    # what you typed in a form survives a refresh
var _confirm := ""                 # a destructive button needs a second press


class KeepRow extends HBoxContainer:
	## (a row of this page's own: Hub._fit never takes it apart -- the page holds on to it)
	pass


func setup(h) -> void:
	hub = h
	hud = h.hud
	name = "GuildPage"
	add_theme_constant_override("separation", 8)
	_status = hud._label(self, "", 15, Color(0.9, 0.88, 0.8))
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tabbar = KeepRow.new()
	_tabbar.add_theme_constant_override("separation", 6)
	add_child(_tabbar)
	var grp := ButtonGroup.new()
	for t in TABS:
		var b := Button.new()
		b.name = t
		b.text = I18n.t(t)
		b.toggle_mode = true
		b.button_group = grp
		b.theme_type_variation = "RailButton"
		b.add_theme_font_size_override("font_size", 15)
		b.add_theme_color_override("font_pressed_color", ACC)
		b.custom_minimum_size = Vector2(0, 30)
		b.pressed.connect(func(): open_tab(t))
		_tabbar.add_child(b)
	# the chat: a feed that fills the page, a line to type in
	var chat := VBoxContainer.new()
	chat.size_flags_vertical = Control.SIZE_EXPAND_FILL
	chat.add_theme_constant_override("separation", 6)
	add_child(chat)
	_bodies["Chat"] = chat
	var chrow := KeepRow.new()
	chrow.add_theme_constant_override("separation", 6)
	chat.add_child(chrow)
	for c in [["", "All"], ["guild", "Guild"], ["sect", "Sect"]]:
		var cb := Button.new()
		cb.text = I18n.t(str(c[1]))
		cb.add_theme_font_size_override("font_size", 13)
		var cc: String = c[0]
		cb.pressed.connect(func():
			chan = cc
			rebuild_feed())
		chrow.add_child(cb)
	_feed = RichTextLabel.new()
	_feed.bbcode_enabled = true
	_feed.scroll_following = true
	_feed.selection_enabled = true
	_feed.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_feed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_feed.custom_minimum_size = Vector2(0, 220)
	_feed.add_theme_font_size_override("normal_font_size", 15)
	_feed.add_theme_font_size_override("italics_font_size", 14)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.03, 0.035, 0.05, 0.7)
	bg.set_corner_radius_all(6)
	bg.set_content_margin_all(10)
	_feed.add_theme_stylebox_override("normal", bg)
	chat.add_child(_feed)
	_offers = HFlowContainer.new()
	_offers.add_theme_constant_override("h_separation", 6)
	chat.add_child(_offers)
	var irow := KeepRow.new()
	irow.add_theme_constant_override("separation", 6)
	chat.add_child(irow)
	_in = LineEdit.new()
	_in.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_in.custom_minimum_size = Vector2(300, 34)
	_in.max_length = 200
	_in.placeholder_text = I18n.t("Say something to the guild...")
	_in.text_submitted.connect(func(_t): _send())
	irow.add_child(_in)
	var sb := Button.new()
	sb.text = I18n.t("Send")
	sb.custom_minimum_size = Vector2(80, 34)
	sb.pressed.connect(_send)
	irow.add_child(sb)
	for t in TABS:
		if t == "Chat":
			continue
		var sc := ScrollContainer.new()
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
		add_child(sc)
		var v := VBoxContainer.new()
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_theme_constant_override("separation", 8)
		sc.add_child(v)
		_bodies[t] = sc
		_lists[t] = v
	var FS = Game.sys("fellowship")
	if FS != null:
		FS.chat_added.connect(_on_line)
	open_tab("Chat" if FS != null and FS.in_guild() else "Guild")


func open_tab(t: String) -> void:
	tab = t
	for k in _bodies:
		(_bodies[k] as Control).visible = (k == t)
	for b in _tabbar.get_children():
		(b as Button).set_pressed_no_signal(b.name == t)
	refresh()
	if t == "Chat" and is_visible_in_tree():
		_in.grab_focus.call_deferred()


func refresh() -> void:
	var FS = Game.sys("fellowship")
	var OS_ = Game.sys("own_sect")
	if FS == null:
		return
	var s := ""
	if FS.in_guild():
		s = "%s %s  ·  %s %d  ·  %s %d" % [FS.badge(), str(FS.g["name"]), I18n.t("renown"), FS.renown, I18n.t("level"), FS.guild_level()]
		if FS.title_text() != "":
			s += "  ·  " + I18n.t("title: %s") % FS.title_text()
	else:
		s = I18n.t("You belong to no guild yet -- join one or found your own (Guild tab).")
	if OS_ != null and OS_.founded():
		s += "\n" + I18n.t("Master of the %s (hall %d, %d disciples)") % [str(OS_.sect["name"]), int(OS_.sect.get("hall", 1)), OS_.disciples.size()]
	if Game.online != null and Game.online.has_method("is_connected_ok") and Game.online.is_connected_ok():
		s += "  ·  " + I18n.t("online: real players in your guild share this chat")
	_status.text = s
	match tab:
		"Chat":
			rebuild_feed()
		"Guild":
			_fill_guild()
		"Support":
			_fill_help()
		"Tasks":
			_fill_tasks()
		"Sect":
			_fill_sect()


# ---- chat --------------------------------------------------------------------------------------------------------

static func esc(t: String) -> String:
	return t.replace("[", "[lb]")


func line_bb(l: Dictionary) -> String:
	var who := str(l.get("who", ""))
	var text := esc(str(l.get("text", "")))
	var ch := str(l.get("ch", "guild"))
	match str(l.get("kind", "line")):
		"sys":
			return "[i][color=#9aa3b5]%s[/color][/i]" % text
		"sect":
			return "[color=#7fe0c8]%s[/color]" % text
		"gift":
			return "[color=#ffd27a]%s[/color]" % text
		"trade":
			return "[color=#ffd27a]%s[/color]" % text
		"you":
			return "[color=#a8d8ff][b]%s[/b][/color]: %s" % [esc(who), text]
		"online":
			return "[color=#9cff9c]● %s[/color]: %s" % [esc(who), text]
	if ch == "sect":
		return "[color=#7fe0c8]%s[/color]" % text
	var hue := float(abs(hash(who)) % 360) / 360.0
	var col := Color.from_hsv(hue, 0.45, 1.0)
	return "[color=#%s][b]%s[/b][/color]: %s" % [col.to_html(false), esc(who), text]


func rebuild_feed() -> void:
	var FS = Game.sys("fellowship")
	if FS == null or _feed == null:
		return
	_feed.clear()
	var ls: Array = FS.lines(chan, 80)
	if ls.is_empty():
		_feed.append_text("[i][color=#9aa3b5]%s[/color][/i]" % esc(I18n.t("Nothing here yet. Join a guild or found your own, and the chat comes alive.")))
	for l in ls:
		_feed.append_text(line_bb(l) + "\n")
	FS.unread = 0
	_fill_offers()


func _on_line(l: Dictionary) -> void:
	if not is_visible_in_tree() or tab != "Chat":
		return
	if chan != "" and str(l.get("ch", "")) != chan and str(l.get("ch", "")) != "sys":
		return
	_feed.append_text(line_bb(l) + "\n")
	Game.sys("fellowship").unread = 0
	if str(l.get("kind", "")) == "trade":
		_fill_offers()


func _fill_offers() -> void:
	for c in _offers.get_children():
		c.queue_free()
	var FS = Game.sys("fellowship")
	for tr in FS.trades:
		var lb := Label.new()
		lb.text = I18n.t("%s offers %d × %s for your %d × %s") % [tr["who"], int(tr["get"][1]), Game.item_name(str(tr["get"][0])), int(tr["give"][1]), Game.item_name(str(tr["give"][0]))]
		lb.add_theme_font_size_override("font_size", 13)
		lb.add_theme_color_override("font_color", Color(1.0, 0.85, 0.5))
		_offers.add_child(lb)
		var tid := int(tr["id"])
		hub._btn(_offers, I18n.t("Accept"), func(): _say(FS.accept_trade(tid)))
		hub._btn(_offers, I18n.t("No thanks"), func():
			FS.decline_trade(tid)
			refresh())


func _send() -> void:
	var t := _in.text.strip_edges()
	_in.text = ""
	if t == "":
		return
	var FS = Game.sys("fellowship")
	if not FS.in_guild():
		Game.message.emit(I18n.t("Join or found a guild first -- then the chat is yours."))
		return
	FS.say(t)
	_in.grab_focus.call_deferred()


func _say(t: String) -> void:
	if t != "":
		Game.message.emit(t)
	refresh()


func _keep(key: String, le: LineEdit, ph: String, maxlen: int) -> LineEdit:
	le.placeholder_text = ph
	le.max_length = maxlen
	le.text = str(_form.get(key, ""))
	le.custom_minimum_size = Vector2(240, 32)
	le.text_changed.connect(func(t): _form[key] = t)
	return le


func _two(key: String) -> bool:
	## a destructive button: the first press arms it, the second does it
	if _confirm == key:
		_confirm = ""
		return true
	_confirm = key
	Game.message.emit(I18n.t("Press again to confirm."))
	return false


# ---- guild -------------------------------------------------------------------------------------------------------

func _fill_guild() -> void:
	var box: VBoxContainer = _lists["Guild"]
	hub._clear(box)
	var FS = Game.sys("fellowship")
	if FS.in_guild():
		var c = hub._card(box, FS.crest_color())
		hub._h(c, "%s %s" % [FS.badge(), str(FS.g["name"])], FS.crest_color(), 20)
		if str(FS.g.get("motto", "")) != "":
			hub._p(c, "\"%s\"" % I18n.t(str(FS.g["motto"])), Color(0.8, 0.8, 0.85), 14)
		hub._p(c, I18n.t("Level %d  ·  %d of %d members  ·  renown %d") % [FS.guild_level(), (FS.g.get("members", []) as Array).size(), FS.member_cap(), FS.renown], Color(0.7, 0.74, 0.82), 13)
		if str(FS.g.get("kind", "")) == "own":
			hub._p(c, I18n.t("Join key for friends online: %s") % str(FS.g.get("key", "")), Color(0.6, 0.9, 0.7), 13)
		hub._h(box, I18n.t("Members"), ACC, 18)
		for m in FS.g.get("members", []):
			var r = hub._row(box)
			var pn := I18n.t(str(FS.data.get("persona_names", {}).get(str(m.get("persona", "")), "")))
			var rn := I18n.t(str(FS.data.get("persona_names", {}).get(str(m.get("role", "")), "")))
			hud._label(r, "%s  —  %s, %s  ·  %s" % [str(m["name"]), rn, pn, Game.realm_info(int(m.get("realm", 0)))["name"]], 14, Color(0.88, 0.9, 0.95))
			if str(FS.g.get("kind", "")) == "own" and str(m.get("role", "")) != "officer":
				var nm := str(m["name"])
				hub._btn(r, I18n.t("Let go"), func():
					if _two("dismiss:" + nm):
						_say(FS.dismiss(nm)))
		if str(FS.g.get("kind", "")) == "own":
			hub._h(box, I18n.t("Answered the notice today"), ACC, 18)
			var rc: Array = FS.recruits()
			if rc.is_empty():
				hub._p(box, I18n.t("No one today. Come back tomorrow."), Color(0.7, 0.72, 0.78), 13)
			for cand in rc:
				var r2 = hub._row(box)
				hud._label(r2, "%s  —  %s" % [str(cand["name"]), I18n.t(str(FS.data.get("persona_names", {}).get(str(cand["persona"]), "")))], 14, Color(0.85, 0.9, 0.85))
				var cn := str(cand["name"])
				hub._btn(r2, I18n.t("Take them on"), func(): _say(FS.recruit(cn)), (FS.g.get("members", []) as Array).size() >= FS.member_cap())
		hub._btn(box, I18n.t("Leave the guild"), func():
			if _two("leave_guild"):
				_say(FS.leave()))
		return
	hub._h(box, I18n.t("Join a guild"), ACC, 20)
	hub._p(box, I18n.t("A guild is company: a chat that talks back, tips from those who've been there, a few spare materials now and then, fair swaps, errands at shop prices, and weekly goals that pay in looks. Never power -- your strength is your own."), Color(0.75, 0.78, 0.85), 13)
	for d in FS.guild_defs():
		var col := Color(float(d["color"][0]), float(d["color"][1]), float(d["color"][2]))
		var c2 = hub._card(box, col)
		hub._h(c2, "[%s] %s" % [str(d["tag"]), I18n.t(str(d["name"]))], col, 18)
		hub._p(c2, "\"%s\"  %s" % [I18n.t(str(d["motto"])), I18n.t(str(d["about"]))], Color(0.82, 0.84, 0.9), 13)
		var gid := str(d["id"])
		hub._btn(c2, I18n.t("Join"), func():
			_say(FS.join(gid))
			open_tab("Chat"), FS.join_check(gid) != "", FS.join_check(gid))
	hub._h(box, I18n.t("Found your own guild"), ACC, 20)
	var c3 = hub._card(box, ACC)
	hub._p(c3, I18n.t("Your name over the door, your tag beside your name, your colours. Three founders answer the call; more come as the guild earns renown. Costs %d gold.") % int(FS.lim("found_guild_gold", 500)), Color(0.8, 0.82, 0.88), 13)
	var r3 = hub._row(c3)
	var nm_e := _keep("g_name", LineEdit.new(), I18n.t("Guild name"), 28)
	r3.add_child(nm_e)
	var tag_e := _keep("g_tag", LineEdit.new(), I18n.t("Tag (2-4)"), 4)
	tag_e.custom_minimum_size = Vector2(90, 32)
	r3.add_child(tag_e)
	var r4 = hub._row(c3)
	var mo_e := _keep("g_motto", LineEdit.new(), I18n.t("Motto (optional)"), 80)
	mo_e.custom_minimum_size = Vector2(340, 32)
	r4.add_child(mo_e)
	var colb := OptionButton.new()
	for cn2 in Game.sys("own_sect").cfg("color_names", ["golden"]):
		colb.add_item(I18n.t(str(cn2)))
	colb.selected = int(_form.get("g_color", 0))
	colb.item_selected.connect(func(i): _form["g_color"] = i)
	r4.add_child(colb)
	hub._btn(c3, I18n.t("Found the guild (%d gold)") % int(FS.lim("found_guild_gold", 500)), func():
		var res: String = FS.found(str(_form.get("g_name", "")), str(_form.get("g_tag", "")), str(_form.get("g_motto", "")), int(_form.get("g_color", 0)))
		if FS.in_guild():
			_form.clear()
			_say(res)
			open_tab("Chat")
		else:
			_say(res))


# ---- help and trades ---------------------------------------------------------------------------------------------

func _fill_help() -> void:
	var box: VBoxContainer = _lists["Support"]
	hub._clear(box)
	var FS = Game.sys("fellowship")
	if not FS.in_guild():
		hub._p(box, I18n.t("Join or found a guild first."), Color(0.8, 0.8, 0.85), 14)
		return
	hub._h(box, I18n.t("Ask the guild"), ACC, 20)
	hub._p(box, I18n.t("A guildmate fetches up to %d of a material you've already found (worth up to %d each at your realm). You pay what a shop would; it arrives in a few minutes. Up to %d asks at a time.") % [int(FS.lim("request_qty_max", 10)), FS.item_value_cap(), int(FS.lim("request_open_max", 3))], Color(0.75, 0.78, 0.85), 13)
	var pool: Array = FS.allowed_items()
	if pool.is_empty():
		hub._p(box, I18n.t("Nothing you've found yet. Gather something first."), Color(0.7, 0.72, 0.78), 13)
	else:
		var r = hub._row(box)
		var ob := OptionButton.new()
		for id in pool:
			ob.add_item("%s (%s %d)" % [Game.item_name(str(id)), I18n.t("have"), Game.count(str(id))])
		var pick := clampi(int(_form.get("req_i", 0)), 0, pool.size() - 1)
		ob.selected = pick
		r.add_child(ob)
		var sp := SpinBox.new()
		sp.min_value = 1
		sp.max_value = int(FS.lim("request_qty_max", 10))
		sp.value = int(_form.get("req_n", 5))
		r.add_child(sp)
		var price := Label.new()
		price.add_theme_font_size_override("font_size", 13)
		r.add_child(price)
		var upd := func():
			price.text = I18n.t("%d gold") % FS.request_price(str(pool[ob.selected]), int(sp.value))
		ob.item_selected.connect(func(i):
			_form["req_i"] = i
			upd.call())
		sp.value_changed.connect(func(v):
			_form["req_n"] = int(v)
			upd.call())
		upd.call()
		hub._btn(r, I18n.t("Ask"), func(): _say(FS.request(str(pool[ob.selected]), int(sp.value))))
	if FS.requests.size() > 0:
		hub._h(box, I18n.t("On the way"), ACC, 18)
		for q in FS.requests:
			var mins := maxi(0, int(ceil((float(q["due"]) - FS.now()) / 60.0)))
			hub._p(box, I18n.t("%s: %d × %s -- about %d min") % [q["who"], int(q["n"]), Game.item_name(str(q["item"])), mins], Color(0.85, 0.85, 0.75), 13)
	hub._h(box, I18n.t("Swaps"), ACC, 18)
	if FS.trades.is_empty():
		hub._p(box, I18n.t("No offers right now. Guildmates offer swaps when you carry plenty of one thing and little of another -- always at the shops' own prices."), Color(0.7, 0.72, 0.78), 13)
	for tr in FS.trades:
		var r2 = hub._row(box)
		hud._label(r2, I18n.t("%s: %d × %s for your %d × %s") % [tr["who"], int(tr["get"][1]), Game.item_name(str(tr["get"][0])), int(tr["give"][1]), Game.item_name(str(tr["give"][0]))], 14, Color(1.0, 0.88, 0.6))
		var tid := int(tr["id"])
		hub._btn(r2, I18n.t("Accept"), func(): _say(FS.accept_trade(tid)))
		hub._btn(r2, I18n.t("No thanks"), func():
			FS.decline_trade(tid)
			refresh())
	hub._h(box, I18n.t("Gifts today"), ACC, 18)
	hub._p(box, I18n.t("Guildmates have sent %d of the %d gold-worth of spare materials a day brings at your realm.") % [FS.gift_value_today, FS.gift_cap()], Color(0.7, 0.72, 0.78), 13)


# ---- tasks and renown --------------------------------------------------------------------------------------------

func _fill_tasks() -> void:
	var box: VBoxContainer = _lists["Tasks"]
	hub._clear(box)
	var FS = Game.sys("fellowship")
	if FS.in_guild():
		hub._h(box, I18n.t("This week's guild tasks"), ACC, 20)
		hub._p(box, I18n.t("What you do counts, and so does what your guildmates do. Each finished task pays the guild renown. New tasks every Monday."), Color(0.75, 0.78, 0.85), 13)
		for t in FS.tasks:
			var c = hub._card(box, Color(0.5, 0.9, 0.6) if bool(t.get("done", false)) else ACC)
			hub._p(c, "%s%s  (+%d %s)" % ["✔ " if bool(t.get("done", false)) else "", str(t["text"]), int(t["renown"]), I18n.t("renown")], Color(0.9, 0.9, 0.85), 14)
			var r = hub._row(c)
			hub._bar(r, float(t["have"]), float(t["goal"]), Color(0.5, 0.85, 1.0), 260.0)
			hud._label(r, "%d / %d" % [int(t["have"]), int(t["goal"])], 13, Color(0.75, 0.8, 0.9))
	hub._h(box, I18n.t("Renown: %d") % FS.renown, ACC, 20)
	hub._p(box, I18n.t("Renown buys looks only -- a title by your name, your crest's colour and emblem, dressing for your sect hall."), Color(0.75, 0.78, 0.85), 13)
	for s in FS.shop():
		if not FS.can_have(s) and int(s.get("cost", 0)) == 0:
			continue
		var r2 = hub._row(box)
		var own: bool = FS.owned.has(str(s["id"]))
		var on: bool = str(s["id"]) in [FS.title, FS.crest, FS.emblem]
		var nm := I18n.t(str(s["name"]))
		if s.has("glyph"):
			nm = str(s["glyph"]) + " " + nm
		hud._label(r2, "%s  —  %s" % [nm, I18n.t("owned") if own else (I18n.t("%d renown") % int(s.get("cost", 0)))], 14,
			Color(float(s["color"][0]), float(s["color"][1]), float(s["color"][2])) if s.has("color") else Color(0.88, 0.9, 0.95))
		var sid := str(s["id"])
		if str(s.get("kind", "")) == "hall":
			if not own:
				hub._btn(r2, I18n.t("Buy"), func(): _say(FS.buy(sid)), FS.renown < int(s.get("cost", 0)))
		elif own or int(s.get("cost", 0)) == 0:
			hub._btn(r2, I18n.t("Take off") if on else I18n.t("Use"), func(): _say(FS.use(sid)))
		else:
			hub._btn(r2, I18n.t("Buy"), func(): _say(FS.buy(sid)), FS.renown < int(s.get("cost", 0)))


# ---- your sect ---------------------------------------------------------------------------------------------------

func _fill_sect() -> void:
	var box: VBoxContainer = _lists["Sect"]
	hub._clear(box)
	var OS_ = Game.sys("own_sect")
	if OS_ == null:
		return
	if not OS_.founded():
		hub._h(box, I18n.t("Found your own sect"), ACC, 20)
		hub._p(box, I18n.t("The Empty Seat -- an old walled compound in the valley, south of the river by the north road -- has waited a long time for a master. Found a sect there: name it, choose its element and colours, and teach up to three of your own arts. Disciples come to the gate every day; they grow, train in the yard and talk in the sect chat."), Color(0.78, 0.8, 0.86), 13)
		var why: String = OS_.found_check()
		hub._p(box, I18n.t("It takes %s and %d gold, and no other sect.") % [Game.realm_info(int(OS_.cfg("found_realm", 3)))["name"], int(OS_.cfg("found_gold", 3000))], Color(0.95, 0.85, 0.6), 14)
		if why != "":
			hub._p(box, why, Color(1.0, 0.65, 0.55), 13)
		var c = hub._card(box, ACC)
		var r = hub._row(c)
		r.add_child(_keep("s_name", LineEdit.new(), I18n.t("Sect name"), 32))
		var elb := OptionButton.new()
		var els: Array = OS_.cfg("elements", ["earth"])
		for e in els:
			elb.add_item(I18n.t(str(e)))
		elb.selected = int(_form.get("s_el", 0))
		elb.item_selected.connect(func(i): _form["s_el"] = i)
		r.add_child(elb)
		var colb := OptionButton.new()
		for cn in OS_.cfg("color_names", ["golden"]):
			colb.add_item(I18n.t(str(cn)))
		colb.selected = int(_form.get("s_col", 0))
		colb.item_selected.connect(func(i): _form["s_col"] = i)
		r.add_child(colb)
		var r2 = hub._row(c)
		var crb := OptionButton.new()
		var creeds: Array = OS_.cfg("creeds", [""])
		for cr in creeds:
			crb.add_item(I18n.t(str(cr)))
		crb.selected = int(_form.get("s_creed", 0))
		crb.item_selected.connect(func(i): _form["s_creed"] = i)
		r2.add_child(crb)
		hub._p(c, I18n.t("Arts to teach (up to three of yours):"), Color(0.8, 0.85, 0.95), 13)
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 8)
		c.add_child(flow)
		var picked: Array = _form.get("s_arts", [])
		for aid in OS_.teachable_arts():
			var cb := CheckBox.new()
			cb.text = OS_.art_name(str(aid))
			cb.button_pressed = str(aid) in picked
			var a2 := str(aid)
			cb.toggled.connect(func(on):
				var p: Array = _form.get("s_arts", [])
				if on and not a2 in p and p.size() < 3:
					p.append(a2)
				elif not on:
					p.erase(a2)
				_form["s_arts"] = p
				if on and not a2 in p:
					cb.set_pressed_no_signal(false))
			flow.add_child(cb)
		hub._btn(c, I18n.t("Found the sect (%d gold)") % int(OS_.cfg("found_gold", 3000)), func():
			var res: String = OS_.found(str(_form.get("s_name", "")), str(els[clampi(int(_form.get("s_el", 0)), 0, els.size() - 1)]),
				int(_form.get("s_col", 0)), I18n.t(str(creeds[clampi(int(_form.get("s_creed", 0)), 0, creeds.size() - 1)])), _form.get("s_arts", []))
			if OS_.founded():
				_form.clear()
			_say(res), why != "")
		return
	var col := Color(float(OS_.sect["color"][0]), float(OS_.sect["color"][1]), float(OS_.sect["color"][2]))
	var hc = hub._card(box, col)
	hub._h(hc, str(OS_.sect["name"]), col, 22)
	hub._p(hc, I18n.t("A %s sect  ·  founded %s  ·  \"%s\"") % [I18n.t(str(OS_.sect["element"])), str(OS_.sect.get("since", "")), str(OS_.sect.get("creed", ""))], Color(0.8, 0.82, 0.88), 13)
	var arts := []
	for a in OS_.sect.get("arts", []):
		arts.append(OS_.art_name(str(a)))
	hub._p(hc, I18n.t("Arts taught: %s") % (", ".join(arts) if arts.size() > 0 else I18n.t("none yet")), Color(0.75, 0.85, 1.0), 13)
	var hall := int(OS_.sect.get("hall", 1))
	hub._p(hc, I18n.t("Hall level %d  ·  room for %d disciples  ·  sitting in it: x%.1f") % [hall, OS_.slots(), Game.SECT_HALL_AID], Color(0.85, 0.85, 0.75), 13)
	var mat: Dictionary = OS_.mature_effect()
	hub._p(hc, I18n.t("Matured: meditation x%.2f, the same as the top rank of any sect.") % float(mat["meditate_mult"]) if not mat.is_empty() else I18n.t("At hall level %d the sect matures (meditation x%.2f -- what the top rank of any sect gives).") % [int(OS_.cfg("mature_hall", 3)), float(OS_.cfg("mature_meditate_mult", 1.15))], Color(0.7, 0.9, 0.75), 13)
	var up: Dictionary = OS_.upgrade_cost()
	if not up.is_empty():
		hub._btn(hc, I18n.t("Raise the hall: %d gold + %d worth of %s materials") % [int(up.get("gold", 0)), int(up.get("material_value", 0)), I18n.t(str(OS_.sect["element"]))], func(): _say(OS_.upgrade()), OS_.upgrade_check() != "", OS_.upgrade_check())
	hub._h(box, I18n.t("Disciples (%d / %d)") % [OS_.disciples.size(), OS_.slots()], ACC, 18)
	for d in OS_.disciples:
		var c2 = hub._card(box, Color(0.5, 0.85, 0.8))
		var er: Dictionary = d.get("errand", {})
		hub._p(c2, "%s  %s  ·  %s, %s  ·  %s" % [str(d["name"]), "★".repeat(int(d["apt"])), I18n.t(str(d["el"])), I18n.t(str(d["trait"])), Game.realm_info(int(d["realm"]))["name"]], Color(0.9, 0.92, 0.95), 14)
		var r3 = hub._row(c2)
		hub._bar(r3, float(d["prog"]), 1.0, Color(0.5, 0.95, 0.85), 200.0)
		var cap_note := I18n.t("(as far as they can go below you)") if int(d["realm"]) >= OS_.realm_cap() else ""
		hud._label(r3, "%d%% %s" % [int(float(d["prog"]) * 100.0), cap_note], 12, Color(0.7, 0.75, 0.82))
		if not er.is_empty():
			hub._p(c2, I18n.t("Out on an errand for %s -- back in about %d min.") % [Game.item_name(str(er["item"])), maxi(0, int(ceil((float(er["due"]) - OS_.now()) / 60.0)))], Color(0.85, 0.8, 0.6), 12)
		var r4 = hub._row(c2)
		var nm := str(d["name"])
		hub._btn(r4, I18n.t("Teach"), func(): _say(OS_.teach(nm)), str(d.get("taught", "")) == Game.today() or not er.is_empty())
		hub._btn(r4, I18n.t("Encourage"), func(): _say(OS_.encourage(nm)), str(d.get("cheered", "")) == Game.today())
		hub._btn(r4, I18n.t("Send on an errand"), func(): _say(OS_.send_errand(nm)), not er.is_empty())
		hub._btn(r4, I18n.t("Dismiss"), func():
			if _two("disc:" + nm):
				_say(OS_.dismiss(nm)))
	hub._h(box, I18n.t("At the gate today"), ACC, 18)
	var cs: Array = OS_.candidates()
	if cs.is_empty():
		hub._p(box, I18n.t("No one waiting. New hopefuls come every day."), Color(0.7, 0.72, 0.78), 13)
	for cd in cs:
		var r5 = hub._row(box)
		hud._label(r5, "%s  %s  ·  %s, %s" % [str(cd["name"]), "★".repeat(int(cd["apt"])), I18n.t(str(cd["el"])), I18n.t(str(cd["trait"]))], 14, Color(0.85, 0.9, 0.85))
		var cn := str(cd["name"])
		hub._btn(r5, I18n.t("Take them in"), func(): _say(OS_.recruit(cn)), OS_.disciples.size() >= OS_.slots())
	hub._h(box, I18n.t("End the sect"), Color(0.9, 0.5, 0.5), 16)
	hub._btn(box, I18n.t("Disband (press twice)"), func():
		if _two("disband"):
			_say(OS_.disband()))
