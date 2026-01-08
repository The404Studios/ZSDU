using System.Collections.Concurrent;
using ZSDU.Backend.Models;

namespace ZSDU.Backend;

/// <summary>
/// InventoryService - Stash and item management
///
/// Rules:
/// - All mutations are atomic with version increments
/// - Locked items (in_raid, in_escrow) cannot be moved/sold
/// - OpId makes operations idempotent
/// - Every mutation is audit logged
/// </summary>
public class InventoryService
{
    // In-memory storage (replace with DB in production)
    private readonly ConcurrentDictionary<string, Character> _characters = new();
    private readonly ConcurrentDictionary<string, ItemDef> _itemDefs = new();
    private readonly ConcurrentDictionary<string, string> _opIdResults = new(); // opId -> result json
    private readonly ConcurrentDictionary<string, AuditEntry> _auditLog = new();

    private static int _nextAuditId = 1;

    public InventoryService()
    {
        _InitializeItemDefs();
    }

    // ============================================
    // ITEM DEFINITIONS (Static)
    // ============================================

    private void _InitializeItemDefs()
    {
        // Weapons
        _AddItemDef(new ItemDef
        {
            DefId = "akm",
            Name = "AKM",
            Category = "weapon",
            Tags = new List<string> { "weapon", "rifle", "automatic" },
            Width = 2, Height = 4,
            BaseValue = 18000
        });

        _AddItemDef(new ItemDef
        {
            DefId = "pistol_pm",
            Name = "PM Pistol",
            Category = "weapon",
            Tags = new List<string> { "weapon", "pistol" },
            Width = 1, Height = 2,
            BaseValue = 3500
        });

        _AddItemDef(new ItemDef
        {
            DefId = "hammer",
            Name = "Hammer",
            Category = "weapon",
            Tags = new List<string> { "weapon", "melee", "tool" },
            Width = 1, Height = 2,
            BaseValue = 500
        });

        _AddItemDef(new ItemDef
        {
            DefId = "nailgun",
            Name = "Nail Gun",
            Category = "weapon",
            Tags = new List<string> { "weapon", "tool", "barricade" },
            Width = 2, Height = 2,
            BaseValue = 2500
        });

        // Armor
        _AddItemDef(new ItemDef
        {
            DefId = "armor_light",
            Name = "Light Armor Vest",
            Category = "armor",
            Tags = new List<string> { "armor", "vest" },
            Width = 3, Height = 3,
            BaseValue = 8000
        });

        _AddItemDef(new ItemDef
        {
            DefId = "armor_heavy",
            Name = "Heavy Armor Vest",
            Category = "armor",
            Tags = new List<string> { "armor", "vest", "heavy" },
            Width = 3, Height = 4,
            BaseValue = 22000
        });

        // Medical
        _AddItemDef(new ItemDef
        {
            DefId = "medkit",
            Name = "Medical Kit",
            Category = "med",
            Tags = new List<string> { "med", "heal" },
            Width = 2, Height = 2,
            BaseValue = 3000
        });

        _AddItemDef(new ItemDef
        {
            DefId = "bandage",
            Name = "Bandage",
            Category = "med",
            Tags = new List<string> { "med", "heal", "quick" },
            Width = 1, Height = 1,
            MaxStack = 4,
            BaseValue = 200
        });

        _AddItemDef(new ItemDef
        {
            DefId = "painkiller",
            Name = "Painkillers",
            Category = "med",
            Tags = new List<string> { "med", "buff" },
            Width = 1, Height = 1,
            MaxStack = 4,
            BaseValue = 350
        });

        // Ammo
        _AddItemDef(new ItemDef
        {
            DefId = "ammo_762",
            Name = "7.62x39mm",
            Category = "ammo",
            Tags = new List<string> { "ammo", "rifle" },
            Width = 1, Height = 1,
            MaxStack = 60,
            BaseValue = 5
        });

        _AddItemDef(new ItemDef
        {
            DefId = "ammo_9mm",
            Name = "9x19mm",
            Category = "ammo",
            Tags = new List<string> { "ammo", "pistol" },
            Width = 1, Height = 1,
            MaxStack = 50,
            BaseValue = 3
        });

        _AddItemDef(new ItemDef
        {
            DefId = "nails",
            Name = "Box of Nails",
            Category = "ammo",
            Tags = new List<string> { "ammo", "barricade" },
            Width = 1, Height = 1,
            MaxStack = 100,
            BaseValue = 2
        });

        // Containers
        _AddItemDef(new ItemDef
        {
            DefId = "backpack_small",
            Name = "Small Backpack",
            Category = "container",
            Tags = new List<string> { "container", "bag" },
            Width = 3, Height = 3,
            BaseValue = 5000,
            Properties = new Dictionary<string, object>
            {
                { "container_width", 4 },
                { "container_height", 4 }
            }
        });

        _AddItemDef(new ItemDef
        {
            DefId = "rig_basic",
            Name = "Tactical Rig",
            Category = "container",
            Tags = new List<string> { "container", "rig" },
            Width = 2, Height = 3,
            BaseValue = 4000,
            Properties = new Dictionary<string, object>
            {
                { "container_width", 2 },
                { "container_height", 4 }
            }
        });

        // Loot / Barter
        _AddItemDef(new ItemDef
        {
            DefId = "scrap_metal",
            Name = "Scrap Metal",
            Category = "misc",
            Tags = new List<string> { "barter", "craft" },
            Width = 1, Height = 1,
            MaxStack = 20,
            BaseValue = 50
        });

        _AddItemDef(new ItemDef
        {
            DefId = "electronics",
            Name = "Electronics Parts",
            Category = "misc",
            Tags = new List<string> { "barter", "craft", "valuable" },
            Width = 1, Height = 1,
            MaxStack = 10,
            BaseValue = 250
        });

        _AddItemDef(new ItemDef
        {
            DefId = "zombie_trophy",
            Name = "Zombie Trophy",
            Category = "misc",
            Tags = new List<string> { "quest", "trophy" },
            Width = 1, Height = 1,
            MaxStack = 5,
            BaseValue = 100
        });
    }

