extends "res://scripts/systems/GameSystem.gd"
## FloorRun (round 61): the pull of one more floor. Robert: "make game play
## more enjoyable, immersive and compulsive."
##
##   a floor's tally  from the moment you step onto a dungeon floor: foes
##                    felled, chests and secret ways found, how much of it you
##                    walked, the hardest blow you struck, how close you came to
##                    falling, how long it took
##   the verdict      when its master falls, a card: the tally, a grade S..D
##                    (data/floorrun.json "grades"), a line from whoever watches
##                    from the dark (Dev's floor_verdicts, or ours), and what
##                    waits below. A better grade than you've had on that floor
##                    pays the difference -- so a floor is worth doing again, better.
##   descent streak   every floor you go DOWN from in a row, without falling or
##                    turning back up, adds to a streak (to 5): a little more qi
##                    from every kill and a little more luck with loot. Fall, or
##                    climb back up, and it's gone. One more floor ...
##   rare finds       Superior and Masterwork gear arrives with a beam of light
##                    where it fell and a sound of its own (Game.loot_reveal)

signal floor_cleared(card: Dictionary)

var cfg := {}
var run := {}            # the floor you're on now
var streak := 0
var best_streak := 0
var best := {}           # level id -> best grade there ("S".."D")
var last_floor_depth := 0
var verdicts_used := {}  # grade -> last line index (no repeats in a row)


func setup(game) -> void:
	super.setup(game)
	cfg = load_json("res://data/floorrun.json")
	preload_assets()


func reset() -> void:
	run = {}
	streak = 0
	best_streak = 0
	best = {}
	last_floor_depth = 0


func save_state() -> Dictionary:
	return {"streak": streak, "best_streak": best_streak, "best": best, "last": last_floor_depth}


func load_state(d: Dictionary) -> void:
	streak = int(d.get("streak", 0))
	best_streak = int(d.get("best_streak", 0))
	best = d.get("best", {}) if d.get("best", {}) is Dictionary else {}
	last_floor_depth = int(d.get("last", 0))


# ---- the streak -----------------------------------------------------------------------

func streak_cap() -> int:
	return int(cfg.get("streak", {}).get("cap", 5))


func effects() -> Array:
	if streak <= 0:
		return []
	var S: Dictionary = cfg.get("streak", {})
	var n := mini(streak, streak_cap())
	return [{"loot_luck": float(S.get("luck", 0.04)) * n, "qi_mult": 1.0 + float(S.get("qi", 0.05)) * n}]


func streak_text() -> String:
	if streak <= 0:
		return ""
	var S: Dictionary = cfg.get("streak", {})
	var n := mini(streak, streak_cap())
	return I18n.t("Descent x%d: +%d%% qi, +%d%% luck") % [streak, int(round(float(S.get("qi", 0.05)) * n * 100)), int(round(float(S.get("luck", 0.04)) * n * 100))]


func _break_streak(why: String) -> void:
	if streak <= 0:
		return
	if streak >= 2:
		G.message.emit(I18n.t("Your descent streak (%d) ends -- %s.") % [streak, why])
	G.log_event("streak_lost", {"n": streak, "why": why})
	streak = 0
	G.stats_changed.emit()


# ---- what you do ------------------------------------------------------------------------

func _is_floor(level_id: String) -> bool:
	return level_id.begins_with("floor") and not level_id.contains(":")


func on_event(kind: String, d: Dictionary) -> void:
	match kind:
		"enter_level":
			var lid := str(d.get("id", ""))
			var dep: int = G.floor_depth(lid) if _is_floor(lid) else 0
			if _is_floor(lid) and last_floor_depth > 0 and dep < last_floor_depth:
				_break_streak("you turned back up")
			elif lid == "village" and last_floor_depth > 0:
				_break_streak("you went home")
			if _is_floor(lid):
				last_floor_depth = dep
				if str(run.get("level", "")) != lid:
					_start_run(lid, d)
		"leave_level":
			var to := str(d.get("to", ""))
			var here := str(run.get("level", ""))
			if here != "" and _is_floor(to) and G.floor_depth(to) > G.floor_depth(here) and not bool(run.get("counted", false)):
				run["counted"] = true
				streak += 1
				best_streak = maxi(best_streak, streak)
				if streak >= 2:
					G.message.emit(I18n.t("DESCENT x%d -- %s.") % [streak, streak_text().get_slice(": ", 1)])
				G.log_event("streak", {"n": streak})
		"death":
			_break_streak("you fell")
		"kill":
			if not run.is_empty():
				run["kills"] = int(run.get("kills", 0)) + 1
		"elite_kill":
			if not run.is_empty():
				run["elites"] = int(run.get("elites", 0)) + 1
		"chest":
			if not run.is_empty():
				run["chests"] = int(run.get("chests", 0)) + 1
		"secret":
			if not run.is_empty():
				run["secrets"] = int(run.get("secrets", 0)) + 1
		"boss_kill":
			if not run.is_empty() and not bool(run.get("cleared", false)) and str(run.get("level", "")) == str(G.current_level):
				run["cleared"] = true
				var card := verdict()
				G.log_event("floor_cleared", {"grade": card["grade"], "depth": card["depth"]})
				floor_cleared.emit(card)


