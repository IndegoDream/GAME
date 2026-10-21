extends "res://scripts/systems/GameSystem.gd"
## The Heirloom set (round 120). Robert, 2026-10-13: a quest to build a full
## set of unique armour that grows with the wearer, whose first recipe is given
## by the ignition and each piece giving the recipe for the next, until every
## craft in the game has been used.
##
## Ignition: ask a smith about an heirloom (smithing 2), or forge a piece with
## all three of motif, trim and dye chosen. That opens the quest in the log
## (kind "heirloom") and shows the recipe for piece 1 at the smith. Making a
## piece (smith's dialog) uses what the recipe asks and opens the next.
## Growth: the set is Dormant, Awakened, Ascendant by (your realm + growth);
## growth comes from kills while two or more pieces are worn and from feeding
## it rare materials. The set bonus is per worn piece (times the stage) and a
## full-set bonus. Pieces keep their own designed look. Numbers: heirloom.json.

var cfg := {}
var started := false
var made := []                # piece indexes made (in order)
var growth := 0.0
var _fx: Array = []
var _fx_key := ""
const QID := "heirloom:line"


func setup(game) -> void:
	super.setup(game)
	var d = G._load_json("res://data/heirloom.json", {})
	cfg = d if d is Dictionary else {}


func reset() -> void:
	started = false
	made = []
	growth = 0.0
	_fx = []
	_fx_key = ""


func save_state() -> Dictionary:
	return {"started": started, "made": made, "growth": growth}


func load_state(d: Dictionary) -> void:
	started = bool(d.get("started", false))
	made = (d.get("made", []) as Array).map(func(x): return int(x))
	growth = float(d.get("growth", 0.0))
	_fx_key = ""


func pieces() -> Array:
	return cfg.get("pieces", [])


func next_index() -> int:
	return made.size()


func complete() -> bool:
	return started and made.size() >= pieces().size()


# ---- the quest ----------------------------------------------------------------

func _quest_def() -> Dictionary:
	var stages := []
	var i := 0
	for p in pieces():
		stages.append({"log": I18n.t("Make the heirloom %s. %s") % [str(p["name"]).to_lower(), str(p["recipe"])], "goal": {"event": {"kind": "heirloom_piece", "match": {"n": i}}}, "say": ""})
		i += 1
	return {"id": QID, "name": str(cfg.get("name", "The Heirloom")), "kind": "heirloom", "giver": "the smith", "pitch": "", "stages": stages, "unlock": {},
		"endings": {"default": {"say": "Seven pieces, and every craft in them. It will grow as you do.", "reward": {"qi_kills": 12}}}}


func ignite(why: String = "") -> String:
	## returns what to tell the player ("" if it was already begun)
	if started:
		return ""
	var Q = G.sys("quests")
	started = true
	made = []
	if Q != null:
		Q.legacy_defs[QID] = _quest_def()
		Q.accept(QID)
	G.log_event("heirloom_start", {"why": why})
	G.message.emit("The line begins. The smith can show you the first recipe.")
	return I18n.t("The smith lays out a thin, old sheet of designs. \"A set that grows with whoever wears it. We start with the cuirass.\"")


func can_ignite_smithing() -> bool:
	return G.skill_level("smithing") >= int(cfg.get("ignite_smithing", 2))


func ignite_by_design(design: Dictionary) -> void:
	## a forged piece with motif, trim and dye all chosen
	if started or G.skill_level("smithing") < 3:
		return
	var n := 0
	for k in ["motif", "trim", "dye"]:
		if not (str(design.get(k, "")) in G.Design.PLAIN):
			n += 1
	if n >= 3:
		ignite("design")


# ---- making ----------------------------------------------------------------------

