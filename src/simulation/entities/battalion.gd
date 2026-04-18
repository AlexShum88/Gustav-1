class_name Battalion
extends SimEntity

const RegimentCommandProfile = preload("res://src/simulation/entities/regiment_command_profile.gd")
const RegimentBannerProfile = preload("res://src/simulation/entities/regiment_banner_profile.gd")
const RegimentProfileLibrary = preload("res://src/simulation/core/regiment_profile_library.gd")
const CombatTypes = preload("res://src/simulation/combat/combat_types.gd")
const DETAILED_VISUAL_BLOCKS_IN_SIM: bool = false

var brigade_id: StringName = &""
var brigade_role: int = SimTypes.BrigadeRole.CENTER
var category: int = SimTypes.UnitCategory.INFANTRY
var _stands: Array = []
var stands: Array:
	get:
		return _stands
	set(value):
		_stands = value
		mark_target_layout_dirty()

# Compatibility bridge while the rest of the codebase is still being renamed.
var companies: Array:
	get:
		return _stands
	set(value):
		_stands = value
		mark_target_layout_dirty()
var formation_slots: Array = []
var formation: FormationModel = FormationModel.new()
var formation_state: int = SimTypes.RegimentFormationState.DEFAULT
var fire_behavior: int = SimTypes.RegimentFireBehavior.NONE
var current_order_id: StringName = &""
var current_order_type: int = SimTypes.OrderType.HOLD
var order_policies: Dictionary = {}
var current_target_position: Vector2 = Vector2.ZERO
var fatigue: float = 0.1
var morale: float = 0.78
var cohesion: float = 0.78
var combat_posture: int = CombatTypes.CombatPosture.IDLE
var combat_order_mode: int = CombatTypes.CombatOrderMode.NONE
var combat_lock_until: float = -1.0
var brace_until: float = -1.0
var charge_recovery_until: float = -1.0
var charge_retreat_until: float = -1.0
var charge_retreat_target_position: Vector2 = Vector2.ZERO
var charge_stage_position: Vector2 = Vector2.ZERO
var charge_stage_valid: bool = false
var charge_target_company_id: StringName = &""
var last_combat_tick_seen_enemy: float = -1.0
var last_visible_enemy_distance: float = INF
var suppression: float = 0.0
var ammo_ratio: float = 1.0
var commander_quality: float = 0.7
var behavior_doctrine_id: StringName = &"default"
var engagement_state: int = SimTypes.EngagementState.NO_CONTACT
var engagement_target_regiment_id: StringName = &""
var engagement_state_since: float = -1.0
var engagement_hold_until: float = -1.0
var engagement_anchor_position: Vector2 = Vector2.ZERO
var recent_incoming_pressure: float = 0.0
var recent_casualty_rate: float = 0.0
var recent_effective_losses: float = 0.0
var target_switch_cooldown_until: float = -1.0
var last_strength_sample: int = -1
var last_suppression_sample: float = 0.0
var state_label: String = "Holding"
var base_speed: float = 46.0
var initial_strength: int = 1
var base_commander_quality: float = 0.7
var company_reform_speed: float = 90.0
var banner_reform_speed: float = 110.0
var base_company_reform_speed: float = 90.0
var base_banner_reform_speed: float = 110.0
var front_direction: Vector2 = Vector2.RIGHT
var banner_element: RegimentalElement
var commander_name: String = ""
var commander_profile_id: StringName = &""
var commander_profile_name: String = ""
var max_company_capacity: int = 4
var banner_profile_id: StringName = &"standard_colors"
var banner_profile_name: String = "Standard Colors"
var debug_forced_formation_state: int = -1
var debug_forced_fire_behavior: int = -1
var debug_test_fire_until: float = -1.0
var formation_cycle_index: int = 0
var formation_cycle_elapsed: float = 0.0
var formation_cycle_phase: int = 0
var desired_formation_type: int = SimTypes.FormationType.LINE
var desired_formation_state: int = SimTypes.RegimentFormationState.DEFAULT
var formation_reform_until: float = -1.0
var formation_change_started_at: float = -1.0
var formation_change_cooldown_until: float = -1.0
var _target_layout_cache_dirty: bool = true
var _cached_target_layout_key: String = ""
var _cached_target_layout_local: Array = []
var _cached_target_slot_specs: Array = []


func get_total_strength() -> int:
	var total: int = 0
	for company_value in companies:
		var company: CombatStand = company_value
		total += company.soldiers
	return total


func get_strength_ratio() -> float:
	return float(get_total_strength()) / float(max(1, initial_strength))


func get_attack_range() -> float:
	var result: float = 24.0
	for company_value in companies:
		var company: CombatStand = company_value
		result = max(result, company.get_max_range())
	return result


func get_weapon_strength_ratio(weapon_type: String) -> float:
	var matching_soldiers: int = 0
	var total_soldiers: int = 0
	for company_value in companies:
		var company: CombatStand = company_value
		total_soldiers += company.soldiers
		if company.weapon_type == weapon_type:
			matching_soldiers += company.soldiers
	return float(matching_soldiers) / float(max(1, total_soldiers))


func get_firearm_strength_ratio() -> float:
	var matching_soldiers: int = 0
	var total_soldiers: int = 0
	for company_value in companies:
		var company: CombatStand = company_value
		total_soldiers += company.soldiers
		if company.weapon_type in ["musket", "carbine", "pistol", "cannon"]:
			matching_soldiers += company.soldiers
	return float(matching_soldiers) / float(max(1, total_soldiers))


func has_significant_firearm_capability() -> bool:
	if category == SimTypes.UnitCategory.ARTILLERY:
		return true
	if category == SimTypes.UnitCategory.CAVALRY:
		return get_firearm_strength_ratio() >= 0.38
	return get_firearm_strength_ratio() >= 0.25


func can_commit_assault() -> bool:
	return category != SimTypes.UnitCategory.ARTILLERY and get_total_strength() > 0


func is_engagement_state_active() -> bool:
	return engagement_state in [
		SimTypes.EngagementState.DEPLOY_FIRE,
		SimTypes.EngagementState.FIREFIGHT,
		SimTypes.EngagementState.ASSAULT,
		SimTypes.EngagementState.DISENGAGE,
		SimTypes.EngagementState.RECOVER,
	]


func is_firefight_engaged() -> bool:
	return engagement_state in [
		SimTypes.EngagementState.DEPLOY_FIRE,
		SimTypes.EngagementState.FIREFIGHT,
	]


func get_preferred_attack_formation() -> int:
	match category:
		SimTypes.UnitCategory.ARTILLERY:
			return SimTypes.FormationType.LINE
		SimTypes.UnitCategory.CAVALRY:
			var pistol_ratio: float = get_weapon_strength_ratio("pistol")
			return SimTypes.FormationType.LINE if pistol_ratio >= 0.45 else SimTypes.FormationType.COLUMN
		_:
			var musket_ratio: float = get_weapon_strength_ratio("musket")
			var pike_ratio: float = get_weapon_strength_ratio("pike")
			if pike_ratio > musket_ratio:
				return SimTypes.FormationType.COLUMN
			return SimTypes.FormationType.LINE


func get_preferred_fire_behavior() -> int:
	if formation_state == SimTypes.RegimentFormationState.PROTECTED or formation.formation_type == SimTypes.FormationType.SQUARE:
		return SimTypes.RegimentFireBehavior.VOLLEY
	match category:
		SimTypes.UnitCategory.ARTILLERY:
			return SimTypes.RegimentFireBehavior.VOLLEY
		SimTypes.UnitCategory.CAVALRY:
			return SimTypes.RegimentFireBehavior.CARACOLE if formation.formation_type == SimTypes.FormationType.COLUMN else SimTypes.RegimentFireBehavior.VOLLEY
		_:
			if has_pike_and_shot_companies():
				return SimTypes.RegimentFireBehavior.COUNTERMARCH
			return SimTypes.RegimentFireBehavior.VOLLEY


func get_charge_windup_distance() -> float:
	var base_distance: float = 190.0 if formation.formation_type == SimTypes.FormationType.LINE else 225.0
	return base_distance * lerpf(0.9, 1.08, clamp(commander_quality, 0.0, 1.0))


func get_charge_windup_min_distance() -> float:
	return 58.0


func get_tactical_contact_distance(nearby_enemy: Battalion = null) -> float:
	var base_distance: float = 92.0
	match category:
		SimTypes.UnitCategory.CAVALRY:
			base_distance = 118.0
		SimTypes.UnitCategory.ARTILLERY:
			base_distance = 140.0
	base_distance = max(base_distance, min(get_attack_range() * 0.58, 176.0))
	if nearby_enemy != null:
		var own_span: float = min(max(formation.frontage, formation.depth), 120.0)
		var enemy_span: float = min(max(nearby_enemy.formation.frontage, nearby_enemy.formation.depth), 120.0)
		base_distance += (own_span + enemy_span) * 0.16
	return clamp(base_distance, 72.0, 196.0)


func get_close_engagement_distance(nearby_enemy: Battalion = null) -> float:
	var base_distance: float = 60.0
	if category == SimTypes.UnitCategory.CAVALRY:
		base_distance = 78.0
	elif category == SimTypes.UnitCategory.ARTILLERY:
		base_distance = 88.0
	if nearby_enemy != null:
		base_distance += min(max(nearby_enemy.formation.frontage, nearby_enemy.formation.depth), 96.0) * 0.10
	return clamp(base_distance, 52.0, 126.0)


func can_use_structured_fire_behavior(current_time_seconds: float) -> bool:
	if current_order_type == SimTypes.OrderType.MARCH \
			and not engagement_state in [
				SimTypes.EngagementState.DEPLOY_FIRE,
				SimTypes.EngagementState.FIREFIGHT,
			]:
		return false
	if formation_state == SimTypes.RegimentFormationState.PROTECTED or formation.formation_type == SimTypes.FormationType.SQUARE:
		return has_significant_firearm_capability() and not is_reforming(current_time_seconds)
	if formation_state == SimTypes.RegimentFormationState.MARCH_COLUMN or formation.formation_type == SimTypes.FormationType.COLUMN:
		return false
	if is_reforming(current_time_seconds):
		return false
	return true


func mark_target_layout_dirty() -> void:
	_target_layout_cache_dirty = true


func prepare_charge_run() -> void:
	if charge_stage_valid:
		return
	charge_stage_position = position
	charge_stage_valid = true


func clear_charge_run() -> void:
	charge_stage_valid = false


func is_charge_retreating(current_time_seconds: float) -> bool:
	return current_time_seconds < charge_retreat_until \
		and charge_retreat_target_position.distance_to(position) > 10.0


func is_charge_recovering(current_time_seconds: float) -> bool:
	return current_time_seconds < charge_recovery_until


func is_reforming(current_time_seconds: float) -> bool:
	return current_time_seconds < formation_reform_until


func get_reform_exposure(current_time_seconds: float) -> float:
	if not is_reforming(current_time_seconds):
		return 0.0
	var reform_duration: float = max(0.1, formation_reform_until - formation_change_started_at)
	var reform_elapsed: float = clamp(current_time_seconds - formation_change_started_at, 0.0, reform_duration)
	var progress: float = reform_elapsed / reform_duration
	return clamp(1.0 - progress * 0.65, 0.3, 1.0)


func get_reform_move_multiplier(current_time_seconds: float) -> float:
	if is_reforming(current_time_seconds):
		return 0.64
	return 1.0


func get_effective_company_reform_speed(current_time_seconds: float) -> float:
	var exposure: float = get_reform_exposure(current_time_seconds)
	return company_reform_speed * lerpf(1.0, 0.34, exposure)


func get_effective_banner_reform_speed(current_time_seconds: float) -> float:
	var exposure: float = get_reform_exposure(current_time_seconds)
	return banner_reform_speed * lerpf(1.0, 0.4, exposure)


func request_formation_change(new_type: int, new_state: int, current_time_seconds: float, urgent: bool = false) -> bool:
	var resolved_type: int = new_type
	var resolved_state: int = new_state
	if resolved_state == SimTypes.RegimentFormationState.PROTECTED or resolved_type == SimTypes.FormationType.SQUARE:
		resolved_type = SimTypes.FormationType.SQUARE
		resolved_state = SimTypes.RegimentFormationState.PROTECTED
	elif resolved_state == SimTypes.RegimentFormationState.MARCH_COLUMN or resolved_type == SimTypes.FormationType.COLUMN:
		resolved_type = SimTypes.FormationType.COLUMN
		if resolved_state == SimTypes.RegimentFormationState.DEFAULT:
			resolved_state = SimTypes.RegimentFormationState.MARCH_COLUMN
	elif resolved_type == SimTypes.FormationType.LINE and resolved_state == SimTypes.RegimentFormationState.MARCH_COLUMN:
		resolved_state = SimTypes.RegimentFormationState.DEFAULT

	if desired_formation_type == resolved_type and desired_formation_state == resolved_state:
		if is_reforming(current_time_seconds) or (not urgent and current_time_seconds < formation_change_cooldown_until):
			return false
	desired_formation_type = resolved_type
	desired_formation_state = resolved_state
	if formation.formation_type == resolved_type and formation_state == resolved_state and not is_reforming(current_time_seconds):
		return false
	if not urgent and current_time_seconds < formation_change_cooldown_until:
		return false
	if not urgent and is_reforming(current_time_seconds):
		return false
	if is_reforming(current_time_seconds) \
			and formation.formation_type == resolved_type \
			and formation_state == resolved_state:
		return false

	var reform_duration: float = _estimate_formation_reform_duration(resolved_type, resolved_state)
	formation.set_type(resolved_type)
	formation_state = resolved_state
	formation_change_started_at = current_time_seconds
	formation_reform_until = current_time_seconds + reform_duration
	formation_change_cooldown_until = current_time_seconds + max(4.2, reform_duration * 1.35)
	mark_target_layout_dirty()
	return true


func _estimate_formation_reform_duration(new_type: int, new_state: int) -> float:
	var duration: float = 3.1
	if formation.formation_type != new_type:
		duration += 1.25
	if formation_state != new_state:
		duration += 0.75
	if new_type == SimTypes.FormationType.SQUARE or formation.formation_type == SimTypes.FormationType.SQUARE:
		duration += 1.45
	elif new_type == SimTypes.FormationType.COLUMN or formation.formation_type == SimTypes.FormationType.COLUMN:
		duration += 0.8
	if category == SimTypes.UnitCategory.ARTILLERY:
		duration += 0.5
	elif category == SimTypes.UnitCategory.CAVALRY:
		duration += 0.3
	return duration / lerpf(0.84, 1.16, clamp(commander_quality, 0.0, 1.0))


func get_company_count() -> int:
	return companies.size()


func get_stand_count() -> int:
	return stands.size()


func get_editor_company_count() -> int:
	var unique_tags: Dictionary = {}
	for stand_value in stands:
		var stand: CombatStand = stand_value
		var tag: StringName = stand.editor_company_tag
		if tag == &"":
			tag = StringName("%s_fallback_%s" % [String(id), String(stand.id)])
		unique_tags[tag] = true
	return unique_tags.size()


func get_company_ids() -> Array:
	var result: Array = []
	for company_value in companies:
		var company: CombatStand = company_value
		result.append(String(company.id))
	return result


func get_stand_ids() -> Array:
	return get_company_ids()


func get_company_world_position(company: CombatStand) -> Vector2:
	if DETAILED_VISUAL_BLOCKS_IN_SIM and company != null and company.has_sprite_bodies():
		return position + company.get_sprite_body_centroid_local()
	return position + company.local_position


func get_stand_world_position(stand: CombatStand) -> Vector2:
	return get_company_world_position(stand)


func get_company_world_front_direction(company: CombatStand) -> Vector2:
	if DETAILED_VISUAL_BLOCKS_IN_SIM and company != null and company.has_sprite_bodies():
		var sprite_front: Vector2 = company.get_sprite_body_front_direction()
		if sprite_front.length_squared() > 0.001:
			return sprite_front
	return company.front_direction if company != null else front_direction


func get_stand_world_front_direction(stand: CombatStand) -> Vector2:
	return get_company_world_front_direction(stand)


func get_company_sprite_bodies_world(company: CombatStand) -> Array:
	if company == null:
		return []
	if DETAILED_VISUAL_BLOCKS_IN_SIM and company.has_sprite_bodies():
		return company.build_sprite_bodies_world(position)
	return _build_company_visual_element_positions(company)


func get_stand_sprite_bodies_world(stand: CombatStand) -> Array:
	return get_company_sprite_bodies_world(stand)


func get_company_world_positions() -> Array:
	var result: Array = []
	for company_value in companies:
		var company: CombatStand = company_value
		result.append(get_company_world_position(company))
	return result


func get_company_slot_role(company_id: StringName) -> StringName:
	for company_index in range(companies.size()):
		var company: CombatStand = companies[company_index]
		if company.id != company_id:
			continue
		if company.current_visual_role != &"":
			return company.current_visual_role
		if company_index < formation_slots.size():
			return formation_slots[company_index].role
		break
	return &""


func get_stand_slot_role(stand_id: StringName) -> StringName:
	return get_company_slot_role(stand_id)


func ensure_banner_element() -> void:
	if banner_element != null:
		return
	banner_element = RegimentalElement.new(StringName("%s_banner" % String(id)), "%s Banner" % display_name, SimTypes.RegimentalElementType.BANNER)
	banner_element.placeholder_key = RegimentProfileLibrary.get_default_banner_profile(category).placeholder_key
	banner_element.front_direction = front_direction


func apply_command_profile(profile: RegimentCommandProfile) -> void:
	commander_profile_id = profile.id
	commander_profile_name = profile.display_name
	max_company_capacity = max(1, profile.max_companies)
	company_reform_speed = base_company_reform_speed * profile.reform_speed_multiplier
	banner_reform_speed = base_banner_reform_speed * profile.banner_reform_speed_multiplier
	commander_quality = clamp(base_commander_quality + profile.command_quality_bonus, 0.0, 1.0)


func apply_banner_profile(profile: RegimentBannerProfile) -> void:
	banner_profile_id = profile.id
	banner_profile_name = profile.display_name
	ensure_banner_element()
	banner_element.display_name = "%s (%s)" % [display_name, profile.display_name]
	banner_element.placeholder_key = profile.placeholder_key


func set_commander_identity(name_text: String, profile_id: StringName = &"") -> void:
	commander_name = name_text
	var profile: RegimentCommandProfile = RegimentProfileLibrary.get_command_profile(
		profile_id if profile_id != &"" else RegimentProfileLibrary.get_default_command_profile(category).id,
		category
	)
	apply_command_profile(profile)


func set_banner_identity(profile_id: StringName = &"standard_colors") -> void:
	apply_banner_profile(RegimentProfileLibrary.get_banner_profile(profile_id))


