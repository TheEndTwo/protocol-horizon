class_name EarthResearch
extends RefCounted

const CONFIG_PATH := "res://data/proposals/research_runtime.json"
const ECONOMY := preload("res://gameplay/EconomyModel.gd")
const SITES := preload("res://gameplay/SiteModel.gd")
const PRESET_SETTING_KEYS := ["network_mode", "autosell", "pd_lens_id", "ir_strategy_id", "profile", "priority", "route_id", "cooling_mode", "recipe_ids", "line", "count"]

static var _config_cache: Dictionary = {}

static func refresh(p: Dictionary) -> void:
	_ensure(p)
	var g := GameMath.game(p)
	var progression: Dictionary = g["progression"]
	var research_cfg: Dictionary = _config().get("research", {})
	var mastery_cfg: Dictionary = _config().get("mastery", {})
	var bonuses: Dictionary = {}
	var owned_nodes: Dictionary = {}
	var features: Dictionary = {}
	for catalog in [{"name":"research", "rows":research_cfg}, {"name":"mastery", "rows":mastery_cfg}]:
		var levels: Dictionary = progression.get(str(catalog["name"]), {})
		for raw_id in catalog["rows"]:
			var id := str(raw_id)
			var node: Dictionary = catalog["rows"][raw_id]
			var rank := maxi(0, int(levels.get(id, 0)))
			if rank <= 0:
				continue
			owned_nodes[id] = {"rank":rank, "mode":str(node.get("mode", "missing")), "mechanism":str(node.get("mechanism", ""))}
			var feature_key := str(node.get("feature_key", ""))
			if not feature_key.is_empty():
				features[feature_key] = true
			if str(node.get("mode", "")) != "modifier" or bool(node.get("skip_numeric", false)):
				continue
			var key := str(node.get("key", ""))
			if key.is_empty():
				continue
			var value := float(node.get("per_rank", 0.0)) * float(rank)
			if node.has("cap"):
				value = minf(value, float(node["cap"]))
			var scope := str(node.get("scope", ""))
			var bonus_key := key if scope.is_empty() or scope == "all" else scope + ":" + key
			bonuses[bonus_key] = float(bonuses.get(bonus_key, 0.0)) + value
	var runtime: Dictionary = g["research_runtime"]
	runtime["owned"] = owned_nodes
	runtime["features"] = features
	runtime["progression_bonus_skip_ids"] = _config().get("compatibility", {}).get("ignore_existing_progression_numeric_ids", []).duplicate()
	g["bonuses"]["research_runtime"] = bonuses

static func act(p: Dictionary, action: String, args: Dictionary = {}) -> Dictionary:
	_ensure(p)
	refresh(p)
	var id := str(args.get("id", args.get("research_id", "")))
	var node := _node(id)
	if node.is_empty():
		return GameMath.fail("Неизвестный research/mastery ID")
	if _owned_rank(p, id) <= 0:
		return GameMath.fail("Сначала изучите этот узел")
	if str(node.get("action", "")) != action:
		return GameMath.fail("У этого узла нет такого действия")
	var result: Dictionary
	match action:
		"reserve_items": result = _reserve_items(p, id, args)
		"set_horizon": result = ECONOMY.act(p, "horizon", {"site":"fe", "index":int(args.get("index", -1))})
		"set_cash_reserve": result = _set_cash_reserve(p, id, args)
		"preset": result = _preset(p, id, node, args)
		"queue_recipe_chain": result = _queue_recipe_chain(p, args)
		"select_pd_lens": result = SITES.act(p, "select_lens", {"site":"pd", "lens_id":str(args.get("lens_id", ""))})
		"select_ir_strategy": result = SITES.act(p, "set_strategy", {"site":"ir", "strategy_id":str(args.get("strategy_id", ""))})
		"set_pd_auto": result = SITES.act(p, "set_automatic", {"site":"pd", "enabled":bool(args.get("enabled", false))})
		"set_preference": result = _set_preference(p, id, node, args)
		"archive_current": result = _archive_current(p, id, node)
		"complete_task": result = _complete_task(p, id, node)
		_: result = GameMath.fail("Действие runtime не реализовано")
	if bool(result.get("ok", false)):
		refresh(p)
	return result

