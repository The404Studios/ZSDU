extends Node
## GameManagerClient - Connects to the Game Manager HTTP/WebSocket API
##
## Provides:
## - HTTP API calls for session management, matchmaking, server list
## - WebSocket connection for real-time updates
## - Automatic reconnection and heartbeat
##
## This complements TraversalClient for full infrastructure support.

signal authenticated(session_id: String)
signal match_found(server_info: Dictionary)
signal matchmaking_started(ticket_id: String)
signal matchmaking_cancelled()
signal matchmaking_status_updated(status: String, wait_time: float)
signal server_list_received(servers: Array)
signal connection_error(message: String)
signal websocket_connected()
signal websocket_disconnected()

# API Configuration (override via environment or config)
var api_host := "localhost"
var api_port := 8080
var ws_port := 8081
var use_ssl := false

# Connection state
var _http_request: HTTPRequest = null
var _websocket: WebSocketPeer = null
var _ws_connected := false
var _ws_reconnect_timer := 0.0
var _ws_heartbeat_timer := 0.0

# Session state
var player_id := ""
var player_name := ""
var session_id := ""
var matchmaking_ticket_id := ""
var is_authenticated := false

# Constants
const WS_RECONNECT_INTERVAL := 5.0
const WS_HEARTBEAT_INTERVAL := 30.0
const HTTP_TIMEOUT := 10.0


func _ready() -> void:
	# Create HTTP request node
	_http_request = HTTPRequest.new()
	_http_request.timeout = HTTP_TIMEOUT
	add_child(_http_request)

	# Load config from environment/settings
	_load_config()


func _process(delta: float) -> void:
	_process_websocket(delta)


func _load_config() -> void:
	# Try to load from environment or project settings
	var env_host := OS.get_environment("GAME_MANAGER_HOST")
	if env_host != "":
		api_host = env_host

	var env_port := OS.get_environment("GAME_MANAGER_PORT")
	if env_port != "":
		api_port = int(env_port)

	var env_ws_port := OS.get_environment("GAME_MANAGER_WS_PORT")
	if env_ws_port != "":
		ws_port = int(env_ws_port)

	use_ssl = OS.get_environment("GAME_MANAGER_SSL") == "true"


# ============================================
# HTTP API
# ============================================

func _get_api_url(endpoint: String) -> String:
	var protocol := "https" if use_ssl else "http"
	return "%s://%s:%d%s" % [protocol, api_host, api_port, endpoint]


func _get_ws_url() -> String:
	var protocol := "wss" if use_ssl else "ws"
	return "%s://%s:%d/" % [protocol, api_host, ws_port]


## Make an HTTP request
func _http_request_async(method: HTTPClient.Method, endpoint: String, body: Dictionary = {}) -> Dictionary:
	var url := _get_api_url(endpoint)
	var headers := ["Content-Type: application/json"]
	var body_str := JSON.stringify(body) if not body.is_empty() else ""

	var error := _http_request.request(url, headers, method, body_str)
	if error != OK:
		return {"error": "Request failed: %s" % error_string(error)}

	var result = await _http_request.request_completed
	# result = [result_code, response_code, headers, body]

	if result[0] != HTTPRequest.RESULT_SUCCESS:
		return {"error": "HTTP error: %d" % result[0]}

	if result[1] < 200 or result[1] >= 300:
		return {"error": "HTTP %d" % result[1], "status_code": result[1]}

	var json := JSON.new()
	var parse_error := json.parse(result[3].get_string_from_utf8())
	if parse_error != OK:
		return {"error": "Invalid JSON response"}

	return json.data if json.data is Dictionary else {"data": json.data}


## Get server status
func get_status() -> Dictionary:
	return await _http_request_async(HTTPClient.METHOD_GET, "/status")


## Get server list
func get_servers() -> Array:
	var result = await _http_request_async(HTTPClient.METHOD_GET, "/api/servers")
	if result.has("error"):
		connection_error.emit(result.error)
		return []

	var servers: Array = result if result is Array else []
	server_list_received.emit(servers)
	return servers


