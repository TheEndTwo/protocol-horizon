extends SceneTree

const State = preload("res://autoload/GameState.gd")
const Economy = preload("res://gameplay/EconomyModel.gd")
const Progression = preload("res://gameplay/ProgressionModel.gd")
const Sites = preload("res://gameplay/SiteModel.gd")
const Research = preload("res://gameplay/ResearchRuntime.gd")
var failures: PackedStringArray = []

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func profile() -> Dictionary:
	var p := State.make_new_profile()
	p["money_cents"] = 100000
	p["sites"]["site_earth_pd_7"]["unlocked"] = true
	Economy.ensure(p)
	Progression.ensure(p)
	Sites.ensure(p)
	Research.refresh(p)
	return p

func own(p: Dictionary, id: String, rank: int = 1) -> void:
	GameMath.game(p)["progression"]["research"][id] = rank
	Research.refresh(p)

func _run() -> void:
	_test_chemical_reserve()
	_test_express_schedule()
	if failures.is_empty():
		print("LATE SITES PASS: protected Pd chemical budget, paid-machine express schedule, fixed sample seed and scope")
	else:
		for failure in failures:
			printerr("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)

func _test_chemical_reserve() -> void:
	var p := profile()
	own(p, "PD24")
	p["money_cents"] = 1000
	GameMath.game(p)["research_runtime"]["cash_reserves"] = {"PD24":800,"P09":200}
	check(GameMath.available_money(p) == 0, "Fixture must have no unreserved cash")
	check(Sites.act(p, "pd_take_sample", {}).get("ok", false), "The actual Pd sample could not spend its chemical reserve")
	Sites.advance(p, 60)
	check(Sites.act(p, "pd_start_cycle", {}).get("ok", false), "The actual Pd cycle could not spend its chemical reserve")
	check(p["money_cents"] == 340 and GameMath.game(p)["research_runtime"]["cash_reserves"] == {"PD24":140,"P09":200}, "Pd debited the wrong reserve, created cash, or spent payroll money")
	Sites.advance(p, 200)
	check(int(p["inventory"].get("pd_concentrate", 0)) > 0, "Paid reserved Pd batch did not produce physical output")
	var blocked := profile()
	blocked["money_cents"] = 100
	GameMath.game(blocked)["research_runtime"]["cash_reserves"] = {"PD24":50,"P09":50}
	var before := blocked.duplicate(true)
	check(not Sites.act(blocked, "pd_take_sample", {}).get("ok", true), "An underfunded chemical reserve launched a free sample")
	check(blocked["money_cents"] == before["money_cents"] and GameMath.game(blocked)["research_runtime"]["cash_reserves"] == GameMath.game(before)["research_runtime"]["cash_reserves"] and Sites.view(blocked, "pd")["seed_counter"] == 0, "Failed chemical payment consumed cash, reserve, or seed")

func _test_express_schedule() -> void:
	var locked := profile()
	check(not Sites.act(locked, "pd_set_crushing_schedule", {"schedule":"express"}).get("ok", true), "Express crushing was available without research")
	own(locked, "PD09", 5)
	check(not Sites.act(locked, "pd_set_crushing_schedule", {"schedule":"express"}).get("ok", true), "Express crushing was available without a paid machine")
	check(Economy.act(locked, "buy", {"site":"pd", "kind":"machines", "id":"pd_separator", "count":1}).get("ok", false), "Could not buy the real crushing machine")
	var standard := locked.duplicate(true)
	var express := locked.duplicate(true)
	check(Sites.act(express, "pd_set_crushing_schedule", {"schedule":"express"}).get("ok", false), "PD09 did not select its unlocked schedule")
	var expected_standard: Dictionary = Sites.view(standard, "pd")["lens_options"][1]
	var expected_express: Dictionary = Sites.view(express, "pd")["lens_options"][1]
	check(float(expected_express["expected_duration_s"]) < float(expected_standard["expected_duration_s"]) and expected_express["expected_yield"] == expected_standard["expected_yield"] and expected_express["cost_cents"] == expected_standard["cost_cents"], "Crushing forecast did not isolate duration from yield and cost")
	Sites.act(standard, "pd_take_sample", {})
	Sites.act(express, "pd_take_sample", {})
	var a: Dictionary = Sites.view(standard, "pd")["sample"]
	var b: Dictionary = Sites.view(express, "pd")["sample"]
	check(float(b["cycle_duration_s"]) < float(a["cycle_duration_s"]) and a["sample_duration_s"] == b["sample_duration_s"], "Express schedule did not shorten only real crushing")
	check(a["seed"] == b["seed"] and a["quality"] == b["quality"] and a["base_yield"] == b["base_yield"] and a["operating_cost_cents"] == b["operating_cost_cents"], "Express choice rerolled or duplicated the sample")
	check(not Sites.act(express, "pd_set_crushing_schedule", {"schedule":"standard"}).get("ok", true) and Sites.view(express, "pd")["sample"]["cycle_duration_s"] == b["cycle_duration_s"], "A running sample changed its fixed schedule")
