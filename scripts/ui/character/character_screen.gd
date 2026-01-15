extends Control
class_name CharacterScreen
## CharacterScreen - Character management with skills, attributes, and equipment
##
## Features:
## - Skill tree with 4 categories (OFFENSE, DEFENSE, HANDLING, CONDITIONING)
## - Attribute panel (STR, AGI, END, INT, LCK)
## - Equipment slots (head, pendant, hands, chest, cape, rings, pants, feet)
## - Currency display
## - Prestige system integration

signal screen_closed

# UI Constants
const SLOT_SIZE := Vector2(64, 64)
const SKILL_BUTTON_SIZE := Vector2(48, 48)

# Equipment slot definitions
const EQUIPMENT_SLOTS := {
	"head": {"position": Vector2(1, 0), "label": "Head"},
	"pendant": {"position": Vector2(1, 1), "label": "Pendant"},
	"chest": {"position": Vector2(1, 2), "label": "Chest"},
	"cape": {"position": Vector2(2, 1), "label": "Cape"},
	"hands": {"position": Vector2(0, 2), "label": "Hands"},
	"ring_left": {"position": Vector2(0, 3), "label": "Ring L"},
	"ring_right": {"position": Vector2(2, 3), "label": "Ring R"},
	"pants": {"position": Vector2(1, 3), "label": "Pants"},
	"feet": {"position": Vector2(1, 4), "label": "Feet"},
}

# References
var skill_system: SkillSystem = null
var attribute_system: AttributeSystem = null

# UI Elements
var tab_container: TabContainer = null
var skills_panel: Control = null
var attributes_panel: Control = null
var equipment_panel: Control = null

# Skills UI
var category_tabs: TabBar = null
var skill_grid: GridContainer = null
var skill_buttons: Dictionary = {}
var skill_point_label: Label = null
var prestige_button: Button = null
var subclass_label: Label = null

# Attributes UI
var attribute_rows: Dictionary = {}
var attribute_points_label: Label = null
var level_label: Label = null
var xp_bar: ProgressBar = null

# Equipment UI
var equipment_slots_ui: Dictionary = {}
var character_preview: Control = null

# Currency
var gold_label: Label = null


func _ready() -> void:
	_create_ui()
	_initialize_systems()
	_connect_signals()
	_refresh_display()


func _create_ui() -> void:
	# Dark background
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.09, 0.1, 0.95)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Main container with margins
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 40)
	margin.add_theme_constant_override("margin_right", 40)
	margin.add_theme_constant_override("margin_top", 40)
	margin.add_theme_constant_override("margin_bottom", 40)
	add_child(margin)

	var main_vbox := VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 20)
	margin.add_child(main_vbox)

	# Header
	_create_header(main_vbox)

	# Content area (tabs)
	_create_content_tabs(main_vbox)

	# Footer with currency and close button
	_create_footer(main_vbox)


func _create_header(parent: Control) -> void:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 20)
	parent.add_child(header)

	# Title
	var title := Label.new()
	title.text = "CHARACTER"
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	# Subclass display
	subclass_label = Label.new()
	subclass_label.text = "No Subclass"
	subclass_label.add_theme_font_size_override("font_size", 18)
	subclass_label.add_theme_color_override("font_color", Color(0.7, 0.5, 0.9))
	header.add_child(subclass_label)

	# Level display
	level_label = Label.new()
	level_label.text = "Level 1"
	level_label.add_theme_font_size_override("font_size", 18)
	level_label.add_theme_color_override("font_color", Color(0.9, 0.8, 0.3))
	header.add_child(level_label)


func _create_content_tabs(parent: Control) -> void:
	tab_container = TabContainer.new()
	tab_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(tab_container)

	# Skills Tab
	_create_skills_tab()

	# Attributes Tab
	_create_attributes_tab()

	# Equipment Tab
	_create_equipment_tab()


