class_name MetaPanels
extends RefCounted

const META_MODEL_PATH := "res://gameplay/MetaModel.gd"
const CONFIG_PATH := "res://data/proposals/meta.json"
const SEASON_LEVELS := 60
const TASK_ROUTES := {
	"active_site":"mine", "trade":"trade", "geology":"geology",
	"network":"network", "research":"research", "hq":"story",
}
const SITE_LABELS := {"fe":"Fe", "pd":"Pd", "ir":"Ir", "vip":"VIP"}
const SLOT_LABELS := {
	"pickaxe":"Кирка", "helmet":"Шлем", "gloves":"Перчатки", "suit":"Костюм",
	"boots":"Ботинки", "lamp":"Фонарь", "scanner":"Сканер", "backpack":"Рюкзак",
	"drill":"Бур", "respirator":"Респиратор", "overalls":"Комбинезон",
	"analyzer":"Анализатор", "transport":"Транспорт", "coolant":"Охлаждение", "robot":"Робот",
}
static var _config_cache: Dictionary = {}

static func render(screen: Control, body: VBoxContainer, tab: String) -> void:
	var profile: Dictionary = screen.call("profile")
	var view := _model_view(profile)
	var site := str(screen.get("site"))
	match tab:
		"equipment": _equipment(screen, body, view.get("gear", {}), view.get("bonuses", {}), profile, site)
		"specialists": _specialists(screen, body, view, profile, site)
		"cases": _cases(screen, body, view.get("cases", {}), profile)
		"season": _season(screen, body, view.get("season", {}), profile)
		"events": _events(screen, body, view.get("events", []))
		"shop": _shop(screen, body, view.get("shop", {}), view.get("vip", {}))
		_:
			HorizonUI.notice(body, "Раздел не найден.")

static func _model_view(profile: Dictionary) -> Dictionary:
	var script: Variant = load(META_MODEL_PATH)
	if script == null or not script.has_script_method("view"):
		return {}
	var value: Variant = script.callv("view", [profile])
	return value if value is Dictionary else {}

