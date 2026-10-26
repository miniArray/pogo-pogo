extends SceneTree
## Focused game rules on the first course: pit retry, checkpoint retry, game
## over and restart, walker contact and turning, and the swing.
const Route = preload("res://tests/route.gd")
const Game = preload("res://src/game/course_game.gd")
const Motion = preload("res://src/game/player_motion.gd")
const Walker = preload("res://src/game/walker.gd")
const Attempts = preload("res://src/game/attempt_flow.gd")
const Check = preload("res://tests/check.gd")
const COURSE := "res://courses/first-steps.json"


func _init() -> void:
	var check := Check.new("WORLD_CHECK")
	_pit_retry(check)
	_checkpoint_retry(check)
	_game_over(check)
	_walker_contact(check)
	_walker_turns(check)
	_swing(check)
	quit(check.finish())


func _game() -> Game:
	var game := Route.load_game(COURSE)
	game.update(0)
	return game


func _place(game: Game, x: int, y: int, camera_x: int) -> void:
	game.motion.x = x * 256
	game.motion.y = y * 256
	game.motion.state = Motion.State.AIRBORNE
	game.motion.velocity_up = 0
	game.camera.x = camera_x
	game.camera.map_index = game.motion.section * 8 + (camera_x >> 8)


func _run_until(game: Game, event: String, limit: int) -> bool:
	for index in range(limit):
		game.update(0)
		if event in game.events:
			return true
	return false


func _pit_retry(check: Check) -> void:
	var game := _game()
	_place(game, 368, 150, 240)
	check.ok(_run_until(game, "retry", 120), "falling into water requests a retry")
	check.equal(game.attempts.phase, Attempts.Phase.RETRY, "retry phase starts")
	for index in range(Attempts.RESUME_TICK):
		game.update(0)
	check.equal(game.attempts.phase, Attempts.Phase.PLAYING, "play resumes after the retry wait")
	check.equal(game.attempts.lives, 1, "a retry spends one life")
	check.equal(game.motion.x >> 8, 40, "retry returns to the course retry point")
	check.equal(game.motion.health, game.motion.max_health, "retry refills health")


func _checkpoint_retry(check: Check) -> void:
	var game := _game()
	_place(game, 800, 196, 700)
	check.ok(_run_until(game, "checkpoint", 5), "reaching page 3 latches the checkpoint")
	_place(game, 1112, 150, 1000)
	check.ok(_run_until(game, "retry", 120), "second water gap requests a retry")
	for index in range(Attempts.RESUME_TICK + 2):
		game.update(0)
	check.equal(game.motion.x >> 8, 792, "retry after the checkpoint returns to the checkpoint")


func _game_over(check: Check) -> void:
	var game := _game()
	game.attempts.lives = 0
	game.score = 500
	_place(game, 368, 150, 240)
	check.ok(_run_until(game, "game_over", 120), "a fall with no lives ends the game")
	check.equal(game.attempts.phase, Attempts.Phase.GAME_OVER, "game-over phase")
	for index in range(Game.GAME_OVER_WAIT + 1):
		game.update(0)
	check.equal(game.attempts.phase, Attempts.Phase.PLAYING, "the course restarts after game over")
	check.equal(game.attempts.lives, 2, "restart restores the course's lives")
	check.equal(game.score, 0, "restart clears the score")


func _walker(game: Game, x: int) -> Walker:
	for walker in game.walkers:
		if int(walker.placement.x) == x:
			return walker
	return null


func _walker_contact(check: Check) -> void:
	var game := _game()
	_place(game, 420, 196, 300)
	game.motion.state = Motion.State.GROUNDED
	var walker := _walker(game, 480)
	check.ok(_run_until(game, "hurt", 120), "walking into a walker hurts the player")
	check.equal(walker.status, Walker.Status.LIVE, "the walker survives a side contact")
	game.update(0)
	check.ok(game.motion.health < game.motion.max_health, "contact costs health")


func _walker_turns(check: Check) -> void:
	var game := _game()
	_place(game, 200, 196, 300)
	game.motion.state = Motion.State.GROUNDED
	var walker := _walker(game, 480)
	game.update(0)
	game.camera.x = 300
	game._stream()
	check.equal(walker.status, Walker.Status.LIVE, "a walker spawns when its spot enters the window")
	check.equal(walker.direction, -1, "it starts walking toward the player")
	var turned := false
	for index in range(120):
		walker.advance(300)
		if walker.direction == 1:
			turned = true
			break
	check.ok(turned, "it turns at the water's edge")
	check.ok((walker.x >> 8) >= 400, "it stays on solid ground (x=%d)" % (walker.x >> 8))


func _swing(check: Check) -> void:
	var game := _game()
	var events := {}
	for step in Route.parse("R220 RB4 . 60"):
		for index in range(step.y):
			game.update(step.x)
			for event in game.events:
				events[event] = true
	check.ok(events.has("swing"), "pushing a wall then B swings")
	check.ok(events.has("swing_miss"), "a swing with nothing to hit misses")
	for index in range(120):
		game.update(0)
	check.equal(game.motion.state, Motion.State.GROUNDED, "the player recovers from the swing")
