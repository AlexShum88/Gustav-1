class_name BattleController
extends Node2D

var _server: SimulationServer
var _battlefield_view: BattlefieldView
var _hud: BattleHUD
var _camera: Camera2D
var _ui_layer: CanvasLayer

var _latest_snapshot: Dictionary = {}
var _selected_regiment_id: StringName = &""
var _pending_order_type: int = SimTypes.OrderType.NONE
var _pending_policies: Dictionary = {
	"road_column": true,
	"deploy_on_contact": true,
	"retreat_on_flank_collapse": false,
	"hold_reserve": false,
}
var _order_anchor_position: Vector2 = Vector2.ZERO
var _preview_target_position: Vector2 = Vector2.ZERO
var _is_order_gesture_active: bool = false
var _camera_zoom: float = 1.0
var _camera_pan_speed: float = 980.0
var _camera_zoom_step: float = 0.12
var _camera_zoom_min: float = 0.3
var _camera_zoom_max: float = 1.75
var _pre_battle_active: bool = true
var _last_view_interest_rect: Rect2 = Rect2()
var _last_view_interest_zoom: float = -INF
var _last_view_interest_regiment_id: StringName = &""
var _last_view_interest_brigade_id: StringName = &""

func _ready() -> void:
	_server = SimulationServer.new()
	_server.name = "SimulationServer"
	add_child(_server)

	_battlefield_view = BattlefieldView.new()
	_battlefield_view.name = "BattlefieldView"
	add_child(_battlefield_view)

	_camera = Camera2D.new()
	_camera.name = "BattleCamera"
	_camera.position = Vector2(800.0, 450.0)
	_camera.zoom = Vector2.ONE
	_camera.enabled = true
	add_child(_camera)

	_ui_layer = CanvasLayer.new()
	_ui_layer.name = "UILayer"
	add_child(_ui_layer)

	_hud = BattleHUD.new()
	_hud.name = "BattleHUD"
	_ui_layer.add_child(_hud)

	_server.snapshot_ready.connect(_on_snapshot_ready)
	_hud.order_type_selected.connect(_on_order_type_selected)
	_hud.policies_changed.connect(_on_policies_changed)
	_hud.order_cancelled.connect(_on_order_cancelled)
	_hud.debug_formation_selected.connect(_on_debug_formation_selected)
	_hud.debug_fire_behavior_selected.connect(_on_debug_fire_behavior_selected)
	_hud.debug_fire_requested.connect(_on_debug_fire_requested)
	_hud.debug_override_cleared.connect(_on_debug_override_cleared)
	_hud.pre_battle_start_requested.connect(_on_pre_battle_start_requested)
	_hud.editor_command_profile_selected.connect(_on_editor_command_profile_selected)
	_hud.editor_banner_profile_selected.connect(_on_editor_banner_profile_selected)
	_hud.editor_add_company_requested.connect(_on_editor_add_company_requested)
	_hud.editor_remove_company_requested.connect(_on_editor_remove_company_requested)

	# The prototype runs client and server in one process, but commands still
	# flow through the same server-authoritative boundary the multiplayer build needs.
	var simulation: BattleSimulation = BattleScenarioFactory.create_large_test_battle({
		&"blue": PlayerArmyRepository.get_selected_army(),
	})
	_server.configure(simulation, &"blue")
	_pre_battle_active = false
	_server.set_paused(false)
	_camera.position = simulation.map_rect.get_center()
	_battlefield_view.set_view_zoom(_camera_zoom)
	_hud.set_pre_battle_active(false)
	_clamp_camera_to_map()
	_update_view_culling_rect()


func _process(delta: float) -> void:
	_update_camera(delta)
	_refresh_live_order_preview()
	_update_view_culling_rect()


