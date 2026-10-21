extends SceneTree
## w002: Pursuit.eta_text() -- a train goal says about how long is left
var passed := 0
var failed := 0

func _ok(name: String, cond: bool) -> void:
	if cond:
		passed += 1
	else:
		failed += 1
		print("FAIL ", name)

func _hours(t: String) -> int:
	return int(t.split(" ")[1].trim_suffix("h"))

func _initialize() -> void:
	await process_frame
	var G = root.get_node("Game")
	var P = G.sys("pursuit")
	G.skills["unarmed"] = 0.0
	G.away_task = {"kind": "train", "skill": "unarmed", "goal": 3}
	var t: String = P.eta_text()
	_ok("a train goal gives text containing 'to go'", t.find("to go") >= 0)
	_ok("level 0 to 3 is about 3h", t == "about 3h to go")
	G.skills["unarmed"] = 90.0
	_ok("a goal already reached says nothing", P.eta_text() == "")
	G.away_task = {"kind": "meditate", "goal": 1}
	_ok("other kinds say nothing", P.eta_text() == "")
	G.away_task = {"kind": "train", "skill": "unarmed", "goal": 0}
	_ok("no goal says nothing", P.eta_text() == "")
	G.skills["unarmed"] = 0.0
	G.away_task = {"kind": "train", "skill": "unarmed", "goal": 10}
	var far: String = P.eta_text()
	G.away_task = {"kind": "train", "skill": "unarmed", "goal": 5}
	_ok("a farther goal takes longer", _hours(far) > _hours(P.eta_text()))
	G.away_task = {"kind": "train", "skill": "unarmed", "goal": 3}
	P.afk = true
	_ok("the chip carries it", P.chip_text().find("to go") >= 0)
	P.afk = false
	print("CHECK %d passed, %d failed" % [passed, failed])
	quit()
