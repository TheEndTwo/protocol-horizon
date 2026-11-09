extends SceneTree

const Registry = preload("res://autoload/ContentRegistry.gd")
const State = preload("res://autoload/GameState.gd")
const Economy = preload("res://gameplay/EconomyModel.gd")
const Progression = preload("res://gameplay/ProgressionModel.gd")

var failures: PackedStringArray = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	root.add_child(Registry.new())
	await process_frame
	_test_definitions_and_start()
	_test_quote_purchase()
	_test_budgeted_buy_all()
	_test_precision_and_stats()
	_test_upgrade_peak_not_mined_total()
	_test_economy_validation()
	_test_canonical_recipes()
	_test_sale_reservations()
	_test_factory_recipe()
	_test_wages_and_determinism()
	_test_horizons()
	_test_fe350_balance()
	if failures.is_empty():
		print("ECONOMY PASS: definitions, quotes/MAX, budgeted buy-all, precision/crit, average-level peak, validation, canonical recipes, reservations, factory, Fe wages, deterministic 60s stepping, horizons, Fe350 balance")
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: " + failure)
		quit(1)

func _test_definitions_and_start() -> void:
	var profile := State.make_new_profile()
	Economy.ensure(profile)
	check(Economy.definitions("fe", "upgrade").size() == 10, "Fe must have ten upgrades")
	check(Economy.definitions("fe", "machine").size() == 5, "Fe must have five machines")
	check(Economy.definitions("fe", "worker").size() == 5, "Fe must have five professions")
	for site in ["fe", "pd", "ir"]:
		check(Economy.definitions(site, "upgrade").size() == 10, site + " must have ten upgrades")
		check(Economy.definitions(site, "machine").size() == 5, site + " must have five machines")
		check(Economy.definitions(site, "worker").size() == 5, site + " must have five professions")
	check(int(profile["money_cents"]) == 0, "Economy initialization must not invent money")
	var tap := Economy.act(profile, "tap", {})
	var tapped_ore := int(profile["inventory"]["iron_ore"])
	check(bool(tap.get("ok", false)) and tapped_ore >= 1, "Manual Fe mining must remain free at zero money")
	var sale := Economy.act(profile, "sell", {"resource":"iron_ore", "amount":-1})
	check(bool(sale.get("ok", false)) and int(profile["money_cents"]) == tapped_ore * 100 and float(profile["game"]["stats"].get("sold", 0.0)) == tapped_ore, "Canonical ore sale must pay 100 cents per unit and record total sold")

func _test_quote_purchase() -> void:
	var profile := State.make_new_profile()
	Economy.ensure(profile)
	profile["money_cents"] = 10000
	var quote := Economy.quote(profile, "fe", "upgrade", "iron_precise_strike", 1)
	check(bool(quote.get("ok", false)) and int(quote.get("cost_cents", -1)) == 100, "First upgrade quote should be one whole G")
	check(int(quote.get("cost_cents", 0)) % 100 == 0, "Upgrade prices must ceil to whole G")
	var before := int(profile["money_cents"])
	var bought := Economy.act(profile, "buy", {"site":"fe", "kind":"upgrade", "id":"iron_precise_strike", "count":1})
	check(bool(bought.get("ok", false)) and int(profile["money_cents"]) == before - int(quote["cost_cents"]), "Purchase must debit the exact quote")
	check(int(profile["game"]["sites"]["fe"]["upgrades"]["iron_precise_strike"]) == 1, "Purchase level was not applied")
	var max_quote := Economy.quote(profile, "fe", "upgrade", "iron_precise_strike", 0)
	check(bool(max_quote.get("ok", false)) and int(max_quote.get("count", 0)) > 0, "Count 0 should quote the affordable MAX batch")
	check(max_quote.has("level") and max_quote.has("before") and max_quote.has("after"), "Purchase quote is missing the UI level or before/after snapshot")
	var max_buy := Economy.act(profile, "buy", {"site":"fe", "kind":"upgrade", "id":"iron_precise_strike", "count":0})
	check(bool(max_buy.get("ok", false)) and int(profile["game"]["sites"]["fe"]["upgrades"]["iron_precise_strike"]) == 1 + int(max_quote["count"]), "MAX purchase did not apply the quoted levels")
	profile["money_cents"] = 0
	var snapshot := profile.duplicate(true)
	var refused := Economy.act(profile, "buy", {"site":"fe", "kind":"upgrade", "id":"iron_precise_strike", "count":1})
	check(not bool(refused.get("ok", false)) and profile["game"]["sites"] == snapshot["game"]["sites"], "Unaffordable purchase must be atomic")
	var old_network: Dictionary = profile["game"]["network"].duplicate(true)
	var invalid_network := Economy.act(profile, "network", {"mode":"income", "autosell":"yes"})
	check(not bool(invalid_network.get("ok", false)) and profile["game"]["network"] == old_network, "Invalid network options must not partially mutate state")

