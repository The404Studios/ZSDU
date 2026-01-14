extends RefCounted
class_name UIAnimations
## UIAnimations - Reusable UI animation library
##
## Provides smooth, game-feel animations for UI elements:
## - Slide in/out with various directions
## - Fade effects with optional scale
## - Pulse and shake for feedback
## - Number counters with easing
## - Button press effects
## - Tooltip reveal animations
##
## Usage:
##   var anim := UIAnimations.new()
##   anim.slide_in(my_panel, UIAnimations.Direction.LEFT)
##   await anim.finished

signal finished

enum Direction { LEFT, RIGHT, UP, DOWN }
enum EaseType { SMOOTH, BOUNCE, ELASTIC, SNAP, OVERSHOOT }

# Default durations
const DEFAULT_DURATION := 0.25
const FAST_DURATION := 0.15
const SLOW_DURATION := 0.4

# Default easings mapped to Godot Tween types
const EASE_MAP := {
	EaseType.SMOOTH: [Tween.TRANS_SINE, Tween.EASE_OUT],
	EaseType.BOUNCE: [Tween.TRANS_BOUNCE, Tween.EASE_OUT],
	EaseType.ELASTIC: [Tween.TRANS_ELASTIC, Tween.EASE_OUT],
	EaseType.SNAP: [Tween.TRANS_BACK, Tween.EASE_OUT],
	EaseType.OVERSHOOT: [Tween.TRANS_BACK, Tween.EASE_IN_OUT],
}


# ============================================
# SLIDE ANIMATIONS
# ============================================

## Slide a control into view from offscreen
func slide_in(control: Control, direction: Direction = Direction.LEFT,
		duration: float = DEFAULT_DURATION, ease_type: EaseType = EaseType.SNAP) -> Tween:

	var target_pos := control.position
	var start_pos := _get_offscreen_pos(control, direction)

	control.position = start_pos
	control.modulate.a = 0.0
	control.visible = true

	var tween := control.create_tween()
	tween.set_parallel(true)

	var ease_config: Array = EASE_MAP[ease_type]
	tween.tween_property(control, "position", target_pos, duration)\
		.set_trans(ease_config[0]).set_ease(ease_config[1])
	tween.tween_property(control, "modulate:a", 1.0, duration * 0.5)

	tween.finished.connect(func(): finished.emit())
	return tween


## Slide a control out of view
func slide_out(control: Control, direction: Direction = Direction.LEFT,
		duration: float = DEFAULT_DURATION, ease_type: EaseType = EaseType.SMOOTH) -> Tween:

	var target_pos := _get_offscreen_pos(control, direction)

	var tween := control.create_tween()
	tween.set_parallel(true)

	var ease_config: Array = EASE_MAP[ease_type]
	tween.tween_property(control, "position", target_pos, duration)\
		.set_trans(ease_config[0]).set_ease(ease_config[1])
	tween.tween_property(control, "modulate:a", 0.0, duration * 0.5).set_delay(duration * 0.3)

	tween.finished.connect(func():
		control.visible = false
		finished.emit()
	)
	return tween


func _get_offscreen_pos(control: Control, direction: Direction) -> Vector2:
	var offset := 100.0  # Extra distance offscreen
	match direction:
		Direction.LEFT:
			return control.position - Vector2(control.size.x + offset, 0)
		Direction.RIGHT:
			return control.position + Vector2(control.size.x + offset, 0)
		Direction.UP:
			return control.position - Vector2(0, control.size.y + offset)
		Direction.DOWN:
			return control.position + Vector2(0, control.size.y + offset)
	return control.position


# ============================================
# FADE ANIMATIONS
# ============================================

## Fade in with optional scale
func fade_in(control: Control, duration: float = DEFAULT_DURATION,
		with_scale: bool = true) -> Tween:

	control.modulate.a = 0.0
	if with_scale:
		control.scale = Vector2(0.8, 0.8)
	control.visible = true

	var tween := control.create_tween()
	tween.set_parallel(true)

	tween.tween_property(control, "modulate:a", 1.0, duration)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	if with_scale:
		tween.tween_property(control, "scale", Vector2.ONE, duration)\
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	tween.finished.connect(func(): finished.emit())
	return tween


## Fade out with optional scale
func fade_out(control: Control, duration: float = DEFAULT_DURATION,
		with_scale: bool = true) -> Tween:

	var tween := control.create_tween()
	tween.set_parallel(true)

	tween.tween_property(control, "modulate:a", 0.0, duration)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

	if with_scale:
		tween.tween_property(control, "scale", Vector2(0.8, 0.8), duration)\
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

	tween.finished.connect(func():
		control.visible = false
		control.scale = Vector2.ONE
		finished.emit()
	)
	return tween


# ============================================
# PULSE & FEEDBACK ANIMATIONS
# ============================================

