extends StaticBody3D
## The Trial Board (round 30), by the fountain in Eliet: a notice board, and
## the old trial-keeper's ledger nailed under it. Everything that brings you
## back lives here --
##   * today's trial (TrialGen.gd): the same twists for everyone today; clear
##     it for gold, insight, trial marks and a streak bonus
##   * this week's sect trials: three goals, counted from what you do anyway
##   * trial marks: spend them (pills, nanites, formulas, a drop of old blood)
##   * collections: how much of the world you've seen, with rewards at 25/50/75/100%
##   * your blood (once it has woken)
##   * ascension: begin the climb again, stronger
## (data/retention.json holds the numbers.)

var level
var cell := Vector2i.ZERO
var _light: OmniLight3D


func setup(lvl, args: Dictionary) -> void:
	level = lvl
	cell = args.get("cell", Vector2i.ZERO)


func _ready() -> void:
	add_to_group("interactable")
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.45, 0.32, 0.2)
	wood.roughness = 0.9
	var tex = preload("res://scripts/world/Look.gd").texture("old_wood_floor", "albedo") if DisplayServer.get_name() != "headless" else null
	if tex:
		wood.albedo_texture = tex
		wood.uv1_triplanar = true
		wood.uv1_scale = Vector3.ONE * 0.8
	for x in [-1.05, 1.05]:
		_box(Vector3(0.14, 2.4, 0.14), Vector3(x, 1.2, 0), wood)
	_box(Vector3(2.4, 1.3, 0.1), Vector3(0, 1.55, 0), wood)
	_box(Vector3(2.7, 0.12, 0.35), Vector3(0, 2.3, 0.05), wood)        # a little roof
	var paper := StandardMaterial3D.new()
	paper.albedo_color = Color(0.92, 0.88, 0.76)
	paper.roughness = 1.0
	var notes := [Vector3(-0.7, 1.75, 0.06), Vector3(-0.1, 1.5, 0.06), Vector3(0.6, 1.8, 0.06), Vector3(0.5, 1.25, 0.06), Vector3(-0.6, 1.2, 0.06)]
	for i in notes.size():
		var q := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(0.42, 0.5) if i != 1 else Vector2(0.55, 0.62)
		q.mesh = qm
		q.material_override = paper
		q.position = notes[i]
		q.rotation.z = (i - 2) * 0.06
		add_child(q)
	var red := StandardMaterial3D.new()
	red.albedo_color = Color(0.7, 0.12, 0.1)
	_box(Vector3(0.1, 0.1, 0.02), Vector3(-0.1, 1.78, 0.08), red)      # the day's seal
	var lbl := Label3D.new()
	lbl.text = "TRIAL BOARD"
	lbl.font_size = 44
	lbl.outline_size = 8
	lbl.pixel_size = 0.008
	lbl.modulate = Color(1.0, 0.85, 0.5)
	lbl.position = Vector3(0, 2.75, 0)
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(lbl)
	if DisplayServer.get_name() != "headless":
		_light = OmniLight3D.new()
		_light.light_color = Color(1.0, 0.8, 0.5)
		_light.light_energy = 1.2
		_light.omni_range = 5.0
		_light.position = Vector3(0, 2.2, 1.0)
		add_child(_light)
	var shape := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = Vector3(2.6, 2.4, 0.5)
	shape.shape = b
	shape.position = Vector3(0, 1.2, 0)
	add_child(shape)
	if level and level.get("astar"):
		level.astar.set_point_solid(cell, true)