func get_max_company_capacity() -> int:
	return max_company_capacity


func can_add_company() -> bool:
	return companies.size() < max_company_capacity


func can_add_stand() -> bool:
	return can_add_company()


func try_add_company(company: CombatStand) -> bool:
	if company == null or not can_add_company():
		return false
	companies.append(company)
	rebuild_after_company_change(false)
	return true


func try_add_stand(stand: CombatStand) -> bool:
	return try_add_company(stand)


func remove_company_by_id(company_id: StringName) -> bool:
	for company_index in range(companies.size()):
		var company: CombatStand = companies[company_index]
		if company.id != company_id:
			continue
		return _remove_company_at_index(company_index)
	return false


func remove_stand_by_id(stand_id: StringName) -> bool:
	return remove_company_by_id(stand_id)


func _remove_company_at_index(company_index: int) -> bool:
	if company_index < 0 or company_index >= companies.size():
		return false
	companies.remove_at(company_index)
	rebuild_after_company_change(false)
	return true


func rebuild_after_company_change(reset_initial_strength: bool = false) -> void:
	formation_cycle_index = 0
	formation_cycle_elapsed = 0.0
	formation_cycle_phase = 0
	mark_target_layout_dirty()
	initialize_company_positions()
	refresh_combat_aggregates()
	if reset_initial_strength:
		initial_strength = get_total_strength()


func create_company(
		company_type: int,
		weapon_type: String,
		soldier_count: int,
		name_text: String = "",
		training_value: float = -1.0
) -> CombatStand:
	var company_index: int = 1
	var existing_ids: Dictionary = {}
	for company_value in companies:
		var existing_company: CombatStand = company_value
		existing_ids[existing_company.id] = true
	while existing_ids.has(StringName("%s_company_%02d" % [String(id), company_index])):
		company_index += 1
	var resolved_training: float = training_value if training_value >= 0.0 else base_commander_quality
	var resolved_name: String = name_text
	if resolved_name.is_empty():
		resolved_name = "%s Company %d" % [SimTypes.company_type_name(company_type), company_index]
	return CombatStand.new(
		StringName("%s_company_%02d" % [String(id), company_index]),
		resolved_name,
		company_type,
		category,
		weapon_type,
		soldier_count,
		resolved_training
	)


func create_stand(
		stand_type: int,
		weapon_type: String,
		soldier_count: int,
		name_text: String = "",
		training_value: float = -1.0
) -> CombatStand:
	return create_company(stand_type, weapon_type, soldier_count, name_text, training_value)


func initialize_company_positions() -> void:
	ensure_banner_element()
	desired_formation_type = formation.formation_type
	desired_formation_state = formation_state
	mark_target_layout_dirty()
	var target_visual_layout: Array = []
	if DETAILED_VISUAL_BLOCKS_IN_SIM:
		target_visual_layout = _build_target_company_visual_layout()
		_rebuild_formation_slots_from_visual_entries(target_visual_layout)
	else:
		_cached_target_slot_specs = _build_company_slot_specs()
		_apply_cached_target_slot_specs()
		target_visual_layout = _build_visual_layout_from_slot_specs(_cached_target_slot_specs)
	for company_index in range(companies.size()):
		var company: CombatStand = companies[company_index]
		var slot: FormationSlot = formation_slots[company_index]
		company.assigned_slot_id = slot.id
		company.slot_offset = Vector2.ZERO
		company.target_slot_offset = Vector2.ZERO
		company.slot_offset_retarget_time = 0.0
		company.local_position = slot.local_position
		company.target_local_position = slot.local_position
		company.front_direction = slot.facing_direction
		company.current_visual_role = _resolve_runtime_visual_role(company, slot.role)
		company.target_visual_role = company.current_visual_role
	if DETAILED_VISUAL_BLOCKS_IN_SIM:
		_initialize_company_visual_states(target_visual_layout)
	else:
		for company_value in companies:
			var stand: CombatStand = company_value
			stand.clear_visual_state()
	var banner_slot: FormationSlot = _build_banner_slot()
	banner_element.assigned_slot_id = banner_slot.id
	banner_element.local_position = banner_slot.local_position
	banner_element.target_local_position = banner_slot.local_position
	banner_element.front_direction = banner_slot.facing_direction


func initialize_subunit_positions() -> void:
	initialize_company_positions()


func update_subunit_blocks(delta: float, current_time_seconds: float = -1.0) -> void:
	if companies.is_empty():
		return
	_update_formation_cycle(delta)
	_sync_front_direction_from_facing()
	var layout_refreshed: bool = _refresh_target_layout_cache_if_needed()
	if layout_refreshed or formation_slots.size() != _cached_target_slot_specs.size():
		_apply_cached_target_slot_specs()
	var effective_reform_speed: float = company_reform_speed
	if current_time_seconds >= 0.0:
		effective_reform_speed = get_effective_company_reform_speed(current_time_seconds)
	for company_index in range(companies.size()):
		var company: CombatStand = companies[company_index]
		var slot: FormationSlot = formation_slots[company_index]
		company.assigned_slot_id = slot.id
		company.update_slot_disorder(slot, fatigue, delta)
		var target_entry: Dictionary = _cached_target_layout_local[company_index] if company_index < _cached_target_layout_local.size() else {}
		var slot_role: StringName = slot.role
		if not target_entry.is_empty():
			slot_role = StringName(target_entry.get("slot_role", String(slot.role)))
			if DETAILED_VISUAL_BLOCKS_IN_SIM:
				if company.has_visual_state():
					company.set_visual_targets(
						target_entry.get("elements", []),
						slot_role,
						company.slot_offset,
						layout_refreshed
					)
				else:
					company.initialize_visual_state(
						target_entry.get("elements", []),
						slot_role,
						company.slot_offset
					)
		if DETAILED_VISUAL_BLOCKS_IN_SIM:
			company.update_visual_state(delta, effective_reform_speed)
		else:
			if company.has_visual_state():
				company.clear_visual_state()
			var runtime_visual_role: StringName = _resolve_runtime_visual_role(company, slot_role)
			company.current_visual_role = runtime_visual_role
			company.target_visual_role = runtime_visual_role
			var target_local_position: Vector2 = slot.local_position + company.slot_offset
			company.target_local_position = target_local_position
			var offset: Vector2 = target_local_position - company.local_position
			if offset.length_squared() > 0.001:
				var offset_length: float = offset.length()
				var step: float = min(offset_length, effective_reform_speed * delta)
				company.local_position += offset / offset_length * step
			else:
				company.local_position = target_local_position
			var target_front: Vector2 = slot.facing_direction
			if target_front.length_squared() <= 0.001:
				target_front = front_direction
			var next_front: Vector2 = company.front_direction.lerp(target_front, min(1.0, delta * 7.0))
			company.front_direction = next_front.normalized() if next_front.length_squared() > 0.001 else target_front
	var banner_slot: FormationSlot = _build_banner_slot()
	banner_element.assigned_slot_id = banner_slot.id
	banner_element.target_local_position = banner_slot.local_position
	banner_element.front_direction = banner_element.front_direction.lerp(banner_slot.facing_direction, min(1.0, delta * 7.0)).normalized()
	var banner_offset: Vector2 = banner_element.target_local_position - banner_element.local_position
	var effective_banner_speed: float = banner_reform_speed
	if current_time_seconds >= 0.0:
		effective_banner_speed = get_effective_banner_reform_speed(current_time_seconds)
	var banner_step: float = min(banner_offset.length(), effective_banner_speed * delta)
	if banner_offset.length() > 0.001:
		banner_element.local_position += banner_offset.normalized() * banner_step


func build_subunit_polygons() -> Array:
	return build_company_polygons()


func build_regiment_polygon() -> PackedVector2Array:
	return build_regiment_polygon_from_visual_entries(build_company_visual_layout())


func build_company_polygons() -> Array:
	return build_company_polygons_from_visual_entries(build_company_visual_layout())


func build_company_polygons_from_visual_entries(visual_entries: Array) -> Array:
	var polygons: Array = []
	for company_visual_value in visual_entries:
		var company_visual: Dictionary = company_visual_value
		polygons.append(_build_company_polygon_from_visual_elements(company_visual.get("elements", [])))
	return polygons


func build_regiment_polygon_from_visual_entries(visual_entries: Array) -> PackedVector2Array:
	var points: Array = []
	for company_visual_value in visual_entries:
		var company_visual: Dictionary = company_visual_value
		for element_value in company_visual.get("elements", []):
			var element: Dictionary = element_value
			points.append(element.get("position", Vector2.ZERO))
	if points.is_empty():
		return formation.build_polygon(position)
	return _build_bounding_polygon_from_points(points, Vector2(22.0, 20.0))


func get_company_weapon_types() -> Array:
	var result: Array = []
	for company_value in companies:
		var company: CombatStand = company_value
		result.append(company.weapon_type)
	return result


func get_stand_weapon_types() -> Array:
	return get_company_weapon_types()


func get_company_type_ids() -> Array:
	var result: Array = []
	for company_value in companies:
		var company: CombatStand = company_value
		result.append(company.company_type)
	return result


func get_stand_type_ids() -> Array:
	return get_company_type_ids()


func get_editor_company_type_ids() -> Array:
	var result: Array = []
	var seen_tags: Dictionary = {}
	for stand_value in stands:
		var stand: CombatStand = stand_value
		var tag: StringName = stand.editor_company_tag
		if tag == &"":
			tag = StringName("%s_fallback_%s" % [String(id), String(stand.id)])
		if seen_tags.has(tag):
			continue
		seen_tags[tag] = true
		result.append(stand.company_type)
	return result


func has_pike_and_shot_companies() -> bool:
	return category == SimTypes.UnitCategory.INFANTRY \
		and _has_company_type(SimTypes.CompanyType.PIKEMEN) \
		and _has_company_type(SimTypes.CompanyType.MUSKETEERS)


func build_company_visual_layout() -> Array:
	var result: Array = []
	for company_value in companies:
		var company: CombatStand = company_value
		var slot_role: StringName = get_company_slot_role(company.id)
		result.append({
			"company_id": String(company.id),
			"company_type": company.company_type,
			"weapon_type": company.weapon_type,
			"slot_role": String(slot_role),
			"elements": _build_company_visual_element_positions(company),
		})
	return result


func build_company_visual_elements() -> Array:
	return build_company_visual_layout()


func _should_use_grouped_runtime_layout() -> bool:
	return false


func _build_runtime_pattern_visual_layout() -> Array:
	if _should_use_grouped_runtime_layout():
		return _build_visual_layout_from_slot_specs(_build_editor_company_derived_slot_specs())
	if category == SimTypes.UnitCategory.INFANTRY \
			and (_has_company_type(SimTypes.CompanyType.PIKEMEN) or _has_company_type(SimTypes.CompanyType.MUSKETEERS)):
		return _order_visual_entries_by_company(_build_infantry_regiment_visual_layout())
	if category == SimTypes.UnitCategory.CAVALRY:
		return _order_visual_entries_by_company(_build_cavalry_regiment_visual_layout())
	if category == SimTypes.UnitCategory.ARTILLERY:
		return _order_visual_entries_by_company(_build_artillery_regiment_visual_layout())
	return []


func _build_target_company_visual_layout() -> Array:
	if not DETAILED_VISUAL_BLOCKS_IN_SIM:
		var pattern_layout: Array = _build_runtime_pattern_visual_layout()
		if not pattern_layout.is_empty():
			return pattern_layout
		return _build_visual_layout_from_slot_specs(_build_company_slot_specs())
	if category == SimTypes.UnitCategory.INFANTRY \
			and (_has_company_type(SimTypes.CompanyType.PIKEMEN) or _has_company_type(SimTypes.CompanyType.MUSKETEERS)):
		return _order_visual_entries_by_company(_build_infantry_regiment_visual_layout())
	if category == SimTypes.UnitCategory.CAVALRY:
		return _order_visual_entries_by_company(_build_cavalry_regiment_visual_layout())
	if category == SimTypes.UnitCategory.ARTILLERY:
		return _order_visual_entries_by_company(_build_artillery_regiment_visual_layout())
	var result: Array = []
	for company_index in range(companies.size()):
		var company: CombatStand = companies[company_index]
		var slot: FormationSlot = formation_slots[company_index] if company_index < formation_slots.size() else null
		result.append({
			"company_id": String(company.id),
			"company_type": company.company_type,
			"weapon_type": company.weapon_type,
			"slot_role": String(slot.role) if slot != null else "",
			"elements": _build_company_visual_element_positions(company, slot),
		})
	return result


func _refresh_target_layout_cache_if_needed() -> bool:
	var cache_key: String = _build_target_layout_cache_key()
	var should_force_refresh: bool = is_caracole_active()
	if not should_force_refresh \
			and not _target_layout_cache_dirty \
			and cache_key == _cached_target_layout_key \
			and not _cached_target_layout_local.is_empty():
		return false

	if not DETAILED_VISUAL_BLOCKS_IN_SIM:
		_cached_target_slot_specs = _build_company_slot_specs()
		_cached_target_layout_local.clear()
		for company_index in range(companies.size()):
			var company: CombatStand = companies[company_index]
			var slot_spec: Dictionary = _cached_target_slot_specs[company_index] if company_index < _cached_target_slot_specs.size() else {}
			_cached_target_layout_local.append({
				"company_id": String(company.id),
				"company_type": company.company_type,
				"weapon_type": company.weapon_type,
				"slot_role": String(slot_spec.get("role", _get_slot_role(company_index, companies.size()))),
				"elements": [],
			})
		_cached_target_layout_key = cache_key
		_target_layout_cache_dirty = false
		return true

	var world_layout: Array = _build_target_company_visual_layout()
	_cached_target_layout_local.clear()
	for entry_value in world_layout:
		var entry: Dictionary = entry_value
		var cached_entry: Dictionary = {
			"company_id": entry.get("company_id", ""),
			"company_type": entry.get("company_type", SimTypes.CompanyType.MUSKETEERS),
			"weapon_type": entry.get("weapon_type", ""),
			"slot_role": entry.get("slot_role", ""),
			"elements": [],
		}
		cached_entry["elements"] = _visual_elements_world_to_local(entry.get("elements", []))
		_cached_target_layout_local.append(cached_entry)
	_cached_target_slot_specs = _build_slot_specs_from_visual_entries(world_layout)
	_cached_target_layout_key = cache_key
	_target_layout_cache_dirty = false
	return true


func _build_target_layout_cache_key() -> String:
	var angle_step: float = 0.18
	if DETAILED_VISUAL_BLOCKS_IN_SIM:
		if is_countermarch_active() or is_caracole_active():
			angle_step = 0.08
		elif formation_state == SimTypes.RegimentFormationState.PROTECTED or formation.formation_type == SimTypes.FormationType.SQUARE:
			angle_step = 0.12
	elif is_caracole_active():
		angle_step = 0.08
	elif formation_state == SimTypes.RegimentFormationState.PROTECTED or formation.formation_type == SimTypes.FormationType.SQUARE:
		angle_step = 0.12
	var angle_bucket: float = snapped(formation.orientation, angle_step)
	var cycle_key: String = "0:0"
	if is_caracole_active():
		cycle_key = "%d:%d" % [formation_cycle_index, formation_cycle_phase]
	elif DETAILED_VISUAL_BLOCKS_IN_SIM and is_countermarch_active():
		cycle_key = "%d:%d" % [formation_cycle_index, formation_cycle_phase]
	var company_key: Array = []
	for company_value in companies:
		var company: CombatStand = company_value
		company_key.append("%s:%s" % [str(company.company_type), company.weapon_type])
	var base_key: String = "%s|%s|%s|%.2f|%s|%s" % [
		str(category),
		str(formation.formation_type),
		str(formation_state),
		angle_bucket,
		str(fire_behavior),
		";".join(company_key),
	]
	return "%s|%s" % [base_key, cycle_key]


func _apply_cached_target_slot_specs() -> void:
	_sync_formation_metrics_from_slot_specs(_cached_target_slot_specs)
	formation_slots.clear()
	for company_index in range(_cached_target_slot_specs.size()):
		var slot_spec: Dictionary = _cached_target_slot_specs[company_index]
		var slot_position: Vector2 = slot_spec.get("position", Vector2.ZERO)
		var role_name: StringName = slot_spec.get("role", _get_slot_role(company_index, companies.size()))
		var slot_facing: Vector2 = slot_spec.get("facing", front_direction)
		var slot_tolerance: float = float(slot_spec.get("tolerance", max(14.0, min(formation.frontage, formation.depth) * 0.18)))
		formation_slots.append(FormationSlot.new(
			StringName("%s_slot_%02d" % [String(id), company_index]),
			slot_position,
			slot_facing,
			role_name,
			slot_tolerance
		))
		if company_index < companies.size():
			var company: CombatStand = companies[company_index]
			company.assigned_slot_id = formation_slots[company_index].id


func _offset_local_visual_elements(source_elements: Array, additional_offset: Vector2 = Vector2.ZERO) -> Array:
	var result: Array = []
	for element_value in source_elements:
		var element: Dictionary = element_value
		var shifted_element: Dictionary = element.duplicate(true)
		shifted_element["position"] = element.get("position", Vector2.ZERO) + additional_offset
		result.append(shifted_element)
	return result


func get_banner_snapshot() -> Dictionary:
	ensure_banner_element()
	return {
		"id": String(banner_element.id),
		"display_name": banner_element.display_name,
		"element_type": banner_element.element_type,
		"placeholder_key": String(banner_element.placeholder_key),
		"position": position + banner_element.local_position,
		"front_direction": banner_element.front_direction,
	}


func get_vision_range() -> float:
	var base_range: float = 200.0
	match category:
		SimTypes.UnitCategory.CAVALRY:
			base_range = 230.0
		SimTypes.UnitCategory.ARTILLERY:
			base_range = 210.0
	return base_range * lerpf(0.75, 1.1, commander_quality)


func initialize_regiment_combat_state() -> void:
	morale = clamp(0.56 + commander_quality * 0.34, 0.0, 1.0)
	cohesion = clamp(0.54 + commander_quality * 0.34, 0.0, 1.0)
	combat_posture = CombatTypes.CombatPosture.IDLE
	combat_order_mode = CombatTypes.CombatOrderMode.NONE
	combat_lock_until = -1.0
	brace_until = -1.0
	charge_recovery_until = -1.0
	charge_retreat_until = -1.0
	charge_retreat_target_position = position
	charge_stage_position = position
	charge_stage_valid = false
	charge_target_company_id = &""
	last_combat_tick_seen_enemy = -1.0
	last_visible_enemy_distance = INF
	suppression = 0.0
	engagement_state = SimTypes.EngagementState.NO_CONTACT
	engagement_target_regiment_id = &""
	engagement_state_since = -1.0
	engagement_hold_until = -1.0
	engagement_anchor_position = position
	recent_incoming_pressure = 0.0
	recent_casualty_rate = 0.0
	recent_effective_losses = 0.0
	target_switch_cooldown_until = -1.0
	last_strength_sample = get_total_strength()
	last_suppression_sample = 0.0
	desired_formation_type = formation.formation_type
	desired_formation_state = formation_state
	formation_reform_until = -1.0
	formation_change_started_at = -1.0
	formation_change_cooldown_until = -1.0
	mark_target_layout_dirty()
	for company_value in companies:
		var company: CombatStand = company_value
		company.initialize_combat_state()
	refresh_combat_aggregates()


