extends Control
## The map (round 75), a page in the menu (Hub.gd, F2). Robert: "be able to build a map of the
## world and area the player has traveled through."
##   THIS PLACE   the place you're in, drawn from the cells you've seen (Atlas.gd): floor, road,
##                water, walls; what you haven't seen stays dark; marks for what you've found;
##                you are the white dot. Drag to pan, wheel / pinch / + - to zoom.
##   THE WORLD    the whole of it from data: Eliet and the valley across the top, the floors in a
##                column down the middle (lit where you've been, ringed in gold where a waystone
##                is yours, grey where you haven't), the deep's reaches as pips beside each floor
##                you've seen, other places you've been down the left -- and the line of your
##                route through them, in the order you went. Tap a place to read about it.
## It draws itself from Atlas, so it works the same under a mouse or a thumb.

const BAR := 46.0

var hud
var atlas
var view := "place"             # "place" | "world"
var place_id := ""
var zoom := 1.0
var pan := Vector2.ZERO
var tex: ImageTexture = null
var tex_size := Vector2i.ZERO
var nodes_world := []
var picked := ""
var _bar: HBoxContainer
var _info: Label
var _drag := false
var _pulse := 0.0
var lit_rect := Rect2i()        # the part of the place you've seen (the map opens zoomed to it)
var _pending_fit := false


func setup(h) -> void:
	hud = h
	name = "MapScreen"
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_bar = HBoxContainer.new()
	_bar.add_theme_constant_override("separation", 8)
	_bar.position = Vector2(8, 6)
	add_child(_bar)
	_tab(_bar, "This place", func(): set_view("place"))
	_tab(_bar, "The world", func(): set_view("world"))
	_tab(_bar, "+", func(): zoom_by(1.35))
	_tab(_bar, "-", func(): zoom_by(1.0 / 1.35))
	_tab(_bar, "Centre", func(): recentre())
	_info = Label.new()
	_info.add_theme_font_size_override("font_size", 14)
	_info.add_theme_color_override("font_color", Color(0.85, 0.88, 0.95))
	_info.position = Vector2(8, BAR + 2)
	add_child(_info)
	atlas = Game.sys("atlas")
	resized.connect(queue_redraw)


func _tab(box: Node, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(44 if text.length() <= 6 and text != "Centre" else 100, 34)
	b.add_theme_font_size_override("font_size", 14)
	b.pressed.connect(cb)
	box.add_child(b)
	return b


func set_view(v: String) -> void:
	view = v
	picked = ""
	pan = Vector2.ZERO
	zoom = 1.0
	refresh()


func zoom_by(f: float) -> void:
	var cfg: Dictionary = atlas.cfg if atlas else {}
	zoom = clampf(zoom * f, float(cfg.get("zoom_min", 0.4)), float(cfg.get("zoom_max", 5.0)))
	queue_redraw()


func recentre() -> void:
	pan = Vector2.ZERO
	if view == "place":
		var pc := player_cell()
		if pc.x > -9000 and tex != null:
			pan = -(Vector2(pc) + Vector2(0.5, 0.5) - Vector2(tex_size) / 2.0) * tile()
	queue_redraw()


func tile() -> float:
	return float((atlas.cfg if atlas else {}).get("tile_px", 6)) * zoom


func player_cell() -> Vector2i:
	var lv = atlas.live_level() if atlas else null
	var pl = get_tree().get_first_node_in_group("player") if is_inside_tree() else null
	if lv == null or pl == null or str(lv.level_id) != place_id:
		return Vector2i(-9999, -9999)
	return lv.world_to_cell(pl.global_position)


# ---- filling ------------------------------------------------------------------------------

func refresh() -> void:
	## called when the page opens (and when the view changes)
	atlas = Game.sys("atlas")
	if atlas == null:
		return
	atlas.scan_live()
	place_id = str(Game.current_level)
	if view == "place":
		build_texture()
		if pan == Vector2.ZERO and is_equal_approx(zoom, 1.0):
			_pending_fit = true
	else:
		nodes_world = atlas.world_nodes()
	_set_info()
	queue_redraw()


func tint_of(ch: String) -> Color:
	var t: Dictionary = atlas.cfg.get("tints", {})
	var key := "floor"
	match ch:
		"#":
			key = "wall"
		",":
			key = "road"
		"~", "&":
			key = "water"
		"H":
			key = "house"
		"t":
			key = "tree"
		"c", "b", "x", "f":
			key = "solid"
	var a: Array = t.get(key, [0.3, 0.3, 0.3])
	return Color(float(a[0]), float(a[1]), float(a[2]), 1.0)


func build_texture() -> void:
	## one pixel a cell: what you've seen in colour, the rest left clear (the dark behind shows through)
	var grid: Array = atlas.grid_of(place_id)
	var h := grid.size()
	var w := 0
	for row in grid:
		w = maxi(w, str(row).length())
	if w == 0 or h == 0:
		tex = null
		tex_size = Vector2i.ZERO
		return
	var fogged: bool = atlas.is_fogged(place_id)
	var seen: Dictionary = atlas.seen_cells(place_id) if fogged else {}
	var known_all: bool = (not fogged) and atlas.visited(place_id)
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var x0 := w
	var y0 := h
	var x1 := -1
	var y1 := -1
	for y in h:
		var row: String = str(grid[y])
		for x in row.length():
			var ch := row[x]
			if ch == " ":
				continue
			if (fogged and seen.has(Vector2i(x, y))) or known_all:
				img.set_pixel(x, y, tint_of(ch))
				x0 = mini(x0, x)
				y0 = mini(y0, y)
				x1 = maxi(x1, x)
				y1 = maxi(y1, y)
	tex = ImageTexture.create_from_image(img)
	tex_size = Vector2i(w, h)
	lit_rect = Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1) if x1 >= 0 else Rect2i(0, 0, w, h)


