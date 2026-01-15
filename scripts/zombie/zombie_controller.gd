extends CharacterBody3D
class_name ZombieController
## ZombieController - Server-authoritative zombie AI
##
## JetBoom philosophy:
## - Zombies attack NAILS, not props
## - Simple state machine, not behavior trees
## - Group logic saves CPU
## - Physics creates emergent intelligence

# Zombie states
enum ZombieState {
	IDLE,
	AGGRO,
	PATH,
	ATTACK_PLAYER,
	ATTACK_NAIL,
	STAGGER,
	DEAD
}

# Zombie types affect stats
enum ZombieType {
	WALKER,      # Basic, slow
	RUNNER,      # Fast, weak
	BRUTE,       # Slow, tanky, high damage
	CRAWLER,     # Low, can fit under gaps
	SPITTER,     # Ranged acid attack
	SCREAMER,    # Calls more zombies when aggro
	EXPLODER,    # Explodes on death or when near player
	BOSS,        # Very tanky boss zombie
}

# Base stats (modified by type and wave)
const BASE_HEALTH := 100.0
const BASE_SPEED := 3.0
const BASE_DAMAGE := 15.0
const BASE_ATTACK_RATE := 1.0

# Current stats
@export var zombie_type: ZombieType = ZombieType.WALKER:
	set(value):
		zombie_type = value
		# Reapply modifiers when type changes
		if is_inside_tree():
			_apply_type_modifiers()
var zombie_id: int = 0
var health: float = BASE_HEALTH
var max_health: float = BASE_HEALTH
var move_speed: float = BASE_SPEED
var damage: float = BASE_DAMAGE
var attack_cooldown: float = BASE_ATTACK_RATE

# State machine
var current_state: ZombieState = ZombieState.IDLE
var state_timer: float = 0.0

# Targeting
var target_player: Node3D = null
var target_nail_id: int = -1
var target_position := Vector3.ZERO
var target_direction := Vector3.FORWARD  # Direction toward sigil

# Navigation (navmesh-based pathfinding)
var nav_agent: NavigationAgent3D = null
var path_update_timer: float = 0.0
const PATH_UPDATE_INTERVAL := 0.25  # Faster path updates for better responsiveness

# Navigation mode
var use_navmesh_pathfinding := true  # Use navmesh when available
var nav_path_failed := false  # Fall back to direct movement if navmesh fails

# Attack state
var attack_timer: float = 0.0
var is_attacking := false

# Stagger
var stagger_duration: float = 0.0

# Group behavior (for horde optimization)
var group_leader: ZombieController = null
var is_group_leader := false
var group_offset := Vector3.ZERO

# Physics
const GRAVITY := 9.8


func _ready() -> void:
	# Get navigation agent
	nav_agent = $NavigationAgent3D if has_node("NavigationAgent3D") else null
	if not nav_agent:
		nav_agent = NavigationAgent3D.new()
		nav_agent.name = "NavigationAgent3D"
		add_child(nav_agent)

	# Configure navigation agent for better pathfinding
	nav_agent.path_desired_distance = 0.5
	nav_agent.target_desired_distance = 1.0
	nav_agent.avoidance_enabled = true
	nav_agent.radius = 0.35
	nav_agent.neighbor_distance = 3.0
	nav_agent.max_neighbors = 5
	nav_agent.path_max_distance = 50.0  # Re-path if distance changes significantly

	# Connect navigation signals
	nav_agent.path_changed.connect(_on_nav_path_changed)
	nav_agent.navigation_finished.connect(_on_nav_finished)

	# Apply type modifiers
	_apply_type_modifiers()

	# Add to groups
	add_to_group("zombies")


func _physics_process(delta: float) -> void:
	# Server-only AI
	if not NetworkManager.is_authority():
		return

	if current_state == ZombieState.DEAD:
		return

	# Update timers
	state_timer += delta
	path_update_timer += delta
	attack_timer += delta

	# State machine
	match current_state:
		ZombieState.IDLE:
			_state_idle(delta)
		ZombieState.AGGRO:
			_state_aggro(delta)
		ZombieState.PATH:
			_state_path(delta)
		ZombieState.ATTACK_PLAYER:
			_state_attack_player(delta)
		ZombieState.ATTACK_NAIL:
			_state_attack_nail(delta)
		ZombieState.STAGGER:
			_state_stagger(delta)

	# Apply gravity
	if not is_on_floor():
		velocity.y -= GRAVITY * delta

	move_and_slide()


