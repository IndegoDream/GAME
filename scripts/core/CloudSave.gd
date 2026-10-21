extends Node
## Cloud saves (round 124): one character, any device. Robert, 2026-10-16: "allow syncing with phone ...
## play offline with a larger world, be the mmo".
##
## What it is: a small Supabase client (accounts by email + password, one row per save slot). It does nothing
## until a project address and its public "anon" key are filled in (data/cloud.json, or the Set up button) and
## someone signs in. Every save is pushed a little after it is written; at start-up (and on "Sync now") each
## slot is compared with the cloud and the NEWER one wins -- the one that loses is kept as a backup file
## beside the slot ("...before-sync-<time>.json", the last three), and the cloud keeps the last five
## versions of every slot too (the SQL in tools/cloud/cloud_setup.sql).
##
## Rules it keeps:
##  * the save file on the device is always the one the game reads; the cloud only ever writes the file
##    BEFORE a slot is in play (a slot being played is never swapped under you -- it says so instead)
##  * the lost side of a sync is never thrown away
##  * offline is normal: any failed call leaves everything as it was and says so
##  * the key in data/cloud.json is the public one (it only works with the row-level rules in the SQL)

signal status_changed(text: String)

const CFG_RES := "res://data/cloud.json"
const CFG_USER := "user://cloud_config.json"
const SESSION_FILE := "user://cloud_session.json"
const KEEP_BACKUPS := 3
const SKEW := 2.0                  # seconds: saves this close are "the same"
const TABLE := "game_saves"

var url := ""
var anon := ""
var game := "dungeon-crawl-elite"
var verify_purchases := false      # round 129: data/cloud.json "verify_purchases" -- purchases are checked by the server (supabase/functions/verify-purchase) too; OFF until the project is live
var session := {}                  # access_token, refresh_token, expires_at, email, user_id
var status := "Cloud save is not set up."
var busy := false
var _push_timer: Timer
var _last_auto := 0.0
var _dirty := {}                   # slot -> true, waiting for a push
var _game_ref = null               # the Game autoload (null in tools that test the plain parts)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_config()
	_push_timer = Timer.new()
	_push_timer.one_shot = true
	_push_timer.wait_time = 20.0
	_push_timer.timeout.connect(_push_dirty)
	add_child(_push_timer)
	if signed_in():
		get_tree().create_timer(4.0).timeout.connect(auto_sync)         # a first look at start-up, before a slot is picked


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_RESUMED and signed_in() and is_inside_tree():
		auto_sync()


func auto_sync() -> void:
	## start-up and coming back to the app: quiet, at most once a minute, never swaps a slot under a game being played
	var now := Time.get_unix_time_from_system()
	if busy or now - _last_auto < 60.0 or _game_ref == null:
		return
	_last_auto = now
	var playing := int(_game_ref.slot) if str(_game_ref.background) != "" else -1
	await sync_all(playing)
	if verify_purchases and _game_ref.store != null:
		_game_ref.store.sync_remote()                # round 129: what this account has bought, from the server


func bind(game_node) -> void:
	_game_ref = game_node


# ---- the plain parts (tested without a network) ---------------------------------------------------

static func decide(local_at: float, cloud_at: float) -> String:
	## "same", "push" (this device is newer) or "pull" (the cloud is newer). Zero means "nothing there".
	if cloud_at <= 0.0 and local_at <= 0.0:
		return "same"
	if cloud_at <= 0.0:
		return "push"
	if local_at <= 0.0:
		return "pull"
	if absf(local_at - cloud_at) <= SKEW:
		return "same"
	return "push" if local_at > cloud_at else "pull"


static func clean_base(u: String) -> String:
	var s := u.strip_edges()
	while s.ends_with("/"):
		s = s.substr(0, s.length() - 1)
	if s != "" and not s.begins_with("http"):
		s = "https://" + s
	return s


static func looks_like_email(e: String) -> bool:
	var s := e.strip_edges()
	var at := s.find("@")
	return at > 0 and s.find(".", at) > at + 1 and s.find(" ") < 0


static func device_name() -> String:
	var n := OS.get_name()
	return "phone" if OS.has_feature("mobile") else n.to_lower()


static func summary_of(d: Dictionary) -> String:
	## the one line that tells two devices' saves apart (shown in the Cloud window)
	var nm := str(d.get("char_name", ""))
	return "%s -- %s, %s" % [nm if nm != "" else "(unnamed)", str(d.get("current_level", "village")), "%d min" % int(float(d.get("playtime", 0.0)) / 60.0)]


