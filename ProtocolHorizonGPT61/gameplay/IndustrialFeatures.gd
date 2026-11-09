class_name EarthIndustrialFeatures
extends RefCounted

const CONFIG_PATH := "res://data/proposals/industrial_features.json"
const SITE_MODEL_PATH := "res://gameplay/SiteModel.gd"
const MATH := preload("res://gameplay/GameMath.gd")
const NO_EVENT := 1.0e30

static var _config_cache: Dictionary = {}

static func ensure(p: Dictionary) -> Dictionary:
	var game := MATH.game(p)
	if not game.has("feature_families") or not game["feature_families"] is Dictionary:
		game["feature_families"] = {}
	var families: Dictionary = game["feature_families"]
	if not families.has("industrial") or not families["industrial"] is Dictionary:
		families["industrial"] = {}
	var industrial: Dictionary = families["industrial"]
	if not industrial.has("pd") or not industrial["pd"] is Dictionary:
		industrial["pd"] = {}
	if not industrial.has("ir") or not industrial["ir"] is Dictionary:
		industrial["ir"] = {}
	if not industrial.has("contact") or not industrial["contact"] is Dictionary:
		industrial["contact"] = {}
	var pd: Dictionary = industrial["pd"]
	var ir: Dictionary = industrial["ir"]
	var contact: Dictionary = industrial["contact"]
	_ensure_fields(pd, {"contract_order_id":"", "used_contract_orders":{}, "pending_analysis_task":{}, "completed_tasks":{}, "reports":{}, "distant_note":{}, "second_sample_task":{}, "second_sample_preview":{}, "filter_task":{}, "filter_prepared":false, "forecast_lines":{}})
	_ensure_fields(ir, {"support_task":{}, "support_prepared":false, "manipulator_task":{}, "manipulator_prepared":false, "expedition":{}, "program":{}, "last_program_message":""})
	_ensure_fields(contact, {"next_profile_id":""})
	var max_lines := int(_config().get("pd", {}).get("forecast", {}).get("max_lines", 2))
	var lines: Dictionary = pd["forecast_lines"]
	for index in range(maxi(0, max_lines)):
		if not lines.has(str(index)) or not lines[str(index)] is Dictionary:
			lines[str(index)] = {}
	return industrial

static func refresh(p: Dictionary) -> void:
	ensure(p)

static func advance(p: Dictionary, dt: float) -> void:
	var industrial := ensure(p)
	if not is_finite(dt) or dt <= 0.0:
		return
	var pd: Dictionary = industrial["pd"]
	var second_sample: Dictionary = pd.get("second_sample_task", {})
	_tick_job(second_sample, dt)
	if str(second_sample.get("status", "")) == "complete":
		pd["second_sample_preview"] = second_sample.get("preview", {}).duplicate(true)
		pd["completed_tasks"]["pd_second_sample"] = {"completed":true, "seed_reference":int(second_sample.get("seed_reference", 0))}
		pd["second_sample_task"] = {}
	var filter_task: Dictionary = pd.get("filter_task", {})
	_tick_job(filter_task, dt)
	if str(filter_task.get("status", "")) == "complete":
		pd["filter_prepared"] = true
		pd["filter_task"] = {}
	for key in pd["forecast_lines"]:
		var line: Dictionary = pd["forecast_lines"][key]
		_tick_job(line, dt)
		if str(line.get("status", "")) == "complete":
			line["result"] = {"target_id":str(line.get("target_id", "")), "forecast_only":true}
	var ir: Dictionary = industrial["ir"]
	var support_task: Dictionary = ir.get("support_task", {})
	_tick_job(support_task, dt)
	if str(support_task.get("status", "")) == "complete":
		ir["support_prepared"] = true
		ir["support_task"] = {}
	var manipulator_task: Dictionary = ir.get("manipulator_task", {})
	_tick_job(manipulator_task, dt)
	if str(manipulator_task.get("status", "")) == "complete":
		ir["manipulator_prepared"] = true
		ir["manipulator_task"] = {}
	var expedition: Dictionary = ir.get("expedition", {})
	_tick_job(expedition, dt)
	if str(expedition.get("status", "")) == "complete":
		var report_id := str(expedition.get("report_id", ""))
		if not report_id.is_empty() and not expedition.get("reported", false):
			expedition["reported"] = true
			expedition["report"] = {"id":report_id, "kind":"ancient_geology", "collected":true}
			MATH.stat(p, "ir_ancient_reports")

static func next_event_in(p: Dictionary) -> float:
	var industrial := ensure(p)
	var next := NO_EVENT
	var pd: Dictionary = industrial["pd"]
	next = minf(next, _job_eta(pd.get("second_sample_task", {})))
	next = minf(next, _job_eta(pd.get("filter_task", {})))
	for line in pd["forecast_lines"].values():
		next = minf(next, _job_eta(line))
	var ir: Dictionary = industrial["ir"]
	next = minf(next, _job_eta(ir.get("support_task", {})))
	next = minf(next, _job_eta(ir.get("manipulator_task", {})))
	next = minf(next, _job_eta(ir.get("expedition", {})))
	return next

