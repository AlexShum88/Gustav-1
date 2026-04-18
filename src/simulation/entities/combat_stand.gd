class_name CombatStand
extends RefCounted

const CombatTypes = preload("res://src/simulation/combat/combat_types.gd")
const DEFAULT_STAND_HEADCOUNT: int = 50

var id: StringName = &""
var display_name: String = ""
var company_type: int = SimTypes.CompanyType.MUSKETEERS
var stand_type: int:
	get:
		return company_type
	set(value):
		company_type = value
var category: int = SimTypes.UnitCategory.INFANTRY
var weapon_type: String = "musket"
var soldiers: int = DEFAULT_STAND_HEADCOUNT
var headcount: int:
	get:
		return soldiers
	set(value):
		soldiers = value
var training: float = 0.6
var combat_role: int = CombatTypes.CombatRole.MUSKET
var morale: float = 0.76
var cohesion: float = 0.76
var ammo: float = 1.0
var reload_state: int = CombatTypes.ReloadState.READY
var reload_progress: float = 0.0
var recover_duration: float = 0.35
var fire_cycle_duration: float = 1.0
var reload_duration: float = 4.0
var melee_reach: float = 1.0
var frontage_width: float = 24.0
var depth_density: float = 1.0
var suppression: float = 0.0
var brace_value: float = 0.1
var charge_bonus: float = 0.0
var charge_resistance: float = 0.5
var contact_side_mask: int = CombatTypes.ContactSide.NONE
var is_routed: bool = false
var local_position: Vector2 = Vector2.ZERO
var target_local_position: Vector2 = Vector2.ZERO
var front_direction: Vector2 = Vector2.RIGHT
var assigned_slot_id: StringName = &""
var home_segment: StringName = &"center"
var home_rank_index: int = 0
var current_target_stand_id: StringName = &""
var current_target_battalion_id: StringName = &""
var target_lock_until: float = -1.0
var fire_timer_until: float = -1.0
var melee_timer_until: float = -1.0
var collision_radius: float = 10.0
var slot_offset: Vector2 = Vector2.ZERO
var target_slot_offset: Vector2 = Vector2.ZERO
var slot_offset_retarget_time: float = 0.0
var slot_offset_retarget_index: int = 0
var visual_fire_until: float = -1.0
var current_visual_role: StringName = &""
var target_visual_role: StringName = &""
var visual_elements_local: Array = []
var target_visual_template_local: Array = []
var target_visual_slot_offset: Vector2 = Vector2.ZERO
var _world_visual_elements_cache: Array = []
var is_destroyed: bool = false
var editor_company_tag: StringName = &""
var editor_company_name: String = ""


func _init(
		company_id: StringName = &"",
		name_text: String = "",
		initial_company_type: int = SimTypes.CompanyType.MUSKETEERS,
		initial_category: int = SimTypes.UnitCategory.INFANTRY,
		initial_weapon_type: String = "musket",
		initial_soldiers: int = DEFAULT_STAND_HEADCOUNT,
		initial_training: float = 0.6
) -> void:
	id = company_id
	display_name = name_text
	company_type = initial_company_type
	category = initial_category
	weapon_type = initial_weapon_type
	soldiers = initial_soldiers
	training = initial_training
	initialize_combat_state()


func initialize_combat_state() -> void:
	_apply_combat_profile_defaults()
	morale = clamp(0.58 + training * 0.34, 0.0, 1.0)
	cohesion = clamp(0.52 + training * 0.38, 0.0, 1.0)
	ammo = 1.0
	reload_state = CombatTypes.ReloadState.READY
	reload_progress = 0.0
	suppression = 0.0
	contact_side_mask = CombatTypes.ContactSide.NONE
	is_routed = false
	is_destroyed = false


func refresh_combat_profile() -> void:
	_apply_combat_profile_defaults()


