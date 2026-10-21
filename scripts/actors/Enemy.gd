extends CharacterBody3D
## A monster. Its stats come from data/enemies.json (by type id), so a
## new monster is a few lines of JSON, not a new script.
##
## Behaviour: stands guard until you come within "aggro" metres and it
## can see you, then paths toward you over the level grid (A*), attacks
## when within "range", and gives up if you get far away.
## Game animals ("passive": true) never start a fight: "flees": true runs
## from you, "retaliates": true fights back once hurt. They're hunted, not
## slain -- Hunting skill, hides and meat. ("model": "beast" draws a
## four-legged creature from simple shapes.)
##
## Round 28 (data/foes.json): monsters fight in STYLES -- brawler, ranged
## (keeps its distance and throws, Bolt.gd), charger (a wind-up you can
## read, then a straight run), guardian (turns blows from the front), skulker
## (unseen until close), swarmer (brings its young), mender (heals the
## others). From floor 2 some in a pack take a VARIANT style; from floor 3
## some are ELITE with affixes (swift, armoured, venomous, vampiric,
## frenzied, splitting, warding, thunderous, gilded). Bosses grow ENRAGED
## at half health.

var _base_scale := Vector3.ONE * 2.0
var level
var etype := "goblin"
var stats := {}
var hp := 1
var cell := Vector2i.ZERO
var home := Vector3.ZERO

var _anim: AnimationPlayer
var _model: Node3D
var _label: Label3D
var _path: Array = []
var _repath := 0.0
var _cooldown := 0.0
var _attacking := 0.0
var _dead := false
var _chasing := false
var _flash := 0.0
var _calm := 0.0          # a wild animal being fed stays put
# round 20: what the arts do to a foe
var _stun := 0.0          # staggered: does nothing (a parry, Collapsing Palm, earth)
var _slow := 0.0          # slowed (water)
var _burn_t := 0.0        # burning (fire): _burn_dps until _burn_t runs out
var _burn_dps := 0.0
var _burn_acc := 0.0
# round 28: how it fights
var style := "brawler"
var affixes := []
var elite := false
var minion := false
var _sd := {}                # the style's numbers (foes.json)
var _t1 := 0.0               # the style's clock: next shot, next charge, next heal
var _t2 := 0.0               # a wind-up in progress (the tell)
var _t3 := 0.0               # thunderous: next stamp
var _t4 := 0.0               # thunderous: the stamp's warning
var _dash := 0.0
var _dash_dir := Vector3.ZERO
var _dash_hit := false
var _revealed := true
var _bar: Node3D                  # round 50: FoeBar.gd under the name
var _matter := "flesh"            # round 52: what a blow knocks loose (FX.matter)
var _model_base := Vector3.ZERO   # round 52: drawn between physics ticks (smooth at any frame rate)
var _label_base := Vector3.ZERO
var _tick_prev := Vector3.ZERO
var _tick_now := Vector3.ZERO
var _tick_pf := -1
var _first_done := false
var _brood_done := false
var _frenzy := false
var _enraged := false
# round 32: poise (break it and the foe staggers, open to a free hit) and a boss's phases
var poise := 0.0
var _poise_rest := 0.0
var _phase := 0
var _tell_ring: MeshInstance3D
var _tell_mat: StandardMaterial3D
# round 60: a foe you can read (Robert: "combat depth")
var _swings := 0
var _heavy_at := 4              # the swing that comes heavy
var _heavy_t := 0.0             # its wind-up (the tell) left
var _heavy_total := 0.75
var _heavy_dir := Vector3.ZERO
var heavy_now := false          # (Player.take_damage: this blow can't be blocked -- only parried or rolled)
var exposed := 0.0              # an opening: it overreached -- every hit lands harder for a moment
var _bm_t := 4.0                # a master's next big move
var _bm_busy := 0.0
var _blink_t := 8.0
var _blink_w := 0.0
var _rally_t := 0.0
var rallied := 0.0              # a Commanding elite's shout: hits harder, moves faster
var sundered := 0.0             # an axe split its armour: it takes more from everything
var weakened := 0.0             # round 122: Withering Gaze -- it hits softer for a while
var weak_mult := 1.0
var sunder_mult := 1.25
var _knock := Vector3.ZERO      # thrown back (a spear's thrust, a halberd's arc)


func setup(lvl, args: Dictionary) -> void:
	level = lvl
	etype = str(args.get("type", "goblin"))
	cell = args.get("cell", Vector2i.ZERO)
	stats = Game.enemies.get(etype, {}).duplicate(true)       # (this one's own numbers: styles and affixes change them)
	minion = bool(args.get("minion", false))
	_roll(args)
	_round30_numbers(args)
	hp = int(stats.get("hp", 20))
	if bool(args.get("dummy", false)):
		_make_dummy()


# ---- round 146: the training dummy -- a post to hit that hits back at nothing ---------------
# It never falls, pays no loot or qi, and keeps a running tally (hits, total, damage per
# second over the last few seconds) that resets when you stop. Weapon practice on it is
# capped each day so it stays a pastime, not a farm.
var _dummy := false
var _dummy_log: Array = []          # [[time, amount], ...]
var _dummy_total := 0
var _dummy_hits := 0
var _dummy_best := 0
var _dummy_idle := 0.0


func _make_dummy() -> void:
	_dummy = true
	affixes = []
	elite = false
	stats["name"] = "Training Dummy"
	stats["hp"] = 999999
	stats["damage"] = 0
	stats["speed"] = 0.0
	stats["aggro"] = 0
	stats["passive"] = true
	stats["dummy"] = true
	stats["flees"] = false
	stats["tameable"] = 0
	stats["qi"] = 0
	stats["loot"] = {}
	stats["tint"] = [0.78, 0.62, 0.38]
	stats["scale"] = 1.1
	hp = 999999


func is_dummy() -> bool:
	return _dummy


func dummy_dps() -> float:
	## damage per second over the last five seconds of hitting
	var now := Time.get_ticks_msec() / 1000.0
	var sum := 0
	var first := now
	for e in _dummy_log:
		if now - float(e[0]) <= 5.0:
			sum += int(e[1])
			first = minf(first, float(e[0]))
	if sum <= 0:
		return 0.0
	return float(sum) / maxf(now - first, 1.0)


func _dummy_hit(amount: int, source: String) -> void:
	if not _revealed:
		_reveal()
	var now := Time.get_ticks_msec() / 1000.0
	_dummy_log.append([now, amount])
	if _dummy_log.size() > 200:
		_dummy_log = _dummy_log.slice(100)
	_dummy_total += amount
	_dummy_hits += 1
	_dummy_idle = 0.0
	_dummy_best = maxi(_dummy_best, amount)
	Game.counters["dummy_best_hit"] = maxf(float(Game.counters.get("dummy_best_hit", 0.0)), float(amount))
	Game.counters["dummy_hits"] = float(Game.counters.get("dummy_hits", 0.0)) + 1.0
	var dps := dummy_dps()
	Game.counters["dummy_best_dps"] = maxf(float(Game.counters.get("dummy_best_dps", 0.0)), dps)
	_flash = 0.12
	if _model:
		_model.scale = _base_scale * 1.06
	Game.sfx_at("hit_flesh", global_position, 0.6)
	var crit := has_meta("_crit_next")
	if crit:
		remove_meta("_crit_next")
	if FX.on():
		var at := global_position + Vector3(0, _mid_height(), 0)
		FX.hit(at, Color(1.0, 0.82, 0.5), amount * 6 >= 60)
		FX.number(at + Vector3(0, 0.6 + _mid_height() * 0.4, 0), amount, "crit" if crit else ("art" if Game.is_art_source(source) else "normal"))
	# a little practice, a few hundred blows a day at most
	if source.begins_with("you") or Game.is_art_source(source):
		var key := "dummy_xp:" + Game.today()
		var done := float(Game.counters.get(key, 0.0))
		if done < 300.0:
			Game.counters[key] = done + 1.0
			Game.train_weapon(1)
	_dummy_label()


func _dummy_label() -> void:
	if _label == null:
		return
	_label.text = "%s\n%s" % [I18n.t("Training Dummy"), I18n.t("%d hits   total %d   best %d   DPS %.0f") % [_dummy_hits, _dummy_total, _dummy_best, dummy_dps()]]


