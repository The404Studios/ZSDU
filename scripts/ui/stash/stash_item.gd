extends Control
class_name StashItem
## StashItem - Draggable item in the stash grid
##
## Represents a single item instance that can be dragged within the grid.
## Handles visual display, drag preview, and interactions.

signal item_clicked(item: StashItem)
signal item_right_clicked(item: StashItem)
signal drag_started(item: StashItem)
signal drag_ended(item: StashItem, success: bool)

const CELL_SIZE := 64  # Pixels per grid cell

# Item data
var iid: String = ""
var def_id: String = ""
var item_data: Dictionary = {}
var item_def: Dictionary = {}
var grid_x: int = 0
var grid_y: int = 0
var item_rotation: int = 0  # 0 or 1

# Visual
var is_dragging := false
var drag_offset := Vector2.ZERO
var is_locked := false

# Colors
var normal_color := Color(0.15, 0.15, 0.15, 0.9)
var hover_color := Color(0.25, 0.25, 0.25, 0.9)
var locked_color := Color(0.4, 0.15, 0.15, 0.9)
var border_color := Color(0.5, 0.5, 0.5)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


func setup(p_iid: String, p_item_data: Dictionary, p_item_def: Dictionary, p_x: int, p_y: int, p_rotation: int = 0) -> void:
	iid = p_iid
	item_data = p_item_data
	item_def = p_item_def
	def_id = p_item_data.get("def_id", p_item_data.get("defId", ""))
	grid_x = p_x
	grid_y = p_y
	item_rotation = p_rotation

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


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)

	# Background
	var bg_color: Color
	if is_locked:
		bg_color = locked_color
	elif is_dragging:
		bg_color = hover_color
	else:
		bg_color = normal_color

	draw_rect(rect, bg_color, true)

	# Border
	draw_rect(rect, border_color, false, 2.0)

	# Item name
	var item_name: String = item_def.get("name", def_id)
	var font := ThemeDB.fallback_font
	var font_size := 12

	# Truncate name if too long
	var max_chars := int(size.x / 8)
	if item_name.length() > max_chars:
		item_name = item_name.substr(0, max_chars - 2) + ".."

	var text_pos := Vector2(4, size.y / 2 + 4)
	draw_string(font, text_pos, item_name, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)

	# Stack count (if stackable)
	var stack: int = item_data.get("stack", 1)
	if stack > 1:
		var stack_text := "x%d" % stack
		var stack_pos := Vector2(size.x - 24, size.y - 6)
		draw_string(font, stack_pos, stack_text, HORIZONTAL_ALIGNMENT_RIGHT, -1, font_size, Color.YELLOW)

	# Durability bar (if has durability)
	var durability: float = item_data.get("durability", 1.0)
	if durability < 1.0:
		var bar_y := size.y - 6
		var bar_width := size.x - 8
		var bar_height := 4.0

		# Background bar
		draw_rect(Rect2(4, bar_y, bar_width, bar_height), Color(0.3, 0.3, 0.3), true)

		# Durability bar
		var dur_color := Color.GREEN if durability > 0.5 else (Color.YELLOW if durability > 0.25 else Color.RED)
		draw_rect(Rect2(4, bar_y, bar_width * durability, bar_height), dur_color, true)

	# Lock indicator
	if is_locked:
		var lock_text := "LOCKED"
		var lock_pos := Vector2(size.x / 2 - 20, 14)
		draw_string(font, lock_pos, lock_text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, Color.RED)


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

	drag_started.emit(self)
	queue_redraw()


func _end_drag(success: bool) -> void:
	is_dragging = false
	z_index = 0

	drag_ended.emit(self, success)
	queue_redraw()


func cancel_drag() -> void:
	if is_dragging:
		is_dragging = false
		z_index = 0
		# Reset position to grid position
		position = Vector2(grid_x * CELL_SIZE, grid_y * CELL_SIZE)
		queue_redraw()


func get_grid_width() -> int:
	var w: int = item_def.get("w", item_def.get("width", 1))
	var h: int = item_def.get("h", item_def.get("height", 1))
	return h if item_rotation == 1 else w


func get_grid_height() -> int:
	var w: int = item_def.get("w", item_def.get("width", 1))
	var h: int = item_def.get("h", item_def.get("height", 1))
	return w if item_rotation == 1 else h


func get_tooltip_text() -> String:
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
