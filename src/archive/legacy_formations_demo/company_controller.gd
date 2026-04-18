class_name CompanyController
extends Node2D

const FormationLayout = preload("res://src/archive/legacy_formations_demo/formation_layout.gd")
const FormationModule = preload("res://src/archive/legacy_formations_demo/formation_module.gd")

enum CompanyType {
	PIKE_AND_SHOT,
	CAVALRY,
	MUSKETEER_ONLY,
	ARTILLERY,
	HQ,
	WAGONS,
}

enum FormationMode {
	IDLE,
	BATTLE,
	MARCH,
	PROTECTED,
	FIRING_CYCLE,
	COUNTERMARCH,
	CARACOLE,
	LINE,
	COLUMN,
	DEPLOYED,
}

signal company_selected(company: CompanyController)
signal mode_changed(company: CompanyController, mode: int)

@export var company_name: String = "Company"
@export var company_type: CompanyType = CompanyType.PIKE_AND_SHOT
@export var company_rect_size: Vector2 = Vector2(320.0, 220.0)
@export var horizontal_spacing: float = 34.0
@export var vertical_spacing: float = 28.0
@export var transition_duration: float = 0.65
@export var fire_hold_duration: float = 1.0
@export var random_jitter_amount: float = 2.0
@export var module_visual_size: Vector2 = Vector2(30.0, 20.0)
@export var show_company_rect: bool = true

@export_group("Counts")
@export var pikemen_count: int = 8
@export var musketeer_count: int = 16
@export var cavalry_count: int = 8
@export var musketeer_only_count: int = 12
@export var artillery_gun_count: int = 4
@export var artillery_crew_count: int = 4
@export var hq_count: int = 4
@export var wagon_count: int = 4

@export_group("Textures")
@export var pikemen_texture: Texture2D = preload("res://assets/sprites/pike.png")
@export var musketeers_texture: Texture2D = preload("res://assets/sprites/musketers.png")
@export var cavalry_texture: Texture2D = preload("res://assets/sprites/kirasiers.png")
@export var cavalry_light_texture: Texture2D = preload("res://assets/sprites/light_cavalry.png")
@export var cavalry_dragoon_texture: Texture2D = preload("res://assets/sprites/dragoons.png")
@export var artillery_texture: Texture2D = preload("res://assets/sprites/field_artilery.png")
@export var artillery_light_texture: Texture2D = preload("res://assets/sprites/light_artilery.png")
@export var artillery_siege_texture: Texture2D = preload("res://assets/sprites/siege_artilery.png")
@export var hq_texture: Texture2D = preload("res://assets/sprites/hq.png")
@export var wagon_texture: Texture2D = preload("res://assets/sprites/convoy.png")

var modules: Array = []
var current_mode: FormationMode = FormationMode.BATTLE
var current_direction: Vector2 = Vector2.RIGHT
var is_selected: bool = false

var _firing_cycle_running: bool = false
var _firing_wave_modules: Array = []
var _firing_phase: StringName = &"idle"
var _current_wave_index: int = 0
var _phase_time_left: float = 0.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	if modules.is_empty():
		build_modules()
	apply_mode(FormationMode.BATTLE, current_direction, true)


func _process(delta: float) -> void:
	if not _firing_cycle_running:
		return
	_phase_time_left -= delta
	if _phase_time_left > 0.0:
		return
	match String(_firing_phase):
		"hold_and_fire":
			_set_active_wave_firing(false)
			_current_wave_index = (_current_wave_index + 1) % max(_firing_wave_modules.size(), 1)
			_apply_firing_cycle_layout()
			_firing_phase = &"rotate_ranks"
			_phase_time_left = transition_duration
		"rotate_ranks":
			_set_active_wave_firing(true)
			_firing_phase = &"hold_and_fire"
			_phase_time_left = fire_hold_duration


func _draw() -> void:
	var rect: Rect2 = _get_company_bounds()
	if show_company_rect:
		var fill: Color = Color(0.1, 0.12, 0.1, 0.08)
		var outline: Color = Color(1.0, 1.0, 1.0, 0.75) if is_selected else Color(0.8, 0.8, 0.8, 0.24)
		draw_rect(rect, fill, true)
		draw_rect(rect, outline, false, 2.0 if is_selected else 1.0)
	var font: Font = ThemeDB.fallback_font
	if font == null:
		return
	var label_position: Vector2 = rect.position + Vector2(8.0, 18.0)
	draw_string(font, label_position, "%s [%s]" % [company_name, get_mode_name(current_mode)], HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 16.0, 14, Color.WHITE)


