# ZSDU Multiplayer Architecture

## Decision: Route A - Godot Headless Server

**Chosen architecture:** Godot headless server with C# backend orchestration.

This document commits the project to **Route A** - using Godot's high-level networking (ENet + RPC) as the authoritative game simulation, with a separate backend for matchmaking and server orchestration.

### Why Route A

- Fastest path to working multiplayer
- Leverages Godot's built-in ENet transport
- Server and client share the same codebase
- Already implemented and working
- Backend handles orchestration, NOT game logic

### What Route A Means

```
┌─────────────────────────────────────────────────────────────────────┐
│                        ROUTE A ARCHITECTURE                         │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│   ┌─────────────────────┐       ┌─────────────────────┐            │
│   │   ZSDU.Backend.exe  │       │   ZSDU.Backend.exe  │            │
│   │   (Orchestration)   │       │   (Orchestration)   │            │
│   │   HTTP :8080        │       │   HTTP :8080        │            │
│   │   TCP :7777         │       │   TCP :7777         │            │
│   └─────────┬───────────┘       └─────────┬───────────┘            │
│             │ spawns                      │ spawns                 │
│             ▼                             ▼                        │
│   ┌─────────────────────┐       ┌─────────────────────┐            │
│   │   godot --headless  │       │   godot --headless  │            │
│   │   AUTHORITATIVE     │       │   AUTHORITATIVE     │            │
│   │   Port :27015       │       │   Port :27016       │            │
│   └─────────────────────┘       └─────────────────────┘            │
│             ▲                             ▲                        │
│             │ ENet                        │ ENet                   │
│   ┌─────────┴─────────┐         ┌─────────┴─────────┐             │
│   │ Client  │ Client  │         │ Client  │ Client  │             │
│   │ Godot   │ Godot   │         │ Godot   │ Godot   │             │
│   └─────────┴─────────┘         └─────────┴─────────┘             │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Authority Laws

These rules are enforced everywhere. Violating them causes desync.

### Server Owns (Authority)

| Entity | Server Responsibility |
|--------|----------------------|
| **World State** | Phase, wave, round lifecycle |
| **Players** | Spawn position, health, death, extraction |
| **Zombies** | AI, pathing, attack decisions, spawning |
| **Combat** | Hit validation, damage application, raycasts |
| **Barricades** | Nail HP, joint physics, destruction |
| **Props** | Physics simulation, held state |
| **Loot/Corpses** | Spawn locations, contents, interactions |
| **Inventory** | Item ownership, currency (when implemented) |

### Client Owns (Local Only)

| Entity | Client Responsibility |
|--------|----------------------|
| **Camera** | First-person view, sensitivity |
| **UI** | Menus, HUD, crosshair |
| **Raw Input** | Mouse, keyboard, gamepad |
| **Audio** | Local sound effects, music |
| **Visual Effects** | Particles, decals, screen effects |

### The Golden Rule

```
CLIENT NEVER:
- Spawns players or zombies
- Applies damage directly
- Decides hit registration
- Moves entities authoritatively
- Modifies game state

CLIENT ALWAYS:
- Sends input/requests to server
- Waits for server validation
- Applies received snapshots
- Interpolates remote entities
```

---

## Connection Flow

```
DISCONNECTED → DISCOVERING → CONNECTING → SYNCING → PLAYING
     │              │             │          │         │
     │              │             │          │         │
  offline     traversal      ENet        world    gameplay
             registering   handshake    loading    active
