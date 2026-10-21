extends Node
## Audio -- music, ambience and sounds.
## Round 31 gave the game sound: five ambient loops and Kenney's CC0 effects.
## Round 59 (Robert: "I almost always turn off both the sound effects and music
## because it gets boring") makes it something you'd leave on:
##
##   music     PIECES, not loops (assets/audio/music2/, tools/music_gen2.py):
##             each has an intro, a theme that returns changed, a middle and an
##             ending. Several per place (data/audio.json "sets"): the village by
##             day and by night, the valley, the dungeon, the deep, the abyss, a
##             town underground, the title. One plays, then the place is left to
##             itself for a while (Menu -> Sound: "between pieces" often /
##             sometimes / rarely) before the next -- never the same one twice
##             running. Arriving somewhere new starts that place's music soon.
##             A piece's name shows for a moment in a corner when it starts.
##   ambience  always on, under everything (assets/audio/ambience/): the place's
##             own sound -- a cave's drips and room tone, the town's murmur and
##             hearth, birds by day and crickets by night, the forge-deep's
##             roar, the storm's thunder, the clockwork deep's hum. A reach
##             changes it while you're inside (ReachZone).
##   combat    when foes are on you, drums come up under the fight (and the
##             music steps back); a master's fight has its own. They go a few
##             seconds after the last foe stops chasing. (Menu -> Sound: off.)
##   sounds    Kenney's effects with more takes of the common ones, never quite
##             the same twice (pitch and loudness vary a little).
##   classic   the round-31 loops are kept: Menu -> Sound -> "Music: classic".
## Volumes: music, sounds and ambience, 0-10 each (Gfx.settings).
## The director runs headless too (tests check what it would play); only the
## players are skipped.

const SFX_DIR := "res://assets/audio/sfx/"
const MUSIC_DIR := "res://assets/audio/music/"          # round 31's loops ("classic")
const PIECE_DIR := "res://assets/audio/music2/"
const COMBAT_DIR := "res://assets/audio/combat/"
const AMB_DIR := "res://assets/audio/ambience/"
const DATA := "res://data/audio.json"
const POOL := 12
const FADE := 2.5

signal now_playing(title: String)

static var _streams := {}
var _pool: Array = []
var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _combat: AudioStreamPlayer
var _amb_a: AudioStreamPlayer
var _amb_b: AudioStreamPlayer
var _fade_t := 0.0
var _fade_from: AudioStreamPlayer
var _fade_to: AudioStreamPlayer
var _amb_fade := 0.0
var _amb_from: AudioStreamPlayer
var _amb_to: AudioStreamPlayer
var _step_t := 0.0
var _data := {}

# the director's state (runs headless too)
var context := ""            # which set: "village", "dungeon", "deep" ... or "title"
var piece := ""              # what's playing now ("" in a quiet stretch)
var wait_left := 0.0         # the quiet before the next piece
var last_piece := {}         # set -> the last piece played there (no repeats)
var ambience := ""           # the bed under everything
var amb_override := ""       # a reach's own air while you're in it
var combat_level := 0.0      # 0 calm .. 1 in a fight
var combat_track := ""
var _combat_hold := 0.0
var _combat_poll := 0.0
var _piece_left := 0.0       # (headless: how long the "playing" piece has to go)
var _amb_poll := 0.0


static func on() -> bool:
	return DisplayServer.get_name() != "headless"


func data() -> Dictionary:
	if _data.is_empty():
		var d = JSON.parse_string(FileAccess.get_file_as_string(DATA)) if FileAccess.file_exists(DATA) else null
		_data = d if d is Dictionary else {}
	return _data


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not on():
		return
	for i in POOL:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_pool.append(p)
	_music_a = AudioStreamPlayer.new()
	_music_b = AudioStreamPlayer.new()
	_combat = AudioStreamPlayer.new()
	_amb_a = AudioStreamPlayer.new()
	_amb_b = AudioStreamPlayer.new()
	for m in [_music_a, _music_b, _combat, _amb_a, _amb_b]:
		m.volume_db = -80.0
		add_child(m)
	_amb_to = _amb_a
	apply_volumes()


