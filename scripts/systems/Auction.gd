extends "res://scripts/systems/GameSystem.gd"
## The Common City's auction house (2026-11-06). Robert, 2026-11-03: "a common city for chat, trade and co-op ...
## auction houses" -- offline now, built so the online version can take over the same listings.
##
## Offline, the house is a market of the deep's other travellers (simulated):
##   BUY   today's lots: materials, remedies and gear from all over, at a fair price or a little over (seeded by day)
##   SELL  list what you carry at one of three prices; buyers come while you're away (hour by hour, real time),
##         the house keeps a fee, you collect at the counter.
## Made so it can't be farmed (Robert: "as close to unexploitable as possible"):
##   - the house never sells below what a trader would pay you for the same thing (no buy-here-sell-there loop)
##   - what you bought at the house can't be listed again (no buy-low-relist loop)
##   - a fee on every sale, a cap on how many of your lots sell in a day, and on how many you can list at once
##   - the heirloom, treasures, quest things and clues can't be listed at all
## Online-ready: every lot is a plain dictionary {id, item, n, price, seller, listed_at, ...}; the online house swaps
## the simulated buyers/sellers for real ones (tools/server would hold the book). Numbers: data/auction.json.

var cfg := {}
var lots := []                 # your listings: {item, n, price, tier, listed_at, sold_at}
var proceeds := 0              # gold waiting at the counter
var bought := {}               # item -> how many you bought here (can't be relisted)
var sold_today := {"day": "", "n": 0}
var _last_check := 0.0
const DATA := "res://data/auction.json"


func setup(game) -> void:
	super.setup(game)
	var d = G._load_json(DATA, {})
	cfg = d if d is Dictionary else {}


func reset() -> void:
	lots = []
	proceeds = 0
	bought = {}
	sold_today = {"day": "", "n": 0}


func save_state() -> Dictionary:
	return {"lots": lots, "proceeds": proceeds, "bought": bought, "sold_today": sold_today}


func load_state(d: Dictionary) -> void:
	lots = (d.get("lots", []) as Array).duplicate(true)
	proceeds = int(d.get("proceeds", 0))
	bought = (d.get("bought", {}) as Dictionary).duplicate()
	sold_today = (d.get("sold_today", {"day": "", "n": 0}) as Dictionary).duplicate()


func _n(k: String, def_v: float) -> float:
	return float(cfg.get(k, def_v))


func _now() -> float:
	return Time.get_unix_time_from_system()


# ---- what may be listed --------------------------------------------------------------------

func value_of(item: String) -> int:
	return maxi(int(G.item_def(item).get("value", 0)), 1)


func listable(item: String) -> String:
	## "" when you can list it, else why not
	if not G.has_item_def(item) or G.count(item) <= 0:
		return I18n.t("You don't have that.")
	var d: Dictionary = G.item_def(item)
	var ty := str(d.get("type", ""))
	if G.is_treasure(item) or ty in ["currency", "quest", "formula", "treasure"] or bool(d.get("clue", false)):
		return I18n.t("The house won't take %s.") % G.item_name(item)
	if G.is_heirloom(item):
		return I18n.t("The heirloom isn't for sale.")
	if G.sys("tester") != null and G.sys("tester").free_item(item):
		return I18n.t("Conjured stock isn't for sale.")
	if free_to_list(item) <= 0:
		return I18n.t("You bought those here -- the house won't take them back to sell again.")
	if lots.size() >= int(_n("max_lots", 8)):
		return I18n.t("You have as many lots up as the house allows (%d).") % int(_n("max_lots", 8))
	return ""


func free_to_list(item: String) -> int:
	## what you hold minus what you're wearing minus what you bought here
	_trim_bought(item)
	return maxi(0, G.count(item) - G.equipped_count(item) - int(bought.get(item, 0)))


func _trim_bought(item: String) -> void:
	## the bought-here mark can never cover more than you still hold: once you sell,
	## eat or use those pieces, the mark goes with them and later finds can be listed
	if not bought.has(item):
		return
	var held: int = G.count(item)
	if held <= 0:
		bought.erase(item)
	elif int(bought[item]) > held:
		bought[item] = held


func tiers() -> Array:
	## [key, name, price multiple of value, sells per hour (chance)]
	return [["quick", I18n.t("Quick sale"), _n("quick_mult", 0.75), _n("quick_rate", 0.9)],
		["fair", I18n.t("Fair price"), _n("fair_mult", 1.0), _n("fair_rate", 0.45)],
		["dear", I18n.t("Dear"), _n("dear_mult", 1.3), _n("dear_rate", 0.15)]]


func price_for(item: String, tier: String, n: int = 1) -> int:
	for t in tiers():
		if t[0] == tier:
			return maxi(1, int(round(value_of(item) * float(t[2])))) * n
	return value_of(item) * n


func list_item(item: String, n: int, tier: String) -> String:
	var why := listable(item)
	if why != "":
		return why
	n = clampi(n, 1, free_to_list(item))
	var price := price_for(item, tier, n)
	var fee := int(ceil(price * _n("listing_fee", 0.02)))
	if G.gold < fee:
		return I18n.t("The listing costs %d gold.") % fee
	G.gold -= fee
	G.remove_item(item, n)
	lots.append({"item": item, "n": n, "price": price, "tier": tier, "listed_at": _now(), "seller": "you"})
	G.log_event("auction_list", {"item": item, "n": n, "price": price})
	G.stats_changed.emit()
	return I18n.t("Listed: %d %s for %d gold (%d gold to list).") % [n, G.item_name(item), price, fee]


