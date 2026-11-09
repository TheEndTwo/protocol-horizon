class_name EarthCanvas
extends Control

signal location_selected(id: String)
signal mine_hit(position: Vector2)

const GameMathScript = preload("res://gameplay/GameMath.gd")
const SITE_KEYS := ["fe", "pd", "ir"]
const BASE_LOCATIONS := [
	{"id":"mine", "label":"Шахта", "art":"res://assets/placeholders/building_mine.svg"},
	{"id":"geology", "label":"Геология", "art":"res://assets/placeholders/building_geology.svg"},
	{"id":"research", "label":"Наука", "art":"res://assets/placeholders/building_research.svg"},
	{"id":"factory", "label":"Фабрика", "art":"res://assets/placeholders/building_factory.svg"},
	{"id":"warehouse", "label":"Склад", "art":"res://assets/placeholders/building_warehouse.svg"},
	{"id":"trade", "label":"Торговля", "art":"res://assets/placeholders/building_trade.svg"},
	{"id":"hq", "label":"Штаб", "art":"res://assets/placeholders/building_hq.svg"},
	{"id":"power", "label":"Энергия", "art":"res://assets/placeholders/building_power.svg"},
	{"id":"map", "label":"Карта", "art":"res://assets/placeholders/building_map.svg"},
	{"id":"network", "label":"Сеть", "art":"res://assets/placeholders/building_network.svg"},
]
const BACKGROUNDS := {
	"base":"res://assets/placeholders/base_panorama.svg",
	"fe":"res://assets/placeholders/fe_rock_face.svg",
	"pd":"res://assets/placeholders/pd_geology_lens.svg",
	"ir":"res://assets/placeholders/ir_vertical_drill.svg",
}
const MAX_VISIBLE_HORIZONS := 10
const MAX_VISIBLE_MACHINES := 5
const MAX_VISIBLE_WORKERS := 5
const WEAK_POINT_HIT_RADIUS := 22.0
const WORKER_SPARK_CLEARANCE := 24.0

var mode: String = "base"

var _profile: Dictionary = {}
var _visual_site_key := "fe"
var _built := false
var _reduce_motion := false
var _horizon_signature := -1
var _machine_signature := ""
var _worker_signature := ""
var _worker_activity_signature := ""
var _depth_layers: Array[TextureRect] = []
var _machine_nodes: Array[TextureRect] = []
var _weak_point_marker: TextureRect
var _anomaly_marker: TextureRect
var _factory_icon: TextureRect
var _workers: Array[Dictionary] = []
var _bursts: Array[Dictionary] = []
var _burst_version := 0
var _visual_accumulator := 0.0
var _amount_labels: Array[Label] = []
var _vein_style_signature := ""
var _deep_vein_data: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	if not get_parent() is Container:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(_on_resized)
	call_deferred("_refresh_world")


func configure(view_mode: String, profile: Dictionary) -> void:
	var requested_mode := view_mode.strip_edges().to_lower()
	mode = requested_mode if requested_mode == "base" or SITE_KEYS.has(requested_mode) else "base"
	_profile = profile.duplicate(true)
	_update_motion_preference()
	if is_inside_tree():
		_refresh_world()


func update_state(profile: Dictionary) -> void:
	_profile = profile.duplicate(true)
	_update_motion_preference()
	var next_site := _resolve_site_key()
	if not _built or next_site != _visual_site_key:
		_refresh_world()
		return
	_sync_site_dynamics(GameMathScript.site(_profile, _visual_site_key))


func is_weak_hit(position: Vector2) -> bool:
	if mode != "fe" or not (_has_weak_point_research() or _has_temporary_weak_mark()):
		return false
	return position.distance_to(_weak_point_position()) <= WEAK_POINT_HIT_RADIUS

func normalized_mining_position(position: Vector2) -> Array[float]:
	if size.x <= 0.0 or size.y <= 0.0:
		return [0.5, 0.5]
	return [clampf(position.x / size.x, 0.0, 1.0), clampf(position.y / size.y, 0.0, 1.0)]


