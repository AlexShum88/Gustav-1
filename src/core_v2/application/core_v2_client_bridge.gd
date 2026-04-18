class_name CoreV2ClientBridge
extends Node


signal snapshot_updated(snapshot: Dictionary)

var _server: CoreV2Server
var _player_army_id: StringName = &"blue"
var _latest_snapshot: Dictionary = {}


func connect_to_server(server: CoreV2Server, player_army_id: StringName) -> void:
	_server = server
	_player_army_id = player_army_id
	if _server != null and not _server.snapshot_ready.is_connected(_on_server_snapshot_ready):
		_server.snapshot_ready.connect(_on_server_snapshot_ready)


func submit_ui_command(command: Dictionary) -> void:
	if _server == null:
		return
	var payload: Dictionary = command.duplicate(true)
	payload["army_id"] = String(_player_army_id)
	_server.submit_client_command(payload)


func get_latest_snapshot() -> Dictionary:
	return _latest_snapshot


func _on_server_snapshot_ready(snapshot: Dictionary) -> void:
	_latest_snapshot = snapshot
	emit_signal("snapshot_updated", snapshot)
