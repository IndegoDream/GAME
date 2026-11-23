extends StaticBody3D
## A valley tower as you see it from outside (round 24): stacked stone
## tiers narrowing upward, each with a dark pagoda roof, a lantern at the
## door, the tower's name over it. The door itself is an exit on the map
## ("1"/"2"/"3", Valley.gd) into TowerGen's first floor. Taller the deeper
## its tier, so the Pagoda shows over the whole valley.

var level
var cell := Vector2i.ZERO
var tid := ""
var tier := 1
var radius := 3
var door := Vector2i.ZERO


func setup(lvl, args: Dictionary) -> void:
	level = lvl
	cell = args.get("cell", Vector2i.ZERO)
	tid = str(args.get("id", ""))
	tier = int(args.get("tier", 1))
	radius = int(args.get("radius", 3))
	var d: Array = args.get("door", [cell.x, cell.y + radius + 1])
	door = Vector2i(int(d[0]), int(d[1]))


func _ready() -> void:
	add_to_group("tower_spire")
	var headless := DisplayServer.get_name() == "headless"
	var t: Dictionary = Game.tower_def(tid)
	var base_r := float(radius) * 2.0 * 0.9          # metres (cells are 2 m)
	var tiers := 3 + tier * 2
	var stone: Material = null
	var roof_m: StandardMaterial3D = null
	if not headless:
		stone = preload("res://scripts/world/Look.gd").surface(["castle_brick_01" if tier < 3 else "old_stone_wall", [0.82, 0.8, 0.78], 2.0])
		roof_m = StandardMaterial3D.new()
		roof_m.albedo_color = [Color(0.25, 0.3, 0.22), Color(0.3, 0.32, 0.4), Color(0.45, 0.12, 0.1)][clampi(tier - 1, 0, 2)]
		roof_m.roughness = 0.8
	var y := 0.0
	for i in tiers:
		var r := base_r * (1.0 - 0.09 * i)
		var h := 4.2 - 0.15 * i
		var body := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.radial_segments = 8
		cm.top_radius = r * 0.94
		cm.bottom_radius = r
		cm.height = h
		body.mesh = cm
		body.position.y = y + h / 2.0
		if stone:
			body.material_override = stone
		add_child(body)
		var roof := MeshInstance3D.new()
		var rm := CylinderMesh.new()
		rm.radial_segments = 8
		rm.top_radius = r * 0.55
		rm.bottom_radius = r * 1.3
		rm.height = 0.9
		roof.mesh = rm
		roof.position.y = y + h + 0.3
		if roof_m:
			roof.material_override = roof_m
		add_child(roof)
		y += h + 0.6
	var spire := MeshInstance3D.new()
	var sm := CylinderMesh.new()
	sm.radial_segments = 8
	sm.top_radius = 0.05
	sm.bottom_radius = base_r * 0.35
	sm.height = 4.0
	spire.mesh = sm
	spire.position.y = y + 2.0
	if roof_m:
		spire.material_override = roof_m
	add_child(spire)
	# solid, so you walk round it, not through it
	var col := CollisionShape3D.new()
	var cs := CylinderShape3D.new()
	cs.radius = base_r
	cs.height = y + 4.0
	col.shape = cs
	col.position.y = cs.height / 2.0
	add_child(col)
	if level:
		for yy in range(cell.y - radius, cell.y + radius + 1):
			for xx in range(cell.x - radius, cell.x + radius + 1):
				if Vector2(xx - cell.x, yy - cell.y).length() <= radius + 0.2:
					level.astar.set_point_solid(Vector2i(xx, yy), true)
	# the door's lantern and name
	var dw: Vector3 = (level.cell_to_world(door) - global_position) if level else Vector3(0, 0, base_r + 1.0)
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.75, 0.45)
	lamp.light_energy = 1.6
	lamp.omni_range = 7.0
	lamp.position = Vector3(dw.x * 0.85, 3.0, dw.z * 0.85)
	add_child(lamp)
	var name_l := Label3D.new()
	var locked := Game.tower_locked(tid)
	name_l.text = "%s\n%s" % [t.get("name", I18n.t("A tower")), (I18n.t("climbed to floor %d of 9") % Game.tower_cleared(tid)) if locked == "" else I18n.t("sealed until %s") % Game.realm_info(int(t.get("realm", 0)))["name"]]
	name_l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	name_l.pixel_size = 0.012
	name_l.font_size = 40
	name_l.outline_size = 10
	name_l.modulate = Color(1.0, 0.88, 0.6)
	name_l.position = Vector3(dw.x * 0.9, 5.5, dw.z * 0.9)
	add_child(name_l)
