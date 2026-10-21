extends SceneTree
## round 124: cloud save, against tools/cloud/mock_supabase.py (start it first: python3 tools/cloud/mock_supabase.py 8791)
##   godot --headless --path . --script res://tools/cloud_check.gd -- 8791
var passed := 0
var failed := 0
var frames := 0
var started := false

func check(n: String, ok: bool, d: String = "") -> void:
	if ok: passed += 1
	else:
		failed += 1
		print("  FAIL  " + n + ("  [" + d + "]" if d != "" else ""))

func _process(_dt: float) -> bool:
	frames += 1
	if frames < 4 or started:
		return false
	started = true
	_run()
	return false

func _save_text(at: float, name: String, place: String = "village") -> String:
	return JSON.stringify({"background": "fighter", "char_name": name, "saved_at": at, "current_level": place, "playtime": 600.0, "realm": 1})

func _put(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()

func _run() -> void:
	var port := "8791"
	for a in OS.get_cmdline_user_args():
		port = a
	var G = root.get_node("Game")
	var CS = load("res://scripts/core/CloudSave.gd")
	# ---- the plain parts
	check("decide: same", CS.decide(100.0, 101.0) == "same")
	check("decide: push", CS.decide(200.0, 100.0) == "push")
	check("decide: pull", CS.decide(100.0, 200.0) == "pull")
	check("decide: nothing local pulls", CS.decide(0.0, 50.0) == "pull")
	check("decide: nothing in the cloud pushes", CS.decide(50.0, 0.0) == "push")
	check("decide: nothing anywhere", CS.decide(0.0, 0.0) == "same")
	check("clean_base", CS.clean_base(" abc.supabase.co/ ") == "https://abc.supabase.co")
	check("email looks", CS.looks_like_email("a@b.co") and not CS.looks_like_email("a@b") and not CS.looks_like_email("a b@c.d"))
	# ---- a clean test area
	G.save_base = "user://cloudtest"
	for f in DirAccess.get_files_at("user://"):
		if f.begins_with("cloudtest") or f.begins_with("cloud_session"):
			DirAccess.remove_absolute("user://" + f)
	var cs = G.cloudsave
	check("the game has a cloud client", cs != null)
	cs.session = {}
	cs.url = ""
	cs.anon = ""
	var r: Dictionary = await cs.sign_in("robert@example.com", "correct horse")
	check("not set up: sign-in says so, no crash", not r["ok"])
	cs.url = CS.clean_base("http://127.0.0.1:" + port)
	cs.anon = "test-anon-key"
	check("configured", cs.configured() and not cs.signed_in())
	r = await cs.sign_in("robert@example.com", "wrong password")
	check("a wrong password is refused kindly", not r["ok"] and str(r["message"]).find("don't match") >= 0, str(r))
	r = await cs.sign_in("nope", "whatever1")
	check("a bad email is refused before the network", not r["ok"])
	r = await cs.sign_up("new@example.com", "abc")
	check("a short password is refused", not r["ok"])
	r = await cs.sign_up("new@example.com", "longenough")
	check("sign-up works and asks for confirmation", r["ok"] and str(r["message"]).find("confirmation") >= 0, str(r))
	r = await cs.sign_in("robert@example.com", "correct horse")
	check("sign-in works", r["ok"] and cs.signed_in() and cs.email() == "robert@example.com", str(r))
	check("the session is kept on disk", FileAccess.file_exists("user://cloud_session.json"))
	# ---- push and read back
	var p1: String = G.slot_path(1)
	_put(p1, _save_text(1000.0, "Mara", "floor3"))
	var pr: Dictionary = await cs.push(1, FileAccess.get_file_as_string(p1))
	check("push slot 1", pr["ok"], str(pr))
	var ls: Dictionary = await cs.list_saves()
	check("list shows slot 1", ls["ok"] and (ls["rows"] as Array).size() == 1 and int(ls["rows"][0]["slot"]) == 1, str(ls))
	pr = await cs.push(2, "{}")
	check("an empty slot is not uploaded", not pr["ok"])
	var g: Dictionary = await cs.pull(1)
	check("pull gives the same save back", g["ok"] and g["found"] and JSON.parse_string(g["text"])["char_name"] == "Mara")
	g = await cs.pull(3)
	check("pull of nothing says not found", g["ok"] and not g["found"])
	# ---- sync: another device saved slot 2 (new here) and a newer slot 1
	var other: Dictionary = {"user_id": "u-1", "game": cs.game, "slot": 2, "saved_at": 5000.0, "device": "phone", "summary": "x", "data": JSON.parse_string(_save_text(5000.0, "Phoneman"))}
	await _raw_push(cs, other)
	other = {"user_id": "u-1", "game": cs.game, "slot": 1, "saved_at": 3000.0, "device": "phone", "summary": "x", "data": JSON.parse_string(_save_text(3000.0, "Mara", "floor9"))}
	await _raw_push(cs, other)
	var s: Dictionary = await cs.sync_all(1)       # slot 1 is being played here
	check("sync ok", s["ok"], str(s))
	check("a slot being played is not swapped under you", (s["waiting"] as Array).has(1) and JSON.parse_string(FileAccess.get_file_as_string(p1))["saved_at"] == 1000.0)
	check("a new slot arrives", (s["pulled"] as Array).has(2) and FileAccess.file_exists(G.slot_path(2)) and JSON.parse_string(FileAccess.get_file_as_string(G.slot_path(2)))["char_name"] == "Phoneman")
	s = await cs.sync_all(-1)                      # nothing in play: slot 1 is taken, the old one kept
	check("a newer cloud slot is taken when not in play", (s["pulled"] as Array).has(1) and JSON.parse_string(FileAccess.get_file_as_string(p1))["saved_at"] == 3000.0, str(s))
	var kept := 0
	for f in DirAccess.get_files_at("user://"):
		if f.begins_with("cloudtest_slot1.before-sync-"):
			kept += 1
			check("the old save is kept intact", JSON.parse_string(FileAccess.get_file_as_string("user://" + f))["saved_at"] == 1000.0)
	check("one backup of slot 1", kept == 1, str(kept))
	# the device newer than the cloud pushes
	_put(p1, _save_text(9000.0, "Mara", "floor12"))
	s = await cs.sync_all(-1)
	check("a newer device uploads", (s["pushed"] as Array).has(1), str(s))
	g = await cs.pull(1)
	check("the cloud now has it", float(g["saved_at"]) == 9000.0)
	s = await cs.sync_all(-1)
	check("then everything is in step", (s["pulled"] as Array).is_empty() and (s["pushed"] as Array).is_empty(), str(s))
	# the backups never pile up
	for i in 6:
		_put(p1, _save_text(9000.0 + i, "Mara"))
		CS.backup_file(p1)
	var n := 0
	for f in DirAccess.get_files_at("user://"):
		if f.begins_with("cloudtest_slot1.before-sync-"):
			n += 1
	check("only the last three backups stay", n == CS.KEEP_BACKUPS, str(n))
	# ---- the token runs out: it is refreshed by itself
	cs.session["expires_at"] = 1.0
	ls = await cs.list_saves()
	check("an expired token is renewed", ls["ok"] and float(cs.session["expires_at"]) > 1000.0, str(ls))
	# ---- the cloud is not there: nothing is lost
	var before := FileAccess.get_file_as_string(p1)
	var real_url: String = cs.url
	cs.url = "http://127.0.0.1:1"
	s = await cs.sync_all(-1)
	check("offline: sync says so and changes nothing", not s["ok"] and FileAccess.get_file_as_string(p1) == before, str(s))
	cs.url = real_url
	# ---- a save made while signed in is marked for upload
	cs.mark_dirty(1)
	check("saving marks the slot to upload", cs._dirty.has(1))
	cs._dirty.clear()
	# ---- when the upload happens (a setting)
	var Gx = load("res://scripts/core/Gfx.gd")
	var keep_when = Gx.settings.get("cloud_when", "saves")
	Gx.settings["cloud_when"] = "manual"
	cs._push_timer.stop()
	cs._dirty.clear()
	cs.mark_dirty(1)
	check("manual: a save does not upload by itself", cs._dirty.is_empty() and cs._push_timer.is_stopped())
	Gx.settings["cloud_when"] = "floor"
	cs.mark_dirty(1)
	check("floor: a save is remembered but waits", cs._dirty.has(1) and cs._push_timer.is_stopped())
	cs.on_travel("valley")
	check("floor: going to the valley sends nothing", cs._push_timer.is_stopped())
	cs.on_travel("floor3")
	check("floor: a new dungeon floor sends it", not cs._push_timer.is_stopped())
	cs._push_timer.stop()
	cs.on_travel("village")
	check("floor: so does the village", not cs._push_timer.is_stopped())
	cs._push_timer.stop()
	cs._dirty.clear()
	Gx.settings["cloud_when"] = "saves"
	cs.mark_dirty(1)
	check("saves: a save starts the upload clock", cs._dirty.has(1) and not cs._push_timer.is_stopped())
	cs._push_timer.stop()
	cs._dirty.clear()
	var seen_w := {}
	for i in 3:
		seen_w[Gx.next_cloud_when()] = true
	check("the setting cycles through three ways", seen_w.size() == 3)
	Gx.settings["cloud_when"] = keep_when
	Gx.save_settings()
	# ---- round 129: purchases checked by the server (against the mock's function and table)
	cs.verify_purchases = true
	var S = G.store
	S.file_path = "user://cloudtest_store.json"
	S.backend = "google"
	S.owned = {}
	check("remote purchase checks are on when flagged and signed in", S.remote_on())
	var rv: Dictionary = await cs.verify_purchase("full_game", "good-token-aaaaaaaaaaaaaaaaaaaa")
	check("the server verifies a good token", rv["ok"] and rv["state"] == "active", str(rv))
	rv = await cs.verify_purchase("full_game", "bogus-token-aaaaaaaaaaaaaaaaaaaa")
	check("a bad token is refused (402)", not rv["ok"] and int(rv["code"]) == 402, str(rv))
	var ents: Dictionary = await cs.entitlements()
	check("the account lists what it owns", ents["ok"] and ents["rows"].size() == 1 and ents["rows"][0]["product"] == "full_game", str(ents))
	await S.sync_remote()
	check("a new device gets the purchase from the account", S.owned.has("full_game"))
	S.owned = {"full_game": true, "style_pack": true}
	await S._verify_remote("style_pack", "bogus-token-aaaaaaaaaaaaaaaaaaaa")
	check("a purchase the server rejects is closed on the device", not S.owned.has("style_pack") and S.owned.has("full_game"))
	await cs.verify_purchase("style_pack", "refund-token-aaaaaaaaaaaaaaaaaaa")
	S.owned = {"full_game": true, "style_pack": true}
	await S.sync_remote()
	check("a refunded purchase is closed on the device", not S.owned.has("style_pack") and S.owned.has("full_game"), str(S.owned))
	cs.verify_purchases = false
	check("flag off: nothing remote happens", not S.remote_on())
	S.backend = "full"
	# ---- sign out
	await cs.sign_out()
	check("signed out", not cs.signed_in() and not FileAccess.get_file_as_string("user://cloud_session.json").contains("tok"))
	for f in DirAccess.get_files_at("user://"):
		if f.begins_with("cloudtest") or f.begins_with("cloud_session"):
			DirAccess.remove_absolute("user://" + f)
	print("CLOUD CHECK %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)

func _raw_push(cs, row: Dictionary) -> void:
	await cs._call(HTTPClient.METHOD_POST, "/rest/v1/game_saves?on_conflict=user_id,game,slot", row, PackedStringArray(["Prefer: resolution=merge-duplicates,return=minimal"]))