func _unhandled_input(event: InputEvent) -> void:
	if _latest_snapshot.is_empty():
		if event is InputEventMouseButton:
			_handle_camera_zoom_input(event)
		return
	if event is InputEventMouseButton:
		_handle_camera_zoom_input(event)
	if event is InputEventMouseMotion and _pending_order_type != SimTypes.OrderType.NONE:
		if _pre_battle_active:
			return
		if not _is_line_order_type(_pending_order_type):
			_order_anchor_position = _get_selected_brigade_hq_position()
		_preview_target_position = get_global_mouse_position()
		_battlefield_view.update_order_preview(_pending_order_type, _order_anchor_position, _preview_target_position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var world_position: Vector2 = get_global_mouse_position()
		var regiment_id: StringName = _battlefield_view.pick_regiment_at(world_position)
		if regiment_id != &"" and not _is_order_gesture_active:
			var regiment_data: Dictionary = _battlefield_view.get_regiment_snapshot(regiment_id)
			if regiment_data.get("is_friendly", false):
				_selected_regiment_id = regiment_id
				_refresh_views()
			return
		if _pre_battle_active:
			return
		if _pending_order_type != SimTypes.OrderType.NONE and _selected_regiment_id != &"":
			_handle_order_click(world_position)


func _handle_order_click(world_position: Vector2) -> void:
	if not _is_line_order_type(_pending_order_type):
		var auto_anchor_position: Vector2 = _get_selected_brigade_hq_position()
		_issue_pending_order(auto_anchor_position, world_position)
		return
	if not _is_order_gesture_active:
		_order_anchor_position = world_position
		_preview_target_position = world_position
		_is_order_gesture_active = true
		_refresh_views()
		return
	_issue_pending_order(_order_anchor_position, world_position)


func _issue_pending_order(anchor_position: Vector2, target_position: Vector2) -> void:
	var selected_regiment: Dictionary = _battlefield_view.get_regiment_snapshot(_selected_regiment_id)
	if selected_regiment.is_empty():
		return
	var brigade_id: String = String(selected_regiment.get("brigade_id", ""))
	var line_start: Vector2 = Vector2.ZERO
	var line_end: Vector2 = Vector2.ZERO
	var path_points: Array = []
	if _pending_order_type in [SimTypes.OrderType.DEFEND, SimTypes.OrderType.HOLD]:
		line_start = anchor_position
		line_end = target_position
	else:
		path_points = [anchor_position, target_position]
	_server.submit_player_command({
		"army_id": "blue",
		"recipient_brigade_id": brigade_id,
		"order_type": _pending_order_type,
		"target_position": target_position,
		"line_start": line_start,
		"line_end": line_end,
		"path_points": path_points,
		"policies": _pending_policies.duplicate(true),
	})
	_pending_order_type = SimTypes.OrderType.NONE
	_is_order_gesture_active = false
	_order_anchor_position = Vector2.ZERO
	_preview_target_position = target_position
	_refresh_views()


func _on_snapshot_ready(snapshot: Dictionary) -> void:
	_latest_snapshot = _merge_snapshot(snapshot)
	_battlefield_view.apply_snapshot(snapshot)
	if _selected_regiment_id != &"" and _find_regiment_in_snapshot(_latest_snapshot, _selected_regiment_id).is_empty():
		_selected_regiment_id = &""
	if _selected_regiment_id == &"":
		for regiment_data in _get_unit_snapshots(_latest_snapshot):
			if regiment_data.get("is_friendly", false):
				_selected_regiment_id = StringName(regiment_data.get("id", ""))
				break
	if _pending_order_type != SimTypes.OrderType.NONE and not _is_line_order_type(_pending_order_type):
		_order_anchor_position = _get_selected_brigade_hq_position()
	_refresh_views()


func _merge_snapshot(incoming_snapshot: Dictionary) -> Dictionary:
	var merged_snapshot: Dictionary = {
		"time_seconds": _latest_snapshot.get("time_seconds", 0.0),
		"player_army_id": _latest_snapshot.get("player_army_id", ""),
		"meta": _latest_snapshot.get("meta", {}),
		"channels": _latest_snapshot.get("channels", {}).duplicate(false),
	}
	var merged_channels: Dictionary = merged_snapshot.get("channels", {})
	for channel_name in incoming_snapshot.get("channels", {}).keys():
		var incoming_channel: Dictionary = incoming_snapshot.get("channels", {}).get(channel_name, {})
		if channel_name == "units":
			merged_channels[channel_name] = _resolve_units_channel_delta(
				merged_channels.get(channel_name, {}),
				incoming_channel
			)
			continue
		merged_channels[channel_name] = incoming_channel
	merged_snapshot["channels"] = merged_channels
	merged_snapshot["time_seconds"] = incoming_snapshot.get("time_seconds", merged_snapshot.get("time_seconds", 0.0))
	merged_snapshot["player_army_id"] = incoming_snapshot.get("player_army_id", merged_snapshot.get("player_army_id", ""))
	merged_snapshot["meta"] = incoming_snapshot.get("meta", merged_snapshot.get("meta", {}))
	return merged_snapshot


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


func _refresh_views() -> void:
	_battlefield_view.set_selected_regiment(_selected_regiment_id)
	_battlefield_view.set_selected_brigade(StringName(_get_selected_brigade_id()))
	_battlefield_view.update_order_preview(_pending_order_type, _order_anchor_position, _preview_target_position)
	_hud.set_snapshot(_latest_snapshot, _battlefield_view.get_regiment_snapshot(_selected_regiment_id), _pending_order_type, _battlefield_view.get_performance_stats())
	_update_view_culling_rect()


func _on_order_type_selected(order_type: int) -> void:
	if _pre_battle_active:
		return
	_pending_order_type = order_type
	_order_anchor_position = _get_selected_brigade_hq_position() if not _is_line_order_type(order_type) else Vector2.ZERO
	_is_order_gesture_active = false
	_preview_target_position = _battlefield_view.get_global_mouse_position()
	_refresh_views()


func _on_policies_changed(policies: Dictionary) -> void:
	if _pre_battle_active:
		return
	_pending_policies = policies.duplicate(true)
	_refresh_views()


func _on_order_cancelled() -> void:
	if _pre_battle_active:
		return
	_pending_order_type = SimTypes.OrderType.NONE
	_is_order_gesture_active = false
	_order_anchor_position = Vector2.ZERO
	_refresh_views()


func _on_debug_formation_selected(formation_state: int) -> void:
	if _selected_regiment_id == &"":
		return
	_server.set_regiment_debug_formation(_selected_regiment_id, formation_state)


func _on_debug_fire_behavior_selected(fire_behavior: int) -> void:
	if _selected_regiment_id == &"":
		return
	_server.set_regiment_debug_fire_behavior(_selected_regiment_id, fire_behavior)


func _on_debug_fire_requested() -> void:
	if _selected_regiment_id == &"":
		return
	_server.trigger_regiment_debug_fire(_selected_regiment_id, 3.0)


func _on_debug_override_cleared() -> void:
	if _selected_regiment_id == &"":
		return
	_server.clear_regiment_debug_overrides(_selected_regiment_id)


func _on_pre_battle_start_requested() -> void:
	_pre_battle_active = false
	_pending_order_type = SimTypes.OrderType.NONE
	_is_order_gesture_active = false
	_server.set_paused(false)
	_hud.set_pre_battle_active(false)
	_refresh_views()


func _on_editor_command_profile_selected(profile_id: StringName) -> void:
	if _selected_regiment_id == &"" or not _pre_battle_active:
		return
	_server.set_regiment_command_profile(_selected_regiment_id, profile_id)


func _on_editor_banner_profile_selected(profile_id: StringName) -> void:
	if _selected_regiment_id == &"" or not _pre_battle_active:
		return
	_server.set_regiment_banner_profile(_selected_regiment_id, profile_id)


func _on_editor_add_company_requested(company_type: int) -> void:
	if _selected_regiment_id == &"" or not _pre_battle_active:
		return
	_server.add_company_to_regiment(_selected_regiment_id, company_type)


func _on_editor_remove_company_requested(company_type: int) -> void:
	if _selected_regiment_id == &"" or not _pre_battle_active:
		return
	_server.remove_company_from_regiment(_selected_regiment_id, company_type)


func _find_regiment_in_snapshot(snapshot: Dictionary, regiment_id: StringName) -> Dictionary:
	for regiment_data in _get_unit_snapshots(snapshot):
		if StringName(regiment_data.get("id", "")) == regiment_id:
			return regiment_data
	return {}


func _get_unit_snapshots(snapshot: Dictionary) -> Array:
	var units: Dictionary = snapshot.get("channels", {}).get("units", {})
	return units.get("battalions", units.get("regiments", []))


func _is_line_order_type(order_type: int) -> bool:
	return order_type in [SimTypes.OrderType.DEFEND, SimTypes.OrderType.HOLD]


func _get_selected_brigade_hq_position() -> Vector2:
	var brigade_id: String = _get_selected_brigade_id()
	if brigade_id == "":
		return Vector2.ZERO
	for hq_data in _latest_snapshot.get("channels", {}).get("units", {}).get("hqs", []):
		if String(hq_data.get("role", "")) != "brigade":
			continue
		if String(hq_data.get("brigade_id", "")) != brigade_id:
			continue
		return hq_data.get("position", Vector2.ZERO)
	return Vector2.ZERO


func _get_selected_brigade_id() -> String:
	var selected_regiment: Dictionary = _battlefield_view.get_regiment_snapshot(_selected_regiment_id)
	if selected_regiment.is_empty():
		return ""
	return String(selected_regiment.get("brigade_id", ""))


func _refresh_live_order_preview() -> void:
	if _battlefield_view == null:
		return
	if _pre_battle_active:
		return
	if _pending_order_type == SimTypes.OrderType.NONE:
		return
	var next_anchor: Vector2 = _order_anchor_position
	if not _is_line_order_type(_pending_order_type):
		next_anchor = _get_selected_brigade_hq_position()
	var next_target: Vector2 = _battlefield_view.get_global_mouse_position()
	var anchor_changed: bool = next_anchor.distance_to(_order_anchor_position) > 0.05
	var target_changed: bool = next_target.distance_to(_preview_target_position) > 0.05
	if not anchor_changed and not target_changed:
		return
	_order_anchor_position = next_anchor
	_preview_target_position = next_target
	_battlefield_view.update_order_preview(_pending_order_type, _order_anchor_position, _preview_target_position)


func _update_camera(delta: float) -> void:
	if _camera == null:
		return
	var movement: Vector2 = Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W):
		movement.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S):
		movement.y += 1.0
	if Input.is_physical_key_pressed(KEY_A):
		movement.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D):
		movement.x += 1.0
	if movement.length() > 0.001:
		var zoom_speed_multiplier: float = 1.0 / max(_camera_zoom, 0.3)
		_camera.position += movement.normalized() * _camera_pan_speed * zoom_speed_multiplier * delta
		_clamp_camera_to_map()


