class_name EarthFeatures
extends RefCounted

const CONFIG_PATH := "res://data/proposals/features.json"
const RESEARCH_PATH := "res://data/proposals/research_runtime.json"
const MATH_PATH := "res://gameplay/GameMath.gd"
const ECONOMY_PATH := "res://gameplay/EconomyModel.gd"
const SITES_PATH := "res://gameplay/SiteModel.gd"
const FACTORY_LINES := 5

static var _json_cache: Dictionary = {}
static var _model_cache: Dictionary = {}

static func ensure(p: Dictionary) -> void:
	var game: Dictionary = _math("game", [p])
	if not game.has("features") or not game["features"] is Dictionary:
		game["features"] = {}
	var state: Dictionary = game["features"]
	for raw_id in _config().get("supported", {}):
		var id := str(raw_id)
		if not state.has(id) or not state[id] is Dictionary:
			state[id] = _default_state(id)
		else:
			_ensure_state(id, state[id])

static func refresh(p: Dictionary) -> void:
	ensure(p)
	var game: Dictionary = _math("game", [p])
	var features: Dictionary = game["features"]
	for id in _config().get("supported", {}):
		if _owned(p, str(id)):
			_ensure_state(str(id), features[id])

static func advance(p: Dictionary, dt: float) -> void:
	ensure(p)
	if not is_finite(dt) or dt <= 0.0:
		return
	if _owned(p, "D13"):
		var combo := _feature_state(p, "D13")
		combo["memory_seconds_left"] = maxf(0.0, float(combo.get("memory_seconds_left", 0.0)) - dt)
		if float(combo["memory_seconds_left"]) <= 0.0:
			combo["banked_streak"] = 0
	if _owned(p, "A19"):
		_run_idle_routes(p)
	if _owned(p, "IR24"):
		_start_queued_ir_campaign(p)

static func act(p: Dictionary, action: String, args: Dictionary) -> Dictionary:
	ensure(p)
	var id := str(args.get("id", ""))
	var spec := _supported(id)
	if spec.is_empty() or not _owned(p, id):
		return _fail("Сначала изучите соответствующее исследование или мастерство")
	if not _action_for_id(spec, action):
		return _fail("У этого узла нет такого действия")
	if not _site_unlocked(p, str(spec.get("site", ""))):
		return _fail("Участок ещё не открыт")
	match action:
		"configure_hiring": return _configure_hiring(p, args)
		"auto_distribute": return _auto_distribute(p)
		"set_factory_priority": return _set_factory_priority(p, args)
		"set_line_route": return _set_line_route(p, args)
		"clear_line_route": return _clear_line_route(p, args)
		"set_combo_memory": return _set_combo_memory(p, args)
		"archive_combo": return _archive_combo(p)
		"choose_horizon": return _choose_horizon(p, args)
		"select_purity_lens": return _select_purity_lens(p, args)
		"start_forced_campaign": return _start_forced_campaign(p)
		"set_thermal_tradeoff": return _set_thermal_tradeoff(p, args)
		"plan_ir_queue": return _plan_ir_queue(p, args)
		"clear_ir_queue": return _clear_ir_queue(p)
		"route_next_batch": return _route_next_batch(p, args)
	return _fail("Действие runtime не реализовано")

