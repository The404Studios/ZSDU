extends Control
class_name StashGrid
## StashGrid - Tarkov-style grid inventory container
##
## Features:
## - Beautiful cell-based grid with hover effects
## - Smooth drag and drop with animated previews
## - Cell highlighting during drag operations
## - Visual feedback for valid/invalid placements

signal item_selected(item: StashItem)
signal item_context_menu(item: StashItem, position: Vector2)
signal item_hovered_changed(item: StashItem)
signal operation_complete(success: bool, message: String)

const CELL_SIZE := 64

# Visual constants
const BG_COLOR := Color(0.08, 0.08, 0.1, 1.0)
const CELL_BG_COLOR := Color(0.11, 0.11, 0.13, 1.0)
const CELL_BG_ALT_COLOR := Color(0.10, 0.10, 0.12, 1.0)
const GRID_LINE_COLOR := Color(0.18, 0.18, 0.2, 1.0)
const GRID_LINE_MAJOR_COLOR := Color(0.22, 0.22, 0.25, 1.0)
const CELL_HOVER_COLOR := Color(0.2, 0.2, 0.25, 0.5)

const VALID_DROP_COLOR := Color(0.15, 0.5, 0.2, 0.4)
const VALID_DROP_BORDER := Color(0.3, 0.8, 0.4, 0.8)
const INVALID_DROP_COLOR := Color(0.5, 0.15, 0.15, 0.4)
const INVALID_DROP_BORDER := Color(0.9, 0.3, 0.3, 0.8)

var grid_width: int = 10
var grid_height: int = 40

# Items in grid
var items: Dictionary = {}  # iid -> StashItem
var placements: Dictionary = {}  # "x,y" -> iid (for collision detection)

# Drag state
var dragging_item: StashItem = null
var drag_valid := false
var drop_target_x := -1
var drop_target_y := -1

# Hover state
var hover_cell_x := -1
var hover_cell_y := -1
var hovered_item: StashItem = null

# Animation
var drop_preview_alpha := 0.0
var _preview_tween: Tween = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_exited.connect(_on_mouse_exited)
	EconomyService.stash_updated.connect(_on_stash_updated)


func _process(delta: float) -> void:
	# Animate drop preview
	var target_alpha := 1.0 if dragging_item else 0.0
	var old_alpha := drop_preview_alpha
	drop_preview_alpha = lerpf(drop_preview_alpha, target_alpha, delta * 10.0)

	if abs(old_alpha - drop_preview_alpha) > 0.01:
		queue_redraw()


func _draw() -> void:
	var total_size := Vector2(grid_width * CELL_SIZE, grid_height * CELL_SIZE)

	# Background
	draw_rect(Rect2(Vector2.ZERO, total_size), BG_COLOR, true)

	# Draw cells with alternating pattern
	for x in range(grid_width):
		for y in range(grid_height):
			var cell_rect := Rect2(Vector2(x * CELL_SIZE, y * CELL_SIZE), Vector2(CELL_SIZE, CELL_SIZE))
			var is_alt := (x + y) % 2 == 1
			var cell_color := CELL_BG_ALT_COLOR if is_alt else CELL_BG_COLOR

			# Highlight hovered cell
			if x == hover_cell_x and y == hover_cell_y and not dragging_item:
				cell_color = cell_color.lerp(CELL_HOVER_COLOR, 0.5)

			draw_rect(cell_rect, cell_color, true)

	# Draw grid lines
	_draw_grid_lines()

	# Draw drop preview if dragging
	if dragging_item and drop_target_x >= 0 and drop_target_y >= 0 and drop_preview_alpha > 0.01:
		_draw_drop_preview()

	# Draw border
	draw_rect(Rect2(Vector2.ZERO, total_size), Color(0.25, 0.25, 0.28), false, 2.0)

	# Draw corner accents
	_draw_corner_accents(Rect2(Vector2.ZERO, total_size))


