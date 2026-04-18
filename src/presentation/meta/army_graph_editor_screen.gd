class_name ArmyGraphEditorScreen
extends Control

const BrigadeDefinition = preload("res://src/meta/army_editor/brigade_definition.gd")
const RegimentDefinition = preload("res://src/meta/army_editor/regiment_definition.gd")
const RegimentProfileLibrary = preload("res://src/simulation/core/regiment_profile_library.gd")

var _graph_container: PanelContainer
var _graph: GraphEdit
var _inspector_root: VBoxContainer
var _selected_node_type: String = "army"
var _selected_brigade_id: StringName = &""
var _selected_regiment_id: StringName = &""
var _graph_scroll_offset: Vector2 = Vector2.ZERO


func _ready() -> void:
	PlayerArmyRepository.armies_changed.connect(_on_repository_changed)
	PlayerArmyRepository.ensure_army_editor_layout(PlayerArmyRepository.get_selected_army())
	_build_ui()
	_rebuild_graph()
	_rebuild_inspector()


func _process(_delta: float) -> void:
	_persist_graph_positions()


func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = Color(0.11, 0.12, 0.13)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var root := MarginContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("margin_left", 20)
	root.add_theme_constant_override("margin_right", 20)
	root.add_theme_constant_override("margin_top", 18)
	root.add_theme_constant_override("margin_bottom", 18)
	add_child(root)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	root.add_child(content)

	var toolbar := HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 8)
	content.add_child(toolbar)

	toolbar.add_child(_make_toolbar_button("Back", func() -> void:
		_persist_graph_positions()
		get_tree().change_scene_to_file("res://scenes/meta/ArmyManagement.tscn")
	))
	toolbar.add_child(_make_toolbar_button("Add Brigade HQ", func() -> void:
		var army = PlayerArmyRepository.get_selected_army()
		if army == null:
			return
		var brigade = PlayerArmyRepository.create_brigade(army.id)
		if brigade != null:
			_selected_node_type = "brigade"
			_selected_brigade_id = brigade.id
			_selected_regiment_id = &""
	))
	toolbar.add_child(_make_toolbar_button("Add Battalion", func() -> void:
		var army = PlayerArmyRepository.get_selected_army()
		if army == null:
			return
		var brigade_id: StringName = _selected_brigade_id
		if brigade_id == &"" and not army.brigades.is_empty():
			brigade_id = army.brigades[0].id
		var regiment = PlayerArmyRepository.create_regiment(army.id, brigade_id)
		if regiment != null:
			_selected_node_type = "regiment"
			_selected_regiment_id = regiment.id
	))
	toolbar.add_child(_make_toolbar_button("Delete Selected", func() -> void:
		_delete_selected_node()
	))
	toolbar.add_child(_make_toolbar_button("Start Battle", func() -> void:
		_persist_graph_positions()
		get_tree().change_scene_to_file("res://scenes/meta/ArmySelect.tscn")
	))

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 16)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(body)

	_graph_container = PanelContainer.new()
	_graph_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_graph_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(_graph_container)

	_graph = GraphEdit.new()
	_graph.set_anchors_preset(Control.PRESET_FULL_RECT)
	_graph.right_disconnects = false
	_graph_container.add_child(_graph)

	var inspector_panel := PanelContainer.new()
	inspector_panel.custom_minimum_size = Vector2(360.0, 0.0)
	body.add_child(inspector_panel)

	var inspector_margin := MarginContainer.new()
	inspector_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	inspector_margin.add_theme_constant_override("margin_left", 14)
	inspector_margin.add_theme_constant_override("margin_right", 14)
	inspector_margin.add_theme_constant_override("margin_top", 14)
	inspector_margin.add_theme_constant_override("margin_bottom", 14)
	inspector_panel.add_child(inspector_margin)

	_inspector_root = VBoxContainer.new()
	_inspector_root.add_theme_constant_override("separation", 10)
	inspector_margin.add_child(_inspector_root)