# ---- settings ----------------------------------------------------------------------

static func _gfx():
	return preload("res://scripts/core/Gfx.gd")


static func music_vol() -> float:
	return clampf(float(_gfx().settings.get("music", 6)) / 10.0, 0.0, 1.0)


static func sfx_vol() -> float:
	return clampf(float(_gfx().settings.get("sfx", 8)) / 10.0, 0.0, 1.0)


static func amb_vol() -> float:
	return clampf(float(_gfx().settings.get("ambience", 7)) / 10.0, 0.0, 1.0)


static func classic() -> bool:
	return str(_gfx().settings.get("music_style", "new")) == "classic"


static func fight_music() -> bool:
	return str(_gfx().settings.get("fight_music", "on")) == "on"


func gap_range() -> Array:
	var g: Dictionary = data().get("gaps", {})
	var r = g.get(str(_gfx().settings.get("music_often", "sometimes")), [60, 150])
	return r if r is Array and r.size() == 2 else [60, 150]


func apply_volumes() -> void:
	if not on():
		return
	if _fade_to and _fade_t <= 0.0:
		_fade_to.volume_db = _db(_music_level())
	if _amb_to and _amb_fade <= 0.0:
		_amb_to.volume_db = _db(_amb_level())


func _music_level() -> float:
	## the exploration music's loudness now: the setting, stepped back under a fight
	var duck := float(data().get("combat", {}).get("duck", 0.25))
	return music_vol() * float(data().get("levels", {}).get("music", 0.8)) * lerpf(1.0, duck, combat_level)


func _amb_level() -> float:
	var duck := float(data().get("combat", {}).get("ambience_duck", 0.6))
	return amb_vol() * float(data().get("levels", {}).get("ambience", 0.75)) * lerpf(1.0, duck, combat_level)


static func _db(v: float) -> float:
	return linear_to_db(maxf(v, 0.0001)) if v > 0.001 else -80.0


static func _stream(path: String) -> AudioStream:
	if not _streams.has(path):
		_streams[path] = load(path) if ResourceLoader.exists(path) else null
	return _streams[path]


static func _pick(name: String) -> AudioStream:
	## "hit_flesh" -> one of hit_flesh1..8.ogg; "parry" -> parry.ogg
	var own := preload("res://scripts/fx/OwnFX.gd").sfx(name)          # r121: the studio's set, if chosen
	if own:
		return own
	var one := _stream(SFX_DIR + name + ".ogg")
	if one:
		return one
	var opts := []
	for i in range(1, 9):
		var s := _stream(SFX_DIR + "%s%d.ogg" % [name, i])
		if s:
			opts.append(s)
	return opts[randi() % opts.size()] if opts.size() > 0 else null


static func has_sound(name: String) -> bool:
	return _pick(name) != null


# ---- sounds ----------------------------------------------------------------------

func play(name: String, vol: float = 1.0, pitch_var: float = 0.08) -> void:
	preload("res://scripts/core/Access.gd").caption(name)          # round 142a: captions for those who cannot hear (before the mute check)
	if not on() or _pool.is_empty():
		return
	var s := _pick(name)
	if s == null:
		return
	for p in _pool:
		var ap := p as AudioStreamPlayer
		if not ap.playing:
			ap.stream = s
			ap.volume_db = _db(sfx_vol() * vol * randf_range(0.85, 1.0))     # never quite the same twice
			ap.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
			ap.play()
			return


