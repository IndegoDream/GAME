extends "res://scripts/systems/GameSystem.gd"
## The crafting journal (round 137). Robert, 2026-10-17: "Build a recipe for every item created. As we learn what
## items can do allow it to fill out the bestiary and herbology / crafting supply -- show what each item can add to a
## craft and likely complementary [materials] ... make this a good crafting journal."
##
## What it keeps (saved): `recipes` -- one row for everything you have made (bench recipe, forged piece, worked mix,
## an Heirloom piece), with what went in, the skill, how many times and the best quality; `used` -- how many times each
## material has gone into something you made; `drops` -- what each foe has actually dropped for you.
## What it works out (never saved): how much the journal tells you about a material (seen, handled, understood), what
## the material adds to a craft, which materials go well with it, where it comes from, and the bestiary's pages.
## Numbers and words: data/craftbook.json. The page: Hub.fill_craft.

var cfg := {}
var recipes := {}        # key -> {kind, item, name, inputs{id:n}, skill, times, best_q, design, fam, stock, gem, makes, first}
var used := {}           # material id -> times used in something you made
var drops := {}          # foe type -> {item id: times}
var order := []          # recipe keys, oldest first


func setup(game) -> void:
	super.setup(game)
	var d = G._load_json("res://data/craftbook.json", {})
	cfg = d if d is Dictionary else {}


func reset() -> void:
	recipes = {}
	used = {}
	drops = {}
	order = []


func save_state() -> Dictionary:
	return {"recipes": recipes, "used": used, "drops": drops, "order": order}


func load_state(d: Dictionary) -> void:
	recipes = d.get("recipes", {}) if d.get("recipes", {}) is Dictionary else {}
	used = d.get("used", {}) if d.get("used", {}) is Dictionary else {}
	drops = d.get("drops", {}) if d.get("drops", {}) is Dictionary else {}
	order = []
	for k in d.get("order", []):
		if recipes.has(str(k)):
			order.append(str(k))
	for k in recipes:
		if not (k in order):
			order.append(str(k))


# ---- recording ---------------------------------------------------------------------------------

func _look_of(design: Dictionary) -> String:
	if design.is_empty():
		return ""
	var parts := []
	for k in design:
		parts.append("%s=%s" % [k, design[k]])
	parts.sort()
	return ",".join(parts)


func note_made(kind: String, item: String, inputs: Dictionary, skill: String, meta: Dictionary = {}) -> void:
	## something came out of a craft: keep how it was made
	var design: Dictionary = meta.get("design", {}) if meta.get("design", {}) is Dictionary else {}
	var key := ""
	match kind:
		"recipe":
			key = "recipe:%s|%s" % [str(meta.get("makes", G.base_id(item))), _look_of(design)]
		"forge":
			key = "forge:%s|%s|%s|%s" % [str(meta.get("fam", "")), str(meta.get("stock", "")), str(meta.get("gem", "")), _look_of(design)]
		"heirloom":
			key = "heirloom:%d" % int(meta.get("n", 0))
		_:
			key = "%s:%s|%s" % [kind, str(meta.get("sig", "")), _look_of(design)]
	var fresh := not recipes.has(key)
	var row: Dictionary = recipes.get(key, {})
	if fresh:
		row = {"kind": kind, "inputs": inputs.duplicate(), "skill": skill, "times": 0, "best_q": 0, "first": int(G.playtime)}
		for k in ["fam", "stock", "gem", "makes", "n", "gold"]:
			if meta.has(k):
				row[k] = meta[k]
		if not design.is_empty():
			row["design"] = design.duplicate()
	row["item"] = item
	row["name"] = G.item_name(item)
	row["times"] = int(row.get("times", 0)) + 1
	row["best_q"] = maxi(int(row.get("best_q", 0)), int(meta.get("q", 0)))
	recipes[key] = row
	order.erase(key)
	order.append(key)
	for id in inputs:
		var b = G.base_id(str(id))
		used[b] = int(used.get(b, 0)) + 1
	if fresh:
		G.message.emit("CRAFT JOURNAL: the recipe for %s is written down." % G.item_name(item))


func note_drop(foe: String, item: String) -> void:
	var b = G.base_id(item)
	var t := str(G.item_def(b).get("type", ""))
	if t != "material" and t != "consumable":
		return
	var d: Dictionary = drops.get(foe, {})
	d[b] = int(d.get(b, 0)) + 1
	drops[foe] = d


# ---- the recipe pages --------------------------------------------------------------------------

func recipe_keys() -> Array:
	var out := order.duplicate()
	out.reverse()
	return out


func recipe_view(key: String) -> Dictionary:
	var r: Dictionary = recipes.get(key, {})
	if r.is_empty():
		return {}
	var parts := []
	var have_all := true
	for id in r.get("inputs", {}):
		var need := int(r["inputs"][id])
		var have: int = G.count(str(id))
		if have < need:
			have_all = false
		parts.append({"id": str(id), "name": G.item_name(str(id)), "need": need, "have": have})
	var kn: Dictionary = cfg.get("kind_names", {})
	var remakeable := str(r.get("kind", "")) in ["recipe", "forge"]
	return {"key": key, "name": str(r.get("name", "?")), "kind": str(kn.get(str(r.get("kind", "")), r.get("kind", ""))), "skill": str(r.get("skill", "")),
		"inputs": parts, "have_all": have_all, "times": int(r.get("times", 1)), "best_q": int(r.get("best_q", 0)), "design": r.get("design", {}),
		"gold": int(r.get("gold", 0)), "remake": remakeable, "item": str(r.get("item", ""))}


