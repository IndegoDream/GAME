extends Node
## Store (round 58): how the game is sold, and what this device owns.
## Robert, 2026-10-05: "free play up to level 5 on iOS and Android with a full
## pay option after the first 5 levels of play are done; then allow Steam to
## have its pay version from the start, with promises of expansions."
##
##   phones   the village, the valley and floors 1-5 are free, with no ads.
##            model "ads" (the one in use -- Robert, later the same day: "after
##            level 5 ... ads on the free tier, still able to complete the game"):
##            below floor 5 everything stays free to the end, with an occasional
##            ad at a natural break and gifts for ads you choose (Ads.gd); the
##            first time you go below floor 5 a window says so. The full game --
##            ONE purchase, a non-consumable -- removes every ad.
##            model "locked": below floor 5 needs the full game (data/store.json).
##            Android: Google Play Billing (addons/GodotGooglePlayBilling,
##            the official plugin) -- query, buy, acknowledge (Play refunds
##            anything not acknowledged in 3 days), restore.
##            iOS: StoreKit through Godot's InAppStore plugin -- buy, restore
##            (Apple requires a Restore button: the unlock window has one).
##   Steam    the whole game from the start (the purchase is Steam's).
##   anywhere else -- the box's phone (web) version, your own PC, the engine
##            checks -- the whole game too. Set ELIET_FREE_TIER=1 (or Menu ->
##            settings "store_test") to try the phone's paywall on a PC with a
##            pretend store.
##
## What you own is kept on the device (user://store.json), apart from your
## save slots -- every character on this device has the full game once it's
## bought -- and checked against the store each time the game starts (a
## refund takes it back; offline, the last answer stands).
## Expansions: data/store.json "expansions" (planned, not built yet).
## owns_expansion(id) is what an expansion's content will check: a Steam DLC
## app id or a phone store product.

signal changed                       # what's owned changed
signal prices_changed
signal note(text: String)            # something to tell the player

const FILE := "user://store.json"
const DATA := "res://data/store.json"
const BILLING := "res://addons/GodotGooglePlayBilling/BillingClient.gd"

var backend := "full"                # "full" | "google" | "apple" | "test" | "none" | "demo" (the Steam demo)
var owned := {}                      # product key -> true
var prices := {}                     # product key -> the store's own price text
var busy := false
var tampered := false                # the record on this device failed its seal (round 127)
var connected := false
var _data := {}
var _billing = null                  # BillingClient (Android)
var _apple = null                    # InAppStore singleton (iOS)
var _after := Callable()             # what to do once the full game is bought (the trip you were taking)
var test_answer := "ok"              # the pretend store: "ok" | "cancel" | "error" | "pending"
var file_path := FILE                # (tools point this elsewhere)
var told := {}                       # windows already shown on this device ("ads": the road-goes-on window)


func data() -> Dictionary:
	if _data.is_empty():
		var t := FileAccess.get_file_as_string(DATA)
		var d = JSON.parse_string(t) if t != "" else null
		_data = d if d is Dictionary else {"free_depth": 5, "products": {"full_game": {}}}
	return _data


func free_depth() -> int:
	return int(data().get("free_depth", 5))


func pick_backend() -> String:
	if OS.has_feature("demo") or OS.get_environment("ELIET_DEMO") == "1":
		return "demo"                  # the Steam demo: floors 1-5, then the store page
	if test_allowed(OS.has_feature("play"), OS.has_feature("steam")) and (OS.get_environment("ELIET_FREE_TIER") == "1" or str(preload("res://scripts/core/Gfx.gd").settings.get("store_test", "off")) == "on"):
		return "test"
	if OS.has_feature("steam"):
		return "full"
	if OS.has_feature("android"):
		return "google" if Engine.has_singleton("GodotGooglePlayBilling") and ResourceLoader.exists(BILLING) else "none"
	if OS.has_feature("ios"):
		return "apple" if Engine.has_singleton("InAppStore") else "none"
	return "full"


static func test_allowed(play_build: bool, steam_build: bool) -> bool:
	## round 127: the pretend store grants the full game for free -- it exists only in builds that aren't sold through a store, so
	## editing settings.json or setting an environment variable can never open it on a Play or Steam copy
	return not (play_build or steam_build)


