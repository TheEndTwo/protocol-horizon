extends SceneTree

const Registry = preload("res://autoload/ContentRegistry.gd")
const State = preload("res://autoload/GameState.gd")
const GameMath = preload("res://gameplay/GameMath.gd")
const Economy = preload("res://gameplay/EconomyModel.gd")
const Mining = preload("res://gameplay/MiningFeatures.gd")
const Features = preload("res://gameplay/FeatureRuntime.gd")
const ResearchRuntime = preload("res://gameplay/ResearchRuntime.gd")

var failures: PackedStringArray = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	root.add_child(Registry.new())
	await process_frame
	_test_coverage_and_ownership()
	_test_marked_physical_contact()
	_test_pocket_open_route_and_budget()
	_test_precision_strikes_and_zone_choice()
	_test_manual_drill_order_shortens_one_cycle()
	_test_forecast_and_profiles()
	_test_iron_features_do_not_modify_other_sites()
	_test_deep_event_is_one_time()
	if failures.is_empty():
		print("mining_features_test: PASS")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)

func _test_coverage_and_ownership() -> void:
	var expected := ["D01", "D02", "D03", "D04", "D11", "D14", "D15", "D19", "D20", "FE_SK01", "FE_SK02", "FE_SK03", "FE_SK04", "FE_SK05"]
	var coverage: Dictionary = Mining.coverage()
	check(coverage.get("supported_ids", []) == expected and coverage.get("gap_ids", []).is_empty(), "Mining runtime does not explicitly cover the exact 14 assigned IDs")
	var feature_coverage: Dictionary = Features.coverage()
	check(str(feature_coverage.get("by_id", {}).get("FE_SK04", {}).get("status", "")) == "supported", "Aggregate feature coverage did not recognize FE_SK04's mining implementation")
	var research_coverage: Dictionary = ResearchRuntime.coverage()
	var mastery_coverage: Dictionary = research_coverage.get("mastery", {})
	check(mastery_coverage.get("implemented_ids", []).has("FE_SK04") and not bool(mastery_coverage.get("by_id", {}).get("FE_SK04", {}).get("core_hook_required", true)), "Canonical mastery coverage still reports FE_SK04 as an unhooked gap")
	var profile := _new_profile()
	var denied := Mining.act(profile, "mining_mark_weak_point", {"id":"FE_SK01"})
	check(not bool(denied.get("ok", false)), "Unowned mining mastery action was accepted")
	_set_owned(profile, "FE_SK01", 1)
	var marked := Mining.act(profile, "mining_mark_weak_point", {"id":"FE_SK01"})
	check(bool(marked.get("ok", false)) and bool(_mining(profile).get("weak_mark_pending", false)), "Owned FE_SK01 did not mark a real timed weak point")

func _test_marked_physical_contact() -> void:
	var profile := _new_profile()
	_set_owned(profile, "FE_SK01", 1)
	var marked := Mining.act(profile, "mining_mark_weak_point", {"id":"FE_SK01"})
	var point := _weak_point_norm(profile)
	var effects: Dictionary = Mining.tap_effects(profile, {"position_norm":[point.x, point.y]}, true)
	check(bool(marked.get("ok", false)) and effects.get("used", []).has("FE_SK01"), "A real weak-point coordinate did not qualify the temporary mark")
	var tap := Economy.act(profile, "tap", {"site":"fe", "precision":true, "position_norm":[point.x, point.y]})
	check(bool(tap.get("ok", false)) and int(tap.get("amount", 0)) > 0 and not bool(_mining(profile).get("weak_mark_pending", true)), "Physical contact did not consume the mark through the economy tap")

