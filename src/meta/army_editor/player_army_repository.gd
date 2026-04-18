extends Node

signal armies_changed()
signal selected_army_changed(army_id: StringName)

const ArmyDefinition = preload("res://src/meta/army_editor/army_definition.gd")
const BrigadeDefinition = preload("res://src/meta/army_editor/brigade_definition.gd")
const RegimentDefinition = preload("res://src/meta/army_editor/regiment_definition.gd")
const EDITOR_LAYOUT_VERSION := 1

var _armies: Array = []
var _selected_army_id: StringName = &""
var _next_id: int = 1


func _ready() -> void:
	if _armies.is_empty():
		_create_default_state()


func get_armies() -> Array:
	return _armies


func get_selected_army() -> ArmyDefinition:
	return get_army(_selected_army_id)


func get_selected_army_id() -> StringName:
	return _selected_army_id


func get_army(army_id: StringName) -> ArmyDefinition:
	for army_value in _armies:
		var army: ArmyDefinition = army_value
		if army.id == army_id:
			return army
	return null


func select_army(army_id: StringName) -> void:
	if get_army(army_id) == null:
		return
	if _selected_army_id == army_id:
		return
	_selected_army_id = army_id
	selected_army_changed.emit(_selected_army_id)


func create_new_army() -> ArmyDefinition:
	var army: ArmyDefinition = ArmyDefinition.new(_make_id("army"), "New Army %d" % _next_id)
	army.commander_name = "Army Commander"
	army.is_default_preset = false
	army.hq_editor_position = Vector2(80.0, 260.0)
	army.editor_layout_version = EDITOR_LAYOUT_VERSION
	var brigade: BrigadeDefinition = BrigadeDefinition.new(_make_id("brigade"), "New Brigade")
	brigade.general_name = "Brigade General"
	brigade.deployment_role = SimTypes.BrigadeDeploymentRole.CENTER
	brigade.hq_editor_position = Vector2(340.0, 220.0)
	var regiment: RegimentDefinition = RegimentDefinition.new(_make_id("regiment"), "New Battalion", SimTypes.UnitCategory.INFANTRY, 0.7)
	regiment.commander_name = "Major"
	regiment.commander_profile_id = &"infantry_standard"
	regiment.banner_profile_id = &"standard_colors"
	regiment.deployment_role = SimTypes.RegimentDeploymentRole.CENTER
	regiment.editor_position = Vector2(580.0, 220.0)
	regiment.rebuild_default_companies()
	brigade.add_regiment(regiment)
	army.add_brigade(brigade)
	_armies.append(army)
	_selected_army_id = army.id
	armies_changed.emit()
	selected_army_changed.emit(_selected_army_id)
	return army


func duplicate_army(army_id: StringName) -> ArmyDefinition:
	var source: ArmyDefinition = get_army(army_id)
	if source == null:
		return null
	var copy: ArmyDefinition = source.clone()
	copy.id = _make_id("army")
	copy.display_name = "%s Copy" % source.display_name
	copy.is_default_preset = false
	for brigade_value in copy.brigades:
		var brigade: BrigadeDefinition = brigade_value
		brigade.id = _make_id("brigade")
		for regiment_value in brigade.regiments:
			var regiment: RegimentDefinition = regiment_value
			regiment.id = _make_id("regiment")
	ensure_army_editor_layout(copy)
	_armies.append(copy)
	_selected_army_id = copy.id
	armies_changed.emit()
	selected_army_changed.emit(_selected_army_id)
	return copy


func delete_army(army_id: StringName) -> void:
	for army_index in range(_armies.size()):
		var army: ArmyDefinition = _armies[army_index]
		if army.id != army_id or army.is_default_preset:
			continue
		_armies.remove_at(army_index)
		if _selected_army_id == army_id:
			_selected_army_id = _armies[0].id if not _armies.is_empty() else &""
			selected_army_changed.emit(_selected_army_id)
		armies_changed.emit()
		return


func notify_army_changed() -> void:
	armies_changed.emit()


func create_brigade(army_id: StringName) -> BrigadeDefinition:
	var army: ArmyDefinition = get_army(army_id)
	if army == null:
		return null
	ensure_army_editor_layout(army)
	var brigade: BrigadeDefinition = BrigadeDefinition.new(_make_id("brigade"), "Brigade %d" % (army.get_brigade_count() + 1))
	brigade.general_name = "%s General" % brigade.display_name
	brigade.deployment_role = _get_default_brigade_deployment_role(army.get_brigade_count())
	var brigade_index: int = army.get_brigade_count()
	var brigade_column: int = int(floor(float(brigade_index) / 4.0))
	var brigade_row: int = brigade_index % 4
	brigade.hq_editor_position = Vector2(
		340.0 + float(brigade_column) * 220.0,
		180.0 + float(brigade_row) * 110.0
	)
	army.add_brigade(brigade)
	armies_changed.emit()
	return brigade


