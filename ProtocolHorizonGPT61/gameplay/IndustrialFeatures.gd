class_name EarthIndustrialFeatures
extends RefCounted

const CONFIG_PATH := "res://data/proposals/industrial_features.json"
const SITE_MODEL_PATH := "res://gameplay/SiteModel.gd"
const MATH := preload("res://gameplay/GameMath.gd")
const ECONOMY_PATH := "res://gameplay/EconomyModel.gd"
const IR_SK07_RESERVE_TOKEN := "mastery:IR_SK07:priority_cleanup"
const IR_SK08_RESERVE_TOKEN := "mastery:IR_SK08:pd_fe_plan"
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
	_ensure_fields(pd, {"contract_order_id":"", "used_contract_orders":{}, "pending_analysis_task":{}, "completed_tasks":{}, "reports":{}, "distant_note":{}, "second_sample_task":{}, "second_sample_preview":{}, "filter_task":{}, "filter_prepared":false, "selected_lens_automatic":false, "one_shot_clean_order_id":"", "forecast_lines":{}})
	_ensure_fields(ir, {"support_task":{}, "support_prepared":false, "manipulator_task":{}, "manipulator_prepared":false, "cooling_mode_id":"", "guaranteed_detour_enabled":false, "fast_cleanup_enabled":false, "expedition":{}, "program":{}, "last_program_message":""})
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
		"industry_set_selected_lens_automation":
			if id != "PD18": return MATH.fail("Действие относится к другому узлу")
			if typeof(args.get("enabled", null)) != TYPE_BOOL: return MATH.fail("Укажите состояние автозапуска выбранной линзы")
			return _site_act(p, "set_selected_lens_automatic", {"site":"pd", "enabled":args["enabled"]})
		"industry_set_contract_profile":
			var order_id := str(args.get("order_id", ""))
			if not _active_order(p, order_id, "pd_concentrate"): return MATH.fail("Нужен активный принятый контракт с фактическим спросом на концентрат палладия")
			pd["contract_order_id"] = order_id
			return MATH.ok("Профиль будет применён только к следующему отбору под этот контракт")
		"industry_analyze_spectrum":
			if id != "PD_SK05": return MATH.fail("Действие относится к другому узлу")
			var band_id := str(args.get("spectral_band_id", ""))
			if not _pd_spectral_band_exists(p, band_id): return MATH.fail("Выберите один из двух диапазонов этой пробы")
			return _site_act(p, "analyze_sample", {"site":"pd", "spectral_band_id":band_id})
		"industry_express_analysis":
			if id != "PD_SK07": return MATH.fail("Действие относится к другому узлу")
			var band_id := str(args.get("spectral_band_id", ""))
			if not _pd_spectral_band_exists(p, band_id): return MATH.fail("Выберите один из двух диапазонов этой пробы")
			return _site_act(p, "analyze_sample", {"site":"pd", "spectral_band_id":band_id, "express_analysis":true})
		"industry_start_pd_contract_clean_plan":
			if id != "PD_SK08": return MATH.fail("Действие относится к другому узлу")
			return _start_pd_contract_clean_plan(p, pd, str(args.get("order_id", "")))
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
		"industry_set_cooling_mode":
			if id != "IR_SK06": return MATH.fail("Действие относится к другому узлу")
			if not _ir_idle_for_prep(p): return MATH.fail("Контур охлаждения можно менять только до начала кампании")
			var mode_id := str(args.get("cooling_mode_id", ""))
			var modes: Dictionary = _config().get("ir", {}).get("cooling_modes", {})
			if not modes.has(mode_id): return MATH.fail("Выберите известный контур охлаждения")
			ir["cooling_mode_id"] = mode_id
			return MATH.ok("Контур охлаждения выбран; стоимость, время и температура учтены в прогнозе")
		"industry_set_guaranteed_detour":
			if id != "IR22": return MATH.fail("Действие относится к другому узлу")
			if typeof(args.get("enabled", null)) != TYPE_BOOL: return MATH.fail("Укажите, включать ли гарантированный обходной маршрут")
			if not _ir_idle_for_prep(p): return MATH.fail("Обходной маршрут можно выбрать только до кампании")
			ir["guaranteed_detour_enabled"] = args["enabled"]
			return MATH.ok("Вариант маршрута сохранён; прогноз показывает цену, время и гарантированный минимум выхода")
		"industry_set_fast_cleanup":
			if id != "IR27": return MATH.fail("Действие относится к другому узлу")
			if typeof(args.get("enabled", null)) != TYPE_BOOL: return MATH.fail("Укажите, включать ли быстрый режим очистки")
			if not _ir_idle_for_prep(p): return MATH.fail("Режим очистки можно выбрать только до кампании")
			ir["fast_cleanup_enabled"] = args["enabled"]
			return MATH.ok("Режим очистки сохранён; прогноз учитывает сокращённую фазу и меньший выход")
		"industry_configure_unstarted_ir_phase":
			if id != "IR_SK04": return MATH.fail("Действие относится к другому узлу")
			return _site_act(p, "configure_unstarted_phase", {"phase_index":int(args.get("phase_index", -1)), "phase_mode_id":str(args.get("phase_mode_id", ""))})
		"industry_reserve_ir_core_for_cleanup":
			if id != "IR_SK07": return MATH.fail("Действие относится к другому узлу")
			return _reserve_ir_cleanup_core(p)
		"industry_release_ir_core_cleanup_reserve":
			if id != "IR_SK07": return MATH.fail("Действие относится к другому узлу")
			return _release_reservation(p, IR_SK07_RESERVE_TOKEN)
		"industry_plan_ir_contact_and_reserves":
			if id != "IR_SK08": return MATH.fail("Действие относится к другому узлу")
			return _plan_ir_contact_and_reserves(p, ir, args)
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
		"PD18": return [{"action":"industry_set_selected_lens_automation", "title":"Автоматически использовать выбранную известную линзу", "fields":[{"key":"enabled", "label":"Автоматизация выбранной линзы", "type":"toggle"}]}]
		"PD17": return [{"action":"industry_set_contract_profile", "title":"Профиль следующего отбора по принятому контракту", "fields":[{"key":"order_id", "label":"Активный контракт на Pd-концентрат", "type":"select", "choices":_contract_choices(p, "pd_concentrate")}]}]
		"PD22": return [{"action":"industry_repeat_analysis", "title":"Оплатить и провести повторный анализ керна", "fields":[]}]
		"PD23": return [{"action":"industry_start_forecast", "title":"Запустить прогнозную линию георадара", "fields":[{"key":"line_id", "label":"Линия прогноза", "type":"select", "choices":_line_choices(int(cfg.pd.forecast.max_lines))}, {"key":"target_id", "label":"Геологическая цель", "type":"select", "choices":_named_choices(cfg.pd.forecast.targets)}]}]
		"PD27": return [{"action":"industry_start_impurity_report", "title":"Провести анализ для коллекционного отчёта", "fields":[{"key":"target_id", "label":"Тип примесей", "type":"select", "choices":_named_choices(cfg.pd.impurity_report.targets)}]}]
		"PD29": return [{"action":"industry_start_distant_analysis", "title":"Оплатить дальний участок анализа", "fields":[]}]
		"PD_SK02": return [{"action":"industry_take_second_sample", "title":"Снять дополнительный предварительный образец", "fields":[]}]
		"PD_SK06": return [{"action":"industry_prepare_filter", "title":"Вручную подготовить фильтр к следующей партии", "fields":[]}]
		"PD_SK05": return [{"action":"industry_analyze_spectrum", "title":"Выбрать спектральный диапазон пробы", "fields":[{"key":"spectral_band_id", "label":"Диапазон спектра", "type":"select", "choices":_pd_spectral_choices(p)}]}]
		"PD_SK07": return [{"action":"industry_express_analysis", "title":"Провести экспресс-анализ пробы", "fields":[{"key":"spectral_band_id", "label":"Диапазон спектра", "type":"select", "choices":_pd_spectral_choices(p)}]}]
		"PD_SK08": return [{"action":"industry_start_pd_contract_clean_plan", "title":"Запустить один цикл по принятому Pd-контракту", "fields":[{"key":"order_id", "label":"Принятый контракт на Pd-концентрат", "type":"select", "choices":_contract_choices(p, "pd_concentrate")}]}]
		"IR05": return [{"action":"industry_start_deep_route", "title":"Начать дорогой глубинный маршрут", "fields":[{"key":"strategy_id", "label":"Безопасная стратегия", "type":"select", "choices":_safe_strategy_choices()}]}]
		"IR_SK06": return [{"action":"industry_set_cooling_mode", "title":"Выбрать контур охлаждения для следующих кампаний", "fields":[{"key":"cooling_mode_id", "label":"Контур охлаждения", "type":"select", "choices":_cooling_mode_choices()}]}]
		"IR22": return [{"action":"industry_set_guaranteed_detour", "title":"Включить гарантированный обходной маршрут для следующей кампании", "fields":[{"key":"enabled", "label":"Обходной маршрут", "type":"toggle"}]}]
		"IR27": return [{"action":"industry_set_fast_cleanup", "title":"Включить быстрый режим очистки для следующей кампании", "fields":[{"key":"enabled", "label":"Быстрая очистка", "type":"toggle"}]}]
		"IR_SK04": return [{"action":"industry_configure_unstarted_ir_phase", "title":"Изменить только ещё не начатую фазу", "fields":[{"key":"phase_index", "label":"Фаза кампании", "type":"select", "choices":_ir_phase_choices()}, {"key":"phase_mode_id", "label":"Режим фазы", "type":"select", "choices":_ir_phase_mode_choices()}]}]
		"IR_SK07": return [{"action":"industry_reserve_ir_core_for_cleanup", "title":"Зарезервировать одно реальное Ir-ядро для очистки", "fields":[]}, {"action":"industry_release_ir_core_cleanup_reserve", "title":"Снять резерв очистки Ir-ядра", "fields":[]}]
		"IR_SK08": return [{"action":"industry_plan_ir_contact_and_reserves", "title":"Выбрать маршрут, поставить контакт и зарезервировать Pd/Fe", "fields":[{"key":"strategy_id", "label":"Маршрут следующей кампании", "type":"select", "choices":_safe_strategy_choices()}, {"key":"line", "label":"Линия контактов", "type":"number", "min":0, "max":4}, {"key":"contact_count", "label":"Число реальных контактов", "type":"number", "min":1, "max":5}, {"key":"pd_reserve", "label":"Резерв свободного Pd-концентрата", "type":"number", "min":0, "max":_free_resource(p, "pd_concentrate")}, {"key":"fe_reserve", "label":"Резерв свободной железной руды", "type":"number", "min":0, "max":_free_resource(p, "iron_ore")}]}]
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
		_apply_contact_profile(p, int(result.get("line", -1)), -1)
	elif domain == "research" and action == "queue_recipe_chain":
		var jobs: Array = result.get("jobs", [])
		var line_index := int(result.get("line", -1))
		var factory: Array = MATH.game(p).get("factory", [])
		if line_index >= 0 and line_index < factory.size():
			var queue: Array = factory[line_index].get("queue", [])
			var start := maxi(0, queue.size() - jobs.size())
			for index in jobs.size():
				if str(jobs[index].get("recipe", "")) == "R_IR_CONTACT":
					_apply_contact_profile(p, line_index, start + index)
					break
	if domain in ["site", "sites", "industrial"] and action == "start_campaign":
		var ir: Dictionary = MATH.game(p).get("feature_families", {}).get("industrial", {}).get("ir", {})
		if ir.get("program", {}) is Dictionary:
			ir["program"]["start_pending"] = false

