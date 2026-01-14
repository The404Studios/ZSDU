extends CanvasLayer
class_name AnimatedHUD
## AnimatedHUD - Animated in-game HUD with smooth transitions
##
## Features:
## - Animated health/stamina bars with damage flash
## - Ammo counter with reload animation
## - Wave/round indicator with dramatic reveals
## - Kill feed with stagger animations
## - Crosshair with hit markers
## - Low health vignette effect
##
## Connect to player signals for automatic updates

signal damage_taken(amount: float)
signal health_changed(current: float, max_value: float)
signal stamina_changed(current: float, max_value: float)
signal ammo_changed(current: int, reserve: int)
signal wave_started(wave_num: int)
signal kill_registered(enemy_name: String, is_headshot: bool)

# UI Animation helper
var anim := UIAnimations.new()

# Root control (for modulate/visibility)
var root: Control

# Health bar
var health_container: Control
var health_bar: ProgressBar
var health_bar_delayed: ProgressBar  # Shows damage taken (red bar behind)
var health_label: Label
var health_icon: TextureRect

# Stamina bar
var stamina_container: Control
var stamina_bar: ProgressBar
var stamina_icon: TextureRect

# Ammo display
var ammo_container: Control
var ammo_current: Label
var ammo_separator: Label
var ammo_reserve: Label
var ammo_icon: TextureRect
var reload_indicator: Control
var reload_progress: ProgressBar

# Wave display
var wave_container: Control
var wave_label: Label
var wave_number: Label
var wave_subtitle: Label

# Sigil health display
var sigil_container: Control
var sigil_bar: ProgressBar
var sigil_label: Label
var sigil_health := 1000.0
var sigil_max_health := 1000.0

# Kill feed
var kill_feed_container: VBoxContainer
var kill_feed_max := 5
var kill_feed_entries: Array[Control] = []

# Crosshair
var crosshair_container: Control
var crosshair_center: ColorRect
var crosshair_lines: Array[ColorRect] = []
var hit_marker: Control
var hit_marker_lines: Array[ColorRect] = []

# Low health vignette
var vignette: ColorRect
var vignette_intensity := 0.0

# State tracking
var current_health := 100.0
var max_health := 100.0
var current_stamina := 100.0
var max_stamina := 100.0
var current_ammo := 30
var reserve_ammo := 90
var is_reloading := false


func _ready() -> void:
	layer = 10  # Above game world
	_build_ui()
	_connect_signals()


func _process(delta: float) -> void:
	_update_vignette(delta)
	_update_stamina_bar(delta)


# ============================================
# UI CONSTRUCTION
# ============================================

func _build_ui() -> void:
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_build_health_bar(root)
	_build_stamina_bar(root)
	_build_ammo_display(root)
	_build_wave_display(root)
	_build_sigil_display(root)
	_build_kill_feed(root)
	_build_crosshair(root)
	_build_vignette(root)


func _build_health_bar(parent: Control) -> void:
	health_container = Control.new()
	health_container.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	health_container.position = Vector2(20, -80)
	health_container.size = Vector2(250, 40)
	health_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(health_container)

	# Background
	var bg := ColorRect.new()
	bg.color = Color(0.1, 0.1, 0.1, 0.8)
	bg.size = Vector2(250, 30)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	health_container.add_child(bg)

	# Delayed health bar (shows damage taken)
	health_bar_delayed = ProgressBar.new()
	health_bar_delayed.position = Vector2(40, 5)
	health_bar_delayed.size = Vector2(200, 20)
	health_bar_delayed.max_value = 100
	health_bar_delayed.value = 100
	health_bar_delayed.show_percentage = false
	health_bar_delayed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_style_progress_bar(health_bar_delayed, Color(0.6, 0.1, 0.1))
	health_container.add_child(health_bar_delayed)

	# Main health bar
	health_bar = ProgressBar.new()
	health_bar.position = Vector2(40, 5)
	health_bar.size = Vector2(200, 20)
	health_bar.max_value = 100
	health_bar.value = 100
	health_bar.show_percentage = false
	health_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_style_progress_bar(health_bar, Color(0.2, 0.7, 0.3))
	health_container.add_child(health_bar)

	# Health icon placeholder
	health_icon = TextureRect.new()
	health_icon.position = Vector2(5, 2)
	health_icon.size = Vector2(26, 26)
	health_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	health_container.add_child(health_icon)

	# Health text
	health_label = Label.new()
	health_label.position = Vector2(40, 5)
	health_label.size = Vector2(200, 20)
	health_label.text = "100"
	health_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	health_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	health_label.add_theme_font_size_override("font_size", 14)
	health_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	health_container.add_child(health_label)


