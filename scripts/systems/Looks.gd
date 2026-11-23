extends "res://scripts/systems/GameSystem.gd"
## Round 183: the store's look packs (data/looks.json). Robert, 2026-11-07: "keep working on rounding out the whole
## project" -- the store's catalogue, built: Spirit Beast Coats, Tribulation Skies, Cultivation Seats, Weapon Spirits,
## and the Look Collection that has them all (with the Style pack's auras).
## LOOKS ONLY. A look changes a colour or an effect drawn around you; nothing here is read by any number the game
## keeps (tools/fair_check.gd and tools/looks_check.gd snapshot every power number with every look on).
##   coats    the companion's coat and accent (Familiar._build asks coat())
##   skies    the lightning when you break through a realm (on_event "breakthrough" -> sky_burst)
##   seats    what gathers round you while you sit (Player.start_meditating -> seat_on, stop_meditating -> seat_off)
##   spirits  the colour of a blade's sweep (Player._deal_hit asks slash_color())
##   strikes  round 188: a Strike Style -- the shape of every blow's sweep and where it lands (FX.strike / FX.impact),
##            the colour of shots (Shot.gd) and of the weapon arts (ArtCaster._style_col). A Weapon Spirit's colour wins.
## Owning: Store.owns_look(pack) -- bought, the Collection, Steam DLC, the box's own builds, or an ad's try-on day.
## Chosen looks are kept per save (save_state). A look you no longer own (a try-on day ended) simply isn't drawn.

var choice := {"coats": "", "skies": "", "seats": "", "spirits": "", "trinkets": "", "strikes": ""}
var wardrobe := {}                 # round 183b: slot -> the gear id it LOOKS like, or "-" (hidden). Free for everyone.
var seen := {}                     # every wearable you've ever held (what the wardrobe can show)
var _seat: Node3D = null


func setup(game) -> void:
	super.setup(game)


func reset() -> void:
	choice = {"coats": "", "skies": "", "seats": "", "spirits": "", "trinkets": "", "strikes": ""}
	wardrobe = {}
	seen = {}


func save_state() -> Dictionary:
	return {"choice": choice.duplicate(), "wardrobe": wardrobe.duplicate(), "seen": seen.keys()}


func load_state(d: Dictionary) -> void:
	reset()
	var c = d.get("choice", {})
	if c is Dictionary:
		for k in choice:
			choice[k] = str(c.get(k, ""))
	var w = d.get("wardrobe", {})
	if w is Dictionary:
		for k in w:
			wardrobe[str(k)] = str(w[k])
	var sn = d.get("seen", [])
	if sn is Array:
		for id in sn:
			seen[str(id)] = true


func data() -> Dictionary:
	return load_json("res://data/looks.json")


func packs() -> Dictionary:
	return data().get("packs", {})


func pack(key: String) -> Dictionary:
	return packs().get(key, {})


func pack_of(kind: String) -> String:
	for k in packs():
		if str(packs()[k].get("kind", "")) == kind:
			return str(k)
	return ""


func owns(pack_key: String) -> bool:
	return G != null and G.store != null and G.store.owns_look(pack_key)


func current(kind: String) -> Dictionary:
	## the chosen item of this kind, if its pack is yours right now; {} = the game's own look
	var id := str(choice.get(kind, ""))
	if id == "":
		return {}
	var pk := pack_of(kind)
	if pk == "" or not owns(pk):
		return {}
	return pack(pk).get("items", {}).get(id, {})


func choose(kind: String, id: String) -> void:
	if not choice.has(kind):
		return
	choice[kind] = id
	if kind in ["coats", "trinkets"] and G != null:
		G.familiar_changed.emit()                 # the companion redraws in its new coat or trinket
	if kind == "seats" and _seat != null:
		var host := _seat.get_parent() as Node3D
		seat_off()
		if host:
			seat_on(host)


