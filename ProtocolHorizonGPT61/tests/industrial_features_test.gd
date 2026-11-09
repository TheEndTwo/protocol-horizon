extends SceneTree

const Industrial = preload("res://gameplay/IndustrialFeatures.gd")
const Features = preload("res://gameplay/FeatureRuntime.gd")
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
	return Features.act(p, action, values)

func _industrial_act(p: Dictionary, id: String, action: String, args: Dictionary = {}) -> Dictionary:
	var values := args.duplicate(true)
	values["id"] = id
	return Industrial.act(p, action, values)

func _advance_site(p: Dictionary, seconds: float) -> void:
	Sites.advance(p, seconds)

func _analyzed_sample(p: Dictionary) -> void:
	Sites.act(p, "take_sample", {"site":"pd"})
	var sample: Dictionary = Sites.view(p, "pd").get("sample", {})
	_advance_site(p, float(sample.get("sample_duration_s", 0.0)) + 1.0)
	var bands: Array = Sites.view(p, "pd").get("sample", {}).get("spectral_profile", {}).get("bands", [])
	var band_id := str(bands[0].get("id", "")) if not bands.is_empty() else ""
	for band in bands:
		if float(band.get("intensity", 0.0)) > float(bands[0].get("intensity", 0.0)):
			band_id = str(band.get("id", ""))
	Sites.act(p, "analyze_sample", {"site":"pd", "spectral_band_id":band_id})
	sample = Sites.view(p, "pd").get("sample", {})
	_advance_site(p, float(sample.get("analysis_duration_s", 0.0)) + 1.0)

func _run() -> void:
	var registry: Node = root.get_node("ContentRegistry")
	_check(registry.is_loaded, "Canonical catalogs failed to load: " + str(registry.errors))
	if registry.is_loaded:
		_test_lens_and_contract_profile()
		_test_pd18_selected_lens_automation()
		_test_pd_spectral_masteries()
		_test_pd_contract_clean_plan()
		_test_paid_analysis_without_output_or_seed_change()
		_test_reports_and_shared_forecasts()
		_test_filter_prep_and_recipe_profile()
		_test_ir_route_pause_and_preparations()
		_test_ir_sk06_cooling_modes()
		_test_ir_skill_readouts_and_routes()
		_test_ir_phase_mode_and_reservation()
		_test_ir_sk08_contact_plan()
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

func _test_pd18_selected_lens_automation() -> void:
	var baseline := _profile()
	_check(bool(Sites.act(baseline, "select_lens", {"site":"pd", "lens_id":"pd_lens_high_grade"}).get("ok", false)), "Could not select a known lens for baseline automation comparison")
	_check(bool(Sites.act(baseline, "set_automatic", {"site":"pd", "enabled":true}).get("ok", false)), "Base balanced automation did not start")
	_check(str(Sites.view(baseline, "pd").sample.get("lens_id", "")) == "pd_lens_balanced", "Unowned baseline automation stopped using the free balanced lens")

	var advanced := _profile()
	_own(advanced, "PD18")
	_check(bool(Sites.act(advanced, "select_lens", {"site":"pd", "lens_id":"pd_lens_high_grade"}).get("ok", false)), "PD18 could not select a known production lens")
	_check(bool(_industrial_act(advanced, "PD18", "industry_set_selected_lens_automation", {"enabled":true}).get("ok", false)), "PD18 selected-lens automation did not start")
	var first: Dictionary = Sites.view(advanced, "pd").sample.duplicate(true)
	_check(str(first.get("lens_id", "")) == "pd_lens_high_grade", "PD18 did not queue the selected known lens")
	_advance_site(advanced, float(first.get("sample_duration_s", 0.0)) + float(first.get("cycle_duration_s", 0.0)) + float(first.get("sample_duration_s", 0.0)) + 2.0)
	var next: Dictionary = Sites.view(advanced, "pd").sample
	_check(str(next.get("lens_id", "")) == "pd_lens_high_grade", "PD18 did not queue the selected lens after the completed cycle")
	_check(int(Sites.view(advanced, "pd").seed_counter) == 2, "PD18 did not use the normal deterministic seed sequence")
	_check(not bool(_industrial_act(baseline, "PD18", "industry_set_selected_lens_automation", {"enabled":true}).get("ok", false)), "PD18 automation worked without ownership")

