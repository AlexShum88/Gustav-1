class_name CoreV2Hud
extends Control


const PERFORMANCE_WARMUP_MSEC: int = 2000

signal deployment_action_requested(command_type: int)
signal start_battle_requested()
signal order_type_selected(order_type: int)
signal order_cancelled()
signal policies_changed(policies: Dictionary)
signal debug_formation_requested(formation_state: int)

var _top_summary: Label
var _reserve_summary: RichTextLabel
var _selection_summary: RichTextLabel
var _order_summary: RichTextLabel
var _event_log: RichTextLabel
var _deployment_summary: RichTextLabel
var _performance_summary: RichTextLabel
var _order_palette_panel: Panel
var _order_detail_panel: Panel
var _deployment_panel: Panel
var _debug_formation_panel: Panel
var _policy_toggles: Dictionary = {}
var _order_buttons: Dictionary = {}
var _debug_formation_buttons: Dictionary = {}
var _performance_min_fps: int = 0
var _performance_max_values: Dictionary = {}
var _performance_started_msec: int = 0


func _ready() -> void:
	_performance_started_msec = Time.get_ticks_msec()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS
	_build_top_bar()
	_build_reserve_panel()
	_build_selected_panel()
	_build_order_detail_panel()
	_build_order_palette()
	_build_debug_formation_panel()
	_build_performance_panel()
	_build_deployment_panel()
	_build_event_log()


func set_snapshot(
		snapshot: Dictionary,
		selected_battalion: Dictionary,
		pending_order_type: int,
		pending_placement_command: int,
		policies: Dictionary,
		performance_stats: Dictionary = {}
) -> void:
	# HUD не тягне дані з домену напряму, а лише відмальовує отриманий snapshot.
	var ui_channel: Dictionary = snapshot.get("channels", {}).get("ui", {})
	var top_bar: Dictionary = ui_channel.get("top_bar", {})
	var deployment: Dictionary = ui_channel.get("deployment", {})
	var battle_phase: int = int(snapshot.get("phase", CoreV2Types.BattlePhase.DEPLOYMENT))
	var is_deployment_phase: bool = battle_phase == CoreV2Types.BattlePhase.DEPLOYMENT

	_top_summary.text = "%s | Фаза: %s | Погода %s %.2f | Мораль %.0f%% | Припаси %.1f | Набої %.1f | VP %.1f : %.1f | Пункти %d : %d | Видимий ворог %d | Гінці %d | Last seen %d | +%.2f ресурсів/с" % [
		top_bar.get("army_name", "Армія"),
		top_bar.get("phase_label", "Невідомо"),
		top_bar.get("weather_label", "Ясно"),
		float(top_bar.get("weather_vision_multiplier", 1.0)),
		float(top_bar.get("army_morale", 0.0)) * 100.0,
		float(top_bar.get("baggage_supply", 0.0)),
		float(top_bar.get("baggage_ammo", 0.0)),
		float(top_bar.get("own_victory_points", 0.0)),
		float(top_bar.get("enemy_victory_points", 0.0)),
		int(top_bar.get("held_objectives", 0)),
		int(top_bar.get("enemy_held_objectives", 0)),
		int(top_bar.get("visible_enemy_battalions", 0)),
		int(top_bar.get("own_order_messengers", 0)),
		int(top_bar.get("last_seen_contacts", 0)),
		float(top_bar.get("recent_supply_income", 0.0)),
	]

	var reserve_lines: Array = []
	for reserve_value in ui_channel.get("reserve_queue", []):
		var reserve_entry: Dictionary = reserve_value
		reserve_lines.append("%s [%s] %d" % [
			reserve_entry.get("name", "Резерв"),
			reserve_entry.get("status", "Резерв"),
			int(reserve_entry.get("cost", 0)),
		])
	_reserve_summary.text = "[b]Виклик із редактора армії[/b]\n%s" % (
		"\n".join(reserve_lines) if not reserve_lines.is_empty() else "Резерв поки не налаштований."
	)

	var selection_summary: Dictionary = _build_selection_summary(selected_battalion)
	var selection_title: String = selection_summary.get("title", "Нічого не вибрано")
	var selection_body: String = selection_summary.get("body", "")
	_selection_summary.text = "[b]%s[/b]\n%s" % [selection_title, selection_body]

	var deployment_lines: Array = [
		"Обоз: %s" % ("готовий" if bool(deployment.get("is_baggage_ready", false)) else "не розміщено"),
		"Полководець: %s" % ("готовий" if bool(deployment.get("is_commander_ready", false)) else "не розміщено"),
		"Старт бою: %s" % ("дозволено" if bool(deployment.get("is_ready", false)) else "заблоковано"),
	]
	_deployment_summary.text = "[b]Стартове розгортання[/b]\n%s" % "\n".join(deployment_lines)

	var pending_text: String = _build_pending_text(is_deployment_phase, pending_order_type, pending_placement_command, policies)
	_order_summary.text = pending_text

	var event_lines: Array = ui_channel.get("recent_events", [])
	_event_log.text = "[b]Журнал штабу[/b]\n%s" % "\n".join(event_lines)
	_performance_summary.text = _build_performance_text(performance_stats)

	_set_phase_visibility(is_deployment_phase)
	_update_order_button_state(pending_order_type, is_deployment_phase, selected_battalion)
	_update_debug_formation_button_state(selected_battalion)


