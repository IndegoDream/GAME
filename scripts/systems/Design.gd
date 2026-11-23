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
	## [[id, option]...] in file order. An option with a "secret" is hidden until you have discovered it (round 182).
	var out := []
	var g: Dictionary = section(craft).get(group, {})
	for k in g:
		var o: Dictionary = g[k]
		var sec := str(o.get("secret", ""))
		if sec != "" and not Game.has_flag(sec):
			continue
		var xp := str(o.get("expansion", ""))
		if xp != "" and not Game.expansion_open(xp):
			continue                       # a pack's look: shown once the pack is yours
		if group == "aspects" and str(k) != "none":
			o = _with_fit_note(craft, str(k), o)
		out.append([str(k), o])
	return out


# ---- round 182: infusion -- discovering how to use materials at the bench and forge --------------------
## Robert, 2026-10-31: "a system that can be discovered in how to properly use items on the bench and forge to make the
## items have more aspects of what we chose." (data/infusion.json)
##   1. HANDLE materials of an element (they are written in the crafting journal as you use them); enough of them, of
##      more than one kind, and you learn to INFUSE that aspect: the Aspect option appears on the bench and forge.
##   2. An infusion costs one material of the element (the cheapest you carry; a richer one infuses more strongly).
##   3. The METHOD you choose decides how well it takes. For each craft and element one method is a true fit; the
##      game never says which. Try, read what the piece tells you, and the fit is remembered (and shown on the option).
##   4. The element you chose as your own aspect (Aspect page) infuses a quarter stronger.

static var _inf := {}
static var _cat := {}            # element -> potency of the material take() just used


static func infusion() -> Dictionary:
	if _inf.is_empty():
		var d = Game._load_json("res://data/infusion.json", {})
		_inf = d if d is Dictionary else {}
	return _inf


static func _with_fit_note(craft: String, el: String, o: Dictionary) -> Dictionary:
	if not Game.has_flag("fit:%s:%s" % [craft, el]):
		return o
	var fit := str(infusion().get("fit", {}).get(craft, {}).get(el, ""))
	var mname := str((section(craft).get("methods", {}) as Dictionary).get(fit, {}).get("name", fit))
	var c := o.duplicate(true)
	c["desc"] = str(o.get("desc", "")) + I18n.t("  You have learned its true method: %s.") % mname
	return c


static func _pick_element(el: String) -> String:
	## the cheapest material of this element you carry and are not wearing ("" if none)
	var best := ""
	var bv := 1.0e18
	for id in Game.inventory:
		var sid := str(id)
		if not Game.has_item_def(sid) or Game.count(sid) - Game.equipped_count(sid) <= 0:
			continue
		var d: Dictionary = Game.item_def(sid)
		if str(d.get("type", "")) != "material" or str(d.get("element", "")) != el:
			continue
		var v := float(d.get("value", 4))
		if v < bv:
			bv = v
			best = sid
	return best


static func discover_check() -> void:
	## called after every craft: handling an element's materials teaches its aspect
	var cfg := infusion()
	var cb = Game.sys("craftbook")
	if cb == null:
		return
	var need_uses := int(cfg.get("discover", {}).get("uses", 6))
	var need_kinds := int(cfg.get("discover", {}).get("kinds", 2))
	var hint_at := int(cfg.get("discover", {}).get("hint_at", 3))
	for el in cfg.get("elements", {}):
		var flag := "infuse:" + str(el)
		if Game.has_flag(flag):
			continue
		var uses := 0
		var kinds := 0
		for mid in cb.used:
			if not Game.has_item_def(str(mid)):
				continue
			if str(Game.item_def(str(mid)).get("element", "")) == str(el):
				uses += int(cb.used[mid])
				kinds += 1
		var nm := str(cfg["elements"][el].get("name", el))
		if uses >= need_uses and kinds >= need_kinds:
			Game.set_flag(flag)
			Game.log_event("infusion_discovered", {"element": str(el)})
			Game.big_moment.emit(I18n.t("DISCOVERED: %s infusion") % nm, I18n.t("You have handled enough %s materials to feel what they want. At the bench and the forge you can now infuse the %s aspect into what you make. The right METHOD makes it take; the wrong one fights it. Try them and watch what the piece tells you.") % [nm.to_lower(), nm.to_lower()])
		elif uses >= hint_at and not Game.has_flag("infuse_hint:" + str(el)):
			Game.set_flag("infuse_hint:" + str(el))
			Game.message.emit(I18n.t("Your hands keep returning to %s materials. There is something in them to learn -- work with a few kinds of them.") % nm.to_lower())


