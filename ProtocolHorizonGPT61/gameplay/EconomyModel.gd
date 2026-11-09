class_name EarthEconomy
extends RefCounted

const SITE_KEYS := ["fe", "pd", "ir"]
const SITE_IDS := {"fe":"site_earth_fe_17", "pd":"site_earth_pd_7", "ir":"site_earth_ir_9"}
const FACTORY_LINE_COUNT := 5
const MAX_PRICE_CENTS := 9000000000000000
const EPSILON := 0.0000001
const PROPOSAL_PATH := "res://data/proposals/economy.json"

static var _proposal_loaded := false
static var _proposal: Dictionary = {}

static func ensure(p: Dictionary) -> void:
	if not p.has("money_cents"):
		p["money_cents"] = 0
	if not p.has("inventory") or not p["inventory"] is Dictionary:
		p["inventory"] = {}
	GameMath.game(p)
	for key in SITE_KEYS:
		var site_data: Dictionary = GameMath.site(p, key)
		for field in ["upgrades", "machines", "workers"]:
			if not site_data.has(field) or not site_data[field] is Dictionary:
				site_data[field] = {}
		if not site_data.has("fraction"):
			site_data["fraction"] = 0.0
		if not site_data.has("wage_fraction"):
			site_data["wage_fraction"] = 0.0
	var game: Dictionary = GameMath.game(p)
	if not game.has("factory") or not game["factory"] is Array:
		game["factory"] = []
	var factory: Array = game["factory"]
	while factory.size() < FACTORY_LINE_COUNT:
		factory.append(_empty_line())
	if factory.size() > FACTORY_LINE_COUNT:
		factory.resize(FACTORY_LINE_COUNT)
	for index in FACTORY_LINE_COUNT:
		var line: Dictionary = factory[index] if factory[index] is Dictionary else _empty_line()
		if not line.has("queue") or not line["queue"] is Array:
			line["queue"] = []
		if not line.has("active") or not line["active"] is Dictionary:
			line["active"] = {}
		if not line.has("pending") or not line["pending"] is Dictionary:
			line["pending"] = {}
		factory[index] = line
	if not game.has("network") or not game["network"] is Dictionary:
		game["network"] = {"mode":"balanced", "autosell":false}
	var network: Dictionary = game["network"]
	if not ["balanced", "income", "build"].has(str(network.get("mode", ""))):
		network["mode"] = "balanced"
	if not network.has("autosell"):
		network["autosell"] = false
	if not network["autosell"] is bool:
		network["autosell"] = false
	_sync_bonuses(p)

static func definitions(site: String, kind: String) -> Array:
	var site_key := _site_key(site)
	var kind_key := _kind_key(kind)
	if site_key.is_empty() or not ["upgrade", "machine", "worker"].has(kind_key):
		return []
	var site_data: Dictionary = _load_proposal().get("sites", {}).get(site_key, {})
	var result: Array = site_data.get(kind_key + "s", []).duplicate(true)
	for definition in result:
		definition["max_level"] = _kind_limit(site_key, kind_key)
	return result

static func act(p: Dictionary, action: String, args: Dictionary) -> Dictionary:
	ensure(p)
	match action:
		"tap":
			return _tap(p, str(args.get("site", "fe")))
		"sell":
			return _sell_action(p, str(args.get("resource", "iron_ore")), int(args.get("amount", -1)))
		"sell_all":
			return _sell_all(p)
		"buy":
			return _buy(p, str(args.get("site", "fe")), str(args.get("kind", "")), str(args.get("id", "")), int(args.get("count", 1)))
		"queue":
			return _queue(p, str(args.get("recipe", args.get("id", ""))), int(args.get("line", -1)), int(args.get("count", 1)))
		"horizon":
			return _set_horizon(p, str(args.get("site", "fe")), int(args.get("index", -1)))
		"reserve":
			return _reserve(p, str(args.get("token", "")), args.get("items", {}))
		"unreserve":
			return _unreserve(p, str(args.get("token", "")))
		"network":
			return _set_network(p, str(args.get("mode", "balanced")), args.get("autosell", null))
		_:
			return GameMath.fail("Неизвестное экономическое действие")