    private void _AddItemDef(ItemDef def)
    {
        _itemDefs[def.DefId] = def;
    }

    public ItemDef? GetItemDef(string defId)
    {
        _itemDefs.TryGetValue(defId, out var def);
        return def;
    }

    public List<ItemDef> GetAllItemDefs()
    {
        return _itemDefs.Values.ToList();
    }

    // ============================================
    // CHARACTER MANAGEMENT
    // ============================================

    public Character CreateCharacter(string accountId, string name)
    {
        var character = new Character
        {
            CharacterId = $"char_{Guid.NewGuid():N}",
            AccountId = accountId,
            Name = name,
            Stash = new Stash { Width = 10, Height = 40 },
            Wallet = new Wallet { Gold = 10000 },
            Items = new List<ItemInstance>()
        };

        // Give starter kit
        _GiveStarterKit(character);

        _characters[character.CharacterId] = character;
        Console.WriteLine($"[Inventory] Created character: {character.CharacterId} ({name})");
        return character;
    }

    private void _GiveStarterKit(Character character)
    {
        // Starter weapons
        var hammer = _MintItem("hammer");
        var pistol = _MintItem("pistol_pm");
        var nailgun = _MintItem("nailgun");

        // Starter supplies
        var bandages = _MintItem("bandage", stack: 4);
        var ammo9mm = _MintItem("ammo_9mm", stack: 30);
        var nails = _MintItem("nails", stack: 50);

        // Add to inventory
        character.Items.AddRange(new[] { hammer, pistol, nailgun, bandages, ammo9mm, nails });

        // Place in stash
        character.Stash.Placements.Add(new StashPlacement { Iid = hammer.Iid, X = 0, Y = 0 });
        character.Stash.Placements.Add(new StashPlacement { Iid = pistol.Iid, X = 2, Y = 0 });
        character.Stash.Placements.Add(new StashPlacement { Iid = nailgun.Iid, X = 0, Y = 3 });
        character.Stash.Placements.Add(new StashPlacement { Iid = bandages.Iid, X = 4, Y = 0 });
        character.Stash.Placements.Add(new StashPlacement { Iid = ammo9mm.Iid, X = 5, Y = 0 });
        character.Stash.Placements.Add(new StashPlacement { Iid = nails.Iid, X = 6, Y = 0 });
    }