func _test_paid_analysis_without_output_or_seed_change() -> void:
	var baseline := _profile()
	var repeat := _profile()
	_own(repeat, "PD22")
	_analyzed_sample(baseline)
	_analyzed_sample(repeat)
	var before: Dictionary = Sites.view(repeat, "pd").get("sample", {}).duplicate(true)
	var money := int(repeat.money_cents)
	_check(not bool(Sites.act(repeat, "pd_industrial_analysis", {"site":"pd", "task_id":"pd_repeat_analysis", "duration_s":28.0}).get("ok", false)), "SiteModel allowed bypassing the paid, feature-owned analysis action")
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
	var second_seed_counter := int(Sites.view(second, "pd").seed_counter)
	var second_seed := int(Sites.view(second, "pd").sample.seed)
	_check(bool(_act(second, "PD_SK02", "industry_take_second_sample").get("ok", false)), "PD_SK02 additional sample could not start")
	Features.advance(second, 37.0)
	var preview: Dictionary = Industrial.ensure(second).pd.second_sample_preview
	_check(int(Sites.view(second, "pd").sample.seed) == second_seed and int(Sites.view(second, "pd").seed_counter) == second_seed_counter, "PD_SK02 changed the current sample or consumed the production seed")
	_check(int(preview.get("sample_number", 0)) == 2 and bool(preview.get("forecast_only", false)) and int(second.inventory.get("pd_concentrate", 0)) == 0, "PD_SK02 did not create a non-producing second-sample preview")

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
	Features.advance(forecast, 33.0)
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
	Features.advance(p, 25.0)
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
	contact.inventory.merge({"ir_refined":1, "pd_catalyst":1, "high_strength_alloy":2}, true)
	var quote_before := Economy.quote(contact, "ir", "recipe", "R_IR_CONTACT", 1)
	_check(bool(_act(contact, "IR14", "industry_prepare_contact_profile", {"profile_id":"speed"}).get("ok", false)), "IR14 could not pay for contact profile preparation")
	var queued := Economy.act(contact, "queue", {"recipe":"R_IR_CONTACT", "line":0, "count":1})
	Features.after_action(contact, "economy", "queue", {"recipe":"R_IR_CONTACT", "line":0, "count":1}, queued)
	var contact_job: Dictionary = Math.game(contact).factory[0].queue[0]
	_check(bool(queued.get("ok", false)) and str(contact_job.get("industrial_profile_id", "")) == "speed", "IR14 did not attach its profile to the next paid contact job")
	_check(float(contact_job.get("seconds_per_unit", 180.0)) < 180.0 and Economy.quote(contact, "ir", "recipe", "R_IR_CONTACT", 1).cost_cents == quote_before.cost_cents, "IR14 changed more than the duration of one real job")
	_check(Industrial.take_recipe_profile(contact, "R_IR_CONTACT").is_empty(), "IR14 profile was reusable after one real job")

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
	Features.advance(support, 43.0)
	_check(bool(Industrial.ensure(support).ir.support_prepared), "IR06 support preparation did not consume time")
	Sites.act(ordinary, "cancel", {"site":"ir"})
	Sites.act(support, "start_campaign", {"site":"ir", "strategy_id":"reliable"})
	_check(float(Sites.view(support, "ir").campaign.projected_duration_s) < float(ordinary_campaign.projected_duration_s) and not bool(Industrial.ensure(support).ir.support_prepared), "IR06 preparation did not improve and consume one real campaign")
	var manipulator := _profile()
	_own(manipulator, "IR_SK05")
	_check(bool(_act(manipulator, "IR_SK05", "industry_prepare_manipulator").get("ok", false)), "IR_SK05 manipulator prep did not start")
	Features.advance(manipulator, 49.0)
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

