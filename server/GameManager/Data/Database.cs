using System.Collections.Concurrent;
using System.Text.Json;

namespace GameManager.Data;

/// <summary>
/// In-memory database implementation for development
/// In production, replace with actual MySQL/PostgreSQL client
/// </summary>
public class DatabaseService
{
    private readonly ConcurrentDictionary<string, Dictionary<string, PlayerData>> _players = new();
    private readonly ConcurrentDictionary<string, Dictionary<string, GameSession>> _gameSessions = new();
    private readonly ConcurrentDictionary<string, Dictionary<string, object>> _leaderboards = new();
    private readonly string _dataPath;

    public DatabaseService(string dataPath = "./data")
    {
        _dataPath = dataPath;
        Directory.CreateDirectory(_dataPath);
        LoadData();
    }

    // ============================================
    // Player Data
    // ============================================

    /// <summary>
    /// Get or create a player
    /// </summary>
    public async Task<PlayerData> GetOrCreatePlayerAsync(string playerId, string username)
    {
        var collection = _players.GetOrAdd("players", _ => new Dictionary<string, PlayerData>());

        if (!collection.TryGetValue(playerId, out var player))
        {
            player = new PlayerData
            {
                Id = playerId,
                Username = username,
                CreatedAt = DateTime.UtcNow
            };
            collection[playerId] = player;
            await SaveDataAsync();
        }

        player.LastLogin = DateTime.UtcNow;
        return player;
    }

    /// <summary>
    /// Get player by ID
    /// </summary>
    public Task<PlayerData?> GetPlayerAsync(string playerId)
    {
        var collection = _players.GetOrAdd("players", _ => new Dictionary<string, PlayerData>());
        collection.TryGetValue(playerId, out var player);
        return Task.FromResult(player);
    }

    /// <summary>
    /// Update player data
    /// </summary>
    public async Task UpdatePlayerAsync(PlayerData player)
    {
        var collection = _players.GetOrAdd("players", _ => new Dictionary<string, PlayerData>());
        collection[player.Id] = player;
        await SaveDataAsync();
    }

    /// <summary>
    /// Update player stats after a game
    /// </summary>
    public async Task UpdatePlayerStatsAsync(string playerId, int zombieKills, int waveReached, bool won)
    {
        var player = await GetPlayerAsync(playerId);
        if (player == null) return;

        player.TotalGamesPlayed++;
        player.TotalZombieKills += zombieKills;
        player.HighestWave = Math.Max(player.HighestWave, waveReached);

        if (won)
            player.TotalWins++;

        // Update skill rating (simple Elo-like)
        var ratingChange = (waveReached * 5) + (zombieKills / 10) + (won ? 50 : -10);
        player.SkillRating = Math.Max(0, player.SkillRating + ratingChange);

        await UpdatePlayerAsync(player);
    }

    // ============================================
    // Game Session History
    // ============================================

    /// <summary>
    /// Save a completed game session
    /// </summary>
    public async Task SaveGameSessionAsync(GameSession session)
    {
        var collection = _gameSessions.GetOrAdd("sessions", _ => new Dictionary<string, GameSession>());
        collection[session.Id] = session;
        await SaveDataAsync();
    }

    /// <summary>
    /// Get recent game sessions
    /// </summary>
    public Task<List<GameSession>> GetRecentSessionsAsync(int limit = 100)
    {
        var collection = _gameSessions.GetOrAdd("sessions", _ => new Dictionary<string, GameSession>());
        var sessions = collection.Values
            .OrderByDescending(s => s.StartedAt)
            .Take(limit)
            .ToList();
        return Task.FromResult(sessions);
    }

