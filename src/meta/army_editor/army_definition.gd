class_name ArmyDefinition
extends RefCounted

var id: StringName = &""
var display_name: String = ""
var commander_name: String = ""
var is_default_preset: bool = false
var hq_editor_position: Vector2 = Vector2(80.0, 260.0)
var editor_layout_version: int = 0
var brigades: Array = []


func _init(army_id: StringName = &"", name_text: String = "") -> void:
	id = army_id
	display_name = name_text


func clone() -> ArmyDefinition:
	var copy: ArmyDefinition = ArmyDefinition.new(id, display_name)
	copy.commander_name = commander_name
	copy.is_default_preset = is_default_preset
	copy.hq_editor_position = hq_editor_position
	copy.editor_layout_version = editor_layout_version
	copy.brigades = []
	for brigade_value in brigades:
		var brigade: BrigadeDefinition = brigade_value
		copy.brigades.append(brigade.clone())
	return copy


func get_brigade_count() -> int:
	return brigades.size()


func get_regiment_count() -> int:
	var total: int = 0
	for brigade_value in brigades:
		var brigade: BrigadeDefinition = brigade_value
		total += brigade.get_regiment_count()
	return total


func get_company_count() -> int:
	var total: int = 0
	for brigade_value in brigades:
		var brigade: BrigadeDefinition = brigade_value
		total += brigade.get_company_count()
	return total


func add_brigade(brigade: BrigadeDefinition) -> void:
	brigades.append(brigade)


func remove_brigade(brigade_id: StringName) -> bool:
	for brigade_index in range(brigades.size()):
		var brigade: BrigadeDefinition = brigades[brigade_index]
		if brigade.id != brigade_id:
			continue
		brigades.remove_at(brigade_index)
		return true
	return false


func find_brigade(brigade_id: StringName) -> BrigadeDefinition:
	for brigade_value in brigades:
		var brigade: BrigadeDefinition = brigade_value
		if brigade.id == brigade_id:
			return brigade
	return null


func find_regiment(regiment_id: StringName) -> RegimentDefinition:
	for brigade_value in brigades:
		var brigade: BrigadeDefinition = brigade_value
		var regiment: RegimentDefinition = brigade.find_regiment(regiment_id)
		if regiment != null:
			return regiment
	return null


func find_brigade_for_regiment(regiment_id: StringName) -> BrigadeDefinition:
	for brigade_value in brigades:
		var brigade: BrigadeDefinition = brigade_value
		if brigade.find_regiment(regiment_id) != null:
			return brigade
	return null
