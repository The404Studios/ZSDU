extends Control
class_name AnimatedTooltip
## AnimatedTooltip - Animated tooltip with flexible content
##
## Features:
## - Smooth reveal/hide animations
## - Auto-positioning to stay on screen
## - Header with icon and title
## - Stat comparisons (green/red deltas)
## - Description text with markdown-lite support
## - Rarity colors and styling
##
## Usage:
##   tooltip.show_item(item_data, anchor_position)
##   tooltip.show_attribute(attr_data, anchor_position)
##   tooltip.hide_tooltip()

signal shown
signal hidden

# Style constants
const PADDING := 12
const GAP := 6
const MAX_WIDTH := 320
const MIN_WIDTH := 200

const RARITY_COLORS := {
	"common": Color(0.7, 0.7, 0.7),
	"uncommon": Color(0.3, 0.9, 0.3),
	"rare": Color(0.3, 0.5, 1.0),
	"epic": Color(0.7, 0.3, 0.9),
	"legendary": Color(1.0, 0.7, 0.2),
	"unique": Color(1.0, 0.4, 0.4),
}

const STAT_COLORS := {
	"positive": Color(0.3, 0.9, 0.3),
	"negative": Color(0.9, 0.3, 0.3),
	"neutral": Color(0.8, 0.8, 0.8),
}

# Animation
var anim := UIAnimations.new()
var current_tween: Tween = null
var is_showing := false

# UI Elements
var background: PanelContainer
var content_container: VBoxContainer
var header_container: HBoxContainer
var icon_rect: TextureRect
var title_label: Label
var subtitle_label: Label
var divider: ColorRect
var stats_container: VBoxContainer
var description_label: RichTextLabel
var footer_label: Label


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_build_ui()
	_apply_style()


func _build_ui() -> void:
	# Main background panel
	background = PanelContainer.new()
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	# Content container
	content_container = VBoxContainer.new()
	content_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content_container.add_theme_constant_override("separation", GAP)
	background.add_child(content_container)

	# Header (icon + title)
	header_container = HBoxContainer.new()
	header_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header_container.add_theme_constant_override("separation", 8)
	content_container.add_child(header_container)

	icon_rect = TextureRect.new()
	icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_rect.custom_minimum_size = Vector2(32, 32)
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_rect.visible = false
	header_container.add_child(icon_rect)

	var title_vbox := VBoxContainer.new()
	title_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_vbox.add_theme_constant_override("separation", 2)
	header_container.add_child(title_vbox)

	title_label = Label.new()
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_label.add_theme_font_size_override("font_size", 16)
	title_vbox.add_child(title_label)

	subtitle_label = Label.new()
	subtitle_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	subtitle_label.add_theme_font_size_override("font_size", 12)
	subtitle_label.modulate = Color(0.6, 0.6, 0.6)
	subtitle_label.visible = false
	title_vbox.add_child(subtitle_label)

	# Divider
	divider = ColorRect.new()
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	divider.custom_minimum_size = Vector2(0, 1)
	divider.color = Color(0.3, 0.3, 0.3)
	divider.visible = false
	content_container.add_child(divider)

	# Stats container
	stats_container = VBoxContainer.new()
	stats_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stats_container.add_theme_constant_override("separation", 4)
	stats_container.visible = false
	content_container.add_child(stats_container)

	# Description
	description_label = RichTextLabel.new()
	description_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	description_label.bbcode_enabled = true
	description_label.fit_content = true
	description_label.scroll_active = false
	description_label.add_theme_font_size_override("normal_font_size", 13)
	description_label.visible = false
	content_container.add_child(description_label)

	# Footer
	footer_label = Label.new()
	footer_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	footer_label.add_theme_font_size_override("font_size", 11)
	footer_label.modulate = Color(0.5, 0.5, 0.5)
	footer_label.visible = false
	content_container.add_child(footer_label)


func _apply_style() -> void:
	# Create stylebox for background
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.12, 0.95)
	style.set_corner_radius_all(6)
	style.set_border_width_all(1)
	style.border_color = Color(0.3, 0.3, 0.35)
	style.set_content_margin_all(PADDING)

	# Add subtle shadow
	style.shadow_color = Color(0, 0, 0, 0.4)
	style.shadow_size = 4
	style.shadow_offset = Vector2(2, 2)

	background.add_theme_stylebox_override("panel", style)


# ============================================
# ITEM TOOLTIP
# ============================================