static func describe(p: Dictionary, id: String) -> Dictionary:
	_ensure(p)
	refresh(p)
	var catalog := "mastery" if id.contains("_SK") else "research"
	var record := GameMath.record(catalog, id)
	var node := _node(id)
	if record.is_empty() or node.is_empty():
		return {"id":id, "known":false, "mode":"missing", "implemented":false, "effect":""}
	var rank := _owned_rank(p, id)
	var mode := str(node.get("mode", "missing"))
	var view_data: Dictionary = _view_state(p, str(node.get("view", "")), node) if mode == "view" else {}
	return {
		"id":id, "known":true, "catalog":catalog, "record":record,
		"effect":str(record.get("effect", "")), "mode":mode,
		"implemented":bool(node.get("implemented", false)),
		"canonical_status":str(node.get("canonical_status", "missing")),
		"mechanism":str(node.get("mechanism", "")),
		"core_hook_required":bool(node.get("core_hook_required", true)),
		"gap":str(node.get("gap", "")),
		"owned":rank > 0, "enabled":rank > 0 and bool(node.get("implemented", false)),
		"level":rank if catalog == "research" else 0,
		"rank":rank if catalog == "mastery" else 0,
		"action":str(node.get("action", "")),
		"action_fields":node.get("action_fields", []).duplicate(true),
		"feature_key":str(node.get("feature_key", "")),
		"modifier_key":str(node.get("key", "")),
		"modifier_scope":str(node.get("scope", "")),
		"current_state":view_data
	}

static func coverage() -> Dictionary:
	var result := {"research":_catalog_coverage("research"), "mastery":_catalog_coverage("mastery")}
	result["compatibility_skip_ids"] = _config().get("compatibility", {}).get("ignore_existing_progression_numeric_ids", []).duplicate()
	return result

static func _catalog_coverage(catalog: String) -> Dictionary:
	var entries: Dictionary = _config().get(catalog, {})
	var ids: Array[String] = []
	var implemented: Array[String] = []
	var partial: Array[String] = []
	var missing: Array[String] = []
	var hooks: Array[String] = []
	var by_id: Dictionary = {}
	for record in GameMath.records(catalog):
		var id := str(record.get("id", ""))
		ids.append(id)
		var node: Dictionary = entries.get(id, {})
		var status := str(node.get("canonical_status", "missing"))
		by_id[id] = {"mode":str(node.get("mode", "missing")), "mechanism":str(node.get("mechanism", "")), "status":status, "core_hook_required":bool(node.get("core_hook_required", true)), "gap":str(node.get("gap", ""))}
		match status:
			"complete": implemented.append(id)
			"partial": partial.append(id)
			_: missing.append(id)
		if bool(node.get("core_hook_required", true)):
			hooks.append(id)
	return {"total":ids.size(), "mapped":by_id.size(), "implemented_ids":implemented, "partial_ids":partial, "missing_ids":missing, "core_hook_ids":hooks, "by_id":by_id}