func _draw_grid_lines() -> void:
	var total_height := grid_height * CELL_SIZE
	var total_width := grid_width * CELL_SIZE

	# Vertical lines
	for x in range(grid_width + 1):
		var is_major := x % 5 == 0
		var color := GRID_LINE_MAJOR_COLOR if is_major else GRID_LINE_COLOR
		var width := 1.5 if is_major else 1.0
		draw_line(Vector2(x * CELL_SIZE, 0), Vector2(x * CELL_SIZE, total_height), color, width)

	# Horizontal lines
	for y in range(grid_height + 1):
		var is_major := y % 5 == 0
		var color := GRID_LINE_MAJOR_COLOR if is_major else GRID_LINE_COLOR
		var width := 1.5 if is_major else 1.0
		draw_line(Vector2(0, y * CELL_SIZE), Vector2(total_width, y * CELL_SIZE), color, width)


func _draw_drop_preview() -> void:
	var preview_pos := Vector2(drop_target_x * CELL_SIZE, drop_target_y * CELL_SIZE)
	var preview_size := Vector2(
		dragging_item.get_grid_width() * CELL_SIZE,
		dragging_item.get_grid_height() * CELL_SIZE
	)
	var preview_rect := Rect2(preview_pos, preview_size)

	var fill_color: Color
	var border_color: Color
	if drag_valid:
		fill_color = VALID_DROP_COLOR
		border_color = VALID_DROP_BORDER
	else:
		fill_color = INVALID_DROP_COLOR
		border_color = INVALID_DROP_BORDER

	# Apply animation alpha
	fill_color.a *= drop_preview_alpha
	border_color.a *= drop_preview_alpha

	# Draw filled preview
	draw_rect(preview_rect, fill_color, true)

	# Draw animated dashed border
	var dash_length := 8.0
	var gap_length := 4.0
	var time_offset := fmod(Time.get_ticks_msec() / 200.0, dash_length + gap_length)

	_draw_dashed_rect(preview_rect, border_color, 2.0, dash_length, gap_length, time_offset)

	# Draw cell highlights within preview
	for dx in range(dragging_item.get_grid_width()):
		for dy in range(dragging_item.get_grid_height()):
			var cell_pos := preview_pos + Vector2(dx * CELL_SIZE, dy * CELL_SIZE)
			var cell_rect := Rect2(cell_pos + Vector2(2, 2), Vector2(CELL_SIZE - 4, CELL_SIZE - 4))
			var cell_highlight := fill_color
			cell_highlight.a *= 0.3
			draw_rect(cell_rect, cell_highlight, true)


func _draw_dashed_rect(rect: Rect2, color: Color, width: float, dash: float, gap: float, offset: float) -> void:
	var points := [
		rect.position,
		Vector2(rect.end.x, rect.position.y),
		rect.end,
		Vector2(rect.position.x, rect.end.y),
		rect.position
	]

	for i in range(4):
		_draw_dashed_line(points[i], points[i + 1], color, width, dash, gap, offset)


func _draw_dashed_line(from: Vector2, to: Vector2, color: Color, width: float, dash: float, gap: float, offset: float) -> void:
	var length := from.distance_to(to)
	var direction := (to - from).normalized()
	var pattern_length := dash + gap

	var pos := offset
	while pos < length:
		var start := from + direction * pos
		var end := from + direction * minf(pos + dash, length)
		draw_line(start, end, color, width)
		pos += pattern_length


func _draw_corner_accents(rect: Rect2) -> void:
	var accent_length := 12.0
	var accent_color := Color(0.35, 0.35, 0.4)

	# Top-left
	draw_line(rect.position, rect.position + Vector2(accent_length, 0), accent_color, 2.0)
	draw_line(rect.position, rect.position + Vector2(0, accent_length), accent_color, 2.0)

	# Top-right
	var tr := Vector2(rect.end.x, rect.position.y)
	draw_line(tr, tr - Vector2(accent_length, 0), accent_color, 2.0)
	draw_line(tr, tr + Vector2(0, accent_length), accent_color, 2.0)

	# Bottom-left
	var bl := Vector2(rect.position.x, rect.end.y)
	draw_line(bl, bl + Vector2(accent_length, 0), accent_color, 2.0)
	draw_line(bl, bl - Vector2(0, accent_length), accent_color, 2.0)

	# Bottom-right
	draw_line(rect.end, rect.end - Vector2(accent_length, 0), accent_color, 2.0)
	draw_line(rect.end, rect.end - Vector2(0, accent_length), accent_color, 2.0)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_update_hover(event.position)
		if dragging_item:
			_update_drop_preview(event.position)

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			if dragging_item:
				_attempt_drop()


