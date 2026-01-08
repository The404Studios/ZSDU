using System.Net;
using System.Text;
using System.Text.Json;

namespace ZSDU.Backend;

/// <summary>
/// HTTP API Server
/// Handles matchmaking, server registration, and status endpoints
/// </summary>
public class HttpApi
{
    private readonly HttpListener _listener;
    private readonly Config _config;
    private readonly SessionRegistry _registry;
    private readonly ServerOrchestrator _orchestrator;
    private readonly GameService _gameService;
    private readonly FriendService _friendService;
    private readonly LobbyService _lobbyService;

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        WriteIndented = false
    };

    public HttpApi(Config config, SessionRegistry registry, ServerOrchestrator orchestrator, GameService gameService)
    {
        _config = config;
        _registry = registry;
        _orchestrator = orchestrator;
        _gameService = gameService;
        _friendService = new FriendService();
        _lobbyService = new LobbyService();
        _listener = new HttpListener();
    }

    public async Task StartAsync(CancellationToken ct)
    {
        var prefix = $"http://+:{_config.HttpPort}/";
        _listener.Prefixes.Add(prefix);

        try
        {
            _listener.Start();
            Console.WriteLine($"[HTTP] Listening on port {_config.HttpPort}");
        }
        catch (HttpListenerException ex)
        {
            // Try localhost only if + fails (requires admin)
            _listener.Prefixes.Clear();
            _listener.Prefixes.Add($"http://localhost:{_config.HttpPort}/");
            _listener.Start();
            Console.WriteLine($"[HTTP] Listening on localhost:{_config.HttpPort} (run as admin for all interfaces)");
        }

        while (!ct.IsCancellationRequested)
        {
            try
            {
                var context = await _listener.GetContextAsync().WaitAsync(ct);
                _ = HandleRequestAsync(context);
            }
            catch (OperationCanceledException)
            {
                break;
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[HTTP] Error: {ex.Message}");
            }
        }

        _listener.Stop();
    }

    private async Task HandleRequestAsync(HttpListenerContext context)
    {
        var request = context.Request;
        var response = context.Response;

        try
        {
            var path = request.Url?.AbsolutePath ?? "/";
            var method = request.HttpMethod;

            // Log request
            Console.WriteLine($"[HTTP] {method} {path}");

            // Route request
            object? result = (path, method) switch
            {
                // Health & Status
                ("/health", "GET") => new { status = "healthy", timestamp = DateTime.UtcNow },
                ("/status", "GET") => GetStatus(),

                // Server Management (called by game servers)
                ("/servers", "GET") => GetServers(),
                ("/servers/ready", "POST") => await HandleServerReady(request),
                ("/servers/heartbeat", "POST") => await HandleServerHeartbeat(request),

                // Matchmaking (called by clients)
                ("/match/find", "POST") => await HandleMatchFind(request),
                var (p, "GET") when p.StartsWith("/match/") => GetMatch(p["/match/".Length..]),

                // Game events (called by game servers)
                ("/game/player_joined", "POST") => await HandlePlayerJoined(request),
                ("/game/player_left", "POST") => await HandlePlayerLeft(request),
                ("/game/wave_complete", "POST") => await HandleWaveComplete(request),
                ("/game/match_end", "POST") => await HandleMatchEnd(request),

                // Friend system
                ("/friends/add", "POST") => await HandleFriendAdd(request),
                ("/friends/remove", "POST") => await HandleFriendRemove(request),
                ("/friends/accept", "POST") => await HandleFriendAccept(request),
                ("/friends/decline", "POST") => await HandleFriendDecline(request),
                ("/friends/status", "POST") => await HandleFriendStatus(request),
                ("/friends/requests", "POST") => await HandleFriendRequests(request),
                ("/friends/invite", "POST") => await HandleFriendInvite(request),
                ("/friends/list", "POST") => await HandleFriendList(request),

                // Lobby system
                ("/lobby/create", "POST") => await HandleLobbyCreate(request),
                ("/lobby/join", "POST") => await HandleLobbyJoin(request),
                ("/lobby/leave", "POST") => await HandleLobbyLeave(request),
                ("/lobby/ready", "POST") => await HandleLobbyReady(request),
                ("/lobby/start", "POST") => await HandleLobbyStart(request),
                ("/lobby/status", "POST") => await HandleLobbyStatus(request),
                ("/lobby/claim_spawn", "POST") => await HandleLobbyClaimSpawn(request),
                ("/lobby/list", "GET") => GetLobbyList(),

                _ => null
            };

            if (result == null)
            {
                await SendJsonAsync(response, new { error = "Not found" }, 404);
            }
            else
            {
                await SendJsonAsync(response, result);
            }
        }
        catch (Exception ex)
        {
            Console.WriteLine($"[HTTP] Request error: {ex.Message}");
            await SendJsonAsync(response, new { error = ex.Message }, 500);
        }
    }

    // ============================================
    // STATUS ENDPOINTS
    // ============================================

    private object GetStatus()
    {
        var stats = _registry.GetStats();
        return new
        {
            healthy = true,
            uptime = DateTime.UtcNow,
            stats.TotalServers,
            stats.ReadyServers,
            stats.InGameServers,
            stats.TotalPlayers,
            stats.ActiveMatches
        };
    }

    private object GetServers()
    {
        return _registry.GetAllServers().Select(s => new
        {
            s.Id,
            s.Port,
            status = s.Status.ToString().ToLower(),
            s.CurrentPlayers,
            s.MaxPlayers,
            s.CurrentMatchId
        });
    }

    // ============================================
    // SERVER REGISTRATION (called by game servers)
    // ============================================

    /// <summary>
    /// POST /servers/ready
    /// Called by game server when it's initialized and ready to accept players
    /// Body: { "port": 27015 }
    /// </summary>
    private async Task<object> HandleServerReady(HttpListenerRequest request)
    {
        var body = await ReadBodyAsync<ServerReadyRequest>(request);
        if (body == null)
            return new { error = "Invalid request" };

        // Find server by port
        var server = _registry.GetServerByPort(body.Port);
        if (server == null)
        {
            // Server not spawned by us - register it (supports external servers)
            server = _registry.RegisterServer(body.Port, 0);
        }

        _registry.ServerReady(server.Id);

        Console.WriteLine($"[HTTP] Server ready: {server.Id} on port {body.Port}");

        return new
        {
            serverId = server.Id,
            message = "Server registered as ready"
        };
    }

    /// <summary>
    /// POST /servers/heartbeat
    /// Called periodically by game servers to report status
    /// Body: { "serverId": "abc123", "playerCount": 5 }
    /// </summary>
    private async Task<object> HandleServerHeartbeat(HttpListenerRequest request)
    {
        var body = await ReadBodyAsync<ServerHeartbeatRequest>(request);
        if (body == null || string.IsNullOrEmpty(body.ServerId))
            return new { error = "Invalid request" };

        var server = _registry.GetServer(body.ServerId);
        if (server == null)
            return new { error = "Server not found" };

        _registry.ServerHeartbeat(body.ServerId, body.PlayerCount);

        return new { message = "OK" };
    }

    // ============================================
    // MATCHMAKING (called by clients)
    // ============================================

    /// <summary>
    /// POST /match/find
    /// Find or create a match for a player
    /// Body: { "playerId": "player123", "gameMode": "survival" }
    /// </summary>
    private async Task<object> HandleMatchFind(HttpListenerRequest request)
    {
        var body = await ReadBodyAsync<MatchFindRequest>(request);
        if (body == null || string.IsNullOrEmpty(body.PlayerId))
            return new { error = "Invalid request" };

        // Check if player already in a match
        var existingMatchId = _registry.GetPlayerMatch(body.PlayerId);
        if (existingMatchId != null)
        {
            var existingMatch = _registry.GetMatch(existingMatchId);
            if (existingMatch != null && existingMatch.Status != MatchStatus.Ended)
            {
                var existingServer = _registry.GetServer(existingMatch.ServerId);
                return new
                {
                    matchId = existingMatch.Id,
                    status = "already_matched",
                    serverHost = "162.248.94.149",  // Production server
                    serverPort = existingServer?.Port ?? 0
                };
            }
        }

        // Find available server
        var server = _orchestrator.GetAvailableServer();
        if (server == null)
        {
            // Try spawning a new one
            server = await _orchestrator.SpawnServerAsync();
            if (server == null)
            {
                return new { error = "No servers available", status = "unavailable" };
            }

            // Wait for it to be ready
            for (int i = 0; i < 30; i++)
            {
                await Task.Delay(1000);
                server = _registry.GetServer(server.Id);
                if (server?.Status == ServerStatus.Ready)
                    break;
            }

            if (server?.Status != ServerStatus.Ready)
            {
                return new { error = "Server failed to start", status = "error" };
            }
        }

        // Get or create match on this server
        var match = _registry.GetMatchByServer(server.Id);
        if (match == null)
        {
            match = _registry.CreateMatch(server.Id, body.GameMode ?? "survival");
        }

        // Add player to match
        _registry.AddPlayerToMatch(match.Id, body.PlayerId);

        Console.WriteLine($"[HTTP] Player {body.PlayerId} matched to {match.Id} on server {server.Id}");

        return new
        {
            matchId = match.Id,
            status = "matched",
            serverHost = "162.248.94.149",  // Production server
            serverPort = server.Port,
            gameMode = match.GameMode
        };
    }

    /// <summary>
    /// GET /match/{matchId}
    /// Get match status
    /// </summary>
    private object GetMatch(string matchId)
    {
        var match = _registry.GetMatch(matchId);
        if (match == null)
            return new { error = "Match not found" };

        var server = _registry.GetServer(match.ServerId);

        return new
        {
            matchId = match.Id,
            status = match.Status.ToString().ToLower(),
            gameMode = match.GameMode,
            playerCount = match.PlayerIds.Count,
            currentWave = match.CurrentWave,
            serverPort = server?.Port ?? 0
        };
    }

    // ============================================
    // GAME EVENTS (called by game servers)
    // ============================================

    private async Task<object> HandlePlayerJoined(HttpListenerRequest request)
    {
        var body = await ReadBodyAsync<PlayerEventRequest>(request);
        if (body == null) return new { error = "Invalid request" };

        var match = _registry.GetMatch(body.MatchId);
        if (match != null)
        {
            _registry.AddPlayerToMatch(match.Id, body.PlayerId);
        }

        return new { message = "OK" };
    }

    private async Task<object> HandlePlayerLeft(HttpListenerRequest request)
    {
        var body = await ReadBodyAsync<PlayerEventRequest>(request);
        if (body == null) return new { error = "Invalid request" };

        _registry.RemovePlayerFromMatch(body.PlayerId);

        return new { message = "OK" };
    }

    private async Task<object> HandleWaveComplete(HttpListenerRequest request)
    {
        var body = await ReadBodyAsync<WaveCompleteRequest>(request);
        if (body == null) return new { error = "Invalid request" };

        var match = _registry.GetMatch(body.MatchId);
        if (match != null)
        {
            match.CurrentWave = body.WaveNumber;
            match.Status = MatchStatus.InProgress;
        }

        return new { message = "OK" };
    }

    private async Task<object> HandleMatchEnd(HttpListenerRequest request)
    {
        var body = await ReadBodyAsync<MatchEndRequest>(request);
        if (body == null) return new { error = "Invalid request" };

        _registry.EndMatch(body.MatchId, body.Reason ?? "completed");

        return new { message = "OK" };
    }

    // ============================================
    // FRIEND SYSTEM
    // ============================================

    private async Task<object> HandleFriendAdd(HttpListenerRequest request)
    {
        var body = await ReadBodyAsync<FriendRequest>(request);
        if (body == null) return new { error = "Invalid request" };

        _friendService.SendFriendRequest(body.PlayerId, body.FriendId);
        return new { message = "Friend request sent" };
    }

    private async Task<object> HandleFriendRemove(HttpListenerRequest request)
    {
        var body = await ReadBodyAsync<FriendRequest>(request);
        if (body == null) return new { error = "Invalid request" };

        _friendService.RemoveFriend(body.PlayerId, body.FriendId);
        return new { message = "Friend removed" };
    }

    private async Task<object> HandleFriendAccept(HttpListenerRequest request)
    {
        var body = await ReadBodyAsync<FriendRequest>(request);
        if (body == null) return new { error = "Invalid request" };

        var friend = _friendService.AcceptFriendRequest(body.PlayerId, body.FriendId);
        return new { message = "Friend added", friend };
    }

    private async Task<object> HandleFriendDecline(HttpListenerRequest request)
    {
        var body = await ReadBodyAsync<FriendRequest>(request);
        if (body == null) return new { error = "Invalid request" };

        _friendService.DeclineFriendRequest(body.PlayerId, body.FriendId);
        return new { message = "Request declined" };
    }

    private async Task<object> HandleFriendStatus(HttpListenerRequest request)
    {
        var body = await ReadBodyAsync<FriendStatusRequest>(request);
        if (body == null) return new { error = "Invalid request" };

        // Update player's online status
        _friendService.UpdatePlayerStatus(body.PlayerId, true, _registry.GetPlayerMatch(body.PlayerId));

        var statuses = _friendService.GetFriendStatuses(body.FriendIds);
        return new { statuses };
    }

    private async Task<object> HandleFriendRequests(HttpListenerRequest request)
    {
        var body = await ReadBodyAsync<PlayerIdRequest>(request);
        if (body == null) return new { error = "Invalid request" };

        var requests = _friendService.GetPendingRequests(body.PlayerId);
        var invites = _friendService.GetPendingInvites(body.PlayerId);
        return new { requests, invites };
    }

    private async Task<object> HandleFriendInvite(HttpListenerRequest request)
    {
        var body = await ReadBodyAsync<FriendInviteRequest>(request);
        if (body == null) return new { error = "Invalid request" };

        _friendService.SendGameInvite(body.FromPlayerId, body.ToPlayerId, body.ServerInfo);
        return new { message = "Invite sent" };
    }

    private async Task<object> HandleFriendList(HttpListenerRequest request)
    {
        var body = await ReadBodyAsync<PlayerIdRequest>(request);
        if (body == null) return new { error = "Invalid request" };

        var friends = _friendService.GetFriends(body.PlayerId);
        return new { friends };
    }

    // ============================================
    // LOBBY SYSTEM
    // ============================================

    // All lobby endpoints return { lobby: {...} } for consistency
    private async Task<object> HandleLobbyCreate(HttpListenerRequest request)
    {
        var body = await ReadBodyAsync<LobbyCreateRequest>(request);
        if (body == null || string.IsNullOrEmpty(body.PlayerId))
            return new { error = "Invalid request" };

        var lobby = _lobbyService.CreateLobby(
            body.PlayerId,
            body.PlayerName ?? "Player",
            body.LobbyName ?? "Game Lobby",
            body.MaxPlayers > 0 ? body.MaxPlayers : 4,
            body.GameMode ?? "survival"
        );

        return new { lobby = _lobbyService.ToResponse(lobby) };
    }

    private async Task<object> HandleLobbyJoin(HttpListenerRequest request)
    {
        var body = await ReadBodyAsync<LobbyJoinRequest>(request);
        if (body == null || string.IsNullOrEmpty(body.PlayerId) || string.IsNullOrEmpty(body.LobbyId))
            return new { error = "Invalid request" };

        var lobby = _lobbyService.JoinLobby(body.PlayerId, body.PlayerName ?? "Player", body.LobbyId);
        if (lobby == null)
            return new { error = "Could not join lobby" };

        return new { lobby = _lobbyService.ToResponse(lobby) };
    }

    private async Task<object> HandleLobbyLeave(HttpListenerRequest request)
    {
        var body = await ReadBodyAsync<PlayerIdRequest>(request);
        if (body == null || string.IsNullOrEmpty(body.PlayerId))
            return new { error = "Invalid request" };

        _lobbyService.LeaveLobby(body.PlayerId);
        return new { message = "Left lobby" };
    }

    private async Task<object> HandleLobbyReady(HttpListenerRequest request)
    {
        var body = await ReadBodyAsync<LobbyReadyRequest>(request);
        if (body == null || string.IsNullOrEmpty(body.PlayerId))
            return new { error = "Invalid request" };

        _lobbyService.SetReady(body.PlayerId, body.Ready);

        var lobby = _lobbyService.GetPlayerLobby(body.PlayerId);
        if (lobby == null)
            return new { error = "Not in a lobby" };

        return new { lobby = _lobbyService.ToResponse(lobby) };
    }

    private async Task<object> HandleLobbyStart(HttpListenerRequest request)
    {
        var body = await ReadBodyAsync<LobbyStartRequest>(request);
        if (body == null || string.IsNullOrEmpty(body.PlayerId) || string.IsNullOrEmpty(body.LobbyId))
            return new { error = "Invalid request" };

        var lobby = _lobbyService.GetLobby(body.LobbyId);
        if (lobby == null)
            return new { error = "Lobby not found" };

        // Find available server for this lobby
        var server = _orchestrator.GetAvailableServer();
        if (server == null)
        {
            server = await _orchestrator.SpawnServerAsync();
            if (server == null)
                return new { error = "No servers available", status = "unavailable" };

            // Wait for server to be ready
            for (int i = 0; i < 30; i++)
            {
                await Task.Delay(1000);
                server = _registry.GetServer(server.Id);
                if (server?.Status == ServerStatus.Ready)
                    break;
            }

            if (server?.Status != ServerStatus.Ready)
                return new { error = "Server failed to start", status = "error" };
        }

        // Start the game - use config.PublicHost (single source of truth)
        var success = _lobbyService.StartGame(body.PlayerId, body.LobbyId, _config.PublicHost, server.Port, server.Id);
        if (!success)
            return new { error = "Cannot start game" };

        // Create match for this lobby
        var match = _registry.CreateMatch(server.Id, lobby.GameMode);
        foreach (var player in lobby.Players)
        {
            _registry.AddPlayerToMatch(match.Id, player.Id);
        }

        lobby = _lobbyService.GetLobby(body.LobbyId);
        return new
        {
            success = true,
            matchId = match.Id,
            serverHost = _config.PublicHost,
            serverPort = server.Port,
            lobby = _lobbyService.ToResponse(lobby!)
        };
    }

    private async Task<object> HandleLobbyStatus(HttpListenerRequest request)
    {
        var body = await ReadBodyAsync<LobbyStatusRequest>(request);
        if (body == null)
            return new { error = "Invalid request" };

        LobbyService.Lobby? lobby = null;

        if (!string.IsNullOrEmpty(body.LobbyId))
        {
            lobby = _lobbyService.GetLobby(body.LobbyId);
        }
        else if (!string.IsNullOrEmpty(body.PlayerId))
        {
            lobby = _lobbyService.GetPlayerLobby(body.PlayerId);
        }

        if (lobby == null)
            return new { error = "Lobby not found" };

        return new { lobby = _lobbyService.ToResponse(lobby) };
    }

    private object GetLobbyList()
    {
        var lobbies = _lobbyService.GetPublicLobbies();
        return new { lobbies };
    }

    /// <summary>
    /// POST /lobby/claim_spawn
    /// Called by game server to get authoritative spawn assignment for a player
    /// </summary>
    private async Task<object> HandleLobbyClaimSpawn(HttpListenerRequest request)
    {
        var body = await ReadBodyAsync<LobbyClaimSpawnRequest>(request);
        if (body == null || string.IsNullOrEmpty(body.LobbyId) || string.IsNullOrEmpty(body.PlayerId))
            return new { error = "Invalid request" };

        var lobby = _lobbyService.GetLobby(body.LobbyId);
        if (lobby == null)
            return new { error = "Lobby not found" };

        // Find player in lobby
        var player = lobby.Players.Find(p => p.Id == body.PlayerId);
        if (player == null)
            return new { error = "Player not in lobby" };

        // Return server-authoritative spawn assignment
        return new
        {
            playerId = player.Id,
            groupName = lobby.Name,  // Use lobby name as group
            spawnIndex = player.SpawnIndex,
            lobbyId = lobby.Id
        };
    }

    // ============================================
    // HELPERS
    // ============================================

    private async Task<T?> ReadBodyAsync<T>(HttpListenerRequest request) where T : class
    {
        try
        {
            using var reader = new StreamReader(request.InputStream);
            var json = await reader.ReadToEndAsync();
            return JsonSerializer.Deserialize<T>(json, new JsonSerializerOptions
            {
                PropertyNameCaseInsensitive = true
            });
        }
        catch
        {
            return null;
        }
    }

    private async Task SendJsonAsync(HttpListenerResponse response, object data, int statusCode = 200)
    {
        response.StatusCode = statusCode;
        response.ContentType = "application/json";

        var json = JsonSerializer.Serialize(data, JsonOptions);
        var bytes = Encoding.UTF8.GetBytes(json);

        response.ContentLength64 = bytes.Length;
        await response.OutputStream.WriteAsync(bytes);
        response.Close();
    }
}

