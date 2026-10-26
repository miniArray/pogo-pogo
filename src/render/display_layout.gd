class_name DisplayLayout
extends RefCounted
## Presentation geometry only. Expanded rasters reveal scenery, never change
## the 256x240 reference window the game simulates. Ratios describe the whole
## raster including the status band.
const REFERENCE := Vector2i(256, 240)
const MODES := ["original", "fill", "16:9", "4:3", "1:1", "21:9", "32:9", "16:10", "3:2", "9:16"]


static func ratio_for(mode: String) -> float:
	var parts := mode.split(":")
	if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return 0.0
	var w := int(parts[0])
	var h := int(parts[1])
	if w < 1 or w > 100 or h < 1 or h > 100:
		return 0.0
	var ratio := float(w) / h
	return ratio if ratio >= 0.125 and ratio <= 8.0 else 0.0


static func valid_mode(mode: String) -> String:
	return mode if mode in ["original", "fill"] or ratio_for(mode) > 0 else "original"


static func calculate(available: Vector2i, mode: String, sharp: bool) -> Dictionary:
	mode = valid_mode(mode)
	var size := Vector2(maxi(available.x, 1), maxi(available.y, 1))
	var fitted := size
	var ratio := ratio_for(mode)
	if ratio > 0:
		fitted = Vector2(minf(size.x, size.y * ratio), minf(size.y, size.x / ratio))
	var zoom := minf(fitted.x / REFERENCE.x, fitted.y / REFERENCE.y)
	# Tiny windows must still fit the entire reference area: fractional downscale
	# takes precedence over whole-number zoom when even 1x will not fit.
	if sharp and zoom >= 1.0:
		zoom = floorf(zoom)
	var raster := Vector2(REFERENCE) if mode == "original" else fitted / zoom
	var rect := Rect2((size - raster * zoom) * 0.5, raster * zoom)
	return {"mode": mode, "scale": zoom, "raster": raster, "rect": rect}
