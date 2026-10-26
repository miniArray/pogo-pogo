class_name CourseView
extends Node2D
## Draws one CourseGame into a raster of at least 256 x 240 pixels. Pictures
## come from the asset pack when it has them; anything else is a placeholder
## shape. Drawing reads game state and never changes it.
const Game = preload("res://src/game/course_game.gd")
const Motion = preload("res://src/game/player_motion.gd")
const PlayerAnim = preload("res://src/game/player_animation.gd")
const WalkerActor = preload("res://src/game/walker.gd")
const Pack = preload("res://src/pack/asset_pack.gd")
const Definition = preload("res://src/course/course_definition.gd")
const HUD_HEIGHT := 48
const CELL := 16
const BACKDROP := Color("1d2b53")
const SOLID := Color("8b6b4a")
const SOLID_EDGE := Color("c2a074")
const CLIMB := Color("5fa15f")
const SPIKES := Color("c2c3c7")
const WATER := Color(0.16, 0.37, 0.69, 0.85)
const PLAYER := Color("ffa300")
const PLAYER_POGO := Color("ffec27")
const WALKER := Color("ff004d")
const GEM := Color("29adff")
const GOAL := Color("00e436")
const INK := Color("fff1e8")
var game: Game
var pack: Pack
var raster := Vector2i(256, 240)
var notice := ""
var _font: Font = ThemeDB.fallback_font


func _process(_delta: float) -> void:
	queue_redraw()


## Left edge of the drawn world window. Wider rasters show more scenery
## around the 256-pixel reference camera, framed within the course width.
func view_left() -> int:
	var extra := raster.x - 256
	var left := game.camera.x - extra / 2
	return clampi(left, 0, maxi(0, 2048 - raster.x))


func _draw() -> void:
	if game == null:
		return
	var motion := game.motion
	var left := view_left()
	draw_rect(Rect2(Vector2.ZERO, raster), _backdrop(motion.section))
	var transition := motion.transition
	if transition.active:
		_draw_section(transition.source_section, left, -transition.camera_offset_y)
		_draw_section(
			transition.target_section, left, transition.direction * 240 - transition.camera_offset_y
		)
	else:
		_draw_section(motion.section, left, 0)
		_draw_pickups(left)
		_draw_walkers(left)
	if game.player_visible:
		var y := motion.y >> 8
		if transition.active:
			y = posmod(y - transition.camera_offset_y, 240)
		_draw_player(Vector2((motion.x >> 8) - left, y))
	_draw_hud()
	var fade := game.attempts.fade()
	if fade > 0.0:
		draw_rect(
			Rect2(Vector2(0, HUD_HEIGHT), Vector2(raster.x, raster.y - HUD_HEIGHT)), Color(0, 0, 0, fade)
		)
	_draw_banner()


func _backdrop(section: int) -> Color:
	if pack != null:
		var color: Variant = pack.backdrop(game.definition.tileset(section))
		if color is Color:
			return color
	return BACKDROP


func _draw_section(section: int, left: int, offset_y: int) -> void:
	var definition := game.definition
	var tileset := definition.tileset(section)
	var first_column := left >> 4
	var last_column := (left + raster.x) >> 4
	for row in range(16):
		var screen_y := row * CELL + offset_y
		if screen_y + CELL <= HUD_HEIGHT or screen_y >= raster.y:
			continue
		for column in range(first_column, last_column + 1):
			var world_x := column * CELL
			if game.terrain.screen_id(section, world_x >> 8) == 255:
				continue
			var metatile := game.terrain.metatile_at(section, world_x, row * CELL)
			var rect := Rect2(Vector2(world_x - left, screen_y), Vector2(CELL, CELL))
			var texture: Texture2D = null
			if pack != null:
				texture = pack.tile(tileset, definition.tile_of(metatile))
			if texture != null:
				draw_texture_rect(texture, rect, false)
			else:
				_draw_placeholder_cell(rect, definition.collision_of(metatile), metatile >> 4)


