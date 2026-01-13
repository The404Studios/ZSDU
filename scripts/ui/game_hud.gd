extends Control
## GameHUD - In-game UI display
##
## Shows health, nails, wave info, game over, extraction progress, etc.
## Updates from local player state and game state.

@onready var wave_label: Label = $TopBar/WaveLabel
@onready var zombies_label: Label = $TopBar/ZombiesLabel
@onready var health_label: Label = $BottomBar/HealthLabel
@onready var nails_label: Label = $BottomBar/NailsLabel

# Weapon HUD elements (created dynamically)
var ammo_label: Label = null
var weapon_label: Label = null
var crosshair: Control = null

# Team currency (EntityRegistry)
var currency_label: Label = null

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

	# Connect to EntityRegistry for currency updates
	if EntityRegistry:
		EntityRegistry.entity_event_received.connect(_on_entity_event)

	# Create game over UI (hidden initially)
	_create_game_over_ui()
	_create_extraction_ui()
	_create_weapon_hud()
	_create_crosshair()
	_create_currency_display()

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

	# Update weapon info
	_update_weapon_display()


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

	# Center button container
	var button_container := HBoxContainer.new()
	button_container.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(button_container)

	# Return button (inside the centered container)
	return_button = Button.new()
	return_button.text = "Return to Menu"
	return_button.custom_minimum_size = Vector2(200, 50)
	return_button.pressed.connect(_on_return_pressed)
	button_container.add_child(return_button)

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


# ============================================
# WEAPON HUD
# ============================================

func _create_weapon_hud() -> void:
	# Create weapon name label (top right area)
	weapon_label = Label.new()
	weapon_label.name = "WeaponLabel"
	weapon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	weapon_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	weapon_label.position = Vector2(-250, 10)
	weapon_label.custom_minimum_size = Vector2(240, 30)
	weapon_label.add_theme_font_size_override("font_size", 18)
	weapon_label.add_theme_color_override("font_color", Color.WHITE)
	weapon_label.text = ""
	add_child(weapon_label)

	# Create ammo label (bottom right)
	ammo_label = Label.new()
	ammo_label.name = "AmmoLabel"
	ammo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ammo_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	ammo_label.position = Vector2(-200, -80)
	ammo_label.custom_minimum_size = Vector2(180, 60)
	ammo_label.add_theme_font_size_override("font_size", 32)
	ammo_label.add_theme_color_override("font_color", Color.WHITE)
	ammo_label.text = "-- / --"
	add_child(ammo_label)


func _create_crosshair() -> void:
	# Create crosshair container
	crosshair = Control.new()
	crosshair.name = "Crosshair"
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	crosshair.custom_minimum_size = Vector2(20, 20)
	crosshair.position = Vector2(-10, -10)
	add_child(crosshair)

	# Add crosshair lines (simple + shape)
	var line_length := 8
	var line_thickness := 2
	var gap := 4

	# Top line
	var top := ColorRect.new()
	top.color = Color.WHITE
	top.size = Vector2(line_thickness, line_length)
	top.position = Vector2(10 - line_thickness / 2, 10 - gap - line_length)
	crosshair.add_child(top)

	# Bottom line
	var bottom := ColorRect.new()
	bottom.color = Color.WHITE
	bottom.size = Vector2(line_thickness, line_length)
	bottom.position = Vector2(10 - line_thickness / 2, 10 + gap)
	crosshair.add_child(bottom)

	# Left line
	var left := ColorRect.new()
	left.color = Color.WHITE
	left.size = Vector2(line_length, line_thickness)
	left.position = Vector2(10 - gap - line_length, 10 - line_thickness / 2)
	crosshair.add_child(left)

	# Right line
	var right := ColorRect.new()
	right.color = Color.WHITE
	right.size = Vector2(line_length, line_thickness)
	right.position = Vector2(10 + gap, 10 - line_thickness / 2)
	crosshair.add_child(right)

	# Center dot
	var dot := ColorRect.new()
	dot.color = Color.WHITE
	dot.size = Vector2(2, 2)
	dot.position = Vector2(9, 9)
	crosshair.add_child(dot)


