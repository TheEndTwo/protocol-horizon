extends RefCounted

const MODEL_PATH := "res://gameplay/ProgressionModel.gd"
const PROPOSAL_PATH := "res://data/proposals/progression.json"
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
	if _progression_script == null:
		return null
	return _progression_script.callv(method, args)

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
	var value := str(_first_value(status, ["reason", "locked_reason", "why", "message"], fallback)).strip_edges()
	return fallback if value.is_empty() else value

static func _option(parent: Node, options: Array, selected: String) -> OptionButton:
	var picker := HorizonUI.option_button()
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
		var available := bool(_first_value(status, ["can_research", "can_buy", "available"], false))
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
		elif not available and bool(status.get("milestone_reached", false)):
			var progression: Dictionary = _game(profile).get("progression", {})
			var points := int(progression.get("mastery_points", 0))
			var cost := int(_first_value(status, ["cost", "cost_mastery_points"], record.get("cost_mastery_points", 0)))
			if points < cost:
				reason = "Нужно очков мастерства: %d; доступно: %d." % [cost, points]
		_button(screen, items, "Открыть навык" if rank < max_rank else "Навык открыт", "mastery_buy", {"id":id}, "" if available and rank < max_rank else reason)
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
	var saved_story: Dictionary = _game(profile).get("progression",{}).get("story",{})
	var selected := str(state.get("story_id",saved_story.get("ui_selected", available_id if not available_id.is_empty() else "A01")))
	var ids: Array = []
	for record in records:
		ids.append(str(record.get("id", "")))
	if not ids.has(selected) and not ids.is_empty():
		selected = str(ids[0])
	var picker_card := _card(screen, content, "Сюжет Земли · A01–A20", "Просмотр архива не завершает сцену, не открывает условие и не выдаёт награду. Полный канонический текст сохранён.")
	var picker := HorizonUI.option_button()
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
	var lines: Variant = selected_record.get("lines", [])
	if lines is Array and not lines.is_empty() and (is_read or is_complete):
		var cursor := clampi(int(saved_story.get("read_cursors",{}).get(id,0)),0,lines.size()-1)
		var line: Dictionary = lines[cursor]
		_card(screen,scene,str(line.get("speaker","")),str(line.get("text","")))
		HorizonUI.label(scene,"Реплика %d / %d · позиция сохраняется" % [cursor+1,lines.size()],13,HorizonUI.MUTED)
		var controls := HBoxContainer.new()
		scene.add_child(controls)
		var story_id := id
		var previous := HorizonUI.button(controls,"‹","StoryPrevious",func():
			if GameSession.set_story_cursor(story_id,cursor-1) == OK:
				screen.call("refresh"))
		previous.disabled = cursor <= 0
		var next := HorizonUI.button(controls,"Далее","StoryNext",func():
			if GameSession.set_story_cursor(story_id,cursor+1) == OK:
				AudioService.play_effect("dialogue_message")
				screen.call("refresh"))
		next.disabled = cursor >= lines.size()-1
		HorizonUI.button(scene,"Пропустить чтение","StorySkip",func():
			if GameSession.set_story_cursor(story_id,lines.size()-1) == OK:
				screen.call("refresh"))
	else:
		HorizonUI.notice(scene,"Текст появится после открытия сцены по игровым условиям. Непройденные главы не раскрывают будущие диалоги.")
	HorizonUI.label(scene, "Ожидаемое открытие только после игрового завершения: %s" % str(selected_record.get("reward_unlock", "—")), 13, HorizonUI.GOLD)
	if can_open and not is_read:
		var open_reason := "" if requirements_met else "; ".join(blockers) if blockers is Array else "Выполните условия главы"
		_button(screen, scene, "Открыть диалог", "story_open", {"id":id},open_reason)
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
	_dialogues = _catalog("dialogue")
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
		for candidate in value:
			if candidate is Dictionary and bool(candidate.get("requirements_met",false)):
				return str(candidate.get("id",""))
		var item: Variant = value[0]
		return str(item.get("id", "")) if item is Dictionary else str(item)
	return ""

static func _story_completed(profile: Dictionary, id: String) -> bool:
	var game := _game(profile)
	var progression: Variant = game.get("progression", {})
	var done: Variant = progression.get("story_done", {}) if progression is Dictionary else {}
	return bool(done.get(id, false)) if done is Dictionary else false

