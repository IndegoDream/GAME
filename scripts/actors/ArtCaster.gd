extends RefCounted
## How the ki arts of round 122 are cast. One instance per Player (Player._ac); every art in
## data/arts_ext.json names a "template" below, and its numbers come from its "params".
## Nothing here is a stub: each template does what its art's description says.
## Attack arts -> F, movement arts -> V, support arts -> 8 / 9 (or F in shared mode).
## The guard arts are passive; their numbers are read by Game.guard_take / block / parry.

const FX := preload("res://scripts/fx/FX.gd")

var p                                   # the Player


func _init(player) -> void:
	p = player


# ---- small helpers -----------------------------------------------------------------------

func _A():
	return Game.sys("arts")


func _fwd() -> Vector3:
	return Vector3(sin(p._model.rotation.y), 0, cos(p._model.rotation.y))


func _dir(d: Vector3) -> Vector3:
	return d.normalized() if d.length() > 0.1 else _fwd()


func _foes() -> Array:
	var out := []
	for e in p.get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(e) and not e._dead:
			out.append(e)
	return out


func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


func _prm(aid: String, k: String, d: float) -> float:
	return Game.art_param(aid, k, d)


func _dmg(aid: String, mult: float, pw: float) -> int:
	return maxi(1, int(round(Game.damage() * mult * pw * Game.branch_damage_mult(aid))))


func _src(aid: String) -> String:
	return str(Game.technique_defs.get(aid, {}).get("name", aid)).to_lower()


func _nearest_front(reach: float, cone: float = 0.3):
	## the nearest foe, in front first
	var best = null
	var bs := 1e9
	var fwd := _fwd()
	for e in _foes():
		var to: Vector3 = _flat(e.global_position - p.global_position)
		var d := to.length()
		if d > reach:
			continue
		var s := d * (1.0 if d < 0.6 or fwd.dot(to.normalized()) > cone else 3.0)
		if s < bs:
			bs = s
			best = e
	return best


func _in_cone(e, reach: float, arc_deg: float) -> bool:
	var to: Vector3 = _flat(e.global_position - p.global_position)
	var d := to.length()
	if d > reach:
		return false
	if arc_deg >= 359.0 or d < 0.6:
		return true
	return _fwd().dot(to.normalized()) >= cos(deg_to_rad(arc_deg * 0.5))


func _ring(at: Vector3, col: Color, r: float) -> void:
	if FX.on():
		FX.ring(at, col, r, 0.4)


func _word(text: String, col: Color) -> void:
	if FX.on():
		FX.word(p.global_position + Vector3(0, 2.4, 0), text, col, 40)


# ---- the one entry point -----------------------------------------------------------------

func cast(aid: String, dir: Vector3 = Vector3.ZERO) -> int:
	## -1: couldn't (nothing spent). Otherwise how many things it reached.
	var tpl := Game.art_template(aid)
	match tpl:
		"lance_line":
			return _lance(aid)
		"arc_sweep":
			return _sweep(aid)
		"chain_arc":
			return _chain(aid)
		"ground_slam":
			return _slam(aid)
		"rend":
			return _rend(aid)
		"shatter":
			return _shatter(aid)
		"blink":
			return _blink(aid, dir)
		"slip":
			return _slip(aid, dir)
		"leap_strike":
			return _leap(aid, dir)
		"glide":
			return _glide(aid)
		"pull":
			return _pull(aid)
		"afterimage":
			return _afterimage(aid)
		"retreat":
			return _retreat(aid)
		"heal_target":
			return _heal_target(aid)
		"heal_area":
			return _heal_area(aid)
		"cleanse":
			return _cleanse(aid)
		"revive":
			return _revive(aid)
		"boon":
			return _boon(aid)
		"refill":
			return _refill(aid)
		"flurry":
			return _flurry(aid)
		"whirlwind":
			return _whirl(aid)
		"throw":
			return _throw(aid)
		"volley":
			return _volley(aid)
		"counter_stance":
			return _counter(aid)
		"multi_bolt":
			return _multi(aid)
		"pin":
			return _pin(aid)
		"hex_mark":
			return _hex_mark(aid)
		"hex_weaken":
			return _hex_weaken(aid)
		"hex_root":
			return _hex_root(aid)
	return -1


# ---- ATTACK ------------------------------------------------------------------------------

func _begin(aid: String, cd: float) -> float:
	## off cooldown and open? spend it. Returns the art's strength (0 when it can't be cast).
	if not p._art_ok(aid):
		return 0.0
	p._art_cool(aid, cd)
	var pw: float = Game.art_fire(aid)
	var A = _A()
	if A != null:
		A.note_resonance(aid)
	return maxf(pw, 0.01)


func _lance(aid: String) -> int:
	var pw := _begin(aid, 5.0)
	if pw <= 0.0:
		return -1
	var rng := _prm(aid, "range", 10.0)
	var wid := _prm(aid, "width", 1.6)
	var mult := _prm(aid, "mult", 1.8)
	var fwd := _fwd()
	var hit := 0
	for e in _foes():
		var to: Vector3 = _flat(e.global_position - p.global_position)
		var along := to.dot(fwd)
		if along < -0.4 or along > rng:
			continue
		var lateral := (to - fwd * along).length()
		if lateral > wid * 0.5 + 0.7:
			continue
		p._strike_hit(aid, e, _dmg(aid, mult, pw), hit, _src(aid))
		if _prm(aid, "slow", 0.0) > 0.0 and e.has_method("slow"):
			e.slow(_prm(aid, "slow", 0.0))
		if _prm(aid, "knock", 0.0) > 0.0 and not bool(e.stats.get("boss", false)):
			e._knock = fwd * _prm(aid, "knock", 0.0) * 2.0
		hit += 1
	p._beam_fx(p.global_position + fwd * rng)
	p._shake(0.15)
	p._play("cast", true)
	p._strike_practice(aid, hit)
	Game.log_event("art_used", {"hit": hit, "art": aid})
	return hit


