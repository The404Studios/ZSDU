using System.Collections.Concurrent;

namespace ZSDU.Backend;

/// <summary>
/// LobbyService - Pre-game lobby management
/// </summary>
public class LobbyService
{
    private readonly ConcurrentDictionary<string, Lobby> _lobbies = new();
    private readonly ConcurrentDictionary<string, string> _playerToLobby = new(); // player -> lobby

    public class Lobby
    {
        public string Id { get; set; } = "";
        public string Name { get; set; } = "";
        public string LeaderId { get; set; } = "";
        public string GameMode { get; set; } = "survival";
        public int MaxPlayers { get; set; } = 4;
        public string State { get; set; } = "waiting"; // waiting, starting, in_game
        public List<LobbyPlayer> Players { get; set; } = new();
        public string? ServerId { get; set; }
        public string? ServerHost { get; set; }
        public int? ServerPort { get; set; }
        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    }

    public class LobbyPlayer
    {
        public string Id { get; set; } = "";
        public string Name { get; set; } = "";
        public bool Ready { get; set; }
        public int SpawnIndex { get; set; }
    }

    /// <summary>
    /// Create a new lobby
    /// </summary>
    public Lobby CreateLobby(string playerId, string playerName, string lobbyName, int maxPlayers, string gameMode)
    {
        // Check if player already in a lobby
        if (_playerToLobby.ContainsKey(playerId))
        {
            LeaveLobby(playerId);
        }

        var lobby = new Lobby
        {
            Id = GenerateLobbyCode(),
            Name = lobbyName,
            LeaderId = playerId,
            MaxPlayers = Math.Clamp(maxPlayers, 1, 8),
            GameMode = gameMode,
            Players = new List<LobbyPlayer>
            {
                new LobbyPlayer
                {
                    Id = playerId,
                    Name = playerName,
                    Ready = false,
                    SpawnIndex = 0
                }
            }
        };

        _lobbies[lobby.Id] = lobby;
        _playerToLobby[playerId] = lobby.Id;

        Console.WriteLine($"[Lobby] Created: {lobby.Id} by {playerName}");
        return lobby;
    }

    /// <summary>
    /// Join an existing lobby
    /// </summary>
    public Lobby? JoinLobby(string playerId, string playerName, string lobbyId)
    {
        // Normalize lobby ID (support short codes)
        lobbyId = lobbyId.ToUpper();

        // Find lobby by ID or partial match
        Lobby? lobby = null;
        if (_lobbies.TryGetValue(lobbyId, out lobby))
        {
            // Found by exact ID
        }
        else
        {
            // Try partial match (for short codes)
            foreach (var kv in _lobbies)
            {
                if (kv.Key.StartsWith(lobbyId) || kv.Value.Id.StartsWith(lobbyId))
                {
                    lobby = kv.Value;
                    break;
                }
            }
        }

        if (lobby == null)
        {
            Console.WriteLine($"[Lobby] Not found: {lobbyId}");
            return null;
        }

        if (lobby.State != "waiting")
        {
            Console.WriteLine($"[Lobby] Game already started: {lobbyId}");
            return null;
        }

        if (lobby.Players.Count >= lobby.MaxPlayers)
        {
            Console.WriteLine($"[Lobby] Full: {lobbyId}");
            return null;
        }

        // Leave current lobby if in one
        if (_playerToLobby.ContainsKey(playerId))
        {
            LeaveLobby(playerId);
        }

        // Add player
        lobby.Players.Add(new LobbyPlayer
        {
            Id = playerId,
            Name = playerName,
            Ready = false,
            SpawnIndex = lobby.Players.Count
        });

        _playerToLobby[playerId] = lobby.Id;

        Console.WriteLine($"[Lobby] {playerName} joined {lobby.Name}");
        return lobby;
    }

    /// <summary>
    /// Leave current lobby
    /// </summary>
    public void LeaveLobby(string playerId)
    {
        if (!_playerToLobby.TryRemove(playerId, out var lobbyId))
            return;

        if (!_lobbies.TryGetValue(lobbyId, out var lobby))
            return;

        // Remove player
        lobby.Players.RemoveAll(p => p.Id == playerId);

        // If lobby empty, remove it
        if (lobby.Players.Count == 0)
        {
            _lobbies.TryRemove(lobbyId, out _);
            Console.WriteLine($"[Lobby] Removed empty: {lobbyId}");
            return;
        }

        // If leader left, assign new leader
        if (lobby.LeaderId == playerId)
        {
            lobby.LeaderId = lobby.Players[0].Id;
            Console.WriteLine($"[Lobby] New leader: {lobby.Players[0].Name}");
        }

        // Update spawn indices
        for (int i = 0; i < lobby.Players.Count; i++)
        {
            lobby.Players[i].SpawnIndex = i;
        }
    }

