extends Control
class_name StashScreen
## StashScreen - Main stash inventory interface with Tarkov-style polish
##
## Provides the full stash UI including:
## - Grid-based inventory display
## - Wallet/gold display
## - Context menu (discard, split)
## - Polished animated tooltips
## - Navigation to traders/market

signal screen_closed
signal navigate_to_traders
signal navigate_to_market
signal navigate_to_loadout

# Rarity colors matching StashItem
const RARITY_COLORS := {
	"common": Color(0.45, 0.45, 0.45),
	"uncommon": Color(0.35, 0.55, 0.35),
	"rare": Color(0.35, 0.45, 0.7),
	"epic": Color(0.55, 0.35, 0.65),
	"legendary": Color(0.8, 0.6, 0.2),
	"quest": Color(0.9, 0.75, 0.3),
}

const RARITY_GLOW_COLORS := {
	"common": Color(0.5, 0.5, 0.5, 0.5),
	"uncommon": Color(0.3, 0.7, 0.3, 0.6),
	"rare": Color(0.3, 0.5, 0.9, 0.7),
	"epic": Color(0.7, 0.3, 0.8, 0.7),
	"legendary": Color(1.0, 0.8, 0.2, 0.8),
	"quest": Color(1.0, 0.9, 0.3, 0.8),
}

# UI Constants
const TOOLTIP_PADDING := 16
const TOOLTIP_MIN_WIDTH := 280
const TOOLTIP_MAX_WIDTH := 400
const TOOLTIP_SHOW_DELAY := 0.2
const TOOLTIP_FADE_DURATION := 0.15

@onready var stash_grid: StashGrid = $MarginContainer/HBoxContainer/ScrollContainer/StashGrid
@onready var scroll_container: ScrollContainer = $MarginContainer/HBoxContainer/ScrollContainer
@onready var gold_label: Label = $MarginContainer/HBoxContainer/SidePanel/WalletContainer/GoldLabel
@onready var context_menu: PopupMenu = $ContextMenu

var selected_item: StashItem = null
var hovered_item: StashItem = null
var tooltip_timer: Timer = null
var tooltip_tween: Tween = null

# Styled tooltip components
var tooltip_panel: Panel = null
var tooltip_container: VBoxContainer = null
var tooltip_header: HBoxContainer = null
var tooltip_name_label: Label = null
var tooltip_rarity_label: Label = null
var tooltip_separator: HSeparator = null
var tooltip_category_label: Label = null
var tooltip_description_label: RichTextLabel = null
var tooltip_stats_container: VBoxContainer = null
var tooltip_footer: HBoxContainer = null
var tooltip_value_label: Label = null
var tooltip_weight_label: Label = null


func _ready() -> void:
	# Connect to EconomyService
	EconomyService.stash_updated.connect(_on_stash_updated)
	EconomyService.gold_changed.connect(_on_gold_changed)
	EconomyService.operation_failed.connect(_on_operation_failed)

	# Create styled tooltip
	_create_styled_tooltip()

	# Setup tooltip timer
	tooltip_timer = Timer.new()
	tooltip_timer.wait_time = TOOLTIP_SHOW_DELAY
	tooltip_timer.one_shot = true
	tooltip_timer.timeout.connect(_show_tooltip)
	add_child(tooltip_timer)

	# Setup context menu
	_setup_context_menu()

	# Connect grid signals
	if stash_grid:
		stash_grid.item_selected.connect(_on_item_selected)
		stash_grid.item_context_menu.connect(_on_item_context_menu)
		stash_grid.operation_complete.connect(_on_operation_complete)
		stash_grid.item_hovered_changed.connect(_on_item_hovered)

	# Initial refresh
	_refresh_display()


