extends RefCounted

const MODEL_PATH := "res://gameplay/ProgressionModel.gd"
const PROPOSAL_PATH := "res://data/proposals/progression.json"
const STORY_PATH := "res://data/canon/12_Сюжет_20_диалоги_v9.json"
const SITE_NAMES := {"fe":"Шахта №17 · Fe", "pd":"Комплекс П-7 · Pd", "ir":"Сектор И-9 · Ir"}
const RESEARCH_FILTERS := [
	["Общие + участок", "current"], ["Общие", "common"],
	["Fe", "fe"], ["Pd", "pd"], ["Ir", "ir"], ["Все", "all"],
]
const NETWORK_MODES := ["balanced", "income", "build"]

static var _progression_script: Script
static var _proposal_data: Dictionary = {}
static var _dialogues: Array = []

static func render(screen: Control, body: VBoxContainer, tab: String) -> void:
	var content := HorizonUI.column(body, 9)
	content.name = "ProgressionContent"
	var profile: Dictionary = screen.call("profile")
	match tab:
		"research": _render_research(screen, content, profile)
		"mastery": _render_mastery(screen, content, profile)
		"geology": _render_geology(screen, content, profile)
		"contracts": _render_contracts(screen, content, profile)
		"buildings": _render_buildings(screen, content, profile)
		"story": _render_story(screen, content, profile)
		"expansion": _render_expansion(screen, content, profile)
		"network": _render_network(screen, content, profile)
		"map": _render_map(screen, content, profile)
		_:
			HorizonUI.notice(content, "Раздел прогрессии не найден.")

static func _model_call(method: String, args: Array) -> Variant:
	if _progression_script == null:
		_progression_script = load(MODEL_PATH) as Script
	if _progression_script == null or not _progression_script.has_method(method):
		return null
	return _progression_script.callv(method, args)

static func _view(profile: Dictionary) -> Dictionary:
	var value: Variant = _model_call("view", [profile])
	return value if value is Dictionary else {}

static func _proposal_section(section: String) -> Dictionary:
	if _proposal_data.is_empty():
		var file := FileAccess.open(PROPOSAL_PATH, FileAccess.READ)
		if file != null:
			var value: Variant = JSON.parse_string(file.get_as_text())
			if value is Dictionary:
				_proposal_data = value
	var value: Variant = _proposal_data.get(section, {})
	return value if value is Dictionary else {}

static func _catalog(name: String) -> Array:
	return ContentRegistry.get_records(StringName(name))

static func _game(profile: Dictionary) -> Dictionary:
	var value: Variant = profile.get("game", {})
	return value if value is Dictionary else {}

static func _tab_state(screen: Control, tab: String) -> Dictionary:
	var value: Variant = screen.get("ui_state")
	var all: Dictionary = value if value is Dictionary else {}
	if not all.has(tab) or not all[tab] is Dictionary:
		all[tab] = {}
		screen.set("ui_state", all)
	return all[tab]

static func _set_state(screen: Control, tab: String, key: String, value: Variant) -> void:
	var state := _tab_state(screen, tab)
	state[key] = value

static func _card(screen: Control, parent: Node, title: String, description: String = "") -> VBoxContainer:
	return screen.call("card", parent, title, description) as VBoxContainer

static func _button(screen: Control, parent: Node, label: String, command: String, args: Dictionary = {}, reason: String = "") -> Button:
	return _button_domain(screen, parent, label, "progression", command, args, reason)

static func _button_domain(screen: Control, parent: Node, label: String, domain: String, command: String, args: Dictionary = {}, reason: String = "") -> Button:
	return screen.call("btn", parent, label, domain, command, args, reason) as Button

static func _live_label(screen: Control, parent: Node, value: Callable) -> Label:
	return screen.call("live", parent, value) as Label

static func _site(screen: Control) -> String:
	var value := str(screen.get("site"))
	return value if GameMath.SITES.has(value) else "fe"

static func _format_value(value: Variant) -> String:
	if value is bool:
		return "да" if value else "нет"
	if value is Array:
		var parts: PackedStringArray = []
		for item in value:
			parts.append(str(item))
		return ", ".join(parts)
	if value is Dictionary:
		return JSON.stringify(value)
	return str(value)

static func _first_value(source: Dictionary, keys: Array, fallback: Variant = null) -> Variant:
	for key in keys:
		if source.has(key):
			return source[key]
	return fallback

static func _status_reason(status: Dictionary, fallback: String) -> String:
	return str(_first_value(status, ["reason", "locked_reason", "why", "message"], fallback))

