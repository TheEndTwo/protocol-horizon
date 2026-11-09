class_name ResearchViewPanels
extends RefCounted

const TITLES := {
	"D06":"Открытые горизонты и специализация",
	"P01":"Рекомендация по следующему найму",
	"P08":"Доходность найма",
	"P09":"Фонд зарплат",
	"P11":"Взаимодействия назначенных специалистов",
	"P16":"Профессии и влияние машин",
	"G01":"Расшифровка геологических сигнатур",
	"G05":"Плотность находок по участкам",
	"G07":"Последние геологические отчёты",
	"G11":"Ценность открытых горизонтов",
	"G13":"Экспедиции и выданные отчёты",
	"G15":"Стили глубоких жил",
	"PD03":"Вклад примесей в выход Pd",
	"PD04":"Диапазон выхода пробы",
	"PD13":"Сравнение существующих Pd-профилей",
	"PD19":"Цепочка Pd-производства",
	"IR01":"Прогнозы маршрутов Ir",
	"IR02":"Затраты по фазам Ir",
	"IR04":"Архивное сравнение старой схемы",
	"IR21":"Тепловые окна и режимы фаз",
	"IR29":"План фаз и гарантированный минимум",
}

static func render(screen: Control, parent: Node, id: String, data: Dictionary) -> void:
	if not is_instance_valid(screen) or not is_instance_valid(parent) or not TITLES.has(id):
		return
	var readout: Dictionary = data.get("current_state", data)
	var frame := PanelContainer.new()
	frame.name = id + "ResearchReadout"
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(frame)
	var body := HorizonUI.column(frame, 5)
	HorizonUI.label(body, str(TITLES[id]), 16, HorizonUI.GOLD)
	match id:
		"D06": _render_horizons(body, readout)
		"P01": _render_hire(body, readout)
		"P08": _render_roi(body, readout)
		"P09": _render_wage_fund(body, readout)
		"P11": _render_specialists(body, readout)
		"P16": _render_professions(body, readout)
		"G01": _render_decoding(body, readout)
		"G05": _render_density(body, readout)
		"G07": _render_recent_scans(body, readout)
		"G11": _render_horizon_value(body, readout)
		"G13": _render_expeditions(body, readout)
		"G15": _render_deep_styles(body, readout)
		"PD03": _render_impurities(body, readout)
		"PD04": _render_yield_bounds(body, readout)
		"PD13": _render_pd_comparison(body, readout)
		"PD19": _render_chain(body, readout)
		"IR01": _render_routes(body, readout)
		"IR02": _render_expense(body, readout)
		"IR04": _render_legacy(body, readout)
		"IR21": _render_heat(body, readout)
		"IR29": _render_ir_phases(body, readout)


static func _render_horizons(parent: Node, data: Dictionary) -> void:
	for row in data.get("open_horizons", []):
		var marker := "●" if bool(row.get("selected", false)) else "○"
		_line(parent, "%s Горизонт %d · %.3f ед/с · рабочие %.3f ед/с" % [marker, int(row.get("index", 0)), float(row.get("rate_per_second", 0.0)), float(row.get("worker_rate_per_second", 0.0))])
		_line(parent, "   " + str(row.get("specialization_hint", "")), true)
		for profession in row.get("deep_professions", []):
			_line(parent, "   %s · штат %d · deep +%s/чел" % [str(profession.get("name", "")), int(profession.get("count", 0)), _number(float(profession.get("deep_output_per_worker", 0.0)))], true)
	if data.get("open_horizons", []).is_empty(): _line(parent, "Открытых горизонтов нет.", true)