func at(name: String, pos: Vector3, vol: float = 1.0, max_dist: float = 22.0) -> void:
	preload("res://scripts/core/Access.gd").caption(name, pos)
	## a sound in the world: quieter with distance from the player
	if not on():
		return
	var pl = get_tree().get_first_node_in_group("player")
	if pl == null:
		play(name, vol)
		return
	var d: float = pl.global_position.distance_to(pos)
	if d > max_dist:
		return
	play(name, vol * clampf(1.0 - d / max_dist, 0.15, 1.0))


func jingle(name: String) -> void:
	play("jingle_" + name, 0.9, 0.0)


func footstep(outdoor: bool, running: bool, delta: float) -> void:
	_step_t -= delta
	if _step_t <= 0.0:
		_step_t = (0.3 if running else 0.46) * randf_range(0.94, 1.06)
		play("step_grass" if outdoor else "step_stone", (0.3 if not running else 0.4) * float(data().get("levels", {}).get("steps", 1.0)), 0.15)


# ---- music: which set a place has ----------------------------------------------------

func music_for(level_id: String, def: Dictionary) -> String:
	if level_id == "title":
		return "title"
	if level_id == "valley" or Game.TowerGen.is_tower(level_id):
		return "valley"
	var night: bool = Game.daylight() < 0.35
	if level_id == "village":
		return "village_night" if night else "village"
	var depth := int(def.get("depth", 0))
	if level_id.begins_with("floor") and depth == 0:
		depth = int(level_id.trim_prefix("floor").get_slice(":", 0))
	if str(def.get("theme", "")) in ["village", "settlement"] or bool(def.get("town", false)):
		return "haven" if depth > 0 else ("village_night" if night else "village")
	if depth >= 30:
		return "abyss"
	if depth >= 10:
		return "deep"
	return "dungeon"


func set_music(name: String) -> void:
	## (the old name) -- the place says which set it is; the director does the rest
	set_context(name)


func set_context(name: String) -> void:
	if name == context:
		return
	context = name
	if classic():
		_classic_play(name)
		return
	# a new place: its own music soon (a breath first, unless it's the title)
	var fd = data().get("first_delay", [2.0, 6.0])
	_end_piece(2.5)
	wait_left = 0.4 if name == "title" else randf_range(float(fd[0]), float(fd[1]))


func pieces_of(set_name: String) -> Array:
	var sets: Dictionary = data().get("sets", {})
	var arr = sets.get(set_name, sets.get(_fallback_set(set_name), []))
	return arr if arr is Array else []


func _fallback_set(set_name: String) -> String:
	return {"village_night": "village", "haven": "village", "abyss": "deep"}.get(set_name, "dungeon")


func next_piece() -> String:
	## a piece from this place's set, never the one just heard
	var opts := pieces_of(context).duplicate()
	if opts.is_empty():
		return ""
	if opts.size() > 1:
		opts.erase(str(last_piece.get(context, "")))
	return str(opts[randi() % opts.size()])


func title_of(p: String) -> String:
	var dev: Dictionary = Game.draft_texts("music_titles")
	if dev.has(p):
		return str(dev[p]).trim_prefix("\"").trim_suffix("\"")      # Dev's name for it (the writing room)
	return str(data().get("titles", {}).get(p, ""))


func start_piece(p: String) -> void:
	if p == "":
		return
	piece = p
	last_piece[context] = p
	var s := _stream(PIECE_DIR + p + ".ogg")
	_piece_left = s.get_length() if s else 150.0
	if on() and s:
		if s is AudioStreamOggVorbis:
			(s as AudioStreamOggVorbis).loop = false
		var nxt := _music_b if _fade_to == _music_a else _music_a
		nxt.stream = s
		nxt.volume_db = -80.0
		nxt.play()
		_fade_from = _fade_to if _fade_to != nxt else null
		_fade_to = nxt
		_fade_t = FADE
	var t := title_of(p)
	if t != "" and music_vol() > 0.0:
		now_playing.emit(t)


