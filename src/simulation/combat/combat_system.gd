class_name CombatSystem
extends RefCounted

const CombatTypes = preload("res://src/simulation/combat/combat_types.gd")

var last_tick_ms: float = 0.0
var last_frame_build_ms: float = 0.0
var last_contact_ms: float = 0.0
var last_fire_ms: float = 0.0
var last_charge_ms: float = 0.0
var last_melee_ms: float = 0.0
var last_apply_ms: float = 0.0
var last_company_frames: int = 0
var last_contact_edges: int = 0
var last_outcome_companies: int = 0
var last_small_arms_firers: int = 0
var last_small_arms_samples: int = 0
var last_small_arms_hits: int = 0
var last_small_arms_casualties: int = 0
var last_artillery_firers: int = 0
var last_artillery_hits: int = 0
var last_artillery_casualties: int = 0
var last_charge_impacts: int = 0
var last_charge_casualties: int = 0
var last_melee_edges: int = 0
var last_melee_casualties: int = 0
var last_active_regiments: int = 0
var _last_frame: Dictionary = CombatTypes.build_empty_frame(0.0, 0.0)

const SPRITE_CONTACT_CELL_SIZE: float = 96.0
const SMALL_ARMS_TARGET_CELL_SIZE: float = 180.0
const ACTIVE_REGIMENT_CELL_SIZE: float = 320.0
const ACTIVE_REGIMENT_STICKY_SECONDS: float = 2.5
const ACTIVE_REGIMENT_NEIGHBOR_RADIUS: int = 4
var _active_regiment_until: Dictionary = {}


func _resolve_small_arms_capacity(company: CombatStand, slot_role: StringName, order_mode: int, formation_type: int, formation_state: int) -> int:
	if formation_type == SimTypes.FormationType.COLUMN or formation_state == SimTypes.RegimentFormationState.MARCH_COLUMN:
		return 0
	var capacity: int = company.get_estimated_active_shooter_capacity(slot_role)
	if capacity <= 0:
		return 0
	var ratio_cap: float = 0.09
	match order_mode:
		CombatTypes.CombatOrderMode.VOLLEY:
			ratio_cap = 0.18
		CombatTypes.CombatOrderMode.COUNTERMARCH:
			ratio_cap = 0.14
		CombatTypes.CombatOrderMode.FIRE_AT_WILL:
			ratio_cap = 0.12
		_:
			ratio_cap = 0.0
	if ratio_cap <= 0.0:
		return 0
	return min(capacity, max(1, int(round(float(company.soldiers) * ratio_cap))))


func tick(sim, delta: float) -> void:
	var tick_start_us: int = Time.get_ticks_usec()
	var active_regiment_ids: Dictionary = _get_active_regiment_ids(sim)
	last_active_regiments = active_regiment_ids.size()
	_sync_live_combat_state(sim, delta, active_regiment_ids)

	var frame_start_us: int = Time.get_ticks_usec()
	var frame: Dictionary = _build_combat_frame(sim, delta, active_regiment_ids)
	last_frame_build_ms = float(Time.get_ticks_usec() - frame_start_us) / 1000.0

	var contact_start_us: int = Time.get_ticks_usec()
	frame["contact_candidates"] = _build_contact_candidates(frame.get("sprite_frames", []))
	last_contact_ms = float(Time.get_ticks_usec() - contact_start_us) / 1000.0

	var outcome_buffer: Dictionary = CombatTypes.build_empty_outcome_buffer()
	last_small_arms_firers = 0
	last_small_arms_samples = 0
	last_small_arms_hits = 0
	last_small_arms_casualties = 0
	last_artillery_firers = 0
	last_artillery_hits = 0
	last_artillery_casualties = 0
	last_charge_impacts = 0
	last_charge_casualties = 0
	last_melee_edges = 0
	last_melee_casualties = 0

	var fire_start_us: int = Time.get_ticks_usec()
	_resolve_small_arms(sim, frame, outcome_buffer)
	last_fire_ms = float(Time.get_ticks_usec() - fire_start_us) / 1000.0

	_resolve_artillery(sim, frame, outcome_buffer)

	var charge_start_us: int = Time.get_ticks_usec()
	_resolve_charge(frame, outcome_buffer)
	last_charge_ms = float(Time.get_ticks_usec() - charge_start_us) / 1000.0

	var melee_start_us: int = Time.get_ticks_usec()
	_resolve_melee(frame, outcome_buffer)
	last_melee_ms = float(Time.get_ticks_usec() - melee_start_us) / 1000.0

	var apply_start_us: int = Time.get_ticks_usec()
	_apply_outcomes(sim, outcome_buffer)
	last_apply_ms = float(Time.get_ticks_usec() - apply_start_us) / 1000.0

	last_company_frames = frame.get("company_frames", []).size()
	last_contact_edges = frame.get("contact_candidates", []).size()
	last_outcome_companies = int(outcome_buffer.get("companies", {}).size())
	_last_frame = frame
	last_tick_ms = float(Time.get_ticks_usec() - tick_start_us) / 1000.0


func get_last_frame() -> Dictionary:
	return _last_frame


func _sync_live_combat_state(sim, delta: float, active_regiment_ids: Dictionary) -> void:
	for regiment_value in sim.regiments.values():
		var regiment: Battalion = regiment_value
		if regiment.is_destroyed:
			continue
		if not active_regiment_ids.has(regiment.id):
			continue
		regiment.update_combat_intent(sim.time_seconds)
		for company_value in regiment.companies:
			var company: CombatStand = company_value
			company.tick_combat_state(delta)
		regiment.refresh_combat_aggregates()


func _build_combat_frame(sim, delta: float, active_regiment_ids: Dictionary) -> Dictionary:
	var frame: Dictionary = CombatTypes.build_empty_frame(sim.time_seconds, delta)
	var regiment_frames: Array = frame.get("regiment_frames", [])
	var company_frames: Array = frame.get("company_frames", [])
	var sprite_frames: Array = frame.get("sprite_frames", [])
	for regiment_value in sim.regiments.values():
		var regiment: Battalion = regiment_value
		if regiment.is_destroyed or not active_regiment_ids.has(regiment.id):
			continue
		regiment_frames.append(_build_regiment_frame(regiment, sim.time_seconds))
		for company_value in regiment.companies:
			var company: CombatStand = company_value
			var company_frame: Dictionary = _build_company_frame(sim, regiment, company)
			company_frames.append(company_frame)
			if _requires_close_combat_sprite_frames(company_frame):
				sprite_frames.append_array(_build_sprite_frames(company_frame))
	frame["regiment_frames"] = regiment_frames
	frame["company_frames"] = company_frames
	frame["sprite_frames"] = sprite_frames
	return frame


func _requires_close_combat_sprite_frames(company_frame: Dictionary) -> bool:
	var posture: int = int(company_frame.get("combat_posture", CombatTypes.CombatPosture.IDLE))
	if posture in [
		CombatTypes.CombatPosture.MELEE,
		CombatTypes.CombatPosture.CHARGE_WINDUP,
		CombatTypes.CombatPosture.CHARGE_COMMIT,
		CombatTypes.CombatPosture.CHARGE_RECOVER,
	]:
		return true
	var engagement_state: int = int(company_frame.get("engagement_state", SimTypes.EngagementState.NO_CONTACT))
	return engagement_state == SimTypes.EngagementState.ASSAULT


func _get_active_regiment_ids(sim) -> Dictionary:
	var active_ids: Dictionary = {}
	var broadphase: Dictionary = {}
	var processed_pairs: Dictionary = {}
	var current_time: float = float(sim.time_seconds)
	for regiment_value in sim.regiments.values():
		var regiment: Battalion = regiment_value
		if regiment.is_destroyed:
			continue
		if _is_regiment_force_active(regiment, current_time):
			active_ids[regiment.id] = true
			_active_regiment_until[regiment.id] = max(float(_active_regiment_until.get(regiment.id, -1.0)), current_time + ACTIVE_REGIMENT_STICKY_SECONDS)
		var cell_key: Vector2i = _get_broadphase_cell(regiment.position, ACTIVE_REGIMENT_CELL_SIZE)
		if not broadphase.has(cell_key):
			broadphase[cell_key] = []
		broadphase[cell_key].append(regiment)
	for cell_key_value in broadphase.keys():
		var cell_key: Vector2i = cell_key_value
		var bucket: Array = broadphase.get(cell_key, [])
		for offset_y in range(-ACTIVE_REGIMENT_NEIGHBOR_RADIUS, ACTIVE_REGIMENT_NEIGHBOR_RADIUS + 1):
			for offset_x in range(-ACTIVE_REGIMENT_NEIGHBOR_RADIUS, ACTIVE_REGIMENT_NEIGHBOR_RADIUS + 1):
				var other_key: Vector2i = Vector2i(cell_key.x + offset_x, cell_key.y + offset_y)
				if not broadphase.has(other_key):
					continue
				var other_bucket: Array = broadphase.get(other_key, [])
				for left_value in bucket:
					var left: Battalion = left_value
					for right_value in other_bucket:
						var right: Battalion = right_value
						if left == right or left.army_id == right.army_id:
							continue
						var left_id: String = String(left.id)
						var right_id: String = String(right.id)
						var pair_key: String = "%s__%s" % [left_id, right_id] if left_id < right_id else "%s__%s" % [right_id, left_id]
						if processed_pairs.has(pair_key):
							continue
						processed_pairs[pair_key] = true
						var activation_distance: float = _get_regiment_activation_distance(left, right)
						if left.position.distance_squared_to(right.position) > activation_distance * activation_distance:
							continue
						active_ids[left.id] = true
						active_ids[right.id] = true
						left.last_combat_tick_seen_enemy = current_time
						right.last_combat_tick_seen_enemy = current_time
						_active_regiment_until[left.id] = current_time + ACTIVE_REGIMENT_STICKY_SECONDS
						_active_regiment_until[right.id] = current_time + ACTIVE_REGIMENT_STICKY_SECONDS
	_prune_inactive_regiment_cache(current_time)
	for regiment_id_value in _active_regiment_until.keys():
		var regiment_id: StringName = regiment_id_value
		if float(_active_regiment_until.get(regiment_id, -1.0)) <= current_time:
			continue
		active_ids[regiment_id] = true
	return active_ids


func _is_regiment_force_active(regiment: Battalion, current_time: float) -> bool:
	if regiment.is_combat_locked(current_time):
		return true
	if regiment.is_charge_recovering(current_time) or regiment.is_charge_retreating(current_time):
		return true
	if regiment.is_engagement_state_active():
		return true
	if regiment.engagement_state == SimTypes.EngagementState.APPROACH \
			and regiment.engagement_target_regiment_id != &"" \
			and regiment.last_visible_enemy_distance <= max(regiment.get_attack_range() * 1.05, regiment.get_tactical_contact_distance() * 1.3):
		return true
	if _has_pending_company_state(regiment, current_time):
		return true
	return float(_active_regiment_until.get(regiment.id, -1.0)) > current_time


func _has_pending_company_state(regiment: Battalion, current_time: float) -> bool:
	for company_value in regiment.companies:
		var company: CombatStand = company_value
		if company.reload_state != CombatTypes.ReloadState.READY:
			return true
		if company.suppression > 0.025:
			return true
		if company.is_visual_fire_active(current_time):
			return true
	return false


func _get_regiment_activation_distance(left: Battalion, right: Battalion) -> float:
	var range_component: float = max(
		left.get_attack_range(),
		right.get_attack_range(),
		left.get_vision_range(),
		right.get_vision_range()
	)
	var contact_component: float = max(
		left.get_tactical_contact_distance(right),
		right.get_tactical_contact_distance(left)
	)
	var activation_distance: float = max(range_component * 1.05, contact_component + 120.0)
	if left.category == SimTypes.UnitCategory.ARTILLERY or right.category == SimTypes.UnitCategory.ARTILLERY:
		activation_distance += 180.0
	return clamp(activation_distance, 180.0, 1200.0)


func _prune_inactive_regiment_cache(current_time: float) -> void:
	var expired_ids: Array = []
	for regiment_id_value in _active_regiment_until.keys():
		var regiment_id: StringName = regiment_id_value
		if float(_active_regiment_until.get(regiment_id, -1.0)) > current_time:
			continue
		expired_ids.append(regiment_id)
	for regiment_id in expired_ids:
		_active_regiment_until.erase(regiment_id)


func _build_regiment_frame(regiment: Battalion, time_seconds: float) -> Dictionary:
	var front_direction: Vector2 = regiment.front_direction.normalized()
	if front_direction.length_squared() <= 0.001:
		front_direction = Vector2.UP
	var front_segment: Dictionary = {
		"center": regiment.position + front_direction * max(8.0, regiment.formation.depth * 0.25),
		"front_direction": front_direction,
		"width": regiment.formation.frontage,
	}
	return {
		"regiment_id": str(regiment.id),
		"army_id": str(regiment.army_id),
		"position": regiment.position,
		"front_direction": front_direction,
		"formation_type": regiment.formation.formation_type,
		"formation_state": regiment.formation_state,
		"morale": regiment.morale,
		"cohesion": regiment.cohesion,
		"fatigue": regiment.fatigue,
		"suppression": regiment.suppression,
		"engagement_state": regiment.engagement_state,
		"combat_posture": regiment.combat_posture,
		"combat_order_mode": regiment.combat_order_mode,
		"is_braced": regiment.is_braced(time_seconds),
		"is_reforming": regiment.is_reforming(time_seconds),
		"reform_exposure": regiment.get_reform_exposure(time_seconds),
		"regiment_front_segments": [front_segment],
		"company_ids": regiment.get_company_ids(),
	}