static func _render_hire(parent: Node, data: Dictionary) -> void:
	var row: Dictionary = data.get("crew_recommendation", {})
	if row.is_empty():
		_line(parent, "Положительной цитаты найма с рассчитанной окупаемостью нет.", true)
	else:
		_line(parent, "Лучший следующий найм: %s" % str(row.get("name", row.get("worker_id", ""))))
		_line(parent, "Цена %s · чистый прирост/ч %s · окупаемость %s ч · хватает средств: %s" % [_money(row.get("cost_cents", 0)), _money(row.get("net_increment_cents_per_hour", 0)), _number(float(row.get("payback_hours", 0.0))), "да" if bool(row.get("quote_available", false)) else "нет"], true)
	_line(parent, str(data.get("crew_recommendation_basis", "")), true)


static func _render_roi(parent: Node, data: Dictionary) -> void:
	if data.has("already_roi_base_cents_per_hour"):
		_line(parent, "Текущий net до найма: %s/ч" % _money(data.already_roi_base_cents_per_hour))
	_line(parent, str(data.get("roi_basis", "")), true)


static func _render_wage_fund(parent: Node, data: Dictionary) -> void:
	var fund: Dictionary = data.get("wage_fund", {})
	_line(parent, "Баланс %s · фонд P09 %s · текущие зарплаты %s/ч" % [_money(fund.get("balance_cents", 0)), _money(fund.get("reserve_cents", 0)), _money(fund.get("hourly_wage_cents", 0))])
	for preset in fund.get("reserve_presets", []):
		_line(parent, "%s: %s" % [str(preset.get("label", "")), _money(preset.get("amount_cents", 0))], true)
	_line(parent, str(fund.get("note", "")), true)


static func _render_specialists(parent: Node, data: Dictionary) -> void:
	for specialist in data.get("active_specialists", []):
		_line(parent, "%s · %s · ур. %d ★%d · %s +%s" % [str(specialist.get("name", "")), str(specialist.get("role", "")), int(specialist.get("level", 1)), int(specialist.get("stars", 0)), str(specialist.get("effect_key", "")), _number(float(specialist.get("effect_value", 0.0)))])
	for group in data.get("interaction_groups", []):
		_line(parent, "Общий ключ %s: сумма уже назначенных эффектов %s" % [str(group.get("key", "")), _number(float(group.get("actual_sum", 0.0)))], true)
	if data.get("active_specialists", []).is_empty(): _line(parent, "На этом участке нет назначенных специалистов.", true)
	_line(parent, str(data.get("specialist_analysis_basis", "")), true)


static func _render_professions(parent: Node, data: Dictionary) -> void:
	for profession in data.get("profession_machine_analysis", []):
		_line(parent, "%s ×%d · сейчас %.4f ед/с" % [str(profession.get("profession", "")), int(profession.get("count", 0)), float(profession.get("current_profession_rate_per_second", 0.0))])
		var recommendation: Dictionary = profession.get("recommended_machine", {})
		if not recommendation.is_empty():
			_line(parent, "   Рекомендация: %s · цена %s · +%.4f ед/с этой профессии%s" % [str(recommendation.get("name", "")), _money(recommendation.get("cost_cents", 0)), float(recommendation.get("profession_gain_per_second", 0.0)), " · доступно" if bool(recommendation.get("affordable", false)) else " · накопить средства"], true)
		for machine in profession.get("machine_effects", []):
			_line(parent, "   %s %s · +%.4f ед/с" % [str(machine.get("name", "")), _effects(machine.get("effects_per_level", {})), float(machine.get("profession_gain_per_second", 0.0))], true)
	if data.get("profession_machine_analysis", []).is_empty(): _line(parent, "Сначала нанимается профессия; неиспользуемые машины не получают мнимую отдачу.", true)
	_line(parent, str(data.get("machine_analysis_basis", "")), true)


static func _render_decoding(parent: Node, data: Dictionary) -> void:
	for report in data.get("spectral_decoding", []):
		var labels: PackedStringArray = []
		for item in report.get("types", []): labels.append(str(item.get("label", "")))
		_line(parent, "%s · %s · %s" % [str(report.get("report_id", "")), str(report.get("site", "")), ", ".join(labels)])
	if data.get("spectral_decoding", []).is_empty(): _line(parent, "Выданных отчётов пока нет.", true)
	_line(parent, str(data.get("spectral_basis", "")), true)


