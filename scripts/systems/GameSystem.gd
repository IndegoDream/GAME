extends Node
## The shape of a game system (round 40). Robert, 2026-10-04: "build it to
## make sense and modular -- if we build a modular game it will make
## updates easier."
##
## A system is one Node under the Game autoload, with its own data file and
## its own saved state. Game.gd calls these hooks on every system it has
## (Game.SYSTEM_SCRIPTS), so a new system is: a script that extends this,
## a line in that list, and a page in the menu if it wants one.
##
##   setup(game)        once, at start: read your data, merge any items/recipes
##   reset()            a new game
##   save_state()       -> Dictionary, kept under save["systems"][id]
##   load_state(d)      from that
##   effects()          -> Array of effect dictionaries (same keys as techniques)
##   tick(delta)        every frame
##   meditate(secs, shares, aid)   a second of sitting: shares is the mind's
##                      split {"cultivate", "cleanse", "research"}; aid is the
##                      meditation aids (shrine, incense, techniques)
##   background(secs, shares)      the swarm working while you don't sit
##                      (secs already scaled by the background rate)
##   on_event(kind, data)          (round 44) anything you do that the play log
##                      records (Game.log_event): a kill, a quest, a rest ...

var G                       # the Game autoload
var id := ""


func setup(game) -> void:
	G = game


func reset() -> void:
	pass


func save_state() -> Dictionary:
	return {}


func load_state(_d: Dictionary) -> void:
	pass


func effects() -> Array:
	return []


func tick(_delta: float) -> void:
	pass


func meditate(_secs: float, _shares: Dictionary, _aid: float) -> void:
	pass


func background(_secs: float, _shares: Dictionary) -> void:
	pass


func on_event(_kind: String, _data: Dictionary) -> void:
	pass


func load_json(path: String) -> Dictionary:
	var d = G._load_json(path, {})
	return (d if d is Dictionary else {}).duplicate(true)


class OptionsSystem extends "res://scripts/systems/GameSystem.gd":
	var colorblind_palette: String = "None"
	var text_size: float = 1.0
	var keybindings: Dictionary = {}
	var gamepad_enabled: bool = true
	var phone_layout_one_handed: bool = false
	var phone_layout_hand: String = "right"
	var subtitles_enabled: bool = true
	var sound_captions: bool = true
	var music_volume: float = 0.8
	var sfx_volume: float = 0.8
	var gamepad_mappings: Dictionary = {
		"move_up": [JOY_BUTTON_DPAD_UP],
		"move_down": [JOY_BUTTON_DPAD_DOWN],
		"move_left": [JOY_BUTTON_DPAD_LEFT],
		"move_right": [JOY_BUTTON_DPAD_RIGHT],
		"interact": [JOY_BUTTON_A],
		"attack": [JOY_BUTTON_X, JOY_BUTTON_RIGHT_SHOULDER]
	}

	func _init() -> void:
		id = "options"

	func reset() -> void:
		colorblind_palette = "None"
		text_size = 1.0
		keybindings = {
			"move_up": KEY_W,
			"move_down": KEY_S,
			"move_left": KEY_A,
			"move_right": KEY_D,
			"interact": KEY_E,
			"attack": KEY_SPACE
		}
		gamepad_enabled = true
		phone_layout_one_handed = false
		phone_layout_hand = "right"
		subtitles_enabled = true
		sound_captions = true
		music_volume = 0.8
		sfx_volume = 0.8
		apply_gamepad_mappings()

	func set_phone_layout_one_handed(enabled: bool, hand: String = "right") -> void:
		phone_layout_one_handed = enabled
		if hand == "left" or hand == "right":
			phone_layout_hand = hand

	func toggle_one_handed_layout() -> bool:
		phone_layout_one_handed = not phone_layout_one_handed
		return phone_layout_one_handed

	func get_one_handed_offsets() -> Dictionary:
		if not phone_layout_one_handed:
			return {"margin_bottom": 0, "align_side": "center", "action_bar_scale": 1.0}
		if phone_layout_hand == "left":
			return {"margin_bottom": 80, "align_side": "left", "action_bar_scale": 0.85}
		return {"margin_bottom": 80, "align_side": "right", "action_bar_scale": 0.85}

	func set_text_size(val: float) -> void:
		text_size = clampf(val, 0.5, 2.5)

	func adjust_text_size(delta: float) -> void:
		set_text_size(text_size + delta)

	func apply_gamepad_mappings() -> void:
		if not gamepad_enabled:
			return
		for action in gamepad_mappings:
			if not InputMap.has_action(action):
				InputMap.add_action(action)
			var buttons: Array = gamepad_mappings[action]
			for btn in buttons:
				var ev := InputEventJoypadButton.new()
				ev.button_index = btn as JoyButton
				if not InputMap.action_has_event(action, ev):
					InputMap.action_add_event(action, ev)

	func save_state() -> Dictionary:
		return {
			"colorblind_palette": colorblind_palette,
			"text_size": text_size,
			"keybindings": keybindings,
			"gamepad_enabled": gamepad_enabled,
			"phone_layout_one_handed": phone_layout_one_handed,
			"phone_layout_hand": phone_layout_hand,
			"subtitles_enabled": subtitles_enabled,
			"sound_captions": sound_captions,
			"music_volume": music_volume,
			"sfx_volume": sfx_volume
		}

	func load_state(d: Dictionary) -> void:
		if d.is_empty():
			reset()
			return
		colorblind_palette = d.get("colorblind_palette", "None")
		text_size = float(d.get("text_size", 1.0))
		keybindings = d.get("keybindings", {}).duplicate()
		gamepad_enabled = bool(d.get("gamepad_enabled", true))
		phone_layout_one_handed = bool(d.get("phone_layout_one_handed", false))
		phone_layout_hand = String(d.get("phone_layout_hand", "right"))
		subtitles_enabled = bool(d.get("subtitles_enabled", true))
		sound_captions = bool(d.get("sound_captions", true))
		music_volume = float(d.get("music_volume", 0.8))
		sfx_volume = float(d.get("sfx_volume", 0.8))
		apply_gamepad_mappings()