func _build_company_frame(sim, regiment: Battalion, company: CombatStand) -> Dictionary:
	var slot_role: StringName = regiment.get_company_slot_role(company.id)
	var active_shooter_capacity: int = _resolve_small_arms_capacity(
		company,
		slot_role,
		regiment.combat_order_mode,
		regiment.formation.formation_type,
		regiment.formation_state
	)
	var sprite_bodies: Array = regiment.get_company_sprite_bodies_world(company)
	var fallback_center: Vector2 = regiment.get_company_world_position(company)
	var fallback_front: Vector2 = regiment.get_company_world_front_direction(company).normalized()
	if fallback_front.length_squared() <= 0.001:
		fallback_front = regiment.front_direction.normalized()
	if fallback_front.length_squared() <= 0.001:
		fallback_front = Vector2.UP
	var body_geometry: Dictionary = _build_company_body_geometry(
		sprite_bodies,
		fallback_center,
		fallback_front,
		company.frontage_width,
		company.depth_density
	)
	var world_center: Vector2 = body_geometry.get("center", fallback_center)
	var front_direction: Vector2 = body_geometry.get("front_direction", fallback_front)
	var frontage_width: float = float(body_geometry.get("frontage_width", company.frontage_width))
	var depth_density: float = float(body_geometry.get("depth_density", company.depth_density))
	var body_depth: float = float(body_geometry.get("body_depth", max(6.0, company.depth_density * 8.0)))
	var combat_polygon: PackedVector2Array = body_geometry.get("polygon", PackedVector2Array())
	var frontage_center: Vector2 = body_geometry.get("frontage_center", world_center + front_direction * max(4.0, body_depth * 0.35))
	return {
		"company_id": str(company.id),
		"regiment_id": str(regiment.id),
		"engagement_target_regiment_id": str(regiment.engagement_target_regiment_id),
		"army_id": str(regiment.army_id),
		"combat_role": company.combat_role,
		"world_center": world_center,
		"front_direction": front_direction,
		"sprite_bodies": sprite_bodies,
		"combat_sprite_count": sprite_bodies.size(),
		"local_frontage_segment": {
			"center": frontage_center,
			"front_direction": front_direction,
			"width": frontage_width,
		},
		"combat_polygon": combat_polygon,
		"morale": company.morale,
		"cohesion": company.cohesion,
		"suppression": company.suppression,
		"ammo": company.ammo,
		"reload_state": company.reload_state,
		"reload_progress": company.reload_progress,
		"fire_cycle_duration": company.fire_cycle_duration,
		"reload_duration": company.reload_duration,
		"melee_reach": company.melee_reach,
		"frontage_width": frontage_width,
		"depth_density": depth_density,
		"body_depth": body_depth,
		"active_shooter_capacity": active_shooter_capacity,
		"active_melee_capacity": company.get_estimated_active_melee_capacity(slot_role),
		"brace_value": company.brace_value,
		"charge_bonus": company.charge_bonus,
		"charge_resistance": company.charge_resistance,
		"training": company.training,
		"max_range": company.get_max_range(),
		"effective_firepower": company.get_effective_firepower(),
		"soldiers": company.soldiers,
		"engagement_state": regiment.engagement_state,
		"combat_posture": regiment.combat_posture,
		"combat_order_mode": regiment.combat_order_mode,
		"regiment_is_braced": regiment.is_braced(sim.time_seconds),
		"is_reforming": regiment.is_reforming(sim.time_seconds),
		"reform_exposure": regiment.get_reform_exposure(sim.time_seconds),
		"charge_recovery_until": regiment.charge_recovery_until,
		"charge_retreat_until": regiment.charge_retreat_until,
		"charge_retreat_target_position": regiment.charge_retreat_target_position,
		"charge_stage_position": regiment.charge_stage_position,
		"charge_stage_valid": regiment.charge_stage_valid,
		"can_fire_small_arms": company.can_fire_small_arms(),
		"can_fire_artillery": company.can_fire_artillery(),
		"is_routed": company.is_routed,
		"slot_role": str(slot_role),
	}


func _build_company_body_geometry(
		sprite_bodies: Array,
		fallback_center: Vector2,
		fallback_front_direction: Vector2,
		fallback_frontage_width: float,
		fallback_depth_density: float
) -> Dictionary:
	if sprite_bodies.is_empty():
		return {
			"center": fallback_center,
			"front_direction": fallback_front_direction,
			"frontage_width": fallback_frontage_width,
			"depth_density": fallback_depth_density,
			"body_depth": max(6.0, fallback_depth_density * 8.0),
			"frontage_center": fallback_center + fallback_front_direction * max(4.0, fallback_depth_density * 4.0),
			"polygon": _build_company_frame_polygon(
				fallback_center,
				fallback_front_direction,
				fallback_frontage_width,
				fallback_depth_density
			),
		}
	var front_direction: Vector2 = _get_sprite_body_front_direction(sprite_bodies, fallback_front_direction)
	var right_axis: Vector2 = Vector2(-front_direction.y, front_direction.x).normalized()
	var centroid: Vector2 = _get_sprite_body_centroid(sprite_bodies, fallback_center)
	var min_lateral: float = INF
	var max_lateral: float = -INF
	var min_depth: float = INF
	var max_depth: float = -INF
	for sprite_value in sprite_bodies:
		var sprite_body: Dictionary = sprite_value
		var offset: Vector2 = sprite_body.get("position", centroid) - centroid
		var lateral: float = offset.dot(right_axis)
		var depth: float = offset.dot(front_direction)
		min_lateral = min(min_lateral, lateral)
		max_lateral = max(max_lateral, lateral)
		min_depth = min(min_depth, depth)
		max_depth = max(max_depth, depth)
	var center: Vector2 = centroid
	if min_lateral < INF and min_depth < INF:
		center = centroid + right_axis * ((min_lateral + max_lateral) * 0.5) + front_direction * ((min_depth + max_depth) * 0.5)
	var measured_frontage: float = max(10.0, (max_lateral - min_lateral) + 14.0)
	var measured_depth: float = max(10.0, (max_depth - min_depth) + 12.0)
	var frontage_width: float = max(fallback_frontage_width * 0.55, measured_frontage)
	var depth_density: float = max(fallback_depth_density * 0.7, measured_depth / 8.0)
	var body_depth: float = max(8.0, measured_depth)
	return {
		"center": center,
		"front_direction": front_direction,
		"frontage_width": frontage_width,
		"depth_density": depth_density,
		"body_depth": body_depth,
		"frontage_center": center + front_direction * max(4.0, body_depth * 0.35),
		"polygon": _build_company_frame_polygon(center, front_direction, frontage_width, depth_density),
	}


func _build_sprite_frames(company_frame: Dictionary) -> Array:
	var sprite_bodies: Array = company_frame.get("sprite_bodies", [])
	if sprite_bodies.is_empty():
		sprite_bodies = [{
			"position": company_frame.get("world_center", Vector2.ZERO),
			"front_direction": company_frame.get("front_direction", Vector2.UP),
		}]
	var center: Vector2 = company_frame.get("world_center", Vector2.ZERO)
	var front_direction: Vector2 = company_frame.get("front_direction", Vector2.UP).normalized()
	if front_direction.length_squared() <= 0.001:
		front_direction = Vector2.UP
	var right_axis: Vector2 = Vector2(-front_direction.y, front_direction.x).normalized()
	var sprite_count: int = sprite_bodies.size()
	var min_depth: float = INF
	var max_depth: float = -INF
	var min_lateral: float = INF
	var max_lateral: float = -INF
	var staged_frames: Array = []
	for sprite_index in range(sprite_bodies.size()):
		var sprite_body: Dictionary = sprite_bodies[sprite_index]
		var position: Vector2 = sprite_body.get("position", center)
		var front: Vector2 = sprite_body.get("front_direction", front_direction).normalized()
		if front.length_squared() <= 0.001:
			front = front_direction
		var offset: Vector2 = position - center
		var local_depth: float = offset.dot(front_direction)
		var local_lateral: float = offset.dot(right_axis)
		min_depth = min(min_depth, local_depth)
		max_depth = max(max_depth, local_depth)
		min_lateral = min(min_lateral, local_lateral)
		max_lateral = max(max_lateral, local_lateral)
		staged_frames.append({
			"sprite_id": "%s#%d" % [str(company_frame.get("company_id", "")), sprite_index],
			"sprite_index": sprite_index,
			"company_id": company_frame.get("company_id", ""),
			"regiment_id": company_frame.get("regiment_id", ""),
			"army_id": company_frame.get("army_id", ""),
			"combat_role": company_frame.get("combat_role", CombatTypes.CombatRole.MUSKET),
			"slot_role": company_frame.get("slot_role", ""),
			"position": position,
			"front_direction": front,
			"local_depth": local_depth,
			"local_lateral": local_lateral,
			"body_role": StringName(sprite_body.get("role", "")),
			"morale": company_frame.get("morale", 0.0),
			"cohesion": company_frame.get("cohesion", 0.0),
			"suppression": company_frame.get("suppression", 0.0),
			"training": company_frame.get("training", 0.0),
			"ammo": company_frame.get("ammo", 0.0),
			"max_range": company_frame.get("max_range", 0.0),
			"effective_firepower": company_frame.get("effective_firepower", 0.0),
			"soldiers": company_frame.get("soldiers", 0),
			"engagement_state": company_frame.get("engagement_state", SimTypes.EngagementState.NO_CONTACT),
			"combat_posture": company_frame.get("combat_posture", CombatTypes.CombatPosture.IDLE),
			"combat_order_mode": company_frame.get("combat_order_mode", CombatTypes.CombatOrderMode.NONE),
			"regiment_is_braced": company_frame.get("regiment_is_braced", false),
			"reform_exposure": company_frame.get("reform_exposure", 0.0),
			"charge_bonus": company_frame.get("charge_bonus", 0.0),
			"charge_resistance": company_frame.get("charge_resistance", 0.0),
			"brace_value": company_frame.get("brace_value", 0.0),
			"charge_recovery_until": company_frame.get("charge_recovery_until", -1.0),
			"is_routed": company_frame.get("is_routed", false),
		})
	var depth_span: float = max(1.0, max_depth - min_depth)
	var lateral_span: float = max(1.0, max_lateral - min_lateral)
	var fire_weight_total: float = 0.0
	var melee_weight_total: float = 0.0
	for sprite_index in range(staged_frames.size()):
		var sprite_frame: Dictionary = staged_frames[sprite_index]
		var depth_ratio: float = clamp((float(sprite_frame.get("local_depth", 0.0)) - min_depth) / depth_span, 0.0, 1.0)
		var lateral_extent: float = max(1.0, max(absf(min_lateral), absf(max_lateral)))
		var lateral_ratio: float = clamp(absf(float(sprite_frame.get("local_lateral", 0.0))) / lateral_extent, 0.0, 1.0)
		var dimensions: Dictionary = _estimate_sprite_dimensions(company_frame, sprite_count, StringName(sprite_frame.get("body_role", &"")))
		var fire_weight: float = _get_sprite_fire_weight(company_frame, sprite_frame, depth_ratio, lateral_ratio)
		var melee_weight: float = _get_sprite_melee_weight(company_frame, sprite_frame, depth_ratio, lateral_ratio)
		sprite_frame["depth_ratio"] = depth_ratio
		sprite_frame["lateral_ratio"] = lateral_ratio
		sprite_frame["width"] = float(dimensions.get("width", 10.0))
		sprite_frame["depth"] = float(dimensions.get("depth", 10.0))
		sprite_frame["fire_weight"] = fire_weight
		sprite_frame["melee_weight"] = melee_weight
		staged_frames[sprite_index] = sprite_frame
		fire_weight_total += fire_weight
		melee_weight_total += melee_weight
	var active_shooters: float = float(company_frame.get("active_shooter_capacity", 0))
	var active_melee: float = float(company_frame.get("active_melee_capacity", 0))
	var soldier_share: float = float(company_frame.get("soldiers", 0)) / float(max(1, sprite_count))
	for sprite_index in range(staged_frames.size()):
		var sprite_frame: Dictionary = staged_frames[sprite_index]
		var fire_weight: float = float(sprite_frame.get("fire_weight", 0.0))
		var melee_weight: float = float(sprite_frame.get("melee_weight", 0.0))
		sprite_frame["soldier_share"] = soldier_share
		sprite_frame["active_shooter_capacity"] = active_shooters * fire_weight / max(0.001, fire_weight_total) if fire_weight_total > 0.0 else 0.0
		sprite_frame["active_melee_capacity"] = active_melee * melee_weight / max(0.001, melee_weight_total) if melee_weight_total > 0.0 else 0.0
		staged_frames[sprite_index] = sprite_frame
	return staged_frames


