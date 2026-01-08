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

	return {
		"tick": Engine.get_physics_frames(),
		"players": player_states,
		"zombies": zombie_states,
		"nails": nail_states,
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
	# TODO: Implement prop carrying
	pass


## Handle prop drop (server-side)
func _handle_prop_drop(peer_id: int, data: Dictionary) -> void:
	# TODO: Implement prop dropping
	pass


## Register a prop (server-side)
func register_prop(prop: RigidBody3D) -> int:
	var prop_id := _next_prop_id
	_next_prop_id += 1

	prop.set("prop_id", prop_id)
	props[prop_id] = prop

	return prop_id


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
	var origin: Vector3 = data.origin
	var direction: Vector3 = data.direction

	# Validate origin is near player's weapon position
	# (anti-cheat: can't shoot from across map)
	var player_pos: Vector3 = player.global_position
	if origin.distance_to(player_pos) > 3.0:
		return  # Suspicious

	# Perform raycast
	var space_state := world_node.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * 1000.0)
	query.collision_mask = 0b00000111  # World, Players, Zombies

	var result := space_state.intersect_ray(query)

	if result:
		var collider: Node = result.collider

		# Check if hit zombie
		if collider.is_in_group("zombies"):
			var zombie_id: int = collider.get("zombie_id")
			var damage: float = data.get("damage", 25.0)
			_damage_zombie(zombie_id, damage, result.position)


## Damage a zombie (server-side)
func _damage_zombie(zombie_id: int, damage: float, hit_position: Vector3) -> void:
	if zombie_id not in zombies:
		return

	var zombie: Node3D = zombies[zombie_id]
	if not is_instance_valid(zombie):
		return

	if zombie.has_method("take_damage"):
		zombie.take_damage(damage, hit_position)


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

	# Start next wave after intermission
	await get_tree().create_timer(30.0).timeout
	_start_wave(current_wave + 1)


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