func build_modules() -> void:
	for module in modules:
		if is_instance_valid(module):
			module.queue_free()
	modules.clear()
	match company_type:
		CompanyType.PIKE_AND_SHOT:
			_create_group_modules(&"pikemen", pikemen_count, &"core", pikemen_texture)
			var left_muskets: int = int(floor(float(musketeer_count) * 0.5))
			_create_group_modules(&"musketeers", left_muskets, &"left", musketeers_texture)
			_create_group_modules(&"musketeers", musketeer_count - left_muskets, &"right", musketeers_texture)
		CompanyType.CAVALRY:
			var front_cavalry: int = int(floor(float(cavalry_count) * 0.5))
			_create_group_modules(&"cavalry", front_cavalry, &"front", cavalry_texture)
			_create_group_modules(&"cavalry", cavalry_count - front_cavalry, &"rear", cavalry_light_texture)
		CompanyType.MUSKETEER_ONLY:
			_create_group_modules(&"musketeers", musketeer_only_count, &"main", musketeers_texture)
		CompanyType.ARTILLERY:
			_create_group_modules(&"artillery", artillery_gun_count, &"guns", artillery_texture)
			_create_group_modules(&"musketeers", artillery_crew_count, &"crew", musketeers_texture)
		CompanyType.HQ:
			_create_group_modules(&"hq", hq_count, &"staff", hq_texture)
		CompanyType.WAGONS:
			_create_group_modules(&"wagons", wagon_count, &"train", wagon_texture)
	queue_redraw()


func apply_mode(mode: FormationMode, direction: Vector2 = current_direction, immediate: bool = false) -> void:
	current_direction = _sanitize_direction(direction)
	current_mode = mode
	if not _is_cycle_mode(mode):
		stop_firing_cycle()
	var layout: FormationLayout = get_layout_for_state(mode, current_direction)
	_apply_layout(layout, immediate)
	mode_changed.emit(self, mode)
	queue_redraw()


func start_firing_cycle(direction: Vector2 = current_direction) -> void:
	start_cycle_mode(FormationMode.FIRING_CYCLE, direction)


func start_cycle_mode(mode: FormationMode, direction: Vector2 = current_direction) -> void:
	if mode == FormationMode.FIRING_CYCLE and company_type != CompanyType.PIKE_AND_SHOT and company_type != CompanyType.ARTILLERY:
		apply_mode(FormationMode.BATTLE, direction)
		return
	if mode == FormationMode.COUNTERMARCH and company_type != CompanyType.PIKE_AND_SHOT:
		apply_mode(FormationMode.BATTLE, direction)
		return
	if mode == FormationMode.CARACOLE and company_type != CompanyType.CAVALRY:
		apply_mode(FormationMode.BATTLE, direction)
		return
	current_direction = _sanitize_direction(direction)
	current_mode = mode
	_firing_cycle_running = true
	_firing_wave_modules = _build_firing_wave_modules()
	_current_wave_index = 0
	_apply_firing_cycle_layout(true)
	_set_active_wave_firing(true)
	_firing_phase = &"hold_and_fire"
	_phase_time_left = fire_hold_duration
	mode_changed.emit(self, current_mode)
	queue_redraw()


func stop_firing_cycle() -> void:
	if not _firing_cycle_running and current_mode != FormationMode.FIRING_CYCLE:
		return
	_firing_cycle_running = false
	_firing_wave_modules.clear()
	_firing_phase = &"idle"
	_current_wave_index = 0
	_phase_time_left = 0.0
	for module in modules:
		module.set_firing_active(false)
	if current_mode == FormationMode.FIRING_CYCLE:
		current_mode = FormationMode.BATTLE


func toggle_firing_cycle(direction: Vector2 = current_direction) -> void:
	toggle_cycle_mode(FormationMode.FIRING_CYCLE, direction)


func toggle_cycle_mode(mode: FormationMode, direction: Vector2 = current_direction) -> void:
	if _firing_cycle_running and current_mode == mode:
		stop_firing_cycle()
		apply_mode(FormationMode.BATTLE, direction)
		return
	start_cycle_mode(mode, direction)


func get_layout_for_state(mode: FormationMode, direction: Vector2) -> FormationLayout:
	match company_type:
		CompanyType.PIKE_AND_SHOT:
			return _get_pike_and_shot_layout(mode, direction)
		CompanyType.CAVALRY:
			return _get_cavalry_layout(mode, direction)
		CompanyType.MUSKETEER_ONLY:
			return _get_musketeer_only_layout(mode, direction)
		CompanyType.ARTILLERY:
			return _get_artillery_layout(mode, direction)
		CompanyType.HQ:
			return _get_hq_layout(mode, direction)
		CompanyType.WAGONS:
			return _get_wagon_layout(mode, direction)
	return FormationLayout.new(&"empty")