func _estimate_sprite_dimensions(company_frame: Dictionary, sprite_count: int, body_role: StringName) -> Dictionary:
	var combat_role: int = int(company_frame.get("combat_role", CombatTypes.CombatRole.MUSKET))
	var company_width: float = max(10.0, float(company_frame.get("frontage_width", 10.0)))
	var company_depth: float = max(10.0, float(company_frame.get("body_depth", max(8.0, float(company_frame.get("depth_density", 1.0)) * 8.0))))
	var width: float = company_width / float(max(1, min(sprite_count, 4)))
	var depth: float = company_depth / float(max(1, int(ceil(float(sprite_count) * 0.5))))
	match combat_role:
		CombatTypes.CombatRole.CAVALRY:
			width = max(10.5, company_width / float(max(1, sprite_count)) * 1.1)
			depth = max(10.0, company_depth * 0.9)
		CombatTypes.CombatRole.ARTILLERY:
			width = max(11.0, company_width * 0.52)
			depth = max(9.0, company_depth * 0.85)
		CombatTypes.CombatRole.PIKE:
			width = max(8.0, width * 0.92)
			depth = max(10.0, depth * 1.08)
		_:
			width = max(8.5, width)
			depth = max(8.0, depth)
	match body_role:
		&"column", &"column_core", &"advance_guard", &"rear_guard", &"cavalry_column", &"battery_column":
			width *= 0.78
			depth *= 1.2
		&"front_shot", &"left_shot", &"right_shot", &"fire_line", &"countermarch_front":
			width *= 1.08
			depth *= 0.82
		&"outer_pike", &"tercia_pike":
			width *= 0.9
			depth *= 1.16
	return {
		"width": width,
		"depth": depth,
	}


func _get_sprite_fire_weight(company_frame: Dictionary, sprite_frame: Dictionary, depth_ratio: float, lateral_ratio: float) -> float:
	if int(company_frame.get("combat_role", CombatTypes.CombatRole.MUSKET)) != CombatTypes.CombatRole.MUSKET:
		return 0.0
	var body_role: StringName = StringName(sprite_frame.get("body_role", &""))
	match body_role:
		&"countermarch_front":
			return 1.15
		&"countermarch_support":
			return 0.78
		&"countermarch_rear":
			return 0.18
	var slot_role: String = str(company_frame.get("slot_role", ""))
	var weight: float = 0.2 + depth_ratio * 0.85
	if slot_role in ["front_shot", "fire_line"]:
		weight += 0.32 * depth_ratio
	elif slot_role in ["left_shot", "right_shot"]:
		weight += 0.14 + lateral_ratio * 0.1
	elif slot_role in ["inner_shot", "countermarch_shot"]:
		weight += 0.08
	elif slot_role == "corner_shot":
		weight += 0.18 * lateral_ratio
	return clamp(weight, 0.0, 1.35)


func _get_sprite_melee_weight(company_frame: Dictionary, sprite_frame: Dictionary, depth_ratio: float, lateral_ratio: float) -> float:
	var combat_role: int = int(company_frame.get("combat_role", CombatTypes.CombatRole.MUSKET))
	var body_role: StringName = StringName(sprite_frame.get("body_role", &""))
	var weight: float = 0.55
	match combat_role:
		CombatTypes.CombatRole.PIKE:
			weight = 0.82 + depth_ratio * 0.22
			if body_role in [&"outer_pike", &"tercia_pike"]:
				weight += 0.12
		CombatTypes.CombatRole.CAVALRY:
			weight = 0.88 + depth_ratio * 0.12
		CombatTypes.CombatRole.ARTILLERY:
			weight = 0.24
		_:
			weight = 0.46 + depth_ratio * 0.26
	if lateral_ratio > 0.75:
		weight *= 0.94
	return clamp(weight, 0.08, 1.25)


func _get_sprite_body_centroid(sprite_bodies: Array, fallback_center: Vector2) -> Vector2:
	if sprite_bodies.is_empty():
		return fallback_center
	var total: Vector2 = Vector2.ZERO
	for sprite_value in sprite_bodies:
		var sprite_body: Dictionary = sprite_value
		total += sprite_body.get("position", fallback_center)
	return total / float(sprite_bodies.size())


func _get_sprite_body_front_direction(sprite_bodies: Array, fallback_front_direction: Vector2) -> Vector2:
	var total_front: Vector2 = Vector2.ZERO
	for sprite_value in sprite_bodies:
		var sprite_body: Dictionary = sprite_value
		total_front += sprite_body.get("front_direction", Vector2.ZERO)
	if total_front.length_squared() > 0.001:
		return total_front.normalized()
	return fallback_front_direction


func _build_company_frame_polygon(center: Vector2, front_direction: Vector2, frontage_width: float, depth_density: float) -> PackedVector2Array:
	var front: Vector2 = front_direction.normalized()
	if front.length_squared() <= 0.001:
		front = Vector2.UP
	var right_axis: Vector2 = Vector2(-front.y, front.x).normalized()
	var half_width: float = max(6.0, frontage_width * 0.5)
	var half_depth: float = max(6.0, depth_density * 8.0)
	return PackedVector2Array([
		center - right_axis * half_width - front * half_depth,
		center + right_axis * half_width - front * half_depth,
		center + right_axis * half_width + front * half_depth,
		center - right_axis * half_width + front * half_depth,
	])


func _get_broadphase_cell(position: Vector2, cell_size: float) -> Vector2i:
	return Vector2i(
		int(floor(position.x / cell_size)),
		int(floor(position.y / cell_size))
	)


func _build_contact_candidates(sprite_frames: Array) -> Array:
	var contacts: Array = []
	if sprite_frames.is_empty():
		return contacts
	var broadphase: Dictionary = {}
	for sprite_frame_value in sprite_frames:
		var sprite_frame: Dictionary = sprite_frame_value
		if not _is_sprite_contact_candidate(sprite_frame):
			continue
		var position: Vector2 = sprite_frame.get("position", Vector2.ZERO)
		var cell: Vector2i = _get_broadphase_cell(position, SPRITE_CONTACT_CELL_SIZE)
		if not broadphase.has(cell):
			broadphase[cell] = []
		broadphase[cell].append(sprite_frame)
	if broadphase.is_empty():
		return contacts
	var processed_pairs: Dictionary = {}
	for cell_key_value in broadphase.keys():
		var cell_key: Vector2i = cell_key_value
		var bucket: Array = broadphase.get(cell_key, [])
		for offset_y in range(-1, 2):
			for offset_x in range(-1, 2):
				var other_key: Vector2i = Vector2i(cell_key.x + offset_x, cell_key.y + offset_y)
				if not broadphase.has(other_key):
					continue
				var other_bucket: Array = broadphase.get(other_key, [])
				for left_value in bucket:
					var left_frame: Dictionary = left_value
					for right_value in other_bucket:
						var right_frame: Dictionary = right_value
						if left_frame.get("army_id", "") == right_frame.get("army_id", ""):
							continue
						var left_sprite_id: String = str(left_frame.get("sprite_id", ""))
						var right_sprite_id: String = str(right_frame.get("sprite_id", ""))
						if left_sprite_id == right_sprite_id:
							continue
						var pair_key: String = "%s__%s" % [left_sprite_id, right_sprite_id] if left_sprite_id < right_sprite_id else "%s__%s" % [right_sprite_id, left_sprite_id]
						if processed_pairs.has(pair_key):
							continue
						processed_pairs[pair_key] = true
						var contact: Dictionary = _build_sprite_contact(left_frame, right_frame)
						if contact.is_empty():
							continue
						contacts.append(contact)
	return contacts


func _is_sprite_contact_candidate(sprite_frame: Dictionary) -> bool:
	var posture: int = int(sprite_frame.get("combat_posture", CombatTypes.CombatPosture.IDLE))
	if posture in [
		CombatTypes.CombatPosture.MELEE,
		CombatTypes.CombatPosture.CHARGE_WINDUP,
		CombatTypes.CombatPosture.CHARGE_COMMIT,
		CombatTypes.CombatPosture.CHARGE_RECOVER,
	]:
		return true
	var engagement_state: int = int(sprite_frame.get("engagement_state", SimTypes.EngagementState.NO_CONTACT))
	if engagement_state == SimTypes.EngagementState.ASSAULT:
		return float(sprite_frame.get("active_melee_capacity", 0.0)) > 0.0
	return false


func _build_sprite_contact(left_frame: Dictionary, right_frame: Dictionary) -> Dictionary:
	var left_center: Vector2 = left_frame.get("position", Vector2.ZERO)
	var right_center: Vector2 = right_frame.get("position", Vector2.ZERO)
	var offset: Vector2 = right_center - left_center
	var distance: float = offset.length()
	var left_width: float = float(left_frame.get("width", 10.0))
	var right_width: float = float(right_frame.get("width", 10.0))
	var left_depth: float = float(left_frame.get("depth", 10.0))
	var right_depth: float = float(right_frame.get("depth", 10.0))
	var max_contact_distance: float = max(12.0, (left_width + right_width) * 0.46 + (left_depth + right_depth) * 0.34)
	if distance > max_contact_distance:
		return {}
	var overlap_ratio: float = clamp(1.0 - distance / max(1.0, max_contact_distance), 0.0, 1.0)
	var shared_frontage_length: float = min(left_width, right_width) * overlap_ratio
	if shared_frontage_length <= 0.4:
		return {}
	var left_to_right: Vector2 = offset.normalized() if distance > 0.001 else Vector2.RIGHT
	var right_to_left: Vector2 = -left_to_right
	return {
		"edge_id": "%s__%s" % [left_frame.get("sprite_id", ""), right_frame.get("sprite_id", "")],
		"left_sprite_id": left_frame.get("sprite_id", ""),
		"right_sprite_id": right_frame.get("sprite_id", ""),
		"left_company_id": left_frame.get("company_id", ""),
		"right_company_id": right_frame.get("company_id", ""),
		"left_regiment_id": left_frame.get("regiment_id", ""),
		"right_regiment_id": right_frame.get("regiment_id", ""),
		"contact_side_left": _resolve_contact_side(left_frame.get("front_direction", Vector2.RIGHT), left_to_right),
		"contact_side_right": _resolve_contact_side(right_frame.get("front_direction", Vector2.LEFT), right_to_left),
		"shared_contact_line": [left_center.lerp(right_center, 0.5)],
		"shared_frontage_length": shared_frontage_length,
		"distance_along_front": distance,
		"is_charge_impact_candidate": int(left_frame.get("combat_role", -1)) == CombatTypes.CombatRole.CAVALRY \
			or int(right_frame.get("combat_role", -1)) == CombatTypes.CombatRole.CAVALRY,
		"is_melee_candidate": true,
		"is_fire_lane_candidate": false,
	}


func _resolve_contact_side(front_direction: Vector2, direction_to_enemy: Vector2) -> int:
	var front: Vector2 = front_direction.normalized()
	if front.length_squared() <= 0.001:
		front = Vector2.UP
	var right_axis: Vector2 = Vector2(-front.y, front.x).normalized()
	var dot_front: float = front.dot(direction_to_enemy)
	if dot_front >= 0.45:
		return CombatTypes.ContactSide.FRONT
	if dot_front <= -0.45:
		return CombatTypes.ContactSide.REAR
	return CombatTypes.ContactSide.RIGHT_FLANK if right_axis.dot(direction_to_enemy) >= 0.0 else CombatTypes.ContactSide.LEFT_FLANK


