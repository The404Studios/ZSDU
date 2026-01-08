extends Node
## GameState - Central game state manager
##
## Handles game phases, player management, and state synchronization.
## Server owns all authoritative state.
## Clients receive snapshots and apply them.

signal phase_changed(phase: GamePhase)
signal wave_started(wave_number: int)
signal wave_ended(wave_number: int)
signal player_spawned(peer_id: int, player_node: Node3D)
signal player_died(peer_id: int)
signal zombie_spawned(zombie_id: int)
signal zombie_killed(zombie_id: int)
signal barricade_damaged(nail_id: int, damage: float)
signal barricade_destroyed(nail_id: int)
signal hit_confirmed(peer_id: int, hit_data: Dictionary)
signal game_over(reason: String, victory: bool)
signal extraction_available()
signal player_extracted(peer_id: int)

enum GamePhase {
	LOBBY,
	PREPARING,
	WAVE_ACTIVE,
	WAVE_INTERMISSION,
	GAME_OVER
}

# Game state
var current_phase: GamePhase = GamePhase.LOBBY
var current_wave: int = 0
var wave_zombies_remaining: int = 0
var wave_zombies_killed: int = 0

# Victory/Extraction settings
const MAX_WAVES := 10  # Survive 10 waves to win
const EXTRACTION_UNLOCK_WAVE := 5  # Extraction available after wave 5
var extraction_active := false
var extracted_players: Array[int] = []  # peer_ids that extracted
var dead_players: Array[int] = []  # peer_ids that died

# Entity tracking
var players: Dictionary = {}  # peer_id -> Player node
var zombies: Dictionary = {}  # zombie_id -> Zombie node
var props: Dictionary = {}    # prop_id -> Prop node
var nails: Dictionary = {}    # nail_id -> Nail data

# ID counters (server-side)
var _next_zombie_id: int = 1
var _next_prop_id: int = 1
var _next_nail_id: int = 1

# References
var world_node: Node3D = null
var players_container: Node = null
var zombies_container: Node = null
var props_container: Node = null

# Preloaded scenes
var player_scene: PackedScene = null
var zombie_scene: PackedScene = null


func _ready() -> void:
	# Defer scene loading to avoid circular dependencies
	call_deferred("_load_scenes")

	# Connect player_died to check for game over
	player_died.connect(_on_player_death_tracked)


func _load_scenes() -> void:
	player_scene = load("res://scenes/player/player.tscn")
	zombie_scene = load("res://scenes/zombie/zombie.tscn")


func _physics_process(_delta: float) -> void:
	if NetworkManager.is_authority():
		_server_tick()


## Server tick - runs every physics frame on server
func _server_tick() -> void:
	# Build and broadcast state snapshot
	var snapshot := _build_snapshot()
	NetworkManager.broadcast_state_update.rpc(snapshot)

	# Check wave completion
	if current_phase == GamePhase.WAVE_ACTIVE:
		if wave_zombies_remaining <= 0 and zombies.is_empty():
			_end_wave()


## Build state snapshot for network sync
func _build_snapshot() -> Dictionary:
	var player_states := {}
	for peer_id in players:
		var player: Node3D = players[peer_id]
		if is_instance_valid(player) and player.has_method("get_network_state"):
			player_states[peer_id] = player.get_network_state()

	var zombie_states := {}
	for zombie_id in zombies:
		var zombie: Node3D = zombies[zombie_id]
		if is_instance_valid(zombie) and zombie.has_method("get_network_state"):
			zombie_states[zombie_id] = zombie.get_network_state()

	var nail_states := {}
	for nail_id in nails:
		var nail_data: Dictionary = nails[nail_id]
		nail_states[nail_id] = {
			"hp": nail_data.hp,
			"active": nail_data.active
		}

	# Prop states (includes held state for interpolation)
	var prop_states := {}
	for prop_id in props:
		var prop: RigidBody3D = props[prop_id]
		if is_instance_valid(prop) and prop.has_method("get_network_state"):
			prop_states[prop_id] = prop.get_network_state()

	return {
		"tick": Engine.get_physics_frames(),
		"players": player_states,
		"zombies": zombie_states,
		"nails": nail_states,
		"props": prop_states,
	}


## Apply snapshot from server (client-side)
func apply_snapshot(snapshot: Dictionary) -> void:
	if NetworkManager.is_authority():
		return  # Server doesn't apply its own snapshots

	# Apply player states
	if "players" in snapshot:
		for peer_id_str in snapshot.players:
			var peer_id: int = int(peer_id_str)
			if peer_id in players:
				var player: Node3D = players[peer_id]
				if is_instance_valid(player) and player.has_method("apply_network_state"):
					player.apply_network_state(snapshot.players[peer_id_str])

	# Apply zombie states
	if "zombies" in snapshot:
		for zombie_id_str in snapshot.zombies:
			var zombie_id: int = int(zombie_id_str)
			if zombie_id in zombies:
				var zombie: Node3D = zombies[zombie_id]
				if is_instance_valid(zombie) and zombie.has_method("apply_network_state"):
					zombie.apply_network_state(snapshot.zombies[zombie_id_str])

	# Apply nail states
	if "nails" in snapshot:
		for nail_id_str in snapshot.nails:
			var nail_id: int = int(nail_id_str)
			if nail_id in nails:
				nails[nail_id].hp = snapshot.nails[nail_id_str].hp
				nails[nail_id].active = snapshot.nails[nail_id_str].active

	# Apply prop states
	if "props" in snapshot:
		for prop_id_str in snapshot.props:
			var prop_id: int = int(prop_id_str)
			if prop_id in props:
				var prop: RigidBody3D = props[prop_id]
				if is_instance_valid(prop) and prop.has_method("apply_network_state"):
					prop.apply_network_state(snapshot.props[prop_id_str])


## Apply full game state (for late joiners)
func apply_state(state: Dictionary) -> void:
	if "wave" in state:
		current_wave = state.wave
	if "phase" in state:
		current_phase = state.phase as GamePhase


