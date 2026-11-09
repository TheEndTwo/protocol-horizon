class_name ResearchGraph
extends GraphEdit

signal purchase_requested(id: String)
var _nodes: Dictionary = {}
var _depths: Dictionary = {}
var _touches: Dictionary = {}
var _pinch_distance := 0.0

func populate(profile: Dictionary) -> void:
	custom_minimum_size = Vector2(0,360)
	zoom_min = 0.25
	zoom_max = 1.5
	zoom = 0.65
	show_grid = false
	show_zoom_label = true
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var progression = load("res://gameplay/ProgressionModel.gd")
	for record in GameMath.records("research"):
		_nodes[str(record["id"])] = record
	var occupied: Dictionary = {}
	for id in _nodes:
		var record: Dictionary = _nodes[id]
		var status: Dictionary = progression.research_status(profile,id)
		var node := GraphNode.new()
		node.name = "Research_" + id
		node.title = id + " · " + str(record["name"])
		node.draggable = false
		node.resizable = false
		node.custom_minimum_size = Vector2(230,100)
		var group := 4 if id.begins_with("PD") else 5 if id.begins_with("IR") else ["D","A","P","G"].find(id.left(1))
		var index := int(id.trim_prefix("PD").trim_prefix("IR").trim_prefix("D").trim_prefix("A").trim_prefix("P").trim_prefix("G")) - 1
		var location := Vector2(_depth(id)*260,group*900+(index%6)*135)
		while occupied.has(str(location)):
			location.y += 135
		occupied[str(location)] = true
		node.position_offset = location
		add_child(node)
		var rows := VBoxContainer.new()
		node.add_child(rows)
		var label := HorizonUI.label(rows,"%d/%d · %d ОИ" % [status["level"],status["max_levels"],status["next_cost"]],14)
		label.custom_minimum_size.x = 200
		var tech_id: String = id
		var button := HorizonUI.button(rows,"Исследовать", "Buy"+id,func(): purchase_requested.emit(tech_id))
		button.custom_minimum_size.y = 44
		button.disabled = not bool(status["can_research"])
		button.tooltip_text = str(status.get("reason","")) + "\n" + str(record["effect"])
		var color := Color("6b9b86") if int(status["level"]) > 0 else Color("c0a46b") if bool(status["can_research"]) else Color("5a6570")
		node.set_slot(0,true,0,color,true,0,color)
		node.modulate = Color.WHITE if bool(status["unlocked"]) else Color(0.67,0.72,0.77,1)
	for id in _nodes:
		for parent_id in str(_nodes[id].get("dependencies","")).split(",",false):
			var parent := parent_id.strip_edges()
			if _nodes.has(parent):
				connect_node("Research_"+parent,0,"Research_"+id,0)

func _depth(id: String) -> int:
	if _depths.has(id):
		return int(_depths[id])
	var result := 0
	for parent in str(_nodes[id].get("dependencies","")).split(",",false):
		var key := parent.strip_edges()
		if _nodes.has(key):
			result = maxi(result,_depth(key)+1)
	_depths[id] = result
	return result

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMagnifyGesture:
		zoom = clampf(zoom*event.factor,zoom_min,zoom_max)
		accept_event()
	elif event is InputEventScreenDrag and _touches.size() < 2:
		scroll_offset -= event.relative/zoom
		accept_event()

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and _inside_visible(event.position):
			_touches[event.index] = event.position
		else:
			_touches.erase(event.index)
		_pinch_distance = 0.0
	elif event is InputEventScreenDrag and _touches.has(event.index):
		_touches[event.index] = event.position
		if _touches.size() == 2:
			var points := _touches.values()
			var distance: float = points[0].distance_to(points[1])
			if _pinch_distance > 0 and distance > 0:
				zoom = clampf(zoom*distance/_pinch_distance,zoom_min,zoom_max)
			_pinch_distance = distance
			get_viewport().set_input_as_handled()

func _inside_visible(point: Vector2) -> bool:
	if not is_visible_in_tree() or not get_global_rect().has_point(point):
		return false
	var ancestor := get_parent()
	while ancestor is Control:
		if ancestor.clip_contents and not ancestor.get_global_rect().has_point(point):
			return false
		ancestor = ancestor.get_parent()
	return true
