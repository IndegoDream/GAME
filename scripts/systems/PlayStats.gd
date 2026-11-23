extends "res://scripts/systems/GameSystem.gd"
## Round 182: opt-in, anonymous play stats, so balance can be checked against real players instead of only the
## floor model (tools/balance_report.gd). Robert, 2026-11-06: "maximize potential of earnings, game mechanic and balance".
##
##   OFF until the player says yes. Asked once (a short window at a town, after about twenty minutes of play), and
##   switchable any time in the menu: Settings > "Share anonymous play stats". Saying no records nothing at all.
##   What a row holds: the day, minutes played, what happened (a fall, a floor reached, a boss beaten, a realm crossed,
##   a sitting begun or ended), the floor depth and level id, the realm step, the build, the platform and the tier
##   (free / full / demo). Never a name, an email, chat, text you typed or anything about the device beyond its
##   platform. The install id is random, made on this device, and can be reset (Settings).
##   Rows wait in user://playstats.jsonl. If the cloud is set up (data/cloud.json url + anon_key) they go up in small
##   batches to the play_stats table (supabase/migrations/20261106000004_play_stats.sql: insert-only, nobody but the
##   owner's service key can read it). With no cloud they stay on the device; a tester can send the file by hand.
##   tools/stats_report.py reads either: deaths, quits and boss attempts per floor.

const MAX_BYTES := 393216              # ~3000 rows: the oldest go first beyond this
const UPLOAD_EVERY_S := 600.0
const BATCH := 200
const ASK_AFTER_S := 1200.0            # twenty minutes in, at a town
const KINDS := ["death", "enter_level", "boss_kill", "breakthrough", "levelup", "floor_cleared", "tribulation_lost",
	"tribulation_start", "trial_start", "session_start", "session_end", "first_hour"]
const KEEP := ["cause", "type", "realm", "step", "level", "floor", "fresh", "sm"]     # the only data keys a row may carry

var file_path := "user://playstats.jsonl"
var cfg_path := "user://playstats_cfg.json"          # (tools point both elsewhere)
var cfg := {"consent": "", "install": "", "sent": 0, "asked": false}
var _up_t := 0.0
var _sess_start := 0.0
var _uploading := false
var _asked_this_run := false


func setup(game) -> void:
	super.setup(game)
	_load_cfg()


func consent() -> bool:
	return str(cfg.get("consent", "")) == "yes"


func asked() -> bool:
	return str(cfg.get("consent", "")) != "" or bool(cfg.get("asked", false))


func set_consent(yes: bool) -> void:
	cfg["consent"] = "yes" if yes else "no"
	cfg["asked"] = true
	if yes and str(cfg.get("install", "")) == "":
		cfg["install"] = _new_id()
	if not yes:
		_wipe_rows()                       # no means no: what was waiting is gone too
	_save_cfg()
	if yes:
		_sess_start = _now()
		record("session_start", {})


func reset_id() -> void:
	## Settings: a fresh random id, and nothing unsent kept under the old one
	cfg["install"] = _new_id() if consent() else ""
	_wipe_rows()
	_save_cfg()


# ---- recording ---------------------------------------------------------------------------------------------------

func on_event(kind: String, data: Dictionary) -> void:
	if kind == "enter_level":
		_maybe_ask(data)
		begin_session()
	if not consent() or not (kind in KINDS):
		return
	var d := {}
	match kind:
		"death":
			d["cause"] = _short(str(data.get("cause", "")))
		"boss_kill":
			d["type"] = _short(str(data.get("type", "")))
		"enter_level":
			var pl = G.journal.get("places", {}).get(str(data.get("id", G.current_level)), {}) if G else {}
			d["fresh"] = pl is Dictionary and int(pl.get("visits", 0)) <= 1
	record(kind, d)


func record(kind: String, extra: Dictionary) -> void:
	if not consent():
		return
	var row := {
		"d": Time.get_date_string_from_system(true),
		"m": int(float(G.playtime) / 60.0) if G else 0,
		"k": kind,
		"lvl": _short(str(G.current_level)) if G else "",
		"f": int(G.depth) if G else 0,
		"s": int(G.step_index()) if G else 0,
		"b": _build(),
		"p": OS.get_name().to_lower(),
		"t": _tier(),
	}
	for k in extra:
		if str(k) in KEEP:
			row[str(k)] = extra[k]
	_append(row)


func _append(row: Dictionary) -> void:
	if FileAccess.file_exists(file_path):
		var f0 := FileAccess.open(file_path, FileAccess.READ)
		if f0 and f0.get_length() > MAX_BYTES:
			f0.close()
			_trim()
	var f := FileAccess.open(file_path, FileAccess.READ_WRITE if FileAccess.file_exists(file_path) else FileAccess.WRITE)
	if f:
		f.seek_end()
		f.store_line(JSON.stringify(row))
		f.close()


func rows() -> Array:
	var out := []
	if not FileAccess.file_exists(file_path):
		return out
	for ln in FileAccess.get_file_as_string(file_path).split("\n", false):
		var r = JSON.parse_string(ln)
		if r is Dictionary:
			out.append(r)
	return out


func _trim() -> void:
	## keep the newest half; anything already sent is the first to go
	var all := rows()
	var sent := int(cfg.get("sent", 0))
	var keep: Array = all.slice(maxi(sent, all.size() / 2))
	var f := FileAccess.open(file_path, FileAccess.WRITE)
	if f:
		for r in keep:
			f.store_line(JSON.stringify(r))
		f.close()
	cfg["sent"] = 0
	_save_cfg()


