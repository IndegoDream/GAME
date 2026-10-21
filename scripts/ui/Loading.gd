extends CanvasLayer
## round 158 (Robert: "make a loading screen that gives tips and hints, don't just freeze the screen"):
## the veil that covers a change of place -- the name of where you're going, one tip, and a little motion so it never
## looks stuck. Main shows it, waits two frames for it to be drawn, builds the level, then lets it fade.

const TIPS := [
	"Quick keys: R, F3, F4 and F5 cast any art you assign. Menu > Arts, then tap the key under the art.",
	"Every key can be changed: pause menu > Controls.",
	"Hold still and press M to meditate; your qi refills faster than it ever does in a fight.",
	"A clash of elements isn't always bad -- an affinity you've tempered turns the clash into strength.",
	"Guard (B or right click) at the right moment turns a blow aside, and a perfect parry opens the foe.",
	"The hearth in your home keeps a chest; the test kit's vault reaches you anywhere.",
	"Companions can search for items, reagents, plants, jewels and shards while you go on -- ask them from the party page.",
	"Press Tab for the whole menu. The yellow NEXT line tells you what to do if you are ever unsure.",
	"Some walls aren't walls. Look for a crack in the stone, or a draught that moves the flame.",
	"A better weapon needs training: use it, and its skill climbs until you can wield it well.",
	"Salves heal, pills restore qi. Keep both on keys 1 and 2.",
	"Your pet and your followers fight beside you; give them rest between floors.",
	"Gather herbs and ore as you walk. Nothing is wasted -- the smith and the alchemist use it all.",
	"A tribulation is hard but fair: arrive rested, full of qi, and with your guard art ready.",
	"The map (F2) remembers where you have been. Stairs and waystones are marked.",
	"Dodge with Ctrl; wind step with V. Both cost a breath, so don't spend them idly.",
	"Every art grows with use. A resonant art, one close to your nature, grows faster.",
	"Flying sword (G) crosses ground quickly once you have earned the treasure.",
	"If you are ever stuck in a wall or outside the world, the game will put you back on your feet by itself.",
	"The village sells almost nothing you cannot make. The craft books are in the market.",
]

var _label: Label
var _name: Label
var _tip: Label
var _dots: Label
var _bg: ColorRect
var _t := 0.0
var _shown := false
static var _last := -1


func _init() -> void:
	layer = 120
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_bg = ColorRect.new()
	_bg.color = Color(0.03, 0.03, 0.06, 1.0)
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_bg)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.add_child(cc)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(minf(640.0, maxf(get_viewport_size_x() - 60.0, 280.0)), 0)
	box.add_theme_constant_override("separation", 18)
	cc.add_child(box)
	_name = _mk(box, 34, Color(1.0, 0.9, 0.65))
	_dots = _mk(box, 20, Color(0.6, 0.75, 0.9))
	_tip = _mk(box, 20, Color(0.85, 0.88, 0.95))
	_tip.custom_minimum_size = Vector2(box.custom_minimum_size.x, 90)


func get_viewport_size_x() -> float:
	return float(DisplayServer.window_get_size().x) if DisplayServer.get_name() != "headless" else 1000.0


func _mk(parent: Node, size: int, col: Color) -> Label:
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 4)
	parent.add_child(l)
	return l


func pick_tip() -> String:
	var i := randi() % TIPS.size()
	if i == _last:
		i = (i + 1) % TIPS.size()
	if "test kit" in str(TIPS[i]) and preload("res://scripts/systems/Tester.gd").clean():
		i = (i + 1) % TIPS.size()
	_last = i
	return I18n.t(TIPS[i])


func show_for(place: String) -> void:
	_name.text = I18n.t("Entering %s") % place if place != "" else I18n.t("Loading")
	_tip.text = pick_tip()
	_bg.modulate.a = 1.0
	_t = 0.0
	_shown = true
	visible = true
	set_process(true)


func fade_out() -> void:
	if not _shown:
		return
	_shown = false
	var tw := create_tween()
	tw.tween_property(_bg, "modulate:a", 0.0, 0.35)
	tw.tween_callback(func(): visible = false)


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	_dots.text = (I18n.t("Loading") + " " + ".".repeat(1 + int(_t * 3.0) % 3)) if _shown else ""
	if _shown and _t > 6.0 and int(_t) % 6 == 0 and fmod(_t, 1.0) < delta:
		_tip.text = pick_tip()
