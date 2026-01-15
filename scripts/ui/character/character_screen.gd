extends Control
class_name CharacterScreen
## CharacterScreen - Character management with skills, attributes, and equipment
##
## Features:
## - Polished skill tree with 4 categories (OFFENSE, DEFENSE, HANDLING, CONDITIONING)
## - Attribute panel (STR, AGI, END, INT, LCK)
## - Equipment slots (head, pendant, hands, chest, cape, rings, pants, feet)
## - Currency display
## - Prestige system integration
## - Skill tooltips with descriptions
## - Animated transitions and feedback

signal screen_closed

# UI Constants
const SLOT_SIZE := Vector2(64, 64)
const SKILL_BUTTON_SIZE := Vector2(56, 56)
const SKILL_NODE_SIZE := Vector2(70, 90)

# Skill descriptions for tooltips
const SKILL_DESCRIPTIONS := {
	# Offense
	"damage_boost": {"name": "Damage Boost", "desc": "Increases all weapon damage.", "bonus": "+5% damage per level"},
	"critical_chance": {"name": "Critical Chance", "desc": "Improves chance to deal critical hits.", "bonus": "+2% crit chance per level"},
	"critical_damage": {"name": "Critical Damage", "desc": "Enhances damage dealt on critical hits.", "bonus": "+10% crit damage per level"},
	"penetration": {"name": "Armor Piercing", "desc": "Bullets ignore enemy armor.", "bonus": "+3% armor penetration per level"},
	"fire_rate": {"name": "Fire Rate", "desc": "Increases weapon fire rate.", "bonus": "+3% fire rate per level"},
	"reload_speed": {"name": "Reload Speed", "desc": "Faster magazine reloads.", "bonus": "+5% reload speed per level"},
	"headshot_damage": {"name": "Headhunter", "desc": "Deal more damage with headshots.", "bonus": "+4% headshot damage per level"},
	"explosive_damage": {"name": "Demolitions", "desc": "Grenades and explosives deal more damage.", "bonus": "+6% explosive damage per level"},
	# Defense
	"health_boost": {"name": "Vitality", "desc": "Increases maximum health.", "bonus": "+5% max health per level"},
	"armor_rating": {"name": "Armor Rating", "desc": "Reduces incoming damage.", "bonus": "+2 armor per level"},
	"damage_reduction": {"name": "Damage Reduction", "desc": "Flat damage reduction from all sources.", "bonus": "+2% damage reduction per level"},
	"bleed_resistance": {"name": "Bleed Resist", "desc": "Resist bleeding effects.", "bonus": "+10% bleed resistance per level"},
	"stagger_resistance": {"name": "Stagger Resist", "desc": "Harder to stagger or knockback.", "bonus": "+10% stagger resistance per level"},
	"regeneration": {"name": "Regeneration", "desc": "Slowly recover health over time.", "bonus": "+0.5 HP/sec per level"},
	"shield_capacity": {"name": "Shield Up", "desc": "Increases shield capacity if equipped.", "bonus": "+8% shield per level"},
	"death_defiance": {"name": "Death Defiance", "desc": "Chance to survive fatal damage.", "bonus": "+2% survival chance per level"},
	# Handling
	"accuracy": {"name": "Accuracy", "desc": "Improves weapon accuracy.", "bonus": "+5% accuracy per level"},
	"recoil_control": {"name": "Recoil Control", "desc": "Reduces weapon recoil.", "bonus": "-5% recoil per level"},
	"swap_speed": {"name": "Quick Hands", "desc": "Faster weapon swapping.", "bonus": "+10% swap speed per level"},
	"aim_stability": {"name": "Steady Aim", "desc": "Less scope sway when aiming.", "bonus": "+5% aim stability per level"},
	"movement_accuracy": {"name": "Run & Gun", "desc": "Better accuracy while moving.", "bonus": "+5% move accuracy per level"},
	"quick_scope": {"name": "Quick Scope", "desc": "Faster aim down sights.", "bonus": "+10% ADS speed per level"},
	"hip_fire": {"name": "Hip Fire", "desc": "Better accuracy without aiming.", "bonus": "+4% hip fire accuracy per level"},
	"weapon_handling": {"name": "Weapon Handling", "desc": "Overall weapon handling improvement.", "bonus": "+3% handling per level"},
	# Conditioning
	"stamina_boost": {"name": "Stamina Boost", "desc": "Increases maximum stamina.", "bonus": "+5% max stamina per level"},
	"stamina_regen": {"name": "Stamina Regen", "desc": "Faster stamina recovery.", "bonus": "+5% stamina regen per level"},
	"movement_speed": {"name": "Movement Speed", "desc": "Move faster on foot.", "bonus": "+2% move speed per level"},
	"sprint_duration": {"name": "Marathon", "desc": "Sprint for longer periods.", "bonus": "+5% sprint duration per level"},
	"jump_height": {"name": "Jump Height", "desc": "Jump higher.", "bonus": "+3% jump height per level"},
	"noise_reduction": {"name": "Silent Steps", "desc": "Move more quietly.", "bonus": "-5% noise per level"},
	"fall_damage": {"name": "Parkour", "desc": "Take less fall damage.", "bonus": "-8% fall damage per level"},
	"carry_capacity": {"name": "Pack Mule", "desc": "Carry more weight.", "bonus": "+5% carry capacity per level"},
}

