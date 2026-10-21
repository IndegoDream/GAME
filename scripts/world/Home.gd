extends Node3D
## Your home in Eliet (Robert, 2026-10-02: "focus on afk and downtime
## portions of the game, that way the user always feels like they are
## accomplishing something"). Elder Mo's spare plot at the edge of the
## village: a garden that grows in real time (Game.plant / harvest), a
## workbench that works through a queue on its own (Game.queue_craft), a
## chest for your materials (Game.home["stash"]), and a bed that leaves you
## well rested (Game.rest_at_home). It's yours the first time you look at it.
##
## Five places to press E -- the garden, the bench, the chest, the bed and
## (round 20) the training post -- each a small Spot node below. Arts used
## at the post are real practice, half an hour a day (Game.post_drill). The crops you see are the crops you
## planted, at the stage they've reached.
##
## Round 32 ("home growing into a compound"): the sign is where you BUILD.
## The plot becomes a cottage (walls, a roof; longer rest), a courtyard
## (a fence, lanterns, a cultivation stone of your own), a compound
## (quarters for your companion, a kennel for your familiar: they grow
## while you're away). data/companions.json "compound".

const N := "res://assets/kenney/nature-kit/"
const D := "res://assets/kenney/mini-dungeon/"
const T := "res://assets/kenney/fantasy-town-kit/"
const CROP_FOR := {"spirit_herb": "crop_turnip.glb", "ember_root": "crop_carrot.glb", "iron_thistle": "crops_wheatStageB.glb",
	"moonpetal": "flower_purpleA.glb", "verdant_heart": "crop_melon.glb", "glowcap_spore": "crop_pumpkin.glb"}
const PLOT_SPACING := 1.25

var level
var cell := Vector2i.ZERO
var _garden: Node3D
var _spots := {}
var _t := 0.0
var _last_sig := ""
var _tent: Node3D
var _compound: Node3D
var _last_stage := -1


class Spot extends Node3D:
	var home
	var what := ""

	func prompt() -> String:
		return home.prompt_for(what)

	func interact(_player) -> void:
		home.open(what, _player)


func setup(lvl, args: Dictionary) -> void:
	level = lvl
	cell = args.get("cell", Vector2i.ZERO)


func _ready() -> void:
	add_to_group("home")
	var headless := DisplayServer.get_name() == "headless"
	# the tent (and the bed in its mouth), the bench, the chest, a sign
	_tent = _prop(N + "tent_detailedOpen.glb", Vector3(3.0, 0, -1.9), 3.2, 0.0)
	_prop(N + "bed_floor.glb", Vector3(3.0, 0.02, -1.6), 2.2, 0.0)
	_prop(D + "table.glb", Vector3(0.2, 0, 1.7), 2.0, 0.0)
	_prop(D + "pot.glb", Vector3(-0.2, 1.05, 1.65), 0.9, 0.0)
	_prop(D + "chest.glb", Vector3(3.2, 0, 1.8), 1.8, PI)
	_prop(N + "sign.glb", Vector3(-1.2, 0, 2.7), 2.2, 0.0)
	_prop(N + "campfire_stones.glb", Vector3(0.6, 0, -0.6), 2.0, 0.0)
	for i in 4:
		_prop(N + "fence_simple.glb", Vector3(-4.6 + i * 1.0, 0, -2.7), 2.0, 0.0)
	if not headless:
		var lamp := OmniLight3D.new()
		lamp.position = Vector3(0.6, 1.3, -0.6)
		lamp.light_color = Color(1.0, 0.75, 0.45)
		lamp.light_energy = 1.2
		lamp.omni_range = 6.0
		add_child(lamp)
	var label := Label3D.new()
	label.text = I18n.t("Home")
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.pixel_size = 0.008
	label.font_size = 30
	label.outline_size = 8
	label.modulate = Color(1.0, 0.9, 0.65)
	label.position = Vector3(-1.2, 2.4, 2.7)
	add_child(label)
	var bed := MeshInstance3D.new()        # the tilled ground the garden beds sit in
	var bm := BoxMesh.new()
	bm.size = Vector3(4.1, 0.04, 4.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.2, 0.12)
	mat.roughness = 1.0
	bm.material = mat
	bed.mesh = bm
	bed.position = Vector3(-3.05, 0.03, -0.15)
	add_child(bed)
	_garden = Node3D.new()
	add_child(_garden)
	for w in [["garden", Vector3(-3.0, 0, 0)], ["bench", Vector3(0.2, 0, 1.7)], ["chest", Vector3(3.2, 0, 1.8)], ["bed", Vector3(3.0, 0, -1.2)], ["post", Vector3(-0.3, 0, -2.35)], ["sign", Vector3(-1.2, 0, 2.7)]]:
		var s := Spot.new()
		s.home = self
		s.what = str(w[0])
		s.position = w[1]
		s.add_to_group("interactable")
		add_child(s)
		_spots[w[0]] = s
	_build_post(Vector3(-0.3, 0, -2.35), headless)
	_compound = Node3D.new()
	add_child(_compound)
	_build_garden()
	_build_compound()
	Game.stats_changed.connect(_build_garden)
	Game.stats_changed.connect(_build_compound)