func cycle(kind: String) -> void:
	## the next item of the pack (and then the game's own look again)
	var pk := pack_of(kind)
	var ids: Array = [""] + pack(pk).get("items", {}).keys()
	var i := ids.find(str(choice.get(kind, "")))
	choose(kind, str(ids[(i + 1) % ids.size()]))


func item_name(kind: String) -> String:
	var it := current(kind)
	return I18n.t(str(it.get("name", ""))) if not it.is_empty() else I18n.t("the game's own")


static func _col(a, fallback: Color) -> Color:
	if a is Array and a.size() >= 3:
		return Color(float(a[0]), float(a[1]), float(a[2]))
	return fallback


# ---- the hooks ---------------------------------------------------------------------------------------------------------

func coat() -> Array:
	## [coat, accent] for the companion, or [] for its own colours
	var it := current("coats")
	if it.is_empty():
		return []
	return [_col(it.get("coat"), Color.WHITE), _col(it.get("accent"), Color.WHITE)]


func slash_color(fallback: Color) -> Color:
	var it := current("spirits")
	return fallback if it.is_empty() else _col(it.get("color"), fallback).lightened(0.15)


func strike_style() -> Dictionary:
	## {} = the game's own blows; else {"style", "color"} (a Weapon Spirit, if worn, gives the colour)
	var it := current("strikes")
	if it.is_empty():
		return {}
	var c := _col(it.get("color"), Color(0.9, 0.95, 1.0))
	var sp := current("spirits")
	if not sp.is_empty():
		c = _col(sp.get("color"), c).lightened(0.15)
	return {"style": str(it.get("style", "")), "color": c}


func strike_color(fallback: Color) -> Color:
	var st := strike_style()
	if st.is_empty():
		return slash_color(fallback) if not current("spirits").is_empty() else fallback
	return st["color"]


func sky_color() -> Color:
	var it := current("skies")
	return Color(0.75, 0.88, 1.0) if it.is_empty() else _col(it.get("color"), Color(0.75, 0.88, 1.0))


func on_event(kind: String, _data: Dictionary) -> void:
	if kind == "breakthrough" and G != null and G.is_inside_tree():
		var p = G.get_tree().get_first_node_in_group("player")
		if p is Node3D:
			sky_burst(p, sky_color(), not current("skies").is_empty())


static func sky_burst(at: Node3D, c: Color, forks: bool) -> void:
	## the heavens answer a breakthrough: a column of light and strikes (with a pack: more strikes, walking forks)
	var FXs = preload("res://scripts/fx/FX.gd")
	if not FXs.on() or at == null or not at.is_inside_tree():
		return
	var where := at.global_position
	FXs.beam(where, c, 1.6)
	var n := 5 if forks else 2
	for i in n:
		var t := at.get_tree().create_timer(0.12 + 0.22 * float(i))
		var off := Vector3(randf_range(-2.6, 2.6), 0, randf_range(-2.6, 2.6)) if i > 0 else Vector3.ZERO
		t.timeout.connect(func():
			if is_instance_valid(at) and at.is_inside_tree():
				_bolt(at.get_tree().current_scene if at.get_tree().current_scene else at.get_tree().root, where + off, c)
				FXs.ring(where + off, c, 1.6 if i > 0 else 3.0, 0.35))


