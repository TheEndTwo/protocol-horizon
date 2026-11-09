class_name EarthMiningFeatures
extends RefCounted

const CONFIG_PATH := "res://data/proposals/mining_features.json"
const ECONOMY_PATH := "res://gameplay/EconomyModel.gd"
const GAME_MATH := preload("res://gameplay/GameMath.gd")
const NO_EVENT := 1.0e30
const BUFFER_TOKEN := "mining:factory_buffer"
const FEATURE_IDS := ["D01", "D02", "D03", "D04", "D11", "D14", "D15", "D19", "D20", "FE_SK01", "FE_SK02", "FE_SK03", "FE_SK05"]

static var _config_cache: Dictionary = {}
static var _economy_cache: Variant

static func ensure(p: Dictionary) -> void:
	var state := _state(p)
	var defaults := {
		"version":1,
		"rng_state":1729,
		"last_processed_tap_id":0,
		"precision_streak":0,
		"successful_hits_since_direction":0,
		"weak_mark_seconds":0.0,
		"weak_mark_pending":false,
		"marked_strike":{"available":false, "armed":false, "zone":"", "seconds_left":0.0},
		"directional_strike":{"available":false, "armed":false, "zone":""},
		"pocket":{"units":0, "opened":false, "destination":"inventory", "source_tap_id":0, "discoveries":0},
		"forecast":{"initialized":false, "enabled":true, "available":false, "seconds_left":0.0, "zone":"left", "opportunities":0},
		"resonance":{"active":false, "armed":false, "armed_seconds":0.0, "cooldown_left":0.0, "uses":0},
		"lens_horizon":0,
		"deep_profile":"balanced",
		"profile_horizon":0,
		"zone_choice":{"available":false, "seconds_left":0.0, "zone":"", "used_in_combo":false},
		"route":{"active":false, "path":-1},
		"factory_buffer_units":0,
		"core_event":{"started":false, "completed":false, "work_units":0, "reward_remaining":0, "reward_claimed":false, "archived":false},
		"archive_records":[]
	}
	for key in defaults:
		if not state.has(key) or typeof(state[key]) != typeof(defaults[key]):
			state[key] = defaults[key].duplicate(true) if defaults[key] is Dictionary or defaults[key] is Array else defaults[key]
	for key in ["marked_strike", "directional_strike", "pocket", "forecast", "resonance", "zone_choice", "route", "core_event"]:
		if not state[key] is Dictionary:
			state[key] = defaults[key].duplicate(true)
	state["rng_state"] = clampi(int(state.get("rng_state", 1729)), 1, 2147483646)
	state["precision_streak"] = maxi(0, int(state.get("precision_streak", 0)))
	state["successful_hits_since_direction"] = clampi(int(state.get("successful_hits_since_direction", 0)), 0, 1000000)
	var pocket: Dictionary = state["pocket"]
	pocket["units"] = clampi(int(pocket.get("units", 0)), 0, int(_config().get("pocket", {}).get("max_pool_units", 4)))
	if not ["inventory", "factory_buffer"].has(str(pocket.get("destination", "inventory"))):
		pocket["destination"] = "inventory"
	state["factory_buffer_units"] = maxi(0, int(state.get("factory_buffer_units", 0)))
	_sync_factory_buffer_reservation(p, state)

static func refresh(p: Dictionary) -> void:
	ensure(p)
	var state := _state(p)
	var forecast: Dictionary = state["forecast"]
	if _owned(p, "D03") and not bool(forecast.get("initialized", false)):
		forecast["enabled"] = true
		forecast["seconds_left"] = _forecast_interval()
		forecast["initialized"] = true
	if not _owned(p, "D03"):
		forecast["enabled"] = false

static func advance(p: Dictionary, dt: float) -> void:
	ensure(p)
	if not is_finite(dt) or dt <= 0.0:
		return
	var state := _state(p)
	state["weak_mark_seconds"] = maxf(0.0, float(state.get("weak_mark_seconds", 0.0)) - dt)
	if float(state["weak_mark_seconds"]) <= 0.0:
		state["weak_mark_pending"] = false
	var marked: Dictionary = state["marked_strike"]
	marked["seconds_left"] = maxf(0.0, float(marked.get("seconds_left", 0.0)) - dt)
	if float(marked["seconds_left"]) <= 0.0 and bool(marked.get("armed", false)):
		marked["armed"] = false
		marked["zone"] = ""
	var resonance: Dictionary = state["resonance"]
	resonance["cooldown_left"] = maxf(0.0, float(resonance.get("cooldown_left", 0.0)) - dt)
	resonance["armed_seconds"] = maxf(0.0, float(resonance.get("armed_seconds", 0.0)) - dt)
	if float(resonance["armed_seconds"]) <= 0.0:
		resonance["armed"] = false
	var zone_choice: Dictionary = state["zone_choice"]
	zone_choice["seconds_left"] = maxf(0.0, float(zone_choice.get("seconds_left", 0.0)) - dt)
	if float(zone_choice["seconds_left"]) <= 0.0:
		zone_choice["available"] = false
		zone_choice["zone"] = ""
	var forecast: Dictionary = state["forecast"]
	if _owned(p, "D03") and bool(forecast.get("enabled", false)) and not bool(forecast.get("available", false)):
		forecast["seconds_left"] = maxf(0.0, float(forecast.get("seconds_left", _forecast_interval())) - dt)
		if float(forecast["seconds_left"]) <= 0.0:
			forecast["available"] = true
			var zones := ["left", "center", "right"]
			forecast["zone"] = zones[posmod(int(forecast.get("opportunities", 0)), zones.size())]

