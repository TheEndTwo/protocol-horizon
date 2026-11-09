class_name ResearchViews
extends RefCounted

const ECONOMY := preload("res://gameplay/EconomyModel.gd")
const SITES := preload("res://gameplay/SiteModel.gd")
const GEOLOGY_LABELS := {
	"STRUCTURE_01":"структурный профиль",
	"guaranteed_geobinding":"связанный образец",
	"registry_anomaly":"аномалия реестра",
	"railway_log":"транспортная структура",
	"old_project_record":"след старого проекта",
	"ir_spectrum":"иридиевый спектр",
	"deep_geology_signal":"глубинная геометка",
	"geology_report":"общий геологический отчёт",
}
const GEOLOGY_COLORS := {
	"STRUCTURE_01":"#8596a3",
	"guaranteed_geobinding":"#78c7b5",
	"registry_anomaly":"#edbd68",
	"railway_log":"#9ca9b4",
	"old_project_record":"#c98d66",
	"ir_spectrum":"#bf83e8",
	"deep_geology_signal":"#56a9df",
	"geology_report":"#b5c0c8",
}
const SITE_LABELS := {"fe":"Fe", "pd":"Pd", "ir":"Ir"}
const _INDUSTRIAL_CONFIG := "res://data/proposals/industrial_features.json"
const _META_CONFIG := "res://data/proposals/meta.json"

static var _json_cache: Dictionary = {}

static func describe(p: Dictionary, id: String, base: Dictionary) -> Dictionary:
	var result := base.duplicate(true)
	var profile := p.duplicate(true)
	var source: Dictionary = result.get("current_state", result)
	var extra: Dictionary = {}
	match id:
		"D06": extra = _open_horizon_view(profile, source)
		"P01": extra = _hire_recommendation(source)
		"P08": extra = _roi_readout(source)
		"P09": extra = _wage_fund_view(profile, source)
		"P11": extra = _specialist_interactions(profile, str(source.get("site", "fe")))
		"P16": extra = _machine_profession_view(profile, str(source.get("site", "fe")))
		"G01": extra = _spectral_decoding(source)
		"G05": extra = _site_density(profile)
		"G07": extra = _recent_geology_stats(source)
		"G11": extra = _opened_horizon_value(profile, source)
		"G13": extra = _expedition_history(profile, source)
		"G15": extra = deep_vein_style(profile)
		"PD03": extra = _impurity_yield_view(profile, source)
		"PD04": extra = _honest_yield_bounds(source)
		"PD13": extra = _pd_profile_comparison(source)
		"PD19": extra = _production_chain(profile, source)
		"IR01": extra = _route_forecasts(profile, source)
		"IR02": extra = _phase_expense_regions(profile, source)
		"IR04": extra = _legacy_scheme_view(profile)
		"IR21": extra = _ir_heat_windows(profile, source)
		"IR29": extra = _ir_phase_forecast(profile, source)
	if result.has("current_state"):
		var nested: Dictionary = result["current_state"].duplicate(true)
		nested.merge(extra, true)
		result["current_state"] = nested
	result.merge(extra, true)
	return result


static func deep_vein_style(p: Dictionary) -> Dictionary:
	var snapshot := p.duplicate(true)
	var game := GameMath.game(snapshot)
	var geology: Dictionary = game.get("progression", {}).get("geology", {})
	var reports: Array = geology.get("reports", [])
	var horizon := int(GameMath.site(snapshot, "fe").get("horizon", 0))
	var available: Array = []
	var goal_counts: Dictionary = {}
	for report_value in reports:
		if not report_value is Dictionary:
			continue
		for raw_tag in report_value.get("tags", []):
			var tag := str(raw_tag)
			goal_counts[tag] = int(goal_counts.get(tag, 0)) + 1
	for raw_tag in goal_counts:
		var tag := str(raw_tag)
		var count := int(goal_counts[tag])
		available.append({
			"id":tag,
			"label":str(GEOLOGY_LABELS.get(tag, tag)),
			"color":str(GEOLOGY_COLORS.get(tag, "#b5c0c8")),
			"report_count":count,
			"discovered":true,
		})
	available.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.id) < str(b.id))
	var open_horizons: Array = _open_horizon_indices(snapshot)
	var next_open := -1
	for candidate in open_horizons:
		if int(candidate) > horizon:
			next_open = int(candidate)
			break
	var goals: Array = []
	if horizon > 0:
		goals.append({"id":"opened_depth", "label":"Открытая глубина Fe", "current":horizon, "target":horizon, "complete":true})
	else:
		goals.append({"id":"opened_depth", "label":"Открыть первый глубокий горизонт", "current":0, "target":next_open if next_open >= 0 else 1, "complete":false})
	for tag in goal_counts:
		goals.append({"id":"discovery:" + str(tag), "label":str(GEOLOGY_LABELS.get(str(tag), str(tag))), "current":int(goal_counts[tag]), "target":int(goal_counts[tag]), "complete":true})
	return {
		"deep_vein_style":{
			"site":"fe", "opened_horizon":horizon,
			"deep_style_available":horizon > 0 and not available.is_empty(),
			"available_types":available,
			"goals":goals,
			"basis":"Только найденные геологические сигнатуры; оттенки служат оформлением и не описывают неизвестные породы.",
		}
	}


