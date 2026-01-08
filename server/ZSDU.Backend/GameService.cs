namespace ZSDU.Backend;

/// <summary>
/// GameService - In-process game logic
/// Handles game rules, scoring, and session state
/// NO external dependencies - just game logic
/// </summary>
public class GameService
{
    private readonly SessionRegistry _registry;

    public GameService(SessionRegistry registry)
    {
        _registry = registry;
    }

    /// <summary>
    /// Calculate rewards for a completed game
    /// </summary>
    public GameRewards CalculateRewards(int waveReached, int zombieKills, bool survived)
    {
        var rewards = new GameRewards();

        // Base rewards
        rewards.Points += waveReached * 100;      // 100 points per wave
        rewards.Points += zombieKills * 10;       // 10 points per kill

        if (survived)
            rewards.Points += 500;                // Survival bonus

        // Wave milestones
        if (waveReached >= 5) rewards.Points += 250;
        if (waveReached >= 10) rewards.Points += 500;
        if (waveReached >= 15) rewards.Points += 1000;
        if (waveReached >= 20) rewards.Points += 2000;

        return rewards;
    }

    /// <summary>
    /// Get leaderboard position (stub - in-memory only for now)
    /// </summary>
    public int GetLeaderboardPosition(string playerId)
    {
        // Future: Track player scores in-memory or simple file
        return 0;
    }

    /// <summary>
    /// Validate game action (anti-cheat stub)
    /// </summary>
    public bool ValidateAction(string playerId, string action, object data)
    {
        // Future: Add basic validation
        // - Check player is in valid match
        // - Check action timing
        // - Check position sanity
        return true;
    }
}

public class GameRewards
{
    public int Points { get; set; }
}