func create_regiment(army_id: StringName, brigade_id: StringName, category: int = SimTypes.UnitCategory.INFANTRY) -> RegimentDefinition:
	var army: ArmyDefinition = get_army(army_id)
	if army == null:
		return null
	ensure_army_editor_layout(army)
	var brigade: BrigadeDefinition = army.find_brigade(brigade_id)
	if brigade == null:
		return null
	var regiment: RegimentDefinition = RegimentDefinition.new(_make_id("regiment"), "Battalion %d" % (brigade.get_regiment_count() + 1), category, 0.7)
	regiment.commander_name = "Major"
	regiment.commander_profile_id = _get_default_command_profile_id(category, 4)
	regiment.banner_profile_id = _get_default_banner_profile_id(category)
	regiment.deployment_role = _get_default_regiment_deployment_role(category, brigade.get_regiment_count())
	var regiment_index: int = brigade.get_regiment_count()
	var regiment_column: int = int(floor(float(regiment_index) / 4.0))
	var regiment_row: int = regiment_index % 4
	regiment.editor_position = brigade.hq_editor_position + Vector2(
		220.0 + float(regiment_column) * 180.0,
		float(regiment_row - 1) * 86.0
	)
	regiment.rebuild_default_companies()
	brigade.add_regiment(regiment)
	armies_changed.emit()
	return regiment


func remove_brigade(army_id: StringName, brigade_id: StringName) -> void:
	var army: ArmyDefinition = get_army(army_id)
	if army == null or army.get_brigade_count() <= 1:
		return
	if army.remove_brigade(brigade_id):
		armies_changed.emit()


func remove_regiment(army_id: StringName, regiment_id: StringName) -> void:
	var army: ArmyDefinition = get_army(army_id)
	if army == null:
		return
	var brigade: BrigadeDefinition = army.find_brigade_for_regiment(regiment_id)
	if brigade == null or brigade.get_regiment_count() <= 1:
		return
	if brigade.remove_regiment(regiment_id):
		armies_changed.emit()