func _test_pocket_open_route_and_budget() -> void:
	var profile := _new_profile()
	_set_owned(profile, "D02", 1)
	_set_owned(profile, "D11", 1)
	_set_owned(profile, "FE_SK03", 1)
	var mining := _mining(profile)
	mining["rng_state"] = 1
	var first := Economy.act(profile, "tap", {"site":"fe"})
	var pocket: Dictionary = mining["pocket"]
	check(bool(first.get("ok", false)) and int(pocket.get("units", 0)) > 0 and int(pocket.get("units", 0)) <= 4, "A successful actual hit did not discover a finite bounded pocket")
	var inventory_before := int(profile["inventory"].get("iron_ore", 0))
	var opened := Mining.act(profile, "mining_open_pocket", {"id":"D02"})
	check(bool(opened.get("ok", false)) and int(profile["inventory"].get("iron_ore", 0)) == inventory_before, "Opening a pocket granted free ore")
	var selected := Mining.act(profile, "mining_set_pocket_destination", {"id":"D11", "destination":"factory_buffer"})
	check(bool(selected.get("ok", false)) and int(profile["inventory"].get("iron_ore", 0)) == inventory_before, "Choosing a pocket destination granted ore before a physical tap")
	pocket["units"] = 4
	var route_before := int(profile["inventory"].get("iron_ore", 0))
	var route_choice := Mining.act(profile, "mining_choose_route", {"id":"FE_SK03", "path":0})
	check(bool(route_choice.get("ok", false)) and int(profile["inventory"].get("iron_ore", 0)) == route_before, "Choosing a displayed vein path granted free ore")
	var wrong_path := Economy.act(profile, "tap", {"site":"fe", "position_norm":[0.64, 0.56]})
	check(bool(wrong_path.get("ok", false)) and int(pocket.get("units", 0)) == 4, "A physical hit on the unselected vein path drew the pocket")
	var selected_path := Economy.act(profile, "tap", {"site":"fe", "position_norm":[0.36, 0.56]})
	check(bool(selected_path.get("ok", false)) and int(pocket.get("units", 0)) == 2, "A physical hit on the selected path did not draw the bounded pocket amount")
	check(int(mining.get("factory_buffer_units", 0)) == 2 and GameMath.free_amount(profile, "iron_ore") == int(profile["inventory"].get("iron_ore", 0)) - 2, "Factory-buffer destination was not reserved from non-factory spending")
	profile["money_cents"] = 1000
	profile["inventory"]["iron_ore"] = int(profile["inventory"].get("iron_ore", 0)) + 5
	var queued := Economy.act(profile, "queue", {"recipe":"R_INGOT", "line":0, "count":1})
	check(bool(queued.get("ok", false)) and int(mining.get("factory_buffer_units", -1)) == 0 and GameMath.free_amount(profile, "iron_ore") == int(profile["inventory"].get("iron_ore", 0)), "Factory queue could not consume reserved pocket ore")

func _test_precision_strikes_and_zone_choice() -> void:
	var profile := _new_profile()
	for id in ["D04", "D14", "FE_SK02", "FE_SK05"]:
		_set_owned(profile, id, 1)
	var point := _weak_point_norm(profile)
	var weak_args := {"site":"fe", "precision":true, "position_norm":[point.x, point.y]}
	for _hit in range(3):
		Economy.act(profile, "tap", weak_args)
	var mining := _mining(profile)
	check(bool(mining["marked_strike"].get("available", false)) and bool(mining["directional_strike"].get("available", false)) and bool(mining["zone_choice"].get("available", false)) and bool(mining["resonance"].get("active", false)), "Precision combo did not unlock D04, D14, FE_SK02 and FE_SK05 choices")
	var resonance_arm := Mining.act(profile, "mining_arm_resonance", {"id":"D14"})
	var resonance_effects: Dictionary = Mining.tap_effects(profile, {"position_norm":[point.x, point.y]}, true)
	var resonance_hit := Economy.act(profile, "tap", weak_args)
	check(bool(resonance_arm.get("ok", false)) and resonance_effects.get("used", []).has("D14") and bool(resonance_hit.get("ok", false)) and int(mining["resonance"].get("uses", 0)) == 1 and float(mining["resonance"].get("cooldown_left", 0.0)) > 0.0, "D14 resonance did not consume one real precise strike or enter cooldown")
	var inventory_before_choices := int(profile["inventory"].get("iron_ore", 0))
	var marked := Mining.act(profile, "mining_arm_marked_strike", {"id":"D04", "zone":"center"})
	var directional := Mining.act(profile, "mining_choose_direction", {"id":"FE_SK02", "zone":"center"})
	var zone := Mining.act(profile, "mining_choose_zone", {"id":"FE_SK05", "zone":"center"})
	check(bool(marked.get("ok", false)) and bool(directional.get("ok", false)) and bool(zone.get("ok", false)) and int(profile["inventory"].get("iron_ore", 0)) == inventory_before_choices, "Target choices granted resources before a physical strike")
	var target_args := {"site":"fe", "position_norm":[0.5, 0.62]}
	var target_effects: Dictionary = Mining.tap_effects(profile, target_args, false)
	var target_hit := Economy.act(profile, "tap", target_args)
	var used: Array = target_effects.get("used", [])
	check(used.has("D04") and used.has("FE_SK02") and used.has("FE_SK05") and float(target_effects.get("multiplier", 2.0)) <= 1.35 and bool(target_hit.get("ok", false)) and not bool(mining["marked_strike"].get("armed", true)) and not bool(mining["directional_strike"].get("armed", true)), "Chosen target-zone strike did not apply its capped effect and consume one-shot strikes")