static func operations(p: Dictionary, id: String) -> Array:
	ensure(p)
	var spec := _supported(id)
	if spec.is_empty() or not _owned(p, id) or not _site_unlocked(p, str(spec.get("site", ""))):
		return []
	match id:
		"P04":
			return [
				{"action":"configure_hiring", "title":"Настроить платное распределение работников", "fields":[
					{"key":"enabled", "label":"Разрешить распределение", "type":"toggle"},
					{"key":"budget_cents", "label":"Бюджет за запуск", "type":"number", "min":0, "max":_cap("auto_hire_budget_cents")}]},
				{"action":"auto_distribute", "title":"Распределить работников в пределах бюджета", "fields":[]}
			]
		"A10":
			return [{"action":"set_factory_priority", "title":"Приоритет первой линии", "fields":[{"key":"first_line", "label":"Первая линия", "type":"select", "choices":_line_choices()}]}]
		"A19":
			var routes := _recipe_choices(p)
			return [
				{"action":"set_line_route", "title":"Включить авто-рецепт для простаивающей линии", "fields":[
					{"key":"line", "label":"Линия", "type":"select", "choices":_line_choices()},
					{"key":"recipe_id", "label":"Рецепт", "type":"select", "choices":routes},
					{"key":"budget_cents", "label":"Предел цены одной партии", "type":"number", "min":0, "max":_cap("factory_route_budget_cents")}]},
				{"action":"clear_line_route", "title":"Отключить авто-рецепт линии", "fields":[{"key":"line", "label":"Линия", "type":"select", "choices":_line_choices()}]}
			]
		"D13":
			var actions: Array = [{"action":"set_combo_memory", "title":"Сохранить серию на один промах", "fields":[{"key":"preserve", "label":"Сохраняемые точные касания", "type":"select", "choices":_integer_choices(0, _cap("combo_preserve_streak"))}]}]
			if int(_feature_state(p, "D13").get("best_streak", 0)) > 0 and _feature_state(p, "D13").get("archive_record", {}).is_empty():
				actions.append({"action":"archive_combo", "title":"Заархивировать лучший реальный результат", "fields":[]})
			return actions
		"D16":
			return [{"action":"choose_horizon", "title":"Выбрать доступный горизонт Fe", "fields":[{"key":"index", "label":"Горизонт", "type":"select", "choices":_horizon_choices(p)}]}]
		"PD07":
			return [{"action":"select_purity_lens", "title":"Выбрать Pd-профиль чистоты", "fields":[{"key":"lens_id", "label":"Реальная линза", "type":"select", "choices":_lens_choices()}]}]
		"IR08":
			return [{"action":"start_forced_campaign", "title":"Начать платную форсированную кампанию", "fields":[]}]
		"IR24":
			var strategies := _ir_strategy_choices(p)
			var empty_choices := [{"label":"Не планировать", "value":""}] + strategies
			return [
				{"action":"plan_ir_queue", "title":"Запланировать до двух последовательных кампаний", "fields":[
					{"key":"first_strategy", "label":"Первая схема", "type":"select", "choices":empty_choices},
					{"key":"second_strategy", "label":"Вторая схема", "type":"select", "choices":empty_choices},
					{"key":"budget_cents", "label":"Общий прогнозный бюджет", "type":"number", "min":0, "max":_cap("ir_queue_budget_cents")}]},
				{"action":"clear_ir_queue", "title":"Очистить план", "fields":[]}
			]
		"IR25":
			return [{"action":"set_thermal_tradeoff", "title":"Выбрать фактический профиль времени и стоимости", "fields":[{"key":"strategy_id", "label":"Профиль кампании", "type":"select", "choices":_ir_safe_strategy_choices(p)}]}]
		"FE_SK06":
			return [{"action":"route_next_batch", "title":"Направить следующую реальную партию", "fields":[
				{"key":"destination", "label":"Назначение", "type":"select", "choices":[{"label":"Свободная продажа", "value":"free_sale"}, {"label":"Работающая линия завода", "value":"factory"}]},
				{"key":"line", "label":"Работающая линия", "type":"select", "choices":_line_choices()},
				{"key":"recipe_id", "label":"Фактический рецепт", "type":"select", "choices":_recipe_choices(p, "fe")}]}]
	return []

static func after_action(p: Dictionary, domain: String, action: String, args: Dictionary, result: Dictionary) -> void:
	if not bool(result.get("ok", false)) or not _is_economy_domain(domain) or _normalize_action(action) != "tap":
		return
	ensure(p)
	if _owned(p, "D13") and _site_unlocked(p, "fe"):
		_record_combo_tap(p, result)
	if _owned(p, "FE_SK06") and _site_unlocked(p, "fe"):
		_route_tapped_batch(p, result)

static func coverage() -> Dictionary:
	var source := _research_config()
	var configured: Dictionary = _config().get("supported", {})
	var by_id: Dictionary = {}
	var supported_ids: Array[String] = []
	var gap_ids: Array[String] = []
	for catalog in ["research", "mastery"]:
		for raw_id in source.get(catalog, {}):
			var id := str(raw_id)
			var node: Dictionary = source[catalog][raw_id]
			if str(node.get("mode", "")) != "feature":
				continue
			var implementation: Dictionary = configured.get(id, {})
			if not implementation.is_empty():
				supported_ids.append(id)
				by_id[id] = {"status":"supported", "supported":true, "catalog":catalog, "mechanism":str(implementation.get("mechanism", "")), "canonical_effect":str(implementation.get("canonical_effect", "")), "actions":implementation.get("actions", []).duplicate()}
			else:
				gap_ids.append(id)
				by_id[id] = {"status":"gap", "supported":false, "catalog":catalog, "mechanism":str(node.get("mechanism", "")), "gap":str(node.get("gap", ""))}
	return {"total":by_id.size(), "supported_ids":supported_ids, "gap_ids":gap_ids, "by_id":by_id}

