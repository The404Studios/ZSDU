extends CanvasLayer
class_name FpsHud
## FpsHud - First-person shooter HUD based on design mockup
##
## Layout:
## - Bottom-left: Mini map (oval), Buffs, Stamina bar, HP bar
## - Bottom-center: Weapon slots (primary, secondary, melee)
## - Bottom-right: Ammo counter (50/128) with weapon name
## - Center: Crosshair

signal damage_taken(amount: float)
signal health_changed(current: float, max_value: float)
signal stamina_changed(current: float, max_value: float)
signal ammo_changed(current: int, reserve: int)

# Root container
var root: Control

# ============================================
# BOTTOM-LEFT: Mini Map, Buffs, HP, Stamina
# ============================================
var bottom_left_container: Control
var mini_map_container: Control
var mini_map_frame: Control
var buffs_container: HBoxContainer
var stamina_bar: ProgressBar
var stamina_bg: ColorRect
var hp_bar: ProgressBar
var hp_bg: ColorRect
var hp_label: Label

# ============================================
# BOTTOM-CENTER: Weapon Slots
# ============================================
var weapon_slots_container: HBoxContainer
var weapon_slot_buttons: Array[Button] = []
var active_slot: int = 0

# ============================================
# BOTTOM-RIGHT: Ammo Display
# ============================================
var ammo_container: Control
var ammo_current_label: Label
var ammo_reserve_label: Label
var weapon_name_label: Label

# ============================================
# CENTER: Crosshair
# ============================================
var crosshair_container: Control
var crosshair_lines: Array[ColorRect] = []

# ============================================
# VIGNETTE (damage/low health)
# ============================================
var vignette: ColorRect

# State
var current_health := 100.0
var max_health := 100.0
var current_stamina := 100.0
var max_stamina := 100.0
var current_ammo := 50
var reserve_ammo := 128
var current_weapon_name := "VECTOR"

# Buff tracking
var active_buffs: Array[Dictionary] = []

# XP popup tracking
var xp_popup_container: Control
var xp_popups: Array[Dictionary] = []

# Wave display
var wave_container: Control
var wave_label: Label
var current_wave: int = 0

# Kill stats display
var stats_container: Control
var kills_label: Label
var zombies_remaining_label: Label
var player_kills: int = 0

# Extraction display
var extraction_container: Control
var extraction_label: Label
var extraction_progress: ProgressBar
var extraction_active: bool = false
var extraction_time: float = 0.0
var extraction_max_time: float = 5.0

# Death/Game Over display
var death_screen: Control
var game_over_screen: Control
var game_over_title: Label
var game_over_stats: Label
var is_dead: bool = false

# Connection tracking
var _connected_player: PlayerController = null


func _ready() -> void:
	layer = 10
	_build_ui()
	_connect_network_signals()


func _process(delta: float) -> void:
	_update_smooth_bars(delta)
	_update_vignette(delta)
	_update_from_player()
	_update_buffs()
	_update_xp_popups(delta)
	_update_extraction(delta)
	_update_damage_numbers(delta)
	_update_combo(delta)
	_update_minimap_from_player()


# ============================================
# UI CONSTRUCTION
# ============================================

func _build_ui() -> void:
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_build_bottom_left()
	_build_weapon_slots()
	_build_ammo_display()
	_build_crosshair()
	_build_vignette()
	_build_wave_display()
	_build_stats_display()
	_build_extraction_display()
	_build_death_screen()
	_build_game_over_screen()
	_build_xp_popup_container()
	_build_damage_numbers()
	_build_combo_display()
	_setup_minimap()


func _build_bottom_left() -> void:
	bottom_left_container = Control.new()
	bottom_left_container.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	bottom_left_container.position = Vector2(15, -180)
	bottom_left_container.size = Vector2(350, 170)
	bottom_left_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bottom_left_container)

	# Mini Map (oval frame)
	_build_mini_map()

	# Buffs row (next to mini map)
	_build_buffs()

	# Stamina bar
	_build_stamina_bar()

	# HP bar
	_build_hp_bar()


func _build_mini_map() -> void:
	mini_map_container = Control.new()
	mini_map_container.position = Vector2(0, 0)
	mini_map_container.size = Vector2(100, 80)
	mini_map_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom_left_container.add_child(mini_map_container)

	# Oval background (using ColorRect with shader would be ideal, but we'll fake it)
	var bg := ColorRect.new()
	bg.position = Vector2(5, 5)
	bg.size = Vector2(90, 70)
	bg.color = Color(0.1, 0.1, 0.12, 0.85)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mini_map_container.add_child(bg)

	# Border
	var border := ColorRect.new()
	border.position = Vector2(3, 3)
	border.size = Vector2(94, 74)
	border.color = Color(0.3, 0.3, 0.35, 0.8)
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mini_map_container.add_child(border)
	border.z_index = -1

	# Inner area for actual mini map content
	mini_map_frame = Control.new()
	mini_map_frame.position = Vector2(8, 8)
	mini_map_frame.size = Vector2(84, 64)
	mini_map_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mini_map_container.add_child(mini_map_frame)

	# "MINI MAP" label (placeholder)
	var label := Label.new()
	label.text = "MINI\nMAP"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_preset(Control.PRESET_CENTER)
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mini_map_frame.add_child(label)


func _build_buffs() -> void:
	buffs_container = HBoxContainer.new()
	buffs_container.position = Vector2(105, 20)
	buffs_container.add_theme_constant_override("separation", 5)
	buffs_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom_left_container.add_child(buffs_container)

	# Label
	var label := Label.new()
	label.text = "- BUFFS"
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	buffs_container.add_child(label)

	# Create buff slot placeholders
	for i in range(3):
		var slot := ColorRect.new()
		slot.custom_minimum_size = Vector2(24, 24)
		slot.color = Color(0.15, 0.15, 0.18, 0.7)
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		buffs_container.add_child(slot)


func _build_stamina_bar() -> void:
	# Stamina label
	var stam_label := Label.new()
	stam_label.position = Vector2(105, 55)
	stam_label.text = "STAMINA"
	stam_label.add_theme_font_size_override("font_size", 11)
	stam_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
	stam_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom_left_container.add_child(stam_label)

	# Stamina bar background
	stamina_bg = ColorRect.new()
	stamina_bg.position = Vector2(105, 70)
	stamina_bg.size = Vector2(220, 18)
	stamina_bg.color = Color(0.1, 0.1, 0.12, 0.85)
	stamina_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom_left_container.add_child(stamina_bg)

	# Stamina bar
	stamina_bar = ProgressBar.new()
	stamina_bar.position = Vector2(107, 72)
	stamina_bar.size = Vector2(216, 14)
	stamina_bar.max_value = 100
	stamina_bar.value = 100
	stamina_bar.show_percentage = false
	stamina_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_style_bar(stamina_bar, Color(0.25, 0.45, 0.7))
	bottom_left_container.add_child(stamina_bar)


