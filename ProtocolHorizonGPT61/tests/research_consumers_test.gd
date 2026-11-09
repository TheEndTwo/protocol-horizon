extends SceneTree

const State = preload("res://autoload/GameState.gd")
const Economy = preload("res://gameplay/EconomyModel.gd")
const Progression = preload("res://gameplay/ProgressionModel.gd")
const Sites = preload("res://gameplay/SiteModel.gd")
const Research = preload("res://gameplay/ResearchRuntime.gd")

var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func _run() -> void:
	var registry: Node = root.get_node("ContentRegistry")
	check(registry.is_loaded, "Canonical catalogs are not loaded: " + str(registry.errors))
	_test_worker_and_drill_scope()
	_test_factory_speed_and_margin()
	_test_geology_duration_and_legacy_flags()
	_test_pd_consumers()
	_test_ir_consumers()
	if failures.is_empty():
		print("research_consumers_test: scoped model hooks passed")
	else:
		for failure in failures:
			push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _profile() -> Dictionary:
	var p := State.make_new_profile()
	p["money_cents"] = 1000000
	p["sites"]["site_earth_pd_7"]["unlocked"] = true
	p["sites"]["site_earth_ir_9"]["unlocked"] = true
	p["inventory"]["iron_ore"] = 100
	Economy.ensure(p)
	Progression.ensure(p)
	Sites.ensure(p)
	Research.refresh(p)
	return p

func _set_rank(p: Dictionary, track: String, id: String, level: int) -> void:
	var progression: Dictionary = GameMath.game(p)["progression"]
	var levels: Dictionary = progression[track]
	levels[id] = level
	Research.refresh(p)

func _test_worker_and_drill_scope() -> void:
	var miner := _profile()
	GameMath.site(miner, "fe")["workers"]["iron_miner"] = 4
	var trained_miner: Dictionary = miner.duplicate(true)
	_set_rank(trained_miner, "research", "P02", 1)
	var worker_before := Economy.metrics(miner, "fe")
	var worker_after := Economy.metrics(trained_miner, "fe")
	check(float(worker_after["worker_rate_per_second"]) > float(worker_before["worker_rate_per_second"]), "P02 did not improve the miner contribution")
	check(is_equal_approx(float(worker_before["base_rate_per_second"]), float(worker_after["base_rate_per_second"])) and is_equal_approx(float(worker_before["output_multiplier"]), float(worker_after["output_multiplier"])), "Miner training leaked into the site's base or global output multiplier")
	check(is_equal_approx(float(Economy.metrics(miner, "pd")["rate_per_second"]), float(Economy.metrics(trained_miner, "pd")["rate_per_second"])), "Fe miner training leaked to Pd")
	var non_miner := _profile()
	GameMath.site(non_miner, "fe")["workers"]["iron_driller"] = 4
	var trained_non_miner: Dictionary = non_miner.duplicate(true)
	_set_rank(trained_non_miner, "research", "P02", 1)
	check(is_equal_approx(float(Economy.metrics(non_miner, "fe")["worker_rate_per_second"]), float(Economy.metrics(trained_non_miner, "fe")["worker_rate_per_second"])), "Miner training changed a non-miner worker")

	var drill := _profile()
	GameMath.site(drill, "fe")["machines"]["iron_drill"] = 10
	var improved_drill: Dictionary = drill.duplicate(true)
	_set_rank(improved_drill, "research", "A02", 1)
	var drill_before := Economy.metrics(drill, "fe")
	var drill_after := Economy.metrics(improved_drill, "fe")
	check(float(drill_after["machine_rate_per_second"]) > float(drill_before["machine_rate_per_second"]), "A02 did not improve the iron drill's own contribution")
	check(is_equal_approx(float(drill_before["worker_rate_per_second"]), float(drill_after["worker_rate_per_second"])) and is_equal_approx(float(drill_before["output_multiplier"]), float(drill_after["output_multiplier"])), "Drill research leaked into workers or the global output multiplier")
	check(is_equal_approx(float(Economy.metrics(drill, "ir")["rate_per_second"]), float(Economy.metrics(improved_drill, "ir")["rate_per_second"])), "Fe drill research leaked to Ir")

