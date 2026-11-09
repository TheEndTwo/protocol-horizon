extends Control

const TABS := {
	"base":"База", "mine":"Шахта / добыча", "upgrades":"Улучшения", "equipment":"Оборудование",
	"machines":"Машины", "workers":"Рабочие", "factory":"Завод", "warehouse":"Склад",
	"trade":"Торговля", "contracts":"Контракты", "research":"Наука", "mastery":"Мастерство",
	"geology":"Геология", "map":"Карта Земли", "buildings":"Строительство", "network":"Промышленная сеть",
	"specialists":"Специалисты", "cases":"Кейсы", "season":"Сезон", "events":"События",
	"story":"Сюжет / архив", "expansion":"Экспансия / офлайн", "shop":"Магазин / VIP",
}
var site := "fe"
var tab := "base"
var ui_state: Dictionary = {}
var _hud: Label
var _status: Label
var _body: VBoxContainer
var _scroll: ScrollContainer
var _selector: OptionButton
var _tutorial_row: HBoxContainer
var _site_tabs: HBoxContainer
var _site_buttons: Dictionary = {}
var _live: Array = []
var _canvas: Control
var _graph_ref: GraphEdit
var _redraw_pending := false
var _buy_count := 1
var _elapsed := 0.0

func profile() -> Dictionary:
	return GameState.profile

func _ready() -> void:
	if not GameSession.prepare():
		var error_box := HorizonUI.screen(self, true)
		HorizonUI.label(error_box, GameSession.fault if not GameSession.fault.is_empty() else "Нет профиля", 20)
		HorizonUI.button(error_box, "В меню", "Menu", func(): SceneRouter.go_to(&"menu"))
		return
	var saved: Dictionary = GameMath.game(profile()).get("ui", {})
	tab = str(saved.get("tab", "base"))
	if not TABS.has(tab):
		tab = "base"
	site = str(saved.get("site", "fe"))
	if not GameMath.SITES.has(site):
		site = "fe"
	var shell := HorizonUI.screen(self, true)
	shell.add_theme_constant_override("separation", 7)
	var top := HBoxContainer.new()
	shell.add_child(top)
	var back := HorizonUI.button(top, "‹", "Menu", func():
		GameSession.flush()
		SceneRouter.go_to(&"menu"))
	back.custom_minimum_size = Vector2(44, 44)
	_hud = HorizonUI.label(top, "", 14, HorizonUI.GOLD)
	_hud.size_flags_horizontal = SIZE_EXPAND_FILL
	_selector = OptionButton.new()
	_selector.name = "SectionSelector"
	_selector.custom_minimum_size.y = 44
	for title in TABS.values():
		_selector.add_item(title)
	shell.add_child(_selector)
	_selector.item_selected.connect(func(index: int): go(TABS.keys()[index]))
	var links := HBoxContainer.new()
	shell.add_child(links)
	for item in [["База", "base"], ["Карта", "map"], ["Задания", "season"], ["↻", "refresh"]]:
		var target: String = item[1]
		var b := HorizonUI.button(links, item[0], "Nav" + target, func(): refresh() if target == "refresh" else go(target))
		b.custom_minimum_size.y = 44
		b.size_flags_horizontal = SIZE_EXPAND_FILL
	_tutorial_row = HBoxContainer.new()
	shell.add_child(_tutorial_row)
	_scroll = ScrollContainer.new()
	_scroll.name = "ContentScroll"
	_scroll.size_flags_vertical = SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	shell.add_child(_scroll)
	_body = HorizonUI.column(_scroll, 10)
	_site_tabs = HBoxContainer.new()
	_site_tabs.name = "SiteTabs"
	shell.add_child(_site_tabs)
	for destination in ["upgrades","equipment","machines","workers"]:
		var target: String = destination
		var button := HorizonUI.button(_site_tabs,TABS[target],"SiteNav"+target,func(): go(target))
		button.custom_minimum_size.y = 44
		button.size_flags_horizontal = SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size",12)
		button.toggle_mode = true
		_site_buttons[target] = button
	_status = HorizonUI.label(shell, "Текстуры-заготовки · нажатия и числа реальные", 12, HorizonUI.MUTED)
	_status.name = "Status"
	GameSession.message.connect(_on_message)
	refresh()
	var report: Dictionary = GameMath.game(profile()).get("offline_report", {})
	if not report.is_empty():
		_on_message("Офлайн: %d мин. · %s Г. Подробности в «Экспансия / офлайн»." % [int(report["seconds"]) / 60, money(int(report["money_cents"]))])