func _build_hp_bar() -> void:
	# HP label
	var hp_title := Label.new()
	hp_title.position = Vector2(105, 95)
	hp_title.text = "HP"
	hp_title.add_theme_font_size_override("font_size", 11)
	hp_title.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
	hp_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom_left_container.add_child(hp_title)

	# HP bar outer frame
	var hp_frame := ColorRect.new()
	hp_frame.position = Vector2(103, 108)
	hp_frame.size = Vector2(224, 35)
	hp_frame.color = Color(0.2, 0.2, 0.22, 0.9)
	hp_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom_left_container.add_child(hp_frame)

	# HP bar background
	hp_bg = ColorRect.new()
	hp_bg.position = Vector2(105, 110)
	hp_bg.size = Vector2(220, 31)
	hp_bg.color = Color(0.1, 0.1, 0.12, 0.95)
	hp_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom_left_container.add_child(hp_bg)

	# HP bar
	hp_bar = ProgressBar.new()
	hp_bar.position = Vector2(107, 112)
	hp_bar.size = Vector2(216, 27)
	hp_bar.max_value = 100
	hp_bar.value = 100
	hp_bar.show_percentage = false
	hp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_style_bar(hp_bar, Color(0.7, 0.25, 0.25))
	bottom_left_container.add_child(hp_bar)

	# HP value label (centered on bar)
	hp_label = Label.new()
	hp_label.position = Vector2(107, 112)
	hp_label.size = Vector2(216, 27)
	hp_label.text = "100"
	hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hp_label.add_theme_font_size_override("font_size", 16)
	hp_label.add_theme_color_override("font_color", Color.WHITE)
	hp_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom_left_container.add_child(hp_label)


func _build_weapon_slots() -> void:
	weapon_slots_container = HBoxContainer.new()
	weapon_slots_container.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	weapon_slots_container.position = Vector2(-150, -60)
	weapon_slots_container.add_theme_constant_override("separation", 10)
	weapon_slots_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(weapon_slots_container)

	# Create weapon slot buttons
	var slot_data := [
		{"name": "KRISS\nVECTOR", "key": "1"},
		{"name": "KNIFE", "key": "2"},
	]

	for i in range(slot_data.size()):
		var slot := _create_weapon_slot(slot_data[i].name, slot_data[i].key, i)
		weapon_slots_container.add_child(slot)
		weapon_slot_buttons.append(slot)

	# Set first slot as active
	_set_active_weapon_slot(0)


func _create_weapon_slot(weapon_name: String, key: String, index: int) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(90, 55)
	btn.text = weapon_name
	btn.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Style
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.14, 0.9)
	style.border_color = Color(0.3, 0.3, 0.35)
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	btn.add_theme_stylebox_override("normal", style)

	var style_active := style.duplicate()
	style_active.border_color = Color(0.8, 0.7, 0.3)
	style_active.bg_color = Color(0.18, 0.16, 0.12, 0.95)
	btn.add_theme_stylebox_override("hover", style_active)

	btn.add_theme_font_size_override("font_size", 12)

	return btn


func _set_active_weapon_slot(slot: int) -> void:
	active_slot = slot

	for i in range(weapon_slot_buttons.size()):
		var btn := weapon_slot_buttons[i]
		var style: StyleBoxFlat

		if i == slot:
			style = StyleBoxFlat.new()
			style.bg_color = Color(0.18, 0.16, 0.12, 0.95)
			style.border_color = Color(0.9, 0.75, 0.3)
			style.set_border_width_all(2)
			style.set_corner_radius_all(4)
		else:
			style = StyleBoxFlat.new()
			style.bg_color = Color(0.12, 0.12, 0.14, 0.9)
			style.border_color = Color(0.3, 0.3, 0.35)
			style.set_border_width_all(2)
			style.set_corner_radius_all(4)

		btn.add_theme_stylebox_override("normal", style)


func _build_ammo_display() -> void:
	ammo_container = Control.new()
	ammo_container.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	ammo_container.position = Vector2(-160, -100)
	ammo_container.size = Vector2(140, 80)
	ammo_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(ammo_container)

	# Background
	var bg := ColorRect.new()
	bg.size = Vector2(140, 80)
	bg.color = Color(0.1, 0.1, 0.12, 0.85)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ammo_container.add_child(bg)

	# Border
	var border := ColorRect.new()
	border.position = Vector2(-2, -2)
	border.size = Vector2(144, 84)
	border.color = Color(0.25, 0.25, 0.28, 0.8)
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	border.z_index = -1
	ammo_container.add_child(border)

	# Ammo display: "50/128"
	var ammo_row := HBoxContainer.new()
	ammo_row.position = Vector2(10, 10)
	ammo_row.add_theme_constant_override("separation", 0)
	ammo_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ammo_container.add_child(ammo_row)

	ammo_current_label = Label.new()
	ammo_current_label.text = "50"
	ammo_current_label.add_theme_font_size_override("font_size", 32)
	ammo_current_label.add_theme_color_override("font_color", Color.WHITE)
	ammo_current_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ammo_row.add_child(ammo_current_label)

	var separator := Label.new()
	separator.text = "/"
	separator.add_theme_font_size_override("font_size", 24)
	separator.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55))
	separator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ammo_row.add_child(separator)

	ammo_reserve_label = Label.new()
	ammo_reserve_label.text = "128"
	ammo_reserve_label.add_theme_font_size_override("font_size", 20)
	ammo_reserve_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
	ammo_reserve_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	ammo_reserve_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ammo_row.add_child(ammo_reserve_label)

	# Weapon name below
	weapon_name_label = Label.new()
	weapon_name_label.position = Vector2(10, 50)
	weapon_name_label.size = Vector2(120, 25)
	weapon_name_label.text = "VECTOR"
	weapon_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	weapon_name_label.add_theme_font_size_override("font_size", 14)
	weapon_name_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
	weapon_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ammo_container.add_child(weapon_name_label)