static func _global_progress_preserved(preview: Dictionary) -> bool:
	var preserved: Variant = preview.get("preserved_fields", [])
	if not preserved is Array:
		return false
	for field in ["money_cents", "inventory", "sites", "stories", "research", "mastery", "equipment", "specialists", "other_sites"]:
		if not preserved.has(field):
			return false
	return true

static func _render_contracts(screen: Control, content: VBoxContainer, profile: Dictionary) -> void:
	var offers := _proposal_section("contracts")
	var progression: Dictionary = _game(profile).get("progression", {})
	var contracts: Dictionary = progression.get("contracts", {})
	var active: Dictionary = contracts.get("active", {})
	var completed: Dictionary = contracts.get("completed", {})
	var root := _card(screen, content, "Контракты", "Однократная выплата проходит только после отгрузки. Принятие резервирует материалы в модели; отгрузка и получение выплаты — отдельные действия.")
	if offers.is_empty():
		HorizonUI.notice(root, "Каталог контрактов не загружен.")
		return
	for id_value in offers:
		var id := str(id_value)
		var spec: Dictionary = offers[id]
		var items := _card(screen, content, id.replace("_", " ").capitalize(), "%s · %s" % [str(spec.get("type", "контракт")), "повторяемый" if bool(spec.get("repeatable", false)) else "одноразовый"])
		HorizonUI.label(items, "Требуется: %s\nНаграда: %s" % [JSON.stringify(spec.get("items", {})), JSON.stringify(spec.get("reward", {}))], 13)
		var order_id := ""
		var order: Dictionary = {}
		for key in active:
			var candidate: Variant = active[key]
			if candidate is Dictionary and str(candidate.get("contract_id", "")) == id:
				order_id = str(key)
				order = candidate
				break
		if not order.is_empty():
			var status := str(order.get("status", "accepted"))
			var reservation_id := str(order.get("reservation_id", ""))
			HorizonUI.label(items, "Заказ %s · этап: %s" % [order_id, status], 13, HorizonUI.GOLD)
			HorizonUI.label(items, "Резерв создан при принятии%s: %s" % [" (%s)" % reservation_id if not reservation_id.is_empty() else "", JSON.stringify(order.get("items", {}))], 13)
			if status == "shipped":
				_button(screen, items, "Получить выплату · один раз", "contract_claim", {"order_id":order_id})
			elif status in ["accepted", "reserved"]:
				_button(screen, items, "Отгрузить заказ", "contract_ship", {"order_id":order_id})
			else:
				HorizonUI.notice(items, "Заказ уже закрыт; повторное получение недоступно.")
			continue
		if not bool(spec.get("repeatable", false)) and bool(completed.get(id, false)):
			HorizonUI.notice(items, "Одноразовый контракт уже закрыт.")
			continue
		var requirement := str(spec.get("requires", ""))
		var reason := ""
		if requirement == "pd_unlocked" and not GameMath.unlocked(profile, "pd"):
			reason = "Сначала откройте П-7."
		elif requirement == "ir_unlocked" and not GameMath.unlocked(profile, "ir"):
			reason = "Сначала откройте И-9."
		elif requirement.begins_with("story:") and not _story_completed(profile, requirement.trim_prefix("story:")):
			reason = "Сначала завершите %s." % requirement.trim_prefix("story:")
		if reason.is_empty():
			for resource in spec.get("items", {}):
				var amount := int(spec["items"][resource])
				if GameMath.free_amount(profile, str(resource)) < amount:
					reason = "Нужно свободного ресурса: %s × %d." % [str(resource), amount]
					break
		_button(screen, items, "Принять · зарезервировать материалы", "contract_accept", {"id":id}, reason)

