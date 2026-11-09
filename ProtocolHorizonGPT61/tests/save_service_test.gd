extends SceneTree

const SaveServiceScript = preload("res://autoload/SaveService.gd")
const GameStateScript = preload("res://autoload/GameState.gd")
var failures: PackedStringArray = []
var save_service: Variant
var state: Variant

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func _run() -> void:
	state = root.get_node("GameState")
	var save_path: String = state.SAVE_PATH
	var isolated_home := OS.get_environment("XDG_DATA_HOME")
	var isolated_opt_in := OS.get_environment("HORIZON_TEST_ISOLATED")
	var absolute_save_path := ProjectSettings.globalize_path(save_path)
	var expected_prefix := isolated_home.trim_suffix("/") + "/ProtocolHorizonGPT61/"
	if isolated_opt_in != "1" or isolated_home.is_empty() or not absolute_save_path.begins_with(expected_prefix):
		printerr("Refusing to run destructive save tests without HORIZON_TEST_ISOLATED=1 and a matching disposable XDG_DATA_HOME.")
		printerr("Expected save below: " + expected_prefix)
		printerr("Resolved save: " + absolute_save_path)
		quit(2)
		return
	print("SAVE_TEST_PATH=" + absolute_save_path)
	_cleanup_files()
	state.current_route = &"menu"
	_restart_service()
	check(not save_service.has_profile(), "Empty install unexpectedly has a profile")
	check(not save_service.has_existing_files(), "Empty install unexpectedly has save files")
	check(not save_service.requires_reset_confirmation(), "Empty install requested reset confirmation")
	check(state.profile.is_empty(), "Empty install profile is not empty")
	check(state.settings == GameStateScript.default_settings(), "Default settings differ")

	var custom_settings: Dictionary = GameStateScript.default_settings()
	custom_settings["master"] = 0.25
	custom_settings["music"] = 0.4
	custom_settings["sfx"] = 0.7
	custom_settings["ambience"] = 0.3
	custom_settings["vibration"] = false
	custom_settings["quality"] = "low"
	custom_settings["fps"] = 30
	custom_settings["reduce_motion"] = true
	check(save_service.save_settings(custom_settings) == OK, "Settings-only save failed: " + save_service.status_message)
	check(not save_service.has_profile(), "Settings-only file enabled Continue")
	check(save_service.has_existing_files(), "Settings-only file was not detected")
	check(not save_service.requires_reset_confirmation(), "Settings-only file requested reset confirmation")
	_restart_service()
	check(not save_service.has_profile(), "Settings-only reload enabled Continue")
	check(state.settings == custom_settings, "Settings-only roundtrip failed")
	check(state.current_route == &"menu", "Loading persistence changed the UI route")
	var cancelled_save_bytes := _read_text(save_path)
	check(not save_service.has_profile() and _read_text(save_path) == cancelled_save_bytes, "A cancelled New Game changed the save")

	var second_profile: Dictionary = GameStateScript.make_new_profile()
	check(second_profile["profile_id"] != GameStateScript.make_new_profile()["profile_id"], "Profile IDs were not unique")
	var new_game_result: Error = save_service.new_game()
	check(new_game_result == OK, "New Game save failed: " + save_service.status_message)
	if not save_service.has_profile():
		for failure in failures:
			printerr("FAIL: " + failure)
		printerr("New Game status: " + save_service.status_message)
		quit(1)
		return
	check(save_service.has_profile(), "New Game did not enable Continue")
	check(save_service.requires_reset_confirmation(), "Existing profile did not require reset confirmation")
	check(state.settings == custom_settings, "New Game did not preserve settings")
	check(state.profile["money_cents"] == 0 and state.profile["shards"] == 0 and state.profile["research_points"] == 0, "New profile currency was not zero")
	check(state.profile["inventory"] == {"iron_ore": 0}, "New profile inventory differs")
	check(state.profile["active_site"] == "site_earth_fe_17", "Wrong starter site")
	check(state.profile["sites"]["site_earth_fe_17"]["unlocked"] and not state.profile["sites"]["site_earth_pd_7"]["unlocked"] and not state.profile["sites"]["site_earth_ir_9"]["unlocked"], "Starter site unlocks differ")
	check(state.profile["local"]["lifetime_peak"] == 0, "Starter lifetime peak was not zero")
	check(state.profile["local"]["upgrades"].is_empty() and state.profile["local"]["machines"].is_empty() and state.profile["local"]["workers"].is_empty() and state.profile["local"]["equipment"].is_empty(), "Starter local state invented IDs")
	check(state.profile["route"] == "intro" and state.profile["story"] == {"current_id": "A01", "line": 0, "intro_seen": false}, "Starter route/story differs")
	var original_profile_id: String = state.profile["profile_id"]
	var unchanged_profile_id: String = state.profile["profile_id"]
	var unchanged_save_bytes := _read_text(save_path)
	check(state.profile["profile_id"] == unchanged_profile_id and _read_text(save_path) == unchanged_save_bytes, "No-op cancellation changed the profile")

	var checkpoint_profile: Dictionary = state.profile.duplicate(true)
	checkpoint_profile["route"] = "checkpoint"
	checkpoint_profile["story"]["line"] = 3
	checkpoint_profile["story"]["intro_seen"] = true
	check(save_service.commit_profile(checkpoint_profile) == OK, "Checkpoint commit failed: " + save_service.status_message)
	check(state.profile["profile_id"] == original_profile_id, "Commit changed the profile ID")
	check(state.current_route == &"menu", "Profile commit changed the UI route")
	var backup_before_recovery := _read_text(save_path + ".bak")
	check(not backup_before_recovery.is_empty(), "Second valid write did not create a backup")
	_restart_service()
	check(save_service.has_profile(), "Continue missing after checkpoint reload")
	check(state.profile["route"] == "checkpoint" and state.profile["story"]["line"] == 3 and state.profile["story"]["intro_seen"], "Checkpoint/story position did not roundtrip")
	check(state.current_route == &"menu", "Reload routed into the game automatically")

	_write_text(save_path, "{broken primary")
	_restart_service()
	check(save_service.recovered_from_backup, "Corrupt primary did not recover from backup")
	check(save_service.has_profile(), "Backup recovery did not restore a profile")
	check(state.profile["route"] == "intro" and state.profile["story"]["line"] == 0, "Recovery did not load the valid backup state")
	var recovered_settings: Dictionary = state.settings.duplicate(true)
	recovered_settings["master"] = 0.55
	check(save_service.save_settings(recovered_settings) == OK, "Save after backup recovery failed: " + save_service.status_message)
	check(_read_text(save_path + ".bak") == backup_before_recovery, "Corrupt primary replaced the valid backup")
	check(not save_service.recovered_from_backup, "Successful write left the service marked as recovered")
	_restart_service()
	check(not save_service.recovered_from_backup and save_service.has_profile(), "Recovered save was not committed as primary")
	check(state.settings["master"] == 0.55 and state.profile["route"] == "intro", "Recovered state did not persist")

	var invalid_fixtures: Array[Dictionary] = []
	var future := _make_envelope(GameStateScript.default_settings(), {})
	future["schema_version"] = 2
	invalid_fixtures.append({"name": "future schema", "json": JSON.stringify(future)})
	var invalid_route_profile: Dictionary = GameStateScript.make_new_profile()
	invalid_route_profile["route"] = "menu"
	invalid_fixtures.append({"name": "invalid profile route", "json": JSON.stringify(_make_envelope(GameStateScript.default_settings(), invalid_route_profile))})
	var invalid_settings: Dictionary = GameStateScript.default_settings()
	invalid_settings["master"] = 1.5
	invalid_fixtures.append({"name": "invalid settings", "json": JSON.stringify(_make_envelope(invalid_settings, {}))})
	var invalid_story_profile: Dictionary = GameStateScript.make_new_profile()
	invalid_story_profile["story"]["line"] = 5
	invalid_fixtures.append({"name": "story line out of range", "json": JSON.stringify(_make_envelope(GameStateScript.default_settings(), invalid_story_profile))})
	invalid_fixtures.append({"name": "malformed JSON", "json": "{broken"})
	for fixture in invalid_fixtures:
		_cleanup_files()
		_write_text(save_path, fixture["json"])
		var original_bytes := _read_text(save_path)
		_restart_service()
		check(not save_service.has_profile(), "%s unexpectedly enabled Continue" % fixture["name"])
		check(save_service.has_existing_files(), "%s file was not detected" % fixture["name"])
		check(save_service.requires_reset_confirmation(), "%s did not require reset confirmation" % fixture["name"])
		var attempted_settings: Dictionary = GameStateScript.default_settings()
		attempted_settings["master"] = 0.1
		check(save_service.save_settings(attempted_settings) != OK, "%s was overwritten by settings" % fixture["name"])
		check(_read_text(save_path) == original_bytes, "%s changed after rejected settings write" % fixture["name"])

	_cleanup_files()
	var future_profile: Dictionary = GameStateScript.make_new_profile()
	future_profile["route"] = "checkpoint"
	var future_primary := _make_envelope(GameStateScript.default_settings(), future_profile)
	future_primary["schema_version"] = 2
	var compatible_settings: Dictionary = GameStateScript.default_settings()
	compatible_settings["master"] = 0.2
	var compatible_backup := JSON.stringify(_make_envelope(compatible_settings, GameStateScript.make_new_profile()))
	var future_primary_bytes := JSON.stringify(future_primary)
	_write_text(save_path, future_primary_bytes)
	_write_text(save_path + ".bak", compatible_backup)
	_restart_service()
	check(not save_service.has_profile(), "Future primary enabled Continue through backup fallback")
	check(not save_service.recovered_from_backup, "Future primary was reported as backup recovery")
	check(save_service.requires_reset_confirmation(), "Future primary did not request explicit reset confirmation")
	check(state.settings == GameStateScript.default_settings(), "Settings were silently loaded from backup under future schema")
	check(save_service.save_settings(compatible_settings) != OK, "Settings write replaced a future-schema primary")
	var blocked_profile: Dictionary = GameStateScript.make_new_profile()
	blocked_profile["route"] = "checkpoint"
	check(save_service.commit_profile(blocked_profile) != OK, "Profile commit replaced a future-schema primary")
	check(_read_text(save_path) == future_primary_bytes, "Future-schema primary changed during settings save")
	check(_read_text(save_path + ".bak") == compatible_backup, "Future-schema backup changed during settings save")
	check(save_service.new_game() == OK, "Explicit New Game could not replace a future-schema save: " + save_service.status_message)
	check(save_service.has_profile() and state.profile["route"] == "intro", "Explicit New Game did not create a fresh profile")
	check(_read_text(save_path + ".bak") == compatible_backup, "Explicit New Game overwrote the compatible backup")

	_cleanup_files()
	_restart_service()
	var baseline_settings: Dictionary = GameStateScript.default_settings()
	baseline_settings["master"] = 0.35
	check(save_service.save_settings(baseline_settings) == OK, "Could not prepare write-failure fixture")
	check(save_service.new_game() == OK, "Could not prepare profile write-failure fixture")
	var profile_before_failure: Dictionary = state.profile.duplicate(true)
	var candidate_profile: Dictionary = state.profile.duplicate(true)
	candidate_profile["route"] = "checkpoint"
	candidate_profile["story"]["line"] = 4
	var primary_before_failure := _read_text(save_path)
	var changed_settings: Dictionary = baseline_settings.duplicate(true)
	changed_settings["master"] = 0.9
	var blocked_temp_path := ProjectSettings.globalize_path(save_path + ".tmp")
	check(DirAccess.make_dir_absolute(blocked_temp_path) == OK, "Could not create write-failure fixture")
	check(save_service.save_settings(changed_settings) != OK, "Write failure reported success")
	check(_read_text(save_path) == primary_before_failure, "Precommit write failure changed primary")
	check(state.settings == baseline_settings, "Failed settings write changed in-memory settings")
	check(save_service.commit_profile(candidate_profile) != OK, "Profile write failure reported success")
	check(_read_text(save_path) == primary_before_failure, "Failed profile commit changed primary")
	check(state.profile == profile_before_failure, "Failed profile commit changed in-memory profile")
	check(DirAccess.remove_absolute(blocked_temp_path) == OK, "Could not remove write-failure fixture")

	if failures.is_empty():
		print("SAVE SERVICE PASS: defaults, settings-only, new/continue, checkpoint, backup recovery, strict rejection, failed write")
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: " + failure)
		quit(1)

func _make_envelope(settings: Dictionary, profile: Dictionary) -> Dictionary:
	return {"schema_version": state.SCHEMA_VERSION, "settings": settings, "profile": profile}

func _restart_service() -> void:
	if save_service != null and is_instance_valid(save_service):
		root.remove_child(save_service)
		save_service.free()
	save_service = SaveServiceScript.new()
	root.add_child(save_service)

func _cleanup_files() -> void:
	for path in [state.SAVE_PATH, state.SAVE_PATH + ".bak", state.SAVE_PATH + ".tmp", state.SAVE_PATH + ".bak.tmp"]:
		var absolute_path := ProjectSettings.globalize_path(path)
		if FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(absolute_path):
			DirAccess.remove_absolute(absolute_path)

func _read_text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var content := file.get_as_text()
	file.close()
	return content

func _write_text(path: String, content: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		check(false, "Could not write test fixture: " + path)
		return
	file.store_string(content)
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	check(write_error == OK, "Could not flush test fixture: " + path)
