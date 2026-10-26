extends SceneTree
## Asset-pack loader: a generated pack loads from a directory and a zip,
## resolves tiles, sprites, sounds and music, draws and plays; broken packs
## are rejected with a reason so the game can fall back to placeholders.
const Pack = preload("res://src/pack/asset_pack.gd")
const TestPack = preload("res://tests/test_pack.gd")
const Route = preload("res://tests/route.gd")
const View = preload("res://src/render/course_view.gd")
const Sounds = preload("res://src/audio/sound_board.gd")
const Check = preload("res://tests/check.gd")
var _check := Check.new("PACK_CHECK")
var _folder := ""


func _init() -> void:
	_folder = OS.get_user_data_dir().path_join("pack-test-%d" % OS.get_process_id())
	TestPack.build(_folder)
	var result := Pack.load_path(_folder)
	_check.equal(result.kind, "ready", "generated directory pack loads: %s" % str(result))
	if result.kind == "ready":
		_resolves(result.pack, "directory")
	var zip_path := _folder + ".zip"
	TestPack.zip(_folder, zip_path)
	var zipped := Pack.load_path(zip_path)
	_check.equal(zipped.kind, "ready", "generated zip pack loads: %s" % str(zipped))
	if zipped.kind == "ready":
		_resolves(zipped.pack, "zip")
		_draws_and_plays.call_deferred(zipped.pack)
	else:
		_broken_packs()


func _resolves(pack: Pack, label: String) -> void:
	_check.ok(pack.tile("meadow", "ground") != null, "%s: tile resolves" % label)
	_check.ok(pack.tile("meadow", "missing") == null, "%s: unknown tile is null" % label)
	_check.ok(pack.tile("nowhere", "ground") == null, "%s: unknown tileset is null" % label)
	_check.equal(pack.backdrop("meadow"), Color("203040"), "%s: backdrop colour" % label)
	var player := pack.sprite("player")
	_check.ok(player != null, "%s: player sheet loads" % label)
	if player != null:
		_check.equal(player.pictures("walk").size(), 2, "%s: walk tag has two pictures" % label)
		var picture = player.pictures("walk")[0]
		_check.equal(picture.offset, Vector2(-12, -20), "%s: origin slice sets the actor point" % label)
		_check.equal(picture.size, Vector2(24, 32), "%s: picture size" % label)
	_check.ok(pack.sound("gem") is AudioStreamWAV, "%s: gem sound loads" % label)
	_check.ok(pack.music("meadow") != null, "%s: music cue loads" % label)
	_check.ok(pack.music("cavern") == null, "%s: missing music cue is null" % label)


func _draws_and_plays(pack: Pack) -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(320, 240)
	root.add_child(viewport)
	var view := View.new()
	view.raster = Vector2i(320, 240)
	view.pack = pack
	view.game = Route.load_game("res://courses/first-steps.json")
	viewport.add_child(view)
	var sounds := Sounds.new()
	root.add_child(sounds)
	sounds.pack = pack
	for index in range(5):
		await process_frame
	view.game.update(0)
	view.queue_redraw()
	await process_frame
	_check.ok(view.is_inside_tree(), "view draws a frame with the pack")
	sounds.play_events(["gem", "unknown-event"] as Array[String])
	_check.equal(sounds.played, ["gem"] as Array[String], "a pack sound plays for its event only")
	sounds.play_music("meadow")
	_check.equal(sounds.music_cue(), "meadow", "the course music cue plays")
	sounds.play_music("cavern")
	_check.equal(sounds.music_cue(), "", "a cue the pack lacks plays nothing")
	_broken_packs()


func _broken_packs() -> void:
	_rejects("no manifest", func(dir): DirAccess.remove_absolute(dir.path_join("pack.json")), "$")
	_rejects("bad JSON", func(dir): _write(dir, "pack.json", "{"), "$")
	_rejects("wrong version", func(dir): _edit(dir, func(m): m.format_version = 2), "$.format_version")
	_rejects("unknown field", func(dir): _edit(dir, func(m): m["code"] = "x"), "$.code")
	_rejects("unknown sprite", func(dir): _edit(dir, func(m): m.sprites["dragon"] = {"sheet": "x.json"}), "$.sprites.dragon")
	_rejects("unknown sound event", func(dir): _edit(dir, func(m): m.sounds["explode"] = "sounds/gem.wav"), "$.sounds.explode")
	_rejects("bad tile key", func(dir): _edit(dir, func(m): m.tilesets.meadow.tiles["Bad Key"] = "tiles/meadow-ground.png"), "$.tilesets.meadow.tiles")
	_rejects("missing file", func(dir): DirAccess.remove_absolute(dir.path_join("tiles/meadow-ground.png")), "$.tilesets.meadow.tiles.ground")
	_rejects("parent path", func(dir): _edit(dir, func(m): m.tilesets.meadow.tiles.ground = "tiles/../pack.json"), "$.tilesets.meadow.tiles.ground")
	_rejects("absolute path", func(dir): _edit(dir, func(m): m.tilesets.meadow.tiles.ground = "/etc/passwd"), "$.tilesets.meadow.tiles.ground")
	_rejects("not a PNG", func(dir): _write(dir, "tiles/meadow-ground.png", "text"), "$.tilesets.meadow.tiles.ground")
	_rejects("not audio", func(dir): _write(dir, "sounds/gem.wav", "text"), "$.sounds.gem")
	_rejects("bad sheet", func(dir): _write(dir, "sprites/player.json", "{\"frames\": []}"), "$.sprites.player")
	var missing := Pack.load_path(_folder.path_join("does-not-exist.zip"))
	_check.ok(missing.kind != "ready", "a missing pack path is rejected")
	quit(_check.finish())


func _rejects(label: String, damage: Callable, path: String) -> void:
	var copy := _folder + "-broken"
	_copy(_folder, copy)
	damage.call(copy)
	var result := Pack.load_path(copy)
	_check.ok(result.kind != "ready", "%s is rejected" % label)
	if result.kind != "ready":
		_check.ok(str(result.path).begins_with(path), "%s reports %s, got %s: %s" % [label, path, result.path, result.message])
		_check.ok(not str(result.message).is_empty(), "%s explains the problem" % label)
	_remove(copy)


func _edit(dir: String, change: Callable) -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("pack.json")))
	change.call(manifest)
	_write(dir, "pack.json", JSON.stringify(manifest))


func _write(dir: String, relative: String, text: String) -> void:
	var file := FileAccess.open(dir.path_join(relative), FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _copy(from: String, to: String) -> void:
	DirAccess.make_dir_recursive_absolute(to)
	var directory := DirAccess.open(from)
	for name in directory.get_files():
		DirAccess.copy_absolute(from.path_join(name), to.path_join(name))
	for name in directory.get_directories():
		_copy(from.path_join(name), to.path_join(name))


func _remove(path: String) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		return
	for name in directory.get_files():
		DirAccess.remove_absolute(path.path_join(name))
	for name in directory.get_directories():
		_remove(path.path_join(name))
	DirAccess.remove_absolute(path)