static func prune_backups(base_path: String, keep: int) -> int:
	## keep the newest `keep` "<slot>.before-sync-*.json" files; returns how many were removed
	var dir := base_path.get_base_dir()
	var stem := base_path.get_file().trim_suffix(".json")
	var d := DirAccess.open(dir)
	if d == null:
		return 0
	var found := []
	for f in d.get_files():
		if f.begins_with(stem + ".before-sync-") and f.ends_with(".json"):
			found.append(f)
	found.sort()                                    # names carry the time, so the oldest sort first
	var gone := 0
	while found.size() > keep:
		DirAccess.remove_absolute(dir.path_join(found.pop_front()))
		gone += 1
	return gone


static func backup_file(path: String) -> String:
	## copy the slot's file aside before the cloud's version takes its place
	if not FileAccess.file_exists(path):
		return ""
	var stamp := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	var to := "%s.before-sync-%s.json" % [path.trim_suffix(".json"), stamp]
	var n := 2
	while FileAccess.file_exists(to):
		to = "%s.before-sync-%s-%d.json" % [path.trim_suffix(".json"), stamp, n]
		n += 1
	var src := FileAccess.open(path, FileAccess.READ)
	if src == null:
		return ""
	var text := src.get_as_text()
	src.close()
	var dst := FileAccess.open(to, FileAccess.WRITE)
	if dst == null:
		return ""
	dst.store_string(text)
	dst.close()
	prune_backups(path, KEEP_BACKUPS)
	return to


# ---- config and session ---------------------------------------------------------------------------

func load_config() -> void:
	for p in [CFG_RES, CFG_USER]:
		if FileAccess.file_exists(p):
			var d = JSON.parse_string(FileAccess.get_file_as_string(p))
			if d is Dictionary:
				if str(d.get("url", "")) != "":
					url = clean_base(str(d["url"]))
				if str(d.get("anon_key", "")) != "":
					anon = str(d["anon_key"]).strip_edges()
				if str(d.get("game", "")) != "":
					game = str(d["game"])
				if p == CFG_RES and d.has("verify_purchases"):
					verify_purchases = bool(d["verify_purchases"])
	if FileAccess.file_exists(SESSION_FILE):
		var s = JSON.parse_string(FileAccess.get_file_as_string(SESSION_FILE))
		if s is Dictionary and str(s.get("access_token", "")) != "":
			session = s
	_set_status(describe())


func save_user_config(u: String, key: String) -> void:
	url = clean_base(u)
	anon = key.strip_edges()
	var f := FileAccess.open(CFG_USER, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"url": url, "anon_key": anon, "game": game}))
		f.close()
	_set_status(describe())


func configured() -> bool:
	return url != "" and anon != ""


func signed_in() -> bool:
	return configured() and str(session.get("access_token", "")) != ""


func email() -> String:
	return str(session.get("email", ""))


func describe() -> String:
	if not configured():
		return "Cloud save is not set up on this device yet."
	if not signed_in():
		return "Cloud save is set up. Sign in to use it."
	return "Signed in as %s." % email()


func _set_status(t: String) -> void:
	status = t
	status_changed.emit(t)


func _store_session() -> void:
	var f := FileAccess.open(SESSION_FILE, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(session))
		f.close()


func _take_session(d: Dictionary, fallback_email: String) -> bool:
	## a sign-in or refresh answer -> the session; false when it has no token
	if str(d.get("access_token", "")) == "":
		return false
	var u: Dictionary = d.get("user", {}) if d.get("user", {}) is Dictionary else {}
	session = {
		"access_token": str(d["access_token"]),
		"refresh_token": str(d.get("refresh_token", session.get("refresh_token", ""))),
		"expires_at": float(d.get("expires_at", Time.get_unix_time_from_system() + float(d.get("expires_in", 3600)))),
		"email": str(u.get("email", fallback_email if fallback_email != "" else session.get("email", ""))),
		"user_id": str(u.get("id", session.get("user_id", ""))),
	}
	_store_session()
	return true


# ---- one HTTP call ----------------------------------------------------------------------------------