func load_texture_and_music_settings(path: String = "data/atlas.json") -> Dictionary:
	var data: Dictionary = load_json(path)
	if data.is_empty() and G != null:
		var alt_path: String = "res://" + path if not path.begins_with("res://") else path
		var raw: Variant = G._load_json(alt_path, {})
		if raw is Dictionary:
			data = (raw as Dictionary).duplicate(true)
	return {
		"texture_settings": data.get("texture_settings", {}),
		"music_settings": data.get("music_settings", {})
	}


func load_atlas_settings(path: String = "data/atlas.json") -> Dictionary:
	return load_texture_and_music_settings(path)


func add_elite_aura(aura_name: String, duration: float, effect: Dictionary) -> void:
	if G == null:
		return

	var aura_data = {
		"name": aura_name,
		"duration": duration,
		"effect": effect
	}

	G.aura_manager.add_aura(aura_data)


### Add a new function to handle elite auras.
### @param aura_name The name of the aura to add.
### @param duration The duration of the aura in seconds.
### @param effect A dictionary representing the effect of the aura.


### Add a new function to handle elite auras.
### @param aura_name The name of the aura to add.
### @param duration The duration of the aura in seconds.
### @param effect A dictionary representing the effect of the aura.


### Add a new function to handle elite auras.
### @param aura_name The name of the aura to add.
### @param duration The duration of the aura in seconds.
### @param effect A dictionary representing the effect of the aura.


### Add a new function to handle elite auras.
### @param aura_name The name of the aura to add.
### @param duration The duration of the aura in seconds.
### @param effect A dictionary representing the effect of the aura.


### Add a new function to handle elite auras.
### @param aura_name The name of the aura to add.
### @param duration The duration of the aura in seconds.
### @param effect A dictionary representing the effect of the aura.


### Add a new function to handle elite auras.
### @param aura_name The name of the aura to add.
### @param duration The duration of the aura in seconds.
### @param effect A dictionary representing the effect of the aura.
