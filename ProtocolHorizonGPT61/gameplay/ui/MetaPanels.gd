class_name MetaPanels
extends RefCounted

const META_MODEL_PATH := "res://gameplay/MetaModel.gd"
const SEASON_LEVELS := 60
const TASK_ROUTES := {
	"active_site":"mine", "trade":"trade", "geology":"geology",
	"network":"network", "research":"research",
}

static func render(screen: Control, body: VBoxContainer, tab: String) -> void:
	var profile: Dictionary = screen.call("profile")
	var projection := _model_view(profile, str(screen.get("site")), tab)
	var section := _section(projection, tab)
	match tab:
		"equipment": _equipment(screen, body, section)
		"specialists": _specialists(screen, body, section)
		"cases": _cases(screen, body, section)
		"season": _season(screen, body, section)
		"events": _events(screen, body, section)
		"shop": _shop(screen, body, section)
		_:
			HorizonUI.notice(body, "Раздел не найден.")

static func _model_view(profile: Dictionary, site: String, tab: String) -> Dictionary:
	var script: Variant = load(META_MODEL_PATH)
	if script == null or not script.has_script_method("view"):
		return {}
	var signature: Dictionary = {}
	for method in script.get_script_method_list():
		if str(method.get("name", "")) == "view":
			signature = method
			break
	var arguments: Array = []
	for index in signature.get("args", []).size():
		var name := str(signature["args"][index].get("name", "")).to_lower()
		if name.contains("tab") or name.contains("page") or name.contains("section"):
			arguments.append(tab)
		elif name.contains("site"):
			arguments.append(site)
		elif index == 0 or name.contains("profile") or name == "p" or name.contains("state"):
			arguments.append(profile)
		elif index == 1:
			arguments.append(site)
		else:
			arguments.append(tab)
	var value: Variant = script.callv("view", arguments)
	return value if value is Dictionary else {}

static func _section(projection: Dictionary, tab: String) -> Dictionary:
	for key in [tab, tab + "_view", "sections", "tabs"]:
		var value: Variant = projection.get(key, {})
		if value is Dictionary and value.has(tab) and value[tab] is Dictionary:
			return value[tab]
		if key in [tab, tab + "_view"] and value is Dictionary:
			return value
	if projection.has("items") or projection.has("records") or projection.has("actions"):
		return projection
	return projection

static func _equipment(screen: Control, body: VBoxContainer, section: Dictionary) -> void:
	HorizonUI.label(body, "Снаряжение из открытых кейсов · предметы и назначения сохраняются отдельно по участкам.", 14)
	if section.is_empty():
		HorizonUI.notice(body, "Модель пока не передала состояние оборудования.")
		return
	var assignments: Variant = section.get("assignments", section.get("assigned", {}))
	if assignments is Dictionary and not assignments.is_empty():
		var card := _card(screen, body, "Назначения", "Текущее распределение оборудования по слотам")
		_render_fields(card, assignments)
	var items := _section_items(section)
	if items.is_empty():
		var card := _card(screen, body, "Состояние оборудования", "Владение и доступность по данным модели")
		_render_fields(card, section)
		_render_actions(screen, card, section.get("actions", []), true)
		return
	for item in items:
		if not item is Dictionary:
			continue
		var title := str(item.get("title", item.get("name", item.get("id", "Оборудование"))))
		var card := _card(screen, body, title, _description(item))
		_render_fields(card, item)
		_render_actions(screen, card, item.get("actions", []), true)

static func _specialists(screen: Control, body: VBoxContainer, section: Dictionary) -> void:
	HorizonUI.label(body, "80 специалистов по канону. Обычные рабочие — отдельная система; назначение одного специалиста на несколько площадок запрещено.", 14)
	if not section.is_empty():
		var overview := _card(screen, body, "Слоты и назначения", "Фактическая вместимость и занятость из модели")
		_render_fields(overview, section, ["slots", "slot_count", "assignments", "active_slots", "site", "reason", "available"])
		_render_actions(screen, overview, section.get("actions", []), true)
	var records := GameMath.records("specialists")
	if records.is_empty():
		HorizonUI.notice(body, "Каталог специалистов не загружен.")
		return
	for record in records:
		var id := str(record.get("id", ""))
		var state := _find_state(section, id)
		var effect := "%s → %s · %s → %s %s" % [str(record.get("stat", "")), str(record.get("target", "")), str(record.get("base", "?")), str(record.get("max", "?")), str(record.get("unit", ""))]
		var card := _card(screen, str(record.get("name", id)), "%s · %s · %s\n%s" % [str(record.get("rarity", "")), str(record.get("site", "")), str(record.get("role", "")), effect])
		_render_state(card, state)
		if state.is_empty():
			HorizonUI.notice(card, "Состояние владения не предоставлено моделью.")
		_render_actions(screen, card, state.get("actions", []), true)

