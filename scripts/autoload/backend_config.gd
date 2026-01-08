extends Node
## BackendConfig - Single source of truth for backend URLs
##
## Centralizes all backend connection settings.
## Supports environment override for dev/staging/prod.

# Default production settings
const DEFAULT_HOST := "162.248.94.149"
const DEFAULT_HTTP_PORT := 8080
const DEFAULT_TRAVERSAL_PORT := 7777

# Runtime config (can be overridden via cmdline or environment)
var host: String = DEFAULT_HOST
var http_port: int = DEFAULT_HTTP_PORT
var traversal_port: int = DEFAULT_TRAVERSAL_PORT


func _ready() -> void:
	_parse_config()
	print("[BackendConfig] Backend: %s (HTTP: %d, Traversal: %d)" % [host, http_port, traversal_port])


func _parse_config() -> void:
	# Command line args (highest priority)
	var args := OS.get_cmdline_args()
	for arg in args:
		if arg.begins_with("--backend-host="):
			host = arg.split("=")[1]
		elif arg.begins_with("--backend-http-port="):
			http_port = int(arg.split("=")[1])
		elif arg.begins_with("--backend-traversal-port="):
			traversal_port = int(arg.split("=")[1])

	# Environment variables (fallback)
	var env_host := OS.get_environment("BACKEND_HOST")
	var env_http := OS.get_environment("BACKEND_HTTP_PORT")
	var env_traversal := OS.get_environment("BACKEND_TRAVERSAL_PORT")

	if env_host != "" and host == DEFAULT_HOST:
		host = env_host
	if env_http != "" and http_port == DEFAULT_HTTP_PORT:
		http_port = int(env_http)
	if env_traversal != "" and traversal_port == DEFAULT_TRAVERSAL_PORT:
		traversal_port = int(env_traversal)


## Get the base HTTP API URL
func get_http_url() -> String:
	return "http://%s:%d" % [host, http_port]


## Get the traversal server address
func get_traversal_host() -> String:
	return host


## Get the traversal server port
func get_traversal_port() -> int:
	return traversal_port


## Get the public game server host (what clients connect to)
func get_game_server_host() -> String:
	return host
