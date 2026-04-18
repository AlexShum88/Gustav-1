class_name HQ
extends SimEntity

var role: String = "brigade"
var command_radius: float = 110.0
var mobility: float = 32.0
var integrity: float = 1.0
var supply_stock: float = 1.0
var ammo_stock: float = 1.0


func is_operational() -> bool:
	return not is_destroyed and integrity > 0.2
