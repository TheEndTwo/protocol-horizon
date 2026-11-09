extends Control

func _ready() -> void:
	if ContentRegistry.is_loaded:
		SceneRouter.go_to.call_deferred(&"menu")
	else:
		var items := HorizonUI.screen(self, true)
		HorizonUI.label(items, "Не удалось загрузить каталоги", 24, HorizonUI.GOLD)
		HorizonUI.label(items, "\n".join(ContentRegistry.errors), 14)