func _test_ir_sk06_cooling_modes() -> void:
	var baseline := _profile()
	baseline["profile_id"] = "ir-sk06-mode-comparison"
	var economy := _profile()
	economy["profile_id"] = "ir-sk06-mode-comparison"
	_own(economy, "IR_SK06")
	var fast := _profile()
	fast["profile_id"] = "ir-sk06-mode-comparison"
	_own(fast, "IR_SK06")
	_check(bool(_industrial_act(economy, "IR_SK06", "industry_set_cooling_mode", {"cooling_mode_id":"economical"}).get("ok", false)), "IR_SK06 could not select the economical mode")
	_check(bool(_industrial_act(fast, "IR_SK06", "industry_set_cooling_mode", {"cooling_mode_id":"fast"}).get("ok", false)), "IR_SK06 could not select the fast mode")
	var base_projection: Dictionary = Sites.view(baseline, "ir").projection
	var economy_projection: Dictionary = Sites.view(economy, "ir").projection
	var fast_projection: Dictionary = Sites.view(fast, "ir").projection
	_check(int(economy_projection.cost_cents) < int(base_projection.cost_cents) and float(economy_projection.duration_seconds) > float(base_projection.duration_seconds), "IR_SK06 economical mode did not lower cost and increase known duration")
	_check(int(fast_projection.cost_cents) > int(base_projection.cost_cents) and float(fast_projection.duration_seconds) < float(base_projection.duration_seconds), "IR_SK06 fast mode did not increase cost and shorten known duration")
	_check(float(economy_projection.projected_peak_temperature_c) > float(fast_projection.projected_peak_temperature_c), "IR_SK06 modes did not produce distinct temperature projections")
	_check(str(base_projection.cooling_mode_id) == "" and str(economy_projection.cooling_mode_id) == "economical" and str(fast_projection.cooling_mode_id) == "fast", "Cooling mode projection was not ownership-gated and identified")
	Sites.act(baseline, "start_campaign", {"site":"ir", "strategy_id":"reliable"})
	Sites.act(economy, "start_campaign", {"site":"ir", "strategy_id":"reliable"})
	Sites.act(fast, "start_campaign", {"site":"ir", "strategy_id":"reliable"})
	var base_campaign: Dictionary = Sites.view(baseline, "ir").campaign
	var economy_campaign: Dictionary = Sites.view(economy, "ir").campaign
	var fast_campaign: Dictionary = Sites.view(fast, "ir").campaign
	_check(str(economy_campaign.cooling_mode_id) == "economical" and str(fast_campaign.cooling_mode_id) == "fast", "IR_SK06 mode was not snapshotted on each real campaign")
	_check(int(base_campaign.seed) == int(economy_campaign.seed) and int(base_campaign.seed) == int(fast_campaign.seed) and int(base_campaign.raw_yield) == int(economy_campaign.raw_yield) and int(base_campaign.raw_yield) == int(fast_campaign.raw_yield), "Changing cooling mode rerolled the deterministic campaign")
	_check(not bool(_industrial_act(economy, "IR_SK06", "industry_set_cooling_mode", {"cooling_mode_id":"fast"}).get("ok", false)) and str(Sites.view(economy, "ir").campaign.cooling_mode_id) == "economical", "IR_SK06 changed the in-flight campaign cooling snapshot")
	Sites.advance(economy, 200.0)
	Sites.advance(fast, 200.0)
	_check(float(Sites.view(fast, "ir").temperature_c) < float(Sites.view(economy, "ir").temperature_c), "IR_SK06 cooling profile did not affect live campaign temperature: fast=%s, economy=%s" % [str(Sites.view(fast, "ir").temperature_c), str(Sites.view(economy, "ir").temperature_c)])

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
	var blocked := _profile()
	_own(blocked, "IR16")
	var blocked_cost := int(Sites.view(blocked, "ir").projection.cost_cents)
	_check(bool(_act(blocked, "IR16", "industry_start_autoprogram", {"strategy_id":"reliable", "campaign_count":2, "budget_cents":blocked_cost * 2 + 100}).get("ok", false)), "IR16 storage-stop scenario did not start")
	blocked.inventory["test_storage_fill"] = Math.capacity(blocked) - 1
	_advance_site(blocked, 2000.0)
	_check(not bool(Industrial.program_status(blocked).get("active", false)) and int(Sites.view(blocked, "ir").pending_output) > 0, "IR16 started another safe campaign while prior output could not be stored")
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
	Features.advance(p, 97.0)
	var report: Dictionary = Industrial.ensure(p).ir.expedition.get("report", {})
	_check(str(report.get("id", "")) == "ancient_geological_markers" and bool(report.get("collected", false)), "IR28 did not collect its one-time report after elapsed time")
	_check(int(p.inventory.get("horizonite", 0)) == 0 and not Math.game(p).get("progression", {}).get("story_done", {}).has("A20"), "IR28 fabricated Horizonite or a story completion")