static func _option(parent: Node, options: Array, selected: String) -> OptionButton:
	var picker := OptionButton.new()
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for option in options:
		picker.add_item(str(option[0]))
		picker.set_item_metadata(picker.item_count - 1, option[1])
	for index in range(picker.item_count):
		if str(picker.get_item_metadata(index)) == selected:
			picker.select(index)
			break
	parent.add_child(picker)
	return picker

static func _render_research(screen: Control, content: VBoxContainer, profile: Dictionary) -> void:
	var state := _tab_state(screen, "research")
	var site_filter := str(state.get("site_filter", "current"))
	var branch_filter := str(state.get("branch_filter", "all"))
	var search_text := str(state.get("search", ""))
	var records := _catalog("research")
	var branches: Dictionary = {}
	for record in records:
		branches[str(record.get("branch", ""))] = true
	var branch_options: Array = [["Все ветви", "all"]]
	var branch_names: Array = branches.keys()
	branch_names.sort()
	for branch in branch_names:
		branch_options.append([str(branch), str(branch)])
	var description := "Каноническое дерево 140 исследований. Узлы показывают реальные зависимости, уровни и эффекты; поиск не меняет состояние."
	var header := _card(screen, content, "Исследования · %d записей" % records.size(), description)
	var filters := HBoxContainer.new()
	filters.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(filters)
	var site_picker := _option(filters, RESEARCH_FILTERS, site_filter)
	var branch_picker := _option(filters, branch_options, branch_filter)
	var search := LineEdit.new()
	search.placeholder_text = "Поиск по ID, названию, ветви или эффекту"
	search.text = search_text
	search.clear_button_enabled = true
	content.add_child(search)
	var summary := HorizonUI.notice(content, "")
	var entries := HorizonUI.column(content, 7)
	for record in records:
		var id := str(record.get("id", ""))
		var status_value: Variant = _model_call("research_status", [profile, id])
		var status: Dictionary = status_value if status_value is Dictionary else {}
		var level := int(_first_value(status, ["level", "current_level", "rank"], _research_level(profile, id)))
		var maximum := int(record.get("max_levels", 1))
		var next_cost: Variant = _first_value(status, ["next_cost_oi", "cost_next", "next_cost", "cost_oi"])
		var title := "%s  ·  %s" % [id, str(record.get("name", "Исследование"))]
		var items := _card(screen, entries, title, "%s  ·  уровень %d/%d" % [str(record.get("branch", "")), level, maximum])
		var panel := items.get_parent() as Control
		panel.set_meta("research_site", str(record.get("site", "common")))
		panel.set_meta("research_branch", str(record.get("branch", "")))
		panel.set_meta("research_text", (id + " " + title + " " + str(record.get("effect", ""))).to_lower())
		panel.set_meta("research_record", record)
		var cost_text := "Следующий уровень: %s ОИ" % str(next_cost) if next_cost != null else "Полная стоимость по канону: %s ОИ" % str(record.get("total_cost_oi", "—"))
		HorizonUI.label(items, cost_text, 13, HorizonUI.GOLD)
		var dependencies := str(record.get("dependencies", ""))
		var successors: PackedStringArray = []
		for candidate in records:
			if str(candidate.get("dependencies", "")).split(",", false).has(id):
				successors.append(str(candidate.get("id", "")))
		HorizonUI.label(items, "Зависимости: %s  ·  Открывает: %s\nУсловие: %s" % ["нет" if dependencies.is_empty() else dependencies, "нет" if successors.is_empty() else ", ".join(successors), str(record.get("unlock", "—"))], 13, HorizonUI.MUTED)
		HorizonUI.label(items, str(record.get("effect", "")), 14)
		var available := bool(_first_value(status, ["can_buy", "available", "unlocked", "can_research"], false))
		var reason := _status_reason(status, "Сначала выполните зависимости и условия открытия.")
		if level >= maximum:
			reason = "Достигнут максимальный уровень."
		_button(screen, items, "Исследовать" if level < maximum else "Уровень завершён", "research_buy", {"id":id}, "" if available and level < maximum else reason)
	var refresh_filter := func():
		var visible_count := _apply_research_filter(entries, search.text, str(site_picker.get_item_metadata(site_picker.selected)), str(branch_picker.get_item_metadata(branch_picker.selected)), screen)
		summary.text = "Показано узлов: %d из %d" % [visible_count, records.size()]
	refresh_filter.call()
	site_picker.item_selected.connect(func(index: int):
		_set_state(screen, "research", "site_filter", str(site_picker.get_item_metadata(index)))
		refresh_filter.call())
	branch_picker.item_selected.connect(func(index: int):
		_set_state(screen, "research", "branch_filter", str(branch_picker.get_item_metadata(index)))
		refresh_filter.call())
	search.text_changed.connect(func(value: String):
		_set_state(screen, "research", "search", value)
		refresh_filter.call())

