class_name EarthSites
extends RefCounted

const MATH := preload("res://gameplay/GameMath.gd")
const ECONOMY := preload("res://gameplay/EconomyModel.gd")
const CONFIG_PATH := "res://data/proposals/sites.json"
const SITE_IDS := {"pd": "site_earth_pd_7", "ir": "site_earth_ir_9"}
const EPSILON := 0.000001
const MAX_STEPS_PER_ADVANCE := 100000

static var _config_cache: Dictionary = {}


static func ensure(p: Dictionary) -> Dictionary:
	var game := MATH.game(p)
	var stored_extraction: Variant = game.get("extraction", {})
	var extraction: Dictionary = stored_extraction if stored_extraction is Dictionary else {}
	if not extraction.has("pd") or not extraction["pd"] is Dictionary:
		extraction["pd"] = _default_pd_state(int(MATH.site(p, "pd").get("expansions", 0)))
	if not extraction.has("ir") or not extraction["ir"] is Dictionary:
		extraction["ir"] = _default_ir_state(int(MATH.site(p, "ir").get("expansions", 0)))
	_sync_expansion(p, "pd", extraction["pd"])
	_sync_expansion(p, "ir", extraction["ir"])
	game["extraction"] = extraction
	return extraction


static func validate(p: Dictionary) -> bool:
	if not p.has("game"):
		return true
	if not p["game"] is Dictionary:
		return false
	var game: Dictionary = p["game"]
	if not game.has("extraction"):
		return true
	if not game["extraction"] is Dictionary:
		return false
	var extraction: Dictionary = game["extraction"]
	for site_key in ["pd", "ir"]:
		if not extraction.has(site_key):
			continue
		var state: Variant = extraction[site_key]
		if not state is Dictionary:
			return false
		if int(state.get("seed_counter", 0)) < 0 or int(state.get("pending_output", 0)) < 0:
			return false
		if not is_finite(float(state.get("elapsed_seconds", 0.0))) or float(state.get("elapsed_seconds", 0.0)) < 0.0:
			return false
		if not is_finite(float(state.get("wage_fraction_cents", 0.0))) or float(state.get("wage_fraction_cents", 0.0)) < 0.0 or float(state.get("wage_fraction_cents", 0.0)) >= 1.0:
			return false
		if site_key == "pd" and not state.get("sample", {}) is Dictionary:
			return false
		if site_key == "ir" and not state.get("campaign", {}) is Dictionary:
			return false
		var status := String(state.get("status", ""))
		var allowed_statuses := ["idle", "sampling", "ready", "analyzing", "concentrating", "running", "paused", "waiting_funds", "waiting_storage", "completed", "cancelled"]
		if not allowed_statuses.has(status):
			return false
	return true


static func lens_definitions() -> Array:
	return _site_data("pd").get("lenses", []).duplicate(true)


static func strategy_definitions() -> Array:
	return _site_data("ir").get("strategies", []).duplicate(true)

static func phase_definitions() -> Array:
	return _site_data("ir").get("phases", []).duplicate(true)


static func advance(p: Dictionary, seconds: float) -> void:
	if not is_finite(seconds) or seconds <= 0.0:
		return
	var extraction := ensure(p)
	if MATH.unlocked(p, "pd"):
		_advance_pd(p, extraction["pd"], seconds)
	if MATH.unlocked(p, "ir"):
		_advance_ir(p, extraction["ir"], seconds)


static func act(p: Dictionary, action: String, args: Dictionary) -> Dictionary:
	var site_key := _site_key(String(args.get("site", "")))
	var verb := action
	if action.begins_with("pd_"):
		if not site_key.is_empty() and site_key != "pd":
			return MATH.fail("Действие Pd не соответствует указанному участку")
		site_key = "pd"
		verb = action.substr(3)
	elif action.begins_with("ir_"):
		if not site_key.is_empty() and site_key != "ir":
			return MATH.fail("Действие Ir не соответствует указанному участку")
		site_key = "ir"
		verb = action.substr(3)
	if site_key.is_empty():
		return MATH.fail("Укажите участок Pd или Ir")
	if not MATH.unlocked(p, site_key):
		return MATH.fail("Участок ещё не открыт")
	var extraction := ensure(p)
	if site_key == "pd":
		return _act_pd(p, extraction["pd"], verb, args)
	return _act_ir(p, extraction["ir"], verb, args)


static func view(p: Dictionary, site: String) -> Dictionary:
	var site_key := _site_key(site)
	if site_key.is_empty():
		return {"site": site, "unlocked": false, "status": "unknown"}
	var site_id: String = SITE_IDS[site_key]
	if not MATH.unlocked(p, site_key):
		return {"site": site_id, "unlocked": false, "status": "locked"}
	var extraction := ensure(p)
	if site_key == "pd":
		return _pd_view(p, extraction["pd"])
	return _ir_view(p, extraction["ir"])


static func _default_pd_state(expansions: int = 0) -> Dictionary:
	var data := _site_data("pd")
	return {
		"status": "idle",
		"automatic": false,
		"one_shot_contract_clean": false,
		"lens_id": String(data.get("balanced_lens_id", "")),
		"sample": {},
		"elapsed_seconds": 0.0,
		"pending_output": 0,
		"seed_counter": 0,
		"wage_fraction_cents": 0.0,
		"wages_paid_cents": 0,
		"cycles_completed": 0,
		"expansion_count": expansions,
		"last_message": "",
	}


static func _default_ir_state(expansions: int = 0) -> Dictionary:
	var data := _site_data("ir")
	return {
		"status": "idle",
		"strategy_id": "reliable",
		"campaign": {},
		"temperature_c": float(data.get("ambient_temperature_c", 20.0)),
		"pending_output": 0,
		"seed_counter": 0,
		"wage_fraction_cents": 0.0,
		"wages_paid_cents": 0,
		"campaigns_completed": 0,
		"expansion_count": expansions,
		"last_message": "",
	}


