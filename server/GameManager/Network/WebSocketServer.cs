using System.Collections.Concurrent;
using System.Net;
using System.Net.WebSockets;
using System.Text;
using System.Text.Json;
using GameManager.Events;
using GameManager.Services;

namespace GameManager.Network;

/// <summary>
/// WebSocket server for real-time client communication
/// Handles live updates, matchmaking notifications, and game events
/// </summary>
public class WebSocketServer
{
    private readonly HttpListener _listener;
    private readonly EventBroker _eventBroker;
    private readonly SessionManager _sessionManager;
    private readonly Matchmaker _matchmaker;
    private readonly Configuration _config;
    private readonly ConcurrentDictionary<string, WebSocketClient> _clients = new();
    private CancellationTokenSource? _cts;

    public WebSocketServer(
        EventBroker eventBroker,
        SessionManager sessionManager,
        Matchmaker matchmaker,
        Configuration config)
    {
        _eventBroker = eventBroker;
        _sessionManager = sessionManager;
        _matchmaker = matchmaker;
        _config = config;
        _listener = new HttpListener();

        // Subscribe to events for broadcasting
        _eventBroker.Subscribe<MatchFoundEvent>(BroadcastMatchFound);
        _eventBroker.Subscribe<ServerStatusChangedEvent>(BroadcastServerStatusChanged);
    }

    /// <summary>
    /// Start the WebSocket server
    /// </summary>
    public async Task StartAsync(CancellationToken ct)
    {
        _cts = CancellationTokenSource.CreateLinkedTokenSource(ct);

        var prefix = $"http://{_config.HttpHost}:{_config.WebSocketPort}/";
        _listener.Prefixes.Add(prefix);
        _listener.Start();

        Console.WriteLine($"[WebSocket] Listening on {prefix}");

        while (!_cts.Token.IsCancellationRequested)
        {
            try
            {
                var context = await _listener.GetContextAsync();

                if (context.Request.IsWebSocketRequest)
                {
                    _ = HandleWebSocketAsync(context);
                }
                else
                {
                    context.Response.StatusCode = 400;
                    context.Response.Close();
                }
            }
            catch (HttpListenerException) when (_cts.Token.IsCancellationRequested)
            {
                break;
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[WebSocket] Error: {ex.Message}");
            }
        }
    }

    /// <summary>
    /// Stop the WebSocket server
    /// </summary>
    public async Task StopAsync()
    {
        _cts?.Cancel();

        // Close all client connections
        foreach (var client in _clients.Values)
        {
            await client.CloseAsync("Server shutting down");
        }

        _listener.Stop();
    }

    /// <summary>
    /// Handle a WebSocket connection
    /// </summary>
    private async Task HandleWebSocketAsync(HttpListenerContext context)
    {
        WebSocketContext? wsContext = null;

        try
        {
            wsContext = await context.AcceptWebSocketAsync(null);
            var ws = wsContext.WebSocket;

            var clientId = Guid.NewGuid().ToString();
            var client = new WebSocketClient(clientId, ws);
            _clients[clientId] = client;

            Console.WriteLine($"[WebSocket] Client connected: {clientId}");

            // Send welcome message
            await client.SendAsync(new WsMessage
            {
                Type = "connected",
                Data = new { ClientId = clientId }
            });

            // Process messages
            var buffer = new byte[4096];
            while (ws.State == WebSocketState.Open && !_cts!.Token.IsCancellationRequested)
            {
                var result = await ws.ReceiveAsync(buffer, _cts.Token);

                if (result.MessageType == WebSocketMessageType.Close)
                {
                    break;
                }

                if (result.MessageType == WebSocketMessageType.Text)
                {
                    var json = Encoding.UTF8.GetString(buffer, 0, result.Count);
                    await HandleMessageAsync(client, json);
                }
            }
        }
        catch (WebSocketException ex)
        {
            Console.WriteLine($"[WebSocket] Connection error: {ex.Message}");
        }
        finally
        {
            if (wsContext != null)
            {
                var clientId = _clients.FirstOrDefault(c => c.Value.WebSocket == wsContext.WebSocket).Key;
                if (clientId != null)
                {
                    _clients.TryRemove(clientId, out var client);
                    if (client?.SessionId != null)
                    {
                        await _sessionManager.EndPlayerSessionAsync(client.SessionId, "websocket_disconnect");
                    }
                    Console.WriteLine($"[WebSocket] Client disconnected: {clientId}");
                }
            }
        }
    }

