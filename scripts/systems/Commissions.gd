extends "res://scripts/systems/GameSystem.gd"
## Round 143: the commission board. Robert, 2026-10-18: something for the crafters -- crafting should have a purpose beyond selling.
## Four orders a day in each town (the day is the real calendar day, like the daily bounties). A named client wants a made thing
## -- one of the things you could make today -- in a minimum quality. You take up to three at a time, make them, and deliver them
## in a town, any town, within three days.
## Fair-pay and economy: the pay is a little over what a trader would give (pay = what its materials could be bought for x 1.22,
## more for a better quality), so the board is worth doing but never a buy-craft-sell loop, and there is a daily cap on the gold it
## pays. Beyond gold: standing with the matching guild (kept for you if you haven't joined it yet), skill practice, and now and
## then a find. Nothing here is for sale and nothing is exclusive to those who pay.
## Scripts only: the board is a section at the top of the menu's Craft page (scripts/ui/Hub.gd). data/commissions.json.

var data := {}
var boards := {}              # town id -> {"day": int, "orders": [order, ...]}
var active := []              # orders you've taken
var taken := {}               # order id -> true (taken or delivered, so it doesn't come back on the board the same day)
var paid := {"day": -1, "gold": 0}
var day_override := -1        # tests


func setup(game) -> void:
	super.setup(game)
	data = load_json("res://data/commissions.json")


func reset() -> void:
	boards = {}
	active = []
	taken = {}
	paid = {"day": -1, "gold": 0}


func save_state() -> Dictionary:
	return {"boards": boards, "active": active, "taken": taken, "paid": paid}


func load_state(d: Dictionary) -> void:
	reset()
	var b = d.get("boards", {})
	if b is Dictionary:
		boards = b
	var a = d.get("active", [])
	if a is Array:
		active = a
	var t = d.get("taken", {})
	if t is Dictionary:
		taken = t
	var p = d.get("paid", {})
	if p is Dictionary:
		paid = {"day": int(p.get("day", -1)), "gold": int(p.get("gold", 0))}


func cfg() -> Dictionary:
	return data.get("board", {})


func _day() -> int:
	return day_override if day_override >= 0 else int(floor(Time.get_unix_time_from_system() / 86400.0))


func in_town() -> bool:
	var tr = G.sys("travel")
	return tr != null and tr.is_town(str(G.current_level))


func town_name(town: String) -> String:
	return str(G.load_level_def(town).get("name", town)) if G.level_exists(town) else town


# ---- making the day's board ------------------------------------------------------------------------------------------------------

func _candidates(skill: String) -> Array:
	var out := []
	var lvl: int = G.skill_level(skill)
	for r in G.recipes:
		if str(r.get("skill", "")) != skill:
			continue
		var mk := str(r.get("makes", ""))
		if not G.items.has(mk) or G.is_treasure(mk) or G.make_cost(mk) < 0.0:
			continue
		if int(r.get("difficulty", 0)) > lvl + 2:
			continue
		out.append(r)
	out.sort_custom(func(a, b): return int(a.get("difficulty", 0)) > int(b.get("difficulty", 0)))
	return out


func _order(rng: RandomNumberGenerator, town: String, idx: int, used: Dictionary) -> Dictionary:
	var skills: Array = (data.get("clients", {}) as Dictionary).keys()
	skills.sort()
	var pool := []
	for sk in skills:
		var c := _candidates(str(sk))
		if not c.is_empty():
			pool.append([str(sk), c])
	if pool.is_empty():
		return {}
	for attempt in 6:
		var pr: Array = pool[rng.randi() % pool.size()]
		var cands: Array = pr[1]
		var pick: Dictionary = cands[int(floor(pow(rng.randf(), 1.8) * float(cands.size())))]
		var mk := str(pick["makes"])
		if used.has(mk):
			continue
		used[mk] = true
		var skill := str(pr[0])
		var diff := int(pick.get("difficulty", 0))
		var cost: float = G.make_cost(mk)
		var n := 1 if cost >= 40.0 else (2 + rng.randi() % 2)
		var lvl: int = G.skill_level(skill)
		var q := 1
		var roll := rng.randf()
		var odds: Dictionary = cfg().get("quality_odds", {})
		if roll > float(odds.get("", 0.6)) and lvl >= diff:
			q = 2
		if roll > float(odds.get("", 0.6)) + float(odds.get("fine", 0.3)) and lvl >= diff + 6:
			q = 3
		var qid := str(G.QUALITY[q]["id"])
		var gold := maxi(int(cfg().get("min_gold", 6)), int(round(cost * float(n) * float(cfg().get("gold_mult", 1.22)) * float(cfg().get("quality_mult", {}).get(qid, 1.0)))))
		var clients: Array = data["clients"][skill]
		var cl: Dictionary = clients[rng.randi() % clients.size()]
		var o := {"id": "%d|%s|%d" % [_day(), town, idx], "town": town, "skill": skill, "item": mk, "n": n, "q": q, "gold": gold,
			"client": str(cl["name"]), "trade": str(cl["trade"]), "reason": str(cl["reason"]), "diff": diff,
			"rep": 3 + int(diff / 10), "xp": 6 + int(diff / 2), "bonus": rng.randf() < float(cfg().get("bonus_chance", 0.15)), "expires": _day() + int(cfg().get("expire_days", 3))}
		if o["bonus"]:
			var bl: Array = cfg().get("bonus_items", ["spirit_herb"])
			o["bonus_item"] = str(bl[rng.randi() % bl.size()])
			o["bonus_n"] = 1 + rng.randi() % 2
		return o
	return {}


