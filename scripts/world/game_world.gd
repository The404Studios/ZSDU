extends Node3D
## GameWorld - Main game scene controller
##
## Implements the "pressure tube" model:
## - Sigil at start (defense objective)
## - Zombies spawn at end, move toward sigil
## - Barricades block the hallway
## - Players defend with props, loot, and skills

# Node references
@onready var players_container: Node = $Players
@onready var zombies_container: Node = $Zombies
@onready var props_container: Node = $Props
@onready var spawn_points: Node = $SpawnPoints
@onready var wave_manager: WaveManager = $WaveManager if has_node("WaveManager") else null
@onready var hud: Control = $HUD if has_node("HUD") else null

# Sigil (defense objective)
var sigil: Sigil = null
var sigil_position := Vector3.ZERO

# Zombie spawn lane
var zombie_spawn_position := Vector3(0, 0, 50)  # End of hallway

# Spawn point system
# Group spawners: Named groups that spawn together (e.g., "alpha", "bravo")
# Solo spawners: Individual spawn points for solo players
var group_spawn_points: Dictionary = {}  # group_name -> Array[Vector3]
var solo_spawn_points: Array[Vector3] = []
var player_spawn_positions: Array[Vector3] = []  # Legacy fallback

# Track which group spawners are in use
var active_groups: Dictionary = {}  # group_name -> [peer_ids]


func _ready() -> void:
	# Initialize GameState with world reference
	GameState.initialize_world(self)

	# Collect spawn points
	_collect_spawn_points()

	# Find or create sigil
	_setup_sigil()

	# Find zombie spawn lane
	_setup_spawn_lane()

	# Connect signals
	NetworkManager.player_joined.connect(_on_player_joined)
	NetworkManager.player_left.connect(_on_player_left)

	# Connect to GameDirector (new system) or WaveManager (legacy)
	if GameDirector:
		GameState.zombie_killed.connect(GameDirector.on_zombie_killed)
		# Sync GameDirector waves to GameState for server-side tracking
		GameDirector.wave_started.connect(_on_game_director_wave_started)
		GameDirector.wave_ended.connect(_on_game_director_wave_ended)
	elif wave_manager:
		GameState.zombie_killed.connect(wave_manager.on_zombie_killed)

	# Connect HUD to game state if present
	_setup_hud_connections()

	# Spawn existing players (for late joiners)
	for peer_id in NetworkManager.connected_peers:
		_spawn_player(peer_id)

	# Start waves on server after delay
	if NetworkManager.is_authority():
		await get_tree().create_timer(3.0).timeout
		_start_game()


func _setup_sigil() -> void:
	# Look for existing sigil in scene
	var sigils := get_tree().get_nodes_in_group("sigil")
	if not sigils.is_empty():
		sigil = sigils[0] as Sigil
		sigil_position = sigil.global_position
		print("[GameWorld] Found sigil at %s" % sigil_position)
	else:
		# Look for sigil spawn point
		if spawn_points:
			var sigil_point := spawn_points.get_node_or_null("SigilSpawn")
			if sigil_point:
				sigil_position = sigil_point.global_position
			else:
				sigil_position = Vector3(0, 0, 0)

		# Create sigil dynamically if script exists
		var sigil_script := load("res://scripts/world/sigil.gd")
		if sigil_script:
			sigil = Sigil.new()
			sigil.global_position = sigil_position
			add_child(sigil)
			print("[GameWorld] Created sigil at %s" % sigil_position)

	# Connect sigil signals for game state tracking
	if sigil:
		sigil.sigil_destroyed.connect(_on_sigil_destroyed)
		sigil.sigil_damaged.connect(_on_sigil_damaged)
		sigil.sigil_corrupted.connect(_on_sigil_corrupted)
		# Pass sigil reference to GameDirector
		if GameDirector:
			GameDirector.sigil = sigil


