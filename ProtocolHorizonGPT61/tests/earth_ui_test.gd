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
	p["game"]["progression"]["buildings"]["factory"] = {"status":"complete","remaining_seconds":0.0}
	p["game"]["stats"]["produced:steel"] = 1.0
	p["game"]["stats"]["produced:pd_catalyst"] = 1.0
	p["game"]["sites"]["fe"]["peak"] = 350
	p["game"]["offline_report"] = {"id":"GEO-QA-OFFLINE-1", "seconds":7260, "money_cents":1250, "materials":{"iron_ore":4}}
	if "--all-research" in OS.get_cmdline_user_args():
		p["game"]["progression"]["story_done"]["A08"] = true
		p["game"]["progression"]["story_done"]["A14"] = true
		for row in GameMath.records("research"):
			p["game"]["progression"]["research"][row["id"]] = 1
		for row in GameMath.records("mastery"):
			p["game"]["progression"]["mastery"][row["id"]] = 1
	session._refresh(p)
	var visual_page := ""
	var visual_site := "fe"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--visual-page="):
			visual_page = arg.trim_prefix("--visual-page=")
		if arg.begins_with("--visual-site="):
			visual_site = arg.trim_prefix("--visual-site=")
	if not visual_page.is_empty():
		p["game"]["qa_fixture"] = true
		p["game"]["ui"] = {"tab":visual_page,"site":visual_site}
		p["active_site"] = GameMath.SITE_IDS.get(visual_site,GameMath.SITE_IDS["fe"])
		for kind in ["machines","workers"]:
			for definition in session.model("economy").definitions("fe",kind):
				var purchase: Dictionary = session.model("economy").act(p,"buy",{"site":"fe","kind":kind,"id":definition["id"],"count":1})
				if not purchase.get("ok",false):
					printerr("Could not prepare visible purchased objects")
					quit(1)
					return
		p["inventory"]["case_basic"] = 3
	if saves.commit_profile(p) != OK:
		printerr("Could not save UI fixture")
		quit(1)
		return
	if not visual_page.is_empty():
		print("Prepared labeled QA visual profile: " + visual_page + "/" + visual_site)
		quit(0)
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
		for frame in range(3):
			await process_frame
		if screen._body.get_child_count() < 2:
			failures.append("Empty game page: " + tab)
		if screen._body.size.x > screen._scroll.size.x + 1:
			failures.append("Game page overflows the portrait viewport: " + tab)
	for site in ["pd", "ir"]:
		for tab in ["mine","upgrades","machines","workers","equipment"]:
			screen.go(tab, site)
			await process_frame
			if screen._body.get_child_count() < 2:
				failures.append("Empty site page: " + site + "/" + tab)
			if tab == "mine" and "--all-research" in OS.get_cmdline_user_args():
				var readouts := ["PD_SK03", "PD_SK04"] if site == "pd" else ["IR_SK01", "IR_SK02", "IR_SK03"]
				for id in readouts:
					if screen._body.find_child("Readout" + id, true, false) == null:
						failures.append("Mastery readout is not visible in its site: " + id)
	if "--all-research" in OS.get_cmdline_user_args():
		var drill: Dictionary = session.perform("economy", "buy", {"site":"fe", "kind":"machines", "id":"iron_drill", "count":1})
		var cosmetic: Dictionary = session.perform("features", "org_set_factory_cosmetic", {"id":"A16", "cosmetic":"steel"})
		if not drill.get("ok", false) or not cosmetic.get("ok", false):
			failures.append("Could not select an earned factory appearance after a real machine purchase")
		screen.go("base", "fe")
		await process_frame
		if screen._canvas._factory_icon == null or screen._canvas._factory_icon.modulate != Color("a5cee0"):
			failures.append("Saved factory appearance did not affect the visible base building")
		screen.go("mine", "fe")
		await process_frame
		screen._canvas.mine_hit.emit(Vector2(150, 130))
		if screen._canvas.find_child("MinedAmount", true, false) == null:
			failures.append("A real mine hit did not display its local mined amount")
		var separator: Dictionary = session.perform("economy", "buy", {"site":"pd", "kind":"machines", "id":"pd_separator", "count":1})
		if not separator.get("ok", false):
			failures.append("Could not purchase the machine required by express crushing")
		screen.go("mine", "pd")
		var express := screen._body.find_child("PdCrushingexpress", true, false) as Button
		if express == null:
			failures.append("PD09 did not expose a real alternative crushing schedule")
		else:
			express.pressed.emit()
			for frame in range(3):
				await process_frame
			if session.model("sites").view(state.profile, "pd").get("crushing_schedule") != "express":
				failures.append("PD09 visible schedule did not save its selection")
		var sampled: Dictionary = session.perform("sites", "pd_take_sample", {})
		if not sampled.get("ok", false):
			failures.append("Could not start a real UI sample")
		else:
			screen.refresh()
			session.simulate(state.profile, 60)
			screen._process(0.5)
			for frame in range(3):
				await process_frame
			var spectrum := screen._body.find_child("PdSpectrum0", true, false) as Button
			if spectrum == null:
				failures.append("Completed sampling did not reveal the spectral analysis controls")
			else:
				spectrum.pressed.emit()
				await process_frame
				if session.model("sites").view(state.profile, "pd").get("sample", {}).get("analysis_selected_band_id", "") != "spectrum_a":
					failures.append("The visible spectral analysis did not commit its choice")
				session.simulate(state.profile, 60)
				if not session.model("sites").view(state.profile, "pd").get("sample", {}).get("analysis_completed", false):
					failures.append("The visible spectral analysis did not finish its real timer")
		await _exercise_collection_cosmetics(screen, session, state)
		for catalog_page in ["research", "mastery"]:
			screen.go(catalog_page, "ir")
			await process_frame
			_check_feature_choices(screen._body)
		var cooling := screen._body.find_child("FeatureInputIR_SK06cooling_mode_id", true, false) as OptionButton
		var apply := screen._body.find_child("FeatureIR_SK06industry_set_cooling_mode", true, false) as Button
		if cooling == null or cooling.item_count < 2 or apply == null:
			failures.append("Ir cooling mastery is not exposed through the shared feature controls")
		else:
			cooling.select(1)
			var selected: Variant = cooling.get_item_metadata(1)
			apply.pressed.emit()
			await process_frame
			var actual: Dictionary = session.model("sites").view(state.profile, "ir")
			if actual.get("cooling_mode_id") != selected:
				failures.append("Feature select did not submit the real industrial choice ID")
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
	root.get_node("AudioService").stop_all()
	await create_timer(0.06).timeout
	if failures.is_empty():
		print("EARTH UI PASS: 23 pages, Pd/Ir site views, and one-time offline report acknowledgement")
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: " + failure)
		quit(1)