func _create_default_state() -> void:
	var army: ArmyDefinition = ArmyDefinition.new(_make_id("army"), "Blue Army")
	army.commander_name = "Field Commander"
	army.is_default_preset = true
	army.hq_editor_position = Vector2(80.0, 260.0)

	var line_brigade: BrigadeDefinition = BrigadeDefinition.new(_make_id("brigade"), "1st Line Brigade")
	line_brigade.general_name = "Line General"
	line_brigade.deployment_role = SimTypes.BrigadeDeploymentRole.CENTER
	line_brigade.hq_editor_position = Vector2(180.0, 120.0)
	line_brigade.add_regiment(_make_infantry_regiment("Blue Forward I", Vector2(20.0, 260.0), 0.72, SimTypes.RegimentDeploymentRole.LEFT_FLANK))
	line_brigade.add_regiment(_make_infantry_regiment("Blue Forward II", Vector2(200.0, 260.0), 0.70, SimTypes.RegimentDeploymentRole.CENTER))
	line_brigade.add_regiment(_make_infantry_regiment("Blue Forward III", Vector2(380.0, 260.0), 0.69, SimTypes.RegimentDeploymentRole.RIGHT_FLANK))
	line_brigade.add_regiment(_make_infantry_regiment("Blue Reserve I", Vector2(110.0, 380.0), 0.68, SimTypes.RegimentDeploymentRole.SECOND_LINE))
	line_brigade.add_regiment(_make_infantry_regiment("Blue Reserve II", Vector2(290.0, 380.0), 0.67, SimTypes.RegimentDeploymentRole.RESERVE))
	line_brigade.add_regiment(_make_artillery_regiment("Blue Grand Battery", Vector2(200.0, 500.0), 0.76, SimTypes.RegimentDeploymentRole.RESERVE))
	army.add_brigade(line_brigade)

	var mixed_brigade: BrigadeDefinition = BrigadeDefinition.new(_make_id("brigade"), "2nd Mixed Brigade")
	mixed_brigade.general_name = "Mixed Brigade General"
	mixed_brigade.deployment_role = SimTypes.BrigadeDeploymentRole.RIGHT_WING
	mixed_brigade.hq_editor_position = Vector2(820.0, 120.0)
	mixed_brigade.add_regiment(_make_infantry_regiment("Blue Fusiliers", Vector2(660.0, 260.0), 0.74, SimTypes.RegimentDeploymentRole.LEFT_FLANK))
	mixed_brigade.add_regiment(_make_infantry_regiment("Blue Shot Battalion", Vector2(840.0, 260.0), 0.71, SimTypes.RegimentDeploymentRole.CENTER))
	mixed_brigade.add_regiment(_make_cavalry_regiment("Blue Guard Horse", Vector2(1020.0, 260.0), 0.82, SimTypes.RegimentDeploymentRole.VANGUARD))
	mixed_brigade.add_regiment(_make_cavalry_regiment("Blue Cuirassiers", Vector2(1110.0, 380.0), 0.79, SimTypes.RegimentDeploymentRole.RIGHT_FLANK))
	mixed_brigade.add_regiment(_make_infantry_regiment("Blue Rear Foot", Vector2(750.0, 380.0), 0.70, SimTypes.RegimentDeploymentRole.RESERVE))
	army.add_brigade(mixed_brigade)

	var tercio_brigade: BrigadeDefinition = BrigadeDefinition.new(_make_id("brigade"), "4th Tercio Brigade")
	tercio_brigade.general_name = "Maestre de Campo"
	tercio_brigade.deployment_role = SimTypes.BrigadeDeploymentRole.SECOND_LINE
	tercio_brigade.hq_editor_position = Vector2(520.0, 720.0)
	tercio_brigade.add_regiment(_make_spanish_tercio_regiment("Blue Spanish Tercio", Vector2(420.0, 860.0), SimTypes.RegimentDeploymentRole.CENTER))
	army.add_brigade(tercio_brigade)
 
	var light_brigade: BrigadeDefinition = BrigadeDefinition.new(_make_id("brigade"), "3rd Light Brigade")
	light_brigade.general_name = "Light Brigade General"
	light_brigade.deployment_role = SimTypes.BrigadeDeploymentRole.LEFT_WING
	light_brigade.hq_editor_position = Vector2(620.0, 520.0)
	light_brigade.add_regiment(_make_infantry_regiment("Blue Left Foot", Vector2(540.0, 640.0), 0.68, SimTypes.RegimentDeploymentRole.LEFT_FLANK))
	light_brigade.add_regiment(_make_infantry_regiment("Blue Center Foot", Vector2(620.0, 640.0), 0.69, SimTypes.RegimentDeploymentRole.CENTER))
	light_brigade.add_regiment(_make_infantry_regiment("Blue Right Foot", Vector2(700.0, 640.0), 0.68, SimTypes.RegimentDeploymentRole.RIGHT_FLANK))
	light_brigade.add_regiment(_make_cavalry_regiment("Blue Light Horse", Vector2(620.0, 740.0), 0.72, SimTypes.RegimentDeploymentRole.VANGUARD))
	army.add_brigade(light_brigade)
	_normalize_army_editor_layout(army)

	_armies = [army]
	_selected_army_id = army.id
	armies_changed.emit()
	selected_army_changed.emit(_selected_army_id)


func _make_infantry_regiment(name_text: String, editor_position: Vector2, training: float, deployment_role: int = SimTypes.RegimentDeploymentRole.CENTER) -> RegimentDefinition:
	var regiment: RegimentDefinition = RegimentDefinition.new(_make_id("regiment"), name_text, SimTypes.UnitCategory.INFANTRY, training)
	regiment.commander_name = "%s Major" % name_text
	regiment.commander_profile_id = &"infantry_standard"
	regiment.banner_profile_id = &"standard_colors"
	regiment.deployment_role = deployment_role
	regiment.editor_position = editor_position
	regiment.rebuild_default_companies()
	return regiment


func _make_cavalry_regiment(name_text: String, editor_position: Vector2, training: float, deployment_role: int = SimTypes.RegimentDeploymentRole.CENTER) -> RegimentDefinition:
	var regiment: RegimentDefinition = RegimentDefinition.new(_make_id("regiment"), name_text, SimTypes.UnitCategory.CAVALRY, training)
	regiment.commander_name = "%s Major" % name_text
	regiment.commander_profile_id = &"cavalry_standard"
	regiment.banner_profile_id = &"guard_colors"
	regiment.deployment_role = deployment_role
	regiment.editor_position = editor_position
	regiment.rebuild_default_companies()
	return regiment


func _make_artillery_regiment(name_text: String, editor_position: Vector2, training: float, deployment_role: int = SimTypes.RegimentDeploymentRole.RESERVE) -> RegimentDefinition:
	var regiment: RegimentDefinition = RegimentDefinition.new(_make_id("regiment"), name_text, SimTypes.UnitCategory.ARTILLERY, training)
	regiment.commander_name = "%s Major" % name_text
	regiment.commander_profile_id = &"artillery_standard"
	regiment.banner_profile_id = &"standard_colors"
	regiment.deployment_role = deployment_role
	regiment.editor_position = editor_position
	regiment.rebuild_default_companies()
	return regiment