func _build_stamina_bar(parent: Control) -> void:
	stamina_container = Control.new()
	stamina_container.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	stamina_container.position = Vector2(20, -45)
	stamina_container.size = Vector2(250, 20)
	stamina_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(stamina_container)

	# Background
	var bg := ColorRect.new()
	bg.color = Color(0.1, 0.1, 0.1, 0.6)
	bg.size = Vector2(250, 15)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stamina_container.add_child(bg)

	# Stamina bar
	stamina_bar = ProgressBar.new()
	stamina_bar.position = Vector2(40, 2)
	stamina_bar.size = Vector2(200, 11)
	stamina_bar.max_value = 100
	stamina_bar.value = 100
	stamina_bar.show_percentage = false
	stamina_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_style_progress_bar(stamina_bar, Color(0.3, 0.5, 0.8))
	stamina_container.add_child(stamina_bar)

	# Stamina icon placeholder
	stamina_icon = TextureRect.new()
	stamina_icon.position = Vector2(8, 0)
	stamina_icon.size = Vector2(15, 15)
	stamina_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stamina_container.add_child(stamina_icon)


func _build_ammo_display(parent: Control) -> void:
	ammo_container = Control.new()
	ammo_container.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	ammo_container.position = Vector2(-180, -80)
	ammo_container.size = Vector2(160, 50)
	ammo_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(ammo_container)

	# Background
	var bg := ColorRect.new()
	bg.color = Color(0.1, 0.1, 0.1, 0.8)
	bg.size = Vector2(160, 50)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ammo_container.add_child(bg)

	# Ammo icon placeholder
	ammo_icon = TextureRect.new()
	ammo_icon.position = Vector2(10, 10)
	ammo_icon.size = Vector2(30, 30)
	ammo_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ammo_container.add_child(ammo_icon)

	# Current ammo (large)
	ammo_current = Label.new()
	ammo_current.position = Vector2(45, 5)
	ammo_current.size = Vector2(60, 40)
	ammo_current.text = "30"
	ammo_current.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ammo_current.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ammo_current.add_theme_font_size_override("font_size", 28)
	ammo_current.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ammo_container.add_child(ammo_current)

	# Separator
	ammo_separator = Label.new()
	ammo_separator.position = Vector2(105, 5)
	ammo_separator.size = Vector2(15, 40)
	ammo_separator.text = "|"
	ammo_separator.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ammo_separator.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ammo_separator.add_theme_font_size_override("font_size", 20)
	ammo_separator.modulate = Color(0.5, 0.5, 0.5)
	ammo_separator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ammo_container.add_child(ammo_separator)

	# Reserve ammo (smaller)
	ammo_reserve = Label.new()
	ammo_reserve.position = Vector2(115, 5)
	ammo_reserve.size = Vector2(40, 40)
	ammo_reserve.text = "90"
	ammo_reserve.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	ammo_reserve.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ammo_reserve.add_theme_font_size_override("font_size", 18)
	ammo_reserve.modulate = Color(0.7, 0.7, 0.7)
	ammo_reserve.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ammo_container.add_child(ammo_reserve)

	# Reload indicator (hidden by default)
	reload_indicator = Control.new()
	reload_indicator.position = Vector2(0, -25)
	reload_indicator.size = Vector2(160, 20)
	reload_indicator.visible = false
	reload_indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ammo_container.add_child(reload_indicator)

	reload_progress = ProgressBar.new()
	reload_progress.size = Vector2(160, 8)
	reload_progress.max_value = 100
	reload_progress.value = 0
	reload_progress.show_percentage = false
	reload_progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_style_progress_bar(reload_progress, Color(0.9, 0.7, 0.2))
	reload_indicator.add_child(reload_progress)

	var reload_label := Label.new()
	reload_label.position = Vector2(0, 8)
	reload_label.size = Vector2(160, 12)
	reload_label.text = "RELOADING"
	reload_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	reload_label.add_theme_font_size_override("font_size", 10)
	reload_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	reload_indicator.add_child(reload_label)


