extends Node3D
## A reach, alive (round 56): its own air, and the change you feel walking
## into it. While you're inside its bounds the floor's drifting motes give
## way to the reach's (spores, snow, embers, sparks ...), the haze takes the
## reach's colour, and the place name at the top of the screen says where
## you are. The first time (this game) you walk in, Reaches.gd names it and
## gives a little insight. Looks only, except that first-visit record.

const Motes := preload("res://scripts/fx/Motes.gd")

var level
var reach := {}          # Reach.gd's record: biome, name, rect, heart ...
var biome := {}
var rect := Rect2i()
var inside := false
var _motes: Node3D
var _t := 0.0
var _blend := 0.0        # 0 = the floor's air, 1 = the reach's
var _fog_c := Color()
var _fog_d := 0.0
var _amb_c := Color()
var _flicker := []


func setup(lvl, r: Dictionary) -> void:
	level = lvl
	reach = r
	biome = preload("res://scripts/world/Reach.gd").biome(str(r.get("biome", "")))
	var rr: Array = r.get("rect", [0, 0, 0, 0])
	rect = Rect2i(int(rr[0]), int(rr[1]), int(rr[2]), int(rr[3]))


func _ready() -> void:
	add_to_group("reach_zone")
	add_to_group("fog_exempt")
	name = "Reach_%d" % int(reach.get("i", 0))
	if DisplayServer.get_name() == "headless":
		return
	_motes = Motes.new()
	_motes.kind = str(biome.get("air", "dust"))
	_motes.tint = preload("res://scripts/world/ReachDress.gd").tint(biome)
	_motes.visible = false
	add_child(_motes)
	for n in level.get_children():
		if n is MeshInstance3D and n.has_meta("flicker"):
			_flicker.append(n)


func contains(cell: Vector2i) -> bool:
	return rect.has_point(cell)


func _process(delta: float) -> void:
	_t -= delta
	var target := 1.0 if inside else 0.0
	if not is_equal_approx(_blend, target):
		_blend = move_toward(_blend, target, delta / 1.4)       # a breath to feel the change
		_apply_air()
	for f in _flicker:
		if is_instance_valid(f):
			f.visible = randf() < 0.55
	if _t > 0.0:
		return
	_t = 0.25
	var p = get_tree().get_first_node_in_group("player")
	if p == null or level == null:
		return
	var now := contains(level.world_to_cell(p.global_position))
	if now == inside:
		return
	inside = now
	_enter() if inside else _leave()


func _enter() -> void:
	var hud = get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("set_level_name"):
		hud.set_level_name("%s  ·  %s" % [str(level.display_name()).get_slice(",", 0).get_slice(" -- ", 0), str(reach.get("name", ""))])
	var R = Game.sys("reaches")
	if R:
		R.entered(str(level.level_id), reach)
	if _motes:
		_motes.visible = true
	_main_motes(false)
	if Game.audio:
		Game.audio.set_reach_look(str(biome.get("look", "")))      # round 59: the reach's own air
	var env: Environment = level._env
	if env and _fog_d <= 0.0:              # (the floor's own air, taken once)
		_fog_c = env.fog_light_color
		_fog_d = env.fog_density
		_amb_c = env.ambient_light_color


func _leave() -> void:
	var hud = get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("set_level_name"):
		hud.set_level_name(level.display_name())
	if _motes:
		_motes.visible = false
	_main_motes(true)
	if Game.audio:
		Game.audio.set_reach_look("")


func _main_motes(on: bool) -> void:
	for n in level.get_children():
		if n is Motes and n.get_parent() == level:
			n.visible = on


func _apply_air() -> void:
	var env: Environment = level._env if level else null
	if env == null or _fog_d <= 0.0 and _blend <= 0.0:
		return
	var fc := preload("res://scripts/world/Look.gd").color3(biome.get("fog", []), _fog_c)
	env.fog_light_color = _fog_c.lerp(fc, _blend)
	env.fog_density = lerpf(_fog_d, float(biome.get("fog_density", _fog_d)) * 0.55, _blend)      # (softer haze than the first pass)
	level._fog_base = env.fog_density           # (a breathing floor breathes around the reach's haze)
	var tc := preload("res://scripts/world/ReachDress.gd").tint(biome)
	# the reach's own light, not the floor's tinted a little: its colour at the floor's brightness
	var lum := maxf(0.2, (_amb_c.r + _amb_c.g + _amb_c.b) / 3.0)
	var own := Color(tc.r, tc.g, tc.b) * (lum / maxf(0.2, (tc.r + tc.g + tc.b) / 3.0))
	env.ambient_light_color = _amb_c.lerp(own, _blend * 0.85)


func _exit_tree() -> void:
	if inside and Game.audio:
		Game.audio.set_reach_look("")         # (left the floor from inside the reach)
