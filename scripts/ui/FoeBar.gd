extends Node3D
## A foe's health, over its head (round 50) -- a slim rounded bar under its
## name instead of "Thornling 258/258". It shows once the foe is hurt (or
## always, for elites and bosses), leaves a pale trail when it drops (like
## your own bar), and goes when the foe does. Looks only; colours and sizes
## in data/ui.json "foe_bar".

const W := 64
const H := 8

static var _tex: Texture2D

var _bg: Sprite3D
var _trail: Sprite3D
var _fill: Sprite3D
var _frac := 1.0
var _trail_frac := 1.0
var _wait := 0.0
var always := false
var frac: float:
	get:
		return _frac


static func _bar_tex() -> Texture2D:
	## a white rounded bar, made once
	if _tex:
		return _tex
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	var r := H / 2.0
	for y in H:
		for x in W:
			var cx := clampf(x + 0.5, r, W - r)
			var d := Vector2(x + 0.5 - cx, y + 0.5 - r).length()
			var a := clampf(r - d + 0.5, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	_tex = ImageTexture.create_from_image(img)
	return _tex


func _cfg() -> Dictionary:
	return preload("res://scripts/core/UiStyle.gd").cfg().get("foe_bar", {})


func _c(key: String, fb: Color) -> Color:
	var a = _cfg().get(key, [])
	return Color(float(a[0]), float(a[1]), float(a[2]), float(a[3]) if a.size() > 3 else 1.0) if a is Array and a.size() >= 3 else fb


func setup(color: Color, show_always: bool) -> void:
	always = show_always
	var px := float(_cfg().get("width_m", 1.0)) / W
	_bg = _sprite(px, _c("track", Color(0.05, 0.05, 0.07, 0.8)), 10)
	_bg.scale = Vector3(1.06, 1.6, 1.0)          # a dark rim around the bar
	_trail = _sprite(px, _c("trail", Color(1.0, 0.92, 0.8, 0.7)), 11)
	_fill = _sprite(px, color, 12)
	visible = always


func _sprite(px: float, col: Color, prio: int) -> Sprite3D:
	var s := Sprite3D.new()
	s.texture = _bar_tex()
	s.pixel_size = px
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.no_depth_test = true
	s.shaded = false
	s.modulate = col
	s.render_priority = prio
	s.region_enabled = true
	s.region_rect = Rect2(0, 0, W, H)
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	add_child(s)
	return s


func set_frac(f: float) -> void:
	f = clampf(f, 0.0, 1.0)
	if f < _frac:
		_wait = float(_cfg().get("trail_wait", 0.35))
	else:
		_trail_frac = maxf(_trail_frac, f)
	_frac = f
	_crop(_fill, _frac)
	_crop(_trail, _trail_frac)
	visible = always or _frac < 0.999


func _crop(s: Sprite3D, f: float) -> void:
	## shrink from the right, keeping the left end where it was
	if s == null:
		return
	var w := maxf(W * f, 0.001)
	s.region_rect = Rect2(0, 0, w, H)
	s.offset = Vector2(-(W - w) * 0.5, 0)
	s.visible = f > 0.002


func _process(delta: float) -> void:
	if _trail_frac <= _frac:
		return
	if _wait > 0.0:
		_wait -= delta
		return
	_trail_frac = maxf(_frac, _trail_frac - delta * float(_cfg().get("trail_speed", 1.2)))
	_crop(_trail, _trail_frac)
