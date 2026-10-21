extends RefCounted
## Round 120 (Robert: "make the nanites and ki sections more intuitive. Build
## a tutorial option that is optional"). Nothing here ever opens by itself.
##   * lessons from data/guide.json -- short, plain, one step per screen
##   * next_hint(page): one plain line "what to do next" for a menu page,
##     worked out from the game's real state (so it changes as you play)
##   * the hints strip can be turned off (flag "guide:off")
## Hub.gd draws it: a ? Help button on every page, a Guide page, a step card.

static var _data := {}

const PAGE_LESSON := {"You": "qi", "Spirit": "qi", "Meridians": "meridians", "Mind": "mind", "Swarm": "nanites", "Pack": "fighting", "Path": "paths"}


static func data() -> Dictionary:
	if _data.is_empty():
		var f := FileAccess.open("res://data/guide.json", FileAccess.READ)
		if f != null:
			var j = JSON.parse_string(f.get_as_text())
			if j is Dictionary:
				_data = j
	return _data


static func lessons() -> Array:
	return data().get("lessons", [])


static func lesson(id: String) -> Dictionary:
	for l in lessons():
		if str(l.get("id", "")) == id:
			return l
	return {}


static func lesson_for_page(page: String) -> String:
	return str(PAGE_LESSON.get(page, ""))


static func hints_on() -> bool:
	return not Game.has_flag("guide:off")


static func set_hints(on: bool) -> void:
	if on:
		Game.flags.erase("guide:off")
	else:
		Game.set_flag("guide:off")


static func next_hint(page: String) -> String:
	## "" when there is nothing useful to say
	match page:
		"Meridians":
			return _meridian_hint()
		"Mind":
			return _mind_hint()
		"Swarm":
			return _swarm_hint()
		"Path":
			return _path_hint()
		"Spirit":
			return I18n.t("Elements grow by what you do -- skills you practise, points you open, what you eat. At %d an element is active and its gift switches on.") % int(Game.AFFINITY_ACTIVE)
	return ""


static func _meridian_hint() -> String:
	if Game.lattice.size() >= 36:
		return I18n.t("All 36 points are open. Cleanse them on the Mind page for the next layer of strength.")
	if Game.lattice_focus == "" or Game.lattice.has(Game.lattice_focus):
		return I18n.t("NEXT: click a point on the map to make it your focus -- then sit (M) and it opens.")
	var pct := int(Game.point_fraction(Game.lattice_focus) * 100.0)
	if not Game.sitting:
		return I18n.t("NEXT: sit (M) with your Mind focus on Cultivate -- your focus point is %d%% open and only opens while you sit.") % pct
	return I18n.t("Sitting: your focus point is %d%% open. Stay put, or press M to stand.") % pct


static func _mind_hint() -> String:
	var M = Game.sys("mind")
	if M == null:
		return ""
	if not Game.sitting:
		return I18n.t("NEXT: sit (M). What the sitting is spent on (%s) is set by the Focus buttons below.") % M.summary()
	return I18n.t("You are sitting: time goes to %s. Change it with the Focus buttons.") % M.summary()


static func _swarm_hint() -> String:
	var R = Game.sys("research")
	if R == null:
		return ""
	if R.current != "":
		var nm := str(R.node(R.current).get("name", R.current))
		var M = Game.sys("mind")
		if M != null and M.mode != "research" and float(M.shares().get("research", 0.0)) <= 0.0:
			return I18n.t("NEXT: '%s' only moves while you sit with Research as your focus -- press 'Make Research my focus', then sit (M).") % nm
		if not Game.sitting:
			return I18n.t("NEXT: sit (M) -- '%s' is being researched and only moves while you sit.") % nm
		return I18n.t("Researching '%s'. Stay seated (or stand with M).") % nm
	# something known but not yet running?
	for bid in R.data.get("branches", {}):
		for nid in R.branch_nodes(str(bid)):
			var st: String = R.state_of(str(nid))
			var kind := str(R.node(str(nid)).get("kind", ""))
			if st == "known" and kind in ["design", "install"]:
				return I18n.t("NEXT: sit (M), then press %s on '%s' -- it is researched but not running yet.") % ["Connect" if kind == "design" else I18n.t("Install"), str(R.node(str(nid)).get("name", nid))]
	for bid2 in R.data.get("branches", {}):
		for nid2 in R.branch_nodes(str(bid2)):
			if R.state_of(str(nid2)) in ["open", "begun"]:
				return I18n.t("NEXT: press Research on a card marked 'open' (try '%s'), then sit (M) with Research as your focus.") % str(R.node(str(nid2)).get("name", nid2))
	return I18n.t("Nothing to research yet -- grow your swarm (run hot, parry, absorb nanite shards) and your realm to open more cards.")


static func _path_hint() -> String:
	var P = Game.sys("paths")
	if P == null:
		return ""
	if P.primary == "":
		return I18n.t("NEXT: pick a Path below. It is free the first time, and every road is open.")
	var nn: Dictionary = P.next_needs(P.primary)
	if nn.is_empty():
		return I18n.t("You have reached the top of your road. A second path gives half of what a path gives.")
	if not bool(nn.get("realm_ok", true)):
		return I18n.t("NEXT: your %s road wants the realm of %s before rank %d -- cultivate.") % [str(P.def(P.primary).get("name", "")), Game.realm_name_of(int(nn["realm_need"])), int(nn["rank"])]
	for n in nn.get("needs", []):
		if int(n["have"]) < int(n["need"]):
			return I18n.t("NEXT: %s -- %d of %d for rank %d (%s).") % [str(n["label"]), int(n["have"]), int(n["need"]), int(nn["rank"]), str(nn["name"])]
	return ""