static func _open_horizon_view(p: Dictionary, base: Dictionary) -> Dictionary:
	var opened: Array = base.get("unlocked_horizon_indices", _open_horizon_indices(p))
	var current := int(GameMath.site(p, "fe").get("horizon", 0))
	var workers: Dictionary = GameMath.site(p, "fe").get("workers", {})
	var worker_defs := ECONOMY.definitions("fe", "worker")
	var horizons: Array = []
	for raw_index in opened:
		var index := int(raw_index)
		var scenario := p.duplicate(true)
		ECONOMY.ensure(scenario)
		var site_state := GameMath.site(scenario, "fe")
		site_state["horizon"] = index
		var metrics := ECONOMY.metrics(scenario, "fe")
		var deep_professions: Array = []
		if index > 0:
			for worker in worker_defs:
				var worker_id := str(worker.get("id", ""))
				var effect := float(worker.get("effects_per_worker", {}).get("deep_output", 0.0))
				var count := int(workers.get(worker_id, 0))
				if effect > 0.0:
					deep_professions.append({"id":worker_id, "name":str(worker.get("name", worker_id)), "count":count, "deep_output_per_worker":effect})
		var hint := "Базовый контур: глубинные эффекты не включены." if index == 0 else "Глубинный контур: действуют только реальные deep_output-эффекты этого горизонта."
		horizons.append({
			"index":index, "selected":index == current,
			"rate_per_second":float(metrics.get("rate_per_second", 0.0)),
			"worker_rate_per_second":float(metrics.get("worker_rate_per_second", 0.0)),
			"deep_professions":deep_professions,
			"specialization_hint":hint,
		})
	return {"open_horizons":horizons, "selected_horizon":current, "horizon_basis":"Открытие — по текущим реальным улучшениям; прогноз пересчитывает уже нанятый штат на копии профиля."}


static func _hire_recommendation(base: Dictionary) -> Dictionary:
	var quotes: Array = base.get("next_worker_quotes", [])
	var candidates: Array = []
	for row_value in quotes:
		if not row_value is Dictionary:
			continue
		var row: Dictionary = row_value.duplicate(true)
		if float(row.get("net_increment_cents_per_hour", 0.0)) <= 0.0:
			continue
		if typeof(row.get("payback_hours", null)) == TYPE_FLOAT:
			candidates.append(row)
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.get("payback_hours", INF)) < float(b.get("payback_hours", INF)))
	return {
		"crew_recommendation":candidates[0] if not candidates.is_empty() else {},
		"crew_ranking":candidates,
		"crew_recommendation_basis":"Среди реальных доступных цитат найма — положительный чистый прирост по цене каталога и фактической зарплате; рекомендация не покупает работника.",
	}


static func _roi_readout(base: Dictionary) -> Dictionary:
	var readout: Dictionary = {"roi_basis":"Почасовая чистая стоимость до найма берётся из существующего расчёта P01/P08; прогноз по каталожной цене, не гарантированная продажа."}
	if base.has("current_net_at_catalog_price_cents_per_hour"):
		readout["already_roi_base_cents_per_hour"] = base["current_net_at_catalog_price_cents_per_hour"]
	return readout


static func _wage_fund_view(p: Dictionary, base: Dictionary) -> Dictionary:
	var site := str(base.get("site", "fe"))
	var metrics := ECONOMY.metrics(p, site)
	var hourly_wages := maxf(0.0, float(metrics.get("worker_wage_cents_per_minute", 0.0)) * 60.0)
	var reserves: Dictionary = base.get("cash_reserves", {})
	var amount := int(reserves.get("P09", 0))
	var balance := int(p.get("money_cents", 0))
	var presets: Array = []
	for hours in [1, 4, 8]:
		presets.append({"hours":hours, "label":"%d ч оплаты" % hours, "amount_cents":int(ceil(hourly_wages * float(hours))), "applied":false})
	return {
		"wage_fund":{
			"balance_cents":balance, "hourly_wage_cents":int(ceil(hourly_wages)),
			"reserve_cents":amount, "reserve_is_applied":amount > 0,
			"payroll_hours_at_balance":float(balance) / hourly_wages if hourly_wages > 0.0 else null,
			"reserve_presets":presets,
			"note":"Пресеты рассчитаны по текущей зарплате и ничего не меняют. Резерв отображается отдельно и не является списанием.",
		}
	}


