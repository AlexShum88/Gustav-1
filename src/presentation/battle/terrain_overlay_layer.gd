class_name TerrainOverlayLayer
extends Node2D

var terrain_regions: Array = []


func update_regions(new_terrain_regions: Array) -> void:
	terrain_regions = new_terrain_regions.duplicate(true)
	queue_redraw()


func _draw() -> void:
	for region in terrain_regions:
		var polygon: PackedVector2Array = region.get("polygon", PackedVector2Array())
		if polygon.is_empty():
			continue
		draw_colored_polygon(polygon, _terrain_color(int(region.get("terrain_type", SimTypes.TerrainType.PLAINS))))
		var closed_polygon: PackedVector2Array = PackedVector2Array(polygon)
		closed_polygon.append(polygon[0])
		draw_polyline(closed_polygon, Color(0.16, 0.13, 0.09, 0.38), 1.8)
		if region.get("has_road", false):
			draw_polyline(closed_polygon, Color(0.4, 0.29, 0.16, 0.7), 4.0)


func _terrain_color(terrain_type: int) -> Color:
	match terrain_type:
		SimTypes.TerrainType.FOREST:
			return Color(0.23, 0.4, 0.22, 0.78)
		SimTypes.TerrainType.BUSHES:
			return Color(0.44, 0.52, 0.29, 0.76)
		SimTypes.TerrainType.SWAMP:
			return Color(0.3, 0.43, 0.38, 0.76)
		SimTypes.TerrainType.VILLAGE:
			return Color(0.58, 0.49, 0.36, 0.82)
		SimTypes.TerrainType.FARM:
			return Color(0.69, 0.64, 0.38, 0.68)
		_:
			return Color(0.0, 0.0, 0.0, 0.0)

