extends Node
## WorldSound -- round 184 (Robert: "keep working on making the details of the game better, more immersive").
## The small sounds that make a place feel alive, on top of Audio.gd's bed and music:
##
##   spots    one-off sounds put somewhere around you: a songbird up in a tree to your left, a dove in
##            the morning, an owl at night, frogs in the warm seasons, the porch chimes, the smith's hammer
##            across the square in working hours, a woodcutter, the temple bell now and then; down below,
##            a drop landing in the dark, stones settling, the deep's rumble, air moaning through a crypt,
##            water lapping, crystals humming, the forge popping, gears catching. Which ones, how often,
##            how far and how high: data/audio.json "spots" (by the place's bed) and "weather_spots".
##            Birds keep quiet in the rain; a storm brings far thunder; a tremor brings the rumble closer.
##            They hush while you fight.
##   weather  rain you can hear when it rains (light, or heavy in a storm), wind when it snows or the fog
##            is in -- under the sky only ("weather_beds").
##   echo     the world's sounds (blows, steps, spots -- not the menus) go through a "World" bus with a
##            reverb sized to the place: dry in the open, a little in the village, long in the deep and the
##            crypts and the flooded halls ("rooms").
##   ground   what your feet say: snow, water, sand, metal, wood, grass or stone ("ground"), and in the rain
##            a splash under the grass.
## Settings (Sound): "world_sounds" on/off (spots and weather), "room_echo" on/off.
## The choosing runs headless too (tests read spot_log); only the players are skipped.

const SPOT_POLL := 0.5
const LOG_MAX := 30

var audio: Node                      # Audio.gd
var bed := ""                        # the place's bed these spots belong to
var weather := ""                    # the weather (surface) or current (deep) here now
var outdoor := false
var day := true
var season := ""
var ground_kind := "stone"
var room := "open"
var weather_bed := ""
var spot_log: Array = []             # [time, name] -- what the director chose (tests)
var spot_count := {}                 # name -> how many times (tests)
var _timers := {}                    # entry key -> seconds to its next sounding
var _rng := RandomNumberGenerator.new()
var _poll := 0.0
var _place_poll := 0.0
var _clock := 0.0
var _bus := -1
var _verb: AudioEffectReverb
var _wet_now := 0.0
var _p3: Array = []                  # AudioStreamPlayer3D pool (world-placed sounds)
var _wx_a: AudioStreamPlayer
var _wx_b: AudioStreamPlayer
var _wx_to: AudioStreamPlayer
var _wx_from: AudioStreamPlayer
var _wx_fade := 0.0
var _wx_gain := 1.0
var _thunder_in := -1.0              # round 184b: seconds until the thunder of the last flash
var _thunder_at := Vector3.ZERO


static func _gfx():
	return preload("res://scripts/core/Gfx.gd")


static func world_on() -> bool:
	return str(_gfx().settings.get("world_sounds", "on")) == "on"


static func echo_on() -> bool:
	return str(_gfx().settings.get("room_echo", "on")) == "on"


func setup(a: Node) -> void:
	audio = a
	_rng.randomize()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if audio == null or not audio.on():
		return
	_bus = AudioServer.get_bus_index("World")
	if _bus < 0:
		AudioServer.add_bus()
		_bus = AudioServer.bus_count - 1
		AudioServer.set_bus_name(_bus, "World")
		AudioServer.set_bus_send(_bus, "Master")
		_verb = AudioEffectReverb.new()
		_verb.room_size = 0.15
		_verb.damping = 0.55
		_verb.spread = 0.9
		_verb.hipass = 0.12
		_verb.predelay_msec = 22.0
		_verb.predelay_feedback = 0.3
		_verb.dry = 1.0
		_verb.wet = 0.0
		AudioServer.add_bus_effect(_bus, _verb)
	else:
		_verb = AudioServer.get_bus_effect(_bus, 0) as AudioEffectReverb
	for i in 10:
		var p := AudioStreamPlayer3D.new()
		p.bus = "World"
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p.unit_size = 5.0
		p.max_db = 3.0
		p.panning_strength = 1.0
		p.attenuation_filter_cutoff_hz = 6000.0
		p.attenuation_filter_db = -18.0
		add_child(p)
		_p3.append(p)
	_wx_a = AudioStreamPlayer.new()
	_wx_b = AudioStreamPlayer.new()
	for w in [_wx_a, _wx_b]:
		w.volume_db = -80.0
		add_child(w)
	_wx_to = _wx_a