# Animation helper
var _ui_anim := UIAnimations.new()

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
var category_budget_bars: Dictionary = {}
var tier_labels: Dictionary = {}
var skill_tooltip: Control = null
var tooltip_title: Label = null
var tooltip_desc: Label = null
var tooltip_bonus: Label = null
var tooltip_cost: Label = null
var hovered_skill: String = ""

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
	margin.add_theme_constant_override("margin_top", 15)
	margin.add_theme_constant_override("margin_bottom", 15)
	skills_panel.add_child(margin)

	var main_hbox := HBoxContainer.new()
	main_hbox.add_theme_constant_override("separation", 20)
	margin.add_child(main_hbox)

	# Left side - category selection and budget
	var left_panel := VBoxContainer.new()
	left_panel.custom_minimum_size = Vector2(200, 0)
	left_panel.add_theme_constant_override("separation", 15)
	main_hbox.add_child(left_panel)

	# Skill points display (prominent)
	var points_panel := PanelContainer.new()
	var points_style := StyleBoxFlat.new()
	points_style.bg_color = Color(0.12, 0.15, 0.2)
	points_style.border_color = Color(0.3, 0.9, 0.3, 0.5)
	points_style.set_border_width_all(2)
	points_style.set_corner_radius_all(8)
	points_style.set_content_margin_all(12)
	points_panel.add_theme_stylebox_override("panel", points_style)
	left_panel.add_child(points_panel)

	var points_vbox := VBoxContainer.new()
	points_vbox.add_theme_constant_override("separation", 4)
	points_panel.add_child(points_vbox)

	var points_title := Label.new()
	points_title.text = "SKILL POINTS"
	points_title.add_theme_font_size_override("font_size", 12)
	points_title.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
	points_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	points_vbox.add_child(points_title)

	skill_point_label = Label.new()
	skill_point_label.text = "0"
	skill_point_label.add_theme_font_size_override("font_size", 36)
	skill_point_label.add_theme_color_override("font_color", Color(0.3, 0.9, 0.3))
	skill_point_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	points_vbox.add_child(skill_point_label)

	# Category buttons (vertical)
	var cat_label := Label.new()
	cat_label.text = "CATEGORIES"
	cat_label.add_theme_font_size_override("font_size", 12)
	cat_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55))
	left_panel.add_child(cat_label)

	category_tabs = TabBar.new()
	category_tabs.tab_changed.connect(_on_category_tab_changed)
	category_tabs.visible = false  # Hidden, we use custom buttons

	# Create category buttons with budget bars
	for cat in SkillSystem.Category.values():
		var cat_container := _create_category_button(cat)
		left_panel.add_child(cat_container)
		category_tabs.add_tab(SkillSystem.CATEGORY_NAMES[cat])

	# Prestige button at bottom
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_panel.add_child(spacer)

	prestige_button = Button.new()
	prestige_button.text = "PRESTIGE"
	prestige_button.custom_minimum_size = Vector2(0, 40)
	prestige_button.pressed.connect(_on_prestige_pressed)
	_style_prestige_button(prestige_button)
	left_panel.add_child(prestige_button)

	# Right side - skill grid
	var right_panel := VBoxContainer.new()
	right_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_panel.add_theme_constant_override("separation", 10)
	main_hbox.add_child(right_panel)

	# Category header with tier
	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 15)
	right_panel.add_child(header_row)

	var cat_title := Label.new()
	cat_title.name = "CategoryTitle"
	cat_title.text = "OFFENSE"
	cat_title.add_theme_font_size_override("font_size", 24)
	cat_title.add_theme_color_override("font_color", SkillSystem.CATEGORY_COLORS[SkillSystem.Category.OFFENSE])
	header_row.add_child(cat_title)

	var tier_badge := _create_tier_badge()
	header_row.add_child(tier_badge)

	var header_spacer := Control.new()
	header_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(header_spacer)

	# Skill grid with scroll
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_panel.add_child(scroll)

	var scroll_vbox := VBoxContainer.new()
	scroll_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(scroll_vbox)

	skill_grid = GridContainer.new()
	skill_grid.columns = 4
	skill_grid.add_theme_constant_override("h_separation", 15)
	skill_grid.add_theme_constant_override("v_separation", 15)
	scroll_vbox.add_child(skill_grid)

	# Create tooltip (hidden initially)
	_create_skill_tooltip()