func refresh_combat_aggregates() -> void:
	if companies.is_empty():
		morale = 0.0
		cohesion = 0.0
		ammo_ratio = 0.0
		return
	var weighted_morale: float = 0.0
	var weighted_cohesion: float = 0.0
	var weighted_ammo: float = 0.0
	var total_weight: float = 0.0
	for company_value in companies:
		var company: CombatStand = company_value
		company.refresh_combat_profile()
		var weight: float = float(max(1, company.soldiers))
		weighted_morale += company.morale * weight
		weighted_cohesion += company.cohesion * weight
		weighted_ammo += company.ammo * weight
		total_weight += weight
	if total_weight <= 0.0:
		morale = 0.0
		cohesion = 0.0
		ammo_ratio = 0.0
		return
	morale = clamp(weighted_morale / total_weight, 0.0, 1.0)
	cohesion = clamp(weighted_cohesion / total_weight, 0.0, 1.0)
	ammo_ratio = clamp(weighted_ammo / total_weight, 0.0, 1.0)
	suppression = clamp(suppression, 0.0, 1.0)


func update_combat_intent(current_time_seconds: float) -> void:
	if current_time_seconds < combat_lock_until:
		combat_posture = CombatTypes.CombatPosture.MELEE
		combat_order_mode = CombatTypes.CombatOrderMode.NONE
		return

	if is_charge_retreating(current_time_seconds):
		combat_posture = CombatTypes.CombatPosture.RETIRING
		combat_order_mode = CombatTypes.CombatOrderMode.NONE
		return

	if is_charge_recovering(current_time_seconds):
		combat_posture = CombatTypes.CombatPosture.CHARGE_RECOVER
		combat_order_mode = CombatTypes.CombatOrderMode.NONE
		return

	var charge_ready: bool = category == SimTypes.UnitCategory.CAVALRY \
		and engagement_state == SimTypes.EngagementState.ASSAULT \
		and fire_behavior != SimTypes.RegimentFireBehavior.CARACOLE
	match engagement_state:
		SimTypes.EngagementState.DEPLOY_FIRE, SimTypes.EngagementState.FIREFIGHT:
			combat_posture = CombatTypes.CombatPosture.FIRING if fire_behavior != SimTypes.RegimentFireBehavior.NONE else CombatTypes.CombatPosture.IDLE
		SimTypes.EngagementState.ASSAULT:
			combat_posture = CombatTypes.CombatPosture.CHARGE_WINDUP if charge_ready else CombatTypes.CombatPosture.ADVANCING
		SimTypes.EngagementState.DISENGAGE:
			combat_posture = CombatTypes.CombatPosture.RETIRING
		SimTypes.EngagementState.RECOVER:
			combat_posture = CombatTypes.CombatPosture.CHARGE_RECOVER
		SimTypes.EngagementState.APPROACH:
			combat_posture = CombatTypes.CombatPosture.ADVANCING
		_:
			if current_order_type in [SimTypes.OrderType.MOVE, SimTypes.OrderType.MARCH, SimTypes.OrderType.ATTACK, SimTypes.OrderType.PATROL]:
				combat_posture = CombatTypes.CombatPosture.ADVANCING
			elif fire_behavior != SimTypes.RegimentFireBehavior.NONE:
				combat_posture = CombatTypes.CombatPosture.FIRING
			else:
				combat_posture = CombatTypes.CombatPosture.IDLE

	if formation_state == SimTypes.RegimentFormationState.PROTECTED or formation.formation_type == SimTypes.FormationType.SQUARE:
		if fire_behavior != SimTypes.RegimentFireBehavior.NONE and has_significant_firearm_capability():
			combat_order_mode = CombatTypes.CombatOrderMode.VOLLEY
		else:
			combat_order_mode = CombatTypes.CombatOrderMode.BRACE
		brace_until = max(brace_until, current_time_seconds + 0.25)
		return

	if charge_ready:
		combat_order_mode = CombatTypes.CombatOrderMode.CHARGE
		return

	match fire_behavior:
		SimTypes.RegimentFireBehavior.VOLLEY:
			combat_order_mode = CombatTypes.CombatOrderMode.VOLLEY
		SimTypes.RegimentFireBehavior.COUNTERMARCH:
			combat_order_mode = CombatTypes.CombatOrderMode.COUNTERMARCH
		SimTypes.RegimentFireBehavior.CARACOLE:
			combat_order_mode = CombatTypes.CombatOrderMode.FIRE_AT_WILL
		_:
			combat_order_mode = CombatTypes.CombatOrderMode.NONE


func is_combat_locked(current_time_seconds: float) -> bool:
	return combat_lock_until > current_time_seconds


func is_braced(current_time_seconds: float) -> bool:
	return brace_until > current_time_seconds


func has_debug_forced_formation() -> bool:
	return debug_forced_formation_state >= 0


func has_debug_forced_fire_behavior() -> bool:
	return debug_forced_fire_behavior >= 0


func has_debug_test_fire(current_time_seconds: float) -> bool:
	return debug_test_fire_until > current_time_seconds


func is_countermarch_active() -> bool:
	if fire_behavior != SimTypes.RegimentFireBehavior.COUNTERMARCH:
		return false
	if current_order_type == SimTypes.OrderType.MARCH:
		return false
	if category != SimTypes.UnitCategory.INFANTRY or not has_pike_and_shot_companies():
		return false
	if formation_state == SimTypes.RegimentFormationState.PROTECTED:
		return false
	return formation_state in [
		SimTypes.RegimentFormationState.DEFAULT,
		SimTypes.RegimentFormationState.MUSKETEER_LINE,
		SimTypes.RegimentFormationState.TERCIA,
	]


func is_caracole_active() -> bool:
	return fire_behavior == SimTypes.RegimentFireBehavior.CARACOLE \
		and formation.formation_type == SimTypes.FormationType.COLUMN


func _sync_front_direction_from_facing() -> void:
	var formation_front: Vector2 = Vector2.UP.rotated(formation.orientation)
	if formation_front.length_squared() <= 0.001:
		formation_front = Vector2.UP
	if front_direction.length_squared() <= 0.001:
		front_direction = formation_front
		return
	if absf(front_direction.angle_to(formation_front)) > 0.02:
		front_direction = formation_front


func _rebuild_formation_slots() -> void:
	formation_slots.clear()
	var slot_specs: Array = _build_company_slot_specs()
	_sync_formation_metrics_from_slot_specs(slot_specs)
	var tolerance: float = max(14.0, min(formation.frontage, formation.depth) * 0.18)
	for company_index in range(companies.size()):
		var company: CombatStand = companies[company_index]
		var slot_spec: Dictionary = slot_specs[company_index] if company_index < slot_specs.size() else {}
		var slot_position: Vector2 = slot_spec.get("position", Vector2.ZERO)
		var role_name: StringName = slot_spec.get("role", _get_slot_role(company_index, companies.size()))
		var slot_facing: Vector2 = slot_spec.get("facing", front_direction)
		var slot_tolerance: float = float(slot_spec.get("tolerance", tolerance))
		formation_slots.append(FormationSlot.new(
			StringName("%s_slot_%02d" % [String(id), company_index]),
			slot_position,
			slot_facing,
			role_name,
			slot_tolerance
		))
		company.assigned_slot_id = formation_slots[company_index].id


func _rebuild_formation_slots_from_visual_entries(visual_entries: Array) -> void:
	formation_slots.clear()
	var slot_specs: Array = _build_slot_specs_from_visual_entries(visual_entries)
	_sync_formation_metrics_from_slot_specs(slot_specs)
	var tolerance: float = max(14.0, min(formation.frontage, formation.depth) * 0.18)
	for company_index in range(companies.size()):
		var company: CombatStand = companies[company_index]
		var slot_spec: Dictionary = slot_specs[company_index] if company_index < slot_specs.size() else {}
		var slot_position: Vector2 = slot_spec.get("position", Vector2.ZERO)
		var role_name: StringName = slot_spec.get("role", _get_slot_role(company_index, companies.size()))
		var slot_facing: Vector2 = slot_spec.get("facing", front_direction)
		var slot_tolerance: float = float(slot_spec.get("tolerance", tolerance))
		formation_slots.append(FormationSlot.new(
			StringName("%s_slot_%02d" % [String(id), company_index]),
			slot_position,
			slot_facing,
			role_name,
			slot_tolerance
		))
		company.assigned_slot_id = formation_slots[company_index].id


func _build_banner_slot() -> FormationSlot:
	var local_position: Vector2 = Vector2.ZERO
	if is_caracole_active():
		local_position = Vector2(0.0, -formation.depth * 0.26)
	elif formation_state == SimTypes.RegimentFormationState.MARCH_COLUMN or formation.formation_type == SimTypes.FormationType.COLUMN:
		local_position = Vector2(0.0, -formation.depth * 0.42)
	elif category == SimTypes.UnitCategory.INFANTRY and formation_state == SimTypes.RegimentFormationState.MUSKETEER_LINE:
		local_position = Vector2(0.0, formation.depth * 0.35)
	else:
		local_position = Vector2(0.0, 0.0)
	return FormationSlot.new(
		StringName("%s_banner_slot" % String(id)),
		local_position,
		front_direction,
		&"banner",
		max(10.0, min(formation.frontage, formation.depth) * 0.14)
	)


func _get_slot_role(company_index: int, company_count: int) -> StringName:
	if company_count <= 2:
		return &"line"
	if company_index == 0:
		return &"left"
	if company_index == company_count - 1:
		return &"right"
	return &"center"


func _build_company_slot_specs() -> Array:
	if not DETAILED_VISUAL_BLOCKS_IN_SIM:
		var pattern_layout: Array = _build_runtime_pattern_visual_layout()
		if not pattern_layout.is_empty():
			return _build_slot_specs_from_visual_entries(pattern_layout)
		return _build_lightweight_company_slot_specs()
	if category == SimTypes.UnitCategory.INFANTRY and _has_company_type(SimTypes.CompanyType.PIKEMEN) and _has_company_type(SimTypes.CompanyType.MUSKETEERS):
		return _build_slot_specs_from_visual_entries(_build_target_company_visual_layout())
	if category == SimTypes.UnitCategory.CAVALRY or category == SimTypes.UnitCategory.ARTILLERY:
		return _build_slot_specs_from_visual_entries(_build_target_company_visual_layout())
	return _build_default_grid_specs()


func _build_lightweight_company_slot_specs() -> Array:
	return _build_editor_company_derived_slot_specs()


func _build_editor_company_derived_slot_specs() -> Array:
	var groups: Array = _build_editor_company_groups()
	if groups.is_empty():
		return _build_default_grid_specs()
	var group_specs: Array = _build_editor_company_center_specs(groups)
	return _expand_editor_company_group_specs_to_stands(groups, group_specs)


func _build_editor_company_groups() -> Array:
	var groups_by_tag: Dictionary = {}
	var ordered_tags: Array = []
	for stand_index in range(companies.size()):
		var stand: CombatStand = companies[stand_index]
		var tag: StringName = stand.editor_company_tag
		if tag == &"":
			tag = StringName("%s_editor_company_fallback_%02d" % [String(id), stand_index])
		if not groups_by_tag.has(tag):
			groups_by_tag[tag] = {
				"tag": tag,
				"name": stand.editor_company_name if stand.editor_company_name != "" else stand.display_name,
				"company_type": stand.company_type,
				"weapon_type": stand.weapon_type,
				"stand_indices": [],
			}
			ordered_tags.append(tag)
		var group: Dictionary = groups_by_tag[tag]
		var stand_indices: Array = group.get("stand_indices", [])
		stand_indices.append(stand_index)
		group["stand_indices"] = stand_indices
		groups_by_tag[tag] = group
	var result: Array = []
	for tag_value in ordered_tags:
		result.append(groups_by_tag.get(tag_value, {}))
	return result


func _build_editor_company_center_specs(groups: Array) -> Array:
	match category:
		SimTypes.UnitCategory.CAVALRY:
			return _build_cavalry_editor_company_center_specs(groups)
		SimTypes.UnitCategory.ARTILLERY:
			return _build_artillery_editor_company_center_specs(groups)
		_:
			if _groups_have_type(groups, SimTypes.CompanyType.PIKEMEN) and _groups_have_type(groups, SimTypes.CompanyType.MUSKETEERS):
				return _build_pike_and_shot_editor_company_center_specs(groups)
			return _build_single_arm_editor_company_center_specs(groups)


func _build_single_arm_editor_company_center_specs(groups: Array) -> Array:
	var specs: Array = _build_default_group_center_specs(groups)
	var musketeer_group_indices: Array = _get_editor_company_group_indices_by_type(groups, SimTypes.CompanyType.MUSKETEERS)
	var pike_group_indices: Array = _get_editor_company_group_indices_by_type(groups, SimTypes.CompanyType.PIKEMEN)
	var active_group_indices: Array = musketeer_group_indices if not musketeer_group_indices.is_empty() else pike_group_indices
	var slot_role: StringName = &"front_shot" if not musketeer_group_indices.is_empty() else &"pike_core"
	match formation_state:
		SimTypes.RegimentFormationState.MARCH_COLUMN:
			return _assign_group_column_specs(specs, active_group_indices, 24.0, &"column" if slot_role == &"front_shot" else &"column_core")
		SimTypes.RegimentFormationState.PROTECTED, SimTypes.RegimentFormationState.TERCIA:
			return _assign_group_grid_specs(
				specs,
				active_group_indices,
				min(max(2, int(ceil(sqrt(float(max(1, active_group_indices.size())))))), 4),
				28.0,
				22.0,
				slot_role
			)
		SimTypes.RegimentFormationState.MUSKETEER_LINE:
			return _assign_group_line_specs(specs, active_group_indices, min(max(1, active_group_indices.size()), 6), 30.0, 20.0, slot_role)
		_:
			return _assign_group_line_specs(specs, active_group_indices, min(max(1, active_group_indices.size()), 6), 28.0, 18.0, slot_role)


func _build_pike_and_shot_editor_company_center_specs(groups: Array) -> Array:
	if is_countermarch_active():
		match formation_state:
			SimTypes.RegimentFormationState.TERCIA:
				return _build_tercia_editor_company_center_specs(groups, &"countermarch_shot")
			SimTypes.RegimentFormationState.MUSKETEER_LINE:
				return _build_musketeer_line_editor_company_center_specs(groups, &"countermarch_shot")
			_:
				return _build_line_pike_and_shot_editor_company_center_specs(groups, &"countermarch_shot")
	match formation_state:
		SimTypes.RegimentFormationState.MARCH_COLUMN:
			return _build_pike_and_shot_column_editor_company_center_specs(groups)
		SimTypes.RegimentFormationState.PROTECTED:
			return _build_protected_editor_company_center_specs(groups)
		SimTypes.RegimentFormationState.MUSKETEER_LINE:
			return _build_musketeer_line_editor_company_center_specs(groups, &"front_shot")
		SimTypes.RegimentFormationState.TERCIA:
			return _build_tercia_editor_company_center_specs(groups, &"corner_shot")
		_:
			return _build_line_pike_and_shot_editor_company_center_specs(groups)


func _build_line_pike_and_shot_editor_company_center_specs(groups: Array, musket_role: StringName = &"") -> Array:
	var specs: Array = _build_default_group_center_specs(groups)
	var musket_group_indices: Array = _get_editor_company_group_indices_by_type(groups, SimTypes.CompanyType.MUSKETEERS)
	var pike_group_indices: Array = _get_editor_company_group_indices_by_type(groups, SimTypes.CompanyType.PIKEMEN)
	var resolved_musket_role: StringName = musket_role if musket_role != &"" else &"left_shot"
	var pike_columns: int = 1 if pike_group_indices.size() <= 1 else min(2, pike_group_indices.size())
	specs = _assign_group_grid_specs(specs, pike_group_indices, pike_columns, 22.0, 18.0, &"pike_core")
	var pike_half_width: float = _estimate_group_grid_half_width(pike_group_indices.size(), pike_columns, 22.0, 12.0)
	var musket_half_width: float = 16.5
	var flank_center_x: float = pike_half_width + musket_half_width + 18.0
	var left_count: int = int(ceil(float(musket_group_indices.size()) * 0.5))
	var right_count: int = max(0, musket_group_indices.size() - left_count)
	var left_role: StringName = resolved_musket_role if resolved_musket_role == &"countermarch_shot" else &"left_shot"
	var right_role: StringName = resolved_musket_role if resolved_musket_role == &"countermarch_shot" else &"right_shot"
	var left_columns: int = min(2, max(1, left_count))
	var left_rows: int = int(ceil(float(left_count) / float(max(1, left_columns))))
	var left_centers: Array = _build_rect_grid_offsets(left_columns, left_rows, 20.0, 16.0, Vector2(-flank_center_x, 0.0))
	for left_index in range(min(left_count, left_centers.size())):
		specs[musket_group_indices[left_index]] = _make_lightweight_slot_spec(left_centers[left_index], left_role, front_direction)
	var right_columns: int = min(2, max(1, right_count))
	var right_rows: int = int(ceil(float(right_count) / float(max(1, right_columns))))
	var right_centers: Array = _build_rect_grid_offsets(right_columns, right_rows, 20.0, 16.0, Vector2(flank_center_x, 0.0))
	for right_index in range(min(right_count, right_centers.size())):
		specs[musket_group_indices[left_count + right_index]] = _make_lightweight_slot_spec(right_centers[right_index], right_role, front_direction)
	return specs