func go(next_tab: String, next_site: String = "") -> void:
	if not TABS.has(next_tab):
		next_tab = {"hq":"story", "power":"buildings", "active_site":"mine", "fe":"mine", "pd":"mine", "ir":"mine"}.get(next_tab, "base")
	if not next_site.is_empty() and GameMath.SITES.has(next_site):
		site = next_site
	if GameSession.navigate(next_tab, site) != OK:
		_on_message("Не удалось сохранить переход")
		return
	tab = next_tab
	_scroll.scroll_vertical = 0
	refresh()

func action(domain: String, command: String, args: Dictionary = {}) -> Dictionary:
	var result: Dictionary = GameSession.perform(domain, command, args)
	if result.get("ok", false):
		queue_refresh()
	return result

func queue_refresh() -> void:
	if not _redraw_pending:
		_redraw_pending = true
		refresh.call_deferred()

func refresh() -> void:
	_redraw_pending = false
	_live.clear()
	if is_instance_valid(_graph_ref):
		ui_state["graph_offset"] = _graph_ref.scroll_offset
		ui_state["graph_zoom"] = _graph_ref.zoom
	_graph_ref = null
	_canvas = null
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	_selector.select(TABS.keys().find(tab))
	_site_tabs.visible = tab in ["mine","upgrades","equipment","machines","workers"]
	for destination in _site_buttons:
		_site_buttons[destination].set_pressed_no_signal(tab == destination)
	_update_hud()
	var site_name: String = {"fe":"Шахта №17 · Fe", "pd":"Комплекс П-7 · Pd", "ir":"Сектор И-9 · Ir"}[site]
	HorizonUI.label(_body, TABS[tab] + "  /  " + site_name, 19, HorizonUI.GOLD)
	if tab in ["equipment", "specialists", "cases", "season", "events", "shop"]:
		load("res://gameplay/ui/MetaPanels.gd").render(self, _body, tab)
		if tab == "events":
			_event_actions()
	elif tab in ["research", "mastery", "geology", "contracts", "buildings", "story", "expansion", "network", "map"]:
		if tab == "research":
			HorizonUI.notice(_body,"Дерево: перетаскивание — панорама, щипок или колесо — масштаб. Ниже поиск и подробности всех узлов.")
			var graph = load("res://components/ResearchGraph.gd").new()
			_body.add_child(graph)
			graph.populate(profile())
			_graph_ref = graph
			if ui_state.has("graph_offset"):
				graph.set_deferred("scroll_offset",ui_state["graph_offset"])
				graph.zoom = float(ui_state.get("graph_zoom",0.65))
			graph.purchase_requested.connect(func(id: String): action("progression","research",{"id":id}))
		load("res://gameplay/ui/ProgressionPanels.gd").render(self, _body, tab)
		if tab in ["research", "mastery"]:
			_research_actions()
			FeatureControls.render(self,_body,"mastery" if tab == "mastery" else "research")
	elif tab == "base":
		_base()
	elif tab == "mine":
		_mine()
	elif tab in ["upgrades", "machines", "workers"]:
		_purchases()
	elif tab == "factory":
		_factory()
	elif tab in ["warehouse", "trade"]:
		_warehouse()
	_update_tutorial()
	AudioService.set_mine_ambience(tab == "mine" and site == "fe" and int(GameMath.site(profile(),"fe")["machines"].get("iron_conveyor",0)) > 0)

