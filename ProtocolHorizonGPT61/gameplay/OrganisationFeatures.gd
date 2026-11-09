class_name EarthOrganisationFeatures
extends RefCounted

const CONFIG_PATH := "res://data/proposals/organisation_features.json"
const PROGRESSION_CONFIG_PATH := "res://data/proposals/progression.json"
const FEATURE_RUNTIME_PATH := "res://gameplay/FeatureRuntime.gd"
const PROGRESSION_MODEL := preload("res://gameplay/ProgressionModel.gd")
const META_MODEL := preload("res://gameplay/MetaModel.gd")
const NO_EVENT := 1.0e30
const ORGANISATION_IDS := ["A11", "A16", "A20", "P12", "P15", "P17", "P19", "P20", "G08", "G10", "G12", "G16"]
const IMPLEMENTED_ACTIONS := [
	"org_save_shift_preset", "org_apply_shift_preset", "org_set_factory_cosmetic",
	"org_save_automation_template", "org_apply_automation_template", "org_start_shift_task",
	"org_save_roster_preset", "org_apply_roster_preset", "org_reassign_specialist",
	"org_start_training_task", "org_start_group_task", "org_preview_geology_event",
	"org_study_artifact", "org_start_parallel_expedition", "org_choose_geology_event"
]
const DEFAULT_STATE := {
	"shift_presets": {}, "roster_presets": {}, "factory_cosmetic": {"owned":{"standard":true}, "active":"standard"},
	"automation_template": {}, "shift_task_sequence": 0, "active_shift_task": {}, "completed_shift_tasks": {},
	"shift_effects": [], "training_task": {}, "training_awards": {}, "group_task": {}, "group_task_claimed": false,
	"geology_previews": {}, "geology_preview_attempts": {}, "studied_artifacts": {}, "artifact_scan_bonus": 0.0,
	"geology_choices": {}, "map_focus": "", "secondary_expedition": {}
}

static var _config_cache: Dictionary = {}
static var _progression_config_cache: Dictionary = {}

static func ensure(p: Dictionary) -> void:
	var g := GameMath.game(p)
	if not g.has("feature_families") or not g["feature_families"] is Dictionary:
		g["feature_families"] = {}
	var families: Dictionary = g["feature_families"]
	if not families.has("organisation") or not families["organisation"] is Dictionary:
		families["organisation"] = {}
	var state: Dictionary = families["organisation"]
	for key in DEFAULT_STATE:
		if not state.has(key) or typeof(state[key]) != typeof(DEFAULT_STATE[key]):
			state[key] = DEFAULT_STATE[key].duplicate(true) if DEFAULT_STATE[key] is Dictionary or DEFAULT_STATE[key] is Array else DEFAULT_STATE[key]
	if not state["factory_cosmetic"].get("owned", {}) is Dictionary:
		state["factory_cosmetic"] = DEFAULT_STATE["factory_cosmetic"].duplicate(true)
	else:
		state["factory_cosmetic"].get("owned", {}).set("standard", true)
	_ensure_fields(state["factory_cosmetic"], {"owned":{"standard":true}, "active":"standard"})

static func refresh(p: Dictionary) -> void:
	ensure(p)
	var state := _state(p)
	if _level(p, "A16") > 0:
		var owned_cosmetics: Dictionary = state["factory_cosmetic"]["owned"]
		var levels := _equipment_levels(p)
		for cosmetic in _config().get("coefficients", {}).get("factory_cosmetic_equipment_levels", {}):
			if levels >= int(_config()["coefficients"]["factory_cosmetic_equipment_levels"][cosmetic]):
				owned_cosmetics[str(cosmetic)] = true
	var bonuses: Dictionary = {"geology:scan_progress":clampf(float(state.get("artifact_scan_bonus", 0.0)), 0.0, _number("artifact_scan_bonus_cap"))}
	for effect in state.get("shift_effects", []):
		if not effect is Dictionary:
			continue
		var choice := str(effect.get("choice", ""))
		if choice == "speed":
			bonuses["speed"] = float(bonuses.get("speed", 0.0)) + float(effect.get("amount", 0.0))
		elif choice == "logistics":
			bonuses["shipping:factory_margin"] = float(bonuses.get("shipping:factory_margin", 0.0)) + float(effect.get("amount", 0.0))
	GameMath.game(p)["bonuses"]["organisation"] = bonuses

static func advance(p: Dictionary, seconds: float) -> void:
	ensure(p)
	if not is_finite(seconds) or seconds < 0.0:
		return
	var state := _state(p)
	if seconds > 0.0:
		var effects: Array = []
		for effect in state["shift_effects"]:
			if not effect is Dictionary:
				continue
			effect["remaining_seconds"] = maxf(0.0, float(effect.get("remaining_seconds", 0.0)) - seconds)
			if float(effect["remaining_seconds"]) > 0.0:
				effects.append(effect)
		state["shift_effects"] = effects
	_sync_work_progress(p)
	refresh(p)

static func next_event_in(p: Dictionary) -> float:
	ensure(p)
	var next_event := NO_EVENT
	for effect in _state(p).get("shift_effects", []):
		if effect is Dictionary:
			next_event = minf(next_event, maxf(0.0, float(effect.get("remaining_seconds", 0.0))))
	var state := _state(p)
	var secondary: Dictionary = state.get("secondary_expedition", {})
	if not secondary.is_empty() and _level(p, "G12") > 0:
		var primary: Dictionary = GameMath.game(p).get("progression", {}).get("geology", {}).get("active", {})
		if primary.is_empty():
			next_event = minf(next_event, maxf(0.0, float(secondary.get("remaining_seconds", 0.0))))
		else:
			next_event = minf(next_event, minf(maxf(0.0, float(primary.get("remaining_seconds", 0.0))), maxf(0.0, float(secondary.get("remaining_seconds", 0.0)))) * 2.0)
	return next_event

