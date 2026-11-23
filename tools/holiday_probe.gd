extends SceneTree
func _initialize() -> void:
	await process_frame
	var G = root.get_node("Game")
	var W = G.sys("world")
	var e = Time.get_unix_time_from_datetime_dict({"year":2026,"month":1,"day":1,"hour":12,"minute":0,"second":0})
	for y in [2026, 2027]:
		for mo in range(1, 13):
			for da in range(1, 32):
				var u = Time.get_unix_time_from_datetime_dict({"year":y,"month":mo,"day":da,"hour":12,"minute":0,"second":0})
				if Time.get_datetime_dict_from_unix_time(int(u))["day"] != da: continue
				var d = int((u - e) / 86400.0)
				var h = W.real_holiday(d)
				if not h.is_empty(): print("%d-%02d-%02d %s" % [y, mo, da, h.get("id")])
	var wc = 0
	for d in range(0, 40):
		var f = W.festival(d)
		if not f.is_empty() and W.real_holiday(d).is_empty(): wc += 1
	print("non-real festival days in 40: ", wc, " today=", W.festival().get("id", "-"))
	quit()
