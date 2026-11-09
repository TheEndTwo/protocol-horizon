extends SceneTree

const Features = preload("res://gameplay/FeatureRuntime.gd")
const MATH_PATH := "res://gameplay/GameMath.gd"
const ECONOMY_PATH := "res://gameplay/EconomyModel.gd"
const SITES_PATH := "res://gameplay/SiteModel.gd"

var failures: PackedStringArray = []

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func profile(open_pd: bool = false, open_ir: bool = false) -> Dictionary:
	var p := {"money_cents":1000000, "inventory":{"iron_ore":100}, "sites":{
		"site_earth_fe_17":{"unlocked":true},
		"site_earth_pd_7":{"unlocked":open_pd},
		"site_earth_ir_9":{"unlocked":open_ir}
	}}
	var game: Dictionary = model(MATH_PATH, "game", [p])
	game["progression"] = {"research":{}, "mastery":{}}
	model(ECONOMY_PATH, "ensure", [p])
	model(SITES_PATH, "ensure", [p])
	return p

func own(p: Dictionary, id: String) -> void:
	var catalog := "mastery" if id.contains("_SK") else "research"
	var game: Dictionary = model(MATH_PATH, "game", [p])
	game["progression"][catalog][id] = 1

func model(path: String, method: String, args: Array) -> Variant:
	return load(path).callv(method, args)

func run_action(p: Dictionary, action: String, args: Dictionary) -> Dictionary:
	return Features.act(p, action, args)

func _run() -> void:
	var registry: Node = root.get_node("ContentRegistry")
	check(registry.is_loaded, "Canonical catalogs are not loaded: " + str(registry.errors))
	if registry.is_loaded:
		_test_coverage_and_ownership()
		_test_paid_auto_distribution()
		_test_routes_quote_live_state()
		_test_combo_and_optional_archive()
		_test_real_lens_and_ir_queue()
	if failures.is_empty():
		print("features_test: all checks passed")
	else:
		for failure in failures:
			push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _test_coverage_and_ownership() -> void:
	var report := Features.coverage()
	check(int(report.get("total", 0)) >= 40 and int(report.get("total", 0)) <= 60, "Coverage should enumerate actual feature-mode research and mastery IDs")
	check(report.get("by_id", {}).get("P04", {}).get("status", "") == "supported", "Paid worker distribution is not reported as supported")
	check(report.get("by_id", {}).get("IR28", {}).get("status", "") == "gap", "Unsupported geology actions must remain honest gaps")
	var p := profile()
	var money := int(p["money_cents"])
	var denied := run_action(p, "configure_hiring", {"id":"P04", "enabled":true, "budget_cents":10000})
	check(not bool(denied.get("ok", false)) and int(p["money_cents"]) == money, "An unowned feature must not configure or spend")
	own(p, "IR24")
	var locked := run_action(p, "plan_ir_queue", {"id":"IR24", "first_strategy":"economic", "second_strategy":"reliable", "budget_cents":100000})
	check(not bool(locked.get("ok", false)) and int(p["money_cents"]) == money, "A feature cannot operate on a locked site")
	check(Features.operations(p, "IR24").is_empty(), "Controls must not be offered for a locked site")

