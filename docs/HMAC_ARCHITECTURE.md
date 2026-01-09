# HMAC Authentication Architecture

## Overview

ZSDU uses HMAC-SHA256 for secure server-to-backend communication. This ensures that only authorized game servers can commit raid outcomes and modify player data.

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              GAME CLIENT                                     │
│  ┌─────────────┐    ┌──────────────┐    ┌─────────────────┐                │
│  │ EconomyService│◄──►│ LobbySystem  │◄──►│ Main Menu/Lobby │                │
│  │  (stash, items) │    │  (groups)    │    │     (UI)        │                │
│  └──────┬──────┘    └──────┬───────┘    └─────────────────┘                │
│         │                  │                                                 │
│         │   HTTP (unsigned - client requests)                               │
│         ▼                  ▼                                                 │
└─────────┼──────────────────┼────────────────────────────────────────────────┘
          │                  │
          ▼                  ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                           BACKEND SERVER                                     │
│                                                                              │
│  ┌────────────────────────────────────────────────────────────────┐        │
│  │                      HTTP API Layer                             │        │
│  │  /auth/login  /stash/*  /trader/*  /market/*  /lobby/*         │        │
│  │  (Client endpoints - no HMAC required)                          │        │
│  └────────────────────────────────────────────────────────────────┘        │
│                                                                              │
│  ┌────────────────────────────────────────────────────────────────┐        │
│  │                   SERVER API Layer (HMAC Required)              │        │
│  │  /server/raid/commit   /server/match/end   /server/player/ban  │        │
│  │                                                                  │        │
│  │  ┌──────────────────────────────────────────────────────────┐  │        │
│  │  │              HMAC Verification Middleware                 │  │        │
│  │  │  1. Extract { payload, signature, timestamp, server_id } │  │        │
│  │  │  2. Check timestamp within 5-minute window               │  │        │
│  │  │  3. Rebuild canonical string from payload                │  │        │
│  │  │  4. Compute HMAC-SHA256(secret, canonical)               │  │        │
│  │  │  5. Constant-time compare with signature                 │  │        │
│  │  │  6. Log server_id for audit trail                        │  │        │
│  │  └──────────────────────────────────────────────────────────┘  │        │
│  └────────────────────────────────────────────────────────────────┘        │
│                                                                              │
│  ┌────────────────────────────────────────────────────────────────┐        │
│  │                        Database                                 │        │
│  │  Characters │ Items │ Stashes │ Raids │ Matches │ AuditLog     │        │
│  └────────────────────────────────────────────────────────────────┘        │
└─────────────────────────────────────────────────────────────────────────────┘
          ▲                  ▲
          │                  │
          │   HTTP (HMAC-signed - server requests)
          │                  │
┌─────────┼──────────────────┼────────────────────────────────────────────────┐
│         │                  │                                                 │
│  ┌──────┴──────┐    ┌──────┴───────┐                                       │
│  │ RaidManager │◄──►│ CryptoUtils  │◄── SERVER_SECRET (env var)            │
│  │             │    │              │                                        │
│  │ - Track raids│    │ - HMAC-SHA256│                                        │
│  │ - Commit     │    │ - Sign/Verify│                                        │
│  │   outcomes   │    │ - Timestamps │                                        │
│  │             │    │ - Server ID  │                                        │
│  └──────┬──────┘    └──────────────┘                                       │
│         │                                                                    │
│         ▼                                                                    │
│  ┌─────────────────────────────────────────────────────────────────┐       │
│  │                      GAME SERVER                                 │       │
│  │  NetworkManager │ GameState │ WaveManager │ PlayerControllers   │       │
│  └─────────────────────────────────────────────────────────────────┘       │
│                              DEDICATED SERVER                               │
└─────────────────────────────────────────────────────────────────────────────┘
```

## HMAC Request Flow

```
┌────────────┐        ┌─────────────┐        ┌──────────────┐        ┌─────────┐
│ RaidManager│        │ CryptoUtils │        │   Backend    │        │Database │
└─────┬──────┘        └──────┬──────┘        └──────┬───────┘        └────┬────┘
      │                      │                      │                     │
      │ 1. Player extracts   │                      │                     │
      │    or dies           │                      │                     │
      │                      │                      │                     │
      │ 2. sign_raid_commit()│                      │                     │
      │─────────────────────►│                      │                     │
      │                      │                      │                     │
      │                      │ 3. Create payload:   │                     │
      │                      │    { raid_id,        │                     │
      │                      │      match_id,       │                     │
      │                      │      outcomes }      │                     │
      │                      │                      │                     │
      │                      │ 4. Get timestamp     │                     │
      │                      │    (Unix epoch)      │                     │
      │                      │                      │                     │
      │                      │ 5. Create canonical: │                     │
      │                      │    "ts|server_id|    │                     │
      │                      │     sorted_json"     │                     │
      │                      │                      │                     │
      │                      │ 6. HMAC-SHA256:      │                     │
      │                      │    sign(secret,      │                     │
      │                      │         canonical)   │                     │
      │                      │                      │                     │
      │◄─────────────────────│                      │                     │
      │  { payload,          │                      │                     │
      │    signature,        │                      │                     │
      │    timestamp,        │                      │                     │
      │    server_id }       │                      │                     │
      │                      │                      │                     │
      │ 7. POST /server/raid/commit                 │                     │
      │────────────────────────────────────────────►│                     │
      │                      │                      │                     │
      │                      │                      │ 8. Verify timestamp │
      │                      │                      │    (within 5 min)   │
      │                      │                      │                     │
      │                      │                      │ 9. Rebuild canonical│
      │                      │                      │    from payload     │
      │                      │                      │                     │
      │                      │                      │ 10. Compute HMAC    │
      │                      │                      │     with secret     │
      │                      │                      │                     │
      │                      │                      │ 11. Constant-time   │
      │                      │                      │     compare sigs    │
      │                      │                      │                     │
      │                      │                      │ 12. If valid:       │
      │                      │                      │─────────────────────►│
      │                      │                      │     Commit raid     │
      │                      │                      │     Update items    │
      │                      │                      │◄─────────────────────│
      │                      │                      │                     │
      │◄────────────────────────────────────────────│                     │
      │  { ok: true }        │                      │                     │
      │                      │                      │                     │
```

## Security Properties

### 1. Message Integrity
The HMAC signature ensures the payload hasn't been tampered with in transit.

```
HMAC(K, m) = H((K' ⊕ opad) || H((K' ⊕ ipad) || m))

Where:
- K  = Server secret (shared between game server and backend)
- m  = Canonical message (timestamp|server_id|sorted_json)
- H  = SHA-256 hash function
- K' = Key padded/hashed to block size (64 bytes)
- ipad = 0x36 repeated 64 times
- opad = 0x5c repeated 64 times
```

### 2. Replay Protection
Timestamp-based protection prevents captured requests from being replayed:

```
current_time - request_timestamp <= 300 seconds (5 minutes)
```

### 3. Server Authentication
Only servers with the correct `SERVER_SECRET` can generate valid signatures:

```bash
# Set on dedicated server
export SERVER_SECRET="your-256-bit-secret-key-here"
```

### 4. Timing Attack Prevention
Signatures are compared using constant-time comparison:

```gdscript
func _constant_time_compare(a: String, b: String) -> bool:
    if a.length() != b.length():
        return false
    var result := 0
    for i in range(a.length()):
        result |= a.unicode_at(i) ^ b.unicode_at(i)
    return result == 0
```

## Request Format

### Signed Request Structure
```json
{
    "payload": {
        "raid_id": "uuid-string",
        "match_id": "uuid-string",
        "outcomes": [
            {
                "character_id": "uuid-string",
                "survived": true,
                "provisional_loot": [
                    { "def_id": "item_bandage", "stack": 3 }
                ]
            }
        ]
    },
    "signature": "a1b2c3d4e5f6...64-char-hex-string",
    "timestamp": 1704067200,
    "server_id": "abc123def456"
}
```

### Canonical String Format
```
{timestamp}|{server_id}|{sorted_json_payload}

Example:
1704067200|abc123def456|{"match_id":"m123","outcomes":[...],"raid_id":"r456"}
```

## File Structure

```
scripts/autoload/
├── crypto_utils.gd      # HMAC implementation, signing, verification
├── raid_manager.gd      # Uses CryptoUtils for signed requests
├── backend_config.gd    # Backend URL configuration
└── economy_service.gd   # Client-side (unsigned) requests
```

## Configuration

### Environment Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `SERVER_SECRET` | Shared secret for HMAC signing | `zsdu_prod_secret_2024_abc123xyz` |
| `BACKEND_HOST` | Backend server hostname | `162.248.94.149` |
| `BACKEND_HTTP_PORT` | Backend HTTP port | `8080` |

### Autoload Order (project.godot)
```ini
[autoload]
BackendConfig="*res://scripts/autoload/backend_config.gd"
# ... other autoloads ...
CryptoUtils="*res://scripts/autoload/crypto_utils.gd"    # Before RaidManager
RaidManager="*res://scripts/autoload/raid_manager.gd"    # Uses CryptoUtils
```

## Backend Verification (Reference Implementation)

```typescript
// Node.js/Express example
import crypto from 'crypto';

const SERVER_SECRET = process.env.SERVER_SECRET;
const TIMESTAMP_WINDOW = 300; // 5 minutes

function verifySignedRequest(req, res, next) {
    const { payload, signature, timestamp, server_id } = req.body;

    // 1. Check timestamp
    const now = Math.floor(Date.now() / 1000);
    if (Math.abs(now - timestamp) > TIMESTAMP_WINDOW) {
        return res.status(403).json({ error: 'timestamp_expired' });
    }

    // 2. Rebuild canonical string
    const sortedPayload = sortKeys(payload);
    const canonical = `${timestamp}|${server_id}|${JSON.stringify(sortedPayload)}`;

    // 3. Compute expected signature
    const expectedSig = crypto
        .createHmac('sha256', SERVER_SECRET)
        .update(canonical)
        .digest('hex');

    // 4. Constant-time comparison
    if (!crypto.timingSafeEqual(
        Buffer.from(signature, 'hex'),
        Buffer.from(expectedSig, 'hex')
    )) {
        return res.status(401).json({ error: 'invalid_signature' });
    }

    // 5. Log for audit
    console.log(`[AUDIT] Server ${server_id} committed raid ${payload.raid_id}`);

    req.verifiedPayload = payload;
    req.serverId = server_id;
    next();
}

// Apply to server-only routes
app.post('/server/raid/commit', verifySignedRequest, handleRaidCommit);
```

## Error Codes

| HTTP Code | Error | Description |
|-----------|-------|-------------|
| 401 | `invalid_signature` | HMAC signature doesn't match |
| 403 | `timestamp_expired` | Request timestamp outside 5-minute window |
| 400 | `missing_fields` | Required fields missing from request |
| 500 | `internal_error` | Server-side error during verification |

## Testing

### Generate Test Signature
```gdscript
# In Godot editor
func _ready():
    var test_payload = {
        "raid_id": "test-raid-123",
        "match_id": "test-match-456",
        "outcomes": [{"character_id": "char-789", "survived": true}]
    }

    var signed = CryptoUtils.create_signed_request(test_payload)
    print("Payload: ", signed.payload)
    print("Signature: ", signed.signature)
    print("Timestamp: ", signed.timestamp)
    print("Server ID: ", signed.server_id)
```

### Verify Signature Locally
```gdscript
func _test_verify():
    var request = {
        "payload": {...},
        "signature": "abc123...",
        "timestamp": 1704067200,
        "server_id": "xyz789"
    }

    var result = CryptoUtils.verify_signed_request(request)
    print("Valid: ", result.valid)
    if not result.valid:
        print("Error: ", result.error)
```