static func _act_pd(p: Dictionary, state: Dictionary, action: String, args: Dictionary) -> Dictionary:
	var data := _site_data("pd")
	match action:
		"select_lens":
			if not _pd_is_idle_for_selection(state):
				return MATH.fail("Нельзя менять линзу во время отбора или обработки")
			var lens_id := String(args.get("lens_id", ""))
			if _lens_definition(p, lens_id).is_empty():
				return MATH.fail("Неизвестная геологическая линза")
			state["lens_id"] = lens_id
			return MATH.ok("Линза выбрана; затраты появятся только при отборе")
		"take_sample", "sample":
			if not _pd_is_idle_for_selection(state):
				return MATH.fail("Сначала завершите текущий образец")
			var lens := _lens_definition(p, String(state.get("lens_id", "")))
			if lens.is_empty():
				return MATH.fail("Сначала выберите линзу")
			if not _pd_start_sample(p, state, lens, false):
				return MATH.fail(String(state.get("last_message", "Не удалось начать отбор")))
			return MATH.ok("Отбор пробы начат")
		"analyze_sample":
			if String(state.get("status", "")) != "ready" or state.get("sample", {}).is_empty():
				return MATH.fail("Для анализа нужна готовая проба")
			var sample: Dictionary = state["sample"]
			if bool(sample.get("analysis_completed", false)):
				return MATH.fail("Проба уже проанализирована")
			var pd_data := _site_data("pd")
			var rng := RandomNumberGenerator.new()
			rng.seed = int(sample.get("seed", 1)) + 31
			var analysis_duration := rng.randi_range(
				int(pd_data.get("analysis_duration_min_s", 20)),
				int(pd_data.get("analysis_duration_max_s", 40))
			)
			var express := bool(args.get("express_analysis", false))
			if express and not _has_mastery(p, "PD_SK07"):
				return MATH.fail("Экспресс-анализ требует мастерства PD_SK07")
			var duration_scale := float(_industrial_cfg().get("pd", {}).get("express_analysis", {}).get("duration_multiplier", 0.5)) if express else 1.0
			var min_duration := float(_industrial_cfg().get("pd", {}).get("express_analysis", {}).get("minimum_duration_s", 8.0)) if express else 1.0
			sample["analysis_duration_s"] = maxf(min_duration, float(analysis_duration) * duration_scale)
			var selected_band_id := str(args.get("spectral_band_id", ""))
			var spectrum: Dictionary = sample.get("spectral_profile", {})
			var accurate := not selected_band_id.is_empty() and selected_band_id == str(spectrum.get("target_band_id", ""))
			sample["analysis_score"] = 1.0 if accurate else 0.0
			sample["analysis_bonus_cap"] = clampf(float(pd_data.get("analysis_bonus_cap", 0.08)), 0.0, 0.15)
			var spectral_bonus := float(_industrial_cfg().get("pd", {}).get("spectral_analysis", {}).get("accurate_batch_bonus", 0.03))
			sample["analysis_skill_bonus"] = spectral_bonus if accurate and _has_mastery(p, "PD_SK05") else 0.0
			sample["analysis_selected_band_id"] = selected_band_id
			sample["analysis_express"] = express
			state["sample"] = sample
			state["elapsed_seconds"] = 0.0
			state["status"] = "analyzing"
			state["last_message"] = "Анализ керна начат"
			return MATH.ok("Экспресс-анализ начат" if express else "Необязательный спектральный анализ начат")
		"industrial_analysis":
			if String(state.get("status", "")) != "ready" or state.get("sample", {}).is_empty():
				return MATH.fail("Для дополнительного анализа нужна готовая проба")
			var sample: Dictionary = state["sample"]
			if not sample.get("industrial_analysis", {}).is_empty():
				return MATH.fail("Дополнительный анализ уже выполняется")
			var task_id := String(args.get("task_id", ""))
			var duration := float(args.get("duration_s", 0.0))
			if task_id.is_empty() or not is_finite(duration) or duration <= 0.0:
				return MATH.fail("Неверные параметры дополнительного анализа")
			var industrial := load("res://gameplay/IndustrialFeatures.gd")
			if industrial == null or not industrial.call("authorize_pd_analysis_task", p, task_id):
				return MATH.fail("Дополнительный анализ должен быть оплачен и запущен изученным промышленным узлом")
			sample["industrial_analysis"] = {"task_id":task_id, "duration_s":duration, "sample_seed":int(sample.get("seed", 0))}
			state["sample"] = sample
			state["elapsed_seconds"] = 0.0
			state["status"] = "analyzing"
			state["last_message"] = "Дополнительный анализ начат; производственный образец не меняется"
			return MATH.ok("Дополнительный анализ оплачен и начат")
		"start_cycle":
			if String(state.get("status", "")) != "ready":
				return MATH.fail("Сначала завершите отбор пробы")
			if not _pd_start_cycle(p, state, false):
				return MATH.fail(String(state.get("last_message", "Не удалось начать цикл")))
			return MATH.ok("Цикл концентрации начат")
		"set_automatic":
			var enabled := bool(args.get("enabled", false))
			var industrial = load("res://gameplay/IndustrialFeatures.gd")
			if industrial != null:
				industrial.call("set_pd_selected_lens_automatic", p, false)
			state["automatic"] = enabled
			if enabled:
				state["lens_id"] = String(data.get("balanced_lens_id", state.get("lens_id", "")))
				_pd_auto_kick(p, state)
			return MATH.ok("Сбалансированный автоматический режим " + ("включён" if enabled else "выключен"))
		"set_selected_lens_automatic":
			if int(MATH.game(p).get("progression", {}).get("research", {}).get("PD18", 0)) <= 0:
				return MATH.fail("Для автозапуска выбранной линзы изучите PD18")
			var enabled := bool(args.get("enabled", false))
			if enabled and _lens_definition(p, String(state.get("lens_id", ""))).is_empty():
				return MATH.fail("Сначала выберите известную геологическую линзу")
			var industrial = load("res://gameplay/IndustrialFeatures.gd")
			if industrial == null:
				return MATH.fail("Модель промышленной автоматизации недоступна")
			industrial.call("set_pd_selected_lens_automatic", p, enabled)
			state["automatic"] = enabled
			if enabled:
				_pd_auto_kick(p, state)
			return MATH.ok("Автоматизация выбранной линзы " + ("включена" if enabled else "выключена"))
		"resume":
			if _pd_resume(p, state):
				return MATH.ok("Операция продолжена")
			return MATH.fail(String(state.get("last_message", "Пока недостаточно средств или места")))
		"cancel":
			if String(state.get("status", "")) in ["idle", "cancelled"]:
				return MATH.fail("Нет активной операции")
			state["automatic"] = false
			state["sample"] = {}
			state["elapsed_seconds"] = 0.0
			state["status"] = "cancelled"
			state["wait_action"] = ""
			state["last_message"] = "Операция отменена; уже понесённые расходы не возвращены"
			MATH.stat(p, "pd_operations_cancelled")
			return MATH.ok(String(state["last_message"]))
		_:
			return MATH.fail("Неизвестное действие для П-7")


static func _act_ir(p: Dictionary, state: Dictionary, action: String, args: Dictionary) -> Dictionary:
	match action:
		"set_strategy":
			if _ir_is_active(state):
				return MATH.fail("Стратегию можно менять только между кампаниями")
			var strategy_id := String(args.get("strategy_id", ""))
			if _strategy_definition(strategy_id).is_empty():
				return MATH.fail("Неизвестная стратегия И-9")
			state["strategy_id"] = strategy_id
			return MATH.ok("Стратегия выбрана; расходы будут показаны в прогнозе")
		"start_campaign":
			var strategy_id := String(args.get("strategy_id", state.get("strategy_id", "reliable")))
			if not _start_ir_campaign(p, state, strategy_id, args):
				return MATH.fail(String(state.get("last_message", "Не удалось начать кампанию")))
			return MATH.ok("Маршрут И-9 зафиксирован; seed сохранён в кампании")
		"configure_unstarted_phase":
			return _configure_unstarted_ir_phase(p, state, args)
		"cool":
			if not _ir_is_active(state):
				return MATH.fail("Охлаждение доступно во время кампании")
			var cooling: Dictionary = _site_data("ir").get("cooling_action", {})
			var campaign: Dictionary = state.get("campaign", {})
			var cost := int(cooling.get("cost_cents", 0))
			if String(campaign.get("strategy_id", "")) == "forced":
				var reduction := clampf(MATH.bonus(p, "ir:forced_cooling_energy_reduction", "ir"), 0.0, 1.0)
				cost = maxi(1, int(floor(float(cost) * (1.0 - reduction) + EPSILON)))
			if not MATH.pay(p, cost):
				return MATH.fail("Недостаточно гелионов для охлаждения")
			var ambient := float(_site_data("ir").get("ambient_temperature_c", 20.0))
			state["temperature_c"] = maxf(ambient, float(state.get("temperature_c", ambient)) - float(cooling.get("temperature_drop_c", 0.0)))
			campaign["cooling_actions"] = int(campaign.get("cooling_actions", 0)) + 1
			state["campaign"] = campaign
			MATH.stat(p, "ir_cooling_actions")
			return MATH.ok("Охлаждение оплачено гелионами; температура снижена")
		"resume":
			if _ir_resume(p, state):
				return MATH.ok("Кампания продолжена")
			return MATH.fail(String(state.get("last_message", "Пока недостаточно средств или места")))
		"cancel":
			if not _ir_is_active(state):
				return MATH.fail("Нет активной кампании")
			var campaign: Dictionary = state.get("campaign", {})
			campaign["status"] = "cancelled"
			state["campaign"] = campaign
			state["status"] = "cancelled"
			state["wait_action"] = ""
			state["last_message"] = "Кампания отменена; списанные расходы не возвращены, будущие фазы не оплачены"
			MATH.stat(p, "ir_campaigns_cancelled")
			return MATH.ok(String(state["last_message"]))
		_:
			return MATH.fail("Неизвестное действие для И-9")


static func _pd_is_idle_for_selection(state: Dictionary) -> bool:
	return String(state.get("status", "idle")) in ["idle", "cancelled"] and state.get("sample", {}).is_empty()


static func _pd_start_sample(p: Dictionary, state: Dictionary, lens: Dictionary, automatic: bool, use_contract_profile: bool = true) -> bool:
	var industrial := load("res://gameplay/IndustrialFeatures.gd")
	var contract_profile: Dictionary = industrial.call("contract_lens_profile", p) if industrial != null and use_contract_profile else {}
	if not contract_profile.is_empty():
		var contract_lens := _lens_definition(p, String(contract_profile.get("lens_id", "")))
		if not contract_lens.is_empty():
			lens = contract_lens
	var reagent_reduction := clampf(MATH.bonus(p, "pd:reagent_cost_reduction", "pd"), 0.0, 1.0)
	var cost := maxi(0, int(floor(float(lens.get("sample_cost_cents", 0)) * (1.0 - reagent_reduction) + EPSILON)))
	if int(state.get("pending_output", 0)) > 0 or MATH.stored(p) >= MATH.capacity(p):
		state["last_message"] = "Освободите место на складе перед новым циклом"
		if automatic:
			state["status"] = "waiting_storage"
		return false
	if not MATH.pay(p, cost):
		state["last_message"] = "Недостаточно гелионов для отбора пробы"
		if automatic:
			state["status"] = "waiting_funds"
			state["wait_action"] = "sample"
		return false
	var seed := _next_seed(p, state, "pd")
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var profile := _profile_scale(p, "pd")
	var sample_duration := rng.randf_range(float(lens.get("sample_seconds_min", 25.0)), float(lens.get("sample_seconds_max", 35.0)))
	var base_cycle_duration := rng.randf_range(float(lens.get("cycle_seconds_min", 100.0)), float(lens.get("cycle_seconds_max", 140.0)))
	var operating_cost := int(lens.get("operating_cost_cents", 0))
	var cycle_speed := 0.0
	if String(lens.get("id", "")) == "pd_lens_bulk":
		var chemical_reduction := clampf(MATH.bonus(p, "pd:chemical_cost_reduction", "pd"), 0.0, 1.0)
		operating_cost = maxi(0, int(floor(float(operating_cost) * (1.0 - chemical_reduction) + EPSILON)))
		cycle_speed = maxf(0.0, MATH.bonus(p, "pd:bulk_processing_speed", "pd"))
	var sample := {
		"lens_id": String(lens.get("id", "")),
		"seed": seed,
		"spectral_profile": _pd_spectral_profile(seed),
		"quality": rng.randf_range(float(lens.get("quality_min", 0.65)), float(lens.get("quality_max", 0.9))),
		"base_yield": rng.randi_range(int(lens.get("yield_min", 3)), int(lens.get("yield_max", 5))),
		"sample_duration_s": sample_duration / float(profile["speed"]),
		"cycle_duration_s": base_cycle_duration / float(profile["speed"]) / maxf(0.1, 1.0 + cycle_speed),
		"sample_cost_cents": cost,
		"operating_cost_cents": operating_cost,
		"analysis_completed": false,
		"analysis_bonus": 0.0,
		"analysis_skill_bonus": 0.0,
		"yield_units": 0,
	}
	state["sample"] = sample
	state["lens_id"] = String(lens.get("id", state.get("lens_id", "")))
	state["elapsed_seconds"] = 0.0
	state["status"] = "sampling"
	state["wait_action"] = ""
	state["last_message"] = "Отбор пробы начат"
	if not contract_profile.is_empty() and industrial != null:
		industrial.call("consume_contract_lens", p, String(contract_profile.get("order_id", "")))
	MATH.stat(p, "pd_samples_started")
	return true