static func _equipment(screen: Control, body: VBoxContainer, gear: Dictionary, bonuses: Dictionary, profile: Dictionary, site: String) -> void:
	var config := _proposal_config()
	var equipment_cfg: Dictionary = config.get("equipment", {})
	var slots_by_site: Dictionary = equipment_cfg.get("site_slots", {})
	var slots: Array = slots_by_site.get(site, [])
	var items: Array = gear.get("items", [])
	var equipped_by_site: Dictionary = gear.get("equipped", {})
	var equipped: Dictionary = equipped_by_site.get(site, {})
	var site_open := GameMath.unlocked(profile, site)
	HorizonUI.label(body, "Снаряжение · %s" % str(SITE_LABELS.get(site, site.to_upper())), 19, HorizonUI.GOLD)
	HorizonUI.label(body, "Предметы и назначения берутся из профиля. Параметры слотов и улучшений — проектные значения, не отдельный канон.", 13)
	var assignments := _card(screen, body, "Слоты участка", "Текущая экипировка для выбранного предприятия")
	if slots.is_empty():
		HorizonUI.notice(assignments, "Для этого участка слоты не настроены.")
	for slot_value in slots:
		var slot := str(slot_value)
		var item_id := str(equipped.get(slot, ""))
		var item := _item_by_id(items, item_id)
		var slot_card := _card(screen, assignments, str(SLOT_LABELS.get(slot, slot)), "Слот %s" % slot)
		if item.is_empty():
			HorizonUI.notice(slot_card, "Не установлено")
		else:
			HorizonUI.label(slot_card, "%s · ур. %d · ★ %d" % [str(item.get("rarity", "Обычный")), int(item.get("level", 1)), int(item.get("stars", 0))], 13)
			HorizonUI.label(slot_card, "ID: %s" % item_id, 11, HorizonUI.MUTED)
			_action(screen, slot_card, "Снять", "gear_unequip", {"site":site, "slot":slot}, "" if site_open else "Участок пока закрыт")
		for candidate in items:
			if str(candidate.get("site", "")) != site or str(candidate.get("slot", "")) != slot or str(candidate.get("id", "")) == item_id:
				continue
			_action(screen, slot_card, "Установить %s" % str(candidate.get("id", "")), "gear_equip", {"site":site, "slot":slot, "item_id":str(candidate.get("id", ""))}, "" if site_open else "Участок пока закрыт")
		var effect: Dictionary = equipment_cfg.get("slot_effects", {}).get(site, {}).get(slot, {})
		if not effect.is_empty():
			HorizonUI.notice(slot_card, "Эффект слота: " + _format_value(effect))
	if not site_open:
		HorizonUI.notice(assignments, "Участок закрыт: действия снаряжения недоступны.")
	var active: Dictionary = {}
	for key in bonuses:
		if str(key).begins_with(site + ":"):
			active[str(key).trim_prefix(site + ":")] = bonuses[key]
	if not active.is_empty():
		HorizonUI.label(body, "Активные бонусы участка: " + _format_value(active), 13)
	var storage := _card(screen, body, "Предметы и улучшения", "Дубликаты дают фрагменты по правилам кейсов")
	if items.is_empty():
		HorizonUI.notice(storage, "Снаряжение пока не получено.")
	for item in items:
		var id := str(item.get("id", ""))
		var template := str(item.get("template_id", id))
		var site_id := str(item.get("site", ""))
		var slot := str(item.get("slot", ""))
		var level := int(item.get("level", 1))
		var stars := int(item.get("stars", 0))
		var card := _card(screen, storage, "%s · %s" % [str(SLOT_LABELS.get(slot, slot)), str(item.get("rarity", "Обычный"))], "%s · %s · уровень %d/%d · звёзды %d/%d" % [str(SITE_LABELS.get(site_id, site_id.to_upper())), str(item.get("source", "")), level, int(equipment_cfg.get("level_cap", 100)), stars, int(equipment_cfg.get("star_cap", 5))])
		screen.call("illustration",card,template)
		var fragments: Dictionary = gear.get("fragments", {})
		HorizonUI.label(card, "Фрагменты: %d" % int(fragments.get(template, 0)), 12)
		var level_cost := int(equipment_cfg.get("upgrade_base_cost_cents", 0)) + level * int(equipment_cfg.get("upgrade_cost_per_level_cents", 0))
		var level_reason := ""
		if level >= int(equipment_cfg.get("level_cap", 100)):
			level_reason = "Достигнут максимальный уровень"
		elif int(profile.get("money_cents", 0)) < level_cost:
			level_reason = "Недостаточно гелионов · нужно %s Г" % _money(level_cost)
		_action(screen, card, "Улучшить · %s Г" % _money(level_cost), "gear_upgrade", {"item_id":id}, level_reason)
		var star_costs: Array = equipment_cfg.get("star_fragment_costs", [])
		var star_reason := ""
		if stars >= int(equipment_cfg.get("star_cap", 5)) or stars >= star_costs.size():
			star_reason = "Достигнут предел звёзд"
		else:
			var needed := int(star_costs[stars])
			if int(fragments.get(template, 0)) < needed:
				star_reason = "Недостаточно фрагментов · нужно %d" % needed
		_action(screen, card, "Повысить звезду", "gear_star", {"item_id":id}, star_reason)
		var current_id := str(equipped_by_site.get(site_id, {}).get(slot, ""))
		if current_id != id:
			_action(screen, card, "Установить", "gear_equip", {"site":site_id, "slot":slot, "item_id":id}, "" if GameMath.unlocked(profile, site_id) else "Участок пока закрыт")