func _update_tutorial() -> void:
	for child in _tutorial_row.get_children():
		_tutorial_row.remove_child(child)
		child.queue_free()
	var g := GameMath.game(profile())
	if bool(g.get("qa_fixture",false)) or bool(g.get("tutorial_skips",{}).get(site,false)):
		_tutorial_row.hide()
		return
	var destination := "mine"
	var target := ""
	var title := ""
	var stats: Dictionary = g["stats"]
	if site == "fe":
		if float(stats.get("taps",0)) == 0:
			title = "Первый удар по породе"
		elif float(stats.get("sold",0)) == 0:
			title = "Продай свободное железо"
			target = "sell"
		elif float(stats.get("purchases:upgrade",0)) == 0:
			title = "Купи первое улучшение"
			destination = "upgrades"
			target = "buy"
		elif float(stats.get("workers_hired",0)) == 0:
			title = "Найми первого работника"
			destination = "workers"
			target = "buy"
		else:
			_tutorial_row.hide()
			return
	elif site == "pd":
		if float(stats.get("pd_cycles_completed",0)) > 0:
			_tutorial_row.hide()
			return
		title = "Проба → анализ → концентрация"
		target = "pd_take_sample"
	else:
		if float(stats.get("ir_campaigns_completed",0)) > 0:
			_tutorial_row.hide()
			return
		title = "Маршрут → шесть фаз → Ir"
		target = "ir_start_campaign"
	_tutorial_row.show()
	var selected_site := site
	var next_tab := destination
	var guide := HorizonUI.button(_tutorial_row,title,"TutorialTarget",func(): go(next_tab,selected_site))
	guide.size_flags_horizontal = SIZE_EXPAND_FILL
	guide.custom_minimum_size.y = 44
	guide.add_theme_font_size_override("font_size",13)
	var skip := HorizonUI.button(_tutorial_row,"Пропуск","SkipTutorial",func():
		if GameSession.skip_tutorial(selected_site) == OK:
			queue_refresh())
	skip.custom_minimum_size.y = 44
	skip.add_theme_font_size_override("font_size",13)
	if tab == destination:
		var control := find_child(target,true,false) as Control if not target.is_empty() else _canvas
		if is_instance_valid(control):
			if control is BaseButton and not control.disabled:
				control.grab_focus()
				_scroll.call_deferred("ensure_control_visible",control)
			elif control == _canvas:
				control.modulate = Color(1.12,1.08,1.0)

func btn(parent: Node, text: String, domain: String, command: String, args: Dictionary = {}, reason: String = "") -> Button:
	var button := HorizonUI.button(parent, text, command.validate_node_name(), func(): action(domain, command, args))
	button.disabled = not reason.is_empty()
	button.tooltip_text = reason
	if not reason.is_empty():
		HorizonUI.notice(parent, reason)
	return button

func card(parent: Node, title: String, description: String = "") -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", HorizonUI.texture_box("panel"))
	parent.add_child(panel)
	var items := HorizonUI.column(panel, 7)
	HorizonUI.label(items, title, 18, HorizonUI.GOLD)
	if not description.is_empty():
		HorizonUI.label(items, description, 14)
	return items

func _base() -> void:
	_art("base")
	var tutorial := card(_body, "Первые шаги", "Открой шахту → добудь руду → продай → купи улучшение. Рабочие требуют зарплату; при нуле денег ручная добыча остаётся бесплатной.")
	HorizonUI.button(tutorial, "В шахту №17", "StartMining", func(): go("mine", "fe"), true)
	HorizonUI.button(tutorial, "Цели сюжета и бесплатные награды", "Objectives", func(): go("story"))

