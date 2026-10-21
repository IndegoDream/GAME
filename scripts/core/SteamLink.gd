extends Node
## SteamLink: the game on Steam (round 30 -- Robert: "Integrate steam godot
## into the game as well I might end up publishing it").
##
## Uses GodotSteam (addons/godotsteam/, MIT -- the GDExtension build, with
## Valve's steam_api redistributables beside it). Everything here is a
## no-op unless the game is really running under Steam, so the game plays
## exactly the same everywhere else (the box, the phone, the engine checks).
##
## When is Steam on?
##   * an export made with the "steam" feature (the "Windows (Steam)" preset
##     in export_presets.cfg) -- what you'd upload to Steam;
##   * or Menu > Steam: on, for testing on your own PC with Steam running.
## The App ID is the project setting steam/app_id. Until there's a real one
## it's 480 -- Valve's public test app ("Spacewar"), which is what every
## Steamworks developer tests against. Change it in project.godot (or the
## editor's Project Settings) once Steamworks gives you yours.
##
## What it does once on:
##   achievements  every one in data/achievements.json (as UPPER_CASE ids),
##                 plus the round-30 ones (BLOOD_AWAKEN, TRIAL_FIRST ...) --
##                 tools/steam_achievements.gd writes the list to paste
##                 into Steamworks
##   stats         deepest_floor, realm, blood_purity, ascensions
##   leaderboards  "deepest_floor", and one per day for the daily trial
##   rich presence what you're doing, in your friends' list
##   Steam Cloud   your save goes up on every save; on load, the newer of
##                 the two (this PC's, the cloud's) is the one you play

const CLOUD_FILE := "eliet_save.json"
const DEFAULT_APP_ID := 480

var on := false
var app_id := DEFAULT_APP_ID
var status := "off"
var _steam = null                 # the Steam singleton (untyped: the plugin may not be here)
var _boards := {}                 # leaderboard name -> handle
var _pending := {}                # leaderboard name -> score waiting for its handle
var _presence_t := 0.0


static func available() -> bool:
	return Engine.has_singleton("Steam")


static func wanted() -> bool:
	if DisplayServer.get_name() == "headless" or not available():
		return false
	if OS.has_feature("steam"):
		return true
	if OS.get_environment("ELIET_STEAM") == "1":
		return true
	return str(preload("res://scripts/core/Gfx.gd").settings.get("steam", "off")) == "on"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	app_id = int(ProjectSettings.get_setting("steam/app_id", DEFAULT_APP_ID))
	if wanted():
		start()


func start() -> bool:
	if on:
		return true
	if not available():
		status = "the Steam plug-in isn't in this build"
		return false
	_steam = Engine.get_singleton("Steam")
	# a real release started outside Steam relaunches through it (not for the test app)
	if OS.has_feature("steam") and app_id != DEFAULT_APP_ID and _steam.restartAppIfNecessary(app_id):
		get_tree().quit()
		return false
	var r: Dictionary = _steam.steamInitEx(app_id, true)
	if int(r.get("status", 1)) != 0:
		status = "Steam didn't start: %s (is the Steam client running and logged in?)" % str(r.get("verbal", "?"))
		push_warning("SteamLink: " + status)
		_steam = null
		return false
	on = true
	status = "on (app %d, %s)" % [app_id, str(_steam.getPersonaName())]
	if _steam.has_signal("leaderboard_find_result"):
		_steam.leaderboard_find_result.connect(_on_board_found)
	_sync_achievements()
	presence()
	return true


func stop() -> void:
	if on and _steam:
		_steam.clearRichPresence()
		_steam.steamShutdown()
	on = false
	_steam = null
	status = "off"


func _process(delta: float) -> void:
	if not on:
		return
	_presence_t -= delta
	if _presence_t <= 0.0:
		_presence_t = 30.0
		presence()


# ---- achievements and stats ----------------------------------------------------------

func open_store(store_app_id: int) -> bool:
	## round 58: the demo's "get the full game" -- the store page in the overlay
	if not on or _steam == null or store_app_id <= 0 or not _steam.has_method("activateGameOverlayToStore"):
		return false
	_steam.activateGameOverlayToStore(store_app_id, 0)
	return true