static func quote(p: Dictionary, site: String, kind: String, id: String, count: int) -> Dictionary:
	ensure(p)
	var site_key := _site_key(site)
	var kind_key := _kind_key(kind)
	if site_key.is_empty() or not GameMath.unlocked(p, SITE_IDS[site_key]):
		return _quote_failure("Участок закрыт")
	if kind_key == "recipe":
		return _quote_recipe(p, site_key, id, count)
	if not ["upgrade", "machine", "worker"].has(kind_key):
		return _quote_failure("Неизвестный тип покупки")
	var definition := _definition(site_key, kind_key, id)
	if definition.is_empty():
		return _quote_failure("Покупка не найдена")
	var site_data: Dictionary = GameMath.site(p, site_key)
	var levels: Dictionary = site_data[kind_key + "s"]
	var current := int(levels.get(id, 0))
	var maximum := int(definition.get("max_level", _kind_limit(site_key, kind_key)))
	var requested := count
	if requested < 0:
		return _quote_failure("Количество должно быть положительным или MAX")
	var maximum_affordable := _maximum_affordable(p, site_key, kind_key, id, definition, current, maximum)
	if requested == 0:
		requested = maximum_affordable
	if requested == 0:
		return {"ok":false, "message":"Недостаточно гелионов или достигнут предел", "site":site_key, "kind":kind_key, "id":id, "count":0, "max_affordable":maximum_affordable, "cost_cents":0}
	if current + requested > maximum:
		return {"ok":false, "message":"Достигнут предел уровня", "site":site_key, "kind":kind_key, "id":id, "count":requested, "max_level":maximum, "max_affordable":maximum_affordable, "cost_cents":0}
	var total := 0
	for level_offset in requested:
		var price := _level_cost(definition, current + level_offset, _price_discount(p, site_key))
		if price > MAX_PRICE_CENTS - total:
			total = MAX_PRICE_CENTS
			break
		total += price
	var level_after := current + requested
	var result := {"ok":int(p["money_cents"]) >= total, "message":"Готово" if int(p["money_cents"]) >= total else "Недостаточно гелионов", "site":site_key, "kind":kind_key, "id":id, "count":requested, "current_level":current, "level_after":level_after, "max_level":maximum, "max_affordable":maximum_affordable, "cost_cents":total, "price_cents":total}
	var future: Dictionary = p.duplicate(true)
	var future_levels: Dictionary = GameMath.site(future, site_key)[kind_key + "s"]
	future_levels[id] = level_after
	_sync_bonuses(future)
	result["effect_before"] = _metrics_snapshot(metrics(p, site_key))
	result["effect_after"] = _metrics_snapshot(metrics(future, site_key))
	return result

static func metrics(p: Dictionary, site: String) -> Dictionary:
	ensure(p)
	var site_key := _site_key(site)
	if site_key.is_empty():
		return {}
	var site_data: Dictionary = GameMath.site(p, site_key)
	var base_rate := float(_load_proposal().get("sites", {}).get(site_key, {}).get("base_rate_per_second", 0.0))
	if not GameMath.unlocked(p, SITE_IDS[site_key]):
		base_rate = 0.0
	var direct_worker_rate := 0.0
	var wage_rate := 0.0
	var worker_effects: Dictionary = {}
	for worker in definitions(site_key, "worker"):
		var count := int(site_data["workers"].get(str(worker["id"]), 0))
		if count <= 0 or not GameMath.unlocked(p, SITE_IDS[site_key]):
			continue
		direct_worker_rate += float(worker.get("rate_per_worker", 0.0)) * count
		wage_rate += float(worker.get("wage_cents_per_minute", 0.0)) * count
		for effect in worker.get("effects_per_worker", {}):
			worker_effects[effect] = float(worker_effects.get(effect, 0.0)) + float(worker["effects_per_worker"][effect]) * count
	var output_bonus := GameMath.bonus(p, "output", site_key) + float(worker_effects.get("output", 0.0))
	var horizon := int(site_data.get("horizon", 0))
	var deep_bonus := GameMath.bonus(p, "deep_output", site_key) + float(worker_effects.get("deep_output", 0.0))
	if horizon > 0:
		output_bonus += deep_bonus
	var total_rate := (base_rate + direct_worker_rate) * maxf(0.0, 1.0 + output_bonus)
	var tap_base := float(_load_proposal().get("sites", {}).get(site_key, {}).get("tap_base", 0.0))
	var tap_bonus := GameMath.bonus(p, "tap", site_key) + float(worker_effects.get("tap", 0.0))
	var crit := clampf(GameMath.bonus(p, "crit", site_key) + float(worker_effects.get("crit", 0.0)), 0.0, 0.75)
	var weak := clampf(GameMath.bonus(p, "weak", site_key) + float(worker_effects.get("weak", 0.0)), 0.0, 0.75)
	var wage_bonus := GameMath.bonus(p, "wage", site_key) + float(worker_effects.get("wage", 0.0))
	wage_rate /= maxf(0.25, 1.0 + wage_bonus)
	var speed_bonus := GameMath.bonus(p, "speed", site_key) + float(worker_effects.get("speed", 0.0))
	var storage := GameMath.capacity(p)
	return {
		"site":site_key,
		"unlocked":GameMath.unlocked(p, SITE_IDS[site_key]),
		"resource":GameMath.OUTPUTS[site_key],
		"base_rate_per_second":base_rate,
		"worker_rate_per_second":direct_worker_rate * maxf(0.0, 1.0 + output_bonus),
		"rate_per_second":total_rate,
		"output_multiplier":maxf(0.0, 1.0 + output_bonus),
		"tap_per_hit":tap_base * maxf(0.0, 1.0 + tap_bonus) * (1.0 + crit) * (1.0 + weak),
		"crit_chance":crit,
		"weak_chance":weak,
		"worker_wage_cents_per_minute":wage_rate,
		"storage_capacity":storage,
		"stored":GameMath.stored(p),
		"free_inventory":GameMath.free_amount(p, GameMath.OUTPUTS[site_key]),
		"horizon":horizon,
		"average_upgrade_level":_average_upgrade_level(site_data),
		"speed_multiplier":1.0 + speed_bonus,
		"offline_bonus":GameMath.bonus(p, "offline", site_key),
		"price_discount":_price_discount(p, site_key),
		"wage_fraction":float(site_data.get("wage_fraction", 0.0))
	}