func get_policy_state() -> Dictionary:
	return {
		"road_column": _policy_toggles["road_column"].button_pressed,
		"deploy_on_contact": _policy_toggles["deploy_on_contact"].button_pressed,
		"retreat_on_flank_collapse": _policy_toggles["retreat_on_flank_collapse"].button_pressed,
		"hold_reserve": _policy_toggles["hold_reserve"].button_pressed,
	}


func _build_selection_summary(selected_unit: Dictionary) -> Dictionary:
	if selected_unit.is_empty():
		return {
			"title": "Нічого не вибрано",
			"body": "Оберіть дружній батальйон або штаб, щоб побачити стан і видати наказ бригаді.",
		}
	var entity_kind: int = int(selected_unit.get("entity_kind", CoreV2Types.EntityKind.BATTALION))
	if entity_kind == CoreV2Types.EntityKind.BRIGADE_HQ or entity_kind == CoreV2Types.EntityKind.ARMY_HQ:
		return _build_hq_selection_summary(selected_unit)
	return _build_battalion_selection_summary(selected_unit)


func _build_battalion_selection_summary(selected_battalion: Dictionary) -> Dictionary:
	var selection_title: String = String(selected_battalion.get("display_name", "Батальйон"))
	var selection_body: String = "Армія: %s\nБригада: %s\nСтатус: %s\nФормація: %s -> %s (%.0f%%)\nКомандир: %s\nЧисельність: %d\nВидима сила: %d\nЗгуртованість: %.0f%%\nБоєприпаси: %.0f%%\nФураж: %.0f%%\nОгляд: %.0f -> %.0f м\nМісцевість: %s h%.0f v%.2f spd%.2f def%+.2f\nНаказ: %s" % [
		selected_battalion.get("army_name", ""),
		selected_battalion.get("brigade_name", ""),
		selected_battalion.get("status_label", ""),
		selected_battalion.get("formation_label", ""),
		selected_battalion.get("desired_formation_label", selected_battalion.get("formation_label", "")),
		float(selected_battalion.get("formation_progress", 1.0)) * 100.0,
		selected_battalion.get("commander_name", ""),
		int(selected_battalion.get("soldiers_total", 0)),
		int(selected_battalion.get("visible_strength_estimate", selected_battalion.get("soldiers_total", 0))),
		float(selected_battalion.get("cohesion", 0.0)) * 100.0,
		float(selected_battalion.get("ammunition", 0.0)) * 100.0,
		float(selected_battalion.get("forage", 0.0)) * 100.0,
		float(selected_battalion.get("vision_radius_m", 0.0)),
		float(selected_battalion.get("effective_vision_radius_m", selected_battalion.get("vision_radius_m", 0.0))),
		selected_battalion.get("terrain_label", "Рівнина"),
		float(selected_battalion.get("terrain_height_m", 0.0)),
		float(selected_battalion.get("terrain_vision_multiplier", 1.0)),
		float(selected_battalion.get("terrain_speed_multiplier", 1.0)),
		float(selected_battalion.get("terrain_defense_modifier", 0.0)),
		selected_battalion.get("order_label", "Без наказу"),
	]
	selection_body += "\nАтмосфера: weather %.2f smoke %.2f los %.2f" % [
		float(selected_battalion.get("weather_vision_multiplier", 1.0)),
		float(selected_battalion.get("smoke_density", 0.0)),
		float(selected_battalion.get("atmospheric_vision_multiplier", 1.0)),
	]
	selection_body += "\nТочки маршруту: %d" % int(selected_battalion.get("movement_path", []).size())
	if not String(selected_battalion.get("engagement_mode", "")).is_empty():
		selection_body += "\nМаневр контакту: %s | дистанція %.0f м" % [
			selected_battalion.get("engagement_mode", ""),
			float(selected_battalion.get("engagement_desired_range_m", 0.0)),
		]
	if int(selected_battalion.get("separation_contacts", 0)) > 0:
		selection_body += "\nКонтакт формацій: %d | поштовх %.1f м" % [
			int(selected_battalion.get("separation_contacts", 0)),
			float(selected_battalion.get("separation_push_m", 0.0)),
		]
	if bool(selected_battalion.get("is_in_contact", false)):
		selection_body += "\nContact: frontage %.0f%% | pressure %.0f%% | compression %.0f%% | recoil %.0f%%" % [
			float(selected_battalion.get("contact_frontage_ratio", 0.0)) * 100.0,
			float(selected_battalion.get("contact_pressure", 0.0)) * 100.0,
			float(selected_battalion.get("compression_level", 0.0)) * 100.0,
			float(selected_battalion.get("recoil_tendency", 0.0)) * 100.0,
		]
	if not String(selected_battalion.get("combat_target_name", "")).is_empty():
		var combat_kind: String = String(selected_battalion.get("combat_attack_kind", ""))
		var combat_kind_label: String = _combat_attack_kind_label(combat_kind)
		var melee_suffix: String = ""
		if combat_kind == "melee":
			melee_suffix = " | commitment %s" % String(selected_battalion.get("melee_commitment_label", ""))
		selection_body += "\nБій: %s %.0f м | %s | втрати +%d / -%d | reload %.1f%s" % [
			selected_battalion.get("combat_target_name", ""),
			float(selected_battalion.get("combat_range_m", 0.0)),
			combat_kind_label,
			int(selected_battalion.get("recent_casualties_inflicted", 0)),
			int(selected_battalion.get("recent_casualties_taken", 0)),
			float(selected_battalion.get("combat_cooldown_seconds", 0.0)),
			melee_suffix,
		]
	elif int(selected_battalion.get("recent_casualties_taken", 0)) > 0:
		selection_body += "\nБій: отримано втрат %d" % int(selected_battalion.get("recent_casualties_taken", 0))
	return {
		"title": selection_title,
		"body": selection_body,
	}