func _block(at: Vector3, s: float, wood: bool) -> void:
	## a house block like the village's: walls, a gabled roof, something to bump into
	var w := _prop(T + ("wall-wood-block.glb" if wood else "wall-block.glb"), at, s, 0.0)
	var r := _prop(T + "roof-gable.glb", at + Vector3(0, s, 0), s, 0.0)
	if w:
		w.reparent(_compound)
	if r:
		r.reparent(_compound)
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(s, s * 2.0, s)
	shape.shape = box
	shape.position = Vector3(0, s, 0)
	body.add_child(shape)
	body.position = at
	_compound.add_child(body)


func _cprop(path: String, at: Vector3, s: float, yaw: float = 0.0) -> void:
	var p := _prop(path, at, s, yaw)
	if p:
		p.reparent(_compound)


func _build_compound() -> void:
	var stage := Game.home_stage()
	if stage == _last_stage:
		return
	_last_stage = stage
	for c in _compound.get_children():
		c.queue_free()
	var headless := DisplayServer.get_name() == "headless"
	if _tent:
		_tent.visible = stage < 1
	if _spots.has("shrine"):
		_spots["shrine"].queue_free()
		_spots.erase("shrine")
	if stage >= 1:
		# the cottage, where the tent stood
		_block(Vector3(3.0, 0, -1.9), 1.8, true)
	if stage >= 2:
		# the courtyard: a fence with a gate along the front, lanterns, a cultivation stone of your own
		for i in 10:
			var x := -4.6 + i * 1.0
			if x > 0.0 and x < 2.0:
				continue
			_cprop(N + "fence_simple.glb", Vector3(x, 0, 2.95), 2.0)
		for x in [-4.8, 4.6]:
			_cprop(T + "lantern.glb", Vector3(x, 0, 2.95), 1.4)
			if not headless:
				var l := OmniLight3D.new()
				l.position = Vector3(x, 1.6, 2.95)
				l.light_color = Color(1.0, 0.8, 0.5)
				l.light_energy = 1.0
				l.omni_range = 5.0
				_compound.add_child(l)
		_cprop(N + "statue_block.glb", Vector3(-4.8, 0, 2.3), 1.3)
		var s := Spot.new()
		s.home = self
		s.what = "shrine"
		s.position = Vector3(-4.8, 0, 1.6)
		s.add_to_group("interactable")
		add_child(s)
		_spots["shrine"] = s
	if stage >= 3:
		# the compound: quarters beside the cottage, a kennel, a back wall
		_block(Vector3(5.6, 0, -1.9), 1.8, false)
		for i in 3:
			_cprop(N + "fence_simple.glb", Vector3(4.8 + i * 1.0, 0, 1.0), 2.0)
		_cprop(N + "fence_simple.glb", Vector3(6.4, 0, 1.9), 2.0, PI / 2)
		_cprop(N + "bed_floor.glb", Vector3(5.4, 0.02, 1.8), 1.4)
		for i in 5:
			_cprop(N + "fence_simple.glb", Vector3(-4.6 + i * 1.0, 0, -2.7), 2.0)
		_cprop(T + "fence.glb", Vector3(5.6, 0, -3.0), 1.2)
		var lab := Label3D.new()
		lab.text = I18n.t("Quarters / Kennel")
		lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lab.pixel_size = 0.008
		lab.font_size = 24
		lab.outline_size = 6
		lab.modulate = Color(0.9, 0.95, 1.0)
		lab.position = Vector3(5.6, 2.6, 0.0)
		_compound.add_child(lab)