func _gui_input(event: InputEvent) -> void:
	if mode != "fe":
		return
	if event is InputEventScreenTouch and event.pressed:
		_handle_mine_input(event.position)
	elif event is InputEventMouseButton:
		var mouse_button := event as InputEventMouseButton
		if mouse_button.pressed:
			if mouse_button.button_index == MOUSE_BUTTON_LEFT:
				if mouse_button.device != InputEvent.DEVICE_ID_EMULATION:
					_handle_mine_input(mouse_button.position)


func _handle_mine_input(position: Vector2) -> void:
	mine_hit.emit(position)
	_register_contact(position, 0)
	accept_event()

func show_mined_amount(position: Vector2, amount: int) -> void:
	if amount <= 0:
		return
	_amount_labels = _amount_labels.filter(func(label: Label): return is_instance_valid(label) and not label.is_queued_for_deletion())
	if _amount_labels.size() >= 6:
		_amount_labels.pop_front().queue_free()
	var label := Label.new()
	label.name = "MinedAmount"
	label.text = "+%d Fe" % amount
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", Color("f6d79b"))
	label.add_theme_color_override("font_outline_color", Color("101b24"))
	label.add_theme_constant_override("outline_size", 3)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.position = Vector2(clampf(position.x, 4, size.x - 120), clampf(position.y - 30, 4, size.y - 32))
	label.z_index = 20
	add_child(label)
	_amount_labels.append(label)
	if _reduce_motion:
		get_tree().create_timer(0.55).timeout.connect(func():
			if is_instance_valid(label): label.queue_free())
	else:
		var tween := create_tween().bind_node(label)
		tween.set_parallel(true)
		tween.tween_property(label, "position:y", maxf(4, label.position.y - 22), 0.5)
		tween.tween_property(label, "modulate:a", 0.0, 0.5)
		tween.chain().tween_callback(label.queue_free)


func _on_resized() -> void:
	if _built:
		_refresh_world()


func _refresh_world() -> void:
	if not is_inside_tree() or size.x <= 0.0 or size.y <= 0.0:
		return
	_clear_world()
	_visual_site_key = _resolve_site_key()
	var background_path: String = BACKGROUNDS.get(mode, BACKGROUNDS["base"])
	_add_texture(background_path, Vector2.ZERO, size, TextureRect.STRETCH_KEEP_ASPECT_COVERED)
	if mode == "base":
		_build_base_locations()
	else:
		_build_site_world()
	_sync_site_dynamics(GameMathScript.site(_profile, _visual_site_key))
	_built = true


func _build_base_locations() -> void:
	_add_texture(
		"res://assets/placeholders/rail_line.svg",
		Vector2(0.0, size.y * 0.43),
		Vector2(size.x, size.y * 0.15),
		TextureRect.STRETCH_KEEP_ASPECT_COVERED
	)
	var cell_width := size.x / 5.0
	var row_height := size.y * 0.45
	for index in range(BASE_LOCATIONS.size()):
		var item: Dictionary = BASE_LOCATIONS[index]
		var column := index % 5
		var row := int(index / 5)
		var hotspot := Button.new()
		hotspot.flat = false
		hotspot.focus_mode = Control.FOCUS_ALL
		hotspot.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		hotspot.position = Vector2(cell_width * column, size.y * (0.025 + row * 0.52))
		hotspot.size = Vector2(cell_width, row_height)
		hotspot.tooltip_text = String(item["label"])
		hotspot.add_theme_stylebox_override("normal", _hotspot_style(Color(0.025, 0.055, 0.07, 0.0), Color(0.0, 0.0, 0.0, 0.0)))
		hotspot.add_theme_stylebox_override("hover", _hotspot_style(Color(0.055, 0.12, 0.15, 0.56), Color(0.73, 0.64, 0.43, 0.75)))
		hotspot.add_theme_stylebox_override("pressed", _hotspot_style(Color(0.36, 0.25, 0.12, 0.68), Color(0.94, 0.75, 0.39, 0.95)))
		hotspot.pressed.connect(_emit_location_selected.bind(String(item["id"])))
		add_child(hotspot)

		var icon_size := minf(cell_width * 0.78, row_height * 0.52)
		var icon := TextureRect.new()
		icon.texture = ArtLibrary.texture_for(String(item["art"]))
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		icon.position = Vector2((cell_width - icon_size) * 0.5, row_height * 0.08)
		icon.size = Vector2(icon_size, icon_size)
		hotspot.add_child(icon)
		if item["id"] == "factory":
			_factory_icon = icon

		var caption := Label.new()
		caption.text = String(item["label"])
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		caption.clip_text = true
		caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
		caption.add_theme_font_size_override("font_size", _base_font_size())
		caption.add_theme_color_override("font_color", Color(0.96, 0.92, 0.83))
		caption.position = Vector2(2.0, row_height * 0.70)
		caption.size = Vector2(cell_width - 4.0, row_height * 0.22)
		hotspot.add_child(caption)