func _build_wave_display(parent: Control) -> void:
	wave_container = Control.new()
	wave_container.set_anchors_preset(Control.PRESET_CENTER_TOP)
	wave_container.position = Vector2(-100, 20)
	wave_container.size = Vector2(200, 80)
	wave_container.modulate.a = 0.0
	wave_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(wave_container)

	wave_label = Label.new()
	wave_label.size = Vector2(200, 30)
	wave_label.text = "WAVE"
	wave_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wave_label.add_theme_font_size_override("font_size", 18)
	wave_label.modulate = Color(0.7, 0.7, 0.7)
	wave_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wave_container.add_child(wave_label)

	wave_number = Label.new()
	wave_number.position = Vector2(0, 25)
	wave_number.size = Vector2(200, 50)
	wave_number.text = "1"
	wave_number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wave_number.add_theme_font_size_override("font_size", 42)
	wave_number.add_theme_color_override("font_color", Color(1, 0.8, 0.2))
	wave_number.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wave_container.add_child(wave_number)

	wave_subtitle = Label.new()
	wave_subtitle.position = Vector2(0, 70)
	wave_subtitle.size = Vector2(200, 20)
	wave_subtitle.text = "Survive!"
	wave_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wave_subtitle.add_theme_font_size_override("font_size", 14)
	wave_subtitle.modulate = Color(0.6, 0.6, 0.6)
	wave_subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wave_container.add_child(wave_subtitle)


func _build_sigil_display(parent: Control) -> void:
	sigil_container = Control.new()
	sigil_container.set_anchors_preset(Control.PRESET_TOP_LEFT)
	sigil_container.position = Vector2(20, 20)
	sigil_container.size = Vector2(200, 50)
	sigil_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(sigil_container)

	# Label
	var label := Label.new()
	label.text = "SIGIL"
	label.add_theme_font_size_override("font_size", 12)
	label.modulate = Color(0.8, 0.6, 1.0)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sigil_container.add_child(label)

	# Background
	var bg := ColorRect.new()
	bg.position = Vector2(0, 18)
	bg.color = Color(0.1, 0.1, 0.1, 0.8)
	bg.size = Vector2(200, 24)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sigil_container.add_child(bg)

	# Sigil health bar
	sigil_bar = ProgressBar.new()
	sigil_bar.position = Vector2(5, 20)
	sigil_bar.size = Vector2(150, 18)
	sigil_bar.max_value = 1000
	sigil_bar.value = 1000
	sigil_bar.show_percentage = false
	sigil_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_style_progress_bar(sigil_bar, Color(0.6, 0.3, 0.8))
	sigil_container.add_child(sigil_bar)

	# Health text
	sigil_label = Label.new()
	sigil_label.position = Vector2(160, 18)
	sigil_label.size = Vector2(40, 24)
	sigil_label.text = "100%"
	sigil_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	sigil_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sigil_label.add_theme_font_size_override("font_size", 12)
	sigil_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sigil_container.add_child(sigil_label)


func _build_kill_feed(parent: Control) -> void:
	kill_feed_container = VBoxContainer.new()
	kill_feed_container.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	kill_feed_container.position = Vector2(-250, 60)
	kill_feed_container.size = Vector2(230, 200)
	kill_feed_container.add_theme_constant_override("separation", 4)
	kill_feed_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(kill_feed_container)


func _build_crosshair(parent: Control) -> void:
	crosshair_container = Control.new()
	crosshair_container.set_anchors_preset(Control.PRESET_CENTER)
	crosshair_container.position = Vector2(-20, -20)
	crosshair_container.size = Vector2(40, 40)
	crosshair_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(crosshair_container)

	# Center dot
	crosshair_center = ColorRect.new()
	crosshair_center.position = Vector2(18, 18)
	crosshair_center.size = Vector2(4, 4)
	crosshair_center.color = Color.WHITE
	crosshair_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crosshair_container.add_child(crosshair_center)

	# Crosshair lines
	var line_length := 8.0
	var line_width := 2.0
	var gap := 6.0

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

	# Hit marker (X shape, hidden by default)
	hit_marker = Control.new()
	hit_marker.position = Vector2(10, 10)
	hit_marker.size = Vector2(20, 20)
	hit_marker.visible = false
	hit_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crosshair_container.add_child(hit_marker)

	for i in range(4):
		var hm_line := ColorRect.new()
		hm_line.size = Vector2(10, 2)
		hm_line.color = Color(1, 0.2, 0.2)
		hm_line.pivot_offset = Vector2(0, 1)
		hm_line.position = Vector2(10, 10)
		hm_line.rotation = deg_to_rad(45 + i * 90)
		hm_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hit_marker.add_child(hm_line)
		hit_marker_lines.append(hm_line)