static func _apply_contact_profile(p: Dictionary, line_index: int, queue_index: int) -> void:
	var factory: Array = MATH.game(p).get("factory", [])
	if line_index < 0 or line_index >= factory.size():
		return
	var queue: Array = factory[line_index].get("queue", [])
	if queue.is_empty():
		return
	var index := queue.size() - 1 if queue_index < 0 else queue_index
	if index < 0 or index >= queue.size():
		return
	var job: Dictionary = queue[index]
	if str(job.get("recipe_id", "")) != "R_IR_CONTACT":
		return
	var profile := take_recipe_profile(p, "R_IR_CONTACT")
	if profile.is_empty():
		return
	job["industrial_profile_id"] = str(profile.get("profile_id", ""))
	job["seconds_per_unit"] = maxf(1.0, float(job.get("seconds_per_unit", 1.0)) * float(profile.get("duration_multiplier", 1.0)))

static func coverage() -> Dictionary:
	var rows: Dictionary = {}
	var supported_ids: Array[String] = []
	var gap_ids: Array[String] = []
	for id in _feature_ids():
		var actions: Array = _exposed_actions(id)
		var implemented_actions: Array = _feature_actions().get(id, [])
		var supported := not implemented_actions.is_empty() or id in _readout_ids()
		for required_action in implemented_actions:
			if not actions.has(required_action):
				supported = false
				break
		var status := "supported" if supported else "gap"
		rows[id] = {"status":status, "supported":supported, "owner":"EarthIndustrialFeatures", "controls":not implemented_actions.is_empty() and supported, "mechanics":_mechanism(id), "readout_only":id in _readout_ids(), "actions":actions}
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
		"PD05":["industry_select_lens"], "PD17":["industry_set_contract_profile"], "PD18":["industry_set_selected_lens_automation"],
		"PD22":["industry_repeat_analysis"], "PD23":["industry_start_forecast"],
		"PD27":["industry_start_impurity_report"], "PD29":["industry_start_distant_analysis"],
		"PD_SK02":["industry_take_second_sample"], "PD_SK05":["industry_analyze_spectrum"], "PD_SK06":["industry_prepare_filter"],
		"PD_SK07":["industry_express_analysis"], "PD_SK08":["industry_start_pd_contract_clean_plan"],
		"IR05":["industry_start_deep_route"], "IR06":["industry_prepare_supports"],
		"IR14":["industry_prepare_contact_profile"], "IR16":["industry_start_autoprogram"],
		"IR17":["industry_start_contract_route"], "IR23":["industry_pause_ir", "industry_resume_ir"],
		"IR22":["industry_set_guaranteed_detour"], "IR27":["industry_set_fast_cleanup"],
		"IR28":["industry_start_ancient_expedition"], "IR_SK04":["industry_configure_unstarted_ir_phase"],
		"IR_SK05":["industry_prepare_manipulator"], "IR_SK06":["industry_set_cooling_mode"],
		"IR_SK07":["industry_reserve_ir_core_for_cleanup", "industry_release_ir_core_cleanup_reserve"],
		"IR_SK08":["industry_plan_ir_contact_and_reserves"]
	}