func _test_factory_speed_and_margin() -> void:
	var base := _profile()
	base["inventory"]["iron_ore"] = 5
	var faster: Dictionary = base.duplicate(true)
	_set_rank(faster, "research", "A18", 1)
	var queued_base := Economy.act(base, "queue", {"recipe":"R_INGOT", "line":0, "count":1})
	var queued_faster := Economy.act(faster, "queue", {"recipe":"R_INGOT", "line":0, "count":1})
	check(bool(queued_base.get("ok", false)) and bool(queued_faster.get("ok", false)), "Could not queue the canonical ingot recipe")
	var line_base: Dictionary = GameMath.game(base)["factory"][0]
	var line_faster: Dictionary = GameMath.game(faster)["factory"][0]
	var job_base: Dictionary = line_base["active"] if not line_base["active"].is_empty() else line_base["queue"][0]
	var job_faster: Dictionary = line_faster["active"] if not line_faster["active"].is_empty() else line_faster["queue"][0]
	check(float(job_faster["seconds_per_unit"]) < float(job_base["seconds_per_unit"]), "A18 did not shorten the queued recipe duration")
	check(int(base["money_cents"]) == int(faster["money_cents"]) and int(base["inventory"]["iron_ore"]) == int(faster["inventory"]["iron_ore"]), "Recipe speed changed queue cost or input quantity")

	var raw_base := _profile()
	raw_base["inventory"]["iron_ore"] = 1
	var raw_ranked: Dictionary = raw_base.duplicate(true)
	_set_rank(raw_ranked, "research", "A17", 1)
	var raw_sale_base := Economy.act(raw_base, "sell", {"resource":"iron_ore", "amount":1})
	var raw_sale_ranked := Economy.act(raw_ranked, "sell", {"resource":"iron_ore", "amount":1})
	check(int(raw_sale_base.get("proceeds_cents", -1)) == int(raw_sale_ranked.get("proceeds_cents", -2)), "Factory margin incorrectly increased raw-ore sales")
	var product_base := _profile()
	product_base["inventory"]["ingot"] = 1
	var product_ranked: Dictionary = product_base.duplicate(true)
	_set_rank(product_ranked, "research", "A17", 1)
	var product_sale_base := Economy.act(product_base, "sell", {"resource":"ingot", "amount":1})
	var product_sale_ranked := Economy.act(product_ranked, "sell", {"resource":"ingot", "amount":1})
	check(int(product_sale_ranked.get("proceeds_cents", 0)) > int(product_sale_base.get("proceeds_cents", 0)), "A17 did not increase factory-product proceeds")

func _test_geology_duration_and_legacy_flags() -> void:
	var base := _profile()
	var faster: Dictionary = base.duplicate(true)
	_set_rank(faster, "research", "G06", 1)
	_set_rank(faster, "research", "G14", 1)
	var start_base := Progression.act(base, "geology_start", {"id":"fe_survey"})
	var start_faster := Progression.act(faster, "geology_start", {"id":"fe_survey"})
	check(bool(start_base.get("ok", false)) and bool(start_faster.get("ok", false)), "Could not start the canonical Fe survey")
	var active_base: Dictionary = GameMath.game(base)["progression"]["geology"]["active"]
	var active_faster: Dictionary = GameMath.game(faster)["progression"]["geology"]["active"]
	check(float(active_faster["remaining_seconds"]) < float(active_base["remaining_seconds"]), "Geology speed research did not shorten its expedition")
	check(int(base["money_cents"]) == int(faster["money_cents"]) and int(active_base["reward_shards"]) == int(active_faster["reward_shards"]), "Geology duration research changed cost or reward")

	var legacy := _profile()
	var game: Dictionary = GameMath.game(legacy)
	var progression: Dictionary = game["progression"]
	progression["research"] = {"D01":1, "D02":1, "D04":1}
	progression["effects"]["research_levels"] = progression["research"].duplicate(true)
	progression["effects"]["research_numeric_skip_ids"] = []
	game["bonuses"]["progression"] = {"fe:tap":0.25}
	Progression.refresh(legacy)
	var flags: Dictionary = progression["effects"]["flags"]
	check(not game["bonuses"]["progression"].has("fe:tap"), "Legacy D02/D04 numeric tap bonus was retained")
	check(bool(flags.get("D01:precision_chain", false)) and bool(flags.get("D02:bonus_pocket", false)) and bool(flags.get("D04:marked_enhanced_strike", false)), "Compatibility filtering removed legacy precision feature flags")