func _test_manual_drill_order_shortens_one_cycle() -> void:
	var baseline := _new_profile()
	_set_owned(baseline, "A02", 5)
	GameMath.site(baseline, "fe")["machines"]["iron_drill"] = 1000
	var ordered: Dictionary = baseline.duplicate(true)
	_set_owned(ordered, "FE_SK04", 1)
	var baseline_rate := float(Economy.metrics(baseline, "fe")["machine_rate_per_second"])
	var ordered_rate := float(Economy.metrics(ordered, "fe")["machine_rate_per_second"])
	check(baseline_rate > 0.0 and is_equal_approx(baseline_rate, ordered_rate), "FE_SK04 changed machine output rate instead of shortening a pending cycle")
	check(Features.operations(baseline, "FE_SK04").is_empty(), "Unowned FE_SK04 offered a drill order")
	check(Features.operations(ordered, "FE_SK04").is_empty(), "FE_SK04 offered an order before the drill contributed to a cycle")
	Economy.advance(ordered, 10.0)
	var mining := _mining(ordered)
	var pending_before := float(mining.get("drill_cycle_progress", 0.0))
	var choices: Array = Features.operations(ordered, "FE_SK04")
	var inventory_before := int(ordered["inventory"].get("iron_ore", 0))
	var order := Features.act(ordered, "mining_order_drill", {"id":"FE_SK04"})
	check(not choices.is_empty() and bool(order.get("ok", false)) and float(mining.get("drill_cycle_progress", 0.0)) > pending_before and int(ordered["inventory"].get("iron_ore", 0)) == inventory_before, "Manual order failed to shorten a real pending cycle without immediate output")
	check(Features.operations(ordered, "FE_SK04").is_empty() and not bool(Features.act(ordered, "mining_order_drill", {"id":"FE_SK04"}).get("ok", false)), "FE_SK04 allowed multiple orders in one drill cycle")
	var wait_after_order := (1.0 - float(mining.get("drill_cycle_progress", 0.0))) / ordered_rate
	Economy.advance(ordered, wait_after_order - 1.0)
	check(int(mining.get("drill_cycles_completed", 0)) == 0, "Drill output completed before the shortened wait elapsed")
	Economy.advance(ordered, 1.0)
	Economy.advance(baseline, 10.0 + wait_after_order)
	check(int(mining.get("drill_cycles_completed", 0)) == 1 and int(ordered["inventory"].get("iron_ore", 0)) == int(baseline["inventory"].get("iron_ore", 0)) + 1, "One manual order did not complete exactly one real drill output earlier")
	Economy.advance(ordered, 10.0)
	Economy.advance(baseline, 10.0)
	check(int(mining.get("drill_cycles_completed", 0)) == 1 and int(ordered["inventory"].get("iron_ore", 0)) == int(baseline["inventory"].get("iron_ore", 0)), "FE_SK04 created a second output instead of only shortening the first cycle wait")