func remake(key: String) -> String:
	## make it again, the same way (bench recipes and forged pieces)
	var r: Dictionary = recipes.get(key, {})
	if r.is_empty():
		return ""
	var design: Dictionary = r.get("design", {}) if r.get("design", {}) is Dictionary else {}
	match str(r.get("kind", "")):
		"recipe":
			for rc in G.recipes:
				if str(rc.get("makes", "")) == str(r.get("makes", "")):
					var res: Dictionary = G.craft_attempt(rc, "balanced", -1.0, -1.0, design)
					return str(res.get("text", ""))
			return I18n.t("The recipe is no longer known.")
		"forge":
			var res2: Dictionary = G.forge_piece(str(r.get("fam", "")), str(r.get("stock", "")), str(r.get("gem", "")), -1.0, -1.0, design)
			return str(res2.get("text", ""))
	return ""


# ---- materials: what the journal knows ---------------------------------------------------------

func shelf_of(id: String) -> String:
	var b = G.base_id(id)
	var m: Dictionary = cfg.get("shelf_of", {})
	if m.has(b):
		return str(m[b])
	var t = G.material_traits(b)
	if t.has("nano"):
		return "tech"
	if t.has("vital") or t.has("living") or t.has("supple"):
		return "herbs"
	return "reagents"


func shelf_name(sh: String) -> String:
	return str(cfg.get("shelves", {}).get(sh, {}).get("name", sh.capitalize()))


func shelf_blurb(sh: String) -> String:
	return str(cfg.get("shelves", {}).get(sh, {}).get("blurb", ""))


func shelves() -> Array:
	return ["herbs", "ores", "gems", "beast", "reagents", "tech"]


func materials_on(sh: String) -> Array:
	var out := []
	for id in (cfg.get("shelf_of", {}) as Dictionary).keys():
		if str(cfg["shelf_of"][id]) == sh:
			out.append(str(id))
	out.sort_custom(func(a, b): return G.item_name(str(a)) < G.item_name(str(b)))
	return out


func seen(id: String) -> bool:
	return G.journal["items"].has(G.base_id(id)) or G.count(id) > 0


func mastered(id: String) -> bool:
	var K: Dictionary = cfg.get("know", {})
	var b = G.base_id(id)
	return int(used.get(b, 0)) >= int(K.get("used_for_mastery", 3)) or _craft_skill_top() >= int(K.get("skill_for_mastery", 5))


func _craft_skill_top() -> int:
	var best := 0
	for sk in ["smithing", "alchemy", "jewelcrafting", "herbalism"]:
		best = maxi(best, G.skill_level(sk))
	return best


func level_of(id: String) -> int:
	## 0 never seen, 1 seen, 2 handled (its traits are known), 3 understood (what it does, and what suits it)
	if not seen(id):
		return 0
	if not G.knows_material(id):
		return 1
	return 3 if mastered(id) else 2


func level_name(lv: int) -> String:
	return ["Not found", "Seen", "Handled", "Understood"][clampi(lv, 0, 3)]


func trait_lines(id: String, with_effect: bool) -> Array:
	## [{name, level, desc}] strongest first
	var t = G.material_traits(id)
	var td: Dictionary = G.craft_data().get("traits", {})
	var out := []
	var top: Dictionary = G._top_traits(t, 6)
	for tr in top:
		var def: Dictionary = td.get(tr, {})
		var line := {"id": str(tr), "name": G.trait_name(str(tr)), "level": int(t[tr]), "desc": ""}
		if with_effect:
			line["desc"] = str(def.get("desc", ""))
		out.append(line)
	return out


func complements(id: String) -> Dictionary:
	## {"named": [{id, name, why}], "hidden": n} -- materials whose traits pair with this one's in a synergy
	var K: Dictionary = cfg.get("know", {})
	var t = G.material_traits(id)
	var b = G.base_id(id)
	var found := {}
	var unseen_ids := {}
	for sy in G.craft_data().get("synergies", []):
		var a := str(sy["a"])
		var bb := str(sy["b"])
		for pair in [[a, bb], [bb, a]]:
			if int(t.get(pair[0], 0)) <= 0:
				continue
			for m2 in (cfg.get("shelf_of", {}) as Dictionary).keys():
				if str(m2) == b:
					continue
				var t2 = G.material_traits(str(m2))
				var lv := int(t2.get(pair[1], 0))
				if lv <= 0:
					continue
				if seen(str(m2)):
					var score := lv * 10 + int(t.get(pair[0], 0))
					if not found.has(m2) or int(found[m2]["score"]) < score:
						found[m2] = {"id": str(m2), "name": G.item_name(str(m2)), "score": score,
							"why": "%s + %s: %s" % [G.trait_name(str(pair[0])), G.trait_name(str(pair[1])), str(sy.get("name", ""))]}
				else:
					unseen_ids[m2] = true
	var arr := found.values()
	arr.sort_custom(func(x, y): return int(x["score"]) > int(y["score"]))
	return {"named": arr.slice(0, int(K.get("complements_shown", 4))), "hidden": unseen_ids.size()}