func _build_crosshair() -> void:
	crosshair_container = Control.new()
	crosshair_container.set_anchors_preset(Control.PRESET_CENTER)
	crosshair_container.position = Vector2(-20, -20)
	crosshair_container.size = Vector2(40, 40)
	crosshair_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(crosshair_container)

	# Center dot
	var dot := ColorRect.new()
	dot.position = Vector2(18, 18)
	dot.size = Vector2(4, 4)
	dot.color = Color.WHITE
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crosshair_container.add_child(dot)

	# Lines
	var line_length := 10.0
	var line_width := 2.0
	var gap := 5.0

	# Top
	var top := ColorRect.new()
	top.position = Vector2(19, 20 - gap - line_length)
	top.size = Vector2(line_width, line_length)
	top.color = Color.WHITE
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crosshair_container.add_child(top)
	crosshair_lines.append(top)

	# Bottom
	var bottom := ColorRect.new()
	bottom.position = Vector2(19, 20 + gap)
	bottom.size = Vector2(line_width, line_length)
	bottom.color = Color.WHITE
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crosshair_container.add_child(bottom)
	crosshair_lines.append(bottom)

	# Left
	var left := ColorRect.new()
	left.position = Vector2(20 - gap - line_length, 19)
	left.size = Vector2(line_length, line_width)
	left.color = Color.WHITE
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crosshair_container.add_child(left)
	crosshair_lines.append(left)

	# Right
	var right := ColorRect.new()
	right.position = Vector2(20 + gap, 19)
	right.size = Vector2(line_length, line_width)
	right.color = Color.WHITE
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crosshair_container.add_child(right)
	crosshair_lines.append(right)


func _build_vignette() -> void:
	vignette = ColorRect.new()
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.color = Color(0.5, 0, 0, 0)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(vignette)


func _style_bar(bar: ProgressBar, fill_color: Color) -> void:
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0.08, 0.08, 0.1, 0.9)
	bg_style.set_corner_radius_all(2)
	bar.add_theme_stylebox_override("background", bg_style)

	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = fill_color
	fill_style.set_corner_radius_all(2)
	bar.add_theme_stylebox_override("fill", fill_style)


# ============================================
# UPDATE FUNCTIONS
# ============================================

func _update_smooth_bars(_delta: float) -> void:
	# Smooth health bar
	hp_bar.value = lerpf(hp_bar.value, current_health, 0.15)

	# Smooth stamina bar
	stamina_bar.value = lerpf(stamina_bar.value, current_stamina, 0.15)


func _update_vignette(_delta: float) -> void:
	var health_percent := current_health / max_health if max_health > 0 else 1.0

	if health_percent < 0.3:
		var intensity := (0.3 - health_percent) / 0.3 * 0.25
		if health_percent < 0.15:
			intensity += sin(Time.get_ticks_msec() / 200.0) * 0.05
		vignette.color.a = lerpf(vignette.color.a, intensity, 0.1)
	else:
		vignette.color.a = lerpf(vignette.color.a, 0.0, 0.1)


func _update_from_player() -> void:
	# Find local player
	var local_peer := NetworkManager.local_peer_id if NetworkManager else 1
	if GameState and local_peer in GameState.players:
		var player: Node3D = GameState.players[local_peer]
		if player is PlayerController:
			var pc := player as PlayerController
			_sync_from_player(pc)


func _sync_from_player(player: PlayerController) -> void:
	# One-time connection to player's systems
	if _connected_player != player:
		_connected_player = player
		if player.attribute_system:
			connect_to_attribute_system(player.attribute_system)

	# Health
	if current_health != player.health or max_health != player.max_health:
		set_health(player.health, player.max_health)

	# Stamina
	if player.movement_controller:
		var mc := player.movement_controller
		if current_stamina != mc.stamina or max_stamina != mc.max_stamina:
			set_stamina(mc.stamina, mc.max_stamina)

	# Weapon info
	var weapon_manager := player.get_weapon_manager()
	if weapon_manager:
		var ammo_info := weapon_manager.get_ammo_info()
		var weapon_info := weapon_manager.get_current_weapon_info()
		set_ammo(ammo_info.get("current", 0), ammo_info.get("reserve", 0))
		set_weapon_name(weapon_info.get("name", "UNKNOWN"))


# ============================================
# PUBLIC API
# ============================================

func set_health(current: float, max_val: float) -> void:
	var old_health := current_health
	current_health = current
	max_health = max_val

	hp_bar.max_value = max_val
	hp_label.text = str(int(current))

	# Flash on damage
	if current < old_health:
		_flash_damage()

	# Update HP bar color based on health
	var fill_style := hp_bar.get_theme_stylebox("fill") as StyleBoxFlat
	if fill_style:
		var percent: float = current / max_val if max_val > 0 else 0.0
		if percent <= 0.2:
			fill_style.bg_color = Color(0.9, 0.2, 0.2)
		elif percent <= 0.5:
			fill_style.bg_color = Color(0.9, 0.5, 0.2)
		else:
			fill_style.bg_color = Color(0.7, 0.25, 0.25)


func set_stamina(current: float, max_val: float) -> void:
	current_stamina = current
	max_stamina = max_val
	stamina_bar.max_value = max_val


func set_ammo(current: int, reserve: int) -> void:
	current_ammo = current
	reserve_ammo = reserve

	ammo_current_label.text = str(current)
	ammo_reserve_label.text = str(reserve)

	# Color based on ammo level
	if current <= 0:
		ammo_current_label.add_theme_color_override("font_color", Color.RED)
	elif current <= 10:
		ammo_current_label.add_theme_color_override("font_color", Color.ORANGE)
	else:
		ammo_current_label.add_theme_color_override("font_color", Color.WHITE)


func set_weapon_name(weapon_name: String) -> void:
	current_weapon_name = weapon_name
	weapon_name_label.text = weapon_name


func set_weapon_slot(slot: int) -> void:
	_set_active_weapon_slot(slot)


func add_buff(buff_id: String, icon_color: Color, duration: float) -> void:
	# Find empty buff slot or replace oldest
	var slot_idx := active_buffs.size()
	if slot_idx >= 3:
		slot_idx = 0  # Replace first

	# Add buff to tracking
	if slot_idx < active_buffs.size():
		active_buffs[slot_idx] = {"id": buff_id, "color": icon_color, "expires": Time.get_ticks_msec() / 1000.0 + duration}
	else:
		active_buffs.append({"id": buff_id, "color": icon_color, "expires": Time.get_ticks_msec() / 1000.0 + duration})

	# Update visual
	_update_buff_visuals()


func _update_buff_visuals() -> void:
	# Get buff slot ColorRects (skip first child which is the label)
	var idx := 0
	for i in range(1, buffs_container.get_child_count()):
		var slot := buffs_container.get_child(i) as ColorRect
		if slot and idx < active_buffs.size():
			slot.color = active_buffs[idx].color
			idx += 1
		elif slot:
			slot.color = Color(0.15, 0.15, 0.18, 0.7)


func _flash_damage() -> void:
	# Flash HP bar
	var tween := hp_bar.create_tween()
	tween.tween_property(hp_bar, "modulate", Color(2, 0.5, 0.5), 0.05)
	tween.tween_property(hp_bar, "modulate", Color.WHITE, 0.15)

	# Flash vignette
	var v_tween := vignette.create_tween()
	v_tween.tween_property(vignette, "color:a", 0.4, 0.05)
	v_tween.tween_property(vignette, "color:a", 0.0, 0.3)