static func _cases(screen: Control, body: VBoxContainer, section: Dictionary) -> void:
	HorizonUI.label(body, "Перед открытием показываются реальные шансы. Открытие выполняется только через сохраняемое действие модели.", 14)
	var records := GameMath.records("cases")
	for record in records:
		var id := str(record.get("id", ""))
		var state := _find_state(section, id)
		var details := "Доступ: %s\nРедкость: %s\nПул: %s" % [str(record.get("unlock", "не указано")), _probabilities(record.get("rarity_prob_pct", {})), _probabilities(record.get("category_prob_pct", {}))]
		var card := _card(screen, str(record.get("title", id)), details)
		_render_state(card, state)
		if bool(record.get("paid_enabled", false)):
			HorizonUI.notice(card, "Для этого набора покупки в этой сборке недоступны.")
		_render_actions(screen, card, state.get("actions", []), not bool(record.get("paid_enabled", false)))
	if not section.is_empty():
		var status := _card(screen, "Счётчики и гарантии", "Показатели модели для доступных бесплатных источников")
		_render_fields(status, section, ["pity", "opened", "free_source", "reason", "available"])
		_render_actions(screen, status, section.get("actions", []), true)
	if records.is_empty():
		HorizonUI.notice(body, "Каталог кейсов не загружен.")

static func _season(screen: Control, body: VBoxContainer, section: Dictionary) -> void:
	HorizonUI.label(body, "Горные глубины · 60 уровней", 20, HorizonUI.GOLD)
	HorizonUI.label(body, "Бесплатная и премиальная дорожки показаны раздельно. Премиальная дорожка не выдаёт награды без подтверждённой оплаты.", 14)
	var progress := _card(screen, "Прогресс сезона", "Фактические XP, уровень и доступность из модели")
	_render_fields(progress, section, ["level", "xp", "season_xp", "xp_to_next", "claimed", "free_claims", "premium_unlocked", "premium_owned", "reason"])
	_render_actions(screen, progress, section.get("actions", []), true)
	_render_track(screen, body, section, "Бесплатная дорожка", ["free_rewards", "free", "rewards_free"], false)
	_render_track(screen, body, section, "Премиальная дорожка", ["premium_rewards", "premium", "rewards_premium"], true)
	var tasks := GameMath.records("season_tasks")
	var task_header := _card(screen, body, "Задания сезона · %d шаблонов" % tasks.size(), "Прогресс и получение наград берутся только из состояния модели")
	if tasks.is_empty():
		HorizonUI.notice(task_header, "Каталог заданий не загружен.")
	for task in tasks:
		var id := str(task.get("template_id", ""))
		var state := _find_state(section, id)
		var title := str(task.get("title", id))
		var details := "%s · цель %s\n%s" % [str(task.get("kind", "")), str(task.get("target_count", "?")), str(task.get("rules", ""))]
		var card := _card(screen, title, details)
		_render_state(card, state)
		var route_id := str(task.get("route_id", ""))
		if TASK_ROUTES.has(route_id):
			var target := str(TASK_ROUTES[route_id])
			HorizonUI.button(card, "К выполнению", "TaskRoute" + id, func(): screen.callv("go", [target, str(screen.get("site"))]))
		_render_actions(screen, card, state.get("actions", []), true)

static func _render_track(screen: Control, body: VBoxContainer, season: Dictionary, title: String, keys: Array, premium: bool) -> void:
	var source: Variant = {}
	for key in keys:
		if season.has(key):
			source = season[key]
			break
	var card := _card(screen, title, "60 уровней · %s" % ("доступ после подтверждённой оплаты" if premium else "бесплатная награда доступна по прогрессу"))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_child(grid)
	for level in range(1, SEASON_LEVELS + 1):
		var tile := PanelContainer.new()
		tile.custom_minimum_size = Vector2(72, 58)
		grid.add_child(tile)
		var text := _level_reward(source, level)
		var label := HorizonUI.label(tile, "%02d\n%s" % [level, text], 11)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if premium:
		HorizonUI.notice(card, "Премиум-пропуск нельзя купить в этой сборке.")
	_render_actions(screen, card, season.get("%s_actions" % ("premium" if premium else "free"), []), not premium)

