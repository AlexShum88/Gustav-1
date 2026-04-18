class_name BehaviorRuleset
extends RefCounted


var doctrines: Dictionary = {}


func _init() -> void:
	_build_default_doctrines()


func get_doctrine(doctrine_id: StringName) -> BehaviorDoctrine:
	var doctrine: BehaviorDoctrine = doctrines.get(doctrine_id)
	if doctrine != null:
		return doctrine
	return doctrines.get(&"default")


func get_effective_fire_range(regiment: Battalion) -> float:
	var doctrine: BehaviorDoctrine = get_doctrine(regiment.behavior_doctrine_id)
	return regiment.get_attack_range() * doctrine.effective_fire_range_multiplier


func get_move_speed(regiment: Battalion, terrain: TerrainCell) -> float:
	var doctrine: BehaviorDoctrine = get_doctrine(regiment.behavior_doctrine_id)
	var move_speed: float = regiment.base_speed * terrain.move_multiplier * regiment.formation.get_speed_multiplier()
	if regiment.current_order_type == SimTypes.OrderType.MARCH:
		move_speed *= doctrine.march_speed_multiplier
	if regiment.current_order_type == SimTypes.OrderType.ATTACK:
		move_speed *= doctrine.attack_speed_multiplier
	if regiment.fatigue > 0.6:
		move_speed *= doctrine.high_fatigue_speed_multiplier
	return move_speed


func get_reserve_goal(regiment: Battalion, goal: Vector2) -> Vector2:
	var doctrine: BehaviorDoctrine = get_doctrine(regiment.behavior_doctrine_id)
	var direction: Vector2 = (goal - regiment.position).normalized()
	if direction.length_squared() <= 0.001:
		return goal
	return goal - direction * doctrine.reserve_offset_distance


func should_deploy_on_contact(regiment: Battalion, nearby_enemy_distance: float) -> bool:
	var doctrine: BehaviorDoctrine = get_doctrine(regiment.behavior_doctrine_id)
	return nearby_enemy_distance <= doctrine.contact_deploy_distance


func should_form_square(regiment: Battalion, nearby_enemy: Battalion, nearby_enemy_distance: float) -> bool:
	var doctrine: BehaviorDoctrine = get_doctrine(regiment.behavior_doctrine_id)
	return regiment.category == SimTypes.UnitCategory.INFANTRY \
		and nearby_enemy != null \
		and nearby_enemy.category == SimTypes.UnitCategory.CAVALRY \
		and nearby_enemy_distance <= doctrine.anti_cavalry_square_distance


func should_retreat_on_flank_collapse(regiment: Battalion, sim: BattleSimulation) -> bool:
	var doctrine: BehaviorDoctrine = get_doctrine(regiment.behavior_doctrine_id)
	var local_enemy_pressure: int = sim.count_enemy_regiments_near(regiment.position, regiment.army_id, doctrine.flank_pressure_radius)
	var local_friendly_support: int = sim.count_friendly_regiments_near(regiment.position, regiment.army_id, doctrine.flank_pressure_radius)
	return local_enemy_pressure > local_friendly_support + doctrine.flank_pressure_margin


func _build_default_doctrines() -> void:
	var default_doctrine: BehaviorDoctrine = BehaviorDoctrine.new(&"default", "Default Line Behavior")
	default_doctrine.firearm_contact_mode = SimTypes.FirearmContactMode.HALT_AND_FIRE
	default_doctrine.shock_contact_mode = SimTypes.ShockContactMode.ASSAULT
	default_doctrine.fire_hold_distance_ratio = 0.92
	default_doctrine.assault_distance_ratio = 1.12
	default_doctrine.retarget_distance_ratio = 0.8
	default_doctrine.disengage_suppression_threshold = 0.48
	default_doctrine.disengage_casualty_rate_threshold = 0.08
	default_doctrine.assault_confidence_threshold = 0.7
	default_doctrine.withdraw_distance = 135.0
	default_doctrine.recovery_duration = 1.8
	default_doctrine.state_hold_duration = 1.2
	default_doctrine.firefight_anchor_leash = 10.0
	doctrines[default_doctrine.id] = default_doctrine

	var cavalry_mobile: BehaviorDoctrine = BehaviorDoctrine.new(&"cavalry_mobile", "Mobile Cavalry Behavior")
	cavalry_mobile.effective_fire_range_multiplier = 0.45
	cavalry_mobile.march_speed_multiplier = 1.22
	cavalry_mobile.attack_speed_multiplier = 1.0
	cavalry_mobile.reserve_offset_distance = 60.0
	cavalry_mobile.contact_deploy_distance = 180.0
	cavalry_mobile.flank_pressure_radius = 210.0
	cavalry_mobile.firearm_contact_mode = SimTypes.FirearmContactMode.ADVANCE_BY_FIRE
	cavalry_mobile.shock_contact_mode = SimTypes.ShockContactMode.ASSAULT
	cavalry_mobile.fire_hold_distance_ratio = 0.86
	cavalry_mobile.assault_distance_ratio = 1.3
	cavalry_mobile.retarget_distance_ratio = 0.72
	cavalry_mobile.disengage_suppression_threshold = 0.34
	cavalry_mobile.disengage_casualty_rate_threshold = 0.06
	cavalry_mobile.assault_confidence_threshold = 0.6
	cavalry_mobile.withdraw_distance = 170.0
	cavalry_mobile.recovery_duration = 2.6
	cavalry_mobile.state_hold_duration = 1.1
	cavalry_mobile.firefight_anchor_leash = 16.0
	doctrines[cavalry_mobile.id] = cavalry_mobile

	var artillery_static: BehaviorDoctrine = BehaviorDoctrine.new(&"artillery_static", "Artillery Battery Behavior")
	artillery_static.effective_fire_range_multiplier = 0.82
	artillery_static.march_speed_multiplier = 1.08
	artillery_static.attack_speed_multiplier = 0.82
	artillery_static.high_fatigue_speed_multiplier = 0.84
	artillery_static.reserve_offset_distance = 110.0
	artillery_static.contact_deploy_distance = 280.0
	artillery_static.flank_pressure_radius = 220.0
	artillery_static.firearm_contact_mode = SimTypes.FirearmContactMode.HALT_AND_FIRE
	artillery_static.shock_contact_mode = SimTypes.ShockContactMode.WITHDRAW
	artillery_static.fire_hold_distance_ratio = 0.98
	artillery_static.assault_distance_ratio = 0.9
	artillery_static.retarget_distance_ratio = 0.84
	artillery_static.disengage_suppression_threshold = 0.28
	artillery_static.disengage_casualty_rate_threshold = 0.04
	artillery_static.assault_confidence_threshold = 0.95
	artillery_static.withdraw_distance = 210.0
	artillery_static.recovery_duration = 2.8
	artillery_static.state_hold_duration = 1.4
	artillery_static.firefight_anchor_leash = 8.0
	doctrines[artillery_static.id] = artillery_static