func _build_vignette(parent: Control) -> void:
	vignette = ColorRect.new()
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.color = Color(0.5, 0, 0, 0)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(vignette)


func _style_progress_bar(bar: ProgressBar, fill_color: Color) -> void:
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0.15, 0.15, 0.15, 0.9)
	bg_style.set_corner_radius_all(2)
	bar.add_theme_stylebox_override("background", bg_style)

	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = fill_color
	fill_style.set_corner_radius_all(2)
	bar.add_theme_stylebox_override("fill", fill_style)


# ============================================
# SIGNAL CONNECTIONS
# ============================================

func _connect_signals() -> void:
	damage_taken.connect(_on_damage_taken)
	health_changed.connect(_on_health_changed)
	stamina_changed.connect(_on_stamina_changed)
	ammo_changed.connect(_on_ammo_changed)
	wave_started.connect(_on_wave_started)
	kill_registered.connect(_on_kill_registered)


# ============================================
# HEALTH ANIMATIONS
# ============================================

func _on_health_changed(current: float, max_val: float) -> void:
	var old_health := current_health
	current_health = current
	max_health = max_val

	health_bar.max_value = max_val
	health_label.text = str(int(current))

	# Animate health bar
	var tween := health_bar.create_tween()
	tween.tween_property(health_bar, "value", current, 0.2)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	# Delayed bar follows after a moment
	if current < old_health:
		# Damage taken - delayed bar catches up slowly
		var delayed_tween := health_bar_delayed.create_tween()
		delayed_tween.tween_property(health_bar_delayed, "value", current, 0.8)\
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)\
			.set_delay(0.3)
	else:
		# Healing - delayed bar updates immediately
		health_bar_delayed.value = current


func _on_damage_taken(amount: float) -> void:
	# Flash health bar red
	var flash_tween := health_container.create_tween()
	flash_tween.tween_property(health_bar, "modulate", Color(2, 0.5, 0.5), 0.05)
	flash_tween.tween_property(health_bar, "modulate", Color.WHITE, 0.15)

	# Shake the container
	anim.shake(health_container, 5.0, 0.2)

	# Flash vignette based on damage severity
	var severity := clampf(amount / 50.0, 0.1, 1.0)
	_flash_vignette(severity)


func _flash_vignette(intensity: float) -> void:
	var tween := vignette.create_tween()
	tween.tween_property(vignette, "color:a", intensity * 0.4, 0.05)
	tween.tween_property(vignette, "color:a", 0.0, 0.3)


func _update_vignette(_delta: float) -> void:
	# Persistent low health vignette
	var health_percent := current_health / max_health if max_health > 0 else 1.0

	if health_percent < 0.3:
		var target_intensity := (0.3 - health_percent) / 0.3 * 0.3
		# Pulse effect at very low health
		if health_percent < 0.15:
			target_intensity += sin(Time.get_ticks_msec() / 200.0) * 0.05
		vignette_intensity = lerpf(vignette_intensity, target_intensity, 0.1)
	else:
		vignette_intensity = lerpf(vignette_intensity, 0.0, 0.1)

	vignette.color.a = vignette_intensity


# ============================================
# STAMINA ANIMATIONS
# ============================================

func _on_stamina_changed(current: float, max_val: float) -> void:
	current_stamina = current
	max_stamina = max_val
	stamina_bar.max_value = max_val


func _update_stamina_bar(_delta: float) -> void:
	# Smooth stamina bar update
	stamina_bar.value = lerpf(stamina_bar.value, current_stamina, 0.15)

	# Color shift when low
	var stamina_percent := current_stamina / max_stamina if max_stamina > 0 else 1.0
	if stamina_percent < 0.2:
		stamina_bar.modulate = Color(1.5, 0.5, 0.5)
	else:
		stamina_bar.modulate = Color.WHITE


# ============================================
# AMMO ANIMATIONS
# ============================================