## Process player input (server-side)
func process_player_input(peer_id: int, input_data: Dictionary) -> void:
	if not NetworkManager.is_authority():
		return

	if peer_id in players:
		var player: Node3D = players[peer_id]
		if is_instance_valid(player) and player.has_method("apply_input"):
			player.apply_input(input_data)


## Process action request from client (server-side)
func process_action_request(peer_id: int, action_type: String, action_data: Dictionary) -> void:
	if not NetworkManager.is_authority():
		return

	match action_type:
		"place_nail":
			_handle_nail_placement(peer_id, action_data)
		"repair_nail":
			_handle_nail_repair(peer_id, action_data)
		"pickup_prop":
			_handle_prop_pickup(peer_id, action_data)
		"drop_prop":
			_handle_prop_drop(peer_id, action_data)
		"throw_prop":
			_handle_prop_throw(peer_id, action_data)
		"hold_update":
			_handle_prop_hold_update(peer_id, action_data)
		"nail_while_holding":
			_handle_nail_while_holding(peer_id, action_data)
		"shoot":
			_handle_shoot(peer_id, action_data)


## Handle event from server (client-side)
func handle_event(event_type: String, event_data: Dictionary) -> void:
	match event_type:
		"spawn_player":
			_spawn_player_local(event_data.peer_id, event_data.position)
		"spawn_zombie":
			_spawn_zombie_local(event_data.zombie_id, event_data.position, event_data.zombie_type)
		"nail_created":
			_create_nail_local(event_data)
		"nail_destroyed":
			_destroy_nail_local(event_data.nail_id)
		"nails_cleared":
			nails.clear()
		"round_reset":
			_handle_round_reset()
		"wave_start":
			current_wave = event_data.wave
			current_phase = GamePhase.WAVE_ACTIVE
			wave_started.emit(current_wave)
		"wave_end":
			current_phase = GamePhase.WAVE_INTERMISSION
			wave_ended.emit(current_wave)
		"prop_picked_up":
			_handle_prop_picked_up_event(event_data)
		"prop_dropped":
			_handle_prop_dropped_event(event_data)
		"prop_thrown":
			_handle_prop_thrown_event(event_data)
		"hit_confirmed":
			_handle_hit_confirmed_event(event_data)
		"game_over":
			_handle_game_over_event(event_data)
		"extraction_unlocked":
			_handle_extraction_unlocked_event(event_data)
		"player_extracted":
			_handle_player_extracted_event(event_data)


## Handle game over event (client-side)
func _handle_game_over_event(event_data: Dictionary) -> void:
	current_phase = GamePhase.GAME_OVER
	var reason: String = event_data.get("reason", "Game Over")
	var victory: bool = event_data.get("victory", false)

	print("[GameState] %s: %s" % ["VICTORY" if victory else "GAME OVER", reason])

	game_over.emit(reason, victory)
	phase_changed.emit(current_phase)


## Handle extraction unlocked event (client-side)
func _handle_extraction_unlocked_event(event_data: Dictionary) -> void:
	extraction_active = true
	var wave: int = event_data.get("wave", current_wave)

	print("[GameState] Extraction unlocked at wave %d!" % wave)

	extraction_available.emit()


## Handle player extracted event (client-side)
func _handle_player_extracted_event(event_data: Dictionary) -> void:
	var peer_id: int = event_data.get("peer_id", -1)

	if peer_id > 0 and peer_id not in extracted_players:
		extracted_players.append(peer_id)

	print("[GameState] Player %d extracted!" % peer_id)

	player_extracted.emit(peer_id)


## Called when a player disconnects
func on_player_disconnected(peer_id: int) -> void:
	if peer_id in players:
		var player: Node3D = players[peer_id]
		if is_instance_valid(player):
			player.queue_free()
		players.erase(peer_id)


## Initialize world references (called when world scene loads)
func initialize_world(world: Node3D) -> void:
	world_node = world

	# Get or create containers
	players_container = world.get_node_or_null("Players")
	if not players_container:
		players_container = Node.new()
		players_container.name = "Players"
		world.add_child(players_container)

	zombies_container = world.get_node_or_null("Zombies")
	if not zombies_container:
		zombies_container = Node.new()
		zombies_container.name = "Zombies"
		world.add_child(zombies_container)

	props_container = world.get_node_or_null("Props")
	if not props_container:
		props_container = Node.new()
		props_container.name = "Props"
		world.add_child(props_container)


## Spawn a player (server-side)
func spawn_player(peer_id: int, position: Vector3 = Vector3.ZERO) -> Node3D:
	if not NetworkManager.is_authority():
		return null

	if not player_scene:
		push_error("Player scene not loaded")
		return null

	var player: Node3D = player_scene.instantiate()
	player.name = "Player_%d" % peer_id
	player.set_multiplayer_authority(peer_id)

	if players_container:
		players_container.add_child(player)
	else:
		push_error("Players container not found")
		return null

	player.global_position = position
	players[peer_id] = player

	# Notify all clients
	NetworkManager.broadcast_event.rpc("spawn_player", {
		"peer_id": peer_id,
		"position": position
	})

	player_spawned.emit(peer_id, player)
	return player


## Spawn player locally (client-side, from event)
func _spawn_player_local(peer_id: int, position: Vector3) -> void:
	if peer_id in players:
		return  # Already exists

	if not player_scene:
		return

	var player: Node3D = player_scene.instantiate()
	player.name = "Player_%d" % peer_id
	player.set_multiplayer_authority(peer_id)

	if players_container:
		players_container.add_child(player)

	player.global_position = position
	players[peer_id] = player
	player_spawned.emit(peer_id, player)


