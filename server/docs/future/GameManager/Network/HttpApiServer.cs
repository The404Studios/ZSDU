using System.Net;
using System.Text;
using System.Text.Json;
using GameManager.Data;
using GameManager.Services;

namespace GameManager.Network;

/// <summary>
/// HTTP API Server for REST endpoints
/// Handles server registration, matchmaking, and status queries
/// </summary>
public class HttpApiServer
{
    private readonly HttpListener _listener;
    private readonly SessionManager _sessionManager;
    private readonly Matchmaker _matchmaker;
    private readonly Director _director;
    private readonly Configuration _config;
    private CancellationTokenSource? _cts;

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        WriteIndented = true
    };

    public HttpApiServer(
        SessionManager sessionManager,
        Matchmaker matchmaker,
        Director director,
        Configuration config)
    {
        _sessionManager = sessionManager;
        _matchmaker = matchmaker;
        _director = director;
        _config = config;
        _listener = new HttpListener();
    }

    /// <summary>
    /// Start the HTTP server
    /// </summary>
    public async Task StartAsync(CancellationToken ct)
    {
        _cts = CancellationTokenSource.CreateLinkedTokenSource(ct);

        var prefix = $"http://{_config.HttpHost}:{_config.HttpPort}/";
        _listener.Prefixes.Add(prefix);
        _listener.Start();

        Console.WriteLine($"[HTTP] Listening on {prefix}");

        while (!_cts.Token.IsCancellationRequested)
        {
            try
            {
                var context = await _listener.GetContextAsync();
                _ = HandleRequestAsync(context);
            }
            catch (HttpListenerException) when (_cts.Token.IsCancellationRequested)
            {
                break;
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[HTTP] Error: {ex.Message}");
            }
        }
    }

    /// <summary>
    /// Stop the HTTP server
    /// </summary>
    public void Stop()
    {
        _cts?.Cancel();
        _listener.Stop();
    }

    /// <summary>
    /// Handle an incoming HTTP request
    /// </summary>
    private async Task HandleRequestAsync(HttpListenerContext context)
    {
        var request = context.Request;
        var response = context.Response;

        try
        {
            var path = request.Url?.AbsolutePath ?? "/";
            var method = request.HttpMethod;

            Console.WriteLine($"[HTTP] {method} {path}");

            // CORS headers
            response.Headers.Add("Access-Control-Allow-Origin", "*");
            response.Headers.Add("Access-Control-Allow-Methods", "GET, POST, DELETE, OPTIONS");
            response.Headers.Add("Access-Control-Allow-Headers", "Content-Type, Authorization");

            if (method == "OPTIONS")
            {
                response.StatusCode = 204;
                response.Close();
                return;
            }

            object? result = (path, method) switch
            {
                // Status
                ("/health", "GET") => new { Status = "healthy" },
                ("/status", "GET") => GetStatus(),

                // Servers
                ("/api/servers", "GET") => GetServers(),
                ("/api/servers", "POST") => await RegisterServer(request),
                ("/api/servers/heartbeat", "POST") => await ProcessHeartbeat(request),
                var (p, "DELETE") when p.StartsWith("/api/servers/") =>
                    await UnregisterServer(p["/api/servers/".Length..]),

                // Sessions
                ("/api/sessions", "POST") => await CreateSession(request),
                var (p, "DELETE") when p.StartsWith("/api/sessions/") =>
                    await EndSession(p["/api/sessions/".Length..]),

                // Matchmaking
                ("/api/matchmaking", "POST") => await StartMatchmaking(request),
                var (p, "GET") when p.StartsWith("/api/matchmaking/") =>
                    GetMatchmakingStatus(p["/api/matchmaking/".Length..]),
                var (p, "DELETE") when p.StartsWith("/api/matchmaking/") =>
                    await CancelMatchmaking(p["/api/matchmaking/".Length..]),

                // Scaling
                ("/api/scaling/status", "GET") => _director.GetStatus(),
                ("/api/scaling/spawn", "POST") => await SpawnServer(),

                // Not found
                _ => null
            };

            if (result == null)
            {
                await SendJsonAsync(response, new { Error = "Not found" }, 404);
            }
            else
            {
                await SendJsonAsync(response, result);
            }
        }
        catch (Exception ex)
        {
            Console.WriteLine($"[HTTP] Request error: {ex.Message}");
            await SendJsonAsync(response, new { Error = ex.Message }, 500);
        }
    }

    // ============================================
    // API Handlers
    // ============================================

    private object GetStatus()
    {
        var servers = _sessionManager.GetAllServers().ToList();
        return new
        {
            ServerCount = servers.Count,
            TotalPlayers = servers.Sum(s => s.CurrentPlayers),
            TotalCapacity = servers.Sum(s => s.MaxPlayers),
            Scaling = _director.GetStatus()
        };
    }

    private object GetServers()
    {
        return _sessionManager.GetAllServers().Select(s => new
        {
            s.Id,
            s.Name,
            s.Host,
            s.Port,
            s.Status,
            s.CurrentPlayers,
            s.MaxPlayers,
            s.GameMode,
            s.MapName,
            s.Version,
            Available = s.IsAvailable
        });
    }

    private async Task<object> RegisterServer(HttpListenerRequest request)
    {
        var body = await ReadBodyAsync<ServerRegistration>(request);
        if (body == null)
            return new { Error = "Invalid request body" };

        var clientIp = request.RemoteEndPoint?.Address.ToString() ?? "unknown";
        var server = await _sessionManager.RegisterServerAsync(body, clientIp);

        return new { server.Id, Message = "Server registered" };
    }

    private async Task<object> ProcessHeartbeat(HttpListenerRequest request)
    {
        var body = await ReadBodyAsync<ServerHeartbeat>(request);
        if (body == null)
            return new { Error = "Invalid request body" };

        await _sessionManager.ProcessHeartbeatAsync(body);
        return new { Message = "OK" };
    }

    private async Task<object> UnregisterServer(string serverId)
    {
        await _sessionManager.UnregisterServerAsync(serverId, "api_unregister");
        return new { Message = "Server unregistered" };
    }

    private async Task<object> CreateSession(HttpListenerRequest request)
    {
        var body = await ReadBodyAsync<CreateSessionRequest>(request);
        if (body == null)
            return new { Error = "Invalid request body" };

        var session = await _sessionManager.CreatePlayerSessionAsync(body.PlayerId, body.PlayerName);
        return new { session.Id, session.PlayerId };
    }

    private async Task<object> EndSession(string sessionId)
    {
        await _sessionManager.EndPlayerSessionAsync(sessionId, "api_end");
        return new { Message = "Session ended" };
    }

    private async Task<object> StartMatchmaking(HttpListenerRequest request)
    {
        var body = await ReadBodyAsync<MatchRequest>(request);
        if (body == null)
            return new { Error = "Invalid request body" };

        var ticket = await _matchmaker.StartMatchmakingAsync(body);
        return new { ticket.Id, ticket.Status };
    }

    private object GetMatchmakingStatus(string ticketId)
    {
        var ticket = _matchmaker.GetTicket(ticketId);
        if (ticket == null)
            return new { Error = "Ticket not found" };

        var result = new
        {
            ticket.Id,
            ticket.Status,
            ticket.AssignedServerId,
            WaitTimeSeconds = (DateTime.UtcNow - ticket.CreatedAt).TotalSeconds
        };

        // If matched, include connection info
        if (ticket.Status == TicketStatus.Matched && ticket.AssignedServerId != null)
        {
            var server = _sessionManager.GetServer(ticket.AssignedServerId);
            if (server != null)
            {
                return new
                {
                    result.Id,
                    result.Status,
                    result.AssignedServerId,
                    result.WaitTimeSeconds,
                    Connection = new ConnectionInfo
                    {
                        ServerId = server.Id,
                        Host = server.Host,
                        Port = server.Port
                    }
                };
            }
        }

        return result;
    }

    private async Task<object> CancelMatchmaking(string ticketId)
    {
        await _matchmaker.CancelMatchmakingAsync(ticketId);
        return new { Message = "Matchmaking cancelled" };
    }

    private async Task<object> SpawnServer()
    {
        var serverId = await _director.SpawnGameServerAsync();
        if (serverId == null)
            return new { Error = "Failed to spawn server" };

        return new { ServerId = serverId, Message = "Server spawning" };
    }

    // ============================================
    // Helpers
    // ============================================

    private async Task<T?> ReadBodyAsync<T>(HttpListenerRequest request) where T : class
    {
        using var reader = new StreamReader(request.InputStream);
        var json = await reader.ReadToEndAsync();
        return JsonSerializer.Deserialize<T>(json, new JsonSerializerOptions
        {
            PropertyNameCaseInsensitive = true
        });
    }

    private async Task SendJsonAsync(HttpListenerResponse response, object data, int statusCode = 200)
    {
        response.StatusCode = statusCode;
        response.ContentType = "application/json";

        var json = JsonSerializer.Serialize(data, JsonOptions);
        var bytes = Encoding.UTF8.GetBytes(json);

        response.ContentLength64 = bytes.Length;
        await response.OutputStream.WriteAsync(bytes);
        response.Close();
    }
}

// Request DTOs
public class CreateSessionRequest
{
    public string PlayerId { get; set; } = "";
    public string PlayerName { get; set; } = "";
}
