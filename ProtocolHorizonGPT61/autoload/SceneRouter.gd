extends Node

const ROUTES := {
	&"start": "res://scenes/start/Splash.tscn",
	&"menu": "res://scenes/start/MainMenu.tscn",
}
var _changing := false

func go_to(route: StringName) -> Error:
	if not ROUTES.has(route):
		return ERR_DOES_NOT_EXIST
	if _changing:
		return ERR_BUSY
	if not GameState.is_content_ready():
		return ERR_UNAVAILABLE
	_changing = true
	var result := get_tree().change_scene_to_file(ROUTES[route])
	if result == OK:
		GameState.current_route = route
		get_tree().scene_changed.connect(_on_scene_changed, CONNECT_ONE_SHOT)
	else:
		_changing = false
	return result

func _on_scene_changed() -> void:
	_changing = false
