class_name FogOfWarOverlay
extends Node2D

var map_rect: Rect2 = Rect2(0.0, 0.0, 1600.0, 900.0)
var vision_sources: Array = []
var visibility_cells: Array = []
var cell_size: float = 48.0
var _last_fog_stamp: float = -1.0
var _last_draw_ms: float = 0.0
var _last_visible_cells: int = 0


func update_from_snapshot(snapshot: Dictionary) -> void:
	map_rect = snapshot.get("map_rect", map_rect)
	vision_sources = snapshot.get("vision_sources", [])
	var fog_stamp: float = float(snapshot.get("fog_stamp", -1.0))
	var new_cell_size: float = float(snapshot.get("fog_cell_size", cell_size))
	if fog_stamp != _last_fog_stamp or absf(new_cell_size - cell_size) > 0.001:
		_last_fog_stamp = fog_stamp
		visibility_cells = snapshot.get("visibility_cells", [])
		cell_size = new_cell_size
		queue_redraw()


func _draw() -> void:
	_last_visible_cells = 0
	_last_draw_ms = 0.0


func get_performance_stats() -> Dictionary:
	return {
		"draw_ms": _last_draw_ms,
		"visible_cells": _last_visible_cells,
	}
