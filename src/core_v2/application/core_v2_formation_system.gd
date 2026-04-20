class_name CoreV2FormationSystem
extends RefCounted


const SPRITE_SPACING_M: float = 10.0
const REFORM_SPEED_MPS: float = 22.0
const MIN_REFORM_DURATION_SECONDS: float = 1.6
const MAX_REFORM_DURATION_SECONDS: float = 12.0
const FRONTAGE_REFORM_EPSILON_M: float = 6.0
const MIN_FLEX_FRONTAGE_M: float = 32.0
const MAX_LINE_RANKS: int = 5
const SOFT_SPRING_PER_SECOND: float = 9.0
const REFORM_SPRING_PER_SECOND: float = 6.5
const SOFT_VELOCITY_DAMPING_PER_SECOND: float = 5.4
const INTERNAL_REFORM_SPEED_SHARE: float = 0.55
const MIN_INTERNAL_REFORM_SPEED_MPS: float = 2.5
const MAX_INTERNAL_REFORM_SPEED_MPS: float = 14.0
const FORMATION_ARRIVAL_EPSILON_M: float = 2.0
const FORMATION_ARRIVAL_SPEED_EPSILON_MPS: float = 0.9
const LAYOUT_MATCH_EPSILON_M: float = 0.25
const MOVEMENT_REAR_LAG_M: float = 14.0
const MOVEMENT_FLANK_BEND_M: float = 9.0
const PRESSURE_DEFORMATION_M: float = 18.0
const PRESSURE_DECAY_PER_SECOND: float = 7.5
const ROUGH_TERRAIN_LAG_M: float = 10.0
const COMBAT_DISORDER_M: float = 7.0


static func initialize_battalion(battalion: CoreV2Battalion) -> void:
	var requested_frontage_m: float = _resolve_requested_frontage_m(battalion, battalion.formation_state, battalion.formation_frontage_m)
	var layout: Dictionary = build_layout(battalion, battalion.formation_state, requested_frontage_m)
	battalion.desired_formation_state = battalion.formation_state
	battalion.sprite_offsets = layout.get("offsets", []).duplicate(true)
	battalion.sprite_offset_velocities = _build_zero_velocities(battalion.sprite_offsets.size())
	battalion.sprite_target_offsets = battalion.sprite_offsets.duplicate(true)
	battalion.sprite_reform_from_offsets = battalion.sprite_offsets.duplicate(true)
	battalion.sprite_roles = layout.get("roles", []).duplicate(true)
	battalion.formation_frontage_m = float(layout.get("frontage_m", requested_frontage_m))
	battalion.formation_depth_m = float(layout.get("depth_m", battalion.formation_depth_m))
	battalion.desired_formation_frontage_m = battalion.formation_frontage_m
	battalion.formation_elapsed_seconds = 0.0
	battalion.formation_duration_seconds = MIN_REFORM_DURATION_SECONDS
	battalion.formation_progress = 1.0
	battalion.is_reforming = false
	battalion.formation_pressure_direction = Vector3.ZERO
	battalion.formation_pressure_m = 0.0
	battalion.sync_sprite_blocks()


static func request_formation(battalion: CoreV2Battalion, next_formation_state: int, requested_frontage_m: float = -1.0) -> void:
	if battalion.sprite_offsets.size() != battalion.sprite_count:
		initialize_battalion(battalion)
	_ensure_soft_state(battalion)
	var next_frontage_m: float = _resolve_requested_frontage_m(battalion, next_formation_state, requested_frontage_m)
	var next_layout: Dictionary = build_layout(battalion, next_formation_state, next_frontage_m)
	var next_offsets: Array = next_layout.get("offsets", [])
	if next_offsets.size() != battalion.sprite_count:
		return
	var same_layout_request: bool = battalion.desired_formation_state == next_formation_state
	same_layout_request = same_layout_request and absf(battalion.desired_formation_frontage_m - next_frontage_m) <= FRONTAGE_REFORM_EPSILON_M
	same_layout_request = same_layout_request and _offsets_match(battalion.sprite_target_offsets, next_offsets, LAYOUT_MATCH_EPSILON_M)
	if same_layout_request:
		return

	battalion.desired_formation_state = next_formation_state
	battalion.desired_formation_frontage_m = float(next_layout.get("frontage_m", next_frontage_m))
	battalion.formation_depth_m = float(next_layout.get("depth_m", battalion.formation_depth_m))
	battalion.sprite_reform_from_offsets = battalion.sprite_offsets.duplicate(true)
	battalion.sprite_target_offsets = next_offsets.duplicate(true)
	battalion.sprite_roles = next_layout.get("roles", []).duplicate(true)
	battalion.formation_elapsed_seconds = 0.0
	battalion.formation_duration_seconds = _estimate_reform_duration(
		battalion.sprite_reform_from_offsets,
		battalion.sprite_target_offsets
	)
	battalion.formation_progress = 0.0
	battalion.is_reforming = true
	battalion.sync_sprite_blocks()


