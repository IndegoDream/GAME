extends StaticBody3D
## A villager you can talk to (E). Defined in a level file's "npcs":
##   "M": {"role": "merchant", "name": "Trader Wen", "line": "Coin for teeth..."}
## Roles: merchant (buy/sell), smith (smithing + jewelcrafting),
## alchemist (alchemy + medicine), elder (quests), guild ("guild": id from
## data/guilds.json -- join, ranks, contracts), innkeeper (a bed for the
## night: full health, and this town becomes where you wake if you fall;
## "price" in gold, "lines" are the talk of the house), villager (just talks).
## A merchant can carry its own "stock": [item ids] (a settlement sells
## what its stretch of floors needs).
## Crafting is a real attempt: your skill against the work's difficulty,
## and how you approach it (carefully / steadily / boldly) -- it can fail,
## and it can come out Fine, Superior or a Masterwork.

const ROLE_TINT := {
	"merchant": Color(1.0, 0.85, 0.55),
	"smith": Color(0.75, 0.6, 0.5),
	"alchemist": Color(0.7, 1.0, 0.8),
	"guild": Color(1.0, 0.75, 0.75),
	"elder": Color(0.85, 0.85, 1.0),
	"innkeeper": Color(1.0, 0.7, 0.45),
	"academy": Color(0.95, 0.75, 0.95),
	"tournament": Color(1.0, 0.9, 0.4),
	"villager": Color(0.9, 1.0, 0.85),
}
const SHOP := ["healing_salve", "qi_pill", "calming_incense", "padded_vest", "storage_ring"]

var level
var cell := Vector2i.ZERO
var role := "villager"
var npc_name := "Villager"
var line := ""
var def := {}
var _anim: AnimationPlayer
var _body_model: Node3D
## Town life (2026-10-02): villagers don't stand on one spot all day --
## they wander a few steps around their home, stop to look at you when you
## come close, and keep closer to home at night. Traders, smiths, guild
## folk and the rest keep their posts. "wander": false in a level file pins
## anyone in place.
const WANDER_RADIUS := 3
const WALK_SPEED := 1.3
var wander := false
var _home_cell := Vector2i.ZERO
var _path: Array = []
var _rest := 0.0
var _wrng := RandomNumberGenerator.new()


func setup(lvl, args: Dictionary) -> void:
	level = lvl
	cell = args.get("cell", Vector2i.ZERO)
	role = str(args.get("role", "villager"))
	npc_name = str(args.get("name", "Villager"))
	line = str(args.get("line", ""))
	def = args.get("def", {})


func _ready() -> void:
	add_to_group("interactable")
	# dressed for their trade; a level file may add "dress": {...} (Dress.gd)
	var spec: Dictionary = preload("res://scripts/world/Dress.gd").spec_for(npc_name, role, def.get("dress", {}))
	var model: Node3D = preload("res://scripts/core/Art.gd").person(spec)
	add_child(model)
	preload("res://scripts/world/Dress.gd").dress(model, spec)
	if not model.has_meta("human"):
		_tint(model, ROLE_TINT.get(role, Color.WHITE))
	_body_model = model
	_anim = _find_anim(model)
	if _anim:
		_anim.playback_default_blend_time = 0.18      # round 37: moves ease into each other
	if _anim and _anim.has_animation("idle"):
		_anim.get_animation("idle").loop_mode = Animation.LOOP_LINEAR
		_anim.play("idle")
	if _anim and _anim.has_animation("walk"):
		_anim.get_animation("walk").loop_mode = Animation.LOOP_LINEAR
	_home_cell = cell
	_wrng.seed = hash(npc_name)
	_rest = _wrng.randf_range(2.0, 8.0)
	wander = role == "villager" and bool(def.get("wander", true)) and not bool(def.get("stays", false)) \
		and (DisplayServer.get_name() != "headless" or Game.life_in_tests)
	var tag := Label3D.new()
	tag.text = npc_name + ("\n(" + role + ")" if role != "villager" else "")
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.pixel_size = 0.009
	tag.no_depth_test = true
	tag.position = Vector3(0, 2.2, 0)
	tag.font_size = 40
	tag.outline_size = 14                          # round 62: readable over snow and sunlight too
	tag.outline_modulate = Color(0.04, 0.03, 0.02, 0.95)
	tag.modulate = Color(1.0, 0.93, 0.7)
	add_child(tag)
	# round 52: a gold "!" when they've a side quest for you, "?" when you've news for them
	_qmark = Label3D.new()
	_qmark.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_qmark.pixel_size = 0.012
	_qmark.no_depth_test = true
	_qmark.position = Vector3(0, 2.85, 0)
	_qmark.font_size = 64
	_qmark.outline_size = 12
	_qmark.outline_modulate = Color(0.15, 0.08, 0.0, 0.9)
	_qmark.modulate = Color(1.0, 0.82, 0.3) * 1.4
	add_child(_qmark)
	_qmark_update()
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.5
	cap.height = 1.6
	shape.shape = cap
	shape.position = Vector3(0, 0.8, 0)
	add_child(shape)
	level.astar.set_point_solid(cell, true)
	Game.companion_changed.connect(_on_companion_changed)
	if Game.in_party(npc_name) >= 0:
		_away()        # they're out walking with you


func prompt() -> String:
	return I18n.t("E: Talk to ") + npc_name


func interact(_player) -> void:
	Game.bump("talk:" + npc_name)
	Game.log_event("talk", {"npc": npc_name, "role": role})
	# round 32: the story -- if this townsperson has a scene waiting, it comes first
	var act: Dictionary = Game.story_act_for(npc_name)
	if not act.is_empty():
		_story_scene(act)
		return
	# round 34: a chapter of the main quest to report to this townsperson
	if Game.mq_reporter() == npc_name and Game.mq_ready():
		_chapter_report()
		return
	# round 52: a side quest -- one to offer, or one to hand in
	var Q = Game.sys("quests")
	if Q and Q.talk(self, _hud(), func(): _usual(Game.story_arc_text(npc_name))):
		return
	_usual(Game.story_arc_text(npc_name))


func _chapter_report() -> void:
	var c: Dictionary = Game.mq_chapter()
	var hud = _hud()
	var rows := []
	for r in Game.mq_progress():
		rows.append(I18n.t("[done] ") + str(r[0]))
	var body := "\"%s\"\n\n%s\n\n%s" % [str(c.get("name", "")), str(c.get("brief", "")), "\n".join(rows)]
	hud.open_dialog("%s -- the road down" % npc_name, body, [
		["Report it", func():
			var got := Game.mq_complete()
			_usual("\"Well walked.\" (%s)" % got)],
		["Later", func(): _usual("")]])


func _usual(extra: String = "") -> void:
	## the townsperson's usual business (extra: a line that goes first)
	match role:
		"merchant":
			_merchant(extra)
		"smith":
			_smith(extra)
		"alchemist":
			_workshop(["alchemy", "medicine"], extra)
		"guild":
			_guild(extra)
		"elder":
			var W = Game.sys("world")
			var gift: String = W.claim_gift() if W and level.level_id == "village" else ""      # round 44: a festival
			_elder((gift + ("\n\n" + extra if extra != "" else "")) if gift != "" else extra)
		"innkeeper":
			_inn(extra)
		"academy":
			_academy(extra)
		"tournament":
			_tournament(extra)
		"sect":
			_sect(extra)
		"headman":
			Game.sys("settlements").talk(self, extra)      # round 44: a camp of the deep's people
		_:
			_hud().open_dialog(npc_name, (extra + "\n\n" if extra != "" else "") + _villager_line(), _talk_opts() + [["Goodbye", _close]])


