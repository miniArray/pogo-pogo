extends SceneTree
## Developer aid: grow a route greedily. Each stage tries every option, keeps
## the one that takes no damage and gets furthest right (or clears), and
## prints the route. Slow but simple: every try replays from the start.
##   tools/godot.sh --headless --script tools/search-route.gd -- COURSE 'PREFIX' 'OPT1|OPT2|...' STAGES [left]
const Route = preload("res://tests/route.gd")
const Motion = preload("res://src/game/player_motion.gd")
var _leftward := false


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var course := args[0]
	var route := args[1]
	var options := args[2].split("|")
	var stages := int(args[3])
	_leftward = args.size() > 4 and args[4] == "left"
	for stage in range(stages):
		var best := ""
		var best_score := -1000000
		for option in options:
			var score := _score(course, route + " " + option, route)
			if score > best_score:
				best_score = score
				best = option
		if best_score <= -1000000:
			print("STUCK after: ", route)
			break
		route += " " + best
		print("stage %d score %d: %s" % [stage, best_score, route])
		if best_score >= 90000:
			break
	print("ROUTE ", route)
	quit()


func _score(course: String, candidate: String, prefix: String) -> int:
	var game := Route.load_game(course)
	var prefix_updates := 0
	for step in Route.parse(prefix):
		prefix_updates += step.y
	var bad := [false]
	var watcher := func(g) -> void:
		if g.updates > prefix_updates:
			for event in g.events:
				if event in ["hurt", "retry", "defeat", "game_over"]:
					bad[0] = true
	Route.run(game, Route.parse(candidate), 1000000, watcher)
	if bad[0]:
		return -1000000
	if game.cleared:
		return 100000 - game.updates
	return -(game.motion.x >> 8) if _leftward else game.motion.x >> 8