## Apply modifiers based on zombie type
func _apply_type_modifiers() -> void:
	match zombie_type:
		ZombieType.WALKER:
			health = BASE_HEALTH
			move_speed = BASE_SPEED
			damage = BASE_DAMAGE
			attack_cooldown = BASE_ATTACK_RATE
		ZombieType.RUNNER:
			health = BASE_HEALTH * 0.6
			move_speed = BASE_SPEED * 2.0
			damage = BASE_DAMAGE * 0.7
			attack_cooldown = BASE_ATTACK_RATE * 0.7
		ZombieType.BRUTE:
			health = BASE_HEALTH * 3.0
			move_speed = BASE_SPEED * 0.6
			damage = BASE_DAMAGE * 2.5
			attack_cooldown = BASE_ATTACK_RATE * 1.5
		ZombieType.CRAWLER:
			health = BASE_HEALTH * 0.8
			move_speed = BASE_SPEED * 1.2
			damage = BASE_DAMAGE * 0.8
			attack_cooldown = BASE_ATTACK_RATE * 0.8
		ZombieType.SPITTER:
			health = BASE_HEALTH * 0.7
			move_speed = BASE_SPEED * 0.9
			damage = BASE_DAMAGE * 1.2  # Ranged damage
			attack_cooldown = BASE_ATTACK_RATE * 2.0  # Slower attack
		ZombieType.SCREAMER:
			health = BASE_HEALTH * 0.5
			move_speed = BASE_SPEED * 1.3
			damage = BASE_DAMAGE * 0.5
			attack_cooldown = BASE_ATTACK_RATE * 1.0
		ZombieType.EXPLODER:
			health = BASE_HEALTH * 0.8
			move_speed = BASE_SPEED * 1.1
			damage = BASE_DAMAGE * 3.0  # Explosion damage
			attack_cooldown = 0.0  # Instant explosion
		ZombieType.BOSS:
			health = BASE_HEALTH * 10.0
			move_speed = BASE_SPEED * 0.5
			damage = BASE_DAMAGE * 4.0
			attack_cooldown = BASE_ATTACK_RATE * 0.8

	max_health = health


## Apply wave scaling
func apply_wave_scaling(wave: int) -> void:
	var health_mult := 1.0 + wave * 0.15
	var damage_mult := 1.0 + wave * 0.05

	health *= health_mult
	max_health = health
	damage *= damage_mult


## Set target position (sigil location) for directional movement
func set_target_position(pos: Vector3) -> void:
	target_position = pos
	# Calculate direction to target
	var direction := pos - global_position
	direction.y = 0
	if direction.length() > 0.1:
		target_direction = direction.normalized()
	_change_state(ZombieState.PATH)


# ============================================
# STATE MACHINE
# ============================================

## IDLE - Look for targets
func _state_idle(_delta: float) -> void:
	# Find nearest player
	_find_target()

	if target_player:
		_change_state(ZombieState.AGGRO)
		return

	# Check for nearby barricades to attack even without a player target
	var nearby_nail := GameState.get_nearest_nail(global_position, 10.0)
	if nearby_nail >= 0:
		target_nail_id = nearby_nail
		var nail: Dictionary = GameState.nails[nearby_nail]
		target_position = nail.get("position", global_position)
		_change_state(ZombieState.PATH)
		return

	# Wander after short delay
	if state_timer > 1.0:
		# Wander randomly towards map center (where players/barricades likely are)
		var to_center := -global_position.normalized()
		var random_offset := Vector3(randf_range(-0.5, 0.5), 0, randf_range(-0.5, 0.5))
		var direction := (to_center + random_offset).normalized()
		target_position = global_position + direction * 10.0
		_change_state(ZombieState.PATH)


## AGGRO - Target acquired, start pursuing
func _state_aggro(_delta: float) -> void:
	if not is_instance_valid(target_player):
		_change_state(ZombieState.IDLE)
		return

	# Screamer special: call for help when first aggroed
	if zombie_type == ZombieType.SCREAMER and state_timer < 0.1:
		_scream_for_help()

	target_position = target_player.global_position
	_change_state(ZombieState.PATH)