static func _specialist_interactions(p: Dictionary, site: String) -> Dictionary:
	var meta_specialists: Dictionary = GameMath.game(p).get("meta", {}).get("specialists", {})
	var assignments: Dictionary = meta_specialists.get("assignments", {}).get(site, {})
	var owned: Dictionary = meta_specialists.get("owned", {})
	var slots: Array = assignments.keys()
	slots.sort()
	var roster: Array = []
	var groups: Dictionary = {}
	var total_assigned := 0
	var config := _json_data(_META_CONFIG)
	var specialist_config: Dictionary = config.get("specialists", {})
	for slot_value in slots:
		var specialist_id := str(assignments[slot_value])
		if not owned.has(specialist_id):
			continue
		var definition := GameMath.record("specialists", specialist_id)
		if definition.is_empty():
			continue
		total_assigned += 1
		if roster.size() >= 5:
			continue
		var progress: Dictionary = owned[specialist_id]
		var level := clampi(int(progress.get("level", 1)), 1, maxi(1, int(definition.get("level_cap", 100))))
		var stars := clampi(int(progress.get("stars", 0)), 0, int(definition.get("star_cap", 5)))
		var ratio := float(level - 1) / float(maxi(1, int(definition.get("level_cap", 100)) - 1))
		var amount := float(definition.get("base", 0.0)) + (float(definition.get("max", 0.0)) - float(definition.get("base", 0.0))) * ratio
		amount *= 1.0 + float(specialist_config.get("effect_per_star", 0.0)) * stars
		var effect_key := _specialist_effect_key(definition)
		var unit := str(definition.get("unit", "percent"))
		if unit == "percent":
			amount /= 100.0
		elif effect_key == "storage":
			amount *= float(specialist_config.get("storage_capacity_per_slot", 1000))
		if effect_key == "storage" and unit == "percent":
			amount *= float(specialist_config.get("storage_base_capacity", 10000))
		var effect_group := site + ":" + effect_key
		var group: Dictionary = groups.get(effect_group, {"key":effect_group, "effect_key":effect_key, "actual_sum":0.0, "specialist_ids":[]})
		group["actual_sum"] = float(group.get("actual_sum", 0.0)) + amount
		group["specialist_ids"].append(specialist_id)
		groups[effect_group] = group
		roster.append({
			"slot":str(slot_value), "id":specialist_id, "name":str(definition.get("name", specialist_id)),
			"role":str(definition.get("role", "")), "target":str(definition.get("target", "")),
			"stat":str(definition.get("stat", "")), "effect_key":effect_key,
			"level":level, "stars":stars, "effect_value":amount, "effect_unit":unit,
		})
	var interaction_groups: Array = groups.values()
	interaction_groups.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.get("key", "")) < str(b.get("key", "")))
	return {
		"active_specialists":roster,
		"interaction_groups":interaction_groups,
		"specialists_omitted_over_five":maxi(0, total_assigned - roster.size()),
		"specialist_analysis_basis":"Только назначенные и принадлежащие профилю специалисты. Группы сводят реальные эффекты по одному существующему ключу; универсальная синергия не предполагается.",
	}


static func _machine_profession_view(p: Dictionary, site: String) -> Dictionary:
	var worker_defs := ECONOMY.definitions(site, "worker")
	var machine_defs := ECONOMY.definitions(site, "machine")
	var owned_workers: Dictionary = GameMath.site(p, site).get("workers", {})
	var professions: Array = []
	for worker in worker_defs:
		var worker_id := str(worker.get("id", ""))
		var count := int(owned_workers.get(worker_id, 0))
		if count <= 0:
			continue
		var isolated := p.duplicate(true)
		ECONOMY.ensure(isolated)
		var isolated_site := GameMath.site(isolated, site)
		isolated_site["workers"] = {worker_id:count}
		ECONOMY.ensure(isolated)
		var before: Dictionary = ECONOMY.metrics(isolated, site)
		var effects: Array = []
		var best: Dictionary = {}
		var best_ratio := -1.0
		for machine in machine_defs:
			var machine_id := str(machine.get("id", ""))
			var quote_profile := isolated.duplicate(true)
			var quote := ECONOMY.quote(quote_profile, site, "machine", machine_id, 1)
			var upgraded := isolated.duplicate(true)
			ECONOMY.ensure(upgraded)
			var upgraded_site := GameMath.site(upgraded, site)
			var levels: Dictionary = upgraded_site.get("machines", {})
			levels[machine_id] = int(levels.get(machine_id, 0)) + 1
			ECONOMY.ensure(upgraded)
			var after: Dictionary = ECONOMY.metrics(upgraded, site)
			var gain := maxf(0.0, float(after.get("worker_rate_per_second", 0.0)) - float(before.get("worker_rate_per_second", 0.0)))
			var price := int(quote.get("cost_cents", 0))
			var row := {
				"id":machine_id, "name":str(machine.get("name", machine_id)),
				"effects_per_level":machine.get("effects_per_level", {}).duplicate(true),
				"next_level":int(quote.get("level_after", int(levels.get(machine_id, 0)))),
				"cost_cents":price, "affordable":bool(quote.get("ok", false)),
				"profession_gain_per_second":gain,
			}
			effects.append(row)
			var ratio := gain / float(maxi(1, price))
			if gain > 0.0 and ratio > best_ratio:
				best_ratio = ratio
				best = row.duplicate(true)
		professions.append({
			"worker_id":worker_id, "profession":str(worker.get("name", worker_id)), "count":count,
			"current_profession_rate_per_second":float(before.get("worker_rate_per_second", 0.0)),
			"machine_effects":effects, "recommended_machine":best,
		})
	return {
		"profession_machine_analysis":professions,
		"machine_analysis_basis":"Эффект каждого следующего уровня проверен на фактическом числе выбранной профессии с остальными профессиями выключенными на копии профиля; уровни и баланс не меняются.",
	}


