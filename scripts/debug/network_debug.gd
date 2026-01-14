extends Node
## NetworkDebug - Golden path validation and network debugging
##
## Toggle with F3 in debug builds.
## Displays connection state, entity counts, and authority info.

var enabled := false
var panel: PanelContainer
var label: RichTextLabel

# Validation state
var golden_path_checks: Dictionary = {}


func _ready() -> void:
	# Only enable in debug builds
	if not OS.is_debug_build():
		return

	_create_debug_panel()
	_reset_golden_path_checks()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_F3:
		enabled = not enabled
		if panel:
			panel.visible = enabled


func _process(_delta: float) -> void:
	if not enabled or not label:
		return

	label.text = _build_debug_text()


func _create_debug_panel() -> void:
	# Create panel container
	panel = PanelContainer.new()
	panel.name = "NetworkDebugPanel"
	panel.visible = false
	panel.custom_minimum_size = Vector2(400, 300)
	panel.anchor_left = 0.0
	panel.anchor_top = 0.0
	panel.anchor_right = 0.0
	panel.anchor_bottom = 0.0
	panel.offset_left = 10
	panel.offset_top = 10

	# Create label
	label = RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.custom_minimum_size = Vector2(380, 280)
	panel.add_child(label)

	# Add to scene tree
	var canvas := CanvasLayer.new()
	canvas.layer = 100
	canvas.add_child(panel)
	add_child(canvas)


func _build_debug_text() -> String:
	var text := "[b]NETWORK DEBUG (F3)[/b]\n\n"

	# Connection state
	text += "[u]Connection State[/u]\n"
	text += "  State: %s\n" % _get_connection_state_name()
	text += "  Is Server: %s\n" % str(NetworkManager.is_server)
	text += "  Is Authority: %s\n" % str(NetworkManager.is_authority())
	text += "  Local Peer ID: %d\n" % NetworkManager.local_peer_id
	text += "  Connected Peers: %s\n" % str(NetworkManager.connected_peers)
	text += "\n"

	# Entity counts
	text += "[u]Entity Counts[/u]\n"
	text += "  Players: %d\n" % GameState.players.size()
	text += "  Zombies: %d\n" % GameState.zombies.size()
	text += "  Props: %d\n" % GameState.props.size()
	text += "  Nails: %d\n" % GameState.nails.size()
	text += "\n"

	# Game state
	text += "[u]Game State[/u]\n"
	text += "  Phase: %s\n" % _get_phase_name()
	text += "  Wave: %d\n" % GameState.current_wave
	text += "  Zombies Remaining: %d\n" % GameState.wave_zombies_remaining
	text += "\n"

	# Golden path validation
	text += "[u]Golden Path Checks[/u]\n"
	_update_golden_path_checks()
	for check_name in golden_path_checks:
		var passed: bool = golden_path_checks[check_name]
		var status := "[color=green]PASS[/color]" if passed else "[color=red]FAIL[/color]"
		text += "  %s: %s\n" % [check_name, status]

	return text


func _get_connection_state_name() -> String:
	match NetworkManager.current_state:
		NetworkManager.ConnectionState.DISCONNECTED: return "DISCONNECTED"
		NetworkManager.ConnectionState.DISCOVERING: return "DISCOVERING"
		NetworkManager.ConnectionState.CONNECTING: return "CONNECTING"
		NetworkManager.ConnectionState.SYNCING: return "SYNCING"
		NetworkManager.ConnectionState.PLAYING: return "PLAYING"
	return "UNKNOWN"


func _get_phase_name() -> String:
	match GameState.current_phase:
		GameState.GamePhase.LOBBY: return "LOBBY"
		GameState.GamePhase.PREPARING: return "PREPARING"
		GameState.GamePhase.WAVE_ACTIVE: return "WAVE_ACTIVE"
		GameState.GamePhase.WAVE_INTERMISSION: return "WAVE_INTERMISSION"
		GameState.GamePhase.GAME_OVER: return "GAME_OVER"
	return "UNKNOWN"


func _reset_golden_path_checks() -> void:
	golden_path_checks = {
		"Server Running": false,
		"Client Connected": false,
		"Player Spawned": false,
		"Authority Correct": false,
		"Sync Active": false,
	}


func _update_golden_path_checks() -> void:
	# Server Running: Either we're the server, or we're connected to one
	golden_path_checks["Server Running"] = (
		NetworkManager.is_server or
		NetworkManager.current_state == NetworkManager.ConnectionState.PLAYING
	)

	# Client Connected: We have a valid peer ID
	golden_path_checks["Client Connected"] = NetworkManager.local_peer_id > 0

	# Player Spawned: Our local player exists
	golden_path_checks["Player Spawned"] = (
		NetworkManager.local_peer_id in GameState.players and
		is_instance_valid(GameState.players.get(NetworkManager.local_peer_id))
	)

	# Authority Correct: Server has authority, clients don't
	if NetworkManager.is_server:
		golden_path_checks["Authority Correct"] = NetworkManager.is_authority()
	else:
		golden_path_checks["Authority Correct"] = not NetworkManager.is_authority()

	# Sync Active: In PLAYING state
	golden_path_checks["Sync Active"] = (
		NetworkManager.current_state == NetworkManager.ConnectionState.PLAYING
	)


## Validate that a specific authority check is working
func validate_authority_check(context: String, expected_authority: bool) -> bool:
	var actual := NetworkManager.is_authority()
	if actual != expected_authority:
		push_warning("[NetworkDebug] Authority violation in %s: expected=%s, actual=%s" % [
			context, expected_authority, actual
		])
		return false
	return true


## Log network event for debugging
func log_event(event_type: String, data: Dictionary = {}) -> void:
	if not OS.is_debug_build():
		return

	var timestamp := Time.get_time_string_from_system()
	var peer_info := "peer=%d" % NetworkManager.local_peer_id
	var auth_info := "auth=%s" % str(NetworkManager.is_authority())

	print("[%s] [Network] %s | %s %s | %s" % [
		timestamp, event_type, peer_info, auth_info, str(data)
	])