func _start_run(lid: String, d: Dictionary) -> void:
	run = {"level": lid, "start": G.playtime, "foes": int(d.get("enemies", 0)), "chests_total": int(d.get("chests", 0)),
		"secrets_total": int(d.get("secrets", 0)), "kills": 0, "chests": 0, "secrets": 0, "elites": 0, "best_hit": 0, "low": 1.0}


func note_hit(dmg: int) -> void:
	if not run.is_empty():
		run["best_hit"] = maxi(int(run.get("best_hit", 0)), dmg)


func tick(_delta: float) -> void:
	if run.is_empty() or G.max_hp() <= 0:
		return
	run["low"] = minf(float(run.get("low", 1.0)), clampf(float(G.hp) / float(G.max_hp()), 0.0, 1.0))


# ---- the verdict ------------------------------------------------------------------------

func score() -> Dictionary:
	## each part 0..1, and the whole
	var W: Dictionary = cfg.get("weights", {})
	var lid := str(run.get("level", ""))
	var dep: int = G.floor_depth(lid)
	var parts := {}
	parts["explored"] = clampf(float(G.fog_frac.get(lid, 0.0)), 0.0, 1.0)
	parts["foes"] = clampf(float(run.get("kills", 0)) / maxf(1.0, float(run.get("foes", 1)) * float(cfg.get("foes_share", 0.8))), 0.0, 1.0)
	parts["chests"] = clampf(float(run.get("chests", 0)) / maxf(1.0, float(run.get("chests_total", 1))), 0.0, 1.0) if int(run.get("chests_total", 0)) > 0 else 1.0
	parts["secrets"] = clampf(float(run.get("secrets", 0)) / maxf(1.0, float(run.get("secrets_total", 1))), 0.0, 1.0) if int(run.get("secrets_total", 0)) > 0 else 1.0
	parts["safety"] = clampf(float(run.get("low", 1.0)) / float(cfg.get("safe_at", 0.6)), 0.0, 1.0)
	var mins: float = (G.playtime - float(run.get("start", G.playtime))) / 60.0
	var par: float = float(cfg.get("par_minutes", 9.0)) + float(cfg.get("par_per_depth", 0.35)) * dep
	parts["time"] = clampf(1.5 - mins / par * 0.5, 0.0, 1.0)      # at par: 1.0; double par: 0.5; triple: 0
	var total := 0.0
	var wsum := 0.0
	for k in parts:
		total += float(parts[k]) * float(W.get(k, 1.0))
		wsum += float(W.get(k, 1.0))
	return {"parts": parts, "total": total / maxf(wsum, 0.001), "minutes": mins, "par": par}


func grade_for(total: float, low: float) -> String:
	for g in cfg.get("grades", []):
		if total >= float(g.get("at", 0.0)) and low >= float(g.get("low", 0.0)):
			return str(g.get("id", "D"))
	return "D"


const ORDER := ["D", "C", "B", "A", "S"]