static func _bolt(root: Node, to: Vector3, c: Color) -> void:
	## a jagged strike from the sky down to a point, gone in half a second
	var im := ImmediateMesh.new()
	var mi := MeshInstance3D.new()
	mi.mesh = im
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(1, 1, 1, 1.0)
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
	var top := to + Vector3(randf_range(-1.5, 1.5), 16.0, randf_range(-1.5, 1.5))
	var pts := [top]
	var steps := 9
	for i in range(1, steps):
		var f := float(i) / float(steps)
		pts.append(top.lerp(to, f) + Vector3(randf_range(-0.7, 0.7), 0, randf_range(-0.7, 0.7)))
	pts.append(to)
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for pass_ in [[3.5, 0.22], [1.0, 1.0]]:              # a wide faint glow, then the bright core
		for i in pts.size() - 1:
			var a: Vector3 = pts[i]
			var b: Vector3 = pts[i + 1]
			var w: float = (0.13 * (1.0 - float(i) / float(pts.size())) + 0.05) * float(pass_[0])
			var col := Color(c.r, c.g, c.b, float(pass_[1])) if pass_[1] < 1.0 else c.lightened(0.55)
			for side in [Vector3(w, 0, 0), Vector3(0, 0, w)]:
				for v in [a - side, a + side, b + side, a - side, b + side, b - side]:
					im.surface_set_color(col)
					im.surface_add_vertex(v)
	im.surface_end()
	root.add_child(mi)
	var light := OmniLight3D.new()
	light.light_color = c
	light.light_energy = 4.0
	light.omni_range = 9.0
	root.add_child(light)
	light.global_position = to + Vector3(0, 1.5, 0)
	var tw := mi.create_tween()
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.45)
	tw.parallel().tween_property(light, "light_energy", 0.0, 0.45)
	tw.tween_callback(func():
		mi.queue_free()
		light.queue_free())


# ---- the wardrobe (free: any gear you've ever held, worn as a look) ---------------------------------------------------

func saw(id: String) -> void:
	## (called as an item comes into your bag) a wearable passed through your hands -- the wardrobe can show it from now on
	if id == "" or seen.has(id) or G == null or G.gear_family(id) == "" or G.gear_family(id) == "weapon":
		return
	if seen.size() >= int(data().get("wardrobe", {}).get("max_seen", 400)):
		return
	seen[id] = true


func _seed() -> void:
	## a save from before the wardrobe: what you carry and wear now counts as seen
	if not seen.is_empty() or G == null:
		return
	for id in G.inventory.keys():
		saw(str(id))
	for sl in G.equipment:
		saw(str(G.equipment[sl]))


func wardrobe_for(slot: String) -> String:
	return str(wardrobe.get(slot, ""))


func set_wardrobe(slot: String, id: String) -> void:
	## "" = show what you really wear, "-" = hide the slot, an id = look like that piece
	if id == "":
		wardrobe.erase(slot)
	elif id == "-" or (seen.has(id) and G != null and slot in G.slots_for(G.gear_family(id))):
		wardrobe[slot] = id
	else:
		return
	if G != null:
		G.stats_changed.emit()                    # (the player redresses on this; no number reads the wardrobe)


func options_for(slot: String) -> Array:
	## every seen piece that fits this slot, by name
	_seed()
	var out := []
	if G == null:
		return out
	for id in seen:
		if slot in G.slots_for(G.gear_family(str(id))) and G.has_item_def(str(id)):
			out.append(str(id))
	out.sort_custom(func(a, b): return str(G.item_def(a).get("name", a)).naturalnocasecmp_to(str(G.item_def(b).get("name", b))) < 0)
	return out


func look_id_for(slot: String, real_id: String) -> String:
	## Game.worn_looks: what this slot is drawn as ("-" hidden; the real piece if nothing is set)
	var w := wardrobe_for(slot)
	if w == "":
		return real_id
	if w == "-":
		return "-"
	return w if (G != null and G.has_item_def(w)) else real_id


func wardrobe_menu(hud) -> void:
	_seed()
	var lines := [I18n.t("Wear the look of any piece you've ever held, or hide a slot. Free, and looks only -- what you really wear decides every number."), ""]
	var opts := []
	for s in G.gear_slots():
		var sl := str(s[0])
		if sl == "weapon":
			continue
		var real: String = G.worn(sl)
		var w := wardrobe_for(sl)
		if real == "" and w == "" and options_for(sl).is_empty():
			continue
		var shown: String = I18n.t("hidden") if w == "-" else (str(G.item_def(w).get("name", w)) if w != "" else I18n.t("as worn"))
		var sl2 := sl
		opts.append(["%s: %s" % [I18n.t(str(s[1])), shown], func(): _slot_menu(hud, sl2)])
	if opts.is_empty():
		lines.append(I18n.t("Nothing to choose from yet -- wear something first."))
	opts.append(["Back", func(): menu(hud)])
	hud.open_dialog(I18n.t("Wardrobe"), "\n".join(lines), opts)


