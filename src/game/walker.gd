class_name Walker
extends RefCounted
## A ground enemy that paces back and forth. It turns at walls and ledges,
## falls when unsupported, hurts the player on contact and is knocked out by
## a pogo bounce. Integer 8.8 positions; one call per game update.
enum Status { WAITING, LIVE, DEFEATED, REMOVED }
const Terrain = preload("res://src/course/course_terrain.gd")
const Definition = preload("res://src/course/course_definition.gd")
const SPEED := 0x100
const GRAVITY := 0x40
const MAX_FALL := 0x400
const KNOCKOUT_JUMP := 0x300
const HALF_WIDTH := 10
const HALF_HEIGHT := 12
const RADIUS := Vector2i(12, 16)
const ACTIVATION_MARGIN := 32
var placement: Dictionary
var status: Status = Status.WAITING
var x := 0
var y := 0
var velocity_up := 0
var direction := -1
var ticks := 0
var was_visible := false
var _terrain: Terrain


func _init(terrain: Terrain, record: Dictionary) -> void:
	_terrain = terrain
	placement = record


func key() -> String:
	return "walker"


func reset() -> void:
	status = Status.WAITING
	was_visible = false


func try_spawn(camera_x: int, player_x: int) -> void:
	## Spawn when the placement enters the logical window from outside it.
	var inside := _in_window(int(placement.x), camera_x, 0)
	if status == Status.WAITING and inside and not was_visible:
		x = int(placement.x) * 256
		y = int(placement.y) * 256
		velocity_up = 0
		direction = -1 if int(placement.x) > (player_x >> 8) else 1
		ticks = 0
		status = Status.LIVE
	was_visible = inside


func advance(camera_x: int) -> void:
	if status == Status.LIVE:
		ticks += 1
		_walk()
		if not _in_window(x >> 8, camera_x, ACTIVATION_MARGIN):
			status = Status.WAITING
	elif status == Status.DEFEATED:
		ticks += 1
		velocity_up = (velocity_up - GRAVITY) & 65535
		y = (y - _signed(velocity_up)) & 0xFFFFFF
		if (y >> 8) >= 272:
			status = Status.REMOVED


func contact(hit: Callable) -> Dictionary:
	return {
		"position": Vector2i(x >> 8, y >> 8),
		"radius": RADIUS,
		"harmful": true,
		"vertical_enabled": true,
		"horizontal_enabled": true,
		"hit": hit,
	}


func knock_out() -> void:
	if status != Status.LIVE:
		return
	status = Status.DEFEATED
	velocity_up = KNOCKOUT_JUMP
	ticks = 0


func _walk() -> void:
	var px := x >> 8
	var py := y >> 8
	if not _supported(px, py):
		velocity_up = maxi(_signed(velocity_up) - GRAVITY, -MAX_FALL) & 65535
		y -= _signed(velocity_up)
		py = y >> 8
		if _supported(px, py):
			y = (((py + HALF_HEIGHT + 1) & ~15) - HALF_HEIGHT - 1) * 256
			velocity_up = 0
		return
	var ahead := px + direction * HALF_WIDTH
	if _solid(ahead, py) or not _solid(ahead, py + HALF_HEIGHT + 1):
		direction = -direction
		return
	x += direction * SPEED


func _supported(px: int, py: int) -> bool:
	return _solid(px, py + HALF_HEIGHT + 1)


func _solid(px: int, py: int) -> bool:
	var collision := _terrain.collision_at(int(placement.section), px, py)
	if collision == 1:
		return true
	if collision == 3:
		return _terrain.metatile_at(int(placement.section), px, py) >> 4 == Definition.SPIKES
	return false


static func _in_window(px: int, camera_x: int, margin: int) -> bool:
	return px >= camera_x - margin and px < camera_x + 256 + margin


static func _signed(value: int) -> int:
	return value - 65536 if value >= 32768 else value
