extends Node2D
## Scene host: picks the course and asset pack, reads input, runs one game
## update per physics tick (60 per second) and shows the raster at the
## window's size. Command line, after `--`:
##   --course=PATH        play a course JSON file
##   --pack=PATH          use an asset pack (directory or zip)
##   --placeholder        ignore every pack and draw placeholder shapes
##   --export-course=PATH write the selected course as canonical JSON and quit
##   --display=MODE       start in a display shape (original, fill or W:H) for this run
## Environment: POGO_PACK and POGO_COURSE act like --pack and --course.
const Definition = preload("res://src/course/course_definition.gd")
const Game = preload("res://src/game/course_game.gd")
const Motion = preload("res://src/game/player_motion.gd")
const Pack = preload("res://src/pack/asset_pack.gd")
const View = preload("res://src/render/course_view.gd")
const Layout = preload("res://src/render/display_layout.gd")
const Sounds = preload("res://src/audio/sound_board.gd")
const COURSES := [
	"res://courses/first-steps.json",
	"res://courses/stilt-gardens.json",
	"res://courses/shaft-and-spires.json",
]
const PACK_CACHE := "user://pack.zip"
const COURSE_CACHE := "user://course.json"
const SETTINGS := "user://settings.cfg"
const BUTTON_RIGHT := 1
const BUTTON_LEFT := 2
const BUTTON_DOWN := 4
const BUTTON_UP := 8
const BUTTON_B := 64
const BUTTON_A := 128
var game: Game
var pack: Pack
var course_index := 0  # -1 when a custom course file is playing.
var course_label := ""
var display_mode := "original"
var sharp := true
var notice := ""
var _viewport: SubViewport
var _screen: Sprite2D
var _view: View
var _sounds: Sounds
var _placeholder := false
var _web_pad: JavaScriptObject
var _web_action: JavaScriptObject
var _notice_ticks := 0


func _ready() -> void:
	var options := _options()
	_placeholder = options.has("placeholder")
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(256, 240)
	_viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)
	_view = View.new()
	_viewport.add_child(_view)
	_screen = Sprite2D.new()
	_screen.centered = false
	_screen.texture = _viewport.get_texture()
	_screen.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_screen)
	_sounds = Sounds.new()
	add_child(_sounds)
	_load_settings()
	if options.has("display"):
		# A launcher's choice for this run; saved preferences stay unchanged.
		display_mode = Layout.valid_mode(str(options.display))
	_select_pack(options)
	_select_course(options)
	if options.has("export-course"):
		var file := FileAccess.open(str(options["export-course"]), FileAccess.WRITE)
		if file == null:
			printerr("Cannot write %s" % options["export-course"])
			get_tree().quit(1)
			return
		file.store_string(game.definition.canonical())
		file.close()
		print("COURSE_EXPORTED %s" % game.definition.id())
		get_tree().quit(0)
		return
	get_viewport().size_changed.connect(_relayout)
	_relayout()
	if OS.has_feature("web"):
		var window := JavaScriptBridge.get_interface("window")
		_web_pad = window.pogoPad
		_web_action = JavaScriptBridge.create_callback(_on_web_action)
		window.pogoAction = _web_action
	print("POGO_READY course=%s pack=%s display=%s" % [game.definition.id(), _pack_label(), display_mode])


func _options() -> Dictionary:
	var result := {}
	for argument in OS.get_cmdline_user_args():
		if not argument.begins_with("--"):
			continue
		var parts := argument.substr(2).split("=", true, 1)
		result[parts[0]] = parts[1] if parts.size() > 1 else true
	if not result.has("pack") and not OS.get_environment("POGO_PACK").is_empty():
		result["pack"] = OS.get_environment("POGO_PACK")
	if not result.has("course") and not OS.get_environment("POGO_COURSE").is_empty():
		result["course"] = OS.get_environment("POGO_COURSE")
	return result


func _select_pack(options: Dictionary) -> void:
	pack = null
	if _placeholder:
		_set_notice("Placeholder shapes (--placeholder)")
	elif options.has("pack"):
		_use_pack(Pack.load_path(str(options.pack)))
	elif FileAccess.file_exists(PACK_CACHE):
		_use_pack(Pack.load_path(ProjectSettings.globalize_path(PACK_CACHE)))
	_apply_pack()


