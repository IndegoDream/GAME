extends StaticBody3D
## A dead master's inheritance -- the cultivation-novel kind: a figure
## still seated where they died, waiting for someone worthy. Defined in a
## level file's "inheritances" section:
##   "I": {"master": "the Azure Sword Sage",
##         "text": "what the master's lingering will says",
##         "hidden": true,          # only Spirit Sense can see it
##         "needs_realm": 1,        # too weak = turned away (come back later)
##         "grants": {"items": {"flying_sword": 1},
##                    "techniques": ["sword_heart"], "qi": 300}}
## Claimed once, ever. A hidden one is invisible and can't be touched
## until you can sense hidden things -- hidden in plain sight.
## Round 43: the BASE REQUIREMENT is the higher of needs_realm and the realm of
## every art it teaches (no needs_realm = one realm per four floors). Too weak,
## or nothing in it you can use -- or just by choice -- you can CONDENSE it
## into an Inheritance Crystal, to absorb later or sell (Game.condense_inheritance).

var level
var cell := Vector2i.ZERO
var master := "a nameless master"
var text := ""
var hidden := false
var needs_realm := 0
var grants := {}
var _key := ""
var _body: Node3D
var _aura: OmniLight3D
var _shape: CollisionShape3D
var _shown := true
var _check_t := 0.0
var tier := ""                  # round 51: "major" or "heavenly" ("" = a level's own, as before)
var heaven := ""                # a heavenly one's pool id
var notice := 0.0               # searching slowly beside it (major only)
var _told := false              # the "something old is near" line, once a visit
var _echo: Node                 # a heavenly master's echo, while it tests you
var _tell: CPUParticles3D


func setup(lvl, args: Dictionary) -> void:
	level = lvl
	cell = args.get("cell", Vector2i.ZERO)
	var d: Dictionary = args.get("def", {})
	master = str(d.get("master", master))
	text = str(d.get("text", ""))
	hidden = bool(d.get("hidden", false))
	needs_realm = int(d.get("needs_realm", -1))
	if needs_realm < 0:
		needs_realm = Game.inheritance_default_realm(int(Game.depth))
	grants = d.get("grants", {})
	tier = str(args.get("tier", d.get("tier", "")))
	heaven = str(d.get("heaven", ""))
	if tier != "" and _L() and not bool(_L().pin.get("sense_everywhere", false)):
		hidden = true                              # round 51: never in plain sight
	# keyed by where the floor's map put it, wherever it sits this game
	_key = str(args["key"]) if args.has("key") else Game.flag_key(level.level_id, args.get("key_cell", cell), "inheritance")


func _ready() -> void:
	_body = Node3D.new()
	add_child(_body)
	var base = preload("res://scripts/core/Art.gd").make("nature-kit/statue_block.glb")
	base.scale = Vector3(1.6, 0.5, 1.6)
	_body.add_child(base)
	var figure = preload("res://scripts/core/Art.gd").person({"sex": "m", "hair": "topknot", "beard": true, "hair_color": [0.85, 0.85, 0.85], "robe": [0.9, 0.9, 0.88]})
	figure.position = Vector3(0, 0.45, 0)
	_body.add_child(figure)
	_tint(figure, Color(0.55, 0.85, 0.75) if not claimed() else Color(0.45, 0.45, 0.45))
	var anim := _find_anim(figure)
	if anim and anim.has_animation("sit"):
		anim.play("sit")
		anim.seek(anim.current_animation_length * 0.99, true)
		anim.pause()
	_aura = OmniLight3D.new()
	_aura.light_color = Color(0.45, 1.0, 0.8)
	_aura.omni_range = 4.0
	_aura.light_energy = 1.6 if not claimed() else 0.0
	_aura.position = Vector3(0, 1.6, 0)
	_body.add_child(_aura)
	_shape = CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.2, 1.6, 1.2)
	_shape.shape = box
	_shape.position = Vector3(0, 0.8, 0)
	add_child(_shape)
	level.astar.set_point_solid(cell, true)
	_shown = not revealed()        # force the first update to apply
	_update_visibility(false)
	if tier == "heavenly":
		_heavenly_look()
	if tier != "" and not claimed():
		_add_tell()