    /// <summary>
    /// Set player ready state
    /// </summary>
    public void SetReady(string playerId, bool ready)
    {
        if (!_playerToLobby.TryGetValue(playerId, out var lobbyId))
            return;

        if (!_lobbies.TryGetValue(lobbyId, out var lobby))
            return;

        var player = lobby.Players.Find(p => p.Id == playerId);
        if (player != null)
        {
            player.Ready = ready;
        }
    }

    /// <summary>
    /// Start the game (leader only)
    /// </summary>
    public bool StartGame(string playerId, string lobbyId, string serverHost, int serverPort, string? serverId = null)
    {
        if (!_lobbies.TryGetValue(lobbyId, out var lobby))
            return false;

        if (lobby.LeaderId != playerId)
            return false;

        if (lobby.State != "waiting")
            return false;

        // Check all players ready
        if (!lobby.Players.All(p => p.Ready || p.Id == lobby.LeaderId))
            return false;

        lobby.State = "starting";
        lobby.ServerHost = serverHost;
        lobby.ServerPort = serverPort;
        lobby.ServerId = serverId;

        Console.WriteLine($"[Lobby] Starting game: {lobby.Name} on {serverHost}:{serverPort}");
        return true;
    }

    /// <summary>
    /// Mark lobby as in game
    /// </summary>
    public void SetInGame(string lobbyId)
    {
        if (_lobbies.TryGetValue(lobbyId, out var lobby))
        {
            lobby.State = "in_game";
        }
    }

    /// <summary>
    /// Get lobby by ID
    /// </summary>
    public Lobby? GetLobby(string lobbyId)
    {
        _lobbies.TryGetValue(lobbyId, out var lobby);
        return lobby;
    }

    /// <summary>
    /// Get lobby for player
    /// </summary>
    public Lobby? GetPlayerLobby(string playerId)
    {
        if (!_playerToLobby.TryGetValue(playerId, out var lobbyId))
            return null;

        return GetLobby(lobbyId);
    }

    /// <summary>
    /// Get all public lobbies
    /// </summary>
    public List<object> GetPublicLobbies()
    {
        return _lobbies.Values
            .Where(l => l.State == "waiting")
            .OrderByDescending(l => l.CreatedAt)
            .Take(50)
            .Select(l => (object)new
            {
                id = l.Id,
                name = l.Name,
                playerCount = l.Players.Count,
                maxPlayers = l.MaxPlayers,
                gameMode = l.GameMode,
                leaderName = l.Players.FirstOrDefault(p => p.Id == l.LeaderId)?.Name ?? "Unknown"
            })
            .ToList();
    }

    /// <summary>
    /// Convert lobby to response object
    /// </summary>
    public object ToResponse(Lobby lobby)
    {
        return new
        {
            id = lobby.Id,
            name = lobby.Name,
            leaderId = lobby.LeaderId,
            maxPlayers = lobby.MaxPlayers,
            gameMode = lobby.GameMode,
            state = lobby.State,
            serverHost = lobby.ServerHost,
            serverPort = lobby.ServerPort,
            groupName = lobby.Name, // For spawn assignment
            players = lobby.Players.Select(p => new
            {
                id = p.Id,
                name = p.Name,
                ready = p.Ready,
                spawnIndex = p.SpawnIndex
            }).ToList()
        };
    }

    /// <summary>
    /// Generate a unique lobby code
    /// </summary>
    private static string GenerateLobbyCode()
    {
        const string chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
        var random = new Random();
        return new string(Enumerable.Range(0, 8).Select(_ => chars[random.Next(chars.Length)]).ToArray());
    }

    /// <summary>
    /// Cleanup old lobbies
    /// </summary>
    public void CleanupOldLobbies()
    {
        var cutoff = DateTime.UtcNow.AddHours(-1);
        var toRemove = _lobbies.Where(kv => kv.Value.CreatedAt < cutoff && kv.Value.State != "in_game")
            .Select(kv => kv.Key)
            .ToList();

        foreach (var id in toRemove)
        {
            if (_lobbies.TryRemove(id, out var lobby))
            {
                foreach (var player in lobby.Players)
                {
                    _playerToLobby.TryRemove(player.Id, out _);
                }
                Console.WriteLine($"[Lobby] Cleaned up old lobby: {id}");
            }
        }
    }
}
