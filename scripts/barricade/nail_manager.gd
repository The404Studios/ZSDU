extends Node
class_name NailManager
## NailManager - Server-side nail authority
##
## JetBoom mechanics:
## - Nail HP with random variance
## - Repair with diminishing returns (max HP decays)
## - Ownership tracking
## - Exploit prevention (silent rejects)
## - Cascading failure detection

signal nail_created(nail_id: int, data: Dictionary)
signal nail_damaged(nail_id: int, damage: float, hp_remaining: float)
signal nail_destroyed(nail_id: int)
signal nail_repaired(nail_id: int, amount: float)
signal cascade_failure(nail_ids: Array)

# Configuration
const MAX_NAILS_PER_PROP := 3
const MAX_TOTAL_NAILS := 500
const MIN_NAIL_DISTANCE := 0.25
const MAX_REACH := 4.5
const NAIL_HP_MIN := 70.0
const NAIL_HP_MAX := 130.0
const REPAIR_AMOUNT_BASE := 35.0
const REPAIR_DEGRADATION := 0.20  # Each repair reduces max HP by 20%
const MAX_REPAIRS := 4
const NAIL_COOLDOWN := 0.25

# Player cooldowns (anti-spam)
var player_cooldowns: Dictionary = {}  # peer_id -> last_nail_time

# Nail data storage (separate from GameState for clean separation)
# GameState.nails is the source of truth, this manages logic


func _ready() -> void:
	# Connect to GameState signals for cascade detection
	if GameState:
		GameState.barricade_destroyed.connect(_on_nail_destroyed)


## Validate and create nail (server-side entry point)
func request_nail_placement(peer_id: int, data: Dictionary) -> Dictionary:
	var result := {
		"success": false,
		"reason": "",
		"nail_id": -1
	}

	# Silent reject checks (no feedback to client = harder to exploit)

	# 1. Player exists and is valid
	if peer_id not in GameState.players:
		return result

	var player: Node3D = GameState.players[peer_id]
	if not is_instance_valid(player):
		return result

	# 2. Cooldown check
	var current_time := Time.get_ticks_msec() / 1000.0
	if peer_id in player_cooldowns:
		if current_time - player_cooldowns[peer_id] < NAIL_COOLDOWN:
			return result

	# 3. Required data present
	if not data.has_all(["prop_id", "position", "normal"]):
		return result

	var prop_id: int = data.prop_id
	var position: Vector3 = data.position
	var normal: Vector3 = data.normal
	var surface_id: int = data.get("surface_id", -1)

	# 4. Prop exists
	if prop_id not in GameState.props:
		return result

	var prop: BarricadeProp = GameState.props[prop_id] as BarricadeProp
	if not is_instance_valid(prop):
		return result

	# 5. Prop not being carried
	if prop.is_carried:
		return result

	# 6. Distance check (anti-teleport)
	var player_pos: Vector3 = player.global_position
	if player_pos.distance_to(position) > MAX_REACH:
		return result

	# 7. Position near prop (anti-fake-position)
	var prop_distance := _distance_to_surface(position, prop)
	if prop_distance > 1.0:
		return result

	# 8. Max nails per prop
	var existing_nails := _count_nails_on_prop(prop_id)
	if existing_nails >= MAX_NAILS_PER_PROP:
		return result

	# 9. Total nail limit
	if GameState.nails.size() >= MAX_TOTAL_NAILS:
		return result

	# 10. No nail stacking
	if _has_nearby_nail(position, prop_id):
		return result

	# 11. Surface validation (if nailing to another prop)
	if surface_id >= 0:
		if surface_id not in GameState.props:
			return result

		var surface_prop: BarricadeProp = GameState.props[surface_id] as BarricadeProp
		if not is_instance_valid(surface_prop):
			return result

		if surface_prop.is_carried:
			return result

	# 12. Normal validation (prevent impossible angles)
	if normal.length() < 0.5 or normal.length() > 1.5:
		normal = Vector3.UP  # Sanitize

	# All checks passed - create nail
	var nail_id := GameState._next_nail_id
	GameState._next_nail_id += 1

	var nail_hp := randf_range(NAIL_HP_MIN, NAIL_HP_MAX)

	var nail_data := {
		"id": nail_id,
		"owner_id": peer_id,
		"prop_id": prop_id,
		"surface_id": surface_id,
		"position": position,
		"normal": normal,
		"hp": nail_hp,
		"max_hp": nail_hp,
		"base_max_hp": nail_hp,  # Original max for degradation calc
		"repair_count": 0,
		"max_repairs": MAX_REPAIRS,
		"active": true,
		"created_at": current_time,
	}

	GameState.nails[nail_id] = nail_data

	# Create physics joint
	_create_joint(nail_data)

	# Register with prop
	prop.register_nail(nail_id)

	# Update cooldown
	player_cooldowns[peer_id] = current_time

	# Notify
	nail_created.emit(nail_id, nail_data)

	# Broadcast to clients
	NetworkManager.broadcast_event.rpc("nail_created", nail_data)

	result.success = true
	result.nail_id = nail_id
	return result