func set_selected(value: bool) -> void:
	if is_selected == value:
		return
	is_selected = value
	for module in modules:
		module.set_highlighted(value)
	queue_redraw()


func contains_global_point(world_point: Vector2) -> bool:
	return _get_company_bounds().has_point(to_local(world_point))


func get_mode_name(mode: FormationMode) -> String:
	match mode:
		FormationMode.BATTLE:
			return "Battle"
		FormationMode.MARCH:
			return "March"
		FormationMode.PROTECTED:
			return "Protected"
		FormationMode.FIRING_CYCLE:
			return "Firing Cycle"
		FormationMode.COUNTERMARCH:
			return "Musketeer Line"
		FormationMode.CARACOLE:
			return "Caracole"
		FormationMode.LINE:
			return "Line"
		FormationMode.COLUMN:
			return "Column"
		FormationMode.DEPLOYED:
			return "Deployed"
		_:
			return "Idle"


func _create_group_modules(module_type_name: StringName, count: int, group_name: StringName, texture: Texture2D) -> void:
	for index in range(count):
		var module: FormationModule = FormationModule.new()
		module.name = "%s_%s_%02d" % [company_name.to_snake_case(), String(module_type_name), index]
		module.configure(
			StringName("%s_%02d" % [String(module_type_name), index]),
			module_type_name,
			group_name,
			texture,
			module_visual_size,
			Vector2(
				_rng.randf_range(-random_jitter_amount, random_jitter_amount),
				_rng.randf_range(-random_jitter_amount, random_jitter_amount)
			)
		)
		add_child(module)
		modules.append(module)


func _apply_layout(layout: FormationLayout, immediate: bool) -> void:
	for slot in layout.slots:
		var module: FormationModule = slot.get("module")
		if module == null:
			continue
		if immediate:
			module.snap_to_slot(slot.get("local_position", Vector2.ZERO), float(slot.get("facing_angle", 0.0)))
		else:
			module.move_to_slot(slot.get("local_position", Vector2.ZERO), float(slot.get("facing_angle", 0.0)), transition_duration)


func _get_pike_and_shot_layout(mode: FormationMode, direction: Vector2) -> FormationLayout:
	match mode:
		FormationMode.MARCH:
			return _build_pike_and_shot_march_layout(direction)
		FormationMode.PROTECTED:
			return _build_pike_and_shot_protected_layout(direction)
		FormationMode.FIRING_CYCLE:
			return _build_pike_and_shot_firing_layout(direction)
		FormationMode.COUNTERMARCH:
			return _build_pike_and_shot_countermarch_layout(direction)
		_:
			return _build_pike_and_shot_battle_layout(direction)


func _get_cavalry_layout(mode: FormationMode, direction: Vector2) -> FormationLayout:
	if mode == FormationMode.CARACOLE:
		return _build_cavalry_caracole_layout(direction)
	if mode == FormationMode.MARCH or mode == FormationMode.COLUMN:
		return _build_simple_columns_layout(&"cavalry_column", _get_modules_of_type(&"cavalry"), 2, direction, horizontal_spacing * 1.05, vertical_spacing * 1.35)
	return _build_simple_line_layout(&"cavalry_line", _get_modules_of_type(&"cavalry"), 4, direction, horizontal_spacing * 1.25, vertical_spacing * 1.1)


func _get_musketeer_only_layout(mode: FormationMode, direction: Vector2) -> FormationLayout:
	var musketeers: Array = _get_modules_of_type(&"musketeers")
	if mode == FormationMode.MARCH or mode == FormationMode.COLUMN:
		return _build_simple_columns_layout(&"musketeer_column", musketeers, 2, direction, horizontal_spacing, vertical_spacing * 1.3)
	return _build_simple_line_layout(&"musketeer_line", musketeers, 4, direction, horizontal_spacing, vertical_spacing)