## Create player session
func create_session(p_player_id: String, p_player_name: String) -> Dictionary:
	player_id = p_player_id
	player_name = p_player_name

	var result = await _http_request_async(HTTPClient.METHOD_POST, "/api/sessions", {
		"playerId": p_player_id,
		"playerName": p_player_name
	})

	if result.has("error"):
		connection_error.emit(result.error)
		return result

	session_id = result.get("id", "")
	is_authenticated = true
	authenticated.emit(session_id)

	return result


## Start matchmaking
func start_matchmaking(game_mode: String = "survival", region: String = "") -> Dictionary:
	if not is_authenticated:
		return {"error": "Not authenticated"}

	var body := {
		"playerId": player_id,
		"gameMode": game_mode
	}
	if region != "":
		body["preferredRegion"] = region

	var result = await _http_request_async(HTTPClient.METHOD_POST, "/api/matchmaking", body)

	if result.has("error"):
		connection_error.emit(result.error)
		return result

	matchmaking_ticket_id = result.get("id", "")
	matchmaking_started.emit(matchmaking_ticket_id)

	# Start polling for status
	_poll_matchmaking_status()

	return result


## Check matchmaking status
func get_matchmaking_status() -> Dictionary:
	if matchmaking_ticket_id == "":
		return {"error": "No active matchmaking ticket"}

	var result = await _http_request_async(HTTPClient.METHOD_GET, "/api/matchmaking/" + matchmaking_ticket_id)

	if result.has("error"):
		return result

	var status: String = result.get("status", "unknown")
	var wait_time: float = result.get("waitTimeSeconds", 0.0)

	matchmaking_status_updated.emit(status, wait_time)

	# Check if match found
	if status == "matched" and result.has("connection"):
		var connection: Dictionary = result.connection
		match_found.emit({
			"server_id": connection.get("serverId", ""),
			"host": connection.get("host", ""),
			"port": connection.get("port", 27015)
		})
		matchmaking_ticket_id = ""

	return result


## Cancel matchmaking
func cancel_matchmaking() -> Dictionary:
	if matchmaking_ticket_id == "":
		return {"error": "No active matchmaking ticket"}

	var result = await _http_request_async(HTTPClient.METHOD_DELETE, "/api/matchmaking/" + matchmaking_ticket_id)

	matchmaking_ticket_id = ""
	matchmaking_cancelled.emit()

	return result


## Poll matchmaking status periodically
func _poll_matchmaking_status() -> void:
	while matchmaking_ticket_id != "":
		await get_tree().create_timer(2.0).timeout

		if matchmaking_ticket_id == "":
			break

		var status = await get_matchmaking_status()
		if status.has("error") or status.get("status", "") in ["matched", "cancelled", "timed_out"]:
			break


# ============================================
# WEBSOCKET
# ============================================

## Connect to WebSocket for real-time updates
func connect_websocket() -> Error:
	if _websocket != null:
		_websocket.close()

	_websocket = WebSocketPeer.new()
	var error := _websocket.connect_to_url(_get_ws_url())

	if error != OK:
		connection_error.emit("WebSocket connection failed: %s" % error_string(error))
		return error

	print("[GameManager] Connecting to WebSocket: %s" % _get_ws_url())
	return OK


## Disconnect WebSocket
func disconnect_websocket() -> void:
	if _websocket:
		_websocket.close()
		_websocket = null

	_ws_connected = false
	websocket_disconnected.emit()


## Process WebSocket messages
func _process_websocket(delta: float) -> void:
	if _websocket == null:
		# Auto-reconnect logic
		if is_authenticated and not _ws_connected:
			_ws_reconnect_timer += delta
			if _ws_reconnect_timer >= WS_RECONNECT_INTERVAL:
				_ws_reconnect_timer = 0.0
				connect_websocket()
		return

	_websocket.poll()

	var state := _websocket.get_ready_state()

	match state:
		WebSocketPeer.STATE_OPEN:
			if not _ws_connected:
				_ws_connected = true
				_on_websocket_connected()

			# Process incoming messages
			while _websocket.get_available_packet_count() > 0:
				var packet := _websocket.get_packet()
				_handle_websocket_message(packet.get_string_from_utf8())

			# Heartbeat
			_ws_heartbeat_timer += delta
			if _ws_heartbeat_timer >= WS_HEARTBEAT_INTERVAL:
				_ws_heartbeat_timer = 0.0
				_send_websocket_message("ping", {})

		WebSocketPeer.STATE_CLOSING:
			pass

		WebSocketPeer.STATE_CLOSED:
			var code := _websocket.get_close_code()
			print("[GameManager] WebSocket closed with code: %d" % code)
			_websocket = null
			_ws_connected = false
			_ws_reconnect_timer = 0.0
			websocket_disconnected.emit()