func _build_pike_and_shot_column_editor_company_center_specs(groups: Array) -> Array:
	var specs: Array = _build_default_group_center_specs(groups)
	var musket_group_indices: Array = _get_editor_company_group_indices_by_type(groups, SimTypes.CompanyType.MUSKETEERS)
	var pike_group_indices: Array = _get_editor_company_group_indices_by_type(groups, SimTypes.CompanyType.PIKEMEN)
	var lead_guard_count: int = int(ceil(float(musket_group_indices.size()) * 0.5))
	var front_guard_indices: Array = musket_group_indices.slice(0, lead_guard_count)
	var rear_guard_indices: Array = musket_group_indices.slice(lead_guard_count, musket_group_indices.size())
	var pike_rows: int = int(ceil(float(max(1, pike_group_indices.size())) / 2.0))
	var guard_rows: int = int(ceil(float(max(1, lead_guard_count)) / 2.0))
	var block_gap: float = 18.0
	var pike_center: Vector2 = Vector2.ZERO
	var front_guard_center: Vector2 = Vector2(0.0, (float(pike_rows + guard_rows) * 9.0) + block_gap)
	var rear_guard_center: Vector2 = Vector2(0.0, -((float(pike_rows + guard_rows) * 9.0) + block_gap))
	var pike_centers: Array = _build_rect_grid_offsets(min(2, max(1, pike_group_indices.size())), pike_rows, 18.0, 16.0, pike_center)
	for pike_index in range(min(pike_group_indices.size(), pike_centers.size())):
		specs[pike_group_indices[pike_index]] = _make_lightweight_slot_spec(pike_centers[pike_index], &"column_core", front_direction)
	var front_guard_centers: Array = _build_rect_grid_offsets(min(2, max(1, front_guard_indices.size())), guard_rows, 18.0, 16.0, front_guard_center)
	for front_index in range(min(front_guard_indices.size(), front_guard_centers.size())):
		specs[front_guard_indices[front_index]] = _make_lightweight_slot_spec(front_guard_centers[front_index], &"advance_guard", front_direction)
	var rear_guard_rows: int = int(ceil(float(max(1, rear_guard_indices.size())) / 2.0))
	var rear_guard_centers: Array = _build_rect_grid_offsets(min(2, max(1, rear_guard_indices.size())), rear_guard_rows, 18.0, 16.0, rear_guard_center)
	for rear_index in range(min(rear_guard_indices.size(), rear_guard_centers.size())):
		specs[rear_guard_indices[rear_index]] = _make_lightweight_slot_spec(rear_guard_centers[rear_index], &"rear_guard", front_direction)
	return specs


func _build_musketeer_line_editor_company_center_specs(groups: Array, musket_role: StringName) -> Array:
	var specs: Array = _build_default_group_center_specs(groups)
	var musket_group_indices: Array = _get_editor_company_group_indices_by_type(groups, SimTypes.CompanyType.MUSKETEERS)
	var pike_group_indices: Array = _get_editor_company_group_indices_by_type(groups, SimTypes.CompanyType.PIKEMEN)
	specs = _assign_group_line_specs(specs, musket_group_indices, min(max(1, musket_group_indices.size()), 4), 24.0, 16.0, musket_role, Vector2(0.0, 18.0))
	specs = _assign_group_grid_specs(specs, pike_group_indices, min(max(1, pike_group_indices.size()), 2), 22.0, 16.0, &"rear_pike", Vector2(0.0, -18.0))
	return specs


func _build_protected_editor_company_center_specs(groups: Array) -> Array:
	var specs: Array = _build_default_group_center_specs(groups)
	var musket_group_indices: Array = _get_editor_company_group_indices_by_type(groups, SimTypes.CompanyType.MUSKETEERS)
	var pike_group_indices: Array = _get_editor_company_group_indices_by_type(groups, SimTypes.CompanyType.PIKEMEN)
	specs = _assign_group_grid_specs(
		specs,
		musket_group_indices,
		min(max(1, musket_group_indices.size()), 3),
		20.0,
		16.0,
		&"inner_shot"
	)
	var musket_columns: int = min(max(1, musket_group_indices.size()), 3)
	var musket_rows: int = int(ceil(float(max(1, musket_group_indices.size())) / float(max(1, musket_columns))))
	var half_width: float = _estimate_group_grid_half_width(musket_group_indices.size(), musket_columns, 20.0, 12.0) + 22.0
	var half_depth: float = _estimate_group_grid_half_depth(musket_rows, 16.0, 10.0) + 20.0
	var perimeter_specs: Array = _build_protected_perimeter_specs(pike_group_indices.size(), half_width, half_depth)
	for perimeter_index in range(min(pike_group_indices.size(), perimeter_specs.size())):
		var perimeter_spec: Dictionary = perimeter_specs[perimeter_index]
		specs[pike_group_indices[perimeter_index]] = _make_lightweight_slot_spec(
			perimeter_spec.get("position", Vector2.ZERO),
			&"outer_pike",
			perimeter_spec.get("facing", front_direction)
		)
	return specs


func _build_tercia_editor_company_center_specs(groups: Array, musket_role: StringName) -> Array:
	var specs: Array = _build_default_group_center_specs(groups)
	var musket_group_indices: Array = _get_editor_company_group_indices_by_type(groups, SimTypes.CompanyType.MUSKETEERS)
	var pike_group_indices: Array = _get_editor_company_group_indices_by_type(groups, SimTypes.CompanyType.PIKEMEN)
	var pike_columns: int = min(max(1, int(ceil(sqrt(float(max(1, pike_group_indices.size())))))), 4)
	specs = _assign_group_grid_specs(specs, pike_group_indices, pike_columns, 28.0, 24.0, &"tercia_pike")
	var pike_rows: int = int(ceil(float(max(1, pike_group_indices.size())) / float(max(1, pike_columns))))
	var core_half_width: float = _estimate_group_grid_half_width(pike_group_indices.size(), pike_columns, 28.0, 12.0) + 24.0
	var core_half_depth: float = _estimate_group_grid_half_depth(pike_rows, 24.0, 12.0) + 20.0
	var sleeve_centers: Array = _build_tercia_sleeve_company_centers(musket_group_indices.size(), core_half_width, core_half_depth, 28.0, 28.0)
	for musket_list_index in range(musket_group_indices.size()):
		specs[musket_group_indices[musket_list_index]] = _make_lightweight_slot_spec(
			sleeve_centers[musket_list_index],
			musket_role,
			front_direction
		)
	return specs


func _build_cavalry_editor_company_center_specs(groups: Array) -> Array:
	var specs: Array = _build_default_group_center_specs(groups)
	var group_indices: Array = _all_group_indices(groups.size())
	if is_caracole_active():
		return _build_cavalry_caracole_editor_company_center_specs(groups)
	if formation.formation_type == SimTypes.FormationType.COLUMN:
		return _assign_group_column_specs(specs, group_indices, 22.0, &"cavalry_column")
	return _assign_group_line_specs(specs, group_indices, min(max(1, group_indices.size()), 6), 28.0, 18.0, &"cavalry_line")


func _build_cavalry_caracole_editor_company_center_specs(groups: Array) -> Array:
	var specs: Array = _build_default_group_center_specs(groups)
	var group_indices: Array = _all_group_indices(groups.size())
	if group_indices.is_empty():
		return specs
	var wave_size: int = _get_caracole_wave_size()
	var ordered_indices: Array = _rotate_indices(group_indices, formation_cycle_index)
	var advanced_indices: Array = ordered_indices.slice(wave_size, ordered_indices.size())
	advanced_indices.append_array(ordered_indices.slice(0, wave_size))
	var start_offsets: Array = _build_front_to_rear_column_offsets(ordered_indices.size(), 28.0)
	var end_offsets: Array = _build_front_to_rear_column_offsets(advanced_indices.size(), 28.0)
	var flank_offset: float = -38.0
	var cycle_t: float = _get_caracole_phase_progress()
	var column_shift_weight: float = _get_caracole_column_shift_weight(cycle_t)
	var start_center_by_group: Dictionary = {}
	var end_center_by_group: Dictionary = {}
	for ordered_index in range(ordered_indices.size()):
		start_center_by_group[ordered_indices[ordered_index]] = Vector2(0.0, start_offsets[ordered_index])
	for advanced_index in range(advanced_indices.size()):
		end_center_by_group[advanced_indices[advanced_index]] = Vector2(0.0, end_offsets[advanced_index])
	for ordered_index in range(ordered_indices.size()):
		var group_index: int = ordered_indices[ordered_index]
		var start_center: Vector2 = start_center_by_group.get(group_index, Vector2.ZERO)
		var end_center: Vector2 = end_center_by_group.get(group_index, start_center)
		var center: Vector2 = start_center
		var slot_role: StringName = &"cavalry_column"
		if ordered_index < wave_size:
			var front_lane_center: Vector2 = start_center + Vector2(flank_offset, 0.0)
			var rear_lane_center: Vector2 = end_center + Vector2(flank_offset, 0.0)
			slot_role = &"caracole_front" if formation_cycle_phase == 0 else &"caracole_reforming"
			match formation_cycle_phase:
				0:
					center = start_center
				1:
					center = start_center.lerp(front_lane_center, cycle_t)
				2:
					center = front_lane_center.lerp(rear_lane_center, cycle_t)
				_:
					center = rear_lane_center.lerp(end_center, cycle_t)
		else:
			center = start_center.lerp(end_center, column_shift_weight)
		specs[group_index] = _make_lightweight_slot_spec(center, slot_role, front_direction)
	return specs


func _build_artillery_editor_company_center_specs(groups: Array) -> Array:
	var specs: Array = _build_default_group_center_specs(groups)
	var group_indices: Array = _all_group_indices(groups.size())
	if formation.formation_type == SimTypes.FormationType.COLUMN:
		return _assign_group_column_specs(specs, group_indices, 26.0, &"battery_column")
	return _assign_group_line_specs(specs, group_indices, min(max(1, group_indices.size()), 4), 34.0, 22.0, &"battery_line")


func _expand_editor_company_group_specs_to_stands(groups: Array, group_specs: Array) -> Array:
	var specs: Array = []
	specs.resize(companies.size())
	for group_index in range(groups.size()):
		var group: Dictionary = groups[group_index]
		var group_spec: Dictionary = group_specs[group_index] if group_index < group_specs.size() else {}
		var stand_indices: Array = group.get("stand_indices", [])
		var stand_specs: Array = _build_stand_specs_for_editor_company_group(group, group_spec)
		for stand_list_index in range(min(stand_indices.size(), stand_specs.size())):
			var stand_index: int = stand_indices[stand_list_index]
			specs[stand_index] = stand_specs[stand_list_index]
	return specs


func _build_stand_specs_for_editor_company_group(group: Dictionary, group_spec: Dictionary) -> Array:
	var result: Array = []
	var company_type: int = int(group.get("company_type", SimTypes.CompanyType.MUSKETEERS))
	var stand_indices: Array = group.get("stand_indices", [])
	var stand_count: int = stand_indices.size()
	if stand_count <= 0:
		return result
	var center: Vector2 = group_spec.get("position", Vector2.ZERO)
	var facing: Vector2 = group_spec.get("facing", front_direction)
	if facing.length_squared() <= 0.001:
		facing = front_direction
	if facing.length_squared() <= 0.001:
		facing = Vector2.UP
	facing = facing.normalized()
	var slot_role: StringName = group_spec.get("role", &"line")
	var tolerance: float = max(8.0, float(group_spec.get("tolerance", 18.0)) * 0.58)
	var right_axis: Vector2 = Vector2(-facing.y, facing.x).normalized()

	if company_type == SimTypes.CompanyType.MUSKETEERS and slot_role == &"countermarch_shot":
		var countermarch_elements: Array = _build_countermarch_company_elements(
			center,
			facing,
			right_axis,
			16.0,
			12.0,
			bool(formation_cycle_index % 2),
			formation_cycle_phase == 0
		)
		for element_index in range(min(stand_count, countermarch_elements.size())):
			var element: Dictionary = countermarch_elements[element_index]
			result.append({
				"position": element.get("position", center),
				"facing": element.get("front_direction", facing),
				"role": element.get("role", &"countermarch_front"),
				"tolerance": tolerance,
			})
		return result

	if company_type == SimTypes.CompanyType.ARTILLERY and stand_count <= 2:
		var artillery_elements: Array = _build_artillery_company_elements(center, facing, right_axis)
		for element_index in range(min(stand_count, artillery_elements.size())):
			var element: Dictionary = artillery_elements[element_index]
			result.append({
				"position": element.get("position", center),
				"facing": element.get("front_direction", facing),
				"role": slot_role,
				"tolerance": tolerance,
			})
		if result.size() == stand_count:
			return result

	var local_offsets: Array = _build_internal_offsets_for_group_members(company_type, slot_role, stand_count)
	for offset_index in range(local_offsets.size()):
		var local_offset: Vector2 = local_offsets[offset_index]
		result.append({
			"position": center + right_axis * local_offset.x + facing * local_offset.y,
			"facing": facing,
			"role": slot_role,
			"tolerance": tolerance,
		})
	return result


func _build_internal_offsets_for_group_members(company_type: int, slot_role: StringName, stand_count: int) -> Array:
	if stand_count <= 0:
		return []
	if company_type == SimTypes.CompanyType.CAVALRY:
		if slot_role in [&"cavalry_column", &"caracole_front", &"caracole_reforming"]:
			return _build_rect_grid_offsets(1, stand_count, 0.0, 10.0, Vector2.ZERO)
		if stand_count <= 3:
			return _build_rect_grid_offsets(stand_count, 1, 11.0, 0.0, Vector2.ZERO)
		return _build_rect_grid_offsets(2, int(ceil(float(stand_count) / 2.0)), 11.0, 10.0, Vector2.ZERO)
	if company_type == SimTypes.CompanyType.ARTILLERY:
		return _build_rect_grid_offsets(stand_count, 1, 12.0, 0.0, Vector2.ZERO)
	var infantry_offsets: Array = _get_infantry_visual_offsets(company_type, slot_role)
	if infantry_offsets.size() == stand_count:
		return infantry_offsets
	if slot_role in [&"advance_guard", &"rear_guard", &"column", &"column_core"]:
		var column_columns: int = min(max(1, stand_count), 2)
		var column_rows: int = int(ceil(float(stand_count) / float(max(1, column_columns))))
		return _build_rect_grid_offsets(column_columns, column_rows, 10.5, 9.0, Vector2.ZERO)
	if slot_role in [&"front_shot", &"left_shot", &"right_shot", &"line", &"fire_line"]:
		var line_columns: int = min(max(1, stand_count), 4)
		var line_rows: int = int(ceil(float(stand_count) / float(max(1, line_columns))))
		return _build_rect_grid_offsets(line_columns, line_rows, 11.0, 9.5, Vector2.ZERO)
	if slot_role == &"rear_pike":
		var rear_pike_columns: int = min(max(2, int(ceil(sqrt(float(stand_count))))), 3)
		var rear_pike_rows: int = int(ceil(float(stand_count) / float(max(1, rear_pike_columns))))
		return _build_rect_grid_offsets(rear_pike_columns, rear_pike_rows, 10.0, 9.5, Vector2.ZERO)
	if slot_role == &"outer_pike":
		var perimeter_columns: int = min(max(1, stand_count), 4)
		var perimeter_rows: int = int(ceil(float(stand_count) / float(max(1, perimeter_columns))))
		return _build_rect_grid_offsets(perimeter_columns, perimeter_rows, 10.5, 8.5, Vector2.ZERO)
	if company_type == SimTypes.CompanyType.PIKEMEN or slot_role in [&"pike_core", &"outer_pike", &"tercia_pike", &"inner_shot", &"corner_shot"]:
		var columns: int = min(max(2, int(ceil(sqrt(float(stand_count))))), 3)
		var rows: int = int(ceil(float(stand_count) / float(max(1, columns))))
		return _build_rect_grid_offsets(columns, rows, 10.0, 9.5, Vector2.ZERO)
	return _build_rect_grid_offsets(min(max(1, stand_count), 2), int(ceil(float(stand_count) / 2.0)), 10.5, 9.5, Vector2.ZERO)


func _build_default_group_center_specs(groups: Array) -> Array:
	var specs: Array = []
	specs.resize(groups.size())
	var local_centers: Array = formation.build_subunit_local_centers(groups.size())
	var tolerance: float = max(14.0, min(formation.frontage, formation.depth) * 0.18)
	for group_index in range(groups.size()):
		var local_center: Vector2 = local_centers[group_index] if group_index < local_centers.size() else Vector2.ZERO
		specs[group_index] = {
			"position": local_center,
			"facing": front_direction,
			"role": &"line",
			"tolerance": tolerance,
		}
	return specs


func _all_group_indices(count: int) -> Array:
	var result: Array = []
	for group_index in range(count):
		result.append(group_index)
	return result


func _groups_have_type(groups: Array, target_type: int) -> bool:
	for group_value in groups:
		var group: Dictionary = group_value
		if int(group.get("company_type", -1)) == target_type:
			return true
	return false


func _get_editor_company_group_indices_by_type(groups: Array, target_type: int) -> Array:
	var result: Array = []
	for group_index in range(groups.size()):
		var group: Dictionary = groups[group_index]
		if int(group.get("company_type", -1)) == target_type:
			result.append(group_index)
	return result


func _assign_group_column_specs(specs: Array, group_indices: Array, spacing: float, role: StringName) -> Array:
	var offsets: Array = _build_front_to_rear_column_offsets(group_indices.size(), spacing)
	for list_index in range(group_indices.size()):
		specs[group_indices[list_index]] = _make_lightweight_slot_spec(Vector2(0.0, offsets[list_index]), role, front_direction)
	return specs


func _assign_group_line_specs(
		specs: Array,
		group_indices: Array,
		front_columns: int,
		x_spacing: float,
		y_spacing: float,
		role: StringName,
		center_offset: Vector2 = Vector2.ZERO
) -> Array:
	var columns: int = max(1, front_columns)
	var rows: int = int(ceil(float(max(1, group_indices.size())) / float(columns)))
	var centers: Array = _build_rect_grid_offsets(columns, rows, x_spacing, y_spacing, center_offset)
	for list_index in range(min(group_indices.size(), centers.size())):
		specs[group_indices[list_index]] = _make_lightweight_slot_spec(centers[list_index], role, front_direction)
	return specs


func _assign_group_grid_specs(
		specs: Array,
		group_indices: Array,
		columns: int,
		x_spacing: float,
		y_spacing: float,
		role: StringName,
		center_offset: Vector2 = Vector2.ZERO
) -> Array:
	var centers: Array = _build_rect_grid_offsets(max(1, columns), int(ceil(float(max(1, group_indices.size())) / float(max(1, columns)))), x_spacing, y_spacing, center_offset)
	for list_index in range(min(group_indices.size(), centers.size())):
		specs[group_indices[list_index]] = _make_lightweight_slot_spec(centers[list_index], role, front_direction)
	return specs


func _estimate_group_grid_half_width(count: int, columns: int, x_spacing: float, block_half_width: float) -> float:
	if count <= 0:
		return block_half_width
	var actual_columns: int = min(max(1, columns), count)
	return float(max(0, actual_columns - 1)) * x_spacing * 0.5 + block_half_width