static func _view_state(p: Dictionary, view: String, node: Dictionary) -> Dictionary:
	var game := GameMath.game(p)
	var site := str(node.get("site", "fe"))
	match view:
		"site_metrics":
			return ECONOMY.metrics(p, site)
		"worker_roi", "wages":
			var workforce := _worker_roi(p, site)
			workforce["cash_reserves"] = game.get("research_runtime", {}).get("cash_reserves", {}).duplicate(true)
			return workforce
		"horizons", "horizon_value_comparison":
			return _horizon_value_comparison(p)
		"open_horizons":
			var metrics: Dictionary = ECONOMY.metrics(p, site)
			var max_horizon := clampi(floori(float(metrics.get("average_upgrade_level", 0.0)) / 100.0), 0, 10)
			return {"site":site, "unlocked_horizon_indices":range(max_horizon + 1), "selected_horizon":int(GameMath.site(p, site).get("horizon", 0)), "average_upgrade_level":float(metrics.get("average_upgrade_level", 0.0))}
		"workforce":
			var workers: Array = []
			for definition in ECONOMY.definitions(site, "worker"):
				var worker_id := str(definition.get("id", ""))
				workers.append({"id":worker_id, "count":int(GameMath.site(p, site).get("workers", {}).get(worker_id, 0)), "name":str(definition.get("name", worker_id))})
			return {"site":site, "workers":workers, "machines":GameMath.site(p, site).get("machines", {}).duplicate(true)}
		"specialists":
			var roster: Variant = p.get("specialists", p.get("local", {}).get("specialists", []))
			if roster is Array or roster is Dictionary:
				return {"site":site, "roster":roster.duplicate(true)}
			return {"site":site, "roster":[]}
		"site_map":
			var sites: Dictionary = {}
			for site_id in GameMath.SITES:
				var state: Dictionary = GameMath.site(p, site_id)
				sites[site_id] = {"unlocked":GameMath.unlocked(p, site_id), "peak":int(state.get("peak", 0)), "geodata":int(state.get("geodata", 0)), "expansions":int(state.get("expansions", 0)), "horizon":int(state.get("horizon", 0))}
			return {"sites":sites}
		"geology_reports", "geology_archive", "geology_history":
			var geology: Dictionary = game.get("progression", {}).get("geology", {})
			var reports: Array = geology.get("reports", []).duplicate(true)
			if view == "geology_history" and reports.size() > 20:
				reports = reports.slice(reports.size() - 20)
			return {"reports":reports, "discoveries":geology.get("discoveries", {}).duplicate(true), "active":geology.get("active", {}).duplicate(true)}
		"pd_lenses":
			return {"unlocked":GameMath.unlocked(p, "pd"), "lenses":SITES.lens_definitions()}
		"pd_sample", "pd_lens_comparison", "production_chain":
			return SITES.view(p, "pd")
		"pd_costs":
			var pd_state: Dictionary = SITES.view(p, "pd")
			pd_state["cash_reserves"] = game.get("research_runtime", {}).get("cash_reserves", {}).duplicate(true)
			return pd_state
		"runtime_archive":
			return {"archive":game.get("research_runtime", {}).get("archive", {}).duplicate(true), "geology":game.get("progression", {}).get("geology", {}).get("reports", []).duplicate(true)}
		"market", "market_added_value":
			return _market_added_value()
		"ir_forecast", "ir_campaign":
			return SITES.view(p, "ir")
		"ir_history":
			return {"campaign":game.get("extraction", {}).get("ir", {}).duplicate(true), "archive":game.get("research_runtime", {}).get("archive", {}).duplicate(true)}
		"ir_contract_status":
			return {"contracts":game.get("progression", {}).get("contracts", {}).duplicate(true), "reservations":game.get("reservations", {}).duplicate(true)}
		"factory_queues":
			return {"factory":game.get("factory", []).duplicate(true), "network":game.get("network", {}).duplicate(true)}
		"geology_goals":
			return {"discoveries":game.get("progression", {}).get("geology", {}).get("discoveries", {}).duplicate(true), "reports":game.get("progression", {}).get("geology", {}).get("reports", []).duplicate(true)}
		"ir_campaign_snapshot":
			return game.get("extraction", {}).get("ir", {}).duplicate(true)
		_:
			return {"available":false, "reason":"No runtime view is defined for this effect."}

