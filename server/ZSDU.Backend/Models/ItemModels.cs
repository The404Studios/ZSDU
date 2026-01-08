using System.Text.Json.Serialization;

namespace ZSDU.Backend.Models;

/// <summary>
/// Static item definition (template)
/// </summary>
public class ItemDef
{
    public string DefId { get; set; } = "";
    public string Name { get; set; } = "";
    public string Description { get; set; } = "";
    public int Width { get; set; } = 1;
    public int Height { get; set; } = 1;
    public int MaxStack { get; set; } = 1;
    public int BaseValue { get; set; } = 100;
    public string Category { get; set; } = "misc"; // weapon, armor, med, ammo, misc, quest
    public List<string> Tags { get; set; } = new();
    public Dictionary<string, object> Properties { get; set; } = new();
}

/// <summary>
/// Unique item instance owned by a player
/// </summary>
public class ItemInstance
{
    public string Iid { get; set; } = ""; // Unique instance ID
    public string DefId { get; set; } = "";
    public int Stack { get; set; } = 1;
    public float Durability { get; set; } = 1.0f;
    public List<ItemMod> Mods { get; set; } = new();
    public ItemFlags Flags { get; set; } = new();
    public Dictionary<string, object> Meta { get; set; } = new();
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}

public class ItemMod
{
    public string Slot { get; set; } = "";
    public string Iid { get; set; } = ""; // Attached item instance
}

public class ItemFlags
{
    public bool InRaid { get; set; } = false;
    public bool InEscrow { get; set; } = false;
    public bool Insured { get; set; } = false;
    public bool QuestBound { get; set; } = false;
    public bool NonTradeable { get; set; } = false;
    public string? RaidId { get; set; } = null;
    public string? EscrowListingId { get; set; } = null;
}

/// <summary>
/// Stash placement (item position in grid)
/// </summary>
public class StashPlacement
{
    public string Iid { get; set; } = "";
    public int X { get; set; }
    public int Y { get; set; }
    public int Rotation { get; set; } = 0; // 0 = normal, 1 = rotated 90deg
}

/// <summary>
/// Player's stash (grid-based inventory)
/// </summary>
public class Stash
{
    public int Width { get; set; } = 10;
    public int Height { get; set; } = 40;
    public List<StashPlacement> Placements { get; set; } = new();
}

/// <summary>
/// Player wallet (currencies)
/// </summary>
public class Wallet
{
    public long Gold { get; set; } = 10000; // Starting gold
    public long PremiumCurrency { get; set; } = 0;
}

/// <summary>
/// Trader reputation
/// </summary>
public class TraderRep
{
    public string TraderId { get; set; } = "";
    public float Rep { get; set; } = 0.0f; // -1.0 to 1.0
    public int Level { get; set; } = 1;
}

/// <summary>
/// Character (player's persistent data)
/// </summary>
public class Character
{
    public string CharacterId { get; set; } = "";
    public string AccountId { get; set; } = "";
    public string Name { get; set; } = "";
    public int Level { get; set; } = 1;
    public long Xp { get; set; } = 0;
    public Wallet Wallet { get; set; } = new();
    public Stash Stash { get; set; } = new();
    public List<ItemInstance> Items { get; set; } = new(); // All owned items
    public List<TraderRep> TraderReps { get; set; } = new();
    public int StashVersion { get; set; } = 1;
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public DateTime LastSeen { get; set; } = DateTime.UtcNow;
}

/// <summary>
/// Loadout slot configuration
/// </summary>
public class LoadoutSlots
{
    public string? Primary { get; set; }
    public string? Secondary { get; set; }
    public string? Melee { get; set; }
    public string? Armor { get; set; }
    public string? Rig { get; set; }
    public string? Bag { get; set; }
    public List<string> Pockets { get; set; } = new();
}

/// <summary>
/// Raid session (for anti-dupe)
/// </summary>
public class RaidSession
{
    public string RaidId { get; set; } = "";
    public string CharacterId { get; set; } = "";
    public string? MatchId { get; set; }
    public string? LobbyId { get; set; }
    public LoadoutSlots Loadout { get; set; } = new();
    public List<string> LockedIids { get; set; } = new();
    public RaidStatus Status { get; set; } = RaidStatus.Preparing;
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public DateTime? ExpiresAt { get; set; }
    public DateTime? CommittedAt { get; set; }
}

public enum RaidStatus
{
    Preparing,
    Active,
    Extracted,
    Died,
    Abandoned,
    Committed
}

/// <summary>
/// Provisional loot (not yet committed to stash)
/// </summary>
public class ProvisionalLoot
{
    public string DefId { get; set; } = "";
    public int Stack { get; set; } = 1;
    public float Durability { get; set; } = 1.0f;
    public int? RollSeed { get; set; }
    public Dictionary<string, object> Meta { get; set; } = new();
}

/// <summary>
/// Raid outcome for a single player
/// </summary>
public class RaidOutcome
{
    public string CharacterId { get; set; } = "";
    public string Status { get; set; } = "extracted"; // extracted, died, abandoned
    public List<ProvisionalLoot> ProvisionalLoot { get; set; } = new();
    public List<string> LostIids { get; set; } = new();
    public List<DurabilityUpdate> DurabilityUpdates { get; set; } = new();
    public long XpGained { get; set; } = 0;
    public long GoldGained { get; set; } = 0;
}

public class DurabilityUpdate
{
    public string Iid { get; set; } = "";
    public float Durability { get; set; }
}

/// <summary>
/// Market listing (escrow-based)
/// </summary>
public class MarketListing
{
    public string ListingId { get; set; } = "";
    public string SellerCharacterId { get; set; } = "";
    public string Iid { get; set; } = ""; // Item in escrow
    public string DefId { get; set; } = "";
    public long Price { get; set; }
    public long Fee { get; set; }
    public ListingStatus Status { get; set; } = ListingStatus.Active;
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public DateTime ExpiresAt { get; set; }
}

public enum ListingStatus
{
    Active,
    Sold,
    Cancelled,
    Expired
}

/// <summary>
/// Trader definition
/// </summary>
public class TraderDef
{
    public string TraderId { get; set; } = "";
    public string Name { get; set; } = "";
    public string Description { get; set; } = "";
    public float BuybackRate { get; set; } = 0.5f; // % of base value
    public List<string> AcceptedCategories { get; set; } = new(); // Empty = accepts all
    public List<TraderOffer> Offers { get; set; } = new();
}

public class TraderOffer
{
    public string OfferId { get; set; } = "";
    public string DefId { get; set; } = "";
    public int Price { get; set; }
    public int Stock { get; set; } = -1; // -1 = unlimited
    public int MinLevel { get; set; } = 1;
    public float MinRep { get; set; } = -1.0f;
    public DateTime? RestockAt { get; set; }
}

/// <summary>
/// Operation result with delta
/// </summary>
public class StashDelta
{
    public List<ItemInstance> Added { get; set; } = new();
    public List<string> Removed { get; set; } = new();
    public List<StashPlacement> Moved { get; set; } = new();
    public List<ItemInstance> Updated { get; set; } = new();
}

/// <summary>
/// Audit log entry
/// </summary>
public class AuditEntry
{
    public string EntryId { get; set; } = "";
    public string OpId { get; set; } = "";
    public string CharacterId { get; set; } = "";
    public string Operation { get; set; } = "";
    public string Details { get; set; } = "";
    public int PreviousVersion { get; set; }
    public int NewVersion { get; set; }
    public DateTime Timestamp { get; set; } = DateTime.UtcNow;
}