    /// <summary>
    /// Handle an incoming WebSocket message
    /// </summary>
    private async Task HandleMessageAsync(WebSocketClient client, string json)
    {
        try
        {
            var message = JsonSerializer.Deserialize<WsMessage>(json, new JsonSerializerOptions
            {
                PropertyNameCaseInsensitive = true
            });

            if (message == null) return;

            Console.WriteLine($"[WebSocket] {client.Id}: {message.Type}");

            switch (message.Type)
            {
                case "authenticate":
                    await HandleAuthenticate(client, message);
                    break;

                case "matchmaking_start":
                    await HandleMatchmakingStart(client, message);
                    break;

                case "matchmaking_cancel":
                    await HandleMatchmakingCancel(client);
                    break;

                case "matchmaking_status":
                    await HandleMatchmakingStatus(client);
                    break;

                case "ping":
                    await client.SendAsync(new WsMessage { Type = "pong" });
                    break;

                default:
                    await client.SendAsync(new WsMessage
                    {
                        Type = "error",
                        Data = new { Message = $"Unknown message type: {message.Type}" }
                    });
                    break;
            }
        }
        catch (Exception ex)
        {
            Console.WriteLine($"[WebSocket] Message handling error: {ex.Message}");
            await client.SendAsync(new WsMessage
            {
                Type = "error",
                Data = new { Message = ex.Message }
            });
        }
    }

    private async Task HandleAuthenticate(WebSocketClient client, WsMessage message)
    {
        var data = JsonSerializer.Deserialize<AuthenticateData>(
            message.Data?.ToString() ?? "{}",
            new JsonSerializerOptions { PropertyNameCaseInsensitive = true });

        if (data == null || string.IsNullOrEmpty(data.PlayerId))
        {
            await client.SendAsync(new WsMessage
            {
                Type = "error",
                Data = new { Message = "Invalid authentication data" }
            });
            return;
        }

        // Create player session
        var session = await _sessionManager.CreatePlayerSessionAsync(data.PlayerId, data.PlayerName ?? data.PlayerId);
        client.SessionId = session.Id;
        client.PlayerId = data.PlayerId;

        await client.SendAsync(new WsMessage
        {
            Type = "authenticated",
            Data = new { SessionId = session.Id }
        });
    }

    private async Task HandleMatchmakingStart(WebSocketClient client, WsMessage message)
    {
        if (client.PlayerId == null)
        {
            await client.SendAsync(new WsMessage
            {
                Type = "error",
                Data = new { Message = "Not authenticated" }
            });
            return;
        }

        var data = JsonSerializer.Deserialize<MatchmakingStartData>(
            message.Data?.ToString() ?? "{}",
            new JsonSerializerOptions { PropertyNameCaseInsensitive = true });

        var request = new Data.MatchRequest
        {
            PlayerId = client.PlayerId,
            GameMode = data?.GameMode ?? "survival",
            PreferredRegion = data?.PreferredRegion
        };

        var ticket = await _matchmaker.StartMatchmakingAsync(request);
        client.MatchmakingTicketId = ticket.Id;

        await client.SendAsync(new WsMessage
        {
            Type = "matchmaking_started",
            Data = new { TicketId = ticket.Id }
        });
    }

    private async Task HandleMatchmakingCancel(WebSocketClient client)
    {
        if (client.MatchmakingTicketId != null)
        {
            await _matchmaker.CancelMatchmakingAsync(client.MatchmakingTicketId);
            client.MatchmakingTicketId = null;

            await client.SendAsync(new WsMessage
            {
                Type = "matchmaking_cancelled"
            });
        }
    }