func dlc_installed(dlc_app_id: int) -> bool:
	## round 58: an expansion bought on Steam (data/store.json "steam_dlc"; none is made yet)
	if not on or _steam == null or dlc_app_id <= 0:
		return false
	return bool(_steam.isDLCInstalled(dlc_app_id))


func achieve(api_name: String) -> void:
	if not on or _steam == null:
		return
	var a: Dictionary = _steam.getAchievement(api_name)
	if bool(a.get("ret", false)) and bool(a.get("achieved", false)):
		return
	if _steam.setAchievement(api_name):
		_steam.storeStats()


func _sync_achievements() -> void:
	## achievements earned before Steam was on (or on another machine's save)
	for id in Game.achievements:
		achieve(str(id).to_upper())
	if Game.blood_awake():
		achieve("BLOOD_AWAKEN")
	stat("deepest_floor", Game.reach_depth())
	stat("realm", Game.realm)
	stat("ascensions", int(Game.ascension.get("count", 0)))


func stat(stat_name: String, value: int) -> void:
	if on and _steam:
		if _steam.setStatInt(stat_name, value):
			_steam.storeStats()
		if stat_name == "deepest_floor":
			leaderboard("deepest_floor", value)


# ---- leaderboards ------------------------------------------------------------------------

func leaderboard(board: String, score: int) -> void:
	## keeps your best (Steam does the comparing); creates the board if it's new
	if not on or _steam == null:
		return
	if _boards.has(board):
		_steam.uploadLeaderboardScore(score, true, PackedInt32Array(), int(_boards[board]))
		return
	_pending[board] = maxi(score, int(_pending.get(board, score)))
	_steam.findOrCreateLeaderboard(board, 2, 1)      # 2: descending (bigger is better), 1: numeric


func _on_board_found(handle, found) -> void:
	## Steam answers one find at a time, in the order asked
	if int(found) == 0 or _pending.is_empty():
		return
	var board: String = _pending.keys()[0]
	var score := int(_pending[board])
	_pending.erase(board)
	_boards[board] = int(handle)
	_steam.uploadLeaderboardScore(score, true, PackedInt32Array(), int(handle))
	if not _pending.is_empty():
		var nxt: String = _pending.keys()[0]
		_steam.findOrCreateLeaderboard(nxt, 2, 1)


# ---- rich presence -----------------------------------------------------------------------

func presence() -> void:
	if not on or _steam == null:
		return
	var where := "Eliet"
	var lvl := str(Game.current_level)
	if lvl.begins_with("floor"):
		where = "Floor %s" % lvl.substr(5)
	elif Game.in_trial():
		where = "the daily trial"
	elif lvl == "valley":
		where = "the valley"
	var s := "%s -- %s" % [where, Game.cultivation_label()]
	if Game.blood_awake() and Game.blood_dominant() != "":
		s += " (%s blood)" % Game.blood_line(Game.blood_dominant()).get("name", "")
	_steam.setRichPresence("status", s)


# ---- Steam Cloud -----------------------------------------------------------------------------

func cloud_put(text: String, file: String = CLOUD_FILE) -> void:
	if not on or _steam == null or not _steam.isCloudEnabledForAccount() or not _steam.isCloudEnabledForApp():
		return
	var bytes := text.to_utf8_buffer()
	_steam.fileWrite(file, bytes, bytes.size())


func cloud_get(file: String = CLOUD_FILE):
	## the save in Steam Cloud, as a Dictionary (null if none / Steam off)
	if not on or _steam == null or not _steam.fileExists(file):
		return null
	var size: int = _steam.getFileSize(file)
	var r: Dictionary = _steam.fileRead(file, size)
	if not bool(r.get("ret", false)):
		return null
	var buf = r.get("buf", PackedByteArray())
	var d = JSON.parse_string((buf as PackedByteArray).get_string_from_utf8()) if buf is PackedByteArray else null
	return d if d is Dictionary else null


func overlay(page: String = "") -> void:
	if on and _steam:
		_steam.activateGameOverlay(page)