static func _pd_spectral_profile(seed: int) -> Dictionary:
	var regions: Array = _industrial_cfg().get("pd", {}).get("spectral_analysis", {}).get("impurity_regions", ["sulfide", "silicate", "oxide"])
	if regions.size() < 2: regions = ["sulfide", "silicate"]
	var rng := RandomNumberGenerator.new()
	rng.seed = seed + 49031
	var target_region_index := rng.randi_range(0, regions.size() - 1)
	var other_region_index := (target_region_index + 1) % regions.size()
	var target_band_index := rng.randi_range(0, 1)
	var target_band_id := "spectrum_a" if target_band_index == 0 else "spectrum_b"
	var target_band_intensity := snappedf(rng.randf_range(0.72, 0.98), 0.01)
	var other_band_intensity := snappedf(rng.randf_range(0.12, 0.46), 0.01)
	var bands := [
		{"id":"spectrum_a", "label":"Спектральная полоса A", "intensity":target_band_intensity if target_band_index == 0 else other_band_intensity},
		{"id":"spectrum_b", "label":"Спектральная полоса B", "intensity":target_band_intensity if target_band_index == 1 else other_band_intensity},
	]
	return {"bands":bands, "target_band_id":target_band_id, "target_impurity_region":str(regions[target_region_index]), "other_impurity_region":str(regions[other_region_index])}

static func _pd_contract_value_readouts(p: Dictionary, lens_rows: Array) -> Array:
	var result: Array = []
	var active: Dictionary = MATH.game(p).get("progression", {}).get("contracts", {}).get("active", {})
	var reference_price := int(_site_data("pd").get("reference_sale_price_cents_per_unit", 0))
	for order_id in active:
		var order: Dictionary = active[order_id]
		if str(order.get("status", "")) != "accepted": continue
		var required := int(order.get("items", {}).get("pd_concentrate", 0))
		if required <= 0: continue
		var remaining := maxi(0, required - int(p.get("inventory", {}).get("pd_concentrate", 0)))
		var reward_cents := int(order.get("reward", {}).get("money_cents", 0))
		for lens in lens_rows:
			var expected := float(lens.get("expected_yield", 0.0))
			var completed := expected >= float(remaining)
			var surplus := maxf(0.0, expected - float(remaining))
			var contract_reward := reward_cents if completed else 0
			var net_value := contract_reward + int(floor(surplus * reference_price)) - int(lens.get("cost_cents", 0))
			result.append({"order_id":str(order_id), "contract_id":str(order.get("contract_id", order_id)), "lens_id":str(lens.get("id", "")), "remaining_units":remaining, "expected_yield":expected, "completion_expected":completed, "reward_cents":contract_reward, "projected_net_value_cents":net_value})
	return result

static func _ir_skill_readouts(p: Dictionary, phases: Array) -> Dictionary:
	var readouts: Dictionary = {}
	var strategy := _strategy_definition(str(MATH.game(p).get("extraction", {}).get("ir", {}).get("strategy_id", "reliable")))
	var base_cooling := float(_site_data("ir").get("base_cooling_rate_c_per_second", 0.0)) + float(strategy.get("cooling_rate_c_per_second", 0.0))
	var peak_heat_phase: Dictionary = {}
	var max_cooling_phase: Dictionary = {}
	var max_heat := -1.0
	var max_cooling_load := -1.0
	for phase in phases:
		var heat := float(phase.get("heat_c_per_second", 0.0))
		if heat > max_heat:
			max_heat = heat
			peak_heat_phase = phase
		var cooling_load := maxf(0.0, heat * float(strategy.get("heat_multiplier", 1.0)) - base_cooling)
		if cooling_load > max_cooling_load:
			max_cooling_load = cooling_load
			max_cooling_phase = phase
	if _has_mastery(p, "IR_SK01"):
		readouts["IR_SK01"] = {"support_phase_id":str(peak_heat_phase.get("id", "")), "support_phase_name":str(peak_heat_phase.get("name", "")), "peak_heat_c_per_second":max_heat}
	if _has_mastery(p, "IR_SK02"):
		readouts["IR_SK02"] = {"maximum_cooling_phase_id":str(max_cooling_phase.get("id", "")), "maximum_cooling_phase_name":str(max_cooling_phase.get("name", "")), "projected_cooling_load_c_per_second":max_cooling_load}
	if _has_mastery(p, "IR_SK03"):
		var comparisons: Array = []
		var safe_temperature := float(_site_data("ir").get("safe_temperature_c", 80.0))
		for option in _ir_strategy_projections(p):
			var projected_peak := float(option.get("projection", {}).get("projected_peak_temperature_c", 0.0))
			comparisons.append({"strategy_id":str(option.get("id", "")), "name":str(option.get("name", "")), "projected_peak_temperature_c":projected_peak, "stability_margin_c":safe_temperature - projected_peak})
		readouts["IR_SK03"] = {"strategy_comparisons":comparisons, "safe_temperature_c":safe_temperature}
	return readouts

static func _has_mastery(p: Dictionary, id: String) -> bool:
	return int(MATH.game(p).get("progression", {}).get("mastery", {}).get(id, 0)) > 0

static func _industrial_cfg() -> Dictionary:
	var path := "res://data/proposals/industrial_features.json"
	if not FileAccess.file_exists(path): return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


static func _pd_start_cycle(p: Dictionary, state: Dictionary, automatic: bool) -> bool:
	var sample: Dictionary = state.get("sample", {})
	if sample.is_empty():
		state["last_message"] = "Нет готовой пробы"
		return false
	if int(state.get("pending_output", 0)) > 0 or MATH.stored(p) >= MATH.capacity(p):
		state["last_message"] = "Освободите место на складе перед циклом концентрации"
		if automatic:
			state["status"] = "waiting_storage"
		return false
	var industrial := load("res://gameplay/IndustrialFeatures.gd")
	var filter_profile: Dictionary = industrial.call("pd_filter_profile", p) if industrial != null else {}
	var cost := int(sample.get("operating_cost_cents", 0))
	if not filter_profile.is_empty():
		cost = maxi(0, int(floor(float(cost) * (1.0 - clampf(float(filter_profile.get("next_cycle_cost_reduction", 0.0)), 0.0, 1.0)) + EPSILON)))
	if not MATH.pay(p, cost):
		state["last_message"] = "Недостаточно гелионов для цикла концентрации"
		if automatic:
			state["status"] = "waiting_funds"
			state["wait_action"] = "start_cycle"
		return false
	if not filter_profile.is_empty() and industrial != null:
		sample["cycle_duration_s"] = float(sample.get("cycle_duration_s", 0.0)) * maxf(0.1, float(filter_profile.get("next_cycle_duration_multiplier", 1.0)))
		industrial.call("consume_pd_filter_prep", p)
	var pd_data := _site_data("pd")
	var profile := _profile_scale(p, "pd")
	var bonus_cap := float(sample.get("analysis_bonus_cap", 0.0)) if bool(sample.get("analysis_completed", false)) else 0.0
	var score_bonus := float(sample.get("analysis_score", 0.0)) * bonus_cap
	var analysis_bonus := minf(float(sample.get("analysis_bonus", 0.0)), bonus_cap) if bonus_cap > 0.0 else 0.0
	analysis_bonus = maxf(analysis_bonus, score_bonus)
	var quality_factor := 0.75 + float(sample.get("quality", 0.0)) * 0.5
	sample["analysis_bonus"] = analysis_bonus
	var skill_bonus := float(sample.get("analysis_skill_bonus", 0.0)) if bool(sample.get("analysis_completed", false)) else 0.0
	sample["yield_units"] = maxi(1, int(floor(float(sample.get("base_yield", 1)) * quality_factor * (1.0 + analysis_bonus + skill_bonus) * float(profile["output"]))))
	sample["projected_cost_cents"] = int(sample.get("sample_cost_cents", 0)) + cost
	sample["projected_wages_cents"] = _projected_wages(p, "pd", float(sample.get("sample_duration_s", 0.0)) + float(sample.get("cycle_duration_s", 0.0)), pd_data)
	state["sample"] = sample
	state["elapsed_seconds"] = 0.0
	state["status"] = "concentrating"
	state["wait_action"] = ""
	state["last_message"] = "Цикл концентрации начат"
	MATH.stat(p, "pd_cycles_started")
	return true