func _apply_combat_profile_defaults() -> void:
	combat_role = CombatTypes.resolve_combat_role(company_type, weapon_type)
	match combat_role:
		CombatTypes.CombatRole.PIKE:
			fire_cycle_duration = 0.0
			reload_duration = 0.0
			recover_duration = 0.0
			melee_reach = 1.8
			frontage_width = max(12.0, float(soldiers) * 0.18)
			depth_density = max(1.25, float(soldiers) / max(1.0, frontage_width * 4.0))
			collision_radius = max(6.5, frontage_width * 0.45)
			brace_value = 1.0
			charge_bonus = 0.0
			charge_resistance = 1.0
		CombatTypes.CombatRole.CAVALRY:
			fire_cycle_duration = 0.0
			reload_duration = 0.0
			recover_duration = 0.0
			melee_reach = 1.2
			frontage_width = max(14.0, float(soldiers) * 0.22)
			depth_density = max(0.95, float(soldiers) / max(1.0, frontage_width * 3.2))
			collision_radius = max(7.5, frontage_width * 0.48)
			brace_value = 0.15
			charge_bonus = 1.0
			charge_resistance = 0.6
		CombatTypes.CombatRole.ARTILLERY:
			fire_cycle_duration = 1.1
			reload_duration = 9.0
			recover_duration = 0.85
			melee_reach = 0.6
			frontage_width = max(18.0, float(soldiers) * 0.26)
			depth_density = max(0.7, float(soldiers) / max(1.0, frontage_width * 2.8))
			collision_radius = max(8.0, frontage_width * 0.42)
			brace_value = 0.0
			charge_bonus = 0.0
			charge_resistance = 0.15
		_:
			fire_cycle_duration = 1.15
			reload_duration = 4.8
			recover_duration = 0.45
			melee_reach = 1.0
			frontage_width = max(12.0, float(soldiers) * 0.2)
			depth_density = max(1.05, float(soldiers) / max(1.0, frontage_width * 4.0))
			collision_radius = max(6.5, frontage_width * 0.44)
			brace_value = 0.1
			charge_bonus = 0.0
			charge_resistance = 0.45


func get_max_range() -> float:
	match weapon_type:
		"cannon":
			return 900.0
		"carbine":
			return 135.0
		"pistol":
			return 70.0
		"pike":
			return 24.0
		_:
			return 165.0


func get_base_firepower() -> float:
	match weapon_type:
		"cannon":
			return 2.5
		"carbine":
			return 1.1
		"pistol":
			return 0.8
		"pike":
			return 0.72
		_:
			return 1.0


func get_effective_firepower() -> float:
	return soldiers * get_base_firepower() * lerpf(0.55, 1.25, clamp(training, 0.0, 1.0))


func tick_combat_state(delta: float) -> void:
	suppression = move_toward(suppression, 0.0, delta * 0.45)
	if fire_cycle_duration <= 0.0:
		reload_state = CombatTypes.ReloadState.READY
		reload_progress = 0.0
		return
	if reload_state == CombatTypes.ReloadState.READY:
		reload_progress = 0.0
		return
	reload_progress += delta
	match reload_state:
		CombatTypes.ReloadState.FIRING:
			if reload_progress >= fire_cycle_duration:
				reload_state = CombatTypes.ReloadState.RECOVERING
				reload_progress = 0.0
		CombatTypes.ReloadState.RECOVERING:
			if reload_progress >= recover_duration:
				reload_state = CombatTypes.ReloadState.RELOADING if reload_duration > 0.0 and ammo > 0.0 else CombatTypes.ReloadState.READY
				reload_progress = 0.0
		CombatTypes.ReloadState.RELOADING:
			if reload_progress >= reload_duration:
				reload_state = CombatTypes.ReloadState.READY
				reload_progress = 0.0


func can_fire_small_arms() -> bool:
	return combat_role == CombatTypes.CombatRole.MUSKET \
		and not is_routed \
		and ammo > 0.0 \
		and reload_state == CombatTypes.ReloadState.READY


func can_fire_artillery() -> bool:
	return combat_role == CombatTypes.CombatRole.ARTILLERY \
		and not is_routed \
		and ammo > 0.0 \
		and reload_state == CombatTypes.ReloadState.READY


