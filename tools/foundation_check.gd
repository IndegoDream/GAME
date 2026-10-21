extends SceneTree
# Foundation: save versioning + data hash agreeing with the server's (python prints the expected hash in env ELITE_EXPECT_HASH)
var ok := 0
var bad := 0
func t(n: String, c: bool) -> void:
	if c: ok += 1
	else:
		bad += 1
		print("  FAIL ", n)
func _init() -> void:
	call_deferred("_run")
func _run() -> void:
	await process_frame
	var G = root.get_node("Game")
	var O = load("res://scripts/net/Online.gd").new()
	var h: String = O.data_hash()
	t("hash is 64 hex", h.length() == 64)
	var exp := OS.get_environment("ELITE_EXPECT_HASH")
	if exp != "":
		t("client hash == server hash", h == exp)
	t("save version const", G.SAVE_VERSION >= 1)
	var m: Dictionary = G._migrate_save({"realm": 2})
	t("old save gets stamped", int(m["save_version"]) == G.SAVE_VERSION and G.loaded_save_version == 0)
	var m2: Dictionary = G._migrate_save({"save_version": G.SAVE_VERSION})
	t("current save keeps version", G.loaded_save_version == G.SAVE_VERSION and int(m2["save_version"]) == G.SAVE_VERSION)
	print("FOUNDATION CHECK %d passed, %d failed" % [ok, bad])
	quit(1 if bad else 0)