static func _pd_auto_kick(p: Dictionary, state: Dictionary) -> void:
	if not bool(state.get("automatic", false)):
		return
	if int(state.get("pending_output", 0)) > 0:
		state["status"] = "waiting_storage"
		return
	if String(state.get("status", "")) in ["idle", "cancelled"]:
		var industrial = load("res://gameplay/IndustrialFeatures.gd")
		var selected_lens_id := str(industrial.call("pd_selected_auto_lens_id", p)) if industrial != null else ""
		var uses_selected_lens := not selected_lens_id.is_empty()
		var lens_id := selected_lens_id if uses_selected_lens else String(_site_data("pd").get("balanced_lens_id", ""))
		var lens := _lens_definition(p, lens_id)
		if lens.is_empty():
			lens = _lens_definition(p, String(_site_data("pd").get("balanced_lens_id", "")))
		_pd_start_sample(p, state, lens, true, not uses_selected_lens)
	elif String(state.get("status", "")) == "ready":
		_pd_start_cycle(p, state, true)


static func _pd_resume(p: Dictionary, state: Dictionary) -> bool:
	var status := String(state.get("status", ""))
	if status == "waiting_funds":
		var action := String(state.get("wait_action", ""))
		if action == "sample":
			var industrial = load("res://gameplay/IndustrialFeatures.gd")
			var selected_lens_id := str(industrial.call("pd_selected_auto_lens_id", p)) if industrial != null else ""
			var lens_id := selected_lens_id if not selected_lens_id.is_empty() else String(state.get("lens_id", ""))
			return _pd_start_sample(p, state, _lens_definition(p, lens_id), true, selected_lens_id.is_empty())
		if action == "start_cycle":
			state["status"] = "ready"
			return _pd_start_cycle(p, state, true)
		if action == "wages" and int(p.get("money_cents", 0)) > 0:
			state["status"] = String(state.get("resume_status", "sampling"))
			state["wait_action"] = ""
			return true
	if status == "waiting_storage":
		_pd_deliver_pending(p, state)
		if int(state.get("pending_output", 0)) == 0:
			state["status"] = "idle"
			if not bool(state.get("one_shot_contract_clean", false)):
				_pd_auto_kick(p, state)
			return true
	state["last_message"] = "Пока недостаточно средств или места"
	return false


static func _advance_pd(p: Dictionary, state: Dictionary, seconds: float) -> void:
	var remaining := seconds + float(state.get("backlog_seconds", 0.0))
	state["backlog_seconds"] = 0.0
	var steps := 0
	while remaining > EPSILON and steps < MAX_STEPS_PER_ADVANCE:
		steps += 1
		_pd_deliver_pending(p, state)
		var status := String(state.get("status", "idle"))
		if status == "waiting_storage":
			if int(state.get("pending_output", 0)) > 0:
				break
			state["status"] = "idle"
			_pd_auto_kick(p, state)
			status = String(state.get("status", "idle"))
		if status == "waiting_funds":
			if not _pd_resume(p, state):
				break
			status = String(state.get("status", "idle"))
		if status in ["idle", "cancelled"] and bool(state.get("automatic", false)):
			_pd_auto_kick(p, state)
			status = String(state.get("status", "idle"))
		if status == "ready" and bool(state.get("automatic", false)):
			_pd_auto_kick(p, state)
			status = String(state.get("status", "ready"))
		if status not in ["sampling", "analyzing", "concentrating"]:
			break
		var sample: Dictionary = state.get("sample", {})
		var duration := _pd_duration_for_status(sample, status)
		var stage_remaining := maxf(0.0, duration - float(state.get("elapsed_seconds", 0.0)))
		if stage_remaining <= EPSILON:
			_pd_finish_stage(p, state, status)
			continue
		var requested := minf(remaining, stage_remaining)
		var spent := _bill_wages(p, "pd", state, requested, _site_data("pd"))
		if spent > 0.0:
			state["elapsed_seconds"] = float(state.get("elapsed_seconds", 0.0)) + spent
			remaining -= spent
		if spent + EPSILON < requested:
			state["resume_status"] = status
			state["status"] = "waiting_funds"
			state["wait_action"] = "wages"
			state["last_message"] = "Операция приостановлена: не хватает гелионов на зарплату"
			break
		if float(state.get("elapsed_seconds", 0.0)) + EPSILON >= duration:
			_pd_finish_stage(p, state, status)
	if remaining > EPSILON and steps >= MAX_STEPS_PER_ADVANCE:
		state["backlog_seconds"] = float(state.get("backlog_seconds", 0.0)) + remaining


static func _pd_finish_stage(p: Dictionary, state: Dictionary, status: String) -> void:
	state["elapsed_seconds"] = 0.0
	if status == "sampling":
		state["status"] = "ready"
		state["last_message"] = "Проба готова"
		if bool(state.get("automatic", false)):
			_pd_start_cycle(p, state, true)
	elif status == "analyzing":
		var sample: Dictionary = state.get("sample", {})
		var industrial_analysis: Dictionary = sample.get("industrial_analysis", {})
		if not industrial_analysis.is_empty():
			var task_id := String(industrial_analysis.get("task_id", ""))
			var sample_seed := int(industrial_analysis.get("sample_seed", sample.get("seed", 0)))
			sample.erase("industrial_analysis")
			state["sample"] = sample
			state["status"] = "ready"
			state["last_message"] = "Дополнительный анализ завершён; производственная проба сохранена"
			var industrial := load("res://gameplay/IndustrialFeatures.gd")
			if industrial != null:
				industrial.call("on_pd_industrial_analysis_completed", p, task_id, sample_seed)
			return
		sample["analysis_completed"] = true
		sample["analysis_bonus"] = float(sample.get("analysis_score", 0.0)) * float(sample.get("analysis_bonus_cap", 0.0))
		state["sample"] = sample
		state["status"] = "ready"
		state["last_message"] = "Анализ керна завершён"
		MATH.stat(p, "pd_samples_analyzed")
		if bool(state.get("automatic", false)):
			_pd_start_cycle(p, state, true)
	elif status == "concentrating":
		var sample: Dictionary = state.get("sample", {})
		var output := maxi(0, int(sample.get("yield_units", 0)))
		state["pending_output"] = int(state.get("pending_output", 0)) + output
		state["sample"] = {}
		state["status"] = "idle"
		state["cycles_completed"] = int(state.get("cycles_completed", 0)) + 1
		state["last_message"] = "Концентрация завершена"
		var site_profile := MATH.site(p, "pd")
		site_profile["mined"] = float(site_profile.get("mined", 0.0)) + output
		MATH.stat(p, "pd_cycles_completed")
		MATH.stat(p, "pd_concentrate_mined", output)
		_pd_deliver_pending(p, state)
		if int(state.get("pending_output", 0)) > 0:
			state["status"] = "waiting_storage"
		if bool(state.get("one_shot_contract_clean", false)):
			state["automatic"] = false
			state["one_shot_contract_clean"] = false
			state["last_message"] = "Один контрактный Pd-цикл завершён; автоповтор не включён"
			var industrial := load("res://gameplay/IndustrialFeatures.gd")
			if industrial != null: industrial.call("complete_pd_one_shot_clean", p)
		elif int(state.get("pending_output", 0)) == 0 and bool(state.get("automatic", false)):
			_pd_auto_kick(p, state)


static func _pd_duration_for_status(sample: Dictionary, status: String) -> float:
	if status == "sampling":
		return float(sample.get("sample_duration_s", 0.0))
	if status == "analyzing":
		var industrial_analysis: Dictionary = sample.get("industrial_analysis", {})
		if not industrial_analysis.is_empty():
			return float(industrial_analysis.get("duration_s", 0.0))
		return float(sample.get("analysis_duration_s", 0.0))
	return float(sample.get("cycle_duration_s", 0.0))


static func _pd_deliver_pending(p: Dictionary, state: Dictionary) -> void:
	var pending := maxi(0, int(state.get("pending_output", 0)))
	if pending == 0:
		return
	var accepted := MATH.add(p, "pd_concentrate", pending)
	state["pending_output"] = pending - accepted


