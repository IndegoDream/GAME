extends SceneTree
## designed gear draws: run with --script tools/dress_check.gd
func _initialize() -> void:
	await process_frame
	var H = load("res://scripts/actors/Human.gd")
	if not H.available():
		print("DRESS CHECK skipped (no human model)")
		quit()
		return
	var m: Node3D = H.make({"sex": "m", "outfit": "ranger", "hair": "long"})
	root.add_child(m)
	var base := []
	var looks := []
	for fam in ["pauldrons", "robe", "armor", "vambraces", "gauntlets"]:
		base.append({"family": fam, "look": "metal", "color": [0.5, 0.5, 0.5], "make": "crafted", "slot": fam})
		for lk in ["studs", "filigree", "flare", "runic"]:
			looks.append({"family": fam, "look": "metal", "color": [0.2, 0.2, 0.3], "make": "crafted", "slot": fam,
				"design": {"look": lk, "trim_color": [0.9, 0.8, 0.3], "glow": [0.5, 0.95, 1.0], "motif": lk}})
	var A = load("res://scripts/actors/Armour.gd")
	A.dress_gear(m, base)
	var n0 := m.find_children("Dress_Armour_*", "", true, false).size()
	for lk in looks:
		A.dress_gear(m, [lk])
	A.dress_gear(m, looks.slice(0, 4))
	var n1 := m.find_children("Dress_Armour_*", "", true, false).size()
	print("DRESS CHECK plain parts %d, designed parts %d" % [n0, n1])
	A.dress_gear(m, [])
	print("DRESS CHECK off again ", m.find_children("Dress_Armour_*", "", true, false).size() == 0)
	quit()