func _sweep(aid: String) -> int:
	var pw := _begin(aid, 6.0)
	if pw <= 0.0:
		return -1
	var r := _prm(aid, "radius", 4.5)
	var arc := _prm(aid, "arc", 200.0)
	var mult := _prm(aid, "mult", 1.5)
	var hit := 0
	for e in _foes():
		if not _in_cone(e, r, arc):
			continue
		var dmg := _dmg(aid, mult, pw)
		p._strike_hit(aid, e, dmg, hit, _src(aid))
		if _prm(aid, "stagger", 0.0) > 0.0:
			e.stagger(_prm(aid, "stagger", 0.0))
		if _prm(aid, "burn", 0.0) > 0.0:
			e.burn(int(round(dmg * _prm(aid, "burn", 0.0))), _prm(aid, "burn_secs", 4.0))
		hit += 1
	p._burst_fx(r)
	_blade_arc(aid, r)
	p._shake(0.22)
	p._play("cast", true)
	p._strike_practice(aid, hit)
	Game.log_event("art_used", {"hit": hit, "art": aid})
	return hit


func _chain(aid: String) -> int:
	var pw := _begin(aid, 8.0)
	if pw <= 0.0:
		return -1
	var rng := _prm(aid, "range", 7.0)
	var jumps := int(_prm(aid, "jumps", 4))
	var fall := _prm(aid, "falloff", 0.85)
	var cur = _nearest_front(rng + 2.0)
	var from: Vector3 = p.global_position
	var done := []
	var hit := 0
	var m := _prm(aid, "mult", 1.7)
	while cur != null and hit <= jumps:
		done.append(cur)
		p._beam_fx(cur.global_position)
		p._strike_hit(aid, cur, _dmg(aid, m, pw), hit, _src(aid))
		m *= fall
		hit += 1
		from = cur.global_position
		var nxt = null
		var bd := rng
		for e in _foes():
			if e in done:
				continue
			var d: float = (e.global_position - from).length()
			if d < bd:
				bd = d
				nxt = e
		cur = nxt
	p._shake(0.2)
	p._play("cast", true)
	p._strike_practice(aid, hit)
	Game.log_event("art_used", {"hit": hit, "art": aid})
	return hit


func _slam(aid: String) -> int:
	var pw := _begin(aid, 7.0)
	if pw <= 0.0:
		return -1
	var centre: Vector3 = p.global_position + _fwd() * _prm(aid, "reach", 4.0)
	var r := _prm(aid, "radius", 3.4)
	var hit := 0
	for e in _foes():
		if _flat(e.global_position - centre).length() <= r:
			p._strike_hit(aid, e, _dmg(aid, _prm(aid, "mult", 2.0), pw), hit, _src(aid))
			e.stagger(_prm(aid, "stagger", 1.2))
			hit += 1
	_ring(centre, Color(0.85, 0.7, 0.4), r)
	if FX.on():
		FX.puff(centre + Vector3(0, 0.3, 0), Color(0.6, 0.5, 0.35), 1.6)
	p._shake(0.35)
	p._play("cast", true)
	p._strike_practice(aid, hit)
	Game.log_event("art_used", {"hit": hit, "art": aid})
	return hit


func _rend(aid: String) -> int:
	var tgt = _nearest_front(_prm(aid, "reach", 3.6), 0.2)
	if tgt == null:
		if p._art_ok(aid):
			Game.message.emit("%s needs a foe within reach." % str(Game.technique_defs.get(aid, {}).get("name", "It")))
			p._cool[aid] = 0.5
		return -1
	var pw := _begin(aid, 3.0)
	if pw <= 0.0:
		return -1
	var dmg := _dmg(aid, _prm(aid, "mult", 1.7), pw)
	p._strike_hit(aid, tgt, dmg, 0, _src(aid))
	tgt.burn(int(round(dmg * _prm(aid, "bleed", 0.9))), _prm(aid, "bleed_secs", 5.0))
	_word("RENT", Color(0.9, 0.3, 0.3))
	p._shake(0.12)
	p._play("cast", true)
	p._strike_practice(aid, 1)
	Game.log_event("art_used", {"hit": 1, "art": aid})
	return 1


func _shatter(aid: String) -> int:
	var pw := _begin(aid, 6.0)
	if pw <= 0.0:
		return -1
	var reach := _prm(aid, "reach", 3.8)
	var arc := _prm(aid, "arc", 100.0)
	var hit := 0
	for e in _foes():
		if not _in_cone(e, reach, arc):
			continue
		var m := _prm(aid, "mult", 1.6)
		if e.has_method("staggered") and e.staggered():
			m *= _prm(aid, "vs_staggered", 1.8)
		if "armoured" in e.affixes:
			m *= _prm(aid, "vs_armoured", 1.5)
			e.sundered = maxf(e.sundered, _prm(aid, "sunder", 6.0))
			e.sunder_mult = maxf(e.sunder_mult, 1.25)
			_word("SPLIT", Color(1.0, 0.8, 0.4))
		p._strike_hit(aid, e, _dmg(aid, m, pw), hit, _src(aid))
		hit += 1
	_blade_arc(aid, reach, Color(1.0, 0.85, 0.55))
	p._shake(0.25)
	p._play("cast", true)
	p._strike_practice(aid, hit)
	Game.log_event("art_used", {"hit": hit, "art": aid})
	return hit


# ---- MOVEMENT ----------------------------------------------------------------------------

func _dash(d: Vector3, dist: float, secs: float = 0.22) -> void:
	p._dash_dir = d
	p._dash_dist = dist * 0.22 / secs
	p._dash_t = secs
	p._play("sprint", true)