func _draw_placeholder_cell(rect: Rect2, collision: int, group: int) -> void:
	match collision:
		1:
			draw_rect(rect, SOLID)
			draw_rect(Rect2(rect.position, Vector2(CELL, 2)), SOLID_EDGE)
		2:
			draw_rect(Rect2(rect.position + Vector2(3, 0), Vector2(2, CELL)), CLIMB)
			draw_rect(Rect2(rect.position + Vector2(11, 0), Vector2(2, CELL)), CLIMB)
			for rung in [3, 11]:
				draw_rect(Rect2(rect.position + Vector2(3, rung), Vector2(10, 2)), CLIMB)
		3:
			if group == Definition.SPIKES:
				draw_rect(Rect2(rect.position + Vector2(0, 12), Vector2(CELL, 4)), SOLID)
				for tooth in range(4):
					var base := rect.position + Vector2(tooth * 4, 12)
					draw_colored_polygon(
						PackedVector2Array([base, base + Vector2(4, 0), base + Vector2(2, -10)]), SPIKES
					)
			else:
				draw_rect(rect, WATER)


func _draw_pickups(left: int) -> void:
	var section := game.motion.section
	for gem in game.gems:
		if int(gem.section) != section or game.collected(int(gem.index)):
			continue
		var point := Vector2(int(gem.x) - left, int(gem.y))
		if not _sprite("gem", "idle", point, true, game.render_tick):
			draw_colored_polygon(
				PackedVector2Array(
					[
						point + Vector2(0, -7),
						point + Vector2(6, 0),
						point + Vector2(0, 7),
						point + Vector2(-6, 0)
					]
				),
				GEM
			)
	for goal in game.goals:
		if int(goal.section) != section:
			continue
		var point := Vector2(int(goal.x) - left, int(goal.y))
		if not _sprite("goal", "idle", point, true, game.render_tick):
			draw_rect(Rect2(point + Vector2(-1, -24), Vector2(2, 48)), INK)
			draw_colored_polygon(
				PackedVector2Array(
					[point + Vector2(1, -24), point + Vector2(14, -18), point + Vector2(1, -12)]
				),
				GOAL
			)


func _draw_walkers(left: int) -> void:
	for walker in game.walkers:
		if int(walker.placement.section) != game.motion.section:
			continue
		if walker.status not in [WalkerActor.Status.LIVE, WalkerActor.Status.DEFEATED]:
			continue
		var point := Vector2((walker.x >> 8) - left, walker.y >> 8)
		var defeated := walker.status == WalkerActor.Status.DEFEATED
		var tag := "knocked_out" if defeated else "walk"
		if _sprite("walker", tag, point, walker.direction > 0, walker.ticks):
			continue
		var body := Rect2(point - Vector2(10, 12), Vector2(20, 24))
		draw_rect(body, WALKER if not defeated else WALKER.darkened(0.4))
		var eye_x := 4.0 if walker.direction > 0 else -6.0
		var eye_y := -6.0 if not defeated else 4.0
		draw_rect(Rect2(point + Vector2(eye_x, eye_y), Vector2(3, 3)), INK)


func _draw_player(point: Vector2) -> void:
	var motion := game.motion
	var animation := game.animation
	var tag: String = PlayerAnim.TAGS.get(animation.id, "idle")
	if pack != null and pack.sprite("player") != null:
		var pictures: Array = pack.sprite("player").pictures(tag)
		if pictures.is_empty():
			pictures = pack.sprite("player").pictures("idle")
		if not pictures.is_empty():
			_draw_picture(pictures[animation.picture(pictures.size())], point, motion.facing_right)
			return
	var height := 24.0
	if animation.id == Motion.ANIM_CROUCH:
		height = 16.0
	var body := Rect2(point + Vector2(-8, 12 - height), Vector2(16, height))
	var color := PLAYER_POGO if animation.id == Motion.ANIM_POGO else PLAYER
	if motion.state == Motion.State.DEAD or animation.id == Motion.ANIM_HURT:
		color = color.darkened(0.35)
	draw_rect(body, color)
	var facing := 1.0 if motion.facing_right else -1.0
	draw_rect(Rect2(point + Vector2(facing * 3 - 1.5, 16 - height), Vector2(3, 3)), Color.BLACK)
	if animation.id == Motion.ANIM_POGO:
		draw_rect(Rect2(point + Vector2(-1, 12), Vector2(2, 6)), INK)
	elif animation.id in [Motion.ANIM_SWING, Motion.ANIM_SWING_MISS, Motion.ANIM_PUSH]:
		draw_rect(Rect2(point + Vector2(facing * 8 - 1, 0), Vector2(2, 12)), INK)


