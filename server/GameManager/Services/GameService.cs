using GameManager.Data;
using GameManager.Events;

namespace GameManager.Services;

/// <summary>
/// GameService - Handles game-specific logic and state management
/// Coordinates between game servers and the manager
/// </summary>
public class GameService
{
    private readonly SessionManager _sessionManager;
    private readonly EventBroker _eventBroker;
    private readonly DatabaseService _database;
    private readonly Configuration _config;

    public GameService(
        SessionManager sessionManager,
        EventBroker eventBroker,
        DatabaseService database,
        Configuration config)
    {
        _sessionManager = sessionManager;
        _eventBroker = eventBroker;
        _database = database;
        _config = config;

        // Subscribe to game events
        _eventBroker.Subscribe<GameEndedEvent>(OnGameEnded);
        _eventBroker.Subscribe<WaveCompletedEvent>(OnWaveCompleted);
    }

    /// <summary>
    /// Start a new game on a server
    /// </summary>
    public async Task<GameSession?> StartGameAsync(string serverId, List<string> playerIds, string gameMode = "survival", string mapName = "default")
    {
        var server = _sessionManager.GetServer(serverId);
        if (server == null || server.Status != ServerStatus.Ready)
            return null;

        // Create game session
        var session = await _sessionManager.CreateGameSessionAsync(serverId, gameMode, mapName, playerIds);

        // Update server status
        server.Status = ServerStatus.InGame;
        server.MapName = mapName;
        server.GameMode = gameMode;

        Console.WriteLine($"[GameService] Game started on {server.Name}: {playerIds.Count} players, mode: {gameMode}");

        return session;
    }

    /// <summary>
    /// End a game and record results
    /// </summary>
    public async Task EndGameAsync(string sessionId, int finalWave, Dictionary<string, int> scores)
    {
        await _sessionManager.EndGameSessionAsync(sessionId, finalWave, scores);

        // Update player stats
        foreach (var (playerId, score) in scores)
        {
            var zombieKills = score; // Assuming score = kills for now
            var won = finalWave >= 10; // Example: wave 10+ is a "win"
            await _database.UpdatePlayerStatsAsync(playerId, zombieKills, finalWave, won);
        }

        Console.WriteLine($"[GameService] Game ended: session {sessionId}, wave {finalWave}");
    }

    /// <summary>
    /// Process wave completion from a game server
    /// </summary>
    public async Task ProcessWaveCompletionAsync(string serverId, int waveNumber, int zombiesKilled)
    {
        var server = _sessionManager.GetServer(serverId);
        if (server == null) return;

        server.Metadata["current_wave"] = waveNumber.ToString();
        server.Metadata["total_kills"] = (
            int.Parse(server.Metadata.GetValueOrDefault("total_kills", "0")) + zombiesKilled
        ).ToString();

        // Could emit event for spectators/UI
        Console.WriteLine($"[GameService] Wave {waveNumber} completed on {server.Name}: {zombiesKilled} zombies killed");

        await Task.CompletedTask;
    }

    /// <summary>
    /// Get active games
    /// </summary>
    public IEnumerable<ActiveGameInfo> GetActiveGames()
    {
        return _sessionManager.GetAllServers()
            .Where(s => s.Status == ServerStatus.InGame)
            .Select(s => new ActiveGameInfo
            {
                ServerId = s.Id,
                ServerName = s.Name,
                GameMode = s.GameMode,
                MapName = s.MapName,
                PlayerCount = s.CurrentPlayers,
                CurrentWave = int.Parse(s.Metadata.GetValueOrDefault("current_wave", "0")),
                TotalKills = int.Parse(s.Metadata.GetValueOrDefault("total_kills", "0"))
            });
    }

    /// <summary>
    /// Get game statistics
    /// </summary>
    public async Task<GameStats> GetStatsAsync()
    {
        var servers = _sessionManager.GetAllServers().ToList();
        var recentSessions = await _database.GetRecentSessionsAsync(100);

        return new GameStats
        {
            TotalServers = servers.Count,
            ActiveGames = servers.Count(s => s.Status == ServerStatus.InGame),
            TotalPlayersOnline = servers.Sum(s => s.CurrentPlayers),
            GamesPlayedToday = recentSessions.Count(s => s.StartedAt.Date == DateTime.UtcNow.Date),
            AverageWaveReached = recentSessions.Count > 0
                ? recentSessions.Average(s => s.CurrentWave)
                : 0
        };
    }

    // Event handlers
    private async Task OnGameEnded(GameEndedEvent evt)
    {
        // Save session to database
        // Could trigger achievements, rewards, etc.
        await Task.CompletedTask;
    }

    private async Task OnWaveCompleted(WaveCompletedEvent evt)
    {
        // Update leaderboards, trigger events
        await Task.CompletedTask;
    }
}

public class ActiveGameInfo
{
    public string ServerId { get; set; } = "";
    public string ServerName { get; set; } = "";
    public string GameMode { get; set; } = "";
    public string MapName { get; set; } = "";
    public int PlayerCount { get; set; }
    public int CurrentWave { get; set; }
    public int TotalKills { get; set; }
}

public class GameStats
{
    public int TotalServers { get; set; }
    public int ActiveGames { get; set; }
    public int TotalPlayersOnline { get; set; }
    public int GamesPlayedToday { get; set; }
    public double AverageWaveReached { get; set; }
}