func _combat_attack_kind_label(attack_kind: String) -> String:
	match attack_kind:
		"melee":
			return "рукопашна"
		"musket":
			return "мушкетний вогонь"
		"artillery":
			return "артилерія"
		_:
			return "контакт"


func _build_hq_selection_summary(selected_hq: Dictionary) -> Dictionary:
	var entity_kind: int = int(selected_hq.get("entity_kind", CoreV2Types.EntityKind.BRIGADE_HQ))
	var kind_label: String = CoreV2Types.entity_kind_name(entity_kind)
	var display_name: String = String(selected_hq.get("display_name", kind_label))
	var selection_body: String = "Тип: %s\nАрмія: %s\nСтатус: %s\nМіцність: %.0f%%\nОстанній урон: %.1f%%\nНаказ: %s" % [
		kind_label,
		selected_hq.get("army_name", selected_hq.get("army_id", "")),
		selected_hq.get("status_label", "активний"),
		float(selected_hq.get("health", 1.0)) * 100.0,
		float(selected_hq.get("recent_damage", 0.0)) * 100.0,
		selected_hq.get("order_label", "Без наказу"),
	]
	if entity_kind == CoreV2Types.EntityKind.BRIGADE_HQ:
		selection_body += "\nБригада: %s\nКомандир: %s" % [
			display_name,
			selected_hq.get("commander_name", ""),
		]
		var battalion_names: Array = selected_hq.get("battalion_names", [])
		if not battalion_names.is_empty():
			selection_body += "\nБатальйони:\n- %s" % "\n- ".join(battalion_names)
	else:
		selection_body += "\nПолководець: %s" % selected_hq.get("commander_name", display_name)
	return {
		"title": display_name,
		"body": selection_body,
	}


