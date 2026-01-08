using GameManager.Data;
using GameManager.Events;

namespace GameManager.Services;

/// <summary>
/// StoreService - Handles in-game economy, inventory, and progression
/// </summary>
public class StoreService
{
    private readonly DatabaseService _database;
    private readonly CacheService _cache;
    private readonly EventBroker _eventBroker;

    // Store items catalog
    private readonly Dictionary<string, StoreItem> _catalog = new();

    public StoreService(DatabaseService database, CacheService cache, EventBroker eventBroker)
    {
        _database = database;
        _cache = cache;
        _eventBroker = eventBroker;

        InitializeCatalog();
    }

    private void InitializeCatalog()
    {
        // Weapons
        AddItem(new StoreItem
        {
            Id = "weapon_shotgun",
            Name = "Shotgun",
            Category = "weapons",
            Description = "Powerful close-range weapon",
            Price = 500,
            Currency = "credits"
        });

        AddItem(new StoreItem
        {
            Id = "weapon_rifle",
            Name = "Assault Rifle",
            Category = "weapons",
            Description = "Balanced automatic weapon",
            Price = 750,
            Currency = "credits"
        });

        AddItem(new StoreItem
        {
            Id = "weapon_sniper",
            Name = "Sniper Rifle",
            Category = "weapons",
            Description = "High-damage long-range weapon",
            Price = 1000,
            Currency = "credits"
        });

        // Tools
        AddItem(new StoreItem
        {
            Id = "tool_hammer_gold",
            Name = "Golden Hammer",
            Category = "tools",
            Description = "Faster nail placement",
            Price = 300,
            Currency = "credits"
        });

        AddItem(new StoreItem
        {
            Id = "tool_nails_reinforced",
            Name = "Reinforced Nails",
            Category = "tools",
            Description = "Nails with 50% more HP",
            Price = 200,
            Currency = "credits"
        });

        // Consumables
        AddItem(new StoreItem
        {
            Id = "consumable_medkit",
            Name = "Medical Kit",
            Category = "consumables",
            Description = "Restore 50 health",
            Price = 100,
            Currency = "credits",
            IsConsumable = true
        });

        AddItem(new StoreItem
        {
            Id = "consumable_ammo_box",
            Name = "Ammo Box",
            Category = "consumables",
            Description = "Refill all ammo",
            Price = 75,
            Currency = "credits",
            IsConsumable = true
        });

        Console.WriteLine($"[StoreService] Catalog initialized with {_catalog.Count} items");
    }

    private void AddItem(StoreItem item)
    {
        _catalog[item.Id] = item;
    }

    /// <summary>
    /// Get all store items
    /// </summary>
    public IEnumerable<StoreItem> GetCatalog(string? category = null)
    {
        if (string.IsNullOrEmpty(category))
            return _catalog.Values;

        return _catalog.Values.Where(i => i.Category == category);
    }

    /// <summary>
    /// Get a specific item
    /// </summary>
    public StoreItem? GetItem(string itemId)
    {
        _catalog.TryGetValue(itemId, out var item);
        return item;
    }

    /// <summary>
    /// Purchase an item for a player
    /// </summary>
    public async Task<PurchaseResult> PurchaseItemAsync(string playerId, string itemId, int quantity = 1)
    {
        var item = GetItem(itemId);
        if (item == null)
        {
            return new PurchaseResult { Success = false, Error = "Item not found" };
        }

        var player = await _database.GetPlayerAsync(playerId);
        if (player == null)
        {
            return new PurchaseResult { Success = false, Error = "Player not found" };
        }

        var totalCost = item.Price * quantity;

        // Check currency
        if (player.Currency < totalCost)
        {
            return new PurchaseResult
            {
                Success = false,
                Error = "Insufficient funds",
                CurrentBalance = player.Currency,
                Required = totalCost
            };
        }

        // Check if already owned (for non-consumables)
        if (!item.IsConsumable && player.UnlockedItems.Contains(itemId))
        {
            return new PurchaseResult { Success = false, Error = "Item already owned" };
        }

        // Process purchase
        player.Currency -= totalCost;

        if (item.IsConsumable)
        {
            // Add to quantities
            if (!player.ItemQuantities.ContainsKey(itemId))
                player.ItemQuantities[itemId] = 0;
            player.ItemQuantities[itemId] += quantity;
        }
        else
        {
            // Unlock permanent item
            player.UnlockedItems.Add(itemId);
        }

        await _database.UpdatePlayerAsync(player);

        Console.WriteLine($"[StoreService] Player {playerId} purchased {quantity}x {item.Name} for {totalCost} credits");

        return new PurchaseResult
        {
            Success = true,
            ItemId = itemId,
            Quantity = quantity,
            Cost = totalCost,
            CurrentBalance = player.Currency
        };
    }