static func act(p: Dictionary, action: String, args: Dictionary = {}) -> Dictionary:
	ensure(p)
	refresh(p)
	var id := str(args.get("id", ""))
	var spec: Dictionary = _config().get("supported", {}).get(id, {})
	if spec.is_empty() or _level(p, id) <= 0:
		return GameMath.fail("Сначала изучите соответствующее исследование.")
	if not Array(spec.get("actions", [])).has(action):
		return GameMath.fail("У этого исследования нет такого действия.")
	match action:
		"org_save_shift_preset": return _save_shift_preset(p, args)
		"org_apply_shift_preset": return _apply_shift_preset(p, args)
		"org_set_factory_cosmetic": return _set_factory_cosmetic(p, args)
		"org_save_automation_template": return _save_automation_template(p)
		"org_apply_automation_template": return _apply_automation_template(p, args)
		"org_start_shift_task": return _start_shift_task(p, args)
		"org_save_roster_preset": return _save_roster_preset(p, args)
		"org_apply_roster_preset": return _apply_roster_preset(p, args)
		"org_reassign_specialist": return _reassign_specialist(p, args)
		"org_start_training_task": return _start_training_task(p, args)
		"org_start_group_task": return _start_group_task(p, args)
		"org_preview_geology_event": return _preview_geology_event(p, args)
		"org_study_artifact": return _study_artifact(p, args)
		"org_start_parallel_expedition": return _start_parallel_expedition(p, args)
		"org_choose_geology_event": return _choose_geology_event(p, args)
	return GameMath.fail("Действие организации не реализовано.")

static func operations(p: Dictionary, id: String) -> Array:
	ensure(p)
	refresh(p)
	if not ORGANISATION_IDS.has(id) or _level(p, id) <= 0:
		return []
	match id:
		"A11":
			if _level(p, "A10") <= 0:
				return []
			return [_operation("org_save_shift_preset", "Сохранить настройки смены", [{"key":"slot", "label":"Слот пресета", "type":"number", "min":0, "max":_coefficient("shift_preset_slots") - 1}]), _operation("org_apply_shift_preset", "Применить настройки смены", [{"key":"slot", "label":"Слот пресета", "type":"number", "min":0, "max":_coefficient("shift_preset_slots") - 1}])]
		"A16":
			var cosmetic_choices: Array = []
			for cosmetic in _state(p)["factory_cosmetic"]["owned"]:
				cosmetic_choices.append({"label":str(cosmetic).capitalize(), "value":str(cosmetic)})
			if cosmetic_choices.is_empty():
				return []
			return [_operation("org_set_factory_cosmetic", "Выбрать открытую отделку фабрики", [{"key":"cosmetic", "label":"Отделка", "type":"select", "choices":cosmetic_choices}])]
		"A20":
			return [_operation("org_save_automation_template", "Сохранить шаблон автоматизации", []), _operation("org_apply_automation_template", "Применить шаблон к открытому участку", [{"key":"site", "label":"Участок", "type":"select", "choices":_open_site_choices(p)}])]
		"P12":
			return [_operation("org_start_shift_task", "Начать производственную задачу смены", [{"key":"choice", "label":"Временный эффект", "type":"select", "choices":[{"label":"Скорость производства", "value":"speed"}, {"label":"Заводская логистика", "value":"logistics"}]}, {"key":"site", "label":"Участок работы", "type":"select", "choices":_open_site_choices(p)}])]
		"P15":
			return [_operation("org_save_roster_preset", "Сохранить состав смены", [{"key":"slot", "label":"Пресет 0 или 1", "type":"number", "min":0, "max":_coefficient("roster_preset_slots") - 1}]), _operation("org_apply_roster_preset", "Применить состав смены", [{"key":"slot", "label":"Пресет 0 или 1", "type":"number", "min":0, "max":_coefficient("roster_preset_slots") - 1}])]
		"P17":
			var available_specialists := _assigned_specialist_choices(p)
			if available_specialists.is_empty():
				return []
			return [_operation("org_start_training_task", "Начать профильное обучение назначенного специалиста", [{"key":"specialist_id", "label":"Назначенный специалист", "type":"select", "choices":available_specialists}])]
		"P19":
			var assigned := _assigned_specialist_choices(p)
			if assigned.is_empty():
				return []
			return [_operation("org_reassign_specialist", "Бесплатно переназначить специалиста", [{"key":"specialist_id", "label":"Специалист", "type":"select", "choices":assigned}, {"key":"site", "label":"Участок", "type":"select", "choices":_open_site_choices(p)}, {"key":"slot", "label":"Слот", "type":"number", "min":0, "max":4}])]
		"P20":
			if bool(_state(p).get("group_task_claimed", false)) or not _state(p).get("group_task", {}).is_empty():
				return []
			var team_sites := _qualified_team_site_choices(p)
			if team_sites.is_empty():
				return []
			return [_operation("org_start_group_task", "Начать уникальное групповое задание", [{"key":"site", "label":"Участок команды", "type":"select", "choices":team_sites}])]
		"G08":
			var report_choices := _report_choices(p, true, false)
			if report_choices.is_empty():
				return []
			return [_operation("org_preview_geology_event", "Проверить вариант события из реального отчёта", [{"key":"report_id", "label":"Геоотчёт", "type":"select", "choices":report_choices}])]
		"G10":
			var artifact_choices := _artifact_report_choices(p)
			if artifact_choices.is_empty():
				return []
			return [_operation("org_study_artifact", "Изучить ранее найденный артефакт", [{"key":"report_id", "label":"Геоотчёт с артефактом", "type":"select", "choices":artifact_choices}])]
		"G12":
			var geology: Dictionary = GameMath.game(p).get("progression", {}).get("geology", {})
			if geology.get("active", {}).is_empty() or not _state(p).get("secondary_expedition", {}).is_empty():
				return []
			var expedition_choices := _geology_expedition_choices(p)
			if expedition_choices.is_empty():
				return []
			return [_operation("org_start_parallel_expedition", "Второе геологическое задание · доступно %d¢ с учётом резервов" % GameMath.available_money(p), [{"key":"expedition_id", "label":"Цена и доступность экспедиции", "type":"select", "choices":expedition_choices}])]
		"G16":
			var choices := _report_choices(p, false, true)
			if choices.is_empty():
				return []
			return [_operation("org_choose_geology_event", "Выбрать необязательный пункт геокарты", [{"key":"report_id", "label":"Известный геоотчёт", "type":"select", "choices":choices}, {"key":"choice", "label":"Безопасный вариант", "type":"select", "choices":_choice_descriptors()}])]
	return []

