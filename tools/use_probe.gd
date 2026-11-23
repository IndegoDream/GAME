extends SceneTree
func _initialize() -> void:
	await process_frame
	var G = root.get_node("Game")
	G.new_game()
	await process_frame
	var ids: Array = []
	for id in G.items.keys():
		var d: Dictionary = G.item_def(id)
		if str(d.get("type", "")) == "consumable":
			ids.append(id)
	print("consumables: ", ids.size())
	G.hp = 10
	var bad := 0
	for id in ids.slice(0, 40):
		G.add_item(id, 1, false)
		var before: int = G.count(id)
		G.use_item(id)
		var after: int = G.count(id)
		if after >= before:
			bad += 1
			print("NOT CONSUMED ", id)
	print("use_probe done bad=", bad)
	quit()
