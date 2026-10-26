class_name PlayerMotion
extends RefCounted
## One fixed player update with integer 8.8 positions and velocity. The
## course clock calls step() once per update; frame time never scales motion.
##
## Buttons are one byte: 1 right, 2 left, 4 down, 8 up, 64 B (pogo and
## swing), 128 A (jump). Pogo starts with Down+B in the air and continues
## while B is held. `velocity_up` is a 16-bit word, positive upward.
## Object contacts are dictionaries: position and radius (integer pixels),
## harmful, optional enable flags and an optional hit callback.
enum State {
	GROUNDED = 0,
	AIRBORNE = 1,
	POGO = 2,
	CLIMBING = 3,
	SWING = 4,
	HURT = 5,
	PIT = 6,
	DEAD = 7,
	CLEAR = 8
}
const Terrain = preload("res://src/course/course_terrain.gd")
const VerticalTransition = preload("res://src/game/vertical_transition.gd")
const WALK := 0x180
const JUMP := 0x4BB
const POGO := 0x5A8
const GRAVITY := 0x33
const RELEASE_THRESHOLD := 0x42D
const PUSH_DELAY := 16
const SPIKES := 9  # Class-3 metatile ID high nibble: solid, hurts.
const WATER := 10  # Class-3 metatile ID high nibble: a pit near the bottom.
const ANIM_IDLE := 0
const ANIM_WALK := 1
const ANIM_AIR := 2
const ANIM_CROUCH := 3
const ANIM_CLIMB := 4
const ANIM_HURT := 5
const ANIM_POGO := 6
const ANIM_PUSH := 7
const ANIM_LAND := 8
const ANIM_SWING := 9
const ANIM_SWING_MISS := 10
var x: int = 0
var y: int = 0
var velocity_up: int = 0
var state: State = State.GROUNDED
var animation: int = ANIM_IDLE
var object_contacts: Array[Dictionary] = []
var invulnerability := 0
var health := 0
var previous_buttons: int = 0
var spawn_direction := 1
var max_health := 0
var facing_right := false
var section: int = 0
var camera_x := 0
var camera_recentered := false
var transition: VerticalTransition
var climb_grabbed := false
var climb_camera_direction := 0
var climb_released := false
var section_changed := false
var animation_frozen := false
var animation_tick := true
var animation_timer_reset := false
var pogo_impact := false
var sound_requests: Array[int] = []
var swing_direction := 0
var swing_loops := 0
var swing_check := false
var swing_failed := false
var retry_requested := false
var deferred_state := 0
var death_falling := false
var updates: int = 0
var animation_counter_write := Vector2i(-1, -1)
var _push_timer: int = PUSH_DELAY
var _wall_hit := false
var _death_started := false
var _vertical_blocked := false
var _pogo_contact := false
var _descending := false
var _terrain: Terrain


func _init(terrain: Terrain) -> void:
	_terrain = terrain
	transition = VerticalTransition.new(terrain)
	var entry: Dictionary = terrain.definition.value("entry")
	x = int(entry.x) * 256
	y = int(entry.y) * 256
	section = entry.section
	camera_x = entry.camera_x
	health = int(terrain.definition.value("hud").health)
	max_health = health


static func sanitize(buttons: int) -> int:
	if (buttons & 3) == 3 or (buttons & 12) == 12:
		return buttons & 0xF0
	return buttons & 255