# ---- round 32: the story's scenes --------------------------------------------

func _story_scene(act: Dictionary) -> void:
	var opts := []
	var ch: Array = act.get("choices", [])
	for i in ch.size():
		var c: Dictionary = ch[i]
		var why := Game.story_can_choose(c)
		opts.append([str(c.get("text", "...")) + ((" [" + why + "]") if why != "" else ""), _story_pick.bind(str(act.get("id", "")), i)])
	opts.append(["Later.", _story_later.bind(str(act.get("id", "")))])
	_hud().open_dialog("%s -- %s" % [npc_name, str(act.get("name", ""))], str(act.get("say", "")), opts)


func _story_pick(act_id: String, i: int) -> void:
	var act := Game.story_act(act_id)
	var c: Dictionary = (act.get("choices", []) as Array)[i] if i < (act.get("choices", []) as Array).size() else {}
	var why := Game.story_can_choose(c)
	if why != "":
		_story_scene(act)
		Game.message.emit(why)
		return
	var after := Game.story_choose(act_id, i)
	Game.sfx("ui_ok", 0.7)
	_hud().open_dialog("%s -- %s" % [npc_name, str(act.get("name", ""))], after if after != "" else "...", [["Continue", _usual.bind("")], ["Goodbye", _close]])


func _story_later(act_id: String) -> void:
	Game.log_event("story_later", {"act": act_id})
	_usual("(%s will wait. The scene is still here when you're ready.)" % npc_name)


# ---- villagers: what they say changes the more you talk to them -----------

func _villager_line() -> String:
	var n := int(Game.counters.get("talk:" + npc_name, 0))
	var lines: Array = []
	if line != "":
		lines.append(line)
	# a "lines" list in the level file gives a villager more to say
	var more = _more_lines()
	lines += more
	if lines.is_empty():
		lines = ["Fine weather for cultivating."]
	var said: String = lines[min(n - 1, lines.size() - 1)] if n > 0 else lines[0]
	# unspoken techniques: a villager can be the hint
	for tid in Game.technique_defs:
		var u: Dictionary = Game.technique_defs[tid].get("unlock", {})
		if u.get("talk", {}).has(npc_name) and not Game.has_tech(tid):
			var need := int(u["talk"][npc_name])
			if n < need:
				said += I18n.t("\n\n(%s seems like she wants to tell you something. Maybe ask again.)") % npc_name
			break
	return said


func _more_lines() -> Array:
	if def.get("lines", []) is Array and not (def.get("lines", []) as Array).is_empty():
		return def["lines"]                    # round 44: a camp's people carry their own words
	var npcs: Dictionary = level.def.get("npcs", {})
	for ch in npcs:
		if str(npcs[ch].get("name", "")) == npc_name:
			return npcs[ch].get("lines", [])
	return []


# ---- merchant -----------------------------------------------------------

func _merchant(extra: String = "") -> void:
	## round 22: the trade screen -- their goods and yours side by side,
	## buy and sell without the window closing (HUD.open_trade)
	var hud = _hud()
	if hud and hud.has_method("open_trade"):
		hud.open_trade(self, extra)
		return
	var sell_value := 0
	for id in Game.inventory:
		if Game.items.get(id, {}).get("type") == "material":
			sell_value += int(Game.items[id].get("value", 0)) * Game.count(id)
	var opts := []
	if sell_value > 0:
		opts.append(["Sell all materials (%d gold)" % sell_value, _sell_all])
	for id in def.get("stock", SHOP):
		if Game.is_treasure(id) and Game.count(id) > 0:
			continue          # a treasure is one of a kind
		var price := int(Game.items.get(id, {}).get("value", 10)) * 2
		opts.append(["Buy %s -- %d gold" % [Game.item_name(id), price], _buy.bind(id, price)])
	opts.append_array(_talk_opts())
	opts.append(["Goodbye", _close])
	var body := (line if line != "" else I18n.t("Coin for goods, goods for coin.")) + I18n.t("\n\nYou have %d gold.") % Game.gold
	if extra != "":
		body = extra + "\n\n" + body
	_hud().open_dialog(npc_name, body, opts)


func faction() -> String:
	## round 44: whose people they are (a camp's, or whoever's town this is)
	if str(def.get("faction", "")) != "":
		return str(def["faction"])
	var F = Game.sys("factions")
	return F.place_faction(str(level.level_id)) if F and level else ""


func trade_refused() -> bool:
	var F = Game.sys("factions")
	return F != null and faction() != "" and F.price_mult(faction()) <= 0.0


func trade_stock() -> Array:
	## [[id, price], ...] -- what they sell
	var out := []
	if trade_refused():
		return out                              # round 44: they won't trade with an enemy
	var F = Game.sys("factions")
	var W = Game.sys("world")
	var fm: float = F.price_mult(faction()) if F else 1.0
	var fest: float = W.festival_discount() if W else 0.0
	var stock: Array = (def.get("stock", SHOP) as Array).duplicate()
	if F and faction() != "":
		for xid in F.extra_stock(faction()):
			if not (xid in stock):
				stock.append(xid)
	for id in stock:
		if not Game.has_item_def(str(id)):
			continue
		if Game.is_treasure(id) and Game.count(id) > 0:
			continue          # a treasure is one of a kind
		var price := int(Game.items.get(id, {}).get("value", 10)) * 2
		var off := Game.shop_discount(npc_name)             # round 32: a story's debt repaid
		if off > 0.0:
			price = maxi(1, int(round(price * (1.0 - off))))
		if fm != 1.0 or fest > 0.0:
			price = maxi(1, int(round(price * fm * (1.0 - fest))))     # round 44: standing, and a festival
		out.append([str(id), price])
	for row in Game.formula_scrolls_for(role):      # round 27: worked recipes, written down
		out.append(row)
	return out


func trade_line() -> String:
	if trade_refused():
		return I18n.t("\"I don't trade with your kind. Not after what you've done.\"")
	return line if line != "" else "Coin for goods, goods for coin."


func trade_buy(id: String, n: int = 1) -> String:
	var price := 0
	for row in trade_stock():
		if row[0] == id:
			price = int(row[1])
	if price <= 0:
		return I18n.t("\"I don't have that.\"")
	var bought := 0
	for i in n:
		if Game.gold < price:
			break
		Game.gold -= price
		Game.add_item(id, 1, false)
		bought += 1
		if Game.is_treasure(id):
			break
	if bought == 0:
		return I18n.t("You can't afford that.")
	Game.log_event("buy", {"id": id, "n": bought})
	Game.stats_changed.emit()
	return I18n.t("Bought %d %s for %d gold.") % [bought, Game.item_name(id), bought * price]


func trade_sell(id: String, n: int) -> String:
	if trade_refused():
		return I18n.t("\"Keep it. I'm not buying from you.\"")
	var got := Game.sell(id, n)
	if got <= 0:
		return I18n.t("\"I won't take that.\"")
	return I18n.t("Sold for %d gold.") % got


