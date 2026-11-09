extends SceneTree

const Views = preload("res://gameplay/ResearchViews.gd")
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
				"pd":{"status":"ready", "lens_id":"pd_lens_balanced", "elapsed_seconds":0.0, "sample":{"lens_id":"pd_lens_balanced", "quality":0.8, "base_yield":8, "yield_units":11, "analysis_completed":true, "analysis_bonus":0.04, "analysis_skill_bonus":0.0, "impurity_analysis_bonus":0.02, "identified_impurity":"carbonaceous", "seed":17}, "pending_output":0},
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
		"PD13":pd,
		"PD19":pd,
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
		"PD03":"impurity_yield", "PD04":"yield_bounds", "PD13":"processing_profile_comparison",
		"PD19":"production_chain_stages", "IR01":"route_forecasts", "IR02":"phase_expense_regions",
		"IR04":"legacy_scheme", "IR21":"ir_heat_windows", "IR29":"ir_phase_forecast",
	}
	for id in cases:
		var before := p.duplicate(true)
		var result: Dictionary = Views.describe(p, str(id), cases[id])
		check(result.has(required[id]), "%s did not provide %s" % [str(id), str(required[id])])
		check(p == before, "%s changed the source profile" % str(id))
	check(Views.describe(p, "P08", cases["P08"]).already_roi_base_cents_per_hour == 1234.0, "P08 did not preserve the base ROI field")
	check(Views.describe(p, "P01", cases["P01"]).crew_recommendation.worker_id == "iron_miner", "P01 did not recommend the best positive actual hire quote")
	check(Views.describe(p, "G07", cases["G07"]).recent_scan_count == 20, "G07 did not limit the scan window to the last 20 reports")
	check(Views.describe(p, "G13", cases["G13"]).reward_history_complete == false, "G13 falsely claimed exact rewards are recorded in reports")
	check(Views.describe(p, "IR01", cases["IR01"]).route_forecast_count == 3, "IR01 did not expose the three existing routes")
	check(Views.describe(p, "IR21", cases["IR21"]).phase_mode_options.size() == 3, "IR21 did not expose the three canonical phase modes")
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