func _set_info() -> void:
	if atlas == null:
		_info.text = ""
		return
	if view == "place":
		var d: Dictionary = Game.load_level_def(place_id)
		var pct: int = int(round(float(atlas.explored_share(place_id)) * 100.0))
		_info.text = "%s   ·   %d%% explored   ·   %d found" % [str(d.get("name", place_id)), pct, atlas.marks_for(place_id).size()]
		if pct == 0:
			_info.text += "   ·   " + tr("Walk around and the map fills in as you go.")
	else:
		var n: int = atlas.visits.size()
		_info.text = ("%d places so far" % n) if picked == "" else picked_text()


func picked_text() -> String:
	for nd in nodes_world:
		if str(nd["id"]) == picked:
			var row: Dictionary = atlas.visit_row(picked)
			if row.is_empty():
				return "%s   ·   not yet visited" % str(nd["name"])
			return "%s   ·   visited %d time%s%s" % [str(nd["name"]), int(row.get("n", 1)), "" if int(row.get("n", 1)) == 1 else "s", "   ·   waystone yours" if bool(nd.get("attuned", false)) else ""]
	return ""


# ---- drawing -------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if visible:
		_pulse += delta
		if view == "place" or picked == "":
			queue_redraw()


func fit() -> void:
	## zoom and slide so all you've seen of the place fills the page
	if tex == null:
		return
	var base: float = float(atlas.cfg.get("tile_px", 6))
	var avail := Vector2(maxf(size.x - 60.0, 100.0), maxf(size.y - BAR - 90.0, 100.0))
	var zmax := minf(float(atlas.cfg.get("zoom_max", 5.0)), 4.0)
	zoom = clampf(minf(avail.x / (float(lit_rect.size.x) * base), avail.y / (float(lit_rect.size.y) * base)), float(atlas.cfg.get("zoom_min", 0.4)), zmax)
	var mid := Vector2(lit_rect.position) + Vector2(lit_rect.size) / 2.0
	pan = -(mid - Vector2(tex_size) / 2.0) * tile()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.015, 0.015, 0.025, 1.0))
	if atlas == null:
		return
	if _pending_fit and size.x > 100.0 and view == "place":
		_pending_fit = false
		fit()
	if view == "place":
		_draw_place()
	else:
		_draw_world()


func origin() -> Vector2:
	return Vector2(size.x * 0.5, BAR + (size.y - BAR) * 0.5) + pan


func _draw_place() -> void:
	if tex == null:
		draw_string(ThemeDB.fallback_font, Vector2(20, size.y * 0.5), "Nothing is drawn of this place yet.", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.7, 0.7, 0.8))
		return
	var t := tile()
	var tl := origin() - Vector2(tex_size) * t * 0.5
	draw_texture_rect(tex, Rect2(tl, Vector2(tex_size) * t), false)
	var cols: Dictionary = atlas.cfg.get("marks", {})
	for m in atlas.marks_for(place_id):
		var p := tl + (Vector2(float(m["x"]), float(m["y"])) + Vector2(0.5, 0.5)) * t
		var a: Array = cols.get(str(m["kind"]), [1, 1, 1])
		var col := Color(float(a[0]), float(a[1]), float(a[2]))
		var r := maxf(3.5, t * 0.6)
		match str(m["kind"]):
			"exit":
				draw_colored_polygon(PackedVector2Array([p + Vector2(0, -r), p + Vector2(r, 0), p + Vector2(0, r), p + Vector2(-r, 0)]), col)
			"boss":
				draw_circle(p, r, col)
				draw_arc(p, r * 1.5, 0, TAU, 20, col, 1.5)
			"shrine", "waystone":
				draw_circle(p, r * 0.8, col)
				draw_arc(p, r * 1.4, 0, TAU, 20, col, 1.5)
			_:
				draw_circle(p, r * 0.7, col)
		if zoom >= 1.6 or t >= 9.0:
			draw_string(ThemeDB.fallback_font, p + Vector2(r + 3, 4), str(m["name"]), HORIZONTAL_ALIGNMENT_LEFT, 180, 12, Color(col, 0.95))
	var pc := player_cell()
	if pc.x > -9000:
		var pp := tl + (Vector2(pc) + Vector2(0.5, 0.5)) * t
		var pr := maxf(4.0, t * 0.6) * (1.0 + 0.12 * sin(_pulse * 4.0))
		draw_circle(pp, pr, Color(1, 1, 1, 0.95))
		draw_arc(pp, pr * 1.7, 0, TAU, 24, Color(1, 1, 1, 0.5), 1.5)