static func advance(p: Dictionary, seconds: float) -> void:
	ensure(p)
	var remaining := maxf(0.0, seconds)
	var iterations := 0
	while remaining > EPSILON and iterations < 50000:
		iterations += 1
		_start_factory_jobs(p)
		var segment := remaining
		for line in GameMath.game(p)["factory"]:
			var active: Dictionary = line["active"]
			if not active.is_empty():
				var until_done := float(active.get("seconds_left", active.get("seconds_per_unit", 0.0)))
				if until_done > EPSILON:
					segment = minf(segment, until_done)
		if segment <= EPSILON:
			segment = remaining
		var paid_seconds := _charge_wages(p, segment)
		_advance_iron(p, segment, paid_seconds)
		for line_index in FACTORY_LINE_COUNT:
			_advance_factory_line(p, line_index, segment)
		remaining -= segment
		if remaining < EPSILON:
			remaining = 0.0

static func _tap(p: Dictionary, site: String) -> Dictionary:
	var site_key := _site_key(site)
	if site_key != "fe" or not GameMath.unlocked(p, SITE_IDS["fe"]):
		return GameMath.fail("Ручная добыча доступна в шахте Fe")
	var stats: Dictionary = metrics(p, site_key)
	var site_data: Dictionary = GameMath.site(p, site_key)
	var exact := float(site_data.get("tap_fraction", 0.0)) + float(stats["tap_per_hit"])
	var requested := int(floor(exact + EPSILON))
	if requested <= 0:
		site_data["tap_fraction"] = exact
		return GameMath.ok("Удар не дал целой единицы руды")
	if GameMath.capacity(p) - GameMath.stored(p) < requested:
		return GameMath.fail("Склад заполнен")
	var accepted := GameMath.add(p, "iron_ore", requested)
	if accepted != requested:
		return GameMath.fail("Склад заполнен")
	site_data["tap_fraction"] = exact - requested
	_record_mined(p, site_key, float(accepted))
	GameMath.stat(p, "taps")
	_autosell_resource(p, "iron_ore")
	return {"ok":true, "message":"Добыто железо", "resource":"iron_ore", "amount":accepted, "money_cents":int(p["money_cents"])}

static func _sell_action(p: Dictionary, resource: String, amount: int) -> Dictionary:
	if amount == 0 or amount < -1:
		return GameMath.fail("Количество продажи должно быть положительным или -1 для всего свободного запаса")
	var record := _resource_record(resource)
	if record.is_empty() or str(record.get("sale_price_cents", "")).is_empty():
		return GameMath.fail("Этот ресурс нельзя продать")
	var available := GameMath.free_amount(p, resource)
	var quantity := available if amount == -1 else amount
	if quantity <= 0 or quantity > available:
		return GameMath.fail("Недостаточно свободного ресурса")
	var price := int(record["sale_price_cents"])
	var proceeds := quantity * price
	if proceeds > MAX_PRICE_CENTS - int(p["money_cents"]):
		return GameMath.fail("Баланс превысит безопасный предел")
	p["inventory"][resource] = int(p["inventory"].get(resource, 0)) - quantity
	p["money_cents"] = int(p["money_cents"]) + proceeds
	GameMath.stat(p, "sold:" + resource, quantity)
	return {"ok":true, "message":"Продано", "resource":resource, "amount":quantity, "proceeds_cents":proceeds, "money_cents":int(p["money_cents"])}