func _resolve_small_arms(sim, frame: Dictionary, outcome_buffer: Dictionary) -> void:
	var company_frames: Array = frame.get("company_frames", [])
	if company_frames.is_empty():
		return
	var company_frames_by_id: Dictionary = {}
	var company_frames_by_regiment: Dictionary = {}
	var target_broadphase: Dictionary = {}
	var sorted_company_ids: Array = []
	var visibility_cache: Dictionary = {}
	for company_frame_value in company_frames:
		var company_frame: Dictionary = company_frame_value
		var company_id: String = str(company_frame.get("company_id", ""))
		company_frames_by_id[company_id] = company_frame
		var regiment_id: String = str(company_frame.get("regiment_id", ""))
		if not company_frames_by_regiment.has(regiment_id):
			company_frames_by_regiment[regiment_id] = []
		company_frames_by_regiment[regiment_id].append(company_frame)
		var cell: Vector2i = _get_broadphase_cell(company_frame.get("world_center", Vector2.ZERO), SMALL_ARMS_TARGET_CELL_SIZE)
		if not target_broadphase.has(cell):
			target_broadphase[cell] = []
		target_broadphase[cell].append(company_frame)
		sorted_company_ids.append(company_id)
	sorted_company_ids.sort()

	for company_id_value in sorted_company_ids:
		var shooter_frame: Dictionary = company_frames_by_id.get(company_id_value, {})
		if shooter_frame.is_empty():
			continue
		if int(shooter_frame.get("combat_role", -1)) != CombatTypes.CombatRole.MUSKET:
			continue
		var shooter_order_mode: int = int(shooter_frame.get("combat_order_mode", CombatTypes.CombatOrderMode.NONE))
		if not [
			CombatTypes.CombatOrderMode.VOLLEY,
			CombatTypes.CombatOrderMode.COUNTERMARCH,
			CombatTypes.CombatOrderMode.FIRE_AT_WILL,
		].has(shooter_order_mode):
			continue
		if not bool(shooter_frame.get("can_fire_small_arms", false)):
			continue
		if bool(shooter_frame.get("is_routed", false)):
			continue
		var active_shooters: int = int(shooter_frame.get("active_shooter_capacity", 0))
		if active_shooters <= 0:
			continue
		var shooter_entry: Dictionary = _get_or_create_company_outcome(outcome_buffer, company_id_value)
		var shooter_regiment_entry: Dictionary = _get_or_create_regiment_outcome(outcome_buffer, str(shooter_frame.get("regiment_id", "")))
		var shooter_sprite: Dictionary = _build_representative_shooter_sprite(shooter_frame)
		var target_solution: Dictionary = _select_small_arms_target_company(
			sim,
			shooter_frame,
			shooter_sprite,
			company_frames_by_regiment,
			target_broadphase,
			visibility_cache
		)
		if target_solution.is_empty():
			continue
		var target_frame: Dictionary = target_solution.get("frame", {})
		var target_sprite: Dictionary = target_solution.get("sprite", {})
		if target_frame.is_empty() or target_sprite.is_empty():
			continue
		var distance: float = float(target_solution.get("distance", 0.0))
		var visibility: float = float(target_solution.get("visibility", 0.0))
		var sample_count: int = int(clamp(int(ceil(float(active_shooters) / 6.0)), 1, 14))
		var final_accuracy: float = _compute_small_arms_accuracy(
			shooter_frame,
			shooter_sprite,
			target_frame,
			target_sprite,
			distance,
			visibility
		)
		if final_accuracy <= 0.01:
			continue
		var casualty_count: int = 0
		var hit_count: int = 0
		for sample_index in range(sample_count):
			var sample_key: String = "%s|%s|%s|%d" % [
				str(frame.get("time_seconds", 0.0)),
				str(shooter_frame.get("company_id", "")),
				str(target_frame.get("company_id", "")),
				sample_index,
			]
			var roll: float = _stable_noise_from_key(sample_key)
			if roll > final_accuracy:
				continue
			hit_count += 1
			var casualty_roll: float = _stable_noise_from_key("%s|casualty" % sample_key)
			var casualty_amount: int = 2 if casualty_roll < 0.12 else 1
			casualty_count += casualty_amount
		if casualty_count <= 0 and final_accuracy < 0.1:
			continue
		var target_company_id: String = str(target_frame.get("company_id", ""))
		var target_entry: Dictionary = _get_or_create_company_outcome(outcome_buffer, target_company_id)
		var target_regiment_entry: Dictionary = _get_or_create_regiment_outcome(outcome_buffer, str(target_frame.get("regiment_id", "")))
		var target_soldiers: int = max(0, int(target_frame.get("soldiers", 0)) - int(target_entry.get("casualties", 0)))
		var applied_casualties: int = min(target_soldiers, casualty_count)
		var suppression_delta: float = clamp(float(hit_count) * 0.018 + float(sample_count) * 0.0032, 0.0, 0.16)
		target_entry["casualties"] = int(target_entry.get("casualties", 0)) + applied_casualties
		target_entry["morale_delta"] = float(target_entry.get("morale_delta", 0.0)) - float(applied_casualties) * 0.0028 - suppression_delta * 0.18
		target_entry["cohesion_delta"] = float(target_entry.get("cohesion_delta", 0.0)) - float(applied_casualties) * 0.0024 - suppression_delta * 0.22
		target_entry["suppression_delta"] = float(target_entry.get("suppression_delta", 0.0)) + suppression_delta
		target_regiment_entry["morale_delta"] = float(target_regiment_entry.get("morale_delta", 0.0)) - float(applied_casualties) * 0.0011
		target_regiment_entry["cohesion_delta"] = float(target_regiment_entry.get("cohesion_delta", 0.0)) - suppression_delta * 0.08
		var ammo_delta: float = -float(active_shooters) / float(max(1, int(shooter_frame.get("soldiers", 1))) * 24)
		shooter_entry["ammo_delta"] = float(shooter_entry.get("ammo_delta", 0.0)) + ammo_delta
		shooter_entry["reload_state_override"] = CombatTypes.ReloadState.FIRING
		shooter_entry["reload_progress_override"] = 0.0
		shooter_regiment_entry["forced_posture"] = CombatTypes.CombatPosture.FIRING
		last_small_arms_firers += 1
		last_small_arms_samples += sample_count
		last_small_arms_hits += hit_count
		last_small_arms_casualties += applied_casualties
		if applied_casualties >= 4:
			_append_event(outcome_buffer, "%s volleyed %s." % [
				str(shooter_frame.get("company_id", "")),
				target_company_id,
			])


func _resolve_artillery(sim, frame: Dictionary, outcome_buffer: Dictionary) -> void:
	var artillery_frames: Array = []
	var company_frames: Array = frame.get("company_frames", [])
	var sprite_frames: Array = frame.get("sprite_frames", [])
	var company_frames_by_id: Dictionary = {}
	for company_frame_value in company_frames:
		var company_frame: Dictionary = company_frame_value
		company_frames_by_id[str(company_frame.get("company_id", ""))] = company_frame
		if int(company_frame.get("combat_role", -1)) != CombatTypes.CombatRole.ARTILLERY:
			continue
		var artillery_order_mode: int = int(company_frame.get("combat_order_mode", CombatTypes.CombatOrderMode.NONE))
		if not [
			CombatTypes.CombatOrderMode.VOLLEY,
			CombatTypes.CombatOrderMode.FIRE_AT_WILL,
		].has(artillery_order_mode):
			continue
		if not bool(company_frame.get("can_fire_artillery", false)):
			continue
		if bool(company_frame.get("is_routed", false)):
			continue
		artillery_frames.append(company_frame)
	artillery_frames.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("company_id", "")) < str(b.get("company_id", ""))
	)
	for shooter_frame_value in artillery_frames:
		var shooter_frame: Dictionary = shooter_frame_value
		var target_frame: Dictionary = _select_artillery_target(sim, shooter_frame, company_frames)
		if target_frame.is_empty():
			continue
		var target_distance: float = shooter_frame.get("world_center", Vector2.ZERO).distance_to(target_frame.get("world_center", Vector2.ZERO))
		var visibility: float = sim.visibility_between(
			shooter_frame.get("world_center", Vector2.ZERO),
			target_frame.get("world_center", Vector2.ZERO)
		)
		if visibility < 0.05:
			continue
		var aim_solution: Dictionary = _build_artillery_aim_solution(frame, shooter_frame, target_frame, target_distance, visibility)
		var corridor_hits: Array = _collect_artillery_corridor_hits(shooter_frame, sprite_frames, company_frames_by_id, aim_solution)
		if corridor_hits.is_empty():
			continue

		var shooter_company_id: String = str(shooter_frame.get("company_id", ""))
		var shooter_entry: Dictionary = _get_or_create_company_outcome(outcome_buffer, shooter_company_id)
		var shooter_regiment_entry: Dictionary = _get_or_create_regiment_outcome(outcome_buffer, str(shooter_frame.get("regiment_id", "")))
		shooter_entry["ammo_delta"] = float(shooter_entry.get("ammo_delta", 0.0)) - 0.025
		shooter_entry["reload_state_override"] = CombatTypes.ReloadState.FIRING
		shooter_entry["reload_progress_override"] = 0.0
		shooter_regiment_entry["forced_posture"] = CombatTypes.CombatPosture.FIRING

		var projectile_energy: float = float(aim_solution.get("projectile_energy", 0.0))
		var total_casualties: int = 0
		var hit_companies: int = 0
		var first_target_id: String = ""
		for corridor_hit_value in corridor_hits:
			if projectile_energy <= 0.18:
				break
			var corridor_hit: Dictionary = corridor_hit_value
			var hit_target_sprite: Dictionary = corridor_hit.get("target_sprite", {})
			if hit_target_sprite.is_empty():
				continue
			var hit_target_frame: Dictionary = corridor_hit.get("target_frame", {})
			if hit_target_frame.is_empty():
				continue
			var hit_target_id: String = str(hit_target_frame.get("company_id", ""))
			var target_entry: Dictionary = _get_or_create_company_outcome(outcome_buffer, hit_target_id)
			var available_soldiers: int = max(0, int(hit_target_frame.get("soldiers", 0)) - int(target_entry.get("casualties", 0)))
			if available_soldiers <= 0:
				projectile_energy *= 0.72
				continue
			var casualties: int = _compute_artillery_casualties(projectile_energy, corridor_hit, hit_target_sprite, hit_target_frame, aim_solution)
			if casualties <= 0:
				projectile_energy *= 0.74
				continue
			var applied_casualties: int = min(available_soldiers, casualties)
			var suppression_delta: float = clamp(0.05 + float(applied_casualties) * 0.012, 0.0, 0.22)
			target_entry["casualties"] = int(target_entry.get("casualties", 0)) + applied_casualties
			target_entry["morale_delta"] = float(target_entry.get("morale_delta", 0.0)) - float(applied_casualties) * 0.0042 - 0.03
			target_entry["cohesion_delta"] = float(target_entry.get("cohesion_delta", 0.0)) - float(applied_casualties) * 0.0054 - 0.035
			target_entry["suppression_delta"] = float(target_entry.get("suppression_delta", 0.0)) + suppression_delta

			total_casualties += applied_casualties
			hit_companies += 1
			last_artillery_hits += 1
			last_artillery_casualties += applied_casualties
			if first_target_id.is_empty():
				first_target_id = hit_target_id
			projectile_energy *= 0.64 if float(corridor_hit.get("lane_factor", 1.0)) > 0.7 else 0.76

		if total_casualties <= 0:
			continue

		last_artillery_firers += 1
		if hit_companies >= 2:
			_append_event(outcome_buffer, "%s roundshot raked %d companies near %s." % [
				shooter_company_id,
				hit_companies,
				first_target_id,
			])
		elif total_casualties >= 4:
			_append_event(outcome_buffer, "%s battered %s." % [shooter_company_id, first_target_id])


func _build_representative_shooter_sprite(shooter_frame: Dictionary) -> Dictionary:
	return {
		"sprite_id": "%s#shooter" % str(shooter_frame.get("company_id", "")),
		"company_id": shooter_frame.get("company_id", ""),
		"army_id": shooter_frame.get("army_id", ""),
		"position": shooter_frame.get("world_center", Vector2.ZERO),
		"front_direction": shooter_frame.get("front_direction", Vector2.UP),
		"depth_ratio": 0.82,
		"lateral_ratio": 0.22,
		"soldier_share": float(shooter_frame.get("soldiers", 0)),
		"is_routed": shooter_frame.get("is_routed", false),
	}


func _select_small_arms_target_company(
		sim,
		shooter_frame: Dictionary,
		shooter_sprite: Dictionary,
		company_frames_by_regiment: Dictionary,
		target_broadphase: Dictionary,
		visibility_cache: Dictionary
) -> Dictionary:
	var shooter_center: Vector2 = shooter_sprite.get("position", Vector2.ZERO)
	var shooter_front: Vector2 = shooter_sprite.get("front_direction", Vector2.UP).normalized()
	if shooter_front.length_squared() <= 0.001:
		shooter_front = Vector2.UP
	var max_range: float = float(shooter_frame.get("max_range", 0.0))
	if max_range <= 0.0:
		return {}
	var preferred_regiment_id: String = str(shooter_frame.get("engagement_target_regiment_id", ""))
	var candidate_frames: Array = _gather_small_arms_candidate_frames(
		shooter_frame,
		shooter_center,
		max_range,
		preferred_regiment_id,
		company_frames_by_regiment,
		target_broadphase
	)
	if candidate_frames.is_empty():
		return {}
	var best_target: Dictionary = {}
	var best_score: float = -INF
	for target_frame_value in candidate_frames:
		var target_frame: Dictionary = target_frame_value
		if target_frame.get("army_id", "") == shooter_frame.get("army_id", ""):
			continue
		if bool(target_frame.get("is_routed", false)):
			continue
		var target_sprite: Dictionary = _build_representative_target_sprite(target_frame, shooter_center)
		var target_center: Vector2 = target_sprite.get("position", Vector2.ZERO)
		var direction_to_target: Vector2 = target_center - shooter_center
		var distance: float = direction_to_target.length()
		if distance <= 20.0 or distance > max_range:
			continue
		var target_direction: Vector2 = direction_to_target.normalized()
		var facing_dot: float = shooter_front.dot(target_direction)
		if facing_dot < -0.35:
			continue
		var visibility: float = _get_cached_visibility(sim, visibility_cache, shooter_center, target_center)
		if visibility < 0.05:
			continue
		var score: float = _score_small_arms_target(
			shooter_frame,
			shooter_sprite,
			target_frame,
			target_sprite,
			distance,
			visibility
		)
		if str(target_frame.get("regiment_id", "")) == preferred_regiment_id:
			score += 0.45
		score += clamp(facing_dot, -0.2, 1.0) * 0.18
		var target_state: int = int(target_frame.get("engagement_state", SimTypes.EngagementState.NO_CONTACT))
		if target_state in [
			SimTypes.EngagementState.FIREFIGHT,
			SimTypes.EngagementState.DEPLOY_FIRE,
			SimTypes.EngagementState.ASSAULT,
		]:
			score += 0.08
		if score <= best_score:
			continue
		best_score = score
		best_target = {
			"frame": target_frame,
			"sprite": target_sprite,
			"distance": distance,
			"visibility": visibility,
		}
	return best_target