func needs_text(i: int) -> String:
	var p: Dictionary = pieces()[i]
	var f: Dictionary = G.gear_data()["families"][str(p["family"])]
	var bits := ["%d %s" % [int(f.get("needs", 1)), G.item_name(str(p["stock"]))]]
	if p.has("gem"):
		bits.append("1 %s" % G.item_name(str(p["gem"])))
	for it in p.get("prep", {}):
		bits.append("%d %s" % [int(p["prep"][it]), G.item_name(str(it))])
	bits.append(I18n.t("%d gold") % int(p.get("gold", 0)))
	return "%s -- %s (%s %d)" % [p["name"], ", ".join(bits), G.skill_name(str(p["craft"])), int(p["skill"])]


func why_not(i: int) -> String:
	var p: Dictionary = pieces()[i]
	var f: Dictionary = G.gear_data()["families"][str(p["family"])]
	if G.skill_level(str(p["craft"])) < int(p["skill"]):
		return I18n.t("Needs %s %d.") % [G.skill_name(str(p["craft"])), int(p["skill"])]
	var pc := str(p.get("prep_craft", ""))
	if pc != "" and not G.skill_known(pc):
		return I18n.t("You don't know %s.") % G.skill_name(pc)
	if G.count(str(p["stock"])) < int(f.get("needs", 1)):
		return I18n.t("Needs %d %s.") % [int(f.get("needs", 1)), G.item_name(str(p["stock"]))]
	if p.has("gem") and G.count(str(p["gem"])) < 1:
		return I18n.t("Needs %s.") % G.item_name(str(p["gem"]))
	for it in p.get("prep", {}):
		var have: int = G.count(str(it)) - G.equipped_count(str(it))
		if str(it) == str(p["stock"]):
			have -= int(f.get("needs", 1))
		if have < int(p["prep"][it]):
			return I18n.t("Needs %d %s.") % [int(p["prep"][it]), G.item_name(str(it))]
	if G.gold < int(p.get("gold", 0)):
		return I18n.t("Needs %d gold.") % int(p.get("gold", 0))
	return ""


func make(i: int, design: Dictionary = {}) -> Dictionary:
	## {ok, item, text}
	if not started or i != next_index() or i >= pieces().size():
		return {"ok": false, "text": "That isn't the next piece."}
	var w := why_not(i)
	if w != "":
		return {"ok": false, "text": w}
	var p: Dictionary = pieces()[i]
	var dc := "jewel" if str(G.gear_data()["families"][str(p["family"])].get("kind", "")) == "jewel" else "forge"
	if not G.Design.is_plain(design):
		var dw: String = G.Design.check(dc, design, G.skill_level(str(p["craft"])))
		if dw != "":
			return {"ok": false, "text": dw}
	var f: Dictionary = G.gear_data()["families"][str(p["family"])]
	G.gold -= int(p.get("gold", 0))
	G.remove_item(str(p["stock"]), int(f.get("needs", 1)))
	if p.has("gem"):
		G.remove_item(str(p["gem"]), 1)
	for it in p.get("prep", {}):
		G.remove_item(str(it), int(p["prep"][it]))
	G.Design.take(dc, design)
	var q := maxi(G.craft_quality({"skill": str(p["craft"]), "difficulty": i}, "balanced"), 1)
	var pd: Dictionary
	if dc == "jewel":
		pd = G.jewel_def(str(p["stock"]), str(p.get("gem", "")), str(p["family"]))
	else:
		pd = G.piece_def(str(p["stock"]), str(p["family"]), {})
	pd.erase("drop")
	pd = G.Design.apply(dc, pd, design)
	pd["name"] = "Heirloom %s" % str(p["name"])
	pd["heirloom"] = i + 1
	pd["set"] = "heirloom"
	pd["effect"] = G.merge_effects(pd.get("effect", {}), {"qi_mult": 1.01})
	if pd.has("ward"):
		pd["ward"] = snappedf(float(pd["ward"]) * 1.15, 0.1)
	pd["desc"] = I18n.t("%s  Piece %d of %d of %s. It grows with whoever wears it.") % [str(pd.get("desc", "")), i + 1, pieces().size(), str(cfg.get("name", I18n.t("the Heirloom")))]
	pd["qrank"] = q
	var id: String = G._register_custom("c27_", G._q_scaled(pd, q))
	G.add_item(id, 1, false)
	made.append(i)
	_fx_key = ""
	G.add_skill_xp(str(p["craft"]), 14.0 + 4.0 * i, "heirloom")
	var pc := str(p.get("prep_craft", ""))
	if pc != "" and pc != str(p["craft"]):
		G.add_skill_xp(pc, 10.0, "heirloom")
	var hin := {str(p["stock"]): int(f.get("needs", 1))}
	if p.has("gem"):
		hin[str(p["gem"])] = 1
	for pit in p.get("prep", {}):
		hin[str(pit)] = int(hin.get(str(pit), 0)) + int(p["prep"][pit])
	G.craftbook_note("heirloom", id, hin, str(p["craft"]), {"n": i, "q": q})
	G.log_event("heirloom_piece", {"n": i, "item": id})
	G.message.emit("You make %s." % G.item_name(id))
	return {"ok": true, "item": id, "text": str(p.get("done", "It is made."))}


