class_name EntityInterpolator
## EntityInterpolator - Smooth network state interpolation for entities
##
## Handles interpolation and extrapolation for networked entities.
## Uses a jitter buffer to smooth out network variance.
##
## Usage:
##   var interp := EntityInterpolator.new()
##   interp.push_state(tick, position, rotation, velocity)
##   var smoothed := interp.get_interpolated_state(current_tick)

# State buffer entry
class StateEntry:
	var tick: int
	var timestamp: float
	var position: Vector3
	var rotation: Vector3
	var velocity: Vector3
	var angular_velocity: Vector3

# Circular buffer of states
var _state_buffer: Array[StateEntry] = []
const BUFFER_SIZE := 32

# Interpolation settings
var interpolation_delay: float = 0.1  # 100ms delay for smooth playback
var extrapolation_limit: float = 0.2  # Max 200ms of extrapolation

# Server tick info
var _server_tick_rate: float = 60.0  # Physics ticks per second
var _local_time_offset: float = 0.0

# Last applied state (for delta compression detection)
var _last_applied_tick: int = 0


func _init(tick_rate: float = 60.0) -> void:
	_server_tick_rate = tick_rate


## Push a new state from the server
func push_state(tick: int, pos: Vector3, rot: Vector3, vel: Vector3 = Vector3.ZERO, ang_vel: Vector3 = Vector3.ZERO) -> void:
	# Skip if we've already processed this tick
	if tick <= _last_applied_tick:
		return

	var entry := StateEntry.new()
	entry.tick = tick
	entry.timestamp = Time.get_ticks_msec() / 1000.0
	entry.position = pos
	entry.rotation = rot
	entry.velocity = vel
	entry.angular_velocity = ang_vel

	# Insert sorted by tick (usually at end)
	var inserted := false
	for i in range(_state_buffer.size() - 1, -1, -1):
		if _state_buffer[i].tick < tick:
			_state_buffer.insert(i + 1, entry)
			inserted = true
			break

	if not inserted:
		_state_buffer.insert(0, entry)

	# Trim buffer
	while _state_buffer.size() > BUFFER_SIZE:
		_state_buffer.pop_front()


## Get interpolated state for current render time
func get_interpolated_state(current_tick: int) -> Dictionary:
	if _state_buffer.is_empty():
		return {}

	var current_time := Time.get_ticks_msec() / 1000.0
	var render_time := current_time - interpolation_delay

	# Find surrounding states based on timestamp
	var before: StateEntry = null
	var after: StateEntry = null

	for i in range(_state_buffer.size()):
		var state := _state_buffer[i]
		if state.timestamp <= render_time:
			before = state
		elif after == null:
			after = state
			break

	# Case 1: No states - return empty
	if before == null and after == null:
		return {}

	# Case 2: Only have future state - use it directly (snap)
	if before == null:
		return _state_to_dict(after)

	# Case 3: Only have past state - extrapolate
	if after == null:
		return _extrapolate(before, render_time)

	# Case 4: Interpolate between states
	return _interpolate(before, after, render_time)


## Interpolate between two states
func _interpolate(before: StateEntry, after: StateEntry, render_time: float) -> Dictionary:
	var time_diff := after.timestamp - before.timestamp
	if time_diff <= 0:
		return _state_to_dict(after)

	var t := clampf((render_time - before.timestamp) / time_diff, 0.0, 1.0)

	return {
		"position": before.position.lerp(after.position, t),
		"rotation": _lerp_angles(before.rotation, after.rotation, t),
		"velocity": before.velocity.lerp(after.velocity, t),
		"angular_velocity": before.angular_velocity.lerp(after.angular_velocity, t),
		"interpolated": true,
	}


## Extrapolate from last known state
func _extrapolate(state: StateEntry, render_time: float) -> Dictionary:
	var time_since := render_time - state.timestamp

	# Clamp extrapolation
	if time_since > extrapolation_limit:
		time_since = extrapolation_limit

	# Linear extrapolation using velocity
	var extrapolated_pos := state.position + state.velocity * time_since
	var extrapolated_rot := state.rotation + state.angular_velocity * time_since

	return {
		"position": extrapolated_pos,
		"rotation": extrapolated_rot,
		"velocity": state.velocity,
		"angular_velocity": state.angular_velocity,
		"extrapolated": true,
	}


## Lerp angles with proper wrapping
func _lerp_angles(a: Vector3, b: Vector3, t: float) -> Vector3:
	return Vector3(
		lerp_angle(a.x, b.x, t),
		lerp_angle(a.y, b.y, t),
		lerp_angle(a.z, b.z, t)
	)


## Convert state entry to dictionary
func _state_to_dict(state: StateEntry) -> Dictionary:
	return {
		"position": state.position,
		"rotation": state.rotation,
		"velocity": state.velocity,
		"angular_velocity": state.angular_velocity,
		"exact": true,
	}


## Clear buffer (for teleports or major corrections)
func clear_buffer() -> void:
	_state_buffer.clear()
	_last_applied_tick = 0


## Get latest state without interpolation
func get_latest_state() -> Dictionary:
	if _state_buffer.is_empty():
		return {}
	return _state_to_dict(_state_buffer.back())


## Set interpolation delay (higher = smoother but more latency)
func set_interpolation_delay(delay: float) -> void:
	interpolation_delay = clampf(delay, 0.05, 0.5)


## Get number of buffered states
func get_buffer_count() -> int:
	return _state_buffer.size()


## Check if buffer has enough states for interpolation
func is_ready() -> bool:
	return _state_buffer.size() >= 2
