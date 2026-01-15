extends Node
## RaidManager - Server-side raid outcome management
##
## Handles:
## - Tracking players' raid IDs when they join
## - Commit raid outcomes on extraction, death, or disconnect
## - Provisional loot tracking during raid
## - HMAC-SHA256 signed requests to backend (via CryptoUtils)
##
## Security:
## - All backend requests are HMAC-SHA256 signed
## - Timestamp-based replay protection (5-minute window)
## - Server ID included for audit trail
##
## Only active on the server (authority).

signal raid_committed(raid_id: String, success: bool)
signal player_extracted(peer_id: int, raid_id: String)
signal player_died(peer_id: int, raid_id: String)

# Raid tracking
# peer_id -> { raid_id, character_id, loadout_iids, provisional_loot, extracted, dead }
var active_raids: Dictionary = {}

# Match tracking
var current_match_id: String = ""


func _ready() -> void:
	# Connect to network signals
	if NetworkManager:
		NetworkManager.player_left.connect(_on_player_disconnected)

	# Connect to game state for player death
	if GameState:
		GameState.player_died.connect(_on_player_died)


func set_match_id(match_id: String) -> void:
	current_match_id = match_id
	print("[RaidManager] Match ID: %s" % match_id)


# ============================================
# RAID REGISTRATION (called when player joins)
# ============================================

## Register a player's raid (server receives this from client on connect)
func register_raid(peer_id: int, raid_id: String, character_id: String, loadout_items: Array) -> void:
	if not NetworkManager.is_authority():
		return

	# Extract IIDs for backend commit tracking
	var loadout_iids: Array = []
	for item in loadout_items:
		loadout_iids.append(item.get("iid", ""))

	active_raids[peer_id] = {
		"raid_id": raid_id,
		"character_id": character_id,
		"loadout_iids": loadout_iids,
		"loadout_items": loadout_items,  # Full item data for server-side equipping
		"provisional_loot": [],  # Items found during raid
		"extracted": false,
		"dead": false,
		"committed": false
	}

	print("[RaidManager] Registered raid for peer %d: raid_id=%s, character=%s, items=%d" % [
		peer_id, raid_id.substr(0, 8), character_id.substr(0, 8), loadout_items.size()
	])


## Client RPC to register raid with server
@rpc("any_peer", "reliable")
func rpc_register_raid(raid_id: String, character_id: String, loadout_items: Array) -> void:
	if not NetworkManager.is_authority():
		return

	var peer_id := multiplayer.get_remote_sender_id()
	register_raid(peer_id, raid_id, character_id, loadout_items)


# ============================================
# LOOT TRACKING (during raid)
# ============================================

## Add provisional loot (picked up during raid, before extract)
func add_provisional_loot(peer_id: int, def_id: String, stack: int = 1, durability: float = 1.0, mods: Array = []) -> void:
	if not NetworkManager.is_authority():
		return

	if peer_id not in active_raids:
		return

	active_raids[peer_id].provisional_loot.append({
		"def_id": def_id,
		"stack": stack,
		"durability": durability,
		"mods": mods
	})

	print("[RaidManager] Peer %d found loot: %s x%d" % [peer_id, def_id, stack])


## Server RPC for loot pickup confirmation
@rpc("authority", "call_local", "reliable")
func rpc_confirm_loot(_peer_id: int, _def_id: String, _stack: int) -> void:
	# Client receives confirmation
	pass


# ============================================
# EXTRACTION (player reaches extraction zone)
# ============================================

## Handle player extraction (server-side)
func on_player_extract(peer_id: int) -> void:
	if not NetworkManager.is_authority():
		return

	if peer_id not in active_raids:
		print("[RaidManager] Player %d extracted but has no active raid" % peer_id)
		return

	var raid := active_raids[peer_id] as Dictionary
	if raid.committed:
		return  # Already committed

	raid.extracted = true
	print("[RaidManager] Player %d extracted!" % peer_id)

	# Commit the raid
	await _commit_raid(peer_id, true)
	player_extracted.emit(peer_id, raid.raid_id)


## Server RPC called when player reaches extraction
@rpc("any_peer", "reliable")
func rpc_request_extract() -> void:
	if not NetworkManager.is_authority():
		return

	var peer_id := multiplayer.get_remote_sender_id()
	on_player_extract(peer_id)


# ============================================
# DEATH (player dies during raid)
# ============================================

func _on_player_died(peer_id: int) -> void:
	if not NetworkManager.is_authority():
		return

	if peer_id not in active_raids:
		return

	var raid := active_raids[peer_id] as Dictionary
	if raid.committed:
		return

	raid.dead = true
	print("[RaidManager] Player %d died during raid" % peer_id)

	# Commit the raid (death = lose loadout, lose provisional loot)
	await _commit_raid(peer_id, false)
	player_died.emit(peer_id, raid.raid_id)


# ============================================
# DISCONNECT (player disconnects = death)
# ============================================

func _on_player_disconnected(peer_id: int) -> void:
	if not NetworkManager.is_authority():
		return

	if peer_id not in active_raids:
		return

	var raid := active_raids[peer_id] as Dictionary
	if raid.committed:
		active_raids.erase(peer_id)
		return

	raid.dead = true
	print("[RaidManager] Player %d disconnected (treated as death)" % peer_id)

	# Commit the raid as death
	await _commit_raid(peer_id, false)
	active_raids.erase(peer_id)