static func act(p: Dictionary, action: String, args: Dictionary) -> Dictionary:
	var industrial := ensure(p)
	var id := str(args.get("id", ""))
	if not _feature_ids().has(id) or not _owned(p, id):
		return MATH.fail("Сначала изучите соответствующее исследование или мастерство")
	var site := "ir" if id.begins_with("IR") else "pd"
	if not MATH.unlocked(p, site):
		return MATH.fail("Участок ещё не открыт")
	if not action.begins_with("industry_"):
		return MATH.fail("Неизвестное действие промышленного узла")
	var pd: Dictionary = industrial["pd"]
	var ir: Dictionary = industrial["ir"]
	var contact: Dictionary = industrial["contact"]
	match action:
		"industry_select_lens":
			if id != "PD05": return MATH.fail("Действие относится к другому узлу")
			return _site_act(p, "select_lens", {"site":"pd", "lens_id":str(args.get("lens_id", ""))})
		"industry_set_contract_profile":
			var order_id := str(args.get("order_id", ""))
			if not _active_order(p, order_id, "pd_concentrate"): return MATH.fail("Нужен активный принятый контракт с фактическим спросом на концентрат палладия")
			pd["contract_order_id"] = order_id
			return MATH.ok("Профиль будет применён только к следующему отбору под этот контракт")
		"industry_repeat_analysis":
			if id != "PD22": return MATH.fail("Действие относится к другому узлу")
			var cfg: Dictionary = _config().get("pd", {}).get("repeat_analysis", {})
			return _start_pd_side_analysis(p, pd, "pd_repeat_analysis", int(cfg.get("fee_cents", 0)), float(cfg.get("duration_s", 0.0)), {})
		"industry_start_forecast":
			if id != "PD23": return MATH.fail("Действие относится к другому узлу")
			return _start_forecast(p, pd, args)
		"industry_start_impurity_report":
			if id != "PD27": return MATH.fail("Действие относится к другому узлу")
			var target_id := str(args.get("target_id", ""))
			if not _target_exists(_config().get("pd", {}).get("impurity_report", {}).get("targets", []), target_id): return MATH.fail("Выберите тип примесей из списка")
			if pd["reports"].has(target_id): return MATH.fail("Отчёт по этому типу примесей уже собран")
			var report_cfg: Dictionary = _config().get("pd", {}).get("impurity_report", {})
			return _start_pd_side_analysis(p, pd, "pd_impurity_report", int(report_cfg.get("fee_cents", 0)), float(report_cfg.get("duration_s", 0.0)), {"target_id":target_id})
		"industry_start_distant_analysis":
			if id != "PD29": return MATH.fail("Действие относится к другому узлу")
			if not Dictionary(pd.get("distant_note", {})).is_empty(): return MATH.fail("Дальняя геологическая заметка уже собрана")
			var distant: Dictionary = _config().get("pd", {}).get("distant_analysis", {})
			return _start_pd_side_analysis(p, pd, "pd_distant_analysis", int(distant.get("fee_cents", 0)), float(distant.get("duration_s", 0.0)), {})
		"industry_take_second_sample":
			if id != "PD_SK02": return MATH.fail("Действие относится к другому узлу")
			return _start_pd_second_sample(p, pd)
		"industry_prepare_filter":
			if id != "PD_SK06": return MATH.fail("Действие относится к другому узлу")
			if bool(pd.get("filter_prepared", false)) or not Dictionary(pd.get("filter_task", {})).is_empty(): return MATH.fail("Подготовка фильтра уже активна или ожидает следующую партию")
			var filter_cfg: Dictionary = _config().get("pd", {}).get("filter_prep", {})
			if not _pay(p, int(filter_cfg.get("fee_cents", 0))): return MATH.fail("Недостаточно кредитов для подготовки фильтра")
			pd["filter_task"] = _new_job("manual_filter", float(filter_cfg.get("duration_s", 0.0)))
			return MATH.ok("Ручная подготовка фильтра оплачена; готовность наступит после рабочего времени")
		"industry_start_deep_route":
			if id != "IR05": return MATH.fail("Действие относится к другому узлу")
			var strategy := str(args.get("strategy_id", "reliable"))
			if not _safe_strategy(strategy): return MATH.fail("Выберите безопасную стратегию кампании")
			return _site_act(p, "start_campaign", {"site":"ir", "strategy_id":strategy, "deep_route":true})
		"industry_prepare_supports":
			if id != "IR06": return MATH.fail("Действие относится к другому узлу")
			if bool(ir.get("support_prepared", false)) or not Dictionary(ir.get("support_task", {})).is_empty(): return MATH.fail("Опоры уже подготовлены или подготовка ещё выполняется")
			if not _ir_idle_for_prep(p): return MATH.fail("Подготовка опор доступна между кампаниями")
			var support: Dictionary = _config().get("ir", {}).get("support_prep", {})
			if not _pay(p, int(support.get("fee_cents", 0))): return MATH.fail("Недостаточно кредитов для подготовки опор")
			ir["support_task"] = _new_job("support_prep", float(support.get("duration_s", 0.0)))
			return MATH.ok("Подготовка опор оплачена и начата")
		"industry_prepare_contact_profile":
			if id != "IR14": return MATH.fail("Действие относится к другому узлу")
			var profile_id := str(args.get("profile_id", ""))
			var profiles: Dictionary = _config().get("contact_assembly", {}).get("profiles", {})
			if not profiles.has(profile_id): return MATH.fail("Выберите профиль сборки контактов")
			if not str(contact.get("next_profile_id", "")).is_empty(): return MATH.fail("Сначала поставьте реальную партию с уже подготовленным профилем")
			var fee := int(_config().get("contact_assembly", {}).get("preparation_fee_cents", 0))
			if not _pay(p, fee): return MATH.fail("Недостаточно кредитов для настройки профиля контактов")
			contact["next_profile_id"] = profile_id
			return MATH.ok("Профиль оплачен и будет использован ровно для следующей реальной партии контактов")
		"industry_start_autoprogram":
			if id != "IR16": return MATH.fail("Действие относится к другому узлу")
			return _start_autoprogram(p, ir, args)
		"industry_start_contract_route":
			if id != "IR17": return MATH.fail("Действие относится к другому узлу")
			return _start_contract_route(p, args)
		"industry_pause_ir":
			if id != "IR23": return MATH.fail("Действие относится к другому узлу")
			var ir_state := _site_view(p, "ir")
			if str(ir_state.get("status", "")) != "running": return MATH.fail("Плановая пауза доступна во время работающей кампании")
			var campaign: Dictionary = _ir_extraction_state(p).get("campaign", {})
			campaign["pause_after_phase"] = true
			return MATH.ok("Пауза запланирована после текущей уже оплаченной фазы")
		"industry_resume_ir":
			if id != "IR23": return MATH.fail("Действие относится к другому узлу")
			return _site_act(p, "resume", {"site":"ir"})
		"industry_start_ancient_expedition":
			if id != "IR28": return MATH.fail("Действие относится к другому узлу")
			if not Dictionary(ir.get("expedition", {})).is_empty(): return MATH.fail("Экспедиция уже проведена или выполняется")
			if not _ir_idle_for_prep(p): return MATH.fail("Экспедиция доступна между кампаниями")
			var expedition_cfg: Dictionary = _config().get("ir", {}).get("ancient_expedition", {})
			if not _pay(p, int(expedition_cfg.get("fee_cents", 0))): return MATH.fail("Недостаточно кредитов для экспедиции")
			ir["expedition"] = _new_job("ancient_expedition", float(expedition_cfg.get("duration_s", 0.0)))
			ir["expedition"]["report_id"] = str(expedition_cfg.get("report_id", ""))
			return MATH.ok("Факультативная экспедиция оплачена; отчёт будет выдан после исследования")
		"industry_prepare_manipulator":
			if id != "IR_SK05": return MATH.fail("Действие относится к другому узлу")
			if bool(ir.get("manipulator_prepared", false)) or not Dictionary(ir.get("manipulator_task", {})).is_empty(): return MATH.fail("Манипулятор уже подготовлен или подготовка ещё выполняется")
			if not _ir_idle_for_prep(p): return MATH.fail("Подготовка манипулятора доступна между кампаниями")
			var manipulator: Dictionary = _config().get("ir", {}).get("manipulator_prep", {})
			if not _pay(p, int(manipulator.get("fee_cents", 0))): return MATH.fail("Недостаточно кредитов для подготовки манипулятора")
			ir["manipulator_task"] = _new_job("manipulator_prep", float(manipulator.get("duration_s", 0.0)))
			return MATH.ok("Подготовка манипулятора оплачена; эффект ожидает следующую кампанию")
	return MATH.fail("Действие не реализовано для этого узла")

