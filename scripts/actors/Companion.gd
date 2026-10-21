extends Node3D
## Whoever travels with you. Robert, 2026-10-01: "allow for there to be
## familiars, bonds and companions maybe even a partner through chatting
## and chance -- allow for the relationships to develop naturally and
## fluidly."
##
## Someone who has come to count you as a close friend may agree to come
## along when you ask (it's their choice -- warmth tilts it, chance decides
## it). They walk at your shoulder from floor to floor, fight beside you,
## and talk in their own words (Voice.gd, the same as in town). The road
## warms a bond on its own. Someone devoted to you may agree to more than
## company: a partner -- you walk the road of cultivation together, and it
## shows (Game.PARTNER_EFFECT).
##
## Round 32 ("companions and pets grown up"): they fight in a STYLE you
## choose (striker, guard, scout -- data/companions.json), carry GEAR you
## give them (it shows in their hand), LEVEL with what they do, and have a
## life bar: knocked down, they're back after a while, or when you rest.

const STRIKE_COOLDOWN := 1.4
const STRIKE_REACH := 2.4
const HUNT_RADIUS := 7.0       # how far from you they'll go after something
const WARM_PER_MINUTE := 0.6

var npc_name := ""
var voice: Node
var _model: Node3D
var _label: Label3D
var _anim: AnimationPlayer
var _cool := 0.0
var _minute := 0.0
var _target = null
var _find_t := 0.0
var _down_shown := false
var slot := 0                  # round 39: 0 walks at your shoulder, 1 the second of a party of two


func _c() -> Dictionary:
	return Game.cslot(slot)


func _ready() -> void:
	set_meta("low_priority", true)     # a chest beside you wins the E key
	add_to_group("companion_node")
	add_to_group("companion")
	_build()
	Game.companion_changed.connect(_build)


func _build() -> void:
	for c in get_children():
		c.queue_free()
	voice = null
	_model = null
	if is_in_group("interactable"):
		remove_from_group("interactable")       # round 157: you talk to a companion from the menu (Party), never in the world -- they were in the way
	if _c().is_empty() or slot == 1 or bool(_c().get("away", false)):     # (or off on an expedition, or waiting at camp)
		visible = false
		npc_name = ""
		if not _c().is_empty():
			npc_name = str(_c().get("name", "Someone"))        # (still someone you can talk to, from the menu)
			voice = preload("res://scripts/core/Voice.gd").new()
			voice.npc_name = npc_name
			voice.persona_text = str(_c().get("persona", npc_name))
			voice.situation = "They are waiting for you at camp, or away on an errand for you."
			add_child(voice)
		return
	visible = true
	npc_name = str(_c().get("name", "Someone"))
	var held := "sword"                                     # round 32: the weapon you gave them
	var wid := Game.companion_gear("weapon", slot)
	if wid != "" and Game.has_item_def(wid):
		var k := str(Game.item_def(wid).get("kind", "sword"))
		if preload("res://scripts/world/Dress.gd").HELD.has(k):
			held = k
	var spec: Dictionary = preload("res://scripts/world/Dress.gd").spec_for(npc_name, "villager",
		{"held": held, "cape": [0.85, 0.75, 0.85]} if is_partner() else {"held": held})
	_model = preload("res://scripts/core/Art.gd").person(spec)
	add_child(_model)
	preload("res://scripts/world/Dress.gd").dress(_model, spec)
	var t: Array = _c().get("tint", [0.9, 0.95, 1.0])
	if not _model.has_meta("human"):
		_tint(_model, Color(float(t[0]), float(t[1]), float(t[2])))
	_anim = _find_anim(_model)
	if _anim:
		_anim.playback_default_blend_time = 0.18      # round 37: moves ease into each other
	if _anim:
		for a in ["idle", "walk", "sprint"]:
			if _anim.has_animation(a):
				_anim.get_animation(a).loop_mode = Animation.LOOP_LINEAR
		_play("idle")
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.pixel_size = 0.008
	_label.no_depth_test = true
	_label.position = Vector3(0, 2.2, 0)
	_label.font_size = 26                # (round 39: two of them now -- smaller names)
	_label.outline_size = 8
	_label.modulate = Color(1.0, 0.85, 0.95) if is_partner() else Color(0.85, 0.95, 1.0)
	_label.text = _tag()
	add_child(_label)
	voice = preload("res://scripts/core/Voice.gd").new()
	voice.npc_name = npc_name
	voice.persona_text = str(_c().get("persona", npc_name))
	voice.situation = ("They are your partner: you walk the road of cultivation together, through the dungeon below Eliet."
		if is_partner() else "They are travelling with you through the dungeon below Eliet, fighting at your side.")
	add_child(voice)


