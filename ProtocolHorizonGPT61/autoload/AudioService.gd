extends Node

var _player: AudioStreamPlayer
var _last_tap_ms := -1000

func _ready() -> void:
	for bus_name in ["Music", "SFX", "Ambience"]:
		if AudioServer.get_bus_index(bus_name) < 0:
			AudioServer.add_bus()
			var index := AudioServer.bus_count - 1
			AudioServer.set_bus_name(index, bus_name)
			AudioServer.set_bus_send(index, "Master")
	_player = AudioStreamPlayer.new()
	_player.bus = "SFX"
	_player.stream = preload("res://assets/audio/ui_tap.wav")
	add_child(_player)
	apply_settings(GameState.settings)

func apply_settings(settings: Dictionary) -> void:
	for key in ["master", "music", "sfx", "ambience"]:
		var index := AudioServer.get_bus_index("Master" if key == "master" else key.capitalize())
		if key == "sfx":
			index = AudioServer.get_bus_index("SFX")
		if index >= 0:
			var value := float(settings[key])
			AudioServer.set_bus_mute(index, value <= 0.0)
			AudioServer.set_bus_volume_db(index, linear_to_db(maxf(value, 0.0001)))
	Engine.max_fps = int(settings["fps"])

func tap() -> void:
	var now := Time.get_ticks_msec()
	if now - _last_tap_ms < 65:
		return
	_last_tap_ms = now
	_player.play()
	if GameState.settings["vibration"] and OS.has_feature("mobile"):
		Input.vibrate_handheld(12)
