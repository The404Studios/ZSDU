using System.Collections.Concurrent;
using ZSDU.Backend.Models;

namespace ZSDU.Backend;

/// <summary>
/// MarketService - Player-to-player market with escrow
///
/// Flow:
/// 1. Seller lists item → item moves to escrow (removed from stash)
/// 2. Buyer purchases → item transfers from escrow to buyer, gold transfers
/// 3. Seller can cancel → item returns to seller stash
/// 4. Listings expire → item returns to seller stash
///
/// Fees:
/// - Listing fee: 5% of price (paid upfront, non-refundable)
/// - Sale fee: 5% of price (deducted from seller proceeds)
/// </summary>
public class MarketService
{
    private readonly InventoryService _inventory;
    private readonly ConcurrentDictionary<string, MarketListing> _listings = new();

    private const float LISTING_FEE_RATE = 0.05f;
    private const float SALE_FEE_RATE = 0.05f;
    private static readonly TimeSpan DEFAULT_DURATION = TimeSpan.FromHours(24);

    public MarketService(InventoryService inventory)
    {
        _inventory = inventory;
    }

    // ============================================
    // PUBLIC API
    // ============================================

    /// <summary>
    /// Search market listings
    /// </summary>
    public object SearchListings(string? query = null, string? category = null, long? minPrice = null, long? maxPrice = null, int limit = 50, int offset = 0)
    {
        var results = _listings.Values
            .Where(l => l.Status == ListingStatus.Active && l.ExpiresAt > DateTime.UtcNow);

        // Apply filters
        if (!string.IsNullOrEmpty(query))
        {
            results = results.Where(l =>
            {
                var def = _inventory.GetItemDef(l.DefId);
                return def != null && (def.Name.Contains(query, StringComparison.OrdinalIgnoreCase) || def.DefId.Contains(query, StringComparison.OrdinalIgnoreCase));
            });
        }

        if (!string.IsNullOrEmpty(category))
        {
            results = results.Where(l =>
            {
                var def = _inventory.GetItemDef(l.DefId);
                return def != null && def.Category == category;
            });
        }

        if (minPrice.HasValue)
            results = results.Where(l => l.Price >= minPrice.Value);

        if (maxPrice.HasValue)
            results = results.Where(l => l.Price <= maxPrice.Value);

        // Order by price
        var ordered = results.OrderBy(l => l.Price).ToList();
        var total = ordered.Count;
        var paged = ordered.Skip(offset).Take(limit);

        return new
        {
            listings = paged.Select(l =>
            {
                var def = _inventory.GetItemDef(l.DefId);
                return new
                {
                    listing_id = l.ListingId,
                    def_id = l.DefId,
                    item_name = def?.Name ?? l.DefId,
                    price = l.Price,
                    expires_at = l.ExpiresAt,
                    created_at = l.CreatedAt
                };
            }),
            total,
            offset,
            limit
        };
    }

    /// <summary>
    /// Get listing details
    /// </summary>
    public object GetListing(string listingId)
    {
        if (!_listings.TryGetValue(listingId, out var listing))
            return new { error = "Listing not found" };

        var character = _inventory.GetCharacter(listing.SellerCharacterId);
        var def = _inventory.GetItemDef(listing.DefId);

        return new
        {
            listing_id = listing.ListingId,
            def_id = listing.DefId,
            item_name = def?.Name ?? listing.DefId,
            item = def,
            iid = listing.Iid,
            price = listing.Price,
            fee = listing.Fee,
            seller_name = character?.Name ?? "Unknown",
            status = listing.Status.ToString().ToLower(),
            created_at = listing.CreatedAt,
            expires_at = listing.ExpiresAt
        };
    }

    /// <summary>
    /// Create listing (escrow item)
    /// </summary>
    public object CreateListing(string characterId, string opId, string iid, long price, int durationHours = 24)
    {
        var character = _inventory.GetCharacter(characterId);
        if (character == null)
            return new { error = "Character not found" };

        var item = character.Items.FirstOrDefault(i => i.Iid == iid);
        if (item == null)
            return new { error = "Item not found" };

        // Check locks
        if (item.Flags.InRaid)
            return new { error = "Item is locked in raid" };
        if (item.Flags.InEscrow)
            return new { error = "Item is already listed" };
        if (item.Flags.NonTradeable)
            return new { error = "Item cannot be traded" };
        if (item.Flags.QuestBound)
            return new { error = "Quest items cannot be traded" };

        // Price validation
        if (price < 1)
            return new { error = "Price must be at least 1" };

        // Calculate listing fee
        var listingFee = (long)(price * LISTING_FEE_RATE);
        listingFee = Math.Max(1, listingFee); // Minimum 1 gold fee

        // Check if seller can afford fee
        if (character.Wallet.Gold < listingFee)
            return new { error = "Cannot afford listing fee" };

        // Deduct listing fee
        if (!_inventory.SpendGold(characterId, listingFee))
            return new { error = "Failed to pay listing fee" };

        // Create listing
        var listingId = $"lst_{Guid.NewGuid():N}";
        var duration = TimeSpan.FromHours(Math.Clamp(durationHours, 1, 72));

        var listing = new MarketListing
        {
            ListingId = listingId,
            SellerCharacterId = characterId,
            Iid = iid,
            DefId = item.DefId,
            Price = price,
            Fee = listingFee,
            Status = ListingStatus.Active,
            CreatedAt = DateTime.UtcNow,
            ExpiresAt = DateTime.UtcNow.Add(duration)
        };

        // Lock item in escrow
        if (!_inventory.LockItemForEscrow(characterId, iid, listingId))
        {
            // Refund listing fee
            _inventory.AddGold(characterId, listingFee);
            return new { error = "Failed to escrow item" };
        }

