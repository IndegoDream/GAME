extends Control

signal colorblind_changed(palette: String)
signal text_size_changed(scale: float)
signal key_remapped(action: String, key_code: int)

var options_panel: VBoxContainer
var colorblind_option: OptionButton
var text_size_slider: HSlider
var text_size_label: Label
var keymap_container: VBoxContainer

var current_colorblind: String = "None"
var current_text_scale: float = 1.0
var key_bindings: Dictionary = {
	"move_up": KEY_W,
	"move_down": KEY_S,
	"move_left": KEY_A,
	"move_right": KEY_D,
	"interact": KEY_E
}

const SAVE_PATH: String = "user://settings.cfg"

func _ready() -> void:
	_setup_ui()
	load_settings()

func _setup_ui() -> void:
	anchor_right = 1.0
	anchor_bottom = 1.0
	
	options_panel = VBoxContainer.new()
	options_panel.name = "OptionsPanel"
	add_child(options_panel)
	
	var cb_label: Label = Label.new()
	cb_label.text = "Colorblind Palette:"
	options_panel.add_child(cb_label)
	
	colorblind_option = OptionButton.new()
	colorblind_option.add_item("None")
	colorblind_option.add_item("Protanopia")
	colorblind_option.add_item("Deuteranopia")
	colorblind_option.add_item("Tritanopia")
	colorblind_option.item_selected.connect(_on_colorblind_selected)
	options_panel.add_child(colorblind_option)
	
	var ts_header: Label = Label.new()
	ts_header.text = "Text Size Scale:"
	options_panel.add_child(ts_header)
	
	text_size_slider = HSlider.new()
	text_size_slider.min_value = 0.8
	text_size_slider.max_value = 1.5
	text_size_slider.step = 0.1
	text_size_slider.value = 1.0
	text_size_slider.value_changed.connect(_on_text_size_changed)
	options_panel.add_child(text_size_slider)
	
	text_size_label = Label.new()
	text_size_label.text = "100%"
	options_panel.add_child(text_size_label)
	
	var km_header: Label = Label.new()
	km_header.text = "Key Remapping:"
	options_panel.add_child(km_header)
	
	keymap_container = VBoxContainer.new()
	options_panel.add_child(keymap_container)
	_build_keymap_ui()

func _build_keymap_ui() -> void:
	for child in keymap_container.get_children():
		child.queue_free()
	
	for action_name in key_bindings.keys():
		var hbox: HBoxContainer = HBoxContainer.new()
		var lbl: Label = Label.new()
		lbl.text = String(action_name) + ": "
		hbox.add_child(lbl)
		
		var btn: Button = Button.new()
		var key_code: int = int(key_bindings[action_name])
		btn.text = OS.get_keycode_string(key_code) if key_code > 0 else "None"
		var act_str: String = String(action_name)
		btn.pressed.connect(func(): _start_remapping(act_str, btn))
		hbox.add_child(btn)
		
		keymap_container.add_child(hbox)

func _start_remapping(action_name: String, button: Button) -> void:
	button.text = "Press Key..."

func remap_action_key(action_name: String, new_key_code: int) -> void:
	key_bindings[action_name] = new_key_code
	key_remapped.emit(action_name, new_key_code)
	_build_keymap_ui()
	save_settings()

func _on_colorblind_selected(index: int) -> void:
	current_colorblind = colorblind_option.get_item_text(index)
	colorblind_changed.emit(current_colorblind)
	save_settings()

func _on_text_size_changed(val: float) -> void:
	current_text_scale = val
	text_size_label.text = str(round(val * 100.0)) + "%"
	text_size_changed.emit(current_text_scale)
	save_settings()

func save_settings() -> void:
	var config: ConfigFile = ConfigFile.new()
	config.set_value("graphics", "colorblind", current_colorblind)
	config.set_value("ui", "text_scale", current_text_scale)
	for action in key_bindings:
		config.set_value("keys", String(action), key_bindings[action])
	config.save(SAVE_PATH)

func load_settings() -> void:
	var config: ConfigFile = ConfigFile.new()
	if config.load(SAVE_PATH) == OK:
		current_colorblind = String(config.get_value("graphics", "colorblind", "None"))
		current_text_scale = float(config.get_value("ui", "text_scale", 1.0))
		for action in key_bindings.keys():
			var act_str: String = String(action)
			if config.has_section_key("keys", act_str):
				key_bindings[act_str] = int(config.get_value("keys", act_str, key_bindings[act_str]))
	
	for i in range(colorblind_option.item_count):
		if colorblind_option.get_item_text(i) == current_colorblind:
			colorblind_option.selected = i
			break
	
	text_size_slider.value = current_text_scale
	text_size_label.text = str(round(current_text_scale * 100.0)) + "%"
	_build_keymap_ui()
	
	colorblind_changed.emit(current_colorblind)
	text_size_changed.emit(current_text_scale)
