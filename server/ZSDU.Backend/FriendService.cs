using System.Collections.Concurrent;

namespace ZSDU.Backend;

/// <summary>
/// FriendService - In-memory friend list and social features
/// </summary>
public class FriendService
{
    // Player data storage
    private readonly ConcurrentDictionary<string, PlayerData> _players = new();

    // Friend relationships (bi-directional)
    private readonly ConcurrentDictionary<string, HashSet<string>> _friends = new();

    // Pending friend requests (from -> to)
    private readonly ConcurrentDictionary<string, List<FriendRequestData>> _pendingRequests = new();

    // Game invites (to -> invite data)
    private readonly ConcurrentDictionary<string, List<GameInvite>> _pendingInvites = new();

    public class PlayerData
    {
        public string Id { get; set; } = "";
        public string Name { get; set; } = "";
        public bool IsOnline { get; set; }
        public string? CurrentGame { get; set; }
        public long LastSeen { get; set; }
    }

    public class FriendRequestData
    {
        public string FromId { get; set; } = "";
        public string FromName { get; set; } = "";
        public long Timestamp { get; set; }
    }

    public class GameInvite
    {
        public string FromId { get; set; } = "";
        public string FromName { get; set; } = "";
        public Dictionary<string, object>? ServerInfo { get; set; }
        public long Timestamp { get; set; }
    }

    /// <summary>
    /// Update player's online status
    /// </summary>
    public void UpdatePlayerStatus(string playerId, bool isOnline, string? currentGame = null)
    {
        var player = _players.GetOrAdd(playerId, id => new PlayerData { Id = id, Name = $"Player_{id[^8..]}" });
        player.IsOnline = isOnline;
        player.CurrentGame = currentGame;
        player.LastSeen = DateTimeOffset.UtcNow.ToUnixTimeSeconds();
    }

    /// <summary>
    /// Send a friend request
    /// </summary>
    public void SendFriendRequest(string fromId, string toId)
    {
        if (fromId == toId) return;

        // Check if already friends
        if (_friends.TryGetValue(fromId, out var friends) && friends.Contains(toId))
            return;

        // Get or create pending requests list for recipient
        var requests = _pendingRequests.GetOrAdd(toId, _ => new List<FriendRequestData>());

        // Check if request already exists
        lock (requests)
        {
            if (requests.Any(r => r.FromId == fromId))
                return;

            var fromPlayer = _players.GetOrAdd(fromId, id => new PlayerData { Id = id, Name = $"Player_{id[^8..]}" });

            requests.Add(new FriendRequestData
            {
                FromId = fromId,
                FromName = fromPlayer.Name,
                Timestamp = DateTimeOffset.UtcNow.ToUnixTimeSeconds()
            });
        }

        Console.WriteLine($"[Friends] Request sent: {fromId} -> {toId}");
    }

    /// <summary>
    /// Accept a friend request
    /// </summary>
    public object? AcceptFriendRequest(string playerId, string fromId)
    {
        // Remove from pending
        if (_pendingRequests.TryGetValue(playerId, out var requests))
        {
            lock (requests)
            {
                requests.RemoveAll(r => r.FromId == fromId);
            }
        }

        // Add bi-directional friendship
        var playerFriends = _friends.GetOrAdd(playerId, _ => new HashSet<string>());
        var fromFriends = _friends.GetOrAdd(fromId, _ => new HashSet<string>());

        lock (playerFriends) playerFriends.Add(fromId);
        lock (fromFriends) fromFriends.Add(playerId);

        var friend = _players.GetOrAdd(fromId, id => new PlayerData { Id = id, Name = $"Player_{id[^8..]}" });

        Console.WriteLine($"[Friends] Request accepted: {playerId} <-> {fromId}");

        return new
        {
            id = friend.Id,
            name = friend.Name,
            online = friend.IsOnline,
            currentGame = friend.CurrentGame,
            lastSeen = friend.LastSeen
        };
    }

