extends Control

var _draft: Dictionary
var _notice: Label
var _sliders: Dictionary = {}

func _ready() -> void:
	_draft = GameState.settings.duplicate(true)
	var items := HorizonUI.screen(self, true)
	HorizonUI.button(items, "‹  Назад без изменений", "Back", _cancel)
	HorizonUI.label(items, "НАСТРОЙКИ", 26, HorizonUI.GOLD)
	var scroll := ScrollContainer.new()
	scroll.name = "SettingsScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	items.add_child(scroll)
	var content := HorizonUI.column(scroll, 10)
	for key in ["master", "music", "sfx", "ambience"]:
		_volume(content, key, {"master":"Общая громкость", "music":"Музыка", "sfx":"Эффекты", "ambience":"Окружение"}[key])
	_toggle(content, "vibration", "Вибрация")
	_choice(content, "quality", "Качество графики", ["Высокое", "Энергосбережение"], ["high", "low"])
	_choice(content, "fps", "Частота кадров", ["60 FPS", "30 FPS"], [60, 30])
	_toggle(content, "reduce_motion", "Уменьшить анимацию")
	HorizonUI.notice(content, "Музыка и фоновые звуки ещё не добавлены. Эффекты можно проверить кнопкой ниже. На компьютере вибрация не используется.")
	HorizonUI.button(content, "Проверить звук", "TestSound", _preview_sound)
	_notice = HorizonUI.notice(items, "Громкость — предпрослушивание. Изменения нужно сохранить.")
	HorizonUI.button(items, "Сохранить настройки", "SaveSettings", _save, true)

func _volume(parent: Node, key: String, title: String) -> void:
	var value := HorizonUI.label(parent, title + "  ·  %d%%" % roundi(float(_draft[key]) * 100), 15)
	var slider := HSlider.new()
	slider.name = key.capitalize() + "Volume"
	slider.custom_minimum_size.y = 44
	slider.max_value = 100
	slider.step = 1
	slider.value = float(_draft[key]) * 100
	parent.add_child(slider)
	_sliders[key] = slider
	slider.value_changed.connect(func(number: float):
		_draft[key] = number / 100.0
		value.text = title + "  ·  %d%%" % number
		AudioService.apply_settings(_draft))

func _toggle(parent: Node, key: String, title: String) -> void:
	var toggle := CheckButton.new()
	toggle.name = key.capitalize()
	toggle.text = title
	toggle.custom_minimum_size.y = 44
	toggle.button_pressed = _draft[key]
	parent.add_child(toggle)
	toggle.toggled.connect(func(on: bool): _draft[key] = on)

func _choice(parent: Node, key: String, title: String, titles: Array, values: Array) -> void:
	HorizonUI.label(parent, title, 15)
	var choice := OptionButton.new()
	choice.name = key.capitalize()
	choice.custom_minimum_size.y = 44
	for option in titles:
		choice.add_item(option)
	choice.select(values.find(_draft[key]))
	parent.add_child(choice)
	choice.item_selected.connect(func(index: int): _draft[key] = values[index])

func _preview_sound() -> void:
	_notice.text = "Общая громкость или эффекты отключены." if _draft["master"] == 0.0 or _draft["sfx"] == 0.0 else "Воспроизведён прототипный звук интерфейса."

func _cancel() -> void:
	AudioService.apply_settings(GameState.settings)
	SceneRouter.go_to(&"menu")

func _save() -> void:
	var result := SaveService.save_settings(_draft)
	if result == OK:
		AudioService.apply_settings(GameState.settings)
		_notice.text = "Настройки сохранены на устройстве."
	else:
		_notice.text = "Ошибка записи. Настройки не сохранены; профиль не изменён."

func _exit_tree() -> void:
	AudioService.apply_settings(GameState.settings)