static func _configure_hiring(p: Dictionary, args: Dictionary) -> Dictionary:
	var enabled: Variant = args.get("enabled", null)
	var budget := _nonnegative_integer(args.get("budget_cents", null))
	if typeof(enabled) != TYPE_BOOL or budget < 0 or budget > _cap("auto_hire_budget_cents"):
		return _fail("Укажите переключатель и бюджет в допустимых пределах")
	if budget > int(p.get("money_cents", 0)):
		return _fail("Бюджет превышает текущие средства")
	var state := _feature_state(p, "P04")
	if bool(state.get("enabled", false)) == bool(enabled) and int(state.get("budget_cents", 0)) == budget:
		return _ok("Настройки уже сохранены")
	state["enabled"] = bool(enabled)
	state["budget_cents"] = budget
	return _ok("Бюджет распределения сохранён; покупка произойдёт только по отдельной команде")

static func _auto_distribute(p: Dictionary) -> Dictionary:
	var state := _feature_state(p, "P04")
	if not bool(state.get("enabled", false)):
		return _fail("Сначала явно включите распределение и задайте бюджет")
	var economy: Variant = _model(ECONOMY_PATH)
	var definitions: Array = economy.callv("definitions", ["fe", "worker"])
	if definitions.is_empty():
		return _fail("Нет доступных профессий")
	var remaining := mini(int(state.get("budget_cents", 0)), int(p.get("money_cents", 0)))
	var spent := 0
	var hired: Array[String] = []
	for _iteration in range(_cap("auto_hire_limit")):
		var workers: Dictionary = _math("site", [p, "fe"]).get("workers", {})
		var candidate_id := ""
		var candidate_count := 2147483647
		var candidate_cost := 0
		for definition_value in definitions:
			var definition: Dictionary = definition_value
			var worker_id := str(definition.get("id", ""))
			var level := int(workers.get(worker_id, 0))
			if worker_id.is_empty() or level >= int(definition.get("max_level", 0)):
				continue
			var quote: Dictionary = economy.callv("quote", [p, "fe", "worker", worker_id, 1])
			var cost := int(quote.get("cost_cents", 0))
			if not bool(quote.get("ok", false)) or cost <= 0 or cost > remaining:
				continue
			if level < candidate_count:
				candidate_id = worker_id
				candidate_count = level
				candidate_cost = cost
		if candidate_id.is_empty():
			break
		var purchase: Dictionary = economy.callv("act", [p, "buy", {"site":"fe", "kind":"worker", "id":candidate_id, "count":1}])
		if not bool(purchase.get("ok", false)):
			break
		remaining -= candidate_cost
		spent += candidate_cost
		hired.append(candidate_id)
	if hired.is_empty():
		return _fail("Бюджета или средств не хватает на следующую реальную профессию")
	var output := _ok("Работники куплены и распределены по реальным открытым ролям")
	output["hired"] = hired
	output["spent_cents"] = spent
	state["enabled"] = false
	state["last_distribution"] = {"hired":hired.duplicate(), "spent_cents":spent, "budget_cents":int(state.get("budget_cents", 0))}
	return output

static func _set_factory_priority(p: Dictionary, args: Dictionary) -> Dictionary:
	var first_line := _nonnegative_integer(args.get("first_line", null))
	if first_line < 0 or first_line >= FACTORY_LINES:
		return _fail("Выберите линию от 0 до 4")
	var state := _feature_state(p, "A10")
	if int(state.get("first_line", 0)) == first_line:
		return _ok("Приоритет уже установлен")
	state["first_line"] = first_line
	return _ok("Порядок проверки простаивающих линий сохранён")

