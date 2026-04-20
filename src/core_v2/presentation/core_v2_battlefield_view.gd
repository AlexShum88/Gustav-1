class_name CoreV2BattlefieldView
extends Node3D


const VISUAL_INTERPOLATION_MIN_SECONDS: float = 0.08
const VISUAL_INTERPOLATION_MAX_SECONDS: float = 0.18
const VISUAL_TELEPORT_DISTANCE_M: float = 450.0
const DEBUG_LOS_RAY_COUNT: int = 64
const DEBUG_LOS_SAMPLE_STEP_M: float = 100.0
const SELECTION_LOS_POSITION_QUANTUM_M: float = 30.0
const SELECTION_LOS_RADIUS_QUANTUM_M: float = 10.0
const HEIGHTFIELD_GRID_STEP_M: float = 160.0
const TERRAIN_OVERLAY_GRID_STEP_M: float = 180.0
const TERRAIN_OVERLAY_HEIGHT_OFFSET_M: float = 0.85
const DEPLOYMENT_ZONE_HEIGHT_OFFSET_M: float = 1.2
const TERRAIN_HEIGHT_FADE_MIN_M: float = 160.0
const TERRAIN_HEIGHT_FADE_MAX_M: float = 760.0
const VISUAL_CUE_MODEL_SCALE: float = 5.8
const VISUAL_CUE_ROW_SPACING_M: float = 8.0
const VISUAL_CUE_COLUMN_SPACING_M: float = 9.5
const MUSKETEER_VISUAL_RESOURCE_PATH: String = "res://assets/core_v2/units/musketeer_lowpoly.obj"
const PIKEMAN_VISUAL_RESOURCE_PATH: String = "res://assets/core_v2/units/pikeman_lowpoly.obj"
const UNIT_ATLAS_PATH: String = "res://assets/core_v2/units/army_atlas.png"

var _ground_root: Node3D
var _terrain_root: Node3D
var _roads_root: Node3D
var _smoke_root: Node3D
var _zones_root: Node3D
var _objectives_root: Node3D
var _hq_root: Node3D
var _units_root: Node3D
var _orders_root: Node3D
var _messenger_root: Node3D
var _last_seen_root: Node3D
var _selection_root: Node3D
var _latest_snapshot: Dictionary = {}
var _battalion_snapshots: Dictionary = {}
var _hq_snapshots: Dictionary = {}
var _selected_battalion_id: StringName = &""
var _static_signature: int = 0
var _selection_signature: int = 0
var _selection_disk: MeshInstance3D
var _selection_ring: MeshInstance3D
var _selection_contour: MeshInstance3D
var _selection_member_root: Node3D
var _selection_overlay_has_content: bool = false
var _selection_overlay_dirty: bool = true
var _performance_stats: Dictionary = {}
var _material_cache: Dictionary = {}
var _box_mesh_cache: Dictionary = {}
var _formation_mesh_cache: Dictionary = {}
var _cylinder_mesh_cache: Dictionary = {}
var _sphere_mesh_cache: Dictionary = {}
var _unit_mesh_cache: Dictionary = {}
var _unit_material_cache: Dictionary = {}
var _unit_atlas_texture: Texture2D
var _objective_visuals: Dictionary = {}
var _smoke_visuals: Dictionary = {}
var _hq_visuals: Dictionary = {}
var _order_line_visuals: Dictionary = {}
var _messenger_visuals: Dictionary = {}
var _last_seen_visuals: Dictionary = {}
var _battalion_visuals: Dictionary = {}
var _last_snapshot_usec: int = 0
var _visual_interpolation_duration: float = VISUAL_INTERPOLATION_MIN_SECONDS
var _selected_brigade_id: StringName = &""


func _ready() -> void:
	_build_environment()
	_build_roots()


func _process(delta: float) -> void:
	var interpolation_started_usec: int = Time.get_ticks_usec()
	_advance_battalion_visuals(delta)
	_performance_stats["visual_interpolation_ms"] = float(Time.get_ticks_usec() - interpolation_started_usec) / 1000.0


func apply_snapshot(snapshot: Dictionary) -> void:
	var apply_started_usec: int = Time.get_ticks_usec()
	_update_visual_interpolation_window(apply_started_usec)
	_latest_snapshot = snapshot
	var static_world: Dictionary = snapshot.get("channels", {}).get("static_world", {})
	var next_static_signature: int = static_world.hash()
	_performance_stats["static_rebuild_ms"] = 0.0
	if next_static_signature != _static_signature:
		# Статичний світ перебудовується лише коли реально змінюється мапа або зони.
		_static_signature = next_static_signature
		_selection_signature = 0
		_selection_overlay_dirty = true
		var static_rebuild_started_usec: int = Time.get_ticks_usec()
		_rebuild_static_world(static_world)
		_performance_stats["static_rebuild_ms"] = float(Time.get_ticks_usec() - static_rebuild_started_usec) / 1000.0
	_rebuild_dynamic_world(snapshot)
	_performance_stats["apply_ms"] = float(Time.get_ticks_usec() - apply_started_usec) / 1000.0


func set_selected_battalion(battalion_id: StringName, brigade_id: StringName = &"") -> void:
	if _selected_battalion_id != battalion_id or _selected_brigade_id != brigade_id:
		_selection_signature = 0
		_selection_overlay_dirty = true
	_selected_battalion_id = battalion_id
	_selected_brigade_id = brigade_id
	_rebuild_selection_overlay()


func get_battalion_snapshot(battalion_id: StringName) -> Dictionary:
	return _battalion_snapshots.get(battalion_id, {})


func get_hq_snapshot(hq_id: StringName) -> Dictionary:
	return _hq_snapshots.get(hq_id, {})


func get_performance_stats() -> Dictionary:
	return _performance_stats.duplicate()


func pick_battalion_at(world_position: Vector3) -> StringName:
	var nearest_id: StringName = &""
	var nearest_distance: float = 160.0
	for battalion_id_value in _battalion_snapshots.keys():
		var battalion_id: StringName = battalion_id_value
		var battalion_snapshot: Dictionary = _battalion_snapshots[battalion_id]
		var battalion_position: Vector3 = battalion_snapshot.get("position", Vector3.ZERO)
		var visual_state: Dictionary = battalion_snapshot.get("visual_state", {})
		var pick_radius: float = max(80.0, float(visual_state.get("frontage_m", battalion_snapshot.get("formation_frontage_m", 120.0))) * 0.55)
		var distance_to_click: float = Vector2(battalion_position.x, battalion_position.z).distance_to(
			Vector2(world_position.x, world_position.z)
		)
		if distance_to_click >= min(nearest_distance, pick_radius):
			continue
		nearest_distance = distance_to_click
		nearest_id = battalion_id
	return nearest_id


func pick_selectable_at(world_position: Vector3) -> Dictionary:
	var nearest: Dictionary = {}
	var nearest_distance: float = 160.0
	for battalion_id_value in _battalion_snapshots.keys():
		var battalion_id: StringName = battalion_id_value
		var battalion_snapshot: Dictionary = _battalion_snapshots[battalion_id]
		var battalion_position: Vector3 = battalion_snapshot.get("position", Vector3.ZERO)
		var visual_state: Dictionary = battalion_snapshot.get("visual_state", {})
		var pick_radius: float = max(80.0, float(visual_state.get("frontage_m", battalion_snapshot.get("formation_frontage_m", 120.0))) * 0.55)
		var distance_to_click: float = Vector2(battalion_position.x, battalion_position.z).distance_to(Vector2(world_position.x, world_position.z))
		if distance_to_click >= min(nearest_distance, pick_radius):
			continue
		nearest_distance = distance_to_click
		nearest = {
			"id": battalion_id,
			"entity_kind": CoreV2Types.EntityKind.BATTALION,
			"snapshot": battalion_snapshot,
		}
	for hq_id_value in _hq_snapshots.keys():
		var hq_id: StringName = hq_id_value
		var hq_snapshot: Dictionary = _hq_snapshots[hq_id]
		var hq_position: Vector3 = hq_snapshot.get("position", Vector3.ZERO)
		var hq_distance_to_click: float = Vector2(hq_position.x, hq_position.z).distance_to(Vector2(world_position.x, world_position.z))
		if hq_distance_to_click >= min(nearest_distance, 120.0):
			continue
		nearest_distance = hq_distance_to_click
		nearest = {
			"id": hq_id,
			"entity_kind": int(hq_snapshot.get("entity_kind", CoreV2Types.EntityKind.BRIGADE_HQ)),
			"snapshot": hq_snapshot,
		}
	return nearest


func _build_environment() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.66, 0.76, 0.87)
	environment.ambient_light_color = Color(0.92, 0.92, 0.9)
	environment.ambient_light_energy = 0.7

	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)

	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.15
	sun.rotation_degrees = Vector3(-58.0, -28.0, 0.0)
	add_child(sun)


func _build_roots() -> void:
	_ground_root = Node3D.new()
	_ground_root.name = "GroundRoot"
	add_child(_ground_root)

	_terrain_root = Node3D.new()
	_terrain_root.name = "TerrainRoot"
	add_child(_terrain_root)

	_roads_root = Node3D.new()
	_roads_root.name = "RoadsRoot"
	add_child(_roads_root)

	_smoke_root = Node3D.new()
	_smoke_root.name = "SmokeRoot"
	add_child(_smoke_root)

	_zones_root = Node3D.new()
	_zones_root.name = "ZonesRoot"
	add_child(_zones_root)

	_objectives_root = Node3D.new()
	_objectives_root.name = "ObjectivesRoot"
	add_child(_objectives_root)

	_hq_root = Node3D.new()
	_hq_root.name = "HqRoot"
	add_child(_hq_root)

	_units_root = Node3D.new()
	_units_root.name = "UnitsRoot"
	add_child(_units_root)

	_orders_root = Node3D.new()
	_orders_root.name = "OrdersRoot"
	add_child(_orders_root)

	_messenger_root = Node3D.new()
	_messenger_root.name = "MessengerRoot"
	add_child(_messenger_root)

	_last_seen_root = Node3D.new()
	_last_seen_root.name = "LastSeenRoot"
	add_child(_last_seen_root)

	_selection_root = Node3D.new()
	_selection_root.name = "SelectionRoot"
	add_child(_selection_root)


func _rebuild_static_world(static_world: Dictionary) -> void:
	_clear_children(_ground_root)
	_clear_children(_terrain_root)
	_clear_children(_roads_root)
	_clear_children(_smoke_root)
	_smoke_visuals.clear()
	_clear_children(_zones_root)

	var map_rect: Rect2 = static_world.get("map_rect", Rect2(-5000.0, -5000.0, 10000.0, 10000.0))
	var terrain_patches: Array = static_world.get("terrain_patches", [])
	_ground_root.add_child(_create_ground_mesh(map_rect, terrain_patches))

	for terrain_value in terrain_patches:
		var terrain_snapshot: Dictionary = terrain_value
		_terrain_root.add_child(_create_terrain_patch_node(terrain_snapshot))

	for road_value in static_world.get("roads", []):
		var road_snapshot: Dictionary = road_value
		_roads_root.add_child(_create_road_node(road_snapshot))

	for smoke_value in static_world.get("smoke_zones", []):
		var smoke_snapshot: Dictionary = smoke_value
		_smoke_root.add_child(_create_smoke_zone_node(smoke_snapshot))

	for zone_value in static_world.get("deployment_zones", []):
		var zone_snapshot: Dictionary = zone_value
		_zones_root.add_child(_create_zone_mesh(zone_snapshot))


func _update_visual_interpolation_window(snapshot_usec: int) -> void:
	if _last_snapshot_usec > 0:
		var snapshot_delta_seconds: float = float(snapshot_usec - _last_snapshot_usec) / 1000000.0
		_visual_interpolation_duration = clamp(
			snapshot_delta_seconds * 1.05,
			VISUAL_INTERPOLATION_MIN_SECONDS,
			VISUAL_INTERPOLATION_MAX_SECONDS
		)
	_last_snapshot_usec = snapshot_usec


