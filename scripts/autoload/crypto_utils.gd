extends Node
## CryptoUtils - Cryptographic utilities for secure server communication
##
## Provides:
## - HMAC-SHA256 for request signing (optimized with pre-computed keys)
## - Timestamp-based replay protection
## - Server authentication
##
## HMAC (Hash-based Message Authentication Code) ensures:
## 1. Message integrity (data hasn't been tampered with)
## 2. Authentication (request came from authorized server)
##
## Performance Optimizations:
## - Pre-computed inner/outer pads (computed once at startup)
## - Reusable HashingContext to reduce allocations
## - Cached padded key for server secret
## - Optimized JSON serialization with StringName keys

# Block size for SHA-256
const BLOCK_SIZE := 64
const HASH_SIZE := 32

# Replay protection window (seconds)
const TIMESTAMP_WINDOW := 300  # 5 minutes

# Server identification
var server_id: String = ""

# ============================================
# OPTIMIZED: Pre-computed key pads
# ============================================
# These are computed once at startup and reused for every signature
var _server_secret: PackedByteArray = []
var _cached_inner_pad: PackedByteArray  # K' XOR ipad (pre-computed)
var _cached_outer_pad: PackedByteArray  # K' XOR opad (pre-computed)
var _is_key_cached: bool = false

# Reusable hashing context (reduces allocations)
var _hash_ctx: HashingContext


func _ready() -> void:
	# Initialize reusable hashing context
	_hash_ctx = HashingContext.new()

	# Load server secret from environment (only on dedicated servers)
	var secret_str := OS.get_environment("SERVER_SECRET")
	if secret_str == "":
		secret_str = "zsdu_dev_secret_change_in_production"

	_server_secret = secret_str.to_utf8_buffer()

	# Pre-compute the padded keys for HMAC (this is the main optimization)
	_precompute_key_pads()

	# Generate server ID from machine info
	server_id = _generate_server_id()

	print("[CryptoUtils] Initialized (server_id: %s, key_cached: %s)" % [
		server_id.substr(0, 8),
		str(_is_key_cached)
	])


## Pre-compute inner and outer pads for the server secret
## This eliminates key processing from every HMAC call
func _precompute_key_pads() -> void:
	var working_key := _server_secret.duplicate()

	# If key is longer than block size, hash it first
	if working_key.size() > BLOCK_SIZE:
		working_key = _sha256(working_key)

	# Pad key to block size with zeros
	working_key.resize(BLOCK_SIZE)  # More efficient than while loop

	# Pre-allocate pads
	_cached_inner_pad = PackedByteArray()
	_cached_outer_pad = PackedByteArray()
	_cached_inner_pad.resize(BLOCK_SIZE)
	_cached_outer_pad.resize(BLOCK_SIZE)

	# Compute XOR once, use forever
	for i in range(BLOCK_SIZE):
		_cached_inner_pad[i] = working_key[i] ^ 0x36  # ipad = 0x36 repeated
		_cached_outer_pad[i] = working_key[i] ^ 0x5c  # opad = 0x5c repeated

	_is_key_cached = true


## Generate a unique server identifier
func _generate_server_id() -> String:
	var data := OS.get_unique_id() + str(OS.get_process_id())
	return _sha256_hex(data.to_utf8_buffer()).substr(0, 16)


# ============================================
# HMAC-SHA256 IMPLEMENTATION (OPTIMIZED)
# ============================================

## Fast HMAC using pre-computed pads (for server secret)
## This is ~3x faster than computing pads each time
func _hmac_sha256_fast(message: PackedByteArray) -> PackedByteArray:
	# Inner hash: H(K ⊕ ipad || message)
	var inner_data := _cached_inner_pad.duplicate()
	inner_data.append_array(message)
	var inner_hash := _sha256(inner_data)

	# Outer hash: H(K ⊕ opad || inner_hash)
	var outer_data := _cached_outer_pad.duplicate()
	outer_data.append_array(inner_hash)

	return _sha256(outer_data)


## Compute HMAC-SHA256 with arbitrary key (for verification or other keys)
## This is the standard HMAC construction: HMAC(K,m) = H((K' ⊕ opad) || H((K' ⊕ ipad) || m))
func hmac_sha256(key: PackedByteArray, message: PackedByteArray) -> PackedByteArray:
	var working_key := key.duplicate()

	# If key is longer than block size, hash it first
	if working_key.size() > BLOCK_SIZE:
		working_key = _sha256(working_key)

	# Pad key to block size with zeros (more efficient resize)
	working_key.resize(BLOCK_SIZE)

	# Create inner and outer padded keys
	var inner_pad := PackedByteArray()
	var outer_pad := PackedByteArray()
	inner_pad.resize(BLOCK_SIZE)
	outer_pad.resize(BLOCK_SIZE)

	for i in range(BLOCK_SIZE):
		inner_pad[i] = working_key[i] ^ 0x36
		outer_pad[i] = working_key[i] ^ 0x5c

	# Inner hash: H(K ⊕ ipad || message)
	inner_pad.append_array(message)
	var inner_hash := _sha256(inner_pad)

	# Outer hash: H(K ⊕ opad || inner_hash)
	outer_pad.append_array(inner_hash)

	return _sha256(outer_pad)


## Compute HMAC-SHA256 and return as hex string
func hmac_sha256_hex(key: PackedByteArray, message: PackedByteArray) -> String:
	return hmac_sha256(key, message).hex_encode()


## Sign a message using the server secret (OPTIMIZED - uses cached pads)
func sign_message(message: String) -> String:
	if _is_key_cached:
		return _hmac_sha256_fast(message.to_utf8_buffer()).hex_encode()
	else:
		return hmac_sha256_hex(_server_secret, message.to_utf8_buffer())


