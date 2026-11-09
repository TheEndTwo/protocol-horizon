extends SceneTree

const Registry = preload("res://autoload/ContentRegistry.gd")
const State = preload("res://autoload/GameState.gd")
const Economy = preload("res://gameplay/EconomyModel.gd")

var failures: PackedStringArray = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	root.add_child(Registry.new())
	await process_frame
	_test_definitions_and_start()
	_test_quote_purchase()
	_test_sale_reservations()
	_test_factory_recipe()
	_test_wages_and_determinism()
	_test_horizons()
	if failures.is_empty():
		print("ECONOMY PASS: definitions, free Fe start, exact quotes, reserved sales, canonical factory, wages, deterministic advance, horizons")
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: " + failure)
		quit(1)

func _test_definitions_and_start() -> void:
	var profile := State.make_new_profile()
	Economy.ensure(profile)
	check(Economy.definitions("fe", "upgrade").size() == 10, "Fe must have ten upgrades")
	check(Economy.definitions("fe", "machine").size() == 5, "Fe must have five machines")
	check(Economy.definitions("fe", "worker").size() == 5, "Fe must have five professions")
	check(Economy.definitions("pd", "upgrade").size() == 10 and Economy.definitions("ir", "upgrade").size() == 10, "Pd/Ir upgrade trees must be complete")
	check(int(profile["money_cents"]) == 0, "Economy initialization must not invent money")
	var tap := Economy.act(profile, "tap", {})
	check(bool(tap.get("ok", false)) and int(profile["inventory"]["iron_ore"]) == 1, "Manual Fe mining must remain free at zero money")
	var sale := Economy.act(profile, "sell", {"resource":"iron_ore", "amount":-1})
	check(bool(sale.get("ok", false)) and int(profile["money_cents"]) == 100, "Canonical ore sale must pay 100 cents")

func _test_quote_purchase() -> void:
	var profile := State.make_new_profile()
	Economy.ensure(profile)
	profile["money_cents"] = 10000
	var quote := Economy.quote(profile, "fe", "upgrade", "iron_precise_strike", 1)
	check(bool(quote.get("ok", false)) and int(quote.get("cost_cents", -1)) == 100, "First upgrade quote should be one whole G")
	check(int(quote.get("cost_cents", 0)) % 100 == 0, "Upgrade prices must ceil to whole G")
	var before := int(profile["money_cents"])
	var bought := Economy.act(profile, "buy", {"site":"fe", "kind":"upgrade", "id":"iron_precise_strike", "count":1})
	check(bool(bought.get("ok", false)) and int(profile["money_cents"]) == before - int(quote["cost_cents"]), "Purchase must debit the exact quote")
	check(int(profile["game"]["sites"]["fe"]["upgrades"]["iron_precise_strike"]) == 1, "Purchase level was not applied")
	profile["money_cents"] = 0
	var snapshot := profile.duplicate(true)
	var refused := Economy.act(profile, "buy", {"site":"fe", "kind":"upgrade", "id":"iron_precise_strike", "count":1})
	check(not bool(refused.get("ok", false)) and profile["game"]["sites"] == snapshot["game"]["sites"], "Unaffordable purchase must be atomic")

func _test_sale_reservations() -> void:
	var profile := State.make_new_profile()
	Economy.ensure(profile)
	profile["inventory"]["iron_ore"] = 10
	var reserved := Economy.act(profile, "reserve", {"token":"contract:test", "items":{"iron_ore":7}})
	check(bool(reserved.get("ok", false)), "Valid reservation failed")
	var sale := Economy.act(profile, "sell", {"resource":"iron_ore", "amount":-1})
	check(bool(sale.get("ok", false)) and int(sale["amount"]) == 3, "Sale must only consume unreserved ore")
	check(int(profile["inventory"]["iron_ore"]) == 7 and int(profile["money_cents"]) == 300, "Reserved stock or sale proceeds are incorrect")
	var duplicate := Economy.act(profile, "reserve", {"token":"contract:test", "items":{"iron_ore":1}})
	check(not bool(duplicate.get("ok", false)) and int(profile["inventory"]["iron_ore"]) == 7, "Duplicate reservation must not mutate stock")
	var unreserved := Economy.act(profile, "unreserve", {"token":"contract:test"})
	check(bool(unreserved.get("ok", false)) and GameMath.free_amount(profile, "iron_ore") == 7, "Unreserve did not restore free stock")