static func _sig(keys: Array, store_kind: String) -> String:
	## a seal on the record of what's owned, tied to this device: a hand-edited store.json fails it and the claim is dropped
	var ks := keys.duplicate()
	ks.sort()
	var msg := "%s|%s" % [",".join(PackedStringArray(ks)), store_kind]
	var key := ("eliet-store-v1|" + OS.get_unique_id() + "|" + OS.get_name()).to_utf8_buffer()
	return Crypto.new().hmac_digest(HashingContext.HASH_SHA256, key, msg.to_utf8_buffer()).hex_encode()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	start(pick_backend())


func start(kind: String) -> void:
	backend = kind
	owned = {}
	told = {}
	prices = {}
	connected = false
	_load()
	match backend:
		"google":
			_billing = load(BILLING).new()
			_billing.name = "BillingClient"
			add_child(_billing)
			_billing.connected.connect(_g_connected)
			_billing.disconnected.connect(_g_disconnected)
			_billing.connect_error.connect(_g_connect_error)
			_billing.query_product_details_response.connect(_g_details)
			_billing.query_purchases_response.connect(_g_purchases)
			_billing.on_purchase_updated.connect(_g_updated)
			_billing.acknowledge_purchase_response.connect(_g_acknowledged)
			_billing.start_connection()
		"apple":
			_apple = Engine.get_singleton("InAppStore")
			if _apple.has_method("set_auto_finish_transaction"):
				_apple.set_auto_finish_transaction(true)
			_apple.request_product_info({"product_ids": _ids("apple")})
			_apple.restore_purchases()             # (quietly: what this Apple ID already owns)
		"test":
			prices["full_game"] = "$4.99 (pretend)"
	changed.emit()


# ---- what's open -----------------------------------------------------------------------------

func full_game() -> bool:
	return backend == "full" or owned.has("full_game")


func comfort() -> bool:
	## round 127: the convenience perks (never power) -- the full game's, and Steam's paid game's from the start
	return full_game()


func style() -> bool:
	## the cosmetic Style pack: bought on phones, included in the paid Steam game
	return backend == "full" or owned.has("style_pack")


func depth_of(level_id: String) -> int:
	## how deep a place is: a floor's number, a hollow's floor below
	if level_id.begins_with("floor"):
		return int(level_id.trim_prefix("floor").get_slice(":", 0))
	var SG = load("res://scripts/world/ScavengeGen.gd")
	if SG.is_scavenge(level_id):
		var p: Dictionary = SG.parse(level_id)
		return int(str(p.get("to", "floor0")).trim_prefix("floor"))
	return 0


func model() -> String:
	if backend == "demo":
		return "locked"                 # (a demo ends at the free floors; no ads on a PC)
	return str(data().get("model", "ads"))


func demo() -> bool:
	return backend == "demo"


func steam_page() -> String:
	var st: Dictionary = data().get("steam", {})
	var url := str(st.get("store_url", ""))
	if url == "" and int(st.get("full_app_id", 0)) > 0:
		url = "https://store.steampowered.com/app/%d/" % int(st["full_app_id"])
	return url


func phone_store() -> bool:
	## a copy sold through a phone store (or the pretend one)
	return backend in ["google", "apple", "test", "none"]


func ads_on() -> bool:
	## the free tier below the free floors shows ads; the full game never does
	return model() == "ads" and phone_store() and not full_game()


func level_locked(level_id: String) -> bool:
	if expansion_locked(level_id) != "":
		return true
	return model() == "locked" and not full_game() and depth_of(level_id) > free_depth()


func travel_check(level_id: String) -> String:
	## what has to happen before this trip: "" (go), "locked", "word" (the
	## road-goes-on window, once per device), "expansion:<id>"
	var ex := expansion_locked(level_id)
	if ex != "":
		return "expansion:" + ex
	if level_locked(level_id):
		return "locked"
	if ads_on() and depth_of(level_id) > free_depth() and not told.has("ads"):
		return "word"
	return ""


