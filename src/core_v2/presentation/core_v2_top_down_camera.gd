class_name CoreV2TopDownCamera
extends Node3D


var _camera: Camera3D
var _map_rect: Rect2 = Rect2(-5000.0, -5000.0, 10000.0, 10000.0)
var _pan_speed: float = 1800.0
var _zoom_value: float = 0.45
var _zoom_step: float = 0.08
var _zoom_min: float = 0.0
var _zoom_max: float = 1.0
var _min_height: float = 450.0
var _max_height: float = 3600.0
var _pitch_degrees: float = -72.0


func _ready() -> void:
	_camera = Camera3D.new()
	_camera.name = "BattleCamera3D"
	_camera.current = true
	_camera.far = 30000.0
	add_child(_camera)
	_apply_camera_transform()


func configure(map_rect: Rect2) -> void:
	_map_rect = map_rect
	position = Vector3(_map_rect.get_center().x, 0.0, _map_rect.get_center().y)
	_clamp_to_map()
	_apply_camera_transform()


func get_camera() -> Camera3D:
	return _camera


func screen_to_ground(screen_position: Vector2) -> Variant:
	if _camera == null:
		return null
	var ray_origin: Vector3 = _camera.project_ray_origin(screen_position)
	var ray_normal: Vector3 = _camera.project_ray_normal(screen_position)
	var physics_hit: Variant = _screen_ray_to_physics_ground(ray_origin, ray_normal)
	if physics_hit != null:
		return physics_hit
	# Fallback потрібний на перших кадрах, поки heightfield collision ще не створений.
	if absf(ray_normal.y) <= 0.0001:
		return null
	var distance: float = -ray_origin.y / ray_normal.y
	if distance < 0.0:
		return null
	return ray_origin + ray_normal * distance


func _screen_ray_to_physics_ground(ray_origin: Vector3, ray_normal: Vector3) -> Variant:
	var world: World3D = get_world_3d()
	if world == null:
		return null
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_normal * _camera.far)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var hit: Dictionary = world.direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return null
	return hit.get("position", null)


func _process(delta: float) -> void:
	var move_input := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		move_input.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		move_input.y += 1.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		move_input.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		move_input.x += 1.0
	if move_input.length_squared() <= 0.0001:
		return
	var zoom_multiplier: float = 0.6 + _zoom_value * 1.2
	var delta_position: Vector3 = Vector3(move_input.x, 0.0, move_input.y).normalized() * _pan_speed * zoom_multiplier * delta
	position += delta_position
	_clamp_to_map()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mouse_event: InputEventMouseButton = event
	if not mouse_event.pressed:
		return
	if mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP:
		_set_zoom(_zoom_value - _zoom_step)
	elif mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_set_zoom(_zoom_value + _zoom_step)


func _set_zoom(next_zoom: float) -> void:
	_zoom_value = clamp(next_zoom, _zoom_min, _zoom_max)
	_apply_camera_transform()


func _apply_camera_transform() -> void:
	if _camera == null:
		return
	var height: float = lerp(_min_height, _max_height, _zoom_value)
	_camera.position = Vector3(0.0, height, height * 0.28)
	_camera.rotation_degrees = Vector3(_pitch_degrees, 0.0, 0.0)


func _clamp_to_map() -> void:
	position.x = clamp(position.x, _map_rect.position.x, _map_rect.end.x)
	position.z = clamp(position.z, _map_rect.position.y, _map_rect.end.y)