func _gather_small_arms_candidate_frames(
		shooter_frame: Dictionary,
		shooter_center: Vector2,
		max_range: float,
		preferred_regiment_id: String,
		company_frames_by_regiment: Dictionary,
		target_broadphase: Dictionary
) -> Array:
	var result: Array = []
	var seen_company_ids: Dictionary = {}
	var shooter_army_id: String = str(shooter_frame.get("army_id", ""))
	if not preferred_regiment_id.is_empty():
		for preferred_value in company_frames_by_regiment.get(preferred_regiment_id, []):
			var preferred_frame: Dictionary = preferred_value
			var preferred_company_id: String = str(preferred_frame.get("company_id", ""))
			if seen_company_ids.has(preferred_company_id):
				continue
			seen_company_ids[preferred_company_id] = true
			result.append(preferred_frame)
	var cell_radius: int = int(ceil(max_range / SMALL_ARMS_TARGET_CELL_SIZE))
	var shooter_cell: Vector2i = _get_broadphase_cell(shooter_center, SMALL_ARMS_TARGET_CELL_SIZE)
	for offset_y in range(-cell_radius, cell_radius + 1):
		for offset_x in range(-cell_radius, cell_radius + 1):
			var cell_key: Vector2i = Vector2i(shooter_cell.x + offset_x, shooter_cell.y + offset_y)
			if not target_broadphase.has(cell_key):
				continue
			for target_value in target_broadphase.get(cell_key, []):
				var target_frame: Dictionary = target_value
				if str(target_frame.get("army_id", "")) == shooter_army_id:
					continue
				var company_id: String = str(target_frame.get("company_id", ""))
				if seen_company_ids.has(company_id):
					continue
				seen_company_ids[company_id] = true
				result.append(target_frame)
	return result


func _select_artillery_target(sim, shooter_frame: Dictionary, company_frames: Array) -> Dictionary:
	var shooter_center: Vector2 = shooter_frame.get("world_center", Vector2.ZERO)
	var max_range: float = float(shooter_frame.get("max_range", 0.0))
	if max_range <= 0.0:
		return {}
	var best_target: Dictionary = {}
	var best_score: float = -INF
	for target_value in company_frames:
		var target_frame: Dictionary = target_value
		if target_frame.get("army_id", "") == shooter_frame.get("army_id", ""):
			continue
		if bool(target_frame.get("is_routed", false)):
			continue
		var target_center: Vector2 = target_frame.get("world_center", Vector2.ZERO)
		var distance: float = shooter_center.distance_to(target_center)
		if distance <= 40.0 or distance > max_range:
			continue
		var visibility: float = sim.visibility_between(shooter_center, target_center)
		if visibility < 0.05:
			continue
		var score: float = _score_artillery_target(shooter_frame, target_frame, company_frames, distance, visibility)
		if score > best_score:
			best_score = score
			best_target = target_frame
	return best_target


func _score_artillery_target(shooter_frame: Dictionary, target_frame: Dictionary, company_frames: Array, distance: float, visibility: float) -> float:
	var max_range: float = max(1.0, float(shooter_frame.get("max_range", 1.0)))
	var range_score: float = clamp(1.0 - distance / max_range, 0.0, 1.0)
	var density_score: float = clamp(float(target_frame.get("depth_density", 1.0)) * float(target_frame.get("cohesion", 1.0)), 0.55, 1.8)
	var cluster_score: float = 0.0
	for other_value in company_frames:
		var other_frame: Dictionary = other_value
		if other_frame.get("army_id", "") != target_frame.get("army_id", ""):
			continue
		if str(other_frame.get("company_id", "")) == str(target_frame.get("company_id", "")):
			continue
		var lateral_distance: float = target_frame.get("world_center", Vector2.ZERO).distance_to(other_frame.get("world_center", Vector2.ZERO))
		if lateral_distance <= 80.0:
			cluster_score += 0.14
	return range_score * 0.85 + visibility * 0.7 + density_score * 0.9 + cluster_score


func _build_artillery_aim_solution(frame: Dictionary, shooter_frame: Dictionary, target_frame: Dictionary, target_distance: float, visibility: float) -> Dictionary:
	var shooter_center: Vector2 = shooter_frame.get("world_center", Vector2.ZERO)
	var target_center: Vector2 = target_frame.get("world_center", Vector2.ZERO)
	var shot_direction: Vector2 = (target_center - shooter_center).normalized()
	if shot_direction.length_squared() <= 0.001:
		shot_direction = shooter_frame.get("front_direction", Vector2.UP).normalized()
	if shot_direction.length_squared() <= 0.001:
		shot_direction = Vector2.UP
	var right_axis: Vector2 = Vector2(-shot_direction.y, shot_direction.x).normalized()
	var accuracy: float = _compute_artillery_accuracy(shooter_frame, target_frame, target_distance, visibility)
	var lateral_error_max: float = lerpf(46.0, 10.0, accuracy)
	var range_error_max: float = lerpf(64.0, 14.0, accuracy)
	var seed_prefix: String = "%s|%s|%.3f" % [
		str(frame.get("time_seconds", 0.0)),
		str(shooter_frame.get("company_id", "")),
		target_distance,
	]
	var lateral_roll: float = _stable_noise_from_key("%s|art_lateral" % seed_prefix)
	var range_roll: float = _stable_noise_from_key("%s|art_range" % seed_prefix)
	var corrected_point: Vector2 = target_center \
		+ right_axis * lerpf(-lateral_error_max, lateral_error_max, lateral_roll) \
		+ shot_direction * lerpf(-range_error_max, range_error_max, range_roll)
	var corrected_direction: Vector2 = (corrected_point - shooter_center).normalized()
	if corrected_direction.length_squared() <= 0.001:
		corrected_direction = shot_direction
	var corridor_length: float = min(float(shooter_frame.get("max_range", target_distance)), shooter_center.distance_to(corrected_point) + 190.0)
	var lane_half_width: float = lerpf(30.0, 12.0, accuracy) + clamp(target_distance / max(1.0, float(shooter_frame.get("max_range", 1.0))), 0.0, 1.0) * 8.0
	var projectile_energy: float = 0.78 \
		+ float(shooter_frame.get("training", 0.6)) * 0.22 \
		+ float(shooter_frame.get("morale", 0.72)) * 0.12 \
		+ float(shooter_frame.get("effective_firepower", 0.0)) / 220.0
	return {
		"origin": shooter_center,
		"direction": corrected_direction,
		"corridor_length": corridor_length,
		"lane_half_width": lane_half_width,
		"projectile_energy": projectile_energy,
	}


func _compute_artillery_accuracy(shooter_frame: Dictionary, target_frame: Dictionary, distance: float, visibility: float) -> float:
	var max_range: float = max(1.0, float(shooter_frame.get("max_range", 1.0)))
	var range_factor: float = clamp(1.0 - (distance / max_range) * 0.7, 0.12, 1.0)
	var visibility_factor: float = clamp(visibility, 0.08, 1.0)
	var morale_factor: float = lerpf(0.72, 1.0, clamp(float(shooter_frame.get("morale", 0.75)), 0.0, 1.0))
	var cohesion_factor: float = lerpf(0.7, 1.0, clamp(float(shooter_frame.get("cohesion", 0.75)), 0.0, 1.0))
	var suppression_factor: float = clamp(1.0 - float(shooter_frame.get("suppression", 0.0)) * 0.4, 0.45, 1.0)
	var training_factor: float = lerpf(0.76, 1.0, clamp(float(shooter_frame.get("training", 0.6)), 0.0, 1.0))
	var target_density_factor: float = clamp(float(target_frame.get("depth_density", 1.0)) * 0.38 * (1.0 + float(target_frame.get("reform_exposure", 0.0)) * 0.18), 0.65, 1.35)
	var reform_factor: float = clamp(1.0 - float(shooter_frame.get("reform_exposure", 0.0)) * 0.38, 0.55, 1.0)
	return clamp(0.34 * range_factor * visibility_factor * morale_factor * cohesion_factor * suppression_factor * training_factor * target_density_factor * reform_factor, 0.0, 0.96)


func _collect_artillery_corridor_hits(shooter_frame: Dictionary, sprite_frames: Array, company_frames_by_id: Dictionary, aim_solution: Dictionary) -> Array:
	var result: Array = []
	var origin: Vector2 = aim_solution.get("origin", Vector2.ZERO)
	var direction: Vector2 = aim_solution.get("direction", Vector2.UP).normalized()
	if direction.length_squared() <= 0.001:
		return result
	var right_axis: Vector2 = Vector2(-direction.y, direction.x).normalized()
	var corridor_length: float = float(aim_solution.get("corridor_length", 0.0))
	var lane_half_width: float = float(aim_solution.get("lane_half_width", 0.0))
	for sprite_frame_value in sprite_frames:
		var target_sprite: Dictionary = sprite_frame_value
		if target_sprite.get("army_id", "") == shooter_frame.get("army_id", ""):
			continue
		if bool(target_sprite.get("is_routed", false)):
			continue
		var target_center: Vector2 = target_sprite.get("position", Vector2.ZERO)
		var target_offset: Vector2 = target_center - origin
		var longitudinal: float = target_offset.dot(direction)
		if longitudinal <= 24.0 or longitudinal > corridor_length:
			continue
		var lateral: float = absf(target_offset.dot(right_axis))
		var sprite_half_width: float = max(5.0, float(target_sprite.get("width", 10.0)) * 0.5)
		if lateral > lane_half_width + sprite_half_width:
			continue
		var target_frame: Dictionary = company_frames_by_id.get(str(target_sprite.get("company_id", "")), {})
		if target_frame.is_empty():
			continue
		result.append({
			"target_sprite": target_sprite,
			"target_frame": target_frame,
			"longitudinal": longitudinal,
			"lateral": lateral,
			"lane_factor": clamp(1.0 - lateral / max(1.0, lane_half_width + sprite_half_width), 0.12, 1.0),
		})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("longitudinal", 0.0)) < float(b.get("longitudinal", 0.0))
	)
	return result


func _compute_artillery_casualties(projectile_energy: float, corridor_hit: Dictionary, target_sprite: Dictionary, target_frame: Dictionary, aim_solution: Dictionary) -> int:
	var corridor_length: float = max(1.0, float(aim_solution.get("corridor_length", 1.0)))
	var travel_factor: float = clamp(1.0 - float(corridor_hit.get("longitudinal", 0.0)) / corridor_length, 0.22, 1.0)
	var lane_factor: float = float(corridor_hit.get("lane_factor", 0.5))
	var density_factor: float = clamp(float(target_frame.get("depth_density", 1.0)) * float(target_frame.get("cohesion", 1.0)) * 0.48, 0.5, 1.55)
	var sprite_density_factor: float = clamp(0.82 + float(target_sprite.get("depth_ratio", 0.5)) * 0.32, 0.72, 1.18)
	var raw_value: float = projectile_energy * (1.9 + travel_factor * 2.1) * lane_factor * density_factor
	var casualty_cap: int = max(2, int(round(float(target_sprite.get("soldier_share", 0.0)) * 0.28)))
	return clamp(int(round(raw_value * sprite_density_factor * 1.18)), 0, casualty_cap)


func _resolve_charge(frame: Dictionary, outcome_buffer: Dictionary) -> void:
	var sprite_frames_by_id: Dictionary = {}
	for sprite_frame_value in frame.get("sprite_frames", []):
		var sprite_frame: Dictionary = sprite_frame_value
		sprite_frames_by_id[str(sprite_frame.get("sprite_id", ""))] = sprite_frame
	var edges: Array = frame.get("contact_candidates", []).duplicate()
	edges.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("edge_id", "")) < str(b.get("edge_id", ""))
	)
	var best_edge_by_attacker_company: Dictionary = {}
	for edge_value in edges:
		var edge: Dictionary = edge_value
		if not bool(edge.get("is_charge_impact_candidate", false)):
			continue
		var left_frame: Dictionary = sprite_frames_by_id.get(str(edge.get("left_sprite_id", "")), {})
		var right_frame: Dictionary = sprite_frames_by_id.get(str(edge.get("right_sprite_id", "")), {})
		if left_frame.is_empty() or right_frame.is_empty():
			continue
		var left_is_cavalry: bool = int(left_frame.get("combat_role", -1)) == CombatTypes.CombatRole.CAVALRY
		var right_is_cavalry: bool = int(right_frame.get("combat_role", -1)) == CombatTypes.CombatRole.CAVALRY
		if left_is_cavalry == right_is_cavalry:
			continue
		var attacker_frame: Dictionary = left_frame if left_is_cavalry else right_frame
		var defender_frame: Dictionary = right_frame if left_is_cavalry else left_frame
		var attacker_company_id: String = str(attacker_frame.get("company_id", ""))
		var contact_side: int = int(edge.get("contact_side_right", CombatTypes.ContactSide.NONE)) if left_is_cavalry else int(edge.get("contact_side_left", CombatTypes.ContactSide.NONE))
		var edge_score: float = float(edge.get("shared_frontage_length", 0.0)) * 1.1 - float(edge.get("distance_along_front", 0.0)) * 0.04
		if contact_side in [CombatTypes.ContactSide.LEFT_FLANK, CombatTypes.ContactSide.RIGHT_FLANK]:
			edge_score += 1.2
		elif contact_side == CombatTypes.ContactSide.REAR:
			edge_score += 1.8
		var existing: Dictionary = best_edge_by_attacker_company.get(attacker_company_id, {})
		if existing.is_empty() or edge_score > float(existing.get("score", -INF)):
			best_edge_by_attacker_company[attacker_company_id] = {
				"score": edge_score,
				"edge": edge,
				"attacker_frame": attacker_frame,
				"defender_frame": defender_frame,
			}
	for resolved_value in best_edge_by_attacker_company.values():
		var resolved: Dictionary = resolved_value
		_resolve_charge_edge(
			frame,
			resolved.get("attacker_frame", {}),
			resolved.get("defender_frame", {}),
			resolved.get("edge", {}),
			outcome_buffer
		)


