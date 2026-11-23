extends "res://scripts/actors/Enemy.gd"
## A foe that lives on the server. It looks like the solo game's foe (the same model, name, bar), but it doesn't think:
## the server moves it and decides its health, and a blow from this player is a *report* sent to the server.

var nid := 0
var net_target := Vector3.ZERO
var net_max := 1
var _last_sent := 0.0
var is_boss := false


func net_setup(lvl, id: int, etype_: String, nm: String, hp_now: int, hp_max: int, scale_: float, boss_: bool, at: Vector3) -> void:
	nid = id
	is_boss = boss_
	net_max = maxi(hp_max, 1)
	level = lvl
	etype = etype_
	stats = Game.enemies.get(etype_, {}).duplicate(true)
	if stats.is_empty():
		stats = {"name": nm, "model": "orc", "tint": [0.8, 0.5, 0.5], "hp": hp_max, "damage": 1, "speed": 1, "boss": boss_}
	stats["name"] = nm
	stats["scale"] = scale_
	stats["hp"] = hp_max
	stats["boss"] = boss_
	stats["loot"] = {}
	hp = hp_now
	position = at
	net_target = at
	style = "brawler"


func _ready() -> void:
	super._ready()
	_revealed = true
	if _model:
		_model.visible = true
	if _label:
		_label.visible = true
	_update_label()


func net_hp(now: int, mx: int) -> void:
	hp = now
	net_max = maxi(mx, 1)
	stats["hp"] = net_max
	if _label:
		_update_label()


func _physics_process(delta: float) -> void:
	if _dead:
		return
	var d := net_target - global_position
	d.y = 0.0
	if d.length() > 8.0:
		global_position = net_target
	elif d.length() > 0.02:
		global_position += d * minf(delta * 9.0, 1.0)
		_face(d)
		_loop(["walk"])
	_flash = maxf(_flash - delta, 0.0)
	if _model and _flash <= 0.0 and _model.scale != _base_scale:
		_model.scale = _model.scale.lerp(_base_scale, minf(delta * 12.0, 1.0))


func take_damage(amount: int, _source: String = "") -> void:
	## the blow is real only if the server says so: send the report, show the strike
	if _dead:
		return
	Online_send_hit(amount)
	_flash = 0.12
	if FX.on():
		var at := global_position + Vector3(0, _mid_height(), 0)
		FX.hit(at, Color(1.0, 0.82, 0.5), false)
		FX.number(at + Vector3(0, 0.6, 0), amount, "normal")
	Game.sfx_at("hit_heavy" if is_boss else "hit_flesh", global_position, 0.6)
	if _model:
		_model.scale = _base_scale * 1.08


func Online_send_hit(amount: int) -> void:
	var o = Game.online
	if o != null:
		o.send({"t": "i_hit", "foe": nid, "amt": amount})


func seen_hit(by_me: bool, amount: int) -> void:
	## somebody else's blow (the server told us): the number and a flash
	_flash = 0.1
	if FX.on() and not by_me:
		FX.number(global_position + Vector3(0, _mid_height() + 0.6, 0), amount, "normal")


func _die() -> void:
	## only the look of it: nothing is looted, no qi comes, no flag is set
	_dead = true
	Game.sfx_at("thud", global_position, 0.7)
	FX.puff(global_position + Vector3(0, _mid_height() * 0.6, 0), Color(0.5, 0.48, 0.45), clampf(float(stats.get("scale", 1.0)), 0.6, 2.5))
	remove_from_group("enemy")
	for c in get_children():
		if c is CollisionShape3D:
			c.set_deferred("disabled", true)
	if _label:
		_label.visible = false
	_play("die", true)
	preload("res://scripts/fx/OwnFX.gd").dissolve(_model)
	if _model and _model.has_method("die"):
		_model.die()
	FX.sink(self, 1.3)


func interact(_player) -> void:
	pass


func prompt() -> String:
	return ""