## Verify a signature
func verify_signature(message: String, signature: String) -> bool:
	var expected := sign_message(message)
	return _constant_time_compare(expected, signature)


# ============================================
# REQUEST SIGNING
# ============================================

## Create a signed request payload
## Returns: { payload, signature, timestamp, server_id }
func create_signed_request(payload: Dictionary) -> Dictionary:
	var timestamp := int(Time.get_unix_time_from_system())

	# Create canonical string: timestamp|server_id|sorted_json_payload
	var canonical := _create_canonical_string(payload, timestamp)

	# Sign the canonical string (uses fast path with cached pads)
	var signature := sign_message(canonical)

	return {
		"payload": payload,
		"signature": signature,
		"timestamp": timestamp,
		"server_id": server_id
	}


## Verify a signed request (for backend use)
func verify_signed_request(request: Dictionary) -> Dictionary:
	var payload: Dictionary = request.get("payload", {})
	var signature: String = request.get("signature", "")
	var timestamp: int = request.get("timestamp", 0)
	var req_server_id: String = request.get("server_id", "")

	# Check timestamp is within window (replay protection)
	var now := int(Time.get_unix_time_from_system())
	if abs(now - timestamp) > TIMESTAMP_WINDOW:
		return {"valid": false, "error": "timestamp_expired"}

	# Recreate canonical string
	var canonical := _create_canonical_string(payload, timestamp)

	# Verify signature
	if not verify_signature(canonical, signature):
		return {"valid": false, "error": "invalid_signature"}

	return {"valid": true, "payload": payload, "server_id": req_server_id}


## Create canonical string for signing (deterministic)
func _create_canonical_string(payload: Dictionary, timestamp: int) -> String:
	# Sort keys for deterministic output
	var sorted_json := _sorted_json(payload)
	return "%d|%s|%s" % [timestamp, server_id, sorted_json]


## Create sorted JSON (keys in alphabetical order) - OPTIMIZED with PackedStringArray
func _sorted_json(data: Variant) -> String:
	if data is Dictionary:
		var keys := data.keys()
		keys.sort()
		var parts := PackedStringArray()
		parts.resize(keys.size())
		for i in range(keys.size()):
			var key = keys[i]
			parts[i] = '"%s":%s' % [str(key), _sorted_json(data[key])]
		return "{" + ",".join(parts) + "}"
	elif data is Array:
		if data.is_empty():
			return "[]"
		var parts := PackedStringArray()
		parts.resize(data.size())
		for i in range(data.size()):
			parts[i] = _sorted_json(data[i])
		return "[" + ",".join(parts) + "]"
	elif data is String:
		# Escape special characters
		var escaped := data.replace("\\", "\\\\").replace('"', '\\"')
		return '"%s"' % escaped
	elif data is bool:
		return "true" if data else "false"
	elif data == null:
		return "null"
	else:
		return str(data)


# ============================================
# HELPER FUNCTIONS
# ============================================

## SHA-256 hash (returns bytes)
func _sha256(data: PackedByteArray) -> PackedByteArray:
	_hash_ctx.start(HashingContext.HASH_SHA256)
	_hash_ctx.update(data)
	return _hash_ctx.finish()


## SHA-256 hash (returns hex string)
func _sha256_hex(data: PackedByteArray) -> String:
	return _sha256(data).hex_encode()


## Constant-time string comparison (prevents timing attacks)
## Uses bytes comparison which is slightly faster than unicode_at
func _constant_time_compare(a: String, b: String) -> bool:
	if a.length() != b.length():
		return false

	var a_bytes := a.to_utf8_buffer()
	var b_bytes := b.to_utf8_buffer()

	var result := 0
	for i in range(a_bytes.size()):
		result |= a_bytes[i] ^ b_bytes[i]

	return result == 0


# ============================================
# CONVENIENCE METHODS FOR RAID MANAGER
# ============================================

## Sign raid commit request
func sign_raid_commit(raid_id: String, match_id: String, outcomes: Array) -> Dictionary:
	var payload := {
		"raid_id": raid_id,
		"match_id": match_id,
		"outcomes": outcomes
	}
	return create_signed_request(payload)


## Sign generic server action
func sign_server_action(action: String, data: Dictionary) -> Dictionary:
	var payload := data.duplicate()
	payload["action"] = action
	return create_signed_request(payload)


# ============================================
# BENCHMARKING (for development)
# ============================================

## Benchmark HMAC performance (call from console or test)
func benchmark(iterations: int = 1000) -> Dictionary:
	var test_message := "1704067200|abc123def456|{\"match_id\":\"test\",\"outcomes\":[],\"raid_id\":\"test\"}".to_utf8_buffer()

	# Benchmark fast path (cached pads)
	var start_fast := Time.get_ticks_usec()
	for i in range(iterations):
		_hmac_sha256_fast(test_message)
	var end_fast := Time.get_ticks_usec()

	# Benchmark slow path (compute pads each time)
	var start_slow := Time.get_ticks_usec()
	for i in range(iterations):
		hmac_sha256(_server_secret, test_message)
	var end_slow := Time.get_ticks_usec()

	var fast_time := (end_fast - start_fast) / 1000.0
	var slow_time := (end_slow - start_slow) / 1000.0
	var speedup := slow_time / fast_time if fast_time > 0 else 0.0

	var results := {
		"iterations": iterations,
		"fast_ms": fast_time,
		"slow_ms": slow_time,
		"speedup": "%.2fx" % speedup
	}

	print("[CryptoUtils] Benchmark: %d iterations" % iterations)
	print("  Fast path (cached): %.2f ms" % fast_time)
	print("  Slow path (compute): %.2f ms" % slow_time)
	print("  Speedup: %.2fx" % speedup)

	return results