    /// <summary>
    /// Grant currency to a player (from gameplay rewards)
    /// </summary>
    public async Task<int> GrantCurrencyAsync(string playerId, int amount, string reason)
    {
        var player = await _database.GetPlayerAsync(playerId);
        if (player == null)
            return 0;

        player.Currency += amount;
        await _database.UpdatePlayerAsync(player);

        Console.WriteLine($"[StoreService] Granted {amount} credits to {playerId}: {reason}");

        return player.Currency;
    }

    /// <summary>
    /// Get player's inventory
    /// </summary>
    public async Task<PlayerInventory> GetInventoryAsync(string playerId)
    {
        var player = await _database.GetPlayerAsync(playerId);
        if (player == null)
            return new PlayerInventory();

        return new PlayerInventory
        {
            PlayerId = playerId,
            Currency = player.Currency,
            UnlockedItems = player.UnlockedItems.Select(id =>
            {
                var item = GetItem(id);
                return new InventoryItem
                {
                    ItemId = id,
                    Name = item?.Name ?? id,
                    Category = item?.Category ?? "unknown",
                    Quantity = 1
                };
            }).ToList(),
            Consumables = player.ItemQuantities.Select(kvp =>
            {
                var item = GetItem(kvp.Key);
                return new InventoryItem
                {
                    ItemId = kvp.Key,
                    Name = item?.Name ?? kvp.Key,
                    Category = item?.Category ?? "consumables",
                    Quantity = kvp.Value
                };
            }).ToList()
        };
    }

    /// <summary>
    /// Use a consumable item
    /// </summary>
    public async Task<bool> UseConsumableAsync(string playerId, string itemId)
    {
        var player = await _database.GetPlayerAsync(playerId);
        if (player == null)
            return false;

        if (!player.ItemQuantities.TryGetValue(itemId, out var quantity) || quantity <= 0)
            return false;

        player.ItemQuantities[itemId] = quantity - 1;
        await _database.UpdatePlayerAsync(player);

        Console.WriteLine($"[StoreService] Player {playerId} used consumable {itemId}");

        return true;
    }

    /// <summary>
    /// Calculate rewards for a completed game
    /// </summary>
    public GameRewards CalculateRewards(int waveReached, int zombieKills, bool survived)
    {
        var rewards = new GameRewards();

        // Base rewards
        rewards.Credits += waveReached * 10;        // 10 credits per wave
        rewards.Credits += zombieKills * 2;         // 2 credits per kill

        if (survived)
            rewards.Credits += 50;                  // Survival bonus

        // Wave milestones
        if (waveReached >= 5)
            rewards.Credits += 25;
        if (waveReached >= 10)
            rewards.Credits += 50;
        if (waveReached >= 15)
            rewards.Credits += 100;
        if (waveReached >= 20)
            rewards.Credits += 200;

        // XP (for future leveling system)
        rewards.Experience = waveReached * 50 + zombieKills * 10;

        return rewards;
    }
}

public class StoreItem
{
    public string Id { get; set; } = "";
    public string Name { get; set; } = "";
    public string Category { get; set; } = "";
    public string Description { get; set; } = "";
    public int Price { get; set; }
    public string Currency { get; set; } = "credits";
    public bool IsConsumable { get; set; }
    public Dictionary<string, object> Metadata { get; set; } = new();
}

public class PurchaseResult
{
    public bool Success { get; set; }
    public string? Error { get; set; }
    public string? ItemId { get; set; }
    public int Quantity { get; set; }
    public int Cost { get; set; }
    public int CurrentBalance { get; set; }
    public int Required { get; set; }
}

public class PlayerInventory
{
    public string PlayerId { get; set; } = "";
    public int Currency { get; set; }
    public List<InventoryItem> UnlockedItems { get; set; } = new();
    public List<InventoryItem> Consumables { get; set; } = new();
}

public class InventoryItem
{
    public string ItemId { get; set; } = "";
    public string Name { get; set; } = "";
    public string Category { get; set; } = "";
    public int Quantity { get; set; }
}

public class GameRewards
{
    public int Credits { get; set; }
    public int Experience { get; set; }
    public List<string> UnlockedItems { get; set; } = new();
}
