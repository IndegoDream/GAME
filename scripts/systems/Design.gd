extends RefCounted
## Designing what you make (rounds 119-120). Robert, 2026-10-13: "During
## blacksmithing allow for player to design the look of the gear and it can
## potentially increase or decrease the items bonuses or attributes in unique
## ways. Same for all crafting ... bonuses and or ignite a quest to build a
## full set of a unique armor that could potentially grow with the wearer."
##
## A design is {group_key: option_id}. Each craft section in
## data/design_traits.json lists its _groups: [[plural, key, label]...].
## check() says what is missing (skill, material); take() uses the material up
## once the piece is made; apply() works the design into a piece or a draught.
## Gear sections: "forge" (motif/trim/dye), "jewel" (cut/setting/finish).
## Draught sections: "alchemy", "medicine" (vial/prep, tincture, seal), where
## herbalism skill unlocks the tinctures.

static var _cfg := {}
const PLAIN := ["", "plain", "none", "natural", "standard", "round"]


static func cfg() -> Dictionary:
	if _cfg.is_empty():
		var d = Game._load_json("res://data/design_traits.json", {})
		_cfg = d if d is Dictionary else {}
	return _cfg


static func section(craft: String) -> Dictionary:
	return cfg().get(craft, {})


static func has_section(craft: String) -> bool:
	return not section(craft).is_empty()


static func groups(craft: String) -> Array:
	## [[plural, key, label]...]
	var g = section(craft).get("_groups", null)
	if g is Array:
		return g
	return [["motifs", "motif", "Motif"], ["trims", "trim", "Trim"], ["dyes", "dye", "Dye"]]


static func _opt(craft: String, group: String, id: String) -> Dictionary:
	return (section(craft).get(group, {}) as Dictionary).get(id, {})


static func options(craft: String, group: String) -> Array:
	## [[id, option]...] in file order
	var out := []
	var g: Dictionary = section(craft).get(group, {})
	for k in g:
		out.append([str(k), g[k]])
	return out


static func is_plain(design: Dictionary) -> bool:
	for k in design:
		if not (str(design[k]) in PLAIN):
			return false
	return true


static func check(craft: String, design: Dictionary, skill: int) -> String:
	for gr in groups(craft):
		var id := str(design.get(gr[1], ""))
		if id == "" or id in PLAIN:
			continue
		var o := _opt(craft, gr[0], id)
		if o.is_empty():
			return I18n.t("Nobody knows that design.")
		var sk_id := str(o.get("skill", ""))
		var have := Game.skill_level(sk_id) if sk_id != "" else skill
		if have < int(o.get("min_skill", 0)):
			return I18n.t("%s needs %s %d.") % [str(o.get("name", id)), Game.skill_name(sk_id if sk_id != "" else _craft_skill(craft)), int(o.get("min_skill", 0))]
		var cost: Dictionary = o.get("cost", {})
		for item in cost:
			if Game.count(str(item)) - Game.equipped_count(str(item)) < int(cost[item]):
				return I18n.t("%s needs %d %s.") % [str(o.get("name", id)), int(cost[item]), Game.item_name(str(item))]
	return ""


static func _craft_skill(craft: String) -> String:
	return {"forge": "smithing", "jewel": "jewelcrafting"}.get(craft, craft)


static func take(craft: String, design: Dictionary) -> void:
	for gr in groups(craft):
		var id := str(design.get(gr[1], ""))
		if id in PLAIN:
			continue
		var cost: Dictionary = _opt(craft, gr[0], id).get("cost", {})
		for item in cost:
			Game.remove_item(str(item), int(cost[item]))


static func apply(craft: String, pd: Dictionary, design: Dictionary) -> Dictionary:
	## returns the piece (or draught) with the design worked into it
	if is_plain(design):
		return pd
	var o := pd.duplicate(true)
	var tags: Array = []
	var m := {"ward_mult": 1.0, "hp_mult": 1.0, "weight_mult": 1.0, "value_mult": 1.0, "heal_mult": 1.0, "item_qi_mult": 1.0}
	var dose := 0
	var eff: Dictionary = o.get("effect", {}).duplicate(true)
	var d := {}
	for gr in groups(craft):
		var id := str(design.get(gr[1], ""))
		if id in PLAIN:
			continue
		var c := _opt(craft, gr[0], id)
		if c.is_empty():
			continue
		for k in m:
			m[k] *= float(c.get(k, 1.0))
		dose += int(c.get("dose_add", 0))
		if c.has("effect"):
			eff = Game.merge_effects(eff, c["effect"])
		if c.has("color") and gr[1] == "dye":
			o["color"] = c["color"]
		if c.has("color") and gr[1] == "trim":
			d["trim_color"] = c["color"]
		if c.has("gem_color"):
			o["gem_color"] = c["gem_color"]
		if c.has("look"):
			d["look"] = str(c["look"])
		if c.has("glow"):
			d["glow"] = c["glow"]
		d[gr[1]] = id
		if gr[1] != "dye":
			tags.append(str(c.get("name", id)))
	if o.has("ward"):
		o["ward"] = snappedf(float(o["ward"]) * m["ward_mult"], 0.1)
	if o.has("hp"):
		o["hp"] = int(round(float(o["hp"]) * m["hp_mult"]))
	if o.has("weight"):
		o["weight"] = snappedf(float(o["weight"]) * m["weight_mult"], 0.1)
	if o.has("heal"):
		o["heal"] = int(round(float(o["heal"]) * m["heal_mult"]))
	if o.has("qi") and str(o.get("type", "")) == "consumable":
		o["qi"] = int(round(float(o["qi"]) * m["item_qi_mult"]))
	if o.has("value"):
		o["value"] = int(round(float(o["value"]) * m["value_mult"]))
	if not eff.is_empty() or o.has("effect"):
		o["effect"] = eff
	o["design"] = d
	o["design_dose"] = dose
	if not tags.is_empty():
		o["name"] = "%s (%s)" % [str(o.get("name", "")), ", ".join(tags).to_lower()]
	o["desc"] = str(o.get("desc", "")) + I18n.t("  Designed: ") + (", ".join(tags) if not tags.is_empty() else "dyed") + "."
	return o