func _dummy_tick(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= 20.0 * delta
	else:
		velocity.y = 0.0
	velocity.x = 0.0
	velocity.z = 0.0
	move_and_slide()
	if _flash > 0.0:
		_flash -= delta
		if _flash <= 0.0 and _model:
			_model.scale = _base_scale
	if _dummy_hits > 0:
		_dummy_idle += delta
		if _dummy_idle > 6.0:          # it forgets: ready for the next round
			_dummy_hits = 0
			_dummy_total = 0
			_dummy_best = 0
			_dummy_log.clear()
			if _label:
				_label.text = I18n.t("Training Dummy")


func _ldef() -> Dictionary:
	return level.def if level != null and level.get("def") is Dictionary else {}


var _treasure := false
var champion := ""
var drops_key := ""
var hunter := false          # round 44: a Hollow Clan hunter


func _round30_numbers(args: Dictionary) -> void:
	## round 30: harder after an ascension; the daily trial's twists; and a
	## Treasure Spirit (a world event) is a gilded runner, not a fighter
	if bool(args.get("treasure", false)):
		_treasure = true
		stats["name"] = "Treasure Spirit"
		stats["passive"] = true
		stats["flees"] = true
		stats["tameable"] = 0
		stats["speed"] = float(stats.get("speed", 4.0)) * 1.5
		stats["tint"] = [1.0, 0.82, 0.25]
		var d := maxi(_depth(), 1)
		stats["loot"] = {"gold": [40 * d, 90 * d], "qi_pill": [1, 2], "healing_salve": [1, 2]}
		affixes = []
		elite = false
		return
	if bool(stats.get("passive", false)):
		return
	if bool(args.get("hunter", false)):
		# round 44: the Hollow Clans' hunters -- they've come for you
		hunter = true
		stats["name"] = "%s (clan hunter)" % str(stats.get("name", etype))
		stats["tint"] = [0.95, 0.45, 0.4]
		stats["qi"] = float(stats.get("qi", 5)) * 1.5
	if str(args.get("champion", "")) != "":
		# round 32: the floor's Keeper -- named, bigger, and it carries the key
		champion = str(args["champion"])
		stats["name"] = champion
		stats["qi"] = float(stats.get("qi", 5)) * 2.0
		stats["gear_chance"] = 1.0
		drops_key = str(args.get("drops_key", ""))
	var cm: float = Game.challenge_mult()
	var ld := _ldef()
	var dcv := _depth()                                                                    # round 34: the curve
	var ramp: float = Game.adaptive_ramp(dcv)                                              # round 136: up to +25% as you outgrow the floor
	var AD: Dictionary = Game.combat_data().get("adaptive", {})
	var hp_ad := 1.0 + ramp * float(AD.get("hp_share", 1.0))
	var dmg_ad := 1.0 + ramp * float(AD.get("damage_share", 0.8))
	stats["hp"] = maxi(1, int(round(float(stats.get("hp", 20)) * cm * hp_ad * Game.level_mod(ld, "foe_hp") * Game.curve_mult(dcv, "hp"))))
	stats["damage"] = maxi(1, int(round(float(stats.get("damage", 5)) * (1.0 + (cm - 1.0) * 0.8) * dmg_ad * Game.level_mod(ld, "foe_damage") * Game.curve_mult(dcv, "damage"))))
	var dfc = Game.sys("difficulty")                                                       # round 139: your own difficulty (offline game)
	if dfc != null and not dfc.is_standard():
		stats["hp"] = maxi(1, int(round(float(stats["hp"]) * dfc.foe_hp())))
		stats["damage"] = maxi(1, int(round(float(stats["damage"]) * dfc.foe_damage())))
	stats["speed"] = float(stats.get("speed", 3.0)) * Game.level_mod(ld, "foe_speed")


func _depth() -> int:
	if level != null and level.get("def") is Dictionary:
		return int(level.def.get("depth", Game.depth))
	return int(Game.depth)


func _level_id() -> String:
	if level != null and level.get("level_id") != null:
		return str(level.level_id)
	return ""


func _roll(args: Dictionary) -> void:
	## what kind of fighter this one is (foes.json)
	var F: Dictionary = Game.foes_data()
	if bool(stats.get("passive", false)):
		return
	var d := _depth()
	var natural: String = Game.foe_style(etype, stats)
	# floor 1 teaches the basics: plain brawlers there, whatever they are elsewhere
	style = str(args.get("style", natural if (d >= 2 or not bool(args.get("roll", false))) else "brawler"))
	if bool(stats.get("boss", false)):
		style = "brawler"
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s|%s|%s" % [_level_id(), str(cell), etype])
	var variant := false
	if bool(args.get("roll", false)) and not bool(stats.get("boss", false)) and not minion:
		var V: Dictionary = F.get("variant", {})
		if d >= int(V.get("from_depth", 2)) and (rng.randf() < float(V.get("chance", 0.3)) or "veteran" in _ldef().get("trial_mods", [])):
			var pool: Array = (V.get("pool", []) as Array).filter(func(x): return str(x) != style)
			if pool.size() > 0:
				style = str(pool[rng.randi() % pool.size()])
				variant = true
		var E: Dictionary = F.get("elite", {})
		var ch := minf(float(E.get("base", 0.05)) + float(E.get("per_depth", 0.005)) * d, float(E.get("max", 0.2)))
		ch = minf(ch * Game.level_mod(_ldef(), "elite_mult"), 0.75)       # round 30: a Blood Moon, the trial's twists
		ch = minf(ch + (Game.curve_mult(d, "elite") - 1.0), 0.75)         # round 34: more of them, deeper
		if d >= int(E.get("from_depth", 3)) and rng.randf() < ch:
			var keys: Array = (F.get("affixes", {}) as Dictionary).keys()
			keys.sort()
			var n := 2 if d >= int(E.get("two_affixes_from", 8)) else 1
			while affixes.size() < n and keys.size() > 0:
				var k: String = keys[rng.randi() % keys.size()]
				keys.erase(k)
				affixes.append(k)
	if args.has("affixes"):
		affixes = (args["affixes"] as Array).duplicate()
	if minion and not args.has("affixes"):
		affixes = []
	elite = affixes.size() > 0
	_sd = F.get("styles", {}).get(style, {})
	# its numbers
	stats["hp"] = int(round(float(stats.get("hp", 20)) * float(_sd.get("hp", 1.0)) * float(args.get("hp_mult", 1.0))))
	stats["speed"] = float(stats.get("speed", 3.0)) * float(_sd.get("speed", 1.0))
	if args.has("scale_mult"):
		stats["scale"] = float(stats.get("scale", 1.0)) * float(args["scale_mult"])
	if elite:
		var E2: Dictionary = F.get("elite", {})
		stats["hp"] = int(round(float(stats["hp"]) * float(E2.get("hp", 2.2))))
		stats["damage"] = int(round(float(stats.get("damage", 5)) * float(E2.get("damage", 1.25))))
		stats["qi"] = float(stats.get("qi", 5)) * float(E2.get("qi", 3.0))
		stats["gear_chance"] = float(E2.get("gear_chance", 0.4))
		for a in affixes:
			if a == "frenzied":
				continue           # (frenzy comes later, when it's hurt)
			var A: Dictionary = F.get("affixes", {}).get(a, {})
			stats["speed"] = float(stats["speed"]) * float(A.get("speed", 1.0))
			stats["cooldown"] = float(stats.get("cooldown", 1.4)) * float(A.get("cooldown", 1.0))
	if minion:
		stats["gear_chance"] = 0.0
		stats["loot"] = {}
		stats["qi"] = float(stats.get("qi", 5)) * 0.3
	# a name that says what it is
	var nm := str(stats.get("name", etype))
	if variant and str(_sd.get("name", "")) != "":
		nm = ("%s %s" % [nm, _sd["name"]]) if style in ["ranged", "guardian"] else ("%s %s" % [_sd["name"], nm])
	if minion and bool(args.get("young", false)):
		nm = "Young " + nm
	var pre := []
	for a in affixes:
		pre.append(str(F.get("affixes", {}).get(a, {}).get("name", a)))
	if pre.size() > 0:
		nm = "%s %s" % [" ".join(pre), nm]
	stats["name"] = nm
	_revealed = style != "skulker"
	_t1 = 1.0 + rng.randf() * 1.5
	_t3 = float(F.get("affixes", {}).get("thunderous", {}).get("every", 7.0))
	var ev: Array = _H().get("every", [3, 5])
	_heavy_at = rng.randi_range(int(ev[0]), int(ev[1]))
	_bm_t = float(Game.combat_data().get("boss_moves", {}).get("first", 4.0))
	_blink_t = float(F.get("affixes", {}).get("blinking", {}).get("every", 8.0)) * (0.5 + rng.randf() * 0.5)


const Mon := preload("res://scripts/actors/Monster.gd")
const FX := preload("res://scripts/fx/FX.gd")
var body_kind := "beast"            # what it's built as: kenney | imp | puglin | golem | human | beast (round 29)


func _ready() -> void:
	add_to_group("enemy")
	if bool(stats.get("passive", false)) and int(stats.get("tameable", 0)) > 0:
		add_to_group("interactable")
	home = global_position
	var s := float(stats.get("scale", 1.0))
	var t: Array = stats.get("tint", [1, 1, 1])
	if str(stats.get("model", "orc")) == "beast":
		_model = make_beast(Color(float(t[0]), float(t[1]), float(t[2])), str(stats.get("name", etype)))
		_model.scale = Vector3.ONE * 2.0 * s
		add_child(_model)
	else:
		var which := "character-orc.glb" if str(stats.get("model", "orc")) == "orc" else "character-human.glb"
		var D = preload("res://scripts/world/Dress.gd")
		if which == "character-human.glb":
			# a rival cultivator: a person (realistic at Medium+), their sect's
			# colour, their own weapon
			var rspec: Dictionary = D.spec_for(str(stats.get("name", "")), "villager", {"robe": t, "sash": [0.15, 0.12, 0.12],
				"hair": "topknot", "held": str(stats.get("kind", "sword"))})
			_model = preload("res://scripts/core/Art.gd").person(rspec, s)
			add_child(_model)
			if not _model.has_meta("human"):
				_tint(_model, Color(float(t[0]), float(t[1]), float(t[2])))
			else:
				body_kind = "human"
				# a skeleton is bone, a wraith is light you can half see through
				# (round 29) -- the skin goes on before the clothes, so a robe stays cloth
				var hskin: String = Mon.skin_for(stats)
				Mon.apply_skin(_model, hskin, Color(float(t[0]), float(t[1]), float(t[2])))
				if hskin in ["bone", "spectral", "crystal", "stone"]:
					rspec.erase("hat")          # (a skeleton in a straw hat looked silly)
			D.dress(_model, rspec)
		else:
			# round 29 (Robert: "less blocky and more smooth"): the Kenney orc
			# becomes a real body -- an Imp or a Puglin from the Bestiary, or a
			# golem (a human body in stone, clay, brass, crystal...) -- at
			# Medium graphics and up. Low keeps the toy.
			var tc := Color(float(t[0]), float(t[1]), float(t[2]))
			var want: String = Mon.pick(stats) if preload("res://scripts/core/Art.gd").style != "kenney" else ""
			if want in ["imp", "puglin"] and Mon.available(want):
				body_kind = want
				_model = Mon.make(want, absi(hash(str(stats.get("name", etype)))) % 3, tc)
				_model.scale *= s
				add_child(_model)
			elif want == "golem" and preload("res://scripts/actors/Human.gd").available():
				body_kind = "golem"
				var gspec: Dictionary = D.spec_for(str(stats.get("name", "")), "villager", {"robe": t, "hair": "buzzed"})
				_model = preload("res://scripts/core/Art.gd").person(gspec, s * 1.1)
				add_child(_model)
				var gskin: String = Mon.skin_for(stats)
				Mon.apply_skin(_model, gskin if gskin != "" else "stone", tc)
			else:
				body_kind = "kenney"
				_model = load("res://assets/kenney/mini-dungeon/" + which).instantiate()
				_model.scale = Vector3.ONE * 2.0 * s
				add_child(_model)
				_tint(_model, tc)
				D.dress_monster(_model, stats)
	_matter = FX.matter_kind(stats)
	_model_base = _model.position
	_base_scale = _model.scale         # (a realistic rival is drawn at 1x, a Kenney figure at 2x: the hit-flash swells from whichever)
	_anim = _find_anim(_model)
	if _anim:
		_anim.playback_default_blend_time = 0.18      # round 37: moves ease into each other
	_loop(["idle", "walk", "sprint"])
	_play("idle")

	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.45 * s
	cap.height = 1.5 * s
	shape.shape = cap
	shape.position = Vector3(0, 0.75 * s, 0)
	add_child(shape)

	_dress_style()
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.pixel_size = 0.009
	_label.no_depth_test = true
	_label.position = Vector3(0, 1.9 * s + 0.2, 0)
	_label.font_size = 30 if not stats.get("boss", false) else 44
	_label.outline_size = 8
	_label.modulate = Color(1.0, 0.55, 0.45) if not stats.get("boss", false) else Color(1.0, 0.35, 0.9)
	var tf := preload("res://scripts/core/UiStyle.gd").font("bold")
	if tf:
		_label.font = tf
	add_child(_label)
	_label_base = _label.position
	# round 50: health as a slim bar under the name (FoeBar.gd), not numbers
	_bar = preload("res://scripts/ui/FoeBar.gd").new()
	_bar.position = Vector3(0, -0.24 if not stats.get("boss", false) else -0.32, 0)
	_label.add_child(_bar)
	_bar.setup(_label.modulate if not elite else Color(1.0, 0.82, 0.3), elite or bool(stats.get("boss", false)))
	_update_label()
	if elite:
		_label.modulate = Color(1.0, 0.82, 0.3)
		var A0: Dictionary = Game.foes_data().get("affixes", {}).get(str(affixes[0]), {})
		var ac: Array = A0.get("color", [1, 0.8, 0.3])
		var eg := OmniLight3D.new()
		eg.light_color = Color(float(ac[0]), float(ac[1]), float(ac[2]))
		eg.omni_range = 4.5
		eg.light_energy = 1.4
		eg.position = Vector3(0, 1.2, 0)
		add_child(eg)
		FX.aura(self, eg.light_color, 1.8 * s)
	if not _revealed:
		_model.visible = false
		_label.visible = false
	if _treasure:
		FX.aura(self, Color(1.0, 0.85, 0.25), 1.2, 30)
		get_tree().create_timer(150.0).timeout.connect(func():
			if is_instance_valid(self) and not _dead:
				Game.message.emit("The Treasure Spirit slips into the rock and is gone.")
				queue_free())
	if stats.get("boss", false):
		var aura := OmniLight3D.new()
		var c := Color(float(t[0]), float(t[1]), float(t[2]))
		aura.light_color = c
		aura.omni_range = 6.0
		aura.light_energy = 1.2
		aura.position = Vector3(0, 1.5, 0)
		add_child(aura)
		FX.aura(self, c.lerp(Color(1.0, 0.6, 0.9), 0.4), 2.2 * s, 40)


# ---- round 150: far creatures sleep (the open world is wide, and every creature is a rigged body) ----------
const SLEEP_M := 56.0
const WAKE_M := 48.0
var _asleep := false
var _sleep_t := 0.0
var _pl_ref: Node3D = null


func _sleeps_when_far() -> bool:
	## only in the open country; never a boss, a hunter after you, a named quarry or a creature already on you
	return level != null and str(_ldef().get("theme", "")) == "wilds" and not _dummy and not bool(stats.get("boss", false)) and not hunter \
		and not has_meta("quest_hunt") and not _chasing


func _check_sleep(delta: float) -> bool:
	## true = stay asleep this tick
	_sleep_t -= delta
	if _sleep_t > 0.0:
		return _asleep
	_sleep_t = 0.35 + randf() * 0.2
	if _pl_ref == null or not is_instance_valid(_pl_ref):
		_pl_ref = get_tree().get_first_node_in_group("player") as Node3D
	if _pl_ref == null:
		return false
	var d: float = global_position.distance_to(_pl_ref.global_position)
	if not _asleep and d > SLEEP_M and _sleeps_when_far():
		_asleep = true
		visible = false
		if _anim:
			_anim.pause()
	elif _asleep and (d < WAKE_M or not _sleeps_when_far()):
		_asleep = false
		visible = true
		if _anim:
			_anim.play("idle") if _anim.has_animation("idle") else _anim.play()
	return _asleep


func _physics_process(delta: float) -> void:
	if _dead:
		return
	if _check_sleep(delta):
		return
	if _dummy:
		_dummy_tick(delta)
		return
	if not is_on_floor():
		velocity.y -= 20.0 * delta
	else:
		velocity.y = 0.0
	_cooldown = max(_cooldown - delta * (0.6 if _slow > 0.0 else 1.0), 0.0)
	_attacking = max(_attacking - delta, 0.0)
	if exposed > 0.0:
		exposed = maxf(exposed - delta, 0.0)
		if exposed <= 0.0:
			_update_label()
	rallied = maxf(rallied - delta, 0.0)
	sundered = maxf(sundered - delta, 0.0)
	if weakened > 0.0:
		weakened = maxf(weakened - delta, 0.0)
		if weakened <= 0.0:
			weak_mult = 1.0
	if _knock.length() > 0.3:
		velocity.x = _knock.x
		velocity.z = _knock.z
		_knock = _knock.move_toward(Vector3.ZERO, 28.0 * delta)
		move_and_slide()
		return
	_slow = maxf(_slow - delta, 0.0)
	if _psn_t > 0.0:
		_psn_t -= delta
		_psn_acc += _psn_dps * delta
		if _psn_acc >= 1.0:
			var pd := int(_psn_acc)
			_psn_acc -= pd
			take_damage(pd, "poison")
			if _dead:
				return
	if _burn_t > 0.0:
		_burn_t -= delta
		_burn_acc += _burn_dps * delta
		if _burn_acc >= 1.0:
			var d := int(_burn_acc)
			_burn_acc -= d
			take_damage(d, "burning")
			if _dead:
				return
	if _stun > 0.0:
		_stun -= delta
		velocity.x = 0.0
		velocity.z = 0.0
		if not is_on_floor():
			velocity.y -= 20.0 * delta
		move_and_slide()
		if _stun <= 0.0:
			_update_label()
		return
	_poise_rest = maxf(_poise_rest - delta, 0.0)
	if _poise_rest <= 0.0 and poise > 0.0:
		poise = maxf(poise - poise_max() * float(Game.combat_data().get("poise", {}).get("regen_per_sec", 0.35)) * delta, 0.0)
	if _flash > 0.0:
		_flash -= delta
		if _flash <= 0.0:
			_model.scale = _base_scale

	var player = get_tree().get_first_node_in_group("player")
	if player == null or player.dead:
		if _heavy_t > 0.0:
			_heavy_t = 0.0
			_tell(false)
		_idle()
		move_and_slide()
		return
	if _heavy_t > 0.0:
		_heavy_tick(delta, player)
		move_and_slide()
		return
	if "commanding" in affixes:
		_rally(delta)
	var to_player: Vector3 = player.global_position - global_position
	to_player.y = 0.0
	var dist := to_player.length()
	var aggro := float(stats.get("aggro", 9.0))

	if bool(stats.get("passive", false)) and not (_chasing and bool(stats.get("retaliates", false))):
		_chasing = false
		_calm = maxf(_calm - delta, 0.0)
		if bool(stats.get("flees", false)) and dist < aggro and _calm <= 0.0:
			var away := -to_player.normalized()
			var spd0 := float(stats.get("speed", 4.0))
			velocity.x = away.x * spd0
			velocity.z = away.z * spd0
			_face(away)
		else:
			_idle()
		move_and_slide()
		return
	if not _chasing and dist < aggro and _can_see(player):
		_chasing = true
	if not _revealed and dist < float(_sd.get("reveal", 4.5)):
		_reveal()
	if _chasing and dist > aggro * 2.2:
		_chasing = false

	if not _chasing:
		_idle()
		move_and_slide()
		return

	if style == "swarmer" and not _brood_done and not minion:
		_brood()
	if "thunderous" in affixes and _thunder(delta, player, dist):
		move_and_slide()
		return
	if bool(stats.get("boss", false)) and _boss_move(delta, player, dist):
		move_and_slide()
		return
	if "blinking" in affixes and _blink(delta, player, dist):
		move_and_slide()
		return
	if _style_tick(delta, player, to_player, dist):
		move_and_slide()
		return
	_face(to_player)
	var reach := float(stats.get("range", 1.8)) + 0.5
	if dist <= reach:
		velocity.x = 0.0
		velocity.z = 0.0
		if _cooldown <= 0.0 and exposed <= 0.0:
			_attack(player)
		elif _attacking <= 0.0:
			_play("idle")
	elif _attacking <= 0.0:
		_repath -= delta
		if _repath <= 0.0:
			_repath = 0.4
			_path = level.path_between(level.world_to_cell(global_position), level.world_to_cell(player.global_position))
			if _path.size() > 0:
				_path.remove_at(0)
		var target: Vector3 = player.global_position
		if _path.size() > 1:
			target = level.cell_to_world(_path[0])
			if Vector2(target.x - global_position.x, target.z - global_position.z).length() < 0.5:
				_path.remove_at(0)
		var dir := Vector3(target.x - global_position.x, 0, target.z - global_position.z).normalized()
		var spd := float(stats.get("speed", 3.0)) * (0.6 if _slow > 0.0 else 1.0) * (_rally_speed() if rallied > 0.0 else 1.0)
		velocity.x = dir.x * spd
		velocity.z = dir.z * spd
		_play("walk" if spd < 3.6 else "sprint")
	move_and_slide()


func _idle() -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	if _attacking <= 0.0:
		_play("idle")


func _attack(player) -> void:
	if _can_heavy():
		_swings += 1
		if _swings >= _heavy_at:
			_start_heavy(player)
			return
	_cooldown = float(stats.get("cooldown", 1.4))
	_attacking = 0.6
	_play("attack-melee-right", true)
	Game.sfx_at("swing", global_position, 0.4)
	# the blow lands a moment into the swing -- step back in time and it misses
	get_tree().create_timer(0.3).timeout.connect(func():
		if _dead or not is_instance_valid(player) or _stun > 0.0:
			return            # staggered mid-swing: the blow never comes
		var d: float = (player.global_position - global_position).length()
		if d <= float(stats.get("range", 1.8)) + 0.8:
			var mult := 1.0
			if style == "skulker" and not _first_done:
				mult = float(_sd.get("first", 1.6))      # out of nowhere
			_first_done = true
			deal(player, int(round(float(stats.get("damage", 5)) * mult))))


func _process(_delta: float) -> void:
	## round 52: drawn where it was between the last two physics ticks -- a
	## beast running across the screen is smooth at any frame rate
	if _model == null or _dead or _asleep:
		return
	var pf := Engine.get_physics_frames()
	if pf != _tick_pf:
		var p := global_position
		_tick_prev = _tick_now if _tick_pf >= 0 and p.distance_to(_tick_now) < 3.0 else p
		_tick_now = p
		_tick_pf = pf
	var off := _tick_prev.lerp(_tick_now, Engine.get_physics_interpolation_fraction()) - global_position
	if off.length() > 2.0:
		off = Vector3.ZERO
	_model.position = _model_base + off
	if _label:
		_label.position = _label_base + off


func _can_see(player) -> bool:
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3(0, 1.0, 0)
	var to: Vector3 = player.global_position + Vector3(0, 1.0, 0)
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.exclude = [get_rid()]
	var hit := space.intersect_ray(q)
	return hit.is_empty() or hit.get("collider") == player


var _last_hit_by := ""


func stagger(secs: float) -> void:
	if _dead:
		return
	_stun = maxf(_stun, secs * (0.5 if bool(stats.get("boss", false)) else 1.0) * _ward())
	_attacking = 0.0
	if _heavy_t > 0.0:
		_heavy_t = 0.0                  # round 60: knocked out of its wind-up -- the blow never comes
		_tell(false)
		if _model:
			_model.scale = _base_scale
		if FX.on():
			FX.word(global_position + Vector3(0, _mid_height() + 1.0, 0), "INTERRUPTED", Color(0.7, 0.9, 1.0), 44)
		Game.log_event("foe_interrupted", {"type": etype})
	_play("idle")


func slow(secs: float) -> void:
	_slow = maxf(_slow, secs * _ward())


func burn(total: int, secs: float) -> void:
	if total <= 0 or secs <= 0.0:
		return
	secs *= _ward()
	_burn_dps = maxf(_burn_dps if _burn_t > 0.0 else 0.0, float(total) / secs)
	_burn_t = maxf(_burn_t, secs)


var _psn_t := 0.0          # round 138: poisoned (a coating): _psn_dps until _psn_t runs out
var _psn_dps := 0.0
var _psn_acc := 0.0


func poison(total: int, secs: float) -> void:
	## a coated blade's venom: a little at a time, capped per second, and a master shrugs half of it off
	if total <= 0 or secs <= 0.0 or _dead:
		return
	var P = Game.sys("poison")
	if P == null:
		return
	if bool(stats.get("boss", false)):
		secs *= float(P.data.get("boss_dur_mult", 0.5))
	secs *= _ward()
	var cap: float = P.foe_cap_dps(self)
	_psn_dps = minf(maxf(_psn_dps if _psn_t > 0.0 else 0.0, float(total) / secs) + (float(total) / secs) * 0.25 * (1.0 if _psn_t > 0.0 else 0.0), cap)
	_psn_t = maxf(_psn_t, secs)


func staggered() -> bool:
	return _stun > 0.0


func take_damage(amount: int, _source: String = "") -> void:
	if _dead:
		return
	if _dummy:
		_dummy_hit(amount, _source)
		return
	_last_hit_by = _source
	amount = _shielded(amount, _source)
	if "armoured" in affixes:
		amount = maxi(1, int(round(amount * float(Game.foes_data().get("affixes", {}).get("armoured", {}).get("taken", 0.6)))))
	if not _revealed:
		_reveal()
	if exposed > 0.0:
		amount = int(round(amount * float(_H().get("opening_mult", 1.5))))     # round 60: it left itself open
	if sundered > 0.0:
		amount = int(round(amount * sunder_mult))
	if _source.begins_with("you") and Game.sys("floorrun"):
		Game.sys("floorrun").note_hit(amount)          # round 61: the floor's hardest blow
	hp -= amount
	_after_hurt()
	Game.sfx_at("hit_heavy" if bool(stats.get("boss", false)) else "hit_flesh", global_position, 0.6)
	_chasing = true
	_flash = 0.12
	var crit := has_meta("_crit_next")          # round 52: the player's blow struck true (the number says so)
	if crit:
		remove_meta("_crit_next")
	if FX.on():
		# sparks where it landed: a warm spray from a blade, blue from qi, orange from a burn
		var hc := Color(1.0, 0.82, 0.5)
		if _source == "burning":
			hc = Color(1.0, 0.5, 0.15)
		elif _source == "poison":
			hc = Color(0.5, 1.0, 0.4)
		elif Game.is_art_source(_source):
			hc = Color(0.55, 0.85, 1.0)
		var big := amount * 6 >= int(stats.get("hp", 10))
		var at := global_position + Vector3(0, _mid_height(), 0)
		FX.hit(at, hc, big)
		# round 52: what this creature is made of comes off it, away from the
		# blow -- and the number
		var pl = get_tree().get_first_node_in_group("player") if is_inside_tree() else null
		var away: Vector3 = (global_position - pl.global_position) if pl else Vector3.ZERO
		away.y = 0.0
		if _source != "burning":
			FX.matter(at, _matter, away, big)
		FX.number(at + Vector3(0, 0.6 + _mid_height() * 0.4, 0), amount, "crit" if crit else ("burn" if _source == "burning" else ("art" if Game.is_art_source(_source) else "normal")))
	_model.scale = _base_scale * 1.08
	_update_label()
	if hp <= 0:
		_die()


func _mid_height() -> float:
	## about where its chest is
	var s := float(stats.get("scale", 1.0))
	return s * (0.5 if body_kind == "beast" else 1.05)


func _boss_phases(mx: float) -> void:
	## round 32: a floor's master changes as it's worn down -- new tricks
	## at two thirds and a third, said aloud
	if not bool(stats.get("boss", false)) or hp <= 0:
		return
	var phases: Array = Game.combat_data().get("boss_phases", [])
	while _phase < phases.size() and hp <= mx * float(phases[_phase].get("at", 0.0)):
		var ph: Dictionary = phases[_phase]
		_phase += 1
		for a in ph.get("gain", []):
			if not (str(a) in affixes):
				affixes.append(str(a))
				if str(a) == "frenzied":
					_frenzy = false         # (so _after_hurt's frenzy fires on the next hurt)
		elite = affixes.size() > 0
		_t3 = 1.5
		Game.banner.emit(str(ph.get("name", "PHASE")), Color(1.0, 0.35, 0.9))
		Game.message.emit(str(ph.get("text", "%s changes.")) % stats.get("name", etype))
		Game.sfx_at("bell", global_position, 1.0)
		FX.ring(global_position, Color(1.0, 0.35, 0.9), 5.0, 0.6)
		Game.Hook.moment(0.3, 0.35, 0.3)                 # round 126: the world holds its breath as the master changes
		if int(ph.get("brood", 0)) > 0 and level != null:
			for i in int(ph.get("brood", 0)):
				var a := TAU * float(i) / float(int(ph["brood"])) + 0.4
				var at := global_position + Vector3(cos(a), 0, sin(a)) * 2.2
				var m = level._spawn_script("res://scripts/actors/Enemy.gd", at, {"type": etype, "cell": level.world_to_cell(at), "minion": true, "style": "brawler", "hp_mult": 0.2, "scale_mult": 0.55, "young": true})
				if m:
					m._chasing = true
		Game.log_event("boss_phase", {"type": etype, "phase": _phase})


func _die() -> void:
	_dead = true
	Game.sfx_at("thud", global_position, 0.7)
	FX.puff(global_position + Vector3(0, _mid_height() * 0.6, 0), Color(0.5, 0.48, 0.45), clampf(float(stats.get("scale", 1.0)), 0.6, 2.5))
	var plq = get_tree().get_first_node_in_group("player") if is_inside_tree() else null
	if plq and not bool(stats.get("passive", false)):
		FX.qi_stream(global_position + Vector3(0, _mid_height(), 0), plq, 2.0 if bool(stats.get("boss", false)) else (1.4 if elite else 1.0))      # round 52: its qi, flowing into you
	remove_from_group("enemy")
	for c in get_children():
		if c is CollisionShape3D:
			c.set_deferred("disabled", true)
	_label.visible = false
	_play("die", true)
	preload("res://scripts/fx/OwnFX.gd").dissolve(_model)          # r121: burns away from one side as it falls
	if _model and _model.has_method("die"):
		_model.die()            # a beast falls on its side
	Game.record_kill(etype)
	Game.loot_source = etype                      # round 137: the bestiary learns what it drops
	Game.clear_loot_source.call_deferred()
	if hunter:
		Game.log_event("hunter_kill", {"type": etype})
	_round30_death()
	if elite:
		Game.log_event("elite_kill", {"type": etype, "affixes": affixes})
		if "gilded" in affixes:
			var G0: Dictionary = Game.foes_data().get("affixes", {}).get("gilded", {})
			var gl: Dictionary = (stats.get("loot", {}) as Dictionary).duplicate()
			if gl.has("gold") and gl["gold"] is Array:
				gl["gold"] = [int(gl["gold"][0] * float(G0.get("gold", 3.0))), int(gl["gold"][1] * float(G0.get("gold", 3.0)))]
			else:
				gl["gold"] = [20 * maxi(_depth(), 1), 40 * maxi(_depth(), 1)]
			for i in int(G0.get("extra_loot", 1)):
				Game.roll_loot(gl)
		if "splitting" in affixes:
			_split()
		if "volatile" in affixes:
			_volatile()
	if Game.is_art_source(_last_hit_by):
		Game.glimpse("art_kill")       # killing with your qi teaches it to narrow (Severing Finger)
	if _last_hit_by.begins_with("you"):
		Game.train_weapon(0, int(stats.get("hp", 10)))     # finishing it teaches most
	if bool(stats.get("passive", false)):
		# a hunt: the skill grows, and a skilled hunter (and a hardy one)
		# takes more from it
		var hl := Game.skill_level("hunting")
		Game.add_skill_xp("hunting", 8.0 + float(stats.get("hp", 10)) / 6.0, "hunting")
		Game.guild_event("gather")
		if randf() < hl * 0.05 + Game.skill_level("survival") * 0.02:
			Game.roll_loot(stats.get("loot", {}))
	var hk := Game.tech_effect("heal_on_kill", 0.0)
	if hk > 0:
		Game.heal(int(hk))
	Game.add_qi(float(stats.get("qi", 5)) * Game.KILL_QI_MULT * Game.diff_reward(), I18n.t("defeated ") + str(stats.get("name", etype)))     # fighting: the main road to qi
	Game.drop_pos = global_position                    # round 61: a rare find's beam rises here
	Game.roll_loot(stats.get("loot", {}))
	if randf() < Game.diff_reward() - 1.0:                                      # round 139: a harder road pays in finds
		Game.roll_loot(stats.get("loot", {}))
	# weapons and armour drop too -- a boss always leaves something
	if not bool(stats.get("passive", false)):
		var d: int = int(level.def.get("depth", Game.depth)) if level != null else int(Game.depth)
		if bool(stats.get("boss", false)):
			Game.drop_gear(d, 2)
		elif randf() < float(stats.get("gear_chance", Game.BRUTE_GEAR_CHANCE if int(stats.get("hp", 0)) >= Game.brute_hp_line(d) else Game.GEAR_CHANCE)):
			Game.drop_gear(d, 0)
	if stats.get("boss", false):
		Game.boss_fell(not Game.has_flag("%s:boss:%s" % [level.level_id, etype]))
		Game.set_flag("%s:boss:%s" % [level.level_id, etype])
		Game.message.emit("%s has fallen!" % stats.get("name", etype))
	FX.sink(self, 1.3)               # the body settles into the ground, then is gone


func _round30_death() -> void:
	## round 30: your blood's kin, a bloodline essence, a second share of loot
	## (Qilin luck, a Blood Moon, the trial's twists), and the daily trial
	Game.blood_kill(stats)
	if champion != "":
		Game.set_flag("%s:keeper" % str(level.level_id) if level else "keeper")      # round 57: a floor's Keeper dies once
		Game.log_event("keeper_kill", {"type": etype, "name": champion})
		Game.message.emit("%s falls." % champion)
		if drops_key != "":
			Game.add_item(drops_key, 1)
			Game.message.emit("FOUND: %s -- the gate on this floor opens to it." % Game.item_name(drops_key))
			Game.sfx("pickup")
	if bool(stats.get("boss", false)):
		Game.log_event("boss_kill", {"type": etype})
	var sd := stats.duplicate()
	sd["elite"] = elite
	var ess := Game.blood_essence_drop(sd, _depth())
	if ess != "":
		Game.message.emit("FOUND: %s -- it's still warm." % Game.item_name(ess))
		FX.hit(global_position + Vector3(0, 1.0, 0), Color(0.9, 0.1, 0.15), true)
	if randf() < Game.tech_effect("loot_luck", 0.0):
		Game.roll_loot(stats.get("loot", {}))
	var lm := Game.level_mod(_ldef(), "loot_mult") - 1.0
	if lm > 0.0 and randf() < lm:
		Game.roll_loot(stats.get("loot", {}))
	if _treasure:
		Game.message.emit("The Treasure Spirit bursts into coins!")
		FX.ring(global_position, Color(1.0, 0.85, 0.25), 3.0)
		Game.log_event("treasure_spirit", {})
	if Game.in_trial():
		Game.trial_note_kill(elite)
		if not bool(stats.get("passive", false)):
			Game.trial_check_clear.call_deferred(get_tree())


static func make_beast(c: Color, beast_name: String = "") -> Node3D:
	## An animal built to its kind, smooth and moving (Beast.gd, round 29).
	return preload("res://scripts/actors/Beast.gd").build(beast_name, c)


# ---- taming: feed a wild animal enough and it stays ----------------------

func _feed_key() -> String:
	return Game.flag_key(level.level_id, cell, "fed:" + etype)


func prompt() -> String:
	var need := int(stats.get("tameable", 0))
	var fed := int(Game.counters.get(_feed_key(), 0.0))
	if not Game.can_tame_more():
		return I18n.t("A wild %s. (Your contracts are full: %d. Taming opens more; or release one.)") % [str(stats.get("name", etype)).to_lower(), Game.contract_cap()]
	if Game.count("raw_meat") <= 0:
		return I18n.t("A wild %s. It might trust you -- with food.") % str(stats.get("name", etype)).to_lower()
	return I18n.t("E: Offer it raw meat (%d / %d)") % [fed, need]


func interact(_player) -> void:
	if _dead or not Game.can_tame_more() or not Game.remove_item("raw_meat", 1):
		return
	_calm = 12.0
	var k := _feed_key()
	Game.counters[k] = float(Game.counters.get(k, 0.0)) + 1.0
	var need := maxi(1, int(ceil(int(stats.get("tameable", 0)) * Game.tame_need_mult())))     # (round 32: Wild Call halves it)
	Game.log_event("feed", {"type": etype, "n": int(Game.counters[k])})
	Game.taming_xp("feed")                                                                     # round 32: the taming skill
	if int(Game.counters[k]) >= need:
		_dead = true
		remove_from_group("enemy")
		remove_from_group("interactable")
		Game.bond_familiar(etype)
		queue_free()
	else:
		Game.message.emit("The %s eats from your hand, watching you." % str(stats.get("name", etype)).to_lower())


func _update_label() -> void:
	_label.text = "%s%s" % [stats.get("name", etype), I18n.t("  [STAGGERED]") if _stun > 0.0 and not _dead else (I18n.t("  [OPEN]") if exposed > 0.0 and not _dead else "")]
	if _bar:
		_bar.set_frac(float(maxi(hp, 0)) / maxf(float(stats.get("hp", 1)), 1.0))


func poise_max() -> float:
	var P: Dictionary = Game.combat_data().get("poise", {})
	return float(stats.get("hp", 20)) * float(P.get("boss_frac", 1.4) if bool(stats.get("boss", false)) else P.get("base_frac", 0.55))


func poise_hit(amount: float, heavy: bool) -> void:
	## round 32: every blow you land pushes at its footing; enough and it
	## staggers -- a free moment, and blows land harder on it
	if _dead or bool(stats.get("passive", false)):
		return
	var P: Dictionary = Game.combat_data().get("poise", {})
	_poise_rest = float(P.get("regen_after", 1.8))
	poise += amount * float(P.get("light", 1.0)) * _ward()
	if poise >= poise_max() and _stun <= 0.0:
		poise = 0.0
		stagger(float(P.get("boss_stagger", 0.9) if bool(stats.get("boss", false)) else P.get("stagger", 1.3)) / _ward())
		Game.message.emit("%s staggers!" % stats.get("name", etype))
		_update_label()
		FX.ring(global_position, Color(1.0, 0.95, 0.6), 1.8, 0.3)
		Game.sfx_at("bell", global_position, 0.6)
		Game.log_event("stagger", {"type": etype})
		if _anim and _anim.has_animation("hit"):
			_anim.play("hit", 0.05)
	elif not heavy and _anim and _anim.has_animation("hit") and randf() < float(Game.combat_data().get("hit_react", {}).get("light_chance", 0.5)) and not bool(stats.get("boss", false)) and _attacking <= 0.0:
		_anim.play("hit", 0.05)      # flinches
		_attacking = 0.25


func _face(dir: Vector3) -> void:
	if dir.length() > 0.01:
		_model.rotation.y = atan2(dir.x, dir.z)


func _play(anim: String, restart: bool = false) -> void:
	if _anim == null or not _anim.has_animation(anim):
		return
	if restart or _anim.current_animation != anim:
		_anim.play(anim, 0.15)


func _loop(names: Array) -> void:
	if _anim == null:
		return
	for n in names:
		if _anim.has_animation(n):
			_anim.get_animation(n).loop_mode = Animation.LOOP_LINEAR


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


func _find_anim(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var a := _find_anim(c)
		if a:
			return a
	return null


# ======================================================================
# round 28: styles and affixes (data/foes.json)
# ======================================================================

func _headless() -> bool:
	return DisplayServer.get_name() == "headless"


func describe() -> String:
	## what you'd learn by watching it a while
	var F: Dictionary = Game.foes_data()
	var bits := [str(_sd.get("desc", "closes in and hits"))]
	for a in affixes:
		bits.append(str(F.get("affixes", {}).get(a, {}).get("desc", a)))
	return "%s: %s" % [stats.get("name", etype), "; ".join(bits)]


func _dress_style() -> void:
	## you can tell how it fights by looking at it
	if _model == null:
		return
	var s := float(stats.get("scale", 1.0))
	match style:
		"guardian":
			var sh: Node3D = preload("res://scripts/core/Art.gd").make("mini-dungeon/shield-round.glb", 0) if ResourceLoader.exists("res://assets/kenney/mini-dungeon/shield-round.glb") else null
			if sh:
				# on the model, so it turns with it (and undo the model's own scale)
				var ms: float = maxf(_model.scale.x, 0.01)
				sh.scale = Vector3.ONE * 1.5 * s / ms
				sh.position = Vector3(0.42 * s, 0.75 * s, 0.32 * s) / ms
				sh.rotation = Vector3(0.0, 0.35, 0.0)
				_model.add_child(sh)
		"ranged", "mender":
			var orb := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.12
			sm.height = 0.24
			orb.mesh = sm
			var c: Array = _sd.get("color", [1, 0.8, 0.4])
			var m := StandardMaterial3D.new()
			m.albedo_color = Color(float(c[0]), float(c[1]), float(c[2]))
			m.emission_enabled = true
			m.emission = m.albedo_color
			m.emission_energy_multiplier = 2.0
			orb.material_override = m
			orb.position = Vector3(0.0, 2.0 * s + 0.3, 0.0)
			add_child(orb)
			if not _headless():
				var l := OmniLight3D.new()
				l.light_color = m.albedo_color
				l.omni_range = 3.0
				l.light_energy = 0.8
				orb.add_child(l)
		"charger":
			if body_kind != "kenney":
				return               # (a person -- or an imp with its own horns -- charges without them)
			for side in [-1.0, 1.0]:
				var horn := MeshInstance3D.new()
				var cm := CylinderMesh.new()
				cm.top_radius = 0.0
				cm.bottom_radius = 0.07
				cm.height = 0.4
				horn.mesh = cm
				var hm := StandardMaterial3D.new()
				hm.albedo_color = Color(0.9, 0.85, 0.7)
				horn.material_override = hm
				horn.position = Vector3(side * 0.18 * s, 1.75 * s, 0.15 * s)
				horn.rotation = Vector3(-0.6, 0.0, side * -0.5)
				add_child(horn)


func _tell(on: bool, k: float = 0.0, c: Color = Color(1.0, 0.3, 0.2)) -> void:
	## a warning ring on the ground: something is coming
	if _tell_ring == null:
		_tell_ring = MeshInstance3D.new()
		var t := TorusMesh.new()
		t.inner_radius = 0.9
		t.outer_radius = 1.0
		_tell_ring.mesh = t
		_tell_mat = StandardMaterial3D.new()
		_tell_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_tell_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		if not _headless():
			_tell_ring.material_override = _tell_mat
		_tell_ring.position.y = 0.08
		add_child(_tell_ring)
	_tell_ring.visible = on
	if on:
		_tell_mat.albedo_color = Color(c.r, c.g, c.b, 0.3 + 0.5 * k)
		_tell_ring.scale = Vector3.ONE * (0.6 + 3.9 * k)


func _ward() -> float:
	return float(Game.foes_data().get("affixes", {}).get("warding", {}).get("status", 0.5)) if "warding" in affixes else 1.0


func _reveal() -> void:
	if _revealed:
		return
	_revealed = true
	if _model:
		_model.visible = true
	if _label:
		_label.visible = true
	Game.message.emit("%s steps out of the dark!" % stats.get("name", etype))


func _shielded(amount: int, source: String) -> int:
	## a guardian turns your blade from the front -- not your qi, not your back
	if style != "guardian" or not source.begins_with("you") or _model == null:
		return amount
	if source == "you (heavy)":
		return amount              # a charged heavy goes through the shield (round 32)
	var player = get_tree().get_first_node_in_group("player") if is_inside_tree() else null
	if player == null:
		return amount
	var fwd := Vector3(sin(_model.rotation.y), 0, cos(_model.rotation.y))
	var to: Vector3 = player.global_position - global_position
	to.y = 0.0
	if to.length() < 0.05 or fwd.dot(to.normalized()) < 0.3:
		return amount
	if randf() < 0.25:
		Game.message.emit("%s takes it on the shield. (Go round it, or use your arts.)" % stats.get("name", etype))
	return maxi(1, int(round(amount * (1.0 - float(_sd.get("front_cut", 0.65))))))


func _after_hurt() -> void:
	var mx := float(stats.get("hp", 1))
	_boss_phases(mx)
	if "frenzied" in affixes and not _frenzy and hp > 0 and hp <= mx * float(Game.foes_data().get("affixes", {}).get("frenzied", {}).get("at", 0.5)):
		_frenzy = true
		var A: Dictionary = Game.foes_data().get("affixes", {}).get("frenzied", {})
		stats["speed"] = float(stats.get("speed", 3.0)) * float(A.get("speed", 1.5))
		stats["cooldown"] = float(stats.get("cooldown", 1.4)) * float(A.get("cooldown", 0.6))
		Game.message.emit("%s goes into a frenzy!" % stats.get("name", etype))
	if bool(stats.get("boss", false)) and not _enraged and hp > 0 and hp <= mx * float(Game.foes_data().get("boss_enrage", {}).get("at", 0.5)):
		_enraged = true
		var B: Dictionary = Game.foes_data().get("boss_enrage", {})
		stats["speed"] = float(stats.get("speed", 3.0)) * float(B.get("speed", 1.3))
		stats["cooldown"] = float(stats.get("cooldown", 1.4)) * float(B.get("cooldown", 0.75))
		Game.message.emit("%s is ENRAGED -- faster, and it won't stop now." % stats.get("name", etype))
		Game.log_event("boss_enraged", {"type": etype})


func heal_by(n: int) -> void:
	if _dead or n <= 0:
		return
	hp = mini(hp + n, int(stats.get("hp", 1)))
	_update_label()


func deal(player, dmg: int) -> void:
	## every blow it lands (melee, a shot, a charge, a stamp) comes through here
	if player == null or not is_instance_valid(player) or player.dead:
		return
	if rallied > 0.0:
		dmg = int(round(dmg * float(Game.foes_data().get("affixes", {}).get("commanding", {}).get("dmg", 1.25))))
	if weakened > 0.0:
		dmg = maxi(1, int(round(dmg * weak_mult)))
	var before: int = Game.hp
	player.take_damage(dmg, str(stats.get("name", etype)), self)
	var dealt: int = maxi(before - Game.hp, 0)
	if dealt <= 0:
		return
	var F: Dictionary = Game.foes_data().get("affixes", {})
	if "vampiric" in affixes:
		heal_by(int(round(dealt * float(F.get("vampiric", {}).get("drain", 0.35)))))
	if "venomous" in affixes:
		var V: Dictionary = F.get("venomous", {})
		var tick := maxi(1, int(round(dmg * float(V.get("poison", 0.12)))))
		var psn = Game.sys("poison")                                # round 138: poison is one thing now (an antidote clears it)
		if psn != null:
			psn.afflict(tick, float(V.get("ticks", 3)))


func _style_tick(delta: float, player, to_player: Vector3, dist: float) -> bool:
	## true when the style moved it this tick (else: close in and hit, as ever)
	match style:
		"ranged", "mender":
			return _keep_distance(delta, player, to_player, dist)
		"charger":
			return _charge(delta, player, to_player, dist)
	return false


func _keep_distance(delta: float, player, to_player: Vector3, dist: float) -> bool:
	var keep: Array = _sd.get("keep", [5.0, 9.0])
	if style == "mender":
		_t2 -= delta
		if _t2 <= 0.0:
			_t2 = float(_sd.get("cd", 5.0))
			_heal_allies()
	if dist > float(keep[1]) + 1.0 or not _can_see(player):
		return false                      # too far, or no line: close in like anyone
	_face(to_player)
	var spd := float(stats.get("speed", 3.0)) * (0.6 if _slow > 0.0 else 1.0)
	if dist < float(keep[0]):
		var away := -to_player.normalized()
		velocity.x = away.x * spd * 0.85
		velocity.z = away.z * spd * 0.85
		_play("walk")
	else:
		velocity.x = 0.0
		velocity.z = 0.0
		if _attacking <= 0.0:
			_play("idle")
	_t1 -= delta * (0.6 if _slow > 0.0 else 1.0)
	if _t1 <= 0.0:
		_t1 = float(_sd.get("fire_cd", 2.4)) * float(stats.get("cooldown", 1.4)) / 1.4
		shoot(player)
	return true


func shoot(player) -> Node:
	## a bolt you can see coming (Bolt.gd): step aside, guard, or parry it
	_attacking = 0.5
	_play("attack-melee-right", true)
	var b = preload("res://scripts/fx/Bolt.gd").new()
	var from := global_position + Vector3(0, 1.3 * float(stats.get("scale", 1.0)), 0)
	var to: Vector3 = player.global_position + Vector3(0, 1.0, 0)
	var c: Array = _sd.get("color", [1, 0.75, 0.35])
	b.setup(self, from, to, float(_sd.get("bolt_speed", 13.0)), int(round(float(stats.get("damage", 5)) * float(_sd.get("dmg", 0.75)))), Color(float(c[0]), float(c[1]), float(c[2])))
	get_parent().add_child(b)
	return b


func _heal_allies() -> void:
	var r := float(_sd.get("radius", 10.0))
	var healed := 0
	for e in get_tree().get_nodes_in_group("enemy"):
		if e == self or not is_instance_valid(e) or e.get("_dead") or not e.has_method("heal_by"):
			continue
		if (e.global_position - global_position).length() > r or int(e.hp) >= int(e.stats.get("hp", 1)):
			continue
		e.heal_by(int(round(float(e.stats.get("hp", 1)) * float(_sd.get("heal", 0.14)))))
		healed += 1
	if healed > 0:
		Game.message.emit("%s mends its allies. (Kill it first.)" % stats.get("name", etype))
		if not _headless():
			var l := OmniLight3D.new()
			l.light_color = Color(0.45, 1.0, 0.6)
			l.omni_range = r
			l.light_energy = 2.0
			l.position = Vector3(0, 1.0, 0)
			add_child(l)
			var tw := create_tween()
			tw.tween_property(l, "light_energy", 0.0, 0.6)
			tw.tween_callback(l.queue_free)


func _charge(delta: float, player, to_player: Vector3, dist: float) -> bool:
	if _dash > 0.0:
		_dash -= delta
		velocity.x = _dash_dir.x * float(_sd.get("dash_speed", 15.0))
		velocity.z = _dash_dir.z * float(_sd.get("dash_speed", 15.0))
		_play("sprint")
		if not _dash_hit and dist < 1.5:
			_dash_hit = true
			_dash = 0.0
			deal(player, int(round(float(stats.get("damage", 5)) * float(_sd.get("dmg", 1.6)))))
		if _dash <= 0.0:
			velocity.x = 0.0
			velocity.z = 0.0
			_cooldown = maxf(_cooldown, 0.8)        # it has to turn round after a run
		return true
	if _t2 > 0.0:
		_t2 -= delta
		velocity.x = 0.0
		velocity.z = 0.0
		_face(to_player)
		_tell(true, 1.0 - _t2 / float(_sd.get("windup", 0.75)), Color(1.0, 0.45, 0.15))
		if _t2 <= 0.0:
			_tell(false)
			_dash = float(_sd.get("dash_time", 0.5))
			_dash_dir = to_player.normalized()           # it commits to where you WERE
			FX.dust(global_position, 1.3)
			_dash_hit = false
		return true
	_t1 -= delta
	if _t1 <= 0.0 and dist >= float(_sd.get("min", 3.5)) and dist <= float(_sd.get("max", 12.0)) and _can_see(player):
		_t1 = float(_sd.get("cd", 5.0))
		_t2 = float(_sd.get("windup", 0.75))
		_play("idle")
		return true
	return false


func _brood() -> void:
	_brood_done = true
	if level == null:
		return
	var n := int(_sd.get("minions", 2))
	for i in n:
		var a := TAU * float(i) / float(n) + 0.7
		var at := global_position + Vector3(cos(a), 0, sin(a)) * 1.6
		var m = level._spawn_script("res://scripts/actors/Enemy.gd", at, {"type": etype, "cell": level.world_to_cell(at), "minion": true, "style": "brawler",
			"hp_mult": float(_sd.get("minion_hp", 0.35)), "scale_mult": float(_sd.get("minion_scale", 0.6)), "young": true})
		if m:
			m._chasing = true
	Game.message.emit("%s brings its young!" % stats.get("name", etype))


func _split() -> void:
	if level == null:
		return
	var A: Dictionary = Game.foes_data().get("affixes", {}).get("splitting", {})
	for i in int(A.get("parts", 2)):
		var a := PI * float(i)
		var at := global_position + Vector3(cos(a), 0, sin(a)) * 1.2
		level._spawn_script.call_deferred("res://scripts/actors/Enemy.gd", at, {"type": etype, "cell": level.world_to_cell(at), "minion": true,
			"style": style, "hp_mult": float(A.get("part_hp", 0.4)), "scale_mult": 0.75})
	Game.message.emit("%s breaks apart -- and the pieces keep fighting!" % stats.get("name", etype))


func _thunder(delta: float, player, dist: float) -> bool:
	var A: Dictionary = Game.foes_data().get("affixes", {}).get("thunderous", {})
	if _t4 > 0.0:
		_t4 -= delta
		velocity.x = 0.0
		velocity.z = 0.0
		var r := float(A.get("radius", 4.5))
		_tell(true, 1.0 - _t4 / float(A.get("warn", 1.0)), Color(1.0, 0.9, 0.3))
		if _tell_ring:
			_tell_ring.scale = Vector3.ONE * r * (1.0 - _t4 / float(A.get("warn", 1.0)))
		if _t4 <= 0.0:
			_tell(false)
			if dist <= r:
				deal(player, int(round(float(stats.get("damage", 5)) * float(A.get("dmg", 1.2)))))
			Game.message.emit("%s stamps -- the ground shakes." % stats.get("name", etype))
			Game.sfx_at("stamp", global_position, 1.0)
			FX.ring(global_position, Color(1.0, 0.9, 0.35), float(A.get("radius", 4.0)))
			FX.dust(global_position, 2.0)
		return true
	_t3 -= delta
	if _t3 <= 0.0 and dist < float(A.get("radius", 4.5)) * 2.0:
		_t3 = float(A.get("every", 7.0))
		_t4 = float(A.get("warn", 1.0))
		return true
	return false


# ======================================================================
# round 60: reading a fight. Robert: "combat depth" -- enemies telegraph
# attacks so you can dodge on purpose; elite fights more varied.
# ======================================================================

func _H() -> Dictionary:
	return Game.combat_data().get("foe_heavy", {})


func _can_heavy() -> bool:
	if minion or bool(stats.get("passive", false)):
		return false
	if not (style in _H().get("styles", ["brawler"])):
		return false
	return bool(stats.get("boss", false)) or elite or _depth() >= int(_H().get("from_depth", 2))


func _start_heavy(player) -> void:
	var H := _H()
	_swings = 0
	var ev: Array = H.get("every", [3, 5])
	_heavy_at = randi_range(int(ev[0]), int(ev[1]))
	_heavy_total = float(H.get("boss_windup", 0.85)) if bool(stats.get("boss", false)) else float(H.get("elite_windup", 0.62) if elite else H.get("windup", 0.75))
	if _enraged:
		_heavy_total *= 0.85
	_heavy_t = _heavy_total
	_attacking = _heavy_t + 0.45
	_cooldown = float(stats.get("cooldown", 1.4)) * 1.5 + _heavy_t
	var to: Vector3 = player.global_position - global_position
	to.y = 0.0
	_heavy_dir = to.normalized() if to.length() > 0.01 else Vector3.FORWARD
	_play("idle")
	_tell(true, 0.0, Color(1.0, 0.22, 0.1))
	Game.sfx_at("windup", global_position, 0.9)
	Game.log_event("foe_heavy", {"type": etype})
	if not Game.has_flag("tut:heavy_tell"):
		Game.set_flag("tut:heavy_tell")
		Game.message.emit("%s draws back for a HEAVY blow (the red ring) -- a guard won't hold it. Roll away, or parry it as it lands." % stats.get("name", etype))


func _heavy_tick(delta: float, player) -> void:
	_heavy_t -= delta
	velocity.x = 0.0
	velocity.z = 0.0
	var to: Vector3 = player.global_position - global_position
	to.y = 0.0
	if _heavy_t > float(_H().get("lock", 0.22)) and to.length() > 0.01:
		_face(to)                              # it tracks you -- until the last moment
		_heavy_dir = to.normalized()
	var k := clampf(1.0 - _heavy_t / maxf(_heavy_total, 0.01), 0.0, 1.0)
	_tell(true, k, Color(1.0, 0.22, 0.1))
	if _model:
		_model.scale = _base_scale * (1.0 + 0.07 * k)     # rearing up
	if _heavy_t <= 0.0:
		_heavy_strike(player)


func _heavy_strike(player) -> void:
	_heavy_t = 0.0
	_tell(false)
	if _model:
		_model.scale = _base_scale
	_play("attack-melee-right", true)
	Game.sfx_at("swing", global_position, 0.9)
	var H := _H()
	var reach := float(stats.get("range", 1.8)) + 0.5 + float(H.get("reach", 0.7))
	var to: Vector3 = player.global_position - global_position
	to.y = 0.0
	var front := to.length() < 0.6 or _heavy_dir.dot(to.normalized()) > 0.25
	if FX.on():
		FX.ring(global_position + _heavy_dir * reach * 0.5, Color(1.0, 0.35, 0.15), reach * 0.6, 0.25)
	if to.length() <= reach and front:
		heavy_now = true
		deal(player, int(round(float(stats.get("damage", 5)) * float(H.get("mult", 1.8)))))
		heavy_now = false
	else:
		expose(float(H.get("opening", 1.6)))          # it swung at air: wide open
		Game.log_event("foe_whiff", {"type": etype})


func expose(secs: float) -> void:
	## it overreached -- every hit lands harder until it recovers (it can't strike back meanwhile)
	if _dead:
		return
	var was := exposed > 0.0
	exposed = maxf(exposed, secs)
	_cooldown = maxf(_cooldown, secs * 0.6)
	if not was:
		if FX.on():
			FX.word(global_position + Vector3(0, _mid_height() + 1.1, 0), "OPENING!", Color(1.0, 0.85, 0.3))
			FX.ring(global_position, Color(1.0, 0.85, 0.3), 1.8, 0.3)
		_update_label()
		Game.log_event("foe_opening", {"type": etype})
		if not Game.has_flag("tut:opening"):
			Game.set_flag("tut:opening")
			Game.message.emit("OPENING -- %s is off balance: every hit lands harder for a moment." % stats.get("name", etype))


func _boss_move(delta: float, player, dist: float) -> bool:
	## a floor's master: now and then a SLAM (a disc grows under you -- it leaps
	## there) or a SWEEP (a wide disc round it -- it spins)
	var B: Dictionary = Game.combat_data().get("boss_moves", {})
	if B.is_empty() or level == null:
		return false
	if _bm_busy > 0.0:
		_bm_busy -= delta
		velocity.x = 0.0
		velocity.z = 0.0
		return true
	_bm_t -= delta
	if _bm_t > 0.0:
		return false
	var S: Dictionary = B.get("slam", {})
	var W: Dictionary = B.get("sweep", {})
	var kind := ""
	if dist <= float(W.get("radius", 3.6)) * 0.9:
		kind = "sweep" if randf() < 0.7 else "slam"
	elif dist >= float(S.get("min", 3.0)) and dist <= float(S.get("max", 12.0)):
		kind = "slam"                     # (a master knows where you are)
	if kind == "":
		return false
	var ev: Array = B.get("every", [7.0, 10.0])
	_bm_t = randf_range(float(ev[0]), float(ev[1])) * (float(B.get("enraged_mult", 0.7)) if _enraged else 1.0)
	var M: Dictionary = S if kind == "slam" else W
	var at: Vector3 = player.global_position if kind == "slam" else global_position
	at.y = global_position.y
	var bl = preload("res://scripts/fx/Blast.gd").new()
	bl.setup(at, float(M.get("radius", 3.0)), float(M.get("windup", 0.9)), int(round(float(stats.get("damage", 5)) * float(M.get("dmg", 1.5)))),
		Color(1.0, 0.3, 0.75), "%s's %s" % [stats.get("name", etype), kind], self)
	var me := self
	if kind == "slam":
		bl.after = func():
			if is_instance_valid(me) and not me._dead:
				var land := Vector3(at.x, me.global_position.y, at.z)
				var away: Vector3 = me.global_position - land
				away.y = 0.0
				me.global_position = land + (away.normalized() * 0.6 if away.length() > 0.1 else Vector3.ZERO)
				FX.dust(land, 2.2)
	else:
		bl.after = func():
			if is_instance_valid(me) and not me._dead:
				me._play("attack-melee-right", true)
	level.add_child(bl)
	bl.global_position = at
	_bm_busy = float(M.get("windup", 0.9)) + 0.35
	_face(player.global_position - global_position)
	_play("idle")
	Game.log_event("boss_move", {"type": etype, "move": kind})
	if not Game.has_flag("tut:boss_move"):
		Game.set_flag("tut:boss_move")
		Game.message.emit("Watch the ground -- %s's big moves show where they'll land. Get out of the disc." % stats.get("name", etype))
	return true


func _blink(delta: float, player, dist: float) -> bool:
	var A: Dictionary = Game.foes_data().get("affixes", {}).get("blinking", {})
	if _blink_w > 0.0:
		_blink_w -= delta
		velocity.x = 0.0
		velocity.z = 0.0
		if _model:
			_model.visible = fmod(_blink_w, 0.12) < 0.06       # flickering
		if _blink_w <= 0.0:
			if _model:
				_model.visible = true
			var pm = player.get("_model")
			var fwd: Vector3 = Vector3(sin(pm.rotation.y), 0, cos(pm.rotation.y)) if pm else -(player.global_position - global_position).normalized()
			var side: Vector3 = fwd.cross(Vector3.UP)
			var spot := Vector3.INF
			for dirv in [-fwd, side, -side, (-fwd + side).normalized(), (-fwd - side).normalized(), fwd]:
				var cand: Vector3 = player.global_position + dirv * float(A.get("behind", 1.8))
				if level == null or level.is_walkable_char(level.char_at(level.world_to_cell(cand))):
					spot = cand
					break
			if spot != Vector3.INF:
				FX.puff(global_position + Vector3(0, 1, 0), Color(0.7, 0.45, 1.0), 1.0)
				global_position = Vector3(spot.x, global_position.y, spot.z)
				FX.puff(global_position + Vector3(0, 1, 0), Color(0.7, 0.45, 1.0), 1.0)
				_face(player.global_position - global_position)
				_cooldown = minf(_cooldown, 0.35)
				Game.sfx_at("crystal", global_position, 0.8)
				Game.log_event("foe_blink", {"type": etype})
		return true
	_blink_t -= delta
	if _blink_t <= 0.0 and dist > 2.5 and dist < 14.0 and _can_see(player):
		_blink_t = float(A.get("every", 8.0))
		_blink_w = float(A.get("warn", 0.6))
		return true
	return false


func _volatile() -> void:
	var A: Dictionary = Game.foes_data().get("affixes", {}).get("volatile", {})
	if level == null:
		return
	var bl = preload("res://scripts/fx/Blast.gd").new()
	bl.setup(global_position, float(A.get("radius", 3.4)), float(A.get("fuse", 1.3)), int(round(float(stats.get("damage", 5)) * float(A.get("dmg", 1.6)))),
		Color(1.0, 0.5, 0.15), "%s's last breath" % stats.get("name", etype), null)
	var at := global_position
	level.add_child(bl)
	bl.global_position = at
	Game.message.emit("%s is about to burst -- get clear!" % stats.get("name", etype))


func _rally(delta: float) -> void:
	_rally_t -= delta
	if _rally_t > 0.0:
		return
	var A: Dictionary = Game.foes_data().get("affixes", {}).get("commanding", {})
	_rally_t = float(A.get("every", 1.0))
	var r := float(A.get("radius", 9.0))
	for e in get_tree().get_nodes_in_group("enemy"):
		if e != self and e is Node3D and e.get("_dead") != true and (e as Node3D).global_position.distance_to(global_position) <= r:
			e.set("rallied", _rally_t + 0.5)


func _rally_speed() -> float:
	return float(Game.foes_data().get("affixes", {}).get("commanding", {}).get("speed", 1.15))

