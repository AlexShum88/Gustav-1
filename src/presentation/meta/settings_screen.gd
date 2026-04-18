class_name SettingsScreen
extends Control


func _ready() -> void:
	_build_ui()


func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = Color(0.09, 0.1, 0.11)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var panel := PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.position = Vector2(-260.0, -180.0)
	panel.custom_minimum_size = Vector2(520.0, 360.0)
	add_child(panel)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	panel.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 14)
	margin.add_child(root)

	var title := Label.new()
	title.text = "Settings"
	title.add_theme_font_size_override("font_size", 24)
	root.add_child(title)

	var note := Label.new()
	note.text = "This screen is a placeholder for settings.\nVideo, controls and UI options can be moved here next."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(note)

	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(0.0, 44.0)
	back.pressed.connect(func() -> void:
		get_tree().change_scene_to_file("res://scenes/meta/MainMenu.tscn")
	)
	root.add_child(back)
