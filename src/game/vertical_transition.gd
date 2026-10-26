class_name VerticalTransition
extends RefCounted
## A fixed 60-update scroll between vertically adjacent sections. The player
## moves in whole pixels only; fractions and vitals are untouched. A transition
## starts only from an odd, page-aligned camera column with a present target.
enum Status { IDLE, SCROLLING, COMPLETED, REJECTED }
enum Rejection { NONE, UNALIGNED_CAMERA, ABSENT_ROOM }
const Terrain = preload("res://src/course/course_terrain.gd")
const SCROLL_TICKS := 60
var status: Status = Status.IDLE
var rejection: Rejection = Rejection.NONE
var source_section := 0
var target_section := 0
var column := 0
var direction := 0
var tick := 0
## View displacement over a 240-row strip per section, and the player's
## accumulated integer displacement.
var camera_offset_y := 0
var player_offset_y := 0
var active: bool:
	get:
		return status == Status.SCROLLING

var _terrain: Terrain


func _init(terrain: Terrain) -> void:
	_terrain = terrain


func begin(section: int, camera_x: int, vertical_direction: int) -> bool:
	assert(vertical_direction == -1 or vertical_direction == 1)
	if active:
		return false
	source_section = section
	target_section = section + vertical_direction
	column = camera_x >> 8
	direction = vertical_direction
	tick = 0
	camera_offset_y = 0
	player_offset_y = 0
	rejection = Rejection.NONE
	status = Status.REJECTED
	if (camera_x & 255) != 0 or (column & 1) == 0:
		rejection = Rejection.UNALIGNED_CAMERA
		return false
	if _terrain.screen_id(target_section, column) == 255:
		rejection = Rejection.ABSENT_ROOM
		return false
	status = Status.SCROLLING
	return true


func advance() -> int:
	## Return this tick's integer player-Y displacement.
	assert(active)
	if tick == SCROLL_TICKS:
		status = Status.COMPLETED
		return 0
	var displacement := direction
	if (tick & 1) == 0:
		camera_offset_y += direction * 8
		var wrap_tick := 12 if direction == -1 else 46
		if tick != wrap_tick:
			displacement -= direction * 8
	player_offset_y += displacement
	tick += 1
	return displacement