## Pulse animation (scale up then back)
func pulse(control: Control, scale_factor: float = 1.2,
		duration: float = FAST_DURATION) -> Tween:

	var original_scale := control.scale

	var tween := control.create_tween()
	tween.tween_property(control, "scale", original_scale * scale_factor, duration * 0.4)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(control, "scale", original_scale, duration * 0.6)\
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

	tween.finished.connect(func(): finished.emit())
	return tween


## Shake animation (for errors, damage feedback)
func shake(control: Control, intensity: float = 10.0,
		duration: float = 0.3) -> Tween:

	var original_pos := control.position

	var tween := control.create_tween()

	# Rapid shake with decreasing intensity
	var shake_count := 6
	for i in range(shake_count):
		var t := float(i) / shake_count
		var current_intensity := intensity * (1.0 - t)
		var offset := Vector2(randf_range(-1, 1), randf_range(-1, 1)) * current_intensity
		tween.tween_property(control, "position", original_pos + offset, duration / shake_count)

	tween.tween_property(control, "position", original_pos, duration / shake_count)

	tween.finished.connect(func(): finished.emit())
	return tween


## Flash color (for damage, pickup, etc.)
func flash(control: Control, flash_color: Color = Color.WHITE,
		duration: float = FAST_DURATION) -> Tween:

	var original_modulate := control.modulate

	var tween := control.create_tween()
	tween.tween_property(control, "modulate", flash_color, duration * 0.3)
	tween.tween_property(control, "modulate", original_modulate, duration * 0.7)

	tween.finished.connect(func(): finished.emit())
	return tween


## Bounce (like collecting an item)
func bounce(control: Control, height: float = 20.0,
		duration: float = 0.4) -> Tween:

	var original_pos := control.position

	var tween := control.create_tween()
	tween.tween_property(control, "position:y", original_pos.y - height, duration * 0.4)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(control, "position:y", original_pos.y, duration * 0.6)\
		.set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)

	tween.finished.connect(func(): finished.emit())
	return tween


# ============================================
# NUMBER ANIMATIONS
# ============================================

## Animate a number counter (for score, health changes, etc.)
func count_number(label: Label, from_value: float, to_value: float,
		duration: float = 0.5, format_string: String = "%.0f") -> Tween:

	var tween := label.create_tween()
	tween.tween_method(
		func(val: float): label.text = format_string % val,
		from_value,
		to_value,
		duration
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	tween.finished.connect(func(): finished.emit())
	return tween


## Damage number popup (floats up and fades)
func damage_popup(label: Label, damage: float, is_crit: bool = false,
		duration: float = 1.0) -> Tween:

	label.text = str(int(damage))
	if is_crit:
		label.add_theme_color_override("font_color", Color(1, 0.8, 0.2))  # Gold
		label.scale = Vector2(1.3, 1.3)
	else:
		label.add_theme_color_override("font_color", Color.WHITE)
		label.scale = Vector2.ONE

	label.modulate.a = 1.0
	label.visible = true

	var start_pos := label.position
	var end_pos := start_pos - Vector2(0, 60)

	var tween := label.create_tween()
	tween.set_parallel(true)

	tween.tween_property(label, "position", end_pos, duration)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, duration * 0.3).set_delay(duration * 0.7)

	if is_crit:
		tween.tween_property(label, "scale", Vector2(0.8, 0.8), duration * 0.5).set_delay(duration * 0.5)

	tween.finished.connect(func():
		label.queue_free()
		finished.emit()
	)
	return tween


# ============================================
# BUTTON ANIMATIONS
# ============================================

## Button hover effect
func button_hover(button: Control, scale_factor: float = 1.05) -> Tween:
	var tween := button.create_tween()
	tween.tween_property(button, "scale", Vector2.ONE * scale_factor, FAST_DURATION)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return tween


## Button unhover effect
func button_unhover(button: Control) -> Tween:
	var tween := button.create_tween()
	tween.tween_property(button, "scale", Vector2.ONE, FAST_DURATION)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	return tween


## Button press effect
func button_press(button: Control) -> Tween:
	var tween := button.create_tween()
	tween.tween_property(button, "scale", Vector2(0.95, 0.95), FAST_DURATION * 0.5)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(button, "scale", Vector2.ONE, FAST_DURATION)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	tween.finished.connect(func(): finished.emit())
	return tween


# ============================================
# TOOLTIP ANIMATIONS
# ============================================