func _make_toolbar_button(text_value: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text_value
	button.custom_minimum_size = Vector2(0.0, 40.0)
	button.pressed.connect(callback)
	return button


func _rebuild_graph() -> void:
	_persist_graph_positions()
	_graph_scroll_offset = _graph.scroll_offset
	for child in _graph.get_children():
		if child is GraphNode:
			child.queue_free()
	_graph.clear_connections()

	var army = PlayerArmyRepository.get_selected_army()
	if army == null:
		return

	var army_node := _build_graph_node(
		"army_hq",
		"Army HQ",
		"%s | %d brigades" % [army.commander_name, army.get_brigade_count()],
		army.hq_editor_position,
		"army"
	)
	_graph.add_child(army_node)

	for brigade_value in army.brigades:
		var brigade: BrigadeDefinition = brigade_value
		var brigade_node := _build_graph_node(
			"brigade_%s" % String(brigade.id),
			brigade.display_name,
			"HQ | %d regs" % brigade.get_regiment_count(),
			brigade.hq_editor_position,
			"brigade"
		)
		_graph.add_child(brigade_node)
		_graph.connect_node(army_node.name, 0, brigade_node.name, 0)
		for regiment_value in brigade.regiments:
			var regiment: RegimentDefinition = regiment_value
			var regiment_node := _build_graph_node(
				"regiment_%s" % String(regiment.id),
				regiment.display_name,
				"%s | %d editor coys" % [SimTypes.unit_category_name(regiment.category), regiment.get_company_count()],
				regiment.editor_position,
				"regiment"
			)
			_graph.add_child(regiment_node)
			_graph.connect_node(brigade_node.name, 0, regiment_node.name, 0)

	call_deferred("_restore_graph_scroll_offset")


func _build_graph_node(node_name: String, title_text: String, body_text: String, position_value: Vector2, node_type: String) -> GraphNode:
	var node := GraphNode.new()
	node.name = node_name
	node.title = _compact_node_title(title_text)
	node.tooltip_text = "%s\n%s" % [title_text, body_text]
	node.position_offset = position_value
	node.resizable = false
	match node_type:
		"army":
			node.set_slot(0, false, 0, Color.WHITE, true, 0, Color.WHITE)
		"regiment":
			node.set_slot(0, true, 0, Color.WHITE, false, 0, Color.WHITE)
		_:
			node.set_slot(0, true, 0, Color.WHITE, true, 0, Color.WHITE)
	node.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_select_graph_node(node_type, node_name)
	)

	var body := VBoxContainer.new()
	body.custom_minimum_size = Vector2(132.0, 38.0)
	body.add_theme_constant_override("separation", 4)
	node.add_child(body)

	var summary := Label.new()
	summary.text = body_text
	summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	summary.clip_text = true
	summary.custom_minimum_size = Vector2(120.0, 0.0)
	summary.add_theme_font_size_override("font_size", 12)
	body.add_child(summary)
	return node


func _select_graph_node(node_type: String, node_name: String) -> void:
	_selected_node_type = node_type
	match node_type:
		"brigade":
			_selected_brigade_id = StringName(node_name.trim_prefix("brigade_"))
			_selected_regiment_id = &""
		"regiment":
			_selected_regiment_id = StringName(node_name.trim_prefix("regiment_"))
			var army = PlayerArmyRepository.get_selected_army()
			if army != null:
				var brigade = army.find_brigade_for_regiment(_selected_regiment_id)
				_selected_brigade_id = brigade.id if brigade != null else &""
		_:
			_selected_brigade_id = &""
			_selected_regiment_id = &""
	_rebuild_inspector()


func _rebuild_inspector() -> void:
	for child in _inspector_root.get_children():
		child.queue_free()
	var army = PlayerArmyRepository.get_selected_army()
	if army == null:
		return
	match _selected_node_type:
		"brigade":
			var brigade = army.find_brigade(_selected_brigade_id)
			if brigade != null:
				_build_brigade_inspector(brigade)
				return
		"regiment":
			var regiment = army.find_regiment(_selected_regiment_id)
			if regiment != null:
				_build_regiment_inspector(regiment)
				return
	_build_army_inspector(army)


func _build_army_inspector(army) -> void:
	_inspector_root.add_child(_make_title("Army"))
	_inspector_root.add_child(_make_line_edit("Army Name", army.display_name, func(text_value: String) -> void:
		army.display_name = text_value
		PlayerArmyRepository.notify_army_changed()
	))
	_inspector_root.add_child(_make_line_edit("Army Commander", army.commander_name, func(text_value: String) -> void:
		army.commander_name = text_value
		PlayerArmyRepository.notify_army_changed()
	))
	_inspector_root.add_child(_make_info_label("Brigades: %d\nBattalions: %d\nEditor Companies: %d" % [
		army.get_brigade_count(),
		army.get_regiment_count(),
		army.get_company_count(),
	]))


