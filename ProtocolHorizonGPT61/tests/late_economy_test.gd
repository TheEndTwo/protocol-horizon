extends SceneTree

const Registry = preload("res://autoload/ContentRegistry.gd")
const State = preload("res://autoload/GameState.gd")
const GameMath = preload("res://gameplay/GameMath.gd")
const Economy = preload("res://gameplay/EconomyModel.gd")
const Mining = preload("res://gameplay/MiningFeatures.gd")
const Progression = preload("res://gameplay/ProgressionModel.gd")
const Research = preload("res://gameplay/ResearchRuntime.gd")
const Meta = preload("res://gameplay/MetaModel.gd")

var failures: PackedStringArray = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	root.add_child(Registry.new())
	await process_frame
	_test_research_scoped_tapping()
	_test_transport_dispatch_and_capacity()
	_test_factory_logistics_and_shipping()
	_test_high_level_machines_and_workers()
	_test_site_scoped_recipe_costs()
	if failures.is_empty():
		print("late_economy_test: scoped economy research consumers passed")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)

func _test_research_scoped_tapping() -> void:
	var control := _profile()
	var protected := _profile()
	var base_chance := float(Economy.metrics(control, "fe").get("crit_chance", 0.0))
	_grant(protected, "D05", 5)
	var seed := 0
	for candidate in range(1, 10000):
		var rng := {"state":candidate, "critical_misses":5, "precision_streak":0}
		var roll := float(Economy._next_roll(rng))
		if roll >= base_chance and roll < base_chance + 0.05:
			seed = candidate
			break
	check(seed > 0, "Could not find a deterministic crit roll in D05's variance-reduction band")
	for profile in [control, protected]:
		var rng: Dictionary = GameMath.game(profile)["economy_rng"]
		rng["state"] = seed
		rng["critical_misses"] = 5
	var ordinary: Dictionary = Economy.act(control, "tap", {"site":"fe"})
	var smoothed: Dictionary = Economy.act(protected, "tap", {"site":"fe"})
	check(not bool(ordinary.get("critical", false)) and bool(smoothed.get("critical", false)), "D05 did not smooth a deterministic long-run critical miss streak")

	var geology := _profile()
	_grant(geology, "D08", 5)
	var weak := _weak_point(geology)
	var tap: Dictionary = Economy.act(geology, "tap", {"site":"fe", "precision":true, "position_norm":[weak.x, weak.y]})
	var mining_state: Dictionary = GameMath.game(geology)["feature_families"]["mining"]
	var highlight: Dictionary = mining_state.get("anomaly_highlight", {})
	check(bool(tap.get("ok", false)) and bool(tap.get("weak_hit", false)) and bool(highlight.get("active", false)) and is_equal_approx(float(highlight.get("seconds_left", 0.0)), 4.2), "D08 did not extend a real weak-point anomaly highlight")
	var sample_profile := _profile()
	_grant(sample_profile, "D17", 1)
	var sample: Dictionary = Economy.act(sample_profile, "tap", {"site":"fe", "position_norm":[0.0, 0.0]})
	var geology_result: Dictionary = Progression.geology_effects(sample_profile, "fe")
	check(bool(sample.get("ok", false)) and float(geology_result.get("active_mining_units", 0.0)) == float(sample.get("amount", 0)) and float(geology_result.get("geology_data_quality", 0.0)) > float(geology_result.get("active_mining_quality", 0.0)), "D17 geology quality was not derived from actual manual strike samples")

	var resonance_profile := _profile()
	_grant(resonance_profile, "D14", 1)
	_grant(resonance_profile, "D18", 5)
	var resonance: Dictionary = GameMath.game(resonance_profile)["feature_families"]["mining"]["resonance"]
	resonance["active"] = true
	resonance["armed"] = true
	resonance["armed_seconds"] = 8.0
	var resonance_point := _weak_point(resonance_profile)
	var fired: Dictionary = Economy.act(resonance_profile, "tap", {"site":"fe", "precision":true, "position_norm":[resonance_point.x, resonance_point.y]})
	check(bool(fired.get("mining_effects", {}).get("used", []).has("D14")) and is_equal_approx(float(resonance.get("cooldown_left", 0.0)), 45.0 / 1.05), "D18 did not shorten the cooldown after a real armed resonance strike")

