extends RefCounted
## The Gate's windows (round 125), all made with the HUD's own dialog: stepping through, making the online hero, the
## dungeon gates, raids, party, world events, records, market, post and the vault.

const BOARDS := [
	["run_time_t1", "Fastest run, tier 1", true], ["run_time_t2", "Fastest run, tier 2", true], ["run_time_t3", "Fastest run, tier 3", true],
	["run_time_t4", "Fastest run, tier 4", true], ["run_time_t5", "Fastest run, tier 5", true], ["run_time_t6", "Fastest run, tier 6", true],
	["run_time_t7", "Fastest run, tier 7", true], ["run_time_t8", "Fastest run, tier 8", true], ["run_time_t9", "Fastest run, tier 9", true],
	["run_time_t10", "Fastest run, tier 10", true], ["raid_time", "Fastest raid", true],
	["boss_damage", "Most boss damage", false], ["kills", "Most foes slain", false], ["event_score", "World boss score", false]]

static var board_idx := 0


static func _on() -> Node:
	return Game.online


static func _fmt_secs(s: float) -> String:
	return "%d:%02d" % [int(s) / 60, int(s) % 60]


static func _form(hud, title: String, body: String, fields: Array, submit_text: String, on_submit: Callable, back: Callable) -> void:
	## fields: [[label, placeholder, secret, text], ...]
	var edits := []
	hud.open_dialog(title, body, [
		[submit_text, func():
			var vals := []
			for e in edits:
				vals.append((e as LineEdit).text)
			on_submit.call(vals)],
		["Back", back]])
	var at := 0
	for f in fields:
		var le := LineEdit.new()
		le.placeholder_text = str(f[1])
		le.secret = bool(f[2])
		le.text = str(f[3])
		le.custom_minimum_size = Vector2(320, 40)
		le.tooltip_text = str(f[0])
		hud._dialog_buttons.add_child(le)
		hud._dialog_buttons.move_child(le, at)
		at += 1
		edits.append(le)
	if edits.size() > 0:
		(edits[0] as LineEdit).grab_focus.call_deferred()


# ---- stepping through ----------------------------------------------------------------------------------------------

static func gate(hud) -> void:
	var on = _on()
	if on == null:
		hud.open_dialog("The Gate", "The Gate isn't in this build.", [["Close", hud.close_dialog]])
		return
	var why: String = Game.online_blocked()
	if why != "":
		hud.open_dialog("The Gate", why, [["Close", hud.close_dialog]])
		return
	var cs = Game.cloudsave
	var signed: bool = cs != null and cs.signed_in()
	var body := I18n.t("A shimmering Gate to the shared world: dungeon runs with friends, raids, world bosses, a market and a post. It is a separate hero with a separate pouch -- your solo game isn't touched, and only crafting materials can come back out.\n\nServer: %s\nSigned in: %s") % [on.url, cs.email() if signed else "no"]
	var opts := []
	opts.append(["Step through", func(): _enter(hud)])
	if not signed:
		opts.append(["Sign in or make an account (Cloud save)...", func(): hud.open_cloud(false)])
	opts.append(["Server address...", func(): _address(hud)])
	opts.append(["Not now", hud.close_dialog])
	hud.open_dialog("The Gate", body, opts)


static func _address(hud) -> void:
	var on = _on()
	_form(hud, "Server address", "Where the Gate leads (ws://host:port, or wss:// for a secure server).", [["address", "ws://host:8765", false, on.url]], "Save",
		func(v):
			var u := str(v[0]).strip_edges()
			if u != "":
				on.url = u
				on.save_config()
			gate(hud), func(): gate(hud))


static func _enter(hud) -> void:
	var on = _on()
	hud.open_dialog("The Gate", "Opening the Gate...", [])
	if not on.is_connected_ok():
		on.connect_now()
		var st: String = await on.wait_state(["char", "nochar"], 14.0)
		if st != "char" and st != "nochar":
			_fail(hud)
			return
	if on.state == "nochar":
		_create(hud)
		return
	hud.close_dialog()
	Game.go_to("online:hub", "P")


