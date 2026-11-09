extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var state := root.get_node("GameState")
	var saves := root.get_node("SaveService")
	var session := root.get_node("GameSession")
	var home := OS.get_environment("XDG_DATA_HOME").trim_suffix("/")
	if OS.get_environment("HORIZON_TEST_ISOLATED") != "1" or home.is_empty() or not ProjectSettings.globalize_path(state.SAVE_PATH).begins_with(home+"/"):
		printerr("Disposable user-data required")
		quit(2)
		return
	if saves.new_game() != OK or not session.prepare():
		printerr("Could not initialize offline fixture")
		quit(1)
		return
	session.set_process(false)
	var long: Dictionary = state.profile.duplicate(true)
	var split: Dictionary = state.profile.duplicate(true)
	session.simulate(long,120)
	for step in range(12):
		session.simulate(split,10)
	if long["inventory"] != split["inventory"] or long["money_cents"] != split["money_cents"]:
		printerr("FAIL: online/offline step partition changed ledger")
		quit(1)
		return
	var p: Dictionary = state.profile.duplicate(true)
	p["game"]["offline_level"] = 50
	var started := Time.get_ticks_msec()
	session.simulate(p,86400)
	var elapsed := Time.get_ticks_msec()-started
	if int(p["inventory"]["iron_ore"]) <= 0 or p["money_cents"] < 0 or GameMath.stored(p)>GameMath.capacity(p):
		printerr("FAIL: 24h offline ledger or capacity invalid")
		quit(1)
		return
	print("OFFLINE PASS: same shared ledger for partitioned time; 24h simulated in %dms, Fe=%d, money=%d cents" % [elapsed,p["inventory"]["iron_ore"],p["money_cents"]])
	quit(0)