func mark_told(what: String) -> void:
	told[what] = true
	_save()


# ---- expansions ------------------------------------------------------------------------------

func expansions() -> Array:
	var out := []
	for e in data().get("expansions", []):
		if e is Dictionary:
			out.append(e)
	return out


func expansion(id: String) -> Dictionary:
	for e in expansions():
		if str(e.get("id", "")) == id:
			return e
	return {}


func expansion_of(level_id: String) -> String:
	## which expansion a place belongs to ("" = the game itself)
	for e in expansions():
		var pre := str(e.get("levels_prefix", ""))
		if pre != "" and level_id.begins_with(pre):
			return str(e["id"])
	return ""


func expansion_locked(level_id: String) -> String:
	var ex := expansion_of(level_id)
	return ex if ex != "" and not owns_expansion(ex) else ""


func owns_expansion(id: String) -> bool:
	## what an expansion's content checks (Game.expansion_open): released, and
	## yours -- Steam: its DLC installed; the box's own builds: yes; phones: bought
	var e := expansion(id)
	if e.is_empty() or str(e.get("status", "planned")) != "released":
		return false
	if backend == "full":
		var dlc := int(e.get("steam_dlc", 0))
		if OS.has_feature("steam") and dlc > 0:
			return Game.steam != null and Game.steam.has_method("dlc_installed") and Game.steam.dlc_installed(dlc)
		return true
	if bool(e.get("needs_full_game", false)) and not full_game():
		return false
	return owned.has(id)


func price_text(key: String = "full_game") -> String:
	return str(prices.get(key, ""))


func can_buy(key: String = "full_game") -> bool:
	if backend == "demo":
		return key == "full_game"
	if not (backend in ["google", "apple", "test"]) or not catalogue().has(key):
		return false
	return not full_game() if key == "full_game" else not owned.has(key)


func why_not() -> String:
	if backend == "none":
		return "The store isn't reachable from this copy of the game."
	if backend == "google" and not connected:
		return "Google Play isn't answering right now -- check the connection and try again."
	return ""


# ---- buying ----------------------------------------------------------------------------------

func buy(key: String = "full_game", after: Callable = Callable()) -> String:
	## start buying; the answer comes later (changed / note). Returns "" or why not.
	if (key == "full_game" and full_game()) or (key != "full_game" and owned.has(key)):
		return "You already have that."
	if not catalogue().has(key):
		return "That isn't for sale yet."
	if busy:
		return "The store is still working on the last request."
	var w := why_not()
	if w != "":
		return w
	if backend == "demo":
		return _open_steam_page()
	_after = after
	match backend:
		"google":
			busy = true
			var r = _billing.purchase(_pid(key, "google"))
			if r is Dictionary and r.has("status") and int(r["status"]) != OK:
				busy = false
				return "Google Play couldn't start the purchase (%s)." % str(r.get("debug_message", r.get("response_code", "?")))
		"apple":
			busy = true
			var e = _apple.purchase({"product_id": _pid(key, "apple")})
			if e != OK:
				busy = false
				return "The App Store couldn't start the purchase."
		"test":
			_test_buy(key)
	return ""


func _open_steam_page() -> String:
	## the demo's buy button: the full game's page in the Steam overlay, or the browser
	Game.log_event("demo_store", {})
	var app := int(data().get("steam", {}).get("full_app_id", 0))
	if app > 0 and Game.steam and Game.steam.has_method("open_store") and Game.steam.open_store(app):
		return ""
	var url := steam_page()
	if url == "":
		return "The full game's Steam page isn't set yet (data/store.json \"steam\")."
	OS.shell_open(url)
	return ""


func restore() -> String:
	match backend:
		"google":
			if not connected:
				return why_not()
			_billing.query_purchases(0)            # ProductType.INAPP
			return "Asking Google Play what this account owns..."
		"apple":
			_apple.restore_purchases()
			return "Asking the App Store what this Apple ID owns..."
		"test":
			return "Nothing to restore (pretend store)." if not owned.has("full_game") else "You have the full game."
	return "Everything is already open here."


