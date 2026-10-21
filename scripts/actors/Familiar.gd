extends Node3D
## Your familiar: an animal that chose you (fed by hand until it trusted
## you -- see Enemy.gd). It follows at your heel from floor to floor,
## sometimes turns something up (a herb, a nugget), and the longer you
## travel together the stronger the bond -- and what it gives you
## (its "effect" in data/enemies.json) grows with the bond.
##
## Round 32 ("pets grown up"): it EVOLVES -- grown, fierce, spirit beast --
## as the bond deepens (data/companions.json "familiar"): bigger, a bite
## of its own, and more of what it gives you. The TAMING skill (feeding,
## finds, bites) opens a tree of perks, one choice a tier, chosen here.

const FIND_SECONDS := 75.0
const BOND_PER_MINUTE := 0.5

var _model: Node3D
var _label: Label3D
var _find_t := FIND_SECONDS
var _minute := 0.0
var _hop := 0.0
var _bite_cool := 0.0
var _glow: OmniLight3D
var slot := 0                  # round 39: which of the beasts at your side (0: the lead)
var _who := ""


func _me() -> Dictionary:
	return Game.summoned_beast(slot)


func _ready() -> void:
	set_meta("low_priority", true)     # anything else in reach wins the E key
	add_to_group("familiar_node")
	_build()
	Game.familiar_changed.connect(_build)


func _build() -> void:
	_orbs = null
	for c in get_children():
		c.queue_free()
	if _me().is_empty() or bool(_me().get("away", false)):     # (or off on an expedition)
		visible = false
		_model = null
		if is_in_group("interactable"):
			remove_from_group("interactable")
		return
	visible = true
	add_to_group("interactable")
	var st: Dictionary = Game.enemies.get(str(_me().get("species", "")), {})
	var t: Array = st.get("tint", [0.8, 0.7, 0.6])
	var tcol := Color(float(t[0]), float(t[1]), float(t[2]))
	var BRd = Game.sys("breeding")
	if BRd != null:
		tcol = BRd.tint_for(_me(), tcol)                 # round 161: mixed blood and mutations show
	_model = preload("res://scripts/actors/Enemy.gd").make_beast(tcol, str(st.get("name", _me().get("species", ""))))
	var sd: Dictionary = Game.familiar_stage_def(_me())
	var MNe = Game.sys("menagerie")
	var fme: Dictionary = MNe.form_of(_me()) if MNe != null else {}
	var accent: Color = fme["color"] if not fme.is_empty() else tcol.lightened(0.35)
	if _model.has_method("evolve"):
		_model.evolve(Game.familiar_stage(_me()), accent)           # round 153: the body changes, not just its size
	if _model.has_method("lineage") and BRd != null:
		var mixc := Color(0, 0, 0, 0)
		var mk := str(_me().get("mix", ""))
		if mk != "":
			var mt: Array = Game.enemies.get(mk, {}).get("tint", [])
			if mt.size() >= 3:
				mixc = Color(float(mt[0]), float(mt[1]), float(mt[2]), 1.0)
		var vk := str(_me().get("variant", ""))
		var vcc := Color(1, 1, 1)
		if vk != "" and BRd.data.get("variants", {}).has(vk):
			var va: Array = BRd.data["variants"][vk]["color"]
			vcc = Color(float(va[0]), float(va[1]), float(va[2]))
		_model.lineage(Game.familiar_stage(_me()), vk, vcc, mixc, int(_me().get("gen", 0)))
	_model.scale = Vector3.ONE * 2.0 * float(st.get("scale", 1.0)) * float(sd.get("scale", 1.0)) * float(Game.contract_tier_def(_me()).get("scale", 1.0))
	add_child(_model)
	if bool(sd.get("glow", false)) and DisplayServer.get_name() != "headless":
		_glow = OmniLight3D.new()                 # a spirit beast carries a little of the deep's light
		_glow.light_color = Color(0.6, 0.95, 0.8)
		_glow.light_energy = 1.1
		_glow.omni_range = 4.0
		_glow.position = Vector3(0, 1.0, 0)
		add_child(_glow)
	var MNf = Game.sys("menagerie")
	var fm: Dictionary = MNf.form_of(_me()) if MNf != null else {}
	if not fm.is_empty():
		_add_form(fm)                                     # round 153: a ring (fierce), orbs (awakened)
	_label = Label3D.new()
	_label.text = Game.familiar_title(_me())
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.pixel_size = 0.008
	_label.no_depth_test = true
	_label.position = Vector3(0, 1.4, 0)
	_label.font_size = 26
	_label.outline_size = 8
	_label.modulate = Color(0.7, 1.0, 0.8)
	add_child(_label)


