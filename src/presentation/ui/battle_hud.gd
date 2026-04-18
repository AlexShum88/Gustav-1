class_name BattleHUD
extends Control

const RegimentEditorPanel = preload("res://src/presentation/ui/regiment_editor_panel.gd")

signal order_type_selected(order_type: int)
signal policies_changed(policies: Dictionary)
signal order_cancelled()
signal debug_formation_selected(formation_state: int)
signal debug_fire_behavior_selected(fire_behavior: int)
signal debug_fire_requested()
signal debug_override_cleared()
signal pre_battle_start_requested()
signal editor_command_profile_selected(profile_id: StringName)
signal editor_banner_profile_selected(profile_id: StringName)
signal editor_add_company_requested(company_type: int)
signal editor_remove_company_requested(company_type: int)

var _top_summary: Label
var _selection_summary: RichTextLabel
var _order_summary: RichTextLabel
var _event_log: RichTextLabel
var _performance_label: RichTextLabel
var _policy_toggles: Dictionary = {}
var _order_buttons: Dictionary = {}
var _order_detail_panel: Panel
var _order_palette_panel: Panel
var _editor_panel: RegimentEditorPanel
var _pre_battle_active: bool = false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS
	_build_top_bar()
	_build_selected_panel()
	_build_order_detail_panel()
	_build_order_palette()
	_build_event_log()
	_build_performance_panel()
	_build_debug_panel()
	_build_editor_panel()