func claimed() -> bool:
	return Game.has_flag(_key)


func _L():
	return Game.sys("legacies")


func _rules() -> Dictionary:
	return _L().cfg("heavenly" if tier == "heavenly" else "major") if _L() else {}


func revealed() -> bool:
	if not hidden:
		return true
	if tier == "" or _L() == null or bool(_L().pin.get("sense_everywhere", false)):
		return Game.can_sense_hidden()
	return Game.has_flag(_key + ":seen") or claimed()


func _search(delta: float) -> void:
	## round 51: a hidden legacy shows itself only to someone close -- Spirit
	## Sense from a few steps, or (a major) a slow, careful search right beside it
	if tier == "" or _L() == null or revealed() or not is_inside_tree():
		return
	var p = get_tree().get_first_node_in_group("player")
	if p == null:
		return
	var d := Vector2(p.global_position.x - global_position.x, p.global_position.z - global_position.z).length()
	var R := _rules()
	var hard := _hardness()
	var can_perceive := tier != "heavenly" or Game.realm >= int(R.get("perceive_realm", 3))
	if not can_perceive:
		return
	if Game.can_sense_hidden() and d <= float(R.get("sense_reach", 6.0)) * float(hard["reach"]):
		_see("sense")
		return
	if Game.can_sense_hidden() and d <= float(R.get("tell_reach", 14.0)) * float(hard["tell"]) and not _told:
		_told = true
		Game.message.emit("Your spirit sense brushes something old and patient nearby. It doesn't want to be found -- not from here.")
	if tier == "major":
		var N: Dictionary = R.get("notice", {})
		if d <= float(N.get("reach", 2.8)) * float(hard["reach"]):
			var r: float = (float(N.get("base", 0.035)) + float(N.get("per_survival", 0.006)) * Game.skill_level("survival")) * float(hard["notice"])
			var v: Vector3 = p.velocity if p is CharacterBody3D else Vector3.ZERO
			var sp := Vector2(v.x, v.z).length()
			if sp < 0.5:
				r *= float(N.get("still_mult", 3.0))
			elif sp > 6.5:
				r *= float(N.get("sprint_mult", 0.0))
			notice += r * delta
			if notice >= 1.0:
				_see("eye")


func _hardness() -> Dictionary:
	## round 119: harder to find the deeper it sits (data/legacies.json depth_scale), never impossible
	var S: Dictionary = _L().cfg("depth_scale") if _L() else {}
	if S.is_empty() or level == null:
		return {"reach": 1.0, "tell": 1.0, "notice": 1.0}
	var t := clampf((float(Game.floor_depth(str(level.level_id))) - float(S.get("from", 8))) / maxf(1.0, float(S.get("to", 48)) - float(S.get("from", 8))), 0.0, 1.0)
	return {"reach": lerpf(1.0, float(S.get("reach_min", 0.6)), t), "tell": lerpf(1.0, float(S.get("tell_min", 0.6)), t), "notice": lerpf(1.0, float(S.get("notice_min", 0.4)), t)}


func _see(how: String) -> void:
	Game.set_flag(_key + ":seen")
	if how == "sense":
		Game.message.emit("Your spirit sense closes on it: someone is sitting here, very still, and has been for a very long time." if tier == "major"
			else "The air goes still and bright. Your spirit sense touches a will so vast it takes your breath -- a HEAVENLY inheritance.")
	else:
		Game.message.emit("You stop. In the dust and the dark there is a shape you took for stone: someone, seated, waiting.")
	_update_visibility(false)


func _process(delta: float) -> void:
	_check_t -= delta
	if _check_t <= 0.0:
		_check_t = 0.5
		_search(0.5)
		_update_visibility(true)
	if _echo != null and not is_instance_valid(_echo):
		_echo = null
	elif _echo != null and bool(_echo.get("_dead")):
		_echo = null
		_trial_won()
	if _shown and not claimed():
		_aura.light_energy = 1.3 + sin(Time.get_ticks_msec() / 400.0) * 0.4