func _test_budgeted_buy_all() -> void:
	var profile := State.make_new_profile()
	Economy.ensure(profile)
	profile["money_cents"] = 5000
	var bought := Economy.act(profile, "buy_all", {"site":"fe", "budget_cents":3500})
	check(bool(bought.get("ok", false)), "Budgeted buy-all did not buy eligible upgrades")
	check(int(bought.get("cost_cents", 0)) <= 3500 and int(profile["money_cents"]) == 5000 - int(bought.get("cost_cents", 0)), "Buy-all exceeded its budget or debited incorrectly")
	check(int(bought.get("count", 0)) > 1 and float(profile["game"]["stats"].get("purchases:upgrade", 0.0)) == int(bought["count"]), "Buy-all did not record the levels actually purchased")
	var levels: Dictionary = profile["game"]["sites"]["fe"]["upgrades"].duplicate(true)
	var wallet := int(profile["money_cents"])
	var refused := Economy.act(profile, "buy_all", {"site":"fe", "budget_cents":99})
	check(not bool(refused.get("ok", false)) and int(profile["money_cents"]) == wallet and profile["game"]["sites"]["fe"]["upgrades"] == levels, "Unsuccessful buy-all was not atomic")
	var capped := State.make_new_profile()
	Economy.ensure(capped)
	capped["money_cents"] = 9000000000000000
	var all_levels := Economy.act(capped, "buy_all", {"site":"fe", "budget_cents":9000000000000000})
	check(bool(all_levels.get("ok", false)) and int(all_levels.get("count", 0)) == 10000 and int(capped["game"]["sites"]["fe"]["peak"]) == 1000, "Buy-all failed to reach every Fe upgrade cap")

func _test_precision_and_stats() -> void:
	var profile := State.make_new_profile()
	Economy.ensure(profile)
	var first := Economy.act(profile, "tap", {"site":"fe", "precision":true})
	var second := Economy.act(profile, "tap", {"site":"fe", "precision":true})
	check(bool(first.get("ok", false)) and bool(first.get("precision", false)) and bool(first.get("weak_hit", false)), "Precise hit did not apply precision and weak-point effects")
	check(int(second.get("precision_streak", 0)) == 2, "Consecutive precise hits did not build the combo")
	check(float(profile["game"]["stats"].get("precise_hits", 0.0)) == 2.0 and int(profile["game"]["stats"].get("combo_streak", 0)) == 2, "Precise-hit/combo stats are missing")
	profile["game"]["economy_rng"]["critical_misses"] = 15
	var critical := Economy.act(profile, "tap", {"precision":false})
	check(bool(critical.get("ok", false)) and bool(critical.get("critical", false)), "Persisted pity counter did not guarantee a critical hit")
	check(float(profile["game"]["stats"].get("critical_hits", 0.0)) >= 1.0 and int(profile["game"]["stats"].get("current_combo_streak", -1)) == 0, "Critical/combo reset stats are incorrect")
	var duplicate: Dictionary = profile.duplicate(true)
	var next_a := Economy.act(profile, "tap", {"precision":true})
	var next_b := Economy.act(duplicate, "tap", {"precision":true})
	check(next_a == next_b and profile["game"]["economy_rng"] == duplicate["game"]["economy_rng"], "Persisted tap RNG is not deterministic across copies")