func _setup_spawn_lane() -> void:
	# Look for zombie spawn point
	if spawn_points:
		var zombie_spawn := spawn_points.get_node_or_null("ZombieSpawn")
		if zombie_spawn:
			zombie_spawn_position = zombie_spawn.global_position
		else:
			# Look for zombie_spawns group
			var spawns := get_tree().get_nodes_in_group("zombie_spawns")
			if not spawns.is_empty():
				zombie_spawn_position = spawns[0].global_position

	# Configure GameDirector spawn lane
	if GameDirector:
		GameDirector.set_spawn_lane(zombie_spawn_position, sigil_position)

	print("[GameWorld] Spawn lane: Zombies at %s -> Sigil at %s" % [
		zombie_spawn_position, sigil_position
	])


func _start_game() -> void:
	if GameDirector:
		GameDirector.start_game()
	elif wave_manager:
		wave_manager.start_waves()


func _collect_spawn_points() -> void:
	player_spawn_positions.clear()
	group_spawn_points.clear()
	solo_spawn_points.clear()

	if spawn_points:
		for child in spawn_points.get_children():
			if child is Node3D:
				# Group spawn points: "GroupSpawn_Alpha_0", "GroupSpawn_Alpha_1", etc.
				if child.name.begins_with("GroupSpawn_"):
					var parts: PackedStringArray = child.name.split("_")
					if parts.size() >= 2:
						var group_name: String = parts[1].to_lower()
						if group_name not in group_spawn_points:
							group_spawn_points[group_name] = []
						group_spawn_points[group_name].append(child.global_position)
				# Solo spawn points: "SoloSpawn_0", "SoloSpawn_1", etc.
				elif child.name.begins_with("SoloSpawn"):
					solo_spawn_points.append(child.global_position)
				# Legacy: "PlayerSpawn0", "PlayerSpawn1", etc.
				elif child.name.begins_with("PlayerSpawn"):
					player_spawn_positions.append(child.global_position)

	# Default spawn points if none found
	if player_spawn_positions.is_empty() and solo_spawn_points.is_empty():
		solo_spawn_points = [
			Vector3(0, 1, 0),
			Vector3(2, 1, 0),
			Vector3(-2, 1, 0),
			Vector3(0, 1, 2),
		]
		player_spawn_positions = solo_spawn_points.duplicate()

	# If only legacy spawn points found, use them as solo spawns too
	if solo_spawn_points.is_empty() and not player_spawn_positions.is_empty():
		solo_spawn_points = player_spawn_positions.duplicate()

	# Create default group if no groups defined
	if group_spawn_points.is_empty():
		group_spawn_points["default"] = [
			Vector3(5, 1, 5),
			Vector3(7, 1, 5),
			Vector3(5, 1, 7),
			Vector3(7, 1, 7),
		]

	print("[GameWorld] Spawn points loaded - Groups: %s, Solo: %d" % [
		group_spawn_points.keys(),
		solo_spawn_points.size()
	])


func _on_player_joined(peer_id: int) -> void:
	if NetworkManager.is_authority():
		_spawn_player(peer_id)


func _on_player_left(peer_id: int) -> void:
	# Cleanup handled by GameState
	pass


func _spawn_player(peer_id: int) -> void:
	if not NetworkManager.is_authority():
		return

	# Get spawn position based on lobby assignment or default
	var spawn_pos := _get_spawn_position_for_player(peer_id)

	# Spawn via GameState
	var player := GameState.spawn_player(peer_id, spawn_pos)

	if player:
		# Give starting equipment
		_equip_player(player)


## Get spawn position based on group assignment or solo
func _get_spawn_position_for_player(peer_id: int) -> Vector3:
	# Check if player has a lobby assignment (sent via RPC or stored in registry)
	var spawn_info := _get_player_spawn_info(peer_id)
	var group_name: String = spawn_info.get("group", "")
	var spawn_index: int = spawn_info.get("index", 0)

	# Group spawning
	if group_name != "" and group_name != "solo":
		# Find an available group spawner
		var target_group := group_name.to_lower()

		# If specific group doesn't exist, try to find any available one
		if target_group not in group_spawn_points:
			target_group = _find_available_group()

		if target_group != "":
			var positions: Array = group_spawn_points.get(target_group, [])
			if positions.size() > 0:
				# Track this player in the group
				if target_group not in active_groups:
					active_groups[target_group] = []
				if peer_id not in active_groups[target_group]:
					active_groups[target_group].append(peer_id)

				var pos_idx := spawn_index % positions.size()
				print("[GameWorld] Player %d spawning in group '%s' at index %d" % [peer_id, target_group, pos_idx])
				return positions[pos_idx]

	# Solo spawning
	if solo_spawn_points.size() > 0:
		var solo_idx := spawn_index % solo_spawn_points.size()
		print("[GameWorld] Player %d spawning solo at index %d" % [peer_id, solo_idx])
		return solo_spawn_points[solo_idx]

	# Fallback to legacy
	var legacy_idx := (peer_id - 1) % player_spawn_positions.size()
	print("[GameWorld] Player %d spawning at legacy index %d" % [peer_id, legacy_idx])
	return player_spawn_positions[legacy_idx]


