extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if GameMath.offline_seconds(0, 100000, 0) != 14400 or GameMath.offline_seconds(0, 100000, 20) != 43200 or GameMath.offline_seconds(0, 100000, 50) != 86400 or GameMath.offline_seconds(100, 0, 0) != 0:
		printerr("FAIL: offline caps or backwards-clock handling changed")
		quit(1)
		return
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
	var worker_case: Dictionary = state.profile.duplicate(true)
	worker_case["game"]["sites"]["fe"]["workers"]["iron_miner"] = 5
	worker_case["money_cents"] = 0
	worker_case["game"]["network"] = {"mode":"income","autosell":true}
	var whole_workers := worker_case.duplicate(true)
	var split_workers := worker_case.duplicate(true)
	session.simulate(whole_workers,240)
	for second in range(240):
		session.simulate(split_workers,1)
	if whole_workers["inventory"] != split_workers["inventory"] or whole_workers["money_cents"] != split_workers["money_cents"]:
		printerr("FAIL: adaptive offline changed wages/autosale at zero balance")
		printerr([whole_workers["inventory"],split_workers["inventory"],whole_workers["money_cents"],split_workers["money_cents"]])
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