func step(buttons: int, rendered_step: int = -1, rendered_timer: int = -1) -> void:
	pogo_impact = false
	sound_requests.clear()
	swing_check = false
	swing_failed = false
	climb_grabbed = false
	climb_camera_direction = 0
	climb_released = false
	section_changed = false
	camera_recentered = false
	_descending = false
	_vertical_blocked = false
	animation_tick = true
	animation_timer_reset = false
	animation_counter_write = Vector2i(-1, -1)
	if transition.active:
		previous_buttons = sanitize(buttons)
		animation_tick = transition.tick < VerticalTransition.SCROLL_TICKS
		y = (y + transition.advance() * 256) & 65535
		return
	if invulnerability > 0 and invulnerability < 128:
		invulnerability -= 1
	var held := sanitize(buttons)
	var pressed := sanitize(held & ~previous_buttons)
	previous_buttons = held
	var handled := true
	match state:
		State.SWING:
			assert(
				rendered_step >= 0 and rendered_timer >= 0, "Swing requires fixed renderer counters"
			)
			_swing(held, rendered_step, rendered_timer)
		State.CLIMBING:
			_climbing(held, pressed, rendered_timer)
		State.CLEAR:
			pass
		State.DEAD:
			_death_step()
		State.HURT:
			_hurt(held)
		_:
			handled = false
	if handled:
		updates += 1
		return
	var pit_dispatch := state == State.PIT
	var airborne_dispatch := state != State.GROUNDED and not pit_dispatch
	var push_check := false
	if airborne_dispatch:
		_push_timer = PUSH_DELAY
	if state == State.POGO:
		if (held & 64) != 0:
			held |= 128
		if (held & 128) == 0:
			state = State.AIRBORNE
	if pit_dispatch:
		if not _falling():
			if (held & 0x44) == 0x44:
				animation = ANIM_POGO
			elif animation != ANIM_PUSH or (held & 3) != swing_direction:
				animation = ANIM_AIR
		if (y >> 8) >= 0xD0:
			retry_requested = true
			state = State.GROUNDED
			deferred_state = 0
			updates += 1
			return
	elif state == State.GROUNDED:
		_falling()
		if state == State.GROUNDED:
			if animation == ANIM_PUSH and (pressed & 64) != 0:
				animation = ANIM_SWING
				state = State.SWING
			elif (pressed & 128) != 0:
				velocity_up = JUMP
				state = State.AIRBORNE
				airborne_dispatch = true
				if _airborne(held):
					_land(held)
			else:
				_grounded_animation(held)
				push_check = (held & 3) != 0 and (held & 4) == 0
	else:
		if _airborne(held):
			_land(held)
	if state == State.AIRBORNE or (state == State.HURT and not _vertical_blocked):
		if (held & 0x44) == 0x44:
			animation = ANIM_POGO
		elif animation != ANIM_PUSH:
			animation = ANIM_AIR
	_wall_hit = false
	if push_check or animation != ANIM_CROUCH or state != State.GROUNDED:
		if (held & 1) != 0:
			var before_x := x >> 8
			x += WALK
			facing_right = true
			_wall_hit = _horizontal_contact(1, before_x)
		elif (held & 2) != 0:
			var before_x := x >> 8
			x -= WALK
			facing_right = false
			_wall_hit = _horizontal_contact(-1, before_x)
	if push_check:
		_update_push(held)
	if airborne_dispatch:
		if animation == ANIM_PUSH and not _vertical_blocked and not _wall_hit:
			animation = ANIM_AIR
		_try_grab(held)
		if _descending and (y >> 8) >= 0xE0 and section + 1 < _terrain.section_count():
			camera_x = (camera_x + 128) & ~255
			camera_recentered = true
			_begin_vertical(1)
	updates += 1


func _try_grab(held: int) -> void:
	if (held & 8) == 0:
		return
	var ix := x >> 8
	var iy := y >> 8
	var probes := [Vector2i(0, 0), Vector2i(0, -12), Vector2i(8, 0), Vector2i(8, -12)]
	var classes: Array[int] = []
	for probe in probes:
		if _solid(ix + probe.x, iy + probe.y):
			return
		classes.append(_terrain.collision_at(section, ix + probe.x, iy + probe.y))
	for index in range(3, -1, -1):
		if ((ix + (8 if index >= 2 else 0)) & 15) >= 8 or classes[index] != 2:
			continue
		var aligned_x := (ix & ~15) + (16 if index >= 2 else 0)
		x = aligned_x * 256 + (x & 255)
		var pair := index & 2
		if classes[pair] != classes[pair + 1]:
			var aligned_y := (iy & 0xF0) + 8 - (16 if (index & 1) != 0 else 0)
			y = ((aligned_y & 255) * 256) + (y & 255)
		state = State.CLIMBING
		animation = ANIM_CLIMB
		animation_frozen = false
		climb_grabbed = true
		climb_camera_direction = 1 if index >= 2 else 2
		return


func _climbing(held: int, pressed: int, rendered_timer: int) -> void:
	_push_timer = PUSH_DELAY
	if (held & 12) == 0:
		if (pressed & 128) != 0:
			_release_climb()
		else:
			animation_frozen = true
		return
	animation_frozen = false
	if rendered_timer >= 0 and (rendered_timer & 127) == 0:
		sound_requests.append(0x12)
	velocity_up = WALK
	var direction := -1 if (held & 8) != 0 else 1
	y = (y + direction * velocity_up) & 65535
	var center_class := _terrain.collision_at(section, x >> 8, y >> 8)
	_collide(Vector2i(0, direction))
	if center_class != 2:
		_release_climb()
		return
	if (direction == -1 and (y >> 8) < 0x39) or (direction == 1 and (y >> 8) >= 0xE0):
		_begin_vertical(direction)


func _begin_vertical(direction: int) -> void:
	if transition.begin(section, camera_x, direction):
		section = transition.target_section
		section_changed = true
		animation_tick = false
		if direction == 1:
			y = 0xE600 | (y & 255)


