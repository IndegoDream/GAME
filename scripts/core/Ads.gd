extends Node
## Ads (round 58): the free tier on phones, gently.
## Robert, 2026-10-05: "after level 5 ... ads on the free tier, still able to
## complete the game, but every so often an ad will pop up -- I don't want it
## to be too distracting, but I do want to be profitable."
##
##   where     only below the free floors (Store.free_depth, floor 5), only
##             on a phone without the full game (Store.ads_on). Steam, the
##             box's builds, and anyone who bought the full game: never.
##   breaks    an ad only at a natural break -- arriving on a deeper floor by
##             the stairs, or reaching a town (data/store.json ads.breaks) --
##             and only when you're safe: not hurt in the last few seconds, no
##             foe near. At most one every ten minutes (every_s), none in the
##             first minutes of a sitting (first_after_s), a cap an hour.
##             A short line says "A short break." first; the game pauses and
##             goes quiet while it plays, and picks up where it was.
##   gifts     ads the player CHOOSES to watch, for something: getting back the
##             gold lost in a fall, or the deep's blessing (insight and luck for
##             a while). Never offered to someone who bought the full game.
##   consent   Google's consent form (UMP) where the law asks for it (EU/UK),
##             before any ad; a "Privacy choices" button in the menu then.
##
## The native side is the Poing Studios AdMob plugin (addons/admob), reached
## only through scripts/AdMobBridge.gd -- loaded on a phone that has it, so
## the web and Steam builds (which leave the plugin out) never touch it.
## backend "test" is a pretend ad network for the tests (and ELIET_FREE_TIER=1).

signal started(kind: String)          # an ad is on screen (the game is paused)
signal finished(kind: String)         # it's gone (the game carries on)
signal gift_given(gift: String)

const FILE := "user://ads.json"

var backend := "none"                 # "admob" | "test" | "none"
var file_path := FILE
var showing := ""                     # "" | "break" | a gift id
var test_answer := "ok"               # the pretend network: "ok" | "skip" (closed early) | "fail" (no ad)
var _bridge = null
var _rec := {"shown": [], "gifts": {}}
var _session_start := 0.0
var _gift_cb := Callable()
var _gift_earned := false
var _was_paused := false
var _was_muted := false
var _pending_break := ""
var _break_t := 0.0
var last_fall_gold := 0               # what the last fall cost (a gift can give it back)
var assume_clear := false             # (tools) skip the look for foes nearby