static func _events(screen: Control, body: VBoxContainer, section: Dictionary) -> void:
	HorizonUI.label(body, "8 канонических событий. Переход к событию сам по себе не засчитывает его выполнение.", 14)
	var records := GameMath.records("events")
	for record in records:
		var id := str(record.get("id", ""))
		var state := _find_state(section, id)
		var details := "%s · %s\nЦель: %s\nНаграда: %s" % [str(record.get("site", "")), str(record.get("gameplay_type", "")), str(record.get("goal", "")), str(record.get("reward_type", ""))]
		var card := _card(screen, str(record.get("title", id)), details)
		_render_state(card, state)
		_render_actions(screen, card, state.get("actions", []), true)
	if not section.is_empty():
		var overview := _card(screen, "Состояние событий", "Таймеры и доступность только из модели")
		_render_fields(overview, section, ["active", "ends_at", "completed", "claimed", "reason"])
		_render_actions(screen, overview, section.get("actions", []), true)
	if records.is_empty():
		HorizonUI.notice(body, "Каталог событий не загружен.")

static func _shop(screen: Control, body: VBoxContainer, section: Dictionary) -> void:
	HorizonUI.label(body, "Покупки пока недоступны", 20, HorizonUI.GOLD)
	HorizonUI.label(body, "В проекте нет платёжного SDK и подтверждения магазина. Цены ниже — только справочные; ничего не списывается и VIP нельзя купить напрямую.", 14)
	var skus := GameMath.records("shop")
	for sku in skus:
		var contents: Variant = sku.get("contents", {})
		var card := _card(screen, str(sku.get("title", sku.get("sku_id", "Набор"))), "SKU %s · справочная цена %s ₸ · лимит %s\nСостав: %s" % [str(sku.get("sku_id", "")), str(sku.get("preview_price_kzt", "—")), str(sku.get("limit", "")), _format_value(contents)])
		HorizonUI.notice(card, "Покупка отключена: StoreKit не подключён.")
	if skus.is_empty():
		HorizonUI.notice(body, "Каталог магазина не загружен.")
	var vip := GameMath.records("vip")
	var vip_card := _card(screen, "VIP · 11 рангов", "Ранг растёт только от подтверждённых покупок; отдельной продажи VIP нет.")
	var current_rank := _lookup(section, ["current_rank", "vip_rank", "rank"])
	var current_points := _lookup(section, ["vip_points", "points"])
	if current_rank != null or current_points != null:
		HorizonUI.label(vip_card, "Текущий ранг: %s · очки: %s" % [str(current_rank if current_rank != null else "—"), str(current_points if current_points != null else "—")], 14)
	for rank in vip:
		var card := _card(screen, "VIP %s · %s очков" % [str(rank.get("rank", "?")), str(rank.get("required_vip_points", "?"))], "Бонус производства: %s%% · Награда: %s" % [str(rank.get("cumulative_base_production_bonus_pct", "?")), str(rank.get("rank_reward", ""))])
		HorizonUI.notice(card, "Ранг нельзя приобрести напрямую.")
	_render_fields(vip_card, section, ["vip_points", "current_rank", "next_rank", "next_rank_points"])
	if vip.is_empty():
		HorizonUI.notice(vip_card, "Каталог VIP не загружен.")

static func _render_actions(screen: Control, parent: Node, actions: Variant, allow: bool) -> void:
	if not allow or not actions is Array:
		return
	for descriptor in actions:
		if not descriptor is Dictionary:
			continue
		var action := str(descriptor.get("action", descriptor.get("command", "")))
		if action.is_empty():
			continue
		var label := str(descriptor.get("label", descriptor.get("title", descriptor.get("text", action))))
		var domain := str(descriptor.get("domain", "meta"))
		var args: Dictionary = descriptor.get("args", {})
		var reason := str(descriptor.get("reason", ""))
		screen.callv("btn", [parent, label, domain, action, args, reason])

static func _render_state(parent: Node, state: Dictionary) -> void:
	if state.is_empty():
		return
	_render_fields(parent, state, ["owned", "count", "quantity", "level", "stars", "equipped", "assigned", "assigned_site", "slot", "progress", "target", "claimed", "completed", "unlocked", "available", "reason", "status", "pity", "opened", "current", "unlock_reason"])

static func _render_fields(parent: Node, values: Dictionary, wanted: Array = []) -> void:
	if values.is_empty():
		return
	var keys: Array = wanted if not wanted.is_empty() else values.keys()
	var shown := 0
	for key in keys:
		if not values.has(key) or key in ["actions", "items", "records", "free_rewards", "premium_rewards"]:
			continue
		var value: Variant = values[key]
		if value == null or value is Dictionary and value.is_empty() or value is Array and value.is_empty():
			continue
		HorizonUI.label(parent, "%s: %s" % [_field_name(str(key)), _format_value(value)], 13)
		shown += 1
		if shown >= 12:
			break
	if values.get("available", true) == false and values.has("reason"):
		HorizonUI.notice(parent, str(values["reason"]))