func _rebuild_dynamic_world(snapshot: Dictionary) -> void:
	var rebuild_started_usec: int = Time.get_ticks_usec()
	# Динамічний шар синхронізується через stable visual records, щоб не пересоздавати вузли на кожен snapshot.
	_battalion_snapshots.clear()
	var objective_count: int = 0
	var smoke_count: int = 0
	var hq_count: int = 0
	var battalion_count: int = 0
	var visual_footprint_count: int = 0
	var route_waypoint_count: int = 0
	var messenger_count: int = 0
	var last_seen_count: int = 0
	var seen_objective_ids: Dictionary = {}
	var seen_smoke_ids: Dictionary = {}
	var seen_hq_ids: Dictionary = {}
	var seen_hq_snapshot_ids: Dictionary = {}
	var seen_order_line_ids: Dictionary = {}
	var seen_messenger_ids: Dictionary = {}
	var seen_last_seen_ids: Dictionary = {}
	var seen_battalion_ids: Dictionary = {}

	var units_channel: Dictionary = snapshot.get("channels", {}).get("units", {})
	for objective_value in units_channel.get("objectives", []):
		var objective_snapshot: Dictionary = objective_value
		_sync_objective_visual(objective_snapshot, seen_objective_ids)
		objective_count += 1

	for smoke_value in units_channel.get("smoke_zones", []):
		var smoke_snapshot: Dictionary = smoke_value
		_sync_smoke_visual(smoke_snapshot, seen_smoke_ids)
		smoke_count += 1

	for hq_value in units_channel.get("hqs", []):
		var hq_snapshot: Dictionary = hq_value
		if not bool(hq_snapshot.get("is_deployed", true)):
			continue
		var hq_id: StringName = StringName(hq_snapshot.get("id", ""))
		_hq_snapshots[hq_id] = hq_snapshot
		seen_hq_snapshot_ids[hq_id] = true
		_sync_hq_visual(hq_snapshot, seen_hq_ids, false)
		hq_count += 1

	for baggage_value in units_channel.get("baggage_trains", []):
		var baggage_snapshot: Dictionary = baggage_value
		if not bool(baggage_snapshot.get("is_deployed", true)):
			continue
		_sync_hq_visual(baggage_snapshot, seen_hq_ids, true)
		hq_count += 1

	for battalion_value in units_channel.get("battalions", []):
		var battalion_snapshot: Dictionary = battalion_value
		var battalion_id: StringName = StringName(battalion_snapshot.get("id", ""))
		_battalion_snapshots[battalion_id] = battalion_snapshot
		seen_battalion_ids[battalion_id] = true
		_sync_battalion_visual(battalion_id, battalion_snapshot)
		battalion_count += 1
		visual_footprint_count += 1
		route_waypoint_count += battalion_snapshot.get("movement_path", []).size()
		if not bool(battalion_snapshot.get("is_friendly", false)):
			continue
		var battalion_position: Vector3 = battalion_snapshot.get("position", Vector3.ZERO)
		var battalion_target: Vector3 = battalion_snapshot.get("target_position", battalion_position)
		var order_line_points: Array = _build_order_line_points(
			battalion_position,
			battalion_target,
			battalion_snapshot.get("movement_path", [])
		)
		if order_line_points.size() < 2:
			continue
		_sync_order_line_visual(battalion_id, order_line_points, seen_order_line_ids, Color(0.96, 0.88, 0.42, 0.74))

	for battalion_id_value in _battalion_snapshots.keys():
		var friendly_battalion_id: StringName = battalion_id_value
		var friendly_snapshot: Dictionary = _battalion_snapshots[friendly_battalion_id]
		if not bool(friendly_snapshot.get("is_friendly", false)):
			continue
		var combat_target_id: StringName = StringName(friendly_snapshot.get("combat_target_id", ""))
		if combat_target_id == &"" or not _battalion_snapshots.has(combat_target_id):
			continue
		var combat_target_snapshot: Dictionary = _battalion_snapshots[combat_target_id]
		_sync_order_line_visual(
			StringName("combat_%s" % String(friendly_battalion_id)),
			[
				friendly_snapshot.get("position", Vector3.ZERO),
				combat_target_snapshot.get("position", Vector3.ZERO),
			],
			seen_order_line_ids,
			_get_combat_line_color(friendly_snapshot)
		)

	for marker_value in units_channel.get("last_seen_markers", []):
		var marker_snapshot: Dictionary = marker_value
		_sync_last_seen_visual(marker_snapshot, seen_last_seen_ids)
		last_seen_count += 1

	for messenger_value in units_channel.get("order_messengers", []):
		var messenger_snapshot: Dictionary = messenger_value
		_sync_messenger_visual(messenger_snapshot, seen_messenger_ids)
		messenger_count += 1

	_prune_missing_visuals(_objective_visuals, seen_objective_ids)
	_hide_missing_visuals(_smoke_visuals, seen_smoke_ids)
	_prune_missing_visuals(_hq_visuals, seen_hq_ids)
	_prune_missing_snapshots(_hq_snapshots, seen_hq_snapshot_ids)
	_hide_missing_order_line_visuals(seen_order_line_ids)
	_prune_missing_visuals(_messenger_visuals, seen_messenger_ids)
	_hide_missing_visuals(_last_seen_visuals, seen_last_seen_ids)
	_prune_missing_battalion_visuals(seen_battalion_ids)
	_rebuild_selection_overlay()
	_performance_stats["dynamic_rebuild_ms"] = float(Time.get_ticks_usec() - rebuild_started_usec) / 1000.0
	_performance_stats["objective_nodes"] = objective_count
	_performance_stats["smoke_nodes"] = smoke_count
	_performance_stats["hq_nodes"] = hq_count
	_performance_stats["battalion_nodes"] = battalion_count
	_performance_stats["battalion_footprints"] = visual_footprint_count
	_performance_stats["formation_cue_multimeshes"] = _count_visual_cue_multimeshes()
	_performance_stats["route_waypoints"] = route_waypoint_count
	_performance_stats["order_messengers"] = messenger_count
	_performance_stats["last_seen_markers"] = last_seen_count
	_performance_stats["material_cache"] = _material_cache.size() + _unit_material_cache.size()
	_performance_stats["mesh_cache"] = _box_mesh_cache.size() + _formation_mesh_cache.size() + _cylinder_mesh_cache.size() + _sphere_mesh_cache.size() + _unit_mesh_cache.size()
	_performance_stats["battalion_visuals"] = _battalion_visuals.size()
	_performance_stats["objective_visuals"] = _objective_visuals.size()
	_performance_stats["smoke_visuals"] = _smoke_visuals.size()
	_performance_stats["hq_visuals"] = _hq_visuals.size()
	_performance_stats["order_line_visuals"] = _order_line_visuals.size()
	_performance_stats["messenger_visuals"] = _messenger_visuals.size()
	_performance_stats["last_seen_visuals"] = _last_seen_visuals.size()
	_performance_stats["selection_overlay_nodes"] = _selection_root.get_child_count()
	_performance_stats["selection_overlay_rebuilds"] = int(_performance_stats.get("selection_overlay_rebuilds", 0))
	_performance_stats["debug_los_rays"] = DEBUG_LOS_RAY_COUNT
	_performance_stats["debug_los_sample_step_m"] = DEBUG_LOS_SAMPLE_STEP_M


func _rebuild_selection_overlay() -> void:
	_performance_stats["selection_overlay_rebuild_ms"] = 0.0
	var battalion_snapshot: Dictionary = _battalion_snapshots.get(_selected_battalion_id, {}) if _selected_battalion_id != &"" else {}
	var brigade_battalions: Array = _get_selected_brigade_battalion_snapshots()
	if battalion_snapshot.is_empty() and brigade_battalions.is_empty():
		_clear_selection_overlay_if_needed()
		return
	var next_signature: int = _build_selection_overlay_signature(battalion_snapshot, brigade_battalions)
	if not _selection_overlay_dirty and _selection_overlay_has_content and next_signature == _selection_signature:
		return
	var selection_rebuild_started_usec: int = Time.get_ticks_usec()
	_selection_signature = next_signature
	# Тьмяне коло - базовий радіус. Жовтий контур - direction-based LOS після cover penetration.
	_ensure_selection_overlay_nodes()
	_clear_children(_selection_member_root)
	if not battalion_snapshot.is_empty():
		var battalion_position: Vector3 = battalion_snapshot.get("position", Vector3.ZERO)
		var battalion_color: Color = battalion_snapshot.get("color", Color(0.95, 0.95, 0.5))
		var base_vision_radius: float = float(battalion_snapshot.get("vision_radius_m", 1500.0))
		var effective_vision_radius: float = float(battalion_snapshot.get("effective_vision_radius_m", base_vision_radius))
		_selection_disk.visible = true
		_selection_ring.visible = true
		_selection_contour.visible = true
		_update_selection_disk(
			battalion_position,
			battalion_color
		)
		_update_los_ring(
			_selection_ring,
			battalion_position,
			base_vision_radius,
			Color(0.78, 0.82, 0.86, 0.28)
		)
		_update_los_contour(
			_selection_contour,
			battalion_position,
			effective_vision_radius,
			Color(0.96, 0.92, 0.48, 0.94)
		)
	else:
		_selection_disk.visible = false
		_selection_ring.visible = false
		_selection_contour.visible = false
	_update_brigade_member_overlay(brigade_battalions)
	_selection_root.visible = true
	_performance_stats["selection_overlay_rebuilds"] = int(_performance_stats.get("selection_overlay_rebuilds", 0)) + 1
	_performance_stats["selection_overlay_rebuild_ms"] = float(Time.get_ticks_usec() - selection_rebuild_started_usec) / 1000.0
	_performance_stats["debug_los_rays"] = DEBUG_LOS_RAY_COUNT
	_performance_stats["debug_los_sample_step_m"] = DEBUG_LOS_SAMPLE_STEP_M
	_selection_overlay_has_content = true
	_selection_overlay_dirty = false


func _clear_selection_overlay_if_needed() -> void:
	if not _selection_overlay_has_content:
		_selection_overlay_dirty = false
		return
	_selection_root.visible = false
	_selection_signature = 0
	_selection_overlay_has_content = false
	_selection_overlay_dirty = false


func _build_selection_overlay_signature(battalion_snapshot: Dictionary, brigade_battalions: Array) -> int:
	var signature_source: Dictionary = {
		"id": String(_selected_battalion_id),
		"brigade_id": String(_selected_brigade_id),
		"static": _static_signature,
		"members": [],
	}
	if not battalion_snapshot.is_empty():
		var battalion_position: Vector3 = battalion_snapshot.get("position", Vector3.ZERO)
		var base_vision_radius: float = float(battalion_snapshot.get("vision_radius_m", 0.0))
		var effective_vision_radius: float = float(battalion_snapshot.get("effective_vision_radius_m", base_vision_radius))
		signature_source["x"] = int(round(battalion_position.x / SELECTION_LOS_POSITION_QUANTUM_M))
		signature_source["y"] = int(round(battalion_position.y / SELECTION_LOS_POSITION_QUANTUM_M))
		signature_source["z"] = int(round(battalion_position.z / SELECTION_LOS_POSITION_QUANTUM_M))
		signature_source["base"] = int(round(base_vision_radius / SELECTION_LOS_RADIUS_QUANTUM_M))
		signature_source["effective"] = int(round(effective_vision_radius / SELECTION_LOS_RADIUS_QUANTUM_M))
	var member_signature: Array = []
	for member_value in brigade_battalions:
		var member_snapshot: Dictionary = member_value
		var member_position: Vector3 = member_snapshot.get("position", Vector3.ZERO)
		member_signature.append([
			String(member_snapshot.get("id", "")),
			int(round(member_position.x / SELECTION_LOS_POSITION_QUANTUM_M)),
			int(round(member_position.z / SELECTION_LOS_POSITION_QUANTUM_M)),
		])
	signature_source["members"] = member_signature
	return signature_source.hash()


