extends SceneTree

const SiteModel = preload("res://gameplay/SiteModel.gd")

var failures: Array[String] = []


func _initialize() -> void:
	_test_locked_sites_reject_actions()
	_test_validation_and_expansion_cancellation()
	_test_pd_costs_and_analysis()
	_test_pd_advance_partitioning()
	_test_pd_single_cent_wage_partitioning()
	_test_site_payroll_uses_payroll_reserve()
	_test_ir_seed_resume_and_output()
	_test_ir_waits_without_debt_or_offline_progress()
	_test_ir_cooling_affects_output()
	if failures.is_empty():
		print("PASS: Pd/Ir extraction state, costs, determinism, partitioned time, phases, and thermal yield")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)


func _test_locked_sites_reject_actions() -> void:
	var profile := _profile()
	var result: Dictionary = SiteModel.act(profile, "take_sample", {"site": "pd"})
	_check(not bool(result.get("ok", false)), "Locked Pd accepted an extraction action")
	_check(not profile.has("game"), "Rejected locked action mutated the profile")
	var view: Dictionary = SiteModel.view(profile, "ir")
	_check(not bool(view.get("unlocked", true)) and String(view.get("status", "")) == "locked", "Locked Ir view did not remain unavailable")


func _test_validation_and_expansion_cancellation() -> void:
	var profile := _profile()
	profile["sites"]["site_earth_pd_7"]["unlocked"] = true
	profile["money_cents"] = 10000
	profile["inventory"]["iron_ore"] = 12
	profile["inventory"]["pd_concentrate"] = 3
	_check(SiteModel.validate(profile), "Valid profile failed SiteModel validation")
	_check(bool(SiteModel.act(profile, "pd_select_lens", {"site": "site_earth_pd_7", "lens_id": "pd_lens_balanced"}).get("ok", false)), "Could not select Pd lens for expansion test")
	_check(bool(SiteModel.act(profile, "take_sample", {"site": "pd"}).get("ok", false)), "Could not start Pd cycle for expansion test")
	var money_after_start := int(profile["money_cents"])
	profile["game"]["sites"]["pd"]["expansions"] = 1
	SiteModel.ensure(profile)
	var pd: Dictionary = SiteModel.view(profile, "pd")
	_check(String(pd.get("status", "")) == "cancelled" and pd.get("sample", {}).is_empty(), "Pd expansion did not cancel its active cycle")
	_check(int(profile["money_cents"]) == money_after_start, "Pd expansion refunded already committed costs")
	_check(int(profile["inventory"]["iron_ore"]) == 12 and int(profile["inventory"]["pd_concentrate"]) == 3, "Pd expansion changed global inventory")
	var ir_profile := _profile()
	ir_profile["sites"]["site_earth_ir_9"]["unlocked"] = true
	ir_profile["money_cents"] = 10000
	ir_profile["inventory"]["ir_core"] = 2
	_check(bool(SiteModel.act(ir_profile, "start_campaign", {"site": "ir", "strategy_id": "reliable"}).get("ok", false)), "Could not start Ir campaign for expansion test")
	var original_seed := int(SiteModel.view(ir_profile, "ir")["campaign"].get("seed", 0))
	var ir_money_after_start := int(ir_profile["money_cents"])
	ir_profile["game"]["sites"]["ir"]["expansions"] = 1
	SiteModel.ensure(ir_profile)
	var ir: Dictionary = SiteModel.view(ir_profile, "ir")
	_check(String(ir.get("status", "")) == "cancelled" and String(ir["campaign"].get("status", "")) == "cancelled", "Ir expansion did not cancel its active campaign")
	_check(int(ir_profile["money_cents"]) == ir_money_after_start and int(ir_profile["inventory"]["ir_core"]) == 2, "Ir expansion changed wallet or existing inventory")
	_check(bool(SiteModel.act(ir_profile, "start_campaign", {"site": "ir", "strategy_id": "reliable"}).get("ok", false)), "Ir could not restart after expansion")
	_check(int(SiteModel.view(ir_profile, "ir")["campaign"].get("seed", 0)) != original_seed, "Ir expansion reused a prior campaign seed")
	var tampered := _profile()
	tampered["game"] = {"extraction": {"pd": "bad-state"}}
	_check(not SiteModel.validate(tampered), "Tampered extraction state passed validation")