func _create_styled_tooltip() -> void:
	# Main tooltip panel with dark theme
	tooltip_panel = Panel.new()
	tooltip_panel.visible = false
	tooltip_panel.z_index = 100
	tooltip_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Create stylebox for panel
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.08, 0.08, 0.1, 0.95)
	panel_style.border_color = Color(0.3, 0.3, 0.35, 0.8)
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(4)
	panel_style.shadow_color = Color(0, 0, 0, 0.5)
	panel_style.shadow_size = 8
	panel_style.shadow_offset = Vector2(2, 2)
	panel_style.set_content_margin_all(TOOLTIP_PADDING)
	tooltip_panel.add_theme_stylebox_override("panel", panel_style)

	# Main container
	tooltip_container = VBoxContainer.new()
	tooltip_container.add_theme_constant_override("separation", 8)
	tooltip_panel.add_child(tooltip_container)

	# Header row (name + rarity)
	tooltip_header = HBoxContainer.new()
	tooltip_header.add_theme_constant_override("separation", 12)
	tooltip_container.add_child(tooltip_header)

	# Item name
	tooltip_name_label = Label.new()
	tooltip_name_label.add_theme_font_size_override("font_size", 18)
	tooltip_name_label.add_theme_color_override("font_color", Color.WHITE)
	tooltip_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tooltip_header.add_child(tooltip_name_label)

	# Rarity badge
	tooltip_rarity_label = Label.new()
	tooltip_rarity_label.add_theme_font_size_override("font_size", 12)
	tooltip_rarity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tooltip_header.add_child(tooltip_rarity_label)

	# Category label
	tooltip_category_label = Label.new()
	tooltip_category_label.add_theme_font_size_override("font_size", 12)
	tooltip_category_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
	tooltip_container.add_child(tooltip_category_label)

	# Separator
	tooltip_separator = HSeparator.new()
	var sep_style := StyleBoxLine.new()
	sep_style.color = Color(0.3, 0.3, 0.35, 0.5)
	sep_style.thickness = 1
	tooltip_separator.add_theme_stylebox_override("separator", sep_style)
	tooltip_container.add_child(tooltip_separator)

	# Description
	tooltip_description_label = RichTextLabel.new()
	tooltip_description_label.bbcode_enabled = true
	tooltip_description_label.fit_content = true
	tooltip_description_label.scroll_active = false
	tooltip_description_label.custom_minimum_size.x = TOOLTIP_MIN_WIDTH - (TOOLTIP_PADDING * 2)
	tooltip_description_label.add_theme_font_size_override("normal_font_size", 13)
	tooltip_description_label.add_theme_color_override("default_color", Color(0.75, 0.75, 0.78))
	tooltip_container.add_child(tooltip_description_label)

	# Stats container
	tooltip_stats_container = VBoxContainer.new()
	tooltip_stats_container.add_theme_constant_override("separation", 4)
	tooltip_container.add_child(tooltip_stats_container)

	# Footer (value + weight)
	tooltip_footer = HBoxContainer.new()
	tooltip_footer.add_theme_constant_override("separation", 20)
	tooltip_container.add_child(tooltip_footer)

	# Value label
	tooltip_value_label = Label.new()
	tooltip_value_label.add_theme_font_size_override("font_size", 13)
	tooltip_value_label.add_theme_color_override("font_color", Color(0.9, 0.8, 0.3))
	tooltip_footer.add_child(tooltip_value_label)

	# Weight label
	tooltip_weight_label = Label.new()
	tooltip_weight_label.add_theme_font_size_override("font_size", 13)
	tooltip_weight_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
	tooltip_footer.add_child(tooltip_weight_label)

	add_child(tooltip_panel)


func _setup_context_menu() -> void:
	if not context_menu:
		context_menu = PopupMenu.new()
		add_child(context_menu)

	context_menu.clear()
	context_menu.add_icon_item(null, "Examine", 0)
	context_menu.add_separator()
	context_menu.add_icon_item(null, "Discard", 1)
	context_menu.add_icon_item(null, "Split Stack", 2)
	context_menu.add_separator()
	context_menu.add_icon_item(null, "Sell to Trader", 3)
	context_menu.add_icon_item(null, "List on Market", 4)

	if not context_menu.id_pressed.is_connected(_on_context_menu_selected):
		context_menu.id_pressed.connect(_on_context_menu_selected)


