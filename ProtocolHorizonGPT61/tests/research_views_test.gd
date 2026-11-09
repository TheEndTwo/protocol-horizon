extends SceneTree

const Views = preload("res://gameplay/ResearchViews.gd")
const Runtime = preload("res://gameplay/ResearchRuntime.gd")
const ECONOMY = preload("res://gameplay/EconomyModel.gd")
const SITES = preload("res://gameplay/SiteModel.gd")

var failures: PackedStringArray = []

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func _run() -> void:
	var registry: Node = root.get_node("ContentRegistry")
	check(registry.is_loaded, "Canonical catalogs are not loaded: " + str(registry.errors))
	if registry.is_loaded:
		var p := _profile()
		var specialist_rows := GameMath.records("specialists")
		if not specialist_rows.is_empty():
			var specialist_id := str(specialist_rows[0].get("id", ""))
			GameMath.game(p)["meta"]["specialists"]["owned"][specialist_id] = {"level":20, "stars":1}
			GameMath.game(p)["meta"]["specialists"]["assignments"]["fe"] = {"0":specialist_id}
		_test_contracts(p)
		_test_gates(p)
	if failures.is_empty():
		print("research_views_test: all checks passed")
	else:
		for failure in failures:
			push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _profile() -> Dictionary:
	var p := {
		"profile_id":"research-views-test", "money_cents":1000000, "research_points":50,
		"inventory":{"iron_ore":500, "pd_concentrate":8, "ir_core":0},
		"sites":{
			"site_earth_fe_17":{"unlocked":true},
			"site_earth_pd_7":{"unlocked":true},
			"site_earth_ir_9":{"unlocked":true},
		},
		"game":{
			"sites":{}, "network":{"mode":"balanced", "autosell":true}, "meta":{"specialists":{"owned":{}, "assignments":{"fe":{}}, "fragments":{}}},
			"progression":{
				"research":{}, "mastery":{}, "story_done":{},
				"geology":{
					"discoveries":{"STRUCTURE_01":true, "deep_geology_signal":true, "old_project_record":true},
					"active":{"id":"deep_signal", "site":"ir", "sequence":2, "remaining_seconds":45.0, "reward_research_points":2, "reward_shards":3},
					"reports":[],
				},
			},
			"extraction":{
				"pd":{"status":"ready", "lens_id":"pd_lens_balanced", "elapsed_seconds":0.0, "measurement_history":[{"seed":11, "lens_id":"pd_lens_high_grade", "quality":0.84, "base_yield":6, "output_units":7, "analysis_completed":true, "sample_cost_cents":110, "operating_cost_cents":500, "measured_at":1700000000}], "sample":{"lens_id":"pd_lens_balanced", "quality":0.8, "base_yield":8, "yield_units":11, "analysis_completed":true, "analysis_bonus":0.04, "analysis_skill_bonus":0.0, "impurity_analysis_bonus":0.02, "identified_impurity":"carbonaceous", "spectral_profile":{"impurity_library":[{"id":"sulfide", "label":"Сульфиды", "hint":"Влияние учтено в измеренной чистоте партии."}, {"id":"silicate", "label":"Силикаты", "hint":"Влияние учтено в измеренной чистоте партии."}, {"id":"oxide", "label":"Оксиды", "hint":"Влияние учтено в измеренной чистоте партии."}, {"id":"carbonaceous", "label":"Углеродистые включения", "hint":"Верное выделение полосы добавляет 2% только этой партии."}]}, "seed":17}, "pending_output":0},
				"ir":{"status":"idle", "strategy_id":"reliable", "campaign":{}, "temperature_c":25.0, "pending_output":0},
			},
		},
	}
	ECONOMY.ensure(p)
	var fe := GameMath.site(p, "fe")
	fe["workers"] = {"iron_miner":2, "iron_driller":1}
	fe["machines"] = {"iron_drill":1}
	fe["upgrades"] = {"iron_tunnel_support":100}
	fe["horizon"] = 1
	var reports: Array = []
	for i in 22:
		reports.append({"id":"GEO-%04d" % (i + 1), "site":"fe" if i % 2 == 0 else "ir", "expedition":"fe_survey", "sequence":i + 1, "tags":["STRUCTURE_01" if i % 2 == 0 else "deep_geology_signal"], "identified_types":["структурный профиль"]})
	GameMath.game(p)["progression"]["geology"]["reports"] = reports
	GameMath.game(p)["progression"]["geology"]["expedition_counts"] = {"fe_survey":22}
	return p

