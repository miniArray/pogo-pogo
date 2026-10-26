extends SceneTree
## Developer aid: play a route and print the player every N updates.
##   tools/godot.sh --headless --script tools/probe-route.gd -- COURSE ROUTE_FILE [EVERY]
const Route = preload("res://tests/route.gd")
const Motion = preload("res://src/game/player_motion.gd")


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var game := Route.load_game(args[0])
	var steps := Route.parse(FileAccess.get_file_as_string(args[1]))
	var every := int(args[2]) if args.size() > 2 else 10
	var printer := func(g) -> void:
		if g.updates % every == 0 or not g.events.is_empty():
			print(
				"%5d x=%4d y=%3d sec=%d st=%2d anim=%2d hp=%d lives=%d cam=%4d score=%d %s%s"
				% [
					g.updates, g.motion.x >> 8, g.motion.y >> 8, g.motion.section,
					int(g.motion.state), g.motion.animation, g.motion.health,
					g.attempts.lives, g.camera.x, g.score, ",".join(g.events),
					" CLEAR" if g.cleared else ""
				]
			)
	Route.run(game, steps, 1000000, printer)
	quit()
