extends SceneTree

const Industrial = preload("res://gameplay/IndustrialFeatures.gd")
const Sites = preload("res://gameplay/SiteModel.gd")
const Economy = preload("res://gameplay/EconomyModel.gd")
const Math = preload("res://gameplay/GameMath.gd")

var failures: PackedStringArray = []

func _initialize() -> void:
	_run.call_deferred()

func _check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)

func _profile() -> Dictionary:
	var p := {"money_cents":1000000, "inventory":{"iron_ore":100}, "sites":{
		"site_earth_fe_17":{"unlocked":true},
		"site_earth_pd_7":{"unlocked":true},
		"site_earth_ir_9":{"unlocked":true}
	}}
	var game := Math.game(p)
	game["progression"] = {"research":{}, "mastery":{}, "contracts":{"active":{}}}
	Economy.ensure(p)
	Sites.ensure(p)
	Industrial.ensure(p)
	return p

func _own(p: Dictionary, id: String) -> void:
	var catalog := "mastery" if id.contains("_SK") else "research"
	Math.game(p)["progression"][catalog][id] = 1

func _act(p: Dictionary, id: String, action: String, args: Dictionary = {}) -> Dictionary:
	var values := args.duplicate(true)
	values["id"] = id
	return Industrial.act(p, action, values)

func _advance_site(p: Dictionary, seconds: float) -> void:
	Sites.advance(p, seconds)

func _analyzed_sample(p: Dictionary) -> void:
	Sites.act(p, "take_sample", {"site":"pd"})
	var sample: Dictionary = Sites.view(p, "pd").get("sample", {})
	_advance_site(p, float(sample.get("sample_duration_s", 0.0)) + 1.0)
	Sites.act(p, "analyze_sample", {"site":"pd", "score":0.5})
	sample = Sites.view(p, "pd").get("sample", {})
	_advance_site(p, float(sample.get("analysis_duration_s", 0.0)) + 1.0)

func _run() -> void:
	var registry: Node = root.get_node("ContentRegistry")
	_check(registry.is_loaded, "Canonical catalogs failed to load: " + str(registry.errors))
	if registry.is_loaded:
		_test_lens_and_contract_profile()
		_test_paid_analysis_without_output_or_seed_change()
		_test_reports_and_shared_forecasts()
		_test_filter_prep_and_recipe_profile()
		_test_ir_route_pause_and_preparations()
		_test_sequential_program_and_contract_route()
		_test_ancient_expedition_report()
		_test_coverage()
	if failures.is_empty():
		print("industrial_features_test: all checks passed")
	else:
		for failure in failures:
			push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _test_lens_and_contract_profile() -> void:
	var p := _profile()
	_own(p, "PD05")
	_check(Sites.lens_definitions().size() == 3, "Optional lens changed the three canonical Pd lenses")
	_check(Sites.view(p, "pd").get("lens_options", []).size() == 4, "PD05 did not expose one optional lens forecast")
	var selected := _act(p, "PD05", "industry_select_lens", {"lens_id":"pd_lens_survey"})
	_check(bool(selected.get("ok", false)), "PD05 could not select its optional lens")
	_check(bool(Sites.act(p, "take_sample", {"site":"pd"}).get("ok", false)), "Optional lens sample did not start")
	_check(str(Sites.view(p, "pd").get("sample", {}).get("lens_id", "")) == "pd_lens_survey", "Optional lens did not control the actual sample")
	var contract_profile := _profile()
	_own(contract_profile, "PD17")
	Math.game(contract_profile)["progression"]["contracts"]["active"]["pd-order#0001"] = {"contract_id":"pd-order", "status":"accepted", "items":{"pd_concentrate":10}}
	_check(bool(_act(contract_profile, "PD17", "industry_set_contract_profile", {"order_id":"pd-order#0001"}).get("ok", false)), "PD17 rejected an accepted Pd contract")
	_check(bool(Sites.act(contract_profile, "take_sample", {"site":"pd"}).get("ok", false)), "PD17 contract-profiled sample did not start")
	_check(str(Sites.view(contract_profile, "pd").get("sample", {}).get("lens_id", "")) == "pd_lens_bulk", "PD17 did not select the profile for the accepted contract's actual quantity")
	_check(str(Industrial.ensure(contract_profile).pd.contract_order_id) == "", "PD17 profile was not consumed by one sample")