func set_snapshot(snapshot: Dictionary, selected_regiment: Dictionary, pending_order_type: int, render_stats: Dictionary = {}) -> void:
	var ui_channel: Dictionary = snapshot.get("channels", {}).get("ui", {})
	var top_bar: Dictionary = ui_channel.get("top_bar", {})
	var perf: Dictionary = ui_channel.get("performance", {})
	_top_summary.text = "%s | Battalions %d | Baggage S %.0f%% / A %.0f%% | VP %.1f - %.1f | Convoys %d" % [
		top_bar.get("army_name", "Army"),
		int(top_bar.get("active_battalions", top_bar.get("active_regiments", 0))),
		float(top_bar.get("baggage_supply", 0.0)) * 100.0,
		float(top_bar.get("baggage_ammo", 0.0)) * 100.0,
		float(top_bar.get("own_victory_points", 0.0)),
		float(top_bar.get("enemy_victory_points", 0.0)),
		int(top_bar.get("active_convoys", 0)),
	]

	var selected_name := "No selection"
	var selected_body := "Click a friendly battalion block to inspect it.\nOrders route to its brigade HQ."
	if not selected_regiment.is_empty():
		var debug_formation_state: int = int(selected_regiment.get("debug_forced_formation_state", -1))
		var debug_fire_behavior: int = int(selected_regiment.get("debug_forced_fire_behavior", -1))
		var debug_label: String = "None" if debug_formation_state < 0 else SimTypes.regiment_formation_state_name(debug_formation_state)
		var debug_fire_label: String = "None" if debug_fire_behavior < 0 else SimTypes.regiment_fire_behavior_name(debug_fire_behavior)
		var formation_label: String = SimTypes.regiment_formation_state_name(int(selected_regiment.get("formation_state", SimTypes.RegimentFormationState.DEFAULT)))
		selected_name = selected_regiment.get("true_name", selected_regiment.get("display_name", "Selected Battalion"))
		selected_body = "Status: %s\nOrder: %s\nRole: %s\nCommander: %s (%s)\nBanner: %s\nStrength: %d\nStands: %d\nEditor companies: %d / %d\nFormation: %s\nFire Behavior: %s\nDebug Formation: %s\nDebug Fire: %s" % [
			selected_regiment.get("status_text", "Idle"),
			selected_regiment.get("order_label", "Idle"),
			SimTypes.brigade_role_name(int(selected_regiment.get("brigade_role", SimTypes.BrigadeRole.CENTER))),
			selected_regiment.get("commander_name", ""),
			selected_regiment.get("commander_profile_name", ""),
			selected_regiment.get("banner_profile_name", ""),
			int(selected_regiment.get("strength", 0)),
			int(selected_regiment.get("stand_count", 0)),
			int(selected_regiment.get("editor_company_count", selected_regiment.get("company_count", 0))),
			int(selected_regiment.get("max_editor_company_capacity", selected_regiment.get("max_company_capacity", 0))),
			formation_label,
			SimTypes.regiment_fire_behavior_name(int(selected_regiment.get("fire_behavior", SimTypes.RegimentFireBehavior.NONE))),
			debug_label,
			debug_fire_label,
		]
	_selection_summary.text = "[b]%s[/b]\n%s" % [selected_name, selected_body]
	if _editor_panel != null:
		_editor_panel.set_editor_state(selected_regiment, _pre_battle_active)

	var pending_text := "Choose an order, set policies, then define the order on the battlefield."
	if pending_order_type != SimTypes.OrderType.NONE:
		var gesture_help: String = "Draw an arrow with two left-clicks." if pending_order_type in [SimTypes.OrderType.MOVE, SimTypes.OrderType.MARCH, SimTypes.OrderType.ATTACK, SimTypes.OrderType.PATROL] else "Draw a defensive line with two left-clicks."
		pending_text = "Pending: [b]%s[/b]\n%s\nPolicies:\n- Road column: %s\n- Deploy on contact: %s\n- Retreat on flank collapse: %s\n- Hold reserve: %s" % [
			SimTypes.order_type_name(pending_order_type),
			gesture_help,
			_yes_no(_policy_toggles["road_column"].button_pressed),
			_yes_no(_policy_toggles["deploy_on_contact"].button_pressed),
			_yes_no(_policy_toggles["retreat_on_flank_collapse"].button_pressed),
			_yes_no(_policy_toggles["hold_reserve"].button_pressed),
		]
	_order_summary.text = pending_text

	var event_lines: Array = ui_channel.get("recent_events", [])
	_event_log.text = "[b]Dispatch log[/b]\n%s" % "\n".join(event_lines)
	var units_perf: Dictionary = render_stats.get("units", {})
	var units_mode: String = String(render_stats.get("units_mode", "detailed"))
	var visible_unit_blocks: int = int(units_perf.get("visible_regiments", units_perf.get("visible_entries", 0)))
	var casualty_perf: Dictionary = render_stats.get("casualties", {})
	var fog_perf: Dictionary = render_stats.get("fog", {})
	var marker_perf: Dictionary = render_stats.get("markers", {})
	var selection_perf: Dictionary = render_stats.get("selection", {})
	_performance_label.text = "[b]Perf[/b]\nSnapshot %.2f ms\nApply %.2f ms / Units sync %.2f ms / Selection %.2f ms\nBehavior %.2f ms / Combat %.2f ms (frame %.2f, contacts %d)\nVisibility %.2f ms\nLogistics %.2f ms\nAI %.2f ms\nUnits draw %.2f ms (%d vis, %s)\nSelection draw %.2f ms (%d)\nCorpses draw %.2f ms / update %.2f ms (%d corpses, %d vis cells, %d rebuilt)\nFog draw %.2f ms (%d cells)\nMarkers draw %.2f ms\nBats %d (%d vis)  Active combat %d" % [
		float(perf.get("snapshot_build_ms", 0.0)),
		float(render_stats.get("apply_ms", 0.0)),
		float(render_stats.get("units_sync_ms", 0.0)),
		float(render_stats.get("selection_sync_ms", 0.0)),
		float(perf.get("behavior_ms", 0.0)),
		float(perf.get("combat_ms", 0.0)),
		float(perf.get("combat_frame_ms", 0.0)),
		int(perf.get("combat_contacts", 0)),
		float(perf.get("visibility_ms", 0.0)),
		float(perf.get("logistics_ms", 0.0)),
		float(perf.get("ai_ms", 0.0)),
		float(units_perf.get("draw_ms", 0.0)),
		visible_unit_blocks,
		units_mode,
		float(selection_perf.get("draw_ms", 0.0)),
		int(selection_perf.get("outlines", 0)),
		float(casualty_perf.get("draw_ms", 0.0)),
		float(casualty_perf.get("update_ms", 0.0)),
		int(casualty_perf.get("corpses", 0)),
		int(casualty_perf.get("visible_cells", 0)),
		int(casualty_perf.get("rebuilt_cells", 0)),
		float(fog_perf.get("draw_ms", 0.0)),
		int(fog_perf.get("visible_cells", 0)),
		float(marker_perf.get("draw_ms", 0.0)),
		int(perf.get("battalions", perf.get("regiments", 0))),
		int(perf.get("visible_battalions", perf.get("visible_regiments", 0))),
		int(perf.get("combat_active_battalions", perf.get("combat_active_regiments", 0))),
	]
	_update_order_button_state(pending_order_type)


func get_policy_state() -> Dictionary:
	return {
		"road_column": _policy_toggles["road_column"].button_pressed,
		"deploy_on_contact": _policy_toggles["deploy_on_contact"].button_pressed,
		"retreat_on_flank_collapse": _policy_toggles["retreat_on_flank_collapse"].button_pressed,
		"hold_reserve": _policy_toggles["hold_reserve"].button_pressed,
	}