func _get_artillery_layout(mode: FormationMode, direction: Vector2) -> FormationLayout:
	var layout: FormationLayout = FormationLayout.new(&"artillery")
	var forward: Vector2 = _sanitize_direction(direction)
	var right: Vector2 = Vector2(-forward.y, forward.x)
	var facing_angle: float = forward.angle() + PI * 0.5
	var safe_x: float = _safe_spacing_x()
	var safe_y: float = _safe_spacing_y()
	var guns: Array = _get_modules_of_type(&"artillery")
	var crew: Array = _get_modules_of_type(&"musketeers")
	if mode == FormationMode.MARCH:
		_assign_grid(layout, guns, 1, guns.size(), Vector2.ZERO, right, forward, safe_x * 1.1, safe_y * 1.45, facing_angle)
		_assign_grid(layout, crew, 1, crew.size(), -forward * (safe_y * 1.6), right, forward, safe_x * 0.95, safe_y * 1.15, facing_angle)
	else:
		_assign_grid(layout, guns, guns.size(), 1, forward * 10.0, right, forward, safe_x * 1.4, safe_y, facing_angle)
		_assign_grid(layout, crew, 2, int(ceil(float(crew.size()) / 2.0)), -forward * (safe_y * 1.25), right, forward, safe_x, safe_y, facing_angle)
	return layout


func _get_hq_layout(_mode: FormationMode, direction: Vector2) -> FormationLayout:
	var layout: FormationLayout = FormationLayout.new(&"hq")
	var forward: Vector2 = _sanitize_direction(direction)
	var right: Vector2 = Vector2(-forward.y, forward.x)
	var facing_angle: float = forward.angle() + PI * 0.5
	var safe_x: float = _safe_spacing_x()
	var safe_y: float = _safe_spacing_y()
	var staff: Array = _get_modules_of_type(&"hq")
	_assign_grid(layout, staff, 2, int(ceil(float(staff.size()) / 2.0)), Vector2.ZERO, right, forward, safe_x * 0.95, safe_y * 0.95, facing_angle)
	return layout


func _get_wagon_layout(mode: FormationMode, direction: Vector2) -> FormationLayout:
	var wagons: Array = _get_modules_of_type(&"wagons")
	if mode == FormationMode.LINE or mode == FormationMode.BATTLE:
		return _build_simple_line_layout(&"wagon_line", wagons, wagons.size(), direction, _safe_spacing_x() * 1.4, _safe_spacing_y())
	return _build_simple_columns_layout(&"wagon_column", wagons, 1, direction, _safe_spacing_x(), _safe_spacing_y() * 1.55)


func _build_pike_and_shot_battle_layout(direction: Vector2) -> FormationLayout:
	var layout: FormationLayout = FormationLayout.new(&"pike_and_shot_battle")
	var forward: Vector2 = _sanitize_direction(direction)
	var right: Vector2 = Vector2(-forward.y, forward.x)
	var facing_angle: float = forward.angle() + PI * 0.5
	var safe_x: float = _safe_spacing_x()
	var safe_y: float = _safe_spacing_y()
	var pikes: Array = _get_modules_by_group(&"core")
	var left_muskets: Array = _get_modules_by_group(&"left")
	var right_muskets: Array = _get_modules_by_group(&"right")
	var flank_offset: float = safe_x * 2.85
	_assign_grid(layout, pikes, 2, int(ceil(float(pikes.size()) / 2.0)), Vector2.ZERO, right, forward, safe_x, safe_y, facing_angle)
	_assign_grid(layout, left_muskets, 2, int(ceil(float(left_muskets.size()) / 2.0)), -right * flank_offset, right, forward, safe_x, safe_y, facing_angle)
	_assign_grid(layout, right_muskets, 2, int(ceil(float(right_muskets.size()) / 2.0)), right * flank_offset, right, forward, safe_x, safe_y, facing_angle)
	return layout


func _build_pike_and_shot_march_layout(direction: Vector2) -> FormationLayout:
	var layout: FormationLayout = FormationLayout.new(&"pike_and_shot_march")
	var forward: Vector2 = _sanitize_direction(direction)
	var right: Vector2 = Vector2(-forward.y, forward.x)
	var facing_angle: float = forward.angle() + PI * 0.5
	var safe_x: float = _safe_spacing_x()
	var safe_y: float = _safe_spacing_y()
	var pikes: Array = _get_modules_by_group(&"core")
	var left_muskets: Array = _get_modules_by_group(&"left")
	var right_muskets: Array = _get_modules_by_group(&"right")
	# March should read as one continuous column, not three parallel blocks.
	# All groups stay on the same center line and stack one after another along
	# the movement axis.
	var pike_rows: int = int(ceil(float(pikes.size()) / 2.0))
	var musket_rows: int = int(ceil(float(left_muskets.size()) / 2.0))
	var block_gap: float = safe_y * 0.9
	var pike_center: Vector2 = Vector2.ZERO
	var front_muskets_center: Vector2 = forward * ((float(pike_rows + musket_rows) * safe_y * 0.5) + block_gap)
	var rear_muskets_center: Vector2 = -forward * ((float(pike_rows + musket_rows) * safe_y * 0.5) + block_gap)
	_assign_grid(layout, pikes, 2, pike_rows, pike_center, right, forward, safe_x * 1.05, safe_y * 1.35, facing_angle)
	_assign_grid(layout, right_muskets, 2, musket_rows, front_muskets_center, right, forward, safe_x * 1.05, safe_y * 1.2, facing_angle)
	_assign_grid(layout, left_muskets, 2, musket_rows, rear_muskets_center, right, forward, safe_x * 1.05, safe_y * 1.2, facing_angle)
	return layout