    private ItemInstance _MintItem(string defId, int stack = 1, float durability = 1.0f)
    {
        return new ItemInstance
        {
            Iid = $"itm_{Guid.NewGuid():N}",
            DefId = defId,
            Stack = stack,
            Durability = durability,
            CreatedAt = DateTime.UtcNow
        };
    }

    public Character? GetCharacter(string characterId)
    {
        _characters.TryGetValue(characterId, out var character);
        return character;
    }

    public Character? GetCharacterByAccount(string accountId)
    {
        return _characters.Values.FirstOrDefault(c => c.AccountId == accountId);
    }

    // ============================================
    // STASH OPERATIONS
    // ============================================

    /// <summary>
    /// Get full stash snapshot
    /// </summary>
    public object GetStashSnapshot(string characterId)
    {
        var character = GetCharacter(characterId);
        if (character == null)
            return new { error = "Character not found" };

        return new
        {
            stash = character.Stash,
            items = character.Items.Select(i => new
            {
                i.Iid,
                i.DefId,
                i.Stack,
                i.Durability,
                i.Mods,
                i.Flags,
                i.Meta
            }),
            wallet = character.Wallet,
            version = character.StashVersion
        };
    }

    /// <summary>
    /// Move item within stash (with collision detection)
    /// </summary>
    public object MoveItem(string characterId, string opId, string iid, int toX, int toY, int rotation)
    {
        // Idempotency check
        if (_opIdResults.TryGetValue(opId, out var cachedResult))
            return cachedResult;

        var character = GetCharacter(characterId);
        if (character == null)
            return _CacheResult(opId, new { error = "Character not found" });

        var item = character.Items.FirstOrDefault(i => i.Iid == iid);
        if (item == null)
            return _CacheResult(opId, new { error = "Item not found" });

        // Check locks
        if (item.Flags.InRaid)
            return _CacheResult(opId, new { error = "Item is locked in raid" });
        if (item.Flags.InEscrow)
            return _CacheResult(opId, new { error = "Item is in market escrow" });

        var def = GetItemDef(item.DefId);
        if (def == null)
            return _CacheResult(opId, new { error = "Invalid item definition" });

        // Calculate item dimensions with rotation
        int width = rotation == 0 ? def.Width : def.Height;
        int height = rotation == 0 ? def.Height : def.Width;

        // Bounds check
        if (toX < 0 || toY < 0 || toX + width > character.Stash.Width || toY + height > character.Stash.Height)
            return _CacheResult(opId, new { error = "Position out of bounds" });

        // Collision check (excluding self)
        foreach (var placement in character.Stash.Placements)
        {
            if (placement.Iid == iid) continue;

            var otherItem = character.Items.FirstOrDefault(i => i.Iid == placement.Iid);
            if (otherItem == null) continue;

            var otherDef = GetItemDef(otherItem.DefId);
            if (otherDef == null) continue;

            int otherW = placement.Rotation == 0 ? otherDef.Width : otherDef.Height;
            int otherH = placement.Rotation == 0 ? otherDef.Height : otherDef.Width;

            if (_RectsOverlap(toX, toY, width, height, placement.X, placement.Y, otherW, otherH))
                return _CacheResult(opId, new { error = "Position blocked by another item" });
        }

        // Find and update placement
        var existingPlacement = character.Stash.Placements.FirstOrDefault(p => p.Iid == iid);
        if (existingPlacement != null)
        {
            existingPlacement.X = toX;
            existingPlacement.Y = toY;
            existingPlacement.Rotation = rotation;
        }
        else
        {
            character.Stash.Placements.Add(new StashPlacement
            {
                Iid = iid,
                X = toX,
                Y = toY,
                Rotation = rotation
            });
        }

        // Increment version
        int prevVersion = character.StashVersion;
        character.StashVersion++;

        // Audit log
        _LogAudit(opId, characterId, "move_item", $"Moved {iid} to ({toX},{toY}) rot={rotation}", prevVersion, character.StashVersion);

        var result = new
        {
            ok = true,
            stash_delta = new StashDelta
            {
                Moved = new List<StashPlacement>
                {
                    new StashPlacement { Iid = iid, X = toX, Y = toY, Rotation = rotation }
                }
            },
            version = character.StashVersion
        };

        return _CacheResult(opId, result);
    }

