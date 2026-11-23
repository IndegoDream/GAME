extends Node3D
## The trial in the middle of a tower floor (round 24, TowerGen.gd).
##
##   combat     foes of the tower's tier rise around the room; beat them all.
##              Floor 9 is the summit: its guardian (a great foe of that
##              depth) and two of its keepers.
##   endurance  hold the floor while foes keep coming (40 s + 4 a floor, at
##              most four at once). Fall and the floor resets.
##   puzzle     five element pillars round the room; the inscription says
##              which order -- creation (wood, fire, earth, metal, water)
##              or, higher up, overcoming (water, fire, metal, wood, earth)
##              -- and where to begin. A wrong pillar puts them all out and
##              wakes something.
##   insight    the inscription asks one question about the way of qi (the
##              Academy's question bank); a wrong answer wakes two foes and
##              the inscription goes quiet for twenty seconds.
##
## Pass it and the stair up opens (Game.clear_tower_floor pays the first
## time; a floor already cleared stays open).

const CREATION := ["wood", "fire", "earth", "metal", "water"]
const OVERCOMING := ["water", "fire", "metal", "wood", "earth"]
const EL_COLOR := {"wood": Color(0.4, 0.85, 0.4), "fire": Color(1.0, 0.45, 0.2), "earth": Color(0.85, 0.7, 0.35),
	"metal": Color(0.85, 0.88, 0.95), "water": Color(0.35, 0.6, 1.0)}

var level
var cell := Vector2i.ZERO
var info := {}
var tid := ""
var n := 1
var kind := "combat"
var cleared := false
var _foes := []
var _t := 0.0
var _spawn_t := 0.0
var _started := false
var _order := []
var _which := "creation"
var _next := 0
var _pillars := []
var _quiet := 0.0
var _q := {}
var _headless := false


func setup(lvl, args: Dictionary) -> void:
	level = lvl
	cell = args.get("cell", Vector2i.ZERO)
	info = args.get("tower", {})
	tid = str(info.get("id", ""))
	n = int(info.get("n", 1))
	kind = str(info.get("kind", "combat"))


func _ready() -> void:
	_headless = DisplayServer.get_name() == "headless"
	add_to_group("tower_trial")
	add_to_group("interactable")
	_build_dais()
	if Game.tower_cleared(tid) >= n:
		cleared = true
		_open_up.call_deferred(false)          # (the level is still adding its children)
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s:%d" % [tid, n])
	if kind == "puzzle":
		var base: Array = OVERCOMING if n >= 6 else CREATION
		_which = "overcoming" if n >= 6 else "creation"
		var start := rng.randi() % 5
		for i in 5:
			_order.append(base[(start + i) % 5])
		_build_pillars()
	elif kind == "insight":
		var qs: Array = Game.AcademyLib.exam_questions(hash("%s:%d:%s" % [tid, n, Game.today()]))
		_q = qs[0] if qs.size() > 0 else {}
	Game.message.emit("%s -- %s" % [info.get("floor_name", I18n.t("Floor %d") % n), info.get("trial", "")])
	# combat and endurance begin a breath after you arrive
	if kind in ["combat", "endurance"]:
		get_tree().create_timer(2.0).timeout.connect(func():
			if is_instance_valid(self) and not cleared:
				_begin())


func _begin() -> void:
	_started = true
	if kind == "combat":
		if n >= 9:
			var gid := Game.tower_guardian(int(info.get("tier", 1)))
			if gid != "":
				_spawn(gid, 0.0)
			for i in 2:
				_spawn("", TAU * (i + 1) / 3.0)
		else:
			var k := 3 + n / 2
			for i in k:
				_spawn("", TAU * i / k)
	elif kind == "endurance":
		_t = 40.0 + 4.0 * n
		_spawn_t = 0.0
		Game.message.emit("Hold the floor: %d seconds." % int(_t))


func _spawn(eid: String, angle: float) -> void:
	if eid == "":
		var pool: Array = Game.tower_enemy_pool(int(info.get("tier", 1)))
		if pool.is_empty():
			return
		eid = str(pool[randi() % pool.size()])
	var at := global_position + Vector3(cos(angle), 0, sin(angle)) * 6.0
	var foe = level._spawn_script("res://scripts/actors/Enemy.gd", at, {"type": eid, "cell": level.world_to_cell(at)})
	if foe:
		foe.set_meta("tower", true)
		_foes.append(foe)