func world_pos(nd: Dictionary) -> Vector2:
	var w := size.x * 0.8
	var h := (size.y - BAR) * 0.88
	var base := Vector2(size.x * 0.1, BAR + 10.0)
	return base + Vector2(float(nd["x"]) * w, float(nd["y"]) * h) * zoom + pan - (Vector2(w, h) * (zoom - 1.0)) * 0.5


func _draw_world() -> void:
	if nodes_world.is_empty():
		nodes_world = atlas.world_nodes()
	var at := {}
	for nd in nodes_world:
		at[str(nd["id"])] = world_pos(nd)
	# the column the floors hang on
	var prev := Vector2.ZERO
	var first := true
	for nd in nodes_world:
		if str(nd["kind"]) != "floor":
			continue
		var p: Vector2 = at[str(nd["id"])]
		if not first:
			draw_line(prev, p, Color(0.25, 0.28, 0.36, 0.7), 1.5)
		prev = p
		first = false
	if at.has("village") and at.has("floor1"):
		draw_line(at["village"], at["floor1"], Color(0.25, 0.28, 0.36, 0.7), 1.5)
	# the route you've taken, in order
	var rt: Array = atlas.route()
	for i in range(1, rt.size()):
		if at.has(rt[i - 1]) and at.has(rt[i]):
			draw_line(at[rt[i - 1]], at[rt[i]], Color(0.4, 0.9, 1.0, 0.55), 2.0)
	var r_big := clampf(5.0 * zoom, 3.0, 14.0)
	for nd in nodes_world:
		var p: Vector2 = at[str(nd["id"])]
		var r0 := r_big if str(nd["kind"]) != "floor" else clampf(2.6 * zoom, 2.0, 7.0)      # (fifty floors close together: small dots)
		var seen_it: bool = bool(nd["visited"])
		var col := Color(0.95, 0.9, 0.7) if seen_it else Color(0.3, 0.3, 0.36)
		if str(nd["kind"]) == "village" or str(nd["kind"]) == "valley":
			col = Color(0.6, 0.95, 0.6) if seen_it else Color(0.28, 0.34, 0.3)
		draw_circle(p, r0, col)
		if bool(nd.get("attuned", false)):
			draw_arc(p, r0 * 1.6, 0, TAU, 20, Color(1.0, 0.82, 0.3), 2.0)
		if str(nd["id"]) == place_id:
			draw_arc(p, r0 * (2.0 + 0.2 * sin(_pulse * 4.0)), 0, TAU, 24, Color(1, 1, 1, 0.9), 2.0)
		for k in int(nd.get("reaches", 0)):
			draw_circle(p + Vector2(r0 * 2.4 + float(k) * r0 * 1.5, 0), r0 * 0.5, Color(0.6, 0.5, 0.9, 0.9))
		var label_it := str(nd["kind"]) != "floor" or int(str(nd["id"]).substr(5)) % 5 == 0 or str(nd["id"]) == picked or str(nd["id"]) == place_id
		if label_it:
			draw_string(ThemeDB.fallback_font, p + Vector2(-r0 * 2.0 - 90.0 if str(nd["kind"]) == "floor" else r0 * 1.8, 5), str(nd["name"]), HORIZONTAL_ALIGNMENT_RIGHT if str(nd["kind"]) == "floor" else HORIZONTAL_ALIGNMENT_LEFT, 90 if str(nd["kind"]) == "floor" else 160, 12, Color(0.8, 0.83, 0.92, 0.9))


# ---- pan, zoom, tap ------------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			zoom_by(1.2)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			zoom_by(1.0 / 1.2)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			_drag = mb.pressed
			if not mb.pressed and view == "world":
				_tap(mb.position)
	elif event is InputEventMouseMotion and _drag:
		pan += (event as InputEventMouseMotion).relative
		queue_redraw()
	elif event is InputEventScreenDrag:
		pan += (event as InputEventScreenDrag).relative
		queue_redraw()
	elif event is InputEventMagnifyGesture:
		zoom_by((event as InputEventMagnifyGesture).factor)


func _tap(pos: Vector2) -> void:
	var best := ""
	var bd := 22.0
	for nd in nodes_world:
		var d := world_pos(nd).distance_to(pos)
		if d < bd:
			bd = d
			best = str(nd["id"])
	if best != "":
		picked = best
		_set_info()
		queue_redraw()
