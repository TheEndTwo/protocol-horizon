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
var _live: Array = []
var _canvas: Control
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
	_scroll = ScrollContainer.new()
	_scroll.name = "ContentScroll"
	_scroll.size_flags_vertical = SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	shell.add_child(_scroll)
	_body = HorizonUI.column(_scroll, 10)
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
	_canvas = null
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	_selector.select(TABS.keys().find(tab))
	_update_hud()
	var site_name: String = {"fe":"Шахта №17 · Fe", "pd":"Комплекс П-7 · Pd", "ir":"Сектор И-9 · Ir"}[site]
	HorizonUI.label(_body, TABS[tab] + "  /  " + site_name, 19, HorizonUI.GOLD)
	if tab in ["equipment", "specialists", "cases", "season", "events", "shop"]:
		load("res://gameplay/ui/MetaPanels.gd").render(self, _body, tab)
	elif tab in ["research", "mastery", "geology", "contracts", "buildings", "story", "expansion", "network", "map"]:
		load("res://gameplay/ui/ProgressionPanels.gd").render(self, _body, tab)
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
		var result := GameSession.perform("economy", "tap", {"site":"fe", "precision":precise})
		if result.get("ok", false):
			_update_hud()
			AudioService.tap())

func _mine() -> void:
	if not GameMath.unlocked(profile(), site):
		HorizonUI.label(_body, "Участок пока закрыт. Условия открытия — на карте Земли.")
		HorizonUI.button(_body, "Показать условия", "ShowMap", func(): go("map"))
		return
	_art(site)
	var metrics := live(_body, func():
		var m: Dictionary = GameSession.model("economy").metrics(profile(), site)
		return "Уровень %d · исторический максимум %d\n%s" % [average(), GameMath.site(profile(), site)["peak"], str(m)])
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
	for target in ["upgrades", "equipment", "machines", "workers"]:
		var destination: String = target
		HorizonUI.button(_body, TABS[target], "Mine" + target, func(): go(destination))

func _extraction() -> void:
	var model = GameSession.model("sites")
	var data: Dictionary = model.view(profile(), site)
	HorizonUI.label(_body, str(data), 13)
	if site == "pd":
		for definition in model.lens_definitions():
			var details: Dictionary = definition
			var items := card(_body, str(details.get("name", details.get("id", "Линза"))), str(details))
			btn(items, "Начать отбор", "sites", "pd_start", {"lens":details["id"]})
		btn(_body, "Авто-линза: сбалансированная", "sites", "pd_auto", {"enabled":true})
		btn(_body, "Остановить авто-линзу", "sites", "pd_auto", {"enabled":false})
		btn(_body, "Анализ керна", "sites", "pd_analyze", {})
	else:
		for definition in model.strategy_definitions():
			var details: Dictionary = definition
			var items := card(_body, str(details.get("name", details.get("id", "Кампания"))), str(details))
			btn(items, "Начать кампанию", "sites", "ir_start", {"strategy":details["id"]})
		btn(_body, "Включить охлаждение", "sites", "ir_cooling", {"enabled":true})
		btn(_body, "Выключить охлаждение", "sites", "ir_cooling", {"enabled":false})

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
		HorizonUI.label(items, str(quote), 13)
		btn(items, "Купить", "economy", "buy", {"site":site, "kind":kind, "id":d["id"], "count":_buy_count}, "" if quote.get("ok", false) else str(quote.get("message", "Недостаточно средств")))

func _factory() -> void:
	live(_body, func(): return "Линии: " + str(GameMath.game(profile()).get("factory", [])))
	for recipe in GameMath.records("recipes"):
		var items := card(_body, str(recipe["output"]), "Входы: %s · расходы %s Г · цена продажи %s Г" % [str(recipe["inputs_json"]), money(int(recipe["cash_cost_cents"])), money(int(recipe["output_sale_cents"]))])
		for i in range(5):
			btn(items, "Запустить на линии %d" % (i + 1), "economy", "queue", {"recipe":recipe["id"], "line":i, "count":1})

func _warehouse() -> void:
	HorizonUI.label(_body, "Занято %d / %d. Резервы не продаются." % [GameMath.stored(profile()), GameMath.capacity(profile())], 15)
	for resource in GameMath.records("resources"):
		var id := str(resource["id"])
		if str(resource["sale_price_cents"]).is_empty():
			continue
		var items := card(_body, str(resource["display_name"]), "Всего %d · свободно %d · резерв %d\nЦена %s Г / шт." % [int(profile()["inventory"].get(id,0)), GameMath.free_amount(profile(), id), GameMath.reserved(profile(),id), money(int(resource["sale_price_cents"]))])
		btn(items, "Продать свободный запас", "economy", "sell", {"resource":id,"amount":-1})
	btn(_body, "Продать все свободные материалы", "economy", "sell_all", {})

func live(parent: Node, value: Callable) -> Label:
	var label := HorizonUI.label(parent, str(value.call()), 14)
	_live.append([label, value])
	return label

func average() -> int:
	var sum := 0
	for level in GameMath.site(profile(), site)["upgrades"].values():
		sum += int(level)
	return sum / 10

static func money(cents: int) -> String:
	return "%0.2f" % (float(cents) / 100.0)

func _on_message(text: String) -> void:
	if is_instance_valid(_status):
		_status.text = text

func _update_hud() -> void:
	if not is_instance_valid(_hud):
		return
	_hud.text = "%s Г   ·   Fe %d   ·   ◇ %d\nОИ %d   ·   %s" % [money(int(profile()["money_cents"])), profile()["inventory"].get("iron_ore",0), profile()["shards"], profile()["research_points"], site.to_upper()]

func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < 0.5 or not SaveService.has_profile():
		return
	_elapsed = 0.0
	_update_hud()
	for entry in _live:
		if is_instance_valid(entry[0]):
			entry[0].text = str(entry[1].call())
	if is_instance_valid(_canvas):
		_canvas.update_state(profile())