func _build_performance_text(performance_stats: Dictionary) -> String:
	var warmup_remaining_msec: int = max(
		0,
		PERFORMANCE_WARMUP_MSEC - (Time.get_ticks_msec() - _performance_started_msec)
	)
	_update_performance_extremes(performance_stats, warmup_remaining_msec <= 0)
	var fps: int = int(performance_stats.get("fps", 0))
	var min_fps_text: String = str(_performance_min_fps) if _performance_min_fps > 0 else "-"
	var lines: Array = [
		"[b]Продуктивність[/b]"
	]
	if warmup_remaining_msec > 0:
		lines.append("Warmup %.1f с" % (float(warmup_remaining_msec) / 1000.0))
	lines.append("FPS %d / min %s" % [fps, min_fps_text])
	lines.append("Apply %.2f ms / max %.2f" % [
		float(performance_stats.get("apply_ms", 0.0)),
		_get_performance_max_float("apply_ms"),
	])
	lines.append("Dynamic %.2f ms / max %.2f" % [
		float(performance_stats.get("dynamic_rebuild_ms", 0.0)),
		_get_performance_max_float("dynamic_rebuild_ms"),
	])
	lines.append("Static %.2f ms / max %.2f" % [
		float(performance_stats.get("static_rebuild_ms", 0.0)),
		_get_performance_max_float("static_rebuild_ms"),
	])
	lines.append("Visual %.2f ms / max %.2f" % [
		float(performance_stats.get("visual_interpolation_ms", 0.0)),
		_get_performance_max_float("visual_interpolation_ms"),
	])
	lines.append("Selection LOS %.2f ms / max %.2f" % [
		float(performance_stats.get("selection_overlay_rebuild_ms", 0.0)),
		_get_performance_max_float("selection_overlay_rebuild_ms"),
	])
	lines.append("Selection LOS nodes %d / max %d" % [
		int(performance_stats.get("selection_overlay_nodes", 0)),
		_get_performance_max_int("selection_overlay_nodes"),
	])
	lines.append("Selection LOS rebuilds %d / max %d" % [
		int(performance_stats.get("selection_overlay_rebuilds", 0)),
		_get_performance_max_int("selection_overlay_rebuilds"),
	])
	lines.append("LOS debug %d rays / %.0f m" % [
		int(performance_stats.get("debug_los_rays", 0)),
		float(performance_stats.get("debug_los_sample_step_m", 0.0)),
	])
	lines.append("Units %d / max %d" % [
		int(performance_stats.get("battalion_nodes", 0)),
		_get_performance_max_int("battalion_nodes"),
	])
	lines.append("Battalion footprints %d / max %d" % [
		int(performance_stats.get("battalion_footprints", 0)),
		_get_performance_max_int("battalion_footprints"),
	])
	lines.append("Formation cues %d / max %d" % [
		int(performance_stats.get("formation_cue_multimeshes", 0)),
		_get_performance_max_int("formation_cue_multimeshes"),
	])
	lines.append("Route waypoints %d / max %d" % [
		int(performance_stats.get("route_waypoints", 0)),
		_get_performance_max_int("route_waypoints"),
	])
	lines.append("Battalion visuals %d / max %d" % [
		int(performance_stats.get("battalion_visuals", 0)),
		_get_performance_max_int("battalion_visuals"),
	])
	lines.append("Objective visuals %d / max %d" % [
		int(performance_stats.get("objective_visuals", 0)),
		_get_performance_max_int("objective_visuals"),
	])
	lines.append("HQ visuals %d / max %d" % [
		int(performance_stats.get("hq_visuals", 0)),
		_get_performance_max_int("hq_visuals"),
	])
	lines.append("Order lines %d / max %d" % [
		int(performance_stats.get("order_line_visuals", 0)),
		_get_performance_max_int("order_line_visuals"),
	])
	lines.append("Messengers %d / max %d" % [
		int(performance_stats.get("order_messengers", 0)),
		_get_performance_max_int("order_messengers"),
	])
	lines.append("Messenger visuals %d / max %d" % [
		int(performance_stats.get("messenger_visuals", 0)),
		_get_performance_max_int("messenger_visuals"),
	])
	lines.append("Last-seen visuals %d / max %d" % [
		int(performance_stats.get("last_seen_visuals", 0)),
		_get_performance_max_int("last_seen_visuals"),
	])
	lines.append("Material cache %d / max %d" % [
		int(performance_stats.get("material_cache", 0)),
		_get_performance_max_int("material_cache"),
	])
	lines.append("Mesh cache %d / max %d" % [
		int(performance_stats.get("mesh_cache", 0)),
		_get_performance_max_int("mesh_cache"),
	])
	return "\n".join(lines)