func _on_websocket_connected() -> void:
	print("[GameManager] WebSocket connected")
	websocket_connected.emit()

	# Authenticate
	if player_id != "":
		_send_websocket_message("authenticate", {
			"playerId": player_id,
			"playerName": player_name
		})


func _send_websocket_message(msg_type: String, data: Dictionary) -> void:
	if _websocket == null or not _ws_connected:
		return

	var message := {
		"type": msg_type,
		"data": data
	}

	_websocket.send_text(JSON.stringify(message))


func _handle_websocket_message(json_str: String) -> void:
	var json := JSON.new()
	var error := json.parse(json_str)
	if error != OK:
		return

	var message: Dictionary = json.data
	var msg_type: String = message.get("type", "")
	var data: Dictionary = message.get("data", {})

	match msg_type:
		"connected":
			print("[GameManager] WebSocket session: %s" % data.get("clientId", ""))

		"authenticated":
			print("[GameManager] WebSocket authenticated")

		"match_found":
			var server_info := {
				"server_id": data.get("server", {}).get("id", ""),
				"host": data.get("server", {}).get("host", ""),
				"port": data.get("server", {}).get("port", 27015),
				"game_mode": data.get("server", {}).get("gameMode", "survival"),
				"map_name": data.get("server", {}).get("mapName", "default")
			}
			match_found.emit(server_info)
			matchmaking_ticket_id = ""

		"matchmaking_started":
			matchmaking_ticket_id = data.get("ticketId", "")
			matchmaking_started.emit(matchmaking_ticket_id)

		"matchmaking_cancelled":
			matchmaking_ticket_id = ""
			matchmaking_cancelled.emit()

		"matchmaking_status":
			var status: String = data.get("status", "unknown")
			var wait_time: float = data.get("waitTime", 0.0)
			matchmaking_status_updated.emit(status, wait_time)

		"server_status_changed":
			# Could emit a signal for UI updates
			pass

		"pong":
			pass  # Heartbeat response

		"error":
			connection_error.emit(data.get("message", "Unknown error"))


# ============================================
# WEBSOCKET MATCHMAKING
# ============================================

## Start matchmaking via WebSocket (real-time updates)
func start_matchmaking_ws(game_mode: String = "survival", region: String = "") -> void:
	if not _ws_connected:
		var error := connect_websocket()
		if error != OK:
			return
		await websocket_connected

	var data := {"gameMode": game_mode}
	if region != "":
		data["preferredRegion"] = region

	_send_websocket_message("matchmaking_start", data)


## Cancel matchmaking via WebSocket
func cancel_matchmaking_ws() -> void:
	_send_websocket_message("matchmaking_cancel", {})


## Get matchmaking status via WebSocket
func request_matchmaking_status_ws() -> void:
	_send_websocket_message("matchmaking_status", {})


# ============================================
# CONVENIENCE
# ============================================

## Full authentication flow
func authenticate(p_player_id: String, p_player_name: String) -> bool:
	# Create HTTP session
	var result = await create_session(p_player_id, p_player_name)
	if result.has("error"):
		return false

	# Connect WebSocket for real-time updates
	connect_websocket()

	return true


## Quick play - authenticate and start matchmaking
func quick_play(p_player_id: String, p_player_name: String, game_mode: String = "survival") -> void:
	if not is_authenticated:
		var success = await authenticate(p_player_id, p_player_name)
		if not success:
			return

	start_matchmaking_ws(game_mode)