func _blink(aid: String, dir: Vector3) -> int:
	var pw := _begin(aid, 4.5)
	if pw <= 0.0:
		return -1
	var d := _dir(dir)
	var rng := _prm(aid, "range", 7.0) * clampf(pw, 0.9, 1.25)
	if FX.on():
		FX.puff(p.global_position + Vector3(0, 1.0, 0), Color(0.7, 0.9, 1.0), 1.2)
	var foe = null
	if _prm(aid, "behind", 0.0) > 0.0:
		var near := _close_first(_foes())
		if not near.is_empty() and _flat(near[0].global_position - p.global_position).length() <= rng:
			foe = near[0]
	if foe != null and is_instance_valid(foe):
		# step to the far side of the nearest foe, facing it
		var fp: Vector3 = foe.global_position
		var away: Vector3 = fp - p.global_position
		away.y = 0.0
		if away.length() < 0.05:
			away = d
		var goal: Vector3 = fp + away.normalized() * 1.4
		p.move_and_collide(goal - p.global_position)
		var look: Vector3 = fp - p.global_position
		look.y = 0.0
		if look.length() > 0.05 and p._model != null:
			p._model.rotation.y = atan2(look.x, look.z)
			p._want_yaw = p._model.rotation.y
	else:
		p.move_and_collide(d * rng)                # walls stop it
	if FX.on():
		FX.puff(p.global_position + Vector3(0, 1.0, 0), Color(0.7, 0.9, 1.0), 1.2)
	p._hurt_cool = maxf(p._hurt_cool, _prm(aid, "iframes", 0.25))
	p._after_step(aid, p._enemy_near(4.5))
	return 0


func _slip(aid: String, dir: Vector3) -> int:
	var pw := _begin(aid, 6.0)
	if pw <= 0.0:
		return -1
	_dash(_dir(dir), _prm(aid, "dash", 6.0))
	p._hurt_cool = maxf(p._hurt_cool, _prm(aid, "iframes", 0.7))
	var prev: float = p._ambush_mult if p._ambush_t > 0.0 else 1.0
	p._ambush_t = 3.0
	p._ambush_mult = maxf(prev, 1.0) * _prm(aid, "ambush", 1.4) * clampf(pw, 0.9, 1.3)
	p._after_step(aid, p._enemy_near(4.5))
	return 0


func _leap(aid: String, dir: Vector3) -> int:
	var pw := _begin(aid, 8.0)
	if pw <= 0.0:
		return -1
	var d := _dir(dir)
	var dist := _prm(aid, "distance", 7.0)
	_dash(d, dist, 0.45)
	p.velocity.y = p.JUMP_SPEED * 1.2
	p._hurt_cool = maxf(p._hurt_cool, 0.4)
	var tree: SceneTree = p.get_tree()
	var pl = p
	tree.create_timer(0.5).timeout.connect(func():
		if not is_instance_valid(pl) or pl.dead:
			return
		var hit := 0
		var r := _prm(aid, "radius", 3.5)
		for e in _foes():
			if _flat(e.global_position - pl.global_position).length() <= r:
				pl._strike_hit(aid, e, _dmg(aid, _prm(aid, "mult", 1.5), pw), hit, _src(aid))
				e.stagger(_prm(aid, "stagger", 0.8))
				hit += 1
		_ring(pl.global_position, Color(1.0, 0.8, 0.45), r)
		pl._shake(0.3)
		pl._strike_practice(aid, hit))
	p._after_step(aid, p._enemy_near(6.0))
	return 0


func _glide(aid: String) -> int:
	var pw := _begin(aid, 14.0)
	if pw <= 0.0:
		return -1
	var A = _A()
	var dur: float = float(A.resonance(aid)["dur"]) if A != null else 1.0
	var mv := 1.0 + (_prm(aid, "move", 1.3) - 1.0) * clampf(pw, 0.9, 1.3)
	Game.add_buff(aid, {"move_mult": mv}, _prm(aid, "seconds", 7.0) * dur)
	Game.message.emit("Reed Glide: your feet barely touch the ground.")
	p._after_step(aid, false)
	return 0


func _pull(aid: String) -> int:
	var tgt = _nearest_front(_prm(aid, "range", 9.0))
	if tgt == null:
		if p._art_ok(aid):
			Game.message.emit("Undertow Pull needs a foe within reach.")
			p._cool[aid] = 0.5
		return -1
	var pw := _begin(aid, 6.0)
	if pw <= 0.0:
		return -1
	p._beam_fx(tgt.global_position)
	if not bool(tgt.stats.get("boss", false)):
		var to: Vector3 = _flat(tgt.global_position - p.global_position)
		var at: Vector3 = p.global_position + (to.normalized() if to.length() > 0.1 else _fwd()) * 1.9
		tgt.global_position = Vector3(at.x, tgt.global_position.y, at.z)
	else:
		_word("TOO HEAVY", Color(0.8, 0.8, 0.9))
	p._strike_hit(aid, tgt, _dmg(aid, _prm(aid, "mult", 0.8), pw), 0, _src(aid))
	tgt.stagger(_prm(aid, "stagger", 1.4))
	p._play("cast", true)
	p._after_step(aid, true)
	return 1


func _afterimage(aid: String) -> int:
	var pw := _begin(aid, 10.0)
	if pw <= 0.0:
		return -1
	var back := -_fwd()
	var tgt = _nearest_front(6.0, -2.0)
	if tgt != null:
		back = _flat(p.global_position - tgt.global_position)
		back = back.normalized() if back.length() > 0.1 else -_fwd()
	if FX.on():
		FX.puff(p.global_position + Vector3(0, 1.0, 0), Color(0.8, 0.8, 1.0), 1.4)
	var r := _prm(aid, "radius", 6.0)
	var n := 0
	for e in _foes():
		if _flat(e.global_position - p.global_position).length() <= r:
			e.stagger(_prm(aid, "stagger", 1.3))
			n += 1
	_dash(back, _prm(aid, "dash", 5.0))
	p._hurt_cool = maxf(p._hurt_cool, _prm(aid, "iframes", 0.6))
	p._after_step(aid, n > 0)
	return n