func _process(delta: float) -> void:
	_t += delta
	if _t >= 5.0:          # crops grow while you watch (or don't)
		_t = 0.0
		_build_garden()


func _prop(path: String, at: Vector3, s: float, yaw: float) -> Node3D:
	if not ResourceLoader.exists(path):
		return null
	var m: Node3D = preload("res://scripts/core/Art.gd").make(path.trim_prefix("res://assets/kenney/"))
	m.position = at
	m.scale = Vector3.ONE * s
	m.rotation.y = yaw
	add_child(m)
	return m


func _build_post(at: Vector3, headless: bool) -> void:
	## a wooden training post: a pole, two arms, a straw head; in the
	## "training_post" group so the Player knows when an art is a drill
	var post := StaticBody3D.new()
	post.name = "TrainingPost"
	post.position = at
	post.add_to_group("training_post")
	add_child(post)
	var wood: Material = null
	if not headless:
		wood = preload("res://scripts/world/Look.gd").surface(["old_wood_floor", [0.72, 0.56, 0.4], 1.0])
	for part in [[Vector3(0, 0.95, 0), Vector3(0.24, 1.9, 0.24), "box"], [Vector3(0, 1.3, 0), Vector3(1.1, 0.14, 0.14), "box"],
			[Vector3(0, 0.75, 0), Vector3(0.8, 0.12, 0.12), "box"], [Vector3(0, 2.05, 0), Vector3(0.36, 0.36, 0.36), "head"]]:
		var mi := MeshInstance3D.new()
		if part[2] == "head":
			var sm := SphereMesh.new()
			sm.radius = 0.2
			sm.height = 0.42
			mi.mesh = sm
			if not headless:
				var straw := StandardMaterial3D.new()
				straw.albedo_color = Color(0.78, 0.66, 0.38)
				straw.roughness = 1.0
				mi.material_override = straw
		else:
			var bm := BoxMesh.new()
			bm.size = part[1]
			mi.mesh = bm
			if wood:
				mi.material_override = wood
		mi.position = part[0]
		post.add_child(mi)
	var col := CollisionShape3D.new()
	var cs := BoxShape3D.new()
	cs.size = Vector3(0.3, 2.2, 0.3)
	col.shape = cs
	col.position = Vector3(0, 1.1, 0)
	post.add_child(col)


func _stage(i: int) -> int:
	## -1 nothing planted, 0 just in, 1 growing, 2 nearly, 3 ready
	var g: Array = Game.home.get("garden", [])
	if i >= g.size() or (g[i] as Dictionary).is_empty():
		return -1
	if Game.plot_ready(i):
		return 3
	var p: Dictionary = g[i]
	var span := maxf(1.0, float(p.get("ready", 0.0)) - float(p.get("planted", 0.0)))
	var f := clampf((Game._now() - float(p.get("planted", 0.0))) / span, 0.0, 1.0)
	return 0 if f < 0.34 else (1 if f < 0.67 else 2)


func _build_garden() -> void:
	if _garden == null or not is_inside_tree():
		return
	var plots := Game.plot_count() if Game.has_home() else 3
	var sig := str(plots)
	for i in plots:
		sig += ":%d%s" % [_stage(i), str((Game.home.get("garden", []) as Array)[i].get("seed", "")) if i < Game.home.get("garden", []).size() else ""]
	if sig == _last_sig:
		return
	_last_sig = sig
	for c in _garden.get_children():
		c.queue_free()
	for i in plots:
		var at := Vector3(-4.3 + (i % 3) * PLOT_SPACING, 0, -1.4 + (i / 3) * PLOT_SPACING)
		var dirt = load(N + "crops_dirtSingle.glb").instantiate()
		dirt.position = at
		dirt.scale = Vector3.ONE * 1.25
		_garden.add_child(dirt)
		var st := _stage(i)
		if st < 0:
			continue
		var seed := str(Game.home["garden"][i].get("seed", "spirit_herb"))
		var path: String = N + ["crops_leafsStageA.glb", "crops_leafsStageB.glb", "crops_cornStageB.glb", CROP_FOR.get(seed, "crop_turnip.glb")][st]
		var m = load(path).instantiate()
		m.position = at + Vector3(0, 0.05, 0)
		m.scale = Vector3.ONE * (1.0 + 0.25 * st)
		_garden.add_child(m)
		if st == 3 and DisplayServer.get_name() != "headless":
			var glow := OmniLight3D.new()       # ready: a little shine so you notice from the path
			glow.position = at + Vector3(0, 0.6, 0)
			glow.light_color = Color(0.7, 1.0, 0.6)
			glow.light_energy = 0.6
			glow.omni_range = 1.6
			_garden.add_child(glow)


