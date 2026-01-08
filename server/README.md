# ZSDU Backend

Single Windows console application for game server orchestration.

## Architecture

```
Windows Server 2022
┌─────────────────────────────────────────┐
│ ZSDU.Backend.exe                        │
│  ├─ HTTP API (:8080)                    │
│  │   ├─ /health           - Health check│
│  │   ├─ /status           - Stats       │
│  │   ├─ /servers          - Server list │
│  │   ├─ /servers/ready    - Server init │
│  │   ├─ /servers/heartbeat- Keepalive   │
│  │   └─ /match/find       - Matchmaking │
│  │                                      │
│  ├─ TCP Traversal (:7777)               │
│  │   └─ Session discovery (legacy)      │
│  │                                      │
│  ├─ ServerOrchestrator                  │
│  │   └─ Spawns godot_server.exe         │
│  │                                      │
│  ├─ SessionRegistry (in-memory)         │
│  │   ├─ Game servers                    │
│  │   ├─ Active matches                  │
│  │   └─ Player → match mapping          │
│  │                                      │
│  └─ GameService (in-process)            │
│      └─ Scoring, validation             │
└─────────────────────────────────────────┘
         │
         ├─→ godot_server.exe (:27015)
         ├─→ godot_server.exe (:27016)
         └─→ godot_server.exe (:27017)
```

## Quick Start (Windows)

```batch
cd ZSDU.Backend
run.bat
```

Or manually:

```batch
dotnet publish -c Release -r win-x64 --self-contained
bin\Release\net8.0\win-x64\ZSDU.Backend.exe
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `HTTP_PORT` | 8080 | HTTP API port |
| `TRAVERSAL_PORT` | 7777 | TCP traversal port |
| `BASE_GAME_PORT` | 27015 | First game server port |
| `MAX_SERVERS` | 10 | Maximum game server instances |
| `GODOT_SERVER_PATH` | godot_server.exe | Path to Godot server |
| `GODOT_PROJECT_PATH` | (empty) | Path to Godot project |
| `PUBLIC_IP` | 127.0.0.1 | Public IP for clients |

## API Endpoints

### Server Management (called by game servers)

**POST /servers/ready** - Server reports ready
```json
{ "port": 27015 }
```

**POST /servers/heartbeat** - Server heartbeat
```json
{ "serverId": "abc123", "playerCount": 5 }
```

### Matchmaking (called by clients)

**POST /match/find** - Find/create a match
```json
{ "playerId": "player123", "gameMode": "survival" }
```

Response:
```json
{
  "matchId": "match123",
  "status": "matched",
  "serverHost": "192.168.1.100",
  "serverPort": 27015,
  "gameMode": "survival"
}
```

### Game Events (called by game servers)

**POST /game/player_joined**
**POST /game/player_left**
**POST /game/wave_complete**
**POST /game/match_end**

## Future (Parked)

See `docs/future/` for:
- Kubernetes manifests
- Docker configuration
- Redis/MySQL setup
- Event broker architecture

These are NOT required for MVP.