static func _specialists(screen: Control, body: VBoxContainer, view: Dictionary, profile: Dictionary, site: String) -> void:
	var data: Dictionary = view.get("specialists", {})
	var catalog: Array = data.get("catalog", [])
	var owned: Dictionary = data.get("owned", {})
	var assignments: Dictionary = data.get("assignments", {})
	var team_slots: Dictionary = data.get("team_slots", {})
	var team: Dictionary = assignments.get(site, {})
	var slot_count := int(team_slots.get(site, 0))
	var site_open := GameMath.unlocked(profile, site)
	var vip_rank := int(view.get("vip", {}).get("rank", 0))
	var cfg := _proposal_config()
	var specialist_cfg: Dictionary = cfg.get("specialists", {})
	HorizonUI.label(body, "Специалисты · %d в каноне" % catalog.size(), 19, HorizonUI.GOLD)
	HorizonUI.label(body, "Коллекционные специалисты не заменяют обычных работников. Один специалист может быть назначен только на один участок.", 13)
	var team_card := _card(screen, body, "Назначения · %s" % str(SITE_LABELS.get(site, site.to_upper())), "Доступно слотов: %d" % slot_count)
	for slot in range(slot_count):
		var slot_key := str(slot)
		var specialist_id := str(team.get(slot_key, ""))
		var row := _catalog_by_id(catalog, specialist_id)
		var title := "Слот %d · %s" % [slot + 1, str(row.get("name", "свободен"))]
		var slot_card := _card(screen, team_card, title, "ID: %s" % specialist_id if not specialist_id.is_empty() else "Назначьте полученного специалиста из каталога ниже")
		if not specialist_id.is_empty():
			_action(screen, slot_card, "Снять со слота", "specialist_unassign", {"site":site, "slot":slot}, "" if site_open else "Участок пока закрыт")
	if not site_open:
		HorizonUI.notice(team_card, "Участок пока закрыт.")
	var vip_slots := int(team_slots.get("vip", 0))
	var vip_team: Dictionary = assignments.get("vip", {})
	var vip_open_slot := _first_open_slot(vip_team, vip_slots)
	if vip_slots > 0:
		var vip_card := _card(screen, body, "Глобальные VIP-слоты", "Разблокируются подтверждённым VIP 8")
		for slot in range(vip_slots):
			var slot_key := str(slot)
			var specialist_id := str(vip_team.get(slot_key, ""))
			var row := _catalog_by_id(catalog, specialist_id)
			var item := _card(screen, vip_card, "Слот %d · %s" % [slot + 1, str(row.get("name", "свободен"))], specialist_id)
			if not specialist_id.is_empty():
				_action(screen, item, "Снять со слота", "specialist_unassign", {"site":"vip", "slot":slot})
	var assigned_to := _assigned_locations(assignments)
	var open_slot := _first_open_slot(team, slot_count)
	var fragments: Dictionary = data.get("fragments", {})
	for row in catalog:
		var id := str(row.get("id", ""))
		var progress: Dictionary = row.get("progress", {})
		var is_owned := owned.has(id)
		if is_owned:
			progress = owned[id]
		var rarity := str(row.get("rarity", ""))
		var effect := "%s → %s · %s–%s %s" % [str(row.get("stat", "")), str(row.get("target", "")), str(row.get("base", "?")), str(row.get("max", "?")), str(row.get("unit", ""))]
		var card := _card(screen, body, "%s · %s" % [str(row.get("name", id)), rarity], "%s · %s\n%s" % [str(SITE_LABELS.get(_site_key(str(row.get("site", ""))), str(row.get("site", "")))), str(row.get("role", "")), effect])
		screen.call("illustration",card,id)
		HorizonUI.label(card, "ID %s · уровень %d/%d · звёзды %d/%d" % [id, int(progress.get("level", 1)), int(row.get("level_cap", 100)), int(progress.get("stars", 0)), int(row.get("star_cap", 5))], 12)
		if is_owned:
			HorizonUI.label(card, "Получен · фрагменты %d" % int(fragments.get(id, 0)), 12, HorizonUI.GOLD)
			var assigned: Dictionary = assigned_to.get(id, {})
			if not assigned.is_empty():
				HorizonUI.notice(card, "Назначен: %s · слот %d" % [str(SITE_LABELS.get(assigned.get("site", ""), assigned.get("site", ""))), int(assigned.get("slot", 0)) + 1])
			else:
				var reason := _assignment_reason(row, site, site_open, open_slot, vip_rank)
				var target_site := site
				var target_slot := maxi(0, open_slot)
				_action(screen, card, "Назначить в слот %d" % (target_slot + 1), "specialist_assign", {"specialist_id":id, "site":target_site, "slot":target_slot}, reason)
				if vip_slots > 0 and _site_key(str(row.get("site", ""))) == "global":
					var vip_reason := "" if vip_open_slot >= 0 else "VIP-слот занят"
					_action(screen, card, "Назначить в глобальный VIP-слот", "specialist_assign", {"specialist_id":id, "site":"vip", "slot":maxi(0, vip_open_slot)}, vip_reason)
			var level := int(progress.get("level", 1))
			var level_cost := int(specialist_cfg.get("level_base_cost_cents", 0)) + level * int(specialist_cfg.get("level_cost_per_level_cents", 0))
			var level_reason := ""
			if level >= int(row.get("level_cap", 100)):
				level_reason = "Достигнут максимальный уровень"
			elif int(profile.get("money_cents", 0)) < level_cost:
				level_reason = "Недостаточно гелионов · нужно %s Г" % _money(level_cost)
			_action(screen, card, "Уровень · %s Г" % _money(level_cost), "specialist_level", {"specialist_id":id}, level_reason)
			var stars := int(progress.get("stars", 0))
			var star_costs: Array = specialist_cfg.get("star_fragment_costs", [])
			var star_reason := ""
			if stars >= int(row.get("star_cap", 5)) or stars >= star_costs.size():
				star_reason = "Достигнут предел звёзд"
			else:
				var needed := int(star_costs[stars])
				if int(fragments.get(id, 0)) < needed:
					star_reason = "Недостаточно фрагментов · нужно %d" % needed
			_action(screen, card, "Повысить звезду", "specialist_star", {"specialist_id":id}, star_reason)
		else:
			var reason := "Не получен"
			if int(row.get("rank_required", 0)) > vip_rank:
				reason = "Требуется VIP %d" % int(row.get("rank_required", 0))
			elif not bool(row.get("eligible_case_pool", false)):
				reason = "Пока нет доступного источника: участок закрыт или действует VIP-ограничение"
			else:
				var sources := _specialist_case_sources(view.get("cases", {}), id)
				reason = "Не получен · доступные кейсы: %s" % (", ".join(sources) if not sources.is_empty() else "нет")
			HorizonUI.notice(card, reason)