static func next_event_in(p: Dictionary) -> float:
	ensure(p)
	var state := _state(p)
	var result := NO_EVENT
	for value in [float(state.get("weak_mark_seconds", 0.0)), float(state["marked_strike"].get("seconds_left", 0.0)), float(state["resonance"].get("cooldown_left", 0.0)), float(state["resonance"].get("armed_seconds", 0.0)), float(state["zone_choice"].get("seconds_left", 0.0))]:
		if value > 0.0:
			result = minf(result, value)
	var forecast: Dictionary = state["forecast"]
	if _owned(p, "D03") and bool(forecast.get("enabled", false)) and not bool(forecast.get("available", false)):
		var eta := maxf(0.0, float(forecast.get("seconds_left", _forecast_interval())))
		result = minf(result, eta)
	return result

static func act(p: Dictionary, action: String, args: Dictionary) -> Dictionary:
	ensure(p)
	var id := str(args.get("id", ""))
	var spec: Dictionary = _config().get("supported", {}).get(id, {})
	if spec.is_empty() or not _owned(p, id):
		return GAME_MATH.fail("Сначала изучите соответствующее исследование или мастерство")
	if _ACTION_IDS.get(action, "") != id:
		return GAME_MATH.fail("Это действие не принадлежит указанному узлу")
	if not GAME_MATH.unlocked(p, "fe"):
		return GAME_MATH.fail("Участок Fe ещё не открыт")
	match action:
		"mining_mark_weak_point":
			var state := _state(p)
			state["weak_mark_seconds"] = float(_config().get("precision", {}).get("weak_mark_seconds", 4.0))
			state["weak_mark_pending"] = true
			return {"ok":true, "message":"Слабая точка отмечена на четыре секунды", "seconds":state["weak_mark_seconds"]}
		"mining_open_pocket":
			var pocket: Dictionary = _state(p)["pocket"]
			if int(pocket.get("units", 0)) <= 0 or bool(pocket.get("opened", false)):
				return GAME_MATH.fail("Нет нового богатого кармана для осмотра")
			pocket["opened"] = true
			return {"ok":true, "message":"Карман осмотрен; руда останется на месте до следующего физического удара", "units_remaining":int(pocket["units"])}
		"mining_set_pocket_destination":
			return _set_pocket_destination(p, args)
		"mining_toggle_forecast":
			return _toggle_forecast(p, args)
		"mining_arm_marked_strike":
			return _arm_marked_strike(p, args)
		"mining_arm_resonance":
			return _arm_resonance(p)
		"mining_select_lens":
			return _select_lens(p, args)
		"mining_choose_profile":
			return _choose_profile(p, args)
		"mining_start_core_event":
			return _start_core_event(p)
		"mining_claim_core_reward":
			return _claim_core_reward(p)
		"mining_choose_direction":
			return _choose_direction(p, args)
		"mining_choose_route":
			return _choose_route(p, args)
		"mining_choose_zone":
			return _choose_zone(p, args)
	return GAME_MATH.fail("Действие добычи не реализовано")