func _resolve_melee(frame: Dictionary, outcome_buffer: Dictionary) -> void:
	var sprite_frames_by_id: Dictionary = {}
	for sprite_frame_value in frame.get("sprite_frames", []):
		var sprite_frame: Dictionary = sprite_frame_value
		sprite_frames_by_id[str(sprite_frame.get("sprite_id", ""))] = sprite_frame
	var edges: Array = frame.get("contact_candidates", []).duplicate()
	edges.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("shared_frontage_length", 0.0)) > float(b.get("shared_frontage_length", 0.0))
	)
	var engaged_sprite_ids: Dictionary = {}
	for edge_value in edges:
		var edge: Dictionary = edge_value
		if not bool(edge.get("is_melee_candidate", false)):
			continue
		var left_sprite_id: String = str(edge.get("left_sprite_id", ""))
		var right_sprite_id: String = str(edge.get("right_sprite_id", ""))
		if engaged_sprite_ids.has(left_sprite_id) or engaged_sprite_ids.has(right_sprite_id):
			continue
		var left_frame: Dictionary = sprite_frames_by_id.get(left_sprite_id, {})
		var right_frame: Dictionary = sprite_frames_by_id.get(right_sprite_id, {})
		if left_frame.is_empty() or right_frame.is_empty():
			continue
		if _is_active_charge_contact(left_frame, right_frame):
			continue
		_resolve_melee_edge(frame, left_frame, right_frame, edge, outcome_buffer)
		engaged_sprite_ids[left_sprite_id] = true
		engaged_sprite_ids[right_sprite_id] = true


func _apply_outcomes(sim, outcome_buffer: Dictionary) -> void:
	var company_outcomes: Dictionary = outcome_buffer.get("companies", {})
	var regiment_outcomes: Dictionary = outcome_buffer.get("regiments", {})
	if company_outcomes.is_empty() and regiment_outcomes.is_empty():
		return

	var company_index: Dictionary = {}
	var regiment_company_ids: Dictionary = {}
	var regiment_total_weight: Dictionary = {}
	for regiment_value in sim.regiments.values():
		var regiment: Battalion = regiment_value
		var company_ids: Array = []
		var total_weight: float = 0.0
		for company_value in regiment.companies:
			var company: CombatStand = company_value
			company_index[company.id] = {
				"company": company,
				"regiment": regiment,
			}
			company_ids.append(str(company.id))
			total_weight += float(max(1, company.soldiers))
		regiment_company_ids[regiment.id] = company_ids
		regiment_total_weight[regiment.id] = total_weight

	_distribute_regiment_state_deltas_to_companies(
		outcome_buffer,
		company_index,
		regiment_company_ids,
		regiment_total_weight
	)

	var dirty_regiments: Dictionary = {}
	for company_id_value in company_outcomes.keys():
		var company_id: StringName = StringName(company_id_value)
		var indexed: Dictionary = company_index.get(company_id, {})
		if indexed.is_empty():
			continue
		var company: CombatStand = indexed.get("company")
		var regiment: Battalion = indexed.get("regiment")
		var entry: Dictionary = company_outcomes[company_id_value]
		company.soldiers = max(0, company.soldiers - int(entry.get("casualties", 0)))
		company.morale = clamp(company.morale + float(entry.get("morale_delta", 0.0)), 0.0, 1.0)
		company.cohesion = clamp(company.cohesion + float(entry.get("cohesion_delta", 0.0)), 0.0, 1.0)
		company.suppression = clamp(company.suppression + float(entry.get("suppression_delta", 0.0)), 0.0, 1.0)
		company.ammo = clamp(company.ammo + float(entry.get("ammo_delta", 0.0)), 0.0, 1.0)
		var reload_state_override: int = int(entry.get("reload_state_override", -1))
		if reload_state_override >= 0:
			company.reload_state = reload_state_override
			if reload_state_override == CombatTypes.ReloadState.FIRING:
				company.trigger_visual_fire(sim.time_seconds, max(company.fire_cycle_duration, 0.2))
		var reload_progress_override: float = float(entry.get("reload_progress_override", -1.0))
		if reload_progress_override >= 0.0:
			company.reload_progress = reload_progress_override
		company.is_routed = bool(entry.get("routed", false)) or company.is_routed
		company.is_destroyed = company.soldiers <= 0
		if regiment != null:
			dirty_regiments[regiment.id] = regiment

	for regiment_id_value in regiment_outcomes.keys():
		var regiment: Battalion = sim.regiments.get(StringName(regiment_id_value))
		if regiment == null:
			continue
		var entry: Dictionary = regiment_outcomes[regiment_id_value]
		var forced_posture: int = int(entry.get("forced_posture", -1))
		if forced_posture >= 0:
			regiment.combat_posture = forced_posture
		var brace_until: float = float(entry.get("brace_until", -1.0))
		if brace_until >= 0.0:
			regiment.brace_until = brace_until
		var combat_lock_until: float = float(entry.get("combat_lock_until", -1.0))
		if combat_lock_until >= 0.0:
			regiment.combat_lock_until = combat_lock_until
		var charge_recovery_until: float = float(entry.get("charge_recovery_until", -1.0))
		if charge_recovery_until >= 0.0:
			regiment.charge_recovery_until = charge_recovery_until
			regiment.clear_charge_run()
		var charge_retreat_requested: bool = bool(entry.get("charge_retreat_requested", false))
		if charge_retreat_requested:
			regiment.charge_retreat_target_position = entry.get("charge_retreat_target_position", regiment.position)
		var charge_retreat_until: float = float(entry.get("charge_retreat_until", -1.0))
		if charge_retreat_until >= 0.0:
			regiment.charge_retreat_until = charge_retreat_until
			regiment.clear_charge_run()
		dirty_regiments[regiment.id] = regiment

	for dirty_regiment_value in dirty_regiments.values():
		var dirty_regiment: Battalion = dirty_regiment_value
		dirty_regiment.refresh_combat_aggregates()
	for event_text_value in outcome_buffer.get("events", []):
		sim.push_event(str(event_text_value))


func _distribute_regiment_state_deltas_to_companies(
		outcome_buffer: Dictionary,
		company_index: Dictionary,
		regiment_company_ids: Dictionary,
		regiment_total_weight: Dictionary
) -> void:
	var regiment_outcomes: Dictionary = outcome_buffer.get("regiments", {})
	if regiment_outcomes.is_empty():
		return
	for regiment_id_value in regiment_outcomes.keys():
		var regiment_entry: Dictionary = regiment_outcomes[regiment_id_value]
		var morale_delta: float = float(regiment_entry.get("morale_delta", 0.0))
		var cohesion_delta: float = float(regiment_entry.get("cohesion_delta", 0.0))
		var suppression_delta: float = float(regiment_entry.get("suppression_delta", 0.0))
		if is_zero_approx(morale_delta) and is_zero_approx(cohesion_delta) and is_zero_approx(suppression_delta):
			continue
		var regiment_id: StringName = StringName(regiment_id_value)
		var total_weight: float = float(regiment_total_weight.get(regiment_id, 0.0))
		if total_weight <= 0.0:
			continue
		for company_id_value in regiment_company_ids.get(regiment_id, []):
			var company_id: String = str(company_id_value)
			var indexed: Dictionary = company_index.get(StringName(company_id), {})
			if indexed.is_empty():
				continue
			var company: CombatStand = indexed.get("company")
			var weight_ratio: float = float(max(1, company.soldiers)) / total_weight
			var company_entry: Dictionary = _get_or_create_company_outcome(outcome_buffer, company_id)
			company_entry["morale_delta"] = float(company_entry.get("morale_delta", 0.0)) + morale_delta * weight_ratio
			company_entry["cohesion_delta"] = float(company_entry.get("cohesion_delta", 0.0)) + cohesion_delta * weight_ratio
			company_entry["suppression_delta"] = float(company_entry.get("suppression_delta", 0.0)) + suppression_delta * weight_ratio


func _select_small_arms_target_sprite(
		sim,
		shooter_frame: Dictionary,
		shooter_sprite: Dictionary,
		company_frames_by_id: Dictionary,
		sprite_frames: Array,
		sprite_frames_by_company: Dictionary,
		contacts_for_company: Array
) -> Dictionary:
	var shooter_center: Vector2 = shooter_sprite.get("position", Vector2.ZERO)
	var shooter_front: Vector2 = shooter_sprite.get("front_direction", Vector2.UP).normalized()
	var max_range: float = float(shooter_frame.get("max_range", 0.0))
	if max_range <= 0.0:
		return {}

	var best_contact_target: Dictionary = {}
	var best_contact_score: float = -INF
	for contact_value in contacts_for_company:
		var contact: Dictionary = contact_value
		var target_company_id: String = str(contact.get("right_company_id", "")) if str(contact.get("left_company_id", "")) == str(shooter_frame.get("company_id", "")) else str(contact.get("left_company_id", ""))
		var target_frame: Dictionary = company_frames_by_id.get(target_company_id, {})
		if target_frame.is_empty() or bool(target_frame.get("is_routed", false)):
			continue
		var target_sprite: Dictionary = _build_representative_target_sprite(target_frame, shooter_center)
		var target_center: Vector2 = target_sprite.get("position", Vector2.ZERO)
		var direction_to_target: Vector2 = target_center - shooter_center
		var distance: float = direction_to_target.length()
		if distance <= 24.0 or distance > max_range:
			continue
		var target_direction: Vector2 = direction_to_target.normalized()
		if shooter_front.dot(target_direction) < 0.05:
			continue
		var visibility: float = sim.visibility_between(shooter_center, target_center)
		if visibility < 0.1:
			continue
		var score: float = float(contact.get("shared_frontage_length", 0.0)) \
			+ _score_small_arms_target(shooter_frame, shooter_sprite, target_frame, target_sprite, distance, visibility) * 0.8
		if score > best_contact_score:
			best_contact_score = score
			best_contact_target = target_sprite
	if not best_contact_target.is_empty():
		return best_contact_target

	var best_target: Dictionary = {}
	var best_score: float = -INF
	for target_frame_value in company_frames_by_id.values():
		var target_frame: Dictionary = target_frame_value
		if target_frame.get("army_id", "") == shooter_sprite.get("army_id", ""):
			continue
		if bool(target_frame.get("is_routed", false)):
			continue
		var target_sprite: Dictionary = _build_representative_target_sprite(target_frame, shooter_center)
		var target_center: Vector2 = target_sprite.get("position", Vector2.ZERO)
		var direction_to_target: Vector2 = target_center - shooter_center
		var distance: float = direction_to_target.length()
		if distance <= 1.0 or distance > max_range:
			continue
		var target_direction: Vector2 = direction_to_target.normalized()
		if shooter_front.dot(target_direction) < 0.05:
			continue
		var visibility: float = sim.visibility_between(shooter_center, target_center)
		if visibility < 0.1:
			continue
		var score: float = _score_small_arms_target(shooter_frame, shooter_sprite, target_frame, target_sprite, distance, visibility)
		if score > best_score:
			best_score = score
			best_target = target_sprite
	return best_target


func _build_representative_target_sprite(target_frame: Dictionary, shooter_center: Vector2 = Vector2.ZERO) -> Dictionary:
	var target_center: Vector2 = target_frame.get("world_center", Vector2.ZERO)
	var target_front: Vector2 = target_frame.get("front_direction", Vector2.UP).normalized()
	if target_front.length_squared() <= 0.001:
		target_front = Vector2.UP
	var right_axis: Vector2 = Vector2(-target_front.y, target_front.x).normalized()
	var approach_offset: Vector2 = shooter_center - target_center
	var incoming_direction: Vector2 = approach_offset.normalized() if approach_offset.length_squared() > 0.001 else target_front
	var half_frontage: float = max(1.0, float(target_frame.get("frontage_width", 12.0)) * 0.5)
	var lateral_ratio: float = clamp(absf(approach_offset.dot(right_axis)) / half_frontage, 0.0, 1.0)
	var depth_ratio: float = 0.78 if target_front.dot(incoming_direction) > 0.0 else 0.42
	var sprite_count: int = max(1, int(target_frame.get("combat_sprite_count", 1)))
	return {
		"sprite_id": "%s#rep" % str(target_frame.get("company_id", "")),
		"company_id": target_frame.get("company_id", ""),
		"army_id": target_frame.get("army_id", ""),
		"position": target_center,
		"front_direction": target_front,
		"depth_ratio": depth_ratio,
		"lateral_ratio": lateral_ratio,
		"soldier_share": float(target_frame.get("soldiers", 0)) / float(sprite_count),
		"is_routed": target_frame.get("is_routed", false),
	}