func _slot_menu(hud, slot: String) -> void:
	var opts := [[I18n.t("As worn (what you really wear)"), func():
		set_wardrobe(slot, "")
		wardrobe_menu(hud)], [I18n.t("Hide this slot"), func():
		set_wardrobe(slot, "-")
		wardrobe_menu(hud)]]
	var ids := options_for(slot)
	for id in ids.slice(0, 24):
		var id2: String = id
		opts.append([str(G.item_def(id2).get("name", id2)), func():
			set_wardrobe(slot, id2)
			wardrobe_menu(hud)])
	opts.append(["Back", func(): wardrobe_menu(hud)])
	hud.open_dialog(I18n.t(G.slot_name(slot)), I18n.t("Pick the look for this slot.") + ("" if ids.size() <= 24 else "\n" + I18n.t("(the first 24 by name)")), opts)


# ---- seats -----------------------------------------------------------------------------------------------------------

func seat_on(host: Node3D) -> void:
	seat_off()
	var it := current("seats")
	if it.is_empty() or host == null or not preload("res://scripts/fx/FX.gd").on():
		return
	_seat = make_seat(str(choice["seats"]), _col(it.get("color"), Color.WHITE))
	host.add_child(_seat)


func seat_off() -> void:
	if _seat != null and is_instance_valid(_seat):
		_seat.queue_free()
	_seat = null


