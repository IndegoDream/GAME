extends StaticBody3D
## The village fountain ('f'). It looks like decoration. It isn't quite.
## Press E to toss in a coin. Most of the time nothing happens.

var level
var cell := Vector2i.ZERO


func setup(lvl, args: Dictionary) -> void:
	level = lvl
	cell = args.get("cell", Vector2i.ZERO)


func _ready() -> void:
	add_to_group("interactable")
	var m = preload("res://scripts/core/Art.gd").make("fantasy-town-kit/fountain-round.glb")      # round 47: marble, not plastic
	m.scale = Vector3.ONE * 1.5
	add_child(m)
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 1.4
	cyl.height = 1.0
	shape.shape = cyl
	shape.position = Vector3(0, 0.5, 0)
	add_child(shape)
	level.astar.set_point_solid(cell, true)


func prompt() -> String:
	return "E: Toss a coin in the fountain" if Game.gold > 0 else "E: Look into the fountain"


func interact(_player) -> void:
	if Game.gold <= 0:
		Game.message.emit("Your reflection looks back. It seems to expect a coin.")
		return
	Game.gold -= 1
	Game.bump("coins")
	var n := int(Game.counters.get("coins", 0))
	Game.log_event("fountain_coin", {"n": n})
	if n == 7:
		Game.message.emit("The seventh coin doesn't sink. It floats, spins, and the water hums with qi.")
		Game.add_qi(77.0, "the fountain")
	elif n == 33:
		if not Game.has_treasure("storage_ring"):
			Game.message.emit("The thirty-third coin comes back up -- threaded on a plain iron ring. It's warm, and it's bigger inside than out.")
			Game.add_item("storage_ring", 1)
		else:
			Game.message.emit("The water parts around your coins and pushes them back to you, doubled. Someone down there likes you.")
			Game.add_item("gold", 66)
	elif n == 100:
		Game.message.emit("One hundred coins. The fountain sighs, and a pill rises from the basin.")
		Game.add_item("breakthrough_pill", 1)
	elif randf() < 0.08:
		Game.message.emit("A ripple runs the wrong way across the water.")
		Game.add_qi(5.0)
	else:
		Game.message.emit("Plink.")
	Game.stats_changed.emit()
