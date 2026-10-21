extends Node3D
## Main -- starts the game: loads your save (or a new game), builds the
## level you were on, puts the player in it, and swaps levels when you
## take the stairs. The world itself is built by scripts/Level.gd from
## the level files in res://levels/ -- see DEV_GUIDE.md.

const LevelScript := preload("res://scripts/world/Level.gd")
const PlayerScript := preload("res://scripts/actors/Player.gd")
const HUDScript := preload("res://scripts/ui/HUD.gd")
const FamiliarScript := preload("res://scripts/actors/Familiar.gd")
const OnlineGen := preload("res://scripts/world/OnlineGen.gd")
const CompanionScript := preload("res://scripts/actors/Companion.gd")

var level: Node3D
var player: CharacterBody3D
var hud: CanvasLayer
var familiar: Node3D
var companion: Node3D


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_INHERIT
	preload("res://scripts/core/Gfx.gd").load_settings()        # graphics preset, window, camera (user://settings.json)
	preload("res://scripts/core/Gfx.gd").apply(get_tree())
	if preload("res://scripts/core/Gfx.gd").small_device():
		preload("res://scripts/ui/TouchUI.gd").fit_screen(get_tree())     # big enough to read on a phone (round 29)
	# round 51: three games, each its own character -- open the last one played
	# (a save from before slots becomes slot 1; the old file stays as it was)
	var ml = get_node_or_null("/root/MemLog")
	if ml != null:
		ml.crumb("main ready")
	if DisplayServer.get_name() != "headless" and not (ml != null and ml.safe_start):
		_warm = preload("res://scripts/core/Warm.gd").new()
		_warm.start(not preload("res://scripts/core/Gfx.gd").small_device())
	I18n.init()                                                  # round 140: the saved language (or the device's), before any menu draws
	Game.migrate_to_slots()
	Game.use_slot(Game.last_slot())
	if not Game.load_game():
		Game.new_game()
		Game.message.emit.call_deferred("Welcome to Eliet. Talk to Elder Mo by the fountain.")
	if ml != null:
		ml.crumb("save loaded; making HUD")
	hud = HUDScript.new()
	hud.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(hud)
	if ml != null:
		ml.crumb("HUD up; loading level " + str(Game.current_level))
	Game.level_change_requested.connect(_on_level_change)
	_load_level(Game.current_level, Game.spawn_tag)
	if ml != null:
		ml.crumb("level loaded")
	preload("res://scripts/ui/TouchUI.gd").sync(get_tree())            # thumbs, on a touch screen (round 29)
	if not preload("res://scripts/ui/TouchUI.gd").wanted() and not OS.has_feature("web"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED                # (a browser only lets go of the mouse on a click)
	if not Game.away_report.is_empty() and not Game.needs_background():
		hud.show_away_report.call_deferred()        # what happened while you were away
	if not OS.has_feature("headless") and DisplayServer.get_name() != "headless":
		hud.show_title.call_deferred()              # round 31: the front door


var _world_frozen: bool = false


var _warm = null          # round 158: reads the levels' models on background threads (Warm.gd)


var _crumb_t := 0.0
var _crumb_n := 0


func _process(delta: float) -> void:
	_crumb_t += delta
	if _crumb_t >= 0.5 and _crumb_n < 80:          # round 169: the first 40 s leave a trail
		_crumb_t = 0.0
		_crumb_n += 1
		var ml = get_node_or_null("/root/MemLog")
		if ml != null:
			var pp := Vector3.ZERO
			if player != null:
				pp = player.global_position
			ml.crumb("fps=%d nodes=%d lvl=%s pos=%s warm=%s stream=%s" % [int(Performance.get_monitor(Performance.TIME_FPS)), int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)), str(level.level_id) if level != null else "-", str(pp.snapped(Vector3.ONE * 0.1)), str(_warm.pending()) if _warm != null else "off", str(level.stream_left()) if level != null and level.has_method("stream_left") else "-"])
	if _warm != null:
		_warm.tick()
		if _warm.pending() == 0:
			_warm = null
	## the world holds still while you plan in the menus (the player keeps
	## running so meditation goes on; input is already ignored by the player)
	var want: bool = hud != null and hud.menu_pages_open() and level != null \
		and not OnlineGen.is_online(str(level.level_id))
	if want or want != _world_frozen:
		set_world_frozen(want)      # (while held: also catches a freshly loaded level)


func set_world_frozen(on: bool) -> void:
	_world_frozen = on
	Game.world_frozen = on
	for c in get_children():
		if c == hud or c == player:
			continue
		if on:
			if c.process_mode == Node.PROCESS_MODE_INHERIT:
				c.process_mode = Node.PROCESS_MODE_DISABLED
				c.set_meta("menu_frozen", true)
		elif c.has_meta("menu_frozen"):
			c.process_mode = Node.PROCESS_MODE_INHERIT
			c.remove_meta("menu_frozen")


