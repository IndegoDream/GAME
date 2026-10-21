extends Node3D
## Round 119: what the player's bow, crossbow and qi focus send out.
## An arrow, a bolt or a ball of qi flies straight; it stops at walls; it
## strikes the first foe in its path (a pierce lets it keep going, losing a
## fifth of its force per foe). A charged ki shot bursts where it lands.
## Far shots hit harder and point-blank ones softer (data/combat.json
## "ranged"), so the weapon wants you to keep your distance.

const FX := preload("res://scripts/fx/FX.gd")

var thrower: Node
var dir := Vector3.FORWARD
var speed := 30.0
var damage := 10
var style := "arrow"           # arrow | bolt | ki
var color := Color(0.9, 0.85, 0.7)
var life := 1.0
var pierce := 0
var burst := 0.0                # a ki burst's blast radius (0 = none)
var burst_share := 0.6
var R := {}
var heavy := false
var _level
var _hit := {}
var _travelled := 0.0
var _far_shown := false


func setup(who: Node, from: Vector3, d: Vector3, st: String, ranged: Dictionary, dmg: int, pierce_n: int, burst_r: float, is_heavy: bool) -> void:
	thrower = who
	position = from
	dir = d.normalized() if d.length() > 0.01 else Vector3.FORWARD
	style = st
	R = ranged
	speed = float(ranged.get("speed", 30.0))
	life = float(ranged.get("range", 26.0)) / maxf(speed, 1.0)
	damage = dmg
	pierce = pierce_n
	burst = burst_r
	burst_share = float(ranged.get("burst_share", 0.6))
	heavy = is_heavy
	_level = who.get_parent().get_node_or_null("Level") if who != null and who.get_parent() != null else null
	match st:
		"ki":
			color = Color(0.55, 0.9, 1.0)
		"bolt":
			color = Color(0.85, 0.85, 0.9)
		_:
			color = Color(0.95, 0.88, 0.7)


func _ready() -> void:
	add_to_group("shot")
	if style == "ki":
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		var r := 0.2 if heavy else 0.11
		sm.radius = r
		sm.height = r * 2.0
		mi.mesh = sm
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = 3.5
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mi.material_override = m
		add_child(mi)
		if DisplayServer.get_name() != "headless":
			var l := OmniLight3D.new()
			l.light_color = color
			l.omni_range = 3.5 if heavy else 2.2
			l.light_energy = 1.4
			add_child(l)
	else:
		# a shaft with a head and fletching, pointing along its flight
		var length := 0.7 if style == "arrow" else 0.45
		var shaft := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.012 if style == "arrow" else 0.018
		cm.bottom_radius = cm.top_radius
		cm.height = length
		cm.radial_segments = 6
		shaft.mesh = cm
		var sm2 := StandardMaterial3D.new()
		sm2.albedo_color = Color(0.55, 0.4, 0.25)
		shaft.material_override = sm2
		shaft.rotation.x = PI / 2.0
		add_child(shaft)
		var head := MeshInstance3D.new()
		var hm := CylinderMesh.new()
		hm.top_radius = 0.0
		hm.bottom_radius = 0.03
		hm.height = 0.1
		hm.radial_segments = 6
		head.mesh = hm
		var hm2 := StandardMaterial3D.new()
		hm2.albedo_color = Color(0.75, 0.78, 0.82)
		hm2.metallic = 0.6
		head.material_override = hm2
		head.rotation.x = PI / 2.0
		head.position.z = length * 0.5 + 0.04
		add_child(head)
		var tail := MeshInstance3D.new()
		var tm := BoxMesh.new()
		tm.size = Vector3(0.06, 0.004, 0.1)
		tail.mesh = tm
		var tm2 := StandardMaterial3D.new()
		tm2.albedo_color = Color(0.85, 0.85, 0.8)
		tail.material_override = tm2
		tail.position.z = -length * 0.5 + 0.04
		add_child(tail)
	FX.trail(self, color)
	if dir.length() > 0.01:
		look_at(global_position + dir, Vector3.UP)


