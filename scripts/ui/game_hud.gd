extends Control
## GameHUD - In-game UI display
##
## Shows health, nails, wave info, game over, extraction progress, etc.
## Updates from local player state and game state.

@onready var wave_label: Label = $TopBar/WaveLabel
@onready var zombies_label: Label = $TopBar/ZombiesLabel
@onready var health_label: Label = $BottomBar/HealthLabel
@onready var nails_label: Label = $BottomBar/NailsLabel

# Game Over UI (created dynamically)
var game_over_panel: Panel = null
var game_over_title: Label = null
var game_over_stats: Label = null
var return_button: Button = null

# Extraction UI
var extraction_label: Label = null
var extraction_progress: ProgressBar = null

# Local player reference
var local_player: PlayerController = null


func _ready() -> void:
	# Connect to game state signals
	GameState.wave_started.connect(_on_wave_started)
	GameState.wave_ended.connect(_on_wave_ended)
	GameState.player_spawned.connect(_on_player_spawned)
	GameState.game_over.connect(_on_game_over)
	GameState.extraction_available.connect(_on_extraction_available)

	# Create game over UI (hidden initially)
	_create_game_over_ui()
	_create_extraction_ui()

	# Initial state
	_update_wave_display(0, 0)


func _process(_delta: float) -> void:
	_update_player_stats()
	_update_zombie_count()


func _on_player_spawned(peer_id: int, player: Node3D) -> void:
	# Check if this is our local player
	if peer_id == NetworkManager.local_peer_id:
		local_player = player as PlayerController


func _on_wave_started(wave_number: int) -> void:
	if wave_label:
		wave_label.text = "Wave: %d" % wave_number


func _on_wave_ended(_wave_number: int) -> void:
	if wave_label:
		wave_label.text += " (Complete!)"


func _update_wave_display(wave: int, zombies: int) -> void:
	if wave_label:
		wave_label.text = "Wave: %d" % wave
	if zombies_label:
		zombies_label.text = "Zombies: %d" % zombies


func _update_player_stats() -> void:
	if not local_player or not is_instance_valid(local_player):
		# Try to find local player
		for peer_id in GameState.players:
			if peer_id == NetworkManager.local_peer_id:
				local_player = GameState.players[peer_id] as PlayerController
				break
		return

	# Update health
	if health_label:
		var health: float = local_player.health
		health_label.text = "Health: %d" % int(health)

	# Update nails
	if nails_label:
		var hammer := _get_player_hammer()
		if hammer:
			nails_label.text = "Nails: %d" % hammer.get_nail_count()


func _update_zombie_count() -> void:
	if zombies_label:
		var zombie_count := GameState.zombies.size()
		zombies_label.text = "Zombies: %d" % zombie_count


func _get_player_hammer() -> Hammer:
	if not local_player:
		return null

	# Hammer is stored as metadata on player
	if local_player.has_meta("hammer"):
		return local_player.get_meta("hammer") as Hammer

	# Fallback: check camera pivot children
	var camera_pivot := local_player.get_camera_pivot()
	if camera_pivot:
		for child in camera_pivot.get_children():
			if child is Hammer:
				return child

	return null


# ============================================
# GAME OVER UI
# ============================================

func _create_game_over_ui() -> void:
	# Create centered panel
	game_over_panel = Panel.new()
	game_over_panel.name = "GameOverPanel"
	game_over_panel.custom_minimum_size = Vector2(400, 300)
	game_over_panel.visible = false
	add_child(game_over_panel)

	# Center the panel
	game_over_panel.set_anchors_preset(Control.PRESET_CENTER)
	game_over_panel.position = Vector2(-200, -150)

	# Create VBox for content
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 20)
	game_over_panel.add_child(vbox)

	# Spacer
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 30)
	vbox.add_child(spacer)

	# Title
	game_over_title = Label.new()
	game_over_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	game_over_title.add_theme_font_size_override("font_size", 36)
	vbox.add_child(game_over_title)

	# Stats
	game_over_stats = Label.new()
	game_over_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	game_over_stats.add_theme_font_size_override("font_size", 18)
	vbox.add_child(game_over_stats)

	# Spacer
	var spacer2 := Control.new()
	spacer2.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer2)

	# Return button
	return_button = Button.new()
	return_button.text = "Return to Menu"
	return_button.custom_minimum_size = Vector2(200, 50)
	return_button.pressed.connect(_on_return_pressed)
	vbox.add_child(return_button)

	# Center button
	var button_container := HBoxContainer.new()
	button_container.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(button_container)

	# Bottom spacer
	var spacer3 := Control.new()
	spacer3.custom_minimum_size = Vector2(0, 30)
	vbox.add_child(spacer3)


func _on_game_over(reason: String, victory: bool) -> void:
	if not game_over_panel:
		return

	# Show panel
	game_over_panel.visible = true

	# Set title
	if victory:
		game_over_title.text = "VICTORY!"
		game_over_title.add_theme_color_override("font_color", Color.GREEN)
	else:
		game_over_title.text = "GAME OVER"
		game_over_title.add_theme_color_override("font_color", Color.RED)

	# Set stats
	var stats := GameState.get_game_stats()
	game_over_stats.text = "%s\n\nWave: %d\nZombies Killed: %d\nPlayers Extracted: %d" % [
		reason,
		stats.get("wave", 0),
		stats.get("kills", 0),
		stats.get("extracted", 0),
	]

	# Show cursor
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _on_return_pressed() -> void:
	# Disconnect and return to main menu
	NetworkManager.disconnect_from_network()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


# ============================================
# EXTRACTION UI
# ============================================

func _create_extraction_ui() -> void:
	# Create extraction notification label
	extraction_label = Label.new()
	extraction_label.name = "ExtractionLabel"
	extraction_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	extraction_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	extraction_label.position = Vector2(-150, 100)
	extraction_label.custom_minimum_size = Vector2(300, 30)
	extraction_label.add_theme_font_size_override("font_size", 20)
	extraction_label.add_theme_color_override("font_color", Color.YELLOW)
	extraction_label.visible = false
	add_child(extraction_label)

	# Create extraction progress bar
	extraction_progress = ProgressBar.new()
	extraction_progress.name = "ExtractionProgress"
	extraction_progress.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	extraction_progress.position = Vector2(-150, -80)
	extraction_progress.custom_minimum_size = Vector2(300, 25)
	extraction_progress.max_value = 100
	extraction_progress.value = 0
	extraction_progress.visible = false
	add_child(extraction_progress)


func _on_extraction_available() -> void:
	if extraction_label:
		extraction_label.text = "EXTRACTION AVAILABLE!"
		extraction_label.visible = true

		# Hide after a few seconds
		await get_tree().create_timer(5.0).timeout
		extraction_label.visible = false


func show_extraction_progress(progress: float) -> void:
	if extraction_progress:
		extraction_progress.value = progress * 100
		extraction_progress.visible = true

		if extraction_label:
			extraction_label.text = "Extracting... %.0f%%" % (progress * 100)
			extraction_label.visible = true


func hide_extraction_progress() -> void:
	if extraction_progress:
		extraction_progress.visible = false
	if extraction_label:
		extraction_label.visible = false
