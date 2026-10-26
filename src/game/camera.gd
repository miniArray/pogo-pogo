class_name CourseCamera
extends RefCounted
## Horizontal follow camera in integer pixels. It centers the player, locks at
## absent screens and course edges, and nudges the player inside a locked edge.
const Terrain = preload("res://src/course/course_terrain.gd")
const WIDTH := 8
const CENTER := 128
var x := 0
var map_index := 0
var direction := 0
var _terrain: Terrain


func _init(terrain: Terrain, section: int = 0, column: int = 0) -> void:
	_terrain = terrain
	x = column * 256
	map_index = section * WIDTH + column


func follow(player_x: int) -> int:
	if (direction & 3) == 0:
		return player_x
	direction = 1
	var delta := ((player_x >> 8) - x - CENTER) & 255
	if delta == 0:
		return player_x
	if delta >= 128:
		delta -= 256
		direction = 2
	var candidate := (x + delta) & 65535
	var page := candidate >> 8
	var carry := ((x & 255) + (delta & 255)) >> 8
	var index := (map_index + carry - (1 if delta < 0 else 0)) & 255
	if delta > 0:
		var next := (index + 1) & 255
		if ((page + 1) & 255) == WIDTH or next == 0 or _screen(next) == 255:
			x = page * 256
			if ((player_x >> 8) & 255) > 240:
				player_x = (player_x & ~0xFF00) | (240 << 8)
		else:
			x = candidate
		map_index = index
	elif page >= 128 or _screen(index) == 255:
		x &= 0xFF00
		if ((player_x >> 8) & 255) <= 16:
			player_x = (player_x & ~0xFF00) | (16 << 8)
	else:
		x = candidate
		map_index = index
	return player_x


func _screen(index: int) -> int:
	return _terrain.screen_id(index / WIDTH, index % WIDTH)