static func force_formation(battalion: CoreV2Battalion, next_formation_state: int) -> void:
	var requested_frontage_m: float = _resolve_requested_frontage_m(battalion, next_formation_state, battalion.desired_formation_frontage_m)
	var next_layout: Dictionary = build_layout(battalion, next_formation_state, requested_frontage_m)
	var next_offsets: Array = next_layout.get("offsets", [])
	if next_offsets.size() != battalion.sprite_count:
		return
	battalion.formation_state = next_formation_state
	battalion.desired_formation_state = next_formation_state
	battalion.formation_frontage_m = float(next_layout.get("frontage_m", requested_frontage_m))
	battalion.formation_depth_m = float(next_layout.get("depth_m", battalion.formation_depth_m))
	battalion.desired_formation_frontage_m = battalion.formation_frontage_m
	battalion.sprite_offsets = next_offsets.duplicate(true)
	battalion.sprite_offset_velocities = _build_zero_velocities(battalion.sprite_offsets.size())
	battalion.sprite_target_offsets = battalion.sprite_offsets.duplicate(true)
	battalion.sprite_reform_from_offsets = battalion.sprite_offsets.duplicate(true)
	battalion.sprite_roles = next_layout.get("roles", []).duplicate(true)
	battalion.formation_elapsed_seconds = 0.0
	battalion.formation_duration_seconds = MIN_REFORM_DURATION_SECONDS
	battalion.formation_progress = 1.0
	battalion.is_reforming = false
	battalion.sync_sprite_blocks()


static func advance_battalion(battalion: CoreV2Battalion, delta: float, terrain_state = null) -> void:
	if delta <= 0.0:
		return
	if battalion.sprite_offsets.size() != battalion.sprite_count:
		initialize_battalion(battalion)
	_ensure_soft_state(battalion)
	if battalion.is_reforming:
		var reform_rate_multiplier: float = _resolve_reform_rate_multiplier(battalion, terrain_state)
		battalion.formation_elapsed_seconds += delta * reform_rate_multiplier
		battalion.formation_progress = clamp(
			battalion.formation_elapsed_seconds / max(battalion.formation_duration_seconds, 0.001),
			0.0,
			1.0
		)
		if battalion.formation_progress >= 1.0:
			battalion.formation_state = battalion.desired_formation_state
			battalion.formation_frontage_m = battalion.desired_formation_frontage_m
			battalion.formation_depth_m = float(_measure_layout(battalion.sprite_target_offsets).get("depth_m", battalion.formation_depth_m))
			battalion.sprite_offsets = battalion.sprite_target_offsets.duplicate(true)
			battalion.sprite_reform_from_offsets = battalion.sprite_offsets.duplicate(true)
			battalion.sprite_offset_velocities = _build_zero_velocities(battalion.sprite_offsets.size())
			battalion.is_reforming = false
	_decay_pressure(battalion, delta)
	battalion.sync_sprite_blocks(terrain_state)


static func choose_formation_for_order(battalion: CoreV2Battalion, order: CoreV2Order, policies: Dictionary) -> int:
	if order == null:
		return battalion.desired_formation_state
	var road_column: bool = bool(policies.get("road_column", false))
	var flexible_formation: bool = bool(policies.get("flexible_formation", false))
	match order.order_type:
		CoreV2Types.OrderType.MARCH:
			return CoreV2Types.FormationState.MARCH_COLUMN
		CoreV2Types.OrderType.MOVE:
			if flexible_formation:
				return CoreV2Types.FormationState.LINE
			return CoreV2Types.FormationState.COLUMN if road_column else CoreV2Types.FormationState.LINE
		CoreV2Types.OrderType.ATTACK:
			if battalion.category == CoreV2Types.UnitCategory.CAVALRY:
				return CoreV2Types.FormationState.LINE if flexible_formation else CoreV2Types.FormationState.COLUMN
			return CoreV2Types.FormationState.MUSKETEER_LINE
		CoreV2Types.OrderType.MELEE_ASSAULT:
			return CoreV2Types.FormationState.LINE
		CoreV2Types.OrderType.DEFEND:
			return CoreV2Types.FormationState.LINE
		CoreV2Types.OrderType.HOLD:
			return CoreV2Types.FormationState.DEFENSIVE if battalion.category == CoreV2Types.UnitCategory.INFANTRY else CoreV2Types.FormationState.LINE
		CoreV2Types.OrderType.PATROL:
			if flexible_formation:
				return CoreV2Types.FormationState.LINE
			return CoreV2Types.FormationState.MARCH_COLUMN if road_column else CoreV2Types.FormationState.COLUMN
		_:
			return battalion.desired_formation_state


