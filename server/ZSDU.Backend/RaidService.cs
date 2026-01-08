using System.Collections.Concurrent;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using ZSDU.Backend.Models;

namespace ZSDU.Backend;

/// <summary>
/// RaidService - Manages raid sessions and prevents item duplication
///
/// Flow:
/// 1. Client calls /raid/prepare → items locked, raid_id created
/// 2. Match server calls /server/raid/start → validates raid exists
/// 3. Match server gets loadout via /server/raid/loadout
/// 4. Match ends → server calls /server/raid/commit with outcomes
/// 5. Backend mints loot, removes lost items, unlocks remaining
///
/// Anti-dupe rules:
/// - Locked items cannot be moved/sold/listed
/// - Raid expires after timeout (stale raids auto-cleanup)
/// - Commit requires valid signature from trusted server
/// - Each raid can only be committed once
/// </summary>
public class RaidService
{
    private readonly InventoryService _inventory;
    private readonly ConcurrentDictionary<string, RaidSession> _raids = new();
    private readonly string _serverSecret;

    private static readonly TimeSpan RAID_TIMEOUT = TimeSpan.FromHours(2);
    private static readonly TimeSpan PREPARE_TIMEOUT = TimeSpan.FromMinutes(10);

    public RaidService(InventoryService inventory, string serverSecret)
    {
        _inventory = inventory;
        _serverSecret = serverSecret;
    }

    // ============================================
    // CLIENT ENDPOINTS
    // ============================================

    /// <summary>
    /// Prepare for raid - lock loadout items
    /// Called by client before joining lobby/match
    /// </summary>
    public object PrepareRaid(string characterId, string opId, string lobbyId, LoadoutSlots loadout)
    {
        var character = _inventory.GetCharacter(characterId);
        if (character == null)
            return new { error = "Character not found" };

        // Check if already in a raid
        var existingRaid = _raids.Values.FirstOrDefault(r =>
            r.CharacterId == characterId &&
            r.Status != RaidStatus.Committed &&
            r.Status != RaidStatus.Abandoned);

        if (existingRaid != null)
        {
            // Check if expired
            if (existingRaid.ExpiresAt.HasValue && existingRaid.ExpiresAt < DateTime.UtcNow)
            {
                // Cleanup stale raid
                _CleanupRaid(existingRaid.RaidId, "expired");
            }
            else
            {
                return new { error = "Already in a raid", existing_raid_id = existingRaid.RaidId };
            }
        }

        // Collect all IIDs from loadout
        var iidsToLock = new List<string>();
        if (!string.IsNullOrEmpty(loadout.Primary)) iidsToLock.Add(loadout.Primary);
        if (!string.IsNullOrEmpty(loadout.Secondary)) iidsToLock.Add(loadout.Secondary);
        if (!string.IsNullOrEmpty(loadout.Melee)) iidsToLock.Add(loadout.Melee);
        if (!string.IsNullOrEmpty(loadout.Armor)) iidsToLock.Add(loadout.Armor);
        if (!string.IsNullOrEmpty(loadout.Rig)) iidsToLock.Add(loadout.Rig);
        if (!string.IsNullOrEmpty(loadout.Bag)) iidsToLock.Add(loadout.Bag);
        iidsToLock.AddRange(loadout.Pockets.Where(p => !string.IsNullOrEmpty(p)));

        // Remove duplicates and empty
        iidsToLock = iidsToLock.Distinct().Where(i => !string.IsNullOrEmpty(i)).ToList();

        // Create raid session
        var raidId = $"raid_{Guid.NewGuid():N}";

        // Try to lock items
        if (!_inventory.LockItemsForRaid(characterId, iidsToLock, raidId))
        {
            return new { error = "Some items are already locked" };
        }

        var raid = new RaidSession
        {
            RaidId = raidId,
            CharacterId = characterId,
            LobbyId = lobbyId,
            Loadout = loadout,
            LockedIids = iidsToLock,
            Status = RaidStatus.Preparing,
            CreatedAt = DateTime.UtcNow,
            ExpiresAt = DateTime.UtcNow.Add(PREPARE_TIMEOUT)
        };

