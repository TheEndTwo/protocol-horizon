extends SceneTree

const State = preload("res://autoload/GameState.gd")
const Progression = preload("res://gameplay/ProgressionModel.gd")
const Research = preload("res://gameplay/ResearchRuntime.gd")

var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func _run() -> void:
	var registry: Node = root.get_node("ContentRegistry")
	check(registry.is_loaded, "Canonical catalogs failed to load: " + str(registry.errors))
	_test_fe_geology_consumers()
	_test_deep_mark_scope()
	_test_safe_project_duration_scope()
	if failures.is_empty():
		print("late_geology_test: scoped geology research consumers passed")
	else:
		for failure in failures:
			push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _profile() -> Dictionary:
	var p := State.make_new_profile()
	p["money_cents"] = 1_000_000
	p["inventory"]["iron_ore"] = 1_000
	p["sites"][GameMath.SITE_IDS["pd"]]["unlocked"] = true
	p["sites"][GameMath.SITE_IDS["ir"]]["unlocked"] = true
	Progression.ensure(p)
	GameMath.game(p)["stats"]["active_geology_units"] = 10.0
	GameMath.game(p)["stats"]["active_geology_quality"] = 8.0
	Research.refresh(p)
	return p

func _own(p: Dictionary, id: String, rank: int = 1) -> void:
	GameMath.game(p)["progression"]["research"][id] = rank
	Research.refresh(p)

func _complete_report(p: Dictionary, id: String) -> Dictionary:
	var started := Progression.act(p, "geology_start", {"id":id})
	check(bool(started.get("ok", false)), "Could not start " + id + ": " + str(started.get("message", "")))
	if not bool(started.get("ok", false)):
		return {}
	var active: Dictionary = GameMath.game(p)["progression"]["geology"]["active"]
	Progression.advance(p, float(active.get("remaining_seconds", 0.0)))
	var reports: Array = GameMath.game(p)["progression"]["geology"]["reports"]
	return Dictionary(reports.back()).duplicate(true) if not reports.is_empty() else {}

func _test_fe_geology_consumers() -> void:
	var base := _profile()
	var researched := _profile()
	_own(researched, "G02")
	_own(researched, "G04")
	_own(researched, "G09")
	_own(researched, "D17")
	var base_preview: Dictionary = Progression.geology_preview(base, "fe_survey")
	var researched_preview: Dictionary = Progression.geology_preview(researched, "fe_survey")
	check(base_preview.get("possible_types", []) == PackedStringArray(["геологическая сигнатура"]), "Unresearched G02 should show only the broad pre-scan type")
	check(researched_preview.get("possible_types", []).size() > 1, "G02 did not reveal more precise possible types before the scan")
	check(base_preview.get("visible_tags", []).is_empty() and researched_preview.get("visible_tags", []).size() > 0, "Exact deterministic tags should only be exposed by G02's pre-scan consumer")
	check(not base_preview.has("fixed_tags"), "Pre-scan output leaked hidden fixed tags without G02")
	check(float(researched_preview.get("signature_precision_bonus", 0.0)) > float(base_preview.get("signature_precision_bonus", 0.0)), "G02 signature precision did not change its actual preview")
	check(float(researched_preview.get("usable_sample_share", 0.0)) > float(base_preview.get("usable_sample_share", 0.0)), "G04 did not increase the measured usable-sample share")
	check(float(researched_preview.get("reward_quality_bonus", 0.0)) > float(base_preview.get("reward_quality_bonus", 0.0)), "G09 did not change expedition reward quality")
	check(float(researched_preview.get("geology_data_quality", 0.0)) > float(base_preview.get("geology_data_quality", 0.0)), "D17 did not improve real active-mining geology data quality")
	var inventory_before: Dictionary = researched["inventory"].duplicate(true)
	var base_report := _complete_report(base, "fe_survey")
	var researched_report := _complete_report(researched, "fe_survey")
	check(base_report.get("tags", []) == researched_report.get("tags", []), "Research changed fixed story/geology tags or added a reroll")
	check(base_report.get("identified_types", []) == researched_report.get("identified_types", []), "G02 changed the deterministic report result rather than its pre-scan display")
	check(is_equal_approx(float(base_report.get("geology_data_quality", 0.0)), 0.8), "Report did not consume the actual active_geology_quality / active_geology_units data")
	check(float(researched_report.get("geology_data_quality", 0.0)) > float(base_report.get("geology_data_quality", 0.0)), "D17 effect was not stored in the real geology report")
	check(float(researched_report.get("usable_sample_share", 0.0)) > float(base_report.get("usable_sample_share", 0.0)), "G04 effect was not stored in the real geology report")
	check(float(researched_report.get("reward_quality_bonus", 0.0)) > float(base_report.get("reward_quality_bonus", 0.0)), "G09 effect was not stored in the real geology report")
	check(int(base["research_points"]) == 1 and int(researched["research_points"]) == 1 and int(base["shards"]) == 2 and int(researched["shards"]) == 2, "Quality effects changed fixed expedition reward quantities")
	check(bool(GameMath.game(base)["progression"]["geology"]["guaranteed_geobinding"]) and bool(GameMath.game(researched)["progression"]["geology"]["guaranteed_geobinding"]), "Research changed the fixed first-survey story discovery")
	check(researched["inventory"] == inventory_before, "Geology quality re-created physical resources instead of reporting manual-mining data")