static func _pd_view(p: Dictionary, state: Dictionary) -> Dictionary:
	var sample: Dictionary = state.get("sample", {}).duplicate(true)
	var skill_readouts: Dictionary = {}
	if not sample.is_empty():
		var spectrum: Dictionary = sample.get("spectral_profile", {}).duplicate(true)
		spectrum.erase("target_band_id")
		spectrum.erase("target_impurity_region")
		sample["spectral_profile"] = spectrum
		if _has_mastery(p, "PD_SK01"):
			sample["highlighted_impurity_region"] = str(state.get("sample", {}).get("spectral_profile", {}).get("target_impurity_region", ""))
			skill_readouts["PD_SK01"] = {"highlighted_impurity_region":sample["highlighted_impurity_region"], "sample_seed":int(sample.get("seed", 0))}
	var lens_rows: Array = _pd_lens_projections(p)
	if _has_mastery(p, "PD_SK03"):
		var comparisons: Array = []
		for row in lens_rows:
			if str(row.get("id", "")) in ["pd_lens_high_grade", "pd_lens_balanced", "pd_lens_bulk"]:
				comparisons.append(row.duplicate(true))
		skill_readouts["PD_SK03"] = {"lens_comparison":comparisons}
	if _has_mastery(p, "PD_SK04"):
		skill_readouts["PD_SK04"] = {"active_contract_values":_pd_contract_value_readouts(p, lens_rows)}
	var lens := _lens_definition(p, String(state.get("lens_id", "")))
	var current_seconds := float(state.get("elapsed_seconds", 0.0))
	var remaining := 0.0
	if not sample.is_empty() and String(state.get("status", "")) in ["sampling", "analyzing", "concentrating"]:
		remaining = maxf(0.0, _pd_duration_for_status(sample, String(state["status"])) - current_seconds)
	return {
		"site": SITE_IDS["pd"],
		"unlocked": true,
		"status": String(state.get("status", "idle")),
		"automatic": bool(state.get("automatic", false)),
		"lens_id": String(state.get("lens_id", "")),
		"lens": lens,
		"lens_options": lens_rows,
		"sample": sample,
		"skill_readouts": skill_readouts,
		"progress_seconds": current_seconds,
		"remaining_seconds": remaining,
		"pending_output": int(state.get("pending_output", 0)),
		"output_item": String(_site_data("pd").get("output_item", "pd_concentrate")),
		"cycles_completed": int(state.get("cycles_completed", 0)),
		"seed_counter": int(state.get("seed_counter", 0)),
		"wages_paid_cents": int(state.get("wages_paid_cents", 0)),
		"last_message": String(state.get("last_message", "")),
	}


static func _sync_expansion(p: Dictionary, site_key: String, state: Dictionary) -> void:
	var expansion_count := int(MATH.site(p, site_key).get("expansions", 0))
	if not state.has("expansion_count"):
		state["expansion_count"] = expansion_count
		return
	if int(state.get("expansion_count", expansion_count)) == expansion_count:
		return
	if site_key == "pd":
		_pd_deliver_pending(p, state)
		var had_active_sample := not Dictionary(state.get("sample", {})).is_empty() or String(state.get("status", "")) in ["sampling", "ready", "analyzing", "concentrating", "waiting_funds"]
		if had_active_sample:
			MATH.stat(p, "pd_operations_cancelled")
		state["automatic"] = false
		if had_active_sample:
			state["sample"] = {}
			state["elapsed_seconds"] = 0.0
			state["wait_action"] = ""
			state["status"] = "cancelled"
			state["last_message"] = "Локальная Экспансия отменила цикл; уже списанные затраты не возвращены"
		elif int(state.get("pending_output", 0)) > 0:
			state["status"] = "waiting_storage"
		elif String(state.get("status", "")) == "waiting_storage":
			state["status"] = "idle"
	else:
		_ir_deliver_pending(p, state)
		var campaign: Dictionary = state.get("campaign", {})
		if String(campaign.get("status", "")) in ["running", "waiting_funds"]:
			campaign["status"] = "cancelled"
			state["campaign"] = campaign
			state["status"] = "cancelled"
			state["wait_action"] = ""
			state["last_message"] = "Локальная Экспансия отменила кампанию; уже списанные расходы не возвращены"
			MATH.stat(p, "ir_campaigns_cancelled")
		state["temperature_c"] = float(_site_data("ir").get("ambient_temperature_c", 20.0))
	state["expansion_count"] = expansion_count


static func _start_ir_campaign(p: Dictionary, state: Dictionary, strategy_id: String, args: Dictionary = {}) -> bool:
	if _ir_is_active(state):
		state["last_message"] = "Сначала завершите или отмените активную кампанию"
		return false
	if int(state.get("pending_output", 0)) > 0:
		state["status"] = "waiting_storage"
		state["last_message"] = "Освободите место на складе"
		return false
	var data := _site_data("ir")
	var strategy := _strategy_definition(strategy_id)
	if strategy.is_empty():
		state["last_message"] = "Неизвестная стратегия И-9"
		return false
	var phases: Array = data.get("phases", [])
	if phases.is_empty():
		state["last_message"] = "Не загружены фазы кампании"
		return false
	var industrial := load("res://gameplay/IndustrialFeatures.gd")
	var industrial_profile: Dictionary = industrial.call("ir_campaign_profile", p, bool(args.get("deep_route", false))) if industrial != null else {}
	if bool(args.get("deep_route", false)) and industrial_profile.is_empty():
		state["last_message"] = "Глубокий маршрут требует изученного узла IR05"
		return false
	if industrial_profile.is_empty():
		industrial_profile = {"cost_multiplier":1.0, "duration_multiplier":1.0}
	var scale := _profile_scale(p, "ir")
	var thermal_projection := _projected_ir_temperature(p, strategy, phases, scale, industrial_profile)
	var costs: Array = []
	var durations: Array = []
	var total_cost := 0
	var total_duration := 0.0
	for phase_value in phases:
		var phase: Dictionary = phase_value
		var cost := maxi(0, int(round(float(phase.get("cost_cents", 0)) * float(strategy.get("cost_multiplier", 1.0)) * float(industrial_profile.get("cost_multiplier", 1.0)))))
		var setup_bonus := MATH.bonus(p, "ir:setup_duration_reduction", "ir") if String(phase.get("id", "")) == "preparation" else 0.0
		var duration := maxf(1.0, float(phase.get("duration_s", 1.0)) * float(strategy.get("duration_multiplier", 1.0)) * float(industrial_profile.get("duration_multiplier", 1.0)) / float(scale["speed"]) / maxf(0.1, 1.0 + setup_bonus))
		costs.append(cost)
		durations.append(duration)
		total_cost += cost
		total_duration += duration
	var projected_wage_cost := _projected_wages(p, "ir", total_duration, data)
	if not MATH.pay(p, int(costs[0])):
		state["last_message"] = "Недостаточно гелионов для маршрута"
		return false
	if industrial != null:
		industrial.call("consume_ir_preparations", p, industrial_profile)
	var seed := _next_seed(p, state, "ir")
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var base_yield := rng.randi_range(int(strategy.get("yield_min", 5)), int(strategy.get("yield_max", 8)))
	var campaign := {
		"seed": seed,
		"strategy_id": strategy_id,
		"status": "running",
		"phase_index": 0,
		"phase_elapsed_s": 0.0,
		"phase_durations_s": durations,
		"phase_costs_cents": costs,
		"phase_paid": [true] + _false_array(phases.size() - 1),
		"raw_yield": base_yield,
		"quality": rng.randf_range(float(strategy.get("quality_min", 0.7)), float(strategy.get("quality_max", 0.95))),
		"projected_cost_cents": total_cost + projected_wage_cost,
		"projected_operation_cost_cents": total_cost,
		"projected_wage_cost_cents": projected_wage_cost,
		"committed_cost_cents": int(costs[0]),
		"wage_cost_paid_cents": 0,
		"projected_duration_s": total_duration,
		"projected_peak_temperature_c": float(thermal_projection.get("peak_temperature_c", 0.0)),
		"thermal_stress": 0.0,
		"cooling_actions": 0,
		"cooling_mode_id": str(industrial_profile.get("cooling_mode_id", "")),
		"cooling_rate_multiplier": float(industrial_profile.get("cooling_rate_multiplier", 1.0)),
		"industrial_deep_route": bool(industrial_profile.get("deep", false)),
	}
	var program: Dictionary = MATH.game(p).get("feature_families", {}).get("industrial", {}).get("ir", {}).get("program", {})
	if bool(program.get("start_pending", false)):
		campaign["industrial_program_id"] = str(program.get("id", ""))
		program["start_pending"] = false
		program["current_seed"] = seed
	else:
		campaign["industrial_program_id"] = ""
	state["campaign"] = campaign
	state["strategy_id"] = strategy_id
	state["status"] = "running"
	state["wait_action"] = ""
	state["last_message"] = "Кампания начата"
	MATH.stat(p, "ir_campaigns_started")
	return true


