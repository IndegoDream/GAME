class_name I18n
extends RefCounted
## Round 140: languages. Robert, 2026-10-17: "add the most common languages that would improve the success of the game."
## Ten: English plus Simplified Chinese, Spanish, Portuguese (Brazil), Russian, German, French, Japanese, Korean, Turkish.
## How it works: Godot translates a Label's or Button's text by looking the English text up in the catalog (data/i18n/<code>.json,
## built by tools/build_i18n.py from tools/i18n/part*.txt). So a screen is translated just by its words being in the catalog;
## anything not there stays English -- never blank, never a key. Item names, floor names and the story are data, and join the
## catalog as they are translated (the coverage counter on the language page says how much is done).
## CJK needs a font: the themed fonts are Latin, so a SystemFont (the player's own Noto / YaHei / Malgun / Yu Gothic) is chained in.

const LANGS := [
	["en", "English"], ["zh_CN", "简体中文"], ["es", "Español"], ["pt_BR", "Português (Brasil)"], ["ru", "Русский"],
	["de", "Deutsch"], ["fr", "Français"], ["ja", "日本語"], ["ko", "한국어"], ["tr", "Türkçe"],
]
const CFG := "user://language.cfg"
static var current := "en"
static var _loaded := {}
static var _cjk: Font = null


static func t(s: String) -> String:
	## Round 141: the words the game builds in code -- translate before filling in the numbers and names.
	## English (and anything not in the catalog) comes back unchanged, so this is always safe to wrap around a literal.
	if current == "en" or s == "":
		return s
	return str(TranslationServer.translate(s))


static func codes() -> Array:
	return LANGS.map(func(r): return r[0])


static func native_name(code: String) -> String:
	for r in LANGS:
		if r[0] == code:
			return str(r[1])
	return code


static func init() -> void:
	## once at start: the saved choice, else the device's language if we have it, else English
	var code := ""
	var cf := ConfigFile.new()
	if cf.load(CFG) == OK:
		code = str(cf.get_value("lang", "code", ""))
	if not (code in codes()):
		code = _match_os(OS.get_locale())
	apply(code)


static func _match_os(loc: String) -> String:
	var l := loc.replace("-", "_")
	for c in codes():
		if c == l:
			return c
	var base := l.get_slice("_", 0)
	if base == "zh":
		return "zh_CN"
	if base == "pt":
		return "pt_BR"
	for c in codes():
		if str(c).get_slice("_", 0) == base:
			return c
	return "en"


static func set_language(code: String) -> bool:
	if not (code in codes()):
		return false
	apply(code)
	var cf := ConfigFile.new()
	cf.set_value("lang", "code", code)
	cf.save(CFG)
	if Game != null and Game.has_signal("language_changed"):
		Game.language_changed.emit()
	return true


static func apply(code: String) -> void:
	if not (code in codes()):
		code = "en"
	current = code
	if code != "en" and not _loaded.has(code):
		var d = Game._load_json("res://data/i18n/%s.json" % code, {}) if Game != null else {}
		var t := PhraseTranslation.new()
		t.locale = code
		t.setup(d if d is Dictionary else {})
		TranslationServer.add_translation(t)
		_loaded[code] = t.size
	TranslationServer.set_locale(code)


static func coverage(code: String = "") -> int:
	## how many catalogued phrases this language has
	var c := code if code != "" else current
	if c == "en":
		return 0
	if not _loaded.has(c):
		apply(c)
	return int(_loaded.get(c, 0))


static func cjk_font() -> Font:
	## the player's own CJK-capable font, chained behind the themed ones (cheap if never needed: glyphs load on demand)
	if _cjk == null:
		var sf := SystemFont.new()
		sf.font_names = PackedStringArray(["Noto Sans CJK SC", "Noto Sans SC", "Microsoft YaHei", "PingFang SC", "Source Han Sans SC", "Noto Sans CJK JP", "Yu Gothic",
			"Noto Sans CJK KR", "Malgun Gothic", "Apple SD Gothic Neo", "WenQuanYi Micro Hei", "Droid Sans Fallback", "sans-serif"])
		sf.allow_system_fallback = true
		_cjk = sf
	return _cjk
