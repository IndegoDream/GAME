extends Node3D
## Level -- builds one playable level out of a level file (res://levels/<id>.json).
##
## A level file is mostly a MAP: a list of text rows where every character
## is one 2x2-metre cell. The fixed characters are listed in LEGEND below
## and in DEV_GUIDE.md; letters you define yourself in the level file's
## "enemies", "chests", "exits" and "npcs" sections become those things.
##
## Walls draw themselves: any walkable cell that touches empty space (a
## space character, or the end of a row) gets a wall on that side. So a
## level only has to draw where you CAN walk -- '#' is still allowed for
## a wall in the middle of a room.

const CELL := 2.0
const K := "res://assets/kenney/"
const Look := preload("res://scripts/world/Look.gd")
const Art := preload("res://scripts/core/Art.gd")
const WALL_H := 2.4

## The characters every level shares. Anything else must be defined in
## the level file. (Keep this in step with godot_levels.py on the box.)
const LEGEND := {
	" ": "nothing -- solid rock, nobody can stand here",
	"#": "wall",
	".": "floor",
	",": "path / road (village) -- floor with a different look",
	"P": "player start (where you appear on a new game or after dying)",
	"L": "light -- a torch in a dungeon, a lantern in the village",
	"T": "spike trap -- hurts anyone standing on it when the spikes come up",
	"S": "secret wall -- looks like a wall; press E on it to open a passage",
	"o": "ore vein -- press E to mine (iron ore; silver in deep levels)",
	"h": "spirit herb -- press E to pick",
	"c": "column (blocks movement)",
	"b": "barrel (blocks movement)",
	"x": "rubble / rocks (blocks movement)",
	"t": "tree (blocks movement)",
	"H": "house wall block (village)",
	"f": "fountain (blocks movement)",
	"Z": "cultivation shrine -- meditate here for fast qi",
	"=": "banner on the floor-side of a wall (decoration only)",
	"~": "water (blocks movement)",
	"^": "glittering vein -- press E to chip out gems and precious metal (gold, jade; ruby and sapphire deeper)",
	"&": "fishing spot -- water; press E beside it to cast a line",
}
const WALKABLE := ".,PLToh=Z^"

var def := {}
var level_id := ""
var theme := "dungeon"
var _sky_mat: ShaderMaterial          # round 37: the sky shader (outdoors)
var sun_light: DirectionalLight3D      # round 44: the sun (or moon) under the sky
var _stalactites: MultiMeshInstance3D  # round 37: shown only when the camera is under the roof
var grid: Array[String] = []
var width := 0
var height := 0
var astar := AStarGrid2D.new()
var spawns := {}          # char -> Array of Vector2i (where that char appears)
var warnings: Array[String] = []
var counts := {}          # what got built, for the smoke test

var _models := {}         # path -> PackedScene cache
var _rng := RandomNumberGenerator.new()
var _env: Environment
var _amb_base := 1.0
var _fog_base := 0.018
var _breath_t := 0.0
var _glows := 0
var ground := "moss"      # a settlement's ground: "moss" (Shellhaven) or "deck" (a market on water)
var look := {}            # how this place looks (Look.gd): surfaces, clutter, motes, light, creatures
var look_key := ""
var event := {}           # round 30: today's world event on this floor ({} = an ordinary day)
var set_pieces := {}      # round 32: where the gate, vault, keeper and levers went
var puzzle_order: Array = []
var puzzle_group := ""
var puzzle_pulled: Array = []
var puzzle_reward_cell := Vector2i(-1, -1)


func lever_pulled(lever) -> void:
	## the levers (SetPieces): the right order opens the puzzle gate; the
	## wrong one wakes the floor and resets them
	if puzzle_order.is_empty() or Game.has_flag("%s:puzzle:%s" % [level_id, puzzle_group]):
		return
	puzzle_pulled.append(str(lever.color_name))
	var i := puzzle_pulled.size() - 1
	if str(puzzle_order[i]) != str(lever.color_name):
		puzzle_pulled = []
		Game.message.emit("A grinding deep in the walls -- the wrong one. Something heard that.")
		Game.sfx("stamp", 0.9)
		Game.log_event("puzzle_wrong", {})
		for lv in get_tree().get_nodes_in_group("lever"):
			if lv.level == self:
				lv.reset()
		for e in get_tree().get_nodes_in_group("enemy"):
			if is_instance_valid(e) and not e._dead and not bool(e.stats.get("passive", false)) and (e.global_position - lever.global_position).length() < 24.0:
				e._chasing = true
				if not e._revealed:
					e._reveal()
		return
	Game.sfx("ui_ok", 0.7)
	if puzzle_pulled.size() >= puzzle_order.size():
		Game.set_flag("%s:puzzle:%s" % [level_id, puzzle_group])
		Game.message.emit("Three levers, the right order: somewhere, iron lifts.")
		Game.log_event("puzzle_solved", {})
		Game.gain_insight(2.0, "a puzzle")
		var opened := false
		for g in get_tree().get_nodes_in_group("gate"):
			if g.level == self and g.puzzle:
				g.open_up("the levers")
				opened = true
		if not opened and puzzle_reward_cell.x >= 0:
			var d := int(def.get("depth", 1))
			Game.drop_gear(d, 1)
			Game.gold += 25 * d
			Game.message.emit("...and a hidden drawer in the tablet's post slides open: %d gold." % (25 * d))
var _floor_cells := {}    # cell -> true: drawn as ONE textured floor mesh (was a model per cell)
var _road_cells := {}
var _wall_cells := {}     # cell -> true: drawn as ONE textured wall mesh
# round 56: the deep's reaches (Reach.gd) -- regions grown past the map's edge, each its own land
var reaches := []           # Reach.gd's records for this floor
var _reach_rects := []      # Rect2i per reach
var _reach_biomes := []     # the biome dictionary per reach

## A settlement deep in the dungeon ("theme": "settlement"): a town in a
## cavern -- lanterns, roads and houses like the village, rock overhead
## instead of sky, moss and glowing mushrooms underfoot. "breathing": true
## makes the whole place rise and fall, slowly (Shellhaven is built on the
## back of a sleeping spirit tortoise).
const BREATH_SECONDS := 14.0
const MAX_GLOWS := 36


func is_town() -> bool:
	return theme == "village" or theme == "settlement"


func is_outdoor() -> bool:
	## under the sky: the village, and (round 24) the valley's wilds
	return theme == "village" or theme == "wilds"


# ======================================================================
# building
# ======================================================================

## round 158 (Robert: "it takes a long time for the world to sync when moving ... only populate nearby"):
## the looks of a place (trees, barrels, lanterns, wall clutter) are queued and made nearest-first, a few
## milliseconds a frame, instead of all before you can move. Solid things (colliders, blockers) and everything
## you can talk to, fight or open are still made at once -- only their visual dressing waits.
static var stream_on := false
static var STREAM_MS := 5.0
var _stream: Array = []
var _stream_sort_t := 0.0
var _stream_first := true


func _vis(at: Vector3, fn: Callable) -> void:
	if stream_on:
		_stream.append([at, fn])
	else:
		fn.call()


func stream_left() -> int:
	return _stream.size()


func finish_stream() -> void:
	while not _stream.is_empty():
		var e: Array = _stream.pop_back()
		(e[1] as Callable).call()


func _stream_step(budget_ms: float) -> void:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	var from := cam.global_position if cam != null else Vector3.ZERO
	if _stream_first or _stream_sort_t <= 0.0:
		_stream_sort_t = 1.5
		_stream_first = false
		# farthest first, so pop_back() takes the nearest
		_stream.sort_custom(func(a, b): return (a[0] as Vector3).distance_squared_to(from) > (b[0] as Vector3).distance_squared_to(from))
	var t0 := Time.get_ticks_usec()
	while not _stream.is_empty() and (Time.get_ticks_usec() - t0) < budget_ms * 1000.0:
		var e: Array = _stream.pop_back()
		(e[1] as Callable).call()


static var prof := false
var _pc := {}
var _t0 := 0


func _pt(what: String) -> void:
	if prof:
		var n := Time.get_ticks_usec()
		print("  [build ", level_id, "] ", what, " ", snappedf((n - _t0) / 1000.0, 0.1), " ms")
		_t0 = n


func build(d: Dictionary) -> void:
	_t0 = Time.get_ticks_usec()
	d = preload("res://scripts/world/Expanse.gd").expand(d)
	d = preload("res://scripts/world/Reach.gd").extend(d, Look.key_for(d))
	def = d
	reaches = d.get("reaches", [])
	_reach_rects.clear()
	_reach_biomes.clear()
	for r in reaches:
		var rr: Array = r.get("rect", [0, 0, 0, 0])
		_reach_rects.append(Rect2i(int(rr[0]), int(rr[1]), int(rr[2]), int(rr[3])))
		_reach_biomes.append(preload("res://scripts/world/Reach.gd").biome(str(r.get("biome", ""))))
	level_id = str(d.get("id", "unnamed"))
	theme = str(d.get("theme", "dungeon"))
	ground = str(d.get("ground", "moss"))
	look_key = Look.key_for(d)
	look = Look.get_look(d)
	Game.depth = int(d.get("depth", 0))
	event = Game.roll_world_event(level_id, d)
	name = "Level_" + level_id
	_rng.seed = hash(level_id)
	grid.clear()
	for row in d.get("map", []):
		grid.append(str(row))
	height = grid.size()
	width = 0
	for row in grid:
		width = max(width, row.length())
	if width == 0 or height == 0:
		warnings.append(I18n.t("the map is empty"))
		width = max(width, 1)
		height = max(height, 1)

	astar.region = Rect2i(0, 0, width, height)
	astar.cell_size = Vector2(1, 1)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.update()

	_build_environment()
	_pt("_build_environment")
	_build_ground()
	_pt("_build_ground")

	for y in range(height):
		for x in range(width):
			var cell := Vector2i(x, y)
			var ch := char_at(cell)
			if not spawns.has(ch):
				spawns[ch] = []
			spawns[ch].append(cell)
			var _tp := Time.get_ticks_usec()
			_place(ch, cell)
			if prof:
				_pc[ch] = float(_pc.get(ch, 0.0)) + (Time.get_ticks_usec() - _tp) / 1000.0
	if prof:
		print("  place by char: ", _pc)
	_pt("loop")
	_place_lamps()
	_pt("_place_lamps")
	_auto_walls()
	_pt("_auto_walls")
	_build_surfaces()
	_pt("_build_surfaces")
	_dress()
	_pt("_dress")
	_place_extras()
	_pt("_place_extras")
	_place_valley()
	_pt("_place_valley")
	_place_round30()
	_pt("_place_round30")
	_place_round44()
	_pt("_place_round44")
	set_pieces = preload("res://scripts/world/SetPieces.gd").place(self)
	_pt("set_pieces = preload")
	_place_legacies()
	_pt("_place_legacies")
	place_quests()
	_pt("place_quests")
	_place_waystone()
	_pt("_place_waystone")
	_place_gate()
	_pt("_place_gate")
	_place_gauntlet()
	_pt("_place_gauntlet")
	_place_dummy()
	_pt("_place_dummy")
	_place_landmark()
	_pt("_place_landmark")


func _place_dummy() -> void:
	## round 146: a training dummy stands in the village, a little way from the fountain
	if level_id != "village":
		return
	var c := near_spot(fountain_cell(), 24, "dummy:" + level_id, plaza_rmin() + 3)
	if c.x < 0:
		c = open_spot(1, "dummy2:" + level_id)
	if c.x < 0:
		return
	spawns["dummy"] = [c]
	_spawn_script("res://scripts/actors/Enemy.gd", cell_to_world(c), {"type": "goblin", "cell": c, "dummy": true})


func _place_landmark() -> void:
	## round 152: something enormous and far away to want -- the Heaven Gate, a dark spire with a slow ring of light,
	## seen from the village and the valley. Floor 50 is the road's end; this says so before you can reach it.
	if level_id != "village" and level_id != "valley":
		return
	var c := Vector2i(width - 3, 3) if level_id == "village" else Vector2i(3, 3)
	var root := Node3D.new()
	root.position = cell_to_world(c)
	add_child(root)
	var spire := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.6
	cm.bottom_radius = 5.0
	cm.height = 90.0
	cm.radial_segments = 8
	spire.mesh = cm
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.07, 0.07, 0.12)
	sm.emission_enabled = true
	sm.emission = Color(0.35, 0.3, 0.7)
	sm.emission_energy_multiplier = 0.25
	spire.material_override = sm
	spire.position.y = 45.0
	spire.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(spire)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 9.0
	tm.outer_radius = 10.0
	ring.mesh = tm
	var rm := StandardMaterial3D.new()
	rm.albedo_color = Color(0.9, 0.85, 1.0)
	rm.emission_enabled = true
	rm.emission = Color(0.8, 0.75, 1.0)
	rm.emission_energy_multiplier = 2.2
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.material_override = rm
	ring.position.y = 70.0
	ring.rotation.x = deg_to_rad(80.0)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.set_meta("spin", true)
	root.add_child(ring)
	var lb := Label3D.new()
	lb.text = I18n.t("THE HEAVEN GATE\nthe road's end: Floor 50")
	lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lb.pixel_size = 0.05
	lb.font_size = 40
	lb.outline_size = 10
	lb.modulate = Color(0.9, 0.85, 1.0)
	lb.visibility_range_end = 400.0
	lb.position.y = 84.0
	root.add_child(lb)
	spawns["landmark"] = [c]


func _place_gate() -> void:
	## round 125: the Gate to the shared world stands in the village and in the valley
	if level_id != "village" and level_id != "valley":
		return
	var anchor: Vector2i = fountain_cell() if level_id == "village" else Vector2i(width / 2, height / 2)
	var pl: Array = spawns.get("P", [])
	if level_id == "valley" and not pl.is_empty():
		anchor = pl[0]
	var c := near_spot(anchor, 16, "gate:" + level_id, plaza_rmin())
	if c.x < 0:
		c = open_spot(1, "gate2:" + level_id)
	if c.x < 0:
		warnings.append(I18n.t("no room for the Gate"))
		return
	spawns["gate"] = [c]
	_spawn_script("res://scripts/objects/Exit.gd", cell_to_world(c), {"cell": c, "to": "online:hub", "arrive": "P", "label": "The Gate -- Elite Online", "down": false, "style": "portal"})
	_count("gates")


func _place_gauntlet() -> void:
	## round 126: the Ember Stone -- the roguelite ring -- stands by the village fountain
	if level_id != "village":
		return
	var c := near_spot(fountain_cell(), 14, "ember:" + level_id, plaza_rmin())
	if c.x < 0:
		c = open_spot(1, "ember2:" + level_id)
	if c.x < 0:
		return
	spawns["ember"] = [c]
	_spawn_script("res://scripts/objects/GauntletStone.gd", cell_to_world(c), {"cell": c})
	_count("ember_stones")


func _open_walk_cells(blocked: Dictionary, start: Vector2i) -> int:
	## how many cells can be reached on foot from `start` (4-way) with the `blocked` cells treated as walls
	var seen := {start: true}
	var q := [start]
	var i := 0
	while i < q.size():
		var c: Vector2i = q[i]
		i += 1
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if seen.has(n) or blocked.has(n) or not astar.region.has_point(n) or astar.is_point_solid(n):
				continue
			seen[n] = true
			q.append(n)
	return seen.size()