## Draw a pack sprite. Returns false when the pack has no picture for it.
func _sprite(key: String, tag: String, point: Vector2, facing_right: bool, ticks: int) -> bool:
	if pack == null or pack.sprite(key) == null:
		return false
	var pictures: Array = pack.sprite(key).pictures(tag)
	if pictures.is_empty():
		return false
	var total := 0
	for picture in pictures:
		total += picture.weight
	var position := ticks % maxi(total, 1)
	for picture in pictures:
		if position < picture.weight:
			_draw_picture(picture, point, facing_right)
			return true
		position -= picture.weight
	_draw_picture(pictures.back(), point, facing_right)
	return true


func _draw_picture(picture: Variant, point: Vector2, facing_right: bool) -> void:
	if facing_right:
		draw_texture_rect(picture.texture, Rect2(point + picture.offset, picture.size), false)
	else:
		var x: float = point.x - picture.offset.x
		draw_texture_rect(
			picture.texture,
			Rect2(Vector2(x, point.y + picture.offset.y), Vector2(-picture.size.x, picture.size.y)),
			false
		)


func _draw_hud() -> void:
	var band := Rect2(Vector2.ZERO, Vector2(raster.x, HUD_HEIGHT))
	var texture := pack.hud("band") if pack != null else null
	if texture != null:
		draw_texture_rect(texture, band, false)
	else:
		draw_rect(band, Color.BLACK)
	var x0 := (raster.x - 256) / 2 + 16
	draw_string(
		_font, Vector2(x0, 20), "SCORE %06d" % game.score, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, INK
	)
	var motion := game.motion
	for pip in range(motion.max_health):
		var rect := Rect2(Vector2(x0 + pip * 12, 28), Vector2(10, 10))
		var full := pip < motion.health
		var picture := pack.hud("health" if full else "health_empty") if pack != null else null
		if picture != null:
			draw_texture_rect(picture, rect, false)
		elif full:
			draw_rect(rect, WALKER)
		else:
			draw_rect(rect, WALKER, false, 1.0)
	var life := pack.hud("life") if pack != null else null
	var life_point := Vector2(x0 + 168, 26)
	if life != null:
		draw_texture_rect(life, Rect2(life_point, Vector2(12, 12)), false)
	else:
		draw_rect(Rect2(life_point, Vector2(10, 12)), PLAYER)
	draw_string(
		_font,
		life_point + Vector2(16, 11),
		"x%d" % game.attempts.lives,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		12,
		INK
	)


func _draw_banner() -> void:
	var text := ""
	if game.cleared:
		text = "COURSE CLEAR"
	elif game.attempts.phase == game.attempts.Phase.GAME_OVER:
		text = "GAME OVER"
	if not text.is_empty():
		var size := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
		draw_string(
			_font, Vector2((raster.x - size.x) / 2, 136), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, INK
		)
	if not notice.is_empty():
		draw_rect(Rect2(Vector2(0, raster.y - 14), Vector2(raster.x, 14)), Color(0, 0, 0, 0.7))
		draw_string(
			_font, Vector2(4, raster.y - 3), notice, HORIZONTAL_ALIGNMENT_LEFT, raster.x - 8, 9, INK
		)