var _orbs: Node3D


func _add_form(fm: Dictionary) -> void:
	var c: Color = fm["color"]
	var sc: float = float(Game.familiar_stage_def(_me()).get("scale", 1.0))
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.34 * sc
	tm.outer_radius = 0.4 * sc
	ring.mesh = tm
	var rm := StandardMaterial3D.new()
	rm.albedo_color = c
	rm.emission_enabled = true
	rm.emission = c
	rm.emission_energy_multiplier = 2.0
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.material_override = rm
	ring.position = Vector3(0, 0.08, 0)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	if bool(fm["awakened"]):
		_orbs = Node3D.new()
		_orbs.position = Vector3(0, 1.0 * sc, 0)
		for i in 3:
			var o := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.08
			sm.height = 0.16
			o.mesh = sm
			o.material_override = rm
			o.position = Vector3(0.5 * sc, 0, 0).rotated(Vector3.UP, TAU * float(i) / 3.0)
			o.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_orbs.add_child(o)
		add_child(_orbs)
		if DisplayServer.get_name() != "headless":
			var l := OmniLight3D.new()
			l.light_color = c
			l.light_energy = 0.9
			l.omni_range = 3.5
			l.position = Vector3(0, 1.0 * sc, 0)
			add_child(l)


func snap_to(p: Vector3) -> void:
	global_position = p + Vector3(1.2 + 0.9 * slot, 0, 1.2 - 1.1 * slot)


func _process(delta: float) -> void:
	if _orbs != null and is_instance_valid(_orbs):
		_orbs.rotate_y(delta * 1.8)
	if _me().is_empty() or _model == null or bool(_me().get("away", false)):
		return
	var player = get_tree().get_first_node_in_group("player")
	if player == null:
		return
	var want: Vector3 = player.global_position + Vector3(1.3 + 0.9 * slot, 0, 1.3 - 1.1 * slot).rotated(Vector3.UP, player._yaw if "_yaw" in player else 0.0)
	var to := want - global_position
	to.y = 0.0
	if to.length() > 12.0:
		global_position = want         # left behind: it catches up
	elif to.length() > 0.4:
		global_position += to * minf(delta * 4.0, 1.0)
		_model.rotation.y = atan2(to.x, to.z)
		_hop += delta * 12.0
		_model.position.y = absf(sin(_hop)) * 0.15
	else:
		_model.position.y = 0.0
	global_position.y = player.global_position.y
	_minute += delta
	if _minute >= 60.0:
		_minute = 0.0
		Game.grow_bond(BOND_PER_MINUTE, _me())
	_find_t -= delta
	if _find_t <= 0.0:
		_find_t = Game.familiar_find_seconds(FIND_SECONDS)
		find_something(randf())
	# round 32: a grown familiar bites what comes near you
	_bite_cool = maxf(0.0, _bite_cool - delta)
	if _bite_cool <= 0.0 and Game.familiar_bite(_me()) > 0:
		var F: Dictionary = Game.companions_data().get("familiar", {})
		var foe = _nearest_foe(player, float(F.get("bite_hunt", 4.0)))
		if foe != null:
			bite(foe)


func find_something(roll: float) -> String:
	## Every so often it turns something up -- more often as the bond grows.
	var st: Dictionary = Game.enemies.get(str(_me().get("species", "")), {})
	var finds: Array = st.get("familiar", {}).get("finds", [])
	var chance := 0.35 + float(_me().get("bond", 0.0)) / 400.0
	if finds.is_empty() or roll > chance:
		return ""
	var id := str(finds[int(roll * 1000.0) % finds.size()])
	if not Game.items.has(id):
		return ""
	Game.add_item(id, 1, false)
	Game.message.emit(I18n.t("%s noses something out of the dirt: %s.") % [_me().get("name", ""), Game.item_name(id)])
	Game.grow_bond(2.0, _me())
	Game.taming_xp("find")
	Game.log_event("familiar_find", {"id": id})
	return id


func _nearest_foe(player, within: float):
	var best = null
	var best_d := within
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or e._dead or bool(e.stats.get("passive", false)):
			continue
		var d: float = e.global_position.distance_to(player.global_position)
		if d < best_d:
			best_d = d
			best = e
	return best


func bite(foe) -> int:
	var F: Dictionary = Game.companions_data().get("familiar", {})
	_bite_cool = float(F.get("bite_cooldown", 1.6))
	var dmg := Game.familiar_bite(_me())
	if dmg <= 0:
		return 0
	var to: Vector3 = foe.global_position - global_position
	to.y = 0.0
	if to.length() > float(F.get("bite_reach", 2.6)):
		global_position += to.normalized() * minf(to.length() - 1.2, 2.0)      # it darts in
	if _model:
		_model.rotation.y = atan2(to.x, to.z)
	foe.take_damage(dmg, Game.familiar_title(_me()))
	Game.taming_xp("bite")
	if Game.has_perk("pack_bond"):
		Game.heal(maxi(1, int(round(Game.max_hp() * 0.02))))
	Game.log_event("familiar_bite", {"dmg": dmg})
	return dmg