// ============================================
// REQUEST MODELS
// ============================================

public class ServerReadyRequest
{
    public int Port { get; set; }
}

public class ServerHeartbeatRequest
{
    public string ServerId { get; set; } = "";
    public int PlayerCount { get; set; }
}

public class MatchFindRequest
{
    public string PlayerId { get; set; } = "";
    public string? GameMode { get; set; }
}

public class PlayerEventRequest
{
    public string MatchId { get; set; } = "";
    public string PlayerId { get; set; } = "";
}

public class WaveCompleteRequest
{
    public string MatchId { get; set; } = "";
    public int WaveNumber { get; set; }
    public int ZombiesKilled { get; set; }
}

public class MatchEndRequest
{
    public string MatchId { get; set; } = "";
    public string? Reason { get; set; }
    public int FinalWave { get; set; }
}

// Friend system request models
public class FriendRequest
{
    public string PlayerId { get; set; } = "";
    public string FriendId { get; set; } = "";
}

public class FriendStatusRequest
{
    public string PlayerId { get; set; } = "";
    public List<string> FriendIds { get; set; } = new();
}

public class PlayerIdRequest
{
    public string PlayerId { get; set; } = "";
}

public class FriendInviteRequest
{
    public string FromPlayerId { get; set; } = "";
    public string ToPlayerId { get; set; } = "";
    public Dictionary<string, object>? ServerInfo { get; set; }
}

// Lobby system request models
public class LobbyCreateRequest
{
    public string PlayerId { get; set; } = "";
    public string? PlayerName { get; set; }
    public string? LobbyName { get; set; }
    public int MaxPlayers { get; set; } = 4;
    public string? GameMode { get; set; }
}

public class LobbyJoinRequest
{
    public string PlayerId { get; set; } = "";
    public string? PlayerName { get; set; }
    public string LobbyId { get; set; } = "";
}

public class LobbyReadyRequest
{
    public string PlayerId { get; set; } = "";
    public bool Ready { get; set; }
}

public class LobbyStartRequest
{
    public string PlayerId { get; set; } = "";
    public string LobbyId { get; set; } = "";
}

public class LobbyStatusRequest
{
    public string? PlayerId { get; set; }
    public string? LobbyId { get; set; }
}

public class LobbyClaimSpawnRequest
{
    public string LobbyId { get; set; } = "";
    public string PlayerId { get; set; } = "";
}
