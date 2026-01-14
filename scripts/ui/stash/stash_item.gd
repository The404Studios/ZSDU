extends Control
class_name StashItem
## StashItem - Tarkov-style draggable inventory item
##
## Features:
## - Rarity-based border colors and glow
## - Smooth animations on hover/drag
## - Icon background with gradient
## - Stack count, durability bar
## - Visual feedback for locked items

signal item_clicked(item: StashItem)
signal item_right_clicked(item: StashItem)
signal item_hovered(item: StashItem)
signal item_unhovered(item: StashItem)
signal drag_started(item: StashItem)
signal drag_ended(item: StashItem, success: bool)

const CELL_SIZE := 64  # Pixels per grid cell

# Rarity colors (Tarkov-inspired)
const RARITY_COLORS := {
	"common": Color(0.45, 0.45, 0.45),
	"uncommon": Color(0.35, 0.55, 0.35),
	"rare": Color(0.35, 0.45, 0.7),
	"epic": Color(0.55, 0.35, 0.65),
	"legendary": Color(0.8, 0.6, 0.2),
	"quest": Color(0.9, 0.75, 0.3),
}

const RARITY_GLOW := {
	"common": Color(0.3, 0.3, 0.3, 0.0),
	"uncommon": Color(0.3, 0.6, 0.3, 0.15),
	"rare": Color(0.3, 0.4, 0.8, 0.2),
	"epic": Color(0.6, 0.3, 0.7, 0.25),
	"legendary": Color(0.9, 0.7, 0.2, 0.3),
	"quest": Color(1.0, 0.9, 0.4, 0.35),
}

# Item data
var iid: String = ""
var def_id: String = ""
var item_data: Dictionary = {}
var item_def: Dictionary = {}
var grid_x: int = 0
var grid_y: int = 0
var item_rotation: int = 0  # 0 or 1

# Visual state
var is_dragging := false
var is_hovered := false
var drag_offset := Vector2.ZERO
var is_locked := false
var rarity: String = "common"

# Animation
var hover_progress: float = 0.0
var drag_scale: float = 1.0
var glow_pulse: float = 0.0
var _tween: Tween = null

# Cached visuals
var _border_color: Color = Color.GRAY
var _glow_color: Color = Color.TRANSPARENT
var _bg_gradient: Gradient = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)


func _process(delta: float) -> void:
	# Animate hover
	var target_hover := 1.0 if is_hovered else 0.0
	hover_progress = lerpf(hover_progress, target_hover, delta * 12.0)

	# Animate glow pulse for rare+ items
	if rarity in ["rare", "epic", "legendary", "quest"]:
		glow_pulse += delta * 2.0
		if glow_pulse > TAU:
			glow_pulse -= TAU
		queue_redraw()
	elif hover_progress > 0.01 or hover_progress < 0.99:
		queue_redraw()


func setup(p_iid: String, p_item_data: Dictionary, p_item_def: Dictionary, p_x: int, p_y: int, p_rotation: int = 0) -> void:
	iid = p_iid
	item_data = p_item_data
	item_def = p_item_def
	def_id = p_item_data.get("def_id", p_item_data.get("defId", ""))
	grid_x = p_x
	grid_y = p_y
	item_rotation = p_rotation

	# Get rarity
	rarity = item_def.get("rarity", "common").to_lower()
	if rarity not in RARITY_COLORS:
		rarity = "common"

	# Cache colors
	_border_color = RARITY_COLORS.get(rarity, Color.GRAY)
	_glow_color = RARITY_GLOW.get(rarity, Color.TRANSPARENT)

	# Create background gradient
	_create_bg_gradient()

	# Check if locked
	var flags: Dictionary = item_data.get("flags", {})
	is_locked = flags.get("in_raid", false) or flags.get("in_escrow", false)

	# Calculate size based on item dimensions
	var w: int = item_def.get("w", item_def.get("width", 1))
	var h: int = item_def.get("h", item_def.get("height", 1))

	# Apply rotation
	if item_rotation == 1:
		var temp := w
		w = h
		h = temp

	custom_minimum_size = Vector2(w * CELL_SIZE, h * CELL_SIZE)
	size = custom_minimum_size
	position = Vector2(grid_x * CELL_SIZE, grid_y * CELL_SIZE)

	queue_redraw()