func verdict() -> Dictionary:
	var lid := str(run.get("level", ""))
	var dep: int = G.floor_depth(lid)
	var sc := score()
	var grade := grade_for(float(sc["total"]), float(run.get("low", 1.0)))
	var prev := str(best.get(lid, ""))
	var pay := {"gold": 0, "insight": 0.0, "qi_kills": 0.0}
	var better := prev == "" or ORDER.find(grade) > ORDER.find(prev)
	if better:
		# what this grade is worth, less what an earlier grade here already paid
		var R: Dictionary = cfg.get("rewards", {})
		var now_r: Dictionary = R.get(grade, {})
		var was_r: Dictionary = R.get(prev, {}) if prev != "" else {}
		pay["gold"] = maxi(0, int(round((float(now_r.get("gold_per_depth", 0)) - float(was_r.get("gold_per_depth", 0))) * maxi(dep, 1))))
		pay["insight"] = maxf(0.0, float(now_r.get("insight", 0)) - float(was_r.get("insight", 0)))
		pay["qi_kills"] = maxf(0.0, float(now_r.get("qi_kills", 0)) - float(was_r.get("qi_kills", 0)))
		best[lid] = grade
		if int(pay["gold"]) > 0:
			G.gold += int(pay["gold"])
		if float(pay["insight"]) > 0.0:
			G.gain_insight(float(pay["insight"]), "a floor done well")
		if float(pay["qi_kills"]) > 0.0:
			G.add_qi(float(pay["qi_kills"]) * G.kill_qi_at(dep), "a floor done well")
	var line := verdict_line(grade)
	var card := {"level": lid, "depth": dep, "grade": grade, "prev": prev, "better": better, "pay": pay, "title": line[0], "line": line[1],
		"parts": sc["parts"], "total": sc["total"], "minutes": sc["minutes"], "par": sc["par"],
		"kills": int(run.get("kills", 0)), "foes": int(run.get("foes", 0)), "chests": int(run.get("chests", 0)), "chests_total": int(run.get("chests_total", 0)),
		"secrets": int(run.get("secrets", 0)), "secrets_total": int(run.get("secrets_total", 0)), "elites": int(run.get("elites", 0)),
		"best_hit": int(run.get("best_hit", 0)), "low": float(run.get("low", 1.0)), "streak": streak, "below": below(dep)}
	G.stats_changed.emit()
	return card


func verdict_line(grade: String) -> Array:
	## [title, line]: Dev's words (data/drafts/floor_verdicts.json) if there are any, else ours
	var opts := []
	var dev: Dictionary = G.draft_texts("floor_verdicts")
	for i in range(1, 4):
		var txt: String = str(dev.get("%s_%d" % [grade.to_lower(), i], ""))
		if txt.contains(" -- "):
			opts.append([txt.get_slice(" -- ", 0).strip_edges(), txt.get_slice(" -- ", 1).strip_edges()])
	if opts.is_empty():
		for row in cfg.get("verdicts", {}).get(grade, []):
			opts.append([str(row[0]), str(row[1])])
	if opts.is_empty():
		return [grade, ""]
	var i := (int(verdicts_used.get(grade, -1)) + 1) % opts.size()
	verdicts_used[grade] = i
	return opts[i]


func below(dep: int) -> Dictionary:
	## a look at what's next: its name, a town or a master, what the gate wants
	var nxt := "floor%d" % (dep + 1)
	if not G.level_exists(nxt):
		return {}
	var d: Dictionary = G.load_level_def(nxt)
	var out := {"id": nxt, "name": str(d.get("name", nxt)).get_slice(" -- ", 0)}
	out["town"] = str(d.get("theme", "")) in ["settlement", "village"]
	var miss: Array = G.gate_missing(dep + 1)
	if not miss.is_empty():
		out["gate"] = ", ".join(miss)
	if G.store and G.store.travel_check(nxt) == "locked":
		out["locked"] = true
	return out


# ---- asset warm-up / preloading ---------------------------------------------------------

var _preloaded_assets: Array = []


func preload_assets() -> int:
	## Preload commonly used 3D meshes, scenes, and materials so initial floor load is warm
	var paths := [
		"res://art/meshes/chest.glb",
		"res://art/meshes/door.glb",
		"res://art/meshes/stairs.glb",
		"res://art/meshes/pillar.glb",
		"res://art/meshes/barrel.glb",
		"res://art/meshes/crate.glb",
		"res://art/meshes/urn.glb",
		"res://art/meshes/torch.glb",
		"res://art/meshes/lantern.glb",
		"res://art/meshes/shrine.glb",
		"res://art/meshes/portal.glb",
		"res://art/meshes/rock.glb",
		"res://art/meshes/crystal.glb",
		"res://art/materials/dungeon_stone.tres",
		"res://art/materials/dungeon_floor.tres",
		"res://art/materials/dungeon_wall.tres",
		"res://art/materials/cave_rock.tres",
		"res://art/materials/wood.tres",
		"res://art/materials/metal.tres",
		"res://art/materials/water.tres",
		"res://art/materials/fog.tres"
	]
	var loaded_count := 0
	for p in paths:
		if ResourceLoader.exists(p):
			var res = load(p)
			if res != null:
				_preloaded_assets.append(res)
				loaded_count += 1
	return loaded_count
