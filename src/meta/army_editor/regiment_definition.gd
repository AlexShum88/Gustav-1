class_name RegimentDefinition
extends RefCounted

var id: StringName = &""
var display_name: String = ""
var category: int = SimTypes.UnitCategory.INFANTRY
var commander_name: String = ""
var commander_profile_id: StringName = &""
var banner_profile_id: StringName = &""
var deployment_role: int = SimTypes.RegimentDeploymentRole.CENTER
var training: float = 0.7
var companies: Array = []
var editor_position: Vector2 = Vector2.ZERO


func _init(
		regiment_id: StringName = &"",
		name_text: String = "",
		regiment_category: int = SimTypes.UnitCategory.INFANTRY,
		regiment_training: float = 0.7
) -> void:
	id = regiment_id
	display_name = name_text
	category = regiment_category
	training = regiment_training


func clone() -> RegimentDefinition:
	var copy: RegimentDefinition = RegimentDefinition.new(id, display_name, category, training)
	copy.commander_name = commander_name
	copy.commander_profile_id = commander_profile_id
	copy.banner_profile_id = banner_profile_id
	copy.deployment_role = deployment_role
	copy.editor_position = editor_position
	copy.companies = companies.duplicate(true)
	return copy


func get_company_count() -> int:
	return companies.size()


func get_company_types() -> Array:
	var result: Array = []
	for company_value in companies:
		var company: Dictionary = company_value
		result.append(int(company.get("company_type", SimTypes.CompanyType.MUSKETEERS)))
	return result


func count_company_type(company_type: int) -> int:
	var total: int = 0
	for company_value in companies:
		var company: Dictionary = company_value
		if int(company.get("company_type", -1)) == company_type:
			total += 1
	return total


func add_company(company_type: int) -> void:
	companies.append(_make_company_template(company_type, count_company_type(company_type) + 1))


func remove_company(company_type: int) -> bool:
	for company_index in range(companies.size() - 1, -1, -1):
		var company: Dictionary = companies[company_index]
		if int(company.get("company_type", -1)) != company_type:
			continue
		companies.remove_at(company_index)
		_renumber_company_names(company_type)
		return true
	return false


func rebuild_default_companies() -> void:
	companies.clear()
	match category:
		SimTypes.UnitCategory.CAVALRY:
			companies = [
				_make_company_template(SimTypes.CompanyType.CAVALRY, 1),
				_make_company_template(SimTypes.CompanyType.CAVALRY, 2),
				_make_company_template(SimTypes.CompanyType.CAVALRY, 3),
				_make_company_template(SimTypes.CompanyType.CAVALRY, 4),
			]
		SimTypes.UnitCategory.ARTILLERY:
			companies = [
				_make_company_template(SimTypes.CompanyType.ARTILLERY, 1),
				_make_company_template(SimTypes.CompanyType.ARTILLERY, 2),
				_make_company_template(SimTypes.CompanyType.ARTILLERY, 3),
				_make_company_template(SimTypes.CompanyType.ARTILLERY, 4),
			]
		_:
			companies = [
				_make_company_template(SimTypes.CompanyType.MUSKETEERS, 1),
				_make_company_template(SimTypes.CompanyType.PIKEMEN, 1),
				_make_company_template(SimTypes.CompanyType.PIKEMEN, 2),
				_make_company_template(SimTypes.CompanyType.MUSKETEERS, 2),
			]


func set_category(next_category: int) -> void:
	if category == next_category:
		return
	category = next_category
	rebuild_default_companies()


func _make_company_template(company_type: int, ordinal: int) -> Dictionary:
	match company_type:
		SimTypes.CompanyType.CAVALRY:
			var cavalry_weapon: String = "carbine" if ordinal == 1 else "pistol"
			return {
				"name": "%s Squadron" % _get_ordinal_name(ordinal),
				"company_type": SimTypes.CompanyType.CAVALRY,
				"weapon_type": cavalry_weapon,
				"soldiers": 150,
			}
		SimTypes.CompanyType.ARTILLERY:
			return {
				"name": "Battery Section %s" % String.chr(64 + ordinal),
				"company_type": SimTypes.CompanyType.ARTILLERY,
				"weapon_type": "cannon",
				"soldiers": 100,
			}
		SimTypes.CompanyType.PIKEMEN:
			return {
				"name": "%s Pike Company" % _get_ordinal_name(ordinal),
				"company_type": SimTypes.CompanyType.PIKEMEN,
				"weapon_type": "pike",
				"soldiers": 200,
			}
		_:
			return {
				"name": "%s Musketeer Company" % _get_ordinal_name(ordinal),
				"company_type": SimTypes.CompanyType.MUSKETEERS,
				"weapon_type": "musket",
				"soldiers": 200,
			}


func _renumber_company_names(company_type: int) -> void:
	var ordinal: int = 1
	for company_index in range(companies.size()):
		var company: Dictionary = companies[company_index]
		if int(company.get("company_type", -1)) != company_type:
			continue
		var updated: Dictionary = _make_company_template(company_type, ordinal)
		updated["weapon_type"] = company.get("weapon_type", updated.get("weapon_type", "musket"))
		updated["soldiers"] = company.get("soldiers", updated.get("soldiers", 200))
		companies[company_index] = updated
		ordinal += 1


func _get_ordinal_name(index: int) -> String:
	var suffix: String = "th"
	if index % 100 < 11 or index % 100 > 13:
		match index % 10:
			1:
				suffix = "st"
			2:
				suffix = "nd"
			3:
				suffix = "rd"
	return "%d%s" % [index, suffix]