static func make_seat(id: String, c: Color) -> Node3D:
	## built in code (no imported art): drawn round the sitter, turning slowly
	var root: Node3D = SeatSpin.new()
	root.name = "SeatLook"
	match id:
		"lotus":
			root.add_child(_glow_disc(c.lightened(0.2), 2.2, 0.35))
			var layers := [[10, 0.82, 0.0, c, -0.45, 2.3], [8, 0.56, PI / 8.0, c.lightened(0.25), -0.8, 2.0], [6, 0.3, 0.0, c.lightened(0.5), -1.1, 1.7]]
			for L in layers:
				var pm := _petal_mat(L[3])
				for i in int(L[0]):
					var petal := MeshInstance3D.new()
					var sm := SphereMesh.new()
					sm.radius = 0.2
					sm.height = 0.1
					sm.radial_segments = 14
					sm.rings = 6
					petal.mesh = sm
					petal.material_override = pm
					var a: float = float(i) / float(L[0]) * TAU + float(L[2])
					var piv := Node3D.new()
					piv.rotation.y = -a
					piv.position.y = 0.05
					petal.position = Vector3(float(L[1]), 0.0, 0.0)
					petal.scale = Vector3(float(L[5]), 1.0, 1.0)
					petal.rotation.z = -float(L[4])
					piv.add_child(petal)
					root.add_child(piv)
			root.set_meta("spin", 0.22)
		"stones":
			root.add_child(_glow_disc(Color(0.6, 0.85, 1.0), 2.4, 0.22))
			var rock := StandardMaterial3D.new()
			rock.albedo_color = c
			rock.roughness = 0.95
			var rng := RandomNumberGenerator.new()
			rng.seed = 7
			for i in 7:
				var st := MeshInstance3D.new()
				var sm := SphereMesh.new()
				sm.radius = 0.1 + 0.05 * float(i % 3)
				sm.height = sm.radius * 2.0
				sm.radial_segments = 6
				sm.rings = 3
				st.mesh = sm
				st.material_override = rock
				var a := float(i) / 7.0 * TAU
				st.position = Vector3(cos(a) * 1.1, 0.75, sin(a) * 1.1)
				st.scale = Vector3(rng.randf_range(0.8, 1.4), rng.randf_range(0.6, 1.0), rng.randf_range(0.8, 1.3))
				st.rotation = Vector3(rng.randf() * TAU, rng.randf() * TAU, 0)
				st.set_meta("bob", float(i) * 0.9)
				root.add_child(st)
			root.set_meta("spin", 0.18)
		"koi":
			var water := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = 1.45
			cyl.bottom_radius = 1.45
			cyl.height = 0.02
			cyl.radial_segments = 48
			water.mesh = cyl
			water.position.y = 0.02
			var wm := StandardMaterial3D.new()
			wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			wm.albedo_color = Color(0.22, 0.42, 0.55, 0.55)
			wm.metallic = 0.3
			wm.roughness = 0.08
			water.material_override = wm
			root.add_child(water)
			var rim := MeshInstance3D.new()
			var tm := TorusMesh.new()
			tm.inner_radius = 1.42
			tm.outer_radius = 1.52
			rim.mesh = tm
			rim.scale = Vector3(1.0, 0.4, 1.0)
			rim.position.y = 0.03
			var rm := StandardMaterial3D.new()
			rm.albedo_color = Color(0.5, 0.48, 0.44)
			rim.material_override = rm
			root.add_child(rim)
			for i in 2:
				var pad := MeshInstance3D.new()
				var pc := CylinderMesh.new()
				pc.top_radius = 0.18
				pc.bottom_radius = 0.18
				pc.height = 0.01
				pad.mesh = pc
				var padm := StandardMaterial3D.new()
				padm.albedo_color = Color(0.25, 0.5, 0.25)
				pad.material_override = padm
				pad.position = Vector3(cos(1.3 + 3.0 * i) * 1.15, 0.04, sin(1.3 + 3.0 * i) * 1.15)
				root.add_child(pad)
			var cols := [c, Color(0.96, 0.95, 0.92), Color(1.0, 0.8, 0.3)]
			for i in 3:
				var fish := Node3D.new()
				var a := float(i) / 3.0 * TAU
				fish.position = Vector3(cos(a) * 1.0, 0.09, sin(a) * 1.0)
				fish.rotation.y = -a
				var fm := StandardMaterial3D.new()
				fm.albedo_color = cols[i]
				fm.roughness = 0.4
				var body := MeshInstance3D.new()
				var cm := CapsuleMesh.new()
				cm.radius = 0.09
				cm.height = 0.5
				body.mesh = cm
				body.rotation.x = PI / 2.0
				body.scale = Vector3(1.0, 1.0, 0.75)
				body.material_override = fm
				fish.add_child(body)
				var tail := MeshInstance3D.new()
				var pm := PrismMesh.new()
				pm.size = Vector3(0.24, 0.2, 0.02)
				tail.mesh = pm
				tail.material_override = fm
				tail.position = Vector3(0, 0, -0.33)
				tail.rotation.x = PI / 2.0
				fish.add_child(tail)
				var fin := MeshInstance3D.new()
				var fp := PrismMesh.new()
				fp.size = Vector3(0.02, 0.06, 0.14)
				fin.mesh = fp
				fin.material_override = fm
				fin.position = Vector3(0, 0.07, 0.02)
				fish.add_child(fin)
				root.add_child(fish)
			root.set_meta("spin", 0.5)
		_:                                          # "ink"
			var im := StandardMaterial3D.new()
			im.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			im.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			im.albedo_color = Color(c.r, c.g, c.b, 0.55)
			for k in 3:                             # three passes of the brush, slightly off each other
				var disc := MeshInstance3D.new()
				var tm := TorusMesh.new()
				tm.inner_radius = 0.95 + 0.04 * float(k)
				tm.outer_radius = 1.08 + 0.07 * float(k)
				tm.rings = 48
				disc.mesh = tm
				disc.scale = Vector3(1.0, 0.02, 1.0)
				disc.position = Vector3(0.03 * float(k - 1), 0.02 + 0.002 * float(k), -0.02 * float(k - 1))
				disc.material_override = im
				root.add_child(disc)
			for i in 9:
				var dab := MeshInstance3D.new()
				var sm := SphereMesh.new()
				sm.radius = 0.07 + 0.03 * float(i % 3)
				sm.height = 0.02
				dab.mesh = sm
				dab.material_override = im
				var a := float(i) / 9.0 * TAU + 0.2 * float(i % 2)
				dab.position = Vector3(cos(a) * (1.32 + 0.1 * float(i % 3)), 0.02, sin(a) * (1.32 + 0.1 * float(i % 3)))
				dab.scale = Vector3(1.0, 1.0, 2.2 + 0.8 * float(i % 2))
				dab.rotation.y = -a
				root.add_child(dab)
			root.set_meta("spin", 0.06)
	return root