static func _set_line_route(p: Dictionary, args: Dictionary) -> Dictionary:
	var line := _nonnegative_integer(args.get("line", null))
	var recipe_id := str(args.get("recipe_id", ""))
	var budget := _nonnegative_integer(args.get("budget_cents", null))
	if line < 0 or line >= FACTORY_LINES or budget <= 0 or budget > _cap("factory_route_budget_cents"):
		return _fail("Линия или бюджет вне допустимого диапазона")
	if budget > int(p.get("money_cents", 0)):
		return _fail("Бюджет одной партии превышает текущие средства")
	var recipe := _recipe(recipe_id)
	var site := _recipe_site(recipe)
	if recipe.is_empty() or site.is_empty() or not _site_unlocked(p, site):
		return _fail("Рецепт не существует или его участок закрыт")
	var quote: Dictionary = _model(ECONOMY_PATH).callv("quote", [p, site, "recipe", recipe_id, 1])
	var cost := int(quote.get("cost_cents", -1))
	if cost <= 0 or cost > budget:
		return _fail("Бюджета на одну реальную партию недостаточно")
	var routes: Dictionary = _feature_state(p, "A19").get("routes", {})
	var route := {"recipe_id":recipe_id, "budget_cents":budget, "enabled":true}
	if routes.get(str(line), {}) == route:
		return _ok("Автоматический маршрут уже сохранён")
	routes[str(line)] = route
	return _ok("Рецепт сохранён; линия потратит средства только если сможет поставить реальную партию")

static func _clear_line_route(p: Dictionary, args: Dictionary) -> Dictionary:
	var line := _nonnegative_integer(args.get("line", null))
	if line < 0 or line >= FACTORY_LINES:
		return _fail("Выберите линию от 0 до 4")
	var routes: Dictionary = _feature_state(p, "A19").get("routes", {})
	if not routes.has(str(line)):
		return _ok("Маршрут уже отключён")
	routes.erase(str(line))
	return _ok("Автоматический маршрут отключён")

static func _run_idle_routes(p: Dictionary) -> void:
	var game: Dictionary = _math("game", [p])
	var factory: Array = game.get("factory", [])
	var routes: Dictionary = _feature_state(p, "A19").get("routes", {})
	var start := int(_feature_state(p, "A10").get("first_line", 0)) if _owned(p, "A10") else 0
	var economy: Variant = _model(ECONOMY_PATH)
	for offset in range(FACTORY_LINES):
		var line_index := (start + offset) % FACTORY_LINES
		var route: Dictionary = routes.get(str(line_index), {})
		if not bool(route.get("enabled", false)) or line_index >= factory.size():
			continue
		var line: Dictionary = factory[line_index]
		if not Dictionary(line.get("active", {})).is_empty() or not Array(line.get("queue", [])).is_empty() or not Dictionary(line.get("pending", {})).is_empty():
			continue
		var recipe_id := str(route.get("recipe_id", ""))
		var site := _recipe_site(_recipe(recipe_id))
		if site.is_empty() or not _site_unlocked(p, site):
			continue
		var quote: Dictionary = economy.callv("quote", [p, site, "recipe", recipe_id, 1])
		var cost := int(quote.get("cost_cents", 0))
		if cost <= 0 or cost > int(route.get("budget_cents", 0)) or not bool(quote.get("ok", false)):
			continue
		var enough_inputs := true
		for resource in quote.get("inputs", {}):
			if int(_math("free_amount", [p, str(resource)]) ) < int(quote["inputs"][resource]):
				enough_inputs = false
				break
		if not enough_inputs:
			continue
		economy.callv("act", [p, "queue", {"recipe":recipe_id, "line":line_index, "count":1}])

static func _set_combo_memory(p: Dictionary, args: Dictionary) -> Dictionary:
	var preserve := _nonnegative_integer(args.get("preserve", null))
	if preserve < 0 or preserve > _cap("combo_preserve_streak"):
		return _fail("Сохраняемая серия должна быть от 0 до допустимого предела")
	var state := _feature_state(p, "D13")
	if int(state.get("preserve", 0)) == preserve:
		return _ok("Размер памяти серии уже установлен")
	state["preserve"] = preserve
	return _ok("На один промах сохранится не больше выбранного числа реальных точных касаний")

