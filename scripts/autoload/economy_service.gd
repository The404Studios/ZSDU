extends Node
## EconomyService - Client-side economy integration
##
## Handles:
## - Authentication and character management
## - Stash inventory (grid-based, Tarkov-style)
## - Trader interactions (buy/sell with reputation)
## - Market operations (escrow-based player market)
## - Raid loadout locking and commit
##
## All operations go through backend - client never directly mutates state.

signal logged_in(character_id: String, name: String)
signal login_failed(error: String)
signal stash_updated(stash: Dictionary, items: Array, wallet: Dictionary)
signal operation_failed(error: String)
signal raid_prepared(raid_id: String, locked_iids: Array)
signal raid_committed(results: Dictionary)
signal gold_changed(new_amount: int)

# Character state
var character_id: String = ""
var character_name: String = ""
var session_token: String = ""
var is_logged_in: bool = false

# Stash cache (updated from backend)
var stash_data: Dictionary = {}  # { w, h, placements }
var items_cache: Dictionary = {}  # iid -> item instance
var wallet: Dictionary = { "gold": 0 }
var stash_version: int = 0

# Item definitions (static, loaded once)
var item_defs: Dictionary = {}  # def_id -> item def

# Active raid (if any)
var current_raid_id: String = ""
var locked_iids: Array = []


func _ready() -> void:
	# Load item definitions on startup
	_load_item_defs()


# ============================================
# AUTHENTICATION
# ============================================

## Login (creates character if doesn't exist)
func login(username: String) -> void:
	print("[Economy] Logging in as: %s" % username)

	var result := await _api_request("/auth/login", {
		"username": username
	})

	if result.has("error"):
		login_failed.emit(result.error)
		return

	session_token = result.get("token", "")
	character_id = result.get("character_id", "")
	character_name = result.get("name", username)
	is_logged_in = true

	print("[Economy] Logged in: %s (%s)" % [character_name, character_id])
	logged_in.emit(character_id, character_name)

	# Fetch stash after login
	await refresh_stash()


## Logout
func logout() -> void:
	character_id = ""
	character_name = ""
	session_token = ""
	is_logged_in = false
	stash_data = {}
	items_cache = {}
	wallet = { "gold": 0 }
	current_raid_id = ""
	locked_iids = []


# ============================================
# STASH OPERATIONS
# ============================================

## Refresh stash from backend
func refresh_stash() -> void:
	if character_id == "":
		return

	var result := await _api_get("/stash?character_id=%s" % character_id)

	if result.has("error"):
		operation_failed.emit(result.error)
		return

	_apply_stash_snapshot(result)


## Move item in stash
func move_item(iid: String, to_x: int, to_y: int, rotation: int = 0) -> bool:
	var op_id := _generate_op_id()

	var result := await _api_request("/stash/move", {
		"character_id": character_id,
		"op_id": op_id,
		"iid": iid,
		"to_x": to_x,
		"to_y": to_y,
		"rotation": rotation
	})

	if result.has("error"):
		operation_failed.emit(result.error)
		return false

	_apply_stash_delta(result)
	return true


## Discard item
func discard_item(iid: String) -> bool:
	var op_id := _generate_op_id()

	var result := await _api_request("/stash/discard", {
		"character_id": character_id,
		"op_id": op_id,
		"iid": iid
	})

	if result.has("error"):
		operation_failed.emit(result.error)
		return false

	_apply_stash_delta(result)
	return true


## Split stack
func split_stack(iid: String, split_amount: int, to_x: int, to_y: int) -> bool:
	var op_id := _generate_op_id()

	var result := await _api_request("/stash/split", {
		"character_id": character_id,
		"op_id": op_id,
		"iid": iid,
		"split_amount": split_amount,
		"to_x": to_x,
		"to_y": to_y
	})

	if result.has("error"):
		operation_failed.emit(result.error)
		return false

	_apply_stash_delta(result)
	return true


# ============================================
# RAID OPERATIONS
# ============================================

## Prepare for raid (lock loadout items)
func prepare_raid(lobby_id: String, loadout: Dictionary) -> bool:
	var op_id := _generate_op_id()

	var result := await _api_request("/raid/prepare", {
		"character_id": character_id,
		"op_id": op_id,
		"lobby_id": lobby_id,
		"loadout": loadout
	})

	if result.has("error"):
		operation_failed.emit(result.error)
		return false

	current_raid_id = result.get("raid_id", "")
	locked_iids = result.get("locked_iids", [])

	# Update item flags locally
	for iid in locked_iids:
		if iid in items_cache:
			items_cache[iid]["flags"]["in_raid"] = true

	raid_prepared.emit(current_raid_id, locked_iids)
	return true