func _score_small_arms_target(
		shooter_frame: Dictionary,
		shooter_sprite: Dictionary,
		target_frame: Dictionary,
		target_sprite: Dictionary,
		distance: float,
		visibility: float
) -> float:
	var max_range: float = float(shooter_frame.get("max_range", 1.0))
	var range_score: float = clamp(1.0 - distance / max(1.0, max_range), 0.0, 1.0)
	var density_score: float = clamp(float(target_frame.get("depth_density", 1.0)) * float(target_frame.get("cohesion", 1.0)), 0.4, 2.0)
	var routed_penalty: float = 0.4 if bool(target_frame.get("is_routed", false)) else 1.0
	var target_front: Vector2 = target_sprite.get("front_direction", Vector2.UP).normalized()
	var incoming_direction: Vector2 = (target_sprite.get("position", Vector2.ZERO) - shooter_sprite.get("position", Vector2.ZERO)).normalized()
	var flank_bonus: float = 0.14 if absf(target_front.dot(incoming_direction)) < 0.35 else 0.0
	var target_cluster_bias: float = 1.0 - absf(float(target_sprite.get("lateral_ratio", 0.5)) - 0.5) * 0.32
	return range_score * 1.2 + visibility * 0.85 + density_score * 0.6 * routed_penalty + flank_bonus + target_cluster_bias * 0.1


func _compute_small_arms_accuracy(
		shooter_frame: Dictionary,
		shooter_sprite: Dictionary,
		target_frame: Dictionary,
		target_sprite: Dictionary,
		distance: float,
		visibility: float
) -> float:
	var max_range: float = float(shooter_frame.get("max_range", 1.0))
	var range_ratio: float = clamp(distance / max(1.0, max_range), 0.0, 1.35)
	var range_factor: float = clamp(1.0 - range_ratio * 0.82, 0.08, 1.0)
	var visibility_factor: float = clamp(visibility, 0.08, 1.0)
	var target_density_factor: float = clamp(
		float(target_frame.get("depth_density", 1.0)) * float(target_frame.get("cohesion", 1.0)) * 0.55 * (1.0 + float(target_frame.get("reform_exposure", 0.0)) * 0.2),
		0.55,
		1.45
	)
	var target_sprite_exposure: float = clamp(0.8 + float(target_sprite.get("depth_ratio", 0.5)) * 0.3 + (1.0 - float(target_sprite.get("lateral_ratio", 0.5))) * 0.08, 0.72, 1.16)
	var morale_factor: float = lerpf(0.68, 1.02, clamp(float(shooter_frame.get("morale", 0.75)), 0.0, 1.0))
	var cohesion_factor: float = lerpf(0.65, 1.0, clamp(float(shooter_frame.get("cohesion", 0.75)), 0.0, 1.0))
	var suppression_factor: float = clamp(1.0 - float(shooter_frame.get("suppression", 0.0)) * 0.42, 0.42, 1.0)
	var movement_factor: float = 0.84 if int(shooter_frame.get("combat_posture", CombatTypes.CombatPosture.IDLE)) == CombatTypes.CombatPosture.ADVANCING else 1.0
	var sprite_stability: float = clamp(0.88 + float(shooter_sprite.get("depth_ratio", 0.5)) * 0.18, 0.82, 1.06)
	var training_factor: float = lerpf(0.7, 1.0, clamp(float(shooter_frame.get("training", 0.6)), 0.0, 1.0))
	var reform_factor: float = clamp(1.0 - float(shooter_frame.get("reform_exposure", 0.0)) * 0.42, 0.52, 1.0)
	var base_accuracy: float = 0.3
	return clamp(base_accuracy * range_factor * visibility_factor * target_density_factor * target_sprite_exposure * morale_factor * cohesion_factor * suppression_factor * movement_factor * sprite_stability * training_factor * reform_factor, 0.0, 0.95)


func _find_company_frame_by_id(company_frames: Array, company_id: String) -> Dictionary:
	for company_frame_value in company_frames:
		var company_frame: Dictionary = company_frame_value
		if str(company_frame.get("company_id", "")) == company_id:
			return company_frame
	return {}


func _get_or_create_company_outcome(outcome_buffer: Dictionary, company_id: String) -> Dictionary:
	var companies: Dictionary = outcome_buffer.get("companies", {})
	var company_key: StringName = StringName(company_id)
	if not companies.has(company_key):
		companies[company_key] = CombatTypes.build_company_outcome_entry()
		outcome_buffer["companies"] = companies
	return companies[company_key]


func _get_or_create_regiment_outcome(outcome_buffer: Dictionary, regiment_id: String) -> Dictionary:
	var regiments: Dictionary = outcome_buffer.get("regiments", {})
	var regiment_key: StringName = StringName(regiment_id)
	if not regiments.has(regiment_key):
		regiments[regiment_key] = CombatTypes.build_regiment_outcome_entry()
		outcome_buffer["regiments"] = regiments
	return regiments[regiment_key]


func _stable_noise_from_key(key: String) -> float:
	var hashed: int = hash(key)
	var normalized: float = float(abs(hashed % 100000)) / 99999.0
	return clamp(normalized, 0.0, 1.0)


func _append_event(outcome_buffer: Dictionary, text: String) -> void:
	var events: Array = outcome_buffer.get("events", [])
	events.append(text)
	outcome_buffer["events"] = events


func _get_cached_visibility(sim, visibility_cache: Dictionary, from_position: Vector2, to_position: Vector2) -> float:
	var left_key: String = "%0.2f,%0.2f" % [from_position.x, from_position.y]
	var right_key: String = "%0.2f,%0.2f" % [to_position.x, to_position.y]
	var cache_key: String = "%s__%s" % [left_key, right_key] if left_key < right_key else "%s__%s" % [right_key, left_key]
	if visibility_cache.has(cache_key):
		return float(visibility_cache[cache_key])
	var visibility: float = sim.visibility_between(from_position, to_position)
	visibility_cache[cache_key] = visibility
	return visibility


func _is_active_charge_contact(left_frame: Dictionary, right_frame: Dictionary) -> bool:
	var left_is_cavalry: bool = int(left_frame.get("combat_role", -1)) == CombatTypes.CombatRole.CAVALRY
	var right_is_cavalry: bool = int(right_frame.get("combat_role", -1)) == CombatTypes.CombatRole.CAVALRY
	if left_is_cavalry == right_is_cavalry:
		return false
	var cavalry_frame: Dictionary = left_frame if left_is_cavalry else right_frame
	return int(cavalry_frame.get("combat_order_mode", CombatTypes.CombatOrderMode.NONE)) == CombatTypes.CombatOrderMode.CHARGE \
		and int(cavalry_frame.get("combat_posture", CombatTypes.CombatPosture.IDLE)) == CombatTypes.CombatPosture.CHARGE_WINDUP


func _resolve_melee_edge(frame: Dictionary, left_frame: Dictionary, right_frame: Dictionary, edge: Dictionary, outcome_buffer: Dictionary) -> void:
	if bool(left_frame.get("is_routed", false)) or bool(right_frame.get("is_routed", false)):
		return
	var left_company_id: String = str(left_frame.get("company_id", ""))
	var right_company_id: String = str(right_frame.get("company_id", ""))
	var left_entry: Dictionary = _get_or_create_company_outcome(outcome_buffer, left_company_id)
	var right_entry: Dictionary = _get_or_create_company_outcome(outcome_buffer, right_company_id)
	if bool(left_entry.get("routed", false)) or bool(right_entry.get("routed", false)):
		return
	var shared_frontage_length: float = float(edge.get("shared_frontage_length", 0.0))
	if shared_frontage_length <= 0.4:
		return

	var left_target_side: int = int(edge.get("contact_side_right", CombatTypes.ContactSide.FRONT))
	var right_target_side: int = int(edge.get("contact_side_left", CombatTypes.ContactSide.FRONT))
	var left_pressure: float = _compute_melee_pressure(left_frame, right_frame, left_target_side, shared_frontage_length)
	var right_pressure: float = _compute_melee_pressure(right_frame, left_frame, right_target_side, shared_frontage_length)
	if left_pressure <= 0.05 and right_pressure <= 0.05:
		return

	var left_available: int = max(0, int(round(float(left_frame.get("soldier_share", left_frame.get("soldiers", 0))))))
	var right_available: int = max(0, int(round(float(right_frame.get("soldier_share", right_frame.get("soldiers", 0))))))
	if left_available <= 0 or right_available <= 0:
		return

	var left_losses: int = min(left_available, _compute_melee_casualties(right_pressure, left_frame, right_frame, right_target_side, shared_frontage_length))
	var right_losses: int = min(right_available, _compute_melee_casualties(left_pressure, right_frame, left_frame, left_target_side, shared_frontage_length))
	var left_pressure_delta: float = max(0.0, right_pressure - left_pressure)
	var right_pressure_delta: float = max(0.0, left_pressure - right_pressure)
	var mutual_disorder: float = min(left_pressure, right_pressure) * 0.012

	left_entry["entered_melee"] = true
	right_entry["entered_melee"] = true
	left_entry["casualties"] = int(left_entry.get("casualties", 0)) + left_losses
	right_entry["casualties"] = int(right_entry.get("casualties", 0)) + right_losses
	left_entry["morale_delta"] = float(left_entry.get("morale_delta", 0.0)) - float(left_losses) * 0.006 - left_pressure_delta * 0.03
	left_entry["cohesion_delta"] = float(left_entry.get("cohesion_delta", 0.0)) - float(left_losses) * 0.008 - left_pressure_delta * 0.042 - mutual_disorder
	left_entry["suppression_delta"] = float(left_entry.get("suppression_delta", 0.0)) + clamp(left_pressure_delta * 0.08 + mutual_disorder, 0.0, 0.18)
	right_entry["morale_delta"] = float(right_entry.get("morale_delta", 0.0)) - float(right_losses) * 0.006 - right_pressure_delta * 0.03
	right_entry["cohesion_delta"] = float(right_entry.get("cohesion_delta", 0.0)) - float(right_losses) * 0.008 - right_pressure_delta * 0.042 - mutual_disorder
	right_entry["suppression_delta"] = float(right_entry.get("suppression_delta", 0.0)) + clamp(right_pressure_delta * 0.08 + mutual_disorder, 0.0, 0.18)

	var left_regiment_entry: Dictionary = _get_or_create_regiment_outcome(outcome_buffer, str(left_frame.get("regiment_id", "")))
	var right_regiment_entry: Dictionary = _get_or_create_regiment_outcome(outcome_buffer, str(right_frame.get("regiment_id", "")))
	left_regiment_entry["forced_posture"] = CombatTypes.CombatPosture.MELEE
	right_regiment_entry["forced_posture"] = CombatTypes.CombatPosture.MELEE
	var melee_lock_until: float = float(frame.get("time_seconds", 0.0)) + 1.35
	left_regiment_entry["combat_lock_until"] = max(float(left_regiment_entry.get("combat_lock_until", -1.0)), melee_lock_until)
	right_regiment_entry["combat_lock_until"] = max(float(right_regiment_entry.get("combat_lock_until", -1.0)), melee_lock_until)
	left_regiment_entry["cohesion_delta"] = float(left_regiment_entry.get("cohesion_delta", 0.0)) - left_pressure_delta * 0.016
	right_regiment_entry["cohesion_delta"] = float(right_regiment_entry.get("cohesion_delta", 0.0)) - right_pressure_delta * 0.016

	if _should_break_in_melee(left_frame, left_entry, left_pressure_delta, int(edge.get("contact_side_left", CombatTypes.ContactSide.FRONT)), left_losses):
		left_entry["routed"] = true
		left_entry["suppression_delta"] = float(left_entry.get("suppression_delta", 0.0)) + 0.16
	if _should_break_in_melee(right_frame, right_entry, right_pressure_delta, int(edge.get("contact_side_right", CombatTypes.ContactSide.FRONT)), right_losses):
		right_entry["routed"] = true
		right_entry["suppression_delta"] = float(right_entry.get("suppression_delta", 0.0)) + 0.16

	last_melee_edges += 1
	last_melee_casualties += left_losses + right_losses

	if bool(left_entry.get("routed", false)) and not bool(right_entry.get("routed", false)):
		_append_event(outcome_buffer, "%s broke in melee against %s." % [left_company_id, right_company_id])
	elif bool(right_entry.get("routed", false)) and not bool(left_entry.get("routed", false)):
		_append_event(outcome_buffer, "%s broke in melee against %s." % [right_company_id, left_company_id])
	elif left_losses + right_losses >= 5:
		_append_event(outcome_buffer, "%s and %s locked in melee." % [left_company_id, right_company_id])


func _compute_melee_pressure(attacker_frame: Dictionary, defender_frame: Dictionary, target_contact_side: int, shared_frontage_length: float) -> float:
	var active_melee_capacity: float = float(attacker_frame.get("active_melee_capacity", 0.0))
	var attackers_available: float = max(active_melee_capacity, float(attacker_frame.get("soldier_share", 0.0)))
	if active_melee_capacity <= 0.05 or attackers_available <= 0.05:
		return 0.0
	var frontage_width: float = max(6.0, float(attacker_frame.get("width", attacker_frame.get("frontage_width", 10.0))))
	var frontage_ratio: float = clamp(shared_frontage_length / frontage_width, 0.25, 1.1)
	var engaged_count: float = min(active_melee_capacity, max(1.0, shared_frontage_length * 0.42))
	var engaged_ratio: float = engaged_count / max(0.001, attackers_available)
	var pressure: float = 0.15 \
		+ engaged_ratio * 0.72 \
		+ float(attacker_frame.get("morale", 0.72)) * 0.24 \
		+ float(attacker_frame.get("cohesion", 0.72)) * 0.27 \
		+ float(attacker_frame.get("training", 0.65)) * 0.18
	pressure *= clamp(1.0 - float(attacker_frame.get("suppression", 0.0)) * 0.35, 0.5, 1.0)
	pressure *= lerpf(0.82, 1.08, frontage_ratio)
	pressure *= _get_melee_role_matchup_multiplier(attacker_frame, defender_frame, target_contact_side)
	pressure *= clamp(1.0 - float(attacker_frame.get("reform_exposure", 0.0)) * 0.28, 0.62, 1.0)
	if int(attacker_frame.get("combat_posture", CombatTypes.CombatPosture.IDLE)) == CombatTypes.CombatPosture.CHARGE_RECOVER:
		pressure *= 0.84
	return pressure


