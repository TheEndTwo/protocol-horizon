extends SceneTree

const Registry = preload("res://autoload/ContentRegistry.gd")
var failures: PackedStringArray = []

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func _run() -> void:
	var registry := root.get_node("ContentRegistry")
	var state := root.get_node("GameState")
	var router := root.get_node("SceneRouter")
	var start_screen = load("res://components/HorizonUI.gd")
	check(registry.is_loaded, "Catalog loading failed: " + str(registry.errors))
	if not registry.is_loaded:
		printerr(failures)
		quit(1)
		return
	check(registry.source_file_count == 17, "Expected all 17 CSV/JSON sources")
	var expected := {"research": 140, "mastery": 24, "specialists": 80, "story": 20,
		"dialogue": 20, "vip": 11, "shop": 11, "cases": 5, "season_tasks": 18,
		"events": 8, "resources": 19, "recipes": 9}
	for catalog in expected:
		check(registry.get_count(catalog) == expected[catalog], "Wrong count: " + catalog)
	check(not registry.get_record(&"research", "A01").is_empty(), "research:A01 missing")
	check(not registry.get_record(&"story", "A01").is_empty(), "story:A01 missing")
	check(registry.get_record(&"research", "A01") != registry.get_record(&"story", "A01"), "ID namespaces collided")
	var record: Dictionary = registry.get_record(&"research", "A01")
	record["id"] = "changed"
	check(registry.get_record(&"research", "A01")["id"] == "A01", "Registry exposed mutable source")
	var spec := {"id_field": "id", "count": 2, "required_fields": ["id", "name"]}
	check(not Registry.validate_records([{"id": "x", "name": "a"}, {"id": "x", "name": "b"}], spec).is_empty(), "Duplicate IDs accepted")
	check(not Registry.validate_records([{"id": ""}], spec).is_empty(), "Malformed record accepted")
	check(state.SCHEMA_VERSION == 1 and state.SEASON_LEVEL_CAP == 60, "Master overrides lost")
	check(state.SAVE_PATH == "user://protocol_horizon_gpt61_save_v1.json", "Save namespace mismatch")
	check(ProjectSettings.get_setting("display/window/stretch/mode") == "canvas_items", "Wrong stretch mode")
	check(ProjectSettings.get_setting("display/window/handheld/orientation") == 1, "Not portrait")
	check(start_screen.safe_insets(Vector2(432, 936), Rect2(0, 44, 432, 858)) == {"left":24, "top":64, "right":24, "bottom":54}, "Safe-area conversion")
	check(router.go_to(&"not_a_route") == ERR_DOES_NOT_EXIST, "Unknown route accepted")
	check(router.go_to(&"start") == OK, "Start route failed")
	for frame in range(12):
		await process_frame
	check(current_scene != null and current_scene.name == "MainMenu", "Splash did not immediately open menu")
	if failures.is_empty():
		print("FOUNDATION PASS: catalogs, IDs, schema, portrait, safe-area math, immediate splash/menu")
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: " + failure)
		quit(1)
