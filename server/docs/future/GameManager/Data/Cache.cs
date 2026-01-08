using System.Collections.Concurrent;
using System.Text.Json;

namespace GameManager.Data;

/// <summary>
/// In-memory cache implementation
/// In production, replace with Redis client
/// </summary>
public class CacheService
{
    private readonly ConcurrentDictionary<string, CacheEntry> _cache = new();
    private readonly Timer _cleanupTimer;

    public CacheService()
    {
        // Cleanup expired entries every minute
        _cleanupTimer = new Timer(
            _ => CleanupExpired(),
            null,
            TimeSpan.FromMinutes(1),
            TimeSpan.FromMinutes(1));
    }

    /// <summary>
    /// Get a value from cache
    /// </summary>
    public T? Get<T>(string key)
    {
        if (_cache.TryGetValue(key, out var entry))
        {
            if (entry.ExpiresAt == null || entry.ExpiresAt > DateTime.UtcNow)
            {
                if (entry.Value is T typed)
                    return typed;

                if (entry.Value is string json)
                    return JsonSerializer.Deserialize<T>(json);
            }
            else
            {
                // Expired
                _cache.TryRemove(key, out _);
            }
        }
        return default;
    }

    /// <summary>
    /// Set a value in cache
    /// </summary>
    public void Set<T>(string key, T value, TimeSpan? expiry = null)
    {
        var entry = new CacheEntry
        {
            Value = value,
            ExpiresAt = expiry.HasValue ? DateTime.UtcNow + expiry.Value : null
        };
        _cache[key] = entry;
    }

    /// <summary>
    /// Remove a value from cache
    /// </summary>
    public void Remove(string key)
    {
        _cache.TryRemove(key, out _);
    }

    /// <summary>
    /// Check if key exists
    /// </summary>
    public bool Exists(string key)
    {
        if (_cache.TryGetValue(key, out var entry))
        {
            if (entry.ExpiresAt == null || entry.ExpiresAt > DateTime.UtcNow)
                return true;
            _cache.TryRemove(key, out _);
        }
        return false;
    }

    /// <summary>
    /// Increment a counter
    /// </summary>
    public long Increment(string key, long amount = 1)
    {
        var entry = _cache.AddOrUpdate(
            key,
            _ => new CacheEntry { Value = amount },
            (_, existing) =>
            {
                if (existing.Value is long current)
                    existing.Value = current + amount;
                else
                    existing.Value = amount;
                return existing;
            });

        return (long)entry.Value!;
    }

    /// <summary>
    /// Get all keys matching a pattern
    /// </summary>
    public IEnumerable<string> Keys(string pattern)
    {
        var regex = new System.Text.RegularExpressions.Regex(
            "^" + System.Text.RegularExpressions.Regex.Escape(pattern).Replace("\\*", ".*") + "$");

        return _cache.Keys.Where(k => regex.IsMatch(k));
    }

    /// <summary>
    /// List operations (for queues)
    /// </summary>
    public void ListPush(string key, object value)
    {
        _cache.AddOrUpdate(
            key,
            _ => new CacheEntry { Value = new List<object> { value } },
            (_, existing) =>
            {
                if (existing.Value is List<object> list)
                    list.Add(value);
                else
                    existing.Value = new List<object> { value };
                return existing;
            });
    }

    public T? ListPop<T>(string key)
    {
        if (_cache.TryGetValue(key, out var entry) && entry.Value is List<object> list && list.Count > 0)
        {
            var item = list[0];
            list.RemoveAt(0);

            if (item is T typed)
                return typed;
        }
        return default;
    }

    public int ListLength(string key)
    {
        if (_cache.TryGetValue(key, out var entry) && entry.Value is List<object> list)
            return list.Count;
        return 0;
    }

    /// <summary>
    /// Hash operations (for objects)
    /// </summary>
    public void HashSet(string key, string field, object value)
    {
        _cache.AddOrUpdate(
            key,
            _ => new CacheEntry { Value = new Dictionary<string, object> { [field] = value } },
            (_, existing) =>
            {
                if (existing.Value is Dictionary<string, object> hash)
                    hash[field] = value;
                else
                    existing.Value = new Dictionary<string, object> { [field] = value };
                return existing;
            });
    }

    public T? HashGet<T>(string key, string field)
    {
        if (_cache.TryGetValue(key, out var entry) && entry.Value is Dictionary<string, object> hash)
        {
            if (hash.TryGetValue(field, out var value) && value is T typed)
                return typed;
        }
        return default;
    }

    public Dictionary<string, object>? HashGetAll(string key)
    {
        if (_cache.TryGetValue(key, out var entry) && entry.Value is Dictionary<string, object> hash)
            return new Dictionary<string, object>(hash);
        return null;
    }

    private void CleanupExpired()
    {
        var now = DateTime.UtcNow;
        var expired = _cache
            .Where(kvp => kvp.Value.ExpiresAt.HasValue && kvp.Value.ExpiresAt < now)
            .Select(kvp => kvp.Key)
            .ToList();

        foreach (var key in expired)
        {
            _cache.TryRemove(key, out _);
        }
    }

    private class CacheEntry
    {
        public object? Value { get; set; }
        public DateTime? ExpiresAt { get; set; }
    }
}