func _get_selected_brigade_battalion_snapshots() -> Array:
	if _selected_brigade_id == &"":
		return []
	var result: Array = []
	for battalion_id_value in _battalion_snapshots.keys():
		var battalion_snapshot: Dictionary = _battalion_snapshots[battalion_id_value]
		if StringName(battalion_snapshot.get("brigade_id", "")) != _selected_brigade_id:
			continue
		result.append(battalion_snapshot)
	return result


func _update_brigade_member_overlay(brigade_battalions: Array) -> void:
	for battalion_value in brigade_battalions:
		var battalion_snapshot: Dictionary = battalion_value
		var member_position: Vector3 = battalion_snapshot.get("position", Vector3.ZERO)
		var member_color: Color = battalion_snapshot.get("color", Color(0.88, 0.86, 0.42))
		var marker := MeshInstance3D.new()
		marker.mesh = _get_cylinder_mesh(96.0, 96.0, 2.0)
		marker.position = Vector3(member_position.x, member_position.y + 2.2, member_position.z)
		var marker_color: Color = member_color.lightened(0.35)
		marker_color.a = 0.24 if StringName(battalion_snapshot.get("id", "")) != _selected_battalion_id else 0.36
		marker.material_override = _make_material(marker_color, true, true)
		_selection_member_root.add_child(marker)

		var label := Label3D.new()
		label.text = String(battalion_snapshot.get("display_name", "Батальйон"))
		label.position = Vector3(member_position.x, member_position.y + 26.0, member_position.z)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.modulate = Color(0.98, 0.94, 0.62, 0.86)
		_selection_member_root.add_child(label)


func _sync_objective_visual(objective_snapshot: Dictionary, seen_objective_ids: Dictionary) -> void:
	var visual_id: String = _get_visual_id(objective_snapshot, "objective")
	seen_objective_ids[visual_id] = true
	var visual_signature: int = objective_snapshot.hash()
	var visual: Dictionary = _objective_visuals.get(visual_id, {})
	if _is_visual_record_current(visual, visual_signature):
		return
	_free_visual_record(visual)
	var root := _create_objective_node(objective_snapshot)
	_objectives_root.add_child(root)
	_objective_visuals[visual_id] = {
		"root": root,
		"signature": visual_signature,
	}


func _sync_smoke_visual(smoke_snapshot: Dictionary, seen_smoke_ids: Dictionary) -> void:
	var visual_id: String = _get_visual_id(smoke_snapshot, "smoke")
	seen_smoke_ids[visual_id] = true
	var visual_signature: int = _snapshot_signature_without(smoke_snapshot, ["position", "density", "expires_at_seconds", "direction"])
	var visual: Dictionary = _smoke_visuals.get(visual_id, {})
	if not _is_visual_record_current(visual, visual_signature):
		_free_visual_record(visual)
		var root := _create_smoke_zone_node(smoke_snapshot)
		_smoke_root.add_child(root)
		visual = {
			"root": root,
			"signature": visual_signature,
		}
	_smoke_visuals[visual_id] = visual
	var root: Node3D = visual.get("root", null) as Node3D
	if root != null and is_instance_valid(root):
		_update_smoke_node(root, smoke_snapshot)


func _sync_hq_visual(hq_snapshot: Dictionary, seen_hq_ids: Dictionary, is_baggage: bool) -> void:
	var visual_id: String = "%s:%s" % ["baggage" if is_baggage else "hq", _get_visual_id(hq_snapshot, "hq")]
	seen_hq_ids[visual_id] = true
	var ignored_keys: Array = ["position", "order_label", "baggage_supply", "baggage_ammo", "health", "recent_damage", "is_destroyed", "status_label"]
	var visual_signature: int = _snapshot_signature_without(hq_snapshot, ignored_keys)
	var visual: Dictionary = _hq_visuals.get(visual_id, {})
	if not _is_visual_record_current(visual, visual_signature):
		_free_visual_record(visual)
		var root: Node3D = _create_hq_node(hq_snapshot)
		if is_baggage:
			root = _create_baggage_node(hq_snapshot)
		_hq_root.add_child(root)
		visual = {
			"root": root,
			"signature": visual_signature,
		}
		_hq_visuals[visual_id] = visual
	var root: Node3D = visual.get("root", null) as Node3D
	if root != null and is_instance_valid(root):
		root.position = hq_snapshot.get("position", root.position)


func _sync_order_line_visual(
		battalion_id: StringName,
		line_points: Array,
		seen_order_line_ids: Dictionary,
		line_color: Color
) -> void:
	var visual_id: String = String(battalion_id)
	seen_order_line_ids[visual_id] = true
	var visual: Dictionary = _order_line_visuals.get(visual_id, {})
	var existing_root: Node3D = visual.get("root", null) as Node3D
	if visual.is_empty() or existing_root == null or not is_instance_valid(existing_root):
		var root := Node3D.new()
		root.name = "OrderLine_%s" % visual_id
		var marker := MeshInstance3D.new()
		root.add_child(marker)
		_orders_root.add_child(root)
		visual = {
			"root": root,
			"marker": marker,
		}
		_order_line_visuals[visual_id] = visual
	_update_order_line_visual(visual, line_points, line_color)


func _build_order_line_points(start_position: Vector3, target_position: Vector3, movement_path: Array) -> Array:
	var line_points: Array = [start_position]
	for waypoint_value in movement_path:
		var waypoint: Vector3 = waypoint_value
		if line_points[line_points.size() - 1].distance_to(waypoint) <= 20.0:
			continue
		line_points.append(waypoint)
	if line_points[line_points.size() - 1].distance_to(target_position) > 20.0:
		line_points.append(target_position)
	if line_points.size() < 2:
		return []
	return line_points


func _update_order_line_visual(visual: Dictionary, line_points: Array, line_color: Color) -> void:
	var root: Node3D = visual.get("root", null) as Node3D
	var marker: MeshInstance3D = visual.get("marker", null) as MeshInstance3D
	if root == null or marker == null or not is_instance_valid(root) or not is_instance_valid(marker):
		return
	if line_points.size() < 2:
		root.visible = false
		return
	root.visible = true
	root.position = Vector3.ZERO
	var immediate := ImmediateMesh.new()
	immediate.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for point_value in line_points:
		var point: Vector3 = point_value
		immediate.surface_set_color(line_color)
		immediate.surface_add_vertex(Vector3(point.x, point.y + 8.0, point.z))
	immediate.surface_end()
	marker.mesh = immediate
	marker.material_override = _make_material(line_color, true, true)


func _sync_messenger_visual(messenger_snapshot: Dictionary, seen_messenger_ids: Dictionary) -> void:
	var visual_id: String = _get_visual_id(messenger_snapshot, "messenger")
	seen_messenger_ids[visual_id] = true
	var visual_signature: int = _snapshot_signature_without(messenger_snapshot, ["position", "target_position", "distance_remaining_m"])
	var visual: Dictionary = _messenger_visuals.get(visual_id, {})
	if not _is_visual_record_current(visual, visual_signature):
		_free_visual_record(visual)
		var root := _create_order_messenger_node(messenger_snapshot)
		_messenger_root.add_child(root)
		var label: Label3D = root.get_child(root.get_child_count() - 1) as Label3D
		visual = {
			"root": root,
			"label": label,
			"signature": visual_signature,
		}
		_messenger_visuals[visual_id] = visual
	var root: Node3D = visual.get("root", null) as Node3D
	if root != null and is_instance_valid(root):
		root.position = messenger_snapshot.get("position", root.position)
	var label: Label3D = visual.get("label", null) as Label3D
	if label != null and is_instance_valid(label):
		label.text = "%s\n%s %.0f м" % [
			messenger_snapshot.get("display_name", "Гінець"),
			messenger_snapshot.get("order_label", "Наказ"),
			float(messenger_snapshot.get("distance_remaining_m", 0.0)),
		]


func _sync_last_seen_visual(marker_snapshot: Dictionary, seen_last_seen_ids: Dictionary) -> void:
	var visual_id: String = _get_visual_id(marker_snapshot, "last_seen", "entity_key")
	seen_last_seen_ids[visual_id] = true
	var visual_signature: int = _snapshot_signature_without(marker_snapshot, ["position", "seconds_ago"])
	var visual: Dictionary = _last_seen_visuals.get(visual_id, {})
	if not _is_visual_record_current(visual, visual_signature):
		_free_visual_record(visual)
		var root := _create_last_seen_marker_node(marker_snapshot)
		_last_seen_root.add_child(root)
		var label: Label3D = root.get_child(root.get_child_count() - 1) as Label3D
		visual = {
			"root": root,
			"label": label,
			"signature": visual_signature,
		}
		_last_seen_visuals[visual_id] = visual
	var root: Node3D = visual.get("root", null) as Node3D
	if root != null and is_instance_valid(root):
		root.visible = true
		root.position = marker_snapshot.get("position", root.position)
	var label: Label3D = visual.get("label", null) as Label3D
	if label != null and is_instance_valid(label):
		label.text = "%s\n%.0f с тому" % [
			marker_snapshot.get("display_name", "Останній контакт"),
			float(marker_snapshot.get("seconds_ago", 0.0)),
		]


func _prune_missing_visuals(visuals: Dictionary, seen_visual_ids: Dictionary) -> void:
	for visual_id_value in visuals.keys():
		var visual_key = visual_id_value
		var visual_id: String = String(visual_key)
		if seen_visual_ids.has(visual_id):
			continue
		_free_visual_record(visuals[visual_key])
		visuals.erase(visual_key)


func _prune_missing_snapshots(snapshots: Dictionary, seen_snapshot_ids: Dictionary) -> void:
	for snapshot_id_value in snapshots.keys():
		var snapshot_id: StringName = snapshot_id_value
		if seen_snapshot_ids.has(snapshot_id):
			continue
		snapshots.erase(snapshot_id)


func _hide_missing_order_line_visuals(seen_order_line_ids: Dictionary) -> void:
	_hide_missing_visuals(_order_line_visuals, seen_order_line_ids)


func _hide_missing_visuals(visuals: Dictionary, seen_visual_ids: Dictionary) -> void:
	for visual_id_value in visuals.keys():
		var visual_id: String = String(visual_id_value)
		if seen_visual_ids.has(visual_id):
			continue
		var visual: Dictionary = visuals[visual_id_value]
		var root: Node3D = visual.get("root", null) as Node3D
		if root != null and is_instance_valid(root):
			root.visible = false


func _free_visual_record(visual: Dictionary) -> void:
	var root: Node3D = visual.get("root", null) as Node3D
	if root != null and is_instance_valid(root):
		root.queue_free()


func _is_visual_record_current(visual: Dictionary, visual_signature: int) -> bool:
	if visual.is_empty():
		return false
	var root: Node3D = visual.get("root", null) as Node3D
	if root == null or not is_instance_valid(root):
		return false
	return int(visual.get("signature", -1)) == visual_signature


func _get_visual_id(snapshot: Dictionary, fallback_prefix: String, id_key: String = "id") -> String:
	var id_text: String = String(snapshot.get(id_key, ""))
	if id_text.is_empty():
		id_text = String(snapshot.get("display_name", fallback_prefix))
	return "%s:%s" % [fallback_prefix, id_text]


func _snapshot_signature_without(snapshot: Dictionary, ignored_keys: Array) -> int:
	var signature_source: Dictionary = snapshot.duplicate(true)
	for key_value in ignored_keys:
		signature_source.erase(String(key_value))
	return signature_source.hash()