func _test_transport_dispatch_and_capacity() -> void:
	var baseline := _dispatch_profile()
	var faster := _dispatch_profile()
	_grant(faster, "A05", 5)
	var operator := _dispatch_profile()
	operator["game"]["sites"]["fe"]["workers"]["iron_operator"] = 1
	_grant(operator, "P06", 5)
	var baseline_interval := float(baseline["game"]["transport"]["ore_dispatch_interval_seconds"])
	var faster_interval := float(faster["game"]["transport"]["ore_dispatch_interval_seconds"])
	var operator_interval := float(operator["game"]["transport"]["ore_dispatch_interval_seconds"])
	check(faster_interval < baseline_interval and operator_interval < baseline_interval, "A05/P06 did not shorten ore dispatch intervals under their required conditions")
	Economy.advance(faster, faster_interval + 0.01)
	var transport: Dictionary = faster["game"]["transport"]
	check(int(faster["inventory"].get("iron_ore", 0)) < 100 and int(GameMath.game(faster)["stats"].get("sold:iron_ore", 0)) == 30 and int(GameMath.game(faster)["stats"].get("ore_dispatch_units", 0)) == 30, "A05 dispatched its bounded ore shipment or recorded it as production")
	check(int(transport.get("ore_dispatches", 0)) == 1 and int(GameMath.game(faster)["stats"].get("produced:iron_ore", 0)) < 30, "Ore dispatch count/production accounting is not distinct")

	var ordinary := _dispatch_profile()
	var efficient := _dispatch_profile()
	_grant(efficient, "A09", 5)
	var synchronized := _dispatch_profile()
	synchronized["game"]["sites"]["fe"]["machines"]["iron_conveyor"] = 1
	_grant(synchronized, "A06", 5)
	GameMath.game(synchronized)["feature_families"]["mining"]["resonance"]["active"] = true
	var no_conveyor_resonance := _dispatch_profile()
	no_conveyor_resonance["game"]["sites"]["fe"]["machines"]["iron_conveyor"] = 1
	_grant(no_conveyor_resonance, "A06", 5)
	for profile in [ordinary, efficient, synchronized, no_conveyor_resonance]:
		Economy.ensure(profile)
		Economy.advance(profile, float(profile["game"]["transport"]["ore_dispatch_interval_seconds"]) + 0.01)
	var ordinary_shipped := int(GameMath.game(ordinary)["stats"].get("sold:iron_ore", 0))
	var efficient_shipped := int(GameMath.game(efficient)["stats"].get("sold:iron_ore", 0))
	var synchronized_shipped := int(GameMath.game(synchronized)["stats"].get("sold:iron_ore", 0))
	var inactive_shipped := int(GameMath.game(no_conveyor_resonance)["stats"].get("sold:iron_ore", 0))
	check(efficient_shipped > ordinary_shipped and synchronized_shipped > inactive_shipped, "A09 soft-cap throughput or A06's active-conveyor-only bonus had no dispatch effect")
	check(int(GameMath.game(efficient)["stats"].get("produced:iron_ore", 0)) < efficient_shipped, "A09 turned transport capacity into iron production")

