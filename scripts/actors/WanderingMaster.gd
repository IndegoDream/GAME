extends StaticBody3D
## A wandering master (round 30 world event): an old cultivator camped by a
## little fire on this floor, today only. Sit and listen (for a fee) and you
## come away with insight and a push to your cultivation; ask about your
## blood and they can tell you things about it -- even what hasn't woken yet.

var level
var cell := Vector2i.ZERO
var _key := ""
var _fire: OmniLight3D


func setup(lvl, args: Dictionary) -> void:
	level = lvl
	cell = args.get("cell", Vector2i.ZERO)
	_key = "master:%s:%s" % [level.level_id if level else "", Game.today()]


func _ready() -> void:
	add_to_group("interactable")
	var Art := preload("res://scripts/core/Art.gd")
	var fig: Node3D = Art.person({"sex": "m" if hash(_key) % 2 == 0 else "f", "hair": "topknot", "beard": hash(_key) % 2 == 0,
		"hair_color": [0.8, 0.8, 0.8], "robe": [0.35, 0.3, 0.45], "outfit": "ranger"})
	fig.position = Vector3(0, 0, 0)
	add_child(fig)
	for ap in fig.find_children("*", "AnimationPlayer", true, false):
		var a := ap as AnimationPlayer
		if a.has_animation("sit"):
			a.play("sit")
	var camp = Art.make("nature-kit/campfire_stones.glb") if ResourceLoader.exists("res://assets/kenney/nature-kit/campfire_stones.glb") else null
	if camp:
		camp.position = Vector3(0, 0, 1.3)
		add_child(camp)
	if DisplayServer.get_name() != "headless":
		_fire = OmniLight3D.new()
		_fire.light_color = Color(1.0, 0.6, 0.25)
		_fire.light_energy = 2.0
		_fire.omni_range = 6.0
		_fire.position = Vector3(0, 0.8, 1.3)
		add_child(_fire)
		preload("res://scripts/fx/FX.gd").aura(self, Color(1.0, 0.55, 0.2), 0.6, 10).position = Vector3(0, 0.2, 1.3)
	var shape := CollisionShape3D.new()
	var b := CapsuleShape3D.new()
	b.radius = 0.4
	b.height = 1.2
	shape.shape = b
	shape.position = Vector3(0, 0.6, 0)
	add_child(shape)


func _process(_delta: float) -> void:
	if _fire:
		_fire.light_energy = 1.8 + sin(Time.get_ticks_msec() / 90.0) * 0.25 + sin(Time.get_ticks_msec() / 37.0) * 0.15


func prompt() -> String:
	return I18n.t("E: Sit with the wandering master")


func fee() -> int:
	return 20 * maxi(int(level.def.get("depth", 1)) if level else 1, 1)


func interact(_player) -> void:
	var hud = get_tree().get_first_node_in_group("hud")
	if hud == null:
		return
	var opts := []
	if not Game.has_flag(_key):
		opts.append(["Sit and listen (%d gold)" % fee(), func(): hud.open_dialog(I18n.t("The Wandering Master"), listen(), [["Thank them", hud.close_dialog]])])
	opts.append(["Ask about your blood", func(): hud.open_dialog(I18n.t("The Wandering Master"), read_blood(), [["Leave", hud.close_dialog]])])
	opts.append(["Leave", hud.close_dialog])
	hud.open_dialog("The Wandering Master", "\"Sit, if you like. The fire's free. The talk costs a little -- I'm old, not a fool.\"", opts)


func listen() -> String:
	if Game.has_flag(_key):
		return I18n.t("\"I've told you what I had for today.\"")
	if Game.gold < fee():
		return I18n.t("\"Come back with %d gold. Wisdom's cheap; my supper isn't.\"") % fee()
	Game.gold -= fee()
	Game.set_flag(_key)
	Game.gain_insight(3.0, "a wandering master")
	Game.add_qi(Game.qi_to_next() * 0.15, "a wandering master's lesson")
	Game.log_event("event_master", {})
	return I18n.t("They talk until the fire is embers -- about breath, and the space between two heartbeats, and a fight they lost sixty years ago. You come away understanding something you didn't before.")


func read_blood() -> String:
	if not Game.blood_awake():
		if not (Game.bloodline.get("hidden", {}) as Dictionary).is_empty():
			return I18n.t("They take your wrist, and their eyebrows go up. \"There's more in your veins than you know. It's asleep. Go deeper -- around the twentieth floor the deep wakes things like that.\"")
		if Game.blood_dominant() != "":
			return I18n.t("\"%s blood. Plain as day, and still asleep. Deeper down, it'll wake.\"") % Game.blood_line(Game.blood_dominant()).get("name", "")
		return I18n.t("\"Plain blood. Don't look like that -- most great cultivators started with plain blood. Blood can be found.\"")
	var rows := Game.blood_rows()
	if rows.is_empty():
		return I18n.t("\"Nothing yet. The masters who died down here left more than techniques -- and the strong carry drops of old blood. Look for both.\"")
	var out := []
	for r in rows:
		var nxt := ""
		for m in Game.blood_data().get("milestones", []):
			if float(r[1]) < float(m.get("at", 0)):
				nxt = " -- %d%% to %s" % [int(ceil(float(m["at"]) - float(r[1]))), m.get("name", "")]
				break
		out.append(I18n.t("%s, %s line: %d%% (%s)%s") % [r[0], r[3], int(r[1]), r[2], nxt])
	return I18n.t("They hold your wrist a long while.\n\n") + "\n".join(out) + I18n.t("\n\n\"Fight its kin; sit at shrines; take what the dead masters left. It'll thicken.\"")