        _raids[raidId] = raid;

        Console.WriteLine($"[Raid] Prepared: {raidId} for {characterId} with {iidsToLock.Count} items");

        return new
        {
            raid_id = raidId,
            locked_iids = iidsToLock,
            expires_at = raid.ExpiresAt
        };
    }

    /// <summary>
    /// Cancel a raid (before it starts)
    /// </summary>
    public object CancelRaid(string characterId, string raidId)
    {
        if (!_raids.TryGetValue(raidId, out var raid))
            return new { error = "Raid not found" };

        if (raid.CharacterId != characterId)
            return new { error = "Not your raid" };

        if (raid.Status != RaidStatus.Preparing)
            return new { error = "Raid already started" };

        _CleanupRaid(raidId, "cancelled");

        return new { ok = true };
    }

    // ============================================
    // SERVER-TO-SERVER ENDPOINTS
    // ============================================

    /// <summary>
    /// Start raid (called by match server)
    /// </summary>
    public object StartRaid(string serverSecret, string raidId, string matchId, List<string> playerIds)
    {
        if (serverSecret != _serverSecret)
            return new { error = "Invalid server secret" };

        if (!_raids.TryGetValue(raidId, out var raid))
            return new { error = "Raid not found" };

        if (raid.Status != RaidStatus.Preparing)
            return new { error = "Raid not in preparing state" };

        raid.MatchId = matchId;
        raid.Status = RaidStatus.Active;
        raid.ExpiresAt = DateTime.UtcNow.Add(RAID_TIMEOUT);

        Console.WriteLine($"[Raid] Started: {raidId} match={matchId}");

        return new { ok = true };
    }

    /// <summary>
    /// Get loadout for a player in a raid
    /// </summary>
    public object GetRaidLoadout(string serverSecret, string raidId, string characterId)
    {
        if (serverSecret != _serverSecret)
            return new { error = "Invalid server secret" };

        if (!_raids.TryGetValue(raidId, out var raid))
            return new { error = "Raid not found" };

        if (raid.CharacterId != characterId)
            return new { error = "Character not in this raid" };

        // Get actual item instances
        var items = _inventory.GetItems(characterId, raid.LockedIids);

        return new
        {
            character_id = characterId,
            loadout = raid.Loadout,
            loadout_items = items.Select(i => new
            {
                i.Iid,
                i.DefId,
                i.Stack,
                i.Durability,
                i.Mods
            })
        };
    }

    /// <summary>
    /// Commit raid results (THE anti-dupe cornerstone)
    /// </summary>
    public object CommitRaid(string serverSecret, string raidId, string matchId, List<RaidOutcome> outcomes, string signature)
    {
        if (serverSecret != _serverSecret)
            return new { error = "Invalid server secret" };

        if (!_raids.TryGetValue(raidId, out var raid))
            return new { error = "Raid not found" };

        if (raid.Status == RaidStatus.Committed)
            return new { error = "Raid already committed" };

        if (raid.MatchId != matchId)
            return new { error = "Match ID mismatch" };

        // Verify signature
        var expectedSignature = _ComputeSignature(raidId, matchId, outcomes);
        if (signature != expectedSignature)
        {
            Console.WriteLine($"[Raid] Invalid signature for {raidId}");
            return new { error = "Invalid signature" };
        }

        var results = new List<object>();