func _estimate_group_grid_half_depth(rows: int, y_spacing: float, block_half_depth: float) -> float:
	return float(max(0, rows - 1)) * y_spacing * 0.5 + block_half_depth


func _build_protected_perimeter_specs(count: int, half_width: float, half_depth: float) -> Array:
	var result: Array = []
	if count <= 0:
		return result
	var front: Vector2 = front_direction.normalized() if front_direction.length_squared() > 0.001 else Vector2.UP
	var right_axis: Vector2 = Vector2(-front.y, front.x).normalized()
	var base_positions: Array = [
		{"position": Vector2(0.0, half_depth), "facing": front},
		{"position": Vector2(0.0, -half_depth), "facing": -front},
		{"position": Vector2(-half_width, 0.0), "facing": -right_axis},
		{"position": Vector2(half_width, 0.0), "facing": right_axis},
		{"position": Vector2(-half_width, half_depth * 0.74), "facing": (-right_axis + front).normalized()},
		{"position": Vector2(half_width, half_depth * 0.74), "facing": (right_axis + front).normalized()},
		{"position": Vector2(-half_width, -half_depth * 0.74), "facing": (-right_axis - front).normalized()},
		{"position": Vector2(half_width, -half_depth * 0.74), "facing": (right_axis - front).normalized()},
	]
	for base_index in range(min(count, base_positions.size())):
		result.append(base_positions[base_index])
	return result


func _sync_formation_metrics_from_slot_specs(slot_specs: Array) -> void:
	if slot_specs.is_empty():
		return
	var min_x: float = INF
	var max_x: float = -INF
	var min_y: float = INF
	var max_y: float = -INF
	for slot_index in range(slot_specs.size()):
		var slot_spec: Dictionary = slot_specs[slot_index]
		var local_position: Vector2 = slot_spec.get("position", Vector2.ZERO)
		var stand: CombatStand = companies[slot_index] if slot_index < companies.size() else null
		var half_width: float = 12.0
		var half_depth: float = 10.0
		if stand != null:
			half_width = max(10.0, stand.frontage_width * 0.52)
			half_depth = max(9.0, stand.depth_density * 6.0)
			if stand.company_type == SimTypes.CompanyType.CAVALRY:
				half_width = max(12.0, stand.frontage_width * 0.46)
				half_depth = max(10.0, stand.depth_density * 7.0)
			elif stand.company_type == SimTypes.CompanyType.ARTILLERY:
				half_width = max(14.0, stand.frontage_width * 0.42)
				half_depth = max(11.0, stand.depth_density * 7.5)
		min_x = min(min_x, local_position.x - half_width)
		max_x = max(max_x, local_position.x + half_width)
		min_y = min(min_y, local_position.y - half_depth)
		max_y = max(max_y, local_position.y + half_depth)
	formation.frontage = max(28.0, (max_x - min_x) + 16.0)
	formation.depth = max(24.0, (max_y - min_y) + 18.0)


func _build_lightweight_single_arm_infantry_slot_specs() -> Array:
	var musket_indices: Array = _get_company_indices_by_type(SimTypes.CompanyType.MUSKETEERS)
	var pike_indices: Array = _get_company_indices_by_type(SimTypes.CompanyType.PIKEMEN)
	var active_indices: Array = musket_indices if not musket_indices.is_empty() else pike_indices
	var slot_role: StringName = &"front_shot" if not musket_indices.is_empty() else &"pike_core"
	match formation_state:
		SimTypes.RegimentFormationState.MARCH_COLUMN:
			return _build_lightweight_column_slot_specs(active_indices, 38.0, &"column" if slot_role == &"front_shot" else &"column_core")
		SimTypes.RegimentFormationState.PROTECTED, SimTypes.RegimentFormationState.TERCIA:
			var columns: int = int(ceil(sqrt(float(max(1, active_indices.size())))))
			var rows: int = int(ceil(float(active_indices.size()) / float(max(1, columns))))
			return _build_lightweight_grid_slot_specs(active_indices, columns, rows, 34.0, 28.0, slot_role)
		SimTypes.RegimentFormationState.MUSKETEER_LINE:
			var expanded_columns: int = min(max(1, active_indices.size()), 6)
			var expanded_rows: int = int(ceil(float(active_indices.size()) / float(expanded_columns)))
			return _build_lightweight_grid_slot_specs(active_indices, expanded_columns, expanded_rows, 42.0 if slot_role == &"front_shot" else 34.0, 28.0, slot_role)
		_:
			var line_columns: int = min(max(1, active_indices.size()), 6)
			var line_rows: int = int(ceil(float(active_indices.size()) / float(line_columns)))
			return _build_lightweight_grid_slot_specs(active_indices, line_columns, line_rows, 42.0 if slot_role == &"front_shot" else 34.0, 24.0, slot_role)


func _build_lightweight_pike_and_shot_slot_specs() -> Array:
	if is_countermarch_active():
		match formation_state:
			SimTypes.RegimentFormationState.TERCIA:
				return _build_lightweight_tercia_slot_specs(&"countermarch_shot")
			SimTypes.RegimentFormationState.MUSKETEER_LINE:
				return _build_lightweight_musketeer_line_slot_specs(&"countermarch_shot")
			_:
				return _build_lightweight_line_pike_and_shot_slot_specs(&"countermarch_shot")
	match formation_state:
		SimTypes.RegimentFormationState.MARCH_COLUMN:
			return _build_lightweight_pike_and_shot_column_slot_specs()
		SimTypes.RegimentFormationState.PROTECTED:
			return _build_lightweight_protected_slot_specs()
		SimTypes.RegimentFormationState.MUSKETEER_LINE:
			return _build_lightweight_musketeer_line_slot_specs(&"front_shot")
		SimTypes.RegimentFormationState.TERCIA:
			return _build_lightweight_tercia_slot_specs(&"corner_shot")
		_:
			return _build_lightweight_line_pike_and_shot_slot_specs()


func _build_lightweight_line_pike_and_shot_slot_specs(musket_role: StringName = &"") -> Array:
	var specs: Array = _build_default_grid_specs()
	var musket_indices: Array = _get_company_indices_by_type(SimTypes.CompanyType.MUSKETEERS)
	var pike_indices: Array = _get_company_indices_by_type(SimTypes.CompanyType.PIKEMEN)
	var resolved_musket_role: StringName = musket_role if musket_role != &"" else &"left_shot"
	var pike_columns: int = 2 if pike_indices.size() <= 2 else int(ceil(sqrt(float(pike_indices.size()))))
	var pike_rows: int = int(ceil(float(max(1, pike_indices.size())) / float(max(1, pike_columns))))
	var pike_centers: Array = _build_rect_grid_offsets(pike_columns, pike_rows, 22.0, 18.0, Vector2.ZERO)
	for pike_list_index in range(pike_indices.size()):
		specs[pike_indices[pike_list_index]] = _make_lightweight_slot_spec(
			pike_centers[pike_list_index],
			&"pike_core",
			front_direction
		)
	var left_musket_count: int = int(ceil(float(musket_indices.size()) * 0.5))
	var right_musket_count: int = max(0, musket_indices.size() - left_musket_count)
	var pike_half_width: float = max(16.0, float(max(1, pike_columns - 1)) * 11.0 + 14.0)
	var flank_center_x: float = pike_half_width + 34.0
	var left_offsets: Array = _build_front_to_rear_column_offsets(left_musket_count, 24.0, -5.0)
	for left_index in range(left_musket_count):
		specs[musket_indices[left_index]] = _make_lightweight_slot_spec(
			Vector2(-flank_center_x, left_offsets[left_index]),
			resolved_musket_role if resolved_musket_role == &"countermarch_shot" else &"left_shot",
			front_direction
		)
	var right_offsets: Array = _build_front_to_rear_column_offsets(right_musket_count, 24.0, -5.0)
	for right_index in range(right_musket_count):
		specs[musket_indices[left_musket_count + right_index]] = _make_lightweight_slot_spec(
			Vector2(flank_center_x, right_offsets[right_index]),
			resolved_musket_role if resolved_musket_role == &"countermarch_shot" else &"right_shot",
			front_direction
		)
	return specs


func _build_lightweight_pike_and_shot_column_slot_specs() -> Array:
	var specs: Array = _build_default_grid_specs()
	var musket_indices: Array = _get_company_indices_by_type(SimTypes.CompanyType.MUSKETEERS)
	var pike_indices: Array = _get_company_indices_by_type(SimTypes.CompanyType.PIKEMEN)
	var lead_guard_count: int = int(ceil(float(musket_indices.size()) * 0.5))
	var ordered_indices: Array = []
	var ordered_roles: Array = []
	for lead_index in range(lead_guard_count):
		ordered_indices.append(musket_indices[lead_index])
		ordered_roles.append(&"advance_guard")
	for pike_index in pike_indices:
		ordered_indices.append(pike_index)
		ordered_roles.append(&"column_core")
	for rear_index in range(lead_guard_count, musket_indices.size()):
		ordered_indices.append(musket_indices[rear_index])
		ordered_roles.append(&"rear_guard")
	var offsets: Array = _build_front_to_rear_column_offsets(ordered_indices.size(), 36.0)
	for ordered_index in range(ordered_indices.size()):
		specs[ordered_indices[ordered_index]] = _make_lightweight_slot_spec(
			Vector2(0.0, offsets[ordered_index]),
			ordered_roles[ordered_index],
			front_direction
		)
	return specs


func _build_lightweight_musketeer_line_slot_specs(musket_role: StringName) -> Array:
	var specs: Array = _build_default_grid_specs()
	var musket_indices: Array = _get_company_indices_by_type(SimTypes.CompanyType.MUSKETEERS)
	var pike_indices: Array = _get_company_indices_by_type(SimTypes.CompanyType.PIKEMEN)
	var musket_columns: int = min(4, max(1, musket_indices.size()))
	var musket_rows: int = int(ceil(float(musket_indices.size()) / float(max(1, musket_columns))))
	var musket_centers: Array = _build_rect_grid_offsets(musket_columns, musket_rows, 26.0, 24.0, Vector2(0.0, 28.0))
	for musket_list_index in range(musket_indices.size()):
		specs[musket_indices[musket_list_index]] = _make_lightweight_slot_spec(
			musket_centers[musket_list_index],
			musket_role,
			front_direction
		)
	var pike_columns: int = min(3, max(1, pike_indices.size()))
	var pike_rows: int = int(ceil(float(pike_indices.size()) / float(max(1, pike_columns))))
	var pike_centers: Array = _build_rect_grid_offsets(pike_columns, pike_rows, 24.0, 18.0, Vector2(0.0, -22.0))
	for pike_list_index in range(pike_indices.size()):
		specs[pike_indices[pike_list_index]] = _make_lightweight_slot_spec(
			pike_centers[pike_list_index],
			&"rear_pike",
			front_direction
		)
	return specs


func _build_lightweight_protected_slot_specs() -> Array:
	var specs: Array = _build_default_grid_specs()
	var musket_indices: Array = _get_company_indices_by_type(SimTypes.CompanyType.MUSKETEERS)
	var pike_indices: Array = _get_company_indices_by_type(SimTypes.CompanyType.PIKEMEN)
	var musket_columns: int = min(4, max(1, musket_indices.size()))
	var musket_rows: int = int(ceil(float(musket_indices.size()) / float(max(1, musket_columns))))
	var musket_centers: Array = _build_rect_grid_offsets(musket_columns, musket_rows, 18.0, 18.0, Vector2.ZERO)
	for musket_list_index in range(musket_indices.size()):
		specs[musket_indices[musket_list_index]] = _make_lightweight_slot_spec(
			musket_centers[musket_list_index],
			&"inner_shot",
			front_direction
		)
	var perimeter_centers: Array = _build_tercia_sleeve_company_centers(pike_indices.size(), 32.0, 30.0, 24.0, 24.0)
	for pike_list_index in range(pike_indices.size()):
		var local_center: Vector2 = perimeter_centers[pike_list_index]
		specs[pike_indices[pike_list_index]] = _make_lightweight_slot_spec(
			local_center,
			&"outer_pike",
			_lightweight_perimeter_facing(local_center)
		)
	return specs


func _build_lightweight_tercia_slot_specs(musket_role: StringName) -> Array:
	var specs: Array = _build_default_grid_specs()
	var musket_indices: Array = _get_company_indices_by_type(SimTypes.CompanyType.MUSKETEERS)
	var pike_indices: Array = _get_company_indices_by_type(SimTypes.CompanyType.PIKEMEN)
	var pike_columns: int = int(ceil(sqrt(float(max(1, pike_indices.size())))))
	var pike_rows: int = int(ceil(float(pike_indices.size()) / float(max(1, pike_columns))))
	var pike_centers: Array = _build_rect_grid_offsets(pike_columns, pike_rows, 32.0, 30.0, Vector2.ZERO)
	for pike_list_index in range(pike_indices.size()):
		specs[pike_indices[pike_list_index]] = _make_lightweight_slot_spec(
			pike_centers[pike_list_index],
			&"tercia_pike",
			front_direction
		)
	var sleeve_centers: Array = _build_tercia_sleeve_company_centers(musket_indices.size(), 40.0, 34.0, 28.0, 28.0)
	for musket_list_index in range(musket_indices.size()):
		specs[musket_indices[musket_list_index]] = _make_lightweight_slot_spec(
			sleeve_centers[musket_list_index],
			musket_role,
			front_direction
		)
	return specs


func _build_lightweight_cavalry_caracole_slot_specs() -> Array:
	var specs: Array = _build_default_grid_specs()
	var cavalry_indices: Array = _get_company_indices_by_type(SimTypes.CompanyType.CAVALRY)
	if cavalry_indices.is_empty():
		return specs
	var wave_size: int = _get_caracole_wave_size()
	var ordered_indices: Array = _rotate_indices(cavalry_indices, formation_cycle_index)
	var advanced_indices: Array = ordered_indices.slice(wave_size, ordered_indices.size())
	advanced_indices.append_array(ordered_indices.slice(0, wave_size))
	var start_offsets: Array = _build_front_to_rear_column_offsets(ordered_indices.size(), 28.0)
	var end_offsets: Array = _build_front_to_rear_column_offsets(advanced_indices.size(), 28.0)
	var flank_offset: float = -34.0
	var cycle_t: float = _get_caracole_phase_progress()
	var column_shift_weight: float = _get_caracole_column_shift_weight(cycle_t)
	var start_center_by_company: Dictionary = {}
	var end_center_by_company: Dictionary = {}
	for ordered_index in range(ordered_indices.size()):
		var company_index: int = ordered_indices[ordered_index]
		start_center_by_company[company_index] = Vector2(0.0, start_offsets[ordered_index])
	for advanced_index in range(advanced_indices.size()):
		var company_index: int = advanced_indices[advanced_index]
		end_center_by_company[company_index] = Vector2(0.0, end_offsets[advanced_index])
	for ordered_index in range(ordered_indices.size()):
		var company_index: int = ordered_indices[ordered_index]
		var start_center: Vector2 = start_center_by_company.get(company_index, Vector2.ZERO)
		var end_center: Vector2 = end_center_by_company.get(company_index, start_center)
		var center: Vector2 = start_center
		var slot_role: StringName = &"cavalry_column"
		if ordered_index < wave_size:
			var front_lane_center: Vector2 = start_center + Vector2(flank_offset, 0.0)
			var rear_lane_center: Vector2 = end_center + Vector2(flank_offset, 0.0)
			slot_role = &"caracole_front" if formation_cycle_phase == 0 else &"caracole_reforming"
			match formation_cycle_phase:
				0:
					center = start_center
				1:
					center = start_center.lerp(front_lane_center, cycle_t)
				2:
					center = front_lane_center.lerp(rear_lane_center, cycle_t)
				_:
					center = rear_lane_center.lerp(end_center, cycle_t)
		else:
			center = start_center.lerp(end_center, column_shift_weight)
		specs[company_index] = _make_lightweight_slot_spec(center, slot_role, front_direction)
	return specs


func _build_lightweight_line_slot_specs(company_indices: Array, x_spacing: float, y_spacing: float, role: StringName) -> Array:
	var columns: int = max(1, company_indices.size())
	return _build_lightweight_grid_slot_specs(company_indices, columns, 1, x_spacing, y_spacing, role)


func _build_lightweight_column_slot_specs(company_indices: Array, spacing: float, role: StringName) -> Array:
	var specs: Array = _build_default_grid_specs()
	var offsets: Array = _build_front_to_rear_column_offsets(company_indices.size(), spacing)
	for company_list_index in range(company_indices.size()):
		specs[company_indices[company_list_index]] = _make_lightweight_slot_spec(
			Vector2(0.0, offsets[company_list_index]),
			role,
			front_direction
		)
	return specs


func _build_lightweight_grid_slot_specs(company_indices: Array, columns: int, rows: int, x_spacing: float, y_spacing: float, role: StringName, center_offset: Vector2 = Vector2.ZERO) -> Array:
	var specs: Array = _build_default_grid_specs()
	var local_centers: Array = _build_rect_grid_offsets(max(1, columns), max(1, rows), x_spacing, y_spacing, center_offset)
	for company_list_index in range(min(company_indices.size(), local_centers.size())):
		specs[company_indices[company_list_index]] = _make_lightweight_slot_spec(
			local_centers[company_list_index],
			role,
			front_direction
		)
	return specs


func _make_lightweight_slot_spec(local_position: Vector2, role: StringName, facing: Vector2) -> Dictionary:
	var resolved_facing: Vector2 = facing.normalized() if facing.length_squared() > 0.001 else front_direction
	if resolved_facing.length_squared() <= 0.001:
		resolved_facing = Vector2.UP
	return {
		"position": local_position,
		"facing": resolved_facing,
		"role": role,
		"tolerance": max(14.0, min(formation.frontage, formation.depth) * 0.18),
	}


func _lightweight_perimeter_facing(local_center: Vector2) -> Vector2:
	var front: Vector2 = front_direction.normalized() if front_direction.length_squared() > 0.001 else Vector2.UP
	var right_axis: Vector2 = Vector2(-front.y, front.x).normalized()
	if absf(local_center.x) > absf(local_center.y):
		return right_axis if local_center.x > 0.0 else -right_axis
	return front if local_center.y > 0.0 else -front


func _all_company_indices() -> Array:
	var result: Array = []
	for company_index in range(companies.size()):
		result.append(company_index)
	return result


func _build_default_grid_specs() -> Array:
	var specs: Array = []
	specs.resize(companies.size())
	var ordered_indices: Array = _get_runtime_ordered_company_indices()
	var local_centers: Array = formation.build_subunit_local_centers(ordered_indices.size())
	var tolerance: float = max(10.0, min(formation.frontage, formation.depth) * 0.12)
	for ordered_index in range(ordered_indices.size()):
		var company_index: int = ordered_indices[ordered_index]
		var local_center: Vector2 = local_centers[ordered_index]
		specs[company_index] = {
			"position": local_center,
			"facing": front_direction,
			"role": _get_runtime_slot_role(company_index),
			"tolerance": tolerance,
		}
	return specs


