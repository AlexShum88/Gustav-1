class_name CoreV2ClientBridge
extends Node


signal snapshot_updated(snapshot: Dictionary)
signal command_acknowledged(ack: Dictionary)

var _server: CoreV2Server
var _player_army_id: StringName = &"blue"
var _latest_snapshot: Dictionary = {}


func connect_to_server(server: CoreV2Server, player_army_id: StringName) -> void:
	_server = server
	_player_army_id = player_army_id
	if _server != null and not _server.snapshot_ready.is_connected(_on_server_snapshot_ready):
		_server.snapshot_ready.connect(_on_server_snapshot_ready)
	if _server != null and not _server.command_acknowledged.is_connected(_on_server_command_acknowledged):
		_server.command_acknowledged.connect(_on_server_command_acknowledged)


func submit_ui_command(command: Dictionary) -> void:
	if _server == null:
		return
	var payload: Dictionary = command.duplicate(true)
	payload["army_id"] = String(_player_army_id)
	_server.submit_client_command(payload)


func get_latest_snapshot() -> Dictionary:
	return _latest_snapshot


func _on_server_snapshot_ready(snapshot: Dictionary) -> void:
	_merge_snapshot(snapshot)
	emit_signal("snapshot_updated", _latest_snapshot)


func _on_server_command_acknowledged(ack: Dictionary) -> void:
	emit_signal("command_acknowledged", ack)


func _merge_snapshot(snapshot: Dictionary) -> void:
	var merged: Dictionary = _latest_snapshot.duplicate(true)
	for key_value in snapshot.keys():
		var key: String = String(key_value)
		if key == "channels":
			continue
		merged[key] = snapshot[key]
	var merged_channels: Dictionary = merged.get("channels", {})
	var patch_channels: Dictionary = snapshot.get("channels", {})
	for channel_key_value in patch_channels.keys():
		var channel_key: String = String(channel_key_value)
		merged_channels[channel_key] = patch_channels[channel_key_value]
	merged["channels"] = merged_channels
	_latest_snapshot = merged