func cfg() -> Dictionary:
	return Game.store.data().get("ads", {}) if Game.store else {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_session_start = _now()
	_load()
	start(pick_backend())


func pick_backend() -> String:
	if Game.store == null:
		return "none"
	if Game.store.backend == "test":
		return "test"
	if (OS.has_feature("android") or OS.has_feature("ios")) and Engine.has_singleton("PoingGodotAdMob") and ResourceLoader.exists("res://scripts/core/AdMobBridge.gd"):
		return "admob"
	return "none"


func start(kind: String) -> void:
	var want_bridge: bool = kind == "admob" and Game.store != null and Game.store.ads_on()
	if kind == backend and (_bridge != null) == want_bridge:
		return                                  # (nothing changed: keep what's loaded)
	backend = kind
	if _bridge:
		_bridge.queue_free()
		_bridge = null
	if want_bridge:
		_bridge = load("res://scripts/core/AdMobBridge.gd").new()
		_bridge.name = "AdMobBridge"
		add_child(_bridge)
		_bridge.setup(self, cfg())


func _now() -> float:
	return Time.get_unix_time_from_system()


# ---- the rules -------------------------------------------------------------------------------

func live() -> bool:
	return backend != "none" and Game.store != null and Game.store.ads_on()


func break_why_not(kind: String) -> String:
	## "" when an ad break may happen now; otherwise why not (for the tests and the log)
	if not live():
		return "off"
	var c := cfg()
	if not (kind in c.get("breaks", ["descend", "haven"])):
		return "not a break"
	if Game.store.depth_of(str(Game.current_level)) <= Game.store.free_depth():
		return "free floors"
	if showing != "":
		return "already showing"
	var now := _now()
	if now - _session_start < float(c.get("first_after_s", 420)):
		return "just sat down"
	var shown: Array = _rec.get("shown", [])
	if not shown.is_empty() and now - float(shown[-1]) < float(c.get("every_s", 600)):
		return "too soon"
	var hour := 0
	for t in shown:
		if now - float(t) < 3600.0:
			hour += 1
	if hour >= int(c.get("max_per_hour", 4)):
		return "hour's cap"
	if not calm():
		return "not safe"
	if Game.arena_active() or str(Game.current_level).begins_with("tribulation:"):
		return "a trial"
	if backend == "admob" and not (_bridge and _bridge.ready_break()):
		return "no ad loaded"
	return ""


func calm() -> bool:
	## not hurt a moment ago, and no foe close
	var c := cfg()
	if _now() - Game.last_hurt_at < float(c.get("calm_s", 10)):
		return false
	var tree := get_tree()
	var p = tree.get_first_node_in_group("player") if tree else null
	if p == null or assume_clear:
		return true
	var near := float(c.get("foe_clear_m", 14))
	for e in tree.get_nodes_in_group("enemy"):
		if e is Node3D and e.is_inside_tree() and e.get("_dead") != true and e.get("_dummy") != true and (e as Node3D).global_position.distance_to(p.global_position) < near:
			return false
	return true


func on_arrival(from_id: String, level_id: String, is_town: bool, hud) -> void:
	## Main, each time you arrive somewhere: after a fall that cost gold, the
	## offer to win it back (at the next quiet moment); otherwise maybe a break --
	## only on the way down or reaching a town
	if not live():
		return
	if last_fall_gold > 0:
		if gift_why_not("recover_gold") == "" and hud and hud.has_method("queue_gift"):
			hud.queue_gift("recover_gold")
		else:
			last_fall_gold = 0
		return
	if is_town:
		at_break("haven")
	elif from_id != "" and Game.store.depth_of(level_id) > Game.store.depth_of(from_id):
		at_break("descend")


func at_break(kind: String) -> void:
	## Main calls this when you arrive somewhere; the ad (if any) waits a breath
	if break_why_not(kind) != "":
		return
	_pending_break = kind
	_break_t = float(cfg().get("delay_s", 1.2))


func _process(delta: float) -> void:
	if _pending_break == "":
		return
	_break_t -= delta
	if _break_t > 0.0:
		return
	var kind := _pending_break
	_pending_break = ""
	if break_why_not(kind) == "":          # (still safe a breath later?)
		show_break(kind)


func show_break(kind: String) -> void:
	Game.message.emit(str(cfg().get("notice", "A short break.")))
	_begin("break")
	_record_shown()
	Game.log_event("ad_break", {"at": kind, "floor": Game.store.depth_of(str(Game.current_level))})
	match backend:
		"admob":
			_bridge.show_break()
		"test":
			if test_answer == "fail":
				_end()
			else:
				_end.call_deferred()
		_:
			_end()


# ---- gifts (ads you choose) ---------------------------------------------------------------------

func gift(id: String) -> Dictionary:
	return cfg().get("gifts", {}).get(id, {})


func gift_why_not(id: String) -> String:
	if not live():
		return "off"
	var g := gift(id)
	if g.is_empty():
		return "no such gift"
	if showing != "":
		return "already showing"
	if id == "recover_gold" and last_fall_gold < int(g.get("min_gold", 20)):
		return "nothing to get back"
	var cd := float(g.get("cooldown_s", 0))
	if cd > 0.0 and _now() - float(_rec.get("gifts", {}).get(id, 0.0)) < cd:
		return "not yet"
	if backend == "admob" and not (_bridge and _bridge.ready_gift()):
		return "no ad loaded"
	return ""


func gift_ask(id: String) -> String:
	var g := gift(id)
	var a := str(g.get("ask", ""))
	return a % last_fall_gold if a.contains("%d") else a


func watch_gift(id: String, after: Callable = Callable()) -> String:
	## the player said yes: play the ad; the gift comes only if it's watched through
	var why := gift_why_not(id)
	if why != "":
		return why
	_gift_cb = after
	_gift_earned = false
	_begin(id)
	Game.log_event("ad_gift_start", {"gift": id})
	match backend:
		"admob":
			_bridge.show_gift()
		"test":
			if test_answer == "ok":
				earned()
			_end.call_deferred()
	return ""


func earned() -> void:
	## the network says the ad was watched through
	_gift_earned = true


func _give(id: String) -> void:
	var g := gift(id)
	_rec["gifts"][id] = _now()
	_save()
	match id:
		"recover_gold":
			Game.gold += last_fall_gold
			Game.message.emit("Your %d gold is back in the ring." % last_fall_gold)
			last_fall_gold = 0
		"blessing":
			Game.add_buff("deep_blessing", g.get("effect", {}), float(g.get("seconds", 1200)))
			Game.message.emit("The deep's blessing settles on you (%s)." % Game._dur(float(g.get("seconds", 1200))))
	Game.log_event("ad_gift", {"gift": id})
	Game.stats_changed.emit()
	gift_given.emit(id)


# ---- on screen / off ------------------------------------------------------------------------------

func _begin(kind: String) -> void:
	showing = kind
	var tree := get_tree()
	_was_paused = tree.paused if tree else false
	if tree:
		tree.paused = true
	var bus := AudioServer.get_bus_index("Master")
	_was_muted = AudioServer.is_bus_mute(bus)
	AudioServer.set_bus_mute(bus, true)
	started.emit(kind)


func _end() -> void:
	## the ad closed (watched, skipped, or it never came)
	if showing == "":
		return
	var kind := showing
	showing = ""
	var tree := get_tree()
	if tree:
		tree.paused = _was_paused
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), _was_muted)
	if kind != "break":
		if _gift_earned:
			_give(kind)
		else:
			Game.message.emit("No gift this time -- the ad didn't play through.")
		_gift_earned = false
		if _gift_cb.is_valid():
			var cb := _gift_cb
			_gift_cb = Callable()
			cb.call()
	finished.emit(kind)


func ad_closed() -> void:
	## (AdMobBridge) dismissed, or failed to show
	_end()


# ---- privacy ------------------------------------------------------------------------------

func privacy_button() -> bool:
	return backend == "admob" and _bridge != null and _bridge.privacy_required()


func show_privacy() -> void:
	if _bridge:
		_bridge.show_privacy()


# ---- the record on this device -----------------------------------------------------------------

func _record_shown() -> void:
	var shown: Array = _rec.get("shown", [])
	shown.append(_now())
	while shown.size() > 12:
		shown.pop_front()
	_rec["shown"] = shown
	_save()


func _load() -> void:
	if not FileAccess.file_exists(file_path):
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(file_path))
	if d is Dictionary:
		_rec["shown"] = d.get("shown", []) if d.get("shown", []) is Array else []
		_rec["gifts"] = d.get("gifts", {}) if d.get("gifts", {}) is Dictionary else {}


func _save() -> void:
	var f := FileAccess.open(file_path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(_rec))
		f.close()


func reset_record() -> void:
	## (tools) a clean slate
	_rec = {"shown": [], "gifts": {}}
	_session_start = 0.0
	_save()