func show_hit_marker(is_kill: bool = false) -> void:
	# Flash crosshair
	var color := Color.RED if is_kill else Color.YELLOW
	for line in crosshair_lines:
		var tween := line.create_tween()
		tween.tween_property(line, "color", color, 0.05)
		tween.tween_property(line, "color", Color.WHITE, 0.15)


func expand_crosshair(amount: float = 1.0) -> void:
	var expansion := 4.0 * amount
	for i in range(crosshair_lines.size()):
		var line := crosshair_lines[i]
		var tween := line.create_tween()
		var direction := Vector2.ZERO
		match i:
			0: direction = Vector2(0, -expansion)
			1: direction = Vector2(0, expansion)
			2: direction = Vector2(-expansion, 0)
			3: direction = Vector2(expansion, 0)

		tween.tween_property(line, "position", line.position + direction, 0.03)
		tween.tween_property(line, "position", line.position, 0.15)


## Connect to player's attribute system for buff display
func connect_to_attribute_system(attr_sys: AttributeSystem) -> void:
	if attr_sys:
		attr_sys.buff_applied.connect(_on_attribute_buff_applied)
		attr_sys.buff_expired.connect(_on_attribute_buff_expired)


func _on_attribute_buff_applied(buff_id: String, attribute: String, _amount: int) -> void:
	# Map attribute to color
	var color := Color(0.3, 0.8, 0.3)  # Default green
	match attribute:
		"Strength":
			color = Color(0.9, 0.3, 0.3)  # Red
		"Agility":
			color = Color(0.3, 0.9, 0.3)  # Green
		"Endurance":
			color = Color(0.9, 0.6, 0.2)  # Orange
		"Intellect":
			color = Color(0.3, 0.5, 0.9)  # Blue
		"Luck":
			color = Color(0.9, 0.8, 0.2)  # Gold

	add_buff(buff_id, color, 30.0)  # Default 30s display


func _on_attribute_buff_expired(buff_id: String) -> void:
	remove_buff(buff_id)


func remove_buff(buff_id: String) -> void:
	for i in range(active_buffs.size() - 1, -1, -1):
		if active_buffs[i].id == buff_id:
			active_buffs.remove_at(i)
			break
	_update_buff_visuals()


## Update buff timers (called each frame to expire old buffs)
func _update_buffs() -> void:
	var current_time := Time.get_ticks_msec() / 1000.0
	var changed := false

	for i in range(active_buffs.size() - 1, -1, -1):
		if active_buffs[i].expires <= current_time:
			active_buffs.remove_at(i)
			changed = true

	if changed:
		_update_buff_visuals()


# ============================================
# XP POPUP SYSTEM
# ============================================

func _connect_network_signals() -> void:
	if NetworkManager and NetworkManager.has_signal("xp_gained"):
		NetworkManager.xp_gained.connect(_on_xp_gained)


func _build_xp_popup_container() -> void:
	xp_popup_container = Control.new()
	xp_popup_container.set_anchors_preset(Control.PRESET_CENTER)
	xp_popup_container.position = Vector2(0, -150)
	xp_popup_container.size = Vector2(200, 100)
	xp_popup_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(xp_popup_container)


func _on_xp_gained(data: Dictionary) -> void:
	var amount: int = data.get("amount", 0)
	var source: String = data.get("source", "")
	var zombie_type: String = data.get("zombie_type", "")

	if amount > 0:
		show_xp_popup(amount, zombie_type)


func show_xp_popup(amount: int, source: String = "") -> void:
	# Create popup label
	var popup := Label.new()
	popup.text = "+%d XP" % amount
	if source != "":
		popup.text += " (%s)" % source

	popup.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	popup.add_theme_font_size_override("font_size", 18)
	popup.add_theme_color_override("font_color", Color(0.9, 0.8, 0.2))  # Gold color

	# Add shadow/outline
	popup.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	popup.add_theme_constant_override("shadow_offset_x", 2)
	popup.add_theme_constant_override("shadow_offset_y", 2)

	popup.position = Vector2(100 - popup.size.x / 2, 50)
	popup.mouse_filter = Control.MOUSE_FILTER_IGNORE
	xp_popup_container.add_child(popup)

	# Track popup for animation
	xp_popups.append({
		"label": popup,
		"lifetime": 0.0,
		"max_lifetime": 2.0
	})

	# Shift existing popups up
	for i in range(xp_popups.size() - 2, -1, -1):
		var existing: Dictionary = xp_popups[i]
		var label: Label = existing.label
		label.position.y -= 25


func _update_xp_popups(delta: float) -> void:
	for i in range(xp_popups.size() - 1, -1, -1):
		var popup: Dictionary = xp_popups[i]
		popup.lifetime += delta

		var label: Label = popup.label
		if not is_instance_valid(label):
			xp_popups.remove_at(i)
			continue

		# Fade out over time
		var progress: float = popup.lifetime / popup.max_lifetime
		label.modulate.a = 1.0 - progress

		# Float upward
		label.position.y -= delta * 30.0

		# Remove when done
		if popup.lifetime >= popup.max_lifetime:
			label.queue_free()
			xp_popups.remove_at(i)


# ============================================
# LEVEL UP DISPLAY
# ============================================

func show_level_up(new_level: int, attribute_points: int) -> void:
	# Create dramatic level up display
	var level_popup := Control.new()
	level_popup.set_anchors_preset(Control.PRESET_CENTER)
	level_popup.position = Vector2(-150, -50)
	level_popup.size = Vector2(300, 100)
	level_popup.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(level_popup)

	# Background
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.1, 0.1, 0.15, 0.9)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	level_popup.add_child(bg)

	# Border
	var border := ColorRect.new()
	border.set_anchors_preset(Control.PRESET_FULL_RECT)
	border.position = Vector2(-3, -3)
	border.size = Vector2(306, 106)
	border.color = Color(0.9, 0.8, 0.2, 0.8)  # Gold border
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	border.z_index = -1
	level_popup.add_child(border)

	# LEVEL UP text
	var title := Label.new()
	title.text = "LEVEL UP!"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.position.y = 10
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(0.9, 0.8, 0.2))  # Gold
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	level_popup.add_child(title)

	# Level number
	var level_label := Label.new()
	level_label.text = "Level %d" % new_level
	level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	level_label.set_anchors_preset(Control.PRESET_CENTER)
	level_label.position.y = 5
	level_label.add_theme_font_size_override("font_size", 20)
	level_label.add_theme_color_override("font_color", Color.WHITE)
	level_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	level_popup.add_child(level_label)

	# Attribute points
	var points_label := Label.new()
	points_label.text = "+3 Attribute Points" if attribute_points >= 3 else "+%d Total Points" % attribute_points
	points_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	points_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	points_label.position.y = -30
	points_label.add_theme_font_size_override("font_size", 14)
	points_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
	points_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	level_popup.add_child(points_label)

	# Animate scale in
	level_popup.scale = Vector2(0.5, 0.5)
	level_popup.pivot_offset = level_popup.size / 2

	var tween := create_tween()
	tween.tween_property(level_popup, "scale", Vector2(1.1, 1.1), 0.15).set_ease(Tween.EASE_OUT)
	tween.tween_property(level_popup, "scale", Vector2(1.0, 1.0), 0.1)
	tween.tween_interval(2.0)  # Hold for 2 seconds
	tween.tween_property(level_popup, "modulate:a", 0.0, 0.5)
	tween.tween_callback(level_popup.queue_free)