func _test_pd_spectral_masteries() -> void:
	var baseline := _profile()
	baseline["profile_id"] = "pd-spectrum-skill-test"
	var skilled := _profile()
	skilled["profile_id"] = "pd-spectrum-skill-test"
	for id in ["PD_SK01", "PD_SK03", "PD_SK04", "PD_SK05"]: _own(skilled, id)
	Math.game(skilled)["progression"]["contracts"]["active"]["pd-value-order"] = {"contract_id":"pd-value-order", "status":"accepted", "items":{"pd_concentrate":8}, "reward":{"money_cents":6000}}
	Sites.act(baseline, "take_sample", {"site":"pd"})
	Sites.act(skilled, "take_sample", {"site":"pd"})
	var view: Dictionary = Sites.view(skilled, "pd")
	var sample: Dictionary = view.get("sample", {})
	var bands: Array = sample.get("spectral_profile", {}).get("bands", [])
	_check(bands.size() == 2 and not sample.get("spectral_profile", {}).has("target_band_id"), "Pd sample exposed no real two-band choice or leaked its answer")
	_check(not str(sample.get("highlighted_impurity_region", "")).is_empty(), "PD_SK01 did not highlight an impurity region in the real sample")
	_check(view.get("skill_readouts", {}).get("PD_SK03", {}).get("lens_comparison", []).size() == 3, "PD_SK03 did not expose all three base lens comparisons")
	_check(not view.get("skill_readouts", {}).get("PD_SK04", {}).get("active_contract_values", []).is_empty(), "PD_SK04 omitted accepted-contract net-value forecasts")
	var target_band := str(Math.game(skilled).get("extraction", {}).get("pd", {}).get("sample", {}).get("spectral_profile", {}).get("target_band_id", ""))
	var baseline_bands: Array = Sites.view(baseline, "pd").get("sample", {}).get("spectral_profile", {}).get("bands", [])
	var baseline_target := str(Math.game(baseline).get("extraction", {}).get("pd", {}).get("sample", {}).get("spectral_profile", {}).get("target_band_id", ""))
	_advance_site(skilled, float(sample.get("sample_duration_s", 0.0)) + 1.0)
	_advance_site(baseline, float(Sites.view(baseline, "pd").sample.get("sample_duration_s", 0.0)) + 1.0)
	_check(bool(_industrial_act(skilled, "PD_SK05", "industry_analyze_spectrum", {"spectral_band_id":target_band}).get("ok", false)), "PD_SK05 rejected a measured spectral band")
	_check(bool(Sites.act(baseline, "analyze_sample", {"site":"pd", "spectral_band_id":baseline_target}).get("ok", false)), "Free base spectral analysis rejected a measured band")
	var skilled_sample: Dictionary = Sites.view(skilled, "pd").sample
	var baseline_sample: Dictionary = Sites.view(baseline, "pd").sample
	_check(float(skilled_sample.get("analysis_skill_bonus", 0.0)) > 0.0 and float(baseline_sample.get("analysis_skill_bonus", 0.0)) == 0.0, "PD_SK05 bonus was not gated to its accurate real-sample choice")
	_check(bands.size() == baseline_bands.size(), "Equivalent samples generated inconsistent spectrum structures")
	var quick := _profile()
	var ordinary := _profile()
	quick["profile_id"] = "pd-express-analysis-test"
	ordinary["profile_id"] = "pd-express-analysis-test"
	_own(quick, "PD_SK07")
	Sites.act(quick, "take_sample", {"site":"pd"})
	Sites.act(ordinary, "take_sample", {"site":"pd"})
	var quick_sample: Dictionary = Sites.view(quick, "pd").sample
	var ordinary_sample: Dictionary = Sites.view(ordinary, "pd").sample
	_advance_site(quick, float(quick_sample.sample_duration_s) + 1.0)
	_advance_site(ordinary, float(ordinary_sample.sample_duration_s) + 1.0)
	var quick_band := str(Sites.view(quick, "pd").sample.spectral_profile.bands[0].id)
	var ordinary_band := str(Sites.view(ordinary, "pd").sample.spectral_profile.bands[0].id)
	_check(bool(_industrial_act(quick, "PD_SK07", "industry_express_analysis", {"spectral_band_id":quick_band}).get("ok", false)), "PD_SK07 express analysis did not start")
	_check(bool(Sites.act(ordinary, "analyze_sample", {"site":"pd", "spectral_band_id":ordinary_band}).get("ok", false)), "Base analysis did not start for duration comparison")
	_check(float(Sites.view(quick, "pd").sample.analysis_duration_s) < float(Sites.view(ordinary, "pd").sample.analysis_duration_s), "PD_SK07 did not shorten a real analysis interval")