    /// <summary>
    /// Get game sessions for a player
    /// </summary>
    public Task<List<GameSession>> GetPlayerSessionsAsync(string playerId, int limit = 50)
    {
        var collection = _gameSessions.GetOrAdd("sessions", _ => new Dictionary<string, GameSession>());
        var sessions = collection.Values
            .Where(s => s.PlayerIds.Contains(playerId))
            .OrderByDescending(s => s.StartedAt)
            .Take(limit)
            .ToList();
        return Task.FromResult(sessions);
    }

    // ============================================
    // Leaderboards
    // ============================================

    /// <summary>
    /// Get top players by a stat
    /// </summary>
    public Task<List<LeaderboardEntry>> GetLeaderboardAsync(string stat, int limit = 100)
    {
        var collection = _players.GetOrAdd("players", _ => new Dictionary<string, PlayerData>());

        var entries = collection.Values
            .Select(p => new LeaderboardEntry
            {
                PlayerId = p.Id,
                Username = p.Username,
                Score = stat switch
                {
                    "kills" => p.TotalZombieKills,
                    "wins" => p.TotalWins,
                    "wave" => p.HighestWave,
                    "rating" => p.SkillRating,
                    "games" => p.TotalGamesPlayed,
                    _ => 0
                }
            })
            .Where(e => e.Score > 0)
            .OrderByDescending(e => e.Score)
            .Take(limit)
            .ToList();

        // Add ranks
        for (int i = 0; i < entries.Count; i++)
        {
            entries[i].Rank = i + 1;
        }

        return Task.FromResult(entries);
    }

    /// <summary>
    /// Get player's rank for a stat
    /// </summary>
    public async Task<int> GetPlayerRankAsync(string playerId, string stat)
    {
        var leaderboard = await GetLeaderboardAsync(stat, int.MaxValue);
        var entry = leaderboard.FirstOrDefault(e => e.PlayerId == playerId);
        return entry?.Rank ?? 0;
    }

    // ============================================
    // Persistence
    // ============================================

    private void LoadData()
    {
        try
        {
            var playersPath = Path.Combine(_dataPath, "players.json");
            if (File.Exists(playersPath))
            {
                var json = File.ReadAllText(playersPath);
                var players = JsonSerializer.Deserialize<Dictionary<string, PlayerData>>(json);
                if (players != null)
                {
                    _players["players"] = players;
                }
            }

            var sessionsPath = Path.Combine(_dataPath, "sessions.json");
            if (File.Exists(sessionsPath))
            {
                var json = File.ReadAllText(sessionsPath);
                var sessions = JsonSerializer.Deserialize<Dictionary<string, GameSession>>(json);
                if (sessions != null)
                {
                    _gameSessions["sessions"] = sessions;
                }
            }

            Console.WriteLine($"[Database] Loaded {_players.GetOrAdd("players", _ => new()).Count} players");
        }
        catch (Exception ex)
        {
            Console.WriteLine($"[Database] Error loading data: {ex.Message}");
        }
    }

    private async Task SaveDataAsync()
    {
        try
        {
            var playersPath = Path.Combine(_dataPath, "players.json");
            var playersJson = JsonSerializer.Serialize(
                _players.GetOrAdd("players", _ => new Dictionary<string, PlayerData>()),
                new JsonSerializerOptions { WriteIndented = true });
            await File.WriteAllTextAsync(playersPath, playersJson);

            var sessionsPath = Path.Combine(_dataPath, "sessions.json");
            var sessionsJson = JsonSerializer.Serialize(
                _gameSessions.GetOrAdd("sessions", _ => new Dictionary<string, GameSession>()),
                new JsonSerializerOptions { WriteIndented = true });
            await File.WriteAllTextAsync(sessionsPath, sessionsJson);
        }
        catch (Exception ex)
        {
            Console.WriteLine($"[Database] Error saving data: {ex.Message}");
        }
    }
}

/// <summary>
/// Leaderboard entry
/// </summary>
public class LeaderboardEntry
{
    public int Rank { get; set; }
    public string PlayerId { get; set; } = "";
    public string Username { get; set; } = "";
    public int Score { get; set; }
}