static func operations(p: Dictionary, id: String) -> Array:
	ensure(p)
	if not _config().get("supported", {}).has(id) or not _owned(p, id) or not GAME_MATH.unlocked(p, "fe"):
		return []
	var state := _state(p)
	var choices := _zone_choices()
	match id:
		"D01": return []
		"D02":
			return [_operation("mining_open_pocket", "Осмотреть обнаруженный богатый карман", [])] if int(state["pocket"].get("units", 0)) > 0 and not bool(state["pocket"].get("opened", false)) else []
		"D03":
			return [_operation("mining_toggle_forecast", "Включить или выключить прогноз", [{"key":"enabled", "label":"Показывать прогноз", "type":"toggle"}])]
		"D04":
			return [_operation("mining_arm_marked_strike", "Отметить цель усиленного удара", [{"key":"zone", "label":"Часть жилы", "type":"select", "choices":choices}])] if bool(state["marked_strike"].get("available", false)) else []
		"D11":
			return [_operation("mining_set_pocket_destination", "Выбрать назначение следующего кармана", [{"key":"destination", "label":"Куда направить", "type":"select", "choices":[{"label":"Инвентарь", "value":"inventory"}, {"label":"Буфер завода", "value":"factory_buffer"}]}])] if int(state["pocket"].get("units", 0)) > 0 and bool(state["pocket"].get("opened", false)) else []
		"D14":
			return [_operation("mining_arm_resonance", "Подготовить одну цепную реакцию резонанса", [])] if bool(state["resonance"].get("active", false)) and not bool(state["resonance"].get("armed", false)) and float(state["resonance"].get("cooldown_left", 0.0)) <= 0.0 else []
		"D15":
			var horizons := _horizon_choices(p)
			return [_operation("mining_select_lens", "Выбрать открытую глубокую линзу", [{"key":"horizon", "label":"Ранее открытый горизонт", "type":"select", "choices":horizons}])] if not horizons.is_empty() else []
		"D19":
			var horizons := _horizon_choices(p)
			return [_operation("mining_choose_profile", "Настроить профиль глубокого горизонта", [
				{"key":"profile", "label":"Профиль", "type":"select", "choices":[{"label":"Сбалансированный", "value":"balanced"}, {"label":"Пропускная способность", "value":"throughput"}, {"label":"Качество ручной добычи", "value":"quality"}]},
				{"key":"horizon", "label":"Открытый горизонт", "type":"select", "choices":horizons}
			])] if not horizons.is_empty() else []
		"D20":
			var event: Dictionary = state["core_event"]
			var actions: Array = []
			if not bool(event.get("started", false)) and not bool(event.get("completed", false)) and int(GAME_MATH.site(p, "fe").get("horizon", 0)) >= int(_config().get("core_event", {}).get("minimum_horizon", 3)):
				actions.append(_operation("mining_start_core_event", "Начать единственное событие глубинного ядра", []))
			if bool(event.get("completed", false)) and int(event.get("reward_remaining", 0)) > 0:
				actions.append(_operation("mining_claim_core_reward", "Забрать оставшуюся награду архива", []))
			return actions
		"FE_SK01": return [_operation("mining_mark_weak_point", "Отметить слабую точку на четыре секунды", [])]
		"FE_SK02":
			return [_operation("mining_choose_direction", "Выбрать цель одного направленного удара", [{"key":"zone", "label":"Часть жилы", "type":"select", "choices":choices}])] if bool(state["directional_strike"].get("available", false)) and not bool(state["directional_strike"].get("armed", false)) else []
		"FE_SK03":
			return [_operation("mining_choose_route", "Выбрать один из двух путей в найденном кармане", [{"key":"path", "label":"Путь прожилки", "type":"select", "choices":[{"label":"Левый путь", "value":0}, {"label":"Правый путь", "value":1}]}])] if int(state["pocket"].get("units", 0)) > 0 and not bool(state["route"].get("active", false)) else []
		"FE_SK05":
			return [_operation("mining_choose_zone", "Выбрать реальную рудную зону на 15 секунд", [{"key":"zone", "label":"Зона добычи", "type":"select", "choices":choices}])] if bool(state["zone_choice"].get("available", false)) else []
	return []

static func tap_effects(p: Dictionary, args: Dictionary, precise: bool) -> Dictionary:
	ensure(p)
	var state := _state(p)
	var position := _position(args)
	var horizon := int(GAME_MATH.site(p, "fe").get("horizon", 0))
	var used: Array[String] = []
	var multiplier := 1.0
	var profile: Dictionary = production_effects(p, "fe", horizon)
	if float(profile.get("tap_multiplier", 1.0)) > 1.0:
		multiplier *= float(profile["tap_multiplier"])
	var marked: Dictionary = state["marked_strike"]
	if _owned(p, "D04") and bool(marked.get("armed", false)) and _inside_zone(position, str(marked.get("zone", ""))):
		var level := _research_level(p, "D04")
		var precision_cfg: Dictionary = _config().get("precision", {})
		multiplier *= 1.0 + minf(float(_config().get("manual_bonus_cap", 0.35)), float(precision_cfg.get("marked_strike_base_bonus", 0.12)) + float(maxi(0, level - 1)) * float(precision_cfg.get("marked_strike_level_bonus", 0.06)))
		used.append("D04")
	var directional: Dictionary = state["directional_strike"]
	if _owned(p, "FE_SK02") and bool(directional.get("armed", false)) and _inside_zone(position, str(directional.get("zone", ""))):
		multiplier *= 1.0 + float(_config().get("precision", {}).get("directional_bonus", 0.22))
		used.append("FE_SK02")
	var zone_choice: Dictionary = state["zone_choice"]
	if _owned(p, "FE_SK05") and float(zone_choice.get("seconds_left", 0.0)) > 0.0 and _inside_zone(position, str(zone_choice.get("zone", ""))):
		multiplier *= 1.0 + float(_config().get("zones", {}).get("bonus", 0.18))
		used.append("FE_SK05")
	var resonance: Dictionary = state["resonance"]
	if _owned(p, "D14") and bool(resonance.get("active", false)) and bool(resonance.get("armed", false)) and precise:
		multiplier *= 1.0 + float(_config().get("resonance", {}).get("bonus", 0.22))
		used.append("D14")
	if _owned(p, "FE_SK01") and bool(state.get("weak_mark_pending", false)) and float(state.get("weak_mark_seconds", 0.0)) > 0.0 and precise:
		used.append("FE_SK01")
	var cap := 1.0 + float(_config().get("manual_bonus_cap", 0.35))
	return {"multiplier":minf(multiplier, cap), "used":used}

