extends Node3D
## What lives in an online place (round 125): in the hub the other players and the stands; in an arena the party,
## the server's foes, its telegraphed circles, and the fight's own HUD. Everything is drawn *from the state Online.gd keeps*,
## so it doesn't matter when a message arrived relative to this level loading.

const NetFoe := preload("res://scripts/net/NetFoe.gd")
const RemotePlayer := preload("res://scripts/net/RemotePlayer.gd")
const Menu := preload("res://scripts/net/OnlineMenu.gd")
const Pedestal := preload("res://scripts/net/Pedestal.gd")

const STANDS := [
	{"kind": "gates", "label": "Dungeon Gates", "at": [-9.0, -5.0], "tint": [1.0, 0.65, 0.3]},
	{"kind": "raids", "label": "Raid Hall", "at": [9.0, -5.0], "tint": [1.0, 0.35, 0.3]},
	{"kind": "events", "label": "Event Obelisk", "at": [0.0, -11.0], "tint": [1.0, 0.9, 0.4]},
	{"kind": "records", "label": "Hall of Records", "at": [-14.0, 3.0], "tint": [0.5, 0.7, 1.0]},
	{"kind": "market", "label": "Market", "at": [14.0, 3.0], "tint": [0.5, 1.0, 0.6]},
	{"kind": "post", "label": "Post", "at": [-10.0, 10.0], "tint": [0.8, 0.55, 1.0]},
	{"kind": "vault", "label": "Vault", "at": [10.0, 10.0], "tint": [0.4, 0.95, 0.9]},
]

var level
var mode := ""
var center := Vector3.ZERO
var radius := 24.0
var remote := {}          # id -> RemotePlayer
var foes := {}            # id -> NetFoe
var hazards := {}         # id -> {node, fill, t0, total, kind}
var orbs := {}            # id -> Node3D
var _player
var _t_move := 0.0
var _t_hp := 0.0
var _frozen := false
var _layer: CanvasLayer
var _phase_label: Label
var _boss_bar: ProgressBar
var _boss_label: Label
var _party_box: VBoxContainer
var _down_label: Label
var _say_label: Label
var _say_t := 0.0
var _ended := false
var _flash: ColorRect
var _bounce := false


func setup(lvl) -> void:
	level = lvl
	mode = str(lvl.def.get("online", ""))
	radius = float(lvl.def.get("arena_radius", 24.0))
	center = lvl.cell_to_world(Vector2i(lvl.width / 2, lvl.height / 2))


func _on() -> Node:
	return Game.online


func _ready() -> void:
	var on = _on()
	if on == null or not on.is_connected_ok():
		_go_home.call_deferred("The Gate is shut. (Enter it from the portal, signed in.)")
		_bounce = true
		return
	on.net.connect(_on_net)
	if mode == "hub":
		if on.state == "char":
			on.send({"t": "enter_hub"})
		for s in STANDS:
			var p := Pedestal.new()
			p.position = center + Vector3(float(s["at"][0]), 0.0, float(s["at"][1]))
			p.setup(level, s)
			level.add_child(p)
		Game.banner.emit.call_deferred("THE GATE", Color(0.7, 0.85, 1.0))
		Game.message.emit.call_deferred("The hub is shared with other players. T to talk. The stands open dungeon runs, raids, world events, the market and more.")
	elif mode == "arena":
		_build_hud()
		var k := str(on.inst.get("kind", "run"))
		Game.banner.emit.call_deferred({"run": "DUNGEON RUN", "raid": "RAID", "world": "WORLD BOSS"}.get(k, "THE GATE"), Color(1.0, 0.7, 0.4))
	set_process(true)
	set_process_unhandled_input(true)


func _go_home(msg: String) -> void:
	Game.message.emit(msg)
	Game.go_to("village", "P")


func _exit_tree() -> void:
	var on = _on()
	if on != null and on.net.is_connected(_on_net):
		on.net.disconnect(_on_net)
	if _frozen and is_instance_valid(_player):
		_player.set_physics_process(true)


func _hud():
	return get_tree().get_first_node_in_group("hud")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_T:
		var h = _hud()
		if h != null and not h.is_blocking():
			Menu.chat(h)


# ---- every frame ---------------------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if _bounce:
		return
	var on = _on()
	if on == null:
		return
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
	if mode == "hub":
		_hub_frame(on, delta)
	elif mode == "arena":
		_arena_frame(on, delta)


