extends "res://scripts/systems/GameSystem.gd"
## Round 163: the guided first hour. Robert, 2026-10-19: "Yes add them all".
## Ten small steps, one line at a time under the top-left stats, each noticed from what you really do (moving, a talk, a first
## swing, a kill, a quick art, a gather, the menu, today's goals, a sit, the first floor). The keys it names are the keys YOU have
## set (Controls.gd); on a touch screen it names buttons. It never blocks anything; hints off hides it (Menu > Guide).
## State: flags "fh:<id>" (saved with the game), so an old save simply shows what is left, and a long-played one shows nothing.

const GfxS := preload("res://scripts/core/Gfx.gd")
var cfg := {}
var _moved := 0.0
var _sat := 0.0
var _last := ""        # last line shown, so the HUD only refreshes on a change


func setup(game) -> void:
	super.setup(game)
	var d = G._load_json("res://data/firsthour.json", {})
	cfg = d if d is Dictionary else {}


func reset() -> void:
	_moved = 0.0
	_sat = 0.0
	_last = ""


func steps() -> Array:
	return cfg.get("steps", [])


func done(id: String) -> bool:
	return G.has_flag("fh:" + id)


func count_done() -> int:
	var n := 0
	for s in steps():
		if done(str(s.get("id", ""))):
			n += 1
	return n


func finished() -> bool:
	return G.has_flag("fh:all") or count_done() >= steps().size()


func current() -> Dictionary:
	for s in steps():
		if not done(str(s.get("id", ""))):
			return s
	return {}


func active() -> bool:
	if cfg.is_empty() or finished():
		return false
	if G.playtime > float(cfg.get("skip_after_playtime", 3600.0)) and count_done() == 0:
		return false                     # a long-played save does not need telling how to walk
	return preload("res://scripts/systems/Guide.gd").hints_on()


func is_touch() -> bool:
	var m := str(GfxS.settings.get("touch", "auto"))
	return m == "on" or (m == "auto" and (DisplayServer.is_touchscreen_available() or OS.has_feature("mobile")))


func key_of(action: String) -> String:
	var C = preload("res://scripts/core/Controls.gd")
	var ks: Array = C.keys(action)
	if ks.is_empty():
		return {"attack": I18n.t("left mouse button")}.get(action, action)
	if DisplayServer.get_name() == "headless":
		return action
	return OS.get_keycode_string(DisplayServer.keyboard_get_keycode_from_physical(int(ks[0])))


func line_of(s: Dictionary) -> String:
	if s.is_empty():
		return ""
	if is_touch():
		return I18n.t(str(s.get("touch", s.get("text", ""))))
	var t := I18n.t(str(s.get("text", "")))
	if t.find("%s") < 0:
		return t
	if s.has("quick"):
		var pad := ""
		if Input.get_connected_joypads().size() > 0:
			pad = I18n.t("  (pad: hold Back + A)")
		return t % G.quick_key_label(int(s["quick"])) + pad
	var ks := []
	for a in s.get("keys", []):
		ks.append(key_of(str(a)))
	return t % " ".join(ks)


func hud_line() -> String:
	if not active():
		return ""
	var s := current()
	return I18n.t("First steps %d/%d  --  %s") % [count_done() + 1, steps().size(), line_of(s)]


func _mark(s: Dictionary) -> void:
	var id := str(s.get("id", ""))
	if done(id):
		return
	G.set_flag("fh:" + id)
	if finished():
		_finish()
	elif active():
		var nx := current()
		G.message.emit(I18n.t("Well done. Next: %s") % line_of(nx))
	G.stats_changed.emit()


func _finish() -> void:
	if G.has_flag("fh:all"):
		return
	G.set_flag("fh:all")
	var r: Dictionary = cfg.get("finish_reward", {})
	if r.has("gold"):
		G.add_item("gold", int(r["gold"]), false)
	for it in r.get("items", {}):
		G.add_item(str(it), int(r["items"][it]))
	G.message.emit(I18n.t("FIRST HOUR DONE. You know the way now -- the rest of the deep is yours to find out. (A small gift for the road.)"))
	G.log_event("first_hour_done", {})


func on_event(kind: String, d: Dictionary) -> void:
	if cfg.is_empty() or finished():
		return
	for s in steps():
		if done(str(s.get("id", ""))):
			continue
		if not (s.get("ev", []) as Array).has(kind):
			continue
		if s.has("prefix") and not str(d.get("id", "")).begins_with(str(s["prefix"])):
			continue
		if s.has("page") and str(d.get("page", "")) != str(s["page"]):
			continue
		_mark(s)


func _step(id: String) -> Dictionary:
	for s in steps():
		if str(s.get("id", "")) == id:
			return s
	return {}


func meditate(secs: float, _shares: Dictionary, _aid: float) -> void:
	if cfg.is_empty() or finished():
		return
	_sat += secs
	var s := _step("sit")
	if not s.is_empty() and not done("sit") and _sat >= float(s.get("need", 20)):
		_mark(s)


func tick(delta: float) -> void:
	if cfg.is_empty() or finished() or G.world_frozen:
		return
	if not done("move"):
		for a in ["move_forward", "move_back", "move_left", "move_right"]:
			if Input.is_action_pressed(a):
				_moved += delta
				break
		if _moved > 1.2:
			_mark(_step("move"))
	if not done("attack") and Input.is_action_just_pressed("attack"):
		_mark(_step("attack"))