func _tag() -> String:
	## two short lines over their head (round 39: a party of two shouldn't drown the screen in words)
	return "%s%s\n%s, %s" % [npc_name, I18n.t("  (partner)") if is_partner() else "", str(Game.style_def("", slot).get("name", "")).to_lower(), Game.companion_level_name(slot)]


func is_partner() -> bool:
	return bool(_c().get("partner", false))


func snap_to(p: Vector3) -> void:
	global_position = p + Vector3(-1.4 - 1.2 * slot, 0, 1.2 + 0.8 * slot)


# ---- walking and fighting ------------------------------------------------

func _process(delta: float) -> void:
	if _c().is_empty() or slot == 1 or _model == null or bool(_c().get("away", false)):
		return
	var player = get_tree().get_first_node_in_group("player")
	if player == null:
		return
	_cool = maxf(0.0, _cool - delta)
	_minute += delta
	if _minute >= 60.0:
		_minute = 0.0
		Game.warm_bond(npc_name, WARM_PER_MINUTE)       # the road does this on its own
	Game.companion_tick(delta, slot)
	var yaw: float = player._yaw if "_yaw" in player else 0.0
	var want: Vector3 = player.global_position + Vector3(-1.5 - 1.2 * slot, 0, 1.4 + 0.8 * slot).rotated(Vector3.UP, yaw)
	if Game.companion_down(slot):
		# down: they kneel where they fell until the count runs out (or you rest)
		if not _down_shown:
			_down_shown = true
			_play("idle")
			_label.text = npc_name + I18n.t("\n(down -- back soon)")
		return
	elif _down_shown:
		_down_shown = false
		_label.text = _tag()
	var style := Game.style_def("", slot)
	var finds := float(style.get("finds", 0.0))
	if finds > 0.0:
		_find_t += delta
		if _find_t >= finds:
			_find_t = 0.0
			scout_find(randf())
	var foe = _pick_target(player)
	if foe != null:
		var to_foe: Vector3 = foe.global_position - global_position
		to_foe.y = 0.0
		if to_foe.length() <= STRIKE_REACH:
			want = global_position
			_model.rotation.y = atan2(to_foe.x, to_foe.z)
			if _cool <= 0.0:
				strike(foe)
		else:
			want = foe.global_position - to_foe.normalized() * 1.6
	var to := want - global_position
	to.y = 0.0
	if to.length() > 14.0:
		global_position = want           # left behind: catches up
	elif to.length() > 0.4:
		global_position += to.normalized() * minf(to.length(), delta * 6.5)
		_model.rotation.y = atan2(to.x, to.z)
		_play("sprint" if to.length() > 4.0 else "walk")
	elif _cool < STRIKE_COOLDOWN - 0.5:
		_play("idle")
	global_position.y = player.global_position.y


func _pick_target(player):
	var hunt := float(Game.style_def("", slot).get("hunt", HUNT_RADIUS))     # round 32: how far their style takes them
	if _target != null and (not is_instance_valid(_target) or _target._dead or not _hostile(_target)
			or _target.global_position.distance_to(player.global_position) > hunt + 2.0):
		_target = null
	if _target != null:
		return _target
	var best = null
	var best_d := hunt
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or e._dead or not _hostile(e):
			continue
		var d: float = e.global_position.distance_to(player.global_position)
		if d < best_d:
			best_d = d
			best = e
	_target = best
	return best