func _retreat(aid: String) -> int:
	var pw := _begin(aid, 9.0)
	if pw <= 0.0:
		return -1
	var back := -_fwd()
	var tgt = _nearest_front(7.0, -2.0)
	if tgt != null:
		back = _flat(p.global_position - tgt.global_position)
		back = back.normalized() if back.length() > 0.1 else -_fwd()
	_dash(back, _prm(aid, "dash", 6.0))
	p._hurt_cool = maxf(p._hurt_cool, _prm(aid, "iframes", 0.5))
	Game.heal(maxi(1, int(round(Game.max_hp() * _prm(aid, "heal", 0.06) * clampf(pw, 0.9, 1.3)))))
	p._after_step(aid, tgt != null)
	return 0


# ---- SUPPORT: restore --------------------------------------------------------------------

func _pick_hurt(rng: float, nature: String):
	## the party member (in reach, up, hurt) who benefits most. null when nobody needs it.
	var A = _A()
	var best = null
	var bs := 0.03
	for e in A.party():
		if str(e["who"]) == "beast" or bool(e["down"]) or not A.in_reach(e, p.global_position, rng):
			continue
		var s: float = (1.0 - float(e["frac"])) * A.kind_mult(str(e["kind"]), nature)
		if s > bs:
			bs = s
			best = e
	return best


func _kind_note(e: Dictionary, nature: String) -> String:
	var A = _A()
	var m: float = A.kind_mult(str(e["kind"]), nature)
	if m < 0.5:
		return I18n.t(" (%s is %s; this does little)") % [str(e["name"]), str(A.cfg.get("kind_names", {}).get(str(e["kind"]), "unlike you"))]
	if m > 1.2:
		return I18n.t(" (just what %s needed)") % str(e["name"])
	return ""


func _support_done(aid: String, helped: bool) -> void:
	p._play("cast", true)
	Game.practice(aid, helped)
	Game.glimpse("support_use")
	Game.log_event("art_used", {"hit": 1 if helped else 0, "art": aid, "support": true})


func _heal_target(aid: String) -> int:
	var nature := _prm_s(aid, "nature", "flesh")
	var rng := _prm(aid, "range", 12.0)
	var tgt = _pick_hurt(rng, nature)
	if tgt == null:
		if p._art_ok(aid):
			Game.message.emit("No one with you is hurt.")
			p._cool[aid] = 0.6
		return -1
	var pw := _begin(aid, 12.0)
	if pw <= 0.0:
		return -1
	var got: int = _A().heal_entry(tgt, _prm(aid, "pct", 0.2) * clampf(pw, 0.85, 1.6), nature)
	var who := "you" if str(tgt["who"]) == "you" else str(tgt["name"])
	Game.message.emit("%s: %s %s (+%d)%s" % [str(Game.technique_defs[aid]["name"]), I18n.t("you heal") if who == "you" else I18n.t("you mend"), "yourself" if who == "you" else who, got, _kind_note(tgt, nature)])
	if _prm(aid, "plating", 0.0) > 0.0:
		var dur: float = float(_A().resonance(aid)["dur"])
		Game.add_buff(aid, {"damage_taken": _prm(aid, "plating", 0.93)}, _prm(aid, "plating_secs", 15.0) * dur)
	if str(tgt["who"]) != "you" and FX.on() and tgt["node"] != null:
		FX.ring(tgt["node"].global_position, Color(0.5, 1.0, 0.6), 1.6, 0.4)
	elif FX.on():
		FX.ring(p.global_position, Color(0.5, 1.0, 0.6), 1.6, 0.4)
	_support_done(aid, got > 0)
	return 1


func _prm_s(aid: String, k: String, d: String) -> String:
	var def: Dictionary = Game.technique_defs.get(aid, {})
	var pr = def.get("params", {})
	if pr is Dictionary and (pr as Dictionary).has(k):
		return str(pr[k])
	return d


func _heal_area(aid: String) -> int:
	var pw := _begin(aid, 22.0)
	if pw <= 0.0:
		return -1
	var nature := _prm_s(aid, "nature", "qi")
	var pulses := int(_prm(aid, "pulses", 6))
	var each := _prm(aid, "pct", 0.3) * clampf(pw, 0.85, 1.6) / float(maxi(pulses, 1))
	var rng := _prm(aid, "radius", 8.0)
	var tree: SceneTree = p.get_tree()
	var pl = p
	var A = _A()
	for i in pulses:
		tree.create_timer(float(i) * 1.0 + 0.05).timeout.connect(func():
			if not is_instance_valid(pl) or pl.dead:
				return
			for e in A.party():
				if str(e["who"]) == "beast" or bool(e["down"]) or not A.in_reach(e, pl.global_position, rng):
					continue
				A.heal_entry(e, each, nature)
			_ring(pl.global_position, Color(0.8, 1.0, 0.7), 2.6))
	Game.message.emit("Lotus Bloom: a soft light opens under everyone near you.")
	_support_done(aid, true)
	return 1


func _cleanse(aid: String) -> int:
	var pw := _begin(aid, 18.0)
	if pw <= 0.0:
		return -1
	var healed := 0
	var A = _A()
	var n := Game.injury.size()
	Game.injury = {}
	Game.heat = maxf(Game.heat - _prm(aid, "vent", 30.0), 0.0)
	for e in A.party():
		if str(e["who"]) == "beast" or bool(e["down"]) or not A.in_reach(e, p.global_position, _prm(aid, "radius", 8.0)):
			continue
		healed += A.heal_entry(e, _prm(aid, "pct", 0.08) * clampf(pw, 0.85, 1.6), _prm_s(aid, "nature", "qi"))
	Game.message.emit(I18n.t("Cleansing Light: %sthe heat vents (+%d life, all told).") % [(I18n.t("torn meridians mend, ")) if n > 0 else "", healed])
	_ring(p.global_position, Color(0.9, 1.0, 0.9), 3.0)
	_support_done(aid, true)
	return 1