static func build_layout(battalion: CoreV2Battalion, formation_state: int, requested_frontage_m: float = -1.0) -> Dictionary:
	var frontage_m: float = _resolve_requested_frontage_m(battalion, formation_state, requested_frontage_m)
	if battalion.category == CoreV2Types.UnitCategory.CAVALRY:
		return _build_cavalry_layout(battalion.sprite_count, formation_state, frontage_m)
	if battalion.category == CoreV2Types.UnitCategory.ARTILLERY:
		return _build_artillery_layout(battalion.sprite_count)
	return _build_infantry_layout(battalion.sprite_count, formation_state, frontage_m)


static func _build_infantry_layout(sprite_count: int, formation_state: int, frontage_m: float) -> Dictionary:
	match formation_state:
		CoreV2Types.FormationState.MUSKETEER_LINE:
			return _build_musketeer_line(sprite_count, frontage_m)
		CoreV2Types.FormationState.DEFENSIVE:
			return _build_defensive_square(sprite_count)
		CoreV2Types.FormationState.TERCIA:
			return _build_tercia(sprite_count)
		CoreV2Types.FormationState.COLUMN:
			return _build_grid_layout(sprite_count, 4, SPRITE_SPACING_M * 0.9, SPRITE_SPACING_M * 0.9, "mixed")
		CoreV2Types.FormationState.MARCH_COLUMN:
			return _build_grid_layout(sprite_count, 2, SPRITE_SPACING_M * 0.8, SPRITE_SPACING_M * 0.95, "mixed")
		_:
			return _build_line(sprite_count, frontage_m)


static func _build_cavalry_layout(sprite_count: int, formation_state: int, frontage_m: float) -> Dictionary:
	match formation_state:
		CoreV2Types.FormationState.MARCH_COLUMN:
			return _build_grid_layout(sprite_count, 2, SPRITE_SPACING_M, SPRITE_SPACING_M * 1.1, "cavalry")
		CoreV2Types.FormationState.COLUMN:
			return _build_grid_layout(sprite_count, 3, SPRITE_SPACING_M * 1.1, SPRITE_SPACING_M * 1.1, "cavalry")
		_:
			var columns: int = _columns_for_frontage(sprite_count, frontage_m, SPRITE_SPACING_M * 1.2, 3)
			return _build_grid_layout(sprite_count, columns, SPRITE_SPACING_M * 1.2, SPRITE_SPACING_M, "cavalry")


static func _build_artillery_layout(sprite_count: int) -> Dictionary:
	return _build_grid_layout(sprite_count, max(1, sprite_count), SPRITE_SPACING_M * 1.4, SPRITE_SPACING_M, "artillery")


static func _build_line(sprite_count: int, frontage_m: float) -> Dictionary:
	if sprite_count <= 0:
		return _normalize_layout([], [])
	var pike_min: int = min(2, sprite_count)
	var pike_max: int = max(pike_min, sprite_count - 2)
	var pike_count: int = min(sprite_count, int(clamp(int(round(float(sprite_count) * 0.35)), pike_min, pike_max)))
	var columns: int = _columns_for_frontage(sprite_count, frontage_m, SPRITE_SPACING_M, 2)
	var rows: int = int(ceil(float(sprite_count) / float(columns)))
	var pike_flags: Array = _build_center_role_flags(sprite_count, columns, rows, pike_count)
	var offsets: Array = []
	var roles: Array = []
	for index in range(sprite_count):
		var column: int = index % columns
		var row: int = int(floor(float(index) / float(columns)))
		offsets.append(Vector3(
			(float(column) - float(columns - 1) * 0.5) * SPRITE_SPACING_M,
			0.0,
			(float(rows - 1) * 0.5 - float(row)) * SPRITE_SPACING_M * 0.86
		))
		roles.append("pikeman" if bool(pike_flags[index]) else "musketeer")
	return _normalize_layout(offsets, roles)