func _create_bg_gradient() -> void:
	_bg_gradient = Gradient.new()

	var base_color := Color(0.12, 0.12, 0.14)
	var highlight := _border_color.lerp(Color.WHITE, 0.1)

	_bg_gradient.set_color(0, base_color.lerp(highlight, 0.15))
	_bg_gradient.set_color(1, base_color)


func _draw() -> void:
	var rect := Rect2(Vector2(2, 2), size - Vector2(4, 4))
	var outer_rect := Rect2(Vector2.ZERO, size)

	# Outer glow (for rare+ items)
	if _glow_color.a > 0:
		var pulse_mult := 0.7 + 0.3 * sin(glow_pulse)
		var glow := _glow_color
		glow.a *= pulse_mult

		# Draw multiple glow layers
		for i in range(3):
			var glow_rect := outer_rect.grow(2 + i * 2)
			var layer_alpha := glow.a * (1.0 - i * 0.3)
			draw_rect(glow_rect, Color(glow.r, glow.g, glow.b, layer_alpha * 0.3), true)

	# Background with gradient
	_draw_gradient_rect(rect)

	# Hover overlay
	if hover_progress > 0.01:
		var hover_color := Color(1, 1, 1, 0.08 * hover_progress)
		draw_rect(rect, hover_color, true)

	# Inner shadow (top-left)
	var shadow_color := Color(0, 0, 0, 0.4)
	draw_line(rect.position, rect.position + Vector2(rect.size.x, 0), shadow_color, 1.0)
	draw_line(rect.position, rect.position + Vector2(0, rect.size.y), shadow_color, 1.0)

	# Inner highlight (bottom-right)
	var highlight_color := Color(1, 1, 1, 0.1)
	draw_line(rect.end - Vector2(rect.size.x, 0), rect.end, highlight_color, 1.0)
	draw_line(rect.end - Vector2(0, rect.size.y), rect.end, highlight_color, 1.0)

	# Border with rarity color
	var border_width := 2.0 if is_hovered else 1.5
	var final_border := _border_color
	if is_hovered:
		final_border = final_border.lerp(Color.WHITE, 0.3)
	if is_locked:
		final_border = Color(0.6, 0.2, 0.2)

	draw_rect(outer_rect, final_border, false, border_width)

	# Corner accents (Tarkov style)
	_draw_corner_accents(outer_rect, final_border)

	# Icon area background
	var icon_size := mini(int(size.x), int(size.y)) - 16
	var icon_rect := Rect2(
		Vector2((size.x - icon_size) / 2, 8),
		Vector2(icon_size, icon_size * 0.7)
	)
	draw_rect(icon_rect, Color(0, 0, 0, 0.3), true)

	# Item name
	var item_name: String = item_def.get("name", def_id)
	var font := ThemeDB.fallback_font
	var font_size := 11

	# Truncate name if too long
	var max_chars := int(size.x / 7)
	if item_name.length() > max_chars:
		item_name = item_name.substr(0, max_chars - 2) + ".."

	# Name background
	var name_bg_rect := Rect2(2, size.y - 22, size.x - 4, 20)
	draw_rect(name_bg_rect, Color(0, 0, 0, 0.6), true)

	# Name text with shadow
	var text_pos := Vector2(6, size.y - 8)
	draw_string(font, text_pos + Vector2(1, 1), item_name, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0, 0, 0, 0.5))
	draw_string(font, text_pos, item_name, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)

	# Stack count (if stackable)
	var stack: int = item_data.get("stack", 1)
	if stack > 1:
		var stack_text := "x%d" % stack
		var stack_pos := Vector2(size.x - 8, size.y - 8)

		# Stack background
		var stack_width := font.get_string_size(stack_text, HORIZONTAL_ALIGNMENT_RIGHT, -1, font_size).x + 8
		var stack_bg := Rect2(size.x - stack_width - 4, size.y - 22, stack_width + 2, 18)
		draw_rect(stack_bg, Color(0.1, 0.1, 0.1, 0.8), true)

		draw_string(font, stack_pos + Vector2(1, 1), stack_text, HORIZONTAL_ALIGNMENT_RIGHT, -1, font_size, Color(0, 0, 0, 0.5))
		draw_string(font, stack_pos, stack_text, HORIZONTAL_ALIGNMENT_RIGHT, -1, font_size, Color(1, 0.9, 0.4))

	# Durability bar (if has durability < 100%)
	var durability: float = item_data.get("durability", 1.0)
	if durability < 1.0:
		_draw_durability_bar(durability)

	# Lock overlay
	if is_locked:
		_draw_locked_overlay()

	# Dragging visual
	if is_dragging:
		draw_rect(outer_rect, Color(1, 1, 1, 0.15), true)


