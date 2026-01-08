extends Control
## Lobby - Pre-game lobby UI
##
## Shows players, game settings, ready state, and handles game start.

# UI References
@onready var lobby_name_label: Label = $MainContainer/Header/LobbyNameLabel
@onready var leave_button: Button = $MainContainer/Header/LeaveButton
@onready var players_list: VBoxContainer = $MainContainer/ContentContainer/PlayersPanel/PlayersVBox/PlayersList
@onready var game_mode_option: OptionButton = $MainContainer/ContentContainer/SettingsPanel/SettingsVBox/GameModeContainer/GameModeOption
@onready var map_option: OptionButton = $MainContainer/ContentContainer/SettingsPanel/SettingsVBox/MapContainer/MapOption
@onready var invite_code: LineEdit = $MainContainer/ContentContainer/SettingsPanel/SettingsVBox/InviteContainer/InviteCode
@onready var copy_code_button: Button = $MainContainer/ContentContainer/SettingsPanel/SettingsVBox/InviteContainer/CopyCodeButton
@onready var ready_button: Button = $MainContainer/BottomContainer/ReadyButton
@onready var start_button: Button = $MainContainer/BottomContainer/StartButton
@onready var countdown_label: Label = $MainContainer/CountdownLabel
@onready var status_label: Label = $StatusLabel

# Player entry scene (created dynamically)
const PLAYER_ENTRY_HEIGHT := 50

# Local state
var is_ready := false


func _ready() -> void:
	# Connect buttons
	leave_button.pressed.connect(_on_leave_pressed)
	ready_button.pressed.connect(_on_ready_pressed)
	start_button.pressed.connect(_on_start_pressed)
	copy_code_button.pressed.connect(_on_copy_code_pressed)

	# Connect lobby signals
	LobbySystem.lobby_updated.connect(_on_lobby_updated)
	LobbySystem.player_joined_lobby.connect(_on_player_joined)
	LobbySystem.player_left_lobby.connect(_on_player_left)
	LobbySystem.player_ready_changed.connect(_on_player_ready_changed)
	LobbySystem.game_starting.connect(_on_game_starting)
	LobbySystem.game_started.connect(_on_game_started)
	LobbySystem.lobby_error.connect(_on_lobby_error)

	# Connect network signals
	NetworkManager.client_connected.connect(_on_client_connected)

	# Initial update
	_update_ui()


func _update_ui() -> void:
	var lobby := LobbySystem.get_current_lobby()

	# Update header
	lobby_name_label.text = "Lobby: %s" % lobby.get("name", "Unknown")

	# Update invite code
	invite_code.text = lobby.get("id", "")[0:8].to_upper() if lobby.has("id") else ""

	# Update players list
	_update_players_list(lobby.get("players", []))

	# Update settings (leader only can change)
	var is_leader := LobbySystem.is_lobby_leader()
	game_mode_option.disabled = not is_leader
	map_option.disabled = not is_leader

	# Update buttons
	ready_button.text = "Unready" if is_ready else "Ready"
	start_button.visible = is_leader
	start_button.disabled = not _all_players_ready()

	# Set start button text based on state
	if is_leader:
		var players: Array = lobby.get("players", [])
		if players.size() < 1:
			start_button.text = "Waiting for players..."
		elif not _all_players_ready():
			start_button.text = "Waiting for ready..."
		else:
			start_button.text = "Start Game"


func _update_players_list(players: Array) -> void:
	# Clear existing entries
	for child in players_list.get_children():
		child.queue_free()

	# Add player entries
	for player in players:
		var entry := _create_player_entry(player)
		players_list.add_child(entry)


func _create_player_entry(player: Dictionary) -> Control:
	var entry := HBoxContainer.new()
	entry.custom_minimum_size.y = PLAYER_ENTRY_HEIGHT

	# Leader crown or ready indicator
	var status_label := Label.new()
	if player.get("id") == LobbySystem.get_current_lobby().get("leaderId"):
		status_label.text = "[HOST] "
	elif player.get("ready", false):
		status_label.text = "[READY] "
	else:
		status_label.text = "[...] "
	status_label.add_theme_color_override("font_color", Color.GOLD if player.get("id") == LobbySystem.get_current_lobby().get("leaderId") else (Color.GREEN if player.get("ready") else Color.GRAY))
	entry.add_child(status_label)

	# Player name
	var name_label := Label.new()
	name_label.text = player.get("name", "Unknown")
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# Highlight local player
	if player.get("id") == FriendSystem.get_player_id():
		name_label.text += " (You)"
		name_label.add_theme_color_override("font_color", Color.CYAN)

	entry.add_child(name_label)

	return entry


func _all_players_ready() -> bool:
	var players: Array = LobbySystem.get_current_lobby().get("players", [])
	for player in players:
		if not player.get("ready", false):
			return false
	return players.size() > 0


# ============================================
# BUTTON HANDLERS
# ============================================

func _on_leave_pressed() -> void:
	LobbySystem.leave_lobby()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _on_ready_pressed() -> void:
	is_ready = not is_ready
	LobbySystem.set_ready(is_ready)
	ready_button.text = "Unready" if is_ready else "Ready"
	_update_ui()


func _on_start_pressed() -> void:
	if LobbySystem.is_lobby_leader():
		start_button.disabled = true
		start_button.text = "Starting..."
		LobbySystem.start_game()


func _on_copy_code_pressed() -> void:
	DisplayServer.clipboard_set(invite_code.text)
	status_label.text = "Lobby code copied!"

	await get_tree().create_timer(2.0).timeout
	status_label.text = ""


# ============================================
# LOBBY SIGNALS
# ============================================

func _on_lobby_updated(lobby_data: Dictionary) -> void:
	_update_ui()


func _on_player_joined(player_id: String, player_name: String) -> void:
	status_label.text = "%s joined the lobby" % player_name
	_update_ui()


func _on_player_left(player_id: String) -> void:
	status_label.text = "A player left the lobby"
	_update_ui()


func _on_player_ready_changed(player_id: String, ready: bool) -> void:
	_update_ui()


func _on_game_starting(countdown: int) -> void:
	countdown_label.text = "Starting in %d..." % countdown
	ready_button.disabled = true
	start_button.disabled = true
	leave_button.disabled = true


func _on_game_started() -> void:
	countdown_label.text = "Loading..."


func _on_lobby_error(message: String) -> void:
	status_label.text = "Error: %s" % message
	start_button.disabled = false
	start_button.text = "Start Game"


func _on_client_connected() -> void:
	# Connected to game server, load game world
	get_tree().change_scene_to_file("res://scenes/game_world.tscn")