func _open_neighbours(c: Vector2i) -> int:
	var k := 0
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]:
		var n: Vector2i = c + d
		if astar.region.has_point(n) and not astar.is_point_solid(n):
			k += 1
	return k


func _unplug_chests() -> void:
	## A chest or ore vein standing in a one-cell doorway cuts the floor in two (stress bot, floor 21). Where freeing it reaches more of
	## the floor than keeping it solid, it moves to the nearest roomy spot that cuts nothing off. Gates and secret walls count as open.
	var starts: Array = spawns.get("<", spawns.get("P", []))
	if starts.is_empty():
		return
	var start: Vector2i = starts[0]
	if astar.is_point_solid(start):
		for d in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
			if astar.region.has_point(start + d) and not astar.is_point_solid(start + d):
				start = start + d
				break
	var things: Array = []
	var doors: Array = []
	for n in get_children():
		var sc = n.get_script()
		if sc == null:
			continue
		var f: String = str(sc.resource_path)
		if (f.ends_with("Chest.gd") or f.ends_with("GatherNode.gd")) and n.get("cell") != null and astar.region.has_point(n.cell) and astar.is_point_solid(n.cell):
			things.append(n)
		elif f.ends_with("Gate.gd") or f.ends_with("SecretWall.gd"):
			var dc = n.get("cell")
			if dc != null and astar.region.has_point(dc) and astar.is_point_solid(dc):
				doors.append(dc)
	if things.is_empty():
		return
	for dc in doors:
		astar.set_point_solid(dc, false)
	for n in things:
		var c: Vector2i = n.cell
		if _open_neighbours(c) <= 1:
			continue                                   # a dead end: nothing lies beyond it
		var with_c := _reach_count(start)
		astar.set_point_solid(c, false)
		var without := _reach_count(start)
		if without <= with_c + 1:
			astar.set_point_solid(c, true)
			continue                                   # not in anyone's way
		var seen := {c: true}
		var q := [c]
		var depth := {c: 0}
		var i := 0
		var target := Vector2i(-1, -1)
		while i < q.size() and target.x < 0:
			var cur: Vector2i = q[i]
			i += 1
			if int(depth[cur]) >= 16:
				continue
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nb: Vector2i = cur + d
				if seen.has(nb) or not astar.region.has_point(nb) or astar.is_point_solid(nb):
					continue
				seen[nb] = true
				depth[nb] = int(depth[cur]) + 1
				q.append(nb)
				if char_at(nb) != "." or _open_neighbours(nb) < 7 or spawns_at(nb):
					continue
				astar.set_point_solid(nb, true)
				var ok := _reach_count(start) + 1 >= without
				astar.set_point_solid(nb, false)
				if ok:
					target = nb
					break
		if target.x >= 0:
			astar.set_point_solid(target, true)
			n.cell = target                            # (its save key stays the old one: an opened chest/node stays collected)
			n.position = cell_to_world(target)
			_count("chests_moved")
		else:
			astar.set_point_solid(c, true)             # nowhere better: leave it
	for dc in doors:
		astar.set_point_solid(dc, true)


func spawns_at(cell: Vector2i) -> bool:
	## true when a spawn marker (arrival, exit, foe, ...) sits on this cell
	for k in spawns:
		if str(k) != "." and (spawns[k] as Array).has(cell):
			return true
	return false


func char_at(cell: Vector2i) -> String:
	if cell.y < 0 or cell.y >= grid.size():
		return " "
	var row: String = grid[cell.y]
	if cell.x < 0 or cell.x >= row.length():
		return " "
	return row[cell.x]


func reach_index(cell: Vector2i) -> int:
	## which reach this cell belongs to (-1: the floor itself)
	for i in _reach_rects.size():
		if (_reach_rects[i] as Rect2i).has_point(cell):
			return i
	return -1


func reach_biome(cell: Vector2i) -> Dictionary:
	var i := reach_index(cell)
	return _reach_biomes[i] if i >= 0 else {}


func cell_to_world(cell: Vector2i) -> Vector3:
	return Vector3((cell.x + 0.5) * CELL, 0.0, (cell.y + 0.5) * CELL)


func world_to_cell(p: Vector3) -> Vector2i:
	return Vector2i(int(floor(p.x / CELL)), int(floor(p.z / CELL)))


func is_walkable_char(ch: String) -> bool:
	if WALKABLE.contains(ch):
		return true
	# letters defined in the level file (enemies, chests, exits, npcs)
	# stand on floor too
	for section in ["enemies", "chests", "exits", "npcs", "lore", "inheritances", "riddles"]:
		if def.get(section, {}).has(ch):
			return true
	return false


func _place(ch: String, cell: Vector2i) -> void:
	var at := cell_to_world(cell)
	if ch == " ":
		_solid(cell)
		return
	if ch == "#":
		_wall(cell)
		return
	if ch == "S":
		_secret_wall(cell)
		return
	# everything else stands on a floor tile
	_floor_tile(cell, ch == ",")
	match ch:
		".", ",":
			pass
		"P":
			pass
		"L":
			if reach_index(cell) >= 0:
				preload("res://scripts/world/ReachDress.gd").lamp(self, cell, reach_biome(cell))      # round 56: the reach's own light
			else:
				_light(cell)
		"T":
			_spawn_script("res://scripts/objects/Trap.gd", at, {"cell": cell})
			_count("traps")
		"o":
			_spawn_script("res://scripts/objects/GatherNode.gd", at, {"kind": "ore", "cell": cell})
			_count("ore")
		"h":
			_spawn_script("res://scripts/objects/GatherNode.gd", at, {"kind": "herb", "cell": cell})
			_count("herbs")
		"c":
			if reach_index(cell) >= 0:
				preload("res://scripts/world/ReachDress.gd").giant(self, cell, reach_biome(cell), true)
			elif (def.get("giants", {}) as Dictionary).has("c"):
				preload("res://scripts/world/TechDress.gd").giant(self, cell, str(def["giants"]["c"]))          # round 123: the frontier's own big things
			else:
				_vis(at, func(): _prop("mini-dungeon/column.glb", at, 2.0))
				_blocker(cell, 1.0)
		"b":
			if theme == "settlement" and ground == "deck":
				# a market on water: stalls and carts, not barrels
				var stalls := ["fantasy-town-kit/stall.glb", "fantasy-town-kit/stall-red.glb", "fantasy-town-kit/stall-green.glb", "fantasy-town-kit/cart.glb"]
				var sp: String = stalls[_rng.randi() % stalls.size()]
				var sy: float = (_rng.randi() % 4) * PI / 2
				_vis(at, func(): _prop(sp, at, 2.0, sy))
			else:
				var bat := at + Vector3(_jit(), 0, _jit())
				_vis(bat, func(): _prop("mini-dungeon/barrel.glb", bat, 2.0))
			_blocker(cell, 0.9)
		"x":
			if reach_index(cell) >= 0:
				preload("res://scripts/world/ReachDress.gd").giant(self, cell, reach_biome(cell), false)
			elif (def.get("giants", {}) as Dictionary).has("x"):
				preload("res://scripts/world/TechDress.gd").giant(self, cell, str(def["giants"]["x"]))
			else:
				_vis(at, func(): _prop("mini-dungeon/rocks.glb", at, 2.0))
				_blocker(cell, 1.0)
		"t":
			var tree := "fantasy-town-kit/tree.glb" if _rng.randf() < 0.5 else "nature-kit/tree_oak.glb"
			var tv := _season_trees()          # round 44: Harvest turns them, Frost darkens them
			if tv != "":
				tree = "nature-kit/tree_oak_%s.glb" % tv if _rng.randf() < 0.5 else "nature-kit/tree_default_%s.glb" % tv
			var tyaw := _rng.randf() * TAU
			var tpath := tree
			var ts := 2.0 if tree.begins_with("fantasy") else 2.8
			_vis(at, func(): _prop(tpath, at, ts, tyaw))
			if tv != "":
				_count("season_trees")
			_blocker(cell, 0.7)
		"H":
			_house_block(cell)
		"f":
			_spawn_script("res://scripts/objects/Fountain.gd", at, {"cell": cell})
		"~":
			_water(cell)
		"%":
			preload("res://scripts/world/ReachDress.gd").lava(self, cell, reach_biome(cell))       # round 56: the Ember Rift's fire
		"^":
			_spawn_script("res://scripts/objects/GatherNode.gd", at, {"kind": "gem", "cell": cell})
			_count("gems")
		"&":
			_water(cell)
			_spawn_script("res://scripts/objects/GatherNode.gd", at, {"kind": "fish", "cell": cell})
			_count("fishing")
		"Z":
			_spawn_script("res://scripts/objects/Shrine.gd", at, {"cell": cell})
			_count("shrines")
		"=":
			_banner(cell)
		_:
			_place_defined(ch, cell, at)


func _place_defined(ch: String, cell: Vector2i, at: Vector3) -> void:
	var enemies: Dictionary = def.get("enemies", {})
	var chests: Dictionary = def.get("chests", {})
	var exits: Dictionary = def.get("exits", {})
	var npcs: Dictionary = def.get("npcs", {})
	var lore: Dictionary = def.get("lore", {})
	var inh: Dictionary = def.get("inheritances", {})
	var rid: Dictionary = def.get("riddles", {})
	if rid.has(ch):
		_spawn_script("res://scripts/objects/RiddleStone.gd", at, {"cell": cell, "def": rid[ch]})
		_count("riddles")
		return
	if inh.has(ch):
		# round 51: where (and whether) a major legacy sits is this game's own
		# choice -- placed at the end of the build (_place_legacies)
		if Game.sys("legacies") == null:
			_spawn_script("res://scripts/objects/Inheritance.gd", at, {"cell": cell, "def": inh[ch]})
			_count("inheritances")
		else:
			_pending_legacies.append([ch, cell, inh[ch]])
		return
	if lore.has(ch):
		_spawn_script("res://scripts/objects/Stele.gd", at, {"cell": cell, "def": lore[ch]})
		_count("lore")
		return
	if enemies.has(ch):
		var etype := str(enemies[ch])
		if not Game.enemies.has(etype):
			warnings.append("'%s' at %s is enemy type '%s', which data/enemies.json doesn't define" % [ch, cell, etype])
			return
		# a boss that's already been killed stays dead
		if bool(Game.enemies[etype].get("boss", false)) and Game.has_flag("%s:boss:%s" % [level_id, etype]):
			return
		# round 28: placed foes roll their style, a variant, and maybe an elite affix (foes.json)
		_spawn_script("res://scripts/actors/HeartDemon.gd" if etype == "heart_demon" else "res://scripts/actors/Enemy.gd", at, {"type": etype, "cell": cell, "roll": etype != "heart_demon"})
		_count("enemies")
	elif chests.has(ch):
		_spawn_script("res://scripts/objects/Chest.gd", at, {"cell": cell, "loot": chests[ch].get("loot", {}), "note": chests[ch].get("note", ""), "hidden": bool(chests[ch].get("hidden", false))})
		_count("chests")
	elif exits.has(ch):
		var e: Dictionary = exits[ch]
		_spawn_script("res://scripts/objects/Exit.gd", at, {"cell": cell, "to": str(e.get("to", "")), "arrive": str(e.get("arrive", "P")), "label": str(e.get("label", "")), "down": bool(e.get("down", true)), "needs": str(e.get("needs", "")),
			"style": str(e.get("style", "door" if str(e.get("to", "")).begins_with("tower:") and theme == "wilds" else ("road" if theme == "wilds" else "stairs")))})
		_count("exits")
	elif npcs.has(ch):
		_spawn_script("res://scripts/actors/NPC.gd", at, {"cell": cell, "role": str(npcs[ch].get("role", "")), "name": str(npcs[ch].get("name", "Villager")), "line": str(npcs[ch].get("line", "")), "def": npcs[ch]})
		_count("npcs")
	else:
		warnings.append(I18n.t("unknown map character '%s' at %s -- built as plain floor") % [ch, cell])


# ======================================================================
# pieces
# ======================================================================

var _art_pick := 0


func _model(path: String) -> Node3D:
	if Art.stand_in(path) != "" or (Art.style != "kenney" and (Art.REMAT.has(path) or Art.is_tree(path))):
		_art_pick += 1
		return Art.make(path, _art_pick)        # photo-scanned stand-in or photo texture (Art.gd), same size and footing
	var full := K + path
	if not _models.has(full):
		if not ResourceLoader.exists(full):
			warnings.append("missing model " + full)
			_models[full] = null
		else:
			_models[full] = load(full)
	if _models[full] == null:
		return Node3D.new()
	return _models[full].instantiate()


func _prop(path: String, at: Vector3, s: float = 2.0, yaw: float = 0.0) -> Node3D:
	var m := _model(path)
	m.position = at
	m.scale = Vector3.ONE * s
	m.rotation.y = yaw
	add_child(m)
	return m


func _tint(n: Node, c: Color) -> void:
	if n is MeshInstance3D:
		for i in n.get_surface_override_material_count():
			var m = n.get_active_material(i)
			if m is StandardMaterial3D:
				var mm: StandardMaterial3D = m.duplicate()
				mm.albedo_color = mm.albedo_color * c
				n.set_surface_override_material(i, mm)
	for ch in n.get_children():
		_tint(ch, c)


func _jit() -> float:
	return _rng.randf_range(-0.25, 0.25)


func _count(what: String) -> void:
	counts[what] = int(counts.get(what, 0)) + 1


func _solid(cell: Vector2i) -> void:
	if astar.region.has_point(cell):
		astar.set_point_solid(cell, true)


func _box_body(center: Vector3, size: Vector3, group: String = "") -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = center
	if group != "":
		body.add_to_group(group)
	add_child(body)
	return body


func _blocker(cell: Vector2i, frac: float) -> void:
	_solid(cell)
	_box_body(cell_to_world(cell) + Vector3(0, 1.5, 0), Vector3(CELL * frac, 3.0, CELL * frac))


