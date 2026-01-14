extends Node
## GameDirector - Server-side wave and pressure management
##
## Implements the pressure tube model:
## - Escalating waves with predictable scaling
## - Type unlocks at specific waves
## - Spawn timing acceleration
## - Player count scaling

signal wave_started(wave: int, pressure: Dictionary)
signal wave_ended(wave: int, stats: Dictionary)
signal zombie_type_unlocked(zombie_type: String)
signal pressure_increased(new_pressure: float)

# Wave configuration
const BASE_ZOMBIE_COUNT := 10
const COUNT_SCALAR := 3.0  # Additional zombies per wave
const BASE_HP := 100.0
const HP_SCALAR := 0.10  # 10% HP increase per wave
const BASE_SPAWN_INTERVAL := 1.0  # Seconds between spawns
const MIN_SPAWN_INTERVAL := 0.2
const SPAWN_ACCELERATION := 0.05  # Faster spawning each wave

# Player scaling (not linear - diminishing returns)
const PLAYER_MULTIPLIERS := {
	1: 1.0,
	2: 1.6,
	3: 2.1,
	4: 2.5
}

# Type unlock table - waves at which types become available
const TYPE_UNLOCK_TABLE := {
	1: ["walker"],
	4: ["runner"],
	7: ["brute"],
	10: ["crawler"],
	15: ["spitter"],  # Future type
	20: ["charger"],  # Future type
}

# Current state
var current_wave := 0
var wave_active := false
var zombies_to_spawn := 0
var zombies_spawned := 0
var zombies_killed := 0
var spawn_timer := 0.0
var current_spawn_interval := BASE_SPAWN_INTERVAL

# Available zombie types for current wave
var available_types: Array[String] = []

# Sigil reference
var sigil: Sigil = null

# Spawn lane (direction zombies move)
var spawn_position := Vector3(0, 0, 50)  # End of hallway
var sigil_position := Vector3(0, 0, 0)   # Start of hallway


func _ready() -> void:
	# Find sigil when world loads
	call_deferred("_find_sigil")


func _physics_process(delta: float) -> void:
	if not NetworkManager.is_authority():
		return

	if wave_active and zombies_to_spawn > 0:
		_process_spawning(delta)


func _find_sigil() -> void:
	var sigils := get_tree().get_nodes_in_group("sigil")
	if not sigils.is_empty():
		sigil = sigils[0] as Sigil
		sigil_position = sigil.global_position
		print("[GameDirector] Found sigil at %s" % sigil_position)


## Configure spawn lane positions
func set_spawn_lane(spawn_pos: Vector3, target_pos: Vector3) -> void:
	spawn_position = spawn_pos
	sigil_position = target_pos
	print("[GameDirector] Spawn lane: %s -> %s" % [spawn_pos, target_pos])


## Start the game (call after world is ready)
func start_game() -> void:
	if not NetworkManager.is_authority():
		return

	current_wave = 0
	_start_next_wave()


## Start next wave
func _start_next_wave() -> void:
	current_wave += 1

	# Calculate pressure for this wave
	var pressure := _calculate_wave_pressure()

	# Update available types
	_update_available_types()

	# Set wave state
	zombies_to_spawn = pressure.zombie_count
	zombies_spawned = 0
	zombies_killed = 0
	current_spawn_interval = pressure.spawn_interval
	wave_active = true
	spawn_timer = 0.0

	wave_started.emit(current_wave, pressure)

	# Broadcast to clients
	if NetworkManager:
		NetworkManager.broadcast_event.rpc("wave_start", {
			"wave": current_wave,
			"zombie_count": pressure.zombie_count,
			"types": available_types
		})

	print("[GameDirector] Wave %d - Count: %d, HP: %.0f, Interval: %.2fs, Types: %s" % [
		current_wave, pressure.zombie_count, pressure.zombie_health,
		pressure.spawn_interval, available_types
	])


## Calculate wave pressure based on formula
func _calculate_wave_pressure() -> Dictionary:
	var player_count := maxi(GameState.players.size(), 1)
	var player_mult: float = PLAYER_MULTIPLIERS.get(player_count, 2.5)

	var zombie_count := int((BASE_ZOMBIE_COUNT + current_wave * COUNT_SCALAR) * player_mult)
	var zombie_health := BASE_HP * (1.0 + current_wave * HP_SCALAR)
	var spawn_interval := clampf(
		BASE_SPAWN_INTERVAL - current_wave * SPAWN_ACCELERATION,
		MIN_SPAWN_INTERVAL,
		BASE_SPAWN_INTERVAL
	)

	# Calculate damage scaling (smaller than HP scaling)
	var damage_mult := 1.0 + current_wave * 0.05

	return {
		"zombie_count": zombie_count,
		"zombie_health": zombie_health,
		"spawn_interval": spawn_interval,
		"damage_mult": damage_mult,
		"player_mult": player_mult,
		"pressure_score": zombie_count * zombie_health * damage_mult
	}