static func _render_geology(screen: Control, content: VBoxContainer, profile: Dictionary) -> void:
	var site := _site(screen)
	var progression: Dictionary = _game(profile).get("progression", {})
	var geology: Dictionary = progression.get("geology", {})
	var active: Dictionary = geology.get("active", {})
	var overview := _card(screen, content, "Геология · %s" % SITE_NAMES[site], "Экспедиции имеют фиксированный срок, стоимость и набор результата. По таймеру отчёт и награда записываются автоматически.")
	var effect_value: Variant = _model_call("geology_effects", [profile, site])
	var effects: Dictionary = effect_value if effect_value is Dictionary else {}
	var effects_card := _card(screen, content, "Точность и качество геоданных", "Исследования улучшают измерения и отчётность; они не добавляют броски редкости или физические образцы.")
	if site == "fe":
		HorizonUI.label(effects_card, "Точность сигнатур до сканирования · G02: +%.1f%%" % [100.0 * float(effects.get("signature_precision_bonus", 0.0))], 13)
		HorizonUI.label(effects_card, "Активные данные добычи · D17: %.1f%% качества из %.0f ручных ед." % [100.0 * float(effects.get("geology_data_quality", 0.0)), float(effects.get("active_mining_units", 0.0))], 13)
		HorizonUI.label(effects_card, "Пригодная доля образцов · G04: %.1f%% (+%.1f п.п.)" % [100.0 * float(effects.get("usable_sample_share", 0.0)), 100.0 * float(effects.get("usable_sample_bonus", 0.0))], 13)
	HorizonUI.label(effects_card, "Качество наград · G09: +%.1f%%; состав и количество фиксированы." % [100.0 * float(effects.get("reward_quality_bonus", 0.0))], 13)
	if site == "ir":
		HorizonUI.label(effects_card, "Точность редкой метки в deep_signal · G18: +%.1f%%; шанс мифического кейса не меняется." % [100.0 * float(effects.get("deep_mark_precision_bonus", 0.0))], 13)
	var site_picker := HBoxContainer.new()
	overview.add_child(site_picker)
	for id in GameMath.SITES:
		var button := HorizonUI.button(site_picker, id.to_upper(), "GeologySite" + id, func(): screen.call("go", "geology", id), id == site)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if not active.is_empty():
		var active_card := _card(screen, content, "Текущая экспедиция · %s" % str(active.get("id", "")), "Участок: %s" % str(active.get("site", "")))
		_live_label(screen, active_card, func():
			var current_profile: Dictionary = screen.call("profile")
			var current_geology: Dictionary = _game(current_profile).get("progression", {}).get("geology", {})
			var current: Dictionary = current_geology.get("active", {})
			if not current.is_empty():
				return "До гарантированного отчёта: %s" % _duration(int(ceil(float(current.get("remaining_seconds", 0.0)))))
			var current_reports: Array = current_geology.get("reports", [])
			for index in range(current_reports.size() - 1, -1, -1):
				var report: Dictionary = current_reports[index]
				if str(report.get("site", "")) == str(active.get("site", "")):
					return "Гарантированный отчёт %s получен · %s" % [str(report.get("id", "")), JSON.stringify(report.get("tags", []))]
			return "Экспедиция завершена; отчёт появится в архиве.")
	for report in geology.get("reports", []):
		if not report is Dictionary or str(report.get("site", "")) != site:
			continue
		var report_card := _card(screen, content, str(report.get("id", "Геоотчёт")), "Экспедиция: %s · результат гарантирован" % str(report.get("expedition", "")))
		HorizonUI.label(report_card, "Находки: %s" % JSON.stringify(report.get("tags", [])), 13, HorizonUI.GOLD)
		var report_types := PackedStringArray()
		for report_type in report.get("identified_types", []):
			report_types.append(str(report_type))
		HorizonUI.label(report_card, "Типы сигнатур: %s · точность G02 +%.1f%%" % [", ".join(report_types), 100.0 * float(report.get("signature_precision_bonus", 0.0))], 13)
		HorizonUI.label(report_card, "Активная добыча: %.0f ед. · качество данных %.1f%% · пригодная доля %.1f%%" % [float(report.get("active_mining_units", 0.0)), 100.0 * float(report.get("geology_data_quality", 0.0)), 100.0 * float(report.get("usable_sample_share", 0.0))], 13)
		HorizonUI.label(report_card, "Качество награды G09 +%.1f%% · фиксированные ОИ/осколки" % [100.0 * float(report.get("reward_quality_bonus", 0.0))], 13)
		if site == "ir" and str(report.get("expedition", "")) == "deep_signal":
			HorizonUI.label(report_card, "Точность редкой глубинной геометки G18 +%.1f%%" % [100.0 * float(report.get("deep_mark_precision_bonus", 0.0))], 13)
	var expeditions := _proposal_section("geology_expeditions")
	for id_value in expeditions:
		var id := str(id_value)
		var spec: Dictionary = expeditions[id]
		if str(spec.get("site", "fe")) != site:
			continue
		var cost := int(spec.get("cost_cents", 0))
		var seconds := int(spec.get("duration_seconds", 0))
		var card := _card(screen, content, id.replace("_", " ").capitalize(), "Стоимость: %s Г · срок: %s" % [_money(cost), _duration(seconds)])
		HorizonUI.label(card, "После завершения: %d ОИ и %d осколков; отчётные теги задаёт модель." % [int(spec.get("reward_research_points", 0)), int(spec.get("reward_shards", 0))], 13)
		var preview_value: Variant = _model_call("geology_preview", [profile, id])
		var preview: Dictionary = preview_value if preview_value is Dictionary else {}
		var possible_types := PackedStringArray()
		for possible_type in preview.get("possible_types", []):
			possible_types.append(str(possible_type))
		HorizonUI.label(card, "До скана · возможные типы: %s · точность G02 +%.1f%%" % [", ".join(possible_types), 100.0 * float(preview.get("signature_precision_bonus", 0.0))], 13)
		HorizonUI.label(card, "Качество награды G09 +%.1f%%; фиксированные награды, без повторных бросков." % [100.0 * float(preview.get("reward_quality_bonus", 0.0))], 13)
		if id == "deep_signal":
			HorizonUI.label(card, "Точность редкой глубинной геометки G18 +%.1f%%; мифический кейс не затрагивается." % [100.0 * float(preview.get("deep_mark_precision_bonus", 0.0))], 13)
		if site == "fe":
			HorizonUI.label(card, "Пригодная доля G04: %.1f%% по реальным данным добычи; ресурсы не выдаются повторно." % [100.0 * float(preview.get("usable_sample_share", 0.0))], 13)
		var reason := ""
		if not GameMath.unlocked(profile, site):
			reason = "Сначала откройте участок на карте Земли."
		elif not active.is_empty():
			reason = "Сначала завершите текущую экспедицию."
		elif id == "deep_signal" and not bool(_model_call("_building_complete", [profile, "deep_station"])):
			reason = "Для глубокого сигнала нужна завершённая Глубинная станция."
		elif int(profile.get("money_cents", 0)) < cost:
			reason = "Недостаточно гелионов для экспедиции."
		_button(screen, card, "Начать экспедицию", "geology_start", {"id":id}, reason)