func _update_visibility(announce: bool) -> void:
	var show := revealed()
	if show == _shown:
		return
	_shown = show
	_body.visible = show
	_shape.disabled = not show
	if show:
		add_to_group("interactable")
		if not claimed():
			add_to_group("discoverable")
			if hidden and announce and tier == "":
				Game.message.emit("Your spirit sense brushes something that wasn't there a moment ago.")
			if hidden:
				Game.log_event("hidden_revealed", {"what": "inheritance", "master": master})
	else:
		remove_from_group("interactable")
		remove_from_group("discoverable")


func prompt() -> String:
	if claimed():
		if Game.has_flag(_key + ":crystal"):
			return "E: Look at the empty seat of " + master
		return "E: Bow to the remains of " + master
	return "E: Approach the seated figure"


func interact(_player) -> void:
	var hud = get_tree().get_first_node_in_group("hud")
	if claimed():
		if Game.has_flag(_key + ":crystal"):
			hud.open_dialog(master.capitalize(), "Only dust where the will sat. What was left of %s is in the crystal you made." % master, [["Leave", hud.close_dialog]])
		else:
			hud.open_dialog(master.capitalize(), "Only bones now, and the quiet of a debt repaid.", [["Bow and leave", hud.close_dialog]])
		return
	if _line_gate(hud):
		return                        # round 119: a master's task comes first
	if tier == "heavenly":
		_heavenly_interact(hud)
		return
	var need: int = Game.inheritance_need(needs_realm, grants)
	var state: String = Game.inheritance_state(needs_realm, grants)
	if state == "locked":
		hud.open_dialog("A Lingering Will", ("The seated bones turn their empty eyes to you, and a pressure like a mountain settles on your shoulders.\n\n\"Too weak. My legacy would break you. Come back when you have reached %s.\"" % Game.realm_name_of(need))
			+ "\n\n(This legacy asks for %s. You are %s.)\n\n%s\n\nOr ask the will to condense itself into a crystal. You can carry it, absorb it once you reach %s, or sell it. The seat will be empty after." % [Game.realm_name_of(need), Game.realm_name_of(Game.realm), _grants_text(), Game.realm_name_of(need)],
			[["Condense it into a crystal", _condense.bind(hud)], ["Withdraw", hud.close_dialog]])
		Game.log_event("inheritance_locked", {"master": master})
		return
	if state == "useless":
		hud.open_dialog("A Lingering Will", "The will looks you over and laughs, dry as old paper.\n\n\"You already carry everything I had to teach. There's nothing here for you.\"\n\nYou can still condense it into a crystal for someone who needs it -- a trader will pay for it. The seat will be empty after.",
			[["Condense it into a crystal", _condense.bind(hud)], ["Leave it be", hud.close_dialog]])
		return
	var body := text if text != "" else "\"At last. Take it -- all of it -- and do better with it than I did.\""
	if Game.sys("lore") and not Game.has_flag(_key + ":advice"):
		var w: String = Game.sys("lore").framed("inheritance", "tip")     # round 42: a dead master's last advice
		if w != "":
			Game.set_flag(_key + ":advice")
			body += "\n\n" + w
	body += "\n\n" + _grants_text()
	hud.open_dialog("The Inheritance of " + master.trim_prefix("the ").capitalize(), body, [["Accept the legacy", func():
		hud.close_dialog()
		Game.claim_inheritance(_key, master, grants)
		Game.note_place("Received the inheritance of " + master)
		remove_from_group("discoverable")
		_tint(_body, Color(0.45, 0.45, 0.45))
		_aura.light_energy = 0.0
	], ["Condense it into a crystal instead", _condense.bind(hud)]])


# ---- round 119: the master's task -----------------------------------------------------------------