func _sync_battalion_visual(battalion_id: StringName, battalion_snapshot: Dictionary) -> void:
	var visual: Dictionary = _battalion_visuals.get(battalion_id, {})
	var existing_root: Node3D = visual.get("root", null) as Node3D
	var is_new_visual: bool = visual.is_empty() or existing_root == null or not is_instance_valid(existing_root)
	if is_new_visual:
		visual = _create_battalion_visual(battalion_id)

	var root: Node3D = visual["root"] as Node3D
	var target_position: Vector3 = battalion_snapshot.get("position", Vector3.ZERO)
	var target_facing: Vector3 = _safe_facing(battalion_snapshot.get("facing", visual.get("visual_facing", Vector3.FORWARD)))
	var should_snap: bool = is_new_visual or root.position.distance_to(target_position) > VISUAL_TELEPORT_DISTANCE_M

	visual["from_position"] = target_position if should_snap else root.position
	visual["target_position"] = target_position
	visual["position_elapsed"] = 0.0
	visual["position_duration"] = 0.001 if should_snap else _visual_interpolation_duration
	if should_snap:
		root.position = target_position
		root.basis = _basis_for_facing(target_facing)

	var current_facing: Vector3 = _safe_facing(visual.get("visual_facing", target_facing))
	visual["from_facing"] = target_facing if should_snap else current_facing
	visual["target_facing"] = target_facing
	visual["visual_facing"] = target_facing if should_snap else current_facing

	_sync_battalion_label(visual, battalion_snapshot)
	var geometry_signature: int = _build_battalion_geometry_signature(battalion_snapshot)
	if should_snap or int(visual.get("geometry_signature", 0)) != geometry_signature:
		_sync_battalion_geometry(visual, battalion_snapshot, should_snap)
		visual["geometry_signature"] = geometry_signature
	_battalion_visuals[battalion_id] = visual


