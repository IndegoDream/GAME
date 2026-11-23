extends Node
## Phone beta self-update (Android test build only).
## The phone app asks Robert's box -- when it can reach it -- whether a newer beta is waiting
## (GET <box>/get/dungeon-crawl-eliet/latest.json) and offers to download it. Android never lets an app
## replace itself silently, so the download opens in the phone's browser and one tap installs it.
## The box address is typed once (first start) and kept in user://box_url.txt.

const SLUG := "dungeon-crawl-eliet"
const URL_FILE := "user://box_url.txt"
const SKIP := "skip"

var _http: HTTPRequest
var _base := ""
var _asked_build := -1
var _dialog: ConfirmationDialog
var _entry: LineEdit
var _apk_url := ""


static func local_build() -> int:
	var f := FileAccess.open("res://data/build_info.json", FileAccess.READ)
	if f == null:
		return 0
	var d = JSON.parse_string(f.get_as_text())
	return int(d.get("build", 0)) if d is Dictionary else 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_http = HTTPRequest.new()
	_http.timeout = 6.0
	add_child(_http)
	_http.request_completed.connect(_on_latest)
	_base = _read_url()
	get_tree().create_timer(6.0).timeout.connect(_start)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_RESUMED and _base != "" and _base != SKIP:
		check()


func _read_url() -> String:
	var f := FileAccess.open(URL_FILE, FileAccess.READ)
	return f.get_as_text().strip_edges() if f else ""


func _start() -> void:
	if _base == "":
		_ask_address()
	elif _base != SKIP:
		check()


func check() -> void:
	if _http == null or _http.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		return
	_http.request("%s/get/%s/latest.json" % [_base, SLUG])


func _on_latest(_result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	if code != 200:
		return                                   # the box is not reachable right now -- try again next time
	var d = JSON.parse_string(body.get_string_from_utf8())
	if not (d is Dictionary):
		return
	var newest := int(d.get("build", 0))
	if newest <= local_build() or newest == _asked_build:
		return
	_asked_build = newest
	_apk_url = "%s/get/%s/%s" % [_base, SLUG, str(d.get("file", ""))]
	_offer(newest)


func _offer(newest: int) -> void:
	var dlg := ConfirmationDialog.new()
	dlg.title = "Update available"
	dlg.dialog_text = "A newer beta (build %d) is on your box.\nDownload it now? (Tap the file when it finishes to install.)" % newest
	dlg.ok_button_text = "Download"
	dlg.cancel_button_text = "Later"
	dlg.confirmed.connect(func(): OS.shell_open(_apk_url))
	add_child(dlg)
	dlg.popup_centered(Vector2i(900, 360))


func _ask_address() -> void:
	_dialog = ConfirmationDialog.new()
	_dialog.title = "Connect to your box"
	_dialog.dialog_text = "To get beta updates automatically, type your box's address\n(for example 192.168.1.20:9214), or Skip."
	_dialog.ok_button_text = "Save"
	_dialog.cancel_button_text = "Skip"
	_entry = LineEdit.new()
	_entry.placeholder_text = "192.168.1.20:9214"
	_dialog.add_child(_entry)
	_entry.position = Vector2(20, 130)
	_entry.size = Vector2(700, 70)
	_dialog.confirmed.connect(_save_address)
	_dialog.canceled.connect(func(): _write(SKIP))
	add_child(_dialog)
	_dialog.popup_centered(Vector2i(900, 360))


func _save_address() -> void:
	var t := _entry.text.strip_edges().trim_suffix("/")
	if t == "":
		return
	if not t.begins_with("http"):
		t = "http://" + t
	_write(t)
	_base = t
	check()


func _write(t: String) -> void:
	var f := FileAccess.open(URL_FILE, FileAccess.WRITE)
	if f:
		f.store_string(t)
	_base = t
