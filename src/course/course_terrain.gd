class_name CourseTerrain
extends RefCounted
## Collision and screen lookups for one course. Sections are rows of eight
## 256-pixel screens; each screen is 16 x 16 metatiles of 16 pixels.
## Rows 240..255 of every screen are drawn but never collide.
const Definition = preload("res://src/course/course_definition.gd")
const HUD_HEIGHT := 48  # Status band over world rows 0..47.
const PLAYFIELD_HEIGHT := 192  # World rows 48..239 are the playfield.
var definition: Definition


func _init(course: Definition) -> void:
	definition = course


func screen_id(row: int, column: int) -> int:
	return definition.screen_id(row, column)


func section_count() -> int:
	return definition.section_count()


func metatile_at(section: int, x: int, y: int) -> int:
	var id := screen_id(section, x >> 8)
	if id == 255 or y < 0 or y >= 256:
		return 0
	return definition.cell(id, (x & 255) >> 4, y >> 4)


func collision_at(section: int, x: int, y: int) -> int:
	if screen_id(section, x >> 8) == 255 or y < 0 or y >= 240:
		return 0
	return definition.collision_of(metatile_at(section, x, y))