static func after_action(p: Dictionary, _domain: String, _action: String, _args: Dictionary, result: Dictionary) -> void:
	if not bool(result.get("ok", false)):
		return
	ensure(p)
	_sync_work_progress(p)
	refresh(p)

static func coverage() -> Dictionary:
	var supported: Array[String] = []
	var gaps: Array[String] = []
	var by_id: Dictionary = {}
	for id in ORGANISATION_IDS:
		var spec: Dictionary = _config().get("supported", {}).get(id, {})
		var actions: Array = spec.get("actions", [])
		var implemented := not actions.is_empty()
		for action in actions:
			if not IMPLEMENTED_ACTIONS.has(str(action)):
				implemented = false
		var enabled := implemented
		by_id[id] = {"status":"supported" if enabled else "gap", "supported":enabled, "catalog":"research", "mechanism":str(spec.get("mechanism", "")), "canonical_effect":str(spec.get("canonical_effect", "")), "actions":actions.duplicate()}
		if enabled:
			supported.append(id)
		else:
			by_id[id]["gap"] = "One or more configured actions have no organisation handler."
			gaps.append(id)
	return {"total":ORGANISATION_IDS.size(), "supported_ids":supported, "gap_ids":gaps, "by_id":by_id}

static func validate(p: Dictionary) -> bool:
	var families: Variant = GameMath.game(p).get("feature_families", {})
	if not families is Dictionary or not families.get("organisation", {}) is Dictionary:
		return true
	var state: Dictionary = families["organisation"]
	for key in ["shift_presets", "roster_presets", "factory_cosmetic", "completed_shift_tasks", "training_awards", "geology_previews", "geology_preview_attempts", "studied_artifacts", "geology_choices"]:
		if state.has(key) and not state[key] is Dictionary:
			return false
	if state.has("shift_effects") and not state["shift_effects"] is Array:
		return false
	if state.has("secondary_expedition") and not state["secondary_expedition"] is Dictionary:
		return false
	for effect in state.get("shift_effects", []):
		if not effect is Dictionary or not _finite_nonnegative(effect.get("remaining_seconds", null)) or not _finite_nonnegative(effect.get("amount", null)):
			return false
	return true

static func _save_shift_preset(p: Dictionary, args: Dictionary) -> Dictionary:
	var slot := _bounded_slot(args.get("slot", null), _coefficient("shift_preset_slots"))
	if slot < 0 or _level(p, "A10") <= 0:
		return GameMath.fail("Нужен открытый A10 и допустимый слот пресета.")
	FEATURE_MODEL.ensure(p)
	var features: Dictionary = GameMath.game(p).get("features", {})
	var a10: Dictionary = features.get("A10", {})
	var a19: Dictionary = features.get("A19", {})
	var routes: Dictionary = a19.get("routes", {}) if _level(p, "A19") > 0 else {}
	_state(p)["shift_presets"][str(slot)] = {"first_line":int(a10.get("first_line", 0)), "routes":routes.duplicate(true)}
	return GameMath.ok("Настройки смены сохранены; уровни, склад и ресурсы не изменены.")

static func _apply_shift_preset(p: Dictionary, args: Dictionary) -> Dictionary:
	var slot := _bounded_slot(args.get("slot", null), _coefficient("shift_preset_slots"))
	var presets: Dictionary = _state(p)["shift_presets"]
	if slot < 0 or not presets.has(str(slot)):
		return GameMath.fail("Сохранённый пресет не найден.")
	var preset: Dictionary = presets[str(slot)]
	return _apply_route_snapshot(p, preset.get("routes", {}), int(preset.get("first_line", 0)), "")

static func _set_factory_cosmetic(p: Dictionary, args: Dictionary) -> Dictionary:
	var cosmetic := str(args.get("cosmetic", ""))
	var owned: Dictionary = _state(p)["factory_cosmetic"]["owned"]
	if not owned.has(cosmetic):
		return GameMath.fail("Эта отделка ещё не открыта.")
	_state(p)["factory_cosmetic"]["active"] = cosmetic
	return GameMath.ok("Косметический ключ фабрики сохранён; изображение может быть добавлено отдельно.")

