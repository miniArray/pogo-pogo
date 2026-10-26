class_name CourseDefinition
extends RefCounted
## One validated, immutable course document. `schema/course.schema.json` is the
## structural contract; this file adds the cross-reference checks the schema
## cannot express. Accessors return deep copies.
const JsonDocument = preload("res://src/shared/json_document.gd")
const MAX_BYTES := 2 * 1024 * 1024
const SCHEMA_PATH := "res://schema/course.schema.json"
const SPIKES := 9  # Class-3 metatiles with this ID high nibble hurt the player.
const WATER := 10  # Class-3 metatiles with this ID high nibble are a pit at the bottom.
var _data: Dictionary
var _screens := {}


## Returns {kind: "ready", definition} or a problem {kind, path, message}.
static func load_bytes(bytes: PackedByteArray) -> Dictionary:
	var document := JsonDocument.read(bytes, SCHEMA_PATH, MAX_BYTES)
	if document.kind != "ready":
		return document
	var error := _semantics(document.data)
	if not error.is_empty():
		return error
	var definition := CourseDefinition.new()
	definition._data = document.data
	for screen in document.data.terrain.screens:
		definition._screens[int(screen.id)] = PackedInt32Array(screen.cells)
	return {"kind": "ready", "definition": definition}


static func load_path(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return JsonDocument.problem("file", "$", "No course file at %s." % path)
	return load_bytes(FileAccess.get_file_as_bytes(path))


static func problem(path: String, message: String) -> Dictionary:
	return JsonDocument.problem("semantics", path, message)


static func _semantics(data: Dictionary) -> Dictionary:
	var terrain: Dictionary = data.terrain
	var screens := {}
	for index in range(terrain.screens.size()):
		var id := int(terrain.screens[index].id)
		if screens.has(id):
			return problem("$.terrain.screens[%d].id" % index, "Screen IDs must be unique.")
		screens[id] = terrain.screens[index].cells
	for index in range(terrain.grid.size()):
		var id := int(terrain.grid[index])
		if id != 255 and not screens.has(id):
			return problem("$.terrain.grid[%d]" % index, "Screen %d is not defined." % id)
	var used := {}
	for id in terrain.grid:
		if int(id) != 255:
			used[int(id)] = true
	for index in range(terrain.screens.size()):
		var screen: Dictionary = terrain.screens[index]
		if not used.has(int(screen.id)):
			continue
		for cell in range(256):
			var metatile := int(screen.cells[cell])
			if int(terrain.metatiles[metatile].collision) != 3:
				continue
			if metatile >> 4 not in [SPIKES, WATER]:
				return problem(
					"$.terrain.screens[%d].cells[%d]" % [index, cell],
					"Class-3 metatiles must use IDs 0x90..0x9F (spikes) or 0xA0..0xAF (water)."
				)
	var indices := {}
	var goals := 0
	for index in range(data.placements.size()):
		var placement: Dictionary = data.placements[index]
		var path := "$.placements[%d]" % index
		if indices.has(int(placement.index)):
			return problem(path + ".index", "Placement indices must be unique.")
		indices[int(placement.index)] = true
		if _screen(terrain, int(placement.section), int(placement.x) >> 8) == 255:
			return problem(path, "Placement is outside every present screen.")
		if placement.type == "goal":
			goals += 1
	if goals == 0:
		return problem("$.placements", "A course needs at least one goal.")
	for key in ["entry", "retry"]:
		var error := _destination(terrain, data[key], "$." + key)
		if not error.is_empty():
			return error
	var checkpoint: Dictionary = data.checkpoint
	if _screen(terrain, int(checkpoint.section), int(checkpoint.page)) == 255:
		return problem("$.checkpoint", "The checkpoint page is not a present screen.")
	return _destination(terrain, checkpoint.destination, "$.checkpoint.destination")


static func _destination(terrain: Dictionary, record: Dictionary, path: String) -> Dictionary:
	var section := int(record.section)
	var camera_x := int(record.camera_x)
	var x := int(record.x)
	if _screen(terrain, section, x >> 8) == 255 or _screen(terrain, section, camera_x >> 8) == 255:
		return problem(path, "Destination must be in a present screen.")
	if x < camera_x or x >= camera_x + 256:
		return problem(path, "Destination must be inside its 256-pixel camera view.")
	return {}


static func _screen(terrain: Dictionary, row: int, column: int) -> int:
	if row < 0 or row >= int(terrain.rows) or column < 0 or column >= int(terrain.columns):
		return 255
	return int(terrain.grid[row * int(terrain.columns) + column])


func canonical() -> String:
	return JSON.stringify(_data, "  ", true, true) + "\n"


func id() -> String:
	return str(_data.level.id)


func value(key: String) -> Variant:
	var result: Variant = _data.get(key)
	return result.duplicate(true) if result is Dictionary or result is Array else result


func screen_id(row: int, column: int) -> int:
	var terrain: Dictionary = _data.terrain
	if row < 0 or row >= terrain.rows or column < 0 or column >= terrain.columns:
		return 255
	return terrain.grid[row * terrain.columns + column]


func section_count() -> int:
	return int(_data.terrain.rows)


func cell(screen: int, mx: int, my: int) -> int:
	return _screens[screen][my * 16 + mx]


func collision_of(metatile: int) -> int:
	return int(_data.terrain.metatiles[metatile].collision)


func tile_of(metatile: int) -> String:
	return str(_data.terrain.metatiles[metatile].tile)


func tileset(section: int) -> String:
	return str(_data.sections[section].tileset)