func _sell_all() -> void:
	var total := 0
	for id in Game.inventory.keys():
		var d: Dictionary = Game.items.get(id, {})
		if d.get("type") == "material":
			var n := Game.count(id)
			total += int(d.get("value", 0)) * n
			Game.remove_item(id, n)
	Game.add_item("gold", total, false)
	_merchant("Sold everything for %d gold." % total)


func _buy(id: String, price: int) -> void:
	if Game.gold < price:
		_merchant("You can't afford that.")
		return
	Game.gold -= price
	Game.add_item(id, 1)
	_merchant("A pleasure.")


# ---- smith / alchemist ----------------------------------------------------

func _smith(extra: String = "") -> void:
	_workshop(["smithing", "jewelcrafting"], extra)


func _settlement() -> String:
	return str(level.level_id) if level != null else str(Game.current_level)


func open_wish() -> Node:
	## Ask the smith to make something you describe (Wish.gd).
	var w = preload("res://scripts/objects/Wish.gd").new()
	w.npc_name = npc_name
	w.settlement = _settlement()
	w.place = str(level.def.get("name", w.settlement)) if level != null else w.settlement
	add_child(w)
	_hud().open_oneshot(w, I18n.t("%s -- a wish") % npc_name, (I18n.t("(Say what you want made, in your own words -- \"a spear that drinks fire\", \"a ring to keep me alive down there\". ") +
		I18n.t("%s will make the nearest honest thing; chance decides how good a casting it is. %d gold. %d of %d wishes left at this settlement.)")) % [
			npc_name, Game.wish_fee(), Game.wishes_left(w.settlement), Game.WISHES_PER_SETTLEMENT], "Describe what you want made...")
	return w


func _workshop(crafts: Array, extra: String = "") -> void:
	var opts := []
	var lines := []
	for r in Game.recipes:
		if not (str(r.get("skill", "smithing")) in crafts):
			continue
		var made := str(r["makes"])
		var sk := str(r.get("skill", "smithing"))
		var ready := Game.can_craft(r)
		lines.append("%s%s  [%s %d vs %d]  %s%s" % ["[ready]  " if ready else "         ",
			Game.item_name(made), Game.skill_name(sk), Game.skill_level(sk), int(r.get("difficulty", 0)),
			Game.recipe_text(r), ("  -- %d%%" % int(round(Game.craft_chance(r) * 100))) if ready else ""])
		if ready:
			opts.append(["Craft %s" % Game.item_name(made), _choose_intent.bind(r, crafts)])
	# round 27: use their forge / workshop yourself, and buy what they know
	var place := "forge" if role == "smith" else "workshop"
	opts.insert(0, ["Use the %s yourself (combine, forge, nanoforge)" % place, func():
		_close()
		_hud().open_kit("Forge" if role == "smith" else "Bench", place)])
	for row in Game.formula_scrolls_for(role):
		var sid := str(row[0])
		var price := int(row[1])
		opts.insert(1, ["Buy %s -- %d gold" % [Game.item_name(sid), price], func():
			if Game.gold < price:
				_workshop(crafts, "You can't afford that.")
				return
			Game.gold -= price
			Game.add_item(sid, 1, false)
			Game.log_event("buy", {"id": sid, "n": 1})
			_workshop(crafts, "You learn it by heart: %s." % Game.item_name(sid).trim_prefix("Formula: "))])
	if role == "smith" and Game.sys("heirloom") != null:
		var H = Game.sys("heirloom")
		if H.started:
			opts.insert(1, ["The heirloom -- %s" % H.status_line(), _heirloom.bind(crafts, "")])
		elif H.can_ignite_smithing():
			opts.insert(1, ["Ask about a set that grows with its wearer", func(): _heirloom(crafts, H.ignite("smith"))])
	opts.append_array(_talk_opts())
	opts.append(["Goodbye", _close])
	var body := (line if line != "" else "Bring me materials and we'll see what you can make of them.")
	if "smithing" in crafts and role == "smith":
		var left := Game.wishes_left(_settlement())
		if left > 0:
			opts.insert(0, ["Ask for something made to your wish (%d left here, %d gold)" % [left, Game.wish_fee()], open_wish])
		else:
			body += I18n.t("\n(\"Three wishes is what I make for anyone. The next forge down might have time for you.\")")
	if "smithing" in crafts:
		body += I18n.t("\n\nWeapon: %s   Armor: %s") % [Game.item_name(Game.weapon) if Game.weapon != "" else "fists", Game.item_name(Game.armor) if Game.armor != "" else "none"]
	var sk_line := []
	for c in crafts:
		sk_line.append("%s %d (%s)" % [Game.skill_name(c), Game.skill_level(c), Game.skill_title(c)])
	body += I18n.t("\nYour craft: ") + ", ".join(sk_line) + "\n\n" + "\n".join(lines)
	if extra != "":
		body = extra + "\n\n" + body
	_hud().open_dialog(npc_name, body, opts)


func _choose_intent(r: Dictionary, crafts: Array) -> void:
	var made := str(r["makes"])
	var body := I18n.t("%s -- how do you go about it?\n\n%s") % [Game.item_name(made), Game.item_desc(made)]
	var opts := []
	for intent in ["careful", "balanced", "bold"]:
		var it: Dictionary = Game.INTENTS[intent]
		opts.append(["%s -- %d%% (%s)" % [it["name"], int(round(Game.craft_chance(r, intent) * 100)), it["desc"]],
			_after_intent.bind(r, intent, crafts)])
	opts.append(["Not now", _workshop.bind(crafts, "")])
	_hud().open_dialog(npc_name, body, opts)


func _heirloom(crafts: Array, extra: String = "") -> void:
	var H = Game.sys("heirloom")
	var opts := []
	var body: String = str(H.cfg.get("name", I18n.t("The Heirloom"))) + "\n" + H.status_line()
	var i: int = H.next_index()
	if H.complete():
		body += I18n.t("\n\nEvery piece is made. It wakes as you do; feed it what the deep gives and it grows.")
	else:
		var p: Dictionary = H.pieces()[i]
		body += I18n.t("\n\nNext: ") + H.needs_text(i) + "\n" + str(p.get("recipe", ""))
		var w: String = H.why_not(i)
		if w != "":
			body += "\n(" + w + ")"
		else:
			var dc := "jewel" if str(Game.gear_data()["families"][str(p["family"])].get("kind", "")) == "jewel" else "forge"
			opts.append(["Make it", _heirloom_design.bind(crafts, i, dc, 0, {})])
	if H.worn_count() > 0:
		for id in H.feed_options().slice(0, 5):
			opts.append(["Feed it: %s (%d)" % [Game.item_name(id), Game.count(id)], func(): _heirloom(crafts, H.feed(id))])
	opts.append(["Back", _workshop.bind(crafts, "")])
	if extra != "":
		body = extra + "\n\n" + body
	_hud().open_dialog(npc_name, body, opts)