func _hostile(e) -> bool:
	## They leave the wild animals alone -- you hunt, or tame, those yourself.
	return not bool(e.stats.get("passive", false))


func strike_damage() -> int:
	## Keeps pace with you: their cultivation, their weapon, their style, their level, the bond.
	return Game.companion_damage(slot)


func strike(foe) -> int:
	_cool = float(Game.style_def("", slot).get("cooldown", STRIKE_COOLDOWN))
	_play("attack-melee-right", true)
	var dmg := strike_damage()
	var was_dead: bool = foe._dead
	foe.take_damage(dmg, npc_name)
	var L: Dictionary = Game.companions_data().get("levels", {})
	Game.companion_xp(float(L.get("xp_strike", 1)), "", slot)
	if not was_dead and foe._dead:
		Game.companion_xp(float(L.get("xp_kill_base", 4)) + float(L.get("xp_kill_per_depth", 1)) * Game.depth, "a kill", slot)
		Game.log_event("companion_kill", {"npc": npc_name, "type": str(foe.etype) if "etype" in foe else ""})
	return dmg


func near_player() -> bool:
	var player = get_tree().get_first_node_in_group("player")
	return player != null and visible and global_position.distance_to(player.global_position) < 4.0


func scout_find(roll: float) -> String:
	## a Scout turns something up as you walk the floor (not in town)
	if roll > 0.55 or Game.depth <= 0:
		return ""
	var rng := RandomNumberGenerator.new()
	rng.seed = int(roll * 1000000.0)
	var haul: Dictionary = Game._gather_haul(["herbalism", "mining"][rng.randi() % 2], 1, maxi(1, Game.depth), rng)
	for id in haul:
		Game.add_item(str(id), int(haul[id]), false)
		Game.message.emit(I18n.t("%s turns something up: %s.") % [npc_name, Game.item_name(str(id))])
		Game.log_event("companion_find", {"npc": npc_name, "id": str(id)})
		return str(id)
	return ""


# ---- talking --------------------------------------------------------------

func prompt() -> String:
	return I18n.t("E: Talk to ") + npc_name


func talk() -> void:
	## from the Party page of the menu
	if npc_name != "":
		interact(null)


func interact(_player) -> void:
	var hud = get_tree().get_first_node_in_group("hud")
	var opts := [["Talk with %s" % npc_name, func(): hud.open_chat(self)]]
	opts.append(["How %s fights (style, gear)" % npc_name, _fight_menu])
	var MN = Game.sys("menagerie")
	if MN != null and MN.is_wayfarer(npc_name):
		var di: Dictionary = MN.human_deed_info(npc_name)
		opts.append([(I18n.t("Ask: %s") % str(di["name"])) + ((" (%s)" % Game._dur(float(di["left"]))) if float(di["left"]) > 0.0 else ""), func():
			hud.close_dialog()
			Game.message.emit(MN.ask_human(npc_name))])
		if MN.oath_ready(npc_name):
			opts.append(["Hear %s out" % npc_name, func():
				var sw: String = MN.swear(npc_name)
				hud.open_dialog(npc_name, MN.oath_text(npc_name) + "\n\n" + sw, [["...", hud.close_dialog]])])
	if Game.can_ask_partner(npc_name):
		opts.append(["Ask %s to walk the road with you -- for good" % npc_name, func(): ask_partner(randf())])
	if slot == 0 and Game.can_send("companion") == "":
		opts.append(["Send %s on an expedition" % npc_name, func(): hud.open_expedition("companion")])
	if slot == 0 and Game.sys("seek") != null and Game.sys("seek").block(0, "plants") == "":
		opts.append(["Send %s searching (plants, reagents, jewels, shards)" % npc_name, func(): hud.open_search(0)])
	opts.append(["The party (the menu)", func():
		hud.close_dialog()
		hud.open_hub("Party")])
	opts.append(["Ask %s to head home for now" % npc_name, func():
		hud.close_dialog()
		Game.part_with_companion(slot)])
	opts.append(["Walk on", hud.close_dialog])
	var line := I18n.t("%s keeps pace beside you. (%s)") % [npc_name, Game.bond_stage(npc_name)]
	if is_partner():
		line = "%s walks at your side, close enough that your sleeves touch." % npc_name
	if Game.companion_down(slot):
		line = I18n.t("%s is down, getting their breath back. (%s)") % [npc_name, Game.bond_stage(npc_name)]
	line += "\n" + _sheet()
	if MN != null and MN.is_wayfarer(npc_name):
		line += "\n" + "\n".join(MN.human_lines(npc_name))
	hud.open_dialog(npc_name, line, opts)