static func _sell_all(p: Dictionary) -> Dictionary:
	var sold_count := 0
	var proceeds := 0
	var registry := GameMath.registry()
	if registry == null:
		return GameMath.fail("Каталог ресурсов недоступен")
	for record in registry.get_records(&"resources"):
		var resource := str(record.get("id", ""))
		if str(record.get("sale_price_cents", "")).is_empty():
			continue
		var amount := GameMath.free_amount(p, resource)
		if amount <= 0:
			continue
		var result := _sell_action(p, resource, -1)
		if bool(result.get("ok", false)):
			sold_count += amount
			proceeds += int(result.get("proceeds_cents", 0))
	return {"ok":true, "message":"Свободные материалы проданы", "amount":sold_count, "proceeds_cents":proceeds, "money_cents":int(p["money_cents"])}

static func _buy(p: Dictionary, site: String, kind: String, id: String, count: int) -> Dictionary:
	var result := quote(p, site, kind, id, count)
	if not bool(result.get("ok", false)):
		return GameMath.fail(str(result.get("message", "Покупка недоступна")))
	var site_key := _site_key(site)
	var kind_key := _kind_key(kind)
	var level_map: Dictionary = GameMath.site(p, site_key)[kind_key + "s"]
	if not GameMath.pay(p, int(result["cost_cents"])):
		return GameMath.fail("Недостаточно гелионов")
	level_map[id] = int(level_map.get(id, 0)) + int(result["count"])
	_sync_bonuses(p)
	GameMath.stat(p, "purchases:" + kind_key, int(result["count"]))
	result["message"] = "Покупка выполнена"
	result["money_cents"] = int(p["money_cents"])
	return result

static func _queue(p: Dictionary, recipe_id: String, line_index: int, count: int) -> Dictionary:
	if count < 1 or count > 100:
		return GameMath.fail("За раз можно поставить от 1 до 100 изделий")
	if line_index < 0 or line_index >= FACTORY_LINE_COUNT:
		return GameMath.fail("Номер линии должен быть от 0 до 4")
	var recipe := _recipe_record(recipe_id)
	if recipe.is_empty():
		return GameMath.fail("Рецепт не найден")
	var recipe_site := _recipe_site(recipe)
	var result := quote(p, recipe_site, "recipe", recipe_id, count)
	if not bool(result.get("ok", false)):
		return GameMath.fail(str(result.get("message", "Рецепт недоступен")))
	var factory: Array = GameMath.game(p)["factory"]
	var line: Dictionary = factory[line_index]
	var queued_units := int(line.get("active", {}).get("units_remaining", 0))
	for job in line.get("queue", []):
		queued_units += int(job.get("units_remaining", 0))
	if queued_units + count > int(_load_proposal().get("factory", {}).get("max_queued_units_per_line", 500)):
		return GameMath.fail("Очередь линии заполнена")
	for resource in result["inputs"]:
		if GameMath.free_amount(p, str(resource)) < int(result["inputs"][resource]):
			return GameMath.fail("Недостаточно свободного сырья: " + str(resource))
	if int(p["money_cents"]) < int(result["cost_cents"]):
		return GameMath.fail("Недостаточно гелионов для производства")
	if not GameMath.pay(p, int(result["cost_cents"])):
		return GameMath.fail("Недостаточно гелионов для производства")
	for resource in result["inputs"]:
		if not GameMath.take(p, str(resource), int(result["inputs"][resource])):
			return GameMath.fail("Не удалось списать сырьё")
	var durations: Dictionary = _load_proposal().get("factory", {}).get("durations_seconds", {})
	var speed_bonus := float(metrics(p, recipe_site).get("speed_multiplier", 1.0)) - 1.0
	var seconds_per_unit := maxf(1.0, float(durations.get(recipe_id, 60.0)) / maxf(0.1, 1.0 + speed_bonus))
	line["queue"].append({"recipe_id":recipe_id, "output":str(recipe.get("output", "")), "output_quantity":int(recipe.get("quantity", 1)), "units_remaining":count, "seconds_per_unit":seconds_per_unit})
	factory[line_index] = line
	GameMath.stat(p, "queued:" + recipe_id, count)
	return {"ok":true, "message":"Партия оплачена и поставлена в очередь", "recipe":recipe_id, "line":line_index, "count":count, "cost_cents":int(result["cost_cents"]), "inputs":result["inputs"], "money_cents":int(p["money_cents"])}