func _art(mode: String) -> void:
	var script = load("res://components/EarthCanvas.gd")
	_canvas = script.new()
	_canvas.custom_minimum_size = Vector2(0, 320)
	_canvas.size_flags_horizontal = SIZE_EXPAND_FILL
	_body.add_child(_canvas)
	_canvas.configure(mode, profile())
	_canvas.location_selected.connect(func(id: String): go(id))
	_canvas.mine_hit.connect(func(position: Vector2):
		var precise := false
		if _canvas.has_method("is_weak_hit"):
			precise = _canvas.is_weak_hit(position)
		var result := GameSession.perform("economy", "tap", {"site":"fe", "precision":precise,"position_norm":[position.x/maxf(1,_canvas.size.x),position.y/maxf(1,_canvas.size.y)],"far_zone":absf(position.x/maxf(1,_canvas.size.x)-0.5)>0.25})
		if result.get("ok", false):
			_update_hud()
			if float(GameMath.game(profile())["stats"].get("taps",0)) <= 1:
				_update_tutorial())

func _mine() -> void:
	if not GameMath.unlocked(profile(), site):
		HorizonUI.label(_body, "Участок пока закрыт. Условия открытия — на карте Земли.")
		HorizonUI.button(_body, "Показать условия", "ShowMap", func(): go("map"))
		return
	_art(site)
	var metrics := live(_body, func():
		var m: Dictionary = GameSession.model("economy").metrics(profile(), site)
		return "Уровень %d · максимум %d\nДобыча %.2f/сек · ручной удар %.2f\nНанято: %d · зарплата %s Г/мин" % [average(), GameMath.site(profile(), site)["peak"], float(m.get("rate_per_second",0)), float(m.get("tap_per_hit",0)), _worker_count(), money(int(ceil(float(m.get("worker_wage_cents_per_minute",0)))))])
	metrics.add_theme_font_size_override("font_size", 13)
	if site == "fe":
		btn(_body, "Продать свободное железо", "economy", "sell", {"resource":"iron_ore", "amount":-1})
		var horizons := HBoxContainer.new()
		_body.add_child(horizons)
		for index in range(11):
			var h := index
			var b := HorizonUI.button(horizons, str(index * 100), "Horizon" + str(index), func(): action("economy", "horizon", {"site":site,"index":h}))
			b.custom_minimum_size = Vector2(54, 44)
			b.disabled = average() < index * 100
		# The horizon strip has its own horizontal scroll, separate from purchases.
		_body.remove_child(horizons)
		var hs := ScrollContainer.new()
		hs.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		_body.add_child(hs)
		hs.add_child(horizons)
	else:
		_extraction()

func _extraction() -> void:
	var model = GameSession.model("sites")
	live(_body, func():
		var info: Dictionary = model.view(profile(), site)
		return "Статус: %s · %s\nОсталось: %.0f сек. · ожидает склад: %d" % [str(info.get("status", "")), str(info.get("phase", "")), float(info.get("remaining_seconds", info.get("phase_remaining_seconds",0))), int(info.get("pending_output",0))])
	if site == "pd":
		for definition in model.lens_definitions():
			var details: Dictionary = definition
			var description := "%s\nЧистота %.0f–%.0f%% · выход %d–%d\nРасход: проба %s Г + цикл %s Г" % [str(details.get("description","")), float(details["quality_min"])*100, float(details["quality_max"])*100, details["yield_min"], details["yield_max"], money(int(details["sample_cost_cents"])), money(int(details["operating_cost_cents"]))]
			var items := card(_body, str(details.get("name", details["id"])), description)
			btn(items, "Выбрать линзу", "sites", "pd_select_lens", {"lens_id":details["id"]})
		btn(_body, "Взять пробу выбранной линзы", "sites", "pd_take_sample", {})
		btn(_body, "Необязательный анализ керна · 20–40 сек.", "sites", "pd_analyze_sample", {"score":0.5})
		btn(_body, "Начать концентрацию", "sites", "pd_start_cycle", {})
		btn(_body, "Авто-линза: сбалансированная", "sites", "pd_set_automatic", {"enabled":true})
		btn(_body, "Остановить авто-линзу", "sites", "pd_set_automatic", {"enabled":false})
	else:
		live(_body, func():
			var info: Dictionary = model.view(profile(), "ir")
			return "Температура %.1f°C · прогноз %s" % [float(info.get("temperature_c",20)), str(info.get("projection",{}))])
		for definition in model.strategy_definitions():
			var details: Dictionary = definition
			var items := card(_body, str(details.get("name", details["id"])), str(details.get("description", "")))
			btn(items, "Выбрать стратегию", "sites", "ir_set_strategy", {"strategy_id":details["id"]})
		btn(_body, "Начать кампанию", "sites", "ir_start_campaign", {})
		btn(_body, "Оплатить охлаждение", "sites", "ir_cool", {})
	btn(_body, "Продолжить ожидающую операцию", "sites", site + "_resume", {})
	btn(_body, "Отменить · понесённые расходы не вернуть", "sites", site + "_cancel", {})