func _srv(p: Vector3) -> Vector2:
	return Vector2(p.x - center.x, p.z - center.z)


func _world(x: float, z: float) -> Vector3:
	return center + Vector3(x, 0.0, z)


func _hub_frame(on: Node, delta: float) -> void:
	if on.state == "char":
		_t_hp += delta
		if _t_hp > 2.0:
			_t_hp = 0.0
			on.send({"t": "enter_hub"})
	var me := str(on.char.get("id", ""))
	for id in on.players:
		if id == me:
			continue
		var p: Dictionary = on.players[id]
		if not remote.has(id):
			var rp := RemotePlayer.new()
			rp.setup(id, str(p.get("name", "?")), _world(float(p.get("x", 0)), float(p.get("z", 0))))
			add_child(rp)
			remote[id] = rp
		var r = remote[id]
		r.target = _world(float(p.get("x", 0)), float(p.get("z", 0)))
		r.target_yaw = float(p.get("yaw", 0))
	for id in remote.keys():
		if not on.players.has(id):
			remote[id].queue_free()
			remote.erase(id)
	_t_move += delta
	if _t_move > 0.2 and _player != null and on.state == "hub":
		_t_move = 0.0
		var v := _srv(_player.global_position)
		var yaw := 0.0
		var mdl = _player.get("_model")
		if mdl != null:
			yaw = mdl.rotation.y
		on.send({"t": "h_move", "x": v.x, "z": v.y, "yaw": yaw, "anim": "walk" if _player.velocity.length() > 0.5 else "idle"})


func _arena_frame(on: Node, delta: float) -> void:
	var inst: Dictionary = on.inst
	if inst.is_empty():
		return
	# --- foes
	var live := {}
	for id in inst["foes"]:
		live[id] = true
		var f: Dictionary = inst["foes"][id]
		if not foes.has(id):
			var nf := NetFoe.new()
			nf.net_setup(level, int(id), str(f.get("type", "")), str(f.get("name", "?")), int(f.get("hp", 1)), int(f.get("max", 1)),
				float(f.get("scale", 1.0)), bool(f.get("boss", false)), _world(float(f.get("x", 0)), float(f.get("z", 0))))
			add_child(nf)
			foes[id] = nf
		var n = foes[id]
		n.net_target = _world(float(f.get("x", 0)), float(f.get("z", 0)))
		n.net_hp(int(f.get("hp", 1)), int(f.get("max", n.net_max)))
	for id in foes.keys():
		if not live.has(id):
			if is_instance_valid(foes[id]):
				foes[id]._die()
			foes.erase(id)
	# --- circles
	var now := Time.get_ticks_msec() / 1000.0
	var hlive := {}
	for id in inst["haz"]:
		hlive[id] = true
		var h: Dictionary = inst["haz"][id]
		if not hazards.has(id):
			hazards[id] = _make_hazard(h)
		var rec: Dictionary = hazards[id]
		var frac := clampf((now - float(h["t0"])) / maxf(float(h["total"]), 0.1), 0.0, 1.0)
		if rec["fill"] != null:
			rec["fill"].scale = Vector3(maxf(frac, 0.02), 1, maxf(frac, 0.02))
	for id in hazards.keys():
		if not hlive.has(id):
			hazards[id]["node"].queue_free()
			hazards.erase(id)
	# --- orbs
	var olive := {}
	for id in inst["orbs"]:
		olive[id] = true
		if not orbs.has(id):
			var o := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.3
			sm.height = 0.6
			o.mesh = sm
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(0.4, 1.0, 0.5)
			mat.emission_enabled = true
			mat.emission = Color(0.4, 1.0, 0.5)
			mat.emission_energy_multiplier = 1.8
			o.material_override = mat
			var v: Vector2 = inst["orbs"][id]
			o.position = _world(v.x, v.y) + Vector3(0, 0.8, 0)
			add_child(o)
			orbs[id] = o
	for id in orbs.keys():
		if not olive.has(id):
			orbs[id].queue_free()
			orbs.erase(id)
	# --- the others in the party
	var me := str(inst.get("me", ""))
	for id in inst["pl"]:
		if id == me:
			continue
		var r: Array = inst["pl"][id]
		if not remote.has(id):
			var rp := RemotePlayer.new()
			rp.setup(id, str(inst["members"].get(id, "?")), _world(float(r[1]), float(r[2])))
			add_child(rp)
			remote[id] = rp
		remote[id].target = _world(float(r[1]), float(r[2]))
		remote[id].target_yaw = float(r[3])
		remote[id].set_down(int(r[5]) != 1)
	for id in remote.keys():
		if not inst["pl"].has(id) or not inst["members"].has(id):
			remote[id].queue_free()
			remote.erase(id)
	# --- me: send where I am; show what the server says my health is
	_t_move += delta
	if _t_move > 0.1 and _player != null and not _ended:
		_t_move = 0.0
		var v := _srv(_player.global_position)
		var mdl = _player.get("_model")
		on.send({"t": "i_move", "x": v.x, "z": v.y, "yaw": mdl.rotation.y if mdl != null else 0.0})
	var alive: bool = bool(inst.get("alive", true))
	if _player != null and alive == _frozen:
		_frozen = not alive
		_player.set_physics_process(alive)
		if not alive:
			_player.velocity = Vector3.ZERO
	_t_hp += delta
	if _t_hp > 0.15:
		_t_hp = 0.0
		var ratio := clampf(float(inst.get("hp", 1.0)) / maxf(float(inst.get("hpmax", 1.0)), 1.0), 0.0, 1.0)
		Game.hp = maxi(1, int(round(ratio * Game.max_hp())))
		Game.stats_changed.emit()
	_update_hud(inst, now, delta)