static func _apply_research_filter(entries: VBoxContainer, query: String, site_filter: String, branch_filter: String, screen: Control) -> int:
	var visible_count := 0
	var active_site := _site(screen)
	var normalized := query.strip_edges().to_lower()
	for panel in entries.get_children():
		var row_site := str(panel.get_meta("research_site", "common"))
		var row_branch := str(panel.get_meta("research_branch", ""))
		var row_text := str(panel.get_meta("research_text", ""))
		var matches_site := true
		match site_filter:
			"current": matches_site = row_site == "common" or row_site == active_site
			"common": matches_site = row_site == "common"
			"all": matches_site = true
			_: matches_site = row_site == site_filter
		var matches := matches_site and (branch_filter == "all" or row_branch == branch_filter) and (normalized.is_empty() or row_text.contains(normalized))
		panel.visible = matches
		if matches:
			visible_count += 1
	return visible_count

static func _research_level(profile: Dictionary, id: String) -> int:
	var game := _game(profile)
	for key in ["research", "research_levels", "research_ranks"]:
		var levels: Variant = game.get(key, {})
		if levels is Dictionary and levels.has(id):
			var value: Variant = levels[id]
			return int(value.get("level", value.get("rank", 0))) if value is Dictionary else int(value)
	return 0

static func _render_mastery(screen: Control, content: VBoxContainer, profile: Dictionary) -> void:
	var site := _site(screen)
	var heading := _card(screen, content, "Мастерство · постоянные навыки", "24 канонических навыка по трём участкам. Навыки требуют исторический рубеж и очки мастерства; сбросы добычи не должны стирать их.")
	var sites := HBoxContainer.new()
	heading.add_child(sites)
	for id in GameMath.SITES:
		var button := HorizonUI.button(sites, id.to_upper(), "MasterySite" + id, func(): screen.call("go", "mastery", id), id == site)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var shown := 0
	for record in _catalog("mastery"):
		if str(record.get("site", "")) != site:
			continue
		shown += 1
		var id := str(record.get("id", ""))
		var status_value: Variant = _model_call("mastery_status", [profile, id])
		var status: Dictionary = status_value if status_value is Dictionary else _fallback_mastery_status(profile, record)
		var rank := int(_first_value(status, ["rank", "level", "current_rank"], 0))
		var max_rank := int(record.get("max_rank", 1))
		var items := _card(screen, content, "%s  ·  %s" % [id, str(record.get("name", "Навык"))], "Исторический рубеж: %s  ·  ранг %d/%d" % [str(record.get("milestone", "—")), rank, max_rank])
		HorizonUI.label(items, "Стоимость: %s очк. мастерства" % str(record.get("cost_mastery_points", "—")), 13, HorizonUI.GOLD)
		HorizonUI.label(items, str(record.get("effect", "")), 14)
		var available := bool(_first_value(status, ["can_unlock", "available", "can_buy"], false))
		var reason := _status_reason(status, "Достигните исторического рубежа и накопите очки мастерства.")
		if rank >= max_rank:
			reason = "Максимальный ранг уже открыт."
		_button(screen, items, "Открыть навык" if rank < max_rank else "Навык открыт", "mastery_unlock", {"id":id}, "" if available and rank < max_rank else reason)
	HorizonUI.notice(content, "Показано навыков: %d/24. Престиж не требуется там, где это не указано в каноне." % shown)