## Spawn a zombie (server-side only)
func spawn_zombie(position: Vector3, zombie_type: String = "walker") -> int:
	if not NetworkManager.is_authority():
		return -1

	if not zombie_scene:
		push_error("Zombie scene not loaded")
		return -1

	var zombie_id := _next_zombie_id
	_next_zombie_id += 1

	var zombie: Node3D = zombie_scene.instantiate()
	zombie.name = "Zombie_%d" % zombie_id
	zombie.set("zombie_id", zombie_id)
	zombie.set("zombie_type", zombie_type)

	if zombies_container:
		zombies_container.add_child(zombie)

	zombie.global_position = position
	zombies[zombie_id] = zombie

	# Notify all clients
	NetworkManager.broadcast_event.rpc("spawn_zombie", {
		"zombie_id": zombie_id,
		"position": position,
		"zombie_type": zombie_type
	})

	zombie_spawned.emit(zombie_id)
	return zombie_id


## Spawn zombie locally (client-side)
func _spawn_zombie_local(zombie_id: int, position: Vector3, zombie_type: String) -> void:
	if zombie_id in zombies:
		return

	if not zombie_scene:
		return

	var zombie: Node3D = zombie_scene.instantiate()
	zombie.name = "Zombie_%d" % zombie_id
	zombie.set("zombie_id", zombie_id)
	zombie.set("zombie_type", zombie_type)

	if zombies_container:
		zombies_container.add_child(zombie)

	zombie.global_position = position
	zombies[zombie_id] = zombie
	zombie_spawned.emit(zombie_id)


## Kill a zombie (server-side)
func kill_zombie(zombie_id: int) -> void:
	if not NetworkManager.is_authority():
		return

	if zombie_id in zombies:
		var zombie: Node3D = zombies[zombie_id]
		if is_instance_valid(zombie):
			zombie.queue_free()
		zombies.erase(zombie_id)
		wave_zombies_killed += 1
		zombie_killed.emit(zombie_id)


# ============================================
# NAIL/BARRICADE SYSTEM (JetBoom-style)
# ============================================

## Handle nail placement request (server-side)
func _handle_nail_placement(peer_id: int, data: Dictionary) -> void:
	# Validate request
	if not _validate_nail_placement(peer_id, data):
		return

	var nail_id := _next_nail_id
	_next_nail_id += 1

	# Create nail data
	var nail_data := {
		"id": nail_id,
		"owner_id": peer_id,
		"prop_id": data.prop_id,
		"surface_id": data.surface_id,  # -1 for world
		"position": data.position,
		"normal": data.normal,
		"hp": randf_range(80.0, 120.0),  # Random HP like JetBoom
		"max_hp": 120.0,
		"repair_count": 0,
		"max_repairs": 3,
		"active": true,
	}

	nails[nail_id] = nail_data

	# Create physics joint on server
	_create_nail_joint(nail_data)

	# Notify all clients
	NetworkManager.broadcast_event.rpc("nail_created", nail_data)


## Validate nail placement (server-side)
func _validate_nail_placement(peer_id: int, data: Dictionary) -> bool:
	# Check player exists and is alive
	if peer_id not in players:
		return false

	var player: Node3D = players[peer_id]
	if not is_instance_valid(player):
		return false

	# Check prop exists
	if data.prop_id not in props:
		return false

	var prop: Node3D = props[data.prop_id]
	if not is_instance_valid(prop):
		return false

	# Check distance to player
	var distance: float = player.global_position.distance_to(data.position)
	if distance > 4.0:  # Max reach
		return false

	# Count existing nails on this prop
	var nail_count := 0
	for nail_id in nails:
		if nails[nail_id].prop_id == data.prop_id and nails[nail_id].active:
			nail_count += 1

	if nail_count >= 3:  # Max nails per prop (JetBoom rule)
		return false

	# Check for nail stacking (no nails too close together)
	for nail_id in nails:
		var nail: Dictionary = nails[nail_id]
		if nail.active and nail.prop_id == data.prop_id:
			var dist: float = nail.position.distance_to(data.position)
			if dist < 0.3:  # Min distance between nails
				return false

	return true


## Create physics joint for nail (server-side)
func _create_nail_joint(nail_data: Dictionary) -> void:
	var prop_id: int = nail_data.prop_id
	if prop_id not in props:
		return

	var prop: RigidBody3D = props[prop_id] as RigidBody3D
	if not prop:
		return

	# Create pin joint
	var joint := PinJoint3D.new()
	joint.name = "Nail_%d" % nail_data.id
	joint.global_position = nail_data.position

	# Configure joint
	if nail_data.surface_id == -1:
		# Nail to world (static)
		joint.node_a = prop.get_path()
		# node_b left empty = world
	else:
		# Nail to another prop
		if nail_data.surface_id in props:
			var surface_prop: RigidBody3D = props[nail_data.surface_id] as RigidBody3D
			if surface_prop:
				joint.node_a = prop.get_path()
				joint.node_b = surface_prop.get_path()

	# Add joint to world
	if world_node:
		world_node.add_child(joint)

	# Store joint reference
	nail_data["joint_node"] = joint


## Create nail locally (client-side)
func _create_nail_local(nail_data: Dictionary) -> void:
	# Store nail data
	nails[nail_data.id] = nail_data.duplicate()

	# Visual only - joint is server-side
	# Could add nail mesh/effect here


## Handle nail repair request (server-side)
func _handle_nail_repair(peer_id: int, data: Dictionary) -> void:
	var nail_id: int = data.nail_id

	if nail_id not in nails:
		return

	var nail: Dictionary = nails[nail_id]

	if not nail.active:
		return

	# Check repair count
	if nail.repair_count >= nail.max_repairs:
		return  # Can't repair anymore (JetBoom diminishing returns)

	# Repair with diminishing returns
	var repair_amount := 30.0 * (1.0 - nail.repair_count * 0.25)
	nail.hp = minf(nail.hp + repair_amount, nail.max_hp * (1.0 - nail.repair_count * 0.15))
	nail.repair_count += 1