func _test_paid_analysis_without_output_or_seed_change() -> void:
	var baseline := _profile()
	var repeat := _profile()
	_own(repeat, "PD22")
	_analyzed_sample(baseline)
	_analyzed_sample(repeat)
	var before: Dictionary = Sites.view(repeat, "pd").get("sample", {}).duplicate(true)
	var money := int(repeat.money_cents)
	var started := _act(repeat, "PD22", "industry_repeat_analysis")
	_check(bool(started.get("ok", false)) and int(repeat.money_cents) < money, "PD22 repeat analysis was not paid and started")
	_check(int(Sites.view(repeat, "pd").get("sample", {}).get("seed", 0)) == int(before.seed), "PD22 changed the current production seed")
	_advance_site(repeat, float(Sites.view(repeat, "pd").sample.industrial_analysis.duration_s) + 1.0)
	var after: Dictionary = Sites.view(repeat, "pd").get("sample", {})
	_check(str(Sites.view(repeat, "pd").status) == "ready", "PD22 analysis did not return the sample to ready")
	_check(int(after.get("seed", 0)) == int(before.seed) and int(after.get("base_yield", 0)) == int(before.base_yield), "PD22 altered existing sample data")
	_check(int(repeat.inventory.get("pd_concentrate", 0)) == 0 and int(repeat.game.extraction.pd.pending_output) == 0, "PD22 produced extra Pd output")
	Sites.act(baseline, "start_cycle", {"site":"pd"})
	Sites.act(repeat, "start_cycle", {"site":"pd"})
	var base_sample: Dictionary = Sites.view(baseline, "pd").sample
	var repeat_sample: Dictionary = Sites.view(repeat, "pd").sample
	_advance_site(baseline, float(base_sample.cycle_duration_s) + 1.0)
	_advance_site(repeat, float(repeat_sample.cycle_duration_s) + 1.0)
	_check(int(baseline.inventory.get("pd_concentrate", 0)) == int(repeat.inventory.get("pd_concentrate", 0)), "Paid repeat analysis changed the subsequent production result")
	var second := _profile()
	_own(second, "PD_SK02")
	Sites.act(second, "take_sample", {"site":"pd"})
	var second_sample: Dictionary = Sites.view(second, "pd").sample
	_advance_site(second, float(second_sample.sample_duration_s) + 1.0)
	var second_seed := int(Sites.view(second, "pd").sample.seed)
	_check(bool(_act(second, "PD_SK02", "industry_take_second_sample").get("ok", false)), "PD_SK02 additional sample could not start")
	_advance_site(second, 37.0)
	_check(int(Sites.view(second, "pd").sample.seed) == second_seed and int(second.inventory.get("pd_concentrate", 0)) == 0, "PD_SK02 rerolled the production sample or created output")

func _test_reports_and_shared_forecasts() -> void:
	var p := _profile()
	_own(p, "PD27")
	_analyzed_sample(p)
	_check(bool(_act(p, "PD27", "industry_start_impurity_report", {"target_id":"sulfide"}).get("ok", false)), "PD27 paid report task did not start")
	_check(not Industrial.ensure(p).pd.reports.has("sulfide"), "PD27 issued a report before analysis completed")
	_advance_site(p, 31.0)
	_check(Industrial.ensure(p).pd.reports.has("sulfide"), "PD27 did not collect the report after actual analysis")
	_check(not bool(_act(p, "PD27", "industry_start_impurity_report", {"target_id":"sulfide"}).get("ok", false)), "PD27 allowed the same one-time report twice")
	var forecast := _profile()
	_own(forecast, "PD23")
	var start := _act(forecast, "PD23", "industry_start_forecast", {"line_id":"0", "target_id":"sulfide_band"})
	_check(bool(start.get("ok", false)), "PD23 first georadar forecast did not start")
	var money := int(forecast.money_cents)
	_check(not bool(_act(forecast, "PD23", "industry_start_forecast", {"line_id":"1", "target_id":"fracture_zone"}).get("ok", false)), "PD23 exceeded actual georadar capacity")
	_check(int(forecast.money_cents) == money, "Rejected second forecast charged money")
	Industrial.advance(forecast, 33.0)
	_check(bool(_act(forecast, "PD23", "industry_start_forecast", {"line_id":"1", "target_id":"fracture_zone"}).get("ok", false)), "PD23 did not release real capacity after the first forecast")
	_check(int(forecast.inventory.get("pd_concentrate", 0)) == 0 and float(Math.site(forecast, "pd").get("mined", 0.0)) == 0.0, "Forecast lines created production")
	var distant := _profile()
	_own(distant, "PD29")
	_analyzed_sample(distant)
	_check(bool(_act(distant, "PD29", "industry_start_distant_analysis").get("ok", false)), "PD29 paid distant analysis did not start")
	_advance_site(distant, 55.0)
	_check(not Industrial.ensure(distant).pd.distant_note.is_empty() and int(distant.inventory.get("pd_concentrate", 0)) == 0, "PD29 failed to collect its note or produced Pd")