var _loading_screen = null
static var force_veil := false          # (tests turn it on to run the loading-screen path headless)
var _changing := false
var _queued: Array = []


func _on_level_change(level_id: String, arrive_at: String) -> void:
	## round 158: in play, a change of place is covered by a loading screen with a tip, drawn BEFORE the build starts
	if DisplayServer.get_name() == "headless" and not force_veil:
		_load_level(level_id, arrive_at)
		return
	if _changing:
		_queued = [level_id, arrive_at]          # (asked again mid-load: do it right after, never drop it)
		return
	_changing = true
	if _loading_screen == null:
		_loading_screen = preload("res://scripts/ui/Loading.gd").new()
		add_child(_loading_screen)
	var def := Game.load_level_def(level_id)
	_loading_screen.show_for(str(def.get("name", "")) if not def.is_empty() else "")
	await get_tree().process_frame
	await get_tree().process_frame
	_load_level(level_id, arrive_at)
	await get_tree().process_frame
	await get_tree().process_frame
	_changing = false
	if not _queued.is_empty():
		var q: Array = _queued
		_queued = []
		_on_level_change(str(q[0]), str(q[1]))
		return
	_loading_screen.fade_out()


func _load_level(level_id: String, arrive_at: String) -> void:
	var from_id: String = str(level.level_id) if level else ""      # round 58: (was this a step down?)
	if level:
		remove_child(level)
		level.free()
	var def := Game.load_level_def(level_id)
	if def.is_empty() and level_id != "village":
		Game.message.emit("Couldn't load '%s' -- back to the village." % level_id)
		level_id = "village"
		arrive_at = "P"
		def = Game.load_level_def(level_id)
	LevelScript.stream_on = DisplayServer.get_name() != "headless"      # round 158: dress the place nearest-first, not all before you move
	level = LevelScript.new()
	level.name = "Level"
	level.build(def)
	add_child(level)
	for w in level.warnings:
		push_warning("[%s] %s" % [level_id, w])
	if player == null:
		player = PlayerScript.new()
		player.name = "Player"
		add_child(player)
	player.global_position = level.spawn_point(arrive_at)
	player.velocity = Vector3.ZERO
	if familiar == null:
		familiar = FamiliarScript.new()
		familiar.name = "Familiar"
		add_child(familiar)
		for i in [1, 2]:                       # round 39: the other contract beasts you've called
			var f2 = FamiliarScript.new()
			f2.slot = i
			f2.name = "Familiar%d" % (i + 1)
			add_child(f2)
	for f3 in get_tree().get_nodes_in_group("familiar_node"):
		f3.snap_to(player.global_position)
	familiar.snap_to(player.global_position)
	if companion == null:
		companion = CompanionScript.new()
		companion.name = "Companion"
		add_child(companion)
		var c2 = CompanionScript.new()         # round 39: the second of a party of two
		c2.slot = 1
		c2.name = "Companion2"
		add_child(c2)
	for c3 in get_tree().get_nodes_in_group("companion_node"):
		c3.snap_to(player.global_position)
	Game.current_level = level_id
	Game.mark_level_entered(level_id, {"enemies": int(level.counts.get("enemies", 0)), "chests": int(level.counts.get("chests", 0)), "secrets": int(level.counts.get("secrets", 0)), "lore": int(level.counts.get("lore", 0))})
	if level.is_town():
		Game.enter_haven(level_id, str(level.def.get("name", level_id)))
	hud.set_level_name(level.display_name())
	var woke := Game.take_after_load_note()          # round 58: moved up out of the full game's floors
	if woke != "":
		Game.message.emit(woke)
	_after_arrival(from_id, level_id)
	Game.stats_changed.emit()
	if Game.needs_background() and not Game.arena_active() and DisplayServer.get_name() == "headless":
		hud.start_creation.call_deferred()     # who were you? (asked until answered; the title asks it otherwise)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		Game.save_game()
	elif what == NOTIFICATION_APPLICATION_PAUSED or (what == NOTIFICATION_APPLICATION_FOCUS_OUT and OS.has_feature("mobile")):
		# round 56: a phone can close a game in the background without asking -- save first
		if not Game.needs_background():
			Game.save_game()
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST:
		# round 56: Android's back button does what Escape does (close what's open, else the pause menu)
		var ev := InputEventAction.new()
		ev.action = "pause"
		ev.pressed = true
		Input.parse_input_event(ev)


func _after_arrival(from_id: String, level_id: String) -> void:
	## round 58, the free tier on phones: a gift offer after a fall, or maybe a
	## short ad break on the way down / reaching a town (Ads.on_arrival decides)
	if Game.ads:
		Game.ads.on_arrival(from_id, level_id, level.is_town(), hud)