static func _record_combo_tap(p: Dictionary, result: Dictionary) -> void:
	var state := _feature_state(p, "D13")
	var current := int(result.get("precision_streak", 0))
	if bool(result.get("precision", false)):
		state["best_streak"] = maxi(int(state.get("best_streak", 0)), current)
		state["banked_streak"] = mini(current, int(state.get("preserve", 0)))
		state["memory_seconds_left"] = float(_cap("combo_memory_seconds"))
		return
	var kept := 0
	if float(state.get("memory_seconds_left", 0.0)) > 0.0:
		kept = mini(int(state.get("banked_streak", 0)), int(state.get("preserve", 0)))
	if kept > 0:
		var game: Dictionary = _math("game", [p])
		var rng: Dictionary = game.get("economy_rng", {})
		rng["precision_streak"] = kept
		var stats: Dictionary = game.get("stats", {})
		stats["current_combo_streak"] = kept
		result["preserved_streak"] = kept
	state["banked_streak"] = 0
	state["memory_seconds_left"] = 0.0

static func _archive_combo(p: Dictionary) -> Dictionary:
	var state := _feature_state(p, "D13")
	if not Dictionary(state.get("archive_record", {})).is_empty():
		return _fail("Этот необязательный рекорд уже заархивирован")
	var best := int(state.get("best_streak", 0))
	if best <= 0:
		return _fail("Сначала нужен реальный результат точной серии")
	state["archive_record"] = {"id":"D13", "best_streak":best, "taps":int(_math("game", [p]).get("stats", {}).get("taps", 0))}
	return _ok("Реальный результат заархивирован один раз без награды или ресурсов")

static func _choose_horizon(p: Dictionary, args: Dictionary) -> Dictionary:
	var index := _nonnegative_integer(args.get("index", null))
	if index < 0 or index > _max_horizon(p):
		return _fail("Горизонт ещё не открыт фактическим уровнем улучшений")
	return _model(ECONOMY_PATH).callv("act", [p, "horizon", {"site":"fe", "index":index}])

static func _select_purity_lens(p: Dictionary, args: Dictionary) -> Dictionary:
	var lens_id := str(args.get("lens_id", ""))
	var valid := false
	for lens in _model(SITES_PATH).callv("lens_definitions", []):
		if str(lens.get("id", "")) == lens_id:
			valid = true
			break
	if not valid:
		return _fail("Выберите одну из реальных линз Pd")
	return _model(SITES_PATH).callv("act", [p, "select_lens", {"site":"pd", "lens_id":lens_id}])

static func _start_forced_campaign(p: Dictionary) -> Dictionary:
	if not _owned(p, "IR08"):
		return _fail("Форсированный режим требует исследования IR08")
	var projection := _ir_projection(p, "forced")
	if projection.is_empty() or int(projection.get("cost_cents", 0)) > int(p.get("money_cents", 0)):
		return _fail("Текущих средств недостаточно для полного прогноза кампании")
	return _model(SITES_PATH).callv("act", [p, "start_campaign", {"site":"ir", "strategy_id":"forced"}])

static func _set_thermal_tradeoff(p: Dictionary, args: Dictionary) -> Dictionary:
	var strategy_id := str(args.get("strategy_id", ""))
	if strategy_id not in ["economic", "reliable"]:
		return _fail("Выберите фактический экономичный или надёжный профиль")
	var projection := _ir_projection(p, strategy_id)
	if projection.is_empty() or int(projection.get("cost_cents", 0)) > int(p.get("money_cents", 0)):
		return _fail("Текущих средств недостаточно для полного прогноза кампании")
	return _model(SITES_PATH).callv("act", [p, "set_strategy", {"site":"ir", "strategy_id":strategy_id}])

static func _plan_ir_queue(p: Dictionary, args: Dictionary) -> Dictionary:
	var first := str(args.get("first_strategy", ""))
	var second := str(args.get("second_strategy", ""))
	var budget := _nonnegative_integer(args.get("budget_cents", null))
	if budget < 0 or budget > _cap("ir_queue_budget_cents") or budget > int(p.get("money_cents", 0)):
		return _fail("Общий прогнозный бюджет превышает лимит или текущие средства")
	var planned: Array[String] = []
	for strategy in [first, second]:
		if strategy.is_empty():
			continue
		if not _valid_ir_strategy(p, strategy):
			return _fail("Схема отсутствует или требует отдельного исследования")
		planned.append(strategy)
	if planned.size() > _cap("ir_queue_length") or (planned.size() == 2 and planned[0] == planned[1]):
		return _fail("План ограничен двумя разными последовательными схемами")
	var total_projection := 0
	for strategy in planned:
		var projection := _ir_projection(p, strategy)
		if projection.is_empty():
			return _fail("Не удалось получить прогноз фактической кампании")
		total_projection += int(projection.get("cost_cents", 0))
	if total_projection > budget:
		return _fail("Плановый бюджет не покрывает полный прогноз очереди")
	var state := _feature_state(p, "IR24")
	if state.get("last_plan", []) == planned and int(state.get("budget_cents", 0)) == budget:
		return _ok("Такой последовательный план уже сохранён")
	state["queue"] = planned.duplicate()
	state["budget_cents"] = budget
	state["remaining_budget_cents"] = budget
	state["last_plan"] = planned.duplicate()
	return _ok("План сохранён без списания средств; каждая кампания начнётся отдельно через SiteModel")

