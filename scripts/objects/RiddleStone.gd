extends StaticBody3D
## A riddle stone -- a face carved in rock that asks you something. Answer
## right and it gives; answer wrong and it falls silent for a while (the
## answer doesn't change -- think about it and come back). Defined in a
## level file's "riddles" section:
##   "Q": {"title": "The Weeping Face",
##         "question": "I have a mouth but never speak, a bed but never sleep.",
##         "options": ["A river", "A grave", "A cave"],
##         "answer": 0,
##         "reward": {"items": {"qi_pill": 2}, "qi": 120, "techniques": []}}

const SILENCE_SECONDS := 300.0

var level
var cell := Vector2i.ZERO
var title := "A Carved Face"
var question := ""
var options: Array = []
var answer := 0
var reward := {}
var _key := ""
var _eyes: OmniLight3D


func setup(lvl, args: Dictionary) -> void:
	level = lvl
	cell = args.get("cell", Vector2i.ZERO)
	var d: Dictionary = args.get("def", {})
	title = str(d.get("title", title))
	question = str(d.get("question", ""))
	options = d.get("options", [])
	answer = int(d.get("answer", 0))
	reward = d.get("reward", {})
	_key = Game.flag_key(level.level_id, cell, "riddle")


func _ready() -> void:
	add_to_group("interactable")
	if not solved():
		add_to_group("discoverable")
	var face = preload("res://scripts/core/Art.gd").make("nature-kit/statue_head.glb")
	face.scale = Vector3.ONE * 2.4
	add_child(face)
	_eyes = OmniLight3D.new()
	_eyes.light_color = Color(1.0, 0.8, 0.4)
	_eyes.omni_range = 3.5
	_eyes.position = Vector3(0, 1.4, 0.3)
	add_child(_eyes)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.0, 1.8, 1.0)
	shape.shape = box
	shape.position = Vector3(0, 0.9, 0)
	add_child(shape)
	level.astar.set_point_solid(cell, true)
	_refresh()


func solved() -> bool:
	return Game.has_flag(_key)


func silent() -> bool:
	return Game.gathered_recently(_key + ":wrong", SILENCE_SECONDS)


func _refresh() -> void:
	_eyes.light_energy = 0.0 if solved() or silent() else 1.4


func _process(_d: float) -> void:
	if Engine.get_process_frames() % 30 == 0:
		_refresh()


func prompt() -> String:
	if solved():
		return "E: Look at " + title
	return "E: Listen to " + title


func interact(_player) -> void:
	var hud = get_tree().get_first_node_in_group("hud")
	if solved():
		hud.open_dialog(title, "The eyes are dark. It asked, you answered; it has nothing more to say to you.", [["Leave it", hud.close_dialog]])
		return
	if silent():
		hud.open_dialog(title, "The face is silent. Its eyes are dark. (It will speak again in a while -- the answer won't have changed.)", [["Leave it", hud.close_dialog]])
		return
	Game.log_event("riddle_seen", {"title": title})
	var opts := []
	for i in options.size():
		opts.append([str(options[i]), choose.bind(i)])
	opts.append(["Say nothing", hud.close_dialog])
	hud.open_dialog(title, "The stone eyes open, and a voice like grinding rock:\n\n\"" + question + "\"", opts)


func choose(i: int) -> void:
	var hud = get_tree().get_first_node_in_group("hud")
	if i == answer:
		Game.set_flag(_key)
		Game.log_event("riddle_solved", {"title": title})
		Game.note_place("Answered " + title)
		remove_from_group("discoverable")
		var got := []
		for id in reward.get("items", {}):
			Game.add_item(str(id), int(reward["items"][id]))
			got.append(Game.item_name(str(id)))
		for tid in reward.get("techniques", []):
			Game.learn(str(tid), "riddle:" + title)
		if reward.has("qi"):
			Game.add_qi(float(reward["qi"]), title)
		hud.open_dialog(title, "\"...Yes.\"\n\nThe stone sighs, and something is left at its feet." + (" (%s)" % ", ".join(got) if got.size() > 0 else ""), [["Take it", hud.close_dialog]])
	else:
		Game.set_flag(_key + ":wrong", Time.get_unix_time_from_system())
		Game.log_event("riddle_wrong", {"title": title, "said": str(options[i])})
		hud.open_dialog(title, "\"No.\"\n\nThe eyes go dark. It will not speak to you again for a while.", [["Leave it", hud.close_dialog]])
	_refresh()
