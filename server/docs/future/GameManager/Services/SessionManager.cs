using System.Collections.Concurrent;
using GameManager.Data;
using GameManager.Events;

namespace GameManager.Services;

/// <summary>
/// Manages player sessions and game server registrations
/// </summary>
public class SessionManager
{
    private readonly ConcurrentDictionary<string, GameServer> _servers = new();
    private readonly ConcurrentDictionary<string, PlayerSession> _playerSessions = new();
    private readonly ConcurrentDictionary<string, GameSession> _gameSessions = new();
    private readonly EventBroker _eventBroker;
    private readonly Configuration _config;
    private readonly Timer _cleanupTimer;

    public SessionManager(EventBroker eventBroker, Configuration config)
    {
        _eventBroker = eventBroker;
        _config = config;

        // Cleanup timer
        _cleanupTimer = new Timer(
            _ => CleanupStale(),
            null,
            TimeSpan.FromSeconds(10),
            TimeSpan.FromSeconds(10));
    }

    // ============================================
    // Server Management
    // ============================================

    /// <summary>
    /// Register a game server
    /// </summary>
    public async Task<GameServer> RegisterServerAsync(ServerRegistration registration, string hostIp)
    {
        var server = new GameServer
        {
            Name = registration.Name,
            Host = hostIp,
            Port = registration.Port,
            MaxPlayers = registration.MaxPlayers,
            MapName = registration.MapName,
            GameMode = registration.GameMode,
            Version = registration.Version,
            Status = ServerStatus.Ready
        };

        _servers[server.Id] = server;

        await _eventBroker.PublishAsync(new ServerRegisteredEvent { Server = server });

        Console.WriteLine($"[SessionManager] Server registered: {server.Name} ({server.Id}) at {hostIp}:{registration.Port}");

        return server;
    }

    /// <summary>
    /// Unregister a game server
    /// </summary>
    public async Task UnregisterServerAsync(string serverId, string reason = "")
    {
        if (_servers.TryRemove(serverId, out var server))
        {
            // Disconnect all players on this server
            foreach (var session in _playerSessions.Values.Where(s => s.CurrentServerId == serverId))
            {
                session.CurrentServerId = null;
            }

            await _eventBroker.PublishAsync(new ServerUnregisteredEvent
            {
                ServerId = serverId,
                Reason = reason
            });

            Console.WriteLine($"[SessionManager] Server unregistered: {server.Name} ({serverId})");
        }
    }

    /// <summary>
    /// Process server heartbeat
    /// </summary>
    public async Task ProcessHeartbeatAsync(ServerHeartbeat heartbeat)
    {
        if (_servers.TryGetValue(heartbeat.ServerId, out var server))
        {
            var oldStatus = server.Status;
            server.LastHeartbeat = DateTime.UtcNow;
            server.CurrentPlayers = heartbeat.CurrentPlayers;
            server.Status = heartbeat.Status;

            if (heartbeat.Metadata != null)
            {
                foreach (var kvp in heartbeat.Metadata)
                {
                    server.Metadata[kvp.Key] = kvp.Value;
                }
            }

            // Emit status change event if changed
            if (oldStatus != server.Status)
            {
                await _eventBroker.PublishAsync(new ServerStatusChangedEvent
                {
                    ServerId = server.Id,
                    OldStatus = oldStatus,
                    NewStatus = server.Status
                });
            }

            await _eventBroker.PublishAsync(new ServerHeartbeatEvent
            {
                ServerId = server.Id,
                CurrentPlayers = heartbeat.CurrentPlayers
            });
        }
    }

    /// <summary>
    /// Get all available servers
    /// </summary>
    public IEnumerable<GameServer> GetAvailableServers()
    {
        return _servers.Values.Where(s => s.IsAvailable);
    }

    /// <summary>
    /// Get all servers
    /// </summary>
    public IEnumerable<GameServer> GetAllServers()
    {
        return _servers.Values;
    }

    /// <summary>
    /// Get server by ID
    /// </summary>
    public GameServer? GetServer(string serverId)
    {
        _servers.TryGetValue(serverId, out var server);
        return server;
    }

    /// <summary>
    /// Get total player count across all servers
    /// </summary>
    public int GetTotalPlayerCount()
    {
        return _servers.Values.Sum(s => s.CurrentPlayers);
    }

    // ============================================
    // Player Session Management
    // ============================================

    /// <summary>
    /// Create a new player session
    /// </summary>
    public async Task<PlayerSession> CreatePlayerSessionAsync(string playerId, string playerName)
    {
        var session = new PlayerSession
        {
            PlayerId = playerId,
            PlayerName = playerName,
            IsConnected = true
        };

        _playerSessions[session.Id] = session;

        await _eventBroker.PublishAsync(new PlayerConnectedEvent
        {
            PlayerId = playerId,
            SessionId = session.Id
        });

        Console.WriteLine($"[SessionManager] Player session created: {playerName} ({session.Id})");

        return session;
    }

