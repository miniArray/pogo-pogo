class_name SoundBoard
extends Node
## Plays pack sounds for game events and loops the course music cue. With no
## pack, or no sound for an event, it stays silent. Sound never feeds back
## into the game.
const Pack = preload("res://src/pack/asset_pack.gd")
const VOICES := 4
var pack: Pack
var muted := false
var played: Array[String] = []  # Events that found a sound, newest last (for checks).
var _voices: Array[AudioStreamPlayer] = []
var _music: AudioStreamPlayer
var _cue := ""
var _next := 0


func _ready() -> void:
	for index in range(VOICES):
		var voice := AudioStreamPlayer.new()
		add_child(voice)
		_voices.append(voice)
	_music = AudioStreamPlayer.new()
	_music.volume_db = -6.0
	add_child(_music)


func play_events(events: Array[String]) -> void:
	if pack == null:
		return
	for event in events:
		var stream := pack.sound(event)
		if stream == null:
			continue
		played.append(event)
		if played.size() > 64:
			played.pop_front()
		if muted:
			continue
		var voice := _voices[_next]
		_next = (_next + 1) % VOICES
		voice.stream = stream
		voice.play()


func play_music(cue: String) -> void:
	var stream := pack.music(cue) if pack != null and not cue.is_empty() else null
	if cue == _cue and _music.stream == stream and (_music.playing or stream == null or muted):
		return
	_cue = cue
	_music.stop()
	_music.stream = stream
	if stream != null and not muted:
		_music.play()


func music_cue() -> String:
	return _cue if _music.stream != null else ""


func set_muted(value: bool) -> void:
	muted = value
	if muted:
		_music.stop()
		for voice in _voices:
			voice.stop()
	elif _music.stream != null:
		_music.play()