func _build_pike_and_shot_protected_layout(direction: Vector2) -> FormationLayout:
	var layout: FormationLayout = FormationLayout.new(&"pike_and_shot_protected")
	var forward: Vector2 = _sanitize_direction(direction)
	var right: Vector2 = Vector2(-forward.y, forward.x)
	var safe_x: float = _safe_spacing_x()
	var safe_y: float = _safe_spacing_y()
	var musketeers: Array = _get_modules_of_type(&"musketeers")
	var pikes: Array = _get_modules_of_type(&"pikemen")
	var inward_facing_angle: float = forward.angle() + PI * 0.5
	_assign_grid(layout, musketeers, 4, int(ceil(float(musketeers.size()) / 4.0)), Vector2.ZERO, right, forward, safe_x, safe_y, inward_facing_angle)
	var shell_positions: Array = [
		{"position": -forward * (safe_y * 2.35) - right * (safe_x * 0.5), "direction": -forward},
		{"position": -forward * (safe_y * 2.35) + right * (safe_x * 0.5), "direction": -forward},
		{"position": right * (safe_x * 2.7) - forward * (safe_y * 0.5), "direction": right},
		{"position": right * (safe_x * 2.7) + forward * (safe_y * 0.5), "direction": right},
		{"position": forward * (safe_y * 2.35) + right * (safe_x * 0.5), "direction": forward},
		{"position": forward * (safe_y * 2.35) - right * (safe_x * 0.5), "direction": forward},
		{"position": -right * (safe_x * 2.7) + forward * (safe_y * 0.5), "direction": -right},
		{"position": -right * (safe_x * 2.7) - forward * (safe_y * 0.5), "direction": -right},
	]
	for index in range(min(pikes.size(), shell_positions.size())):
		var slot_data: Dictionary = shell_positions[index]
		var outward_direction: Vector2 = slot_data.get("direction", forward)
		layout.add_slot(pikes[index], slot_data.get("position", Vector2.ZERO), outward_direction.angle() + PI * 0.5)
	return layout


func _build_pike_and_shot_firing_layout(direction: Vector2) -> FormationLayout:
	var layout: FormationLayout = FormationLayout.new(&"pike_and_shot_firing")
	var forward: Vector2 = _sanitize_direction(direction)
	var right: Vector2 = Vector2(-forward.y, forward.x)
	var facing_angle: float = forward.angle() + PI * 0.5
	var safe_x: float = _safe_spacing_x()
	var safe_y: float = _safe_spacing_y()
	var pikes: Array = _get_modules_by_group(&"core")
	var left_muskets: Array = _get_modules_by_group(&"left")
	var right_muskets: Array = _get_modules_by_group(&"right")
	var flank_offset: float = safe_x * 2.85
	_assign_grid(layout, pikes, 2, int(ceil(float(pikes.size()) / 2.0)), Vector2.ZERO, right, forward, safe_x, safe_y, facing_angle)
	var front_source_row: int = 3 - _current_wave_index
	_assign_rotated_rank_block(layout, left_muskets, 2, 4, -right * flank_offset, right, forward, safe_x, safe_y, facing_angle, front_source_row)
	_assign_rotated_rank_block(layout, right_muskets, 2, 4, right * flank_offset, right, forward, safe_x, safe_y, facing_angle, front_source_row)
	return layout


