extends Node
## Elite Online -- the client (round 125). One WebSocket to the server in tools/server/. This node knows the state of the
## connection and of the shared world (hub, party, queue, an instance in progress); the places it draws live in
## OnlineWorld.gd and the windows in OnlineMenu.gd.
##
## Nothing here writes a solo save except one thing: a `grant` -- materials the server hands over when a player takes
## them out of the Gate. A grant is added to the pouch once (its id is remembered) and then acknowledged.

var data_ok := true                    # false when the server reports our game data differs from its own
signal changed                       # something the windows show has changed
signal net(m)                        # every message from the server, for OnlineWorld

const DEFAULT_URL := "ws://100.96.204.37:8765"
const CONFIG := "user://online.json"
const TIMEOUT := 25.0

var url := DEFAULT_URL
var state := "off"                   # off | connecting | login | nochar | char | hub | instance
var char := {}                       # my online character (name, realm, step, level, gold, marks, inv, titles)
var tiers := {}
var events := []
var party := {}                      # {id, leader, members:[{id,name,...}]} or {}
var invites := []                    # [{pid, from}]
var queued := {}                     # {kind, tier} while waiting for a match
var players := {}                    # the hub: id -> {id, name, realm, x, z, yaw, anim}
var shard := 0
var inst := {}                       # the instance I'm in: id, kind, tier, depth, radius, me, hpmax, members, boss, phase ...
var last_error := ""
var last_code := ""
var server_skew := 0.0               # server time minus local time
var sel_tier := 1
var dev_name := ""                   # tests only: a name for a development server
var drive_game := true               # false: a second client for tests that must not move the game around
var solo_hp := -1                    # my solo hit points, put back when I leave an instance
var _ws: WebSocketPeer = null
var _last := {}                      # message type -> the latest message of that type
var _ping_t := 0.0
var _seen_grants := {}


func _ready() -> void:
	load_config()
	set_process(true)


func load_config() -> void:
	if not FileAccess.file_exists(CONFIG):
		return
	var f := FileAccess.open(CONFIG, FileAccess.READ)
	if f == null:
		return
	var d = JSON.parse_string(f.get_as_text())
	if d is Dictionary:
		url = str(d.get("url", DEFAULT_URL))
		sel_tier = int(d.get("tier", 1))


func save_config() -> void:
	var f := FileAccess.open(CONFIG, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"url": url, "tier": sel_tier}))


func is_connected_ok() -> bool:
	return state in ["char", "hub", "instance"]


const HASH_FILES := ["enemies.json", "items.json", "gates.json", "online_events.json"]      # same list as the server


func data_hash() -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	for n in HASH_FILES:
		var h: String = FileAccess.get_sha256("res://data/" + n)
		ctx.update((n + ":" + (h if h != "" else "missing") + "\n").to_utf8_buffer())
	return ctx.finish().hex_encode()


func build_number() -> int:
	var f := FileAccess.open("res://data/build_info.json", FileAccess.READ)
	if f:
		var d = JSON.parse_string(f.get_as_text())
		if d is Dictionary:
			return int(d.get("build", 0))
	return 0


# ---- connecting ----------------------------------------------------------------------------------------------------

func connect_now() -> bool:
	close()
	last_error = ""
	last_code = ""
	_ws = WebSocketPeer.new()
	_ws.inbound_buffer_size = 1 << 20
	var err := _ws.connect_to_url(url)
	if err != OK:
		last_error = "That server address doesn't look right (%s)." % url
		_ws = null
		state = "off"
		changed.emit()
		return false
	state = "connecting"
	_connect_t = Time.get_ticks_msec() / 1000.0
	changed.emit()
	return true


var _connect_t := 0.0


func close() -> void:
	restore_solo()
	if _ws != null:
		_ws.close()
		_ws = null
	state = "off"
	players.clear()
	party = {}
	invites.clear()
	queued = {}
	inst = {}


func sign_in_token() -> String:
	var cs = Game.cloudsave
	if cs != null and cs.signed_in():
		return str(cs.session.get("access_token", ""))
	return ""