func _test_pd_contract_clean_plan() -> void:
	var p := _profile()
	_own(p, "PD_SK08")
	Math.game(p)["progression"]["contracts"]["active"]["pd-clean-order"] = {"contract_id":"pd-clean-order", "status":"accepted", "items":{"pd_concentrate":10}, "reward":{"money_cents":9000}}
	var started := _act(p, "PD_SK08", "industry_start_pd_contract_clean_plan", {"order_id":"pd-clean-order"})
	_check(bool(started.get("ok", false)) and bool(started.get("one_batch", false)), "PD_SK08 did not start one actual contract-directed sample")
	var sample: Dictionary = Sites.view(p, "pd").sample
	_check(bool(Sites.view(p, "pd").automatic) and bool(Math.game(p).get("extraction", {}).get("pd", {}).get("one_shot_contract_clean", false)), "PD_SK08 did not arm exactly one automatic production cycle")
	_advance_site(p, float(sample.sample_duration_s) + float(sample.cycle_duration_s) + 2.0)
	var state: Dictionary = Sites.view(p, "pd")
	_check(int(state.cycles_completed) == 1 and not bool(state.automatic) and int(state.seed_counter) == 1, "PD_SK08 repeated production or rerolled its sample seed")
	_check(str(Industrial.ensure(p).pd.one_shot_clean_order_id) == "", "PD_SK08 left a stale one-shot order after production")