func _test_upgrade_peak_not_mined_total() -> void:
	var profile := State.make_new_profile()
	Economy.ensure(profile)
	for _hit in 350:
		Economy.act(profile, "tap", {"site":"fe"})
	check(float(profile["game"]["sites"]["fe"]["mined"]) >= 350.0 and int(profile["game"]["sites"]["fe"]["peak"]) == 0, "Mining quantity incorrectly advanced historical upgrade-level peak")
	profile["money_cents"] = 1000000
	for definition in Economy.definitions("fe", "upgrade"):
		var result := Economy.act(profile, "buy", {"site":"fe", "kind":"upgrades", "id":definition["id"], "count":1})
		check(bool(result.get("ok", false)), "Could not buy a level for peak test: " + str(definition["id"]))
	check(int(profile["game"]["sites"]["fe"]["peak"]) == 1, "Historical peak did not track floor(sum(10 upgrades)/10)")
	profile["money_cents"] = 1000000
	for definition in Economy.definitions("fe", "upgrade"):
		Economy.act(profile, "buy", {"site":"fe", "kind":"upgrade", "id":definition["id"], "count":1})
	check(int(profile["game"]["sites"]["fe"]["peak"]) == 2, "Average-level peak did not advance with all ten upgrades")
	var advanced := State.make_new_profile()
	Economy.ensure(advanced)
	Progression.ensure(advanced)
	advanced["game"]["sites"]["fe"]["peak"] = 350
	advanced["game"]["progression"]["story_done"]["A06"] = true
	advanced["game"]["progression"]["story_done"]["A13"] = true
	advanced["game"]["progression"]["geology"]["guaranteed_geobinding"] = true
	advanced["game"]["progression"]["geology"]["reports"] = [{"id":"report1"}, {"id":"report2"}]
	advanced["game"]["progression"]["buildings"]["deep_station"] = {"status":"complete"}
	advanced["game"]["stats"]["produced:steel"] = 1.0
	advanced["game"]["stats"]["produced:pd_catalyst"] = 1.0
	Progression.refresh(advanced)
	advanced["money_cents"] = 1000000000
	for site in ["pd", "ir"]:
		for definition in Economy.definitions(site, "upgrade"):
			var result := Economy.act(advanced, "buy", {"site":site, "kind":"upgrade", "id":definition["id"], "count":5})
			check(bool(result.get("ok", false)), "%s upgrade purchase failed while building average level 5: %s" % [site, str(definition["id"])])
		check(int(advanced["game"]["sites"][site]["peak"]) == 5, "%s peak must be the average of its ten upgrades at level 5" % site)
	Progression.refresh(advanced)
	check(bool(Progression.mastery_status(advanced, "PD_SK01").get("milestone_reached", false)) and bool(Progression.mastery_status(advanced, "IR_SK01").get("milestone_reached", false)), "Pd/Ir mastery-5 milestones did not follow the 10-upgrade average")
	for site in ["pd", "ir"]:
		for definition in Economy.definitions(site, "upgrade"):
			var result := Economy.act(advanced, "buy", {"site":site, "kind":"upgrades", "id":definition["id"], "count":5})
			check(bool(result.get("ok", false)), "%s upgrade purchase failed while building average level 10: %s" % [site, str(definition["id"])])
		check(int(advanced["game"]["sites"][site]["peak"]) == 10, "%s peak must advance to the average of ten upgrades" % site)
	Progression.refresh(advanced)
	for site in ["pd", "ir"]:
		var prefix := "PD" if site == "pd" else "IR"
		var milestone := Progression.mastery_status(advanced, prefix + "_SK02")
		var expansion := Progression.expansion_preview(advanced, site)
		check(bool(milestone.get("milestone_reached", false)), "%s mastery-10 milestone did not follow average upgrade level" % site)
		check(int(expansion.get("average_level", -1)) == 10 and int(expansion.get("required_average", -1)) == 60 and not bool(expansion.get("eligible", false)), "%s expansion preview did not use average level and site threshold" % site)

func _test_economy_validation() -> void:
	var profile := State.make_new_profile()
	Economy.ensure(profile)
	check(Economy.validate(profile), "Valid economy profile was rejected")
	var invalid: Dictionary = profile.duplicate(true)
	invalid["game"]["sites"]["fe"]["upgrades"]["iron_precise_strike"] = 1001
	check(not Economy.validate(invalid), "Out-of-range upgrade level passed economy validation")
	invalid = profile.duplicate(true)
	invalid["game"]["economy_rng"]["state"] = "bad"
	check(not Economy.validate(invalid), "Malformed persisted tap RNG passed economy validation")
	invalid = profile.duplicate(true)
	invalid["money_cents"] = -1
	check(not Economy.validate(invalid), "Negative wallet passed economy validation")

