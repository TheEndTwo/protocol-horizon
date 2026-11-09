extends SceneTree

var failures: PackedStringArray = []
var state: Node
var session: Node
var saves: Node

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func _isolated() -> bool:
	var home := OS.get_environment("XDG_DATA_HOME").trim_suffix("/")
	return OS.get_environment("HORIZON_TEST_ISOLATED") == "1" and not home.is_empty() and ProjectSettings.globalize_path(state.SAVE_PATH).begins_with(home + "/")

func _run() -> void:
	state = root.get_node("GameState")
	session = root.get_node("GameSession")
	saves = root.get_node("SaveService")
	if not _isolated():
		printerr("Use a disposable XDG_DATA_HOME and HORIZON_TEST_ISOLATED=1")
		quit(2)
		return
	if "--reload" in OS.get_cmdline_user_args():
		check(saves.has_profile(), "Profile was not restored")
		check(session.prepare(), "Could not prepare restored game")
		check(state.profile.get("route") == "earth", "Earth route was lost")
		check(state.profile["game"].has("sites"), "Game state missing after restart")
		check(state.profile["money_cents"] >= 0, "Money became negative")
		_finish("separate process save/load")
		return
	check(not saves.has_profile(), "Session test requires clean user-data")
	check(saves.new_game() == OK, "Could not create isolated profile")
	check(session.prepare(), "Could not initialize earth models")
	if not failures.is_empty():
		_finish("initialization failed")
		return
	var profile_id: String = state.profile["profile_id"]
	check(GameMath.unlocked(state.profile, "fe") and not GameMath.unlocked(state.profile,"pd"), "Starter unlock rules")
	var initial_ore := int(state.profile["inventory"]["iron_ore"])
	var tap: Dictionary = session.perform("economy", "tap", {"site":"fe", "precision":false})
	check(tap.get("ok",false), "Zero-money free tap failed")
	check(int(state.profile["inventory"]["iron_ore"]) > initial_ore, "Tap produced no real iron")
	var sale: Dictionary = session.perform("economy", "sell", {"resource":"iron_ore", "amount":-1})
	check(sale.get("ok",false) and state.profile["money_cents"] > 0, "Free iron sale failed")
	var cents: int = state.profile["money_cents"]
	var invalid: Dictionary = session.perform("economy", "queue", {"recipe":"not_a_recipe", "line":0,"count":1})
	check(not invalid.get("ok",true) and state.profile["money_cents"] == cents, "Invalid transaction changed money")
	check(session.navigate("mine", "fe") == OK, "Could not save current scene")
	check(state.profile["game"]["ui"]["tab"] == "mine", "Saved subscene mismatch")
	check(absi(int(Time.get_unix_time_from_system())-int(state.profile["game"]["last_saved_ts"])) <= 1,"Navigation saved progress with a stale offline timestamp")
	check(state.profile["profile_id"] == profile_id, "Gameplay replaced profile identity")
	# A paused process gets one committed offline calculation, not a reward-on-view.
	var before: Dictionary = state.profile.duplicate(true)
	before["game"]["last_saved_ts"] = int(Time.get_unix_time_from_system()) - 120
	check(saves.commit_profile(before) == OK, "Could not prepare offline fixture")
	session._profile_id = ""
	check(session.prepare(), "Offline processing failed")
	var report: Dictionary = state.profile["game"].get("offline_report", {})
	check(int(report.get("seconds",0)) >= 120, "Offline report not generated")
	var after: Dictionary = state.profile.duplicate(true)
	check(session.prepare(), "Second view failed")
	check(state.profile["inventory"] == after["inventory"] and state.profile["money_cents"] == after["money_cents"], "Offline rewards duplicated")
	session.dismiss_offline()
	check(not state.profile["game"].has("offline_report"), "Report dismissal not saved")
	session.notification(MainLoop.NOTIFICATION_APPLICATION_PAUSED)
	var backgrounded: Dictionary = state.profile.duplicate(true)
	backgrounded["game"]["last_saved_ts"] = int(Time.get_unix_time_from_system()) - 180
	check(saves.commit_profile(backgrounded) == OK, "Could not prepare background-resume fixture")
	session.notification(MainLoop.NOTIFICATION_APPLICATION_RESUMED)
	check(int(state.profile["game"].get("offline_report", {}).get("seconds", 0)) >= 180, "Resume did not calculate background production")
	var resumed: Dictionary = state.profile.duplicate(true)
	session.notification(MainLoop.NOTIFICATION_APPLICATION_RESUMED)
	check(state.profile["inventory"] == resumed["inventory"] and state.profile["money_cents"] == resumed["money_cents"], "Repeated resume applied background production twice")
	_test_bound_research_reserve()
	check(session.flush() == OK, "Final persistence failed")
	check(GameMath.valid_game(state.profile["game"]), "Game shape is invalid")
	_finish("new game, free tap/sale, rollback, routes, one-time offline, persistence")

func _test_bound_research_reserve() -> void:
	var p: Dictionary = state.profile.duplicate(true)
	p["money_cents"] = 100000
	p["story"]["intro_seen"] = true
	p["route"] = "earth"
	var g := GameMath.game(p)
	g["progression"]["story_done"]["A06"] = true
	g["progression"]["story_done"]["A13"] = true
	g["progression"]["geology"]["guaranteed_geobinding"] = true
	g["progression"]["geology"]["reports"] = [{"id":"BIND-QA-1","tags":[]},{"id":"BIND-QA-2","tags":[]}]
	g["progression"]["buildings"]["deep_station"] = {"status":"complete","remaining_seconds":0.0}
	g["progression"]["buildings"]["factory"] = {"status":"complete","remaining_seconds":0.0}
	g["stats"]["produced:steel"] = 1.0
	g["stats"]["produced:pd_catalyst"] = 1.0
	g["sites"]["fe"]["peak"] = 350
	g["progression"]["research"]["IR26"] = 1
	for resource in {"steel":1,"pd_catalyst":1,"ir_refined":1,"high_strength_alloy":2}:
		p["inventory"][resource] = {"steel":1,"pd_catalyst":1,"ir_refined":1,"high_strength_alloy":2}[resource]
	session._refresh(p)
	check(saves.commit_profile(p) == OK, "Could not save the isolated bound-reserve fixture")
	var reserve: Dictionary = session.perform("research", "reserve_items", {"id":"IR26", "items":{"steel":1,"pd_catalyst":1}})
	check(reserve.get("ok", false), "Could not bind existing inputs to the next thermal contact: " + str(reserve))
	var before: Dictionary = state.profile.duplicate(true)
	var rejected: Dictionary = session.perform("economy", "queue", {"recipe":"R_IR_CONTACT","line":0,"count":1000})
	check(not rejected.get("ok", true) and state.profile["inventory"] == before["inventory"] and GameMath.game(state.profile)["reservations"] == GameMath.game(before)["reservations"] and state.profile["money_cents"] == before["money_cents"], "Failed contact request released its committed reserve or changed the ledger")
	var queued: Dictionary = session.perform("economy", "queue", {"recipe":"R_IR_CONTACT","line":0,"count":1})
	check(queued.get("ok", false), "The next real contact batch could not consume its bound reserve: " + str(queued))

func _finish(label: String) -> void:
	if failures.is_empty():
		print("EARTH SESSION PASS: " + label)
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: " + failure)
		quit(1)