static func _render_density(parent: Node, data: Dictionary) -> void:
	for row in data.get("site_finding_density", []):
		var blocks := int(round(float(row.get("density_ratio", 0.0)) * 12.0))
		_line(parent, "%s  %s %s  · %d отчётов / %d сигнатур%s" % [str(row.get("label", "")), "█".repeat(blocks), "░".repeat(12 - blocks), int(row.get("report_count", 0)), int(row.get("finding_count", 0)), " · закрыт" if not bool(row.get("unlocked", false)) else ""])
	_line(parent, str(data.get("density_basis", "")), true)


static func _render_recent_scans(parent: Node, data: Dictionary) -> void:
	_line(parent, "Последние отчёты: %d / 20" % int(data.get("recent_scan_count", 0)))
	for row in data.get("recent_tag_counts", []):
		_line(parent, "%s × %d" % [str(row.get("label", "")), int(row.get("count", 0))], true)
	_line(parent, str(data.get("recent_scan_basis", "")), true)


static func _render_horizon_value(parent: Node, data: Dictionary) -> void:
	for row in data.get("opened_horizon_forecast", []):
		_line(parent, "%s Горизонт %d · net %s/ч · к выбранному %s/ч" % ["●" if bool(row.get("selected", false)) else "○", int(row.get("horizon", 0)), _money(row.get("net_catalog_value_cents_per_hour", 0)), _money(row.get("delta_vs_selected_cents_per_hour", 0))])
	_line(parent, str(data.get("horizon_value_basis", "")), true)


static func _render_expeditions(parent: Node, data: Dictionary) -> void:
	var active: Dictionary = data.get("active_expedition", {})
	if active.is_empty():
		_line(parent, "Активной экспедиции нет.")
	else:
		var reward: Dictionary = data.get("pending_reward", {})
		_line(parent, "%s · ETA %.0f с · ожидает %d ОИ / %d осколков" % [str(active.get("id", "")), float(data.get("expedition_eta_seconds", 0.0)), int(reward.get("research_points", 0)), int(reward.get("shards", 0))])
	_line(parent, "Фактически выданные отчёты: %d" % data.get("issued_report_history", []).size())
	for report in data.get("issued_report_history", []):
		_line(parent, "%s · %s #%d · награда записана: %s" % [str(report.get("id", "")), str(report.get("expedition", "")), int(report.get("sequence", 0)), "да" if bool(report.get("reward_amount_recorded", false)) else "нет"], true)
	_line(parent, str(data.get("reward_history_basis", "")), true)


static func _render_deep_styles(parent: Node, data: Dictionary) -> void:
	var style: Dictionary = data.get("deep_vein_style", {})
	_line(parent, "Fe · горизонт %d" % int(style.get("opened_horizon", 0)))
	for vein in style.get("available_types", []):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		parent.add_child(row)
		var swatch := ColorRect.new()
		swatch.color = Color(str(vein.get("color", "#b5c0c8")))
		swatch.custom_minimum_size = Vector2(12, 12)
		row.add_child(swatch)
		HorizonUI.label(row, "%s · отчётов %d" % [str(vein.get("label", "")), int(vein.get("report_count", 0))], 13)
	if style.get("available_types", []).is_empty(): _line(parent, "Подтверждённых типов для цветовой маркировки нет.", true)
	for goal in style.get("goals", []):
		_line(parent, "%s · %s/%s · %s" % [str(goal.get("label", "")), str(goal.get("current", 0)), str(goal.get("target", 0)), "готово" if bool(goal.get("complete", false)) else "цель"], true)
	_line(parent, str(style.get("basis", "")), true)