static func _cases(screen: Control, body: VBoxContainer, cases: Dictionary, profile: Dictionary) -> void:
	HorizonUI.notice(body,"Гарантия 10/40/120 даёт настоящую карту или фрагменты нужной редкости. Деньги и материалы не сбрасывают счётчик гарантии; при закрытом пуле специалиста выпадает снаряжение той же редкости.")
	var catalog: Array = cases.get("catalog", [])
	var inventory: Dictionary = cases.get("inventory", {})
	var pity: Dictionary = cases.get("pity", {})
	HorizonUI.label(body, "Кейсы · таблица %s" % str(cases.get("table_version", "")), 19, HorizonUI.GOLD)
	HorizonUI.label(body, "Шансы приведены из канонического каталога. Открытие требует кейс в инвентаре; покупки здесь отключены.", 13)
	for row in catalog:
		var id := str(row.get("id", ""))
		var count := int(inventory.get(id, profile.get("inventory", {}).get(id, 0)))
		var state: Dictionary = pity.get(id, {})
		var details := "Доступ: %s · источник: %s\nРедкость: %s\nКатегория: %s" % [str(row.get("unlock", "—")), str(row.get("free_source", "—")), _probabilities(row.get("rarity_prob_pct", {})), _probabilities(row.get("category_prob_pct", {}))]
		var card := _card(screen, body, str(row.get("title", id)), details)
		HorizonUI.label(card, "В инвентаре: %d · доступно: %s" % [count, "да" if bool(row.get("available", false)) else "нет"], 13)
		var thresholds: Dictionary = row.get("pity", {})
		HorizonUI.notice(card, "Гарантия · эпик %d · легендарный %d · мифический %d" % [int(thresholds.get("epic_or_higher", 0)), int(thresholds.get("legendary_or_higher", 0)), int(thresholds.get("mythic", 0))])
		if not state.is_empty():
			HorizonUI.label(card, "До гарантий: эпик %d · легендарный %d · мифический %d" % [int(state.get("since_epic", 0)), int(state.get("since_legendary", 0)), int(state.get("since_mythic", 0))], 12)
		if count > 0 and bool(row.get("available", false)):
			var open_id: String = "%s:%s:%d" % [str(profile.get("profile_id", "local")), id, Time.get_ticks_usec()]
			_action(screen, card, "Открыть кейс", "case_open", {"case_id":id, "open_id":open_id})
		else:
			var reason := "Кейс недоступен по условию %s" % str(row.get("unlock", "разблокировки")) if not bool(row.get("available", false)) else "Нет кейса в инвентаре"
			_action(screen, card, "Открыть кейс", "case_open", {"case_id":id, "open_id":""}, reason)
	var milestone_cfg: Array = _proposal_config().get("cases", {}).get("free_case_milestones", [])
	if not milestone_cfg.is_empty():
		var milestones: Dictionary = GameMath.game(profile).get("meta", {}).get("milestones", {})
		var stats: Dictionary = GameMath.game(profile).get("stats", {})
		var milestone_card := _card(screen, body, "Бесплатные кейсы за игровые этапы", "Без покупок · награды выдаются один раз")
		for milestone in milestone_cfg:
			var milestone_id := str(milestone.get("id", ""))
			var target := int(milestone.get("target", 0))
			var progress := int(stats.get(str(milestone.get("stat", "")), 0))
			var reward := _format_value(milestone.get("reward", {}))
			var line := _card(screen, milestone_card, str(milestone_id), "%s · %d/%d\nНаграда: %s" % [str(milestone.get("stat", "")), mini(progress, target), target, reward])
			if bool(milestones.get(milestone_id, false)):
				HorizonUI.notice(line, "Получено")
			elif progress >= target:
				_action(screen, line, "Получить бесплатный кейс", "claim_case_milestone", {"milestone_id":milestone_id})
			else:
				HorizonUI.notice(line, "Этап ещё не выполнен")
	var history: Dictionary = cases.get("history", {})
	if not history.is_empty():
		var history_card := _card(screen, body, "Недавние открытия", "Результаты уже сохранены")
		var ids: Array = history.keys()
		ids.reverse()
		for index in mini(ids.size(), 5):
			var record: Dictionary = history[ids[index]]
			var result: Dictionary = record.get("result", {})
			HorizonUI.label(history_card, "%s · %s · %s" % [str(record.get("case_id", "")), str(result.get("rarity", "")), _format_value(result.get("reward", {}))], 12)