func _create_category_button(cat: SkillSystem.Category) -> Control:
	var container := VBoxContainer.new()
	container.add_theme_constant_override("separation", 4)

	var color: Color = SkillSystem.CATEGORY_COLORS[cat]
	var name: String = SkillSystem.CATEGORY_NAMES[cat]

	var btn := Button.new()
	btn.text = name
	btn.custom_minimum_size = Vector2(0, 36)
	btn.toggle_mode = true
	btn.button_group = _get_category_button_group()
	btn.pressed.connect(_on_category_button_pressed.bind(cat))
	btn.set_meta("category", cat)

	var btn_style := StyleBoxFlat.new()
	btn_style.bg_color = color.darkened(0.6)
	btn_style.border_color = color.darkened(0.3)
	btn_style.set_border_width_all(2)
	btn_style.set_corner_radius_all(6)
	btn.add_theme_stylebox_override("normal", btn_style)

	var btn_pressed := btn_style.duplicate()
	btn_pressed.bg_color = color.darkened(0.3)
	btn_pressed.border_color = color
	btn.add_theme_stylebox_override("pressed", btn_pressed)

	var btn_hover := btn_style.duplicate()
	btn_hover.bg_color = color.darkened(0.5)
	btn.add_theme_stylebox_override("hover", btn_hover)

	container.add_child(btn)

	# Budget progress bar
	var budget_bar := ProgressBar.new()
	budget_bar.custom_minimum_size = Vector2(0, 6)
	budget_bar.max_value = 1500  # Max tier
	budget_bar.value = 0
	budget_bar.show_percentage = false

	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = color
	bar_fill.set_corner_radius_all(2)
	budget_bar.add_theme_stylebox_override("fill", bar_fill)

	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(0.08, 0.08, 0.1)
	bar_bg.set_corner_radius_all(2)
	budget_bar.add_theme_stylebox_override("background", bar_bg)

	container.add_child(budget_bar)

	category_budget_bars[cat] = {"button": btn, "bar": budget_bar}

	# Select first category by default
	if cat == SkillSystem.Category.OFFENSE:
		btn.button_pressed = true

	return container


var _category_button_group: ButtonGroup = null

func _get_category_button_group() -> ButtonGroup:
	if not _category_button_group:
		_category_button_group = ButtonGroup.new()
	return _category_button_group


func _on_category_button_pressed(cat: SkillSystem.Category) -> void:
	category_tabs.current_tab = cat as int
	_on_category_tab_changed(cat as int)


func _style_prestige_button(btn: Button) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.4, 0.2, 0.5)
	style.border_color = Color(0.7, 0.4, 0.9)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	btn.add_theme_stylebox_override("normal", style)

	var hover := style.duplicate()
	hover.bg_color = Color(0.5, 0.25, 0.6)
	btn.add_theme_stylebox_override("hover", hover)

	var disabled := style.duplicate()
	disabled.bg_color = Color(0.2, 0.15, 0.25)
	disabled.border_color = Color(0.3, 0.25, 0.35)
	btn.add_theme_stylebox_override("disabled", disabled)