static func _fallback_mastery_status(profile: Dictionary, record: Dictionary) -> Dictionary:
	var id := str(record.get("id", ""))
	var game := _game(profile)
	var rank := 0
	for key in ["mastery", "mastery_ranks", "mastery_skills"]:
		var ranks: Variant = game.get(key, {})
		if ranks is Dictionary and ranks.has(id):
			var value: Variant = ranks[id]
			rank = int(value.get("rank", value.get("level", 0))) if value is Dictionary else int(value)
			break
	var points := int(game.get("mastery_points", profile.get("mastery_points", 0)))
	var milestone := str(record.get("milestone", ""))
	var parts := milestone.split("_")
	var required_peak := int(parts[3]) if parts.size() >= 4 and parts[3].is_valid_int() else 0
	var site := str(record.get("site", "fe"))
	var site_state := GameMath.site(profile, site)
	var peak := int(site_state.get("peak", 0))
	if site == "fe":
		peak = maxi(peak, int(profile.get("local", {}).get("lifetime_peak", 0)))
	var cost := int(record.get("cost_mastery_points", 0))
	var milestone_reached := required_peak > 0 and peak >= required_peak
	var can_unlock := rank < int(record.get("max_rank", 1)) and milestone_reached and points >= cost
	var reason := ""
	if not milestone_reached:
		reason = "Нужен исторический максимум %d; сейчас %d." % [required_peak, peak]
	elif points < cost:
		reason = "Нужно очков мастерства: %d; доступно: %d." % [cost, points]
	return {"rank":rank, "can_unlock":can_unlock, "reason":reason}

static func _render_story(screen: Control, content: VBoxContainer, profile: Dictionary) -> void:
	var records := _dialogue_records()
	var available_value: Variant = _model_call("available_story", [profile])
	var available_id := _story_available_id(available_value)
	var available_by_id: Dictionary = {}
	if available_value is Array:
		for entry in available_value:
			if entry is Dictionary:
				available_by_id[str(entry.get("id", ""))] = entry
	var state := _tab_state(screen, "story")
	var selected := str(state.get("story_id", available_id if not available_id.is_empty() else "A01"))
	var ids: Array = []
	for record in records:
		ids.append(str(record.get("id", "")))
	if not ids.has(selected) and not ids.is_empty():
		selected = str(ids[0])
	var picker_card := _card(screen, content, "Сюжет Земли · A01–A20", "Просмотр архива не завершает сцену, не открывает условие и не выдаёт награду. Полный канонический текст сохранён.")
	var picker := OptionButton.new()
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var selected_index := 0
	for index in range(records.size()):
		var record: Dictionary = records[index]
		var id := str(record.get("id", ""))
		var complete := _story_completed(profile, id)
		var stage: Dictionary = available_by_id.get(id, {})
		var marker := "✓" if complete else ("●" if bool(stage.get("requirements_met", false)) else ("○" if not stage.is_empty() else "·"))
		picker.add_item("%s  %s · %s" % [marker, id, str(record.get("title", "Сцена"))])
		picker.set_item_metadata(index, id)
		if id == selected:
			selected_index = index
	picker.select(selected_index)
	picker_card.add_child(picker)
	picker.item_selected.connect(func(index: int):
		_set_state(screen, "story", "story_id", str(picker.get_item_metadata(index)))
		screen.call("refresh"))
	var selected_record: Dictionary = {}
	for record in records:
		if str(record.get("id", "")) == selected:
			selected_record = record
			break
	if selected_record.is_empty():
		HorizonUI.notice(content, "Канонические диалоги не загружены.")
		return
	var id := str(selected_record.get("id", ""))
	var is_complete := _story_completed(profile, id)
	var current_stage: Dictionary = available_by_id.get(id, {})
	var can_open := not current_stage.is_empty() and not is_complete
	var progression: Dictionary = _game(profile).get("progression", {})
	var read_flags: Variant = progression.get("story_read", {})
	var is_read := bool(read_flags.get(id, false)) if read_flags is Dictionary else false
	var requirements_met := bool(current_stage.get("requirements_met", false))
	var blockers: Variant = current_stage.get("blockers", [])
	var state_line := "Сцена завершена" if is_complete else ("Открыта для прохождения" if can_open else "Архив · предыдущая глава ещё не завершена")
	var scene := _card(screen, content, "%s · %s" % [id, str(selected_record.get("title", "Сцена"))], state_line)
	HorizonUI.label(scene, "Предусловие: %s\nТриггер: %s" % [str(selected_record.get("prerequisite_story", "—")) if not str(selected_record.get("prerequisite_story", "")).is_empty() else "нет", str(selected_record.get("trigger", "—"))], 13, HorizonUI.MUTED)
	var lines: Variant = selected_record.get("lines", selected_record.get("dialogue", []))
	if lines is Array:
		for line in lines:
			if line is Dictionary:
				var speaker := str(line.get("speaker", ""))
				var bubble := _card(screen, scene, speaker, str(line.get("text", "")))
				bubble.add_theme_constant_override("separation", 2)
	HorizonUI.label(scene, "Ожидаемое открытие только после игрового завершения: %s" % str(selected_record.get("reward_unlock", "—")), 13, HorizonUI.GOLD)
	if can_open and not is_read:
		_button(screen, scene, "Открыть диалог", "story_open", {"id":id})
		_button(screen, scene, "Пропустить чтение (без награды)", "story_open", {"id":id})
	elif can_open and is_read:
		var reason := "" if requirements_met else "; ".join(blockers) if blockers is Array and not blockers.is_empty() else "Сначала выполните условия главы."
		_button(screen, scene, "Завершить сцену", "story_complete", {"id":id}, reason)
		if not requirements_met:
			HorizonUI.notice(scene, "Сцена открыта, но завершение и любое сюжетное открытие требуют: %s" % reason)
	elif not is_complete:
		HorizonUI.notice(scene, "Архивный просмотр не меняет сюжет. Глава откроется после завершения предыдущей сцены.")