func _get_runtime_ordered_company_indices() -> Array:
	var ordered: Array = _all_company_indices()
	ordered.sort_custom(func(a: int, b: int) -> bool:
		var left_company: CombatStand = companies[a]
		var right_company: CombatStand = companies[b]
		var left_segment: int = _get_runtime_segment_priority(left_company.home_segment)
		var right_segment: int = _get_runtime_segment_priority(right_company.home_segment)
		if left_segment != right_segment:
			return left_segment < right_segment
		var left_type_priority: int = 0 if left_company.company_type == SimTypes.CompanyType.PIKEMEN else 1
		var right_type_priority: int = 0 if right_company.company_type == SimTypes.CompanyType.PIKEMEN else 1
		if left_type_priority != right_type_priority:
			return left_type_priority < right_type_priority
		return String(left_company.id) < String(right_company.id)
	)
	return ordered


func _get_runtime_segment_priority(segment: StringName) -> int:
	match segment:
		&"left":
			return 0
		&"core", &"center", &"battery":
			return 1
		&"right":
			return 2
		_:
			return 1


func _get_runtime_slot_role(company_index: int) -> StringName:
	if company_index < 0 or company_index >= companies.size():
		return &"line"
	var company: CombatStand = companies[company_index]
	if category == SimTypes.UnitCategory.ARTILLERY:
		return &"battery_column" if formation.formation_type == SimTypes.FormationType.COLUMN else &"battery_line"
	if category == SimTypes.UnitCategory.CAVALRY:
		if is_caracole_active():
			return &"caracole_front"
		return &"cavalry_column" if formation.formation_type == SimTypes.FormationType.COLUMN else &"cavalry_line"
	if company.company_type == SimTypes.CompanyType.PIKEMEN:
		return &"outer_pike" if formation_state == SimTypes.RegimentFormationState.PROTECTED else &"pike_core"
	if formation.formation_type == SimTypes.FormationType.COLUMN or formation_state == SimTypes.RegimentFormationState.MARCH_COLUMN:
		return &"column"
	if formation_state == SimTypes.RegimentFormationState.PROTECTED:
		return &"inner_shot"
	if fire_behavior == SimTypes.RegimentFireBehavior.COUNTERMARCH:
		return &"countermarch_shot"
	match company.home_segment:
		&"left":
			return &"left_shot"
		&"right":
			return &"right_shot"
		_:
			return &"front_shot"


func _has_company_type(target_type: int) -> bool:
	for company_value in companies:
		var company: CombatStand = company_value
		if company.company_type == target_type:
			return true
	return false


func _get_company_indices_by_type(target_type: int) -> Array:
	var indices: Array = []
	for company_index in range(companies.size()):
		var company: CombatStand = companies[company_index]
		if company.company_type == target_type:
			indices.append(company_index)
	return indices


func _build_infantry_regiment_visual_layout() -> Array:
	if has_pike_and_shot_companies():
		return _build_pike_and_shot_regiment_visual_layout()
	return _build_single_arm_infantry_visual_layout()


func _build_single_arm_infantry_visual_layout() -> Array:
	var musket_indices: Array = _get_company_indices_by_type(SimTypes.CompanyType.MUSKETEERS)
	var pike_indices: Array = _get_company_indices_by_type(SimTypes.CompanyType.PIKEMEN)
	var active_indices: Array = musket_indices if not musket_indices.is_empty() else pike_indices
	var primary_type: int = SimTypes.CompanyType.MUSKETEERS if not musket_indices.is_empty() else SimTypes.CompanyType.PIKEMEN
	match formation_state:
		SimTypes.RegimentFormationState.MARCH_COLUMN:
			return _build_single_arm_infantry_column_visual_elements(active_indices, primary_type)
		SimTypes.RegimentFormationState.PROTECTED, SimTypes.RegimentFormationState.TERCIA:
			return _build_single_arm_infantry_block_visual_elements(active_indices, primary_type)
		SimTypes.RegimentFormationState.MUSKETEER_LINE:
			return _build_single_arm_infantry_line_visual_elements(active_indices, primary_type, true)
		_:
			return _build_single_arm_infantry_line_visual_elements(active_indices, primary_type, false)


func _build_single_arm_infantry_line_visual_elements(company_indices: Array, company_type: int, expanded_front: bool) -> Array:
	var result: Array = []
	if company_indices.is_empty():
		return result
	var front: Vector2 = front_direction.normalized()
	if front.length_squared() <= 0.001:
		front = Vector2.UP
	var right_axis: Vector2 = Vector2(-front.y, front.x).normalized()
	var columns: int = min(max(1, company_indices.size()), 6)
	var rows: int = int(ceil(float(company_indices.size()) / float(columns)))
	var x_spacing: float = 42.0 if company_type == SimTypes.CompanyType.MUSKETEERS else 34.0
	var y_spacing: float = 28.0 if expanded_front else 24.0
	var company_centers: Array = _build_rect_grid_offsets(columns, rows, x_spacing, y_spacing, Vector2.ZERO)
	var slot_role: String = "front_shot" if company_type == SimTypes.CompanyType.MUSKETEERS else "pike_core"
	var element_offsets: Array = _get_infantry_visual_offsets(company_type, StringName(slot_role))
	for company_list_index in range(company_indices.size()):
		var company: CombatStand = companies[company_indices[company_list_index]]
		var company_center: Vector2 = position + right_axis * company_centers[company_list_index].x + front * company_centers[company_list_index].y
		result.append(_make_company_visual_entry(
			company,
			slot_role,
			_build_world_elements_from_offsets(element_offsets, company_center, front, right_axis)
		))
	return result


func _build_single_arm_infantry_column_visual_elements(company_indices: Array, company_type: int) -> Array:
	var result: Array = []
	if company_indices.is_empty():
		return result
	var front: Vector2 = front_direction.normalized()
	if front.length_squared() <= 0.001:
		front = Vector2.UP
	var right_axis: Vector2 = Vector2(-front.y, front.x).normalized()
	var company_offsets: Array = _build_front_to_rear_column_offsets(company_indices.size(), 38.0)
	var slot_role: StringName = &"column" if company_type == SimTypes.CompanyType.MUSKETEERS else &"column_core"
	var element_offsets: Array = _get_infantry_visual_offsets(company_type, slot_role)
	for company_list_index in range(company_indices.size()):
		var company: CombatStand = companies[company_indices[company_list_index]]
		var company_center: Vector2 = position + front * company_offsets[company_list_index]
		result.append(_make_company_visual_entry(
			company,
			String(slot_role),
			_build_world_elements_from_offsets(element_offsets, company_center, front, right_axis)
		))
	return result


func _build_single_arm_infantry_block_visual_elements(company_indices: Array, company_type: int) -> Array:
	var result: Array = []
	if company_indices.is_empty():
		return result
	var front: Vector2 = front_direction.normalized()
	if front.length_squared() <= 0.001:
		front = Vector2.UP
	var right_axis: Vector2 = Vector2(-front.y, front.x).normalized()
	var columns: int = int(ceil(sqrt(float(company_indices.size()))))
	var rows: int = int(ceil(float(company_indices.size()) / float(max(1, columns))))
	var company_centers: Array = _build_rect_grid_offsets(columns, rows, 34.0, 28.0, Vector2.ZERO)
	var slot_role: String = "inner_shot" if company_type == SimTypes.CompanyType.MUSKETEERS else "pike_core"
	var element_offsets: Array = _get_infantry_visual_offsets(company_type, StringName(slot_role))
	for company_list_index in range(company_indices.size()):
		var company: CombatStand = companies[company_indices[company_list_index]]
		var company_center: Vector2 = position + right_axis * company_centers[company_list_index].x + front * company_centers[company_list_index].y
		result.append(_make_company_visual_entry(
			company,
			slot_role,
			_build_world_elements_from_offsets(element_offsets, company_center, front, right_axis)
		))
	return result


func _build_pike_and_shot_regiment_visual_layout() -> Array:
	if is_countermarch_active():
		return _build_pike_and_shot_countermarch_visual_elements()
	match formation_state:
		SimTypes.RegimentFormationState.MARCH_COLUMN:
			return _build_pike_and_shot_column_visual_elements()
		SimTypes.RegimentFormationState.PROTECTED:
			return _build_pike_and_shot_protected_visual_elements()
		SimTypes.RegimentFormationState.MUSKETEER_LINE:
			return _build_pike_and_shot_musketeer_line_visual_elements()
		SimTypes.RegimentFormationState.TERCIA:
			return _build_pike_and_shot_tercia_visual_elements()
		_:
			return _build_pike_and_shot_line_visual_elements()


func _build_cavalry_regiment_visual_layout() -> Array:
	if is_caracole_active():
		return _build_cavalry_caracole_visual_elements()
	if formation.formation_type == SimTypes.FormationType.COLUMN:
		return _build_cavalry_column_visual_elements()
	return _build_cavalry_line_visual_elements()


func _build_artillery_regiment_visual_layout() -> Array:
	if formation.formation_type == SimTypes.FormationType.COLUMN:
		return _build_artillery_column_visual_elements()
	return _build_artillery_line_visual_elements()


func _build_pike_and_shot_line_visual_elements() -> Array:
	var result: Array = []
	var musket_indices: Array = _get_company_indices_by_type(SimTypes.CompanyType.MUSKETEERS)
	var pike_indices: Array = _get_company_indices_by_type(SimTypes.CompanyType.PIKEMEN)
	var front: Vector2 = front_direction.normalized()
	if front.length_squared() <= 0.001:
		front = Vector2.UP
	var right_axis: Vector2 = Vector2(-front.y, front.x).normalized()
	var center: Vector2 = position

	var total_pike_elements: int = pike_indices.size() * 4
	var pike_columns: int = 4 if total_pike_elements > 8 else 2
	var pike_rows: int = int(ceil(float(total_pike_elements) / float(max(1, pike_columns))))
	var pike_x_spacing: float = 20.0
	var pike_y_spacing: float = 14.0
	var pike_offsets: Array = _build_rect_grid_offsets(pike_columns, pike_rows, pike_x_spacing, pike_y_spacing, Vector2.ZERO)
	var pike_chunks: Array = _split_offsets_for_companies(pike_offsets, pike_indices.size())
	for pike_list_index in range(pike_indices.size()):
		var pike_company: CombatStand = companies[pike_indices[pike_list_index]]
		result.append(_make_company_visual_entry(
			pike_company,
			"pike_core",
			_build_world_elements_from_offsets(pike_chunks[pike_list_index], center, front, right_axis)
		))

	var left_musket_count: int = int(ceil(float(musket_indices.size()) * 0.5))
	var right_musket_count: int = max(0, musket_indices.size() - left_musket_count)
	var musket_company_columns: int = 2 if left_musket_count <= 1 and right_musket_count <= 1 else 4
	var musket_x_spacing: float = 16.0
	var musket_y_spacing: float = 16.0
	var pike_half_width: float = _get_grid_half_extent(pike_columns, pike_x_spacing, 9.0)
	var musket_half_width: float = _get_grid_half_extent(musket_company_columns, musket_x_spacing, 9.0)
	var flank_center_x: float = pike_half_width + musket_half_width + 18.0

	if left_musket_count > 0:
		var left_columns: int = 2 if left_musket_count <= 1 else 4
		var left_rows: int = int(ceil(float(left_musket_count * 4) / float(left_columns)))
		var left_offsets: Array = _build_rect_grid_offsets(left_columns, left_rows, musket_x_spacing, musket_y_spacing, Vector2(-flank_center_x, -5.0))
		var left_chunks: Array = _split_offsets_for_companies(left_offsets, left_musket_count)
		for left_index in range(left_musket_count):
			var left_company: CombatStand = companies[musket_indices[left_index]]
			result.append(_make_company_visual_entry(
				left_company,
				"left_shot",
				_build_world_elements_from_offsets(left_chunks[left_index], center, front, right_axis)
			))

	if right_musket_count > 0:
		var right_columns: int = 2 if right_musket_count <= 1 else 4
		var right_rows: int = int(ceil(float(right_musket_count * 4) / float(right_columns)))
		var right_offsets: Array = _build_rect_grid_offsets(right_columns, right_rows, musket_x_spacing, musket_y_spacing, Vector2(flank_center_x, -5.0))
		var right_chunks: Array = _split_offsets_for_companies(right_offsets, right_musket_count)
		for right_index in range(right_musket_count):
			var right_company: CombatStand = companies[musket_indices[left_musket_count + right_index]]
			result.append(_make_company_visual_entry(
				right_company,
				"right_shot",
				_build_world_elements_from_offsets(right_chunks[right_index], center, front, right_axis)
			))
	return result


func _build_cavalry_line_visual_elements() -> Array:
	var result: Array = []
	var front: Vector2 = front_direction.normalized()
	if front.length_squared() <= 0.001:
		front = Vector2.UP
	var right_axis: Vector2 = Vector2(-front.y, front.x).normalized()
	var company_offsets: Array = _build_rect_grid_offsets(companies.size(), 1, 26.0, 18.0, Vector2.ZERO)
	var cavalry_offsets: Array = [
		Vector2(0.0, -8.0),
		Vector2(0.0, 8.0),
	]
	for company_index in range(companies.size()):
		var company: CombatStand = companies[company_index]
		var center: Vector2 = position + right_axis * company_offsets[company_index].x + front * company_offsets[company_index].y
		result.append(_make_company_visual_entry(company, "cavalry_line", _build_world_elements_from_offsets(cavalry_offsets, center, front, right_axis)))
	return result


func _build_cavalry_column_visual_elements() -> Array:
	var result: Array = []
	var front: Vector2 = front_direction.normalized()
	if front.length_squared() <= 0.001:
		front = Vector2.UP
	var right_axis: Vector2 = Vector2(-front.y, front.x).normalized()
	var company_offsets: Array = _build_rect_grid_offsets(1, companies.size(), 20.0, 28.0, Vector2.ZERO)
	var cavalry_offsets: Array = [
		Vector2(-7.0, 0.0),
		Vector2(7.0, 0.0),
	]
	for company_index in range(companies.size()):
		var company: CombatStand = companies[company_index]
		var center: Vector2 = position + right_axis * company_offsets[company_index].x + front * company_offsets[company_index].y
		result.append(_make_company_visual_entry(company, "cavalry_column", _build_world_elements_from_offsets(cavalry_offsets, center, front, right_axis)))
	return result


func _build_cavalry_caracole_visual_elements() -> Array:
	var result: Array = []
	var front: Vector2 = front_direction.normalized()
	if front.length_squared() <= 0.001:
		front = Vector2.UP
	var right_axis: Vector2 = Vector2(-front.y, front.x).normalized()
	var cavalry_indices: Array = _get_company_indices_by_type(SimTypes.CompanyType.CAVALRY)
	if cavalry_indices.is_empty():
		return result
	var wave_size: int = _get_caracole_wave_size()
	var ordered_indices: Array = _rotate_indices(cavalry_indices, formation_cycle_index)
	var advanced_indices: Array = ordered_indices.slice(wave_size, ordered_indices.size())
	advanced_indices.append_array(ordered_indices.slice(0, wave_size))
	var start_offsets: Array = _build_front_to_rear_column_offsets(ordered_indices.size(), 28.0)
	var end_offsets: Array = _build_front_to_rear_column_offsets(advanced_indices.size(), 28.0)
	var cavalry_offsets: Array = [
		Vector2(-7.0, 0.0),
		Vector2(7.0, 0.0),
	]
	var flank_offset: float = -34.0
	var cycle_t: float = _get_caracole_phase_progress()
	var column_shift_weight: float = _get_caracole_column_shift_weight(cycle_t)
	var start_center_by_company: Dictionary = {}
	var end_center_by_company: Dictionary = {}
	for ordered_index in range(ordered_indices.size()):
		var company_index: int = ordered_indices[ordered_index]
		start_center_by_company[company_index] = position + front * start_offsets[ordered_index]
	for advanced_index in range(advanced_indices.size()):
		var company_index: int = advanced_indices[advanced_index]
		end_center_by_company[company_index] = position + front * end_offsets[advanced_index]
	for ordered_index in range(ordered_indices.size()):
		var company_index: int = ordered_indices[ordered_index]
		var company: CombatStand = companies[company_index]
		var start_center: Vector2 = start_center_by_company.get(company_index, position)
		var end_center: Vector2 = end_center_by_company.get(company_index, start_center)
		var center: Vector2 = start_center
		var slot_role: String = "cavalry_column"
		if ordered_index < wave_size:
			var front_lane_center: Vector2 = start_center + right_axis * flank_offset
			var rear_lane_center: Vector2 = end_center + right_axis * flank_offset
			slot_role = "caracole_front" if formation_cycle_phase == 0 else "caracole_reforming"
			match formation_cycle_phase:
				0:
					center = start_center
				1:
					center = start_center.lerp(front_lane_center, cycle_t)
				2:
					center = front_lane_center.lerp(rear_lane_center, cycle_t)
				_:
					center = rear_lane_center.lerp(end_center, cycle_t)
		else:
			center = start_center.lerp(end_center, column_shift_weight)
		result.append(_make_company_visual_entry(company, slot_role, _build_world_elements_from_offsets(cavalry_offsets, center, front, right_axis)))
	return result


func _build_artillery_line_visual_elements() -> Array:
	var result: Array = []
	var front: Vector2 = front_direction.normalized()
	if front.length_squared() <= 0.001:
		front = Vector2.UP
	var right_axis: Vector2 = Vector2(-front.y, front.x).normalized()
	var company_offsets: Array = _build_rect_grid_offsets(companies.size(), 1, 32.0, 22.0, Vector2.ZERO)
	for company_index in range(companies.size()):
		var company: CombatStand = companies[company_index]
		var center: Vector2 = position + right_axis * company_offsets[company_index].x + front * company_offsets[company_index].y
		result.append(_make_company_visual_entry(company, "battery_line", _build_artillery_company_elements(center, front, right_axis)))
	return result


func _build_artillery_column_visual_elements() -> Array:
	var result: Array = []
	var front: Vector2 = front_direction.normalized()
	if front.length_squared() <= 0.001:
		front = Vector2.UP
	var right_axis: Vector2 = Vector2(-front.y, front.x).normalized()
	var company_offsets: Array = _build_rect_grid_offsets(1, companies.size(), 20.0, 36.0, Vector2.ZERO)
	for company_index in range(companies.size()):
		var company: CombatStand = companies[company_index]
		var center: Vector2 = position + right_axis * company_offsets[company_index].x + front * company_offsets[company_index].y
		result.append(_make_company_visual_entry(company, "battery_column", _build_artillery_company_elements(center, front, right_axis)))
	return result


