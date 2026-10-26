extends SceneTree
## Replays each bundled course's route and compares the game state digest every
## 30 updates with the recorded fixture. Every route must clear its course.
## POGO_RECORD=1 rewrites the fixtures after an intended mechanics change.
const Route = preload("res://tests/route.gd")
const Check = preload("res://tests/check.gd")
const COURSES := ["first-steps", "stilt-gardens", "shaft-and-spires"]
## Events each route must show, proving the mechanic is exercised.
const REQUIRED := {
	"first-steps": ["gem", "pogo", "knockout", "checkpoint", "climb", "clear"],
	"stilt-gardens": ["gem", "pogo", "checkpoint", "clear"],
	"shaft-and-spires": ["gem", "pogo", "knockout", "checkpoint", "climb", "clear"],
}


func _init() -> void:
	var check := Check.new("ROUTE_CHECK")
	var record := OS.get_environment("POGO_RECORD") == "1"
	for course in COURSES:
		var game := Route.load_game("res://courses/%s.json" % course)
		var steps := Route.parse(FileAccess.get_file_as_string("res://tests/routes/%s.route" % course))
		var seen := {}
		var sections := {}
		var collect := func(g) -> void:
			for event in g.events:
				seen[event] = true
			sections[g.motion.section] = true
		var lines := Route.run(game, steps, 30, collect)
		var path := "res://tests/fixtures/%s.digest" % course
		if record:
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tests/fixtures"))
			var file := FileAccess.open(path, FileAccess.WRITE)
			file.store_string("\n".join(lines) + "\n")
			file.close()
			print("recorded %s (%d lines)" % [path, lines.size()])
		var expected := FileAccess.get_file_as_string(path).strip_edges().split("\n")
		check.equal(lines.size(), expected.size(), "%s digest line count" % course)
		for index in range(mini(lines.size(), expected.size())):
			if lines[index] != expected[index]:
				check.ok(false, "%s diverges at line %d:\n  got      %s\n  expected %s" % [course, index, lines[index], expected[index]])
				break
		check.ok(game.cleared, "%s route clears the course" % course)
		for event in REQUIRED[course]:
			check.ok(seen.has(event), "%s route shows %s" % [course, event])
		if course == "shaft-and-spires":
			check.ok(sections.size() >= 2, "shaft-and-spires route crosses sections")
	quit(check.finish())