# ============================================
# COMMIT RAID (send to backend)
# ============================================

func _commit_raid(peer_id: int, survived: bool) -> void:
	if peer_id not in active_raids:
		return

	var raid := active_raids[peer_id] as Dictionary
	if raid.committed:
		return

	raid.committed = true

	var raid_id: String = raid.raid_id
	var character_id: String = raid.character_id

	# Build outcome
	var outcome := {
		"character_id": character_id,
		"survived": survived,
		"provisional_loot": raid.provisional_loot if survived else []  # No loot if dead
	}

	# Build all outcomes (for batch commit)
	var outcomes := [outcome]

	# Send signed request to backend
	await _send_signed_commit_request(raid_id, current_match_id, outcomes)


func _send_signed_commit_request(raid_id: String, match_id: String, outcomes: Array) -> void:
	# Create HMAC-signed request using CryptoUtils
	var signed_request := CryptoUtils.sign_raid_commit(raid_id, match_id, outcomes)

	var http := HTTPRequest.new()
	http.timeout = 15.0
	add_child(http)

	var url := BackendConfig.get_http_url() + "/server/raid/commit"
	var headers := ["Content-Type: application/json"]

	# Signed request format:
	# {
	#   "payload": { raid_id, match_id, outcomes },
	#   "signature": "hmac-sha256-hex",
	#   "timestamp": unix_timestamp,
	#   "server_id": "unique-server-id"
	# }

	print("[RaidManager] POST /server/raid/commit (raid=%s, match=%s, server=%s)" % [
		raid_id.substr(0, 8),
		match_id.substr(0, 8),
		signed_request.server_id.substr(0, 8)
	])

	var error := http.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(signed_request))
	if error != OK:
		push_error("[RaidManager] Commit request failed: %s" % error_string(error))
		raid_committed.emit(raid_id, false)
		http.queue_free()
		return

	var result = await http.request_completed
	http.queue_free()

	if result[0] != HTTPRequest.RESULT_SUCCESS:
		push_error("[RaidManager] Commit HTTP error: %d" % result[0])
		raid_committed.emit(raid_id, false)
		return

	var response_code: int = result[1]
	if response_code == 401:
		push_error("[RaidManager] Commit failed: Invalid signature (401 Unauthorized)")
		raid_committed.emit(raid_id, false)
		return
	elif response_code == 403:
		push_error("[RaidManager] Commit failed: Timestamp expired (403 Forbidden)")
		raid_committed.emit(raid_id, false)
		return

	var json := JSON.new()
	if json.parse(result[3].get_string_from_utf8()) != OK:
		push_error("[RaidManager] Invalid commit response")
		raid_committed.emit(raid_id, false)
		return

	var data: Dictionary = json.data if json.data is Dictionary else {}

	if data.get("ok", false):
		print("[RaidManager] Raid committed successfully: %s" % raid_id.substr(0, 8))
		raid_committed.emit(raid_id, true)
	else:
		push_error("[RaidManager] Raid commit failed: %s" % data.get("error", "unknown"))
		raid_committed.emit(raid_id, false)


# ============================================
# MATCH LIFECYCLE
# ============================================

## End all active raids (match over)
func end_match(reason: String = "match_end") -> void:
	if not NetworkManager.is_authority():
		return

	print("[RaidManager] Ending match: %s" % reason)

	# Commit all uncommitted raids as deaths
	var peer_ids := active_raids.keys()
	for peer_id in peer_ids:
		var raid := active_raids[peer_id] as Dictionary
		if not raid.committed:
			raid.dead = true
			await _commit_raid(peer_id, false)

	active_raids.clear()
	current_match_id = ""


## Check if peer has active raid
func has_active_raid(peer_id: int) -> bool:
	return peer_id in active_raids


## Get raid info for peer
func get_raid_info(peer_id: int) -> Dictionary:
	if peer_id in active_raids:
		return active_raids[peer_id]
	return {}


# ============================================
# CLIENT-SIDE (for connecting with raid)
# ============================================

## Called by client to send their raid info to server
func client_register_raid() -> void:
	if NetworkManager.is_authority():
		return  # Server doesn't register with itself

	var raid_id := EconomyService.get_raid_id()
	var character_id := EconomyService.character_id
	var locked_iids := EconomyService.locked_iids

	if raid_id == "":
		print("[RaidManager] Client has no active raid")
		return

	# Build loadout data with item definitions for server
	var loadout_items: Array = []
	for iid in locked_iids:
		var item: Dictionary = EconomyService.get_item(iid)
		var def_id: String = item.get("def_id", item.get("defId", ""))
		var item_def: Dictionary = EconomyService.get_item_def(def_id)

		loadout_items.append({
			"iid": iid,
			"def_id": def_id,
			"item_def": item_def,  # Include full definition for server
			"item_data": item
		})

	print("[RaidManager] Sending raid registration to server with %d items..." % loadout_items.size())
	rpc_register_raid.rpc_id(1, raid_id, character_id, loadout_items)


## Called by client when they reach extraction
func client_request_extract() -> void:
	if NetworkManager.is_authority():
		return

	print("[RaidManager] Requesting extraction...")
	rpc_request_extract.rpc_id(1)