func set_pre_battle_active(value: bool) -> void:
	_pre_battle_active = value
	if _order_detail_panel != null:
		_order_detail_panel.visible = not value
	if _order_palette_panel != null:
		_order_palette_panel.visible = not value
	if _editor_panel != null:
		_editor_panel.visible = value


func _build_top_bar() -> void:
	var panel := _make_panel(Vector2(12.0, 10.0), Vector2(1140.0, 54.0))
	_top_summary = Label.new()
	_top_summary.position = Vector2(12.0, 8.0)
	_top_summary.size = Vector2(1110.0, 30.0)
	_top_summary.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	panel.add_child(_top_summary)


func _build_selected_panel() -> void:
	var panel := _make_panel(Vector2(12.0, 578.0), Vector2(320.0, 310.0))
	var title := _make_title("Selected Battalion")
	panel.add_child(title)
	_selection_summary = RichTextLabel.new()
	_selection_summary.position = Vector2(12.0, 36.0)
	_selection_summary.size = Vector2(292.0, 262.0)
	_selection_summary.bbcode_enabled = true
	_selection_summary.scroll_active = true
	panel.add_child(_selection_summary)


func _build_order_detail_panel() -> void:
	var panel := _make_panel(Vector2(420.0, 716.0), Vector2(420.0, 172.0))
	_order_detail_panel = panel
	var title := _make_title("Order Detail")
	panel.add_child(title)
	_order_summary = RichTextLabel.new()
	_order_summary.position = Vector2(12.0, 36.0)
	_order_summary.size = Vector2(220.0, 124.0)
	_order_summary.bbcode_enabled = true
	_order_summary.scroll_active = false
	panel.add_child(_order_summary)

	var toggle_names := [
		["road_column", "Road column"],
		["deploy_on_contact", "Deploy on contact"],
		["retreat_on_flank_collapse", "Retreat if flank collapses"],
		["hold_reserve", "Hold reserve"],
	]
	var y := 38.0
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
	cancel_button.text = "Cancel Order"
	cancel_button.position = Vector2(245.0, 132.0)
	cancel_button.pressed.connect(func() -> void:
		emit_signal("order_cancelled")
	)
	panel.add_child(cancel_button)


func _build_order_palette() -> void:
	var panel := _make_panel(Vector2(1280.0, 612.0), Vector2(308.0, 276.0))
	_order_palette_panel = panel
	var title := _make_title("Order Palette")
	panel.add_child(title)

	var order_types := [
		SimTypes.OrderType.MOVE,
		SimTypes.OrderType.MARCH,
		SimTypes.OrderType.ATTACK,
		SimTypes.OrderType.DEFEND,
		SimTypes.OrderType.PATROL,
		SimTypes.OrderType.HOLD,
	]
	var y := 40.0
	for order_type in order_types:
		var button := Button.new()
		button.position = Vector2(16.0, y)
		button.size = Vector2(276.0, 32.0)
		button.text = SimTypes.order_type_name(order_type)
		button.pressed.connect(_on_order_button_pressed.bind(order_type))
		panel.add_child(button)
		_order_buttons[order_type] = button
		y += 38.0


func _build_event_log() -> void:
	var panel := _make_panel(Vector2(1235.0, 10.0), Vector2(353.0, 240.0))
	var title := _make_title("Dispatch Log")
	panel.add_child(title)
	_event_log = RichTextLabel.new()
	_event_log.position = Vector2(12.0, 36.0)
	_event_log.size = Vector2(329.0, 192.0)
	_event_log.bbcode_enabled = true
	_event_log.scroll_active = true
	panel.add_child(_event_log)


func _build_performance_panel() -> void:
	var panel := _make_panel(Vector2(1235.0, 262.0), Vector2(300.0, 244.0))
	var title := _make_title("Perf")
	panel.add_child(title)
	_performance_label = RichTextLabel.new()
	_performance_label.position = Vector2(12.0, 36.0)
	_performance_label.size = Vector2(276.0, 196.0)
	_performance_label.bbcode_enabled = true
	_performance_label.scroll_active = true
	panel.add_child(_performance_label)


