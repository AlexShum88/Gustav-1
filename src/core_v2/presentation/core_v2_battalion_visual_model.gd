class_name CoreV2BattalionVisualModel
extends RefCounted


const MIN_FRONTAGE_M: float = 32.0
const MIN_DEPTH_M: float = 20.0
const MAX_DOCTRINE_CUES: int = 18


static func from_snapshot(battalion_snapshot: Dictionary) -> Dictionary:
	var visual_state: Dictionary = battalion_snapshot.get("visual_state", {})
	var category: int = int(battalion_snapshot.get("category", CoreV2Types.UnitCategory.INFANTRY))
	var formation_state: int = int(visual_state.get("formation_state", battalion_snapshot.get("formation_state", CoreV2Types.FormationState.LINE)))
	var frontage_m: float = max(MIN_FRONTAGE_M, float(visual_state.get("frontage_m", battalion_snapshot.get("formation_frontage_m", 120.0))))
	var depth_m: float = max(MIN_DEPTH_M, float(visual_state.get("depth_m", battalion_snapshot.get("formation_depth_m", 48.0))))
	var desired_formation_state: int = int(battalion_snapshot.get("desired_formation_state", formation_state))
	var desired_frontage_m: float = max(MIN_FRONTAGE_M, float(battalion_snapshot.get("desired_formation_frontage_m", frontage_m)))
	var disorder_band: float = clamp(float(visual_state.get("disorder_band", battalion_snapshot.get("disorder", 0.0))), 0.0, 1.0)
	var smoke_burden: float = clamp(float(visual_state.get("smoke_burden", battalion_snapshot.get("smoke_burden", 0.0))), 0.0, 1.0)
	var pike_ratio: float = clamp(float(visual_state.get("pike_ratio", battalion_snapshot.get("pike_ratio", 0.35))), 0.0, 1.0)
	var shot_ratio: float = clamp(float(visual_state.get("shot_ratio", battalion_snapshot.get("shot_ratio", 0.65))), 0.0, 1.0)
	var compression_level: float = clamp(float(visual_state.get("compression_level", battalion_snapshot.get("compression_level", 0.0))), 0.0, 1.0)
	var contact_pressure: float = clamp(float(visual_state.get("contact_pressure", battalion_snapshot.get("contact_pressure", 0.0))), 0.0, 1.0)
	var recoil_tendency: float = clamp(float(visual_state.get("recoil_tendency", battalion_snapshot.get("recoil_tendency", 0.0))), 0.0, 1.0)
	var terrain_distortion: float = clamp(float(visual_state.get("terrain_distortion", battalion_snapshot.get("terrain_distortion", 0.0))), 0.0, 1.0)
	var formation_progress: float = clamp(float(visual_state.get("formation_progress", battalion_snapshot.get("formation_progress", 1.0))), 0.0, 1.0)
	var transition_strain: float = 1.0 - formation_progress if bool(battalion_snapshot.get("is_reforming", false)) else 0.0
	if bool(battalion_snapshot.get("is_reforming", false)):
		var transition_t: float = _smoothstep01(formation_progress)
		frontage_m = lerp(frontage_m, desired_frontage_m, transition_t)
		depth_m = lerp(depth_m, _estimate_desired_depth_m(category, desired_formation_state, desired_frontage_m, battalion_snapshot), transition_t)
	var locked_in_melee: bool = bool(visual_state.get("locked_in_melee", battalion_snapshot.get("locked_in_melee", false)))
	var melee_pressure: float = clamp(float(visual_state.get("combat_melee_pressure", battalion_snapshot.get("combat_melee_pressure", 0.0))), 0.0, 1.0)
	var firing_smoke: float = 0.18 if String(visual_state.get("combat_attack_kind", battalion_snapshot.get("combat_attack_kind", ""))) in ["musket", "artillery"] else 0.0
	var smoke_intensity: float = clamp(max(smoke_burden, firing_smoke), 0.0, 1.0)
	var battalion_color: Color = battalion_snapshot.get("color", Color(1.0, 1.0, 1.0))
	var visual_irregularity: float = clamp(
		disorder_band * 0.54
		+ terrain_distortion * 0.25
		+ contact_pressure * 0.30
		+ recoil_tendency * 0.25
		+ transition_strain * 0.18,
		0.04,
		1.0
	)
	var visual_frontage_m: float = frontage_m * (1.0 + disorder_band * 0.08 - compression_level * 0.07 - contact_pressure * 0.03)
	var visual_depth_m: float = depth_m * (1.0 + disorder_band * 0.15 - compression_level * 0.13 + recoil_tendency * 0.08 + transition_strain * 0.06)
	var pike_width_m: float = max(8.0, visual_frontage_m * clamp(pike_ratio, 0.12, 0.62))
	var shot_width_m: float = max(5.0, max(0.0, visual_frontage_m - pike_width_m) * 0.5)
	var body_height_m: float = 6.5 + disorder_band * 2.2 + contact_pressure * 1.4 + transition_strain * 1.0
	var mass_color: Color = battalion_color.lerp(Color(0.42, 0.38, 0.31, 1.0), smoke_burden * 0.35).darkened(disorder_band * 0.18)
	var cue_pressure_state: float = clamp(contact_pressure + recoil_tendency * 0.65 + melee_pressure * 0.55 + (0.35 if locked_in_melee else 0.0), 0.0, 1.0)
	return {
		"category": category,
		"formation_state": formation_state,
		"visual_frontage_m": max(MIN_FRONTAGE_M, visual_frontage_m),
		"visual_depth_m": max(MIN_DEPTH_M, visual_depth_m),
		"body_height_m": body_height_m,
		"visual_irregularity": visual_irregularity,
		"compression_level": compression_level,
		"contact_pressure": contact_pressure,
		"recoil_tendency": recoil_tendency,
		"terrain_distortion": terrain_distortion,
		"disorder_band": disorder_band,
		"smoke_intensity": smoke_intensity,
		"smoke_burden": smoke_burden,
		"pike_ratio": pike_ratio,
		"shot_ratio": shot_ratio,
		"pike_width_m": pike_width_m,
		"shot_width_m": shot_width_m,
		"subzone_height_m": body_height_m + 1.4,
		"mass_color": mass_color,
		"shot_color": battalion_color.darkened(0.12).lerp(Color(0.82, 0.82, 0.76, 1.0), smoke_burden * 0.22),
		"battalion_color": battalion_color,
		"shape_seed": String(battalion_snapshot.get("id", "")).hash(),
		"locked_in_melee": locked_in_melee,
		"combat_melee_pressure": melee_pressure,
		"transition_strain": transition_strain,
		"cue_pressure_state": cue_pressure_state,
		"pike_cue_count": _resolve_pike_cue_count(category, pike_ratio, visual_frontage_m, visual_depth_m),
		"shot_cue_count_per_wing": _resolve_shot_cue_count_per_wing(category, shot_ratio, visual_frontage_m),
	}