func bus_name() -> String:
	return "World" if _bus >= 0 else "Master"


# ---- what a place is -------------------------------------------------------------------------------

static func level_outdoor(level) -> bool:
	return level != null and level.has_method("is_outdoor") and level.is_outdoor()


static func ground_for(level, data: Dictionary, wx: String) -> String:
	## the floor under your feet
	if level == null:
		return "stone"
	var g: Dictionary = data.get("ground", {})
	var lk := str(level.get("look_key")) if level.get("look_key") != null else ""
	var by_look: Dictionary = g.get("look", {})
	var th := str(level.get("theme")) if level.get("theme") != null else ""
	var out := level_outdoor(level)
	if out and wx == "snow":
		return "snow"
	if by_look.has(lk):
		return str(by_look[lk])
	var by_theme: Dictionary = g.get("theme", {})
	if by_theme.has(th):
		return str(by_theme[th])
	return "grass" if out else "stone"


static func weather_bed_for(data: Dictionary, wx: String, out: bool, region: String) -> Array:
	## [file, loudness] of the weather layer, or [] -- rain under the sky; a cold seep in the deep
	var wb: Dictionary = data.get("weather_beds", {})
	if wx == "" or not wb.has(wx) or wx.begins_with("_"):
		return []
	var deep_ok := wx == "cold_seep"
	if not ((out and region == "surface") or (deep_ok and region.begins_with("deep:"))):
		return []
	var e = wb[wx]
	return e if e is Array and e.size() == 2 else []


static func room_for(data: Dictionary, bed_name: String, out: bool) -> Array:
	var r: Dictionary = data.get("rooms", {})
	var key := "open" if out and not bed_name.begins_with("village") else bed_name
	var e = r.get(key, r.get("open", [0.15, 0.03]))
	return e if e is Array and e.size() == 2 else [0.15, 0.03]


static func entry_ok(e: Dictionary, is_day: bool, hr: float, wx: String, sea: String) -> bool:
	## may this spot sound now?
	if e.has("day") and bool(e["day"]) != is_day:
		return false
	if e.has("hours"):
		var h: Array = e["hours"]
		if h.size() == 2 and not (hr >= float(h[0]) and hr < float(h[1])):
			return false
	if e.has("weather") and not (wx in (e["weather"] as Array)):
		return false
	if e.has("not_weather") and wx in (e["not_weather"] as Array):
		return false
	if e.has("season") and sea != "" and not (sea in (e["season"] as Array)):
		return false
	return true


static func entries_for(data: Dictionary, bed_name: String, wx: String) -> Array:
	## [key, entry] -- the place's own spots and the weather's
	var rows := []
	var sp: Dictionary = data.get("spots", {})
	var i := 0
	for e in sp.get(bed_name, []):
		rows.append(["%s#%d" % [bed_name, i], e])
		i += 1
	var ws: Dictionary = data.get("weather_spots", {})
	var j := 0
	for e in ws.get(wx, []):
		rows.append(["w:%s#%d" % [wx, j], e])
		j += 1
	return rows


# ---- the director ---------------------------------------------------------------------------------

func _W():
	return Game.sys("world")


func _level():
	var tree := get_tree()
	return tree.get_first_node_in_group("level") if tree else null