func _sheet() -> String:
	var rows := []
	for r in Game.companion_rows(slot):
		rows.append("%s: %s" % [r[0], r[1]])
	return "\n".join(rows)


func _fight_menu(note: String = "") -> void:
	var hud = get_tree().get_first_node_in_group("hud")
	var opts := []
	var S: Dictionary = Game.companions_data().get("styles", {})
	var ids: Array = S.keys()
	ids.sort()
	for sid in ids:
		if sid == Game.companion_style(slot):
			continue
		opts.append(["Fight as a %s -- %s" % [S[sid].get("name", sid), S[sid].get("desc", "")], func():
			Game.set_companion_style(str(sid), slot)
			_fight_menu(I18n.t("%s nods. \"%s, then.\"") % [npc_name, S[sid].get("name", sid)])])
	var gear := []
	for id in Game.inventory:
		var t := str(Game.item_def(str(id)).get("type", ""))
		if (t == "weapon" or t == "armor") and str(id) != Game.weapon and str(id) != Game.armor:
			gear.append(str(id))
	gear.sort()
	for id in gear.slice(0, 8):
		opts.append(["Give %s" % Game.item_name(id), func(): _fight_menu(Game.give_companion_gear(id, slot))])
	for gslot in ["weapon", "armor"]:
		if Game.companion_gear(gslot, slot) != "":
			opts.append(["Take back their %s" % gslot, func(): _fight_menu(Game.take_companion_gear(gslot, slot))])
	opts.append(["Back", interact.bind(null)])
	var body := (note + "\n\n" if note != "" else "") + I18n.t("%s fights as a %s: %s\n\n%s") % [npc_name, Game.style_def("", slot).get("name", ""), Game.style_def("", slot).get("desc", ""), _sheet()]
	body += I18n.t("\n\nThey grow with every strike and every kill (and train at home while you're away, once home is a compound).")
	hud.open_dialog("%s -- how they fight" % npc_name, body, opts)


func say(text: String, cb: Callable) -> void:
	if voice == null:
		cb.call("")
		return
	voice.say(text, cb)


func ask_partner(roll: float) -> bool:
	var hud = get_tree().get_first_node_in_group("hud")
	var yes := Game.ask_partner(npc_name, roll)
	var body := ("%s is quiet for a long moment. Then: \"I was waiting for you to ask.\"" % npc_name if yes
		else "%s looks away, then back, and smiles -- but shakes their head. \"Not yet. Ask me again, some other day.\"" % npc_name)
	if hud:
		hud.open_dialog(npc_name, body, [["...", hud.close_dialog]])
	return yes


# ---- helpers ----------------------------------------------------------------

func _play(anim: String, restart: bool = false) -> void:
	if _anim and _anim.has_animation(anim) and (restart or _anim.current_animation != anim):
		_anim.play(anim)


func _tint(n: Node, c: Color) -> void:
	# (looks only -- the headless engine check's dummy renderer errors on
	# re-tinting a freshly rebuilt model, so skip it there)
	if DisplayServer.get_name() == "headless":
		return
	if n is MeshInstance3D:
		for i in n.get_surface_override_material_count():
			var m = n.get_active_material(i)
			if m is StandardMaterial3D:
				var mm: StandardMaterial3D = m.duplicate()
				mm.albedo_color = mm.albedo_color * c
				n.set_surface_override_material(i, mm)
	for ch in n.get_children():
		_tint(ch, c)


func _find_anim(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var a := _find_anim(c)
		if a:
			return a
	return null