static func operations(p: Dictionary, id: String) -> Array:
	ensure(p)
	if not _feature_ids().has(id) or not _owned(p, id): return []
	var site := "ir" if id.begins_with("IR") else "pd"
	if not MATH.unlocked(p, site): return []
	var cfg := _config()
	match id:
		"PD05": return [{"action":"industry_select_lens", "title":"Выбрать дополнительный геопласт", "fields":[{"key":"lens_id", "label":"Геологическая линза", "type":"select", "choices":_named_choices(lens_definitions(p))}]}]
		"PD17": return [{"action":"industry_set_contract_profile", "title":"Профиль следующего отбора по принятому контракту", "fields":[{"key":"order_id", "label":"Активный контракт на Pd-концентрат", "type":"select", "choices":_contract_choices(p, "pd_concentrate")}]}]
		"PD22": return [{"action":"industry_repeat_analysis", "title":"Оплатить и провести повторный анализ керна", "fields":[]}]
		"PD23": return [{"action":"industry_start_forecast", "title":"Запустить прогнозную линию георадара", "fields":[{"key":"line_id", "label":"Линия прогноза", "type":"select", "choices":_line_choices(int(cfg.pd.forecast.max_lines))}, {"key":"target_id", "label":"Геологическая цель", "type":"select", "choices":_named_choices(cfg.pd.forecast.targets)}]}]
		"PD27": return [{"action":"industry_start_impurity_report", "title":"Провести анализ для коллекционного отчёта", "fields":[{"key":"target_id", "label":"Тип примесей", "type":"select", "choices":_named_choices(cfg.pd.impurity_report.targets)}]}]
		"PD29": return [{"action":"industry_start_distant_analysis", "title":"Оплатить дальний участок анализа", "fields":[]}]
		"PD_SK02": return [{"action":"industry_take_second_sample", "title":"Снять дополнительный предварительный образец", "fields":[]}]
		"PD_SK06": return [{"action":"industry_prepare_filter", "title":"Вручную подготовить фильтр к следующей партии", "fields":[]}]
		"IR05": return [{"action":"industry_start_deep_route", "title":"Начать дорогой глубинный маршрут", "fields":[{"key":"strategy_id", "label":"Безопасная стратегия", "type":"select", "choices":_safe_strategy_choices()}]}]
		"IR06": return [{"action":"industry_prepare_supports", "title":"Оплатить подготовку дополнительных опор", "fields":[]}]
		"IR14": return [{"action":"industry_prepare_contact_profile", "title":"Подготовить профиль следующей партии термоконтактов", "fields":[{"key":"profile_id", "label":"Профиль", "type":"select", "choices":_contact_profile_choices()}]}]
		"IR16": return [{"action":"industry_start_autoprogram", "title":"Запустить последовательную безопасную программу кампаний", "fields":[{"key":"strategy_id", "label":"Стратегия", "type":"select", "choices":_safe_strategy_choices()}, {"key":"campaign_count", "label":"Число кампаний", "type":"number", "min":1, "max":int(cfg.ir.safe_program.max_campaigns)}, {"key":"budget_cents", "label":"Общий предел расходов", "type":"number", "min":1, "max":10000000}]}]
		"IR17": return [{"action":"industry_start_contract_route", "title":"Начать безопасный маршрут под принятый заказ", "fields":[{"key":"order_id", "label":"Принятый заказ на Ir-ядра", "type":"select", "choices":_contract_choices(p, "ir_core")}]}]
		"IR23": return [{"action":"industry_pause_ir", "title":"Запланировать паузу между фазами", "fields":[]}, {"action":"industry_resume_ir", "title":"Продолжить кампанию и оплатить следующую фазу", "fields":[]}]
		"IR28": return [{"action":"industry_start_ancient_expedition", "title":"Оплатить необязательную экспедицию древних геометок", "fields":[]}]
		"IR_SK05": return [{"action":"industry_prepare_manipulator", "title":"Оплатить подготовку манипулятора к одной партии", "fields":[]}]
	return []

