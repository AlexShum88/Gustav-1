class_name RegimentController
extends Node2D

const CompanyController = preload("res://src/archive/legacy_formations_demo/company_controller.gd")

signal selection_changed(company: CompanyController)

@export var company_spacing: Vector2 = Vector2(430.0, 320.0)

var companies: Array = []
var selected_company: CompanyController
var current_direction: Vector2 = Vector2.RIGHT


func build_demo_regiment() -> void:
	_clear_companies()
	var configs: Array = [
		{
			"name": "Pike and Shot",
			"type": CompanyController.CompanyType.PIKE_AND_SHOT,
			"position": Vector2(-company_spacing.x * 0.5, -company_spacing.y * 0.5),
		},
		{
			"name": "Cavalry",
			"type": CompanyController.CompanyType.CAVALRY,
			"position": Vector2(company_spacing.x * 0.5, -company_spacing.y * 0.5),
		},
		{
			"name": "Artillery",
			"type": CompanyController.CompanyType.ARTILLERY,
			"position": Vector2(-company_spacing.x * 0.5, company_spacing.y * 0.5),
		},
		{
			"name": "Supply Train",
			"type": CompanyController.CompanyType.WAGONS,
			"position": Vector2(company_spacing.x * 0.5, company_spacing.y * 0.5),
		},
	]
	for config in configs:
		var company: CompanyController = CompanyController.new()
		company.company_name = String(config.get("name", "Company"))
		company.company_type = int(config.get("type", CompanyController.CompanyType.PIKE_AND_SHOT))
		company.position = config.get("position", Vector2.ZERO)
		add_child(company)
		companies.append(company)
	if not companies.is_empty():
		select_company(companies[0])


func select_company(company: CompanyController) -> void:
	selected_company = company
	for company_value in companies:
		company_value.set_selected(company_value == company)
	selection_changed.emit(company)


func select_company_at(world_position: Vector2) -> bool:
	for company in companies:
		if company.contains_global_point(world_position):
			select_company(company)
			return true
	return false


func cycle_selection(step: int = 1) -> void:
	if companies.is_empty():
		return
	var current_index: int = companies.find(selected_company)
	if current_index == -1:
		select_company(companies[0])
		return
	var next_index: int = posmod(current_index + step, companies.size())
	select_company(companies[next_index])


func apply_mode_to_selected(mode: int) -> void:
	if selected_company == null:
		return
	if _is_cycle_mode(mode):
		selected_company.toggle_cycle_mode(mode, current_direction)
		return
	selected_company.apply_mode(mode, current_direction)


func apply_mode_to_all(mode: int) -> void:
	if _is_cycle_mode(mode):
		var should_start: bool = true
		for company_value in companies:
			if company_value._firing_cycle_running and company_value.current_mode == mode:
				should_start = false
				break
		for company_value in companies:
			if should_start:
				company_value.start_cycle_mode(mode, current_direction)
			else:
				company_value.stop_firing_cycle()
				company_value.apply_mode(CompanyController.FormationMode.BATTLE, current_direction)
		return
	for company in companies:
		company.apply_mode(mode, current_direction)


func reset_all() -> void:
	for company in companies:
		company.stop_firing_cycle()
		company.apply_mode(CompanyController.FormationMode.BATTLE, current_direction, true)


func set_direction(direction: Vector2, reapply_current: bool = true) -> void:
	current_direction = direction.normalized() if direction.length_squared() > 0.001 else Vector2.RIGHT
	if not reapply_current:
		return
	for company in companies:
		if company._is_cycle_mode(company.current_mode) and company._firing_cycle_running:
			company.start_cycle_mode(company.current_mode, current_direction)
		else:
			company.apply_mode(company.current_mode, current_direction)


func get_selected_company_name() -> String:
	return selected_company.company_name if selected_company != null else "None"


func get_selected_company_mode_name() -> String:
	if selected_company == null:
		return "None"
	return selected_company.get_mode_name(selected_company.current_mode)


func _clear_companies() -> void:
	for company in companies:
		if is_instance_valid(company):
			company.queue_free()
	companies.clear()


func _is_cycle_mode(mode: int) -> bool:
	return mode == CompanyController.FormationMode.FIRING_CYCLE \
		or mode == CompanyController.FormationMode.COUNTERMARCH \
		or mode == CompanyController.FormationMode.CARACOLE
