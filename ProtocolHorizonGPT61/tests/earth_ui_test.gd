extends SceneTree

var failures: PackedStringArray = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var state := root.get_node("GameState")
	var saves := root.get_node("SaveService")
	var session := root.get_node("GameSession")
	var router := root.get_node("SceneRouter")
	var home := OS.get_environment("XDG_DATA_HOME").trim_suffix("/")
	if OS.get_environment("HORIZON_TEST_ISOLATED") != "1" or home.is_empty() or not ProjectSettings.globalize_path(state.SAVE_PATH).begins_with(home + "/"):
		printerr("A disposable isolated user-data directory is required")
		quit(2)
		return
	if saves.new_game() != OK or not session.prepare():
		printerr("Could not initialize UI test profile")
		quit(1)
		return
	session.set_process(false)
	# Late-game fixture is confined to this test user-data, never the playable default.
	var p: Dictionary = state.profile.duplicate(true)
	p["money_cents"] = 10000000
	p["story"]["intro_seen"] = true
	p["route"] = "earth"
	p["game"]["progression"]["story_done"]["A06"] = true
	p["game"]["progression"]["story_done"]["A13"] = true
	p["game"]["progression"]["geology"]["guaranteed_geobinding"] = true
	p["game"]["progression"]["geology"]["reports"] = [{"id":"GEO-QA-1","tags":[]},{"id":"GEO-QA-2","tags":[]}]
	p["game"]["progression"]["buildings"]["deep_station"] = {"status":"complete","remaining_seconds":0.0}
	p["game"]["stats"]["produced:steel"] = 1.0
	p["game"]["stats"]["produced:pd_catalyst"] = 1.0
	p["game"]["sites"]["fe"]["peak"] = 350
	session._refresh(p)
	if saves.commit_profile(p) != OK:
		printerr("Could not save UI fixture")
		quit(1)
		return
	router.go_to(&"earth")
	for frame in range(8):
		await process_frame
	if current_scene == null or current_scene.name != "Earth":
		printerr("Earth scene failed to open")
		quit(1)
		return
	var screen := current_scene
	for tab in screen.TABS:
		screen.go(tab, "fe")
		await process_frame
		if screen._body.get_child_count() < 2:
			failures.append("Empty game page: " + tab)
	for site in ["pd", "ir"]:
		for tab in ["mine","upgrades","machines","workers","equipment"]:
			screen.go(tab, site)
			await process_frame
			if screen._body.get_child_count() < 2:
				failures.append("Empty site page: " + site + "/" + tab)
	if failures.is_empty():
		print("EARTH UI PASS: 23 pages plus Pd/Ir mining, upgrades, workers, machines, equipment")
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: " + failure)
		quit(1)