func _test_pd_consumers() -> void:
	var forecast_base := _profile()
	var forecast_ranked: Dictionary = forecast_base.duplicate(true)
	_set_rank(forecast_ranked, "research", "PD02", 1)
	var lens_base := _find(Sites.view(forecast_base, "pd")["lens_options"], "pd_lens_bulk")
	var lens_ranked := _find(Sites.view(forecast_ranked, "pd")["lens_options"], "pd_lens_bulk")
	var range_base: Array = lens_base["yield_range"]
	var range_ranked: Array = lens_ranked["yield_range"]
	check(float(range_ranked[1]) - float(range_ranked[0]) < float(range_base[1]) - float(range_base[0]), "PD02 did not narrow only its forecast range")
	check(is_equal_approx(float(lens_base["expected_yield"]), float(lens_ranked["expected_yield"])), "PD02 changed expected or actual sample yield")

	var sample_base := _profile()
	var sample_ranked: Dictionary = sample_base.duplicate(true)
	_set_rank(sample_ranked, "research", "PD08", 1)
	_set_rank(sample_ranked, "research", "PD11", 1)
	_set_rank(sample_ranked, "research", "PD12", 1)
	var start_base := _start_bulk_sample(sample_base)
	var start_ranked := _start_bulk_sample(sample_ranked)
	check(bool(start_base.get("ok", false)) and bool(start_ranked.get("ok", false)), "Could not start the bulk Pd sample")
	var sample_view_base: Dictionary = Sites.view(sample_base, "pd")["sample"]
	var sample_view_ranked: Dictionary = Sites.view(sample_ranked, "pd")["sample"]
	check(float(sample_view_ranked["cycle_duration_s"]) < float(sample_view_base["cycle_duration_s"]), "PD08 did not shorten only the bulk concentration stage")
	check(int(sample_view_ranked["sample_cost_cents"]) < int(sample_view_base["sample_cost_cents"]) and int(sample_view_ranked["operating_cost_cents"]) < int(sample_view_base["operating_cost_cents"]), "Pd sample and long-cycle cost reductions missed their expense stages")
	check(is_equal_approx(float(sample_view_ranked["quality"]), float(sample_view_base["quality"])) and int(sample_view_ranked["base_yield"]) == int(sample_view_base["base_yield"]), "Pd cost or speed research changed the sampled geology")

	var analysis_base := _profile()
	var analysis_ranked: Dictionary = analysis_base.duplicate(true)
	_set_rank(analysis_ranked, "mastery", "PD_SK05", 5)
	var output_base := _pd_analysis_yield(analysis_base)
	var output_ranked := _pd_analysis_yield(analysis_ranked)
	check(output_ranked > output_base, "PD_SK05 did not improve the one analyzed batch")