static func _spectral_decoding(base: Dictionary) -> Dictionary:
	var decoded: Array = []
	var counts: Dictionary = {}
	for report_value in base.get("reports", []):
		if not report_value is Dictionary:
			continue
		var report: Dictionary = report_value
		var tags: Array = report.get("tags", [])
		var labels: Array = []
		for raw_tag in tags:
			var tag := str(raw_tag)
			var label := str(GEOLOGY_LABELS.get(tag, tag))
			labels.append({"id":tag, "label":label})
			counts[tag] = int(counts.get(tag, 0)) + 1
		if labels.is_empty():
			for raw_label in report.get("identified_types", []):
				labels.append({"id":"", "label":str(raw_label)})
		decoded.append({"report_id":str(report.get("id", "")), "site":str(report.get("site", "")), "types":labels})
	var summary: Array = []
	for tag in counts:
		summary.append({"id":str(tag), "label":str(GEOLOGY_LABELS.get(str(tag), str(tag))), "count":int(counts[tag])})
	summary.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.id) < str(b.id))
	return {"spectral_decoding":decoded, "spectral_tag_counts":summary, "spectral_basis":"Расшифрованы только теги уже выданных геологических отчётов."}


static func _site_density(p: Dictionary) -> Dictionary:
	var reports: Array = GameMath.game(p).get("progression", {}).get("geology", {}).get("reports", [])
	var counts: Dictionary = {}
	var findings: Dictionary = {}
	for report_value in reports:
		if not report_value is Dictionary:
			continue
		var report: Dictionary = report_value
		var site := str(report.get("site", ""))
		counts[site] = int(counts.get(site, 0)) + 1
		findings[site] = int(findings.get(site, 0)) + Array(report.get("tags", [])).size()
	var highest := 0
	for site in SITE_LABELS:
		highest = maxi(highest, int(counts.get(site, 0)))
	var site_rows: Array = []
	for site in ["fe", "pd", "ir"]:
		var report_count := int(counts.get(site, 0))
		site_rows.append({
			"site":site, "label":str(SITE_LABELS[site]), "unlocked":GameMath.unlocked(p, site),
			"report_count":report_count, "finding_count":int(findings.get(site, 0)),
			"density_ratio":float(report_count) / float(highest) if highest > 0 else 0.0,
		})
	return {"site_finding_density":site_rows, "density_basis":"Плотность — число фактических отчётов по участкам. Координаты находок не записываются, поэтому пространственная сетка не имитируется."}


static func _recent_geology_stats(base: Dictionary) -> Dictionary:
	var reports: Array = base.get("reports", []).duplicate(true)
	if reports.size() > 20:
		reports = reports.slice(reports.size() - 20)
	var counts: Dictionary = {}
	for report_value in reports:
		if not report_value is Dictionary:
			continue
		for tag in report_value.get("tags", []):
			counts[str(tag)] = int(counts.get(str(tag), 0)) + 1
	var rows: Array = []
	for tag in counts:
		rows.append({"id":str(tag), "label":str(GEOLOGY_LABELS.get(str(tag), str(tag))), "count":int(counts[tag])})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.id) < str(b.id))
	return {"recent_scan_count":reports.size(), "recent_tag_counts":rows, "recent_scan_basis":"Статистика ограничена 20 последними реальными отчётами; пожизненные шансы не оцениваются."}


static func _opened_horizon_value(p: Dictionary, base: Dictionary) -> Dictionary:
	var rows: Array = base.get("horizons", []).duplicate(true)
	var selected := int(GameMath.site(p, "fe").get("horizon", 0))
	var selected_value: Variant = null
	for row in rows:
		if int(row.get("horizon", -1)) == selected:
			selected_value = float(row.get("net_catalog_value_cents_per_hour", 0.0))
	for row in rows:
		row["selected"] = int(row.get("horizon", -1)) == selected
		row["delta_vs_selected_cents_per_hour"] = float(row.get("net_catalog_value_cents_per_hour", 0.0)) - float(selected_value) if selected_value != null else 0.0
	return {
		"opened_horizon_forecast":rows, "selected_horizon":selected,
		"horizon_forecast_status":"estimate",
		"horizon_value_basis":"Only currently unlocked horizons; current workforce, catalog sale price and wages. This is not realized income or a guaranteed sale.",
	}


static func _expedition_history(p: Dictionary, base: Dictionary) -> Dictionary:
	var geology: Dictionary = GameMath.game(p).get("progression", {}).get("geology", {})
	var active: Dictionary = geology.get("active", {}).duplicate(true)
	var reports: Array = base.get("reports", geology.get("reports", [])).duplicate(true)
	var issued: Array = []
	for report_value in reports:
		if not report_value is Dictionary:
			continue
		var report: Dictionary = report_value
		var has_reward_record := report.has("reward_research_points") or report.has("reward_shards")
		issued.append({
			"id":str(report.get("id", "")), "expedition":str(report.get("expedition", "")),
			"sequence":int(report.get("sequence", 0)), "site":str(report.get("site", "")),
			"tags":report.get("tags", []).duplicate(true),
			"report_issued":true, "reward_amount_recorded":has_reward_record,
			"reward_research_points":report.get("reward_research_points", null),
			"reward_shards":report.get("reward_shards", null),
		})
	return {
		"active_expedition":active,
		"expedition_eta_seconds":float(active.get("remaining_seconds", 0.0)) if not active.is_empty() else null,
		"pending_reward":{"research_points":int(active.get("reward_research_points", 0)), "shards":int(active.get("reward_shards", 0))} if not active.is_empty() else {},
		"issued_report_history":issued,
		"reward_history_complete":issued.is_empty() or issued.all(func(entry: Dictionary) -> bool: return bool(entry.get("reward_amount_recorded", false))),
		"reward_history_basis":"Завершённые отчёты и ETA взяты из фактического состояния. Точная выдача награды не хранится в записи отчёта; ожидание активной экспедиции показано отдельно.",
	}