# ---- what E says, and what it opens -------------------------------------------------

func prompt_for(what: String) -> String:
	if not Game.has_home():
		return I18n.t("E: Elder Mo's spare plot")
	match what:
		"garden":
			var r := Game.ready_plots()
			return I18n.t("E: Your garden") + (I18n.t(" -- %d ready to pick") % r if r > 0 else "")
		"bench":
			var q: Dictionary = Game.home.get("queue", {})
			return I18n.t("E: Your workbench") + (" -- %d %s to go" % [int(q["left"]), Game.item_name(str(q.get("recipe", "")))] if int(q.get("left", 0)) > 0 else "")
		"chest":
			return I18n.t("E: Your chest")
		"bed":
			return I18n.t("E: Your bed") + (I18n.t(" (well rested)") if Game.rested() else "")
		"post":
			return I18n.t("E: Training post -- %d min of drill left today") % int(ceil(Game.post_budget() / 60.0))
		"sign":
			var nx := Game.home_next_stage()
			return I18n.t("E: Your home (%s)%s") % [str(Game.home_stage_def().get("name", "")), (I18n.t(" -- build %s: %d gold") % [nx.get("name", ""), int(nx.get("cost", 0))]) if not nx.is_empty() else ""]
		"shrine":
			return I18n.t("E: Sit and cultivate at your stone (stand up by moving)") if not Game.meditating else I18n.t("Cultivating... (move to stand)")
	return ""


func _hud():
	return get_tree().get_first_node_in_group("hud") if is_inside_tree() else null


func open(what: String, player = null) -> void:
	var hud = _hud()
	if hud == null:
		return
	if what == "shrine":
		if player != null and player.has_method("start_meditating"):
			player.start_meditating(true)
		return
	if not Game.has_home():
		hud.open_dialog("Elder Mo's spare plot",
			"A tent, a bit of tilled earth, an old bench and a chest. Elder Mo said it was yours if you wanted it: \"Everyone needs somewhere to come back to.\"\n\nThe garden grows while you're away. The bench works through whatever you set it to. The chest holds what your pouch can't. The bed leaves you well rested.",
			[["Make it yours", func():
				Game.take_home()
				_last_sig = ""
				_build_garden()
				open(what)], ["Not now", hud.close_dialog]])
		return
	match what:
		"garden":
			garden_menu()
		"bench":
			bench_menu()
		"chest":
			chest_menu()
		"bed":
			bed_menu()
		"post":
			post_menu()
		"sign":
			build_menu()


func build_menu(note: String = "") -> void:
	var hud = _hud()
	var cur := Game.home_stage_def()
	var nx := Game.home_next_stage()
	var body := (note + "\n\n" if note != "" else "") + I18n.t("Your home is %s. %s") % [cur.get("name", ""), cur.get("desc", "")]
	var opts := []
	if nx.is_empty():
		body += I18n.t("\n\nThere's nothing more to build. It's a compound now -- yours, and theirs.")
	else:
		var needs := []
		for id in nx.get("needs", {}):
			needs.append("%d %s" % [int(nx["needs"][id]), Game.item_name(str(id))])
		body += I18n.t("\n\nNext: %s -- %d gold%s.\n%s") % [nx.get("name", ""), int(nx.get("cost", 0)), (" and " + ", ".join(needs)) if not needs.is_empty() else "", nx.get("desc", "")]
		var why := Game.home_upgrade_check()
		if why != "":
			body += "\n\n" + why
		else:
			opts.append(["Build %s" % nx.get("name", ""), func():
				var r := Game.home_upgrade()
				_build_compound()
				build_menu(r if r != "" else "Built. %s" % Game.home_stage_def().get("desc", ""))])
	opts.append(["Close", hud.close_dialog])
	hud.open_dialog("Your home", body, opts)


