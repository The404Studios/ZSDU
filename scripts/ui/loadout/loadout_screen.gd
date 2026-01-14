extends Control
class_name LoadoutScreen
## LoadoutScreen - Pre-raid equipment selection
##
## Allows players to select their loadout before entering a raid.
## Equipment slots: Primary, Secondary, Helmet, Vest, Rig, Backpack
## Items dragged from stash into slots are locked when ready.

signal screen_closed
signal navigate_to_stash
signal ready_for_raid(loadout: Dictionary)

# Equipment slots
enum EquipmentSlot {
	PRIMARY,      # Primary weapon
	SECONDARY,    # Secondary weapon / sidearm
	HELMET,       # Head protection
	VEST,         # Body armor
	RIG,          # Tactical rig
	BACKPACK,     # Storage
	MELEE,        # Melee weapon (hammer always available)
}

const SLOT_NAMES := {
	EquipmentSlot.PRIMARY: "Primary Weapon",
	EquipmentSlot.SECONDARY: "Secondary",
	EquipmentSlot.HELMET: "Helmet",
	EquipmentSlot.VEST: "Body Armor",
	EquipmentSlot.RIG: "Tactical Rig",
	EquipmentSlot.BACKPACK: "Backpack",
	EquipmentSlot.MELEE: "Melee",
}

const SLOT_CATEGORIES := {
	EquipmentSlot.PRIMARY: ["weapon", "rifle", "shotgun", "smg"],
	EquipmentSlot.SECONDARY: ["weapon", "pistol", "sidearm"],
	EquipmentSlot.HELMET: ["helmet", "headwear"],
	EquipmentSlot.VEST: ["armor", "vest"],
	EquipmentSlot.RIG: ["rig", "tactical_rig"],
	EquipmentSlot.BACKPACK: ["backpack", "bag"],
	EquipmentSlot.MELEE: ["melee"],
}

# Current loadout
var loadout: Dictionary = {}  # EquipmentSlot -> iid
var slot_controls: Dictionary = {}  # EquipmentSlot -> LoadoutSlot

# Stash reference for item selection
var stash_items_panel: Control = null
var selected_slot: int = -1

# UI References
var ready_button: Button = null
var status_label: Label = null
var gold_label: Label = null


func _ready() -> void:
	_create_ui()

	# Connect signals
	EconomyService.stash_updated.connect(_on_stash_updated)
	EconomyService.raid_prepared.connect(_on_raid_prepared)
	EconomyService.operation_failed.connect(_on_operation_failed)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			close()
		elif event.keycode == KEY_TAB:
			navigate_to_stash.emit()


func open() -> void:
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh_stash_items()
	_update_gold_display()


func close() -> void:
	visible = false
	screen_closed.emit()


func _create_ui() -> void:
	# Background
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.08, 0.12, 0.98)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Main container
	var main_container := MarginContainer.new()
	main_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	main_container.add_theme_constant_override("margin_left", 30)
	main_container.add_theme_constant_override("margin_top", 30)
	main_container.add_theme_constant_override("margin_right", 30)
	main_container.add_theme_constant_override("margin_bottom", 30)
	add_child(main_container)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 30)
	main_container.add_child(hbox)

	# Left panel - Equipment slots
	var left_panel := _create_equipment_panel()
	left_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_panel.size_flags_stretch_ratio = 0.4
	hbox.add_child(left_panel)

	# Right panel - Stash items
	var right_panel := _create_stash_panel()
	right_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_panel.size_flags_stretch_ratio = 0.6
	hbox.add_child(right_panel)


func _create_equipment_panel() -> Control:
	var panel := PanelContainer.new()

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	# Title
	var title := Label.new()
	title.text = "LOADOUT"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	vbox.add_child(title)

	# Gold display
	var gold_hbox := HBoxContainer.new()
	gold_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(gold_hbox)

	var gold_icon := Label.new()
	gold_icon.text = "Gold: "
	gold_hbox.add_child(gold_icon)

	gold_label = Label.new()
	gold_label.text = "0"
	gold_label.add_theme_color_override("font_color", Color.GOLD)
	gold_hbox.add_child(gold_label)

	var sep := HSeparator.new()
	vbox.add_child(sep)

	# Character preview placeholder
	var preview := ColorRect.new()
	preview.color = Color(0.15, 0.15, 0.15)
	preview.custom_minimum_size = Vector2(200, 300)
	preview.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(preview)

	var preview_label := Label.new()
	preview_label.text = "Character Preview"
	preview_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	preview_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	preview_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	preview.add_child(preview_label)

	# Equipment slots grid
	var slots_label := Label.new()
	slots_label.text = "Equipment Slots"
	slots_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(slots_label)

	var slots_grid := GridContainer.new()
	slots_grid.columns = 2
	slots_grid.add_theme_constant_override("h_separation", 10)
	slots_grid.add_theme_constant_override("v_separation", 10)
	vbox.add_child(slots_grid)

	# Create slots
	for slot in [EquipmentSlot.PRIMARY, EquipmentSlot.SECONDARY, EquipmentSlot.HELMET,
				 EquipmentSlot.VEST, EquipmentSlot.RIG, EquipmentSlot.BACKPACK]:
		var slot_control := _create_slot_button(slot)
		slots_grid.add_child(slot_control)
		slot_controls[slot] = slot_control

	# Spacer
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer)

	# Status
	status_label = Label.new()
	status_label.text = "Select items from your stash"
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	vbox.add_child(status_label)

	# Buttons
	var button_hbox := HBoxContainer.new()
	button_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	button_hbox.add_theme_constant_override("separation", 20)
	vbox.add_child(button_hbox)

	var back_btn := Button.new()
	back_btn.text = "Back to Stash"
	back_btn.custom_minimum_size = Vector2(120, 40)
	back_btn.pressed.connect(func(): navigate_to_stash.emit())
	button_hbox.add_child(back_btn)

	ready_button = Button.new()
	ready_button.text = "READY"
	ready_button.custom_minimum_size = Vector2(150, 50)
	ready_button.pressed.connect(_on_ready_pressed)
	button_hbox.add_child(ready_button)

	return panel


