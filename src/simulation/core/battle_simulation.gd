class_name BattleSimulation
extends RefCounted

const CombatSystemScript = preload("res://src/simulation/combat/combat_system.gd")
const RUNTIME_STAND_HEADCOUNT: int = 50
const SNAPSHOT_PAYLOAD_COARSE: int = 1
const SNAPSHOT_PAYLOAD_FULL: int = 2
const SNAPSHOT_FULL_DETAIL_ZOOM_THRESHOLD: float = 9999.0

# Pure authoritative simulation state. Presentation should only consume
# snapshots built by this class instead of reaching into live entities.
var map_rect: Rect2 = Rect2(0.0, 0.0, 1600.0, 900.0)
var time_seconds: float = 0.0

var armies: Dictionary = {}
var commanders: Dictionary = {}
var generals: Dictionary = {}
var brigades: Dictionary = {}
var regiments: Dictionary = {}
var battalions: Dictionary:
	get:
		return regiments
	set(value):
		regiments = value
var hqs: Dictionary = {}
var messengers: Dictionary = {}
var supply_convoys: Dictionary = {}
var strategic_points: Dictionary = {}
var terrain_regions: Array = []
var terrain_grid: TerrainGrid
var orders: Dictionary = {}

var command_queue: Array = []
var recent_events: Array = []
var visible_enemy_ids_by_army: Dictionary = {}
var last_seen_markers_by_army: Dictionary = {}
var fog_cache_by_army: Dictionary = {}
var fog_cache_interval_seconds: float = 0.3
var vision_outline_cache_interval_seconds: float = 0.3
var _last_snapshot_build_ms: float = 0.0
var _last_visibility_update_ms: float = 0.0
var _last_logistics_tick_ms: float = 0.0
var _last_ai_tick_ms: float = 0.0
var _last_behavior_tick_ms: float = 0.0
var _last_combat_tick_ms: float = 0.0
var _last_advance_tick_ms: float = 0.0
var _cached_terrain_snapshots: Array = []
var _vision_outline_cache_by_regiment: Dictionary = {}
var ai_tick_interval_seconds: float = 0.25
var visibility_tick_interval_seconds: float = 0.2
var logistics_tick_interval_seconds: float = 0.25
var _ai_tick_accumulator: float = 0.0
var _visibility_tick_accumulator: float = 0.0
var _logistics_tick_accumulator: float = 0.0
var general_ai_system: GeneralAISystem = GeneralAISystem.new()
var brigade_formation_planner_system: BrigadeFormationPlannerSystem = BrigadeFormationPlannerSystem.new()
var regiment_behavior_system: RegimentBehaviorSystem = RegimentBehaviorSystem.new()
var combat_system = CombatSystemScript.new()

var _next_order_index: int = 1
var _next_messenger_index: int = 1
var _next_convoy_index: int = 1


func queue_player_command(command: Dictionary) -> void:
	command_queue.append(command.duplicate(true))


func set_regiment_debug_formation(regiment_id: StringName, formation_state: int) -> void:
	var regiment: Battalion = regiments.get(regiment_id)
	if regiment == null:
		return
	regiment.debug_forced_formation_state = formation_state


func set_regiment_debug_fire_behavior(regiment_id: StringName, fire_behavior: int) -> void:
	var regiment: Battalion = regiments.get(regiment_id)
	if regiment == null:
		return
	regiment.debug_forced_fire_behavior = fire_behavior


func clear_regiment_debug_overrides(regiment_id: StringName) -> void:
	var regiment: Battalion = regiments.get(regiment_id)
	if regiment == null:
		return
	regiment.debug_forced_formation_state = -1
	regiment.debug_forced_fire_behavior = -1
	regiment.debug_test_fire_until = -1.0


func trigger_regiment_debug_fire(regiment_id: StringName, duration_seconds: float = 2.5) -> void:
	var regiment: Battalion = regiments.get(regiment_id)
	if regiment == null:
		return
	regiment.debug_test_fire_until = max(regiment.debug_test_fire_until, time_seconds + max(duration_seconds, 0.1))


func set_regiment_command_profile(regiment_id: StringName, profile_id: StringName) -> bool:
	var regiment: Battalion = regiments.get(regiment_id)
	if regiment == null:
		return false
	var profile: RegimentCommandProfile = RegimentProfileLibrary.get_command_profile(profile_id, regiment.category)
	if regiment.get_editor_company_count() > profile.max_companies:
		return false
	regiment.apply_command_profile(profile)
	_update_army_summaries()
	return true


func set_regiment_banner_profile(regiment_id: StringName, profile_id: StringName) -> bool:
	var regiment: Battalion = regiments.get(regiment_id)
	if regiment == null:
		return false
	regiment.apply_banner_profile(RegimentProfileLibrary.get_banner_profile(profile_id))
	_update_army_summaries()
	return true


func add_company_to_regiment(regiment_id: StringName, company_type: int) -> bool:
	var regiment: Battalion = regiments.get(regiment_id)
	if regiment == null or regiment.get_editor_company_count() >= regiment.get_max_company_capacity():
		return false
	var company_spec: Dictionary = _build_default_company_spec(regiment, company_type)
	if company_spec.is_empty():
		return false
	var new_stands: Array = _create_stands_from_company_spec(regiment, company_spec)
	if new_stands.is_empty():
		return false
	regiment.stands.append_array(new_stands)
	regiment.rebuild_after_company_change(false)
	regiment.initial_strength = regiment.get_total_strength()
	_update_army_summaries()
	return true


func remove_company_from_regiment(regiment_id: StringName, company_type: int) -> bool:
	var regiment: Battalion = regiments.get(regiment_id)
	if regiment == null or regiment.get_editor_company_count() <= 1:
		return false
	var target_tag: StringName = &""
	for stand_index in range(regiment.stands.size() - 1, -1, -1):
		var stand: CombatStand = regiment.stands[stand_index]
		if stand.company_type != company_type:
			continue
		target_tag = stand.editor_company_tag if stand.editor_company_tag != &"" else StringName(String(stand.id))
		break
	if target_tag == &"":
		return false
	for stand_index in range(regiment.stands.size() - 1, -1, -1):
		var stand: CombatStand = regiment.stands[stand_index]
		var stand_tag: StringName = stand.editor_company_tag if stand.editor_company_tag != &"" else StringName(String(stand.id))
		if stand_tag != target_tag:
			continue
		regiment.stands.remove_at(stand_index)
	regiment.rebuild_after_company_change(false)
	regiment.initial_strength = regiment.get_total_strength()
	_update_army_summaries()
	return true


func advance(delta: float) -> void:
	var advance_start_us: int = Time.get_ticks_usec()
	time_seconds += delta
	_process_player_commands()
	_tick_messengers(delta)
	brigade_formation_planner_system.tick(self, delta)
	var behavior_start_us: int = Time.get_ticks_usec()
	regiment_behavior_system.tick(self, delta)
	_last_behavior_tick_ms = float(Time.get_ticks_usec() - behavior_start_us) / 1000.0
	combat_system.tick(self, delta)
	_last_combat_tick_ms = combat_system.last_tick_ms
	_ai_tick_accumulator += delta
	_visibility_tick_accumulator += delta
	_logistics_tick_accumulator += delta
	if _ai_tick_accumulator >= ai_tick_interval_seconds:
		var ai_start_us: int = Time.get_ticks_usec()
		general_ai_system.tick(self, _ai_tick_accumulator)
		_last_ai_tick_ms = float(Time.get_ticks_usec() - ai_start_us) / 1000.0
		_ai_tick_accumulator = 0.0
	if _logistics_tick_accumulator >= logistics_tick_interval_seconds:
		var logistics_start_us: int = Time.get_ticks_usec()
		_tick_supply_convoys(_logistics_tick_accumulator)
		_tick_strategic_points(_logistics_tick_accumulator)
		_tick_last_seen_markers(_logistics_tick_accumulator)
		_update_army_summaries()
		_last_logistics_tick_ms = float(Time.get_ticks_usec() - logistics_start_us) / 1000.0
		_logistics_tick_accumulator = 0.0
	if _visibility_tick_accumulator >= visibility_tick_interval_seconds:
		var visibility_start_us: int = Time.get_ticks_usec()
		_update_visibility()
		_last_visibility_update_ms = float(Time.get_ticks_usec() - visibility_start_us) / 1000.0
		_visibility_tick_accumulator = 0.0
	_trim_recent_events()
	_last_advance_tick_ms = float(Time.get_ticks_usec() - advance_start_us) / 1000.0