## Damage a nail (server-side, called by zombies)
func damage_nail(nail_id: int, damage: float) -> void:
	if not NetworkManager.is_authority():
		return

	if nail_id not in nails:
		return

	var nail: Dictionary = nails[nail_id]
	if not nail.active:
		return

	nail.hp -= damage
	barricade_damaged.emit(nail_id, damage)

	if nail.hp <= 0:
		_destroy_nail(nail_id)


## Destroy a nail (server-side)
func _destroy_nail(nail_id: int) -> void:
	if nail_id not in nails:
		return

	var nail: Dictionary = nails[nail_id]
	nail.active = false

	# Destroy physics joint
	if "joint_node" in nail and is_instance_valid(nail.joint_node):
		nail.joint_node.queue_free()

	# Notify clients
	NetworkManager.broadcast_event.rpc("nail_destroyed", {"nail_id": nail_id})

	barricade_destroyed.emit(nail_id)


## Destroy nail locally (client-side)
func _destroy_nail_local(nail_id: int) -> void:
	if nail_id in nails:
		nails[nail_id].active = false


## Get nearest active nail to position (for zombie targeting)
func get_nearest_nail(position: Vector3, max_distance: float = 3.0) -> int:
	var nearest_id := -1
	var nearest_dist := max_distance

	for nail_id in nails:
		var nail: Dictionary = nails[nail_id]
		if not nail.active:
			continue

		var dist: float = position.distance_to(nail.position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest_id = nail_id

	return nearest_id


# ============================================
# PROP SYSTEM
# ============================================

## Handle prop pickup (server-side)
func _handle_prop_pickup(peer_id: int, data: Dictionary) -> void:
	var prop_id: int = data.get("prop_id", -1)
	if prop_id < 0 or prop_id not in props:
		return

	var prop: RigidBody3D = props[prop_id]
	if not is_instance_valid(prop):
		return

	# Delegate to prop's pickup method
	if prop.has_method("pickup"):
		var success: bool = prop.pickup(peer_id)
		if success:
			# Notify clients
			NetworkManager.broadcast_event.rpc("prop_picked_up", {
				"prop_id": prop_id,
				"peer_id": peer_id,
			})


## Handle prop drop (server-side)
func _handle_prop_drop(peer_id: int, data: Dictionary) -> void:
	var prop_id: int = data.get("prop_id", -1)
	if prop_id < 0 or prop_id not in props:
		return

	var prop: RigidBody3D = props[prop_id]
	if not is_instance_valid(prop):
		return

	# Validate the peer owns this prop
	if prop.has_method("get_holder"):
		if prop.get_holder() != peer_id:
			return  # Can't drop what you're not holding

	# Delegate to prop's release method
	if prop.has_method("release"):
		prop.release()
		# Notify clients
		NetworkManager.broadcast_event.rpc("prop_dropped", {
			"prop_id": prop_id,
			"peer_id": peer_id,
		})


## Handle prop throw (server-side)
func _handle_prop_throw(peer_id: int, data: Dictionary) -> void:
	var prop_id: int = data.get("prop_id", -1)
	if prop_id < 0 or prop_id not in props:
		return

	var prop: RigidBody3D = props[prop_id]
	if not is_instance_valid(prop):
		return

	# Validate the peer owns this prop
	if prop.has_method("get_holder"):
		if prop.get_holder() != peer_id:
			return

	# Get throw direction
	var direction: Vector3 = data.get("direction", Vector3.FORWARD)
	direction = direction.normalized()

	# Delegate to prop's throw method
	if prop.has_method("throw_prop"):
		prop.throw_prop(direction)
		# Notify clients
		NetworkManager.broadcast_event.rpc("prop_thrown", {
			"prop_id": prop_id,
			"peer_id": peer_id,
			"direction": direction,
		})


## Handle hold update (rotation/distance changes while holding)
func _handle_prop_hold_update(peer_id: int, data: Dictionary) -> void:
	var prop_id: int = data.get("prop_id", -1)
	if prop_id < 0 or prop_id not in props:
		return

	var prop: RigidBody3D = props[prop_id]
	if not is_instance_valid(prop):
		return

	# Validate the peer owns this prop
	if prop.has_method("get_holder"):
		if prop.get_holder() != peer_id:
			return

	# Apply rotation delta
	var rotation_delta: Vector3 = data.get("rotation_delta", Vector3.ZERO)
	if rotation_delta.length() > 0.001:
		if prop.has_method("apply_rotation_delta"):
			prop.apply_rotation_delta(rotation_delta)

	# Apply distance delta
	var distance_delta: float = data.get("distance_delta", 0.0)
	if abs(distance_delta) > 0.001:
		if prop.has_method("adjust_hold_distance"):
			prop.adjust_hold_distance(distance_delta)


## Handle nail while holding (player places nail on held prop)
func _handle_nail_while_holding(peer_id: int, data: Dictionary) -> void:
	var prop_id: int = data.get("prop_id", -1)
	if prop_id < 0 or prop_id not in props:
		return

	var prop: RigidBody3D = props[prop_id]
	if not is_instance_valid(prop):
		return

	# Validate the peer owns this prop
	if prop.has_method("get_holder"):
		if prop.get_holder() != peer_id:
			return

	# Check if prop can accept another nail
	if prop.has_method("can_accept_nail"):
		if not prop.can_accept_nail():
			return  # Max nails reached

	# Validate nail placement
	var nail_data := {
		"prop_id": prop_id,
		"surface_id": data.get("surface_id", -1),
		"position": data.get("position", Vector3.ZERO),
		"normal": data.get("normal", Vector3.UP),
	}

	if not _validate_nail_placement(peer_id, nail_data):
		return

	# Create the nail
	var nail_id := _next_nail_id
	_next_nail_id += 1

	var full_nail_data := {
		"id": nail_id,
		"owner_id": peer_id,
		"prop_id": prop_id,
		"surface_id": nail_data.surface_id,
		"position": nail_data.position,
		"normal": nail_data.normal,
		"hp": randf_range(80.0, 120.0),
		"max_hp": 120.0,
		"repair_count": 0,
		"max_repairs": 3,
		"active": true,
	}

	nails[nail_id] = full_nail_data

	# Register nail with prop
	if prop.has_method("register_nail"):
		prop.register_nail(nail_id)

	# Release the prop (nailing drops it)
	if prop.has_method("release"):
		prop.release()

	# Create physics joint
	_create_nail_joint(full_nail_data)

	# Notify all clients
	NetworkManager.broadcast_event.rpc("nail_created", full_nail_data)
	NetworkManager.broadcast_event.rpc("prop_dropped", {
		"prop_id": prop_id,
		"peer_id": peer_id,
	})

	print("[GameState] Nail %d placed on prop %d by peer %d" % [nail_id, prop_id, peer_id])


## Register a prop (server-side)
func register_prop(prop: RigidBody3D) -> int:
	var prop_id := _next_prop_id
	_next_prop_id += 1

	prop.set("prop_id", prop_id)
	props[prop_id] = prop

	return prop_id


# ============================================
# PROP EVENTS (Client-Side)
# ============================================

## Handle prop pickup event (client-side)
func _handle_prop_picked_up_event(event_data: Dictionary) -> void:
	var prop_id: int = event_data.get("prop_id", -1)
	var peer_id: int = event_data.get("peer_id", -1)

	if prop_id < 0 or prop_id not in props:
		return

	var prop: RigidBody3D = props[prop_id]
	if not is_instance_valid(prop):
		return

	# Update local prop state
	prop.set("held_by_peer", peer_id)
	prop.set("current_mode", 1)  # PropMode.HELD
	prop.freeze = true

	# Notify local player's PropHandler if it's their pickup
	var local_peer := multiplayer.get_unique_id()
	if peer_id == local_peer and local_peer in players:
		var player: Node3D = players[local_peer]
		if player and player.has_method("get_prop_handler"):
			var handler = player.get_prop_handler()
			if handler and handler.has_method("on_pickup_confirmed"):
				handler.on_pickup_confirmed(prop_id)


## Handle prop dropped event (client-side)
func _handle_prop_dropped_event(event_data: Dictionary) -> void:
	var prop_id: int = event_data.get("prop_id", -1)
	var peer_id: int = event_data.get("peer_id", -1)

	if prop_id < 0 or prop_id not in props:
		return

	var prop: RigidBody3D = props[prop_id]
	if not is_instance_valid(prop):
		return

	# Update local prop state
	prop.set("held_by_peer", -1)
	# Mode will be set by apply_network_state based on nails
	prop.freeze = false

	# Notify local player's PropHandler if it was their prop
	var local_peer := multiplayer.get_unique_id()
	if peer_id == local_peer and local_peer in players:
		var player: Node3D = players[local_peer]
		if player and player.has_method("get_prop_handler"):
			var handler = player.get_prop_handler()
			if handler and handler.has_method("on_drop_confirmed"):
				handler.on_drop_confirmed()


## Handle prop thrown event (client-side)
func _handle_prop_thrown_event(event_data: Dictionary) -> void:
	var prop_id: int = event_data.get("prop_id", -1)
	var peer_id: int = event_data.get("peer_id", -1)
	var direction: Vector3 = event_data.get("direction", Vector3.FORWARD)

	if prop_id < 0 or prop_id not in props:
		return

	var prop: RigidBody3D = props[prop_id]
	if not is_instance_valid(prop):
		return

	# Update local prop state
	prop.set("held_by_peer", -1)
	prop.set("current_mode", 0)  # PropMode.FREE
	prop.freeze = false

	# Notify local player's PropHandler if it was their prop
	var local_peer := multiplayer.get_unique_id()
	if peer_id == local_peer and local_peer in players:
		var player: Node3D = players[local_peer]
		if player and player.has_method("get_prop_handler"):
			var handler = player.get_prop_handler()
			if handler and handler.has_method("on_drop_confirmed"):
				handler.on_drop_confirmed()


## Handle hit confirmed event (client-side, for visual effects)
func _handle_hit_confirmed_event(event_data: Dictionary) -> void:
	var position: Vector3 = event_data.get("position", Vector3.ZERO)
	var normal: Vector3 = event_data.get("normal", Vector3.UP)
	var target_type: String = event_data.get("target_type", "world")
	var is_headshot: bool = event_data.get("is_headshot", false)
	var shooter_id: int = event_data.get("shooter_id", -1)

	# Spawn hit effect at position
	# This would typically spawn a decal, particles, or blood effect
	# For now, emit signal so UI/effects can respond
	hit_confirmed.emit(shooter_id, event_data)

	# Local player gets hitmarker feedback
	var local_peer := multiplayer.get_unique_id()
	if shooter_id == local_peer and target_type != "world":
		# Could play hitmarker sound, show crosshair feedback, etc.
		pass


# ============================================
# COMBAT SYSTEM
# ============================================

## Handle shoot request (server-side)
func _handle_shoot(peer_id: int, data: Dictionary) -> void:
	if peer_id not in players:
		return

	var player: Node3D = players[peer_id]
	if not is_instance_valid(player):
		return

	# Server validates and performs raycast
	var origin: Vector3 = data.get("origin", Vector3.ZERO)
	var direction: Vector3 = data.get("direction", Vector3.FORWARD).normalized()
	var damage: float = data.get("damage", 25.0)
	var spread: float = data.get("spread", 0.0)
	var pellets: int = data.get("pellets", 1)  # For shotguns

	# Validate origin is near player's weapon position (anti-cheat)
	var player_pos: Vector3 = player.global_position
	if origin.distance_to(player_pos) > 3.0:
		push_warning("[GameState] Suspicious shot origin from peer %d" % peer_id)
		return

	# Validate player is alive
	var player_health: float = player.get("health") if player.has_method("get") else 100.0
	if player_health <= 0:
		return  # Dead players can't shoot

	# Process each pellet (1 for rifles/pistols, multiple for shotguns)
	for _pellet in range(pellets):
		var pellet_dir := direction

		# Apply server-side spread
		if spread > 0.0:
			pellet_dir = direction.rotated(Vector3.UP, randf_range(-spread, spread))
			pellet_dir = pellet_dir.rotated(direction.cross(Vector3.UP).normalized(), randf_range(-spread, spread))

		_perform_raycast_hit(peer_id, origin, pellet_dir, damage / pellets)


## Perform single raycast and register hit (server-side)
func _perform_raycast_hit(peer_id: int, origin: Vector3, direction: Vector3, damage: float) -> void:
	if not world_node:
		return

	var space_state := world_node.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * 1000.0)
	query.collision_mask = 0b00000111  # World (1), Players (2), Zombies (4)

	# Exclude the shooter
	if peer_id in players:
		var player: Node3D = players[peer_id]
		if player is CollisionObject3D:
			query.exclude = [player.get_rid()]

	var result := space_state.intersect_ray(query)

	if not result:
		return

	var collider: Node = result.collider
	var hit_position: Vector3 = result.position
	var hit_normal: Vector3 = result.normal

	# Build hit result
	var hit_data := {
		"shooter_id": peer_id,
		"position": hit_position,
		"normal": hit_normal,
		"damage": damage,
		"is_headshot": false,
		"target_type": "world",
		"target_id": -1,
	}

	# Check what we hit
	if collider.is_in_group("zombies"):
		var zombie_id: int = collider.get("zombie_id")
		hit_data["target_type"] = "zombie"
		hit_data["target_id"] = zombie_id

		# Check for headshot (if zombie has head hitbox or use height check)
		var zombie: Node3D = zombies.get(zombie_id)
		if zombie:
			var head_height: float = zombie.global_position.y + 1.5  # Approximate head height
			if hit_position.y > head_height:
				hit_data["is_headshot"] = true
				damage *= 2.0  # Headshot multiplier
				hit_data["damage"] = damage

		_damage_zombie(zombie_id, damage, hit_position)

	elif collider.is_in_group("players"):
		# Friendly fire check (disabled by default)
		var target_peer_id: int = collider.get("peer_id") if collider.has_method("get") else -1
		if target_peer_id > 0 and target_peer_id != peer_id:
			hit_data["target_type"] = "player"
			hit_data["target_id"] = target_peer_id
			# Uncomment to enable friendly fire:
			# _damage_player(target_peer_id, damage, hit_position)

	elif collider.is_in_group("props"):
		var prop_id: int = collider.get("prop_id") if collider.has_method("get") else -1
		hit_data["target_type"] = "prop"
		hit_data["target_id"] = prop_id
		# Props could take damage or apply impulse
		if collider is RigidBody3D:
			collider.apply_impulse(direction * damage * 0.5, hit_position - collider.global_position)

	# Broadcast hit confirmation for effects
	NetworkManager.broadcast_event.rpc("hit_confirmed", hit_data)
	hit_confirmed.emit(peer_id, hit_data)