func _test_paid_auto_distribution() -> void:
	var p := profile()
	own(p, "P04")
	var workers: Array = model(ECONOMY_PATH, "definitions", ["fe", "worker"])
	var first_id := str(workers[0].get("id", ""))
	var quote: Dictionary = model(ECONOMY_PATH, "quote", [p, "fe", "worker", first_id, 1])
	var price := int(quote.get("cost_cents", 0))
	check(price > 0, "Fixture needs a real paid worker quote")
	var before_money := int(p["money_cents"])
	check(bool(run_action(p, "configure_hiring", {"id":"P04", "enabled":true, "budget_cents":price}).get("ok", false)), "Explicit hiring budget did not save")
	var hired := run_action(p, "auto_distribute", {"id":"P04"})
	var site: Dictionary = model(MATH_PATH, "site", [p, "fe"])
	var levels: Dictionary = site.get("workers", {})
	var total_levels := 0
	for level in levels.values():
		total_levels += int(level)
	check(bool(hired.get("ok", false)) and total_levels == 1, "Auto-distribution must make only the one worker affordable from the explicit budget")
	check(int(hired.get("spent_cents", -1)) == price and int(p["money_cents"]) == before_money - price, "A worker level must be purchased at its actual quoted cost")
	var before_levels := total_levels
	var before_cash := int(p["money_cents"])
	var too_small := run_action(p, "configure_hiring", {"id":"P04", "enabled":true, "budget_cents":1})
	check(bool(too_small.get("ok", false)), "A valid small budget should be stored rather than silently raised")
	var no_hire := run_action(p, "auto_distribute", {"id":"P04"})
	check(not bool(no_hire.get("ok", false)) and int(p["money_cents"]) == before_cash, "Insufficient explicit budget must not add free worker levels")
	var after_levels: Array = model(MATH_PATH, "site", [p, "fe"]).get("workers", {}).values()
	var after_total := 0
	for level in after_levels:
		after_total += int(level)
	check(after_total == before_levels, "A failed distribution changed profession levels")

func _test_routes_quote_live_state() -> void:
	var p := profile()
	own(p, "A19")
	own(p, "A10")
	var money_before := int(p["money_cents"])
	var ore_before := int(p["inventory"].get("iron_ore", 0))
	var saved := run_action(p, "set_line_route", {"id":"A19", "line":0, "recipe_id":"R_INGOT", "budget_cents":10000})
	check(bool(saved.get("ok", false)), "An unlocked real recipe route did not save")
	var prioritized := run_action(p, "set_factory_priority", {"id":"A10", "first_line":0})
	check(bool(prioritized.get("ok", false)), "Factory priority preset did not save")
	Features.advance(p, 1.0)
	var game: Dictionary = model(MATH_PATH, "game", [p])
	var line: Dictionary = game["factory"][0]
	check(not Array(line.get("queue", [])).is_empty() or not Dictionary(line.get("active", {})).is_empty(), "An idle route did not use the actual paid recipe queue")
	check(int(p["money_cents"]) < money_before and int(p["inventory"].get("iron_ore", 0)) < ore_before, "Auto-route must pay and consume real current cash and inventory")
	var once_money := int(p["money_cents"])
	var once_ore := int(p["inventory"].get("iron_ore", 0))
	Features.advance(p, 1.0)
	check(int(p["money_cents"]) == once_money and int(p["inventory"].get("iron_ore", 0)) == once_ore, "A busy line must not be queued or charged twice")

func _test_combo_and_optional_archive() -> void:
	var p := profile()
	own(p, "D13")
	var configured := run_action(p, "set_combo_memory", {"id":"D13", "preserve":2})
	check(bool(configured.get("ok", false)), "Combo memory setting failed")
	var economy_rng: Dictionary = model(MATH_PATH, "game", [p])["economy_rng"]
	var first: Dictionary = model(ECONOMY_PATH, "act", [p, "tap", {"site":"fe", "precision":true}])
	Features.after_action(p, "economy", "tap", {"site":"fe"}, first)
	var second: Dictionary = model(ECONOMY_PATH, "act", [p, "tap", {"site":"fe", "precision":true}])
	Features.after_action(p, "economy", "tap", {"site":"fe"}, second)
	var miss: Dictionary = model(ECONOMY_PATH, "act", [p, "tap", {"site":"fe", "precision":false}])
	var seed_after_real_tap := int(model(MATH_PATH, "game", [p])["economy_rng"]["state"])
	Features.after_action(p, "EarthEconomy", "tap", {"site":"fe"}, miss)
	check(int(model(MATH_PATH, "game", [p])["economy_rng"].get("precision_streak", 0)) == 2, "A real short-window miss did not preserve the selected measured streak")
	check(int(miss.get("preserved_streak", 0)) == 2, "Tap hook should expose the actually retained streak")
	check(int(model(MATH_PATH, "game", [p])["economy_rng"]["state"]) == seed_after_real_tap, "Combo memory must not reroll or alter the economy seed")
	var money_before := int(p["money_cents"])
	var inventory_before: Dictionary = p["inventory"].duplicate(true)
	var archived := run_action(p, "archive_combo", {"id":"D13"})
	var duplicate := run_action(p, "archive_combo", {"id":"D13"})
	var record: Dictionary = model(MATH_PATH, "game", [p])["features"]["D13"]["archive_record"]
	check(bool(archived.get("ok", false)) and not bool(duplicate.get("ok", false)) and record.get("id", "") == "D13", "Optional archive task must be keyed by ID and idempotent")
	check(int(p["money_cents"]) == money_before and p["inventory"] == inventory_before, "Archiving a measured combo must not award resources or cash")
	check(int(economy_rng["state"]) > 0, "Economy fixture seed should be initialized")