static func _save_automation_template(p: Dictionary) -> Dictionary:
	if _level(p, "A19") <= 0:
		return GameMath.fail("Для шаблона нужна изученная настройка оплачиваемых маршрутов A19.")
	FEATURE_MODEL.ensure(p)
	var features: Dictionary = GameMath.game(p).get("features", {})
	var a10: Dictionary = features.get("A10", {})
	var a19: Dictionary = features.get("A19", {})
	_state(p)["automation_template"] = {"first_line":int(a10.get("first_line", 0)), "routes":Dictionary(a19.get("routes", {})).duplicate(true)}
	return GameMath.ok("Шаблон будущего участка сохранён. Он не запускает оплату автоматически.")

static func _apply_automation_template(p: Dictionary, args: Dictionary) -> Dictionary:
	var site := str(args.get("site", ""))
	var template: Dictionary = _state(p).get("automation_template", {})
	if template.is_empty() or not GameMath.SITES.has(site) or not GameMath.unlocked(p, site):
		return GameMath.fail("Нужен сохранённый шаблон и уже открытый целевой участок.")
	return _apply_route_snapshot(p, template.get("routes", {}), int(template.get("first_line", 0)), site)

static func _start_shift_task(p: Dictionary, args: Dictionary) -> Dictionary:
	var choice := str(args.get("choice", ""))
	var site := str(args.get("site", "fe"))
	var state := _state(p)
	if not ["speed", "logistics"].has(choice) or not GameMath.SITES.has(site) or not GameMath.unlocked(p, site):
		return GameMath.fail("Выберите доступный участок и один из двух вариантов смены.")
	if not state["active_shift_task"].is_empty():
		return GameMath.fail("Сначала завершите текущую задачу смены.")
	state["shift_task_sequence"] = int(state["shift_task_sequence"]) + 1
	var task_id := "shift-%04d" % int(state["shift_task_sequence"])
	state["active_shift_task"] = {"id":task_id, "choice":choice, "site":site, "progress":0.0, "required_work":_coefficient("shift_work_units"), "baseline":_site_output(p, site)}
	return GameMath.ok("Задача смены начата; эффект будет выдан только за реальную продукцию после старта.")

static func _save_roster_preset(p: Dictionary, args: Dictionary) -> Dictionary:
	var slot := _bounded_slot(args.get("slot", null), _coefficient("roster_preset_slots"))
	if slot < 0:
		return GameMath.fail("Допустимы только два слота состава смены.")
	META_MODEL.ensure(p)
	var assignments: Dictionary = GameMath.game(p)["meta"]["specialists"]["assignments"]
	_state(p)["roster_presets"][str(slot)] = assignments.duplicate(true)
	return GameMath.ok("Состав текущей команды сохранён без найма или изменения уровней.")

static func _apply_roster_preset(p: Dictionary, args: Dictionary) -> Dictionary:
	var slot := _bounded_slot(args.get("slot", null), _coefficient("roster_preset_slots"))
	var presets: Dictionary = _state(p)["roster_presets"]
	if slot < 0 or not presets.has(str(slot)):
		return GameMath.fail("Сохранённый состав не найден.")
	return _replace_assignments(p, presets[str(slot)])

static func _reassign_specialist(p: Dictionary, args: Dictionary) -> Dictionary:
	var specialist_id := str(args.get("specialist_id", ""))
	var target_site := str(args.get("site", "fe"))
	var target_slot := _bounded_slot(args.get("slot", null), 5)
	if _level(p, "P19") <= 0 or specialist_id.is_empty() or target_slot < 0:
		return GameMath.fail("Нужен открытый P19 и допустимый слот.")
	META_MODEL.ensure(p)
	var assignments: Dictionary = GameMath.game(p)["meta"]["specialists"]["assignments"]
	var old_site := ""
	var old_slot := -1
	for site in assignments:
		for slot in assignments[site]:
			if str(assignments[site][slot]) == specialist_id:
				old_site = str(site)
				old_slot = int(slot)
	if old_site.is_empty():
		return GameMath.fail("Переназначить можно только реально назначенного специалиста.")
	if old_site == target_site and old_slot == target_slot:
		return GameMath.ok("Специалист уже занимает выбранный слот.")
	var removed := META_MODEL.act(p, "specialist_unassign", {"site":old_site, "slot":old_slot})
	if not bool(removed.get("ok", false)):
		return removed
	var assigned := META_MODEL.act(p, "specialist_assign", {"specialist_id":specialist_id, "site":target_site, "slot":target_slot})
	if not bool(assigned.get("ok", false)):
		META_MODEL.act(p, "specialist_assign", {"specialist_id":specialist_id, "site":old_site, "slot":old_slot})
		return assigned
	return GameMath.ok("Специалист бесплатно переназначен по правилам состава MetaModel.")

static func _start_training_task(p: Dictionary, args: Dictionary) -> Dictionary:
	var specialist_id := str(args.get("specialist_id", ""))
	var state := _state(p)
	if not state["training_task"].is_empty():
		return GameMath.fail("Другая учебная задача уже выполняется.")
	META_MODEL.ensure(p)
	var specialist: Dictionary = GameMath.game(p)["meta"]["specialists"]["owned"].get(specialist_id, {})
	var assignment := _assignment_for(p, specialist_id)
	if specialist.is_empty() or assignment.is_empty() or GameMath.record("specialists", specialist_id).is_empty():
		return GameMath.fail("Обучение доступно только полученному каноническому специалисту в активном составе.")
	var awards: Dictionary = state["training_awards"]
	if int(awards.get(specialist_id, 0)) >= _level(p, "P17"):
		return GameMath.fail("Для этого специалиста уже использованы учебные задачи текущего ранга.")
	var row := GameMath.record("specialists", specialist_id)
	if int(specialist.get("level", 1)) >= int(row.get("level_cap", 100)):
		return GameMath.fail("Специалист уже достиг канонического предела уровня.")
	var site := str(assignment["site"])
	state["training_task"] = {"specialist_id":specialist_id, "site":site, "progress":0.0, "required_work":_coefficient("training_work_units"), "baseline":_site_output(p, site)}
	return GameMath.ok("Учебная задача начата; засчитывается только продукция после назначения и старта.")

