extends Control

@export var menu_mode := false
@onready var safe_margin: MarginContainer = $SafeMargin
@onready var title: Label = $SafeMargin/Column/Title
@onready var status: Label = $SafeMargin/Column/Status
@onready var details: Label = $SafeMargin/Column/Details
@onready var action: Button = $SafeMargin/Column/Action

func _ready() -> void:
	get_viewport().size_changed.connect(_update_safe_area)
	_update_safe_area()
	action.pressed.connect(_on_action)
	if not ContentRegistry.is_loaded:
		status.text = "ОШИБКА ЗАГРУЗКИ"
		details.text = "Каталоги не прошли проверку.\nПодробности — в журнале Godot."
		action.disabled = true
		return
	if menu_mode:
		title.text = "ТЕХНИЧЕСКОЕ\nМЕНЮ"
		status.text = "ПЕРЕХОД ВЫПОЛНЕН"
		details.text = "Маршрутизатор открыл отдельную сцену.\n\nГлавное меню, настройки и новая игра\nбудут реализованы только после\nприёмки этапа 0."
		action.text = "Назад"
	else:
		status.text = "КАТАЛОГИ ЗАГРУЖЕНЫ"
		details.text = ("%d исследований · %d навыка\n%d специалистов · %d сюжетных сцен\n%d VIP-рангов · %d товаров · %d кейсов\n%d шаблонов сезонных заданий" % [
			ContentRegistry.get_count(&"research"), ContentRegistry.get_count(&"mastery"),
			ContentRegistry.get_count(&"specialists"), ContentRegistry.get_count(&"story"),
			ContentRegistry.get_count(&"vip"), ContentRegistry.get_count(&"shop"),
			ContentRegistry.get_count(&"cases"), ContentRegistry.get_count(&"season_tasks")])

func _on_action() -> void:
	var result := SceneRouter.go_to(&"start" if menu_mode else &"menu")
	if result != OK and result != ERR_BUSY:
		status.text = "НЕ УДАЛОСЬ ОТКРЫТЬ СЦЕНУ"

func _update_safe_area() -> void:
	var view_size := get_viewport_rect().size
	var safe_rect := Rect2(Vector2.ZERO, view_size)
	if OS.has_feature("mobile"):
		var display_safe := DisplayServer.get_display_safe_area()
		if display_safe.has_area():
			safe_rect = get_viewport().get_screen_transform().affine_inverse() * Rect2(display_safe)
	var insets := safe_insets(view_size, safe_rect)
	for side in insets:
		safe_margin.add_theme_constant_override("margin_" + side, insets[side])

static func safe_insets(view_size: Vector2, safe_rect: Rect2) -> Dictionary:
	return {
		"left": 24 + ceili(maxf(0.0, safe_rect.position.x)),
		"top": 24 + ceili(maxf(0.0, safe_rect.position.y)),
		"right": 24 + ceili(maxf(0.0, view_size.x - safe_rect.end.x)),
		"bottom": 24 + ceili(maxf(0.0, view_size.y - safe_rect.end.y)),
	}