func _build_pike_and_shot_countermarch_layout(direction: Vector2) -> FormationLayout:
	var layout: FormationLayout = FormationLayout.new(&"pike_and_shot_countermarch")
	var forward: Vector2 = _sanitize_direction(direction)
	var right: Vector2 = Vector2(-forward.y, forward.x)
	var facing_angle: float = forward.angle() + PI * 0.5
	var safe_x: float = _safe_spacing_x()
	var safe_y: float = _safe_spacing_y()
	var pikes: Array = _get_modules_by_group(&"core")
	var musketeers: Array = _get_modules_of_type(&"musketeers")
	var pike_center: Vector2 = -forward * (safe_y * 1.9)
	var muskets_center: Vector2 = forward * (safe_y * 1.9)
	_assign_grid(layout, pikes, 2, int(ceil(float(pikes.size()) / 2.0)), pike_center, right, forward, safe_x, safe_y, facing_angle)
	var rows: int = int(ceil(float(musketeers.size()) / 4.0))
	var front_source_row: int = rows - 1 - _current_wave_index
	_assign_rotated_rank_block(layout, musketeers, 4, rows, muskets_center, right, forward, safe_x, safe_y, facing_angle, front_source_row)
	return layout


func _build_cavalry_caracole_layout(direction: Vector2) -> FormationLayout:
	var layout: FormationLayout = FormationLayout.new(&"cavalry_caracole")
	var cavalry: Array = _get_modules_of_type(&"cavalry")
	var forward: Vector2 = _sanitize_direction(direction)
	var right: Vector2 = Vector2(-forward.y, forward.x)
	var facing_angle: float = forward.angle() + PI * 0.5
	var safe_x: float = _safe_spacing_x()
	var safe_y: float = _safe_spacing_y()
	var wave_size: int = _get_cycle_wave_size()
	_assign_rotated_chunk_grid(layout, cavalry, 2, Vector2.ZERO, right, forward, safe_x * 1.1, safe_y * 1.35, facing_angle, _current_wave_index, wave_size)
	return layout


func _apply_firing_cycle_layout(immediate: bool = false) -> void:
	var layout: FormationLayout = get_layout_for_state(current_mode, current_direction)
	_apply_layout(layout, immediate)


func _build_firing_wave_modules() -> Array:
	if current_mode == FormationMode.FIRING_CYCLE and company_type == CompanyType.ARTILLERY:
		return [_get_modules_of_type(&"artillery")]
	if current_mode == FormationMode.CARACOLE:
		return _build_chunk_waves(_get_modules_of_type(&"cavalry"), _get_cycle_wave_size())
	if current_mode == FormationMode.COUNTERMARCH:
		return _build_row_waves(_get_modules_of_type(&"musketeers"), 4)
	var waves: Array = []
	var left_muskets: Array = _get_modules_by_group(&"left")
	var right_muskets: Array = _get_modules_by_group(&"right")
	var rows: int = int(max(ceil(float(left_muskets.size()) / 2.0), ceil(float(right_muskets.size()) / 2.0)))
	for row in range(rows - 1, -1, -1):
		var wave: Array = []
		for column in range(2):
			var left_index: int = row * 2 + column
			if left_index < left_muskets.size():
				wave.append(left_muskets[left_index])
			var right_index: int = row * 2 + column
			if right_index < right_muskets.size():
				wave.append(right_muskets[right_index])
		if not wave.is_empty():
			waves.append(wave)
	return waves


func _build_row_waves(target_modules: Array, columns: int) -> Array:
	var waves: Array = []
	var rows: int = int(ceil(float(target_modules.size()) / float(max(columns, 1))))
	for row in range(rows - 1, -1, -1):
		var wave: Array = []
		for column in range(columns):
			var index: int = row * columns + column
			if index < target_modules.size():
				wave.append(target_modules[index])
		if not wave.is_empty():
			waves.append(wave)
	return waves


func _build_chunk_waves(target_modules: Array, chunk_size: int) -> Array:
	var waves: Array = []
	if target_modules.is_empty():
		return waves
	var safe_chunk_size: int = max(chunk_size, 1)
	var index: int = target_modules.size() - safe_chunk_size
	while index >= 0:
		var wave: Array = []
		for offset in range(safe_chunk_size):
			var module_index: int = index + offset
			if module_index >= 0 and module_index < target_modules.size():
				wave.append(target_modules[module_index])
		if not wave.is_empty():
			waves.append(wave)
		index -= safe_chunk_size
	if waves.is_empty():
		waves.append(target_modules.duplicate())
	return waves


func _build_chunk_waves_front_first(target_modules: Array, chunk_size: int) -> Array:
	var waves: Array = []
	if target_modules.is_empty():
		return waves
	var safe_chunk_size: int = max(chunk_size, 1)
	var index: int = 0
	while index < target_modules.size():
		var wave: Array = []
		for offset in range(safe_chunk_size):
			var module_index: int = index + offset
			if module_index < target_modules.size():
				wave.append(target_modules[module_index])
		if not wave.is_empty():
			waves.append(wave)
		index += safe_chunk_size
	if waves.is_empty():
		waves.append(target_modules.duplicate())
	return waves


