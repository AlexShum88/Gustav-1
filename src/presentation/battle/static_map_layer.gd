class_name StaticMapLayer
extends Node2D

var map_rect: Rect2 = Rect2(0.0, 0.0, 1600.0, 900.0)
var terrain_regions: Array = []
var _map_texture: ImageTexture


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func update_static_data(new_map_rect: Rect2, new_terrain_regions: Array) -> void:
	var requires_rebuild: bool = new_map_rect != map_rect or terrain_regions.size() != new_terrain_regions.size()
	map_rect = new_map_rect
	if requires_rebuild or terrain_regions.is_empty():
		terrain_regions = new_terrain_regions.duplicate(true)
		_rebuild_texture()
		queue_redraw()


func _draw() -> void:
	if _map_texture == null:
		return
	draw_texture_rect(_map_texture, map_rect, false)


func _rebuild_texture() -> void:
	var width: int = max(1, int(map_rect.size.x))
	var height: int = max(1, int(map_rect.size.y))
	var image: Image = Image.create(width, height, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.64, 0.61, 0.47, 1.0))
	for region in terrain_regions:
		_fill_polygon(image, region.get("polygon", PackedVector2Array()), _terrain_color(int(region.get("terrain_type", SimTypes.TerrainType.PLAINS))))
		if region.get("has_road", false):
			_draw_polyline(image, region.get("polygon", PackedVector2Array()), Color(0.4, 0.29, 0.16, 0.8), 5)
	_map_texture = ImageTexture.create_from_image(image)


func _fill_polygon(image: Image, polygon: PackedVector2Array, color: Color) -> void:
	if polygon.size() < 3:
		return
	var bounds: Rect2 = _polygon_bounds(polygon)
	var start_x: int = clamp(int(floor(bounds.position.x - map_rect.position.x)), 0, image.get_width() - 1)
	var end_x: int = clamp(int(ceil(bounds.end.x - map_rect.position.x)), 0, image.get_width() - 1)
	var start_y: int = clamp(int(floor(bounds.position.y - map_rect.position.y)), 0, image.get_height() - 1)
	var end_y: int = clamp(int(ceil(bounds.end.y - map_rect.position.y)), 0, image.get_height() - 1)
	for y in range(start_y, end_y + 1):
		for x in range(start_x, end_x + 1):
			var sample: Vector2 = map_rect.position + Vector2(x + 0.5, y + 0.5)
			if Geometry2D.is_point_in_polygon(sample, polygon):
				image.set_pixel(x, y, color)


func _draw_polyline(image: Image, polygon: PackedVector2Array, color: Color, thickness: int) -> void:
	if polygon.size() < 2:
		return
	for index in range(polygon.size()):
		var from_point: Vector2 = polygon[index]
		var to_point: Vector2 = polygon[(index + 1) % polygon.size()]
		_draw_line_segment(image, from_point, to_point, color, thickness)


func _draw_line_segment(image: Image, from_point: Vector2, to_point: Vector2, color: Color, thickness: int) -> void:
	var distance: float = from_point.distance_to(to_point)
	var steps: int = max(1, int(distance))
	for step_index in range(steps + 1):
		var t: float = float(step_index) / float(steps)
		var sample: Vector2 = from_point.lerp(to_point, t) - map_rect.position
		for offset_y in range(-thickness, thickness + 1):
			for offset_x in range(-thickness, thickness + 1):
				var px: int = int(round(sample.x)) + offset_x
				var py: int = int(round(sample.y)) + offset_y
				if px < 0 or py < 0 or px >= image.get_width() or py >= image.get_height():
					continue
				if Vector2(offset_x, offset_y).length() <= float(thickness):
					image.set_pixel(px, py, color)


func _polygon_bounds(polygon: PackedVector2Array) -> Rect2:
	var min_x: float = INF
	var min_y: float = INF
	var max_x: float = -INF
	var max_y: float = -INF
	for point in polygon:
		min_x = min(min_x, point.x)
		min_y = min(min_y, point.y)
		max_x = max(max_x, point.x)
		max_y = max(max_y, point.y)
	return Rect2(Vector2(min_x, min_y), Vector2(max_x - min_x, max_y - min_y))


func _terrain_color(terrain_type: int) -> Color:
	match terrain_type:
		SimTypes.TerrainType.FOREST:
			return Color(0.23, 0.4, 0.22, 0.92)
		SimTypes.TerrainType.BUSHES:
			return Color(0.44, 0.52, 0.29, 0.9)
		SimTypes.TerrainType.SWAMP:
			return Color(0.3, 0.43, 0.38, 0.9)
		SimTypes.TerrainType.VILLAGE:
			return Color(0.58, 0.49, 0.36, 0.92)
		SimTypes.TerrainType.FARM:
			return Color(0.69, 0.64, 0.38, 0.85)
		_:
			return Color(0.65, 0.63, 0.49, 0.95)