func _get_melee_role_matchup_multiplier(attacker_frame: Dictionary, defender_frame: Dictionary, target_contact_side: int) -> float:
	var attacker_role: int = int(attacker_frame.get("combat_role", -1))
	var defender_role: int = int(defender_frame.get("combat_role", -1))
	var multiplier: float = 1.0
	match attacker_role:
		CombatTypes.CombatRole.MUSKET:
			if defender_role == CombatTypes.CombatRole.PIKE and target_contact_side == CombatTypes.ContactSide.FRONT:
				multiplier *= 0.92
			elif defender_role == CombatTypes.CombatRole.ARTILLERY:
				multiplier *= 1.18
		CombatTypes.CombatRole.PIKE:
			if defender_role == CombatTypes.CombatRole.CAVALRY:
				multiplier *= 1.34 if target_contact_side == CombatTypes.ContactSide.FRONT else 1.18
			elif defender_role == CombatTypes.CombatRole.MUSKET:
				multiplier *= 1.1
		CombatTypes.CombatRole.CAVALRY:
			if defender_role == CombatTypes.CombatRole.PIKE:
				if target_contact_side == CombatTypes.ContactSide.FRONT:
					multiplier *= 0.48 if bool(defender_frame.get("regiment_is_braced", false)) else 0.74
				else:
					multiplier *= 1.18
			elif defender_role == CombatTypes.CombatRole.MUSKET:
				multiplier *= 1.18
			elif defender_role == CombatTypes.CombatRole.ARTILLERY:
				multiplier *= 1.3
		CombatTypes.CombatRole.ARTILLERY:
			multiplier *= 0.58
	if target_contact_side in [CombatTypes.ContactSide.LEFT_FLANK, CombatTypes.ContactSide.RIGHT_FLANK]:
		multiplier *= 1.16
	elif target_contact_side == CombatTypes.ContactSide.REAR:
		multiplier *= 1.28
	return multiplier


func _compute_melee_casualties(
		incoming_pressure: float,
		defender_frame: Dictionary,
		attacker_frame: Dictionary,
		defender_contact_side: int,
		shared_frontage_length: float
) -> int:
	if incoming_pressure <= 0.05:
		return 0
	var defender_role: int = int(defender_frame.get("combat_role", -1))
	var attacker_role: int = int(attacker_frame.get("combat_role", -1))
	var frontage_scale: float = clamp(
		shared_frontage_length / max(6.0, min(float(defender_frame.get("width", defender_frame.get("frontage_width", 10.0))), float(attacker_frame.get("width", attacker_frame.get("frontage_width", 10.0))))),
		0.35,
		1.05
	)
	var defense_value: float = 0.74 \
		+ float(defender_frame.get("cohesion", 0.72)) * 0.36 \
		+ float(defender_frame.get("training", 0.65)) * 0.24 \
		+ float(defender_frame.get("charge_resistance", 0.0)) * 0.14
	defense_value *= clamp(1.0 - float(defender_frame.get("reform_exposure", 0.0)) * 0.24, 0.62, 1.0)
	if defender_role == CombatTypes.CombatRole.PIKE and attacker_role == CombatTypes.CombatRole.CAVALRY and defender_contact_side == CombatTypes.ContactSide.FRONT:
		defense_value += 0.38 if bool(defender_frame.get("regiment_is_braced", false)) else 0.18
	var exposure_multiplier: float = 1.0
	if defender_contact_side in [CombatTypes.ContactSide.LEFT_FLANK, CombatTypes.ContactSide.RIGHT_FLANK]:
		exposure_multiplier = 1.14
	elif defender_contact_side == CombatTypes.ContactSide.REAR:
		exposure_multiplier = 1.28
	var casualty_pressure: float = incoming_pressure * (1.78 + frontage_scale * 1.42) * exposure_multiplier
	var loss_value: float = max(0.0, casualty_pressure - defense_value)
	var casualty_cap: int = max(1, int(round(min(float(defender_frame.get("soldier_share", 1.0)), float(attacker_frame.get("soldier_share", 1.0))) * 0.24)))
	return clamp(int(round(loss_value * 0.85)), 0, casualty_cap)


func _should_break_in_melee(
		company_frame: Dictionary,
		outcome_entry: Dictionary,
		losing_pressure_delta: float,
		contact_side: int,
		incoming_casualties: int
) -> bool:
	if bool(outcome_entry.get("routed", false)):
		return true
	var projected_morale: float = clamp(
		float(company_frame.get("morale", 0.0)) + float(outcome_entry.get("morale_delta", 0.0)),
		0.0,
		1.0
	)
	var projected_cohesion: float = clamp(
		float(company_frame.get("cohesion", 0.0)) + float(outcome_entry.get("cohesion_delta", 0.0)),
		0.0,
		1.0
	)
	var shock_value: float = losing_pressure_delta
	if contact_side in [CombatTypes.ContactSide.LEFT_FLANK, CombatTypes.ContactSide.RIGHT_FLANK]:
		shock_value += 0.16
	elif contact_side == CombatTypes.ContactSide.REAR:
		shock_value += 0.28
	shock_value += float(company_frame.get("reform_exposure", 0.0)) * 0.12
	return projected_morale < 0.16 \
		or projected_cohesion < 0.14 \
		or (shock_value > 0.34 and (projected_morale < 0.34 or projected_cohesion < 0.3)) \
		or (incoming_casualties >= 3 and projected_cohesion < 0.24)


func _resolve_charge_edge(frame: Dictionary, left_frame: Dictionary, right_frame: Dictionary, edge: Dictionary, outcome_buffer: Dictionary) -> void:
	var attacker_frame: Dictionary = left_frame
	var defender_frame: Dictionary = right_frame
	if attacker_frame.is_empty() or defender_frame.is_empty():
		return
	var attacker_company_id: String = str(attacker_frame.get("company_id", ""))
	var defender_company_id: String = str(defender_frame.get("company_id", ""))
	var defender_contact_side: int = int(edge.get("contact_side_right", CombatTypes.ContactSide.NONE)) if str(edge.get("left_company_id", "")) == attacker_company_id else int(edge.get("contact_side_left", CombatTypes.ContactSide.NONE))
	if int(attacker_frame.get("combat_order_mode", CombatTypes.CombatOrderMode.NONE)) != CombatTypes.CombatOrderMode.CHARGE:
		return
	if int(attacker_frame.get("combat_posture", CombatTypes.CombatPosture.IDLE)) != CombatTypes.CombatPosture.CHARGE_WINDUP:
		return
	if float(attacker_frame.get("charge_recovery_until", -1.0)) > float(frame.get("time_seconds", 0.0)):
		return
	if bool(attacker_frame.get("is_routed", false)) or bool(defender_frame.get("is_routed", false)):
		return

	var impact_strength: float = 0.34 \
		+ float(attacker_frame.get("morale", 0.75)) * 0.28 \
		+ float(attacker_frame.get("cohesion", 0.75)) * 0.26 \
		+ float(attacker_frame.get("charge_bonus", 0.0)) * 0.24
	impact_strength *= clamp(1.0 - float(attacker_frame.get("reform_exposure", 0.0)) * 0.28, 0.66, 1.0)
	var defender_brace: float = float(defender_frame.get("brace_value", 0.0))
	var defender_braced: bool = bool(defender_frame.get("regiment_is_braced", false))
	var defender_frontally_braced: bool = defender_contact_side == CombatTypes.ContactSide.FRONT and defender_braced
	var defender_role: int = int(defender_frame.get("combat_role", -1))
	var brace_multiplier: float = 1.25 if defender_frontally_braced else (0.65 if defender_contact_side == CombatTypes.ContactSide.FRONT else 0.0)
	if float(defender_frame.get("reform_exposure", 0.0)) > 0.0:
		brace_multiplier *= clamp(1.0 - float(defender_frame.get("reform_exposure", 0.0)) * 0.5, 0.45, 1.0)
	var pike_wall_bonus: float = 0.0
	if defender_role == CombatTypes.CombatRole.PIKE and defender_contact_side == CombatTypes.ContactSide.FRONT:
		pike_wall_bonus = 0.82 if defender_braced else 0.28
		pike_wall_bonus *= clamp(1.0 - float(defender_frame.get("reform_exposure", 0.0)) * 0.55, 0.35, 1.0)
	var shock_delta: float = impact_strength - defender_brace * brace_multiplier - pike_wall_bonus
	var attacker_entry: Dictionary = _get_or_create_company_outcome(outcome_buffer, attacker_company_id)
	var defender_entry: Dictionary = _get_or_create_company_outcome(outcome_buffer, defender_company_id)
	if bool(attacker_entry.get("charge_broken", false)):
		return
	var attacker_regiment_entry: Dictionary = _get_or_create_regiment_outcome(outcome_buffer, str(attacker_frame.get("regiment_id", "")))
	var defender_regiment_entry: Dictionary = _get_or_create_regiment_outcome(outcome_buffer, str(defender_frame.get("regiment_id", "")))
	if bool(attacker_regiment_entry.get("charge_resolved", false)):
		return
	var time_seconds: float = float(frame.get("time_seconds", 0.0))
	var charge_lock_until: float = time_seconds + 1.35
	attacker_regiment_entry["combat_lock_until"] = max(float(attacker_regiment_entry.get("combat_lock_until", -1.0)), charge_lock_until)
	defender_regiment_entry["combat_lock_until"] = max(float(defender_regiment_entry.get("combat_lock_until", -1.0)), charge_lock_until)
	attacker_regiment_entry["charge_resolved"] = true
	attacker_entry["charge_broken"] = true

	if shock_delta <= 0.0:
		var recoil_casualties: int = 1 + int(round(absf(shock_delta) * 3.2))
		if defender_role == CombatTypes.CombatRole.PIKE and defender_contact_side == CombatTypes.ContactSide.FRONT:
			recoil_casualties += 2 if defender_braced else 1
		recoil_casualties = min(recoil_casualties, max(1, int(round(float(attacker_frame.get("soldier_share", 1.0)) * 0.28))))
		attacker_entry["casualties"] = int(attacker_entry.get("casualties", 0)) + recoil_casualties
		attacker_entry["morale_delta"] = float(attacker_entry.get("morale_delta", 0.0)) - 0.07 - absf(shock_delta) * 0.05
		attacker_entry["cohesion_delta"] = float(attacker_entry.get("cohesion_delta", 0.0)) - 0.14 - absf(shock_delta) * 0.1
		attacker_entry["suppression_delta"] = float(attacker_entry.get("suppression_delta", 0.0)) + 0.07
		defender_entry["cohesion_delta"] = float(defender_entry.get("cohesion_delta", 0.0)) - 0.01
		attacker_regiment_entry["forced_posture"] = CombatTypes.CombatPosture.MELEE
		defender_regiment_entry["forced_posture"] = CombatTypes.CombatPosture.MELEE
		if defender_frontally_braced:
			defender_regiment_entry["brace_until"] = max(float(defender_regiment_entry.get("brace_until", -1.0)), time_seconds + 1.4)
		last_charge_impacts += 1
		last_charge_casualties += recoil_casualties
		_append_event(outcome_buffer, "%s charge was repulsed by %s." % [attacker_company_id, defender_company_id])
		return

	var flank_or_rear_bonus: float = 0.0
	if defender_contact_side in [CombatTypes.ContactSide.LEFT_FLANK, CombatTypes.ContactSide.RIGHT_FLANK]:
		flank_or_rear_bonus = 0.22
	elif defender_contact_side == CombatTypes.ContactSide.REAR:
		flank_or_rear_bonus = 0.34
	var defender_casualties: int = 2 + int(round(shock_delta * 4.2 + flank_or_rear_bonus * 6.5))
	defender_casualties = min(defender_casualties, max(1, int(round(float(defender_frame.get("soldier_share", 1.0)) * 0.34))))
	defender_entry["casualties"] = int(defender_entry.get("casualties", 0)) + defender_casualties
	defender_entry["morale_delta"] = float(defender_entry.get("morale_delta", 0.0)) - 0.07 - shock_delta * 0.05 - flank_or_rear_bonus * 0.12
	defender_entry["cohesion_delta"] = float(defender_entry.get("cohesion_delta", 0.0)) - 0.08 - shock_delta * 0.07 - flank_or_rear_bonus * 0.18
	defender_entry["suppression_delta"] = float(defender_entry.get("suppression_delta", 0.0)) + 0.08
	attacker_entry["cohesion_delta"] = float(attacker_entry.get("cohesion_delta", 0.0)) - 0.04
	attacker_regiment_entry["forced_posture"] = CombatTypes.CombatPosture.MELEE
	defender_regiment_entry["forced_posture"] = CombatTypes.CombatPosture.MELEE
	last_charge_impacts += 1
	last_charge_casualties += defender_casualties
	_append_event(outcome_buffer, "%s charge hit %s." % [attacker_company_id, defender_company_id])