func _update_hover(pos: Vector2) -> void:
	var new_x := int(pos.x / CELL_SIZE)
	var new_y := int(pos.y / CELL_SIZE)

	# Clamp to grid
	new_x = clampi(new_x, 0, grid_width - 1)
	new_y = clampi(new_y, 0, grid_height - 1)

	if new_x != hover_cell_x or new_y != hover_cell_y:
		hover_cell_x = new_x
		hover_cell_y = new_y
		queue_redraw()


func _on_mouse_exited() -> void:
	hover_cell_x = -1
	hover_cell_y = -1
	queue_redraw()


func setup(width: int, height: int) -> void:
	grid_width = width
	grid_height = height
	custom_minimum_size = Vector2(grid_width * CELL_SIZE, grid_height * CELL_SIZE)
	size = custom_minimum_size
	queue_redraw()


func refresh() -> void:
	# Clear existing items with fade out animation
	for child in get_children():
		if child is StashItem:
			child.queue_free()

	items.clear()
	placements.clear()

	# Get data from EconomyService
	var stash_placements: Array = EconomyService.get_placements()

	# Create items with staggered animation
	var delay := 0.0
	for placement in stash_placements:
		var iid: String = placement.get("iid", "")
		var x: int = placement.get("x", 0)
		var y: int = placement.get("y", 0)
		var rot: int = placement.get("rotation", placement.get("rot", 0))

		var item_data: Dictionary = EconomyService.get_item(iid)
		if item_data.is_empty():
			continue

		var def_id: String = item_data.get("def_id", item_data.get("defId", ""))
		var item_def: Dictionary = EconomyService.get_item_def(def_id)
		if item_def.is_empty():
			item_def = { "name": def_id, "w": 1, "h": 1, "rarity": "common" }

		var item := _create_item(iid, item_data, item_def, x, y, rot)

		# Animate item appearing
		item.modulate.a = 0.0
		item.scale = Vector2(0.8, 0.8)

		var tween := create_tween()
		tween.set_parallel(true)
		tween.tween_property(item, "modulate:a", 1.0, 0.2).set_delay(delay)
		tween.tween_property(item, "scale", Vector2.ONE, 0.25).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

		delay += 0.02  # Stagger

	queue_redraw()


func _create_item(iid: String, item_data: Dictionary, item_def: Dictionary, x: int, y: int, rotation: int) -> StashItem:
	var item := StashItem.new()
	add_child(item)
	item.setup(iid, item_data, item_def, x, y, rotation)

	# Register in dictionaries
	items[iid] = item
	_register_placement(iid, x, y, item.get_grid_width(), item.get_grid_height())

	# Connect signals
	item.item_clicked.connect(_on_item_clicked)
	item.item_right_clicked.connect(_on_item_right_clicked)
	item.item_hovered.connect(_on_item_hovered)
	item.item_unhovered.connect(_on_item_unhovered)
	item.drag_started.connect(_on_item_drag_started)
	item.drag_ended.connect(_on_item_drag_ended)

	return item


func _register_placement(iid: String, x: int, y: int, w: int, h: int) -> void:
	for dx in range(w):
		for dy in range(h):
			placements["%d,%d" % [x + dx, y + dy]] = iid


func _unregister_placement(iid: String, x: int, y: int, w: int, h: int) -> void:
	for dx in range(w):
		for dy in range(h):
			var key := "%d,%d" % [x + dx, y + dy]
			if key in placements and placements[key] == iid:
				placements.erase(key)