## Cancel raid (before it starts)
func cancel_raid() -> bool:
	if current_raid_id == "":
		return false

	var result := await _api_request("/raid/cancel", {
		"character_id": character_id,
		"raid_id": current_raid_id
	})

	if result.has("error"):
		operation_failed.emit(result.error)
		return false

	# Unlock items locally
	for iid in locked_iids:
		if iid in items_cache:
			items_cache[iid]["flags"]["in_raid"] = false

	current_raid_id = ""
	locked_iids = []
	return true


## Get current raid ID (for match server)
func get_raid_id() -> String:
	return current_raid_id


# ============================================
# TRADER OPERATIONS
# ============================================

## Get list of traders
func get_traders() -> Array:
	var result := await _api_get("/traders?character_id=%s" % character_id)

	if result.has("error"):
		return []

	return result.get("traders", [])


## Get trader catalog
func get_trader_catalog(trader_id: String) -> Dictionary:
	var result := await _api_get("/trader/catalog?character_id=%s&trader_id=%s" % [character_id, trader_id])

	if result.has("error"):
		operation_failed.emit(result.error)
		return {}

	return result


## Buy from trader
func buy_from_trader(trader_id: String, offer_id: String, quantity: int = 1) -> bool:
	var op_id := _generate_op_id()

	var result := await _api_request("/trader/buy", {
		"character_id": character_id,
		"op_id": op_id,
		"trader_id": trader_id,
		"offer_id": offer_id,
		"quantity": quantity
	})

	if result.has("error"):
		operation_failed.emit(result.error)
		return false

	_apply_stash_delta(result)
	return true


## Sell to trader
func sell_to_trader(trader_id: String, iid: String, quantity: int = -1) -> bool:
	var op_id := _generate_op_id()

	var data := {
		"character_id": character_id,
		"op_id": op_id,
		"trader_id": trader_id,
		"iid": iid
	}
	if quantity > 0:
		data["quantity"] = quantity

	var result := await _api_request("/trader/sell", data)

	if result.has("error"):
		operation_failed.emit(result.error)
		return false

	_apply_stash_delta(result)
	return true


# ============================================
# MARKET OPERATIONS
# ============================================

## Search market
func search_market(query: String = "", category: String = "", min_price: int = -1, max_price: int = -1) -> Array:
	var url := "/market/search?"
	if query != "":
		url += "query=%s&" % query.uri_encode()
	if category != "":
		url += "category=%s&" % category
	if min_price >= 0:
		url += "min_price=%d&" % min_price
	if max_price >= 0:
		url += "max_price=%d&" % max_price

	var result := await _api_get(url)

	if result.has("error"):
		return []

	return result.get("listings", [])


## Create market listing
func create_listing(iid: String, price: int, duration_hours: int = 24) -> bool:
	var op_id := _generate_op_id()

	var result := await _api_request("/market/list", {
		"character_id": character_id,
		"op_id": op_id,
		"iid": iid,
		"price": price,
		"duration_hours": duration_hours
	})

	if result.has("error"):
		operation_failed.emit(result.error)
		return false

	_apply_stash_delta(result)
	return true


## Buy market listing
func buy_listing(listing_id: String) -> bool:
	var op_id := _generate_op_id()

	var result := await _api_request("/market/buy", {
		"character_id": character_id,
		"op_id": op_id,
		"listing_id": listing_id
	})

	if result.has("error"):
		operation_failed.emit(result.error)
		return false

	_apply_stash_delta(result)
	return true


## Cancel listing
func cancel_listing(listing_id: String) -> bool:
	var result := await _api_request("/market/cancel", {
		"character_id": character_id,
		"listing_id": listing_id
	})

	if result.has("error"):
		operation_failed.emit(result.error)
		return false

	_apply_stash_delta(result)
	return true


## Get my listings
func get_my_listings() -> Array:
	var result := await _api_get("/market/my_listings?character_id=%s" % character_id)

	if result.has("error"):
		return []

	return result.get("listings", [])


# ============================================
# ITEM DEFINITIONS
# ============================================

## Get item definition by ID
func get_item_def(def_id: String) -> Dictionary:
	if def_id in item_defs:
		return item_defs[def_id]
	return {}


## Get item by instance ID
func get_item(iid: String) -> Dictionary:
	if iid in items_cache:
		return items_cache[iid]
	return {}


## Load item definitions from backend
func _load_item_defs() -> void:
	var result := await _api_get("/items/defs")

	if result.has("error"):
		push_warning("[Economy] Failed to load item defs: %s" % result.error)
		return

	var items: Array = result.get("items", [])
	for item in items:
		var def_id: String = item.get("defId", item.get("def_id", ""))
		if def_id != "":
			item_defs[def_id] = item

	print("[Economy] Loaded %d item definitions" % item_defs.size())


