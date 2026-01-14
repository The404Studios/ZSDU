extends Control
class_name MarketScreen
## MarketScreen - Player-to-player marketplace
##
## Features:
## - Browse listings by category/search
## - Create listings (escrow-based)
## - Buy from other players
## - View and cancel your own listings

signal screen_closed
signal navigate_to_stash
signal navigate_to_traders

# Search/filter state
var search_query: String = ""
var selected_category: String = ""
var listings: Array = []
var my_listings: Array = []

# UI references
var search_input: LineEdit = null
var category_dropdown: OptionButton = null
var listings_panel: VBoxContainer = null
var my_listings_panel: VBoxContainer = null
var create_listing_panel: Control = null
var gold_label: Label = null
var status_label: Label = null

# Listing creation state
var listing_item_iid: String = ""
var listing_price_input: SpinBox = null

const CATEGORIES := ["", "weapon", "armor", "ammo", "medical", "misc"]


func _ready() -> void:
	_create_ui()

	EconomyService.stash_updated.connect(_on_stash_updated)
	EconomyService.operation_failed.connect(_on_operation_failed)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			close()


func open() -> void:
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_search_market()
	_load_my_listings()
	_update_gold_display()


func close() -> void:
	visible = false
	screen_closed.emit()


func _create_ui() -> void:
	# Background
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.08, 0.1, 0.98)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Main container
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 30)
	margin.add_theme_constant_override("margin_top", 30)
	margin.add_theme_constant_override("margin_right", 30)
	margin.add_theme_constant_override("margin_bottom", 30)
	add_child(margin)

	var main_vbox := VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 15)
	margin.add_child(main_vbox)

	# Header
	var header := _create_header()
	main_vbox.add_child(header)

	# Content area
	var content_hbox := HBoxContainer.new()
	content_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_hbox.add_theme_constant_override("separation", 20)
	main_vbox.add_child(content_hbox)

	# Left - Market listings
	var listings_panel_container := _create_listings_panel()
	listings_panel_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	listings_panel_container.size_flags_stretch_ratio = 2.0
	content_hbox.add_child(listings_panel_container)

	# Right - My listings & Create listing
	var right_panel := _create_right_panel()
	right_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_panel.size_flags_stretch_ratio = 1.0
	content_hbox.add_child(right_panel)

	# Footer
	var footer := _create_footer()
	main_vbox.add_child(footer)


func _create_header() -> Control:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 20)

	# Title
	var title := Label.new()
	title.text = "PLAYER MARKET"
	title.add_theme_font_size_override("font_size", 24)
	hbox.add_child(title)

	# Spacer
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(spacer)

	# Gold display
	gold_label = Label.new()
	gold_label.text = "Gold: 0"
	gold_label.add_theme_font_size_override("font_size", 18)
	gold_label.add_theme_color_override("font_color", Color.GOLD)
	hbox.add_child(gold_label)

	return hbox


func _create_listings_panel() -> Control:
	var panel := PanelContainer.new()

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	# Search bar
	var search_hbox := HBoxContainer.new()
	search_hbox.add_theme_constant_override("separation", 10)
	vbox.add_child(search_hbox)

	search_input = LineEdit.new()
	search_input.placeholder_text = "Search items..."
	search_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search_input.text_submitted.connect(func(_text): _search_market())
	search_hbox.add_child(search_input)

	category_dropdown = OptionButton.new()
	category_dropdown.add_item("All Categories", 0)
	category_dropdown.add_item("Weapons", 1)
	category_dropdown.add_item("Armor", 2)
	category_dropdown.add_item("Ammo", 3)
	category_dropdown.add_item("Medical", 4)
	category_dropdown.add_item("Misc", 5)
	category_dropdown.item_selected.connect(_on_category_selected)
	search_hbox.add_child(category_dropdown)

	var search_btn := Button.new()
	search_btn.text = "Search"
	search_btn.pressed.connect(_search_market)
	search_hbox.add_child(search_btn)

	var sep := HSeparator.new()
	vbox.add_child(sep)

	# Listings header
	var header := HBoxContainer.new()
	vbox.add_child(header)

	var item_col := Label.new()
	item_col.text = "Item"
	item_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	item_col.add_theme_font_size_override("font_size", 12)
	header.add_child(item_col)

	var seller_col := Label.new()
	seller_col.text = "Seller"
	seller_col.custom_minimum_size = Vector2(100, 0)
	seller_col.add_theme_font_size_override("font_size", 12)
	header.add_child(seller_col)

	var price_col := Label.new()
	price_col.text = "Price"
	price_col.custom_minimum_size = Vector2(80, 0)
	price_col.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	price_col.add_theme_font_size_override("font_size", 12)
	header.add_child(price_col)

	var action_col := Label.new()
	action_col.text = ""
	action_col.custom_minimum_size = Vector2(60, 0)
	header.add_child(action_col)

	# Scrollable listings
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	listings_panel = VBoxContainer.new()
	listings_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(listings_panel)

	return panel