static func _advance_ir(p: Dictionary, state: Dictionary, seconds: float) -> void:
	var remaining := seconds + float(state.get("backlog_seconds", 0.0))
	state["backlog_seconds"] = 0.0
	var steps := 0
	while remaining > EPSILON and steps < MAX_STEPS_PER_ADVANCE:
		steps += 1
		_ir_deliver_pending(p, state)
		var status := String(state.get("status", "idle"))
		if status == "waiting_storage":
			if int(state.get("pending_output", 0)) > 0:
				break
			state["status"] = "completed"
			status = "completed"
		if status == "waiting_funds":
			if not _ir_resume(p, state):
				break
			status = String(state.get("status", ""))
		if status != "running":
			_ir_relax_temperature(state, remaining)
			remaining = 0.0
			break
		var campaign: Dictionary = state.get("campaign", {})
		var phases: Array = _site_data("ir").get("phases", [])
		var index := int(campaign.get("phase_index", 0))
		if index >= phases.size():
			_ir_finish_campaign(p, state)
			continue
		var phase: Dictionary = phases[index]
		var durations: Array = campaign.get("phase_durations_s", [])
		var duration := float(durations[index]) if index < durations.size() else 1.0
		var elapsed := float(campaign.get("phase_elapsed_s", 0.0))
		var stage_remaining := maxf(0.0, duration - elapsed)
		if stage_remaining <= EPSILON:
			if not _ir_complete_phase(p, state, campaign, phases):
				break
			continue
		var requested := minf(remaining, stage_remaining)
		var spent := _bill_wages(p, "ir", state, requested, _site_data("ir"))
		if spent > 0.0:
			_ir_apply_thermal_tick(p, state, campaign, phase, spent)
			campaign["phase_elapsed_s"] = elapsed + spent
			state["campaign"] = campaign
			remaining -= spent
		if spent + EPSILON < requested:
			campaign["status"] = "waiting_funds"
			state["campaign"] = campaign
			state["resume_status"] = "running"
			state["status"] = "waiting_funds"
			state["wait_action"] = "wages"
			state["last_message"] = "Кампания приостановлена: не хватает гелионов на зарплату"
			break
		if float(campaign.get("phase_elapsed_s", 0.0)) + EPSILON >= duration:
			if not _ir_complete_phase(p, state, campaign, phases):
				break
	if remaining > EPSILON and steps >= MAX_STEPS_PER_ADVANCE:
		state["backlog_seconds"] = float(state.get("backlog_seconds", 0.0)) + remaining


static func _ir_complete_phase(p: Dictionary, state: Dictionary, campaign: Dictionary, phases: Array) -> bool:
	var next_index := int(campaign.get("phase_index", 0)) + 1
	campaign["phase_index"] = next_index
	campaign["phase_elapsed_s"] = 0.0
	if next_index >= phases.size():
		state["campaign"] = campaign
		_ir_finish_campaign(p, state)
		return true
	state["campaign"] = campaign
	if bool(campaign.get("pause_after_phase", false)):
		campaign["pause_after_phase"] = false
		campaign["status"] = "paused"
		state["campaign"] = campaign
		state["status"] = "paused"
		state["wait_action"] = ""
		state["last_message"] = "Плановая пауза между фазами; следующая фаза ещё не оплачена"
		return false
	if not _ir_pay_phase(p, state, campaign, next_index):
		campaign["status"] = "waiting_funds"
		state["campaign"] = campaign
		state["status"] = "waiting_funds"
		state["wait_action"] = "phase_cost"
		state["last_message"] = "Кампания ждёт гелионов на следующую фазу"
		return false
	campaign["status"] = "running"
	state["campaign"] = campaign
	state["status"] = "running"
	return true


static func _ir_pay_phase(p: Dictionary, state: Dictionary, campaign: Dictionary, index: int) -> bool:
	var paid: Array = campaign.get("phase_paid", [])
	if index >= paid.size() or bool(paid[index]):
		return true
	var costs: Array = campaign.get("phase_costs_cents", [])
	var cost := int(costs[index]) if index < costs.size() else 0
	if not MATH.pay(p, cost):
		return false
	paid[index] = true
	campaign["phase_paid"] = paid
	campaign["committed_cost_cents"] = int(campaign.get("committed_cost_cents", 0)) + cost
	state["campaign"] = campaign
	return true


static func _ir_resume(p: Dictionary, state: Dictionary) -> bool:
	if String(state.get("status", "")) == "waiting_storage":
		_ir_deliver_pending(p, state)
		if int(state.get("pending_output", 0)) == 0:
			state["status"] = "completed"
			return true
		state["last_message"] = "Освободите место на складе"
		return false
	var current_status := String(state.get("status", ""))
	if current_status == "paused":
		var paused_campaign: Dictionary = state.get("campaign", {})
		var paused_index := int(paused_campaign.get("phase_index", 0))
		if not _ir_pay_phase(p, state, paused_campaign, paused_index):
			paused_campaign["status"] = "waiting_funds"
			state["campaign"] = paused_campaign
			state["status"] = "waiting_funds"
			state["wait_action"] = "phase_cost"
			state["last_message"] = "Пауза сохранена: не хватает гелионов для следующей фазы"
			return false
		paused_campaign["status"] = "running"
		state["campaign"] = paused_campaign
		state["status"] = "running"
		state["wait_action"] = ""
		return true
	if current_status != "waiting_funds":
		return false
	var campaign: Dictionary = state.get("campaign", {})
	var wait_action := String(state.get("wait_action", ""))
	if wait_action == "phase_cost":
		var index := int(campaign.get("phase_index", 0))
		if not _ir_pay_phase(p, state, campaign, index):
			state["last_message"] = "Недостаточно гелионов для следующей фазы"
			return false
		campaign["status"] = "running"
		state["campaign"] = campaign
		state["status"] = "running"
		state["wait_action"] = ""
		return true
	if wait_action == "wages" and int(p.get("money_cents", 0)) > 0:
		campaign["status"] = "running"
		state["campaign"] = campaign
		state["status"] = "running"
		state["wait_action"] = ""
		return true
	state["last_message"] = "Пока недостаточно гелионов"
	return false


static func _ir_finish_campaign(p: Dictionary, state: Dictionary) -> void:
	var campaign: Dictionary = state.get("campaign", {})
	var strategy := _strategy_definition(String(campaign.get("strategy_id", "")))
	var data := _site_data("ir")
	var max_stress := maxf(1.0, float(data.get("thermal_stress_for_max_penalty_c_seconds", 12000.0)))
	var max_penalty := clampf(float(data.get("max_thermal_penalty", 0.4)), 0.0, 0.8)
	var thermal_penalty := minf(max_penalty, float(campaign.get("thermal_stress", 0.0)) / max_stress * max_penalty)
	var profile := _profile_scale(p, "ir")
	var quality_factor := 0.8 + float(campaign.get("quality", 0.0)) * 0.4
	var output := maxi(1, int(floor(float(campaign.get("raw_yield", 1)) * float(strategy.get("yield_multiplier", 1.0)) * quality_factor * (1.0 - thermal_penalty) * float(profile["output"]))))
	campaign["status"] = "completed"
	campaign["thermal_penalty"] = thermal_penalty
	campaign["output_units"] = output
	state["campaign"] = campaign
	state["pending_output"] = int(state.get("pending_output", 0)) + output
	state["status"] = "completed"
	state["wait_action"] = ""
	state["campaigns_completed"] = int(state.get("campaigns_completed", 0)) + 1
	state["last_message"] = "Кампания завершена: получено ядро иридия"
	var site_profile := MATH.site(p, "ir")
	site_profile["mined"] = float(site_profile.get("mined", 0.0)) + output
	MATH.stat(p, "ir_campaigns_completed")
	MATH.stat(p, "ir_core_mined", output)
	_ir_deliver_pending(p, state)
	if int(state.get("pending_output", 0)) > 0:
		state["status"] = "waiting_storage"
	var industrial := load("res://gameplay/IndustrialFeatures.gd")
	if industrial != null:
		var next_program: Dictionary = industrial.call("on_ir_campaign_completed", p, campaign)
		if bool(next_program.get("continue", false)):
			var industrial_ir: Dictionary = MATH.game(p).get("feature_families", {}).get("industrial", {}).get("ir", {})
			var program: Dictionary = industrial_ir.get("program", {})
			if int(state.get("pending_output", 0)) > 0 or not _start_ir_campaign(p, state, str(next_program.get("strategy_id", "reliable"))):
				program["active"] = false
				program["start_pending"] = false
				industrial_ir["last_program_message"] = "Программа остановлена: склад не освобождён или следующую кампанию не удалось запустить"