static func _start_group_task(p: Dictionary, args: Dictionary) -> Dictionary:
	var site := str(args.get("site", "fe"))
	var state := _state(p)
	if bool(state.get("group_task_claimed", false)) or not state["group_task"].is_empty():
		return GameMath.fail("Уникальное групповое задание уже начато или завершено.")
	if not GameMath.SITES.has(site) or not GameMath.unlocked(p, site) or _assigned_count(p, site) < _coefficient("group_required_specialists"):
		return GameMath.fail("Нужны открытый участок и достаточное число реально назначенных специалистов.")
	var team_ids := _canonical_assigned_ids(p, site)
	state["group_task"] = {"site":site, "team_ids":team_ids, "progress":0.0, "required_work":_coefficient("group_work_units"), "baseline":_site_output(p, site)}
	return GameMath.ok("Групповое задание начато; учитывается только новая продукция команды.")

static func _preview_geology_event(p: Dictionary, args: Dictionary) -> Dictionary:
	var report_id := str(args.get("report_id", ""))
	var state := _state(p)
	var report := _report_by_id(p, report_id)
	if report.is_empty() or state["geology_preview_attempts"].has(report_id):
		return GameMath.fail("Нужен новый реальный геоотчёт; повторный бросок для отчёта запрещён.")
	state["geology_preview_attempts"][report_id] = true
	var chance := clampf(_number("geology_preview_chance_per_level") * float(_level(p, "G08")), 0.0, 1.0)
	if float(_stable_hash(report_id) % 10000) / 10000.0 >= chance:
		return GameMath.fail("На этот известный отчёт вариант не раскрылся; повторно проверить его нельзя.")
	var choices := _geology_choices_for_report(report)
	if choices.is_empty():
		return GameMath.fail("В отчёте нет известного события для предварительного выбора.")
	var option := str(choices[_stable_hash(report_id + ":option") % choices.size()])
	state["geology_previews"][report_id] = {"option":option, "choices":choices.duplicate(), "expedition":str(report.get("expedition", ""))}
	return GameMath.ok("Показан вариант, рассчитанный только по этому реальному отчёту.")

static func _study_artifact(p: Dictionary, args: Dictionary) -> Dictionary:
	var report_id := str(args.get("report_id", ""))
	var report := _report_by_id(p, report_id)
	if report.is_empty():
		return GameMath.fail("Сначала найдите геологический артефакт в реальной экспедиции.")
	var artifact_tag := ""
	var tags: Array = report.get("tags", [])
	var studied: Dictionary = _state(p)["studied_artifacts"]
	for tag in _config().get("coefficients", {}).get("artifact_tags", []):
		if tags.has(tag) and not studied.has(report_id + ":" + str(tag)):
			artifact_tag = str(tag)
			break
	var claim_id := report_id + ":" + artifact_tag
	if artifact_tag.is_empty():
		return GameMath.fail("В отчёте нет неизученного артефакта.")
	var level := _level(p, "G10")
	var reward := _coefficient("artifact_research_points_base") + _coefficient("artifact_research_points_per_level") * maxi(0, level - 1)
	_state(p)["studied_artifacts"][claim_id] = true
	var g := GameMath.game(p)
	p["research_points"] = int(p.get("research_points", 0)) + reward
	var state := _state(p)
	state["artifact_scan_bonus"] = minf(_number("artifact_scan_bonus_cap"), float(state.get("artifact_scan_bonus", 0.0)) + _number("artifact_scan_bonus_per_level") * float(level))
	refresh(p)
	return {"ok":true, "message":"Артефакт изучен один раз; эффект ускорит только будущие сканирования.", "research_points":reward, "artifact":claim_id}

static func _start_parallel_expedition(p: Dictionary, args: Dictionary) -> Dictionary:
	var state := _state(p)
	var progression: Dictionary = GameMath.game(p).get("progression", {})
	var geology: Dictionary = progression.get("geology", {})
	if _level(p, "G12") <= 0 or int(_coefficient("parallel_expedition_capacity")) < 2:
		return GameMath.fail("Параллельное задание недоступно.")
	if geology.get("active", {}).is_empty():
		return GameMath.fail("Сначала оплатите и начните первое геологическое задание.")
	if not state["secondary_expedition"].is_empty():
		return GameMath.fail("Общая геологическая мощность уже занята двумя заданиями.")
	var expedition_id := str(args.get("expedition_id", ""))
	var result: Dictionary = PROGRESSION_MODEL.start_parallel_geology_expedition(p, expedition_id)
	if not bool(result.get("ok", false)):
		return result
	var secondary: Dictionary = result.get("expedition", {})
	if float(secondary.get("remaining_seconds", 0.0)) <= 0.0:
		PROGRESSION_MODEL.complete_parallel_geology_expedition(p, secondary)
	else:
		state["secondary_expedition"] = secondary
	return GameMath.ok("Вторая экспедиция оплачена по обычным правилам; обе делят одну пропускную способность.")