## Damage a zombie (server-side)
func _damage_zombie(zombie_id: int, damage: float, hit_position: Vector3) -> void:
	if zombie_id not in zombies:
		return

	var zombie: Node3D = zombies[zombie_id]
	if not is_instance_valid(zombie):
		return

	if zombie.has_method("take_damage"):
		zombie.take_damage(damage, hit_position)

	# Check if zombie died
	var zombie_health: float = zombie.get("health") if zombie.has_method("get") else 0.0
	if zombie_health <= 0:
		kill_zombie(zombie_id)


## Damage a player (server-side, for friendly fire if enabled)
func _damage_player(target_peer_id: int, damage: float, hit_position: Vector3) -> void:
	if target_peer_id not in players:
		return

	var player: Node3D = players[target_peer_id]
	if not is_instance_valid(player):
		return

	if player.has_method("take_damage"):
		player.take_damage(damage, hit_position)


# ============================================
# WAVE SYSTEM
# ============================================

## Start the game (server-side)
func start_game() -> void:
	if not NetworkManager.is_authority():
		return

	current_phase = GamePhase.PREPARING
	phase_changed.emit(current_phase)

	# Start first wave after delay
	await get_tree().create_timer(5.0).timeout
	_start_wave(1)


## Start a wave (server-side)
func _start_wave(wave_number: int) -> void:
	current_wave = wave_number
	current_phase = GamePhase.WAVE_ACTIVE

	# Calculate zombie count
	var player_count := players.size()
	var zombie_count := player_count * (5 + wave_number * 2)
	wave_zombies_remaining = zombie_count
	wave_zombies_killed = 0

	# Notify clients
	NetworkManager.broadcast_event.rpc("wave_start", {
		"wave": wave_number,
		"zombie_count": zombie_count
	})

	wave_started.emit(wave_number)
	phase_changed.emit(current_phase)