static func _set_horizon(p: Dictionary, site: String, index: int) -> Dictionary:
	var site_key := _site_key(site)
	if site_key != "fe" or not GameMath.unlocked(p, SITE_IDS.get(site_key, "")):
		return GameMath.fail("Горизонты доступны в шахте Fe")
	var site_data: Dictionary = GameMath.site(p, site_key)
	var max_horizon := floori(_average_upgrade_level(site_data) / 100.0)
	if index < 0 or index > 10 or index > max_horizon:
		return GameMath.fail("Горизонт закрыт: требуется средний уровень %d" % (index * 100))
	site_data["horizon"] = index
	return {"ok":true, "message":"Горизонт выбран", "site":"fe", "index":index, "max_unlocked":max_horizon}

static func _reserve(p: Dictionary, token: String, items: Variant) -> Dictionary:
	if token.strip_edges().is_empty() or not items is Dictionary or items.is_empty():
		return GameMath.fail("Нужны уникальный токен и список ресурсов")
	var reservations: Dictionary = GameMath.game(p)["reservations"]
	if reservations.has(token):
		return GameMath.fail("Этот резерв уже существует")
	var normalized: Dictionary = {}
	for resource_value in items:
		var resource := str(resource_value)
		var amount := int(items[resource_value])
		if amount <= 0 or _resource_record(resource).is_empty():
			return GameMath.fail("Некорректный ресурс или количество в резерве")
		if GameMath.free_amount(p, resource) < amount:
			return GameMath.fail("Недостаточно свободного ресурса: " + resource)
		normalized[resource] = amount
	reservations[token] = normalized
	return {"ok":true, "message":"Резерв создан", "token":token, "items":normalized}

static func _unreserve(p: Dictionary, token: String) -> Dictionary:
	var reservations: Dictionary = GameMath.game(p)["reservations"]
	if not reservations.has(token):
		return GameMath.fail("Резерв не найден")
	reservations.erase(token)
	return {"ok":true, "message":"Резерв снят", "token":token}

static func _set_network(p: Dictionary, mode: String, autosell: Variant) -> Dictionary:
	if not ["balanced", "income", "build"].has(mode):
		return GameMath.fail("Режим сети должен быть balanced, income или build")
	if autosell != null and not autosell is bool:
		return GameMath.fail("Автопродажа должна быть включена или выключена")
	var network: Dictionary = GameMath.game(p)["network"]
	network["mode"] = mode
	if autosell != null:
		network["autosell"] = autosell
	return {"ok":true, "message":"Настройки сети обновлены", "mode":mode, "autosell":bool(network["autosell"])}

static func _quote_recipe(p: Dictionary, site: String, recipe_id: String, count: int) -> Dictionary:
	if count < 0:
		return _quote_failure("Количество должно быть положительным или MAX")
	var recipe := _recipe_record(recipe_id)
	if recipe.is_empty():
		return _quote_failure("Рецепт не найден")
	var recipe_site := _recipe_site(recipe)
	if recipe_site != site or not GameMath.unlocked(p, SITE_IDS[recipe_site]):
		return _quote_failure("Для рецепта нужен открытый участок " + recipe_site)
	var inputs_value := JSON.parse_string(str(recipe.get("inputs_json", "{}")))
	if not inputs_value is Dictionary:
		return _quote_failure("У рецепта повреждён список входов")
	var max_count := 100
	var cash_per_unit := int(recipe.get("cash_cost_cents", 0))
	var total_free: int = int(p["money_cents"]) / maxi(cash_per_unit, 1) if cash_per_unit > 0 else max_count
	max_count = mini(max_count, total_free)
	for resource in inputs_value:
		var needed := int(inputs_value[resource])
		if needed > 0:
			max_count = mini(max_count, GameMath.free_amount(p, str(resource)) / needed)
	var requested := count if count > 0 else max_count
	if requested <= 0:
		return {"ok":false, "message":"Недостаточно свободных входов или гелионов", "site":site, "kind":"recipe", "id":recipe_id, "count":0, "max_affordable":0, "cost_cents":0, "inputs":{}}
	if requested > 100 or requested > max_count:
		return {"ok":false, "message":"Недостаточно свободных входов или гелионов", "site":site, "kind":"recipe", "id":recipe_id, "count":requested, "max_affordable":max_count, "cost_cents":cash_per_unit * requested, "inputs":_scaled_inputs(inputs_value, requested)}
	return {"ok":true, "message":"Готово", "site":site, "kind":"recipe", "id":recipe_id, "count":requested, "max_affordable":max_count, "cost_cents":cash_per_unit * requested, "inputs":_scaled_inputs(inputs_value, requested), "output":str(recipe.get("output", "")), "output_quantity":int(recipe.get("quantity", 1)) * requested, "sale_price_cents":int(recipe.get("output_sale_cents", 0))}