static func after_action(p: Dictionary, domain: String, action: String, args: Dictionary, result: Dictionary) -> void:
	if not bool(result.get("ok", false)):
		return
	ensure(p)
	if domain == "economy" and action == "queue" and str(args.get("recipe", args.get("id", ""))) == "R_IR_CONTACT":
		var line_index := int(result.get("line", -1))
		var factory: Array = MATH.game(p).get("factory", [])
		if line_index >= 0 and line_index < factory.size():
			var line: Dictionary = factory[line_index]
			var queue: Array = line.get("queue", [])
			if not queue.is_empty():
				var job: Dictionary = queue.back()
				if str(job.get("recipe_id", "")) == "R_IR_CONTACT":
					var profile := take_recipe_profile(p, "R_IR_CONTACT")
					if not profile.is_empty():
						job["industrial_profile_id"] = str(profile.get("profile_id", ""))
						job["seconds_per_unit"] = maxf(1.0, float(job.get("seconds_per_unit", 1.0)) * float(profile.get("duration_multiplier", 1.0)))
	if domain in ["site", "sites", "industrial"] and action == "start_campaign":
		var ir: Dictionary = MATH.game(p).get("feature_families", {}).get("industrial", {}).get("ir", {})
		if ir.get("program", {}) is Dictionary:
			ir["program"]["start_pending"] = false

static func coverage() -> Dictionary:
	var rows: Dictionary = {}
	var supported_ids: Array[String] = []
	var gap_ids: Array[String] = []
	for id in _feature_ids():
		var actions: Array = _exposed_actions(id)
		var implemented_actions: Array = _feature_actions().get(id, [])
		var supported := not implemented_actions.is_empty()
		for required_action in implemented_actions:
			if not actions.has(required_action):
				supported = false
				break
		var status := "supported" if supported else "gap"
		rows[id] = {"status":status, "supported":supported, "owner":"EarthIndustrialFeatures", "controls":supported, "mechanics":_mechanism(id), "actions":actions}
		if supported:
			supported_ids.append(id)
		else:
			gap_ids.append(id)
	return {"total":rows.size(), "supported":supported_ids.size(), "supported_ids":supported_ids, "gap_ids":gap_ids, "by_id":rows}

static func _exposed_actions(id: String) -> Array:
	var site_id := "site_earth_ir_9" if id.begins_with("IR") else "site_earth_pd_7"
	var p := {"sites":{site_id:{"unlocked":true}}, "game":{"progression":{"research":{}, "mastery":{}}}}
	var progression: Dictionary = MATH.game(p)["progression"]
	var catalog := "mastery" if id.contains("_SK") else "research"
	progression[catalog][id] = 1
	var actions: Array = []
	for operation in operations(p, id):
		var operation_actions := [str(operation.get("action", ""))]
		for operation_action in operation.get("actions", []):
			operation_actions.append(str(operation_action))
		for operation_action in operation_actions:
			if not operation_action.is_empty() and not actions.has(operation_action):
				actions.append(operation_action)
	return actions

static func _feature_actions() -> Dictionary:
	return {
		"PD05":["industry_select_lens"], "PD17":["industry_set_contract_profile"],
		"PD22":["industry_repeat_analysis"], "PD23":["industry_start_forecast"],
		"PD27":["industry_start_impurity_report"], "PD29":["industry_start_distant_analysis"],
		"PD_SK02":["industry_take_second_sample"], "PD_SK06":["industry_prepare_filter"],
		"IR05":["industry_start_deep_route"], "IR06":["industry_prepare_supports"],
		"IR14":["industry_prepare_contact_profile"], "IR16":["industry_start_autoprogram"],
		"IR17":["industry_start_contract_route"], "IR23":["industry_pause_ir", "industry_resume_ir"],
		"IR28":["industry_start_ancient_expedition"], "IR_SK05":["industry_prepare_manipulator"]
	}

