extends Control
class_name LoadoutScreen
## LoadoutScreen - Equip items for raid
##
## Players drag items from stash to loadout slots before entering a raid.
## Slots: primary weapon, secondary, melee, armor, rig, backpack

signal screen_closed
signal navigate_to_stash
signal raid_ready(loadout: Dictionary)

const CELL_SIZE := 64

# Loadout slots
@onready var primary_slot: Panel = $MarginContainer/HBoxContainer/LoadoutPanel/SlotsContainer/WeaponSlots/PrimarySlot
@onready var secondary_slot: Panel = $MarginContainer/HBoxContainer/LoadoutPanel/SlotsContainer/WeaponSlots/SecondarySlot
@onready var melee_slot: Panel = $MarginContainer/HBoxContainer/LoadoutPanel/SlotsContainer/WeaponSlots/MeleeSlot
@onready var armor_slot: Panel = $MarginContainer/HBoxContainer/LoadoutPanel/SlotsContainer/GearSlots/ArmorSlot
@onready var rig_slot: Panel = $MarginContainer/HBoxContainer/LoadoutPanel/SlotsContainer/GearSlots/RigSlot
@onready var backpack_slot: Panel = $MarginContainer/HBoxContainer/LoadoutPanel/SlotsContainer/GearSlots/BackpackSlot

@onready var ready_button: Button = $MarginContainer/HBoxContainer/LoadoutPanel/ReadyButton
@onready var status_label: Label = $MarginContainer/HBoxContainer/LoadoutPanel/StatusLabel

# Stash grid (mini view for equipping)
@onready var stash_scroll: ScrollContainer = $MarginContainer/HBoxContainer/StashPanel/ScrollContainer
@onready var stash_grid: StashGrid = $MarginContainer/HBoxContainer/StashPanel/ScrollContainer/StashGrid

# Current loadout
var loadout := {
	"primary": "",
	"secondary": "",
	"melee": "",
	"armor": "",
	"rig": "",
	"backpack": ""
}

# Slot configurations (category restrictions)
var slot_configs := {
	"primary": { "categories": ["weapon"], "size": Vector2i(4, 2) },
	"secondary": { "categories": ["weapon"], "size": Vector2i(2, 1) },
	"melee": { "categories": ["tool", "melee"], "size": Vector2i(1, 2) },
	"armor": { "categories": ["armor"], "size": Vector2i(2, 2) },
	"rig": { "categories": ["rig", "container"], "size": Vector2i(2, 2) },
	"backpack": { "categories": ["container", "backpack"], "size": Vector2i(2, 3) }
}

var slot_panels: Dictionary = {}
var dragging_from_slot: String = ""


func _ready() -> void:
	# Map slots
	slot_panels = {
		"primary": primary_slot,
		"secondary": secondary_slot,
		"melee": melee_slot,
		"armor": armor_slot,
		"rig": rig_slot,
		"backpack": backpack_slot
	}

	# Setup slot visuals and interactions
	for slot_name in slot_panels:
		var panel: Panel = slot_panels[slot_name]
		if panel:
			_setup_slot(slot_name, panel)

	# Connect stash grid
	if stash_grid:
		stash_grid.item_selected.connect(_on_stash_item_selected)

	# Connect EconomyService
	EconomyService.stash_updated.connect(_on_stash_updated)
	EconomyService.raid_prepared.connect(_on_raid_prepared)
	EconomyService.operation_failed.connect(_on_operation_failed)

	_refresh_display()


func _setup_slot(slot_name: String, panel: Panel) -> void:
	var config: Dictionary = slot_configs.get(slot_name, {})
	var slot_size: Vector2i = config.get("size", Vector2i(1, 1))

	panel.custom_minimum_size = Vector2(slot_size.x * CELL_SIZE, slot_size.y * CELL_SIZE)

	# Add label
	var label := Label.new()
	label.text = slot_name.capitalize()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	label.anchors_preset = Control.PRESET_FULL_RECT
	label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	panel.add_child(label)

	# Make droppable
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.gui_input.connect(func(event): _on_slot_input(slot_name, event))


func open() -> void:
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh_display()


func close() -> void:
	visible = false
	screen_closed.emit()


func _refresh_display() -> void:
	if not is_inside_tree():
		return

	# Setup stash grid
	if stash_grid:
		stash_grid.setup(
			EconomyService.get_stash_width(),
			EconomyService.get_stash_height()
		)
		stash_grid.refresh()

	# Update slot displays
	for slot_name in slot_panels:
		_update_slot_display(slot_name)

	_update_ready_button()


