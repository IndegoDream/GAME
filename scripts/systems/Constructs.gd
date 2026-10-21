extends "res://scripts/systems/GameSystem.gd"
## Round 154 (Robert: "golems, mechs, ships"). Things you BUILD that serve you:
##   * golems  -- six materials (clay to meteor). Research Animation, gather the materials, and one joins your
##                contracts (it does not use a beast slot). Their kinds, forms and awakenings work like any contract's.
##   * mech    -- wear the Power Frame as a suit (Mech Suit research, a key, or the Party page): much tougher and
##                harder-hitting, a little slower, and it drinks qi while worn.
##   * voyages -- a skiff (Skiff Yard research) carries a golem crew away on a timed trip; they come home laden.
## Fair pay: everything is earned in play; nothing is bought or exclusive.

var cfg := {}
var mech_on := false
var voyage := {}
var built := 0
var _shell: Node3D
var _t := 0.0
var _drain_acc := 0.0


func setup(game) -> void:
	super.setup(game)
	var d = G._load_json("res://data/constructs.json", {})
	cfg = d if d is Dictionary else {}


func reset() -> void:
	mech_on = false
	voyage = {}
	built = 0
	_shell = null


func save_state() -> Dictionary:
	return {"mech": mech_on, "voyage": voyage, "built": built}


func load_state(d: Dictionary) -> void:
	mech_on = bool(d.get("mech", false))
	var v = d.get("voyage", {})
	voyage = v if v is Dictionary else {}
	built = int(d.get("built", 0))


func _research(feature: String) -> bool:
	var r = G.sys("research")
	return r != null and r.unlocked(feature)


func golems() -> Dictionary:
	return cfg.get("golems", {})


func is_construct(c: Dictionary) -> bool:
	return bool(c.get("construct", false))


# ---- golems -------------------------------------------------------------------------------------------------------

func golem_count() -> int:
	var n := 0
	for c in G.contracts:
		if is_construct(c):
			n += 1
	return n


func golem_cap() -> int:
	var n := 0
	if not _research("animate"):
		return 0
	for row in cfg.get("golem_cap", [[0, 1]]):
		if G.realm >= int(row[0]):
			n = int(row[1])
	return n


func build_block(kind: String) -> String:
	## "" when it can be built now, else why not
	var g: Dictionary = golems().get(kind, {})
	if g.is_empty():
		return I18n.t("No such golem.")
	if not _research("animate"):
		return I18n.t("Research Animation first (the swarm, Constructs).")
	if G.realm < int(g.get("realm", 0)):
		return I18n.t("Needs %s.") % G.realm_name_of(int(g.get("realm", 0)))
	if golem_count() >= golem_cap():
		return I18n.t("You can keep %d golems for now.") % golem_cap()
	var miss := []
	for id in g.get("needs", {}):
		var have: int = G.count(str(id))
		if have < int(g["needs"][id]):
			miss.append("%s %d/%d" % [G.item_name(str(id)), have, int(g["needs"][id])])
	if not miss.is_empty():
		return I18n.t("Needs: ") + ", ".join(miss)
	return ""


func needs_text(kind: String) -> String:
	var g: Dictionary = golems().get(kind, {})
	var parts := []
	for id in g.get("needs", {}):
		parts.append("%d %s" % [int(g["needs"][id]), G.item_name(str(id))])
	return ", ".join(parts)


func build(kind: String) -> String:
	var why: String = build_block(kind)
	if why != "":
		return why
	var g: Dictionary = golems()[kind]
	for id in g.get("needs", {}):
		G.remove_item(str(id), int(g["needs"][id]))
	var nm := str(g.get("fname", kind.capitalize()))
	var taken: Array = G.contracts.map(func(c): return str(c.get("name", "")))
	var base := nm
	var k := 2
	while nm in taken:
		nm = "%s %s" % [base, ["", "", "II", "III", "IV", "V", "VI", "VII", "VIII"][mini(k, 8)]]
		k += 1
	var nb := {"species": str(g["species"]), "name": nm, "bond": 0.0, "tier": 0, "out": false, "construct": true}
	G.contracts.append(nb)
	built += 1
	G.message.emit(I18n.t("The swarm breathes a spark into the %s. %s opens its eyes.") % [I18n.t(str(g.get("name", ""))).to_lower(), nm])
	G.jingle("discovery")
	G.log_event("golem_built", {"kind": kind})
	G.note_place(I18n.t("Built ") + nm)
	G.familiar_changed.emit()
	G.stats_changed.emit()
	return ""


