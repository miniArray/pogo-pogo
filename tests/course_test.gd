extends SceneTree
## Course contract: bundled courses validate; malformed documents are rejected
## with a field path; canonical output round-trips.
const Definition = preload("res://src/course/course_definition.gd")
const Check = preload("res://tests/check.gd")
const COURSES := [
	"res://courses/first-steps.json",
	"res://courses/stilt-gardens.json",
	"res://courses/shaft-and-spires.json",
]


func _init() -> void:
	var check := Check.new("COURSE_CHECK")
	var base: Dictionary = {}
	for path in COURSES:
		var result := Definition.load_path(path)
		check.equal(result.kind, "ready", "%s validates: %s" % [path, str(result)])
		if result.kind == "ready":
			var again := Definition.load_bytes(result.definition.canonical().to_utf8_buffer())
			check.equal(again.kind, "ready", "%s canonical form re-validates" % path)
			check.equal(again.definition.canonical(), result.definition.canonical(), "%s round-trips" % path)
			if base.is_empty():
				base = JSON.parse_string(FileAccess.get_file_as_string(path))
	_rejects(check, base, "format_version", func(d): d.format_version = 2, "$.format_version")
	_rejects(check, base, "unknown field", func(d): d["extra"] = 1, "$.extra")
	_rejects(check, base, "missing hud", func(d): d.erase("hud"), "$.hud")
	_rejects(check, base, "bad level id", func(d): d.level.id = "Bad Id", "$.level.id")
	_rejects(check, base, "fractional x", func(d): d.placements[0].x = 10.5, "$.placements[0].x")
	_rejects(check, base, "unknown actor", func(d): d.placements[0].type = "dragon", "$.placements[0].type")
	_rejects(
		check, base, "duplicate placement index",
		func(d): d.placements[1].index = d.placements[0].index, "$.placements[1].index"
	)
	_rejects(
		check, base, "no goal",
		func(d): d.placements = d.placements.filter(func(p): return p.type != "goal"), "$.placements"
	)
	_rejects(check, base, "dangling screen", func(d): d.terrain.grid[0] = 200, "$.terrain.grid[0]")
	_rejects(
		check, base, "class-3 outside the hazard groups",
		func(d): d.terrain.metatiles[5].collision = 3, "$.terrain.screens"
	)
	_rejects(check, base, "entry outside camera", func(d): d.entry.x = d.entry.camera_x + 300, "$.entry")
	_rejects(check, base, "absent checkpoint page", func(d): d.checkpoint.page = 7, "$.checkpoint")
	_rejects(check, base, "bad tile key", func(d): d.terrain.metatiles[1].tile = "Up/../x", "$.terrain.metatiles[1].tile")
	_rejects(check, base, "bad tileset key", func(d): d.sections[0].tileset = "", "$.sections[0].tileset")
	var huge := PackedByteArray()
	huge.resize(Definition.MAX_BYTES + 1)
	check.equal(Definition.load_bytes(huge).kind, "size", "oversized file is rejected before parsing")
	check.equal(
		Definition.load_bytes("{\"a\":".to_utf8_buffer()).kind, "json", "broken JSON is reported"
	)
	quit(check.finish())


func _rejects(check: Check, base: Dictionary, label: String, change: Callable, path: String) -> void:
	var document: Dictionary = base.duplicate(true)
	change.call(document)
	var result := Definition.load_bytes(JSON.stringify(document).to_utf8_buffer())
	check.ok(result.kind != "ready", "%s is rejected" % label)
	if result.kind != "ready":
		check.ok(
			str(result.path).begins_with(path), "%s reports %s, got %s" % [label, path, result.path]
		)
