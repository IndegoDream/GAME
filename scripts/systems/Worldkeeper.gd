extends "res://scripts/systems/GameSystem.gd"
## Your own world (2026-11-06). Robert chose: "Own pocket world -- a personal realm you shape: pick its biome, place
## buildings and shrines, seed resources ... it grows with your cultivation. Becomes your online world later."
##
## Opens when the main quest makes you a Worldkeeper (or you reach Immortal Ascension another way). Reached by
## waystone ("Your World"). Its keeper's lectern (an NPC, role "keeper") is where you shape it:
##   - name it, and choose its land (the look of any Land you have walked)
##   - build on its plots: a house, a shrine, a pond, a grove, a herb garden, a mine, an orchard, a lantern court
##   - it grows with you: more plots open as your realm climbs
##   - a daily tithe: what your world grew since you last collected (gold, herbs, ore), capped at a day's worth
## The level is drawn from this state each time you enter (scripts/world/KeeperGen.gd). Online-ready: the state
## is a plain dictionary the online world can load as its seed.

var name_ := ""
var land := "whisperwood"
var plots := {}              # "0".."11" -> kind
var last_tithe := 0.0
const KINDS := ["house", "shrine", "pond", "grove", "garden", "mine", "orchard", "lanterns"]


func reset() -> void:
	name_ = ""
	land = "whisperwood"
	plots = {}
	last_tithe = 0.0


func save_state() -> Dictionary:
	return {"name": name_, "land": land, "plots": plots, "last_tithe": last_tithe}


func load_state(d: Dictionary) -> void:
	name_ = str(d.get("name", ""))
	land = str(d.get("land", "whisperwood"))
	plots = (d.get("plots", {}) as Dictionary).duplicate()
	last_tithe = float(d.get("last_tithe", 0.0))


func unlocked() -> bool:
	return G.titles.has("Worldkeeper") or G.realm >= 10


func world_name() -> String:
	return name_ if name_ != "" else I18n.t("Your World")


func plot_count() -> int:
	## four plots to start, one more for every realm past Immortal Ascension, up to twelve
	return clampi(4 + maxi(G.realm - 9, 0), 4, 12)


func kind_name(k: String) -> String:
	return {"house": I18n.t("a house"), "shrine": I18n.t("a shrine"), "pond": I18n.t("a pond"), "grove": I18n.t("a grove"), "garden": I18n.t("a herb garden"),
		"mine": I18n.t("a mine"), "orchard": I18n.t("an orchard"), "lanterns": I18n.t("a lantern court")}.get(k, k)


func plot_name(i: int) -> String:
	return [I18n.t("the north meadow"), I18n.t("the east rise"), I18n.t("the south bank"), I18n.t("the west hollow"),
		I18n.t("the far north"), I18n.t("the far east"), I18n.t("the far south"), I18n.t("the far west"),
		I18n.t("the north-east corner"), I18n.t("the south-east corner"), I18n.t("the south-west corner"), I18n.t("the north-west corner")][clampi(i, 0, 11)]


func build(i: int, kind: String) -> String:
	if i < 0 or i >= plot_count():
		return I18n.t("That plot hasn't opened yet -- your world grows as you do.")
	if not (kind in KINDS):
		return ""
	var cost := build_cost(kind)
	if G.gold < cost:
		return I18n.t("Shaping %s costs %d gold.") % [kind_name(kind), cost]
	G.gold -= cost
	plots[str(i)] = kind
	G.log_event("keeper_build", {"plot": i, "kind": kind})
	G.stats_changed.emit()
	return I18n.t("You shape %s on %s. The land settles round it as if it had always been there.") % [kind_name(kind), plot_name(i)]


func clear_plot(i: int) -> String:
	if not plots.has(str(i)):
		return ""
	var k := str(plots[str(i)])
	plots.erase(str(i))
	G.stats_changed.emit()
	return I18n.t("%s returns to meadow.") % kind_name(k).capitalize()


func build_cost(kind: String) -> int:
	return int({"house": 400, "shrine": 900, "pond": 300, "grove": 300, "garden": 350, "mine": 700, "orchard": 350, "lanterns": 250}.get(kind, 400)) * maxi(G.realm - 8, 1)


func lands_walked() -> Array:
	var out := []
	var places: Dictionary = G.journal.get("places", {})
	for rid in G.FrontierGen.data().get("regions", {}):
		var r: Dictionary = G.FrontierGen.region(str(rid))
		if r.has("_grown") and (places.has("frontier:" + str(rid)) or str(rid) == land):
			out.append(str(rid))
	if not ("whisperwood" in out):
		out.push_front("whisperwood")
	return out


func set_land(rid: String) -> String:
	if not (rid in lands_walked()):
		return I18n.t("You can only shape your world like a Land you have walked.")
	land = rid
	return I18n.t("Your world takes on the look of %s.") % G.FrontierGen.name_of("frontier:" + rid)


# ---- the tithe: what it grew while you were away -----------------------------------------------

func tithe_preview() -> Dictionary:
	var now := Time.get_unix_time_from_system()
	var days := clampf((now - last_tithe) / 86400.0, 0.0, 1.0) if last_tithe > 0.0 else 1.0
	var out := {"gold": 0}
	for k in plots.values():
		match str(k):
			"house": out["gold"] = int(out["gold"]) + int(120 * days * maxi(G.realm - 8, 1))
			"garden": out["spirit_herb"] = int(out.get("spirit_herb", 0)) + int(round(4 * days))
			"orchard": out["healing_salve"] = int(out.get("healing_salve", 0)) + int(round(2 * days))
			"mine": out["iron_ore"] = int(out.get("iron_ore", 0)) + int(round(5 * days))
			"shrine": out["qi_pill"] = int(out.get("qi_pill", 0)) + int(round(2 * days))
	return out


func collect_tithe() -> String:
	var t := tithe_preview()
	last_tithe = Time.get_unix_time_from_system()
	var bits := []
	for k in t:
		var n := int(t[k])
		if n <= 0:
			continue
		if k == "gold":
			G.add_item("gold", n, false)
			bits.append(I18n.t("%d gold") % n)
		elif G.items.has(k):
			G.add_item(str(k), n, false)
			bits.append("%d %s" % [n, G.item_name(str(k))])
	G.stats_changed.emit()
	return I18n.t("Your world gives back: %s.") % ", ".join(bits) if not bits.is_empty() else I18n.t("Nothing has grown yet. Build, and come back tomorrow.")


func on_event(kind: String, _d: Dictionary) -> void:
	if unlocked() and (kind == "levelup" or kind == "title" or kind == "realm_up"):
		_open_door()


func tick(_delta: float) -> void:
	if not G.is_inside_tree():
		return
	if unlocked() and G.sys("travel") != null and not G.sys("travel").stones.has("realm:own"):
		_open_door()


func _open_door() -> void:
	var T = G.sys("travel")
	if T != null and not T.stones.has("realm:own"):
		T.stones["realm:own"] = {"name": world_name(), "when": Time.get_unix_time_from_system()}
		G.message.emit(I18n.t("WORLDKEEPER: a world of your own has opened. Travel there from any waystone (\"%s\").") % world_name())
		G.stats_changed.emit()