func _create_tier_badge() -> Control:
	var container := HBoxContainer.new()
	container.name = "TierBadge"
	container.add_theme_constant_override("separation", 8)

	var tier_label := Label.new()
	tier_label.name = "TierLabel"
	tier_label.text = "TIER 0"
	tier_label.add_theme_font_size_override("font_size", 14)
	tier_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
	container.add_child(tier_label)

	var progress := ProgressBar.new()
	progress.name = "TierProgress"
	progress.custom_minimum_size = Vector2(80, 16)
	progress.max_value = 100
	progress.value = 0
	progress.show_percentage = false

	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.5, 0.5, 0.55)
	fill.set_corner_radius_all(3)
	progress.add_theme_stylebox_override("fill", fill)

	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.1, 0.1, 0.12)
	bg.set_corner_radius_all(3)
	progress.add_theme_stylebox_override("background", bg)

	container.add_child(progress)

	return container


func _create_skill_tooltip() -> void:
	skill_tooltip = PanelContainer.new()
	skill_tooltip.visible = false
	skill_tooltip.z_index = 100
	skill_tooltip.custom_minimum_size = Vector2(250, 0)
	add_child(skill_tooltip)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.12, 0.95)
	style.border_color = Color(0.4, 0.4, 0.45)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(12)
	skill_tooltip.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	skill_tooltip.add_child(vbox)

	tooltip_title = Label.new()
	tooltip_title.add_theme_font_size_override("font_size", 16)
	tooltip_title.add_theme_color_override("font_color", Color(0.9, 0.9, 0.95))
	vbox.add_child(tooltip_title)

	var sep := HSeparator.new()
	vbox.add_child(sep)

	tooltip_desc = Label.new()
	tooltip_desc.add_theme_font_size_override("font_size", 13)
	tooltip_desc.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
	tooltip_desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(tooltip_desc)

	tooltip_bonus = Label.new()
	tooltip_bonus.add_theme_font_size_override("font_size", 13)
	tooltip_bonus.add_theme_color_override("font_color", Color(0.3, 0.9, 0.3))
	vbox.add_child(tooltip_bonus)

	tooltip_cost = Label.new()
	tooltip_cost.add_theme_font_size_override("font_size", 13)
	tooltip_cost.add_theme_color_override("font_color", Color(0.9, 0.8, 0.3))
	vbox.add_child(tooltip_cost)


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

	# Update skill points with animation
	var old_points := int(skill_point_label.text) if skill_point_label.text.is_valid_int() else 0
	var new_points := skill_system.skill_points
	if old_points != new_points:
		_ui_anim.count_number(skill_point_label, old_points, new_points, 0.3, "%.0f")
	else:
		skill_point_label.text = str(skill_system.skill_points)

	# Update prestige button
	var total_budget: float = 0.0
	for cat in skill_system.category_budgets:
		total_budget += skill_system.category_budgets[cat]
	prestige_button.disabled = total_budget < 2000
	if skill_system.prestige_level > 0:
		prestige_button.text = "PRESTIGE (P%d)" % skill_system.prestige_level
	else:
		prestige_button.text = "PRESTIGE"

	# Update category budget bars
	for cat in category_budget_bars:
		var data: Dictionary = category_budget_bars[cat]
		var budget: float = skill_system.category_budgets.get(cat, 0.0)
		var bar := data.bar as ProgressBar
		if bar:
			var tween := bar.create_tween()
			tween.tween_property(bar, "value", budget, 0.2)

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
	var category_name: String = SkillSystem.CATEGORY_NAMES.get(category, "Unknown")

	# Update category title
	var title_node := skills_panel.find_child("CategoryTitle", true, false)
	if title_node:
		title_node.text = category_name.to_upper()
		title_node.add_theme_color_override("font_color", category_color)

	# Update tier badge
	_update_tier_display(category)

	for skill_id in category_skills:
		var skill_node := _create_skill_node(category, skill_id, category_color)
		skill_grid.add_child(skill_node)


