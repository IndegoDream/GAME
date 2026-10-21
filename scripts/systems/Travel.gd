extends "res://scripts/systems/GameSystem.gd"
## Travel (round 63): waystones and quick travel. Robert, 2026-10-05: "We can
## introduce quick travel options for the deeper levels since the safe zones
## will be farther apart. Allow the user to quick travel to any location they
## have conquered and found the quick travel [stone] for."
##
##   a waystone   every place you can go back to has one (Waystone.gd): Eliet
##                by the fountain, the valley by its gate, each town of the
##                deep, and each dungeon floor beside the way down -- past its
##                master, so you find it by winning. Walk up to one and it's
##                ATTUNED.
##   conquered    a dungeon floor counts once its master has fallen; Eliet,
##                the valley and the towns count as soon as you've attuned them.
##   travelling   from any waystone, at once. From anywhere else (the menu's
##                Quick travel) only when it's safe -- no foe close, not hurt a
##                moment ago, not in a trial or an arena -- and it takes a few
##                seconds of gathering yourself: a blow breaks it.
## Every number is in data/travel.json.

signal attuned(level_id: String)
signal channel_changed(left: float, total: float)     # left < 0: stopped

var cfg := {}
var stones := {}          # level id -> {"name", "when"}
var channel_to := ""      # where you're gathering yourself to go ("" none)
var channel_left := 0.0
var channel_total := 0.0
var _hurt_at := 0.0
var trips := 0


func setup(game) -> void:
	super.setup(game)
	cfg = load_json("res://data/travel.json")


func load_json(p: String) -> Dictionary:
	return G._load_json(p, {}) if G else {}


func reset() -> void:
	stones = {}
	channel_to = ""
	channel_left = 0.0
	trips = 0


func save_state() -> Dictionary:
	return {"stones": stones, "trips": trips}


func load_state(d: Dictionary) -> void:
	stones = d.get("stones", {}) if d.get("stones", {}) is Dictionary else {}
	trips = int(d.get("trips", 0))


func _n(key: String, dflt: float) -> float:
	return float(cfg.get(key, dflt))


# ---- which places --------------------------------------------------------------------------

static func eligible(level_id: String, theme: String) -> bool:
	## a place a waystone stands in: Eliet, the valley, the towns, the dungeon floors
	if level_id.contains(":") or level_id == "":
		return false
	if level_id in ["village", "valley"]:
		return true
	return level_id.begins_with("floor") and level_id.substr(5).is_valid_int() and theme in ["dungeon", "settlement", "village", "wilds", ""]


func is_town(level_id: String) -> bool:
	if level_id in ["village", "valley"]:
		return true
	var d: Dictionary = G.load_level_def(level_id) if G.level_exists(level_id) else {}
	return str(d.get("theme", "")) in ["settlement", "village"]


func conquered(level_id: String) -> bool:
	if is_town(level_id):
		return true
	var dep: int = G.floor_depth(level_id)
	return dep > 0 and float(G.counters.get("boss_floor:%d" % dep, 0.0)) > 0.0


func attune(level_id: String, place_name: String) -> bool:
	if stones.has(level_id):
		return false
	stones[level_id] = {"name": place_name, "when": Time.get_unix_time_from_system()}
	G.log_event("waystone", {"id": level_id})
	if conquered(level_id):
		G.message.emit("WAYSTONE ATTUNED -- %s. You can travel here from any waystone." % place_name)
	else:
		G.message.emit("WAYSTONE ATTUNED -- %s. Its master still lives: beat it, and you can travel here." % place_name)
	var words := inscription(level_id)
	if words != "":
		G.message.emit("Carved on the stone: \"%s\"" % words)
	attuned.emit(level_id)
	G.stats_changed.emit()
	return true