func get_estimated_active_shooter_capacity(slot_role: StringName = &"") -> int:
	if combat_role != CombatTypes.CombatRole.MUSKET or soldiers <= 0:
		return 0
	var base_ratio: float = 0.18
	match slot_role:
		&"front_shot", &"fire_line", &"line":
			base_ratio = 0.36
		&"left_shot", &"right_shot":
			base_ratio = 0.32
		&"countermarch_shot":
			base_ratio = 0.18
		&"countermarch_front":
			base_ratio = 0.22
		&"countermarch_support":
			base_ratio = 0.04
		&"countermarch_rear":
			base_ratio = 0.0
		&"inner_shot", &"corner_shot":
			base_ratio = 0.18
		&"advance_guard", &"rear_guard", &"column", &"column_core":
			base_ratio = 0.02
	var effective_ratio: float = base_ratio \
		* clamp(0.45 + cohesion * 0.55, 0.0, 1.0) \
		* lerpf(0.7, 1.0, clamp(training, 0.0, 1.0))
	return int(clamp(int(round(float(soldiers) * effective_ratio)), 0, soldiers))


func get_estimated_active_melee_capacity(slot_role: StringName = &"") -> int:
	if soldiers <= 0:
		return 0
	var base_ratio: float = 0.18
	match combat_role:
		CombatTypes.CombatRole.PIKE:
			base_ratio = 0.28
		CombatTypes.CombatRole.CAVALRY:
			base_ratio = 0.24
		CombatTypes.CombatRole.ARTILLERY:
			base_ratio = 0.08
	if slot_role in [&"outer_pike", &"pike_core", &"tercia_pike", &"protected"]:
		base_ratio *= 1.16
	var effective_ratio: float = base_ratio * clamp(0.55 + cohesion * 0.45, 0.0, 1.0)
	return int(clamp(int(round(float(soldiers) * effective_ratio)), 0, soldiers))


func get_reload_ratio() -> float:
	if reload_duration <= 0.0:
		return 1.0
	if reload_state == CombatTypes.ReloadState.READY:
		return 1.0
	if reload_state == CombatTypes.ReloadState.RELOADING:
		return clamp(reload_progress / reload_duration, 0.0, 1.0)
	return 0.0


func update_slot_disorder(slot: FormationSlot, regiment_fatigue: float, delta: float) -> void:
	slot_offset_retarget_time -= delta
	var disorder_ratio: float = clamp(regiment_fatigue * 0.18 + (1.0 - clamp(training, 0.0, 1.0)) * 0.12, 0.0, 0.38)
	var max_offset: float = slot.tolerance_radius * disorder_ratio
	if max_offset <= 0.35:
		target_slot_offset = Vector2.ZERO
		slot_offset = slot_offset.move_toward(Vector2.ZERO, 18.0 * delta)
		slot_offset_retarget_time = max(slot_offset_retarget_time, 0.8)
		return
	if slot_offset_retarget_time <= 0.0:
		slot_offset_retarget_time = lerpf(1.6, 3.2, _stable_noise(slot_offset_retarget_index, 37))
		slot_offset_retarget_index += 1
		var lateral_axis: Vector2 = Vector2(-slot.facing_direction.y, slot.facing_direction.x)
		var longitudinal_axis: Vector2 = slot.facing_direction
		var lateral_limit: float = max_offset
		var longitudinal_limit: float = max_offset * 0.22
		if slot.role in [&"column", &"advance_guard", &"rear_guard", &"cavalry_column", &"battery_column", &"caracole_front", &"caracole_reforming"]:
			lateral_limit *= 0.35
			longitudinal_limit *= 0.15
		elif slot.role in [&"protected", &"outer_pike", &"inner_shot", &"fire_line", &"front_shot", &"rear_pike", &"left_shot", &"right_shot", &"pike_core", &"cavalry_line", &"battery_line", &"countermarch_shot", &"corner_shot", &"tercia_pike"]:
			lateral_limit *= 0.5
			longitudinal_limit *= 0.18
		var lateral_offset: float = lerpf(-lateral_limit, lateral_limit, _stable_noise(slot_offset_retarget_index, 53))
		var longitudinal_offset: float = lerpf(-longitudinal_limit, longitudinal_limit, _stable_noise(slot_offset_retarget_index, 71))
		target_slot_offset = lateral_axis * lateral_offset + longitudinal_axis * longitudinal_offset
	var correction_speed: float = lerpf(7.0, 18.0, clamp(training, 0.0, 1.0))
	slot_offset = slot_offset.move_toward(target_slot_offset, correction_speed * delta)


