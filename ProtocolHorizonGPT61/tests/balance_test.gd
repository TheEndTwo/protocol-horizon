extends SceneTree

const FE_ID := "site_earth_fe_17"
const PD_ID := "site_earth_pd_7"
const IR_ID := "site_earth_ir_9"
const FE350_LIMIT_DAYS := 60.0
const ACTIVE_SESSION_SECONDS := 300
const OFFLINE_GAP_SECONDS := 7 * 3600 + 55 * 60
const DAILY_OFFLINE_LEVEL := 0

var failures: PackedStringArray = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var registry: Node = root.get_node_or_null("ContentRegistry")
	if registry == null:
		var registry_script: Script = load("res://autoload/ContentRegistry.gd") as Script
		registry = registry_script.new()
		registry.name = "ContentRegistry"
		root.add_child(registry)
	await process_frame
	if not bool(registry.get("is_loaded")):
		_fail("Канонический ContentRegistry не загрузился: " + str(registry.get("errors")))
		_finish({"status":"FAIL", "reason":"ContentRegistry"})
		return

	var economy_model = load("res://gameplay/EconomyModel.gd")
	var site_model = load("res://gameplay/SiteModel.gd")
	var progression_model = load("res://gameplay/ProgressionModel.gd")
	if economy_model == null or site_model == null or progression_model == null or not economy_model.can_instantiate() or not site_model.can_instantiate() or not progression_model.can_instantiate():
		_fail("Одна из моделей баланса не загрузилась")
		_finish({"status":"FAIL", "reason":"model_load"})
		return
	var iron_price := _sale_price(registry, "iron_ore")
	var active := _measure_active_five_minutes(economy_model, iron_price)
	var daily := _measure_daily_sessions(economy_model, iron_price)
	var wages := _measure_zero_cash_wages(economy_model)
	var roi := _measure_next_level_roi(economy_model, iron_price)
	var extraction := _measure_pd_ir_margins(site_model, registry)
	var gate := _measure_fe350_gate(economy_model, progression_model)

	var summary := {
		"status":"PASS" if failures.is_empty() else "FAIL",
		"balance_status":"provisional_model_measurement_not_approved_canon",
		"cash_unit":"money_cents; 100 cents = 1 game G",
		"iron_sale_price_cents":iron_price,
		"active_free_fe_5m":active,
		"f2p_day_3x5m":daily,
		"zero_cash_wages_and_freeflow":wages,
		"next_level_roi":roi,
		"pd_ir_projection_margins":extraction,
		"fe350_gate":gate,
		"failures":failures
	}
	_finish(summary)


func _measure_active_five_minutes(economy: Variant, iron_price: int) -> Dictionary:
	var profile := _fixture("active-free-fe")
	_economy_ensure(economy, profile)
	var rate := float(economy.metrics(profile, "fe").get("rate_per_second", 0.0))
	var session := _play_active_session(economy, profile, ACTIVE_SESSION_SECONDS)
	var tap_mined := int(session["tap_iron"])
	var passive_mined := int(session["passive_iron"])
	var mined := tap_mined + passive_mined
	var peak_after_mining := int(profile["game"]["sites"]["fe"].get("peak", 0))
	var sale: Dictionary = economy.act(profile, "sell_all", {})
	var expected_cash := mined * iron_price
	_check(rate > 0.0 and mined > 0, "Добыча Fe за 5 минут игры не дала руду")
	_check(int(session["taps_succeeded"]) == ACTIVE_SESSION_SECONDS and tap_mined >= ACTIVE_SESSION_SECONDS, "Обычные ручные удары Fe не прошли с частотой 1/с")
	_check(passive_mined > 0, "Пассивное производство Fe за 5 минут не дало руду")
	_check(int(profile["money_cents"]) == expected_cash, "Продажа Fe не совпала с канонической ценой ресурса")
	_check(bool(sale.get("ok", false)), "Продажа Fe после 5 минут не прошла")
	_check(int(profile["inventory"].get("iron_ore", 0)) == 0, "Продажа Fe оставила свободную руду")
	_check(peak_after_mining == 0, "Добыча руды ошибочно увеличила исторический пик улучшений")
	return {
		"start_money_cents":0,
		"active_seconds":int(session["active_seconds"]),
		"tap_interval_seconds":1,
		"taps":int(session["taps_succeeded"]),
		"tap_iron":tap_mined,
		"passive_iron":passive_mined,
		"rate_per_minute":rate * 60.0,
		"iron_mined":mined,
		"sale_cash_cents":int(profile["money_cents"]),
		"peak_after_mining":peak_after_mining
	}


