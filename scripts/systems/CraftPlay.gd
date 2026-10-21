extends "res://scripts/systems/GameSystem.gd"
## Round 141c: a mini-game for every craft. Robert, 2026-10-17: "a mini-game per craft (skill-based, balanced against fair-pay caps)".
##   smithing -> HAMMER   a heat marker sweeps; strike when it is in the glowing zone (5 strikes, faster each time)
##   alchemy  -> SIMMER   hold to heat, let go to cool: keep the flame in the moving band for 8 seconds
##   medicine -> POUR     hold to pour, let go on the line (3 measures)
##   jewelcrafting -> FACET  a pointer circles the stone; cut when it crosses the mark (6 cuts, the marks narrow)
##   runecraft, talismans -> TRACE  watch a short run of strokes, then draw it back
## It is always OPTIONAL (a switch on the Craft page, and a Skip button on the game itself) and always BOUNDED: a perfect
## game moves the odds of success by at most +12 points and the quality roll by +0.15, a bad one costs at most 4 points;
## it never lets anything be made that the materials and skill don't allow, never touches money, and gives the same
## to everyone. Skill and level still do most of the work (the odds are 70% + 7 points a level).
## Pure scoring lives here (static, tested without a screen); the screen is scripts/ui/CraftPlayUI.gd.
## data/craftplay.json.

var data := {}
var enabled := true
var pending := -1.0          # the score of the game just played; Game.craft_play_apply() takes it
var last := {}               # {"kind", "score", "text"} for the Craft page


func setup(game) -> void:
	super.setup(game)
	data = load_json("res://data/craftplay.json")


func reset() -> void:
	enabled = true
	pending = -1.0
	last = {}


func save_state() -> Dictionary:
	return {"enabled": enabled}


func load_state(d: Dictionary) -> void:
	reset()
	enabled = bool(d.get("enabled", true))


func kind_for(skill: String) -> String:
	return str(data.get("games", {}).get(skill, ""))


func has_game(skill: String) -> bool:
	return kind_for(skill) != ""


func take() -> float:
	var s := pending
	pending = -1.0
	return s


func bonus(score: float) -> Dictionary:
	## what a score is worth: a shift on the success roll and the quality roll (lower rolls are better), and skill xp
	var b: Dictionary = data.get("bonus", {})
	var s := clampf(score, 0.0, 1.0)
	return {"chance": lerpf(float(b.get("chance_lo", -0.04)), float(b.get("chance_hi", 0.12)), s),
		"quality": lerpf(float(b.get("quality_lo", -0.05)), float(b.get("quality_hi", 0.15)), s),
		"xp": 1.0 + float(b.get("xp_hi", 0.3)) * s}


func grade(score: float) -> String:
	if score >= 0.9:
		return I18n.t("Flawless")
	if score >= 0.7:
		return I18n.t("Fine work")
	if score >= 0.45:
		return I18n.t("Steady")
	return I18n.t("Rough")


func begin(skill: String, recipe: Dictionary, then: Callable) -> void:
	## play the craft's game if it's on and there is a screen to play it on; either way, then() makes the thing
	var hud = G.get_tree().get_first_node_in_group("hud") if G.get_tree() != null else null
	if not enabled or not has_game(skill) or hud == null or not hud.has_method("open_craftplay") or DisplayServer.get_name() == "headless":
		pending = -1.0
		then.call()
		return
	var lvl: int = G.skill_level(skill)
	var diff := int(recipe.get("difficulty", 0))
	hud.open_craftplay(kind_for(skill), skill, lvl - diff, func(score: float):
		pending = score
		if score >= 0.0:
			last = {"kind": kind_for(skill), "score": score, "text": grade(score)}
		then.call()
		pending = -1.0)


# ---- the rules of each game: pure functions ------------------------------------------------------------------------------------

static func tri(x: float) -> float:
	## a triangle wave, 0..1..0 with period 1
	return 1.0 - absf(fposmod(x, 1.0) * 2.0 - 1.0)