    /// <summary>
    /// Discard item (destroy)
    /// </summary>
    public object DiscardItem(string characterId, string opId, string iid)
    {
        if (_opIdResults.TryGetValue(opId, out var cachedResult))
            return cachedResult;

        var character = GetCharacter(characterId);
        if (character == null)
            return _CacheResult(opId, new { error = "Character not found" });

        var item = character.Items.FirstOrDefault(i => i.Iid == iid);
        if (item == null)
            return _CacheResult(opId, new { error = "Item not found" });

        if (item.Flags.InRaid || item.Flags.InEscrow)
            return _CacheResult(opId, new { error = "Item is locked" });

        // Remove from stash and items
        character.Stash.Placements.RemoveAll(p => p.Iid == iid);
        character.Items.RemoveAll(i => i.Iid == iid);

        int prevVersion = character.StashVersion;
        character.StashVersion++;

        _LogAudit(opId, characterId, "discard_item", $"Discarded {iid} ({item.DefId})", prevVersion, character.StashVersion);

        return _CacheResult(opId, new
        {
            ok = true,
            stash_delta = new StashDelta { Removed = new List<string> { iid } },
            version = character.StashVersion
        });
    }

    /// <summary>
    /// Split stack
    /// </summary>
    public object SplitStack(string characterId, string opId, string iid, int splitAmount, int toX, int toY)
    {
        if (_opIdResults.TryGetValue(opId, out var cachedResult))
            return cachedResult;

        var character = GetCharacter(characterId);
        if (character == null)
            return _CacheResult(opId, new { error = "Character not found" });

        var item = character.Items.FirstOrDefault(i => i.Iid == iid);
        if (item == null)
            return _CacheResult(opId, new { error = "Item not found" });

        if (item.Flags.InRaid || item.Flags.InEscrow)
            return _CacheResult(opId, new { error = "Item is locked" });

        if (splitAmount <= 0 || splitAmount >= item.Stack)
            return _CacheResult(opId, new { error = "Invalid split amount" });

        var def = GetItemDef(item.DefId);
        if (def == null || def.MaxStack <= 1)
            return _CacheResult(opId, new { error = "Item cannot be stacked" });

        // Check target position is free
        if (toX < 0 || toY < 0 || toX + def.Width > character.Stash.Width || toY + def.Height > character.Stash.Height)
            return _CacheResult(opId, new { error = "Position out of bounds" });

        foreach (var placement in character.Stash.Placements)
        {
            var otherItem = character.Items.FirstOrDefault(i => i.Iid == placement.Iid);
            if (otherItem == null) continue;
            var otherDef = GetItemDef(otherItem.DefId);
            if (otherDef == null) continue;

            int otherW = placement.Rotation == 0 ? otherDef.Width : otherDef.Height;
            int otherH = placement.Rotation == 0 ? otherDef.Height : otherDef.Width;

            if (_RectsOverlap(toX, toY, def.Width, def.Height, placement.X, placement.Y, otherW, otherH))
                return _CacheResult(opId, new { error = "Position blocked" });
        }

        // Create new stack
        var newItem = _MintItem(item.DefId, stack: splitAmount);
        item.Stack -= splitAmount;

        character.Items.Add(newItem);
        character.Stash.Placements.Add(new StashPlacement { Iid = newItem.Iid, X = toX, Y = toY });

        int prevVersion = character.StashVersion;
        character.StashVersion++;

        _LogAudit(opId, characterId, "split_stack", $"Split {splitAmount} from {iid} to {newItem.Iid}", prevVersion, character.StashVersion);

        return _CacheResult(opId, new
        {
            ok = true,
            stash_delta = new StashDelta
            {
                Added = new List<ItemInstance> { newItem },
                Updated = new List<ItemInstance> { item }
            },
            version = character.StashVersion
        });
    }

    // ============================================
    // ITEM LOCKING (for raids/escrow)
    // ============================================