func _wall(cell: Vector2i) -> void:
	_solid(cell)
	var at := cell_to_world(cell)
	if theme == "settlement" and ground == "deck":
		# a market built on water: past the edge of the decks is the lake
		# (the lake surface is one plane under everything -- _build_ground);
		# here only an invisible edge, and now and then a light far down
		_box_body(at + Vector3(0, 1.5, 0), Vector3(CELL, 3.0, CELL))
		if _rng.randf() < 0.06 and _glows < MAX_GLOWS:
			_glows += 1
			var deep := OmniLight3D.new()
			deep.light_color = Color(0.35, 0.75, 1.0)
			deep.omni_range = 4.0
			deep.light_energy = 0.9
			deep.position = at + Vector3(_jit() * 2, -0.6, _jit() * 2)
			add_child(deep)
		_count("walls")
		return
	if theme == "wilds" and char_at(cell) == "#":
		# a built wall in the wilds (a sect's yard): dressed stone, not crag
		_prop("fantasy-town-kit/wall-block.glb", at, 2.0)
		var cap := _prop("fantasy-town-kit/roof-flat.glb", at + Vector3(0, 2.0, 0), 2.0)
		if cap and DisplayServer.get_name() != "headless":
			_tint(cap, Color(0.35, 0.3, 0.28))
		_box_body(at + Vector3(0, 1.5, 0), Vector3(CELL, 3.0, CELL))
		_count("walls")
		return
	if theme == "village" or (theme == "wilds" and _on_rim(cell)):
		# round 48: under the sky, the edge of the map isn't a wall of crags --
		# it's the edge of the fields (hedge, boulders, a fence, a tree), and
		# the land beyond (Horizon.gd) runs on into the hills
		_rim_edge(cell, at)
		_count("rim")
		_box_body(at + Vector3(0, 2.0, 0), Vector3(CELL, 4.0, CELL))
		_count("walls")
		return
	if is_town() or theme == "wilds":
		var rock := _prop("nature-kit/cliff_block_rock.glb", at + Vector3(0, 0.1, 0), 2.0, (_rng.randi() % 4) * PI / 2)
		rock.scale.y = 2.0 + _rng.randf() * 0.8
		if theme == "settlement":
			rock.scale.y = 3.2 + _rng.randf() * 1.6      # cavern walls rise into the dark
			# (looks only -- the headless engine check's dummy renderer
			# errors on re-tinting this model's materials, so skip it there)
			if DisplayServer.get_name() != "headless":
				_tint(rock, Color(0.55, 0.52, 0.6))
		elif def.has("cliff_tint") and DisplayServer.get_name() != "headless":
			_tint(rock, Look.color3(def["cliff_tint"], Color(0.6, 0.6, 0.65)))
	else:
		# drawn later, all together, as one textured mesh (_build_surfaces)
		_wall_cells[cell] = true
	_box_body(at + Vector3(0, 2.0, 0), Vector3(CELL, 4.0, CELL))
	_count("walls")


var _cap: BoxMesh


func _cap_mesh() -> BoxMesh:
	if _cap == null:
		_cap = BoxMesh.new()
		_cap.size = Vector3(CELL, 0.12, CELL)
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.2, 0.19, 0.24)
		m.roughness = 0.95
		_cap.material = m
	return _cap


func _on_rim(cell: Vector2i) -> bool:
	## a cell within two of the map's edge, with only open land (nothing) past it
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			var n := cell + Vector2i(dx, dy)
			if n.x < 0 or n.y < 0 or n.x >= width or n.y >= height:
				return true
	return false


func _rim_edge(cell: Vector2i, at: Vector3) -> void:
	## what stands at the edge of the fields: mostly shrubs and hedgerow,
	## a boulder, a stretch of old fence, now and then a tree
	var r := RandomNumberGenerator.new()
	r.seed = hash(str(cell) + level_id + "rim")
	if str(def.get("rim", "")) != "":
		preload("res://scripts/world/TechDress.gd").rim(self, cell, at, str(def["rim"]), r)          # round 123: boulders and plate stacks at a tech region's edge
		return
	var roll := r.randf()
	var j := Vector3(r.randf_range(-0.4, 0.4), 0.0, r.randf_range(-0.4, 0.4))
	if roll < 0.42:
		_prop("nature-kit/plant_bushLarge.glb", at + j, r.randf_range(1.8, 2.6), r.randf() * TAU)
		if r.randf() < 0.5:
			_prop("nature-kit/plant_bush.glb", at - j * 1.5, r.randf_range(1.6, 2.2), r.randf() * TAU)
	elif roll < 0.62:
		_prop("nature-kit/rock_largeA.glb", at + j, r.randf_range(1.2, 1.8), r.randf() * TAU)
		_prop("nature-kit/plant_bush.glb", at - j, 1.8, r.randf() * TAU)
	elif roll < 0.82:
		# old fence along the edge, turned to run beside the open side
		var along := 0.0
		for d in [Vector2i(1, 0), Vector2i(-1, 0)]:
			if is_walkable_char(char_at(cell + d)):
				along = PI / 2
		_prop("fantasy-town-kit/fence-broken.glb" if r.randf() < 0.35 else "fantasy-town-kit/fence.glb", at, 2.0, along)
		_prop("nature-kit/plant_bush.glb", at + Vector3(j.x, 0, j.z) * 2.0, 1.5, r.randf() * TAU)
	else:
		var tv := _season_trees()
		var tree := "nature-kit/tree_oak.glb" if tv == "" else "nature-kit/tree_oak_%s.glb" % tv
		_prop(tree, at + j, 2.8, r.randf() * TAU)


func _auto_walls() -> void:
	## Seal every walkable edge that faces nothing. Runs after the map is
	## placed so it can see the whole grid.
	var done := {}
	for y in height:
		for x in width:
			var cell := Vector2i(x, y)
			var here := char_at(cell)
			if not is_walkable_char(here) and here != "S":
				continue
			for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n: Vector2i = cell + dir
				if char_at(n) == " " and not done.has(n):
					done[n] = true
					_wall(n)


func _floor_tile(cell: Vector2i, road: bool) -> void:
	var at := cell_to_world(cell)
	if theme == "settlement" and ground == "deck":
		var pl := _prop("fantasy-town-kit/planks.glb", at, 2.0, (_rng.randi() % 2) * PI / 2)
		if road and DisplayServer.get_name() != "headless":
			_tint(pl, Color(0.7, 0.62, 0.55))        # the boardwalks: older, darker wood
	elif theme == "settlement":
		if road:
			_road_cells[cell] = true
		else:
			_floor_cells[cell] = true
			if _rng.randf() < 0.07:
				_glow_mushroom(at)
			elif _rng.randf() < 0.08:
				var moss := ["nature-kit/grass.glb", "nature-kit/grass_leafs.glb", "nature-kit/mushroom_tan.glb"]
				_prop(moss[_rng.randi() % moss.size()], at + Vector3(_jit() * 2, 0.02, _jit() * 2), 2.0, _rng.randf() * TAU)
	elif is_outdoor():
		if road:
			_road_cells[cell] = true
		else:
			_floor_cells[cell] = true
			if _rng.randf() < 0.16 and str(def.get("deco", "")) != "none":
				var deco := ["nature-kit/flower_redA.glb", "nature-kit/flower_yellowA.glb", "nature-kit/flower_purpleA.glb", "nature-kit/grass.glb",
					"nature-kit/grass_large.glb", "nature-kit/plant_bushSmall.glb"]
				_prop(deco[_rng.randi() % deco.size()], at + Vector3(_jit() * 2, 0.02, _jit() * 2), 2.0, _rng.randf() * TAU)
	else:
		_floor_cells[cell] = true


func _build_ground() -> void:
	## One big invisible slab under the whole level -- walking happens on
	## this; the floor tiles are only looks.
	var size := Vector3(width * CELL + 8, 1.0, height * CELL + 8)
	_box_body(Vector3(width * CELL / 2.0, -0.5, height * CELL / 2.0), size)
	if theme == "settlement" and ground == "deck":
		# the lake: one dark, still surface under every deck and boardwalk
		var lake := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(width * CELL + 120, height * CELL + 120)
		lake.mesh = pm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.05, 0.13, 0.22)
		mat.roughness = 0.05
		mat.metallic = 0.3
		lake.material_override = mat
		lake.position = Vector3(width * CELL / 2.0, -0.08, height * CELL / 2.0)
		add_child(lake)


func _glow_mushroom(at: Vector3) -> void:
	## cave mushrooms that give off a soft blue-green light
	var kinds := ["nature-kit/mushroom_tanTall.glb", "nature-kit/mushroom_tanGroup.glb", "nature-kit/mushroom_redGroup.glb"]
	var m := _prop(kinds[_rng.randi() % kinds.size()], at + Vector3(_jit() * 3, 0.1, _jit() * 3), 3.2, _rng.randf() * TAU)
	var c := Color(0.45, 1.0, 0.85) if _rng.randf() < 0.7 else Color(0.7, 0.6, 1.0)
	_glow_tint(m, c)
	if _glows < MAX_GLOWS:
		_glows += 1
		var l := OmniLight3D.new()
		l.light_color = c
		l.omni_range = 3.5
		l.light_energy = 0.7
		l.position = m.position + Vector3(0, 0.6, 0)
		add_child(l)


func _glow_tint(n: Node, c: Color) -> void:
	if n is MeshInstance3D:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = c * 0.6
		mat.emission_enabled = true
		mat.emission = c
		mat.emission_energy_multiplier = 1.4
		n.material_override = mat
	for ch in n.get_children():
		_glow_tint(ch, c)


var _lamp_cells := []            # (round 75: lanterns wait until every road cell is known, then stand set back from the road)
var _lamps_flushed := false
var lantern_spots := []          # where the village's lanterns stand (world positions, for tests)
var dressing_spots := []         # where stalls and other dressing stand (world positions, for tests)


func on_road(p: Vector3, margin: float = CELL * 0.6) -> bool:
	## round 75 (Robert: "the roadway should be a no-drop zone unless it is very deliberate"): is this spot on a
	## road cell, or in its verge (the ground shader blurs the road's edge, so the margin is about 0.6 of a cell)?
	if _road_cells.is_empty():
		return false
	var c0 := world_to_cell(p)
	var reach := int(ceil(margin / CELL)) + 1
	var half := CELL * 0.5 + margin
	for dy in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			var c := c0 + Vector2i(dx, dy)
			if not _road_cells.has(c):
				continue
			var rc := cell_to_world(c)
			if absf(p.x - rc.x) <= half and absf(p.z - rc.z) <= half:
				return true
	return false


func nearest_road_cell(p: Vector3, within: int = 3) -> Vector2i:
	## the road cell nearest to this spot (within a few cells), or (-1, -1)
	var best := Vector2i(-1, -1)
	var bd := 1.0e9
	var c0 := world_to_cell(p)
	for dy in range(-within, within + 1):
		for dx in range(-within, within + 1):
			var c := c0 + Vector2i(dx, dy)
			if not _road_cells.has(c):
				continue
			var d := cell_to_world(c).distance_to(p)
			if d < bd:
				bd = d
				best = c
	return best


func _lamp_spot(cell: Vector2i) -> Vector3:
	## a lantern stands beside the road, not in it: of the spots a little way around its cell (the nearest first)
	## take one the road's verge doesn't reach and that isn't a wall or a road cell; failing that, the one furthest from the road
	var at := cell_to_world(cell)
	if nearest_road_cell(at, 2).x < 0:
		return at
	var step := CELL * 0.55
	var offs := [Vector3.ZERO, Vector3(step, 0, 0), Vector3(-step, 0, 0), Vector3(0, 0, step), Vector3(0, 0, -step),
		Vector3(step, 0, step), Vector3(-step, 0, step), Vector3(step, 0, -step), Vector3(-step, 0, -step)]
	var best := at
	var best_score := -1.0e9
	for o: Vector3 in offs:
		var to: Vector3 = at + o
		var tc := world_to_cell(to)
		if tc != cell and (not is_walkable_char(char_at(tc)) or _road_cells.has(tc)):
			continue
		var rc := nearest_road_cell(to, 3)
		var far: float = cell_to_world(rc).distance_to(to) if rc.x >= 0 else 99.0
		var score: float = far - o.length() * 0.01 + (100.0 if not on_road(to) else 0.0)
		if score > best_score:
			best_score = score
			best = to
	return best


func _place_lamps() -> void:
	_lamps_flushed = true
	for c in _lamp_cells:
		_light(c)
	_lamp_cells = []


func _light(cell: Vector2i) -> void:
	if (is_town() or theme == "wilds") and not _lamps_flushed:
		_lamp_cells.append(cell)
		return
	if str(def.get("lamp", "")) != "":
		preload("res://scripts/world/TechDress.gd").lamp(self, cell, str(def["lamp"]))          # round 123: arc lamps, floods, panels -- not the village lantern
		return
	var at := cell_to_world(cell)
	if is_town() or theme == "wilds":
		at = _lamp_spot(cell)
		lantern_spots.append(at)
		var lat := at
		_vis(lat, func():
			_prop("fantasy-town-kit/lantern.glb", lat, 1.6)
			var l := OmniLight3D.new()
			l.light_color = Color(1.0, 0.8, 0.5)
			l.omni_range = 9.0
			# lanterns burn brighter as the evening comes on (and in the village,
			# by day they're only a glow)
			var night := 1.0 - Game.daylight()
			l.light_energy = (0.35 + 1.6 * night) if is_outdoor() else (1.1 + 0.4 * night)
			l.position = lat + Vector3(0, 2.4, 0)
			add_child(l))
	else:
		# a dungeon torch hangs on the wall beside the passage -- not a post planted in the middle of it
		var args := {"color": look.get("torch", [1.0, 0.68, 0.35])}
		for d: Vector2i in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
			var wc: String = char_at(cell + d)
			if wc == "#" or wc == " ":
				at += Vector3(float(d.x), 0.0, float(d.y)) * (CELL * 0.5 - 0.22)
				args["wall"] = true
				args["dir"] = Vector2(float(d.x), float(d.y))
				break
		_spawn_script("res://scripts/objects/Torch.gd", at, args)
	_count("lights")


func _secret_wall(cell: Vector2i) -> void:
	_spawn_script("res://scripts/objects/SecretWall.gd", cell_to_world(cell), {"cell": cell})
	_count("secrets")


func _house_block(cell: Vector2i) -> void:
	_solid(cell)
	var at := cell_to_world(cell)
	var wood := (cell.x + cell.y) % 3 != 0
	_prop("fantasy-town-kit/wall-wood-block.glb" if wood else "fantasy-town-kit/wall-block.glb", at, 2.0)
	_prop("fantasy-town-kit/roof-gable.glb", at + Vector3(0, 2.0, 0), 2.0)
	_box_body(at + Vector3(0, 2.0, 0), Vector3(CELL, 4.0, CELL))
	_count("houses")


func _water(cell: Vector2i) -> void:
	_solid(cell)
	var at := cell_to_world(cell)
	var mi := MeshInstance3D.new()
	mi.mesh = _pond_mesh(cell)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.15, 0.35, 0.55, 0.85)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.1
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
	if reach_index(cell) >= 0:
		mi.material_override = preload("res://scripts/world/ReachDress.gd").water(self, cell, reach_biome(cell))
	mi.position = at + Vector3(0, 0.05, 0)
	add_child(mi)
	_box_body(at + Vector3(0, 1.5, 0), Vector3(CELL, 3.0, CELL))


func _is_water_char(ch: String) -> bool:
	return ch == "~" or ch == "&"


func _pond_mesh(cell: Vector2i) -> ArrayMesh:
	## a pond is not a stack of square tiles: every outer corner of the water is rounded off (a lone cell becomes a round pool)
	var h := CELL * 0.5
	var pts: Array[Vector2] = []
	var corners := [Vector2i(1, 1), Vector2i(-1, 1), Vector2i(-1, -1), Vector2i(1, -1)]      # walk round the square
	for cr: Vector2i in corners:
		var rounded: bool = not _is_water_char(char_at(cell + Vector2i(cr.x, 0))) and not _is_water_char(char_at(cell + Vector2i(0, cr.y)))
		if rounded:
			# the quarter circle is centred on the cell's own middle: radius h, so a lone cell is a circle
			var a0: float = atan2(float(cr.y), float(cr.x)) - PI / 4.0
			for k in range(7):
				var a: float = a0 + (PI / 2.0) * float(k) / 6.0
				pts.append(Vector2(cos(a), sin(a)) * h * 1.0)
		else:
			pts.append(Vector2(float(cr.x) * h, float(cr.y) * h))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(pts.size()):
		var p1: Vector2 = pts[i]
		var p2: Vector2 = pts[(i + 1) % pts.size()]
		for q: Vector2 in [Vector2.ZERO, p1, p2]:
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2(q.x / CELL + 0.5, q.y / CELL + 0.5))
			st.add_vertex(Vector3(q.x, 0.0, q.y))
	return st.commit()


