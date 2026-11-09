extends SceneTree

func _initialize() -> void:
	check.call_deferred()

func check() -> void:
	var paths := ["res://scenes/world/EarthScreen.gd", "res://autoload/GameSession.gd", "res://components/ResearchGraph.gd", "res://components/ArtLibrary.gd", "res://components/FeatureControls.gd"]
	for path in paths:
		var script = load(path)
		if script == null or not script.can_instantiate():
			printerr("Failed to compile: " + path)
			quit(1)
			return
	print("Earth shell scripts compile")
	quit(0)
