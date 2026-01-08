extends Control
class_name TraderScreen
## TraderScreen - NPC trader interface
##
## Features:
## - List of traders with reputation
## - Buy items from trader catalog
## - Sell items to traders
## - Price scaling based on reputation

signal screen_closed
signal navigate_to_stash
signal navigate_to_market

@onready var trader_list: ItemList = $MarginContainer/HBoxContainer/TraderPanel/TraderList
@onready var trader_name_label: Label = $MarginContainer/HBoxContainer/CatalogPanel/TraderHeader/TraderName
@onready var trader_rep_label: Label = $MarginContainer/HBoxContainer/CatalogPanel/TraderHeader/RepLabel
@onready var catalog_container: VBoxContainer = $MarginContainer/HBoxContainer/CatalogPanel/ScrollContainer/CatalogContainer
@onready var gold_label: Label = $MarginContainer/HBoxContainer/SellPanel/WalletContainer/GoldLabel
@onready var sell_list: ItemList = $MarginContainer/HBoxContainer/SellPanel/SellList
@onready var status_label: Label = $MarginContainer/HBoxContainer/SellPanel/StatusLabel

var traders: Array = []
var current_trader_id: String = ""
var current_catalog: Dictionary = {}
var sellable_items: Array = []  # Items player can sell


func _ready() -> void:
	EconomyService.stash_updated.connect(_on_stash_updated)
	EconomyService.gold_changed.connect(_on_gold_changed)
	EconomyService.operation_failed.connect(_on_operation_failed)

	if trader_list:
		trader_list.item_selected.connect(_on_trader_selected)

	if sell_list:
		sell_list.item_selected.connect(_on_sell_item_selected)


func open() -> void:
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await _load_traders()
	_update_gold_display()
	_update_sell_list()


func close() -> void:
	visible = false
	screen_closed.emit()


func _load_traders() -> void:
	traders = await EconomyService.get_traders()

	trader_list.clear()
	for trader in traders:
		var name_text: String = trader.get("name", "Unknown")
		var rep: float = trader.get("rep", 0)
		var rep_text := " (%.0f%%)" % (rep * 100)
		trader_list.add_item(name_text + rep_text)

	if traders.size() > 0:
		trader_list.select(0)
		_on_trader_selected(0)


func _on_trader_selected(index: int) -> void:
	if index < 0 or index >= traders.size():
		return

	var trader: Dictionary = traders[index]
	current_trader_id = trader.get("trader_id", "")

	trader_name_label.text = trader.get("name", "Unknown")
	var rep: float = trader.get("rep", 0)
	trader_rep_label.text = "Rep: %.0f%%" % (rep * 100)

	# Load catalog
	await _load_catalog()


func _load_catalog() -> void:
	if current_trader_id == "":
		return

	current_catalog = await EconomyService.get_trader_catalog(current_trader_id)

	# Clear existing catalog
	for child in catalog_container.get_children():
		child.queue_free()

	# Populate catalog
	var offers: Array = current_catalog.get("offers", [])
	for offer in offers:
		_create_offer_row(offer)


func _create_offer_row(offer: Dictionary) -> void:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 40
	catalog_container.add_child(row)

	# Item info
	var item: Dictionary = offer.get("item", {})
	var item_name: String = item.get("name", offer.get("def_id", "Unknown"))

	var name_label := Label.new()
	name_label.text = item_name
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)

	# Stock
	var stock: int = offer.get("stock", -1)
	var stock_label := Label.new()
	if stock == -1:
		stock_label.text = "∞"
	elif stock == 0:
		stock_label.text = "OUT"
		stock_label.add_theme_color_override("font_color", Color.RED)
	else:
		stock_label.text = "x%d" % stock
	stock_label.custom_minimum_size.x = 50
	row.add_child(stock_label)

	# Price
	var price: int = offer.get("price", 0)
	var price_label := Label.new()
	price_label.text = "%dg" % price
	price_label.custom_minimum_size.x = 80
	price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(price_label)

	# Buy button
	var buy_btn := Button.new()
	buy_btn.text = "Buy"
	buy_btn.custom_minimum_size.x = 60
	buy_btn.disabled = stock == 0 or price > EconomyService.get_gold()
	buy_btn.pressed.connect(func(): _buy_item(offer))
	row.add_child(buy_btn)