func _heirloom_design(crafts: Array, i: int, dc: String, gi: int, design: Dictionary) -> void:
	## choose the look of the piece, one thing at a time, then make it
	var gs: Array = Game.Design.groups(dc)
	var H = Game.sys("heirloom")
	var skl := Game.skill_level(str(H.pieces()[i]["craft"]))
	while gi < gs.size():
		var ok_opts := []
		for row in Game.Design.options(dc, gs[gi][0]):
			var d1 := {gs[gi][1]: str(row[0])}
			if str(row[0]) in Game.Design.PLAIN or Game.Design.check(dc, d1, skl) == "":
				ok_opts.append(row)
		if ok_opts.size() > 1:
			var opts := []
			for row in ok_opts:
				var o: Dictionary = row[1]
				var note := ""
				for it in o.get("cost", {}):
					note += " [%d %s]" % [int(o["cost"][it]), Game.item_name(str(it))]
				var nd := design.duplicate()
				nd[gs[gi][1]] = str(row[0])
				opts.append(["%s%s -- %s" % [o.get("name", row[0]), note, o.get("desc", "")], _heirloom_design.bind(crafts, i, dc, gi + 1, nd)])
			_hud().open_dialog(npc_name, I18n.t("Heirloom %s -- choose the %s.") % [str(H.pieces()[i]["name"]).to_lower(), str(gs[gi][2]).to_lower()], opts)
			return
		gi += 1
	var res: Dictionary = H.make(i, design)
	_heirloom(crafts, str(res.get("text", "")))


func _after_intent(r: Dictionary, intent: String, crafts: Array) -> void:
	## draughts can be designed (vial, tincture, seal): ask, one choice at a time
	var sk := str(r.get("skill", "smithing"))
	if Game.Design.has_section(sk) and _design_options(sk, 0).size() > 1:
		_choose_design(r, intent, crafts, 0, {})
	else:
		_craft(r, intent, crafts)


func _design_options(sk: String, gi: int) -> Array:
	## the options of group gi you could use right now (skill + material), plain first
	var out := []
	var gs: Array = Game.Design.groups(sk)
	if gi >= gs.size():
		return out
	for row in Game.Design.options(sk, gs[gi][0]):
		var o: Dictionary = row[1]
		var d := {gs[gi][1]: str(row[0])}
		if str(row[0]) in Game.Design.PLAIN or Game.Design.check(sk, d, Game.skill_level(sk)) == "":
			out.append(row)
	return out


func _choose_design(r: Dictionary, intent: String, crafts: Array, gi: int, design: Dictionary) -> void:
	var sk := str(r.get("skill", "smithing"))
	var gs: Array = Game.Design.groups(sk)
	while gi < gs.size() and _design_options(sk, gi).size() <= 1:
		gi += 1
	if gi >= gs.size():
		_craft(r, intent, crafts, design)
		return
	var opts := []
	for row in _design_options(sk, gi):
		var o: Dictionary = row[1]
		var note := ""
		for it in o.get("cost", {}):
			note += " [%d %s]" % [int(o["cost"][it]), Game.item_name(str(it))]
		var nd := design.duplicate()
		nd[gs[gi][1]] = str(row[0])
		opts.append(["%s%s -- %s" % [o.get("name", row[0]), note, o.get("desc", "")], _choose_design.bind(r, intent, crafts, gi + 1, nd)])
	opts.append(["Not now", _workshop.bind(crafts, "")])
	_hud().open_dialog(npc_name, I18n.t("%s -- choose the %s.") % [Game.item_name(str(r["makes"])), str(gs[gi][2]).to_lower()], opts)


func _craft(r: Dictionary, intent: String = "balanced", crafts: Array = [], design: Dictionary = {}) -> void:
	if crafts.is_empty():
		crafts = ["smithing", "jewelcrafting"]
	var cp = Game.sys("craftplay")
	var go := func():
		var res: Dictionary = Game.craft_attempt(r, intent, -1.0, -1.0, design)
		_workshop(crafts, str(res.get("text", "")))
	if cp != null:
		cp.begin(str(r.get("skill", "smithing")), r, go)
	else:
		go.call()


# ---- guilds ------------------------------------------------------------------

func _guild(extra: String = "") -> void:
	var gid := str(def.get("guild", ""))
	var gd: Dictionary = Game.guild_defs.get(gid, {})
	if gd.is_empty():
		_hud().open_dialog(npc_name, _villager_line(), [["Goodbye", _close]])
		return
	var opts := []
	var body := "%s\n\n%s" % [gd.get("name", gid), gd.get("desc", "")]
	var ranks: Array = gd.get("ranks", [])
	if not Game.in_guild(gid):
		var lines := []
		for rk in ranks:
			lines.append("  %s (%d)%s" % [rk.get("name", ""), int(rk.get("rep", 0)), (" -- " + str(rk["perk"])) if rk.has("perk") else ""])
		body += "\n\nRanks:\n" + "\n".join(lines)
		var rival := str(gd.get("rival", ""))
		if rival != "":
			body += I18n.t("\n\nThey don't get on with the %s%s.") % [Game.guild_name(rival), I18n.t(" -- and you're one of them") if Game.in_guild(rival) else ""]
		opts.append(["Join the %s" % gd.get("name", gid), func(): _guild(Game.join_guild(gid))])
	else:
		var r := Game.guild_rank(gid)
		var rep := float(Game.guilds[gid].get("rep", 0.0))
		body += I18n.t("\n\nYou are a %s. Standing: %d") % [Game.guild_rank_name(gid), int(rep)]
		if r + 1 < ranks.size():
			body += I18n.t(" / %d for %s") % [int(ranks[r + 1].get("rep", 0)), ranks[r + 1].get("name", "")]
		var cur: Dictionary = Game.guilds[gid].get("contract", {})
		if cur.is_empty():
			var c: Dictionary = Game.contract_offer(gid)
			if not c.is_empty():
				body += I18n.t("\n\nWork on offer: %s (+%d standing, %d gold)") % [c.get("desc", ""), int(c.get("reward", {}).get("rep", 0)), int(c.get("reward", {}).get("gold", 0))]
				opts.append(["Take the contract", func(): Game.take_contract(gid, c); _guild(I18n.t("Good. Come back when it's done."))])
		else:
			var p: Array = Game.contract_progress(gid)
			body += I18n.t("\n\nYour contract: %s  (%d / %d)") % [Game._contract_def(gid).get("desc", ""), int(p[0]), int(p[1])]
			if Game.contract_ready(gid):
				opts.append(["Hand in the contract", func(): Game.turn_in_contract(gid); _guild(I18n.t("Well done."))])
		body += "\n%s: %d" % [Game.contribution_name(gid).capitalize(), int(Game.contribution(gid))]
		opts.append(["The %s's stores (spend contribution)" % gd.get("name", gid), _stores.bind(gid, _guild)])
		opts.append(["Leave the %s (lose your standing)" % gd.get("name", gid), func(): Game.leave_guild(gid); _guild()])
	opts.append_array(_talk_opts())
	opts.append(["Goodbye", _close])
	if extra != "":
		body = extra + "\n\n" + body
	_hud().open_dialog(npc_name, body, opts)


# ---- talking freely: the box's own model gives them a voice ------------------

var voice: Node


func _voice() -> Node:
	if voice == null:
		voice = preload("res://scripts/core/Voice.gd").new()
		voice.npc_name = npc_name
		voice.persona_text = persona()
		add_child(voice)
	return voice