# ============================================
# HELPERS
# ============================================

func _apply_stash_snapshot(result: Dictionary) -> void:
	stash_data = result.get("stash", {})
	wallet = result.get("wallet", { "gold": 0 })
	stash_version = result.get("version", 0)

	# Build items cache
	items_cache.clear()
	var items: Array = result.get("items", [])
	for item in items:
		var iid: String = item.get("iid", "")
		if iid != "":
			items_cache[iid] = item

	stash_updated.emit(stash_data, items, wallet)
	gold_changed.emit(wallet.get("gold", 0))


func _apply_stash_delta(result: Dictionary) -> void:
	var delta: Dictionary = result.get("stash_delta", {})

	# Handle added items
	var added: Array = delta.get("added", [])
	for item in added:
		var iid: String = item.get("iid", "")
		if iid != "":
			items_cache[iid] = item

	# Handle removed items
	var removed: Array = delta.get("removed", [])
	for iid in removed:
		items_cache.erase(iid)
		# Also remove from placements
		var placements: Array = stash_data.get("placements", [])
		for i in range(placements.size() - 1, -1, -1):
			if placements[i].get("iid") == iid:
				placements.remove_at(i)

	# Handle moved items
	var moved: Array = delta.get("moved", [])
	for placement in moved:
		var iid: String = placement.get("iid", "")
		# Update or add placement
		var found := false
		var placements: Array = stash_data.get("placements", [])
		for i in range(placements.size()):
			if placements[i].get("iid") == iid:
				placements[i] = placement
				found = true
				break
		if not found:
			placements.append(placement)

	# Update wallet
	if result.has("wallet"):
		var old_gold: int = wallet.get("gold", 0)
		wallet = result.wallet
		if wallet.get("gold", 0) != old_gold:
			gold_changed.emit(wallet.get("gold", 0))

	# Update version
	if result.has("version"):
		stash_version = result.version

	stash_updated.emit(stash_data, items_cache.values(), wallet)


func _generate_op_id() -> String:
	return "op_%d_%d" % [Time.get_unix_time_from_system(), randi()]


func _api_request(endpoint: String, data: Dictionary) -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = 15.0
	add_child(http)

	var url := BackendConfig.get_http_url() + endpoint
	var headers := ["Content-Type: application/json"]

	# Add session token if authenticated
	if session_token != "":
		headers.append("Authorization: Bearer %s" % session_token)

	var body := JSON.stringify(data)

	var error := http.request(url, headers, HTTPClient.METHOD_POST, body)
	if error != OK:
		http.queue_free()
		return { "error": "Request failed" }

	var result = await http.request_completed
	http.queue_free()

	if result[0] != HTTPRequest.RESULT_SUCCESS:
		return { "error": "HTTP error" }

	# Handle authentication errors
	if result[1] == 401:
		is_logged_in = false
		session_token = ""
		return { "error": "Session expired - please login again" }

	var json := JSON.new()
	if json.parse(result[3].get_string_from_utf8()) != OK:
		return { "error": "Invalid JSON" }

	return json.data if json.data is Dictionary else { "error": "Invalid response" }


func _api_get(endpoint: String) -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = 15.0
	add_child(http)

	var url := BackendConfig.get_http_url() + endpoint
	var headers: PackedStringArray = []

	# Add session token if authenticated
	if session_token != "":
		headers.append("Authorization: Bearer %s" % session_token)

	var error := http.request(url, headers, HTTPClient.METHOD_GET)
	if error != OK:
		http.queue_free()
		return { "error": "Request failed" }

	var result = await http.request_completed
	http.queue_free()

	if result[0] != HTTPRequest.RESULT_SUCCESS:
		return { "error": "HTTP error" }

	# Handle authentication errors
	if result[1] == 401:
		is_logged_in = false
		session_token = ""
		return { "error": "Session expired - please login again" }

	var json := JSON.new()
	if json.parse(result[3].get_string_from_utf8()) != OK:
		return { "error": "Invalid JSON" }

	return json.data if json.data is Dictionary else { "error": "Invalid response" }


# ============================================
# PUBLIC GETTERS
# ============================================

func get_gold() -> int:
	return wallet.get("gold", 0)


func get_stash_width() -> int:
	return stash_data.get("w", 10)


func get_stash_height() -> int:
	return stash_data.get("h", 40)


func get_placements() -> Array:
	return stash_data.get("placements", [])


func get_all_items() -> Array:
	return items_cache.values()


func is_item_locked(iid: String) -> bool:
	if iid in items_cache:
		var flags: Dictionary = items_cache[iid].get("flags", {})
		return flags.get("in_raid", false) or flags.get("in_escrow", false)
	return false