func _create_battalion_visual(battalion_id: StringName) -> Dictionary:
	var root := Node3D.new()
	root.name = "Battalion_%s" % String(battalion_id)
	_units_root.add_child(root)

	var label := Label3D.new()
	label.position = Vector3(0.0, 54.0, 0.0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	root.add_child(label)

	return {
		"root": root,
		"label": label,
		"mass_marker": null,
		"pike_marker": null,
		"shot_left_marker": null,
		"shot_right_marker": null,
		"smoke_marker": null,
		"pressure_marker": null,
		"cue_multimeshes": {},
		"from_position": Vector3.ZERO,
		"target_position": Vector3.ZERO,
		"position_elapsed": 0.0,
		"position_duration": 0.001,
		"from_facing": Vector3.FORWARD,
		"target_facing": Vector3.FORWARD,
		"visual_facing": Vector3.FORWARD,
		"geometry_signature": 0,
		"cue_from_transforms": {},
		"cue_target_transforms": {},
		"cue_elapsed": 0.0,
		"cue_duration": 0.001,
	}


func _sync_battalion_label(visual: Dictionary, battalion_snapshot: Dictionary) -> void:
	var label: Label3D = visual["label"] as Label3D
	var reform_suffix: String = " %.0f%%" % (float(battalion_snapshot.get("formation_progress", 1.0)) * 100.0) if bool(battalion_snapshot.get("is_reforming", false)) else ""
	label.text = "%s\n%s%s" % [
		String(battalion_snapshot.get("display_name", "Батальйон")),
		String(battalion_snapshot.get("desired_formation_label", battalion_snapshot.get("formation_label", ""))),
		reform_suffix,
	]


func _build_battalion_geometry_signature(battalion_snapshot: Dictionary) -> int:
	return CoreV2BattalionVisualModel.geometry_signature_source(battalion_snapshot).hash()


func _sync_battalion_geometry(
		visual: Dictionary,
		battalion_snapshot: Dictionary,
		should_snap: bool
) -> void:
	_sync_battalion_mass_visual(visual, battalion_snapshot, should_snap)


func _sync_battalion_mass_visual(visual: Dictionary, battalion_snapshot: Dictionary, should_snap: bool) -> void:
	var model: Dictionary = CoreV2BattalionVisualModel.from_snapshot(battalion_snapshot)
	var battalion_color: Color = model.get("battalion_color", battalion_snapshot.get("color", Color(1.0, 1.0, 1.0)))
	var distorted_frontage: float = float(model.get("visual_frontage_m", 120.0))
	var distorted_depth: float = float(model.get("visual_depth_m", 48.0))
	var body_height: float = float(model.get("body_height_m", 6.5))
	var visual_irregularity: float = float(model.get("visual_irregularity", 0.1))
	var compression_level: float = float(model.get("compression_level", 0.0))
	var contact_pressure: float = float(model.get("contact_pressure", 0.0))
	var recoil_tendency: float = float(model.get("recoil_tendency", 0.0))
	var smoke_burden: float = float(model.get("smoke_burden", 0.0))
	var smoke_intensity: float = float(model.get("smoke_intensity", 0.0))
	var pike_ratio: float = float(model.get("pike_ratio", 0.35))
	var shot_ratio: float = float(model.get("shot_ratio", 0.65))
	var mass_color: Color = model.get("mass_color", battalion_color)
	var shape_seed: int = int(model.get("shape_seed", String(battalion_snapshot.get("id", "")).hash()))

	var mass_marker: MeshInstance3D = _get_or_create_battalion_marker(visual, "mass_marker", "BattalionMass")
	mass_marker.mesh = _get_formation_body_mesh(distorted_frontage, body_height, distorted_depth, visual_irregularity, compression_level, contact_pressure, shape_seed)
	mass_marker.position = Vector3.ZERO
	mass_marker.material_override = _make_material(Color(mass_color.r, mass_color.g, mass_color.b, 0.72), true, false)
	mass_marker.visible = true

	var pike_width: float = float(model.get("pike_width_m", max(8.0, distorted_frontage * clamp(pike_ratio, 0.12, 0.62))))
	var shot_width: float = float(model.get("shot_width_m", max(5.0, max(0.0, distorted_frontage - pike_width) * 0.5)))
	var sub_height: float = float(model.get("subzone_height_m", body_height + 1.4))
	var pike_marker: MeshInstance3D = _get_or_create_battalion_marker(visual, "pike_marker", "PikeCore")
	pike_marker.mesh = _get_formation_body_mesh(pike_width, sub_height, distorted_depth * 0.78, visual_irregularity * 0.42, compression_level * 0.35, contact_pressure * 0.45, shape_seed + 17)
	pike_marker.position = Vector3(0.0, 0.18, 0.0)
	pike_marker.material_override = _make_material(battalion_color.lightened(0.18), false, false)
	pike_marker.visible = pike_ratio > 0.03

	var shot_color: Color = model.get("shot_color", battalion_color.darkened(0.12).lerp(Color(0.82, 0.82, 0.76, 1.0), smoke_burden * 0.22))
	var left_marker: MeshInstance3D = _get_or_create_battalion_marker(visual, "shot_left_marker", "ShotLeft")
	left_marker.mesh = _get_formation_body_mesh(shot_width, sub_height * 0.82, distorted_depth * 0.9, visual_irregularity * 0.56, compression_level * 0.5, contact_pressure * 0.35, shape_seed + 31)
	left_marker.position = Vector3(-(pike_width + shot_width) * 0.5, 0.26, 0.0)
	left_marker.material_override = _make_material(shot_color, false, false)
	left_marker.visible = shot_ratio > 0.03

	var right_marker: MeshInstance3D = _get_or_create_battalion_marker(visual, "shot_right_marker", "ShotRight")
	right_marker.mesh = _get_formation_body_mesh(shot_width, sub_height * 0.82, distorted_depth * 0.9, visual_irregularity * 0.56, compression_level * 0.5, contact_pressure * 0.35, shape_seed + 47)
	right_marker.position = Vector3((pike_width + shot_width) * 0.5, 0.26, 0.0)
	right_marker.material_override = _make_material(shot_color, false, false)
	right_marker.visible = shot_ratio > 0.03

	var pressure_marker: MeshInstance3D = _get_or_create_battalion_marker(visual, "pressure_marker", "PressureBand")
	var pressure_intensity: float = clamp(max(contact_pressure, recoil_tendency * 0.75), 0.0, 1.0)
	if pressure_intensity > 0.04:
		pressure_marker.mesh = _get_formation_body_mesh(distorted_frontage * (0.72 + pressure_intensity * 0.18), 2.4 + pressure_intensity * 3.5, max(8.0, distorted_depth * 0.16), 0.45 + pressure_intensity * 0.45, compression_level, contact_pressure, shape_seed + 73)
		pressure_marker.position = Vector3(0.0, 0.65, -distorted_depth * 0.50)
		pressure_marker.material_override = _make_material(Color(1.0, 0.28, 0.10, 0.22 + pressure_intensity * 0.30), true, true)
		pressure_marker.visible = true
	else:
		pressure_marker.visible = false

	var smoke_marker: MeshInstance3D = _get_or_create_battalion_marker(visual, "smoke_marker", "BattalionSmoke")
	if smoke_intensity > 0.03:
		var smoke_radius: float = max(24.0, distorted_frontage * (0.28 + smoke_intensity * 0.18))
		var smoke_height: float = 18.0 + smoke_intensity * 28.0
		smoke_marker.mesh = _get_sphere_mesh(smoke_radius, smoke_height)
		smoke_marker.position = Vector3(0.0, body_height + smoke_height * 0.18, distorted_depth * 0.34)
		smoke_marker.material_override = _make_material(Color(0.56, 0.56, 0.50, 0.16 + smoke_intensity * 0.18), true, true)
		smoke_marker.visible = true
	else:
		smoke_marker.visible = false
	_sync_battalion_doctrine_cues(visual, model, battalion_color, should_snap)


func _get_or_create_battalion_marker(visual: Dictionary, visual_key: String, marker_name: String) -> MeshInstance3D:
	var marker: MeshInstance3D = visual.get(visual_key, null) as MeshInstance3D
	if marker != null and is_instance_valid(marker):
		return marker
	var root: Node3D = visual["root"] as Node3D
	marker = MeshInstance3D.new()
	marker.name = marker_name
	root.add_child(marker)
	visual[visual_key] = marker
	return marker


func _get_combat_line_color(battalion_snapshot: Dictionary) -> Color:
	match String(battalion_snapshot.get("combat_attack_kind", "")):
		"melee":
			return Color(1.0, 0.06, 0.02, 0.96)
		"artillery":
			return Color(1.0, 0.72, 0.18, 0.82)
		_:
			return Color(1.0, 0.32, 0.18, 0.86)


func _sync_battalion_doctrine_cues(visual: Dictionary, visual_model: Dictionary, battalion_color: Color, should_snap: bool) -> void:
	var cue_target_transforms: Dictionary = _build_doctrine_cue_transforms(visual_model)
	_sync_visual_cue_multimeshes(visual, cue_target_transforms, battalion_color, should_snap)


func _build_doctrine_cue_transforms(visual_model: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	var pike_count: int = int(visual_model.get("pike_cue_count", 0))
	var shot_count_per_wing: int = int(visual_model.get("shot_cue_count_per_wing", 0))
	var frontage_m: float = float(visual_model.get("visual_frontage_m", 120.0))
	var depth_m: float = float(visual_model.get("visual_depth_m", 48.0))
	var pike_width_m: float = float(visual_model.get("pike_width_m", frontage_m * 0.36))
	var shot_width_m: float = float(visual_model.get("shot_width_m", max(5.0, (frontage_m - pike_width_m) * 0.5)))
	var pressure_state: float = float(visual_model.get("cue_pressure_state", 0.0))
	var pike_transforms: Array = []
	var musket_transforms: Array = []
	_append_cue_grid(pike_transforms, "pikeman", pike_count, 0.0, 0.0, max(18.0, pike_width_m * 0.55), max(18.0, depth_m * 0.52), pressure_state)
	var wing_offset_x: float = (pike_width_m + shot_width_m) * 0.5
	_append_cue_grid(musket_transforms, "musketeer", shot_count_per_wing, -wing_offset_x, -depth_m * 0.04, max(14.0, shot_width_m * 0.65), max(16.0, depth_m * 0.64), pressure_state)
	_append_cue_grid(musket_transforms, "musketeer", shot_count_per_wing, wing_offset_x, -depth_m * 0.04, max(14.0, shot_width_m * 0.65), max(16.0, depth_m * 0.64), pressure_state)
	if not pike_transforms.is_empty():
		result["pikeman"] = pike_transforms
	if not musket_transforms.is_empty():
		result["musketeer"] = musket_transforms
	return result


func _append_cue_grid(target_transforms: Array, model_role: String, count: int, center_x: float, center_z: float, width_m: float, depth_m: float, pressure_state: float) -> void:
	if count <= 0:
		return
	var columns: int = int(clamp(ceil(sqrt(float(count)) * width_m / max(1.0, depth_m)), 1.0, float(count)))
	var rows: int = int(ceil(float(count) / float(columns)))
	for index in range(count):
		var column: int = index % columns
		var row: int = int(floor(float(index) / float(columns)))
		var column_t: float = (float(column) / max(1.0, float(columns - 1))) - 0.5 if columns > 1 else 0.0
		var row_t: float = (float(row) / max(1.0, float(rows - 1))) - 0.5 if rows > 1 else 0.0
		var jitter_x: float = sin(float(index) * 2.371) * (1.0 + pressure_state * 2.0)
		var jitter_z: float = cos(float(index) * 1.913) * (0.8 + pressure_state * 1.6)
		var local_position := Vector3(
			center_x + column_t * width_m + jitter_x,
			1.4,
			center_z + row_t * depth_m + jitter_z
		)
		target_transforms.append(Transform3D(_get_visual_cue_basis(Vector3.FORWARD), local_position))


func _sync_visual_cue_multimeshes(
		visual: Dictionary,
		cue_target_transforms: Dictionary,
		battalion_color: Color,
		should_snap: bool
) -> void:
	var cue_multimeshes: Dictionary = visual.get("cue_multimeshes", {})
	var cue_from_transforms: Dictionary = {}
	var normalized_target_transforms: Dictionary = {}
	for group_key_value in cue_target_transforms.keys():
		var group_key: String = String(group_key_value)
		var target_transforms: Array = cue_target_transforms[group_key]
		var multimesh_instance: MultiMeshInstance3D = _get_or_create_visual_cue_multimesh_instance(visual, group_key)
		var multimesh: MultiMesh = multimesh_instance.multimesh
		var count_changed: bool = multimesh.instance_count != target_transforms.size()
		var from_transforms: Array = []
		if should_snap or count_changed:
			from_transforms = target_transforms.duplicate(true)
		else:
			for transform_index in range(target_transforms.size()):
				from_transforms.append(multimesh.get_instance_transform(transform_index))
		multimesh.mesh = _get_visual_cue_mesh(group_key)
		multimesh.instance_count = target_transforms.size()
		multimesh_instance.material_override = _get_visual_cue_material(group_key, battalion_color)
		multimesh_instance.visible = target_transforms.size() > 0
		if should_snap or count_changed:
			for transform_index in range(target_transforms.size()):
				multimesh.set_instance_transform(transform_index, target_transforms[transform_index])
		cue_from_transforms[group_key] = from_transforms
		normalized_target_transforms[group_key] = target_transforms

	for group_key_value in cue_multimeshes.keys():
		var existing_group_key: String = String(group_key_value)
		if cue_target_transforms.has(existing_group_key):
			continue
		var stale_instance: MultiMeshInstance3D = cue_multimeshes[existing_group_key] as MultiMeshInstance3D
		if stale_instance == null or not is_instance_valid(stale_instance) or stale_instance.multimesh == null:
			continue
		stale_instance.multimesh.instance_count = 0
		stale_instance.visible = false

	visual["cue_from_transforms"] = cue_from_transforms
	visual["cue_target_transforms"] = normalized_target_transforms
	visual["cue_elapsed"] = 0.0
	visual["cue_duration"] = 0.001 if should_snap else _visual_interpolation_duration


func _get_or_create_visual_cue_multimesh_instance(visual: Dictionary, group_key: String) -> MultiMeshInstance3D:
	var cue_multimeshes: Dictionary = visual.get("cue_multimeshes", {})
	if cue_multimeshes.has(group_key):
		var existing_instance: MultiMeshInstance3D = cue_multimeshes[group_key] as MultiMeshInstance3D
		if existing_instance != null and is_instance_valid(existing_instance):
			return existing_instance
	var root: Node3D = visual["root"] as Node3D
	var multimesh_instance := MultiMeshInstance3D.new()
	multimesh_instance.name = "DoctrineCue_%s" % group_key
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = _get_visual_cue_mesh(group_key)
	multimesh.instance_count = 0
	multimesh_instance.multimesh = multimesh
	root.add_child(multimesh_instance)
	cue_multimeshes[group_key] = multimesh_instance
	visual["cue_multimeshes"] = cue_multimeshes
	return multimesh_instance


func _count_visual_cue_multimeshes() -> int:
	var result: int = 0
	for visual_value in _battalion_visuals.values():
		var visual: Dictionary = visual_value
		var cue_multimeshes: Dictionary = visual.get("cue_multimeshes", {})
		for multimesh_value in cue_multimeshes.values():
			var multimesh_instance: MultiMeshInstance3D = multimesh_value as MultiMeshInstance3D
			if multimesh_instance != null and is_instance_valid(multimesh_instance) and multimesh_instance.visible:
				result += 1
	return result


func _prune_missing_battalion_visuals(seen_battalion_ids: Dictionary) -> void:
	for battalion_id_value in _battalion_visuals.keys():
		var battalion_id: StringName = battalion_id_value
		if seen_battalion_ids.has(battalion_id):
			continue
		var visual: Dictionary = _battalion_visuals[battalion_id]
		var root: Node3D = visual.get("root", null) as Node3D
		if root != null and is_instance_valid(root):
			root.queue_free()
		_battalion_visuals.erase(battalion_id)


func _advance_battalion_visuals(delta: float) -> void:
	for battalion_id_value in _battalion_visuals.keys():
		var battalion_id: StringName = battalion_id_value
		var visual: Dictionary = _battalion_visuals[battalion_id]
		var root: Node3D = visual.get("root", null) as Node3D
		if root == null or not is_instance_valid(root):
			continue

		var position_duration: float = max(float(visual.get("position_duration", 0.001)), 0.001)
		var position_elapsed: float = min(position_duration, float(visual.get("position_elapsed", 0.0)) + delta)
		var position_t: float = _smoothstep01(position_elapsed / position_duration)
		visual["position_elapsed"] = position_elapsed
		var from_position: Vector3 = visual.get("from_position", root.position)
		var target_position: Vector3 = visual.get("target_position", root.position)
		root.position = from_position.lerp(target_position, position_t)

		var from_facing: Vector3 = _safe_facing(visual.get("from_facing", Vector3.FORWARD))
		var target_facing: Vector3 = _safe_facing(visual.get("target_facing", from_facing))
		var next_visual_facing: Vector3 = _lerp_facing(from_facing, target_facing, position_t)
		visual["visual_facing"] = next_visual_facing
		root.basis = _basis_for_facing(next_visual_facing)

		var cue_multimeshes: Dictionary = visual.get("cue_multimeshes", {})
		var cue_from_transforms: Dictionary = visual.get("cue_from_transforms", {})
		var cue_target_transforms: Dictionary = visual.get("cue_target_transforms", {})
		var cue_duration: float = max(float(visual.get("cue_duration", 0.001)), 0.001)
		var previous_cue_elapsed: float = float(visual.get("cue_elapsed", 0.0))
		var was_cue_complete: bool = previous_cue_elapsed >= cue_duration
		var cue_elapsed: float = min(cue_duration, previous_cue_elapsed + delta)
		var cue_t: float = _smoothstep01(cue_elapsed / cue_duration)
		visual["cue_elapsed"] = cue_elapsed
		if not was_cue_complete:
			for group_key_value in cue_multimeshes.keys():
				var group_key: String = String(group_key_value)
				var multimesh_instance: MultiMeshInstance3D = cue_multimeshes[group_key] as MultiMeshInstance3D
				if multimesh_instance == null or not is_instance_valid(multimesh_instance) or multimesh_instance.multimesh == null:
					continue
				var from_transforms: Array = cue_from_transforms.get(group_key, [])
				var target_transforms: Array = cue_target_transforms.get(group_key, [])
				var cue_limit: int = min(multimesh_instance.multimesh.instance_count, min(from_transforms.size(), target_transforms.size()))
				for cue_index in range(cue_limit):
					var from_transform: Transform3D = from_transforms[cue_index]
					var target_transform: Transform3D = target_transforms[cue_index]
					var next_transform: Transform3D = target_transform
					next_transform.origin = from_transform.origin.lerp(target_transform.origin, cue_t)
					multimesh_instance.multimesh.set_instance_transform(cue_index, next_transform)

		_battalion_visuals[battalion_id] = visual


func _safe_facing(facing: Vector3) -> Vector3:
	if facing.length_squared() <= 0.0001:
		return Vector3.FORWARD
	return facing.normalized()


func _lerp_facing(from_facing: Vector3, target_facing: Vector3, weight: float) -> Vector3:
	var mixed: Vector3 = from_facing.lerp(target_facing, clamp(weight, 0.0, 1.0))
	return _safe_facing(mixed)


func _basis_for_facing(facing: Vector3) -> Basis:
	var forward: Vector3 = _safe_facing(facing)
	var side := Vector3(-forward.z, 0.0, forward.x).normalized()
	return Basis(side, Vector3.UP, forward)


func _smoothstep01(value: float) -> float:
	var t: float = clamp(value, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


func _get_static_terrain_patches() -> Array:
	return _latest_snapshot.get("channels", {}).get("static_world", {}).get("terrain_patches", [])


func _create_ground_mesh(map_rect: Rect2, terrain_patches: Array) -> Node3D:
	var root := Node3D.new()
	root.name = "GroundHeightfield"
	var ground_mesh: ArrayMesh = _build_heightfield_mesh(map_rect, terrain_patches)

	var ground := MeshInstance3D.new()
	ground.name = "GroundMesh"
	ground.mesh = ground_mesh
	ground.material_override = _make_material(Color(0.29, 0.4, 0.22), false, false)
	root.add_child(ground)

	var body := StaticBody3D.new()
	body.name = "GroundCollision"
	var collision := CollisionShape3D.new()
	collision.shape = ground_mesh.create_trimesh_shape()
	body.add_child(collision)
	root.add_child(body)
	return root


func _build_heightfield_mesh(map_rect: Rect2, terrain_patches: Array) -> ArrayMesh:
	# Сітку будуємо по межах patches, щоб карта 10x10 км не ставала щільною heightmap.
	var x_coords: Array = _build_heightfield_axis_coords(
		map_rect.position.x,
		map_rect.position.x + map_rect.size.x,
		terrain_patches,
		true
	)
	var z_coords: Array = _build_heightfield_axis_coords(
		map_rect.position.y,
		map_rect.position.y + map_rect.size.y,
		terrain_patches,
		false
	)
	var surface_tool := SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for x_index in range(x_coords.size() - 1):
		for z_index in range(z_coords.size() - 1):
			var x0: float = float(x_coords[x_index])
			var x1: float = float(x_coords[x_index + 1])
			var z0: float = float(z_coords[z_index])
			var z1: float = float(z_coords[z_index + 1])
			if x1 - x0 <= 0.01 or z1 - z0 <= 0.01:
				continue
			_add_terrain_surface_quad(surface_tool, x0, x1, z0, z1, terrain_patches, 0.0)
	surface_tool.generate_normals()
	return surface_tool.commit()


func _build_heightfield_axis_coords(min_value: float, max_value: float, terrain_patches: Array, use_x_axis: bool) -> Array:
	var coords: Array = [min_value, max_value]
	var grid_coord: float = ceil(min_value / HEIGHTFIELD_GRID_STEP_M) * HEIGHTFIELD_GRID_STEP_M
	while grid_coord < max_value:
		coords.append(grid_coord)
		grid_coord += HEIGHTFIELD_GRID_STEP_M
	for patch_value in terrain_patches:
		var patch: Dictionary = patch_value
		var patch_rect: Rect2 = patch.get("rect", Rect2())
		var start_value: float = patch_rect.position.x if use_x_axis else patch_rect.position.y
		var end_value: float = start_value + (patch_rect.size.x if use_x_axis else patch_rect.size.y)
		var fade_m: float = _get_static_height_fade_m(patch, patch_rect)
		coords.append(clamp(start_value, min_value, max_value))
		coords.append(clamp(end_value, min_value, max_value))
		coords.append(clamp(start_value + fade_m, min_value, max_value))
		coords.append(clamp(end_value - fade_m, min_value, max_value))
	coords.sort()
	return _unique_sorted_heightfield_coords(coords)


func _unique_sorted_heightfield_coords(coords: Array) -> Array:
	var result: Array = []
	for coord_value in coords:
		var coord: float = float(coord_value)
		if result.is_empty() or absf(coord - float(result[result.size() - 1])) > 0.01:
			result.append(coord)
	return result


func _sample_static_height_at(point_2d: Vector2, terrain_patches: Array) -> float:
	var height_m: float = 0.0
	for patch_value in terrain_patches:
		var patch: Dictionary = patch_value
		var influence: float = _get_static_height_patch_influence(point_2d, patch)
		if influence <= 0.0:
			continue
		height_m = lerp(height_m, float(patch.get("height_m", height_m)), influence)
	return height_m


func _get_static_height_patch_influence(point_2d: Vector2, patch: Dictionary) -> float:
	var patch_rect: Rect2 = patch.get("rect", Rect2())
	if not patch_rect.has_point(point_2d):
		return 0.0
	var fade_m: float = _get_static_height_fade_m(patch, patch_rect)
	if fade_m <= 0.01:
		return 1.0
	var distance_to_edge: float = min(
		min(point_2d.x - patch_rect.position.x, patch_rect.end.x - point_2d.x),
		min(point_2d.y - patch_rect.position.y, patch_rect.end.y - point_2d.y)
	)
	var max_fade_m: float = max(1.0, min(absf(patch_rect.size.x), absf(patch_rect.size.y)) * 0.5)
	return _smoothstep01(distance_to_edge / min(fade_m, max_fade_m))


func _get_static_height_fade_m(patch: Dictionary, patch_rect: Rect2) -> float:
	return max(0.0, float(patch.get("height_fade_m", _default_static_height_fade_m(patch_rect))))


func _default_static_height_fade_m(rect: Rect2) -> float:
	return clamp(
		min(absf(rect.size.x), absf(rect.size.y)) * 0.28,
		TERRAIN_HEIGHT_FADE_MIN_M,
		TERRAIN_HEIGHT_FADE_MAX_M
	)


func _build_terrain_aligned_rect_mesh(rect: Rect2, terrain_patches: Array, height_offset_m: float) -> ArrayMesh:
	var x_coords: Array = _build_rect_axis_coords(rect.position.x, rect.position.x + rect.size.x, TERRAIN_OVERLAY_GRID_STEP_M)
	var z_coords: Array = _build_rect_axis_coords(rect.position.y, rect.position.y + rect.size.y, TERRAIN_OVERLAY_GRID_STEP_M)
	var surface_tool := SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for x_index in range(x_coords.size() - 1):
		for z_index in range(z_coords.size() - 1):
			var x0: float = float(x_coords[x_index])
			var x1: float = float(x_coords[x_index + 1])
			var z0: float = float(z_coords[z_index])
			var z1: float = float(z_coords[z_index + 1])
			if x1 - x0 <= 0.01 or z1 - z0 <= 0.01:
				continue
			_add_terrain_surface_quad(surface_tool, x0, x1, z0, z1, terrain_patches, height_offset_m)
	surface_tool.generate_normals()
	return surface_tool.commit()


func _build_rect_axis_coords(min_value: float, max_value: float, step_m: float) -> Array:
	var coords: Array = [min_value, max_value]
	var grid_coord: float = ceil(min_value / step_m) * step_m
	while grid_coord < max_value:
		coords.append(grid_coord)
		grid_coord += step_m
	coords.sort()
	return _unique_sorted_heightfield_coords(coords)


func _add_terrain_surface_quad(
		surface_tool: SurfaceTool,
		x0: float,
		x1: float,
		z0: float,
		z1: float,
		terrain_patches: Array,
		height_offset_m: float
) -> void:
	var v00: Vector3 = _terrain_surface_vertex(x0, z0, terrain_patches, height_offset_m)
	var v01: Vector3 = _terrain_surface_vertex(x0, z1, terrain_patches, height_offset_m)
	var v11: Vector3 = _terrain_surface_vertex(x1, z1, terrain_patches, height_offset_m)
	var v10: Vector3 = _terrain_surface_vertex(x1, z0, terrain_patches, height_offset_m)
	_add_terrain_quad(surface_tool, v00, v01, v11, v10)


func _terrain_surface_vertex(x: float, z: float, terrain_patches: Array, height_offset_m: float) -> Vector3:
	var height_m: float = _sample_static_height_at(Vector2(x, z), terrain_patches)
	return Vector3(x, height_m + height_offset_m, z)


func _add_terrain_quad(surface_tool: SurfaceTool, v0: Vector3, v1: Vector3, v2: Vector3, v3: Vector3) -> void:
	surface_tool.add_vertex(v0)
	surface_tool.add_vertex(v1)
	surface_tool.add_vertex(v2)
	surface_tool.add_vertex(v0)
	surface_tool.add_vertex(v2)
	surface_tool.add_vertex(v3)


func _create_terrain_patch_node(terrain_snapshot: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "Terrain_%s" % String(terrain_snapshot.get("id", "patch"))
	var terrain_rect: Rect2 = terrain_snapshot.get("rect", Rect2())
	var terrain_patches: Array = _get_static_terrain_patches()
	var center_2d: Vector2 = terrain_rect.get_center()
	var height_m: float = _sample_static_height_at(center_2d, terrain_patches)

	var patch := MeshInstance3D.new()
	patch.mesh = _build_terrain_aligned_rect_mesh(terrain_rect, terrain_patches, TERRAIN_OVERLAY_HEIGHT_OFFSET_M)
	var patch_color: Color = terrain_snapshot.get("color", Color(0.4, 0.42, 0.32, 0.5))
	patch.material_override = _make_material(patch_color, true, true)
	root.add_child(patch)

	var label := Label3D.new()
	label.text = "%s\nv%.2f los%.2f" % [
		String(terrain_snapshot.get("display_name", terrain_snapshot.get("terrain_label", "Terrain"))),
		float(terrain_snapshot.get("speed_multiplier", 1.0)),
		float(terrain_snapshot.get("vision_multiplier", 1.0)),
	]
	label.position = Vector3(center_2d.x, height_m + 32.0, center_2d.y)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color(0.88, 0.9, 0.74, 0.72)
	root.add_child(label)
	return root


func _create_road_node(road_snapshot: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "Road_%s" % String(road_snapshot.get("id", "road"))
	var points: Array = road_snapshot.get("points", [])
	if points.size() < 2:
		return root
	var width_m: float = float(road_snapshot.get("width_m", 90.0))
	var road_color: Color = road_snapshot.get("color", Color(0.46, 0.39, 0.25, 0.92))
	for index in range(points.size() - 1):
		var start_position: Vector3 = points[index]
		var end_position: Vector3 = points[index + 1]
		root.add_child(_create_road_segment_node(start_position, end_position, width_m, road_color))
	return root


func _create_road_segment_node(start_position: Vector3, end_position: Vector3, width_m: float, road_color: Color) -> Node3D:
	var root := Node3D.new()
	var length: float = start_position.distance_to(end_position)
	if length <= 0.01:
		return root
	var midpoint: Vector3 = (start_position + end_position) * 0.5
	root.position = Vector3(midpoint.x, midpoint.y + 2.0, midpoint.z)
	root.look_at_from_position(root.position, Vector3(end_position.x, end_position.y + 2.0, end_position.z), Vector3.UP, true)

	var marker := MeshInstance3D.new()
	marker.mesh = _get_box_mesh(Vector3(width_m, 2.0, length))
	marker.material_override = _make_material(road_color, true, true)
	root.add_child(marker)
	return root


func _create_smoke_zone_node(smoke_snapshot: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "Smoke_%s" % String(smoke_snapshot.get("id", "smoke"))
	var smoke_color: Color = smoke_snapshot.get("color", Color(0.58, 0.58, 0.53, 0.14))
	var puff_material_color: Color = smoke_color.lightened(0.06)
	puff_material_color.a = clamp(smoke_color.a, 0.07, 0.16)
	for puff_index in range(7):
		var puff := MeshInstance3D.new()
		puff.name = "SmokePuff_%d" % puff_index
		puff.mesh = _get_sphere_mesh(1.0, 1.0)
		puff.material_override = _make_material(puff_material_color, true, true)
		_configure_smoke_puff_meta(puff, puff_index)
		root.add_child(puff)
	_update_smoke_node(root, smoke_snapshot)
	return root


func _update_smoke_node(root: Node3D, smoke_snapshot: Dictionary) -> void:
	var smoke_position: Vector3 = smoke_snapshot.get("position", Vector3.ZERO)
	root.position = Vector3(smoke_position.x, smoke_position.y, smoke_position.z)
	var density: float = clamp(float(smoke_snapshot.get("density", 0.0)), 0.0, 1.0)
	root.visible = density > 0.035
	if not root.visible:
		return
	var radius_m: float = float(smoke_snapshot.get("radius_m", 120.0))
	var height_m: float = float(smoke_snapshot.get("height_m", 20.0))
	var forward: Vector3 = smoke_snapshot.get("direction", Vector3.FORWARD)
	forward.y = 0.0
	if forward.length_squared() <= 0.001:
		forward = Vector3.FORWARD
	forward = forward.normalized()
	var right := Vector3(forward.z, 0.0, -forward.x)
	var density_scale: float = lerp(0.62, 1.0, density)
	for child in root.get_children():
		var puff: MeshInstance3D = child as MeshInstance3D
		if puff == null:
			continue
		var forward_offset_m: float = radius_m * float(puff.get_meta("forward_weight", 0.0))
		var side_offset_m: float = radius_m * float(puff.get_meta("side_weight", 0.0))
		var lift_m: float = max(5.0, height_m * float(puff.get_meta("lift_weight", 0.45)))
		puff.position = forward * forward_offset_m + right * side_offset_m + Vector3(0.0, lift_m, 0.0)
		puff.scale = Vector3(
			radius_m * float(puff.get_meta("scale_x", 0.35)) * density_scale,
			max(4.0, height_m * float(puff.get_meta("scale_y", 0.65))) * density_scale,
			radius_m * float(puff.get_meta("scale_z", 0.35)) * density_scale
		)


func _configure_smoke_puff_meta(puff: MeshInstance3D, puff_index: int) -> void:
	var layouts: Array = [
		[0.00, 0.00, 0.42, 0.38, 0.78, 0.34],
		[0.22, -0.20, 0.54, 0.32, 0.66, 0.30],
		[0.24, 0.18, 0.48, 0.30, 0.62, 0.28],
		[0.46, -0.08, 0.62, 0.34, 0.76, 0.36],
		[0.58, 0.16, 0.50, 0.28, 0.58, 0.30],
		[-0.18, -0.12, 0.36, 0.26, 0.50, 0.24],
		[0.34, 0.00, 0.76, 0.24, 0.48, 0.22],
	]
	var layout: Array = layouts[puff_index % layouts.size()]
	puff.set_meta("forward_weight", float(layout[0]))
	puff.set_meta("side_weight", float(layout[1]))
	puff.set_meta("lift_weight", float(layout[2]))
	puff.set_meta("scale_x", float(layout[3]))
	puff.set_meta("scale_y", float(layout[4]))
	puff.set_meta("scale_z", float(layout[5]))


func _create_zone_mesh(zone_snapshot: Dictionary) -> Node3D:
	var zone_rect: Rect2 = zone_snapshot.get("rect", Rect2())
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = _build_terrain_aligned_rect_mesh(
		zone_rect,
		_get_static_terrain_patches(),
		DEPLOYMENT_ZONE_HEIGHT_OFFSET_M
	)

	var zone_color: Color = zone_snapshot.get("color", Color(0.5, 0.5, 0.5, 1.0))
	var tint: Color = zone_color.lightened(0.24)
	tint.a = 0.22
	mesh_instance.material_override = _make_material(tint, true, true)
	return mesh_instance


func _create_objective_node(objective_snapshot: Dictionary) -> Node3D:
	var root := Node3D.new()
	var position_value: Vector3 = objective_snapshot.get("position", Vector3.ZERO)
	root.position = position_value

	var marker := MeshInstance3D.new()
	marker.mesh = _get_cylinder_mesh(58.0, 58.0, 28.0)
	marker.position.y = 14.0
	marker.material_override = _make_material(objective_snapshot.get("owner_color", Color(0.68, 0.68, 0.68)), false, false)
	root.add_child(marker)

	var label := Label3D.new()
	label.text = "%s\n%s" % [objective_snapshot.get("display_name", ""), objective_snapshot.get("owner_name", "")]
	label.position = Vector3(0.0, 62.0, 0.0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	root.add_child(label)

	return root


func _create_hq_node(hq_snapshot: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.position = hq_snapshot.get("position", Vector3.ZERO)

	var marker := MeshInstance3D.new()
	var mesh := _get_cylinder_mesh(42.0, 42.0, 48.0)
	marker.mesh = mesh
	marker.position.y = 24.0
	marker.material_override = _make_material(hq_snapshot.get("color", Color(1.0, 1.0, 1.0)), false, false)
	root.add_child(marker)

	var label := Label3D.new()
	label.text = String(hq_snapshot.get("display_name", "Штаб"))
	label.position = Vector3(0.0, 72.0, 0.0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	root.add_child(label)

	return root


func _create_baggage_node(baggage_snapshot: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.position = baggage_snapshot.get("position", Vector3.ZERO)

	var marker := MeshInstance3D.new()
	var mesh := _get_box_mesh(Vector3(120.0, 26.0, 88.0))
	marker.mesh = mesh
	marker.position.y = 13.0
	marker.material_override = _make_material(baggage_snapshot.get("color", Color(0.84, 0.76, 0.48)), false, false)
	root.add_child(marker)

	var label := Label3D.new()
	label.text = "Обоз"
	label.position = Vector3(0.0, 56.0, 0.0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	root.add_child(label)

	return root


func _create_order_messenger_node(messenger_snapshot: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.position = messenger_snapshot.get("position", Vector3.ZERO)

	var base_color: Color = messenger_snapshot.get("color", Color(0.92, 0.84, 0.42))
	var marker := MeshInstance3D.new()
	marker.mesh = _get_cylinder_mesh(16.0, 16.0, 20.0)
	marker.position.y = 12.0
	marker.material_override = _make_material(base_color, false, false)
	root.add_child(marker)

	var rider := MeshInstance3D.new()
	rider.mesh = _get_box_mesh(Vector3(10.0, 14.0, 20.0))
	rider.position.y = 30.0
	rider.material_override = _make_material(base_color.lightened(0.18), false, false)
	root.add_child(rider)

	var label := Label3D.new()
	label.text = "%s\n%s %.0f м" % [
		messenger_snapshot.get("display_name", "Гінець"),
		messenger_snapshot.get("order_label", "Наказ"),
		float(messenger_snapshot.get("distance_remaining_m", 0.0)),
	]
	label.position = Vector3(0.0, 62.0, 0.0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	root.add_child(label)

	return root


func _create_last_seen_marker_node(marker_snapshot: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.position = marker_snapshot.get("position", Vector3.ZERO)

	var marker := MeshInstance3D.new()
	var mesh := _get_cylinder_mesh(54.0, 54.0, 4.0)
	marker.mesh = mesh
	marker.position.y = 2.0
	marker.material_override = _make_material(Color(0.95, 0.88, 0.36, 0.34), true, true)
	root.add_child(marker)

	var pin := MeshInstance3D.new()
	var pin_mesh := _get_cylinder_mesh(10.0, 18.0, 72.0)
	pin.mesh = pin_mesh
	pin.position.y = 36.0
	pin.material_override = _make_material(Color(0.95, 0.78, 0.24, 0.72), true, true)
	root.add_child(pin)

	var label := Label3D.new()
	label.text = "%s\n%.0f с тому" % [
		marker_snapshot.get("display_name", "Останній контакт"),
		float(marker_snapshot.get("seconds_ago", 0.0)),
	]
	label.position = Vector3(0.0, 98.0, 0.0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	root.add_child(label)

	return root


func _create_link_line(start_position: Vector3, end_position: Vector3, line_color: Color) -> Node3D:
	var root := Node3D.new()
	var midpoint: Vector3 = (start_position + end_position) * 0.5
	var length: float = start_position.distance_to(end_position)
	root.position = Vector3(midpoint.x, 6.0, midpoint.z)
	root.look_at_from_position(root.position, Vector3(end_position.x, 6.0, end_position.z), Vector3.UP, true)

	var marker := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(8.0, 4.0, length)
	marker.mesh = mesh
	marker.material_override = _make_material(line_color, true, true)
	root.add_child(marker)
	return root


func _ensure_selection_overlay_nodes() -> void:
	if _selection_disk == null or not is_instance_valid(_selection_disk):
		_selection_disk = MeshInstance3D.new()
		_selection_disk.name = "SelectionDisk"
		_selection_root.add_child(_selection_disk)
	if _selection_ring == null or not is_instance_valid(_selection_ring):
		_selection_ring = MeshInstance3D.new()
		_selection_ring.name = "SelectionBaseLos"
		_selection_root.add_child(_selection_ring)
	if _selection_contour == null or not is_instance_valid(_selection_contour):
		_selection_contour = MeshInstance3D.new()
		_selection_contour.name = "SelectionBlockedLos"
		_selection_root.add_child(_selection_contour)
	if _selection_member_root == null or not is_instance_valid(_selection_member_root):
		_selection_member_root = Node3D.new()
		_selection_member_root.name = "SelectionBrigadeMembers"
		_selection_root.add_child(_selection_member_root)


func _update_selection_disk(world_position: Vector3, disk_color: Color) -> void:
	_selection_disk.mesh = _get_cylinder_mesh(72.0, 72.0, 2.0)
	_selection_disk.position = Vector3(world_position.x, world_position.y + 1.5, world_position.z)
	var color_with_alpha: Color = disk_color.lightened(0.2)
	color_with_alpha.a = 0.28
	_selection_disk.material_override = _make_material(color_with_alpha, true, true)


func _update_los_ring(mesh_instance: MeshInstance3D, world_position: Vector3, radius: float, ring_color: Color) -> void:
	var immediate := ImmediateMesh.new()
	immediate.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for index in range(49):
		var angle: float = TAU * float(index) / 48.0
		var vertex: Vector3 = world_position + Vector3(cos(angle) * radius, 4.0, sin(angle) * radius)
		immediate.surface_set_color(ring_color)
		immediate.surface_add_vertex(vertex)
	immediate.surface_end()
	mesh_instance.mesh = immediate
	mesh_instance.material_override = _make_material(ring_color, true, true)


func _update_los_contour(mesh_instance: MeshInstance3D, world_position: Vector3, radius: float, contour_color: Color) -> void:
	var immediate := ImmediateMesh.new()
	immediate.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for index in range(DEBUG_LOS_RAY_COUNT + 1):
		var angle: float = TAU * float(index) / float(DEBUG_LOS_RAY_COUNT)
		var direction := Vector3(cos(angle), 0.0, sin(angle))
		var traced_radius: float = _trace_debug_los_radius(world_position, direction, radius)
		var vertex: Vector3 = world_position + direction * traced_radius + Vector3(0.0, 6.0, 0.0)
		immediate.surface_set_color(contour_color)
		immediate.surface_add_vertex(vertex)
	immediate.surface_end()
	mesh_instance.mesh = immediate
	mesh_instance.material_override = _make_material(contour_color, true, true)


func _trace_debug_los_radius(origin: Vector3, direction: Vector3, max_radius: float) -> float:
	var distance_m: float = 0.0
	var cover_depth_m: float = 0.0
	var was_inside_cover: bool = false
	var smoke_depth_m: float = 0.0
	var was_inside_smoke: bool = false
	while distance_m < max_radius:
		var next_distance_m: float = min(max_radius, distance_m + DEBUG_LOS_SAMPLE_STEP_M)
		var sample_position: Vector3 = origin + direction * next_distance_m
		var sample_step_m: float = next_distance_m - distance_m
		var smoke_density: float = _get_debug_los_smoke_density_at(sample_position)
		if smoke_density <= 0.01:
			smoke_depth_m = 0.0
			was_inside_smoke = false
		else:
			smoke_depth_m += (sample_step_m if was_inside_smoke else sample_step_m * 0.5) * smoke_density
			was_inside_smoke = true
			var smoke_penetration_m: float = _get_debug_los_smoke_penetration_at(sample_position)
			if smoke_depth_m > smoke_penetration_m:
				return max(0.0, next_distance_m - ((smoke_depth_m - smoke_penetration_m) / max(smoke_density, 0.01)))
		var cover_height: float = _get_debug_los_cover_height_at(sample_position)
		if cover_height <= 0.01:
			cover_depth_m = 0.0
			was_inside_cover = false
			distance_m = next_distance_m
			continue
		cover_depth_m += sample_step_m if was_inside_cover else sample_step_m * 0.5
		was_inside_cover = true
		var cover_penetration_m: float = _get_debug_los_cover_penetration_at(sample_position)
		if cover_depth_m > cover_penetration_m:
			return max(0.0, next_distance_m - (cover_depth_m - cover_penetration_m))
		distance_m = next_distance_m
	return max_radius


func _get_debug_los_cover_height_at(world_position: Vector3) -> float:
	match _get_debug_terrain_type_at(world_position):
		CoreV2Types.TerrainType.FOREST:
			return 18.0
		CoreV2Types.TerrainType.TOWN:
			return 14.0
		CoreV2Types.TerrainType.VILLAGE:
			return 8.0
		CoreV2Types.TerrainType.BRUSH:
			return 4.0
		CoreV2Types.TerrainType.FARM:
			return 2.0
		_:
			return 0.0


func _get_debug_los_cover_penetration_at(world_position: Vector3) -> float:
	match _get_debug_terrain_type_at(world_position):
		CoreV2Types.TerrainType.FOREST:
			return 100.0
		CoreV2Types.TerrainType.TOWN:
			return 80.0
		CoreV2Types.TerrainType.VILLAGE:
			return 110.0
		CoreV2Types.TerrainType.BRUSH:
			return 150.0
		CoreV2Types.TerrainType.FARM:
			return 220.0
		_:
			return INF


func _get_debug_los_smoke_density_at(world_position: Vector3) -> float:
	var point_2d := Vector2(world_position.x, world_position.z)
	var density: float = 0.0
	var smoke_zones: Array = _get_debug_smoke_zones()
	for smoke_value in smoke_zones:
		var smoke: Dictionary = smoke_value
		var smoke_position: Vector3 = smoke.get("position", Vector3.ZERO)
		var smoke_radius_m: float = float(smoke.get("radius_m", 0.0))
		if smoke_radius_m <= 0.01:
			continue
		var distance_m: float = point_2d.distance_to(Vector2(smoke_position.x, smoke_position.z))
		if distance_m > smoke_radius_m:
			continue
		var edge_factor: float = 1.0 - clamp(distance_m / smoke_radius_m, 0.0, 1.0)
		var smoke_density: float = float(smoke.get("density", 0.0)) * (0.35 + 0.65 * edge_factor)
		density = max(density, smoke_density)
	return clamp(density, 0.0, 1.0)


func _get_debug_los_smoke_penetration_at(world_position: Vector3) -> float:
	var point_2d := Vector2(world_position.x, world_position.z)
	var penetration_m: float = INF
	var smoke_zones: Array = _get_debug_smoke_zones()
	for smoke_value in smoke_zones:
		var smoke: Dictionary = smoke_value
		var smoke_position: Vector3 = smoke.get("position", Vector3.ZERO)
		var smoke_radius_m: float = float(smoke.get("radius_m", 0.0))
		if smoke_radius_m <= 0.01:
			continue
		if point_2d.distance_to(Vector2(smoke_position.x, smoke_position.z)) > smoke_radius_m:
			continue
		penetration_m = min(penetration_m, float(smoke.get("penetration_m", penetration_m)))
	return penetration_m


func _get_debug_smoke_zones() -> Array:
	var channels: Dictionary = _latest_snapshot.get("channels", {})
	var smoke_zones: Array = []
	smoke_zones.append_array(channels.get("static_world", {}).get("smoke_zones", []))
	smoke_zones.append_array(channels.get("units", {}).get("smoke_zones", []))
	return smoke_zones


func _get_debug_terrain_type_at(world_position: Vector3) -> int:
	var terrain_type: int = CoreV2Types.TerrainType.PLAIN
	var point_2d := Vector2(world_position.x, world_position.z)
	var terrain_patches: Array = _latest_snapshot.get("channels", {}).get("static_world", {}).get("terrain_patches", [])
	for patch_value in terrain_patches:
		var patch: Dictionary = patch_value
		var patch_rect: Rect2 = patch.get("rect", Rect2())
		if patch_rect.has_point(point_2d):
			terrain_type = int(patch.get("terrain_type", terrain_type))
	return terrain_type


func _get_visual_cue_basis(_facing: Vector3 = Vector3.FORWARD) -> Basis:
	return Basis.IDENTITY.scaled(Vector3.ONE * VISUAL_CUE_MODEL_SCALE)


func _get_visual_cue_mesh(model_role: String) -> Mesh:
	if _unit_mesh_cache.has(model_role):
		return _unit_mesh_cache[model_role] as Mesh
	var model_path: String = MUSKETEER_VISUAL_RESOURCE_PATH if model_role == "musketeer" else PIKEMAN_VISUAL_RESOURCE_PATH
	var loaded_mesh: Mesh = load(model_path) as Mesh
	if loaded_mesh == null:
		loaded_mesh = _get_box_mesh(_get_visual_cue_fallback_size(model_role))
	_unit_mesh_cache[model_role] = loaded_mesh
	return loaded_mesh


func _get_visual_cue_fallback_size(model_role: String) -> Vector3:
	match model_role:
		"pikeman":
			return Vector3(7.0, 8.0, 8.0)
		"musketeer":
			return Vector3(8.0, 8.0, 7.0)
		_:
			return Vector3(8.0, 8.0, 8.0)


func _get_visual_cue_color(model_role: String, battalion_color: Color) -> Color:
	match model_role:
		"pikeman":
			return battalion_color.lightened(0.24)
		"musketeer":
			return battalion_color.darkened(0.12)
		_:
			return battalion_color


func _get_visual_cue_material(model_role: String, battalion_color: Color) -> StandardMaterial3D:
	var color_value: Color = _get_visual_cue_color(model_role, battalion_color)
	var cache_key: String = "%s:%s" % [model_role, color_value.to_html(true)]
	if _unit_material_cache.has(cache_key):
		return _unit_material_cache[cache_key] as StandardMaterial3D
	var material := StandardMaterial3D.new()
	material.albedo_color = color_value
	material.albedo_texture = _get_unit_atlas_texture()
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_unit_material_cache[cache_key] = material
	return material


func _get_unit_atlas_texture() -> Texture2D:
	if _unit_atlas_texture != null:
		return _unit_atlas_texture
	_unit_atlas_texture = load(UNIT_ATLAS_PATH) as Texture2D
	return _unit_atlas_texture


func _get_formation_body_mesh(
		frontage_m: float,
		height_m: float,
		depth_m: float,
		irregularity: float,
		compression: float,
		pressure: float,
		shape_seed: int
) -> Mesh:
	var frontage_bucket: int = int(round(frontage_m / 4.0))
	var height_bucket: int = int(round(height_m / 1.0))
	var depth_bucket: int = int(round(depth_m / 4.0))
	var irregularity_bucket: int = int(round(clamp(irregularity, 0.0, 1.0) * 10.0))
	var compression_bucket: int = int(round(clamp(compression, 0.0, 1.0) * 10.0))
	var pressure_bucket: int = int(round(clamp(pressure, 0.0, 1.0) * 10.0))
	var seed_bucket: int = abs(shape_seed) % 97
	var cache_key: String = "%d:%d:%d:%d:%d:%d:%d" % [
		frontage_bucket,
		height_bucket,
		depth_bucket,
		irregularity_bucket,
		compression_bucket,
		pressure_bucket,
		seed_bucket,
	]
	if _formation_mesh_cache.has(cache_key):
		return _formation_mesh_cache[cache_key] as Mesh
	var points: Array = _build_formation_outline_points(
		float(frontage_bucket) * 4.0,
		float(depth_bucket) * 4.0,
		float(irregularity_bucket) / 10.0,
		float(compression_bucket) / 10.0,
		float(pressure_bucket) / 10.0,
		shape_seed
	)
	var mesh: Mesh = _build_prism_mesh(points, max(1.0, float(height_bucket)))
	_formation_mesh_cache[cache_key] = mesh
	return mesh


func _build_formation_outline_points(frontage_m: float, depth_m: float, irregularity: float, compression: float, pressure: float, shape_seed: int) -> Array:
	var half_width: float = max(8.0, frontage_m * 0.5)
	var half_depth: float = max(6.0, depth_m * 0.5)
	var wave_m: float = 1.2 + irregularity * 9.5 + pressure * 5.0
	var front_bow_m: float = pressure * 6.0 + compression * 4.0
	var edge_slack_m: float = irregularity * 5.5 + compression * 2.0
	return [
		Vector2(-half_width + _shape_noise(shape_seed, 0) * edge_slack_m, -half_depth + _shape_noise(shape_seed, 1) * wave_m * 0.45),
		Vector2(-half_width * 0.55 + _shape_noise(shape_seed, 2) * wave_m, -half_depth - _shape_noise(shape_seed, 3) * wave_m * 0.35),
		Vector2(_shape_noise(shape_seed, 4) * wave_m * 0.5, -half_depth - front_bow_m + _shape_noise(shape_seed, 5) * wave_m * 0.25),
		Vector2(half_width * 0.55 + _shape_noise(shape_seed, 6) * wave_m, -half_depth - _shape_noise(shape_seed, 7) * wave_m * 0.35),
		Vector2(half_width + _shape_noise(shape_seed, 8) * edge_slack_m, -half_depth + _shape_noise(shape_seed, 9) * wave_m * 0.45),
		Vector2(half_width + edge_slack_m * 0.45, _shape_noise(shape_seed, 10) * wave_m * 0.35),
		Vector2(half_width + _shape_noise(shape_seed, 11) * edge_slack_m, half_depth + _shape_noise(shape_seed, 12) * wave_m * 0.35),
		Vector2(half_width * 0.40 + _shape_noise(shape_seed, 13) * wave_m, half_depth + _shape_noise(shape_seed, 14) * wave_m * 0.30),
		Vector2(_shape_noise(shape_seed, 15) * wave_m * 0.4, half_depth + _shape_noise(shape_seed, 16) * wave_m * 0.35),
		Vector2(-half_width * 0.40 + _shape_noise(shape_seed, 17) * wave_m, half_depth + _shape_noise(shape_seed, 18) * wave_m * 0.30),
		Vector2(-half_width + _shape_noise(shape_seed, 19) * edge_slack_m, half_depth + _shape_noise(shape_seed, 20) * wave_m * 0.35),
		Vector2(-half_width - edge_slack_m * 0.45, _shape_noise(shape_seed, 21) * wave_m * 0.35),
	]


func _shape_noise(shape_seed: int, index: int) -> float:
	return sin(float(abs(shape_seed) % 1009) * 0.037 + float(index) * 1.713)


func _build_prism_mesh(points: Array, height_m: float) -> Mesh:
	var vertices: Array = []
	var normals: Array = []
	var top_center := Vector3.ZERO
	for point_value in points:
		var point: Vector2 = point_value
		top_center += Vector3(point.x, height_m, point.y)
	top_center /= float(max(1, points.size()))
	for index in range(points.size()):
		var next_index: int = (index + 1) % points.size()
		var point_a: Vector2 = points[index]
		var point_b: Vector2 = points[next_index]
		var bottom_a := Vector3(point_a.x, 0.0, point_a.y)
		var bottom_b := Vector3(point_b.x, 0.0, point_b.y)
		var top_a := Vector3(point_a.x, height_m, point_a.y)
		var top_b := Vector3(point_b.x, height_m, point_b.y)
		_append_mesh_triangle(vertices, normals, top_center, top_a, top_b, Vector3.UP)
		var edge: Vector3 = top_b - top_a
		var side_normal := Vector3(edge.z, 0.0, -edge.x).normalized()
		if side_normal.length_squared() <= 0.001:
			side_normal = Vector3.FORWARD
		_append_mesh_triangle(vertices, normals, bottom_a, bottom_b, top_b, side_normal)
		_append_mesh_triangle(vertices, normals, bottom_a, top_b, top_a, side_normal)
	var packed_vertices := PackedVector3Array()
	var packed_normals := PackedVector3Array()
	for vertex_value in vertices:
		packed_vertices.append(vertex_value)
	for normal_value in normals:
		packed_normals.append(normal_value)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = packed_vertices
	arrays[Mesh.ARRAY_NORMAL] = packed_normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _append_mesh_triangle(vertices: Array, normals: Array, a: Vector3, b: Vector3, c: Vector3, normal: Vector3) -> void:
	vertices.append(a)
	vertices.append(b)
	vertices.append(c)
	normals.append(normal)
	normals.append(normal)
	normals.append(normal)


func _get_box_mesh(size_value: Vector3) -> BoxMesh:
	var cache_key: String = "%.2f:%.2f:%.2f" % [size_value.x, size_value.y, size_value.z]
	if _box_mesh_cache.has(cache_key):
		return _box_mesh_cache[cache_key] as BoxMesh
	var mesh := BoxMesh.new()
	mesh.size = size_value
	_box_mesh_cache[cache_key] = mesh
	return mesh


func _get_cylinder_mesh(top_radius: float, bottom_radius: float, height: float) -> CylinderMesh:
	var cache_key: String = "%.2f:%.2f:%.2f" % [top_radius, bottom_radius, height]
	if _cylinder_mesh_cache.has(cache_key):
		return _cylinder_mesh_cache[cache_key] as CylinderMesh
	var mesh := CylinderMesh.new()
	mesh.top_radius = top_radius
	mesh.bottom_radius = bottom_radius
	mesh.height = height
	_cylinder_mesh_cache[cache_key] = mesh
	return mesh


func _get_sphere_mesh(radius: float, height: float) -> SphereMesh:
	var cache_key: String = "%.2f:%.2f" % [radius, height]
	if _sphere_mesh_cache.has(cache_key):
		return _sphere_mesh_cache[cache_key] as SphereMesh
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = height
	mesh.radial_segments = 10
	mesh.rings = 6
	_sphere_mesh_cache[cache_key] = mesh
	return mesh


func _make_material(color_value: Color, transparent: bool, unshaded: bool) -> StandardMaterial3D:
	var cache_key: String = "%s:%s:%s" % [color_value.to_html(true), str(transparent), str(unshaded)]
	if _material_cache.has(cache_key):
		return _material_cache[cache_key] as StandardMaterial3D
	var material := StandardMaterial3D.new()
	material.albedo_color = color_value
	if transparent:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if unshaded:
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material_cache[cache_key] = material
	return material


func _clear_children(parent: Node) -> void:
	for child in parent.get_children():
		child.queue_free()