func _build_pike_and_shot_column_visual_elements() -> Array:
	var result: Array = []
	var musket_indices: Array = _get_company_indices_by_type(SimTypes.CompanyType.MUSKETEERS)
	var pike_indices: Array = _get_company_indices_by_type(SimTypes.CompanyType.PIKEMEN)
	var front: Vector2 = front_direction.normalized()
	if front.length_squared() <= 0.001:
		front = Vector2.UP
	var right_axis: Vector2 = Vector2(-front.y, front.x).normalized()
	var center: Vector2 = position

	var lead_guard_count: int = int(ceil(float(musket_indices.size()) * 0.5))
	var ordered_indices: Array = []
	var ordered_roles: Array = []
	for lead_index in range(lead_guard_count):
		ordered_indices.append(musket_indices[lead_index])
		ordered_roles.append("advance_guard")
	for pike_index in pike_indices:
		ordered_indices.append(pike_index)
		ordered_roles.append("column_core")
	for rear_index in range(lead_guard_count, musket_indices.size()):
		ordered_indices.append(musket_indices[rear_index])
		ordered_roles.append("rear_guard")

	var company_offsets: Array = _build_front_to_rear_column_offsets(ordered_indices.size(), 36.0)
	var element_offsets: Array = _build_rect_grid_offsets(2, 2, 12.0, 12.0, Vector2.ZERO)
	for ordered_index in range(ordered_indices.size()):
		var company: CombatStand = companies[ordered_indices[ordered_index]]
		var company_center: Vector2 = center + front * company_offsets[ordered_index]
		result.append(_make_company_visual_entry(
			company,
			ordered_roles[ordered_index],
			_build_world_elements_from_offsets(element_offsets, company_center, front, right_axis)
		))
	return result


func _build_pike_and_shot_musketeer_line_visual_elements() -> Array:
	var result: Array = []
	var musket_indices: Array = _get_company_indices_by_type(SimTypes.CompanyType.MUSKETEERS)
	var pike_indices: Array = _get_company_indices_by_type(SimTypes.CompanyType.PIKEMEN)
	var front: Vector2 = front_direction.normalized()
	if front.length_squared() <= 0.001:
		front = Vector2.UP
	var right_axis: Vector2 = Vector2(-front.y, front.x).normalized()
	var center: Vector2 = position

	var total_musket_elements: int = musket_indices.size() * 4
	var musket_columns: int = 4 if total_musket_elements <= 8 else 8
	var musket_rows: int = int(ceil(float(total_musket_elements) / float(max(1, musket_columns))))
	var musket_offsets: Array = _build_rect_grid_offsets(musket_columns, musket_rows, 18.0, 14.0, Vector2(0.0, 23.0))
	var total_pike_elements: int = pike_indices.size() * 4
	var pike_columns: int = 4 if total_pike_elements > 8 else 2
	var pike_rows: int = int(ceil(float(total_pike_elements) / float(max(1, pike_columns))))
	var pike_offsets: Array = _build_rect_grid_offsets(pike_columns, pike_rows, 20.0, 12.0, Vector2(0.0, -22.0))

	var musket_chunks: Array = _split_offsets_for_companies(musket_offsets, musket_indices.size())
	for musket_list_index in range(musket_indices.size()):
		var musket_company: CombatStand = companies[musket_indices[musket_list_index]]
		var musket_elements: Array = []
		for local_offset_value in musket_chunks[musket_list_index]:
			var local_offset: Vector2 = local_offset_value
			musket_elements.append({
				"position": center + right_axis * local_offset.x + front * local_offset.y,
				"front_direction": front,
			})
		result.append({
			"company_id": String(musket_company.id),
			"company_type": musket_company.company_type,
			"weapon_type": musket_company.weapon_type,
			"slot_role": "front_shot",
			"elements": musket_elements,
		})

	var pike_chunks: Array = _split_offsets_for_companies(pike_offsets, pike_indices.size())
	for pike_list_index in range(pike_indices.size()):
		var pike_company: CombatStand = companies[pike_indices[pike_list_index]]
		var pike_elements: Array = []
		for local_offset_value in pike_chunks[pike_list_index]:
			var local_offset: Vector2 = local_offset_value
			pike_elements.append({
				"position": center + right_axis * local_offset.x + front * local_offset.y,
				"front_direction": front,
			})
		result.append({
			"company_id": String(pike_company.id),
			"company_type": pike_company.company_type,
			"weapon_type": pike_company.weapon_type,
			"slot_role": "rear_pike",
			"elements": pike_elements,
		})
	return result


func _build_pike_and_shot_countermarch_visual_elements() -> Array:
	match formation_state:
		SimTypes.RegimentFormationState.TERCIA:
			return _build_tercia_countermarch_visual_elements()
		SimTypes.RegimentFormationState.MUSKETEER_LINE:
			return _build_musketeer_line_countermarch_visual_elements()
		_:
			return _build_line_countermarch_visual_elements()


func _build_line_countermarch_visual_elements() -> Array:
	var result: Array = []
	var musket_indices: Array = _get_company_indices_by_type(SimTypes.CompanyType.MUSKETEERS)
	var pike_indices: Array = _get_company_indices_by_type(SimTypes.CompanyType.PIKEMEN)
	var front: Vector2 = front_direction.normalized()
	if front.length_squared() <= 0.001:
		front = Vector2.UP
	var right_axis: Vector2 = Vector2(-front.y, front.x).normalized()
	var center: Vector2 = position
	var swap_rows: bool = bool(formation_cycle_index % 2)
	var fire_phase: bool = formation_cycle_phase == 0

	var total_pike_elements: int = pike_indices.size() * 4
	var pike_columns: int = 4 if total_pike_elements > 8 else 2
	var pike_rows: int = int(ceil(float(total_pike_elements) / float(max(1, pike_columns))))
	var pike_offsets: Array = _build_rect_grid_offsets(pike_columns, pike_rows, 20.0, 14.0, Vector2.ZERO)
	var pike_chunks: Array = _split_offsets_for_companies(pike_offsets, pike_indices.size())
	for pike_list_index in range(pike_indices.size()):
		var pike_company: CombatStand = companies[pike_indices[pike_list_index]]
		result.append(_make_company_visual_entry(
			pike_company,
			"pike_core",
			_build_world_elements_from_offsets(pike_chunks[pike_list_index], center, front, right_axis)
		))

	var left_musket_count: int = int(ceil(float(musket_indices.size()) * 0.5))
	var right_musket_count: int = max(0, musket_indices.size() - left_musket_count)
	var flank_center_x: float = 52.0 if pike_columns <= 2 else 68.0
	var left_rank_offsets: Array = _build_front_to_rear_column_offsets(left_musket_count, 24.0)
	for left_index in range(left_musket_count):
		var left_company: CombatStand = companies[musket_indices[left_index]]
		var left_center: Vector2 = center - right_axis * flank_center_x + front * left_rank_offsets[left_index]
		result.append(_make_company_visual_entry(
			left_company,
			"countermarch_shot",
			_build_countermarch_company_elements(left_center, front, right_axis, 16.0, 12.0, swap_rows, fire_phase)
		))

	var right_rank_offsets: Array = _build_front_to_rear_column_offsets(right_musket_count, 24.0)
	for right_index in range(right_musket_count):
		var right_company: CombatStand = companies[musket_indices[left_musket_count + right_index]]
		var right_center: Vector2 = center + right_axis * flank_center_x + front * right_rank_offsets[right_index]
		result.append(_make_company_visual_entry(
			right_company,
			"countermarch_shot",
			_build_countermarch_company_elements(right_center, front, right_axis, 16.0, 12.0, swap_rows, fire_phase)
		))
	return result


func _build_musketeer_line_countermarch_visual_elements() -> Array:
	var result: Array = []
	var musket_indices: Array = _get_company_indices_by_type(SimTypes.CompanyType.MUSKETEERS)
	var pike_indices: Array = _get_company_indices_by_type(SimTypes.CompanyType.PIKEMEN)
	var front: Vector2 = front_direction.normalized()
	if front.length_squared() <= 0.001:
		front = Vector2.UP
	var right_axis: Vector2 = Vector2(-front.y, front.x).normalized()
	var center: Vector2 = position
	var swap_rows: bool = bool(formation_cycle_index % 2)
	var fire_phase: bool = formation_cycle_phase == 0

	var total_pike_elements: int = pike_indices.size() * 4
	var pike_columns: int = 4 if total_pike_elements > 8 else 2
	var pike_rows: int = int(ceil(float(total_pike_elements) / float(max(1, pike_columns))))
	var pike_offsets: Array = _build_rect_grid_offsets(pike_columns, pike_rows, 20.0, 12.0, Vector2(0.0, -24.0))
	var pike_chunks: Array = _split_offsets_for_companies(pike_offsets, pike_indices.size())
	for pike_list_index in range(pike_indices.size()):
		var pike_company: CombatStand = companies[pike_indices[pike_list_index]]
		result.append(_make_company_visual_entry(
			pike_company,
			"rear_pike",
			_build_world_elements_from_offsets(pike_chunks[pike_list_index], center, front, right_axis)
		))

	var musket_company_offsets: Array = _build_rect_grid_offsets(min(4, max(1, musket_indices.size())), int(ceil(float(musket_indices.size()) / 4.0)), 26.0, 24.0, Vector2(0.0, 28.0))
	for musket_list_index in range(musket_indices.size()):
		var musket_company: CombatStand = companies[musket_indices[musket_list_index]]
		var company_offset: Vector2 = musket_company_offsets[musket_list_index]
		var company_center: Vector2 = center + right_axis * company_offset.x + front * company_offset.y
		result.append(_make_company_visual_entry(
			musket_company,
			"countermarch_shot",
			_build_countermarch_company_elements(company_center, front, right_axis, 16.0, 12.0, swap_rows, fire_phase)
		))
	return result


func _build_tercia_countermarch_visual_elements() -> Array:
	var base_entries: Array = _build_pike_and_shot_tercia_visual_elements()
	var result: Array = []
	var swap_rows: bool = bool(formation_cycle_index % 2)
	var fire_phase: bool = formation_cycle_phase == 0
	var entries_by_company: Dictionary = {}
	for entry_value in base_entries:
		var entry: Dictionary = entry_value
		entries_by_company[StringName(entry.get("company_id", ""))] = entry
	for company_value in companies:
		var company: CombatStand = company_value
		var base_entry: Dictionary = entries_by_company.get(company.id, {})
		if base_entry.is_empty():
			continue
		if company.company_type != SimTypes.CompanyType.MUSKETEERS:
			result.append(base_entry)
			continue
		result.append(_make_company_visual_entry(
			company,
			"countermarch_shot",
			_build_countermarch_elements_from_base_entry(base_entry, swap_rows, fire_phase)
		))
	return result


func _build_company_visual_element_positions(company: CombatStand, slot: FormationSlot = null) -> Array:
	var company_center: Vector2 = position + (slot.local_position if slot != null else company.local_position)
	var front: Vector2 = slot.facing_direction.normalized() if slot != null else company.front_direction.normalized()
	if front.length_squared() <= 0.001:
		front = front_direction.normalized()
	if front.length_squared() <= 0.001:
		front = Vector2.UP
	var slot_role: StringName = slot.role if slot != null else get_company_slot_role(company.id)
	return [{
		"position": company_center,
		"front_direction": front,
		"role": _resolve_runtime_visual_role(company, slot_role),
	}]


func _resolve_runtime_visual_role(company: CombatStand, base_role: StringName) -> StringName:
	if base_role != &"countermarch_shot":
		return base_role
	var front: Vector2 = front_direction.normalized() if front_direction.length_squared() > 0.001 else Vector2.UP
	var role_entries: Array = []
	for company_value in companies:
		var other: CombatStand = company_value
		var other_role: StringName = other.current_visual_role if other.current_visual_role != &"" else _get_base_slot_role_for_company(other)
		if other_role != &"countermarch_shot":
			continue
		role_entries.append({
			"id": other.id,
			"depth": other.local_position.dot(front),
		})
	if role_entries.is_empty():
		return &"countermarch_front"
	role_entries.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return float(left.get("depth", 0.0)) > float(right.get("depth", 0.0))
	)
	if bool(formation_cycle_index % 2):
		role_entries.reverse()
	var front_count: int = max(1, int(ceil(float(role_entries.size()) * 0.34)))
	var support_count: int = max(1, int(ceil(float(role_entries.size()) * 0.28)))
	for role_index in range(role_entries.size()):
		var entry: Dictionary = role_entries[role_index]
		if StringName(entry.get("id", &"")) != company.id:
			continue
		if role_index < front_count:
			return &"countermarch_front"
		if role_index < front_count + support_count:
			return &"countermarch_support"
		return &"countermarch_rear"
	return &"countermarch_front"


func _get_base_slot_role_for_company(company: CombatStand) -> StringName:
	for company_index in range(companies.size()):
		var candidate: CombatStand = companies[company_index]
		if candidate.id != company.id:
			continue
		if company_index < formation_slots.size():
			return formation_slots[company_index].role
		break
	return &""


func _get_infantry_visual_offsets(company_type: int, slot_role: StringName) -> Array:
	match slot_role:
		&"advance_guard", &"rear_guard", &"column", &"column_core":
			return [
				Vector2(0.0, -13.5),
				Vector2(0.0, -4.5),
				Vector2(0.0, 4.5),
				Vector2(0.0, 13.5),
			]
		&"front_shot", &"left_shot", &"right_shot", &"line", &"fire_line":
			return [
				Vector2(-16.5, 0.0),
				Vector2(-5.5, 0.0),
				Vector2(5.5, 0.0),
				Vector2(16.5, 0.0),
			]
		&"rear_pike":
			return [
				Vector2(-5.5, -7.0),
				Vector2(5.5, -7.0),
				Vector2(-5.5, 7.0),
				Vector2(5.5, 7.0),
			]
		&"outer_pike":
			return [
				Vector2(0.0, -16.5),
				Vector2(0.0, -5.5),
				Vector2(0.0, 5.5),
				Vector2(0.0, 16.5),
			]
		&"inner_shot":
			return [
				Vector2(-11.0, -5.5),
				Vector2(11.0, -5.5),
				Vector2(-11.0, 5.5),
				Vector2(11.0, 5.5),
			]
		_:
			if company_type == SimTypes.CompanyType.PIKEMEN:
				return [
					Vector2(-6.5, -8.0),
					Vector2(6.5, -8.0),
					Vector2(-6.5, 8.0),
					Vector2(6.5, 8.0),
				]
			return [
				Vector2(-7.5, -7.5),
				Vector2(7.5, -7.5),
				Vector2(-7.5, 7.5),
				Vector2(7.5, 7.5),
			]


func _get_cavalry_visual_offsets(slot_role: StringName) -> Array:
	if slot_role == &"cavalry_column" or slot_role == &"caracole_front":
		return [
			Vector2(-7.0, 0.0),
			Vector2(7.0, 0.0),
		]
	return [
		Vector2(0.0, -8.0),
		Vector2(0.0, 8.0),
	]


func _build_artillery_company_elements(center: Vector2, front: Vector2, right_axis: Vector2) -> Array:
	return [
		{
			"position": center + right_axis * 4.0,
			"front_direction": front,
			"role": &"gun",
		},
		{
			"position": center - right_axis * 6.0,
			"front_direction": front,
			"role": &"crew",
		},
	]


func _build_countermarch_company_elements(
		center: Vector2,
		front: Vector2,
		right_axis: Vector2,
		width: float,
		depth: float,
		swap_rows: bool,
		fire_phase: bool
) -> Array:
	var column_positions: Array = [-width * 0.5, width * 0.5]
	var front_rank_y: float = depth * 0.5
	var rear_rank_y: float = -depth * 0.5
	return _build_countermarch_musket_elements(center, front, right_axis, column_positions, front_rank_y, rear_rank_y, swap_rows, fire_phase)


func _build_countermarch_elements_from_base_entry(base_entry: Dictionary, swap_rows: bool, fire_phase: bool) -> Array:
	var base_elements: Array = base_entry.get("elements", [])
	if base_elements.is_empty():
		return []
	var center: Vector2 = _get_visual_elements_center(base_elements)
	var front: Vector2 = _get_dominant_front_direction(base_elements)
	if front.length_squared() <= 0.001:
		front = front_direction.normalized()
	if front.length_squared() <= 0.001:
		front = Vector2.UP
	var right_axis: Vector2 = Vector2(-front.y, front.x).normalized()
	var projected_width: float = 0.0
	var projected_depth: float = 0.0
	for element_value in base_elements:
		var element: Dictionary = element_value
		var local_offset: Vector2 = element.get("position", center) - center
		projected_width = max(projected_width, absf(local_offset.dot(right_axis)))
		projected_depth = max(projected_depth, absf(local_offset.dot(front)))
	var width: float = max(14.0, projected_width * 2.0)
	var depth: float = max(10.0, projected_depth * 2.0)
	return _build_countermarch_company_elements(center, front, right_axis, width, depth, swap_rows, fire_phase)


func _build_countermarch_musket_elements(
		center: Vector2,
		front: Vector2,
		right_axis: Vector2,
		column_positions: Array,
		front_rank_y: float,
		rear_rank_y: float,
		swap_rows: bool,
		fire_phase: bool
) -> Array:
	var result: Array = []
	var front_role: StringName = &"countermarch_front" if fire_phase else &"countermarch_support"
	var rear_role: StringName = &"countermarch_rear"
	if swap_rows:
		for column_x_value in column_positions:
			var column_x: float = float(column_x_value)
			result.append({
				"position": center + right_axis * column_x + front * rear_rank_y,
				"front_direction": front,
				"role": rear_role,
			})
		for column_x_value in column_positions:
			var column_x: float = float(column_x_value)
			result.append({
				"position": center + right_axis * column_x + front * front_rank_y,
				"front_direction": front,
				"role": front_role,
			})
		return result
	for column_x_value in column_positions:
		var column_x: float = float(column_x_value)
		result.append({
			"position": center + right_axis * column_x + front * front_rank_y,
			"front_direction": front,
			"role": front_role,
		})
	for column_x_value in column_positions:
		var column_x: float = float(column_x_value)
		result.append({
			"position": center + right_axis * column_x + front * rear_rank_y,
			"front_direction": front,
			"role": rear_role,
		})
	return result


