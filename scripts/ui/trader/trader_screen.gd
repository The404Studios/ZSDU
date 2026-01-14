extends Control
class_name TraderScreen
## TraderScreen - NPC Trader interface
##
## Buy and sell items with NPC traders.
## Each trader has:
## - Reputation level (affects prices and available items)
## - Catalog of items for sale
## - Buy-back option for player items

signal screen_closed
signal navigate_to_stash
signal navigate_to_market

# Trader data
var traders: Array = []
var selected_trader: Dictionary = {}
var catalog: Array = []

# UI References
var trader_list: VBoxContainer = null
var catalog_panel: VBoxContainer = null
var player_items_panel: VBoxContainer = null
var trader_info_label: Label = null
var gold_label: Label = null
var status_label: Label = null


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
	_load_traders()
	_update_gold_display()


func close() -> void:
	visible = false
	screen_closed.emit()


func _create_ui() -> void:
	# Background
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.08, 0.1, 0.98)
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

	var main_hbox := HBoxContainer.new()
	main_hbox.add_theme_constant_override("separation", 20)
	margin.add_child(main_hbox)

	# Left panel - Trader list
	var left_panel := _create_trader_list_panel()
	left_panel.custom_minimum_size = Vector2(200, 0)
	main_hbox.add_child(left_panel)

	# Middle panel - Trader catalog
	var middle_panel := _create_catalog_panel()
	middle_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	middle_panel.size_flags_stretch_ratio = 1.0
	main_hbox.add_child(middle_panel)

	# Right panel - Player items to sell
	var right_panel := _create_sell_panel()
	right_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_panel.size_flags_stretch_ratio = 1.0
	main_hbox.add_child(right_panel)


func _create_trader_list_panel() -> Control:
	var panel := PanelContainer.new()

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "TRADERS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	vbox.add_child(title)

	var sep := HSeparator.new()
	vbox.add_child(sep)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	trader_list = VBoxContainer.new()
	trader_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(trader_list)

	# Navigation buttons
	var sep2 := HSeparator.new()
	vbox.add_child(sep2)

	var stash_btn := Button.new()
	stash_btn.text = "Back to Stash"
	stash_btn.custom_minimum_size = Vector2(0, 35)
	stash_btn.pressed.connect(func(): navigate_to_stash.emit())
	vbox.add_child(stash_btn)

	var market_btn := Button.new()
	market_btn.text = "Go to Market"
	market_btn.custom_minimum_size = Vector2(0, 35)
	market_btn.pressed.connect(func(): navigate_to_market.emit())
	vbox.add_child(market_btn)

	var close_btn := Button.new()
	close_btn.text = "Close [ESC]"
	close_btn.custom_minimum_size = Vector2(0, 35)
	close_btn.pressed.connect(close)
	vbox.add_child(close_btn)

	return panel


func _create_catalog_panel() -> Control:
	var panel := PanelContainer.new()

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	# Header
	var header_hbox := HBoxContainer.new()
	vbox.add_child(header_hbox)

	var title := Label.new()
	title.text = "CATALOG"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 18)
	header_hbox.add_child(title)

	gold_label = Label.new()
	gold_label.text = "Gold: 0"
	gold_label.add_theme_color_override("font_color", Color.GOLD)
	header_hbox.add_child(gold_label)

	# Trader info
	trader_info_label = Label.new()
	trader_info_label.text = "Select a trader"
	trader_info_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	vbox.add_child(trader_info_label)

	var sep := HSeparator.new()
	vbox.add_child(sep)

	# Catalog scroll
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	catalog_panel = VBoxContainer.new()
	catalog_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(catalog_panel)

	# Status
	status_label = Label.new()
	status_label.text = ""
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(status_label)

	return panel


func _create_sell_panel() -> Control:
	var panel := PanelContainer.new()

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "SELL ITEMS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	vbox.add_child(title)

	var info := Label.new()
	info.text = "Your items to sell"
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.add_theme_font_size_override("font_size", 12)
	info.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	vbox.add_child(info)

	var sep := HSeparator.new()
	vbox.add_child(sep)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	player_items_panel = VBoxContainer.new()
	player_items_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(player_items_panel)

	return panel


