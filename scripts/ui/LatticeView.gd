extends Control
## The Meridian Lattice, drawn (K): your dantian at the centre, six rings
## (one per realm), three meridians -- Strike up, Guard down-left, Step
## down-right. Open points glow in their element's colour; the one you're
## opening has a ring of progress around it; sealed rings sit dark.
## Click a point to make it your meditation focus (Game.set_focus).

signal picked(pid: String)
signal hovered(pid: String)

const ANGLE := {"strike": -90.0, "guard": 150.0, "step": 30.0}
const ELEMENT_COLOR := {"wood": Color(0.45, 0.85, 0.4), "fire": Color(1.0, 0.45, 0.2), "earth": Color(0.85, 0.7, 0.35),
	"metal": Color(0.85, 0.88, 0.95), "water": Color(0.35, 0.65, 1.0)}
const R0 := 46.0
const STEP := 38.0
const DOT := 9.0

var _hover := ""


func _init() -> void:
	custom_minimum_size = Vector2(560, 560)
	mouse_filter = Control.MOUSE_FILTER_STOP


func centre() -> Vector2:
	return size / 2.0 if size.x > 0 else custom_minimum_size / 2.0


func point_pos(p: Dictionary) -> Vector2:
	## where a point sits: on its ring, either side of its meridian's ray
	var ring := int(p.get("ring", 1))
	var mer := str(p.get("meridian", "strike"))
	var pts: Array = Game.lattice_data().get("points", [])
	var k := 0
	for q in pts:
		if str(q["meridian"]) == mer and int(q["ring"]) == ring:
			if str(q["id"]) == str(p["id"]):
				break
			k += 1
	var spread := 15.0 - ring * 1.2
	var a := deg_to_rad(float(ANGLE.get(mer, 0.0)) + (-spread if k == 0 else spread))
	var r := R0 + STEP * (ring - 0.5)
	return centre() + Vector2(cos(a), sin(a)) * r


func point_at(pos: Vector2) -> String:
	for p in Game.lattice_data().get("points", []):
		if point_pos(p).distance_to(pos) <= DOT + 4.0:
			return str(p["id"])
	return ""


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var h := point_at(event.position)
		if h != _hover:
			_hover = h
			hovered.emit(h)
			queue_redraw()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var pid := point_at(event.position)
		if pid != "":
			picked.emit(pid)
			queue_redraw()


func _draw() -> void:
	var c := centre()
	# the rings: lit up to the realm you've reached, dark beyond
	for ring in range(1, 7):
		var open := Game.point_ring_open(ring)
		var col := Color(0.55, 0.75, 0.9, 0.35) if open else Color(0.4, 0.4, 0.45, 0.15)
		draw_arc(c, R0 + STEP * ring, 0, TAU, 96, col, 1.5 if open else 1.0, true)
	# the meridians
	for mer in ANGLE:
		var a := deg_to_rad(float(ANGLE[mer]))
		draw_line(c, c + Vector2(cos(a), sin(a)) * (R0 + STEP * 6), Color(0.7, 0.8, 0.9, 0.25), 2.0, true)
	# the dantian
	draw_circle(c, 22.0, Color(0.35, 0.75, 1.0, 0.25))
	draw_arc(c, 22.0, 0, TAU, 48, Color(0.5, 0.85, 1.0, 0.9), 2.0, true)
	# routes of the arts you know, traced between their points
	for aid in Game.arts:
		var prev := c
		for pid in Game.art_route(str(aid)):
			var p := Game.lattice_point(str(pid))
			if p.is_empty():
				continue
			var at := point_pos(p)
			draw_line(prev, at, Color(1.0, 0.85, 0.4, 0.6 if Game.lattice.has(str(pid)) else 0.2), 2.5, true)
			prev = at
	# the points
	for p in Game.lattice_data().get("points", []):
		var pid := str(p["id"])
		var at := point_pos(p)
		var ec: Color = ELEMENT_COLOR.get(str(p.get("element", "")), Color.WHITE)
		if Game.lattice.has(pid):
			draw_circle(at, DOT + 5.0, Color(ec.r, ec.g, ec.b, 0.25))
			draw_circle(at, DOT, ec)
		elif Game.point_ring_open(int(p["ring"])):
			draw_circle(at, DOT, Color(ec.r, ec.g, ec.b, 0.18))
			draw_arc(at, DOT, 0, TAU, 24, Color(ec.r, ec.g, ec.b, 0.8), 1.5, true)
			var f := Game.point_fraction(pid)
			if f > 0.0:
				draw_arc(at, DOT + 4.0, -PI / 2, -PI / 2 + TAU * f, 32, ec, 3.0, true)
		else:
			draw_arc(at, DOT * 0.7, 0, TAU, 16, Color(0.5, 0.5, 0.55, 0.4), 1.0, true)
		if pid == Game.lattice_focus:
			draw_arc(at, DOT + 8.0, 0, TAU, 32, Color(1, 1, 1, 0.95), 2.0, true)
		if pid == _hover:
			draw_arc(at, DOT + 11.0, 0, TAU, 32, Color(1, 1, 0.7, 0.6), 1.0, true)