static func _impurity_yield_view(p: Dictionary, base: Dictionary) -> Dictionary:
	var site_state: Dictionary = GameMath.game(p).get("extraction", {}).get("pd", {})
	var sample: Dictionary = base.get("sample", site_state.get("sample", {})).duplicate(true)
	if sample.is_empty():
		return {"impurity_yield":{"available":false, "note":"Нет текущей керновой пробы; начислений и нового концентрата нет."}}
	var impurity_bonus := float(sample.get("impurity_analysis_bonus", 0.0)) if bool(sample.get("analysis_completed", false)) else 0.0
	var profile_multiplier := float(ECONOMY.metrics(p, "pd").get("output_multiplier", 1.0))
	var quality_factor := 0.75 + float(sample.get("quality", 0.0)) * 0.5
	var analysis_bonus := float(sample.get("analysis_bonus", 0.0))
	var skill_bonus := float(sample.get("analysis_skill_bonus", 0.0))
	var without_impurity := maxi(1, int(floor(float(sample.get("base_yield", 0)) * quality_factor * (1.0 + analysis_bonus + skill_bonus) * profile_multiplier)))
	var with_impurity := maxi(1, int(floor(float(sample.get("base_yield", 0)) * quality_factor * (1.0 + analysis_bonus + skill_bonus + impurity_bonus) * profile_multiplier)))
	return {
		"impurity_yield":{
			"available":true, "impurity_id":str(sample.get("identified_impurity", "")),
			"impurity_analysis_bonus":impurity_bonus,
			"actual_yield_units":int(sample.get("yield_units", 0)),
			"modeled_incremental_units_at_current_profile":with_impurity - without_impurity,
			"has_completed_analysis":bool(sample.get("analysis_completed", false)),
			"note":"Выход сравнивается по фактическим полям текущей пробы; прирост в единицах пересчитан с текущим множителем профиля и может отличаться, если профиль менялся после старта цикла.",
		}
	}


static func _honest_yield_bounds(base: Dictionary) -> Dictionary:
	var sample: Dictionary = base.get("sample", {})
	var lens_id := str(sample.get("lens_id", base.get("lens_id", "")))
	var lens: Dictionary = _find_id(base.get("lens_options", []), lens_id)
	var bounds: Variant = lens.get("yield_range", [])
	var exact_yield: Variant = null
	if not sample.is_empty() and int(sample.get("yield_units", 0)) > 0:
		exact_yield = int(sample.get("yield_units", 0))
	return {
		"yield_bounds":bounds.duplicate(true) if bounds is Array else [],
		"yield_bounds_source":lens_id,
		"actual_sample_yield_units":exact_yield,
		"yield_bounds_kind":"model_range_not_statistical_confidence_interval",
		"yield_bounds_note":"Диапазон берётся из расчёта реальной Pd-линзы; вероятностный уровень доверия модель не задаёт. Фактический выход текущей завершённой пробы указан отдельно.",
	}


static func _pd_profile_comparison(base: Dictionary) -> Dictionary:
	var options: Array = base.get("lens_options", [])
	var selected_id := str(base.get("lens_id", ""))
	var first: Dictionary = _find_id(options, selected_id)
	if first.is_empty() and not options.is_empty() and options[0] is Dictionary:
		first = options[0].duplicate(true)
	var second: Dictionary = {}
	var best_score := -INF
	for option_value in options:
		if not option_value is Dictionary:
			continue
		var option: Dictionary = option_value
		if str(option.get("id", "")) == str(first.get("id", "")):
			continue
		var score := float(option.get("reference_net_per_hour_cents", 0.0))
		if second.is_empty() or score > best_score:
			second = option.duplicate(true)
			best_score = score
	var profiles: Array = []
	if not first.is_empty(): profiles.append(first)
	if not second.is_empty(): profiles.append(second)
	return {
		"processing_profile_comparison":profiles,
		"processing_profile_comparison_available":profiles.size() == 2,
		"processing_profile_basis":"Сравниваются существующие определения Pd-линз и их расчёты выхода/стоимости; рецепты и новые продукты не создаются.",
	}