static func _season(screen: Control, body: VBoxContainer, season: Dictionary, profile: Dictionary) -> void:
	var level := int(season.get("level", 0))
	var cap := int(season.get("level_cap", SEASON_LEVELS))
	var xp := int(season.get("xp", 0))
	HorizonUI.label(body, "Горные глубины · %d уровней" % cap, 20, HorizonUI.GOLD)
	HorizonUI.label(body, "Уровень %d/%d · %d XP · %d XP на уровень" % [level, cap, xp, int(season.get("xp_per_level", 0))], 15)
	HorizonUI.notice(body, "Награды дорожек — предварительные данные. Премиальная дорожка отключена до подтверждённой оплаты; награды без оплаты не выдаются.")
	var levels: Array = season.get("levels", [])
	_render_season_track(screen, body, levels, "Бесплатная дорожка", "free", true)
	_render_season_track(screen, body, levels, "Премиальная дорожка", "premium", false)
	var tasks: Array = season.get("tasks", [])
	var task_list := _card(screen, body, "Задания сезона · %d шаблонов" % tasks.size(), "Прогресс считается моделью по фактическим игровым событиям")
	if tasks.is_empty():
		HorizonUI.notice(task_list, "Задания сезона не загружены.")
	for task in tasks:
		var id := str(task.get("template_id", ""))
		var target := int(task.get("target_count", 0))
		var progress := int(task.get("progress", 0))
		var card := _card(screen, task_list, str(task.get("title", id)), "%s · %d/%d · +%s XP\n%s" % [str(task.get("kind", "")), mini(progress, target), target, str(task.get("xp_reward", "0")), str(task.get("rules", ""))])
		HorizonUI.label(card, "Статус: %s" % ("награда получена" if bool(task.get("claimed", false)) else "выполнено" if bool(task.get("complete", false)) else "в процессе"), 12)
		var route_id := str(task.get("route_id", ""))
		if TASK_ROUTES.has(route_id):
			var target_tab := str(TASK_ROUTES[route_id])
			var site := str(screen.get("site"))
			HorizonUI.button(card, "К выполнению", "TaskRoute" + id, func(): screen.callv("go", [target_tab, site]))
		if bool(task.get("complete", false)) and not bool(task.get("claimed", false)):
			_action(screen, card, "Получить +%s XP" % str(task.get("xp_reward", "0")), "claim_season_task", {"task_id":id})