func _test_ir_consumers() -> void:
	var base := _profile()
	var setup_ranked: Dictionary = base.duplicate(true)
	_set_rank(setup_ranked, "research", "IR09", 1)
	var start_base := Sites.act(base, "start_campaign", {"site":"ir", "strategy_id":"reliable"})
	var start_ranked := Sites.act(setup_ranked, "start_campaign", {"site":"ir", "strategy_id":"reliable"})
	check(bool(start_base.get("ok", false)) and bool(start_ranked.get("ok", false)), "Could not start reliable Ir campaigns")
	var phases_base: Array = Sites.view(base, "ir")["campaign"]["phase_durations_s"]
	var phases_ranked: Array = Sites.view(setup_ranked, "ir")["campaign"]["phase_durations_s"]
	check(is_equal_approx(float(phases_base[0]), float(phases_ranked[0])) and float(phases_ranked[1]) < float(phases_base[1]), "IR09 changed phases outside preparation")
	check(int(base["money_cents"]) == int(setup_ranked["money_cents"]), "IR09 changed campaign costs")

	var forecast_base := _profile()
	var forecast_ranked: Dictionary = forecast_base.duplicate(true)
	_set_rank(forecast_ranked, "research", "IR03", 1)
	var projection_base := _strategy_projection(Sites.view(forecast_base, "ir")["strategy_options"], "reliable")
	var projection_ranked := _strategy_projection(Sites.view(forecast_ranked, "ir")["strategy_options"], "reliable")
	var ir_range_base: Array = projection_base["projection"]["yield_range"]
	var ir_range_ranked: Array = projection_ranked["projection"]["yield_range"]
	check(float(ir_range_ranked[1]) - float(ir_range_ranked[0]) < float(ir_range_base[1]) - float(ir_range_base[0]), "IR03 did not narrow its forecast range")
	check(is_equal_approx(float(projection_base["projection"]["expected_yield"]), float(projection_ranked["projection"]["expected_yield"])), "IR03 changed expected actual yield")

	var cooling_base := _profile()
	var cooling_ranked: Dictionary = cooling_base.duplicate(true)
	_set_rank(cooling_ranked, "research", "IR10", 1)
	Sites.act(cooling_base, "start_campaign", {"site":"ir", "strategy_id":"forced"})
	Sites.act(cooling_ranked, "start_campaign", {"site":"ir", "strategy_id":"forced"})
	var money_base := int(cooling_base["money_cents"])
	var money_ranked := int(cooling_ranked["money_cents"])
	var cool_base := Sites.act(cooling_base, "cool", {"site":"ir"})
	var cool_ranked := Sites.act(cooling_ranked, "cool", {"site":"ir"})
	check(bool(cool_base.get("ok", false)) and bool(cool_ranked.get("ok", false)), "Forced-route cooling action failed")
	check(money_base - int(cooling_base["money_cents"]) > money_ranked - int(cooling_ranked["money_cents"]), "IR10 did not reduce forced-route cooling expense")
	check(Sites.view(cooling_ranked, "pd")["lens_options"] == Sites.view(cooling_base, "pd")["lens_options"], "Ir research leaked into Pd projections")

func _start_bulk_sample(p: Dictionary) -> Dictionary:
	var selected := Sites.act(p, "pd_select_lens", {"site":"pd", "lens_id":"pd_lens_bulk"})
	if not bool(selected.get("ok", false)):
		return selected
	return Sites.act(p, "take_sample", {"site":"pd"})

func _pd_analysis_yield(p: Dictionary) -> float:
	var extraction := Sites.ensure(p)
	var state: Dictionary = extraction["pd"]
	state["status"] = "ready"
	state["lens_id"] = "pd_lens_balanced"
	state["sample"] = {"lens_id":"pd_lens_balanced", "seed":55, "quality":0.8, "base_yield":10, "analysis_completed":false, "analysis_bonus":0.0, "sample_cost_cents":0, "operating_cost_cents":0, "sample_duration_s":0.0, "cycle_duration_s":0.0, "yield_units":0}
	var analysis := Sites.act(p, "analyze_sample", {"site":"pd", "score":0.0})
	check(bool(analysis.get("ok", false)), "Could not start Pd batch analysis")
	var sample: Dictionary = state["sample"]
	sample["analysis_bonus_cap"] = 0.0
	sample["analysis_score"] = 0.0
	Sites.advance(p, float(sample["analysis_duration_s"]))
	var cycle := Sites.act(p, "start_cycle", {"site":"pd"})
	check(bool(cycle.get("ok", false)), "Could not start the analyzed Pd batch")
	return float(Sites.view(p, "pd")["sample"]["yield_units"])

func _find(options: Array, id: String) -> Dictionary:
	for option_value in options:
		var option: Dictionary = option_value
		if str(option.get("id", "")) == id:
			return option
	return {}

func _strategy_projection(options: Array, id: String) -> Dictionary:
	return _find(options, id)