static func _production_chain(p: Dictionary, base: Dictionary) -> Dictionary:
	var game := GameMath.game(p)
	var progression: Dictionary = game.get("progression", {})
	var active_expedition: Dictionary = progression.get("geology", {}).get("active", {})
	var mining := ECONOMY.metrics(p, "fe")
	var pd_status := str(base.get("status", game.get("extraction", {}).get("pd", {}).get("status", "idle")))
	var network: Dictionary = game.get("network", {})
	var inventory: Dictionary = p.get("inventory", {})
	var stages: Array = [
		{"id":"exploration", "label":"Разведка", "active":not active_expedition.is_empty(), "status":str(active_expedition.get("id", "ожидание экспедиции")), "remaining_seconds":float(active_expedition.get("remaining_seconds", 0.0)) if not active_expedition.is_empty() else null},
		{"id":"mining", "label":"Добыча", "active":bool(mining.get("unlocked", false)) and float(mining.get("rate_per_second", 0.0)) > 0.0, "status":"поток %.3f ед/с" % float(mining.get("rate_per_second", 0.0)), "rate_per_second":float(mining.get("rate_per_second", 0.0))},
		{"id":"chemistry", "label":"Химия Pd", "active":pd_status in ["sampling", "analyzing", "concentrating"], "status":pd_status, "remaining_seconds":float(base.get("remaining_seconds", 0.0))},
		{"id":"sale", "label":"Продажа", "active":bool(network.get("autosell", false)) or int(inventory.get("pd_concentrate", 0)) > 0, "status":"автопродажа" if bool(network.get("autosell", false)) else "%d ед. на складе" % int(inventory.get("pd_concentrate", 0)), "autosell":bool(network.get("autosell", false))},
	]
	for stage in stages:
		stage["state"] = "работает" if bool(stage.get("active", false)) else "простой"
	return {"production_chain_stages":stages, "production_chain_basis":"Показаны реальные статусы разведки, Fe-потока, Pd-цикла и имеющегося маршрута продажи; время простоя, которого нет в сохранении, не выдумывается."}


static func _route_forecasts(p: Dictionary, base: Dictionary) -> Dictionary:
	var reports: Array = GameMath.game(p).get("progression", {}).get("geology", {}).get("reports", [])
	var latest_rock: Dictionary = {}
	for index in range(reports.size() - 1, -1, -1):
		var report: Dictionary = reports[index]
		if str(report.get("site", "")) == "ir":
			latest_rock = report
			break
	var forecasts: Array = []
	for option_value in base.get("strategy_options", []):
		if not option_value is Dictionary:
			continue
		var option: Dictionary = option_value.duplicate(true)
		option["rock_basis"] = "actual_report" if not latest_rock.is_empty() else "provisional_no_site_specific_report"
		option["rock_tags"] = latest_rock.get("tags", []).duplicate(true) if not latest_rock.is_empty() else []
		forecasts.append(option)
	return {
		"route_forecasts":forecasts,
		"route_forecast_count":forecasts.size(),
		"route_forecast_note":"Прогнозы пересчитываются по трём существующим стратегиям. Без отчёта И-9 порода явно помечена как предварительная.",
	}


static func _phase_expense_regions(p: Dictionary, base: Dictionary) -> Dictionary:
	var details := _ir_phases(p, base)
	var rows: Array = details.get("phases", [])
	var highest := 0.0
	for row in rows:
		highest = maxf(highest, float(row.get("cost_per_second", 0.0)))
	for row in rows:
		var ratio := float(row.get("cost_per_second", 0.0)) / highest if highest > 0.0 else 0.0
		row["cost_pressure"] = "высокое" if ratio >= 0.67 else "среднее" if ratio >= 0.34 else "низкое"
		row["relative_cost_pressure"] = ratio
	return {
		"phase_expense_regions":rows,
		"expense_risk_basis":"Отношение включает фактическую операционную стоимость фазы и оценку зарплаты по текущему тарифу; ранжирование не означает вероятность случайной аварии.",
	}


static func _legacy_scheme_view(p: Dictionary) -> Dictionary:
	var game := GameMath.game(p)
	var progression: Dictionary = game.get("progression", {})
	var found := bool(progression.get("geology", {}).get("discoveries", {}).get("old_project_record", false))
	var story_done: bool = bool(progression.get("story_done", {}).get("A13", false))
	if not found and not story_done:
		return {"legacy_scheme":{"available":false, "status":"не обнаружена", "snippet":[], "numeric_history_invented":false}}
	var dialogue := GameMath.record("dialogue", "A13")
	var lines: Array = []
	for entry in dialogue.get("lines", []):
		if entry is Dictionary:
			lines.append({"speaker":str(entry.get("speaker", "")), "text":str(entry.get("text", ""))})
		if lines.size() >= 3:
			break
	return {
		"legacy_scheme":{
			"available":not lines.is_empty(), "status":"canonical_story_record" if not lines.is_empty() else "discovered_no_dialogue_record",
			"discovery_source":"story:A13" if story_done else "geology:old_project_record",
			"canonical_dialogue_id":"A13", "snippet":lines,
			"numeric_history_invented":false,
			"note":"Архив показывает только канонический фрагмент сюжета; исторических чисел в найденной записи нет.",
		}
	}