static func _render_impurities(parent: Node, data: Dictionary) -> void:
	var view: Dictionary = data.get("impurity_yield", {})
	if not bool(view.get("available", false)):
		_line(parent, str(view.get("note", "Текущих данных пробы нет.")), true)
		return
	_line(parent, "Примесь: %s · бонус анализа +%s · текущий фактический выход %d ед." % [str(view.get("impurity_id", "не определена")), _number(float(view.get("impurity_analysis_bonus", 0.0))), int(view.get("actual_yield_units", 0))])
	_line(parent, "Модельный вклад при текущем профиле: +%d ед." % int(view.get("modeled_incremental_units_at_current_profile", 0)), true)
	_line(parent, str(view.get("note", "")), true)


static func _render_yield_bounds(parent: Node, data: Dictionary) -> void:
	var bounds: Array = data.get("yield_bounds", [])
	if bounds.size() >= 2:
		_line(parent, "%s · диапазон модели %.2f–%.2f ед." % [str(data.get("yield_bounds_source", "")), float(bounds[0]), float(bounds[1])])
	else:
		_line(parent, "Для выбранной линзы диапазон сейчас недоступен.", true)
	if data.get("actual_sample_yield_units", null) != null:
		_line(parent, "Фактический выход текущей пробы: %d ед." % int(data.actual_sample_yield_units))
	_line(parent, str(data.get("yield_bounds_note", "")), true)


static func _render_pd_comparison(parent: Node, data: Dictionary) -> void:
	for profile in data.get("processing_profile_comparison", []):
		var bounds: Array = profile.get("yield_range", [])
		var range_text := "%.2f–%.2f" % [float(bounds[0]), float(bounds[1])] if bounds.size() >= 2 else "нет диапазона"
		_line(parent, "%s · %s ед. · %s с · стоимость %s · net %s/ч" % [str(profile.get("name", profile.get("id", ""))), range_text, _number(float(profile.get("expected_duration_s", 0.0))), _money(profile.get("cost_cents", 0)), _money(profile.get("reference_net_per_hour_cents", 0))])
	if not bool(data.get("processing_profile_comparison_available", false)):
		_line(parent, "Для сравнения нужны две доступные каталожные Pd-линзы.", true)
	_line(parent, str(data.get("processing_profile_basis", "")), true)


static func _render_chain(parent: Node, data: Dictionary) -> void:
	var stages: Array = data.get("production_chain_stages", [])
	var diagram: PackedStringArray = []
	for stage in stages:
		diagram.append("%s %s" % ["●" if bool(stage.get("active", false)) else "○", str(stage.get("label", ""))])
	_line(parent, "   →   ".join(diagram))
	for stage in stages:
		_line(parent, "%s · %s · %s" % [str(stage.get("label", "")), str(stage.get("state", "")), str(stage.get("status", ""))], true)
	_line(parent, str(data.get("production_chain_basis", "")), true)


static func _render_routes(parent: Node, data: Dictionary) -> void:
	for route in data.get("route_forecasts", []):
		var projection: Dictionary = route.get("projection", {})
		var bounds: Array = projection.get("yield_range", [])
		var yield_text := "%.2f–%.2f" % [float(bounds[0]), float(bounds[1])] if bounds.size() >= 2 else _number(float(projection.get("expected_yield", 0.0)))
		var tags: PackedStringArray = []
		for tag in route.get("rock_tags", []): tags.append(str(tag))
		_line(parent, "%s · %s ед. · %s с · стоимость %s · пик %.1f°C" % [str(route.get("name", route.get("id", ""))), yield_text, _number(float(projection.get("duration_seconds", 0.0))), _money(projection.get("cost_cents", 0)), float(projection.get("projected_peak_temperature_c", 0.0))])
		_line(parent, "   Данные породы: %s%s" % [str(route.get("rock_basis", "")), " · " + ", ".join(tags) if not tags.is_empty() else ""], true)
	_line(parent, str(data.get("route_forecast_note", "")), true)


