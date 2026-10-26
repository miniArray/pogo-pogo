class_name PlayerAnimation
extends RefCounted
## Player animation counters, advanced once per game update. They are game
## state: the swing reads `step` and `timer` to decide when it connects and
## ends, and climbing plays its sound when the timer wraps. Pictures come from
## the asset pack and never feed back into these counters.
const Motion = preload("res://src/game/player_motion.gd")
## Animation ID -> Vector2i(last step, ticks per step - 1).
const TIMING := {
	0: Vector2i(0, 0),
	1: Vector2i(3, 8),
	2: Vector2i(0, 0),
	3: Vector2i(4, 4),
	4: Vector2i(1, 8),
	5: Vector2i(0, 0),
	6: Vector2i(2, 12),
	7: Vector2i(1, 8),
	8: Vector2i(1, 4),
	9: Vector2i(6, 4),
	10: Vector2i(1, 2),
}
## Pack tag name for each animation ID.
const TAGS := {
	0: "idle",
	1: "walk",
	2: "air",
	3: "crouch",
	4: "climb",
	5: "hurt",
	6: "pogo",
	7: "push",
	8: "land",
	9: "swing",
	10: "swing_miss",
}
var id := 0
var step := 0  # Bit 7 enables the loop target.
var timer := 0  # Bit 7 freezes the animation.
var loop_target := 0
var held_ticks := 0  # Updates since `id` last changed; for single-picture loops.
var _rendered_id := 0


static func timing(animation: int) -> Vector2i:
	return TIMING.get(animation, Vector2i.ZERO)


func prepare(
	animation_id: int,
	pogo_impact: bool = false,
	climbing_frozen: bool = false,
	timer_reset: bool = false
) -> void:
	if timer_reset:
		timer = 0
	if pogo_impact:
		step = 0x81
		timer = 0
		loop_target = 2
	elif animation_id == Motion.ANIM_IDLE or animation_id == Motion.ANIM_AIR:
		step = 0
		timer = 0
	elif animation_id != id:
		step = 0
		timer = 0
		if animation_id == Motion.ANIM_CROUCH or animation_id == Motion.ANIM_LAND:
			step = 0x80
			loop_target = 1  # Loops skip the entry pose.
		elif animation_id == Motion.ANIM_POGO:
			timer = 0x80  # Held compressed while airborne.
	id = animation_id
	if id == Motion.ANIM_CLIMB:
		timer = (timer | 0x80) if climbing_frozen else (timer & 0x7F)


func advance(
	animation_id: int,
	pogo_impact: bool = false,
	visible: bool = true,
	climbing_frozen: bool = false,
	timer_reset: bool = false
) -> void:
	prepare(animation_id, pogo_impact, climbing_frozen, timer_reset)
	if id != _rendered_id:
		held_ticks = 0
	else:
		held_ticks = (held_ticks + 1) & 0x7FFFFFFF
	_rendered_id = id
	if not visible or (timer & 0x80) != 0:
		return
	var record := timing(id)
	var old_timer := timer
	timer = (timer + 1) & 255
	if old_timer != record.y:
		return
	timer = 0
	var old_step := step & 127
	step = (step + 1) & 255
	if old_step == record.x:
		step = (0x80 | loop_target) if (step & 0x80) != 0 else 0


func write_counters(value: Vector2i) -> void:
	## Explicit step/timer writes that the motion requests during hurt.
	if value.x >= 0:
		step = value.x
		timer = value.y


## Picture index for a pack tag with `count` pictures. A tag with exactly one
## picture per step shows the step's picture. Other counts spread over the
## loop in update ticks; single-step loops cycle by time held.
func picture(count: int) -> int:
	if count <= 1:
		return 0
	var record := timing(id)
	var steps := record.x + 1
	if count == steps:
		return clampi(step & 127, 0, count - 1)
	var span := record.y + 1
	var total := steps * span
	if total <= 1:
		return (held_ticks / 8) % count
	var position := clampi((step & 127) * span + (timer & 127), 0, total - 1)
	return position * count / total