func _create_skills_tab() -> void:
	skills_panel = PanelContainer.new()
	skills_panel.name = "Skills"
	tab_container.add_child(skills_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	skills_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 15)
	margin.add_child(vbox)

	# Skill points display
	var points_row := HBoxContainer.new()
	points_row.add_theme_constant_override("separation", 20)
	vbox.add_child(points_row)

	var points_title := Label.new()
	points_title.text = "Skill Points:"
	points_title.add_theme_font_size_override("font_size", 16)
	points_row.add_child(points_title)

	skill_point_label = Label.new()
	skill_point_label.text = "0"
	skill_point_label.add_theme_font_size_override("font_size", 16)
	skill_point_label.add_theme_color_override("font_color", Color(0.3, 0.9, 0.3))
	points_row.add_child(skill_point_label)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	points_row.add_child(spacer)

	prestige_button = Button.new()
	prestige_button.text = "PRESTIGE"
	prestige_button.custom_minimum_size = Vector2(120, 35)
	prestige_button.pressed.connect(_on_prestige_pressed)
	points_row.add_child(prestige_button)

	# Category tabs
	category_tabs = TabBar.new()
	category_tabs.tab_changed.connect(_on_category_tab_changed)
	vbox.add_child(category_tabs)

	# Add category tabs with colors
	for cat in SkillSystem.Category.values():
		var idx := category_tabs.tab_count
		category_tabs.add_tab(SkillSystem.CATEGORY_NAMES[cat])
		# Note: TabBar doesn't support per-tab colors directly, but we show it in skill grid

	# Skill grid
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	skill_grid = GridContainer.new()
	skill_grid.columns = 3
	skill_grid.add_theme_constant_override("h_separation", 20)
	skill_grid.add_theme_constant_override("v_separation", 15)
	scroll.add_child(skill_grid)


func _create_attributes_tab() -> void:
	attributes_panel = PanelContainer.new()
	attributes_panel.name = "Attributes"
	tab_container.add_child(attributes_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	attributes_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 15)
	margin.add_child(vbox)

	# Attribute points display
	var points_row := HBoxContainer.new()
	vbox.add_child(points_row)

	var points_title := Label.new()
	points_title.text = "Attribute Points:"
	points_title.add_theme_font_size_override("font_size", 16)
	points_row.add_child(points_title)

	attribute_points_label = Label.new()
	attribute_points_label.text = "0"
	attribute_points_label.add_theme_font_size_override("font_size", 16)
	attribute_points_label.add_theme_color_override("font_color", Color(0.3, 0.9, 0.3))
	points_row.add_child(attribute_points_label)

	# XP bar
	var xp_row := HBoxContainer.new()
	xp_row.add_theme_constant_override("separation", 10)
	vbox.add_child(xp_row)

	var xp_label := Label.new()
	xp_label.text = "XP:"
	xp_label.add_theme_font_size_override("font_size", 14)
	xp_row.add_child(xp_label)

	xp_bar = ProgressBar.new()
	xp_bar.custom_minimum_size = Vector2(200, 20)
	xp_bar.value = 0
	xp_bar.show_percentage = true
	xp_row.add_child(xp_bar)

	# Separator
	var sep := HSeparator.new()
	vbox.add_child(sep)

	# Attribute rows
	for attr in AttributeSystem.Attribute.values():
		_create_attribute_row(vbox, attr)


func _create_attribute_row(parent: Control, attr: AttributeSystem.Attribute) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 15)
	parent.add_child(row)

	var color: Color = AttributeSystem.ATTRIBUTE_COLORS[attr]
	var name: String = AttributeSystem.ATTRIBUTE_NAMES[attr]
	var abbrev: String = AttributeSystem.ATTRIBUTE_ABBREV[attr]

	# Attribute name
	var name_label := Label.new()
	name_label.text = "%s (%s)" % [name, abbrev]
	name_label.custom_minimum_size = Vector2(180, 0)
	name_label.add_theme_font_size_override("font_size", 16)
	name_label.add_theme_color_override("font_color", color)
	row.add_child(name_label)

	# Value display
	var value_label := Label.new()
	value_label.text = "10"
	value_label.custom_minimum_size = Vector2(40, 0)
	value_label.add_theme_font_size_override("font_size", 16)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(value_label)

	# Progress bar showing attribute level
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(150, 25)
	bar.max_value = 100
	bar.value = 10
	bar.show_percentage = false

	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = color
	bar_fill.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("fill", bar_fill)

	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(0.15, 0.15, 0.18)
	bar_bg.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("background", bar_bg)
	row.add_child(bar)

	# Upgrade button
	var btn := Button.new()
	btn.text = "+"
	btn.custom_minimum_size = Vector2(40, 30)
	btn.pressed.connect(_on_attribute_upgrade.bind(attr))
	row.add_child(btn)

	# Spacer
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	# Derived stats preview
	var derived := Label.new()
	derived.text = ""
	derived.add_theme_font_size_override("font_size", 12)
	derived.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
	row.add_child(derived)

	attribute_rows[attr] = {
		"row": row,
		"value_label": value_label,
		"bar": bar,
		"button": btn,
		"derived": derived
	}