func _handle_camera_zoom_input(event: InputEventMouseButton) -> void:
	if not event.pressed:
		return
	if event.button_index == MOUSE_BUTTON_WHEEL_UP:
		_set_camera_zoom(_camera_zoom - _camera_zoom_step)
	elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_set_camera_zoom(_camera_zoom + _camera_zoom_step)


func _set_camera_zoom(new_zoom: float) -> void:
	_camera_zoom = clamp(new_zoom, _camera_zoom_min, _camera_zoom_max)
	if _camera != null:
		_camera.zoom = Vector2(_camera_zoom, _camera_zoom)
		if _battlefield_view != null:
			_battlefield_view.set_view_zoom(_camera_zoom)
		_clamp_camera_to_map()


func _clamp_camera_to_map() -> void:
	if _camera == null:
		return
	var map_rect: Rect2 = _latest_snapshot.get("channels", {}).get("static_world", {}).get("map_rect", Rect2(0.0, 0.0, 2800.0, 1800.0))
	var viewport_size: Vector2 = get_viewport_rect().size
	var half_view: Vector2 = viewport_size * 0.5 * _camera_zoom
	var min_x: float = map_rect.position.x + half_view.x
	var max_x: float = map_rect.end.x - half_view.x
	var min_y: float = map_rect.position.y + half_view.y
	var max_y: float = map_rect.end.y - half_view.y
	if min_x > max_x:
		_camera.position.x = map_rect.get_center().x
	else:
		_camera.position.x = clamp(_camera.position.x, min_x, max_x)
	if min_y > max_y:
		_camera.position.y = map_rect.get_center().y
	else:
		_camera.position.y = clamp(_camera.position.y, min_y, max_y)