func _draw_gradient_rect(rect: Rect2) -> void:
	if not _bg_gradient:
		draw_rect(rect, Color(0.12, 0.12, 0.14), true)
		return

	# Draw gradient from top to bottom
	var steps := 8
	var step_height := rect.size.y / steps

	for i in range(steps):
		var t := float(i) / (steps - 1)
		var color := _bg_gradient.sample(t)
		var step_rect := Rect2(
			rect.position + Vector2(0, i * step_height),
			Vector2(rect.size.x, step_height + 1)
		)
		draw_rect(step_rect, color, true)


func _draw_corner_accents(rect: Rect2, color: Color) -> void:
	var accent_length := 8.0
	var accent_color := color.lerp(Color.WHITE, 0.2)

	# Top-left corner
	draw_line(rect.position, rect.position + Vector2(accent_length, 0), accent_color, 2.0)
	draw_line(rect.position, rect.position + Vector2(0, accent_length), accent_color, 2.0)

	# Top-right corner
	var tr := Vector2(rect.end.x, rect.position.y)
	draw_line(tr, tr - Vector2(accent_length, 0), accent_color, 2.0)
	draw_line(tr, tr + Vector2(0, accent_length), accent_color, 2.0)

	# Bottom-left corner
	var bl := Vector2(rect.position.x, rect.end.y)
	draw_line(bl, bl + Vector2(accent_length, 0), accent_color, 2.0)
	draw_line(bl, bl - Vector2(0, accent_length), accent_color, 2.0)

	# Bottom-right corner
	draw_line(rect.end, rect.end - Vector2(accent_length, 0), accent_color, 2.0)
	draw_line(rect.end, rect.end - Vector2(0, accent_length), accent_color, 2.0)


func _draw_durability_bar(durability: float) -> void:
	var bar_margin := 4.0
	var bar_height := 4.0
	var bar_y := size.y - 26

	var bg_rect := Rect2(bar_margin, bar_y, size.x - bar_margin * 2, bar_height)
	var fill_rect := Rect2(bar_margin, bar_y, (size.x - bar_margin * 2) * durability, bar_height)

	# Background
	draw_rect(bg_rect, Color(0.1, 0.1, 0.1, 0.8), true)
	draw_rect(bg_rect, Color(0.3, 0.3, 0.3), false, 1.0)

	# Fill color based on durability
	var fill_color: Color
	if durability > 0.6:
		fill_color = Color(0.3, 0.7, 0.3)
	elif durability > 0.3:
		fill_color = Color(0.8, 0.7, 0.2)
	else:
		fill_color = Color(0.8, 0.25, 0.2)

	draw_rect(fill_rect, fill_color, true)

	# Shine effect
	var shine_rect := Rect2(bar_margin, bar_y, fill_rect.size.x, bar_height * 0.4)
	draw_rect(shine_rect, Color(1, 1, 1, 0.2), true)


func _draw_locked_overlay() -> void:
	# Semi-transparent red overlay
	var overlay := Rect2(Vector2(2, 2), size - Vector2(4, 4))
	draw_rect(overlay, Color(0.4, 0.1, 0.1, 0.5), true)

	# Lock icon (simple)
	var center := size / 2 - Vector2(0, 10)
	var lock_size := 16.0

	# Lock body
	draw_rect(
		Rect2(center - Vector2(lock_size/2, 0), Vector2(lock_size, lock_size * 0.8)),
		Color(0.8, 0.2, 0.2),
		true
	)

	# Lock shackle
	draw_arc(
		center - Vector2(0, 2),
		lock_size * 0.35,
		PI, 0,
		8,
		Color(0.8, 0.2, 0.2),
		3.0
	)

	# "LOCKED" text
	var font := ThemeDB.fallback_font
	var lock_pos := Vector2(size.x / 2, center.y + lock_size + 14)
	draw_string(font, lock_pos, "LOCKED", HORIZONTAL_ALIGNMENT_CENTER, -1, 10, Color(1, 0.3, 0.3))


