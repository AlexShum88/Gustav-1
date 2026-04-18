class_name FormationModule
extends Node2D

@export var visual_size: Vector2 = Vector2(26.0, 18.0)
@export var fallback_color: Color = Color(0.82, 0.82, 0.82, 1.0)

var module_id: StringName = &""
var module_type: StringName = &"musketeers"
var tactical_group: StringName = &""
var sprite_texture: Texture2D
var jitter_offset: Vector2 = Vector2.ZERO
var target_local_position: Vector2 = Vector2.ZERO
var target_rotation_radians: float = 0.0
var is_highlighted: bool = false
var is_firing_active: bool = false
var visual_offset: Vector2 = Vector2.ZERO

var _move_tween: Tween
var _recoil_tween: Tween


func configure(
		new_module_id: StringName,
		new_module_type: StringName,
		new_tactical_group: StringName,
		new_texture: Texture2D,
		new_visual_size: Vector2,
		new_jitter: Vector2
) -> void:
	module_id = new_module_id
	module_type = new_module_type
	tactical_group = new_tactical_group
	sprite_texture = new_texture
	visual_size = new_visual_size
	jitter_offset = new_jitter
	queue_redraw()


func move_to_slot(local_position: Vector2, facing_angle: float, duration: float) -> void:
	target_local_position = local_position
	target_rotation_radians = facing_angle
	if _move_tween != null and _move_tween.is_running():
		_move_tween.kill()
	_move_tween = create_tween()
	_move_tween.set_parallel(true)
	_move_tween.set_trans(Tween.TRANS_SINE)
	_move_tween.set_ease(Tween.EASE_IN_OUT)
	_move_tween.tween_property(self, "position", target_local_position, max(duration, 0.01))
	_move_tween.tween_property(self, "rotation", target_rotation_radians, max(duration, 0.01))


func snap_to_slot(local_position: Vector2, facing_angle: float) -> void:
	target_local_position = local_position
	target_rotation_radians = facing_angle
	position = target_local_position
	rotation = target_rotation_radians


func set_highlighted(value: bool) -> void:
	if is_highlighted == value:
		return
	is_highlighted = value
	queue_redraw()


func set_firing_active(value: bool) -> void:
	if is_firing_active == value:
		return
	is_firing_active = value
	queue_redraw()


func trigger_recoil(offset: Vector2, duration: float) -> void:
	if _recoil_tween != null and _recoil_tween.is_running():
		_recoil_tween.kill()
	visual_offset = Vector2.ZERO
	_recoil_tween = create_tween()
	_recoil_tween.set_trans(Tween.TRANS_SINE)
	_recoil_tween.set_ease(Tween.EASE_OUT)
	_recoil_tween.tween_property(self, "visual_offset", offset, max(duration * 0.25, 0.04))
	_recoil_tween.tween_property(self, "visual_offset", Vector2.ZERO, max(duration * 0.5, 0.08))
	_recoil_tween.finished.connect(queue_redraw)


func _process(_delta: float) -> void:
	z_index = int(global_position.y)
	if visual_offset.length_squared() > 0.001:
		queue_redraw()


func _draw() -> void:
	var rect: Rect2 = Rect2(-visual_size * 0.5 + visual_offset, visual_size)
	if sprite_texture != null:
		draw_texture_rect(sprite_texture, rect, false)
	else:
		draw_rect(rect, fallback_color, true)
		draw_rect(rect, Color.BLACK, false, 2.0)
	if is_highlighted:
		draw_rect(rect.grow(2.0), Color(1.0, 1.0, 1.0, 0.9), false, 2.0)
	if is_firing_active:
		var flash_center: Vector2 = Vector2(0.0, -visual_size.y * 0.55)
		draw_circle(flash_center, 5.0, Color(1.0, 0.92, 0.62, 0.95))
		draw_circle(flash_center, 2.4, Color(1.0, 1.0, 1.0, 0.95))
