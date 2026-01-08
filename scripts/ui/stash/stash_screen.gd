extends Control
class_name StashScreen
## StashScreen - Main stash inventory interface
##
## Provides the full stash UI including:
## - Grid-based inventory display
## - Wallet/gold display
## - Context menu (discard, split)
## - Item tooltips
## - Navigation to traders/market

signal screen_closed
signal navigate_to_traders
signal navigate_to_market
signal navigate_to_loadout

@onready var stash_grid: StashGrid = $MarginContainer/HBoxContainer/ScrollContainer/StashGrid
@onready var scroll_container: ScrollContainer = $MarginContainer/HBoxContainer/ScrollContainer
@onready var gold_label: Label = $MarginContainer/HBoxContainer/SidePanel/WalletContainer/GoldLabel
@onready var item_tooltip: Panel = $ItemTooltip
@onready var tooltip_label: Label = $ItemTooltip/TooltipLabel
@onready var context_menu: PopupMenu = $ContextMenu

var selected_item: StashItem = null
var tooltip_timer: Timer = null


func _ready() -> void:
	# Connect to EconomyService
	EconomyService.stash_updated.connect(_on_stash_updated)
	EconomyService.gold_changed.connect(_on_gold_changed)
	EconomyService.operation_failed.connect(_on_operation_failed)

	# Setup tooltip timer
	tooltip_timer = Timer.new()
	tooltip_timer.wait_time = 0.3
	tooltip_timer.one_shot = true
	tooltip_timer.timeout.connect(_show_tooltip)
	add_child(tooltip_timer)

	# Setup context menu
	context_menu.add_item("Discard", 0)
	context_menu.add_item("Split Stack", 1)
	context_menu.id_pressed.connect(_on_context_menu_selected)

	# Hide tooltip initially
	item_tooltip.visible = false

	# Connect grid signals
	if stash_grid:
		stash_grid.item_selected.connect(_on_item_selected)
		stash_grid.item_context_menu.connect(_on_item_context_menu)
		stash_grid.operation_complete.connect(_on_operation_complete)

	# Initial refresh
	_refresh_display()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			close()
		elif event.keycode == KEY_TAB:
			# Tab cycles through stash/loadout/traders
			navigate_to_loadout.emit()


func open() -> void:
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	# Refresh stash data
	EconomyService.refresh_stash()
	_refresh_display()


func close() -> void:
	visible = false
	screen_closed.emit()


func _refresh_display() -> void:
	if not is_inside_tree():
		return

	# Update gold display
	if gold_label:
		gold_label.text = "%d" % EconomyService.get_gold()

	# Setup grid dimensions
	if stash_grid:
		stash_grid.setup(
			EconomyService.get_stash_width(),
			EconomyService.get_stash_height()
		)
		stash_grid.refresh()


func _on_stash_updated(_stash: Dictionary, _items: Array, wallet: Dictionary) -> void:
	if gold_label:
		gold_label.text = "%d" % wallet.get("gold", 0)


func _on_gold_changed(new_amount: int) -> void:
	if gold_label:
		gold_label.text = "%d" % new_amount


func _on_operation_failed(error: String) -> void:
	# Could show a toast notification here
	print("[StashScreen] Operation failed: %s" % error)


func _on_item_selected(item: StashItem) -> void:
	selected_item = item
	_update_tooltip(item)


func _on_item_context_menu(item: StashItem, pos: Vector2) -> void:
	selected_item = item
	_hide_tooltip()

	# Configure context menu based on item
	context_menu.set_item_disabled(1, item.item_data.get("stack", 1) <= 1)  # Split only for stacks

	context_menu.position = Vector2i(int(pos.x), int(pos.y))
	context_menu.popup()


func _on_context_menu_selected(id: int) -> void:
	if not selected_item:
		return

	match id:
		0:  # Discard
			_discard_item(selected_item)
		1:  # Split
			_show_split_dialog(selected_item)