func _physics_process(delta: float) -> void:
	life -= delta
	if life <= 0.0:
		_fizzle()
		return
	var step := speed * delta
	position += dir * step
	_travelled += step
	if is_inside_tree() and dir.length() > 0.01:
		look_at(global_position + dir, Vector3.UP)
	if _level != null and is_instance_valid(_level) and _level.has_method("world_to_cell"):
		var c: Vector2i = _level.world_to_cell(global_position)
		if _level._is_wallish(c) or _level.char_at(c) == " ":
			_land(global_position)
			return
	for e in get_tree().get_nodes_in_group("enemy"):
		if _hit.has(e) or not is_instance_valid(e) or e.get("_dead") == true:
			continue
		var sc := float(e.stats.get("scale", 1.0)) if e.get("stats") != null else 1.0
		var centre: Vector3 = e.global_position + Vector3(0, 0.9 * sc, 0)
		if centre.distance_to(global_position) < 0.5 + 0.35 * sc:
			_strike(e)
			if pierce < 0:
				return


func _strike(e) -> void:
	_hit[e] = true
	var dmg := float(damage)
	var far_d := float(R.get("far_dist", 10.0))
	var close_d := float(R.get("close_dist", 2.5))
	if _travelled >= far_d:
		dmg *= float(R.get("far_mult", 1.3))
		if not _far_shown and FX.on() and float(R.get("far_mult", 1.0)) > 1.01:
			_far_shown = true
			FX.word(e.global_position + Vector3(0, 2.3, 0), "FAR SHOT", Color(0.7, 0.9, 1.0), 36)
	elif _travelled < close_d:
		dmg *= float(R.get("close_mult", 0.7))
	var Gm = Game
	dmg *= Gm.bestiary_mult(str(e.etype)) * Gm.fury_mult()
	if e.has_method("staggered") and e.staggered():
		dmg *= float(Gm.combat_data().get("poise", {}).get("stagger_damage_mult", 1.35))
	var n := maxi(1, int(round(dmg)))
	e.take_damage(n, "you (%s)" % style)
	if is_instance_valid(e) and e.has_method("poise_hit"):
		e.poise_hit(float(n) * (2.0 if heavy else 0.8), heavy)
	if FX.on() and is_instance_valid(e):
		FX.hit(e.global_position + Vector3(0, 1.1, 0), color, heavy)
	if (heavy or burst > 0.0) and is_instance_valid(e) and e.get("affixes") != null and "armoured" in e.affixes and R.has("sunder"):
		e.set("sundered", float(R.get("sunder_secs", 4.0)))        # round 121: a full draw splits the plating
		e.set("sunder_mult", 1.0 + float(R["sunder"]))
		if FX.on():
			FX.word(e.global_position + Vector3(0, 2.0, 0), "SUNDERED", Color(1.0, 0.6, 0.35), 38)
	Gm.train_weapon(1)
	if thrower != null and is_instance_valid(thrower) and thrower.has_method("_punch"):
		thrower._punch(0.5 if heavy else 0.25)
	if burst > 0.0:
		_land(e.global_position + Vector3(0, 1.0, 0), e)
		return
	if pierce > 0:
		pierce -= 1
		damage = int(round(damage * 0.8))
	else:
		queue_free()
		pierce = -1


func _land(at: Vector3, skip = null) -> void:
	## the shot ends here: a wall's spark, or a ki burst that catches what's near
	if burst > 0.0:
		for o in get_tree().get_nodes_in_group("enemy"):
			if o == skip or not is_instance_valid(o) or o.get("_dead") == true:
				continue
			if (o.global_position + Vector3(0, 0.9, 0)).distance_to(at) <= burst:
				var d2 := maxi(1, int(round(float(damage) * burst_share)))
				o.take_damage(d2, "you (ki burst)")
				if is_instance_valid(o) and o.has_method("poise_hit"):
					o.poise_hit(float(d2) * 1.5, true)
		if FX.on():
			FX.hit(at, color, true)
			FX.hit(at + Vector3(0, 0.3, 0), Color(1, 1, 1), true)
	elif FX.on():
		FX.hit(at, color)
	queue_free()
	pierce = -1


func _fizzle() -> void:
	if style == "ki" and FX.on():
		FX.hit(global_position, color)
	queue_free()
