extends Control

var _speaker: Label
var _text: Label
var _progress: Label
var _notice: Label
var _next: Button
var _lines: Array
var _busy := false

func _ready() -> void:
	if not SaveService.has_profile():
		SceneRouter.go_to.call_deferred(&"menu")
		return
	_lines = ContentRegistry.get_record(&"dialogue", "A01")["lines"]
	var items := HorizonUI.screen(self)
	HorizonUI.label(items, "A01  /  ПОСЛЕДНИЕ СРЕДСТВА", 13, HorizonUI.GOLD)
	HorizonUI.button(items, "‹  В меню", "Menu", func(): SceneRouter.go_to(&"menu"))
	HorizonUI.spacer(items)
	_speaker = HorizonUI.label(items, "", 21, HorizonUI.GOLD)
	_text = HorizonUI.label(items, "", 20)
	_text.custom_minimum_size.y = 180
	_progress = HorizonUI.label(items, "", 13, HorizonUI.MUTED)
	_notice = HorizonUI.notice(items, "Позиция диалога сохраняется автоматически.")
	_next = HorizonUI.button(items, "Далее", "Next", _advance, true)
	HorizonUI.button(items, "Пропустить вступление", "Skip", _finish)
	_render()

func _render() -> void:
	var line := int(GameState.profile["story"]["line"])
	if line < 0 or line >= _lines.size():
		_notice.text = "Не удалось прочитать позицию диалога."
		_next.disabled = true
		return
	_speaker.text = _lines[line]["speaker"]
	_text.text = _lines[line]["text"]
	_progress.text = "%d / %d" % [line + 1, _lines.size()]
	_next.text = "Завершить вступление" if line == _lines.size() - 1 else "Далее"

func _advance() -> void:
	if int(GameState.profile["story"]["line"]) + 1 >= _lines.size():
		_finish()
		return
	var next := GameState.profile.duplicate(true)
	next["story"]["line"] += 1
	if _commit(next):
		_render()

func _finish() -> void:
	var next := GameState.profile.duplicate(true)
	next["story"]["intro_seen"] = true
	next["route"] = "checkpoint"
	if _commit(next):
		SceneRouter.go_to(&"checkpoint")

func _commit(next: Dictionary) -> bool:
	if _busy:
		return false
	_busy = true
	var result := SaveService.commit_profile(next)
	_busy = false
	if result != OK:
		_notice.text = "Не удалось сохранить. Попробуй снова; прогресс не изменён."
	return result == OK
