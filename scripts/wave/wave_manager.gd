extends Node
class_name WaveManager
## WaveManager - Server-only wave control
##
## Controls zombie spawning, wave progression, and difficulty scaling.
## All logic runs exclusively on the server.

signal wave_started(wave_number: int, zombie_count: int)
signal wave_ended(wave_number: int, kills: int)
signal zombie_spawned_signal(zombie_id: int)
signal wave_progress_changed(remaining: int, total: int)

# Wave configuration
@export var base_zombies_per_player := 5
@export var zombies_per_wave_increase := 2
@export var intermission_duration := 30.0
@export var preparation_duration := 10.0
@export var spawn_interval := 0.5
@export var max_active_zombies := 50

# Difficulty scaling
@export var health_scale_per_wave := 0.15
@export var damage_scale_per_wave := 0.05
@export var special_zombie_chance_base := 0.1
@export var special_zombie_chance_per_wave := 0.02

# Current state
var current_wave := 0
var wave_active := false
var zombies_to_spawn := 0
var zombies_spawned := 0
var zombies_killed := 0
var total_wave_zombies := 0

# Spawn state
var spawn_timer := 0.0
var spawn_points: Array[Node3D] = []

# Zombie type distribution (base weights, adjusted by wave)
var zombie_type_weights := {
	ZombieController.ZombieType.WALKER: 60,
	ZombieController.ZombieType.RUNNER: 20,
	ZombieController.ZombieType.BRUTE: 8,
	ZombieController.ZombieType.CRAWLER: 5,
	ZombieController.ZombieType.SPITTER: 3,
	ZombieController.ZombieType.SCREAMER: 2,
	ZombieController.ZombieType.EXPLODER: 2,
}

# Boss spawn tracking
var boss_spawned_this_wave := false
const BOSS_SPAWN_WAVE_INTERVAL := 5  # Boss every 5 waves


func _ready() -> void:
	# Find spawn points in the scene
	call_deferred("_find_spawn_points")


func _physics_process(delta: float) -> void:
	if not NetworkManager.is_authority():
		return

	if wave_active and zombies_to_spawn > 0:
		_process_spawning(delta)


## Find spawn points in the scene
func _find_spawn_points() -> void:
	spawn_points.clear()

	# Look for nodes in "zombie_spawns" group
	var spawns := get_tree().get_nodes_in_group("zombie_spawns")
	for spawn in spawns:
		if spawn is Node3D:
			spawn_points.append(spawn)

	# If no spawn points found, create default ones
	if spawn_points.is_empty():
		push_warning("No zombie spawn points found. Using default positions.")


## Start the wave system
func start_waves() -> void:
	if not NetworkManager.is_authority():
		return

	current_wave = 0
	_start_next_wave()


## Start next wave
func _start_next_wave() -> void:
	current_wave += 1

	# Calculate zombie count
	var player_count := maxi(GameState.players.size(), 1)
	total_wave_zombies = player_count * (base_zombies_per_player + current_wave * zombies_per_wave_increase)

	# Limit to reasonable number
	total_wave_zombies = mini(total_wave_zombies, 200)

	zombies_to_spawn = total_wave_zombies
	zombies_spawned = 0
	zombies_killed = 0
	wave_active = true
	spawn_timer = 0.0
	boss_spawned_this_wave = false

	# Check if this is a boss wave
	var is_boss_wave := current_wave % BOSS_SPAWN_WAVE_INTERVAL == 0

	# Notify
	wave_started.emit(current_wave, total_wave_zombies)

	# Broadcast to clients
	NetworkManager.broadcast_event.rpc("wave_start", {
		"wave": current_wave,
		"zombie_count": total_wave_zombies,
		"is_boss_wave": is_boss_wave
	})

	if is_boss_wave:
		print("[WaveManager] BOSS WAVE %d started - %d zombies + BOSS" % [current_wave, total_wave_zombies])
	else:
		print("[WaveManager] Wave %d started - %d zombies" % [current_wave, total_wave_zombies])


## End current wave
func _end_wave() -> void:
	wave_active = false

	wave_ended.emit(current_wave, zombies_killed)

	NetworkManager.broadcast_event.rpc("wave_end", {
		"wave": current_wave,
		"kills": zombies_killed
	})

	print("[WaveManager] Wave %d ended - %d kills" % [current_wave, zombies_killed])

	# Start intermission, then next wave
	await get_tree().create_timer(intermission_duration).timeout
	_start_next_wave()


## Process zombie spawning
func _process_spawning(delta: float) -> void:
	spawn_timer += delta

	if spawn_timer < spawn_interval:
		return

	spawn_timer = 0.0

	# Check active zombie limit
	if GameState.zombies.size() >= max_active_zombies:
		return

	# Spawn a zombie
	_spawn_zombie()


## Spawn a single zombie
func _spawn_zombie() -> void:
	if zombies_to_spawn <= 0:
		return

	# Get spawn position
	var spawn_pos := _get_spawn_position()

	# Determine zombie type
	var zombie_type := _get_zombie_type()

	# Spawn via GameState
	var zombie_id := GameState.spawn_zombie(spawn_pos, _type_to_string(zombie_type))

	if zombie_id >= 0:
		# Apply wave scaling
		if zombie_id in GameState.zombies:
			var zombie: ZombieController = GameState.zombies[zombie_id]
			if is_instance_valid(zombie):
				zombie.zombie_type = zombie_type
				zombie.apply_wave_scaling(current_wave)

		zombies_to_spawn -= 1
		zombies_spawned += 1
		zombie_spawned_signal.emit(zombie_id)
		wave_progress_changed.emit(zombies_to_spawn, total_wave_zombies)


