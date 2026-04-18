class_name BattlefieldView
extends Node2D

var snapshot: Dictionary = {}
var selected_regiment_id: StringName = &""
var pending_order_type: int = SimTypes.OrderType.NONE
var preview_anchor_position: Vector2 = Vector2.ZERO
var preview_target_position: Vector2 = Vector2.ZERO

var _ground_layer: GroundLayer
var _terrain_overlay_layer: TerrainOverlayLayer
var _strategic_point_layer: StrategicPointLayer
var _marker_layer: MarkerLayer
var _casualty_layer: CasualtyLayer
var _batch_units_layer: SubunitBatchView
var _units_layer: UnitsLayer
var _vision_outline_layer: VisionOutlineLayer
var _fog_overlay: FogOfWarOverlay
var _order_preview_overlay: OrderPreviewOverlay
var _last_static_world_stamp: float = -1.0
var _last_units_stamp: float = -1.0
var _last_fog_stamp: float = -1.0
var _last_selection_stamp: float = -1.0
var _view_zoom: float = 1.0
var _batched_units_active: bool = false
var _selected_brigade_id: StringName = &""
var _world_view_rect: Rect2 = Rect2(-100000.0, -100000.0, 200000.0, 200000.0)
var _last_apply_snapshot_ms: float = 0.0
var _last_units_sync_ms: float = 0.0
var _last_selection_sync_ms: float = 0.0
var _resolved_channels: Dictionary = {
	"static_world": {},
	"units": {},
	"fog": {},
	"ui": {},
	"selection": {},
}
var _regiment_snapshots_by_id: Dictionary = {}

const BATCHED_UNITS_ZOOM_THRESHOLD: float = 0.82
const ENABLE_BATTLEFIELD_LOD: bool = false


func _ready() -> void:
	_ground_layer = GroundLayer.new()
	_ground_layer.z_index = 0
	add_child(_ground_layer)

	_terrain_overlay_layer = TerrainOverlayLayer.new()
	_terrain_overlay_layer.z_index = 1
	add_child(_terrain_overlay_layer)

	_strategic_point_layer = StrategicPointLayer.new()
	_strategic_point_layer.z_index = 2
	add_child(_strategic_point_layer)

	_marker_layer = MarkerLayer.new()
	_marker_layer.z_index = 3
	add_child(_marker_layer)

	_casualty_layer = CasualtyLayer.new()
	_casualty_layer.z_index = 4
	add_child(_casualty_layer)

	_batch_units_layer = SubunitBatchView.new()
	_batch_units_layer.z_index = 5
	add_child(_batch_units_layer)

	_units_layer = UnitsLayer.new()
	_units_layer.z_index = 6
	add_child(_units_layer)

	_vision_outline_layer = VisionOutlineLayer.new()
	_vision_outline_layer.z_index = 7
	add_child(_vision_outline_layer)

	_order_preview_overlay = OrderPreviewOverlay.new()
	_order_preview_overlay.z_index = 8
	add_child(_order_preview_overlay)

	_fog_overlay = FogOfWarOverlay.new()
	_fog_overlay.z_index = 9
	add_child(_fog_overlay)


func apply_snapshot(new_snapshot: Dictionary) -> void:
	var apply_start_us: int = Time.get_ticks_usec()
	_merge_snapshot(new_snapshot)
	var incoming_channels: Dictionary = new_snapshot.get("channels", {})
	var static_world_channel: Dictionary = _get_static_world_channel()
	var units_channel: Dictionary = _get_units_channel()
	var fog_channel: Dictionary = _get_fog_channel()
	var selection_channel: Dictionary = _get_selection_channel()
	var static_stamp: float = float(static_world_channel.get("stamp", 1.0))
	var units_stamp: float = float(units_channel.get("stamp", -1.0))
	var fog_stamp: float = float(fog_channel.get("stamp", -1.0))
	var selection_stamp: float = float(selection_channel.get("stamp", -1.0))
	var static_changed: bool = incoming_channels.has("static_world") and static_stamp != _last_static_world_stamp
	var units_changed: bool = incoming_channels.has("units") and units_stamp != _last_units_stamp
	var fog_changed: bool = incoming_channels.has("fog") and fog_stamp != _last_fog_stamp
	var selection_changed: bool = incoming_channels.has("selection") and selection_stamp != _last_selection_stamp
	if static_changed:
		_last_static_world_stamp = static_stamp
		_ground_layer.update_map_rect(static_world_channel.get("map_rect", Rect2(0.0, 0.0, 1600.0, 900.0)))
		_terrain_overlay_layer.update_regions(static_world_channel.get("terrain_regions", []))
		_casualty_layer.clear()
		_batch_units_layer.clear()
	if units_changed or static_changed:
		_last_units_stamp = units_stamp
		_marker_layer.update_from_snapshot(_build_marker_payload())
		_strategic_point_layer.update_points(units_channel.get("strategic_points", []))
		_sync_units_layer()
	if selection_changed or static_changed:
		_last_selection_stamp = selection_stamp
		_sync_selection_layer()
	if fog_changed:
		_last_fog_stamp = fog_stamp
		_fog_overlay.update_from_snapshot(fog_channel)
	_last_apply_snapshot_ms = float(Time.get_ticks_usec() - apply_start_us) / 1000.0