func _get_current_wave_modules() -> Array:
	if _firing_wave_modules.is_empty():
		return []
	return _firing_wave_modules[_current_wave_index]


func _set_active_wave_firing(value: bool) -> void:
	var active_wave: Array = _get_current_wave_modules()
	for module in modules:
		module.set_firing_active(value and active_wave.has(module))
		if value and active_wave.has(module) and company_type == CompanyType.ARTILLERY and module.module_type == &"artillery":
			var recoil_direction: Vector2 = -_sanitize_direction(current_direction)
			module.trigger_recoil(recoil_direction * 6.0, fire_hold_duration)


func _build_simple_line_layout(layout_name: StringName, target_modules: Array, columns: int, direction: Vector2, x_spacing: float, y_spacing: float) -> FormationLayout:
	var layout: FormationLayout = FormationLayout.new(layout_name)
	var forward: Vector2 = _sanitize_direction(direction)
	var right: Vector2 = Vector2(-forward.y, forward.x)
	var facing_angle: float = forward.angle() + PI * 0.5
	var rows: int = int(ceil(float(target_modules.size()) / float(max(columns, 1))))
	_assign_grid(layout, target_modules, columns, rows, Vector2.ZERO, right, forward, max(x_spacing, _safe_spacing_x()), max(y_spacing, _safe_spacing_y()), facing_angle)
	return layout


func _build_simple_columns_layout(layout_name: StringName, target_modules: Array, columns: int, direction: Vector2, x_spacing: float, y_spacing: float) -> FormationLayout:
	var layout: FormationLayout = FormationLayout.new(layout_name)
	var forward: Vector2 = _sanitize_direction(direction)
	var right: Vector2 = Vector2(-forward.y, forward.x)
	var facing_angle: float = forward.angle() + PI * 0.5
	var rows: int = int(ceil(float(target_modules.size()) / float(max(columns, 1))))
	_assign_grid(layout, target_modules, columns, rows, Vector2.ZERO, right, forward, max(x_spacing, _safe_spacing_x()), max(y_spacing, _safe_spacing_y()), facing_angle)
	return layout


func _assign_grid(
		layout: FormationLayout,
		target_modules: Array,
		columns: int,
		rows: int,
		center_offset: Vector2,
		right_axis: Vector2,
		forward_axis: Vector2,
		x_spacing: float,
		y_spacing: float,
		facing_angle: float
) -> void:
	if target_modules.is_empty():
		return
	var width_offset: float = float(columns - 1) * 0.5
	var height_offset: float = float(rows - 1) * 0.5
	for index in range(target_modules.size()):
		var column: int = index % max(columns, 1)
		var row: int = int(floor(float(index) / float(max(columns, 1))))
		var local_position: Vector2 = center_offset
		local_position += right_axis * ((float(column) - width_offset) * x_spacing)
		local_position += forward_axis * ((float(row) - height_offset) * y_spacing)
		layout.add_slot(target_modules[index], local_position, facing_angle)


func _assign_rotated_rank_block(
		layout: FormationLayout,
		target_modules: Array,
		columns: int,
		rows: int,
		center_offset: Vector2,
		right_axis: Vector2,
		forward_axis: Vector2,
		x_spacing: float,
		y_spacing: float,
		facing_angle: float,
		front_rank_index: int
) -> void:
	if target_modules.is_empty():
		return
	var width_offset: float = float(columns - 1) * 0.5
	var height_offset: float = float(rows - 1) * 0.5
	var front_display_row: int = rows - 1
	for display_row in range(rows):
		var distance_from_front: int = front_display_row - display_row
		var source_row: int = posmod(front_rank_index - distance_from_front, rows)
		for column in range(columns):
			var source_index: int = source_row * columns + column
			if source_index >= target_modules.size():
				continue
			var local_position: Vector2 = center_offset
			local_position += right_axis * ((float(column) - width_offset) * x_spacing)
			local_position += forward_axis * ((float(display_row) - height_offset) * y_spacing)
			layout.add_slot(target_modules[source_index], local_position, facing_angle)