func refresh_place() -> void:
	## what the place is now: its bed, weather, light, season, floor and room
	var lv = _level()
	var d: Dictionary = audio.data()
	outdoor = level_outdoor(lv)
	day = Game.daylight() >= 0.35
	var W = _W()
	var reg := ""
	weather = ""
	season = ""
	if W != null and lv != null:
		reg = str(W.region())
		var wd: Dictionary = W.weather(reg)
		weather = str(wd.get("id", ""))
		season = str(W.season_id())
	var nb: String = audio.amb_override if audio.amb_override != "" else audio.ambience
	if nb != bed:
		bed = nb
		_timers.clear()
	ground_kind = ground_for(lv, d, weather)
	room = "open" if outdoor and not bed.begins_with("village") else bed
	var wb := weather_bed_for(d, weather, outdoor, reg)
	_set_weather_bed(str(wb[0]) if wb.size() == 2 and world_on() else "", float(wb[1]) if wb.size() == 2 else 1.0)


func thunder_after(secs: float, at: Vector3) -> void:
	## the lightning was seen; its thunder arrives a little after, from that way
	_thunder_in = secs
	_thunder_at = at


func tick(delta: float) -> void:
	_clock += delta
	if _thunder_in > 0.0:
		_thunder_in -= delta
		if _thunder_in <= 0.0 and world_on():
			_sound_spot({"s": "thunder_far", "vol": 0.5, "dist": [24, 30], "h": [10, 14], "at": _thunder_at})
	_place_poll -= delta
	if _place_poll <= 0.0:
		_place_poll = 2.0
		if audio.context == "title":
			bed = ""
			_set_weather_bed("", 1.0)
		else:
			refresh_place()
	_poll -= delta
	if _poll > 0.0:
		return
	var dt := SPOT_POLL - _poll
	_poll = SPOT_POLL
	if bed == "" or not world_on():
		return
	var hr: float = Game.hour()
	var calm: bool = audio.combat_level < 0.4 and not get_tree().paused and not bool(Game.get("world_frozen"))     # (hushed in a fight and while the world holds still)
	for row in entries_for(audio.data(), bed, weather):
		var key: String = row[0]
		var e: Dictionary = row[1]
		var ev: Array = e.get("every", [30, 60])
		if not _timers.has(key):
			_timers[key] = _rng.randf_range(float(ev[0]) * 0.3, float(ev[1]))     # first time: sooner, spread out
			continue
		_timers[key] = float(_timers[key]) - dt
		if float(_timers[key]) > 0.0:
			continue
		_timers[key] = _rng.randf_range(float(ev[0]), float(ev[1]))
		if not calm or not entry_ok(e, day, hr, weather, season):
			continue
		_sound_spot(e)


func _sound_spot(e: Dictionary) -> void:
	var nm := str(e.get("s", ""))
	if nm == "":
		return
	spot_log.append([snappedf(_clock, 0.1), nm])
	spot_count[nm] = int(spot_count.get(nm, 0)) + 1
	while spot_log.size() > LOG_MAX:
		spot_log.pop_front()
	if not audio.on():
		return
	var cam := get_viewport().get_camera_3d() if get_viewport() else null
	if cam == null:
		return
	var dist: Array = e.get("dist", [8, 20])
	var hh: Array = e.get("h", [0, 1])
	var a := _rng.randf() * TAU
	var r := _rng.randf_range(float(dist[0]), float(dist[1]))
	var base: Vector3 = cam.global_position
	var pl = get_tree().get_first_node_in_group("player")
	if pl is Node3D:
		base = (pl as Node3D).global_position
	var pos := base + Vector3(cos(a) * r, _rng.randf_range(float(hh[0]), float(hh[1])), sin(a) * r)
	if e.get("at") is Vector3:          # (a sound with a known source -- the flash's thunder: that way, kept far)
		var to: Vector3 = (e["at"] as Vector3) - base
		to.y = 0.0
		if to.length() > 0.5:
			pos = base + to.normalized() * r + Vector3(0, float(hh[0]), 0)
	place3d(nm, pos, float(e.get("vol", 0.3)), float(dist[1]) + 6.0, true)


# ---- placing a sound in the world -------------------------------------------------------------------