```

### Phase Details

1. **DISCONNECTED** - No network connection
2. **DISCOVERING** - Talking to traversal server for session lookup
3. **CONNECTING** - ENet handshake with game server
4. **SYNCING** - Client receives full world snapshot for late join
5. **PLAYING** - Normal gameplay, receiving tick updates

---

## Server Directory Role

The `server/` directory is **orchestration infrastructure**, NOT game logic.

### What server/ Contains

```
server/
├── ZSDU.Backend/          # C# orchestration service
│   ├── Program.cs         # HTTP API + TCP traversal
│   ├── ServerOrchestrator # Spawns godot --headless processes
│   ├── SessionRegistry    # Tracks active game servers
│   └── GameService        # Match scoring, validation
└── README.md              # Deployment docs
```

### What server/ Does

- **Matchmaking** - `/match/find` endpoint pairs players to servers
- **Server spawning** - Starts new `godot_server.exe` instances
- **Health monitoring** - Heartbeat tracking, dead server cleanup
- **Session registry** - Maps players to their game servers
- **Future: Economy** - Inventory, trading (backend-validated)

### What server/ Does NOT Do

- Game simulation
- Physics
- AI decisions
- Hit detection
- Entity spawning
- Movement validation

All game logic runs in the Godot headless process.

---

## Network Protocol

### Transport

- **ENet** via Godot's `ENetMultiplayerPeer`
- Server port: 27015 (base), increments for additional servers
- Max players: 32 per server
- Tick rate: 60 Hz

### RPC Categories

| RPC | Direction | Reliability | Purpose |
|-----|-----------|-------------|---------|
| `send_player_input` | Client→Server | Unreliable Ordered | Input transmission |
| `broadcast_state_update` | Server→Clients | Unreliable Ordered | Tick snapshots |
| `broadcast_event` | Server→Clients | Reliable | Spawns, kills, events |
| `request_action` | Client→Server | Reliable | Interactions, actions |
| `request_interact` | Client→Server | Reliable | Entity interactions |

### State Synchronization

Every physics frame, server broadcasts:

```gdscript
{
    "tick": 12345,
    "players": { peer_id: { position, velocity, rotation, ... } },
    "zombies": { zombie_id: { position, health, state, ... } },
    "nails": { nail_id: { hp, active } },
    "props": { prop_id: { position, rotation, velocity, ... } }
}
```

Clients interpolate with 100ms jitter buffer.

---

## Golden Path Checklist

Use this checklist to verify multiplayer is working:

### Phase 1: Boot + Connect

- [ ] Host can start server (`NetworkManager.host_game()`)
- [ ] Console shows: `[Server] Started on port 27015`
- [ ] Client can connect (`NetworkManager.join_server()`)
- [ ] Console shows: `[Network] Peer connected: 2`
- [ ] Client receives peer ID confirmation
- [ ] Disconnect triggers: `[Network] Peer disconnected: 2`

### Phase 2: Spawn + Movement

- [ ] Server spawns player on connect (`GameState.spawn_player()`)
- [ ] Player appears at spawn point
- [ ] Second client sees first player
- [ ] Movement replicates (no jitter)
- [ ] Disconnect removes player from all clients

### Phase 3: Zombies

- [ ] Only server spawns zombies (`GameState.spawn_zombie()`)
- [ ] Clients see zombie via `broadcast_event`
- [ ] Zombie AI runs only on server (check `is_authority()`)
- [ ] Zombie positions sync smoothly
- [ ] Zombie death removes from all clients

### Phase 4: Combat + Barricades

- [ ] Client sends shoot request (`request_action("shoot", ...)`)
- [ ] Server validates and performs raycast
- [ ] Hit confirmation sent to all clients
- [ ] Damage applied server-side only
- [ ] Nails create physics joints server-side
- [ ] Nail destruction replicates

---

## Common Failure Patterns (And Fixes)

### Client Spawns Player Locally

**Symptom:** Duplicate players, desync, ghost players

**Fix:** Never call `spawn_player()` on client. Server calls it, then broadcasts event.

```gdscript
# WRONG - client code
func _on_connected():
    spawn_my_player()  # NO!

# RIGHT - server broadcasts, client handles event
func handle_event("spawn_player", data):
    _spawn_player_local(data.peer_id, data.position)
```

### Zombie AI on Clients

**Symptom:** Zombies behave differently for each player

**Fix:** Guard all AI with authority check:

```gdscript
func _physics_process(delta):
    if not NetworkManager.is_authority():
        return  # Clients skip AI entirely

    _update_pathfinding()
    _attack_logic()
```

### Client Applies Damage Directly

**Symptom:** Cheating, inconsistent health, "I shot him!" disputes

**Fix:** Client requests, server validates:

```gdscript
# WRONG - client applies damage
func shoot():
    var hit = raycast()
    hit.zombie.take_damage(25)  # NO!

# RIGHT - client requests, server validates
func shoot():
    NetworkManager.request_action.rpc_id(1, "shoot", {
        origin = camera.global_position,
        direction = -camera.global_basis.z,
        damage = 25
    })
```

### No Deterministic Disconnect Cleanup

**Symptom:** Ghost players, orphaned entities, memory leaks

**Fix:** Handle disconnect signal and clean up:

```gdscript
func _on_peer_disconnected(peer_id):
    if is_authority():
        _unregister_player(peer_id)
    GameState.on_player_disconnected(peer_id)  # Despawns player
```

---

## File Reference

### Core Networking

| File | Purpose |
|------|---------|
| `scripts/autoload/network_manager.gd` | ENet peer management, RPC routing |
| `scripts/autoload/game_state.gd` | Central game state, server tick |
| `scripts/autoload/headless_server.gd` | Dedicated server lifecycle |
| `scripts/autoload/entity_registry.gd` | Server-authoritative interactions |

### Player Networking

| File | Purpose |
|------|---------|
| `scripts/player/player_network_controller.gd` | Input + prediction + reconciliation |
| `scripts/network/entity_interpolator.gd` | Smooth interpolation for remotes |

### Entities

| File | Purpose |
|------|---------|
| `scripts/zombie/zombie_controller.gd` | Server-only AI state machine |
| `scripts/world/game_world.gd` | Spawn points, player spawning |

### Backend

| File | Purpose |
|------|---------|
| `server/ZSDU.Backend/Program.cs` | Orchestration service |
| `server/README.md` | Backend deployment docs |

---

## Summary

**Architecture:** Route A (Godot headless server)

**Server owns:** Everything that affects game state

**Client owns:** Camera, UI, input

**Backend:** Orchestration and matchmaking only

**Transport:** ENet with custom RPC-based replication

This architecture is implemented and working. Do not deviate.