func _use_pack(result: Dictionary) -> bool:
	if result.kind != "ready":
		pack = null
		_set_notice("Asset pack not used: %s %s" % [result.path, result.message])
		printerr("POGO_PACK_REJECTED %s %s" % [result.path, result.message])
		_apply_pack()
		return false
	pack = result.pack
	_set_notice("Asset pack: " + pack.summary())
	for line in pack.notices:
		print("POGO_PACK_NOTICE " + line)
	print("POGO_PACK_READY " + pack.summary())
	_apply_pack()
	return true


func _apply_pack() -> void:
	_view.pack = pack
	_sounds.pack = pack
	if game != null:
		_sounds.play_music(str(game.definition.value("music")) if game.definition.value("music") != null else "")


func _pack_label() -> String:
	return pack.name if pack != null else "placeholder"


func _select_course(options: Dictionary) -> void:
	if options.has("course"):
		var result := Definition.load_path(str(options.course))
		if result.kind == "ready":
			_play(result.definition, -1)
			return
		_set_notice("Course not loaded: %s %s" % [result.path, result.message])
		printerr("POGO_COURSE_REJECTED %s %s" % [result.path, result.message])
	_play_bundled(0)


func _play_bundled(index: int) -> void:
	var result := Definition.load_path(COURSES[posmod(index, COURSES.size())])
	assert(result.kind == "ready", "Bundled course failed validation: %s" % str(result))
	_play(result.definition, posmod(index, COURSES.size()))


func _play(definition: Definition, index: int) -> void:
	course_index = index
	game = Game.new(definition)
	_view.game = game
	course_label = definition.id() if index >= 0 else "custom: " + definition.id()
	var music: Variant = definition.value("music")
	_sounds.play_music(str(music) if music != null else "")


func _physics_process(_delta: float) -> void:
	if game == null:
		return
	var held := _buttons()
	game.update(held)
	_sounds.play_events(game.events)
	if game.finished:
		if course_index >= 0:
			_play_bundled(course_index + 1)
		else:
			game.restart()
	if _notice_ticks > 0:
		_notice_ticks -= 1
		if _notice_ticks == 0:
			_view.notice = ""
	_publish_state()


func _buttons() -> int:
	var held := 0
	if Input.is_action_pressed("ui_right") or Input.is_joy_button_pressed(0, JOY_BUTTON_DPAD_RIGHT):
		held |= BUTTON_RIGHT
	if Input.is_action_pressed("ui_left") or Input.is_joy_button_pressed(0, JOY_BUTTON_DPAD_LEFT):
		held |= BUTTON_LEFT
	if Input.is_action_pressed("ui_down") or Input.is_joy_button_pressed(0, JOY_BUTTON_DPAD_DOWN):
		held |= BUTTON_DOWN
	if Input.is_action_pressed("ui_up") or Input.is_joy_button_pressed(0, JOY_BUTTON_DPAD_UP):
		held |= BUTTON_UP
	var stick := Vector2(Input.get_joy_axis(0, JOY_AXIS_LEFT_X), Input.get_joy_axis(0, JOY_AXIS_LEFT_Y))
	if stick.x > 0.5:
		held |= BUTTON_RIGHT
	elif stick.x < -0.5:
		held |= BUTTON_LEFT
	if stick.y > 0.5:
		held |= BUTTON_DOWN
	elif stick.y < -0.5:
		held |= BUTTON_UP
	if (
		Input.is_physical_key_pressed(KEY_Z)
		or Input.is_physical_key_pressed(KEY_SPACE)
		or Input.is_joy_button_pressed(0, JOY_BUTTON_A)
	):
		held |= BUTTON_A
	if (
		Input.is_physical_key_pressed(KEY_X)
		or Input.is_physical_key_pressed(KEY_SHIFT)
		or Input.is_joy_button_pressed(0, JOY_BUTTON_X)
		or Input.is_joy_button_pressed(0, JOY_BUTTON_B)
	):
		held |= BUTTON_B
	if _web_pad != null:
		held |= int(_web_pad.buttons)
	return held


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.physical_keycode:
		KEY_R:
			game.restart()
		KEY_N:
			_play_bundled(course_index + 1)
		KEY_M:
			_sounds.set_muted(not _sounds.muted)
		KEY_F8:
			var index := Layout.MODES.find(display_mode)
			display_mode = Layout.MODES[(index + 1) % Layout.MODES.size()]
			_save_settings()
			_relayout()
		KEY_F9:
			sharp = not sharp
			_save_settings()
			_relayout()


