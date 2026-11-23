extends Node3D
## Fog of war (round 35 -- Robert: "add a fog of war so it's harder to see the
## rest of the level"). Underground only (dungeon floors, scavenger's hollows,
## trials, towers): towns and the open valley stay clear.
##
##   unexplored   black -- walls, floor, whatever stands there: you don't know
##   remembered   where you've been: dimmed, and nothing moving shows in it
##                (the chests and townsfolk you saw stay where you saw them)
##   in sight     what you can see from where you stand, out to SIGHT cells,
##                with walls and closed secret walls blocking the line
##
## What you've explored is kept per floor (Game.fog_seen, saved) so a floor you
## come back to remembers itself. Sight grows with what reads "sight" (a lantern,
## a technique, your familiar's nose -- Game.sight_radius). Settings: "Fog of
## war: on / off" in the menu (Gfx.settings "fog").

const SIGHT := 8                  # cells (16 m) of sight, before lanterns and arts
const BOX_H := 6.0                # tall enough to hide anything a floor holds
const DIM_ALPHA := 0.55           # how dark a remembered cell sits

var level
var seen := {}                    # cell -> true: explored
var visible_now := {}             # cell -> true: in sight right now
var _cells: Array = []            # every cell the shroud covers (not the void)
var _index := {}                  # cell -> instance index
var _dark: MultiMeshInstance3D    # unexplored
var _dim: MultiMeshInstance3D     # remembered, out of sight
var _last_cell := Vector2i(-9999, -9999)
var _t := 0.0
var _show := true                 # (headless: logic only, no meshes)
var _statics_dirty := true        # the explored set changed: re-check what stands on the floor


static func wanted(lvl) -> bool:
	if lvl == null or not ("theme" in lvl):
		return false
	if str(preload("res://scripts/core/Gfx.gd").load_settings().get("fog", "on")) == "off":
		return false
	if lvl.is_town() or lvl.is_outdoor() or str(lvl.theme) == "wilds":
		return false
	if bool(lvl.def.get("arena", false)) or bool(lvl.def.get("tribulation", false)) or str(lvl.def.get("online", "")) != "":
		return false                         # (round 125: the Gate's arena is one open room -- nothing hides in it)
	return true


func setup(lvl) -> void:
	level = lvl


func _ready() -> void:
	name = "FogOfWar"
	add_to_group("fog_of_war")
	_show = DisplayServer.get_name() != "headless"
	seen = Game.fog_load(str(level.level_id), level.grid)
	for y in level.grid.size():
		var row: String = level.grid[y]
		for x in row.length():
			if row[x] != " ":
				_cells.append(Vector2i(x, y))
	for i in _cells.size():
		_index[_cells[i]] = i
	if _show:
		_dark = _make_layer(Color(0, 0, 0, 1.0), false)
		_dim = _make_layer(Color(0, 0, 0, DIM_ALPHA), true)
		for i in _cells.size():
			_apply(i)


func _make_layer(col: Color, transparent: bool) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var box := BoxMesh.new()
	box.size = Vector3(level.CELL * 1.002, BOX_H, level.CELL * 1.002)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = col
	mat.disable_receive_shadows = true
	if transparent:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode = BaseMaterial3D.CULL_BACK
		mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS
		mat.render_priority = 1
	box.material = mat
	mm.mesh = box
	mm.instance_count = _cells.size()
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func _xf(cell: Vector2i, on: bool) -> Transform3D:
	if not on:
		return Transform3D(Basis().scaled(Vector3.ZERO), Vector3(0, -50, 0))
	return Transform3D(Basis(), level.cell_to_world(cell) + Vector3(0, BOX_H / 2.0 - 0.02, 0))


func _apply(i: int) -> void:
	if not _show:
		return
	var c: Vector2i = _cells[i]
	_dark.multimesh.set_instance_transform(i, _xf(c, not seen.has(c)))
	_dim.multimesh.set_instance_transform(i, _xf(c, seen.has(c) and not visible_now.has(c)))


func state(cell: Vector2i) -> String:
	## "unexplored", "remembered" or "visible"
	if visible_now.has(cell):
		return "visible"
	return "remembered" if seen.has(cell) else "unexplored"


func blocks(cell: Vector2i) -> bool:
	var ch: String = level.char_at(cell)
	if ch == "#" or ch == " ":
		return true
	if ch == "S":                                   # a secret wall, until it's found
		return not Game.has_flag(Game.flag_key(level.level_id, cell, "secret"))
	return false