func _call(method: int, path: String, body = null, extra: PackedStringArray = PackedStringArray(), authed: bool = true) -> Dictionary:
	## {"ok", "code", "data"} -- never throws; code 0 = could not reach the server
	if not configured():
		return {"ok": false, "code": 0, "data": null, "error": "Cloud save is not set up."}
	if authed and signed_in() and float(session.get("expires_at", 0.0)) - 30.0 < Time.get_unix_time_from_system():
		await _refresh()
	var h := PackedStringArray(["apikey: " + anon, "Content-Type: application/json"])
	h.append("Authorization: Bearer " + (str(session.get("access_token", "")) if authed and signed_in() else anon))
	h.append_array(extra)
	var http := HTTPRequest.new()
	http.timeout = 12.0
	add_child(http)
	var err := http.request(url + path, h, method, "" if body == null else (body if body is String else JSON.stringify(body)))
	if err != OK:
		http.queue_free()
		return {"ok": false, "code": 0, "data": null, "error": "Could not start the request."}
	var r: Array = await http.request_completed
	http.queue_free()
	var code := int(r[1])
	var text := (r[3] as PackedByteArray).get_string_from_utf8()
	var data = JSON.parse_string(text) if text.strip_edges() != "" else null
	var ok: bool = int(r[0]) == HTTPRequest.RESULT_SUCCESS and code >= 200 and code < 300
	var msg := ""
	if not ok:
		if int(r[0]) != HTTPRequest.RESULT_SUCCESS:
			msg = "Can't reach the cloud right now."
		elif data is Dictionary:
			msg = str(data.get("error_description", data.get("msg", data.get("message", data.get("error", "Error %d" % code)))))
		else:
			msg = "Error %d" % code
	return {"ok": ok, "code": code if int(r[0]) == HTTPRequest.RESULT_SUCCESS else 0, "data": data, "error": msg}


func _refresh() -> bool:
	var rt := str(session.get("refresh_token", ""))
	if rt == "":
		return false
	var r: Dictionary = await _call(HTTPClient.METHOD_POST, "/auth/v1/token?grant_type=refresh_token", {"refresh_token": rt}, PackedStringArray(), false)
	if r["ok"] and r["data"] is Dictionary and _take_session(r["data"], ""):
		return true
	if int(r["code"]) in [400, 401]:
		session = {}                       # the sign-in has lapsed for good: ask again
		_store_session()
	return false


# ---- accounts ---------------------------------------------------------------------------------------

func sign_in(mail: String, password: String) -> Dictionary:
	if not looks_like_email(mail):
		return {"ok": false, "message": "That doesn't look like an email address."}
	if password.length() < 6:
		return {"ok": false, "message": "The password needs at least 6 characters."}
	var r: Dictionary = await _call(HTTPClient.METHOD_POST, "/auth/v1/token?grant_type=password", {"email": mail.strip_edges(), "password": password}, PackedStringArray(), false)
	if r["ok"] and r["data"] is Dictionary and _take_session(r["data"], mail.strip_edges()):
		_set_status(describe())
		return {"ok": true, "message": describe()}
	return {"ok": false, "message": str(r.get("error", "Could not sign in.")) if int(r["code"]) != 400 else "That email and password don't match."}


func sign_up(mail: String, password: String) -> Dictionary:
	if not looks_like_email(mail):
		return {"ok": false, "message": "That doesn't look like an email address."}
	if password.length() < 6:
		return {"ok": false, "message": "The password needs at least 6 characters."}
	var r: Dictionary = await _call(HTTPClient.METHOD_POST, "/auth/v1/signup", {"email": mail.strip_edges(), "password": password}, PackedStringArray(), false)
	if not r["ok"]:
		return {"ok": false, "message": str(r.get("error", "Could not make the account."))}
	if r["data"] is Dictionary and _take_session(r["data"], mail.strip_edges()):
		_set_status(describe())
		return {"ok": true, "message": "Account made. " + describe()}
	return {"ok": true, "message": "Account made. Check %s for the confirmation link, then sign in." % mail.strip_edges()}


func sign_out() -> void:
	if signed_in():
		await _call(HTTPClient.METHOD_POST, "/auth/v1/logout", "")
	session = {}
	_store_session()
	_dirty.clear()
	_set_status(describe())


# ---- saves ------------------------------------------------------------------------------------------

func list_saves() -> Dictionary:
	## {"ok", "rows": [{slot, saved_at, device, summary}], "message"}
	var r: Dictionary = await _call(HTTPClient.METHOD_GET, "/rest/v1/%s?game=eq.%s&select=slot,saved_at,device,summary,updated_at&order=slot" % [TABLE, game.uri_encode()])
	if not r["ok"] or not (r["data"] is Array):
		return {"ok": false, "rows": [], "message": str(r.get("error", "Could not read the cloud."))}
	return {"ok": true, "rows": r["data"], "message": ""}