static func _duration(seconds: int) -> String:
	var safe := maxi(seconds, 0)
	return "%02d:%02d:%02d" % [floori(float(safe) / 3600.0), floori(float(safe % 3600) / 60.0), safe % 60]

static func _render_buildings(screen: Control, content: VBoxContainer, profile: Dictionary) -> void:
	var progression: Dictionary = _game(profile).get("progression", {})
	var states: Dictionary = progression.get("buildings", {})
	var definitions := _proposal_section("buildings")
	var intro := _card(screen, content, "Строительные проекты", "Стоимость, материалы, сроки и зависимости берутся из той же модели, что запускает и завершает проекты.")
	for id_value in definitions:
		var id := str(id_value)
		var spec: Dictionary = definitions[id]
		var state: Dictionary = states.get(id, {})
		var status := str(state.get("status", ""))
		var done := bool(_model_call("_building_complete", [profile, id]))
		var blocker := str(_model_call("_building_blocker", [profile, id]))
		if blocker.is_empty() and int(profile.get("money_cents", 0)) < int(spec.get("cost_cents", 0)):
			blocker = "Нужно %s Г на строительство." % _money(int(spec.get("cost_cents", 0)))
		if blocker.is_empty():
			for resource in spec.get("items", {}):
				var required := int(spec["items"][resource])
				if GameMath.free_amount(profile, str(resource)) < required:
					blocker = "Недостаточно свободного ресурса: %s × %d." % [str(resource), required]
					break
		var title := id.replace("_", " ").capitalize()
		var card := _card(screen, content, title, "Статус: %s" % ("завершён" if done else "строится" if status == "building" else "доступен" if blocker.is_empty() else "закрыт"))
		HorizonUI.label(card, "Стоимость: %s Г · материалы: %s\nСрок: %s" % [_money(int(spec.get("cost_cents", 0))), JSON.stringify(spec.get("items", {})), _duration(int(spec.get("duration_seconds", 0)))], 13)
		if done:
			HorizonUI.notice(card, "Проект завершён.")
		elif status == "building":
			_live_label(screen, card, func():
				var current_profile: Dictionary = screen.call("profile")
				var current: Dictionary = _game(current_profile).get("progression", {}).get("buildings", {}).get(id, {})
				return "До завершения: %s" % _duration(int(ceil(float(current.get("remaining_seconds", 0.0))))) if str(current.get("status", "")) == "building" else "Строительство завершено.")
		elif status == "blocked":
			HorizonUI.notice(card, str(state.get("error", "Система остановила строительство: проверьте резерв материалов.")))
			_button(screen, card, "Повторить строительство", "building_start", {"id":id}, blocker)
		else:
			_button(screen, card, "Начать строительство", "building_start", {"id":id}, blocker)

