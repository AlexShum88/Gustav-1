class_name BrigadeDefinition
extends RefCounted

var id: StringName = &""
var display_name: String = ""
var general_name: String = ""
var deployment_role: int = SimTypes.BrigadeDeploymentRole.CENTER
var hq_editor_position: Vector2 = Vector2.ZERO
var regiments: Array = []


func _init(brigade_id: StringName = &"", name_text: String = "") -> void:
	id = brigade_id
	display_name = name_text


func clone() -> BrigadeDefinition:
	var copy: BrigadeDefinition = BrigadeDefinition.new(id, display_name)
	copy.general_name = general_name
	copy.deployment_role = deployment_role
	copy.hq_editor_position = hq_editor_position
	copy.regiments = []
	for regiment_value in regiments:
		var regiment: RegimentDefinition = regiment_value
		copy.regiments.append(regiment.clone())
	return copy


func get_regiment_count() -> int:
	return regiments.size()


func get_company_count() -> int:
	var total: int = 0
	for regiment_value in regiments:
		var regiment: RegimentDefinition = regiment_value
		total += regiment.get_company_count()
	return total


func add_regiment(regiment: RegimentDefinition) -> void:
	regiments.append(regiment)


func remove_regiment(regiment_id: StringName) -> bool:
	for regiment_index in range(regiments.size()):
		var regiment: RegimentDefinition = regiments[regiment_index]
		if regiment.id != regiment_id:
			continue
		regiments.remove_at(regiment_index)
		return true
	return false


func find_regiment(regiment_id: StringName) -> RegimentDefinition:
	for regiment_value in regiments:
		var regiment: RegimentDefinition = regiment_value
		if regiment.id == regiment_id:
			return regiment
	return null