func _measure_daily_sessions(economy: Variant, iron_price: int) -> Dictionary:
	var profile := _fixture("f2p-three-sessions")
	_economy_ensure(economy, profile)
	var active_seconds := 0
	var passive_seconds := 0
	var requested_offline_seconds := 0
	var wall_seconds := 0
	var taps := 0
	var tap_iron := 0
	var session_sales_cents := 0
	for _session in 3:
		var last_saved_ts := wall_seconds
		var now := last_saved_ts + OFFLINE_GAP_SECONDS
		var offline_seconds := GameMath.offline_seconds(last_saved_ts, now, DAILY_OFFLINE_LEVEL)
		requested_offline_seconds += now - last_saved_ts
		passive_seconds += offline_seconds
		wall_seconds += now - last_saved_ts
		_check(offline_seconds == 4 * 3600, "Базовый офлайн-доход должен ограничивать каждую паузу четырьмя часами")
		economy.advance(profile, float(offline_seconds))

		var active: Dictionary = _play_active_session(economy, profile, ACTIVE_SESSION_SECONDS)
		active_seconds += int(active["active_seconds"])
		taps += int(active["taps_succeeded"])
		tap_iron += int(active["tap_iron"])
		wall_seconds += int(active["active_seconds"])
		var sale: Dictionary = economy.act(profile, "sell_all", {})
		_check(bool(sale.get("ok", false)), "Продажа запасов во время F2P-сессии не прошла")
		session_sales_cents += int(sale.get("proceeds_cents", 0))
	var produced := int(profile["game"]["stats"].get("produced:iron_ore", 0))
	var cash := int(profile["money_cents"])
	var modeled_seconds := active_seconds + passive_seconds
	var mined_total := produced + tap_iron
	_check(wall_seconds == 86400, "Три цикла 7:55 паузы + 5:00 игры должны покрывать ровно одни сутки")
	_check(active_seconds == 3 * ACTIVE_SESSION_SECONDS and taps == active_seconds, "F2P-сценарий должен выполнять ровно один обычный тап в секунду игры")
	_check(requested_offline_seconds == 3 * OFFLINE_GAP_SECONDS and passive_seconds == 3 * 4 * 3600, "Не все офлайн-паузы применили общий четырёхчасовой лимит")
	_check(produced > 0 and cash == mined_total * iron_price and session_sales_cents == cash, "Суточная F2P-модель потеряла фактическую добычу или неверно оценила продажи")
	_check(int(profile["game"]["sites"]["fe"].get("peak", 0)) == 0, "Пассивная добыча ошибочно увеличила пик улучшений")
	_check(int(profile["inventory"].get("iron_ore", 0)) == 0, "Суточные онлайн-продажи оставили свободную руду")
	return {
		"iap_spend_cents":0,
		"sessions_per_day":3,
		"active_minutes_per_session":5,
		"tap_interval_seconds":1,
		"taps":taps,
		"tap_iron":tap_iron,
		"active_seconds":active_seconds,
		"requested_offline_seconds":requested_offline_seconds,
		"offline_cap_seconds_per_pause":4 * 3600,
		"credited_offline_seconds":passive_seconds,
		"wall_day_seconds":wall_seconds,
		"modeled_seconds":modeled_seconds,
		"passive_iron_produced":produced,
		"iron_produced_including_taps":mined_total,
		"iron_per_modeled_minute":float(mined_total) * 60.0 / float(modeled_seconds),
		"cash_after_sales_cents":cash,
		"ending_inventory_iron":int(profile["inventory"].get("iron_ore", 0)),
		"upgrade_levels_bought":int(profile["game"]["stats"].get("purchases:upgrade", 0))
	}