func _hello() -> void:
	var cs = Game.cloudsave
	if cs != null and cs.signed_in() and float(cs.session.get("expires_at", 0)) < Time.get_unix_time_from_system() + 90.0:
		await cs._refresh()
	var m := {"t": "hello", "build": build_number(), "token": sign_in_token(), "data": data_hash()}
	var who: String = cs.email() if cs != null and cs.signed_in() else "player"
	m["dev"] = dev_name if dev_name != "" else who.get_slice("@", 0)
	send(m)


func send(m: Dictionary) -> void:
	if _ws != null and _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_ws.send_text(JSON.stringify(m))


func _process(delta: float) -> void:
	if _ws == null:
		return
	_ws.poll()
	match _ws.get_ready_state():
		WebSocketPeer.STATE_CONNECTING:
			if state == "connecting" and Time.get_ticks_msec() / 1000.0 - _connect_t > 12.0:
				last_error = "The Gate didn't answer. Is the server running, and is the address right?"
				close()
				changed.emit()
		WebSocketPeer.STATE_OPEN:
			if state == "connecting":
				state = "login"
				_hello()
			while _ws != null and _ws.get_available_packet_count() > 0:
				var txt := _ws.get_packet().get_string_from_utf8()
				var m = JSON.parse_string(txt)
				if m is Dictionary:
					_handle(m)
			_ping_t += delta
			if _ping_t > 15.0:
				_ping_t = 0.0
				send({"t": "ping", "n": 1})
		WebSocketPeer.STATE_CLOSED:
			var was := state
			if last_error == "" and was != "off":
				last_error = "The connection to the Gate closed."
			_ws = null
			state = "off"
			players.clear()
			party = {}
			queued = {}
			var had_inst := not inst.is_empty()
			inst = {}
			net.emit({"t": "_closed", "was": was, "inst": had_inst})
			changed.emit()


func wait_for(t: String, timeout: float = 6.0) -> Dictionary:
	## the next message of this type (awaits; {} if none came in time)
	_last.erase(t)
	var end := Time.get_ticks_msec() + int(timeout * 1000.0)
	while Time.get_ticks_msec() < end:
		if _last.has(t):
			return _last[t]
		await get_tree().process_frame
	return {}


func ask(m: Dictionary, reply: String, timeout: float = 6.0) -> Dictionary:
	_last.erase(reply)
	send(m)
	return await wait_for(reply, timeout)


func wait_any(types: Array, timeout: float = 6.0) -> Dictionary:
	for t in types:
		_last.erase(t)
	var end := Time.get_ticks_msec() + int(timeout * 1000.0)
	while Time.get_ticks_msec() < end:
		for t in types:
			if _last.has(t):
				return _last[t]
		await get_tree().process_frame
	return {}


func wait_state(want: Array, timeout: float = 12.0) -> String:
	var end := Time.get_ticks_msec() + int(timeout * 1000.0)
	while Time.get_ticks_msec() < end:
		if state in want:
			return state
		if state == "off" and _ws == null:
			return state
		await get_tree().process_frame
	return state


func server_now() -> float:
	return Time.get_unix_time_from_system() + server_skew


# ---- what the server says ------------------------------------------------------------------------------------------