func _test_ir_skill_readouts_and_routes() -> void:
	var readout := _profile()
	for id in ["IR_SK01", "IR_SK02", "IR_SK03"]: _own(readout, id)
	var readouts: Dictionary = Sites.view(readout, "ir").get("skill_readouts", {})
	_check(not readouts.get("IR_SK01", {}).get("support_phase_id", "").is_empty(), "IR_SK01 omitted its real peak-heat support phase")
	_check(not readouts.get("IR_SK02", {}).get("maximum_cooling_phase_id", "").is_empty(), "IR_SK02 omitted its maximum-cooling phase")
	_check(readouts.get("IR_SK03", {}).get("strategy_comparisons", []).size() >= 2, "IR_SK03 omitted strategy stability-margin comparison")
	var base := _profile()
	var detour := _profile()
	var cleanup := _profile()
	for p in [base, detour, cleanup]: p["profile_id"] = "ir-route-mode-test"
	_own(detour, "IR22")
	_own(cleanup, "IR27")
	_check(bool(_industrial_act(detour, "IR22", "industry_set_guaranteed_detour", {"enabled":true}).get("ok", false)), "IR22 detour selection failed")
	_check(bool(_industrial_act(cleanup, "IR27", "industry_set_fast_cleanup", {"enabled":true}).get("ok", false)), "IR27 cleanup selection failed")
	var base_projection: Dictionary = Sites.view(base, "ir").projection
	var detour_projection: Dictionary = Sites.view(detour, "ir").projection
	var cleanup_projection: Dictionary = Sites.view(cleanup, "ir").projection
	_check(int(detour_projection.cost_cents) > int(base_projection.cost_cents) and float(detour_projection.duration_seconds) > float(base_projection.duration_seconds) and int(detour_projection.guaranteed_output_floor_units) > 0, "IR22 did not project its guaranteed detour's real cost, time and output floor")
	_check(float(cleanup_projection.duration_seconds) < float(base_projection.duration_seconds) and float(cleanup_projection.expected_yield) < float(base_projection.expected_yield), "IR27 did not project a faster lower-yield cleanup")
	for p in [base, detour, cleanup]: Sites.act(p, "start_campaign", {"site":"ir", "strategy_id":"reliable"})
	var base_campaign: Dictionary = Sites.view(base, "ir").campaign
	var detour_campaign: Dictionary = Sites.view(detour, "ir").campaign
	var cleanup_campaign: Dictionary = Sites.view(cleanup, "ir").campaign
	_check(int(base_campaign.seed) == int(detour_campaign.seed) and int(base_campaign.seed) == int(cleanup_campaign.seed), "IR22/IR27 mode choice rerolled deterministic campaign inputs")
	_check(int(detour_campaign.guaranteed_output_floor_units) > 0 and float(cleanup_campaign.cleanup_yield_multiplier) < 1.0, "IR22/IR27 settings were not snapshotted onto the actual campaign")
	_check(float(cleanup_campaign.phase_durations_s.back()) < float(base_campaign.phase_durations_s.back()), "IR27 did not change the real cleanup phase duration")

func _test_ir_phase_mode_and_reservation() -> void:
	var p := _profile()
	_own(p, "IR_SK04")
	Sites.act(p, "start_campaign", {"site":"ir", "strategy_id":"reliable"})
	var before: Dictionary = Sites.view(p, "ir").campaign
	var paid_before := int(before.committed_cost_cents)
	var phase_index := 2
	var changed := _act(p, "IR_SK04", "industry_configure_unstarted_ir_phase", {"phase_index":phase_index, "phase_mode_id":"expedited"})
	var after: Dictionary = Sites.view(p, "ir").campaign
	_check(bool(changed.get("ok", false)) and float(after.phase_durations_s[phase_index]) < float(before.phase_durations_s[phase_index]) and int(after.phase_costs_cents[phase_index]) > int(before.phase_costs_cents[phase_index]), "IR_SK04 did not alter only the selected future phase: result=%s, duration=%s->%s, cost=%s->%s" % [str(changed), str(before.phase_durations_s[phase_index]), str(after.phase_durations_s[phase_index]), str(before.phase_costs_cents[phase_index]), str(after.phase_costs_cents[phase_index])])
	_check(int(after.committed_cost_cents) == paid_before and not bool(after.phase_paid[phase_index]), "IR_SK04 charged or marked a future phase as paid")
	_check(not bool(_act(p, "IR_SK04", "industry_configure_unstarted_ir_phase", {"phase_index":0, "phase_mode_id":"economical"}).get("ok", false)), "IR_SK04 changed an already paid phase")
	var reserve := _profile()
	_own(reserve, "IR_SK07")
	reserve["inventory"]["ir_core"] = 2
	_check(bool(_act(reserve, "IR_SK07", "industry_reserve_ir_core_for_cleanup").get("ok", false)), "IR_SK07 did not reserve a real owned Ir core")
	_check(Math.free_amount(reserve, "ir_core") == 1 and int(Sites.view(reserve, "ir").priority_cleanup_reserve.amount) == 1, "IR_SK07 did not expose its existing reserved core")
	_check(bool(_act(reserve, "IR_SK07", "industry_release_ir_core_cleanup_reserve").get("ok", false)) and Math.free_amount(reserve, "ir_core") == 2, "IR_SK07 could not release its real reserve")