func garden_menu() -> void:
	var hud = _hud()
	var lines := []
	var g: Array = Game.home.get("garden", [])
	for i in g.size():
		var p: Dictionary = g[i]
		if p.is_empty():
			lines.append(I18n.t("Plot %d: empty") % (i + 1))
		elif Game.plot_ready(i):
			lines.append(I18n.t("Plot %d: %s -- ready") % [i + 1, Game.item_name(str(p.get("seed", "")))])
		else:
			lines.append(I18n.t("Plot %d: %s -- %s to go") % [i + 1, Game.item_name(str(p.get("seed", ""))), Game._dur(float(p.get("ready", 0.0)) - Game._now())])
	lines.append(I18n.t("\nAnything you plant comes back as several (more as your Herbalism grows), and now and then something better seeds itself. Growing takes %s.") % Game._dur(Game.grow_seconds()))
	var opts := []
	var r := Game.ready_plots()
	if r > 0:
		opts.append(["Pick everything that's ready (%d)" % r, func():
			var got := []
			for i in g.size():
				var t := Game.harvest(i)
				if t != "":
					got.append(t)
			Game.message.emit(I18n.t("From your garden: ") + "; ".join(got) + ".")
			Game.save_game()
			garden_menu()])
	var empty := 0
	for p in g:
		if (p as Dictionary).is_empty():
			empty += 1
	if empty > 0:
		for sid in Game.plantable():
			opts.append(["Plant %s (you have %d)" % [Game.item_name(str(sid)), Game.count(str(sid))], func():
				var n := 0
				for i in g.size():
					if (Game.home["garden"][i] as Dictionary).is_empty() and Game.plant(i, str(sid)):
						n += 1
				Game.message.emit(I18n.t("You plant %d %s.") % [n, Game.item_name(str(sid))])
				Game.save_game()
				_last_sig = ""
				_build_garden()
				garden_menu()])
		if Game.plantable().is_empty():
			lines.append(I18n.t("(You've nothing to plant. Herbs you pick in the deep can go in the ground here.)"))
	var c := Game.plot_upgrade_cost()
	if c > 0:
		opts.append(["Dig more beds (%d gold)%s" % [c, "" if Game.gold >= c else " -- not enough gold"], func():
			if Game.upgrade_plots():
				Game.message.emit("Your garden now has %d beds." % Game.plot_count())
				Game.save_game()
				_last_sig = ""
				_build_garden()
			garden_menu()])
	opts.append(["Leave it be", hud.close_dialog])
	hud.open_dialog("Your garden", "\n".join(lines), opts)


func bench_menu() -> void:
	var hud = _hud()
	var q: Dictionary = Game.home.get("queue", {})
	var lines := []
	if int(q.get("left", 0)) > 0:
		lines.append(I18n.t("The bench is making %s: %d to go, next in %s.") % [Game.item_name(str(q.get("recipe", ""))), int(q["left"]),
			Game._dur(maxf(0.0, float(q.get("next", 0.0)) - Game._now()))])
	else:
		lines.append(I18n.t("The bench is idle. Set it something to make and it works through it on its own -- one piece every few minutes, whether you're in the deep or away from the game. It takes from your pouch first, then your chest."))
	var opts := []
	if int(q.get("left", 0)) > 0:
		opts.append(["Stop the bench", func():
			Game.stop_queue()
			Game.save_game()
			bench_menu()])
	else:
		var shown := 0
		for r in Game.recipes:
			var n := Game.bench_can_make(r)
			if n <= 0:
				continue
			shown += 1
			if shown > 10:
				break
			opts.append(["Make %s x%d (%d%% each)" % [Game.item_name(str(r["makes"])), n, int(Game.craft_chance(r) * 100)], func():
				Game.message.emit(Game.queue_craft(str(r["makes"]), n))
				Game.save_game()
				bench_menu()])
		if shown == 0:
			lines.append(I18n.t("\n(Nothing you have the materials for, in your pouch or your chest.)"))
	if Game.count("nanite_shard") > 0:
		opts.append(["Experiment with nanites (a shard and one other thing)", experiment_menu])
	# round 27: your own hands at your own bench -- anything with anything, any piece
	opts.insert(0, ["Work at the bench yourself (combine, forge, nanoforge)", func():
		hud.close_dialog()
		hud.open_kit("Bench", "home")])
	opts.append(["Leave it", hud.close_dialog])
	hud.open_dialog("Your workbench", "\n".join(lines), opts)