# ============================================
# WAVE DISPLAY
# ============================================

func _build_wave_display() -> void:
	wave_container = Control.new()
	wave_container.set_anchors_preset(Control.PRESET_TOP_WIDE)
	wave_container.position = Vector2(0, 10)
	wave_container.size = Vector2(200, 40)
	wave_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(wave_container)

	# Center the container
	wave_container.set_anchors_preset(Control.PRESET_CENTER_TOP)
	wave_container.position = Vector2(-100, 10)

	# Background
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.1, 0.1, 0.12, 0.8)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wave_container.add_child(bg)

	# Wave label
	wave_label = Label.new()
	wave_label.text = "WAVE 1"
	wave_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wave_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	wave_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	wave_label.add_theme_font_size_override("font_size", 20)
	wave_label.add_theme_color_override("font_color", Color(0.9, 0.8, 0.2))
	wave_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wave_container.add_child(wave_label)

	# Connect to GameState wave signal
	if GameState:
		GameState.wave_started.connect(_on_wave_started)


func _on_wave_started(wave_number: int, is_boss_wave: bool = false) -> void:
	current_wave = wave_number

	if is_boss_wave:
		wave_label.text = "BOSS WAVE %d" % wave_number
		wave_label.add_theme_color_override("font_color", Color(0.9, 0.2, 0.3))
	else:
		wave_label.text = "WAVE %d" % wave_number
		wave_label.add_theme_color_override("font_color", Color(0.9, 0.8, 0.2))

	# Reset kill counter for new wave (keep total kills)
	# Update zombies remaining from GameState
	if GameState:
		var remaining: int = GameState.wave_zombies_remaining
		zombies_remaining_label.text = "REMAINING: %d" % remaining

	# Flash effect
	var tween := wave_container.create_tween()
	tween.tween_property(wave_container, "modulate", Color(2, 2, 2), 0.1)
	tween.tween_property(wave_container, "modulate", Color.WHITE, 0.3)

	# Show wave announcement popup
	_show_wave_announcement(wave_number, is_boss_wave)


func _show_wave_announcement(wave_number: int, is_boss_wave: bool = false) -> void:
	var announce := Label.new()

	if is_boss_wave:
		announce.text = "BOSS WAVE %d" % wave_number
		announce.add_theme_color_override("font_color", Color(0.9, 0.2, 0.3))  # Red for boss
	else:
		announce.text = "WAVE %d" % wave_number
		announce.add_theme_color_override("font_color", Color(1, 0.9, 0.3))  # Gold for normal

	announce.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	announce.set_anchors_preset(Control.PRESET_CENTER)
	announce.position = Vector2(-200, -100)
	announce.size = Vector2(400, 100)
	announce.add_theme_font_size_override("font_size", 48 if not is_boss_wave else 56)
	announce.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	announce.add_theme_constant_override("shadow_offset_x", 3)
	announce.add_theme_constant_override("shadow_offset_y", 3)
	announce.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(announce)

	# Animate in and out
	announce.modulate.a = 0
	var tween := announce.create_tween()
	tween.tween_property(announce, "modulate:a", 1.0, 0.2)

	# Boss waves get extra dramatic effect
	if is_boss_wave:
		# Add screen shake effect by shaking the label
		for i in range(6):
			tween.tween_property(announce, "position:x", -200 + randf_range(-10, 10), 0.05)
		tween.tween_property(announce, "position:x", -200, 0.1)

	tween.tween_interval(1.5 if not is_boss_wave else 2.5)
	tween.tween_property(announce, "modulate:a", 0.0, 0.5)
	tween.tween_callback(announce.queue_free)

	# Show boss warning subtitle for boss waves
	if is_boss_wave:
		_show_boss_warning()


# ============================================
# STATS DISPLAY (Kills & Zombies Remaining)
# ============================================

func _build_stats_display() -> void:
	stats_container = Control.new()
	stats_container.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	stats_container.position = Vector2(-170, 10)
	stats_container.size = Vector2(160, 60)
	stats_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(stats_container)

	# Background
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.1, 0.1, 0.12, 0.8)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stats_container.add_child(bg)

	# Kills label
	kills_label = Label.new()
	kills_label.text = "KILLS: 0"
	kills_label.position = Vector2(10, 8)
	kills_label.size = Vector2(140, 20)
	kills_label.add_theme_font_size_override("font_size", 14)
	kills_label.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3))
	kills_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stats_container.add_child(kills_label)

	# Zombies remaining label
	zombies_remaining_label = Label.new()
	zombies_remaining_label.text = "REMAINING: 0"
	zombies_remaining_label.position = Vector2(10, 32)
	zombies_remaining_label.size = Vector2(140, 20)
	zombies_remaining_label.add_theme_font_size_override("font_size", 14)
	zombies_remaining_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
	zombies_remaining_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stats_container.add_child(zombies_remaining_label)

	# Connect to GameState zombie_killed signal
	if GameState:
		GameState.zombie_killed.connect(_on_zombie_killed)


func _on_zombie_killed(_zombie_id: int) -> void:
	player_kills += 1
	kills_label.text = "KILLS: %d" % player_kills

	# Update zombies remaining from GameState
	if GameState:
		var remaining: int = GameState.wave_zombies_remaining - GameState.wave_zombies_killed
		zombies_remaining_label.text = "REMAINING: %d" % maxi(remaining, 0)


func update_zombies_remaining(remaining: int) -> void:
	zombies_remaining_label.text = "REMAINING: %d" % remaining


# ============================================
# EXTRACTION DISPLAY
# ============================================

