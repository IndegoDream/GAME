extends "res://scripts/actors/Enemy.gd"
## A rival disciple out in the valley (round 28): someone from another sect,
## walking the roads, who wants to see what you're made of. Talk to them
## (E) and they'll ask for a bout. It's a friendly fight, to a yield: when
## either of you is down to the last 15%, it's over -- nobody dies.
## They fight in their sect's way (foes.json "rivals"): fire charges, metal
## guards, wood keeps its distance and throws, water mends itself, earth
## brawls. Win, and you're paid in gold, insight and (if you belong to a
## sect) contribution; lose, and you learn something anyway. Each rival
## takes you on once a day. Game.rivals remembers them all.

var rival := {}               # {"name", "sect", "sect_name", "element", "line"}
var dueling := false


func setup(lvl, args: Dictionary) -> void:
	level = lvl
	cell = args.get("cell", Vector2i.ZERO)
	rival = args.get("rival", {})
	etype = "rival_disciple"
	stats = Game.rival_disciple_stats(rival)
	style = str(stats.get("style", "brawler"))
	_sd = Game.foes_data().get("styles", {}).get(style, {})
	_revealed = true
	hp = int(stats.get("hp", 60))


func _ready() -> void:
	super()
	add_to_group("interactable")
	add_to_group("rival")


func prompt() -> String:
	if dueling:
		return ""
	if Game.has_flag(_today_key()):
		return I18n.t("%s nods to you. (Tomorrow, another bout.)") % rival.get("name", I18n.t("The disciple"))
	return I18n.t("E: %s of the %s wants a bout") % [rival.get("name", I18n.t("A disciple")), rival.get("sect_name", "sect")]


func _today_key() -> String:
	return "duel:%s:%d" % [str(rival.get("name", "")), int(Time.get_unix_time_from_system() / 86400.0)]


func interact(_player) -> void:
	if dueling or _dead:
		return
	var hud = get_tree().get_first_node_in_group("hud")
	if hud == null:
		return
	if Game.has_flag(_today_key()):
		hud.open_dialog(str(rival.get("name", "")), "\"Again? Rest. Come find me tomorrow -- I'll have something new.\"", [["Leave", hud.close_dialog]])
		return
	var met: Dictionary = Game.rivals.get(str(rival.get("name", "")), {})
	var body := I18n.t("\"%s\"\n\n%s of the %s (%s). %s\n\nA friendly bout, to a yield -- whoever's down to their last breath first gives in.") % [
		rival.get("line", "Cross hands with me."), rival.get("name", ""), rival.get("sect_name", ""), rival.get("element", ""), describe()]
	if int(met.get("met", 0)) > 0:
		body += I18n.t("\n\nYou've crossed hands before: you won %d, they won %d.") % [int(met.get("beat", 0)), int(met.get("lost", 0))]
	hud.open_dialog(str(rival.get("name", "")), body, [["Cross hands", func():
		hud.close_dialog()
		begin()], ["Not today", hud.close_dialog]])


func begin() -> void:
	dueling = true
	stats["passive"] = false
	_chasing = true
	Game.log_event("duel_start", {"rival": rival.get("name", "")})
	Game.message.emit("BOUT: %s bows, and comes at you." % rival.get("name", ""))


func _physics_process(delta: float) -> void:
	if not dueling:
		# waiting by the road, watching you
		var player = get_tree().get_first_node_in_group("player")
		if player and _model and (player.global_position - global_position).length() < 12.0:
			var to: Vector3 = player.global_position - global_position
			to.y = 0.0
			_face(to)
		velocity = Vector3.ZERO
		if is_on_floor():
			_play("idle")
		else:
			velocity.y -= 20.0 * delta
		move_and_slide()
		return
	super(delta)


func deal(player, dmg: int) -> void:
	## a bout, not a killing: the blow that would take you under the line ends it
	if not dueling or player == null or not is_instance_valid(player):
		return
	var line := int(round(Game.max_hp() * float(Game.foes_data().get("rivals", {}).get("yield", 0.15))))
	if Game.hp - dmg <= line:
		Game.hp = maxi(Game.hp, line)
		_end(false)
		return
	super(player, dmg)


func take_damage(amount: int, source: String = "") -> void:
	if not dueling or _dead:
		return
	var line := int(round(float(stats.get("hp", 60)) * float(Game.foes_data().get("rivals", {}).get("yield", 0.15))))
	if hp - amount <= line:
		hp = line
		_update_label()
		_end(true)
		return
	super(amount, source)


func _end(you_won: bool) -> void:
	dueling = false
	stats["passive"] = true
	_chasing = false
	_attacking = 0.0
	_dash = 0.0
	_t2 = 0.0
	_tell(false)
	Game.set_flag(_today_key())
	Game.duel_result(rival, you_won)
	hp = int(stats.get("hp", 60))
	_update_label()