func _test_deep_mark_scope() -> void:
	var base := _profile()
	var researched := _profile()
	GameMath.game(base)["progression"]["buildings"]["deep_station"] = {"status":"complete"}
	GameMath.game(researched)["progression"]["buildings"]["deep_station"] = {"status":"complete"}
	_own(researched, "G18")
	var deep_preview: Dictionary = Progression.geology_preview(researched, "deep_signal")
	var ordinary_preview: Dictionary = Progression.geology_preview(researched, "ir_probe")
	check(float(deep_preview.get("deep_mark_precision_bonus", 0.0)) > 0.0, "G18 did not improve deep-horizon mark precision")
	check(is_zero_approx(float(ordinary_preview.get("deep_mark_precision_bonus", 0.0))), "G18 incorrectly affected a non-deep Ir expedition")
	var base_report := _complete_report(base, "deep_signal")
	var researched_report := _complete_report(researched, "deep_signal")
	check(float(researched_report.get("deep_mark_precision_bonus", 0.0)) > 0.0, "G18 precision did not reach the actual deep geology report")
	check(base_report.get("tags", []) == researched_report.get("tags", []), "G18 altered fixed deep tags or introduced rarity rerolls")
	check(int(base["shards"]) == 5 and int(researched["shards"]) == 5, "G18 changed the fixed deep expedition reward")
	check(not researched_report.has("mythical_case_chance") and GameMath.game(researched).get("meta", {}).get("cases", {}) == {}, "G18 incorrectly created or improved a mythical case")
	var regular_ir := _profile()
	GameMath.game(regular_ir)["progression"]["buildings"]["deep_station"] = {"status":"complete"}
	_own(regular_ir, "G18")
	var ordinary_report := _complete_report(regular_ir, "ir_probe")
	check(is_zero_approx(float(ordinary_report.get("deep_mark_precision_bonus", -1.0))), "G18 precision leaked into a non-deep Ir report")

func _test_safe_project_duration_scope() -> void:
	var base := _profile()
	var researched := _profile()
	for p in [base, researched]:
		var progression: Dictionary = GameMath.game(p)["progression"]
		progression["story_done"]["A19"] = true
		progression["buildings"]["hq"] = {"status":"complete"}
		progression["buildings"]["deep_station"] = {"status":"complete"}
		progression["buildings"]["power"] = {"status":"complete"}
		p["inventory"]["ir_core"] = 2
		p["inventory"]["high_strength_alloy"] = 2
	_own(researched, "IR19")
	var base_start := Progression.act(base, "build", {"id":"safe_cavity_project"})
	var researched_start := Progression.act(researched, "build", {"id":"safe_cavity_project"})
	check(bool(base_start.get("ok", false)) and bool(researched_start.get("ok", false)), "Could not start the safe-cavity project for the duration comparison")
	var base_duration := float(GameMath.game(base)["progression"]["buildings"]["safe_cavity_project"]["remaining_seconds"])
	var researched_duration := float(GameMath.game(researched)["progression"]["buildings"]["safe_cavity_project"]["remaining_seconds"])
	check(researched_duration < base_duration and is_equal_approx(researched_duration, 297.0), "IR19 did not reduce only the safe-cavity project duration")
	var other_build := _profile()
	for p in [other_build]:
		GameMath.game(p)["progression"]["buildings"]["hq"] = {"status":"complete"}
	_own(other_build, "IR19")
	var ordinary_start := Progression.act(other_build, "build", {"id":"research"})
	check(bool(ordinary_start.get("ok", false)), "Could not start a comparison building")
	check(is_equal_approx(float(GameMath.game(other_build)["progression"]["buildings"]["research"]["remaining_seconds"]), 30.0), "IR19 accelerated an unrelated construction")
	var locked := _profile()
	_own(locked, "IR19")
	check(not bool(Progression.act(locked, "build", {"id":"safe_cavity_project"}).get("ok", false)), "IR19 bypassed the A19/deep-station/power safe-project gate")