func _create_skill_node(category: SkillSystem.Category, skill_id: String, category_color: Color) -> Control:
	var container := VBoxContainer.new()
	container.custom_minimum_size = SKILL_NODE_SIZE
	container.add_theme_constant_override("separation", 4)

	var level: int = skill_system.get_skill_level(category, skill_id)
	var is_maxed := level >= SkillSystem.MAX_SKILL_LEVEL
	var can_upgrade := skill_system.can_upgrade_skill(category, skill_id)

	# Skill button with icon area
	var btn := Button.new()
	btn.custom_minimum_size = SKILL_BUTTON_SIZE
	btn.pressed.connect(_on_skill_pressed.bind(category, skill_id))
	btn.mouse_entered.connect(_on_skill_hover.bind(category, skill_id, btn))
	btn.mouse_exited.connect(_on_skill_unhover)
	btn.focus_mode = Control.FOCUS_NONE

	# Create button content
	var btn_content := VBoxContainer.new()
	btn_content.set_anchors_preset(Control.PRESET_FULL_RECT)
	btn_content.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(btn_content)

	# Icon placeholder (colored circle)
	var icon_container := CenterContainer.new()
	icon_container.custom_minimum_size = Vector2(28, 28)
	icon_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn_content.add_child(icon_container)

	var icon := ColorRect.new()
	icon.custom_minimum_size = Vector2(24, 24)
	icon.color = category_color if level > 0 else category_color.darkened(0.5)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_container.add_child(icon)

	# Level text
	var level_text := Label.new()
	level_text.text = "%d/%d" % [level, SkillSystem.MAX_SKILL_LEVEL]
	level_text.add_theme_font_size_override("font_size", 11)
	level_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	level_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if is_maxed:
		level_text.add_theme_color_override("font_color", Color(0.9, 0.8, 0.3))
	elif level > 0:
		level_text.add_theme_color_override("font_color", Color(0.9, 0.9, 0.95))
	else:
		level_text.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55))
	btn_content.add_child(level_text)

	# Style button
	var btn_style := StyleBoxFlat.new()
	if is_maxed:
		btn_style.bg_color = category_color.darkened(0.2)
		btn_style.border_color = Color(0.9, 0.8, 0.3)
		btn_style.set_border_width_all(3)
	elif level > 0:
		btn_style.bg_color = category_color.darkened(0.5)
		btn_style.border_color = category_color.darkened(0.2)
		btn_style.set_border_width_all(2)
	else:
		btn_style.bg_color = Color(0.12, 0.12, 0.15)
		btn_style.border_color = Color(0.25, 0.25, 0.3)
		btn_style.set_border_width_all(2)
	btn_style.set_corner_radius_all(10)
	btn.add_theme_stylebox_override("normal", btn_style)

	# Hover style
	var btn_hover := btn_style.duplicate()
	if can_upgrade:
		btn_hover.bg_color = category_color.darkened(0.4)
		btn_hover.border_color = category_color
	else:
		btn_hover.bg_color = btn_style.bg_color.lightened(0.1)
	btn.add_theme_stylebox_override("hover", btn_hover)

	# Pressed style
	var btn_pressed := btn_style.duplicate()
	btn_pressed.bg_color = category_color.darkened(0.3)
	btn.add_theme_stylebox_override("pressed", btn_pressed)

	# Add glow effect for upgradable skills
	if can_upgrade:
		btn.modulate = Color(1.1, 1.1, 1.1)

	container.add_child(btn)

	# Skill name
	var skill_info: Dictionary = SKILL_DESCRIPTIONS.get(skill_id, {})
	var display_name: String = skill_info.get("name", skill_id.replace("_", " ").capitalize())

	var name_label := Label.new()
	name_label.text = display_name
	name_label.add_theme_font_size_override("font_size", 10)
	name_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	name_label.custom_minimum_size = Vector2(SKILL_NODE_SIZE.x, 0)
	container.add_child(name_label)

	# Level progress bar
	var level_bar := ProgressBar.new()
	level_bar.custom_minimum_size = Vector2(SKILL_BUTTON_SIZE.x, 6)
	level_bar.max_value = SkillSystem.MAX_SKILL_LEVEL
	level_bar.value = level
	level_bar.show_percentage = false

	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = category_color if not is_maxed else Color(0.9, 0.8, 0.3)
	bar_fill.set_corner_radius_all(2)
	level_bar.add_theme_stylebox_override("fill", bar_fill)

	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(0.08, 0.08, 0.1)
	bar_bg.set_corner_radius_all(2)
	level_bar.add_theme_stylebox_override("background", bar_bg)

	container.add_child(level_bar)

	skill_buttons[skill_id] = {
		"container": container,
		"button": btn,
		"label": name_label,
		"bar": level_bar,
		"icon": icon
	}

	return container