static func production_effects(p: Dictionary, site: String, horizon: int) -> Dictionary:
	var neutral := {"rate_bonus":0.0, "wage_multiplier":1.0, "tap_multiplier":1.0}
	if site != "fe" or horizon <= 0 or not _owned(p, "D19"):
		return neutral
	var state := _state(p)
	if int(state.get("profile_horizon", 0)) != horizon:
		return neutral
	var profile_id := str(state.get("deep_profile", "balanced"))
	var profiles: Dictionary = _config().get("profiles", {})
	return profiles.get(profile_id, profiles.get("balanced", neutral)).duplicate(true)

static func after_action(p: Dictionary, domain: String, action: String, args: Dictionary, result: Dictionary) -> void:
	if domain not in ["economy", "economy_model"] or action.strip_edges().to_lower() != "tap" or not bool(result.get("ok", false)):
		return
	var amount := int(result.get("amount", 0))
	if amount <= 0:
		return
	ensure(p)
	var state := _state(p)
	var tap_id := int(result.get("tap_id", GAME_MATH.game(p).get("stats", {}).get("taps", 0)))
	if tap_id <= int(state.get("last_processed_tap_id", 0)):
		return
	state["last_processed_tap_id"] = tap_id
	var pool: Dictionary = state["pocket"]
	var had_pool := int(pool.get("units", 0)) > 0
	if had_pool and _route_allows_draw(state, args):
		var draw_cap := int(_config().get("pocket", {}).get("max_draw_per_tap", 2))
		var requested := mini(draw_cap, int(pool["units"]))
		var delivered := _deliver_pool(p, state, requested)
		if delivered > 0:
			pool["units"] = maxi(0, int(pool["units"]) - delivered)
			result["pocket_bonus_units"] = int(result.get("pocket_bonus_units", 0)) + delivered
			result["amount"] = amount + int(result["pocket_bonus_units"])
		if int(pool["units"]) <= 0:
			pool["opened"] = false
			pool["destination"] = "inventory"
			state["route"] = {"active":false, "path":-1}
	var used: Array = result.get("mining_effects", {}).get("used", [])
	for effect in used:
		match str(effect):
			"FE_SK01":
				state["weak_mark_pending"] = false
				state["weak_mark_seconds"] = 0.0
			"D04":
				state["marked_strike"] = {"available":false, "armed":false, "zone":"", "seconds_left":0.0}
			"FE_SK02":
				state["directional_strike"] = {"available":false, "armed":false, "zone":""}
				state["successful_hits_since_direction"] = 0
			"D14":
				var resonance: Dictionary = state["resonance"]
				resonance["armed"] = false
				resonance["armed_seconds"] = 0.0
				resonance["uses"] = int(resonance.get("uses", 0)) + 1
				resonance["cooldown_left"] = clampf(float(_config().get("resonance", {}).get("cooldown_seconds", 45.0)), 0.0, float(_config().get("resonance", {}).get("max_cooldown_seconds", 60.0)))
	var precision := bool(result.get("precision", false))
	var streak := int(result.get("precision_streak", 0))
	state["precision_streak"] = streak if precision else 0
	var directional: Dictionary = state["directional_strike"]
	if _owned(p, "FE_SK02") and not bool(directional.get("available", false)) and not bool(directional.get("armed", false)):
		state["successful_hits_since_direction"] = int(state.get("successful_hits_since_direction", 0)) + 1
		if int(state["successful_hits_since_direction"]) >= int(_config().get("precision", {}).get("directional_successes", 3)):
			directional["available"] = true
	if _owned(p, "D04"):
		var marked: Dictionary = state["marked_strike"]
		var threshold := maxi(2, int(_config().get("precision", {}).get("marked_strike_threshold", 3)) - int((_research_level(p, "D04") - 1) / 2))
		if precision and streak >= threshold and not bool(marked.get("armed", false)):
			marked["available"] = true
		elif not precision:
			marked["available"] = false
			marked["armed"] = false
			marked["zone"] = ""
			marked["seconds_left"] = 0.0
	if _owned(p, "FE_SK05"):
		var zone_choice: Dictionary = state["zone_choice"]
		if precision and streak >= int(_config().get("zones", {}).get("choice_streak", 3)) and not bool(zone_choice.get("used_in_combo", false)):
			zone_choice["available"] = true
			zone_choice["seconds_left"] = float(_config().get("zones", {}).get("choice_seconds", 15.0))
			zone_choice["used_in_combo"] = true
		elif not precision and float(zone_choice.get("seconds_left", 0.0)) <= 0.0:
			zone_choice["used_in_combo"] = false
		if not precision and float(zone_choice.get("seconds_left", 0.0)) <= 0.0:
			zone_choice["available"] = false
			zone_choice["zone"] = ""
	var resonance_state: Dictionary = state["resonance"]
	resonance_state["active"] = _owned(p, "D14") and precision and streak >= int(_config().get("resonance", {}).get("streak_required", 3)) and float(resonance_state.get("cooldown_left", 0.0)) <= 0.0
	var forecast_triggered := _consume_forecast_if_hit(p, state, args)
	if not had_pool and _owned(p, "D02"):
		var chance := _pocket_chance(p, state, result, streak, forecast_triggered)
		if _roll(state) < chance:
			var pocket_cfg: Dictionary = _config().get("pocket", {})
			var units := clampi(ceili(float(amount) * float(pocket_cfg.get("units_per_hit", 0.25))), 1, int(pocket_cfg.get("max_pool_units", 4)))
			pool["units"] = units
			pool["opened"] = false
			pool["destination"] = "inventory"
			pool["source_tap_id"] = tap_id
			pool["discoveries"] = int(pool.get("discoveries", 0)) + 1
			result["pocket_discovered"] = true
	var event: Dictionary = state["core_event"]
	var current_horizon := int(GAME_MATH.site(p, "fe").get("horizon", 0))
	if _owned(p, "D20") and bool(event.get("started", false)) and not bool(event.get("completed", false)) and current_horizon >= int(_config().get("core_event", {}).get("minimum_horizon", 3)):
		var required := int(_config().get("core_event", {}).get("work_units", 5))
		var previous_work := int(event.get("work_units", 0))
		var work := mini(required, previous_work + amount)
		event["work_units"] = work
		GAME_MATH.stat(p, "deep_fe_event_work", float(work - previous_work))
		result["core_event_work"] = work
		if work >= required:
			_complete_core_event(p, state)
			var reward := _claim_core_reward(p, false)
			if bool(reward.get("ok", false)):
				result["core_event_reward_units"] = int(reward.get("amount", 0))
				result["amount"] = int(result.get("amount", amount)) + int(reward.get("amount", 0))

