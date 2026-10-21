extends "res://scripts/systems/GameSystem.gd"
## Round 144: something fresh each day, and a way to tune each trip. Robert, 2026-10-18: "do them all" (run modifiers + a daily rotation).
##   - Before a trip down, in any town: take ONE blessing from today's three (free), and optionally ONE hardship from today's three,
##     which pays a little more qi and finds while it lasts. Both end when you come back to a town. Skip them and nothing changes.
##   - A wandering pedlar (3 goods a day, two of each, at double the base price -- never a way to make money) in towns.
##   - The day's shrine: one half-hour blessing, once a day.
##   - The day's quarry: a beast of the floors you know; hunt three, earn a little insight and gold.
## The day is the real calendar day (like the daily bounties and the commission board). Offline game only; no stat is ever for sale.
## data/boons.json.

var data := {}
var day := ""
var run := {"boon": "", "curse": "", "out": false}
var bought := {}           # item id -> how many today
var shrine_used := false
var quarry_kills := 0
var quarry_paid := false
var day_override := ""     # tests
var _last_level := ""


func setup(game) -> void:
	super.setup(game)
	data = load_json("res://data/boons.json")


func reset() -> void:
	day = ""
	run = {"boon": "", "curse": "", "out": false}
	bought = {}
	shrine_used = false
	quarry_kills = 0
	quarry_paid = false
	_last_level = ""


func save_state() -> Dictionary:
	return {"day": day, "run": run, "bought": bought, "shrine_used": shrine_used, "quarry_kills": quarry_kills, "quarry_paid": quarry_paid}


func load_state(d: Dictionary) -> void:
	reset()
	day = str(d.get("day", ""))
	var r = d.get("run", {})
	if r is Dictionary:
		run = {"boon": str(r.get("boon", "")), "curse": str(r.get("curse", "")), "out": bool(r.get("out", false))}
		if run["boon"] != "" and _find("boons", str(run["boon"])).is_empty():
			run["boon"] = ""
		if run["curse"] != "" and _find("curses", str(run["curse"])).is_empty():
			run["curse"] = ""
	var b = d.get("bought", {})
	if b is Dictionary:
		for k in b:
			bought[str(k)] = int(b[k])
	shrine_used = bool(d.get("shrine_used", false))
	quarry_kills = int(d.get("quarry_kills", 0))
	quarry_paid = bool(d.get("quarry_paid", false))


func today() -> String:
	return day_override if day_override != "" else G.today()


func _roll_day() -> void:
	## a new day: the day's own counters start over
	var t := today()
	if day != t:
		day = t
		bought = {}
		shrine_used = false
		quarry_kills = 0
		quarry_paid = false


func _find(kind: String, id: String) -> Dictionary:
	for e in data.get(kind, []):
		if str(e.get("id", "")) == id:
			return e
	return {}


func _rng(salt: String) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash("%s|%s|%s" % [today(), G.char_name, salt])
	return r


func _draw(kind: String, n: int, salt: String) -> Array:
	var ids := []
	for e in data.get(kind, []):
		ids.append(str(e["id"]))
	var r := _rng(salt)
	for i in range(ids.size() - 1, 0, -1):
		var j := r.randi() % (i + 1)
		var t: String = ids[i]
		ids[i] = ids[j]
		ids[j] = t
	return ids.slice(0, mini(n, ids.size()))


func in_town() -> bool:
	var tr = G.sys("travel")
	return tr != null and tr.is_town(str(G.current_level))


func online() -> bool:
	return G.current_level != "" and G.OnlineGen.is_online(str(G.current_level))


# ---- blessings and hardships ------------------------------------------------------------------------------------------------------

func boon_offers() -> Array:
	_roll_day()
	return _draw("boons", int(data.get("offer", 3)), "boon")


func curse_offers() -> Array:
	_roll_day()
	return _draw("curses", int(data.get("offer", 3)), "curse")


func boon_def(id: String) -> Dictionary:
	return _find("boons", id)


func curse_def(id: String) -> Dictionary:
	return _find("curses", id)


func can_change() -> bool:
	return in_town()


func pick(kind: String, id: String) -> String:
	## kind "boon" or "curse"; "" as id puts it down
	_roll_day()
	if not can_change():
		return I18n.t("Choose in a town, before you set out.")
	var key := "boons" if kind == "boon" else "curses"
	if id != "":
		if not (id in (boon_offers() if kind == "boon" else curse_offers())):
			return ""
		run[kind] = id
		run["out"] = false
		G.log_event("boon_pick", {"kind": kind, "id": id})
		G.stats_changed.emit()
		return "%s: %s." % [I18n.t("Blessing") if kind == "boon" else I18n.t("Hardship"), str(_find(key, id).get("name", id))]
	run[kind] = ""
	G.stats_changed.emit()
	return ""


func active_text() -> Array:
	var out := []
	if str(run["boon"]) != "":
		out.append(str(boon_def(str(run["boon"])).get("name", "")))
	if str(run["curse"]) != "":
		out.append(str(curse_def(str(run["curse"])).get("name", "")))
	return out


func effects() -> Array:
	var out := []
	if online():
		return out
	if str(run["boon"]) != "":
		out.append(boon_def(str(run["boon"])).get("fx", {}))
	if str(run["curse"]) != "":
		out.append(curse_def(str(run["curse"])).get("fx", {}))
	return out


func reward() -> float:
	## the extra qi and finds a hardship pays while it lasts (0.0 with none)
	if str(run["curse"]) == "" or online():
		return 0.0
	return float(curse_def(str(run["curse"])).get("reward", 0.0))