static func _infuse(craft: String, asp: String, method: String) -> Dictionary:
	## what an infusion gives: {effect, mult, dose, harmony, glow}
	var cfg := infusion()
	var el: Dictionary = cfg.get("elements", {}).get(asp, {})
	var out := {"effect": {}, "mult": {}, "dose": 0, "harmony": false}
	if el.is_empty():
		return out
	var nm := str(el.get("name", asp)).to_lower()
	var fit := str(cfg.get("fit", {}).get(craft, {}).get(asp, ""))
	var s := 0.6 + 0.2 * float(_cat.get(asp, 1.0))
	var mname := str((section(craft).get("methods", {}) as Dictionary).get(method, {}).get("name", method)).to_lower()
	if method in PLAIN:
		s *= float(cfg.get("bare_mult", 0.85))
		Game.message.emit(I18n.t("Without a method the %s only half takes.") % nm)
	elif method == fit:
		s *= float(cfg.get("harmony_mult", 1.6))
		out["harmony"] = true
		Game.set_flag("fit:%s:%s" % [craft, asp])
		Game.message.emit(I18n.t("The %s took to the %s method: a true infusion. (Remembered.)") % [nm, mname])
	else:
		s *= float(cfg.get("clash_mult", 0.6))
		Game.message.emit(I18n.t("The %s fought the %s method; the infusion is thin. Another method may suit it.") % [nm, mname])
	var asys = Game.sys("aspect")
	if asys != null and str(asys.focus) == asp:
		s *= float(cfg.get("attuned_mult", 1.25))
		Game.message.emit(I18n.t("Your own %s aspect answers it.") % nm)
	if cfg.get("consumable_crafts", []).has(craft):
		out["mult"] = {"heal_mult": 1.0 + 0.06 * s, "item_qi_mult": 1.0 + 0.06 * s}
		out["dose"] = 1 if bool(out["harmony"]) else 0
	else:
		out["effect"] = Game.merge_effects({}, el.get("effect", {}), s)
		if bool(out["harmony"]):
			out["effect"] = Game.merge_effects(out["effect"], el.get("harmony_effect", {}), s)
	if el.has("glow"):
		out["glow"] = el["glow"]
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
		var sec := str(o.get("secret", ""))
		if sec != "" and not Game.has_flag(sec):
			return I18n.t("You have not learned how to do that yet.")
		var cel := str(o.get("cost_element", ""))
		if cel != "" and _pick_element(cel) == "":
			return I18n.t("%s needs a material of the %s aspect.") % [str(o.get("name", id)), cel]
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
		var cel := str(_opt(craft, gr[0], id).get("cost_element", ""))
		if cel != "":
			var mid := _pick_element(cel)
			if mid != "":
				_cat[cel] = Game.material_potency(mid)
				Game.remove_item(mid, 1)


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
		if gr[1] == "method" and str(design.get("aspect", "")) in PLAIN:
			continue                                  # (a method only matters when something is being infused)
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
	var asp := str(design.get("aspect", ""))
	if not (asp in PLAIN):
		var ai := _infuse(craft, asp, str(design.get("method", "")))
		eff = Game.merge_effects(eff, ai["effect"])
		for mk in ai["mult"]:
			if m.has(mk):
				m[mk] *= float(ai["mult"][mk])
		dose += int(ai["dose"])
		if ai.has("glow") and not d.has("glow"):
			d["glow"] = ai["glow"]
		d["harmony"] = bool(ai["harmony"])
		if bool(ai["harmony"]):
			tags.append(I18n.t("in harmony"))
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