func _buy_item(offer: Dictionary) -> void:
	var offer_id: String = offer.get("offer_id", "")
	var price: int = offer.get("price", 0)

	if EconomyService.get_gold() < price:
		status_label.text = "Not enough gold"
		status_label.add_theme_color_override("font_color", Color.RED)
		return

	status_label.text = "Buying..."

	var success := await EconomyService.buy_from_trader(current_trader_id, offer_id, 1)

	if success:
		var item: Dictionary = offer.get("item", {})
		status_label.text = "Bought: %s" % item.get("name", "item")
		status_label.add_theme_color_override("font_color", Color.GREEN)
		await _load_catalog()  # Refresh catalog to update stock
	else:
		status_label.text = "Purchase failed"
		status_label.add_theme_color_override("font_color", Color.RED)


func _update_sell_list() -> void:
	sell_list.clear()
	sellable_items.clear()

	# Get all items that can be sold to current trader
	var accepted_cats: Array = current_catalog.get("accepted_categories", [])
	var buyback_rate: float = current_catalog.get("buyback_rate", 0.25)

	var all_items: Array = EconomyService.get_all_items()
	for item in all_items:
		if EconomyService.is_item_locked(item.get("iid", "")):
			continue

		var def_id: String = item.get("def_id", item.get("defId", ""))
		var item_def: Dictionary = EconomyService.get_item_def(def_id)
		var category: String = item_def.get("category", "misc")

		# Check if trader accepts this category
		var accepts := accepted_cats.is_empty() or "all" in accepted_cats or category in accepted_cats
		if not accepts:
			continue

		# Calculate sell price
		var base_value: int = item_def.get("base_value", item_def.get("baseValue", 0))
		var durability: float = item.get("durability", 1.0)
		var stack: int = item.get("stack", 1)
		var sell_price: int = int(base_value * buyback_rate * durability) * stack

		sellable_items.append({
			"iid": item.get("iid", ""),
			"name": item_def.get("name", def_id),
			"price": sell_price,
			"stack": stack
		})

		var display_text := "%s - %dg" % [item_def.get("name", def_id), sell_price]
		if stack > 1:
			display_text = "%s (x%d) - %dg" % [item_def.get("name", def_id), stack, sell_price]
		sell_list.add_item(display_text)


func _on_sell_item_selected(index: int) -> void:
	if index < 0 or index >= sellable_items.size():
		return

	var item_info: Dictionary = sellable_items[index]
	_sell_item(item_info)


func _sell_item(item_info: Dictionary) -> void:
	var iid: String = item_info.get("iid", "")

	status_label.text = "Selling..."

	var success := await EconomyService.sell_to_trader(current_trader_id, iid)

	if success:
		status_label.text = "Sold: %s for %dg" % [item_info.get("name", "item"), item_info.get("price", 0)]
		status_label.add_theme_color_override("font_color", Color.GREEN)
		_update_sell_list()
	else:
		status_label.text = "Sale failed"
		status_label.add_theme_color_override("font_color", Color.RED)


func _update_gold_display() -> void:
	if gold_label:
		gold_label.text = "%d" % EconomyService.get_gold()


func _on_stash_updated(_stash: Dictionary, _items: Array, _wallet: Dictionary) -> void:
	_update_sell_list()


func _on_gold_changed(new_amount: int) -> void:
	if gold_label:
		gold_label.text = "%d" % new_amount
	# Refresh catalog to update buy button states
	await _load_catalog()


func _on_operation_failed(error: String) -> void:
	status_label.text = "Error: %s" % error
	status_label.add_theme_color_override("font_color", Color.RED)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			close()


# Button handlers
func _on_stash_button_pressed() -> void:
	navigate_to_stash.emit()


func _on_market_button_pressed() -> void:
	navigate_to_market.emit()


func _on_close_button_pressed() -> void:
	close()
