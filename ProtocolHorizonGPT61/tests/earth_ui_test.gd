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
	p["game"]["offline_report"] = {"id":"GEO-QA-OFFLINE-1", "seconds":7260, "money_cents":1250, "materials":{"iron_ore":4}}
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
	screen.go("expansion", "fe")
	await process_frame
	var report_button := screen._body.find_child("AcknowledgeOfflineReport", true, false) as Button
	if report_button == null or not _has_label_text(screen._body, "применены один раз"):
		failures.append("Offline report details or acknowledgement button missing")
	else:
		var money_before := int(state.profile["money_cents"])
		var inventory_before: Dictionary = state.profile["inventory"].duplicate(true)
		report_button.emit_signal("pressed")
		await process_frame
		if GameMath.game(state.profile).has("offline_report"):
			failures.append("Offline report acknowledgement did not dismiss the report")
		if int(state.profile["money_cents"]) != money_before or state.profile["inventory"] != inventory_before:
			failures.append("Offline report acknowledgement applied rewards again")
	if failures.is_empty():
		print("EARTH UI PASS: 23 pages, Pd/Ir site views, and one-time offline report acknowledgement")
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: " + failure)
		quit(1)

func _has_label_text(node: Node, phrase: String) -> bool:
	if node is Label and str(node.text).contains(phrase):
		return true
	for child in node.get_children():
		if _has_label_text(child, phrase):
			return true
	return false