static func hit_score(dist: float, half_width: float) -> float:
	## how well a strike landed: the middle quarter of the zone is perfect
	if half_width <= 0.0:
		return 0.0
	var d := absf(dist) / half_width
	if d < 0.25:
		return 1.0
	if d < 0.5:
		return 0.75
	if d < 1.0:
		return 0.4
	return 0.0


func hammer_params(edge: int, strike: int) -> Dictionary:
	## the zone for strike n (0-based) when your skill is `edge` levels above the work (negative: below it)
	var h: Dictionary = data.get("hammer", {})
	var w := clampf(float(h.get("width_base", 0.22)) + float(h.get("width_per_level", 0.02)) * edge, float(h.get("width_min", 0.12)), float(h.get("width_max", 0.34)))
	var speed := float(h.get("speed", 0.9)) + float(h.get("speed_up", 0.12)) * strike
	var centre := 0.5 + 0.28 * sin(float(strike) * 2.1 + 0.7)
	return {"width": w, "speed": speed, "centre": centre}


func hammer_marker(t: float, speed: float) -> float:
	return tri(t * speed * 0.5)


func simmer_params(edge: int) -> Dictionary:
	var s: Dictionary = data.get("simmer", {})
	return {"seconds": float(s.get("seconds", 8.0)), "band": clampf(float(s.get("band", 0.22)) + 0.015 * edge, 0.14, 0.34),
		"rise": float(s.get("rise", 0.9)), "fall": float(s.get("fall", 0.7)), "drift": float(s.get("drift", 0.35))}


static func simmer_band_centre(t: float) -> float:
	return 0.55 + 0.08 * sin(t * 0.6)


static func simmer_step(temp: float, holding: bool, t: float, dt: float, p: Dictionary) -> float:
	var v := (float(p["rise"]) if holding else -float(p["fall"])) * dt + float(p["drift"]) * sin(t * 1.7 + 0.4) * dt
	return clampf(temp + v, 0.0, 1.0)


static func simmer_in_band(temp: float, t: float, p: Dictionary) -> bool:
	return absf(temp - simmer_band_centre(t)) <= float(p["band"]) * 0.5


func pour_params(edge: int) -> Dictionary:
	var s: Dictionary = data.get("pour", {})
	return {"rounds": int(s.get("rounds", 3)), "rate": float(s.get("rate", 0.55)), "tolerance": clampf(float(s.get("tolerance", 0.22)) + 0.012 * edge, 0.14, 0.34),
		"targets": [0.62, 0.38, 0.80, 0.5, 0.7]}


static func pour_score(fill: float, target: float, tolerance: float) -> float:
	return clampf(1.0 - absf(fill - target) / tolerance, 0.0, 1.0)


func facet_params(edge: int, cut: int) -> Dictionary:
	var s: Dictionary = data.get("facet", {})
	var arc := maxf(float(s.get("arc_min", 0.08)), float(s.get("arc_base", 0.18)) + 0.01 * edge - 0.012 * cut)
	return {"arc": arc, "speed": float(s.get("speed", 0.7)) + float(s.get("speed_up", 0.1)) * cut, "mark": fposmod(0.13 + 0.37 * float(cut) + 0.11 * sin(cut * 1.9), 1.0)}


static func facet_pointer(t: float, speed: float) -> float:
	return fposmod(t * speed, 1.0)


static func circ_dist(a: float, b: float) -> float:
	var d := absf(fposmod(a, 1.0) - fposmod(b, 1.0))
	return minf(d, 1.0 - d)


func trace_length(edge: int, level: int) -> int:
	var s: Dictionary = data.get("trace", {})
	return clampi(int(s.get("steps_base", 3)) + int(maxi(level, 0) / 3.0) + (1 if edge >= 3 else 0), int(s.get("steps_base", 3)), int(s.get("max", 7)))


static func trace_sequence(n: int, seed_value: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var out := []
	for i in n:
		out.append(rng.randi() % 4)             # 0 up, 1 right, 2 down, 3 left
	return out


static func trace_score(seq: Array, entered: Array) -> float:
	if seq.is_empty():
		return 0.0
	var ok := 0
	for i in seq.size():
		if i < entered.size() and int(entered[i]) == int(seq[i]):
			ok += 1
	return float(ok) / float(seq.size())