## Update available zombie types based on wave
func _update_available_types() -> void:
	for unlock_wave in TYPE_UNLOCK_TABLE:
		if current_wave >= unlock_wave:
			for zombie_type in TYPE_UNLOCK_TABLE[unlock_wave]:
				if zombie_type not in available_types:
					available_types.append(zombie_type)
					zombie_type_unlocked.emit(zombie_type)
					print("[GameDirector] Unlocked zombie type: %s" % zombie_type)


## Process zombie spawning
func _process_spawning(delta: float) -> void:
	spawn_timer += delta

	if spawn_timer < current_spawn_interval:
		return

	spawn_timer = 0.0

	# Spawn a zombie
	_spawn_zombie()


## Spawn a single zombie at the spawn lane
func _spawn_zombie() -> void:
	if zombies_to_spawn <= 0:
		return

	# Add some variance to spawn position
	var variance := Vector3(randf_range(-3, 3), 0, randf_range(-2, 2))
	var pos := spawn_position + variance

	# Select type based on available types and wave
	var zombie_type := _select_zombie_type()

	# Spawn via GameState
	var zombie_id := GameState.spawn_zombie(pos, zombie_type)

	if zombie_id >= 0:
		# Apply wave scaling
		if zombie_id in GameState.zombies:
			var zombie: ZombieController = GameState.zombies[zombie_id]
			if is_instance_valid(zombie):
				var pressure := _calculate_wave_pressure()
				zombie.health = pressure.zombie_health
				zombie.max_health = pressure.zombie_health
				zombie.damage *= pressure.damage_mult

				# Set target direction (toward sigil)
				zombie.set_target_position(sigil_position)

		zombies_to_spawn -= 1
		zombies_spawned += 1


## Select zombie type based on available types and wave
func _select_zombie_type() -> String:
	if available_types.is_empty():
		return "walker"

	# Higher waves have better chance of special types
	var special_chance := minf(0.1 + current_wave * 0.02, 0.5)

	if randf() < special_chance and available_types.size() > 1:
		# Pick a random non-walker type
		var specials := available_types.filter(func(t): return t != "walker")
		if not specials.is_empty():
			return specials[randi() % specials.size()]

	# Weight towards walkers
	var weights := {
		"walker": 60,
		"runner": 25,
		"brute": 10,
		"crawler": 5
	}

	var total := 0
	for t in available_types:
		total += weights.get(t, 10)

	var roll := randi() % total
	var cumulative := 0

	for t in available_types:
		cumulative += weights.get(t, 10)
		if roll < cumulative:
			return t

	return "walker"


## Called when a zombie is killed
func on_zombie_killed(_zombie_id: int) -> void:
	if not NetworkManager.is_authority():
		return

	zombies_killed += 1

	# Check if wave is complete
	if zombies_to_spawn <= 0 and GameState.zombies.is_empty():
		_end_wave()


## End current wave
func _end_wave() -> void:
	wave_active = false

	var stats := {
		"wave": current_wave,
		"spawned": zombies_spawned,
		"killed": zombies_killed,
		"sigil_health": sigil.health if sigil else 1000.0
	}

	wave_ended.emit(current_wave, stats)

	# Broadcast to clients
	if NetworkManager:
		NetworkManager.broadcast_event.rpc("wave_end", stats)

	print("[GameDirector] Wave %d complete - Killed: %d, Sigil: %.0f HP" % [
		current_wave, zombies_killed, stats.sigil_health
	])

	# Brief intermission then next wave
	await get_tree().create_timer(10.0).timeout

	# Check sigil still alive
	if sigil and sigil.health > 0:
		_start_next_wave()


## Get current wave info
func get_wave_info() -> Dictionary:
	return {
		"wave": current_wave,
		"active": wave_active,
		"remaining": zombies_to_spawn + GameState.zombies.size(),
		"killed": zombies_killed,
		"types": available_types
	}


## Get pressure score (for UI/difficulty display)
func get_pressure_score() -> float:
	var pressure := _calculate_wave_pressure()
	return pressure.pressure_score