static func _clear_ir_queue(p: Dictionary) -> Dictionary:
	var state := _feature_state(p, "IR24")
	if state.get("queue", []).is_empty() and state.get("last_plan", []).is_empty():
		return _ok("Очередь уже пуста")
	state["queue"] = []
	state["budget_cents"] = 0
	state["remaining_budget_cents"] = 0
	state["last_plan"] = []
	return _ok("Будущие кампании удалены; активная кампания не затронута")

static func _start_queued_ir_campaign(p: Dictionary) -> void:
	var state := _feature_state(p, "IR24")
	var queue: Array = state.get("queue", [])
	if queue.is_empty():
		return
	var view: Dictionary = _model(SITES_PATH).callv("view", [p, "ir"])
	if not bool(view.get("unlocked", false)) or str(view.get("status", "")) not in ["idle", "completed", "cancelled"] or int(view.get("pending_output", 0)) > 0:
		return
	var strategy := str(queue[0])
	if not _valid_ir_strategy(p, strategy):
		return
	var projection := _ir_projection(p, strategy)
	var projected_cost := int(projection.get("cost_cents", 0))
	var remaining_budget := int(state.get("remaining_budget_cents", state.get("budget_cents", 0)))
	if projected_cost > remaining_budget or projected_cost > int(p.get("money_cents", 0)):
		return
	var result: Dictionary = _model(SITES_PATH).callv("act", [p, "start_campaign", {"site":"ir", "strategy_id":strategy}])
	if bool(result.get("ok", false)):
		queue.pop_front()
		state["queue"] = queue
		state["remaining_budget_cents"] = maxi(0, remaining_budget - projected_cost)

static func _route_next_batch(p: Dictionary, args: Dictionary) -> Dictionary:
	var destination := str(args.get("destination", ""))
	if destination not in ["free_sale", "factory"]:
		return _fail("Выберите продажу или работающую заводскую линию")
	var network: Dictionary = _math("game", [p]).get("network", {})
	if bool(network.get("autosell", false)):
		return _fail("Сначала отключите автопродажу, иначе партия уже продаётся моделью экономики")
	var spec := {"destination":destination, "armed_iron":int(p.get("inventory", {}).get("iron_ore", 0))}
	if destination == "factory":
		var line := _nonnegative_integer(args.get("line", null))
		var recipe_id := str(args.get("recipe_id", ""))
		var recipe := _recipe(recipe_id)
		if line < 0 or line >= FACTORY_LINES or recipe.is_empty() or _recipe_site(recipe) != "fe" or not _site_unlocked(p, "fe"):
			return _fail("Выберите реальный Fe-рецепт и действующую линию")
		var lines: Array = _math("game", [p]).get("factory", [])
		if line >= lines.size() or (Dictionary(lines[line].get("active", {})).is_empty() and Array(lines[line].get("queue", [])).is_empty()):
			return _fail("Для перенаправления нужна уже работающая линия")
		spec["line"] = line
		spec["recipe_id"] = recipe_id
	var state := _feature_state(p, "FE_SK06")
	if state.get("pending", {}).is_empty():
		state["pending"] = spec
		return _ok("Назначение вооружено для следующей успешной ручной партии, без создания руды")
	if state["pending"] == spec:
		return _ok("Такое назначение уже ожидает следующей партии")
	return _fail("Сначала используйте или отмените уже вооружённое назначение")