func _make_hazard(h: Dictionary) -> Dictionary:
	var node := Node3D.new()
	node.position = _world(float(h.get("x", 0)), float(h.get("z", 0)))
	add_child(node)
	var kind := str(h.get("kind", "circle"))
	var fill: MeshInstance3D = null
	var rr := float(h.get("r", 3.0))
	if kind == "circle":
		node.add_child(_disc(rr, Color(1.0, 0.25, 0.15, 0.22), 0.05))
		fill = _disc(rr, Color(1.0, 0.3, 0.1, 0.5), 0.07)
		node.add_child(fill)
	else:
		# "safe": the whole arena is going to hurt -- unless you stand in one of the green circles
		node.add_child(_disc(radius, Color(1.0, 0.2, 0.1, 0.16), 0.04))
		fill = _disc(radius, Color(1.0, 0.3, 0.1, 0.22), 0.05)
		node.add_child(fill)
		for z in h.get("zones", []):
			var d := _disc(float(z[2]), Color(0.3, 1.0, 0.5, 0.45), 0.09)
			d.position = Vector3(float(z[0]) - float(h.get("x", 0)), 0.0, float(z[1]) - float(h.get("z", 0)))
			node.add_child(d)
		fill.scale = Vector3(0.02, 1, 0.02)
	return {"node": node, "fill": fill}


func _disc(r: float, col: Color, y: float) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = 0.02
	c.radial_segments = 40
	m.mesh = c
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = Color(col.r, col.g, col.b)
	mat.emission_energy_multiplier = 0.6
	m.material_override = mat
	m.position.y = y
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return m


# ---- the fight's HUD ------------------------------------------------------------------------------------------------