func _banner(cell: Vector2i) -> void:
	var at := cell_to_world(cell)
	# face the banner toward the open side
	for dir in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
		var n: Vector2i = cell + dir
		if char_at(n) == "#" or char_at(n) == " ":
			var yaw := atan2(float(-dir.x), float(-dir.y))
			_prop("mini-dungeon/banner.glb", at, 2.0, yaw)
			return


func _spawn_script(script_path: String, at: Vector3, args: Dictionary) -> Node:
	var scr = load(script_path)
	if scr == null:
		warnings.append("missing script " + script_path)
		return null
	var n = scr.new()
	n.position = at
	if n.has_method("setup"):
		n.setup(self, args)
	add_child(n)
	return n


# ======================================================================
# environment
# ======================================================================

func _build_environment() -> void:
	var env := Environment.new()
	var amb: Array = def.get("ambient", [])
	if theme == "settlement":
		# a cavern town: no sky, warm lantern-light, a faint amber haze
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color(0.02, 0.025, 0.04)
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		var sc := Color(0.62, 0.57, 0.56)
		if amb.size() >= 3:
			sc = Color(float(amb[0]), float(amb[1]), float(amb[2]))
		env.ambient_light_color = sc
		env.ambient_light_energy = 1.25
		# the cavern roof is crusted with glowing fungus: a soft, cool,
		# shadowless light from above, like a moon that never moves
		var roof := DirectionalLight3D.new()
		roof.rotation_degrees = Vector3(-70, 20, 0)
		roof.light_color = Color(0.7, 0.85, 1.0)
		roof.light_energy = 0.55
		add_child(roof)
		env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
		env.fog_enabled = true
		env.fog_light_color = Color(0.35, 0.25, 0.15)
		env.fog_density = 0.006
		env.glow_enabled = true
		env.glow_intensity = 0.6
		_cave_vault(env, sc, Color(0.55, 0.9, 1.0), 1.4)    # the fungus-crusted roof of a cavern town
	elif is_outdoor():
		# the village keeps your own clock: morning light, a long gold dusk,
		# a blue night with every lantern lit (Game.daylight)
		var dl := Game.daylight()
		var dusk := clampf(1.0 - absf(dl - 0.5) * 2.0, 0.0, 1.0) if dl < 1.0 and dl > 0.0 else 0.0
		var sky := Sky.new()
		var sm := ProceduralSkyMaterial.new()
		sm.sky_top_color = Color(0.04, 0.06, 0.16).lerp(Color(0.35, 0.55, 0.85), dl)
		sm.sky_horizon_color = Color(0.1, 0.12, 0.22).lerp(Color(0.75, 0.82, 0.9), dl).lerp(Color(0.95, 0.6, 0.35), dusk * 0.7)
		sm.ground_horizon_color = Color(0.5, 0.55, 0.45) * (0.3 + 0.7 * dl)
		sky.sky_material = sm
		env.sky = sky
		# round 37: a living sky -- clouds drifting by day, stars and a moon by
		# night, a warm horizon at dusk (assets/shaders/sky.gdshader)
		var sky_shader = load("res://assets/shaders/sky.gdshader")
		if sky_shader:
			var shm := ShaderMaterial.new()
			shm.shader = sky_shader
			shm.set_shader_parameter("daylight", dl)
			shm.set_shader_parameter("dusk", dusk)
			var srng := RandomNumberGenerator.new()
			srng.seed = hash(Game.today() + level_id)              # each day its own weather
			shm.set_shader_parameter("cloud_cover", srng.randf_range(0.15, 0.85))
			var sky2 := Sky.new()
			sky2.sky_material = shm
			env.sky = sky2
			_sky_mat = shm
		env.background_mode = Environment.BG_SKY
		# a fixed, neutral fill light: sky-coloured ambient turned every
		# texture cyan (seen in the first screenshots)
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.4, 0.45, 0.65).lerp(Color(0.62, 0.6, 0.58), dl)
		env.ambient_light_energy = 0.3 + 0.25 * dl
		# ...and no sky reflections: the low-poly materials are glossy
		# enough that a blue sky mirrored in every flat surface
		env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
		var sun := DirectionalLight3D.new()
		sun.rotation_degrees = Vector3(-52, -35, 0) if dl >= 1.0 else Vector3(-18 - 30 * dl, -35, 0)
		sun.light_energy = 0.18 + 1.07 * dl         # at night it's the moon
		sun.light_color = Color(0.6, 0.7, 1.0).lerp(Color(1.0, 0.97, 0.92), dl).lerp(Color(1.0, 0.7, 0.45), dusk * 0.6)
		sun.shadow_enabled = true
		add_child(sun)
		sun_light = sun                # round 44: WorldFX moves it as the hours go by
		if _sky_mat:
			_sky_mat.set_shader_parameter("sun_dir", sun.transform.basis.z.normalized())
	else:
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color(0.02, 0.02, 0.03)
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		var c := Color(0.32, 0.29, 0.38)
		if amb.size() >= 3:
			c = Color(float(amb[0]), float(amb[1]), float(amb[2]))
		env.ambient_light_color = c
		env.ambient_light_energy = 1.7      # (textured stone drinks more light than the old flat tiles did)
		env.fog_enabled = true
		env.fog_light_color = c.darkened(0.6)
		env.fog_density = 0.0065
		_cave_vault(env, c, Color(0.45, 0.8, 1.0))      # round 37: rock overhead, not a void
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 6.0
	preload("res://scripts/core/Gfx.gd").tune_env(env, "village" if is_outdoor() else theme)      # the graphics preset's extras (Gfx.gd)
	if is_outdoor() and not (def.get("atmos", {}) as Dictionary).is_empty():
		apply_atmos(env)          # round 123: a tech place keeps its own sky and light, whatever the hour
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	_env = env
	_amb_base = env.ambient_light_energy
	_fog_base = env.fog_density


func apply_atmos(env: Environment = null) -> void:
	## round 123: the Ashen Moon is always a black sky with a bright earth in it; the Glass Desert always burns.
	## def.atmos {daylight, dusk, clouds, sun, sun_energy, ambient, ambient_energy, fog, fog_density}
	var a: Dictionary = def.get("atmos", {})
	if a.is_empty():
		return
	if env == null:
		env = _env
	if env == null:
		return
	if _sky_mat:
		_sky_mat.set_shader_parameter("daylight", float(a.get("daylight", 0.8)))
		_sky_mat.set_shader_parameter("dusk", float(a.get("dusk", 0.0)))
		_sky_mat.set_shader_parameter("cloud_cover", float(a.get("clouds", 0.3)))
	if sun_light:
		sun_light.light_color = Look.color3(a.get("sun", []), Color(1, 1, 1))
		sun_light.light_energy = float(a.get("sun_energy", 1.0))
		if a.has("sun_angle"):
			sun_light.rotation_degrees = Vector3(float(a["sun_angle"][0]), float(a["sun_angle"][1]), 0)
		if _sky_mat:
			_sky_mat.set_shader_parameter("sun_dir", sun_light.transform.basis.z.normalized())
	env.ambient_light_color = Look.color3(a.get("ambient", []), Color(0.5, 0.5, 0.55))
	env.ambient_light_energy = float(a.get("ambient_energy", 0.5))
	env.fog_enabled = true
	env.fog_light_color = Look.color3(a.get("fog", []), Color(0.6, 0.6, 0.7))
	env.fog_density = float(a.get("fog_density", 0.005))
	_amb_base = env.ambient_light_energy
	_fog_base = env.fog_density


func _ready() -> void:
	add_to_group("level")                     # round 42: so systems can find the place you're in
	_ensure_path_without_secrets()            # a player must never be stuck behind a secret wall
	_unplug_chests()                          # nor behind a chest or ore vein standing in a doorway
	_unplug_things()                          # nor behind a lore stone or lever standing in a one-cell corridor
	var wfx = preload("res://scripts/world/WorldFX.gd").new()     # round 44: the hour, the weather, the season
	wfx.setup(self)
	add_child(wfx)
	var hz = preload("res://scripts/world/Horizon.gd").new()      # round 48: the world past the edge of the map
	hz.setup(self)
	add_child(hz)
	if Game.audio:
		Game.audio.set_music(Game.audio.music_for(level_id, def))        # round 31: the place's music
	var Fog := preload("res://scripts/world/FogOfWar.gd")
	if Fog.wanted(self):
		var fog = Fog.new()                       # round 35: fog of war underground
		fog.setup(self)
		add_child(fog)
	# round 30: a world event, or the day's trial, says so as you arrive
	if not event.is_empty():
		var ec: Array = event.get("color", [1, 1, 1])
		var col := Color(float(ec[0]), float(ec[1]), float(ec[2]))
		Game.banner.emit.call_deferred(str(event.get("name", "")).to_upper(), col)
		Game.message.emit.call_deferred("%s -- %s" % [event.get("name", ""), event.get("desc", "")])
		if _env and str(event.get("id", "")) in ["blood_moon", "heavenly_sign", "spirit_tide"]:
			_env.ambient_light_color = _env.ambient_light_color.lerp(col, 0.45)
			_env.fog_light_color = _env.fog_light_color.lerp(col, 0.5)
	elif bool(def.get("final", false)):
		# round 33: the last floor
		Game.banner.emit.call_deferred("THE LAST FLOOR", Color(1.0, 0.6, 0.45))
		Game.message.emit.call_deferred("Past this floor's master lies the Heart of the Deep. Nothing is mapped beyond it -- not in this game.")
	elif bool(def.get("trial", false)):
		Game.banner.emit.call_deferred("THE DAILY TRIAL", Color(1.0, 0.85, 0.5))
		Game.message.emit.call_deferred("Clear every hall -- the master in the last one too. %s" % "; ".join(Game.trial_mod_names(Game.TrialGen.day_of(level_id))))
	if str(def.get("online", "")) != "":
		var ow = preload("res://scripts/net/OnlineWorld.gd").new()          # round 125: the people and foes of the shared world
		ow.setup(self)
		add_child(ow)
	if bool(def.get("breathing", false)):
		get_tree().create_timer(4.0).timeout.connect(func():
			if is_inside_tree():
				Game.message.emit("Under your feet the whole town rises... and, slowly, settles again."))


func _process(delta: float) -> void:
	if not _stream.is_empty():
		_stream_sort_t -= delta
		_stream_step(STREAM_MS * (3.0 if _stream.size() > 400 and _stream_sort_t > 1.0 else 1.0))
	if _stalactites:
		var cam := get_viewport().get_camera_3d()
		_stalactites.visible = cam != null and cam.global_position.y < WALL_H
	if bool(def.get("arena", false)):
		_watch_arena(delta)
	if _env == null or not bool(def.get("breathing", false)):
		return
	_breath_t += delta
	var b := sin(_breath_t * TAU / BREATH_SECONDS)
	_env.ambient_light_energy = _amb_base * (1.0 + 0.16 * b)
	_env.fog_density = _fog_base * (1.0 - 0.25 * b)


var _arena_t := 0.0
var _arena_done := false


func _watch_arena(delta: float) -> void:
	## The ring is clear: a moment for the crowd, then the next round.
	if _arena_done:
		return
	_arena_t += delta
	if _arena_t < 1.0:
		return
	if arena_foes_left() == 0:
		_arena_done = true
		Game.message.emit("The ring falls quiet.")
		get_tree().create_timer(1.5).timeout.connect(func(): Game.arena_cleared())


func arena_foes_left() -> int:
	var n := 0
	for e in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(e) and not e._dead and not bool(e.stats.get("passive", false)):
			n += 1
	return n


func breath() -> float:
	## (tools) where in its slow breath the place is, -1..1
	return sin(_breath_t * TAU / BREATH_SECONDS)


# ======================================================================
# used by the player, enemies and Main
# ======================================================================

func spawn_point(tag: String) -> Vector3:
	## Where to put the player: on a 'P', or next to the exit character
	## you came through (an exit's "arrive" names a character on THIS level).
	var cells: Array = spawns.get(tag, [])
	if cells.is_empty():
		cells = spawns.get("P", [])
	if cells.is_empty():
		for ch in spawns:
			if is_walkable_char(ch) and ch != " ":
				cells = spawns[ch]
				break
	if cells.is_empty():
		return Vector3(CELL, 1, CELL)
	var c: Vector2i = cells[0]
	if tag != "P" and tag != ".":
		# step off the exit so you don't bounce straight back through it
		for dir in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(1, 1), Vector2i(-1, 1)]:
			var n: Vector2i = c + dir
			if is_free(n):
				return cell_to_world(n) + Vector3(0, 0.6, 0)
	return cell_to_world(c) + Vector3(0, 0.6, 0)


func is_free(cell: Vector2i) -> bool:
	if not astar.region.has_point(cell):
		return false
	if astar.is_point_solid(cell):
		return false
	var ch := char_at(cell)
	return ch in [".", ",", "P", "L", "o", "h", "="]


func path_between(from_cell: Vector2i, to_cell: Vector2i) -> Array:
	if not astar.region.has_point(from_cell) or not astar.region.has_point(to_cell):
		return []
	if astar.is_point_solid(to_cell):
		return []
	return astar.get_id_path(from_cell, to_cell)


func open_cell(cell: Vector2i) -> void:
	## A secret wall opened: the cell becomes walkable for pathfinding too.
	if astar.region.has_point(cell):
		astar.set_point_solid(cell, false)


func display_name() -> String:
	return str(def.get("name", level_id))


# ======================================================================
# texture and detail (2026-10-02, Look.gd): real surfaces, clutter, light,
# drifting motes, little scenes and little creatures
# ======================================================================

const CLUTTER_CHANCE := 0.13
const MAX_FEATURE_LIGHTS := 18
var _feature_lights := 0


func _is_wallish(cell: Vector2i) -> bool:
	return _wall_cells.has(cell)