func _revive(aid: String) -> int:
	var A = _A()
	var rng := _prm(aid, "range", 12.0)
	var down = null
	for e in A.party():
		if str(e["who"]) == "companion" and bool(e["down"]) and A.in_reach(e, p.global_position, rng + 6.0):
			down = e
	if down == null:
		# nobody has fallen: it's a lesser mending for whoever is worst hurt
		var tgt = _pick_hurt(rng, "qi")
		if tgt == null:
			if p._art_ok(aid):
				Game.message.emit("No one with you has fallen or is hurt.")
				p._cool[aid] = 0.6
			return -1
		var pw0 := _begin(aid, 60.0)
		if pw0 <= 0.0:
			return -1
		var got: int = A.heal_entry(tgt, _prm(aid, "fallback_pct", 0.35) * clampf(pw0, 0.85, 1.6), "qi")
		Game.message.emit(I18n.t("Call Back the Breath: no one has fallen, so it mends %s (+%d).") % [str(tgt["name"]), got])
		_support_done(aid, got > 0)
		return 1
	var pw := _begin(aid, 60.0)
	if pw <= 0.0:
		return -1
	var s := int(down["slot"])
	var cc: Dictionary = Game.cslot(s)
	cc.erase("down_until")
	cc["hp"] = maxi(1, int(round(Game.companion_max_hp(s) * _prm(aid, "pct", 0.5))))
	var word: String = {"human": "stands", "spirit": "re-forms", "construct": "restarts"}.get(str(down["kind"]), "stands")
	Game.message.emit(I18n.t("Call Back the Breath: %s %s, at half their life.") % [str(down["name"]), word])
	Game.log_event("companion_revived", {"npc": str(down["name"])})
	Game.stats_changed.emit()
	_ring(p.global_position, Color(1.0, 0.95, 0.6), 3.5)
	_support_done(aid, true)
	return 1


# ---- SUPPORT: boons ----------------------------------------------------------------------

func _scale_effect(eff: Dictionary, s: float) -> Dictionary:
	var out := {}
	for k in eff:
		var v := float(eff[k])
		if v > 1.0:
			out[k] = 1.0 + (v - 1.0) * s
		elif v < 1.0 and v > 0.0:
			out[k] = maxf(1.0 - (1.0 - v) * s, 0.5)
		else:
			out[k] = v
	return out


func _boon(aid: String) -> int:
	var pw := _begin(aid, 30.0)
	if pw <= 0.0:
		return -1
	var A = _A()
	var dur: float = float(A.resonance(aid)["dur"])
	var s := clampf(pw, 0.9, 1.4)
	var pr: Dictionary = Game.technique_defs.get(aid, {}).get("params", {})
	var eff: Dictionary = _scale_effect(pr.get("effect", {}), s)
	var secs := float(pr.get("seconds", 20.0)) * dur
	Game.add_buff(aid, eff, secs)
	var allies := 0
	for e in A.party():
		if str(e["who"]) != "you" and A.in_reach(e, p.global_position, float(pr.get("radius", 12.0))) and not bool(e["down"]):
			allies += 1
	if allies > 0:
		if pr.has("ally_dmg"):
			A.set_ally_buff("dmg", 1.0 + (float(pr["ally_dmg"]) - 1.0) * s, secs)
		if pr.has("ally_take"):
			A.set_ally_buff("take", 1.0 - (1.0 - float(pr["ally_take"])) * s, secs)
	Game.message.emit("%s: %s%s." % [str(Game.technique_defs[aid]["name"]), I18n.t("for %d seconds") % int(secs), (I18n.t(", and %d with you") % allies) if allies > 0 else ""])
	_ring(p.global_position, Color(1.0, 0.85, 0.4), 2.8)
	_support_done(aid, true)
	return 1


func _refill(aid: String) -> int:
	var pw := _begin(aid, 30.0)
	if pw <= 0.0:
		return -1
	Game.heat = maxf(Game.heat - _prm(aid, "vent", 60.0) * clampf(pw, 0.9, 1.4), 0.0)
	p.ki_shots = minf(p.ki_shots + _prm(aid, "ki", 3.0), 12.0)
	var dur: float = float(_A().resonance(aid)["dur"])
	Game.add_buff(aid, {"regen": maxf(1.0, Game.max_hp() * _prm(aid, "regen", 0.01))}, _prm(aid, "regen_secs", 10.0) * dur)
	Game.message.emit("Still Heart: the heat goes out of you, and your ki steadies.")
	_ring(p.global_position, Color(0.6, 0.9, 1.0), 2.4)
	_support_done(aid, true)
	return 1


# ---- SUPPORT: hexes ----------------------------------------------------------------------

func _hex_targets(rng: float, count: int) -> Array:
	var cands := []
	var fwd := _fwd()
	for e in _foes():
		var to: Vector3 = _flat(e.global_position - p.global_position)
		var d := to.length()
		if d <= rng:
			cands.append([d * (1.0 if d < 0.6 or fwd.dot(to.normalized()) > 0.3 else 2.5), e])
	cands.sort_custom(func(a, b): return a[0] < b[0])
	var out := []
	for c in cands:
		if out.size() >= count:
			break
		out.append(c[1])
	return out


func _hex_mark(aid: String) -> int:
	var t := _hex_targets(_prm(aid, "radius", 10.0), int(_prm(aid, "count", 3)))
	if t.is_empty():
		if p._art_ok(aid):
			Game.message.emit("Mark of Prey needs a foe in sight.")
			p._cool[aid] = 0.6
		return -1
	var pw := _begin(aid, 14.0)
	if pw <= 0.0:
		return -1
	var dur: float = float(_A().resonance(aid)["dur"])
	for e in t:
		e.sundered = maxf(e.sundered, _prm(aid, "seconds", 8.0) * dur)
		e.sunder_mult = maxf(e.sunder_mult, 1.0 + (_prm(aid, "mult", 1.25) - 1.0) * clampf(pw, 0.9, 1.3))
		if FX.on():
			FX.word(e.global_position + Vector3(0, 2.4, 0), "MARKED", Color(1.0, 0.8, 0.3), 36)
	p._beam_fx(t[0].global_position)
	_support_done(aid, true)
	return t.size()