func _build_hud() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 40
	add_child(_layer)
	_flash = ColorRect.new()
	_flash.color = Color(1, 0, 0, 0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_layer.add_child(_flash)
	var top := VBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_CENTER_TOP)
	top.position = Vector2(-220, 8)
	top.custom_minimum_size = Vector2(440, 0)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(top)
	_phase_label = Label.new()
	_phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_phase_label.add_theme_font_size_override("font_size", 22)
	_phase_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_phase_label.add_theme_constant_override("outline_size", 6)
	top.add_child(_phase_label)
	_boss_label = Label.new()
	_boss_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_boss_label.add_theme_constant_override("outline_size", 5)
	top.add_child(_boss_label)
	_boss_bar = ProgressBar.new()
	_boss_bar.custom_minimum_size = Vector2(440, 16)
	_boss_bar.show_percentage = false
	_boss_bar.visible = false
	top.add_child(_boss_bar)
	_party_box = VBoxContainer.new()
	_party_box.position = Vector2(12, 210)
	_party_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_party_box)
	_down_label = Label.new()
	_down_label.set_anchors_preset(Control.PRESET_CENTER)
	_down_label.position = Vector2(-300, 120)
	_down_label.custom_minimum_size = Vector2(600, 0)
	_down_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_down_label.add_theme_font_size_override("font_size", 26)
	_down_label.add_theme_color_override("font_color", Color(1.0, 0.5, 0.45))
	_down_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_down_label.add_theme_constant_override("outline_size", 8)
	_down_label.visible = false
	_layer.add_child(_down_label)
	_say_label = Label.new()
	_say_label.set_anchors_preset(Control.PRESET_CENTER)
	_say_label.position = Vector2(-300, -170)
	_say_label.custom_minimum_size = Vector2(600, 0)
	_say_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_say_label.add_theme_font_size_override("font_size", 24)
	_say_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.5))
	_say_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_say_label.add_theme_constant_override("outline_size", 8)
	_say_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_layer.add_child(_say_label)
	var leave := Button.new()
	leave.text = I18n.t("Leave")
	leave.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	leave.position = Vector2(12, -56)
	leave.custom_minimum_size = Vector2(110, 40)
	leave.focus_mode = Control.FOCUS_NONE
	leave.pressed.connect(_ask_leave)
	_layer.add_child(leave)


func _ask_leave() -> void:
	var h = _hud()
	if h == null:
		return
	h.open_dialog("Leave the fight?", "You can go back to the hub now. Whatever the party hasn't finished, you won't be paid for.", [
		["Leave", func():
			h.close_dialog()
			Game.online.leave_instance(true)],
		["Stay and fight", h.close_dialog]])


func _update_hud(inst: Dictionary, now: float, delta: float) -> void:
	if _layer == null:
		return
	var ph := str(inst.get("phase", ""))
	var txt := ""
	if ph == "countdown":
		var left := maxf(float(inst.get("phase_secs", 0.0)) - (now - float(inst.get("phase_at", now))), 0.0) if inst.has("phase_at") else 0.0
		txt = "Get ready... %d" % int(ceil(left))
	elif ph == "breather":
		txt = str(inst.get("text", "Room cleared"))
	else:
		txt = str(inst.get("text", ""))
	if ph in ["room", "boss"]:
		txt = "%s%s" % [(I18n.t("Boss: ") if ph == "boss" else ""), str(inst.get("text", ""))]
	_phase_label.text = txt
	# the boss bar
	var boss = null
	for id in inst["foes"]:
		if bool(inst["foes"][id].get("boss", false)):
			boss = inst["foes"][id]
			break
	_boss_bar.visible = boss != null
	_boss_label.text = str(boss.get("name", "")) if boss != null else ""
	if boss != null:
		_boss_bar.max_value = maxf(float(boss.get("max", 1)), 1.0)
		_boss_bar.value = float(boss.get("hp", 0))
	# the party
	var want: int = inst["members"].size()
	if _party_box.get_child_count() != want:
		for c in _party_box.get_children():
			c.queue_free()
		for id in inst["members"]:
			var row := HBoxContainer.new()
			row.name = "m" + str(id)
			var l := Label.new()
			l.custom_minimum_size = Vector2(110, 0)
			l.add_theme_color_override("font_outline_color", Color.BLACK)
			l.add_theme_constant_override("outline_size", 4)
			l.name = "l"
			row.add_child(l)
			var b := ProgressBar.new()
			b.custom_minimum_size = Vector2(110, 14)
			b.show_percentage = false
			b.name = "b"
			row.add_child(b)
			_party_box.add_child(row)
	for id in inst["members"]:
		var row = _party_box.get_node_or_null("m" + str(id))
		if row == null:
			continue
		var r = inst["pl"].get(id)
		row.get_node("l").text = str(inst["members"][id])
		row.get_node("b").max_value = float(inst.get("hpmax", 1.0))
		row.get_node("b").value = float(r[4]) if r != null else 0.0
		row.get_node("l").modulate = Color(1.0, 0.5, 0.45) if (r != null and int(r[5]) != 1) else Color.WHITE
	# down
	var alive: bool = bool(inst.get("alive", true))
	_down_label.visible = not alive and not _ended
	if not alive:
		var since := now - float(inst.get("down_at", now))
		var wind := ""
		if inst["members"].size() == 1:
			wind = "\nA second wind in %d s." % int(maxf(8.0 - since, 0.0))
		_down_label.text = I18n.t("YOU ARE DOWN\nA friend can raise you -- they must stand close.%s") % wind
	_flash.color.a = maxf(_flash.color.a - delta * 1.5, 0.0)
	if _say_t > 0.0:
		_say_t -= delta
		if _say_t <= 0.0:
			_say_label.text = ""