func _test_factory_logistics_and_shipping() -> void:
	var loader := _profile()
	var fe := GameMath.site(loader, "fe")
	fe["machines"]["iron_loader"] = 1
	loader["inventory"]["iron_ore"] = 1000
	loader["money_cents"] = 1000000
	_grant(loader, "A04", 5)
	var without_hauler := int(loader["game"]["transport"].get("factory_loader_buffer_units", 0))
	fe["workers"]["iron_hauler"] = 1
	_grant(loader, "P05", 5)
	var with_hauler := int(loader["game"]["transport"].get("factory_loader_buffer_units", 0))
	check(with_hauler > without_hauler and GameMath.reserved(loader, "iron_ore") >= with_hauler, "A04/P05 did not reserve a capped loader-directed factory share")
	var queued: Dictionary = Economy.act(loader, "queue", {"recipe":"R_INGOT", "line":0, "count":1})
	check(bool(queued.get("ok", false)) and int(loader["inventory"].get("iron_ore", 0)) == 995 and GameMath.free_amount(loader, "iron_ore") <= 995, "Loader buffer could not feed a later real factory job")

	var no_shipping := _blocked_factory_profile(false)
	var shipping := _blocked_factory_profile(true)
	Economy.advance(no_shipping, 1.0)
	Economy.advance(shipping, 1.0)
	check(int(no_shipping["inventory"].get("steel", 0)) == GameMath.capacity(no_shipping) and not GameMath.game(no_shipping)["factory"][0]["pending"].is_empty(), "Factory output advanced without shipping capacity")
	check(int(shipping["inventory"].get("steel", 0)) == GameMath.capacity(shipping) - 1 and int(shipping["inventory"].get("ingot", 0)) == 1 and int(GameMath.game(shipping)["stats"].get("finished_goods_shipped", 0)) == 1, "A12 did not ship a finished good to unblock the actual pending factory output")
	check(int(GameMath.game(shipping)["stats"].get("produced:ingot", 0)) == 1, "A12 shipping did not preserve factory production accounting")
	check(GameMath.game(shipping)["factory"][0]["active"].is_empty() and GameMath.game(shipping)["factory"][0]["queue"].size() == 1, "Factory line consumed shipment wait time on the next queued unit")

func _test_high_level_machines_and_workers() -> void:
	var ordinary := _profile()
	var researched := _profile()
	for profile in [ordinary, researched]:
		GameMath.site(profile, "fe")["machines"]["iron_drill"] = 20
		GameMath.site(profile, "fe")["machines"]["iron_ore_truck"] = 20
	Economy.ensure(ordinary)
	var storage_before := GameMath.capacity(ordinary)
	var output_before := float(GameMath.game(ordinary)["bonuses"]["economy"].get("fe:output", 0.0))
	_grant(researched, "A13", 5)
	var output_after := float(GameMath.game(researched)["bonuses"]["economy"].get("fe:output", 0.0))
	check(output_after > output_before and GameMath.capacity(researched) == storage_before, "A13 did not apply diminishing high-level machine efficiency without changing storage")

	var driller := _profile()
	GameMath.site(driller, "fe")["workers"]["iron_driller"] = 1
	_grant(driller, "P03", 5)
	var surface_rate := float(Economy.metrics(driller, "fe").get("worker_rate_per_second", 0.0))
	GameMath.site(driller, "fe")["horizon"] = 1
	var deep_rate := float(Economy.metrics(driller, "fe").get("worker_rate_per_second", 0.0))
	check(deep_rate > surface_rate, "P03 affected no iron driller output at a real deep horizon")

	var matched := _worker_specialist_profile("SP01")
	var mismatched := _worker_specialist_profile("SP02")
	check(float(Economy.metrics(matched, "fe").get("worker_rate_per_second", 0.0)) > float(Economy.metrics(mismatched, "fe").get("worker_rate_per_second", 0.0)), "P13 stacked a role bonus onto a specialist assigned to the wrong worker profession")