func _build_site_world() -> void:
	if mode == "fe":
		_add_texture(
			"res://assets/placeholders/rail_line.svg",
			Vector2(0.0, size.y * 0.76),
			Vector2(size.x, size.y * 0.16),
			TextureRect.STRETCH_KEEP_ASPECT_COVERED
		)


func _hotspot_style(fill: Color, outline: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = outline
	style.set_border_width_all(1 if outline.a > 0.0 else 0)
	style.set_corner_radius_all(8)
	style.content_margin_left = 2.0
	style.content_margin_right = 2.0
	style.content_margin_top = 2.0
	style.content_margin_bottom = 2.0
	return style


func _emit_location_selected(id: String) -> void:
	location_selected.emit(id)


func _sync_site_dynamics(site_data: Dictionary) -> void:
	var horizon := int(site_data.get("horizon", 0)) if mode == "fe" else 0
	_sync_depth_layers(horizon)
	var machines: Dictionary = site_data.get("machines", {})
	var workers: Dictionary = site_data.get("workers", {})
	_sync_machines(machines)
	_sync_workers(workers)
	_sync_weak_point()
	_sync_anomaly()
	_sync_deep_veins()
	if is_instance_valid(_factory_icon):
		var cosmetic := str(_profile.get("game", {}).get("feature_families", {}).get("organisation", {}).get("factory_cosmetic", {}).get("active", "standard"))
		_factory_icon.texture = ArtLibrary.texture_named("factory_style_" + cosmetic, "res://assets/placeholders/building_factory.svg")
		_factory_icon.modulate = {"steel":Color("a5cee0"), "copper":Color("e4a16d")}.get(cosmetic, Color.WHITE)
	queue_redraw()

func _sync_deep_veins() -> void:
	var game: Dictionary = _profile.get("game", {})
	var owns := int(game.get("progression", {}).get("research", {}).get("G15", 0)) > 0
	var horizon := int(game.get("sites", {}).get("fe", {}).get("horizon", 0))
	var discoveries: Dictionary = game.get("progression", {}).get("geology", {}).get("discoveries", {})
	var signature := "%s:%s:%d:%s" % [mode, owns, horizon, str(discoveries)]
	if signature == _vein_style_signature:
		return
	_vein_style_signature = signature
	_deep_vein_data = {}
	if mode == "fe" and owns and horizon > 0:
		_deep_vein_data = load("res://gameplay/ResearchViews.gd").deep_vein_style(_profile).get("deep_vein_style", {})

func _sync_anomaly() -> void:
	var mining := _mining_state()
	var visible_seconds := float(mining.get("anomaly_seconds_left", mining.get("anomaly_highlight", {}).get("seconds_left", 0.0)))
	var owned := int(_profile.get("game", {}).get("progression", {}).get("research", {}).get("D08", 0)) > 0
	if mode != "fe" or not owned or visible_seconds <= 0:
		if is_instance_valid(_anomaly_marker):
			_anomaly_marker.queue_free()
		_anomaly_marker = null
		return
	if not is_instance_valid(_anomaly_marker):
		_anomaly_marker = TextureRect.new()
		_anomaly_marker.name = "GeologyAnomaly"
		_anomaly_marker.texture = ArtLibrary.texture_named("geology_anomaly", "res://assets/placeholders/weak_point.svg")
		_anomaly_marker.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_anomaly_marker.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_anomaly_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_anomaly_marker.modulate = Color(0.45, 0.9, 1.0)
		add_child(_anomaly_marker)
	_anomaly_marker.size = Vector2(30, 30)
	var point := _weak_point_position() + Vector2(64, -28)
	_anomaly_marker.position = Vector2(clampf(point.x, 16, size.x - 46), clampf(point.y, 16, size.y - 46))


func _sync_weak_point() -> void:
	var should_show := mode == "fe" and (_has_weak_point_research() or _has_temporary_weak_mark())
	if not should_show:
		if is_instance_valid(_weak_point_marker):
			_weak_point_marker.queue_free()
		_weak_point_marker = null
		return
	var marker_size := clampf(minf(size.x, size.y) * 0.105, 32.0, 44.0)
	if not is_instance_valid(_weak_point_marker):
		_weak_point_marker = TextureRect.new()
		_weak_point_marker.texture = ArtLibrary.texture_for("res://assets/placeholders/weak_point.svg")
		_weak_point_marker.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_weak_point_marker.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_weak_point_marker.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		_weak_point_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_weak_point_marker.z_index = 50
		add_child(_weak_point_marker)
	_weak_point_marker.size = Vector2.ONE * marker_size
	_weak_point_marker.position = _weak_point_position() - _weak_point_marker.size * 0.5
	_weak_point_marker.tooltip_text = "Слабая точка · D01" if _has_weak_point_research() else "Отмеченная слабая точка · FE_SK01"
	queue_redraw()


func _weak_point_position() -> Vector2:
	var site_data: Dictionary = _profile.get("game", {}).get("sites", {}).get("fe", {})
	var horizon := maxi(0, int(site_data.get("horizon", 0)))
	var lane := posmod((horizon % 67) * 37 + 17, 67)
	var x_ratio := 0.16 + float(lane) / 67.0 * 0.68
	var y_ratio := minf(0.47 + float(horizon % MAX_VISIBLE_HORIZONS) * 0.042, 0.72)
	return Vector2(size.x * x_ratio, size.y * y_ratio)


func _has_weak_point_research() -> bool:
	var game_data: Dictionary = _profile.get("game", {})
	var progression: Dictionary = game_data.get("progression", {})
	var research: Dictionary = progression.get("research", {})
	return int(research.get("D01", 0)) >= 1

func _has_temporary_weak_mark() -> bool:
	var game_data: Dictionary = _profile.get("game", {})
	var progression: Dictionary = game_data.get("progression", {})
	var mastery: Dictionary = progression.get("mastery", {})
	var mining := _mining_state()
	return int(mastery.get("FE_SK01", 0)) > 0 and bool(mining.get("weak_mark_pending", false)) and float(mining.get("weak_mark_seconds", 0.0)) > 0.0

func _mining_state() -> Dictionary:
	var game_data: Dictionary = _profile.get("game", {})
	var families: Dictionary = game_data.get("feature_families", {})
	return families.get("mining", {})

func _draw_mining_targets() -> void:
	if mode != "fe":
		return
	var mining := _mining_state()
	var radius := clampf(minf(size.x, size.y) * 0.055, 12.0, 28.0)
	var zone_choice: Dictionary = mining.get("zone_choice", {})
	if bool(zone_choice.get("available", false)):
		for zone in ["left", "center", "right"]:
			var center := _zone_center(zone)
			draw_arc(center, radius, 0.0, TAU, 24, Color(0.68, 0.89, 1.0, 0.62), 2.0, true)
	elif float(zone_choice.get("seconds_left", 0.0)) > 0.0 and not str(zone_choice.get("zone", "")).is_empty():
		draw_arc(_zone_center(str(zone_choice["zone"])), radius * 1.25, 0.0, TAU, 28, Color(0.42, 0.92, 0.81, 0.88), 3.0, true)
	var marked: Dictionary = mining.get("marked_strike", {})
	if bool(marked.get("armed", false)):
		draw_arc(_zone_center(str(marked.get("zone", ""))), radius * 1.55, 0.0, TAU, 28, Color(1.0, 0.76, 0.30, 0.94), 3.0, true)
	var directional: Dictionary = mining.get("directional_strike", {})
	if bool(directional.get("armed", false)):
		draw_arc(_zone_center(str(directional.get("zone", ""))), radius * 1.8, 0.0, TAU, 28, Color(0.44, 0.79, 1.0, 0.92), 2.5, true)
	var forecast: Dictionary = mining.get("forecast", {})
	var research: Dictionary = _profile.get("game", {}).get("progression", {}).get("research", {})
	if int(research.get("D03", 0)) > 0 and bool(forecast.get("enabled", false)):
		var alpha := 0.95 if bool(forecast.get("available", false)) else 0.48
		draw_arc(_zone_center(str(forecast.get("zone", "left"))), radius * 2.1, 0.0, TAU, 32, Color(0.58, 0.75, 1.0, alpha), 2.0, true)
	var route: Dictionary = mining.get("route", {})
	if bool(route.get("active", false)):
		for path in range(2):
			var start := Vector2(size.x * (0.22 if path == 0 else 0.78), size.y * 0.49)
			var finish := Vector2(size.x * (0.78 if path == 0 else 0.22), size.y * 0.76)
			var color := Color(0.34, 0.94, 0.76, 0.92) if path == int(route.get("path", -1)) else Color(0.62, 0.77, 0.79, 0.48)
			draw_line(start, finish, color, 4.0 if path == int(route.get("path", -1)) else 2.0, true)
	var event: Dictionary = mining.get("core_event", {})
	if bool(event.get("started", false)) and not bool(event.get("completed", false)):
		draw_arc(Vector2(size.x * 0.5, size.y * 0.78), radius * 1.35, 0.0, TAU, 28, Color(1.0, 0.58, 0.32, 0.9), 2.5, true)

func _zone_center(zone: String) -> Vector2:
	var centers := {"left":Vector2(0.28, 0.60), "center":Vector2(0.50, 0.62), "right":Vector2(0.72, 0.60)}
	var normalized: Vector2 = centers.get(zone, Vector2(0.5, 0.62))
	return Vector2(size.x * normalized.x, size.y * normalized.y)


func _sync_depth_layers(horizon: int) -> void:
	var visible_horizon := clampi(horizon, 0, MAX_VISIBLE_HORIZONS)
	if _horizon_signature == visible_horizon:
		return
	for layer in _depth_layers:
		if is_instance_valid(layer):
			if layer.get_parent() != null:
				layer.get_parent().remove_child(layer)
			layer.queue_free()
	_depth_layers.clear()
	_horizon_signature = visible_horizon
	if mode != "fe":
		return
	for index in range(visible_horizon):
		var width := size.x * (0.91 - index * 0.025)
		var layer_height := size.y * 0.105
		var layer := _add_texture(
			"res://assets/placeholders/fe_horizon_ledge.svg",
			Vector2(size.x * (0.045 + index * 0.025), size.y * (0.39 + index * 0.049)),
			Vector2(width, layer_height),
			TextureRect.STRETCH_KEEP_ASPECT_COVERED
		)
		if layer != null:
			layer.modulate = Color(1.0, 1.0, 1.0, maxf(0.42, 0.92 - index * 0.055))
			_depth_layers.append(layer)


func _sync_machines(machines: Dictionary) -> void:
	var signature := _count_signature(machines)
	if signature == _machine_signature:
		return
	for machine in _machine_nodes:
		if is_instance_valid(machine):
			if machine.get_parent() != null:
				machine.get_parent().remove_child(machine)
			machine.queue_free()
	_machine_nodes.clear()
	_machine_signature = signature
	var paths: Array[Dictionary] = []
	var keys: Array = machines.keys()
	keys.sort()
	for key in keys:
		var count := _positive_count(machines[key])
		if count == 0:
			continue
		var path := "res://assets/placeholders/machine_drill.svg"
		var key_text := String(key).to_lower()
		if key_text.contains("loader") or key_text.contains("excavat") or key_text.contains("погруз"):
			path = "res://assets/placeholders/machine_loader.svg"
		paths.append({"path":path, "id":str(key)})
		if paths.size() >= MAX_VISIBLE_MACHINES:
			break
	for index in range(paths.size()):
		var position := _machine_position(index)
		var machine := _add_texture(paths[index]["path"], position, _machine_size(), TextureRect.STRETCH_KEEP_ASPECT_CENTERED, paths[index]["id"])
		if machine != null:
			_machine_nodes.append(machine)


func _sync_workers(workers: Dictionary) -> void:
	var signature := _count_signature(workers)
	if signature != _worker_signature:
		_clear_workers()
		_worker_signature = signature
		var total := 0
		var keys: Array = workers.keys()
		keys.sort()
		for key in keys:
			total += _positive_count(workers[key])
		for index in range(mini(total, MAX_VISIBLE_WORKERS)):
			var actor := TextureRect.new()
			actor.texture = ArtLibrary.texture_for("res://assets/placeholders/worker_miner.svg")
			actor.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			actor.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			actor.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
			actor.mouse_filter = Control.MOUSE_FILTER_IGNORE
			actor.position = _worker_position(index)
			actor.size = _worker_size()
			actor.pivot_offset = actor.size * 0.5
			add_child(actor)
			var timer := Timer.new()
			timer.one_shot = true
			add_child(timer)
			timer.timeout.connect(_on_worker_cycle.bind(actor, timer, index))
			_workers.append({"actor":actor, "timer":timer, "tween":null, "index":index})
	_update_worker_activity()


func _on_worker_cycle(actor: TextureRect, timer: Timer, worker_index: int) -> void:
	if not is_instance_valid(actor) or not is_instance_valid(timer):
		return
	if not _workers_have_funds():
		timer.stop()
		return
	if _reduce_motion:
		_register_contact(_worker_contact_position(actor), worker_index + 1, true)
		timer.start(_worker_interval(worker_index))
		return
	var swing := create_tween()
	swing.tween_property(actor, "rotation", deg_to_rad(18.0), 0.13).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	swing.tween_callback(_register_contact.bind(_worker_contact_position(actor), worker_index + 1, false))
	swing.tween_property(actor, "rotation", 0.0, 0.20).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	for worker in _workers:
		if worker["actor"] == actor:
			worker["tween"] = swing
			break
	timer.start(_worker_interval(worker_index))


func _update_worker_activity() -> void:
	var activity_signature := "%s:%s" % [str(_workers_have_funds()), str(_reduce_motion)]
	if activity_signature == _worker_activity_signature:
		return
	_worker_activity_signature = activity_signature
	for worker in _workers:
		var actor: TextureRect = worker["actor"]
		var timer: Timer = worker["timer"]
		if not is_instance_valid(actor) or not is_instance_valid(timer):
			continue
		if _workers_have_funds():
			actor.modulate = Color.WHITE
		else:
			actor.modulate = Color(0.62, 0.66, 0.67, 0.78)
		if not _workers_have_funds():
			timer.stop()
			var tween: Variant = worker["tween"]
			if tween is Tween and tween.is_running():
				tween.kill()
			worker["tween"] = null
			actor.rotation = 0.0
		elif _reduce_motion:
			var tween: Variant = worker["tween"]
			if tween is Tween and tween.is_running():
				tween.kill()
			worker["tween"] = null
			actor.rotation = 0.0
			if timer.is_stopped():
				timer.start(_worker_interval(int(worker["index"])))
		elif timer.is_stopped():
			timer.start(_worker_interval(int(worker["index"])))


func _worker_interval(index: int) -> float:
	return 1.05 + float((index * 37) % 9) * 0.13


func _worker_contact_position(actor: TextureRect) -> Vector2:
	var contact := actor.position + Vector2(actor.size.x * 0.92, actor.size.y * 0.96)
	var rail_y_ratio := 0.43 + 0.15 * 73.0 / 180.0 if mode == "base" else 0.76 + 0.16 * 73.0 / 180.0
	contact.y = maxf(contact.y, size.y * rail_y_ratio + WORKER_SPARK_CLEARANCE)
	return contact


func _clear_workers() -> void:
	for worker in _workers:
		var timer: Timer = worker["timer"]
		var actor: TextureRect = worker["actor"]
		if is_instance_valid(timer):
			timer.stop()
			if timer.get_parent() != null:
				timer.get_parent().remove_child(timer)
			timer.queue_free()
		var tween: Variant = worker["tween"]
		if tween is Tween and tween.is_running():
			tween.kill()
		if is_instance_valid(actor):
			if actor.get_parent() != null:
				actor.get_parent().remove_child(actor)
			actor.queue_free()
	_workers.clear()
	_worker_activity_signature = ""


func _count_signature(values: Dictionary) -> String:
	var keys: Array = values.keys()
	keys.sort()
	var parts := ""
	for key in keys:
		var count := _positive_count(values[key])
		if count > 0:
			parts += "%s:%d;" % [String(key), count]
	return parts


func _positive_count(value: Variant) -> int:
	if value is Dictionary:
		return maxi(0, int(value.get("count", value.get("owned", 0))))
	if value is bool:
		return 1 if value else 0
	if value is int or value is float:
		return maxi(0, int(value))
	return 0


func _machine_position(index: int) -> Vector2:
	if mode == "base":
		return Vector2(size.x * (0.02 + index * 0.078), size.y * 0.435)
	return Vector2(size.x * (0.46 + index * 0.092), size.y * 0.68)


func _machine_size() -> Vector2:
	if mode == "base":
		return Vector2(size.x * 0.07, size.y * 0.14)
	return Vector2(size.x * 0.085, size.y * 0.16)


func _worker_position(index: int) -> Vector2:
	if mode == "base":
		return Vector2(size.x * (0.37 + index * 0.055), size.y * 0.435)
	return Vector2(size.x * (0.11 + (index % 3) * 0.12), size.y * (0.68 + int(index / 3) * 0.045))


func _worker_size() -> Vector2:
	if mode == "base":
		return Vector2(size.x * 0.085, size.y * 0.145)
	return Vector2(size.x * 0.14, size.y * 0.21)


func _register_contact(position: Vector2, seed: int, static_contact: bool = false) -> void:
	_burst_version += 1
	var is_static := static_contact or _reduce_motion
	_bursts.append({"position":position, "age":0.0, "duration":0.34, "seed":seed, "static":is_static})
	if is_static:
		queue_redraw()
		if _bursts.size() == 1:
			set_process(false)
		var version := _burst_version
		if is_inside_tree():
			get_tree().create_timer(0.14).timeout.connect(_clear_static_contact.bind(version))
		return
	_visual_accumulator = 0.0
	set_process(true)
	queue_redraw()


func _clear_static_contact(version: int) -> void:
	if version != _burst_version:
		return
	_bursts.clear()
	queue_redraw()


func _process(delta: float) -> void:
	if _reduce_motion or _bursts.is_empty():
		set_process(false)
		return
	var frame_interval := 1.0 / 30.0
	if Engine.max_fps > 0:
		frame_interval = maxf(frame_interval, 1.0 / float(Engine.max_fps))
	_visual_accumulator += delta
	if _visual_accumulator < frame_interval:
		return
	var elapsed := _visual_accumulator
	_visual_accumulator = 0.0
	var remaining_bursts: Array[Dictionary] = []
	for burst in _bursts:
		burst["age"] = float(burst["age"]) + elapsed
		if float(burst["age"]) < float(burst["duration"]):
			remaining_bursts.append(burst)
	_bursts = remaining_bursts
	queue_redraw()
	if _bursts.is_empty():
		set_process(false)


func _draw() -> void:
	if bool(_deep_vein_data.get("deep_style_available", false)):
		var types: Array = _deep_vein_data.get("available_types", [])
		for index in range(mini(3, types.size())):
			var color := Color(str(types[index].get("color", "#b5c0c8")))
			color.a = 0.65
			var points := PackedVector2Array()
			for step in range(6):
				points.append(Vector2(size.x * (0.5 + index * 0.12 + (0.035 if step % 2 == 0 else -0.035)), size.y * (0.16 + step * 0.12)))
			draw_polyline(points, color, 2.5, true)
	_draw_mining_targets()
	for burst in _bursts:
		var center: Vector2 = burst["position"]
		var duration := float(burst["duration"])
		var progress := clampf(float(burst["age"]) / duration, 0.0, 1.0)
		if bool(burst.get("static", false)):
			draw_arc(center, 7.0, 0.0, TAU, 16, Color(1.0, 0.77, 0.39, 0.72), 2.0, true)
			draw_circle(center, 2.0, Color(1.0, 0.92, 0.68, 0.88))
			continue
		var radius := 4.0 + progress * 12.0
		var alpha := 1.0 - progress
		draw_arc(center, radius, 0.0, TAU, 18, Color(1.0, 0.61, 0.27, alpha), 2.0, true)
		for spark_index in range(5):
			var angle := TAU * float(spark_index) / 5.0 + float(burst["seed"]) * 0.23
			var direction := Vector2.RIGHT.rotated(angle)
			var start := center + direction * (radius * 0.68)
			var finish := center + direction * (radius + 5.0 * alpha)
			draw_line(start, finish, Color(1.0, 0.84, 0.49, alpha), 1.6, true)
			draw_circle(start, 1.1 * alpha + 0.4, Color(1.0, 0.94, 0.69, alpha))


func _resolve_site_key() -> String:
	if mode != "base":
		return mode
	match String(_profile.get("active_site", "site_earth_fe_17")):
		"site_earth_pd_7":
			return "pd"
		"site_earth_ir_9":
			return "ir"
		_:
			return "fe"


func _read_reduce_motion() -> bool:
	var state := get_node_or_null("/root/GameState")
	if state != null:
		var settings: Variant = state.get("settings")
		if settings is Dictionary:
			return bool(settings.get("reduce_motion", settings.get("reduced_motion", false)))
	return bool(_profile.get("reduce_motion", false))


func _update_motion_preference() -> void:
	var should_reduce := _read_reduce_motion()
	if should_reduce == _reduce_motion:
		return
	_reduce_motion = should_reduce
	if _reduce_motion:
		_bursts.clear()
		set_process(false)
		queue_redraw()


func _workers_have_funds() -> bool:
	if not _profile.has("money_cents"):
		return false
	return GameMathScript.available_money(_profile, "payroll") > 0


func _base_font_size() -> int:
	var scale_factor := minf(size.x / 432.0, size.y / 320.0)
	return maxi(12, roundi(13.0 * scale_factor))


func _add_texture(path: String, position: Vector2, texture_size: Vector2, stretch: int, art_key: String = "") -> TextureRect:
	var texture := ArtLibrary.texture_for(path) if art_key.is_empty() else ArtLibrary.texture_named(art_key, path)
	if texture == null:
		push_warning("EarthCanvas texture could not be loaded: " + path)
		return null
	var rect := TextureRect.new()
	rect.texture = texture
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = stretch
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.show_behind_parent = true
	rect.position = position
	rect.size = texture_size
	add_child(rect)
	return rect


func _clear_world() -> void:
	_clear_workers()
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_depth_layers.clear()
	_machine_nodes.clear()
	_weak_point_marker = null
	_anomaly_marker = null
	_factory_icon = null
	_amount_labels.clear()
	_vein_style_signature = ""
	_deep_vein_data = {}
	_bursts.clear()
	_horizon_signature = -1
	_machine_signature = ""
	_worker_signature = ""
	_visual_accumulator = 0.0
	set_process(false)
	_built = false