func _build_surfaces() -> void:
	## One mesh for every floor, one for every road, one for every wall --
	## a real textured surface instead of thousands of separate tiles.
	# round 56: a reach's ground and walls are its own land's, not the floor's
	var rfloor := []
	var rwall := []
	for i in _reach_rects.size():
		rfloor.append({})
		rwall.append({})
	if not _reach_rects.is_empty():
		for c in _floor_cells.keys():
			var ri := reach_index(c)
			if ri >= 0:
				rfloor[ri][c] = true
				_floor_cells.erase(c)
		for c2 in _wall_cells.keys():
			var ri2 := reach_index(c2)
			if ri2 >= 0:
				rwall[ri2][c2] = true
				_wall_cells.erase(c2)
	if is_outdoor():
		# round 63: under the sky the map's ground IS the land's ground (one
		# shader, world-space), and the roads are drawn into it with soft,
		# curving edges -- and run on out past the map (road mask)
		_build_road_mask()
		var plane := MeshInstance3D.new()
		plane.name = "OutdoorGround"
		var pm := PlaneMesh.new()
		pm.size = Vector2(width * CELL, height * CELL)
		pm.subdivide_width = mini(width, 64)
		pm.subdivide_depth = mini(height, 64)
		plane.mesh = pm
		plane.position = Vector3(width * CELL / 2.0, 0.02, height * CELL / 2.0)
		plane.material_override = preload("res://scripts/world/Horizon.gd").land_material(self)
		add_child(plane)
	elif not _floor_cells.is_empty():
		var spec: Array = look.get("floor", ["stony_dirt_path", [0.8, 0.8, 0.8], 3.0])
		add_child(_floor_mesh(_floor_cells, Look.surface(spec), 0.02))
	if not _road_cells.is_empty() and not is_outdoor():
		var rspec: Array = look.get("road", ["mossy_cobblestone", [0.8, 0.78, 0.74], 2.5])
		add_child(_floor_mesh(_road_cells, Look.surface(rspec), 0.035))
	if not _wall_cells.is_empty():
		var wspec: Array = look.get("wall", ["old_stone_wall", [0.75, 0.72, 0.7], 3.0])
		add_child(_wall_mesh(Look.surface(wspec), Look.surface(wspec, 0.32)))
	for i in _reach_rects.size():
		var rl: Dictionary = Look.LOOKS.get(str(_reach_biomes[i].get("look", "")), look)
		if not rfloor[i].is_empty():
			var m := _floor_mesh(rfloor[i], Look.surface(rl.get("floor", ["rock_face", [0.7, 0.7, 0.7], 3.0])), 0.02)
			m.name = "ReachFloor_%d" % i
			add_child(m)
		if not rwall[i].is_empty():
			var keep := _wall_cells
			_wall_cells = rwall[i]
			var wl: Array = rl.get("wall", ["rock_face", [0.7, 0.7, 0.7], 3.0])
			var wm := _wall_mesh(Look.surface(wl), Look.surface(wl, 0.32))
			wm.name = "ReachWalls_%d" % i
			add_child(wm)
			_wall_cells = keep
	# (everything else that asks about floor and walls sees the whole floor again)
	for i in _reach_rects.size():
		for c3 in rfloor[i]:
			_floor_cells[c3] = true
		for c4 in rwall[i]:
			_wall_cells[c4] = true
	if not is_outdoor() and theme != "settlement":
		_build_ceiling()


# ---- round 63: roads that curve, and lead somewhere -------------------------------------------

var road_mask: ImageTexture = null
var road_mask_rect := Rect2()
var roads_out := []            # [[Vector2 from, Vector2 to], ...] (for tests)


func _build_road_mask() -> void:
	## A picture of where the roads are (1 pixel a metre) over the map and the
	## land around it. The map's road cells, and from every road that meets
	## the map's edge a road that carries on out across the land, curving
	## gently, toward something -- the sect's pagoda on the ridge (Horizon), or
	## just over the hills -- fading out as it goes.
	var H := preload("res://scripts/world/Horizon.gd")
	var margin := float((H.config().get("land", {}) as Dictionary).get("margin", 230.0))
	var x0 := -margin
	var z0 := -margin
	var w := int(width * CELL + margin * 2.0)
	var h := int(height * CELL + margin * 2.0)
	var img := Image.create(w, h, false, Image.FORMAT_L8)
	for c in _road_cells:
		var px := int(c.x * CELL - x0)
		var pz := int(c.y * CELL - z0)
		img.fill_rect(Rect2i(px, pz, int(CELL), int(CELL)), Color(1, 1, 1))
	# where roads leave the map
	var exits := []
	var reach := 9                     # a road that ends this close to the edge goes on out
	for c in _road_cells:
		var edge_d := mini(mini(c.x, width - 1 - c.x), mini(c.y, height - 1 - c.y))
		if edge_d > reach:
			continue
		var side := "n"
		var out_v := Vector2i(0, -1)
		if edge_d == c.y:
			side = "n"
		elif edge_d == height - 1 - c.y:
			side = "s"
			out_v = Vector2i(0, 1)
		elif edge_d == c.x:
			side = "w"
			out_v = Vector2i(-1, 0)
		else:
			side = "e"
			out_v = Vector2i(1, 0)
		if _road_cells.has(c + out_v):
			continue                   # (not the road's end on that side)
		exits.append([c, side])
	var seen := {}
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(level_id + "roads")
	var tower := Vector2(width * CELL * float((H.config().get("tower", {}) as Dictionary).get("across", 0.65)),
		-float((H.config().get("tower", {}) as Dictionary).get("ahead", 120.0)))
	for e in exits:
		var c: Vector2i = e[0]
		var side: String = e[1]
		# one road per stretch of edge (neighbouring road cells are the same road)
		var key := "%s:%d" % [side, int((c.x if side in ["n", "s"] else c.y) / 10)]
		if seen.has(key):
			continue
		seen[key] = true
		var dir := {"n": Vector2(0, -1), "s": Vector2(0, 1), "w": Vector2(-1, 0), "e": Vector2(1, 0)}[side] as Vector2
		var p := Vector2(c.x * CELL + CELL / 2.0, c.y * CELL + CELL / 2.0)
		# the road runs straight on to the map's edge first (so it doesn't stop short)
		var edge_pt := p
		while edge_pt.x > 0.0 and edge_pt.y > 0.0 and edge_pt.x < width * CELL and edge_pt.y < height * CELL:
			edge_pt += dir * 1.0
			var cc := Vector2i(int(edge_pt.x / CELL), int(edge_pt.y / CELL))
			if not is_walkable_char(char_at(cc)) and char_at(cc) != " " and not _road_cells.has(cc):
				break
			img.fill_rect(Rect2i(int(edge_pt.x - x0) - 1, int(edge_pt.y - z0) - 1, 3, 3), Color(1, 1, 1))
		p = edge_pt
		var goal := p + dir * rng.randf_range(150.0, 210.0) + dir.orthogonal() * rng.randf_range(-60.0, 60.0)
		if side == "n" and absf(tower.x - p.x) < width * CELL:
			goal = tower                         # the north road climbs toward the pagoda
		var heading := dir.angle()
		var length := p.distance_to(goal)
		var steps := int(length / 1.5)
		var start := p
		for i in steps:
			var want := (goal - p).angle()
			var turn := wrapf(want - heading, -PI, PI)
			heading += clampf(turn, -0.06, 0.06) + rng.randf_range(-0.05, 0.05)
			p += Vector2.from_angle(heading) * 1.5
			var fade := 1.0 - smoothstep(0.6, 1.0, float(i) / float(steps))
			var px2 := int(p.x - x0)
			var pz2 := int(p.y - z0)
			for dz in range(-2, 3):
				for dx in range(-2, 3):
					var d2 := dx * dx + dz * dz
					if d2 > 5:
						continue
					var xx := px2 + dx
					var zz := pz2 + dz
					if xx < 0 or zz < 0 or xx >= w or zz >= h:
						continue
					var v := fade * (1.0 if d2 <= 2 else 0.6)
					if img.get_pixel(xx, zz).r < v:
						img.set_pixel(xx, zz, Color(v, v, v))
		roads_out.append([start, p])
	road_mask = ImageTexture.create_from_image(img)
	road_mask_rect = Rect2(x0, z0, w, h)


func _cave_vault(env: Environment, tint: Color, glow: Color, glow_amount: float = 0.8) -> void:
	## the far roof of the deep, behind everything above the walls (cave_sky.gdshader)
	var sh = load("res://assets/shaders/cave_sky.gdshader")
	if sh == null:
		return
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("rock_tint", Color(tint.r * 0.6, tint.g * 0.57, tint.b * 0.57))
	m.set_shader_parameter("glow_tint", glow)
	m.set_shader_parameter("glow_amount", glow_amount)
	var sky := Sky.new()
	sky.sky_material = m
	env.sky = sky
	env.background_mode = Environment.BG_SKY
	env.fog_sky_affect = 0.25
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED     # (no rock mirrored in every stone)
	_sky_mat = m


func _build_ceiling() -> void:
	## Round 37 (Robert: "a sky or ceiling ... more texture"): underground,
	## rock overhead. One mesh over every open cell, at the top of the walls,
	## facing DOWN -- so from below (close cameras, first person) it's a rough
	## stone roof hung with stalactites, and from the far camera above it's
	## invisible (its back is culled) and never hides the floor.
	var cells := []
	for y in grid.size():
		var row: String = grid[y]
		for x in row.length():
			if row[x] != "#" and row[x] != " ":
				cells.append(Vector2i(x, y))
	if cells.is_empty():
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h := WALL_H
	for c in cells:
		var x0: float = c.x * CELL
		var z0: float = c.y * CELL
		var pts := [Vector3(x0, h, z0), Vector3(x0 + CELL, h, z0), Vector3(x0 + CELL, h, z0 + CELL), Vector3(x0, h, z0 + CELL)]
		for i in [0, 2, 1, 0, 3, 2]:
			st.set_normal(Vector3.DOWN)
			st.set_uv(Vector2(pts[i].x, pts[i].z) / CELL)
			st.add_vertex(pts[i])
	st.generate_tangents()
	var mi := MeshInstance3D.new()
	mi.name = "Ceiling"
	mi.mesh = st.commit()
	var cspec: Array = look.get("wall", ["rock_face", [0.6, 0.58, 0.56], 3.0])
	var m: StandardMaterial3D = (Look.surface(["rock_face", cspec[1], 3.5], 0.55) as StandardMaterial3D).duplicate()
	m.cull_mode = BaseMaterial3D.CULL_BACK
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	_count("ceiling")
	# stalactites, hanging here and there over open floor
	if DisplayServer.get_name() == "headless":
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("ceiling|" + level_id)
	var n := mini(cells.size() / 18, 160)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var cone := CylinderMesh.new()
	cone.top_radius = 0.16
	cone.bottom_radius = 0.0
	cone.height = 0.45
	cone.radial_segments = 7
	cone.rings = 2
	cone.cap_top = false
	cone.cap_bottom = false
	cone.material = m
	mm.mesh = cone
	mm.instance_count = n
	for i in n:
		var c: Vector2i = cells[rng.randi() % cells.size()]
		var sc := rng.randf_range(0.45, 1.1)
		var at := cell_to_world(c) + Vector3(rng.randf_range(-0.8, 0.8), h - 0.225 * sc, rng.randf_range(-0.8, 0.8))
		mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sc, sc, sc)), at))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Stalactites"
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	_stalactites = mmi


func _corner_shade(cells: Dictionary, x: int, y: int) -> float:
	## Floor corners that touch walls are a little darker (cheap ambient
	## occlusion: the room's edges sink into shadow).
	var n := 0
	for c in [Vector2i(x - 1, y - 1), Vector2i(x, y - 1), Vector2i(x - 1, y), Vector2i(x, y)]:
		if _wall_cells.has(c) or (not cells.has(c) and not _road_cells.has(c) and not _floor_cells.has(c)):
			n += 1
	return 1.0 - 0.17 * n


func _floor_mesh(cells: Dictionary, mat: Material, y: float) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for c in cells:
		var cell: Vector2i = c
		var x0 := cell.x * CELL
		var z0 := cell.y * CELL
		var pts := [Vector3(x0, y, z0), Vector3(x0 + CELL, y, z0), Vector3(x0 + CELL, y, z0 + CELL), Vector3(x0, y, z0 + CELL)]
		var sh := [_corner_shade(cells, cell.x, cell.y), _corner_shade(cells, cell.x + 1, cell.y),
			_corner_shade(cells, cell.x + 1, cell.y + 1), _corner_shade(cells, cell.x, cell.y + 1)]
		for i in [0, 1, 2, 0, 2, 3]:
			st.set_normal(Vector3.UP)
			st.set_color(Color(sh[i], sh[i], sh[i]))
			st.set_uv(Vector2(pts[i].x, pts[i].z) / CELL)
			st.add_vertex(pts[i])
	st.generate_tangents()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _with_vertex_color(mat)
	return mi


func _with_vertex_color(mat: Material) -> Material:
	var m: StandardMaterial3D = (mat as StandardMaterial3D).duplicate()
	m.vertex_color_use_as_albedo = true
	return m


func _wall_mesh(side_mat: Material, top_mat: Material) -> Node3D:
	var sides := SurfaceTool.new()
	sides.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tops := SurfaceTool.new()
	tops.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h := WALL_H
	for c in _wall_cells:
		var cell: Vector2i = c
		var x0 := cell.x * CELL
		var z0 := cell.y * CELL
		var x1 := x0 + CELL
		var z1 := z0 + CELL
		# the top: dark rock, seen from the high camera
		for v in [Vector3(x0, h, z0), Vector3(x1, h, z0), Vector3(x1, h, z1), Vector3(x0, h, z0), Vector3(x1, h, z1), Vector3(x0, h, z1)]:
			tops.set_normal(Vector3.UP)
			tops.set_color(Color.WHITE)
			tops.set_uv(Vector2(v.x, v.z) / CELL)
			tops.add_vertex(v)
		# a side wherever this wall faces something that isn't wall
		for dir in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
			var n: Vector2i = cell + dir
			if _wall_cells.has(n) or char_at(n) == " ":
				continue
			var a: Vector3
			var b: Vector3
			match dir:
				Vector2i(0, -1):
					a = Vector3(x1, 0, z0); b = Vector3(x0, 0, z0)
				Vector2i(1, 0):
					a = Vector3(x1, 0, z1); b = Vector3(x1, 0, z0)
				Vector2i(0, 1):
					a = Vector3(x0, 0, z1); b = Vector3(x1, 0, z1)
				_:
					a = Vector3(x0, 0, z0); b = Vector3(x0, 0, z1)
			var nrm := Vector3(dir.x, 0, dir.y)
			var up := Vector3(0, h, 0)
			# darker at the foot of the wall, lighter where the torchlight reaches
			var lo := Color(0.78, 0.78, 0.78)
			var hi := Color.WHITE
			# (wound clockwise as seen from the floor side: that's Godot's front face)
			for pv in [[b, lo], [a, lo], [a + up, hi], [b, lo], [a + up, hi], [b + up, hi]]:
				sides.set_normal(nrm)
				sides.set_color(pv[1])
				var vv: Vector3 = pv[0]
				sides.set_uv(Vector2(vv.x + vv.z, vv.y) / CELL)
				sides.add_vertex(vv)
	sides.generate_tangents()
	tops.generate_tangents()
	var root := Node3D.new()
	root.name = "Walls"
	var ms := MeshInstance3D.new()
	ms.mesh = sides.commit()
	ms.material_override = _with_vertex_color(side_mat)
	root.add_child(ms)
	var mt := MeshInstance3D.new()
	mt.mesh = tops.commit()
	mt.material_override = top_mat
	root.add_child(mt)
	return root


