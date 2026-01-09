extends Node
## CryptoUtils - Cryptographic utilities for secure server communication
##
## Provides:
## - HMAC-SHA256 for request signing
## - Timestamp-based replay protection
## - Server authentication
##
## HMAC (Hash-based Message Authentication Code) ensures:
## 1. Message integrity (data hasn't been tampered with)
## 2. Authentication (request came from authorized server)

# Block size for SHA-256
const BLOCK_SIZE := 64
const HASH_SIZE := 32

# Replay protection window (seconds)
const TIMESTAMP_WINDOW := 300  # 5 minutes

# Server identification
var server_id: String = ""
var _server_secret: PackedByteArray = []


func _ready() -> void:
	# Load server secret from environment (only on dedicated servers)
	var secret_str := OS.get_environment("SERVER_SECRET")
	if secret_str == "":
		secret_str = "zsdu_dev_secret_change_in_production"

	_server_secret = secret_str.to_utf8_buffer()

	# Generate server ID from machine info
	server_id = _generate_server_id()

	print("[CryptoUtils] Initialized (server_id: %s)" % server_id.substr(0, 8))


## Generate a unique server identifier
func _generate_server_id() -> String:
	var data := OS.get_unique_id() + str(OS.get_process_id())
	return _sha256_hex(data.to_utf8_buffer()).substr(0, 16)


# ============================================
# HMAC-SHA256 IMPLEMENTATION
# ============================================

## Compute HMAC-SHA256
## This is the standard HMAC construction: HMAC(K,m) = H((K' ⊕ opad) || H((K' ⊕ ipad) || m))
func hmac_sha256(key: PackedByteArray, message: PackedByteArray) -> PackedByteArray:
	var working_key := key.duplicate()

	# If key is longer than block size, hash it first
	if working_key.size() > BLOCK_SIZE:
		working_key = _sha256(working_key)

	# Pad key to block size with zeros
	while working_key.size() < BLOCK_SIZE:
		working_key.append(0)

	# Create inner and outer padded keys
	var inner_pad := PackedByteArray()
	var outer_pad := PackedByteArray()
	inner_pad.resize(BLOCK_SIZE)
	outer_pad.resize(BLOCK_SIZE)

	for i in range(BLOCK_SIZE):
		inner_pad[i] = working_key[i] ^ 0x36  # ipad = 0x36 repeated
		outer_pad[i] = working_key[i] ^ 0x5c  # opad = 0x5c repeated

	# Inner hash: H(K ⊕ ipad || message)
	var inner_data := inner_pad
	inner_data.append_array(message)
	var inner_hash := _sha256(inner_data)

	# Outer hash: H(K ⊕ opad || inner_hash)
	var outer_data := outer_pad
	outer_data.append_array(inner_hash)
	var outer_hash := _sha256(outer_data)

	return outer_hash


## Compute HMAC-SHA256 and return as hex string
func hmac_sha256_hex(key: PackedByteArray, message: PackedByteArray) -> String:
	return hmac_sha256(key, message).hex_encode()


## Sign a message using the server secret
func sign_message(message: String) -> String:
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

	# Sign the canonical string
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


## Create sorted JSON (keys in alphabetical order)
func _sorted_json(data: Variant) -> String:
	if data is Dictionary:
		var keys := data.keys()
		keys.sort()
		var parts: Array[String] = []
		for key in keys:
			parts.append('"%s":%s' % [str(key), _sorted_json(data[key])])
		return "{" + ",".join(parts) + "}"
	elif data is Array:
		var parts: Array[String] = []
		for item in data:
			parts.append(_sorted_json(item))
		return "[" + ",".join(parts) + "]"
	elif data is String:
		return '"%s"' % data.replace("\\", "\\\\").replace('"', '\\"')
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
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(data)
	return ctx.finish()


## SHA-256 hash (returns hex string)
func _sha256_hex(data: PackedByteArray) -> String:
	return _sha256(data).hex_encode()


## Constant-time string comparison (prevents timing attacks)
func _constant_time_compare(a: String, b: String) -> bool:
	if a.length() != b.length():
		return false

	var result := 0
	for i in range(a.length()):
		result |= a.unicode_at(i) ^ b.unicode_at(i)

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