## End current wave (server-side)
func _end_wave() -> void:
	current_phase = GamePhase.WAVE_INTERMISSION

	NetworkManager.broadcast_event.rpc("wave_end", {
		"wave": current_wave,
		"kills": wave_zombies_killed
	})

	wave_ended.emit(current_wave)
	phase_changed.emit(current_phase)

	# Check for victory (survived all waves)
	if current_wave >= MAX_WAVES:
		_trigger_victory("Survived all waves!")
		return

	# Check if extraction should unlock
	if current_wave >= EXTRACTION_UNLOCK_WAVE and not extraction_active:
		_unlock_extraction()

	# Start next wave after intermission
	await get_tree().create_timer(30.0).timeout

	# Don't start next wave if game ended
	if current_phase == GamePhase.GAME_OVER:
		return

	_start_wave(current_wave + 1)


# ============================================
# GAME OVER / VICTORY SYSTEM
# ============================================

## Check if all players are dead (server-side)
func _check_all_players_dead() -> void:
	if not NetworkManager.is_authority():
		return

	if current_phase == GamePhase.GAME_OVER:
		return

	var alive_count := 0
	for peer_id in players:
		var player: Node3D = players[peer_id]
		if is_instance_valid(player):
			var is_dead: bool = player.get("is_dead") if player.has_method("get") else false
			if not is_dead:
				alive_count += 1

	# Also count extracted players as "survived"
	var total_survived := alive_count + extracted_players.size()

	if total_survived == 0 and players.size() > 0:
		_trigger_game_over("All players eliminated")