static func coverage() -> Dictionary:
	var by_id: Dictionary = {}
	for id in FEATURE_IDS:
		by_id[id] = {"status":"supported", "supported":true, "catalog":str(_config().get("supported", {}).get(id, {}).get("catalog", "")), "mechanism":str(_config().get("supported", {}).get(id, {}).get("mechanism", "")), "canonical_effect":str(_config().get("supported", {}).get(id, {}).get("canonical_effect", ""))}
	return {"total":by_id.size(), "supported_ids":FEATURE_IDS.duplicate(), "gap_ids":[], "by_id":by_id}

static func _set_pocket_destination(p: Dictionary, args: Dictionary) -> Dictionary:
	var pocket: Dictionary = _state(p)["pocket"]
	var destination := str(args.get("destination", ""))
	if int(pocket.get("units", 0)) <= 0 or not bool(pocket.get("opened", false)):
		return GAME_MATH.fail("Сначала осмотрите обнаруженный карман")
	if not ["inventory", "factory_buffer"].has(destination):
		return GAME_MATH.fail("Выберите инвентарь или заводской буфер")
	pocket["destination"] = destination
	return {"ok":true, "message":"Назначение сохранено; награда появится только после следующего физического удара", "destination":destination}

static func _toggle_forecast(p: Dictionary, args: Dictionary) -> Dictionary:
	var forecast: Dictionary = _state(p)["forecast"]
	var requested: Variant = args.get("enabled", null)
	var enabled := not bool(forecast.get("enabled", false)) if requested == null else bool(requested)
	forecast["enabled"] = enabled
	forecast["available"] = false
	forecast["seconds_left"] = _forecast_interval() if enabled else 0.0
	forecast["initialized"] = true
	return {"ok":true, "message":"Прогноз включён" if enabled else "Прогноз выключен", "enabled":enabled, "seconds_left":float(forecast["seconds_left"])}

static func _arm_marked_strike(p: Dictionary, args: Dictionary) -> Dictionary:
	var state := _state(p)
	var marked: Dictionary = state["marked_strike"]
	var zone := str(args.get("zone", ""))
	if not bool(marked.get("available", false)) or not _valid_zone(zone):
		return GAME_MATH.fail("Нужна серия точных попаданий и реальная цель на жиле")
	marked["available"] = false
	marked["armed"] = true
	marked["zone"] = zone
	marked["seconds_left"] = float(_config().get("precision", {}).get("marked_strike_seconds", 10.0))
	return {"ok":true, "message":"Усиленный удар направлен; он сработает только при попадании в отмеченную часть жилы", "zone":zone}

