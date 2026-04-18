class_name FormationDemo
extends Node2D

const RegimentController = preload("res://src/archive/legacy_formations_demo/regiment_controller.gd")
const CompanyController = preload("res://src/archive/legacy_formations_demo/company_controller.gd")

var _regiment: RegimentController
var _ui_layer: CanvasLayer
var _status_label: Label
var _hint_label: Label
var _apply_scope_all: bool = false


func _ready() -> void:
	_regiment = RegimentController.new()
	_regiment.position = Vector2(760.0, 430.0)
	add_child(_regiment)
	_regiment.build_demo_regiment()
	_regiment.selection_changed.connect(_on_selection_changed)
	_build_ui()
	_update_status()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, Vector2(1600.0, 900.0)), Color(0.58, 0.61, 0.52), true)
	_draw_grid(1600, 900, 80.0, Color(0.0, 0.0, 0.0, 0.05))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if _regiment.select_company_at(event.position):
			_update_status()
			return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_TAB:
				_regiment.cycle_selection(1)
			KEY_1:
				_apply_mode(CompanyController.FormationMode.BATTLE)
			KEY_2:
				_apply_mode(CompanyController.FormationMode.PROTECTED)
			KEY_3:
				_apply_mode(CompanyController.FormationMode.FIRING_CYCLE)
			KEY_4:
				_apply_mode(CompanyController.FormationMode.COUNTERMARCH)
			KEY_5:
				_apply_mode(CompanyController.FormationMode.CARACOLE)
			KEY_M:
				_apply_mode(CompanyController.FormationMode.MARCH)
			KEY_I:
				_apply_mode(CompanyController.FormationMode.BATTLE)
			KEY_R:
				_regiment.reset_all()
			KEY_SPACE:
				_apply_mode(CompanyController.FormationMode.FIRING_CYCLE)
			KEY_UP:
				_set_direction(Vector2.UP)
			KEY_DOWN:
				_set_direction(Vector2.DOWN)
			KEY_LEFT:
				_set_direction(Vector2.LEFT)
			KEY_RIGHT:
				_set_direction(Vector2.RIGHT)
			KEY_Q:
				_set_direction(Vector2(-1.0, -1.0))
			KEY_E:
				_set_direction(Vector2(1.0, -1.0))
			KEY_Z:
				_set_direction(Vector2(-1.0, 1.0))
			KEY_C:
				_set_direction(Vector2(1.0, 1.0))
		_update_status()


func _build_ui() -> void:
	_ui_layer = CanvasLayer.new()
	add_child(_ui_layer)

	var panel: PanelContainer = PanelContainer.new()
	panel.position = Vector2(18.0, 18.0)
	panel.size = Vector2(620.0, 340.0)
	_ui_layer.add_child(panel)

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)

	var root: VBoxContainer = VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	margin.add_child(root)

	var title: Label = Label.new()
	title.text = "Formation Demo"
	root.add_child(title)

	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_status_label)

	var scope_row: HBoxContainer = HBoxContainer.new()
	root.add_child(scope_row)
	var selected_button: Button = Button.new()
	selected_button.text = "Selected Company"
	selected_button.pressed.connect(func() -> void:
		_apply_scope_all = false
		_update_status()
	)
	scope_row.add_child(selected_button)
	var regiment_button: Button = Button.new()
	regiment_button.text = "Whole Regiment"
	regiment_button.pressed.connect(func() -> void:
		_apply_scope_all = true
		_update_status()
	)
	scope_row.add_child(regiment_button)

	var row_one: HBoxContainer = HBoxContainer.new()
	root.add_child(row_one)
	_add_action_button(row_one, "Battle [1/I]", func() -> void:
		_apply_mode(CompanyController.FormationMode.BATTLE)
	)
	_add_action_button(row_one, "Protected [2]", func() -> void:
		_apply_mode(CompanyController.FormationMode.PROTECTED)
	)
	_add_action_button(row_one, "Firing [3/Space]", func() -> void:
		_apply_mode(CompanyController.FormationMode.FIRING_CYCLE)
	)

	var row_two: HBoxContainer = HBoxContainer.new()
	root.add_child(row_two)
	_add_action_button(row_two, "Musketeer Line [4]", func() -> void:
		_apply_mode(CompanyController.FormationMode.COUNTERMARCH)
	)
	_add_action_button(row_two, "Caracole [5]", func() -> void:
		_apply_mode(CompanyController.FormationMode.CARACOLE)
	)
	_add_action_button(row_two, "March [M]", func() -> void:
		_apply_mode(CompanyController.FormationMode.MARCH)
	)

	var row_three: HBoxContainer = HBoxContainer.new()
	root.add_child(row_three)
	_add_action_button(row_three, "Reset [R]", func() -> void:
		_regiment.reset_all()
		_update_status()
	)

	_hint_label = Label.new()
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_label.text = "LMB: select company | Tab: next company | Arrows/Q/E/Z/C: direction\n1 Battle | 2 Protected | 3 Firing | 4 Musketeer Line | 5 Caracole | M March | R Reset"
	root.add_child(_hint_label)


func _add_action_button(container: HBoxContainer, text: String, callback: Callable) -> void:
	var button: Button = Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(132.0, 32.0)
	button.pressed.connect(callback)
	container.add_child(button)


func _apply_mode(mode: int) -> void:
	if _apply_scope_all:
		_regiment.apply_mode_to_all(mode)
	else:
		_regiment.apply_mode_to_selected(mode)
	_update_status()


func _set_direction(direction: Vector2) -> void:
	_regiment.set_direction(direction)
	_update_status()


func _on_selection_changed(_company) -> void:
	_update_status()


func _update_status() -> void:
	if _status_label == null:
		return
	var direction_name: String = _direction_to_text(_regiment.current_direction)
	var scope_text: String = "Whole regiment" if _apply_scope_all else "Selected company"
	_status_label.text = "Selected: %s\nMode: %s\nDirection: %s\nScope: %s" % [
		_regiment.get_selected_company_name(),
		_regiment.get_selected_company_mode_name(),
		direction_name,
		scope_text,
	]


func _direction_to_text(direction: Vector2) -> String:
	var dir: Vector2 = direction.normalized()
	if dir == Vector2.RIGHT:
		return "East"
	if dir == Vector2.LEFT:
		return "West"
	if dir == Vector2.UP:
		return "North"
	if dir == Vector2.DOWN:
		return "South"
	if dir.x > 0.0 and dir.y < 0.0:
		return "North-East"
	if dir.x < 0.0 and dir.y < 0.0:
		return "North-West"
	if dir.x > 0.0 and dir.y > 0.0:
		return "South-East"
	return "South-West"


func _draw_grid(width: int, height: int, step: float, color: Color) -> void:
	var x: float = 0.0
	while x <= float(width):
		draw_line(Vector2(x, 0.0), Vector2(x, float(height)), color, 1.0)
		x += step
	var y: float = 0.0
	while y <= float(height):
		draw_line(Vector2(0.0, y), Vector2(float(width), y), color, 1.0)
		y += step