func _build_pike_and_shot_protected_visual_elements() -> Array:
	var result: Array = []
	var musket_indices: Array = _get_company_indices_by_type(SimTypes.CompanyType.MUSKETEERS)
	var pike_indices: Array = _get_company_indices_by_type(SimTypes.CompanyType.PIKEMEN)
	var front: Vector2 = front_direction.normalized()
	if front.length_squared() <= 0.001:
		front = Vector2.UP
	var right_axis: Vector2 = Vector2(-front.y, front.x).normalized()
	var center: Vector2 = position

	var total_musket_elements: int = musket_indices.size() * 4
	var musket_columns: int = 4
	var musket_rows: int = int(ceil(float(total_musket_elements) / float(max(1, musket_columns))))
	var musket_offsets: Array = _build_rect_grid_offsets(musket_columns, musket_rows, 11.0, 16.0, Vector2.ZERO)
	var side_count: int = max(2, int((pike_indices.size() * 4) / 4))
	var pike_offsets: Array = []
	for local_offset_value in _build_rect_grid_offsets(side_count, 1, 16.0, 16.0, Vector2(0.0, -30.0)):
		pike_offsets.append({"offset": local_offset_value, "front": -front})
	for local_offset_value in _build_rect_grid_offsets(1, side_count, 16.0, 16.0, Vector2(-32.0, 0.0)):
		pike_offsets.append({"offset": local_offset_value, "front": -right_axis})
	for local_offset_value in _build_rect_grid_offsets(1, side_count, 16.0, 16.0, Vector2(32.0, 0.0)):
		pike_offsets.append({"offset": local_offset_value, "front": right_axis})
	for local_offset_value in _build_rect_grid_offsets(side_count, 1, 16.0, 16.0, Vector2(0.0, 30.0)):
		pike_offsets.append({"offset": local_offset_value, "front": front})

	var musket_chunks: Array = _split_offsets_for_companies(musket_offsets, musket_indices.size())
	for musket_list_index in range(musket_indices.size()):
		var company: CombatStand = companies[musket_indices[musket_list_index]]
		var elements: Array = []
		for local_offset_value in musket_chunks[musket_list_index]:
			var local_offset: Vector2 = local_offset_value
			elements.append({
				"position": center + right_axis * local_offset.x + front * local_offset.y,
				"front_direction": front,
			})
		result.append(_make_company_visual_entry(company, "inner_shot", elements))

	var pike_chunks: Array = _split_offsets_for_companies(pike_offsets, pike_indices.size())
	for pike_list_index in range(pike_indices.size()):
		var company: CombatStand = companies[pike_indices[pike_list_index]]
		var elements: Array = []
		for entry_value in pike_chunks[pike_list_index]:
			var pike_entry: Dictionary = entry_value
			var local_offset: Vector2 = pike_entry.get("offset", Vector2.ZERO)
			var element_front: Vector2 = pike_entry.get("front", front)
			elements.append({
				"position": center + right_axis * local_offset.x + front * local_offset.y,
				"front_direction": element_front,
			})
		result.append(_make_company_visual_entry(company, "outer_pike", elements))
	return result


func _build_pike_and_shot_tercia_visual_elements() -> Array:
	var musket_indices: Array = _get_company_indices_by_type(SimTypes.CompanyType.MUSKETEERS)
	var pike_indices: Array = _get_company_indices_by_type(SimTypes.CompanyType.PIKEMEN)
	if musket_indices.is_empty() or pike_indices.is_empty():
		return _build_pike_and_shot_line_visual_elements()
	if musket_indices.size() >= 3 or pike_indices.size() >= 3:
		return _build_full_tercia_visual_elements(musket_indices, pike_indices)
	return _build_compact_tercia_visual_elements(musket_indices, pike_indices)


func _build_full_tercia_visual_elements(musket_indices: Array, pike_indices: Array) -> Array:
	var result: Array = []
	var front: Vector2 = front_direction.normalized()
	if front.length_squared() <= 0.001:
		front = Vector2.UP
	var right_axis: Vector2 = Vector2(-front.y, front.x).normalized()
	var center: Vector2 = position

	var pike_company_columns: int = int(ceil(sqrt(float(max(1, pike_indices.size())))))
	var pike_company_rows: int = int(ceil(float(pike_indices.size()) / float(max(1, pike_company_columns))))
	var pike_company_centers: Array = _build_rect_grid_offsets(pike_company_columns, pike_company_rows, 32.0, 30.0, Vector2.ZERO)
	for pike_list_index in range(pike_indices.size()):
		var pike_company: CombatStand = companies[pike_indices[pike_list_index]]
		var pike_block_offsets: Array = _build_rect_grid_offsets(2, 2, 17.0, 15.0, pike_company_centers[pike_list_index])
		result.append(_make_company_visual_entry(
			pike_company,
			"tercia_pike",
			_build_world_elements_from_offsets(pike_block_offsets, center, front, right_axis)
		))

	var core_half_width: float = max(18.0, (float(pike_company_columns - 1) * 16.0) + 24.0)
	var core_half_depth: float = max(18.0, (float(pike_company_rows - 1) * 15.0) + 22.0)
	var sleeve_company_centers: Array = _build_tercia_sleeve_company_centers(
		musket_indices.size(),
		core_half_width + 24.0,
		core_half_depth + 20.0,
		28.0,
		28.0
	)
	for musket_list_index in range(musket_indices.size()):
		var musket_company: CombatStand = companies[musket_indices[musket_list_index]]
		var corner_offset: Vector2 = sleeve_company_centers[musket_list_index]
		var local_offsets: Array = _build_rect_grid_offsets(2, 2, 17.0, 17.0, corner_offset)
		result.append(_make_company_visual_entry(
			musket_company,
			"corner_shot",
			_build_world_elements_from_offsets(local_offsets, center, front, right_axis)
		))
	return result


func _build_compact_tercia_visual_elements(musket_indices: Array, pike_indices: Array) -> Array:
	var result: Array = []
	var front: Vector2 = front_direction.normalized()
	if front.length_squared() <= 0.001:
		front = Vector2.UP
	var right_axis: Vector2 = Vector2(-front.y, front.x).normalized()
	var center: Vector2 = position

	var front_pike_block: Array = _build_rect_grid_offsets(2, 2, 16.0, 14.0, Vector2(0.0, -10.0))
	var rear_pike_block: Array = _build_rect_grid_offsets(2, 2, 16.0, 14.0, Vector2(0.0, 10.0))
	if pike_indices.size() >= 1:
		result.append(_make_company_visual_entry(
			companies[pike_indices[0]],
			"tercia_pike",
			_build_world_elements_from_offsets(front_pike_block, center, front, right_axis)
		))
	if pike_indices.size() >= 2:
		result.append(_make_company_visual_entry(
			companies[pike_indices[1]],
			"tercia_pike",
			_build_world_elements_from_offsets(rear_pike_block, center, front, right_axis)
		))

	var front_corner_offsets: Array = []
	front_corner_offsets.append_array(_build_rect_grid_offsets(1, 2, 14.0, 14.0, Vector2(-36.0, 28.0)))
	front_corner_offsets.append_array(_build_rect_grid_offsets(1, 2, 14.0, 14.0, Vector2(36.0, 28.0)))
	if musket_indices.size() >= 1:
		result.append(_make_company_visual_entry(
			companies[musket_indices[0]],
			"corner_shot",
			_build_world_elements_from_offsets(front_corner_offsets, center, front, right_axis)
		))

	var rear_corner_offsets: Array = []
	rear_corner_offsets.append_array(_build_rect_grid_offsets(1, 2, 14.0, 14.0, Vector2(-36.0, -28.0)))
	rear_corner_offsets.append_array(_build_rect_grid_offsets(1, 2, 14.0, 14.0, Vector2(36.0, -28.0)))
	if musket_indices.size() >= 2:
		result.append(_make_company_visual_entry(
			companies[musket_indices[1]],
			"corner_shot",
			_build_world_elements_from_offsets(rear_corner_offsets, center, front, right_axis)
		))
	return result


func _build_tercia_sleeve_company_centers(count: int, half_width: float, half_depth: float, x_spacing: float, y_spacing: float) -> Array:
	var centers: Array = []
	if count <= 0:
		return centers
	var layer: int = 0
	while centers.size() < count:
		var layer_half_width: float = half_width + float(layer) * x_spacing * 1.2
		var layer_half_depth: float = half_depth + float(layer) * y_spacing * 1.2
		var layer_centers: Array = [
			Vector2(-layer_half_width, layer_half_depth),
			Vector2(layer_half_width, layer_half_depth),
			Vector2(-layer_half_width, -layer_half_depth),
			Vector2(layer_half_width, -layer_half_depth),
		]
		var front_slots: int = max(0, int(floor((layer_half_width * 2.0) / x_spacing)) - 1)
		for front_index in range(front_slots):
			var x: float = -layer_half_width + x_spacing * float(front_index + 1)
			layer_centers.append(Vector2(x, layer_half_depth))
		for rear_index in range(front_slots):
			var x: float = -layer_half_width + x_spacing * float(rear_index + 1)
			layer_centers.append(Vector2(x, -layer_half_depth))
		var side_slots: int = max(0, int(floor((layer_half_depth * 2.0) / y_spacing)) - 1)
		for left_index in range(side_slots):
			var y: float = -layer_half_depth + y_spacing * float(left_index + 1)
			layer_centers.append(Vector2(-layer_half_width, y))
		for right_index in range(side_slots):
			var y: float = -layer_half_depth + y_spacing * float(right_index + 1)
			layer_centers.append(Vector2(layer_half_width, y))
		for center_value in layer_centers:
			if centers.size() >= count:
				break
			centers.append(center_value)
		layer += 1
	return centers


func _make_company_visual_entry(company: CombatStand, slot_role: String, elements: Array) -> Dictionary:
	return {
		"company_id": String(company.id),
		"company_type": company.company_type,
		"weapon_type": company.weapon_type,
		"slot_role": slot_role,
		"elements": elements,
	}


func _initialize_company_visual_states(visual_entries: Array) -> void:
	var entries_by_company: Dictionary = {}
	for entry_value in visual_entries:
		var entry: Dictionary = entry_value
		entries_by_company[StringName(entry.get("company_id", ""))] = entry
	for company_value in companies:
		var company: CombatStand = company_value
		var company_entry: Dictionary = entries_by_company.get(company.id, {})
		if company_entry.is_empty():
			continue
		var local_elements: Array = _visual_elements_world_to_local(company_entry.get("elements", []))
		var slot_role: StringName = StringName(company_entry.get("slot_role", ""))
		company.initialize_visual_state(local_elements, slot_role)


func _build_visual_layout_from_slot_specs(slot_specs: Array) -> Array:
	var result: Array = []
	for company_index in range(companies.size()):
		var company: CombatStand = companies[company_index]
		var slot_spec: Dictionary = slot_specs[company_index] if company_index < slot_specs.size() else {}
		var slot_position: Vector2 = slot_spec.get("position", company.local_position)
		var slot_role: StringName = slot_spec.get("role", _get_runtime_slot_role(company_index))
		var slot_facing: Vector2 = slot_spec.get("facing", front_direction)
		var slot_tolerance: float = float(slot_spec.get("tolerance", max(10.0, min(formation.frontage, formation.depth) * 0.12)))
		var slot: FormationSlot = FormationSlot.new(
			StringName("%s_preview_slot_%02d" % [String(id), company_index]),
			slot_position,
			slot_facing,
			slot_role,
			slot_tolerance
		)
		result.append({
			"company_id": String(company.id),
			"company_type": company.company_type,
			"weapon_type": company.weapon_type,
			"slot_role": String(slot_role),
			"elements": _build_company_visual_element_positions(company, slot),
		})
	return result


func _visual_elements_world_to_local(elements: Array, additional_offset: Vector2 = Vector2.ZERO) -> Array:
	var result: Array = []
	for element_value in elements:
		var element: Dictionary = element_value
		result.append({
			"position": element.get("position", Vector2.ZERO) - position + additional_offset,
			"front_direction": element.get("front_direction", front_direction),
			"role": element.get("role", &""),
		})
	return result


func _build_slot_specs_from_visual_entries(visual_entries: Array) -> Array:
	var specs: Array = []
	for company_visual_value in visual_entries:
		var company_visual: Dictionary = company_visual_value
		var elements: Array = company_visual.get("elements", [])
		var center: Vector2 = _get_visual_elements_center(elements) - position
		var facing: Vector2 = _get_dominant_front_direction(elements)
		specs.append({
			"position": center,
			"facing": facing,
			"role": StringName(company_visual.get("slot_role", "line")),
			"tolerance": 6.0,
		})
	return specs


func _build_world_elements_from_offsets(offsets: Array, center: Vector2, front: Vector2, right_axis: Vector2) -> Array:
	var elements: Array = []
	for local_offset_value in offsets:
		var local_offset: Vector2 = local_offset_value
		elements.append({
			"position": center + right_axis * local_offset.x + front * local_offset.y,
			"front_direction": front,
		})
	return elements


func _get_visual_elements_center(elements: Array) -> Vector2:
	if elements.is_empty():
		return position
	var total: Vector2 = Vector2.ZERO
	for element_value in elements:
		var element: Dictionary = element_value
		total += element.get("position", Vector2.ZERO)
	return total / float(elements.size())


func _get_dominant_front_direction(elements: Array) -> Vector2:
	var total: Vector2 = Vector2.ZERO
	for element_value in elements:
		var element: Dictionary = element_value
		total += element.get("front_direction", Vector2.ZERO)
	if total.length_squared() <= 0.001:
		return front_direction.normalized() if front_direction.length_squared() > 0.001 else Vector2.UP
	return total.normalized()


func _build_rect_grid_offsets(columns: int, rows: int, x_spacing: float, y_spacing: float, center_offset: Vector2 = Vector2.ZERO) -> Array:
	var offsets: Array = []
	if columns <= 0 or rows <= 0:
		return offsets
	var half_width: float = float(columns - 1) * 0.5
	var half_height: float = float(rows - 1) * 0.5
	for row in range(rows):
		for column in range(columns):
			var local_x: float = (float(column) - half_width) * x_spacing + center_offset.x
			var local_y: float = (float(row) - half_height) * y_spacing + center_offset.y
			offsets.append(Vector2(local_x, local_y))
	return offsets


func _get_grid_half_extent(columns: int, spacing: float, element_half_extent: float = 0.0) -> float:
	if columns <= 0:
		return element_half_extent
	return float(columns - 1) * spacing * 0.5 + element_half_extent


func _split_offsets_for_companies(source: Array, company_count: int) -> Array:
	var result: Array = []
	for _index in range(max(1, company_count)):
		result.append([])
	if company_count <= 0:
		return result
	for source_index in range(source.size()):
		result[source_index % company_count].append(source[source_index])
	return result


func _rotate_indices(source: Array, front_index: int) -> Array:
	if source.is_empty():
		return []
	var rotated: Array = []
	var start_index: int = posmod(front_index, source.size())
	for index_offset in range(source.size()):
		rotated.append(source[(start_index + index_offset) % source.size()])
	return rotated


func _get_caracole_wave_size() -> int:
	if companies.is_empty():
		return 1
	return clamp(int(ceil(float(companies.size()) * 0.25)), 1, companies.size())


func _update_formation_cycle(delta: float) -> void:
	if not is_caracole_active() and not is_countermarch_active():
		formation_cycle_index = 0
		formation_cycle_elapsed = 0.0
		formation_cycle_phase = 0
		return
	formation_cycle_elapsed += delta
	var phase_duration: float = _get_formation_cycle_phase_duration()
	if formation_cycle_elapsed < phase_duration:
		return
	formation_cycle_elapsed = 0.0
	if is_countermarch_active():
		if formation_cycle_phase < 1:
			formation_cycle_phase += 1
			return
		formation_cycle_phase = 0
		formation_cycle_index = posmod(formation_cycle_index + 1, 2)
		return
	if formation_cycle_phase < 3:
		formation_cycle_phase += 1
		return
	formation_cycle_phase = 0
	formation_cycle_index = posmod(formation_cycle_index + _get_caracole_wave_size(), max(1, companies.size()))


func _get_formation_cycle_phase_duration() -> float:
	if is_countermarch_active():
		return 0.4 if formation_cycle_phase == 0 else 0.75
	match formation_cycle_phase:
		0:
			return 0.45
		1:
			return 0.22
		2:
			return 0.55
		_:
			return 0.24


func _get_caracole_phase_progress() -> float:
	var phase_duration: float = _get_formation_cycle_phase_duration()
	if phase_duration <= 0.001:
		return 1.0
	return clamp(formation_cycle_elapsed / phase_duration, 0.0, 1.0)


func _get_caracole_column_shift_weight(phase_progress: float) -> float:
	match formation_cycle_phase:
		0:
			return 0.0
		1:
			return phase_progress * 0.25
		2:
			return 0.25 + phase_progress * 0.5
		_:
			return 0.75 + phase_progress * 0.25


func _build_front_to_rear_column_offsets(count: int, spacing: float, shift: float = 0.0) -> Array:
	var offsets: Array = []
	if count <= 0:
		return offsets
	var front_offset: float = float(count - 1) * 0.5 * spacing + shift
	for index in range(count):
		offsets.append(front_offset - float(index) * spacing)
	return offsets


func _order_visual_entries_by_company(visual_entries: Array) -> Array:
	var entries_by_company: Dictionary = {}
	for entry_value in visual_entries:
		var entry: Dictionary = entry_value
		entries_by_company[StringName(entry.get("company_id", ""))] = entry
	var ordered_entries: Array = []
	for company_value in companies:
		var company: CombatStand = company_value
		if entries_by_company.has(company.id):
			ordered_entries.append(entries_by_company[company.id])
			entries_by_company.erase(company.id)
	for leftover_entry in entries_by_company.values():
		ordered_entries.append(leftover_entry)
	return ordered_entries


func _build_company_polygon_from_visual_elements(elements: Array) -> PackedVector2Array:
	var points: Array = []
	for element_value in elements:
		var element: Dictionary = element_value
		points.append(element.get("position", Vector2.ZERO))
	return _build_bounding_polygon_from_points(points, Vector2(11.0, 9.0))


func _build_bounding_polygon_from_points(points: Array, padding: Vector2) -> PackedVector2Array:
	if points.is_empty():
		return PackedVector2Array()
	var min_x: float = INF
	var min_y: float = INF
	var max_x: float = -INF
	var max_y: float = -INF
	for point_value in points:
		var world_point: Vector2 = point_value
		min_x = min(min_x, world_point.x)
		min_y = min(min_y, world_point.y)
		max_x = max(max_x, world_point.x)
		max_y = max(max_y, world_point.y)
	return PackedVector2Array([
		Vector2(min_x, min_y) - padding,
		Vector2(max_x, min_y) + Vector2(padding.x, -padding.y),
		Vector2(max_x, max_y) + padding,
		Vector2(min_x, max_y) + Vector2(-padding.x, padding.y),
	])