static func _build_musketeer_line(sprite_count: int, frontage_m: float) -> Dictionary:
	if sprite_count <= 0:
		return _normalize_layout([], [])
	var pike_count: int = int(clamp(int(round(float(sprite_count) * 0.25)), 1, max(1, sprite_count - 1)))
	var musketeer_count: int = max(0, sprite_count - pike_count)
	var offsets: Array = []
	var roles: Array = []
	var musketeer_columns: int = _columns_for_frontage(musketeer_count, frontage_m, SPRITE_SPACING_M, 2)
	var pike_frontage_m: float = max(MIN_FLEX_FRONTAGE_M, min(frontage_m * 0.58, _default_frontage_for_count(pike_count, CoreV2Types.FormationState.LINE, CoreV2Types.UnitCategory.INFANTRY)))
	var pike_columns: int = _columns_for_frontage(pike_count, pike_frontage_m, SPRITE_SPACING_M * 0.9, 1)
	var musketeer_rows: int = int(ceil(float(max(1, musketeer_count)) / float(max(1, musketeer_columns))))
	var pike_rows: int = int(ceil(float(max(1, pike_count)) / float(max(1, pike_columns))))
	var gap_z: float = SPRITE_SPACING_M * 1.15
	var musketeer_center_z: float = float(pike_rows - 1) * SPRITE_SPACING_M * 0.42 + gap_z * 0.5
	var pike_center_z: float = -float(musketeer_rows - 1) * SPRITE_SPACING_M * 0.42 - gap_z * 0.5
	_append_ranked_segment(offsets, roles, musketeer_count, musketeer_columns, SPRITE_SPACING_M, SPRITE_SPACING_M * 0.84, musketeer_center_z, "musketeer")
	_append_ranked_segment(offsets, roles, pike_count, pike_columns, SPRITE_SPACING_M * 0.9, SPRITE_SPACING_M * 0.84, pike_center_z, "pikeman")
	return _normalize_layout(offsets, roles)


static func _build_defensive_square(sprite_count: int) -> Dictionary:
	if sprite_count <= 0:
		return _normalize_layout([], [])
	var pike_count: int = int(clamp(int(round(float(sprite_count) * 0.55)), min(4, sprite_count), sprite_count))
	var musketeer_count: int = max(0, sprite_count - pike_count)
	var offsets: Array = []
	var roles: Array = []
	var side_slots: int = max(2, int(ceil(float(pike_count) / 4.0)))
	var square_half: float = float(side_slots - 1) * SPRITE_SPACING_M * 0.75
	for index in range(pike_count):
		var side_index: int = int(floor(float(index) / float(side_slots)))
		var slot_index: int = index % side_slots
		var t: float = (float(slot_index) / max(1.0, float(side_slots - 1))) * 2.0 - 1.0
		match side_index % 4:
			0:
				offsets.append(Vector3(t * square_half, 0.0, square_half))
			1:
				offsets.append(Vector3(square_half, 0.0, -t * square_half))
			2:
				offsets.append(Vector3(-t * square_half, 0.0, -square_half))
			_:
				offsets.append(Vector3(-square_half, 0.0, t * square_half))
		roles.append("pikeman")
	if musketeer_count > 0:
		var center_layout: Dictionary = _build_grid_layout(musketeer_count, max(1, int(ceil(sqrt(float(musketeer_count))))), SPRITE_SPACING_M * 0.55, SPRITE_SPACING_M * 0.55, "musketeer")
		offsets.append_array(center_layout.get("offsets", []))
		roles.append_array(center_layout.get("roles", []))
	return _normalize_layout(offsets, roles)


static func _build_tercia(sprite_count: int) -> Dictionary:
	if sprite_count <= 0:
		return _normalize_layout([], [])
	var pike_min: int = min(4, sprite_count)
	var pike_max: int = max(pike_min, sprite_count - 4)
	var pike_count: int = min(sprite_count, int(clamp(int(round(float(sprite_count) * 0.45)), pike_min, pike_max)))
	var musketeer_count: int = max(0, sprite_count - pike_count)
	var offsets: Array = []
	var roles: Array = []
	var pike_layout: Dictionary = _build_grid_layout(pike_count, max(2, int(ceil(sqrt(float(pike_count))))), SPRITE_SPACING_M * 0.75, SPRITE_SPACING_M * 0.75, "pikeman")
	offsets.append_array(pike_layout.get("offsets", []))
	roles.append_array(pike_layout.get("roles", []))
	var corner_anchors: Array = [
		Vector3(-SPRITE_SPACING_M * 3.6, 0.0, SPRITE_SPACING_M * 3.6),
		Vector3(SPRITE_SPACING_M * 3.6, 0.0, SPRITE_SPACING_M * 3.6),
		Vector3(-SPRITE_SPACING_M * 3.6, 0.0, -SPRITE_SPACING_M * 3.6),
		Vector3(SPRITE_SPACING_M * 3.6, 0.0, -SPRITE_SPACING_M * 3.6),
	]
	for index in range(musketeer_count):
		var anchor: Vector3 = corner_anchors[index % corner_anchors.size()]
		var local_column: int = int(floor(float(index) / float(corner_anchors.size()))) % 2
		var local_row: int = int(floor(float(index) / float(corner_anchors.size() * 2)))
		offsets.append(anchor + Vector3(float(local_column) * SPRITE_SPACING_M * 0.45, 0.0, float(local_row) * SPRITE_SPACING_M * 0.45))
		roles.append("musketeer")
	return _normalize_layout(offsets, roles)