static func geometry_signature_source(battalion_snapshot: Dictionary) -> Dictionary:
	var model: Dictionary = from_snapshot(battalion_snapshot)
	var movement_direction: Vector3 = _resolve_snapshot_movement_direction(battalion_snapshot)
	return {
		"formation_state": int(model.get("formation_state", CoreV2Types.FormationState.LINE)),
		"frontage_bucket": int(round(float(model.get("visual_frontage_m", 120.0)) / 4.0)),
		"depth_bucket": int(round(float(model.get("visual_depth_m", 48.0)) / 4.0)),
		"disorder_bucket": int(round(float(model.get("disorder_band", 0.0)) * 10.0)),
		"smoke_bucket": int(round(float(model.get("smoke_intensity", 0.0)) * 10.0)),
		"pike_bucket": int(round(float(model.get("pike_ratio", 0.35)) * 20.0)),
		"shot_bucket": int(round(float(model.get("shot_ratio", 0.65)) * 20.0)),
		"compression_bucket": int(round(float(model.get("compression_level", 0.0)) * 12.0)),
		"contact_bucket": int(round(float(model.get("contact_pressure", 0.0)) * 12.0)),
		"recoil_bucket": int(round(float(model.get("recoil_tendency", 0.0)) * 10.0)),
		"transition_bucket": int(round(float(model.get("transition_strain", 0.0)) * 10.0)),
		"cue_pressure_bucket": int(round(float(model.get("cue_pressure_state", 0.0)) * 10.0)),
		"status": int(battalion_snapshot.get("status", CoreV2Types.UnitStatus.IDLE)),
		"movement_x_bucket": int(round(movement_direction.x * 10.0)),
		"movement_z_bucket": int(round(movement_direction.z * 10.0)),
		"formation_pressure_direction": battalion_snapshot.get("formation_pressure_direction", Vector3.ZERO),
		"formation_pressure_bucket": int(round(float(battalion_snapshot.get("formation_pressure_m", 0.0)) / 2.0)),
		"casualties_bucket": int(round(float(int(battalion_snapshot.get("recent_casualties_taken", 0))) / 5.0)),
		"terrain_speed_bucket": int(round(float(battalion_snapshot.get("terrain_speed_multiplier", 1.0)) * 10.0)),
	}


