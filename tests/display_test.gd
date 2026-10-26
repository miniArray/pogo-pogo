extends SceneTree
## Display layout: every mode fits its container, keeps the whole 256 x 240
## reference view, and sharp mode zooms by whole numbers when it can.
const Layout = preload("res://src/render/display_layout.gd")
const Check = preload("res://tests/check.gd")
const SIZES := [Vector2i(256, 240), Vector2i(320, 240), Vector2i(1280, 720), Vector2i(390, 844), Vector2i(2560, 1080), Vector2i(200, 150)]


func _init() -> void:
	var check := Check.new("DISPLAY_CHECK")
	for size in SIZES:
		for mode in Layout.MODES:
			for sharp in [true, false]:
				var layout := Layout.calculate(size, mode, sharp)
				var rect: Rect2 = layout.rect
				var label := "%s %s sharp=%s" % [size, mode, sharp]
				check.ok(rect.size.x <= size.x + 0.01 and rect.size.y <= size.y + 0.01, label + " fits")
				check.ok(layout.raster.x >= 255.99 and layout.raster.y >= 239.99, label + " keeps the reference view")
				if sharp and layout.scale >= 1.0:
					check.equal(layout.scale, floorf(layout.scale), label + " whole-number zoom")
	check.equal(Layout.valid_mode("7:0"), "original", "an invalid ratio falls back to original")
	check.equal(Layout.valid_mode("21:9"), "21:9", "a valid ratio is kept")
	quit(check.finish())
