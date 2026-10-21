extends RefCounted
## The Lotus Ascent Academy -- a school that only takes those who prove
## themselves (Robert, 2026-10-02: "a school entry exam"). Its entrance
## exam has three trials: Strength (the arena), Knowledge (questions about
## what a cultivator should know -- the five elements, the realms, what
## things are for), and Craft (bring something you made yourself, Fine or
## better). Pass all three and you're an Outer Disciple; the Academy's ranks
## above that each need standing, a realm, and a rank trial in the arena.

const ELEMENTS := ["wood", "fire", "earth", "metal", "water"]
## generating cycle: each feeds the next
const FEEDS := {"wood": "fire", "fire": "earth", "earth": "metal", "metal": "water", "water": "wood"}
## overcoming cycle: each overcomes this one
const OVERCOMES := {"wood": "earth", "earth": "water", "water": "fire", "fire": "metal", "metal": "wood"}
const PASS_MARK := 4
const QUESTIONS := 5


static func _opts(rng: RandomNumberGenerator, right: String, pool: Array, n: int = 3) -> Array:
	var others := []
	for p in pool:
		if str(p) != right and not (str(p) in others):
			others.append(str(p))
	var out := [right]
	while out.size() < n and others.size() > 0:
		out.append(others.pop_at(rng.randi_range(0, others.size() - 1)))
	# shuffle
	for i in range(out.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = out[i]
		out[i] = out[j]
		out[j] = t
	return out


static func question(kind: int, rng: RandomNumberGenerator) -> Dictionary:
	## {"q": text, "options": [...], "answer": index}
	var right := ""
	var q := ""
	var pool: Array = []
	match kind % 7:
		0:
			var e: String = ELEMENTS[rng.randi_range(0, 4)]
			q = "In the generating cycle, what does %s feed?" % e.capitalize()
			right = str(FEEDS[e]).capitalize()
			pool = ELEMENTS.map(func(x): return str(x).capitalize())
		1:
			var e2: String = ELEMENTS[rng.randi_range(0, 4)]
			q = "Which element does %s overcome?" % e2.capitalize()
			right = str(OVERCOMES[e2]).capitalize()
			pool = ELEMENTS.map(func(x): return str(x).capitalize())
		2:
			var i := rng.randi_range(0, 4)
			q = "Which realm comes after %s?" % Game.realm_info(i)["name"]
			right = str(Game.realm_info(i + 1)["name"])
			pool = []
			for k in 8:
				pool.append(str(Game.realm_info(k)["name"]))
		3:
			var heals := []
			for id in Game.items:
				if Game.items[id].get("type") == "consumable" and Game.items[id].has("heal"):
					heals.append(id)
			heals.sort()
			var pick: String = heals[rng.randi_range(0, heals.size() - 1)] if heals.size() > 0 else "healing_salve"
			q = "What is a %s for?" % Game.item_name(pick)
			right = "It heals wounds"
			pool = ["It heals wounds", "It feeds your qi", "It is only a crafting material", "It sharpens a blade"]
		4:
			var qis := []
			for id in Game.items:
				if Game.items[id].get("type") == "consumable" and Game.items[id].has("qi") and not Game.items[id].has("heal"):
					qis.append(id)
			qis.sort()
			var pick2: String = qis[rng.randi_range(0, qis.size() - 1)] if qis.size() > 0 else "qi_pill"
			q = "What is a %s for?" % Game.item_name(pick2)
			right = "It feeds your qi"
			pool = ["It heals wounds", "It feeds your qi", "It is only a crafting material", "It wards off traps"]
		5:
			var far := rng.randf() < 0.5
			q = "Which weapon reaches the farthest?" if far else "Which weapon strikes the fastest?"
			right = "Halberd" if far else "Fist Wraps"
			pool = ["Halberd", "Fist Wraps", "Dagger", "Hammer", "Sword", "Spear" if not far else "Saber"]
		_:
			q = "Which two guilds will each trust you only half as much if you belong to both?"
			right = "The Alchemists' Circle and the Healers' House"
			pool = ["The Alchemists' Circle and the Healers' House", "The Adventurers' Lodge and the Gatherers' Hall",
				"The Blacksmiths' Guild and the Alchemists' Circle"]
	var opts := _opts(rng, right, pool)
	return {"q": q, "options": opts, "answer": opts.find(right)}


static func exam_questions(seed_: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	var kinds := [0, 1, 2, 3, 4, 5, 6]
	var out := []
	while out.size() < QUESTIONS and kinds.size() > 0:
		var k: int = kinds.pop_at(rng.randi_range(0, kinds.size() - 1))
		out.append(question(k, rng))
	return out
