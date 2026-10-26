class_name CourseGame
extends RefCounted
## One playable course: player, camera, actors, pickups, checkpoint, retries
## and the score. Pure game state with no nodes, so tests and the scene run
## the same updates. Call update() once per fixed game update.
const Definition = preload("res://src/course/course_definition.gd")
const Terrain = preload("res://src/course/course_terrain.gd")
const Motion = preload("res://src/game/player_motion.gd")
const PlayerAnim = preload("res://src/game/player_animation.gd")
const Camera = preload("res://src/game/camera.gd")
const Attempts = preload("res://src/game/attempt_flow.gd")
const WalkerActor = preload("res://src/game/walker.gd")
const GEM_SCORE := 100
const KNOCKOUT_SCORE := 200
const PICKUP_RADIUS := Vector2i(12, 16)
const GOAL_RADIUS := Vector2i(12, 24)
const CLEAR_WAIT := 180
const GAME_OVER_WAIT := 240
## Player sound requests to pack event keys.
const SOUNDS := {0x10: "land", 0x11: "pogo", 0x12: "climb", 0x13: "swing", 0x14: "hurt", 0x18: "swing_miss"}
var definition: Definition
var terrain: Terrain
var motion: Motion
var animation := PlayerAnim.new()
var camera: Camera
var attempts: Attempts
var walkers: Array[WalkerActor] = []
var gems: Array[Dictionary] = []
var goals: Array[Dictionary] = []
var score := 0
var updates := 0
var render_tick := 0
var player_visible := true
var cleared := false
var clear_ticks := 0
var finished := false  # Clear wait done; the host may load the next course.
var game_over_ticks := 0
## Sound and music events from this update, as pack keys.
var events: Array[String] = []
var _collected := {}
var _last_row := 0


func _init(course: Definition) -> void:
	definition = course
	_start()


func _start() -> void:
	terrain = Terrain.new(definition)
	motion = Motion.new(terrain)
	animation = PlayerAnim.new()
	var entry: Dictionary = definition.value("entry")
	camera = Camera.new(terrain, int(entry.section), int(entry.camera_x) >> 8)
	camera.x = int(entry.camera_x)
	attempts = Attempts.new(terrain)
	walkers.clear()
	gems.clear()
	goals.clear()
	for placement in definition.value("placements"):
		match str(placement.type):
			"walker":
				walkers.append(WalkerActor.new(terrain, placement))
			"gem":
				gems.append(placement)
			"goal":
				goals.append(placement)
	score = 0
	cleared = false
	clear_ticks = 0
	finished = false
	game_over_ticks = 0
	_collected.clear()
	_stream()


func restart() -> void:
	_start()


func update(held: int) -> void:
	events.clear()
	updates += 1
	if attempts.phase == Attempts.Phase.GAME_OVER:
		motion.previous_buttons = Motion.sanitize(held)
		game_over_ticks += 1
		if game_over_ticks >= GAME_OVER_WAIT:
			_start()
		_finish(false)
		return
	if attempts.phase != Attempts.Phase.PLAYING:
		_advance_retry(held)
		_finish()
		return
	if cleared:
		motion.previous_buttons = Motion.sanitize(held)
		clear_ticks += 1
		finished = clear_ticks >= CLEAR_WAIT
		_finish(false)
		return
	var was_transition := motion.transition.active
	motion.camera_x = camera.x
	motion.object_contacts = _contacts()
	var state_before := motion.state
	motion.step(held, animation.step, animation.timer)
	for id in motion.sound_requests:
		if SOUNDS.has(id):
			events.append(SOUNDS[id])
	if motion.state == Motion.State.DEAD and state_before != Motion.State.DEAD:
		events.append("defeat")
	if motion.camera_recentered:
		camera.x = motion.camera_x
		camera.map_index = motion.section * Camera.WIDTH + (camera.x >> 8)
	if motion.section_changed:
		_enter_section()
	if was_transition or motion.section_changed:
		camera.map_index = motion.section * Camera.WIDTH + (camera.x >> 8)
		if was_transition and not motion.transition.active:
			motion.spawn_direction = 1
			_stream()
		_finish(false)
		return
	var horizontal := Motion.sanitize(held) & 3
	if (
		horizontal != 0
		and motion.animation != Motion.ANIM_CROUCH
		and motion.state != Motion.State.CLIMBING
	):
		camera.direction = horizontal
	if motion.climb_camera_direction != 0:
		camera.direction = motion.climb_camera_direction
	animation.prepare(
		motion.animation, motion.pogo_impact, motion.animation_frozen, motion.animation_timer_reset
	)
	animation.write_counters(motion.animation_counter_write)
	for walker in walkers:
		if int(walker.placement.section) == motion.section:
			walker.advance(camera.x)
	_pickups()
	motion.x = camera.follow(motion.x)
	if not motion.retry_requested and not motion.transition.active and _below_course():
		motion.retry_requested = true
		motion.state = Motion.State.GROUNDED
	if motion.retry_requested:
		motion.reset_death_phase()
		attempts.begin_retry()
		events.append("retry" if attempts.phase == Attempts.Phase.RETRY else "game_over")
		if attempts.phase == Attempts.Phase.RETRY:
			motion.invulnerability = 1
	_finish()