## Find an available group spawner
func _find_available_group() -> String:
	# Return the first group that's not at capacity
	for group_name in group_spawn_points:
		var positions: Array = group_spawn_points[group_name]
		var current_count: int = active_groups.get(group_name, []).size()
		if current_count < positions.size():
			return group_name

	# If all full, return first group (will wrap around)
	if not group_spawn_points.is_empty():
		return group_spawn_points.keys()[0]

	return ""


## Get spawn info for a player (from lobby assignment or server registry)
func _get_player_spawn_info(peer_id: int) -> Dictionary:
	# On server, check if we have lobby data for this player
	# This would be set when the lobby starts the game
	var session_data := HeadlessServer.get_session_data() if has_node("/root/HeadlessServer") else {}
	var lobby_players: Array = session_data.get("lobby_players", [])

	for player_info in lobby_players:
		if player_info.get("peer_id") == peer_id:
			return {
				"group": player_info.get("group", ""),
				"index": player_info.get("spawn_index", 0)
			}

	# Check if running as dedicated server with HeadlessServer autoload
	if HeadlessServer and HeadlessServer.has_method("get_player_spawn_info"):
		return HeadlessServer.get_player_spawn_info(peer_id)

	# Default: Return info based on peer_id order
	return {
		"group": "",
		"index": peer_id - 1
	}


func _equip_player(player: PlayerController) -> void:
	var inventory := player.get_inventory_runtime()
	var equipment := player.get_equipment_runtime()

	# Try to apply loadout from EconomyService (if player prepared a raid)
	var loadout_applied := false
	if EconomyService and EconomyService.is_logged_in:
		loadout_applied = _apply_loadout_from_economy(player, inventory, equipment)

	# Fall back to default loadout if no prepared loadout
	if not loadout_applied:
		if inventory and inventory.get_weapon(0) == null:
			inventory.setup_default_loadout()
			print("[GameWorld] Gave default loadout to player %d" % player.peer_id)

			# Bind primary weapon to combat controller
			var combat := player.get_combat_controller()
			if combat:
				var weapon := inventory.get_weapon(0)
				if weapon:
					combat.bind_weapon(weapon)
					print("[GameWorld] Bound weapon '%s' to player %d" % [weapon.name, player.peer_id])

	# Give hammer (barricading tool, always available)
	var hammer_scene := load("res://scenes/weapons/hammer.tscn")
	if hammer_scene:
		var hammer: Hammer = hammer_scene.instantiate()
		hammer.initialize(player)

		var camera_pivot := player.get_camera_pivot()
		if camera_pivot:
			camera_pivot.add_child(hammer)
			hammer.position = Vector3(0.3, -0.2, -0.5)  # Offset for first person view

		# Store hammer reference on player for access via get_meta
		player.set_meta("hammer", hammer)


