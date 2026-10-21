extends "res://scripts/systems/GameSystem.gd"
## The swarm's research tree (round 40). Robert, 2026-10-04: "while growing
## your own swarm it would be nice to be able to utilize them as a utility and
## extra function in the game -- build its own skill tree, be able to design
## different nanites for different functions, cost qi and resources to research
## and connect while meditating ... wetware upgrades, hardware upgrades,
## cybernetics and power armor come into play in late game. The game should
## feel more techy as we get further on but qi and equipment still matter.
## Build it modular."
##
## ONE ENGINE, ONE DATA FILE (data/tech_tree.json): add a node there and it's
## in the game -- the menu draws it, the save keeps it, the effects apply.
## Node kinds:
##   design   researched, then CONNECTED into the swarm's bandwidth (grows with
##            the swarm tier); runs on qi upkeep; can be TUNED with a material
##   passive  always on once researched
##   unlock   opens a feature (a split mind, the swarm working in the background)
##   install  wetware, hardware, cybernetics, power armour: costs BODY LOAD,
##            which grows with your realm and how many nodes you've made radiant
## Research costs sitting time (Research as your focus), a share of a step of
## qi (paid when you begin) and materials. Connecting, tuning and installing
## are done while you sit.

var data := {}
var researched := {}      # id -> true
var progress := {}        # id -> seconds
var current := ""
var connected := {}       # design id -> {"tune": material id or ""}
var installed := {}       # install id -> true
var _eff := []
var _eff_dirty := true
var _eff_starved := false


func setup(game) -> void:
	super.setup(game)
	data = load_json("res://data/tech_tree.json")
	var dr = G._load_json("res://data/drafts/tech_tree.json", {})        # Dev's words (brief "tech_tree")
	if dr is Dictionary:
		for it in dr.get("items", []):
			if it is Dictionary and data.get("nodes", {}).has(str(it.get("id", ""))):
				for k in ["name", "desc"]:
					if str(it.get(k, "")).strip_edges() != "":
						data["nodes"][str(it["id"])][k] = str(it[k]).strip_edges()


func reset() -> void:
	researched = {}
	progress = {}
	current = ""
	connected = {}
	installed = {}
	_eff_dirty = true


func save_state() -> Dictionary:
	return {"researched": researched, "progress": progress, "current": current, "connected": connected, "installed": installed}


func load_state(d: Dictionary) -> void:
	for k in ["researched", "progress", "connected", "installed"]:
		var v = d.get(k, {})
		set(k, v if v is Dictionary else {})
	current = str(d.get("current", ""))
	for nid in connected.keys():
		if not (connected[nid] is Dictionary):
			connected[nid] = {"tune": ""}
	_eff_dirty = true


func dirty() -> void:
	_eff_dirty = true
	G.stats_changed.emit()


# ---- the tree ------------------------------------------------------------------------------

func node(nid: String) -> Dictionary:
	return data.get("nodes", {}).get(nid, {})


func branch(bid: String) -> Dictionary:
	return data.get("branches", {}).get(bid, {})


func branch_nodes(bid: String) -> Array:
	var out := []
	for nid in data.get("nodes", {}):
		if str(data["nodes"][nid].get("branch", "")) == bid:
			out.append(str(nid))
	return out


func gate_missing(nid: String) -> Array:
	var gt: Dictionary = node(nid).get("gate", {})
	var out := []
	if G.nanite_tier() < int(gt.get("tier", 0)):
		out.append(I18n.t("swarm tier %d (%s)") % [int(gt["tier"]), G.tier_name(int(gt["tier"]))])
	if G.realm < int(gt.get("realm", 0)):
		out.append(G.realm_name_of(int(gt["realm"])))
	for r in node(nid).get("requires", []):
		if not researched.has(str(r)):
			out.append(str(node(str(r)).get("name", r)))
	return out


func cost_qi(nid: String) -> float:
	return float(node(nid).get("cost", {}).get("qi", 0.0)) * G.qi_to_next()


func cost_seconds(nid: String) -> float:
	return float(node(nid).get("cost", {}).get("seconds", 600))


func can_research(nid: String) -> String:
	var n := node(nid)
	if n.is_empty():
		return I18n.t("There's no such design.")
	if researched.has(nid):
		return I18n.t("%s is already known.") % n["name"]
	if current == nid:
		return I18n.t("You're already working on %s.") % n["name"]
	var miss := gate_missing(nid)
	if not miss.is_empty():
		return I18n.t("%s needs %s.") % [n["name"], ", ".join(miss)]
	if progress.has(nid):
		return ""                       # (begun before: the price is paid)
	for it in n.get("cost", {}).get("items", {}):
		if G.count(str(it)) < int(n["cost"]["items"][it]):
			return I18n.t("%s needs %d %s (you have %d).") % [n["name"], int(n["cost"]["items"][it]), G.item_name(str(it)), G.count(str(it))]
	if G.qi < cost_qi(nid):
		return I18n.t("%s needs %d qi to begin (you have %d).") % [n["name"], int(cost_qi(nid)), int(G.qi)]
	return ""