func _assign_rotated_chunk_column(
		layout: FormationLayout,
		target_modules: Array,
		center_offset: Vector2,
		right_axis: Vector2,
		forward_axis: Vector2,
		y_spacing: float,
		facing_angle: float,
		front_chunk_index: int,
		chunk_size: int
) -> void:
	if target_modules.is_empty():
		return
	var ordered_modules: Array = []
	var chunks: Array = _build_chunk_waves(target_modules, chunk_size)
	if chunks.is_empty():
		return
	for chunk_offset in range(chunks.size()):
		var chunk_index: int = (front_chunk_index + chunk_offset) % chunks.size()
		for module in chunks[chunk_index]:
			ordered_modules.append(module)
	var height_offset: float = float(ordered_modules.size() - 1) * 0.5
	for display_index in range(ordered_modules.size()):
		var local_position: Vector2 = center_offset + forward_axis * ((float(display_index) - height_offset) * y_spacing)
		layout.add_slot(ordered_modules[display_index], local_position, facing_angle)


func _assign_rotated_chunk_grid(
		layout: FormationLayout,
		target_modules: Array,
		columns: int,
		center_offset: Vector2,
		right_axis: Vector2,
		forward_axis: Vector2,
		x_spacing: float,
		y_spacing: float,
		facing_angle: float,
		front_chunk_index: int,
		chunk_size: int
) -> void:
	if target_modules.is_empty():
		return
	var ordered_modules: Array = []
	var chunks: Array = _build_chunk_waves(target_modules, chunk_size)
	if chunks.is_empty():
		return
	for chunk_offset in range(chunks.size()):
		var chunk_index: int = (front_chunk_index + chunk_offset) % chunks.size()
		for module in chunks[chunk_index]:
			ordered_modules.append(module)
	var rows: int = int(ceil(float(ordered_modules.size()) / float(max(columns, 1))))
	var width_offset: float = float(columns - 1) * 0.5
	var height_offset: float = float(rows - 1) * 0.5
	for display_index in range(ordered_modules.size()):
		var column: int = display_index % columns
		var row: int = int(floor(float(display_index) / float(columns)))
		var distance_from_front: int = (rows - 1) - row
		var local_position: Vector2 = center_offset
		local_position += right_axis * ((float(column) - width_offset) * x_spacing)
		local_position += forward_axis * (float(distance_from_front) * y_spacing - height_offset * y_spacing)
		layout.add_slot(ordered_modules[display_index], local_position, facing_angle)


func _get_modules_by_group(group_name: StringName) -> Array:
	var result: Array = []
	for module in modules:
		if module.tactical_group == group_name:
			result.append(module)
	return result


func _get_modules_of_type(type_name: StringName) -> Array:
	var result: Array = []
	for module in modules:
		if module.module_type == type_name:
			result.append(module)
	return result


func _sanitize_direction(direction: Vector2) -> Vector2:
	if direction.length_squared() <= 0.001:
		return Vector2.RIGHT
	return direction.normalized()


func _is_cycle_mode(mode: FormationMode) -> bool:
	return mode == FormationMode.FIRING_CYCLE or mode == FormationMode.COUNTERMARCH or mode == FormationMode.CARACOLE


func _safe_spacing_x() -> float:
	return max(horizontal_spacing, module_visual_size.x + 10.0)


func _safe_spacing_y() -> float:
	return max(vertical_spacing, module_visual_size.y + 12.0)


func _get_cycle_wave_size() -> int:
	if current_mode == FormationMode.CARACOLE:
		var cavalry_count_value: int = _get_modules_of_type(&"cavalry").size()
		return max(int(ceil(float(cavalry_count_value) * 0.25 / 2.0)) * 2, 2)
	if current_mode == FormationMode.COUNTERMARCH:
		return 4
	if current_mode == FormationMode.FIRING_CYCLE:
		return 4
	return 1


func _get_company_bounds() -> Rect2:
	if modules.is_empty():
		return Rect2(-company_rect_size * 0.5, company_rect_size)
	var min_point: Vector2 = Vector2(INF, INF)
	var max_point: Vector2 = Vector2(-INF, -INF)
	for module in modules:
		var points: Array = [module.position, module.target_local_position]
		for point in points:
			min_point.x = min(min_point.x, point.x)
			min_point.y = min(min_point.y, point.y)
			max_point.x = max(max_point.x, point.x)
			max_point.y = max(max_point.y, point.y)
	var dynamic_rect: Rect2 = Rect2(min_point - module_visual_size * 0.9, (max_point - min_point) + module_visual_size * 1.8)
	var min_rect: Rect2 = Rect2(-company_rect_size * 0.5, company_rect_size)
	return dynamic_rect.merge(min_rect).grow(24.0)
