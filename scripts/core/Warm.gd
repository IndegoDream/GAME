extends RefCounted
## round 158 (Robert: "it takes a long time for the world to sync when moving from village to dungeon"): the first time a
## model is used it must be read and built -- ~2 s for a village, 0.2 s the second time. This reads them on background
## threads while you play, so the first visit to anywhere is already warm. Nothing here changes what is built.
## (data/warm_list.json: every model the levels name; tools/warm_check.gd keeps it honest.)

const LIST := "res://data/warm_list.json"
const IN_FLIGHT := 6

var _todo: Array = []
var _keep: Array = []             # models we have read stay held, or the engine lets go of them the moment we look away
var _live: Array = []
var done := 0
var total := 0


func start(keep_photo_models: bool = true) -> void:
	## (a phone keeps only the small models warm: the photo-scanned stand-ins carry big textures, and phones run short of memory)
	var d = JSON.parse_string(FileAccess.get_file_as_string(LIST)) if FileAccess.file_exists(LIST) else []
	_todo = d if d is Array else []
	if not keep_photo_models:
		_todo = _todo.filter(func(p): return not str(p).contains("/realistic/"))
	total = _todo.size()


func pending() -> int:
	return _todo.size() + _live.size()


func tick() -> void:
	## a few reads in flight at once; call once a frame
	var i := _live.size() - 1
	while i >= 0:
		var st := ResourceLoader.load_threaded_get_status(str(_live[i]))
		if st != ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			if st == ResourceLoader.THREAD_LOAD_LOADED:
				var r = ResourceLoader.load_threaded_get(str(_live[i]))
				if r is PackedScene:
					_keep.append(r)
			_live.remove_at(i)
			done += 1
		i -= 1
	while _live.size() < IN_FLIGHT and not _todo.is_empty():
		var p := str(_todo.pop_front())
		if not ResourceLoader.exists(p) or ResourceLoader.has_cached(p):
			done += 1
			continue
		if ResourceLoader.load_threaded_request(p) == OK:
			_live.append(p)
		else:
			done += 1