func _build_brigade_inspector(brigade) -> void:
	_inspector_root.add_child(_make_title("Brigade HQ"))
	_inspector_root.add_child(_make_line_edit("Brigade Name", brigade.display_name, func(text_value: String) -> void:
		brigade.display_name = text_value
		PlayerArmyRepository.notify_army_changed()
	))
	_inspector_root.add_child(_make_line_edit("General", brigade.general_name, func(text_value: String) -> void:
		brigade.general_name = text_value
		PlayerArmyRepository.notify_army_changed()
	))
	_inspector_root.add_child(_make_enum_option_field(
		"Deployment Role",
		_get_brigade_deployment_role_options(),
		brigade.deployment_role,
		func(next_role: int) -> void:
			brigade.deployment_role = next_role
			PlayerArmyRepository.notify_army_changed()
	))
	_inspector_root.add_child(_make_info_label("Battalions: %d\nEditor Companies: %d" % [
		brigade.get_regiment_count(),
		brigade.get_company_count(),
	]))


func _build_regiment_inspector(regiment) -> void:
	_inspector_root.add_child(_make_title("Battalion"))
	_inspector_root.add_child(_make_line_edit("Battalion Name", regiment.display_name, func(text_value: String) -> void:
		regiment.display_name = text_value
		PlayerArmyRepository.notify_army_changed()
	))
	_inspector_root.add_child(_make_line_edit("Commander", regiment.commander_name, func(text_value: String) -> void:
		regiment.commander_name = text_value
		PlayerArmyRepository.notify_army_changed()
	))

	var category_label := Label.new()
	category_label.text = "Category"
	_inspector_root.add_child(category_label)
	var category_select := OptionButton.new()
	category_select.add_item("Infantry", SimTypes.UnitCategory.INFANTRY)
	category_select.add_item("Cavalry", SimTypes.UnitCategory.CAVALRY)
	category_select.add_item("Artillery", SimTypes.UnitCategory.ARTILLERY)
	var selected_category_index: int = [SimTypes.UnitCategory.INFANTRY, SimTypes.UnitCategory.CAVALRY, SimTypes.UnitCategory.ARTILLERY].find(regiment.category)
	category_select.select(max(selected_category_index, 0))
	category_select.item_selected.connect(func(index: int) -> void:
		var next_category: int = category_select.get_item_id(index)
		regiment.set_category(next_category)
		regiment.commander_profile_id = _get_default_command_profile_id(next_category, regiment.get_company_count())
		regiment.banner_profile_id = _get_default_banner_profile_id(next_category)
		PlayerArmyRepository.notify_army_changed()
	)
	_inspector_root.add_child(category_select)

	var on_command_profile_changed := func(profile_id: StringName) -> void:
		regiment.commander_profile_id = profile_id
		PlayerArmyRepository.notify_army_changed()
	var command_profile_filter := func(profile_value) -> bool:
		return profile_value.max_companies >= regiment.get_company_count()
	_inspector_root.add_child(_make_option_field(
		"Commander Profile",
		RegimentProfileLibrary.get_command_profiles_for_category(regiment.category),
		regiment.commander_profile_id,
		on_command_profile_changed,
		command_profile_filter
	))

	var on_banner_profile_changed := func(profile_id: StringName) -> void:
		regiment.banner_profile_id = profile_id
		PlayerArmyRepository.notify_army_changed()
	_inspector_root.add_child(_make_option_field(
		"Banner",
		RegimentProfileLibrary.get_banner_profiles_for_category(regiment.category),
		regiment.banner_profile_id,
		on_banner_profile_changed
	))
	_inspector_root.add_child(_make_enum_option_field(
		"Deployment Role",
		_get_regiment_deployment_role_options(),
		regiment.deployment_role,
		func(next_role: int) -> void:
			regiment.deployment_role = next_role
			PlayerArmyRepository.notify_army_changed()
	))

	_inspector_root.add_child(_make_info_label("Editor Companies: %d" % regiment.get_company_count()))
	_rebuild_company_controls(regiment)