static func lens_definitions(p: Dictionary) -> Array:
	if not _owned(p, "PD05"): return []
	return _config().get("pd", {}).get("extra_lenses", []).duplicate(true)

static func lens_definition(p: Dictionary, lens_id: String) -> Dictionary:
	for lens in lens_definitions(p):
		if str(lens.get("id", "")) == lens_id: return lens.duplicate(true)
	return {}

static func contract_lens_profile(p: Dictionary) -> Dictionary:
	if not _owned(p, "PD17"): return {}
	var pd: Dictionary = ensure(p).get("pd", {})
	var order_id := str(pd.get("contract_order_id", ""))
	var order := _active_order(p, order_id, "pd_concentrate")
	if order.is_empty() or pd.get("used_contract_orders", {}).has(order_id): return {}
	var need := int(order.get("items", {}).get("pd_concentrate", 0))
	if need <= 0: return {}
	var profile: Dictionary = _config().get("pd", {}).get("contract_profile", {})
	return {"order_id":order_id, "lens_id":str(profile.get("bulk_lens_id", "pd_lens_bulk")) if need >= int(profile.get("bulk_need_units", 8)) else str(profile.get("small_lens_id", "pd_lens_high_grade"))}

static func consume_contract_lens(p: Dictionary, order_id: String) -> void:
	var pd: Dictionary = ensure(p).get("pd", {})
	if str(pd.get("contract_order_id", "")) != order_id: return
	pd["used_contract_orders"][order_id] = true
	pd["contract_order_id"] = ""

static func pd_filter_profile(p: Dictionary) -> Dictionary:
	if not _owned(p, "PD_SK06"): return {}
	var pd: Dictionary = ensure(p).get("pd", {})
	if not bool(pd.get("filter_prepared", false)): return {}
	return _config().get("pd", {}).get("filter_prep", {}).duplicate(true)

static func consume_pd_filter_prep(p: Dictionary) -> void:
	var pd: Dictionary = ensure(p).get("pd", {})
	pd["filter_prepared"] = false

static func ir_campaign_profile(p: Dictionary, deep_requested: bool) -> Dictionary:
	var ir: Dictionary = ensure(p).get("ir", {})
	var cost_scale := 1.0
	var duration_scale := 1.0
	var deep := false
	if deep_requested:
		if not _owned(p, "IR05"): return {}
		var profile: Dictionary = _config().get("ir", {}).get("deep_route", {})
		cost_scale *= float(profile.get("cost_multiplier", 1.0))
		duration_scale *= float(profile.get("duration_multiplier", 1.0))
		deep = true
	var support_used := bool(ir.get("support_prepared", false)) and _owned(p, "IR06")
	if support_used:
		var support: Dictionary = _config().get("ir", {}).get("support_prep", {})
		cost_scale *= float(support.get("next_campaign_cost_multiplier", 1.0))
		duration_scale *= float(support.get("next_campaign_duration_multiplier", 1.0))
	var manipulator_used := bool(ir.get("manipulator_prepared", false)) and _owned(p, "IR_SK05")
	if manipulator_used:
		var manipulator: Dictionary = _config().get("ir", {}).get("manipulator_prep", {})
		cost_scale *= float(manipulator.get("next_campaign_cost_multiplier", 1.0))
		duration_scale *= float(manipulator.get("next_campaign_duration_multiplier", 1.0))
	return {"deep":deep, "cost_multiplier":cost_scale, "duration_multiplier":duration_scale, "consume_support":support_used, "consume_manipulator":manipulator_used}

static func consume_ir_preparations(p: Dictionary, profile: Dictionary) -> void:
	var ir: Dictionary = ensure(p).get("ir", {})
	if bool(profile.get("consume_support", false)): ir["support_prepared"] = false
	if bool(profile.get("consume_manipulator", false)): ir["manipulator_prepared"] = false

static func on_pd_industrial_analysis_completed(p: Dictionary, task_id: String, sample_seed: int) -> void:
	var pd: Dictionary = ensure(p).get("pd", {})
	var pending: Dictionary = pd.get("pending_analysis_task", {})
	if str(pending.get("task_id", "")) != task_id or pd.get("completed_tasks", {}).has(task_id): return
	var record := {"task_id":task_id, "sample_seed":sample_seed, "completed":true}
	pd["completed_tasks"][task_id] = record
	match task_id:
		"pd_impurity_report":
			var target_id := str(pending.get("target_id", ""))
			if not target_id.is_empty() and not pd["reports"].has(target_id):
				pd["reports"][target_id] = {"target_id":target_id, "sample_seed":sample_seed, "collected":true}
		"pd_distant_analysis":
			pd["distant_note"] = {"id":str(_config().pd.distant_analysis.note_id), "sample_seed":sample_seed, "collected":true}
			MATH.stat(p, "pd_distant_notes")
	pd["pending_analysis_task"] = {}