func _test_filter_prep_and_recipe_profile() -> void:
	var p := _profile()
	_own(p, "PD_SK06")
	var money := int(p.money_cents)
	_check(bool(_act(p, "PD_SK06", "industry_prepare_filter").get("ok", false)) and int(p.money_cents) < money, "Manual filter preparation was not paid")
	Industrial.advance(p, 25.0)
	_check(not Industrial.pd_filter_profile(p).is_empty(), "Manual filter preparation did not finish with real time")
	Sites.act(p, "take_sample", {"site":"pd"})
	var sample: Dictionary = Sites.view(p, "pd").sample
	_advance_site(p, float(sample.sample_duration_s) + 1.0)
	var original_cycle := float(Sites.view(p, "pd").sample.cycle_duration_s)
	_check(bool(Sites.act(p, "start_cycle", {"site":"pd"}).get("ok", false)), "Prepared next Pd cycle did not start")
	_check(float(Sites.view(p, "pd").sample.cycle_duration_s) < original_cycle and Industrial.pd_filter_profile(p).is_empty(), "Manual filter did not affect and consume exactly the next real cycle")
	var contact := _profile()
	_own(contact, "IR14")
	var before := Industrial.recipe_profile(contact, "R_IR_CONTACT")
	_check(before.is_empty(), "Unselected contact profile was already active")
	_check(bool(_act(contact, "IR14", "industry_prepare_contact_profile", {"profile_id":"speed"}).get("ok", false)), "IR14 could not pay for contact profile preparation")
	var selected := Industrial.take_recipe_profile(contact, "R_IR_CONTACT")
	_check(float(selected.get("duration_multiplier", 1.0)) < 1.0 and Industrial.take_recipe_profile(contact, "R_IR_CONTACT").is_empty(), "IR14 profile was not a one-real-job duration modifier")

func _test_ir_route_pause_and_preparations() -> void:
	var ordinary := _profile()
	var deep := _profile()
	_own(deep, "IR05")
	Sites.act(ordinary, "start_campaign", {"site":"ir", "strategy_id":"reliable"})
	_check(bool(_act(deep, "IR05", "industry_start_deep_route", {"strategy_id":"reliable"}).get("ok", false)), "IR05 deep campaign did not start")
	var ordinary_campaign: Dictionary = Sites.view(ordinary, "ir").campaign
	var deep_campaign: Dictionary = Sites.view(deep, "ir").campaign
	_check(int(deep_campaign.projected_cost_cents) > int(ordinary_campaign.projected_cost_cents) and float(deep_campaign.projected_duration_s) > float(ordinary_campaign.projected_duration_s), "IR05 deep route did not consume additional real campaign cost and time")
	var support := _profile()
	_own(support, "IR06")
	var before := int(support.money_cents)
	_check(bool(_act(support, "IR06", "industry_prepare_supports").get("ok", false)) and int(support.money_cents) < before, "IR06 support preparation was not paid")
	Industrial.advance(support, 43.0)
	_check(bool(Industrial.ensure(support).ir.support_prepared), "IR06 support preparation did not consume time")
	Sites.act(ordinary, "cancel", {"site":"ir"})
	Sites.act(support, "start_campaign", {"site":"ir", "strategy_id":"reliable"})
	_check(float(Sites.view(support, "ir").campaign.projected_duration_s) < float(ordinary_campaign.projected_duration_s) and not bool(Industrial.ensure(support).ir.support_prepared), "IR06 preparation did not improve and consume one real campaign")
	var manipulator := _profile()
	_own(manipulator, "IR_SK05")
	_check(bool(_act(manipulator, "IR_SK05", "industry_prepare_manipulator").get("ok", false)), "IR_SK05 manipulator prep did not start")
	Industrial.advance(manipulator, 49.0)
	Sites.act(manipulator, "start_campaign", {"site":"ir", "strategy_id":"reliable"})
	_check(float(Sites.view(manipulator, "ir").campaign.projected_duration_s) < float(ordinary_campaign.projected_duration_s), "IR_SK05 preparation did not affect one real campaign")
	var pause := _profile()
	_own(pause, "IR23")
	Sites.act(pause, "start_campaign", {"site":"ir", "strategy_id":"reliable"})
	var started: Dictionary = Sites.view(pause, "ir").campaign
	var paid_before := int(pause.money_cents)
	_check(bool(_act(pause, "IR23", "industry_pause_ir").get("ok", false)), "IR23 pause could not be planned")
	_advance_site(pause, float(started.phase_durations_s[0]) + 1.0)
	var paused: Dictionary = Sites.view(pause, "ir")
	_check(str(paused.status) == "paused" and not bool(paused.campaign.phase_paid[1]), "IR23 did not stop between already-paid phases")
	_check(int(pause.money_cents) == paid_before, "IR23 pause charged the next phase early")
	_check(bool(_act(pause, "IR23", "industry_resume_ir").get("ok", false)), "IR23 could not resume a paused campaign")
	var after_resume := int(pause.money_cents)
	_check(bool(Sites.view(pause, "ir").campaign.phase_paid[1]), "IR23 resume did not pay the next phase")
	_check(not bool(_act(pause, "IR23", "industry_resume_ir").get("ok", false)) and int(pause.money_cents) == after_resume, "IR23 resumed twice or charged the next phase twice")

