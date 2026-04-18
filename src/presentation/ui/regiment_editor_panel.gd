class_name RegimentEditorPanel
extends Panel

signal start_battle_requested()
signal command_profile_selected(profile_id: StringName)
signal banner_profile_selected(profile_id: StringName)
signal add_company_requested(company_type: int)
signal remove_company_requested(company_type: int)

const RegimentProfileLibrary = preload("res://src/simulation/core/regiment_profile_library.gd")

var _title_label: Label
var _status_label: Label
var _commander_select: OptionButton
var _banner_select: OptionButton
var _companies_label: Label
var _company_rows: VBoxContainer
var _start_battle_button: Button
var _is_populating: bool = false
var _selected_regiment_id: StringName = &""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	self_modulate = Color(0.1, 0.12, 0.16, 0.9)
	_build_ui()


func set_editor_state(selected_regiment: Dictionary, pre_battle_active: bool) -> void:
	visible = pre_battle_active
	if not pre_battle_active:
		return
	_selected_regiment_id = StringName(selected_regiment.get("id", ""))
	if selected_regiment.is_empty() or not bool(selected_regiment.get("is_friendly", false)):
		_set_empty_state()
		return
	_is_populating = true
	_title_label.text = "Battalion Editor"
	_status_label.text = "%s\nCategory: %s" % [
		String(selected_regiment.get("true_name", selected_regiment.get("display_name", "Battalion"))),
		SimTypes.unit_category_name(int(selected_regiment.get("category", SimTypes.UnitCategory.INFANTRY))),
	]
	var category: int = int(selected_regiment.get("category", SimTypes.UnitCategory.INFANTRY))
	var company_count: int = int(selected_regiment.get("company_count", 0))
	var max_company_capacity: int = int(selected_regiment.get("max_company_capacity", 0))
	_companies_label.text = "Editor Companies: %d / %d" % [company_count, max_company_capacity]
	_populate_command_profiles(
		category,
		company_count,
		StringName(selected_regiment.get("commander_profile_id", ""))
	)
	_populate_banner_profiles(
		category,
		StringName(selected_regiment.get("banner_profile_id", ""))
	)
	_rebuild_company_rows(
		category,
		selected_regiment.get("company_types", []),
		company_count,
		max_company_capacity
	)
	_is_populating = false


func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	margin.add_child(root)

	_title_label = Label.new()
	_title_label.text = "Battalion Editor"
	root.add_child(_title_label)

	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_status_label)

	root.add_child(_make_field_label("Commander Profile"))
	_commander_select = OptionButton.new()
	_commander_select.item_selected.connect(_on_commander_profile_selected)
	root.add_child(_commander_select)

	root.add_child(_make_field_label("Banner"))
	_banner_select = OptionButton.new()
	_banner_select.item_selected.connect(_on_banner_profile_selected)
	root.add_child(_banner_select)

	_companies_label = Label.new()
	root.add_child(_companies_label)

	_company_rows = VBoxContainer.new()
	_company_rows.add_theme_constant_override("separation", 6)
	root.add_child(_company_rows)

	_start_battle_button = Button.new()
	_start_battle_button.text = "Start Battle"
	_start_battle_button.custom_minimum_size = Vector2(0.0, 34.0)
	_start_battle_button.pressed.connect(func() -> void:
		emit_signal("start_battle_requested")
	)
	root.add_child(_start_battle_button)


func _make_field_label(text_value: String) -> Label:
	var label := Label.new()
	label.text = text_value
	return label


func _set_empty_state() -> void:
	_is_populating = true
	_title_label.text = "Battalion Editor"
	_status_label.text = "Select a friendly battalion to edit it before battle."
	_companies_label.text = ""
	_commander_select.clear()
	_banner_select.clear()
	for child in _company_rows.get_children():
		child.queue_free()
	_is_populating = false


func _populate_command_profiles(category: int, company_count: int, selected_profile_id: StringName) -> void:
	_commander_select.clear()
	var selected_index: int = -1
	var item_index: int = 0
	for profile_value in RegimentProfileLibrary.get_command_profiles_for_category(category):
		var profile: RegimentCommandProfile = profile_value
		if profile.max_companies < company_count:
			continue
		_commander_select.add_item("%s (%d)" % [profile.display_name, profile.max_companies])
		_commander_select.set_item_metadata(item_index, profile.id)
		if profile.id == selected_profile_id:
			selected_index = item_index
		item_index += 1
	if item_index == 0:
		_commander_select.add_item("No valid profiles")
		_commander_select.disabled = true
		return
	_commander_select.disabled = false
	_commander_select.select(max(selected_index, 0))


func _populate_banner_profiles(category: int, selected_profile_id: StringName) -> void:
	_banner_select.clear()
	var selected_index: int = 0
	var item_index: int = 0
	for profile_value in RegimentProfileLibrary.get_banner_profiles_for_category(category):
		var profile: RegimentBannerProfile = profile_value
		_banner_select.add_item(profile.display_name)
		_banner_select.set_item_metadata(item_index, profile.id)
		if profile.id == selected_profile_id:
			selected_index = item_index
		item_index += 1
	_banner_select.disabled = item_index == 0
	if item_index > 0:
		_banner_select.select(selected_index)


func _rebuild_company_rows(category: int, company_types: Array, company_count: int, max_company_capacity: int) -> void:
	for child in _company_rows.get_children():
		child.queue_free()
	var add_enabled: bool = company_count < max_company_capacity
	for company_type in _get_editable_company_types(category):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var count: int = _count_company_type(company_types, company_type)
		var label := Label.new()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.text = "%s: %d" % [SimTypes.company_type_name(company_type), count]
		row.add_child(label)
		var remove_button := Button.new()
		remove_button.text = "-"
		remove_button.disabled = count <= 0 or company_count <= 1
		remove_button.pressed.connect(func() -> void:
			emit_signal("remove_company_requested", company_type)
		)
		row.add_child(remove_button)
		var add_button := Button.new()
		add_button.text = "+"
		add_button.disabled = not add_enabled
		add_button.pressed.connect(func() -> void:
			emit_signal("add_company_requested", company_type)
		)
		row.add_child(add_button)
		_company_rows.add_child(row)


func _get_editable_company_types(category: int) -> Array:
	match category:
		SimTypes.UnitCategory.CAVALRY:
			return [SimTypes.CompanyType.CAVALRY]
		SimTypes.UnitCategory.ARTILLERY:
			return [SimTypes.CompanyType.ARTILLERY]
		_:
			return [SimTypes.CompanyType.MUSKETEERS, SimTypes.CompanyType.PIKEMEN]


func _count_company_type(company_types: Array, company_type: int) -> int:
	var count: int = 0
	for company_type_value in company_types:
		if int(company_type_value) == company_type:
			count += 1
	return count


func _on_commander_profile_selected(item_index: int) -> void:
	if _is_populating or item_index < 0:
		return
	emit_signal("command_profile_selected", StringName(_commander_select.get_item_metadata(item_index)))


func _on_banner_profile_selected(item_index: int) -> void:
	if _is_populating or item_index < 0:
		return
	emit_signal("banner_profile_selected", StringName(_banner_select.get_item_metadata(item_index)))