func _relayout() -> void:
	var available := Vector2i(get_viewport().get_visible_rect().size)
	var layout := Layout.calculate(available, display_mode, sharp)
	var raster := Vector2i(roundi(layout.raster.x), roundi(layout.raster.y))
	raster = Vector2i(maxi(raster.x, 256), maxi(raster.y, 240))
	_viewport.size = raster
	_view.raster = raster
	_screen.position = layout.rect.position
	_screen.scale = Vector2(layout.scale, layout.scale)


func _set_notice(text: String) -> void:
	notice = text
	_view.notice = text
	_notice_ticks = 300


func _load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS) == OK:
		display_mode = Layout.valid_mode(str(config.get_value("display", "mode", "original")))
		sharp = bool(config.get_value("display", "sharp", true))
		_sounds.muted = bool(config.get_value("audio", "muted", false))


func _save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("display", "mode", display_mode)
	config.set_value("display", "sharp", sharp)
	config.set_value("audio", "muted", _sounds.muted)
	config.save(SETTINGS)


## Browser actions from web/controller.js. File contents arrive as base64.
func _on_web_action(args: Array) -> void:
	var action := str(args[0]) if args.size() > 0 else ""
	match action:
		"course":
			_play_bundled(int(args[1]))
		"reset":
			game.restart()
		"course_json":
			var result := Definition.load_bytes(Marshalls.base64_to_raw(str(args[1])))
			if result.kind == "ready":
				_play(result.definition, -1)
				_set_notice("Course loaded: " + result.definition.id())
			else:
				_set_notice("Course not loaded: %s %s" % [result.path, result.message])
		"course_save":
			var text := Marshalls.utf8_to_base64(game.definition.canonical())
			JavaScriptBridge.eval(
				"window.pogoDownload && window.pogoDownload('%s.json', '%s')" % [game.definition.id(), text]
			)
		"pack":
			var bytes := Marshalls.base64_to_raw(str(args[1]))
			var file := FileAccess.open(PACK_CACHE + ".tmp", FileAccess.WRITE)
			if file == null:
				_set_notice("Asset pack not saved: browser storage is unavailable.")
				return
			file.store_buffer(bytes)
			file.close()
			var result := Pack.load_path(ProjectSettings.globalize_path(PACK_CACHE + ".tmp"))
			if result.kind == "ready":
				DirAccess.rename_absolute(
					ProjectSettings.globalize_path(PACK_CACHE + ".tmp"), ProjectSettings.globalize_path(PACK_CACHE)
				)
				_placeholder = false
				_use_pack(result)
			else:
				DirAccess.remove_absolute(ProjectSettings.globalize_path(PACK_CACHE + ".tmp"))
				_set_notice("Asset pack not used: %s %s" % [result.path, result.message])
			_sync_web_storage()
		"pack_clear":
			DirAccess.remove_absolute(ProjectSettings.globalize_path(PACK_CACHE))
			pack = null
			_apply_pack()
			_set_notice("Asset pack removed; placeholder shapes")
			_sync_web_storage()
		"display":
			display_mode = Layout.valid_mode(str(args[1]))
			sharp = bool(args[2]) if args.size() > 2 else sharp
			_save_settings()
			_relayout()
		"mute":
			_sounds.set_muted(bool(args[1]))
			_save_settings()
		"release_keys":
			pass


func _sync_web_storage() -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.force_fs_sync()


func _publish_state() -> void:
	if not OS.has_feature("web"):
		return
	JavaScriptBridge.get_interface("window").pogoStateJSON = JSON.stringify(
		{
			"course": game.definition.id(),
			"course_index": course_index,
			"pack": _pack_label(),
			"notice": notice,
			"x": game.motion.x,
			"y": game.motion.y,
			"section": game.motion.section,
			"state": int(game.motion.state),
			"score": game.score,
			"lives": game.attempts.lives,
			"updates": game.updates,
			"cleared": game.cleared,
			"raster": [_view.raster.x, _view.raster.y],
			"sounds": _sounds.played.size(),
			"music": _sounds.music_cue(),
		}
	)