func _purchases() -> void:
	if not GameMath.unlocked(profile(), site):
		HorizonUI.label(_body, "Участок ещё закрыт")
		return
	var kind: String = {"upgrades":"upgrades", "machines":"machines", "workers":"workers"}[tab]
	var quantities := HBoxContainer.new()
	_body.add_child(quantities)
	for count in [1, 10, 100, 0]:
		var n: int = count
		var b := HorizonUI.button(quantities, "MAX" if count == 0 else "×%d" % count, "Count" + str(count), func():
			_buy_count = n
			refresh())
		b.size_flags_horizontal = SIZE_EXPAND_FILL
		b.disabled = _buy_count == count
	var cards: Node = _body
	if tab == "upgrades":
		btn(_body, "Улучшить доступное · лимит текущий кошелёк", "economy", "buy_all", {"site":site,"budget_cents":int(profile()["money_cents"])})
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 8)
		grid.add_theme_constant_override("v_separation", 8)
		_body.add_child(grid)
		cards = grid
	for definition in GameSession.model("economy").definitions(site, kind):
		var d: Dictionary = definition
		var quote: Dictionary = GameSession.model("economy").quote(profile(), site, kind, d["id"], _buy_count)
		var items := card(cards, str(d.get("name", d["id"])), str(d.get("description", d.get("effect", ""))))
		illustration(items, str(d["id"]))
		HorizonUI.label(items, "Уровень %d → %d\n%s\nЦена %d Г" % [int(quote.get("current_level",0)),int(quote.get("level_after",0)),effect_summary(quote.get("effect_before",{}),quote.get("effect_after",{})),int(quote.get("cost_cents",0))/100], 13)
		btn(items, "Купить", "economy", "buy", {"site":site, "kind":kind, "id":d["id"], "count":_buy_count}, "" if quote.get("ok", false) else str(quote.get("message", "Недостаточно средств")))

func _factory() -> void:
	if not GameSession.building_complete("factory"):
		HorizonUI.label(_body,"Завод ещё не построен. Продажа сырой руды доступна без завода.",16)
		HorizonUI.button(_body,"Построить завод","BuildFactory",func(): go("buildings"))
		return
	var selector := OptionButton.new()
	selector.name = "FactoryLine"
	selector.custom_minimum_size.y = 44
	for i in range(5):
		selector.add_item("Линия %d" % (i + 1))
	selector.select(int(ui_state.get("factory_line",0)))
	_body.add_child(selector)
	selector.item_selected.connect(func(index: int): ui_state["factory_line"] = index)
	var quantity := SpinBox.new()
	quantity.name = "FactoryCount"
	quantity.min_value = 1
	quantity.max_value = 100
	quantity.value = int(ui_state.get("factory_count",1))
	quantity.custom_minimum_size.y = 44
	_body.add_child(quantity)
	quantity.value_changed.connect(func(value: float): ui_state["factory_count"] = int(value))
	for index in range(5):
		var line_index := index
		var line_card := card(_body, "Линия %d" % (index + 1))
		live(line_card, func():
			var line: Dictionary = GameMath.game(profile()).get("factory",[])[line_index]
			var active: Dictionary = line.get("active",{})
			var pending: Dictionary = line.get("pending",{})
			if not pending.is_empty():
				return "Готовая партия ожидает места на складе"
			if active.is_empty():
				return "Свободна · в очереди %d партий" % line.get("queue",[]).size()
			return "%s · осталось %.0f сек. · изделий %d" % [str(active.get("recipe_id",active.get("recipe",""))),float(active.get("seconds_left",0)),int(active.get("units_remaining",0))])
	for recipe in GameMath.records("recipes"):
		var output := str(recipe["output"])
		var id := str(recipe["id"])
		var title := str(GameMath.record("resources",output).get("display_name",output))
		var items := card(_body, title, "Входы: %s\nРасходы %s Г · продажа %s Г / шт." % [str(recipe["inputs_json"]), money(int(recipe["cash_cost_cents"])), money(int(recipe["output_sale_cents"]))])
		HorizonUI.button(items, "Запустить на выбранной линии", "Queue" + id, func(): action("economy", "queue", {"recipe":id,"line":int(ui_state.get("factory_line",0)),"count":int(ui_state.get("factory_count",1))}))