## Track player death
func _on_player_death_tracked(peer_id: int) -> void:
	if peer_id not in dead_players:
		dead_players.append(peer_id)

	# Check if all players are now dead
	_check_all_players_dead()


## Trigger game over (defeat)
func _trigger_game_over(reason: String) -> void:
	if current_phase == GamePhase.GAME_OVER:
		return

	current_phase = GamePhase.GAME_OVER
	phase_changed.emit(current_phase)

	print("[GameState] GAME OVER: %s" % reason)

	# Notify clients
	NetworkManager.broadcast_event.rpc("game_over", {
		"reason": reason,
		"victory": false,
		"wave": current_wave,
		"kills": wave_zombies_killed,
	})

	game_over.emit(reason, false)

	# Report to backend
	if HeadlessServer and HeadlessServer.is_headless:
		HeadlessServer.report_match_end("defeat")


## Trigger victory
func _trigger_victory(reason: String) -> void:
	if current_phase == GamePhase.GAME_OVER:
		return

	current_phase = GamePhase.GAME_OVER
	phase_changed.emit(current_phase)

	print("[GameState] VICTORY: %s" % reason)

	# Notify clients
	NetworkManager.broadcast_event.rpc("game_over", {
		"reason": reason,
		"victory": true,
		"wave": current_wave,
		"kills": wave_zombies_killed,
		"extracted": extracted_players.size(),
	})

	game_over.emit(reason, true)

	# Report to backend
	if HeadlessServer and HeadlessServer.is_headless:
		HeadlessServer.report_match_end("victory")


## Unlock extraction (after wave threshold)
func _unlock_extraction() -> void:
	extraction_active = true

	print("[GameState] Extraction unlocked at wave %d!" % current_wave)

	# Notify clients
	NetworkManager.broadcast_event.rpc("extraction_unlocked", {
		"wave": current_wave
	})

	extraction_available.emit()


## Player extracts (server-side)
func extract_player(peer_id: int) -> void:
	if not NetworkManager.is_authority():
		return

	if not extraction_active:
		return

	if peer_id in extracted_players:
		return

	extracted_players.append(peer_id)

	print("[GameState] Player %d extracted!" % peer_id)

	# Remove player from world
	if peer_id in players:
		var player: Node3D = players[peer_id]
		if is_instance_valid(player):
			player.queue_free()
		players.erase(peer_id)

	# Notify clients
	NetworkManager.broadcast_event.rpc("player_extracted", {
		"peer_id": peer_id
	})

	player_extracted.emit(peer_id)

	# Check if all remaining players extracted
	if players.is_empty() and extracted_players.size() > 0:
		_trigger_victory("All players extracted!")


## Check if extraction is available
func is_extraction_available() -> bool:
	return extraction_active


## Get game end stats
func get_game_stats() -> Dictionary:
	return {
		"wave": current_wave,
		"kills": wave_zombies_killed,
		"extracted": extracted_players.size(),
		"dead": dead_players.size(),
		"victory": current_phase == GamePhase.GAME_OVER and extracted_players.size() > 0,
	}


# ============================================
# FULL SNAPSHOT (JOIN-IN-PROGRESS)
# ============================================

## Apply full world snapshot from server (client-side, for late joiners)
func apply_full_snapshot(state: Dictionary) -> void:
	print("[GameState] Applying full snapshot...")

	# Apply basic state
	if "wave" in state:
		current_wave = state.wave
	if "phase" in state:
		current_phase = state.phase as GamePhase

	# Reconstruct players
	if "players" in state:
		for player_data in state.players:
			var peer_id: int = player_data.id
			var position: Vector3 = player_data.get("position", Vector3.ZERO)
			_spawn_player_local(peer_id, position)

			# Apply additional state
			if peer_id in players:
				var player: Node3D = players[peer_id]
				if player_data.has("health"):
					player.set("health", player_data.health)
				if player_data.has("is_dead"):
					player.set("is_dead", player_data.is_dead)

	# Reconstruct zombies
	if "zombies" in state:
		for zombie_data in state.zombies:
			var zombie_id: int = zombie_data.id
			var position: Vector3 = zombie_data.position
			var zombie_type: String = _zombie_type_to_string(zombie_data.get("type", 0))

			_spawn_zombie_local(zombie_id, position, zombie_type)

			# Apply state
			if zombie_id in zombies:
				var zombie: Node3D = zombies[zombie_id]
				zombie.set("health", zombie_data.get("health", 100))
				zombie.set("current_state", zombie_data.get("state", 0))
				zombie.rotation.y = zombie_data.get("rotation", 0)

			# Track highest ID for server sync
			_next_zombie_id = maxi(_next_zombie_id, zombie_id + 1)

	# Reconstruct props (apply state to existing props)
	if "props" in state:
		for prop_data in state.props:
			var prop_id: int = prop_data.id
			if prop_id in props:
				var prop: RigidBody3D = props[prop_id] as RigidBody3D
				if prop:
					prop.global_position = prop_data.position
					prop.rotation = prop_data.rotation
					prop.sleeping = prop_data.get("sleeping", false)
					prop.linear_velocity = prop_data.get("linear_velocity", Vector3.ZERO)
					prop.angular_velocity = prop_data.get("angular_velocity", Vector3.ZERO)

	# Reconstruct nails with joints
	if "nails" in state:
		for nail_data in state.nails:
			_reconstruct_nail(nail_data)

	print("[GameState] Full snapshot applied: %d players, %d zombies, %d nails" % [
		players.size(), zombies.size(), nails.size()
	])