func _load_traders() -> void:
	traders = await EconomyService.get_traders()

	# Clear trader list
	for child in trader_list.get_children():
		child.queue_free()

	# Add default traders if backend returns empty
	if traders.is_empty():
		traders = _get_default_traders()

	# Create trader buttons
	for trader in traders:
		var btn := Button.new()
		btn.text = trader.get("name", "Unknown Trader")
		btn.custom_minimum_size = Vector2(0, 50)
		btn.pressed.connect(func(): _select_trader(trader))
		trader_list.add_child(btn)

	# Select first trader
	if not traders.is_empty():
		_select_trader(traders[0])


func _get_default_traders() -> Array:
	# Default traders for offline/testing
	return [
		{
			"id": "merchant_general",
			"name": "General Store",
			"description": "Basic supplies and tools",
			"reputation": 1.0,
			"catalog": [
				{"offer_id": "nails_pack", "def_id": "nails", "name": "Nails x50", "price": 100, "stock": -1},
				{"offer_id": "bandage", "def_id": "bandage", "name": "Bandage", "price": 50, "stock": 10},
				{"offer_id": "medkit", "def_id": "medkit", "name": "Medkit", "price": 200, "stock": 5},
			]
		},
		{
			"id": "merchant_weapons",
			"name": "Weapons Dealer",
			"description": "Firearms and ammunition",
			"reputation": 1.0,
			"catalog": [
				{"offer_id": "pistol_basic", "def_id": "pistol", "name": "9mm Pistol", "price": 500, "stock": 3},
				{"offer_id": "shotgun", "def_id": "shotgun", "name": "Pump Shotgun", "price": 1200, "stock": 2},
				{"offer_id": "ammo_9mm", "def_id": "ammo_9mm", "name": "9mm Ammo x30", "price": 75, "stock": -1},
				{"offer_id": "ammo_shells", "def_id": "ammo_shells", "name": "Shotgun Shells x8", "price": 100, "stock": -1},
			]
		},
		{
			"id": "merchant_armor",
			"name": "Armor Smith",
			"description": "Protection and tactical gear",
			"reputation": 1.0,
			"catalog": [
				{"offer_id": "helmet_basic", "def_id": "helmet_basic", "name": "Basic Helmet", "price": 300, "stock": 5},
				{"offer_id": "vest_light", "def_id": "vest_light", "name": "Light Vest", "price": 450, "stock": 3},
				{"offer_id": "rig_basic", "def_id": "rig_basic", "name": "Basic Rig", "price": 250, "stock": 4},
			]
		}
	]


func _select_trader(trader: Dictionary) -> void:
	selected_trader = trader

	# Update trader info
	trader_info_label.text = "%s - %s" % [
		trader.get("name", "Unknown"),
		trader.get("description", "")
	]

	# Load catalog
	var trader_id: String = trader.get("id", "")
	if trader_id != "":
		var catalog_data := await EconomyService.get_trader_catalog(trader_id)
		catalog = catalog_data.get("catalog", trader.get("catalog", []))
	else:
		catalog = trader.get("catalog", [])

	_refresh_catalog()
	_refresh_player_items()


func _refresh_catalog() -> void:
	# Clear catalog
	for child in catalog_panel.get_children():
		child.queue_free()

	if catalog.is_empty():
		var empty := Label.new()
		empty.text = "No items available"
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		catalog_panel.add_child(empty)
		return

	for offer in catalog:
		var item_row := _create_catalog_item(offer)
		catalog_panel.add_child(item_row)


func _create_catalog_item(offer: Dictionary) -> Control:
	var hbox := HBoxContainer.new()
	hbox.custom_minimum_size = Vector2(0, 50)
	hbox.add_theme_constant_override("separation", 10)

	# Item info
	var info_vbox := VBoxContainer.new()
	info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(info_vbox)

	var name_label := Label.new()
	name_label.text = offer.get("name", offer.get("def_id", "Unknown"))
	name_label.add_theme_font_size_override("font_size", 14)
	info_vbox.add_child(name_label)

	var stock: int = offer.get("stock", -1)
	var stock_text := "Unlimited" if stock < 0 else "Stock: %d" % stock
	var details := Label.new()
	details.text = stock_text
	details.add_theme_font_size_override("font_size", 11)
	details.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	info_vbox.add_child(details)

	# Price
	var price_label := Label.new()
	price_label.text = "%d" % offer.get("price", 0)
	price_label.add_theme_color_override("font_color", Color.GOLD)
	price_label.custom_minimum_size = Vector2(80, 0)
	price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hbox.add_child(price_label)

	# Buy button
	var buy_btn := Button.new()
	buy_btn.text = "Buy"
	buy_btn.custom_minimum_size = Vector2(60, 40)
	buy_btn.disabled = stock == 0 or EconomyService.get_gold() < offer.get("price", 0)
	buy_btn.pressed.connect(func(): _buy_item(offer))
	hbox.add_child(buy_btn)

	return hbox