func build_snapshot_for_army(army_id: StringName, view_interest: Dictionary = {}) -> Dictionary:
	var snapshot_start_us: int = Time.get_ticks_usec()
	var own_army: Army = armies.get(army_id)
	var visible_enemy_ids: Dictionary = visible_enemy_ids_by_army.get(army_id, {})
	var markers_for_army: Dictionary = last_seen_markers_by_army.get(army_id, {})
	var snapshot_interest: Dictionary = _resolve_snapshot_interest(view_interest)

	var regiment_snapshots: Array = []
	var friendly_regiment_count: int = 0
	for regiment in regiments.values():
		if regiment.army_id == army_id:
			friendly_regiment_count += 1
			if not _should_include_friendly_regiment_in_snapshot(regiment, snapshot_interest):
				continue
			var payload_lod: int = _get_snapshot_payload_lod(regiment, army_id, snapshot_interest, true)
			regiment_snapshots.append(_build_regiment_snapshot(regiment, true, SimTypes.IntelDetail.CLOSE, payload_lod))
		elif visible_enemy_ids.has(regiment.id) and _should_include_enemy_regiment_in_snapshot(regiment, snapshot_interest):
			var enemy_payload_lod: int = _get_snapshot_payload_lod(regiment, army_id, snapshot_interest, false)
			regiment_snapshots.append(_build_regiment_snapshot(
				regiment,
				false,
				int(visible_enemy_ids[regiment.id]),
				enemy_payload_lod
			))

	var hq_snapshots: Array = []
	for hq in hqs.values():
		if hq.army_id != army_id and not _is_hq_visible_to_army(hq, army_id):
			continue
		var brigade_id_for_hq: StringName = _get_brigade_id_for_hq(hq.id)
		if not _should_include_hq_in_snapshot(hq, brigade_id_for_hq, army_id, snapshot_interest):
			continue
		hq_snapshots.append({
			"id": String(hq.id),
			"display_name": hq.display_name,
			"position": hq.position,
			"army_id": String(hq.army_id),
			"role": hq.role,
			"brigade_id": String(brigade_id_for_hq),
			"is_friendly": hq.army_id == army_id,
			"is_operational": hq.is_operational(),
		})

	var strategic_snapshots: Array = []
	for point in strategic_points.values():
		if not _rect_intersects_circle(snapshot_interest.get("units_rect", map_rect), point.position, point.radius):
			continue
		strategic_snapshots.append({
			"id": String(point.id),
			"display_name": point.display_name,
			"position": point.position,
			"radius": point.radius,
			"controlling_army_id": String(point.controlling_army_id),
			"capture_progress": point.capture_progress,
		})

	var marker_snapshots: Array = []
	for marker in markers_for_army.values():
		if not _rect_intersects_circle(snapshot_interest.get("units_rect", map_rect), marker.position, 32.0):
			continue
		marker_snapshots.append({
			"enemy_regiment_id": String(marker.enemy_regiment_id),
			"position": marker.position,
			"detail_level": marker.detail_level,
			"remaining_time": marker.remaining_time,
			"label": marker.label,
		})

	var messenger_snapshots: Array = []
	for messenger in messengers.values():
		if messenger.army_id != army_id and not _is_position_visible_to_army(messenger.position, army_id):
			continue
		if not _rect_intersects_circle(snapshot_interest.get("units_rect", map_rect), messenger.position, 24.0):
			continue
		messenger_snapshots.append({
			"id": String(messenger.id),
			"position": messenger.position,
			"army_id": String(messenger.army_id),
			"is_friendly": messenger.army_id == army_id,
		})

	var convoy_snapshots: Array = []
	for convoy in supply_convoys.values():
		if convoy.army_id != army_id and not _is_position_visible_to_army(convoy.position, army_id):
			continue
		if not _rect_intersects_circle(snapshot_interest.get("units_rect", map_rect), convoy.position, 28.0):
			continue
		convoy_snapshots.append({
			"id": String(convoy.id),
			"position": convoy.position,
			"army_id": String(convoy.army_id),
			"is_friendly": convoy.army_id == army_id,
			"supply_load": convoy.supply_load_amount,
			"ammo_load": convoy.ammo_load_amount,
		})

	var own_supply_hq: HQ = hqs.get(own_army.baggage_hq_id)
	var enemy_army_id: StringName = _get_enemy_army_id(army_id)
	var enemy_army: Army = armies.get(enemy_army_id)
	var selection_outline_snapshots: Array = _build_selection_outline_snapshots(army_id, snapshot_interest)
	var selection_stamp: float = _build_selection_snapshot_stamp(snapshot_interest)
	var snapshot: Dictionary = {
		"time_seconds": time_seconds,
		"player_army_id": String(army_id),
		"channels": {
			"static_world": {
				"stamp": 1.0,
				"map_rect": map_rect,
				"terrain_regions": _get_cached_terrain_snapshots(),
			},
			"units": {
				"stamp": time_seconds,
				"zoom": float(snapshot_interest.get("zoom", 1.0)),
				"visible_rect": snapshot_interest.get("visible_rect", map_rect),
				"battalions": regiment_snapshots,
				"hqs": hq_snapshots,
				"messengers": messenger_snapshots,
				"convoys": convoy_snapshots,
				"last_seen_markers": marker_snapshots,
				"strategic_points": strategic_snapshots,
			},
			"fog": {
				"stamp": 0.0,
				"map_rect": map_rect,
				"vision_sources": [],
				"fog_cell_size": 0.0,
				"visibility_cells": [],
				"fog_stamp": 0.0,
			},
			"selection": {
				"stamp": selection_stamp,
				"vision_outlines": selection_outline_snapshots,
			},
			"ui": {
				"stamp": time_seconds,
				"recent_events": recent_events.duplicate(),
				"performance": {
					"snapshot_build_ms": _last_snapshot_build_ms,
					"visibility_ms": _last_visibility_update_ms,
					"logistics_ms": _last_logistics_tick_ms,
					"ai_ms": _last_ai_tick_ms,
					"behavior_ms": _last_behavior_tick_ms,
					"combat_ms": _last_combat_tick_ms,
					"combat_frame_ms": combat_system.last_frame_build_ms if combat_system != null else 0.0,
					"combat_contacts": combat_system.last_contact_edges if combat_system != null else 0,
					"combat_firers": combat_system.last_small_arms_firers if combat_system != null else 0,
					"combat_shots": combat_system.last_small_arms_samples if combat_system != null else 0,
					"combat_hits": combat_system.last_small_arms_hits if combat_system != null else 0,
					"combat_fire_casualties": combat_system.last_small_arms_casualties if combat_system != null else 0,
					"combat_artillery_firers": combat_system.last_artillery_firers if combat_system != null else 0,
					"combat_artillery_hits": combat_system.last_artillery_hits if combat_system != null else 0,
					"combat_artillery_casualties": combat_system.last_artillery_casualties if combat_system != null else 0,
					"combat_charge_impacts": combat_system.last_charge_impacts if combat_system != null else 0,
					"combat_charge_casualties": combat_system.last_charge_casualties if combat_system != null else 0,
					"combat_melee_edges": combat_system.last_melee_edges if combat_system != null else 0,
					"combat_melee_casualties": combat_system.last_melee_casualties if combat_system != null else 0,
					"combat_active_regiments": combat_system.last_active_regiments if combat_system != null else 0,
					"combat_active_battalions": combat_system.last_active_regiments if combat_system != null else 0,
					"advance_ms": _last_advance_tick_ms,
					"regiments": friendly_regiment_count,
					"battalions": friendly_regiment_count,
					"visible_regiments": regiment_snapshots.size(),
					"visible_battalions": regiment_snapshots.size(),
					"convoys": convoy_snapshots.size(),
					"fog_cells": 0,
				},
				"top_bar": {
					"army_name": own_army.display_name,
					"baggage_supply": own_supply_hq.supply_stock if own_supply_hq != null else 0.0,
					"baggage_ammo": own_supply_hq.ammo_stock if own_supply_hq != null else 0.0,
					"own_victory_points": own_army.victory_points,
					"enemy_victory_points": enemy_army.victory_points if enemy_army != null else 0.0,
					"active_convoys": _count_active_convoys_for_army(army_id),
					"active_regiments": friendly_regiment_count,
					"active_battalions": friendly_regiment_count,
				},
			},
			"orders_preview": {},
		},
	}
	_last_snapshot_build_ms = float(Time.get_ticks_usec() - snapshot_start_us) / 1000.0
	snapshot["channels"]["ui"]["performance"]["snapshot_build_ms"] = _last_snapshot_build_ms
	return snapshot