func trigger_visual_fire(current_time_seconds: float, duration_seconds: float = 0.35) -> void:
	visual_fire_until = max(visual_fire_until, current_time_seconds + max(duration_seconds, 0.05))


func is_visual_fire_active(current_time_seconds: float) -> bool:
	return visual_fire_until > current_time_seconds


func has_visual_state() -> bool:
	return not visual_elements_local.is_empty()


func initialize_visual_state(local_elements: Array, slot_role: StringName, slot_offset: Vector2 = Vector2.ZERO) -> void:
	current_visual_role = slot_role
	target_visual_role = slot_role
	target_visual_template_local = local_elements
	target_visual_slot_offset = slot_offset
	visual_elements_local = _duplicate_visual_elements_with_offset(local_elements, slot_offset)
	_sync_derived_anchor_from_sprite_bodies()
	target_local_position = local_position


func clear_visual_state() -> void:
	visual_elements_local.clear()
	target_visual_template_local.clear()
	_world_visual_elements_cache.clear()
	current_visual_role = &""
	target_visual_role = &""
	target_visual_slot_offset = Vector2.ZERO


func set_visual_targets(local_elements: Array, slot_role: StringName, slot_offset: Vector2 = Vector2.ZERO, force_refresh: bool = false) -> void:
	if not force_refresh \
			and target_visual_role == slot_role \
			and not target_visual_template_local.is_empty() \
			and target_visual_template_local.size() == local_elements.size() \
			and target_visual_slot_offset.distance_to(slot_offset) <= 0.35:
		target_visual_slot_offset = slot_offset
		return
	target_visual_role = slot_role
	target_visual_template_local = local_elements
	target_visual_slot_offset = slot_offset
	if visual_elements_local.size() != local_elements.size():
		visual_elements_local = _duplicate_visual_elements_with_offset(local_elements, slot_offset)
		current_visual_role = slot_role


func update_visual_state(delta: float, move_speed: float) -> void:
	if target_visual_template_local.is_empty():
		return
	if visual_elements_local.size() != target_visual_template_local.size():
		visual_elements_local = _duplicate_visual_elements_with_offset(target_visual_template_local, target_visual_slot_offset)
		current_visual_role = target_visual_role
	var current_center_total: Vector2 = Vector2.ZERO
	var target_center_total: Vector2 = Vector2.ZERO
	var front_total: Vector2 = Vector2.ZERO
	var target_count: int = target_visual_template_local.size()
	for element_index in range(target_count):
		var element: Dictionary = visual_elements_local[element_index]
		var target_element: Dictionary = target_visual_template_local[element_index]
		var current_position: Vector2 = element.get("position", Vector2.ZERO)
		var target_position: Vector2 = target_element.get("position", current_position) + target_visual_slot_offset
		var offset: Vector2 = target_position - current_position
		var offset_length_sq: float = offset.length_squared()
		if offset_length_sq > 0.001:
			var offset_length: float = sqrt(offset_length_sq)
			var step: float = min(offset_length, move_speed * delta)
			element["position"] = current_position + offset / offset_length * step
		else:
			element["position"] = target_position
		var target_front: Vector2 = target_element.get("front_direction", front_direction)
		var next_front: Vector2 = element.get("front_direction", front_direction).lerp(
			target_front,
			min(1.0, delta * 7.0)
		)
		element["front_direction"] = next_front.normalized() if next_front.length_squared() > 0.001 else target_front
		element["role"] = target_element.get("role", element.get("role", &""))
		visual_elements_local[element_index] = element
		current_center_total += element.get("position", target_position)
		target_center_total += target_position
		front_total += element.get("front_direction", front_direction)
	current_visual_role = target_visual_role
	local_position = current_center_total / float(max(1, target_count))
	target_local_position = target_center_total / float(max(1, target_count))
	if front_total.length_squared() > 0.001:
		front_direction = front_total.normalized()