## Apply loadout from EconomyService (prepared raid items)
func _apply_loadout_from_economy(player: PlayerController, inventory: InventoryRuntime, equipment: EquipmentRuntime) -> bool:
	var locked_iids: Array = EconomyService.locked_iids
	if locked_iids.is_empty():
		return false

	print("[GameWorld] Applying loadout with %d locked items for player %d" % [locked_iids.size(), player.peer_id])

	var equipped_primary := false

	for iid in locked_iids:
		var item: Dictionary = EconomyService.get_item(iid)
		if item.is_empty():
			continue

		var def_id: String = item.get("def_id", item.get("defId", ""))
		var item_def: Dictionary = EconomyService.get_item_def(def_id)
		var category: String = item_def.get("category", "misc").to_lower()

		# Handle weapons
		if category in ["weapon", "rifle", "shotgun", "smg", "pistol"]:
			if inventory:
				var weapon := _create_weapon_from_item(item, item_def)
				if weapon:
					var slot := 0 if not equipped_primary else 1
					inventory.add_weapon(weapon, slot)
					print("[GameWorld] Equipped %s in slot %d" % [weapon.name, slot])

					if slot == 0:
						equipped_primary = true
						var combat := player.get_combat_controller()
						if combat:
							combat.bind_weapon(weapon)

		# Handle armor/equipment
		elif category in ["helmet", "headwear"]:
			if equipment:
				equipment.equip_item("helmet", item)
				print("[GameWorld] Equipped helmet: %s" % item_def.get("name", def_id))

		elif category in ["armor", "vest"]:
			if equipment:
				equipment.equip_item("vest", item)
				print("[GameWorld] Equipped vest: %s" % item_def.get("name", def_id))

		elif category in ["rig", "tactical_rig"]:
			if equipment:
				equipment.equip_item("rig", item)
				print("[GameWorld] Equipped rig: %s" % item_def.get("name", def_id))

		elif category in ["backpack", "bag"]:
			if equipment:
				equipment.equip_item("backpack", item)
				print("[GameWorld] Equipped backpack: %s" % item_def.get("name", def_id))

		# Handle consumables/ammo - add to inventory
		elif category in ["ammo", "medical", "consumable"]:
			if inventory:
				inventory.add_item_to_container(item, item_def)

	return locked_iids.size() > 0


## Create a WeaponRuntime from item data
func _create_weapon_from_item(item: Dictionary, item_def: Dictionary) -> WeaponRuntime:
	var weapon := WeaponRuntime.new()
	weapon.name = item_def.get("name", "Weapon")
	weapon.weapon_type = item_def.get("weapon_type", "rifle")
	weapon.damage = item_def.get("damage", 25.0)
	weapon.fire_rate = item_def.get("fire_rate", 0.1)
	weapon.magazine_size = item_def.get("magazine_size", 30)
	weapon.current_ammo = item.get("ammo", weapon.magazine_size)
	weapon.reload_time = item_def.get("reload_time", 2.0)
	weapon.range_max = item_def.get("range", 100.0)
	weapon.spread_base = item_def.get("spread", 0.02)
	return weapon


## Fast round reset (for testing or game restart)
func reset_round() -> void:
	if not NetworkManager.is_authority():
		return

	# Reset waves
	wave_manager.reset_waves()

	# Clear all nails
	for nail_id in GameState.nails.keys():
		if GameState.nails[nail_id].has("joint_node"):
			var joint = GameState.nails[nail_id].joint_node
			if is_instance_valid(joint):
				joint.queue_free()
	GameState.nails.clear()

	# Reset props to original positions
	for prop_id in GameState.props:
		var prop: BarricadeProp = GameState.props[prop_id] as BarricadeProp
		if prop:
			prop.attached_nail_ids.clear()
			# Could reset position to original if stored

	# Respawn all players
	for peer_id in GameState.players:
		var player: PlayerController = GameState.players[peer_id] as PlayerController
		if player:
			var spawn_idx: int = (peer_id - 1) % player_spawn_positions.size()
			player.respawn(player_spawn_positions[spawn_idx])

	# Notify clients
	NetworkManager.broadcast_event.rpc("round_reset", {})

	# Restart waves
	await get_tree().create_timer(3.0).timeout
	wave_manager.start_waves()


func _input(event: InputEvent) -> void:
	# Debug: Reset round with F5 (server only)
	if event.is_action_pressed("ui_page_down") and NetworkManager.is_authority():
		reset_round()

	# Toggle mouse capture with Escape
	if event.is_action_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# ============================================
# GAME DIRECTOR SIGNAL HANDLERS
# ============================================