func wall_block() -> Node3D:
	## One wall cell on its own (a secret wall must look like the rest).
	var root := Node3D.new()
	var spec: Array = look.get("wall", ["old_stone_wall", [0.75, 0.72, 0.7], 3.0])
	var bm := BoxMesh.new()
	bm.size = Vector3(CELL, WALL_H, CELL)
	var mi := MeshInstance3D.new()
	mi.mesh = bm
	mi.material_override = Look.surface(spec)
	mi.position = Vector3(0, WALL_H / 2.0, 0)
	root.add_child(mi)
	return root


func floor_patch() -> Node3D:
	## One floor cell on its own (where a secret wall used to be).
	var spec: Array = look.get("floor", ["stony_dirt_path", [0.8, 0.8, 0.8], 3.0])
	var pm := PlaneMesh.new()
	pm.size = Vector2(CELL, CELL)
	var mi := MeshInstance3D.new()
	mi.mesh = pm
	mi.material_override = Look.surface(spec)
	mi.position = Vector3(0, 0.02, 0)
	return mi


func _dress() -> void:
	## What makes a place feel lived-in (or died-in): clutter along the
	## walls, glowing things, drifting motes, little scenes, little lives.
	if bool(def.get("arena", false)) or bool(def.get("tribulation", false)):
		return          # (a ring, or the inside of your own head: nothing else in it)
	if not is_town() and theme != "wilds":
		_scatter_clutter()
		_pt("  clutter")
		_glow_features()
		_pt("  glowfeat")
		for i in _reach_rects.size():         # round 56: each reach's own light, through its ground
			var rc: Array = _floor_cells.keys().filter(func(c): return char_at(c) == "." and reach_index(c) == i)
			rc.sort()
			preload("res://scripts/world/ReachDress.gd").glows(self, rc, _reach_biomes[i])
		var gd = preload("res://scripts/world/GroundDetail.gd").new()      # round 52: puddles, moss, grit, cobwebs
		gd.setup(self)
		add_child(gd)
		_pt("  grounddetail")
	add_child(_motes())
	_pt("  motes")
	for r in reaches:                       # round 56: each reach's own air, and the change walking in
		var z = preload("res://scripts/world/ReachZone.gd").new()
		z.setup(self, r)
		add_child(z)
	_place_vignettes()
	_pt("  vignettes")
	_place_critters()
	_pt("  critters")
	if Game.sys("menagerie") != null:
		_pt("  zones")
		Game.sys("menagerie").place(self)          # round 141b: wild beasts of the floor, wayfarers waiting in town
	_pt("  menagerie")
	if Game.sys("pull") != null:
		Game.sys("pull").place(self)               # round 152: an omen, now and then
	_pt("  pull")
	if is_town():
		_town_life()
		_pt("  townlife")
	if level_id == "village":
		_place_home()


func _wall_neighbor(cell: Vector2i) -> Vector2i:
	var x := cell.x
	var y := cell.y
	var width := self.width
	var height := self.height

	# Check left neighbor
	if x > 0 and char_at(Vector2i(x - 1, y)) in WALKABLE:
		return Vector2i(x - 1, y)

	# Check right neighbor
	if x < width - 1 and char_at(Vector2i(x + 1, y)) in WALKABLE:
		return Vector2i(x + 1, y)

	# Check above neighbor
	if y > 0 and char_at(Vector2i(x, y - 1)) in WALKABLE:
		return Vector2i(x, y - 1)

	# Check below neighbor
	if y < height - 1 and char_at(Vector2i(x, y + 1)) in WALKABLE:
		return Vector2i(x, y + 1)

	return cell  # No walkable neighbor found


func _scatter_clutter() -> void:
	var table0: Array = look.get("clutter", [])
	for c in _floor_cells:
		var cell: Vector2i = c
		if char_at(cell) != ".":
			continue
		var wd := _wall_neighbor(cell)
		if wd == Vector2i.ZERO or _rng.randf() >= CLUTTER_CHANCE:
			continue
		# round 56: along a reach's walls, that land's own clutter
		var table: Array = table0
		var ri := reach_index(cell)
		if ri >= 0:
			table = Look.LOOKS.get(str(_reach_biomes[ri].get("look", "")), {}).get("clutter", table0)
		if table.is_empty():
			continue
		var total := 0
		for row0 in table:
			total += int(row0[2])
		var pick := _rng.randi() % maxi(total, 1)
		var row: Array = table[0]
		for r in table:
			pick -= int(r[2])
			if pick < 0:
				row = r
				break
		var at := cell_to_world(cell) + Vector3(wd.x, 0, wd.y) * (CELL * 0.3) + Vector3(_jit(), 0, _jit())
		if on_road(at):
			continue                   # (round 75: the roadway is a no-drop zone)
		dressing_spots.append(at)
		var cpath := str(row[0])
		var cscale := float(row[1]) * _rng.randf_range(0.85, 1.15)
		var cyaw := _rng.randf() * TAU
		var stab := Vector3.ZERO
		if cpath.contains("weapon-"):
			stab = Vector3(deg_to_rad(_rng.randf_range(70, 100)), _rng.randf() * TAU, 0)   # stuck in the ground
		_vis(at, func():
			var p := _prop(cpath, at, cscale, cyaw)
			if stab != Vector3.ZERO:
				p.rotation = stab
				p.position.y = 0.5
			if bool(look.get("crystals", false)) and cpath.contains("stone_tall") and DisplayServer.get_name() != "headless":
				_glow_tint(p, Look.color3(look.get("glow", []), Color(0.5, 0.8, 1.0))))
		_count("clutter")


func _feature_light(at: Vector3, c: Color, energy: float, rng: float) -> void:
	if _feature_lights >= MAX_FEATURE_LIGHTS:
		return
	_feature_lights += 1
	var l := OmniLight3D.new()
	l.light_color = c
	l.light_energy = energy
	l.omni_range = rng
	l.position = at
	add_child(l)


func _glow_features() -> void:
	## Each region's own light: ember cracks in the forges, glowing fungus
	## in the deeps, crystal light, runes in the old sanctums.
	if not look.has("glow"):
		return
	var gc := Look.color3(look.get("glow", []), Color(1, 1, 1))
	var cells: Array = _floor_cells.keys().filter(func(c): return char_at(c) == "." and reach_index(c) < 0)
	if cells.is_empty():
		return
	var n := mini(cells.size() / 40 + 3, 24)
	for i in n:
		var cell: Vector2i = cells[_rng.randi() % cells.size()]
		var at := cell_to_world(cell) + Vector3(_jit() * 2, 0, _jit() * 2)
		match look_key:
			"forge", "dragonspine":
				var crack := MeshInstance3D.new()
				var bm := BoxMesh.new()
				bm.size = Vector3(_rng.randf_range(0.6, 1.6), 0.02, _rng.randf_range(0.06, 0.14))
				crack.mesh = bm
				crack.material_override = _emissive(gc, 3.0)
				crack.position = at + Vector3(0, 0.04, 0)
				crack.rotation.y = _rng.randf() * TAU
				add_child(crack)
				_feature_light(at + Vector3(0, 0.4, 0), gc, 0.9, 3.0)
			"fungal":
				_glow_mushroom(at)
			_:
				var rune := MeshInstance3D.new()
				var cm := CylinderMesh.new()
				cm.top_radius = _rng.randf_range(0.25, 0.5)
				cm.bottom_radius = cm.top_radius
				cm.height = 0.01
				cm.radial_segments = 6 if look_key == "sanctum" else 12
				rune.mesh = cm
				rune.material_override = _emissive(gc, 1.6)
				rune.position = at + Vector3(0, 0.04, 0)
				add_child(rune)
				_feature_light(at + Vector3(0, 0.5, 0), gc, 0.7, 3.0)
		_count("glows")