static func on_ir_campaign_completed(p: Dictionary, campaign: Dictionary) -> Dictionary:
	var ir: Dictionary = ensure(p).get("ir", {})
	var program: Dictionary = ir.get("program", {})
	if not bool(program.get("active", false)) or str(program.get("id", "")) != str(campaign.get("industrial_program_id", "")):
		return {}
	if int(program.get("current_seed", 0)) != int(campaign.get("seed", 0)):
		return {}
	program["current_seed"] = 0
	var spent := int(campaign.get("committed_cost_cents", 0)) + int(campaign.get("wage_cost_paid_cents", 0))
	program["spent_cents"] = int(program.get("spent_cents", 0)) + spent
	program["remaining_budget_cents"] = maxi(0, int(program.get("remaining_budget_cents", 0)) - spent)
	if int(_ir_extraction_state(p).get("pending_output", 0)) > 0:
		program["active"] = false
		ir["last_program_message"] = "Программа остановлена: склад хранит завершённый выпуск кампании"
		return {}
	if int(program.get("remaining_campaigns", 0)) <= 0:
		program["active"] = false
		ir["last_program_message"] = "Последовательная программа завершена"
		return {}
	var next_estimate := int(campaign.get("projected_cost_cents", 0))
	if next_estimate <= 0 or int(program.get("remaining_budget_cents", 0)) < next_estimate:
		program["active"] = false
		ir["last_program_message"] = "Программа остановлена у заданного бюджета"
		return {}
	program["remaining_campaigns"] = int(program.get("remaining_campaigns", 0)) - 1
	program["start_pending"] = true
	return {"continue":true, "strategy_id":str(program.get("strategy_id", "reliable"))}

static func recipe_profile(p: Dictionary, recipe_id: String) -> Dictionary:
	if not _owned(p, "IR14") or not _config().get("contact_assembly", {}).get("recipe_ids", []).has(recipe_id): return {}
	var profile_id := str(ensure(p).get("contact", {}).get("next_profile_id", ""))
	return _config().get("contact_assembly", {}).get("profiles", {}).get(profile_id, {}).duplicate(true) if not profile_id.is_empty() else {}

static func take_recipe_profile(p: Dictionary, recipe_id: String) -> Dictionary:
	var profile := recipe_profile(p, recipe_id)
	if profile.is_empty(): return {}
	profile["profile_id"] = str(ensure(p).get("contact", {}).get("next_profile_id", ""))
	profile["duration_multiplier"] = float(profile.get("duration_multiplier", 1.0))
	ensure(p).get("contact", {})["next_profile_id"] = ""
	return profile

static func program_status(p: Dictionary) -> Dictionary:
	return ensure(p).get("ir", {}).get("program", {}).duplicate(true)

static func _start_pd_side_analysis(p: Dictionary, pd: Dictionary, task_id: String, fee: int, duration: float, payload: Dictionary) -> Dictionary:
	if pd.get("completed_tasks", {}).has(task_id) or not Dictionary(pd.get("pending_analysis_task", {})).is_empty(): return MATH.fail("Этот анализ уже выполняется или завершён")
	var view := _site_view(p, "pd")
	var sample: Dictionary = view.get("sample", {})
	if str(view.get("status", "")) != "ready" or sample.is_empty(): return MATH.fail("Для дополнительного анализа нужна готовая проба")
	if task_id == "pd_repeat_analysis" and not bool(sample.get("analysis_completed", false)): return MATH.fail("Сначала выполните первичный анализ керна")
	if task_id == "pd_impurity_report" and not bool(sample.get("analysis_completed", false)): return MATH.fail("Коллекционный отчёт требует завершённого первичного анализа")
	if not _pay(p, fee): return MATH.fail("Недостаточно кредитов для дополнительного анализа")
	var pending := {"task_id":task_id, "target_id":str(payload.get("target_id", "")), "fee_paid":true}
	pd["pending_analysis_task"] = pending
	var result := _site_act(p, "pd_industrial_analysis", {"site":"pd", "task_id":task_id, "duration_s":duration})
	if not bool(result.get("ok", false)):
		p["money_cents"] = int(p.get("money_cents", 0)) + fee
		pd["pending_analysis_task"] = {}
	return result

static func authorize_pd_analysis_task(p: Dictionary, task_id: String) -> bool:
	var required_id: String = str({"pd_repeat_analysis":"PD22", "pd_impurity_report":"PD27", "pd_distant_analysis":"PD29"}.get(task_id, ""))
	var pending: Dictionary = ensure(p).get("pd", {}).get("pending_analysis_task", {})
	return not required_id.is_empty() and _owned(p, required_id) and MATH.unlocked(p, "pd") and str(pending.get("task_id", "")) == task_id and bool(pending.get("fee_paid", false))

static func _start_pd_second_sample(p: Dictionary, pd: Dictionary) -> Dictionary:
	var cfg: Dictionary = _config().get("pd", {}).get("second_sample", {})
	if pd.get("completed_tasks", {}).has("pd_second_sample") or not Dictionary(pd.get("second_sample_task", {})).is_empty(): return MATH.fail("Дополнительная проба уже выполняется или завершена")
	var view := _site_view(p, "pd")
	var sample: Dictionary = view.get("sample", {})
	if str(view.get("status", "")) != "ready" or sample.is_empty() or bool(sample.get("analysis_completed", false)): return MATH.fail("Вторую пробу можно запросить до фиксации готового образца")
	if not _pay(p, int(cfg.get("fee_cents", 0))): return MATH.fail("Недостаточно кредитов для второй пробы")
	var lens: Dictionary = view.get("lens", {})
	var rng := RandomNumberGenerator.new()
	rng.seed = int(sample.get("seed", 0)) + 104729
	var preview := {
		"lens_id":str(sample.get("lens_id", "")), "sample_number":2, "forecast_only":true,
		"seed_reference":int(sample.get("seed", 0)),
		"quality":rng.randf_range(float(lens.get("quality_min", 0.0)), float(lens.get("quality_max", 0.0))),
		"yield_units":rng.randi_range(int(lens.get("yield_min", 0)), int(lens.get("yield_max", 0))),
	}
	pd["second_sample_task"] = _new_job("pd_second_sample", float(cfg.get("duration_s", 0.0)))
	pd["second_sample_task"]["preview"] = preview
	pd["second_sample_task"]["seed_reference"] = int(sample.get("seed", 0))
	return MATH.ok("Вторая проба оплачена; результат появится до запуска концентрации и не изменит текущую пробу")