func prompt() -> String:
	return "E: " + str(_me().get("name", ""))


func interact(_player) -> void:
	var hud = get_tree().get_first_node_in_group("hud")
	if hud == null:
		return
	var nm := str(_me().get("name", ""))
	var opts := []
	if slot == 0 and Game.can_send("familiar") == "":
		opts.append(["Send %s off exploring" % nm, func(): hud.open_expedition("familiar")])
	var MN = Game.sys("menagerie")
	if MN != null and not MN.beast_deed_info(_me()).is_empty():
		var di: Dictionary = MN.beast_deed_info(_me())
		opts.append([(I18n.t("Ask: %s") % str(di["name"])) + ((" (%s)" % Game._dur(float(di["left"]))) if float(di["left"]) > 0.0 else ""), func():
			hud.close_dialog()
			Game.message.emit(MN.ask_beast(_me()))])
	var PU = Game.sys("pull")
	opts.append(["Scratch behind the ears", func():
		hud.close_dialog()
		Game.message.emit(PU.pet(_me()) if PU != null else "%s leans into your hand." % nm)])
	if PU != null:
		var fi: String = PU.feed_item()
		opts.append([I18n.t("Feed %s") % nm + ((" (" + Game.item_name(fi) + ")") if fi != "" else ""), func():
			hud.close_dialog()
			Game.message.emit(PU.feed(_me()))])
	opts.append(["The taming tree", taming_menu])
	opts.append(["Your contracts (the Party page)", func():
		hud.close_dialog()
		hud.open_hub("Party")])
	var sd: Dictionary = Game.familiar_stage_def(_me())
	var body := I18n.t("%s looks up at you. (bond %d%s)") % [nm, int(_me().get("bond", 0.0)), (", " + str(sd.get("title", ""))) if str(sd.get("title", "")) != "" else ""]
	var nxt: Array = (Game.companions_data().get("familiar", {}).get("stages", []) as Array).filter(func(x): return float(x.get("bond", 0)) > float(_me().get("bond", 0.0)))
	if not nxt.is_empty():
		body += I18n.t("\nAt bond %d it becomes %s.") % [int(nxt[0].get("bond", 0)), str(nxt[0].get("title", ""))]
	if Game.familiar_bite(_me()) > 0:
		body += I18n.t("\nIts bite: %d.") % Game.familiar_bite(_me())
	body += I18n.t("\nWhat it gives you is x%.1f for its stage.") % Game.familiar_effect_mult(_me())
	if MN != null:
		for bl in MN.beast_lines(_me()):
			body += "\n" + bl
	hud.open_dialog(Game.familiar_title(_me()), body, opts)


func taming_menu(note: String = "") -> void:
	var hud = get_tree().get_first_node_in_group("hud")
	var lines := []
	var opts := []
	lines.append(I18n.t("Taming %d (%s). Feeding animals, your familiar's finds and its bites all teach it. Each tier is one choice of two -- for good.") % [Game.taming_level(), Game.skill_title("taming")])
	for row in Game.taming_tiers():
		var t: Dictionary = row[0]
		var chosen: String = row[1]
		var open: bool = row[2]
		var a: Dictionary = t["a"]
		var b: Dictionary = t["b"]
		if chosen != "":
			var c: Dictionary = a if str(a.get("id", "")) == chosen else b
			lines.append(I18n.t("Tier (Taming %d): %s -- %s  [chosen]") % [int(t.get("skill", 1)), c.get("name", ""), c.get("desc", "")])
		elif open:
			lines.append(I18n.t("Tier (Taming %d): choose --") % int(t.get("skill", 1)))
			for c2 in [a, b]:
				lines.append("    %s -- %s" % [c2.get("name", ""), c2.get("desc", "")])
				opts.append(["Choose %s" % c2.get("name", ""), func(): taming_menu(Game.choose_perk(str(c2["id"])))])
		else:
			lines.append(I18n.t("Tier (Taming %d): %s / %s  [needs Taming %d]") % [int(t.get("skill", 1)), a.get("name", ""), b.get("name", ""), int(t.get("skill", 1))])
	opts.append(["Back", interact.bind(null)])
	hud.open_dialog(I18n.t("The taming tree"), (note + "\n\n" if note != "" else "") + "\n".join(lines), opts)