func withdraw(i: int) -> String:
	if i < 0 or i >= lots.size():
		return ""
	var l: Dictionary = lots.pop_at(i)
	G.add_item(str(l["item"]), int(l["n"]), false)
	G.stats_changed.emit()
	return I18n.t("You take back %d %s.") % [int(l["n"]), G.item_name(str(l["item"]))]


# ---- buyers come while you're away ------------------------------------------------------------

func settle(now: float = -1.0) -> int:
	## real time since each lot went up decides whether a buyer came; returns how many sold now
	if now < 0.0:
		now = _now()
	var day: String = G.today()
	if str(sold_today.get("day", "")) != day:
		sold_today = {"day": day, "n": 0}
	var cap := int(_n("daily_sales", 10))
	var n_sold := 0
	var keep := []
	for l in lots:
		var rate := 0.45
		for t in tiers():
			if t[0] == str(l.get("tier", "fair")):
				rate = float(t[3])
		var hours := maxf(0.0, (now - float(l.get("listed_at", now))) / 3600.0)
		# the chance someone has bought it by now (seeded by the lot itself, so checking twice never re-rolls)
		var p_sold := 1.0 - pow(1.0 - rate, hours)
		var roll := float(absi(hash("%s|%s|%d" % [str(l["item"]), str(l.get("listed_at", 0)), int(l.get("price", 0))])) % 10000) / 10000.0
		if roll < p_sold and int(sold_today["n"]) < cap:
			var cut := int(round(int(l["price"]) * (1.0 - _n("sale_fee", 0.08))))
			proceeds += cut
			sold_today["n"] = int(sold_today["n"]) + 1
			n_sold += 1
			G.log_event("auction_sold", {"item": str(l["item"]), "n": int(l["n"]), "gold": cut})
		else:
			keep.append(l)
	lots = keep
	return n_sold


func collect() -> String:
	settle()
	if proceeds <= 0:
		return I18n.t("Nothing waiting at the counter yet.")
	var g := proceeds
	proceeds = 0
	G.add_item("gold", g, false)
	G.stats_changed.emit()
	return I18n.t("The clerk counts out %d gold." % g)


func tick(delta: float) -> void:
	_last_check += delta
	if _last_check >= 60.0 and not lots.is_empty():
		_last_check = 0.0
		var before := proceeds
		if settle() > 0 and proceeds > before:
			G.message.emit(I18n.t("AUCTION HOUSE: something of yours sold -- collect at the counter in the Common City."))


# ---- what the house has today ------------------------------------------------------------

func market() -> Array:
	## today's lots from the other travellers: [{item, n, price}] -- same all day, new tomorrow
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("auction|" + G.today())
	var dep := maxi(int(G.reach_depth()) if G.has_method("reach_depth") else 1, 1)
	var pool := []
	for id in G.items:
		var sid := str(id)
		var it: Dictionary = G.items[sid]
		var ty := str(it.get("type", ""))
		if not (ty in ["material", "consumable", "weapon", "armor", "ring", "amulet"]):
			continue
		if G.is_treasure(sid) or bool(it.get("clue", false)) or sid.begins_with("c27_") or sid.begins_with("custom_") or sid.begins_with("brew_") or G.is_heirloom(sid):
			continue
		var fl := int(it.get("floor", it.get("depth", 0)))
		if fl > dep + 3:
			continue          # nothing from deeper than you've been, much
		pool.append(sid)
	pool.sort()
	var out := []
	for i in int(_n("market_lots", 12)):
		if pool.is_empty():
			break
		var sid: String = pool.pop_at(rng.randi() % pool.size())
		var mult := rng.randf_range(_n("market_min", 1.0), _n("market_max", 1.45))
		var each := maxi(int(round(value_of(sid) * mult)), G.sell_price(sid) + 1)        # never below what a trader pays you
		var n := 1 if str(G.item_def(sid).get("type", "")) in ["weapon", "armor", "ring", "amulet"] else rng.randi_range(2, 6)
		out.append({"item": sid, "n": n, "price": each * n, "each": each})
	return out


func buy(i: int) -> String:
	var m := market()
	if i < 0 or i >= m.size():
		return ""
	var lot: Dictionary = m[i]
	var key := "%s|%s" % [G.today(), str(i)]
	if G.counters.has("auction_bought:" + key):
		return I18n.t("Someone else got there first -- that lot is gone.")
	if G.gold < int(lot["price"]):
		return I18n.t("That lot is %d gold; you have %d.") % [int(lot["price"]), G.gold]
	G.gold -= int(lot["price"])
	G.add_item(str(lot["item"]), int(lot["n"]), false)
	bought[str(lot["item"])] = int(bought.get(str(lot["item"]), 0)) + int(lot["n"])
	G.counters["auction_bought:" + key] = 1.0
	G.log_event("auction_buy", {"item": str(lot["item"]), "n": int(lot["n"]), "gold": int(lot["price"])})
	G.stats_changed.emit()
	return I18n.t("Yours: %d %s for %d gold.") % [int(lot["n"]), G.item_name(str(lot["item"])), int(lot["price"])]


func lot_gone(i: int) -> bool:
	return G.counters.has("auction_bought:%s|%s" % [G.today(), str(i)])