static func _fail(hud) -> void:
	var on = _on()
	var why: String = on.last_error if on.last_error != "" else "The Gate didn't answer."
	var opts := [["Try again", func(): _enter(hud)]]
	if on.last_code == "auth":
		opts.append(["Sign in (Cloud save)...", func(): hud.open_cloud(false)])
	opts.append(["Server address...", func(): _address(hud)])
	opts.append(["Close", hud.close_dialog])
	hud.open_dialog("The Gate", why, opts)


static func _create(hud, note: String = "") -> void:
	var on = _on()
	var cap := 3
	var rr := mini(Game.realm, cap)
	var st := Game.sublevel if Game.realm <= cap else 1
	var rname := str(Game.realm_info(rr)["name"])
	var body := I18n.t("You have no hero in the shared world yet. Name one. It begins at %s, step %d (the Gate takes heroes up to that rank at most -- the shared world is climbed from there, with its own gear).") % [rname, st]
	if note != "":
		body += "\n\n" + note
	_form(hud, "Your online hero", body, [["name", "3-16 letters", false, ""]], "Create the hero",
		func(v):
			hud.open_dialog("The Gate", "One moment...", [])
			on.send({"t": "create_char", "name": str(v[0]).strip_edges(), "realm": Game.realm, "step": Game.sublevel})
			var r: Dictionary = await on.wait_any(["char", "char_error"], 6.0)
			if r.get("t", "") == "char":
				hud.close_dialog()
				Game.go_to("online:hub", "P")
			else:
				_create(hud, str(r.get("msg", "No answer."))), hud.close_dialog)


# ---- the stands ----------------------------------------------------------------------------------------------------

static func open_kind(hud, kind: String) -> void:
	match kind:
		"gates":
			dungeon(hud, "run")
		"raids":
			dungeon(hud, "raid")
		"events":
			events(hud)
		"records":
			records(hud)
		"market":
			market(hud)
		"post":
			post(hud)
		"vault":
			vault(hud)


static func chat(hud) -> void:
	var on = _on()
	if on == null or not on.is_connected_ok():
		return
	var ch := "inst" if on.state == "instance" else "hub"
	_form(hud, "Say", "To everyone here. (Start with /p for your party, /w name for a whisper.)", [["text", "say something...", false, ""]], "Say",
		func(v):
			var t := str(v[0]).strip_edges()
			hud.close_dialog()
			if t == "":
				return
			if t.begins_with("/p "):
				on.send({"t": "chat", "ch": "party", "text": t.substr(3)})
			elif t.begins_with("/w "):
				var rest := t.substr(3)
				on.send({"t": "chat", "ch": "whisper", "to": rest.get_slice(" ", 0), "text": rest.substr(rest.find(" ") + 1)})
			else:
				on.send({"t": "chat", "ch": ch, "text": t}), hud.close_dialog)


static func _me() -> String:
	return str(_on().char.get("id", ""))


static func _tier_ok(t: int) -> bool:
	var on = _on()
	var need := int(on.tiers.get(str(t), {}).get("need_realm", 0))
	return int(on.char.get("realm", 0)) >= need