static func _build_grid_layout(sprite_count: int, columns: int, spacing_x: float, spacing_z: float, role: String) -> Dictionary:
	var offsets: Array = []
	var roles: Array = []
	var safe_columns: int = max(1, columns)
	var rows: int = int(ceil(float(max(1, sprite_count)) / float(safe_columns)))
	for index in range(sprite_count):
		var column: int = index % safe_columns
		var row: int = int(floor(float(index) / float(safe_columns)))
		offsets.append(Vector3(
			(float(column) - float(safe_columns - 1) * 0.5) * spacing_x,
			0.0,
			(float(row) - float(rows - 1) * 0.5) * spacing_z
		))
		roles.append(role)
	return _with_layout_metrics(offsets, roles)


static func _append_line_segment(offsets: Array, roles: Array, count: int, start_x: float, z: float, role: String) -> void:
	for index in range(count):
		offsets.append(Vector3(start_x + float(index) * SPRITE_SPACING_M, 0.0, z))
		roles.append(role)


static func _append_ranked_segment(
		offsets: Array,
		roles: Array,
		count: int,
		columns: int,
		spacing_x: float,
		spacing_z: float,
		center_z: float,
		role: String
) -> void:
	if count <= 0:
		return
	var safe_columns: int = max(1, columns)
	var rows: int = int(ceil(float(count) / float(safe_columns)))
	for index in range(count):
		var column: int = index % safe_columns
		var row: int = int(floor(float(index) / float(safe_columns)))
		offsets.append(Vector3(
			(float(column) - float(safe_columns - 1) * 0.5) * spacing_x,
			0.0,
			center_z + (float(rows - 1) * 0.5 - float(row)) * spacing_z
		))
		roles.append(role)


static func _columns_for_frontage(sprite_count: int, frontage_m: float, spacing_x: float, minimum_columns: int) -> int:
	if sprite_count <= 0:
		return 1
	var max_columns: int = max(1, sprite_count)
	var min_columns: int = min(max_columns, max(1, minimum_columns))
	var safe_spacing: float = max(1.0, spacing_x)
	var requested_columns: int = int(round(max(0.0, frontage_m) / safe_spacing)) + 1
	var max_columns_for_ranks: int = max(min_columns, int(ceil(float(sprite_count) / float(MAX_LINE_RANKS))))
	requested_columns = max(requested_columns, max(min_columns, max_columns_for_ranks))
	return int(clamp(requested_columns, min_columns, max_columns))


static func _build_center_role_flags(sprite_count: int, columns: int, rows: int, role_count: int) -> Array:
	var flags: Array = []
	for _index in range(sprite_count):
		flags.append(false)
	if sprite_count <= 0 or role_count <= 0:
		return flags
	var safe_columns: int = max(1, columns)
	var safe_rows: int = max(1, rows)
	var role_columns: int = int(clamp(int(ceil(float(role_count) / float(safe_rows))), 1, safe_columns))
	var first_role_column: int = int(floor(float(safe_columns - role_columns) * 0.5))
	var assigned_count: int = 0
	for row in range(safe_rows):
		for column_offset in range(role_columns):
			var column: int = first_role_column + column_offset
			var sprite_index: int = row * safe_columns + column
			if sprite_index < 0 or sprite_index >= sprite_count:
				continue
			flags[sprite_index] = true
			assigned_count += 1
			if assigned_count >= role_count:
				return flags
	return flags


static func _build_zero_velocities(count: int) -> Array:
	var velocities: Array = []
	for _index in range(count):
		velocities.append(Vector3.ZERO)
	return velocities


static func _ensure_soft_state(battalion: CoreV2Battalion) -> void:
	while battalion.sprite_offset_velocities.size() > battalion.sprite_count:
		battalion.sprite_offset_velocities.pop_back()
	while battalion.sprite_offset_velocities.size() < battalion.sprite_count:
		battalion.sprite_offset_velocities.append(Vector3.ZERO)
	if battalion.sprite_target_offsets.size() != battalion.sprite_count:
		var layout: Dictionary = build_layout(battalion, battalion.desired_formation_state, battalion.desired_formation_frontage_m)
		battalion.sprite_target_offsets = layout.get("offsets", []).duplicate(true)
	if battalion.sprite_reform_from_offsets.size() != battalion.sprite_count:
		battalion.sprite_reform_from_offsets = battalion.sprite_offsets.duplicate(true)