## PATH - Move toward target using navmesh pathfinding with barricade awareness
func _state_path(delta: float) -> void:
	# Priority 1: Check for nearby nails to attack (immediate barricade threat)
	var nearby_nail := GameState.get_nearest_nail(global_position, 2.5)
	if nearby_nail >= 0:
		target_nail_id = nearby_nail
		_change_state(ZombieState.ATTACK_NAIL)
		return

	# Priority 2: Check for blocking barricades via raycast (periodic check)
	if path_update_timer >= PATH_UPDATE_INTERVAL:
		path_update_timer = 0.0

		var nail_id := _check_for_blocking_nail()
		if nail_id >= 0:
			target_nail_id = nail_id
			_change_state(ZombieState.ATTACK_NAIL)
			return

		# Check if player is nearby and should chase
		_find_target()
		if target_player:
			var player_dist := global_position.distance_to(target_player.global_position)
			if player_dist < 5.0:
				_change_state(ZombieState.AGGRO)
				return

		# Update navmesh target if using navmesh
		if use_navmesh_pathfinding and nav_agent:
			nav_agent.target_position = target_position

	# Calculate movement direction
	var direction := _get_movement_direction()

	# Check if reached target (sigil area)
	var dist_to_target := global_position.distance_to(target_position)
	if dist_to_target < 2.0:
		# Reached sigil - handled by sigil's area trigger
		velocity.x = 0
		velocity.z = 0
		return

	# Apply group offset if following leader (horde behavior)
	if group_leader and is_instance_valid(group_leader):
		direction = (direction + group_offset * 0.3).normalized()

	velocity.x = direction.x * move_speed
	velocity.z = direction.z * move_speed

	# Face movement direction smoothly
	if direction.length() > 0.1:
		var target_angle := atan2(direction.x, direction.z)
		rotation.y = lerp_angle(rotation.y, target_angle, 10.0 * delta)


## Get movement direction using navmesh or fallback to direct movement
func _get_movement_direction() -> Vector3:
	var direction: Vector3

	# Try navmesh pathfinding first
	if use_navmesh_pathfinding and nav_agent and not nav_path_failed:
		if nav_agent.is_navigation_finished():
			# Reached target via navmesh
			return Vector3.ZERO

		var next_pos := nav_agent.get_next_path_position()
		direction = global_position.direction_to(next_pos)
		direction.y = 0

		# Check if we're stuck (velocity is very low but not at target)
		if direction.length() < 0.01:
			# Navmesh might be blocked, use direct movement temporarily
			nav_path_failed = true
			direction = global_position.direction_to(target_position)
			direction.y = 0
	else:
		# Direct movement toward target (fallback)
		direction = global_position.direction_to(target_position)
		direction.y = 0

		# Reset navmesh failure after a short delay
		if nav_path_failed:
			nav_path_failed = false

	return direction.normalized() if direction.length() > 0.01 else Vector3.ZERO


## Called when navigation path changes
func _on_nav_path_changed() -> void:
	nav_path_failed = false  # New path available, reset failure flag


## Called when navigation target is reached
func _on_nav_finished() -> void:
	# At destination - could transition to attack or idle
	pass


## ATTACK_PLAYER - Melee attack player
func _state_attack_player(delta: float) -> void:
	if not is_instance_valid(target_player):
		_change_state(ZombieState.IDLE)
		return

	var dist := global_position.distance_to(target_player.global_position)

	# Too far, resume chase
	if dist > 2.5:
		_change_state(ZombieState.AGGRO)
		return

	# Face player
	var direction := global_position.direction_to(target_player.global_position)
	direction.y = 0
	var target_angle := atan2(direction.x, direction.z)
	rotation.y = lerp_angle(rotation.y, target_angle, 10.0 * delta)

	# Stop moving while attacking
	velocity.x = move_toward(velocity.x, 0, 10.0 * delta)
	velocity.z = move_toward(velocity.z, 0, 10.0 * delta)

	# Attack on cooldown
	if attack_timer >= attack_cooldown:
		attack_timer = 0.0
		_perform_attack_player()


## ATTACK_NAIL - Attack barricade nail (JetBoom core mechanic)
func _state_attack_nail(delta: float) -> void:
	# Verify nail still exists and is active
	if target_nail_id < 0 or not GameState or not GameState.nails or target_nail_id not in GameState.nails:
		target_nail_id = -1
		_change_state(ZombieState.PATH)
		return

	var nail: Dictionary = GameState.nails[target_nail_id]
	if not nail.get("active", false):
		target_nail_id = -1
		_change_state(ZombieState.PATH)
		return

	var nail_pos: Vector3 = nail.get("position", global_position)
	var dist := global_position.distance_to(nail_pos)

	# Too far, move closer
	if dist > 2.0:
		target_position = nail_pos
		_change_state(ZombieState.PATH)
		return

	# Face nail
	var direction := global_position.direction_to(nail_pos)
	direction.y = 0
	var target_angle := atan2(direction.x, direction.z)
	rotation.y = lerp_angle(rotation.y, target_angle, 10.0 * delta)

	# Stop moving while attacking
	velocity.x = move_toward(velocity.x, 0, 10.0 * delta)
	velocity.z = move_toward(velocity.z, 0, 10.0 * delta)

	# Attack nail on cooldown
	if attack_timer >= attack_cooldown:
		attack_timer = 0.0
		_perform_attack_nail()