func _test_pd_costs_and_analysis() -> void:
	var profile := _profile()
	profile["sites"]["site_earth_pd_7"]["unlocked"] = true
	profile["money_cents"] = 100000
	var lens: Dictionary = SiteModel.lens_definitions()[1]
	var options: Array = SiteModel.view(profile, "pd").get("lens_options", [])
	_check(options.size() == 3, "Pd view did not expose all lens forecasts")
	_check(float(options[1].get("expected_duration_s", 0.0)) > 0.0 and int(options[1].get("cost_cents", 0)) > 0, "Pd lens forecast omitted time or costs")
	var before := int(profile["money_cents"])
	_check(bool(SiteModel.act(profile, "select_lens", {"site": "pd", "lens_id": lens["id"]}).get("ok", false)), "Pd lens selection failed")
	_check(int(profile["money_cents"]) == before, "Selecting a Pd lens charged money")
	_check(bool(SiteModel.act(profile, "take_sample", {"site": "pd"}).get("ok", false)), "Pd sample did not start")
	var after_sample := int(profile["money_cents"])
	_check(after_sample == before - int(lens["sample_cost_cents"]), "Pd sample fee was not charged exactly once")
	_check(not bool(SiteModel.act(profile, "take_sample", {"site": "pd"}).get("ok", false)), "Pd allowed a second concurrent sample")
	_check(int(profile["money_cents"]) == after_sample, "Rejected second sample charged money")
	profile["game"]["sites"] = {"pd": {"workers": {"pd_geologist": 1}}}
	profile["money_cents"] = 0
	SiteModel.advance(profile, 10.0)
	var unfunded: Dictionary = SiteModel.view(profile, "pd")
	_check(String(unfunded.get("status", "")) == "waiting_funds", "Pd kept extracting without funds for worker wages")
	_check(float(unfunded.get("progress_seconds", 0.0)) == 0.0, "Pd progressed while worker wages could not be paid")
	profile["money_cents"] = after_sample
	_check(bool(SiteModel.act(profile, "resume", {"site": "pd"}).get("ok", false)), "Pd did not resume after wages could be funded")
	SiteModel.advance(profile, 60.0)
	_check(String(SiteModel.view(profile, "pd").get("status", "")) == "ready", "Pd sample did not become ready")
	_check(bool(SiteModel.act(profile, "analyze_sample", {"site": "pd", "score": 1.0}).get("ok", false)), "Optional Pd analysis did not start")
	var analysis_view: Dictionary = SiteModel.view(profile, "pd")
	_check(float(analysis_view["sample"].get("analysis_duration_s", 0.0)) >= 20.0 and float(analysis_view["sample"].get("analysis_duration_s", 0.0)) <= 40.0, "Pd analysis duration is outside its 20–40 second range")
	SiteModel.advance(profile, 40.0)
	_check(bool(SiteModel.act(profile, "start_cycle", {"site": "pd"}).get("ok", false)), "Pd concentration cycle did not start")
	var after_cycle_start := int(profile["money_cents"])
	_check(not bool(SiteModel.act(profile, "start_cycle", {"site": "pd"}).get("ok", false)), "Pd charged for a duplicate start")
	_check(int(profile["money_cents"]) == after_cycle_start, "Duplicate Pd cycle start charged twice")