func _check_collision(x: int, y: int, w: int, h: int, exclude_iid: String = "") -> bool:
	# Check bounds
	if x < 0 or y < 0 or x + w > grid_width or y + h > grid_height:
		return true

	# Check for overlapping items
	for dx in range(w):
		for dy in range(h):
			var key := "%d,%d" % [x + dx, y + dy]
			if key in placements:
				if placements[key] != exclude_iid:
					return true

	return false


func _update_drop_preview(mouse_pos: Vector2) -> void:
	if not dragging_item:
		return

	# Calculate target grid position (centered on cursor)
	var target_x := int(mouse_pos.x / CELL_SIZE) - dragging_item.get_grid_width() / 2
	var target_y := int(mouse_pos.y / CELL_SIZE) - dragging_item.get_grid_height() / 2

	# Clamp to grid bounds
	target_x = clampi(target_x, 0, grid_width - dragging_item.get_grid_width())
	target_y = clampi(target_y, 0, grid_height - dragging_item.get_grid_height())

	var changed := target_x != drop_target_x or target_y != drop_target_y

	drop_target_x = target_x
	drop_target_y = target_y

	# Check if drop is valid
	drag_valid = not _check_collision(
		target_x, target_y,
		dragging_item.get_grid_width(),
		dragging_item.get_grid_height(),
		dragging_item.iid
	)

	if changed:
		queue_redraw()


func _attempt_drop() -> void:
	if not dragging_item:
		return

	if not drag_valid or drop_target_x < 0 or drop_target_y < 0:
		dragging_item.cancel_drag()
		_clear_drag_state()
		return

	# Check if position changed
	if drop_target_x == dragging_item.grid_x and drop_target_y == dragging_item.grid_y:
		dragging_item.cancel_drag()
		_clear_drag_state()
		return

	# Store old state for potential rollback
	var iid := dragging_item.iid
	var old_x := dragging_item.grid_x
	var old_y := dragging_item.grid_y
	var old_w := dragging_item.get_grid_width()
	var old_h := dragging_item.get_grid_height()
	var new_x := drop_target_x
	var new_y := drop_target_y

	# Optimistically update UI with animation
	_unregister_placement(iid, old_x, old_y, old_w, old_h)
	dragging_item.animate_to_position(new_x, new_y)
	_register_placement(iid, new_x, new_y, old_w, old_h)

	_clear_drag_state()

	# Send to backend
	var success := await EconomyService.move_item(iid, new_x, new_y, dragging_item.item_rotation)

	if not success:
		# Revert on failure with animation
		if iid in items:
			var item: StashItem = items[iid]
			_unregister_placement(iid, item.grid_x, item.grid_y, item.get_grid_width(), item.get_grid_height())
			item.animate_to_position(old_x, old_y)
			_register_placement(iid, old_x, old_y, old_w, old_h)

		operation_complete.emit(false, "Failed to move item")
	else:
		operation_complete.emit(true, "Item moved")


func _clear_drag_state() -> void:
	dragging_item = null
	drag_valid = false
	drop_target_x = -1
	drop_target_y = -1
	queue_redraw()


func _on_item_clicked(item: StashItem) -> void:
	item_selected.emit(item)


func _on_item_right_clicked(item: StashItem) -> void:
	item_context_menu.emit(item, get_global_mouse_position())


func _on_item_hovered(item: StashItem) -> void:
	hovered_item = item
	item_hovered_changed.emit(item)


func _on_item_unhovered(_item: StashItem) -> void:
	hovered_item = null
	item_hovered_changed.emit(null)


func _on_item_drag_started(item: StashItem) -> void:
	dragging_item = item
	queue_redraw()


func _on_item_drag_ended(_item: StashItem, _success: bool) -> void:
	# Handled in _attempt_drop
	pass


func _on_stash_updated(_stash: Dictionary, _items: Array, _wallet: Dictionary) -> void:
	refresh()


func get_item_at(x: int, y: int) -> StashItem:
	var key := "%d,%d" % [x, y]
	if key in placements:
		var iid: String = placements[key]
		if iid in items:
			return items[iid]
	return null


## Get the currently hovered item
func get_hovered_item() -> StashItem:
	return hovered_item