# ---- growth ---------------------------------------------------------------------

func worn_count() -> int:
	var n := 0
	for s in G.gear_slots():
		var sl := str(s[0])
		if sl == "weapon":
			continue
		var id: String = G.worn(sl)
		if id != "" and G.has_item_def(id) and G.item_def(id).has("heirloom"):
			n += 1
	return n


func stage_index() -> int:
	var pts := float(G.realm) + growth / 100.0 * 3.0
	var idx := 0
	var st: Array = cfg.get("stages", [])
	for i in st.size():
		if pts >= float(st[i].get("from", 0)):
			idx = i
	return idx


func stage_name() -> String:
	return str(cfg.get("stages", [{"name": "Dormant"}])[stage_index()].get("name", "Dormant"))


func feed_options() -> Array:
	var out := []
	var minv := int(cfg.get("feed_min_value", 40))
	for id in G.inventory:
		var sid := str(id)
		if G.count(sid) > 0 and str(G.item_def(sid).get("type", "")) == "material" and int(G.item_def(sid).get("value", 0)) >= minv:
			out.append(sid)
	return out


func feed(item: String) -> String:
	if worn_count() < 1:
		return I18n.t("Wear at least one piece for it to take anything.")
	if G.count(item) <= 0:
		return ""
	var v := float(G.item_def(item).get("value", 0))
	G.remove_item(item, 1)
	growth += v / 4.0
	_fx_key = ""
	return I18n.t("The set drinks in the %s. It is %s now.") % [G.item_name(item).to_lower(), stage_name()]


func on_event(kind: String, _d: Dictionary) -> void:
	if kind == "kill" and started:
		var n := worn_count()
		if n >= 2:
			growth += float(cfg.get("growth_per_kill", 0.25)) * float(n) / 7.0


func effects() -> Array:
	var n := worn_count()
	if n <= 0:
		return []
	var key := "%d|%d" % [n, stage_index()]
	if key == _fx_key:
		return _fx
	_fx_key = key
	var m := float(cfg.get("stages", [{"mult": 1.0}])[stage_index()].get("mult", 1.0))
	var pp: Dictionary = cfg.get("per_piece", {})
	var e := {"hp_mult": 1.0 + float(pp.get("hp_mult", 0.0)) * n * m, "qi_mult": 1.0 + float(pp.get("qi_mult", 0.0)) * n * m, "ward": float(pp.get("ward", 0.0)) * n * m}
	if n >= pieces().size():
		var fs: Dictionary = cfg.get("full_set", {})
		e["damage_taken"] = 1.0 + float(fs.get("damage_taken", 0.0)) * m
		e["loot_luck"] = float(fs.get("loot_luck", 0.0)) * m
	_fx = [e]
	return _fx


func status_line() -> String:
	if not started:
		return ""
	if complete():
		return I18n.t("%s: complete. %s (%d worn). Growth %d.") % [str(cfg.get("name", "")), stage_name(), worn_count(), int(growth)]
	return I18n.t("%s: %d of %d pieces made. %s (%d worn).") % [str(cfg.get("name", "")), made.size(), pieces().size(), stage_name(), worn_count()]