func _emissive(c: Color, e: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c * 0.5
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = e
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


func _motes() -> Node3D:
	var m = preload("res://scripts/fx/Motes.gd").new()
	m.kind = str(look.get("motes", ""))
	m.tint = Look.color3(look.get("glow", look.get("torch", [])), Color(1, 0.9, 0.7))
	return m


func _free_area_cells(min_free: int = 9) -> Array:
	## Floor cells with open floor all around them -- room for a little scene.
	var out := []
	for c in _floor_cells:
		var cell: Vector2i = c
		if char_at(cell) != ".":
			continue
		var free := 0
		for dy in [-1, 0, 1]:
			for dx in [-1, 0, 1]:
				if char_at(cell + Vector2i(dx, dy)) == ".":
					free += 1
		if free >= min_free:
			out.append(cell)
	out.sort()
	return out


## which lost workshop a region's floors hide (Robert, 2026-10-02: "lost
## remnants of smiths, labs from alchemy etc.")
const WORKSHOP_FOR := {"warrens": "smithy", "forge": "smithy", "swordgrave": "smithy", "starmine": "smithy", "dragonspine": "smithy",
	"clockwork": "smithy", "drowned": "alchemy_lab", "ash": "alchemy_lab", "storm": "alchemy_lab", "ghostmarket": "alchemy_lab",
	"crypt": "apothecary", "cloudruins": "apothecary", "frost": "apothecary", "silk": "apothecary",
	"sanctum": "jeweler", "barrows": "jeweler", "crystal": "jeweler", "mirror": "jeweler",
	"grove": "herb_garden", "canopy": "herb_garden", "fungal": "herb_garden"}
const LEGACY_FLOORS := 10      # a workshop master waits on every dungeon floor this high up


func _place_vignettes() -> void:
	var kinds: Array = look.get("vignettes", []).duplicate()
	if is_town():
		return
	if kinds.is_empty() and (Game.sys("legacies") == null or str(Game.sys("legacies").craft_master_on(level_id)) in ["", "*"]):
		return          # (a floor with no little scenes -- unless this game's craft master waits here)
	var shop := str(WORKSHOP_FOR.get(look_key, "alchemy_lab"))
	var legacy_here := Game.depth >= 1 and Game.depth <= LEGACY_FLOORS
	# round 51: which craft master waits where is this game's own (Legacies.gd);
	# the workshop he sits in is his craft's
	var L = Game.sys("legacies")
	var rng_keep := _rng.state
	if L:
		var craft: String = L.craft_master_on(level_id)
		if craft != "*":
			legacy_here = craft != ""
			if legacy_here:
				shop = str(SHOP_OF.get(craft, shop))
		_rng.seed = hash("%s|%d|scenes" % [level_id, int(L.seed_v)])      # the little scenes move too, game to game
	kinds.insert(0, shop)
	var spots := _free_area_cells()
	if spots.is_empty():
		if L:
			_rng.state = rng_keep
		return
	var n := clampi(int(_floor_cells.size() / 260) + 2, 2, 5)
	var used: Array[Vector2i] = []
	var tries := 0
	while used.size() < n and tries < 60:
		tries += 1
		var cell: Vector2i = spots[_rng.randi() % spots.size()]
		var near := false
		for u in used:
			if absi(u.x - cell.x) + absi(u.y - cell.y) < 12:
				near = true
		for ch in ["P", "<", ">"]:
			for sc in spawns.get(ch, []):
				if absi(sc.x - cell.x) + absi(sc.y - cell.y) < 5:
					near = true
		for e in def.get("extras", []):           # a side chamber has its own wonder
			if absi(int(e["cell"][0]) - cell.x) + absi(int(e["cell"][1]) - cell.y) < 9:
				near = true
		if near:
			continue
		used.append(cell)
		var i := used.size() - 1
		_spawn_script("res://scripts/fx/Vignette.gd", cell_to_world(cell), {"cell": cell, "kind": str(kinds[i % kinds.size()]),
			"look": look_key, "seed": _rng.randi(), "index": i, "legacy": legacy_here and i == 0})
		_count("vignettes")
	if L:
		_rng.seed = hash(level_id)
		_rng.state = rng_keep


const SHOP_OF := {"smithing": "smithy", "alchemy": "alchemy_lab", "medicine": "apothecary", "jewelcrafting": "jeweler", "herbalism": "herb_garden"}
var _pending_legacies := []


func _place_legacies() -> void:
	## round 51 (Robert: "make sure major inheritance isn't something easy to
	## find"): each major this floor's map names sits this game in a far
	## corner or a sealed chamber (or where the maker put it) -- or isn't here
	## yet, asleep until you're strong enough; and a heavenly inheritance, if
	## this game put one on this floor
	var L = Game.sys("legacies")
	if L == null:
		return
	for row in _pending_legacies:
		var ch := str(row[0])
		var home: Vector2i = row[1]
		if not L.major_present(level_id, ch):
			_count("legacies_sleeping")
			continue
		var at: Vector2i = L.pick_spot(self, ch, home)
		if at != home:
			astar.set_point_solid(home, false)
		_spawn_script("res://scripts/objects/Inheritance.gd", cell_to_world(at), {"cell": at, "key_cell": home, "def": row[2], "tier": "major"})
		_count("inheritances")
	_pending_legacies = []
	if bool(def.get("arena", false)) or bool(def.get("tribulation", false)) or is_town():
		return
	var h: Dictionary = L.heavenly_on(level_id)
	if not h.is_empty():
		var hc: Vector2i = L.pick_spot(self, "heaven", Vector2i(-1, -1))
		if hc.x >= 0:
			_spawn_script("res://scripts/objects/Inheritance.gd", cell_to_world(hc), {"cell": hc, "def": L.heavenly_def(h, int(def.get("depth", Game.depth))), "tier": "heavenly",
				"key": L.heaven_key(str(h.get("id", "")))})
			_count("heavenly")


func place_quests(only_qid: String = "") -> void:
	## round 52: things a side quest sent you to find, and named foes to hunt --
	## each somewhere out of the way on this floor, marked with a gold diamond
	var Q = Game.sys("quests")
	if Q == null or is_town() or bool(def.get("arena", false)):
		return
	var L = Game.sys("legacies")
	for sp in Q.spawns_for(level_id):
		if only_qid != "" and str(sp["qid"]) != only_qid:
			continue
		var salt := "quest|%s|%s|%d" % [sp["qid"], sp["kind"], int(sp["index"])]
		var at: Vector2i = L.pick_spot(self, salt, Vector2i(-1, -1)) if L else Vector2i(-1, -1)
		if at.x < 0:
			var free := _free_area_cells(5)
			if free.is_empty():
				continue
			at = free[absi(hash(salt)) % free.size()]
		if str(sp["kind"]) == "find":
			_spawn_script("res://scripts/objects/QuestObject.gd", cell_to_world(at), {"cell": at, "qid": sp["qid"], "item": sp["item"], "what": sp["what"], "look": sp["look"]})
			_count("quest_finds")
		else:
			_quest_hunt(sp, at)
			_count("quest_hunts")


func _quest_hunt(sp: Dictionary, at: Vector2i) -> void:
	## a named foe: this floor's toughest kind (or the one named), made worse
	var best := str(sp.get("type", "strongest"))
	if best == "strongest" or not Game.enemies.has(best):
		var hp_best := -1
		best = ""
		for eid in Game.enemies:
			var st: Dictionary = Game.enemies[eid]
			if bool(st.get("passive", false)) or bool(st.get("boss", false)) or int(st.get("floor", -1)) != int(def.get("depth", Game.depth)):
				continue
			if int(st.get("hp", 0)) > hp_best:
				hp_best = int(st.get("hp", 0))
				best = str(eid)
		if best == "":
			best = "goblin_brute"
	var e = load("res://scripts/actors/Enemy.gd").new()
	e.setup(self, {"type": best, "cell": at})
	e.stats = (e.stats as Dictionary).duplicate()
	e.stats["name"] = str(sp.get("name", "a named foe"))
	e.stats["hp"] = int(float(e.stats.get("hp", 30)) * float(sp.get("hp_mult", 3.0)))
	e.hp = int(e.stats["hp"])
	e.stats["boss"] = true            # (a name across the top of the screen while you're near it)
	e.set_meta("quest_hunt", str(sp["qid"]))
	add_child(e)
	e.position = cell_to_world(at)          # (round 57: the level may not be in the tree yet -- global_position put it at the origin)
	preload("res://scripts/objects/QuestObject.gd").marker(e, 2.6 * float(e.stats.get("scale", 1.0)) + 0.6).visible = true
	var qid := str(sp["qid"])
	e.tree_exiting.connect(func():
		if is_instance_valid(e) and bool(e.get("_dead")) and Game.sys("quests"):
			Game.sys("quests").hunted(qid))


func _place_valley() -> void:
	## round 24: the valley's sect halls and towers; a tower floor's trial and
	## its stair up; and, in the village, the road out to the valley
	for s in def.get("sects", []):
		var c: Array = s.get("cell", [0, 0])
		var cell := Vector2i(int(c[0]), int(c[1]))
		_spawn_script("res://scripts/world/SectHall.gd", cell_to_world(cell), {"cell": cell, "id": str(s.get("id", "")), "element": str(s.get("element", "earth"))})
		_count("sects")
	for t in def.get("towers", []):
		var c2: Array = t.get("cell", [0, 0])
		var cell2 := Vector2i(int(c2[0]), int(c2[1]))
		_spawn_script("res://scripts/world/TowerSpire.gd", cell_to_world(cell2), {"cell": cell2, "id": str(t.get("id", "")), "tier": int(t.get("tier", 1)),
			"radius": int(t.get("radius", 3)), "door": t.get("door", [])})
		_count("towers")
	if def.has("up_cell"):
		var u: Array = def["up_cell"]
		spawns["up"] = [Vector2i(int(u[0]), int(u[1]))]
	if def.get("tower", {}) is Dictionary and not def.get("tower", {}).is_empty():
		var ce: Array = def.get("centre", [width / 2, height / 2])
		var cc := Vector2i(int(ce[0]), int(ce[1]))
		_spawn_script("res://scripts/world/TowerTrial.gd", cell_to_world(cc), {"cell": cc, "tower": def["tower"]})
	for gr in def.get("grounds", []):
		_ground_sign(gr)
	if level_id == "village":
		var gate := valley_gate_cell()
		if gate.x >= 0:
			spawns["@valley"] = [gate]
			_spawn_script("res://scripts/objects/Exit.gd", cell_to_world(gate), {"cell": gate, "to": "valley", "arrive": "<",
				"label": "The valley road", "down": false, "style": "road"})


func _ground_sign(gr: Dictionary) -> void:
	## round 150: a hunting or gathering ground is named where you arrive at it (seen from about 45 m)
	var c := Vector2i(int(gr["cell"][0]), int(gr["cell"][1]))
	var kind := str(gr.get("kind", "hunt"))
	var sub := {"hunt": "Hunting ground", "herbs": "Gathering ground: herbs", "ore": "Gathering ground: ore and stone", "reeds": "Fishing reeds"}
	var lb := Label3D.new()
	lb.text = "%s\n%s" % [I18n.t(str(gr.get("name", I18n.t("The grounds")))), I18n.t(str(sub.get(kind, I18n.t("Hunting ground"))))]
	lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lb.pixel_size = 0.014
	lb.font_size = 42
	lb.outline_size = 8
	lb.modulate = {"hunt": Color(1.0, 0.7, 0.45), "herbs": Color(0.6, 1.0, 0.6), "ore": Color(0.8, 0.85, 1.0), "reeds": Color(0.6, 0.9, 1.0)}.get(kind, Color.WHITE)
	lb.visibility_range_end = 45.0
	add_child(lb)
	lb.position = cell_to_world(c) + Vector3(0, 4.0, 0)


func valley_gate_cell() -> Vector2i:
	## the village's road out: the southern-most open cell near the column
	## you start in (the village map is Dev's -- this only reads it)
	var p: Array = spawns.get("P", [Vector2i(width / 2, height / 2)])
	var px: int = p[0].x
	for y in range(height - 1, -1, -1):
		for dx in [0, -1, 1, -2, 2, -3, 3, -4, 4]:
			var c := Vector2i(px + dx, y)
			if char_at(c) in [".", ","]:
				return c
	return Vector2i(-1, -1)


func _place_extras() -> void:
	## the wonders in Expanse's side chambers (Wonder.gd)
	for e in def.get("extras", []):
		if not (e is Dictionary):
			continue
		var c: Array = e.get("cell", [0, 0])
		var cell := Vector2i(int(c[0]), int(c[1]))
		if str(e.get("kind", "")) == "rival":
			var rs: Array = Game.valley_rivals()
			var ri := int(e.get("index", 0))
			if ri < rs.size():
				_spawn_script("res://scripts/actors/Rival.gd", cell_to_world(cell), {"cell": cell, "rival": rs[ri]})
				_count("rivals")
			continue
		if str(e.get("kind", "")) == "reach_heart":
			_spawn_script("res://scripts/world/ReachHeart.gd", cell_to_world(cell), {"cell": cell, "biome": str(e.get("biome", "")), "i": int(e.get("i", 0))})
			_count("reach_hearts")
			continue
		if str(e.get("kind", "")) == "landmark":
			_spawn_script("res://scripts/world/Landmark.gd", cell_to_world(cell), {"cell": cell, "index": int(e.get("index", 0))})
			_count("landmarks")
			continue
		_spawn_script("res://scripts/world/Wonder.gd", cell_to_world(cell), {"cell": cell, "kind": str(e.get("kind", "relic")), "i": int(e.get("i", 0))})
		_count("wonders")
		if str(e.get("kind", "")) in ["grotto", "hermitage", "relic", "echo"]:
			for i in 2:
				_glow_mushroom(cell_to_world(cell + Vector2i(_rng.randi_range(-3, 3), _rng.randi_range(-2, 2))))


# ---- round 30: the Trial Board in Eliet; what a world event brings ------------------

func trial_board_cell() -> Vector2i:
	## open ground (3x3) near where you arrive in the village, off to one side
	var ps: Array = spawns.get("P", [])
	if ps.is_empty():
		return Vector2i(-1, -1)
	var p: Vector2i = ps[0]
	var home := home_cell()
	var best := Vector2i(-1, -1)
	var best_d := 1 << 30
	for c in _floor_cells:
		var cell: Vector2i = c
		var dd := (cell - (p + Vector2i(4, 2))).length_squared()
		if dd >= best_d or (cell - p).length_squared() < 9 or (home.x >= 0 and (cell - home).length_squared() < 25):
			continue
		if _open_around(cell) < 9 or char_at(cell) != ".":
			continue
		var clear := true
		for dy in [-1, 0, 1]:
			for dx in [-1, 0, 1]:
				if not is_free(cell + Vector2i(dx, dy)):
					clear = false          # (a tree, a cart, a well already stands there)
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				if char_at(cell + Vector2i(dx, dy)) in ["t", "H", "f", "b", "c"]:
					clear = false          # (and not tucked behind a big tree or a house)
		if not clear:
			continue
		best_d = dd
		best = cell
	return best


func _event_cells(n: int, rng: RandomNumberGenerator) -> Array:
	var cells: Array = (spawns.get(".", []) as Array).filter(func(c): return is_free(c) and _open_around(c) >= 8)
	cells.sort()
	var out := []
	var tries := 0
	while out.size() < n and cells.size() > 0 and tries < 200:
		tries += 1
		var c: Vector2i = cells[rng.randi() % cells.size()]
		if out.any(func(o): return (o - c).length_squared() < 4):
			continue
		out.append(c)
	return out


func _place_hidden_masters() -> void:
	## round 34: whoever is hiding on this level, somewhere open, away from the way in
	var ms: Array = Game.hm_masters_at(level_id)
	if ms.is_empty():
		return
	var starts: Array = spawns.get("<", spawns.get("P", []))
	var taken := {}
	for m in ms:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash("master|" + level_id + str(m.get("id", "")))
		var df: Dictionary = Game.hm_data().get("difficulty", {})
		var far := clampf(float(df.get("far_from_stairs_base", 6)) + float(df.get("far_from_stairs_per_floor", 0.0)) * float(Game.floor_depth(level_id)), 6.0, float(df.get("far_from_stairs_max", 6)))
		var ok := func(c):
			if taken.has(c) or not is_free(c):
				return false
			for st in starts:
				if (c - st).length_squared() < 36:
					return false
			return true
		var ok_far := func(c):
			if not ok.call(c):
				return false
			for st2 in starts:
				if (c - st2).length() < far:
					return false
			return true
		var cells: Array = _free_area_cells(9).filter(ok_far)          # round 119: deeper = farther from the way in
		if cells.is_empty():
			cells = _free_area_cells(9).filter(ok)
		if cells.is_empty():
			cells = _free_area_cells(6).filter(ok)          # a town's streets are narrow
		if cells.is_empty():
			# (a boardwalk town records no floor cells: any open cell will do)
			for y in grid.size():
				for x in str(grid[y]).length():
					var gc := Vector2i(x, y)
					if ok.call(gc) and _open_around(gc) >= 6:
						cells.append(gc)
		if cells.is_empty():
			warnings.append(I18n.t("no room for the hidden master %s") % m.get("id", ""))
			continue
		var c: Vector2i = cells[rng.randi() % cells.size()]
		taken[c] = true
		_spawn_script("res://scripts/actors/HiddenMaster.gd", cell_to_world(c), {"cell": c, "id": str(m.get("id", ""))})
		_count("hidden_masters")


func _place_round30() -> void:
	_place_hidden_masters()
	if level_id == "village":
		var bc := trial_board_cell()
		if bc.x >= 0:
			_spawn_script("res://scripts/objects/TrialBoard.gd", cell_to_world(bc), {"cell": bc})
			_count("trial_board")
		else:
			warnings.append(I18n.t("no room for the Trial Board in the village"))
	if event.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("eventplace|" + level_id + str(event.get("id", "")))
	match str(event.get("spawn", "")):
		"master":
			var cs := _event_cells(1, rng)
			if cs.size() > 0:
				_spawn_script("res://scripts/actors/WanderingMaster.gd", cell_to_world(cs[0]), {"cell": cs[0]})
				_count("event_master")
		"meteor":
			var cs2 := _event_cells(1, rng)
			if cs2.size() > 0:
				var centre: Vector2i = cs2[0]
				var at := cell_to_world(centre)
				var glow := OmniLight3D.new()
				glow.light_color = Color(0.7, 0.75, 1.0)
				glow.light_energy = 2.5
				glow.omni_range = 9.0
				glow.position = at + Vector3(0, 1.5, 0)
				add_child(glow)
				var rock := MeshInstance3D.new()
				var sm := SphereMesh.new()
				sm.radius = 0.7
				sm.height = 1.2
				rock.mesh = sm
				var m := StandardMaterial3D.new()
				m.albedo_color = Color(0.2, 0.2, 0.25)
				m.emission_enabled = true
				m.emission = Color(0.55, 0.6, 1.0)
				m.emission_energy_multiplier = 1.2
				m.metallic = 0.7
				m.roughness = 0.35
				rock.material_override = m
				rock.position = at + Vector3(0, 0.3, 0)
				add_child(rock)
				var k := 0
				for dc in [Vector2i(2, 0), Vector2i(-2, 1), Vector2i(0, 2), Vector2i(1, -2)]:
					var c: Vector2i = centre + dc
					if is_free(c):
						_spawn_script("res://scripts/objects/GatherNode.gd", cell_to_world(c), {"kind": "ore", "cell": c, "yields": "star_iron" if k % 2 == 0 else "meteor_glass"})
						k += 1
				_count("event_meteor")
		"treasure":
			var beasts := []
			for e in Game.enemies:
				if bool(Game.enemies[e].get("passive", false)) and int(Game.enemies[e].get("floor", 99)) <= maxi(int(def.get("depth", 1)), 1):
					beasts.append(str(e))
			beasts.sort()
			var cs3 := _event_cells(1, rng)
			if cs3.size() > 0 and beasts.size() > 0:
				_spawn_script("res://scripts/actors/Enemy.gd", cell_to_world(cs3[0]), {"type": beasts[rng.randi() % beasts.size()], "cell": cs3[0], "treasure": true})
				_count("event_treasure")


func _place_critters() -> void:
	var kinds: Array = look.get("critters", [])
	if kinds.is_empty():
		return
	var cells: Array = _floor_cells.keys().filter(func(c): return char_at(c) == "." and not on_road(cell_to_world(c)))
	if cells.is_empty():
		cells = spawns.get(".", []).duplicate()          # a town on decks: no ground cells, still floor
	if cells.is_empty():
		return
	cells.sort()
	var n := clampi(int(cells.size() / 70) + 2, 2, 12 if not is_town() else 8)
	for i in n:
		var cell: Vector2i = cells[_rng.randi() % cells.size()]
		_spawn_script("res://scripts/actors/Critter.gd", cell_to_world(cell), {"cell": cell, "kind": str(kinds[i % kinds.size()]), "seed": _rng.randi()})
		_count("critters")


func _town_life() -> void:
	## Smoke from chimneys, stalls by the traders, lanterns that answer the
	## hour (Game.daylight()).
	var houses: Array = spawns.get("H", [])
	houses.sort()
	var chimneys := 0
	for c in houses:
		var cell: Vector2i = c
		if chimneys >= 10 or (cell.x * 7 + cell.y * 13) % 5 != 0:
			continue
		chimneys += 1
		var at := cell_to_world(cell)
		_prop("fantasy-town-kit/chimney.glb", at + Vector3(0.3, 3.2, 0.3), 1.6)
		var sm = preload("res://scripts/fx/Motes.gd").new()
		sm.kind = "smoke"
		sm.position = at + Vector3(0.3, 4.6, 0.3)
		add_child(sm)
		_count("chimneys")
	for ch in def.get("npcs", {}):
		var nd: Dictionary = def["npcs"][ch]
		if str(nd.get("role", "")) != "merchant":
			continue
		for cell in spawns.get(ch, []):
			for dir in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1)]:
				var n: Vector2i = cell + dir
				if char_at(n) == "." and _open_around(n) >= 9 and not on_road(cell_to_world(n)):      # open floor all round: can't cut a path (and never in the road)
					var stalls := ["fantasy-town-kit/stall.glb", "fantasy-town-kit/stall-red.glb", "fantasy-town-kit/stall-green.glb"]
					_prop(stalls[(cell.x + cell.y) % stalls.size()], cell_to_world(n), 1.6, atan2(float(-dir.x), float(-dir.y)))
					dressing_spots.append(cell_to_world(n))
					_solid(n)
					_box_body(cell_to_world(n) + Vector3(0, 1.0, 0), Vector3(CELL * 0.8, 2.0, CELL * 0.8))
					_count("stalls")
					break


