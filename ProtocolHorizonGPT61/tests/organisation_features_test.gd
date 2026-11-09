extends SceneTree

const Organisation = preload("res://gameplay/OrganisationFeatures.gd")
const Progression = preload("res://gameplay/ProgressionModel.gd")
const Meta = preload("res://gameplay/MetaModel.gd")
const Features = preload("res://gameplay/FeatureRuntime.gd")
const Economy = preload("res://gameplay/EconomyModel.gd")
const Game = preload("res://gameplay/GameMath.gd")

var failures: PackedStringArray = []

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func profile() -> Dictionary:
	var p := {"money_cents":1000000, "research_points":0, "shards":0, "inventory":{"iron_ore":1000}, "sites":{
		"site_earth_fe_17":{"unlocked":true}, "site_earth_pd_7":{"unlocked":true}, "site_earth_ir_9":{"unlocked":true}
	}}
	Progression.ensure(p)
	Meta.ensure(p)
	Economy.ensure(p)
	Features.ensure(p)
	return p

func own(p: Dictionary, id: String, level: int = 1) -> void:
	Game.game(p)["progression"]["research"][id] = level

func action(p: Dictionary, name: String, id: String, args: Dictionary = {}) -> Dictionary:
	args["id"] = id
	return Organisation.act(p, name, args)

func produce(p: Dictionary, amount: int) -> bool:
	var before := float(Game.game(p).get("stats", {}).get("produced:iron_ore", 0.0))
	var args := {"site":"fe"}
	for _iteration in range(amount * 4 + 100):
		var result: Dictionary = Economy.act(p, "tap", args)
		if _iteration == 0:
			print("PROBE ", result, " unlocked=", Game.unlocked(p, "fe"), " capacity=", Game.capacity(p), " inventory=", p.get("inventory", {}))
		if bool(result.get("ok", false)):
			Features.after_action(p, "economy", "tap", args, result)
		if float(Game.game(p).get("stats", {}).get("produced:iron_ore", 0.0)) - before >= amount:
			return true
	return false

func _run() -> void:
	var registry: Node = root.get_node("ContentRegistry")
	check(registry.is_loaded, "Canonical catalogs did not load: " + str(registry.errors))
	if registry.is_loaded:
		_test_coverage_and_presets()
		_test_cosmetic_and_template()
		_test_tasks_and_rosters()
		_test_geology_reports()
		_test_parallel_work()
	if failures.is_empty():
		print("organisation_features_test: all checks passed")
	else:
		for failure in failures:
			push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _test_coverage_and_presets() -> void:
	var p := profile()
	var report := Organisation.coverage()
	check(int(report.get("total", 0)) == 12 and report.get("gap_ids", []).is_empty(), "All twelve assigned research IDs must have real implementations")
	var runtime_coverage: Dictionary = Features.coverage()
	for id in Organisation.ORGANISATION_IDS:
		check(bool(runtime_coverage.get("by_id", {}).get(id, {}).get("supported", false)), "Feature runtime coverage must register " + id)
	var money := int(p["money_cents"])
	var denied := action(p, "org_save_shift_preset", "A11", {"slot":0})
	check(not bool(denied.get("ok", false)) and int(p["money_cents"]) == money, "Unowned presets must not change state or spend")
	check(Organisation.operations(p, "A11").is_empty(), "Unowned organisation nodes must expose no controls")
	own(p, "A11")
	own(p, "A10")
	Features.act(p, "set_factory_priority", {"id":"A10", "first_line":3})
	var inventory_before: Dictionary = p["inventory"].duplicate(true)
	var upgrades_before: Dictionary = Game.site(p, "fe").get("upgrades", {}).duplicate(true)
	check(bool(action(p, "org_save_shift_preset", "A11", {"slot":0}).get("ok", false)), "A11 must save a real settings snapshot")
	Features.act(p, "set_factory_priority", {"id":"A10", "first_line":1})
	check(bool(action(p, "org_apply_shift_preset", "A11", {"slot":0}).get("ok", false)), "A11 must apply a saved settings snapshot")
	check(int(Game.game(p)["features"]["A10"]["first_line"]) == 3, "Applying the preset must restore the actual factory priority")
	check(p["inventory"] == inventory_before and Game.site(p, "fe")["upgrades"] == upgrades_before, "Settings-only presets cannot print inventory or equipment levels")
	check(bool(Organisation.validate(p)), "Organisation state should remain JSON-safe")