func _process(_delta: float) -> void:
	# Update tooltip position to follow mouse
	if tooltip_panel and tooltip_panel.visible and hovered_item:
		_position_tooltip()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			close()
		elif event.keycode == KEY_TAB:
			navigate_to_loadout.emit()


func open() -> void:
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	# Refresh stash data
	EconomyService.refresh_stash()
	_refresh_display()


func close() -> void:
	_hide_tooltip()
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
	_show_notification(error, Color(0.9, 0.3, 0.3))


func _on_item_selected(item: StashItem) -> void:
	selected_item = item


func _on_item_hovered(item: StashItem) -> void:
	if item == hovered_item:
		return

	hovered_item = item

	if item:
		_update_tooltip_content(item)
		tooltip_timer.start()
	else:
		_hide_tooltip()


func _update_tooltip_content(item: StashItem) -> void:
	if not item:
		return

	var item_def := item.item_def
	var item_data := item.item_data
	var rarity: String = item_def.get("rarity", "common")
	var rarity_color: Color = RARITY_COLORS.get(rarity, RARITY_COLORS.common)

	# Update name with rarity color
	tooltip_name_label.text = item_def.get("name", item.def_id)
	tooltip_name_label.add_theme_color_override("font_color", rarity_color)

	# Update rarity badge
	tooltip_rarity_label.text = rarity.to_upper()
	tooltip_rarity_label.add_theme_color_override("font_color", rarity_color)

	# Update category
	var category: String = item_def.get("category", "misc")
	var item_type: String = item_def.get("type", "")
	if item_type:
		tooltip_category_label.text = "%s • %s" % [category.capitalize(), item_type.capitalize()]
	else:
		tooltip_category_label.text = category.capitalize()

	# Update description
	var desc: String = item_def.get("description", "No description available.")
	tooltip_description_label.text = desc

	# Update stats
	_update_tooltip_stats(item, item_def, item_data)

	# Update footer
	var value: int = item_def.get("value", 0)
	var stack: int = item_data.get("stack", 1)
	if stack > 1:
		tooltip_value_label.text = "₽ %d (×%d = %d)" % [value, stack, value * stack]
	else:
		tooltip_value_label.text = "₽ %d" % value

	var weight: float = item_def.get("weight", 0.0)
	if weight > 0:
		tooltip_weight_label.text = "%.2f kg" % (weight * stack)
		tooltip_weight_label.visible = true
	else:
		tooltip_weight_label.visible = false

	# Size the tooltip
	tooltip_panel.reset_size()