## Get spawn position from available spawn points
func _get_spawn_position() -> Vector3:
	if spawn_points.is_empty():
		# Default spawn positions around the map edge
		var angle := randf() * TAU
		var distance := randf_range(30.0, 50.0)
		return Vector3(cos(angle) * distance, 0, sin(angle) * distance)

	# Random spawn point with some variance
	var spawn_point: Node3D = spawn_points[randi() % spawn_points.size()]
	var variance := Vector3(randf_range(-2, 2), 0, randf_range(-2, 2))
	return spawn_point.global_position + variance


## Determine zombie type based on weights and wave
func _get_zombie_type() -> ZombieController.ZombieType:
	# Check if should spawn boss (once per boss wave, at 50% progress)
	var is_boss_wave := current_wave % BOSS_SPAWN_WAVE_INTERVAL == 0
	if is_boss_wave and not boss_spawned_this_wave:
		var progress := float(zombies_spawned) / float(total_wave_zombies)
		if progress >= 0.5:
			boss_spawned_this_wave = true
			return ZombieController.ZombieType.BOSS

	# Adjust weights based on wave (more dangerous zombies in later waves)
	var adjusted_weights := zombie_type_weights.duplicate()

	# Reduce walkers, increase specials as waves progress
	var wave_factor := minf(current_wave / 10.0, 1.0)  # 0 to 1 over 10 waves
	adjusted_weights[ZombieController.ZombieType.WALKER] = int(60 * (1.0 - wave_factor * 0.4))
	adjusted_weights[ZombieController.ZombieType.RUNNER] = int(20 + wave_factor * 10)
	adjusted_weights[ZombieController.ZombieType.BRUTE] = int(8 + wave_factor * 7)
	adjusted_weights[ZombieController.ZombieType.SPITTER] = int(3 + wave_factor * 5)
	adjusted_weights[ZombieController.ZombieType.SCREAMER] = int(2 + wave_factor * 4)
	adjusted_weights[ZombieController.ZombieType.EXPLODER] = int(2 + wave_factor * 4)

	# More special zombies chance in later waves
	var special_chance := special_zombie_chance_base + current_wave * special_zombie_chance_per_wave
	special_chance = minf(special_chance, 0.5)

	if randf() < special_chance:
		# Roll for special type (weighted by wave)
		var specials: Array[ZombieController.ZombieType] = [
			ZombieController.ZombieType.RUNNER,
			ZombieController.ZombieType.BRUTE,
			ZombieController.ZombieType.CRAWLER,
			ZombieController.ZombieType.SPITTER,
			ZombieController.ZombieType.SCREAMER,
			ZombieController.ZombieType.EXPLODER,
		]

		# Later waves can spawn more dangerous specials
		var max_special_idx := mini(2 + int(current_wave / 3), specials.size() - 1)
		return specials[randi() % (max_special_idx + 1)]

	# Weighted random for normal distribution
	var total_weight := 0
	for type in adjusted_weights:
		total_weight += adjusted_weights[type]

	var roll := randi() % maxi(total_weight, 1)
	var cumulative := 0

	for type in adjusted_weights:
		cumulative += adjusted_weights[type]
		if roll < cumulative:
			return type

	return ZombieController.ZombieType.WALKER


## Convert type enum to string
func _type_to_string(type: ZombieController.ZombieType) -> String:
	match type:
		ZombieController.ZombieType.WALKER:
			return "walker"
		ZombieController.ZombieType.RUNNER:
			return "runner"
		ZombieController.ZombieType.BRUTE:
			return "brute"
		ZombieController.ZombieType.CRAWLER:
			return "crawler"
		ZombieController.ZombieType.SPITTER:
			return "spitter"
		ZombieController.ZombieType.SCREAMER:
			return "screamer"
		ZombieController.ZombieType.EXPLODER:
			return "exploder"
		ZombieController.ZombieType.BOSS:
			return "boss"
	return "walker"


## Called when a zombie is killed (connect to GameState.zombie_killed)
func on_zombie_killed(_zombie_id: int) -> void:
	if not NetworkManager.is_authority():
		return

	zombies_killed += 1
	wave_progress_changed.emit(zombies_to_spawn, total_wave_zombies)

	# Check if wave is complete
	if zombies_to_spawn <= 0 and GameState.zombies.is_empty():
		_end_wave()


## Fast reset for testing/round restart
func reset_waves() -> void:
	if not NetworkManager.is_authority():
		return

	wave_active = false
	current_wave = 0
	zombies_to_spawn = 0
	zombies_spawned = 0
	zombies_killed = 0

	# Kill all active zombies
	for zombie_id in GameState.zombies.keys():
		GameState.kill_zombie(zombie_id)


## Get current wave info
func get_wave_info() -> Dictionary:
	return {
		"wave": current_wave,
		"active": wave_active,
		"remaining": zombies_to_spawn,
		"killed": zombies_killed,
		"total": total_wave_zombies,
	}