func inscription(level_id: String) -> String:
	## what's carved on a waystone: Dev's lines (writing room brief "waystone_words")
	var dev: Dictionary = G.draft_texts("waystone_words")
	var opts := []
	for k in dev:
		if str(dev[k]).strip_edges() != "":
			opts.append(str(dev[k]).strip_edges())
	if opts.is_empty():
		return ""
	opts.sort()
	return str(opts[absi(hash(level_id)) % opts.size()])


func destinations() -> Array:
	## [{id, name, depth, town, ready}] -- every attuned stone, Eliet first, then by depth
	var out := []
	for lid in stones:
		var s := str(lid)
		if not G.level_exists(s):
			continue
		out.append({"id": s, "name": str(stones[lid].get("name", s)), "depth": G.floor_depth(s) if s.begins_with("floor") else (0 if s == "village" else 0),
			"town": is_town(s), "ready": conquered(s), "here": s == str(G.current_level)})
	out.sort_custom(func(a, b):
		var ka: int = -2 if a["id"] == "village" else (-1 if a["id"] == "valley" else int(a["depth"]))
		var kb: int = -2 if b["id"] == "village" else (-1 if b["id"] == "valley" else int(b["depth"]))
		return ka < kb)
	return out


# ---- may you go now? ------------------------------------------------------------------------

func why_not(from_stone: bool) -> String:
	## "" when you can travel right now, else why not
	if channel_to != "":
		return I18n.t("You're already gathering yourself to travel.")
	if G.arena_active() or str(G.current_level).begins_with("tribulation:") or str(G.current_level).begins_with("trial:"):
		return I18n.t("Not in the middle of a trial.")
	if from_stone:
		return ""
	if not bool(cfg.get("from_menu", true)):
		return I18n.t("Find a waystone to travel from.")
	if Time.get_unix_time_from_system() - G.last_hurt_at < _n("calm_s", 8.0):
		return I18n.t("Not straight after a blow -- catch your breath.")
	var tree: SceneTree = G.get_tree()
	var p = tree.get_first_node_in_group("player") if tree else null
	if p:
		for e in tree.get_nodes_in_group("enemy"):
			if e is Node3D and e.is_inside_tree() and e.get("_dead") != true and e.get("_dummy") != true and (e as Node3D).global_position.distance_to(p.global_position) < _n("safe_radius", 14.0):
				return I18n.t("Not with foes this close.")
	return ""


func travel(level_id: String, from_stone: bool) -> String:
	## start the trip: "" when it's under way, else why not
	var w := why_not(from_stone)
	if w != "":
		return w
	if not stones.has(level_id):
		return I18n.t("You haven't attuned that waystone.")
	if not conquered(level_id):
		return I18n.t("Its master still lives.")
	if level_id == str(G.current_level):
		return I18n.t("You're already here.")
	var secs := 0.0 if from_stone else _n("channel_s", 2.5)
	if secs <= 0.0:
		_go(level_id)
		return ""
	channel_to = level_id
	channel_left = secs
	channel_total = secs
	_hurt_at = G.last_hurt_at
	G.message.emit("You gather yourself for %s..." % str(stones[level_id].get("name", level_id)))
	channel_changed.emit(channel_left, channel_total)
	return ""


func cancel(why: String = "") -> void:
	if channel_to == "":
		return
	channel_to = ""
	channel_left = 0.0
	if why != "":
		G.message.emit(why)
	channel_changed.emit(-1.0, channel_total)


func tick(delta: float) -> void:
	if channel_to == "":
		return
	if G.last_hurt_at > _hurt_at:
		cancel("The blow breaks your concentration -- no travel.")
		return
	channel_left -= delta
	channel_changed.emit(maxf(channel_left, 0.0), channel_total)
	if channel_left <= 0.0:
		var to := channel_to
		channel_to = ""
		channel_changed.emit(-1.0, channel_total)
		_go(to)


func _go(level_id: String) -> void:
	trips += 1
	G.log_event("quick_travel", {"to": level_id, "from": str(G.current_level)})
	G.sfx("waystone", 0.9)
	G.go_to(level_id, "waystone")