func _test_pd_advance_partitioning() -> void:
	var whole := _profile()
	whole["profile_id"] = "pd-partition-test"
	whole["sites"]["site_earth_pd_7"]["unlocked"] = true
	whole["money_cents"] = 100000
	whole["game"] = {"sites": {"pd": {"peak": 23, "upgrades": {"pd_lens_analysis": 2}, "machines": {"pd_filter_press": 3}, "workers": {"pd_sampler": 4}}}}
	var split: Dictionary = whole.duplicate(true)
	var start_args := {"site": "pd", "enabled": true}
	_check(bool(SiteModel.act(whole, "set_automatic", start_args).get("ok", false)), "Pd balanced automation did not start")
	_check(bool(SiteModel.act(split, "set_automatic", start_args).get("ok", false)), "Pd balanced automation clone did not start")
	SiteModel.advance(whole, 120.0)
	for _index in range(12):
		SiteModel.advance(split, 10.0)
	var whole_pd: Dictionary = whole["game"]["extraction"]["pd"]
	var split_pd: Dictionary = split["game"]["extraction"]["pd"]
	_check(whole["inventory"] == split["inventory"], "Pd output depends on advance partitioning")
	_check(int(whole["money_cents"]) == int(split["money_cents"]), "Pd costs depend on advance partitioning")
	_check(int(whole_pd["cycles_completed"]) == int(split_pd["cycles_completed"]), "Pd cycle count depends on advance partitioning")
	_check(String(whole_pd["status"]) == String(split_pd["status"]), "Pd phase depends on advance partitioning")
	_check(absf(float(whole_pd.get("elapsed_seconds", 0.0)) - float(split_pd.get("elapsed_seconds", 0.0))) < 0.00001, "Pd progress depends on advance partitioning")
	_check(absf(float(whole_pd.get("wage_fraction_cents", 0.0)) - float(split_pd.get("wage_fraction_cents", 0.0))) < 0.00001, "Pd wages depend on advance partitioning")
	_check(float(whole["game"]["stats"].get("pd_wages_paid_cents", 0.0)) > 0.0 and int(whole["money_cents"]) >= 0, "Pd workers were not charged safely")
	SiteModel.advance(whole, 100.0)
	for _index in range(10):
		SiteModel.advance(split, 10.0)
	_check(int(whole["inventory"].get("pd_concentrate", 0)) > 0, "Balanced Pd automation did not produce concentrate")
	_check(is_equal_approx(float(whole["game"]["sites"]["pd"].get("mined", 0.0)), float(whole["inventory"].get("pd_concentrate", 0))), "Pd resource production did not update mined quantity")
	_check(int(whole["game"]["sites"]["pd"].get("peak", 0)) == 23, "Pd resource production overwrote historical upgrade peak")


func _test_pd_single_cent_wage_partitioning() -> void:
	var whole := _profile()
	whole["sites"]["site_earth_pd_7"]["unlocked"] = true
	whole["money_cents"] = 10000
	_check(bool(SiteModel.act(whole, "take_sample", {"site": "pd"}).get("ok", false)), "Pd single-cent wage sample did not start")
	whole["money_cents"] = 1
	whole["game"]["sites"]["pd"]["workers"] = {"pd_geologist": 1}
	var split: Dictionary = whole.duplicate(true)
	SiteModel.advance(whole, 10.0)
	for _index in range(20):
		SiteModel.advance(split, 0.5)
	var whole_pd: Dictionary = whole["game"]["extraction"]["pd"]
	var split_pd: Dictionary = split["game"]["extraction"]["pd"]
	_check(String(whole_pd.get("status", "")) == "waiting_funds" and String(split_pd.get("status", "")) == "waiting_funds", "Pd did not stop after the final wage cent")
	_check(is_equal_approx(float(whole_pd.get("elapsed_seconds", 0.0)), float(split_pd.get("elapsed_seconds", 0.0))), "Partial one-cent wage payment changed progress by advance partition")
	_check(is_equal_approx(float(whole_pd.get("wage_fraction_cents", 0.0)), float(split_pd.get("wage_fraction_cents", 0.0))), "Partial one-cent wage remainder changed by advance partition")
	_check(int(whole["money_cents"]) == 0 and int(split["money_cents"]) == 0, "Pd single-cent wage test created or retained spendable credits")
	_check(int(whole["game"]["stats"].get("pd_wages_paid_cents", 0)) == 1 and int(split["game"]["stats"].get("pd_wages_paid_cents", 0)) == 1, "Pd did not charge exactly the final available wage cent")


func _test_site_payroll_uses_payroll_reserve() -> void:
	var profile := _profile()
	profile["sites"]["site_earth_pd_7"]["unlocked"] = true
	profile["money_cents"] = 10000
	_check(bool(SiteModel.act(profile, "take_sample", {"site":"pd"}).get("ok", false)), "Pd payroll-reserve sample did not start")
	profile["money_cents"] = 100
	profile["game"]["research_runtime"] = {"cash_reserves":{"P09":50, "P14":0, "PD24":30}}
	profile["game"]["sites"] = {"pd":{"workers":{"pd_geologist":1}}}
	SiteModel.advance(profile, 10.0)
	var reserves: Dictionary = profile["game"]["research_runtime"]["cash_reserves"]
	_check(int(profile["money_cents"]) < 100 and int(reserves["P09"]) < 50, "Site wages did not use the protected payroll reserve")
	_check(int(reserves["PD24"]) == 30 and GameMath.available_money(profile) == 20, "Pd wages spent the chemical reserve or changed general spendable cash")