static func _cooling_mode_choices() -> Array:
	var choices: Array = []
	var modes: Dictionary = _config().get("ir", {}).get("cooling_modes", {})
	for mode_id in modes:
		choices.append({"id":str(mode_id), "label":str(modes[mode_id].get("label", mode_id))})
	return choices

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
	var cooling_mode := ir_cooling_profile(p)
	var deep := false
	var detour: Dictionary = _config().get("ir", {}).get("guaranteed_detour", {}) if bool(ir.get("guaranteed_detour_enabled", false)) and _owned(p, "IR22") else {}
	var cleanup: Dictionary = _config().get("ir", {}).get("fast_cleanup", {}) if bool(ir.get("fast_cleanup_enabled", false)) and _owned(p, "IR27") else {}
	if not detour.is_empty():
		cost_scale *= float(detour.get("cost_multiplier", 1.0))
		duration_scale *= float(detour.get("duration_multiplier", 1.0))
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
	if not cooling_mode.is_empty():
		cost_scale *= float(cooling_mode.get("cost_multiplier", 1.0))
		duration_scale *= float(cooling_mode.get("duration_multiplier", 1.0))
	return {"deep":deep, "cost_multiplier":cost_scale, "duration_multiplier":duration_scale, "cooling_mode_id":str(cooling_mode.get("id", "")), "cooling_rate_multiplier":float(cooling_mode.get("cooling_rate_multiplier", 1.0)), "guaranteed_output_floor_units":int(detour.get("minimum_output_units", 0)), "cleanup_yield_multiplier":float(cleanup.get("yield_multiplier", 1.0)), "cleanup_duration_multiplier":float(cleanup.get("cleanup_duration_multiplier", 1.0)), "guaranteed_detour":not detour.is_empty(), "fast_cleanup":not cleanup.is_empty(), "consume_support":support_used, "consume_manipulator":manipulator_used}