static func _choose_geology_event(p: Dictionary, args: Dictionary) -> Dictionary:
	var report_id := str(args.get("report_id", ""))
	var option := str(args.get("choice", ""))
	var report := _report_by_id(p, report_id)
	var state := _state(p)
	if report.is_empty() or state["geology_choices"].has(report_id) or not _config().get("coefficients", {}).get("geology_choices", []).has(option):
		return GameMath.fail("Выбор доступен только для ещё не отмеченного реального отчёта.")
	var choices := _geology_choices_for_report(report)
	if not choices.has(option):
		return GameMath.fail("Этот вариант не подходит известным данным отчёта.")
	state["geology_choices"][report_id] = {"choice":option, "site":str(report.get("site", "")), "expedition":str(report.get("expedition", "")), "tags":Array(report.get("tags", [])).duplicate()}
	if option == "chart":
		state["map_focus"] = str(report.get("site", ""))
	return GameMath.ok("Необязательный выбор сохранён; сюжетные флаги и ресурсы не менялись.")

static func _sync_work_progress(p: Dictionary) -> void:
	var state := _state(p)
	var shift: Dictionary = state.get("active_shift_task", {})
	if not shift.is_empty():
		_update_work_task(p, shift, "shift")
	var training: Dictionary = state.get("training_task", {})
	if not training.is_empty():
		_update_work_task(p, training, "training")
	var group: Dictionary = state.get("group_task", {})
	if not group.is_empty():
		_update_work_task(p, group, "group")

static func _update_work_task(p: Dictionary, task: Dictionary, kind: String) -> void:
	var site := str(task.get("site", "fe"))
	var current := _site_output(p, site)
	if kind == "training" and str(_assignment_for(p, str(task.get("specialist_id", ""))).get("site", "")) != site:
		task["baseline"] = current
		return
	if kind == "group" and not _group_team_is_assigned(p, task):
		task["baseline"] = current
		return
	var baseline := float(task.get("baseline", current))
	var progress := maxf(0.0, float(task.get("progress", 0.0))) + maxf(0.0, current - baseline)
	task["baseline"] = current
	task["progress"] = progress
	if progress < float(task.get("required_work", INF)):
		return
	var state := _state(p)
	match kind:
		"shift": _complete_shift_task(p, task)
		"training": _complete_training_task(p, task)
		"group": _complete_group_task(p)

static func _complete_shift_task(p: Dictionary, task: Dictionary) -> void:
	var state := _state(p)
	var task_id := str(task.get("id", ""))
	if task_id.is_empty() or state["completed_shift_tasks"].has(task_id):
		state["active_shift_task"] = {}
		return
	state["completed_shift_tasks"][task_id] = true
	var choice := str(task.get("choice", ""))
	var key := "speed" if choice == "speed" else "logistics"
	var amount_key := "shift_speed_per_task" if choice == "speed" else "shift_logistics_per_task"
	var active_total := 0.0
	for effect in state["shift_effects"]:
		if str(effect.get("choice", "")) == choice:
			active_total += float(effect.get("amount", 0.0))
	var amount := minf(_number(amount_key), maxf(0.0, _number("shift_total_bonus_cap") - active_total))
	if amount > 0.0:
		state["shift_effects"].append({"id":task_id, "choice":choice, "amount":amount, "remaining_seconds":_number("shift_effect_seconds")})
	state["active_shift_task"] = {}

static func _complete_training_task(p: Dictionary, task: Dictionary) -> void:
	var state := _state(p)
	var specialist_id := str(task.get("specialist_id", ""))
	var awards: Dictionary = state["training_awards"]
	awards[specialist_id] = int(awards.get(specialist_id, 0)) + 1
	var owned: Dictionary = GameMath.game(p).get("meta", {}).get("specialists", {}).get("owned", {})
	if owned.has(specialist_id):
		var specialist: Dictionary = owned[specialist_id]
		specialist["training_xp"] = int(specialist.get("training_xp", 0)) + _coefficient("training_xp_per_task")
		var row := GameMath.record("specialists", specialist_id)
		var threshold := maxi(1, _coefficient("training_xp_per_level"))
		var level := int(specialist.get("level", 1))
		var cap := int(row.get("level_cap", level))
		while int(specialist["training_xp"]) >= threshold and level < cap:
			specialist["training_xp"] = int(specialist["training_xp"]) - threshold
			level += 1
		specialist["level"] = level
		if level >= cap:
			specialist["training_xp"] = 0
		META_MODEL.refresh(p)
	state["training_task"] = {}

static func _complete_group_task(p: Dictionary) -> void:
	var state := _state(p)
	if bool(state.get("group_task_claimed", false)):
		state["group_task"] = {}
		return
	var task: Dictionary = state.get("group_task", {})
	if not _group_team_is_assigned(p, task):
		return
	state["group_task_claimed"] = true
	p["research_points"] = int(p.get("research_points", 0)) + _coefficient("group_reward_research_points")
	state["group_task"] = {}

static func _replace_assignments(p: Dictionary, target: Dictionary) -> Dictionary:
	META_MODEL.ensure(p)
	var current: Dictionary = GameMath.game(p)["meta"]["specialists"]["assignments"].duplicate(true)
	var probe := p.duplicate(true)
	var validation := _set_assignments_through_meta(probe, target)
	if not bool(validation.get("ok", false)):
		return validation
	var applied := _set_assignments_through_meta(p, target)
	if not bool(applied.get("ok", false)):
		_set_assignments_through_meta(p, current)
		return applied
	return GameMath.ok("Состав применён через стандартную проверку владения, участка и слота.")

