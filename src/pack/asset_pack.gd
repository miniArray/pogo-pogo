class_name AssetPack
extends RefCounted
## A player-supplied asset pack: pictures and sounds only. It is a directory
## or a zip with `pack.json` at its root (see docs/asset-packs.md). A pack never
## changes motion, collision, timing or the course, and nothing missing from
## it is an error: the game draws a placeholder shape or plays nothing.
const JsonDocument = preload("res://src/shared/json_document.gd")
const Sheet = preload("res://src/pack/sprite_sheet.gd")
const PlayerAnim = preload("res://src/game/player_animation.gd")
const SCHEMA_PATH := "res://schema/asset-pack.schema.json"
const MANIFEST := "pack.json"
const MAX_MANIFEST_BYTES := 1024 * 1024
const MAX_FILE_BYTES := 16 * 1024 * 1024
const MAX_IMAGE_SIDE := 4096
const MAX_ENTRIES := 4096
const KEY_PATTERN := "^[a-z0-9][a-z0-9._-]{0,63}$"
## Sprite key -> tags the game draws for it.
const SPRITE_TAGS := {
	"walker": ["walk", "knocked_out"],
	"gem": ["idle"],
	"goal": ["idle"],
}
var name := ""
var source := ""
var _tiles := {}  # tileset -> {tile -> Texture2D}
var _backdrops := {}  # tileset -> Color
var _sprites := {}  # key -> SpriteSheet
var _hud := {}  # key -> Texture2D
var _sounds := {}  # event -> AudioStream
var _music := {}  # cue -> AudioStream
var notices: Array[String] = []


class Reader:
	extends RefCounted
	var _zip: ZIPReader
	var _dir := ""
	var _files := {}

	func open(path: String) -> String:
		if DirAccess.dir_exists_absolute(path):
			_dir = path
			return ""
		_zip = ZIPReader.new()
		if _zip.open(path) != OK:
			return "Cannot open %s as a directory or zip." % path.get_file()
		for file in _zip.get_files():
			_files[file] = true
		return ""

	func read(relative: String) -> Variant:
		if not _dir.is_empty():
			var full := _dir.path_join(relative)
			if not FileAccess.file_exists(full):
				return null
			var file := FileAccess.open(full, FileAccess.READ)
			if file == null or file.get_length() > MAX_FILE_BYTES:
				return null
			return file.get_buffer(file.get_length())
		if not _files.has(relative):
			return null
		return _zip.read_file(relative)

	func close() -> void:
		if _zip != null:
			_zip.close()


## Load a pack from a directory or zip path. Returns {kind: "ready", pack} or a problem.
static func load_path(path: String) -> Dictionary:
	var reader := Reader.new()
	var error := reader.open(path)
	if not error.is_empty():
		return JsonDocument.problem("file", "$", error)
	var result := _load(reader)
	reader.close()
	if result.kind == "ready":
		result.pack.source = path.get_file()
	return result