func place3d(name: String, pos: Vector3, vol: float, max_dist: float, caption: bool = true) -> bool:
	## a sound at a point: heard from that side, softer and duller with distance, with the room's echo.
	## false when it couldn't be placed (no camera, no players) -- the caller falls back.
	if caption:
		preload("res://scripts/core/Access.gd").caption(name, pos)
	if _p3.is_empty() or not audio.on():
		return false
	var s: AudioStream = audio._pick(name)
	if s == null:
		return true
	for p in _p3:
		var ap := p as AudioStreamPlayer3D
		if not ap.playing:
			ap.stream = s
			ap.global_position = pos
			ap.max_distance = max_dist
			ap.volume_db = audio._db(audio.sfx_vol() * vol * _rng.randf_range(0.85, 1.0))
			ap.pitch_scale = 1.0 + _rng.randf_range(-0.05, 0.05)
			ap.play()
			return true
	return true


# ---- the echo and the weather layer -----------------------------------------------------------------

func _process(delta: float) -> void:
	if audio == null:
		return
	tick(delta)
	if not audio.on():
		return
	if _verb:
		var r := room_for(audio.data(), bed, outdoor)
		var want := float(r[1]) if echo_on() else 0.0
		_wet_now = move_toward(_wet_now, want, delta * 0.2)
		_verb.wet = _wet_now
		_verb.room_size = lerpf(_verb.room_size, float(r[0]), minf(delta * 0.8, 1.0))
	var lvl: float = audio._amb_level() * _wx_gain
	if _wx_fade > 0.0:
		_wx_fade = maxf(_wx_fade - delta, 0.0)
		var k := 1.0 - _wx_fade / 4.0
		if _wx_to:
			_wx_to.volume_db = audio._db(lvl * k)
		if _wx_from:
			_wx_from.volume_db = audio._db(lvl * (1.0 - k))
			if _wx_fade <= 0.0:
				_wx_from.stop()
	elif _wx_to and _wx_to.playing:
		_wx_to.volume_db = audio._db(lvl)


func _set_weather_bed(name: String, gain: float) -> void:
	_wx_gain = gain
	if name == weather_bed:
		return
	weather_bed = name
	if not audio.on() or _wx_a == null:
		return
	var s: AudioStream = audio._stream(audio.AMB_DIR + name + ".ogg") if name != "" else null
	var nxt := _wx_b if _wx_to == _wx_a else _wx_a
	if s:
		if s is AudioStreamOggVorbis:
			(s as AudioStreamOggVorbis).loop = true
		nxt.stream = s
		nxt.volume_db = -80.0
		nxt.play(_rng.randf() * 30.0)
	else:
		nxt.stop()
	_wx_from = _wx_to
	_wx_to = nxt
	_wx_fade = 4.0


# ---- footsteps -------------------------------------------------------------------------------------

static func step_fx_kind(ground: String, out: bool, wx: String) -> String:
	## round 184b: what a footfall throws up here ("" for nothing)
	if ground in ["snow", "sand", "water"]:
		return ground
	if ground == "grass" and out and wx in ["rain", "storm"]:
		return "puddle"
	return ""


func step_fx(running: bool) -> void:
	var k := step_fx_kind(ground_kind, outdoor, weather)
	if k == "" or not audio.on():
		return
	var pl = get_tree().get_first_node_in_group("player")
	if pl is Node3D:
		preload("res://scripts/fx/FX.gd").step_puff((pl as Node3D).global_position, k, running)


func step_sounds(running: bool) -> Array:
	## [[sound, loudness]...] for one step on this ground
	var base := 0.4 if running else 0.3
	match ground_kind:
		"snow":
			return [["step_snow", base * 1.1]]
		"water":
			return [["step_water", base * 1.2]]
		"sand":
			return [["step_sand", base * 1.2]]
		"metal":
			return [["step_metal", base * 0.8]]
		"wood":
			return [["step_wood", base * 0.9]]
		"grass":
			if outdoor and weather in ["rain", "storm"]:
				return [["step_grass", base], ["step_water", base * 0.45]]
			return [["step_grass", base]]
	return [["step_stone", base]]