func _hex_weaken(aid: String) -> int:
	var t := _hex_targets(_prm(aid, "radius", 8.0), 99)
	if t.is_empty():
		if p._art_ok(aid):
			Game.message.emit("Withering Gaze needs foes near.")
			p._cool[aid] = 0.6
		return -1
	var pw := _begin(aid, 20.0)
	if pw <= 0.0:
		return -1
	var dur: float = float(_A().resonance(aid)["dur"])
	for e in t:
		var w := _prm(aid, "weak", 0.7)
		if bool(e.stats.get("boss", false)):
			w = lerpf(1.0, w, 0.5)                 # a great foe shrugs off half of it
		w = 1.0 - (1.0 - w) * clampf(pw, 0.9, 1.3)
		e.weakened = maxf(e.weakened, _prm(aid, "seconds", 10.0) * dur)
		e.weak_mult = minf(e.weak_mult, maxf(w, 0.4))
		e.burn(int(round(Game.damage() * _prm(aid, "burn", 0.15) * 4.0)), 4.0)
		if FX.on():
			FX.word(e.global_position + Vector3(0, 2.4, 0), "WEAKENED", Color(0.9, 0.5, 0.3), 34)
	_ring(p.global_position, Color(1.0, 0.5, 0.2), _prm(aid, "radius", 8.0))
	_support_done(aid, true)
	return t.size()


func _hex_root(aid: String) -> int:
	var t := _hex_targets(_prm(aid, "radius", 6.0), 99)
	if t.is_empty():
		if p._art_ok(aid):
			Game.message.emit("Binding Roots needs foes near.")
			p._cool[aid] = 0.6
		return -1
	var pw := _begin(aid, 16.0)
	if pw <= 0.0:
		return -1
	var dur: float = float(_A().resonance(aid)["dur"])
	for e in t:
		e.stagger(_prm(aid, "stagger", 1.0) * clampf(pw, 0.9, 1.3))
		e.slow(_prm(aid, "slow", 5.0) * dur)
	_ring(p.global_position, Color(0.4, 0.8, 0.3), _prm(aid, "radius", 6.0))
	_support_done(aid, true)
	return t.size()



# ---- round 188: the weapon arts' own ways of fighting (data/weapon_arts.json) -----------------------------------

func _name(aid: String) -> String:
	return I18n.t(str(Game.technique_defs.get(aid, {}).get("name", aid)))


func _style_col(dflt: Color) -> Color:
	## a Strike Style look (if one is worn) colours the weapon arts too -- looks only
	var LK = Game.sys("looks")
	return LK.strike_color(dflt) if LK != null and LK.has_method("strike_color") else dflt


func _need_foe(aid: String, ok: bool) -> bool:
	if ok:
		return true
	if p._art_ok(aid):
		Game.message.emit(I18n.t("%s needs a foe within reach.") % _name(aid))
		p._cool[aid] = 0.5
	return false


func _close_first(list: Array) -> Array:
	var pl = p
	list.sort_custom(func(a, b): return _flat(a.global_position - pl.global_position).length() < _flat(b.global_position - pl.global_position).length())
	return list


func _flurry(aid: String) -> int:
	## many quick blows on the nearest one or two in front
	var reach := _prm(aid, "reach", 3.0)
	var arc := _prm(aid, "arc", 110.0)
	var any := false
	for e in _foes():
		if _in_cone(e, reach + 0.6, arc):
			any = true
	if not _need_foe(aid, any):
		return -1
	var pw := _begin(aid, 6.0)
	if pw <= 0.0:
		return -1
	var hits := int(_prm(aid, "hits", 5))
	var gap := _prm(aid, "interval", 0.08)
	var pl = p
	var col := _style_col(Color(0.9, 0.95, 1.0))
	var acc := {"dmg": 0, "n": 0, "last": null}
	p._hurt_cool = maxf(p._hurt_cool, 0.12)
	p._play("cast", true)
	for i in hits:
		var nth := i
		p.get_tree().create_timer(gap * i + 0.02).timeout.connect(func():
			if not is_instance_valid(pl) or pl.dead:
				return
			var tg := []
			for e in _foes():
				if _in_cone(e, reach + 0.6, arc):
					tg.append(e)
			tg = _close_first(tg).slice(0, 2)
			for e in tg:
				var m := _prm(aid, "mult", 0.5)
				if _prm(aid, "crit", 0.0) > 0.0 and randf() < _prm(aid, "crit", 0.0):
					m *= 1.6
					if FX.on():
						FX.word(e.global_position + Vector3(0, 2.2, 0), I18n.t("TRUE"), Color(1.0, 0.9, 0.5), 30)
				var dmg := _dmg(aid, m, pw)
				pl._strike_hit(aid, e, dmg, int(acc["n"]), _src(aid))
				if _prm(aid, "stagger", 0.0) > 0.0:
					e.stagger(_prm(aid, "stagger", 0.0))
				acc["dmg"] = int(acc["dmg"]) + dmg
				acc["n"] = int(acc["n"]) + 1
				acc["last"] = e
			if FX.on():
				FX.slash(pl, col, reach * 0.55 + 0.6, pl._model.rotation.y + (0.5 if nth % 2 == 0 else -0.5), 0.9 + 0.12 * (nth % 3))
			if nth == hits - 1:
				var last = acc["last"]
				if _prm(aid, "bleed", 0.0) > 0.0 and last != null and is_instance_valid(last) and not last._dead:
					last.burn(int(round(float(acc["dmg"]) * _prm(aid, "bleed", 0.0))), 4.0)
					if FX.on():
						FX.word(last.global_position + Vector3(0, 2.4, 0), I18n.t("BLEEDING"), Color(0.9, 0.25, 0.25), 32)
				pl._strike_practice(aid, int(acc["n"]))
				Game.log_event("art_used", {"hit": int(acc["n"]), "art": aid}))
	return 1