func _resolve_snapshot_interest(view_interest: Dictionary) -> Dictionary:
	var visible_rect: Rect2 = view_interest.get("visible_rect", map_rect)
	if visible_rect.size.x <= 1.0 or visible_rect.size.y <= 1.0:
		visible_rect = map_rect
	var zoom: float = float(view_interest.get("zoom", 1.0))
	var selected_regiment_id: StringName = StringName(view_interest.get("selected_regiment_id", ""))
	var selected_brigade_id: StringName = StringName(view_interest.get("selected_brigade_id", ""))
	var margin: float = clamp(max(720.0, max(visible_rect.size.x, visible_rect.size.y) * 0.50), 720.0, 2600.0)
	return {
		"zoom": zoom,
		"visible_rect": visible_rect,
		"units_rect": visible_rect.grow(margin),
		"selected_regiment_id": selected_regiment_id,
		"selected_brigade_id": selected_brigade_id,
	}


func _should_include_friendly_regiment_in_snapshot(regiment: Battalion, snapshot_interest: Dictionary) -> bool:
	var selected_regiment_id: StringName = snapshot_interest.get("selected_regiment_id", &"")
	if regiment.id == selected_regiment_id:
		return true
	var selected_brigade_id: StringName = snapshot_interest.get("selected_brigade_id", &"")
	if selected_brigade_id != &"" and regiment.brigade_id == selected_brigade_id:
		return true
	return _rect_intersects_circle(
		snapshot_interest.get("units_rect", map_rect),
		regiment.position,
		_get_snapshot_interest_radius_for_regiment(regiment)
	)


func _should_include_enemy_regiment_in_snapshot(regiment: Battalion, snapshot_interest: Dictionary) -> bool:
	return _rect_intersects_circle(
		snapshot_interest.get("units_rect", map_rect),
		regiment.position,
		_get_snapshot_interest_radius_for_regiment(regiment)
	)


func _should_include_hq_in_snapshot(
		hq: HQ,
		brigade_id: StringName,
		army_id: StringName,
		snapshot_interest: Dictionary
) -> bool:
	var selected_brigade_id: StringName = snapshot_interest.get("selected_brigade_id", &"")
	if hq.army_id == army_id and selected_brigade_id != &"" and brigade_id == selected_brigade_id:
		return true
	return _rect_intersects_circle(snapshot_interest.get("units_rect", map_rect), hq.position, 40.0)


func _build_selection_outline_snapshots(army_id: StringName, snapshot_interest: Dictionary) -> Array:
	var selected_brigade_id: StringName = snapshot_interest.get("selected_brigade_id", &"")
	if selected_brigade_id == &"":
		return []
	var selected_regiment_id: StringName = snapshot_interest.get("selected_regiment_id", &"")
	var outlines: Array = []
	for regiment_value in regiments.values():
		var regiment: Battalion = regiment_value
		if regiment.is_destroyed or regiment.army_id != army_id or regiment.brigade_id != selected_brigade_id:
			continue
		outlines.append({
			"regiment_id": String(regiment.id),
			"is_selected": regiment.id == selected_regiment_id,
			"points": _get_cached_regiment_vision_outline(regiment),
		})
	return outlines


func _build_selection_snapshot_stamp(snapshot_interest: Dictionary) -> float:
	var selected_brigade_id: String = String(snapshot_interest.get("selected_brigade_id", ""))
	if selected_brigade_id.is_empty():
		return 0.0
	var outline_window: int = int(floor(time_seconds / max(vision_outline_cache_interval_seconds, 0.05)))
	return float(selected_brigade_id.hash()) + float(outline_window) * 1000000.0


func _get_snapshot_interest_radius_for_regiment(regiment: Battalion) -> float:
	return max(84.0, max(regiment.formation.frontage, regiment.formation.depth) * 0.85 + 96.0)


func _get_snapshot_payload_lod(
		regiment: Battalion,
		army_id: StringName,
		snapshot_interest: Dictionary,
		is_friendly: bool
) -> int:
	var selected_regiment_id: StringName = snapshot_interest.get("selected_regiment_id", &"")
	if regiment.id == selected_regiment_id:
		return SNAPSHOT_PAYLOAD_FULL
	var selected_brigade_id: StringName = snapshot_interest.get("selected_brigade_id", &"")
	if is_friendly and selected_brigade_id != &"" and regiment.brigade_id == selected_brigade_id:
		return SNAPSHOT_PAYLOAD_FULL
	var zoom: float = float(snapshot_interest.get("zoom", 1.0))
	if zoom >= SNAPSHOT_FULL_DETAIL_ZOOM_THRESHOLD:
		return SNAPSHOT_PAYLOAD_COARSE
	var detail_rect: Rect2 = snapshot_interest.get("visible_rect", map_rect).grow(260.0)
	if _rect_intersects_circle(detail_rect, regiment.position, _get_snapshot_interest_radius_for_regiment(regiment)):
		return SNAPSHOT_PAYLOAD_FULL
	return SNAPSHOT_PAYLOAD_COARSE


func _rect_intersects_circle(rect: Rect2, center: Vector2, radius: float) -> bool:
	var nearest_x: float = clamp(center.x, rect.position.x, rect.end.x)
	var nearest_y: float = clamp(center.y, rect.position.y, rect.end.y)
	var nearest_position: Vector2 = Vector2(nearest_x, nearest_y)
	return nearest_position.distance_squared_to(center) <= radius * radius


func _get_cached_terrain_snapshots() -> Array:
	if not _cached_terrain_snapshots.is_empty():
		return _cached_terrain_snapshots
	for region in terrain_regions:
		_cached_terrain_snapshots.append({
			"id": String(region.id),
			"display_name": region.display_name,
			"polygon": region.polygon,
			"terrain_type": region.terrain_type,
			"average_height": region.average_height,
			"has_road": region.has_road,
		})
	return _cached_terrain_snapshots


func _build_vision_sources_for_army(army_id: StringName) -> Array:
	var vision_sources: Array = []
	for regiment in regiments.values():
		if regiment.army_id != army_id or regiment.is_destroyed:
			continue
		vision_sources.append({
			"position": regiment.position,
			"radius": regiment.get_vision_range(),
		})
	for hq in hqs.values():
		if hq.army_id != army_id or not hq.is_operational():
			continue
		vision_sources.append({
			"position": hq.position,
			"radius": hq.command_radius * 1.2,
		})
	return vision_sources


func _get_or_build_fog_payload(army_id: StringName) -> Dictionary:
	var cached_payload: Dictionary = fog_cache_by_army.get(army_id, {})
	if not cached_payload.is_empty():
		var last_time: float = float(cached_payload.get("time_seconds", -INF))
		if time_seconds - last_time < fog_cache_interval_seconds:
			return cached_payload
	var fog_cell_size: float = _get_fog_cell_size()
	var visibility_cells: Array = []
	var start_x: int = int(map_rect.position.x)
	var end_x: int = int(map_rect.end.x)
	var start_y: int = int(map_rect.position.y)
	var end_y: int = int(map_rect.end.y)
	var fog_step: int = int(fog_cell_size)
	for x in range(start_x, end_x, fog_step):
		for y in range(start_y, end_y, fog_step):
			var center: Vector2 = Vector2(x + fog_cell_size * 0.5, y + fog_cell_size * 0.5)
			visibility_cells.append({
				"position": center,
				"visibility": _get_visibility_strength_for_army(center, army_id),
			})
	var payload: Dictionary = {
		"time_seconds": time_seconds,
		"cell_size": fog_cell_size,
		"cells": visibility_cells,
	}
	fog_cache_by_army[army_id] = payload
	return payload


func _get_fog_cell_size() -> float:
	var longest_edge: float = max(map_rect.size.x, map_rect.size.y)
	if longest_edge >= 2600.0:
		return 96.0
	if longest_edge >= 2000.0:
		return 72.0
	return 48.0