func _create_equipment_tab() -> void:
	equipment_panel = PanelContainer.new()
	equipment_panel.name = "Equipment"
	tab_container.add_child(equipment_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	equipment_panel.add_child(margin)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 40)
	margin.add_child(hbox)

	# Equipment slots (left side)
	var slots_container := VBoxContainer.new()
	slots_container.add_theme_constant_override("separation", 10)
	hbox.add_child(slots_container)

	var slots_title := Label.new()
	slots_title.text = "Equipment"
	slots_title.add_theme_font_size_override("font_size", 20)
	slots_container.add_child(slots_title)

	# Grid for equipment slots
	var slot_grid := GridContainer.new()
	slot_grid.columns = 3
	slot_grid.add_theme_constant_override("h_separation", 10)
	slot_grid.add_theme_constant_override("v_separation", 10)
	slots_container.add_child(slot_grid)

	# Create slot grid with proper positioning
	# We create a 3x5 grid and place slots at specific positions
	for y in range(5):
		for x in range(3):
			var slot_found := false
			var slot_id := ""

			for id in EQUIPMENT_SLOTS:
				var slot_info: Dictionary = EQUIPMENT_SLOTS[id]
				var pos: Vector2 = slot_info.position
				if int(pos.x) == x and int(pos.y) == y:
					slot_found = true
					slot_id = id
					break

			if slot_found:
				var slot := _create_equipment_slot(slot_id, EQUIPMENT_SLOTS[slot_id].label)
				slot_grid.add_child(slot)
				equipment_slots_ui[slot_id] = slot
			else:
				# Empty spacer
				var spacer := Control.new()
				spacer.custom_minimum_size = SLOT_SIZE
				slot_grid.add_child(spacer)

	# Character preview (center)
	character_preview = _create_character_preview()
	hbox.add_child(character_preview)

	# Stats summary (right side)
	var stats_container := VBoxContainer.new()
	stats_container.add_theme_constant_override("separation", 10)
	stats_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(stats_container)

	var stats_title := Label.new()
	stats_title.text = "Equipment Bonuses"
	stats_title.add_theme_font_size_override("font_size", 20)
	stats_container.add_child(stats_title)

	var stats_info := Label.new()
	stats_info.text = "Equip items to gain bonuses\n\nArmor: +0\nDamage: +0%\nSpeed: +0%"
	stats_info.add_theme_font_size_override("font_size", 14)
	stats_info.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
	stats_container.add_child(stats_info)


func _create_equipment_slot(slot_id: String, label_text: String) -> Control:
	var container := VBoxContainer.new()
	container.add_theme_constant_override("separation", 2)

	# Slot button
	var slot := Button.new()
	slot.custom_minimum_size = SLOT_SIZE
	slot.text = ""
	slot.pressed.connect(_on_equipment_slot_pressed.bind(slot_id))

	var slot_style := StyleBoxFlat.new()
	slot_style.bg_color = Color(0.15, 0.15, 0.18)
	slot_style.border_color = Color(0.3, 0.3, 0.35)
	slot_style.set_border_width_all(2)
	slot_style.set_corner_radius_all(4)
	slot.add_theme_stylebox_override("normal", slot_style)

	var slot_hover := slot_style.duplicate()
	slot_hover.border_color = Color(0.5, 0.5, 0.55)
	slot.add_theme_stylebox_override("hover", slot_hover)

	container.add_child(slot)

	# Label
	var lbl := Label.new()
	lbl.text = label_text
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	container.add_child(lbl)

	return container


func _create_character_preview() -> Control:
	var preview := Panel.new()
	preview.custom_minimum_size = Vector2(200, 400)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.15)
	style.border_color = Color(0.25, 0.25, 0.3)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	preview.add_theme_stylebox_override("panel", style)

	var label := Label.new()
	label.text = "Character\nPreview"
	label.set_anchors_preset(Control.PRESET_CENTER)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", Color(0.4, 0.4, 0.45))
	preview.add_child(label)

	return preview