static func _arm_resonance(p: Dictionary) -> Dictionary:
	var resonance: Dictionary = _state(p)["resonance"]
	if not bool(resonance.get("active", false)) or bool(resonance.get("armed", false)) or float(resonance.get("cooldown_left", 0.0)) > 0.0:
		return GAME_MATH.fail("Резонанс пока не активен или ещё на перезарядке")
	resonance["armed"] = true
	resonance["armed_seconds"] = float(_config().get("resonance", {}).get("armed_seconds", 8.0))
	return {"ok":true, "message":"Одна цепная реакция подготовлена для точного физического удара"}

static func _select_lens(p: Dictionary, args: Dictionary) -> Dictionary:
	var horizon := _nonnegative_integer(args.get("horizon", null))
	if horizon < 1 or horizon > _max_open_horizon(p):
		return GAME_MATH.fail("Линза доступна только на ранее открытом глубоком горизонте")
	_state(p)["lens_horizon"] = horizon
	return {"ok":true, "message":"Глубокая линза настроена на открытый горизонт", "horizon":horizon}

static func _choose_profile(p: Dictionary, args: Dictionary) -> Dictionary:
	var profile := str(args.get("profile", ""))
	var horizon := _nonnegative_integer(args.get("horizon", null))
	if not _config().get("profiles", {}).has(profile) or horizon < 1 or horizon > _max_open_horizon(p):
		return GAME_MATH.fail("Выберите профиль и ранее открытый глубокий горизонт")
	var state := _state(p)
	state["deep_profile"] = profile
	state["profile_horizon"] = horizon
	return {"ok":true, "message":"Профиль применён к выбранному горизонту; его можно сменить в любой момент", "profile":profile, "horizon":horizon}

static func _start_core_event(p: Dictionary) -> Dictionary:
	var event: Dictionary = _state(p)["core_event"]
	var minimum_horizon := int(_config().get("core_event", {}).get("minimum_horizon", 3))
	if int(GAME_MATH.site(p, "fe").get("horizon", 0)) < minimum_horizon:
		return GAME_MATH.fail("Событие требует открытого глубокого горизонта %d" % minimum_horizon)
	if bool(event.get("started", false)) or bool(event.get("completed", false)):
		return GAME_MATH.fail("Это уникальное событие уже начато или завершено")
	event["started"] = true
	return {"ok":true, "message":"Событие начато; завершите реальную ручную работу на глубоком горизонте", "work_required":int(_config().get("core_event", {}).get("work_units", 5))}

static func _claim_core_reward(p: Dictionary, return_failure: bool = true) -> Dictionary:
	var event: Dictionary = _state(p)["core_event"]
	if not bool(event.get("completed", false)) or int(event.get("reward_remaining", 0)) <= 0:
		return GAME_MATH.fail("Награда появится только после завершения уникального события") if return_failure else {"ok":false, "amount":0}
	var remaining := int(event["reward_remaining"])
	var accepted := GAME_MATH.add(p, "iron_ore", remaining)
	if accepted <= 0:
		return GAME_MATH.fail("Освободите место на складе для архивной награды") if return_failure else {"ok":false, "amount":0}
	event["reward_remaining"] = remaining - accepted
	event["reward_claimed"] = int(event["reward_remaining"]) == 0
	_record_mining_bonus(p, accepted)
	return {"ok":true, "message":"Однократная награда глубинного архива получена", "amount":accepted, "remaining":int(event["reward_remaining"]), "claimed":bool(event["reward_claimed"])}

static func _choose_direction(p: Dictionary, args: Dictionary) -> Dictionary:
	var directional: Dictionary = _state(p)["directional_strike"]
	var zone := str(args.get("zone", ""))
	if not bool(directional.get("available", false)) or not _valid_zone(zone):
		return GAME_MATH.fail("Сначала выполните три успешных касания и выберите цель")
	directional["available"] = false
	directional["armed"] = true
	directional["zone"] = zone
	return {"ok":true, "message":"Направленный удар выбран; бонус будет только при касании этой части жилы", "zone":zone}

static func _choose_route(p: Dictionary, args: Dictionary) -> Dictionary:
	var state := _state(p)
	var pocket: Dictionary = state["pocket"]
	var path := _nonnegative_integer(args.get("path", null))
	if int(pocket.get("units", 0)) <= 0 or path not in [0, 1]:
		return GAME_MATH.fail("Выберите путь внутри уже обнаруженного кармана")
	state["route"] = {"active":true, "path":path}
	return {"ok":true, "message":"Путь показан; он не выдаёт руду без физического попадания по выбранной прожилке", "path":path}