func start(nid: String) -> String:
	var why := can_research(nid)
	if why != "":
		return why
	var n := node(nid)
	if not progress.has(nid):
		for it in n.get("cost", {}).get("items", {}):
			G.remove_item(str(it), int(n["cost"]["items"][it]))
		G.qi -= cost_qi(nid)
		progress[nid] = 0.0
	current = nid
	G.log_event("research_start", {"id": nid})
	G.stats_changed.emit()
	return I18n.t("Research: %s. Sit with Research as your focus (the Mind page) to work on it.") % n["name"]


func stop() -> String:
	if current == "":
		return ""
	var nm := str(node(current).get("name", current))
	current = ""
	G.stats_changed.emit()
	return I18n.t("You set %s aside (what you've done is kept).") % nm


func speed() -> float:
	return G.tech_effect("research_speed", 1.0) * G.tech_effect("focus_mult", 1.0)


func push(secs: float) -> bool:
	## true when the current research finished
	if current == "" or secs <= 0.0:
		return false
	var nid := current
	progress[nid] = float(progress.get(nid, 0.0)) + secs * speed()
	if float(progress[nid]) < cost_seconds(nid):
		return false
	progress.erase(nid)
	researched[nid] = true
	current = ""
	var n := node(nid)
	G.log_event("researched", {"id": nid, "branch": str(n.get("branch", ""))})
	G.bump("researched")
	G.integrate(20.0 + cost_seconds(nid) / 120.0, "research")        # (the swarm grows by being used)
	G.jingle("discovery")
	var how: String = {"design": "Connect it on the Swarm page while you sit.", "install": "Install it on the Swarm page while you sit -- if your body can bear the load.",
		"passive": "It's part of your swarm now.", "unlock": "Your mind can do something new."}.get(str(n.get("kind", "")), "")
	G.big_moment.emit(I18n.t("RESEARCHED: %s") % n.get("name", nid), "%s\n\n%s%s" % [str(n.get("desc", "")), ("(" + G.effect_text(n.get("effect", {})) + ")\n\n") if n.has("effect") else "", how])
	dirty()
	return true


func meditate(secs: float, shares: Dictionary, aid: float) -> void:
	var r := float(shares.get("research", 0.0))
	if r <= 0.0:
		return
	var eff: float = G.sys("mind").split_efficiency(shares)
	push(secs * aid * r * eff)


func background(secs: float, shares: Dictionary) -> void:
	var r := float(shares.get("research", 0.0))
	if r > 0.0:
		push(secs * r)


func unlocked(feature: String) -> bool:
	for nid in researched:
		if str(node(str(nid)).get("unlock", "")) == feature:
			return true
	return false


# ---- designs: bandwidth, upkeep, tuning -------------------------------------------------------

func bandwidth_cap() -> int:
	var n := 0
	for row in data.get("bandwidth", [[0, 2]]):
		if G.nanite_tier() >= int(row[0]):
			n = int(row[1])
	return n


func tuning(mat: String) -> Dictionary:
	return data.get("tunings", {}).get(mat, {})


func design_bandwidth(nid: String) -> int:
	var t := tuning(str(connected.get(nid, {}).get("tune", "")))
	return maxi(1, int(node(nid).get("bandwidth", 1)) + int(t.get("bandwidth", 0)))


func design_upkeep(nid: String) -> int:
	var t := tuning(str(connected.get(nid, {}).get("tune", "")))
	return maxi(0, int(node(nid).get("upkeep", 0)) + int(t.get("upkeep", 0)))


func bandwidth_used() -> int:
	var n := 0
	for nid in connected:
		n += design_bandwidth(str(nid))
	return n


func upkeep_points() -> int:
	var n := 0
	for nid in connected:
		n += design_upkeep(str(nid))
	for nid in installed:
		n += int(node(str(nid)).get("upkeep", 0))
	return n


func connect_design(nid: String, sitting: bool) -> String:
	var n := node(nid)
	if str(n.get("kind", "")) != "design" or not researched.has(nid):
		return I18n.t("You haven't designed that.")
	if connected.has(nid):
		return I18n.t("%s is already part of your swarm.") % n["name"]
	if not sitting:
		return I18n.t("You can only rewire the swarm while you sit still (meditate first).")
	var bw := maxi(1, int(n.get("bandwidth", 1)))
	if bandwidth_used() + bw > bandwidth_cap():
		return I18n.t("Not enough bandwidth: %s needs %d, you have %d free (it grows with your swarm's tier).") % [n["name"], bw, bandwidth_cap() - bandwidth_used()]
	connected[nid] = {"tune": ""}
	G.log_event("design_connected", {"id": nid})
	dirty()
	return I18n.t("%s joins your swarm.") % n["name"]


func disconnect_design(nid: String) -> String:
	if not connected.has(nid):
		return ""
	connected.erase(nid)
	dirty()
	return I18n.t("%s goes dormant.") % node(nid).get("name", nid)