func _test_cosmetic_and_template() -> void:
	var p := profile()
	own(p, "A16")
	Organisation.refresh(p)
	check(not Game.game(p)["feature_families"]["organisation"]["factory_cosmetic"]["owned"].has("steel"), "Factory cosmetic must require a real equipment milestone")
	Game.site(p, "fe")["machines"]["iron_drill"] = 1
	Organisation.refresh(p)
	check(bool(action(p, "org_set_factory_cosmetic", "A16", {"cosmetic":"steel"}).get("ok", false)), "A16 cosmetic should be selectable after real equipment work")
	check(Game.game(p)["feature_families"]["organisation"]["factory_cosmetic"]["active"] == "steel", "Active cosmetic key was not persisted")
	own(p, "A19")
	own(p, "A20")
	var route := Features.act(p, "set_line_route", {"id":"A19", "line":0, "recipe_id":"R_INGOT", "budget_cents":100000})
	check(bool(route.get("ok", false)), "Fixture needs a real affordable A19 route: " + str(route.get("message", "")))
	check(bool(action(p, "org_save_automation_template", "A20").get("ok", false)), "A20 should save its persistent automation template")
	var saved: Dictionary = Game.game(p)["feature_families"]["organisation"]["automation_template"]
	check(int(saved.get("routes", {}).get("0", {}).get("budget_cents", 0)) > 0, "Template must retain a real per-route spending limit")
	var cash := int(p["money_cents"])
	check(bool(action(p, "org_apply_automation_template", "A20", {"site":"fe"}).get("ok", false)), "A20 template should apply only after explicit command")
	check(int(p["money_cents"]) == cash, "Applying settings must not itself auto-pay for a queued recipe")

func _test_tasks_and_rosters() -> void:
	var p := profile()
	own(p, "P12")
	check(bool(action(p, "org_start_shift_task", "P12", {"choice":"speed", "site":"fe"}).get("ok", false)), "P12 shift task did not start")
	var state: Dictionary = Game.game(p)["feature_families"]["organisation"]
	p["inventory"]["iron_ore"] = 0
	check(produce(p, 100), "P12 fixture did not generate enough real production")
	check(state["active_shift_task"].is_empty() and not state["shift_effects"].is_empty(), "A shift reward must require real production after task start")
	check(Game.bonus(p, "speed", "fe") > 0.0, "Completed shift task must apply a real bounded speed bonus")
	var effects: int = state["shift_effects"].size()
	Organisation.after_action(p, "economy", "tap", {}, Game.ok("repeat"))
	check(state["shift_effects"].size() == effects, "A completed task cannot award its effect twice")
	Organisation.advance(p, 300.0)
	check(Game.bonus(p, "speed", "fe") == 0.0, "Temporary shift bonus must expire")

	own(p, "P15")
	Meta.ensure(p)
	var owned_before: int = Game.game(p)["meta"]["specialists"]["owned"].size()
	check(bool(action(p, "org_save_roster_preset", "P15", {"slot":0}).get("ok", false)), "P15 should save the actual roster")
	check(bool(action(p, "org_apply_roster_preset", "P15", {"slot":0}).get("ok", false)), "P15 should apply a roster through MetaModel")
	check(Game.game(p)["meta"]["specialists"]["owned"].size() == owned_before, "Roster presets must not hire specialists")

	var specialist_id := "SP01"
	var assigned := Meta.act(p, "specialist_assign", {"specialist_id":specialist_id, "site":"fe", "slot":0})
	check(bool(assigned.get("ok", false)), "Fixture starter specialist could not be assigned")
	own(p, "P17", 1)
	check(bool(action(p, "org_start_training_task", "P17", {"specialist_id":specialist_id}).get("ok", false)), "P17 should start only for an assigned canonical specialist")
	var level_before := int(Game.game(p)["meta"]["specialists"]["owned"][specialist_id]["level"])
	check(produce(p, 100), "P17 fixture did not generate enough real production")
	check(int(Game.game(p)["meta"]["specialists"]["owned"][specialist_id]["level"]) == level_before + 1, "Training must level the real specialist, not player XP")
	check(not action(p, "org_start_training_task", "P17", {"specialist_id":specialist_id}).get("ok", false), "P17 rank must cap repeated training awards per specialist")

	own(p, "P19")
	check(bool(action(p, "org_reassign_specialist", "P19", {"specialist_id":specialist_id, "site":"fe", "slot":1}).get("ok", false)), "P19 should reassign through MetaModel rules")
	check(Game.game(p)["meta"]["specialists"]["assignments"]["fe"].get("1", "") == specialist_id, "P19 did not update the canonical assignment")

	own(p, "P20")
	var rp_before := int(p["research_points"])
	check(not action(p, "org_start_group_task", "P20", {"site":"fe"}).get("ok", false), "Group task cannot start with only one assigned specialist")
	var second_id := "SP02"
	Game.game(p)["meta"]["specialists"]["owned"][second_id] = {"level":1, "stars":0}
	var second_assignment := Meta.act(p, "specialist_assign", {"specialist_id":second_id, "site":"fe", "slot":2})
	check(bool(second_assignment.get("ok", false)), "Fixture second canonical specialist could not be assigned: " + str(second_assignment.get("message", "")))
	check(bool(action(p, "org_start_group_task", "P20", {"site":"fe"}).get("ok", false)), "P20 should start with the real two-specialist team")
	check(produce(p, 250), "P20 fixture did not generate enough real team production")
	check(int(p["research_points"]) == rp_before + 2, "Group reward must follow fresh production and be one-time")
	check(not action(p, "org_start_group_task", "P20", {"site":"fe"}).get("ok", false), "P20 group reward/task must not be replayable")