func _update_performance_extremes(performance_stats: Dictionary, can_record_extremes: bool) -> void:
	if not can_record_extremes:
		return
	var fps: int = int(performance_stats.get("fps", 0))
	if fps > 0 and (_performance_min_fps <= 0 or fps < _performance_min_fps):
		_performance_min_fps = fps

	var max_metric_keys: Array = [
		"apply_ms",
		"dynamic_rebuild_ms",
		"static_rebuild_ms",
		"visual_interpolation_ms",
		"selection_overlay_rebuild_ms",
		"selection_overlay_nodes",
		"selection_overlay_rebuilds",
		"battalion_nodes",
		"battalion_footprints",
		"formation_cue_multimeshes",
		"route_waypoints",
		"battalion_visuals",
		"objective_visuals",
		"hq_visuals",
		"order_line_visuals",
		"order_messengers",
		"messenger_visuals",
		"last_seen_visuals",
		"last_seen_markers",
		"hq_nodes",
		"objective_nodes",
		"material_cache",
		"mesh_cache",
	]
	for metric_key_value in max_metric_keys:
		var metric_key: String = String(metric_key_value)
		var metric_value: float = float(performance_stats.get(metric_key, 0.0))
		if not _performance_max_values.has(metric_key) or metric_value > float(_performance_max_values[metric_key]):
			_performance_max_values[metric_key] = metric_value


func _get_performance_max_float(metric_key: String) -> float:
	return float(_performance_max_values.get(metric_key, 0.0))


func _get_performance_max_int(metric_key: String) -> int:
	return int(round(_get_performance_max_float(metric_key)))


func _reset_performance_extremes() -> void:
	_performance_min_fps = 0
	_performance_max_values.clear()
	_performance_started_msec = Time.get_ticks_msec()


func _build_top_bar() -> void:
	var panel := _make_panel(Vector2(12.0, 12.0), Vector2(1576.0, 54.0))
	_top_summary = Label.new()
	_top_summary.position = Vector2(12.0, 8.0)
	_top_summary.size = Vector2(1548.0, 34.0)
	_top_summary.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	panel.add_child(_top_summary)