    private async Task HandleMatchmakingStatus(WebSocketClient client)
    {
        if (client.MatchmakingTicketId == null)
        {
            await client.SendAsync(new WsMessage
            {
                Type = "matchmaking_status",
                Data = new { Status = "none" }
            });
            return;
        }

        var ticket = _matchmaker.GetTicket(client.MatchmakingTicketId);
        if (ticket == null)
        {
            await client.SendAsync(new WsMessage
            {
                Type = "matchmaking_status",
                Data = new { Status = "not_found" }
            });
            return;
        }

        await client.SendAsync(new WsMessage
        {
            Type = "matchmaking_status",
            Data = new
            {
                Status = ticket.Status.ToString().ToLower(),
                WaitTime = (DateTime.UtcNow - ticket.CreatedAt).TotalSeconds
            }
        });
    }

    // ============================================
    // Event Broadcasting
    // ============================================

    private async Task BroadcastMatchFound(MatchFoundEvent evt)
    {
        var server = _sessionManager.GetServer(evt.ServerId);
        if (server == null) return;

        var message = new WsMessage
        {
            Type = "match_found",
            Data = new
            {
                TicketId = evt.TicketId,
                Server = new
                {
                    server.Id,
                    server.Host,
                    server.Port,
                    server.GameMode,
                    server.MapName
                }
            }
        };

        // Send to all players in the ticket
        foreach (var playerId in evt.PlayerIds)
        {
            var client = _clients.Values.FirstOrDefault(c => c.PlayerId == playerId);
            if (client != null)
            {
                await client.SendAsync(message);
            }
        }
    }

    private async Task BroadcastServerStatusChanged(ServerStatusChangedEvent evt)
    {
        // Broadcast to all connected clients (for server browser)
        var message = new WsMessage
        {
            Type = "server_status_changed",
            Data = new
            {
                evt.ServerId,
                OldStatus = evt.OldStatus.ToString(),
                NewStatus = evt.NewStatus.ToString()
            }
        };

        foreach (var client in _clients.Values)
        {
            await client.SendAsync(message);
        }
    }
}

/// <summary>
/// Represents a connected WebSocket client
/// </summary>
public class WebSocketClient
{
    public string Id { get; }
    public WebSocket WebSocket { get; }
    public string? SessionId { get; set; }
    public string? PlayerId { get; set; }
    public string? MatchmakingTicketId { get; set; }

    private readonly SemaphoreSlim _sendLock = new(1, 1);

    public WebSocketClient(string id, WebSocket webSocket)
    {
        Id = id;
        WebSocket = webSocket;
    }

    public async Task SendAsync(WsMessage message)
    {
        if (WebSocket.State != WebSocketState.Open)
            return;

        await _sendLock.WaitAsync();
        try
        {
            var json = JsonSerializer.Serialize(message, new JsonSerializerOptions
            {
                PropertyNamingPolicy = JsonNamingPolicy.CamelCase
            });
            var bytes = Encoding.UTF8.GetBytes(json);
            await WebSocket.SendAsync(bytes, WebSocketMessageType.Text, true, CancellationToken.None);
        }
        finally
        {
            _sendLock.Release();
        }
    }

    public async Task CloseAsync(string reason)
    {
        if (WebSocket.State == WebSocketState.Open)
        {
            await WebSocket.CloseAsync(WebSocketCloseStatus.NormalClosure, reason, CancellationToken.None);
        }
    }
}

/// <summary>
/// WebSocket message format
/// </summary>
public class WsMessage
{
    public string Type { get; set; } = "";
    public object? Data { get; set; }
}

// Message data classes
public class AuthenticateData
{
    public string PlayerId { get; set; } = "";
    public string? PlayerName { get; set; }
    public string? AuthToken { get; set; }
}

public class MatchmakingStartData
{
    public string? GameMode { get; set; }
    public string? PreferredRegion { get; set; }
}
