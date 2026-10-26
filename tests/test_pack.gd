extends RefCounted
## Builds a small asset pack of solid colours and short tones for checks.
## Nothing it writes is committed: tests and the browser check create it in
## a scratch folder each run.
const TILES := {
	"meadow": ["ground-top", "ground", "block", "vine", "ledge", "grass", "spikes", "water"],
	"garden": ["ground-top", "ground", "block", "ledge", "grass", "spikes", "water"],
	"cavern": ["ground-top", "ground", "ledge", "vine", "grass", "spikes", "water"],
	"spires": ["ground-top", "ground", "ledge", "vine", "grass", "spikes", "water"],
}
const PLAYER_TAGS := [
	"idle", "walk", "air", "crouch", "climb", "hurt", "pogo", "push", "land", "swing", "swing_miss"
]


## Write the pack into `folder` (created if needed). Returns the manifest.
static func build(folder: String) -> Dictionary:
	DirAccess.make_dir_recursive_absolute(folder.path_join("tiles"))
	DirAccess.make_dir_recursive_absolute(folder.path_join("sprites"))
	DirAccess.make_dir_recursive_absolute(folder.path_join("sounds"))
	var tilesets := {}
	var hue := 0.0
	for tileset in TILES:
		var tiles := {}
		for tile in TILES[tileset]:
			hue = fmod(hue + 0.13, 1.0)
			var path := "tiles/%s-%s.png" % [tileset, tile]
			_solid(Vector2i(16, 16), Color.from_hsv(hue, 0.6, 0.9)).save_png(folder.path_join(path))
			tiles[tile] = path
		tilesets[tileset] = {"backdrop": "#203040", "tiles": tiles}
	_sheet(folder, "sprites/player", PLAYER_TAGS, Vector2i(24, 32), Color("ffa300"))
	_sheet(folder, "sprites/walker", ["walk", "knocked_out"], Vector2i(24, 24), Color("ff004d"))
	_sheet(folder, "sprites/gem", ["idle"], Vector2i(12, 14), Color("29adff"))
	_sheet(folder, "sprites/goal", ["idle"], Vector2i(16, 48), Color("00e436"))
	var sounds := {}
	var pitch := 330.0
	for event in ["land", "pogo", "climb", "swing", "swing_miss", "hurt", "knockout", "gem", "checkpoint", "defeat", "retry", "game_over", "clear"]:
		pitch *= 1.06
		var path := "sounds/%s.wav" % event
		_tone(folder.path_join(path), pitch, 0.08)
		sounds[event] = path
	_tone(folder.path_join("sounds/theme.wav"), 220.0, 0.5)
	var manifest := {
		"format_version": 1,
		"name": "Solid colours",
		"tilesets": tilesets,
		"sprites": {
			"player": {"sheet": "sprites/player.json"},
			"walker": {"sheet": "sprites/walker.json"},
			"gem": {"sheet": "sprites/gem.json"},
			"goal": {"sheet": "sprites/goal.json", "texels_per_pixel": 1},
		},
		"sounds": sounds,
		"music": {"meadow": "sounds/theme.wav", "garden": "sounds/theme.wav", "spires": "sounds/theme.wav"},
	}
	var file := FileAccess.open(folder.path_join("pack.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest, "  "))
	file.close()
	return manifest


## Zip every file under `folder` into `zip_path` with paths relative to it.
static func zip(folder: String, zip_path: String) -> void:
	var packer := ZIPPacker.new()
	packer.open(zip_path)
	for relative in _files(folder, ""):
		packer.start_file(relative)
		packer.write_file(FileAccess.get_file_as_bytes(folder.path_join(relative)))
		packer.close_file()
	packer.close()


static func _files(root: String, prefix: String) -> Array[String]:
	var result: Array[String] = []
	var directory := DirAccess.open(root.path_join(prefix))
	for name in directory.get_files():
		result.append(prefix.path_join(name) if not prefix.is_empty() else name)
	for name in directory.get_directories():
		result.append_array(_files(root, prefix.path_join(name) if not prefix.is_empty() else name))
	return result


static func _solid(size: Vector2i, color: Color) -> Image:
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	image.fill(color)
	for x in range(size.x):
		image.set_pixel(x, 0, color.lightened(0.4))
	return image


## One sheet: a row of frames per tag, two frames each, Aseprite array format.
static func _sheet(folder: String, base: String, tags: Array, size: Vector2i, color: Color) -> void:
	var image := Image.create(size.x * 2, size.y * tags.size(), false, Image.FORMAT_RGBA8)
	var frames := []
	var frame_tags := []
	for row in range(tags.size()):
		for column in range(2):
			var shade := color.darkened(0.1 * row) if column == 0 else color.lightened(0.15)
			image.fill_rect(Rect2i(column * size.x + 1, row * size.y + 1, size.x - 2, size.y - 2), shade)
			frames.append(
				{
					"frame": {"x": column * size.x, "y": row * size.y, "w": size.x, "h": size.y},
					"rotated": false,
					"trimmed": false,
					"spriteSourceSize": {"x": 0, "y": 0, "w": size.x, "h": size.y},
					"sourceSize": {"w": size.x, "h": size.y},
					"duration": 100,
				}
			)
		frame_tags.append({"name": tags[row], "from": row * 2, "to": row * 2 + 1, "direction": "forward"})
	image.save_png(folder.path_join(base + ".png"))
	var data := {
		"frames": frames,
		"meta": {
			"app": "test",
			"image": base.get_file() + ".png",
			"size": {"w": image.get_width(), "h": image.get_height()},
			"frameTags": frame_tags,
			"slices": [
				{
					"name": "origin",
					"keys": [
						{
							"frame": 0,
							"bounds": {"x": 0, "y": 0, "w": size.x, "h": size.y},
							"pivot": {"x": size.x / 2, "y": size.y - 12}
						}
					]
				}
			]
		}
	}
	var file := FileAccess.open(folder.path_join(base + ".json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(data, "  "))
	file.close()


## A 16-bit mono PCM WAV sine tone.
static func _tone(path: String, frequency: float, seconds: float) -> void:
	var rate := 22050
	var count := int(rate * seconds)
	var samples := PackedByteArray()
	samples.resize(count * 2)
	for index in range(count):
		var envelope := 1.0 - float(index) / count
		var value := int(sin(TAU * frequency * index / rate) * 9000.0 * envelope)
		samples.encode_s16(index * 2, value)
	var header := PackedByteArray()
	header.append_array("RIFF".to_ascii_buffer())
	var size := PackedByteArray()
	size.resize(4)
	size.encode_u32(0, 36 + samples.size())
	header.append_array(size)
	header.append_array("WAVEfmt ".to_ascii_buffer())
	var fmt := PackedByteArray()
	fmt.resize(20)
	fmt.encode_u32(0, 16)
	fmt.encode_u16(4, 1)
	fmt.encode_u16(6, 1)
	fmt.encode_u32(8, rate)
	fmt.encode_u32(12, rate * 2)
	fmt.encode_u16(16, 2)
	fmt.encode_u16(18, 16)
	header.append_array(fmt)
	header.append_array("data".to_ascii_buffer())
	var data_size := PackedByteArray()
	data_size.resize(4)
	data_size.encode_u32(0, samples.size())
	header.append_array(data_size)
	header.append_array(samples)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(header)
	file.close()