func _update_tier_display(category: SkillSystem.Category) -> void:
	if not skill_system:
		return

	var tier := skill_system.get_category_tier(category)
	var progress := skill_system.get_tier_progress(category) * 100
	var color: Color = SkillSystem.CATEGORY_COLORS.get(category, Color.WHITE)

	var badge := skills_panel.find_child("TierBadge", true, false)
	if badge:
		var tier_label := badge.find_child("TierLabel", true, false) as Label
		var tier_progress := badge.find_child("TierProgress", true, false) as ProgressBar

		if tier_label:
			tier_label.text = "TIER %d" % tier
			if tier >= 4:
				tier_label.add_theme_color_override("font_color", Color(0.9, 0.8, 0.3))
			else:
				tier_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))

		if tier_progress:
			tier_progress.value = progress
			var fill := tier_progress.get_theme_stylebox("fill") as StyleBoxFlat
			if fill:
				fill.bg_color = color


func _on_skill_hover(category: SkillSystem.Category, skill_id: String, btn: Button) -> void:
	hovered_skill = skill_id

	# Animate button
	btn.pivot_offset = btn.size / 2
	_ui_anim.button_hover(btn, 1.08)

	# Update tooltip content
	var skill_info: Dictionary = SKILL_DESCRIPTIONS.get(skill_id, {})
	var level: int = skill_system.get_skill_level(category, skill_id)
	var cost: int = skill_system.get_skill_upgrade_cost(category, skill_id)
	var can_upgrade := skill_system.can_upgrade_skill(category, skill_id)

	tooltip_title.text = skill_info.get("name", skill_id.replace("_", " ").capitalize())
	tooltip_desc.text = skill_info.get("desc", "No description available.")
	tooltip_bonus.text = skill_info.get("bonus", "")

	if level >= SkillSystem.MAX_SKILL_LEVEL:
		tooltip_cost.text = "MAX LEVEL"
		tooltip_cost.add_theme_color_override("font_color", Color(0.9, 0.8, 0.3))
	elif can_upgrade:
		tooltip_cost.text = "Cost: %d skill point%s" % [cost, "s" if cost > 1 else ""]
		tooltip_cost.add_theme_color_override("font_color", Color(0.3, 0.9, 0.3))
	else:
		tooltip_cost.text = "Need %d more point%s" % [cost - skill_system.skill_points, "s" if cost - skill_system.skill_points > 1 else ""]
		tooltip_cost.add_theme_color_override("font_color", Color(0.9, 0.4, 0.3))

	# Position and show tooltip
	await get_tree().process_frame
	var btn_global := btn.global_position
	skill_tooltip.position = btn_global + Vector2(btn.size.x + 10, 0)

	# Keep tooltip on screen
	var screen_size := get_viewport_rect().size
	if skill_tooltip.position.x + skill_tooltip.size.x > screen_size.x - 20:
		skill_tooltip.position.x = btn_global.x - skill_tooltip.size.x - 10
	if skill_tooltip.position.y + skill_tooltip.size.y > screen_size.y - 20:
		skill_tooltip.position.y = screen_size.y - skill_tooltip.size.y - 20

	skill_tooltip.visible = true
	skill_tooltip.modulate.a = 0.0
	var tween := skill_tooltip.create_tween()
	tween.tween_property(skill_tooltip, "modulate:a", 1.0, 0.1)


func _on_skill_unhover() -> void:
	hovered_skill = ""

	# Hide tooltip
	if skill_tooltip.visible:
		var tween := skill_tooltip.create_tween()
		tween.tween_property(skill_tooltip, "modulate:a", 0.0, 0.08)
		tween.tween_callback(func(): skill_tooltip.visible = false)


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


func _on_skill_upgraded(_category: String, skill_id: String, _new_level: int) -> void:
	# Animate the upgraded skill
	if skill_id in skill_buttons:
		var data: Dictionary = skill_buttons[skill_id]
		var btn := data.get("button") as Button
		if btn:
			_ui_anim.pulse(btn, 1.15, 0.2)
			_ui_anim.flash(btn, Color(1.5, 1.5, 1.0), 0.2)

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