        foreach (var outcome in outcomes)
        {
            if (outcome.CharacterId != raid.CharacterId)
                continue;

            var character = _inventory.GetCharacter(outcome.CharacterId);
            if (character == null) continue;

            int prevVersion = character.StashVersion;

            // Process based on status
            if (outcome.Status == "extracted")
            {
                // Mint provisional loot
                var mintedItems = _inventory.MintLoot(outcome.CharacterId, outcome.ProvisionalLoot);

                // Remove lost items (used consumables, etc.)
                _inventory.RemoveItems(outcome.CharacterId, outcome.LostIids);

                // Update durability
                _inventory.UpdateDurability(outcome.CharacterId, outcome.DurabilityUpdates);

                // Add rewards
                _inventory.AddGold(outcome.CharacterId, outcome.GoldGained);

                // Add XP
                character.Xp += outcome.XpGained;

                results.Add(new
                {
                    character_id = outcome.CharacterId,
                    status = "extracted",
                    stash_delta = new
                    {
                        added = mintedItems,
                        removed = outcome.LostIids,
                        updated = outcome.DurabilityUpdates.Select(u => u.Iid)
                    },
                    wallet = character.Wallet,
                    xp = character.Xp,
                    version = character.StashVersion
                });

                Console.WriteLine($"[Raid] {outcome.CharacterId} extracted with {mintedItems.Count} loot items");
            }
            else if (outcome.Status == "died")
            {
                // Lost everything brought in (based on game rules)
                // For now: lose all loadout items except insured
                var lostIids = raid.LockedIids
                    .Where(iid =>
                    {
                        var item = character.Items.FirstOrDefault(i => i.Iid == iid);
                        return item != null && !item.Flags.Insured;
                    })
                    .ToList();

                _inventory.RemoveItems(outcome.CharacterId, lostIids);

                results.Add(new
                {
                    character_id = outcome.CharacterId,
                    status = "died",
                    stash_delta = new
                    {
                        removed = lostIids
                    },
                    wallet = character.Wallet,
                    version = character.StashVersion
                });

                Console.WriteLine($"[Raid] {outcome.CharacterId} died, lost {lostIids.Count} items");
            }

            // Unlock remaining items
            _inventory.UnlockRaidItems(outcome.CharacterId, raidId);
        }

        // Mark raid as committed
        raid.Status = RaidStatus.Committed;
        raid.CommittedAt = DateTime.UtcNow;

        Console.WriteLine($"[Raid] Committed: {raidId}");

        return new
        {
            ok = true,
            results
        };
    }

    // ============================================
    // HELPERS
    // ============================================

    private void _CleanupRaid(string raidId, string reason)
    {
        if (!_raids.TryRemove(raidId, out var raid))
            return;

        // Unlock items
        _inventory.UnlockRaidItems(raid.CharacterId, raidId);

        Console.WriteLine($"[Raid] Cleaned up {raidId}: {reason}");
    }

    private string _ComputeSignature(string raidId, string matchId, List<RaidOutcome> outcomes)
    {
        // Create canonical JSON payload
        var payload = new
        {
            raid_id = raidId,
            match_id = matchId,
            outcomes = outcomes.Select(o => new
            {
                character_id = o.CharacterId,
                status = o.Status,
                loot_count = o.ProvisionalLoot.Count,
                lost_count = o.LostIids.Count
            })
        };

        var json = JsonSerializer.Serialize(payload, new JsonSerializerOptions { WriteIndented = false });
        var data = Encoding.UTF8.GetBytes(json + _serverSecret);

        using var sha256 = SHA256.Create();
        var hash = sha256.ComputeHash(data);
        return Convert.ToHexString(hash).ToLower();
    }

    /// <summary>
    /// Cleanup expired raids (call periodically)
    /// </summary>
    public void CleanupExpiredRaids()
    {
        var now = DateTime.UtcNow;
        var expiredIds = _raids
            .Where(kv => kv.Value.ExpiresAt.HasValue && kv.Value.ExpiresAt < now && kv.Value.Status != RaidStatus.Committed)
            .Select(kv => kv.Key)
            .ToList();

        foreach (var raidId in expiredIds)
        {
            _CleanupRaid(raidId, "expired");
        }
    }

    /// <summary>
    /// Get raid by ID
    /// </summary>
    public RaidSession? GetRaid(string raidId)
    {
        _raids.TryGetValue(raidId, out var raid);
        return raid;
    }

    /// <summary>
    /// Get active raid for character
    /// </summary>
    public RaidSession? GetActiveRaidForCharacter(string characterId)
    {
        return _raids.Values.FirstOrDefault(r =>
            r.CharacterId == characterId &&
            (r.Status == RaidStatus.Preparing || r.Status == RaidStatus.Active));
    }
}
