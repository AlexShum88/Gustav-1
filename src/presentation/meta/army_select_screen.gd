class_name ArmySelectScreen
extends Control

var _summary_label: RichTextLabel
var _army_name_label: Label


func _ready() -> void:
	_build_ui()
	_refresh_summary()


func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = Color(0.12, 0.13, 0.12)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var root := MarginContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("margin_left", 24)
	root.add_theme_constant_override("margin_right", 24)
	root.add_theme_constant_override("margin_top", 24)
	root.add_theme_constant_override("margin_bottom", 24)
	add_child(root)

	var content := HBoxContainer.new()
	content.add_theme_constant_override("separation", 24)
	root.add_child(content)

	var preview_panel := PanelContainer.new()
	preview_panel.custom_minimum_size = Vector2(940.0, 0.0)
	content.add_child(preview_panel)

	var preview_margin := MarginContainer.new()
	preview_margin.add_theme_constant_override("margin_left", 16)
	preview_margin.add_theme_constant_override("margin_right", 16)
	preview_margin.add_theme_constant_override("margin_top", 14)
	preview_margin.add_theme_constant_override("margin_bottom", 14)
	preview_panel.add_child(preview_margin)

	var preview_root := VBoxContainer.new()
	preview_root.add_theme_constant_override("separation", 10)
	preview_margin.add_child(preview_root)

	var title := Label.new()
	title.text = "Selected Army"
	title.add_theme_font_size_override("font_size", 24)
	preview_root.add_child(title)

	_army_name_label = Label.new()
	_army_name_label.add_theme_font_size_override("font_size", 20)
	preview_root.add_child(_army_name_label)

	_summary_label = RichTextLabel.new()
	_summary_label.fit_content = true
	_summary_label.bbcode_enabled = true
	_summary_label.scroll_active = true
	_summary_label.custom_minimum_size = Vector2(0.0, 640.0)
	preview_root.add_child(_summary_label)

	var actions_panel := PanelContainer.new()
	actions_panel.custom_minimum_size = Vector2(360.0, 0.0)
	content.add_child(actions_panel)

	var actions_margin := MarginContainer.new()
	actions_margin.add_theme_constant_override("margin_left", 16)
	actions_margin.add_theme_constant_override("margin_right", 16)
	actions_margin.add_theme_constant_override("margin_top", 14)
	actions_margin.add_theme_constant_override("margin_bottom", 14)
	actions_panel.add_child(actions_margin)

	var actions_root := VBoxContainer.new()
	actions_root.add_theme_constant_override("separation", 12)
	actions_margin.add_child(actions_root)

	var actions_title := Label.new()
	actions_title.text = "Actions"
	actions_title.add_theme_font_size_override("font_size", 22)
	actions_root.add_child(actions_title)

	actions_root.add_child(_make_action_button("Start Battle With Current Army", func() -> void:
		get_tree().change_scene_to_file("res://scenes/battle/test_battle.tscn")
	))
	actions_root.add_child(_make_action_button("Edit Current Army", func() -> void:
		get_tree().change_scene_to_file("res://scenes/meta/ArmyGraphEditor.tscn")
	))
	actions_root.add_child(_make_action_button("Choose Another Army", func() -> void:
		get_tree().change_scene_to_file("res://scenes/meta/ArmyManagement.tscn")
	))
	actions_root.add_child(_make_action_button("Back", func() -> void:
		get_tree().change_scene_to_file("res://scenes/meta/MainMenu.tscn")
	))


func _refresh_summary() -> void:
	var army = PlayerArmyRepository.get_selected_army()
	if army == null:
		_army_name_label.text = "No army selected"
		_summary_label.text = "Open Army Management and choose an army."
		return
	_army_name_label.text = army.display_name
	_summary_label.text = _build_army_summary(army)


func _build_army_summary(army) -> String:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("[b]Commander:[/b] %s" % army.commander_name)
	lines.append("[b]Brigades:[/b] %d" % army.get_brigade_count())
	lines.append("[b]Battalions:[/b] %d" % army.get_regiment_count())
	lines.append("[b]Editor Companies:[/b] %d" % army.get_company_count())
	lines.append("")
	for brigade_value in army.brigades:
		var brigade = brigade_value
		lines.append("[b]%s[/b] (%d battalions)" % [brigade.display_name, brigade.get_regiment_count()])
		for regiment_value in brigade.regiments:
			var regiment = regiment_value
			lines.append("  - %s | %s | %d companies" % [
				regiment.display_name,
				SimTypes.unit_category_name(regiment.category),
				regiment.get_company_count(),
			])
		lines.append("")
	return "\n".join(lines)


func _make_action_button(text_value: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text_value
	button.custom_minimum_size = Vector2(0.0, 48.0)
	button.pressed.connect(callback)
	return button
