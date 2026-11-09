extends Control

func _ready() -> void:
	var candidate := GameState.profile.duplicate(true)
	if candidate.is_empty():
		SceneRouter.go_to.call_deferred(&"menu")
		return
	candidate["route"] = "earth"
	if SaveService.commit_profile(candidate) == OK:
		SceneRouter.go_to.call_deferred(&"earth")
