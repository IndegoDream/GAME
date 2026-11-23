extends Node3D
## A camp of the deep's people, as you see it (round 44; the rules are in
## systems/Settlements.gd). Built around a fire in an open hall, and rebuilt
## as it grows: what each stage adds is something you can see --
##   camp     a fire, two tents, the headman, a few of their people, their banner
##   outpost  more tents, a fence going up, a trader's stall, lanterns
##   haven    a proper workshop, carts and stores, a shrine you can sit at
##   town     an inn, a market, light everywhere -- and your statue by the fire

var level
var cell := Vector2i.ZERO
var sid := ""
var built_stage := -1
var radius := 3            # nothing goes further out than this (the square is one wider)
var _parts: Node3D
var _people := []          # NPC nodes we spawned
var _check := 0.0
var _flames := []
var _ft := 0.0

# (offset, model, scale, from stage) -- the camp's look, ring by ring
const PIECES := [
	[Vector2i(-2, -2), "nature-kit/tent_smallOpen.glb", 2.2, 0],
	[Vector2i(2, -2), "nature-kit/tent_smallClosed.glb", 2.2, 0],
	[Vector2i(-3, 1), "mini-dungeon/barrel.glb", 1.6, 0],
	[Vector2i(-2, 2), "nature-kit/tent_detailedOpen.glb", 2.2, 1],
	[Vector2i(2, 2), "nature-kit/tent_smallOpen.glb", 2.2, 1],
	[Vector2i(-4, -4), "fantasy-town-kit/fence.glb", 1.6, 1],
	[Vector2i(4, -4), "fantasy-town-kit/fence.glb", 1.6, 1],
	[Vector2i(4, 4), "fantasy-town-kit/fence-broken.glb", 1.6, 1],
	[Vector2i(3, -1), "fantasy-town-kit/stall.glb", 1.6, 1],
	[Vector2i(-3, -1), "fantasy-town-kit/cart.glb", 1.6, 2],
	[Vector2i(-4, 4), "fantasy-town-kit/fence.glb", 1.6, 2],
	[Vector2i(-1, -3), "nature-kit/tent_detailedClosed.glb", 2.2, 2],
	[Vector2i(3, 3), "mini-dungeon/barrel.glb", 1.6, 2],
	[Vector2i(1, -3), "nature-kit/pot_large.glb", 2.0, 2],
	[Vector2i(3, 1), "fantasy-town-kit/stall-green.glb", 1.6, 3],
	[Vector2i(-3, 3), "fantasy-town-kit/stall-red.glb", 1.6, 3],
	[Vector2i(4, 0), "fantasy-town-kit/cart-high.glb", 1.6, 3],
]
# where people stand, in order: headman first, then each person by stage
const SPOTS := [Vector2i(0, -1), Vector2i(-1, 2), Vector2i(2, 0), Vector2i(-2, 0), Vector2i(1, 2), Vector2i(0, 3), Vector2i(-3, 2)]
const LANTERNS := [Vector2i(-1, -1), Vector2i(1, 1), Vector2i(-2, 3), Vector2i(3, -3), Vector2i(-3, -3)]


func setup(lvl, args: Dictionary) -> void:
	level = lvl
	cell = args.get("cell", Vector2i.ZERO)
	sid = str(args.get("sid", ""))
	radius = int(args.get("radius", 3))


func _S():
	return Game.sys("settlements")


func _ready() -> void:
	add_to_group("settlement")
	_build.call_deferred()        # (it adds people to the level: wait until the level is done setting up)


func _process(delta: float) -> void:
	_ft += delta
	for i in _flames.size():
		var fm = _flames[i]
		if is_instance_valid(fm):
			fm.scale = Vector3(1.0, 0.85 + 0.25 * absf(sin(_ft * (5.0 + i * 1.7) + i)), 1.0)
	_check -= delta
	if _check > 0.0:
		return
	_check = 1.0
	if _S() and _S().stage(sid) != built_stage:
		_build()            # it grew while you stood there