func board(town: String) -> Array:
	## today's orders in a town that you haven't taken
	var b: Dictionary = boards.get(town, {})
	if int(b.get("day", -1)) != _day():
		var rng := RandomNumberGenerator.new()
		rng.seed = hash("%d|%s|%s" % [_day(), town, G.char_name])
		var used := {}
		var orders := []
		for i in int(cfg().get("size", 4)):
			var o := _order(rng, town, i, used)
			if not o.is_empty():
				orders.append(o)
		b = {"day": _day(), "orders": orders}
		boards[town] = b
		for k in taken.keys():                      # an old day's ids can't come back
			if not str(k).begins_with(str(_day()) + "|"):
				taken.erase(k)
	var out := []
	for o in b.get("orders", []):
		if not taken.has(str(o["id"])):
			out.append(o)
	return out


# ---- taking, making, delivering --------------------------------------------------------------------------------------------------

func purge() -> void:
	var keep := []
	for o in active:
		if int(o.get("expires", 0)) >= _day():
			keep.append(o)
		else:
			G.message.emit(I18n.t("COMMISSION: %s's order for %s has lapsed.") % [str(o.get("client", "")), G.item_name(str(o.get("item", "")))])
	active = keep


func active_orders() -> Array:
	purge()
	return active


func find(oid: String) -> Dictionary:
	for o in active:
		if str(o.get("id", "")) == oid:
			return o
	return {}


func accept(oid: String, town: String = "") -> String:
	purge()
	if not in_town():
		return I18n.t("Commissions are posted in towns.")
	if active.size() >= int(cfg().get("max_active", 3)):
		return I18n.t("You already have %d orders in hand. Deliver or drop one first.") % active.size()
	var t := town if town != "" else str(G.current_level)
	for o in board(t):
		if str(o["id"]) == oid:
			active.append(o.duplicate(true))
			taken[oid] = true
			G.log_event("commission_taken", {"id": oid})
			G.stats_changed.emit()
			return I18n.t("You take %s's order: %d x %s%s.") % [str(o["client"]), int(o["n"]), G.item_name(str(o["item"])), quality_text(int(o["q"]))]
	return ""


func abandon(oid: String) -> void:
	for i in active.size():
		if str(active[i].get("id", "")) == oid:
			active.remove_at(i)
			G.stats_changed.emit()
			return


func quality_text(q: int) -> String:
	return "" if q <= 1 else I18n.t(" (%s or better)") % I18n.t(str(G.QUALITY[q]["name"]))


func qualifying(o: Dictionary) -> Array:
	## [item id, how many free] for the pieces in the pack that meet the order, lowest quality first
	var out := []
	var mk := str(o.get("item", ""))
	for id in G.inventory:
		var s := str(id)
		if G.base_id(s) != mk or G.quality_index(s) < int(o.get("q", 1)):
			continue
		var free: int = G.count(s) - G.equipped_count(s)
		if free > 0:
			out.append([s, free])
	out.sort_custom(func(a, b): return G.quality_index(str(a[0])) < G.quality_index(str(b[0])))
	return out


func have_for(o: Dictionary) -> int:
	var n := 0
	for p in qualifying(o):
		n += int(p[1])
	return n


func can_deliver(o: Dictionary) -> bool:
	return in_town() and have_for(o) >= int(o.get("n", 1))


func _gold_room() -> int:
	if int(paid.get("day", -1)) != _day():
		paid = {"day": _day(), "gold": 0}
	return maxi(0, int(cfg().get("daily_gold_cap", 600)) - int(paid["gold"]))


func deliver(oid: String) -> String:
	purge()
	var o := find(oid)
	if o.is_empty():
		return ""
	if not in_town():
		return I18n.t("Deliver it in a town.")
	if have_for(o) < int(o["n"]):
		return I18n.t("You don't have enough of those%s yet.") % quality_text(int(o["q"]))
	var need := int(o["n"])
	for p in qualifying(o):
		var take := mini(need, int(p[1]))
		if not G.remove_item(str(p[0]), take):
			return ""
		need -= take
		if need <= 0:
			break
	var room := _gold_room()
	var gold := mini(int(o["gold"]), room)
	paid["gold"] = int(paid["gold"]) + gold
	if gold > 0:
		G.add_item("gold", gold, false)
	G.add_skill_xp(str(o["skill"]), float(o["xp"]), "a commission")
	var gid := str(cfg().get("guilds", {}).get(str(o["skill"]), ""))
	var rep_text := ""
	if gid != "":
		if G.in_guild(gid):
			G.add_guild_rep(gid, float(o["rep"]))
		else:
			G.flags["story:rep_owed:" + gid] = float(G.flags.get("story:rep_owed:" + gid, 0.0)) + float(o["rep"])
		rep_text = I18n.t(", +%d standing with the %s") % [int(o["rep"]), G.guild_name(gid)]
	var extra := ""
	if bool(o.get("bonus", false)) and str(o.get("bonus_item", "")) != "":
		G.add_item(str(o["bonus_item"]), int(o.get("bonus_n", 1)), false)
		extra = ", %s x%d" % [G.item_name(str(o["bonus_item"])), int(o.get("bonus_n", 1))]
	abandon(oid)
	G.bump("commissions")
	G.log_event("commission_done", {"id": oid, "gold": gold, "skill": str(o["skill"])})
	var capnote := I18n.t(" (the day's commission gold is used up)") if gold < int(o["gold"]) else ""
	var line := I18n.t("COMMISSION: %s is delighted. +%d gold%s%s%s.") % [str(o["client"]), gold, rep_text, extra, capnote]
	G.message.emit(line)
	G.stats_changed.emit()
	return line


func client_line(o: Dictionary) -> String:
	return "%s (%s): \"%s\"" % [str(o.get("client", "")), I18n.t(str(o.get("trade", ""))), I18n.t(str(o.get("reason", "")))]