static func _card(screen: Control, body: Node, title: String, description: String = "") -> VBoxContainer:
	var value: Variant = screen.callv("card", [body, title, description])
	if value is VBoxContainer:
		return value
	var fallback := HorizonUI.column(body, 6)
	HorizonUI.label(fallback, title, 17, HorizonUI.GOLD)
	if not description.is_empty():
		HorizonUI.label(fallback, description, 13)
	return fallback

static func _section_items(section: Dictionary) -> Array:
	for key in ["items", "records", "equipment", "owned", "inventory"]:
		var value: Variant = section.get(key, [])
		if value is Array:
			return value
		if value is Dictionary:
			var result: Array = []
			for id in value:
				var item: Variant = value[id]
				if item is Dictionary:
					var copy: Dictionary = item.duplicate(true)
					copy["id"] = str(copy.get("id", id))
					result.append(copy)
		return result
	return []

static func _find_state(section: Dictionary, id: String) -> Dictionary:
	if section.has(id) and section[id] is Dictionary:
		return section[id]
	for key in ["items", "records", "owned", "inventory", "specialists", "cases", "tasks", "events"]:
		var source: Variant = section.get(key, {})
		if source is Dictionary and source.has(id):
			var item: Variant = source[id]
			return item if item is Dictionary else {"count":item}
		if source is Array:
			for item in source:
				if item is Dictionary and str(item.get("id", item.get("template_id", item.get("sku_id", "")))) == id:
					return item
	return {}

static func _description(record: Dictionary) -> String:
	for key in ["description", "effect", "summary", "goal"]:
		if record.has(key) and not str(record[key]).is_empty():
			return str(record[key])
	return ""

static func _probabilities(value: Variant) -> String:
	if not value is Dictionary:
		return _format_value(value)
	var parts: PackedStringArray = []
	for key in value:
		parts.append("%s %s%%" % [str(key), str(value[key])])
	return ", ".join(parts) if not parts.is_empty() else "не указано"

static func _level_reward(source: Variant, level: int) -> String:
	if source is Dictionary:
		var value: Variant = source.get(str(level), source.get(level, ""))
		return _format_value(value) if value != null and not str(value).is_empty() else "—"
	if source is Array:
		for reward in source:
			if reward is Dictionary and int(reward.get("level", reward.get("level_id", 0))) == level:
				return _format_value(reward.get("reward", reward.get("title", reward)))
	return "—"

static func _lookup(values: Dictionary, keys: Array) -> Variant:
	for key in keys:
		if values.has(key):
			return values[key]
	return null

static func _format_value(value: Variant) -> String:
	if value is Dictionary:
		var parts: PackedStringArray = []
		for key in value:
			parts.append("%s: %s" % [str(key), _format_value(value[key])])
		return ", ".join(parts)
	if value is Array:
		var parts: PackedStringArray = []
		for item in value:
			parts.append(_format_value(item))
		return ", ".join(parts)
	return str(value)

static func _field_name(key: String) -> String:
	var names := {
		"owned":"В наличии", "count":"Количество", "quantity":"Количество", "level":"Уровень",
		"stars":"Звёзды", "equipped":"Установлено", "assigned":"Назначен", "assigned_site":"Площадка",
		"slot":"Слот", "progress":"Прогресс", "target":"Цель", "claimed":"Получено",
		"completed":"Выполнено", "unlocked":"Открыто", "available":"Доступно", "reason":"Причина",
		"status":"Статус", "pity":"Гарантия", "opened":"Открыто кейсов", "current":"Текущее",
		"unlock_reason":"Условие открытия", "slots":"Слоты", "slot_count":"Всего слотов",
		"active_slots":"Активные слоты", "assignments":"Назначения", "season_xp":"XP сезона",
		"xp":"XP сезона", "xp_to_next":"До следующего уровня", "premium_unlocked":"Премиум открыт",
		"premium_owned":"Премиум пропуск", "free_claims":"Получено бесплатных наград",
		"current_rank":"Текущий ранг", "vip_points":"VIP-очки", "next_rank":"Следующий ранг",
		"next_rank_points":"Очки до ранга", "active":"Активно", "ends_at":"Завершение",
	}
	return str(names.get(key, key))