func _test_canonical_recipes() -> void:
	var profile := State.make_new_profile()
	profile["money_cents"] = 100000000
	profile["sites"]["site_earth_pd_7"]["unlocked"] = true
	profile["sites"]["site_earth_ir_9"]["unlocked"] = true
	for resource in root.get_node("ContentRegistry").get_records(&"resources"):
		profile["inventory"][str(resource["id"])] = 1000
	Economy.ensure(profile)
	var recipes: Array = root.get_node("ContentRegistry").get_records(&"recipes")
	check(recipes.size() == 9, "Expected all nine canonical recipes")
	for recipe in recipes:
		var output := str(recipe["output"])
		var site := "pd" if output.begins_with("pd_") else "ir" if output.begins_with("ir_") else "fe"
		var quote := Economy.quote(profile, site, "recipe", str(recipe["id"]), 1)
		var inputs: Variant = JSON.parse_string(str(recipe["inputs_json"]))
		var same_inputs: bool = quote.get("inputs", {}).size() == inputs.size()
		for resource in inputs:
			same_inputs = same_inputs and int(quote.get("inputs", {}).get(resource, -1)) == int(inputs[resource])
		check(bool(quote.get("ok", false)), "Canonical recipe unavailable: " + str(recipe["id"]))
		check(int(quote.get("cost_cents", -1)) == int(recipe["cash_cost_cents"]), "Recipe cash cost changed: " + str(recipe["id"]))
		check(same_inputs, "Recipe inputs changed: " + str(recipe["id"]))
		check(int(quote.get("output_quantity", -1)) == int(recipe["quantity"]), "Recipe output quantity changed: " + str(recipe["id"]))

func _test_sale_reservations() -> void:
	var profile := State.make_new_profile()
	Economy.ensure(profile)
	profile["inventory"]["iron_ore"] = 10
	var reserved := Economy.act(profile, "reserve", {"token":"contract:test", "items":{"iron_ore":7}})
	check(bool(reserved.get("ok", false)), "Valid reservation failed")
	var sale := Economy.act(profile, "sell", {"resource":"iron_ore", "amount":-1})
	check(bool(sale.get("ok", false)) and int(sale["amount"]) == 3, "Sale must only consume unreserved ore")
	check(int(profile["inventory"]["iron_ore"]) == 7 and int(profile["money_cents"]) == 300, "Reserved stock or sale proceeds are incorrect")
	var duplicate := Economy.act(profile, "reserve", {"token":"contract:test", "items":{"iron_ore":1}})
	check(not bool(duplicate.get("ok", false)) and int(profile["inventory"]["iron_ore"]) == 7, "Duplicate reservation must not mutate stock")
	var unreserved := Economy.act(profile, "unreserve", {"token":"contract:test"})
	check(bool(unreserved.get("ok", false)) and GameMath.free_amount(profile, "iron_ore") == 7, "Unreserve did not restore free stock")

func _test_factory_recipe() -> void:
	var profile := State.make_new_profile()
	Economy.ensure(profile)
	profile["money_cents"] = 10000
	profile["inventory"]["iron_ore"] = 5
	var queued := Economy.act(profile, "queue", {"recipe":"R_INGOT", "line":0, "count":1})
	check(bool(queued.get("ok", false)), "Canonical ingot recipe failed to queue: " + str(queued))
	check(int(profile["inventory"]["iron_ore"]) == 0 and int(profile["money_cents"]) == 9950, "Queue start must immediately debit 5 ore and 50 cents")
	Economy.advance(profile, 30.0)
	check(int(profile["inventory"].get("ingot", 0)) == 1, "Queued ingot did not complete after proposed duration")
	check(float(profile["game"]["stats"].get("produced:ingot", 0.0)) == 1.0, "Factory output statistic is missing")
	var locked := State.make_new_profile()
	Economy.ensure(locked)
	locked["inventory"]["pd_concentrate"] = 4
	locked["money_cents"] = 1000
	var pd := Economy.act(locked, "queue", {"recipe":"R_PD_REFINED", "line":1, "count":1})
	check(not bool(pd.get("ok", false)), "Locked Pd recipe must not run")