func _play_active_session(economy: Variant, profile: Dictionary, seconds: int) -> Dictionary:
	var taps_attempted := 0
	var taps_succeeded := 0
	var tap_iron := 0
	var produced_before := int(profile["game"]["stats"].get("produced:iron_ore", 0))
	for _second in seconds:
		economy.advance(profile, 1.0)
		var result: Dictionary = economy.act(profile, "tap", {"site":"fe", "precision":false})
		taps_attempted += 1
		if bool(result.get("ok", false)):
			taps_succeeded += 1
			tap_iron += int(result.get("amount", 0))
	_check(taps_succeeded == taps_attempted, "Один или несколько обычных ручных ударов Fe не прошли")
	var produced_after := int(profile["game"]["stats"].get("produced:iron_ore", 0))
	return {
		"active_seconds":seconds,
		"taps_attempted":taps_attempted,
		"taps_succeeded":taps_succeeded,
		"tap_iron":tap_iron,
		"passive_iron":produced_after - produced_before
	}


func _measure_zero_cash_wages(economy: Variant) -> Dictionary:
	var freeflow := _fixture("zero-cash-freeflow")
	_economy_ensure(economy, freeflow)
	economy.advance(freeflow, 300.0)
	var free_ore := int(freeflow["inventory"].get("iron_ore", 0))

	var with_worker := _fixture("zero-cash-wages")
	with_worker["game"] = {"sites":{"fe":{"workers":{"iron_miner":1}}}}
	_economy_ensure(economy, with_worker)
	economy.advance(with_worker, 300.0)
	var worker_scenario_ore := int(with_worker["inventory"].get("iron_ore", 0))
	var wages_paid := int(with_worker["game"]["stats"].get("fe_wages_paid_cents", 0))
	var worker_rate := float(economy.metrics(with_worker, "fe").get("worker_rate_per_second", 0.0))
	_check(free_ore > 0, "Базовый поток Fe без зарплат остановился при нулевом балансе")
	_check(worker_scenario_ore == free_ore, "При нулевом балансе оплачиваемая добыча рабочего не должна начисляться")
	_check(wages_paid == 0 and int(with_worker["money_cents"]) == 0, "Модель списала зарплату в долг при нулевом балансе")
	return {
		"start_money_cents":0,
		"active_seconds":300,
		"freeflow_iron":free_ore,
		"one_miner_unpaid_iron":worker_scenario_ore,
		"one_miner_nominal_rate_per_second":worker_rate,
		"wages_paid_cents":wages_paid,
		"ending_money_cents":int(with_worker["money_cents"])
	}


func _measure_next_level_roi(economy: Variant, iron_price: int) -> Dictionary:
	var profile := _fixture("next-level-roi")
	_economy_ensure(economy, profile)
	var quote: Dictionary = economy.quote(profile, "fe", "upgrade", "iron_tunnel_support", 1)
	var before: Dictionary = quote.get("effect_before", {})
	var after: Dictionary = quote.get("effect_after", {})
	var delta_rate := float(after.get("rate_per_second", 0.0)) - float(before.get("rate_per_second", 0.0))
	var cost := int(quote.get("cost_cents", 0))
	var incremental_per_day := delta_rate * 86400.0 * float(iron_price)
	var payback_hours := float(cost) / (delta_rate * 3600.0 * float(iron_price)) if delta_rate > 0.0 and iron_price > 0 else INF
	_check(cost > 0 and delta_rate > 0.0 and is_finite(payback_hours), "Не удалось рассчитать следующий уровень улучшения по EconomyModel.quote")
	return {
		"upgrade_id":"iron_tunnel_support",
		"current_level":0,
		"cost_cents":cost,
		"before_iron_per_minute":float(before.get("rate_per_second", 0.0)) * 60.0,
		"after_iron_per_minute":float(after.get("rate_per_second", 0.0)) * 60.0,
		"incremental_iron_per_minute":delta_rate * 60.0,
		"incremental_cash_cents_per_day":incremental_per_day,
		"payback_hours":payback_hours,
		"gross_return_24h_percent":incremental_per_day * 100.0 / float(cost) if cost > 0 else 0.0
	}


