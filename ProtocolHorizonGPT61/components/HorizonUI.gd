class_name HorizonUI
extends RefCounted

const GOLD := Color("dcc18c")
const MUTED := Color("a8b5be")
const THEME = preload("res://assets/ui/HorizonTheme.tres")

static func screen(root: Control, quiet := false) -> VBoxContainer:
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.theme = THEME.duplicate(true)
	for pair in [["normal","button_dark"],["hover","button_hover"],["pressed","button_pressed"],["disabled","button_disabled"],["focus","focus"]]:
		root.theme.set_stylebox(pair[0], "Button", texture_box(pair[1]))
	var background := TextureRect.new()
	background.name = "Backdrop"
	background.texture = ArtLibrary.texture_for("res://assets/backgrounds/mine_archival_low.jpg" if GameState.settings["quality"] == "low" else "res://assets/backgrounds/mine_archival.jpg")
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := TextureRect.new()
	shade.texture = preload("res://assets/ui/shade.svg")
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if quiet:
		var dark := ColorRect.new()
		dark.color = Color(0.02, 0.05, 0.08, 0.84)
		dark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(dark)
		dark.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	elif not GameState.settings["reduce_motion"]:
		background.modulate.a = 0.0
		root.create_tween().tween_property(background, "modulate:a", 1.0, 0.45)
	var margin := MarginContainer.new()
	margin.name = "SafeMargin"
	root.add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var update := func():
		var size := root.get_viewport_rect().size
		var rect := Rect2(Vector2.ZERO, size)
		if OS.has_feature("mobile"):
			var safe := DisplayServer.get_display_safe_area()
			if safe.has_area():
				rect = root.get_viewport().get_screen_transform().affine_inverse() * Rect2(safe)
		var insets := safe_insets(size, rect)
		for side in insets:
			margin.add_theme_constant_override("margin_" + side, insets[side])
	var viewport := root.get_viewport()
	viewport.size_changed.connect(update)
	root.tree_exiting.connect(func():
		if viewport.size_changed.is_connected(update):
			viewport.size_changed.disconnect(update))
	update.call()
	return column(margin, 12)

static func safe_insets(size: Vector2, safe: Rect2) -> Dictionary:
	return {"left": 24 + ceili(maxf(0, safe.position.x)), "top": 20 + ceili(maxf(0, safe.position.y)),
		"right": 24 + ceili(maxf(0, size.x - safe.end.x)), "bottom": 20 + ceili(maxf(0, size.y - safe.end.y))}

static func column(parent: Node, gap := 12) -> VBoxContainer:
	var node := VBoxContainer.new()
	node.add_theme_constant_override("separation", gap)
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(node)
	return node

static func label(parent: Node, text: String, size := 16, color := Color("e4e9ec")) -> Label:
	var node := Label.new()
	node.text = text
	node.add_theme_font_size_override("font_size", size)
	node.add_theme_color_override("font_color", color)
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(node)
	return node

static func button(parent: Node, text: String, name: String, action: Callable, primary := false) -> Button:
	var node := Button.new()
	node.name = name
	node.text = text
	node.custom_minimum_size.y = 52
	node.clip_text = true
	node.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	node.tooltip_text = text
	node.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if primary:
		node.add_theme_stylebox_override("normal", texture_box("button_gold"))
		node.add_theme_stylebox_override("hover", texture_box("button_gold"))
		for state in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color"]:
			node.add_theme_color_override(state, Color("101b24"))
		node.add_theme_color_override("font_pressed_color", Color("f7ecd5"))
	parent.add_child(node)
	node.pressed.connect(func():
		if name == "Menu" or name.begins_with("Back"):
			AudioService.play_effect("ui_back")
		else:
			AudioService.tap()
		action.call())
	return node

static func option_button() -> OptionButton:
	var node := OptionButton.new()
	node.fit_to_longest_item = false
	node.clip_text = true
	node.custom_minimum_size.y = 44
	return node

static func texture_box(name: String) -> StyleBoxTexture:
	var box := StyleBoxTexture.new()
	box.texture = ArtLibrary.texture_for("res://assets/ui/" + name + ".svg")
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		box.set_texture_margin(side, 12)
		box.set_content_margin(side, 12)
	return box

static func spacer(parent: Node) -> void:
	var node := Control.new()
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(node)

static func notice(parent: Node, text: String) -> Label:
	var node := label(parent, text, 13, MUTED)
	node.name = "Notice"
	return node

static func confirm(root: Control, text: String, accepted: Callable) -> void:
	var blocked: Array[BaseButton] = []
	var previous_focus := root.get_viewport().gui_get_focus_owner()
	for control in root.find_children("*", "BaseButton", true, false):
		if not control.disabled:
			blocked.append(control)
			control.disabled = true
	var overlay := ColorRect.new()
	overlay.name = "ConfirmNewGame"
	overlay.color = Color(0.01, 0.03, 0.05, 0.95)
	root.add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	overlay.add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 32)
	var items := column(margin, 16)
	spacer(items)
	label(items, "НАЧАТЬ ЗАНОВО?", 24, GOLD)
	label(items, text, 16)
	var close := func():
		for control in blocked:
			if is_instance_valid(control):
				control.disabled = false
		overlay.queue_free()
	button(items, "Заменить профиль", "ConfirmReplace", func():
		close.call()
		accepted.call(), true)
	var cancel := button(items, "Отмена", "CancelReplace", func():
		close.call()
		if is_instance_valid(previous_focus):
			previous_focus.grab_focus())
	cancel.grab_focus()
	spacer(items)
