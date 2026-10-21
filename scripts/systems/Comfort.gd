extends RefCounted
## Round 127: pay for CONVENIENCE and STYLE, never for POWER. (Robert: "work on the pay for convenience but not pay to win.")
## What money buys, in total:
##   - the full game: no ads, plus the comforts below (Steam's paid game has them from the start)
##   - the Style pack: cosmetic auras (phones; included in the Steam game)
##   - expansions: new places and stories (data/store.json), never stronger numbers
## What it never touches: damage, health, qi, insight, drops, luck, prices, any progression speed. tools/fair_check.gd
## proves it -- it fails if a purchase changes any of those numbers, or if the power functions ever mention the store.

const COMFORTS := [
	["slots", "Five character slots instead of three"],
	["auto_stash", "Materials go to your home stash by themselves when you reach the village"],
	["stash_anywhere", "Send materials to the stash from anywhere"],
	["sell_spare", "Sell all your spare gear in one go (below Superior, never what you wear)"],
]
const AURAS := [
	["", "No aura", [0.0, 0.0, 0.0, 0.0]],
	["ember", "Ember", [1.0, 0.5, 0.2, 0.6]],
	["jade", "Jade", [0.3, 0.9, 0.55, 0.6]],
	["azure", "Azure", [0.35, 0.65, 1.0, 0.6]],
	["violet", "Violet", [0.7, 0.45, 1.0, 0.6]],
	["gold", "Gold", [1.0, 0.85, 0.4, 0.6]],
	["rose", "Rose", [1.0, 0.45, 0.65, 0.6]],
	["frost", "Frost", [0.8, 0.95, 1.0, 0.6]],
	["shadow", "Shadow", [0.35, 0.25, 0.5, 0.7]],
]


static func comfort() -> bool:
	return Game.store != null and Game.store.comfort()


static func style() -> bool:
	return Game.store != null and Game.store.style()


static func slots() -> int:
	return 5 if comfort() else 3


static func aura_index() -> int:
	return clampi(int(Game.counters.get("style_aura", 0.0)), 0, AURAS.size() - 1)


static func aura_color() -> Color:
	if not style():
		return Color(0, 0, 0, 0)
	var a: Array = AURAS[aura_index()][2]
	return Color(a[0], a[1], a[2], a[3])


static func cycle_aura() -> void:
	Game.counters["style_aura"] = float((aura_index() + 1) % AURAS.size())
	Game.stats_changed.emit()                 # the player redraws its aura on this


static func auto_stash_on() -> bool:
	return comfort() and float(Game.counters.get("comfort_autostash", 1.0)) > 0.0


static func on_village() -> void:
	## arriving in the village with the comforts: the pouch's materials go home by themselves
	if not auto_stash_on() or not bool(Game.home.get("have", false)):
		return
	var n: int = Game.stash_all_materials()
	if n > 0:
		Game.message.emit("Comforts: %d materials went to your home stash." % n)


static func stash_now() -> int:
	if not comfort() or not bool(Game.home.get("have", false)):
		return -1
	return Game.stash_all_materials()


static func spare_list() -> Array:
	## [[id, count, each], ...]: gear you aren't wearing, below Superior, that a trader would take
	var out := []
	for id in Game.inventory.keys():
		var sid := str(id)
		if Game.gear_family(sid) == "" or Game.is_treasure(sid) or Game.quality_index(sid) >= 3:
			continue
		var each: int = Game.sell_price(sid)
		var n: int = Game.count(sid) - Game.equipped_count(sid)
		if each > 0 and n > 0:
			out.append([sid, n, each])
	return out


static func sell_spare() -> Array:
	## -> [pieces, gold]
	var pieces := 0
	var gold := 0
	for r in spare_list():
		var sid: String = r[0]
		var n: int = r[1]
		Game.remove_item(sid, n)
		pieces += n
		gold += n * int(r[2])
	if gold > 0:
		Game.add_item("gold", gold, false)
	Game.stats_changed.emit()
	return [pieces, gold]


static func menu(hud) -> void:
	var st = Game.store
	var lines := []
	if comfort():
		lines.append(I18n.t("Your comforts are on:"))
		for c in COMFORTS:
			lines.append("  -  " + str(c[1]))
	else:
		lines.append(I18n.t("The full game adds comforts -- never power:"))
		for c in COMFORTS:
			lines.append("  -  " + str(c[1]))
	lines.append("")
	lines.append(I18n.t("Nothing here makes you hit harder, live longer, find better loot or level faster. That is a promise."))
	var opts := []
	if comfort():
		var on := float(Game.counters.get("comfort_autostash", 1.0)) > 0.0
		opts.append(["Auto-stash in the village: %s" % ("on" if on else "off"), func():
			Game.counters["comfort_autostash"] = 0.0 if on else 1.0
			menu(hud)])
		opts.append(["Send materials to the stash now", func():
			var n := stash_now()
			Game.message.emit("No home stash yet." if n < 0 else "%d materials sent to the stash." % n)
			menu(hud)])
		var sp := spare_list()
		var tot := 0
		var pc := 0
		for r in sp:
			pc += int(r[1])
			tot += int(r[1]) * int(r[2])
		opts.append(["Sell spare gear: %d pieces for %d gold" % [pc, tot] if pc > 0 else I18n.t("Sell spare gear (nothing spare)"), func():
			if pc > 0:
				hud.open_dialog(I18n.t("Sell spare gear"), I18n.t("Sell %d pieces for %d gold? What you wear and anything Superior or better stays.") % [pc, tot], [
					["Sell", func():
						var r := sell_spare()
						Game.message.emit(I18n.t("Sold %d pieces for %d gold.") % [r[0], r[1]])
						menu(hud)],
					["Keep them", func(): menu(hud)]])])
	elif st != null and (st.phone_store() or st.demo()):
		opts.append(["Get the full game%s" % (("  (%s)" % st.price_text()) if st.price_text() != "" else ""), func():
			hud.close_dialog()
			hud.open_unlock("", "")])
	if style():
		opts.append(["Aura: %s  (tap to change)" % AURAS[aura_index()][1], func():
			cycle_aura()
			menu(hud)])
	elif st != null and st.can_buy("style_pack"):
		opts.append(["Style pack -- auras, cosmetic only%s" % (("  (%s)" % st.price_text("style_pack")) if st.price_text("style_pack") != "" else ""), func():
			var why: String = st.buy("style_pack")
			if why != "":
				Game.message.emit(why)
			hud.close_dialog()])
	opts.append(["Close", hud.close_dialog])
	hud.open_dialog("Comforts & Style", "\n".join(PackedStringArray(lines)), opts)