func _talk() -> void:
	_hud().open_chat(self)


func _talk_opts() -> Array:
	## Talking -- and, once they count you as a close friend, asking them
	## to come along (their choice; see Game.ask_companion).
	var o := [] if Game.llm_offline() else [["Talk with %s" % npc_name, _talk]]     # (round 56: free talk needs the box's model)
	if Game.knows_lesson(npc_name) and Game.lesson_for(npc_name, role) != "":
		var ln: Dictionary = Game.training_data().get("lessons", {}).get(Game.lesson_for(npc_name, role), {})
		o.append(["Train: %s (%d gold)%s" % [ln.get("name", I18n.t("a lesson")), Game.lesson_price(npc_name), I18n.t("  -- tomorrow") if Game.lesson_wait(npc_name) else ""], lesson])
	var MN = Game.sys("menagerie")
	if MN != null and can_travel() and MN.is_wayfarer(npc_name) and Game.in_party(npc_name) < 0:
		o.append(["Offer to travel together", wayfarer_join])
	elif can_travel() and Game.can_ask_companion(npc_name):
		o.append(["Ask %s to travel with you" % npc_name, func(): ask_to_travel(randf())])
	if Game.rumour(0) != "":
		o.append(["Heard anything strange?", _rumour])
	o.append(["Any advice?", _advice])             # round 42: anyone you ask has something true to tell you
	return o


func _advice() -> void:
	var w: String = Game.sys("lore").framed("npc", "tip") if Game.sys("lore") else ""
	_hud().open_dialog(npc_name, w if w != "" else "\"Keep your guard up and your pack light. That's all I've got.\"", [["Thank them", _close]])
	Game.log_event("advice", {"npc": npc_name})


# ---- a sect's elder (round 24, Valley.gd) ------------------------------------------

func sect_id() -> String:
	return str(def.get("sect", ""))


func _hall():
	for h in get_tree().get_nodes_in_group("sect_hall"):
		if str(h.sid) == sect_id():
			return h
	return null


func _sect(extra: String = "") -> void:
	var sid := sect_id()
	var s: Dictionary = Game.sect_def(sid)
	var lines := []
	if extra != "":
		lines.append(extra + "\n")
	lines.append(I18n.t("The %s -- %s.") % [s.get("name", "sect"), s.get("element", "")])
	lines.append("\"%s\"" % str(s.get("creed", "")))
	lines.append(I18n.t("\nTheir way with nanites: %s") % s.get("nanite_way", ""))
	if str(s.get("rival", "")) != "":
		lines.append(I18n.t("Rivals: %s") % s.get("rival", ""))
	var al := []
	for a in s.get("arts", []):
		var aid := str(a.get("id", ""))
		al.append(I18n.t("  %s %s (%s, taught to the %s) -- %s") % ["*" if Game.has_tech(aid) else "-", a.get("name", ""), a.get("kind", ""),
			Game.sect_rank_name(int(a.get("rank", 1)) - 1), str(a.get("what", "")).left(140)])
	lines.append(I18n.t("\nThe sect's arts:\n") + "\n".join(al))
	var Qs = Game.sys("quests")                  # round 55: the sect's own road of quests
	if Qs and Qs.sect_line(sid) != "":
		lines.append("\n" + Qs.sect_line(sid))
	var opts := []
	if Game.in_sect(sid):
		lines.append(I18n.t("\nYou are %s. %s") % [Game.sect_rank_name(), Game.sect_next_text()])
		opts.append(["Give the stores your %s materials (contribution)" % s.get("element", ""), func(): _sect(Game.sect_donate())])
		opts.append(["Leave the sect", func():
			_hud().open_dialog(npc_name, "\"Leave? What we taught you stays with you. The door doesn't.\"", [
				["Yes -- leave", func(): _sect(Game.leave_sect())], ["No", func(): _sect()]])])
	else:
		var t: Dictionary = s.get("trial", {})
		var how: String = {"combat": I18n.t("defeat %d foes in the yard within %d seconds") % [int(t.get("need", 4)), int(t.get("seconds", 60))],
			"endurance": "hold the yard for %d seconds" % int(t.get("seconds", 60)),
			"stillness": "sit on the hall's dais without rising for %d seconds" % int(t.get("seconds", 120))}.get(str(t.get("kind", "")), "")
		lines.append(I18n.t("\nTo enter: %s\n(The trial here: %s.)") % [s.get("entry_trial", ""), how])
		var why := Game.sect_join_check(sid)
		if why == "":
			opts.append(["Take the entry trial", func():
				var h = _hall()
				var r: String = h.start_trial() if h else "The hall isn't ready."
				_close()
				Game.message.emit(r)])
		else:
			lines.append("\n" + why)
	opts.append_array(_talk_opts())
	opts.append(["Goodbye", _close])
	_hud().open_dialog("%s -- %s" % [npc_name, s.get("name", "")], "\n".join(lines), opts)


func lesson() -> String:
	## a lesson (found by asking about training in chat)
	var r := Game.take_lesson(npc_name, role)
	var hud = _hud()
	if hud and hud._chat.visible:
		hud.chat_note(r)
	elif hud:
		hud.open_dialog(npc_name, r, _talk_opts() + [["Goodbye", _close]])
	return r


func _rumour() -> void:
	## round 21: townsfolk trade rumours of discoveries and augments you
	## haven't found -- a nudge toward a faster or different road
	var r := Game.rumour(hash(npc_name + Game.today()))
	_hud().open_dialog(npc_name, ("\"%s\"" % r) if r != "" else "\"Nothing you don't already know.\"", [["...", _close]])
	Game.log_event("rumour", {"npc": npc_name})


func can_travel() -> bool:
	## Villagers may come along; someone with a post (a shop, a forge, a
	## guild hall, an inn) keeps it -- unless the level says "can_travel".
	return bool(def.get("can_travel", role == "villager")) and not bool(def.get("stays", false))


func ask_to_travel(roll: float) -> String:
	var r := Game.ask_companion(npc_name, persona(), level.level_id if level else "village",
		ROLE_TINT.get(role, Color.WHITE), roll)
	var body := ""
	match r:
		"yes":
			body = "%s looks at you for a long moment, then reaches for a pack. \"Lead on.\"" % npc_name
			_away()
		"no":
			body = "%s smiles, but shakes their head. \"Not now. Ask me another day.\"" % npc_name
		"later":
			body = "\"You only just asked me,\" %s says. \"Give me time to think.\"" % npc_name
		_:
			body = "%s doesn't know you well enough for that yet." % npc_name
	_hud().open_dialog(npc_name, body, [["...", _close]])
	return r


func wayfarer_join() -> void:
	## a wayfarer takes anyone on (scripts/systems/Menagerie.gd): no friendship needed, trust grows on the road
	var MN = Game.sys("menagerie")
	var r: String = MN.recruit(npc_name, persona(), MN.wayfarer_home(npc_name), ROLE_TINT.get(role, Color.WHITE))
	if r == "yes":
		_hud().open_dialog(npc_name, "%s looks you over, shoulders a pack and nods. \"Lead on. We'll see how far trust goes.\"" % npc_name, [["...", _close]])
		_away()
	else:
		_hud().open_dialog(npc_name, "%s shakes their head. \"Not today.\"" % npc_name, [["...", _close]])


