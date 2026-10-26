class_name AttemptFlow
extends RefCounted
## Lives, the checkpoint latch and the timed retry after a fall or defeat.
## A retry fades out, moves the player, refills health, then fades back in.
enum Phase { PLAYING, RETRY, GAME_OVER }
const Terrain = preload("res://src/course/course_terrain.gd")
const FIRST_WAIT := 180
const POSITION_TICK := 196
const REFILL_TICK := 202
const SHOW_TICK := 221
const RESUME_TICK := 401
var phase: Phase = Phase.PLAYING
var lives := 2
var elapsed := 0
var deaths := 0
var spawn: Vector2i
var section: int
var camera_x: int
var checkpoint := false
var position_tick := POSITION_TICK
var refill_tick := REFILL_TICK
var camera_tick := REFILL_TICK + 2
var show_tick := SHOW_TICK
var resume_tick := RESUME_TICK
var first_wait := FIRST_WAIT
var _terrain: Terrain


func _init(terrain: Terrain) -> void:
	_terrain = terrain
	lives = int(terrain.definition.value("hud").lives)
	_read_destination(terrain.definition.value("retry"))


func observe_checkpoint(player_section: int, player_x: int) -> bool:
	## Latch the checkpoint when the player reaches its page. True on the first touch.
	var record: Dictionary = _terrain.definition.value("checkpoint")
	if checkpoint:
		return false
	if player_section == int(record.section) and (player_x >> 16) == int(record.page):
		checkpoint = true
		return true
	return false


func _read_destination(record: Dictionary) -> void:
	section = record.section
	camera_x = record.camera_x
	spawn = Vector2i(record.x, record.y)


func begin_retry() -> void:
	if phase != Phase.PLAYING:
		return
	var definition := _terrain.definition
	_read_destination(
		definition.value("checkpoint").destination if checkpoint else definition.value("retry")
	)
	var stream_delay := 2 if checkpoint else 0
	first_wait = FIRST_WAIT
	position_tick = POSITION_TICK
	refill_tick = REFILL_TICK + stream_delay
	camera_tick = refill_tick + 2
	show_tick = SHOW_TICK + stream_delay
	resume_tick = RESUME_TICK + stream_delay
	deaths += 1
	elapsed = 0
	phase = Phase.RETRY if lives > 0 else Phase.GAME_OVER


func advance() -> void:
	if phase != Phase.RETRY:
		return
	elapsed += 1
	if elapsed == refill_tick:
		lives -= 1
	if elapsed == resume_tick:
		phase = Phase.PLAYING


func player_present() -> bool:
	return phase == Phase.PLAYING or (phase == Phase.RETRY and elapsed >= show_tick)


func renderer_advances() -> bool:
	return (
		phase in [Phase.PLAYING, Phase.GAME_OVER]
		or (phase == Phase.RETRY and (elapsed < first_wait or elapsed >= show_tick))
	)


func fade() -> float:
	## Presentation-only opacity of the retry fade.
	if phase != Phase.RETRY or elapsed < first_wait or elapsed >= show_tick:
		return 0.0
	if elapsed < position_tick:
		return float(elapsed - first_wait) / 16.0
	if elapsed < camera_tick:
		return 1.0
	return 1.0 - float(elapsed - camera_tick) / float(show_tick - camera_tick)