func _test_wages_and_determinism() -> void:
	var poor := State.make_new_profile()
	Economy.ensure(poor)
	poor["money_cents"] = 100000
	var hired := Economy.act(poor, "buy", {"site":"fe", "kind":"worker", "id":"iron_miner", "count":1})
	check(bool(hired.get("ok", false)), "Miner hire failed")
	poor["money_cents"] = 0
	var mined_before := float(poor["game"]["sites"]["fe"]["mined"])
	Economy.advance(poor, 60.0)
	var mined_after := float(poor["game"]["sites"]["fe"]["mined"])
	var base_rate := float(Economy.metrics(poor, "fe")["base_rate_per_second"])
	check(int(poor["money_cents"]) == 0, "Unpaid wages must never create debt")
	check(is_equal_approx(mined_after - mined_before, base_rate * 60.0), "Workers must pause without wages while free passive mining continues")

	var first := State.make_new_profile()
	Economy.ensure(first)
	first["money_cents"] = 100000
	first["inventory"]["iron_ore"] = 100
	Economy.act(first, "buy", {"site":"fe", "kind":"worker", "id":"iron_miner", "count":2})
	Economy.act(first, "queue", {"recipe":"R_INGOT", "line":0, "count":2})
	var second: Dictionary = first.duplicate(true)
	Economy.advance(first, 20.0)
	Economy.advance(second, 10.0)
	Economy.advance(second, 10.0)
	check(first["inventory"] == second["inventory"], "Split elapsed time changed inventory")
	check(int(first["money_cents"]) == int(second["money_cents"]), "Split elapsed time changed wallet/wage outcome")
	check(first["game"]["factory"] == second["game"]["factory"], "Split elapsed time changed factory progress")
	check(is_equal_approx(float(first["game"]["sites"]["fe"]["mined"]), float(second["game"]["sites"]["fe"]["mined"])), "Split elapsed time changed production")
	var single_step := State.make_new_profile()
	Economy.ensure(single_step)
	single_step["money_cents"] = 100000
	single_step["inventory"]["iron_ore"] = 10
	Economy.act(single_step, "buy", {"site":"fe", "kind":"worker", "id":"iron_miner", "count":2})
	Economy.act(single_step, "queue", {"recipe":"R_INGOT", "line":0, "count":2})
	var sixty_steps: Dictionary = single_step.duplicate(true)
	Economy.advance(single_step, 60.0)
	for _second in 60:
		Economy.advance(sixty_steps, 1.0)
	check(single_step["inventory"] == sixty_steps["inventory"] and single_step["game"]["factory"] == sixty_steps["game"]["factory"], "One 60-second advance differs from sixty 1-second advances")
	check(single_step["money_cents"] == sixty_steps["money_cents"] and is_equal_approx(float(single_step["game"]["sites"]["fe"]["mined"]), float(sixty_steps["game"]["sites"]["fe"]["mined"])), "60s/1s integration changed wages or Fe output")
	var cross_site := State.make_new_profile()
	Economy.ensure(cross_site)
	cross_site["money_cents"] = 100000
	cross_site["game"]["sites"]["pd"]["workers"]["pd_sample_technician"] = 10
	cross_site["game"]["sites"]["ir"]["workers"]["ir_route_engineer"] = 10
	cross_site["game"]["sites"]["pd"]["wage_fraction"] = 0.4
	cross_site["game"]["sites"]["ir"]["wage_fraction"] = 0.6
	var cross_wallet := int(cross_site["money_cents"])
	Economy.advance(cross_site, 60.0)
	check(int(cross_site["money_cents"]) == cross_wallet and is_equal_approx(float(cross_site["game"]["sites"]["pd"]["wage_fraction"]), 0.4) and is_equal_approx(float(cross_site["game"]["sites"]["ir"]["wage_fraction"]), 0.6), "Economy.advance must not charge Pd/Ir wages or mutate their wage accrual")

func _test_horizons() -> void:
	var profile := State.make_new_profile()
	Economy.ensure(profile)
	var gated := Economy.act(profile, "horizon", {"site":"fe", "index":1})
	check(not bool(gated.get("ok", false)), "Direct horizon selection must require D07")
	profile["game"]["progression"]["research"]["D07"] = 1
	var upgrades: Dictionary = profile["game"]["sites"]["fe"]["upgrades"]
	for expected in range(1, 11):
		for definition in Economy.definitions("fe", "upgrade"):
			upgrades[str(definition["id"])] = expected * 100
		Economy.ensure(profile)
		var opened := Economy.act(profile, "horizon", {"site":"fe", "index":expected})
		check(bool(opened.get("ok", false)), "Horizon %d should unlock at average level %d" % [expected, expected * 100])
		var beyond := Economy.act(profile, "horizon", {"site":"fe", "index":expected + 1})
		check(not bool(beyond.get("ok", false)), "Horizon %d must remain locked before its threshold" % (expected + 1))

func _test_fe350_balance() -> void:
	var profile := State.make_new_profile()
	Economy.ensure(profile)
	var elapsed_hours := 0
	while int(profile["game"]["sites"]["fe"]["peak"]) < 350 and elapsed_hours < 24 * 60:
		Economy.advance(profile, 3600.0)
		Economy.act(profile, "sell_all", {})
		Economy.act(profile, "buy_all", {"site":"fe", "budget_cents":int(profile["money_cents"])})
		elapsed_hours += 1
	var elapsed_days := float(elapsed_hours) / 24.0
	print("BALANCE FE350: %.1f in-game days at baseline Fe production with hourly free-ore sale and budgeted upgrade purchases" % elapsed_days)
	check(int(profile["game"]["sites"]["fe"]["peak"]) >= 350, "Fe350 was not reached within the 60-day baseline production simulation")
	check(elapsed_days <= 60.0, "Fe350 exceeds the 60-day baseline production budget: %.1f days" % elapsed_days)

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