func set_selected_regiment(new_selected_regiment_id: StringName) -> void:
	selected_regiment_id = new_selected_regiment_id
	_batch_units_layer.set_selected_regiment(selected_regiment_id)
	_units_layer.set_selected_regiment(selected_regiment_id)
	_sync_selection_layer()


func set_selected_brigade(new_selected_brigade_id: StringName) -> void:
	_selected_brigade_id = new_selected_brigade_id
	_units_layer.set_selected_brigade(new_selected_brigade_id)
	_sync_selection_layer()


func set_view_zoom(new_zoom: float) -> void:
	_view_zoom = new_zoom
	_units_layer.set_view_zoom(new_zoom)
	_update_units_render_mode()


func set_world_view_rect(value: Rect2) -> void:
	if _world_view_rect == value:
		return
	_world_view_rect = value
	_batch_units_layer.set_world_view_rect(value)
	_units_layer.set_world_view_rect(value)
	_casualty_layer.set_world_view_rect(value)
	_marker_layer.set_world_view_rect(value)
	_strategic_point_layer.set_world_view_rect(value)
	_vision_outline_layer.set_world_view_rect(value)


func update_snapshot(
		new_snapshot: Dictionary,
		new_selected_regiment_id: StringName,
		new_pending_order_type: int,
		new_preview_anchor_position: Vector2,
		new_preview_target_position: Vector2
) -> void:
	apply_snapshot(new_snapshot)
	set_selected_regiment(new_selected_regiment_id)
	update_order_preview(new_pending_order_type, new_preview_anchor_position, new_preview_target_position)


func update_order_preview(new_pending_order_type: int, new_preview_anchor_position: Vector2, new_preview_target_position: Vector2) -> void:
	pending_order_type = new_pending_order_type
	preview_anchor_position = new_preview_anchor_position
	preview_target_position = new_preview_target_position
	_order_preview_overlay.update_preview(pending_order_type, preview_anchor_position, preview_target_position)


func pick_regiment_at(world_position: Vector2) -> StringName:
	if _use_batched_units_view():
		return _batch_units_layer.pick_regiment_at(world_position)
	return _units_layer.pick_regiment_at(world_position)


func get_regiment_snapshot(regiment_id: StringName) -> Dictionary:
	return _regiment_snapshots_by_id.get(regiment_id, {})


func _merge_snapshot(new_snapshot: Dictionary) -> void:
	var incoming_channels: Dictionary = new_snapshot.get("channels", {})
	for channel_name in incoming_channels.keys():
		if channel_name == "units":
			_resolved_channels[channel_name] = _resolve_units_channel_delta(
				_resolved_channels.get(channel_name, {}),
				incoming_channels[channel_name]
			)
			continue
		_resolved_channels[channel_name] = incoming_channels[channel_name]
	snapshot = {
		"time_seconds": float(new_snapshot.get("time_seconds", snapshot.get("time_seconds", 0.0))),
		"player_army_id": new_snapshot.get("player_army_id", snapshot.get("player_army_id", "")),
		"meta": new_snapshot.get("meta", snapshot.get("meta", {})),
		"channels": _resolved_channels,
	}