func _line_gate(hud) -> bool:
	## true while the quest line still stands between you and this seat
	var LL = preload("res://scripts/systems/LegacyLines.gd")
	if not LL.needs_line(tier):
		return false
	var st: String = LL.state(_key)
	var bal = Game.sys("balance")
	if bal:
		bal.note_seat(_key, tier)               # the roads count the seats you have come across
	if st == "done":
		return false
	var Q = Game.sys("quests")
	var lt: String = tier
	if tier == "heavenly" and _L() and str(_L().heavenly(heaven).get("line_tier", "")) != "":
		lt = str(_L().heavenly(heaven)["line_tier"])          # the ultimate legacy: the longest line
	if st == "active":
		var q: String = LL.qid_of(_key)
		hud.open_dialog("The Task of " + master.trim_prefix("the ").capitalize(),
			"The will does not stir. It has already told you what it wants.\n\nYour task: %s%s\n\n(Step %d of %d. Check the Quests page.)" % [str(Q.stage(q).get("log", "")), Q.progress_text(q), int(Q.active[q]["stage"]) + 1, Q.qdef(q).get("stages", []).size()],
			[["Go and do it", hud.close_dialog]])
		return true
	var def: Dictionary = LL.plan(_key, master, lt, grants, int(Game.depth))
	var n: int = def["stages"].size()
	var base: int = int(def.get("base_steps", n))
	var shorter := ""
	if n < base:
		shorter = "\n\n(It would have asked %d of you. What you already carry of its way shortens it to %d.)" % [base, n]
	hud.open_dialog("A Lingering Will" if tier == "major" else "A Heavenly Will",
		("The seated figure does not give. It asks.\n\n\"A legacy is not picked up like a coin. Do what I ask -- %d tasks -- and come back. Do them in your own time, beside whatever else you walk.\"" % n) + shorter,
		[["Take up the task", func():
			hud.close_dialog()
			LL.start(_key, master, lt, grants, int(Game.depth))
			Game.note_place("Took up the task of " + master)], ["Not now", hud.close_dialog]])
	return true


# ---- round 51: heavenly inheritances ------------------------------------------------------------

func _heavenly_look() -> void:
	## white jade on a lotus dais, a gold light, a faint pillar into the dark
	_tint(_body, Color(0.92, 0.95, 0.88) if not claimed() else Color(0.5, 0.5, 0.48))
	_aura.light_color = Color(1.0, 0.88, 0.55)
	_aura.omni_range = 6.0
	if DisplayServer.get_name() == "headless":
		return
	var pillar := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.5
	cm.bottom_radius = 0.7
	cm.height = 6.0
	pillar.mesh = cm
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(1.0, 0.9, 0.6, 0.07)
	pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.cull_mode = BaseMaterial3D.CULL_DISABLED
	pillar.material_override = pm
	pillar.position = Vector3(0, 3.0, 0)
	pillar.name = "Pillar"
	_body.add_child(pillar)


func _add_tell() -> void:
	## the only sign before it's found: a few motes of light, drifting up
	## from nothing -- easy to take for dust
	if DisplayServer.get_name() == "headless":
		return
	_tell = CPUParticles3D.new()
	_tell.amount = 4 if tier == "major" else 6
	_tell.lifetime = 4.0
	_tell.preprocess = 4.0
	_tell.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_tell.emission_box_extents = Vector3(0.5, 0.2, 0.5)
	_tell.position = Vector3(0, 0.3, 0)
	_tell.direction = Vector3.UP
	_tell.spread = 8.0
	_tell.gravity = Vector3.ZERO
	_tell.initial_velocity_min = 0.08
	_tell.initial_velocity_max = 0.16
	var q := QuadMesh.new()
	q.size = Vector2(0.03, 0.03)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.7, 1.0, 0.85, 0.4) if tier == "major" else Color(1.0, 0.92, 0.6, 0.5)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	q.material = m
	_tell.mesh = q
	add_child(_tell)


func trial_passed() -> bool:
	return _L() != null and bool(_L().trials_passed.get(heaven, false))