func _build_regiment_snapshot(regiment: Battalion, is_friendly: bool, detail_level: int, payload_lod: int = SNAPSHOT_PAYLOAD_FULL) -> Dictionary:
	var label: String = regiment.display_name if is_friendly else "Enemy %s" % SimTypes.unit_category_name(regiment.category)
	var approximate_strength: float = snapped(float(regiment.get_total_strength()) / 50.0, 1.0) * 50.0
	var status_text: String = regiment.state_label if is_friendly or detail_level >= SimTypes.IntelDetail.CLOSE else "Activity unknown"
	var order_label: String = SimTypes.order_type_name(regiment.current_order_type) if is_friendly or detail_level >= SimTypes.IntelDetail.CLOSE else "Unknown order"
	var include_company_payload: bool = payload_lod == SNAPSHOT_PAYLOAD_FULL
	var stand_visual_entries: Array = regiment.build_company_visual_layout() if include_company_payload else []
	var stand_snapshots: Array = _build_stand_snapshots(regiment, is_friendly, detail_level, stand_visual_entries) if include_company_payload else []
	if not is_friendly and detail_level >= SimTypes.IntelDetail.DETAILED:
		label = "%s (~%d)" % [regiment.display_name, int(approximate_strength)]
	return {
		"id": String(regiment.id),
		"battalion_id": String(regiment.id),
		"display_name": label,
		"true_name": regiment.display_name,
		"position": regiment.position,
		"front_direction": regiment.front_direction,
		"category": regiment.category,
		"army_id": String(regiment.army_id),
		"brigade_id": String(regiment.brigade_id),
		"is_friendly": is_friendly,
		"detail_level": detail_level,
		"strength": regiment.get_total_strength() if is_friendly or detail_level >= SimTypes.IntelDetail.DETAILED else -1,
		"strength_ratio": regiment.get_strength_ratio(),
		"subunit_types": regiment.get_stand_weapon_types(),
		"stand_types": regiment.get_stand_type_ids(),
		"editor_company_types": regiment.get_editor_company_type_ids(),
		"company_types": regiment.get_editor_company_type_ids(),
		"stand_count": regiment.get_stand_count(),
		"editor_company_count": regiment.get_editor_company_count(),
		"company_count": regiment.get_editor_company_count(),
		"max_editor_company_capacity": regiment.get_max_company_capacity(),
		"max_company_capacity": regiment.get_max_company_capacity(),
		"commander_name": regiment.commander_name,
		"commander_profile_id": String(regiment.commander_profile_id),
		"commander_profile_name": regiment.commander_profile_name,
		"banner_profile_id": String(regiment.banner_profile_id),
		"banner_profile_name": regiment.banner_profile_name,
		"payload_lod": payload_lod,
		"stands": stand_snapshots,
		"stand_visual_entries": stand_visual_entries,
		"subunit_polygons": [] if include_company_payload else _build_snapshot_subunit_polygons(regiment),
		"formation_type": regiment.formation.formation_type,
		"formation_state": regiment.formation_state,
		"formation_frontage": regiment.formation.frontage,
		"formation_depth": regiment.formation.depth,
		"fire_behavior": regiment.fire_behavior,
		"combat_posture": regiment.combat_posture,
		"combat_order_mode": regiment.combat_order_mode,
		"morale": regiment.morale if is_friendly or detail_level >= SimTypes.IntelDetail.CLOSE else -1.0,
		"cohesion": regiment.cohesion if is_friendly or detail_level >= SimTypes.IntelDetail.CLOSE else -1.0,
		"suppression": regiment.suppression if is_friendly or detail_level >= SimTypes.IntelDetail.CLOSE else -1.0,
		"ammo_ratio": regiment.ammo_ratio if is_friendly or detail_level >= SimTypes.IntelDetail.CLOSE else -1.0,
		"debug_forced_formation_state": regiment.debug_forced_formation_state,
		"debug_forced_fire_behavior": regiment.debug_forced_fire_behavior,
		"brigade_role": regiment.brigade_role,
		"visual_test_fire": regiment.has_debug_test_fire(time_seconds),
		"status_text": status_text,
		"order_label": order_label,
		"regimental_elements": [regiment.get_banner_snapshot()],
		"policies": regiment.order_policies if is_friendly else {},
		"vision_range": regiment.get_vision_range() if is_friendly else 0.0,
	}


func _build_snapshot_subunit_polygons(regiment: Battalion) -> Array:
	var polygons: Array = []
	var width_scale: float = 0.88
	var depth_scale: float = 0.88
	if regiment.category == SimTypes.UnitCategory.CAVALRY:
		width_scale = 0.94
		depth_scale = 0.82
	elif regiment.category == SimTypes.UnitCategory.ARTILLERY:
		width_scale = 0.72
		depth_scale = 0.94
	for stand_value in regiment.stands:
		var stand: CombatStand = stand_value
		if stand.soldiers <= 0:
			continue
		var center: Vector2 = regiment.get_stand_world_position(stand)
		var front: Vector2 = regiment.get_stand_world_front_direction(stand)
		var body_depth: float = max(6.0, stand.depth_density * 8.0)
		var block_width: float = max(14.0, stand.frontage_width * width_scale)
		var block_depth: float = max(14.0, body_depth * depth_scale)
		polygons.append(_build_snapshot_oriented_box(center, front, block_width, block_depth))
	return polygons


func _build_snapshot_oriented_box(center: Vector2, front_direction: Vector2, width: float, depth: float) -> PackedVector2Array:
	var front: Vector2 = front_direction.normalized() if front_direction.length_squared() > 0.001 else Vector2.RIGHT
	var right_axis: Vector2 = Vector2(-front.y, front.x).normalized()
	var half_width: float = width * 0.5
	var half_depth: float = depth * 0.5
	return PackedVector2Array([
		center - right_axis * half_width - front * half_depth,
		center + right_axis * half_width - front * half_depth,
		center + right_axis * half_width + front * half_depth,
		center - right_axis * half_width + front * half_depth,
	])


func _build_stand_snapshots(regiment: Battalion, is_friendly: bool, detail_level: int, stand_visual_entries: Array = []) -> Array:
	var stand_snapshots: Array = []
	var visual_entry_by_stand_id: Dictionary = {}
	for entry_value in stand_visual_entries:
		var entry: Dictionary = entry_value
		visual_entry_by_stand_id[StringName(entry.get("company_id", ""))] = entry
	for stand_value in regiment.stands:
		var stand: CombatStand = stand_value
		var display_position: Vector2 = regiment.get_stand_world_position(stand)
		var slot_role: StringName = stand.current_visual_role
		if slot_role == &"":
			slot_role = regiment.get_stand_slot_role(stand.id)
		var visual_entry: Dictionary = visual_entry_by_stand_id.get(stand.id, {})
		stand_snapshots.append({
			"id": String(stand.id),
			"stand_id": String(stand.id),
			"display_name": stand.display_name if is_friendly or detail_level >= SimTypes.IntelDetail.CLOSE else SimTypes.company_type_name(stand.company_type),
			"company_type": stand.company_type,
			"stand_type": stand.company_type,
			"combat_role": stand.combat_role,
			"weapon_type": stand.weapon_type,
			"soldiers": stand.soldiers if is_friendly or detail_level >= SimTypes.IntelDetail.CLOSE else -1,
			"morale": stand.morale if is_friendly or detail_level >= SimTypes.IntelDetail.CLOSE else -1.0,
			"cohesion": stand.cohesion if is_friendly or detail_level >= SimTypes.IntelDetail.CLOSE else -1.0,
			"ammo": stand.ammo if is_friendly or detail_level >= SimTypes.IntelDetail.CLOSE else -1.0,
			"reload_state": stand.reload_state if is_friendly or detail_level >= SimTypes.IntelDetail.CLOSE else -1,
			"reload_progress": stand.reload_progress if is_friendly or detail_level >= SimTypes.IntelDetail.CLOSE else -1.0,
			"reload_ratio": stand.get_reload_ratio() if is_friendly or detail_level >= SimTypes.IntelDetail.CLOSE else -1.0,
			"suppression": stand.suppression if is_friendly or detail_level >= SimTypes.IntelDetail.CLOSE else -1.0,
			"is_routed": stand.is_routed if is_friendly or detail_level >= SimTypes.IntelDetail.CLOSE else false,
			"can_fire_small_arms": stand.can_fire_small_arms() if is_friendly or detail_level >= SimTypes.IntelDetail.CLOSE else false,
			"position": display_position,
			"front_direction": stand.front_direction,
			"slot_role": String(slot_role),
			"editor_company_tag": String(stand.editor_company_tag),
			"editor_company_name": stand.editor_company_name,
			"visual_elements": visual_entry.get("elements", []).duplicate(true),
			"fire_behavior": regiment.fire_behavior,
			"visual_fire_active": stand.is_visual_fire_active(time_seconds),
		})
	return stand_snapshots


func _build_company_snapshots(regiment: Battalion, is_friendly: bool, detail_level: int) -> Array:
	return _build_stand_snapshots(regiment, is_friendly, detail_level)


func _get_visual_elements_center(visual_elements: Array) -> Vector2:
	if visual_elements.is_empty():
		return Vector2.ZERO
	var total: Vector2 = Vector2.ZERO
	for element_value in visual_elements:
		var element: Dictionary = element_value
		total += element.get("position", Vector2.ZERO)
	return total / float(visual_elements.size())


func _build_regiment_vision_outline(regiment: Battalion) -> PackedVector2Array:
	var vision_outline: PackedVector2Array = PackedVector2Array()
	var ray_count: int = 28
	var max_range: float = regiment.get_vision_range()
	for ray_index in range(ray_count):
		var angle: float = TAU * float(ray_index) / float(ray_count)
		var direction: Vector2 = Vector2.RIGHT.rotated(angle)
		var distance: float = _sample_visibility_distance(regiment.position, direction, max_range)
		vision_outline.append(regiment.position + direction * distance)
	return vision_outline