static func _dialogue_records() -> Array:
	if not _dialogues.is_empty():
		return _dialogues
	var value: Variant = _model_call("story_records", [])
	if value is Array and not value.is_empty():
		_dialogues = value
		return _dialogues
	var file := FileAccess.open(STORY_PATH, FileAccess.READ)
	if file == null:
		return []
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Array:
		_dialogues = parsed
	return _dialogues

static func _story_available_id(value: Variant) -> String:
	if value is String:
		return value
	if value is Dictionary:
		for key in ["id", "story_id", "current_id", "available_id"]:
			if value.has(key):
				return str(value[key])
		for key in ["available", "available_stories", "ids"]:
			if value.get(key) is Array and not value[key].is_empty():
				var item: Variant = value[key][0]
				return str(item.get("id", "")) if item is Dictionary else str(item)
		return ""
	if value is Array and not value.is_empty():
		var item: Variant = value[0]
		return str(item.get("id", "")) if item is Dictionary else str(item)
	return ""

static func _story_completed(profile: Dictionary, id: String) -> bool:
	var game := _game(profile)
	var progression: Variant = game.get("progression", {})
	var done: Variant = progression.get("story_done", {}) if progression is Dictionary else {}
	return bool(done.get(id, false)) if done is Dictionary else false

static func _story_status_for(available: Variant, id: String) -> Dictionary:
	if available is Array:
		for item in available:
			if item is Dictionary and str(item.get("id", "")) == id:
				return item
	return {}

static func _global_progress_preserved(preview: Dictionary) -> bool:
	var preserved: Variant = preview.get("preserved_fields", [])
	if not preserved is Array:
		return false
	for field in ["money_cents", "inventory", "research", "mastery", "equipment", "specialists", "other_sites"]:
		if not preserved.has(field):
			return false
	return true

static func _render_contracts(screen: Control, content: VBoxContainer, profile: Dictionary) -> void:
	var records := _progression_records(profile, ["contract_offers", "contracts", "trade_contracts"])
	var root := _card(screen, content, "Контракты", "Каждый этап отдельный и одноразовый: принять → зарезервировать → отгрузить → получить выплату. Повторное получение не начисляется.")
	if records.is_empty():
		HorizonUI.notice(root, "Активных контрактов пока нет. Панель показывает только предложения игрового состояния; тестовые контракты не создаются.")
		return
	for record in records:
		var id := str(_first_value(record, ["id", "contract_id"], ""))
		var title := str(_first_value(record, ["title", "name"], id))
		var items := _card(screen, content, title, "%s · %s" % [id, str(record.get("status", "предложение"))])
		var terms := []
		for key in ["resource", "amount", "target", "reward", "reward_cents", "deadline_seconds", "remaining_seconds"]:
			if record.has(key):
				terms.append("%s: %s" % [key, _format_value(record[key])])
		HorizonUI.label(items, "\n".join(terms) if not terms.is_empty() else "Условия: %s" % JSON.stringify(record), 13)
		var status := str(record.get("status", "offer"))
		if bool(record.get("claimed", false)) or status in ["claimed", "complete", "completed"]:
			HorizonUI.notice(items, "Контракт уже получен; повторная выплата недоступна.")
		elif status in ["offer", "available", "new", ""]:
			_button(screen, items, "Принять", "contract_accept", {"id":id})
		elif status in ["accepted", "active"]:
			_button(screen, items, "Зарезервировать материалы", "contract_reserve", {"id":id})
		elif status in ["reserved", "ready_to_ship"]:
			_button(screen, items, "Отгрузить резерв", "contract_ship", {"id":id})
		elif status in ["shipped", "delivered", "ready_to_claim"]:
			_button(screen, items, "Получить выплату", "contract_claim", {"id":id})
		else:
			HorizonUI.notice(items, "Этап: %s" % status)