func _update_tooltip_stats(item: StashItem, item_def: Dictionary, item_data: Dictionary) -> void:
	# Clear existing stats
	for child in tooltip_stats_container.get_children():
		child.queue_free()

	var stats_to_show: Array[Dictionary] = []

	# Durability
	var durability := item_data.get("durability", -1.0)
	var max_durability := item_def.get("max_durability", -1.0)
	if durability >= 0 and max_durability > 0:
		var percent := (durability / max_durability) * 100.0
		var dur_color := Color.GREEN
		if percent < 25:
			dur_color = Color.RED
		elif percent < 50:
			dur_color = Color.ORANGE
		elif percent < 75:
			dur_color = Color.YELLOW
		stats_to_show.append({
			"label": "Durability",
			"value": "%.0f / %.0f (%.0f%%)" % [durability, max_durability, percent],
			"color": dur_color,
			"show_bar": true,
			"percent": percent
		})

	# Weapon stats
	if item_def.has("damage"):
		stats_to_show.append({
			"label": "Damage",
			"value": str(item_def.damage),
			"color": Color(0.9, 0.4, 0.3)
		})

	if item_def.has("fire_rate"):
		stats_to_show.append({
			"label": "Fire Rate",
			"value": "%d RPM" % item_def.fire_rate,
			"color": Color(0.7, 0.7, 0.75)
		})

	if item_def.has("accuracy"):
		stats_to_show.append({
			"label": "Accuracy",
			"value": "%.0f%%" % (item_def.accuracy * 100),
			"color": Color(0.4, 0.7, 0.9)
		})

	if item_def.has("recoil"):
		stats_to_show.append({
			"label": "Recoil",
			"value": str(item_def.recoil),
			"color": Color(0.9, 0.6, 0.3)
		})

	# Armor stats
	if item_def.has("armor_class"):
		stats_to_show.append({
			"label": "Armor Class",
			"value": str(item_def.armor_class),
			"color": Color(0.3, 0.6, 0.9)
		})

	if item_def.has("protection"):
		stats_to_show.append({
			"label": "Protection",
			"value": "%.0f%%" % (item_def.protection * 100),
			"color": Color(0.3, 0.7, 0.5)
		})

	# Container stats
	if item_def.has("capacity"):
		stats_to_show.append({
			"label": "Capacity",
			"value": "%d slots" % item_def.capacity,
			"color": Color(0.6, 0.6, 0.65)
		})

	# Consumable stats
	if item_def.has("heal_amount"):
		stats_to_show.append({
			"label": "Heals",
			"value": "+%d HP" % item_def.heal_amount,
			"color": Color(0.3, 0.9, 0.4)
		})

	if item_def.has("uses"):
		var uses_left := item_data.get("uses_remaining", item_def.uses)
		stats_to_show.append({
			"label": "Uses",
			"value": "%d / %d" % [uses_left, item_def.uses],
			"color": Color(0.7, 0.7, 0.75)
		})

	# Locked status
	if item.is_locked:
		stats_to_show.append({
			"label": "Status",
			"value": "LOCKED FOR RAID",
			"color": Color(0.9, 0.3, 0.3)
		})

	# Create stat rows
	for stat in stats_to_show:
		var row := _create_stat_row(stat)
		tooltip_stats_container.add_child(row)


func _create_stat_row(stat: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	# Label
	var label := Label.new()
	label.text = stat.label + ":"
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55))
	label.custom_minimum_size.x = 80
	row.add_child(label)

	# Value with optional bar
	if stat.get("show_bar", false):
		var bar_container := HBoxContainer.new()
		bar_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar_container.add_theme_constant_override("separation", 8)

		# Progress bar
		var bar := ProgressBar.new()
		bar.value = stat.percent
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(80, 12)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER

		var bar_bg := StyleBoxFlat.new()
		bar_bg.bg_color = Color(0.15, 0.15, 0.18)
		bar_bg.set_corner_radius_all(2)
		bar.add_theme_stylebox_override("background", bar_bg)

		var bar_fill := StyleBoxFlat.new()
		bar_fill.bg_color = stat.color
		bar_fill.set_corner_radius_all(2)
		bar.add_theme_stylebox_override("fill", bar_fill)

		bar_container.add_child(bar)

		# Value text
		var value_label := Label.new()
		value_label.text = stat.value
		value_label.add_theme_font_size_override("font_size", 12)
		value_label.add_theme_color_override("font_color", stat.color)
		bar_container.add_child(value_label)

		row.add_child(bar_container)
	else:
		var value_label := Label.new()
		value_label.text = stat.value
		value_label.add_theme_font_size_override("font_size", 12)
		value_label.add_theme_color_override("font_color", stat.color)
		value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(value_label)

	return row


func _show_tooltip() -> void:
	if not hovered_item or not tooltip_panel:
		return

	# Kill any existing tween
	if tooltip_tween:
		tooltip_tween.kill()

	# Fade in animation
	tooltip_panel.modulate.a = 0.0
	tooltip_panel.visible = true

	tooltip_tween = create_tween()
	tooltip_tween.tween_property(tooltip_panel, "modulate:a", 1.0, TOOLTIP_FADE_DURATION)

	_position_tooltip()


