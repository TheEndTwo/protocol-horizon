extends Control

var _notice: Label
var _busy := false

func _ready() -> void:
	var items := HorizonUI.screen(self)
	HorizonUI.label(items, "ГЕЛИОС  /  ЗЕМНОЙ КОНТУР", 12, HorizonUI.GOLD)
	var emblem := TextureRect.new()
	emblem.texture = preload("res://assets/ui/emblem.svg")
	emblem.custom_minimum_size = Vector2(64, 64)
	emblem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	emblem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	items.add_child(emblem)
	HorizonUI.label(items, "ПРОТОКОЛ\nГОРИЗОНТ", 38)
	HorizonUI.label(items, "Каждая глубина хранит свою тайну.", 15, HorizonUI.GOLD)
	HorizonUI.spacer(items)
	HorizonUI.label(items, "ГЛАВА I  /  ЗЕМЛЯ", 12, HorizonUI.GOLD)
	HorizonUI.button(items, "Новая игра", "NewGame", _request_new, not SaveService.has_profile())
	var resume := HorizonUI.button(items, "Продолжить", "Continue", _continue, SaveService.has_profile())
	resume.disabled = not SaveService.has_profile()
	HorizonUI.button(items, "Настройки", "Settings", func(): SceneRouter.go_to(&"settings"))
	_notice = HorizonUI.notice(items, "Нет сохранённого профиля" if not SaveService.has_profile() else "Профиль сохранён на этом устройстве")
	if not SaveService.status_message.is_empty():
		_notice.text = SaveService.status_message
	var footer := HorizonUI.label(items, "ЭТАП 1  ·  ОФЛАЙН  ·  БЕЗ АККАУНТА", 11, HorizonUI.MUTED)
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

func _request_new() -> void:
	if _busy or has_node("ConfirmNewGame"):
		return
	if SaveService.requires_reset_confirmation():
		HorizonUI.confirm(self, "Текущий профиль на этом устройстве будет заменён. Настройки останутся. Без подтверждения ничего не изменится.", _new_game)
	else:
		_new_game()

func _new_game() -> void:
	if _busy:
		return
	_busy = true
	var result := SaveService.new_game()
	if result != OK:
		_notice.text = "Не удалось сохранить новую игру. Старый профиль не заменён."
		_busy = false
	elif SceneRouter.go_to(&"intro") != OK:
		_notice.text = "Профиль сохранён, но не удалось открыть вступление."
		_busy = false

func _continue() -> void:
	if not _busy and SaveService.has_profile():
		var result := SceneRouter.go_to(StringName(GameState.profile["route"]))
		if result != OK:
			_notice.text = "Не удалось открыть сохранённую сцену."