static func ir_cooling_profile(p: Dictionary) -> Dictionary:
	if not _owned(p, "IR_SK06"):
		return {}
	var mode_id := str(ensure(p).get("ir", {}).get("cooling_mode_id", ""))
	var mode: Dictionary = _config().get("ir", {}).get("cooling_modes", {}).get(mode_id, {})
	if mode.is_empty():
		return {}
	var profile := mode.duplicate(true)
	profile["id"] = mode_id
	return profile

static func pd_selected_auto_lens_id(p: Dictionary) -> String:
	if not _owned(p, "PD18"):
		return ""
	var pd: Dictionary = ensure(p).get("pd", {})
	if not bool(pd.get("selected_lens_automatic", false)):
		return ""
	var extraction: Dictionary = MATH.game(p).get("extraction", {})
	return str(extraction.get("pd", {}).get("lens_id", ""))

static func set_pd_selected_lens_automatic(p: Dictionary, enabled: bool) -> void:
	var pd: Dictionary = ensure(p).get("pd", {})
	pd["selected_lens_automatic"] = enabled

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

static func _pd_spectral_choices(p: Dictionary) -> Array:
	var sample: Dictionary = _site_view(p, "pd").get("sample", {})
	var profile: Dictionary = sample.get("spectral_profile", {})
	var choices: Array = []
	for row in profile.get("bands", []):
		choices.append({"id":str(row.get("id", "")), "label":"%s · %s" % [str(row.get("label", "Диапазон")), str(row.get("intensity", ""))]})
	return choices

