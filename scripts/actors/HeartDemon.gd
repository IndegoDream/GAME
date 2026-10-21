extends "res://scripts/actors/Enemy.gd"
## Your heart demon (round 25): the resistance of your own nanites to being
## rewritten at a breakthrough, wearing your shape. It fights like an
## ordinary foe -- and, every few seconds, uses the art family YOU lean on
## most (Game.favored_family), always with a moment's warning (a dark ring
## that swells), so it can be read, guarded, parried or stepped away from:
##
##   strike  a burst of dark qi around it
##   step    it vanishes and strikes from behind you
##   guard   it closes up for two seconds: blows mostly glance off, and
##           some come back
##
## Game.heart_demon_def sets its numbers from yours; its death crosses the
## realm (Game.tribulation_won), and your fall here costs an hour, not your
## progress (Game.tribulation_lost).

const WARN := 0.8
var _art_t := 4.0
var _warn_t := 0.0
var _guard_t := 0.0
var _ring: MeshInstance3D
var _ring_mat: StandardMaterial3D


func _ready() -> void:
	super()
	add_to_group("heart_demon")
	var aura := OmniLight3D.new()
	aura.light_color = Color(0.55, 0.2, 0.85)
	aura.light_energy = 1.6
	aura.omni_range = 6.0
	aura.position = Vector3(0, 1.5, 0)
	add_child(aura)
	_ring = MeshInstance3D.new()
	var t := TorusMesh.new()
	t.inner_radius = 0.9
	t.outer_radius = 1.0
	_ring.mesh = t
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.albedo_color = Color(0.45, 0.1, 0.6, 0.0)
	_ring_mat.emission_enabled = true
	_ring_mat.emission = Color(0.6, 0.15, 0.9)
	_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if DisplayServer.get_name() != "headless":
		_ring.material_override = _ring_mat
	_ring.position.y = 0.1
	_ring.visible = false
	add_child(_ring)
	_art_t = 4.0 + randf() * 2.0


func favored() -> String:
	return str(stats.get("favored", "strike"))


func _physics_process(delta: float) -> void:
	super(delta)
	if _dead:
		return
	_guard_t = maxf(_guard_t - delta, 0.0)
	var player = get_tree().get_first_node_in_group("player")
	if player == null or player.dead:
		return
	if _warn_t > 0.0:
		_warn_t -= delta
		var k := 1.0 - _warn_t / WARN
		_ring.visible = true
		_ring.scale = Vector3.ONE * (0.5 + 4.0 * k)
		_ring_mat.albedo_color.a = 0.3 + 0.5 * k
		if _warn_t <= 0.0:
			_ring.visible = false
			cast(player)
		return
	_art_t -= delta
	if _art_t <= 0.0:
		_art_t = maxf(4.0, 7.0 - 0.3 * float(stats.get("realm", 0)))
		_warn_t = WARN          # the tell: always a moment's warning


func cast(player) -> String:
	## the demon's art -- your own favourite family, turned on you
	match favored():
		"step":
			var away: Vector3 = player.global_position - global_position
			away.y = 0.0
			var fwd := Vector3(sin(player._model.rotation.y), 0, cos(player._model.rotation.y)) if player.get("_model") else Vector3.FORWARD
			global_position = player.global_position - fwd * 1.5
			player.take_damage(int(float(stats.get("damage", 5)) * 1.3), "your heart demon (from behind)", self)
			return "step"
		"guard":
			_guard_t = 2.0
			Game.message.emit("Your heart demon closes up, the way you do.")
			return "guard"
	# strike: a burst of dark qi round it
	if (player.global_position - global_position).length() <= 4.5:
		player.take_damage(int(float(stats.get("damage", 5)) * 1.6), "your heart demon's qi", self)
	return "strike"


func take_damage(amount: int, _source: String = "") -> void:
	if _guard_t > 0.0 and amount > 1:
		# it guards the way you guard: most of the blow glances off, some comes back
		var back := int(round(amount * 0.2))
		amount = int(round(amount * 0.3))
		var player = get_tree().get_first_node_in_group("player")
		if player and back > 0 and not player.dead:
			player.take_damage(back, "your own guard, turned", null)
	super(amount, _source)