func line_clear(a: Vector2i, b: Vector2i) -> bool:
	## Bresenham from a to b: nothing in between blocks (b itself may be a wall -- you see its face)
	var x0 := a.x
	var y0 := a.y
	var dx := absi(b.x - a.x)
	var dy := -absi(b.y - a.y)
	var sx := 1 if a.x < b.x else -1
	var sy := 1 if a.y < b.y else -1
	var err := dx + dy
	while true:
		if x0 == b.x and y0 == b.y:
			return true
		if not (x0 == a.x and y0 == a.y) and blocks(Vector2i(x0, y0)):
			return false
		var e2 := 2 * err
		if e2 >= dy:
			err += dy
			x0 += sx
		if e2 <= dx:
			err += dx
			y0 += sy
	return true


func reveal_from(at: Vector2i) -> int:
	## what you can see from this cell; returns how many cells were newly explored
	var r := SIGHT + Game.sight_bonus()
	var now := {}
	var fresh := 0
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if dx * dx + dy * dy > r * r:
				continue
			var c := at + Vector2i(dx, dy)
			if not _index.has(c) and c != at:
				continue
			if c == at or line_clear(at, c):
				now[c] = true
	var changed := {}
	for c in visible_now:
		if not now.has(c):
			changed[c] = true
	for c in now:
		if not visible_now.has(c):
			changed[c] = true
		if not seen.has(c):
			seen[c] = true
			fresh += 1
	visible_now = now
	if fresh > 0:
		_statics_dirty = true
	for c in changed:
		if _index.has(c):
			_apply(int(_index[c]))
	if fresh > 0:
		Game.fog_store(str(level.level_id), seen, level.grid)
		if str(level.level_id).begins_with("floor"):
			Game.fog_frac[str(level.level_id)] = snappedf(explored_fraction(), 0.001)    # round 37: mastery counts explored floors
	return fresh


var _open_total := -1


func explored_fraction() -> float:
	if _open_total < 0:
		_open_total = 0
		for c in _cells:
			if not blocks(c):
				_open_total += 1
	var n := 0
	for c in seen:
		if _index.has(c) and not blocks(c):
			n += 1
	return float(n) / maxf(1.0, float(_open_total))


func reveal_all() -> void:
	## a floor's map (a lore stone's, a scout's): everything explored at once
	for c in _cells:
		seen[c] = true
	for i in _cells.size():
		_apply(i)
	_statics_dirty = true
	Game.fog_store(str(level.level_id), seen, level.grid)


func _process(delta: float) -> void:
	var pl = get_tree().get_first_node_in_group("player")
	if pl == null:
		return
	var c: Vector2i = level.world_to_cell(pl.global_position)
	_t -= delta
	if c != _last_cell or _t <= 0.0:
		_last_cell = c
		_t = 0.5                               # (a secret wall opens, a gate lifts: look again)
		reveal_from(c)
	_hide_things()


func _cell_of(n: Node3D) -> Vector2i:
	return level.world_to_cell(n.global_position)


func _hide_things() -> void:
	## anything that moves shows only in sight; anything that stays shows once explored
	for e in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(e) and e is Node3D:
			_fog_show(e, e._dead or visible_now.has(_cell_of(e)))
	if not _statics_dirty:
		return
	_statics_dirty = false
	# everything else the floor placed (chests, stones, levers, torches, the
	# stairs' signs): shown once you've explored where it stands
	for n in level.get_children():
		if n == self or not (n is Node3D) or n.get_script() == null or n.is_in_group("enemy") or n.is_in_group("fog_exempt"):
			continue          # (round 48: the world itself -- the weather, the rock past the walls -- isn't "a thing on a cell")
		_fog_show(n, seen.has(_cell_of(n)))


func _fog_show(n: Node3D, show: bool) -> void:
	## hide what the fog covers -- and only ever un-hide what the fog hid
	## (a townsperson walking with you is hidden for their own reasons)
	if show:
		if n.has_meta("fog_hidden"):
			n.remove_meta("fog_hidden")
			n.visible = true
	elif n.visible:
		n.visible = false
		n.set_meta("fog_hidden", true)


func shown(n: Node3D) -> bool:
	return not n.has_meta("fog_hidden")