static func _ir_heat_windows(p: Dictionary, base: Dictionary) -> Dictionary:
	var details := _ir_phases(p, base)
	var modes := _industrial_config().get("ir", {}).get("unstarted_phase_modes", {})
	var mode_rows: Array = []
	for raw_mode in modes:
		var mode: Dictionary = modes[raw_mode]
		mode_rows.append({"id":str(raw_mode), "label":str(mode.get("label", raw_mode)), "cost_multiplier":float(mode.get("cost_multiplier", 1.0)), "duration_multiplier":float(mode.get("duration_multiplier", 1.0))})
	mode_rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.id) < str(b.id))
	for phase in details.get("phases", []):
		var scenarios: Array = []
		var base_cost := int(phase.get("base_cost_cents", phase.get("cost_cents", 0)))
		var base_duration := float(phase.get("base_duration_seconds", phase.get("duration_seconds", 0.0)))
		var wage_rate := float(phase.get("wage_cents_per_minute", 0.0))
		for mode in mode_rows:
			var mode_cost := int(round(float(base_cost) * float(mode.cost_multiplier)))
			var mode_duration := base_duration * float(mode.duration_multiplier)
			var wage_estimate := int(ceil(wage_rate * mode_duration / 60.0))
			scenarios.append({"mode_id":str(mode.id), "label":str(mode.label), "cost_cents":mode_cost, "wage_cost_estimate_cents":wage_estimate, "total_cost_estimate_cents":mode_cost + wage_estimate, "duration_seconds":mode_duration})
		phase["mode_scenarios"] = scenarios
	return {
		"ir_heat_windows":details.get("phases", []),
		"phase_mode_options":mode_rows,
		"heat_window_basis":"Тепловые окна используют текущую стратегию и канонические фазы. Режимы меняют только стоимость/время по существующим множителям; температура — оценка без случайных аварий.",
	}


static func _ir_phase_forecast(p: Dictionary, base: Dictionary) -> Dictionary:
	var details := _ir_phases(p, base)
	var rows: Array = details.get("phases", [])
	var floor_units := int(details.get("guaranteed_output_floor_units", 0))
	for index in rows.size():
		rows[index]["guaranteed_minimum_units"] = floor_units if index == rows.size() - 1 else 0
		rows[index]["minimum_is_campaign_total"] = index == rows.size() - 1 and floor_units > 0
	return {
		"ir_phase_forecast":rows,
		"guaranteed_campaign_minimum_units":floor_units,
		"phase_forecast_source":str(details.get("source", "base_configuration")),
		"phase_forecast_basis":"Для активной кампании показаны сохранённые операционные стоимости/длительности; зарплата оценена по текущему тарифу. В простое — выбранная базовая конфигурация; гарантированный минимум относится ко всей кампании.",
	}