func _whirl(aid: String) -> int:
	## a spin with the weapon out: several turns, everything round you each turn, still on your feet
	var pw := _begin(aid, 8.0)
	if pw <= 0.0:
		return -1
	var r := _prm(aid, "radius", 3.2)
	var ticks := int(_prm(aid, "ticks", 4))
	var gap := _prm(aid, "interval", 0.24)
	if absf(_prm(aid, "move", 1.0) - 1.0) > 0.01:
		Game.add_buff(aid, {"move_mult": _prm(aid, "move", 1.0)}, gap * ticks + 0.1)
	var pl = p
	var col := _style_col(Color(0.95, 0.9, 0.8))
	var tot := {"n": 0}
	p._hurt_cool = maxf(p._hurt_cool, 0.1)
	for i in ticks:
		var nth := i
		p.get_tree().create_timer(gap * i).timeout.connect(func():
			if not is_instance_valid(pl) or pl.dead:
				return
			pl._play("cast", true)
			if FX.on():
				FX.slash(pl, col, r * 0.7, pl._model.rotation.y + PI * nth, 0.9)
				FX.slash(pl, col, r * 0.7, pl._model.rotation.y + PI * nth + PI, 1.0)
			for e in _foes():
				if _flat(e.global_position - pl.global_position).length() <= r:
					var dmg := _dmg(aid, _prm(aid, "mult", 0.7), pw)
					pl._strike_hit(aid, e, dmg, int(tot["n"]), _src(aid))
					if _prm(aid, "bleed", 0.0) > 0.0:
						e.burn(int(round(dmg * _prm(aid, "bleed", 0.0))), 3.0)
					if _prm(aid, "knock", 0.0) > 0.0 and not bool(e.stats.get("boss", false)):
						var away: Vector3 = _flat(e.global_position - pl.global_position)
						e._knock = (away.normalized() if away.length() > 0.1 else _fwd()) * _prm(aid, "knock", 0.0) * 2.0
					tot["n"] = int(tot["n"]) + 1
			if nth == ticks - 1:
				_ring(pl.global_position, col, r)
				pl._shake(0.18)
				pl._strike_practice(aid, int(tot["n"]))
				Game.log_event("art_used", {"hit": int(tot["n"]), "art": aid}))
	return 1


func _line_hits(from: Vector3, fwd: Vector3, rng: float, wid: float) -> Array:
	var out := []
	for e in _foes():
		var to: Vector3 = _flat(e.global_position - from)
		var along := to.dot(fwd)
		if along < -0.4 or along > rng:
			continue
		if (to - fwd * along).length() <= wid * 0.5 + 0.7:
			out.append(e)
	return out


func _throw(aid: String) -> int:
	## the weapon (or a fan of blades) flies out along a line -- and, for some, spins home again
	var pw := _begin(aid, 7.0)
	if pw <= 0.0:
		return -1
	var rng := _prm(aid, "range", 10.0)
	var wid := _prm(aid, "width", 1.6)
	var fwd := _fwd()
	var from: Vector3 = p.global_position
	var col := _style_col(Color(0.85, 0.85, 0.9))
	var back := _prm(aid, "returns", 0.0) > 0.0
	var pl = p
	p._play("cast", true)
	if FX.on():
		_flyer(from + Vector3(0, 1.2, 0), from + Vector3(0, 1.2, 0) + fwd * rng, col, back, wid > 2.5)
	var pass_hit := func(tag: int) -> int:
		if not is_instance_valid(pl) or pl.dead:
			return 0
		var n := 0
		for e in _line_hits(from, fwd, rng, wid):
			var dmg := _dmg(aid, _prm(aid, "mult", 1.2), pw)
			pl._strike_hit(aid, e, dmg, n + tag, _src(aid))
			if _prm(aid, "bleed", 0.0) > 0.0:
				e.burn(int(round(dmg * _prm(aid, "bleed", 0.0))), 4.0)
			if _prm(aid, "stagger", 0.0) > 0.0:
				e.stagger(_prm(aid, "stagger", 0.0))
			n += 1
		return n
	var first: int = pass_hit.call(0)
	if back:
		p.get_tree().create_timer(0.55).timeout.connect(func():
			var n2: int = pass_hit.call(10)
			if is_instance_valid(pl):
				pl._strike_practice(aid, first + n2))
	else:
		p._strike_practice(aid, first)
	Game.log_event("art_used", {"hit": first, "art": aid})
	return first


func _flyer(a: Vector3, b: Vector3, col: Color, back: bool, fan: bool) -> void:
	## what you throw, seen: a spinning blade out (and home), or a fan of three
	var root: Node = p.get_tree().current_scene if p.get_tree().current_scene != null else p.get_parent()
	if root == null:
		return
	var dirs := [0.0] if not fan else [-0.22, 0.0, 0.22]
	for off in dirs:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.7, 0.05, 0.16)
		mi.mesh = bm
		var m := StandardMaterial3D.new()
		m.albedo_color = col
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = 1.5
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
		mi.global_position = a
		var to: Vector3 = (b - a).rotated(Vector3.UP, off)
		var tw := mi.create_tween()
		tw.set_parallel(true)
		tw.tween_property(mi, "global_position", a + to, 0.3).set_ease(Tween.EASE_OUT)
		tw.tween_property(mi, "rotation:y", TAU * 3.0, 0.3)
		if back:
			tw.chain().set_parallel(true)
			tw.tween_property(mi, "global_position", a, 0.3).set_ease(Tween.EASE_IN)
			tw.tween_property(mi, "rotation:y", TAU * 6.0, 0.3)
		tw.chain().tween_callback(mi.queue_free)