static func _render_season_track(screen: Control, body: VBoxContainer, levels: Array, title: String, lane: String, claimable: bool) -> void:
	var card := _card(screen, body, title, "Награды не утверждены как канон" if not levels.is_empty() else "Таблица наград не загружена")
	var scroll := ScrollContainer.new()
	scroll.name = "SeasonTrack" + lane
	scroll.custom_minimum_size.y = 180
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_ALWAYS
	card.add_child(scroll)
	var grid := HBoxContainer.new()
	grid.add_theme_constant_override("separation", 8)
	scroll.add_child(grid)
	for level in range(1, SEASON_LEVELS + 1):
		var row := _level_row(levels, level)
		var tile := PanelContainer.new()
		tile.custom_minimum_size = Vector2(148, 156)
		grid.add_child(tile)
		var content := HorizonUI.column(tile, 6)
		var reward: Variant = row.get(lane, {})
		var claimed_key := "free_claimed" if lane == "free" else "premium_claimed"
		var claimed := bool(row.get(claimed_key, false))
		var unlocked := bool(row.get("unlocked", false))
		var status := "получено" if claimed else "открыто" if unlocked else "закрыто"
		if lane == "premium":
			status = "недоступно"
		var reward_text := _format_reward(reward)
		if str(row.get("approval_status", "")) != "approved" and not reward_text.is_empty():
			reward_text += " · предварительно"
		var label := HorizonUI.label(content, "%02d · %s\n%s" % [level, reward_text, status], 13)
		label.size_flags_vertical = Control.SIZE_EXPAND_FILL
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		if claimable and unlocked and not claimed:
			_action(screen, content, "Получить", "claim_season_reward", {"level":level, "lane":"free"})
	if lane == "premium":
		HorizonUI.notice(card, "Premium недоступен: верифицированная оплата не подключена.")

static func _events(screen: Control, body: VBoxContainer, events: Array) -> void:
	var config: Dictionary = _proposal_config().get("events", {})
	var hooks: Dictionary = config.get("hooks", {})
	var rewards: Dictionary = config.get("rewards", {})
	HorizonUI.label(body, "События · %d шаблонов" % events.size(), 19, HorizonUI.GOLD)
	HorizonUI.label(body, "Посещение раздела не засчитывает событие. Прогресс приходит только от игрового действия; награды помечены как предварительные.", 13)
	for event in events:
		var id := str(event.get("id", ""))
		var hook: Dictionary = hooks.get(id, {})
		var target := int(hook.get("target", 1))
		var progress := int(event.get("progress", 0))
		var reward: Dictionary = rewards.get(id, {})
		var details := "%s · %s\nЦель: %s · %d/%d\nНаграда (предварительно): %s" % [str(event.get("site", "")), str(event.get("gameplay_type", "")), str(event.get("goal", "")), mini(progress, target), target, _format_reward(reward)]
		var card := _card(screen, body, str(event.get("title", id)), details)
		var status := "получено" if bool(event.get("claimed", false)) else "выполнено" if bool(event.get("complete", false)) else "в процессе"
		HorizonUI.label(card, "Статус: %s" % status, 12)
		if not bool(event.get("available", false)):
			HorizonUI.notice(card, "Недоступно: участок события ещё закрыт.")
		elif bool(event.get("complete", false)) and not bool(event.get("claimed", false)):
			_action(screen, card, "Получить предварительную награду", "claim_event", {"event_id":id})
		elif not bool(event.get("complete", false)):
			HorizonUI.notice(card, "Ожидает выполнения цели в соответствующей игровой системе.")

static func _shop(screen: Control, body: VBoxContainer, shop: Dictionary, vip: Dictionary) -> void:
	HorizonUI.label(body, str(shop.get("message", "Покупки пока недоступны")), 20, HorizonUI.GOLD)
	HorizonUI.label(body, "StoreKit и подтверждение чеков не подключены. Справочные цены не списываются; VIP нельзя купить напрямую.", 13)
	var products: Array = shop.get("products", [])
	var product_list := _card(screen, body, "Магазин · %d SKU" % products.size(), "Канонический каталог · без покупочных действий")
	for product in products:
		var title := str(product.get("title", product.get("sku_id", "")))
		var details := "SKU %s · справочная цена %s ₸ · лимит %s\nVIP-очки: %s · состав: %s" % [str(product.get("sku_id", "")), str(product.get("preview_price_kzt", "—")), str(product.get("limit", "")), str(product.get("vip_points", "0")), _format_value(product.get("contents", {}))]
		var card := _card(screen, product_list, title, details)
		HorizonUI.notice(card, str(product.get("message", "Покупки пока недоступны")))
	var ranks: Array = vip.get("catalog", [])
	var vip_list := _card(screen, body, "VIP · %d рангов" % ranks.size(), "Текущий ранг %d · доступен только от подтверждённых покупок" % int(vip.get("rank", 0)))
	for rank in ranks:
		var title := "VIP %s · %s очков" % [str(rank.get("rank", "?")), str(rank.get("required_vip_points", "?"))]
		var details := "Накопительный бонус производства: %s%%\nНаграда: %s" % [str(rank.get("cumulative_base_production_bonus_pct", "?")), str(rank.get("rank_reward", ""))]
		HorizonUI.label(_card(screen, vip_list, title, details), "VIP-ранг не продаётся отдельно.", 12, HorizonUI.MUTED)
	if not bool(shop.get("purchase_available", false)) or not bool(vip.get("purchase_available", false)):
		HorizonUI.notice(body, "Покупки отключены: нет верифицированного платёжного SDK.")