static func _worker_roi(p: Dictionary, site: String) -> Dictionary:
	var metrics := ECONOMY.metrics(p, site)
	var resource := str(metrics.get("resource", ""))
	var sale_price := int(GameMath.record("resources", resource).get("sale_price_cents", 0))
	var rows: Array = []
	for worker in ECONOMY.definitions(site, "worker"):
		var worker_id := str(worker.get("id", ""))
		var quote: Dictionary = ECONOMY.quote(p, site, "worker", worker_id, 1)
		var before: Dictionary = quote.get("effect_before", {})
		var after: Dictionary = quote.get("effect_after", {})
		var before_net := float(before.get("rate_per_second", 0.0)) * 3600.0 * sale_price - float(before.get("worker_wage_cents_per_minute", 0.0)) * 60.0
		var after_net := float(after.get("rate_per_second", 0.0)) * 3600.0 * sale_price - float(after.get("worker_wage_cents_per_minute", 0.0)) * 60.0
		var increment := after_net - before_net
		rows.append({
			"worker_id":worker_id, "name":str(worker.get("name", worker_id)),
			"owned":int(GameMath.site(p, site).get("workers", {}).get(worker_id, 0)),
			"cost_cents":int(quote.get("cost_cents", 0)),
			"net_increment_cents_per_hour":increment,
			"payback_hours":float(quote.get("cost_cents", 0)) / increment if increment > 0.0 else null,
			"quote_available":bool(quote.get("ok", false))
		})
	return {
		"site":site, "resource":resource, "catalog_sale_price_cents":sale_price,
		"current_net_at_catalog_price_cents_per_hour":float(metrics.get("rate_per_second", 0.0)) * 3600.0 * sale_price - float(metrics.get("worker_wage_cents_per_minute", 0.0)) * 60.0,
		"next_worker_quotes":rows,
		"basis":"Catalog sale value less wages; not guaranteed cash income or storage-aware.",
		"currency":"money_cents"
	}


static func _market_added_value() -> Dictionary:
	var recipes: Array = []
	for record in GameMath.records("recipes"):
		recipes.append({
			"id":str(record.get("id", "")), "output":str(record.get("output", "")),
			"quantity":int(record.get("quantity", 1)), "inputs_json":str(record.get("inputs_json", "{}")),
			"output_sale_cents":int(record.get("output_sale_cents", 0)),
			"cash_cost_cents":int(record.get("cash_cost_cents", 0)),
			"added_margin_cents":int(record.get("added_margin_cents", 0)),
			"production_line":str(record.get("production_line", ""))
		})
	return {"recipes":recipes, "currency":"money_cents", "basis":"Canonical recipe and sale-value catalog; no transactions are created."}


static func _horizon_value_comparison(p: Dictionary) -> Dictionary:
	var rows: Array = []
	for site in GameMath.SITES:
		if not GameMath.unlocked(p, site):
			continue
		var max_horizon := int(GameMath.site(p, site).get("horizon", 0))
		var output_item := str(GameMath.OUTPUTS[site])
		var sale_price := int(GameMath.record("resources", output_item).get("sale_price_cents", 0))
		for horizon in range(max_horizon + 1):
			var future: Dictionary = p.duplicate(true)
			var future_site: Dictionary = GameMath.site(future, site)
			future_site["horizon"] = horizon
			var metrics: Dictionary = ECONOMY.metrics(future, site)
			var gross := float(metrics.get("rate_per_second", 0.0)) * 3600.0 * sale_price
			var wages := float(metrics.get("worker_wage_cents_per_minute", 0.0)) * 60.0
			rows.append({
				"site":site, "horizon":horizon, "resource":output_item,
				"rate_per_second":float(metrics.get("rate_per_second", 0.0)),
				"gross_catalog_value_cents_per_hour":gross,
				"wage_cents_per_hour":wages,
				"net_catalog_value_cents_per_hour":gross-wages
			})
	return {"horizons":rows, "currency":"money_cents", "basis":"Currently open horizons only; catalog-price gross value less worker wages."}


static func _reserve_items(p: Dictionary, id: String, args: Dictionary) -> Dictionary:
	var token := str(args.get("token", "research:" + id + ":reserve"))
	var prefix := "research:" + id + ":"
	var game := GameMath.game(p)
	var reservations: Dictionary = game["reservations"]
	if not token.begins_with(prefix):
		return GameMath.fail("Резервный токен должен принадлежать этому research-узлу")
	if bool(args.get("release", false)):
		if not reservations.has(token):
			return GameMath.fail("Резерв не найден")
		reservations.erase(token)
		return {"ok":true, "message":"Резерв снят", "token":token}
	if reservations.has(token):
		return GameMath.fail("Этот резерв уже существует")
	var items: Variant = args.get("items", {})
	if not items is Dictionary or items.is_empty():
		return GameMath.fail("Резерв требует список ресурсов")
	var clean: Dictionary = {}
	for raw_resource in items:
		var amount: Variant = items[raw_resource]
		var resource := str(raw_resource)
		if typeof(amount) != TYPE_INT or int(amount) < 0 or GameMath.record("resources", resource).is_empty():
			return GameMath.fail("Количество или тип ресурса в резерве некорректны")
		if int(amount) > GameMath.free_amount(p, resource):
			return GameMath.fail("Недостаточно свободного ресурса для резерва: " + resource)
		clean[resource] = int(amount)
	reservations[token] = clean
	return {"ok":true, "message":"Существующий ресурс зарезервирован без списания", "token":token, "items":clean.duplicate(true)}