func _on_ammo_changed(current: int, reserve: int) -> void:
	var old_ammo := current_ammo
	current_ammo = current
	reserve_ammo = reserve

	ammo_reserve.text = str(reserve)

	# Animate current ammo change
	if current != old_ammo:
		_animate_ammo_change(old_ammo, current)

	# Low ammo warning
	if current <= 5 and current > 0:
		ammo_current.add_theme_color_override("font_color", Color(1, 0.3, 0.3))
	elif current == 0:
		ammo_current.add_theme_color_override("font_color", Color(1, 0, 0))
		anim.shake(ammo_container, 3.0, 0.15)
	else:
		ammo_current.remove_theme_color_override("font_color")


func _animate_ammo_change(from: int, to: int) -> void:
	# Quick count animation
	var tween := ammo_current.create_tween()
	tween.tween_method(
		func(val: float): ammo_current.text = str(int(val)),
		float(from),
		float(to),
		0.1
	)

	# Scale pulse on fire
	if to < from:
		var scale_tween := ammo_current.create_tween()
		scale_tween.tween_property(ammo_current, "scale", Vector2(1.15, 1.15), 0.05)
		scale_tween.tween_property(ammo_current, "scale", Vector2.ONE, 0.1)


## Start reload animation
func start_reload(duration: float) -> void:
	is_reloading = true
	reload_indicator.visible = true
	reload_indicator.modulate.a = 0.0
	reload_progress.value = 0

	var tween := reload_indicator.create_tween()
	tween.set_parallel(true)
	tween.tween_property(reload_indicator, "modulate:a", 1.0, 0.1)
	tween.tween_property(reload_progress, "value", 100, duration)\
		.set_trans(Tween.TRANS_LINEAR)

	tween.chain().tween_callback(_on_reload_complete)


func _on_reload_complete() -> void:
	is_reloading = false

	var tween := reload_indicator.create_tween()
	tween.tween_property(reload_indicator, "modulate:a", 0.0, 0.15)
	tween.tween_callback(func(): reload_indicator.visible = false)


# ============================================
# WAVE ANIMATIONS
# ============================================

func _on_wave_started(wave_num: int) -> void:
	wave_number.text = str(wave_num)

	# Determine subtitle based on wave
	if wave_num == 1:
		wave_subtitle.text = "Survive!"
	elif wave_num % 5 == 0:
		wave_subtitle.text = "BOSS WAVE"
		wave_number.add_theme_color_override("font_color", Color(1, 0.2, 0.2))
	else:
		wave_subtitle.text = "Hold the line!"
		wave_number.add_theme_color_override("font_color", Color(1, 0.8, 0.2))

	# Dramatic reveal animation
	wave_container.modulate.a = 0.0
	wave_container.scale = Vector2(0.5, 0.5)

	var tween := wave_container.create_tween()
	tween.set_parallel(true)
	tween.tween_property(wave_container, "modulate:a", 1.0, 0.3)
	tween.tween_property(wave_container, "scale", Vector2(1.1, 1.1), 0.3)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	tween.chain().tween_property(wave_container, "scale", Vector2.ONE, 0.2)
	tween.chain().tween_interval(2.0)
	tween.chain().tween_property(wave_container, "modulate:a", 0.0, 0.5)


# ============================================
# KILL FEED
# ============================================

func _on_kill_registered(enemy_name: String, is_headshot: bool) -> void:
	var entry := _create_kill_entry(enemy_name, is_headshot)
	kill_feed_container.add_child(entry)
	kill_feed_entries.append(entry)

	# Limit entries
	while kill_feed_entries.size() > kill_feed_max:
		var old_entry: Control = kill_feed_entries.pop_front()
		old_entry.queue_free()

	# Animate in
	entry.modulate.a = 0.0
	entry.position.x = 50

	var tween := entry.create_tween()
	tween.set_parallel(true)
	tween.tween_property(entry, "modulate:a", 1.0, 0.15)
	tween.tween_property(entry, "position:x", 0, 0.2)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	# Auto remove after delay
	tween.chain().tween_interval(4.0)
	tween.chain().tween_property(entry, "modulate:a", 0.0, 0.3)
	tween.chain().tween_callback(func():
		if entry in kill_feed_entries:
			kill_feed_entries.erase(entry)
		entry.queue_free()
	)