func _handle(m: Dictionary) -> void:
	var t := str(m.get("t", ""))
	_last[t] = m
	match t:
		"welcome":
			tiers = m.get("tiers", {})
			data_ok = bool(m.get("data_ok", true))
			if not data_ok:
				push_warning("Online: game data differs from the server's (update the game)")
			events = m.get("events", [])
			server_skew = float(m.get("server_time", 0.0)) - Time.get_unix_time_from_system()
			if bool(m.get("has_char", false)):
				char = m.get("char", {})
				state = "char"
			else:
				state = "nochar"
		"char":
			char = m.get("char", {})
			if state == "nochar":
				state = "char"
		"char_error":
			last_error = str(m.get("msg", ""))
		"error":
			last_error = str(m.get("msg", "Something went wrong."))
			last_code = str(m.get("code", ""))
			if state == "login" or state == "connecting":
				pass
			elif last_code == "":
				Game.message.emit(last_error)
		"pong":
			server_skew = float(m.get("server_time", 0.0)) - Time.get_unix_time_from_system()
		"hub":
			state = "hub"
			shard = int(m.get("shard", 0))
			players.clear()
			for p in m.get("players", []):
				players[str(p["id"])] = p
		"h_join":
			var p: Dictionary = m["p"]
			players[str(p["id"])] = p
		"h_leave":
			players.erase(str(m.get("id", "")))
		"h_state":
			for r in m.get("p", []):
				var k := str(r[0])
				if players.has(k):
					players[k]["x"] = float(r[1])
					players[k]["z"] = float(r[2])
					players[k]["yaw"] = float(r[3])
					players[k]["anim"] = str(r[4])
		"left_hub":
			if state == "hub":
				state = "char"
			players.clear()
		"chat":
			var ch := str(m.get("ch", "hub"))
			var tag: String = {"hub": "", "party": "(party) ", "inst": "(group) ", "whisper": "(whisper) "}.get(ch, "")
			Game.message.emit("%s%s: %s" % [tag, m.get("from", "?"), m.get("text", "")])
		"chat_error", "party_error", "queue_error", "market_error", "mail_error":
			Game.message.emit(str(m.get("msg", "")))
			last_error = str(m.get("msg", ""))
		"party":
			party = m if int(m.get("id", 0)) != 0 else {}
		"p_invited":
			invites.append({"pid": int(m["pid"]), "from": str(m["from"])})
			Game.message.emit("%s invites you to a party. (Gate menu -> Party)" % m["from"])
		"queued":
			queued = {"kind": m.get("kind", "run"), "tier": int(m.get("tier", 1))}
		"unqueued":
			queued = {}
		"inst_start":
			_instance_start(m)
		"i_join":
			if not inst.is_empty():
				inst["members"][str(m["id"])] = str(m.get("name", "?"))
		"i_left":
			if not inst.is_empty():
				inst["members"].erase(str(m.get("id", "")))
				inst["pl"].erase(str(m.get("id", "")))
		"i_spawn":
			if not inst.is_empty():
				var f: Dictionary = m["foe"]
				inst["foes"][int(f["id"])] = f
		"i_gone":
			if not inst.is_empty():
				inst["foes"].erase(int(m.get("id", 0)))
				inst["orbs"].erase(int(m.get("id", 0)))
		"i_foe_hp":
			if not inst.is_empty() and inst["foes"].has(int(m["id"])):
				inst["foes"][int(m["id"])]["hp"] = float(m["hp"])
				inst["foes"][int(m["id"])]["max"] = float(m["max"])
		"i_dmg":
			if not inst.is_empty() and inst["foes"].has(int(m["id"])):
				inst["foes"][int(m["id"])]["hp"] = float(m["hp"])
		"i_hazard":
			if not inst.is_empty():
				var h: Dictionary = m["h"]
				h["t0"] = Time.get_ticks_msec() / 1000.0
				h["total"] = float(h.get("t", 1.0))
				inst["haz"][int(h["id"])] = h
		"i_boom":
			if not inst.is_empty():
				inst["haz"].erase(int(m.get("id", 0)))
		"i_orb":
			if not inst.is_empty():
				inst["orbs"][int(m["id"])] = Vector2(float(m["x"]), float(m["z"]))
		"i_orb_gone":
			if not inst.is_empty():
				inst["orbs"].erase(int(m.get("id", 0)))
		"i_phase":
			if inst.is_empty():
				pass
			else:
				if m.has("hpmax"):
					inst["hpmax"] = m["hpmax"]
				inst["phase"] = str(m.get("ph", ""))
				inst["text"] = str(m.get("text", ""))
				inst["phase_secs"] = float(m.get("secs", 0.0))
				inst["phase_at"] = Time.get_ticks_msec() / 1000.0
		"i_state":
			if not inst.is_empty():
				for r in m.get("p", []):
					inst["pl"][str(r[0])] = r
					if str(r[0]) == str(inst.get("me", "")):
						inst["hp"] = float(r[4])
						inst["alive"] = int(r[5]) == 1
				var seen := {}
				for r in m.get("f", []):
					var fid := int(r[0])
					seen[fid] = true
					if inst["foes"].has(fid):
						var ff: Dictionary = inst["foes"][fid]
						ff["x"] = float(r[1])
						ff["z"] = float(r[2])
						ff["hp"] = float(r[3])
						ff["state"] = str(r[4])
				for fid in inst["foes"].keys():
					if not seen.has(fid):
						inst["foes"].erase(fid)
		"i_hurt":
			if not inst.is_empty() and str(m.get("id", "")) == str(inst.get("me", "")):
				inst["hp"] = float(m.get("hp", 0))
		"i_down":
			if not inst.is_empty() and str(m.get("id", "")) == str(inst.get("me", "")):
				inst["alive"] = false
				inst["down_at"] = Time.get_ticks_msec() / 1000.0
		"i_up":
			if not inst.is_empty() and str(m.get("id", "")) == str(inst.get("me", "")):
				inst["alive"] = true
				inst["hp"] = float(m.get("hp", 0))
		"i_end":
			if not inst.is_empty():
				inst["end"] = m
			if m.has("char"):
				char = m["char"]
		"left_inst":
			inst = {}
			if state == "instance":
				state = "char"
		"events":
			events = m.get("events", [])
			server_skew = float(m.get("server_time", 0.0)) - Time.get_unix_time_from_system()
		"event_start":
			Game.message.emit("%s has begun! Find the Event Obelisk in the hub." % str(m.get("event", {}).get("name", "A world event")))
		"grant":
			_take_grant(m)
		"account_deleted":
			char = {}
			close()
		"mail_new":
			Game.message.emit("New post at the Gate.")
	net.emit(m)
	changed.emit()