func _volley(aid: String) -> int:
	## arrows (or bolts) loosed high, falling round the foe you face
	var tgt = _nearest_front(_prm(aid, "range", 20.0), 0.3)
	if not _need_foe(aid, tgt != null):
		return -1
	var pw := _begin(aid, 8.0)
	if pw <= 0.0:
		return -1
	var centre: Vector3 = tgt.global_position
	var r := _prm(aid, "radius", 3.2)
	var n := int(_prm(aid, "arrows", 8))
	var pl = p
	var col := _style_col(Color(0.95, 0.9, 0.7))
	var tot := {"n": 0}
	p._play("cast", true)
	_ring(centre, col, r)
	for i in n:
		var nth := i
		p.get_tree().create_timer(0.35 + 0.07 * i).timeout.connect(func():
			if not is_instance_valid(pl) or pl.dead:
				return
			var near := []
			for e in _foes():
				if _flat(e.global_position - centre).length() <= r:
					near.append(e)
			var spot: Vector3 = centre + Vector3(randf_range(-r, r), 0, randf_range(-r, r)) * 0.7
			if near.size() > 0:
				var e = near[randi() % near.size()]
				spot = e.global_position
				pl._strike_hit(aid, e, _dmg(aid, _prm(aid, "mult", 0.6), pw), int(tot["n"]), _src(aid))
				tot["n"] = int(tot["n"]) + 1
			if FX.on():
				FX.streak(spot + Vector3(0.6, 9.0, -0.4), spot + Vector3(0, 0.6, 0), col)
				FX.hit(spot + Vector3(0, 0.5, 0), col, false)
			if nth == n - 1:
				pl._strike_practice(aid, int(tot["n"]))
				Game.log_event("art_used", {"hit": int(tot["n"]), "art": aid}))
	return 1


func _counter(aid: String) -> int:
	## a stance: the next blow in a moment is turned aside and answered (Player.take_damage)
	var pw := _begin(aid, 8.0)
	if pw <= 0.0:
		return -1
	p._counter_t = _prm(aid, "secs", 1.5)
	p._counter = {"aid": aid, "mult": _prm(aid, "mult", 3.0) * pw, "stagger": _prm(aid, "stagger", 1.4), "cool_heat": _prm(aid, "cool_heat", 0.0)}
	_ring(p.global_position, _style_col(Color(0.7, 0.9, 1.0)), 1.6)
	_word(I18n.t("STANCE"), Color(0.7, 0.9, 1.0))
	p._play("guard", true)
	return 0


func counter_strike(from) -> void:
	## (Player.take_damage, while the stance holds) the blow meets nothing; they meet the answer
	var c: Dictionary = p._counter
	var aid := str(c.get("aid", ""))
	if from == null or not is_instance_valid(from) or not from.has_method("take_damage"):
		return
	var dmg := maxi(1, int(round(Game.damage() * float(c.get("mult", 3.0)) * Game.branch_damage_mult(aid))))
	p._strike_hit(aid, from, dmg, 0, _src(aid))
	if from.has_method("stagger"):
		from.stagger(float(c.get("stagger", 1.4)))
	if float(c.get("cool_heat", 0.0)) > 0.0:
		Game.heat = maxf(0.0, Game.heat - float(c["cool_heat"]))
	if FX.on():
		FX.word(p.global_position + Vector3(0, 2.4, 0), I18n.t("COUNTER"), Color(0.75, 0.95, 1.0), 44)
		FX.slash(p, _style_col(Color(0.8, 0.95, 1.0)), 2.4, p._model.rotation.y, 1.1)
	p._shake(0.2)
	p.hit_stop(0.06)
	p._strike_practice(aid, 1)
	Game.log_event("art_used", {"hit": 1, "art": aid, "counter": true})


func _multi(aid: String) -> int:
	## a shot (or an orb) for each of several foes
	var rng := _prm(aid, "range", 15.0)
	var cone := _prm(aid, "cone", 0.2)
	var fwd := _fwd()
	var tg := []
	for e in _foes():
		var to: Vector3 = _flat(e.global_position - p.global_position)
		if to.length() <= rng and (to.length() < 0.6 or fwd.dot(to.normalized()) >= cone):
			tg.append(e)
	if not _need_foe(aid, not tg.is_empty()):
		return -1
	var pw := _begin(aid, 6.0)
	if pw <= 0.0:
		return -1
	tg = _close_first(tg).slice(0, int(_prm(aid, "targets", 4)))
	var col := _style_col(Color(0.8, 0.9, 1.0))
	var n := 0
	for e in tg:
		p._beam_fx(e.global_position)
		if FX.on():
			FX.hit(e.global_position + Vector3(0, 1.0, 0), col, false)
		p._strike_hit(aid, e, _dmg(aid, _prm(aid, "mult", 1.0), pw), n, _src(aid))
		n += 1
	p._play("cast", true)
	p._strike_practice(aid, n)
	Game.log_event("art_used", {"hit": n, "art": aid})
	return n


func _pin(aid: String) -> int:
	## a heavy shot that nails the foe you face where it stands
	var tgt = _nearest_front(_prm(aid, "range", 18.0), 0.3)
	if not _need_foe(aid, tgt != null):
		return -1
	var pw := _begin(aid, 7.0)
	if pw <= 0.0:
		return -1
	p._beam_fx(tgt.global_position)
	p._strike_hit(aid, tgt, _dmg(aid, _prm(aid, "mult", 1.2), pw), 0, _src(aid))
	var secs := _prm(aid, "secs", 3.0)
	tgt.stagger(secs if not bool(tgt.stats.get("boss", false)) else secs * 0.35)
	if tgt.has_method("slow"):
		tgt.slow(secs)
	if FX.on():
		FX.word(tgt.global_position + Vector3(0, 2.4, 0), I18n.t("PINNED"), Color(0.9, 0.8, 0.5), 36)
	p._play("cast", true)
	p._strike_practice(aid, 1)
	Game.log_event("art_used", {"hit": 1, "art": aid})
	return 1


func _blade_arc(aid: String, r: float, plain := Color(0, 0, 0, 0)) -> void:
	## (round 188) a weapon art's sweep is drawn as the blade's arc -- in your Strike Style if you wear one.
	## Other arts draw nothing here unless given a plain colour.
	if not FX.on():
		return
	if Game.sys("arts") == null or str(Game.sys("arts").weapon_of(aid)) == "":
		if plain.a > 0.0:
			FX.slash(p, plain, r * 0.8, p._model.rotation.y, 1.0)
		return
	var LK = Game.sys("looks")
	var st: Dictionary = LK.strike_style() if LK != null and LK.has_method("strike_style") else {}
	if st.is_empty():
		st = {"style": "", "color": _style_col(Color(0.9, 0.95, 1.0))}
	FX.strike(p, st, r * 0.8, p._model.rotation.y, 1.0)