static func _set_cash_reserve(p: Dictionary, id: String, args: Dictionary) -> Dictionary:
	var value: Variant = args.get("amount_cents", -1)
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)) or float(value) < 0.0 or float(value) != floorf(float(value)):
		return GameMath.fail("Резерв денег задаётся целым неотрицательным числом центов")
	var runtime: Dictionary = GameMath.game(p)["research_runtime"]
	var reserves: Dictionary = runtime["cash_reserves"]
	var already_reserved := 0
	for key in reserves:
		if str(key) != id:
			already_reserved += int(reserves[key])
	var amount := int(value)
	if already_reserved + amount > int(p.get("money_cents", 0)):
		return GameMath.fail("Сумма резервов превышает текущий баланс")
	if amount == 0:
		reserves.erase(id)
	else:
		reserves[id] = amount
	return {"ok":true, "message":"Бюджетный резерв сохранён, деньги не списаны", "reserved_cents":amount, "spendable_before_core_hook":maxi(0, int(p.get("money_cents", 0)) - already_reserved - amount), "spending_hook_required":true}

static func _preset(p: Dictionary, id: String, node: Dictionary, args: Dictionary) -> Dictionary:
	var operation := str(args.get("operation", ""))
	var slot := int(args.get("slot", 0))
	var slots := int(node.get("preset_slots", 1))
	if slot < 0 or slot >= slots:
		return GameMath.fail("Номер пресета вне открытого диапазона")
	var runtime: Dictionary = GameMath.game(p)["research_runtime"]
	var presets: Dictionary = runtime["presets"]
	if not presets.has(id):
		presets[id] = {}
	var node_presets: Dictionary = presets[id]
	match operation:
		"save":
			var settings: Variant = args.get("settings", _current_settings(p))
			if not settings is Dictionary:
				return GameMath.fail("Пресет хранит только словарь настроек")
			var sanitized := _sanitize_settings(settings, str(node.get("preset_kind", "settings")))
			if not bool(sanitized.get("ok", false)):
				return GameMath.fail(str(sanitized.get("message", "Некорректные настройки")))
			node_presets[str(slot)] = sanitized["settings"]
			runtime["presets"][id] = node_presets
			return {"ok":true, "message":"Настройки сохранены; уровни, инвентарь и ресурсы не входят в пресет", "slot":slot, "settings":sanitized["settings"].duplicate(true)}
		"load":
			if not node_presets.has(str(slot)):
				return GameMath.fail("Пустой слот пресета")
			var settings: Dictionary = node_presets[str(slot)].duplicate(true)
			return _apply_preset(p, settings)
		_:
			return GameMath.fail("Операция пресета должна быть save или load")

static func _current_settings(p: Dictionary) -> Dictionary:
	var g := GameMath.game(p)
	var settings: Dictionary = {"network_mode":str(g.get("network", {}).get("mode", "balanced")), "autosell":bool(g.get("network", {}).get("autosell", false))}
	var extraction: Dictionary = g.get("extraction", {})
	if extraction.has("pd"):
		settings["pd_lens_id"] = str(extraction["pd"].get("lens_id", ""))
	if extraction.has("ir"):
		settings["ir_strategy_id"] = str(extraction["ir"].get("strategy_id", ""))
	return settings