func _test_contracts(p: Dictionary) -> void:
	var reports: Array = GameMath.game(p)["progression"]["geology"]["reports"]
	var pd := SITES.view(p.duplicate(true), "pd")
	var ir := SITES.view(p.duplicate(true), "ir")
	var cases := {
		"D06":{"unlocked_horizon_indices":[0, 1]},
		"P01":{"next_worker_quotes":[{"worker_id":"iron_miner", "name":"Шахтёры", "cost_cents":500, "quote_available":true, "net_increment_cents_per_hour":200, "payback_hours":2.5}]},
		"P08":{"current_net_at_catalog_price_cents_per_hour":1234.0},
		"P09":{"site":"fe", "cash_reserves":{"P09":2000}},
		"P11":{"site":"fe"},
		"P16":{"site":"fe"},
		"G01":{"reports":reports},
		"G05":{},
		"G07":{"reports":reports},
		"G11":{"horizons":[{"site":"fe", "horizon":0, "net_catalog_value_cents_per_hour":1000.0}, {"site":"fe", "horizon":1, "net_catalog_value_cents_per_hour":1400.0}]},
		"G13":{"reports":reports},
		"G15":{},
		"PD03":pd,
		"PD04":pd,
		"PD06":pd,
		"PD10":pd,
		"PD13":pd,
		"PD19":pd,
		"PD21":pd,
		"IR01":ir,
		"IR02":ir,
		"IR04":{},
		"IR21":ir,
		"IR29":ir,
	}
	var required := {
		"D06":"open_horizons", "P01":"crew_recommendation", "P08":"already_roi_base_cents_per_hour",
		"P09":"wage_fund", "P11":"active_specialists", "P16":"profession_machine_analysis",
		"G01":"spectral_decoding", "G05":"site_finding_density", "G07":"recent_scan_count",
		"G11":"opened_horizon_forecast", "G13":"issued_report_history", "G15":"deep_vein_style",
		"PD03":"impurity_yield", "PD04":"yield_bounds", "PD06":"previous_measurements",
		"PD10":"purification_energy_forecasts", "PD13":"processing_profile_comparison",
		"PD19":"production_chain_stages", "PD21":"fourth_impurity_analysis",
		"IR01":"route_forecasts", "IR02":"phase_expense_regions",
		"IR04":"legacy_scheme", "IR21":"ir_heat_windows", "IR29":"ir_phase_forecast",
	}
	for id in cases:
		var before := p.duplicate(true)
		var result: Dictionary = Views.describe(p, str(id), cases[id])
		check(result.has(required[id]), "%s did not provide %s" % [str(id), str(required[id])])
		check(p == before, "%s changed the source profile" % str(id))
	for id in ["PD06", "PD10", "PD21"]:
		var runtime_readout: Dictionary = Runtime.describe(p.duplicate(true), id)
		check(str(runtime_readout.get("mode", "")) == "view" and bool(runtime_readout.get("implemented", false)) and str(runtime_readout.get("modifier_key", "")).is_empty(), "%s is not mapped as an implemented non-modifier view" % id)
		var combined: Dictionary = Views.describe(p, id, runtime_readout)
		check(combined.get("current_state", {}).has(required[id]), "%s did not enrich its mapped runtime view" % id)
	check(Views.describe(p, "P08", cases["P08"]).already_roi_base_cents_per_hour == 1234.0, "P08 did not preserve the base ROI field")
	check(Views.describe(p, "P01", cases["P01"]).crew_recommendation.worker_id == "iron_miner", "P01 did not recommend the best positive actual hire quote")
	check(Views.describe(p, "G07", cases["G07"]).recent_scan_count == 20, "G07 did not limit the scan window to the last 20 reports")
	check(Views.describe(p, "G13", cases["G13"]).reward_history_complete == false, "G13 falsely claimed exact rewards are recorded in reports")
	check(Views.describe(p, "IR01", cases["IR01"]).route_forecast_count == 3, "IR01 did not expose the three existing routes")
	check(Views.describe(p, "IR21", cases["IR21"]).phase_mode_options.size() == 3, "IR21 did not expose the three canonical phase modes")
	var measurements: Dictionary = Views.describe(p, "PD06", cases["PD06"])
	check(measurements.previous_measurement_count == 1 and measurements.previous_measurements[0].lens_id == "pd_lens_high_grade", "PD06 did not retain the actual previous-lens measurement")
	check(measurements.measurements_from_other_lenses == 1, "PD06 did not distinguish a saved measurement from the current lens")
	var energy: Dictionary = Views.describe(p, "PD10", cases["PD10"])
	var selected_energy: Variant = null
	for forecast in energy.purification_energy_forecasts:
		if bool(forecast.get("selected", false)):
			selected_energy = int(forecast.get("energy_cost_cents", -1))
	check(selected_energy != null and int(energy.selected_purification_energy_cost_cents) == int(selected_energy), "PD10 did not report the selected lens's real pre-start energy forecast")
	check(bool(energy.purification_energy_cost_already_included), "PD10 presented the energy breakdown as an extra charge")
	var impurity: Dictionary = Views.describe(p, "PD21", cases["PD21"]).fourth_impurity_analysis
	check(impurity.impurity_id == "carbonaceous" and impurity.included_in_current_sample_library, "PD21 did not expose the actual fourth impurity in the current sample library")
	check(impurity.current_sample_impurity_count == 4 and is_equal_approx(float(impurity.configured_bonus_percent), 2.0), "PD21's fourth-impurity hint did not match its configured one-batch bonus")
	check(bool(impurity.effect_applied_to_current_sample), "PD21 did not identify its applied current-batch effect")
	check(Views.describe(p, "IR29", cases["IR29"]).phase_forecast_source == "base_configuration", "IR29 did not label its idle forecast source")
	var pd_bounds: Dictionary = Views.describe(p, "PD04", cases["PD04"])
	check(pd_bounds.yield_bounds_kind == "model_range_not_statistical_confidence_interval", "PD04 misrepresented a model range as statistical confidence")
	var styles: Dictionary = Views.deep_vein_style(p)
	check(styles.deep_vein_style.available_types.size() == 2, "G15 did not derive visual types from actual discoveries")
	check(not styles.deep_vein_style.has("coordinates"), "G15 invented spatial geological data")
	var density: Dictionary = Views.describe(p, "G05", {})
	check(density.site_finding_density.size() == 3 and density.density_basis.contains("Координаты"), "G05 omitted existing-site rows or implied spatial data")

func _test_gates(p: Dictionary) -> void:
	var hidden_profile := p.duplicate(true)
	GameMath.game(hidden_profile)["progression"]["geology"]["discoveries"].erase("old_project_record")
	GameMath.game(hidden_profile)["progression"]["story_done"] = {}
	var hidden: Dictionary = Views.describe(hidden_profile, "IR04", {})
	check(not hidden.legacy_scheme.available and hidden.legacy_scheme.snippet.is_empty(), "IR04 exposed an undiscovered story record")