static func _route_tapped_batch(p: Dictionary, result: Dictionary) -> void:
	var state := _feature_state(p, "FE_SK06")
	var pending: Dictionary = state.get("pending", {})
	if pending.is_empty():
		return
	state["pending"] = {}
	var amount := int(result.get("amount", 0))
	var current_iron := int(p.get("inventory", {}).get("iron_ore", 0))
	var required_balance := int(pending.get("armed_iron", 0)) + amount
	var outcome: Dictionary = _fail("Не удалось подтвердить наличие новой партии")
	if amount <= 0 or current_iron < required_balance:
		state["last_route"] = {"ok":false, "message":str(outcome.get("message", ""))}
		return
	if str(pending.get("destination", "")) == "free_sale":
		outcome = _model(ECONOMY_PATH).callv("act", [p, "sell", {"resource":"iron_ore", "amount":amount}])
	else:
		var line := int(pending.get("line", -1))
		var line_state: Dictionary = _math("game", [p]).get("factory", [])[line]
		if not bool(_math("game", [p]).get("network", {}).get("autosell", false)) and (not Dictionary(line_state.get("active", {})).is_empty() or not Array(line_state.get("queue", [])).is_empty()):
			outcome = _model(ECONOMY_PATH).callv("act", [p, "queue", {"recipe":str(pending.get("recipe_id", "")), "line":line, "count":1}])
	state["last_route"] = outcome.duplicate(true)
	result["batch_route"] = outcome.duplicate(true)

static func _ir_projection(p: Dictionary, strategy: String) -> Dictionary:
	var view: Dictionary = _model(SITES_PATH).callv("view", [p, "ir"])
	for option_value in view.get("strategy_options", []):
		var option: Dictionary = option_value
		if str(option.get("id", "")) == strategy:
			return option.get("projection", {}).duplicate(true)
	return {}

static func _valid_ir_strategy(p: Dictionary, strategy: String) -> bool:
	if strategy == "forced" and not _owned(p, "IR08"):
		return false
	for option in _model(SITES_PATH).callv("strategy_definitions", []):
		if str(option.get("id", "")) == strategy:
			return true
	return false

static func _ir_strategy_choices(p: Dictionary) -> Array:
	var choices: Array = []
	for option in _model(SITES_PATH).callv("strategy_definitions", []):
		var id := str(option.get("id", ""))
		if not _valid_ir_strategy(p, id):
			continue
		var projection := _ir_projection(p, id)
		choices.append({"label":"%s — %d¢ / %.0f сек" % [str(option.get("name", id)), int(projection.get("cost_cents", 0)), float(projection.get("duration_seconds", 0.0))], "value":id})
	return choices

static func _ir_safe_strategy_choices(p: Dictionary) -> Array:
	var choices: Array = []
	for id in ["economic", "reliable"]:
		for option in _ir_strategy_choices(p):
			if str(option.get("value", "")) == id and int(_ir_projection(p, id).get("cost_cents", 0)) <= int(p.get("money_cents", 0)):
				choices.append(option)
	return choices

static func _recipe_choices(p: Dictionary, only_site: String = "") -> Array:
	var choices: Array = []
	for value in _math("records", ["recipes"]):
		var recipe: Dictionary = value
		var id := str(recipe.get("id", ""))
		var site := _recipe_site(recipe)
		if id.is_empty() or site.is_empty() or (not only_site.is_empty() and site != only_site) or not _site_unlocked(p, site):
			continue
		choices.append({"label":"%s — %s" % [id, str(recipe.get("output", ""))], "value":id})
	return choices

static func _lens_choices() -> Array:
	var choices: Array = []
	for lens in _model(SITES_PATH).callv("lens_definitions", []):
		choices.append({"label":"%s — %d…%d ед." % [str(lens.get("name", lens.get("id", ""))), int(lens.get("yield_min", 0)), int(lens.get("yield_max", 0))], "value":str(lens.get("id", ""))})
	return choices

static func _horizon_choices(p: Dictionary) -> Array:
	return _integer_choices(0, _max_horizon(p))

static func _max_horizon(p: Dictionary) -> int:
	var site_data: Dictionary = _math("site", [p, "fe"])
	var definitions: Array = _model(ECONOMY_PATH).callv("definitions", ["fe", "upgrade"])
	var total := 0
	for definition in definitions:
		total += maxi(0, int(site_data.get("upgrades", {}).get(str(definition.get("id", "")), 0)))
	var average := floori(float(total) / float(maxi(1, definitions.size())))
	return clampi(floori(float(average) / 100.0), 0, 10)

static func _line_choices() -> Array:
	return _integer_choices(0, FACTORY_LINES - 1, "Линия ")