func _get_cached_regiment_vision_outline(regiment: Battalion) -> PackedVector2Array:
	var cached_entry: Dictionary = _vision_outline_cache_by_regiment.get(regiment.id, {})
	if not cached_entry.is_empty():
		var cached_time: float = float(cached_entry.get("time_seconds", -INF))
		var cached_position: Vector2 = cached_entry.get("position", regiment.position)
		var cached_range: float = float(cached_entry.get("range", -1.0))
		var cached_local_outline: PackedVector2Array = cached_entry.get("outline_local", PackedVector2Array())
		if time_seconds - cached_time < vision_outline_cache_interval_seconds \
				and absf(cached_range - regiment.get_vision_range()) <= 0.1 \
				and cached_local_outline.size() >= 3:
			var translated_outline: PackedVector2Array = PackedVector2Array()
			for local_point_value in cached_local_outline:
				var local_point: Vector2 = local_point_value
				translated_outline.append(regiment.position + local_point)
			return translated_outline
	var outline: PackedVector2Array = _build_regiment_vision_outline(regiment)
	var outline_local: PackedVector2Array = PackedVector2Array()
	for point_value in outline:
		var point: Vector2 = point_value
		outline_local.append(point - regiment.position)
	_vision_outline_cache_by_regiment[regiment.id] = {
		"time_seconds": time_seconds,
		"position": regiment.position,
		"range": regiment.get_vision_range(),
		"outline_local": outline_local,
	}
	return outline


func _sample_visibility_distance(origin: Vector2, direction: Vector2, max_range: float) -> float:
	var step_size: float = 18.0
	var best_distance: float = step_size
	var traveled: float = step_size
	while traveled <= max_range:
		var sample_position: Vector2 = origin + direction * traveled
		if not map_rect.has_point(sample_position):
			break
		var path_visibility: float = _visibility_between(origin, sample_position)
		if traveled > max_range * path_visibility:
			break
		best_distance = traveled
		traveled += step_size
	return clamp(best_distance, step_size, max_range)



func _process_player_commands() -> void:
	while not command_queue.is_empty():
		var command: Dictionary = command_queue.pop_front()
		var army_id: StringName = StringName(command.get("army_id", ""))
		var brigade_id: StringName = StringName(command.get("recipient_brigade_id", ""))
		if not armies.has(army_id) or not brigades.has(brigade_id):
			continue
		var army: Army = armies[army_id]
		var brigade: Brigade = brigades[brigade_id]
		var order: SimOrder = SimOrder.new()
		order.id = StringName("order_%d" % _next_order_index)
		_next_order_index += 1
		order.issuer_army_id = army_id
		order.recipient_brigade_id = brigade_id
		order.order_type = int(command.get("order_type", SimTypes.OrderType.MOVE))
		order.target_position = command.get("target_position", brigade_position(brigade))
		order.line_start = command.get("line_start", Vector2.ZERO)
		order.line_end = command.get("line_end", Vector2.ZERO)
		order.path_points = command.get("path_points", []).duplicate(true)
		order.policies = command.get("policies", {}).duplicate(true)
		order.issued_at = time_seconds

		var commander: Commander = commanders.get(army.commander_id)
		var commander_hq: HQ = hqs.get(commander.hq_id) if commander != null else null
		var brigade_hq: HQ = hqs.get(brigade.hq_id)
		if commander_hq == null or brigade_hq == null:
			continue
		order.issuer_hq_id = commander_hq.id
		orders[order.id] = order
		# Orders travel instantly only when the commander can plausibly
		# shout them to the recipient HQ. Otherwise a messenger is spawned.
		if commander_hq.position.distance_to(brigade_hq.position) <= commander.command_voice_radius:
			order.delivery_method = SimTypes.DeliveryMethod.VOICE
			order.status = SimTypes.OrderStatus.DELIVERED
			order.delivered_at = time_seconds
			_apply_delivered_order(order)
			_push_event("%s reached %s by voice." % [SimTypes.order_type_name(order.order_type), brigade.display_name])
		else:
			order.delivery_method = SimTypes.DeliveryMethod.MESSENGER
			order.status = SimTypes.OrderStatus.IN_TRANSIT
			var messenger: Messenger = Messenger.new(
				StringName("messenger_%d" % _next_messenger_index),
				army_id,
				commander_hq.position
			)
			_next_messenger_index += 1
			messenger.order_id = order.id
			messenger.source_hq_id = commander_hq.id
			messenger.recipient_hq_id = brigade_hq.id
			messengers[messenger.id] = messenger
			_push_event("Messenger dispatched from %s to %s." % [commander_hq.display_name, brigade.display_name])


func _apply_delivered_order(order: SimOrder) -> void:
	var brigade: Brigade = brigades.get(order.recipient_brigade_id)
	if brigade == null:
		return
	brigade.current_order_id = order.id
	brigade.current_order_type = order.order_type
	brigade.order_policies = order.policies.duplicate(true)
	brigade.target_position = order.target_position
	brigade.order_line_start = order.line_start
	brigade.order_line_end = order.line_end
	brigade.order_path_points = order.path_points.duplicate(true)
	for regiment_id in brigade.regiment_ids:
		var regiment: Battalion = regiments.get(regiment_id)
		if regiment == null:
			continue
		regiment.current_order_id = order.id
		regiment.current_order_type = order.order_type
		regiment.current_target_position = order.target_position
		regiment.order_policies = order.policies.duplicate(true)
		regiment.state_label = SimTypes.order_type_name(order.order_type)


func _tick_messengers(delta: float) -> void:
	var delivered_ids: Array = []
	var lost_ids: Array = []
	for messenger in messengers.values():
		var target_hq: HQ = hqs.get(messenger.recipient_hq_id)
		if target_hq == null:
			lost_ids.append(messenger.id)
			continue
		messenger.move_toward(target_hq.position, messenger.speed, delta)
		if _messenger_intercepted(messenger):
			var order: SimOrder = orders.get(messenger.order_id)
			if order != null:
				order.status = SimTypes.OrderStatus.FAILED
				order.failure_reason = "Messenger intercepted"
			lost_ids.append(messenger.id)
			_push_event("A messenger carrying %s was intercepted." % [order.get_summary() if order != null else "orders"])
			continue
		if messenger.position.distance_to(target_hq.position) <= messenger.delivery_radius:
			var delivered_order: SimOrder = orders.get(messenger.order_id)
			if delivered_order != null:
				delivered_order.status = SimTypes.OrderStatus.DELIVERED
				delivered_order.delivered_at = time_seconds
				_apply_delivered_order(delivered_order)
				var brigade: Brigade = brigades.get(delivered_order.recipient_brigade_id)
				_push_event("%s delivered to %s." % [
					SimTypes.order_type_name(delivered_order.order_type),
					brigade.display_name if brigade != null else "brigade",
				])
			delivered_ids.append(messenger.id)
	for messenger_id in delivered_ids:
		messengers.erase(messenger_id)
	for messenger_id in lost_ids:
		messengers.erase(messenger_id)


func _messenger_intercepted(messenger: Messenger) -> bool:
	for regiment in regiments.values():
		if regiment.army_id == messenger.army_id:
			continue
		var interception_radius: float = 42.0
		if regiment.category == SimTypes.UnitCategory.CAVALRY:
			interception_radius = 62.0
		if regiment.position.distance_to(messenger.position) <= interception_radius:
			return true
	return false


func _tick_supply_convoys(delta: float) -> void:
	# Prototype logistics: convoys move directly, but the surrounding
	# architecture already isolates them as interceptable entities.
	_maybe_spawn_convoys()
	var delivered_ids: Array = []
	var lost_ids: Array = []
	for convoy in supply_convoys.values():
		var target_hq: HQ = hqs.get(convoy.target_hq_id)
		if target_hq == null:
			lost_ids.append(convoy.id)
			continue
		var speed: float = convoy.speed
		var terrain: TerrainCell = get_terrain_at(convoy.position)
		if terrain != null and terrain.has_road:
			speed *= 1.3
		convoy.move_toward(target_hq.position, speed, delta)
		for regiment in regiments.values():
			if regiment.army_id == convoy.army_id:
				continue
			if regiment.position.distance_to(convoy.position) <= 55.0:
				convoy.is_destroyed_in_transit = true
				lost_ids.append(convoy.id)
				_push_event("%s was intercepted near %s." % [convoy.display_name, target_hq.display_name])
				break
		if lost_ids.has(convoy.id):
			continue
		if convoy.position.distance_to(target_hq.position) <= 22.0:
			_deliver_convoy(convoy)
			delivered_ids.append(convoy.id)
	for convoy_id in delivered_ids:
		supply_convoys.erase(convoy_id)
	for convoy_id in lost_ids:
		supply_convoys.erase(convoy_id)


