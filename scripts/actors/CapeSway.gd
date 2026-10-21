extends Node3D
## A cape that behaves like cloth (round 27): it hangs, breathes a little in
## the air when you stand, and streams out behind you as you move -- more
## the faster you go, settling back when you stop. The pivot is the cape's
## top edge; we only turn it about the shoulders' axis (and a touch to the
## side when you turn), smoothed so it never snaps.

var _last := Vector3.ZERO
var _have := false
var _swing := 0.0
var _side := 0.0
var _t := 0.0


func _ready() -> void:
	_t = randf() * 10.0


func _process(delta: float) -> void:
	if delta <= 0.0:
		return
	_t += delta
	var p := global_position
	var speed := 0.0
	var lateral := 0.0
	if _have:
		var v := (p - _last) / delta
		v.y = 0.0
		speed = v.length()
		# how much of the motion is sideways, from where the back faces
		var right := global_transform.basis.x
		right.y = 0.0
		if right.length() > 0.01 and speed > 0.1:
			lateral = v.normalized().dot(right.normalized())
	_last = p
	_have = true
	var want := clampf(speed / 8.0, 0.0, 1.0) * 0.75 + 0.05 + 0.03 * sin(_t * 1.3)
	_swing = lerpf(_swing, want, clampf(delta * 4.0, 0.0, 1.0))
	_side = lerpf(_side, -lateral * 0.25, clampf(delta * 3.0, 0.0, 1.0))
	rotation = Vector3(_swing, 0.0, _side)      # +x tips the hem back (-z)