func _test_forecast_and_profiles() -> void:
	var profile := _new_profile()
	_set_owned(profile, "D03", 1)
	_set_owned(profile, "D15", 1)
	_set_owned(profile, "D19", 1)
	var site_data: Dictionary = GameMath.site(profile, "fe")
	for definition in Economy.definitions("fe", "upgrade"):
		site_data["upgrades"][str(definition.get("id", ""))] = 100
	site_data["horizon"] = 1
	var mining := _mining(profile)
	var before: Dictionary = Economy.metrics(profile, "fe")
	var lens_choices: Array = Mining.operations(profile, "D15")
	var lens := Mining.act(profile, "mining_select_lens", {"id":"D15", "horizon":1})
	var profile_choices: Array = Mining.operations(profile, "D19")
	var profile_choice := Mining.act(profile, "mining_choose_profile", {"id":"D19", "profile":"throughput", "horizon":1})
	check(not lens_choices.is_empty() and bool(lens.get("ok", false)) and not profile_choices.is_empty() and bool(profile_choice.get("ok", false)), "D15/D19 did not offer valid previously unlocked horizon choices")
	var forecast_before := int(profile["inventory"].get("iron_ore", 0))
	Mining.refresh(profile)
	var eta := Mining.next_event_in(profile)
	Mining.advance(profile, eta)
	check(bool(mining["forecast"].get("available", false)) and int(profile["inventory"].get("iron_ore", 0)) == forecast_before, "Forecast timer did not reveal an opportunity without generating resources")
	var forecast_tap := Economy.act(profile, "tap", {"site":"fe", "position_norm":[0.28, 0.60]})
	check(bool(forecast_tap.get("ok", false)) and not bool(mining["forecast"].get("available", true)), "Actual tap on the forecast target did not consume the opportunity")
	var after: Dictionary = Economy.metrics(profile, "fe")
	check(float(after.get("output_multiplier", 0.0)) > float(before.get("output_multiplier", 0.0)), "D19 throughput profile did not affect real deep-horizon production")

func _test_deep_event_is_one_time() -> void:
	var profile := _new_profile()
	_set_owned(profile, "D20", 1)
	GameMath.site(profile, "fe")["horizon"] = 3
	var start := Mining.act(profile, "mining_start_core_event", {"id":"D20"})
	check(bool(start.get("ok", false)), "D20 deep event could not start at an open deep horizon")
	var mining := _mining(profile)
	for _hit in range(10):
		if bool(mining["core_event"].get("completed", false)):
			break
		Economy.act(profile, "tap", {"site":"fe"})
	var event: Dictionary = mining["core_event"]
	check(bool(event.get("completed", false)) and bool(event.get("archived", false)) and mining.get("archive_records", []).size() == 1, "D20 did not complete and archive after real manual deep work")
	check(bool(event.get("reward_claimed", false)) and int(event.get("reward_remaining", -1)) == 0, "D20 one-time archive reward was not paid")
	var restart := Mining.act(profile, "mining_start_core_event", {"id":"D20"})
	var duplicate_reward := Mining.act(profile, "mining_claim_core_reward", {"id":"D20"})
	check(not bool(restart.get("ok", false)) and not bool(duplicate_reward.get("ok", false)) and mining.get("archive_records", []).size() == 1, "D20 event or archive reward could be claimed more than once")

func _test_iron_features_do_not_modify_other_sites() -> void:
	var profile := _new_profile()
	_set_owned(profile, "D04", 1)
	var effects: Dictionary = Mining.tap_effects(profile, {"site":"pd", "position_norm":[0.5, 0.62]}, true)
	check(float(effects.get("multiplier", 0.0)) == 1.0 and effects.get("used", []).is_empty(), "Fe mining bonus leaked onto a non-iron site")

func _new_profile() -> Dictionary:
	var profile := State.make_new_profile()
	Economy.ensure(profile)
	Mining.ensure(profile)
	return profile

func _set_owned(profile: Dictionary, id: String, rank: int) -> void:
	var game: Dictionary = GameMath.game(profile)
	if not game.has("progression") or not game["progression"] is Dictionary:
		game["progression"] = {}
	var progression: Dictionary = game["progression"]
	var catalog := "mastery" if id.contains("_SK") else "research"
	if not progression.has(catalog) or not progression[catalog] is Dictionary:
		progression[catalog] = {}
	progression[catalog][id] = rank

func _mining(profile: Dictionary) -> Dictionary:
	return GameMath.game(profile)["feature_families"]["mining"]

func _weak_point_norm(profile: Dictionary) -> Vector2:
	var horizon := int(GameMath.site(profile, "fe").get("horizon", 0))
	var lane := posmod((horizon % 67) * 37 + 17, 67)
	return Vector2(0.16 + float(lane) / 67.0 * 0.68, minf(0.47 + float(horizon % 10) * 0.042, 0.72))

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