static func _sanitize_settings(settings: Dictionary, preset_kind: String) -> Dictionary:
	var clean: Dictionary = {}
	for raw_key in settings:
		var key := str(raw_key)
		if not PRESET_SETTING_KEYS.has(key):
			return {"ok":false, "message":"Пресет не может хранить поле " + key}
		var value: Variant = settings[raw_key]
		if key == "recipe_ids":
			if preset_kind != "recipe_chain" or not value is Array or value.is_empty() or value.size() > 5:
				return {"ok":false, "message":"План очереди содержит от 1 до 5 рецептов"}
			for recipe_id in value:
				if GameMath.record("recipes", str(recipe_id)).is_empty():
					return {"ok":false, "message":"В пресете указан неизвестный рецепт"}
			clean[key] = value.duplicate(true)
		elif key in ["line", "count"]:
			if typeof(value) != TYPE_INT:
				return {"ok":false, "message":"Параметр очереди должен быть целым"}
			clean[key] = value
		elif typeof(value) in [TYPE_STRING, TYPE_BOOL, TYPE_INT, TYPE_FLOAT] and (typeof(value) not in [TYPE_FLOAT] or is_finite(float(value))):
			clean[key] = value
		else:
			return {"ok":false, "message":"Пресет принимает только скалярные настройки"}
	if clean.has("network_mode") and not ["balanced", "income", "build"].has(str(clean["network_mode"])):
		return {"ok":false, "message":"Неизвестный режим сети"}
	return {"ok":true, "settings":clean}

static func _apply_preset(p: Dictionary, settings: Dictionary) -> Dictionary:
	if settings.has("pd_lens_id") and (not GameMath.unlocked(p, "pd") or _find_id(SITES.lens_definitions(), str(settings["pd_lens_id"])).is_empty()):
		return GameMath.fail("Pd линзу нельзя восстановить на закрытом участке или для неизвестного типа")
	if settings.has("ir_strategy_id") and (not GameMath.unlocked(p, "ir") or _find_id(SITES.strategy_definitions(), str(settings["ir_strategy_id"])).is_empty()):
		return GameMath.fail("Ir стратегию нельзя восстановить на закрытом участке или для неизвестного типа")
	if settings.has("network_mode") or settings.has("autosell"):
		var net: Dictionary = GameMath.game(p).get("network", {})
		var applied := ECONOMY.act(p, "network", {"mode":str(settings.get("network_mode", net.get("mode", "balanced"))), "autosell":settings.get("autosell", net.get("autosell", false))})
		if not bool(applied.get("ok", false)):
			return applied
	if settings.has("pd_lens_id"):
		var pd_result := SITES.act(p, "select_lens", {"site":"pd", "lens_id":str(settings["pd_lens_id"])})
		if not bool(pd_result.get("ok", false)):
			return pd_result
	if settings.has("ir_strategy_id"):
		var ir_result := SITES.act(p, "set_strategy", {"site":"ir", "strategy_id":str(settings["ir_strategy_id"])})
		if not bool(ir_result.get("ok", false)):
			return ir_result
	if settings.has("recipe_ids"):
		var queued := _queue_recipe_chain(p, {"recipe_ids":settings["recipe_ids"], "line":int(settings.get("line", 0)), "count":int(settings.get("count", 1))})
		if not bool(queued.get("ok", false)):
			return queued
	return {"ok":true, "message":"Только допустимые настройки восстановлены; производственные планы оплачены по обычному бюджету", "settings":settings.duplicate(true)}