# ---- the mech -----------------------------------------------------------------------------------------------------

func mech_block() -> String:
	if not _research("mech"):
		return I18n.t("Research the Mech Suit first (the swarm, Constructs).")
	if not mech_on and G.qi < G.qi_to_next() * float(cfg.get("mech", {}).get("min_qi_frac", 0.1)):
		return I18n.t("Not enough qi to wake the frame.")
	return ""


func toggle_mech() -> String:
	var why: String = mech_block()
	if mech_on:
		why = ""
	if why != "":
		return why
	mech_on = not mech_on
	_drain_acc = 0.0
	G.jingle("trial" if mech_on else "levelup")
	G.log_event("mech_on" if mech_on else "mech_off", {})
	G.stats_changed.emit()
	sync_visual()
	return I18n.t("The frame closes around you.") if mech_on else I18n.t("The frame opens and lets you out.")


func effects() -> Array:
	var out := []
	if mech_on:
		out.append(cfg.get("mech", {}).get("effect", {}))
	return out


func sync_visual() -> void:
	var tree = G.get_tree()
	if tree == null:
		return
	var pl = tree.get_first_node_in_group("player")
	if pl == null:
		_shell = null
		return
	if mech_on and (_shell == null or not is_instance_valid(_shell) or _shell.get_parent() != pl):
		_shell = _build_shell()
		pl.add_child(_shell)
	elif not mech_on and _shell != null:
		if is_instance_valid(_shell):
			_shell.queue_free()
		_shell = null


func _build_shell() -> Node3D:
	var s := Node3D.new()
	s.name = "MechShell"
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.55, 0.6, 0.68)
	steel.metallic = 0.8
	steel.roughness = 0.35
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color(0.5, 0.9, 1.0)
	glow.emission_enabled = true
	glow.emission = Color(0.4, 0.85, 1.0)
	glow.emission_energy_multiplier = 2.0
	var parts := [
		[Vector3(0.62, 0.22, 0.4), Vector3(0, 1.45, 0), steel],        # shoulder yoke
		[Vector3(0.34, 0.5, 0.14), Vector3(0, 1.05, 0.2), steel],      # chest plate
		[Vector3(0.12, 0.12, 0.05), Vector3(0, 1.1, 0.28), glow],      # the reactor
		[Vector3(0.22, 0.2, 0.22), Vector3(-0.42, 1.5, 0), steel],     # pauldrons
		[Vector3(0.22, 0.2, 0.22), Vector3(0.42, 1.5, 0), steel],
		[Vector3(0.16, 0.5, 0.16), Vector3(-0.15, 0.4, 0), steel],     # greaves
		[Vector3(0.16, 0.5, 0.16), Vector3(0.15, 0.4, 0), steel],
	]
	for p in parts:
		var m := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = p[0]
		m.mesh = b
		m.position = p[1]
		m.material_override = p[2]
		s.add_child(m)
	return s


# ---- voyages ------------------------------------------------------------------------------------------------------

func voyages() -> Array:
	return cfg.get("voyages", [])


func crew_candidates() -> Array:
	## golem contracts at rest and not the lead
	var out := []
	for i in G.contracts.size():
		var c: Dictionary = G.contracts[i]
		if is_construct(c) and not bool(c.get("away", false)) and not is_same(c, G.familiar):
			out.append(i)
	return out


func voyage_left() -> float:
	if voyage.is_empty():
		return 0.0
	return maxf(0.0, float(voyage.get("end", 0.0)) - G._now())


