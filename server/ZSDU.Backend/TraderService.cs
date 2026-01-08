using System.Collections.Concurrent;
using ZSDU.Backend.Models;

namespace ZSDU.Backend;

/// <summary>
/// TraderService - NPC merchants with reputation
///
/// Traders:
/// - Have buy lists (what they accept)
/// - Have sell catalogs (limited stock)
/// - Prices scale with reputation
/// - Some items require minimum rep/level
/// </summary>
public class TraderService
{
    private readonly InventoryService _inventory;
    private readonly ConcurrentDictionary<string, TraderDef> _traders = new();
    private readonly ConcurrentDictionary<string, int> _traderStock = new(); // offer_id -> remaining stock

    public TraderService(InventoryService inventory)
    {
        _inventory = inventory;
        _InitializeTraders();
    }

    private void _InitializeTraders()
    {
        // The Mechanic - weapons and tools
        _traders["mechanic"] = new TraderDef
        {
            TraderId = "mechanic",
            Name = "The Mechanic",
            Description = "Deals in weapons, tools, and ammunition",
            BuybackRate = 0.45f,
            AcceptedCategories = new List<string> { "weapon", "ammo", "tool" },
            Offers = new List<TraderOffer>
            {
                new TraderOffer { OfferId = "mech_1", DefId = "akm", Price = 22000, Stock = 3, MinLevel = 1 },
                new TraderOffer { OfferId = "mech_2", DefId = "pistol_pm", Price = 4500, Stock = 10, MinLevel = 1 },
                new TraderOffer { OfferId = "mech_3", DefId = "hammer", Price = 600, Stock = -1, MinLevel = 1 },
                new TraderOffer { OfferId = "mech_4", DefId = "nailgun", Price = 3200, Stock = 5, MinLevel = 1 },
                new TraderOffer { OfferId = "mech_5", DefId = "ammo_762", Price = 8, Stock = -1, MinLevel = 1 },
                new TraderOffer { OfferId = "mech_6", DefId = "ammo_9mm", Price = 5, Stock = -1, MinLevel = 1 },
                new TraderOffer { OfferId = "mech_7", DefId = "nails", Price = 3, Stock = -1, MinLevel = 1 },
            }
        };

        // The Medic - medical supplies
        _traders["medic"] = new TraderDef
        {
            TraderId = "medic",
            Name = "Doc",
            Description = "Medical supplies and treatment",
            BuybackRate = 0.50f,
            AcceptedCategories = new List<string> { "med" },
            Offers = new List<TraderOffer>
            {
                new TraderOffer { OfferId = "med_1", DefId = "medkit", Price = 4000, Stock = 5, MinLevel = 1 },
                new TraderOffer { OfferId = "med_2", DefId = "bandage", Price = 280, Stock = 20, MinLevel = 1 },
                new TraderOffer { OfferId = "med_3", DefId = "painkiller", Price = 450, Stock = 10, MinLevel = 1 },
            }
        };

        // The Outfitter - armor and containers
        _traders["outfitter"] = new TraderDef
        {
            TraderId = "outfitter",
            Name = "The Outfitter",
            Description = "Protective gear and storage",
            BuybackRate = 0.40f,
            AcceptedCategories = new List<string> { "armor", "container" },
            Offers = new List<TraderOffer>
            {
                new TraderOffer { OfferId = "out_1", DefId = "armor_light", Price = 10000, Stock = 3, MinLevel = 1 },
                new TraderOffer { OfferId = "out_2", DefId = "armor_heavy", Price = 28000, Stock = 1, MinLevel = 5, MinRep = 0.1f },
                new TraderOffer { OfferId = "out_3", DefId = "backpack_small", Price = 6500, Stock = 5, MinLevel = 1 },
                new TraderOffer { OfferId = "out_4", DefId = "rig_basic", Price = 5200, Stock = 5, MinLevel = 1 },
            }
        };

        // Fence - buys everything, sells junk
        _traders["fence"] = new TraderDef
        {
            TraderId = "fence",
            Name = "Fence",
            Description = "Buys anything, no questions asked",
            BuybackRate = 0.25f, // Worst prices but accepts all
            AcceptedCategories = new List<string>(), // Empty = accepts everything
            Offers = new List<TraderOffer>
            {
                // Fence sells random/looted items at markup - populated dynamically
                new TraderOffer { OfferId = "fence_1", DefId = "scrap_metal", Price = 80, Stock = 50, MinLevel = 1 },
                new TraderOffer { OfferId = "fence_2", DefId = "electronics", Price = 400, Stock = 10, MinLevel = 1 },
            }
        };

        // Initialize stock
        foreach (var trader in _traders.Values)
        {
            foreach (var offer in trader.Offers)
            {
                if (offer.Stock > 0)
                {
                    _traderStock[offer.OfferId] = offer.Stock;
                }
            }
        }
    }