func _refresh_player_items() -> void:
	# Clear panel
	for child in player_items_panel.get_children():
		child.queue_free()

	var items: Array = EconomyService.get_all_items()

	if items.is_empty():
		var empty := Label.new()
		empty.text = "No items to sell"
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		player_items_panel.add_child(empty)
		return

	for item in items:
		var iid: String = item.get("iid", "")

		# Skip locked items
		if EconomyService.is_item_locked(iid):
			continue

		var def_id: String = item.get("def_id", item.get("defId", ""))
		var item_def: Dictionary = EconomyService.get_item_def(def_id)

		var sell_row := _create_sell_item(iid, item, item_def)
		player_items_panel.add_child(sell_row)


func _create_sell_item(iid: String, item_data: Dictionary, item_def: Dictionary) -> Control:
	var hbox := HBoxContainer.new()
	hbox.custom_minimum_size = Vector2(0, 45)
	hbox.add_theme_constant_override("separation", 10)

	# Item info
	var info_vbox := VBoxContainer.new()
	info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(info_vbox)

	var name_label := Label.new()
	name_label.text = item_def.get("name", iid)
	name_label.add_theme_font_size_override("font_size", 13)
	info_vbox.add_child(name_label)

	var stack: int = item_data.get("stack", 1)
	if stack > 1:
		var stack_label := Label.new()
		stack_label.text = "x%d" % stack
		stack_label.add_theme_font_size_override("font_size", 11)
		stack_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		info_vbox.add_child(stack_label)

	# Sell value (traders typically pay 50% of base value)
	var base_value: int = item_def.get("base_value", item_def.get("baseValue", 10))
	var sell_value := int(base_value * 0.5 * stack)

	var value_label := Label.new()
	value_label.text = "%d" % sell_value
	value_label.add_theme_color_override("font_color", Color(0.8, 0.7, 0.3))
	value_label.custom_minimum_size = Vector2(60, 0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hbox.add_child(value_label)

	# Sell button
	var sell_btn := Button.new()
	sell_btn.text = "Sell"
	sell_btn.custom_minimum_size = Vector2(55, 35)
	sell_btn.pressed.connect(func(): _sell_item(iid))
	hbox.add_child(sell_btn)

	return hbox


func _buy_item(offer: Dictionary) -> void:
	var trader_id: String = selected_trader.get("id", "")
	var offer_id: String = offer.get("offer_id", "")
	var price: int = offer.get("price", 0)

	if EconomyService.get_gold() < price:
		status_label.text = "Not enough gold!"
		status_label.add_theme_color_override("font_color", Color.RED)
		return

	status_label.text = "Buying..."
	var success := await EconomyService.buy_from_trader(trader_id, offer_id)

	if success:
		status_label.text = "Purchased %s!" % offer.get("name", "item")
		status_label.add_theme_color_override("font_color", Color.GREEN)
		_update_gold_display()
		_refresh_catalog()
		_refresh_player_items()
	else:
		status_label.text = "Purchase failed"
		status_label.add_theme_color_override("font_color", Color.RED)


func _sell_item(iid: String) -> void:
	var trader_id: String = selected_trader.get("id", "")

	status_label.text = "Selling..."
	var success := await EconomyService.sell_to_trader(trader_id, iid)

	if success:
		status_label.text = "Item sold!"
		status_label.add_theme_color_override("font_color", Color.GREEN)
		_update_gold_display()
		_refresh_player_items()
	else:
		status_label.text = "Sale failed"
		status_label.add_theme_color_override("font_color", Color.RED)


func _update_gold_display() -> void:
	if gold_label:
		gold_label.text = "Gold: %d" % EconomyService.get_gold()


func _on_stash_updated(_stash: Dictionary, _items: Array, _wallet: Dictionary) -> void:
	_update_gold_display()
	_refresh_player_items()
	_refresh_catalog()


func _on_operation_failed(error: String) -> void:
	status_label.text = "Error: %s" % error
	status_label.add_theme_color_override("font_color", Color.RED)