## Show tooltip for an item
func show_item(item_data: Dictionary, anchor_pos: Vector2, compare_data: Dictionary = {}) -> void:
	_reset_content()

	# Title and rarity
	var item_name: String = item_data.get("name", "Unknown Item")
	var rarity: String = item_data.get("rarity", "common")

	title_label.text = item_name
	title_label.add_theme_color_override("font_color", RARITY_COLORS.get(rarity, Color.WHITE))

	# Subtitle (item type)
	var item_type: String = item_data.get("type", "")
	if item_type != "":
		subtitle_label.text = item_type.capitalize()
		subtitle_label.visible = true

	# Icon
	var icon_path: String = item_data.get("icon", "")
	if icon_path != "" and ResourceLoader.exists(icon_path):
		icon_rect.texture = load(icon_path)
		icon_rect.visible = true

	# Stats
	var stats: Dictionary = item_data.get("stats", {})
	if not stats.is_empty():
		divider.visible = true
		stats_container.visible = true
		_build_stats(stats, compare_data.get("stats", {}))

	# Description
	var description: String = item_data.get("description", "")
	if description != "":
		description_label.text = _format_description(description)
		description_label.visible = true

	# Footer (weight, value, etc.)
	var weight: float = item_data.get("weight", 0)
	var value: int = item_data.get("value", 0)
	if weight > 0 or value > 0:
		var footer_parts: Array[String] = []
		if weight > 0:
			footer_parts.append("%.1f kg" % weight)
		if value > 0:
			footer_parts.append("%d gold" % value)
		footer_label.text = " | ".join(footer_parts)
		footer_label.visible = true

	_show_at_position(anchor_pos)


# ============================================
# ATTRIBUTE TOOLTIP
# ============================================

## Show tooltip for an attribute
func show_attribute(attr_info: Dictionary, anchor_pos: Vector2) -> void:
	_reset_content()

	# Title
	var attr_name: String = attr_info.get("name", "Unknown")
	var attr_color: Color = attr_info.get("color", Color.WHITE)

	title_label.text = attr_name
	title_label.add_theme_color_override("font_color", attr_color)

	# Subtitle (abbreviation)
	var abbrev: String = attr_info.get("abbrev", "")
	if abbrev != "":
		subtitle_label.text = abbrev
		subtitle_label.visible = true

	# Icon
	var icon_path: String = attr_info.get("icon", "")
	if icon_path != "" and ResourceLoader.exists(icon_path):
		icon_rect.texture = load(icon_path)
		icon_rect.visible = true

	# Stats breakdown
	divider.visible = true
	stats_container.visible = true

	_add_stat_row("Base", str(attr_info.get("base", 10)), STAT_COLORS.neutral)

	var equip_bonus: int = attr_info.get("equipment_bonus", 0)
	if equip_bonus != 0:
		var color := STAT_COLORS.positive if equip_bonus > 0 else STAT_COLORS.negative
		_add_stat_row("Equipment", "%+d" % equip_bonus, color)

	var buff_bonus: int = attr_info.get("buff_bonus", 0)
	if buff_bonus != 0:
		var color := STAT_COLORS.positive if buff_bonus > 0 else STAT_COLORS.negative
		_add_stat_row("Buffs", "%+d" % buff_bonus, color)

	var perk_bonus: int = attr_info.get("perk_bonus", 0)
	if perk_bonus != 0:
		var color := STAT_COLORS.positive if perk_bonus > 0 else STAT_COLORS.negative
		_add_stat_row("Perks", "%+d" % perk_bonus, color)

	# Total
	_add_stat_row("Total", str(attr_info.get("total", 10)), attr_color, true)

	# Description
	var description: String = attr_info.get("description", "")
	if description != "":
		description_label.text = description
		description_label.visible = true

	_show_at_position(anchor_pos)


# ============================================
# BUFF TOOLTIP
# ============================================

## Show tooltip for an active buff
func show_buff(buff_data: Dictionary, anchor_pos: Vector2) -> void:
	_reset_content()

	var buff_name: String = buff_data.get("name", "Unknown Buff")
	var is_debuff: bool = buff_data.get("amount", 0) < 0

	title_label.text = buff_name
	title_label.add_theme_color_override("font_color",
		STAT_COLORS.negative if is_debuff else STAT_COLORS.positive)

	# Effect
	var attribute: String = buff_data.get("attribute", "")
	var amount: int = buff_data.get("amount", 0)
	if attribute != "" and amount != 0:
		divider.visible = true
		stats_container.visible = true
		var color := STAT_COLORS.positive if amount > 0 else STAT_COLORS.negative
		_add_stat_row(attribute.capitalize(), "%+d" % amount, color)

	# Duration
	var remaining: float = buff_data.get("remaining_time", 0)
	if remaining > 0:
		footer_label.text = "%.1fs remaining" % remaining
		footer_label.visible = true

	# Description
	var description: String = buff_data.get("description", "")
	if description != "":
		description_label.text = description
		description_label.visible = true

	_show_at_position(anchor_pos)


# ============================================
# EQUIPMENT SLOT TOOLTIP
# ============================================

## Show tooltip for an equipment slot
func show_equipment_slot(slot_data: Dictionary, anchor_pos: Vector2) -> void:
	_reset_content()

	var slot_name: String = slot_data.get("slot_name", "Slot")
	var has_item: bool = slot_data.get("has_item", false)

	title_label.text = slot_name.capitalize()

	if has_item:
		var item_data: Dictionary = slot_data.get("item", {})
		show_item(item_data, anchor_pos)
		return

	# Empty slot
	subtitle_label.text = "Empty"
	subtitle_label.visible = true

	var accepted_types: Array = slot_data.get("accepted_types", [])
	if not accepted_types.is_empty():
		description_label.text = "Accepts: " + ", ".join(accepted_types)
		description_label.visible = true

	_show_at_position(anchor_pos)