    // ============================================
    // PUBLIC API
    // ============================================

    /// <summary>
    /// Get list of all traders
    /// </summary>
    public object GetTraders(string characterId)
    {
        var character = _inventory.GetCharacter(characterId);

        return new
        {
            traders = _traders.Values.Select(t => new
            {
                trader_id = t.TraderId,
                name = t.Name,
                description = t.Description,
                rep = character?.TraderReps.FirstOrDefault(r => r.TraderId == t.TraderId)?.Rep ?? 0f
            })
        };
    }

    /// <summary>
    /// Get trader catalog
    /// </summary>
    public object GetTraderCatalog(string traderId, string characterId)
    {
        if (!_traders.TryGetValue(traderId, out var trader))
            return new { error = "Trader not found" };

        var character = _inventory.GetCharacter(characterId);
        var rep = character?.TraderReps.FirstOrDefault(r => r.TraderId == traderId);
        var level = character?.Level ?? 1;

        // Filter offers by requirements
        var availableOffers = trader.Offers
            .Where(o => o.MinLevel <= level && o.MinRep <= (rep?.Rep ?? 0f))
            .Select(o => new
            {
                offer_id = o.OfferId,
                def_id = o.DefId,
                item = _inventory.GetItemDef(o.DefId),
                price = _GetAdjustedPrice(o.Price, rep?.Rep ?? 0f, true),
                stock = o.Stock == -1 ? -1 : _traderStock.GetValueOrDefault(o.OfferId, 0),
                min_level = o.MinLevel,
                min_rep = o.MinRep
            })
            .Where(o => o.item != null);

        return new
        {
            trader_id = traderId,
            name = trader.Name,
            buyback_rate = _GetAdjustedBuybackRate(trader.BuybackRate, rep?.Rep ?? 0f),
            accepted_categories = trader.AcceptedCategories.Count == 0 ? new List<string> { "all" } : trader.AcceptedCategories,
            offers = availableOffers
        };
    }

    /// <summary>
    /// Buy from trader
    /// </summary>
    public object BuyFromTrader(string characterId, string opId, string traderId, string offerId, int quantity = 1)
    {
        if (!_traders.TryGetValue(traderId, out var trader))
            return new { error = "Trader not found" };

        var offer = trader.Offers.FirstOrDefault(o => o.OfferId == offerId);
        if (offer == null)
            return new { error = "Offer not found" };

        var character = _inventory.GetCharacter(characterId);
        if (character == null)
            return new { error = "Character not found" };

        // Check requirements
        var rep = character.TraderReps.FirstOrDefault(r => r.TraderId == traderId);
        if (offer.MinLevel > character.Level)
            return new { error = "Level too low" };
        if (offer.MinRep > (rep?.Rep ?? 0f))
            return new { error = "Reputation too low" };

        // Check stock
        if (offer.Stock > 0)
        {
            var currentStock = _traderStock.GetValueOrDefault(offer.OfferId, 0);
            if (currentStock < quantity)
                return new { error = "Out of stock" };
        }

        // Calculate price
        var totalPrice = _GetAdjustedPrice(offer.Price, rep?.Rep ?? 0f, true) * quantity;

        // Check funds
        if (character.Wallet.Gold < totalPrice)
            return new { error = "Insufficient funds" };

        // Deduct gold
        if (!_inventory.SpendGold(characterId, totalPrice))
            return new { error = "Payment failed" };

        // Reduce stock
        if (offer.Stock > 0)
        {
            _traderStock.AddOrUpdate(offer.OfferId, 0, (_, current) => Math.Max(0, current - quantity));
        }

        // Give items
        var def = _inventory.GetItemDef(offer.DefId);
        var stack = def?.MaxStack > 1 ? Math.Min(quantity, def.MaxStack) : 1;
        var itemsToMint = new List<ProvisionalLoot>();

        int remaining = quantity;
        while (remaining > 0)
        {
            var thisStack = Math.Min(remaining, stack);
            itemsToMint.Add(new ProvisionalLoot
            {
                DefId = offer.DefId,
                Stack = thisStack,
                Durability = 1.0f
            });
            remaining -= thisStack;
        }

        var mintedItems = _inventory.MintLoot(characterId, itemsToMint);