static func _maximum_affordable(p: Dictionary, site: String, kind: String, id: String, definition: Dictionary, current: int, maximum: int) -> int:
	var capacity := mini(maximum - current, 1000 if kind != "worker" else 1000)
	var total := 0
	var affordable := 0
	for offset in maxi(0, capacity):
		var price := _level_cost(definition, current + offset, _price_discount(p, site))
		if price > int(p["money_cents"]) - total:
			break
		total += price
		affordable += 1
	return affordable

static func _level_cost(definition: Dictionary, current_level: int, discount: float) -> int:
	var base := maxf(100.0, float(definition.get("base_cost_cents", 100)))
	var growth := maxf(1.0, float(definition.get("growth", 1.0)))
	var raw := base * pow(growth, maxf(0.0, current_level)) * (1.0 - clampf(discount, 0.0, float(_load_proposal().get("purchase_price_discount_cap", 0.75))))
	if not is_finite(raw) or raw >= float(MAX_PRICE_CENTS):
		return MAX_PRICE_CENTS
	return maxi(100, int(ceil(raw / 100.0)) * 100)

static func _metrics_snapshot(value: Dictionary) -> Dictionary:
	return {"rate_per_second":value["rate_per_second"], "tap_per_hit":value["tap_per_hit"], "output_multiplier":value["output_multiplier"], "worker_wage_cents_per_minute":value["worker_wage_cents_per_minute"], "storage_capacity":value["storage_capacity"], "speed_multiplier":value["speed_multiplier"], "price_discount":value["price_discount"]}

static func _sync_bonuses(p: Dictionary) -> void:
	var domain: Dictionary = {}
	var storage_total := 0.0
	for site_key in SITE_KEYS:
		var site_data: Dictionary = GameMath.site(p, site_key)
		for kind in ["upgrade", "machine"]:
			var levels: Dictionary = site_data[kind + "s"]
			for definition in definitions(site_key, kind):
				var count := max(0, int(levels.get(str(definition["id"]), 0)))
				for effect in definition.get("effects_per_level", {}):
					var value := float(definition["effects_per_level"][effect]) * count
					if effect == "storage":
						storage_total += value
					else:
					var key := site_key + ":" + str(effect)
					 domain[key] = float(domain.get(key, 0.0)) + value
	domain["storage"] = storage_total
	GameMath.game(p)["bonuses"]["economy"] = domain

static func _charge_wages(p: Dictionary, seconds: float) -> float:
	var wage_rates: Dictionary = {}
	var total_rate := 0.0
	var total_fraction := 0.0
	for site_key in SITE_KEYS:
		var site_data: Dictionary = GameMath.site(p, site_key)
		var rate := float(metrics(p, site_key).get("worker_wage_cents_per_minute", 0.0)) / 60.0
		wage_rates[site_key] = rate
		total_rate += rate
		total_fraction += maxf(0.0, float(site_data.get("wage_fraction", 0.0)))
	if total_rate <= EPSILON:
		return seconds
	if int(p["money_cents"]) <= 0:
		for site_key in SITE_KEYS:
			GameMath.site(p, site_key)["wage_fraction"] = 0.0
		return 0.0
	var due_for_full := floori(total_fraction + total_rate * seconds + EPSILON)
	var paid_seconds := seconds
	if due_for_full > int(p["money_cents"]):
		var low := 0.0
		var high := seconds
		for _iteration in 48:
			var middle := (low + high) * 0.5
			if floori(total_fraction + total_rate * middle + EPSILON) <= int(p["money_cents"]):
				low = middle
			else:
				high = middle
		paid_seconds = low
	var accrued := total_fraction + total_rate * paid_seconds
	var due := mini(int(p["money_cents"]), floori(accrued + EPSILON))
	if due > 0:
		GameMath.pay(p, due)
	var fractional := maxf(0.0, accrued - due)
	for site_key in SITE_KEYS:
		var share := float(wage_rates[site_key]) / total_rate
		GameMath.site(p, site_key)["wage_fraction"] = fractional * share
	return paid_seconds

