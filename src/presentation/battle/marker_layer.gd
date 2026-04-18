class_name MarkerLayer
extends Node2D

const HQ_TEXTURE: Texture2D = preload("res://assets/sprites/hq.png")
const CONVOY_TEXTURE: Texture2D = preload("res://assets/sprites/convoy.png")

var snapshot: Dictionary = {}
var _world_view_rect: Rect2 = Rect2(-100000.0, -100000.0, 200000.0, 200000.0)
var _last_draw_ms: float = 0.0


func update_from_snapshot(new_snapshot: Dictionary) -> void:
	snapshot = new_snapshot
	queue_redraw()


func set_world_view_rect(value: Rect2) -> void:
	_world_view_rect = value
	queue_redraw()


func _draw() -> void:
	var draw_start_us: int = Time.get_ticks_usec()
	_draw_convoys()
	_draw_messengers()
	_draw_hqs()
	_draw_last_seen_markers()
	_last_draw_ms = float(Time.get_ticks_usec() - draw_start_us) / 1000.0


func get_performance_stats() -> Dictionary:
	return {
		"draw_ms": _last_draw_ms,
	}

func _draw_hqs() -> void:
	var visible_rect: Rect2 = _world_view_rect.grow(48.0)
	for hq_data in snapshot.get("hqs", []):
		var world_position: Vector2 = hq_data.get("position", Vector2.ZERO)
		if not visible_rect.has_point(world_position):
			continue
		_draw_centered_texture(HQ_TEXTURE, world_position, Vector2(28.0, 28.0))


func _draw_convoys() -> void:
	var visible_rect: Rect2 = _world_view_rect.grow(40.0)
	for convoy_data in snapshot.get("convoys", []):
		var world_position: Vector2 = convoy_data.get("position", Vector2.ZERO)
		if not visible_rect.has_point(world_position):
			continue
		_draw_centered_texture(CONVOY_TEXTURE, world_position, Vector2(26.0, 20.0))


func _draw_messengers() -> void:
	var visible_rect: Rect2 = _world_view_rect.grow(20.0)
	for messenger_data in snapshot.get("messengers", []):
		var world_position: Vector2 = messenger_data.get("position", Vector2.ZERO)
		if not visible_rect.has_point(world_position):
			continue
		var color: Color = Color(0.35, 0.63, 0.95) if messenger_data.get("is_friendly", false) else Color(0.92, 0.46, 0.38)
		draw_circle(world_position, 5.0, color)
		draw_line(world_position + Vector2(0.0, -8.0), world_position + Vector2(0.0, 8.0), color, 2.0)


func _draw_last_seen_markers() -> void:
	var visible_rect: Rect2 = _world_view_rect.grow(36.0)
	for marker in snapshot.get("last_seen_markers", []):
		var world_position: Vector2 = marker.get("position", Vector2.ZERO)
		if not visible_rect.intersects(Rect2(world_position - Vector2(24.0, 24.0), Vector2.ONE * 48.0)):
			continue
		draw_arc(world_position, 22.0, 0.0, TAU, 20, Color(1.0, 0.93, 0.62, 0.85), 2.0)
		draw_line(world_position + Vector2(-10.0, -10.0), world_position + Vector2(10.0, 10.0), Color(1.0, 0.93, 0.62, 0.85), 2.0)
		draw_line(world_position + Vector2(-10.0, 10.0), world_position + Vector2(10.0, -10.0), Color(1.0, 0.93, 0.62, 0.85), 2.0)


func _draw_centered_texture(texture: Texture2D, world_position: Vector2, target_size: Vector2) -> void:
	if texture == null:
		return
	draw_texture_rect(texture, Rect2(world_position - target_size * 0.5, target_size), false)