func _warehouse() -> void:
	HorizonUI.label(_body, "Занято %d / %d. Резервы не продаются." % [GameMath.stored(profile()), GameMath.capacity(profile())], 15)
	for resource in GameMath.records("resources"):
		var id := str(resource["id"])
		if str(resource["sale_price_cents"]).is_empty():
			continue
		var items := card(_body, str(resource["display_name"]), "Всего %d · свободно %d · резерв %d\nЦена %s Г / шт." % [int(profile()["inventory"].get(id,0)), GameMath.free_amount(profile(), id), GameMath.reserved(profile(),id), money(int(resource["sale_price_cents"]))])
		btn(items, "Продать свободный запас", "economy", "sell", {"resource":id,"amount":-1})
	btn(_body, "Продать все свободные материалы", "economy", "sell_all", {})
	for token in GameMath.game(profile())["reservations"]:
		var reservation := card(_body,"Резерв: "+str(token),str(GameMath.game(profile())["reservations"][token]))
		if str(token).begins_with("event:") or str(token).begins_with("research:") or str(token).begins_with("manual:"):
			btn(reservation,"Освободить резерв для продажи / производства","economy","unreserve",{"token":token})

func illustration(parent: Node, key: String) -> TextureRect:
	var image := TextureRect.new()
	image.texture = ArtLibrary.texture_named(key, "res://assets/ui/emblem.svg")
	image.custom_minimum_size = Vector2(0,72)
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.mouse_filter = MOUSE_FILTER_IGNORE
	parent.add_child(image)
	return image

func live(parent: Node, value: Callable) -> Label:
	var label := HorizonUI.label(parent, str(value.call()), 14)
	_live.append([label, value])
	return label

static func effect_summary(before: Dictionary, after: Dictionary) -> String:
	var lines: PackedStringArray = []
	var units := {"tap_per_hit":"железа/удар", "rate_per_second":"ресурса/сек", "worker_wage_cents_per_minute":"сотых Г/мин", "storage_capacity":"мест на складе", "speed_multiplier":"скорость ×", "output_multiplier":"добыча ×", "price_discount":"скидка","wage_multiplier":"расход зарплаты ×","crit_chance":"шанс крита","weak_chance":"шанс слабой точки"}
	for key in units:
		var a := float(before.get(key,0))
		var b := float(after.get(key,a))
		if not is_equal_approx(a,b):
			lines.append("%.3f → %.3f %s" % [a,b,units[key]])
	if lines.is_empty():
		return "Эффект зависит от работающей смены или выбранного горизонта"
	return "\n".join(lines)