# ============================================
# SIMPLE TOOLTIP
# ============================================

## Show a simple text tooltip
func show_simple(text: String, anchor_pos: Vector2, title: String = "") -> void:
	_reset_content()

	if title != "":
		title_label.text = title
	else:
		title_label.text = text
		_show_at_position(anchor_pos)
		return

	description_label.text = text
	description_label.visible = true

	_show_at_position(anchor_pos)


# ============================================
# HIDE
# ============================================

## Hide the tooltip with animation
func hide_tooltip() -> void:
	if not is_showing:
		return

	is_showing = false

	if current_tween and current_tween.is_valid():
		current_tween.kill()

	current_tween = anim.tooltip_hide(self)
	current_tween.finished.connect(func(): hidden.emit(), CONNECT_ONE_SHOT)


# ============================================
# HELPERS
# ============================================

func _reset_content() -> void:
	# Clear previous content
	icon_rect.visible = false
	subtitle_label.visible = false
	divider.visible = false
	stats_container.visible = false
	description_label.visible = false
	footer_label.visible = false

	# Clear stats container
	for child in stats_container.get_children():
		child.queue_free()

	title_label.text = ""
	subtitle_label.text = ""
	description_label.text = ""
	footer_label.text = ""

	title_label.remove_theme_color_override("font_color")


func _build_stats(stats: Dictionary, compare_stats: Dictionary) -> void:
	for stat_name in stats:
		var value = stats[stat_name]
		var color := STAT_COLORS.neutral

		# Check for comparison
		if stat_name in compare_stats:
			var compare_value = compare_stats[stat_name]
			if value > compare_value:
				color = STAT_COLORS.positive
			elif value < compare_value:
				color = STAT_COLORS.negative

		var value_str: String
		if value is float:
			if value >= 1.0 and value < 2.0:
				value_str = "+%.0f%%" % ((value - 1.0) * 100)
			else:
				value_str = "%.1f" % value
		else:
			value_str = str(value)

		_add_stat_row(_format_stat_name(stat_name), value_str, color)


func _add_stat_row(name: String, value: String, color: Color, bold: bool = false) -> void:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var name_label := Label.new()
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.text = name
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_size_override("font_size", 13)
	if bold:
		name_label.add_theme_color_override("font_color", color)
	row.add_child(name_label)

	var value_label := Label.new()
	value_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	value_label.text = value
	value_label.add_theme_color_override("font_color", color)
	value_label.add_theme_font_size_override("font_size", 13)
	row.add_child(value_label)

	stats_container.add_child(row)


func _format_stat_name(stat_name: String) -> String:
	# Convert snake_case to Title Case
	return stat_name.replace("_", " ").capitalize()


func _format_description(text: String) -> String:
	# Simple markdown-lite formatting
	# *text* -> italic
	# **text** -> bold
	# [color]text[/color] -> colored

	var formatted := text
	# Already supports BBCode via RichTextLabel
	return formatted


func _show_at_position(anchor_pos: Vector2) -> void:
	# Wait for layout to settle
	await get_tree().process_frame

	# Get viewport size
	var viewport_size := get_viewport_rect().size

	# Determine best position to stay on screen
	var tooltip_size := background.size
	var final_pos := anchor_pos

	# Prefer showing above and to the right of cursor
	final_pos.x += 16
	final_pos.y -= tooltip_size.y + 8

	# Keep on screen horizontally
	if final_pos.x + tooltip_size.x > viewport_size.x - PADDING:
		final_pos.x = anchor_pos.x - tooltip_size.x - 16

	# Keep on screen vertically
	if final_pos.y < PADDING:
		final_pos.y = anchor_pos.y + 24  # Show below instead

	if final_pos.y + tooltip_size.y > viewport_size.y - PADDING:
		final_pos.y = viewport_size.y - tooltip_size.y - PADDING

	position = final_pos

	# Kill any existing animation
	if current_tween and current_tween.is_valid():
		current_tween.kill()

	# Show with animation
	is_showing = true
	modulate.a = 0.0
	scale = Vector2(0.95, 0.95)
	visible = true

	current_tween = create_tween()
	current_tween.set_parallel(true)
	current_tween.tween_property(self, "modulate:a", 1.0, 0.12)
	current_tween.tween_property(self, "scale", Vector2.ONE, 0.15)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	current_tween.finished.connect(func(): shown.emit(), CONNECT_ONE_SHOT)


## Static helper to create and show a tooltip
static func create_for(parent: Control) -> AnimatedTooltip:
	var tooltip := AnimatedTooltip.new()
	parent.add_child(tooltip)
	return tooltip
