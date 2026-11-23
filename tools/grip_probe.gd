extends SceneTree
## prints the hand's frame: where the knuckles are in the hand bone's own axes, and the blade model's extents
func _initialize() -> void:
	await process_frame
	var D = load("res://scripts/world/Dress.gd")
	var m = preload("res://scripts/core/Art.gd").person(D.spec_for("Player", "", {"held": "sword"}), 1.0)
	root.add_child(m)
	var sk: Skeleton3D = D.skeleton(m)
	var hi := sk.find_bone("hand_r")
	print("hand_r idx ", hi, " children:")
	var rest_h: Transform3D = sk.get_bone_global_rest(hi)
	for i in sk.get_bone_count():
		if sk.get_bone_parent(i) == hi or sk.get_bone_name(i).ends_with("_r") and (sk.get_bone_name(i).begins_with("index") or sk.get_bone_name(i).begins_with("middle") or sk.get_bone_name(i).begins_with("ring") or sk.get_bone_name(i).begins_with("pinky") or sk.get_bone_name(i).begins_with("thumb")):
			var local: Vector3 = rest_h.affine_inverse() * sk.get_bone_global_rest(i).origin
			print(sk.get_bone_name(i), " in hand frame: ", local)
	print("hand basis (world axes of hand x,y,z at rest): ", rest_h.basis.x, rest_h.basis.y, rest_h.basis.z)
	var b: Node3D = preload("res://scripts/core/Art.gd").make("mini-dungeon/weapon-sword.glb", 0)
	root.add_child(b)
	var mn := Vector3(1e9, 1e9, 1e9)
	var mx := Vector3(-1e9, -1e9, -1e9)
	for mi in b.find_children("*", "MeshInstance3D", true, false):
		var bb: AABB = (mi as MeshInstance3D).get_aabb()
		var xf: Transform3D = b.global_transform.affine_inverse() * (mi as MeshInstance3D).global_transform
		for c in 8:
			var p: Vector3 = xf * bb.get_endpoint(c)
			mn = mn.min(p)
			mx = mx.max(p)
	print("blade model extents min ", mn, " max ", mx)
	quit()