static func _ir_apply_thermal_tick(p: Dictionary, state: Dictionary, campaign: Dictionary, phase: Dictionary, seconds: float) -> void:
	var data := _site_data("ir")
	var strategy := _strategy_definition(String(campaign.get("strategy_id", "")))
	var old_temperature := float(state.get("temperature_c", data.get("ambient_temperature_c", 20.0)))
	var base_cooling := float(data.get("base_cooling_rate_c_per_second", 0.0))
	var strategy_cooling := float(strategy.get("cooling_rate_c_per_second", 0.0))
	var bonus_cooling := maxf(-base_cooling, MATH.bonus(p, "cooling", "ir") * float(data.get("cooling_bonus_scale", 0.1)))
	var cooling_rate := maxf(0.0, base_cooling + strategy_cooling + bonus_cooling) * maxf(0.1, float(campaign.get("cooling_rate_multiplier", 1.0)))
	var heat_rate := float(phase.get("heat_c_per_second", 0.0)) * float(strategy.get("heat_multiplier", 1.0))
	var ambient := float(data.get("ambient_temperature_c", 20.0))
	var new_temperature := maxf(ambient, old_temperature + (heat_rate - cooling_rate) * seconds)
	state["temperature_c"] = new_temperature
	var safe_temperature := float(data.get("safe_temperature_c", 80.0))
	if String(strategy.get("id", "")) == "reliable":
		safe_temperature = ambient + (safe_temperature - ambient) * (1.0 + maxf(0.0, MATH.bonus(p, "ir:stability_margin", "ir")))
	var average_overheat := maxf(0.0, (old_temperature + new_temperature) * 0.5 - safe_temperature)
	campaign["thermal_stress"] = float(campaign.get("thermal_stress", 0.0)) + average_overheat * seconds


static func _ir_relax_temperature(state: Dictionary, seconds: float) -> void:
	var data := _site_data("ir")
	var ambient := float(data.get("ambient_temperature_c", 20.0))
	var rate := maxf(0.0, float(data.get("idle_cooling_rate_c_per_second", 0.05)))
	state["temperature_c"] = maxf(ambient, float(state.get("temperature_c", ambient)) - rate * seconds)


static func _ir_deliver_pending(p: Dictionary, state: Dictionary) -> void:
	var pending := maxi(0, int(state.get("pending_output", 0)))
	if pending == 0:
		return
	var accepted := MATH.add(p, "ir_core", pending)
	state["pending_output"] = pending - accepted


static func _ir_view(p: Dictionary, state: Dictionary) -> Dictionary:
	var campaign: Dictionary = state.get("campaign", {}).duplicate(true)
	var phases: Array = _site_data("ir").get("phases", [])
	var industrial = load("res://gameplay/IndustrialFeatures.gd")
	var cooling_profile: Dictionary = industrial.call("ir_cooling_profile", p) if industrial != null else {}
	var index := int(campaign.get("phase_index", -1))
	var phase_name := ""
	var phase_remaining := 0.0
	if index >= 0 and index < phases.size():
		phase_name = String(phases[index].get("name", phases[index].get("id", "")))
		var durations: Array = campaign.get("phase_durations_s", [])
		if index < durations.size():
			phase_remaining = maxf(0.0, float(durations[index]) - float(campaign.get("phase_elapsed_s", 0.0)))
	var projection := _ir_projection(p, String(state.get("strategy_id", "reliable")))
	var skill_readouts := _ir_skill_readouts(p, phases)
	var cleanup_reservation: Dictionary = MATH.game(p).get("reservations", {}).get("mastery:IR_SK07:priority_cleanup", {})
	return {
		"site": SITE_IDS["ir"],
		"unlocked": true,
		"status": String(state.get("status", "idle")),
		"strategy_id": String(state.get("strategy_id", "reliable")),
		"strategies": strategy_definitions(),
		"strategy_options": _ir_strategy_projections(p),
		"campaign": campaign,
		"seed": int(campaign.get("seed", 0)),
		"phase": phase_name,
		"phase_index": index,
		"phase_remaining_seconds": phase_remaining,
		"temperature_c": float(state.get("temperature_c", 20.0)),
		"cooling_mode_id": str(cooling_profile.get("id", "")),
		"projection": projection,
		"skill_readouts": skill_readouts,
		"guaranteed_detour_enabled":bool(MATH.game(p).get("feature_families", {}).get("industrial", {}).get("ir", {}).get("guaranteed_detour_enabled", false)),
		"fast_cleanup_enabled":bool(MATH.game(p).get("feature_families", {}).get("industrial", {}).get("ir", {}).get("fast_cleanup_enabled", false)),
		"priority_cleanup_reserve": {"item_id":"ir_core", "amount":int(cleanup_reservation.get("ir_core", 0)), "token":"mastery:IR_SK07:priority_cleanup"},
		"pending_output": int(state.get("pending_output", 0)),
		"output_item": String(_site_data("ir").get("output_item", "ir_core")),
		"last_message": String(state.get("last_message", "")),
	}


static func _ir_projection(p: Dictionary, strategy_id: String) -> Dictionary:
	var data := _site_data("ir")
	var strategy := _strategy_definition(strategy_id)
	var phases: Array = data.get("phases", [])
	var profile := _profile_scale(p, "ir")
	var industrial = load("res://gameplay/IndustrialFeatures.gd")
	var route_profile: Dictionary = industrial.call("ir_campaign_profile", p, false) if industrial != null else {}
	if route_profile.is_empty():
		route_profile = {"cost_multiplier":1.0, "duration_multiplier":1.0, "cooling_rate_multiplier":1.0}
	var cost := 0
	var duration := 0.0
	for phase_value in phases:
		var phase: Dictionary = phase_value
		cost += int(round(float(phase.get("cost_cents", 0)) * float(strategy.get("cost_multiplier", 1.0)) * float(route_profile.get("cost_multiplier", 1.0))))
		var setup_bonus := MATH.bonus(p, "ir:setup_duration_reduction", "ir") if String(phase.get("id", "")) == "preparation" else 0.0
		duration += float(phase.get("duration_s", 0.0)) * float(strategy.get("duration_multiplier", 1.0)) * float(route_profile.get("duration_multiplier", 1.0)) / float(profile["speed"]) / maxf(0.1, 1.0 + setup_bonus)
	var base_yield := (int(strategy.get("yield_min", 0)) + int(strategy.get("yield_max", 0))) / 2.0
	var quality := (float(strategy.get("quality_min", 0.0)) + float(strategy.get("quality_max", 0.0))) * 0.5
	var quality_factor := 0.8 + quality * 0.4
	var thermal := _projected_ir_temperature(p, strategy, phases, profile, route_profile)
	var expected_yield := base_yield * float(strategy.get("yield_multiplier", 1.0)) * quality_factor * float(profile["output"]) * (1.0 - float(thermal["penalty"]))
	var uncertainty_reduction := clampf(MATH.bonus(p, "ir:yield_uncertainty_reduction", "ir"), 0.0, 1.0)
	var yield_scale := float(strategy.get("yield_multiplier", 1.0)) * float(profile["output"]) * (1.0 - float(thermal["penalty"]))
	var yield_minimum := float(strategy.get("yield_min", 0)) * (0.8 + float(strategy.get("quality_min", 0.0)) * 0.4) * yield_scale
	var yield_maximum := float(strategy.get("yield_max", 0)) * (0.8 + float(strategy.get("quality_max", 0.0)) * 0.4) * yield_scale
	var yield_range := [lerpf(yield_minimum, expected_yield, uncertainty_reduction), lerpf(yield_maximum, expected_yield, uncertainty_reduction)]
	var wage_cost := _projected_wages(p, "ir", duration, data)
	return {
		"cost_cents": cost + wage_cost,
		"operation_cost_cents": cost,
		"wage_cost_cents": wage_cost,
		"duration_seconds": duration,
		"cooling_mode_id": str(route_profile.get("cooling_mode_id", "")),
		"expected_yield": expected_yield,
		"yield_range": yield_range,
		"projected_peak_temperature_c": float(thermal["peak_temperature_c"]),
		"estimated_thermal_penalty": float(thermal["penalty"]),
		"yield_item": String(data.get("output_item", "ir_core")),
		"currency": "money_cents",
	}


static func _ir_strategy_projections(p: Dictionary) -> Array:
	var results: Array = []
	for strategy in strategy_definitions():
		var option: Dictionary = strategy.duplicate(true)
		option["projection"] = _ir_projection(p, String(strategy.get("id", "")))
		results.append(option)
	return results