func _end_piece(fade: float) -> void:
	piece = ""
	_piece_left = 0.0
	if on() and _fade_to and _fade_to.playing:
		_fade_from = _fade_to
		_fade_to = null
		_fade_t = fade


func _piece_done() -> void:
	## it ended on its own: a quiet stretch, then the next
	piece = ""
	var r := gap_range()
	wait_left = randf_range(float(r[0]), float(r[1]))


func _classic_play(name: String) -> void:
	piece = name
	if not on():
		return
	var s := _stream(MUSIC_DIR + {"village_night": "village", "haven": "village", "abyss": "deep"}.get(name, name) + ".ogg")
	if s == null:
		return
	if s is AudioStreamOggVorbis:
		(s as AudioStreamOggVorbis).loop = true
	var nxt := _music_b if _fade_to == _music_a else _music_a
	nxt.stream = s
	nxt.volume_db = -80.0
	nxt.play(randf() * 20.0)
	_fade_from = _fade_to
	_fade_to = nxt
	_fade_t = FADE


func restart_music() -> void:
	## (the settings changed: style) -- start this place over
	var c := context
	context = ""
	_end_piece(1.0)
	set_context(c)


# ---- ambience --------------------------------------------------------------------------

func ambience_for(level) -> String:
	if level == null:
		return ""
	var a: Dictionary = data().get("ambience", {})
	var lid := str(level.level_id)
	var day: bool = Game.daylight() >= 0.35
	if lid == "village":
		return "village_day" if day else "village_night"
	if lid == "valley" or Game.TowerGen.is_tower(lid):
		return "valley_day" if day else "valley_night"
	if level.has_method("is_town") and level.is_town():
		return "town"
	var lk := str(level.get("look_key")) if level.get("look_key") != null else ""
	var by_look: Dictionary = a.get("look", {})
	if by_look.has(lk):
		return str(by_look[lk])
	var depth := int(level.def.get("depth", 0)) if level.get("def") is Dictionary else 0
	return "deep" if depth >= 10 else "cave"


func ambience_for_look(look: String) -> String:
	return str(data().get("ambience", {}).get("look", {}).get(look, ""))


func set_ambience(name: String) -> void:
	if name == ambience:
		return
	ambience = name
	if not on():
		return
	var s: AudioStream = _stream(AMB_DIR + name + ".ogg") if name != "" else null
	var nxt := _amb_b if _amb_to == _amb_a else _amb_a
	if s:
		if s is AudioStreamOggVorbis:
			(s as AudioStreamOggVorbis).loop = true
		nxt.stream = s
		nxt.volume_db = -80.0
		nxt.play(randf() * 30.0)
	else:
		nxt.stop()
	_amb_from = _amb_to
	_amb_to = nxt
	_amb_fade = 3.0


func set_reach_look(look: String) -> void:
	## ReachZone: in a reach, that land's own air; "" when you leave
	amb_override = ambience_for_look(look) if look != "" else ""
	_amb_poll = 0.0


# ---- combat -------------------------------------------------------------------------------

func fight_now() -> Dictionary:
	## {"on": foes on you?, "boss": a master among them?}
	var tree := get_tree()
	var pl = tree.get_first_node_in_group("player") if tree else null
	if pl == null:
		return {"on": false, "boss": false}
	var r := float(data().get("combat", {}).get("radius", 22.0))
	var on_me := false
	var boss := false
	for e in tree.get_nodes_in_group("enemy"):
		if not (e is Node3D) or not e.is_inside_tree() or e.get("_dead") == true or e.get("_chasing") != true:
			continue
		if (e as Node3D).global_position.distance_to(pl.global_position) > r:
			continue
		on_me = true
		var st = e.get("stats")
		if st is Dictionary and bool(st.get("boss", false)):
			boss = true
	return {"on": on_me, "boss": boss}