func _instance_start(m: Dictionary) -> void:
	state = "instance"
	queued = {}
	players.clear()
	var members := {}
	for p in m.get("members", []):
		members[str(p["id"])] = str(p.get("name", "?"))
	inst = {"id": int(m["id"]), "kind": str(m["kind"]), "tier": int(m["tier"]), "depth": int(m["depth"]), "radius": float(m["radius"]),
		"me": str(m["me"]), "hpmax": float(m.get("hpmax", 1000)), "members": members, "boss": str(m.get("boss", "")),
		"hp": float(m.get("hpmax", 1000)), "alive": true, "late": bool(m.get("late", false)), "phase": "countdown", "text": "",
		"foes": {}, "haz": {}, "orbs": {}, "pl": {}}
	for f in m.get("foes", []):
		inst["foes"][int(f["id"])] = f
	for h in m.get("hazards", []):
		h["t0"] = Time.get_ticks_msec() / 1000.0
		h["total"] = float(h.get("t", 1.0))
		inst["haz"][int(h["id"])] = h
	if drive_game:
		if solo_hp < 0:
			solo_hp = Game.hp
		Game.go_to("online:arena", "P")


func restore_solo() -> void:
	if solo_hp >= 0 and drive_game:
		Game.hp = clampi(solo_hp, 1, Game.max_hp())
		solo_hp = -1
		Game.stats_changed.emit()


func leave_instance(then_hub: bool) -> void:
	## out of the fight (a result is kept by the server either way); on to the hub or home
	send({"t": "i_leave"})
	await wait_state(["char"], 4.0)
	restore_solo()
	if drive_game:
		Game.go_to("online:hub" if then_hub else "village", "P")


func _take_grant(m: Dictionary) -> void:
	var gid := str(m.get("id", ""))
	var key := "og:" + gid
	if Game.flags.has(key) or _seen_grants.has(key):
		send({"t": "grant_ack", "id": int(m.get("id", 0))})        # (already in the pouch: just tell the server)
		return
	var items: Dictionary = m.get("items", {})
	var lines := []
	for k in items:
		var n := int(items[k])
		var room := n
		if Game.item_def(str(k)).get("type") == "material":
			room = mini(n, maxi(Game.pouch_cap() - Game.count(str(k)), 0))
		if room > 0:
			Game.add_item(str(k), room, false)
			lines.append("%d x %s" % [room, Game.item_name(str(k))])
		if room < n:
			lines.append(I18n.t("(%d x %s didn't fit your pouch -- they were lost)") % [n - room, Game.item_name(str(k))])
			Game.flags["og_over:" + gid + ":" + str(k)] = n - room
	Game.flags[key] = true
	_seen_grants[key] = true
	Game.save_game()
	send({"t": "grant_ack", "id": int(m.get("id", 0))})
	Game.message.emit("The Gate hands over: %s." % ", ".join(lines))