func _below_course() -> bool:
	## Safety net for an unbounded fall with no section below: retry as a pit.
	## Rows wrap at 256, so only a fall from the bottom band counts, not a
	## jump above row 0.
	var row := motion.y >> 8
	var fell := _last_row >= 0xC0 and _last_row < 0xF0 and row >= 0xF0
	_last_row = row
	return fell and motion.state not in [Motion.State.DEAD, Motion.State.CLIMBING]


func _contacts() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for index in range(walkers.size() - 1, -1, -1):
		var walker := walkers[index]
		if int(walker.placement.section) == motion.section and walker.status == WalkerActor.Status.LIVE:
			result.append(walker.contact(_knock_out.bind(index)))
	return result


func _knock_out(index: int) -> void:
	var walker := walkers[index]
	if walker.status == WalkerActor.Status.LIVE:
		walker.knock_out()
		score += KNOCKOUT_SCORE
		events.append("knockout")


func _pickups() -> void:
	var player := Vector2i(motion.x >> 8, motion.y >> 8)
	if motion.state == Motion.State.DEAD:
		return
	for gem in gems:
		if int(gem.section) != motion.section or _collected.has(int(gem.index)):
			continue
		if _overlaps(player, gem, PICKUP_RADIUS):
			_collected[int(gem.index)] = true
			score += GEM_SCORE
			events.append("gem")
	for goal in goals:
		if int(goal.section) == motion.section and _overlaps(player, goal, GOAL_RADIUS):
			cleared = true
			motion.state = Motion.State.CLEAR
			events.append("clear")
			return


static func _overlaps(player: Vector2i, record: Dictionary, radius: Vector2i) -> bool:
	return absi(player.x - int(record.x)) < radius.x and absi(player.y - int(record.y)) < radius.y


func collected(index: int) -> bool:
	return _collected.has(index)


func _enter_section() -> void:
	for walker in walkers:
		walker.reset()


func _stream() -> void:
	for walker in walkers:
		if int(walker.placement.section) == motion.section:
			walker.try_spawn(camera.x, motion.x)


func _advance_retry(held: int) -> void:
	motion.previous_buttons = Motion.sanitize(held)
	attempts.advance()
	if attempts.phase == Attempts.Phase.GAME_OVER:
		return
	if attempts.elapsed <= attempts.first_wait or attempts.elapsed > attempts.show_tick:
		animation.timer = 0
	if attempts.elapsed == attempts.position_tick:
		motion.x = attempts.spawn.x * 256 + (motion.x & 255)
		motion.y = attempts.spawn.y * 256 + (motion.y & 255)
		motion.section = attempts.section
		camera = Camera.new(terrain, attempts.section, attempts.camera_x >> 8)
		camera.x = attempts.camera_x
		_enter_section()
		motion.object_contacts = []
		motion.spawn_direction = 1
	if attempts.elapsed == attempts.refill_tick:
		motion.health = motion.max_health
		motion.animation = Motion.ANIM_IDLE
	if attempts.elapsed == attempts.camera_tick:
		camera.direction = 1
	if attempts.elapsed == attempts.show_tick:
		_stream()
		motion.reset_death_phase()
		motion.facing_right = false
	if attempts.elapsed == attempts.resume_tick:
		motion.invulnerability = 0
		motion.retry_requested = false
		motion.state = Motion.State.GROUNDED


func _finish(world_finish: bool = true) -> void:
	if world_finish and attempts.phase == Attempts.Phase.PLAYING and not motion.retry_requested:
		_stream()
	if attempts.renderer_advances() and motion.animation_tick:
		render_tick = (render_tick + 1) & 255
	player_visible = (
		attempts.player_present()
		and (motion.invulnerability == 0 or (render_tick & 2) != 0)
	)
	if motion.animation_tick:
		animation.advance(motion.animation, false, player_visible, motion.animation_frozen)
	if attempts.phase == Attempts.Phase.PLAYING and world_finish:
		motion.finish_update()
		if attempts.observe_checkpoint(motion.section, motion.x):
			events.append("checkpoint")


## Compact state for replay fixtures: equal digests mean equal game state.
func digest() -> String:
	var parts := [
		motion.x, motion.y, motion.velocity_up, int(motion.state), motion.animation,
		motion.section, motion.health, motion.invulnerability, camera.x,
		animation.step, animation.timer, attempts.lives, int(attempts.phase), score,
		int(cleared)
	]
	for walker in walkers:
		parts.append_array([int(walker.status), walker.x, walker.y])
	return ",".join(parts.map(func(value): return str(value)))