func _test_geology_reports() -> void:
	var p := profile()
	own(p, "G08", 5)
	own(p, "G10", 3)
	own(p, "G16")
	check(bool(Progression.act(p, "geology_start", {"id":"fe_survey"}).get("ok", false)), "Fixture expedition did not start")
	Progression.advance(p, 30.0)
	var report: Dictionary = Game.game(p)["progression"]["geology"]["reports"][0]
	var report_id := str(report["id"])
	var preview := action(p, "org_preview_geology_event", "G08", {"report_id":report_id})
	check(bool(preview.get("ok", false)), "G08 level 5 should preview the real report deterministically")
	check(not action(p, "org_preview_geology_event", "G08", {"report_id":report_id}).get("ok", false), "G08 cannot reroll a report preview")
	var choice := action(p, "org_choose_geology_event", "G16", {"report_id":report_id, "choice":"chart"})
	check(bool(choice.get("ok", false)), "G16 should expose an optional choice from the real report")
	check(not Game.game(p)["progression"]["story_done"].get("A20", false), "Optional map events must not change main story reachability")
	var points_before := int(p["research_points"])
	var artifact := action(p, "org_study_artifact", "G10", {"report_id":report_id})
	check(bool(artifact.get("ok", false)), "G10 should study a known artifact tag")
	check(int(p["research_points"]) > points_before and Game.bonus(p, "geology:scan_progress", "fe") > 0.0, "Artifact study must provide its one-time configured benefit")
	var points_after := int(p["research_points"])
	check(not action(p, "org_study_artifact", "G10", {"report_id":report_id}).get("ok", false) and int(p["research_points"]) == points_after, "Artifact rewards must be idempotent per real report")

func _test_parallel_work() -> void:
	var parallel := profile()
	var serial := profile()
	own(parallel, "G12")
	own(serial, "G12")
	var cash_parallel := int(parallel["money_cents"])
	var cash_serial := int(serial["money_cents"])
	check(bool(Progression.act(parallel, "geology_start", {"id":"pd_lens"}).get("ok", false)), "Primary parallel fixture expedition failed")
	check(bool(action(parallel, "org_start_parallel_expedition", "G12", {"expedition_id":"fe_survey"}).get("ok", false)), "Second parallel expedition did not start")
	check(bool(Progression.act(serial, "geology_start", {"id":"pd_lens"}).get("ok", false)), "First serial fixture expedition failed")
	Progression.advance(serial, 60.0)
	check(bool(Progression.act(serial, "geology_start", {"id":"fe_survey"}).get("ok", false)), "Second serial fixture expedition failed")
	Progression.advance(serial, 30.0)
	check(int(parallel["money_cents"]) == cash_parallel - 2700 and int(serial["money_cents"]) == cash_serial - 2700, "Both modes must pay each existing expedition's exact real cost")
	Progression.advance(parallel, 60.0)
	var geo_parallel: Dictionary = Game.game(parallel)["progression"]["geology"]
	check(not geo_parallel["active"].is_empty() and Game.game(parallel)["feature_families"]["organisation"]["secondary_expedition"].is_empty(), "At 60s the shorter task should finish and release its shared capacity")
	check(geo_parallel["reports"].size() == 1, "At 60s only the shorter parallel expedition should have completed")
	Progression.advance(parallel, 30.0)
	var reports_parallel: Array = Game.game(parallel)["progression"]["geology"]["reports"]
	var reports_serial: Array = Game.game(serial)["progression"]["geology"]["reports"]
	check(reports_parallel.size() == 2 and reports_serial.size() == 2, "Parallel total work must match serial total work")
	check(int(parallel["research_points"]) == int(serial["research_points"]) and int(parallel["shards"]) == int(serial["shards"]), "Parallel capacity must not multiply expedition rewards")
	check(bool(Game.game(parallel)["progression"]["geology"]["guaranteed_geobinding"]) and bool(Game.game(serial)["progression"]["geology"]["guaranteed_geobinding"]), "Parallel completion must preserve sequence-one geobinding guarantee")
	check(str(reports_parallel[0]["id"]) != str(reports_parallel[1]["id"]) and str(reports_parallel[0]["claim_key"]) != str(reports_parallel[1]["claim_key"]), "Parallel report IDs and sequence claims must be unique")