func _alive() -> int:
	var k := 0
	for f in _foes:
		if is_instance_valid(f) and not f._dead:
			k += 1
	return k


func _process(delta: float) -> void:
	_quiet = maxf(_quiet - delta, 0.0)
	if cleared or not _started:
		return
	if kind == "combat":
		if _alive() == 0:
			_pass()
	elif kind == "endurance":
		var pl = get_tree().get_first_node_in_group("player")
		if pl and pl.dead:
			_reset("You fall -- the floor lets you go, and waits for you to try again.")
			return
		_t -= delta
		_spawn_t -= delta
		if _spawn_t <= 0.0 and _alive() < 4:
			_spawn_t = 6.0
			_spawn("", randf() * TAU)
		if _t <= 0.0:
			for f in _foes:
				if is_instance_valid(f) and not f._dead:
					f.queue_free()
			_pass()


func _reset(why: String) -> void:
	for f in _foes:
		if is_instance_valid(f) and not f._dead:
			f.queue_free()
	_foes = []
	_started = false
	Game.message.emit(why)
	get_tree().create_timer(4.0).timeout.connect(func():
		if is_instance_valid(self) and not cleared:
			_begin())


func _pass() -> void:
	if cleared:
		return
	cleared = true
	_started = false
	Game.clear_tower_floor(tid, n)
	_open_up(true)
	var hud = get_tree().get_first_node_in_group("hud")
	if n >= 9 and hud:
		hud.open_dialog(str(info.get("name", "The summit")), str(Game.tower_def(tid).get("summit", "")), [["...", hud.close_dialog]])


func _open_up(announce: bool) -> void:
	## the stair up (or, at the summit, nothing above but sky)
	for p in _pillars:
		p.lit = true
		p.refresh()
	if n >= 9 or level == null:
		return
	var uc: Array = level.def.get("up_cell", [cell.x, cell.y - 7])
	var up_cell := Vector2i(int(uc[0]), int(uc[1]))
	var next_name := ""
	var floors: Array = Game.tower_def(tid).get("floors", [])
	if n < floors.size():
		next_name = str(floors[n].get("name", ""))
	level._spawn_script("res://scripts/objects/Exit.gd", level.cell_to_world(up_cell), {"cell": up_cell, "to": "tower:%s:%d" % [tid, n + 1],
		"arrive": "<", "label": I18n.t("Up to floor %d%s") % [n + 1, (": " + next_name) if next_name != "" else ""], "down": false})
	if announce:
		Game.message.emit("Somewhere above you, stone grinds aside: the stair up is open.")


# ---- the inscription (E at the dais) ------------------------------------------------

func prompt() -> String:
	if cleared:
		return I18n.t("The inscription is quiet -- this floor is passed") if n < 9 else I18n.t("E: Read the summit stone")
	match kind:
		"puzzle":
			return I18n.t("E: Read the inscription on the dais")
		"insight":
			return I18n.t("The inscription is silent a while (%ds)") % int(ceil(_quiet)) if _quiet > 0.0 else I18n.t("E: Answer the inscription's question")
		"endurance":
			return I18n.t("Hold -- %ds") % int(ceil(maxf(_t, 0.0))) if _started else I18n.t("The floor is waking...")
	return I18n.t("%d left") % _alive() if _started else I18n.t("The floor is waking...")


func interact(_player) -> void:
	var hud = get_tree().get_first_node_in_group("hud")
	if hud == null:
		return
	if cleared:
		if n >= 9:
			hud.open_dialog(str(info.get("name", "")), str(Game.tower_def(tid).get("summit", "")), [["...", hud.close_dialog]])
		return
	match kind:
		"puzzle":
			hud.open_dialog(str(info.get("floor_name", "")), I18n.t("%s\n\nCut into the dais: wake the pillars in the order of %s, beginning with %s.") % [
				info.get("trial", ""), _which, _order[0]], [["...", hud.close_dialog]])
		"insight":
			if _quiet > 0.0 or _q.is_empty():
				return
			var opts := []
			for k in _q.get("options", []).size():
				opts.append([str(_q["options"][k]), func(): answer(k)])
			hud.open_dialog(str(info.get("floor_name", "")), "%s\n\n%s" % [info.get("trial", ""), _q.get("q", "")], opts)