func _create_footer(parent: Control) -> void:
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 20)
	parent.add_child(footer)

	# Gold display
	var gold_container := HBoxContainer.new()
	gold_container.add_theme_constant_override("separation", 8)
	footer.add_child(gold_container)

	var gold_icon := Label.new()
	gold_icon.text = "Gold:"
	gold_icon.add_theme_font_size_override("font_size", 16)
	gold_icon.add_theme_color_override("font_color", Color(0.9, 0.8, 0.3))
	gold_container.add_child(gold_icon)

	gold_label = Label.new()
	gold_label.text = "0"
	gold_label.add_theme_font_size_override("font_size", 16)
	gold_label.add_theme_color_override("font_color", Color(0.9, 0.8, 0.3))
	gold_container.add_child(gold_label)

	# Spacer
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)

	# Close button
	var close_btn := Button.new()
	close_btn.text = "Close (ESC)"
	close_btn.custom_minimum_size = Vector2(120, 40)
	close_btn.pressed.connect(close)
	footer.add_child(close_btn)


func _initialize_systems() -> void:
	# Create skill system and load saved data
	skill_system = SkillSystem.new()

	# Create attribute system
	attribute_system = AttributeSystem.new()

	# Load saved character data from EconomyService
	if EconomyService and EconomyService.is_logged_in:
		var saved_data: Dictionary = EconomyService.get_character_data()
		_apply_saved_data(saved_data)
	else:
		# No saved data - use defaults
		attribute_system.setup_default()


## Apply saved character data to systems
func _apply_saved_data(data: Dictionary) -> void:
	# Load attributes
	attribute_system.level = data.get("level", 1)
	attribute_system.experience = data.get("experience", 0)
	attribute_system.attribute_points = data.get("attribute_points", 5)

	var base_attrs: Dictionary = data.get("base_attributes", {})
	if not base_attrs.is_empty():
		for attr_name in base_attrs:
			var attr_enum := _get_attribute_enum(attr_name)
			if attr_enum >= 0:
				attribute_system.base_attributes[attr_enum] = base_attrs[attr_name]

	attribute_system._recalculate_derived_stats()

	# Load skills
	var skill_data: Dictionary = data.get("skill_data", {})
	if not skill_data.is_empty():
		skill_system.load_save_data(skill_data)
	else:
		# Set prestige level from saved data
		skill_system.prestige_level = data.get("prestige_level", 0)


## Convert attribute name string to enum
func _get_attribute_enum(name: String) -> int:
	match name.to_lower():
		"strength": return AttributeSystem.Attribute.STRENGTH
		"agility": return AttributeSystem.Attribute.AGILITY
		"endurance": return AttributeSystem.Attribute.ENDURANCE
		"intellect": return AttributeSystem.Attribute.INTELLECT
		"luck": return AttributeSystem.Attribute.LUCK
	return -1


## Save character data to EconomyService
func _save_character_data() -> void:
	if not EconomyService or not EconomyService.is_logged_in:
		return

	# Build attributes dictionary
	var attrs := {}
	for attr in AttributeSystem.Attribute.values():
		var name: String = AttributeSystem.ATTRIBUTE_NAMES[attr].to_lower()
		attrs[name] = attribute_system.base_attributes.get(attr, 10)

	EconomyService.update_attributes(attrs)
	EconomyService.set_attribute_points(attribute_system.attribute_points)

	# Save skill data
	if skill_system:
		var skill_data := skill_system.get_save_data()
		EconomyService.update_skill_data(skill_data)


func _connect_signals() -> void:
	if skill_system:
		skill_system.skill_upgraded.connect(_on_skill_upgraded)
		skill_system.skill_points_changed.connect(_on_skill_points_changed)
		skill_system.prestige_level_changed.connect(_on_prestige_changed)
		skill_system.subclass_unlocked.connect(_on_subclass_unlocked)

	if attribute_system:
		attribute_system.attribute_changed.connect(_on_attribute_changed)
		attribute_system.derived_stats_updated.connect(_on_derived_stats_updated)
		attribute_system.level_up.connect(_on_level_up)

	# Economy service for gold
	if EconomyService:
		EconomyService.gold_changed.connect(_on_gold_changed)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			close()