func element_note(id: String) -> String:
	var e = G.material_element(id)
	var g: String = str(G.GENERATES.get(e, ""))
	var o: String = str(G.OVERCOMES.get(e, ""))
	var feeds_from := ""
	for k in G.GENERATES:
		if str(G.GENERATES[k]) == e:
			feeds_from = str(k)
	return I18n.t("%s: smooth with %s and %s materials; works against %s.") % [e.capitalize(), feeds_from, g, o]


func uses_of(id: String) -> Array:
	## what it goes into: bench recipes and formulas
	var b = G.base_id(id)
	var out := []
	for r in G.recipes:
		if (r.get("needs", {}) as Dictionary).has(b):
			var n1 = G.item_name(str(r["makes"]))
			if not (n1 in out):
				out.append(n1)
	for f in G.craft_data().get("formulas", []):
		if (f.get("needs", {}) as Dictionary).has(b):
			var nm = G.item_name(str(f.get("makes", "")))
			if not (nm in out) and (G.knows_formula(str(f["id"])) or mastered(b)):
				out.append(nm)
	return out


func found_in(id: String) -> Array:
	var e: Dictionary = G.journal["items"].get(G.base_id(id), {})
	return (e.get("where", []) as Array).duplicate()


func dropped_by(id: String) -> Array:
	var b = G.base_id(id)
	var out := []
	for foe in drops:
		if (drops[foe] as Dictionary).has(b):
			out.append(str(G.enemies.get(foe, {}).get("name", foe)))
	out.sort()
	return out


func material_card(id: String) -> Dictionary:
	var lv := level_of(id)
	var c := {"id": id, "name": G.item_name(id) if lv > 0 else "???", "level": lv, "level_name": level_name(lv), "shelf": shelf_of(id), "count": G.count(id),
		"made_with": int(used.get(G.base_id(id), 0))}
	if lv <= 0:
		return c
	c["desc"] = str(G.item_def(id).get("desc", ""))
	c["found"] = found_in(id)
	c["dropped_by"] = dropped_by(id)
	c["uses"] = []
	if lv >= 2:
		c["element"] = G.material_element(id)
		c["traits"] = trait_lines(id, lv >= 3)
		var cp := complements(id)
		c["pairs"] = cp["named"]
		c["pairs_hidden"] = cp["hidden"]
	if lv >= 3:
		c["element_note"] = element_note(id)
		c["uses"] = uses_of(id)
		c["adds"] = G.traits_to_effect(G.material_traits(id), G.material_potency(id) * 0.5)
	return c


func shelf_progress(sh: String) -> Array:
	var have := 0
	var all := materials_on(sh)
	for id in all:
		if seen(str(id)):
			have += 1
	return [have, all.size()]


# ---- the bestiary ------------------------------------------------------------------------------

func foes() -> Array:
	var out := []
	for id in G.enemies:
		var d: Dictionary = G.enemies[id]
		if bool(d.get("rival", false)) or str(id).begins_with("rival_"):
			continue
		out.append(str(id))
	out.sort_custom(func(a, b):
		var fa := int(G.enemies[a].get("floor", 0))
		var fb := int(G.enemies[b].get("floor", 0))
		return fa < fb or (fa == fb and str(G.enemies[a].get("name", a)) < str(G.enemies[b].get("name", b))))
	return out


func foe_met(id: String) -> bool:
	return int(G.kills.get(id, 0)) > 0


func foe_card(id: String) -> Dictionary:
	var K: Dictionary = cfg.get("know", {})
	var d: Dictionary = G.enemies.get(id, {})
	var k := int(G.kills.get(id, 0))
	var c := {"id": id, "met": k > 0, "kills": k, "floor": int(d.get("floor", 0)), "name": str(d.get("name", id)) if k > 0 else "???"}
	if k <= 0:
		return c
	if k >= int(K.get("bestiary_stats_at", 3)):
		c["hp"] = int(d.get("hp", 0))
		c["damage"] = int(d.get("damage", 0))
		c["speed"] = float(d.get("speed", 0.0))
		c["boss"] = bool(d.get("boss", false))
	var seen_drops := []
	for it in (drops.get(id, {}) as Dictionary):
		seen_drops.append(str(it))
	seen_drops.sort()
	c["drops"] = seen_drops
	if k >= int(K.get("bestiary_table_at", 10)):
		var table := []
		for it in (d.get("loot", {}) as Dictionary):
			if str(it) != "gold" and not str(it).begins_with("random_"):
				table.append(str(it))
		table.sort()
		c["table"] = table
	return c


func foes_met() -> Array:
	var all := foes()
	var n := 0
	for id in all:
		if foe_met(str(id)):
			n += 1
	return [n, all.size()]