func _build_reserve_panel() -> void:
	var panel := _make_panel(Vector2(510.0, 78.0), Vector2(568.0, 116.0))
	var title := _make_title("Резерви")
	panel.add_child(title)
	_reserve_summary = RichTextLabel.new()
	_reserve_summary.position = Vector2(12.0, 36.0)
	_reserve_summary.size = Vector2(540.0, 68.0)
	_reserve_summary.bbcode_enabled = true
	_reserve_summary.scroll_active = false
	panel.add_child(_reserve_summary)


func _build_selected_panel() -> void:
	var panel := _make_panel(Vector2(12.0, 560.0), Vector2(336.0, 328.0))
	var title := _make_title("Виділений юніт")
	panel.add_child(title)
	_selection_summary = RichTextLabel.new()
	_selection_summary.position = Vector2(12.0, 36.0)
	_selection_summary.size = Vector2(312.0, 280.0)
	_selection_summary.bbcode_enabled = true
	_selection_summary.scroll_active = true
	panel.add_child(_selection_summary)


func _build_order_detail_panel() -> void:
	var panel := _make_panel(Vector2(430.0, 716.0), Vector2(420.0, 172.0))
	_order_detail_panel = panel
	var title := _make_title("Параметри наказу")
	panel.add_child(title)

	_order_summary = RichTextLabel.new()
	_order_summary.position = Vector2(12.0, 36.0)
	_order_summary.size = Vector2(220.0, 124.0)
	_order_summary.bbcode_enabled = true
	_order_summary.scroll_active = false
	panel.add_child(_order_summary)

	var toggle_names := [
		["road_column", "Колона дорогою"],
		["deploy_on_contact", "Розгортатись при контакті"],
		["retreat_on_flank_collapse", "Відходити при фланговому провалі"],
		["hold_reserve", "Тримати резерв"],
	]
	var y: float = 38.0
	for toggle_data in toggle_names:
		var toggle := CheckBox.new()
		toggle.position = Vector2(245.0, y)
		toggle.text = toggle_data[1]
		toggle.toggled.connect(_on_policy_toggle_changed)
		panel.add_child(toggle)
		_policy_toggles[toggle_data[0]] = toggle
		y += 30.0
	_policy_toggles["road_column"].button_pressed = true
	_policy_toggles["deploy_on_contact"].button_pressed = true

	var cancel_button := Button.new()
	cancel_button.text = "Скасувати"
	cancel_button.position = Vector2(245.0, 132.0)
	cancel_button.pressed.connect(func() -> void:
		emit_signal("order_cancelled")
	)
	panel.add_child(cancel_button)


func _build_order_palette() -> void:
	var panel := _make_panel(Vector2(1268.0, 550.0), Vector2(320.0, 338.0))
	_order_palette_panel = panel
	var title := _make_title("Палітра наказів")
	panel.add_child(title)

	var order_types := [
		CoreV2Types.OrderType.MOVE,
		CoreV2Types.OrderType.MARCH,
		CoreV2Types.OrderType.ATTACK,
		CoreV2Types.OrderType.MELEE_ASSAULT,
		CoreV2Types.OrderType.DEFEND,
		CoreV2Types.OrderType.PATROL,
		CoreV2Types.OrderType.HOLD,
	]
	var y: float = 40.0
	for order_type in order_types:
		var button := Button.new()
		button.position = Vector2(16.0, y)
		button.size = Vector2(288.0, 34.0)
		button.text = CoreV2Types.order_type_name(order_type)
		button.pressed.connect(_on_order_button_pressed.bind(order_type))
		panel.add_child(button)
		_order_buttons[order_type] = button
		y += 40.0


