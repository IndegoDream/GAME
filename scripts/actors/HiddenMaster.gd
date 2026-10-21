extends StaticBody3D
## A hidden master (round 34 -- Robert: "put hidden masters throughout the
## game"). Someone ordinary: a sweeper, a ratcatcher, a cook, a beggar.
## Talk to them enough -- and be strong enough -- and they show who they
## are, set a test, and, once it's passed, teach a technique no one else
## knows (Game.gd "hidden masters", data/hidden_masters.json).

var level
var cell := Vector2i.ZERO
var master_id := ""
var _label: Label3D


func setup(lvl, args: Dictionary) -> void:
	level = lvl
	cell = args.get("cell", Vector2i.ZERO)
	master_id = str(args.get("id", ""))


func _m() -> Dictionary:
	return Game.hm_master(master_id)


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("hidden_master")
	var m := _m()
	var spec: Dictionary = (m.get("look", {}) as Dictionary).duplicate(true)
	var child := bool(spec.get("child", false))
	spec.erase("child")
	var fig: Node3D = preload("res://scripts/core/Art.gd").person(spec)
	if child:
		fig.scale *= 0.62
	add_child(fig)
	preload("res://scripts/world/Dress.gd").dress(fig, spec)
	for ap in fig.find_children("*", "AnimationPlayer", true, false):
		var a := ap as AnimationPlayer
		if a.has_animation("idle"):
			a.get_animation("idle").loop_mode = Animation.LOOP_LINEAR
			a.play("idle")
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.pixel_size = 0.008
	_label.no_depth_test = true
	_label.font_size = 30
	_label.outline_size = 8
	_label.position = Vector3(0, 1.4 if child else 2.2, 0)
	add_child(_label)
	_refresh()
	var shape := CollisionShape3D.new()
	var b := CapsuleShape3D.new()
	b.radius = 0.35
	b.height = 1.0 if child else 1.7
	shape.shape = b
	shape.position = Vector3(0, b.height / 2.0, 0)
	add_child(shape)
	if level and level.get("astar"):
		level.astar.set_point_solid(cell, true)


func _refresh() -> void:
	var m := _m()
	var st := Game.hm_stage(master_id)
	if st == "":
		_label.text = str(m.get("disguise", "someone")).capitalize()
		_label.modulate = Color(0.85, 0.85, 0.8)
	else:
		_label.text = str(m.get("name", ""))
		_label.modulate = Color(1.0, 0.82, 0.45)
		if st == "done":
			_label.text += I18n.t("\n(your teacher)")


func prompt() -> String:
	if Game.hm_stage(master_id) == "":
		return I18n.t("E: Talk to %s") % str(_m().get("disguise", "them"))
	return "E: %s" % str(_m().get("name", ""))


func interact(_player) -> void:
	var hud = get_tree().get_first_node_in_group("hud")
	if hud == null:
		return
	var m := _m()
	var title := str(m.get("disguise", "")).capitalize()
	var st := Game.hm_stage(master_id)
	if st == "":
		var r := Game.hm_talk(master_id)
		_refresh()
		if r == "reveal":
			hud.open_dialog(str(m.get("name", "")), I18n.t("%s\n\nTheir test: %s") % [str(m.get("reveal_text", "")), str(m.get("test", {}).get("text", ""))],
				[["\"I'll do it.\"", hud.close_dialog]])
			return
		Game.log_event("hm_talk", {"id": master_id})
		hud.open_dialog(title, Game.hm_line(master_id), [["Leave them be", hud.close_dialog]])
		return
	title = str(m.get("name", ""))
	if st == "done":
		var opts0 := []
		if str(m.get("table", "")) != "":
			# round 38: a craft master's table -- carve, draw, set runes
			opts0.append(["Work at their table", func():
				hud.close_dialog()
				hud.open_kit("Runes", "rune")])
			if str(m.get("table", "")) == "runecraft":
				opts0.append(["Ask about rune words", func():
					hud.open_dialog(title, _word_hint(), [["Back", func(): interact(_player)], ["Bow, and go", hud.close_dialog]])])
		opts0.append(["Bow, and go", hud.close_dialog])
		hud.open_dialog(title, str(m.get("after", "")), opts0)
		return
	var p := Game.hm_test_progress(master_id)
	var body := I18n.t("Their test: %s (%d / %d)") % [str(m.get("test", {}).get("text", "")), int(p[0]), int(p[1])]
	var opts := []
	if Game.hm_test_ready(master_id):
		opts.append(["Show them", func():
			Game.hm_complete(master_id)          # (its window says what they taught)
			_refresh()
			hud.close_dialog()])
	else:
		body = I18n.t("\"Not yet.\"\n\n") + body
	opts.append(["Leave", hud.close_dialog])
	hud.open_dialog(title, body, opts)



func _word_hint() -> String:
	## Oda tells you one word you haven't spoken yet -- its marks, in order.
	## He won't tell you another until you've cut the last one he told you.
	var pick := {}
	for w in Game.runes_data().get("words", []):
		if not Game.rune_word_known(str(w.get("id", ""))) and Game.has_flag("runeword_told:" + str(w.get("id", ""))):
			pick = w
			break
	if pick.is_empty():
		for w in Game.runes_data().get("words", []):
			if not Game.rune_word_known(str(w.get("id", ""))):
				pick = w
				break
	for w in ([pick] if not pick.is_empty() else []):
		var marks: Array = (w.get("runes", []) as Array).map(func(r): return Game.rune_mark(str(r)))
		Game.set_flag("runeword_told:" + str(w.get("id", "")))
		return I18n.t("\"%s. %s -- on %s. Cut them in that order and they'll speak.\" (%s)") % [str(w.get("hint", "")), ", then ".join(marks),
			{"weapon": "a blade", "wear": "something you wear", "any": "anything"}.get(str(w.get("on", "any")), "anything"), str(w.get("name", ""))]
	return I18n.t("\"You've heard every word I know. There are more. There are always more.\"")