static func _resolve_pike_cue_count(category: int, pike_ratio: float, frontage_m: float, depth_m: float) -> int:
	if category != CoreV2Types.UnitCategory.INFANTRY:
		return 0
	var density_count: int = int(round(clamp(frontage_m / 28.0 + depth_m / 24.0, 4.0, float(MAX_DOCTRINE_CUES))))
	return int(clamp(round(float(density_count) * clamp(pike_ratio, 0.18, 0.62)), 3.0, float(MAX_DOCTRINE_CUES)))


static func _resolve_shot_cue_count_per_wing(category: int, shot_ratio: float, frontage_m: float) -> int:
	if category != CoreV2Types.UnitCategory.INFANTRY:
		return 0
	var density_count: int = int(round(clamp(frontage_m / 24.0, 4.0, float(MAX_DOCTRINE_CUES))))
	return int(clamp(round(float(density_count) * clamp(shot_ratio, 0.25, 0.80) * 0.5), 2.0, float(MAX_DOCTRINE_CUES)))


static func _resolve_snapshot_movement_direction(battalion_snapshot: Dictionary) -> Vector3:
	var position: Vector3 = battalion_snapshot.get("position", Vector3.ZERO)
	var active_target: Vector3 = battalion_snapshot.get("target_position", position)
	var movement_path: Array = battalion_snapshot.get("movement_path", [])
	if not movement_path.is_empty():
		active_target = movement_path[0]
	var movement: Vector3 = active_target - position
	movement.y = 0.0
	if movement.length_squared() <= 0.001:
		return Vector3.ZERO
	return movement.normalized()


static func _estimate_desired_depth_m(category: int, desired_formation_state: int, desired_frontage_m: float, battalion_snapshot: Dictionary) -> float:
	if category == CoreV2Types.UnitCategory.CAVALRY:
		return max(MIN_DEPTH_M, desired_frontage_m * 0.42)
	if category == CoreV2Types.UnitCategory.ARTILLERY:
		return max(MIN_DEPTH_M, desired_frontage_m * 0.34)
	var soldier_factor: float = clamp(sqrt(float(max(1, int(battalion_snapshot.get("soldiers_total", 1000))))) / 32.0, 0.70, 1.35)
	match desired_formation_state:
		CoreV2Types.FormationState.MUSKETEER_LINE:
			return max(MIN_DEPTH_M, desired_frontage_m * 0.24 * soldier_factor)
		CoreV2Types.FormationState.LINE:
			return max(MIN_DEPTH_M, desired_frontage_m * 0.30 * soldier_factor)
		CoreV2Types.FormationState.TERCIA:
			return max(58.0, desired_frontage_m * 0.68 * soldier_factor)
		CoreV2Types.FormationState.DEFENSIVE:
			return max(62.0, desired_frontage_m * 0.62)
		CoreV2Types.FormationState.COLUMN:
			return max(70.0, desired_frontage_m * 1.10)
		CoreV2Types.FormationState.MARCH_COLUMN:
			return max(92.0, desired_frontage_m * 1.85)
		_:
			return max(MIN_DEPTH_M, desired_frontage_m * 0.36 * soldier_factor)


static func _smoothstep01(value: float) -> float:
	var t: float = clamp(value, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)