func _test_ir_seed_resume_and_output() -> void:
	var profile := _profile()
	profile["profile_id"] = "ir-resume-test"
	profile["sites"]["site_earth_ir_9"]["unlocked"] = true
	profile["money_cents"] = 100000
	profile["game"] = {"sites": {"ir": {"peak": 17}}}
	_check(bool(SiteModel.act(profile, "start_campaign", {"site": "ir", "strategy_id": "economic"}).get("ok", false)), "Ir campaign did not start")
	var before_save: Dictionary = SiteModel.view(profile, "ir")
	_check(float(before_save["projection"].get("duration_seconds", 0.0)) > 0.0 and float(before_save["projection"].get("expected_yield", 0.0)) > 0.0, "Ir strategy forecast omitted duration or yield")
	_check(before_save.get("strategy_options", []).size() == 3, "Ir view did not expose projections for all strategies")
	var serialized := JSON.stringify(profile)
	var loaded: Variant = JSON.parse_string(serialized)
	_check(loaded is Dictionary, "Ir save roundtrip did not parse")
	if not loaded is Dictionary:
		return
	SiteModel.advance(profile, 120.0)
	SiteModel.advance(loaded, 120.0)
	var after_original: Dictionary = SiteModel.view(profile, "ir")
	var after_loaded: Dictionary = SiteModel.view(loaded, "ir")
	_check(int(before_save.get("seed", 0)) == int(after_original.get("seed", 0)), "Ir campaign seed changed during advance")
	_check(int(after_original.get("seed", 0)) == int(after_loaded.get("seed", 0)), "Ir save/load rerolled the campaign seed")
	_check(String(after_original["status"]) == String(after_loaded["status"]), "Ir status changed after identical save/load advance")
	_check(int(after_original["phase_index"]) == int(after_loaded["phase_index"]), "Ir phase changed after identical save/load advance")
	_check(absf(float(after_original["campaign"].get("phase_elapsed_s", 0.0)) - float(after_loaded["campaign"].get("phase_elapsed_s", 0.0))) < 0.00001, "Ir progress changed after identical save/load advance")
	_check(int(after_original["campaign"].get("committed_cost_cents", 0)) == int(after_loaded["campaign"].get("committed_cost_cents", 0)), "Ir costs changed after identical save/load advance")
	SiteModel.advance(profile, 1000.0)
	SiteModel.advance(loaded, 1000.0)
	var completed: Dictionary = SiteModel.view(profile, "ir")
	var loaded_completed: Dictionary = SiteModel.view(loaded, "ir")
	_check(int(profile["inventory"].get("ir_core", 0)) > 0, "Ir campaign did not produce its canonical raw output")
	_check(int(profile["game"]["sites"]["ir"].get("peak", 0)) == 17, "Ir resource production overwrote historical upgrade peak")
	_check(int(profile["inventory"].get("ir_core", 0)) == int(loaded["inventory"].get("ir_core", 0)), "Ir result changed after save/load")
	_check(int(profile["money_cents"]) == int(loaded["money_cents"]), "Ir costs changed after save/load")
	_check(int(completed["campaign"].get("output_units", 0)) == int(loaded_completed["campaign"].get("output_units", 0)), "Ir output rerolled after save/load")
	_check(not profile["inventory"].has("ir_refined") and not profile["inventory"].has("thermal_contact"), "SiteModel created refined Ir or a thermal-contact recipe output")
	_check(int(completed["campaign"].get("seed", 0)) == int(before_save.get("seed", 0)), "Completed Ir result lost its committed seed")
	_check(int(completed["campaign"].get("committed_cost_cents", 0)) == int(completed["campaign"].get("projected_cost_cents", -1)), "Ir phase costs were not charged exactly once")