    /// <summary>
    /// Lock items for a raid
    /// </summary>
    public bool LockItemsForRaid(string characterId, List<string> iids, string raidId)
    {
        var character = GetCharacter(characterId);
        if (character == null) return false;

        foreach (var iid in iids)
        {
            var item = character.Items.FirstOrDefault(i => i.Iid == iid);
            if (item == null) continue;

            if (item.Flags.InRaid || item.Flags.InEscrow)
            {
                // Rollback any locks we made
                foreach (var lockedIid in iids)
                {
                    var lockedItem = character.Items.FirstOrDefault(i => i.Iid == lockedIid);
                    if (lockedItem != null && lockedItem.Flags.RaidId == raidId)
                    {
                        lockedItem.Flags.InRaid = false;
                        lockedItem.Flags.RaidId = null;
                    }
                }
                return false;
            }

            item.Flags.InRaid = true;
            item.Flags.RaidId = raidId;
        }

        return true;
    }

    /// <summary>
    /// Unlock items after raid
    /// </summary>
    public void UnlockRaidItems(string characterId, string raidId)
    {
        var character = GetCharacter(characterId);
        if (character == null) return;

        foreach (var item in character.Items)
        {
            if (item.Flags.RaidId == raidId)
            {
                item.Flags.InRaid = false;
                item.Flags.RaidId = null;
            }
        }
    }

    /// <summary>
    /// Remove items (lost in raid)
    /// </summary>
    public void RemoveItems(string characterId, List<string> iids)
    {
        var character = GetCharacter(characterId);
        if (character == null) return;

        foreach (var iid in iids)
        {
            character.Items.RemoveAll(i => i.Iid == iid);
            character.Stash.Placements.RemoveAll(p => p.Iid == iid);
        }
    }

    /// <summary>
    /// Add loot to stash (mint new items)
    /// </summary>
    public List<ItemInstance> MintLoot(string characterId, List<ProvisionalLoot> loot)
    {
        var character = GetCharacter(characterId);
        if (character == null) return new List<ItemInstance>();

        var minted = new List<ItemInstance>();

        foreach (var prov in loot)
        {
            var item = new ItemInstance
            {
                Iid = $"itm_{Guid.NewGuid():N}",
                DefId = prov.DefId,
                Stack = prov.Stack,
                Durability = prov.Durability,
                Meta = prov.Meta,
                CreatedAt = DateTime.UtcNow
            };

            character.Items.Add(item);
            minted.Add(item);

            // Auto-place in stash (find first free slot)
            var def = GetItemDef(prov.DefId);
            if (def != null)
            {
                var pos = _FindFreeSlot(character, def.Width, def.Height);
                if (pos.HasValue)
                {
                    character.Stash.Placements.Add(new StashPlacement
                    {
                        Iid = item.Iid,
                        X = pos.Value.x,
                        Y = pos.Value.y
                    });
                }
            }
        }

        character.StashVersion++;
        return minted;
    }

    /// <summary>
    /// Update item durability
    /// </summary>
    public void UpdateDurability(string characterId, List<DurabilityUpdate> updates)
    {
        var character = GetCharacter(characterId);
        if (character == null) return;

        foreach (var update in updates)
        {
            var item = character.Items.FirstOrDefault(i => i.Iid == update.Iid);
            if (item != null)
            {
                item.Durability = update.Durability;
            }
        }
    }

    /// <summary>
    /// Add currency
    /// </summary>
    public void AddGold(string characterId, long amount)
    {
        var character = GetCharacter(characterId);
        if (character != null)
        {
            character.Wallet.Gold += amount;
        }
    }

    /// <summary>
    /// Remove currency
    /// </summary>
    public bool SpendGold(string characterId, long amount)
    {
        var character = GetCharacter(characterId);
        if (character == null || character.Wallet.Gold < amount)
            return false;

        character.Wallet.Gold -= amount;
        return true;
    }

    // ============================================
    // HELPERS
    // ============================================

    private bool _RectsOverlap(int x1, int y1, int w1, int h1, int x2, int y2, int w2, int h2)
    {
        return !(x1 + w1 <= x2 || x2 + w2 <= x1 || y1 + h1 <= y2 || y2 + h2 <= y1);
    }