# ---- round 129: purchases, checked by the server (all of it dormant while verify_purchases is false) ----------------------

func entitlements() -> Dictionary:
	## {"ok", "rows": [{product, state}], "message"}
	var r: Dictionary = await _call(HTTPClient.METHOD_GET, "/rest/v1/entitlements?game=eq.%s&select=product,state" % game.uri_encode())
	if not r["ok"] or not (r["data"] is Array):
		return {"ok": false, "rows": [], "message": str(r.get("error", "Could not read the account."))}
	return {"ok": true, "rows": r["data"], "message": ""}


func verify_purchase(product: String, token: String) -> Dictionary:
	## ask the server to check a Google Play purchase with Google and tie it to this account
	var r: Dictionary = await _call(HTTPClient.METHOD_POST, "/functions/v1/verify-purchase", {"product": product, "purchaseToken": token})
	var st := str((r["data"] as Dictionary).get("state", "")) if r["data"] is Dictionary else ""
	return {"ok": r["ok"], "code": r["code"], "state": st, "message": str(r.get("error", ""))}


func reconcile_purchase(product: String) -> Dictionary:
	var r: Dictionary = await _call(HTTPClient.METHOD_POST, "/functions/v1/verify-purchase", {"product": product, "reconcile": true})
	var st := str((r["data"] as Dictionary).get("state", "")) if r["data"] is Dictionary else ""
	return {"ok": r["ok"], "code": r["code"], "state": st, "message": str(r.get("error", ""))}


func push(slot: int, text: String) -> Dictionary:
	var d = JSON.parse_string(text)
	if not (d is Dictionary) or d.is_empty() or str(d.get("background", "")) == "":
		return {"ok": false, "message": "Nothing to upload: that slot has no character."}
	var uid := str(session.get("user_id", ""))
	var row := {"user_id": uid, "game": game, "slot": slot, "saved_at": float(d.get("saved_at", 0.0)),
		"device": device_name(), "summary": summary_of(d), "data": d}
	var r: Dictionary = await _call(HTTPClient.METHOD_POST, "/rest/v1/%s?on_conflict=user_id,game,slot" % TABLE, row, PackedStringArray(["Prefer: resolution=merge-duplicates,return=minimal"]))
	if r["ok"]:
		return {"ok": true, "message": "Slot %d uploaded." % slot}
	return {"ok": false, "message": str(r.get("error", "Upload failed."))}


func pull(slot: int) -> Dictionary:
	## {"ok", "found", "text", "saved_at", "device"}
	var r: Dictionary = await _call(HTTPClient.METHOD_GET, "/rest/v1/%s?game=eq.%s&slot=eq.%d&select=data,saved_at,device" % [TABLE, game.uri_encode(), slot])
	if not r["ok"] or not (r["data"] is Array):
		return {"ok": false, "found": false, "message": str(r.get("error", "Could not read the cloud."))}
	if (r["data"] as Array).is_empty():
		return {"ok": true, "found": false}
	var row: Dictionary = r["data"][0]
	return {"ok": true, "found": true, "text": JSON.stringify(row.get("data", {}), "  "), "saved_at": float(row.get("saved_at", 0.0)), "device": str(row.get("device", ""))}


static func when_mode() -> String:
	## "saves" (a little after every save), "floor" (at the start of each dungeon floor and back in the village) or "manual"
	var G = load("res://scripts/core/Gfx.gd")
	G.load_settings()
	var m := str(G.settings.get("cloud_when", "saves"))
	return m if m in G.CLOUD_WHEN else "saves"


func mark_dirty(slot: int) -> void:
	## the game calls this after every save. "saves": the upload waits a little so a run of saves is one trip.
	## "floor": the slot is remembered and goes up when a floor starts (on_travel). "manual": nothing goes up by itself.
	if not signed_in():
		return
	var m := when_mode()
	if m == "manual":
		return
	_dirty[slot] = true
	if m == "saves":
		_start_push_timer()


func on_travel(level_id: String) -> void:
	## the game calls this as you go somewhere: in "floor" mode a new dungeon floor (or the village) sends what was saved
	if when_mode() == "floor" and signed_in() and not _dirty.is_empty() and (level_id.begins_with("floor") or level_id == "village"):
		_start_push_timer(2.0)


func _start_push_timer(wait: float = 20.0) -> void:
	if _push_timer and is_inside_tree() and (_push_timer.is_stopped() or wait < _push_timer.time_left):
		_push_timer.start(wait)