static func _pd_spectral_band_exists(p: Dictionary, band_id: String) -> bool:
	for row in _pd_spectral_choices(p):
		if str(row.get("id", "")) == band_id:
			return true
	return false

static func _pd_lens_record(p: Dictionary, lens_id: String) -> Dictionary:
	var model: Variant = load(SITE_MODEL_PATH)
	if model == null:
		return {}
	for row in model.call("lens_definitions"):
		if str(row.get("id", "")) == lens_id:
			return row.duplicate(true)
	for row in lens_definitions(p):
		if str(row.get("id", "")) == lens_id:
			return row.duplicate(true)
	return {}

static func _start_pd_contract_clean_plan(p: Dictionary, pd: Dictionary, order_id: String) -> Dictionary:
	var order := _active_order(p, order_id, "pd_concentrate")
	if order.is_empty():
		return MATH.fail("Нужен активный принятый контракт на Pd-концентрат")
	var view := _site_view(p, "pd")
	if not str(view.get("status", "")) in ["idle", "completed", "cancelled"] or not Dictionary(view.get("sample", {})).is_empty():
		return MATH.fail("Одноцикловый контрактный план не заменяет активную или готовую пробу")
	if int(view.get("pending_output", 0)) > 0 or MATH.stored(p) >= MATH.capacity(p):
		return MATH.fail("Освободите место в реальном хранилище перед запуском")
	var cfg: Dictionary = _config().get("pd", {}).get("contract_clean_plan", {})
	var need := int(order.get("items", {}).get("pd_concentrate", 0))
	var lens_id := str(cfg.get("bulk_lens_id", "pd_lens_bulk")) if need >= int(cfg.get("bulk_need_units", 8)) else str(cfg.get("small_lens_id", "pd_lens_high_grade"))
	var lens := _pd_lens_record(p, lens_id)
	if lens.is_empty() or MATH.available_money(p) < int(lens.get("sample_cost_cents", 0)):
		return MATH.fail("Недостаточно кредитов для реального отбора по выбранной линзе")
	var old_order_id := str(pd.get("contract_order_id", ""))
	var old_lens_id := str(view.get("lens_id", ""))
	pd["contract_order_id"] = order_id
	var selected := _site_act(p, "select_lens", {"site":"pd", "lens_id":lens_id})
	if not bool(selected.get("ok", false)):
		pd["contract_order_id"] = old_order_id
		return selected
	var started := _site_act(p, "take_sample", {"site":"pd"})
	if not bool(started.get("ok", false)):
		pd["contract_order_id"] = old_order_id
		if not old_lens_id.is_empty(): _site_act(p, "select_lens", {"site":"pd", "lens_id":old_lens_id})
		return started
	var site_state: Dictionary = MATH.game(p).get("extraction", {}).get("pd", {})
	site_state["automatic"] = true
	site_state["one_shot_contract_clean"] = true
	pd["one_shot_clean_order_id"] = order_id
	return {"ok":true, "message":"Запущен один реальный отбор и цикл концентрации под принятый контракт", "order_id":order_id, "lens_id":lens_id, "one_batch":true}