func _build_extraction_display() -> void:
	extraction_container = Control.new()
	extraction_container.set_anchors_preset(Control.PRESET_CENTER)
	extraction_container.position = Vector2(-150, 80)
	extraction_container.size = Vector2(300, 60)
	extraction_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	extraction_container.visible = false
	root.add_child(extraction_container)

	# Background
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.1, 0.15, 0.1, 0.9)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	extraction_container.add_child(bg)

	# Border
	var border := ColorRect.new()
	border.set_anchors_preset(Control.PRESET_FULL_RECT)
	border.position = Vector2(-2, -2)
	border.size = Vector2(304, 64)
	border.color = Color(0.3, 0.8, 0.3, 0.8)
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	border.z_index = -1
	extraction_container.add_child(border)

	# Label
	extraction_label = Label.new()
	extraction_label.text = "EXTRACTING..."
	extraction_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	extraction_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	extraction_label.position.y = 8
	extraction_label.add_theme_font_size_override("font_size", 16)
	extraction_label.add_theme_color_override("font_color", Color(0.3, 0.9, 0.3))
	extraction_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	extraction_container.add_child(extraction_label)

	# Progress bar
	extraction_progress = ProgressBar.new()
	extraction_progress.position = Vector2(20, 35)
	extraction_progress.size = Vector2(260, 15)
	extraction_progress.min_value = 0.0
	extraction_progress.max_value = 1.0
	extraction_progress.value = 0.0
	extraction_progress.show_percentage = false
	extraction_progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	extraction_container.add_child(extraction_progress)

	# Style the progress bar
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0.1, 0.1, 0.12)
	bg_style.set_corner_radius_all(3)
	extraction_progress.add_theme_stylebox_override("background", bg_style)

	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = Color(0.3, 0.9, 0.3)
	fill_style.set_corner_radius_all(3)
	extraction_progress.add_theme_stylebox_override("fill", fill_style)

	# Connect to GameState extraction signals
	if GameState:
		if GameState.has_signal("extraction_available"):
			GameState.extraction_available.connect(_on_extraction_available)
		if GameState.has_signal("extraction_started"):
			GameState.extraction_started.connect(_on_extraction_started)
		if GameState.has_signal("extraction_cancelled"):
			GameState.extraction_cancelled.connect(_on_extraction_cancelled)
		if GameState.has_signal("player_extracted"):
			GameState.player_extracted.connect(_on_player_extracted)


func _on_extraction_available() -> void:
	# Show extraction available notification
	var notify := Label.new()
	notify.text = "EXTRACTION AVAILABLE"
	notify.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notify.set_anchors_preset(Control.PRESET_CENTER)
	notify.position = Vector2(-200, 50)
	notify.size = Vector2(400, 50)
	notify.add_theme_font_size_override("font_size", 24)
	notify.add_theme_color_override("font_color", Color(0.3, 0.9, 0.3))
	notify.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(notify)

	var tween := notify.create_tween()
	tween.tween_property(notify, "modulate:a", 1.0, 0.2)
	tween.tween_interval(3.0)
	tween.tween_property(notify, "modulate:a", 0.0, 0.5)
	tween.tween_callback(notify.queue_free)


func start_extraction(duration: float) -> void:
	extraction_active = true
	extraction_time = 0.0
	extraction_max_time = duration
	extraction_container.visible = true
	extraction_progress.value = 0.0


func cancel_extraction() -> void:
	extraction_active = false
	extraction_container.visible = false


func complete_extraction() -> void:
	extraction_active = false
	extraction_label.text = "EXTRACTED!"
	extraction_progress.value = 1.0

	var tween := extraction_container.create_tween()
	tween.tween_interval(1.0)
	tween.tween_property(extraction_container, "modulate:a", 0.0, 0.5)
	tween.tween_callback(func(): extraction_container.visible = false; extraction_container.modulate.a = 1.0)


func _update_extraction(delta: float) -> void:
	if not extraction_active:
		return

	extraction_time += delta
	var progress: float = extraction_time / extraction_max_time
	extraction_progress.value = clampf(progress, 0.0, 1.0)

	# Update label with countdown
	var remaining: float = extraction_max_time - extraction_time
	extraction_label.text = "EXTRACTING... %.1fs" % maxf(remaining, 0.0)


func _on_extraction_started(peer_id: int, _zone_name: String, duration: float) -> void:
	# Only show for local player
	var local_peer := NetworkManager.local_peer_id if NetworkManager else 1
	if peer_id == local_peer:
		start_extraction(duration)


func _on_extraction_cancelled(peer_id: int, _reason: String) -> void:
	# Only handle for local player
	var local_peer := NetworkManager.local_peer_id if NetworkManager else 1
	if peer_id == local_peer:
		cancel_extraction()


func _on_player_extracted(peer_id: int) -> void:
	# Only handle for local player
	var local_peer := NetworkManager.local_peer_id if NetworkManager else 1
	if peer_id == local_peer:
		complete_extraction()


# ============================================
# DEATH SCREEN
# ============================================

func _build_death_screen() -> void:
	death_screen = Control.new()
	death_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	death_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	death_screen.visible = false
	root.add_child(death_screen)

	# Dark overlay
	var overlay := ColorRect.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0.1, 0, 0, 0.7)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	death_screen.add_child(overlay)

	# YOU DIED text
	var died_label := Label.new()
	died_label.text = "YOU DIED"
	died_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	died_label.set_anchors_preset(Control.PRESET_CENTER)
	died_label.position = Vector2(-200, -50)
	died_label.size = Vector2(400, 100)
	died_label.add_theme_font_size_override("font_size", 64)
	died_label.add_theme_color_override("font_color", Color(0.8, 0.1, 0.1))
	died_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	death_screen.add_child(died_label)

	# Respawn hint
	var hint_label := Label.new()
	hint_label.text = "Waiting for respawn..."
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.set_anchors_preset(Control.PRESET_CENTER)
	hint_label.position = Vector2(-200, 50)
	hint_label.size = Vector2(400, 30)
	hint_label.add_theme_font_size_override("font_size", 18)
	hint_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
	hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	death_screen.add_child(hint_label)

	# Connect to player died signal
	if GameState:
		GameState.player_died.connect(_on_player_died)
		GameState.player_spawned.connect(_on_player_respawned)


func _on_player_died(peer_id: int) -> void:
	var local_peer := NetworkManager.local_peer_id if NetworkManager else 1
	if peer_id == local_peer:
		show_death_screen()


func _on_player_respawned(peer_id: int, _player_node: Node3D) -> void:
	var local_peer := NetworkManager.local_peer_id if NetworkManager else 1
	if peer_id == local_peer:
		hide_death_screen()


func show_death_screen() -> void:
	is_dead = true
	death_screen.visible = true
	death_screen.modulate.a = 0

	var tween := death_screen.create_tween()
	tween.tween_property(death_screen, "modulate:a", 1.0, 0.5)


func hide_death_screen() -> void:
	is_dead = false

	var tween := death_screen.create_tween()
	tween.tween_property(death_screen, "modulate:a", 0.0, 0.3)
	tween.tween_callback(func(): death_screen.visible = false)


# ============================================
# GAME OVER SCREEN
# ============================================