static func _progression_records(profile: Dictionary, keys: Array) -> Array:
	var game := _game(profile)
	for key in keys:
		var value: Variant = game.get(key, [])
		if value is Array:
			return value
		if value is Dictionary:
			var rows: Array = []
			for id in value:
				var row: Variant = value[id]
				if row is Dictionary:
					var copy: Dictionary = row.duplicate(true)
					copy["id"] = str(copy.get("id", id))
					rows.append(copy)
			return rows
	return []

static func _render_geology(screen: Control, content: VBoxContainer, profile: Dictionary) -> void:
	var site := _site(screen)
	var game := _game(profile)
	var data: Variant = game.get("geology", game.get("geology_reports", {}))
	var reports: Array = []
	if data is Array:
		reports = data
	elif data is Dictionary:
		var candidate: Variant = data.get("reports", data.get("active", []))
		if candidate is Array:
			reports = candidate
		elif candidate is Dictionary:
			for id in candidate:
				var row: Variant = candidate[id]
				if row is Dictionary:
					var copy: Dictionary = row.duplicate(true)
					copy["id"] = str(copy.get("id", id))
					reports.append(copy)
	var overview := _card(screen, content, "Геология · гарантированные отчёты", "Отчёты выдаются по расписанию модели, без случайных шансов. Срок и результат читаются из сохранённого состояния.")
	HorizonUI.label(overview, "Участок: %s" % SITE_NAMES[site], 13, HorizonUI.MUTED)
	var site_reports := 0
	for report in reports:
		if not report is Dictionary or (report.has("site") and str(report["site"]) != site):
			continue
		site_reports += 1
		var id := str(_first_value(report, ["id", "report_id"], "Отчёт"))
		var status := str(report.get("status", "в работе"))
		var seconds := int(_first_value(report, ["remaining_seconds", "seconds_left", "remaining", "timer_seconds"], -1))
		var description := "Статус: %s" % status
		if seconds >= 0:
			description += " · %s" % _duration(seconds)
		var card := _card(screen, content, id, description)
		for key in ["result", "sample", "site", "started_at", "ready_at"]:
			if report.has(key):
				HorizonUI.label(card, "%s: %s" % [key, _format_value(report[key])], 13)
		if status in ["ready", "complete", "completed", "claimable"] or (seconds == 0 and status != "claimed"):
			_button(screen, card, "Забрать отчёт", "geology_claim", {"id":id})
		elif status in ["claimed", "collected"]:
			HorizonUI.notice(card, "Отчёт уже получен и остаётся в архиве.")
	if site_reports == 0:
		HorizonUI.notice(overview, "Для этого участка активного отчёта нет.")
	var active := false
	if data is Dictionary:
		var active_value: Variant = data.get("active_report", data.get("active", null))
		active = active_value is Dictionary and str(active_value.get("status", "")) in ["active", "running", "in_progress"]
	var reason := ""
	if not GameMath.unlocked(profile, site):
		reason = "Сначала откройте участок на карте Земли."
	elif active:
		reason = "Сначала завершите текущий геоотчёт."
	_button(screen, overview, "Запустить гарантированный геоотчёт", "geology_start", {"site":site}, reason)

static func _duration(seconds: int) -> String:
	var safe := maxi(seconds, 0)
	return "%02d:%02d:%02d" % [safe / 3600, (safe % 3600) / 60, safe % 60]

static func _render_buildings(screen: Control, content: VBoxContainer, profile: Dictionary) -> void:
	var site := _site(screen)
	var records := _progression_records(profile, ["building_projects", "projects", "buildings"])
	var intro := _card(screen, content, "Строительство · %s" % SITE_NAMES[site], "Здесь отображаются только проекты из текущего профиля; требования, сроки и стройматериалы не подменяются демонстрационными данными.")
	if not GameMath.unlocked(profile, site):
		HorizonUI.notice(intro, "Участок закрыт. Посмотрите реальные условия на карте Земли.")
		return
	var shown := 0
	for project in records:
		if not project is Dictionary or (project.has("site") and str(project["site"]) != site):
			continue
		shown += 1
		var id := str(_first_value(project, ["id", "project_id", "building_id"], ""))
		var name := str(_first_value(project, ["name", "title"], id))
		var status := str(project.get("status", "locked"))
		var card := _card(screen, content, name, "Статус: %s" % status)
		for key in ["description", "cost", "materials", "duration_seconds", "remaining_seconds", "reason"]:
			if project.has(key):
				HorizonUI.label(card, "%s: %s" % [key, _format_value(project[key])], 13)
		if status in ["available", "ready_to_build"]:
			_button(screen, card, "Начать строительство", "building_start", {"id":id, "site":site})
		elif status in ["ready", "complete", "completed"]:
			_button(screen, card, "Завершить проект", "building_complete", {"id":id, "site":site})
		elif status in ["building", "in_progress"]:
			HorizonUI.notice(card, "Строительство идёт по таймеру; завершение откроется после срока.")
		else:
			HorizonUI.notice(card, str(project.get("reason", "Условия строительства пока не выполнены.")))
	if shown == 0:
		HorizonUI.notice(intro, "Нет доступных строительных проектов в сохранённом состоянии.")

