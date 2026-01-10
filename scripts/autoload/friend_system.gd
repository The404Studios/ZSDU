extends Node
## FriendSystem - Social features for multiplayer
##
## Provides:
## - Friend list management (add/remove)
## - Online status tracking
## - Game invites
## - Join friend's game
##
## All data syncs with the backend server.

signal friends_updated(friends: Array)
signal friend_request_received(from_player: Dictionary)
signal invite_received(from_player: Dictionary, server_info: Dictionary)
signal friend_online(friend_id: String)
signal friend_offline(friend_id: String)

# Configuration
const STATUS_UPDATE_INTERVAL := 30.0  # Update friend status every 30s

# Player identity
var local_player_id: String = ""
var local_player_name: String = "Player"

# Friend data
var friends: Dictionary = {}  # friend_id -> FriendInfo
var pending_requests: Array[Dictionary] = []  # Incoming friend requests
var sent_requests: Array[Dictionary] = []     # Outgoing friend requests

# Status timer
var _status_timer: Timer = null

# Invite queue
var pending_invite: Dictionary = {}


class FriendInfo:
	var id: String = ""
	var name: String = ""
	var is_online: bool = false
	var current_game: String = ""  # match_id if in game
	var last_seen: int = 0         # Unix timestamp

	func _init(data: Dictionary = {}) -> void:
		id = data.get("id", "")
		name = data.get("name", "")
		is_online = data.get("online", false)
		current_game = data.get("currentGame", "")
		last_seen = data.get("lastSeen", 0)

	func to_dict() -> Dictionary:
		return {
			"id": id,
			"name": name,
			"online": is_online,
			"currentGame": current_game,
			"lastSeen": last_seen
		}


func _ready() -> void:
	# Generate player ID if not set
	if local_player_id == "":
		local_player_id = _generate_player_id()

	# Create status update timer
	_status_timer = Timer.new()
	_status_timer.wait_time = STATUS_UPDATE_INTERVAL
	_status_timer.one_shot = false
	_status_timer.timeout.connect(_update_friend_status)
	add_child(_status_timer)

	# Load cached friends
	_load_friends_cache()

	print("[FriendSystem] Initialized with player ID: %s" % local_player_id)


func _generate_player_id() -> String:
	# Use a persistent ID stored in user data
	var config := ConfigFile.new()
	var path := "user://player_data.cfg"

	if config.load(path) == OK:
		var saved_id: String = config.get_value("player", "id", "")
		if saved_id != "":
			return saved_id

	# Generate new ID
	var new_id := "player_%d_%d" % [Time.get_unix_time_from_system(), randi()]
	config.set_value("player", "id", new_id)
	config.save(path)

	return new_id


# ============================================
# PUBLIC API
# ============================================

## Set player identity
func set_player_info(player_id: String, player_name: String) -> void:
	local_player_id = player_id
	local_player_name = player_name
	_save_player_info()


## Get current player ID
func get_player_id() -> String:
	return local_player_id


## Start tracking friend status (call after login)
func start_status_tracking() -> void:
	_update_friend_status()
	_status_timer.start()


## Stop tracking friend status
func stop_status_tracking() -> void:
	_status_timer.stop()


## Add friend by ID or name
func add_friend(friend_identifier: String) -> void:
	print("[FriendSystem] Sending friend request to: %s" % friend_identifier)

	var result = await _api_request("/friends/add", {
		"playerId": local_player_id,
		"friendId": friend_identifier
	})

	if result.has("error"):
		push_error("[FriendSystem] Add friend failed: %s" % result.error)
		return

	# Add to sent requests
	sent_requests.append({
		"id": friend_identifier,
		"timestamp": Time.get_unix_time_from_system()
	})

	print("[FriendSystem] Friend request sent")


## Remove friend
func remove_friend(friend_id: String) -> void:
	print("[FriendSystem] Removing friend: %s" % friend_id)

	var result = await _api_request("/friends/remove", {
		"playerId": local_player_id,
		"friendId": friend_id
	})

	if result.has("error"):
		push_error("[FriendSystem] Remove friend failed: %s" % result.error)
		return

	friends.erase(friend_id)
	_save_friends_cache()
	friends_updated.emit(_get_friends_array())


## Accept friend request
func accept_friend_request(from_id: String) -> void:
	print("[FriendSystem] Accepting friend request from: %s" % from_id)

	var result = await _api_request("/friends/accept", {
		"playerId": local_player_id,
		"friendId": from_id
	})

	if result.has("error"):
		push_error("[FriendSystem] Accept friend failed: %s" % result.error)
		return

	# Remove from pending
	pending_requests = pending_requests.filter(func(r): return r.id != from_id)

	# Add to friends
	var friend_info := FriendInfo.new(result.get("friend", {}))
	friends[from_id] = friend_info
	_save_friends_cache()
	friends_updated.emit(_get_friends_array())


## Decline friend request
func decline_friend_request(from_id: String) -> void:
	var result = await _api_request("/friends/decline", {
		"playerId": local_player_id,
		"friendId": from_id
	})

	# Remove from pending regardless
	pending_requests = pending_requests.filter(func(r): return r.id != from_id)


## Get friends list
func get_friends() -> Array[Dictionary]:
	return _get_friends_array()


## Get online friends
func get_online_friends() -> Array[Dictionary]:
	var online: Array[Dictionary] = []
	for friend_id in friends:
		var friend: FriendInfo = friends[friend_id]
		if friend.is_online:
			online.append(friend.to_dict())
	return online