static func _set_assignments_through_meta(p: Dictionary, target: Dictionary) -> Dictionary:
	META_MODEL.ensure(p)
	var assignments: Dictionary = GameMath.game(p)["meta"]["specialists"]["assignments"]
	for site in assignments.keys():
		var team: Dictionary = assignments[site].duplicate()
		for slot in team.keys():
			var removed := META_MODEL.act(p, "specialist_unassign", {"site":str(site), "slot":int(slot)})
			if not bool(removed.get("ok", false)):
				return removed
	for site in target:
		if not target[site] is Dictionary:
			return GameMath.fail("Сохранённый состав повреждён.")
		for slot in target[site]:
			var result := META_MODEL.act(p, "specialist_assign", {"specialist_id":str(target[site][slot]), "site":str(site), "slot":int(slot)})
			if not bool(result.get("ok", false)):
				return result
	return GameMath.ok("Состав установлен.")

static func _apply_route_snapshot(p: Dictionary, routes: Dictionary, first_line: int, target_site: String) -> Dictionary:
	FEATURE_MODEL.ensure(p)
	var previous_features: Dictionary = GameMath.game(p).get("features", {}).duplicate(true)
	var probe := p.duplicate(true)
	var preview := _apply_route_snapshot_impl(probe, routes, first_line, target_site)
	if not bool(preview.get("ok", false)):
		return preview
	var applied := _apply_route_snapshot_impl(p, routes, first_line, target_site)
	if not bool(applied.get("ok", false)):
		GameMath.game(p)["features"] = previous_features
		return applied
	return applied

static func _apply_route_snapshot_impl(p: Dictionary, routes: Dictionary, first_line: int, target_site: String) -> Dictionary:
	if target_site != "" and (not GameMath.SITES.has(target_site) or not GameMath.unlocked(p, target_site)):
		return GameMath.fail("Целевой участок ещё не открыт.")
	if _level(p, "A10") > 0:
		var priority := FEATURE_MODEL.act(p, "set_factory_priority", {"id":"A10", "first_line":first_line})
		if not bool(priority.get("ok", false)):
			return priority
	if _level(p, "A19") <= 0:
		return GameMath.ok("Приоритет применён; платные маршруты пока не изучены.")
	FEATURE_MODEL.ensure(p)
	var live_routes: Dictionary = GameMath.game(p).get("features", {}).get("A19", {}).get("routes", {})
	for raw_line in live_routes.keys():
		var existing: Dictionary = live_routes[raw_line]
		if target_site != "" and _recipe_site(str(existing.get("recipe_id", ""))) != target_site:
			continue
		var cleared := FEATURE_MODEL.act(p, "clear_line_route", {"id":"A19", "line":int(raw_line)})
		if not bool(cleared.get("ok", false)):
			return cleared
	for raw_line in routes:
		var route: Dictionary = routes[raw_line]
		var recipe_id := str(route.get("recipe_id", ""))
		var recipe_site := _recipe_site(recipe_id)
		if recipe_site.is_empty() or (target_site != "" and recipe_site != target_site) or not GameMath.unlocked(p, recipe_site):
			continue
		var budget := int(route.get("budget_cents", 0))
		if budget <= 0 or not bool(route.get("enabled", true)):
			return GameMath.fail("Автомаршрут требует отдельный ненулевой бюджет на реальную партию.")
		var configured := FEATURE_MODEL.act(p, "set_line_route", {"id":"A19", "line":int(raw_line), "recipe_id":recipe_id, "budget_cents":budget})
		if not bool(configured.get("ok", false)):
			return configured
	return GameMath.ok("Настройки применены вручную; каждый действующий маршрут сохраняет собственный денежный предел.")

static func _assignment_for(p: Dictionary, specialist_id: String) -> Dictionary:
	var assignments: Dictionary = GameMath.game(p).get("meta", {}).get("specialists", {}).get("assignments", {})
	for site in assignments:
		for slot in assignments[site]:
			if str(assignments[site][slot]) == specialist_id:
				return {"site":str(site), "slot":str(slot)}
	return {}

static func _assigned_count(p: Dictionary, site: String) -> int:
	return _canonical_assigned_ids(p, site).size()

static func _canonical_assigned_ids(p: Dictionary, site: String) -> Array:
	var result: Array = []
	var specialists: Dictionary = GameMath.game(p).get("meta", {}).get("specialists", {})
	var assignments: Dictionary = specialists.get("assignments", {})
	var owned: Dictionary = specialists.get("owned", {})
	for specialist_id in assignments.get(site, {}).values():
		var id := str(specialist_id)
		if owned.has(id) and not GameMath.record("specialists", id).is_empty() and not result.has(id):
			result.append(id)
	return result

static func _group_team_is_assigned(p: Dictionary, task: Dictionary) -> bool:
	var site := str(task.get("site", ""))
	var assigned := _canonical_assigned_ids(p, site)
	var team_ids: Array = task.get("team_ids", [])
	if team_ids.size() < _coefficient("group_required_specialists"):
		return false
	for specialist_id in team_ids:
		if not assigned.has(str(specialist_id)):
			return false
	return true

static func _assigned_specialist_choices(p: Dictionary) -> Array:
	META_MODEL.ensure(p)
	var choices: Array = []
	var assignments: Dictionary = GameMath.game(p)["meta"]["specialists"]["assignments"]
	for site in assignments:
		for specialist_id in assignments[site].values():
			var row := GameMath.record("specialists", str(specialist_id))
			if not row.is_empty():
				choices.append({"label":str(row.get("name", specialist_id)), "value":str(specialist_id)})
	return choices

static func _qualified_team_site_choices(p: Dictionary) -> Array:
	var result: Array = []
	for site in GameMath.SITES:
		if GameMath.unlocked(p, site) and _assigned_count(p, site) >= _coefficient("group_required_specialists"):
			result.append({"label":site.to_upper(), "value":site})
	return result

static func _open_site_choices(p: Dictionary) -> Array:
	var result: Array = []
	for site in GameMath.SITES:
		if GameMath.unlocked(p, site):
			result.append({"label":site.to_upper(), "value":site})
	return result