static func _render_expansion(screen: Control, content: VBoxContainer, profile: Dictionary) -> void:
	var site := _site(screen)
	var state := _tab_state(screen, "expansion")
	var preview_value: Variant = _model_call("expansion_preview", [profile, site])
	var preview: Dictionary = preview_value if preview_value is Dictionary else {}
	var card := _card(screen, content, "Экспансия · %s" % SITE_NAMES[site], "Сначала проверяется полный расчёт последствий. До явного подтверждения никаких данных или ресурсов не меняется.")
	var selector := HBoxContainer.new()
	card.add_child(selector)
	for id in GameMath.SITES:
		var b := HorizonUI.button(selector, id.to_upper(), "ExpansionSite" + id, func(): screen.call("go", "expansion", id), id == site)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if preview.is_empty():
		HorizonUI.notice(card, "Предварительный расчёт недоступен; экспансия заблокирована.")
	else:
		for key in ["available", "can_expand", "reason", "cost", "cost_cents", "cost_shards", "resets", "reset", "preserves", "preserved", "preserves_global", "site_changes", "duration_seconds"]:
			if preview.has(key):
				HorizonUI.label(card, "%s: %s" % [key, _format_value(preview[key])], 13, HorizonUI.MUTED if key == "reason" else Color("e4e9ec"))
		var can_expand := bool(_first_value(preview, ["can_expand", "available", "eligible"], false))
		var reason := _status_reason(preview, "Условия экспансии не выполнены.")
		if not bool(state.get("confirm_phase", false)):
			var confirm_button := HorizonUI.button(card, "Перейти к подтверждению", "ExpansionReview", func():
				_set_state(screen, "expansion", "confirm_phase", true)
				screen.call("refresh"))
			confirm_button.disabled = not can_expand
			confirm_button.tooltip_text = "" if can_expand else reason
		else:
			var confirmation := CheckBox.new()
			confirmation.text = "Подтверждаю только локальные изменения участка; глобальный прогресс и все перечисленные сохранённые данные остаются без изменений."
			confirmation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			card.add_child(confirmation)
			var apply := _button(screen, card, "Подтвердить экспансию", "expansion_confirm", {"site":site}, "Сначала отметьте явное подтверждение.")
			apply.disabled = true
			confirmation.toggled.connect(func(checked: bool):
				apply.disabled = not checked or not can_expand
				apply.tooltip_text = "" if checked and can_expand else "Сначала отметьте явное подтверждение." if not checked else reason)
			var cancel := HorizonUI.button(card, "Отмена", "CancelExpansion", func():
				_set_state(screen, "expansion", "confirm_phase", false)
				screen.call("refresh"))
			cancel.custom_minimum_size.y = 44
			if not bool(_first_value(preview, ["preserves_global"], false)):
				apply.disabled = true
				apply.tooltip_text = "Нет подтверждённого расчёта о сохранении глобального прогресса."
				HorizonUI.notice(card, "Подтверждение недоступно, пока модель не гарантирует сохранение глобального состояния.")
	var offline := _card(screen, content, "Офлайн-лимит", "Базовый лимит — 4 часа. По канону 12 часов стоят 1500 осколков, полный лимит 24 часа — 2950 осколков.")
	var game := _game(profile)
	var offline_level := int(game.get("offline_level", 0))
	var cap_seconds := mini(14400 + 1440 * offline_level, 86400)
	HorizonUI.label(offline, "Текущий расчётный предел: %s" % _duration(cap_seconds), 14, HorizonUI.GOLD)
	if cap_seconds < 43200:
		_button(screen, offline, "Увеличить предел до 12 ч · 1500 ◇", "offline_upgrade", {"target_hours":12})
	elif cap_seconds < 86400:
		_button(screen, offline, "Увеличить предел до 24 ч · 2950 ◇", "offline_upgrade", {"target_hours":24})
	else:
		HorizonUI.notice(offline, "Достигнут канонический максимум 24 часа.")