func voyage_block(vid: String) -> String:
	if not _research("voyage"):
		return I18n.t("Research the Skiff Yard first (the swarm, Constructs).")
	if not voyage.is_empty():
		return I18n.t("The skiff is already out.")
	var v := _voyage_def(vid)
	if v.is_empty():
		return I18n.t("No such voyage.")
	if G.realm < int(v.get("realm", 0)):
		return I18n.t("Needs %s.") % G.realm_name_of(int(v.get("realm", 0)))
	if crew_candidates().is_empty():
		return I18n.t("A golem must crew the skiff (one at rest, not your lead).")
	return ""


func _voyage_def(vid: String) -> Dictionary:
	for v in voyages():
		if str(v.get("id", "")) == vid:
			return v
	return {}


func start_voyage(vid: String, crew_index: int = -1) -> String:
	var why: String = voyage_block(vid)
	if why != "":
		return why
	var cands: Array = crew_candidates()
	var ci: int = crew_index if crew_index in cands else int(cands[0])
	var c: Dictionary = G.contracts[ci]
	var v: Dictionary = _voyage_def(vid)
	c["away"] = true
	c["voyage"] = true
	if bool(c.get("out", false)):
		c["out"] = false
	var now: float = G._now()
	voyage = {"id": vid, "crew": str(c.get("name", "")), "start": now, "end": now + float(v.get("hours", 1.0)) * 3600.0}
	G.log_event("voyage_start", {"id": vid})
	G.message.emit(I18n.t("%s casts off on the %s.") % [str(c.get("name", "")), I18n.t(str(v.get("name", ""))).to_lower()])
	G.familiar_changed.emit()
	G.stats_changed.emit()
	return ""


func _crew_contract() -> Dictionary:
	for c in G.contracts:
		if bool(c.get("voyage", false)):
			return c
	return {}


func finish_voyage() -> Array:
	## the skiff is home: rewards. Returns the lines.
	var out := []
	var v: Dictionary = _voyage_def(str(voyage.get("id", "")))
	var hours: float = float(v.get("hours", 1.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = int(voyage.get("start", 0.0)) + 7
	for id in v.get("loot", {}):
		var r: Array = v["loot"][id]
		var n: int = rng.randi_range(int(r[0]), int(r[1]))
		if n > 0 and G.items.has(str(id)):
			G.add_item(str(id), n, false)
			out.append("%d %s" % [n, G.item_name(str(id))])
	var gold: int = int(hours * float(v.get("gold_per_hour", 30)))
	G.gold += gold
	out.append(I18n.t("%d gold") % gold)
	var ins: float = float(v.get("insight", 0))
	if ins > 0.0:
		G.gain_insight(ins)
	var cn := str(voyage.get("crew", ""))
	var c: Dictionary = _crew_contract()
	if not c.is_empty():
		c.erase("away")
		c.erase("voyage")
		G.grow_bond(2.0 * hours, c)
	voyage = {}
	G.log_event("voyage_done", {"id": str(v.get("id", ""))})
	G.message.emit(I18n.t("%s brings the skiff home: %s.") % [cn, ", ".join(out)])
	G.sfx("coins")
	G.familiar_changed.emit()
	G.stats_changed.emit()
	return out


func tick(delta: float) -> void:
	_t += delta
	if mech_on:
		_drain_acc += delta
		if _drain_acc >= 1.0:
			var per_sec: float = G.qi_to_next() * float(cfg.get("mech", {}).get("drain_per_min", 0.06)) / 60.0
			G.qi = maxf(G.qi - per_sec * _drain_acc, 0.0)
			_drain_acc = 0.0
			if G.qi <= 0.01:
				mech_on = false
				G.message.emit(I18n.t("The frame runs dry of qi and opens."))
				sync_visual()
				G.stats_changed.emit()
	if _t >= 3.0:
		_t = 0.0
		if mech_on and (_shell == null or not is_instance_valid(_shell)):
			sync_visual()
		if not voyage.is_empty() and voyage_left() <= 0.0:
			finish_voyage()