func _box(size: Vector3, at: Vector3, m: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	mi.position = at
	add_child(mi)


func _process(_delta: float) -> void:
	# the board glows warmer when today's trial is still waiting
	if _light:
		_light.light_energy = (1.6 + sin(Time.get_ticks_msec() / 500.0) * 0.3) if not Game.trial_done_today() else 0.8


func prompt() -> String:
	return "E: The Trial Board%s" % ("  (today's trial is posted)" if not Game.trial_done_today() else "")


func interact(_player) -> void:
	open_main()


func _hud():
	return get_tree().get_first_node_in_group("hud")


func open_main(note: String = "") -> void:
	var hud = _hud()
	if hud == null:
		return
	var day := Game.today()
	var body := ""
	if note != "":
		body += note + "\n\n"
	body += "TODAY'S TRIAL (%s), at floor %d strength:\n   %s\n" % [day, Game.trial_depth(), "\n   ".join(Game.trial_mod_names())]
	if Game.trial_done_today():
		body += "Done today -- best score %d. Try again for a better one; the rewards are yours already.\n" % int(Game.trials.get("best", {}).get(day, 0))
	else:
		body += "Clear every hall for gold, insight, trial marks, and your streak.\n"
	var st := int(Game.trials.get("streak", 0))
	body += "\nStreak: %d day%s  ·  Trial marks: %d" % [st, "" if st == 1 else "s", Game.marks]
	if int(Game.ascension.get("count", 0)) > 0:
		body += "  ·  Ascension %d (heavenly marks: %d)" % [int(Game.ascension["count"]), int(Game.ascension.get("marks", 0))]
	var opts := [
		["Try today's trial again" if Game.trial_done_today() else "Enter today's trial", func():
			hud.close_dialog()
			Game.start_trial()],
		["This week's sect trials", func(): open_weekly()],
		["Spend trial marks (%d)" % Game.marks, func(): open_shop()],
		["Collections", func(): open_collections()],
	]
	if Game.blood_awake() or not Game.blood_rows().is_empty():
		opts.append(["Your blood", func(): open_blood()])
	opts.append(["Ascension...", func(): open_ascension()])
	opts.append(["Leave", hud.close_dialog])
	hud.open_dialog("The Trial Board", body, opts)


func open_weekly() -> void:
	var hud = _hud()
	var lines := []
	for r in Game.weekly_rows():
		lines.append("%s %s -- %d/%d" % ["[done]" if bool(r[3]) else "   ", r[0], int(r[1]), int(r[2])])
	var R: Dictionary = Game.retention_data().get("weekly", {}).get("reward", {})
	var body := "THIS WEEK (%s left):\n%s\n\nEach one: +%d marks, +%d gold, insight. All three: +%d marks more. They count what you'd do anyway -- just do it." % [
		Game.week_left_text(), "\n".join(lines), int(R.get("marks", 6)), int(R.get("gold", 250)), int(R.get("all_three", {}).get("marks", 10))]
	hud.open_dialog("The Week's Sect Trials", body, [["Back", func(): open_main()]])


func open_shop(note: String = "") -> void:
	var hud = _hud()
	var opts := []
	for s in Game.shop_rows():
		var sid := str(s.get("id", ""))
		opts.append(["%s -- %d marks" % [s.get("name", sid), int(s.get("cost", 0))], func():
			open_shop(Game.buy_with_marks(sid))])
	opts.append(["Back", func(): open_main()])
	hud.open_dialog("Trial Marks: %d" % Game.marks, (note + "\n\n" if note != "" else "") + "The trial-keeper's shelf. Marks come from the daily trial, the week's sect trials and collections.", opts)


func open_collections() -> void:
	var hud = _hud()
	var lines := []
	for c in Game.collections():
		var pct := 100.0 * float(c["have"]) / maxf(float(c["total"]), 1.0)
		lines.append("%s: %d of %d (%d%%)" % [c["name"], int(c["have"]), int(c["total"]), int(pct)])
	var B: Dictionary = Game.retention_data().get("collections", {}).get("bestiary", {})
	var studied := 0
	var mastered := 0
	for e in Game.kills:
		if int(Game.kills[e]) >= int(B.get("mastered", 50)):
			mastered += 1
		elif int(Game.kills[e]) >= int(B.get("studied", 10)):
			studied += 1
	var body := "\n".join(lines) + "\n\nRewards at 25%, 50%, 75% and 100% of each.\nBestiary: %d kinds studied (+%d%% damage to them), %d mastered (+%d%%) -- %d and %d of a kind." % [
		studied, int(round((float(B.get("studied_bonus", 1.04)) - 1.0) * 100)), mastered, int(round((float(B.get("mastered_bonus", 1.1)) - 1.0) * 100)),
		int(B.get("studied", 10)), int(B.get("mastered", 50))]
	var nudge := Game.collection_nudge()
	if nudge != "":
		body += "\n\nAlmost there -- " + nudge + "."
	hud.open_dialog("Collections", body, [["Back", func(): open_main()]])


func open_blood(note: String = "") -> void:
	var hud = _hud()
	hud.open_blood(note, func(): open_main())


func open_ascension(note: String = "") -> void:
	var hud = _hud()
	var why := Game.can_ascend()
	var A: Dictionary = Game.retention_data().get("ascension", {})
	var body := (note + "\n\n" if note != "" else "")
	body += "To ascend is to begin the climb again from Eliet -- stronger. The deep grows harder (+%d%% to every foe each time) and richer.\n\n" % int(float(A.get("foe_scale_per", 0.25)) * 100)
	body += "What comes with you: your achievements, collections, trial marks and streak, every material and formula you know, %d piece%s of gear (your weapon and your best), and %d%% of your blood's purity.\nWhat stays behind: your cultivation, floors, gold and everything else you carry.\n\n" % [
		Game.heirloom_count(), "" if Game.heirloom_count() == 1 else "s", int(round(minf(float(A.get("keep_blood", 0.6)) + 0.1 * Game.boon_rank("true_blood"), 1.0) * 100))]
	var opts := []
	if why != "":
		body += "Not yet: %s" % why
	else:
		body += "Ascending now earns %d heavenly marks (from how deep and how far you've come)." % Game.ascension_marks()
		opts.append(["ASCEND NOW", func():
			hud.open_dialog("Ascend?", "Everything you carry except your heirlooms stays behind. Your cultivation starts again at Body Tempering. Are you sure?", [
				["Yes -- begin again", func():
					hud.close_dialog()
					Game.ascend()],
				["Not yet", func(): open_ascension()]])])
	body += "\n\nHeavenly marks to spend: %d" % int(Game.ascension.get("marks", 0))
	var Bd: Dictionary = A.get("boons", {})
	var bids: Array = Bd.keys()
	bids.sort()
	for bid in bids:
		var c := Game.boon_cost(str(bid))
		var b: Dictionary = Bd[bid]
		var label := "%s (rank %d/%d) -- %s" % [b.get("name", bid), Game.boon_rank(str(bid)), int(b.get("max", 1)), b.get("desc", "")]
		if c >= 0:
			opts.append(["%s: %d marks" % [label, c], func(): open_ascension(Game.buy_boon(str(bid)))])
	opts.append(["Back", func(): open_main()])
	hud.open_dialog("Ascension", body, opts)