func answer(k: int) -> bool:
	var hud = get_tree().get_first_node_in_group("hud") if is_inside_tree() else null
	if hud:
		hud.close_dialog()
	if cleared or _q.is_empty():
		return cleared
	if k == int(_q.get("answer", -1)):
		Game.message.emit("The inscription glows, and is still. (Correct.)")
		_started = true
		_pass()
		return true
	_quiet = 20.0
	_started = true
	for i in 2:
		_spawn("", randf() * TAU)
	Game.message.emit("Wrong. The stone wakes its keepers.")
	return false


func touch_pillar(el: String) -> bool:
	## a pillar woken -- true if it was the right one
	if cleared or kind != "puzzle":
		return false
	if _next < _order.size() and _order[_next] == el:
		_next += 1
		for p in _pillars:
			if p.element == el:
				p.lit = true
				p.refresh()
		if _next >= _order.size():
			_started = true
			_pass()
		return true
	_next = 0
	for p in _pillars:
		p.lit = false
		p.refresh()
	_started = true
	_spawn("", randf() * TAU)
	Game.message.emit("The pillars go dark together -- and something stirs.")
	return false


# ---- looks ---------------------------------------------------------------------------

func color_of(el: String) -> Color:
	return EL_COLOR.get(el, Color.WHITE)


func _build_dais() -> void:
	var b := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 1.4
	cm.bottom_radius = 1.6
	cm.height = 0.4
	b.mesh = cm
	b.position.y = 0.2
	if not _headless:
		b.material_override = preload("res://scripts/world/Look.gd").surface(["castle_brick_01", [0.8, 0.78, 0.75], 1.0])
	add_child(b)
	var lbl := Label3D.new()
	lbl.text = "%s\n%s" % [info.get("floor_name", ""), {"combat": I18n.t("a fight"), "endurance": I18n.t("hold the floor"), "puzzle": I18n.t("the five pillars"),
		"insight": "a question"}.get(kind, "")]
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.pixel_size = 0.008
	lbl.font_size = 34
	lbl.outline_size = 8
	lbl.modulate = Color(1.0, 0.9, 0.7)
	lbl.position = Vector3(0, 2.4, 0)
	add_child(lbl)


func _build_pillars() -> void:
	for i in 5:
		var el: String = CREATION[i]
		var p := Pillar.new()
		p.trial = self
		p.element = el
		var a := TAU * i / 5.0 - PI / 2.0
		p.position = Vector3(cos(a), 0, sin(a)) * 6.5
		add_child(p)
		_pillars.append(p)


class Pillar extends Node3D:
	var trial
	var element := "wood"
	var lit := false
	var _mat: StandardMaterial3D

	func _ready() -> void:
		add_to_group("interactable")
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.35
		cm.bottom_radius = 0.45
		cm.height = 2.4
		mi.mesh = cm
		mi.position.y = 1.2
		_mat = StandardMaterial3D.new()
		_mat.emission_enabled = true
		if DisplayServer.get_name() != "headless":
			mi.material_override = _mat
		add_child(mi)
		var lbl := Label3D.new()
		lbl.text = element
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.pixel_size = 0.007
		lbl.font_size = 30
		lbl.outline_size = 6
		lbl.position = Vector3(0, 2.8, 0)
		add_child(lbl)
		refresh()

	func refresh() -> void:
		if _mat == null:
			return
		var c: Color = trial.color_of(element)
		_mat.albedo_color = c.darkened(0.55)
		_mat.emission = c
		_mat.emission_energy_multiplier = 2.2 if lit else 0.15

	func prompt() -> String:
		return I18n.t("The %s pillar burns") % element if lit else I18n.t("E: Wake the %s pillar") % element

	func interact(_player) -> void:
		if not lit:
			trial.touch_pillar(element)