func _event_actions() -> void:
	var actions := card(_body,"Действия событий","Посещение окна не выдаёт наград. Сначала выполни реальную цель, затем получи награду в карточке события выше.")
	btn(actions,"EV01 · выбрать ручную разработку жилы","meta","event_action",{"id":"EV01","choice":"manual"})
	btn(actions,"EV01 · отправить жилу в резерв под завод","meta","event_action",{"id":"EV01","choice":"auto_sort"})
	HorizonUI.button(actions,"EV04 · добровольный анализ керна","EventPdScan",func(): go("mine","pd"))
	btn(actions,"EV05 · отгрузить 1 собственный Pd-катализатор","meta","event_action",{"id":"EV05"})
	HorizonUI.button(actions,"EV06 · выбрать надёжную кампанию И-9","EventIrRoute",func(): go("mine","ir"))
	var reports: Array = GameMath.game(profile()).get("progression",{}).get("geology",{}).get("reports",[])
	if reports.size() >= 2:
		HorizonUI.label(actions,"EV08 · сравнить два документа",15,HorizonUI.GOLD)
		var first := _choice(actions,reports,"id")
		var second := _choice(actions,reports,"id")
		second.select(1)
		HorizonUI.button(actions,"Сверить документы","EventCompare",func(): action("meta","event_action",{"id":"EV08","first_id":first.get_item_metadata(first.selected),"second_id":second.get_item_metadata(second.selected)}))
	else:
		HorizonUI.notice(actions,"EV08: получи два разных геологических отчёта; повторно отправлять один документ недостаточно.")

func _research_actions() -> void:
	var model = GameSession.model("research")
	var owned: Dictionary = GameMath.game(profile()).get("progression",{}).get("mastery" if tab == "mastery" else "research",{})
	for id in owned:
		var description: Dictionary = model.describe(profile(),str(id))
		if int(owned[id]) <= 0:
			continue
		var command := str(description.get("action",""))
		var mode := str(description.get("mode",""))
		if command.is_empty() and mode != "view":
			continue
		var items := card(_body, str(id) + " · " + str(description.get("record",{}).get("name",id)), str(description.get("effect","")))
		if mode == "view":
			for key in description.get("current_state",{}):
				HorizonUI.label(items, str(key) + ": " + str(description["current_state"][key]),13)
		if not command.is_empty():
			_runtime_controls(items,str(id),command)

func _runtime_controls(items: VBoxContainer, id: String, command: String) -> void:
	match command:
		"reserve_items":
			var resource := _choice(items, GameMath.records("resources").filter(func(row): return not str(row.get("sale_price_cents","")).is_empty()), "display_name")
			var amount := _amount(items, "Количество в резерве", 0, GameMath.capacity(profile()))
			HorizonUI.button(items, "Сохранить резерв", "Reserve"+id, func():
				var values: Dictionary = {}
				values[str(resource.get_item_metadata(resource.selected))] = int(amount.value)
				action("research",command,{"id":id,"items":values}))
			btn(items,"Снять этот резерв","research",command,{"id":id,"release":true})
		"set_cash_reserve":
			var amount := _amount(items,"Резерв, Г (0 — снять)",0,int(profile()["money_cents"])/100)
			amount.step = 0.01
			HorizonUI.label(items,"Свободный бюджет: %s Г" % money(GameMath.available_money(profile())),13)
			HorizonUI.button(items,"Сохранить целевой резерв","CashReserve"+id,func(): action("research",command,{"id":id,"amount_cents":int(round(amount.value*100))}))
		"preset":
			var slot := _amount(items,"Слот шаблона",0,1)
			for operation in ["save","load"]:
				var op: String = operation
				HorizonUI.button(items,"Сохранить настройки" if op == "save" else "Применить настройки","Preset"+op+id,func(): action("research",command,{"id":id,"slot":int(slot.value),"operation":op}))
		"queue_recipe_chain":
			var recipe := _choice(items,GameMath.records("recipes"),"output")
			var line := _amount(items,"Линия (1–5)",1,5)
			var count := _amount(items,"Изделий",1,100)
			HorizonUI.button(items,"Запланировать производство","RecipePlan"+id,func(): action("research",command,{"id":id,"recipe_ids":[recipe.get_item_metadata(recipe.selected)],"line":int(line.value)-1,"count":int(count.value)}))
		"select_pd_lens":
			var lens := _choice(items,GameSession.model("sites").lens_definitions(),"name")
			HorizonUI.button(items,"Выбрать линзу","ResearchLens"+id,func(): action("research",command,{"id":id,"lens_id":lens.get_item_metadata(lens.selected)}))
		"select_ir_strategy":
			var strategy := _choice(items,GameSession.model("sites").strategy_definitions(),"name")
			HorizonUI.button(items,"Выбрать маршрут кампании","ResearchStrategy"+id,func(): action("research",command,{"id":id,"strategy_id":strategy.get_item_metadata(strategy.selected)}))
		"set_pd_auto":
			btn(items,"Включить сбалансированный режим","research",command,{"id":id,"enabled":true})
			btn(items,"Выключить автоматический режим","research",command,{"id":id,"enabled":false})
		"set_preference":
			var picker := OptionButton.new()
			for label in ["balanced","income","construction"]:
				picker.add_item(label)
			picker.custom_minimum_size.y = 44
			items.add_child(picker)
			HorizonUI.button(items,"Сохранить приоритет","Preference"+id,func(): action("research",command,{"id":id,"field":"cooling_mode" if id == "IR_SK06" else "priorities","value":picker.get_item_text(picker.selected)}))
		_:
			btn(items,"Выполнить / получить результат","research",command,{"id":id})