func _test_sequential_program_and_contract_route() -> void:
	var p := _profile()
	_own(p, "IR16")
	var estimate := int(Sites.view(p, "ir").get("projection", {}).get("cost_cents", 0))
	var program := _act(p, "IR16", "industry_start_autoprogram", {"strategy_id":"reliable", "campaign_count":2, "budget_cents":estimate * 2 + 100})
	_check(bool(program.get("ok", false)), "IR16 rejected a fully forecast, explicit budget")
	var campaign: Dictionary = Sites.view(p, "ir").campaign
	_check(str(Sites.view(p, "ir").status) == "running" and str(campaign.industrial_program_id).begins_with("ir_program_"), "IR16 did not start a real first campaign")
	Sites.advance(p, float(campaign.projected_duration_s) * 2.0 + 5.0)
	var stats: Dictionary = Math.game(p).get("stats", {})
	_check(int(stats.get("ir_campaigns_started", 0)) == 2 and int(stats.get("ir_campaigns_completed", 0)) == 2, "IR16 did not run exactly two sequential campaigns")
	_check(not bool(Industrial.program_status(p).get("active", false)) and int(p.inventory.get("ir_core", 0)) == int(stats.get("ir_core_mined", 0)), "IR16 program did not stop cleanly after its budgeted campaigns")
	var route := _profile()
	_own(route, "IR17")
	Math.game(route)["progression"]["contracts"]["active"]["ir-order#0001"] = {"contract_id":"ir-order", "status":"accepted", "items":{"ir_core":10}}
	_check(bool(_act(route, "IR17", "industry_start_contract_route", {"order_id":"ir-order#0001"}).get("ok", false)), "IR17 did not select a route for a real accepted Ir order")
	_check(str(Sites.view(route, "ir").campaign.strategy_id) == "reliable", "IR17 selected the wrong safe route for the order size")
	var denied := _profile()
	_own(denied, "IR17")
	_check(not bool(_act(denied, "IR17", "industry_start_contract_route", {"order_id":"missing"}).get("ok", false)), "IR17 acted without an accepted contract")

func _test_ancient_expedition_report() -> void:
	var p := _profile()
	_own(p, "IR28")
	var before := int(p.money_cents)
	_check(bool(_act(p, "IR28", "industry_start_ancient_expedition").get("ok", false)) and int(p.money_cents) < before, "IR28 expedition was not paid")
	Industrial.advance(p, 97.0)
	var report: Dictionary = Industrial.ensure(p).ir.expedition.get("report", {})
	_check(str(report.get("id", "")) == "ancient_geological_markers" and bool(report.get("collected", false)), "IR28 did not collect its one-time report after elapsed time")
	_check(int(p.inventory.get("horizonite", 0)) == 0 and not Math.game(p).get("progression", {}).get("story_done", {}).has("A20"), "IR28 fabricated Horizonite or a story completion")

func _test_coverage() -> void:
	var report := Industrial.coverage()
	_check(int(report.get("total", 0)) == 16 and int(report.get("supported", 0)) == 16, "Industrial coverage omitted requested feature IDs")
	for id in ["PD05", "PD17", "PD22", "PD23", "PD27", "PD29", "PD_SK02", "PD_SK06", "IR05", "IR06", "IR14", "IR16", "IR17", "IR23", "IR28", "IR_SK05"]:
		_check(report.get("by_id", {}).get(id, {}).get("status", "") == "supported", "Feature is missing operative coverage: " + id)

