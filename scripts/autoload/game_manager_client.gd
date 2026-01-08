extends Node
## GameManagerClient - Connects to the Backend HTTP API
##
## Provides:
## - Simple /match/find for quick matchmaking
## - Server list via /servers
## - Status checks via /status and /health
##
## This is the primary matchmaking client for production use.
## TraversalClient is for LAN session discovery.

signal match_found(server_info: Dictionary)
signal server_list_received(servers: Array)
signal connection_error(message: String)
signal status_received(status: Dictionary)

# API Configuration (override via environment)
# Uses same env vars as HeadlessServer for consistency
var api_host := "162.248.94.149"  # Production server
var api_port := 8080
var use_ssl := false

# HTTP client
var _http_request: HTTPRequest = null

# Player state (set before matchmaking)
var player_id := ""

# Constants
const HTTP_TIMEOUT := 10.0


func _ready() -> void:
	# Create HTTP request node
	_http_request = HTTPRequest.new()
	_http_request.timeout = HTTP_TIMEOUT
	add_child(_http_request)

	# Load config from environment
	_load_config()


func _load_config() -> void:
	# Same env vars as HeadlessServer for consistency
	var env_host := OS.get_environment("BACKEND_HOST")
	if env_host != "":
		api_host = env_host

	var env_port := OS.get_environment("BACKEND_PORT")
	if env_port != "":
		api_port = int(env_port)

	use_ssl = OS.get_environment("BACKEND_SSL") == "true"

	print("[GameManager] Backend: %s://%s:%d" % ["https" if use_ssl else "http", api_host, api_port])


# ============================================
# HTTP HELPERS
# ============================================

func _get_api_url(endpoint: String) -> String:
	var protocol := "https" if use_ssl else "http"
	return "%s://%s:%d%s" % [protocol, api_host, api_port, endpoint]


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
		# Try to parse error from body
		var body_text: String = result[3].get_string_from_utf8()
		var json := JSON.new()
		if json.parse(body_text) == OK and json.data is Dictionary:
			return json.data
		return {"error": "HTTP %d" % result[1], "status_code": result[1]}

	var json := JSON.new()
	var parse_error := json.parse(result[3].get_string_from_utf8())
	if parse_error != OK:
		return {"error": "Invalid JSON response"}

	return json.data if json.data is Dictionary else {"data": json.data}


# ============================================
# STATUS ENDPOINTS
# ============================================

## GET /health - Simple health check
func get_health() -> Dictionary:
	return await _http_request_async(HTTPClient.METHOD_GET, "/health")


## GET /status - Full server status with stats
func get_status() -> Dictionary:
	var result = await _http_request_async(HTTPClient.METHOD_GET, "/status")
	if not result.has("error"):
		status_received.emit(result)
	return result


## GET /servers - List all game servers
func get_servers() -> Array:
	var result = await _http_request_async(HTTPClient.METHOD_GET, "/servers")
	if result.has("error"):
		connection_error.emit(result.error)
		return []

	# Result is an array wrapped or direct
	var servers: Array = []
	if result.has("data") and result.data is Array:
		servers = result.data
	elif result is Array:
		servers = result

	server_list_received.emit(servers)
	return servers


# ============================================
# MATCHMAKING
# ============================================

## POST /match/find - Find or create a match
## Returns: { matchId, status, serverHost, serverPort, gameMode } or { error }
func find_match(p_player_id: String, game_mode: String = "survival") -> Dictionary:
	player_id = p_player_id
	print("[GameManager] Finding match for player: %s (mode: %s)" % [p_player_id, game_mode])

	var result = await _http_request_async(HTTPClient.METHOD_POST, "/match/find", {
		"playerId": p_player_id,
		"gameMode": game_mode
	})

	if result.has("error"):
		connection_error.emit(result.get("error", "Unknown error"))
		return result

	var status: String = result.get("status", "unknown")

	match status:
		"matched", "already_matched":
			print("[GameManager] Match found: %s on %s:%d" % [
				result.get("matchId", "?"),
				result.get("serverHost", "?"),
				result.get("serverPort", 0)
			])
			match_found.emit({
				"match_id": result.get("matchId", ""),
				"host": result.get("serverHost", "127.0.0.1"),
				"port": result.get("serverPort", 27015),
				"game_mode": result.get("gameMode", "survival")
			})

		"unavailable":
			print("[GameManager] No servers available")
			connection_error.emit("No servers available - try again later")

		"error":
			var error_msg: String = result.get("error", "Matchmaking failed")
			print("[GameManager] Matchmaking error: %s" % error_msg)
			connection_error.emit(error_msg)

	return result


## GET /match/{id} - Get match status
func get_match(match_id: String) -> Dictionary:
	return await _http_request_async(HTTPClient.METHOD_GET, "/match/" + match_id)


## Quick play - Find match and connect automatically via NetworkManager
func quick_play(p_player_id: String, game_mode: String = "survival") -> void:
	var result = await find_match(p_player_id, game_mode)

	if result.has("error"):
		return

	var status: String = result.get("status", "")
	if status in ["matched", "already_matched"]:
		var host: String = result.get("serverHost", "127.0.0.1")
		var port: int = result.get("serverPort", 27015)

		print("[GameManager] Quick play connecting to %s:%d" % [host, port])
		NetworkManager.join_server(host, port)


# ============================================
# SERVER BROWSER (future)
# ============================================

## Get available servers for manual selection
func get_available_servers() -> Array:
	var all_servers = await get_servers()
	return all_servers.filter(func(s): return s.get("status") == "ready")


## Join a specific server directly
func join_server_direct(host: String, port: int) -> void:
	print("[GameManager] Direct connect to %s:%d" % [host, port])
	NetworkManager.join_server(host, port)