func experiment_menu(result: String = "") -> void:
	## round 21: a nanite shard and a reagent -- see what the swarm makes of it
	var hud = _hud()
	var tried: Dictionary = Game.flags.get("experiments_tried", {}) if Game.flags.get("experiments_tried", {}) is Dictionary else {}
	var body := (result + "\n\n") if result != "" else ""
	body += I18n.t("You have %d nanite shard%s. Each try costs one, and one of whatever you pair it with. The swarm grows a little whatever happens; the right pairing teaches it an augment. When something of the right element is close, it stirs.") % [
		Game.count("nanite_shard"), "" if Game.count("nanite_shard") == 1 else "s"]
	var opts := []
	if Game.count("nanite_shard") > 0:
		var n := 0
		for id in Game.experiment_reagents():
			n += 1
			if n > 12:
				break
			opts.append(["%s%s (%d)" % [Game.item_name(id), I18n.t("  [tried]") if tried.has(id) else "", Game.count(id)], func():
				var r := Game.experiment(id)
				Game.save_game()
				experiment_menu(r)])
		if n == 0:
			body += I18n.t("\n\n(You have nothing to pair a shard with.)")
	else:
		body += I18n.t("\n\n(No shards left.)")
	opts.append(["Back to the bench", bench_menu])
	hud.open_dialog("Nanite experiments", body, opts)


func chest_menu() -> void:
	var hud = _hud()
	var st: Dictionary = Game.stash_ref()
	var lines := []
	var ids := st.keys()
	ids.sort()
	if ids.is_empty():
		lines.append(I18n.t("The chest is empty."))
	else:
		var parts := []
		for id in ids:
			parts.append("%s x%d" % [Game.item_name(str(id)), int(st[id])])
		lines.append(I18n.t("In the chest: ") + ", ".join(parts))
	lines.append(I18n.t("\nTrophies: %d of %d achievements (+%.1f%% to all your growth).") % [Game.achievements.size(), Game.achievement_defs.size(), Game.achievements.size() * Game.ACHIEVEMENT_BONUS * 100.0])
	var earned := []
	for a in Game.achievement_defs:
		if Game.achievements.has(str(a.get("id", ""))):
			earned.append(str(a.get("name", "")))
	if earned.size() > 0:
		lines.append(I18n.t("On the shelf: ") + ", ".join(earned))
	var opts := [["Put away all your materials", func():
		var n := Game.stash_all_materials()
		Game.message.emit("You put %d things away in the chest." % n if n > 0 else "You've no materials to put away.")
		Game.save_game()
		chest_menu()]]
	for id in ids.slice(0, 10):
		opts.append(["Take %s (%d)" % [Game.item_name(str(id)), int(st[id])], func():
			var n := Game.take_from_stash(str(id))
			if n <= 0:
				Game.message.emit("Your pouch has no room for more %s." % Game.item_name(str(id)))
			Game.save_game()
			chest_menu()])
	opts.append(["Close the chest", hud.close_dialog])
	hud.open_dialog("Your chest", "\n".join(lines), opts)


func post_menu() -> void:
	var hud = _hud()
	var left := Game.post_budget()
	var body := "A post of old timber with a straw head, scarred by everyone who ever stood here.\n\n"
	body += I18n.t("Use your arts here -- F and V -- and each one is real practice (more than an art thrown at nothing, less than one that lands in a fight). It settles into mastery when you rest, like any practice.\n\n")
	body += ("%d minutes of drill left today." % int(ceil(left / 60.0))) if left > 0.0 else "You've drilled all you usefully can today. Come back tomorrow -- or go and find a real fight."
	hud.open_dialog("Training post", body, [["Close", hud.close_dialog]])


func bed_menu() -> void:
	var hud = _hud()
	var body := "Your own bed, in your own tent. A night here mends you, and you wake WELL RESTED: +10% qi and skill growth for half an hour."
	if Game.rested():
		body += I18n.t("\n\nYou're well rested for another %s.") % Game._dur(float(Game.home.get("rested_until", 0.0)) - Game._now())
	body += I18n.t("\n\nBefore you leave for a while, you can plan your time away: meditate, train, gather or work the bench -- it's done when you're back.")
	hud.open_dialog("Your bed", body, [
		["Sleep", func():
			hud.close_dialog()
			Game.rest_at_home()
			Game.save_game()],
		["Plan your time away", func(): hud.open_away_plan()],
		["Not now", hud.close_dialog]])