static func _action(screen: Control, parent: Node, label: String, action: String, args: Dictionary = {}, reason: String = "") -> Button:
	var value: Variant = screen.callv("btn", [parent, label, "meta", action, args, reason])
	return value as Button

static func _card(screen: Control, parent: Node, title: String, description: String = "") -> VBoxContainer:
	var value: Variant = screen.callv("card", [parent, title, description])
	return value as VBoxContainer

static func _proposal_config() -> Dictionary:
	if not _config_cache.is_empty():
		return _config_cache
	var file := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if file == null:
		return {}
	var value: Variant = JSON.parse_string(file.get_as_text())
	_config_cache = value if value is Dictionary else {}
	return _config_cache

static func _item_by_id(items: Array, id: String) -> Dictionary:
	for item in items:
		if str(item.get("id", "")) == id:
			return item
	return {}

static func _catalog_by_id(catalog: Array, id: String) -> Dictionary:
	for row in catalog:
		if str(row.get("id", "")) == id:
			return row
	return {}

static func _first_open_slot(team: Dictionary, count: int) -> int:
	for slot in range(count):
		if not team.has(str(slot)):
			return slot
	return -1

static func _assigned_locations(assignments: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for site in assignments:
		var team: Dictionary = assignments[site]
		for slot in team:
			result[str(team[slot])] = {"site":str(site), "slot":int(slot)}
	return result

static func _assignment_reason(row: Dictionary, site: String, site_open: bool, open_slot: int, vip_rank: int) -> String:
	if not site_open:
		return "Участок пока закрыт"
	if int(row.get("rank_required", 0)) > vip_rank:
		return "Требуется подтверждённый VIP %d" % int(row.get("rank_required", 0))
	var specialist_site := _site_key(str(row.get("site", "")))
	if specialist_site != "global" and specialist_site != site:
		return "Специалист предназначен для участка %s" % str(SITE_LABELS.get(specialist_site, specialist_site))
	if open_slot < 0:
		return "Нет свободных слотов на этом участке"
	return ""

static func _specialist_case_sources(cases: Dictionary, specialist_id: String) -> Array:
	var result: Array = []
	for case_id in cases.get("pools", {}):
		if cases["pools"][case_id].has(specialist_id):
			result.append(str(case_id))
	return result

static func _site_key(value: String) -> String:
	return {"Fe":"fe", "Pd":"pd", "Ir":"ir", "Global":"global", "fe":"fe", "pd":"pd", "ir":"ir", "global":"global"}.get(value, value.to_lower())

static func _level_row(levels: Array, target: int) -> Dictionary:
	for row in levels:
		if int(row.get("level", 0)) == target:
			return row
	return {}

static func _probabilities(values: Variant) -> String:
	if not values is Dictionary:
		return str(values)
	var parts: PackedStringArray = []
	for key in values:
		parts.append("%s %s%%" % [str(key), str(values[key])])
	return ", ".join(parts)

static func _format_reward(reward: Variant) -> String:
	if not reward is Dictionary or reward.is_empty():
		return "—"
	var kind := str(reward.get("kind", ""))
	var amount := str(reward.get("amount", ""))
	match kind:
		"money_cents": return "%s Г" % _money(int(reward.get("amount", 0)))
		"case": return "%s × %s" % [str(reward.get("case_id", "кейс")), amount]
		"shards": return "%s осколков" % amount
		"material": return "%s × %s" % [str(reward.get("resource_id", "материал")), amount]
		"evidence": return "Сюжетное свидетельство × %s" % amount
		_: return _format_value(reward)

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

static func _money(cents: int) -> String:
	return "%0.2f" % (float(cents) / 100.0)
