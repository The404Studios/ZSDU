using System.Collections.Concurrent;
using GameManager.Data;
using GameManager.Events;

namespace GameManager.Services;

/// <summary>
/// Handles matchmaking - finding appropriate servers for players
/// </summary>
public class Matchmaker
{
    private readonly ConcurrentDictionary<string, MatchmakingTicket> _tickets = new();
    private readonly SessionManager _sessionManager;
    private readonly EventBroker _eventBroker;
    private readonly Configuration _config;
    private readonly Timer _processTimer;

    public Matchmaker(SessionManager sessionManager, EventBroker eventBroker, Configuration config)
    {
        _sessionManager = sessionManager;
        _eventBroker = eventBroker;
        _config = config;

        // Process matchmaking every second
        _processTimer = new Timer(
            _ => ProcessMatchmaking(),
            null,
            TimeSpan.FromSeconds(1),
            TimeSpan.FromSeconds(1));
    }

    /// <summary>
    /// Start matchmaking for a player
    /// </summary>
    public async Task<MatchmakingTicket> StartMatchmakingAsync(MatchRequest request)
    {
        // Check if player already has a ticket
        var existingTicket = _tickets.Values.FirstOrDefault(
            t => t.PlayerIds.Contains(request.PlayerId) && t.Status == TicketStatus.Pending);

        if (existingTicket != null)
        {
            return existingTicket;
        }

        var playerIds = new List<string> { request.PlayerId };
        if (request.PartyMembers != null)
        {
            playerIds.AddRange(request.PartyMembers);
        }

        // Get skill ratings
        int minSkill = 0, maxSkill = 3000;
        foreach (var playerId in playerIds)
        {
            var session = _sessionManager.GetPlayerSessionByPlayerId(playerId);
            if (session != null)
            {
                minSkill = Math.Max(minSkill, session.SkillRating - 200);
                maxSkill = Math.Min(maxSkill, session.SkillRating + 200);
            }
        }

        var ticket = new MatchmakingTicket
        {
            PlayerIds = playerIds,
            GameMode = request.GameMode,
            PreferredRegion = request.PreferredRegion,
            MinSkillRating = minSkill,
            MaxSkillRating = maxSkill
        };

        _tickets[ticket.Id] = ticket;

        await _eventBroker.PublishAsync(new MatchmakingStartedEvent
        {
            TicketId = ticket.Id,
            PlayerIds = playerIds,
            GameMode = request.GameMode
        });

        Console.WriteLine($"[Matchmaker] Ticket created: {ticket.Id} for {playerIds.Count} players, mode: {request.GameMode}");

        return ticket;
    }

    /// <summary>
    /// Cancel matchmaking
    /// </summary>
    public async Task CancelMatchmakingAsync(string ticketId, string reason = "user_cancelled")
    {
        if (_tickets.TryRemove(ticketId, out var ticket))
        {
            ticket.Status = TicketStatus.Cancelled;

            await _eventBroker.PublishAsync(new MatchmakingCancelledEvent
            {
                TicketId = ticketId,
                Reason = reason
            });

            Console.WriteLine($"[Matchmaker] Ticket cancelled: {ticketId}");
        }
    }

    /// <summary>
    /// Get ticket status
    /// </summary>
    public MatchmakingTicket? GetTicket(string ticketId)
    {
        _tickets.TryGetValue(ticketId, out var ticket);
        return ticket;
    }

    /// <summary>
    /// Get ticket by player ID
    /// </summary>
    public MatchmakingTicket? GetTicketByPlayerId(string playerId)
    {
        return _tickets.Values.FirstOrDefault(
            t => t.PlayerIds.Contains(playerId) &&
                 (t.Status == TicketStatus.Pending || t.Status == TicketStatus.Matched));
    }

    /// <summary>
    /// Process all pending tickets
    /// </summary>
    private void ProcessMatchmaking()
    {
        try
        {
            var pendingTickets = _tickets.Values
                .Where(t => t.Status == TicketStatus.Pending)
                .OrderBy(t => t.CreatedAt)
                .ToList();

            foreach (var ticket in pendingTickets)
            {
                // Check timeout
                if ((DateTime.UtcNow - ticket.CreatedAt).TotalSeconds > _config.MatchmakingTimeoutSeconds)
                {
                    ticket.Status = TicketStatus.TimedOut;
                    _tickets.TryRemove(ticket.Id, out _);

                    _ = _eventBroker.PublishAsync(new MatchmakingTimedOutEvent
                    {
                        TicketId = ticket.Id
                    });

                    Console.WriteLine($"[Matchmaker] Ticket timed out: {ticket.Id}");
                    continue;
                }

                // Try to find a matching server
                var server = FindBestServer(ticket);
                if (server != null)
                {
                    MatchToServer(ticket, server);
                }
            }
        }
        catch (Exception ex)
        {
            Console.WriteLine($"[Matchmaker] Processing error: {ex.Message}");
        }
    }

    /// <summary>
    /// Find the best server for a ticket
    /// </summary>
    private GameServer? FindBestServer(MatchmakingTicket ticket)
    {
        var availableServers = _sessionManager.GetAvailableServers()
            .Where(s => s.GameMode == ticket.GameMode)
            .Where(s => s.MaxPlayers - s.CurrentPlayers >= ticket.PlayerIds.Count)
            .ToList();

        if (availableServers.Count == 0)
            return null;

        // Score servers (lower is better)
        var scored = availableServers.Select(s =>
        {
            double score = 0;

            // Prefer servers with some players (not empty)
            if (s.CurrentPlayers == 0)
                score += 50;

            // Prefer servers that are filling up
            var fillRatio = (double)s.CurrentPlayers / s.MaxPlayers;
            score += (1 - fillRatio) * 30;

            // Could add region scoring here

            return (server: s, score);
        })
        .OrderBy(x => x.score)
        .ToList();

        return scored.FirstOrDefault().server;
    }

    /// <summary>
    /// Match ticket to server
    /// </summary>
    private void MatchToServer(MatchmakingTicket ticket, GameServer server)
    {
        ticket.Status = TicketStatus.Matched;
        ticket.AssignedServerId = server.Id;
        ticket.MatchedAt = DateTime.UtcNow;

        // Assign players to server
        foreach (var playerId in ticket.PlayerIds)
        {
            var session = _sessionManager.GetPlayerSessionByPlayerId(playerId);
            if (session != null)
            {
                _ = _sessionManager.JoinServerAsync(session.Id, server.Id);
            }
        }

        _ = _eventBroker.PublishAsync(new MatchFoundEvent
        {
            TicketId = ticket.Id,
            ServerId = server.Id,
            PlayerIds = ticket.PlayerIds
        });

        Console.WriteLine($"[Matchmaker] Match found! Ticket {ticket.Id} -> Server {server.Name}");

        // Move to confirmed after short delay (for cancellation window)
        Task.Delay(TimeSpan.FromSeconds(5)).ContinueWith(_ =>
        {
            if (_tickets.TryGetValue(ticket.Id, out var t) && t.Status == TicketStatus.Matched)
            {
                t.Status = TicketStatus.Confirmed;
                _tickets.TryRemove(ticket.Id, out _);
            }
        });
    }
}
