class_name MainMenuScreen
extends Control


func _ready() -> void:
	_build_ui()


func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = Color(0.11, 0.12, 0.1)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var root := VBoxContainer.new()
	root.anchor_left = 0.5
	root.anchor_top = 0.5
	root.anchor_right = 0.5
	root.anchor_bottom = 0.5
	root.position = Vector2(-180.0, -220.0)
	root.custom_minimum_size = Vector2(360.0, 440.0)
	root.add_theme_constant_override("separation", 14)
	add_child(root)

	var title := Label.new()
	title.text = "Gustav I"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 34)
	root.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Main Menu"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.modulate = Color(0.86, 0.86, 0.82)
	root.add_child(subtitle)

	root.add_child(_make_menu_button("Start Battle", func() -> void:
		get_tree().change_scene_to_file("res://scenes/meta/ArmySelect.tscn")
	))
	root.add_child(_make_menu_button("Core V2 Sandbox", func() -> void:
		get_tree().change_scene_to_file("res://scenes/core_v2/CoreV2Sandbox.tscn")
	))
	root.add_child(_make_menu_button("Edit Army", func() -> void:
		get_tree().change_scene_to_file("res://scenes/meta/ArmyManagement.tscn")
	))
	root.add_child(_make_menu_button("Settings", func() -> void:
		get_tree().change_scene_to_file("res://scenes/meta/Settings.tscn")
	))
	root.add_child(_make_menu_button("Exit", func() -> void:
		get_tree().quit()
	))


func _make_menu_button(text_value: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text_value
	button.custom_minimum_size = Vector2(360.0, 56.0)
	button.pressed.connect(callback)
	return button