func _create_right_panel() -> Control:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 15)

	# My listings section
	var my_panel := PanelContainer.new()
	my_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(my_panel)

	var my_vbox := VBoxContainer.new()
	my_vbox.add_theme_constant_override("separation", 8)
	my_panel.add_child(my_vbox)

	var my_title := Label.new()
	my_title.text = "MY LISTINGS"
	my_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	my_title.add_theme_font_size_override("font_size", 16)
	my_vbox.add_child(my_title)

	var sep1 := HSeparator.new()
	my_vbox.add_child(sep1)

	var my_scroll := ScrollContainer.new()
	my_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	my_vbox.add_child(my_scroll)

	my_listings_panel = VBoxContainer.new()
	my_listings_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	my_scroll.add_child(my_listings_panel)

	# Create listing section
	create_listing_panel = _create_listing_creator()
	vbox.add_child(create_listing_panel)

	return vbox


func _create_listing_creator() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 200)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "CREATE LISTING"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 16)
	vbox.add_child(title)

	var sep := HSeparator.new()
	vbox.add_child(sep)

	# Item selection
	var item_label := Label.new()
	item_label.text = "Select item from stash:"
	item_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(item_label)

	var item_dropdown := OptionButton.new()
	item_dropdown.name = "ItemDropdown"
	item_dropdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	item_dropdown.item_selected.connect(_on_listing_item_selected)
	vbox.add_child(item_dropdown)

	# Price input
	var price_hbox := HBoxContainer.new()
	vbox.add_child(price_hbox)

	var price_label := Label.new()
	price_label.text = "Price:"
	price_hbox.add_child(price_label)

	listing_price_input = SpinBox.new()
	listing_price_input.min_value = 1
	listing_price_input.max_value = 999999
	listing_price_input.value = 100
	listing_price_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	price_hbox.add_child(listing_price_input)

	# Create button
	var create_btn := Button.new()
	create_btn.text = "List for Sale"
	create_btn.custom_minimum_size = Vector2(0, 40)
	create_btn.pressed.connect(_create_listing)
	vbox.add_child(create_btn)

	return panel


func _create_footer() -> Control:
	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 20)

	status_label = Label.new()
	status_label.text = ""
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(status_label)

	var stash_btn := Button.new()
	stash_btn.text = "Stash"
	stash_btn.custom_minimum_size = Vector2(100, 40)
	stash_btn.pressed.connect(func(): navigate_to_stash.emit())
	hbox.add_child(stash_btn)

	var traders_btn := Button.new()
	traders_btn.text = "Traders"
	traders_btn.custom_minimum_size = Vector2(100, 40)
	traders_btn.pressed.connect(func(): navigate_to_traders.emit())
	hbox.add_child(traders_btn)

	var close_btn := Button.new()
	close_btn.text = "Close [ESC]"
	close_btn.custom_minimum_size = Vector2(100, 40)
	close_btn.pressed.connect(close)
	hbox.add_child(close_btn)

	return hbox


func _search_market() -> void:
	status_label.text = "Searching..."

	search_query = search_input.text if search_input else ""
	listings = await EconomyService.search_market(search_query, selected_category)

	_refresh_listings()
	status_label.text = "Found %d listings" % listings.size()


func _on_category_selected(index: int) -> void:
	selected_category = CATEGORIES[index] if index < CATEGORIES.size() else ""
	_search_market()


func _refresh_listings() -> void:
	# Clear existing
	for child in listings_panel.get_children():
		child.queue_free()

	if listings.is_empty():
		var empty := Label.new()
		empty.text = "No listings found"
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		listings_panel.add_child(empty)
		return

	for listing in listings:
		var row := _create_listing_row(listing, false)
		listings_panel.add_child(row)


func _create_listing_row(listing: Dictionary, is_mine: bool) -> Control:
	var hbox := HBoxContainer.new()
	hbox.custom_minimum_size = Vector2(0, 45)
	hbox.add_theme_constant_override("separation", 10)

	# Item name
	var name_label := Label.new()
	name_label.text = listing.get("item_name", listing.get("def_id", "Unknown"))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_size_override("font_size", 13)
	hbox.add_child(name_label)

	if not is_mine:
		# Seller name
		var seller_label := Label.new()
		seller_label.text = listing.get("seller_name", "Unknown")
		seller_label.custom_minimum_size = Vector2(100, 0)
		seller_label.add_theme_font_size_override("font_size", 12)
		seller_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		hbox.add_child(seller_label)

	# Price
	var price_label := Label.new()
	price_label.text = "%d" % listing.get("price", 0)
	price_label.custom_minimum_size = Vector2(80, 0)
	price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	price_label.add_theme_color_override("font_color", Color.GOLD)
	hbox.add_child(price_label)

	# Action button
	var action_btn := Button.new()
	if is_mine:
		action_btn.text = "Cancel"
		action_btn.custom_minimum_size = Vector2(70, 35)
		action_btn.pressed.connect(func(): _cancel_listing(listing.get("listing_id", "")))
	else:
		action_btn.text = "Buy"
		action_btn.custom_minimum_size = Vector2(60, 35)
		action_btn.disabled = EconomyService.get_gold() < listing.get("price", 0)
		action_btn.pressed.connect(func(): _buy_listing(listing.get("listing_id", "")))
	hbox.add_child(action_btn)

	return hbox


