extends RefCounted
## Surfaces drawn in code (round 123): metal plate, deck grating, hull, rust, regolith, glass, slag. No picture files:
## each is a height field built from a pattern plus noise, turned into an albedo and a normal map when first asked
## for, then kept. Look.texture() hands these out for any "folder" that starts with "proc_".
## (Robert, 2026-10-16: "dev can create its own art, we just have to make sure the assets are in a form usable to
## the game" -- these are the form: a Texture2D the triplanar surface material takes like any photo texture.)

const KINDS := ["proc_plate", "proc_deck", "proc_hull", "proc_rust", "proc_regolith", "proc_glass", "proc_slag"]
static var _cache := {}


static func size_px() -> int:
	return 128 if (OS.has_feature("mobile") or OS.has_feature("web")) else 256


static func texture(kind: String, which: String) -> Texture2D:
	var key := "%s|%s|%d" % [kind, which, size_px()]
	if _cache.has(key):
		return _cache[key]
	var imgs := build(kind, size_px())
	for w in imgs:
		var t := ImageTexture.create_from_image(imgs[w])
		_cache["%s|%s|%d" % [kind, w, size_px()]] = t
	return _cache.get(key)


static func _noise(seed_: int, freq: float, oct: int = 3) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = seed_
	n.frequency = freq
	n.fractal_octaves = oct
	return n


static func build(kind: String, px: int) -> Dictionary:
	## {"albedo": Image, "normal": Image, "arm": Image} (all seamless: the noise wraps via 4-way blending, the grids repeat)
	var hs := PackedFloat32Array()
	hs.resize(px * px)
	var col := PackedColorArray()
	col.resize(px * px)
	var n1 := _noise(hash(kind), 0.06)
	var n2 := _noise(hash(kind) + 7, 0.22, 2)
	var cell := px / 4                                 # a panel is a quarter of the texture
	for y in px:
		for x in px:
			var i := y * px + x
			var a := _wrapped(n1, x, y, px)
			var b := _wrapped(n2, x, y, px)
			var h := 0.5
			var c := Color(0.5, 0.5, 0.5)
			match kind:
				"proc_plate":
					var lx := x % cell
					var ly := y % cell
					var seam := lx < 3 or ly < 3
					var rivet := _rivet(lx, ly, cell)
					h = 0.55 + 0.08 * a - (0.35 if seam else 0.0) + (0.18 if rivet else 0.0)
					var g := 0.52 + 0.1 * a + 0.05 * b
					c = Color(g * 0.95, g, g * 1.08)
					if seam:
						c = c * 0.55
					if rivet:
						c = c * 1.25
				"proc_deck":
					var lx := x % (cell / 2)
					var bar := lx < (cell / 2) * 0.28
					var cross := (y % cell) < 3
					h = 0.5 + 0.06 * a - (0.4 if bar else 0.0) - (0.25 if cross else 0.0)
					var g := 0.45 + 0.08 * a
					c = Color(g, g * 1.04, g * 1.1) * (0.35 if bar else 1.0)
				"proc_hull":
					var lx := x % cell
					var ly := y % (cell / 2)
					var seam := lx < 2 or ly < 2
					h = 0.6 + 0.05 * a - (0.3 if seam else 0.0)
					var g := 0.72 + 0.07 * a
					c = Color(g, g * 1.02, g * 1.06) * (0.7 if seam else 1.0)
					if (y / (cell / 2)) % 4 == 1 and ly > 4 and ly < 8:
						c = Color(0.35, 0.65, 0.95)           # a painted stripe
				"proc_rust":
					var streak := _wrapped(_noise(hash(kind) + 3, 0.02, 1), x * 4, y, px)
					h = 0.5 + 0.2 * a + 0.1 * b
					var r := clampf(0.5 + 0.6 * (a + streak * 0.5), 0.0, 1.0)
					c = Color(0.62, 0.4, 0.28).lerp(Color(0.34, 0.33, 0.35), 1.0 - r) * (0.8 + 0.2 * b)
					if absf(streak) < 0.05:
						c = c * 0.7
				"proc_regolith":
					h = 0.5 + 0.35 * a + 0.2 * b
					var g := 0.42 + 0.14 * a + 0.1 * b
					c = Color(g, g * 1.0, g * 1.07)
					if b > 0.55:
						c = c * 1.25
				"proc_glass":
					var band := sin((x * 0.045 + a * 3.0) * TAU * 0.25) * 0.5 + 0.5
					h = 0.5 + 0.12 * a + 0.08 * band
					c = Color(0.95, 0.74, 0.42).lerp(Color(0.72, 0.5, 0.78), band * 0.7) * (0.8 + 0.25 * b)
				"proc_slag":
					var crack := absf(a)
					var glow := clampf(1.0 - crack * 7.0, 0.0, 1.0)
					h = 0.5 + 0.25 * b - glow * 0.2
					c = Color(0.16, 0.14, 0.14).lerp(Color(0.9, 0.34, 0.1), glow * 0.85) * (0.8 + 0.3 * b)
			hs[i] = h
			col[i] = c
	var alb := Image.create(px, px, true, Image.FORMAT_RGB8)
	var nor := Image.create(px, px, true, Image.FORMAT_RGB8)
	var arm := Image.create(px, px, true, Image.FORMAT_RGB8)
	var strength := 3.0
	for y in px:
		for x in px:
			var i := y * px + x
			alb.set_pixel(x, y, col[i])
			var hl := hs[y * px + (x - 1 + px) % px]
			var hr := hs[y * px + (x + 1) % px]
			var hu := hs[((y - 1 + px) % px) * px + x]
			var hd := hs[((y + 1) % px) * px + x]
			var v := Vector3((hl - hr) * strength, (hu - hd) * strength, 1.0).normalized()
			nor.set_pixel(x, y, Color(v.x * 0.5 + 0.5, v.y * 0.5 + 0.5, v.z * 0.5 + 0.5))
			var ao := clampf(hs[i] * 1.4, 0.0, 1.0)
			var rough := 0.55 if kind in ["proc_plate", "proc_deck", "proc_hull"] else 0.92
			var metal := 0.8 if kind in ["proc_plate", "proc_deck", "proc_hull"] else 0.0
			arm.set_pixel(x, y, Color(ao, rough, metal))
	alb.generate_mipmaps()
	nor.generate_mipmaps()
	arm.generate_mipmaps()
	return {"albedo": alb, "normal": nor, "arm": arm}


static func _wrapped(n: FastNoiseLite, x: int, y: int, px: int) -> float:
	## tileable noise: blend four offset samples across the seam
	var fx := float(x) / px
	var fy := float(y) / px
	var a := n.get_noise_2d(x, y)
	var b := n.get_noise_2d(x - px, y)
	var c := n.get_noise_2d(x, y - px)
	var d := n.get_noise_2d(x - px, y - px)
	return lerpf(lerpf(a, b, fx), lerpf(c, d, fx), fy)


static func _rivet(lx: int, ly: int, cell: int) -> bool:
	var m := 8
	return (absi(lx - m) < 2 and absi(ly - m) < 2) or (absi(lx - (cell - m)) < 2 and absi(ly - m) < 2) \
		or (absi(lx - m) < 2 and absi(ly - (cell - m)) < 2) or (absi(lx - (cell - m)) < 2 and absi(ly - (cell - m)) < 2)