static func dungeon(hud, kind: String, note: String = "") -> void:
	var on = _on()
	if on.state != "hub":
		hud.open_dialog("The Gate", "Wait for the hub to settle...", [["Close", hud.close_dialog]])
		return
	var t := clampi(on.sel_tier, 1, 10)
	var ti: Dictionary = on.tiers.get(str(t), {})
	var members := []
	for p in on.party.get("members", []):
		members.append(str(p.get("name", "?")) + (I18n.t(" (leader)") if str(p.get("id", "")) == str(on.party.get("leader", "")) else ""))
	var title := "Dungeon Gates" if kind == "run" else "Raid Hall"
	var body := ""
	if kind == "run":
		body = "Up to four heroes clear four rooms and a master. Dodge the red circles; stand near a fallen friend to raise them. Materials, gold, marks and a title are the prize -- never gear or pills."
	else:
		body = "Three to eight heroes against one great master with phases. Bring friends; a raid is won by spacing and by rescuing each other."
	body += I18n.t("\n\nTier %d: floor depth %d%s") % [t, int(ti.get("depth", t * 5)), "" if _tier_ok(t) else I18n.t("  -- needs realm %d (you are realm %d here)") % [int(ti.get("need_realm", 0)), int(on.char.get("realm", 0))]]
	body += I18n.t("\nParty: %s") % (", ".join(members) if members.size() > 0 else I18n.t("just you"))
	if not on.queued.is_empty():
		body += I18n.t("\nLooking for a group: %s tier %d...") % [on.queued.get("kind", ""), int(on.queued.get("tier", 1))]
	if note != "":
		body += "\n\n" + note
	var opts := []
	opts.append(["Tier: %d  (tap to change)" % t, func():
		on.sel_tier = t % 10 + 1
		on.save_config()
		dungeon(hud, kind)])
	opts.append(["Party...", func(): party(hud, kind)])
	var leader: bool = on.party.is_empty() or str(on.party.get("leader", "")) == _me()
	if leader:
		opts.append(["Start now%s" % (I18n.t(" with my party") if not on.party.is_empty() else I18n.t(" (just me)")), func(): _start(hud, kind, t)])
	if on.party.is_empty():
		if on.queued.is_empty():
			opts.append(["Find a group (queue)", func():
				on.send({"t": "queue", "kind": kind, "tier": t})
				await on.wait_any(["queued", "queue_error"], 3.0)
				dungeon(hud, kind, str(on.last_error) if on.queued.is_empty() else "")])
		else:
			opts.append(["Leave the queue", func():
				on.send({"t": "unqueue"})
				await on.wait_for("unqueued", 3.0)
				dungeon(hud, kind)])
	opts.append(["Close", hud.close_dialog])
	hud.open_dialog(title, body, opts)


static func _start(hud, kind: String, tier: int) -> void:
	var on = _on()
	hud.open_dialog("The Gate", "Opening the way...", [])
	on.send({"t": "p_start", "kind": kind, "tier": tier})
	var r: Dictionary = await on.wait_any(["inst_start", "party_error"], 6.0)
	if r.get("t", "") == "inst_start":
		hud.close_dialog()
	else:
		dungeon(hud, kind, str(r.get("msg", "Nothing happened.")))


static func party(hud, back_kind: String = "run", note: String = "") -> void:
	var on = _on()
	var lines := []
	for p in on.party.get("members", []):
		lines.append("  %s%s" % [p.get("name", "?"), I18n.t("  (leader)") if str(p.get("id", "")) == str(on.party.get("leader", "")) else ""])
	var body := "Your party:\n%s" % ("\n".join(lines) if lines.size() > 0 else "  (nobody -- you're alone)")
	if note != "":
		body += "\n\n" + note
	var opts := []
	for inv in on.invites:
		var iv: Dictionary = inv
		opts.append(["Accept the invitation from %s" % iv["from"], func():
			on.invites.erase(iv)
			on.send({"t": "p_accept", "pid": iv["pid"]})
			var r: Dictionary = await on.wait_any(["party", "party_error"], 4.0)
			party(hud, back_kind, str(r.get("msg", "")))])
	if on.party.is_empty() or str(on.party.get("leader", "")) == _me():
		opts.append(["Invite a player in the hub...", func():
			_form(hud, "Invite", "The name of a hero who is in the hub right now.", [["name", "name", false, ""]], "Invite",
				func(v):
					on.send({"t": "p_invite", "name": str(v[0]).strip_edges()})
					var r: Dictionary = await on.wait_any(["party", "party_error"], 4.0)
					party(hud, back_kind, str(r.get("msg", "Invitation sent."))), func(): party(hud, back_kind))])
	if not on.party.is_empty():
		opts.append(["Leave the party", func():
			on.send({"t": "p_leave"})
			await on.wait_for("party", 3.0)
			party(hud, back_kind)])
	opts.append(["Back", func(): dungeon(hud, back_kind)])
	hud.open_dialog("Party", body, opts)


