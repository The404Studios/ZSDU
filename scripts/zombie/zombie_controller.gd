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

# Navigation
var nav_agent: NavigationAgent3D = null
var path_update_timer: float = 0.0
const PATH_UPDATE_INTERVAL := 0.5  # Don't re-path every frame

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

	# Configure navigation
	nav_agent.path_desired_distance = 0.5
	nav_agent.target_desired_distance = 1.0
	nav_agent.avoidance_enabled = true

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
		ZombieType.RUNNER:
			health = BASE_HEALTH * 0.6
			move_speed = BASE_SPEED * 2.0
			damage = BASE_DAMAGE * 0.7
		ZombieType.BRUTE:
			health = BASE_HEALTH * 3.0
			move_speed = BASE_SPEED * 0.6
			damage = BASE_DAMAGE * 2.5
		ZombieType.CRAWLER:
			health = BASE_HEALTH * 0.8
			move_speed = BASE_SPEED * 1.2
			damage = BASE_DAMAGE * 0.8

	max_health = health


## Apply wave scaling
func apply_wave_scaling(wave: int) -> void:
	var health_mult := 1.0 + wave * 0.15
	var damage_mult := 1.0 + wave * 0.05

	health *= health_mult
	max_health = health
	damage *= damage_mult


# ============================================
# STATE MACHINE
# ============================================

## IDLE - Look for targets
func _state_idle(delta: float) -> void:
	# Find nearest player
	_find_target()

	if target_player:
		_change_state(ZombieState.AGGRO)
	elif state_timer > 2.0:
		# Wander randomly
		var random_dir := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
		target_position = global_position + random_dir * 5.0
		_change_state(ZombieState.PATH)


## AGGRO - Target acquired, start pursuing
func _state_aggro(_delta: float) -> void:
	if not is_instance_valid(target_player):
		_change_state(ZombieState.IDLE)
		return

	target_position = target_player.global_position
	_change_state(ZombieState.PATH)


## PATH - Navigate to target
func _state_path(delta: float) -> void:
	if not nav_agent:
		_change_state(ZombieState.IDLE)
		return

	# Update path periodically (not every frame)
	if path_update_timer >= PATH_UPDATE_INTERVAL:
		path_update_timer = 0.0

		# Check for blocking barricades
		var nail_id := _check_for_blocking_nail()
		if nail_id >= 0:
			target_nail_id = nail_id
			_change_state(ZombieState.ATTACK_NAIL)
			return

		# Update target if we have a player
		if is_instance_valid(target_player):
			target_position = target_player.global_position

		nav_agent.target_position = target_position

	# Check if we reached target
	if nav_agent.is_navigation_finished():
		if is_instance_valid(target_player):
			var dist := global_position.distance_to(target_player.global_position)
			if dist < 2.0:
				_change_state(ZombieState.ATTACK_PLAYER)
			else:
				_change_state(ZombieState.AGGRO)
		else:
			_change_state(ZombieState.IDLE)
		return

	# Move towards next path point
	var next_pos := nav_agent.get_next_path_position()
	var direction := global_position.direction_to(next_pos)
	direction.y = 0
	direction = direction.normalized()

	# Apply group offset if following leader
	if group_leader and is_instance_valid(group_leader):
		direction = (direction + group_offset * 0.3).normalized()

	velocity.x = direction.x * move_speed
	velocity.z = direction.z * move_speed

	# Face movement direction
	if direction.length() > 0.1:
		var target_angle := atan2(direction.x, direction.z)
		rotation.y = lerp_angle(rotation.y, target_angle, 10.0 * delta)


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
	if not nail.active:
		target_nail_id = -1
		_change_state(ZombieState.PATH)
		return

	var nail_pos: Vector3 = nail.position
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
		_change_state(ZombieState.AGGRO)


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
	# Raycast forward to check for barricades
	var space_state := get_world_3d().direct_space_state
	var from := global_position + Vector3.UP * 0.5
	var to := from + -global_basis.z * 3.0

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
				if nail.active and nail.prop_id == prop_id:
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
	if target_nail_id not in GameState.nails or not GameState.nails[target_nail_id].active:
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

	# Notify game state
	GameState.kill_zombie(zombie_id)

	# Play death animation, then remove
	# For now, just queue free
	queue_free()


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
	return ZombieType.WALKER


## Set type from string (used when spawning)
func set_type_from_string(type_str: String) -> void:
	zombie_type = string_to_type(type_str)
