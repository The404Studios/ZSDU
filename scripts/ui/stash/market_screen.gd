extends Control
class_name MarketScreen
## MarketScreen - Player-to-player flea market
##
## Features:
## - Search/browse listings
## - Buy listings (escrow-based)
## - Create listings (items go to escrow)
## - View/cancel own listings

signal screen_closed
signal navigate_to_stash
signal navigate_to_traders

@onready var search_input: LineEdit = $MarginContainer/HBoxContainer/BrowsePanel/SearchContainer/SearchInput
@onready var category_option: OptionButton = $MarginContainer/HBoxContainer/BrowsePanel/SearchContainer/CategoryOption
@onready var listings_container: VBoxContainer = $MarginContainer/HBoxContainer/BrowsePanel/ScrollContainer/ListingsContainer
@onready var gold_label: Label = $MarginContainer/HBoxContainer/SellPanel/WalletContainer/GoldLabel
@onready var my_listings_list: ItemList = $MarginContainer/HBoxContainer/SellPanel/MyListingsList
@onready var sell_item_list: ItemList = $MarginContainer/HBoxContainer/SellPanel/SellItemList
@onready var price_input: SpinBox = $MarginContainer/HBoxContainer/SellPanel/PriceContainer/PriceInput
@onready var list_button: Button = $MarginContainer/HBoxContainer/SellPanel/ListButton
@onready var status_label: Label = $MarginContainer/HBoxContainer/SellPanel/StatusLabel

var market_listings: Array = []
var my_listings: Array = []
var sellable_items: Array = []
var selected_sell_item_index: int = -1


func _ready() -> void:
	EconomyService.stash_updated.connect(_on_stash_updated)
	EconomyService.gold_changed.connect(_on_gold_changed)
	EconomyService.operation_failed.connect(_on_operation_failed)

	# Setup category dropdown
	if category_option:
		category_option.add_item("All", 0)
		category_option.add_item("Weapons", 1)
		category_option.add_item("Ammo", 2)
		category_option.add_item("Armor", 3)
		category_option.add_item("Medical", 4)
		category_option.add_item("Tools", 5)
		category_option.add_item("Misc", 6)
		category_option.item_selected.connect(_on_category_changed)

	if search_input:
		search_input.text_submitted.connect(_on_search_submitted)

	if sell_item_list:
		sell_item_list.item_selected.connect(_on_sell_item_selected)

	if my_listings_list:
		my_listings_list.item_selected.connect(_on_my_listing_selected)


func open() -> void:
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await _refresh_all()


func close() -> void:
	visible = false
	screen_closed.emit()


func _refresh_all() -> void:
	_update_gold_display()
	await _search_market()
	await _load_my_listings()
	_update_sellable_items()


func _search_market(query: String = "", category: String = "") -> void:
	market_listings = await EconomyService.search_market(query, category)

	# Clear existing listings
	for child in listings_container.get_children():
		child.queue_free()

	# Populate listings
	for listing in market_listings:
		_create_listing_row(listing)


func _create_listing_row(listing: Dictionary) -> void:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 50
	listings_container.add_child(row)

	# Item info
	var item: Dictionary = listing.get("item", {})
	var item_def: Dictionary = listing.get("item_def", {})
	var item_name: String = item_def.get("name", listing.get("def_id", "Unknown"))

	var name_label := Label.new()
	name_label.text = item_name
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)

	# Stack
	var stack: int = item.get("stack", 1)
	if stack > 1:
		var stack_label := Label.new()
		stack_label.text = "x%d" % stack
		stack_label.custom_minimum_size.x = 40
		row.add_child(stack_label)

	# Seller
	var seller_name: String = listing.get("seller_name", "Unknown")
	var seller_label := Label.new()
	seller_label.text = seller_name.substr(0, 10)
	seller_label.custom_minimum_size.x = 80
	seller_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	row.add_child(seller_label)

	# Price
	var price: int = listing.get("price", 0)
	var price_label := Label.new()
	price_label.text = "%dg" % price
	price_label.custom_minimum_size.x = 100
	price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(price_label)

	# Buy button
	var buy_btn := Button.new()
	buy_btn.text = "Buy"
	buy_btn.custom_minimum_size.x = 60
	buy_btn.disabled = price > EconomyService.get_gold()
	buy_btn.pressed.connect(func(): _buy_listing(listing))
	row.add_child(buy_btn)


func _buy_listing(listing: Dictionary) -> void:
	var listing_id: String = listing.get("listing_id", "")
	var price: int = listing.get("price", 0)

	if EconomyService.get_gold() < price:
		status_label.text = "Not enough gold"
		status_label.add_theme_color_override("font_color", Color.RED)
		return

	status_label.text = "Purchasing..."

	var success := await EconomyService.buy_listing(listing_id)

	if success:
		var item_def: Dictionary = listing.get("item_def", {})
		status_label.text = "Bought: %s" % item_def.get("name", "item")
		status_label.add_theme_color_override("font_color", Color.GREEN)
		await _search_market()  # Refresh listings
	else:
		status_label.text = "Purchase failed"
		status_label.add_theme_color_override("font_color", Color.RED)