static func events(hud, note: String = "") -> void:
	var on = _on()
	var r: Dictionary = await on.ask({"t": "events"}, "events", 3.0)
	var now: float = on.server_now()
	var lines := []
	var opts := []
	for e in on.events:
		var ev: Dictionary = e
		var active: bool = float(ev["start"]) <= now and now < float(ev["end"])
		if active:
			lines.append(I18n.t("%s -- NOW, for %s") % [ev["name"], _fmt_secs(float(ev["end"]) - now)])
		else:
			var d := float(ev["start"]) - now
			lines.append("%s -- in %s" % [ev["name"], ("%dh %02dm" % [int(d) / 3600, (int(d) % 3600) / 60]) if d >= 3600.0 else _fmt_secs(maxf(d, 0.0))])
		if active and str(ev["kind"]) == "world":
			opts.append(["Join: %s" % ev["name"], func(): _join_event(hud, str(ev["id"]))])
	var body := "World events everyone shares.\n\n%s" % "\n".join(lines)
	if note != "":
		body += "\n\n" + note
	opts.append(["Refresh", func(): events(hud)])
	opts.append(["Close", hud.close_dialog])
	hud.open_dialog("Event Obelisk", body, opts)


static func _join_event(hud, id: String) -> void:
	var on = _on()
	hud.open_dialog("The Gate", "Going in...", [])
	on.send({"t": "event_join", "id": id})
	var r: Dictionary = await on.wait_any(["inst_start", "party_error"], 6.0)
	if r.get("t", "") == "inst_start":
		hud.close_dialog()
	else:
		events(hud, str(r.get("msg", "")))


static func records(hud) -> void:
	var on = _on()
	var b: Array = BOARDS[board_idx]
	var r: Dictionary = await on.ask({"t": "lb", "board": b[0]}, "lb", 4.0)
	var lines := []
	var i := 1
	for row in r.get("rows", []):
		var v := float(row.get("value", 0))
		lines.append("%2d. %s -- %s" % [i, row.get("name", "?"), _fmt_secs(v) if bool(b[2]) else str(int(v))])
		i += 1
	if lines.is_empty():
		lines.append(I18n.t("(nobody yet)"))
	hud.open_dialog(I18n.t("Hall of Records"), "%s\n\n%s" % [b[1], "\n".join(lines)], [
		["Season ladder", func(): ladder(hud)],
		["Board: %s  (tap to change)" % b[1], func():
			board_idx = (board_idx + 1) % BOARDS.size()
			records(hud)],
		["Close", hud.close_dialog]])


static func _days_left(ends: float, now: float) -> String:
	var secs := maxf(0.0, ends - now)
	var d := int(secs / 86400.0)
	var h := int(fmod(secs, 86400.0) / 3600.0)
	return I18n.t("%d days %d h") % [d, h] if d > 0 else "%d h" % h


static func ladder(hud, past_season: int = 0) -> void:
	## the season ladder: wins score points (a run 10 x tier, a raid 30 x tier, the Titan 20); when a season closes the best get titles
	var on = _on()
	var req := {"t": "season"}
	if past_season > 0:
		req["season"] = past_season
	var r: Dictionary = await on.ask(req, "season", 4.0)
	var lines := []
	var i := 1
	for row in r.get("rows", []):
		lines.append("%2d. %s -- %d" % [i, row.get("name", "?"), int(row.get("points", 0))])
		i += 1
	if lines.is_empty():
		lines.append(I18n.t("(nobody yet -- win a run to start the ladder)"))
	var sn := int(r.get("season", 0))
	var head := "Season %d (final standings)" % sn
	var opts := []
	if not bool(r.get("past", false)):
		var me: Dictionary = r.get("me", {})
		head = I18n.t("Season %d -- ends in %s") % [sn, _days_left(float(r.get("ends", 0.0)), float(r.get("server_time", Time.get_unix_time_from_system())))]
		head += I18n.t("\nYou: %d points%s") % [int(me.get("points", 0)), (I18n.t(" (rank %d)") % int(me.get("rank", 0))) if int(me.get("rank", 0)) > 0 else ""]
		if sn > 1:
			opts.append(["Last season's winners", func(): ladder(hud, sn - 1)])
	else:
		opts.append(["This season", func(): ladder(hud)])
	opts.append(["Records", func(): records(hud)])
	opts.append(["Close", hud.close_dialog])
	hud.open_dialog(I18n.t("Season Ladder"), I18n.t("%s\n\n%s\n\nTitles: top 10 Ladder Elite, top 3 Podium, first Champion, 50+ points Veteran.") % [head, "\n".join(lines)], opts)