static func _advance_iron(p: Dictionary, seconds: float, paid_seconds: float) -> void:
	var site_key := "fe"
	if not GameMath.unlocked(p, SITE_IDS[site_key]):
		return
	var stats := metrics(p, site_key)
	var rate := float(stats["base_rate_per_second"]) * float(stats["output_multiplier"])
	var worker_rate := float(stats["worker_rate_per_second"])
	var site_data: Dictionary = GameMath.site(p, site_key)
	var exact := maxf(0.0, rate * seconds + worker_rate * paid_seconds) + float(site_data.get("fraction", 0.0))
	var requested := floori(exact + EPSILON)
	var free_capacity := maxi(0, GameMath.capacity(p) - GameMath.stored(p))
	if requested > 0 and free_capacity < requested and bool(GameMath.game(p)["network"].get("autosell", false)):
		_autosell_inventory(p)
		free_capacity = maxi(0, GameMath.capacity(p) - GameMath.stored(p))
	var accepted := mini(requested, free_capacity)
	if accepted > 0:
		GameMath.add(p, "iron_ore", accepted)
		_record_mined(p, site_key, float(accepted))
		GameMath.stat(p, "produced:iron_ore", accepted)
		_autosell_resource(p, "iron_ore")
	if accepted == requested:
		site_data["fraction"] = exact - requested
	else:
		site_data["fraction"] = 0.0

static func _start_factory_jobs(p: Dictionary) -> void:
	for index in FACTORY_LINE_COUNT:
		var line: Dictionary = GameMath.game(p)["factory"][index]
		if line["active"].is_empty() and not line["queue"].is_empty():
			line["active"] = line["queue"].pop_front()
			line["active"]["seconds_left"] = float(line["active"].get("seconds_per_unit", 60.0))

static func _advance_factory_line(p: Dictionary, index: int, seconds: float) -> void:
	var factory: Array = GameMath.game(p)["factory"]
	var line: Dictionary = factory[index]
	var pending: Dictionary = line["pending"]
	if not pending.is_empty():
		if not _deliver_factory_output(p, pending):
			return
		line["pending"] = {}
		_finish_factory_unit(line)
	var remaining := seconds
	var guard := 0
	while guard < 10000:
		guard += 1
		if line["active"].is_empty():
			if line["queue"].is_empty():
				break
			line["active"] = line["queue"].pop_front()
			line["active"]["seconds_left"] = float(line["active"].get("seconds_per_unit", 60.0))
		var active: Dictionary = line["active"]
		var seconds_left := float(active.get("seconds_left", active.get("seconds_per_unit", 60.0)))
		if seconds_left > remaining + EPSILON:
			active["seconds_left"] = seconds_left - remaining
			remaining = 0.0
			break
		remaining = maxf(0.0, remaining - seconds_left)
		var result := {"resource":str(active.get("output", "")), "quantity":int(active.get("output_quantity", 1))}
		if not _deliver_factory_output(p, result):
			line["pending"] = result
			active["seconds_left"] = 0.0
			break
		_finish_factory_unit(line)
		if remaining <= EPSILON:
			break
	factory[index] = line

static func _finish_factory_unit(line: Dictionary) -> void:
	var active: Dictionary = line["active"]
	if active.is_empty():
		return
	active["units_remaining"] = int(active.get("units_remaining", 1)) - 1
	if int(active["units_remaining"]) <= 0:
		line["active"] = {}
	else:
		active["seconds_left"] = float(active.get("seconds_per_unit", 60.0))

static func _deliver_factory_output(p: Dictionary, output: Dictionary) -> bool:
	var resource := str(output.get("resource", ""))
	var quantity := int(output.get("quantity", 0))
	if resource.is_empty() or quantity <= 0:
		return false
	if bool(GameMath.game(p)["network"].get("autosell", false)):
		_autosell_inventory(p)
	if GameMath.capacity(p) - GameMath.stored(p) < quantity:
		return false
	if GameMath.add(p, resource, quantity) != quantity:
		return false
	GameMath.stat(p, "produced:" + resource, quantity)
	_autosell_resource(p, resource)
	return true

static func _autosell_inventory(p: Dictionary) -> void:
	if not bool(GameMath.game(p)["network"].get("autosell", false)):
		return
	var registry := GameMath.registry()
	if registry == null:
		return
	for record in registry.get_records(&"resources"):
		var resource := str(record.get("id", ""))
		if not str(record.get("sale_price_cents", "")).is_empty():
			_autosell_resource(p, resource)