static func _load(reader: Reader) -> Dictionary:
	var bytes: Variant = reader.read(MANIFEST)
	if bytes == null:
		return JsonDocument.problem("file", "$", "The pack has no %s at its root." % MANIFEST)
	var document := JsonDocument.read(bytes, SCHEMA_PATH, MAX_MANIFEST_BYTES)
	if document.kind != "ready":
		return document
	var data: Dictionary = document.data
	var pack := AssetPack.new()
	pack.name = str(data.name)
	var key := RegEx.create_from_string(KEY_PATTERN)
	var entries := 0
	for tileset in data.get("tilesets", {}):
		if key.search(tileset) == null:
			return _bad_key("$.tilesets", tileset)
		var record: Dictionary = data.tilesets[tileset]
		if record.has("backdrop"):
			pack._backdrops[tileset] = Color.html(record.backdrop)
		pack._tiles[tileset] = {}
		for tile in record.get("tiles", {}):
			if key.search(tile) == null:
				return _bad_key("$.tilesets.%s.tiles" % tileset, tile)
			entries += 1
			if entries > MAX_ENTRIES:
				return JsonDocument.problem("size", "$.tilesets", "At most %d tiles." % MAX_ENTRIES)
			var image: Variant = _image(reader, record.tiles[tile], "$.tilesets.%s.tiles.%s" % [tileset, tile])
			if image is Dictionary:
				return image
			pack._tiles[tileset][tile] = ImageTexture.create_from_image(image)
	var sprites: Dictionary = data.get("sprites", {})
	for sprite in sprites:
		var record: Dictionary = sprites[sprite]
		var path := str(record.sheet)
		var json: Variant = _bytes(reader, path, "$.sprites.%s.sheet" % sprite)
		if json is Dictionary:
			return json
		var folder := path.get_base_dir()
		var tags: Array = PlayerAnim.TAGS.values() if sprite == "player" else SPRITE_TAGS[sprite]
		var loader := func(image_name: String) -> Variant:
			return _image(reader, folder.path_join(image_name) if not folder.is_empty() else image_name, "$.sprites.%s" % sprite)
		var sheet := Sheet.read(json, loader, tags, int(record.get("texels_per_pixel", 1)))
		if sheet.kind != "ready":
			sheet.path = "$.sprites.%s: %s" % [sprite, sheet.path]
			return sheet
		pack._sprites[sprite] = sheet.sheet
		for notice in sheet.sheet.notices:
			pack.notices.append("%s: %s" % [sprite, notice])
	var hud: Dictionary = data.get("hud", {})
	for part in hud:
		var image: Variant = _image(reader, hud[part], "$.hud.%s" % part)
		if image is Dictionary:
			return image
		pack._hud[part] = ImageTexture.create_from_image(image)
	var sounds: Dictionary = data.get("sounds", {})
	for event in sounds:
		var stream: Variant = _audio(reader, sounds[event], "$.sounds.%s" % event)
		if stream is Dictionary:
			return stream
		pack._sounds[event] = stream
	var music: Dictionary = data.get("music", {})
	for cue in music:
		if key.search(cue) == null:
			return _bad_key("$.music", cue)
		var stream: Variant = _audio(reader, music[cue], "$.music.%s" % cue)
		if stream is Dictionary:
			return stream
		if stream is AudioStreamWAV:
			stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
			stream.loop_end = stream.get_length() * stream.mix_rate
		elif stream is AudioStreamOggVorbis:
			stream.loop = true
		pack._music[cue] = stream
	return {"kind": "ready", "pack": pack}


static func _bad_key(path: String, value: String) -> Dictionary:
	return JsonDocument.problem(
		"schema", path, 'Key "%s" must be 1..64 lowercase letters, digits, dot, underscore or hyphen.' % value.left(64)
	)


static func _bytes(reader: Reader, path: String, where: String) -> Variant:
	if path.split("/").has("..") or path.split("/").has("."):
		return JsonDocument.problem("schema", where, "Paths may not contain . or .. segments.")
	var bytes: Variant = reader.read(path)
	if bytes == null:
		return JsonDocument.problem("file", where, "Missing file %s." % path)
	if bytes.size() > MAX_FILE_BYTES:
		return JsonDocument.problem("size", where, "%s is larger than 16 MB." % path)
	return bytes


static func _image(reader: Reader, path: String, where: String) -> Variant:
	if path.get_extension().to_lower() != "png":
		return JsonDocument.problem("schema", where, "Pictures must be PNG files.")
	var bytes: Variant = _bytes(reader, path, where)
	if bytes is Dictionary:
		return bytes
	var image := Image.new()
	if image.load_png_from_buffer(bytes) != OK:
		return JsonDocument.problem("file", where, "%s is not a readable PNG." % path)
	if image.get_width() > MAX_IMAGE_SIDE or image.get_height() > MAX_IMAGE_SIDE:
		return JsonDocument.problem("size", where, "%s is larger than %d pixels." % [path, MAX_IMAGE_SIDE])
	return image


static func _audio(reader: Reader, path: String, where: String) -> Variant:
	var bytes: Variant = _bytes(reader, path, where)
	if bytes is Dictionary:
		return bytes
	var stream: AudioStream = null
	match path.get_extension().to_lower():
		"wav":
			stream = AudioStreamWAV.load_from_buffer(bytes)
		"ogg":
			stream = AudioStreamOggVorbis.load_from_buffer(bytes)
		_:
			return JsonDocument.problem("schema", where, "Sounds must be WAV or Ogg Vorbis files.")
	if stream == null:
		return JsonDocument.problem("file", where, "%s is not readable audio." % path)
	return stream


func tile(tileset: String, key: String) -> Texture2D:
	return _tiles.get(tileset, {}).get(key)


func backdrop(tileset: String) -> Variant:
	return _backdrops.get(tileset)


func sprite(key: String) -> Sheet:
	return _sprites.get(key)


func hud(key: String) -> Texture2D:
	return _hud.get(key)


func sound(event: String) -> AudioStream:
	return _sounds.get(event)


func music(cue: String) -> AudioStream:
	return _music.get(cue)


func summary() -> String:
	var tiles := 0
	for tileset in _tiles:
		tiles += _tiles[tileset].size()
	return (
		"%s: %d tiles, %d sprites, %d sounds, %d music cues"
		% [name, tiles, _sprites.size(), _sounds.size(), _music.size()]
	)