static func _reserve_ir_cleanup_core(p: Dictionary) -> Dictionary:
	var reservations: Dictionary = MATH.game(p).get("reservations", {})
	if reservations.has(IR_SK07_RESERVE_TOKEN):
		return MATH.fail("Ядро для приоритетной очистки уже зарезервировано")
	if MATH.free_amount(p, "ir_core") < 1:
		return MATH.fail("Нужно одно свободное реальное Ir-ядро")
	var economy: Variant = load(ECONOMY_PATH)
	return economy.call("act", p, "reserve", {"token":IR_SK07_RESERVE_TOKEN, "items":{"ir_core":1}})

static func _release_reservation(p: Dictionary, token: String) -> Dictionary:
	var economy: Variant = load(ECONOMY_PATH)
	return economy.call("act", p, "unreserve", {"token":token})

static func _plan_ir_contact_and_reserves(p: Dictionary, ir: Dictionary, args: Dictionary) -> Dictionary:
	if not _ir_idle_for_prep(p):
		return MATH.fail("Планирование доступно только до начала следующей Ir-кампании")
	var strategy_id := str(args.get("strategy_id", ""))
	if not _safe_strategy(strategy_id):
		return MATH.fail("Выберите одну из существующих безопасных стратегий")
	var line_index := int(args.get("line", -1))
	var contact_count := int(args.get("contact_count", 0))
	var pd_amount := int(args.get("pd_reserve", 0))
	var fe_amount := int(args.get("fe_reserve", 0))
	if line_index < 0 or line_index >= 5 or contact_count < 1 or contact_count > 5 or pd_amount < 0 or fe_amount < 0:
		return MATH.fail("Линия, число контактов или резерв вне допустимого диапазона")
	if pd_amount > MATH.free_amount(p, "pd_concentrate") or fe_amount > MATH.free_amount(p, "iron_ore"):
		return MATH.fail("Резерв превышает свободные реальные запасы Pd/Fe")
	var reservations: Dictionary = MATH.game(p).get("reservations", {})
	if reservations.has(IR_SK08_RESERVE_TOKEN):
		return MATH.fail("Сначала снимите резерв предыдущего плана IR_SK08")
	var economy: Variant = load(ECONOMY_PATH)
	var quote: Dictionary = economy.call("quote", p, "ir", "recipe", "R_IR_CONTACT", contact_count)
	if not bool(quote.get("ok", false)):
		return MATH.fail(str(quote.get("message", "Реальный рецепт контактов недоступен")))
	var factory: Array = MATH.game(p).get("factory", [])
	var queued_units := 0
	if line_index >= factory.size(): return MATH.fail("Линия производства недоступна")
	var selected_line: Dictionary = factory[line_index]
	queued_units += int(selected_line.get("active", {}).get("units_remaining", 0))
	for job in selected_line.get("queue", []): queued_units += int(job.get("units_remaining", 0))
	if queued_units + contact_count > 500: return MATH.fail("В выбранной линии недостаточно места")
	var old_strategy := str(_site_view(p, "ir").get("strategy_id", "reliable"))
	var route_result := _site_act(p, "set_strategy", {"site":"ir", "strategy_id":strategy_id})
	if not bool(route_result.get("ok", false)): return route_result
	var reserved := false
	if pd_amount > 0 or fe_amount > 0:
		var reserve_items := {}
		if pd_amount > 0: reserve_items["pd_concentrate"] = pd_amount
		if fe_amount > 0: reserve_items["iron_ore"] = fe_amount
		var reserve_result: Dictionary = economy.call("act", p, "reserve", {"token":IR_SK08_RESERVE_TOKEN, "items":reserve_items})
		if not bool(reserve_result.get("ok", false)):
			_site_act(p, "set_strategy", {"site":"ir", "strategy_id":old_strategy})
			return reserve_result
		reserved = true
	var queue_result: Dictionary = economy.call("act", p, "queue", {"recipe":"R_IR_CONTACT", "line":line_index, "count":contact_count})
	if not bool(queue_result.get("ok", false)):
		if reserved: economy.call("act", p, "unreserve", {"token":IR_SK08_RESERVE_TOKEN})
		_site_act(p, "set_strategy", {"site":"ir", "strategy_id":old_strategy})
		return queue_result
	return {"ok":true, "message":"Маршрут выбран, существующий рецепт контактов поставлен в очередь; резервы списания не создают", "strategy_id":strategy_id, "recipe_id":"R_IR_CONTACT", "queued_count":contact_count, "line":line_index, "reserved_items":({"pd_concentrate":pd_amount, "iron_ore":fe_amount} if reserved else {})}