func _release_climb() -> void:
	state = State.GROUNDED
	velocity_up = 0
	climb_released = true


func _land(held: int) -> void:
	if animation == ANIM_PUSH or state == State.SWING:
		state = State.GROUNDED
		return
	if (
		_pogo_contact
		and (state == State.POGO or (held & 4) != 0)
		and (held & 64) != 0
	):
		pogo_impact = true
		sound_requests.append(0x11)
		velocity_up = POGO
		animation = ANIM_POGO
		state = State.POGO
	else:
		sound_requests.append(0x10)
		animation = ANIM_LAND
		state = State.GROUNDED


func _grounded_animation(held: int) -> void:
	if (held & 7) == 0:
		if animation != ANIM_LAND:
			animation = ANIM_IDLE
		_push_timer = PUSH_DELAY
	elif (held & 4) != 0:
		animation = ANIM_CROUCH
		_push_timer = PUSH_DELAY


func _update_push(held: int) -> void:
	if _wall_hit:
		if animation == ANIM_PUSH:
			return
		_push_timer -= 1
		if _push_timer == 0:
			swing_direction = held & 3
			animation = ANIM_PUSH
			return
	else:
		_push_timer = PUSH_DELAY
	animation = ANIM_WALK


func _swing(held: int, rendered_step: int, rendered_timer: int) -> void:
	_airborne(held)
	if animation == ANIM_SWING_MISS:
		if rendered_step == 0 and rendered_timer == 0:
			swing_loops -= 1
			if swing_loops == 0:
				state = State.GROUNDED
				_push_timer = PUSH_DELAY
		return
	if rendered_step == 6:
		state = State.GROUNDED
		if (held & swing_direction) != 0:
			animation = ANIM_PUSH
		else:
			_push_timer = PUSH_DELAY
		return
	if rendered_step != 2 or rendered_timer != 0:
		return
	swing_check = true
	sound_requests.append(0x13)
	for contact in object_contacts:
		if not contact.get("horizontal_enabled", true):
			continue
		var position: Vector2i = contact.position
		var radius: Vector2i = contact.radius
		if absi((x >> 8) - position.x) > radius.x or absi((y >> 8) - position.y) >= radius.y:
			continue
		if invulnerability != 0:
			continue
		if contact.harmful:
			_harmful_contact(contact)
		break
	animation = ANIM_SWING_MISS
	swing_loops = 5
	swing_failed = true
	sound_requests.append(0x18)


func _falling() -> bool:
	_descending = true
	if (velocity_up >> 8) != 0xF4:
		velocity_up = (velocity_up - GRAVITY) & 65535
	var previous_y := y >> 8
	y = (y - velocity_up) & 65535
	var hit := _vertical_contact(true, previous_y)
	if hit:
		velocity_up = 0
	elif state == State.GROUNDED:
		state = State.AIRBORNE
	return hit


func _airborne(held: int) -> bool:
	var hit := false
	if (velocity_up & 32768) != 0:
		hit = _falling()
	elif (
		state != State.POGO
		and state != State.HURT
		and velocity_up < RELEASE_THRESHOLD
		and (held & 128) == 0
	):
		velocity_up = 0
		y &= 0xFF00
		hit = _falling()
	else:
		var previous_y := y >> 8
		y = (y - velocity_up) & 65535
		hit = _vertical_contact(false, previous_y)
		if hit:
			velocity_up = 0
			y &= 0xFF00
			hit = _falling()
		else:
			velocity_up = (velocity_up - GRAVITY) & 65535
	return hit


func finish_update() -> void:
	if deferred_state != 0:
		if deferred_state != State.HURT or invulnerability == 0:
			state = deferred_state as State
		deferred_state = 0


func _solid(px: int, py: int, probe: int = -1) -> bool:
	if px < 0:
		return false
	if py < 0:
		return true
	if py >= 256:
		return false
	var collision: int = _terrain.collision_at(section, px, py)
	if collision == 1:
		return true
	if collision != 3:
		return false
	var group: int = _terrain.metatile_at(section, px, py) >> 4
	if group == SPIKES and invulnerability == 0:
		if probe >= 0 and probe % 3 == 1 and (animation != ANIM_POGO or probe == 10):
			deferred_state = State.HURT
	elif group == WATER and (y >> 8) >= 0xD0:
		deferred_state = State.PIT
	return group == SPIKES