static func _resolve_reform_rate_multiplier(battalion: CoreV2Battalion, terrain_state) -> float:
	var terrain_speed: float = terrain_state.get_speed_multiplier_at(battalion.position, battalion.category) if terrain_state != null else 1.0
	# Перешикування великої маси людей сповільнюється на поганому терені та під фронтовим тиском.
	var condition_factor: float = clamp(
		1.0 - battalion.disorder * 0.35 - battalion.contact_pressure * 0.45 - battalion.compression_level * 0.30 - battalion.movement_strain * 0.25,
		0.20,
		1.0
	)
	return clamp(terrain_speed * condition_factor, 0.15, 1.15)


static func _resolve_ideal_offsets(battalion: CoreV2Battalion, delta: float) -> Array:
	if not battalion.is_reforming:
		return battalion.sprite_target_offsets.duplicate(true)
	battalion.formation_elapsed_seconds += delta
	battalion.formation_progress = clamp(
		battalion.formation_elapsed_seconds / max(battalion.formation_duration_seconds, 0.001),
		0.0,
		1.0
	)
	var eased_progress: float = _smoothstep(battalion.formation_progress)
	var ideal_offsets: Array = []
	for index in range(battalion.sprite_target_offsets.size()):
		var from_offset: Vector3 = battalion.sprite_reform_from_offsets[index]
		var target_offset: Vector3 = battalion.sprite_target_offsets[index]
		ideal_offsets.append(from_offset.lerp(target_offset, eased_progress))
	return ideal_offsets


static func _build_soft_target_offset(
		battalion: CoreV2Battalion,
		ideal_offset: Vector3,
		sprite_index: int,
		ideal_metrics: Dictionary,
		local_movement_direction: Vector3,
		local_pressure_direction: Vector3,
		terrain_state
) -> Vector3:
	var soft_target: Vector3 = ideal_offset
	var looseness: float = clamp(1.15 - battalion.cohesion * 0.65 - battalion.training * 0.35, 0.22, 0.95)
	if local_movement_direction.length_squared() > 0.001 and battalion.status == CoreV2Types.UnitStatus.MOVING:
		var movement_direction: Vector3 = local_movement_direction.normalized()
		var movement_side := Vector3(-movement_direction.z, 0.0, movement_direction.x).normalized()
		var radius_m: float = max(1.0, float(ideal_metrics.get("radius_m", SPRITE_SPACING_M)))
		var rear_factor: float = clamp(-ideal_offset.dot(movement_direction) / radius_m, 0.0, 1.0)
		var flank_factor: float = clamp(absf(ideal_offset.dot(movement_side)) / radius_m, 0.0, 1.0)
		soft_target -= movement_direction * (MOVEMENT_REAR_LAG_M * rear_factor + MOVEMENT_FLANK_BEND_M * flank_factor * flank_factor) * looseness
		soft_target += movement_side * sin(float(sprite_index) * 1.618) * flank_factor * looseness * 1.8
		soft_target += _resolve_terrain_lag(battalion, ideal_offset, movement_direction, movement_side, sprite_index, terrain_state) * looseness
	if local_pressure_direction.length_squared() > 0.001 and battalion.formation_pressure_m > 0.01:
		var pressure_direction: Vector3 = local_pressure_direction.normalized()
		var pressure_radius_m: float = max(1.0, float(ideal_metrics.get("radius_m", SPRITE_SPACING_M)))
		var contact_edge_factor: float = clamp(-ideal_offset.dot(pressure_direction) / pressure_radius_m, 0.0, 1.0)
		var pressure_strength: float = clamp(battalion.formation_pressure_m / 24.0, 0.0, 1.0)
		soft_target += pressure_direction * PRESSURE_DEFORMATION_M * contact_edge_factor * pressure_strength
		soft_target += Vector3(-pressure_direction.z, 0.0, pressure_direction.x) * sin(float(sprite_index) * 2.31) * pressure_strength * contact_edge_factor * 2.4
	var combat_disorder: float = _resolve_combat_disorder(battalion)
	if combat_disorder > 0.001:
		soft_target += Vector3(
			sin(float(sprite_index) * 3.17),
			0.0,
			cos(float(sprite_index) * 2.73)
		) * COMBAT_DISORDER_M * combat_disorder * looseness
	return soft_target


static func _resolve_terrain_lag(
		battalion: CoreV2Battalion,
		ideal_offset: Vector3,
		movement_direction: Vector3,
		movement_side: Vector3,
		sprite_index: int,
		terrain_state
) -> Vector3:
	if terrain_state == null:
		return Vector3.ZERO
	var world_position: Vector3 = battalion.position + _local_to_world_offset(ideal_offset, battalion.facing)
	var speed_multiplier: float = terrain_state.get_speed_multiplier_at(world_position, battalion.category)
	var roughness: float = clamp(1.0 - speed_multiplier, 0.0, 0.75)
	if roughness <= 0.01:
		return Vector3.ZERO
	return movement_direction * -ROUGH_TERRAIN_LAG_M * roughness + movement_side * sin(float(sprite_index) * 12.9898) * roughness * 2.5