func _resolve_units_channel_delta(current_units: Dictionary, incoming_units: Dictionary) -> Dictionary:
	if not bool(incoming_units.get("is_delta", false)):
		return incoming_units
	var resolved_units: Dictionary = current_units.duplicate(false)
	resolved_units["stamp"] = incoming_units.get("stamp", resolved_units.get("stamp", 0.0))
	resolved_units["zoom"] = incoming_units.get("zoom", resolved_units.get("zoom", 1.0))
	resolved_units["visible_rect"] = incoming_units.get("visible_rect", resolved_units.get("visible_rect", Rect2()))
	resolved_units["hqs"] = incoming_units.get("hqs", resolved_units.get("hqs", []))
	resolved_units["messengers"] = incoming_units.get("messengers", resolved_units.get("messengers", []))
	resolved_units["convoys"] = incoming_units.get("convoys", resolved_units.get("convoys", []))
	resolved_units["last_seen_markers"] = incoming_units.get("last_seen_markers", resolved_units.get("last_seen_markers", []))
	resolved_units["strategic_points"] = incoming_units.get("strategic_points", resolved_units.get("strategic_points", []))
	var unit_key: String = "battalions" if current_units.has("battalions") or incoming_units.has("battalions_delta") or incoming_units.has("battalion_order") else "regiments"
	var delta_key: String = "battalions_delta" if unit_key == "battalions" else "regiments_delta"
	var removed_key: String = "removed_battalion_ids" if unit_key == "battalions" else "removed_regiment_ids"
	var order_key: String = "battalion_order" if unit_key == "battalions" else "regiment_order"
	var regiment_snapshots_by_id: Dictionary = {}
	for regiment_value in resolved_units.get(unit_key, []):
		var regiment_snapshot: Dictionary = regiment_value
		regiment_snapshots_by_id[StringName(regiment_snapshot.get("id", ""))] = regiment_snapshot
	for regiment_value in incoming_units.get(delta_key, []):
		var changed_regiment: Dictionary = regiment_value
		regiment_snapshots_by_id[StringName(changed_regiment.get("id", ""))] = changed_regiment
	for removed_id_value in incoming_units.get(removed_key, []):
		regiment_snapshots_by_id.erase(StringName(removed_id_value))
	var ordered_regiments: Array = []
	var seen_ids: Dictionary = {}
	for regiment_id_value in incoming_units.get(order_key, []):
		var regiment_id: StringName = StringName(regiment_id_value)
		if not regiment_snapshots_by_id.has(regiment_id):
			continue
		ordered_regiments.append(regiment_snapshots_by_id[regiment_id])
		seen_ids[regiment_id] = true
	for regiment_id_value in regiment_snapshots_by_id.keys():
		var regiment_id: StringName = regiment_id_value
		if seen_ids.has(regiment_id):
			continue
		ordered_regiments.append(regiment_snapshots_by_id[regiment_id])
	resolved_units[unit_key] = ordered_regiments
	resolved_units.erase("is_delta")
	resolved_units.erase("regiments_delta")
	resolved_units.erase("removed_regiment_ids")
	resolved_units.erase("regiment_order")
	resolved_units.erase("battalions_delta")
	resolved_units.erase("removed_battalion_ids")
	resolved_units.erase("battalion_order")
	return resolved_units


func _sync_units_layer() -> void:
	var sync_start_us: int = Time.get_ticks_usec()
	var sim_time_seconds: float = float(snapshot.get("time_seconds", 0.0))
	var snapshot_interval: float = float(snapshot.get("meta", {}).get("snapshot_interval", 1.0 / 16.0))
	_units_layer.set_snapshot_interval(snapshot_interval)
	_batch_units_layer.set_snapshot_interval(snapshot_interval)
	_units_layer.set_sim_time_seconds(sim_time_seconds)
	_casualty_layer.set_sim_time_seconds(sim_time_seconds)
	var regiments: Array = _get_unit_snapshots()
	_rebuild_regiment_index(regiments)
	if _use_batched_units_view():
		_batch_units_layer.update_from_regiments(regiments, selected_regiment_id)
		_batch_units_layer.set_selected_regiment(selected_regiment_id)
	else:
		_units_layer.update_from_regiments(regiments)
	_units_layer.set_selected_regiment(selected_regiment_id)
	_units_layer.set_selected_brigade(_selected_brigade_id)
	_casualty_layer.update_from_regiments(regiments)
	_update_units_render_mode()
	_last_units_sync_ms = float(Time.get_ticks_usec() - sync_start_us) / 1000.0


