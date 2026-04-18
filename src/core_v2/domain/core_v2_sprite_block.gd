class_name CoreV2SpriteBlock
extends RefCounted


const DEFAULT_SOLDIERS_PER_BLOCK: int = 50


var id: StringName = &""
var battalion_id: StringName = &""
var army_id: StringName = &""
var index: int = 0
var role: String = "mixed"
var local_offset: Vector3 = Vector3.ZERO
var world_position: Vector3 = Vector3.ZERO
var soldiers: int = DEFAULT_SOLDIERS_PER_BLOCK
var damage_carry: float = 0.0
var combat_cooldown_seconds: float = 0.0
var combat_reload_seconds: float = 0.0
var combat_sequence: int = 0
var target_battalion_id: StringName = &""
var target_sprite_index: int = -1
var target_world_position: Vector3 = Vector3.ZERO
var last_attack_kind: String = ""
var last_line_of_fire_density: float = 0.0


static func create(new_battalion_id: StringName, new_army_id: StringName, new_index: int, new_role: String, soldiers_in_block: int) -> CoreV2SpriteBlock:
	var block := CoreV2SpriteBlock.new()
	block.battalion_id = new_battalion_id
	block.army_id = new_army_id
	block.index = new_index
	block.id = StringName("%s:%d" % [String(new_battalion_id), new_index])
	block.role = new_role
	block.soldiers = max(0, soldiers_in_block)
	return block


func sync_from_battalion(new_army_id: StringName, new_battalion_id: StringName, new_index: int, new_role: String, new_local_offset: Vector3, new_world_position: Vector3) -> void:
	army_id = new_army_id
	battalion_id = new_battalion_id
	index = new_index
	id = StringName("%s:%d" % [String(new_battalion_id), new_index])
	role = new_role
	local_offset = new_local_offset
	world_position = new_world_position
	if target_sprite_index == index and target_battalion_id == battalion_id:
		clear_target()


func advance_cooldown(delta: float) -> void:
	combat_cooldown_seconds = max(0.0, combat_cooldown_seconds - delta)


func can_attack() -> bool:
	return soldiers > 0 and combat_cooldown_seconds <= 0.0


func set_target(target_battalion: StringName, target_index: int, target_position: Vector3, attack_kind: String, reload_seconds: float, smoke_density: float) -> void:
	combat_sequence += 1
	target_battalion_id = target_battalion
	target_sprite_index = target_index
	target_world_position = target_position
	last_attack_kind = attack_kind
	combat_reload_seconds = reload_seconds
	combat_cooldown_seconds = reload_seconds
	last_line_of_fire_density = smoke_density


func clear_target() -> void:
	target_battalion_id = &""
	target_sprite_index = -1
	target_world_position = Vector3.ZERO
	last_attack_kind = ""
	last_line_of_fire_density = 0.0