func _position_tooltip() -> void:
	if not tooltip_panel:
		return

	var mouse_pos := get_global_mouse_position()
	var screen_size := get_viewport_rect().size
	var tooltip_size := tooltip_panel.size

	# Default position: below and to the right of cursor
	var pos := mouse_pos + Vector2(20, 20)

	# Adjust if would go off right edge
	if pos.x + tooltip_size.x > screen_size.x - 10:
		pos.x = mouse_pos.x - tooltip_size.x - 10

	# Adjust if would go off bottom edge
	if pos.y + tooltip_size.y > screen_size.y - 10:
		pos.y = mouse_pos.y - tooltip_size.y - 10

	# Ensure not off left or top
	pos.x = max(10, pos.x)
	pos.y = max(10, pos.y)

	tooltip_panel.position = pos


func _hide_tooltip() -> void:
	if not tooltip_panel:
		return

	tooltip_timer.stop()

	if tooltip_tween:
		tooltip_tween.kill()

	# Quick fade out
	tooltip_tween = create_tween()
	tooltip_tween.tween_property(tooltip_panel, "modulate:a", 0.0, TOOLTIP_FADE_DURATION * 0.5)
	tooltip_tween.tween_callback(func(): tooltip_panel.visible = false)


func _on_item_context_menu(item: StashItem, pos: Vector2) -> void:
	selected_item = item
	_hide_tooltip()

	if not context_menu:
		return

	# Configure menu based on item
	var stack := item.item_data.get("stack", 1)
	context_menu.set_item_disabled(2, stack <= 1)  # Split only for stacks > 1
	context_menu.set_item_disabled(3, item.is_locked)  # Can't sell locked
	context_menu.set_item_disabled(4, item.is_locked)  # Can't list locked

	context_menu.position = Vector2i(int(pos.x), int(pos.y))
	context_menu.popup()


func _on_context_menu_selected(id: int) -> void:
	if not selected_item:
		return

	match id:
		0:  # Examine
			_examine_item(selected_item)
		1:  # Discard
			_discard_item(selected_item)
		2:  # Split
			_show_split_dialog(selected_item)
		3:  # Sell to Trader
			_quick_sell_item(selected_item)
		4:  # List on Market
			navigate_to_market.emit()


func _examine_item(item: StashItem) -> void:
	# Force show tooltip
	hovered_item = item
	_update_tooltip_content(item)
	_show_tooltip()


func _discard_item(item: StashItem) -> void:
	if item.is_locked:
		_show_notification("Cannot discard locked items", Color(0.9, 0.3, 0.3))
		return

	var confirm := ConfirmationDialog.new()
	confirm.dialog_text = "Discard %s?" % item.item_def.get("name", item.def_id)
	confirm.confirmed.connect(func():
		EconomyService.discard_item(item.iid)
		_show_notification("Item discarded", Color(0.6, 0.6, 0.65))
	)
	confirm.canceled.connect(func(): confirm.queue_free())
	add_child(confirm)
	confirm.popup_centered()


func _quick_sell_item(item: StashItem) -> void:
	if item.is_locked:
		_show_notification("Cannot sell locked items", Color(0.9, 0.3, 0.3))
		return

	var value: int = item.item_def.get("value", item.item_def.get("base_value", 0))
	var stack: int = item.item_data.get("stack", 1)
	# Quick sell is at 50% value (same as trader rate)
	var sell_value := int(value * 0.5 * stack)

	var confirm := ConfirmationDialog.new()
	confirm.dialog_text = "Quick sell %s for ₽%d?" % [item.item_def.get("name", item.def_id), sell_value]
	confirm.confirmed.connect(func():
		# Use general merchant for quick sell
		_execute_quick_sell(item.iid, sell_value)
	)
	confirm.canceled.connect(func(): confirm.queue_free())
	add_child(confirm)
	confirm.popup_centered()


func _execute_quick_sell(iid: String, expected_value: int) -> void:
	_show_notification("Selling...", Color(0.7, 0.7, 0.7))

	# Use trader sell mechanism with generic merchant
	var success := await EconomyService.sell_to_trader("merchant_general", iid)

	if success:
		_show_notification("Sold for ~₽%d" % expected_value, Color(0.9, 0.8, 0.3))
	else:
		_show_notification("Sale failed", Color(0.9, 0.3, 0.3))


