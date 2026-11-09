extends SceneTree

const Research = preload("res://gameplay/ResearchRuntime.gd")
const Economy = preload("res://gameplay/EconomyModel.gd")

var failures: PackedStringArray = []

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func profile() -> Dictionary:
	return {
		"money_cents":100000, "research_points":0, "inventory":{"iron_ore":0},
		"sites":{"site_earth_fe_17":{"unlocked":true}, "site_earth_pd_7":{"unlocked":false}, "site_earth_ir_9":{"unlocked":false}}
	}

func _run() -> void:
	var registry: Node = root.get_node("ContentRegistry")
	check(registry.is_loaded, "Canonical catalogs are not loaded: " + str(registry.errors))
	if registry.is_loaded:
		_test_catalog_coverage()
		_test_owned_effects_only()
		_test_reserve_and_task_idempotency()
		_test_real_recipe_queue()
		_test_refresh_has_no_phantom_production()
	if failures.is_empty():
		print("research_runtime_test: all checks passed")	
	else:
		for failure in failures:
			push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _test_catalog_coverage() -> void:
	var result := Research.coverage()
	check(int(result.research.total) == 140 and int(result.mastery.total) == 24, "Coverage must inspect all canonical nodes")
	check(int(result.research.mapped) == 140 and int(result.mastery.mapped) == 24, "Every canonical node needs an explicit runtime contract or gap")
	check(result.compatibility_skip_ids == ["D02", "D04"], "Legacy D02/D04 numeric bonuses must be ignored by the runtime")
	var description := Research.describe(profile(), "A02")
	check(str(description.get("mode", "")) == "modifier" and str(description.get("modifier_key", "")) == "machine:iron_drill", "Drill research must target only the iron drill mechanism")
	check(not bool(description.get("implemented", true)) and bool(description.get("core_hook_required", false)), "Unconsumed modifier must not claim to be active")

func _test_owned_effects_only() -> void:
	var locked := profile()
	var owned := profile()
	var progression: Dictionary = GameMath.game(owned).get("progression", {})
	if progression.is_empty():
		GameMath.game(owned)["progression"] = {"research":{"P02":5,"D10":5,"D02":5,"D04":5},"mastery":{},"effects":{"flags":{},"mastery":{}}}
	else:
		progression["research"] = {"P02":5,"D10":5,"D02":5,"D04":5}
	GameMath.game(owned)["bonuses"]["progression"] = {"fe:tap":0.25}
	Research.refresh(locked)
	Research.refresh(owned)
	check(is_zero_approx(GameMath.bonus(locked, "worker:iron_miner", "fe")), "Unowned worker research changed a worker bonus")
	check(is_equal_approx(GameMath.bonus(owned, "worker:iron_miner", "fe"), 0.05), "Miner training did not emit its bounded worker-only bonus contract")
	check(is_equal_approx(GameMath.bonus(owned, "deep_output", "fe"), 0.05), "Deep-output research did not reach its existing deep-only consumer key")
	check(not GameMath.game(owned)["bonuses"]["research_runtime"].has("fe:tap"), "D02/D04 legacy tap bonuses were double-counted")
	check(Research.describe(locked, "P02").get("enabled", true) == false and Research.describe(owned, "P02").get("owned", false), "Description ownership state is incorrect")

func _test_reserve_and_task_idempotency() -> void:
	var p := profile()
	p["inventory"]["iron_ore"] = 10
	GameMath.game(p)["progression"] = {"research":{"A15":1,"P20":1,"P14":1,"PD24":1},"mastery":{},"geology":{"reports":[],"discoveries":{}},"story_done":{}}
	GameMath.site(p, "fe")["workers"] = {"iron_miner":1,"iron_hauler":1}
	var before: Dictionary = p["inventory"].duplicate(true)
	var reserved := Research.act(p, "reserve_items", {"id":"A15", "token":"test:A15", "items":{"iron_ore":4}})
	check(bool(reserved.get("ok", false)), "Owned reserve action failed: " + str(reserved))
	check(GameMath.reserved(p, "iron_ore") == 4 and GameMath.free_amount(p, "iron_ore") == 6, "Research reserve did not use the actual economy reservation ledger")
	check(p["inventory"] == before, "Reservation must not create or consume resources")
	var cash_reserve := Research.act(p, "set_cash_reserve", {"id":"P14", "amount_cents":20000})
	check(bool(cash_reserve.get("ok", false)) and int(p["money_cents"]) == 100000, "Cash reserve should be tracked without spending money")
	var over_budget := Research.act(p, "set_cash_reserve", {"id":"PD24", "amount_cents":90000})
	check(not bool(over_budget.get("ok", false)), "Combined cash reservations must not exceed the real current balance")
	var points_before := int(p["research_points"])
	var task := Research.act(p, "complete_task", {"id":"P20"})
	check(bool(task.get("ok", false)) and int(p["research_points"]) == points_before + 1, "Optional team task did not award its one-time OI after real role conditions")
	var duplicate := Research.act(p, "complete_task", {"id":"P20"})
	check(not bool(duplicate.get("ok", false)) and int(p["research_points"]) == points_before + 1, "Unique task reward was claimable more than once")
	check(p["inventory"] == before, "Task confirmation must not grant phantom inventory")

func _test_real_recipe_queue() -> void:
	var p := profile()
	p["money_cents"] = 1000000
	GameMath.game(p)["progression"] = {"research":{"A14":1},"mastery":{}}
	var candidate := ""
	var inputs: Dictionary = {}
	for recipe in GameMath.records("recipes"):
		var output := str(recipe.get("output", ""))
		if output.begins_with("pd_") or output.begins_with("ir_"):
			continue
		var parsed: Variant = JSON.parse_string(str(recipe.get("inputs_json", "{}")))
		if not parsed is Dictionary:
			continue
		candidate = str(recipe.get("id", ""))
		inputs = parsed
		break
	check(not candidate.is_empty(), "No canonical Fe recipe available for queue test")
	if candidate.is_empty():
		return
	for resource in inputs:
		p["inventory"][str(resource)] = int(inputs[resource])
	var before_output := int(p["inventory"].get(str(GameMath.record("recipes", candidate).get("output", "")), 0))
	var result := Research.act(p, "queue_recipe_chain", {"id":"A14", "recipe_ids":[candidate], "line":0, "count":1})
	check(bool(result.get("ok", false)), "Research cascade did not use the real recipe budget: " + str(result))
	check(not GameMath.game(p).get("factory", []).is_empty(), "Queued recipe did not enter the existing factory state")
	check(int(p["inventory"].get(str(GameMath.record("recipes", candidate).get("output", "")), 0)) == before_output, "Queue action fabricated an output before the real recipe completed")

func _test_refresh_has_no_phantom_production() -> void:
	var p := profile()
	p["inventory"]["iron_ore"] = 3
	GameMath.game(p)["progression"] = {"research":{"D10":5,"A02":5,"P02":5},"mastery":{}}
	var inventory_before: Dictionary = p["inventory"].duplicate(true)
	var stats_before: Dictionary = GameMath.game(p)["stats"].duplicate(true)
	Research.refresh(p)
	check(p["inventory"] == inventory_before, "Refreshing research must not produce offsite resources")
	check(GameMath.game(p)["stats"] == stats_before, "Refreshing research must not write production statistics")
	check(GameMath.site(p, "fe").get("peak", 0) == 0, "Research refresh must not advance site progression")