    /// <summary>
    /// End a player session
    /// </summary>
    public async Task EndPlayerSessionAsync(string sessionId, string reason = "")
    {
        if (_playerSessions.TryRemove(sessionId, out var session))
        {
            session.IsConnected = false;

            // Leave current server if any
            if (session.CurrentServerId != null)
            {
                await LeaveServerAsync(session.Id);
            }

            await _eventBroker.PublishAsync(new PlayerDisconnectedEvent
            {
                PlayerId = session.PlayerId,
                SessionId = sessionId,
                Reason = reason
            });

            Console.WriteLine($"[SessionManager] Player session ended: {session.PlayerName}");
        }
    }

    /// <summary>
    /// Get player session by ID
    /// </summary>
    public PlayerSession? GetPlayerSession(string sessionId)
    {
        _playerSessions.TryGetValue(sessionId, out var session);
        return session;
    }

    /// <summary>
    /// Get player session by player ID
    /// </summary>
    public PlayerSession? GetPlayerSessionByPlayerId(string playerId)
    {
        return _playerSessions.Values.FirstOrDefault(s => s.PlayerId == playerId);
    }

    /// <summary>
    /// Assign player to a server
    /// </summary>
    public async Task<bool> JoinServerAsync(string sessionId, string serverId)
    {
        if (!_playerSessions.TryGetValue(sessionId, out var playerSession))
            return false;

        if (!_servers.TryGetValue(serverId, out var server))
            return false;

        if (!server.IsAvailable)
            return false;

        // Leave current server if any
        if (playerSession.CurrentServerId != null)
        {
            await LeaveServerAsync(sessionId);
        }

        playerSession.CurrentServerId = serverId;
        server.CurrentPlayers++;

        await _eventBroker.PublishAsync(new PlayerJoinedServerEvent
        {
            PlayerId = playerSession.PlayerId,
            ServerId = serverId
        });

        Console.WriteLine($"[SessionManager] Player {playerSession.PlayerName} joined server {server.Name}");

        return true;
    }

    /// <summary>
    /// Remove player from current server
    /// </summary>
    public async Task LeaveServerAsync(string sessionId)
    {
        if (!_playerSessions.TryGetValue(sessionId, out var playerSession))
            return;

        if (playerSession.CurrentServerId == null)
            return;

        var serverId = playerSession.CurrentServerId;
        playerSession.CurrentServerId = null;

        if (_servers.TryGetValue(serverId, out var server))
        {
            server.CurrentPlayers = Math.Max(0, server.CurrentPlayers - 1);
        }

        await _eventBroker.PublishAsync(new PlayerLeftServerEvent
        {
            PlayerId = playerSession.PlayerId,
            ServerId = serverId
        });
    }

    // ============================================
    // Game Session Management
    // ============================================

    /// <summary>
    /// Create a game session for a server
    /// </summary>
    public async Task<GameSession> CreateGameSessionAsync(string serverId, string gameMode, string mapName, List<string> playerIds)
    {
        var session = new GameSession
        {
            ServerId = serverId,
            GameMode = gameMode,
            MapName = mapName,
            PlayerIds = playerIds
        };

        _gameSessions[session.Id] = session;

        await _eventBroker.PublishAsync(new GameStartedEvent
        {
            SessionId = session.Id,
            ServerId = serverId,
            PlayerIds = playerIds
        });

        return session;
    }

    /// <summary>
    /// End a game session
    /// </summary>
    public async Task EndGameSessionAsync(string sessionId, int finalWave, Dictionary<string, int> scores)
    {
        if (_gameSessions.TryGetValue(sessionId, out var session))
        {
            session.IsActive = false;
            session.EndedAt = DateTime.UtcNow;
            session.CurrentWave = finalWave;
            session.Scores = scores;

            await _eventBroker.PublishAsync(new GameEndedEvent
            {
                SessionId = sessionId,
                FinalWave = finalWave,
                Scores = scores
            });
        }
    }

    // ============================================
    // Cleanup
    // ============================================

    private void CleanupStale()
    {
        var timeout = TimeSpan.FromSeconds(_config.SessionTimeoutSeconds);

        // Cleanup timed out servers
        var timedOutServers = _servers.Values
            .Where(s => s.IsTimedOut(timeout))
            .Select(s => s.Id)
            .ToList();

        foreach (var serverId in timedOutServers)
        {
            _ = UnregisterServerAsync(serverId, "heartbeat_timeout");
        }

        // Cleanup inactive player sessions
        var inactiveSessions = _playerSessions.Values
            .Where(s => !s.IsConnected && (DateTime.UtcNow - s.LastActivity).TotalMinutes > 5)
            .Select(s => s.Id)
            .ToList();

        foreach (var sessionId in inactiveSessions)
        {
            _playerSessions.TryRemove(sessionId, out _);
        }
    }
}