func _build_debug_formation_panel() -> void:
	var panel := _make_panel(Vector2(1030.0, 418.0), Vector2(226.0, 236.0))
	_debug_formation_panel = panel
	var title := _make_title("Примусовий стрій")
	panel.add_child(title)

	var formation_states := [
		CoreV2Types.FormationState.LINE,
		CoreV2Types.FormationState.MUSKETEER_LINE,
		CoreV2Types.FormationState.DEFENSIVE,
		CoreV2Types.FormationState.TERCIA,
		CoreV2Types.FormationState.COLUMN,
		CoreV2Types.FormationState.MARCH_COLUMN,
	]
	var y: float = 38.0
	for formation_state in formation_states:
		var button := Button.new()
		button.position = Vector2(12.0, y)
		button.size = Vector2(202.0, 28.0)
		button.text = CoreV2Types.formation_state_name(formation_state)
		button.pressed.connect(_on_debug_formation_button_pressed.bind(formation_state))
		panel.add_child(button)
		_debug_formation_buttons[formation_state] = button
		y += 31.0


func _build_performance_panel() -> void:
	var panel := _make_panel(Vector2(1030.0, 666.0), Vector2(226.0, 222.0))
	var title := _make_title("Моніторинг")
	panel.add_child(title)

	var reset_button := Button.new()
	reset_button.text = "Reset"
	reset_button.position = Vector2(154.0, 6.0)
	reset_button.size = Vector2(60.0, 24.0)
	reset_button.pressed.connect(_reset_performance_extremes)
	panel.add_child(reset_button)

	_performance_summary = RichTextLabel.new()
	_performance_summary.position = Vector2(12.0, 36.0)
	_performance_summary.size = Vector2(202.0, 174.0)
	_performance_summary.bbcode_enabled = true
	_performance_summary.scroll_active = true
	panel.add_child(_performance_summary)


func _build_deployment_panel() -> void:
	var panel := _make_panel(Vector2(1268.0, 78.0), Vector2(320.0, 214.0))
	_deployment_panel = panel
	var title := _make_title("Розгортання")
	panel.add_child(title)

	_deployment_summary = RichTextLabel.new()
	_deployment_summary.position = Vector2(12.0, 36.0)
	_deployment_summary.size = Vector2(296.0, 76.0)
	_deployment_summary.bbcode_enabled = true
	_deployment_summary.scroll_active = false
	panel.add_child(_deployment_summary)

	var baggage_button := Button.new()
	baggage_button.text = "Розмістити обоз"
	baggage_button.position = Vector2(12.0, 120.0)
	baggage_button.size = Vector2(296.0, 28.0)
	baggage_button.pressed.connect(func() -> void:
		emit_signal("deployment_action_requested", CoreV2Types.CommandType.PLACE_BAGGAGE)
	)
	panel.add_child(baggage_button)

	var commander_button := Button.new()
	commander_button.text = "Розмістити полководця"
	commander_button.position = Vector2(12.0, 152.0)
	commander_button.size = Vector2(296.0, 28.0)
	commander_button.pressed.connect(func() -> void:
		emit_signal("deployment_action_requested", CoreV2Types.CommandType.PLACE_COMMANDER)
	)
	panel.add_child(commander_button)

	var start_button := Button.new()
	start_button.text = "Почати бій"
	start_button.position = Vector2(12.0, 184.0)
	start_button.size = Vector2(296.0, 24.0)
	start_button.pressed.connect(func() -> void:
		emit_signal("start_battle_requested")
	)
	panel.add_child(start_button)


func _build_event_log() -> void:
	var panel := _make_panel(Vector2(12.0, 78.0), Vector2(472.0, 186.0))
	var title := _make_title("Штабний журнал")
	panel.add_child(title)
	_event_log = RichTextLabel.new()
	_event_log.position = Vector2(12.0, 36.0)
	_event_log.size = Vector2(448.0, 138.0)
	_event_log.bbcode_enabled = true
	_event_log.scroll_active = true
	panel.add_child(_event_log)