## STAGGER - Temporarily stunned
func _state_stagger(delta: float) -> void:
	# Slow down
	velocity.x = move_toward(velocity.x, 0, 20.0 * delta)
	velocity.z = move_toward(velocity.z, 0, 20.0 * delta)

	stagger_duration -= delta
	if stagger_duration <= 0:
		# Re-validate target after stagger ends
		_find_target()
		if target_player:
			_change_state(ZombieState.AGGRO)
		else:
			_change_state(ZombieState.IDLE)


# ============================================
# HELPER FUNCTIONS
# ============================================

## Change to new state
func _change_state(new_state: ZombieState) -> void:
	current_state = new_state
	state_timer = 0.0


## Find nearest player target
func _find_target() -> void:
	target_player = null
	var nearest_dist := 50.0  # Max aggro range

	if not GameState or not GameState.players:
		return

	for peer_id in GameState.players:
		var player: Node3D = GameState.players[peer_id]
		if not is_instance_valid(player):
			continue

		# Skip dead players
		if player.get("is_dead"):
			continue

		var dist := global_position.distance_to(player.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			target_player = player


## Check for blocking nail along path
func _check_for_blocking_nail() -> int:
	var space_state := get_world_3d().direct_space_state
	var from := global_position + Vector3.UP * 0.5
	var forward := -global_basis.z

	# Check multiple angles for better detection
	var angles := [0.0, -0.3, 0.3]  # Center, left, right
	for angle_offset in angles:
		var direction := forward.rotated(Vector3.UP, angle_offset)
		var to := from + direction * 4.0  # Increased range

		var query := PhysicsRayQueryParameters3D.create(from, to)
		query.collision_mask = 0b00001000  # Props layer

		var result := space_state.intersect_ray(query)

		if result:
			# Found a prop, check if it has nails
			var prop: Node = result.collider
			var prop_id: int = prop.get("prop_id") if prop else -1

			if prop_id >= 0 and GameState and GameState.nails:
				# Find a nail connected to this prop
				for nail_id in GameState.nails:
					var nail: Dictionary = GameState.nails[nail_id]
					if nail.get("active", false) and nail.get("prop_id", -1) == prop_id:
						return nail_id

	# Also check for nearby nails directly
	var nearest_nail := GameState.get_nearest_nail(global_position, 2.0)
	return nearest_nail


## Perform attack on player
func _perform_attack_player() -> void:
	if not is_instance_valid(target_player):
		return

	is_attacking = true

	# Deal damage
	if target_player.has_method("take_damage"):
		target_player.take_damage(damage, global_position)

	# Animation would go here
	is_attacking = false


## Perform attack on nail (JetBoom mechanic)
func _perform_attack_nail() -> void:
	if target_nail_id < 0:
		return

	is_attacking = true

	# Damage the nail, not the prop!
	GameState.damage_nail(target_nail_id, damage)

	# Check if nail broke
	if target_nail_id not in GameState.nails or not GameState.nails[target_nail_id].get("active", false):
		target_nail_id = -1
		# Resume pathing after breaking through
		_change_state(ZombieState.PATH)

	is_attacking = false


## Take damage (server-side)
func take_damage(amount: float, hit_position: Vector3) -> void:
	if not NetworkManager.is_authority():
		return

	if current_state == ZombieState.DEAD:
		return

	health -= amount

	# Stagger chance based on damage
	if amount > damage * 0.5 and randf() < 0.3:
		stagger_duration = 0.5
		_change_state(ZombieState.STAGGER)

	if health <= 0:
		_die()


## Die
func _die() -> void:
	current_state = ZombieState.DEAD
	health = 0

	# Special death behaviors
	match zombie_type:
		ZombieType.EXPLODER:
			_explode_on_death()
		ZombieType.SCREAMER:
			# Already called zombies when aggroed
			pass
		ZombieType.BOSS:
			# Broadcast boss killed event for HUD celebration
			NetworkManager.broadcast_event.rpc("boss_killed", {
				"position": global_position,
				"zombie_id": zombie_id
			})

	# Drop loot
	_drop_loot()

	# Notify game state
	GameState.kill_zombie(zombie_id)

	# Play death animation, then remove
	# For now, just queue free
	queue_free()


## Exploder special: explodes on death dealing AoE damage
func _explode_on_death() -> void:
	var explosion_radius := 4.0
	var explosion_damage := damage  # Uses exploder's damage stat

	# Find all players and zombies in radius
	for peer_id in GameState.players:
		var player: Node3D = GameState.players[peer_id]
		if not is_instance_valid(player):
			continue

		var dist := global_position.distance_to(player.global_position)
		if dist < explosion_radius:
			# Damage falls off with distance
			var falloff := 1.0 - (dist / explosion_radius)
			var actual_damage := explosion_damage * falloff
			if player.has_method("take_damage"):
				player.take_damage(actual_damage, global_position)

	# Broadcast explosion event for VFX
	NetworkManager.broadcast_event.rpc("zombie_explode", {
		"position": global_position,
		"radius": explosion_radius
	})


## Screamer special: call nearby zombies to converge on player
func _scream_for_help() -> void:
	if not target_player:
		return

	var scream_radius := 20.0
	var player_pos := target_player.global_position

	# All zombies in radius target this player
	for zid in GameState.zombies:
		var zombie: ZombieController = GameState.zombies[zid]
		if not is_instance_valid(zombie):
			continue
		if zombie == self:
			continue

		var dist := global_position.distance_to(zombie.global_position)
		if dist < scream_radius:
			zombie.target_player = target_player
			zombie.target_position = player_pos
			zombie._change_state(ZombieState.AGGRO)

	# Broadcast scream event for audio
	NetworkManager.broadcast_event.rpc("zombie_scream", {
		"position": global_position
	})


## Drop loot on death
func _drop_loot() -> void:
	if not NetworkManager.is_authority():
		return

	# Calculate loot chance based on zombie type
	var loot_chance := 0.1  # Base 10% chance
	var gold_amount := 0
	var xp_amount := 10

	match zombie_type:
		ZombieType.WALKER:
			loot_chance = 0.08
			gold_amount = randi_range(5, 15)
			xp_amount = 10
		ZombieType.RUNNER:
			loot_chance = 0.10
			gold_amount = randi_range(8, 20)
			xp_amount = 15
		ZombieType.BRUTE:
			loot_chance = 0.25
			gold_amount = randi_range(20, 50)
			xp_amount = 35
		ZombieType.CRAWLER:
			loot_chance = 0.12
			gold_amount = randi_range(10, 25)
			xp_amount = 12
		ZombieType.SPITTER:
			loot_chance = 0.18
			gold_amount = randi_range(15, 35)
			xp_amount = 25
		ZombieType.SCREAMER:
			loot_chance = 0.20
			gold_amount = randi_range(12, 30)
			xp_amount = 20
		ZombieType.EXPLODER:
			loot_chance = 0.15
			gold_amount = randi_range(18, 40)
			xp_amount = 30
		ZombieType.BOSS:
			loot_chance = 1.0  # Always drop loot
			gold_amount = randi_range(100, 250)
			xp_amount = 150

	# Broadcast loot drop event (handled by game world)
	NetworkManager.broadcast_event.rpc("zombie_loot", {
		"position": global_position,
		"gold": gold_amount,
		"xp": xp_amount,
		"drop_item": randf() < loot_chance,
		"zombie_type": zombie_type
	})


## Get network state for snapshot
func get_network_state() -> Dictionary:
	return {
		"pos": global_position,
		"rot": rotation.y,
		"vel": velocity,
		"state": current_state,
		"health": health,
		"attacking": is_attacking,
	}


## Apply network state (client-side)
func apply_network_state(state: Dictionary) -> void:
	if NetworkManager.is_authority():
		return  # Server doesn't apply

	# Interpolate position
	var target_pos: Vector3 = state.pos
	global_position = global_position.lerp(target_pos, 0.5)

	# Apply rotation
	rotation.y = state.get("rot", rotation.y)

	# Apply state
	current_state = state.get("state", current_state) as ZombieState
	health = state.get("health", health)
	is_attacking = state.get("attacking", false)


## Convert string to ZombieType enum
static func string_to_type(type_str: String) -> ZombieType:
	match type_str.to_lower():
		"walker": return ZombieType.WALKER
		"runner": return ZombieType.RUNNER
		"brute": return ZombieType.BRUTE
		"crawler": return ZombieType.CRAWLER
		"spitter": return ZombieType.SPITTER
		"screamer": return ZombieType.SCREAMER
		"exploder": return ZombieType.EXPLODER
		"boss": return ZombieType.BOSS
	return ZombieType.WALKER


## Set type from string (used when spawning)
func set_type_from_string(type_str: String) -> void:
	zombie_type = string_to_type(type_str)