func _push_dirty() -> void:
	if _game_ref == null or busy or not signed_in():
		return
	var slots := _dirty.keys()
	_dirty.clear()
	for s in slots:
		var p: String = _game_ref.slot_path(int(s))
		if FileAccess.file_exists(p):
			var r: Dictionary = await push(int(s), FileAccess.get_file_as_string(p))
			if not r["ok"]:
				_dirty[s] = true            # try again with the next save
				_set_status(str(r["message"]))


func sync_all(active_slot_in_play: int = -1) -> Dictionary:
	## compare every slot with the cloud; the newer side wins, the other is kept as a backup.
	## active_slot_in_play: a slot that is being played right now is never overwritten (it is reported instead).
	## Returns {"ok", "lines": [String], "pulled": [slot], "pushed": [slot], "waiting": [slot]}
	var out := {"ok": false, "lines": [], "pulled": [], "pushed": [], "waiting": []}
	if not signed_in():
		out["lines"].append(describe())
		return out
	if busy:
		out["lines"].append("A sync is already running.")
		return out
	if _game_ref == null:
		out["lines"].append("Not ready yet.")
		return out
	busy = true
	var ls: Dictionary = await list_saves()
	if not ls["ok"]:
		busy = false
		out["lines"].append(str(ls["message"]))
		_set_status(str(ls["message"]))
		return out
	var cloud := {}
	for row in ls["rows"]:
		cloud[int(row.get("slot", 0))] = row
	for s in range(1, int(_game_ref.SLOTS) + 1):
		var p: String = _game_ref.slot_path(s)
		var local_at := 0.0
		var local_ok := false
		if FileAccess.file_exists(p):
			var d = JSON.parse_string(FileAccess.get_file_as_string(p))
			if d is Dictionary and str(d.get("background", "")) != "":
				local_at = float(d.get("saved_at", 0.0))
				local_ok = true
		var cloud_at := float(cloud[s].get("saved_at", 0.0)) if cloud.has(s) else 0.0
		match decide(local_at if local_ok else 0.0, cloud_at):
			"same":
				if local_ok or cloud_at > 0.0:
					out["lines"].append("Slot %d: in step." % s)
			"push":
				var r: Dictionary = await push(s, FileAccess.get_file_as_string(p))
				out["lines"].append("Slot %d: %s" % [s, "this device is newer -- uploaded." if r["ok"] else str(r["message"])])
				if r["ok"]:
					out["pushed"].append(s)
			"pull":
				if s == active_slot_in_play:
					out["waiting"].append(s)
					out["lines"].append("Slot %d: the cloud has a newer save (%s) -- you're playing this slot, so it was left alone. Use 'Take the cloud save' to switch." % [s, str(cloud[s].get("device", "another device"))])
					continue
				var g: Dictionary = await pull(s)
				if g["ok"] and g["found"]:
					var kept := backup_file(p)
					if _write(p, str(g["text"])):
						out["pulled"].append(s)
						out["lines"].append("Slot %d: the cloud was newer (%s) -- took it.%s" % [s, str(g["device"]), " Your old one is kept." if kept != "" else ""])
					else:
						out["lines"].append("Slot %d: could not write the cloud save." % s)
				else:
					out["lines"].append("Slot %d: %s" % [s, str(g.get("message", "nothing there"))])
	busy = false
	out["ok"] = true
	_set_status("Synced.  " + "  ".join(out["lines"]))
	return out


func take_cloud(slot: int) -> Dictionary:
	## the slot being played: replace the device's file with the cloud's (old one backed up). The caller reloads.
	if not signed_in() or _game_ref == null:
		return {"ok": false, "message": describe()}
	var g: Dictionary = await pull(slot)
	if not g["ok"]:
		return {"ok": false, "message": str(g.get("message", "Could not read the cloud."))}
	if not g["found"]:
		return {"ok": false, "message": "The cloud has nothing for slot %d." % slot}
	var p: String = _game_ref.slot_path(slot)
	backup_file(p)
	if not _write(p, str(g["text"])):
		return {"ok": false, "message": "Could not write the cloud save."}
	return {"ok": true, "message": "Took the cloud save for slot %d (from %s). Your old one is kept." % [slot, str(g["device"])]}


func _write(path: String, text: String) -> bool:
	## the game's own safe writer (new file checked, last good one kept as .bak) when it is there
	if _game_ref != null and _game_ref.has_method("_write_safely"):
		return _game_ref._write_safely(path, text)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(text)
	f.close()
	return true