func _build_debug_panel() -> void:
	var panel := _make_panel(Vector2(1235.0, 454.0), Vector2(220.0, 370.0))
	var title := _make_title("Formation / Fire Debug")
	panel.add_child(title)
	_add_debug_button(panel, "Line", 34.0, _emit_debug_line)
	_add_debug_button(panel, "March Column", 64.0, _emit_debug_march_column)
	_add_debug_button(panel, "Protected", 94.0, _emit_debug_protected)
	_add_debug_button(panel, "Musketeer Line", 124.0, _emit_debug_musketeer_line)
	_add_debug_button(panel, "Tercia", 154.0, _emit_debug_tercia)
	var fire_title := _make_title("Fire Behavior")
	fire_title.position = Vector2(12.0, 190.0)
	panel.add_child(fire_title)
	_add_debug_button(panel, "Volley", 216.0, _emit_debug_volley)
	_add_debug_button(panel, "Countermarch", 246.0, _emit_debug_countermarch)
	_add_debug_button(panel, "Caracole", 276.0, _emit_debug_caracole)
	_add_debug_button(panel, "Test Fire", 306.0, _emit_debug_fire)
	_add_debug_button(panel, "Clear Debug", 336.0, _emit_debug_clear)


func _build_editor_panel() -> void:
	_editor_panel = RegimentEditorPanel.new()
	_editor_panel.position = Vector2(995.0, 454.0)
	_editor_panel.size = Vector2(228.0, 370.0)
	_editor_panel.start_battle_requested.connect(func() -> void:
		emit_signal("pre_battle_start_requested")
	)
	_editor_panel.command_profile_selected.connect(func(profile_id: StringName) -> void:
		emit_signal("editor_command_profile_selected", profile_id)
	)
	_editor_panel.banner_profile_selected.connect(func(profile_id: StringName) -> void:
		emit_signal("editor_banner_profile_selected", profile_id)
	)
	_editor_panel.add_company_requested.connect(func(company_type: int) -> void:
		emit_signal("editor_add_company_requested", company_type)
	)
	_editor_panel.remove_company_requested.connect(func(company_type: int) -> void:
		emit_signal("editor_remove_company_requested", company_type)
	)
	add_child(_editor_panel)
	_editor_panel.visible = _pre_battle_active


func _add_debug_button(panel: Panel, text_value: String, y: float, callback: Callable) -> void:
	var button := Button.new()
	button.position = Vector2(12.0, y)
	button.size = Vector2(196.0, 28.0)
	button.text = text_value
	button.pressed.connect(callback)
	panel.add_child(button)


func _emit_debug_line() -> void:
	emit_signal("debug_formation_selected", SimTypes.RegimentFormationState.DEFAULT)


func _emit_debug_march_column() -> void:
	emit_signal("debug_formation_selected", SimTypes.RegimentFormationState.MARCH_COLUMN)


func _emit_debug_protected() -> void:
	emit_signal("debug_formation_selected", SimTypes.RegimentFormationState.PROTECTED)


func _emit_debug_musketeer_line() -> void:
	emit_signal("debug_formation_selected", SimTypes.RegimentFormationState.MUSKETEER_LINE)


func _emit_debug_tercia() -> void:
	emit_signal("debug_formation_selected", SimTypes.RegimentFormationState.TERCIA)


func _emit_debug_volley() -> void:
	emit_signal("debug_fire_behavior_selected", SimTypes.RegimentFireBehavior.VOLLEY)


func _emit_debug_countermarch() -> void:
	emit_signal("debug_fire_behavior_selected", SimTypes.RegimentFireBehavior.COUNTERMARCH)


func _emit_debug_caracole() -> void:
	emit_signal("debug_fire_behavior_selected", SimTypes.RegimentFireBehavior.CARACOLE)


func _emit_debug_fire() -> void:
	emit_signal("debug_fire_requested")


func _emit_debug_clear() -> void:
	emit_signal("debug_override_cleared")


func _make_panel(position_value: Vector2, size_value: Vector2) -> Panel:
	var panel := Panel.new()
	panel.position = position_value
	panel.size = size_value
	panel.self_modulate = Color(0.1, 0.12, 0.16, 0.84)
	add_child(panel)
	return panel


func _make_title(text_value: String) -> Label:
	var label := Label.new()
	label.position = Vector2(12.0, 8.0)
	label.text = text_value
	label.add_theme_color_override("font_color", Color(0.95, 0.94, 0.88))
	return label


func _on_order_button_pressed(order_type: int) -> void:
	emit_signal("order_type_selected", order_type)


func _on_policy_toggle_changed(_pressed: bool) -> void:
	emit_signal("policies_changed", get_policy_state())


func _update_order_button_state(active_order_type: int) -> void:
	for order_type in _order_buttons.keys():
		var button: Button = _order_buttons[order_type]
		button.modulate = Color(1.0, 1.0, 1.0) if order_type != active_order_type else Color(0.92, 0.9, 0.56)


func _yes_no(value: bool) -> String:
	return "Yes" if value else "No"
