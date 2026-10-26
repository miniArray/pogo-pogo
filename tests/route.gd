extends RefCounted
## Scripted controller input for a course. A route is whitespace-separated
## steps: button letters then an update count, e.g. `R60 RA12 . 30 DB40`.
## Letters: R right, L left, D down, U up, A jump, B pogo/swing; `.` none.
## Lines starting with # are comments.
const Game = preload("res://src/game/course_game.gd")
const Definition = preload("res://src/course/course_definition.gd")
const LETTERS := {"R": 1, "L": 2, "D": 4, "U": 8, "B": 64, "A": 128}


static func parse(text: String) -> Array[Vector2i]:
	var steps: Array[Vector2i] = []
	for line in text.split("\n"):
		line = line.strip_edges()
		if line.begins_with("#") or line.is_empty():
			continue
		for token in line.split(" ", false):
			var letters := ""
			var digits := ""
			for character in token:
				if character >= "0" and character <= "9":
					digits += character
				else:
					letters += character
			var buttons := 0
			for letter in letters:
				if letter != ".":
					assert(LETTERS.has(letter), "Unknown route letter " + letter)
					buttons |= LETTERS[letter]
			steps.append(Vector2i(buttons, int(digits) if not digits.is_empty() else 1))
	return steps


static func load_game(course_path: String) -> Game:
	var result := Definition.load_path(course_path)
	assert(result.kind == "ready", "Course failed validation: %s" % str(result))
	return Game.new(result.definition)


## Run `steps` and return one digest line every `every` updates plus the final one.
static func run(game: Game, steps: Array[Vector2i], every: int = 30, log: Callable = Callable()) -> PackedStringArray:
	var lines := PackedStringArray()
	for step in steps:
		for index in range(step.y):
			game.update(step.x)
			if log.is_valid():
				log.call(game)
			if game.updates % every == 0:
				lines.append("%d %s" % [game.updates, game.digest()])
	lines.append("%d %s" % [game.updates, game.digest()])
	return lines