func tune(nid: String, mat: String, sitting: bool) -> String:
	var n := node(nid)
	var t := tuning(mat)
	if not connected.has(nid):
		return I18n.t("Connect it first.")
	if t.is_empty():
		return I18n.t("That material won't tune a swarm.")
	if not sitting:
		return I18n.t("Tuning needs you sitting still (meditate first).")
	var need := int(t.get("need", 1))
	if G.count(mat) < need:
		return I18n.t("Tuning %s needs %d %s.") % [n["name"], need, G.item_name(mat)]
	var old := str(connected[nid].get("tune", ""))
	var bw_after := bandwidth_used() - design_bandwidth(nid) + maxi(1, int(n.get("bandwidth", 1)) + int(t.get("bandwidth", 0)))
	if bw_after > bandwidth_cap():
		return I18n.t("That tuning would take more bandwidth than you have.")
	G.remove_item(mat, need)
	connected[nid]["tune"] = mat
	G.log_event("design_tuned", {"id": nid, "mat": mat, "was": old})
	dirty()
	return "%s, %s: %s." % [n["name"], str(t.get("name", "")).to_lower(), str(t.get("desc", ""))]


# ---- installs: body load ------------------------------------------------------------------------

func load_cap() -> int:
	var L: Dictionary = data.get("load", {})
	var c = G.sys("cleansing")
	var rad := float(c.radiant_count()) if c else 0.0
	return int(L.get("base", 2)) + floori(G.realm / 2.0) * int(L.get("per_two_realms", 1)) + int(floor(rad * float(L.get("per_radiant", 0.34))))


func load_used() -> int:
	var n := 0
	for nid in installed:
		n += int(node(str(nid)).get("load", 1))
	return n


func install(nid: String, sitting: bool) -> String:
	var n := node(nid)
	if str(n.get("kind", "")) != "install" or not researched.has(nid):
		return I18n.t("You haven't researched that.")
	if installed.has(nid):
		return I18n.t("It's already part of you.")
	if not sitting:
		return I18n.t("Installing needs you sitting still (meditate first).")
	for r in n.get("requires", []):
		if str(node(str(r)).get("kind", "")) == "install" and not installed.has(str(r)):
			return I18n.t("%s fits onto %s -- install that first.") % [n["name"], node(str(r)).get("name", r)]
	var ld := int(n.get("load", 1))
	if load_used() + ld > load_cap():
		return I18n.t("Your body can't bear it: %s weighs %d, you have %d free. (Load grows with your realm and with radiant nodes.)") % [n["name"], ld, load_cap() - load_used()]
	installed[nid] = true
	G.log_event("installed", {"id": nid})
	G.sfx("equip", 0.8)
	dirty()
	return I18n.t("%s is part of you now.") % n["name"]


func uninstall(nid: String) -> String:
	if not installed.has(nid):
		return ""
	installed.erase(nid)
	var also := []
	for other in installed.keys():                 # what was mounted on it comes off too
		if nid in (node(str(other)).get("requires", []) as Array):
			installed.erase(other)
			also.append(str(node(str(other)).get("name", other)))
	dirty()
	return I18n.t("%s comes out.%s") % [node(nid).get("name", nid), (" So does " + ", ".join(also) + ".") if not also.is_empty() else ""]


# ---- what it all gives --------------------------------------------------------------------------

func scaled(effect: Dictionary, mult: float, add: Dictionary = {}) -> Dictionary:
	var out := {}
	for k in effect:
		var v := float(effect[k])
		if k in G.ADDITIVE_KEYS or str(k).begins_with("craft_") or k in ["gather_bonus"]:
			out[k] = v * mult
		else:
			out[k] = 1.0 + (v - 1.0) * mult
	for k in add:
		out[k] = float(out.get(k, 0.0)) + float(add[k])
	return out


func effects() -> Array:
	var starved: bool = G.sys("synergy") != null and G.sys("synergy").starved
	if not _eff_dirty and starved == _eff_starved:
		return _eff
	_eff_dirty = false
	_eff_starved = starved
	var out := []
	for nid in researched:
		var n := node(str(nid))
		if str(n.get("kind", "")) == "passive" and n.has("effect"):
			out.append(n["effect"])
	for nid in connected:
		var n2 := node(str(nid))
		if starved and design_upkeep(str(nid)) > 0:
			continue
		var t := tuning(str(connected[nid].get("tune", "")))
		out.append(scaled(n2.get("effect", {}), float(t.get("mult", 1.0)), t.get("add", {})))
	for nid in installed:
		var n3 := node(str(nid))
		if starved and int(n3.get("upkeep", 0)) > 0:
			continue
		out.append(n3.get("effect", {}))
	_eff = out
	return out


func state_of(nid: String) -> String:
	## "installed" / "connected" / "known" / "researching" / "begun" / "open" / "locked"
	if installed.has(nid):
		return "installed"
	if connected.has(nid):
		return "connected"
	if researched.has(nid):
		return "known"
	if current == nid:
		return "researching"
	if progress.has(nid):
		return "begun"
	return "open" if gate_missing(nid).is_empty() else "locked"