func _test_ir_cooling_affects_output() -> void:
	var hot := _profile()
	hot["profile_id"] = "ir-thermal-test"
	hot["sites"]["site_earth_ir_9"]["unlocked"] = true
	hot["money_cents"] = 100000
	var cooled: Dictionary = hot.duplicate(true)
	_check(bool(SiteModel.act(hot, "start_campaign", {"site": "ir", "strategy_id": "forced"}).get("ok", false)), "Hot forced campaign did not start")
	_check(bool(SiteModel.act(cooled, "start_campaign", {"site": "ir", "strategy_id": "forced"}).get("ok", false)), "Cooled forced campaign did not start")
	var campaign: Dictionary = SiteModel.view(hot, "ir")["campaign"]
	var durations: Array = campaign["phase_durations_s"]
	var to_extraction := float(durations[0]) + float(durations[1]) + float(durations[2])
	SiteModel.advance(hot, to_extraction)
	SiteModel.advance(cooled, to_extraction)
	_check(String(SiteModel.view(hot, "ir").get("phase", "")) == "Извлечение", "Ir phase sequence did not reach extraction")
	_check(bool(SiteModel.act(cooled, "cool", {"site": "ir"}).get("ok", false)), "Ir cooling action did not operate")
	SiteModel.advance(hot, 1000.0)
	SiteModel.advance(cooled, 1000.0)
	var hot_view: Dictionary = SiteModel.view(hot, "ir")
	var cooled_view: Dictionary = SiteModel.view(cooled, "ir")
	_check(float(cooled_view["campaign"].get("thermal_penalty", 1.0)) < float(hot_view["campaign"].get("thermal_penalty", 0.0)), "Cooling did not reduce thermal yield penalty")
	_check(int(cooled["inventory"].get("ir_core", 0)) >= int(hot["inventory"].get("ir_core", 0)), "Cooling reduced Ir core output")
	_check(not cooled["inventory"].has("thermal_contact"), "Cooling created a non-canonical thermal-contact output")


func _test_ir_waits_without_debt_or_offline_progress() -> void:
	var profile := _profile()
	profile["sites"]["site_earth_ir_9"]["unlocked"] = true
	profile["money_cents"] = 140
	_check(bool(SiteModel.act(profile, "start_campaign", {"site": "ir", "strategy_id": "economic"}).get("ok", false)), "Ir could not start with exactly the route fee")
	SiteModel.advance(profile, 1000.0)
	var waiting: Dictionary = SiteModel.view(profile, "ir")
	_check(String(waiting.get("status", "")) == "waiting_funds", "Ir did not stop before an unaffordable phase")
	_check(int(profile["money_cents"]) == 0, "Ir phase payment went below zero")
	_check(int(waiting["campaign"].get("phase_index", -1)) == 1 and float(waiting["campaign"].get("phase_elapsed_s", 0.0)) == 0.0, "Ir charged or progressed the unpaid phase")
	profile["money_cents"] = 265
	_check(bool(SiteModel.act(profile, "resume", {"site": "ir"}).get("ok", false)), "Ir did not resume after exact phase funds were added")
	var resumed: Dictionary = SiteModel.view(profile, "ir")
	_check(float(resumed["campaign"].get("phase_elapsed_s", 0.0)) == 0.0, "Ir accumulated paused offline time")
	_check(int(resumed["campaign"].get("committed_cost_cents", 0)) == 405, "Ir charged the resumed phase more than once")
	_check(int(profile["money_cents"]) == 0, "Ir resume created debt")
	var workers := _profile()
	workers["sites"]["site_earth_ir_9"]["unlocked"] = true
	workers["money_cents"] = 225
	workers["game"] = {"sites": {"ir": {"workers": {"ir_route_engineer": 1}}}}
	_check(bool(SiteModel.act(workers, "start_campaign", {"site": "ir", "strategy_id": "reliable"}).get("ok", false)), "Ir route fee with workers was not accepted")
	_check(int(workers["money_cents"]) == 0, "Ir route charge was incorrect in wage-stop test")
	SiteModel.advance(workers, 10.0)
	var stopped: Dictionary = SiteModel.view(workers, "ir")
	_check(String(stopped.get("status", "")) == "waiting_funds", "Ir progressed without money for worker wages")
	_check(float(stopped["campaign"].get("phase_elapsed_s", 0.0)) == 0.0, "Ir accrued unpaid work with zero credits")


func _profile() -> Dictionary:
	return {
		"profile_id": "sites-test-profile",
		"money_cents": 0,
		"inventory": {"iron_ore": 0},
		"sites": {
			"site_earth_fe_17": {"unlocked": true},
			"site_earth_pd_7": {"unlocked": false},
			"site_earth_ir_9": {"unlocked": false},
		},
	}


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