func _measure_pd_ir_margins(site_model: Variant, registry: Node) -> Dictionary:
	var profile := _fixture("pd-ir-forecast")
	profile["sites"][PD_ID]["unlocked"] = true
	profile["sites"][IR_ID]["unlocked"] = true
	var pd_price := _sale_price(registry, "pd_concentrate")
	var ir_price := _sale_price(registry, "ir_core")
	var pd_view: Dictionary = site_model.view(profile, "pd")
	var ir_view: Dictionary = site_model.view(profile, "ir")
	var pd_margins := _margins(pd_view.get("lens_options", []), pd_price, "pd")
	var ir_margins := _margins(ir_view.get("strategy_options", []), ir_price, "ir")
	_check(pd_price > 0 and ir_price > 0, "Нет канонических цен продажи Pd/Ir для расчёта маржи")
	_check(not pd_margins.is_empty() and not ir_margins.is_empty(), "SiteModel не вернул прогнозы доходности Pd/Ir")
	for margin in pd_margins + ir_margins:
		_check(int(margin["net_cash_cents"]) == int(margin["gross_cash_cents"]) - int(margin["modeled_cost_cents"]), "Маржа Pd/Ir не равна выручке минус смоделированные расходы")
	return {
		"projections_only_not_realized":true,
		"pd_output_sale_price_cents":pd_price,
		"pd_lenses":pd_margins,
		"ir_output_sale_price_cents":ir_price,
		"ir_strategies":ir_margins
	}


func _margins(options: Array, sale_price: int, prefix: String) -> Array:
	var results: Array = []
	for option_value in options:
		var option: Dictionary = option_value
		var projection: Dictionary = option.get("projection", option)
		var expected_yield := float(projection.get("expected_yield", 0.0))
		var duration := float(projection.get("expected_duration_s", projection.get("duration_seconds", 0.0)))
		var gross := int(floor(expected_yield * float(sale_price)))
		var cost := int(projection.get("cost_cents", 0))
		var net := gross - cost
		var net_per_hour := int(floor(float(net) * 3600.0 / duration)) if duration > 0.0 else 0
		results.append({
			"id":String(option.get("id", "")),
			"name":String(option.get("name", option.get("id", ""))),
			"output_item":String(projection.get("yield_item", "pd_concentrate" if prefix == "pd" else "ir_core")),
			"expected_yield":expected_yield,
			"duration_seconds":duration,
			"sale_price_cents_per_unit":sale_price,
			"gross_cash_cents":gross,
			"modeled_cost_cents":cost,
			"net_cash_cents":net,
			"net_cash_cents_per_hour":net_per_hour
		})
	return results