static func _choose_zone(p: Dictionary, args: Dictionary) -> Dictionary:
	var zone_choice: Dictionary = _state(p)["zone_choice"]
	var zone := str(args.get("zone", ""))
	if not bool(zone_choice.get("available", false)) or not _valid_zone(zone):
		return GAME_MATH.fail("Трёхточечная серия не открыла выбор рудной зоны")
	zone_choice["available"] = false
	zone_choice["zone"] = zone
	return {"ok":true, "message":"Зона выбрана на оставшееся время окна; можно не использовать этот выбор", "zone":zone, "seconds_left":float(zone_choice.get("seconds_left", 0.0))}

static func _route_allows_draw(state: Dictionary, args: Dictionary) -> bool:
	var route: Dictionary = state["route"]
	if not bool(route.get("active", false)):
		return true
	var position := _position(args)
	if position.x < 0.0:
		return false
	var path := int(route.get("path", -1))
	var points := _path_points(path)
	return _distance_to_segment(position, points[0], points[1]) <= float(_config().get("routes", {}).get("path_radius", 0.055))

static func _deliver_pool(p: Dictionary, state: Dictionary, requested: int) -> int:
	var pocket: Dictionary = state["pocket"]
	var destination := str(pocket.get("destination", "inventory"))
	var units := mini(maxi(requested, 0), int(pocket.get("units", 0)))
	var accepted := GAME_MATH.add(p, "iron_ore", units)
	if accepted <= 0:
		return 0
	if destination == "factory_buffer":
		state["factory_buffer_units"] = int(state.get("factory_buffer_units", 0)) + accepted
		_sync_factory_buffer_reservation(p, state)
	_record_mining_bonus(p, accepted)
	return accepted

static func _consume_forecast_if_hit(p: Dictionary, state: Dictionary, args: Dictionary) -> bool:
	if not _owned(p, "D03"):
		return false
	var forecast: Dictionary = state["forecast"]
	if not bool(forecast.get("enabled", false)) or not bool(forecast.get("available", false)):
		return false
	if not _inside_zone(_position(args), str(forecast.get("zone", ""))):
		return false
	forecast["available"] = false
	forecast["opportunities"] = int(forecast.get("opportunities", 0)) + 1
	forecast["seconds_left"] = _forecast_interval()
	return true

static func _pocket_chance(p: Dictionary, state: Dictionary, result: Dictionary, streak: int, forecast_triggered: bool) -> float:
	var cfg: Dictionary = _config().get("pocket", {})
	var level := _research_level(p, "D02")
	var chance := float(cfg.get("base_chance", 0.08)) + float(maxi(0, level - 1)) * float(cfg.get("per_level_chance", 0.035))
	chance += float(mini(streak, int(cfg.get("streak_cap", 8)))) * float(cfg.get("per_precision_streak", 0.015))
	if bool(result.get("critical", false)):
		chance += float(cfg.get("critical_chance", 0.06))
	if forecast_triggered:
		chance += float(cfg.get("forecast_chance", 0.10))
	var lens_horizon := int(state.get("lens_horizon", 0))
	if _owned(p, "D15") and lens_horizon > 0 and int(GAME_MATH.site(p, "fe").get("horizon", 0)) == lens_horizon:
		chance += float(cfg.get("lens_chance", 0.08)) + float(maxi(0, _research_level(p, "D15") - 1)) * float(cfg.get("lens_per_level", 0.03))
	return clampf(chance, 0.0, float(cfg.get("max_chance", 0.35)))

static func _complete_core_event(p: Dictionary, state: Dictionary) -> void:
	var event: Dictionary = state["core_event"]
	if bool(event.get("completed", false)):
		return
	event["completed"] = true
	event["reward_remaining"] = int(_config().get("core_event", {}).get("reward_units", 20))
	if not bool(event.get("archived", false)):
		var record := {"id":"deep_fe_heart", "horizon":int(GAME_MATH.site(p, "fe").get("horizon", 0)), "work_units":int(event.get("work_units", 0)), "reward_units":int(event["reward_remaining"])}
		state["archive_records"].append(record)
		event["archived"] = true
		event["archive_record"] = record

static func _record_mining_bonus(p: Dictionary, amount: int) -> void:
	if amount <= 0:
		return
	var script: Variant = _economy()
	if script != null and script.has_method("record_mining_bonus"):
		script.call("record_mining_bonus", p, amount)
	else:
		GAME_MATH.stat(p, "produced:iron_ore", amount)

static func _sync_factory_buffer_reservation(p: Dictionary, state: Dictionary) -> void:
	var game: Dictionary = GAME_MATH.game(p)
	var reservations: Dictionary = game["reservations"]
	var units := mini(maxi(0, int(state.get("factory_buffer_units", 0))), maxi(0, int(p.get("inventory", {}).get("iron_ore", 0))))
	state["factory_buffer_units"] = units
	if units <= 0:
		reservations.erase(BUFFER_TOKEN)
	else:
		reservations[BUFFER_TOKEN] = {"iron_ore":units}

