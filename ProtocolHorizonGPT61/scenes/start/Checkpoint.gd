extends Control

func _ready() -> void:
	if not SaveService.has_profile():
		SceneRouter.go_to.call_deferred(&"menu")
		return
	var items := HorizonUI.screen(self)
	HorizonUI.label(items, "ЗЕМЛЯ  /  УЧАСТОК №17", 13, HorizonUI.GOLD)
	HorizonUI.spacer(items)
	HorizonUI.label(items, "ПЕРВАЯ\nСМЕНА ВПЕРЕДИ", 32)
	HorizonUI.label(items, "Участок зарегистрирован.\nПрофиль сохранён на этом устройстве.", 17)
	var profile := GameState.profile
	HorizonUI.label(items, "Гелионы: %d Г  ·  Железо: %d\nОсколки: %d  ·  Очки исследований: %d" % [int(profile["money_cents"]) / 100, profile["inventory"]["iron_ore"], profile["shards"], profile["research_points"]], 16, HorizonUI.GOLD)
	HorizonUI.label(items, "Конец доступного этапа 1.\nБаза и добыча пока не реализованы.\nВступление не выдаёт наград.", 15, HorizonUI.MUTED)
	HorizonUI.spacer(items)
	HorizonUI.button(items, "В главное меню", "Menu", func(): SceneRouter.go_to(&"menu"), true)