func _away() -> void:
	## Out walking with you: not standing at their post.
	visible = false
	remove_from_group("interactable")
	for c in get_children():
		if c is CollisionShape3D:
			c.set_deferred("disabled", true)
	if level:
		level.astar.set_point_solid(cell, false)


func _back() -> void:
	visible = true
	if not is_in_group("interactable"):
		add_to_group("interactable")
	for c in get_children():
		if c is CollisionShape3D:
			c.set_deferred("disabled", false)
	if level:
		level.astar.set_point_solid(cell, true)


func _on_companion_changed() -> void:
	if Game.in_party(npc_name) >= 0:
		_away()
	elif not visible:
		_back()


func persona() -> String:
	var p := str(def.get("persona", ""))
	if p == "":
		p = "%s, %s in %s. %s" % [npc_name, "a " + role if role != "villager" else I18n.t("a villager"),
			level.display_name() if level else "Eliet", line]
	return p


func say(text: String, cb: Callable) -> void:
	## Send what the player said; cb(reply_text) when they answer.
	## Asked about training, they know what they can teach (and say so).
	var v := _voice()
	v.situation = ""
	if Game.sys("lore"):
		var ts: Array = Game.sys("lore").tips()           # round 42: something true they could pass on
		if not ts.is_empty():
			v.situation = I18n.t("If it fits the conversation, you know this and might pass it on, plainly and in your own words: ") + str(ts[0]["text"])
	if Game.asks_about_training(text) and Game.lesson_for(npc_name, role) != "":
		v.situation += I18n.t(" If they ask about training or lessons: ") + Game.lesson_pitch(npc_name, role) + I18n.t(" Offer it in your own words, briefly.")
		Game.learn_of_lesson(npc_name)
	v.say(text, cb)


# ---- innkeeper ---------------------------------------------------------------

func inn_price() -> int:
	var F = Game.sys("factions")
	if F and level and str(level.level_id) == "village" and F.inn_free():
		return 0                                   # round 44: Eliet trusts you
	if def.has("settlement"):
		return Game.sys("settlements").rest_price(str(def["settlement"]))
	return int(def.get("price", 10))


func _inn(extra: String = "") -> void:
	var opts := []
	var price := inn_price()
	opts.append(["Rest the night (%d gold)" % price, rest])
	if not _more_lines().is_empty():
		opts.append(["Listen to the talk of the house", _gossip])
	opts.append_array(_talk_opts())
	opts.append(["Goodbye", _close])
	var body := (line if line != "" else "A bed, a bowl, a door that locks.")
	body += I18n.t("\n\nYou have %d gold.") % Game.gold
	if extra != "":
		body = extra + "\n\n" + body
	_hud().open_dialog(npc_name, body, opts)


func rest() -> bool:
	var price := inn_price()
	if Game.gold < price:
		_inn("\"No coin, no bed. Come back when your purse is heavier.\"")
		return false
	Game.gold -= price
	Game.meditating = false
	Game.hp = Game.max_hp()
	Game.enter_haven(level.level_id, level.display_name())
	Game.bump("rested")
	Game.log_event("rest", {"at": level.level_id, "price": price})
	Game.stats_changed.emit()
	Game.save_game()
	_inn("You sleep like the dead and wake whole. (Health restored. If you fall below, you'll wake here.)")
	return true


func _gossip() -> void:
	var lines := _more_lines()
	Game.bump("gossip:" + npc_name)
	var n := int(Game.counters.get("gossip:" + npc_name, 1.0))
	_inn("Over the noise of the room you catch:\n\n\"%s\"" % str(lines[(n - 1) % lines.size()]))


# ---- the Lotus Ascent Academy -------------------------------------------------

func _academy(extra: String = "") -> void:
	var opts := []
	var body := line if line != "" else "The Lotus Ascent Academy takes those who prove themselves. Strength, knowledge, craft."
	var res := _arena_report("exam") + _arena_report("rank")
	if res != "":
		body = res + "\n\n" + body
	if not bool(Game.academy.get("enrolled", false)):
		var t: Dictionary = Game.academy.get("trials", {})
		body += I18n.t("\n\nThe entrance exam:\n  %s Trial of Strength -- three waves in the arena\n  %s Trial of Knowledge -- five questions; four right to pass\n  %s Trial of Craft -- something you made yourself, Fine or better") % [
			"[passed]" if t.get("strength", false) else "[ ]", "[passed]" if t.get("knowledge", false) else "[ ]", "[passed]" if t.get("craft", false) else "[ ]"]
		if Game.realm < 1:
			body += I18n.t("\n\n\"Come back when you have reached Qi Condensation. We do not test children of the body.\"")
		else:
			if not t.get("strength", false):
				opts.append(["Take the Trial of Strength", func(): _close(); Game.start_exam_strength(level.level_id, int(level.def.get("depth", 5)))])
			if not t.get("knowledge", false):
				var wait := Game.knowledge_retry_wait()
				if wait > 0.0:
					body += I18n.t("\n(The examiner won't ask you again for another %d minutes.)") % int(ceil(wait / 60.0))
				else:
					opts.append(["Take the Trial of Knowledge", func(): _knowledge(Game.AcademyLib.exam_questions(Game.exam_knowledge_seed()), 0, 0)])
			if not t.get("craft", false):
				for id in Game.craft_trial_candidates().slice(0, 4):
					opts.append(["Present your %s (Trial of Craft)" % Game.item_name(id), func():
						Game.exam_present_craft(id)
						_academy("The examiner turns it over in her hands for a long time. \"Yes. You made this. Passed.\"")])
			if Game.exam_complete():
				opts.append(["Accept your place at the Academy", func():
					Game.enroll()
					_academy("\"Welcome, Outer Disciple.\" A robe is folded into your arms.")])
	else:
		var rk := Game.academy_rank_def(int(Game.academy.get("rank", 0)))
		body += I18n.t("\n\nYou are a %s. Standing %d, merit %d.") % [rk.get("name", ""), int(Game.guilds.get("academy", {}).get("rep", 0.0)), int(Game.academy.get("merit", 0.0))]
		var why := Game.can_rank_trial()
		var nxt := Game.academy_rank_def(int(Game.academy.get("rank", 0)) + 1)
		if why == "":
			opts.append(["Take the rank trial for %s" % nxt.get("name", ""), func(): _close(); Game.start_rank_trial(level.level_id)])
		elif not nxt.is_empty():
			body += I18n.t("\nNext rank, %s: %s") % [nxt.get("name", ""), why]
		opts.append(["Visit the library (learn techniques for merit)", _library])
		opts.append(["The Academy's stores (spend merit)", _stores.bind("academy", _academy)])
		var c := Game.contract_offer("academy")
		if not c.is_empty():
			opts.append(["Academy task: %s" % c.get("desc", ""), func(): Game.take_contract("academy", c); _academy(I18n.t("Task taken."))])
		if Game.contract_ready("academy"):
			opts.append(["Report your task", func(): Game.turn_in_contract("academy"); _academy(I18n.t("\"Good work.\""))])
	opts.append_array(_talk_opts())
	opts.append(["Goodbye", _close])
	if extra != "":
		body = extra + "\n\n" + body
	_hud().open_dialog(npc_name, body, opts)