func _maybe_spawn_convoys() -> void:
	return


func _deliver_convoy(convoy: SupplyConvoy) -> void:
	var target_hq: HQ = hqs.get(convoy.target_hq_id)
	if target_hq == null:
		return
	target_hq.supply_stock = min(1.0, target_hq.supply_stock + convoy.supply_load_amount)
	target_hq.ammo_stock = min(1.0, target_hq.ammo_stock + convoy.ammo_load_amount)
	_push_event("Supply convoy reached %s." % target_hq.display_name)


func _tick_brigade_hqs(delta: float) -> void:
	for brigade in brigades.values():
		var brigade_hq: HQ = hqs.get(brigade.hq_id)
		if brigade_hq == null:
			continue
		var anchor_position: Vector2 = _get_brigade_anchor_position(brigade)
		var desired_offset: Vector2 = _get_brigade_hq_offset(brigade)
		var target_position: Vector2 = anchor_position + desired_offset
		brigade_hq.move_toward(target_position, brigade_hq.mobility, delta)




func _tick_strategic_points(delta: float) -> void:
	for point in strategic_points.values():
		var presence: Dictionary = {}
		for regiment in regiments.values():
			if regiment.is_destroyed:
				continue
			if regiment.position.distance_to(point.position) <= point.radius:
				presence[regiment.army_id] = int(presence.get(regiment.army_id, 0)) + 1
		if presence.size() == 1:
			var army_id: StringName = presence.keys()[0]
			point.capture_progress = clamp(point.capture_progress + delta * 0.18, 0.0, 1.0)
			if point.capture_progress >= 1.0:
				point.controlling_army_id = army_id
		elif presence.size() > 1:
			point.capture_progress = max(0.0, point.capture_progress - delta * 0.2)

		if point.controlling_army_id != &"" and armies.has(point.controlling_army_id):
			var owner: Army = armies[point.controlling_army_id]
			owner.victory_points += point.victory_rate_per_second * delta


func _tick_last_seen_markers(delta: float) -> void:
	for army_id in last_seen_markers_by_army.keys():
		var to_remove: Array = []
		var markers_for_army: Dictionary = last_seen_markers_by_army[army_id]
		for marker in markers_for_army.values():
			marker.remaining_time -= delta
			if marker.remaining_time <= 0.0:
				to_remove.append(marker.enemy_regiment_id)
		for marker_id in to_remove:
			markers_for_army.erase(marker_id)


func _update_visibility() -> void:
	for army_id in armies.keys():
		if not visible_enemy_ids_by_army.has(army_id):
			visible_enemy_ids_by_army[army_id] = {}
		if not last_seen_markers_by_army.has(army_id):
			last_seen_markers_by_army[army_id] = {}

		var previous_visible: Dictionary = visible_enemy_ids_by_army[army_id]
		var new_visible: Dictionary = {}
		var observers: Array = _get_observers_for_army(army_id)
		var observer_descriptors: Array = _build_visibility_observer_descriptors(observers)
		var enemy_regiments: Array = _get_enemy_regiments_for_army(army_id)
		for descriptor_value in observer_descriptors:
			var descriptor: Dictionary = descriptor_value
			for enemy_value in enemy_regiments:
				var regiment: Battalion = enemy_value
				var detail: int = _get_detail_level_from_descriptor(descriptor, regiment)
				if detail > SimTypes.IntelDetail.NONE:
					new_visible[regiment.id] = max(int(new_visible.get(regiment.id, SimTypes.IntelDetail.NONE)), detail)
		visible_enemy_ids_by_army[army_id] = new_visible

		var markers_for_army: Dictionary = last_seen_markers_by_army[army_id]
		for enemy_id in previous_visible.keys():
			if new_visible.has(enemy_id):
				markers_for_army.erase(enemy_id)
				continue
			var enemy_regiment: Battalion = regiments.get(enemy_id)
			if enemy_regiment == null or enemy_regiment.is_destroyed:
				continue
			var marker: LastSeenMarker = LastSeenMarker.new()
			marker.enemy_regiment_id = enemy_regiment.id
			marker.observer_army_id = army_id
			marker.position = enemy_regiment.position
			marker.detail_level = int(previous_visible[enemy_id])
			marker.remaining_time = 16.0
			marker.label = "Last seen %s" % SimTypes.unit_category_name(enemy_regiment.category)
			markers_for_army[enemy_id] = marker
		for enemy_id in new_visible.keys():
			markers_for_army.erase(enemy_id)


func _get_observers_for_army(army_id: StringName) -> Array:
	var observers: Array = []
	for regiment in regiments.values():
		if regiment.army_id == army_id and not regiment.is_destroyed:
			observers.append(regiment)
	for hq in hqs.values():
		if hq.army_id == army_id and hq.is_operational():
			observers.append(hq)
	return observers


func _get_enemy_regiments_for_army(army_id: StringName) -> Array:
	var enemies: Array = []
	for regiment in regiments.values():
		if regiment.army_id == army_id or regiment.is_destroyed:
			continue
		enemies.append(regiment)
	return enemies


func _build_visibility_observer_descriptors(observers: Array) -> Array:
	var descriptors: Array = []
	for observer_value in observers:
		var observer: Variant = observer_value
		var observer_position: Vector2 = observer.position
		var base_range: float = 150.0
		var observer_is_regiment: bool = observer is Battalion
		if observer_is_regiment:
			base_range = observer.get_vision_range()
		elif observer is HQ:
			base_range = observer.command_radius * 1.2
		var observer_terrain: TerrainCell = get_terrain_at(observer_position)
		var terrain_visibility: float = 1.0
		var height_bonus: float = 1.0
		if observer_terrain != null:
			terrain_visibility = clamp(observer_terrain.visibility_multiplier, 0.65, 1.15)
			height_bonus = 1.0 + observer_terrain.average_height * 0.25
		var adjusted_range: float = base_range * terrain_visibility * height_bonus
		descriptors.append({
			"observer": observer,
			"position": observer_position,
			"range": adjusted_range,
			"broad_phase_range": adjusted_range * 1.1,
			"is_regiment": observer_is_regiment,
		})
	return descriptors


func _get_detail_level_from_descriptor(descriptor: Dictionary, target: Battalion) -> int:
	var observer: Variant = descriptor.get("observer")
	var observer_position: Vector2 = descriptor.get("position", Vector2.ZERO)
	var adjusted_range: float = float(descriptor.get("range", 150.0))
	var broad_phase_range: float = float(descriptor.get("broad_phase_range", adjusted_range))
	var distance: float = observer_position.distance_to(target.position)
	if distance > broad_phase_range:
		return SimTypes.IntelDetail.NONE
	if bool(descriptor.get("is_regiment", false)):
		var observer_regiment: Battalion = observer
		var close_contact_detail: int = _get_forced_close_contact_detail(observer_regiment, target)
		if close_contact_detail > SimTypes.IntelDetail.NONE:
			return close_contact_detail
	var target_terrain: TerrainCell = get_terrain_at(target.position)
	var visibility_modifier: float = target_terrain.visibility_multiplier if target_terrain != null else 1.0
	var cheap_effective_range: float = adjusted_range * visibility_modifier
	if distance > cheap_effective_range * 1.08:
		return SimTypes.IntelDetail.NONE
	if bool(descriptor.get("is_regiment", false)):
		var visibility_observer: Battalion = observer
		visibility_modifier *= sampled_visibility_between_battalions(visibility_observer, target, 5)
	else:
		visibility_modifier *= _visibility_between(observer_position, target.position)
	var effective_range: float = adjusted_range * visibility_modifier
	if distance > effective_range:
		return SimTypes.IntelDetail.NONE
	if distance <= effective_range * 0.38:
		return SimTypes.IntelDetail.CLOSE
	if distance <= effective_range * 0.7:
		return SimTypes.IntelDetail.DETAILED
	return SimTypes.IntelDetail.BROAD


func _get_detail_level(observer: Variant, target: Battalion) -> int:
	var observer_position: Vector2 = observer.position
	var observer_range: float = observer.get_vision_range() if observer is Battalion else observer.command_radius * 1.2
	var observer_terrain: TerrainCell = get_terrain_at(observer_position)
	var terrain_visibility: float = clamp(observer_terrain.visibility_multiplier, 0.65, 1.15) if observer_terrain != null else 1.0
	var height_bonus: float = 1.0 + observer_terrain.average_height * 0.25 if observer_terrain != null else 1.0
	return _get_detail_level_from_descriptor({
		"observer": observer,
		"position": observer_position,
		"range": observer_range * terrain_visibility * height_bonus,
		"broad_phase_range": observer_range * terrain_visibility * height_bonus * 1.1,
		"is_regiment": observer is Battalion,
	}, target)


