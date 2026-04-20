class_name CoreV2CommandValidator
extends RefCounted


static func validate(state: CoreV2BattleState, command: Dictionary) -> Dictionary:
	if state == null:
		return _reject("missing_state")
	var command_type: int = int(command.get("command_type", -1))
	if command_type < 0:
		return _reject("missing_command_type")
	var army_id: StringName = StringName(command.get("army_id", ""))
	if army_id == &"" or state.get_army(army_id) == null:
		return _reject("invalid_army")
	match command_type:
		CoreV2Types.CommandType.PLACE_BAGGAGE, CoreV2Types.CommandType.PLACE_COMMANDER:
			return _validate_deployment_position(state, command)
		CoreV2Types.CommandType.ISSUE_BRIGADE_ORDER:
			return _validate_brigade_order(state, army_id, command)
		CoreV2Types.CommandType.ISSUE_BATTALION_ORDER:
			return _validate_battalion_order(state, army_id, command)
		CoreV2Types.CommandType.START_BATTLE:
			return _accept()
		CoreV2Types.CommandType.DEBUG_FORCE_FORMATION:
			return _accept()
		_:
			return _reject("unknown_command")


static func _validate_deployment_position(state: CoreV2BattleState, command: Dictionary) -> Dictionary:
	if state.phase != CoreV2Types.BattlePhase.DEPLOYMENT:
		return _reject("battle_already_started")
	if not command.has("position") or not (command.get("position") is Vector3):
		return _reject("missing_position")
	return _accept()


static func _validate_brigade_order(state: CoreV2BattleState, army_id: StringName, command: Dictionary) -> Dictionary:
	if state.phase != CoreV2Types.BattlePhase.ACTIVE:
		return _reject("battle_not_active")
	var army: CoreV2Army = state.get_army(army_id)
	var brigade: CoreV2Brigade = army.get_brigade(StringName(command.get("brigade_id", ""))) if army != null else null
	if brigade == null:
		return _reject("invalid_brigade")
	if not command.has("target_position") or not (command.get("target_position") is Vector3):
		return _reject("missing_target_position")
	return _accept()


static func _validate_battalion_order(state: CoreV2BattleState, army_id: StringName, command: Dictionary) -> Dictionary:
	if state.phase != CoreV2Types.BattlePhase.ACTIVE:
		return _reject("battle_not_active")
	var battalion: CoreV2Battalion = state.get_battalion(StringName(command.get("battalion_id", "")))
	if battalion == null or battalion.army_id != army_id:
		return _reject("invalid_battalion")
	if not command.has("target_position") or not (command.get("target_position") is Vector3):
		return _reject("missing_target_position")
	return _accept()


static func _accept() -> Dictionary:
	return {"accepted": true, "reason": ""}


static func _reject(reason: String) -> Dictionary:
	return {"accepted": false, "reason": reason}