static func _resolve_combat_disorder(battalion: CoreV2Battalion) -> float:
	if battalion.recent_casualties_taken <= 0:
		return 0.0
	var shock_scale: float = max(6.0, float(max(1, battalion.soldiers_total)) * 0.018)
	var casualty_shock: float = clamp(float(battalion.recent_casualties_taken) / shock_scale, 0.0, 1.0)
	var cohesion_multiplier: float = clamp(1.1 - battalion.cohesion, 0.2, 1.0)
	return casualty_shock * cohesion_multiplier


static func _get_internal_step_speed_mps(battalion: CoreV2Battalion, terrain_state) -> float:
	var speed_multiplier: float = terrain_state.get_speed_multiplier_at(battalion.position, battalion.category) if terrain_state != null else 1.0
	var discipline: float = clamp((battalion.cohesion + battalion.training) * 0.5, 0.25, 1.0)
	var step_speed_mps: float = battalion.move_speed_mps * max(0.1, speed_multiplier) * INTERNAL_REFORM_SPEED_SHARE * lerp(0.72, 1.08, discipline)
	return clamp(step_speed_mps, MIN_INTERNAL_REFORM_SPEED_MPS, MAX_INTERNAL_REFORM_SPEED_MPS)


static func _has_reached_target_offsets(battalion: CoreV2Battalion) -> bool:
	if battalion.sprite_offsets.size() != battalion.sprite_target_offsets.size():
		return false
	for index in range(battalion.sprite_offsets.size()):
		var current_offset: Vector3 = battalion.sprite_offsets[index]
		var target_offset: Vector3 = battalion.sprite_target_offsets[index]
		if current_offset.distance_to(target_offset) > FORMATION_ARRIVAL_EPSILON_M:
			return false
		var velocity: Vector3 = battalion.sprite_offset_velocities[index] if index < battalion.sprite_offset_velocities.size() else Vector3.ZERO
		if velocity.length() > FORMATION_ARRIVAL_SPEED_EPSILON_MPS:
			return false
	return true


static func _offsets_match(first_offsets: Array, second_offsets: Array, epsilon_m: float) -> bool:
	if first_offsets.size() != second_offsets.size():
		return false
	for index in range(first_offsets.size()):
		var first_offset: Vector3 = first_offsets[index]
		var second_offset: Vector3 = second_offsets[index]
		if first_offset.distance_to(second_offset) > epsilon_m:
			return false
	return true


static func _measure_layout(offsets: Array) -> Dictionary:
	var radius_m: float = SPRITE_SPACING_M
	var half_width_m: float = 0.0
	var half_depth_m: float = 0.0
	for offset_value in offsets:
		var offset: Vector3 = offset_value
		half_width_m = max(half_width_m, absf(offset.x))
		half_depth_m = max(half_depth_m, absf(offset.z))
		radius_m = max(radius_m, Vector2(offset.x, offset.z).length())
	return {
		"radius_m": radius_m,
		"half_width_m": half_width_m,
		"half_depth_m": half_depth_m,
	}


static func _resolve_movement_direction(battalion: CoreV2Battalion) -> Vector3:
	if battalion.status != CoreV2Types.UnitStatus.MOVING:
		return Vector3.ZERO
	var active_target: Vector3 = battalion.movement_path[0] if not battalion.movement_path.is_empty() else battalion.target_position
	var movement: Vector3 = active_target - battalion.position
	movement.y = 0.0
	if movement.length_squared() <= 0.001:
		return Vector3.ZERO
	return movement.normalized()


static func _world_to_local_direction(world_direction: Vector3, facing: Vector3) -> Vector3:
	var flat_direction := Vector3(world_direction.x, 0.0, world_direction.z)
	if flat_direction.length_squared() <= 0.001:
		return Vector3.ZERO
	flat_direction = flat_direction.normalized()
	var forward := Vector3(facing.x, 0.0, facing.z)
	if forward.length_squared() <= 0.001:
		forward = Vector3.FORWARD
	forward = forward.normalized()
	var side := Vector3(-forward.z, 0.0, forward.x).normalized()
	return Vector3(flat_direction.dot(side), 0.0, flat_direction.dot(forward))


static func _local_to_world_offset(local_offset: Vector3, facing: Vector3) -> Vector3:
	var forward := Vector3(facing.x, 0.0, facing.z)
	if forward.length_squared() <= 0.001:
		forward = Vector3.FORWARD
	forward = forward.normalized()
	var side := Vector3(-forward.z, 0.0, forward.x).normalized()
	return side * local_offset.x + Vector3.UP * local_offset.y + forward * local_offset.z


