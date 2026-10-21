extends SceneTree
## round 124: the Cloud save window opens, shows the right buttons, and its forms have their fields.
var passed := 0
var failed := 0
var frames := 0
var hud
func check(n: String, ok: bool, d: String = "") -> void:
	if ok: passed += 1
	else:
		failed += 1
		print("  FAIL  " + n + ("  [" + d + "]" if d != "" else ""))
func _btns() -> Array:
	var out := []
	for c in hud._dialog_buttons.get_children():
		if c is Button and not c.is_queued_for_deletion():
			out.append(c.text)
	return out
func _edits() -> int:
	var n := 0
	for c in hud._dialog_buttons.get_children():
		if c is LineEdit and not c.is_queued_for_deletion():
			n += 1
	return n
func _process(_dt: float) -> bool:
	frames += 1
	if frames == 5:
		var packed = load("res://Main.tscn")
		var main = packed.instantiate()
		root.add_child(main)
	if frames < 40:
		return false
	hud = get_first_node_in_group("hud")
	if hud == null:
		print("CLOUD UI CHECK: no HUD found")
		quit(1)
		return true
	var cs = root.get_node("Game").cloudsave
	cs.url = ""
	cs.anon = ""
	cs.session = {}
	hud.open_cloud(false)
	check("dialog open", hud._dialog.visible)
	check("not set up: offers the address", "Set up the cloud address..." in _btns(), str(_btns()))
	hud._cloud_setup_form(false)
	check("address form has two fields", _edits() == 2, str(_edits()))
	cs.url = "http://x.example"
	cs.anon = "k"
	hud.open_cloud(false)
	check("set up: offers sign in and account", "Sign in..." in _btns() and "Make an account..." in _btns(), str(_btns()))
	hud._cloud_login_form(false, false)
	check("sign-in form has email and a hidden password", _edits() == 2 and _pw_hidden())
	cs.session = {"access_token": "t", "refresh_token": "r", "expires_at": 9e12, "email": "a@b.co", "user_id": "u"}
	hud.open_cloud(false)
	check("signed in: sync, take, sign out", "Sync now" in _btns() and "Sign out" in _btns(), str(_btns()))
	check("the pause menu has the button", _find_pause_button())
	cs.session = {}
	cs.url = ""
	cs.anon = ""
	print("CLOUD UI CHECK %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)
	return true
func _find_pause_button() -> bool:
	for n in hud.find_children("*", "Button", true, false):
		if (n as Button).text == "Cloud save...":
			return true
	return false
func _pw_hidden() -> bool:
	for c in hud._dialog_buttons.get_children():
		if c is LineEdit and not c.is_queued_for_deletion() and c.secret:
			return true
	return false