func _rebuild_company_controls(regiment) -> void:
	var profile = _get_command_profile_by_id(regiment.commander_profile_id, regiment.category)
	var max_companies: int = profile.max_companies if profile != null else regiment.get_company_count()
	for company_type in _get_editable_company_types(regiment.category):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var label := Label.new()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.text = "%s: %d" % [SimTypes.company_type_name(company_type), regiment.count_company_type(company_type)]
		row.add_child(label)
		var remove_button := Button.new()
		remove_button.text = "-"
		remove_button.disabled = regiment.count_company_type(company_type) <= 0 or regiment.get_company_count() <= 1
		remove_button.pressed.connect(func() -> void:
			if regiment.remove_company(company_type):
				PlayerArmyRepository.notify_army_changed()
		)
		row.add_child(remove_button)
		var add_button := Button.new()
		add_button.text = "+"
		add_button.disabled = regiment.get_company_count() >= max_companies
		add_button.pressed.connect(func() -> void:
			if regiment.get_company_count() >= max_companies:
				return
			regiment.add_company(company_type)
			PlayerArmyRepository.notify_army_changed()
		)
		row.add_child(add_button)
		_inspector_root.add_child(row)


func _make_title(text_value: String) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", 24)
	return label


func _make_info_label(text_value: String) -> Label:
	var label := Label.new()
	label.text = text_value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _make_line_edit(label_text: String, value: String, callback: Callable) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	var label := Label.new()
	label.text = label_text
	box.add_child(label)
	var line_edit := LineEdit.new()
	line_edit.text = value
	line_edit.text_submitted.connect(func(text_value: String) -> void:
		callback.call(text_value)
	)
	line_edit.focus_exited.connect(func() -> void:
		callback.call(line_edit.text)
	)
	box.add_child(line_edit)
	return box


func _make_option_field(label_text: String, profiles: Array, selected_profile_id: StringName, callback: Callable, filter_callback: Callable = Callable()) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	var label := Label.new()
	label.text = label_text
	box.add_child(label)
	var select := OptionButton.new()
	var selected_index: int = 0
	var item_index: int = 0
	for profile_value in profiles:
		if filter_callback.is_valid() and not filter_callback.call(profile_value):
			continue
		select.add_item(profile_value.display_name)
		select.set_item_metadata(item_index, profile_value.id)
		if profile_value.id == selected_profile_id:
			selected_index = item_index
		item_index += 1
	select.select(selected_index)
	select.item_selected.connect(func(index: int) -> void:
		callback.call(StringName(select.get_item_metadata(index)))
	)
	box.add_child(select)
	return box


func _make_enum_option_field(label_text: String, options: Array, selected_value: int, callback: Callable) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	var label := Label.new()
	label.text = label_text
	box.add_child(label)
	var select := OptionButton.new()
	var selected_index: int = 0
	for option_index in range(options.size()):
		var option: Dictionary = options[option_index]
		select.add_item(String(option.get("label", "Option")), int(option.get("id", option_index)))
		if int(option.get("id", -1)) == selected_value:
			selected_index = option_index
	select.select(selected_index)
	select.item_selected.connect(func(index: int) -> void:
		callback.call(select.get_item_id(index))
	)
	box.add_child(select)
	return box


func _persist_graph_positions() -> void:
	if _graph == null:
		return
	_graph_scroll_offset = _graph.scroll_offset
	var army = PlayerArmyRepository.get_selected_army()
	if army == null:
		return
	for child in _graph.get_children():
		if child is not GraphNode:
			continue
		var node: GraphNode = child
		if node.name.begins_with("brigade_"):
			var brigade = army.find_brigade(StringName(node.name.trim_prefix("brigade_")))
			if brigade != null:
				brigade.hq_editor_position = node.position_offset
		elif node.name == "army_hq":
			army.hq_editor_position = node.position_offset
		elif node.name.begins_with("regiment_"):
			var regiment = army.find_regiment(StringName(node.name.trim_prefix("regiment_")))
			if regiment != null:
				regiment.editor_position = node.position_offset


func _restore_graph_scroll_offset() -> void:
	if _graph == null:
		return
	_graph.scroll_offset = _graph_scroll_offset


func _compact_node_title(title_text: String) -> String:
	const MAX_TITLE_LENGTH := 18
	if title_text.length() <= MAX_TITLE_LENGTH:
		return title_text
	return "%s..." % title_text.substr(0, MAX_TITLE_LENGTH - 3)