func _update_weapon_display() -> void:
	if not local_player:
		return

	# Get weapon manager
	var weapon_manager := local_player.get_weapon_manager()
	if not weapon_manager:
		# Fallback to inventory runtime
		var inventory := local_player.get_inventory_runtime()
		if inventory:
			var weapon := inventory.get_current_weapon()
			if weapon:
				_update_ammo_from_runtime(weapon)
		return

	# Get current weapon info
	var weapon_info := weapon_manager.get_current_weapon_info()
	var ammo_info := weapon_manager.get_ammo_info()

	# Update weapon name
	if weapon_label:
		var weapon_name: String = weapon_info.get("name", "")
		weapon_label.text = weapon_name

	# Update ammo display
	if ammo_label:
		var current: int = ammo_info.get("current", 0)
		var max_ammo: int = ammo_info.get("max", 0)

		if max_ammo > 0:
			ammo_label.text = "%d / %d" % [current, max_ammo]

			# Color based on ammo level
			if current <= 0:
				ammo_label.add_theme_color_override("font_color", Color.RED)
			elif current <= max_ammo * 0.3:
				ammo_label.add_theme_color_override("font_color", Color.ORANGE)
			else:
				ammo_label.add_theme_color_override("font_color", Color.WHITE)
		else:
			# Melee weapon
			ammo_label.text = ""


func _update_ammo_from_runtime(weapon: WeaponRuntime) -> void:
	if not weapon:
		return

	if weapon_label:
		weapon_label.text = weapon.name

	if ammo_label:
		if weapon.weapon_type != "melee":
			ammo_label.text = "%d / %d" % [weapon.current_ammo, weapon.magazine_size]

			if weapon.current_ammo <= 0:
				ammo_label.add_theme_color_override("font_color", Color.RED)
			elif weapon.current_ammo <= weapon.magazine_size * 0.3:
				ammo_label.add_theme_color_override("font_color", Color.ORANGE)
			else:
				ammo_label.add_theme_color_override("font_color", Color.WHITE)
		else:
			ammo_label.text = ""


## Set crosshair spread (visual feedback for accuracy)
func set_crosshair_spread(spread: float) -> void:
	if not crosshair:
		return

	# Adjust gap based on spread (more spread = wider crosshair)
	var base_gap := 4
	var spread_mult := spread * 100  # Convert to reasonable scale
	var new_gap := base_gap + int(spread_mult * 20)
	new_gap = mini(new_gap, 30)  # Cap at reasonable max

	# Update crosshair line positions
	var line_length := 8
	var line_thickness := 2

	for i in range(crosshair.get_child_count()):
		var child := crosshair.get_child(i) as ColorRect
		if not child:
			continue

		match i:
			0:  # Top
				child.position.y = 10 - new_gap - line_length
			1:  # Bottom
				child.position.y = 10 + new_gap
			2:  # Left
				child.position.x = 10 - new_gap - line_length
			3:  # Right
				child.position.x = 10 + new_gap


## Show hit marker briefly
func show_hit_marker() -> void:
	if not crosshair:
		return

	# Flash crosshair red
	for child in crosshair.get_children():
		if child is ColorRect:
			child.color = Color.RED

	# Reset after delay
	await get_tree().create_timer(0.1).timeout

	for child in crosshair.get_children():
		if child is ColorRect:
			child.color = Color.WHITE


# ============================================
# TEAM CURRENCY (EntityRegistry)
# ============================================

func _create_currency_display() -> void:
	# Create currency label (top left, below wave)
	currency_label = Label.new()
	currency_label.name = "CurrencyLabel"
	currency_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	currency_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	currency_label.position = Vector2(20, 80)
	currency_label.custom_minimum_size = Vector2(150, 30)
	currency_label.add_theme_font_size_override("font_size", 20)
	currency_label.add_theme_color_override("font_color", Color.GOLD)
	currency_label.text = "Team: 100"
	add_child(currency_label)

	# Initial update
	_update_currency_display()


func _update_currency_display() -> void:
	if not currency_label:
		return

	var currency := 0
	if EntityRegistry:
		currency = EntityRegistry.get_team_currency()

	currency_label.text = "Team: %d" % currency


func _on_entity_event(net_id: int, event: String, payload: Dictionary) -> void:
	# Update currency on relevant events
	match event:
		"looted", "item_purchased", "item_sold", "turret_spawned", "turret_refilled":
			_update_currency_display()