static func _state(p: Dictionary) -> Dictionary:
	var game: Dictionary = GAME_MATH.game(p)
	if not game.has("feature_families") or not game["feature_families"] is Dictionary:
		game["feature_families"] = {}
	var families: Dictionary = game["feature_families"]
	if not families.has("mining") or not families["mining"] is Dictionary:
		families["mining"] = {}
	return families["mining"]

static func _owned(p: Dictionary, id: String) -> bool:
	var progression: Dictionary = GAME_MATH.game(p).get("progression", {})
	var catalog := "mastery" if id.contains("_SK") else "research"
	return int(progression.get(catalog, {}).get(id, 0)) > 0

static func _research_level(p: Dictionary, id: String) -> int:
	return int(GAME_MATH.game(p).get("progression", {}).get("research", {}).get(id, 0))

static func _position(args: Dictionary) -> Vector2:
	var raw: Variant = args.get("position_norm", null)
	if raw is Vector2:
		return Vector2(clampf(raw.x, 0.0, 1.0), clampf(raw.y, 0.0, 1.0))
	if raw is Array and raw.size() >= 2 and is_finite(float(raw[0])) and is_finite(float(raw[1])):
		return Vector2(clampf(float(raw[0]), 0.0, 1.0), clampf(float(raw[1]), 0.0, 1.0))
	return Vector2(-1.0, -1.0)

static func _inside_zone(position: Vector2, zone: String) -> bool:
	if position.x < 0.0 or not _valid_zone(zone):
		return false
	var centers := {"left":Vector2(0.28, 0.60), "center":Vector2(0.50, 0.62), "right":Vector2(0.72, 0.60)}
	return position.distance_to(centers[zone]) <= float(_config().get("zones", {}).get("radius", 0.15))

static func _valid_zone(zone: String) -> bool:
	return ["left", "center", "right"].has(zone)

static func _path_points(path: int) -> Array[Vector2]:
	if path == 0:
		return [Vector2(0.22, 0.49), Vector2(0.78, 0.76)]
	return [Vector2(0.78, 0.49), Vector2(0.22, 0.76)]

static func _distance_to_segment(point: Vector2, a: Vector2, b: Vector2) -> float:
	var segment := b - a
	var length_squared := segment.length_squared()
	if length_squared <= 0.000001:
		return point.distance_to(a)
	var t := clampf((point - a).dot(segment) / length_squared, 0.0, 1.0)
	return point.distance_to(a + segment * t)

static func _roll(state: Dictionary) -> float:
	var next := int((int(state.get("rng_state", 1729)) * 48271) % 2147483647)
	if next <= 0:
		next = 1
	state["rng_state"] = next
	return float(next) / 2147483647.0

static func _forecast_interval() -> float:
	return clampf(float(_config().get("forecast", {}).get("interval_seconds", 35.0)), 1.0, float(_config().get("forecast", {}).get("max_interval_seconds", 90.0)))

static func _max_open_horizon(p: Dictionary) -> int:
	var script: Variant = _economy()
	if script == null or not script.has_method("metrics"):
		return 0
	var metrics: Dictionary = script.call("metrics", p, "fe")
	return clampi(floori(float(metrics.get("average_upgrade_level", 0.0)) / 100.0), 0, 10)

static func _horizon_choices(p: Dictionary) -> Array:
	var result: Array = []
	for horizon in range(1, _max_open_horizon(p) + 1):
		result.append({"label":"Горизонт %d" % horizon, "value":horizon})
	return result

static func _zone_choices() -> Array:
	return [{"label":"Левый участок", "value":"left"}, {"label":"Центральный участок", "value":"center"}, {"label":"Правый участок", "value":"right"}]

static func _operation(action: String, title: String, fields: Array) -> Dictionary:
	return {"action":action, "title":title, "fields":fields}

static func _nonnegative_integer(value: Variant) -> int:
	if typeof(value) == TYPE_BOOL or not (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT):
		return -1
	var number := float(value)
	if not is_finite(number) or number < 0.0 or number != floorf(number):
		return -1
	return int(number)

static func _economy() -> Variant:
	if _economy_cache == null:
		_economy_cache = load(ECONOMY_PATH)
	return _economy_cache

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

const _ACTION_IDS := {
	"mining_mark_weak_point":"FE_SK01",
	"mining_open_pocket":"D02",
	"mining_set_pocket_destination":"D11",
	"mining_toggle_forecast":"D03",
	"mining_arm_marked_strike":"D04",
	"mining_arm_resonance":"D14",
	"mining_select_lens":"D15",
	"mining_choose_profile":"D19",
	"mining_start_core_event":"D20",
	"mining_claim_core_reward":"D20",
	"mining_choose_direction":"FE_SK02",
	"mining_choose_route":"FE_SK03",
	"mining_choose_zone":"FE_SK05"
}