static func _render_expansion(screen: Control, content: VBoxContainer, profile: Dictionary) -> void:
	var site := _site(screen)
	var state := _tab_state(screen, "expansion")
	_render_offline_report(screen, content, profile)
	var preview_value: Variant = _model_call("expansion_preview", [profile, site])
	var preview: Dictionary = preview_value if preview_value is Dictionary else {}
	var card := _card(screen, content, "Экспансия · %s" % SITE_NAMES[site], "Сначала проверяется полный расчёт последствий. До явного подтверждения никаких данных или ресурсов не меняется.")
	var selector := HBoxContainer.new()
	card.add_child(selector)
	for id in GameMath.SITES:
		var b := HorizonUI.button(selector, id.to_upper(), "ExpansionSite" + id, func():
			_set_state(screen, "expansion", "confirm_phase", false)
			screen.call("go", "expansion", id), id == site)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if preview.is_empty():
		HorizonUI.notice(card, "Предварительный расчёт недоступен; экспансия заблокирована.")
	else:
		for key in ["average_level", "required_average", "expansions", "mined_since_expansion", "geodata_award", "reset_fields", "preserved_fields", "message"]:
			if preview.has(key):
				HorizonUI.label(card, "%s: %s" % [key, _format_value(preview[key])], 13, HorizonUI.MUTED if key == "message" else Color("e4e9ec"))
		var can_expand := bool(preview.get("eligible", false))
		var global_preserved := _global_progress_preserved(preview)
		var reason := _status_reason(preview, "Условия экспансии не выполнены.")
		if not bool(state.get("confirm_phase", false)):
			var confirm_button := HorizonUI.button(card, "Перейти к подтверждению", "ExpansionReview", func():
				_set_state(screen, "expansion", "confirm_phase", true)
				screen.call("refresh"))
			confirm_button.disabled = not can_expand or not global_preserved
			confirm_button.tooltip_text = "" if can_expand and global_preserved else reason if not can_expand else "Нет полного списка сохраняемого глобального состояния."
		else:
			var confirmation := CheckBox.new()
			confirmation.text = "Подтверждаю локальный сброс (%s). Сохраняются глобальные ресурсы, сюжет, исследования, мастерство, оборудование, специалисты и остальные участки." % _format_value(preview.get("reset_fields", []))
			confirmation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			card.add_child(confirmation)
			var apply := HorizonUI.button(card, "Подтвердить экспансию", "ExpansionApply", func():
				var result: Dictionary = screen.call("action", "progression", "expand", {"site":site})
				if bool(result.get("ok", false)):
					_set_state(screen, "expansion", "confirm_phase", false))
			apply.disabled = true
			confirmation.toggled.connect(func(checked: bool):
				apply.disabled = not checked or not can_expand or not global_preserved
				apply.tooltip_text = "" if checked and can_expand and global_preserved else "Сначала отметьте явное подтверждение." if not checked else reason)
			var cancel := HorizonUI.button(card, "Отмена", "CancelExpansion", func():
				_set_state(screen, "expansion", "confirm_phase", false)
				screen.call("refresh"))
			cancel.custom_minimum_size.y = 44
			if not global_preserved:
				apply.disabled = true
				apply.tooltip_text = "Модель не подтверждает полный список сохраняемых глобальных данных."
				HorizonUI.notice(card, "Подтверждение недоступно, пока модель не гарантирует сохранение глобального состояния.")
	var offline := _card(screen, content, "Офлайн-лимит", "База 4 часа; 20 шагов по 24 минуты дают 12 часов за 1500 осколков, 50 шагов — 24 часа за 2950.")
	var game := _game(profile)
	var offline_level := int(game.get("offline_level", 0))
	var cap_seconds := mini(14400 + 1440 * offline_level, 86400)
	HorizonUI.label(offline, "Текущий расчётный предел: %s" % _duration(cap_seconds), 14, HorizonUI.GOLD)
	HorizonUI.label(offline, "12 ч: %s · 24 ч: %s" % ["достигнуты" if offline_level >= 20 else "%d шагов / 1500 ◇" % (20 - offline_level), "достигнуты" if offline_level >= 50 else "%d шагов / 2950 ◇" % (50 - offline_level)], 13)
	if offline_level < 50:
		var next_level := offline_level + 1
		var costs: Dictionary = _proposal_section("offline").get("costs", {})
		var step_cost := int(costs.get("1-20", 75)) if next_level <= 20 else int(costs.get("21-40", 48)) if next_level <= 40 else int(costs.get("41-50", 49))
		var reason := "" if int(profile.get("shards", 0)) >= step_cost else "Для следующего 24-минутного шага нужно %d осколков." % step_cost
		_button(screen, offline, "Добавить 24 минуты · %d ◇" % step_cost, "offline_upgrade", {}, reason)
	else:
		HorizonUI.notice(offline, "Достигнут канонический максимум 24 часа.")