func _check_feature_choices(node: Node) -> void:
	if node is OptionButton and str(node.name).begins_with("FeatureInput"):
		for index in range(node.item_count):
			if node.get_item_metadata(index) == null:
				failures.append("Feature choice lost its action ID: " + str(node.name))
	for child in node.get_children():
		_check_feature_choices(child)

func _exercise_collection_cosmetics(screen: Control, session: Node, state: Node) -> void:
	for cycle in range(2):
		if cycle > 0:
			if not session.perform("sites", "pd_take_sample", {}).get("ok", false):
				failures.append("Could not prepare a real Pd cosmetic milestone")
				return
			session.simulate(state.profile, 60)
		if not session.perform("sites", "pd_start_cycle", {}).get("ok", false):
			failures.append("Could not run the actual Pd cosmetic milestone cycle")
			return
		session.simulate(state.profile, 200)
	if not session.perform("research", "complete_task", {"id":"PD30"}).get("ok", false):
		failures.append("Actual Pd cycles did not unlock the one-time appearance")
		return
	screen.go("research", "pd")
	await process_frame
	var apply := screen._body.find_child("CosmeticApplyPD30", true, false) as Button
	if apply == null:
		failures.append("Earned factory appearance has no native Apply control")
		return
	var cash_before := int(state.profile["money_cents"])
	var inventory_before: Dictionary = state.profile["inventory"].duplicate(true)
	apply.pressed.emit()
	await process_frame
	if state.profile["money_cents"] != cash_before or state.profile["inventory"] != inventory_before:
		failures.append("A cosmetic selection changed currencies or physical materials")
	screen.go("base", "fe")
	await process_frame
	if screen._canvas._factory_icon.modulate != Color("8bd7bf"):
		failures.append("The earned Pd factory appearance did not change the visible building")
	screen.go("research", "pd")
	await process_frame
	var clear := screen._body.find_child("CosmeticClearPD30", true, false) as Button
	if clear == null:
		failures.append("Earned appearance has no native reset control")
		return
	clear.pressed.emit()
	await process_frame
	screen.go("base", "fe")
	await process_frame
	if screen._canvas._factory_icon.modulate != Color("a5cee0"):
		failures.append("Clearing the research appearance did not restore the chosen ordinary factory finish")
	if not session.perform("sites", "ir_start_campaign", {"strategy_id":"reliable"}).get("ok", false):
		failures.append("Could not start the real Ir appearance milestone")
		return
	session.simulate(state.profile, 500)
	if not session.perform("research", "complete_task", {"id":"IR30"}).get("ok", false):
		failures.append("A real Ir campaign did not unlock its one-time appearance")
		return
	screen.go("research", "ir")
	await process_frame
	apply = screen._body.find_child("CosmeticApplyIR30", true, false) as Button
	if apply == null:
		failures.append("Earned Ir rig appearance has no native Apply control")
		return
	apply.pressed.emit()
	await process_frame
	screen.go("mine", "ir")
	await process_frame
	if screen._canvas._active_ir_cosmetic != "ir30_depth_chronicle_rig" or screen._canvas._background_image.modulate != Color("a7d6e2"):
		failures.append("The earned Ir appearance did not affect the visible drill scene")

func _has_label_text(node: Node, phrase: String) -> bool:
	if node is Label and str(node.text).contains(phrase):
		return true
	for child in node.get_children():
		if _has_label_text(child, phrase):
			return true
	return false