func _build_game_over_screen() -> void:
	game_over_screen = Control.new()
	game_over_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	game_over_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	game_over_screen.visible = false
	root.add_child(game_over_screen)

	# Dark overlay
	var overlay := ColorRect.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0, 0, 0, 0.85)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	game_over_screen.add_child(overlay)

	# Title (VICTORY or DEFEAT)
	game_over_title = Label.new()
	game_over_title.text = "GAME OVER"
	game_over_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	game_over_title.set_anchors_preset(Control.PRESET_CENTER)
	game_over_title.position = Vector2(-250, -100)
	game_over_title.size = Vector2(500, 80)
	game_over_title.add_theme_font_size_override("font_size", 56)
	game_over_title.add_theme_color_override("font_color", Color.WHITE)
	game_over_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	game_over_screen.add_child(game_over_title)

	# Stats
	game_over_stats = Label.new()
	game_over_stats.text = "Wave: 1\nKills: 0"
	game_over_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	game_over_stats.set_anchors_preset(Control.PRESET_CENTER)
	game_over_stats.position = Vector2(-200, 0)
	game_over_stats.size = Vector2(400, 100)
	game_over_stats.add_theme_font_size_override("font_size", 20)
	game_over_stats.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
	game_over_stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	game_over_screen.add_child(game_over_stats)

	# Connect to game over signal
	if GameState:
		GameState.game_over.connect(_on_game_over)


func _on_game_over(reason: String, victory: bool) -> void:
	show_game_over(reason, victory)


func show_game_over(reason: String, victory: bool) -> void:
	# Hide death screen if showing
	death_screen.visible = false

	# Set title and color based on victory/defeat
	if victory:
		game_over_title.text = "VICTORY"
		game_over_title.add_theme_color_override("font_color", Color(0.3, 0.9, 0.3))
	else:
		game_over_title.text = "DEFEAT"
		game_over_title.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3))

	# Set stats
	game_over_stats.text = "%s\n\nWave: %d\nKills: %d" % [reason, current_wave, player_kills]

	game_over_screen.visible = true
	game_over_screen.modulate.a = 0

	var tween := game_over_screen.create_tween()
	tween.tween_property(game_over_screen, "modulate:a", 1.0, 0.5)


# ============================================
# DAMAGE NUMBERS SYSTEM
# ============================================

var damage_number_container: Control
var active_damage_numbers: Array[Dictionary] = []

func _build_damage_numbers() -> void:
	damage_number_container = Control.new()
	damage_number_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	damage_number_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(damage_number_container)


## Show floating damage number at world position
func show_damage_number(damage: float, world_position: Vector3, is_crit: bool = false, is_headshot: bool = false) -> void:
	if not damage_number_container:
		_build_damage_numbers()

	# Find local player camera for projection
	var camera := _get_local_camera()
	if not camera:
		return

	# Check if position is in front of camera
	var camera_forward := -camera.global_transform.basis.z
	var to_target := (world_position - camera.global_position).normalized()
	if camera_forward.dot(to_target) < 0:
		return

	# Project world position to screen
	var screen_pos := camera.unproject_position(world_position)

	# Create damage label
	var label := Label.new()
	var damage_text := str(int(damage))

	if is_headshot:
		damage_text = "!" + damage_text + "!"
	if is_crit:
		damage_text = damage_text + "!"

	label.text = damage_text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	# Style based on damage type
	var font_size := 18
	var color := Color(1, 1, 1)

	if is_crit and is_headshot:
		font_size = 28
		color = Color(1, 0.3, 0.8)  # Pink for crit headshot
	elif is_headshot:
		font_size = 24
		color = Color(1, 0.8, 0.2)  # Gold for headshot
	elif is_crit:
		font_size = 22
		color = Color(1, 0.4, 0.2)  # Orange for crit
	elif damage >= 50:
		font_size = 20
		color = Color(1, 0.6, 0.3)  # Orange-ish for big damage
	else:
		font_size = 16
		color = Color(1, 1, 1)  # White for normal

	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)

	label.position = screen_pos - Vector2(30, 10)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	damage_number_container.add_child(label)

	# Add random offset for variety
	var random_offset := Vector2(randf_range(-20, 20), randf_range(-10, 10))
	label.position += random_offset

	# Track for animation
	active_damage_numbers.append({
		"label": label,
		"world_pos": world_position,
		"lifetime": 0.0,
		"max_lifetime": 1.2,
		"velocity": Vector2(randf_range(-30, 30), -80)  # Float upward
	})


func _update_damage_numbers(delta: float) -> void:
	var camera := _get_local_camera()

	for i in range(active_damage_numbers.size() - 1, -1, -1):
		var data: Dictionary = active_damage_numbers[i]
		data.lifetime += delta

		var label: Label = data.label
		if not is_instance_valid(label):
			active_damage_numbers.remove_at(i)
			continue

		# Update position (float upward)
		label.position += data.velocity * delta
		data.velocity.y += 50 * delta  # Gravity effect

		# Fade out
		var progress: float = data.lifetime / data.max_lifetime
		label.modulate.a = 1.0 - (progress * progress)  # Quadratic fade

		# Scale down slightly
		label.scale = Vector2.ONE * (1.0 - progress * 0.3)

		# Remove when done
		if data.lifetime >= data.max_lifetime:
			label.queue_free()
			active_damage_numbers.remove_at(i)


func _get_local_camera() -> Camera3D:
	if _connected_player and is_instance_valid(_connected_player):
		return _connected_player.camera
	# Fallback to viewport camera
	return get_viewport().get_camera_3d()


# ============================================
# MINIMAP SYSTEM
# ============================================

var minimap_player_marker: ColorRect
var minimap_markers: Dictionary = {}  # entity_id -> marker node
var minimap_scale: float = 2.0  # World units per pixel

func _setup_minimap() -> void:
	if not mini_map_frame:
		return

	# Clear placeholder
	for child in mini_map_frame.get_children():
		child.queue_free()

	# Player marker (center of minimap)
	minimap_player_marker = ColorRect.new()
	minimap_player_marker.size = Vector2(6, 6)
	minimap_player_marker.position = Vector2(mini_map_frame.size.x / 2 - 3, mini_map_frame.size.y / 2 - 3)
	minimap_player_marker.color = Color(0.2, 0.8, 0.2)  # Green
	minimap_player_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mini_map_frame.add_child(minimap_player_marker)


func update_minimap(player_pos: Vector3, player_rotation: float) -> void:
	if not mini_map_frame:
		return

	# Rotate minimap based on player facing
	mini_map_frame.rotation = -player_rotation

	# Update other markers (zombies, objectives)
	_update_minimap_markers(player_pos)


