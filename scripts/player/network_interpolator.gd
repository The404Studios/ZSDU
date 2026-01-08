extends RefCounted
class_name NetworkInterpolator
## NetworkInterpolator - Smooth remote player movement
##
## Uses a jitter buffer to store recent states and interpolates between them.
## Falls back to extrapolation when no future states are available.
##
## Timeline:
##   [past states] ... [render time] ... [current time]
##                      ↑ interpolate here (100ms behind)

# Configuration
var interpolation_delay := 0.1  # 100ms - adjusts for network jitter
var extrapolation_limit := 0.25  # Max 250ms of extrapolation
var buffer_size := 32

# State buffer (circular, sorted by time)
var state_buffer: Array[Dictionary] = []
var buffer_head := 0

# Timing
var server_time_offset := 0.0  # Local time - server time
var last_received_time := 0.0

# Extrapolation state
var is_extrapolating := false
var extrapolation_start_time := 0.0


## Push a new state from server
func push_state(server_tick: int, position: Vector3, rotation: Vector3, velocity: Vector3) -> void:
	var server_time := server_tick / 60.0  # Assuming 60 tick server
	var local_time := Time.get_ticks_msec() / 1000.0

	# Update time offset (smoothed)
	var new_offset := local_time - server_time
	if server_time_offset == 0.0:
		server_time_offset = new_offset
	else:
		server_time_offset = lerpf(server_time_offset, new_offset, 0.1)

	last_received_time = local_time

	# Create state entry
	var state := {
		"time": server_time,
		"local_time": local_time,
		"position": position,
		"rotation": rotation,
		"velocity": velocity,
	}

	# Insert into buffer (keep sorted by time)
	_insert_sorted(state)

	# Reset extrapolation flag
	is_extrapolating = false


## Insert state keeping buffer sorted
func _insert_sorted(state: Dictionary) -> void:
	# Find insertion point
	var insert_idx := state_buffer.size()
	for i in range(state_buffer.size() - 1, -1, -1):
		if state_buffer[i].time < state.time:
			insert_idx = i + 1
			break
		elif state_buffer[i].time == state.time:
			# Replace duplicate
			state_buffer[i] = state
			return
		else:
			insert_idx = i

	state_buffer.insert(insert_idx, state)

	# Trim old states
	while state_buffer.size() > buffer_size:
		state_buffer.pop_front()


## Get interpolated state for current render time
func get_interpolated_state() -> Dictionary:
	if state_buffer.size() < 2:
		if state_buffer.size() == 1:
			return _extrapolate_from_last()
		return {}

	var local_time := Time.get_ticks_msec() / 1000.0
	var render_time := local_time - server_time_offset - interpolation_delay

	# Find two states to interpolate between
	var before: Dictionary = {}
	var after: Dictionary = {}

	for i in range(state_buffer.size() - 1):
		if state_buffer[i].time <= render_time and state_buffer[i + 1].time >= render_time:
			before = state_buffer[i]
			after = state_buffer[i + 1]
			break

	# If render time is before all states, use earliest
	if before.is_empty() and not state_buffer.is_empty():
		if render_time < state_buffer[0].time:
			return state_buffer[0].duplicate()

	# If render time is after all states, extrapolate
	if before.is_empty() or after.is_empty():
		return _extrapolate_from_last()

	# Interpolate
	is_extrapolating = false
	var t := (render_time - before.time) / (after.time - before.time)
	t = clampf(t, 0.0, 1.0)

	return {
		"position": before.position.lerp(after.position, t),
		"rotation": _lerp_rotation(before.rotation, after.rotation, t),
		"velocity": before.velocity.lerp(after.velocity, t),
		"is_extrapolating": false,
	}


## Extrapolate from last known state
func _extrapolate_from_last() -> Dictionary:
	if state_buffer.is_empty():
		return {}

	var last_state: Dictionary = state_buffer.back()
	var local_time := Time.get_ticks_msec() / 1000.0
	var time_since_last := local_time - last_state.local_time

	# Track extrapolation start
	if not is_extrapolating:
		is_extrapolating = true
		extrapolation_start_time = local_time

	# Limit extrapolation
	var extrap_time := minf(time_since_last, extrapolation_limit)

	# Simple linear extrapolation using velocity
	var velocity: Vector3 = last_state.velocity
	var extrap_position: Vector3 = last_state.position + velocity * extrap_time

	# Dampen extrapolation over time (become less confident)
	var dampen := 1.0 - (time_since_last / extrapolation_limit)
	dampen = maxf(dampen, 0.0)

	return {
		"position": last_state.position.lerp(extrap_position, dampen),
		"rotation": last_state.rotation,
		"velocity": velocity * dampen,
		"is_extrapolating": true,
		"extrapolation_time": time_since_last,
	}


## Lerp rotation handling wrap-around
func _lerp_rotation(from: Vector3, to: Vector3, t: float) -> Vector3:
	return Vector3(
		lerpf(from.x, to.x, t),
		lerp_angle(from.y, to.y, t),
		lerpf(from.z, to.z, t)
	)


## Clean old states (call periodically)
func cleanup_old_states() -> void:
	var local_time := Time.get_ticks_msec() / 1000.0
	var cutoff := local_time - server_time_offset - 1.0  # Keep 1 second of history

	while not state_buffer.is_empty() and state_buffer[0].time < cutoff:
		state_buffer.pop_front()


## Get network quality metrics
func get_metrics() -> Dictionary:
	var local_time := Time.get_ticks_msec() / 1000.0
	var time_since_update := local_time - last_received_time

	return {
		"buffer_size": state_buffer.size(),
		"is_extrapolating": is_extrapolating,
		"time_since_update": time_since_update,
		"interpolation_delay": interpolation_delay,
	}


## Adjust interpolation delay based on network conditions
func adapt_delay(jitter: float) -> void:
	# Increase delay if jitter is high
	interpolation_delay = clampf(0.05 + jitter * 2.0, 0.05, 0.2)
