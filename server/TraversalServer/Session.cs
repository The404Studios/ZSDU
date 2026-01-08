using System;
using System.Net;
using System.Text.Json.Serialization;

namespace TraversalServer;

/// <summary>
/// Represents a game session registered with the traversal server.
/// </summary>
public class Session
{
    /// <summary>
    /// Unique session identifier (GUID)
    /// </summary>
    public string Id { get; set; } = Guid.NewGuid().ToString();

    /// <summary>
    /// Display name of the session
    /// </summary>
    public string Name { get; set; } = "Unnamed Session";

    /// <summary>
    /// Host's public IP address
    /// </summary>
    public string HostIp { get; set; } = "";

    /// <summary>
    /// Port the game server is listening on
    /// </summary>
    public int HostPort { get; set; } = 27015;

    /// <summary>
    /// Maximum number of players allowed
    /// </summary>
    public int MaxPlayers { get; set; } = 32;

    /// <summary>
    /// Current number of connected players
    /// </summary>
    public int CurrentPlayers { get; set; } = 1;

    /// <summary>
    /// Game version string for compatibility checking
    /// </summary>
    public string GameVersion { get; set; } = "1.0";

    /// <summary>
    /// When this session was created
    /// </summary>
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    /// <summary>
    /// Last heartbeat received from host
    /// </summary>
    public DateTime LastHeartbeat { get; set; } = DateTime.UtcNow;

    /// <summary>
    /// Internal: TCP client endpoint for the host
    /// </summary>
    [JsonIgnore]
    public EndPoint? HostEndpoint { get; set; }

    /// <summary>
    /// Check if session has timed out
    /// </summary>
    public bool IsTimedOut(TimeSpan timeout)
    {
        return DateTime.UtcNow - LastHeartbeat > timeout;
    }

    /// <summary>
    /// Update heartbeat timestamp
    /// </summary>
    public void RefreshHeartbeat()
    {
        LastHeartbeat = DateTime.UtcNow;
    }

    /// <summary>
    /// Create a sanitized copy for sending to clients
    /// </summary>
    public SessionInfo ToPublicInfo()
    {
        return new SessionInfo
        {
            Id = Id,
            Name = Name,
            HostIp = HostIp,
            HostPort = HostPort,
            MaxPlayers = MaxPlayers,
            CurrentPlayers = CurrentPlayers,
            GameVersion = GameVersion
        };
    }
}

/// <summary>
/// Public session info sent to clients (no internal data)
/// </summary>
public class SessionInfo
{
    public string Id { get; set; } = "";
    public string Name { get; set; } = "";
    public string HostIp { get; set; } = "";
    public int HostPort { get; set; }
    public int MaxPlayers { get; set; }
    public int CurrentPlayers { get; set; }
    public string GameVersion { get; set; } = "";
}