func _load_my_listings() -> void:
	my_listings = await EconomyService.get_my_listings()

	my_listings_list.clear()
	for listing in my_listings:
		var item_def: Dictionary = listing.get("item_def", {})
		var item_name: String = item_def.get("name", listing.get("def_id", "Unknown"))
		var price: int = listing.get("price", 0)
		my_listings_list.add_item("%s - %dg" % [item_name, price])


func _on_my_listing_selected(index: int) -> void:
	if index < 0 or index >= my_listings.size():
		return

	# Show cancel confirmation
	var listing: Dictionary = my_listings[index]
	_cancel_listing(listing)


func _cancel_listing(listing: Dictionary) -> void:
	var listing_id: String = listing.get("listing_id", "")
	var item_def: Dictionary = listing.get("item_def", {})

	var confirm := ConfirmationDialog.new()
	confirm.dialog_text = "Cancel listing for %s?" % item_def.get("name", "item")
	confirm.confirmed.connect(func():
		_do_cancel_listing(listing_id)
	)
	add_child(confirm)
	confirm.popup_centered()


func _do_cancel_listing(listing_id: String) -> void:
	status_label.text = "Canceling..."

	var success := await EconomyService.cancel_listing(listing_id)

	if success:
		status_label.text = "Listing canceled"
		status_label.add_theme_color_override("font_color", Color.GREEN)
		await _load_my_listings()
	else:
		status_label.text = "Cancel failed"
		status_label.add_theme_color_override("font_color", Color.RED)


func _update_sellable_items() -> void:
	sell_item_list.clear()
	sellable_items.clear()

	var all_items: Array = EconomyService.get_all_items()
	for item in all_items:
		var iid: String = item.get("iid", "")
		if EconomyService.is_item_locked(iid):
			continue

		var def_id: String = item.get("def_id", item.get("defId", ""))
		var item_def: Dictionary = EconomyService.get_item_def(def_id)
		var base_value: int = item_def.get("base_value", item_def.get("baseValue", 100))

		sellable_items.append({
			"iid": iid,
			"name": item_def.get("name", def_id),
			"base_value": base_value,
			"stack": item.get("stack", 1)
		})

		var display_text: String = item_def.get("name", def_id)
		if item.get("stack", 1) > 1:
			display_text += " (x%d)" % item.get("stack", 1)
		sell_item_list.add_item(display_text)


func _on_sell_item_selected(index: int) -> void:
	selected_sell_item_index = index
	if index >= 0 and index < sellable_items.size():
		var item_info: Dictionary = sellable_items[index]
		# Suggest price based on base value
		price_input.value = item_info.get("base_value", 100)
		list_button.disabled = false
	else:
		list_button.disabled = true


func _create_listing() -> void:
	if selected_sell_item_index < 0 or selected_sell_item_index >= sellable_items.size():
		status_label.text = "Select an item to list"
		return

	var item_info: Dictionary = sellable_items[selected_sell_item_index]
	var iid: String = item_info.get("iid", "")
	var price: int = int(price_input.value)

	if price < 1:
		status_label.text = "Price must be at least 1 gold"
		status_label.add_theme_color_override("font_color", Color.RED)
		return

	status_label.text = "Creating listing..."

	var success := await EconomyService.create_listing(iid, price, 24)

	if success:
		status_label.text = "Listed: %s for %dg" % [item_info.get("name", "item"), price]
		status_label.add_theme_color_override("font_color", Color.GREEN)
		selected_sell_item_index = -1
		list_button.disabled = true
		_update_sellable_items()
		await _load_my_listings()
	else:
		status_label.text = "Listing failed"
		status_label.add_theme_color_override("font_color", Color.RED)


func _on_search_submitted(query: String) -> void:
	var category := _get_selected_category()
	await _search_market(query, category)


func _on_category_changed(_index: int) -> void:
	var category := _get_selected_category()
	var query: String = search_input.text if search_input else ""
	await _search_market(query, category)


func _get_selected_category() -> String:
	if not category_option:
		return ""

	match category_option.selected:
		1: return "weapon"
		2: return "ammo"
		3: return "armor"
		4: return "med"
		5: return "tool"
		6: return "misc"
		_: return ""


func _update_gold_display() -> void:
	if gold_label:
		gold_label.text = "%d" % EconomyService.get_gold()


func _on_stash_updated(_stash: Dictionary, _items: Array, _wallet: Dictionary) -> void:
	_update_sellable_items()


func _on_gold_changed(new_amount: int) -> void:
	if gold_label:
		gold_label.text = "%d" % new_amount


func _on_operation_failed(error: String) -> void:
	status_label.text = "Error: %s" % error
	status_label.add_theme_color_override("font_color", Color.RED)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			close()


# Button handlers
func _on_search_button_pressed() -> void:
	var query: String = search_input.text if search_input else ""
	var category := _get_selected_category()
	await _search_market(query, category)


func _on_refresh_button_pressed() -> void:
	await _refresh_all()


func _on_list_button_pressed() -> void:
	_create_listing()


func _on_stash_button_pressed() -> void:
	navigate_to_stash.emit()


func _on_traders_button_pressed() -> void:
	navigate_to_traders.emit()


func _on_close_button_pressed() -> void:
	close()