static func _integer_choices(minimum: int, maximum: int, prefix: String = "") -> Array:
	var choices: Array = []
	for value in range(minimum, maximum + 1):
		choices.append({"label":prefix + str(value), "value":value})
	return choices

static func _recipe(id: String) -> Dictionary:
	for value in _math("records", ["recipes"]):
		if str(value.get("id", "")) == id:
			return value
	return {}

static func _recipe_site(recipe: Dictionary) -> String:
	if recipe.is_empty():
		return ""
	var output := str(recipe.get("output", ""))
	if output.begins_with("pd_"):
		return "pd"
	if output.begins_with("ir_"):
		return "ir"
	return "fe"

static func _site_unlocked(p: Dictionary, site: String) -> bool:
	return site in ["fe", "pd", "ir"] and bool(_math("unlocked", [p, site]))

static func _owned(p: Dictionary, id: String) -> bool:
	var spec := _supported(id)
	if spec.is_empty():
		return false
	var catalog := "mastery" if id.contains("_SK") else "research"
	var record: Dictionary = _research_config().get(catalog, {}).get(id, {})
	if str(record.get("mode", "")) != "feature":
		return false
	var progression: Dictionary = _math("game", [p]).get("progression", {})
	return int(progression.get(catalog, {}).get(id, 0)) > 0

static func _supported(id: String) -> Dictionary:
	return _config().get("supported", {}).get(id, {}).duplicate(true)

static func _action_for_id(spec: Dictionary, action: String) -> bool:
	return action in spec.get("actions", [])

static func _feature_state(p: Dictionary, id: String) -> Dictionary:
	var game: Dictionary = _math("game", [p])
	var features: Dictionary = game.get("features", {})
	if not features.has(id) or not features[id] is Dictionary:
		features[id] = _default_state(id)
	return features[id]

static func _default_state(id: String) -> Dictionary:
	match id:
		"P04": return {"enabled":false, "budget_cents":0, "last_distribution":{}}
		"A10": return {"first_line":0}
		"A19": return {"routes":{}}
		"D13": return {"preserve":0, "banked_streak":0, "memory_seconds_left":0.0, "best_streak":0, "archive_record":{}}
		"IR24": return {"queue":[], "budget_cents":0, "remaining_budget_cents":0, "last_plan":[]}
		"FE_SK06": return {"pending":{}, "last_route":{}}
	return {}

static func _ensure_state(id: String, state: Dictionary) -> void:
	for key in _default_state(id):
		if not state.has(key) or typeof(state[key]) != typeof(_default_state(id)[key]):
			state[key] = _default_state(id)[key]
	if id == "D13":
		state["preserve"] = clampi(int(state.get("preserve", 0)), 0, _cap("combo_preserve_streak"))
		state["banked_streak"] = clampi(int(state.get("banked_streak", 0)), 0, _cap("combo_preserve_streak"))
		state["memory_seconds_left"] = clampf(float(state.get("memory_seconds_left", 0.0)), 0.0, float(_cap("combo_memory_seconds")))

static func _is_economy_domain(domain: String) -> bool:
	var normalized := domain.to_lower().replace("_", "").replace(".", "")
	return normalized in ["economy", "economymodel", "eartheconomy"]

static func _normalize_action(action: String) -> String:
	var pieces := action.to_lower().split(".")
	return pieces[pieces.size() - 1].replace("_", "")

static func _nonnegative_integer(value: Variant) -> int:
	if typeof(value) == TYPE_BOOL or typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)) or float(value) != floorf(float(value)) or float(value) < 0.0 or float(value) > 2147483647.0:
		return -1
	return int(value)

static func _cap(key: String) -> int:
	return int(_config().get("caps", {}).get(key, 0))

static func _math(method: String, args: Array) -> Variant:
	return _model(MATH_PATH).callv(method, args)

static func _ok(message: String) -> Dictionary:
	return _math("ok", [message])

static func _fail(message: String) -> Dictionary:
	return _math("fail", [message])

static func _model(path: String) -> Variant:
	if not _model_cache.has(path):
		_model_cache[path] = load(path)
	return _model_cache[path]

static func _config() -> Dictionary:
	return _read_json(CONFIG_PATH)

static func _research_config() -> Dictionary:
	return _read_json(RESEARCH_PATH)

static func _read_json(path: String) -> Dictionary:
	if _json_cache.has(path):
		return _json_cache[path]
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		_json_cache[path] = parsed
	return _json_cache.get(path, {})