    /// <summary>
    /// Decline a friend request
    /// </summary>
    public void DeclineFriendRequest(string playerId, string fromId)
    {
        if (_pendingRequests.TryGetValue(playerId, out var requests))
        {
            lock (requests)
            {
                requests.RemoveAll(r => r.FromId == fromId);
            }
        }
    }

    /// <summary>
    /// Remove a friend
    /// </summary>
    public void RemoveFriend(string playerId, string friendId)
    {
        if (_friends.TryGetValue(playerId, out var playerFriends))
        {
            lock (playerFriends) playerFriends.Remove(friendId);
        }

        if (_friends.TryGetValue(friendId, out var friendFriends))
        {
            lock (friendFriends) friendFriends.Remove(playerId);
        }

        Console.WriteLine($"[Friends] Removed: {playerId} <-> {friendId}");
    }

    /// <summary>
    /// Get friend statuses
    /// </summary>
    public List<object> GetFriendStatuses(List<string> friendIds)
    {
        var statuses = new List<object>();

        foreach (var id in friendIds)
        {
            if (_players.TryGetValue(id, out var player))
            {
                statuses.Add(new
                {
                    id = player.Id,
                    name = player.Name,
                    online = player.IsOnline,
                    currentGame = player.CurrentGame,
                    lastSeen = player.LastSeen
                });
            }
            else
            {
                statuses.Add(new
                {
                    id,
                    name = $"Player_{id[^8..]}",
                    online = false,
                    currentGame = (string?)null,
                    lastSeen = 0L
                });
            }
        }

        return statuses;
    }

    /// <summary>
    /// Get pending friend requests for a player
    /// </summary>
    public List<object> GetPendingRequests(string playerId)
    {
        if (!_pendingRequests.TryGetValue(playerId, out var requests))
            return new List<object>();

        lock (requests)
        {
            return requests.Select(r => (object)new
            {
                fromId = r.FromId,
                fromName = r.FromName,
                timestamp = r.Timestamp
            }).ToList();
        }
    }

    /// <summary>
    /// Send a game invite
    /// </summary>
    public void SendGameInvite(string fromId, string toId, Dictionary<string, object>? serverInfo)
    {
        var invites = _pendingInvites.GetOrAdd(toId, _ => new List<GameInvite>());
        var fromPlayer = _players.GetOrAdd(fromId, id => new PlayerData { Id = id, Name = $"Player_{id[^8..]}" });

        lock (invites)
        {
            // Remove old invite from same player
            invites.RemoveAll(i => i.FromId == fromId);

            invites.Add(new GameInvite
            {
                FromId = fromId,
                FromName = fromPlayer.Name,
                ServerInfo = serverInfo,
                Timestamp = DateTimeOffset.UtcNow.ToUnixTimeSeconds()
            });
        }

        Console.WriteLine($"[Friends] Game invite sent: {fromId} -> {toId}");
    }

    /// <summary>
    /// Get pending game invites for a player
    /// </summary>
    public List<object> GetPendingInvites(string playerId)
    {
        if (!_pendingInvites.TryGetValue(playerId, out var invites))
            return new List<object>();

        lock (invites)
        {
            // Remove old invites (older than 5 minutes)
            var cutoff = DateTimeOffset.UtcNow.ToUnixTimeSeconds() - 300;
            invites.RemoveAll(i => i.Timestamp < cutoff);

            return invites.Select(i => (object)new
            {
                fromId = i.FromId,
                fromName = i.FromName,
                serverInfo = i.ServerInfo,
                timestamp = i.Timestamp
            }).ToList();
        }
    }

    /// <summary>
    /// Get all friends for a player
    /// </summary>
    public List<object> GetFriends(string playerId)
    {
        if (!_friends.TryGetValue(playerId, out var friendIds))
            return new List<object>();

        lock (friendIds)
        {
            return GetFriendStatuses(friendIds.ToList());
        }
    }
}