static func _render_expense(parent: Node, data: Dictionary) -> void:
	for phase in data.get("phase_expense_regions", []):
		_line(parent, "%s · давление: %s · операции %s · зарплата ≈ %s · всего ≈ %s · %s/с" % [str(phase.get("name", "")), str(phase.get("cost_pressure", "")), _money(phase.get("cost_cents", 0)), _money(phase.get("wage_cost_estimate_cents", 0)), _money(phase.get("total_cost_estimate_cents", 0)), _money(phase.get("cost_per_second", 0.0))])
	_line(parent, str(data.get("expense_risk_basis", "")), true)


static func _render_legacy(parent: Node, data: Dictionary) -> void:
	var legacy: Dictionary = data.get("legacy_scheme", {})
	if not bool(legacy.get("available", false)):
		_line(parent, "Запись старого проекта не обнаружена; архив закрыт.", true)
		return
	for entry in legacy.get("snippet", []):
		_line(parent, "%s: %s" % [str(entry.get("speaker", "")), str(entry.get("text", ""))], true)
	_line(parent, str(legacy.get("note", "")), true)


static func _render_heat(parent: Node, data: Dictionary) -> void:
	for phase in data.get("ir_heat_windows", []):
		if str(phase.get("status", "")) == "завершена":
			_line(parent, "%02d · %s · завершена · тепловая история не сохраняется" % [int(phase.get("index", 0)) + 1, str(phase.get("name", ""))], true)
			continue
		_line(parent, "%02d · %s · %s · %.1f → %.1f°C · net %.3f°C/с" % [int(phase.get("index", 0)) + 1, str(phase.get("name", "")), str(phase.get("thermal_window", "")), float(phase.get("temperature_start_c", 0.0)), float(phase.get("estimated_temperature_end_c", 0.0)), float(phase.get("net_heat_rate_c_per_second", 0.0))])
		var scenarios: PackedStringArray = []
		for scenario in phase.get("mode_scenarios", []): scenarios.append("%s %s (с з/п %s)/%sс" % [str(scenario.get("label", "")), _money(scenario.get("cost_cents", 0)), _money(scenario.get("total_cost_estimate_cents", 0)), _number(float(scenario.get("duration_seconds", 0.0)))])
		if not scenarios.is_empty(): _line(parent, "   " + " · ".join(scenarios), true)
	_line(parent, str(data.get("heat_window_basis", "")), true)


static func _render_ir_phases(parent: Node, data: Dictionary) -> void:
	_line(parent, "Источник: %s · минимум всей кампании %d ед." % [str(data.get("phase_forecast_source", "")), int(data.get("guaranteed_campaign_minimum_units", 0))])
	for phase in data.get("ir_phase_forecast", []):
		_line(parent, "%02d · %s · %s · операции %s + з/п ≈ %s · %s · минимум %d" % [int(phase.get("index", 0)) + 1, str(phase.get("name", "")), str(phase.get("status", "")), _money(phase.get("cost_cents", 0)), _money(phase.get("wage_cost_estimate_cents", 0)), _seconds(float(phase.get("duration_seconds", 0.0))), int(phase.get("guaranteed_minimum_units", 0))])
	_line(parent, str(data.get("phase_forecast_basis", "")), true)


static func _effects(effects: Dictionary) -> String:
	var parts: PackedStringArray = []
	for key in effects:
		parts.append("%s %s" % [str(key), _number(float(effects[key]))])
	return ", ".join(parts)


static func _line(parent: Node, value: String, muted := false) -> void:
	HorizonUI.label(parent, value, 13 if muted else 14, HorizonUI.MUTED if muted else Color("e4e9ec"))


static func _money(value: Variant) -> String:
	return "%d ¢" % int(round(float(value)))


static func _number(value: float) -> String:
	return str(snappedf(value, 0.001))


static func _seconds(value: float) -> String:
	return "%s с" % _number(value)