func _sync_selection_layer() -> void:
	var sync_start_us: int = Time.get_ticks_usec()
	var outlines: Array = []
	for entry_value in _get_selection_channel().get("vision_outlines", []):
		var entry: Dictionary = entry_value.duplicate(true)
		entry["is_selected"] = StringName(entry.get("regiment_id", "")) == selected_regiment_id
		outlines.append(entry)
	_vision_outline_layer.update_outlines(outlines)
	_last_selection_sync_ms = float(Time.get_ticks_usec() - sync_start_us) / 1000.0


func _rebuild_regiment_index(regiments: Array) -> void:
	_regiment_snapshots_by_id.clear()
	for regiment_value in regiments:
		var regiment_data: Dictionary = regiment_value
		_regiment_snapshots_by_id[StringName(regiment_data.get("id", ""))] = regiment_data


func _get_static_world_channel() -> Dictionary:
	return snapshot.get("channels", {}).get("static_world", {})


func _get_units_channel() -> Dictionary:
	return snapshot.get("channels", {}).get("units", {})


func _get_unit_snapshots() -> Array:
	var units_channel: Dictionary = _get_units_channel()
	return units_channel.get("battalions", units_channel.get("regiments", []))


func _get_fog_channel() -> Dictionary:
	return snapshot.get("channels", {}).get("fog", {})


func _get_ui_channel() -> Dictionary:
	return snapshot.get("channels", {}).get("ui", {})


func _get_selection_channel() -> Dictionary:
	return snapshot.get("channels", {}).get("selection", {})


func _build_marker_payload() -> Dictionary:
	return {
		"strategic_points": _get_units_channel().get("strategic_points", []),
		"hqs": _get_units_channel().get("hqs", []),
		"messengers": _get_units_channel().get("messengers", []),
		"convoys": _get_units_channel().get("convoys", []),
		"last_seen_markers": _get_units_channel().get("last_seen_markers", []),
	}


func get_performance_stats() -> Dictionary:
	var active_units_stats: Dictionary = _batch_units_layer.get_performance_stats() if _use_batched_units_view() else _units_layer.get_performance_stats()
	return {
		"apply_ms": _last_apply_snapshot_ms,
		"units_sync_ms": _last_units_sync_ms,
		"selection_sync_ms": _last_selection_sync_ms,
		"units": active_units_stats,
		"units_mode": "batched" if _use_batched_units_view() else "detailed",
		"casualties": _casualty_layer.get_performance_stats(),
		"fog": _fog_overlay.get_performance_stats(),
		"markers": _marker_layer.get_performance_stats(),
		"selection": _vision_outline_layer.get_performance_stats(),
	}


func _use_batched_units_view() -> bool:
	if not ENABLE_BATTLEFIELD_LOD:
		return false
	return _view_zoom >= BATCHED_UNITS_ZOOM_THRESHOLD


func _update_units_render_mode() -> void:
	var batched: bool = _use_batched_units_view()
	if batched != _batched_units_active and not snapshot.is_empty():
		var regiments: Array = _get_unit_snapshots()
		if batched:
			_batch_units_layer.set_snapshot_interval(float(snapshot.get("meta", {}).get("snapshot_interval", 1.0 / 16.0)))
			_batch_units_layer.update_from_regiments(regiments, selected_regiment_id)
		else:
			_units_layer.set_snapshot_interval(float(snapshot.get("meta", {}).get("snapshot_interval", 1.0 / 16.0)))
			_units_layer.set_sim_time_seconds(float(snapshot.get("time_seconds", 0.0)))
			_units_layer.update_from_regiments(regiments)
			_units_layer.set_selected_regiment(selected_regiment_id)
			_units_layer.set_selected_brigade(_selected_brigade_id)
	_batched_units_active = batched
	if _batch_units_layer != null:
		_batch_units_layer.visible = batched
	if _units_layer != null:
		_units_layer.visible = not batched