func _knowledge(qs: Array, i: int, score: int) -> void:
	if i >= qs.size():
		var ok := Game.exam_knowledge_done(score)
		_academy("%d of %d. %s" % [score, qs.size(), I18n.t("\"Passed. You have been paying attention.\"") if ok else "\"Not yet. Read more. Come back in a while.\""])
		return
	var q: Dictionary = qs[i]
	var opts := []
	for k in q["options"].size():
		opts.append([str(q["options"][k]), func(): _knowledge(qs, i + 1, score + (1 if k == int(q["answer"]) else 0))])
	_hud().open_dialog(I18n.t("Trial of Knowledge -- %d of %d") % [i + 1, qs.size()], str(q["q"]), opts)


func _library() -> void:
	var opts := []
	var lines := []
	for row in Game.library_list():
		var tid := str(row.get("tech", ""))
		var t: Dictionary = Game.technique_defs.get(tid, {})
		var lock := int(Game.academy.get("rank", -1)) < int(row.get("rank", 0))
		lines.append(I18n.t("%s %s -- %s (%d merit%s)") % ["*" if Game.has_tech(tid) else "-", t.get("name", tid), t.get("desc", ""), int(row.get("merit", 0)),
			", " + str(Game.academy_rank_def(int(row.get("rank", 0))).get("name", "")) + " only" if lock else ""])
		if not Game.has_tech(tid) and not lock:
			opts.append(["Study %s (%d merit)" % [t.get("name", tid), int(row.get("merit", 0))], func():
				var why := Game.library_learn(tid)
				_academy(why if why != "" else "You spend days with the scroll. It stays with you.")])
	opts.append(["Back", _academy])
	_hud().open_dialog(I18n.t("The Academy Library"), I18n.t("Merit: %d\n\n%s") % [int(Game.academy.get("merit", 0.0)), "\n".join(lines)], opts)


func _arena_report(event: String) -> String:
	## What happened in the ring, told once by whoever sent you there.
	if str(Game.arena.get("result", "")) != event or str(Game.arena.get("host", "")) != (level.level_id if level else ""):
		return ""
	var t := str(Game.arena.get("text", ""))
	Game.arena = {}
	return t


# ---- tournaments ------------------------------------------------------------

func tourney_tier() -> int:
	return int(def.get("tier", level.def.get("depth", 5) if level else 5))


func _tournament(extra: String = "") -> void:
	var tier := tourney_tier()
	var fee := 10 * tier
	var host_name: String = level.display_name() if level else "the town"
	var body := line if line != "" else "Three bouts, one champion. The ring doesn't care who you are."
	var res := _arena_report("tour")
	if res != "":
		body = res + "\n\n" + body
	body += I18n.t("\n\nEntry: %d gold. Prize: %d gold, a piece from the champions' rack, Academy standing, and a title.") % [fee, 40 * tier]
	if Game.titles.size() > 0:
		body += I18n.t("\nYour titles: %s.") % ", ".join(Game.titles)
	var known := []
	for r in Game.rivals:
		var rr: Dictionary = Game.rivals[r]
		known.append(I18n.t("%s (you %d - %d)") % [r, int(rr.get("beat", 0)), int(rr.get("lost", 0))])
	if known.size() > 0:
		body += I18n.t("\nRivals: %s.") % ", ".join(known)
	var opts := []
	var cd := Game.tourney_cooldown(level.level_id if level else "")
	if cd > 0.0:
		body += I18n.t("\n\nThe next bracket is still being drawn up (%d min).") % int(ceil(cd / 60.0))
	elif Game.gold < fee:
		body += I18n.t("\n\nYou can't cover the entry fee.")
	else:
		opts.append(["Enter the tournament (%d gold)" % fee, func():
			_close()
			Game.start_tournament(level.level_id, host_name, tier)])
	opts.append_array(_talk_opts())
	opts.append(["Goodbye", _close])
	if extra != "":
		body = extra + "\n\n" + body
	_hud().open_dialog(npc_name, body, opts)


# ---- elder / quests --------------------------------------------------------

func _elder(extra: String = "") -> void:
	var opts := []
	var lines := []
	var ids: Array = Game.quest_defs.keys()
	ids.sort_custom(func(a, b): return int(Game.quest_defs[a].get("order", 99)) < int(Game.quest_defs[b].get("order", 99)))
	for qid in ids:
		var q: Dictionary = Game.quest_defs[qid]
		var st: String = Game.quests.get(qid, "")
		if st == "active":
			if Game.quest_ready(qid):
				opts.append(["Report: %s" % q["name"], _turn_in.bind(qid)])
				lines.append(I18n.t("* %s -- done! Report it.") % q["name"])
			else:
				lines.append("* %s -- %s" % [q["name"], q.get("desc", "")])
		elif st == "" and Game.quest_available(qid):
			opts.append(["Accept: %s" % q["name"], _accept.bind(qid)])
			lines.append("? %s -- %s" % [q["name"], q.get("desc", "")])
	# round 34: the main quest's standing, and his errands (one kill, one gather, per floor you've reached)
	var mqc: Dictionary = Game.mq_chapter()
	if not mqc.is_empty():
		lines.append("")
		lines.append(I18n.t("The road down -- %s: %s") % [mqc.get("name", ""), (I18n.t("report to %s") % Game.mq_reporter()) if Game.mq_ready() else Game.mq_next_goal()])
	var er: Array = Game.errands_open()
	if not er.is_empty():
		lines.append("")
		lines.append(I18n.t("Errands:"))
	for row in er:
		var eq: String = row[0]
		var ed: Dictionary = row[1]
		if row[2] == "active":
			if Game.errand_ready(eq):
				opts.append(["Report: %s" % ed["name"], func(): _elder(Game.errand_turn_in(eq))])
				lines.append(I18n.t("* %s -- done! Report it.") % ed["name"])
			else:
				lines.append("* %s -- %s" % [ed["name"], ed.get("desc", "")])
		else:
			opts.append(["Take on: %s (%d gold)" % [ed["name"], int(ed.get("reward", {}).get("gold", 0))], func():
				Game.errand_accept(eq)
				_elder("\"Go well.\"")])
			lines.append("? %s -- %s" % [ed["name"], ed.get("desc", "")])
	opts.append_array(_talk_opts())
	opts.append(["Goodbye", _close])
	var body := (line if line != "" else "Cultivation is a long road.")
	body += I18n.t("\n\nYour cultivation: %s (%s)\n\n") % [Game.cultivation_label(), Game.nanite_label()]
	body += "\n".join(lines) if lines.size() > 0 else I18n.t("I have nothing more to ask of you -- for now.")
	if extra != "":
		body = extra + "\n\n" + body
	_hud().open_dialog(npc_name, body, opts)


func _accept(qid: String) -> void:
	Game.quests[qid] = "active"
	Game.message.emit(I18n.t("Quest accepted: ") + str(Game.quest_defs[qid]["name"]))
	_elder("Go well.")


func _turn_in(qid: String) -> void:
	Game.turn_in(qid)
	_elder("You have done well.")


# ---- helpers -----------------------------------------------------------------