# ---- one-off things the server says ------------------------------------------------------------------------------------

func _on_net(m: Dictionary) -> void:
	var t := str(m.get("t", ""))
	match t:
		"_closed":
			if not _ended and not _bounce:
				_ended = true
				var h = _hud()
				Game.online.restore_solo()
				if h != null:
					h.open_dialog("The Gate closed", "The connection to the Gate was lost.\n\n%s" % Game.online.last_error, [["Back to the village", func():
						h.close_dialog()
						Game.go_to("village", "P")]])
		"i_dmg":
			var fid := int(m.get("id", 0))
			if foes.has(fid) and is_instance_valid(foes[fid]) and str(m.get("by", "")) != str(Game.online.inst.get("me", "")):
				foes[fid].seen_hit(false, int(m.get("amt", 0)))
		"i_hurt":
			if str(m.get("id", "")) == str(Game.online.inst.get("me", "")) and _flash != null:
				_flash.color.a = 0.35
				if is_instance_valid(_player) and _player.has_method("_shake"):
					_player._shake(0.12)
		"i_boom":
			var h2: Array = m.get("hit", [])
			if str(Game.online.inst.get("me", "")) in h2 and _flash != null:
				_flash.color.a = 0.5
		"i_say":
			var tx := str(m.get("text", ""))
			var ab := str(m.get("ability", ""))
			if tx != "" and _say_label != null:
				_say_label.text = tx
				_say_t = 3.5
			elif ab != "" and _say_label != null:
				_say_label.text = {"slam": I18n.t("SLAM -- get out of the circles!"), "volley": I18n.t("VOLLEY -- keep moving!"), "charge": I18n.t("It's charging!"),
					"safe": "Get into a GREEN circle!", "adds": "More are coming!"}.get(ab, "")
				_say_t = 2.5
		"i_end":
			_show_result(m)
		"i_up":
			if str(m.get("id", "")) == str(Game.online.inst.get("me", "")) and _player != null:
				Game.message.emit("You're back on your feet.")


func _show_result(m: Dictionary) -> void:
	if _ended:
		return
	_ended = true
	var rw: Dictionary = m.get("reward", {})
	var won := str(m.get("result", "")) == "won"
	var lines := []
	lines.append("%s in %s." % ["VICTORY" if won else "DEFEAT", _fmt_time(float(m.get("time", 0)))])
	var pen := float(rw.get("penalty", 0.0))
	if pen > 0.0:
		lines.append(I18n.t("Level gap in the party (%d levels): %d%% of the gold, XP and items were lost. Fight alongside players near your level.") % [int(rw.get("spread", 0)), int(round(pen * 100.0))])
	if won:
		lines.append(I18n.t("Gold %d   Marks %d   XP %d") % [int(rw.get("gold", 0)), int(rw.get("marks", 0)), int(rw.get("xp", 0))])
		var items: Dictionary = rw.get("items", {})
		var its := []
		for k in items:
			its.append("%d x %s" % [int(items[k]), Game.item_name(str(k))])
		if its.size() > 0:
			lines.append(I18n.t("Found: ") + ", ".join(its))
		if rw.has("title"):
			lines.append(I18n.t("New title: %s") % rw["title"])
	else:
		lines.append(I18n.t("The party fell. (You keep a little experience: %d.)") % int(rw.get("xp", 0)))
	lines.append("")
	for s in m.get("summary", []):
		lines.append(I18n.t("%s -- dealt %d, taken %d, downed %d") % [s.get("name", "?"), int(s.get("dealt", 0)), int(s.get("taken", 0)), int(s.get("downs", 0))])
	var h = _hud()
	if h == null:
		return
	h.open_dialog("The Gate -- result", "\n".join(lines), [
		["Back to the hub", func():
			h.close_dialog()
			Game.online.leave_instance(true)],
		["Home to the village", func():
			h.close_dialog()
			Game.online.leave_instance(false)]])


func _fmt_time(s: float) -> String:
	return "%d:%02d" % [int(s) / 60, int(s) % 60]