## Validate and repair nail (server-side)
func request_nail_repair(peer_id: int, nail_id: int) -> Dictionary:
	var result := {
		"success": false,
		"reason": "",
		"repaired_amount": 0.0
	}

	# Validation
	if peer_id not in GameState.players:
		return result

	var player: Node3D = GameState.players[peer_id]
	if not is_instance_valid(player):
		return result

	if nail_id not in GameState.nails:
		return result

	var nail: Dictionary = GameState.nails[nail_id]

	if not nail.active:
		return result

	# Distance check
	var player_pos: Vector3 = player.global_position
	if player_pos.distance_to(nail.position) > MAX_REACH:
		return result

	# Repair count check (JetBoom diminishing returns)
	if nail.repair_count >= nail.max_repairs:
		result.reason = "max_repairs"
		return result

	# Already full HP
	if nail.hp >= nail.max_hp - 0.1:
		result.reason = "full_hp"
		return result

	# Calculate repair with degradation
	var repair_mult := 1.0 - (nail.repair_count * REPAIR_DEGRADATION * 0.5)
	var repair_amount := REPAIR_AMOUNT_BASE * repair_mult

	# Reduce max HP (diminishing returns)
	var new_max_hp := nail.base_max_hp * (1.0 - nail.repair_count * REPAIR_DEGRADATION)
	nail.max_hp = maxf(new_max_hp, NAIL_HP_MIN * 0.5)  # Floor at 50% of min

	# Apply repair
	nail.hp = minf(nail.hp + repair_amount, nail.max_hp)
	nail.repair_count += 1

	nail_repaired.emit(nail_id, repair_amount)

	result.success = true
	result.repaired_amount = repair_amount
	return result


## Damage a nail (called by zombies, server-side)
func damage_nail(nail_id: int, damage: float, attacker_pos: Vector3 = Vector3.ZERO) -> void:
	if nail_id not in GameState.nails:
		return

	var nail: Dictionary = GameState.nails[nail_id]
	if not nail.active:
		return

	nail.hp -= damage
	nail_damaged.emit(nail_id, damage, nail.hp)

	if nail.hp <= 0:
		destroy_nail(nail_id)


## Destroy a nail (server-side)
func destroy_nail(nail_id: int) -> void:
	if nail_id not in GameState.nails:
		return

	var nail: Dictionary = GameState.nails[nail_id]
	nail.active = false
	nail.hp = 0

	# Destroy physics joint
	if nail.has("joint_node") and is_instance_valid(nail.joint_node):
		nail.joint_node.queue_free()

	# Unregister from prop
	if nail.prop_id in GameState.props:
		var prop: BarricadeProp = GameState.props[nail.prop_id] as BarricadeProp
		if prop:
			prop.unregister_nail(nail_id)

	nail_destroyed.emit(nail_id)

	# Broadcast
	NetworkManager.broadcast_event.rpc("nail_destroyed", {"nail_id": nail_id})

	# Check for cascade failures
	_check_cascade_failure(nail)


## Check for cascading barricade failure
func _check_cascade_failure(destroyed_nail: Dictionary) -> void:
	var prop_id: int = destroyed_nail.prop_id

	if prop_id not in GameState.props:
		return

	var prop: BarricadeProp = GameState.props[prop_id] as BarricadeProp
	if not prop:
		return

	# Check if prop still has supporting nails
	var remaining_nails := 0
	for nail_id in prop.attached_nail_ids:
		if nail_id in GameState.nails and GameState.nails[nail_id].active:
			remaining_nails += 1

	# If no nails left, prop is free
	if remaining_nails == 0:
		# Prop will fall naturally due to physics
		# Check if this prop was supporting others
		_check_supported_props(prop)