func grant(key: String, how: String = "") -> void:
	var was := owned.has(key)
	owned[key] = true
	busy = false
	_save()
	if not was:
		Game.log_event("purchase", {"product": key, "store": backend, "how": how})
		if key == "full_game":
			note.emit("THE FULL GAME: no more ads, ever. Thank you!" if model() == "ads" else "THE FULL GAME: the way down is open. Thank you!")
		elif key == "style_pack":
			note.emit("THE STYLE PACK: your auras are in Comforts & Style. Thank you!")
		elif expansion(key).has("name"):
			note.emit("%s is yours. Thank you!" % str(expansion(key)["name"]))
	changed.emit()
	if _after.is_valid():
		var a := _after
		_after = Callable()
		a.call()


func revoke(key: String) -> void:
	## the store says it isn't owned (a refund)
	if owned.has(key):
		owned.erase(key)
		_save()
		changed.emit()


func _test_buy(key: String) -> void:
	match test_answer:
		"ok":
			grant(key, "test")
		"cancel":
			_after = Callable()
			note.emit("Purchase cancelled.")
		"pending":
			note.emit("The purchase is pending -- the game opens up the moment it goes through.")
		_:
			_after = Callable()
			note.emit("The purchase didn't go through.")


# ---- Google Play ------------------------------------------------------------------------------

func _g_disconnected() -> void:
	connected = false


func _g_connect_error(code, msg) -> void:
	connected = false
	push_warning("Store: Play billing didn't connect (%s %s)" % [str(code), str(msg)])


func _g_acknowledged(r: Dictionary) -> void:
	if int(r.get("response_code", -1)) != 0:
		push_warning("Store: acknowledge failed %s" % str(r))


func _g_connected() -> void:
	connected = true
	_billing.query_product_details(PackedStringArray(_ids("google")), 0)
	_billing.query_purchases(0)


func _g_details(r: Dictionary) -> void:
	if int(r.get("response_code", -1)) != 0:
		return
	for pd in r.get("product_details", []):
		if not (pd is Dictionary):
			continue
		var key := _key_for(str(pd.get("product_id", "")), "google")
		var offer = pd.get("one_time_purchase_offer_details", {})
		var p := ""
		if offer is Dictionary:
			p = str(offer.get("formatted_price", ""))
		if p == "":
			p = str(pd.get("formatted_price", pd.get("price", "")))
		if key != "" and p != "":
			prices[key] = p
	prices_changed.emit()


func _g_purchases(r: Dictionary) -> void:
	## what this Google account owns (on start, and on Restore)
	if int(r.get("response_code", -1)) != 0:
		return                                     # (no answer: keep what we knew)
	var seen := {}
	for p in r.get("purchases", []):
		_g_take(p, seen)
	for key in catalogue():
		if not seen.has(key):
			revoke(str(key))                       # (refunded, or never bought on this account)
	busy = false


func _g_updated(r: Dictionary) -> void:
	busy = false
	var code := int(r.get("response_code", -1))
	if code == 0:
		for p in r.get("purchases", []):
			_g_take(p, {})
	elif code == 1:
		_after = Callable()
		note.emit("Purchase cancelled.")
	elif code == 7:
		_billing.query_purchases(0)               # already owned: find it
	else:
		_after = Callable()
		note.emit("The purchase didn't go through (%s)." % str(r.get("debug_message", code)))


func _g_take(p, seen: Dictionary) -> void:
	if not (p is Dictionary):
		return
	var ids: Array = p.get("products", p.get("product_ids", []))
	var state := int(p.get("purchase_state", 0))
	for pid in ids:
		var key := _key_for(str(pid), "google")
		if key == "":
			continue
		if state == 1:                             # PURCHASED
			seen[key] = true
			if not bool(p.get("is_acknowledged", false)):
				_billing.acknowledge_purchase(str(p.get("purchase_token", "")))
			grant(key, "google")
			if remote_on():
				_verify_remote(key, str(p.get("purchase_token", "")))
		elif state == 2:                           # PENDING: not yours until it clears
			seen[key] = owned.has(key)
			note.emit("The purchase is pending -- the game opens up the moment it goes through.")


# ---- round 129: the account's side (dormant until data/cloud.json says verify_purchases) ---------------------------------------