## Sync GameDirector wave to GameState (server-side)
func _on_game_director_wave_started(wave: int, pressure: Dictionary) -> void:
	if not NetworkManager.is_authority():
		return

	# Update GameState to match GameDirector
	GameState.current_wave = wave
	GameState.wave_zombies_remaining = pressure.get("zombie_count", 0)
	GameState.wave_zombies_killed = 0
	GameState.current_phase = GameState.GamePhase.WAVE_ACTIVE

	# Emit GameState signal for local HUD updates
	GameState.wave_started.emit(wave)
	GameState.phase_changed.emit(GameState.current_phase)

	print("[GameWorld] Wave %d started - %d zombies" % [wave, pressure.zombie_count])


func _on_game_director_wave_ended(wave: int, stats: Dictionary) -> void:
	if not NetworkManager.is_authority():
		return

	GameState.current_phase = GameState.GamePhase.WAVE_INTERMISSION
	GameState.wave_ended.emit(wave)
	GameState.phase_changed.emit(GameState.current_phase)

	print("[GameWorld] Wave %d ended - Sigil HP: %.0f" % [wave, stats.get("sigil_health", 0)])


# ============================================
# SIGIL SIGNAL HANDLERS
# ============================================

func _on_sigil_destroyed() -> void:
	print("[GameWorld] SIGIL DESTROYED - GAME OVER")

	# Stop GameDirector from spawning more zombies
	if GameDirector:
		GameDirector.wave_active = false

	# GameState._trigger_game_over is already called by Sigil


func _on_sigil_damaged(damage: float, current_health: float) -> void:
	# Broadcast sigil damage to clients for HUD updates
	if NetworkManager.is_authority():
		NetworkManager.broadcast_event.rpc("sigil_damaged", {
			"damage": damage,
			"health": current_health,
			"max_health": sigil.max_health if sigil else 1000.0
		})


func _on_sigil_corrupted() -> void:
	# A zombie reached the sigil
	if NetworkManager.is_authority():
		NetworkManager.broadcast_event.rpc("sigil_corrupted", {
			"corruption_count": sigil.total_corruption if sigil else 0
		})


# ============================================
# HUD CONNECTIONS
# ============================================

func _setup_hud_connections() -> void:
	# Find HUD in scene
	var animated_hud: AnimatedHUD = null

	if hud and hud is AnimatedHUD:
		animated_hud = hud as AnimatedHUD
	else:
		# Look for HUD in UI layer
		animated_hud = get_node_or_null("/root/AnimatedHUD") as AnimatedHUD
		if not animated_hud:
			# Look for it as child
			for child in get_children():
				if child is AnimatedHUD:
					animated_hud = child as AnimatedHUD
					break

	if not animated_hud:
		print("[GameWorld] No AnimatedHUD found - skipping HUD connections")
		return

	# Connect GameState signals to HUD
	GameState.wave_started.connect(func(wave_num: int):
		animated_hud.wave_started.emit(wave_num)
	)

	GameState.zombie_killed.connect(func(zombie_id: int):
		# Get zombie type for kill feed
		var zombie_type := "Zombie"
		animated_hud.kill_registered.emit(zombie_type, false)
	)

	GameState.hit_confirmed.connect(func(peer_id: int, hit_data: Dictionary):
		# Show hit marker for local player
		var local_peer := multiplayer.get_unique_id()
		if peer_id == local_peer:
			var is_kill: bool = hit_data.get("target_type", "") == "zombie"
			var is_headshot: bool = hit_data.get("is_headshot", false)
			animated_hud.show_hit_marker(is_kill, is_headshot)
	)

	GameState.game_over.connect(func(reason: String, victory: bool):
		# Could show game over UI here
		print("[HUD] Game Over: %s (%s)" % [reason, "Victory" if victory else "Defeat"])
	)

	# Connect sigil signals to HUD
	GameState.sigil_damaged.connect(func(damage: float, health: float, max_health: float):
		animated_hud.update_sigil_health(health, max_health)
	)

	GameState.sigil_corrupted.connect(func(corruption_count: int):
		animated_hud.on_sigil_corrupted()
	)

	print("[GameWorld] HUD connections established")