func _test_real_lens_and_ir_queue() -> void:
	var p := profile(true, true)
	own(p, "PD07")
	own(p, "IR08")
	own(p, "IR24")
	own(p, "IR25")
	var game: Dictionary = model(MATH_PATH, "game", [p])
	var rng_before := int(game["economy_rng"]["state"])
	var pd_seed := int(game["extraction"]["pd"]["seed_counter"])
	var ir_seed := int(game["extraction"]["ir"]["seed_counter"])
	var cash_before := int(p["money_cents"])
	var lens := run_action(p, "select_purity_lens", {"id":"PD07", "lens_id":"pd_lens_high_grade"})
	var profile_choice := run_action(p, "set_thermal_tradeoff", {"id":"IR25", "strategy_id":"economic"})
	var plan := run_action(p, "plan_ir_queue", {"id":"IR24", "first_strategy":"economic", "second_strategy":"reliable", "budget_cents":cash_before})
	check(bool(lens.get("ok", false)) and bool(profile_choice.get("ok", false)) and bool(plan.get("ok", false)), "Real lens/profile/queue planning action failed")
	game = model(MATH_PATH, "game", [p])
	check(int(p["money_cents"]) == cash_before, "Lens, strategy and queue planning must not precharge the campaign")
	check(int(game["economy_rng"]["state"]) == rng_before and int(game["extraction"]["pd"]["seed_counter"]) == pd_seed and int(game["extraction"]["ir"]["seed_counter"]) == ir_seed, "Selection and planning must preserve active seeds")
	var ir_view: Dictionary = model(SITES_PATH, "view", [p, "ir"])
	check(str(ir_view.get("strategy_id", "")) == "economic", "Thermal profile should use the actual SiteModel strategy")
	Features.advance(p, 1.0)
	game = model(MATH_PATH, "game", [p])
	check(int(game["extraction"]["ir"]["seed_counter"]) == ir_seed + 1, "One queued campaign start must advance the real campaign seed exactly once")
	var active: Dictionary = game["extraction"]["ir"]
	check(str(active.get("campaign", {}).get("strategy_id", "")) == "economic" and active["status"] == "running", "First queued campaign should start through the real SiteModel")
	var active_cash := int(p["money_cents"])
	Features.advance(p, 1.0)
	check(int(model(MATH_PATH, "game", [p])["extraction"]["ir"]["seed_counter"]) == ir_seed + 1 and int(p["money_cents"]) == active_cash, "An active route must not start or charge the next campaign")
	model(SITES_PATH, "advance", [p, 10000.0])
	Features.advance(p, 1.0)
	game = model(MATH_PATH, "game", [p])
	check(int(game["extraction"]["ir"]["campaigns_completed"]) == 1 and int(game["extraction"]["ir"]["seed_counter"]) == ir_seed + 2, "Second planned campaign must start only after the first completes")
	check(str(game["extraction"]["ir"]["campaign"].get("strategy_id", "")) == "reliable", "Sequential queue did not preserve its second strategy")
	model(SITES_PATH, "advance", [p, 10000.0])
	check(int(model(MATH_PATH, "game", [p])["extraction"]["ir"]["campaigns_completed"]) == 2, "Both plans should resolve through real campaign advancement")
