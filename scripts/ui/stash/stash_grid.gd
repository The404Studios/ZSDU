extends Control
class_name StashGrid
## StashGrid - Grid-based inventory container (Tarkov-style)
##
## Displays items on a grid with drag-and-drop functionality.
## Communicates with EconomyService for backend operations.

signal item_selected(item: StashItem)
signal item_context_menu(item: StashItem, position: Vector2)
signal operation_complete(success: bool, message: String)

const CELL_SIZE := 64
const GRID_COLOR := Color(0.2, 0.2, 0.2, 0.5)
const GRID_LINE_COLOR := Color(0.3, 0.3, 0.3)
const VALID_DROP_COLOR := Color(0.2, 0.5, 0.2, 0.5)
const INVALID_DROP_COLOR := Color(0.5, 0.2, 0.2, 0.5)

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

# Scene for items
var stash_item_script: GDScript = preload("res://scripts/ui/stash/stash_item.gd")


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	EconomyService.stash_updated.connect(_on_stash_updated)


func _draw() -> void:
	# Draw grid background
	var grid_rect := Rect2(Vector2.ZERO, Vector2(grid_width * CELL_SIZE, grid_height * CELL_SIZE))
	draw_rect(grid_rect, GRID_COLOR, true)

	# Draw grid lines
	for x in range(grid_width + 1):
		draw_line(
			Vector2(x * CELL_SIZE, 0),
			Vector2(x * CELL_SIZE, grid_height * CELL_SIZE),
			GRID_LINE_COLOR, 1.0
		)

	for y in range(grid_height + 1):
		draw_line(
			Vector2(0, y * CELL_SIZE),
			Vector2(grid_width * CELL_SIZE, y * CELL_SIZE),
			GRID_LINE_COLOR, 1.0
		)

	# Draw drop preview if dragging
	if dragging_item and drop_target_x >= 0 and drop_target_y >= 0:
		var preview_rect := Rect2(
			Vector2(drop_target_x * CELL_SIZE, drop_target_y * CELL_SIZE),
			Vector2(dragging_item.get_grid_width() * CELL_SIZE, dragging_item.get_grid_height() * CELL_SIZE)
		)
		var preview_color := VALID_DROP_COLOR if drag_valid else INVALID_DROP_COLOR
		draw_rect(preview_rect, preview_color, true)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and dragging_item:
		_update_drop_preview(event.position)

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			if dragging_item:
				_attempt_drop()


func setup(width: int, height: int) -> void:
	grid_width = width
	grid_height = height
	custom_minimum_size = Vector2(grid_width * CELL_SIZE, grid_height * CELL_SIZE)
	size = custom_minimum_size
	queue_redraw()


func refresh() -> void:
	# Clear existing items
	for child in get_children():
		if child is StashItem:
			child.queue_free()

	items.clear()
	placements.clear()

	# Get data from EconomyService
	var stash_placements: Array = EconomyService.get_placements()

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
			item_def = { "name": def_id, "w": 1, "h": 1 }

		_create_item(iid, item_data, item_def, x, y, rot)

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

	# Calculate target grid position
	var target_x := int(mouse_pos.x / CELL_SIZE)
	var target_y := int(mouse_pos.y / CELL_SIZE)

	# Center on item
	target_x -= dragging_item.get_grid_width() / 2
	target_y -= dragging_item.get_grid_height() / 2

	# Clamp to grid bounds
	target_x = clampi(target_x, 0, grid_width - dragging_item.get_grid_width())
	target_y = clampi(target_y, 0, grid_height - dragging_item.get_grid_height())

	drop_target_x = target_x
	drop_target_y = target_y

	# Check if drop is valid
	drag_valid = not _check_collision(
		target_x, target_y,
		dragging_item.get_grid_width(),
		dragging_item.get_grid_height(),
		dragging_item.iid
	)

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

	# Request move from backend
	var iid := dragging_item.iid
	var old_x := dragging_item.grid_x
	var old_y := dragging_item.grid_y
	var old_w := dragging_item.get_grid_width()
	var old_h := dragging_item.get_grid_height()

	# Optimistically update UI
	_unregister_placement(iid, old_x, old_y, old_w, old_h)
	dragging_item.grid_x = drop_target_x
	dragging_item.grid_y = drop_target_y
	dragging_item.position = Vector2(drop_target_x * CELL_SIZE, drop_target_y * CELL_SIZE)
	_register_placement(iid, drop_target_x, drop_target_y, old_w, old_h)

	_clear_drag_state()

	# Send to backend
	var success := await EconomyService.move_item(iid, drop_target_x, drop_target_y, dragging_item.item_rotation)

	if not success:
		# Revert on failure
		if iid in items:
			var item: StashItem = items[iid]
			_unregister_placement(iid, item.grid_x, item.grid_y, item.get_grid_width(), item.get_grid_height())
			item.grid_x = old_x
			item.grid_y = old_y
			item.position = Vector2(old_x * CELL_SIZE, old_y * CELL_SIZE)
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


func _on_item_drag_started(item: StashItem) -> void:
	dragging_item = item


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