        _listings[listingId] = listing;

        Console.WriteLine($"[Market] {characterId} listed {item.DefId} for {price}g (fee: {listingFee}g)");

        return new
        {
            ok = true,
            listing_id = listingId,
            fee_paid = listingFee,
            stash_delta = new { removed = new List<string> { iid } },
            wallet = character.Wallet,
            version = character.StashVersion
        };
    }

    /// <summary>
    /// Cancel listing (return item)
    /// </summary>
    public object CancelListing(string characterId, string listingId)
    {
        if (!_listings.TryGetValue(listingId, out var listing))
            return new { error = "Listing not found" };

        if (listing.SellerCharacterId != characterId)
            return new { error = "Not your listing" };

        if (listing.Status != ListingStatus.Active)
            return new { error = "Listing is not active" };

        // Return item from escrow
        _inventory.ReturnFromEscrow(characterId, listing.Iid);

        // Mark as cancelled (fee is NOT refunded)
        listing.Status = ListingStatus.Cancelled;

        var character = _inventory.GetCharacter(characterId);

        Console.WriteLine($"[Market] {characterId} cancelled listing {listingId}");

        return new
        {
            ok = true,
            stash_delta = new { added = new List<string> { listing.Iid } },
            wallet = character?.Wallet,
            version = character?.StashVersion ?? 0
        };
    }

    /// <summary>
    /// Buy listing
    /// </summary>
    public object BuyListing(string characterId, string opId, string listingId)
    {
        if (!_listings.TryGetValue(listingId, out var listing))
            return new { error = "Listing not found" };

        if (listing.Status != ListingStatus.Active)
            return new { error = "Listing is not available" };

        if (listing.ExpiresAt < DateTime.UtcNow)
        {
            // Auto-expire
            _ExpireListing(listingId);
            return new { error = "Listing expired" };
        }

        if (listing.SellerCharacterId == characterId)
            return new { error = "Cannot buy your own listing" };

        var buyer = _inventory.GetCharacter(characterId);
        if (buyer == null)
            return new { error = "Buyer not found" };

        // Check funds
        if (buyer.Wallet.Gold < listing.Price)
            return new { error = "Insufficient funds" };

        // Deduct gold from buyer
        if (!_inventory.SpendGold(characterId, listing.Price))
            return new { error = "Payment failed" };

        // Transfer item from escrow to buyer
        var item = _inventory.TransferItem(listing.SellerCharacterId, characterId, listing.Iid);
        if (item == null)
        {
            // Refund buyer
            _inventory.AddGold(characterId, listing.Price);
            return new { error = "Transfer failed" };
        }

        // Pay seller (minus sale fee)
        var saleFee = (long)(listing.Price * SALE_FEE_RATE);
        var sellerProceeds = listing.Price - saleFee;
        _inventory.AddGold(listing.SellerCharacterId, sellerProceeds);

        // Mark as sold
        listing.Status = ListingStatus.Sold;

        var sellerChar = _inventory.GetCharacter(listing.SellerCharacterId);

        Console.WriteLine($"[Market] {characterId} bought {listing.DefId} from {listing.SellerCharacterId} for {listing.Price}g");

        return new
        {
            ok = true,
            item,
            price_paid = listing.Price,
            stash_delta = new { added = new List<ItemInstance> { item } },
            wallet = buyer.Wallet,
            version = buyer.StashVersion
        };
    }

    /// <summary>
    /// Get player's own listings
    /// </summary>
    public object GetMyListings(string characterId)
    {
        var listings = _listings.Values
            .Where(l => l.SellerCharacterId == characterId)
            .OrderByDescending(l => l.CreatedAt)
            .Select(l =>
            {
                var def = _inventory.GetItemDef(l.DefId);
                return new
                {
                    listing_id = l.ListingId,
                    def_id = l.DefId,
                    item_name = def?.Name ?? l.DefId,
                    price = l.Price,
                    status = l.Status.ToString().ToLower(),
                    created_at = l.CreatedAt,
                    expires_at = l.ExpiresAt
                };
            });

        return new { listings };
    }

    // ============================================
    // MAINTENANCE
    // ============================================

    /// <summary>
    /// Expire stale listings (call periodically)
    /// </summary>
    public void ExpireStaleListings()
    {
        var now = DateTime.UtcNow;
        var expiredIds = _listings
            .Where(kv => kv.Value.Status == ListingStatus.Active && kv.Value.ExpiresAt < now)
            .Select(kv => kv.Key)
            .ToList();

        foreach (var listingId in expiredIds)
        {
            _ExpireListing(listingId);
        }

        if (expiredIds.Count > 0)
        {
            Console.WriteLine($"[Market] Expired {expiredIds.Count} listings");
        }
    }

    private void _ExpireListing(string listingId)
    {
        if (!_listings.TryGetValue(listingId, out var listing))
            return;

        if (listing.Status != ListingStatus.Active)
            return;

        // Return item to seller
        _inventory.ReturnFromEscrow(listing.SellerCharacterId, listing.Iid);

        listing.Status = ListingStatus.Expired;
    }

    /// <summary>
    /// Get market stats
    /// </summary>
    public object GetMarketStats()
    {
        var active = _listings.Values.Count(l => l.Status == ListingStatus.Active);
        var sold = _listings.Values.Count(l => l.Status == ListingStatus.Sold);
        var expired = _listings.Values.Count(l => l.Status == ListingStatus.Expired);

        return new
        {
            active_listings = active,
            total_sold = sold,
            total_expired = expired
        };
    }
}