func _create_slot_button(slot: int) -> Control:
	var container := VBoxContainer.new()
	container.custom_minimum_size = Vector2(140, 90)

	var label := Label.new()
	label.text = SLOT_NAMES.get(slot, "Unknown")
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 12)
	container.add_child(label)

	var slot_btn := Button.new()
	slot_btn.custom_minimum_size = Vector2(140, 60)
	slot_btn.text = "[Empty]"
	slot_btn.set_meta("slot", slot)
	slot_btn.pressed.connect(func(): _on_slot_clicked(slot))
	container.add_child(slot_btn)

	# Store reference to button in container metadata
	container.set_meta("button", slot_btn)

	return container


func _create_stash_panel() -> Control:
	var panel := PanelContainer.new()

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	# Title
	var title := Label.new()
	title.text = "STASH ITEMS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	vbox.add_child(title)

	# Filter info
	var filter_label := Label.new()
	filter_label.text = "Click a slot to filter compatible items"
	filter_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	filter_label.add_theme_font_size_override("font_size", 12)
	filter_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	vbox.add_child(filter_label)

	var sep := HSeparator.new()
	vbox.add_child(sep)

	# Scrollable item list
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	stash_items_panel = VBoxContainer.new()
	stash_items_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(stash_items_panel)

	return panel


func _refresh_stash_items() -> void:
	if not stash_items_panel:
		return

	# Clear existing
	for child in stash_items_panel.get_children():
		child.queue_free()

	# Get items from stash
	var items: Array = EconomyService.get_all_items()

	# Filter by selected slot if any
	var filter_categories: Array = []
	if selected_slot >= 0:
		filter_categories = SLOT_CATEGORIES.get(selected_slot, [])

	for item in items:
		var iid: String = item.get("iid", "")
		var def_id: String = item.get("def_id", item.get("defId", ""))
		var item_def: Dictionary = EconomyService.get_item_def(def_id)

		# Skip locked items
		if EconomyService.is_item_locked(iid):
			continue

		# Skip items already in loadout
		if iid in loadout.values():
			continue

		# Filter by category if slot is selected
		if not filter_categories.is_empty():
			var item_category: String = item_def.get("category", "misc").to_lower()
			var matches := false
			for cat in filter_categories:
				if item_category.contains(cat) or cat.contains(item_category):
					matches = true
					break
			if not matches:
				continue

		# Create item button
		var item_btn := _create_item_button(iid, item, item_def)
		stash_items_panel.add_child(item_btn)

	# Show "no items" message if empty
	if stash_items_panel.get_child_count() == 0:
		var empty_label := Label.new()
		empty_label.text = "No compatible items found"
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		stash_items_panel.add_child(empty_label)


func _create_item_button(iid: String, item_data: Dictionary, item_def: Dictionary) -> Control:
	var hbox := HBoxContainer.new()
	hbox.custom_minimum_size = Vector2(0, 50)
	hbox.add_theme_constant_override("separation", 10)

	# Item icon placeholder
	var icon := ColorRect.new()
	icon.custom_minimum_size = Vector2(50, 50)
	icon.color = _get_rarity_color(item_def.get("rarity", "common"))
	hbox.add_child(icon)

	# Item info
	var info_vbox := VBoxContainer.new()
	info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(info_vbox)

	var name_label := Label.new()
	name_label.text = item_def.get("name", iid)
	name_label.add_theme_font_size_override("font_size", 14)
	info_vbox.add_child(name_label)

	var details := Label.new()
	var category: String = item_def.get("category", "misc")
	var stack: int = item_data.get("stack", 1)
	details.text = "%s%s" % [category.capitalize(), " x%d" % stack if stack > 1 else ""]
	details.add_theme_font_size_override("font_size", 11)
	details.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	info_vbox.add_child(details)

	# Equip button
	var equip_btn := Button.new()
	equip_btn.text = "Equip"
	equip_btn.custom_minimum_size = Vector2(70, 40)
	equip_btn.pressed.connect(func(): _equip_item(iid, item_def))
	hbox.add_child(equip_btn)

	return hbox