## Reconstruct a nail from snapshot data (client-side)
func _reconstruct_nail(nail_data: Dictionary) -> void:
	var nail_id: int = nail_data.id

	# Store nail data
	var local_nail := {
		"id": nail_id,
		"owner_id": nail_data.owner_id,
		"prop_id": nail_data.prop_id,
		"surface_id": nail_data.surface_id,
		"position": nail_data.position,
		"normal": nail_data.normal,
		"hp": nail_data.hp,
		"max_hp": nail_data.max_hp,
		"repair_count": nail_data.repair_count,
		"active": true,
	}

	nails[nail_id] = local_nail

	# Track highest ID
	_next_nail_id = maxi(_next_nail_id, nail_id + 1)

	# Clients don't create joints - server owns physics
	# But we store the data for UI/targeting


func _zombie_type_to_string(type_int: int) -> String:
	match type_int:
		0: return "walker"
		1: return "runner"
		2: return "brute"
		3: return "crawler"
	return "walker"


# ============================================
# PROP REGISTRY (Server-Authoritative)
# ============================================

# Original prop positions for round reset
var _prop_registry: Dictionary = {}  # prop_id -> { scene_path, original_position, original_rotation }


## Register a prop with its original state (server-side, called at world init)
func register_prop_with_state(prop: RigidBody3D, scene_path: String = "") -> int:
	var prop_id := _next_prop_id
	_next_prop_id += 1

	prop.set("prop_id", prop_id)
	props[prop_id] = prop

	# Store original state for reset
	_prop_registry[prop_id] = {
		"scene_path": scene_path,
		"original_position": prop.global_position,
		"original_rotation": prop.rotation,
		"original_mass": prop.mass,
	}

	return prop_id


## Get prop's original state
func get_prop_original_state(prop_id: int) -> Dictionary:
	return _prop_registry.get(prop_id, {})


# ============================================
# ROUND RESET (Clean World Lifecycle)
# ============================================

signal round_reset_started
signal round_reset_completed


## Full round reset (server-side only)
func reset_round() -> void:
	if not NetworkManager.is_authority():
		return

	round_reset_started.emit()
	print("[GameState] Starting round reset...")

	# 1. Destroy all joints (nails)
	_cleanup_all_nails()

	# 2. Kill all zombies
	_cleanup_all_zombies()

	# 3. Reset props to original positions
	_reset_all_props()

	# 4. Respawn all players
	_respawn_all_players()

	# 5. Reset wave state
	current_wave = 0
	wave_zombies_remaining = 0
	wave_zombies_killed = 0
	current_phase = GamePhase.LOBBY

	# 6. Reset ID counters (optional, keeps them for debugging)
	# _next_nail_id = 1
	# _next_zombie_id = 1

	# Notify clients
	NetworkManager.broadcast_event.rpc("round_reset", {})

	round_reset_completed.emit()
	print("[GameState] Round reset complete")


## Cleanup all nails with guaranteed joint destruction
func _cleanup_all_nails() -> void:
	var nail_ids := nails.keys()
	for nail_id in nail_ids:
		var nail: Dictionary = nails[nail_id]

		# Destroy joint first
		if nail.has("joint_node") and is_instance_valid(nail.joint_node):
			nail.joint_node.queue_free()

		# Unregister from prop
		if nail.prop_id in props:
			var prop = props[nail.prop_id]
			if prop and prop.has_method("unregister_nail"):
				prop.unregister_nail(nail_id)

	# Clear nails dictionary
	nails.clear()

	# Notify clients
	NetworkManager.broadcast_event.rpc("nails_cleared", {})


## Cleanup all zombies
func _cleanup_all_zombies() -> void:
	var zombie_ids := zombies.keys()
	for zombie_id in zombie_ids:
		var zombie: Node3D = zombies[zombie_id]
		if is_instance_valid(zombie):
			zombie.queue_free()

	zombies.clear()


## Reset all props to original positions
func _reset_all_props() -> void:
	for prop_id in props:
		var prop: RigidBody3D = props[prop_id] as RigidBody3D
		if not is_instance_valid(prop):
			continue

		# Clear attached nails tracking
		if prop.has_method("get"):
			var attached: Array = prop.get("attached_nail_ids")
			if attached:
				attached.clear()

		# Reset to original state
		if prop_id in _prop_registry:
			var original: Dictionary = _prop_registry[prop_id]
			prop.global_position = original.original_position
			prop.rotation = original.original_rotation
			prop.linear_velocity = Vector3.ZERO
			prop.angular_velocity = Vector3.ZERO
			prop.sleeping = false

			# Wake up then let physics settle
			await get_tree().physics_frame
			prop.sleeping = true


## Respawn all players at spawn points
func _respawn_all_players() -> void:
	# Get spawn points from world
	var spawn_points: Array[Vector3] = []
	if world_node:
		var spawn_container := world_node.get_node_or_null("SpawnPoints")
		if spawn_container:
			for child in spawn_container.get_children():
				if child is Node3D and child.name.begins_with("PlayerSpawn"):
					spawn_points.append(child.global_position)

	# Default spawn points
	if spawn_points.is_empty():
		spawn_points = [Vector3(0, 1, 0), Vector3(2, 1, 0), Vector3(-2, 1, 0)]

	# Respawn each player
	var idx := 0
	for peer_id in players:
		var player = players[peer_id]
		if is_instance_valid(player) and player.has_method("respawn"):
			var spawn_pos := spawn_points[idx % spawn_points.size()]
			player.respawn(spawn_pos)
			idx += 1


## Handle round_reset event (client-side)
func _handle_round_reset() -> void:
	# Clear local state
	nails.clear()

	# Zombies will be cleaned up by their queue_free


# Update handle_event to include new events
func _handle_additional_events(event_type: String, event_data: Dictionary) -> void:
	match event_type:
		"nails_cleared":
			nails.clear()
		"round_reset":
			_handle_round_reset()