## Send game invite to friend
func invite_friend(friend_id: String) -> void:
	if not NetworkManager.is_authority():
		push_error("[FriendSystem] Only host can send invites")
		return

	var match_info := {
		"matchId": NetworkManager.get_session_id() if NetworkManager else "",
		"host": BackendConfig.get_game_server_host() if BackendConfig else "127.0.0.1",
		"port": 27015,  # Default game server port
		"hostName": local_player_name
	}

	print("[FriendSystem] Inviting %s to game" % friend_id)

	var result = await _api_request("/friends/invite", {
		"fromPlayerId": local_player_id,
		"toPlayerId": friend_id,
		"serverInfo": match_info
	})

	if result.has("error"):
		push_error("[FriendSystem] Invite failed: %s" % result.error)


## Join friend's game
func join_friend_game(friend_id: String) -> void:
	if friend_id not in friends:
		push_error("[FriendSystem] Not in friends list")
		return

	var friend: FriendInfo = friends[friend_id]
	if friend.current_game == "":
		push_error("[FriendSystem] Friend is not in a game")
		return

	print("[FriendSystem] Joining %s's game: %s" % [friend.name, friend.current_game])

	# Get server info from backend
	var result = await _api_request("/match/" + friend.current_game, {}, "GET")

	if result.has("error"):
		push_error("[FriendSystem] Failed to get game info: %s" % result.error)
		return

	var host: String = result.get("serverHost", BackendConfig.get_game_server_host())
	var port: int = result.get("serverPort", 27015)

	NetworkManager.join_server(host, port)


## Check if player is friend
func is_friend(player_id: String) -> bool:
	return player_id in friends


## Get pending friend requests
func get_pending_requests() -> Array[Dictionary]:
	return pending_requests


# ============================================
# STATUS UPDATES
# ============================================

func _update_friend_status() -> void:
	if friends.is_empty():
		return

	var friend_ids: Array[String] = []
	for id in friends:
		friend_ids.append(id)

	var result = await _api_request("/friends/status", {
		"playerId": local_player_id,
		"friendIds": friend_ids
	})

	if result.has("error"):
		return

	var statuses: Array = result.get("statuses", [])
	var changed := false

	for status in statuses:
		var fid: String = status.get("id", "")
		if fid in friends:
			var friend: FriendInfo = friends[fid]
			var was_online := friend.is_online

			friend.is_online = status.get("online", false)
			friend.current_game = status.get("currentGame", "")
			friend.last_seen = status.get("lastSeen", friend.last_seen)

			if friend.is_online and not was_online:
				friend_online.emit(fid)
				changed = true
			elif not friend.is_online and was_online:
				friend_offline.emit(fid)
				changed = true

	if changed:
		friends_updated.emit(_get_friends_array())

	# Also check for pending requests
	_check_pending_requests()


func _check_pending_requests() -> void:
	var result = await _api_request("/friends/requests", {
		"playerId": local_player_id
	})

	if result.has("error"):
		return

	var requests: Array = result.get("requests", [])
	for req in requests:
		var from_id: String = req.get("fromId", "")
		var already_pending := false

		for existing in pending_requests:
			if existing.id == from_id:
				already_pending = true
				break

		if not already_pending:
			pending_requests.append({
				"id": from_id,
				"name": req.get("fromName", "Unknown"),
				"timestamp": req.get("timestamp", 0)
			})
			friend_request_received.emit(req)

	# Check for invites
	var invites: Array = result.get("invites", [])
	for invite in invites:
		invite_received.emit(
			{"id": invite.get("fromId"), "name": invite.get("fromName")},
			invite.get("serverInfo", {})
		)


# ============================================
# HTTP HELPERS
# ============================================

func _api_request(endpoint: String, data: Dictionary, method: String = "POST") -> Dictionary:
	# Create fresh HTTPRequest per call to avoid concurrency issues
	var http := HTTPRequest.new()
	http.timeout = 10.0
	add_child(http)

	var url := BackendConfig.get_http_url() + endpoint
	var headers := ["Content-Type: application/json"]
	var body := JSON.stringify(data) if not data.is_empty() else ""
	var http_method := HTTPClient.METHOD_POST if method == "POST" else HTTPClient.METHOD_GET

	var error := http.request(url, headers, http_method, body)
	if error != OK:
		http.queue_free()
		return {"error": "Request failed (%s)" % error_string(error)}

	var result = await http.request_completed
	http.queue_free()

	if result[0] != HTTPRequest.RESULT_SUCCESS:
		return {"error": "HTTP error (%d)" % result[0]}

	if result[1] < 200 or result[1] >= 300:
		return {"error": "HTTP %d" % result[1]}

	var json := JSON.new()
	if json.parse(result[3].get_string_from_utf8()) != OK:
		return {"error": "Invalid JSON response"}

	return json.data if json.data is Dictionary else {"data": json.data}


# ============================================
# PERSISTENCE
# ============================================

func _get_friends_array() -> Array[Dictionary]:
	var arr: Array[Dictionary] = []
	for id in friends:
		arr.append(friends[id].to_dict())
	return arr


func _save_friends_cache() -> void:
	var config := ConfigFile.new()
	config.load("user://player_data.cfg")

	var friends_data: Array = []
	for id in friends:
		friends_data.append(friends[id].to_dict())

	config.set_value("friends", "list", friends_data)
	config.save("user://player_data.cfg")


func _load_friends_cache() -> void:
	var config := ConfigFile.new()
	if config.load("user://player_data.cfg") != OK:
		return

	var friends_data: Array = config.get_value("friends", "list", [])
	for data in friends_data:
		var friend := FriendInfo.new(data)
		friends[friend.id] = friend


func _save_player_info() -> void:
	var config := ConfigFile.new()
	config.load("user://player_data.cfg")
	config.set_value("player", "id", local_player_id)
	config.set_value("player", "name", local_player_name)
	config.save("user://player_data.cfg")