func tick(_delta: float) -> void:
	## a trip is over when you are back in a town after having been out
	var lv := str(G.current_level)
	if lv == _last_level:
		return
	_last_level = lv
	if str(run["boon"]) == "" and str(run["curse"]) == "":
		return
	if in_town():
		if bool(run["out"]):
			var had := active_text()
			run = {"boon": "", "curse": "", "out": false}
			G.message.emit(I18n.t("BLESSING: the trip is over (%s). Pick again for the next.") % ", ".join(had))
			G.stats_changed.emit()
	else:
		run["out"] = true


# ---- the pedlar ------------------------------------------------------------------------------------------------------------------

func merchant_name() -> String:
	var names: Array = data.get("merchant_names", ["A pedlar"])
	return str(names[_rng("mname").randi() % names.size()])


func merchant_stock() -> Array:
	## [{id, price, left}]
	_roll_day()
	var pool := []
	for s in data.get("merchant_stock", []):
		if G.items.has(str(s)):
			pool.append(str(s))
	var r := _rng("merchant")
	for i in range(pool.size() - 1, 0, -1):
		var j := r.randi() % (i + 1)
		var t: String = pool[i]
		pool[i] = pool[j]
		pool[j] = t
	var out := []
	var each := int((data.get("merchant", {}) as Dictionary).get("stock_each", 2))
	var mult := float((data.get("merchant", {}) as Dictionary).get("price_mult", 2.0))
	for id in pool.slice(0, int((data.get("merchant", {}) as Dictionary).get("slots", 3))):
		var price := int(round(float(G.items[id].get("value", 1)) * mult))
		out.append({"id": id, "price": maxi(price, 1), "left": maxi(0, each - int(bought.get(id, 0)))})
	return out


func merchant_buy(id: String) -> String:
	if not in_town():
		return I18n.t("The pedlar only sets up in towns.")
	for s in merchant_stock():
		if str(s["id"]) != id:
			continue
		if int(s["left"]) <= 0:
			return I18n.t("They have no more of those today.")
		if G.gold < int(s["price"]):
			return I18n.t("Not enough gold.")
		G.gold -= int(s["price"])
		bought[id] = int(bought.get(id, 0)) + 1
		G.add_item(id, 1, false)
		G.log_event("pedlar", {"id": id})
		G.stats_changed.emit()
		return I18n.t("You buy %s for %d gold.") % [G.item_name(id), int(s["price"])]
	return ""


# ---- the shrine ------------------------------------------------------------------------------------------------------------------

func shrine_today() -> Dictionary:
	_roll_day()
	var l: Array = data.get("shrines", [])
	if l.is_empty():
		return {}
	return l[_rng("shrine").randi() % l.size()]


func shrine_ready() -> bool:
	_roll_day()
	return not shrine_used and in_town() and not shrine_today().is_empty()


func shrine_use() -> String:
	_roll_day()
	if not in_town():
		return I18n.t("The shrine is in town.")
	if shrine_used:
		return I18n.t("You have already knelt here today.")
	var s := shrine_today()
	if s.is_empty():
		return ""
	shrine_used = true
	G.add_buff("shrine_" + str(s["id"]), s.get("fx", {}), float(data.get("shrine_seconds", 1800)))
	G.log_event("shrine", {"id": str(s["id"])})
	G.stats_changed.emit()
	return I18n.t("SHRINE: %s answers. %s") % [str(s["name"]), str(s["text"])]


# ---- the quarry ------------------------------------------------------------------------------------------------------------------

func quarry_species() -> String:
	_roll_day()
	var q: Dictionary = data.get("quarry", {})
	var hi: int = G.reach_depth()
	var lo := maxi(1, hi - int(q.get("span", 4)))
	var pool := []
	var keys: Array = G.enemies.keys()
	keys.sort()
	for k in keys:
		var e: Dictionary = G.enemies[k]
		if bool(e.get("boss", false)) or bool(e.get("final", false)) or bool(e.get("passive", false)) or bool(e.get("frontier", false)):
			continue
		var f: int = int(e.get("floor", 1))
		if f >= lo and f <= hi:
			pool.append(str(k))
	if pool.is_empty():
		return ""
	return str(pool[_rng("quarry").randi() % pool.size()])


func quarry() -> Dictionary:
	var sp := quarry_species()
	var q: Dictionary = data.get("quarry", {})
	return {"species": sp, "name": str(G.enemies.get(sp, {}).get("name", sp)), "kills": quarry_kills, "need": int(q.get("need", 3)), "paid": quarry_paid,
		"insight": int(q.get("insight", 2)), "gold": int(q.get("gold_base", 6)) + int(q.get("gold_per_floor", 2)) * int(G.enemies.get(sp, {}).get("floor", 1))}


func on_event(kind: String, d: Dictionary) -> void:
	if kind != "kill" or online():
		return
	_roll_day()
	if quarry_paid:
		return
	var qr := quarry()
	if str(qr["species"]) == "" or str(d.get("type", "")) != str(qr["species"]):
		return
	quarry_kills += 1
	if quarry_kills >= int(qr["need"]):
		quarry_paid = true
		G.gain_insight(float(qr["insight"]), "the day's quarry")
		G.add_item("gold", int(qr["gold"]), false)
		G.message.emit(I18n.t("QUARRY: the day's hunt is done (%s). +%d insight, +%d gold.") % [str(qr["name"]), int(qr["insight"]), int(qr["gold"])])
		G.log_event("quarry_done", {"species": str(qr["species"])})
		G.stats_changed.emit()
