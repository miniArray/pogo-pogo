class_name SpriteSheet
extends RefCounted
## Reads an Aseprite sheet export (JSON + PNG) into tagged picture lists.
##
## Tags name animations, `sourceSize` is each picture's canvas,
## `spriteSourceSize` restores trimmed art, and a slice named `origin` with a
## pivot gives the actor point. Without that slice the actor point is the
## canvas centre. Art faces right; the game mirrors it. Pictures never change
## motion, timing, state or collision.
const JsonDocument = preload("res://src/shared/json_document.gd")
const SCHEMA_PATH := "res://schema/sprite-sheet.schema.json"
const MAX_JSON_BYTES := 2 * 1024 * 1024
const MAX_FRAMES := 4096
const MAX_PICTURES := 64
const ORIGIN_SLICE := "origin"


class Picture:
	extends RefCounted
	var texture: Texture2D
	## Top-left of the picture relative to the actor point, in world pixels.
	var offset: Vector2
	## Drawn size in world pixels.
	var size: Vector2
	## Updates this picture stays on screen when the engine cycles by time.
	var weight := 1


var tags := {}  # name -> Array[Picture]
var notices: Array[String] = []


func pictures(tag: String) -> Array:
	return tags.get(tag, [])


## Returns {kind: "ready", sheet, image_name} or a problem dictionary.
## `allowed` lists tag names the game draws; others are reported as notices.
static func read(
	json_bytes: PackedByteArray, load_image: Callable, allowed: Array, texels_per_pixel: int
) -> Dictionary:
	var document := JsonDocument.read(json_bytes, SCHEMA_PATH, MAX_JSON_BYTES)
	if document.kind != "ready":
		return document
	var data: Dictionary = document.data
	var image: Variant = load_image.call(str(data.meta.image))
	if image is Dictionary:
		return image
	var sheet_image: Image = image
	var frames: Array = data.frames.values() if data.frames is Dictionary else data.frames
	if not data.frames is Array and not data.frames is Dictionary:
		return JsonDocument.problem("schema", "$.frames", "Expected an array or object.")
	if frames.is_empty() or frames.size() > MAX_FRAMES:
		return JsonDocument.problem("schema", "$.frames", "Expected 1..%d frames." % MAX_FRAMES)
	var root := JsonDocument.schema_at(SCHEMA_PATH)
	for index in range(frames.size()):
		var error := JsonDocument.validate(
			frames[index], root["$defs"]["frame"], "$.frames[%d]" % index, root
		)
		if not error.is_empty():
			return error
		var rect := _rect(frames[index].frame)
		if not Rect2i(Vector2i.ZERO, sheet_image.get_size()).encloses(rect) or not rect.has_area():
			return JsonDocument.problem(
				"schema", "$.frames[%d].frame" % index, "Frame lies outside the sheet image."
			)
	var pivots: Variant = _pivots(data.meta.get("slices", []), frames.size())
	if pivots is String:
		return JsonDocument.problem("schema", "$.meta.slices", str(pivots))
	var sheet := SpriteSheet.new()
	for tag in data.meta.frameTags:
		var name := str(tag.name).to_lower()
		if name not in allowed:
			sheet.notices.append('Tag "%s" is not drawn by the game.' % str(tag.name))
			continue
		if sheet.tags.has(name):
			return JsonDocument.problem("schema", "$.meta.frameTags", 'Tag "%s" appears twice.' % name)
		if tag.to < tag.from or tag.to >= frames.size():
			return JsonDocument.problem(
				"schema", "$.meta.frameTags", 'Tag "%s" names frames that do not exist.' % name
			)
		var list: Array = []
		for index in _sequence(tag.from, tag.to, str(tag.direction)):
			list.append(_picture(sheet_image, frames[index], pivots.get(index), texels_per_pixel))
		if list.size() > MAX_PICTURES:
			return JsonDocument.problem(
				"schema", "$.meta.frameTags", 'Tag "%s" has more than %d pictures.' % [name, MAX_PICTURES]
			)
		sheet.tags[name] = list
	if sheet.tags.is_empty():
		return JsonDocument.problem(
			"schema", "$.meta.frameTags", "No tag names an animation the game draws: %s." % ", ".join(allowed)
		)
	return {"kind": "ready", "sheet": sheet}


static func _sequence(from: int, to: int, direction: String) -> Array[int]:
	var forward: Array[int] = []
	for index in range(from, to + 1):
		forward.append(index)
	match direction:
		"reverse":
			forward.reverse()
			return forward
		"pingpong", "pingpong_reverse":
			var back := forward.slice(1, forward.size() - 1)
			back.reverse()
			if direction == "pingpong_reverse":
				forward.reverse()
				back.reverse()
			return forward + back
	return forward


static func _picture(sheet: Image, frame: Dictionary, pivot: Variant, density: int) -> Picture:
	var rect := _rect(frame.frame)
	var canvas := Vector2i(frame.sourceSize.w, frame.sourceSize.h)
	var trim := Vector2i(frame.spriteSourceSize.x, frame.spriteSourceSize.y)
	var anchor: Vector2i = pivot if pivot is Vector2i else canvas / 2
	var picture := Picture.new()
	picture.texture = ImageTexture.create_from_image(sheet.get_region(rect))
	picture.offset = Vector2(trim - anchor) / density
	picture.size = Vector2(rect.size) / density
	picture.weight = maxi(roundi(int(frame.duration) * 60 / 1000.0), 1)
	return picture


## The `origin` slice gives each frame's actor point: slice bounds position
## plus pivot. A slice key applies from its frame until the next key.
static func _pivots(slices: Array, count: int) -> Variant:
	var result := {}
	for slice in slices:
		if str(slice.name).to_lower() != ORIGIN_SLICE:
			continue
		var keys: Array = slice.keys
		keys.sort_custom(func(a, b): return a.frame < b.frame)
		for k in range(keys.size()):
			var key: Dictionary = keys[k]
			if not key.has("pivot"):
				return "The origin slice needs a pivot on every key."
			var until: int = keys[k + 1].frame if k + 1 < keys.size() else count
			for index in range(key.frame, mini(until, count)):
				result[index] = Vector2i(key.bounds.x + key.pivot.x, key.bounds.y + key.pivot.y)
	return result


static func _rect(value: Dictionary) -> Rect2i:
	return Rect2i(value.x, value.y, value.w, value.h)
