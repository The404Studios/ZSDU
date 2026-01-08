using System.Collections.Concurrent;

namespace ZSDU.Backend;

/// <summary>
/// In-memory session and server registry
/// No database, no Redis - just ConcurrentDictionary
/// </summary>
public class SessionRegistry
{
    // Game servers
    private readonly ConcurrentDictionary<string, GameServer> _servers = new();

    // Active matches/sessions
    private readonly ConcurrentDictionary<string, MatchSession> _matches = new();

    // Player sessions (player -> match mapping)
    private readonly ConcurrentDictionary<string, string> _playerMatches = new();

    // ============================================
    // SERVER MANAGEMENT
    // ============================================

    public GameServer RegisterServer(int port, int pid)
    {
        var server = new GameServer
        {
            Id = Guid.NewGuid().ToString("N")[..8],
            Port = port,
            ProcessId = pid,
            Status = ServerStatus.Starting,
            CreatedAt = DateTime.UtcNow
        };

        _servers[server.Id] = server;
        Console.WriteLine($"[Registry] Server registered: {server.Id} on port {port}");
        return server;
    }

    public void UnregisterServer(string serverId)
    {
        if (_servers.TryRemove(serverId, out var server))
        {
            Console.WriteLine($"[Registry] Server unregistered: {serverId}");

            // Clean up any matches on this server
            foreach (var match in _matches.Values.Where(m => m.ServerId == serverId).ToList())
            {
                EndMatch(match.Id, "server_shutdown");
            }
        }
    }

    public GameServer? GetServer(string serverId)
    {
        _servers.TryGetValue(serverId, out var server);
        return server;
    }

    public GameServer? GetServerByPort(int port)
    {
        return _servers.Values.FirstOrDefault(s => s.Port == port);
    }

    public IEnumerable<GameServer> GetAllServers() => _servers.Values;

    public IEnumerable<GameServer> GetAvailableServers()
    {
        return _servers.Values.Where(s =>
            s.Status == ServerStatus.Ready &&
            s.CurrentPlayers < s.MaxPlayers);
    }

    public void ServerReady(string serverId)
    {
        if (_servers.TryGetValue(serverId, out var server))
        {
            server.Status = ServerStatus.Ready;
            server.LastHeartbeat = DateTime.UtcNow;
            Console.WriteLine($"[Registry] Server ready: {serverId}");
        }
    }

    public void ServerHeartbeat(string serverId, int playerCount)
    {
        if (_servers.TryGetValue(serverId, out var server))
        {
            server.LastHeartbeat = DateTime.UtcNow;
            server.CurrentPlayers = playerCount;
        }
    }

    public List<string> GetTimedOutServers(TimeSpan timeout)
    {
        var cutoff = DateTime.UtcNow - timeout;
        return _servers.Values
            .Where(s => s.Status != ServerStatus.Starting && s.LastHeartbeat < cutoff)
            .Select(s => s.Id)
            .ToList();
    }

    // ============================================
    // MATCH MANAGEMENT
    // ============================================

    public MatchSession CreateMatch(string serverId, string gameMode = "survival")
    {
        var match = new MatchSession
        {
            Id = Guid.NewGuid().ToString("N")[..8],
            ServerId = serverId,
            GameMode = gameMode,
            Status = MatchStatus.Waiting,
            CreatedAt = DateTime.UtcNow
        };

        _matches[match.Id] = match;

        // Update server status
        if (_servers.TryGetValue(serverId, out var server))
        {
            server.Status = ServerStatus.InGame;
            server.CurrentMatchId = match.Id;
        }

        Console.WriteLine($"[Registry] Match created: {match.Id} on server {serverId}");
        return match;
    }

    public MatchSession? GetMatch(string matchId)
    {
        _matches.TryGetValue(matchId, out var match);
        return match;
    }

    public MatchSession? GetMatchByServer(string serverId)
    {
        return _matches.Values.FirstOrDefault(m => m.ServerId == serverId && m.Status != MatchStatus.Ended);
    }

    public void AddPlayerToMatch(string matchId, string playerId)
    {
        if (_matches.TryGetValue(matchId, out var match))
        {
            if (!match.PlayerIds.Contains(playerId))
            {
                match.PlayerIds.Add(playerId);
            }
            _playerMatches[playerId] = matchId;

            // Update server player count
            if (_servers.TryGetValue(match.ServerId, out var server))
            {
                server.CurrentPlayers = match.PlayerIds.Count;
            }
        }
    }

    public void RemovePlayerFromMatch(string playerId)
    {
        if (_playerMatches.TryRemove(playerId, out var matchId))
        {
            if (_matches.TryGetValue(matchId, out var match))
            {
                match.PlayerIds.Remove(playerId);

                // Update server player count
                if (_servers.TryGetValue(match.ServerId, out var server))
                {
                    server.CurrentPlayers = match.PlayerIds.Count;
                }
            }
        }
    }

    public string? GetPlayerMatch(string playerId)
    {
        _playerMatches.TryGetValue(playerId, out var matchId);
        return matchId;
    }

    public void EndMatch(string matchId, string reason = "")
    {
        if (_matches.TryGetValue(matchId, out var match))
        {
            match.Status = MatchStatus.Ended;
            match.EndedAt = DateTime.UtcNow;

            // Clear player mappings
            foreach (var playerId in match.PlayerIds.ToList())
            {
                _playerMatches.TryRemove(playerId, out _);
            }

            // Reset server
            if (_servers.TryGetValue(match.ServerId, out var server))
            {
                server.Status = ServerStatus.Ready;
                server.CurrentMatchId = null;
                server.CurrentPlayers = 0;
            }

            Console.WriteLine($"[Registry] Match ended: {matchId} ({reason})");
        }
    }

    // ============================================
    // STATISTICS
    // ============================================

    public RegistryStats GetStats()
    {
        var servers = _servers.Values.ToList();
        return new RegistryStats
        {
            TotalServers = servers.Count,
            ReadyServers = servers.Count(s => s.Status == ServerStatus.Ready),
            InGameServers = servers.Count(s => s.Status == ServerStatus.InGame),
            TotalPlayers = servers.Sum(s => s.CurrentPlayers),
            ActiveMatches = _matches.Values.Count(m => m.Status != MatchStatus.Ended)
        };
    }
}

// ============================================
// DATA MODELS
// ============================================

public enum ServerStatus
{
    Starting,
    Ready,
    InGame,
    Stopping,
    Error
}

public enum MatchStatus
{
    Waiting,
    InProgress,
    Ended
}

public class GameServer
{
    public string Id { get; set; } = "";
    public int Port { get; set; }
    public int ProcessId { get; set; }
    public ServerStatus Status { get; set; }
    public int CurrentPlayers { get; set; }
    public int MaxPlayers { get; set; } = 32;
    public string? CurrentMatchId { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime LastHeartbeat { get; set; }
}

public class MatchSession
{
    public string Id { get; set; } = "";
    public string ServerId { get; set; } = "";
    public string GameMode { get; set; } = "survival";
    public MatchStatus Status { get; set; }
    public List<string> PlayerIds { get; set; } = new();
    public int CurrentWave { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime? EndedAt { get; set; }
}

public class RegistryStats
{
    public int TotalServers { get; set; }
    public int ReadyServers { get; set; }
    public int InGameServers { get; set; }
    public int TotalPlayers { get; set; }
    public int ActiveMatches { get; set; }
}