func remote_on() -> bool:
	var cs = Game.cloudsave
	return cs != null and cs.verify_purchases and cs.signed_in()


func sync_remote() -> void:
	## what the signed-in account owns, from the server: an active entitlement opens it on this device, a refunded one closes it
	if not remote_on() or busy:
		return
	var r: Dictionary = await Game.cloudsave.entitlements()
	if not bool(r.get("ok", false)):
		return
	var cat := catalogue()
	for row in r["rows"]:
		var key := str(row.get("product", ""))
		if not cat.has(key):
			continue
		var st := str(row.get("state", ""))
		if st == "active" and not owned.has(key):
			grant(key, "account")
		elif st in ["refunded", "revoked"] and owned.has(key):
			revoke(key)
			note.emit("A purchase on this account was refunded, so it is closed here.")
	for key in owned.keys():
		if cat.has(key):
			var q: Dictionary = await Game.cloudsave.reconcile_purchase(str(key))
			if str(q.get("state", "")) in ["refunded", "revoked"]:
				revoke(str(key))


func _verify_remote(key: String, token: String) -> void:
	var r: Dictionary = await Game.cloudsave.verify_purchase(key, token)
	if not bool(r.get("ok", false)) and int(r.get("code", 0)) in [402, 403]:
		revoke(key)
		note.emit("That purchase could not be verified for this account: %s" % str(r.get("message", "")))


# ---- the App Store ------------------------------------------------------------------------------

func _process(_d: float) -> void:
	if _apple == null:
		return
	while _apple.get_pending_event_count() > 0:
		_a_event(_apple.pop_pending_event())


func _a_event(e) -> void:
	if not (e is Dictionary):
		return
	match str(e.get("type", "")):
		"product_info":
			var ids: Array = e.get("ids", [])
			var lp: Array = e.get("localized_prices", e.get("prices", []))
			for i in ids.size():
				var key := _key_for(str(ids[i]), "apple")
				if key != "" and i < lp.size():
					prices[key] = str(lp[i])
			prices_changed.emit()
		"purchase", "restore":
			if str(e.get("result", "")) == "ok":
				var key2 := _key_for(str(e.get("product_id", "")), "apple")
				if key2 != "":
					grant(key2, str(e["type"]))
			elif str(e.get("result", "")) == "error":
				busy = false
				_after = Callable()
				if str(e.get("type", "")) == "purchase":
					note.emit("The purchase didn't go through.")
		"completed":
			busy = false


# ---- the record on this device -------------------------------------------------------------------

func _load() -> void:
	if not FileAccess.file_exists(file_path):
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(file_path))
	if d is Dictionary and d.get("owned", {}) is Dictionary:
		var keys: Array = (d["owned"] as Dictionary).keys().map(func(k): return str(k))
		var sealed: bool = str(d.get("sig", "")) == _sig(keys, str(d.get("store", "")))
		if sealed and str(d.get("store", "")) == backend:
			for k in keys:
				owned[str(k)] = true
		elif not keys.is_empty():
			tampered = true                  # (edited, copied from another device, or from another store: the store is asked again)
	if d is Dictionary and d.get("told", {}) is Dictionary:
		told = d["told"]


func _save() -> void:
	var f := FileAccess.open(file_path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"owned": owned, "told": told, "store": backend, "sig": _sig(owned.keys(), backend), "at": Time.get_datetime_string_from_system()}))
		f.close()


func catalogue() -> Dictionary:
	## product key -> its store ids: the full game, and every released expansion
	var out: Dictionary = data().get("products", {}).duplicate()
	for e in expansions():
		if str(e.get("status", "")) == "released" and e.get("products", {}) is Dictionary:
			out[str(e["id"])] = e["products"]
	return out


func _ids(store: String) -> Array:
	var out := []
	for key in catalogue():
		out.append(_pid(str(key), store))
	return out


func _pid(key: String, store: String) -> String:
	return str(catalogue().get(key, {}).get(store, key))


func _key_for(pid: String, store: String) -> String:
	for key in catalogue():
		if _pid(str(key), store) == pid:
			return str(key)
	return ""