static func _start_forecast(p: Dictionary, pd: Dictionary, args: Dictionary) -> Dictionary:
	var cfg: Dictionary = _config().get("pd", {}).get("forecast", {})
	var line_id := str(args.get("line_id", ""))
	var index := int(line_id)
	var lines: Dictionary = pd.get("forecast_lines", {})
	if index < 0 or index >= int(cfg.get("max_lines", 2)) or not lines.has(line_id): return MATH.fail("Выберите прогнозную линию")
	var target_id := str(args.get("target_id", ""))
	if not _target_exists(cfg.get("targets", []), target_id): return MATH.fail("Выберите цель прогноза")
	if str(lines[line_id].get("status", "")) == "running": return MATH.fail("Эта линия уже выполняет прогноз")
	var capacity := int(cfg.get("base_capacity", 1)) + int(cfg.get("capacity_per_georadar", 1)) * int(MATH.site(p, "pd").get("machines", {}).get("pd_georadar", 0))
	var active := 0
	for row in lines.values():
		if str(row.get("status", "")) == "running": active += 1
	if active >= capacity: return MATH.fail("Все реальные георадарные мощности уже заняты")
	var fee := int(cfg.get("fee_cents", 0))
	if not _pay(p, fee): return MATH.fail("Недостаточно кредитов для прогноза")
	lines[line_id] = _new_job("forecast", float(cfg.get("duration_s", 0.0)))
	lines[line_id]["target_id"] = target_id
	return MATH.ok("Прогноз оплачен и занимает георадарную мощность; выпуск не создаётся")

static func _start_autoprogram(p: Dictionary, ir: Dictionary, args: Dictionary) -> Dictionary:
	if bool(ir.get("program", {}).get("active", false)): return MATH.fail("Последовательная программа уже запущена")
	if not _ir_idle_for_prep(p): return MATH.fail("Автопрограмма запускается только между кампаниями")
	var cfg: Dictionary = _config().get("ir", {}).get("safe_program", {})
	var count := int(args.get("campaign_count", 0))
	var budget := int(args.get("budget_cents", 0))
	var strategy := str(args.get("strategy_id", ""))
	if count < 1 or count > int(cfg.get("max_campaigns", 1)) or not cfg.get("safe_strategies", []).has(strategy) or budget <= 0 or budget > int(p.get("money_cents", 0)):
		return MATH.fail("Количество, безопасная стратегия или общий бюджет вне допустимого диапазона")
	var view := _site_view(p, "ir")
	var projected := int(view.get("projection", {}).get("cost_cents", 0))
	if projected <= 0 or projected * count > budget: return MATH.fail("Бюджета недостаточно для полного прогнозного объёма кампаний")
	var program_id := "ir_program_%d" % (int(ir.get("program", {}).get("sequence", 0)) + 1)
	ir["program"] = {"id":program_id, "sequence":int(ir.get("program", {}).get("sequence", 0)) + 1, "active":true, "start_pending":true, "strategy_id":strategy, "remaining_campaigns":count - 1, "remaining_budget_cents":budget, "spent_cents":0, "current_seed":0}
	var result := _site_act(p, "start_campaign", {"site":"ir", "strategy_id":strategy})
	if not bool(result.get("ok", false)):
		ir["program"]["active"] = false
		ir["program"]["start_pending"] = false
	return result

static func _start_contract_route(p: Dictionary, args: Dictionary) -> Dictionary:
	var order_id := str(args.get("order_id", ""))
	var order := _active_order(p, order_id, "ir_core")
	if order.is_empty(): return MATH.fail("Нужен активный принятый заказ на Ir-ядра")
	var need := int(order.get("items", {}).get("ir_core", 0))
	if need <= 0: return MATH.fail("У принятого заказа нет фактического спроса на Ir-ядра")
	var route: Dictionary = _config().get("ir", {}).get("contract_route", {})
	var strategy := str(route.get("large_order_strategy", "reliable")) if need >= int(route.get("large_order_units", 8)) else str(route.get("small_order_strategy", "economic"))
	return _site_act(p, "start_campaign", {"site":"ir", "strategy_id":strategy, "contract_order_id":order_id})

static func _ir_idle_for_prep(p: Dictionary) -> bool:
	var status := str(_site_view(p, "ir").get("status", ""))
	return not status in ["running", "waiting_funds", "waiting_storage", "paused"]