static func _owned(p: Dictionary, id: String) -> bool:
	var progression: Dictionary = MATH.game(p).get("progression", {})
	var catalog := "mastery" if id.contains("_SK") else "research"
	return int(progression.get(catalog, {}).get(id, 0)) > 0

static func _feature_ids() -> Array:
	return ["PD05", "PD17", "PD18", "PD22", "PD23", "PD27", "PD29", "PD_SK01", "PD_SK02", "PD_SK03", "PD_SK04", "PD_SK05", "PD_SK06", "PD_SK07", "PD_SK08", "IR05", "IR06", "IR14", "IR16", "IR17", "IR22", "IR23", "IR27", "IR28", "IR_SK01", "IR_SK02", "IR_SK03", "IR_SK04", "IR_SK05", "IR_SK06", "IR_SK07", "IR_SK08"]

static func _readout_ids() -> Array:
	return ["PD_SK01", "PD_SK03", "PD_SK04", "IR_SK01", "IR_SK02", "IR_SK03"]

static func _mechanism(id: String) -> String:
	return {
		"PD05":"extra_optional_lens", "PD17":"accepted_contract_next_lens", "PD18":"selected_known_lens_auto_queue", "PD22":"paid_second_analysis", "PD23":"shared_georadar_forecast_capacity", "PD27":"paid_impurity_analysis_report", "PD29":"paid_distant_analysis_note",
		"PD_SK01":"sample_impurity_region_highlight", "PD_SK02":"paid_second_sample_preview_before_concentration", "PD_SK03":"three_lens_expected_yield_comparison", "PD_SK04":"active_contract_net_value_projection", "PD_SK05":"two_band_sample_choice_one_batch_bonus", "PD_SK06":"paid_manual_filter_prep_next_cycle", "PD_SK07":"shorter_paid_wage_analysis", "PD_SK08":"one_shot_contract_lens_concentration_plan",
		"IR05":"paid_deep_campaign_route", "IR06":"paid_timed_support_prep", "IR14":"one_real_contact_job_duration_profile", "IR16":"budgeted_sequential_safe_campaigns", "IR17":"accepted_contract_route", "IR22":"prestart_guaranteed_detour_with_projection", "IR23":"paid_phase_pause_resume", "IR27":"prestart_lower_yield_faster_cleanup", "IR28":"paid_timed_ancient_report",
		"IR_SK01":"peak_heat_support_phase_readout", "IR_SK02":"maximum_cooling_load_readout", "IR_SK03":"strategy_stability_margin_comparison", "IR_SK04":"unstarted_phase_only_cost_time_override", "IR_SK05":"paid_timed_one_campaign_manipulator_prep", "IR_SK06":"preplanned_cooling_cost_time_temperature_profile", "IR_SK07":"reserve_one_existing_core_for_cleanup", "IR_SK08":"one_command_route_real_contact_and_pd_fe_reserve"
	}.get(id, "")

static func _ir_phase_choices() -> Array:
	var model: Variant = load(SITE_MODEL_PATH)
	var rows: Array = model.call("phase_definitions") if model != null else []
	var choices: Array = []
	for index in rows.size():
		choices.append({"id":str(index), "label":str(rows[index].get("name", rows[index].get("id", "Фаза %d" % (index + 1))))})
	return choices

static func _ir_phase_mode_choices() -> Array:
	var choices: Array = []
	var modes: Dictionary = _config().get("ir", {}).get("unstarted_phase_modes", {})
	for mode_id in modes:
		choices.append({"id":str(mode_id), "label":str(modes[mode_id].get("label", mode_id))})
	return choices

static func _free_resource(p: Dictionary, resource_id: String) -> int:
	return MATH.free_amount(p, resource_id)

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