static func _report_choices(p: Dictionary, only_unpreviewed: bool, only_unselected: bool) -> Array:
	var result: Array = []
	var state := _state(p)
	for report in GameMath.game(p).get("progression", {}).get("geology", {}).get("reports", []):
		if not report is Dictionary:
			continue
		var report_id := str(report.get("id", ""))
		if (only_unpreviewed and state["geology_preview_attempts"].has(report_id)) or (only_unselected and state["geology_choices"].has(report_id)):
			continue
		result.append({"label":"%s · %s" % [report_id, str(report.get("expedition", ""))], "value":report_id})
	return result

static func _artifact_report_choices(p: Dictionary) -> Array:
	var result: Array = []
	var tags: Array = _config().get("coefficients", {}).get("artifact_tags", [])
	for report in GameMath.game(p).get("progression", {}).get("geology", {}).get("reports", []):
		if not report is Dictionary:
			continue
		var report_id := str(report.get("id", ""))
		for tag in tags:
			var claim_id := report_id + ":" + str(tag)
			if Array(report.get("tags", [])).has(tag) and not _state(p)["studied_artifacts"].has(claim_id):
				result.append({"label":"%s · %s" % [report_id, str(tag)], "value":report_id})
				break
	return result

static func _report_by_id(p: Dictionary, report_id: String) -> Dictionary:
	for report in GameMath.game(p).get("progression", {}).get("geology", {}).get("reports", []):
		if report is Dictionary and str(report.get("id", "")) == report_id:
			return report
	return {}

static func _geology_choices_for_report(report: Dictionary) -> Array:
	var choices: Array = []
	var configured: Array = _config().get("coefficients", {}).get("geology_choices", [])
	var tags: Array = report.get("tags", [])
	for choice in configured:
		if choice == "chart" or (choice == "archive" and not tags.is_empty()):
			choices.append(str(choice))
	return choices

static func _choice_descriptors() -> Array:
	var result: Array = []
	for choice in _config().get("coefficients", {}).get("geology_choices", []):
		result.append({"label":"Отметить на карте" if choice == "chart" else "Добавить в архив", "value":choice})
	return result

static func _geology_expedition_choices(p: Dictionary) -> Array:
	var result: Array = []
	var config := _progression_config()
	var available := GameMath.available_money(p)
	for expedition_id in config.get("geology_expeditions", {}):
		var spec: Dictionary = config["geology_expeditions"][expedition_id]
		var site := str(spec.get("site", "fe"))
		if site != "fe" and not GameMath.unlocked(p, site):
			continue
		if str(expedition_id) == "deep_signal" and not GameMath.game(p).get("progression", {}).get("buildings", {}).get("deep_station", {}).get("status", "") == "complete":
			continue
		var cost := int(spec.get("cost_cents", 0))
		var affordable := available >= cost
		var affordability := "доступно" if affordable else "не хватает свободных средств"
		result.append({"label":"%s · %d¢ · %s" % [str(expedition_id), cost, affordability], "value":str(expedition_id), "cost_cents":cost, "available_cents":available, "affordable":affordable})
	return result

static func _recipe_site(recipe_id: String) -> String:
	var row := GameMath.record("recipes", recipe_id)
	var output := str(row.get("output", ""))
	if output.begins_with("pd_"):
		return "pd"
	if output.begins_with("ir_"):
		return "ir"
	return "fe" if not output.is_empty() else ""

static func _site_output(p: Dictionary, site: String) -> float:
	if not GameMath.SITES.has(site):
		return 0.0
	return float(GameMath.site(p, site).get("mined", 0.0))

static func _equipment_levels(p: Dictionary) -> int:
	var site := GameMath.site(p, "fe")
	var total := 0
	for field in ["upgrades", "machines"]:
		for level in site.get(field, {}).values():
			total += int(level)
	return total

static func _bounded_slot(value: Variant, count: int) -> int:
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or float(value) != floorf(float(value)):
		return -1
	var slot := int(value)
	return slot if slot >= 0 and slot < count else -1

static func _level(p: Dictionary, id: String) -> int:
	var progression: Dictionary = GameMath.game(p).get("progression", {})
	return int(progression.get("research", {}).get(id, 0))

static func _state(p: Dictionary) -> Dictionary:
	return GameMath.game(p)["feature_families"]["organisation"]

static func _operation(action: String, title: String, fields: Array) -> Dictionary:
	return {"action":action, "title":title, "fields":fields}

static func _ensure_fields(target: Dictionary, defaults: Dictionary) -> void:
	for key in defaults:
		if not target.has(key) or typeof(target[key]) != typeof(defaults[key]):
			target[key] = defaults[key].duplicate(true) if defaults[key] is Dictionary or defaults[key] is Array else defaults[key]

static func _coefficient(key: String) -> int:
	return int(_config().get("coefficients", {}).get(key, 0))

static func _number(key: String) -> float:
	return float(_config().get("coefficients", {}).get(key, 0.0))

static func _finite_nonnegative(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) >= 0.0

static func _config() -> Dictionary:
	if _config_cache.is_empty():
		_config_cache = _read_json(CONFIG_PATH)
	return _config_cache

static func _progression_config() -> Dictionary:
	if _progression_config_cache.is_empty():
		_progression_config_cache = _read_json(PROGRESSION_CONFIG_PATH)
	return _progression_config_cache

static func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}

static func _stable_hash(value: String) -> int:
	var result := 2166136261
	for byte in value.to_utf8_buffer():
		result = int((result ^ int(byte)) * 16777619) & 0x7fffffff
	return result