static func _render_network(screen: Control, content: VBoxContainer, profile: Dictionary) -> void:
	var game := _game(profile)
	var state: Variant = game.get("network", game.get("industrial_network", {}))
	var network: Dictionary = state if state is Dictionary else {}
	var card := _card(screen, content, "Промышленная сеть", "Выберите режим распределения. Автопродажа включается отдельно и по умолчанию отключена.")
	var current := str(network.get("mode", "balanced"))
	var modes := HBoxContainer.new()
	card.add_child(modes)
	var captions := {"balanced":"Баланс", "income":"Доход", "build":"Строительство"}
	for mode in NETWORK_MODES:
		var reason := "" if GameMath.unlocked(profile, _site(screen)) else "Сначала откройте участок."
		var button := _button(screen, modes, str(captions[mode]) + (" ✓" if current == mode else ""), "network_mode", {"mode":mode}, reason)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var auto_sell := bool(network.get("auto_sell", network.get("autosell", false)))
	HorizonUI.label(card, "Автопродажа: %s" % ("включена" if auto_sell else "выключена"), 14, HorizonUI.GOLD)
	_button(screen, card, "Отключить автопродажу" if auto_sell else "Явно включить автопродажу", "network_autosell", {"enabled":not auto_sell})
	var budget := int(network.get("autobuy_budget_cents", network.get("auto_buy_budget", 0)))
	var autobuy := bool(network.get("auto_buy", false))
	HorizonUI.notice(card, "Автопокупка %s. Без отдельного положительного бюджета закупки не выполняются." % ("включена" if autobuy and budget > 0 else "выключена"))
	if budget > 0:
		HorizonUI.label(card, "Выделенный бюджет автопокупки: %s Г" % _money(budget), 13, HorizonUI.MUTED)
	var status: Variant = network.get("status", {})
	if status is Dictionary:
		for key in ["income_cents", "build_queue", "last_allocation", "reason"]:
			if status.has(key):
				HorizonUI.label(card, "%s: %s" % [key, _format_value(status[key])], 13)

static func _money(cents: int) -> String:
	return "%0.2f" % (float(cents) / 100.0)

static func _render_map(screen: Control, content: VBoxContainer, profile: Dictionary) -> void:
	var intro := _card(screen, content, "Земля · три участка", "Открытия следуют сюжетным и производственным условиям. Четвёртого участка и престиж-сброса на карте нет.")
	var sites := ["fe", "pd", "ir"]
	for id in sites:
		var unlocked := GameMath.unlocked(profile, id)
		var detail := "Открыт и доступен." if unlocked else _site_unlock_reason(id)
		var card := _card(screen, content, SITE_NAMES[id], detail)
		if id == "fe":
			HorizonUI.label(card, "Стартовый участок · исходный производственный контур.", 13, HorizonUI.MUTED)
		elif id == "pd":
			HorizonUI.label(card, "Открытие: A06, исторический Fe-пик 350, фактическое производство стали и гарантированная геопривязка. Экспансия для открытия не нужна.", 13, HorizonUI.MUTED)
		else:
			HorizonUI.label(card, "Открытие: A13, первый Pd-катализатор, два геоотчёта и завершённая «Глубинная станция».", 13, HorizonUI.MUTED)
		var button := HorizonUI.button(card, "Перейти на участок" if unlocked else "Условия открытия", "OpenSite" + id, func():
			if unlocked:
				screen.call("go", "mine", id)
			else:
				screen.call("go", "story" if id == "pd" else "geology", id))
		button.disabled = not unlocked
		button.tooltip_text = "" if unlocked else detail
		if id == _site(screen):
			HorizonUI.notice(card, "Текущий участок")
	HorizonUI.notice(intro, "Карта показывает только Fe, Pd и Ir. Экспансия участка и глобальные сюжетные открытия — разные механики.")

static func _site_unlock_reason(site: String) -> String:
	if site == "pd":
		return "Палладий закрыт: завершите A06, достигните Fe lifetime peak 350, произведите сталь и получите геопривязку."
	if site == "ir":
		return "Иридий закрыт: завершите A13, произведите первый Pd-катализатор, завершите два геоотчёта и проект «Глубинная станция»."
	return "Участок закрыт."