        // Small rep gain
        _AddRep(characterId, traderId, 0.001f * quantity);

        Console.WriteLine($"[Trader] {characterId} bought {quantity}x {offer.DefId} from {traderId} for {totalPrice}g");

        return new
        {
            ok = true,
            stash_delta = new { added = mintedItems },
            wallet = character.Wallet,
            version = character.StashVersion
        };
    }

    /// <summary>
    /// Sell to trader
    /// </summary>
    public object SellToTrader(string characterId, string opId, string traderId, string iid, int? quantity = null)
    {
        if (!_traders.TryGetValue(traderId, out var trader))
            return new { error = "Trader not found" };

        var character = _inventory.GetCharacter(characterId);
        if (character == null)
            return new { error = "Character not found" };

        var item = character.Items.FirstOrDefault(i => i.Iid == iid);
        if (item == null)
            return new { error = "Item not found" };

        // Check if locked
        if (item.Flags.InRaid || item.Flags.InEscrow)
            return new { error = "Item is locked" };

        var def = _inventory.GetItemDef(item.DefId);
        if (def == null)
            return new { error = "Invalid item" };

        // Check if trader accepts this category
        if (trader.AcceptedCategories.Count > 0 && !trader.AcceptedCategories.Contains(def.Category))
            return new { error = "Trader doesn't accept this item type" };

        // Calculate sell price
        var rep = character.TraderReps.FirstOrDefault(r => r.TraderId == traderId);
        var buybackRate = _GetAdjustedBuybackRate(trader.BuybackRate, rep?.Rep ?? 0f);
        var sellQuantity = quantity ?? item.Stack;
        var unitPrice = (int)(def.BaseValue * buybackRate * item.Durability);
        var totalPrice = unitPrice * sellQuantity;

        // Handle partial stack sell
        if (sellQuantity < item.Stack)
        {
            item.Stack -= sellQuantity;
            character.StashVersion++;
        }
        else
        {
            // Remove entire item
            character.Items.Remove(item);
            character.Stash.Placements.RemoveAll(p => p.Iid == iid);
            character.StashVersion++;
        }

        // Add gold
        _inventory.AddGold(characterId, totalPrice);

        // Small rep gain
        _AddRep(characterId, traderId, 0.0005f * sellQuantity);

        Console.WriteLine($"[Trader] {characterId} sold {sellQuantity}x {item.DefId} to {traderId} for {totalPrice}g");

        return new
        {
            ok = true,
            stash_delta = new
            {
                removed = sellQuantity >= (quantity ?? item.Stack) ? new List<string> { iid } : new List<string>(),
                updated = sellQuantity < (quantity ?? item.Stack) ? new List<string> { iid } : new List<string>()
            },
            gold_earned = totalPrice,
            wallet = character.Wallet,
            version = character.StashVersion
        };
    }

    // ============================================
    // HELPERS
    // ============================================

    private int _GetAdjustedPrice(int basePrice, float rep, bool buying)
    {
        // Better rep = better prices
        // buying: lower is better, selling: higher is better
        var modifier = 1.0f - (rep * 0.15f); // Up to 15% discount at max rep
        if (!buying) modifier = 1.0f / modifier;

        return Math.Max(1, (int)(basePrice * modifier));
    }

    private float _GetAdjustedBuybackRate(float baseRate, float rep)
    {
        // Better rep = better sell prices
        return baseRate + (rep * 0.1f); // Up to 10% better buyback at max rep
    }

    private void _AddRep(string characterId, string traderId, float amount)
    {
        var character = _inventory.GetCharacter(characterId);
        if (character == null) return;

        var rep = character.TraderReps.FirstOrDefault(r => r.TraderId == traderId);
        if (rep == null)
        {
            rep = new TraderRep { TraderId = traderId, Rep = 0f, Level = 1 };
            character.TraderReps.Add(rep);
        }

        rep.Rep = Math.Clamp(rep.Rep + amount, -1f, 1f);

        // Update level based on rep
        rep.Level = rep.Rep switch
        {
            < 0f => 1,
            < 0.25f => 1,
            < 0.5f => 2,
            < 0.75f => 3,
            _ => 4
        };
    }

    /// <summary>
    /// Restock traders (call periodically)
    /// </summary>
    public void RestockTraders()
    {
        foreach (var trader in _traders.Values)
        {
            foreach (var offer in trader.Offers)
            {
                if (offer.Stock > 0)
                {
                    _traderStock[offer.OfferId] = offer.Stock;
                }
            }
        }
        Console.WriteLine("[Trader] All traders restocked");
    }
}
