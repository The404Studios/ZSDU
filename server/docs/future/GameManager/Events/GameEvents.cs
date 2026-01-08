using GameManager.Data;

namespace GameManager.Events;

/// <summary>
/// Base class for all game events
/// </summary>
public abstract class GameEvent
{
    public string EventId { get; } = Guid.NewGuid().ToString();
    public DateTime Timestamp { get; } = DateTime.UtcNow;
    public abstract string EventType { get; }
}

// ============================================
// Server Events
// ============================================

public class ServerRegisteredEvent : GameEvent
{
    public override string EventType => "server.registered";
    public required GameServer Server { get; init; }
}

public class ServerUnregisteredEvent : GameEvent
{
    public override string EventType => "server.unregistered";
    public required string ServerId { get; init; }
    public string Reason { get; init; } = "";
}

public class ServerStatusChangedEvent : GameEvent
{
    public override string EventType => "server.status_changed";
    public required string ServerId { get; init; }
    public required ServerStatus OldStatus { get; init; }
    public required ServerStatus NewStatus { get; init; }
}

public class ServerHeartbeatEvent : GameEvent
{
    public override string EventType => "server.heartbeat";
    public required string ServerId { get; init; }
    public required int CurrentPlayers { get; init; }
}

// ============================================
// Player Events
// ============================================

public class PlayerConnectedEvent : GameEvent
{
    public override string EventType => "player.connected";
    public required string PlayerId { get; init; }
    public required string SessionId { get; init; }
}

public class PlayerDisconnectedEvent : GameEvent
{
    public override string EventType => "player.disconnected";
    public required string PlayerId { get; init; }
    public required string SessionId { get; init; }
    public string Reason { get; init; } = "";
}

public class PlayerJoinedServerEvent : GameEvent
{
    public override string EventType => "player.joined_server";
    public required string PlayerId { get; init; }
    public required string ServerId { get; init; }
}

public class PlayerLeftServerEvent : GameEvent
{
    public override string EventType => "player.left_server";
    public required string PlayerId { get; init; }
    public required string ServerId { get; init; }
}

// ============================================
// Matchmaking Events
// ============================================

public class MatchmakingStartedEvent : GameEvent
{
    public override string EventType => "matchmaking.started";
    public required string TicketId { get; init; }
    public required List<string> PlayerIds { get; init; }
    public required string GameMode { get; init; }
}

public class MatchFoundEvent : GameEvent
{
    public override string EventType => "matchmaking.match_found";
    public required string TicketId { get; init; }
    public required string ServerId { get; init; }
    public required List<string> PlayerIds { get; init; }
}

public class MatchmakingCancelledEvent : GameEvent
{
    public override string EventType => "matchmaking.cancelled";
    public required string TicketId { get; init; }
    public string Reason { get; init; } = "";
}

public class MatchmakingTimedOutEvent : GameEvent
{
    public override string EventType => "matchmaking.timed_out";
    public required string TicketId { get; init; }
}

// ============================================
// Game Session Events
// ============================================

public class GameStartedEvent : GameEvent
{
    public override string EventType => "game.started";
    public required string SessionId { get; init; }
    public required string ServerId { get; init; }
    public required List<string> PlayerIds { get; init; }
}

public class GameEndedEvent : GameEvent
{
    public override string EventType => "game.ended";
    public required string SessionId { get; init; }
    public required int FinalWave { get; init; }
    public required Dictionary<string, int> Scores { get; init; }
}

public class WaveStartedEvent : GameEvent
{
    public override string EventType => "game.wave_started";
    public required string SessionId { get; init; }
    public required int WaveNumber { get; init; }
}

public class WaveCompletedEvent : GameEvent
{
    public override string EventType => "game.wave_completed";
    public required string SessionId { get; init; }
    public required int WaveNumber { get; init; }
    public required int ZombiesKilled { get; init; }
}

// ============================================
// System Events
// ============================================

public class ScaleUpRequestedEvent : GameEvent
{
    public override string EventType => "system.scale_up";
    public required int RequestedCount { get; init; }
    public string Reason { get; init; } = "";
}

public class ScaleDownRequestedEvent : GameEvent
{
    public override string EventType => "system.scale_down";
    public required int RequestedCount { get; init; }
    public required List<string> ServerIds { get; init; }
}