func _on_mouse_entered() -> void:
	is_hovered = true
	item_hovered.emit(self)

	# Animate scale slightly
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "scale", Vector2(1.02, 1.02), 0.1).set_ease(Tween.EASE_OUT)


func _on_mouse_exited() -> void:
	is_hovered = false
	item_unhovered.emit(self)

	# Reset scale
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "scale", Vector2.ONE, 0.1).set_ease(Tween.EASE_OUT)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				item_clicked.emit(self)
				if not is_locked:
					_start_drag()
			else:
				if is_dragging:
					_end_drag(true)

		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			item_right_clicked.emit(self)


func _input(event: InputEvent) -> void:
	if is_dragging and event is InputEventMouseMotion:
		global_position = get_global_mouse_position() - drag_offset
		queue_redraw()


func _start_drag() -> void:
	if is_locked:
		return

	is_dragging = true
	drag_offset = get_local_mouse_position()
	z_index = 100  # Bring to front

	# Scale up animation
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "scale", Vector2(1.05, 1.05), 0.1).set_ease(Tween.EASE_OUT)
	_tween.parallel().tween_property(self, "modulate:a", 0.85, 0.1)

	drag_started.emit(self)
	queue_redraw()


func _end_drag(success: bool) -> void:
	is_dragging = false
	z_index = 0

	# Scale back animation
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "scale", Vector2.ONE, 0.15).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	_tween.parallel().tween_property(self, "modulate:a", 1.0, 0.1)

	drag_ended.emit(self, success)
	queue_redraw()


func cancel_drag() -> void:
	if is_dragging:
		is_dragging = false
		z_index = 0

		# Animate back to position
		if _tween:
			_tween.kill()
		_tween = create_tween()
		_tween.tween_property(self, "position", Vector2(grid_x * CELL_SIZE, grid_y * CELL_SIZE), 0.2).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		_tween.parallel().tween_property(self, "scale", Vector2.ONE, 0.15)
		_tween.parallel().tween_property(self, "modulate:a", 1.0, 0.1)

		queue_redraw()


## Animate item to new position (for smooth grid placement)
func animate_to_position(new_x: int, new_y: int) -> void:
	grid_x = new_x
	grid_y = new_y

	var target_pos := Vector2(grid_x * CELL_SIZE, grid_y * CELL_SIZE)

	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "position", target_pos, 0.15).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)


func get_grid_width() -> int:
	var w: int = item_def.get("w", item_def.get("width", 1))
	var h: int = item_def.get("h", item_def.get("height", 1))
	return h if item_rotation == 1 else w


func get_grid_height() -> int:
	var w: int = item_def.get("w", item_def.get("width", 1))
	var h: int = item_def.get("h", item_def.get("height", 1))
	return w if item_rotation == 1 else h


func get_rarity_color() -> Color:
	return _border_color


func get_item_tooltip_text() -> String:
	var name_text: String = item_def.get("name", def_id)
	var desc: String = item_def.get("description", "")
	var category: String = item_def.get("category", "misc")
	var value: int = item_def.get("base_value", item_def.get("baseValue", 0))
	var stack: int = item_data.get("stack", 1)
	var durability: float = item_data.get("durability", 1.0)

	var tooltip := "%s\n" % name_text
	tooltip += "[%s]\n" % category.capitalize()

	if desc != "":
		tooltip += "%s\n" % desc

	if stack > 1:
		tooltip += "Stack: %d\n" % stack

	if durability < 1.0:
		tooltip += "Durability: %d%%\n" % int(durability * 100)

	tooltip += "Value: %d gold" % value

	var flags: Dictionary = item_data.get("flags", {})
	if flags.get("in_raid", false):
		tooltip += "\n[IN RAID]"
	if flags.get("in_escrow", false):
		tooltip += "\n[IN ESCROW]"

	return tooltip