static func _queue_recipe_chain(p: Dictionary, args: Dictionary) -> Dictionary:
	var ids: Variant = args.get("recipe_ids", [])
	var line_index := int(args.get("line", 0))
	var count := int(args.get("count", 1))
	if not ids is Array or ids.is_empty() or ids.size() > 5 or count < 1 or count > 100 or line_index < 0 or line_index >= 5:
		return GameMath.fail("Нужны 1–5 рецептов, линия 0–4 и количество 1–100")
	ECONOMY.ensure(p)
	var factory: Array = GameMath.game(p)["factory"]
	var line: Dictionary = factory[line_index]
	var queued_units := int(line.get("active", {}).get("units_remaining", 0))
	for job in line.get("queue", []):
		queued_units += int(job.get("units_remaining", 0))
	if queued_units + ids.size() * count > 500:
		return GameMath.fail("Недостаточно места в реальной очереди")
	var totals: Dictionary = {}
	var cost_total := 0
	var requests: Array[Dictionary] = []
	for raw_id in ids:
		var recipe_id := str(raw_id)
		var recipe := GameMath.record("recipes", recipe_id)
		if recipe.is_empty():
			return GameMath.fail("Рецепт не найден: " + recipe_id)
		var output := str(recipe.get("output", ""))
		var site := "pd" if output.begins_with("pd_") else "ir" if output.begins_with("ir_") else "fe"
		var quote := ECONOMY.quote(p, site, "recipe", recipe_id, count)
		if not bool(quote.get("ok", false)):
			return GameMath.fail(str(quote.get("message", "Рецепт недоступен")))
		cost_total += int(quote.get("cost_cents", 0))
		for resource in quote.get("inputs", {}):
			totals[str(resource)] = int(totals.get(str(resource), 0)) + int(quote["inputs"][resource])
		requests.append({"id":recipe_id, "count":count})
	if cost_total > int(p.get("money_cents", 0)):
		return GameMath.fail("Недостаточно гелионов на весь план")
	for resource in totals:
		if GameMath.free_amount(p, str(resource)) < int(totals[resource]):
			return GameMath.fail("Недостаточно общего сырья для плана: " + str(resource))
	var results: Array[Dictionary] = []
	for request in requests:
		var result := ECONOMY.act(p, "queue", {"recipe":str(request["id"]), "line":line_index, "count":int(request["count"])})
		if not bool(result.get("ok", false)):
			return GameMath.fail("План предварительно проверен, но реальная очередь отклонила рецепт: " + str(result.get("message", "")))
		results.append(result)
	return {"ok":true, "message":"Все рецепты поставлены в одну реальную производственную линию", "line":line_index, "jobs":results, "inputs_spent":totals, "cash_spent_cents":cost_total}

static func _set_preference(p: Dictionary, id: String, node: Dictionary, args: Dictionary) -> Dictionary:
	var expected := str(node.get("preference_key", "value"))
	var field := str(args.get("field", expected))
	if field != expected:
		return GameMath.fail("Недопустимое поле настройки")
	var value: Variant = args.get("value", null)
	if value == null or (typeof(value) not in [TYPE_STRING, TYPE_BOOL, TYPE_INT, TYPE_FLOAT]) or (typeof(value) == TYPE_FLOAT and not is_finite(float(value))):
		return GameMath.fail("Настройка должна быть скалярным значением")
	var options: Array = node.get("options", [])
	if not options.is_empty() and not options.has(value) and not options.has(str(value)):
		return GameMath.fail("Такого варианта нет в настройке")
	var runtime: Dictionary = GameMath.game(p)["research_runtime"]
	if not runtime["preferences"].has(id):
		runtime["preferences"][id] = {}
	runtime["preferences"][id][field] = value
	return {"ok":true, "message":"Настройка сохранена; игровой потребитель ещё требует подключения", "id":id, "field":field, "value":value, "core_hook_required":true}

static func _archive_current(p: Dictionary, id: String, node: Dictionary) -> Dictionary:
	var source := str(node.get("archive_source", ""))
	var data: Dictionary
	if source == "ir_campaign":
		data = GameMath.game(p).get("extraction", {}).get("ir", {}).duplicate(true)
		if data.is_empty() or data.get("campaign", {}).is_empty():
			return GameMath.fail("Нет реальной Ir кампании для архива")
	else:
		return GameMath.fail("Источник архива не подключён")
	var runtime: Dictionary = GameMath.game(p)["research_runtime"]
	var archive: Dictionary = runtime["archive"]
	if archive.has(id):
		return GameMath.fail("Эта архивная запись уже сохранена")
	archive[id] = {"source":source, "snapshot":data}
	return {"ok":true, "message":"Сохранён снимок существующего состояния без выдачи ресурсов", "archive_id":id}