static func _autosell_resource(p: Dictionary, resource: String) -> void:
	var network: Dictionary = GameMath.game(p)["network"]
	if not bool(network.get("autosell", false)):
		return
	var record := _resource_record(resource)
	if record.is_empty() or str(record.get("sale_price_cents", "")).is_empty():
		return
	var mode := str(network.get("mode", "balanced"))
	var keep := 0
	if mode == "balanced":
		keep = int(_load_proposal().get("network", {}).get("balanced_keep", 25))
	elif mode == "build":
		var type := str(record.get("type", ""))
		keep = int(_load_proposal().get("network", {}).get("build_ore_keep", 250)) if type == "ore" else int(_load_proposal().get("network", {}).get("build_product_keep", 100))
	var free := GameMath.free_amount(p, resource)
	var excess := maxi(0, free - keep)
	if excess > 0:
		_sell_action(p, resource, excess)

static func _record_mined(p: Dictionary, site: String, amount: float) -> void:
	if amount <= 0.0:
		return
	var site_data: Dictionary = GameMath.site(p, site)
	site_data["mined"] = float(site_data.get("mined", 0.0)) + amount
	site_data["peak"] = maxi(int(site_data.get("peak", 0)), floori(float(site_data["mined"])))
	GameMath.stat(p, "mined:" + site, amount)
	if site == "fe":
		if not p.has("local") or not p["local"] is Dictionary:
			p["local"] = {}
		p["local"]["lifetime_peak"] = maxf(float(p["local"].get("lifetime_peak", 0.0)), float(site_data["mined"]))

static func _reserve_failure(message: String) -> Dictionary:
	return GameMath.fail(message)

static func _recipe_record(id: String) -> Dictionary:
	var registry := GameMath.registry()
	if registry == null:
		return {}
	return registry.get_record(&"recipes", id)

static func _resource_record(id: String) -> Dictionary:
	var registry := GameMath.registry()
	if registry == null:
		return {}
	return registry.get_record(&"resources", id)

static func _recipe_site(recipe: Dictionary) -> String:
	var output := str(recipe.get("output", ""))
	if output.begins_with("pd_"):
		return "pd"
	if output.begins_with("ir_"):
		return "ir"
	return "fe"

static func _scaled_inputs(inputs: Dictionary, count: int) -> Dictionary:
	var result: Dictionary = {}
	for resource in inputs:
		result[str(resource)] = int(inputs[resource]) * count
	return result

static func _kind_key(kind: String) -> String:
	if kind in ["upgrade", "upgrades"]:
		return "upgrade"
	if kind in ["machine", "machines"]:
		return "machine"
	if kind in ["worker", "workers", "profession", "professions"]:
		return "worker"
	return kind

static func _site_key(site: String) -> String:
	if site in SITE_KEYS:
		return site
	for key in SITE_IDS:
		if SITE_IDS[key] == site:
			return key
	return ""

static func _kind_limit(site: String, kind: String) -> int:
	var site_data: Dictionary = _load_proposal().get("sites", {}).get(site, {})
	if kind == "upgrade":
		return int(site_data.get("upgrade_max_level", 1000))
	if kind == "machine":
		return int(site_data.get("machine_max_level", 1000))
	return int(site_data.get("worker_max_count", 1000))

static func _definition(site: String, kind: String, id: String) -> Dictionary:
	for definition in definitions(site, kind):
		if str(definition.get("id", "")) == id:
			if not definition.has("max_level"):
				definition["max_level"] = _kind_limit(site, kind)
			return definition
	return {}

static func _price_discount(p: Dictionary, site: String) -> float:
	return minf(float(_load_proposal().get("purchase_price_discount_cap", 0.75)), maxf(0.0, GameMath.bonus(p, "price", site)))

static func _average_upgrade_level(site_data: Dictionary) -> float:
	var total := 0
	for definition in definitions("fe", "upgrade"):
		total += maxi(0, int(site_data.get("upgrades", {}).get(str(definition["id"]), 0)))
	return float(total) / 10.0

static func _empty_line() -> Dictionary:
	return {"queue":[], "active":{}, "pending":{}}

static func _quote_failure(message: String) -> Dictionary:
	return {"ok":false, "message":message, "count":0, "cost_cents":0}

static func _load_proposal() -> Dictionary:
	if _proposal_loaded:
		return _proposal
	_proposal_loaded = true
	var file := FileAccess.open(PROPOSAL_PATH, FileAccess.READ)
	if file == null:
		push_error("Economy proposal missing: " + PROPOSAL_PATH)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		push_error("Economy proposal is invalid JSON")
		return {}
	_proposal = parsed
	return _proposal