    private (int x, int y)? _FindFreeSlot(Character character, int width, int height)
    {
        for (int y = 0; y <= character.Stash.Height - height; y++)
        {
            for (int x = 0; x <= character.Stash.Width - width; x++)
            {
                bool blocked = false;
                foreach (var placement in character.Stash.Placements)
                {
                    var item = character.Items.FirstOrDefault(i => i.Iid == placement.Iid);
                    if (item == null) continue;
                    var def = GetItemDef(item.DefId);
                    if (def == null) continue;

                    int pw = placement.Rotation == 0 ? def.Width : def.Height;
                    int ph = placement.Rotation == 0 ? def.Height : def.Width;

                    if (_RectsOverlap(x, y, width, height, placement.X, placement.Y, pw, ph))
                    {
                        blocked = true;
                        break;
                    }
                }

                if (!blocked)
                    return (x, y);
            }
        }
        return null;
    }

    private object _CacheResult(string opId, object result)
    {
        var json = System.Text.Json.JsonSerializer.Serialize(result);
        _opIdResults[opId] = json;
        return result;
    }

    private void _LogAudit(string opId, string characterId, string operation, string details, int prevVersion, int newVersion)
    {
        var entry = new AuditEntry
        {
            EntryId = $"audit_{Interlocked.Increment(ref _nextAuditId)}",
            OpId = opId,
            CharacterId = characterId,
            Operation = operation,
            Details = details,
            PreviousVersion = prevVersion,
            NewVersion = newVersion,
            Timestamp = DateTime.UtcNow
        };
        _auditLog[entry.EntryId] = entry;
    }

    /// <summary>
    /// Get item instances by IIDs
    /// </summary>
    public List<ItemInstance> GetItems(string characterId, List<string> iids)
    {
        var character = GetCharacter(characterId);
        if (character == null) return new List<ItemInstance>();

        return character.Items.Where(i => iids.Contains(i.Iid)).ToList();
    }

    /// <summary>
    /// Lock item for escrow (market listing)
    /// </summary>
    public bool LockItemForEscrow(string characterId, string iid, string listingId)
    {
        var character = GetCharacter(characterId);
        if (character == null) return false;

        var item = character.Items.FirstOrDefault(i => i.Iid == iid);
        if (item == null || item.Flags.InRaid || item.Flags.InEscrow)
            return false;

        item.Flags.InEscrow = true;
        item.Flags.EscrowListingId = listingId;

        // Remove from stash placements (in escrow)
        character.Stash.Placements.RemoveAll(p => p.Iid == iid);
        character.StashVersion++;

        return true;
    }

    /// <summary>
    /// Return item from escrow
    /// </summary>
    public void ReturnFromEscrow(string characterId, string iid)
    {
        var character = GetCharacter(characterId);
        if (character == null) return;

        var item = character.Items.FirstOrDefault(i => i.Iid == iid);
        if (item == null) return;

        item.Flags.InEscrow = false;
        item.Flags.EscrowListingId = null;

        // Auto-place back in stash
        var def = GetItemDef(item.DefId);
        if (def != null)
        {
            var pos = _FindFreeSlot(character, def.Width, def.Height);
            if (pos.HasValue)
            {
                character.Stash.Placements.Add(new StashPlacement
                {
                    Iid = item.Iid,
                    X = pos.Value.x,
                    Y = pos.Value.y
                });
            }
        }
        character.StashVersion++;
    }

    /// <summary>
    /// Transfer item to another character (for market)
    /// </summary>
    public ItemInstance? TransferItem(string fromCharId, string toCharId, string iid)
    {
        var fromChar = GetCharacter(fromCharId);
        var toChar = GetCharacter(toCharId);
        if (fromChar == null || toChar == null) return null;

        var item = fromChar.Items.FirstOrDefault(i => i.Iid == iid);
        if (item == null) return null;

        // Remove from seller
        fromChar.Items.Remove(item);
        fromChar.Stash.Placements.RemoveAll(p => p.Iid == iid);
        fromChar.StashVersion++;

        // Clear flags
        item.Flags.InEscrow = false;
        item.Flags.EscrowListingId = null;

        // Add to buyer
        toChar.Items.Add(item);

        // Auto-place
        var def = GetItemDef(item.DefId);
        if (def != null)
        {
            var pos = _FindFreeSlot(toChar, def.Width, def.Height);
            if (pos.HasValue)
            {
                toChar.Stash.Placements.Add(new StashPlacement
                {
                    Iid = item.Iid,
                    X = pos.Value.x,
                    Y = pos.Value.y
                });
            }
        }
        toChar.StashVersion++;

        return item;
    }
}