func _update_minimap_markers(player_pos: Vector3) -> void:
	# Get zombies in range
	var zombies := get_tree().get_nodes_in_group("zombies")
	var minimap_range := mini_map_frame.size.x * minimap_scale / 2

	# Track which markers to keep
	var active_ids: Array[int] = []

	for zombie in zombies:
		if not zombie is CharacterBody3D:
			continue

		var zombie_pos: Vector3 = zombie.global_position
		var offset := Vector2(zombie_pos.x - player_pos.x, zombie_pos.z - player_pos.z)
		var distance := offset.length()

		if distance > minimap_range:
			continue

		var entity_id: int = zombie.get_instance_id()
		active_ids.append(entity_id)

		# Get or create marker
		var marker: ColorRect
		if entity_id in minimap_markers:
			marker = minimap_markers[entity_id]
		else:
			marker = ColorRect.new()
			marker.size = Vector2(4, 4)
			marker.color = Color(0.9, 0.2, 0.2)  # Red for enemies
			marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
			mini_map_frame.add_child(marker)
			minimap_markers[entity_id] = marker

		# Position marker relative to center
		var screen_offset := offset / minimap_scale
		marker.position = Vector2(
			mini_map_frame.size.x / 2 + screen_offset.x - 2,
			mini_map_frame.size.y / 2 + screen_offset.y - 2
		)

	# Remove markers for entities no longer in range
	for entity_id in minimap_markers.keys():
		if entity_id not in active_ids:
			var marker: ColorRect = minimap_markers[entity_id]
			if is_instance_valid(marker):
				marker.queue_free()
			minimap_markers.erase(entity_id)


func _update_minimap_from_player() -> void:
	if not _connected_player or not is_instance_valid(_connected_player):
		return

	var player_pos := _connected_player.global_position
	var player_rot := _connected_player.look_yaw
	update_minimap(player_pos, player_rot)


# ============================================
# COMBO SYSTEM
# ============================================

var combo_count: int = 0
var combo_timer: float = 0.0
var combo_timeout: float = 3.0
var combo_label: Label
var combo_container: Control

func _build_combo_display() -> void:
	combo_container = Control.new()
	combo_container.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	combo_container.position = Vector2(-150, -100)
	combo_container.size = Vector2(140, 60)
	combo_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	combo_container.visible = false
	root.add_child(combo_container)

	# Background
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.1, 0.1, 0.12, 0.8)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	combo_container.add_child(bg)

	# Combo text
	combo_label = Label.new()
	combo_label.text = "x1"
	combo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	combo_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	combo_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	combo_label.add_theme_font_size_override("font_size", 32)
	combo_label.add_theme_color_override("font_color", Color(1, 0.8, 0.2))
	combo_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	combo_container.add_child(combo_label)


func add_combo_kill() -> void:
	combo_count += 1
	combo_timer = combo_timeout

	if not combo_container:
		_build_combo_display()

	combo_container.visible = true
	combo_label.text = "x%d" % combo_count

	# Color based on combo size
	if combo_count >= 10:
		combo_label.add_theme_color_override("font_color", Color(1, 0.2, 0.8))  # Pink
	elif combo_count >= 5:
		combo_label.add_theme_color_override("font_color", Color(1, 0.4, 0.2))  # Orange
	else:
		combo_label.add_theme_color_override("font_color", Color(1, 0.8, 0.2))  # Gold

	# Pulse animation
	var tween := combo_container.create_tween()
	tween.tween_property(combo_container, "scale", Vector2(1.2, 1.2), 0.08)
	tween.tween_property(combo_container, "scale", Vector2(1.0, 1.0), 0.1)


func _update_combo(delta: float) -> void:
	if combo_count > 0:
		combo_timer -= delta
		if combo_timer <= 0:
			_end_combo()


func _end_combo() -> void:
	if combo_count >= 3 and combo_container:
		# Show final combo message
		var final_label := Label.new()
		final_label.text = "%d KILL COMBO!" % combo_count
		final_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		final_label.set_anchors_preset(Control.PRESET_CENTER)
		final_label.position = Vector2(-150, 50)
		final_label.size = Vector2(300, 40)
		final_label.add_theme_font_size_override("font_size", 24)
		final_label.add_theme_color_override("font_color", Color(1, 0.8, 0.2))
		final_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(final_label)

		var tween := final_label.create_tween()
		tween.tween_property(final_label, "modulate:a", 1.0, 0.1)
		tween.tween_interval(1.5)
		tween.tween_property(final_label, "modulate:a", 0.0, 0.5)
		tween.tween_callback(final_label.queue_free)

	combo_count = 0
	if combo_container:
		combo_container.visible = false


func _show_boss_warning() -> void:
	var warning := Label.new()
	warning.text = "BOSS INCOMING"
	warning.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	warning.set_anchors_preset(Control.PRESET_CENTER)
	warning.position = Vector2(-150, -40)
	warning.size = Vector2(300, 30)
	warning.add_theme_font_size_override("font_size", 24)
	warning.add_theme_color_override("font_color", Color(1, 0.4, 0.4))
	warning.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	warning.add_theme_constant_override("shadow_offset_x", 2)
	warning.add_theme_constant_override("shadow_offset_y", 2)
	warning.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(warning)

	warning.modulate.a = 0
	var tween := warning.create_tween()
	tween.tween_property(warning, "modulate:a", 1.0, 0.3).set_delay(0.5)
	tween.tween_interval(2.0)
	tween.tween_property(warning, "modulate:a", 0.0, 0.5)
	tween.tween_callback(warning.queue_free)


## Show boss killed announcement
func show_boss_killed() -> void:
	var killed := Label.new()
	killed.text = "BOSS DEFEATED!"
	killed.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	killed.set_anchors_preset(Control.PRESET_CENTER)
	killed.position = Vector2(-200, -60)
	killed.size = Vector2(400, 60)
	killed.add_theme_font_size_override("font_size", 40)
	killed.add_theme_color_override("font_color", Color(0.9, 0.8, 0.2))
	killed.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	killed.add_theme_constant_override("shadow_offset_x", 3)
	killed.add_theme_constant_override("shadow_offset_y", 3)
	killed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(killed)

	killed.modulate.a = 0
	killed.scale = Vector2(0.5, 0.5)
	killed.pivot_offset = killed.size / 2

	var tween := killed.create_tween()
	tween.set_parallel(true)
	tween.tween_property(killed, "modulate:a", 1.0, 0.2)
	tween.tween_property(killed, "scale", Vector2(1.1, 1.1), 0.3).set_trans(Tween.TRANS_BACK)
	tween.set_parallel(false)
	tween.tween_property(killed, "scale", Vector2(1.0, 1.0), 0.1)
	tween.tween_interval(2.0)
	tween.tween_property(killed, "modulate:a", 0.0, 0.5)
	tween.tween_callback(killed.queue_free)