func _build_pending_text(
		is_deployment_phase: bool,
		pending_order_type: int,
		pending_placement_command: int,
		policies: Dictionary
) -> String:
	if pending_placement_command == CoreV2Types.CommandType.PLACE_BAGGAGE:
		return "Клікніть по тиловій зоні, щоб поставити обоз."
	if pending_placement_command == CoreV2Types.CommandType.PLACE_COMMANDER:
		return "Клікніть по зоні штабу, щоб поставити полководця."
	if is_deployment_phase:
		return "Активна пауза: спочатку розмістіть обоз і полководця, після цього можна запускати бій."
	if pending_order_type == CoreV2Types.OrderType.NONE:
		return "Оберіть наказ справа знизу, а потім клацніть на мапі точку прибуття бригади."
	return "Очікує: [b]%s[/b]\nЦіль буде задана наступним кліком по мапі.\nПолітики:\n- Колона дорогою: %s\n- Розгортатись при контакті: %s\n- Відходити при фланговому провалі: %s\n- Тримати резерв: %s" % [
		CoreV2Types.order_type_name(pending_order_type),
		_yes_no(bool(policies.get("road_column", false))),
		_yes_no(bool(policies.get("deploy_on_contact", false))),
		_yes_no(bool(policies.get("retreat_on_flank_collapse", false))),
		_yes_no(bool(policies.get("hold_reserve", false))),
	]


func _set_phase_visibility(is_deployment_phase: bool) -> void:
	_order_palette_panel.visible = not is_deployment_phase
	_order_detail_panel.visible = true


func _update_order_button_state(active_order_type: int, is_deployment_phase: bool, selected_unit: Dictionary) -> void:
	var can_issue_order: bool = _can_selected_unit_issue_brigade_order(selected_unit)
	for order_type_value in _order_buttons.keys():
		var order_type: int = int(order_type_value)
		var button: Button = _order_buttons[order_type]
		button.disabled = is_deployment_phase or not can_issue_order
		button.modulate = Color(1.0, 1.0, 1.0) if order_type != active_order_type else Color(0.92, 0.9, 0.56)


func _can_selected_unit_issue_brigade_order(selected_unit: Dictionary) -> bool:
	if selected_unit.is_empty() or not bool(selected_unit.get("is_friendly", false)):
		return false
	var entity_kind: int = int(selected_unit.get("entity_kind", CoreV2Types.EntityKind.NONE))
	if entity_kind != CoreV2Types.EntityKind.BATTALION and entity_kind != CoreV2Types.EntityKind.BRIGADE_HQ:
		return false
	return not String(selected_unit.get("brigade_id", "")).is_empty()


func _update_debug_formation_button_state(selected_battalion: Dictionary) -> void:
	var has_selection: bool = not selected_battalion.is_empty() and int(selected_battalion.get("entity_kind", CoreV2Types.EntityKind.NONE)) == CoreV2Types.EntityKind.BATTALION
	var desired_formation: int = int(selected_battalion.get("desired_formation_state", -1))
	for formation_state_value in _debug_formation_buttons.keys():
		var formation_state: int = int(formation_state_value)
		var button: Button = _debug_formation_buttons[formation_state]
		button.disabled = not has_selection
		button.modulate = Color(0.92, 0.9, 0.56) if formation_state == desired_formation else Color(1.0, 1.0, 1.0)


func _make_panel(position_value: Vector2, size_value: Vector2) -> Panel:
	var panel := Panel.new()
	panel.position = position_value
	panel.size = size_value
	panel.self_modulate = Color(0.09, 0.11, 0.14, 0.86)
	add_child(panel)
	return panel


func _make_title(text_value: String) -> Label:
	var label := Label.new()
	label.position = Vector2(12.0, 8.0)
	label.text = text_value
	label.add_theme_color_override("font_color", Color(0.96, 0.95, 0.9))
	return label


func _on_order_button_pressed(order_type: int) -> void:
	emit_signal("order_type_selected", order_type)


func _on_policy_toggle_changed(_pressed: bool) -> void:
	emit_signal("policies_changed", get_policy_state())


func _on_debug_formation_button_pressed(formation_state: int) -> void:
	emit_signal("debug_formation_requested", formation_state)


func _yes_no(value: bool) -> String:
	return "так" if value else "ні"
