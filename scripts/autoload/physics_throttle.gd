extends Node
## PhysicsThrottle - Performance optimization for physics
##
## Manages physics simulation throttling based on:
## - Distance from active players
## - Entity importance (zombies near players vs far)
## - Sleep state management
## - LOD for AI updates

# Configuration
const NEAR_DISTANCE := 20.0
const MID_DISTANCE := 40.0
const FAR_DISTANCE := 60.0
const CULL_DISTANCE := 100.0

const NEAR_TICK_RATE := 1    # Every tick
const MID_TICK_RATE := 2     # Every 2nd tick
const FAR_TICK_RATE := 4     # Every 4th tick
const VERY_FAR_TICK_RATE := 8  # Every 8th tick

# Tick counter
var tick_counter := 0

# Entity tracking
var throttled_entities: Dictionary = {}  # node_path -> ThrottleData

class ThrottleData:
	var node: Node
	var distance_to_player: float = 0.0
	var tick_rate: int = NEAR_TICK_RATE
	var last_update_tick: int = 0
	var is_sleeping: bool = false
	var importance: float = 1.0  # Higher = more frequent updates


func _ready() -> void:
	# Process on physics tick
	set_physics_process(true)


func _physics_process(_delta: float) -> void:
	if not NetworkManager.is_authority():
		return

	tick_counter += 1

	# Update throttle data periodically (not every tick)
	if tick_counter % 10 == 0:
		_update_all_distances()

	# Process zombies
	_process_zombie_throttling()

	# Process props
	_process_prop_throttling()


## Update distances for all tracked entities
func _update_all_distances() -> void:
	# Get average player position (or centroid)
	var player_positions: Array[Vector3] = []
	for peer_id in GameState.players:
		var player: Node3D = GameState.players[peer_id]
		if is_instance_valid(player) and not player.get("is_dead"):
			player_positions.append(player.global_position)

	if player_positions.is_empty():
		return

	# Calculate centroid
	var centroid := Vector3.ZERO
	for pos in player_positions:
		centroid += pos
	centroid /= player_positions.size()

	# Update zombie distances
	for zombie_id in GameState.zombies:
		var zombie: Node3D = GameState.zombies[zombie_id]
		if not is_instance_valid(zombie):
			continue

		var min_dist := INF
		for pos in player_positions:
			var dist := zombie.global_position.distance_to(pos)
			min_dist = minf(min_dist, dist)

		_update_entity_throttle(zombie, min_dist, true)

	# Update prop distances
	for prop_id in GameState.props:
		var prop: Node3D = GameState.props[prop_id]
		if not is_instance_valid(prop):
			continue

		var dist := prop.global_position.distance_to(centroid)
		_update_entity_throttle(prop, dist, false)


## Update throttle data for an entity
func _update_entity_throttle(entity: Node, distance: float, is_zombie: bool) -> void:
	var path := entity.get_path()

	if path not in throttled_entities:
		var data := ThrottleData.new()
		data.node = entity
		throttled_entities[path] = data

	var data: ThrottleData = throttled_entities[path]
	data.distance_to_player = distance

	# Determine tick rate based on distance
	if distance < NEAR_DISTANCE:
		data.tick_rate = NEAR_TICK_RATE
	elif distance < MID_DISTANCE:
		data.tick_rate = MID_TICK_RATE
	elif distance < FAR_DISTANCE:
		data.tick_rate = FAR_TICK_RATE
	else:
		data.tick_rate = VERY_FAR_TICK_RATE

	# Zombies that are targeting get higher priority
	if is_zombie and "current_state" in entity:
		var state = entity.current_state
		if state in [1, 2, 3, 4]:  # AGGRO, PATH, ATTACK_PLAYER, ATTACK_NAIL
			data.importance = 2.0
			data.tick_rate = maxi(data.tick_rate / 2, 1)
		else:
			data.importance = 1.0


## Process zombie throttling
func _process_zombie_throttling() -> void:
	for zombie_id in GameState.zombies:
		var zombie: ZombieController = GameState.zombies[zombie_id] as ZombieController
		if not is_instance_valid(zombie):
			continue

		var path := zombie.get_path()
		if path not in throttled_entities:
			continue

		var data: ThrottleData = throttled_entities[path]

		# Check if should update this tick
		if tick_counter - data.last_update_tick < data.tick_rate:
			# Skip this zombie's AI this tick
			zombie.set_physics_process(false)
		else:
			zombie.set_physics_process(true)
			data.last_update_tick = tick_counter

		# Cull very far zombies (optional - could despawn instead)
		if data.distance_to_player > CULL_DISTANCE:
			# Slow down significantly
			zombie.set_physics_process(tick_counter % 16 == 0)


## Process prop throttling (sleep management)
func _process_prop_throttling() -> void:
	for prop_id in GameState.props:
		var prop: RigidBody3D = GameState.props[prop_id] as RigidBody3D
		if not is_instance_valid(prop):
			continue

		var path := prop.get_path()
		if path not in throttled_entities:
			continue

		var data: ThrottleData = throttled_entities[path]

		# Aggressive sleep for distant props
		if data.distance_to_player > FAR_DISTANCE:
			if not prop.sleeping and prop.linear_velocity.length() < 0.1:
				prop.sleeping = true
				data.is_sleeping = true
		else:
			# Let physics decide sleep state for near props
			data.is_sleeping = prop.sleeping


## Check if entity should update this tick
func should_update(entity: Node) -> bool:
	var path := entity.get_path()
	if path not in throttled_entities:
		return true

	var data: ThrottleData = throttled_entities[path]
	return tick_counter - data.last_update_tick >= data.tick_rate


## Get throttle info for debugging
func get_throttle_stats() -> Dictionary:
	var near_count := 0
	var mid_count := 0
	var far_count := 0
	var sleeping_count := 0

	for path in throttled_entities:
		var data: ThrottleData = throttled_entities[path]
		if data.distance_to_player < NEAR_DISTANCE:
			near_count += 1
		elif data.distance_to_player < MID_DISTANCE:
			mid_count += 1
		else:
			far_count += 1

		if data.is_sleeping:
			sleeping_count += 1

	return {
		"total": throttled_entities.size(),
		"near": near_count,
		"mid": mid_count,
		"far": far_count,
		"sleeping": sleeping_count,
	}


## Remove entity from tracking
func unregister_entity(entity: Node) -> void:
	var path := entity.get_path()
	throttled_entities.erase(path)


## Force wake a prop (when zombie attacks nearby)
func wake_nearby_props(position: Vector3, radius: float = 5.0) -> void:
	for prop_id in GameState.props:
		var prop: RigidBody3D = GameState.props[prop_id] as RigidBody3D
		if not is_instance_valid(prop):
			continue

		if prop.global_position.distance_to(position) < radius:
			prop.sleeping = false