# ---- market --------------------------------------------------------------------------------------------------------

static func _item(id: String) -> String:
	return Game.item_name(id) if Game.item_def(id).size() > 0 else id


static func market(hud, note: String = "") -> void:
	var on = _on()
	var r: Dictionary = await on.ask({"t": "m_search"}, "market", 4.0)
	var rows: Array = r.get("rows", [])
	var body := I18n.t("Players sell crafting materials here (a %d%% fee on every sale). Your gold: %d.") % [5, int(on.char.get("gold", 0))]
	if note != "":
		body += "\n\n" + note
	var opts := []
	var shown := 0
	for row in rows:
		if shown >= 8:
			break
		var rw: Dictionary = row
		var mine: bool = str(rw.get("seller_name", "")) == str(on.char.get("name", ""))
		if mine:
			opts.append(["Take back my %d x %s (listing %d)" % [int(rw["qty"]), _item(str(rw["item"])), int(rw["id"])], func():
				on.send({"t": "m_cancel", "id": int(rw["id"])})
				await on.wait_for("market_ok", 3.0)
				market(hud)])
		else:
			opts.append(["Buy 1 x %s -- %d gold each (%d for sale, %s)" % [_item(str(rw["item"])), int(rw["price"]), int(rw["qty"]), rw.get("seller_name", "?")], func():
				on.send({"t": "m_buy", "id": int(rw["id"]), "qty": 1})
				var rr: Dictionary = await on.wait_any(["market_ok", "market_error"], 4.0)
				market(hud, str(rr.get("msg", "Bought."))) ])
		shown += 1
	opts.append(["Sell a material...", func(): _sell_pick(hud)])
	opts.append(["Refresh", func(): market(hud)])
	opts.append(["Close", hud.close_dialog])
	hud.open_dialog("Market", body, opts)


static func _materials() -> Array:
	var on = _on()
	var out := []
	for k in on.char.get("inv", {}):
		if int(on.char["inv"][k]) > 0 and Game.item_def(str(k)).get("type") == "material":
			out.append(str(k))
	out.sort()
	return out


static func _sell_pick(hud) -> void:
	var on = _on()
	var opts := []
	for k in _materials():
		var kk: String = k
		opts.append(["%s  (you have %d)" % [_item(kk), int(on.char["inv"][kk])], func(): _sell_form(hud, kk)])
	opts.append(["Back", func(): market(hud)])
	hud.open_dialog("Sell what?", "Only crafting materials can be sold." if opts.size() > 1 else "You have no materials to sell. Win some in the Gate's runs.", opts)


static func _sell_form(hud, item: String) -> void:
	var on = _on()
	_form(hud, "Sell %s" % _item(item), "How many, and the price of each in gold. (You have %d.)" % int(on.char["inv"].get(item, 0)), [["quantity", "quantity", false, "1"], ["price", "price each", false, "10"]], "List it",
		func(v):
			on.send({"t": "m_list", "item": item, "qty": int(str(v[0])), "price": int(str(v[1]))})
			var r: Dictionary = await on.wait_any(["market_ok", "market_error"], 4.0)
			market(hud, str(r.get("msg", "Listed."))), func(): _sell_pick(hud))


# ---- post ----------------------------------------------------------------------------------------------------------

static func post(hud, note: String = "") -> void:
	var on = _on()
	var r: Dictionary = await on.ask({"t": "mail_list"}, "mail", 4.0)
	var rows: Array = r.get("rows", [])
	var opts := []
	var n := 0
	for row in rows:
		if n >= 6:
			break
		var m: Dictionary = row
		var att := ""
		if int(m.get("gold", 0)) > 0 and not bool(m.get("claimed", 0)):
			att = "  [%d gold]" % int(m["gold"])
		if (m.get("items", {}) as Dictionary).size() > 0 and not bool(m.get("claimed", 0)):
			att += I18n.t("  [items]")
		opts.append(["%s -- %s%s" % [m.get("from_name", "?"), m.get("subject", ""), att], func(): _read_mail(hud, m)])
		n += 1
	opts.append(["Write a letter...", func(): _write_mail(hud)])
	opts.append(["Close", hud.close_dialog])
	hud.open_dialog(I18n.t("Post"), (note + "\n\n" if note != "" else "") + (I18n.t("Your post (%d).") % rows.size() if rows.size() > 0 else I18n.t("No post.")), opts)