func _make_spanish_tercio_regiment(name_text: String, editor_position: Vector2, deployment_role: int = SimTypes.RegimentDeploymentRole.CENTER) -> RegimentDefinition:
	var regiment: RegimentDefinition = RegimentDefinition.new(_make_id("regiment"), name_text, SimTypes.UnitCategory.INFANTRY, 0.78)
	regiment.commander_name = "Maestre de Campo"
	regiment.commander_profile_id = &"tercio_maestre"
	regiment.banner_profile_id = &"tercio_colors"
	regiment.deployment_role = deployment_role
	regiment.editor_position = editor_position
	regiment.companies = [
		{"name": "1st Musketeer Company", "company_type": SimTypes.CompanyType.MUSKETEERS, "weapon_type": "musket", "soldiers": 200},
		{"name": "2nd Musketeer Company", "company_type": SimTypes.CompanyType.MUSKETEERS, "weapon_type": "musket", "soldiers": 200},
		{"name": "3rd Musketeer Company", "company_type": SimTypes.CompanyType.MUSKETEERS, "weapon_type": "musket", "soldiers": 200},
		{"name": "4th Musketeer Company", "company_type": SimTypes.CompanyType.MUSKETEERS, "weapon_type": "musket", "soldiers": 200},
		{"name": "1st Pike Company", "company_type": SimTypes.CompanyType.PIKEMEN, "weapon_type": "pike", "soldiers": 200},
		{"name": "2nd Pike Company", "company_type": SimTypes.CompanyType.PIKEMEN, "weapon_type": "pike", "soldiers": 200},
		{"name": "3rd Pike Company", "company_type": SimTypes.CompanyType.PIKEMEN, "weapon_type": "pike", "soldiers": 200},
		{"name": "4th Pike Company", "company_type": SimTypes.CompanyType.PIKEMEN, "weapon_type": "pike", "soldiers": 200},
	]
	return regiment


func _make_id(prefix: String) -> StringName:
	var value: StringName = StringName("%s_%03d" % [prefix, _next_id])
	_next_id += 1
	return value


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


func _get_default_brigade_deployment_role(brigade_index: int) -> int:
	var sequence: Array = [
		SimTypes.BrigadeDeploymentRole.CENTER,
		SimTypes.BrigadeDeploymentRole.LEFT_WING,
		SimTypes.BrigadeDeploymentRole.RIGHT_WING,
		SimTypes.BrigadeDeploymentRole.SECOND_LINE,
		SimTypes.BrigadeDeploymentRole.RESERVE,
	]
	return int(sequence[brigade_index % sequence.size()])


func _get_default_regiment_deployment_role(category: int, regiment_index: int) -> int:
	if category == SimTypes.UnitCategory.ARTILLERY:
		return SimTypes.RegimentDeploymentRole.RESERVE
	var sequence: Array = [
		SimTypes.RegimentDeploymentRole.LEFT_FLANK,
		SimTypes.RegimentDeploymentRole.CENTER,
		SimTypes.RegimentDeploymentRole.RIGHT_FLANK,
		SimTypes.RegimentDeploymentRole.SECOND_LINE,
		SimTypes.RegimentDeploymentRole.RESERVE,
		SimTypes.RegimentDeploymentRole.VANGUARD,
	]
	return int(sequence[regiment_index % sequence.size()])


func ensure_army_editor_layout(army: ArmyDefinition) -> void:
	if army == null:
		return
	if army.editor_layout_version >= EDITOR_LAYOUT_VERSION:
		return
	_normalize_army_editor_layout(army)


func _normalize_army_editor_layout(army: ArmyDefinition) -> void:
	if army == null:
		return
	var brigade_count: int = max(army.get_brigade_count(), 1)
	var top_y: float = 180.0
	var spacing_y: float = 140.0
	var content_height: float = float(brigade_count - 1) * spacing_y
	army.hq_editor_position = Vector2(80.0, top_y + content_height * 0.5)

	for brigade_index in range(army.brigades.size()):
		var brigade: BrigadeDefinition = army.brigades[brigade_index]
		brigade.hq_editor_position = Vector2(340.0, top_y + float(brigade_index) * spacing_y)
		var regiment_count: int = max(brigade.get_regiment_count(), 1)
		var regiment_top_y: float = brigade.hq_editor_position.y - (float(regiment_count - 1) * 86.0 * 0.5)
		for regiment_index in range(brigade.regiments.size()):
			var regiment: RegimentDefinition = brigade.regiments[regiment_index]
			var regiment_column: int = int(floor(float(regiment_index) / 4.0))
			var regiment_row: int = regiment_index % 4
			regiment.editor_position = Vector2(
				580.0 + float(regiment_column) * 190.0,
				regiment_top_y + float(regiment_row) * 86.0
			)
	army.editor_layout_version = EDITOR_LAYOUT_VERSION