func _wipe_rows() -> void:
	if FileAccess.file_exists(file_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(file_path))
	cfg["sent"] = 0


# ---- sending -------------------------------------------------------------------------------------------------------

func tick(delta: float) -> void:
	if not consent():
		return
	_up_t += delta
	if _up_t >= UPLOAD_EVERY_S:
		_up_t = 0.0
		upload()


func can_send() -> bool:
	return consent() and G != null and G.cloudsave != null and G.cloudsave.configured()


func pending() -> int:
	return maxi(0, rows().size() - int(cfg.get("sent", 0)))


func upload() -> Dictionary:
	## one batch of unsent rows to the play_stats table; {"ok", "sent", "error"}
	if not can_send():
		return {"ok": false, "sent": 0, "error": "off"}
	if _uploading:
		return {"ok": false, "sent": 0, "error": "busy"}
	var all := rows()
	var from := clampi(int(cfg.get("sent", 0)), 0, all.size())
	var batch: Array = all.slice(from, mini(all.size(), from + BATCH))
	if batch.is_empty():
		return {"ok": true, "sent": 0, "error": ""}
	var body := []
	for r in batch:
		body.append({"game": str(G.cloudsave.game), "install": str(cfg.get("install", "")), "data": r})
	_uploading = true
	var res: Dictionary = await G.cloudsave._call(HTTPClient.METHOD_POST, "/rest/v1/play_stats", body,
		PackedStringArray(["Prefer: return=minimal"]), false)
	_uploading = false
	if bool(res.get("ok", false)):
		cfg["sent"] = from + batch.size()
		_save_cfg()
		return {"ok": true, "sent": batch.size(), "error": ""}
	return {"ok": false, "sent": 0, "error": str(res.get("error", ""))}


func end_session() -> void:
	## the window closes, the phone puts the game away, or Quit in the menu
	if consent() and _sess_start > 0.0:
		record("session_end", {"sm": int((_now() - _sess_start) / 60.0)})
		_sess_start = 0.0


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
		end_session()
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		if consent() and _sess_start <= 0.0:
			_sess_start = _now()
			record("session_start", {})


func begin_session() -> void:
	## Game, once a save is loaded or a new game starts
	if consent() and _sess_start <= 0.0:
		_sess_start = _now()
		record("session_start", {})


# ---- asking once ---------------------------------------------------------------------------------------------------

func _maybe_ask(_data: Dictionary) -> void:
	if asked() or _asked_this_run or G == null or float(G.playtime) < ASK_AFTER_S:
		return
	if G.store != null and G.store.backend == "test" and OS.get_environment("ELIET_ASK_STATS") == "":
		return                                    # (the tools don't get asked unless they ask to be)
	if not (str(G.current_level) == "village" or G.havens.has(str(G.current_level))):
		return                                    # only in a town: never on a floor
	var hud = G.get_tree().get_first_node_in_group("hud") if G.is_inside_tree() else null
	if hud == null or not hud.has_method("queue_moment"):
		return
	_asked_this_run = true
	hud.queue_moment("__ask_stats", "")


func ask(hud) -> void:
	hud.open_dialog(I18n.t("Help balance the game?"),
		I18n.t("May the game keep anonymous play stats -- where people fall, which floors take longest, when a sitting ends -- so the difficulty can be tuned for everyone?\n\nNo name, no email, no chat, nothing you type. A random id made on this device. You can turn it off or reset it any time in Settings."),
		[["Yes, share them", func():
			set_consent(true)
			hud.close_dialog()
			G.message.emit(I18n.t("Thank you. Play stats are on (Settings to change)."))],
		["No thanks", func():
			set_consent(false)
			hud.close_dialog()]])


func settings_label() -> String:
	return I18n.t("Share anonymous play stats: %s") % (I18n.t("on") if consent() else I18n.t("off"))


func toggle() -> void:
	set_consent(not consent())


# ---- bits ------------------------------------------------------------------------------------------------------------

func _tier() -> String:
	if G == null or G.store == null:
		return ""
	if G.store.demo():
		return "demo"
	return "full" if G.store.full_game() else "free"


func _build() -> int:
	if G != null and G.get("online") != null and G.online.has_method("build_number"):
		return int(G.online.build_number())
	var d = JSON.parse_string(FileAccess.get_file_as_string("res://data/build_info.json")) if FileAccess.file_exists("res://data/build_info.json") else null
	return int(d.get("build", 0)) if d is Dictionary else 0


static func _short(s: String) -> String:
	## ids only: letters, digits, _ : - . (anything else -- a typed name, a sentence -- is dropped)
	var out := ""
	for ch in s.substr(0, 48):
		if (ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z") or (ch >= "0" and ch <= "9") or ch in ["_", ":", "-", "."]:
			out += ch
		elif ch == " ":
			return ""                             # a sentence, not an id
	return out


func _new_id() -> String:
	var c := Crypto.new()
	return c.generate_random_bytes(12).hex_encode()


func _now() -> float:
	return Time.get_unix_time_from_system()


func _load_cfg() -> void:
	if not FileAccess.file_exists(cfg_path):
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(cfg_path))
	if d is Dictionary:
		for k in cfg:
			if d.has(k):
				cfg[k] = d[k]
		var inst := str(cfg.get("install", ""))
		if inst.length() < 16 or inst.length() > 32 or not inst.is_valid_hex_number():
			cfg["install"] = _new_id() if consent() else ""


func _save_cfg() -> void:
	var f := FileAccess.open(cfg_path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(cfg))
		f.close()
