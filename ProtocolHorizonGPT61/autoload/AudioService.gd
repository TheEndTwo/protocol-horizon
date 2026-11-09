extends Node

var _player: AudioStreamPlayer
var _last_tap_ms := -1000
var _effect_players: Array[AudioStreamPlayer] = []
var _ambience: AudioStreamPlayer
var _sounds: Dictionary = {}
var _last_effect: Dictionary = {}
var _voice := 0
var _suspended := false
const EFFECTS := ["case_open","dialogue_message","machine_start","mining_critical","mining_hit","mission_complete","radar_ping","reward_claim","ui_back","ui_error","ui_purchase"]

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
	_player.name = "UIClick"
	_player.volume_db = -8
	add_child(_player)
	for i in range(3):
		var voice := AudioStreamPlayer.new()
		voice.name = "Effect%d" % i
		voice.bus = "SFX"
		voice.volume_db = -8
		add_child(voice)
		_effect_players.append(voice)
	_ambience = AudioStreamPlayer.new()
	_ambience.name = "MineAmbience"
	_ambience.bus = "Ambience"
	_ambience.volume_db = -22
	add_child(_ambience)
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
	if _suspended or DisplayServer.get_name() == "headless":
		return
	var now := Time.get_ticks_msec()
	if now - _last_tap_ms < 65:
		return
	_last_tap_ms = now
	if _player.stream == null:
		_player.stream = preload("res://assets/audio/ui_tap.wav")
	_player.play()
	if GameState.settings["vibration"] and OS.has_feature("mobile"):
		Input.vibrate_handheld(12)

func stop_all() -> void:
	var voices: Array = _effect_players.duplicate()
	voices.append(_player)
	voices.append(_ambience)
	for voice in voices:
		if is_instance_valid(voice):
			voice.stop()
			voice.stream = null

func _exit_tree() -> void:
	stop_all()

func play_effect(id: String) -> void:
	if _suspended or DisplayServer.get_name() == "headless" or not id in EFFECTS:
		return
	var now := Time.get_ticks_msec()
	if now-int(_last_effect.get(id,-1000)) < 80:
		return
	_last_effect[id] = now
	if not _sounds.has(id):
		_sounds[id] = load("res://assets/audio/"+id+".wav")
	var voice := _effect_players[_voice]
	_voice = (_voice+1)%_effect_players.size()
	voice.stream = _sounds[id]
	voice.play()

func set_mine_ambience(enabled: bool) -> void:
	if not is_instance_valid(_ambience):
		return
	if not enabled or _suspended or DisplayServer.get_name() == "headless":
		_ambience.stop()
		return
	if _ambience.playing:
		return
	if not _sounds.has("conveyor_loop"):
		var stream = load("res://assets/audio/conveyor_loop.wav")
		if stream is AudioStreamWAV:
			stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
			stream.loop_begin = 0
			stream.loop_end = int(round(stream.get_length()*stream.mix_rate))
		_sounds["conveyor_loop"] = stream
	_ambience.stream = _sounds["conveyor_loop"]
	_ambience.play()

func suspend() -> void:
	_suspended = true
	stop_all()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED:
		suspend()
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		_suspended = false