func _delete_selected_node() -> void:
	var army = PlayerArmyRepository.get_selected_army()
	if army == null:
		return
	match _selected_node_type:
		"brigade":
			PlayerArmyRepository.remove_brigade(army.id, _selected_brigade_id)
			_selected_node_type = "army"
			_selected_brigade_id = &""
			_selected_regiment_id = &""
		"regiment":
			PlayerArmyRepository.remove_regiment(army.id, _selected_regiment_id)
			_selected_node_type = "brigade"
			_selected_regiment_id = &""
		_:
			return


func _on_repository_changed() -> void:
	_rebuild_graph()
	_rebuild_inspector()


func _get_command_profile_by_id(profile_id: StringName, category: int):
	for profile_value in RegimentProfileLibrary.get_command_profiles_for_category(category):
		if profile_value.id == profile_id:
			return profile_value
	return null


func _get_editable_company_types(category: int) -> Array:
	match category:
		SimTypes.UnitCategory.CAVALRY:
			return [SimTypes.CompanyType.CAVALRY]
		SimTypes.UnitCategory.ARTILLERY:
			return [SimTypes.CompanyType.ARTILLERY]
		_:
			return [SimTypes.CompanyType.MUSKETEERS, SimTypes.CompanyType.PIKEMEN]


func _get_default_command_profile_id(category: int, company_count: int) -> StringName:
	if company_count >= 8 and category == SimTypes.UnitCategory.INFANTRY:
		return &"tercio_maestre"
	match category:
		SimTypes.UnitCategory.CAVALRY:
			return &"cavalry_standard"
		SimTypes.UnitCategory.ARTILLERY:
			return &"artillery_standard"
		_:
			return &"expanded_colonel" if company_count > 4 else &"infantry_standard"


func _get_default_banner_profile_id(category: int) -> StringName:
	match category:
		SimTypes.UnitCategory.CAVALRY:
			return &"guard_colors"
		_:
			return &"standard_colors"


func _get_brigade_deployment_role_options() -> Array:
	return [
		{"id": SimTypes.BrigadeDeploymentRole.LEFT_WING, "label": SimTypes.brigade_deployment_role_name(SimTypes.BrigadeDeploymentRole.LEFT_WING)},
		{"id": SimTypes.BrigadeDeploymentRole.CENTER, "label": SimTypes.brigade_deployment_role_name(SimTypes.BrigadeDeploymentRole.CENTER)},
		{"id": SimTypes.BrigadeDeploymentRole.RIGHT_WING, "label": SimTypes.brigade_deployment_role_name(SimTypes.BrigadeDeploymentRole.RIGHT_WING)},
		{"id": SimTypes.BrigadeDeploymentRole.VANGUARD, "label": SimTypes.brigade_deployment_role_name(SimTypes.BrigadeDeploymentRole.VANGUARD)},
		{"id": SimTypes.BrigadeDeploymentRole.SECOND_LINE, "label": SimTypes.brigade_deployment_role_name(SimTypes.BrigadeDeploymentRole.SECOND_LINE)},
		{"id": SimTypes.BrigadeDeploymentRole.RESERVE, "label": SimTypes.brigade_deployment_role_name(SimTypes.BrigadeDeploymentRole.RESERVE)},
	]


func _get_regiment_deployment_role_options() -> Array:
	return [
		{"id": SimTypes.RegimentDeploymentRole.LEFT_FLANK, "label": SimTypes.regiment_deployment_role_name(SimTypes.RegimentDeploymentRole.LEFT_FLANK)},
		{"id": SimTypes.RegimentDeploymentRole.CENTER, "label": SimTypes.regiment_deployment_role_name(SimTypes.RegimentDeploymentRole.CENTER)},
		{"id": SimTypes.RegimentDeploymentRole.RIGHT_FLANK, "label": SimTypes.regiment_deployment_role_name(SimTypes.RegimentDeploymentRole.RIGHT_FLANK)},
		{"id": SimTypes.RegimentDeploymentRole.VANGUARD, "label": SimTypes.regiment_deployment_role_name(SimTypes.RegimentDeploymentRole.VANGUARD)},
		{"id": SimTypes.RegimentDeploymentRole.SECOND_LINE, "label": SimTypes.regiment_deployment_role_name(SimTypes.RegimentDeploymentRole.SECOND_LINE)},
		{"id": SimTypes.RegimentDeploymentRole.RESERVE, "label": SimTypes.regiment_deployment_role_name(SimTypes.RegimentDeploymentRole.RESERVE)},
	]
