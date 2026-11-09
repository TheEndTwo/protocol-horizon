extends SceneTree

var failures: PackedStringArray = []
var registry: Node
var state: Node
var saves: Node
var router: Node

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func settle() -> void:
	for frame in range(5):
		await process_frame

func click(name: String) -> void:
	var control := current_scene.find_child(name, true, false) as Button
	check(control != null and not control.disabled, "Unavailable button: " + name)
	if control != null and not control.disabled:
		control.pressed.emit()
	await settle()

func _run() -> void:
	state = root.get_node("GameState")
	saves = root.get_node("SaveService")
	router = root.get_node("SceneRouter")
	var isolated_home := OS.get_environment("XDG_DATA_HOME").trim_suffix("/")
	if OS.get_environment("HORIZON_TEST_ISOLATED") != "1" or isolated_home.is_empty() or not ProjectSettings.globalize_path(state.SAVE_PATH).begins_with(isolated_home + "/"):
		printerr("Run with an isolated XDG_DATA_HOME and HORIZON_TEST_ISOLATED=1")
		quit(2)
		return
	router.go_to(&"menu")
	await settle()
	if "--reload" in OS.get_cmdline_user_args():
		check(saves.has_profile(), "Profile did not survive process restart")
		check(state.settings["master"] == 0.0 and state.settings["fps"] == 30, "Settings lost on restart")
		check(state.settings["reduce_motion"] and state.settings["quality"] == "low", "Accessibility/quality lost")
		check(state.profile["route"] == "earth", "Playable Earth route lost")
		await click("Continue")
		check(current_scene.name == "Earth", "Continue did not restore Earth after restart")
		_finish("restart + exact saved route/settings")
		return
	check(not saves.has_existing_files(), "Test directory must start empty")
	check(current_scene.find_child("Continue", true, false).disabled, "Continue enabled with no save")
	await click("Settings")
	var settings_scene := current_scene
	settings_scene._sliders["master"].value = 25
	await click("Back")
	check(is_equal_approx(float(state.settings["master"]), 0.8), "Cancel changed settings")
	check(not saves.has_existing_files(), "Cancel created a save")
	await click("Settings")
	settings_scene = current_scene
	settings_scene._sliders["master"].value = 0
	settings_scene._sliders["music"].value = 42
	settings_scene._sliders["sfx"].value = 23
	settings_scene._sliders["ambience"].value = 18
	settings_scene._draft["fps"] = 30
	settings_scene._draft["reduce_motion"] = true
	settings_scene._draft["quality"] = "low"
	settings_scene._draft["vibration"] = false
	await click("SaveSettings")
	check(state.settings["master"] == 0.0 and FileAccess.file_exists(state.SAVE_PATH), "Settings were not persisted")
	check(AudioServer.is_bus_mute(AudioServer.get_bus_index("Master")), "Master mute not applied")
	check(Engine.max_fps == 30, "FPS limit not applied")
	await click("Back")
	check(not saves.has_profile() and current_scene.find_child("Continue", true, false).disabled, "Settings-only save enabled Continue")
	await click("NewGame")
	check(current_scene.name == "Intro", "New Game did not open intro")
	if current_scene.name != "Intro":
		_finish("new game failed")
		return
	var profile_id: String = state.profile["profile_id"]
	check(state.profile["money_cents"] == 0 and state.profile["inventory"]["iron_ore"] == 0, "Invented starter resources")
	await click("Next")
	check(state.profile["story"]["line"] == 1, "Dialogue progress not committed")
	await click("Menu")
	await click("Continue")
	check(current_scene.name == "Intro" and state.profile["story"]["line"] == 1, "Continue lost dialogue position")
	await click("Menu")
	var before_cancel := FileAccess.get_file_as_string(state.SAVE_PATH)
	await click("NewGame")
	check(current_scene.has_node("ConfirmNewGame"), "Missing replacement warning")
	check(current_scene.find_child("NewGame", true, false).disabled and current_scene.find_child("Continue", true, false).disabled, "Modal left underlying buttons focusable")
	await click("CancelReplace")
	check(not current_scene.find_child("NewGame", true, false).disabled, "Cancel left menu disabled")
	check(state.profile["profile_id"] == profile_id and state.profile["story"]["line"] == 1, "Cancel replaced previous profile")
	check(FileAccess.get_file_as_string(state.SAVE_PATH) == before_cancel, "Cancel changed save bytes")
	await click("NewGame")
	await click("ConfirmReplace")
	check(state.profile["profile_id"] != profile_id and state.profile["story"]["line"] == 0, "Confirmed new game did not reset profile")
	check(state.settings["master"] == 0.0, "New Game reset preferences")
	await click("Skip")
	check(current_scene.name == "Earth" and state.profile["story"]["intro_seen"], "Skip failed")
	check(state.profile["money_cents"] == 0 and state.profile["shards"] == 0, "Intro granted unapproved rewards")
	await click("Menu")
	await click("Continue")
	check(current_scene.name == "Earth", "Continue did not resume Earth")
	_finish("menu, settings cancel/save, audio/FPS, new/continue, dialogue, replacement cancel/confirm, skip")

func _finish(summary: String) -> void:
	if failures.is_empty():
		print("STAGE 1 UI PASS: " + summary)
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: " + failure)
		quit(1)
