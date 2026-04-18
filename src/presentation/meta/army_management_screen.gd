class_name ArmyManagementScreen
extends Control

var _army_list: ItemList
var _summary_label: RichTextLabel


func _ready() -> void:
	PlayerArmyRepository.armies_changed.connect(_refresh_armies)
	PlayerArmyRepository.selected_army_changed.connect(_refresh_armies)
	_build_ui()
	_refresh_armies()


func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = Color(0.1, 0.11, 0.12)
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

	var list_panel := PanelContainer.new()
	list_panel.custom_minimum_size = Vector2(420.0, 0.0)
	content.add_child(list_panel)

	var list_margin := MarginContainer.new()
	list_margin.add_theme_constant_override("margin_left", 14)
	list_margin.add_theme_constant_override("margin_right", 14)
	list_margin.add_theme_constant_override("margin_top", 14)
	list_margin.add_theme_constant_override("margin_bottom", 14)
	list_panel.add_child(list_margin)

	var list_root := VBoxContainer.new()
	list_root.add_theme_constant_override("separation", 12)
	list_margin.add_child(list_root)

	var title := Label.new()
	title.text = "Armies"
	title.add_theme_font_size_override("font_size", 24)
	list_root.add_child(title)

	_army_list = ItemList.new()
	_army_list.custom_minimum_size = Vector2(0.0, 560.0)
	_army_list.item_selected.connect(_on_army_selected)
	list_root.add_child(_army_list)

	var button_row := HBoxContainer.new()
	button_row.add_theme_constant_override("separation", 8)
	list_root.add_child(button_row)
	button_row.add_child(_make_button("Use", func() -> void:
		var army = _get_selected_army_from_list()
		if army != null:
			PlayerArmyRepository.select_army(army.id)
	))
	button_row.add_child(_make_button("Edit", func() -> void:
		var army = _get_selected_army_from_list()
		if army == null:
			return
		PlayerArmyRepository.select_army(army.id)
		get_tree().change_scene_to_file("res://scenes/meta/ArmyGraphEditor.tscn")
	))

	var second_row := HBoxContainer.new()
	second_row.add_theme_constant_override("separation", 8)
	list_root.add_child(second_row)
	second_row.add_child(_make_button("Create New", func() -> void:
		var army = PlayerArmyRepository.create_new_army()
		if army != null:
			get_tree().change_scene_to_file("res://scenes/meta/ArmyGraphEditor.tscn")
	))
	second_row.add_child(_make_button("Duplicate", func() -> void:
		var army = _get_selected_army_from_list()
		if army != null:
			PlayerArmyRepository.duplicate_army(army.id)
	))
	second_row.add_child(_make_button("Delete", func() -> void:
		var army = _get_selected_army_from_list()
		if army != null:
			PlayerArmyRepository.delete_army(army.id)
	))

	list_root.add_child(_make_button("Back", func() -> void:
		get_tree().change_scene_to_file("res://scenes/meta/MainMenu.tscn")
	))

	var summary_panel := PanelContainer.new()
	content.add_child(summary_panel)

	var summary_margin := MarginContainer.new()
	summary_margin.add_theme_constant_override("margin_left", 16)
	summary_margin.add_theme_constant_override("margin_right", 16)
	summary_margin.add_theme_constant_override("margin_top", 14)
	summary_margin.add_theme_constant_override("margin_bottom", 14)
	summary_panel.add_child(summary_margin)

	_summary_label = RichTextLabel.new()
	_summary_label.bbcode_enabled = true
	_summary_label.fit_content = true
	_summary_label.scroll_active = true
	summary_margin.add_child(_summary_label)


func _refresh_armies(_unused = null) -> void:
	var armies: Array = PlayerArmyRepository.get_armies()
	_army_list.clear()
	var selected_index: int = -1
	for army_index in range(armies.size()):
		var army = armies[army_index]
		var item_text: String = army.display_name
		if army.is_default_preset:
			item_text += " [Preset]"
		if army.id == PlayerArmyRepository.get_selected_army_id():
			item_text += " [Current]"
			selected_index = army_index
		_army_list.add_item(item_text)
	if selected_index == -1 and not armies.is_empty():
		selected_index = 0
	if selected_index >= 0:
		_army_list.select(selected_index)
	_show_summary(_get_selected_army_from_list())


func _show_summary(army) -> void:
	if army == null:
		_summary_label.text = "No army selected."
		return
	var lines: PackedStringArray = PackedStringArray()
	lines.append("[b]%s[/b]" % army.display_name)
	lines.append("[b]Army Commander:[/b] %s" % army.commander_name)
	lines.append("[b]Brigades:[/b] %d" % army.get_brigade_count())
	lines.append("[b]Battalions:[/b] %d" % army.get_regiment_count())
	lines.append("[b]Editor Companies:[/b] %d" % army.get_company_count())
	lines.append("")
	for brigade_value in army.brigades:
		var brigade = brigade_value
		lines.append("[b]%s[/b] | %s" % [brigade.display_name, brigade.general_name])
		for regiment_value in brigade.regiments:
			var regiment = regiment_value
			lines.append("  - %s | %s | %d editor companies" % [
				regiment.display_name,
				SimTypes.unit_category_name(regiment.category),
				regiment.get_company_count(),
			])
		lines.append("")
	_summary_label.text = "\n".join(lines)


func _on_army_selected(_index: int) -> void:
	_show_summary(_get_selected_army_from_list())


func _get_selected_army_from_list():
	var selected_items: PackedInt32Array = _army_list.get_selected_items()
	if selected_items.is_empty():
		return null
	var armies: Array = PlayerArmyRepository.get_armies()
	var selected_index: int = selected_items[0]
	return armies[selected_index] if selected_index >= 0 and selected_index < armies.size() else null


func _make_button(text_value: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text_value
	button.custom_minimum_size = Vector2(0.0, 42.0)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(callback)
	return button