func _build() -> void:
	var S = _S()
	if S == null or level == null:
		return
	var stg: int = S.stage(sid)
	var sd: Dictionary = S.sdef(sid)
	if _parts:
		_parts.queue_free()
	_parts = Node3D.new()
	_parts.name = "Parts"
	add_child(_parts)
	# the fire, always
	var fire := _piece("nature-kit/campfire_stones.glb", Vector2i.ZERO, 2.2)
	if fire:
		fire.name = "Campfire"
	var fl := OmniLight3D.new()
	fl.light_color = Color(1.0, 0.65, 0.35)
	fl.light_energy = 2.2 + 0.4 * stg
	fl.omni_range = 9.0 + 2.0 * stg
	fl.position = Vector3(0, 1.2, 0)
	_parts.add_child(fl)
	var em = preload("res://scripts/fx/Motes.gd").new()
	em.kind = "smoke"
	em.position = Vector3(0, 0.8, 0)
	_parts.add_child(em)
	_flames = []
	for i in 3:
		var fm := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.0
		cm.bottom_radius = 0.22 - 0.05 * i
		cm.height = 0.7 - 0.12 * i
		fm.mesh = cm
		var mat := StandardMaterial3D.new()
		var fc: Color = [Color(1.0, 0.45, 0.12), Color(1.0, 0.7, 0.25), Color(1.0, 0.9, 0.55)][i]
		mat.albedo_color = fc
		mat.emission_enabled = true
		mat.emission = fc
		mat.emission_energy_multiplier = 2.5
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		fm.material_override = mat
		fm.position = Vector3(0.08 * (i - 1), 0.35 + 0.05 * i, 0.05 * (1 - i))
		_parts.add_child(fm)
		_flames.append(fm)
	level._solid(cell)
	for p in PIECES:
		if stg >= int(p[3]):
			_piece(str(p[1]), p[0], float(p[2]), true)
	# their colours
	var F = Game.sys("factions")
	var fid := str(sd.get("faction", ""))
	var fcol := Color(0.9, 0.9, 0.9)
	var bmodel := "mini-dungeon/banner.glb"
	if F:
		var fc: Array = F.fdef(fid).get("color", [0.9, 0.9, 0.9])
		fcol = Color(float(fc[0]), float(fc[1]), float(fc[2]))
		bmodel = str(F.fdef(fid).get("banner", bmodel))
	var bn := _piece(bmodel, Vector2i(0, -radius), 2.0, true)
	if bn:
		bn.name = "Banner"
		level._tint(bn, fcol.lerp(Color(1, 1, 1), 0.35))
	if stg >= 3:
		var bn2 := _piece(bmodel, Vector2i(0, radius), 2.0, true)
		if bn2:
			level._tint(bn2, fcol.lerp(Color(1, 1, 1), 0.35))
	# lanterns from the outpost on
	if stg >= 1:
		for i in mini(LANTERNS.size(), stg + 1):
			var lc: Vector2i = LANTERNS[i]
			var lp := _piece("fantasy-town-kit/lantern.glb", lc, 1.5, false)
			if lp:
				lp.position.y = 0.0
			var l := OmniLight3D.new()
			l.light_color = fcol.lerp(Color(1.0, 0.85, 0.6), 0.6)
			l.light_energy = 1.1
			l.omni_range = 6.0
			l.position = level.cell_to_world(cell + lc) - global_position + Vector3(0, 1.6, 0)
			_parts.add_child(l)
	# a shrine from the haven on (only once: it's a real node, not a prop)
	if stg >= 2 and get_node_or_null("../Shrine_" + sid) == null:
		var sc := _free_near(Vector2i(-3, 0))
		if sc.x > -9999:
			var sh = level._spawn_script("res://scripts/objects/Shrine.gd", level.cell_to_world(cell + sc), {"cell": cell + sc})
			if sh:
				sh.name = "Shrine_" + sid
	# your statue, once it's a town
	if stg >= 3:
		_statue()
	_spawn_people(stg, sd)
	built_stage = stg


func _piece(model: String, off: Vector2i, s: float, solid: bool = true) -> Node3D:
	var c := cell + off
	if maxi(absi(off.x), absi(off.y)) > radius:
		return null
	if off != Vector2i.ZERO and not level.is_free(c):
		return null
	var at: Vector3 = level.cell_to_world(c)
	var yaw := atan2(float(-off.x), float(-off.y)) if off != Vector2i.ZERO else 0.0
	var m: Node3D = level._model(model)
	m.position = at - global_position
	m.scale = Vector3.ONE * s
	m.rotation.y = yaw + PI
	_parts.add_child(m)
	if solid and off != Vector2i.ZERO:
		level._solid(c)
	return m