static func _render_offline_report(screen: Control, content: VBoxContainer, profile: Dictionary) -> void:
	var report: Dictionary = _game(profile).get("offline_report", {})
	if report.is_empty():
		return
	var seconds := maxi(0, int(report.get("seconds", 0)))
	var report_card := _card(screen, content, "Офлайн-отчёт · уже рассчитан", "Эти изменения применены один раз при загрузке профиля. Просмотр и закрытие отчёта ничего повторно не начисляют.")
	HorizonUI.label(report_card, "Время: %d ч %d мин\nИзменение гелионов: %s Г" % [floori(float(seconds) / 3600.0), floori(float(seconds % 3600) / 60.0), _signed_money(int(report.get("money_cents", 0)))], 14, HorizonUI.GOLD)
	var materials: Dictionary = report.get("materials", {})
	if materials.is_empty():
		HorizonUI.label(report_card, "Материалы: без изменений", 13, HorizonUI.MUTED)
	else:
		var changes: PackedStringArray = []
		for resource in materials:
			var amount := int(materials[resource])
			var sign := "+" if amount > 0 else "−" if amount < 0 else ""
			changes.append("%s %s × %d" % [sign, str(resource), absi(amount)])
		HorizonUI.label(report_card, "Материалы: " + ", ".join(changes), 13)
	var acknowledge := HorizonUI.button(report_card, "Понятно · закрыть отчёт", "AcknowledgeOfflineReport", func():
		GameSession.dismiss_offline()
		screen.call("refresh"))
	acknowledge.custom_minimum_size.y = 44

static func _signed_money(cents: int) -> String:
	var sign := "+" if cents > 0 else "−" if cents < 0 else ""
	return sign + _money(absi(cents))

static func _render_network(screen: Control, content: VBoxContainer, profile: Dictionary) -> void:
	var game := _game(profile)
	var state: Variant = game.get("network", {})
	var network: Dictionary = state if state is Dictionary else {}
	var card := _card(screen, content, "Промышленная сеть", "Режим и автопродажа проходят через экономическую модель. Автопродажа по умолчанию выключена.")
	var current := str(network.get("mode", "balanced"))
	var modes := HBoxContainer.new()
	card.add_child(modes)
	var captions := {"balanced":"Баланс", "income":"Доход", "build":"Строительство"}
	for mode in NETWORK_MODES:
		var button := _button_domain(screen, modes, str(captions[mode]) + (" ✓" if current == mode else ""), "economy", "network", {"mode":mode})
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var auto_sell := bool(network.get("autosell", false))
	HorizonUI.label(card, "Автопродажа: %s" % ("включена" if auto_sell else "выключена"), 14, HorizonUI.GOLD)
	_button_domain(screen, card, "Отключить автопродажу" if auto_sell else "Явно включить автопродажу", "economy", "network", {"mode":current, "autosell":not auto_sell})
	HorizonUI.notice(card, "Автопокупка не включается и не выполняется: модель не задаёт бюджета закупок.")

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