func _load_my_listings() -> void:
	my_listings = await EconomyService.get_my_listings()
	_refresh_my_listings()
	_refresh_item_dropdown()


func _refresh_my_listings() -> void:
	# Clear existing
	for child in my_listings_panel.get_children():
		child.queue_free()

	if my_listings.is_empty():
		var empty := Label.new()
		empty.text = "No active listings"
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		my_listings_panel.add_child(empty)
		return

	for listing in my_listings:
		var row := _create_listing_row(listing, true)
		my_listings_panel.add_child(row)


func _refresh_item_dropdown() -> void:
	var dropdown := create_listing_panel.get_node_or_null("ItemDropdown") as OptionButton
	if not dropdown:
		# Find it in children
		for child in create_listing_panel.get_children():
			if child is VBoxContainer:
				for subchild in child.get_children():
					if subchild is OptionButton:
						dropdown = subchild
						break

	if not dropdown:
		return

	dropdown.clear()
	dropdown.add_item("-- Select Item --", 0)

	var items: Array = EconomyService.get_all_items()
	var index := 1
	for item in items:
		var iid: String = item.get("iid", "")

		# Skip locked items
		if EconomyService.is_item_locked(iid):
			continue

		var def_id: String = item.get("def_id", item.get("defId", ""))
		var item_def: Dictionary = EconomyService.get_item_def(def_id)
		var name_text: String = item_def.get("name", def_id)

		dropdown.add_item(name_text, index)
		dropdown.set_item_metadata(index, iid)
		index += 1

	listing_item_iid = ""


func _on_listing_item_selected(index: int) -> void:
	var dropdown := create_listing_panel.get_node_or_null("ItemDropdown") as OptionButton
	if not dropdown:
		for child in create_listing_panel.get_children():
			if child is VBoxContainer:
				for subchild in child.get_children():
					if subchild is OptionButton:
						dropdown = subchild
						break

	if dropdown and index > 0:
		listing_item_iid = dropdown.get_item_metadata(index)

		# Set suggested price based on item value
		var item: Dictionary = EconomyService.get_item(listing_item_iid)
		var def_id: String = item.get("def_id", item.get("defId", ""))
		var item_def: Dictionary = EconomyService.get_item_def(def_id)
		var base_value: int = item_def.get("base_value", item_def.get("baseValue", 100))

		if listing_price_input:
			listing_price_input.value = base_value
	else:
		listing_item_iid = ""


func _create_listing() -> void:
	if listing_item_iid == "":
		status_label.text = "Select an item first!"
		status_label.add_theme_color_override("font_color", Color.RED)
		return

	var price := int(listing_price_input.value) if listing_price_input else 100

	if price <= 0:
		status_label.text = "Invalid price!"
		status_label.add_theme_color_override("font_color", Color.RED)
		return

	status_label.text = "Creating listing..."
	var success := await EconomyService.create_listing(listing_item_iid, price)

	if success:
		status_label.text = "Listing created!"
		status_label.add_theme_color_override("font_color", Color.GREEN)
		listing_item_iid = ""
		_load_my_listings()
	else:
		status_label.text = "Failed to create listing"
		status_label.add_theme_color_override("font_color", Color.RED)


func _buy_listing(listing_id: String) -> void:
	if listing_id == "":
		return

	status_label.text = "Purchasing..."
	var success := await EconomyService.buy_listing(listing_id)

	if success:
		status_label.text = "Purchase successful!"
		status_label.add_theme_color_override("font_color", Color.GREEN)
		_search_market()
		_update_gold_display()
	else:
		status_label.text = "Purchase failed"
		status_label.add_theme_color_override("font_color", Color.RED)


func _cancel_listing(listing_id: String) -> void:
	if listing_id == "":
		return

	status_label.text = "Cancelling..."
	var success := await EconomyService.cancel_listing(listing_id)

	if success:
		status_label.text = "Listing cancelled"
		status_label.add_theme_color_override("font_color", Color.GREEN)
		_load_my_listings()
	else:
		status_label.text = "Failed to cancel"
		status_label.add_theme_color_override("font_color", Color.RED)


func _update_gold_display() -> void:
	if gold_label:
		gold_label.text = "Gold: %d" % EconomyService.get_gold()


func _on_stash_updated(_stash: Dictionary, _items: Array, _wallet: Dictionary) -> void:
	_update_gold_display()
	_refresh_item_dropdown()


func _on_operation_failed(error: String) -> void:
	status_label.text = "Error: %s" % error
	status_label.add_theme_color_override("font_color", Color.RED)