func _close() -> void:
	_hud().close_dialog()


func _hud():
	return get_tree().get_first_node_in_group("hud")


func _tint(n: Node, c: Color) -> void:
	if n is MeshInstance3D:
		for i in n.get_surface_override_material_count():
			var m = n.get_active_material(i)
			if m is StandardMaterial3D:
				var mm: StandardMaterial3D = m.duplicate()
				mm.albedo_color = mm.albedo_color * c
				n.set_surface_override_material(i, mm)
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


# ---- guild and sect stores: contribution buys what money can't ----------------

var _maker: Node      # LLMCall.gd, for a commissioned piece


func _stores(gid: String, back: Callable, extra: String = "") -> void:
	var gname := Game.guild_name(gid)
	var cn := Game.contribution_name(gid)
	var lines := []
	var opts := []
	for row in Game.guild_specials(gid):
		var id := str(row.get("item", ""))
		var why := Game.special_block(gid, row)
		var ranks: Array = Game.guild_defs.get(gid, {}).get("ranks", [])
		var rk := int(row.get("rank", 0))
		lines.append("%s %s -- %d %s, %s+. %s" % ["*" if why == "" else "-", Game.item_name(id), int(row.get("cost", 0)), cn,
			str(ranks[rk].get("name", "")) if rk < ranks.size() else "?", Game.item_desc(id)])
		if why == "":
			opts.append(["Take the %s (%d %s)" % [Game.item_name(id), int(row.get("cost", 0)), cn], func():
				var r := Game.buy_special(gid, id)
				_stores(gid, back, r if r != "" else "It's yours.")])
	var tb := Game.tailor_block(gid)
	if Game.tailor_cost(gid) > 0:
		lines.append(I18n.t("\nA piece made for you -- for how you actually fight and work -- %d %s. %s") % [Game.tailor_cost(gid), cn, tb if tb != "" else "They'll make it."])
		if tb == "":
			opts.append(["Commission a piece made for you (%d %s)" % [Game.tailor_cost(gid), cn], commission.bind(gid, back)])
	var dv := Game.donation_value(gid)
	if dv > 0:
		opts.append(["Donate all your materials (+%d standing and %s)" % [dv, cn], func():
			var got := Game.donate_materials(gid)
			_stores(gid, back, "They take it all, and write your name in the book. (+%d)" % got)])
	opts.append(["Back", back])
	var body := I18n.t("%s -- what the %s keeps for its own.\nYour %s: %d.\n\n%s") % [gname, gname, cn, int(Game.contribution(gid)), "\n".join(lines)]
	if extra != "":
		body = extra + "\n\n" + body
	_hud().open_dialog(npc_name, body, opts)


func commission(gid: String, back: Callable, roll: float = -1.0) -> bool:
	## A piece designed for how you play, paid for in contribution.
	if Game.tailor_block(gid) != "":
		return false
	Game.spend_contribution(gid, float(Game.tailor_cost(gid)))
	var p := Game.play_profile()
	var r := randf() if roll < 0.0 else roll
	var hud = _hud()
	if hud:
		hud.open_dialog(npc_name, "%s watches you for a long moment -- how you stand, what your hands are used to, what you carry. Then gets to work.\n\n(...)" % npc_name, [])
	if _maker == null:
		_maker = preload("res://scripts/core/LLMCall.gd").new()
		add_child(_maker)
	_maker.ask(preload("res://scripts/objects/Artisan.gd").tailor_prompt(npc_name, Game.guild_name(gid), p), _commissioned.bind(gid, back, p, r), 260, 0.8)
	return true


func _commissioned(d, gid: String, back: Callable, p: Dictionary, r: float) -> void:
	var design: Dictionary = d if d is Dictionary and d.has("name") else preload("res://scripts/objects/Artisan.gd").design(p, "", r)
	var how := I18n.t("Made for you by the ") + Game.guild_name(gid)
	var def := Game.finalize_design(design, Game.reach_depth(), 0.6 + 0.4 * r, how)
	var made := Game.grant_custom_item(def, 3, how)
	var say := str(design.get("line", "")).strip_edges()
	if is_inside_tree() and _hud() != null:
		_stores(gid, back, "%s%s\n\n%s -- %s" % [say, "\n" if say != "" else "", Game.item_name(made), str(Game.item_def(made).get("desc", ""))])


# ---- town life: a villager's day ---------------------------------------------------

var _qmark: Label3D
var _qmark_t := 0.0


func _qmark_update() -> void:
	var Q = Game.sys("quests")
	_qmark.text = Q.marker_for(npc_name) if Q else ""
	if _qmark.text == "" and role == "elder" and not Game.has_flag("fs:talk"):
		_qmark.text = "!"                           # round 62: the first step -- here's who to talk to


func _process(delta: float) -> void:
	if _qmark:
		_qmark_t -= delta
		if _qmark_t <= 0.0:
			_qmark_t = 1.0
			_qmark_update()
	if not wander or not visible or level == null:
		return
	var player = get_tree().get_first_node_in_group("player")
	var hud = _hud()
	if player and global_position.distance_to(player.global_position) < 2.6:
		# someone's come to see them: stop, and look at them
		_path.clear()
		var to: Vector3 = player.global_position - global_position
		if _body_model:
			_body_model.rotation.y = lerp_angle(_body_model.rotation.y, atan2(to.x, to.z), minf(delta * 5.0, 1.0))
		_play_anim("idle")
		return
	if hud and hud.is_blocking():
		return
	if _path.is_empty():
		_rest -= delta
		if _rest > 0.0:
			return
		var night: bool = Game.daylight() < 0.25
		_rest = _wrng.randf_range(4.0, 10.0) * (2.5 if night else 1.0)
		_choose_walk(1 if night else WANDER_RADIUS)
		return
	var next: Vector2i = _path[0]
	if level.astar.is_point_solid(next) and next != cell:
		_path.clear()           # someone (you, a stall, another villager) is in the way
		_play_anim("idle")
		return
	var goal: Vector3 = level.cell_to_world(next)
	var d := goal - global_position
	d.y = 0.0
	if d.length() < 0.08:
		_step_to(next)
		_path.pop_front()
		if _path.is_empty():
			_play_anim("idle")
		return
	global_position += d.normalized() * minf(d.length(), WALK_SPEED * delta)
	if _body_model:
		_body_model.rotation.y = atan2(d.x, d.z)
	_play_anim("walk")


func _choose_walk(radius: int) -> void:
	for i in 6:
		var target := _home_cell + Vector2i(_wrng.randi_range(-radius, radius), _wrng.randi_range(-radius, radius))
		if target == cell or not level.is_free(target):
			continue
		level.astar.set_point_solid(cell, false)
		var p: Array = level.path_between(cell, target)
		level.astar.set_point_solid(cell, true)
		if p.size() >= 2 and p.size() <= radius * 2 + 2:
			_path = p.slice(1)
			return


func _step_to(next: Vector2i) -> void:
	## Arrived at the next cell: it's theirs now, the last one is free.
	level.astar.set_point_solid(cell, false)
	cell = next
	level.astar.set_point_solid(cell, true)


func _play_anim(a: String) -> void:
	if _anim and _anim.has_animation(a) and _anim.current_animation != a:
		_anim.play(a)