static func _active_order(p: Dictionary, order_id: String, item_id: String) -> Dictionary:
	if order_id.is_empty(): return {}
	var active: Dictionary = MATH.game(p).get("progression", {}).get("contracts", {}).get("active", {})
	var order: Dictionary = active.get(order_id, {})
	if str(order.get("status", "")) != "accepted" or int(order.get("items", {}).get(item_id, 0)) <= 0: return {}
	return order

static func _contract_choices(p: Dictionary, item_id: String) -> Array:
	var result: Array = []
	var active: Dictionary = MATH.game(p).get("progression", {}).get("contracts", {}).get("active", {})
	for order_id in active:
		var order: Dictionary = active[order_id]
		if str(order.get("status", "")) == "accepted" and int(order.get("items", {}).get(item_id, 0)) > 0:
			result.append({"id":str(order_id), "label":"%s — %d" % [str(order.get("contract_id", order_id)), int(order["items"][item_id])]})
	return result

static func _owned(p: Dictionary, id: String) -> bool:
	var progression: Dictionary = MATH.game(p).get("progression", {})
	var catalog := "mastery" if id.contains("_SK") else "research"
	return int(progression.get(catalog, {}).get(id, 0)) > 0

static func _feature_ids() -> Array:
	return ["PD05", "PD17", "PD22", "PD23", "PD27", "PD29", "PD_SK02", "PD_SK06", "IR05", "IR06", "IR14", "IR16", "IR17", "IR23", "IR28", "IR_SK05"]

static func _mechanism(id: String) -> String:
	return {
		"PD05":"extra_optional_lens", "PD17":"accepted_contract_next_lens", "PD22":"paid_second_analysis", "PD23":"shared_georadar_forecast_capacity", "PD27":"paid_impurity_analysis_report", "PD29":"paid_distant_analysis_note", "PD_SK02":"paid_second_sample_preview_before_concentration", "PD_SK06":"paid_manual_filter_prep_next_cycle", "IR05":"paid_deep_campaign_route", "IR06":"paid_timed_support_prep", "IR14":"one_real_contact_job_duration_profile", "IR16":"budgeted_sequential_safe_campaigns", "IR17":"accepted_contract_route", "IR23":"paid_phase_pause_resume", "IR28":"paid_timed_ancient_report", "IR_SK05":"paid_timed_one_campaign_manipulator_prep"
	}.get(id, "")

static func _site_act(p: Dictionary, action: String, args: Dictionary) -> Dictionary:
	var model: Variant = load(SITE_MODEL_PATH)
	return model.callv("act", [p, action, args]) if model != null else MATH.fail("Модель участков недоступна")

static func _site_view(p: Dictionary, site: String) -> Dictionary:
	var model: Variant = load(SITE_MODEL_PATH)
	return model.callv("view", [p, site]) if model != null else {}

static func _ir_extraction_state(p: Dictionary) -> Dictionary:
	return MATH.game(p).get("extraction", {}).get("ir", {})

static func _pay(p: Dictionary, cents: int) -> bool:
	return cents >= 0 and MATH.pay(p, cents)

static func _new_job(kind: String, duration: float) -> Dictionary:
	return {"kind":kind, "status":"running", "remaining_s":maxf(0.0, duration)}

static func _tick_job(job: Dictionary, dt: float) -> void:
	if str(job.get("status", "")) != "running": return
	job["remaining_s"] = maxf(0.0, float(job.get("remaining_s", 0.0)) - dt)
	if float(job["remaining_s"]) <= 0.0: job["status"] = "complete"

static func _job_eta(job: Variant) -> float:
	if not job is Dictionary or str(job.get("status", "")) != "running": return NO_EVENT
	return maxf(0.0, float(job.get("remaining_s", 0.0)))

static func _ensure_fields(state: Dictionary, defaults: Dictionary) -> void:
	for key in defaults:
		if not state.has(key) or typeof(state[key]) != typeof(defaults[key]): state[key] = defaults[key].duplicate(true) if defaults[key] is Dictionary or defaults[key] is Array else defaults[key]

static func _target_exists(targets: Array, target_id: String) -> bool:
	for row in targets:
		if str(row.get("id", "")) == target_id: return true
	return false

static func _named_choices(rows: Array) -> Array:
	var choices: Array = []
	for row in rows:
		choices.append({"id":str(row.get("id", "")), "label":str(row.get("label", row.get("name", row.get("id", ""))))})
	return choices

static func _line_choices(max_lines: int) -> Array:
	var choices: Array = []
	for index in range(maxi(0, max_lines)):
		choices.append({"id":str(index), "label":"Линия %d" % (index + 1)})
	return choices

static func _safe_strategy(id: String) -> bool:
	return _config().get("ir", {}).get("safe_program", {}).get("safe_strategies", []).has(id)

static func _safe_strategy_choices() -> Array:
	var choices: Array = []
	for strategy in _config().get("ir", {}).get("safe_program", {}).get("safe_strategies", []):
		choices.append({"id":str(strategy), "label":"Надёжная" if str(strategy) == "reliable" else "Экономная"})
	return choices

static func _contact_profile_choices() -> Array:
	var choices: Array = []
	for id in _config().get("contact_assembly", {}).get("profiles", {}):
		choices.append({"id":str(id), "label":str(_config().contact_assembly.profiles[id].get("label", id))})
	return choices

static func _config() -> Dictionary:
	if not _config_cache.is_empty(): return _config_cache
	if not FileAccess.file_exists(CONFIG_PATH): return {}
	var file := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if file == null: return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary: _config_cache = parsed
	return _config_cache