func _show_split_dialog(item: StashItem) -> void:
	var stack: int = item.item_data.get("stack", 1)
	if stack <= 1:
		return

	var dialog := Window.new()
	dialog.title = "Split Stack"
	dialog.size = Vector2i(320, 180)
	dialog.transient = true
	dialog.exclusive = true

	# Style the window
	var panel := Panel.new()
	panel.anchors_preset = Control.PRESET_FULL_RECT
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.1, 0.1, 0.12)
	panel.add_theme_stylebox_override("panel", panel_style)
	dialog.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.anchors_preset = Control.PRESET_FULL_RECT
	vbox.offset_left = 16
	vbox.offset_right = -16
	vbox.offset_top = 16
	vbox.offset_bottom = -16
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)

	var label := Label.new()
	label.text = "Split amount (max %d):" % (stack - 1)
	label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.85))
	vbox.add_child(label)

	var slider_row := HBoxContainer.new()
	slider_row.add_theme_constant_override("separation", 12)
	vbox.add_child(slider_row)

	var slider := HSlider.new()
	slider.min_value = 1
	slider.max_value = stack - 1
	slider.value = stack / 2
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider_row.add_child(slider)

	var spin := SpinBox.new()
	spin.min_value = 1
	spin.max_value = stack - 1
	spin.value = stack / 2
	spin.custom_minimum_size.x = 80
	slider_row.add_child(spin)

	# Sync slider and spinbox
	slider.value_changed.connect(func(v): spin.value = v)
	spin.value_changed.connect(func(v): slider.value = v)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer)

	var button_row := HBoxContainer.new()
	button_row.add_theme_constant_override("separation", 12)
	button_row.alignment = BoxContainer.ALIGNMENT_END
	vbox.add_child(button_row)

	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.custom_minimum_size.x = 80
	cancel_btn.pressed.connect(func(): dialog.queue_free())
	button_row.add_child(cancel_btn)

	var split_btn := Button.new()
	split_btn.text = "Split"
	split_btn.custom_minimum_size.x = 80
	split_btn.pressed.connect(func():
		_do_split(item, int(spin.value))
		dialog.queue_free()
	)
	button_row.add_child(split_btn)

	add_child(dialog)
	dialog.popup_centered()


func _do_split(item: StashItem, amount: int) -> void:
	var empty_spot := _find_empty_spot(1, 1)
	if empty_spot.x < 0:
		_show_notification("No space for split stack", Color(0.9, 0.3, 0.3))
		return

	EconomyService.split_stack(item.iid, amount, empty_spot.x, empty_spot.y)
	_show_notification("Stack split", Color(0.5, 0.8, 0.5))


func _find_empty_spot(w: int, h: int) -> Vector2i:
	for y in range(EconomyService.get_stash_height() - h + 1):
		for x in range(EconomyService.get_stash_width() - w + 1):
			if stash_grid and not stash_grid._check_collision(x, y, w, h):
				return Vector2i(x, y)
	return Vector2i(-1, -1)


func _show_notification(message: String, color: Color) -> void:
	# Create floating notification
	var notif := Label.new()
	notif.text = message
	notif.add_theme_font_size_override("font_size", 14)
	notif.add_theme_color_override("font_color", color)
	notif.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notif.anchors_preset = Control.PRESET_CENTER_TOP
	notif.position.y = 60
	notif.modulate.a = 0.0
	notif.z_index = 100
	add_child(notif)

	# Animate
	var tween := create_tween()
	tween.tween_property(notif, "modulate:a", 1.0, 0.2)
	tween.tween_interval(1.5)
	tween.tween_property(notif, "modulate:a", 0.0, 0.3)
	tween.tween_property(notif, "position:y", 40.0, 0.3).set_trans(Tween.TRANS_QUAD)
	tween.tween_callback(func(): notif.queue_free())


func _on_operation_complete(_success: bool, message: String) -> void:
	if _success:
		_show_notification(message, Color(0.5, 0.8, 0.5))
	else:
		_show_notification(message, Color(0.9, 0.3, 0.3))


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
	_show_notification("Refreshing stash...", Color(0.6, 0.6, 0.65))