func _discard_item(item: StashItem) -> void:
	if item.is_locked:
		print("[StashScreen] Cannot discard locked item")
		return

	# Confirm discard
	var confirm := ConfirmationDialog.new()
	confirm.dialog_text = "Discard %s?" % item.item_def.get("name", item.def_id)
	confirm.confirmed.connect(func():
		EconomyService.discard_item(item.iid)
	)
	add_child(confirm)
	confirm.popup_centered()


func _show_split_dialog(item: StashItem) -> void:
	var stack: int = item.item_data.get("stack", 1)
	if stack <= 1:
		return

	# Simple split dialog
	var dialog := Window.new()
	dialog.title = "Split Stack"
	dialog.size = Vector2i(300, 150)
	dialog.transient = true
	dialog.exclusive = true

	var vbox := VBoxContainer.new()
	vbox.anchors_preset = Control.PRESET_FULL_RECT
	vbox.offset_left = 10
	vbox.offset_right = -10
	vbox.offset_top = 10
	vbox.offset_bottom = -10
	dialog.add_child(vbox)

	var label := Label.new()
	label.text = "Split amount (max %d):" % (stack - 1)
	vbox.add_child(label)

	var spin := SpinBox.new()
	spin.min_value = 1
	spin.max_value = stack - 1
	spin.value = stack / 2
	vbox.add_child(spin)

	var hbox := HBoxContainer.new()
	vbox.add_child(hbox)

	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.pressed.connect(func(): dialog.queue_free())
	hbox.add_child(cancel_btn)

	var split_btn := Button.new()
	split_btn.text = "Split"
	split_btn.pressed.connect(func():
		_do_split(item, int(spin.value))
		dialog.queue_free()
	)
	hbox.add_child(split_btn)

	add_child(dialog)
	dialog.popup_centered()


func _do_split(item: StashItem, amount: int) -> void:
	# Find an empty spot for the split stack
	var empty_spot := _find_empty_spot(1, 1)  # Assuming split items are 1x1
	if empty_spot.x < 0:
		print("[StashScreen] No space for split stack")
		return

	EconomyService.split_stack(item.iid, amount, empty_spot.x, empty_spot.y)


func _find_empty_spot(w: int, h: int) -> Vector2i:
	# Naive search for empty spot
	for y in range(EconomyService.get_stash_height() - h + 1):
		for x in range(EconomyService.get_stash_width() - w + 1):
			if stash_grid and not stash_grid._check_collision(x, y, w, h):
				return Vector2i(x, y)
	return Vector2i(-1, -1)


func _update_tooltip(item: StashItem) -> void:
	if not item:
		_hide_tooltip()
		return

	tooltip_label.text = item.get_tooltip_text()
	tooltip_timer.start()


func _show_tooltip() -> void:
	if not selected_item:
		return

	item_tooltip.visible = true
	item_tooltip.position = get_global_mouse_position() + Vector2(15, 15)

	# Keep tooltip on screen
	var screen_size := get_viewport_rect().size
	if item_tooltip.position.x + item_tooltip.size.x > screen_size.x:
		item_tooltip.position.x = screen_size.x - item_tooltip.size.x - 10
	if item_tooltip.position.y + item_tooltip.size.y > screen_size.y:
		item_tooltip.position.y = screen_size.y - item_tooltip.size.y - 10


func _hide_tooltip() -> void:
	item_tooltip.visible = false
	tooltip_timer.stop()


func _on_operation_complete(_success: bool, message: String) -> void:
	print("[StashScreen] %s" % message)


# Button handlers (called from scene)
func _on_close_button_pressed() -> void:
	close()


func _on_traders_button_pressed() -> void:
	navigate_to_traders.emit()


func _on_market_button_pressed() -> void:
	navigate_to_market.emit()


func _on_loadout_button_pressed() -> void:
	navigate_to_loadout.emit()


func _on_refresh_button_pressed() -> void:
	EconomyService.refresh_stash()