func _update_slot_display(slot_name: String) -> void:
	var panel: Panel = slot_panels.get(slot_name)
	if not panel:
		return

	var iid: String = loadout.get(slot_name, "")

	# Clear existing item display (except label)
	for child in panel.get_children():
		if child is Label:
			child.visible = iid == ""
		elif child.name == "ItemDisplay":
			child.queue_free()

	if iid == "":
		return

	# Get item data
	var item_data: Dictionary = EconomyService.get_item(iid)
	if item_data.is_empty():
		loadout[slot_name] = ""
		return

	var def_id: String = item_data.get("def_id", item_data.get("defId", ""))
	var item_def: Dictionary = EconomyService.get_item_def(def_id)

	# Create item display
	var item_display := ColorRect.new()
	item_display.name = "ItemDisplay"
	item_display.anchors_preset = Control.PRESET_FULL_RECT
	item_display.offset_left = 4
	item_display.offset_top = 4
	item_display.offset_right = -4
	item_display.offset_bottom = -4
	item_display.color = Color(0.2, 0.3, 0.2, 0.9)
	panel.add_child(item_display)

	var item_label := Label.new()
	item_label.text = item_def.get("name", def_id)
	item_label.anchors_preset = Control.PRESET_CENTER
	item_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	item_display.add_child(item_label)


func _update_ready_button() -> void:
	# Check if minimum loadout requirements met
	var has_weapon := loadout.primary != "" or loadout.secondary != "" or loadout.melee != ""
	ready_button.disabled = not has_weapon

	if has_weapon:
		status_label.text = "Ready to raid!"
		status_label.add_theme_color_override("font_color", Color.GREEN)
	else:
		status_label.text = "Equip at least one weapon"
		status_label.add_theme_color_override("font_color", Color.YELLOW)


func _on_slot_input(slot_name: String, event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			# Could start drag from slot
			if loadout.get(slot_name, "") != "":
				dragging_from_slot = slot_name

		elif event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			dragging_from_slot = ""

		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			# Right-click to unequip
			_unequip_slot(slot_name)


func _on_stash_item_selected(item: StashItem) -> void:
	if item.is_locked:
		status_label.text = "Item is locked"
		return

	# Try to auto-equip to appropriate slot
	var item_def: Dictionary = item.item_def
	var category: String = item_def.get("category", "misc")

	for slot_name in slot_configs:
		var config: Dictionary = slot_configs[slot_name]
		var allowed_categories: Array = config.get("categories", [])

		if category in allowed_categories and loadout.get(slot_name, "") == "":
			_equip_to_slot(slot_name, item.iid)
			return

	# If no empty slot found, try to replace first matching slot
	for slot_name in slot_configs:
		var config: Dictionary = slot_configs[slot_name]
		var allowed_categories: Array = config.get("categories", [])

		if category in allowed_categories:
			_equip_to_slot(slot_name, item.iid)
			return

	status_label.text = "No slot available for this item"


func _equip_to_slot(slot_name: String, iid: String) -> void:
	# Unequip current item if any
	var current_iid: String = loadout.get(slot_name, "")
	if current_iid != "":
		# Current item stays in stash, just remove from loadout
		pass

	loadout[slot_name] = iid
	_update_slot_display(slot_name)
	_update_ready_button()

	var item_data: Dictionary = EconomyService.get_item(iid)
	var def_id: String = item_data.get("def_id", item_data.get("defId", ""))
	var item_def: Dictionary = EconomyService.get_item_def(def_id)
	status_label.text = "Equipped: %s" % item_def.get("name", def_id)


func _unequip_slot(slot_name: String) -> void:
	var iid: String = loadout.get(slot_name, "")
	if iid == "":
		return

	loadout[slot_name] = ""
	_update_slot_display(slot_name)
	_update_ready_button()

	status_label.text = "Unequipped from %s" % slot_name


func _get_loadout_dict() -> Dictionary:
	# Build loadout for API
	var result := {}
	for slot_name in loadout:
		if loadout[slot_name] != "":
			result[slot_name] = loadout[slot_name]
	return result


func _on_stash_updated(_stash: Dictionary, _items: Array, _wallet: Dictionary) -> void:
	# Validate loadout (remove items that no longer exist)
	for slot_name in loadout:
		var iid: String = loadout[slot_name]
		if iid != "" and EconomyService.get_item(iid).is_empty():
			loadout[slot_name] = ""

	_refresh_display()


func _on_raid_prepared(raid_id: String, locked_iids: Array) -> void:
	status_label.text = "Raid prepared! ID: %s" % raid_id.substr(0, 8)
	status_label.add_theme_color_override("font_color", Color.GREEN)

	# Emit signal with loadout
	raid_ready.emit(_get_loadout_dict())


func _on_operation_failed(error: String) -> void:
	status_label.text = "Error: %s" % error
	status_label.add_theme_color_override("font_color", Color.RED)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			close()
		elif event.keycode == KEY_TAB:
			navigate_to_stash.emit()


# Button handlers
func _on_ready_button_pressed() -> void:
	var loadout_dict := _get_loadout_dict()
	if loadout_dict.is_empty():
		status_label.text = "Equip at least one item"
		return

	status_label.text = "Preparing raid..."

	# Get current lobby ID (if in lobby)
	var lobby_id: String = LobbySystem.current_lobby_id if LobbySystem.current_lobby_id else "solo_" + str(randi())

	EconomyService.prepare_raid(lobby_id, loadout_dict)


func _on_stash_button_pressed() -> void:
	navigate_to_stash.emit()


func _on_close_button_pressed() -> void:
	close()


func _on_clear_button_pressed() -> void:
	for slot_name in loadout:
		loadout[slot_name] = ""
	_refresh_display()
	status_label.text = "Loadout cleared"