func _test_ir_sk08_contact_plan() -> void:
	var p := _profile()
	_own(p, "IR_SK08")
	p.inventory.merge({"ir_refined":2, "pd_catalyst":1, "high_strength_alloy":2, "pd_concentrate":3}, true)
	var result := _act(p, "IR_SK08", "industry_plan_ir_contact_and_reserves", {"strategy_id":"economic", "line":0, "contact_count":1, "pd_reserve":2, "fe_reserve":4})
	_check(bool(result.get("ok", false)), "IR_SK08 combined route, real recipe and free-material reserve plan failed: " + str(result.get("message", "")))
	_check(str(Sites.view(p, "ir").strategy_id) == "economic" and not Math.game(p).get("factory", [])[0].get("queue", []).is_empty(), "IR_SK08 did not apply its route or queue the real contact recipe")
	_check(int(Math.game(p).get("reservations", {}).get("mastery:IR_SK08:pd_fe_plan", {}).get("pd_concentrate", 0)) == 2 and int(Math.game(p).get("reservations", {}).get("mastery:IR_SK08:pd_fe_plan", {}).get("iron_ore", 0)) == 4, "IR_SK08 did not reserve the actual free Pd/Fe inventory")

func _test_coverage() -> void:
	var report := Industrial.coverage()
	_check(int(report.get("total", 0)) == 32 and report.get("supported_ids", []).size() == 32, "Industrial coverage omitted requested feature IDs")
	var p := _profile()
	for id in Industrial._feature_ids():
		_check(report.get("by_id", {}).get(id, {}).get("status", "") == "supported", "Feature is missing operative coverage: " + id)
		_check(report.get("supported_ids", []).has(id), "Feature ID missing from aggregate support set: " + id)
		if not report.get("by_id", {}).get(id, {}).get("readout_only", false):
			_check(not report.get("by_id", {}).get(id, {}).get("actions", []).is_empty(), "Coverage has no UI action evidence for " + id)
		_own(p, id)
		var operations: Array = Industrial.operations(p, id)
		if not report.get("by_id", {}).get(id, {}).get("readout_only", false):
			_check(not operations.is_empty(), "IndustrialFeatures did not expose native UI actions for " + id)
		for operation in operations:
			for field in operation.get("fields", []):
				var field_type := str(field.get("type", ""))
				_check(field_type in ["select", "number", "toggle"], "Feature uses an unsupported native control type: " + id + "/" + field_type)
				if field_type == "select":
					_check(field.get("choices", []) is Array, "Select descriptor has no choices array: " + id)
	_check(bool(_industrial_act(p, "PD18", "industry_set_selected_lens_automation", {"enabled":true}).get("ok", false)), "PD18 could not persist its selected-lens automation toggle")
	_check(bool(Industrial.operations(p, "PD18")[0].get("fields", [])[0].get("value", false)), "PD18 operation did not report its current toggle value")
	_check(bool(_industrial_act(p, "IR22", "industry_set_guaranteed_detour", {"enabled":true}).get("ok", false)), "IR22 could not persist its detour toggle")
	_check(bool(Industrial.operations(p, "IR22")[0].get("fields", [])[0].get("value", false)), "IR22 operation did not report its current toggle value")
	_check(bool(_industrial_act(p, "IR27", "industry_set_fast_cleanup", {"enabled":true}).get("ok", false)), "IR27 could not persist its cleanup toggle")
	_check(bool(Industrial.operations(p, "IR27")[0].get("fields", [])[0].get("value", false)), "IR27 operation did not report its current toggle value")
	_check(bool(_industrial_act(p, "IR_SK06", "industry_set_cooling_mode", {"cooling_mode_id":"fast"}).get("ok", false)), "IR_SK06 could not persist its cooling select")
	_check(str(Industrial.operations(p, "IR_SK06")[0].get("fields", [])[0].get("value", "")) == "fast", "IR_SK06 operation did not report its current select value")
