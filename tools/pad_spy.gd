extends Node
var got := 0
func _input(e: InputEvent) -> void:
	if e.is_action_pressed("inventory"):
		got += 1
