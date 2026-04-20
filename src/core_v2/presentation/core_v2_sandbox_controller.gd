class_name CoreV2SandboxController
extends Node3D


var _server: CoreV2Server
var _client: CoreV2ClientBridge
var _view: CoreV2BattlefieldView
var _camera_rig: CoreV2TopDownCamera
var _ui_layer: CanvasLayer
var _hud: CoreV2Hud
var _latest_snapshot: Dictionary = {}
var _selected_entity_id: StringName = &""
var _selected_entity_kind: int = CoreV2Types.EntityKind.NONE
var _selected_battalion_id: StringName = &""
var _selected_brigade_id: StringName = &""
var _pending_order_type: int = CoreV2Types.OrderType.NONE
var _pending_placement_command: int = -1
var _pending_policies: Dictionary = {
	"road_column": true,
	"deploy_on_contact": true,
	"retreat_on_flank_collapse": false,
	"hold_reserve": false,
}
var _camera_configured: bool = false


func _ready() -> void:
	# Контролер працює як локальний клієнт: input -> client bridge -> server -> snapshot.
	_view = CoreV2BattlefieldView.new()
	_view.name = "BattlefieldView"
	add_child(_view)

	_camera_rig = CoreV2TopDownCamera.new()
	_camera_rig.name = "TopDownCamera"
	add_child(_camera_rig)

	_server = CoreV2Server.new()
	_server.name = "CoreV2Server"
	add_child(_server)

	_client = CoreV2ClientBridge.new()
	_client.name = "CoreV2ClientBridge"
	add_child(_client)

	_ui_layer = CanvasLayer.new()
	_ui_layer.name = "UiLayer"
	add_child(_ui_layer)

	_hud = CoreV2Hud.new()
	_hud.name = "CoreV2Hud"
	_ui_layer.add_child(_hud)

	_client.snapshot_updated.connect(_on_snapshot_updated)
	_hud.deployment_action_requested.connect(_on_deployment_action_requested)
	_hud.start_battle_requested.connect(_on_start_battle_requested)
	_hud.order_type_selected.connect(_on_order_type_selected)
	_hud.order_cancelled.connect(_on_order_cancelled)
	_hud.policies_changed.connect(_on_policies_changed)
	_hud.debug_formation_requested.connect(_on_debug_formation_requested)

	var battle_state: CoreV2BattleState = CoreV2ScenarioFactory.create_test_sandbox()
	_client.connect_to_server(_server, battle_state.player_army_id)
	_server.configure(battle_state, battle_state.player_army_id)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_pending_order_type = CoreV2Types.OrderType.NONE
		_pending_placement_command = -1
		_refresh_views()
		return
	if not (event is InputEventMouseButton):
		return
	var mouse_event: InputEventMouseButton = event
	if not mouse_event.pressed or mouse_event.button_index != MOUSE_BUTTON_LEFT:
		return
	_handle_left_click(mouse_event.position)


func _handle_left_click(screen_position: Vector2) -> void:
	var ground_point_variant: Variant = _camera_rig.screen_to_ground(screen_position)
	if ground_point_variant == null:
		return
	var ground_point: Vector3 = ground_point_variant
	if _pending_placement_command >= 0:
		# Під час active pause кліки йдуть на стартове розміщення обозу або штабу.
		_client.submit_ui_command({
			"command_type": _pending_placement_command,
			"position": ground_point,
		})
		_pending_placement_command = -1
		_refresh_views()
		return
	if _pending_order_type != CoreV2Types.OrderType.NONE:
		var selected_unit: Dictionary = _get_selected_unit_snapshot()
		var order_command: Dictionary = _build_selected_order_command(selected_unit, ground_point)
		if order_command.is_empty():
			return
		_client.submit_ui_command(order_command)
		_pending_order_type = CoreV2Types.OrderType.NONE
		_refresh_views()
		return
	var picked_unit: Dictionary = _view.pick_selectable_at(ground_point)
	if picked_unit.is_empty():
		return
	_select_unit(
		StringName(picked_unit.get("id", "")),
		int(picked_unit.get("entity_kind", CoreV2Types.EntityKind.NONE))
	)
	_refresh_views()


func _select_unit(entity_id: StringName, entity_kind: int) -> void:
	_selected_entity_id = entity_id
	_selected_entity_kind = entity_kind
	_selected_battalion_id = entity_id if entity_kind == CoreV2Types.EntityKind.BATTALION else &""
	_selected_brigade_id = _resolve_selected_brigade_id(entity_id, entity_kind)


func _get_selected_unit_snapshot() -> Dictionary:
	if _selected_entity_kind == CoreV2Types.EntityKind.BATTALION:
		return _view.get_battalion_snapshot(_selected_entity_id)
	if _selected_entity_kind == CoreV2Types.EntityKind.BRIGADE_HQ or _selected_entity_kind == CoreV2Types.EntityKind.ARMY_HQ:
		return _view.get_hq_snapshot(_selected_entity_id)
	return {}