static func _read_mail(hud, m: Dictionary) -> void:
	var on = _on()
	var body := I18n.t("From %s\n%s\n\n%s") % [m.get("from_name", "?"), m.get("subject", ""), m.get("body", "")]
	var opts := []
	if (int(m.get("gold", 0)) > 0 or (m.get("items", {}) as Dictionary).size() > 0) and not bool(m.get("claimed", 0)):
		opts.append(["Take what's inside", func():
			on.send({"t": "mail_claim", "id": int(m["id"])})
			await on.wait_for("mail", 4.0)
			post(hud, "Taken.")])
	opts.append(["Delete", func():
		on.send({"t": "mail_delete", "id": int(m["id"])})
		await on.wait_for("mail", 4.0)
		post(hud)])
	opts.append(["Back", func(): post(hud)])
	hud.open_dialog("Letter", body, opts)


static func _write_mail(hud) -> void:
	var on = _on()
	_form(hud, "Write a letter", "To another online hero. You can send gold along (the Gate keeps nothing back).", [["to", "hero's name", false, ""], ["subject", "subject", false, ""], ["message", "message", false, ""], ["gold", "gold to send (0)", false, "0"]], "Send",
		func(v):
			on.send({"t": "mail_send", "to": str(v[0]).strip_edges(), "subject": str(v[1]), "body": str(v[2]), "gold": int(str(v[3]))})
			var r: Dictionary = await on.wait_any(["mail_ok", "mail_error"], 4.0)
			post(hud, str(r.get("msg", "Sent."))), func(): post(hud))


# ---- vault ---------------------------------------------------------------------------------------------------------

static func vault(hud, note: String = "") -> void:
	var on = _on()
	await on.ask({"t": "inv"}, "char", 3.0)
	var c: Dictionary = on.char
	var lines := ["%s -- level %d, %s" % [c.get("name", "?"), int(c.get("level", 1)), str(Game.realm_info(int(c.get("realm", 0)))["name"])],
		I18n.t("Gold %d    Marks %d") % [int(c.get("gold", 0)), int(c.get("marks", 0))]]
	if (c.get("titles", []) as Array).size() > 0:
		lines.append(I18n.t("Titles: ") + ", ".join(PackedStringArray(c["titles"])))
	var mats := _materials()
	lines.append("")
	lines.append(I18n.t("Materials kept here: %s") % (", ".join(PackedStringArray(mats.map(func(k): return "%d x %s" % [int(c["inv"][k]), _item(k)]))) if mats.size() > 0 else "none"))
	if note != "":
		lines.append("")
		lines.append(note)
	var opts := []
	for k in mats:
		var kk: String = k
		var have := int(c["inv"][kk])
		var room := maxi(Game.pouch_cap() - Game.count(kk), 0)
		var take := mini(have, room)
		if take > 0:
			opts.append(["Carry %d x %s home to the solo game" % [take, _item(kk)], func():
				on.send({"t": "withdraw", "items": {kk: take}})
				await on.wait_for("grant", 4.0)
				vault(hud, "Handed over -- check your pouch.")])
	opts.append(["Delete my online account...", func(): _delete(hud)])
	opts.append(["Close", hud.close_dialog])
	hud.open_dialog("Vault", "\n".join(PackedStringArray(lines)), opts)


static func _delete(hud) -> void:
	var on = _on()
	hud.open_dialog("Delete the online account?", "This erases your online hero, gold, marks, materials and listings from the server. Your solo game is not touched. It cannot be undone.", [
		["Yes, erase it", func():
			on.send({"t": "delete_account", "confirm": "DELETE"})
			await on.wait_for("account_deleted", 4.0)
			hud.close_dialog()
			Game.message.emit("Your online account is erased.")
			Game.go_to("village", "P")],
		["No", func(): vault(hud)]])