static func _glow_disc(c: Color, size: float, alpha: float) -> MeshInstance3D:
	## a soft pool of light on the ground
	var m := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	q.orientation = PlaneMesh.FACE_Y
	m.mesh = q
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_texture = preload("res://scripts/fx/FX.gd").soft_dot()
	mat.albedo_color = Color(c.r, c.g, c.b, alpha)
	m.material_override = mat
	m.position.y = 0.02
	return m


static func _petal_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(c.r, c.g, c.b, 0.82)
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = 0.35
	m.roughness = 0.6
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


class SeatSpin extends Node3D:
	var _t := 0.0
	func _process(delta: float) -> void:
		_t += delta
		rotation.y += delta * float(get_meta("spin", 0.2))
		for ch in get_children():
			if ch.has_meta("bob"):
				ch.position.y = 0.75 + 0.18 * sin(_t * 1.4 + float(ch.get_meta("bob")))


# ---- the page ----------------------------------------------------------------------------------------------------------

func menu(hud) -> void:
	var st = G.store
	var lines := [I18n.t("Looks change how things look -- never a number. Nothing here makes you stronger."), ""]
	var opts := []
	for pk in packs():
		var p: Dictionary = packs()[pk]
		var kind := str(p.get("kind", ""))
		var mine := owns(str(pk))
		lines.append("%s%s" % [I18n.t(str(p.get("name", pk))), "" if mine else "  " + I18n.t("(not yours yet)")])
		lines.append("   " + I18n.t(str(p.get("pitch", ""))))
		if mine:
			var k2 := kind
			opts.append([I18n.t(str(p.get("slot", kind))) + ": " + item_name(kind) + I18n.t("  (tap to change)"), func():
				cycle(k2)
				menu(hud)])
		elif st != null and st.can_buy(str(pk)):
			var pk2 := str(pk)
			var price: String = st.price_text(pk2)
			opts.append([I18n.t("Get %s") % I18n.t(str(p.get("name", pk))) + ("  (%s)" % price if price != "" else ""), func():
				var why: String = st.buy(pk2, func(): menu(hud))
				if why != "":
					G.message.emit(why)])
	if st != null and st.can_buy("look_collection"):
		var pr: String = st.price_text("look_collection")
		opts.append([I18n.t("Get the Look Collection (every pack and the Style pack)") + ("  (%s)" % pr if pr != "" else ""), func():
			var why: String = st.buy("look_collection", func(): menu(hud))
			if why != "":
				G.message.emit(why)])
	opts.insert(0, ["Wardrobe (wear any piece you've held as a look -- free)...", func(): wardrobe_menu(hud)])
	if G.ads != null and G.ads.style_trial():
		lines.append("")
		lines.append(I18n.t("Trying on every look: %s left.") % G._dur(G.ads.style_trial_left()))
	opts.append(["Back", func(): G.Comfort.menu(hud)])
	hud.open_dialog(I18n.t("Looks"), "\n".join(lines), opts)