func open() -> void:
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh_display()


func close() -> void:
	visible = false
	screen_closed.emit()


func _refresh_display() -> void:
	_refresh_skills_display()
	_refresh_attributes_display()
	_refresh_header()
	_refresh_gold()


func _refresh_header() -> void:
	if skill_system:
		if skill_system.current_subclass != "":
			subclass_label.text = "%s (%s)" % [skill_system.current_subclass, skill_system.subclass_quality]
		else:
			subclass_label.text = "No Subclass"

	if attribute_system:
		level_label.text = "Level %d" % attribute_system.level


func _refresh_skills_display() -> void:
	if not skill_system:
		return

	# Update skill points
	skill_point_label.text = str(skill_system.skill_points)

	# Update prestige button
	var total_budget: float = 0.0
	for cat in skill_system.category_budgets:
		total_budget += skill_system.category_budgets[cat]
	prestige_button.disabled = total_budget < 2000
	prestige_button.text = "PRESTIGE (P%d)" % skill_system.prestige_level

	# Refresh skill grid for current category
	_populate_skill_grid(category_tabs.current_tab)


func _populate_skill_grid(category_idx: int) -> void:
	# Clear existing buttons
	for child in skill_grid.get_children():
		child.queue_free()
	skill_buttons.clear()

	if not skill_system:
		return

	var category: SkillSystem.Category = category_idx as SkillSystem.Category
	var category_skills: Dictionary = skill_system.skills.get(category, {})
	var category_color: Color = SkillSystem.CATEGORY_COLORS.get(category, Color.WHITE)

	for skill_id in category_skills:
		var skill_container := VBoxContainer.new()
		skill_container.add_theme_constant_override("separation", 4)
		skill_grid.add_child(skill_container)

		# Skill button
		var btn := Button.new()
		btn.custom_minimum_size = SKILL_BUTTON_SIZE
		btn.pressed.connect(_on_skill_pressed.bind(category, skill_id))

		var level: int = skill_system.get_skill_level(category, skill_id)
		btn.text = str(level)

		# Style based on level
		var btn_style := StyleBoxFlat.new()
		if level > 0:
			btn_style.bg_color = category_color.darkened(0.3)
			btn_style.border_color = category_color
		else:
			btn_style.bg_color = Color(0.15, 0.15, 0.18)
			btn_style.border_color = Color(0.3, 0.3, 0.35)
		btn_style.set_border_width_all(2)
		btn_style.set_corner_radius_all(8)
		btn.add_theme_stylebox_override("normal", btn_style)

		skill_container.add_child(btn)

		# Skill name
		var name_label := Label.new()
		var formatted_name: String = skill_id.replace("_", " ").capitalize()
		name_label.text = formatted_name
		name_label.add_theme_font_size_override("font_size", 11)
		name_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		skill_container.add_child(name_label)

		# Level progress
		var level_bar := ProgressBar.new()
		level_bar.custom_minimum_size = Vector2(SKILL_BUTTON_SIZE.x, 8)
		level_bar.max_value = SkillSystem.MAX_SKILL_LEVEL
		level_bar.value = level
		level_bar.show_percentage = false

		var bar_fill := StyleBoxFlat.new()
		bar_fill.bg_color = category_color
		bar_fill.set_corner_radius_all(2)
		level_bar.add_theme_stylebox_override("fill", bar_fill)

		var bar_bg := StyleBoxFlat.new()
		bar_bg.bg_color = Color(0.1, 0.1, 0.12)
		bar_bg.set_corner_radius_all(2)
		level_bar.add_theme_stylebox_override("background", bar_bg)

		skill_container.add_child(level_bar)

		skill_buttons[skill_id] = {
			"button": btn,
			"label": name_label,
			"bar": level_bar
		}