static func _complete_task(p: Dictionary, id: String, node: Dictionary) -> Dictionary:
	var runtime: Dictionary = GameMath.game(p)["research_runtime"]
	var completed: Dictionary = runtime["tasks"]
	if bool(completed.get(id, false)):
		return GameMath.fail("Одноразовое задание уже выполнено")
	if not _task_satisfied(p, str(node.get("condition", ""))):
		return GameMath.fail("Условия факультативного задания ещё не выполнены")
	var reward: Dictionary = node.get("reward", {})
	var points := int(reward.get("research_points", 0))
	if points < 0:
		return GameMath.fail("Некорректная награда")
	p["research_points"] = int(p.get("research_points", 0)) + points
	completed[id] = true
	var archive: Dictionary = runtime["archive"]
	archive[id] = {"kind":"optional_research_task", "condition":str(node.get("condition", "")), "reward_research_points":points}
	return {"ok":true, "message":"Факультативное задание подтверждено один раз по реальным игровым условиям", "id":id, "reward_research_points":points}

static func _task_satisfied(p: Dictionary, condition: String) -> bool:
	var g := GameMath.game(p)
	var progression: Dictionary = g.get("progression", {})
	var geology: Dictionary = progression.get("geology", {})
	var discoveries: Dictionary = geology.get("discoveries", {})
	var stats: Dictionary = g.get("stats", {})
	match condition:
		"ir_output": return float(stats.get("ir_core_mined", 0.0)) > 0.0
		"team_roles": return _worker_count(p, "iron_miner") > 0 and _worker_count(p, "iron_hauler") > 0
		"fe_peak_600": return int(GameMath.site(p, "fe").get("peak", 0)) >= 600
		"registry_anomaly": return bool(discoveries.get("registry_anomaly", false))
		"deep_geology_signal": return bool(discoveries.get("deep_geology_signal", false))
		"geology_report": return not geology.get("reports", []).is_empty()
		"pd_cycle": return int(g.get("extraction", {}).get("pd", {}).get("cycles_completed", 0)) >= 1
		"pd_two_cycles": return int(g.get("extraction", {}).get("pd", {}).get("cycles_completed", 0)) >= 2
		"story_a20": return bool(progression.get("story_done", {}).get("A20", false))
		"ir_campaign": return int(g.get("extraction", {}).get("ir", {}).get("campaigns_completed", 0)) >= 1
	return false

static func _worker_count(p: Dictionary, worker_id: String) -> int:
	for site in GameMath.SITES:
		if int(GameMath.site(p, site).get("workers", {}).get(worker_id, 0)) > 0:
			return int(GameMath.site(p, site).get("workers", {}).get(worker_id, 0))
	return 0

static func _current_level_map(p: Dictionary, catalog: String) -> Dictionary:
	return GameMath.game(p).get("progression", {}).get(catalog, {})

static func _owned_rank(p: Dictionary, id: String) -> int:
	return int(_current_level_map(p, "mastery" if id.contains("_SK") else "research").get(id, 0))

static func _node(id: String) -> Dictionary:
	var catalog := "mastery" if id.contains("_SK") else "research"
	return _config().get(catalog, {}).get(id, {}).duplicate(true)

static func _find_id(rows: Array, id: String) -> Dictionary:
	for row in rows:
		if str(row.get("id", "")) == id:
			return row
	return {}

static func _ensure(p: Dictionary) -> void:
	var g := GameMath.game(p)
	if not g.has("progression") or typeof(g.get("progression")) != TYPE_DICTIONARY:
		g["progression"] = {}
	var progression: Dictionary = g["progression"]
	for key in ["research", "mastery"]:
		if not progression.get(key, {}) is Dictionary:
			progression[key] = {}
	if not g.has("research_runtime") or typeof(g.get("research_runtime")) != TYPE_DICTIONARY:
		g["research_runtime"] = {}
	var runtime: Dictionary = g["research_runtime"]
	for key in ["owned", "features", "preferences", "presets", "cash_reserves", "tasks", "archive"]:
		if not runtime.has(key) or typeof(runtime.get(key)) != TYPE_DICTIONARY:
			runtime[key] = {}

static func _config() -> Dictionary:
	if not _config_cache.is_empty():
		return _config_cache
	var file := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		_config_cache = parsed
	return _config_cache