func _free_near(off: Vector2i) -> Vector2i:
	for d in [Vector2i.ZERO, Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
		var o: Vector2i = off + d
		if maxi(absi(o.x), absi(o.y)) <= radius and o != Vector2i.ZERO and level.is_free(cell + o):
			return o
	return Vector2i(-9999, -9999)


func _statue() -> void:
	if _parts.get_node_or_null("Statue"):
		return
	var spec := {"hair": "topknot", "robe": [0.6, 0.6, 0.6]}
	for k in ["sex", "skin", "hair", "hair_color", "beard"]:
		if Game.look.has(k):
			spec[k] = Game.look[k]
	var fig: Node3D = preload("res://scripts/core/Art.gd").person(spec)
	fig.name = "Statue"
	var c := _free_near(Vector2i(0, 2))
	if c.x <= -9999:
		c = Vector2i(0, 1)
	var base: Node3D = level._model("nature-kit/statue_block.glb")
	base.scale = Vector3(1.2, 0.5, 1.2)
	base.position = level.cell_to_world(cell + c) - global_position
	_parts.add_child(base)
	fig.position = base.position + Vector3(0, 0.5, 0)
	fig.rotation.y = PI
	_parts.add_child(fig)
	var bronze := StandardMaterial3D.new()        # bronze, whatever the figure is made of
	bronze.albedo_color = Color(0.62, 0.47, 0.3)
	bronze.metallic = 0.8
	bronze.roughness = 0.35
	_overlay(fig, bronze)
	for ap in fig.find_children("*", "AnimationPlayer", true, false):
		var a := ap as AnimationPlayer
		var pose := "idle" if a.has_animation("idle") else ""
		if pose != "":
			a.play(pose)           # held still, mid-breath -- a statue, not a puppet
			a.seek(0.4, true)
			a.pause()
	level._solid(cell + c)
	var tag := Label3D.new()
	tag.text = I18n.t("%s\n(they put it up for you)") % (Game.char_name if Game.char_name != "" else "You")
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.pixel_size = 0.008
	tag.font_size = 30
	tag.outline_size = 8
	tag.modulate = Color(1.0, 0.85, 0.55)
	tag.position = fig.position + Vector3(0, 2.4, 0)
	_parts.add_child(tag)


func _spawn_people(stg: int, sd: Dictionary) -> void:
	var have := {}
	var stock: Array = (sd.get("stock", []) as Array).duplicate()
	if stg >= 3:
		stock.append_array(sd.get("specialty", []))
	for n in _people:
		if is_instance_valid(n):
			have[str(n.npc_name)] = true
			n.def["stock"] = stock.duplicate()          # (a town's traders carry its specialty)
	var who := [{"name": str(sd.get("headman", {}).get("name", "Headman")), "role": "headman", "line": str(sd.get("headman", {}).get("line", "")), "stage": 0}]
	who.append_array(sd.get("people", []))
	var i := 0
	for p in who:
		if int(p.get("stage", 0)) > stg:
			i += 1
			continue
		var nm := str(p.get("name", ""))
		if str(p.get("role", "")) == "merchant" and Game.sys("settlements").market_day(sid):
			i += 1
			continue                  # (up in Eliet today, selling)
		if have.has(nm) or i >= SPOTS.size():
			i += 1
			continue
		var c := _free_near(SPOTS[i])
		i += 1
		if c.x <= -9999:
			continue
		var d := {"settlement": sid, "faction": str(sd.get("faction", "")), "lines": p.get("lines", []), "stays": true, "stock": stock.duplicate(),
			"price": int(Game.sys("settlements").rest_price(sid)) if str(p.get("role", "")) == "innkeeper" else 0}
		var npc = level._spawn_script("res://scripts/actors/NPC.gd", level.cell_to_world(cell + c), {"cell": cell + c, "role": str(p.get("role", "villager")), "name": nm, "line": str(p.get("line", "")), "def": d})
		if npc:
			npc.look_at_from_position(npc.position, level.cell_to_world(cell), Vector3.UP)
			npc.rotation.x = 0.0
			npc.rotation.z = 0.0
			npc.rotate_y(PI)
			_people.append(npc)
			level._count("settlers")


func _overlay(n: Node, m: Material) -> void:
	if n is MeshInstance3D:
		(n as MeshInstance3D).material_overlay = m
	for ch in n.get_children():
		_overlay(ch, m)