func _refresh_attributes_display() -> void:
	if not attribute_system:
		return

	# Update points
	attribute_points_label.text = str(attribute_system.attribute_points)

	# Update XP bar
	xp_bar.value = attribute_system.get_level_progress() * 100

	# Update each attribute row
	for attr in attribute_rows:
		var row_data: Dictionary = attribute_rows[attr]
		var value: int = attribute_system.get_attribute(attr)
		var base: int = attribute_system.get_base_attribute(attr)

		row_data.value_label.text = str(value)
		row_data.bar.value = value
		row_data.button.disabled = attribute_system.attribute_points <= 0 or base >= 100

		# Update derived stats preview
		_update_derived_preview(attr, row_data.derived)


func _update_derived_preview(attr: AttributeSystem.Attribute, label: Label) -> void:
	if not attribute_system:
		return

	match attr:
		AttributeSystem.Attribute.STRENGTH:
			var dmg: float = attribute_system.get_derived_stat("melee_damage_mult")
			var weight: float = attribute_system.get_derived_stat("carry_weight")
			label.text = "Melee: +%.0f%% | Carry: %.0f" % [(dmg - 1.0) * 100, weight]
		AttributeSystem.Attribute.AGILITY:
			var spd: float = attribute_system.get_derived_stat("move_speed_mult")
			var reload: float = attribute_system.get_derived_stat("reload_speed_mult")
			label.text = "Speed: +%.0f%% | Reload: +%.0f%%" % [(spd - 1.0) * 100, (reload - 1.0) * 100]
		AttributeSystem.Attribute.ENDURANCE:
			var hp: float = attribute_system.get_derived_stat("max_health")
			var stam: float = attribute_system.get_derived_stat("max_stamina")
			label.text = "HP: %.0f | Stamina: %.0f" % [hp, stam]
		AttributeSystem.Attribute.INTELLECT:
			var xp: float = attribute_system.get_derived_stat("xp_multiplier")
			var cd: float = attribute_system.get_derived_stat("skill_cooldown_mult")
			label.text = "XP: +%.0f%% | Cooldown: -%.0f%%" % [(xp - 1.0) * 100, (1.0 - cd) * 100]
		AttributeSystem.Attribute.LUCK:
			var crit: float = attribute_system.get_derived_stat("crit_chance")
			var loot: float = attribute_system.get_derived_stat("loot_quality_mult")
			label.text = "Crit: %.1f%% | Loot: +%.0f%%" % [crit * 100, (loot - 1.0) * 100]


func _refresh_gold() -> void:
	if EconomyService:
		gold_label.text = str(EconomyService.get_gold())


# Signal handlers

func _on_category_tab_changed(tab: int) -> void:
	_populate_skill_grid(tab)


func _on_skill_pressed(category: SkillSystem.Category, skill_id: String) -> void:
	if skill_system and skill_system.can_upgrade_skill(category, skill_id):
		skill_system.upgrade_skill(category, skill_id)


func _on_skill_upgraded(_category: String, _skill_id: String, _new_level: int) -> void:
	_refresh_skills_display()
	_save_character_data()  # Persist skill upgrade


func _on_skill_points_changed(_new_points: int) -> void:
	_refresh_skills_display()
	_save_character_data()  # Persist skill point change


func _on_prestige_pressed() -> void:
	if skill_system:
		skill_system.prestige()


func _on_prestige_changed(_new_level: int) -> void:
	_refresh_skills_display()
	_refresh_header()
	_save_character_data()  # Persist prestige level


func _on_subclass_unlocked(subclass_name: String) -> void:
	_refresh_header()
	_save_character_data()  # Persist subclass unlock
	print("[Character] Subclass unlocked: %s" % subclass_name)


func _on_attribute_upgrade(attr: AttributeSystem.Attribute) -> void:
	if attribute_system:
		attribute_system.increase_attribute(attr)
		_save_character_data()  # Persist attribute upgrade


func _on_attribute_changed(_attribute: String, _old_value: int, _new_value: int) -> void:
	_refresh_attributes_display()
	_save_character_data()  # Persist attribute change


func _on_derived_stats_updated(_stats: Dictionary) -> void:
	_refresh_attributes_display()


func _on_level_up(new_level: int, _attribute_points: int) -> void:
	_refresh_attributes_display()
	level_label.text = "Level %d" % new_level


func _on_gold_changed(new_amount: int) -> void:
	gold_label.text = str(new_amount)


func _on_equipment_slot_pressed(slot_id: String) -> void:
	print("[Character] Equipment slot pressed: %s" % slot_id)
	# TODO: Open equipment selection from stash