func _get_selected_order_brigade_id(selected_unit: Dictionary) -> String:
	if selected_unit.is_empty() or not bool(selected_unit.get("is_friendly", false)):
		return ""
	var entity_kind: int = int(selected_unit.get("entity_kind", _selected_entity_kind))
	if entity_kind == CoreV2Types.EntityKind.BATTALION or entity_kind == CoreV2Types.EntityKind.BRIGADE_HQ:
		return String(selected_unit.get("brigade_id", ""))
	return ""


func _build_selected_order_command(selected_unit: Dictionary, ground_point: Vector3) -> Dictionary:
	if selected_unit.is_empty() or not bool(selected_unit.get("is_friendly", false)):
		return {}
	var entity_kind: int = int(selected_unit.get("entity_kind", _selected_entity_kind))
	if entity_kind == CoreV2Types.EntityKind.BATTALION:
		return {
			"command_type": CoreV2Types.CommandType.ISSUE_BATTALION_ORDER,
			"battalion_id": String(selected_unit.get("id", _selected_entity_id)),
			"order_type": _pending_order_type,
			"target_position": ground_point,
			"policies": _pending_policies.duplicate(true),
		}
	var selected_brigade_id: String = _get_selected_order_brigade_id(selected_unit)
	if selected_brigade_id.is_empty():
		return {}
	return {
		"command_type": CoreV2Types.CommandType.ISSUE_BRIGADE_ORDER,
		"brigade_id": selected_brigade_id,
		"order_type": _pending_order_type,
		"target_position": ground_point,
		"policies": _pending_policies.duplicate(true),
	}


func _on_snapshot_updated(snapshot: Dictionary) -> void:
	_latest_snapshot = snapshot
	_view.apply_snapshot(snapshot)
	if not _camera_configured:
		var map_rect: Rect2 = snapshot.get("channels", {}).get("static_world", {}).get("map_rect", Rect2(-5000.0, -5000.0, 10000.0, 10000.0))
		_camera_rig.configure(map_rect)
		_camera_configured = true
	if int(snapshot.get("phase", CoreV2Types.BattlePhase.DEPLOYMENT)) == CoreV2Types.BattlePhase.DEPLOYMENT:
		_pending_order_type = CoreV2Types.OrderType.NONE
	if _selected_entity_id != &"" and _get_selected_unit_snapshot().is_empty():
		_selected_entity_id = &""
		_selected_entity_kind = CoreV2Types.EntityKind.NONE
		_selected_battalion_id = &""
		_selected_brigade_id = &""
	if _selected_entity_id == &"":
		_select_first_friendly_battalion()
	_refresh_views()


func _on_deployment_action_requested(command_type: int) -> void:
	_pending_placement_command = command_type
	_pending_order_type = CoreV2Types.OrderType.NONE
	_refresh_views()


func _on_start_battle_requested() -> void:
	_pending_placement_command = -1
	_client.submit_ui_command({
		"command_type": CoreV2Types.CommandType.START_BATTLE,
	})


func _on_order_type_selected(order_type: int) -> void:
	if int(_latest_snapshot.get("phase", CoreV2Types.BattlePhase.DEPLOYMENT)) != CoreV2Types.BattlePhase.ACTIVE:
		return
	_pending_placement_command = -1
	_pending_order_type = order_type
	_refresh_views()


func _on_order_cancelled() -> void:
	_pending_order_type = CoreV2Types.OrderType.NONE
	_pending_placement_command = -1
	_refresh_views()


func _on_policies_changed(policies: Dictionary) -> void:
	_pending_policies = policies.duplicate(true)
	_refresh_views()


func _on_debug_formation_requested(formation_state: int) -> void:
	if _selected_battalion_id == &"":
		return
	_client.submit_ui_command({
		"command_type": CoreV2Types.CommandType.DEBUG_FORCE_FORMATION,
		"battalion_id": String(_selected_battalion_id),
		"formation_state": formation_state,
	})


func _refresh_views() -> void:
	_view.set_selected_battalion(_selected_battalion_id, _selected_brigade_id)
	var performance_stats: Dictionary = _view.get_performance_stats()
	performance_stats["fps"] = Engine.get_frames_per_second()
	_hud.set_snapshot(
		_latest_snapshot,
		_get_selected_unit_snapshot(),
		_pending_order_type,
		_pending_placement_command,
		_pending_policies,
		performance_stats
	)


func _select_first_friendly_battalion() -> void:
	for battalion_value in _latest_snapshot.get("channels", {}).get("units", {}).get("battalions", []):
		var battalion_snapshot: Dictionary = battalion_value
		if not bool(battalion_snapshot.get("is_friendly", false)):
			continue
		_select_unit(StringName(battalion_snapshot.get("id", "")), CoreV2Types.EntityKind.BATTALION)
		return


func _resolve_selected_brigade_id(entity_id: StringName, entity_kind: int) -> StringName:
	if entity_kind == CoreV2Types.EntityKind.BATTALION:
		var battalion_snapshot: Dictionary = _view.get_battalion_snapshot(entity_id)
		return StringName(battalion_snapshot.get("brigade_id", ""))
	if entity_kind == CoreV2Types.EntityKind.BRIGADE_HQ:
		var hq_snapshot: Dictionary = _view.get_hq_snapshot(entity_id)
		return StringName(hq_snapshot.get("brigade_id", ""))
	return &""