static func _decay_pressure(battalion: CoreV2Battalion, delta: float) -> void:
	if battalion.formation_pressure_m <= 0.0:
		battalion.formation_pressure_direction = Vector3.ZERO
		return
	battalion.formation_pressure_m = max(0.0, battalion.formation_pressure_m - PRESSURE_DECAY_PER_SECOND * delta)
	if battalion.formation_pressure_m <= 0.01:
		battalion.formation_pressure_direction = Vector3.ZERO


static func _normalize_layout(offsets: Array, roles: Array) -> Dictionary:
	if offsets.is_empty():
		return _with_layout_metrics(offsets, roles)
	var center: Vector3 = Vector3.ZERO
	for offset_value in offsets:
		var offset: Vector3 = offset_value
		center += offset
	center /= float(offsets.size())
	for index in range(offsets.size()):
		var offset: Vector3 = offsets[index]
		offsets[index] = offset - center
	return _with_layout_metrics(offsets, roles)


static func _with_layout_metrics(offsets: Array, roles: Array) -> Dictionary:
	var min_x: float = INF
	var max_x: float = -INF
	var min_z: float = INF
	var max_z: float = -INF
	for offset_value in offsets:
		var offset: Vector3 = offset_value
		min_x = min(min_x, offset.x)
		max_x = max(max_x, offset.x)
		min_z = min(min_z, offset.z)
		max_z = max(max_z, offset.z)
	var frontage_m: float = 0.0 if offsets.is_empty() else max_x - min_x
	var depth_m: float = 0.0 if offsets.is_empty() else max_z - min_z
	return {
		"offsets": offsets,
		"roles": roles,
		"frontage_m": frontage_m,
		"depth_m": depth_m,
	}


static func _resolve_requested_frontage_m(battalion: CoreV2Battalion, formation_state: int, requested_frontage_m: float) -> float:
	if requested_frontage_m > 0.0:
		return max(MIN_FLEX_FRONTAGE_M, requested_frontage_m)
	if battalion != null:
		if battalion.desired_formation_frontage_m > 0.0:
			return max(MIN_FLEX_FRONTAGE_M, battalion.desired_formation_frontage_m)
		if battalion.formation_frontage_m > 0.0:
			return max(MIN_FLEX_FRONTAGE_M, battalion.formation_frontage_m)
		return _default_frontage_for_count(battalion.sprite_count, formation_state, battalion.category)
	return MIN_FLEX_FRONTAGE_M


static func _default_frontage_for_count(sprite_count: int, formation_state: int, unit_category: int) -> float:
	if sprite_count <= 0:
		return MIN_FLEX_FRONTAGE_M
	match formation_state:
		CoreV2Types.FormationState.MARCH_COLUMN:
			return SPRITE_SPACING_M * 0.8
		CoreV2Types.FormationState.COLUMN:
			return SPRITE_SPACING_M * 3.0
		CoreV2Types.FormationState.DEFENSIVE:
			return max(MIN_FLEX_FRONTAGE_M, sqrt(float(sprite_count)) * SPRITE_SPACING_M * 0.95)
		CoreV2Types.FormationState.TERCIA:
			return max(MIN_FLEX_FRONTAGE_M, sqrt(float(sprite_count)) * SPRITE_SPACING_M * 1.45)
		_:
			if unit_category == CoreV2Types.UnitCategory.CAVALRY:
				return max(MIN_FLEX_FRONTAGE_M, min(float(sprite_count - 1) * SPRITE_SPACING_M * 1.2, 260.0))
			if unit_category == CoreV2Types.UnitCategory.ARTILLERY:
				return max(MIN_FLEX_FRONTAGE_M, float(max(1, sprite_count - 1)) * SPRITE_SPACING_M * 1.4)
			return max(MIN_FLEX_FRONTAGE_M, min(float(sprite_count - 1) * SPRITE_SPACING_M, 220.0))


static func _estimate_reform_duration(from_offsets: Array, target_offsets: Array) -> float:
	var max_distance: float = 0.0
	for index in range(min(from_offsets.size(), target_offsets.size())):
		var from_offset: Vector3 = from_offsets[index]
		var target_offset: Vector3 = target_offsets[index]
		max_distance = max(max_distance, from_offset.distance_to(target_offset))
	return clamp(max_distance / REFORM_SPEED_MPS + MIN_REFORM_DURATION_SECONDS, MIN_REFORM_DURATION_SECONDS, MAX_REFORM_DURATION_SECONDS)


static func _smoothstep(value: float) -> float:
	var t: float = clamp(value, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)