## Reveal tooltip with slide and fade
func tooltip_show(tooltip: Control, anchor_pos: Vector2,
		direction: Direction = Direction.UP) -> Tween:

	# Position tooltip relative to anchor
	var offset := _get_tooltip_offset(tooltip, direction)
	tooltip.position = anchor_pos + offset

	var start_offset := 10.0
	match direction:
		Direction.UP:
			tooltip.position.y += start_offset
		Direction.DOWN:
			tooltip.position.y -= start_offset
		Direction.LEFT:
			tooltip.position.x += start_offset
		Direction.RIGHT:
			tooltip.position.x -= start_offset

	tooltip.modulate.a = 0.0
	tooltip.scale = Vector2(0.95, 0.95)
	tooltip.visible = true

	var final_pos := anchor_pos + offset

	var tween := tooltip.create_tween()
	tween.set_parallel(true)

	tween.tween_property(tooltip, "position", final_pos, FAST_DURATION)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(tooltip, "modulate:a", 1.0, FAST_DURATION * 0.7)
	tween.tween_property(tooltip, "scale", Vector2.ONE, FAST_DURATION)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	tween.finished.connect(func(): finished.emit())
	return tween


## Hide tooltip
func tooltip_hide(tooltip: Control) -> Tween:
	var tween := tooltip.create_tween()
	tween.set_parallel(true)

	tween.tween_property(tooltip, "modulate:a", 0.0, FAST_DURATION * 0.6)
	tween.tween_property(tooltip, "scale", Vector2(0.95, 0.95), FAST_DURATION)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

	tween.finished.connect(func():
		tooltip.visible = false
		tooltip.scale = Vector2.ONE
		finished.emit()
	)
	return tween


func _get_tooltip_offset(tooltip: Control, direction: Direction) -> Vector2:
	var gap := 8.0
	match direction:
		Direction.UP:
			return Vector2(-tooltip.size.x / 2, -tooltip.size.y - gap)
		Direction.DOWN:
			return Vector2(-tooltip.size.x / 2, gap)
		Direction.LEFT:
			return Vector2(-tooltip.size.x - gap, -tooltip.size.y / 2)
		Direction.RIGHT:
			return Vector2(gap, -tooltip.size.y / 2)
	return Vector2.ZERO


# ============================================
# PROGRESS BAR ANIMATIONS
# ============================================

## Animate progress bar fill
func progress_fill(progress_bar: ProgressBar, to_value: float,
		duration: float = 0.3) -> Tween:

	var tween := progress_bar.create_tween()
	tween.tween_property(progress_bar, "value", to_value, duration)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	tween.finished.connect(func(): finished.emit())
	return tween


## Health bar with damage flash effect
func health_change(health_bar: ProgressBar, old_value: float, new_value: float,
		duration: float = 0.4) -> Tween:

	var is_damage := new_value < old_value

	var tween := health_bar.create_tween()

	# Flash the bar
	if is_damage:
		tween.tween_property(health_bar, "modulate", Color(1.5, 0.5, 0.5), 0.05)
		tween.tween_property(health_bar, "modulate", Color.WHITE, 0.1)
	else:
		tween.tween_property(health_bar, "modulate", Color(0.5, 1.5, 0.5), 0.05)
		tween.tween_property(health_bar, "modulate", Color.WHITE, 0.1)

	# Animate the value change
	tween.tween_property(health_bar, "value", new_value, duration - 0.15)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	tween.finished.connect(func(): finished.emit())
	return tween


# ============================================
# LIST/GRID ANIMATIONS
# ============================================

## Stagger animation for list items
func stagger_in(items: Array[Control], direction: Direction = Direction.UP,
		stagger_delay: float = 0.05) -> Tween:

	if items.is_empty():
		return null

	var first_item := items[0]
	var tween := first_item.create_tween()

	for i in range(items.size()):
		var item := items[i]
		var target_pos := item.position
		var start_pos := _get_offscreen_pos(item, direction)

		item.position = start_pos
		item.modulate.a = 0.0
		item.visible = true

		var delay := i * stagger_delay

		tween.parallel().tween_property(item, "position", target_pos, DEFAULT_DURATION)\
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)\
			.set_delay(delay)
		tween.parallel().tween_property(item, "modulate:a", 1.0, DEFAULT_DURATION * 0.5)\
			.set_delay(delay)

	tween.finished.connect(func(): finished.emit())
	return tween


## Stagger out animation for list items
func stagger_out(items: Array[Control], direction: Direction = Direction.DOWN,
		stagger_delay: float = 0.03) -> Tween:

	if items.is_empty():
		return null

	var first_item := items[0]
	var tween := first_item.create_tween()

	for i in range(items.size()):
		var item := items[i]
		var target_pos := _get_offscreen_pos(item, direction)
		var delay := i * stagger_delay

		tween.parallel().tween_property(item, "position", target_pos, DEFAULT_DURATION)\
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)\
			.set_delay(delay)
		tween.parallel().tween_property(item, "modulate:a", 0.0, DEFAULT_DURATION * 0.5)\
			.set_delay(delay + DEFAULT_DURATION * 0.3)

	tween.finished.connect(func():
		for item in items:
			item.visible = false
		finished.emit()
	)
	return tween