func _heavenly_interact(hud) -> void:
	var need: int = maxi(needs_realm, Game.inheritance_need(needs_realm, grants))
	if Game.realm < need:
		hud.open_dialog("A Heavenly Will", ("The pressure is not a mountain. It is the sky. You are on your knees before you know it.\n\n\"Not yet. Come back when you have reached %s -- and I will see if you are worth the rest.\"" % Game.realm_name_of(need))
			+ "\n\n(A heavenly inheritance asks for %s. You are %s. A legacy this great can't be pressed into a crystal.)" % [Game.realm_name_of(need), Game.realm_name_of(Game.realm)],
			[["Withdraw", hud.close_dialog]])
		Game.log_event("inheritance_locked", {"master": master, "tier": "heavenly"})
		return
	if not trial_passed():
		if _echo != null:
			hud.open_dialog("A Heavenly Will", "The echo is still standing. Finish it.", [["Back to the fight", hud.close_dialog]])
			return
		hud.open_dialog("The Will of " + master.trim_prefix("the ").capitalize(), text + "\n\nThe will rises out of the seated body and takes its old shape in the air.\n\n\"Words are cheap. Show me.\"",
			[["Face the test", func():
				hud.close_dialog()
				_raise_echo()], ["Not yet", hud.close_dialog]])
		return
	var body := "The will settles back into the seated body and bows its head -- to you.\n\n\"Take it. All of it. There will never be another.\"\n\n" + _grants_text()
	var ttl := str(_L().heavenly(heaven).get("title", ""))
	if ttl != "":
		body += "\n(And a name: %s.)" % ttl
	hud.open_dialog("The Heavenly Inheritance of " + master.trim_prefix("the ").capitalize(), body, [["Accept the legacy", func():
		hud.close_dialog()
		Game.claim_inheritance(_key, master, grants)
		_L().claim_heavenly(heaven)
		Game.note_place("Received the HEAVENLY inheritance of " + master)
		remove_from_group("discoverable")
		_tint(_body, Color(0.5, 0.5, 0.48))
		_aura.light_energy = 0.0
		if _tell:
			_tell.queue_free()
			_tell = null
	], ["Leave it for now", hud.close_dialog]])


func _raise_echo() -> void:
	## the master's echo: the strongest thing this floor knows, made into the
	## master's shadow and four times as hard to kill
	var E: Dictionary = _rules().get("echo", {})
	var best := ""
	var hp_best := -1
	for eid in Game.enemies:
		var st: Dictionary = Game.enemies[eid]
		if bool(st.get("passive", false)) or int(st.get("floor", -1)) != int(level.def.get("depth", Game.depth)):
			continue
		if int(st.get("hp", 0)) > hp_best:
			hp_best = int(st.get("hp", 0))
			best = str(eid)
	if best == "":
		best = str(E.get("fallback", "goblin_chief"))
	var e = load("res://scripts/actors/Enemy.gd").new()
	e.setup(level, {"type": best, "cell": cell + Vector2i(0, 2)})
	e.stats = (e.stats as Dictionary).duplicate()
	e.stats["name"] = "Echo of " + master.trim_prefix("the ").capitalize()
	e.stats["hp"] = int(float(e.stats.get("hp", 50)) * float(E.get("hp_mult", 4.0)))
	if e.stats.has("damage"):
		e.stats["damage"] = int(round(float(e.stats["damage"]) * float(E.get("damage_mult", 1.6))))
	e.stats["boss"] = true
	e.hp = int(e.stats["hp"])
	level.add_child(e)
	e.global_position = global_position + Vector3(0, 0, 2.2)
	_echo = e
	Game.message.emit("The echo of %s steps down from the seat." % master)
	Game.log_event("heaven_trial", {"id": heaven})


func _trial_won() -> void:
	if _L() == null or heaven == "":
		return
	_L().trials_passed[heaven] = true
	Game.message.emit("The echo bows, and comes apart like smoke. The seated will is waiting for you.")
	Game.log_event("heaven_trial_won", {"id": heaven})


func _condense(hud) -> void:
	## round 43: the legacy, pressed into a crystal for later or for sale
	hud.close_dialog()
	var id: String = Game.condense_inheritance(_key, master, needs_realm, grants)
	if id == "":
		return
	remove_from_group("discoverable")
	_tint(_body, Color(0.32, 0.36, 0.34))
	_aura.light_energy = 0.0


func _grants_text() -> String:
	var parts := []
	for id in grants.get("items", {}):
		parts.append(Game.item_name(str(id)))
	for tid in grants.get("techniques", []):
		parts.append(str(Game.technique_defs.get(str(tid), {}).get("name", tid)))
	if grants.has("qi"):
		parts.append("%d qi" % int(grants["qi"]))
	return "(You will receive: %s.)" % ", ".join(parts) if parts.size() > 0 else ""


func _tint(n: Node, c: Color) -> void:
	if n is MeshInstance3D:
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.emission_enabled = true
		m.emission = c * 0.25
		n.material_override = m
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