func _update_view_culling_rect() -> void:
	if _camera == null or _battlefield_view == null:
		return
	var viewport_size: Vector2 = get_viewport_rect().size
	var half_view: Vector2 = viewport_size * 0.5 * _camera_zoom
	var base_rect: Rect2 = Rect2(_camera.position - half_view, half_view * 2.0)
	var cull_margin: float = max(1600.0, max(base_rect.size.x, base_rect.size.y) * 0.70)
	var visible_rect: Rect2 = base_rect.grow(cull_margin)
	_battlefield_view.set_world_view_rect(visible_rect)
	var selected_brigade_id: StringName = StringName(_get_selected_brigade_id())
	if visible_rect == _last_view_interest_rect \
			and absf(_camera_zoom - _last_view_interest_zoom) <= 0.001 \
			and _selected_regiment_id == _last_view_interest_regiment_id \
			and selected_brigade_id == _last_view_interest_brigade_id:
		return
	_last_view_interest_rect = visible_rect
	_last_view_interest_zoom = _camera_zoom
	_last_view_interest_regiment_id = _selected_regiment_id
	_last_view_interest_brigade_id = selected_brigade_id
	if _server != null:
		_server.set_view_interest(
			visible_rect,
			_camera_zoom,
			_selected_regiment_id,
			selected_brigade_id
		)