func _test_site_scoped_recipe_costs() -> void:
	var pd := _recipe_profile("pd", "R_PD_CAT")
	var pd_baseline: Dictionary = Economy.quote(pd, "pd", "recipe", "R_PD_CAT", 1)
	_grant(pd, "PD15", 5)
	var pd_reduced: Dictionary = Economy.quote(pd, "pd", "recipe", "R_PD_CAT", 1)
	check(bool(pd_baseline.get("ok", false)) and bool(pd_reduced.get("ok", false)) and int(pd_reduced.get("cost_cents", 0)) < int(pd_baseline.get("cost_cents", 0)), "PD15 did not reduce only the Pd catalyst tooling cash fee")

	var ir := _recipe_profile("ir", "R_IR_REFINED")
	var ir_baseline: Dictionary = Economy.quote(ir, "ir", "recipe", "R_IR_REFINED", 1)
	_grant(ir, "IR13", 5)
	var ir_reduced: Dictionary = Economy.quote(ir, "ir", "recipe", "R_IR_REFINED", 1)
	check(bool(ir_baseline.get("ok", false)) and bool(ir_reduced.get("ok", false)) and int(ir_reduced.get("cost_cents", 0)) < int(ir_baseline.get("cost_cents", 0)), "IR13 did not reduce only the Ir cleanup cash expense")

	var cleanup := _profile()
	cleanup["sites"]["site_earth_ir_9"]["unlocked"] = true
	cleanup["inventory"]["ir_core"] = 1000
	_grant(cleanup, "IR12", 5)
	var reserve := int(cleanup["game"]["transport"].get("cleanup_buffer_units", 0))
	check(reserve == 5 and GameMath.reserved(cleanup, "ir_core") == reserve, "IR12 did not reserve its independent Ir cleanup buffer")

func _profile() -> Dictionary:
	var profile := State.make_new_profile()
	Economy.ensure(profile)
	Progression.ensure(profile)
	Mining.ensure(profile)
	return profile

func _grant(profile: Dictionary, id: String, rank: int) -> void:
	var game: Dictionary = GameMath.game(profile)
	var progression: Dictionary = game.get("progression", {})
	if not progression.has("research"):
		progression["research"] = {}
	progression["research"][id] = rank
	game["progression"] = progression
	Research.refresh(profile)
	Economy.ensure(profile)
	Mining.ensure(profile)

func _dispatch_profile() -> Dictionary:
	var profile := _profile()
	GameMath.site(profile, "fe")["machines"]["iron_ore_truck"] = 1
	profile["inventory"]["iron_ore"] = 100
	Economy.ensure(profile)
	return profile

func _blocked_factory_profile(owned_shipping: bool) -> Dictionary:
	var profile := _profile()
	profile["inventory"] = {"steel":GameMath.capacity(profile)}
	var line: Dictionary = GameMath.game(profile)["factory"][0]
	line["active"] = {"output":"ingot", "output_quantity":1, "units_remaining":1, "seconds_per_unit":30.0, "seconds_left":0.0, "status":"waiting_capacity"}
	line["pending"] = {"resource":"ingot", "quantity":1}
	line["queue"] = [{"recipe_id":"R_INGOT", "output":"ingot", "output_quantity":1, "units_remaining":1, "seconds_per_unit":30.0, "inputs":{}, "cash_cost_cents":0, "status":"queued"}]
	if owned_shipping:
		_grant(profile, "A12", 1)
	return profile

func _worker_specialist_profile(specialist_id: String) -> Dictionary:
	var profile := _profile()
	GameMath.site(profile, "fe")["workers"]["iron_miner"] = 1
	_grant(profile, "P13", 5)
	Meta.ensure(profile)
	var specialists: Dictionary = GameMath.game(profile)["meta"]["specialists"]
	specialists["owned"][specialist_id] = {"level":1, "stars":0}
	specialists["assignments"]["fe"] = {"0":specialist_id}
	return profile

func _recipe_profile(site: String, recipe_id: String) -> Dictionary:
	var profile := _profile()
	var site_id := "site_earth_pd_7" if site == "pd" else "site_earth_ir_9"
	profile["sites"][site_id]["unlocked"] = true
	profile["money_cents"] = 100000000
	var recipe: Dictionary = GameMath.record("recipes", recipe_id)
	var inputs: Dictionary = JSON.parse_string(str(recipe.get("inputs_json", "{}")))
	for resource in inputs:
		profile["inventory"][str(resource)] = int(inputs[resource])
	return profile

func _weak_point(profile: Dictionary) -> Vector2:
	var horizon := int(GameMath.site(profile, "fe").get("horizon", 0))
	var lane := posmod((horizon % 67) * 37 + 17, 67)
	return Vector2(0.16 + float(lane) / 67.0 * 0.68, minf(0.47 + float(horizon % 10) * 0.042, 0.72))

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