func _get_forced_close_contact_detail(observer: Battalion, target: Battalion) -> int:
	if observer.army_id == target.army_id or observer.is_destroyed or target.is_destroyed:
		return SimTypes.IntelDetail.NONE
	var distance: float = observer.position.distance_to(target.position)
	if distance <= 56.0:
		return SimTypes.IntelDetail.BROAD
	return SimTypes.IntelDetail.NONE


func _update_army_summaries() -> void:
	return


func _trim_recent_events() -> void:
	while recent_events.size() > 10:
		recent_events.pop_front()


func _push_event(text: String) -> void:
	recent_events.append("[%05.1f] %s" % [time_seconds, text])


func get_terrain_at(world_position: Vector2) -> TerrainCell:
	if terrain_grid != null:
		return terrain_grid.get_cell_at(world_position)
	var fallback: TerrainCell = TerrainCell.new()
	for region_index in range(terrain_regions.size() - 1, -1, -1):
		var region: TerrainRegion = terrain_regions[region_index]
		if region.contains(world_position):
			fallback.copy_from_region(region)
			return fallback
	return fallback


func _find_nearest_enemy(regiment: Battalion) -> Battalion:
	var best_enemy: Battalion = null
	var best_distance: float = INF
	for candidate in regiments.values():
		if candidate.army_id == regiment.army_id or candidate.is_destroyed:
			continue
		var distance: float = regiment.position.distance_to(candidate.position)
		if distance < best_distance:
			best_distance = distance
			best_enemy = candidate
	return best_enemy


func _count_enemy_regiments_near(center: Vector2, army_id: StringName, radius: float) -> int:
	var result: int = 0
	for regiment in regiments.values():
		if regiment.army_id == army_id or regiment.is_destroyed:
			continue
		if regiment.position.distance_to(center) <= radius:
			result += 1
	return result


func _count_friendly_regiments_near(center: Vector2, army_id: StringName, radius: float) -> int:
	var result: int = 0
	for regiment in regiments.values():
		if regiment.army_id != army_id or regiment.is_destroyed:
			continue
		if regiment.position.distance_to(center) <= radius:
			result += 1
	return result


func _get_army_fallback_position(army_id: StringName) -> Vector2:
	var army: Army = armies.get(army_id)
	if army == null:
		return Vector2.ZERO
	var baggage_hq: HQ = hqs.get(army.baggage_hq_id)
	if baggage_hq != null:
		return baggage_hq.position
	return Vector2.ZERO


func brigade_position(brigade: Brigade) -> Vector2:
	var brigade_hq: HQ = hqs.get(brigade.hq_id)
	return brigade_hq.position if brigade_hq != null else Vector2.ZERO


func _brigade_has_active_convoy(brigade_id: StringName) -> bool:
	for convoy in supply_convoys.values():
		if convoy.recipient_brigade_id == brigade_id:
			return true
	return false


func _count_active_convoys_for_brigade(brigade_id: StringName) -> int:
	var count: int = 0
	for convoy in supply_convoys.values():
		if convoy.recipient_brigade_id == brigade_id:
			count += 1
	return count


func _count_active_convoys_for_army(army_id: StringName) -> int:
	var count: int = 0
	for convoy in supply_convoys.values():
		if convoy.army_id == army_id:
			count += 1
	return count


func _build_default_company_spec(regiment: Battalion, company_type: int) -> Dictionary:
	match regiment.category:
		SimTypes.UnitCategory.CAVALRY:
			if company_type != SimTypes.CompanyType.CAVALRY:
				return {}
			var cavalry_count: int = _count_companies_of_type(regiment, SimTypes.CompanyType.CAVALRY) + 1
			var cavalry_weapon: String = "carbine" if cavalry_count % 2 == 1 else "pistol"
			return {
				"company_type": SimTypes.CompanyType.CAVALRY,
				"weapon_type": cavalry_weapon,
				"soldiers": 150,
				"name": "%s Squadron" % _get_ordinal_name(cavalry_count),
			}
		SimTypes.UnitCategory.ARTILLERY:
			if company_type != SimTypes.CompanyType.ARTILLERY:
				return {}
			var battery_index: int = _count_companies_of_type(regiment, SimTypes.CompanyType.ARTILLERY)
			var battery_letter_index: int = int(clamp(battery_index, 0, 25))
			var battery_letter: String = "ABCDEFGHIJKLMNOPQRSTUVWXYZ".substr(battery_letter_index, 1)
			return {
				"company_type": SimTypes.CompanyType.ARTILLERY,
				"weapon_type": "cannon",
				"soldiers": 100,
				"name": "Battery Section %s" % battery_letter,
			}
		_:
			match company_type:
				SimTypes.CompanyType.MUSKETEERS:
					var musket_count: int = _count_companies_of_type(regiment, SimTypes.CompanyType.MUSKETEERS) + 1
					return {
						"company_type": SimTypes.CompanyType.MUSKETEERS,
						"weapon_type": "musket",
						"soldiers": 200,
						"name": "%s Musketeer Company" % _get_ordinal_name(musket_count),
					}
				SimTypes.CompanyType.PIKEMEN:
					var pike_count: int = _count_companies_of_type(regiment, SimTypes.CompanyType.PIKEMEN) + 1
					return {
						"company_type": SimTypes.CompanyType.PIKEMEN,
						"weapon_type": "pike",
						"soldiers": 200,
						"name": "%s Pike Company" % _get_ordinal_name(pike_count),
					}
	return {}


func _count_companies_of_type(regiment: Battalion, company_type: int) -> int:
	var seen_tags: Dictionary = {}
	for stand_value in regiment.stands:
		var stand: CombatStand = stand_value
		if stand.company_type != company_type:
			continue
		var tag: StringName = stand.editor_company_tag if stand.editor_company_tag != &"" else StringName(String(stand.id))
		seen_tags[tag] = true
	return seen_tags.size()


func _create_stands_from_company_spec(regiment: Battalion, company_spec: Dictionary) -> Array:
	var result: Array = []
	var company_name: String = String(company_spec.get("name", "Company"))
	var company_type: int = int(company_spec.get("company_type", SimTypes.CompanyType.MUSKETEERS))
	var weapon_type: String = String(company_spec.get("weapon_type", "musket"))
	var soldiers: int = max(1, int(company_spec.get("soldiers", 200)))
	var stand_count: int = max(1, int(ceil(float(soldiers) / float(RUNTIME_STAND_HEADCOUNT))))
	var company_ordinal: int = _count_companies_of_type(regiment, company_type) + 1
	var editor_company_tag: StringName = StringName("%s_editor_company_%s_%02d" % [
		String(regiment.id),
		str(company_type),
		company_ordinal,
	])
	var remaining_soldiers: int = soldiers
	for stand_index in range(stand_count):
		var stand_soldiers: int = min(RUNTIME_STAND_HEADCOUNT, remaining_soldiers)
		if stand_index == stand_count - 1:
			stand_soldiers = max(1, remaining_soldiers)
		var stand: CombatStand = CombatStand.new(
			StringName("%s_stand_runtime_%02d_%02d_%02d" % [String(regiment.id), company_type, company_ordinal, stand_index + 1]),
			"%s Stand %d" % [company_name, stand_index + 1],
			company_type,
			regiment.category,
			weapon_type,
			stand_soldiers,
			regiment.base_commander_quality
		)
		stand.editor_company_tag = editor_company_tag
		stand.editor_company_name = company_name
		if company_type == SimTypes.CompanyType.ARTILLERY:
			stand.home_segment = &"battery"
		elif company_type == SimTypes.CompanyType.PIKEMEN:
			stand.home_segment = &"core"
		elif stand_count <= 1:
			stand.home_segment = &"center"
		else:
			var ratio: float = float(stand_index) / float(max(1, stand_count - 1))
			if ratio <= 0.25:
				stand.home_segment = &"left"
			elif ratio >= 0.75:
				stand.home_segment = &"right"
			else:
				stand.home_segment = &"center"
		result.append(stand)
		remaining_soldiers = max(0, remaining_soldiers - stand_soldiers)
	return result


func _get_ordinal_name(index: int) -> String:
	match index:
		1:
			return "1st"
		2:
			return "2nd"
		3:
			return "3rd"
		_:
			return "%dth" % index


func push_event(text: String) -> void:
	_push_event(text)


func find_nearest_enemy(regiment: Battalion) -> Battalion:
	return _find_nearest_enemy(regiment)


func get_regiment_by_id(regiment_id: StringName) -> Battalion:
	return regiments.get(regiment_id)