func _test_factory_recipe() -> void:
	var profile := State.make_new_profile()
	Economy.ensure(profile)
	profile["money_cents"] = 10000
	profile["inventory"]["iron_ore"] = 5
	var queued := Economy.act(profile, "queue", {"recipe":"R_INGOT", "line":0, "count":1})
	check(bool(queued.get("ok", false)), "Canonical ingot recipe failed to queue: " + str(queued))
	check(int(profile["inventory"]["iron_ore"]) == 0 and int(profile["money_cents"]) == 9950, "Queue start must immediately debit 5 ore and 50 cents")
	Economy.advance(profile, 30.0)
	check(int(profile["inventory"].get("ingot", 0)) == 1, "Queued ingot did not complete after proposed duration")
	check(float(profile["game"]["stats"].get("produced:ingot", 0.0)) == 1.0, "Factory output statistic is missing")
	var locked := State.make_new_profile()
	Economy.ensure(locked)
	locked["inventory"]["pd_concentrate"] = 4
	locked["money_cents"] = 1000
	var pd := Economy.act(locked, "queue", {"recipe":"R_PD_REFINED", "line":1, "count":1})
	check(not bool(pd.get("ok", false)), "Locked Pd recipe must not run")

func _test_wages_and_determinism() -> void:
	var poor := State.make_new_profile()
	Economy.ensure(poor)
	poor["money_cents"] = 100000
	var hired := Economy.act(poor, "buy", {"site":"fe", "kind":"worker", "id":"iron_miner", "count":1})
	check(bool(hired.get("ok", false)), "Miner hire failed")
	poor["money_cents"] = 0
	var mined_before := float(poor["game"]["sites"]["fe"]["mined"])
	Economy.advance(poor, 60.0)
	var mined_after := float(poor["game"]["sites"]["fe"]["mined"])
	var base_rate := float(Economy.metrics(poor, "fe")["base_rate_per_second"])
	check(int(poor["money_cents"]) == 0, "Unpaid wages must never create debt")
	check(is_equal_approx(mined_after - mined_before, base_rate * 60.0), "Workers must pause without wages while free passive mining continues")

	var first := State.make_new_profile()
	Economy.ensure(first)
	first["money_cents"] = 100000
	first["inventory"]["iron_ore"] = 100
	Economy.act(first, "buy", {"site":"fe", "kind":"worker", "id":"iron_miner", "count":2})
	Economy.act(first, "queue", {"recipe":"R_INGOT", "line":0, "count":2})
	var second: Dictionary = first.duplicate(true)
	Economy.advance(first, 20.0)
	Economy.advance(second, 10.0)
	Economy.advance(second, 10.0)
	check(first["inventory"] == second["inventory"], "Split elapsed time changed inventory")
	check(int(first["money_cents"]) == int(second["money_cents"]), "Split elapsed time changed wallet/wage outcome")
	check(first["game"]["factory"] == second["game"]["factory"], "Split elapsed time changed factory progress")
	check(is_equal_approx(float(first["game"]["sites"]["fe"]["mined"]), float(second["game"]["sites"]["fe"]["mined"])), "Split elapsed time changed production")

func _test_horizons() -> void:
	var profile := State.make_new_profile()
	Economy.ensure(profile)
	var upgrades: Dictionary = profile["game"]["sites"]["fe"]["upgrades"]
	for definition in Economy.definitions("fe", "upgrade"):
		upgrades[str(definition["id"])] = 100
	Economy.ensure(profile)
	var opened := Economy.act(profile, "horizon", {"site":"fe", "index":10})
	check(bool(opened.get("ok", false)), "Horizon ten should unlock at average level 100")
	var beyond := Economy.act(profile, "horizon", {"site":"fe", "index":11})
	check(not bool(beyond.get("ok", false)), "Horizons beyond 1000 must remain locked")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