const HOME_NEAR := Vector2i(6, 20)


func home_cell() -> Vector2i:
	## Elder Mo's spare plot: the open ground (5 cells by 3) nearest the
	## south-west corner of the village. (-1, -1) if a map has none.
	var best := Vector2i(-1, -1)
	var best_d := 1 << 30
	for c in _floor_cells:
		var cell: Vector2i = c
		var ok := true
		for dy in range(-1, 2):
			for dx in range(-2, 3):
				if char_at(cell + Vector2i(dx, dy)) != ".":
					ok = false
		if not ok:
			continue
		var d := (cell - HOME_NEAR).length_squared()
		if d < best_d or (d == best_d and cell < best):
			best_d = d
			best = cell
	return best


func _place_home() -> void:
	var cell := home_cell()
	if cell.x < 0:
		warnings.append(I18n.t("no room for a home in the village"))
		return
	_spawn_script("res://scripts/world/Home.gd", cell_to_world(cell), {"cell": cell})
	_count("home")


func _against_edge(cell: Vector2i) -> bool:
	for dir in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
		if char_at(cell + dir) in [" ", "#"]:
			return true
	return false


func _open_around(cell: Vector2i) -> int:
	var n := 0
	for dy in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			if char_at(cell + Vector2i(dx, dy)) in [".", ","]:
				n += 1
	return n


# ---- round 44: the deep's peoples, the old age, the clans' hunters -----------------------------

var _reserved := []         # [centre, radius]: areas already given to a camp or a dig


func _season_trees() -> String:
	var W = Game.sys("world")
	if W == null or W.calm:
		return ""
	return str(W.season().get("look", {}).get("trees", ""))


func open_spot(r: int, seed_key: String) -> Vector2i:
	## an open square of floor (2r+1 across, all free), away from the way in and
	## from anything already placed this way -- (-1, -1) if there's none
	var starts: Array = spawns.get("<", spawns.get("P", []))
	var out := []
	var cands := _free_area_cells(9)
	if cands.is_empty():
		for y in grid.size():
			for x in str(grid[y]).length():
				if is_free(Vector2i(x, y)) and _open_around(Vector2i(x, y)) >= 9:
					cands.append(Vector2i(x, y))
	for c in cands:
		var ok := true
		for st in starts:
			if (c - st).length_squared() < 100:
				ok = false
				break
		if not ok:
			continue
		for rv in _reserved:
			var d: Vector2i = c - rv[0]
			if absi(d.x) <= r + int(rv[1]) + 1 and absi(d.y) <= r + int(rv[1]) + 1:
				ok = false
				break
		if not ok:
			continue
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var cc: Vector2i = c + Vector2i(dx, dy)
				if char_at(cc) == "P" or not is_free(cc):
					ok = false
					break
			if not ok:
				break
		if ok:
			out.append(c)
	if out.is_empty():
		return Vector2i(-1, -1)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_key)
	var pick: Vector2i = out[rng.randi() % out.size()]
	_reserved.append([pick, r])
	return pick


func _place_round44() -> void:
	if level_id.begins_with("tribulation:") or bool(def.get("trial", false)) or bool(def.get("arena", false)):
		return
	var S = Game.sys("settlements")
	if S:
		S.place(self)
	var R = Game.sys("ruins")
	if R:
		R.place(self)
	var F = Game.sys("factions")
	if F == null:
		return
	if level_id == "village":
		_place_village_memory(F, S)          # round 45: Eliet shows what you've done
		return
	var n: int = F.hunters_for(level_id, def)
	if n <= 0:
		return
	# the clans' hunters: the hardest ordinary thing that lives this deep, in a pack
	var d := int(def.get("depth", 0))
	var best := ""
	var bf := -1
	for e in Game.enemies:
		var ed: Dictionary = Game.enemies[e]
		if bool(ed.get("boss", false)) or bool(ed.get("passive", false)):
			continue
		var f := int(ed.get("floor", 0))
		if f <= d and f > bf:
			bf = f
			best = str(e)
	if best == "":
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("hunters|" + level_id)
	for c in _event_cells(n, rng):
		_spawn_script("res://scripts/actors/Enemy.gd", cell_to_world(c), {"type": best, "cell": c, "hunter": true, "hp_mult": float(F.data.get("hunter", {}).get("hp_mult", 1.3))})
		_count("hunters")
	Game.message.emit.call_deferred("The Hollow Clans have sent hunters onto this floor. They're looking for you.")


# ---- round 45: Eliet remembers -----------------------------------------------------------------

# ---- round 63: the waystone (systems/Travel.gd) -----------------------------------------------

var waystone_cell := Vector2i(-1, -1)


func waystone_center() -> Vector2i:
	## where this place's waystone goes: Eliet by the fountain, a town where you
	## come in, a dungeon floor beside the way DOWN (past its master)
	if level_id == "village":
		return fountain_cell()
	if is_town() or theme == "wilds":
		var arr: Array = spawns.get("<", spawns.get("P", []))
		return arr[0] if not arr.is_empty() else Vector2i(width / 2, height / 2)
	var exits: Dictionary = def.get("exits", {})
	for ch in exits:
		var e = exits[ch]
		if e is Dictionary and bool(e.get("down", true)) and str(e.get("to", "")).begins_with("floor") and not spawns.get(ch, []).is_empty():
			return spawns[ch][0]
	var arr2: Array = spawns.get(">", [])
	return arr2[0] if not arr2.is_empty() else Vector2i(-1, -1)


func _place_waystone() -> void:
	if not preload("res://scripts/systems/Travel.gd").eligible(level_id, theme):
		return
	if bool(def.get("trial", false)) or bool(def.get("arena", false)):
		return
	var center := waystone_center()
	if center.x < 0:
		return
	var c := near_spot(center, 7 + plaza_rmin() - 2, "waystone:" + level_id, plaza_rmin())
	if c.x < 0:
		c = near_spot(center, 16, "waystone2:" + level_id, plaza_rmin())        # (a cramped way down: look further out)
	if c.x < 0:
		var arr: Array = spawns.get("<", spawns.get("P", []))
		if not arr.is_empty():
			c = near_spot(arr[0], 10, "waystone3:" + level_id)      # (or where you come in)
	if c.x < 0:
		c = open_spot(1, "waystone4:" + level_id)                  # (or any open ground at all)
	if c.x < 0:
		warnings.append(I18n.t("no room for a waystone"))
		return
	waystone_cell = c
	_solid(c)
	spawns["waystone"] = [c]
	_spawn_script("res://scripts/objects/Waystone.gd", cell_to_world(c), {"cell": c, "id": level_id, "name": display_name().get_slice(" -- ", 0)})
	_count("waystones")


const PLAZA_CLEAR := 6          # round 167: cells around the fountain that hold nothing but people (Robert: "don't make the center of town so busy")


func plaza_rmin() -> int:
	return PLAZA_CLEAR if level_id == "village" else 2


func fountain_cell() -> Vector2i:
	var fs: Array = spawns.get("f", [])
	if fs.is_empty():
		return Vector2i(width / 2, height / 2)
	return fs[0]


func near_spot(center: Vector2i, rmax: int, seed_key: String, rmin: int = 2) -> Vector2i:
	## a free, open cell within rmax of center (nearest rings first, none nearer than rmin), not already taken
	## (round 167: the village's plaza keeps its middle clear -- see PLAZA_CLEAR)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_key)
	for r in range(rmin, rmax + 1):
		var ring := []
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var c: Vector2i = center + Vector2i(dx, dy)
				if is_free(c) and char_at(c) in [".", ","] and _open_around(c) >= 8 and not _near_reserved(c):
					ring.append(c)
		if not ring.is_empty():
			var pick: Vector2i = ring[rng.randi() % ring.size()]
			_reserved.append([pick, 0])
			return pick
	return Vector2i(-1, -1)


func _near_reserved(c: Vector2i) -> bool:
	for rv in _reserved:
		var d: Vector2i = c - rv[0]
		if absi(d.x) <= int(rv[1]) + 1 and absi(d.y) <= int(rv[1]) + 1:
			return true
	return false


func _place_village_memory(F, S) -> void:
	## the peoples who trust you fly their colours in Eliet; the Lantern Stone
	## remembers who came back; a town in the deep sends its trader up on market days
	var fc := fountain_cell()
	# the Lantern Stone: always there, by the fountain
	var lc := near_spot(fc, 12, "lantern_stone", plaza_rmin())
	if lc.x >= 0:
		var st := _prop("nature-kit/statue_obelisk.glb", cell_to_world(lc), 2.2)
		st.name = "LanternStone"
		_solid(lc)
		_box_body(cell_to_world(lc) + Vector3(0, 1.2, 0), Vector3(CELL * 0.6, 2.4, CELL * 0.6))
		var names := ["THOSE WHO WENT DOWN AND CAME BACK", "Mo -- the first expedition, the only one of nine"]
		if F.at_least("eliet", "revered"):
			names.append(I18n.t("%s -- who made the deep a place people live") % (Game.char_name if Game.char_name != "" else "You"))
		var tag := Label3D.new()
		tag.name = "LanternStoneWords"
		tag.text = "\n".join(names)
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.pixel_size = 0.008
		tag.font_size = 30
		tag.outline_size = 8
		tag.modulate = Color(1.0, 0.9, 0.65)
		tag.position = cell_to_world(lc) + Vector3(0, 3.4, 0)
		add_child(tag)
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.8, 0.5)
		l.light_energy = 0.3 + 0.9 * (1.0 - Game.daylight())       # its lamp is lit at dusk
		l.omni_range = 5.0
		l.position = cell_to_world(lc) + Vector3(0, 1.4, 0)
		add_child(l)
		_count("lantern_stone")
	# banners of the peoples who trust you
	for fid in F.ids():
		if fid == "eliet" or not F.at_least(str(fid), "trusted"):
			continue
		var bc := near_spot(fc, 16, "banner|" + str(fid), plaza_rmin())
		if bc.x < 0:
			continue
		var fd: Dictionary = F.fdef(str(fid))
		var b := _prop(str(fd.get("banner", "fantasy-town-kit/banner-green.glb")), cell_to_world(bc), 2.0, atan2(float(fc.x - bc.x), float(fc.y - bc.y)))
		b.name = "Banner_" + str(fid)
		var col: Array = fd.get("color", [0.9, 0.9, 0.9])
		_tint(b, Color(float(col[0]), float(col[1]), float(col[2])).lerp(Color(1, 1, 1), 0.35))
		_solid(bc)
		var bt := Label3D.new()
		bt.text = str(fd.get("short", fid))
		bt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		bt.pixel_size = 0.006
		bt.font_size = 24
		bt.outline_size = 6
		bt.modulate = Color(float(col[0]), float(col[1]), float(col[2])).lightened(0.3)
		bt.position = cell_to_world(bc) + Vector3(0, 3.0, 0)
		add_child(bt)
		_count("faction_banners")
	if S:
		S.place_visitors(self)


## A player must never be stuck (stress bot, floor6): when the only way from the arrival to the way down is through
## secret walls, the ones on that route are opened as ordinary doorways. Secrets off the main route stay secret.
## Runs when the floor enters the tree, after every wall, gate and chest has marked its own cell in astar.
func _ensure_path_without_secrets() -> void:
	var starts: Array = spawns.get("<", spawns.get("P", []))
	var goals: Array = spawns.get(">", [])
	if starts.is_empty() or goals.is_empty():
		return
	var walls: Array = []
	var gates: Array = []
	for child in get_children():
		var sc = child.get_script()
		if sc == null:
			continue
		if sc.resource_path.ends_with("SecretWall.gd") and not bool(child.get("_opening")):
			walls.append(child)
		elif sc.resource_path.ends_with("Gate.gd"):
			gates.append(child)
	if walls.is_empty():
		return
	var start: Vector2i = starts[0]
	var goal: Vector2i = goals[0]
	var closed_gates: Array = []
	for g in gates:
		var gc: Vector2i = g.get("cell")
		if astar.region.has_point(gc) and astar.is_point_solid(gc):
			astar.set_point_solid(gc, false)
			closed_gates.append(gc)
	var to_open: Array = []
	if astar.get_id_path(start, goal).is_empty():
		for w in walls:
			astar.set_point_solid(w.cell, false)
		var route: Array = astar.get_id_path(start, goal)
		for w in walls:
			astar.set_point_solid(w.cell, true)
		for w in walls:
			if w.cell in route:
				to_open.append(w)
	for gc in closed_gates:
		astar.set_point_solid(gc, true)
	for w in to_open:
		w._open_now()


## A lore stone (Stele) or a lever standing in a one-cell corridor cuts the floor in two (stress bot, floors 14, 17, 24):
## where freeing one reaches more of the floor than keeping it solid, it becomes a stone you can walk through
## (still readable, still usable). Roomy spots keep their solid stones. Gates and secret walls count as open.
func _reach_count(start: Vector2i) -> int:
	var seen := {start: true}
	var q := [start]
	var i := 0
	while i < q.size():
		var c: Vector2i = q[i]
		i += 1
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if seen.has(n) or not astar.region.has_point(n) or astar.is_point_solid(n):
				continue
			seen[n] = true
			q.append(n)
	return seen.size()


func _unplug_things() -> void:
	var starts: Array = spawns.get("<", spawns.get("P", []))
	if starts.is_empty():
		return
	var start: Vector2i = starts[0]
	var things: Array = []
	var doors: Array = []
	for child in get_children():
		var sc = child.get_script()
		if sc == null:
			continue
		var f: String = str(sc.resource_path)
		if f.ends_with("Stele.gd") or f.ends_with("Lever.gd"):
			if child.get("cell") != null and astar.region.has_point(child.cell) and astar.is_point_solid(child.cell):
				things.append(child)
		elif f.ends_with("Gate.gd") or f.ends_with("SecretWall.gd"):
			var dc = child.get("cell")
			if dc != null and astar.region.has_point(dc) and astar.is_point_solid(dc):
				doors.append(dc)
	if things.is_empty():
		return
	for dc in doors:
		astar.set_point_solid(dc, false)
	var freed: Array = []
	for t in things:
		var before := _reach_count(start)
		astar.set_point_solid(t.cell, false)
		if _reach_count(start) > before + 1:
			freed.append(t)
		else:
			astar.set_point_solid(t.cell, true)
	for dc in doors:
		astar.set_point_solid(dc, true)
	for t in freed:
		for c in t.get_children():
			if c is CollisionShape3D:
				c.disabled = true
		_count("stones_walkthrough")


func check_secret_wall(cell: Vector2i = Vector2i(-1, -1)) -> bool:
	if cell != Vector2i(-1, -1):
		if spawns.has("S"):
			for s in spawns["S"]:
				if s == cell:
					return true
		for child in get_children():
			if child.get_script() and child.get_script().resource_path.ends_with("SecretWall.gd"):
				if child.get("cell") == cell:
					return true
		return false
	if spawns.has("S") and spawns["S"].size() > 0:
		return true
	if counts.get("secrets", 0) > 0:
		return true
	for child in get_children():
		if child.get_script() and child.get_script().resource_path.ends_with("SecretWall.gd"):
			return true
	return false
