using System.Text.Json.Serialization;

namespace GameManager.Data;

/// <summary>
/// Game server instance status
/// </summary>
public enum ServerStatus
{
    Starting,
    Ready,
    InGame,
    Full,
    Stopping,
    Stopped,
    Error
}

/// <summary>
/// Matchmaking ticket status
/// </summary>
public enum TicketStatus
{
    Pending,
    Matched,
    Confirmed,
    Cancelled,
    TimedOut
}

/// <summary>
/// Represents a game server instance
/// </summary>
public class GameServer
{
    public string Id { get; set; } = Guid.NewGuid().ToString();
    public string Name { get; set; } = "";
    public string Host { get; set; } = "";
    public int Port { get; set; }
    public ServerStatus Status { get; set; } = ServerStatus.Starting;
    public int CurrentPlayers { get; set; }
    public int MaxPlayers { get; set; } = 32;
    public string MapName { get; set; } = "default";
    public string GameMode { get; set; } = "survival";
    public string Version { get; set; } = "1.0";
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public DateTime LastHeartbeat { get; set; } = DateTime.UtcNow;
    public Dictionary<string, string> Metadata { get; set; } = new();

    // Kubernetes specific
    public string? PodName { get; set; }
    public string? NodeName { get; set; }

    public bool IsAvailable => Status == ServerStatus.Ready && CurrentPlayers < MaxPlayers;
    public bool IsTimedOut(TimeSpan timeout) => DateTime.UtcNow - LastHeartbeat > timeout;
}

/// <summary>
/// Represents a player session
/// </summary>
public class PlayerSession
{
    public string Id { get; set; } = Guid.NewGuid().ToString();
    public string PlayerId { get; set; } = "";
    public string PlayerName { get; set; } = "";
    public string? CurrentServerId { get; set; }
    public string? MatchmakingTicketId { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public DateTime LastActivity { get; set; } = DateTime.UtcNow;
    public bool IsConnected { get; set; }

    // Stats for matchmaking
    public int SkillRating { get; set; } = 1000;
    public int GamesPlayed { get; set; }
    public int Wins { get; set; }
}

/// <summary>
/// Matchmaking ticket
/// </summary>
public class MatchmakingTicket
{
    public string Id { get; set; } = Guid.NewGuid().ToString();
    public List<string> PlayerIds { get; set; } = new();
    public TicketStatus Status { get; set; } = TicketStatus.Pending;
    public string? AssignedServerId { get; set; }
    public string GameMode { get; set; } = "survival";
    public string? PreferredRegion { get; set; }
    public int MinSkillRating { get; set; }
    public int MaxSkillRating { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public DateTime? MatchedAt { get; set; }
}

/// <summary>
/// Game session (a single match/round)
/// </summary>
public class GameSession
{
    public string Id { get; set; } = Guid.NewGuid().ToString();
    public string ServerId { get; set; } = "";
    public string GameMode { get; set; } = "survival";
    public string MapName { get; set; } = "default";
    public List<string> PlayerIds { get; set; } = new();
    public int CurrentWave { get; set; }
    public bool IsActive { get; set; } = true;
    public DateTime StartedAt { get; set; } = DateTime.UtcNow;
    public DateTime? EndedAt { get; set; }
    public Dictionary<string, int> Scores { get; set; } = new();
}

/// <summary>
/// Player data (persistent)
/// </summary>
public class PlayerData
{
    public string Id { get; set; } = "";
    public string Username { get; set; } = "";
    public string Email { get; set; } = "";
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public DateTime LastLogin { get; set; } = DateTime.UtcNow;

    // Stats
    public int TotalGamesPlayed { get; set; }
    public int TotalWins { get; set; }
    public int TotalZombieKills { get; set; }
    public int HighestWave { get; set; }
    public int SkillRating { get; set; } = 1000;

    // Inventory/Progression
    public int Currency { get; set; }
    public List<string> UnlockedItems { get; set; } = new();
    public Dictionary<string, int> ItemQuantities { get; set; } = new();
}

/// <summary>
/// Server registration request from a game server
/// </summary>
public class ServerRegistration
{
    public string Name { get; set; } = "";
    public int Port { get; set; }
    public int MaxPlayers { get; set; } = 32;
    public string MapName { get; set; } = "default";
    public string GameMode { get; set; } = "survival";
    public string Version { get; set; } = "1.0";
}

/// <summary>
/// Server heartbeat
/// </summary>
public class ServerHeartbeat
{
    public string ServerId { get; set; } = "";
    public int CurrentPlayers { get; set; }
    public ServerStatus Status { get; set; }
    public int CurrentWave { get; set; }
    public Dictionary<string, string>? Metadata { get; set; }
}

/// <summary>
/// Matchmaking request from a client
/// </summary>
public class MatchRequest
{
    public string PlayerId { get; set; } = "";
    public string GameMode { get; set; } = "survival";
    public string? PreferredRegion { get; set; }
    public List<string>? PartyMembers { get; set; }
}

/// <summary>
/// Connection info sent to client
/// </summary>
public class ConnectionInfo
{
    public string ServerId { get; set; } = "";
    public string Host { get; set; } = "";
    public int Port { get; set; }
    public string? AuthToken { get; set; }
}