static func _ir_phases(p: Dictionary, base: Dictionary) -> Dictionary:
	var snapshot := p.duplicate(true)
	var state: Dictionary = SITES.view(snapshot, "ir")
	if not base.is_empty():
		state.merge(base, true)
	var campaign: Dictionary = state.get("campaign", {})
	var active := str(campaign.get("status", state.get("status", ""))) in ["running", "paused", "waiting_funds", "waiting_storage"]
	var strategy_id := str(campaign.get("strategy_id", state.get("strategy_id", "reliable")))
	var strategy := _find_id(SITES.strategy_definitions(), strategy_id)
	if strategy.is_empty():
		strategy = _find_id(SITES.strategy_definitions(), "reliable")
	var phases := SITES.phase_definitions()
	var rows: Array = []
	var costs: Array = campaign.get("phase_costs_cents", [])
	var durations: Array = campaign.get("phase_durations_s", [])
	var base_costs: Array = campaign.get("base_phase_costs_cents", [])
	var base_durations: Array = campaign.get("base_phase_durations_s", [])
	var phase_modes: Array = campaign.get("phase_mode_ids", [])
	var profile: Dictionary = ECONOMY.metrics(snapshot, "ir")
	var industrial_profile: Dictionary = _industrial_call("ir_campaign_profile", snapshot, false)
	if industrial_profile.is_empty():
		industrial_profile = {"cost_multiplier":1.0, "duration_multiplier":1.0, "cooling_rate_multiplier":1.0}
	var ir_data: Dictionary = _json_data("res://data/proposals/sites.json").get("ir", {})
	var current_temperature := float(state.get("temperature_c", ir_data.get("ambient_temperature_c", 20.0)))
	var temperature := maxf(float(ir_data.get("ambient_temperature_c", 20.0)), current_temperature)
	var current_phase := int(campaign.get("phase_index", -1))
	var elapsed := float(campaign.get("phase_elapsed_s", 0.0))
	var cooling_profile: Dictionary = _industrial_call("ir_cooling_profile", snapshot)
	var cooling := float(ir_data.get("base_cooling_rate_c_per_second", 0.0)) + float(strategy.get("cooling_rate_c_per_second", 0.0))
	cooling += maxf(-float(ir_data.get("base_cooling_rate_c_per_second", 0.0)), GameMath.bonus(snapshot, "cooling", "ir") * float(ir_data.get("cooling_bonus_scale", 0.1)))
	cooling *= maxf(0.1, float(cooling_profile.get("cooling_rate_multiplier", campaign.get("cooling_rate_multiplier", industrial_profile.get("cooling_rate_multiplier", 1.0)))))
	var speed := maxf(0.1, float(profile.get("speed_multiplier", 1.0)))
	var wage_rate := maxf(0.0, float(profile.get("worker_wage_cents_per_minute", 0.0)))
	for index in phases.size():
		var phase: Dictionary = phases[index]
		var base_cost := int(round(float(phase.get("cost_cents", 0)) * float(strategy.get("cost_multiplier", 1.0)) * float(industrial_profile.get("cost_multiplier", 1.0))))
		var setup_bonus := GameMath.bonus(snapshot, "ir:setup_duration_reduction", "ir") if str(phase.get("id", "")) == "preparation" else 0.0
		var base_duration := float(phase.get("duration_s", 0.0)) * float(strategy.get("duration_multiplier", 1.0)) * float(industrial_profile.get("duration_multiplier", 1.0)) / speed / maxf(0.1, 1.0 + setup_bonus)
		if str(phase.get("id", "")) == "refining":
			base_duration *= maxf(0.1, float(industrial_profile.get("cleanup_duration_multiplier", 1.0)))
		var cost := base_cost
		var duration := base_duration
		var mode_id := "standard"
		if active:
			if index < costs.size(): cost = int(costs[index])
			if index < durations.size(): duration = float(durations[index])
			if index < phase_modes.size(): mode_id = str(phase_modes[index])
		elif index < phase_modes.size():
			mode_id = str(phase_modes[index])
		var remaining := maxf(0.0, duration - elapsed) if active and index == current_phase else duration
		var wage_estimate := int(ceil(wage_rate * duration / 60.0))
		var heat_rate := float(phase.get("heat_c_per_second", 0.0)) * float(strategy.get("heat_multiplier", 1.0))
		var projected_delta := (heat_rate - cooling) * remaining
		var end_temperature := maxf(float(ir_data.get("ambient_temperature_c", 20.0)), temperature + projected_delta)
		var status := "завершена" if active and index < current_phase else "текущая" if active and index == current_phase else "следующая" if active else "прогноз"
		rows.append({
			"id":str(phase.get("id", "")), "name":str(phase.get("name", phase.get("id", ""))), "index":index,
			"status":status, "phase_mode_id":mode_id,
			"cost_cents":cost, "duration_seconds":duration, "remaining_seconds":remaining,
			"wage_cost_estimate_cents":wage_estimate, "total_cost_estimate_cents":cost + wage_estimate,
			"wage_cents_per_minute":wage_rate,
			"cost_per_second":float(cost + wage_estimate) / maxf(1.0, duration),
			"base_cost_cents":base_cost if not active else int(base_costs[index]) if index < base_costs.size() else cost,
			"base_duration_seconds":base_duration if not active else float(base_durations[index]) if index < base_durations.size() else duration,
			"base_cost_for_mode_cents":base_cost, "base_duration_for_mode_seconds":base_duration,
			"heat_rate_c_per_second":heat_rate, "cooling_rate_c_per_second":cooling,
			"net_heat_rate_c_per_second":heat_rate - cooling,
			"temperature_start_c":temperature, "estimated_temperature_end_c":end_temperature,
			"thermal_window":"нагрев" if heat_rate > cooling else "охлаждение/стабилизация",
		})
		if not active or index >= current_phase:
			temperature = end_temperature
			elapsed = 0.0
	var guaranteed := int(campaign.get("guaranteed_output_floor_units", industrial_profile.get("guaranteed_output_floor_units", 0)))
	return {"phases":rows, "active":active, "source":"active_campaign_arrays" if active else "base_configuration", "guaranteed_output_floor_units":guaranteed, "strategy_id":strategy_id}


static func _open_horizon_indices(p: Dictionary) -> Array:
	var metrics := ECONOMY.metrics(p, "fe")
	var maximum := clampi(floori(float(metrics.get("average_upgrade_level", 0.0)) / 100.0), 0, 10)
	return range(maximum + 1)


static func _specialist_effect_key(row: Dictionary) -> String:
	var stat := str(row.get("stat", ""))
	var target := str(row.get("target", ""))
	if stat == "tap_bonus": return "weak" if target.contains("weak_point") else "tap"
	if stat in ["operating_cost_saving", "salary_saving", "material_input_saving"]: return "wage"
	if stat in ["storage_capacity", "storage_reserved_slots", "queue_capacity"]: return "storage"
	if stat in ["survey_speed", "campaign_speed", "resonance_duration"]: return "speed"
	if stat in ["survey_precision", "geology_normal_samples"] or target.contains("weak_point") or target.contains("deep_scan") or target.contains("quality"): return "weak"
	return "output"


static func _find_id(rows: Array, id: String) -> Dictionary:
	for row in rows:
		if row is Dictionary and str(row.get("id", "")) == id:
			return row.duplicate(true)
	return {}


static func _json_data(path: String) -> Dictionary:
	if _json_cache.has(path):
		return _json_cache[path]
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		_json_cache[path] = parsed
		return parsed
	return {}


static func _industrial_config() -> Dictionary:
	return _json_data(_INDUSTRIAL_CONFIG)


static func _industrial_call(method: String, p: Dictionary, extra: Variant = null) -> Dictionary:
	var model: Variant = load("res://gameplay/IndustrialFeatures.gd")
	if model == null:
		return {}
	var result: Variant = model.call(method, p) if extra == null else model.call(method, p, extra)
	return result if result is Dictionary else {}
