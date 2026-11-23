extends SceneTree
var ok := 0
var bad := 0
func t(c: bool, n: String) -> void:
	if c: ok += 1
	else:
		bad += 1
		print("FAIL ", n)
func _initialize() -> void:
	await process_frame
	var src: String = FileAccess.get_file_as_string("res://scripts/actors/Companion.gd")
	t(src.contains("func talk("), "talk() exists")
	t(src.contains("remove_from_group(\"interactable\")") or src.contains("remove_from_group('interactable')"), "not interactable")
	var hub: String = FileAccess.get_file_as_string("res://scripts/ui/Hub.gd")
	t(hub.contains("Talk to %s"), "hub talk button")
	print("talk_menu_check: %d passed, %d failed" % [ok, bad])
	quit(1 if bad > 0 else 0)
