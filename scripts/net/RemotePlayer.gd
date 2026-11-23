extends Node3D
## Another player, drawn as a person with their name over their head. Moves toward the position the server last said.

var pname := "?"
var pid := ""
var target := Vector3.ZERO
var target_yaw := 0.0
var _model: Node3D
var _label: Label3D
var _hp_bar: MeshInstance3D
var _anim: AnimationPlayer
var _moving := false
var down := false
var ghost := false


func setup(id: String, nm: String, at: Vector3, realm: int = 0) -> void:
	pid = id
	pname = nm
	target = at
	position = at


func _ready() -> void:
	var D = preload("res://scripts/world/Dress.gd")
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(pname)
	var hue := rng.randf()
	var c := Color.from_hsv(hue, 0.5, 0.8)
	var spec: Dictionary = D.spec_for(pname, "villager", {"robe": [c.r, c.g, c.b], "sash": [0.15, 0.12, 0.12], "hair": "topknot", "held": "sword"})
	_model = preload("res://scripts/core/Art.gd").person(spec, 1.0)
	add_child(_model)
	D.dress(_model, spec)
	_anim = _find_anim(_model)
	_label = Label3D.new()
	_label.text = pname
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.pixel_size = 0.009
	_label.no_depth_test = true
	_label.position = Vector3(0, 2.3, 0)
	_label.font_size = 32
	_label.outline_size = 8
	_label.modulate = Color(0.7, 1.0, 0.8)
	add_child(_label)


func _find_anim(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var r := _find_anim(c)
		if r:
			return r
	return null


func set_down(d: bool) -> void:
	down = d
	if _model:
		_model.rotation.x = -PI / 2.0 if d else 0.0
		_model.position.y = 0.2 if d else 0.0
	if _label:
		_label.modulate = Color(1.0, 0.5, 0.45) if d else Color(0.7, 1.0, 0.8)


func _process(delta: float) -> void:
	var d := target - position
	d.y = 0.0
	_moving = d.length() > 0.05
	if d.length() > 6.0:
		position = target
	else:
		position += d * minf(delta * 8.0, 1.0)
	if _model and not down:
		_model.rotation.y = lerp_angle(_model.rotation.y, target_yaw, minf(delta * 10.0, 1.0))
	if _anim:
		var want := "walk" if _moving else "idle"
		if _anim.has_animation(want) and _anim.current_animation != want:
			_anim.play(want)