func combat_for(boss: bool) -> String:
	var c: Dictionary = data().get("combat", {})
	var key := "boss" if boss else ("deep" if context in ["deep", "abyss"] else "dungeon")
	var arr = c.get(key, [])
	if not (arr is Array) or arr.is_empty():
		return ""
	if combat_track in arr:
		return combat_track                    # (keep the one already going)
	return str(arr[randi() % arr.size()])


func _set_combat_track(name: String) -> void:
	combat_track = name
	if not on() or name == "":
		return
	var s := _stream(COMBAT_DIR + name + ".ogg")
	if s == null:
		return
	if s is AudioStreamOggVorbis:
		(s as AudioStreamOggVorbis).loop = true
	if _combat.stream != s:
		_combat.stream = s
		_combat.play()


# ---- the tick ------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_tick_combat(delta)
	_tick_director(delta)
	_tick_ambience(delta)
	if not on():
		return
	# cross-fades
	if _fade_t > 0.0:
		_fade_t = maxf(_fade_t - delta, 0.0)
		var k := 1.0 - _fade_t / FADE
		if _fade_to:
			_fade_to.volume_db = _db(_music_level() * k)
		if _fade_from:
			_fade_from.volume_db = _db(_music_level() * (1.0 - k))
			if _fade_t <= 0.0:
				_fade_from.stop()
				_fade_from = null
	elif _fade_to:
		_fade_to.volume_db = _db(_music_level())
	if _amb_fade > 0.0:
		_amb_fade = maxf(_amb_fade - delta, 0.0)
		var k2 := 1.0 - _amb_fade / 3.0
		if _amb_to:
			_amb_to.volume_db = _db(_amb_level() * k2)
		if _amb_from:
			_amb_from.volume_db = _db(_amb_level() * (1.0 - k2))
			if _amb_fade <= 0.0:
				_amb_from.stop()
	elif _amb_to:
		_amb_to.volume_db = _db(_amb_level())
	if _combat:
		var cv := music_vol() * float(data().get("levels", {}).get("combat", 0.9)) * combat_level
		_combat.volume_db = _db(cv)
		if combat_level <= 0.001 and _combat.playing:
			_combat.stop()
			_combat.stream = null


func _tick_director(delta: float) -> void:
	if classic() or context == "":
		return
	if piece != "":
		var ended := false
		if on():
			ended = _fade_to == null or (not _fade_to.playing and _fade_t <= 0.0)
		else:
			_piece_left -= delta
			ended = _piece_left <= 0.0
		if ended:
			_piece_done()
		return
	if music_vol() <= 0.0:
		return
	wait_left -= delta
	if wait_left <= 0.0:
		start_piece(next_piece())


func _tick_combat(delta: float) -> void:
	var c: Dictionary = data().get("combat", {})
	_combat_poll -= delta
	if _combat_poll <= 0.0:
		_combat_poll = 0.3
		var f := fight_now() if fight_music() and not classic() else {"on": false, "boss": false}
		if f["on"]:
			_combat_hold = float(c.get("hold", 5.0))
			var tr := combat_for(bool(f["boss"]))
			if tr != combat_track:
				_set_combat_track(tr)
		else:
			_combat_hold = maxf(_combat_hold - 0.3, 0.0)
	var target := 1.0 if _combat_hold > 0.0 and combat_track != "" else 0.0
	var rate := 1.0 / float(c.get("fade_in", 1.2)) if target > combat_level else 1.0 / float(c.get("fade_out", 3.5))
	combat_level = move_toward(combat_level, target, delta * rate)
	if combat_level <= 0.0 and target == 0.0:
		combat_track = ""


func _tick_ambience(delta: float) -> void:
	_amb_poll -= delta
	if _amb_poll > 0.0:
		return
	_amb_poll = 2.0
	var tree := get_tree()
	var lv = tree.get_first_node_in_group("level") if tree else null
	if context == "title":
		set_ambience("")
		return
	set_ambience(amb_override if amb_override != "" else ambience_for(lv))