func _get_rarity_color(rarity: String) -> Color:
	match rarity.to_lower():
		"common": return Color(0.4, 0.4, 0.4)
		"uncommon": return Color(0.2, 0.5, 0.2)
		"rare": return Color(0.2, 0.3, 0.6)
		"epic": return Color(0.5, 0.2, 0.5)
		"legendary": return Color(0.6, 0.5, 0.1)
		_: return Color(0.3, 0.3, 0.3)


func _on_slot_clicked(slot: int) -> void:
	# Toggle selection
	if selected_slot == slot:
		selected_slot = -1
	else:
		selected_slot = slot

	# Update visual feedback
	for s in slot_controls:
		var container: Control = slot_controls[s]
		var btn: Button = container.get_meta("button")
		if s == selected_slot:
			btn.add_theme_color_override("font_color", Color.YELLOW)
		else:
			btn.remove_theme_color_override("font_color")

	# Refresh item list with filter
	_refresh_stash_items()

	# Update status
	if selected_slot >= 0:
		status_label.text = "Select a %s from your stash" % SLOT_NAMES.get(slot, "item")
	else:
		status_label.text = "Select items from your stash"


func _equip_item(iid: String, item_def: Dictionary) -> void:
	if selected_slot < 0:
		# Auto-detect slot from category
		var category: String = item_def.get("category", "misc").to_lower()
		for slot in SLOT_CATEGORIES:
			for cat in SLOT_CATEGORIES[slot]:
				if category.contains(cat) or cat.contains(category):
					selected_slot = slot
					break
			if selected_slot >= 0:
				break

	if selected_slot < 0:
		status_label.text = "Select a slot first"
		return

	# Check if slot already has item
	if selected_slot in loadout:
		var old_iid: String = loadout[selected_slot]
		loadout.erase(selected_slot)

	# Equip item
	loadout[selected_slot] = iid

	# Update slot button
	if selected_slot in slot_controls:
		var container: Control = slot_controls[selected_slot]
		var btn: Button = container.get_meta("button")
		btn.text = item_def.get("name", iid)
		btn.add_theme_color_override("font_color", Color.GREEN)

	# Clear selection
	var prev_slot := selected_slot
	selected_slot = -1
	_on_slot_clicked(-1)  # Reset UI

	status_label.text = "Equipped %s" % item_def.get("name", iid)

	# Refresh items list
	_refresh_stash_items()


func _on_ready_pressed() -> void:
	if loadout.is_empty():
		status_label.text = "Equip at least one item!"
		return

	status_label.text = "Preparing raid..."
	ready_button.disabled = true

	# Convert loadout to backend format
	var loadout_data := {}
	for slot in loadout:
		var slot_name: String = SLOT_NAMES.get(slot, "slot_%d" % slot).to_lower().replace(" ", "_")
		loadout_data[slot_name] = loadout[slot]

	# Prepare raid via backend
	var lobby_id: String = LobbySystem.get_current_lobby_id() if LobbySystem else "direct_%d" % Time.get_unix_time_from_system()
	var success := await EconomyService.prepare_raid(lobby_id, loadout_data)

	ready_button.disabled = false

	if success:
		status_label.text = "Ready! Waiting for other players..."
		ready_for_raid.emit(loadout_data)
	else:
		status_label.text = "Failed to prepare loadout"


func _on_raid_prepared(raid_id: String, locked_iids: Array) -> void:
	print("[LoadoutScreen] Raid prepared: %s, locked %d items" % [raid_id, locked_iids.size()])

	# Update slot visuals to show locked state
	for slot in loadout:
		if loadout[slot] in locked_iids:
			if slot in slot_controls:
				var container: Control = slot_controls[slot]
				var btn: Button = container.get_meta("button")
				btn.add_theme_color_override("font_color", Color.ORANGE)
				btn.text += " [LOCKED]"


func _on_stash_updated(_stash: Dictionary, _items: Array, _wallet: Dictionary) -> void:
	_refresh_stash_items()
	_update_gold_display()


func _on_operation_failed(error: String) -> void:
	status_label.text = "Error: %s" % error


func _update_gold_display() -> void:
	if gold_label:
		gold_label.text = "%d" % EconomyService.get_gold()


func get_loadout() -> Dictionary:
	return loadout


func clear_loadout() -> void:
	loadout.clear()
	selected_slot = -1

	# Reset all slot buttons
	for slot in slot_controls:
		var container: Control = slot_controls[slot]
		var btn: Button = container.get_meta("button")
		btn.text = "[Empty]"
		btn.remove_theme_color_override("font_color")

	_refresh_stash_items()