func count_enemy_regiments_near(center: Vector2, army_id: StringName, radius: float) -> int:
	return _count_enemy_regiments_near(center, army_id, radius)


func count_friendly_regiments_near(center: Vector2, army_id: StringName, radius: float) -> int:
	return _count_friendly_regiments_near(center, army_id, radius)


func get_army_fallback_position(army_id: StringName) -> Vector2:
	return _get_army_fallback_position(army_id)


func visibility_between(start_position: Vector2, end_position: Vector2) -> float:
	return _visibility_between(start_position, end_position)


func sampled_visibility_between_battalions(observer: Battalion, target: Battalion, max_samples: int = 5) -> float:
	if observer == null or target == null:
		return 0.0
	var observer_samples: Array = _get_battalion_visibility_sample_points(observer, max_samples)
	var target_samples: Array = _get_battalion_visibility_sample_points(target, max_samples)
	if observer_samples.is_empty() or target_samples.is_empty():
		return 0.0
	var best_visibility: float = 0.0
	for observer_sample_value in observer_samples:
		var observer_sample: Vector2 = observer_sample_value
		for target_sample_value in target_samples:
			var target_sample: Vector2 = target_sample_value
			best_visibility = max(best_visibility, _visibility_between(observer_sample, target_sample))
			if best_visibility >= 0.999:
				return best_visibility
	return best_visibility


func sampled_visibility_between_position_and_battalion(origin: Vector2, target: Battalion, max_samples: int = 5) -> float:
	if target == null:
		return 0.0
	var target_samples: Array = _get_battalion_visibility_sample_points(target, max_samples)
	if target_samples.is_empty():
		return 0.0
	var best_visibility: float = 0.0
	for target_sample_value in target_samples:
		var target_sample: Vector2 = target_sample_value
		best_visibility = max(best_visibility, _visibility_between(origin, target_sample))
		if best_visibility >= 0.999:
			return best_visibility
	return best_visibility


func get_brigade_anchor_position(brigade: Brigade) -> Vector2:
	return _get_brigade_anchor_position(brigade)


func get_brigade_hq_offset(brigade: Brigade) -> Vector2:
	return _get_brigade_hq_offset(brigade)


func _is_hq_visible_to_army(hq: HQ, army_id: StringName) -> bool:
	return _is_position_visible_to_army(hq.position, army_id)


func _is_position_visible_to_army(world_position: Vector2, army_id: StringName) -> bool:
	return _get_visibility_strength_for_army(world_position, army_id) >= 0.2


func _get_visibility_strength_for_army(world_position: Vector2, army_id: StringName) -> float:
	var best_visibility: float = 0.0
	for observer in _get_observers_for_army(army_id):
		var observer_range: float = observer.get_vision_range() if observer is Battalion else observer.command_radius * 1.2
		var distance: float = observer.position.distance_to(world_position)
		if distance > observer_range:
			continue
		var path_visibility: float = _visibility_between(observer.position, world_position)
		var effective_range: float = observer_range * path_visibility
		if distance > effective_range:
			continue
		var local_visibility: float = clamp(1.0 - distance / max(1.0, effective_range), 0.2, 1.0)
		best_visibility = max(best_visibility, local_visibility)
	return best_visibility


func _get_battalion_visibility_sample_points(battalion: Battalion, max_samples: int = 5) -> Array:
	var samples: Array = []
	if battalion == null:
		return samples
	if battalion.companies.is_empty():
		samples.append(battalion.position)
		return samples
	var front: Vector2 = battalion.front_direction.normalized()
	if front.length_squared() <= 0.001:
		front = Vector2.UP
	var right_axis: Vector2 = Vector2(-front.y, front.x).normalized()
	var entries: Array = []
	for company_value in battalion.companies:
		var stand: CombatStand = company_value
		var world_position: Vector2 = battalion.get_company_world_position(stand)
		var offset: Vector2 = world_position - battalion.position
		entries.append({
			"position": world_position,
			"lateral": offset.dot(right_axis),
			"depth": offset.dot(front),
			"distance_to_center": offset.length_squared(),
		})
	var selected_positions: Dictionary = {}
	_add_battalion_sample_entry(samples, selected_positions, _pick_battalion_sample_entry(entries, "distance_to_center", true))
	_add_battalion_sample_entry(samples, selected_positions, _pick_battalion_sample_entry(entries, "depth", false))
	_add_battalion_sample_entry(samples, selected_positions, _pick_battalion_sample_entry(entries, "depth", true))
	_add_battalion_sample_entry(samples, selected_positions, _pick_battalion_sample_entry(entries, "lateral", false))
	_add_battalion_sample_entry(samples, selected_positions, _pick_battalion_sample_entry(entries, "lateral", true))
	var entry_index: int = 0
	while samples.size() < max(1, max_samples) and entry_index < entries.size():
		_add_battalion_sample_entry(samples, selected_positions, entries[entry_index])
		entry_index += 1
	if samples.is_empty():
		samples.append(battalion.position)
	return samples


func _pick_battalion_sample_entry(entries: Array, field_name: String, pick_smallest: bool) -> Dictionary:
	if entries.is_empty():
		return {}
	var best_entry: Dictionary = entries[0]
	var best_value: float = float(best_entry.get(field_name, 0.0))
	for entry_value in entries:
		var entry: Dictionary = entry_value
		var value: float = float(entry.get(field_name, 0.0))
		if pick_smallest:
			if value < best_value:
				best_value = value
				best_entry = entry
		elif value > best_value:
			best_value = value
			best_entry = entry
	return best_entry


func _add_battalion_sample_entry(samples: Array, selected_positions: Dictionary, entry: Dictionary) -> void:
	if entry.is_empty():
		return
	var sample_position: Vector2 = entry.get("position", Vector2.ZERO)
	var sample_key: String = "%.2f:%.2f" % [sample_position.x, sample_position.y]
	if selected_positions.has(sample_key):
		return
	selected_positions[sample_key] = true
	samples.append(sample_position)


func _visibility_between(start_position: Vector2, end_position: Vector2) -> float:
	var visibility: float = 1.0
	var distance: float = start_position.distance_to(end_position)
	if distance <= 1.0:
		return visibility
	var steps: int = max(1, int(distance / 64.0))
	var start_terrain: TerrainCell = get_terrain_at(start_position)
	var end_terrain: TerrainCell = get_terrain_at(end_position)
	var start_height: float = start_terrain.average_height if start_terrain != null else 0.0
	var end_height: float = end_terrain.average_height if end_terrain != null else 0.0
	var max_mid_height: float = max(start_height, end_height)
	for step_index in range(1, steps):
		var t: float = float(step_index) / float(steps)
		var sample_position: Vector2 = start_position.lerp(end_position, t)
		var cell: TerrainCell = get_terrain_at(sample_position)
		visibility *= clamp(cell.visibility_multiplier, 0.38, 1.08)
		max_mid_height = max(max_mid_height, cell.average_height)
		match cell.terrain_type:
			SimTypes.TerrainType.FOREST:
				visibility *= 0.82
			SimTypes.TerrainType.VILLAGE, SimTypes.TerrainType.BUSHES:
				visibility *= 0.88
			SimTypes.TerrainType.SWAMP:
				visibility *= 0.93
	if max_mid_height > max(start_height, end_height) + 0.18:
		visibility *= 0.72
	return clamp(visibility, 0.08, 1.0)


func _get_brigade_anchor_position(brigade: Brigade) -> Vector2:
	var total_position: Vector2 = Vector2.ZERO
	var count: int = 0
	for regiment_id in brigade.regiment_ids:
		var regiment: Battalion = regiments.get(regiment_id)
		if regiment == null or regiment.is_destroyed:
			continue
		total_position += regiment.position
		count += 1
	if count == 0:
		return brigade_position(brigade)
	return total_position / float(count)


func _get_brigade_hq_offset(brigade: Brigade) -> Vector2:
	var brigade_hq: HQ = hqs.get(brigade.hq_id)
	if brigade_hq == null:
		return Vector2.ZERO
	var target_direction: Vector2 = Vector2.DOWN
	for regiment_id in brigade.regiment_ids:
		var regiment: Battalion = regiments.get(regiment_id)
		if regiment == null:
			continue
		var movement_direction: Vector2 = regiment.current_target_position - regiment.position
		if movement_direction.length() > 1.0:
			target_direction = movement_direction.normalized()
			break
	return -target_direction * 70.0


func _get_enemy_army_id(army_id: StringName) -> StringName:
	for candidate_id in armies.keys():
		if candidate_id != army_id:
			return candidate_id
	return &""


func _get_brigade_id_for_hq(hq_id: StringName) -> StringName:
	for brigade_value in brigades.values():
		var brigade: Brigade = brigade_value
		if brigade.hq_id == hq_id:
			return brigade.id
	return &""