func build_visual_elements_world(regiment_position: Vector2) -> Array:
	while _world_visual_elements_cache.size() > visual_elements_local.size():
		_world_visual_elements_cache.pop_back()
	while _world_visual_elements_cache.size() < visual_elements_local.size():
		_world_visual_elements_cache.append({})
	for element_index in range(visual_elements_local.size()):
		var element: Dictionary = visual_elements_local[element_index]
		var world_element: Dictionary = _world_visual_elements_cache[element_index]
		world_element["position"] = regiment_position + element.get("position", Vector2.ZERO)
		world_element["front_direction"] = element.get("front_direction", front_direction)
		world_element["role"] = element.get("role", &"")
		_world_visual_elements_cache[element_index] = world_element
	return _world_visual_elements_cache


func has_sprite_bodies() -> bool:
	return not visual_elements_local.is_empty()


func build_sprite_bodies_world(regiment_position: Vector2) -> Array:
	return build_visual_elements_world(regiment_position)


func get_sprite_body_centroid_local() -> Vector2:
	return get_visual_center_local()


func get_sprite_body_target_centroid_local() -> Vector2:
	return get_target_visual_center_local()


func get_sprite_body_front_direction() -> Vector2:
	return get_visual_dominant_front()


func get_visual_center_local() -> Vector2:
	if visual_elements_local.is_empty():
		return local_position
	var total: Vector2 = Vector2.ZERO
	for element_value in visual_elements_local:
		var element: Dictionary = element_value
		total += element.get("position", Vector2.ZERO)
	return total / float(visual_elements_local.size())


func get_target_visual_center_local() -> Vector2:
	if target_visual_template_local.is_empty():
		return target_local_position
	var total: Vector2 = Vector2.ZERO
	for element_value in target_visual_template_local:
		var element: Dictionary = element_value
		total += element.get("position", Vector2.ZERO) + target_visual_slot_offset
	return total / float(target_visual_template_local.size())


func get_visual_dominant_front() -> Vector2:
	var total: Vector2 = Vector2.ZERO
	for element_value in visual_elements_local:
		var element: Dictionary = element_value
		total += element.get("front_direction", Vector2.ZERO)
	return total.normalized() if total.length_squared() > 0.001 else front_direction


func _sync_derived_anchor_from_sprite_bodies() -> void:
	local_position = get_visual_center_local()
	target_local_position = local_position
	var dominant_front: Vector2 = get_visual_dominant_front()
	if dominant_front.length_squared() > 0.001:
		front_direction = dominant_front


func _duplicate_visual_elements(source: Array) -> Array:
	var result: Array = []
	for element_value in source:
		var element: Dictionary = element_value
		result.append(element.duplicate(true))
	return result


func _duplicate_visual_elements_with_offset(source: Array, additional_offset: Vector2) -> Array:
	var result: Array = []
	for element_value in source:
		var element: Dictionary = element_value
		var shifted_element: Dictionary = element.duplicate(true)
		shifted_element["position"] = element.get("position", Vector2.ZERO) + additional_offset
		result.append(shifted_element)
	return result


func _stable_noise(index: int, salt: int) -> float:
	var seed: int = salt * 131 + index * 977
	var id_text: String = String(id)
	for char_index in range(id_text.length()):
		seed = int((seed * 33 + id_text.unicode_at(char_index)) % 2147483647)
	var normalized: float = float(seed % 10000) / 9999.0
	return clamp(normalized, 0.0, 1.0)