func _collide(direction: Vector2i) -> bool:
	var ix := x >> 8
	var iy := y >> 8
	var hit := false
	if direction.x != 0:
		var first := 0 if direction.x > 0 else 3
		for index in range(3):
			hit = _solid(ix + direction.x * 10, iy + 11 - index * 11, first + index) or hit
	else:
		var first := 6 if direction.y > 0 else 9
		_pogo_contact = (_terrain.collision_at(section, ix, iy + direction.y * 12) & 1) != 0
		for index in range(3):
			hit = _solid(ix - 9 + index * 9, iy + direction.y * 12, first + index) or hit
	if not hit:
		return false
	if direction.x == 1:
		x -= ((ix + 10) & 15) * 256
	elif direction.x == -1:
		x += (16 - ((ix - 10) & 15)) * 256
	elif direction.y == 1:
		y -= ((iy + 12) & 15) * 256
	else:
		y += (16 - ((iy - 12) & 15)) * 256
	y &= 65535
	return true


func _vertical_contact(down: bool, previous_y: int) -> bool:
	var hit := false
	var correction := 0
	var pogo_hit := false
	for contact in object_contacts:
		if not contact.get("vertical_enabled", true):
			continue
		var position: Vector2i = contact.position
		var radius: Vector2i = contact.radius
		var dx := absi((x >> 8) - position.x)
		var dy := absi((y >> 8) - position.y)
		if contact.harmful and animation == ANIM_CROUCH:
			dy += 8
		if dx >= radius.x or dy > radius.y:
			continue
		if contact.harmful and invulnerability != 0:
			continue
		hit = true
		correction = radius.y - dy
		if not pogo_hit and down and (velocity_up & 0x8000) != 0 and animation == ANIM_POGO:
			pogo_hit = true
			if contact.has("hit"):
				contact.hit.call()
		elif contact.harmful:
			_harmful_contact(contact)
	if hit:
		y = (y + (-correction if down else correction + 1) * 256) & 65535
	var direction := Vector2i.DOWN if down else Vector2i.UP
	if previous_y != (y >> 8):
		direction = Vector2i.UP if previous_y > (y >> 8) else Vector2i.DOWN
	var terrain_hit := _collide(direction)
	_pogo_contact = _pogo_contact or pogo_hit
	_vertical_blocked = hit or terrain_hit
	return _vertical_blocked


func _horizontal_contact(direction: int, before: int) -> bool:
	var hit := false
	spawn_direction = 1 if direction > 0 else 2
	for contact in object_contacts:
		if not contact.get("horizontal_enabled", true):
			continue
		var position: Vector2i = contact.position
		var radius: Vector2i = contact.radius
		var dx := absi((x >> 8) - position.x)
		var dy := absi((y >> 8) - position.y)
		if contact.harmful and animation == ANIM_CROUCH:
			dy += 8
		if dx > radius.x or dy >= radius.y:
			continue
		if invulnerability != 0:
			continue
		x -= direction * mini(radius.x - dx, 12) * 256
		if contact.harmful:
			_harmful_contact(contact)
		hit = true
		break
	var probe_direction := direction
	if hit and before != (x >> 8):
		probe_direction = 1 if before > (x >> 8) else -1
	spawn_direction = 1 if probe_direction > 0 else 2
	return _collide(Vector2i(probe_direction, 0)) or hit


func _harmful_contact(_contact: Dictionary) -> void:
	state = State.HURT


func _apply_damage() -> void:
	health = maxi(0, health - 1)


func _hurt(held: int) -> void:
	if invulnerability == 0:
		sound_requests.append(0x14)
		velocity_up = 0x169
		animation_counter_write = Vector2i.ZERO
		invulnerability = 0x46
		_apply_damage()
		if health == 0:
			_death_started = false
			state = State.DEAD
			animation = ANIM_HURT
			_death_step()
			return
	_airborne(held)
	if (held & 0x44) == 0x44:
		if animation != ANIM_POGO:
			animation_counter_write = Vector2i(0, 128)
	elif animation != ANIM_PUSH:
		animation_counter_write = Vector2i.ZERO
	var knockback := 0x100
	if invulnerability == 0x3C:
		state = State.GROUNDED
		knockback = WALK
	animation = ANIM_HURT
	var direction := -1 if facing_right else 1
	var before_x := x >> 8
	x += direction * knockback
	_horizontal_contact(direction, before_x)


func reset_death_phase() -> void:
	_death_started = false


func _death_step() -> void:
	if not _death_started:
		_death_started = true
		death_falling = false
		velocity_up = 0x400
		animation = ANIM_HURT
	if not death_falling:
		y = (y - velocity_up) & 65535
		velocity_up = (velocity_up - GRAVITY) & 65535
		if (velocity_up & 0x8000) != 0:
			death_falling = true
			velocity_up = 0
			return
	else:
		velocity_up = (velocity_up - GRAVITY) & 65535
		y = (y - velocity_up) & 65535
		if (y >> 8) >= 224:
			retry_requested = true
			state = State.GROUNDED
			return
	x += 0x80
