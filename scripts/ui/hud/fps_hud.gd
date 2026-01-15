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

# Connection tracking
var _connected_player: PlayerController = null


func _ready() -> void:
	layer = 10
	_build_ui()


func _process(delta: float) -> void:
	_update_smooth_bars(delta)
	_update_vignette(delta)
	_update_from_player()
	_update_buffs()


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