func _measure_fe350_gate(economy: Variant, progression: Variant) -> Dictionary:
	var profile := _fixture("fe350-hourly-sale-buy-all")
	profile["game"] = {
		"stats":{"produced:steel":1},
		"progression":{
			"story_done":{"A06":true},
			"geology":{"guaranteed_geobinding":true}
		}
	}
	economy.ensure(profile)
	progression.refresh(profile)
	var initial_locked := not bool(profile["sites"][PD_ID].get("unlocked", false))
	var elapsed_hours := 0
	var max_hours := int(FE350_LIMIT_DAYS * 24.0)
	while int(profile["game"]["sites"]["fe"].get("peak", 0)) < 350 and elapsed_hours < max_hours:
		economy.advance(profile, 3600.0)
		economy.act(profile, "sell_all", {})
		economy.act(profile, "buy_all", {"site":"fe", "budget_cents":int(profile["money_cents"])})
		elapsed_hours += 1
		_check(int(profile["money_cents"]) >= 0, "Экономическая симуляция создала отрицательный баланс")
	var peak := int(profile["game"]["sites"]["fe"].get("peak", 0))
	progression.refresh(profile)
	var pd_unlocked := bool(profile["sites"][PD_ID].get("unlocked", false))
	var reached := peak >= 350
	var days := float(elapsed_hours) / 24.0
	_check(initial_locked, "Pd открылся до достижения пика Fe-350 при остальных выполненных условиях")
	_check(reached, "Fe-350 не достигнут в пределах %.0f суток при почасовой продаже и покупке в пределах бюджета" % FE350_LIMIT_DAYS)
	_check(not reached or pd_unlocked, "Pd не открылся после Fe-350 при заданных выполненных условиях")
	return {
		"target_average_upgrade_peak":350,
		"reached":reached,
		"elapsed_hours":elapsed_hours,
		"elapsed_days":days,
		"max_days":FE350_LIMIT_DAYS,
		"strategy":"hourly EconomyModel.advance(3600) -> sell_all -> budgeted buy_all; no workers/IAP",
		"average_upgrade_peak":peak,
		"upgrade_levels_sum":_upgrade_level_sum(profile),
		"ending_cash_cents":int(profile["money_cents"]),
		"pd_locked_before_threshold":initial_locked,
		"pd_unlocked_after_threshold":pd_unlocked
	}


func _upgrade_level_sum(profile: Dictionary) -> int:
	var total := 0
	for value in profile["game"]["sites"]["fe"].get("upgrades", {}).values():
		total += int(value)
	return total


func _economy_ensure(economy: Variant, profile: Dictionary) -> void:
	economy.ensure(profile)


func _fixture(profile_id: String) -> Dictionary:
	return {
		"profile_id":"balance-" + profile_id,
		"money_cents":0,
		"inventory":{"iron_ore":0},
		"sites":{
			FE_ID:{"unlocked":true},
			PD_ID:{"unlocked":false},
			IR_ID:{"unlocked":false}
		}
	}


func _sale_price(registry: Node, resource: String) -> int:
	var record: Dictionary = registry.get_record(&"resources", resource)
	return int(record.get("sale_price_cents", 0))


func _check(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)


func _fail(message: String) -> void:
	failures.append(message)
	printerr("FAIL: " + message)


func _finish(summary: Dictionary) -> void:
	if not failures.is_empty():
		summary["status"] = "FAIL"
		summary["failures"] = failures
	print("BALANCE_JSON " + JSON.stringify(summary))
	if failures.is_empty():
		var active: Dictionary = summary.get("active_free_fe_5m", {})
		var daily: Dictionary = summary.get("f2p_day_3x5m", {})
		var wages: Dictionary = summary.get("zero_cash_wages_and_freeflow", {})
		var roi: Dictionary = summary.get("next_level_roi", {})
		var gate: Dictionary = summary.get("fe350_gate", {})
		print("БАЛАНС (предварительная модель, не утверждённый канон): 5 мин Fe при 1 тапе/с — %d руды (%d тапами, %d пассивно), продажа %d центов; 3×5 мин/сутки с офлайн-лимитом 4 ч на паузу — %d руды (%d тапами, %d пассивно), продажа %d центов; при нуле денег свободный поток %d руды, шахтёр без зарплаты — %d руды без долга; следующий уровень — %d центов, окупаемость %.2f ч; Fe-350 — %.2f суток, Pd после порога: %s." % [int(active.get("iron_mined", 0)), int(active.get("tap_iron", 0)), int(active.get("passive_iron", 0)), int(active.get("sale_cash_cents", 0)), int(daily.get("iron_produced_including_taps", 0)), int(daily.get("tap_iron", 0)), int(daily.get("passive_iron_produced", 0)), int(daily.get("cash_after_sales_cents", 0)), int(wages.get("freeflow_iron", 0)), int(wages.get("one_miner_unpaid_iron", 0)), int(roi.get("cost_cents", 0)), float(roi.get("payback_hours", 0.0)), float(gate.get("elapsed_days", 0.0)), str(gate.get("pd_unlocked_after_threshold", false))])
		quit(0)
	else:
		quit(1)