static func _pd_lens_projections(p: Dictionary) -> Array:
	var results: Array = []
	var data := _site_data("pd")
	var scale := _profile_scale(p, "pd")
	var reference_price := int(data.get("reference_sale_price_cents_per_unit", 0))
	var lens_rows: Array = data.get("lenses", []).duplicate(true)
	var industrial := load("res://gameplay/IndustrialFeatures.gd")
	if industrial != null:
		lens_rows.append_array(industrial.call("lens_definitions", p))
	for lens_value in lens_rows:
		var lens: Dictionary = lens_value
		var quality := (float(lens.get("quality_min", 0.0)) + float(lens.get("quality_max", 0.0))) * 0.5
		var base_yield := (int(lens.get("yield_min", 0)) + int(lens.get("yield_max", 0))) * 0.5
		var output := maxf(0.0, base_yield * (0.75 + quality * 0.5) * float(scale["output"]))
		var is_bulk := String(lens.get("id", "")) == "pd_lens_bulk"
		var cycle_speed := MATH.bonus(p, "pd:bulk_processing_speed", "pd") if is_bulk else 0.0
		var sample_seconds := (float(lens.get("sample_seconds_min", 0.0)) + float(lens.get("sample_seconds_max", 0.0))) * 0.5
		var cycle_seconds := (float(lens.get("cycle_seconds_min", 0.0)) + float(lens.get("cycle_seconds_max", 0.0))) * 0.5 / maxf(0.1, 1.0 + cycle_speed)
		var duration := (sample_seconds + cycle_seconds) / float(scale["speed"])
		var sample_cost := maxi(0, int(floor(float(lens.get("sample_cost_cents", 0)) * (1.0 - clampf(MATH.bonus(p, "pd:reagent_cost_reduction", "pd"), 0.0, 1.0)) + EPSILON)))
		var operating_cost := int(lens.get("operating_cost_cents", 0))
		if is_bulk:
			operating_cost = maxi(0, int(floor(float(operating_cost) * (1.0 - clampf(MATH.bonus(p, "pd:chemical_cost_reduction", "pd"), 0.0, 1.0)) + EPSILON)))
		var operation_cost := sample_cost + operating_cost
		var variance_reduction := clampf(MATH.bonus(p, "pd:forecast_variance_reduction", "pd"), 0.0, 1.0)
		var minimum_yield := float(lens.get("yield_min", 0)) * (0.75 + float(lens.get("quality_min", 0.0)) * 0.5) * float(scale["output"])
		var maximum_yield := float(lens.get("yield_max", 0)) * (0.75 + float(lens.get("quality_max", 0.0)) * 0.5) * float(scale["output"])
		var yield_range := [lerpf(minimum_yield, output, variance_reduction), lerpf(maximum_yield, output, variance_reduction)]
		var wage_cost := _projected_wages(p, "pd", duration, data)
		var gross_reference_value := int(floor(output * reference_price))
		var net_reference_value := gross_reference_value - operation_cost - wage_cost
		results.append({
			"id": String(lens.get("id", "")),
			"name": String(lens.get("name", "")),
			"expected_quality": quality,
			"expected_yield": output,
			"yield_range": yield_range,
			"expected_duration_s": duration,
			"operation_cost_cents": operation_cost,
			"wage_cost_cents": wage_cost,
			"cost_cents": operation_cost + wage_cost,
			"reference_gross_value_cents": gross_reference_value,
			"reference_net_per_hour_cents": int(floor(float(net_reference_value) * 3600.0 / maxf(1.0, duration))),
			"reference_price_source": String(data.get("reference_price_source", "")),
		})
	return results


static func _projected_ir_temperature(p: Dictionary, strategy: Dictionary, phases: Array, profile: Dictionary, route_profile: Dictionary = {}) -> Dictionary:
	var data := _site_data("ir")
	var ambient := float(data.get("ambient_temperature_c", 20.0))
	var temperature := maxf(ambient, float(ensure(p)["ir"].get("temperature_c", ambient)))
	var peak := temperature
	var stress := 0.0
	var cooling := float(data.get("base_cooling_rate_c_per_second", 0.0)) + float(strategy.get("cooling_rate_c_per_second", 0.0))
	cooling += maxf(-float(data.get("base_cooling_rate_c_per_second", 0.0)), MATH.bonus(p, "cooling", "ir") * float(data.get("cooling_bonus_scale", 0.1)))
	cooling *= maxf(0.1, float(route_profile.get("cooling_rate_multiplier", 1.0)))
	var safe := float(data.get("safe_temperature_c", 80.0))
	if String(strategy.get("id", "")) == "reliable":
		safe = ambient + (safe - ambient) * (1.0 + maxf(0.0, MATH.bonus(p, "ir:stability_margin", "ir")))
	var speed := float(profile["speed"])
	for phase_value in phases:
		var phase: Dictionary = phase_value
		var setup_bonus := MATH.bonus(p, "ir:setup_duration_reduction", "ir") if String(phase.get("id", "")) == "preparation" else 0.0
		var duration := float(phase.get("duration_s", 0.0)) * float(strategy.get("duration_multiplier", 1.0)) * float(route_profile.get("duration_multiplier", 1.0)) / speed / maxf(0.1, 1.0 + setup_bonus)
		var next_temperature := maxf(ambient, temperature + (float(phase.get("heat_c_per_second", 0.0)) * float(strategy.get("heat_multiplier", 1.0)) - cooling) * duration)
		stress += maxf(0.0, (temperature + next_temperature) * 0.5 - safe) * duration
		temperature = next_temperature
		peak = maxf(peak, temperature)
	var max_penalty := clampf(float(data.get("max_thermal_penalty", 0.4)), 0.0, 0.8)
	var penalty := minf(max_penalty, stress / maxf(1.0, float(data.get("thermal_stress_for_max_penalty_c_seconds", 12000.0))) * max_penalty)
	return {"peak_temperature_c": peak, "penalty": penalty}


static func _profile_scale(p: Dictionary, key: String) -> Dictionary:
	var site_metrics: Dictionary = ECONOMY.metrics(p, key)
	return {
		"output": maxf(0.0, float(site_metrics.get("output_multiplier", 1.0))),
		"speed": maxf(0.1, float(site_metrics.get("speed_multiplier", 1.0))),
		"wage_cents_per_second": maxf(0.0, float(site_metrics.get("worker_wage_cents_per_minute", 0.0)) / 60.0),
	}


static func _projected_wages(p: Dictionary, key: String, seconds: float, data: Dictionary) -> int:
	var profile := _profile_scale(p, key)
	return maxi(0, int(ceil(float(profile["wage_cents_per_second"]) * maxf(0.0, seconds))))


static func _bill_wages(p: Dictionary, key: String, state: Dictionary, seconds: float, data: Dictionary) -> float:
	var scale := _profile_scale(p, key)
	var rate := float(scale["wage_cents_per_second"])
	if rate <= EPSILON:
		return seconds
	var fraction := clampf(float(state.get("wage_fraction_cents", 0.0)), 0.0, 0.999999)
	var balance := MATH.available_money(p, "payroll")
	var allowed := seconds
	if balance == 0:
		return 0.0
	if fraction + rate * allowed > float(balance) + EPSILON:
		allowed = minf(seconds, maxf(0.0, (float(balance) - fraction) / rate))
	var accrued := fraction + rate * allowed
	var due := maxi(0, int(floor(accrued + EPSILON)))
	if due > balance:
		due = balance
	if due > 0:
		if not MATH.pay(p, due, "payroll"):
			return 0.0
		state["wages_paid_cents"] = int(state.get("wages_paid_cents", 0)) + due
		MATH.stat(p, key + "_wages_paid_cents", due)
		if key == "ir":
			var campaign: Dictionary = state.get("campaign", {})
			if not campaign.is_empty():
				campaign["committed_cost_cents"] = int(campaign.get("committed_cost_cents", 0)) + due
				campaign["wage_cost_paid_cents"] = int(campaign.get("wage_cost_paid_cents", 0)) + due
				state["campaign"] = campaign
	state["wage_fraction_cents"] = clampf(accrued - due, 0.0, 0.999999)
	return allowed

static func _next_seed(p: Dictionary, state: Dictionary, site_key: String) -> int:
	var counter := int(state.get("seed_counter", 0))
	var profile_id := String(p.get("profile_id", "protocol-horizon"))
	var site_salt := 7001 if site_key == "pd" else 9001
	var seed := int((profile_id.hash() * 31 + site_salt + counter * 7919) % 2147483647)
	state["seed_counter"] = counter + 1
	return abs(seed)


static func _false_array(size: int) -> Array:
	var result: Array = []
	for _index in range(maxi(0, size)):
		result.append(false)
	return result


static func _ir_is_active(state: Dictionary) -> bool:
	return String(state.get("status", "")) in ["running", "paused", "waiting_funds", "waiting_storage"]


static func _lens_definition(p: Dictionary, lens_id: String) -> Dictionary:
	for lens_value in _site_data("pd").get("lenses", []):
		var lens: Dictionary = lens_value
		if String(lens.get("id", "")) == lens_id:
			return lens.duplicate(true)
	var industrial := load("res://gameplay/IndustrialFeatures.gd")
	if industrial != null:
		return industrial.call("lens_definition", p, lens_id)
	return {}


static func _strategy_definition(strategy_id: String) -> Dictionary:
	for strategy_value in _site_data("ir").get("strategies", []):
		var strategy: Dictionary = strategy_value
		if String(strategy.get("id", "")) == strategy_id:
			return strategy.duplicate(true)
	return {}


static func _site_key(site: String) -> String:
	if site in ["pd", SITE_IDS["pd"]]:
		return "pd"
	if site in ["ir", SITE_IDS["ir"]]:
		return "ir"
	return ""


static func _site_data(key: String) -> Dictionary:
	var config := _load_config()
	var sites: Dictionary = config.get("sites", {})
	var data: Variant = sites.get(key, {})
	return data if data is Dictionary else {}


static func _load_config() -> Dictionary:
	if not _config_cache.is_empty():
		return _config_cache
	if not FileAccess.file_exists(CONFIG_PATH):
		return {}
	var file := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		_config_cache = parsed
	return _config_cache