func _create_kill_entry(enemy_name: String, is_headshot: bool) -> Control:
	var entry := HBoxContainer.new()
	entry.add_theme_constant_override("separation", 8)
	entry.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Background
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.6)
	bg.size = Vector2(230, 24)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	entry.add_child(bg)

	# Kill text
	var label := Label.new()
	label.text = "Killed " + enemy_name
	label.add_theme_font_size_override("font_size", 12)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	entry.add_child(label)

	# Headshot indicator
	if is_headshot:
		var hs_label := Label.new()
		hs_label.text = "HEADSHOT"
		hs_label.add_theme_font_size_override("font_size", 10)
		hs_label.add_theme_color_override("font_color", Color(1, 0.8, 0.2))
		hs_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		entry.add_child(hs_label)

	return entry


# ============================================
# CROSSHAIR / HIT MARKER
# ============================================

## Show hit marker when damage dealt
func show_hit_marker(is_kill: bool = false, is_headshot: bool = false) -> void:
	hit_marker.visible = true
	hit_marker.modulate.a = 1.0
	hit_marker.scale = Vector2(0.5, 0.5)

	# Color based on hit type
	var color := Color.WHITE
	if is_kill:
		color = Color(1, 0.2, 0.2)
	elif is_headshot:
		color = Color(1, 0.8, 0.2)

	for line in hit_marker_lines:
		line.color = color

	var tween := hit_marker.create_tween()
	tween.set_parallel(true)
	tween.tween_property(hit_marker, "scale", Vector2.ONE, 0.1)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(hit_marker, "modulate:a", 0.0, 0.3).set_delay(0.1)

	tween.chain().tween_callback(func(): hit_marker.visible = false)


## Expand crosshair (when shooting/moving)
func expand_crosshair(amount: float = 1.0) -> void:
	var expansion := 4.0 * amount
	# Animate lines outward briefly
	for i in range(crosshair_lines.size()):
		var line := crosshair_lines[i]
		var tween := line.create_tween()
		var direction := Vector2.ZERO
		match i:
			0: direction = Vector2(0, -expansion)  # Top
			1: direction = Vector2(0, expansion)   # Bottom
			2: direction = Vector2(-expansion, 0)  # Left
			3: direction = Vector2(expansion, 0)   # Right

		tween.tween_property(line, "position", line.position + direction, 0.03)
		tween.tween_property(line, "position", line.position, 0.15)


# ============================================
# PUBLIC API
# ============================================

## Update sigil health display
func update_sigil_health(current: float, max_val: float) -> void:
	sigil_health = current
	sigil_max_health = max_val

	sigil_bar.max_value = max_val

	# Animate the bar
	var tween := sigil_bar.create_tween()
	tween.tween_property(sigil_bar, "value", current, 0.3)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	# Update percentage text
	var percent := int((current / max_val) * 100) if max_val > 0 else 0
	sigil_label.text = "%d%%" % percent

	# Color based on health
	if percent <= 20:
		sigil_bar.modulate = Color(1.5, 0.3, 0.3)
		# Shake when critical
		anim.shake(sigil_container, 5.0, 0.2)
	elif percent <= 50:
		sigil_bar.modulate = Color(1.2, 0.8, 0.4)
	else:
		sigil_bar.modulate = Color.WHITE


## Flash sigil bar when corrupted (zombie reached sigil)
func on_sigil_corrupted() -> void:
	var flash_tween := sigil_container.create_tween()
	flash_tween.tween_property(sigil_bar, "modulate", Color(2, 0.2, 0.2), 0.1)
	flash_tween.tween_property(sigil_bar, "modulate", Color.WHITE, 0.3)
	anim.shake(sigil_container, 8.0, 0.3)


## Connect to a player controller for automatic updates
func connect_to_player(player: PlayerController) -> void:
	if player.movement_controller:
		player.movement_controller.stamina_changed.connect(
			func(c, m): stamina_changed.emit(c, m)
		)

	# Connect health tracking (would need signal from player)
	# player.health_changed.connect(...)


## Show/hide HUD with animation
func show_hud() -> void:
	visible = true
	if root:
		root.modulate.a = 0.0
		var tween := root.create_tween()
		tween.tween_property(root, "modulate:a", 1.0, 0.3)


func hide_hud() -> void:
	if root:
		var tween := root.create_tween()
		tween.tween_property(root, "modulate:a", 0.0, 0.3)
		tween.tween_callback(func(): visible = false)