func _choice(parent: Node, records: Array, label_field: String) -> OptionButton:
	var picker := OptionButton.new()
	picker.custom_minimum_size.y = 44
	for record in records:
		picker.add_item(str(record.get(label_field,record.get("id",""))))
		picker.set_item_metadata(picker.item_count-1,str(record.get("id","")))
	parent.add_child(picker)
	return picker

func _amount(parent: Node, label: String, minimum: int, maximum: int) -> SpinBox:
	HorizonUI.label(parent,label,13)
	var input := SpinBox.new()
	input.min_value = minimum
	input.max_value = maximum
	input.value = minimum
	input.custom_minimum_size.y = 44
	parent.add_child(input)
	return input

func _worker_count() -> int:
	var total := 0
	for number in GameMath.site(profile(), site)["workers"].values():
		total += int(number)
	return total

func average() -> int:
	var sum := 0
	for level in GameMath.site(profile(), site)["upgrades"].values():
		sum += int(level)
	return sum / 10

static func compact(value: float) -> String:
	for entry in [[1000000000.0,"B"],[1000000.0,"M"],[1000.0,"K"]]:
		if value >= entry[0]:
			return "%.2f%s" % [value/entry[0],entry[1]]
	return str(int(value)) if is_equal_approx(value,roundf(value)) else "%.2f" % value

static func money(cents: int) -> String:
	return "%0.2f" % (float(cents) / 100.0)

func _on_message(text: String) -> void:
	if is_instance_valid(_status):
		_status.text = text

func _update_hud() -> void:
	if not is_instance_valid(_hud):
		return
	_hud.text = "%s Г  ·  Fe %s  ·  ◇ %s" % [compact(float(profile()["money_cents"])/100),compact(float(profile()["inventory"].get("iron_ore",0))),compact(float(profile()["shards"]))]
	if bool(GameMath.game(profile()).get("qa_fixture",false)):
		_hud.text = "[QA] " + _hud.text
	if tab not in ["mine","upgrades","equipment","machines","workers"]:
		_hud.text += "\nОИ %d · %s" % [profile()["research_points"],site.to_upper()]
	_hud.tooltip_text = "%s Г · железо %d · осколки %d" % [money(int(profile()["money_cents"])),profile()["inventory"].get("iron_ore",0),profile()["shards"]]

func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < 0.5 or not SaveService.has_profile():
		return
	_elapsed = 0.0
	_update_hud()
	AudioService.set_mine_ambience(tab == "mine" and site == "fe" and int(GameMath.site(profile(),"fe")["machines"].get("iron_conveyor",0)) > 0)
	for entry in _live:
		if is_instance_valid(entry[0]):
			entry[0].text = str(entry[1].call())
	if is_instance_valid(_canvas):
		_canvas.update_state(profile())