## Check props that were supported by this one
func _check_supported_props(freed_prop: BarricadeProp) -> void:
	var cascade_nail_ids: Array[int] = []

	# Find nails that were using this prop as a surface
	for nail_id in GameState.nails:
		var nail: Dictionary = GameState.nails[nail_id]
		if not nail.active:
			continue

		if nail.surface_id == freed_prop.prop_id:
			# This nail was attached to the freed prop
			cascade_nail_ids.append(nail_id)

	# Destroy cascading nails
	if cascade_nail_ids.size() > 0:
		cascade_failure.emit(cascade_nail_ids)

		for nail_id in cascade_nail_ids:
			destroy_nail(nail_id)


## Create physics joint for nail
func _create_joint(nail_data: Dictionary) -> void:
	var prop_id: int = nail_data.prop_id
	if prop_id not in GameState.props:
		return

	var prop: RigidBody3D = GameState.props[prop_id] as RigidBody3D
	if not prop:
		return

	# Create pin joint
	var joint := PinJoint3D.new()
	joint.name = "Nail_%d" % nail_data.id
	joint.global_position = nail_data.position

	# Configure based on surface
	if nail_data.surface_id == -1:
		# Nail to world
		joint.node_a = prop.get_path()
		# node_b empty = world
	else:
		# Nail to another prop
		if nail_data.surface_id in GameState.props:
			var surface_prop: RigidBody3D = GameState.props[nail_data.surface_id] as RigidBody3D
			if surface_prop:
				joint.node_a = prop.get_path()
				joint.node_b = surface_prop.get_path()

	# Add to world
	if GameState.world_node:
		GameState.world_node.add_child(joint)

	nail_data["joint_node"] = joint


## Count nails on a prop
func _count_nails_on_prop(prop_id: int) -> int:
	var count := 0
	for nail_id in GameState.nails:
		var nail: Dictionary = GameState.nails[nail_id]
		if nail.active and nail.prop_id == prop_id:
			count += 1
	return count


## Check for nearby nails (stacking prevention)
func _has_nearby_nail(position: Vector3, prop_id: int) -> bool:
	for nail_id in GameState.nails:
		var nail: Dictionary = GameState.nails[nail_id]
		if not nail.active:
			continue
		if nail.prop_id != prop_id:
			continue

		var dist := position.distance_to(nail.position)
		if dist < MIN_NAIL_DISTANCE:
			return true

	return false


## Calculate distance to prop surface (rough approximation)
func _distance_to_surface(point: Vector3, prop: RigidBody3D) -> float:
	# Use AABB as approximation
	var aabb := AABB(Vector3.ZERO, Vector3.ONE)

	if prop.has_node("CollisionShape3D"):
		var collision_shape = prop.get_node("CollisionShape3D")
		if collision_shape and collision_shape.shape:
			var debug_mesh = collision_shape.shape.get_debug_mesh()
			if debug_mesh:
				aabb = debug_mesh.get_aabb()

	aabb.position += prop.global_position

	var closest := aabb.position + aabb.size * 0.5
	closest.x = clampf(point.x, aabb.position.x, aabb.position.x + aabb.size.x)
	closest.y = clampf(point.y, aabb.position.y, aabb.position.y + aabb.size.y)
	closest.z = clampf(point.z, aabb.position.z, aabb.position.z + aabb.size.z)

	return point.distance_to(closest)


## Handle nail destroyed callback
func _on_nail_destroyed(nail_id: int) -> void:
	# Additional cleanup if needed
	pass


## Get nail info for UI
func get_nail_info(nail_id: int) -> Dictionary:
	if nail_id not in GameState.nails:
		return {}

	var nail: Dictionary = GameState.nails[nail_id]
	return {
		"id": nail_id,
		"hp": nail.hp,
		"max_hp": nail.max_hp,
		"repair_count": nail.repair_count,
		"can_repair": nail.repair_count < nail.max_repairs,
		"owner_id": nail.owner_id,
	}
